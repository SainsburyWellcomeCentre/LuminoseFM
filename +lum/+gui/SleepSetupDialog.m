function [S, accepted, app] = SleepSetupDialog(S, rig, varargin)
% lum.gui.SleepSetupDialog collects what a home-cage sleep session needs before it runs.
%
% The reduced counterpart of lum.gui.SetupDialog, for sessions that record sleep in
% the home cage (D11). There is no task, so no stimulus, light path, cue or runtime
% tier: only what the data file records about the animal (the same panels as the
% behaviour dialog, lum.gui.ExperimentForm), how long to record, the sync pulses sent
% on Flex2 and the session barcode that opens them, with a preview of that barcode.
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
% See also: lum.sleep.run, lum.sleep.validate, lum.gui.SessionTypeDialog

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

fig = uifigure('Name', 'LuminoseFM - sleep session setup', 'Position', [50 50 1180 800], ...
               'Color', t.Background, 'Visible', p.Results.Visible);
outer = uigridlayout(fig, [4 1], 'RowHeight', {58, '1x', 'fit', 34}, ...
                     'Padding', [14 10 14 12], 'RowSpacing', 8, 'BackgroundColor', t.Background);
buildHeader(outer, S, rig, t);

body = uigridlayout(outer, [1 2], 'ColumnWidth', {480, '1x'}, 'Padding', 0, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
height = @lum.gui.Form.panelHeight;
left = uigridlayout(body, [4 1], 'RowHeight', {height(2), height(2), height(6) + 50, '1x'}, ...
                    'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background);
controls = lum.gui.ExperimentForm.buildAnimal(left, S, choices, t);

form = lum.gui.Form.panel(left, 'Recording', 2, t, 190);
lum.gui.Form.label(form, 'Duration (min)', t);
controls.Duration = lum.gui.Form.number(form, S.Sleep.DurationMinutes, [0.01 1440], @refresh, false);
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

right = uigridlayout(body, [2 1], 'RowHeight', {'1x', 260}, 'Padding', 0, 'RowSpacing', 10, ...
                     'BackgroundColor', t.Background);
controls = lum.gui.ExperimentForm.merge(controls, ...
    lum.gui.ExperimentForm.buildRecordings(right, S, choices, t, @refresh));

barcode = S.Sync.Barcode;
box = uipanel(right, 'Title', 'Session barcode', 'FontWeight', 'bold', ...
              'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
barcodeGrid = uigridlayout(box, [1 2], 'ColumnWidth', {330, '1x'}, 'Padding', [10 8 10 8], ...
                           'ColumnSpacing', 12, 'BackgroundColor', t.Panel);
form = uigridlayout(barcodeGrid, [6 2], 'ColumnWidth', {160, '1x'}, ...
                    'RowHeight', repmat({26}, 1, 6), 'Padding', 0, 'RowSpacing', 6, ...
                    'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
lum.gui.Form.label(form, '', t);
controls.BarcodeEnabled = uicheckbox(form, 'Text', 'Session barcode', 'Value', barcode.Enabled, ...
                                     'ValueChangedFcn', @(~, ~) refresh());
lum.gui.Form.label(form, 'Bits', t);
controls.BarcodeBits = lum.gui.Form.number(form, barcode.nBits, [8 48], @refresh, true);
lum.gui.Form.label(form, 'Sleep marker pulse (s)', t);
controls.BarcodeSleepMarker = lum.gui.Form.number(form, lum.sync.sleepMarkerWidth(barcode), ...
                                                  [0.001 1], @refresh, false);
lum.gui.Form.label(form, '0 bit pulse (s)', t);
controls.BarcodeZero = lum.gui.Form.number(form, barcode.ZeroWidth, [0.001 1], @refresh, false);
lum.gui.Form.label(form, '1 bit pulse (s)', t);
controls.BarcodeOne = lum.gui.Form.number(form, barcode.OneWidth, [0.001 1], @refresh, false);
lum.gui.Form.label(form, 'Gap after each pulse (s)', t);
controls.BarcodeGap = lum.gui.Form.number(form, barcode.Gap, [0.001 1], @refresh, false);
controls.BarcodeAxes = uiaxes(barcodeGrid);
controls.BarcodeAxes.Toolbar.Visible = 'off';
disableDefaultInteractivity(controls.BarcodeAxes);

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
        message = sprintf('Ready to start: %g min, about %d pulses, one every %g s, %s.', ...
                          candidate.Sleep.DurationMinutes, ...
                          round(60 * candidate.Sleep.DurationMinutes / sleepSync.Interval), ...
                          sleepSync.Interval, lower(candidate.Sync.ModeNames{sleepSync.Mode}));
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
        candidate.Sleep.DurationMinutes = c.Duration.Value;
        candidate.Sleep.Sync = struct( ...
            'Mode', find(strcmp(c.SyncMode.Value, candidate.Sync.ModeNames), 1), ...
            'FixedWidth', c.FixedWidth.Value, 'MeanWidth', c.MeanWidth.Value, ...
            'WidthJitter', c.WidthJitter.Value, 'Interval', c.Interval.Value, ...
            'IntervalJitter', c.IntervalJitter.Value);
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
    end
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
uilabel(titles, 'Text', sprintf('Subject %s  |  home-cage sleep: session barcode and sync pulses', ...
                                subject), 'FontColor', t.Muted);
uilabel(grid, 'Text', sprintf('v%s  |  %s', lum.version(), rig.MachineModel), ...
        'FontColor', t.Muted, 'HorizontalAlignment', 'right');
end
