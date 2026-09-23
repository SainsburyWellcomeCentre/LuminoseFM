function [S, accepted, app] = EphysSetupDialog(S, rig, varargin)
% lum.gui.EphysSetupDialog collects what an ePhys calibration session needs before it runs.
%
% An ePhys calibration session (D18) sends light pulses whose intensity or pairing
% changes step by step, for the response recorded on the Neuropixels probe: an
% input-output curve and a paired-pulse ratio (lum.ephys.plan). This dialog sets:
%
%   ePhys calibration  the animal and what is recorded (lum.gui.ExperimentForm); the
%                      pulses (channels, width, interval between epochs, repeats per
%                      step, order); the input-output curve (lowest and highest
%                      intensity per channel, levels); the paired-pulse ratio
%                      (intensity per channel, inter-pulse intervals); the sync pulses,
%                      the house light and the session barcode (ePhys marker); with a
%                      summary and a preview of the steps and their currents
%   Doric LED          the LED driver, fiber bundle, limits and calibrations
%                      (lum.gui.DoricSetup)
%   Cameras            video (lum.gui.CameraSetup)
%
% Intensities are shown and typed in mW/mm2 where a channel's light path (its cable,
% calibrated on that channel) is calibrated, in mA where it is not
% (lum.gui.IntensityField); settings keep both forms (S.Ephys). By default the curve runs
% from 0 to 12 mW/mm2, or to the most the channel gives if less, and the pairs are at
% 8 mW/mm2; uncalibrated, from 0 mA to the channel's limit, and pairs at 100 mA. Everything is
% validated on every edit by lum.ephys.validate, and Start stays disabled while anything
% fails.
%
% Arguments:
%   S    Settings struct, from the launch manager's settings file
%   rig  Channel map from RigConfig
%
% Options:
%   'Subject'   The subject chosen in the launch manager
%   'Wait'      false to return at once with the dialog open (for tests); default true
%   'Visible'   'on' (default) or 'off'
%   'DoricLED'  The protocol's lum.dev.DoricLED, for the Doric LED tab; [] for none
%   'CalibrationFolder'  Where LED calibrations are read and saved (tests pass their own)
%
% Returns:
%   S         The edited settings, with S.Session.Type 'EphysCalibration'
%   accepted  True if the operator started the session, false if they cancelled
%   app       With 'Wait' false: .Figure, .collect(), .refresh(), .start(), .cancel(),
%             .status(), .controls, .helpLine, .cameras and .doric
%
% See also: lum.ephys.plan, lum.ephys.validate, lum.sleep.run, lum.gui.SleepSetupDialog

p = inputParser;
p.FunctionName = 'lum.gui.EphysSetupDialog';
addParameter(p, 'Subject', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'Wait', true, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'Visible', 'on');
addParameter(p, 'DoricLED', []);
addParameter(p, 'CalibrationFolder', '');
parse(p, varargin{:});
if strlength(string(p.Results.Subject)) > 0
    S.Meta.Subject = char(p.Results.Subject);
end
S.Session.Type = 'EphysCalibration';

accepted = false;
t = lum.gui.theme();
choices = lum.experimentChoices();
modeNames = S.Sync.ModeNames([lum.SyncMode.FixedWidth, lum.SyncMode.JitteredWidth]);
drawnKey = {};
drawnBarcode = [];
e = S.Ephys;

fig = uifigure('Name', 'LuminoseFM - ePhys calibration setup', 'Position', [30 50 1580 820], ...
               'Color', t.Background, 'Visible', p.Results.Visible);
lum.gui.Form.waitForView(fig);  % Before any content (see waitForView)
outer = uigridlayout(fig, [5 1], 'RowHeight', {58, '1x', 46, 'fit', 34}, ...
                     'Padding', [14 10 14 12], 'RowSpacing', 8, 'BackgroundColor', t.Background);
buildHeader(outer, S, rig, t);

tabGroup = uitabgroup(outer);
sessionTab = uitab(tabGroup, 'Title', 'ePhys calibration', 'BackgroundColor', t.Background);
doricTab = uitab(tabGroup, 'Title', 'Doric LED', 'BackgroundColor', t.Background);
cameraTab = uitab(tabGroup, 'Title', 'Cameras', 'BackgroundColor', t.Background);
body = uigridlayout(sessionTab, [1 3], 'ColumnWidth', {430, 520, '1x'}, 'Padding', 8, ...
                    'ColumnSpacing', 12, 'BackgroundColor', t.Background);
