function [S, added] = mergeSettings(defaults, loaded)
% lum.mergeSettings brings a loaded settings struct up to date with the defaults.
%
% Settings files persist per subject and outlive the code that wrote them. When a
% new parameter is added to lum.defaultSettings, every existing settings file is
% missing it, and a protocol that reads it would fail on the first trial of the
% first animal of the day. Merging makes that a non-event: the new parameter appears
% with its default and the operator is told which ones were filled in.
%
% Three kinds of change need more than filling in:
%
%   Renamed    A setting that moved or was renamed would otherwise be filled in
%              from the default while the operator's value sat unused under the
%              old name. Values are moved to the new name first.
%   Reshaped   A setting whose shape changed (a scalar carrier that became one per
%              channel, a list of cue names that became rows) is converted.
%   Retired    A setting nothing reads any more is removed, and listed, so that a
%              stale value cannot be mistaken for a live one.
%
% Declarations are always taken from the defaults, never from the file: GUIMeta,
% GUIPanels and GUITabs, and the name lists Sync.ModeNames and
% Task.TrainingStageNames. They describe the code, not the animal, and an old file's
% copy would carry old labels and panels naming parameters that no longer exist.
%
% Any other field present in the loaded struct wins, including fields the defaults
% do not contain.
%
% Arguments:
%   defaults  Struct of defaults, from lum.defaultSettings
%   loaded    Struct loaded from the settings file; may be empty
%
% Returns:
%   S      The merged settings struct
%   added  Cell array describing what was filled in, converted or retired
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.defaultSettings

if nargin < 2 || isempty(loaded) || ~isstruct(loaded) || isempty(fieldnames(loaded))
    S = defaults;
    added = {'(all: settings file was empty)'};
    return
end

[loaded, migrated] = migrateLegacy(defaults, loaded);
[S, filled] = mergeStruct(defaults, loaded, '');
added = [migrated filled];

for name = {'GUIMeta', 'GUIPanels', 'GUITabs'}
    S.(name{1}) = defaults.(name{1});
end
S.Sync.ModeNames = defaults.Sync.ModeNames;
S.Task.TrainingStageNames = defaults.Task.TrainingStageNames;


function [loaded, migrated] = migrateLegacy(defaults, loaded)
% Convert settings written by earlier versions, so that the merge sees the current
% layout and the operator's own values survive it.
migrated = {};

%% Reshaped, under their old names (version 0.1)
% The carrier was one set of numbers for the whole rig until each optical channel
% got its own. Spread it across the channels, so a session pulsing at 20 Hz still
% pulses at 20 Hz on both after the upgrade.
if hasPath(loaded, 'Stimulus.Waveform') && isscalar(loaded.Stimulus.Waveform) ...
        && ~isfield(loaded.Stimulus.Waveform, 'Channel')
    old = loaded.Stimulus.Waveform;
    channels = defaults.Light.Carrier;
    for k = 1:numel(channels)
        channels(k).Channel = k;
        channels(k) = copyField(channels(k), old, 'Frequency', 1);
        channels(k) = copyField(channels(k), old, 'PulseWidth', 1);
        channels(k) = copyField(channels(k), old, 'Voltage', k);  % Was already per channel
    end
    loaded.Stimulus.Waveform = channels;
    migrated{end+1} = 'Light.Carrier (converted to one carrier per channel)';
end

% The sync pulse was a random width between a minimum and a maximum until the
% modes were added. Same distribution, written as a mean and a jitter.
if hasPath(loaded, 'Sync.MinDuration') && ~isfield(loaded.Sync, 'Mode')
    low = loaded.Sync.MinDuration;
    high = loaded.Sync.MaxDuration;
    loaded.Sync.Mode = lum.SyncMode.JitteredWidth;
    loaded.Sync.MeanDuration = (low + high) / 2;
    loaded.Sync.Jitter = (high - low) / 2;
    loaded.Sync.Duration = loaded.Sync.MeanDuration;
    loaded.Sync = rmfield(loaded.Sync, {'MinDuration', 'MaxDuration'});
    migrated{end+1} = 'Sync (min/max width rewritten as a mean and a jitter)';
end

