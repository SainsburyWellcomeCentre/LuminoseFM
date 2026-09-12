function [S, accepted, app] = TestPulseDesigner(S, rig, varargin)
% lum.gui.TestPulseDesigner designs a sleep session's test pulses and their schedule.
%
% Test pulses (D13) are light on channels A and B during a sleep recording: probe
% pulses — a single pulse or a pair, every inter-epoch interval — to measure the
% response, and plasticity trains — theta burst, high frequency or any other — to change
% it, arranged in a schedule of steps that runs from the start of the recording (for
% example probes, a theta burst, probes again). This window puts every parameter in
% front of the operator, compiles the schedule on each edit (lum.sleep.testPulsePlan,
% lum.sleep.validateTestPulses), and draws the whole session and one epoch of the
% selected step the way PulsePal will deliver it.
%
% It opens from the sleep setup dialog ("Design test-pulse schedule..."), and on its
% own:
%
%   S = lum.gui.TestPulseDesigner();             % defaults
%   S = lum.gui.TestPulseDesigner(S, RigConfig);
%
% Only S.Sleep.TestPulses is changed, and not its Enabled flag, which belongs to the
% sleep setup dialog. Nothing leaves the window until the schedule compiles.
%
% Options:
%   'Wait'     false to return at once with the window open (for tests); default true
%   'Visible'  'on' (default) or 'off'
%
% Returns:
%   S         The settings, with the design applied if accepted
%   accepted  True if the operator chose 'Use this schedule'
%   app       With 'Wait' false: .Figure, .collect(), .refresh(), .apply(), .cancel(),
%             .status(), .preset(name), .addStep(), .removeStep(), .moveStep(offset),
%             .addTrain(), .removeTrain(), .selectStep(k) and .controls
%
% See also: lum.sleep.testPulsePlan, lum.gui.SleepSetupDialog, lum.sleep.describeTrain

if nargin < 1 || isempty(S)
    S = lum.defaultSettings;
end
if nargin < 2 || isempty(rig)
    rig = RigConfig;
end
p = inputParser;
p.FunctionName = 'lum.gui.TestPulseDesigner';
addParameter(p, 'Wait', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'Visible', 'on');
parse(p, varargin{:});

accepted = false;
t = lum.gui.theme();
testPulses = S.Sleep.TestPulses;
choices = lum.sleep.stepChoices(testPulses);
trainColumns = {'Name', 'PulseFrequency', 'PulseWidth', 'PulsesPerBurst', 'BurstFrequency', ...
                'BurstsPerTrain', 'nTrains', 'TrainInterval'};
presets = {'Start from a preset...', 'Paired-pulse probes, 4 h', 'Probe, theta burst, probe', ...
           'Probe, high frequency, probe'};
selectedStep = 1;
selectedTrain = 0;

fig = uifigure('Name', 'LuminoseFM - test-pulse designer', 'Position', [60 40 1360 840], ...
               'Color', t.Background, 'Visible', p.Results.Visible);
outer = uigridlayout(fig, [4 1], 'RowHeight', {54, '1x', 'fit', 34}, 'Padding', [14 10 14 12], ...
                     'RowSpacing', 8, 'BackgroundColor', t.Background);
buildHeader(outer, rig, t);

