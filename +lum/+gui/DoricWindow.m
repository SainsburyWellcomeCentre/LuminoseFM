classdef DoricWindow < handle
    % lum.gui.DoricWindow is the LED window: each channel's intensity during a session (D17).
    %
    % Shows the current each LED channel runs at, as irradiance too when its light path is
    % calibrated, and, in behaviour and sleep sessions, lets the operator change it. A
    % change is asked of the session's lum.dev.DoricLED (request) and sent in the next
    % prepare window, or between sleep blocks, so light already gated is never changed
    % part way through; until then the channel reads "waiting for the next trial". In an
    % ePhys calibration session the schedule sets the current, so the window only shows it.
    %
    % It never sends anything itself and costs the trial loop nothing: it redraws when
    % the LED says something changed. Closing it only hides it; close() deletes it.
    %
    % Usage:
    %   w = lum.gui.DoricWindow(devices.doricLED, S, 'Subject', subject, 'Editable', true, ...
    %                           'Calibrations', cals);
    %   w.close();
    %
    % See also: lum.dev.DoricLED, lum.gui.IntensityField, lum.gui.DoricSetup

    properties (SetAccess = private)
        Figure
        Controls = struct()
    end

    properties (Access = private)
        led
        theme
        cals
        editable
        fields = {}
        listener = []
    end

    methods
        function obj = DoricWindow(led, S, varargin)
            p = inputParser;
            addParameter(p, 'Subject', '');
            addParameter(p, 'Editable', true);
            addParameter(p, 'Calibrations', {[], []});
            addParameter(p, 'Visible', 'on');
            parse(p, varargin{:});
            obj.led = led;
            obj.theme = lum.gui.theme();
            obj.cals = p.Results.Calibrations;
            obj.editable = logical(p.Results.Editable) && led.isControlled();
            obj.build(S, char(p.Results.Subject), p.Results.Visible);
            obj.listener = addlistener(led, 'Changed', @(~, ~) obj.refresh());
            obj.refresh();
        end

        function refresh(obj)
            % refresh() shows the currents running and any waiting to be sent.
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end
            c = obj.Controls;
            c.State.Text = obj.led.describeState();
            for k = 1:2
                running = lum.led.describe(obj.cals{k}, obj.led.CurrentmA(k));
                if ~isnan(obj.led.Pending(k))
                    running = sprintf('%s  |  %s waiting for the next trial', running, ...
                                      lum.led.describe(obj.cals{k}, obj.led.Pending(k)));
                end
                c.Running(k).Text = running;
            end
        end

        function apply(obj, k)
            % apply(k) asks for the current typed for channel k.
            try
                obj.led.request(k, obj.fields{k}.currentmA());
            catch requestError
                uialert(obj.Figure, requestError.message, 'LED current');
            end
        end

        function close(obj)
            if ~isvalid(obj)
                return
            end
            if ~isempty(obj.listener) && isvalid(obj.listener)
                delete(obj.listener);
            end
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Access = private)
        function build(obj, S, subject, visible)
            t = obj.theme;
            if isempty(subject)
                subject = '-';
            end
            obj.Figure = uifigure('Name', 'LuminoseFM - LED', 'Position', [1300 520 520 330], ...
                                  'Color', t.Background, 'Visible', visible, ...
                                  'CloseRequestFcn', @(source, ~) set(source, 'Visible', 'off'));
            outer = uigridlayout(obj.Figure, [5 1], 'RowHeight', {26, 34, 104, 104, '1x'}, ...
                                 'Padding', [12 10 12 10], 'RowSpacing', 6, 'BackgroundColor', t.Background);
            uilabel(outer, 'Text', sprintf('Doric LED  |  %s', subject), 'FontSize', 15, ...
                    'FontWeight', 'bold', 'FontColor', t.Ink);
            obj.Controls.State = uilabel(outer, 'Text', '', 'WordWrap', 'on', 'FontSize', 11, ...
                                         'FontColor', t.Muted);
            colours = {t.ChannelA, t.ChannelB};
            names = {'Channel A  (LED channel 1)', 'Channel B  (LED channel 2)'};
            for k = 1:2
                box = uipanel(outer, 'Title', names{k}, 'FontWeight', 'bold', ...
                              'BackgroundColor', t.Panel, 'ForegroundColor', colours{k});
                grid = uigridlayout(box, [2 4], 'ColumnWidth', {90, 90, '1x', 110}, ...
                                    'RowHeight', {22, 26}, 'Padding', [8 6 8 6], 'RowSpacing', 6, ...
                                    'ColumnSpacing', 8, 'BackgroundColor', t.Panel);
                uilabel(grid, 'Text', 'Running', 'FontColor', t.Ink);
                obj.Controls.Running(k) = uilabel(grid, 'Text', '', 'FontColor', t.Ink);
                obj.Controls.Running(k).Layout.Column = [2 4];
                uilabel(grid, 'Text', 'Set to', 'FontColor', t.Ink);
                start = S.Doric.CurrentmA(k);
                if ~isnan(obj.led.CurrentmA(k))
                    start = obj.led.CurrentmA(k);
                end
                obj.fields{k} = lum.gui.IntensityField(grid, start, @() [], ...
                    'Tooltip', 'The new intensity, sent before the next trial (or sleep block).');
                obj.fields{k}.setCalibration(obj.cals{k});
                channel = k;
                obj.Controls.Apply(k) = uibutton(grid, 'Text', 'Apply', ...
                    'ButtonPushedFcn', @(~, ~) obj.apply(channel), ...
                    'Tooltip', 'Send this intensity before the next trial or sleep block.');
                obj.fields{k}.setEnable(obj.editable);
                obj.Controls.Apply(k).Enable = lum.gui.Form.onOff(obj.editable);
            end
            if obj.editable
                note = ['A new intensity is sent between trials (or sleep blocks), never while light is '...
                        'gated, and each trial records the current it ran at.'];
            elseif obj.led.isControlled()
                note = 'The ePhys calibration schedule sets the current, step by step.';
            else
                note = 'The LED is set by hand on the driver in this session.';
            end
            lum.gui.Form.note(outer, note, t);
        end
    end
end