% The cue was a list of component names sharing one duration until each component
% got its own timing. Convert the names into rows with the old shared duration; the
% version 0.4 conversion below then brings the rows up to date.
oldCueNames = struct('PortLight', 'CentreLight', 'Sound', 'Tone', 'Air', 'Air');
if hasPath(loaded, 'Cue.Components') && iscell(loaded.Cue.Components)
    chosen = renameAll(loaded.Cue.Components, oldCueNames);
    duration = 0.1;
    if isfield(loaded.Cue, 'Duration') && ~isempty(loaded.Cue.Duration)
        duration = loaded.Cue.Duration;
    end
    rows = defaults.Cue.Components;
    for k = 1:numel(rows)
        rows(k).Enabled = ismember(rows(k).Type, chosen);
        rows(k).Latency = 0;
        rows(k).Duration = duration;
    end
    loaded.Cue.Components = rows;
    loaded.Cue = removeFields(loaded.Cue, {'Duration'});
    migrated{end+1} = 'Cue.Components (given a latency and duration each)';
elseif hasPath(loaded, 'Cue.Components') && isfield(loaded.Cue.Components, 'Type')
    types = {loaded.Cue.Components.Type};
    renamed = renameAll(types, oldCueNames);
    if ~isequal(types, renamed)
        [loaded.Cue.Components.Type] = renamed{:};
        migrated{end+1} = 'Cue.Components (PortLight and Sound renamed CentreLight and Tone)';
    end
end

% The stimulus was a list of component names until each got its own timing, and the
% side-informative port light and tone moved to the Left and Right settings.
if hasPath(loaded, 'Stimulus.Components') && iscell(loaded.Stimulus.Components)
    chosen = loaded.Stimulus.Components;
    rows = defaults.Stimulus.Components;
    for k = 1:numel(rows)
        rows(k).Enabled = (strcmp(rows(k).Type, 'Air') && ismember('Air', chosen)) ...
                          || (strcmp(rows(k).Type, 'Tone') && ismember('Sound', chosen));
        rows(k).Duration = defaultsWindow(defaults, loaded);
    end
    loaded.Stimulus.Components = rows;
    if ismember('PortLight', chosen)
        loaded.Left.Light.Enabled = true;
        loaded.Right.Light.Enabled = true;
    end
    migrated{end+1} = 'Stimulus.Components (a row per component; port light moved to Left/Right)';
end

%% Renamed or moved (version 0.2)
renames = { ...
    'Meta.FiberBundle',        'Light.Bundle'; ...
    'Stimulus.Waveform',       'Light.Carrier'; ...
    'Cue.KeepCentrePortLit',   'Cue.CentreLightDuringHold'; ...
    'Sound.CueFrequency',      'Cue.ToneFrequency'; ...
    'Sound.ErrorDuration',     'Sound.NoiseDuration'; ...
    'Sound.StimulusFreqRange', 'Stimulus.ToneFrequencyRange'; ...
    'Sync.Duration',           'Sync.FixedWidth'; ...
    'Sync.MeanDuration',       'Sync.MeanWidth'; ...
    'Sync.Jitter',             'Sync.WidthJitter'; ...
    'GUI.StimulusOn',          'GUI.OptoOn'; ...
    'GUI.PortLEDIntensity',    'GUI.PortLightIntensity'; ...
    ... % Version 0.3: the window now runs from trial start across restarts of the stimulus
    'GUI.InitiationWindow',    'GUI.HoldWindow'; ...
    ... % Version 0.6.1: the house light is switched from the plots, at once, not per trial
    'GUI.HouseLight',          'Session.HouseLight'};
for i = 1:size(renames, 1)
    [oldPath, newPath] = renames{i, :};
    if hasPath(loaded, oldPath)
        if ~hasPath(loaded, newPath)
            loaded = setPath(loaded, newPath, getPath(loaded, oldPath));
        end
        loaded = removePath(loaded, oldPath);
        migrated{end+1} = sprintf('%s (was %s)', newPath, oldPath); %#ok<AGROW>
    end
end

%% Reshaped (version 0.4): the cue lasts until the poke
% Each cue row had a latency and a duration from trial start, and the centre light
% could be kept on through the hold. The cue now stays on until the animal pokes, and
% a row's Duration is how long it stays on after stimulus onset, so Latency has no
% meaning left. Each component keeps doing what it did during the stimulus: the centre
% light stays on through it if it was kept on through the hold, and goes off at the
% poke otherwise; the tone and air, which never lasted into the stimulus, go off at
% the poke.
if hasPath(loaded, 'Cue.Components') && isstruct(loaded.Cue.Components) ...
        && isfield(loaded.Cue.Components, 'Latency')
    rows = loaded.Cue.Components;
    keptOn = true;
    if isfield(loaded.Cue, 'CentreLightDuringHold')
        keptOn = logical(loaded.Cue.CentreLightDuringHold);
    end
    converted = struct('Type', {rows.Type}, 'Enabled', {rows.Enabled}, ...
                       'ThroughStimulus', false, 'Duration', 0);
    for k = 1:numel(converted)
        converted(k).ThroughStimulus = strcmp(converted(k).Type, 'CentreLight') && keptOn;
    end
    loaded.Cue.Components = converted;
    migrated{end+1} = ['Cue.Components (the cue now lasts until the poke; Duration counts '...
                       'from stimulus onset)'];