main = uigridlayout(outer, [1 2], 'ColumnWidth', {610, '1x'}, 'Padding', 0, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
height = @lum.gui.Form.panelHeight;
left = uigridlayout(main, [3 1], 'RowHeight', {height(5) + 30, height(2), '1x'}, ...
                    'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background);
controls = struct();

probe = testPulses.Probe;
form = lum.gui.Form.panel(left, 'Probe pulses', 5, t, 250);
form.RowHeight = {26, 26, 26, 26, 56};
lum.gui.Form.label(form, 'Each epoch', t);
controls.ProbeMode = uidropdown(form, 'Items', choices.ProbeModes, 'Value', probe.Mode, ...
                                'ValueChangedFcn', @(~, ~) refresh());
lum.gui.Form.label(form, 'Pulse width (s)', t);
controls.ProbeWidth = lum.gui.Form.number(form, probe.PulseWidth, [0.0001 10], @refresh, false);
lum.gui.Form.label(form, 'Inter-pulse interval (s, onset to onset)', t);
controls.InterPulseInterval = lum.gui.Form.number(form, probe.InterPulseInterval, [0.0002 60], ...
                                                  @refresh, false);
lum.gui.Form.label(form, 'Inter-epoch interval (s, onset to onset)', t);
controls.InterEpochInterval = lum.gui.Form.number(form, probe.InterEpochInterval, [0.001 3600], ...
                                                  @refresh, false);
lum.gui.Form.label(form, '', t);
controls.ProbeNote = lum.gui.Form.note(form, '', t);

form = lum.gui.Form.panel(left, 'LED drive (constant light for probes, pulse height for trains)', 2, t, 250);
lum.gui.Form.label(form, 'Channel A (V)', t);
controls.VoltageA = lum.gui.Form.number(form, testPulses.Voltage(1), [-10 10], @refresh, false);
lum.gui.Form.label(form, 'Channel B (V)', t);
controls.VoltageB = lum.gui.Form.number(form, testPulses.Voltage(2), [-10 10], @refresh, false);

box = uipanel(left, 'Title', 'Plasticity trains', 'FontWeight', 'bold', ...
              'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
grid = uigridlayout(box, [4 1], 'RowHeight', {26, '1x', 30, 96}, 'Padding', [10 8 10 8], ...
                    'RowSpacing', 6, 'BackgroundColor', t.Panel);
controls.TrainsEnabled = uicheckbox(grid, 'Text', 'Plasticity trains: schedule steps may deliver these', ...
                                    'Value', testPulses.PlasticityTrains, ...
                                    'ValueChangedFcn', @(~, ~) refresh());
controls.TrainTable = uitable(grid, 'Data', trainRows(testPulses.Trains), ...
    'ColumnName', {'Name', 'Pulse Hz', 'Width (s)', 'Pulses/burst', 'Burst Hz', 'Bursts', ...
                   'Trains', 'Interval (s)'}, ...
    'ColumnWidth', {112, 64, 70, 84, 66, 58, 52, 76}, ...
    'ColumnFormat', {'char', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric', 'numeric'}, ...
    'ColumnEditable', true, 'RowName', {}, 'CellEditCallback', @(~, ~) refresh(), ...
    'CellSelectionCallback', @(~, event) onTrainSelected(event));
buttons = uigridlayout(grid, [1 3], 'ColumnWidth', {110, 120, '1x'}, 'Padding', 0, ...
                       'ColumnSpacing', 8, 'BackgroundColor', t.Panel);
uibutton(buttons, 'Text', 'Add train', 'ButtonPushedFcn', @(~, ~) addTrain());
uibutton(buttons, 'Text', 'Remove train', 'ButtonPushedFcn', @(~, ~) removeTrain());
uilabel(buttons, 'Text', '');
controls.TrainNote = lum.gui.Form.note(grid, '', t);

right = uigridlayout(main, [4 1], 'RowHeight', {'1x', 30, 190, 180}, 'Padding', 0, ...
                     'RowSpacing', 10, 'BackgroundColor', t.Background);
box = uipanel(right, 'Title', 'Schedule: steps run in order from the start of the recording', ...
              'FontWeight', 'bold', 'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
grid = uigridlayout(box, [1 1], 'Padding', [10 8 10 8], 'BackgroundColor', t.Panel);
controls.StepTable = uitable(grid, 'Data', stepRows(testPulses.Schedule), ...
    'ColumnName', {'Step', 'Channels', 'Minutes', 'Starts at (min)', 'Epochs'}, ...
    'ColumnFormat', {choices.Kinds, choices.Channels, 'numeric', 'numeric', 'numeric'}, ...
    'ColumnEditable', [true true true false false], 'RowName', 'numbered', ...
    'CellEditCallback', @(~, ~) refresh(), 'CellSelectionCallback', @(~, event) onStepSelected(event));
buttons = uigridlayout(right, [1 6], 'ColumnWidth', {100, 110, 90, 100, '1x', 260}, 'Padding', 0, ...
                       'ColumnSpacing', 8, 'BackgroundColor', t.Background);
uibutton(buttons, 'Text', 'Add step', 'ButtonPushedFcn', @(~, ~) addStep());
uibutton(buttons, 'Text', 'Remove step', 'ButtonPushedFcn', @(~, ~) removeStep());
uibutton(buttons, 'Text', 'Move up', 'ButtonPushedFcn', @(~, ~) moveStep(-1));
uibutton(buttons, 'Text', 'Move down', 'ButtonPushedFcn', @(~, ~) moveStep(1));
uilabel(buttons, 'Text', '');
controls.Preset = uidropdown(buttons, 'Items', presets, 'Value', presets{1}, ...
                             'ValueChangedFcn', @(source, ~) preset(source.Value));
controls.ScheduleAxes = previewAxes(right);
controls.EpochAxes = previewAxes(right);

controls.Status = uilabel(outer, 'Text', '', 'WordWrap', 'on', 'FontSize', 12);
footer = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 110, 170}, 'Padding', 0, ...
                      'ColumnSpacing', 8, 'BackgroundColor', t.Background);
lum.gui.Form.note(footer, ['Probes are constant light for the gate''s length; trains are PulsePal '...
                           'pulses inside each burst''s gate. Every interval is onset to onset.'], t);
uibutton(footer, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
controls.Apply = uibutton(footer, 'Text', 'Use this schedule', 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Accent, 'FontColor', [1 1 1], ...
                          'ButtonPushedFcn', @(~, ~) apply());

refresh();
app = struct('Figure', fig, 'collect', @collect, 'refresh', @refresh, 'apply', @apply, ...
             'cancel', @onCancel, 'status', @statusText, 'preset', @preset, ...
             'addStep', @addStep, 'removeStep', @removeStep, 'moveStep', @moveStep, ...
             'addTrain', @addTrain, 'removeTrain', @removeTrain, 'selectStep', @selectStep, ...
             'controls', controls);
if p.Results.Wait
    uiwait(fig);
end


    function candidate = collect()
        % The settings as the window shows them.
        c = controls;
        candidate = S;
        designed = candidate.Sleep.TestPulses;
        designed.Probe = struct('Mode', c.ProbeMode.Value, 'PulseWidth', c.ProbeWidth.Value, ...
                                'InterPulseInterval', c.InterPulseInterval.Value, ...
                                'InterEpochInterval', c.InterEpochInterval.Value);
        designed.Voltage = [c.VoltageA.Value c.VoltageB.Value];
        designed.PlasticityTrains = c.TrainsEnabled.Value;
        trains = c.TrainTable.Data;
        if isempty(trains)
            trains = cell(0, numel(trainColumns));
        end
        designed.Trains = reshape(cell2struct(trains, trainColumns, 2), 1, []);
        rows = c.StepTable.Data;
        if isempty(rows)
            rows = cell(0, 5);
        end
        designed.Schedule = reshape(cell2struct(rows(:, 1:3), {'Kind', 'Channels', 'Minutes'}, 2), 1, []);
        candidate.Sleep.TestPulses = designed;
    end

    function refresh()
        % Compile the design, update the tables' derived columns, previews and status.
        candidate = collect();
        designed = candidate.Sleep.TestPulses;
        c = controls;
        c.StepTable.ColumnFormat = {lum.sleep.stepChoices(designed).Kinds, choices.Channels, ...
                                    'numeric', 'numeric', 'numeric'};
        lum.gui.Form.setEnable({c.InterPulseInterval}, strcmp(designed.Probe.Mode, 'Paired'));
        c.TrainTable.Enable = char(lum.gui.Form.onOff(designed.PlasticityTrains));   % A table wants text
        if strcmp(designed.Probe.Mode, 'Paired')
            c.ProbeNote.Text = sprintf(['Two %g ms pulses %g ms apart, every %g s: the second '...
                                        'pulse''s response against the first''s.'], ...
                                       1000 * designed.Probe.PulseWidth, ...
                                       1000 * designed.Probe.InterPulseInterval, ...
                                       designed.Probe.InterEpochInterval);
        else
            c.ProbeNote.Text = sprintf('One %g ms pulse every %g s.', 1000 * designed.Probe.PulseWidth, ...
                                       designed.Probe.InterEpochInterval);
        end
        trainText = arrayfun(@lum.sleep.describeTrain, designed.Trains, 'UniformOutput', false);
        if ~designed.PlasticityTrains
            trainText = [{'Off: no step may deliver a train.'}, trainText];
        end
        c.TrainNote.Text = strjoin(trainText, newline);

        check = candidate;
        check.Sleep.TestPulses.Enabled = true;
        try
            [plan, notes] = lum.sleep.validateTestPulses(check, rig);
        catch designError
            setStatus(designError.message, false);
            return
        end

        rows = c.StepTable.Data;
        for s = 1:numel(plan.Steps)
            rows{s, 4} = round(plan.Steps(s).Start / 60, 3);
            rows{s, 5} = plan.Steps(s).nEpochs;
            if ~isempty(plan.Steps(s).Train)
                rows{s, 3} = plan.Steps(s).Duration / 60;   % A train step lasts its trains
            end
        end
        c.StepTable.Data = rows;
        lum.gui.drawTestPulseSchedule(c.ScheduleAxes, plan, t);
        title(c.ScheduleAxes, sprintf('The session: %.4g min', plan.Duration / 60), ...
              'FontWeight', 'normal', 'FontSize', 10, 'Color', t.Ink);
        shown = min(max(selectedStep, 1), numel(plan.Steps));
        if plan.Steps(shown).nEpochs < 1
            shown = find([plan.Steps.nEpochs] > 0, 1);
        end
        lum.gui.drawTestPulseEpoch(c.EpochAxes, plan, shown, t);
        description = lum.sleep.describeTestPulses(check.Sleep.TestPulses, plan);
        message = sprintf('Ready: %s. %d epoch(s) of light.', description{2}, size(plan.Epochs, 1));
        if numel(notes) > 0
            message = sprintf('%s  %s', message, strjoin(notes, ' '));
        end
        setStatus(message, true);
    end

    function [ok, candidate] = apply()
        ok = false;
        candidate = collect();
        check = candidate;
        check.Sleep.TestPulses.Enabled = true;
        try
            lum.sleep.validateTestPulses(check, rig);
        catch designError
            setStatus(designError.message, false);
            uialert(fig, designError.message, 'Schedule not usable');
            return
        end
        refresh();   % So train steps carry the minutes their trains last
        candidate = collect();
        candidate.Sleep.TestPulses.Enabled = S.Sleep.TestPulses.Enabled;
        S = candidate;
        accepted = true;
        ok = true;
        delete(fig);
    end

    function onCancel()
        accepted = false;
        if isvalid(fig)
            delete(fig);
        end
    end

    function text = statusText()
        text = controls.Status.Text;
    end

    function setStatus(message, isGood)
        controls.Status.Text = message;
        if isGood
            controls.Status.FontColor = t.Good;
        else
            controls.Status.FontColor = t.Bad;
        end
        controls.Apply.Enable = lum.gui.Form.onOff(isGood);
    end

    function preset(name)
        % Replace the schedule with a common one; trains it needs are added and switched on.
        rows = {};
        switch name
            case 'Paired-pulse probes, 4 h'
                controls.ProbeMode.Value = 'Paired';
                rows = {'Probe', 'A and B', 240, 0, 0};
            case {'Probe, theta burst, probe', 'Probe, high frequency, probe'}
                trainName = 'Theta burst';
                if contains(name, 'high frequency')
                    trainName = 'High frequency';
                end
                ensureTrain(trainName);
                controls.TrainsEnabled.Value = true;
                rows = {'Probe', 'A and B', 30, 0, 0; trainName, 'A and B', 0, 0, 0; ...
                        'Probe', 'A and B', 210, 0, 0};
        end
        controls.Preset.Value = presets{1};
        if ~isempty(rows)
            controls.StepTable.Data = rows;
            selectedStep = 1;
        end
        refresh();
    end

    function ensureTrain(trainName)
        % Add a default train definition when the table no longer has one of that name.
        data = controls.TrainTable.Data;
        if ~isempty(data) && any(strcmp(data(:, 1), trainName))
            return
        end
        defaults = lum.defaultSettings().Sleep.TestPulses.Trains;
        controls.TrainTable.Data = [data; trainRows(defaults(strcmp({defaults.Name}, trainName)))];
    end

    function addStep()
        rows = controls.StepTable.Data;
        at = min(max(selectedStep, 0), size(rows, 1));
        rows = [rows(1:at, :); {'Probe', 'A and B', 30, 0, 0}; rows(at + 1:end, :)];
        controls.StepTable.Data = rows;
        selectedStep = at + 1;
        refresh();
    end

    function removeStep()
        rows = controls.StepTable.Data;
        if isempty(rows) || selectedStep < 1 || selectedStep > size(rows, 1)
            return
        end
        rows(selectedStep, :) = [];
        controls.StepTable.Data = rows;
        selectedStep = min(selectedStep, size(rows, 1));
        refresh();
    end

    function moveStep(offset)
        rows = controls.StepTable.Data;
        target = selectedStep + offset;
        if selectedStep < 1 || selectedStep > size(rows, 1) || target < 1 || target > size(rows, 1)
            return
        end
        rows([selectedStep target], :) = rows([target selectedStep], :);
        controls.StepTable.Data = rows;
        selectedStep = target;
        refresh();
    end

    function selectStep(k)
        selectedStep = k;
        refresh();
    end

    function addTrain()
        data = controls.TrainTable.Data;
        names = {};
        if ~isempty(data)
            names = data(:, 1);
        end
        name = 'Custom train';
        k = 1;
        while ismember(name, names)
            k = k + 1;
            name = sprintf('Custom train %d', k);
        end
        controls.TrainTable.Data = [data; {name, 20, 0.005, 1, 1, 20, 1, 60}];
        controls.TrainsEnabled.Value = true;
        refresh();
    end

    function removeTrain()
        data = controls.TrainTable.Data;
        if selectedTrain < 1 || selectedTrain > size(data, 1)
            return
        end
        data(selectedTrain, :) = [];
        controls.TrainTable.Data = data;
        selectedTrain = 0;
        refresh();
    end

    function onStepSelected(event)
        if ~isempty(event.Indices)
            selectStep(event.Indices(1, 1));
        end
    end

    function onTrainSelected(event)
        if ~isempty(event.Indices)
            selectedTrain = event.Indices(1, 1);
        end
    end
end


function rows = trainRows(trains)
% Train definitions as table rows.
rows = cell(numel(trains), 8);
for k = 1:numel(trains)
    d = trains(k);
    rows(k, :) = {char(d.Name), d.PulseFrequency, d.PulseWidth, d.PulsesPerBurst, ...
                  d.BurstFrequency, d.BurstsPerTrain, d.nTrains, d.TrainInterval};
end
end


function rows = stepRows(schedule)
% Schedule steps as table rows; the last two columns are filled in on refresh.
rows = cell(numel(schedule), 5);
for s = 1:numel(schedule)
    rows(s, :) = {char(schedule(s).Kind), char(schedule(s).Channels), schedule(s).Minutes, 0, 0};
end
end


function ax = previewAxes(parent)
ax = uiaxes(parent);
ax.Toolbar.Visible = 'off';
disableDefaultInteractivity(ax);
end


function buildHeader(parent, rig, t)
grid = uigridlayout(parent, [1 2], 'ColumnWidth', {48, '1x'}, 'Padding', 0, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
logoImage = lum.gui.logo(96);
if isempty(logoImage)
    uilabel(grid, 'Text', '');
else
    uiimage(grid, 'ImageSource', logoImage, 'ScaleMethod', 'fit');
end
titles = uigridlayout(grid, [2 1], 'RowHeight', {26, 20}, 'Padding', 0, 'RowSpacing', 0, ...
                      'BackgroundColor', t.Background);
uilabel(titles, 'Text', 'Test-pulse designer', 'FontSize', 18, 'FontWeight', 'bold', ...
        'FontColor', t.Ink);
uilabel(titles, 'Text', sprintf(['Probe pulses and plasticity trains on channels A and B, through '...
                                 'PulsePal, and the schedule a sleep session runs them in  |  %s, '...
                                 '%d states per state machine'], rig.MachineModel, rig.Limits.MaxStates), ...
        'FontColor', t.Muted);
end
