function [S, accepted, app] = SetupDialog(S, rig, varargin)
% lum.gui.SetupDialog collects everything the operator sets before a session runs.
%
% This is the pre-session half of architecture decision D2. The runtime window is a
% good fit for scalars that may change with an animal in the box, but it has no
% representation for a stimulus set or a per-channel carrier, and every field it
% owns stays editable for the whole session — which is wrong for parameters that have
% to be constant for the data to mean anything. So the pre-session tier gets this
% dialog, and the split between the tiers is structural rather than a rule the
% operator has to remember. The runtime tier is editable here too, so a session never
% starts with the reward volume at a default nobody chose.
%
% Tabs, in the order a session is usually set up:
%
%   Experiment  The animal (subject, genotype), what else is recorded or given in
%               this session (Neuropixels, EEG/EMG, a drug), length, devices, notes
%   Task        Training stage, trial order, the centre hold and its shaping, which
%               components make up the cue, the stimulus and each side, and the trial
%               timeline
%   Cue         Whether each cue component continues through the stimulus, or how
%               long it stays on into it; the cue tone, sound output, and a timeline
%               of the cue against the stimulus
%   Stimulus    The stimulus window and its latency from the poke; the light patterns
%               and trial order (the stimulus designer opens from
%               here), P(left) per group, every trial of the session to scroll
%               through, and the timing of the other stimulus components
%   Light path  The fiber bundle and its cables, and each channel's carrier
%   Left/Right  Side port light, side tone and guide light for each side
%   Sync        Trial sync pulses and the session barcode
%   Runtime     Starting values of the runtime tier
%
% Ticking a component on the Task tab is what switches it on: its rows light up on
% the tab that times it, and that tab's title counts it. Everything is validated on
% every edit by lum.validateSettings, and Start stays disabled while anything fails.
%
% Arguments:
%   S    Settings struct, from the launch manager's settings file
%   rig  Channel map from RigConfig; supplies the timer budget and channel count
%
% Options:
%   'Subject'  The subject chosen in the launch manager
%   'Wait'     false to return at once with the dialog open (for tests); default true
%   'Visible'  'on' (default) or 'off'
%
% Returns:
%   S         The edited settings
%   accepted  True if the operator started the session, false if they cancelled
%   app       With 'Wait' false: .Figure, .collect(), .refresh(), .start(),
%             .cancel(), .status() and .controls
%
% See also: lum.defaultSettings, lum.validateSettings, lum.gui.StimulusDesigner,
%           lum.gui.RuntimeWindow

p = inputParser;
p.FunctionName = 'lum.gui.SetupDialog';
addParameter(p, 'Subject', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'Wait', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'Visible', 'on');
parse(p, varargin{:});
if strlength(string(p.Results.Subject)) > 0
    S.Meta.Subject = char(p.Results.Subject);
end

accepted = false;
t = lum.gui.theme();
choices = lum.experimentChoices();
runtime = lum.gui.runtimeFields(S);

% Compiling the stimulus set is the slow part of validation, and most edits do not
% touch it, so the last set is kept with the settings it came from. Diagrams are
% redrawn only when what they show has changed.
cachedSet = [];
cachedKey = {};
drawnKeys = struct('Flow', {{}}, 'Cue', {{}}, 'Barcode', {{}}, 'Browser', {{}});

fig = uifigure('Name', 'LuminoseFM - session setup', 'Position', [40 40 1280 850], ...
               'Color', t.Background, 'Visible', p.Results.Visible);
outer = uigridlayout(fig, [4 1], 'RowHeight', {58, '1x', 'fit', 34}, ...
                     'Padding', [14 10 14 12], 'RowSpacing', 8, 'BackgroundColor', t.Background);
buildHeader(outer, S, rig, t);
tabGroup = uitabgroup(outer);

controls = struct();
controls = buildExperimentTab(tabGroup, S, controls, choices, t, @refresh);
controls = buildTaskTab(tabGroup, S, controls, runtime, t, @refresh);
controls = buildCueTab(tabGroup, S, controls, t, @refresh);
controls = buildStimulusTab(tabGroup, S, controls, t, @refresh, @openDesigner, @newTrialOrder);
controls = buildLightPathTab(tabGroup, S, controls, t, @refresh);
controls = buildSideTab(tabGroup, S, 'Left', controls, choices, t, @refresh);
controls = buildSideTab(tabGroup, S, 'Right', controls, choices, t, @refresh);
controls = buildSyncTab(tabGroup, S, controls, t, @refresh);
controls = buildRuntimeTab(tabGroup, runtime, controls, t, @refresh);

controls.Status = uilabel(outer, 'Text', '', 'WordWrap', 'on', 'FontSize', 12);
footer = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 110, 150}, 'Padding', 0, ...
                      'ColumnSpacing', 8, 'BackgroundColor', t.Background);
uilabel(footer, 'Text', sprintf('%s  |  %d global timers, %d conditions', rig.MachineModel, ...
                                rig.Limits.GlobalTimers, rig.Limits.Conditions), ...
        'FontColor', t.Muted, 'FontSize', 11);