end
if hasPath(loaded, 'Cue.CentreLightDuringHold')
    loaded = removePath(loaded, 'Cue.CentreLightDuringHold');
    migrated{end+1} = 'Cue.CentreLightDuringHold (retired: each cue row says how long it stays on)';
end

%% Reshaped (version 0.6): automatic shaping is a switch of its own
% Hold shaping was one choice, Off or a way of shaping. It is now a switch,
% Task.AutoShaping, and the way it shapes, Task.HoldShaping, which has no Off. A file
% that shaped keeps shaping the same way; one that did not gets the switch off and the
% default way, ready for when it is switched on.
if hasPath(loaded, 'Task.HoldShaping') && ~hasPath(loaded, 'Task.AutoShaping')
    old = loaded.Task.HoldShaping;
    shaped = ischar(old) && ismember(old, lum.HoldShaping.modes());
    loaded.Task.AutoShaping = shaped;
    if ~shaped
        loaded.Task.HoldShaping = defaults.Task.HoldShaping;
    end
    migrated{end+1} = sprintf('Task.AutoShaping (%s, from hold shaping ''%s'')', ...
                              onOffText(shaped), char(string(old)));
end

%% Reshaped (version 0.7.2): the 2-to-19 bundle's cables are named by colour
% Its cables were fixed ('ch1 fiber' on A, 'ch2 fiber' on B) and S.Light.Cables was read
% only for the 4-to-19 bundle, so a 2-to-19 file holds a 4-to-19 pair or the old names.
% Its cables are now blue and green, either on either channel; such a file gets the
% bundle's defaults, blue on A and green on B.
if hasPath(loaded, 'Light.Bundle') && strcmp(loaded.Light.Bundle, '2-to-19')
    bundles = lum.fiberBundles();
    bundle = bundles(strcmp({bundles.Name}, '2-to-19'));
    cables = {};
    if hasPath(loaded, 'Light.Cables')
        cables = loaded.Light.Cables;
    end
    if ~iscell(cables) || numel(cables) ~= 2 || ~all(ismember(cables, bundle.Cables)) ...
            || strcmp(cables{1}, cables{2})
        loaded.Light.Cables = bundle.Defaults;
        migrated{end+1} = sprintf(['Light.Cables (the 2-to-19 bundle''s cables are named by '...
                                   'colour: %s on A, %s on B)'], bundle.Defaults{:});
    end
end

%% Reshaped (version 0.9.0): stimulus families that say what the animal tells apart
% The families were redesigned around the question each asks (docs/stimulus_family.md).
% A generator holding any field of the old families is converted: pure and hand-drawn
% keep their meaning; the sequence motif becomes two words, the motif and its mirror;
% the overlap order becomes the order family's guarded cycle and the tiled order its
% simple design with no overlap; occupancy has no counterpart and becomes the mixture
% family at its defaults. P(left) is kept only where the groups are still the same ones.
if hasPath(loaded, 'Stimulus.Generator') && isstruct(loaded.Stimulus.Generator) ...
        && isscalar(loaded.Stimulus.Generator) ...
        && any(isfield(loaded.Stimulus.Generator, retiredGeneratorFields()))
    [loaded, note] = migrateGenerator(defaults, loaded);
    migrated{end+1} = note;
end

