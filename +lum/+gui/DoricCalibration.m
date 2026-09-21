classdef DoricCalibration < handle
    % lum.gui.DoricCalibration measures an LED calibration: current against irradiance.
    %
    % Opened from the Doric LED tab's Calibrate... button, for the cable on one optical
    % channel (lum.led.lightPath), lit through that channel. The operator holds a power meter at the cable's tip,
    % lights the channel at each current in the table (continuous light, through the
    % connected driver) and types the power read, in mW or uW. The window shows the
    % irradiance, power over the area of the cable's fibers, and draws current against
    % irradiance as the readings come in (lum.led.plotCalibration).
    %
    % Save calibration writes it (lum.led.saveCalibration), replacing any earlier one of
    % this cable, and every session type uses it from then on, on either channel (the two
    % LED channels are taken to give equal power at equal current). Closing the
    % window switches the channel off; the session puts it back in external TTL mode.
    %
    % Without a connected driver (DoricLED not found, the control off), the Light buttons
    % are greyed out and each current is set on the driver by hand.
    %
    % Usage:
    %   w = lum.gui.DoricCalibration(path, 'LED', led, 'MaxCurrentmA', 700, ...
    %                                'OnSaved', @(cal) ...);
    %
    % Options:
    %   'LED'           A connected lum.dev.DoricLED, or [] to take readings only
    %   'MaxCurrentmA'  The highest current offered (default 700; at most 1000)
    %   'Previous'      The cable's calibration so far, to start from its readings
    %   'Folder'        Where to save (default lum.led.calibrationFolder)
    %   'OnSaved'       Called with the saved calibration
    %   'Visible'       'on' (default) or 'off', for tests
    %
    % Members for tests: Figure, Controls, setPower(row, value), select(row), lightOn(),
    % lightOff(), save(), calibration(), close().
    %
    % See also: lum.gui.DoricSetup, lum.led.makeCalibration, lum.led.saveCalibration

    properties (SetAccess = private)
        Figure
        Controls = struct()
        Path                 % From lum.led.lightPath
        Saved = []           % The calibration saved, once saved
    end

    properties (Access = private)
        led
        theme
        onSaved
        folder
        maxCurrent
        selected = 1
        lit = false
    end

    methods
        function obj = DoricCalibration(path, varargin)
            p = inputParser;
            addParameter(p, 'LED', []);
            addParameter(p, 'MaxCurrentmA', 700);
            addParameter(p, 'Previous', []);
            addParameter(p, 'Folder', '');
            addParameter(p, 'OnSaved', []);
            addParameter(p, 'Visible', 'on');
            parse(p, varargin{:});
            obj.Path = path;
            obj.led = p.Results.LED;
            obj.onSaved = p.Results.OnSaved;
            obj.folder = p.Results.Folder;
            obj.maxCurrent = min(p.Results.MaxCurrentmA, 1000);
            obj.theme = lum.gui.theme();
            obj.build(p.Results.Visible, p.Results.Previous);
            obj.redraw();
        end

        function setPower(obj, row, value)
            % setPower(row, value) types a reading, as the operator would.
            data = obj.Controls.Table.Data;
            data{row, 2} = value;
            obj.Controls.Table.Data = data;
            obj.redraw();
        end

        function select(obj, row)
            obj.selected = row;
            obj.showSelected();
        end

        function lightOn(obj)
            % lightOn() lights the channel continuously at the selected row's current.
            data = obj.Controls.Table.Data;
            current = data{obj.selected, 1};
            if isempty(obj.led)
                return
            end
            try
                obj.led.lightOn(obj.Path.LEDChannel, current);
                obj.lit = true;
                obj.setStatus(sprintf('Channel %s on at %g mA. Read the power meter, type the power, then Next.', ...
                                      obj.Path.Channel, current), true);
            catch lightError
                obj.setStatus(lightError.message, false);
            end
        end

        function lightOff(obj)
            if ~isvalid(obj)
                return
            end
            if ~isempty(obj.led) && isvalid(obj.led) && obj.lit
                obj.led.lightOff(obj.Path.LEDChannel);
            end
            obj.lit = false;
        end

        function cal = calibration(obj)
            % calibration() is the calibration the readings make so far (errors if they
            % make none).
            data = obj.Controls.Table.Data;
            currents = cell2mat(data(:, 1));
            powers = cellfun(@readingOf, data(:, 2));
            cal = lum.led.makeCalibration(obj.Path, currents, powers, obj.Controls.Unit.Value, ...
                                          'Notes', obj.Controls.Notes.Value);
        end

        function ok = save(obj)
            % save() writes the calibration, replacing any earlier one of this cable.
            ok = false;
            try
                cal = obj.calibration();
                [file, image] = lum.led.saveCalibration(cal, obj.folder);
            catch saveError
                obj.setStatus(saveError.message, false);
                return
            end
            obj.Saved = cal;
            ok = true;
            where = file;
            if ~isempty(image)
                where = sprintf('%s (graph: %s)', file, image);
            end
            obj.setStatus(sprintf('Saved: %s', where), true);
            if ~isempty(obj.onSaved)
                obj.onSaved(cal);
            end
        end

        function close(obj)
            % close() switches the channel off and closes the window.
            if ~isvalid(obj)
                return
            end
            obj.lightOff();
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function build(obj, visible, previous)
            t = obj.theme;
            path = obj.Path;
            obj.Figure = uifigure('Name', sprintf('LuminoseFM - calibrate the %s cable (channel %s)', ...
                                                  path.Cable, path.Channel), ...
                                  'Position', [120 90 1060 640], 'Color', t.Background, ...
                                  'Visible', visible, 'CloseRequestFcn', @(~, ~) obj.close());
            lum.gui.Form.waitForView(obj.Figure);
            outer = uigridlayout(obj.Figure, [3 1], 'RowHeight', {44, '1x', 34}, ...
                                 'Padding', [14 10 14 12], 'RowSpacing', 8, 'BackgroundColor', t.Background);
            colours = {t.ChannelA, t.ChannelB};
            uilabel(outer, 'Text', sprintf(['%s cable, %s bundle: %d fibers of %g um = %.4g mm2  |  '...
                                            'lit by channel %s (Doric LED channel %d)'], path.Cable, ...
                                           path.Bundle, path.nFibers, 1000 * path.FiberDiameter, path.Area, ...
                                           path.Channel, path.LEDChannel), ...
                    'FontSize', 15, 'FontWeight', 'bold', 'FontColor', colours{path.LEDChannel});

            body = uigridlayout(outer, [1 2], 'ColumnWidth', {430, '1x'}, 'Padding', 0, ...
                                'ColumnSpacing', 12, 'BackgroundColor', t.Background);
            left = uigridlayout(body, [5 1], 'RowHeight', {lum.gui.Form.panelHeight(3), '1x', 30, 30, 70}, ...
                                'Padding', 0, 'RowSpacing', 8, 'BackgroundColor', t.Background);
            form = lum.gui.Form.panel(left, 'Readings', 3, t, 150);
            lum.gui.Form.label(form, 'Power meter reads', t);
            obj.Controls.Unit = uidropdown(form, 'Items', {'mW', 'uW'}, 'Value', 'mW', ...
                'ValueChangedFcn', @(~, ~) obj.redraw(), 'Tooltip', 'The unit the power meter shows.');
            lum.gui.Form.label(form, 'Currents (mA)', t);
            row = uigridlayout(form, [1 4], 'ColumnWidth', {'1x', '1x', '1x', 60}, 'Padding', 0, ...
                               'ColumnSpacing', 4, 'BackgroundColor', t.Panel);
            obj.Controls.From = uieditfield(row, 'numeric', 'Value', 0, 'Limits', [0 obj.maxCurrent], ...
                'RoundFractionalValues', 'on', 'Tooltip', 'The first current, mA.');
            obj.Controls.To = uieditfield(row, 'numeric', 'Value', min(500, obj.maxCurrent), ...
                'Limits', [0 obj.maxCurrent], 'RoundFractionalValues', 'on', 'Tooltip', 'The last current, mA.');
            obj.Controls.Step = uieditfield(row, 'numeric', 'Value', 50, 'Limits', [1 1000], ...
                'RoundFractionalValues', 'on', 'Tooltip', 'The step between currents, mA.');
            uibutton(row, 'Text', 'Fill', 'ButtonPushedFcn', @(~, ~) obj.fill(), ...
                     'Tooltip', 'Replace the table''s currents; readings are cleared.');
            lum.gui.Form.label(form, 'Notes', t);
            obj.Controls.Notes = uieditfield(form, 'text', 'Value', '', ...
                'Placeholder', 'power meter, wavelength setting', ...
                'Tooltip', 'Saved with the calibration: the meter and its wavelength setting (465 nm).');

            currents = (0:50:min(500, obj.maxCurrent))';
            powers = num2cell(NaN(numel(currents), 1));
            if ~isempty(previous)
                currents = previous.CurrentmA(:);
                powers = num2cell(previous.PowerTyped(:));
                obj.Controls.Unit.Value = previous.PowerUnit;
                obj.Controls.Notes.Value = previous.Notes;
            end
            obj.Controls.Table = uitable(left, 'Data', [num2cell(currents), powers, num2cell(NaN(numel(currents), 1))], ...
                'ColumnName', {'Current (mA)', 'Power', ['Irradiance (mW/mm' char(178) ')']}, ...
                'ColumnEditable', [true true false], 'ColumnFormat', {'numeric', 'numeric', 'numeric'}, ...
                'CellEditCallback', @(~, ~) obj.redraw(), ...
                'CellSelectionCallback', @(~, event) obj.cellSelected(event));
            buttons = uigridlayout(left, [1 3], 'ColumnWidth', {'1x', '1x', '1x'}, 'Padding', 0, ...
                                   'ColumnSpacing', 6, 'BackgroundColor', t.Background);
            obj.Controls.On = uibutton(buttons, 'Text', 'Light on', 'ButtonPushedFcn', @(~, ~) obj.lightOn(), ...
                'Tooltip', 'Light this channel continuously at the selected row''s current.');
            obj.Controls.Off = uibutton(buttons, 'Text', 'Light off', 'ButtonPushedFcn', @(~, ~) obj.lightOff(), ...
                'Tooltip', 'Switch this channel off.');
            obj.Controls.Next = uibutton(buttons, 'Text', 'Next', 'ButtonPushedFcn', @(~, ~) obj.next(), ...
                'Tooltip', 'Go to the next row and light it.');
            obj.Controls.Selected = uilabel(left, 'Text', '', 'FontColor', t.Ink);
            if isempty(obj.led)
                text = ['No driver connected: set each current on the driver by hand (continuous '...
                        'mode), read the power meter and type the power.'];
                lum.gui.Form.setEnable({obj.Controls.On, obj.Controls.Off, obj.Controls.Next}, false);
            else
                text = ['Hold the power meter at the cable''s tip. Pick a row, Light on, type the '...
                        'power read, then Next. The light is continuous: keep the fiber away from any animal.'];
            end
            lum.gui.Form.note(left, text, t);

            obj.Controls.Axes = uiaxes(body);
            obj.Controls.Axes.Toolbar.Visible = 'off';

            footer = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 160, 100}, 'Padding', 0, ...
                                  'ColumnSpacing', 8, 'BackgroundColor', t.Background);
            obj.Controls.Status = uilabel(footer, 'Text', '', 'WordWrap', 'on', 'FontSize', 11);
            obj.Controls.Save = uibutton(footer, 'Text', 'Save calibration', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Accent, 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) obj.save(), ...
                'Tooltip', 'Save, replacing any earlier calibration of this cable. It is used on either channel.');
            uibutton(footer, 'Text', 'Close', 'ButtonPushedFcn', @(~, ~) obj.close());
            obj.showSelected();
        end

        function fill(obj)
            currents = (obj.Controls.From.Value:obj.Controls.Step.Value:obj.Controls.To.Value)';
            if isempty(currents)
                obj.setStatus('No currents between the first and the last.', false);
                return
            end
            obj.Controls.Table.Data = [num2cell(currents), num2cell(NaN(numel(currents), 1)), ...
                                       num2cell(NaN(numel(currents), 1))];
            obj.selected = 1;
            obj.showSelected();
            obj.redraw();
        end

        function next(obj)
            obj.selected = min(obj.selected + 1, size(obj.Controls.Table.Data, 1));
            obj.showSelected();
            obj.lightOn();
        end

        function cellSelected(obj, event)
            if ~isempty(event.Indices)
                obj.selected = event.Indices(1, 1);
                obj.showSelected();
            end
        end

        function showSelected(obj)
            data = obj.Controls.Table.Data;
            if isempty(data)
                obj.Controls.Selected.Text = '';
                return
            end
            obj.selected = min(max(obj.selected, 1), size(data, 1));
            obj.Controls.Selected.Text = sprintf('Row %d: %g mA', obj.selected, data{obj.selected, 1});
        end

        function redraw(obj)
            % Irradiance per row, the graph, and whether the readings make a calibration.
            data = obj.Controls.Table.Data;
            scale = 1;
            if strcmp(obj.Controls.Unit.Value, 'uW')
                scale = 1e-3;
            end
            for i = 1:size(data, 1)
                data{i, 3} = readingOf(data{i, 2}) * scale / obj.Path.Area;
            end
            obj.Controls.Table.Data = data;
            partial = obj.Path;
            partial.MeasuredOn = obj.Path.Channel;
            partial.MeasuredLEDChannel = obj.Path.LEDChannel;
            partial.CurrentmA = cell2mat(data(:, 1));
            partial.IrradiancemWmm2 = cell2mat(data(:, 3));
            lum.led.plotCalibration(obj.Controls.Axes, partial, obj.theme);
            try
                obj.calibration();
                obj.setStatus('Ready to save.', true);
                obj.Controls.Save.Enable = 'on';
            catch problem
                obj.setStatus(problem.message, false);
                obj.Controls.Save.Enable = 'off';
            end
        end

        function setStatus(obj, message, isGood)
            obj.Controls.Status.Text = message;
            if isGood
                obj.Controls.Status.FontColor = obj.theme.Good;
            else
                obj.Controls.Status.FontColor = obj.theme.Bad;
            end
        end
    end
end


function value = readingOf(cellValue)
% A table cell as a number, NaN when empty.
if isempty(cellValue) || ~isnumeric(cellValue)
    value = NaN;
else
    value = double(cellValue);
end
end
