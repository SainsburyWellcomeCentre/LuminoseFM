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
    'GUI.InitiationWindow',    'GUI.HoldWindow'};
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