%% Replaced default (version 0.9.2): test pulses one channel at a time, all recording long
% Up to 0.9.1 the default schedule sent paired probes on A and B together every 2 s for
% 240 min. A file still holding exactly that schedule was never designed by anyone, so it
% takes the new default: probes alternating between A and B every 30 s until the
% recording ends. A schedule that differs in any way is the operator's, and is kept.
if hasPath(loaded, 'Sleep.TestPulses.Schedule') && hasPath(loaded, 'Sleep.TestPulses.Probe') ...
        && isstruct(loaded.Sleep.TestPulses.Schedule) && isscalar(loaded.Sleep.TestPulses.Schedule) ...
        && isequal(loaded.Sleep.TestPulses.Schedule, ...
                   struct('Kind', 'Probe', 'Channels', 'A and B', 'Minutes', 240)) ...
        && isfield(loaded.Sleep.TestPulses.Probe, 'InterEpochInterval') ...
        && isequal(loaded.Sleep.TestPulses.Probe.InterEpochInterval, 2)
    loaded.Sleep.TestPulses.Schedule = defaults.Sleep.TestPulses.Schedule;
    loaded.Sleep.TestPulses.Probe.InterEpochInterval = defaults.Sleep.TestPulses.Probe.InterEpochInterval;
    migrated{end+1} = ['Sleep.TestPulses (the old default schedule, probes on A and B every 2 s for '...
                       '240 min, became the new one: alternating A and B every 30 s, all recording long)'];
end

%% Replaced default (version 0.9.3): the LED current limit is the LED's rating
% Up to 0.9.2 each channel's limit was 700 mA by default, Doric's recommended current for
% an LED held on; the rating is 1000 mA, and the light here is gated. A file from before
% 0.9.3 (it has no Doric.CalibrationCurrentsmA) whose limit is still 700 mA on a channel
% takes 1000 mA there. Any other limit is the operator's, and is kept; so is 700 mA typed
% again from 0.9.3 on.
if hasPath(loaded, 'Doric.MaxCurrentmA') && ~hasPath(loaded, 'Doric.CalibrationCurrentsmA') ...
        && isnumeric(loaded.Doric.MaxCurrentmA) && any(loaded.Doric.MaxCurrentmA(:) == 700)
    loaded.Doric.MaxCurrentmA(loaded.Doric.MaxCurrentmA == 700) = 1000;
    migrated{end+1} = ['Doric.MaxCurrentmA (the old default limit, 700 mA, became the new one: '...
                       '1000 mA, the LED''s rating)'];
end

%% Replaced default (version 0.9.6): the views checked against the cameras
% Up to 0.9.5 the defaults named 24226887 sideview and 24226657 topview, never checked
% against the pictures; the operator found them the other way round (2026-09-25). A file from
% before 0.9.6 (it has no Camera.Crops) holding exactly that pairing takes the checked one.
% Any other naming is the operator's, and is kept; so is the old pairing typed from 0.9.6 on.
if hasPath(loaded, 'Camera.Cameras') && ~hasPath(loaded, 'Camera.Crops') ...
        && isstruct(loaded.Camera.Cameras) && all(isfield(loaded.Camera.Cameras, {'Serial', 'Name'}))
    rows = loaded.Camera.Cameras;
    serials = arrayfun(@(row) strtrim(char(row.Serial)), rows, 'UniformOutput', false);
    names = arrayfun(@(row) strtrim(char(row.Name)), rows, 'UniformOutput', false);
    side = strcmp(serials, '24226887') & strcmp(names, 'sideview');
    top = strcmp(serials, '24226657') & strcmp(names, 'topview');
    if any(side) && any(top) && numel(rows) == 2
        loaded.Camera.Cameras(side).Name = 'topview';
        loaded.Camera.Cameras(top).Name = 'sideview';
        migrated{end+1} = ['Camera.Cameras (the old default views, 24226887 sideview and 24226657 '...
                           'topview, became the checked ones: 24226887 topview, 24226657 sideview)'];
    end
end

%% Reshaped (version 0.9.6): crops are kept per session type
% Up to 0.9.5 one crop per camera (Camera.Cameras(k).Roi) served every session type, so a
% crop drawn for the behaviour box also cropped the home cage. Each type now keeps its own
% (Camera.Crops). A file's crops were drawn for the last session it ran, so they are kept
% for that session type only.
if hasPath(loaded, 'Camera.Cameras') && ~hasPath(loaded, 'Camera.Crops') ...
        && isstruct(loaded.Camera.Cameras) && isfield(loaded.Camera.Cameras, 'Roi') ...
        && any(arrayfun(@(row) ~isempty(row.Roi), loaded.Camera.Cameras))
    kind = 'Behaviour';
    if hasPath(loaded, 'Session.Type')
        kind = lum.dev.Cameras.cropKind(loaded.Session.Type);
    end
    loaded.Camera.Crops = lum.dev.Cameras.noCrops();
    loaded.Camera = lum.dev.Cameras.keepCrop(loaded.Camera, kind);
    migrated{end+1} = sprintf('Camera.Crops (the crops in the file kept for %s sessions only)', ...
                              lum.gui.Form.sessionLabel(kind, true));
