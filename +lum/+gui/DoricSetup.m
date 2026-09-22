classdef DoricSetup < handle
    % lum.gui.DoricSetup is the Doric LED tab of every setup dialog (D17).
    %
    % It edits S.Doric and the light path (S.Light.Bundle, S.Light.Cables), which every
    % session type with light shares:
    %
    %   Doric LED driver  whether the session controls the LED from MATLAB (the DoricLED
    %                     package, found in the folder given or on the path), the
    %                     connection's state, and the driver's own window
    %   Fiber bundle      the bundle on the animal and the cable, by colour, on each
    %                     channel (2-to-19: blue on A and green on B by default;
    %                     4-to-19: orange on A and blue on B), and Calibrate LED
    %                     power..., which measures the cables two at a time, one on each
    %                     channel (lum.gui.DoricCalibration)
    %   Intensity         per channel: the LED current (mW/mm2 when the cable on it is
    %                     calibrated, mA when not), its limit in mA and the cable's
    %                     calibration
    %   LED window        whether the session opens the LED window (lum.gui.DoricWindow)
    %
    % The tab shows the protocol's lum.dev.DoricLED, which connects in the background
    % while the dialog is open. A calibration belongs to the cable, not the channel (the two
    % LED channels are taken to give equal power at equal current). One saved here is used
    % at once, by this dialog and by every later session of any type with that cable on
    % either channel.
    %
    % Usage, inside a dialog:
    %   doric = lum.gui.DoricSetup(tab, S, t, @refresh, led);
    %   S = doric.read(S);              % in collect: S.Doric, S.Light.Bundle and Cables
    %   doric.update(S);                % in the appearance update
    %   note = doric.problem(S);        % '' or a note for the status line
    %   cals = doric.calibrations();    % 1 x 2 cell, the light paths' calibrations
    %
    % See also: lum.dev.DoricLED, lum.gui.DoricCalibration, lum.gui.IntensityField,
    %           lum.led.lightPath

    properties (SetAccess = private)
        Controls = struct()
        LED = []                  % The protocol's lum.dev.DoricLED, or []
    end

    properties (Access = private)
        onEdit
        theme
        intensity = {}            % lum.gui.IntensityField per channel
        cals = {[], []}
        paths = {}
        listener = []
        calibrationFolder = ''
        calibrationWindow = []
    end

    methods
        function obj = DoricSetup(parent, S, t, onEdit, led, varargin)
            p = inputParser;
            addParameter(p, 'CalibrationFolder', '');
            parse(p, varargin{:});
            obj.onEdit = onEdit;
            obj.theme = t;
            obj.LED = led;
            obj.calibrationFolder = p.Results.CalibrationFolder;
            obj.build(parent, S);
            obj.lightPathChanged(S);
            if ~isempty(led)
                obj.listener = addlistener(led, 'Changed', @(~, ~) obj.showState());
            end
            obj.showState();
            fig = ancestor(parent, 'figure');
            addlistener(fig, 'ObjectBeingDestroyed', @(~, ~) obj.close());
        end

        function S = read(obj, S)
            % read(S) is S with S.Doric and the light path as the tab has them.
            c = obj.Controls;
            S.Doric.Enabled = c.Enabled.Value;
            S.Doric.Folder = strtrim(c.Folder.Value);
            S.Doric.ShowWindow = c.ShowWindow.Value;
            S.Doric.CurrentmA = [obj.intensity{1}.currentmA(), obj.intensity{2}.currentmA()];
            S.Doric.MaxCurrentmA = [c.MaxCurrent(1).Value, c.MaxCurrent(2).Value];
            S.Light.Bundle = c.Bundle.Value;
            S.Light.Cables = {c.CableA.Value, c.CableB.Value};
        end

        function update(obj, S)
            % update(S) follows the light path's calibrations, greys out what does not
            % apply and refreshes the notes.
            c = obj.Controls;
            obj.lightPathChanged(S);
            on = S.Doric.Enabled;
            lum.gui.Form.setEnable({c.Folder, c.Browse, c.ShowWindow, c.MaxCurrent(1), c.MaxCurrent(2)}, on);
            for k = 1:2
                obj.intensity{k}.setEnable(on);
                path = obj.paths{k};
                c.PathNote(k).Text = sprintf('%s cable, %d fibers of %g um: %.4g mm2', path.Cable, ...
                                             path.nFibers, 1000 * path.FiberDiameter, path.Area);
                cal = obj.cals{k};
                if isempty(cal)
                    c.CalibrationNote(k).Text = 'Not calibrated: intensity in mA.';
                    c.CalibrationNote(k).FontColor = obj.theme.Muted;
                else
                    c.CalibrationNote(k).Text = sprintf(['%s cable calibrated %s on channel %s, '...
                        '%g-%g mA = %.3g-%.3g mW/mm2.'], cal.Cable, cal.Date, cal.MeasuredOn, ...
                        cal.CurrentmA(1), cal.CurrentmA(end), cal.IrradiancemWmm2(1), ...
                        cal.IrradiancemWmm2(end));
                    c.CalibrationNote(k).FontColor = obj.theme.Good;
                end
            end
            folder = lum.dev.DoricLED.locatePackage(S.Doric.Folder);
            if isempty(folder)
                c.FolderNote.Text = ['DoricLED not found: the driver is used as set by hand. Choose '...
                                     'the folder DoricLED was cloned into to control it.'];
                c.FolderNote.FontColor = obj.theme.Bad;
            else
                c.FolderNote.Text = sprintf('DoricLED found in %s', folder);
                c.FolderNote.FontColor = obj.theme.Good;
            end
            obj.showState();
        end

        function note = problem(obj, S)
            % problem(S) is '' when the LED is ready for the session, or a note saying
            % what the session will do instead.
            note = '';
            if ~S.Doric.Enabled
                note = 'The LED is used as set by hand (external TTL mode on the driver).';
            elseif isempty(lum.dev.DoricLED.locatePackage(S.Doric.Folder))
                note = 'DoricLED was not found, so the LED is used as set by hand.';
            elseif ~isempty(obj.LED) && strcmp(obj.LED.state(), 'Faulted')
                note = sprintf('The Doric LED is not responding (%s); the session tries again as it starts.', ...
                               obj.LED.describeState());
            end
        end

        function cals = calibrations(obj)
            % calibrations() is the 1 x 2 cell of the calibrations of the cables on A and B.
            cals = obj.cals;
        end

        function close(obj)
            % close() closes the calibration window, and stops listening to the LED.
            if ~isempty(obj.listener) && isvalid(obj.listener)
                delete(obj.listener);
            end
            obj.listener = [];
            if ~isempty(obj.calibrationWindow) && isvalid(obj.calibrationWindow)
                obj.calibrationWindow.close();
            end
        end
    end

    methods (Access = private)
        function build(obj, parent, S)
            t = obj.theme;
            grid = uigridlayout(parent, [1 2], 'ColumnWidth', {640, '1x'}, 'Padding', 12, ...
                                'ColumnSpacing', 12, 'BackgroundColor', t.Background);
            left = uigridlayout(grid, [3 1], 'RowHeight', {lum.gui.Form.panelHeight(5) + 30, ...
                                lum.gui.Form.panelHeight(4) + 16, '1x'}, 'Padding', 0, 'RowSpacing', 10, ...
                                'BackgroundColor', t.Background);

            % The driver.
            form = lum.gui.Form.panel(left, 'Doric LED driver', 5, t, 170);
            form.RowHeight = {26, 26, 44, 26, 26};
            lum.gui.Form.label(form, 'Control', t);
            obj.Controls.Enabled = uicheckbox(form, 'Text', 'Control the LED from MATLAB', ...
                'Value', S.Doric.Enabled, 'ValueChangedFcn', @(~, ~) obj.onEdit(), ...
                'Tooltip', ['On: the session connects to the Doric driver through the DoricLED package and '...
                            'puts both channels in external TTL mode at the currents below. Off: the '...
                            'driver is used as it was set by hand, which must be external TTL mode.']);
            lum.gui.Form.label(form, 'DoricLED folder', t);
            row = uigridlayout(form, [1 2], 'ColumnWidth', {'1x', 80}, 'Padding', 0, ...
                               'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            obj.Controls.Folder = uieditfield(row, 'text', 'Value', char(S.Doric.Folder), ...
                'Placeholder', 'on the MATLAB path', 'ValueChangedFcn', @(~, ~) obj.onEdit(), ...
                'Tooltip', 'The folder the DoricLED package was cloned into; empty when it is on the MATLAB path.');
            obj.Controls.Browse = uibutton(row, 'Text', ['Browse' char(8230)], ...
                                           'ButtonPushedFcn', @(~, ~) obj.browse());
            lum.gui.Form.label(form, '', t);
            obj.Controls.FolderNote = lum.gui.Form.note(form, '', t);
            lum.gui.Form.label(form, 'Connection', t);
            obj.Controls.State = uilabel(form, 'Text', '', 'WordWrap', 'on', 'FontSize', 11);
            lum.gui.Form.label(form, '', t);
            row = uigridlayout(form, [1 3], 'ColumnWidth', {110, 150, '1x'}, 'Padding', 0, ...
                               'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            obj.Controls.Connect = uibutton(row, 'Text', 'Connect', 'ButtonPushedFcn', @(~, ~) obj.connect(), ...
                'Tooltip', 'Connect to the driver again, after a failure or a replug.');
            obj.Controls.DoricWindow = uibutton(row, 'Text', ['Doric controls' char(8230)], ...
                'ButtonPushedFcn', @(~, ~) obj.openDoricApp(), ...
                'Tooltip', ['The DoricLED package''s own window, on the same connection: every mode and '...
                            'setting. The session puts both channels back in external TTL mode as it starts.']);
            obj.Controls.ShowWindow = uicheckbox(row, 'Text', 'LED window in the session', ...
                'Value', S.Doric.ShowWindow, 'ValueChangedFcn', @(~, ~) obj.onEdit(), ...
                'Tooltip', ['Open the LED window during the session: the current on each channel, '...
                            'changed between trials.']);

            % The fiber bundle.
            bundles = lum.fiberBundles();
            form = lum.gui.Form.panel(left, 'Fiber bundle', 4, t, 170);
            lum.gui.Form.label(form, 'Bundle on the animal', t);
            obj.Controls.Bundle = uidropdown(form, 'Items', {bundles.Name}, 'Value', S.Light.Bundle, ...
                'Tooltip', ['The fiber bundle on the animal: 2-to-19 (blue and green cables) or 4-to-19 '...
                            '(two of black, blue, orange and green on the commutator).']);
            lum.gui.Form.label(form, 'Cable on channel A', t);
            obj.Controls.CableA = uidropdown(form, 'Items', {''}, ...
                'Tooltip', 'The cable on the commutator lit by channel A (LED channel 1).');
            lum.gui.Form.label(form, 'Cable on channel B', t);
            obj.Controls.CableB = uidropdown(form, 'Items', {''}, ...
                'Tooltip', 'The cable on the commutator lit by channel B (LED channel 2).');
            lum.gui.Form.label(form, 'LED calibration', t);
            obj.Controls.Calibrate = uibutton(form, 'Text', ['Calibrate LED power' char(8230)], ...
                'ButtonPushedFcn', @(~, ~) obj.calibrate(), ...
                'Tooltip', ['Measure the power leaving the cables with a power meter, two at a time: '...
                            'the pair on the commutator, one on each channel, lit continuously at '...
                            '0 to 700 mA. Saving replaces a cable''s earlier calibration; it is used on '...
                            'either channel.']);
            fillCables(obj.Controls, bundles, S.Light.Cables);
            obj.Controls.Bundle.ValueChangedFcn = @(~, ~) obj.bundleChanged();
            obj.Controls.CableA.ValueChangedFcn = @(~, ~) obj.onEdit();
            obj.Controls.CableB.ValueChangedFcn = @(~, ~) obj.onEdit();

            lum.gui.Form.note(left, sprintf(['Channel A:  Bpod BNC1 -> PulsePal OUT1 -> Doric LED channel 1\n'...
                'Channel B:  Bpod BNC2 -> PulsePal OUT2 -> Doric LED channel 2\n\n'...
                'Bpod and PulsePal time the light; the driver sets its intensity, the LED current, '...
                'in external TTL mode: each channel is lit at its current while PulsePal''s output '...
                'into it is high. The current is changed only between trials (the LED window), '...
                'sleep blocks or ePhys steps.\n\nCalibrating measures the power leaving a cable '...
                'at several currents, two cables at a time, each lit by the channel it is on. Irradiance is that power over the '...
                'area of the cable''s fibers (100 um each). The calibration belongs to the cable, not '...
                'the channel: the two LED channels are taken to give equal power at equal current, '...
                'so a cable moved to the other channel keeps its calibration. Once a cable is '...
                'calibrated, every session type shows and takes its intensity in mW/mm2.']), t);

            % Intensity, per channel.
            box = uipanel(grid, 'Title', 'Intensity', 'FontWeight', 'bold', ...
                          'BackgroundColor', t.Panel, 'ForegroundColor', t.Accent);
            rows = uigridlayout(box, [2 1], 'RowHeight', {230, 230}, 'Padding', [10 8 10 8], ...
                                'RowSpacing', 12, 'BackgroundColor', t.Panel);
            colours = {t.ChannelA, t.ChannelB};
            names = {'Channel A  (LED channel 1)', 'Channel B  (LED channel 2)'};
            for k = 1:2
                form = uigridlayout(rows, [5 3], 'ColumnWidth', {170, 120, '1x'}, ...
                                    'RowHeight', {24, 26, 26, 24, 44}, 'Padding', 0, ...
                                    'RowSpacing', 6, 'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
                heading = uilabel(form, 'Text', names{k}, 'FontWeight', 'bold', 'FontColor', colours{k});
                heading.Layout.Column = [1 3];
                lum.gui.Form.label(form, 'Intensity', t);
                obj.intensity{k} = lum.gui.IntensityField(form, S.Doric.CurrentmA(k), @() obj.onEdit(), ...
                    'Tooltip', ['The LED current while this channel is gated: irradiance at the fiber '...
                                'tips in mW/mm2 when the light path is calibrated, mA when not.']);
                lum.gui.Form.label(form, 'Limit (mA)', t);
                obj.Controls.MaxCurrent(k) = uieditfield(form, 'numeric', 'Value', S.Doric.MaxCurrentmA(k), ...
                    'Limits', [0 1000], 'RoundFractionalValues', 'on', 'ValueChangedFcn', @(~, ~) obj.onEdit(), ...
                    'Tooltip', ['The highest current this channel may be set to, in mA. A request above it '...
                                'is refused. At most 1000 mA, the LED''s rating; Doric recommends 700.']);
                uilabel(form, 'Text', '');
                lum.gui.Form.label(form, 'Light path', t);
                obj.Controls.PathNote(k) = uilabel(form, 'Text', '', 'FontSize', 11, 'FontColor', t.Muted);
                obj.Controls.PathNote(k).Layout.Column = [2 3];
                lum.gui.Form.label(form, 'Calibration', t);
                obj.Controls.CalibrationNote(k) = uilabel(form, 'Text', '', 'FontSize', 11, 'WordWrap', 'on');
                obj.Controls.CalibrationNote(k).Layout.Column = [2 3];
            end
        end

        function lightPathChanged(obj, S)
            % Calibrations follow the cable on each channel.
            obj.paths = {lum.led.lightPath(S, 1), lum.led.lightPath(S, 2)};
            for k = 1:2
                obj.cals{k} = lum.led.loadCalibration(obj.paths{k}, obj.calibrationFolder);
                obj.intensity{k}.setCalibration(obj.cals{k});
            end
        end

        function bundleChanged(obj)
            c = obj.Controls;
            bundles = lum.fiberBundles();
            bundle = bundles(strcmp({bundles.Name}, c.Bundle.Value));
            fillCables(c, bundles, bundle.Defaults);
            obj.onEdit();
        end

        function showState(obj)
            if ~isvalid(obj) || ~isfield(obj.Controls, 'State') || ~isvalid(obj.Controls.State)
                return
            end
            c = obj.Controls;
            if isempty(obj.LED)
                c.State.Text = 'Not opened.';
                c.State.FontColor = obj.theme.Muted;
                lum.gui.Form.setEnable({c.Connect, c.DoricWindow, c.Calibrate}, false);
                return
            end
            c.State.Text = obj.LED.describeState();
            state = obj.LED.state();
            switch state
                case 'Ready'
                    c.State.FontColor = obj.theme.Good;
                case {'Faulted', 'Disconnected'}
                    c.State.FontColor = obj.theme.Bad;
                otherwise
                    c.State.FontColor = obj.theme.Muted;
            end
            controlled = obj.LED.isControlled();
            lum.gui.Form.setEnable({c.Connect}, controlled && ~ismember(state, {'Ready', 'Connecting'}));
            lum.gui.Form.setEnable({c.DoricWindow}, controlled && strcmp(state, 'Ready'));
            % Calibration works without control too: the operator then sets each current by hand.
            lum.gui.Form.setEnable({c.Calibrate}, ~strcmp(state, 'Connecting'));
        end

        function connect(obj)
            if ~isempty(obj.LED)
                obj.LED.connect();
            end
        end

        function openDoricApp(obj)
            if isempty(obj.LED) || ~obj.LED.isControlled()
                return
            end
            try
                doric.app(obj.LED.LightSource);
            catch appError
                uialert(ancestor(obj.Controls.State, 'figure'), appError.message, 'Doric controls');
            end
        end

        function browse(obj)
            folder = uigetdir(obj.Controls.Folder.Value, 'The folder DoricLED was cloned into');
            if ischar(folder)
                obj.Controls.Folder.Value = folder;
                obj.onEdit();
            end
        end

        function calibrate(obj)
            % One calibration window at a time, starting from the tab's bundle and cables.
            if ~isempty(obj.calibrationWindow) && isvalid(obj.calibrationWindow) ...
                    && isvalid(obj.calibrationWindow.Figure)
                figure(obj.calibrationWindow.Figure);
                return
            end
            fig = ancestor(obj.Controls.State, 'figure');
            led = obj.LED;
            if ~isempty(led) && ~(led.isControlled() && strcmp(led.state(), 'Ready'))
                led = [];   % Readings only: the operator sets each current on the driver
            end
            c = obj.Controls;
            obj.calibrationWindow = lum.gui.DoricCalibration(c.Bundle.Value, {c.CableA.Value, c.CableB.Value}, ...
                'LED', led, 'MaxCurrentmA', [c.MaxCurrent(1).Value, c.MaxCurrent(2).Value], ...
                'Folder', obj.calibrationFolder, 'OnSaved', @(~) obj.calibrationSaved(), ...
                'Visible', fig.Visible);
        end

        function calibrationSaved(obj)
            obj.cals = {[], []};
            for k = 1:2
                obj.cals{k} = lum.led.loadCalibration(obj.paths{k}, obj.calibrationFolder);
                obj.intensity{k}.setCalibration(obj.cals{k});
            end
            obj.onEdit();
        end
    end
end


function fillCables(c, bundles, chosen)
% Offer the chosen bundle's cables, with their spot counts, keeping choices that fit.
bundle = bundles(strcmp({bundles.Name}, c.Bundle.Value));
items = arrayfun(@(k) sprintf('%s (%d spots)', bundle.Cables{k}, bundle.Spots(k)), ...
                 1:numel(bundle.Cables), 'UniformOutput', false);
c.CableA.Items = items;
c.CableA.ItemsData = bundle.Cables;
c.CableB.Items = items;
c.CableB.ItemsData = bundle.Cables;
if numel(chosen) == 2 && all(ismember(chosen, bundle.Cables))
    c.CableA.Value = chosen{1};
    c.CableB.Value = chosen{2};
else
    c.CableA.Value = bundle.Defaults{1};
    c.CableB.Value = bundle.Defaults{2};
end
end