uibutton(footer, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
controls.Start = uibutton(footer, 'Text', 'Start session', 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Accent, 'FontColor', [1 1 1], ...
                          'ButtonPushedFcn', @(~, ~) onStart());

% The trial timeline is laid out in the pixels its axes have, so it is drawn once the
% layout exists, and again whenever the window changes size or the Task tab is shown
% (axes on a hidden tab report a size they do not have yet).
drawnow;
fig.AutoResizeChildren = 'off';
fig.SizeChangedFcn = @(~, ~) onResize();
tabGroup.SelectionChangedFcn = @(~, ~) refresh();
refresh();
app = struct('Figure', fig, 'collect', @collectSettings, 'refresh', @refresh, ...
             'start', @onStart, 'cancel', @onCancel, 'status', @statusText, ...
             'controls', controls);
if p.Results.Wait
    uiwait(fig);
end


    function onResize()
        drawnKeys.Flow = {};
        refresh();
    end

    function onCancel()
        accepted = false;
        if isvalid(fig)
            delete(fig);
        end
    end

    function [ok, candidate] = onStart()
        ok = false;
        candidate = S;
        try
            candidate = collectSettings();
            lum.validateSettings(candidate, rig);
        catch settingsError
            setStatus(settingsError.message, false);
            uialert(fig, settingsError.message, 'Settings not usable');
            return
        end
        S = candidate;
        accepted = true;
        ok = true;
        delete(fig);
    end

    function text = statusText()
        text = controls.Status.Text;
    end

    function openDesigner()
        % The designer edits the generator, the window and P(left); everything else
        % stays as the dialog has it.
        try
            candidate = collectSettings();
        catch readError
            uialert(fig, readError.message, 'Settings not usable');
            return
        end
        [designed, ok] = lum.gui.StimulusDesigner(candidate, rig);
        if ~ok || ~isvalid(fig)
            return
        end
        S.Stimulus.Generator = designed.Stimulus.Generator;
        controls.StimulusDuration.Value = designed.Stimulus.Duration;
        setGroupTable(controls.GroupTable, designed.Task.GroupPLeft);
        refresh();
    end

    function newTrialOrder()
        S.Stimulus.Generator.Seed = lum.pattern.newSeed();
        refresh();
    end

    function refresh()
        % Read every control, bring the dialog's appearance in line with it, and
        % validate the lot.
        try
            candidate = collectSettings();
        catch readError
            setStatus(readError.message, false);
            return
        end
        updateAppearance(candidate);
        try
            key = setKey(candidate, rig);
            if isequal(key, cachedKey)
                [stimulusSet, budget, notes] = lum.validateSettings(candidate, rig, cachedSet);
            else
                [stimulusSet, budget, notes] = lum.validateSettings(candidate, rig);
                cachedSet = stimulusSet;
                cachedKey = key;
            end
        catch validationError
            setStatus(validationError.message, false);
            return
        end
        showStimulusSet(stimulusSet);
        message = sprintf(['Ready to start: %d group(s) over %d trials; the busiest pattern '...
                           'uses %d of the %d global timers left for light.'], ...
                          stimulusSet.nGroups, stimulusSet.nTrials, max([0 stimulusSet.nTimers]), ...
                          budget);
        if ~isempty(notes)
            message = sprintf('%s  Note: %s', message, strjoin(notes, ' '));
        end
        setStatus(message, true);
    end

    function setStatus(message, isGood)
        controls.Status.Text = message;
        if isGood
            controls.Status.FontColor = t.Good;
        else
            controls.Status.FontColor = t.Bad;
        end
        controls.Start.Enable = onOff(isGood);
    end

    function candidate = collectSettings()
        % Read every control back into a settings struct. Fields no control shows —
        % the generator, which only the designer edits — come from S.
        c = controls;
        candidate = S;

        candidate.Meta = lum.gui.ExperimentForm.read(c, candidate.Meta);

        candidate.Session.Type = 'Behaviour';
        candidate.Session.MaxTrials = round(c.MaxTrials.Value);
        candidate.Session.SaveEveryNTrials = round(c.SaveEveryNTrials.Value);
        candidate.Session.UseOpto = c.UseOpto.Value;
        candidate.Session.UseSound = c.UseSound.Value;
        candidate.Session.UseSync = c.UseSync.Value;
        candidate.Session.ShowAnalogViewer = c.ShowAnalogViewer.Value;
        candidate.Session.RuntimeWindow = c.RuntimeWindow.Value;

        candidate.Task.TrainingStage = find(strcmp(c.TrainingStage.Value, ...
                                                   S.Task.TrainingStageNames), 1);
        candidate.Task.MaxSameSide = round(c.MaxSameSide.Value);
        candidate.Task.HoldShaping = c.HoldShaping.Value;
        candidate.Task.OnHoldBreak = c.OnHoldBreak.Value;
        candidate.Task.GroupPLeft = readPLeft(c.GroupTable.Data);

        for k = 1:numel(candidate.Cue.Components)
            candidate.Cue.Components(k).Enabled = c.CueEnabled(k).Value;
            candidate.Cue.Components(k).ThroughStimulus = c.CueThrough(k).Value;
            candidate.Cue.Components(k).Duration = c.CueDuration(k).Value;
        end
        candidate.Cue.ToneFrequency = c.CueToneFrequency.Value;

        candidate.Stimulus.Duration = c.StimulusDuration.Value;
        candidate.Stimulus.Latency = c.StimulusLatency.Value;
        for k = 1:numel(candidate.Stimulus.Components)
            candidate.Stimulus.Components(k).Enabled = c.StimulusEnabled(k).Value;
            candidate.Stimulus.Components(k).Onset = c.StimulusOnset(k).Value;
            candidate.Stimulus.Components(k).Duration = c.StimulusLength(k).Value;
        end
        candidate.Stimulus.ToneFrequencyRange = [c.ToneLow.Value, c.ToneHigh.Value];

        for side = {'Left', 'Right'}
            s = c.(side{1});
            candidate.(side{1}).Light = struct('Enabled', s.LightEnabled.Value, ...
                'Onset', s.LightOnset.Value, 'Duration', s.LightDuration.Value);
            candidate.(side{1}).Tone = struct('Enabled', s.ToneEnabled.Value, ...
                'Frequency', s.ToneFrequency.Value, 'Onset', s.ToneOnset.Value, ...
                'Duration', s.ToneDuration.Value);
            candidate.(side{1}).GuideLight = s.GuideLight.Value;
        end

        % Cables are the operator's choice only on a bundle that has more than two;
        % the 2-to-19 bundle's fixed fibers leave the recorded choice as it was.
        candidate.Light.Bundle = c.Bundle.Value;
        bundles = lum.fiberBundles();
        bundle = bundles(strcmp({bundles.Name}, c.Bundle.Value));
        if ~isempty(bundle) && bundle.Choose
            candidate.Light.Cables = {c.CableA.Value, c.CableB.Value};
        end
        candidate.Light.Carrier = struct('Channel', {1, 2}, ...
            'Frequency', {c.Frequency(1).Value, c.Frequency(2).Value}, ...
            'PulseWidth', {c.PulseWidth(1).Value, c.PulseWidth(2).Value}, ...
            'Voltage', {c.Voltage(1).Value, c.Voltage(2).Value});

        candidate.Sound.Amplitude = c.SoundAmplitude.Value;
        candidate.Sound.Attenuation_dB = c.Attenuation.Value;
        candidate.Sound.NoiseDuration = c.NoiseDuration.Value;

        candidate.Sync.Mode = find(strcmp(c.SyncMode.Value, S.Sync.ModeNames), 1);
        candidate.Sync.FixedWidth = c.SyncFixed.Value;
        candidate.Sync.MeanWidth = c.SyncMean.Value;
        candidate.Sync.WidthJitter = c.SyncJitter.Value;
        candidate.Sync.Barcode = struct('Enabled', c.BarcodeEnabled.Value, ...
            'nBits', round(c.BarcodeBits.Value), 'MarkerWidth', c.BarcodeMarker.Value, ...
            'ZeroWidth', c.BarcodeZero.Value, 'OneWidth', c.BarcodeOne.Value, ...
            'Gap', c.BarcodeGap.Value, 'SleepMarkerWidth', c.BarcodeSleepMarker.Value);

        candidate.GUI = readRuntime(c.Runtime, runtime, candidate.GUI);
    end

    function updateAppearance(candidate)
        % Chips, enables, tab titles, notes and diagrams follow the settings.
        c = controls;
        c.StageNote.Text = lum.trainingStageNote(candidate);
        c.ShapingNote.Text = sprintf('%s %s', lum.HoldShaping.describeBreak(candidate), ...
                                     lum.HoldShaping.describe(candidate));
        c.HoldNote.Text = lum.HoldShaping.describeHold(candidate);
        setEnable(runtimeHandles(c.Runtime, {'HoldStart', 'HoldGrowth', 'HoldTarget'}), ...
                  lum.HoldShaping.growsHold(candidate.Task.HoldShaping));
        setEnable(runtimeHandles(c.Runtime, {'GraceStart', 'GraceShrink', 'GraceTarget'}), ...
                  lum.HoldShaping.hasGrace(candidate.Task.HoldShaping));

        lum.gui.ExperimentForm.update(c, candidate.Meta);

        cue = candidate.Cue.Components;
        for k = 1:numel(cue)
            setChip(c.CueChip(k), cue(k).Enabled, t);
            setEnable({c.CueThrough(k)}, cue(k).Enabled);
            setEnable({c.CueDuration(k)}, cue(k).Enabled && ~cue(k).ThroughStimulus);
        end
        cueTone = cue(strcmp({cue.Type}, 'Tone'));
        setEnable({c.CueToneFrequency}, ~isempty(cueTone) && cueTone.Enabled);

        stimulus = candidate.Stimulus.Components;
        setChip(c.OptoChip, candidate.Session.UseOpto, t);
        for k = 1:numel(stimulus)
            setChip(c.StimulusChip(k), stimulus(k).Enabled, t);
            setEnable({c.StimulusOnset(k), c.StimulusLength(k)}, stimulus(k).Enabled);
        end
        stimulusTone = stimulus(strcmp({stimulus.Type}, 'Tone'));
        setEnable({c.ToneLow, c.ToneHigh}, ~isempty(stimulusTone) && stimulusTone.Enabled);

        nSide = zeros(1, 2);
        sides = {'Left', 'Right'};
        for i = 1:2
            s = c.(sides{i});
            light = candidate.(sides{i}).Light;
            sideTone = candidate.(sides{i}).Tone;
            setChip(s.LightChip, light.Enabled, t);
            setEnable({s.LightOnset, s.LightDuration}, light.Enabled);
            setChip(s.ToneChip, sideTone.Enabled, t);
            setEnable({s.ToneFrequency, s.ToneOnset, s.ToneDuration}, sideTone.Enabled);
            nSide(i) = light.Enabled + sideTone.Enabled;
        end

        c.Tabs.Cue.Title = countedTitle('Cue', sum([cue.Enabled]));
        c.Tabs.Stimulus.Title = countedTitle('Stimulus', ...
                                             candidate.Session.UseOpto + sum([stimulus.Enabled]));
        c.Tabs.Left.Title = countedTitle('Left', nSide(1));
        c.Tabs.Right.Title = countedTitle('Right', nSide(2));

        bundles = lum.fiberBundles();
        bundle = bundles(strcmp({bundles.Name}, candidate.Light.Bundle));
        setEnable({c.CableA, c.CableB}, ~isempty(bundle) && bundle.Choose);
        c.BundleNote.Text = bundleNote(candidate, bundles);

        mode = candidate.Sync.Mode;
        setEnable({c.SyncFixed}, mode == lum.SyncMode.FixedWidth);
        setEnable({c.SyncMean, c.SyncJitter}, mode == lum.SyncMode.JitteredWidth);
        c.SyncNote.Text = syncNote(mode);
        setEnable({c.BarcodeBits, c.BarcodeMarker, c.BarcodeSleepMarker, c.BarcodeZero, ...
                   c.BarcodeOne, c.BarcodeGap}, candidate.Sync.Barcode.Enabled);

        flowKey = {candidate.Cue.Components, candidate.Stimulus.Duration, ...
                   candidate.Stimulus.Latency, candidate.GUI, ...
                   candidate.Task.HoldShaping, candidate.Task.OnHoldBreak, ...
                   round(c.FlowAxes.InnerPosition(3))};
        if ~isequal(flowKey, drawnKeys.Flow)
            lum.gui.drawTrialFlow(c.FlowAxes, candidate);
            drawnKeys.Flow = flowKey;
        end
        cueKey = {candidate.Cue.Components, candidate.Stimulus.Duration, ...
                  candidate.Stimulus.Latency, candidate.GUI.PostStimulusHold};
        if ~isequal(cueKey, drawnKeys.Cue)
            drawCueTimeline(c.CueAxes, candidate, t);
            drawnKeys.Cue = cueKey;
        end
        if ~isequal(candidate.Sync.Barcode, drawnKeys.Barcode)
            drawBarcode(c.BarcodeAxes, candidate.Sync.Barcode, t);
            drawnKeys.Barcode = candidate.Sync.Barcode;
        end
    end

    function showStimulusSet(stimulusSet)
        % The group table, the set summary, the session browser and each side's list
        % of the groups that pay it.
        nGroups = stimulusSet.nGroups;
        groupOfTrial = stimulusSet.PatternGroup(stimulusSet.TrialPattern);
        data = cell(nGroups, 5);
        for g = 1:nGroups
            members = stimulusSet.PatternGroup == g;
            data(g, :) = {g, stimulusSet.GroupLabels{g}, sum(groupOfTrial == g), ...
                          max([0 stimulusSet.nTimers(members)]), stimulusSet.GroupPLeft(g)};
        end
        if ~isequal(controls.GroupTable.Data, data)
            controls.GroupTable.Data = data;
        end

        families = lum.pattern.families();
        family = families(strcmp({families.Name}, stimulusSet.Family));
        if stimulusSet.Continuous
            groupsText = 'a new pattern every trial';
        else
            groupsText = sprintf('%d group(s)', nGroups);
        end
        controls.SetSummary.Text = sprintf('%s  |  %s  |  %g ms bins  |  seed %d', ...
            family.Label, groupsText, 1000 * stimulusSet.BinDuration, stimulusSet.Seed);

        if ~isequal(cachedKey, drawnKeys.Browser)
            controls.Browser.show(stimulusSet);
            drawnKeys.Browser = cachedKey;
        end

        pays = {stimulusSet.GroupPLeft > 0, stimulusSet.GroupPLeft < 1};
        sides = {'Left', 'Right'};
        for i = 1:2
            groups = find(pays{i});
            if isempty(groups)
                text = 'No group pays this side.';
            else
                parts = arrayfun(@(g) sprintf('%s (P(left) %.2f)', stimulusSet.GroupLabels{g}, ...
                                              stimulusSet.GroupPLeft(g)), groups, ...
                                 'UniformOutput', false);
                text = strjoin(parts, ', ');
            end
            controls.(sides{i}).Groups.Text = text;
        end
    end
end


%% Header and tabs --------------------------------------------------------------
% Local, not nested, so their arguments can share names with the caller's variables.
% Each returns the controls struct with its own controls added.

function buildHeader(parent, S, rig, t)
grid = uigridlayout(parent, [1 3], 'ColumnWidth', {52, '1x', 'fit'}, 'Padding', 0, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
logoImage = lum.gui.logo(96);
if isempty(logoImage)
    uilabel(grid, 'Text', '');
else
    uiimage(grid, 'ImageSource', logoImage, 'ScaleMethod', 'fit');
end
titles = uigridlayout(grid, [2 1], 'RowHeight', {26, 20}, 'Padding', 0, 'RowSpacing', 0, ...
                      'BackgroundColor', t.Background);
uilabel(titles, 'Text', 'LuminoseFM  |  session setup', 'FontSize', 18, 'FontWeight', 'bold', ...
        'FontColor', t.Ink);
subject = S.Meta.Subject;
if isempty(subject)
    subject = 'no subject chosen';
end
uilabel(titles, 'Text', sprintf('Subject %s  |  freely-moving 2-AFC, patterned light on the olfactory bulb', ...
                                subject), 'FontColor', t.Muted);
uilabel(grid, 'Text', sprintf('v%s  |  %s', lum.version(), rig.MachineModel), ...
        'FontColor', t.Muted, 'HorizontalAlignment', 'right');
end


function controls = buildExperimentTab(tabGroup, S, controls, choices, t, onEdit)
tab = uitab(tabGroup, 'Title', 'Experiment', 'BackgroundColor', t.Background);
grid = uigridlayout(tab, [1 2], 'ColumnWidth', {470, '1x'}, 'Padding', 12, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);

left = uigridlayout(grid, [4 1], 'RowHeight', {panelHeight(2), panelHeight(2), ...
                    panelHeight(4), '1x'}, 'Padding', 0, 'RowSpacing', 10, ...
                    'BackgroundColor', t.Background);
controls = lum.gui.ExperimentForm.merge(controls, ...
                                        lum.gui.ExperimentForm.buildAnimal(left, S, choices, t));

form = formPanel(left, 'Session length', 2, t, 170);
label(form, 'Maximum trials', t);
controls.MaxTrials = numberField(form, S.Session.MaxTrials, [1 100000], onEdit, true);
label(form, 'Save every N trials', t);
controls.SaveEveryNTrials = numberField(form, S.Session.SaveEveryNTrials, [1 100], onEdit, true);

form = formPanel(left, 'Devices and windows', 4, t, 170);
label(form, 'Sound', t);
controls.UseSound = uicheckbox(form, 'Text', 'HiFi module', ...
    'Value', S.Session.UseSound, 'ValueChangedFcn', @(~, ~) onEdit());
label(form, 'Sync TTL', t);
controls.UseSync = uicheckbox(form, 'Text', 'Flex2 output', ...
    'Value', S.Session.UseSync, 'ValueChangedFcn', @(~, ~) onEdit(), ...
    'Tooltip', 'Trial sync pulses and the session barcode');
label(form, 'Airflow', t);
controls.ShowAnalogViewer = uicheckbox(form, 'Text', 'Analog viewer', ...
    'Value', S.Session.ShowAnalogViewer, 'ValueChangedFcn', @(~, ~) onEdit(), ...
    'Tooltip', 'Opened at session start, to watch the flow meter');
label(form, 'Runtime window', t);
controls.RuntimeWindow = uidropdown(form, 'Items', choices.RuntimeWindows, ...
    'Value', S.Session.RuntimeWindow, 'ValueChangedFcn', @(~, ~) onEdit(), ...
    'Tooltip', 'Automatic: tabbed on the rig, Bpod''s compact window in the emulator');

controls = lum.gui.ExperimentForm.merge(controls, lum.gui.ExperimentForm.buildNotes(left, S, t));
controls = lum.gui.ExperimentForm.merge(controls, ...
                                        lum.gui.ExperimentForm.buildRecordings(grid, S, choices, t, onEdit));
end


function controls = buildTaskTab(tabGroup, S, controls, runtime, t, onEdit)
tab = uitab(tabGroup, 'Title', 'Task', 'BackgroundColor', t.Background);
grid = uigridlayout(tab, [2 2], 'ColumnWidth', {480, '1x'}, 'RowHeight', {'1x', 170}, ...
                    'Padding', 12, 'ColumnSpacing', 12, 'RowSpacing', 10, ...
                    'BackgroundColor', t.Background);

shaping = runtime(strcmp({runtime.Panel}, 'Shaping'));
left = uigridlayout(grid, [3 1], 'RowHeight', {panelHeight(2) + 20, panelHeight(1), '1x'}, ...
                    'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background);
left.Layout.Row = 1;
left.Layout.Column = 1;

form = formPanel(left, 'Training', 2, t, 170);
form.RowHeight = {26, 44};
label(form, 'Training stage', t);
controls.TrainingStage = uidropdown(form, 'Items', S.Task.TrainingStageNames, ...
    'Value', S.Task.TrainingStageNames{S.Task.TrainingStage}, ...
    'ValueChangedFcn', @(~, ~) onEdit());
label(form, 'Rewards', t);
controls.StageNote = uilabel(form, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Muted, ...
                             'FontSize', 11);

form = formPanel(left, 'Trial order', 1, t, 170);
label(form, 'Max same side in a row', t);
controls.MaxSameSide = numberField(form, S.Task.MaxSameSide, [0 50], onEdit, true);

panel = uipanel(left, 'Title', 'Centre hold', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
form = uigridlayout(panel, [numel(shaping) + 4, 2], 'ColumnWidth', {170, '1x'}, ...
                    'RowHeight', [{44, 26, 26, 72}, repmat({26}, 1, numel(shaping))], ...
                    'Padding', [10 8 10 8], 'RowSpacing', 6, 'ColumnSpacing', 10, ...
                    'BackgroundColor', t.Panel, 'Scrollable', 'on');
label(form, 'Hold', t);
controls.HoldNote = uilabel(form, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Ink, ...
                            'FontSize', 11, 'VerticalAlignment', 'top');
label(form, 'When the hold breaks', t);
controls.OnHoldBreak = uidropdown(form, 'Items', lum.HoldShaping.breakModes(), ...
    'Value', S.Task.OnHoldBreak, 'ValueChangedFcn', @(~, ~) onEdit(), ...
    'Tooltip', ['Restart stimulus: the next poke starts it again, within the hold window. '...
                'End trial: the break is an early withdrawal.']);
label(form, 'Shaping', t);
controls.HoldShaping = uidropdown(form, 'Items', lum.HoldShaping.modes(), ...
    'Value', S.Task.HoldShaping, 'ValueChangedFcn', @(~, ~) onEdit());
label(form, '', t);
controls.ShapingNote = uilabel(form, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Muted, ...
                               'FontSize', 11);
if ~isfield(controls, 'Runtime')
    controls.Runtime = struct();
end
for k = 1:numel(shaping)
    label(form, shaping(k).Label, t);
    controls.Runtime.(shaping(k).Name) = runtimeControl(form, shaping(k), onEdit);
end

panel = uipanel(grid, 'Title', 'Components', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
panel.Layout.Row = 1;
panel.Layout.Column = 2;
form = uigridlayout(panel, [5 2], 'ColumnWidth', {100, '1x'}, ...
                    'RowHeight', {30, 30, 30, 30, '1x'}, 'Padding', [10 8 10 8], ...
                    'RowSpacing', 8, 'ColumnSpacing', 10, 'BackgroundColor', t.Panel);

label(form, 'Cue', t);
row = checkRow(form, numel(S.Cue.Components), t);
cueCaptions = captionsFor({S.Cue.Components.Type});
for k = 1:numel(S.Cue.Components)
    controls.CueEnabled(k) = uicheckbox(row, 'Text', cueCaptions{k}, ...
        'Value', S.Cue.Components(k).Enabled, 'ValueChangedFcn', @(~, ~) onEdit());
end

label(form, 'Stimulus', t);
row = checkRow(form, numel(S.Stimulus.Components) + 1, t);
controls.UseOpto = uicheckbox(row, 'Text', 'Light pattern', 'Value', S.Session.UseOpto, ...
    'ValueChangedFcn', @(~, ~) onEdit(), 'Tooltip', 'Delivered through PulsePal on channels A and B');
stimulusCaptions = captionsFor({S.Stimulus.Components.Type});
for k = 1:numel(S.Stimulus.Components)
    controls.StimulusEnabled(k) = uicheckbox(row, 'Text', stimulusCaptions{k}, ...
        'Value', S.Stimulus.Components(k).Enabled, 'ValueChangedFcn', @(~, ~) onEdit());
end

for side = {'Left', 'Right'}
    label(form, sprintf('%s side', side{1}), t);
    row = checkRow(form, 2, t);
    controls.(side{1}).LightEnabled = uicheckbox(row, 'Text', 'Port light', ...
        'Value', S.(side{1}).Light.Enabled, 'ValueChangedFcn', @(~, ~) onEdit());
    controls.(side{1}).ToneEnabled = uicheckbox(row, 'Text', 'Tone', ...
        'Value', S.(side{1}).Tone.Enabled, 'ValueChangedFcn', @(~, ~) onEdit());
end
explanation = note(form, ['Tick what makes up the trial. Each ticked component is timed on its '...
                          'own tab — Cue, Stimulus, Left or Right — whose title counts what is '...
                          'on. The cue is on from trial start until the stimulus starts, which is '...
                          'the latency set on the Stimulus tab after the animal pokes the centre '...
                          'port (0 s: on the poke). Left and right components are '...
                          'delivered on trials rewarded on that side, so they tell the animal '...
                          'where to go.'], t);
explanation.Layout.Column = [1 2];

panel = uipanel(grid, 'Title', 'One trial', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
panel.Layout.Row = 2;
panel.Layout.Column = [1 2];
flowGrid = uigridlayout(panel, [1 1], 'Padding', 4, 'BackgroundColor', t.Panel);
controls.FlowAxes = uiaxes(flowGrid, 'Color', t.Panel);
controls.FlowAxes.Toolbar.Visible = 'off';
disableDefaultInteractivity(controls.FlowAxes);
end


function controls = buildCueTab(tabGroup, S, controls, t, onEdit)
tab = uitab(tabGroup, 'Title', 'Cue', 'BackgroundColor', t.Background);
controls.Tabs.Cue = tab;
grid = uigridlayout(tab, [1 2], 'ColumnWidth', {520, '1x'}, 'Padding', 12, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);

components = S.Cue.Components;
nComponents = numel(components);
left = uigridlayout(grid, [4 1], 'RowHeight', {panelHeight(nComponents + 1), panelHeight(1), ...
                    panelHeight(3), '1x'}, 'Padding', 0, 'RowSpacing', 10, ...
                    'BackgroundColor', t.Background);
table = timingTable(left, 'Cue components', nComponents, ...
                    {'Through stimulus', 'If not, on for (s)'}, t);
captions = captionsFor({components.Type});
for k = 1:nComponents
    controls.CueChip(k) = makeChip(table, t);
    uilabel(table, 'Text', captions{k}, 'FontColor', t.Ink);
    controls.CueThrough(k) = uicheckbox(table, 'Text', 'continues', ...
        'Value', components(k).ThroughStimulus, 'ValueChangedFcn', @(~, ~) onEdit(), ...
        'Tooltip', 'Ticked: stays on through the whole stimulus, until the hold ends');
    controls.CueDuration(k) = numberField(table, components(k).Duration, [0 60], onEdit, false);
    controls.CueDuration(k).Tooltip = ['Seconds it stays on once the stimulus starts; 0 switches '...
                                       'it off as the stimulus starts'];
end

form = formPanel(left, 'Cue tone', 1, t, 190);
label(form, 'Tone frequency (Hz)', t);
controls.CueToneFrequency = numberField(form, S.Cue.ToneFrequency, [20 80000], onEdit, false);

form = formPanel(left, 'Sound output', 3, t, 190);
label(form, 'Amplitude (0-1)', t);
controls.SoundAmplitude = numberField(form, S.Sound.Amplitude, [0 1], onEdit, false);
label(form, 'Attenuation (dB FS)', t);
controls.Attenuation = numberField(form, S.Sound.Attenuation_dB, [-120 0], onEdit, false);
label(form, 'Punishment noise (s)', t);
controls.NoiseDuration = numberField(form, S.Sound.NoiseDuration, [0.001 10], onEdit, false);

note(left, ['The cue asks the animal to start a trial. Every ticked part comes on at trial '...
            'start and stays on until the stimulus starts — through the wait for the poke, '...
            'however long that takes, and the latency after it (Stimulus tab) — and comes back '...
            'on whenever a broken hold sends the animal back to poke. Ticked "continues", a part '...
            'stays on through the whole stimulus; unticked, it stays on for the time given once '...
            'the stimulus starts, and 0 switches it off as it starts. A centre light or air that '...
            'goes off part way through the stimulus uses a global timer; the tone never does. '...
            'The HiFi module plays one sound at a time, so a cue tone that continues into the '...
            'stimulus cannot be combined with a stimulus or side tone.'], t);

right = uigridlayout(grid, [1 1], 'Padding', 0, 'BackgroundColor', t.Background);
panel = uipanel(right, 'Title', 'Cue timeline: on from trial start until the stimulus starts, then as set', ...
                'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
axesGrid = uigridlayout(panel, [1 1], 'Padding', 6, 'BackgroundColor', t.Panel);
controls.CueAxes = uiaxes(axesGrid);
controls.CueAxes.Toolbar.Visible = 'off';
disableDefaultInteractivity(controls.CueAxes);
end


function controls = buildStimulusTab(tabGroup, S, controls, t, onEdit, onDesign, onNewOrder)
tab = uitab(tabGroup, 'Title', 'Stimulus', 'BackgroundColor', t.Background);
controls.Tabs.Stimulus = tab;
grid = uigridlayout(tab, [1 2], 'ColumnWidth', {520, '1x'}, 'Padding', 12, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);

components = S.Stimulus.Components;
nComponents = numel(components);
left = uigridlayout(grid, [4 1], 'RowHeight', {panelHeight(2), '1x', ...
                    panelHeight(nComponents + 2), 64}, 'Padding', 0, 'RowSpacing', 10, ...
                    'BackgroundColor', t.Background);

form = formPanel(left, 'Stimulus window', 2, t, 190);
label(form, 'Duration (s)', t);
controls.StimulusDuration = numberField(form, S.Stimulus.Duration, [0.001 60], onEdit, false);
label(form, 'Latency from poke (s)', t);
controls.StimulusLatency = numberField(form, S.Stimulus.Latency, [0 60], onEdit, false);
controls.StimulusLatency.Tooltip = ['How long the animal holds the centre port after poking '...
                                    'before the stimulus starts. 0 starts it on the poke; '...
                                    'leaving during it is a broken hold.'];

panel = uipanel(left, 'Title', 'Light patterns and trial order', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
patterns = uigridlayout(panel, [3 1], 'RowHeight', {'fit', 30, '1x'}, 'Padding', [10 8 10 8], ...
                        'RowSpacing', 6, 'BackgroundColor', t.Panel);
summaryRow = uigridlayout(patterns, [1 2], 'ColumnWidth', {50, '1x'}, 'Padding', 0, ...
                          'BackgroundColor', t.Panel);
controls.OptoChip = makeChip(summaryRow, t);
controls.SetSummary = uilabel(summaryRow, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Ink);
buttons = uigridlayout(patterns, [1 3], 'ColumnWidth', {'1x', 150, 130}, 'Padding', 0, ...
                       'ColumnSpacing', 8, 'BackgroundColor', t.Panel);
note(buttons, 'P(left) is editable here and in the designer.', t);
uibutton(buttons, 'Text', 'Design stimuli...', 'FontWeight', 'bold', ...
         'ButtonPushedFcn', @(~, ~) onDesign());
uibutton(buttons, 'Text', 'New trial order', 'ButtonPushedFcn', @(~, ~) onNewOrder(), ...
         'Tooltip', 'Draw a new seed: same patterns, a new shuffle');
controls.GroupTable = uitable(patterns, 'ColumnName', {'Group', 'Label', 'Trials', 'Timers', 'P(left)'}, ...
    'ColumnEditable', [false false false false true], ...
    'ColumnWidth', {50, 'auto', 60, 60, 70}, ...
    'CellEditCallback', @(~, ~) onEdit());
setGroupTable(controls.GroupTable, S.Task.GroupPLeft);

table = timingTable(left, 'Other stimulus components', nComponents + 1, ...
                    {'Onset (s)', 'Duration (s)'}, t);
captions = captionsFor({components.Type});
for k = 1:nComponents
    controls.StimulusChip(k) = makeChip(table, t);
    uilabel(table, 'Text', captions{k}, 'FontColor', t.Ink);
    controls.StimulusOnset(k) = numberField(table, components(k).Onset, [0 60], onEdit, false);
    controls.StimulusLength(k) = numberField(table, components(k).Duration, [0 60], onEdit, false);
end
uilabel(table, 'Text', '');
uilabel(table, 'Text', 'Tone range (Hz)', 'FontColor', t.Ink);
controls.ToneLow = numberField(table, S.Stimulus.ToneFrequencyRange(1), [20 80000], onEdit, false);
controls.ToneHigh = numberField(table, S.Stimulus.ToneFrequencyRange(2), [20 80000], onEdit, false);

note(left, ['Timed from stimulus onset. A component on for the whole window is free; one '...
            'that starts late or ends early uses a global timer. The stimulus tone has a '...
            'frequency of its own for each group, spread across the range.'], t);

panel = uipanel(grid, 'Title', 'Every trial of the session', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
browserGrid = uigridlayout(panel, [1 1], 'Padding', 8, 'BackgroundColor', t.Panel);
controls.Browser = lum.gui.PatternBrowser(browserGrid);
end


function controls = buildLightPathTab(tabGroup, S, controls, t, onEdit)
tab = uitab(tabGroup, 'Title', 'Light path', 'BackgroundColor', t.Background);
grid = uigridlayout(tab, [1 2], 'ColumnWidth', {600, '1x'}, 'Padding', 12, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
left = uigridlayout(grid, [3 1], 'RowHeight', {panelHeight(4) + 20, panelHeight(3), '1x'}, ...
                    'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background);

bundles = lum.fiberBundles();
form = formPanel(left, 'Fiber bundle', 4, t, 190);
form.RowHeight = {26, 26, 26, 46};
label(form, 'Bundle on the animal', t);
controls.Bundle = uidropdown(form, 'Items', {bundles.Name}, 'Value', S.Light.Bundle);
label(form, 'Cable on channel A', t);
controls.CableA = uidropdown(form, 'Items', {''});
label(form, 'Cable on channel B', t);
controls.CableB = uidropdown(form, 'Items', {''});
fillCables(controls.Bundle, controls.CableA, controls.CableB, bundles, S.Light.Cables);
controls.Bundle.ValueChangedFcn = @(~, ~) bundleChanged(controls.Bundle, controls.CableA, ...
                                                        controls.CableB, bundles, onEdit);
controls.CableA.ValueChangedFcn = @(~, ~) onEdit();
controls.CableB.ValueChangedFcn = @(~, ~) onEdit();
label(form, 'Wiring', t);
controls.BundleNote = uilabel(form, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Muted, ...
                              'FontSize', 11);

panel = uipanel(left, 'Title', 'Carrier (PulsePal)', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
table = uigridlayout(panel, [3 4], 'ColumnWidth', {190, '1x', '1x', '1x'}, ...
                     'RowHeight', {22, 26, 26}, 'Padding', [10 8 10 8], 'RowSpacing', 6, ...
                     'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
headings(table, {'', 'Frequency (Hz)', 'Pulse width (s)', 'LED drive (V)'}, t);
names = {'A  (BNC1, PulsePal OUT1)', 'B  (BNC2, PulsePal OUT2)'};
colours = {t.ChannelA, t.ChannelB};
for k = 1:2
    carrier = S.Light.Carrier(min(k, numel(S.Light.Carrier)));
    uilabel(table, 'Text', names{k}, 'FontWeight', 'bold', 'FontColor', colours{k});
    controls.Frequency(k) = numberField(table, carrier.Frequency, [0 10000], onEdit, false);
    controls.PulseWidth(k) = numberField(table, carrier.PulseWidth, [0 1], onEdit, false);
    controls.Voltage(k) = numberField(table, carrier.Voltage, [0 lum.dev.PulsePal.MaxVoltage], ...
                                      onEdit, false);
end

note(left, ['The pattern says which channel is on and when; the carrier says what the light '...
            'does while it is on. Each channel drives its own LED into its own cable, so each '...
            'has its own carrier: equalising the light the two deliver is a per-channel '...
            'calibration. A frequency of 0 gives constant light while the channel is on.'], t);
note(grid, sprintf(['Channel A:  Bpod BNC1 -> PulsePal IN1 -> OUT1 -> Doric LED ch1\n'...
                    'Channel B:  Bpod BNC2 -> PulsePal IN2 -> OUT2 -> Doric LED ch2\n\n'...
                    'The 2-to-19 bundle has one fiber per channel: ch1 makes 10 spots and ch2 9. '...
                    'The 4-to-19 bundle has four cables — black (4 spots), blue, orange and green '...
                    '(5 each) — of which two are on the commutator. Record which, so the pattern '...
                    'a channel delivered can be traced to the spots it lit.']), t);
end


function controls = buildSideTab(tabGroup, S, side, controls, choices, t, onEdit)
tab = uitab(tabGroup, 'Title', side, 'BackgroundColor', t.Background);
controls.Tabs.(side) = tab;
grid = uigridlayout(tab, [1 2], 'ColumnWidth', {560, '1x'}, 'Padding', 12, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
left = uigridlayout(grid, [4 1], 'RowHeight', {panelHeight(2), panelHeight(2), ...
                    panelHeight(1), '1x'}, 'Padding', 0, 'RowSpacing', 10, ...
                    'BackgroundColor', t.Background);
settings = S.(side);

panel = uipanel(left, 'Title', sprintf('%s port light', side), 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
row = uigridlayout(panel, [2 3], 'ColumnWidth', {60, '1x', '1x'}, 'RowHeight', {20, 26}, ...
                   'Padding', [10 8 10 8], 'RowSpacing', 4, 'ColumnSpacing', 10, ...
                   'BackgroundColor', t.Panel);
headings(row, {'', 'Onset (s)', 'Duration (s)'}, t);
controls.(side).LightChip = makeChip(row, t);
controls.(side).LightOnset = numberField(row, settings.Light.Onset, [0 60], onEdit, false);
controls.(side).LightDuration = numberField(row, settings.Light.Duration, [0 60], onEdit, false);

panel = uipanel(left, 'Title', sprintf('%s tone', side), 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
row = uigridlayout(panel, [2 4], 'ColumnWidth', {60, '1x', '1x', '1x'}, 'RowHeight', {20, 26}, ...
                   'Padding', [10 8 10 8], 'RowSpacing', 4, 'ColumnSpacing', 10, ...
                   'BackgroundColor', t.Panel);
headings(row, {'', 'Frequency (Hz)', 'Onset (s)', 'Duration (s)'}, t);
controls.(side).ToneChip = makeChip(row, t);
controls.(side).ToneFrequency = numberField(row, settings.Tone.Frequency, [20 80000], onEdit, false);
controls.(side).ToneOnset = numberField(row, settings.Tone.Onset, [0 60], onEdit, false);
controls.(side).ToneDuration = numberField(row, settings.Tone.Duration, [0 60], onEdit, false);

form = formPanel(left, 'Guide light', 1, t, 220);
label(form, 'Light the port while choosing', t);
controls.(side).GuideLight = uidropdown(form, 'Items', choices.GuideLights, ...
    'Value', settings.GuideLight, 'ValueChangedFcn', @(~, ~) onEdit());

panel = uipanel(left, 'Title', sprintf('Groups rewarded on the %s', lower(side)), ...
                'FontWeight', 'bold', 'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
listGrid = uigridlayout(panel, [1 1], 'Padding', 10, 'BackgroundColor', t.Panel);
controls.(side).Groups = uilabel(listGrid, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Ink, ...
                                 'VerticalAlignment', 'top');

note(grid, sprintf(['Delivered on trials rewarded on the %s, timed from stimulus onset, so they '...
                    'tell the animal where to go: a visual or auditory version of the task, or a '...
                    'hint during training. Switch them on from the Task tab.\n\nThe guide light '...
                    'lights this port during the response window. "Habituation only" lights it '...
                    'in stage 1, where both side ports pay.'], lower(side)), t);
end


function controls = buildSyncTab(tabGroup, S, controls, t, onEdit)
tab = uitab(tabGroup, 'Title', 'Sync', 'BackgroundColor', t.Background);
grid = uigridlayout(tab, [1 2], 'ColumnWidth', {500, '1x'}, 'Padding', 12, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
left = uigridlayout(grid, [3 1], 'RowHeight', {panelHeight(5) + 30, panelHeight(7), '1x'}, ...
                    'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background);

form = formPanel(left, 'Trial sync pulses', 5, t, 190);
form.RowHeight = {26, 26, 26, 26, 56};
label(form, 'Mode', t);
controls.SyncMode = uidropdown(form, 'Items', S.Sync.ModeNames, ...
    'Value', S.Sync.ModeNames{S.Sync.Mode}, 'ValueChangedFcn', @(~, ~) onEdit());
label(form, 'Fixed width (s)', t);
controls.SyncFixed = numberField(form, S.Sync.FixedWidth, [0.0001 10], onEdit, false);
label(form, 'Mean width (s)', t);
controls.SyncMean = numberField(form, S.Sync.MeanWidth, [0.0001 10], onEdit, false);
label(form, 'Width jitter (+/- s)', t);
controls.SyncJitter = numberField(form, S.Sync.WidthJitter, [0 10], onEdit, false);
label(form, '', t);
controls.SyncNote = uilabel(form, 'Text', '', 'WordWrap', 'on', 'FontColor', t.Muted, ...
                            'FontSize', 11, 'VerticalAlignment', 'top');

barcode = S.Sync.Barcode;
form = formPanel(left, 'Session barcode', 7, t, 190);
label(form, '', t);
controls.BarcodeEnabled = uicheckbox(form, 'Text', 'Session barcode', ...
    'Value', barcode.Enabled, 'ValueChangedFcn', @(~, ~) onEdit(), ...
    'Tooltip', 'Sent before the first trial');
label(form, 'Bits', t);
controls.BarcodeBits = numberField(form, barcode.nBits, [8 48], onEdit, true);
label(form, 'Behaviour marker (s)', t);
controls.BarcodeMarker = numberField(form, barcode.MarkerWidth, [0.001 1], onEdit, false);
label(form, 'Sleep marker (s)', t);
controls.BarcodeSleepMarker = numberField(form, lum.sync.sleepMarkerWidth(barcode), [0.001 1], ...
                                          onEdit, false);
label(form, '0 bit pulse (s)', t);
controls.BarcodeZero = numberField(form, barcode.ZeroWidth, [0.001 1], onEdit, false);
label(form, '1 bit pulse (s)', t);
controls.BarcodeOne = numberField(form, barcode.OneWidth, [0.001 1], onEdit, false);
label(form, 'Gap after each pulse (s)', t);
controls.BarcodeGap = numberField(form, barcode.Gap, [0.001 1], onEdit, false);

note(left, ['Both go out on Flex2, which has to be set as a digital output in the Bpod '...
            'console. The emulator has no Flex I/O, so an emulated session records the '...
            'barcode it would have sent without sending it.'], t);

right = uigridlayout(grid, [2 1], 'RowHeight', {220, '1x'}, 'Padding', 0, 'RowSpacing', 10, ...
                     'BackgroundColor', t.Background);
panel = uipanel(right, 'Title', 'Barcode preview', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
axesGrid = uigridlayout(panel, [1 1], 'Padding', 6, 'BackgroundColor', t.Panel);
controls.BarcodeAxes = uiaxes(axesGrid);
controls.BarcodeAxes.Toolbar.Visible = 'off';
disableDefaultInteractivity(controls.BarcodeAxes);
note(right, sprintf(['The barcode identifies the session on every device that records the '...
                     'sync line: a marker pulse, one pulse per bit (short for 0, long for 1, most '...
                     'significant first), and a closing marker. It encodes the seconds from '...
                     '2020-01-01 to the session start, which is also in the data file''s name. '...
                     'Behaviour sessions use the behaviour marker and sleep sessions the longer '...
                     'sleep marker, so a recording says which kind of session it holds.\n\n'...
                     'To read it from a recording: [value, ~, kind] = lum.sync.decodeBarcode(rising, '...
                     'falling, SessionData.Session.Barcode.Params), then lum.sync.barcodeTime(value).']), t);
end


function controls = buildRuntimeTab(tabGroup, fields, controls, t, onEdit)
% The runtime tier, built from its own declaration, grouped as the runtime window
% groups it. Hold shaping is on the Task tab, beside the choice that uses it.
tab = uitab(tabGroup, 'Title', 'Runtime', 'BackgroundColor', t.Background);
fields = fields(~strcmp({fields.Panel}, 'Shaping'));
grid = uigridlayout(tab, [2 1], 'RowHeight', {34, '1x'}, 'Padding', 12, 'RowSpacing', 8, ...
                    'BackgroundColor', t.Background);
note(grid, ['Starting values for the parameters that stay editable during the session. They '...
            'appear in the runtime window, where a change takes effect on the next trial.'], t);

tabNames = unique({fields.Tab}, 'stable');
columns = uigridlayout(grid, [1 numel(tabNames)], 'Padding', 0, 'ColumnSpacing', 12, ...
                       'BackgroundColor', t.Background);
if ~isfield(controls, 'Runtime')
    controls.Runtime = struct();
end
for i = 1:numel(tabNames)
    inTab = fields(strcmp({fields.Tab}, tabNames{i}));
    panelNames = unique({inTab.Panel}, 'stable');
    heights = cellfun(@(name) panelHeight(sum(strcmp({inTab.Panel}, name))), panelNames, ...
                      'UniformOutput', false);
    column = uigridlayout(columns, [numel(panelNames) + 2, 1], ...
                          'RowHeight', [{22}, heights, {'1x'}], 'Padding', 0, 'RowSpacing', 10, ...
                          'BackgroundColor', t.Background, 'Scrollable', 'on');
    uilabel(column, 'Text', tabNames{i}, 'FontSize', 14, 'FontWeight', 'bold', 'FontColor', t.Ink);
    for j = 1:numel(panelNames)
        members = inTab(strcmp({inTab.Panel}, panelNames{j}));
        form = formPanel(column, panelNames{j}, numel(members), t, 200);
        for k = 1:numel(members)
            label(form, members(k).Label, t);
            controls.Runtime.(members(k).Name) = runtimeControl(form, members(k), onEdit);
        end
    end
end
end


%% Reading controls back ---------------------------------------------------------

function values = readRuntime(handles, fields, values)
% Read the runtime controls back into S.GUI. Read-only displays and in-session
% buttons are left at the value they came in with.
for i = 1:numel(fields)
    name = fields(i).Name;
    if ~isfield(handles, name)
        continue
    end
    switch fields(i).Style
        case 'numeric'
            values.(name) = handles.(name).Value;
        case 'checkbox'
            values.(name) = double(handles.(name).Value);  % As the runtime windows store it
        case 'dropdown'
            values.(name) = find(strcmp(handles.(name).Value, fields(i).Items), 1);
        case 'text'
            values.(name) = handles.(name).Value;
    end
end
end


function pLeft = readPLeft(data)
% P(left) per group, from the group table's last column.
if isempty(data)
    pLeft = [];
    return
end
pLeft = cellfun(@double, data(:, 5))';
end


function key = setKey(S, rig)
% Everything the stimulus set depends on, to decide whether it has to be rebuilt.
key = {S.Stimulus.Generator, S.Stimulus.Duration, S.Session.MaxTrials, S.Session.UseOpto, ...
       S.Task.GroupPLeft, lum.timerBudget(S, rig)};
end


%% Pieces -----------------------------------------------------------------------

function setGroupTable(table, pLeft)
% Placeholder rows for a contingency, before the set they belong to is compiled.
n = numel(pLeft);
data = cell(n, 5);
for g = 1:n
    data(g, :) = {g, sprintf('Group %d', g), [], [], pLeft(g)};
end
table.Data = data;
end


function fillCables(bundleDropdown, cableA, cableB, bundles, chosen)
% Offer the chosen bundle's cables, with their spot counts, keeping choices that fit.
bundle = bundles(strcmp({bundles.Name}, bundleDropdown.Value));
items = arrayfun(@(k) sprintf('%s (%d spots)', bundle.Cables{k}, bundle.Spots(k)), ...
                 1:numel(bundle.Cables), 'UniformOutput', false);
cableA.Items = items;
cableA.ItemsData = bundle.Cables;
cableB.Items = items;
cableB.ItemsData = bundle.Cables;
if bundle.Choose && numel(chosen) == 2 && all(ismember(chosen, bundle.Cables))
    cableA.Value = chosen{1};
    cableB.Value = chosen{2};
else
    cableA.Value = bundle.Cables{1};
    cableB.Value = bundle.Cables{2};
end
end


function bundleChanged(bundleDropdown, cableA, cableB, bundles, onEdit)
fillCables(bundleDropdown, cableA, cableB, bundles, {cableA.Value, cableB.Value});
onEdit();
end


function text = bundleNote(S, bundles)
% Which cable carries which channel, in words.
bundle = bundles(strcmp({bundles.Name}, S.Light.Bundle));
if isempty(bundle)
    text = '';
    return
end
spots = containers.Map(bundle.Cables, num2cell(bundle.Spots));
names = S.Light.Cables;
if ~bundle.Choose || numel(names) ~= 2 || ~all(isKey(spots, names))
    names = bundle.Cables(1:2);
end
text = sprintf('A lights %d spots through the %s; B lights %d through the %s.', ...
               spots(names{1}), names{1}, spots(names{2}), names{2});
end


function text = syncNote(mode)
% What the acquisition system will see, by mode.
switch mode
    case lum.SyncMode.FixedWidth
        text = 'One pulse per trial, always the same width: enough to count trials.';
    case lum.SyncMode.JitteredWidth
        text = ['One pulse per trial, its width drawn within the jitter of the mean. The '...
                'widths are near-unique, so a recording is matched trial by trial.'];
    otherwise
        text = ['No pulse: high at trial start, low when the animal pokes the centre port, so '...
                'the edges mark those events. Costs no global timer.'];
end
end


function drawCueTimeline(ax, S, t)
% The cue as the animal meets it, one row per component under a row for the stimulus:
% on from trial start, through the wait for the poke (the animal's, not to scale) and
% the latency, until the stimulus starts; then on for as long as its row says.
cla(ax);
hold(ax, 'on');
rows = S.Cue.Components;
captions = captionsFor({rows.Type});
n = numel(rows);
window = max(S.Stimulus.Duration, 0);
postHold = max(S.GUI.PostStimulusHold, 0);
latency = max(S.Stimulus.Latency, 0);
holdEnd = max(window + postHold, 0.01);
wait = 0.5 * (holdEnd + latency);
start = -latency - wait;
cueColour = t.Accent;

% The stimulus, for reference, with the latency held before it.
top = n + 1;
if latency > 0
    rectangle(ax, 'Position', [-latency, top - 0.3, latency, 0.6], 'FaceColor', t.Faint, ...
              'EdgeColor', 'none');
end
rectangle(ax, 'Position', [0, top - 0.3, max(window, 1e-3), 0.6], ...
          'FaceColor', (t.ChannelA + t.ChannelB) / 2, 'EdgeColor', 'none');
if postHold > 0
    rectangle(ax, 'Position', [window, top - 0.3, postHold, 0.6], 'FaceColor', t.Faint, ...
              'EdgeColor', 'none');
end
line(ax, [0 0], [0.4, n + 1.55], 'Color', t.Ink, 'LineStyle', '--', 'LineWidth', 1);
if latency > 0
    line(ax, -[latency latency], [0.4, n + 1.55], 'Color', t.Muted, 'LineStyle', ':', 'LineWidth', 1);
    text(ax, -latency, n + 1.6, 'poke  ', 'FontSize', 10, 'Color', t.Muted, ...
         'VerticalAlignment', 'bottom', 'HorizontalAlignment', 'right');
    text(ax, 0, n + 1.6, '  the stimulus starts', 'FontSize', 10, 'Color', t.Ink, ...
         'VerticalAlignment', 'bottom');
else
    text(ax, 0, n + 1.6, '  centre poke: the stimulus starts', 'FontSize', 10, 'Color', t.Ink, ...
         'VerticalAlignment', 'bottom');
end

try
    parts = lum.cueTiming(S);
catch
    parts = struct('Type', {}, 'Mode', {}, 'Duration', {});  % A bad value; draw nothing on
end
labels = cell(1, n + 1);
labels{top} = 'Stimulus';
for k = 1:n
    y = n - k + 1;
    part = parts(strcmp({parts.Type}, rows(k).Type));
    if ~rows(k).Enabled || isempty(part)
        labels{y} = sprintf('%s: off', captions{k});
        line(ax, [start, holdEnd], [y y], 'Color', t.Faint, 'LineWidth', 1);
        continue
    end
    rectangle(ax, 'Position', [start, y - 0.3, -start, 0.6], 'FaceColor', cueColour, ...
              'EdgeColor', 'none');
    switch part.Mode
        case 'Whole'
            after = holdEnd;
            labels{y} = sprintf('%s: continues', captions{k});
        case 'Off'
            after = 0;
            labels{y} = sprintf('%s: off as it starts', captions{k});
        otherwise
            after = min(part.Duration, holdEnd);
            labels{y} = sprintf('%s: %g s into it', captions{k}, part.Duration);
    end
    if after > 0
        rectangle(ax, 'Position', [0, y - 0.3, after, 0.6], 'FaceColor', cueColour, ...
                  'EdgeColor', 'none');
    end
end

ticks = unique([0, window, holdEnd]);
if latency > 0
    ticks = [-latency, ticks];
end
tickLabels = arrayfun(@(value) sprintf('%g', value), ticks, 'UniformOutput', false);
set(ax, 'YTick', 1:n + 1, 'YTickLabel', labels, 'YLim', [0.4, n + 2.1], ...
    'XLim', [start, 1.1 * holdEnd], 'XTick', [start, ticks], ...
    'XTickLabel', [{'trial start'}, tickLabels], 'Color', t.Panel, 'XColor', t.Muted, ...
    'YColor', t.Muted, 'TickDir', 'out', 'Box', 'off', 'XGrid', 'off', 'YGrid', 'off', ...
    'FontSize', 11);
xlabel(ax, 'Seconds from stimulus onset');
hold(ax, 'off');
end


function drawBarcode(ax, params, t)
% The barcode a behaviour session started now would send.
lum.gui.Form.drawBarcode(ax, params, 'Behaviour', t);
end


function control = runtimeControl(parent, field, onEdit)
% One control for one runtime parameter, chosen by the style its GUIMeta declares.
switch field.Style
    case 'numeric'
        control = uieditfield(parent, 'numeric', 'Value', field.Value, ...
                              'ValueChangedFcn', @(~, ~) onEdit());
        if ~isempty(field.Limits)
            control.Limits = field.Limits;
        end
    case 'checkbox'
        control = uicheckbox(parent, 'Text', '', 'Value', logical(field.Value), ...
                             'ValueChangedFcn', @(~, ~) onEdit());
    case 'dropdown'
        control = uidropdown(parent, 'Items', field.Items, ...
                             'Value', field.Items{min(field.Value, numel(field.Items))}, ...
                             'ValueChangedFcn', @(~, ~) onEdit());
    case 'text'
        control = uieditfield(parent, 'text', 'Value', field.Value);
    otherwise
        % A read-only display or an in-session action: nothing to act on before a session.
        control = uilabel(parent, 'Text', '(set during the session)', 'FontSize', 11);
end
end


function handles = runtimeHandles(runtimeControls, names)
% The runtime controls of the named parameters that exist.
names = names(isfield(runtimeControls, names));
handles = cellfun(@(name) runtimeControls.(name), names, 'UniformOutput', false);
end


function grid = formPanel(parent, title, nRows, t, labelWidth)
% A titled panel holding a label/field form of nRows rows (lum.gui.Form.panel).
grid = lum.gui.Form.panel(parent, title, nRows, t, labelWidth);
end


function grid = timingTable(parent, title, nRows, columnNames, t)
% A titled panel with a header row and nRows rows of: chip, name, then one numeric
% column per columnNames entry.
panel = uipanel(parent, 'Title', title, 'FontWeight', 'bold', 'BackgroundColor', t.Panel, ...
                'ForegroundColor', t.Accent);
nColumns = 2 + numel(columnNames);
grid = uigridlayout(panel, [nRows + 1, nColumns], ...
                    'ColumnWidth', [{50, 150}, repmat({'1x'}, 1, numel(columnNames))], ...
                    'RowHeight', repmat({26}, 1, nRows + 1), 'Padding', [10 8 10 8], ...
                    'RowSpacing', 6, 'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
headings(grid, [{'', ''}, columnNames], t);
end


function headings(grid, names, t)
% A row of small bold column headings.
for i = 1:numel(names)
    uilabel(grid, 'Text', names{i}, 'FontWeight', 'bold', 'FontSize', 11, 'FontColor', t.Muted);
end
end


function row = checkRow(parent, n, t)
% A row of n equal cells for checkboxes.
row = uigridlayout(parent, [1 n], 'ColumnWidth', repmat({'1x'}, 1, n), 'Padding', 0, ...
                   'ColumnSpacing', 8, 'BackgroundColor', t.Panel);
end


function chip = makeChip(parent, t)
% A small on/off badge showing whether a component is part of the trial.
chip = uilabel(parent, 'Text', 'off', 'HorizontalAlignment', 'center', 'FontSize', 10, ...
               'FontWeight', 'bold', 'BackgroundColor', t.Faint, 'FontColor', t.Muted);
end


function setChip(chip, on, t)
if on
    chip.Text = 'on';
    chip.BackgroundColor = t.Accent;
    chip.FontColor = [1 1 1];
else
    chip.Text = 'off';
    chip.BackgroundColor = t.Faint;
    chip.FontColor = t.Muted;
end
end


function setEnable(handles, on)
% Enable or disable a list of controls together.
lum.gui.Form.setEnable(handles, on);
end


function title = countedTitle(name, n)
% A tab title that counts the components switched on in it.
if n > 0
    title = sprintf('%s  (%d on)', name, n);
else
    title = name;
end
end


function captions = captionsFor(types)
% Readable names for component types.
names = struct('CentreLight', 'Centre light', 'Tone', 'Tone', 'Air', 'Air');
captions = types;
for i = 1:numel(types)
    if isfield(names, types{i})
        captions{i} = names.(types{i});
    end
end
end


function field = numberField(parent, value, limits, onEdit, isInteger)
field = lum.gui.Form.number(parent, value, limits, onEdit, isInteger);
end


function label(parent, caption, t)
lum.gui.Form.label(parent, caption, t);
end


function handle = note(parent, caption, t)
handle = lum.gui.Form.note(parent, caption, t);
end


function height = panelHeight(nRows)
% The pixel height formPanel needs for nRows rows (lum.gui.Form.panelHeight).
height = lum.gui.Form.panelHeight(nRows);
end


function state = onOff(tf)
% A logical as the on/off value a control's Enable property wants.
state = lum.gui.Form.onOff(tf);
end