end

%% Retired (version 0.2, and 0.4)
% The hand-written stimulus table was replaced by the stimulus generator; its rows
% cannot be converted into generator parameters, so the defaults are used instead.
% Version 0.4 starts the stimulus on the poke, so the pre-stimulus hold is gone.
retired = {'Meta.Experimenter', 'Meta.Rig', 'Sound.CueDuration', 'Stimulus.Patterns', ...
           'Task.StimulusNames', 'Task.LeftProbability', 'Task.StimulusWeights', ...
           'GUI.PreStimulusHold'};
for i = 1:numel(retired)
    if hasPath(loaded, retired{i})
        loaded = removePath(loaded, retired{i});
        migrated{end+1} = sprintf('%s (retired)', retired{i}); %#ok<AGROW>
    end
end


function names = retiredGeneratorFields()
% Generator fields of the families before 0.9.0.
names = {'PureChannel', 'OnFraction', 'Motif', 'DutyCycle', 'SlotWeights', 'NumCycles', ...
         'BPhase', 'AOnFraction', 'BOnFraction', 'Overlap', 'Beta', 'Layout', 'BlockOrder', ...
         'CycleBins', 'PureWidth', 'ShortGuard', 'Phase'};


function [loaded, note] = migrateGenerator(defaults, loaded)
% A generator from before 0.9.0 in the current families' terms.
old = lum.pattern.withGeneratorDefaults(struct());
old = mergeFields(old, loaded.Stimulus.Generator);  % Every field, the file's winning
g = removeFields(loaded.Stimulus.Generator, retiredGeneratorFields());
g = lum.pattern.withGeneratorDefaults(g);
family = lower(char(old.Family));
nGroups = oldValue(old, 'nGroups', 2);
duration = defaultsWindow(defaults, loaded);
nBins = max(1, round(duration / old.BinDuration));
keepPLeft = true;
switch family
    case 'pure'
        channel = upper(char(oldValue(old, 'PureChannel', 'A')));
        if nGroups == 1 && ismember(channel, {'A', 'B'})
            g.PureChannels = channel;
        else
            g.PureChannels = 'A and B';
        end
        g.PureFractions = unique(oldValue(old, 'OnFraction', 1), 'stable');
        keepPLeft = nGroups <= 2 && isscalar(g.PureFractions);
        g.Continuous = false;
        what = 'pure channel, as before';
    case 'sequence'
        g.Family = 'motif';
        letters = '-ABX';
        motif = oldValue(old, 'Motif', [1 2]);
        cycles = oldValue(old, 'NumCycles', 1);
        duty = oldValue(old, 'DutyCycle', 1);
        if nGroups <= 2 && ~isequal(logical(old.Continuous), true) && all(ismember(motif, 0:3))
            word = repmat(letters(motif + 1), 1, cycles);
            mirror = word;
            mirror(word == 'A') = 'B';
            mirror(word == 'B') = 'A';
            g.MotifLeftWords = word;
            g.MotifRightWords = '';
            if nGroups == 2
                g.MotifRightWords = mirror;
            end
            g.MotifFill = min(1, max(0.01, mean(duty)));
            what = sprintf('sequence motif as the motif family: %s against %s', word, mirror);
        else
            g = lum.pattern.familyDefaults(g, 'motif');
            keepPLeft = false;
            what = 'sequence motif swept over groups: motif family at its defaults';
        end
        g.Continuous = false;
    case 'occupancy'
        g = lum.pattern.familyDefaults(g, 'mixture');
        g.MixtureLayout = 'onset';   % One stretch per channel: two timers on any machine
        keepPLeft = false;
        what = 'occupancy retired: mixture family at its defaults, lit from onset';
    case 'overlap_order'
        g.Family = 'order';
        g.OrderDesign = 'guarded';
        cycleBins = oldValue(old, 'CycleBins', 10);
        short = oldValue(old, 'ShortGuard', 1) / cycleBins;
        long = (cycleBins - 2 * oldValue(old, 'PureWidth', 2) - oldValue(old, 'ShortGuard', 1)) ...
               / cycleBins;
        g.OrderCycles = max(1, round(nBins / cycleBins));
        if short > 0 && long > short && short + long < 1
            g.OrderShortOverlap = short;
            g.OrderLongOverlap = long;
        end
        keepPLeft = nGroups <= 2 || isequal(logical(old.Continuous), true);
        what = 'overlap order as the order family''s guarded cycle';
    case 'tiled_order'
        g.Family = 'order';
        g.OrderDesign = 'simple';
        g.OrderCycles = 1;
        g.OrderOverlap = 0;
        g.Continuous = false;
        keepPLeft = nGroups <= 2;
        what = 'tiled order as the order family, no overlap';
    otherwise
        what = 'hand-drawn pulses, as before';
