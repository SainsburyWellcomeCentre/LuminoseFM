function [S, accepted, app] = SleepSetupDialog(S, rig, varargin)
% lum.gui.SleepSetupDialog collects what a home-cage sleep session needs before it runs.
%
% The reduced counterpart of lum.gui.SetupDialog, for sessions that record sleep in
% the home cage (D11). There is no task, so no stimulus set, cue or runtime tier: what
% the data file records about the animal (the same panels as the behaviour dialog,
% lum.gui.ExperimentForm), how long to record, the sync pulses sent on Flex2 and the
% session barcode that opens them, with a preview of that barcode — and the test
% pulses (D13): whether light is sent on channels A and B, a summary and preview of
% the schedule, and the button that opens lum.gui.TestPulseDesigner to design it. With
% test pulses on, the recording lasts as long as their schedule, which the duration
% field then shows.
%
% Everything is validated on every edit by lum.sleep.validate, and Start stays
% disabled while anything fails.
%
% Arguments:
%   S    Settings struct, from the launch manager's settings file
%   rig  Channel map from RigConfig
%
% Options:
%   'Subject'  The subject chosen in the launch manager
%   'Wait'     false to return at once with the dialog open (for tests); default true
%   'Visible'  'on' (default) or 'off'
%
% Returns:
%   S         The edited settings, with S.Session.Type 'Sleep'
%   accepted  True if the operator started the session, false if they cancelled
%   app       With 'Wait' false: .Figure, .collect(), .refresh(), .start(),
%             .cancel(), .status() and .controls
%
% See also: lum.sleep.run, lum.sleep.validate, lum.gui.SessionTypeDialog,
%           lum.gui.TestPulseDesigner

p = inputParser;
p.FunctionName = 'lum.gui.SleepSetupDialog';
addParameter(p, 'Subject', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'Wait', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'Visible', 'on');
parse(p, varargin{:});
if strlength(string(p.Results.Subject)) > 0
    S.Meta.Subject = char(p.Results.Subject);
end
S.Session.Type = 'Sleep';

accepted = false;
t = lum.gui.theme();
choices = lum.experimentChoices();
modeNames = S.Sync.ModeNames([lum.SyncMode.FixedWidth, lum.SyncMode.JitteredWidth]);
drawnBarcode = [];
testPulses = S.Sleep.TestPulses;     % The design; its Enabled flag is the checkbox below
ownDuration = S.Sleep.DurationMinutes;  % The recording length without test pulses
drawnTestPulses = [];
designedPlan = [];

fig = uifigure('Name', 'LuminoseFM - sleep session setup', 'Position', [30 50 1580 800], ...
               'Color', t.Background, 'Visible', p.Results.Visible);
outer = uigridlayout(fig, [4 1], 'RowHeight', {58, '1x', 'fit', 34}, ...
                     'Padding', [14 10 14 12], 'RowSpacing', 8, 'BackgroundColor', t.Background);
buildHeader(outer, S, rig, t);