height = @lum.gui.Form.panelHeight;
label = @(form, caption) lum.gui.Form.label(form, caption, t);

% Left: the animal, the recording, the sync pulses.
left = uigridlayout(body, [4 1], 'RowHeight', {height(2), height(2), height(7) + 18, '1x'}, ...
                    'Padding', 0, 'RowSpacing', 10, 'BackgroundColor', t.Background);
controls = lum.gui.ExperimentForm.buildAnimal(left, S, choices, t);
form = lum.gui.Form.panel(left, 'Recording', 2, t, 170);
label(form, 'Sync TTL');
controls.UseSync = uicheckbox(form, 'Text', 'Flex2 output', 'Value', S.Session.UseSync, ...
                              'ValueChangedFcn', @(~, ~) refresh());
label(form, 'House light');
controls.HouseLight = uicheckbox(form, 'Text', 'On', 'Value', e.HouseLight, ...
    'Tooltip', ['The white house light (PulsePal output 3) as the session starts; switched during it '...
                'from the session window''s header.'], 'ValueChangedFcn', @(~, ~) refresh());
sync = e.Sync;
form = lum.gui.Form.panel(left, 'Sync pulses', 7, t, 170);
form.RowHeight = {26, 26, 26, 26, 26, 26, 44};
label(form, 'Pulse widths');
controls.SyncMode = uidropdown(form, 'Items', modeNames, 'Value', S.Sync.ModeNames{sync.Mode}, ...
                               'ValueChangedFcn', @(~, ~) refresh());
label(form, 'Fixed width (s)');
controls.FixedWidth = lum.gui.Form.number(form, sync.FixedWidth, [0.0001 10], @refresh, false);
label(form, 'Mean width (s)');
controls.MeanWidth = lum.gui.Form.number(form, sync.MeanWidth, [0.0001 10], @refresh, false);
label(form, 'Width jitter (+/- s)');
controls.WidthJitter = lum.gui.Form.number(form, sync.WidthJitter, [0 10], @refresh, false);
label(form, 'Interval (s)');
controls.Interval = lum.gui.Form.number(form, sync.Interval, [0.002 3600], @refresh, false);
label(form, 'Interval jitter (+/- s)');
controls.IntervalJitter = lum.gui.Form.number(form, sync.IntervalJitter, [0 3600], @refresh, false);
label(form, '');
lum.gui.Form.note(form, ['Sync pulses on a clock, as in a sleep session, alongside the light: they align '...
                         'the recording through the session.'], t);
controls = lum.gui.ExperimentForm.merge(controls, lum.gui.ExperimentForm.buildNotes(left, S, t));

% Middle: the pulses and the two protocols.
middle = uigridlayout(body, [4 1], 'RowHeight', {height(6), 230, 160, '1x'}, 'Padding', 0, ...
                      'RowSpacing', 10, 'BackgroundColor', t.Background);
form = lum.gui.Form.panel(middle, 'Pulses', 6, t, 200);
label(form, 'Channels');
controls.Channels = uidropdown(form, 'Items', {'A', 'B', 'A and B'}, 'Value', e.Channels, ...
    'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', 'The channels lit: A, B, or both together, each at its own intensity.');
label(form, 'Pulse width (ms)');
controls.PulseWidth = lum.gui.Form.number(form, 1000 * e.PulseWidth, [0.1 10000], @refresh, false);
controls.PulseWidth.Tooltip = 'How long each pulse of light lasts: constant light, gated by Bpod.';
label(form, 'Interval between epochs (s)');
controls.EpochInterval = lum.gui.Form.number(form, e.InterEpochInterval, [0.01 3600], @refresh, false);
controls.EpochInterval.Tooltip = 'Onset to onset, from one single pulse or pair to the next.';
label(form, 'Repeats per step');
controls.Repeats = lum.gui.Form.number(form, e.Repeats, [1 10000], @refresh, true);
controls.Repeats.Tooltip = 'Epochs sent at each intensity (input-output) or each interval (paired-pulse).';
label(form, 'Order of steps');
controls.Order = uidropdown(form, 'Items', {'Ascending', 'Descending', 'Shuffled'}, 'Value', e.Order, ...
    'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', 'The order of the steps within each protocol. Shuffled draws it from the seed.');
