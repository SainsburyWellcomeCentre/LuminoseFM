classdef Plots < handle
    % lum.sleep.Plots is a sleep session's live figure: the sync pulses being sent.
    %
    % A sleep session has no trials and no choices, so the figure shows only what it
    % puts on the sync line (D11):
    %   Header       subject, session length and pulse rule, the barcode and whether it
    %                was sent, pulses so far and time elapsed
    %   Sync line    the line as sent over the last 30 s, so the operator sees it pulse
    %   Pulses sent  every pulse's width against session time, so a jittered session
    %                shows its spread and a stalled one a gap
    %
    % As in lum.OnlinePlots, every handle is created in the constructor into
    % preallocated data and only updated afterwards, each update touches the new
    % pulses and the visible trace only, and there is one drawnow limitrate per block.
    % Closing the figure does not stop the session.
    %
    % See also: lum.sleep.run, lum.OnlinePlots, lum.gui.theme

    properties (SetAccess = private)
        Figure   % The figure this object owns
    end

    properties (Access = private)
        theme
        handles = struct()
        axesOf = struct()
        traceSeconds = 30   % Width of the sync line panel
        nTrace              % Most pulses the trace can hold
        maxPulses
        minutes             % Session time of each pulse, minutes from the first
        widthsMs            % Width of each pulse, ms
        nShown = 0          % Pulses already copied into minutes and widthsMs
        traceX
        traceY
        durationMinutes
    end

    methods
        function obj = Plots(S, varargin)
            % Plots(S) creates the figure and every handle in it.
            %
            % Options:
            %   'Subject'    Shown in the header
            %   'MaxPulses'  Pulses to preallocate for (default: the session's worth)
            %   'Visible'    'on' (default) or 'off', for tests
            global BpodSystem %#ok<GVMIS> % Figures are registered so Bpod can close them

            sync = S.Sleep.Sync;
            shortestInterval = max(sync.Interval - sync.IntervalJitter, 1e-3);
            p = inputParser;
            p.FunctionName = 'lum.sleep.Plots';
            addParameter(p, 'Subject', '', @(x) ischar(x) || isstring(x));
            addParameter(p, 'MaxPulses', ceil(60 * S.Sleep.DurationMinutes / shortestInterval) + 1, ...
                         @(x) isnumeric(x) && isscalar(x) && x >= 1);
            addParameter(p, 'Visible', 'on');
            parse(p, varargin{:});

            t = lum.gui.theme();
            obj.theme = t;
            obj.maxPulses = p.Results.MaxPulses;
            obj.durationMinutes = S.Sleep.DurationMinutes;
            obj.nTrace = min(obj.maxPulses, ceil(obj.traceSeconds / shortestInterval) + 1);
            obj.minutes = NaN(1, obj.maxPulses);
            obj.widthsMs = NaN(1, obj.maxPulses);
            obj.traceX = NaN(1, 4 * obj.nTrace + 2);
            obj.traceY = NaN(1, 4 * obj.nTrace + 2);

            obj.Figure = figure('Name', 'LuminoseFM - sleep', 'NumberTitle', 'off', ...
                                'MenuBar', 'none', 'ToolBar', 'none', 'Color', t.Background, ...
                                'Position', [80 80 1100 640], 'Visible', p.Results.Visible);
            if ~isempty(BpodSystem) && isobject(BpodSystem)
                BpodSystem.ProtocolFigures.LuminoseSleepPlots = obj.Figure;
            end

            obj.buildHeader(S, char(p.Results.Subject));
            body = uipanel(obj.Figure, 'Units', 'normalized', 'Position', [0 0 1 0.88], ...
                           'BorderType', 'none', 'BackgroundColor', t.Background);
            tiles = tiledlayout(body, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
            obj.buildTracePanel(nexttile(tiles, 1));
            obj.buildWidthPanel(nexttile(tiles, 2), S);
            drawnow;
        end

        function showBarcode(obj, code, sent)
            % showBarcode(code, sent) says in the header which barcode opened the session.
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end
            if sent
                message = sprintf('Sleep barcode 0x%s sent (%.2f s, %g ms markers)', code.Hex, ...
                                  code.TotalDuration, 1000 * code.MarkerWidth);
            else
                message = sprintf('Sleep barcode 0x%s not sent: no sync line', code.Hex);
            end
            set(obj.handles.barcode, 'String', message);
        end

        function update(obj, onsets, widths, nPulses, elapsedSeconds)
            % update(onsets, widths, nPulses, elapsedSeconds) shows the pulses sent so
            % far; onsets and widths are the session's preallocated series, in seconds.
            if isempty(obj.Figure) || ~isvalid(obj.Figure) || nPulses < 1
                return
            end
            first = obj.nShown + 1;
            if nPulses >= first
                obj.minutes(first:nPulses) = (onsets(first:nPulses) - onsets(1)) / 60;
                obj.widthsMs(first:nPulses) = 1000 * widths(first:nPulses);
                obj.nShown = nPulses;
            end
            set(obj.handles.widths, 'XData', obj.minutes, 'YData', obj.widthsMs);
            set(obj.axesOf.widths, 'XLim', [0, max(1, 1.05 * obj.minutes(nPulses))]);

            % The trace: the last pulses as line levels, in seconds before the newest.
            latest = onsets(nPulses);
            oldest = max(1, nPulses - obj.nTrace + 1);
            while oldest < nPulses && latest - onsets(oldest) > obj.traceSeconds
                oldest = oldest + 1;
            end
            obj.traceX(:) = NaN;
            obj.traceY(:) = NaN;
            obj.traceX(1) = -obj.traceSeconds;
            obj.traceY(1) = 0;
            k = 1;
            for i = oldest:nPulses
                on = onsets(i) - latest;
                off = on + widths(i);
                obj.traceX(k + 1:k + 4) = [on on off off];
                obj.traceY(k + 1:k + 4) = [0 1 1 0];
                k = k + 4;
            end
            obj.traceX(k + 1) = widths(nPulses) + 1;
            obj.traceY(k + 1) = 0;
            set(obj.handles.trace, 'XData', obj.traceX, 'YData', obj.traceY);

            set(obj.handles.summary, 'String', obj.summaryText(nPulses, elapsedSeconds));
            drawnow limitrate;
        end

        function text = summaryText(obj, nPulses, elapsedSeconds)
            % summaryText(nPulses, elapsedSeconds) is the one-line session summary.
            text = sprintf('%d pulse(s) sent  |  %02d:%02d:%02d of %g min', nPulses, ...
                           floor(elapsedSeconds / 3600), floor(mod(elapsedSeconds, 3600) / 60), ...
                           floor(mod(elapsedSeconds, 60)), obj.durationMinutes);
        end

        function close(obj)
            % close() closes the figure, if it is still open.
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                close(obj.Figure);
            end
        end
    end

    methods (Access = private)
        function buildHeader(obj, S, subject)
            t = obj.theme;
            header = uipanel(obj.Figure, 'Units', 'normalized', 'Position', [0 0.88 1 0.12], ...
                             'BorderType', 'none', 'BackgroundColor', t.Background);
            logoImage = lum.gui.logo(48);
            if ~isempty(logoImage)
                logoAxes = axes('Parent', header, 'Units', 'normalized', ...
                                'Position', [0.004 0.1 0.05 0.8], 'Visible', 'off');
                image(logoAxes, logoImage);
                axis(logoAxes, 'image', 'off');
            end
            if isempty(subject)
                subject = '-';
            end
            sync = S.Sleep.Sync;
            if sync.Mode == lum.SyncMode.FixedWidth
                widthText = sprintf('%g ms', 1000 * sync.FixedWidth);
            else
                widthText = sprintf('%g +/- %g ms', 1000 * sync.MeanWidth, 1000 * sync.WidthJitter);
            end
            titleText = sprintf('LuminoseFM  |  %s  |  sleep session, %g min  |  a %s pulse every %g s', ...
                                subject, S.Sleep.DurationMinutes, widthText, sync.Interval);
            if sync.IntervalJitter > 0
                titleText = sprintf('%s +/- %g s', titleText, sync.IntervalJitter);
            end
            uicontrol(header, 'Style', 'text', 'Units', 'normalized', 'Position', [0.06 0.62 0.92 0.32], ...
                      'String', titleText, 'FontSize', 12, 'FontWeight', 'bold', ...
                      'HorizontalAlignment', 'left', 'BackgroundColor', t.Background, 'ForegroundColor', t.Ink);
            obj.handles.barcode = uicontrol(header, 'Style', 'text', 'Units', 'normalized', ...
                      'Position', [0.06 0.34 0.92 0.26], 'String', 'Barcode not sent yet', 'FontSize', 10, ...
                      'HorizontalAlignment', 'left', 'BackgroundColor', t.Background, 'ForegroundColor', t.Muted);
            obj.handles.summary = uicontrol(header, 'Style', 'text', 'Units', 'normalized', ...
                      'Position', [0.06 0.05 0.92 0.26], 'String', 'Waiting for the first pulses', ...
                      'FontSize', 10, 'HorizontalAlignment', 'left', 'BackgroundColor', t.Background, ...
                      'ForegroundColor', t.Muted);
        end

        function buildTracePanel(obj, ax)
            t = obj.theme;
            styleAxes(ax, t, sprintf('Sync line, last %d s', obj.traceSeconds));
            obj.axesOf.trace = ax;
            obj.handles.trace = line(ax, obj.traceX, obj.traceY, 'Color', t.Accent, 'LineWidth', 1.5);
            set(ax, 'XLim', [-obj.traceSeconds, 1], 'YLim', [-0.15 1.25], 'YTick', [0 1], ...
                'YTickLabel', {'low', 'high'});
            xlabel(ax, 'Seconds before the latest pulse');
        end

        function buildWidthPanel(obj, ax, S)
            t = obj.theme;
            styleAxes(ax, t, 'Pulses sent');
            obj.axesOf.widths = ax;
            obj.handles.widths = line(ax, obj.minutes, obj.widthsMs, 'LineStyle', 'none', ...
                'Marker', '.', 'MarkerSize', 8, 'Color', t.Accent);
            sync = S.Sleep.Sync;
            if sync.Mode == lum.SyncMode.FixedWidth
                limits = 1000 * sync.FixedWidth * [0.5 1.5];
            else
                limits = 1000 * [max(0, sync.MeanWidth - 1.3 * sync.WidthJitter), ...
                                 sync.MeanWidth + 1.3 * sync.WidthJitter];
            end
            if limits(2) <= limits(1)
                limits = limits(1) + [-1 1];
            end
            set(ax, 'XLim', [0 1], 'YLim', limits);
            xlabel(ax, 'Session time (min)');
            ylabel(ax, 'Pulse width (ms)');
        end
    end
end


function styleAxes(ax, t, titleText)
% The look every panel shares; the same as lum.OnlinePlots.
set(ax, 'Color', t.Panel, 'XColor', t.Muted, 'YColor', t.Muted, 'GridColor', t.Faint, ...
    'GridAlpha', 1, 'Box', 'off', 'TickDir', 'out', 'FontSize', 9, 'LineWidth', 0.75, ...
    'XGrid', 'on', 'YGrid', 'on');
ax.Title.String = titleText;
ax.Title.FontWeight = 'bold';
ax.Title.FontSize = 10;
ax.Title.Color = t.Ink;
ax.TitleHorizontalAlignment = 'left';
hold(ax, 'on');
end