body = uigridlayout(outer, [1 3], 'ColumnWidth', {470, '1x', 480}, 'Padding', 0, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
height = @lum.gui.Form.panelHeight;
left = uigridlayout(body, [4 1], 'RowHeight', {height(2), height(2), height(6) + 50, '1x'}, ...
                    'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background);
controls = lum.gui.ExperimentForm.buildAnimal(left, S, choices, t);

form = lum.gui.Form.panel(left, 'Recording', 2, t, 190);
lum.gui.Form.label(form, 'Duration (min)', t);
controls.Duration = lum.gui.Form.number(form, S.Sleep.DurationMinutes, [0.01 1440], @durationEdited, false);
lum.gui.Form.label(form, 'Sync TTL', t);
controls.UseSync = uicheckbox(form, 'Text', 'Flex2 output', 'Value', S.Session.UseSync, ...
                              'ValueChangedFcn', @(~, ~) refresh());

sync = S.Sleep.Sync;
form = lum.gui.Form.panel(left, 'Sync pulses', 7, t, 190);
form.RowHeight = {26, 26, 26, 26, 26, 26, 44};
lum.gui.Form.label(form, 'Pulse widths', t);
controls.SyncMode = uidropdown(form, 'Items', modeNames, ...
    'Value', S.Sync.ModeNames{sync.Mode}, 'ValueChangedFcn', @(~, ~) refresh());
lum.gui.Form.label(form, 'Fixed width (s)', t);
controls.FixedWidth = lum.gui.Form.number(form, sync.FixedWidth, [0.0001 10], @refresh, false);
lum.gui.Form.label(form, 'Mean width (s)', t);
controls.MeanWidth = lum.gui.Form.number(form, sync.MeanWidth, [0.0001 10], @refresh, false);
lum.gui.Form.label(form, 'Width jitter (+/- s)', t);
controls.WidthJitter = lum.gui.Form.number(form, sync.WidthJitter, [0 10], @refresh, false);
lum.gui.Form.label(form, 'Interval (s)', t);
controls.Interval = lum.gui.Form.number(form, sync.Interval, [0.002 3600], @refresh, false);
lum.gui.Form.label(form, 'Interval jitter (+/- s)', t);
controls.IntervalJitter = lum.gui.Form.number(form, sync.IntervalJitter, [0 3600], @refresh, false);
lum.gui.Form.label(form, '', t);
controls.SyncNote = lum.gui.Form.note(form, '', t);

controls = lum.gui.ExperimentForm.merge(controls, lum.gui.ExperimentForm.buildNotes(left, S, t));

middle = uigridlayout(body, [2 1], 'RowHeight', {'1x', 260}, 'Padding', 0, 'RowSpacing', 10, ...
                      'BackgroundColor', t.Background);
controls = lum.gui.ExperimentForm.merge(controls, ...
    lum.gui.ExperimentForm.buildRecordings(middle, S, choices, t, @refresh));

barcode = S.Sync.Barcode;
box = uipanel(middle, 'Title', 'Session barcode', 'FontWeight', 'bold', ...
              'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
barcodeGrid = uigridlayout(box, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [10 8 10 8], ...
                           'RowSpacing', 6, 'BackgroundColor', t.Panel);
form = uigridlayout(barcodeGrid, [3 4], 'ColumnWidth', {150, '1x', 150, '1x'}, ...
                    'RowHeight', repmat({26}, 1, 3), 'Padding', 0, 'RowSpacing', 6, ...
                    'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
% Placed cell by cell: the checkbox spans the first label and field.
controls.BarcodeEnabled = uicheckbox(form, 'Text', 'Session barcode', 'Value', barcode.Enabled, ...
                                     'ValueChangedFcn', @(~, ~) refresh());
place(controls.BarcodeEnabled, 1, [1 2]);
place(uilabel(form, 'Text', 'Bits', 'FontColor', t.Ink), 1, 3);
controls.BarcodeBits = place(lum.gui.Form.number(form, barcode.nBits, [8 48], @refresh, true), 1, 4);
place(uilabel(form, 'Text', 'Sleep marker pulse (s)', 'FontColor', t.Ink), 2, 1);
controls.BarcodeSleepMarker = place(lum.gui.Form.number(form, lum.sync.sleepMarkerWidth(barcode), ...
                                                        [0.001 1], @refresh, false), 2, 2);
place(uilabel(form, 'Text', '0 bit pulse (s)', 'FontColor', t.Ink), 2, 3);
controls.BarcodeZero = place(lum.gui.Form.number(form, barcode.ZeroWidth, [0.001 1], @refresh, false), 2, 4);
place(uilabel(form, 'Text', '1 bit pulse (s)', 'FontColor', t.Ink), 3, 1);
controls.BarcodeOne = place(lum.gui.Form.number(form, barcode.OneWidth, [0.001 1], @refresh, false), 3, 2);
place(uilabel(form, 'Text', 'Gap after each pulse (s)', 'FontColor', t.Ink), 3, 3);
controls.BarcodeGap = place(lum.gui.Form.number(form, barcode.Gap, [0.001 1], @refresh, false), 3, 4);
controls.BarcodeAxes = previewAxes(barcodeGrid);

box = uipanel(body, 'Title', 'Test pulses', 'FontWeight', 'bold', ...
              'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
grid = uigridlayout(box, [6 1], 'RowHeight', {26, 118, '1x', 160, 32, 58}, ...
                    'Padding', [10 8 10 8], 'RowSpacing', 8, 'BackgroundColor', t.Panel);
controls.TestPulsesEnabled = uicheckbox(grid, 'Text', 'Send test pulses on channels A and B', ...
                                        'Value', testPulses.Enabled, 'ValueChangedFcn', @(~, ~) refresh());
controls.TestPulseSummary = lum.gui.Form.note(grid, '', t);
controls.TestScheduleAxes = previewAxes(grid);
controls.TestEpochAxes = previewAxes(grid);
controls.DesignTestPulses = uibutton(grid, 'Text', ['Design test-pulse schedule' char(8230)], ...
                                     'FontWeight', 'bold', 'ButtonPushedFcn', @(~, ~) designTestPulses());
lum.gui.Form.note(grid, ['Light goes out through PulsePal, programmed as for behaviour: a session with '...
                         'test pulses does not start unless PulsePal is connected and answers, and '...
                         'stops if it stops answering.'], t);

controls.Status = uilabel(outer, 'Text', '', 'WordWrap', 'on', 'FontSize', 12);
footer = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 110, 150}, 'Padding', 0, ...
                      'ColumnSpacing', 8, 'BackgroundColor', t.Background);
lum.gui.Form.note(footer, sprintf(['%s  |  The sleep barcode opens and closes with %g ms markers, the '...
                                   'behaviour barcode with %g ms, so recordings say which kind of '...
                                   'session they hold.'], rig.MachineModel, ...
                                  1000 * lum.sync.sleepMarkerWidth(barcode), 1000 * barcode.MarkerWidth), t);
uibutton(footer, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
controls.Start = uibutton(footer, 'Text', 'Start recording', 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Accent, 'FontColor', [1 1 1], ...
                          'ButtonPushedFcn', @(~, ~) onStart());

refresh();
app = struct('Figure', fig, 'collect', @collectSettings, 'refresh', @refresh, ...
             'start', @onStart, 'cancel', @onCancel, 'status', @statusText, ...
             'controls', controls);
if p.Results.Wait
    uiwait(fig);
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
            lum.sleep.validate(candidate, rig);
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

    function durationEdited()
        % The duration field is only editable with test pulses off, and then it is the
        % recording's own length.
        ownDuration = controls.Duration.Value;
        refresh();
    end

    function designTestPulses()
        try
            candidate = collectSettings();
        catch readError
            uialert(fig, readError.message, 'Settings not usable');
            return
        end
        [designed, ok] = lum.gui.TestPulseDesigner(candidate, rig);
        if ~ok || ~isvalid(fig)
            return
        end
        testPulses = designed.Sleep.TestPulses;
        controls.TestPulsesEnabled.Value = true;   % A schedule chosen is a schedule wanted
        refresh();
    end

    function refresh()
        % Read every control, bring the dialog's appearance in line, and validate.
        try
            candidate = collectSettings();
        catch readError
            setStatus(readError.message, false);
            return
        end
        updateAppearance(candidate);
        try
            notes = lum.sleep.validate(candidate, rig);
        catch validationError
            setStatus(validationError.message, false);
            return
        end
        sleepSync = candidate.Sleep.Sync;
        minutes = candidate.Sleep.DurationMinutes;
        if candidate.Sleep.TestPulses.Enabled && ~isempty(designedPlan)
            minutes = designedPlan.Duration / 60;
        end
        message = sprintf('Ready to start: %.4g min, about %d sync pulses, one every %g s, %s.', ...
                          minutes, round(60 * minutes / sleepSync.Interval), ...
                          sleepSync.Interval, lower(candidate.Sync.ModeNames{sleepSync.Mode}));
        if candidate.Sleep.TestPulses.Enabled && ~isempty(designedPlan)
            message = sprintf('%s  Test pulses: %d epoch(s) of light in %d step(s).', message, ...
                              size(designedPlan.Epochs, 1), numel(designedPlan.Steps));
        end
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
        controls.Start.Enable = lum.gui.Form.onOff(isGood);
    end

    function candidate = collectSettings()
        % Read every control back into a settings struct; everything no control shows
        % — the behaviour tiers — comes from S untouched.
        c = controls;
        candidate = S;
        candidate.Meta = lum.gui.ExperimentForm.read(c, candidate.Meta);
        candidate.Session.Type = 'Sleep';
        candidate.Session.UseSync = c.UseSync.Value;
        candidate.Sleep.DurationMinutes = ownDuration;
        candidate.Sleep.Sync = struct( ...
            'Mode', find(strcmp(c.SyncMode.Value, candidate.Sync.ModeNames), 1), ...
            'FixedWidth', c.FixedWidth.Value, 'MeanWidth', c.MeanWidth.Value, ...
            'WidthJitter', c.WidthJitter.Value, 'Interval', c.Interval.Value, ...
            'IntervalJitter', c.IntervalJitter.Value);
        candidate.Sleep.TestPulses = testPulses;
        candidate.Sleep.TestPulses.Enabled = c.TestPulsesEnabled.Value;
        candidate.Sync.Barcode.Enabled = c.BarcodeEnabled.Value;
        candidate.Sync.Barcode.nBits = round(c.BarcodeBits.Value);
        candidate.Sync.Barcode.SleepMarkerWidth = c.BarcodeSleepMarker.Value;
        candidate.Sync.Barcode.ZeroWidth = c.BarcodeZero.Value;
        candidate.Sync.Barcode.OneWidth = c.BarcodeOne.Value;
        candidate.Sync.Barcode.Gap = c.BarcodeGap.Value;
    end

    function updateAppearance(candidate)
        c = controls;
        lum.gui.ExperimentForm.update(c, candidate.Meta);
        mode = candidate.Sleep.Sync.Mode;
        lum.gui.Form.setEnable({c.FixedWidth}, mode == lum.SyncMode.FixedWidth);
        lum.gui.Form.setEnable({c.MeanWidth, c.WidthJitter}, mode == lum.SyncMode.JitteredWidth);
        if mode == lum.SyncMode.FixedWidth
            c.SyncNote.Text = 'Every pulse the same width: enough to count pulses.';
        else
            c.SyncNote.Text = ['Each width drawn within the jitter of the mean, so a recording '...
                               'is matched to the data file pulse by pulse.'];
        end
        lum.gui.Form.setEnable({c.BarcodeBits, c.BarcodeSleepMarker, c.BarcodeZero, ...
                                c.BarcodeOne, c.BarcodeGap}, candidate.Sync.Barcode.Enabled);
        if ~isequal(candidate.Sync.Barcode, drawnBarcode)
            lum.gui.Form.drawBarcode(c.BarcodeAxes, candidate.Sync.Barcode, 'Sleep', t);
            drawnBarcode = candidate.Sync.Barcode;
        end

        design = candidate.Sleep.TestPulses;
        if ~isequal(design, drawnTestPulses)
            drawTestPulses(design);
            drawnTestPulses = design;
        end
        % With test pulses the recording lasts as long as their schedule.
        on = design.Enabled && ~isempty(designedPlan);
        lum.gui.Form.setEnable({c.Duration}, ~design.Enabled);
        if on
            c.Duration.Value = min(max(designedPlan.Duration / 60, 0.01), 1440);
        else
            c.Duration.Value = ownDuration;
        end
    end

    function drawTestPulses(design)
        % Summarise and preview the schedule, whether or not it is switched on.
        c = controls;
        design.Enabled = true;
        try
            designedPlan = lum.sleep.testPulsePlan(design);
        catch planError
            designedPlan = [];
            c.TestPulseSummary.Text = planError.message;
            c.TestPulseSummary.FontColor = t.Bad;
            cla(c.TestScheduleAxes);
            cla(c.TestEpochAxes);
            return
        end
        lines = lum.sleep.describeTestPulses(design, designedPlan);
        if ~c.TestPulsesEnabled.Value
            lines = [{'Off. When switched on:'}, lines];
        end
        c.TestPulseSummary.Text = strjoin(lines, newline);
        c.TestPulseSummary.FontColor = t.Muted;
        lum.gui.drawTestPulseSchedule(c.TestScheduleAxes, designedPlan, t);
        lum.gui.drawTestPulseEpoch(c.TestEpochAxes, designedPlan, ...
                                   find([designedPlan.Steps.nEpochs] > 0, 1), t);
    end
end


function ax = previewAxes(parent)
ax = uiaxes(parent);
ax.Toolbar.Visible = 'off';
disableDefaultInteractivity(ax);
end


function component = place(component, row, column)
% Put a component in a grid cell (or span).
component.Layout.Row = row;
component.Layout.Column = column;
end


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
uilabel(titles, 'Text', 'LuminoseFM  |  sleep session setup', 'FontSize', 18, ...
        'FontWeight', 'bold', 'FontColor', t.Ink);
subject = S.Meta.Subject;
if isempty(subject)
    subject = 'no subject chosen';
end
uilabel(titles, 'Text', sprintf(['Subject %s  |  home-cage sleep: session barcode, sync pulses and '...
                                 'test pulses'], subject), 'FontColor', t.Muted);
uilabel(grid, 'Text', sprintf('v%s  |  %s', lum.version(), rig.MachineModel), ...
        'FontColor', t.Muted, 'HorizontalAlignment', 'right');
end
