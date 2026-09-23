classdef DoricCalibration < handle
    % lum.gui.DoricCalibration measures LED calibrations, two cables at a time.
    %
    % Opened from the Doric LED tab's Calibrate LED power... button. The commutator takes
    % two cables of the bundle at once, one on each optical channel, so the window
    % calibrates a pair: choose the bundle and the cable on A and on B (the 2-to-19 has
    % one pair, blue and green; the 4-to-19 needs two, for example orange and blue, then
    % black and green). A calibration is of a cable on a channel, so a cable used on both
    % channels is calibrated on each: swap the pair at the commutator and calibrate again.
    % The line under the choice says which of the bundle's cables are calibrated on which
    % channel already.
    %
    % Each channel has its own table of currents, 0 to 700 mA in steps of 50 by default
    % (Fill makes another series, never above the channel's limit), its own On and Off,
    % and its own graph. On lights that channel continuously (continuous mode, through
    % the connected driver) at the selected row's current; while it is lit, choosing
    % another row, or Next, lights it at that row's current. The operator holds the power
    % meter at the cable's tip and types the power read, in mW or uW. The window shows the
    % irradiance, power over the area of the cable's fibers, and draws current against
    % irradiance as the readings come in (lum.led.plotCalibration), with the cable's saved
    % calibration dashed behind it when there is one.
    %
    % Save calibrations writes each channel whose readings make a calibration
    % (lum.led.saveCalibration), replacing any earlier one of that cable on that channel;
    % every session type uses it from then on, with that cable on that channel. Choosing
    % another cable drops that channel's
    % unsaved readings, after asking. Closing the window switches both channels off; the
    % session puts them back in external TTL mode.
    %
    % Without a connected driver (DoricLED not found, the control off), On and Off are
    % greyed out and each current is set on the driver by hand, in continuous mode.
    %
    % Usage:
    %   w = lum.gui.DoricCalibration('4-to-19', {'orange', 'blue'}, 'LED', led, ...
    %                                'MaxCurrentmA', [700 700], 'OnSaved', @(cal) ...);
    %
    % Options:
    %   'LED'           A connected lum.dev.DoricLED, or [] to take readings only
    %   'MaxCurrentmA'  The highest current offered on A and B (default 700 each; at most 1000)
    %   'Folder'        Where to save (default lum.led.calibrationFolder)
    %   'OnSaved'       Called with each saved calibration
    %   'Visible'       'on' (default) or 'off', for tests
    %
    % Members for tests: Figure, Controls, Paths, setCables(bundle, cables),
    % setPower(k, row, value), select(k, row), next(k), lightOn(k), lightOff(k),
    % switchOff(k) (the Off button), save(), calibration(k), close().
    %
    % See also: lum.gui.DoricSetup, lum.led.makeCalibration, lum.led.saveCalibration

    properties (SetAccess = private)
        Figure
        Controls = struct()
        Paths = {}           % The light path on A and B (lum.led.lightPath)
        Saved = {}           % The calibrations saved so far
    end

    properties (Constant)
        DefaultCurrentsmA = 0:50:700   % The table each channel starts with
    end

    properties (Access = private)
        led
        theme
        onSaved
        folder
        maxCurrent = [700 700]
        selected = [1 1]
        lit = [false false]
        dirty = [false false]    % Readings typed since the last save or cable change
        previous = {[], []}      % Each cable's saved calibration, drawn behind the readings
        bundleName
        cables
    end

    methods
        function obj = DoricCalibration(bundle, cables, varargin)
            p = inputParser;
            addParameter(p, 'LED', []);
            addParameter(p, 'MaxCurrentmA', [700 700]);
            addParameter(p, 'Folder', '');
            addParameter(p, 'OnSaved', []);
            addParameter(p, 'Visible', 'on');
            parse(p, varargin{:});
            obj.led = p.Results.LED;
            obj.onSaved = p.Results.OnSaved;
            obj.folder = p.Results.Folder;
            limits = double(p.Results.MaxCurrentmA);
            if isscalar(limits)
                limits = [limits limits];
            end
            obj.maxCurrent = min(limits(:)', 1000);
            obj.theme = lum.gui.theme();
            obj.bundleName = char(bundle);
            obj.cables = cellfun(@char, cables, 'UniformOutput', false);
            obj.build(p.Results.Visible);
            obj.useCables();
        end

        function setCables(obj, bundle, cables)
            % setCables(bundle, {cableA, cableB}) calibrates another pair, as choosing
            % them in the window would (without asking about unsaved readings).
            obj.Controls.Bundle.Value = bundle;
            obj.fillCableLists(cables);
            obj.applyCableChoice();
        end

        function setPower(obj, k, row, value)
            % setPower(k, row, value) types a reading for channel k, as the operator would.
            data = obj.Controls.Table(k).Data;
            data{row, 2} = value;
            obj.Controls.Table(k).Data = data;
            obj.dirty(k) = true;
            obj.redraw(k);
        end

        function select(obj, k, row)
            % select(k, row) chooses channel k's row; a lit channel follows it.
            obj.selected(k) = row;
            obj.showSelected(k);
            if obj.lit(k)
                obj.lightOn(k);
            end
        end

        function next(obj, k)
            % next(k) goes to channel k's next row; a lit channel follows it.
            obj.select(k, min(obj.selected(k) + 1, size(obj.Controls.Table(k).Data, 1)));
        end

        function lightOn(obj, k)
            % lightOn(k) lights channel k continuously at its selected row's current.
            if isempty(obj.led)
                return
            end
            data = obj.Controls.Table(k).Data;
            current = data{obj.selected(k), 1};
            try
                obj.led.lightOn(k, current);
                obj.lit(k) = true;
                obj.setStatus(sprintf('Channel %s on at %g mA, continuous. Read the power meter and type the power.', ...
                                      obj.Paths{k}.Channel, current), true);
            catch lightError
                obj.lit(k) = false;
                obj.setStatus(lightError.message, false);
            end
            obj.showLight(k);
        end

        function lightOff(obj, k)
            % lightOff(k) switches channel k off; lightOff() switches both off.
            if ~isvalid(obj)
                return
            end
            if nargin < 2
                k = 1:2;
            end
            for channel = k
                if ~isempty(obj.led) && isvalid(obj.led) && obj.lit(channel)
                    obj.led.lightOff(channel);
                end
                obj.lit(channel) = false;
                obj.showLight(channel);
            end
        end

        function switchOff(obj, k)
            % The Off button: stop channel k on the driver whether or not this window lit it.
            if ~isempty(obj.led) && isvalid(obj.led)
                obj.led.lightOff(k);
            end
            obj.lit(k) = false;
            obj.showLight(k);
            obj.setStatus(sprintf('Channel %s off.', obj.Paths{k}.Channel), true);
        end

        function cal = calibration(obj, k)
            % calibration(k) is the calibration channel k's readings make so far (errors
            % if they make none).
            data = obj.Controls.Table(k).Data;
            currents = cell2mat(data(:, 1));
            powers = cellfun(@readingOf, data(:, 2));
            cal = lum.led.makeCalibration(obj.Paths{k}, currents, powers, obj.Controls.Unit.Value, ...
                                          'Notes', obj.Controls.Notes.Value);
        end

        function ok = save(obj)
            % save() writes each channel's calibration, replacing any earlier one of its
            % cable. Channels without readings are skipped; true when at least one was
            % saved and none failed.
            ok = false;
            if strcmp(obj.Paths{1}.Cable, obj.Paths{2}.Cable)
                obj.setStatus('The same cable is chosen on A and B: choose two cables.', false);
                return
            end
            savedNames = {};
            problems = {};
            for k = 1:2
                if ~any(~isnan(cellfun(@readingOf, obj.Controls.Table(k).Data(:, 2))))
                    continue
                end
                try
                    cal = obj.calibration(k);
                    lum.led.saveCalibration(cal, obj.folder);
                catch saveError
                    problems{end+1} = sprintf('%s: %s', obj.Paths{k}.Cable, saveError.message); %#ok<AGROW>
                    continue
                end
                obj.Saved{end+1} = cal;
                obj.dirty(k) = false;
                obj.previous{k} = cal;
                savedNames{end+1} = sprintf('%s (channel %s)', cal.Cable, obj.Paths{k}.Channel); %#ok<AGROW>
                if ~isempty(obj.onSaved)
                    obj.onSaved(cal);
                end
                obj.redraw(k);
            end
            obj.showBundle();
            if ~isempty(problems)
                obj.setStatus(strjoin([{'Not saved:'}, problems], '  '), false);
            elseif isempty(savedNames)
                obj.setStatus('No readings to save.', false);
            else
                ok = true;
                obj.setStatus(sprintf('Saved %s in %s.', strjoin(savedNames, ' and '), ...
                                      obj.calibrationFolder()), true);
            end
        end

        function close(obj)
            % close() switches both channels off and closes the window.
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
        function build(obj, visible)
            t = obj.theme;
            obj.Figure = uifigure('Name', 'LuminoseFM - calibrate LED power', ...
                                  'Position', [80 60 1240 800], 'Color', t.Background, ...
                                  'Visible', visible, 'CloseRequestFcn', @(~, ~) obj.close());
            lum.gui.Form.waitForView(obj.Figure);
            outer = uigridlayout(obj.Figure, [4 1], 'RowHeight', {30, 150, '1x', 34}, ...
                                 'Padding', [14 10 14 12], 'RowSpacing', 8, 'BackgroundColor', t.Background);
            uilabel(outer, 'Text', 'Calibrate LED power: two cables at a time, one on each channel', ...
                    'FontSize', 15, 'FontWeight', 'bold', 'FontColor', t.Ink);

            % The pair of cables, and what every channel's readings share.
            top = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', 0, ...
                               'ColumnSpacing', 12, 'BackgroundColor', t.Background);
            form = lum.gui.Form.panel(top, 'Cables on the commutator', 3, t, 150);
            bundles = lum.fiberBundles();
            lum.gui.Form.label(form, 'Fiber bundle', t);
            obj.Controls.Bundle = uidropdown(form, 'Items', {bundles.Name}, 'Value', obj.bundleName, ...
                'ValueChangedFcn', @(~, ~) obj.bundleChanged(), ...
                'Tooltip', 'The bundle whose cables are on the commutator.');
            lum.gui.Form.label(form, 'Cables on A and B', t);
            row = uigridlayout(form, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', 0, ...
                               'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            names = {'A', 'B'};
            for k = 1:2
                channel = k;
                obj.Controls.Cable(k) = uidropdown(row, 'Items', {''}, ...
                    'ValueChangedFcn', @(source, event) obj.cableChanged(channel, event), ...
                    'Tooltip', sprintf(['The cable on the commutator lit by channel %s (Doric LED '...
                                        'channel %d).'], names{k}, k));
            end
            lum.gui.Form.label(form, 'Calibrated', t);
            obj.Controls.BundleNote = uilabel(form, 'Text', '', 'FontSize', 11, 'WordWrap', 'on');

            form = lum.gui.Form.panel(top, 'Readings', 3, t, 150);
            lum.gui.Form.label(form, 'Power meter reads', t);
            obj.Controls.Unit = uidropdown(form, 'Items', {'mW', 'uW'}, 'Value', 'mW', ...
                'ValueChangedFcn', @(~, ~) obj.redraw(1:2), 'Tooltip', 'The unit the power meter shows.');
            lum.gui.Form.label(form, 'Currents (mA)', t);
            row = uigridlayout(form, [1 4], 'ColumnWidth', {'1x', '1x', '1x', 60}, 'Padding', 0, ...
                               'ColumnSpacing', 4, 'BackgroundColor', t.Panel);
            highest = max(obj.maxCurrent);
            obj.Controls.From = uieditfield(row, 'numeric', 'Value', 0, 'Limits', [0 highest], ...
                'RoundFractionalValues', 'on', 'Tooltip', 'The first current, mA.');
            obj.Controls.To = uieditfield(row, 'numeric', 'Value', min(obj.DefaultCurrentsmA(end), highest), ...
                'Limits', [0 highest], 'RoundFractionalValues', 'on', ...
                'Tooltip', 'The last current, mA; never above a channel''s limit.');
            obj.Controls.Step = uieditfield(row, 'numeric', 'Value', 50, 'Limits', [1 1000], ...
                'RoundFractionalValues', 'on', 'Tooltip', 'The step between currents, mA.');
            uibutton(row, 'Text', 'Fill', 'ButtonPushedFcn', @(~, ~) obj.fill(), ...
                     'Tooltip', 'Replace both tables'' currents; their readings are cleared.');
            lum.gui.Form.label(form, 'Notes', t);
            obj.Controls.Notes = uieditfield(form, 'text', 'Value', '', ...
                'Placeholder', 'power meter, wavelength setting', ...
                'Tooltip', 'Saved with each calibration: the meter and its wavelength setting (465 nm).');

            % One column per channel.
            body = uigridlayout(outer, [1 2], 'ColumnWidth', {'1x', '1x'}, 'Padding', 0, ...
                                'ColumnSpacing', 12, 'BackgroundColor', t.Background);
            colours = {t.ChannelA, t.ChannelB};
            for k = 1:2
                obj.buildChannel(body, k, colours{k});
            end

            footer = uigridlayout(outer, [1 3], 'ColumnWidth', {'1x', 170, 100}, 'Padding', 0, ...
                                  'ColumnSpacing', 8, 'BackgroundColor', t.Background);
            obj.Controls.Status = uilabel(footer, 'Text', '', 'WordWrap', 'on', 'FontSize', 11);
            obj.Controls.Save = uibutton(footer, 'Text', 'Save calibrations', 'FontWeight', 'bold', ...
                'BackgroundColor', t.Accent, 'FontColor', [1 1 1], 'ButtonPushedFcn', @(~, ~) obj.save(), ...
                'Tooltip', ['Save each channel''s readings as the calibration of its cable on that '...
                            'channel, replacing any earlier one.']);
            uibutton(footer, 'Text', 'Close', 'ButtonPushedFcn', @(~, ~) obj.close(), ...
                     'Tooltip', 'Switch both channels off and close.');
            obj.fillCableLists(obj.cables);
            if isempty(obj.led)
                obj.setStatus(['No driver connected: set each current on the driver by hand, in '...
                               'continuous mode, read the power meter and type the power.'], false);
            else
                obj.setStatus(['Hold the power meter at a cable''s tip. Pick a row, On, type the power '...
                               'read, then Next. The light is continuous: keep the fibers away from any animal.'], true);
            end
        end

        function buildChannel(obj, parent, k, colour)
            t = obj.theme;
            box = uipanel(parent, 'Title', sprintf('Channel %s  (Doric LED channel %d)', char('A' + k - 1), k), ...
                          'FontWeight', 'bold', 'BackgroundColor', t.Panel, 'ForegroundColor', colour);
            grid = uigridlayout(box, [4 2], 'ColumnWidth', {262, '1x'}, ...
                                'RowHeight', {20, '1x', 28, 20}, 'Padding', [8 6 8 6], ...
                                'RowSpacing', 6, 'ColumnSpacing', 10, 'BackgroundColor', t.Panel);
            obj.Controls.PathNote(k) = uilabel(grid, 'Text', '', 'FontSize', 11, 'FontColor', t.Ink);
            obj.Controls.PathNote(k).Layout.Column = [1 2];
            channel = k;
            obj.Controls.Table(k) = uitable(grid, 'Data', cell(0, 3), ...
                'ColumnName', {'mA', 'Power', ['mW/mm' char(178)]}, 'RowName', [], ...
                'ColumnWidth', {60, 85, 95}, ...
                'ColumnEditable', [true true false], 'ColumnFormat', {'numeric', 'numeric', 'numeric'}, ...
                'CellEditCallback', @(~, ~) obj.edited(channel), ...
                'CellSelectionCallback', @(~, event) obj.cellSelected(channel, event));
            obj.Controls.Axes(k) = uiaxes(grid);
            obj.Controls.Axes(k).Layout.Row = [2 4];
            obj.Controls.Axes(k).Layout.Column = 2;
            obj.Controls.Axes(k).Toolbar.Visible = 'off';
            buttons = uigridlayout(grid, [1 3], 'ColumnWidth', {'1x', '1x', '1x'}, 'Padding', 0, ...
                                   'ColumnSpacing', 6, 'BackgroundColor', t.Panel);
            buttons.Layout.Row = 3;
            buttons.Layout.Column = 1;
            name = char('A' + k - 1);
            obj.Controls.On(k) = uibutton(buttons, 'Text', 'On', 'ButtonPushedFcn', @(~, ~) obj.lightOn(channel), ...
                'Tooltip', sprintf('Light channel %s continuously at the selected row''s current.', name));
            obj.Controls.Off(k) = uibutton(buttons, 'Text', 'Off', 'ButtonPushedFcn', @(~, ~) obj.switchOff(channel), ...
                'Tooltip', sprintf('Switch channel %s off.', name));
            obj.Controls.Next(k) = uibutton(buttons, 'Text', ['Next ' char(9656)], ...
                'ButtonPushedFcn', @(~, ~) obj.next(channel), ...
                'Tooltip', 'The next row; a lit channel follows it.');
            obj.Controls.Light(k) = uilabel(grid, 'Text', '', 'FontSize', 11);
            obj.Controls.Light(k).Layout.Row = 4;
            obj.Controls.Light(k).Layout.Column = 1;
            lum.gui.Form.setEnable({obj.Controls.On(k), obj.Controls.Off(k)}, ~isempty(obj.led));
        end

        function fillCableLists(obj, chosen)
            % Offer the chosen bundle's cables, keeping choices that fit.
            bundles = lum.fiberBundles();
            bundle = bundles(strcmp({bundles.Name}, obj.Controls.Bundle.Value));
            items = arrayfun(@(i) sprintf('%s (%d spots)', bundle.Cables{i}, bundle.Spots(i)), ...
                             1:numel(bundle.Cables), 'UniformOutput', false);
            if numel(chosen) ~= 2 || ~all(ismember(chosen, bundle.Cables))
                chosen = bundle.Defaults;
            end
            for k = 1:2
                obj.Controls.Cable(k).Items = items;
                obj.Controls.Cable(k).ItemsData = bundle.Cables;
                obj.Controls.Cable(k).Value = chosen{k};
            end
        end

        function bundleChanged(obj)
            if any(obj.dirty) && strcmp(obj.Figure.Visible, 'on')
                previousBundle = obj.bundleName;
                obj.confirmDiscard(find(obj.dirty), @() obj.bundleAccepted(), ...
                                   @() obj.restoreBundle(previousBundle));
            else
                obj.bundleAccepted();
            end
        end

        function bundleAccepted(obj)
            obj.fillCableLists({});
            obj.applyCableChoice();
        end

        function restoreBundle(obj, bundle)
            obj.Controls.Bundle.Value = bundle;
        end

        function cableChanged(obj, k, event)
            if obj.dirty(k) && strcmp(obj.Figure.Visible, 'on')
                obj.confirmDiscard(k, @() obj.applyCableChoice(), ...
                                   @() set(obj.Controls.Cable(k), 'Value', event.PreviousValue));
            else
                obj.applyCableChoice();
            end
        end

        function confirmDiscard(obj, channels, onYes, onNo)
            names = strjoin(arrayfun(@(k) obj.Paths{k}.Cable, channels, 'UniformOutput', false), ' and ');
            uiconfirm(obj.Figure, sprintf('The readings of the %s cable are not saved. Drop them?', names), ...
                      'Unsaved readings', 'Options', {'Drop them', 'Keep them'}, ...
                      'DefaultOption', 2, 'CancelOption', 2, 'Icon', 'warning', ...
                      'CloseFcn', @(~, event) choose(strcmp(event.SelectedOption, 'Drop them')));
            function choose(yes)
                if yes
                    onYes();
                else
                    onNo();
                end
            end
        end

        function applyCableChoice(obj)
            obj.bundleName = obj.Controls.Bundle.Value;
            obj.cables = {obj.Controls.Cable(1).Value, obj.Controls.Cable(2).Value};
            obj.useCables();
        end

        function useCables(obj)
            % Each channel starts again: light off, the default currents, no readings.
            obj.lightOff();
            S = struct('Light', struct('Bundle', obj.bundleName, 'Cables', {obj.cables}));
            for k = 1:2
                obj.Paths{k} = lum.led.lightPath(S, k);
                obj.previous{k} = lum.led.loadCalibration(obj.Paths{k}, obj.folder);
                path = obj.Paths{k};
                obj.Controls.PathNote(k).Text = sprintf('%s cable: %d fibers of %g um = %.4g mm2', ...
                    path.Cable, path.nFibers, 1000 * path.FiberDiameter, path.Area);
                currents = obj.DefaultCurrentsmA(obj.DefaultCurrentsmA <= obj.maxCurrent(k))';
                obj.setCurrents(k, currents);
            end
            obj.showBundle();
            if strcmp(obj.cables{1}, obj.cables{2})
                obj.setStatus('The same cable is chosen on A and B: choose the two on the commutator.', false);
            end
        end

        function setCurrents(obj, k, currents)
            blank = num2cell(NaN(numel(currents), 1));
            obj.Controls.Table(k).Data = [num2cell(currents(:)), blank, blank];
            obj.dirty(k) = false;
            obj.selected(k) = 1;
            obj.showSelected(k);
            obj.redraw(k);
        end

        function fill(obj)
            currents = (obj.Controls.From.Value:obj.Controls.Step.Value:obj.Controls.To.Value)';
            if isempty(currents)
                obj.setStatus('No currents between the first and the last.', false);
                return
            end
            for k = 1:2
                obj.setCurrents(k, currents(currents <= obj.maxCurrent(k)));
            end
        end

        function edited(obj, k)
            obj.dirty(k) = true;
            obj.redraw(k);
        end

        function cellSelected(obj, k, event)
            if ~isempty(event.Indices) && event.Indices(1, 1) ~= obj.selected(k)
                obj.select(k, event.Indices(1, 1));
            end
        end

        function showSelected(obj, k)
            data = obj.Controls.Table(k).Data;
            if isempty(data)
                obj.selected(k) = 1;
                return
            end
            obj.selected(k) = min(max(obj.selected(k), 1), size(data, 1));
            obj.showLight(k);
        end

        function showLight(obj, k)
            % The channel's lamp: lit at what, or off, and the row On would use.
            if ~isvalid(obj) || ~isfield(obj.Controls, 'Light') || numel(obj.Controls.Light) < k ...
                    || ~isvalid(obj.Controls.Light(k))
                return
            end
            data = obj.Controls.Table(k).Data;
            current = NaN;
            if ~isempty(data)
                current = data{obj.selected(k), 1};
            end
            if obj.lit(k)
                obj.Controls.Light(k).Text = sprintf('%s On, continuous, %g mA (row %d)', char(9679), ...
                                                     current, obj.selected(k));
                colours = {obj.theme.ChannelA, obj.theme.ChannelB};
                obj.Controls.Light(k).FontColor = colours{k};
                obj.Controls.Light(k).FontWeight = 'bold';
            else
                obj.Controls.Light(k).Text = sprintf('%s Off  |  row %d: %g mA', char(9675), ...
                                                     obj.selected(k), current);
                obj.Controls.Light(k).FontColor = obj.theme.Muted;
                obj.Controls.Light(k).FontWeight = 'normal';
            end
        end

        function showBundle(obj)
            % Which of the bundle's cables have a calibration on each channel, and from when.
            bundles = lum.fiberBundles();
            bundle = bundles(strcmp({bundles.Name}, obj.bundleName));
            parts = cell(1, numel(bundle.Cables));
            nDone = 0;
            for i = 1:numel(bundle.Cables)
                S = struct('Light', struct('Bundle', bundle.Name, 'Cables', {{bundle.Cables{i}, bundle.Cables{i}}}));
                dates = {'-', '-'};
                for k = 1:2
                    cal = lum.led.loadCalibration(lum.led.lightPath(S, k), obj.folder);
                    if ~isempty(cal)
                        dates{k} = cal.Date(1:10);
                        nDone = nDone + 1;
                    end
                end
                parts{i} = sprintf('%s: A %s, B %s', bundle.Cables{i}, dates{1}, dates{2});
            end
            obj.Controls.BundleNote.Text = strjoin(parts, '   |   ');
            if nDone == 2 * numel(bundle.Cables)
                obj.Controls.BundleNote.FontColor = obj.theme.Good;
            else
                obj.Controls.BundleNote.FontColor = obj.theme.Muted;
            end
        end

        function redraw(obj, channels)
            % Irradiance per row, the graphs, and whether the readings can be saved.
            scale = 1;
            if strcmp(obj.Controls.Unit.Value, 'uW')
                scale = 1e-3;
            end
            for k = channels
                data = obj.Controls.Table(k).Data;
                for i = 1:size(data, 1)
                    data{i, 3} = round(readingOf(data{i, 2}) * scale / obj.Paths{k}.Area, 2);
                end
                obj.Controls.Table(k).Data = data;
                partial = obj.Paths{k};
                partial.MeasuredOn = obj.Paths{k}.Channel;
                partial.MeasuredLEDChannel = obj.Paths{k}.LEDChannel;
                partial.CurrentmA = cell2mat(data(:, 1));
                partial.IrradiancemWmm2 = cell2mat(data(:, 3));
                ax = obj.Controls.Axes(k);
                lum.led.plotCalibration(ax, partial, obj.theme);
                ax.Title.String = sprintf('%s cable on channel %s', partial.Cable, partial.Channel);
                if max(partial.CurrentmA) > 0
                    ax.XLim = [0 max(partial.CurrentmA)];  % The table's range, readings or not
                end
                old = obj.previous{k};
                if ~isempty(old)
                    hold(ax, 'on');
                    plot(ax, old.CurrentmA, old.IrradiancemWmm2, '--', 'Color', obj.theme.Muted, ...
                         'LineWidth', 1);
                    hold(ax, 'off');
                    ax.Title.String = sprintf('%s  (dashed: saved %s)', ax.Title.String, old.Date(1:10));
                end
            end
            anyReadings = false;
            for k = 1:2
                anyReadings = anyReadings || any(~isnan(cellfun(@readingOf, obj.Controls.Table(k).Data(:, 2))));
            end
            obj.Controls.Save.Enable = lum.gui.Form.onOff(anyReadings);
        end

        function folder = calibrationFolder(obj)
            folder = obj.folder;
            if isempty(folder)
                folder = lum.led.calibrationFolder();
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