label(form, 'Seed');
controls.Seed = lum.gui.Form.number(form, e.Seed, [0 2^31], @refresh, true);
controls.Seed.Tooltip = 'Seeds the shuffled order, so a session can be repeated in the same order.';

box = uipanel(middle, 'Title', 'Input-output curve', 'FontWeight', 'bold', ...
              'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
grid = uigridlayout(box, [6 3], 'ColumnWidth', {200, 100, '1x'}, 'RowHeight', {24, 26, 26, 26, 26, 26}, ...
                    'Padding', [10 8 10 8], 'RowSpacing', 6, 'ColumnSpacing', 8, 'BackgroundColor', t.Panel);
controls.IOEnabled = uicheckbox(grid, 'Text', 'Send an input-output curve', 'Value', e.InputOutput.Enabled, ...
                                'ValueChangedFcn', @(~, ~) refresh());
controls.IOEnabled.Layout.Column = [1 3];
fields = struct();
names = {'A', 'B'};
for ch = 1:2
    label(grid, sprintf('Channel %s from', names{ch}));
    fields.IOMin{ch} = lum.gui.IntensityField(grid, e.InputOutput.MinmA(ch), @refresh, ...
        'Irradiance', e.InputOutput.MinIrradiancemWmm2(ch), 'LimitmA', S.Doric.MaxCurrentmA(ch), ...
        'Tooltip', 'The lowest intensity of the curve; 0 gives pulses with no light, a baseline.');
end
for ch = 1:2
    label(grid, sprintf('Channel %s to', names{ch}));
    fields.IOMax{ch} = lum.gui.IntensityField(grid, e.InputOutput.MaxmA(ch), @refresh, 'AllowEmpty', true, ...
        'Irradiance', e.InputOutput.MaxIrradiancemWmm2(ch), 'LimitmA', S.Doric.MaxCurrentmA(ch), ...
        'Tooltip', ['The highest intensity of the curve. Above what the channel gives, or empty, the '...
                    'curve ends at the most it gives within its limit.']);
end
label(grid, 'Levels');
controls.IOLevels = lum.gui.Form.number(grid, e.InputOutput.nLevels, [2 100], @refresh, true);
controls.IOLevels.Tooltip = ['Steps from the lowest to the highest intensity, evenly spaced: in irradiance '...
                             'when calibrated, in mA when not.'];

box = uipanel(middle, 'Title', 'Paired-pulse ratio', 'FontWeight', 'bold', ...
              'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
grid = uigridlayout(box, [4 3], 'ColumnWidth', {200, 100, '1x'}, 'RowHeight', {24, 26, 26, 26}, ...
                    'Padding', [10 8 10 8], 'RowSpacing', 6, 'ColumnSpacing', 8, 'BackgroundColor', t.Panel);
controls.PPEnabled = uicheckbox(grid, 'Text', 'Send paired pulses', 'Value', e.PairedPulse.Enabled, ...
                                'ValueChangedFcn', @(~, ~) refresh());
controls.PPEnabled.Layout.Column = [1 3];
for ch = 1:2
    label(grid, sprintf('Channel %s intensity', names{ch}));
    fields.PP{ch} = lum.gui.IntensityField(grid, e.PairedPulse.CurrentmA(ch), @refresh, ...
        'Irradiance', e.PairedPulse.IrradiancemWmm2(ch), 'LimitmA', S.Doric.MaxCurrentmA(ch), ...
        'Tooltip', 'The intensity of both pulses of every pair.');
end
label(grid, 'Inter-pulse intervals (ms)');
controls.PPIntervals = uieditfield(grid, 'text', 'Value', numbersText(1000 * e.PairedPulse.Intervals), ...
    'ValueChangedFcn', @(~, ~) refresh(), ...
    'Tooltip', 'Onset to onset within a pair, one step each: for example 20 30 50 75 100 200 300 500.');
controls.PPIntervals.Layout.Column = [2 3];
controls.Summary = lum.gui.Form.note(middle, '', t);

% Right: the steps, and the barcode.
right = uigridlayout(body, [3 1], 'RowHeight', {'1x', '1x', 230}, 'Padding', 0, 'RowSpacing', 10, ...
                     'BackgroundColor', t.Background);
controls.ScheduleAxes = previewAxes(right);
controls.CurrentAxes = previewAxes(right);
barcode = S.Sync.Barcode;
box = uipanel(right, 'Title', 'Session barcode', 'FontWeight', 'bold', ...
              'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
barcodeGrid = uigridlayout(box, [2 1], 'RowHeight', {'fit', '1x'}, 'Padding', [10 8 10 8], ...
                           'RowSpacing', 6, 'BackgroundColor', t.Panel);
form = uigridlayout(barcodeGrid, [2 4], 'ColumnWidth', {150, '1x', 150, '1x'}, ...
                    'RowHeight', {26, 26}, 'Padding', 0, 'RowSpacing', 6, ...
                    'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
controls.BarcodeEnabled = uicheckbox(form, 'Text', 'Session barcode', 'Value', barcode.Enabled, ...
                                     'ValueChangedFcn', @(~, ~) refresh());
controls.BarcodeEnabled.Layout.Column = [1 2];
uilabel(form, 'Text', 'Bits', 'FontColor', t.Ink);
controls.BarcodeBits = lum.gui.Form.number(form, barcode.nBits, [8 48], @refresh, true);
uilabel(form, 'Text', 'ePhys marker pulse (s)', 'FontColor', t.Ink);
controls.BarcodeMarker = lum.gui.Form.number(form, lum.sync.markerWidth(barcode, 'EphysCalibration'), ...
                                             [0.001 2], @refresh, false);
controls.BarcodeMarker.Tooltip = ['The marker that opens and closes this session''s barcode: longer than the '...
                                  'sleep marker, which is longer than the behaviour marker.'];
uilabel(form, 'Text', '', 'FontColor', t.Ink);
uilabel(form, 'Text', '', 'FontColor', t.Ink);
controls.BarcodeAxes = previewAxes(barcodeGrid);

cameras = lum.gui.CameraSetup(cameraTab, S.Camera, t, @refresh, 'Subject', S.Meta.Subject);
controls.Tabs.Cameras = cameraTab;
doric = lum.gui.DoricSetup(doricTab, S, t, @refresh, p.Results.DoricLED, ...
                           'CalibrationFolder', p.Results.CalibrationFolder, ...
                           'Intensity', 'EphysCalibration');
controls.Tabs.Doric = doricTab;

controls.Help = uilabel(outer, 'Text', '', 'WordWrap', 'on', 'FontSize', 11, ...
                        'FontColor', t.Ink, 'BackgroundColor', t.AccentSoft, ...
                        'VerticalAlignment', 'top');
controls.Status = uilabel(outer, 'Text', '', 'WordWrap', 'on', 'FontSize', 12);
footer = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 110, 150}, 'Padding', 0, ...
                      'ColumnSpacing', 8, 'BackgroundColor', t.Background);
lum.gui.Form.note(footer, sprintf(['%s  |  Barcode markers: behaviour %g ms, sleep %g ms, ePhys calibration '...
                                   '%g ms, so a recording says which kind of session it holds.'], ...
                                  rig.MachineModel, 1000 * barcode.MarkerWidth, ...
                                  1000 * lum.sync.sleepMarkerWidth(barcode), ...
                                  1000 * lum.sync.markerWidth(barcode, 'EphysCalibration')), t);
uibutton(footer, 'Text', 'Cancel', 'ButtonPushedFcn', @(~, ~) onCancel());
controls.Start = uibutton(footer, 'Text', 'Start recording', 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Accent, 'FontColor', [1 1 1], ...
                          'ButtonPushedFcn', @(~, ~) onStart());

helpLine = lum.gui.HelpLine(fig, controls.Help, ...
                            'Point at a field, or use it, to see what it does here.');
helpLine.registerTooltips();
cameras.useHelpLine(helpLine);
refresh();
app = struct('Figure', fig, 'collect', @collectSettings, 'refresh', @refresh, ...
             'start', @onStart, 'cancel', @onCancel, 'status', @statusText, ...
             'controls', controls, 'fields', fields, 'helpLine', helpLine, 'cameras', cameras, ...
             'doric', doric);
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
            lum.ephys.validate(candidate, rig, doric.calibrations());
        catch settingsError
            setStatus(settingsError.message, false);
            uialert(fig, settingsError.message, 'Settings not usable');
            return
        end
        S = candidate;
        accepted = true;
        ok = true;
        cameras.close();
        doric.close();
        delete(fig);
    end

    function text = statusText()
        text = controls.Status.Text;
    end

    function refresh()
        try
            candidate = collectSettings();
        catch readError
            setStatus(readError.message, false);
            return
        end
        updateAppearance(candidate);
        try
            [plan, notes] = lum.ephys.validate(candidate, rig, doric.calibrations());
        catch validationError
            setStatus(validationError.message, false);
            clearPreview();
            return
        end
        showPlan(candidate, plan);
        cameraNote = cameras.problem(candidate.Camera);
        if ~isempty(cameraNote)
            notes{end+1} = cameraNote;
        end
        doricNote = doric.problem(candidate);
        if ~isempty(doricNote)
            notes{end+1} = doricNote;
        end
        setStatus(sprintf('Ready to start.  %s', strjoin(notes, ' ')), true);
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
        c = controls;
        candidate = S;
        candidate.Meta = lum.gui.ExperimentForm.read(c, candidate.Meta);
        candidate.Session.Type = 'EphysCalibration';
        candidate.Session.UseSync = c.UseSync.Value;
        candidate.Ephys.HouseLight = c.HouseLight.Value;
        candidate.Ephys.Sync = struct( ...
            'Mode', find(strcmp(c.SyncMode.Value, candidate.Sync.ModeNames), 1), ...
            'FixedWidth', c.FixedWidth.Value, 'MeanWidth', c.MeanWidth.Value, ...
            'WidthJitter', c.WidthJitter.Value, 'Interval', c.Interval.Value, ...
            'IntervalJitter', c.IntervalJitter.Value);
        candidate.Ephys.Channels = c.Channels.Value;
        candidate.Ephys.PulseWidth = c.PulseWidth.Value / 1000;
        candidate.Ephys.InterEpochInterval = c.EpochInterval.Value;
        candidate.Ephys.Repeats = round(c.Repeats.Value);
        candidate.Ephys.Order = c.Order.Value;
        candidate.Ephys.Seed = round(c.Seed.Value);
        candidate.Ephys.InputOutput.Enabled = c.IOEnabled.Value;
        candidate.Ephys.InputOutput.MinmA = [fields.IOMin{1}.currentmA(), fields.IOMin{2}.currentmA()];
        candidate.Ephys.InputOutput.MaxmA = [fields.IOMax{1}.currentmA(), fields.IOMax{2}.currentmA()];
        candidate.Ephys.InputOutput.MinIrradiancemWmm2 = [fields.IOMin{1}.irradiance(), fields.IOMin{2}.irradiance()];
        candidate.Ephys.InputOutput.MaxIrradiancemWmm2 = [fields.IOMax{1}.irradiance(), fields.IOMax{2}.irradiance()];
        candidate.Ephys.InputOutput.nLevels = round(c.IOLevels.Value);
        candidate.Ephys.PairedPulse.Enabled = c.PPEnabled.Value;
        candidate.Ephys.PairedPulse.CurrentmA = [fields.PP{1}.currentmA(), fields.PP{2}.currentmA()];
        candidate.Ephys.PairedPulse.IrradiancemWmm2 = [fields.PP{1}.irradiance(), fields.PP{2}.irradiance()];
        candidate.Ephys.PairedPulse.Intervals = ...
            lum.gui.parseNumbers(c.PPIntervals.Value, 'Inter-pulse intervals') / 1000;
        candidate.Sync.Barcode.Enabled = c.BarcodeEnabled.Value;
        candidate.Sync.Barcode.nBits = round(c.BarcodeBits.Value);
        candidate.Sync.Barcode.EphysMarkerWidth = c.BarcodeMarker.Value;
        candidate.Camera = cameras.read(candidate.Camera);
        candidate = doric.read(candidate);
    end

    function updateAppearance(candidate)
        c = controls;
        lum.gui.ExperimentForm.update(c, candidate.Meta);
        cameras.update(candidate.Camera);
        doric.update(candidate);
        cals = doric.calibrations();
        used = [ismember(candidate.Ephys.Channels, {'A', 'A and B'}), ...
                ismember(candidate.Ephys.Channels, {'B', 'A and B'})];
        for k = 1:2
            fields.IOMin{k}.setCalibration(cals{k});
            fields.IOMax{k}.setCalibration(cals{k});
            fields.PP{k}.setCalibration(cals{k});
            fields.IOMin{k}.setLimit(candidate.Doric.MaxCurrentmA(k));
            fields.IOMax{k}.setLimit(candidate.Doric.MaxCurrentmA(k));
            fields.PP{k}.setLimit(candidate.Doric.MaxCurrentmA(k));
            fields.IOMin{k}.setEnable(used(k) && candidate.Ephys.InputOutput.Enabled);
            fields.IOMax{k}.setEnable(used(k) && candidate.Ephys.InputOutput.Enabled);
            fields.PP{k}.setEnable(used(k) && candidate.Ephys.PairedPulse.Enabled);
        end
        lum.gui.Form.setEnable({c.IOLevels}, candidate.Ephys.InputOutput.Enabled);
        lum.gui.Form.setEnable({c.PPIntervals}, candidate.Ephys.PairedPulse.Enabled);
        mode = candidate.Ephys.Sync.Mode;
        lum.gui.Form.setEnable({c.FixedWidth}, mode == lum.SyncMode.FixedWidth);
        lum.gui.Form.setEnable({c.MeanWidth, c.WidthJitter}, mode == lum.SyncMode.JitteredWidth);
        lum.gui.Form.setEnable({c.Seed}, strcmp(candidate.Ephys.Order, 'Shuffled'));
        lum.gui.Form.setEnable({c.BarcodeBits, c.BarcodeMarker}, candidate.Sync.Barcode.Enabled);
        fitted = lum.sync.fitToCameras(candidate);
        if ~isequal(fitted.Sync.Barcode, drawnBarcode)
            lum.gui.Form.drawBarcode(c.BarcodeAxes, fitted.Sync.Barcode, 'EphysCalibration', t);
            drawnBarcode = fitted.Sync.Barcode;
        end
    end

    function showPlan(candidate, plan)
        key = {candidate.Ephys, doric.calibrations()};
        controls.Summary.Text = strjoin(lum.ephys.describe(candidate, plan), newline);
        controls.Summary.FontColor = t.Muted;
        if isequal(key, drawnKey)
            return
        end
        drawnKey = key;
        lum.gui.drawTestPulseSchedule(controls.ScheduleAxes, plan, t);
        title(controls.ScheduleAxes, 'Steps across the session', 'FontWeight', 'normal', 'FontSize', 10);
        drawCurrents(controls.CurrentAxes, plan, doric.calibrations(), t);
    end

    function clearPreview()
        cla(controls.ScheduleAxes);
        cla(controls.CurrentAxes);
        drawnKey = {};
    end
end


function drawCurrents(ax, plan, cals, t)
% Each step's intensity on A and B, in order: irradiance where calibrated, mA where not.
cla(ax);
hold(ax, 'on');
colours = {t.ChannelA, t.ChannelB};
currents = vertcat(plan.Steps.CurrentmA);
units = {};
for k = 1:2
    if all(isnan(currents(:, k)))
        continue
    end
    [values, unit] = lum.led.toUnit(cals{k}, currents(:, k));
    units{end+1} = sprintf('%s in %s', char('A' + k - 1), unit); %#ok<AGROW>
    plot(ax, 1:numel(values), values, 'o-', 'Color', colours{k}, 'MarkerFaceColor', colours{k});
end
set(ax, 'Color', t.Panel, 'XColor', t.Muted, 'YColor', t.Muted, 'TickDir', 'out', 'Box', 'off', ...
    'XLim', [0.5, numel(plan.Steps) + 0.5], 'XTick', 1:numel(plan.Steps), ...
    'XTickLabel', {plan.Steps.Label}, 'XTickLabelRotation', 45);
ylabel(ax, 'Intensity');
title(ax, sprintf('Intensity per step (%s)', strjoin(units, ', ')), 'FontWeight', 'normal', 'FontSize', 10);
hold(ax, 'off');
end


function ax = previewAxes(parent)
ax = uiaxes(parent);
ax.Toolbar.Visible = 'off';
disableDefaultInteractivity(ax);
end


function text = numbersText(values)
text = strjoin(arrayfun(@(v) sprintf('%g', v), values, 'UniformOutput', false), ' ');
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
uilabel(titles, 'Text', 'LuminoseFM  |  ePhys calibration setup', 'FontSize', 18, ...
        'FontWeight', 'bold', 'FontColor', t.Ink);
subject = S.Meta.Subject;
if isempty(subject)
    subject = 'no subject chosen';
end
uilabel(titles, 'Text', sprintf(['Subject %s  |  light pulses for an input-output curve and a '...
                                 'paired-pulse ratio, with a session barcode and sync pulses'], subject), ...
        'FontColor', t.Muted);
uilabel(grid, 'Text', sprintf('v%s  |  %s', lum.version(), rig.MachineModel), ...
        'FontColor', t.Muted, 'HorizontalAlignment', 'right');
end