end
loaded.Stimulus.Generator = g;
if ~keepPLeft && hasPath(loaded, 'Task.GroupPLeft')
    loaded.Task.GroupPLeft = [];
    what = [what '; P(left) from the family'];
end
note = sprintf('Stimulus.Generator (stimulus families redesigned in 0.9.0: %s)', what);


function value = oldValue(old, name, default)
% A field of an old generator, or its default where the file has none or an empty one.
value = default;
if isfield(old, name) && ~isempty(old.(name))
    value = old.(name);
end


function target = mergeFields(target, source)
% Copy every field of source into target.
names = fieldnames(source);
for i = 1:numel(names)
    target.(names{i}) = source.(names{i});
end


function text = onOffText(tf)
% 'on' or 'off'.
if tf
    text = 'on';
else
    text = 'off';
end


function duration = defaultsWindow(defaults, loaded)
% The stimulus window the loaded file used, or the default one.
duration = defaults.Stimulus.Duration;
if hasPath(loaded, 'Stimulus.Duration')
    duration = loaded.Stimulus.Duration;
end


function names = renameAll(names, map)
% Replace each name that the map renames.
for i = 1:numel(names)
    if isfield(map, names{i})
        names{i} = map.(names{i});
    end
end


function target = copyField(target, source, name, index)
% Copy one legacy field across, taking element `index` if it held a vector.
if ~isfield(source, name) || isempty(source.(name))
    return
end
value = source.(name);
target.(name) = value(min(index, numel(value)));


function s = removeFields(s, names)
% rmfield that ignores fields that are not there.
present = names(isfield(s, names));
if ~isempty(present)
    s = rmfield(s, present);
end


function tf = hasPath(s, path)
% True if the dotted path exists in s, through scalar structs.
parts = strsplit(path, '.');
tf = true;
for i = 1:numel(parts)
    if ~isstruct(s) || ~isscalar(s) || ~isfield(s, parts{i})
        tf = false;
        return
    end
    s = s.(parts{i});
end


function value = getPath(s, path)
% The value at a dotted path that exists.
parts = strsplit(path, '.');
value = s;
for i = 1:numel(parts)
    value = value.(parts{i});
end


function s = setPath(s, path, value)
% Set a dotted path, creating the scalar structs along the way.
s = setParts(s, strsplit(path, '.'), value);


function s = setParts(s, parts, value)
% setPath, one level at a time.
if isscalar(parts)
    s.(parts{1}) = value;
    return
end
if ~isfield(s, parts{1}) || ~isstruct(s.(parts{1}))
    s.(parts{1}) = struct();
end
s.(parts{1}) = setParts(s.(parts{1}), parts(2:end), value);


function s = removePath(s, path)
% Remove the last field of a dotted path that exists.
s = removeParts(s, strsplit(path, '.'));


function s = removeParts(s, parts)
% removePath, one level at a time.
if isscalar(parts)
    s = rmfield(s, parts{1});
    return
end
s.(parts{1}) = removeParts(s.(parts{1}), parts(2:end));


function [out, added] = mergeStruct(defaults, loaded, prefix)
% Recursively copy defaults into loaded wherever loaded has nothing to say.
out = loaded;
added = {};
fields = fieldnames(defaults);
for i = 1:numel(fields)
    name = fields{i};
    dotted = [prefix name];
    if ~isfield(out, name)
        out.(name) = defaults.(name);
        added{end+1} = dotted; %#ok<AGROW>
    elseif isstruct(defaults.(name)) && isstruct(out.(name)) ...
            && isscalar(defaults.(name)) && isscalar(out.(name))
        % Recurse into nested settings groups, but not into struct arrays such as
        % S.Cue.Components, where the loaded array is the operator's own design and
        % must be taken whole.
        [out.(name), nested] = mergeStruct(defaults.(name), out.(name), [dotted '.']);
        added = [added nested]; %#ok<AGROW>
    end
end
