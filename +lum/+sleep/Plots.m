classdef Plots < handle
    % lum.sleep.Plots is a sleep session's live figure: the sync pulses and test pulses sent.
    %
    % A sleep session has no trials and no choices, so the figure shows what it puts on
    % its lines (D11, D13):
    %   Header        subject, session length and pulse rule, the test pulses, the
    %                 barcode and whether it was sent, pulses so far and time elapsed
    %   Schedule      (test pulses only) every step on channels A and B across the
    %                 session, with the part already sent shaded
    %   Lines         the sync line — and channels A and B — as sent over the last 30 s
    %   Latest epoch  (test pulses only) the last epoch sent: its gates, and the light
    %                 PulsePal puts in them, so a pair of probes or a burst can be read
    %   Pulses sent   every sync pulse's width against session time, so a jittered
    %                 session shows its spread and a stalled one a gap
    %   Epochs sent   (test pulses only) epochs sent against planned, step by step
    %
    % As in lum.OnlinePlots, every handle is created in the constructor into
    % preallocated data and only updated afterwards, each update touches the new pulses
    % and the visible trace only, and there is one drawnow limitrate per block. Closing
    % the figure does not stop the session.
    %
    % See also: lum.sleep.run, lum.OnlinePlots, lum.gui.drawTestPulseSchedule, lum.gui.theme

    properties (SetAccess = private)
        Figure   % The figure this object owns
    end

    properties (Access = private)
        theme
        handles = struct()
        axesOf = struct()
        traceSeconds = 30   % Width of the lines panel
        nTrace              % Most sync pulses the trace can hold
        maxPulses
        minutes             % Session time of each sync pulse, minutes from the first
        widthsMs            % Width of each sync pulse, ms
        nShown = 0          % Sync pulses already copied into minutes and widthsMs
        traceX
        traceY
        syncLane = 0        % Where the sync line sits on the lines panel, and how tall
        laneHeight = 1
        durationMinutes

        plan                % From lum.sleep.testPulsePlan
        hasLight = false
        nLightTrace         % Most gates of light the trace can hold
        lightX              % 2 x (4 nLightTrace + 2): A's trace, then B's
        lightY
        stepSent            % Epochs sent, per step
        stepPlanned         % Epochs planned, per step
        nLightShown = 0     % Gates already counted into stepSent
        shownEpoch = [0 0]  % Step and epoch on the latest-epoch panel
        maxGates
        maxEpochPulses
    end

    methods
        function obj = Plots(S, varargin)
            % Plots(S) creates the figure and every handle in it.
            %
            % Options:
            %   'Subject'    Shown in the header
            %   'Plan'       From lum.sleep.testPulsePlan (default: compiled from S)
            %   'MaxPulses'  Sync pulses to preallocate for (default: the session's worth)
            %   'Visible'    'on' (default) or 'off', for tests
            global BpodSystem %#ok<GVMIS> % Figures are registered so Bpod can close them

            sync = S.Sleep.Sync;
            shortestInterval = max(sync.Interval - sync.IntervalJitter, 1e-3);
            p = inputParser;
            p.FunctionName = 'lum.sleep.Plots';
            addParameter(p, 'Subject', '', @(x) ischar(x) || isstring(x));
            addParameter(p, 'Plan', [], @(x) isempty(x) || isstruct(x));
            addParameter(p, 'MaxPulses', [], @(x) isempty(x) || (isnumeric(x) && isscalar(x) && x >= 1));
            addParameter(p, 'Visible', 'on');
            parse(p, varargin{:});

            t = lum.gui.theme();
            obj.theme = t;
            plan = p.Results.Plan;
            if isempty(plan)
                plan = lum.sleep.testPulsePlan(S.Sleep.TestPulses);
            end
            obj.plan = plan;
            obj.hasLight = ~isempty(plan.Steps);
            if obj.hasLight
                obj.durationMinutes = plan.Duration / 60;
                obj.syncLane = 2.4;
                obj.laneHeight = 0.9;
            else
                obj.durationMinutes = S.Sleep.DurationMinutes;
            end
            obj.maxPulses = p.Results.MaxPulses;
            if isempty(obj.maxPulses)
                obj.maxPulses = ceil(60 * obj.durationMinutes / shortestInterval) + 1;
            end
            obj.nTrace = min(obj.maxPulses, ceil(obj.traceSeconds / shortestInterval) + 1);
            obj.minutes = NaN(1, obj.maxPulses);
            obj.widthsMs = NaN(1, obj.maxPulses);
            obj.traceX = NaN(1, 4 * obj.nTrace + 2);
            obj.traceY = NaN(1, 4 * obj.nTrace + 2);
            obj.nLightTrace = max(1, min(size(plan.Segments, 1), 4000));
            obj.lightX = NaN(2, 4 * obj.nLightTrace + 2);
            obj.lightY = NaN(2, 4 * obj.nLightTrace + 2);
            obj.stepSent = zeros(1, numel(plan.Steps));
            obj.stepPlanned = [plan.Steps.nEpochs];
            obj.maxGates = max(1, plan.MostSegmentsPerEpoch);
            obj.maxEpochPulses = max(1, min(plan.MostPulsesPerEpoch, 5000));

            obj.Figure = figure('Name', 'LuminoseFM - sleep', 'NumberTitle', 'off', ...
                                'MenuBar', 'none', 'ToolBar', 'none', 'Color', t.Background, ...
                                'Position', [80 60 1200 780], 'Visible', p.Results.Visible);
            if ~isempty(BpodSystem) && isobject(BpodSystem)
                BpodSystem.ProtocolFigures.LuminoseSleepPlots = obj.Figure;
            end

            obj.buildHeader(S, char(p.Results.Subject));
            body = uipanel(obj.Figure, 'Units', 'normalized', 'Position', [0 0 1 0.86], ...
                           'BorderType', 'none', 'BackgroundColor', t.Background);
            if obj.hasLight
                tiles = tiledlayout(body, 3, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
                obj.buildSchedulePanel(nexttile(tiles, 1, [1 3]));
                obj.buildTracePanel(nexttile(tiles, 4, [1 2]));
                obj.buildEpochPanel(nexttile(tiles, 6));
                obj.buildWidthPanel(nexttile(tiles, 7, [1 2]), S);
                obj.buildStepPanel(nexttile(tiles, 9));
            else
                tiles = tiledlayout(body, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
                obj.buildTracePanel(nexttile(tiles, 1));
                obj.buildWidthPanel(nexttile(tiles, 2), S);
            end
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

        function update(obj, sync, light, elapsedSeconds, planSeconds)
            % update(sync, light, elapsedSeconds, planSeconds) shows what has been sent.
            %
            %   sync         .Onset and .Width (s), the session's preallocated series,
            %                and .n, how many were sent
            %   light        .Onset (s) of each gate in the plan and .n sent; [] or n 0
            %                without test pulses
            %   planSeconds  How far through the timeline the session has got
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end
            nPulses = sync.n;
            nLight = 0;
            if obj.hasLight && ~isempty(light)
                nLight = light.n;
            end
            if nPulses < 1 && nLight < 1
                return
            end

            latest = -Inf;
            if nPulses >= 1
                first = obj.nShown + 1;
                if nPulses >= first
                    obj.minutes(first:nPulses) = (sync.Onset(first:nPulses) - sync.Onset(1)) / 60;
                    obj.widthsMs(first:nPulses) = 1000 * sync.Width(first:nPulses);
                    obj.nShown = nPulses;
                end
                set(obj.handles.widths, 'XData', obj.minutes, 'YData', obj.widthsMs);
                set(obj.axesOf.widths, 'XLim', [0, max(1, 1.05 * obj.minutes(nPulses))]);
                latest = sync.Onset(nPulses);
            end
            if nLight >= 1
                latest = max(latest, light.Onset(nLight));
            end
            obj.drawSyncTrace(sync, nPulses, latest);

            if obj.hasLight
                obj.drawLightTrace(light, nLight, latest);
                obj.countEpochs(nLight);
                done = min(planSeconds / 60, obj.durationMinutes);
                set(obj.handles.done, 'XData', [0 done done 0]);
                set(obj.handles.now, 'XData', [done done]);
                if nLight >= 1 && ~isequal(obj.plan.Segments(nLight, 4:5), obj.shownEpoch)
                    obj.shownEpoch = obj.plan.Segments(nLight, 4:5);
                    obj.showEpoch(obj.shownEpoch(1), obj.shownEpoch(2));
                end
            end

            set(obj.handles.summary, 'String', obj.summaryText(nPulses, elapsedSeconds));
            drawnow limitrate;
        end

        function text = summaryText(obj, nPulses, elapsedSeconds)
            % summaryText(nPulses, elapsedSeconds) is the one-line session summary.
            text = sprintf('%d pulse(s) sent', nPulses);
            if obj.hasLight
                text = sprintf('%s  |  %d of %d epoch(s) of test pulses', text, sum(obj.stepSent), ...
                               sum([obj.plan.Steps.nEpochs]));
            end
            text = sprintf('%s  |  %02d:%02d:%02d of %.4g min', text, ...
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
        function drawSyncTrace(obj, sync, nPulses, latest)
            % The sync line over the last traceSeconds, in seconds before the newest onset.
            obj.traceX(:) = NaN;
            obj.traceY(:) = NaN;
            base = obj.syncLane;
            obj.traceX(1) = -obj.traceSeconds;
            obj.traceY(1) = base;
            k = 1;
            if nPulses >= 1
                oldest = max(1, nPulses - obj.nTrace + 1);
                while oldest < nPulses && latest - sync.Onset(oldest) > obj.traceSeconds
                    oldest = oldest + 1;
                end
                for i = oldest:nPulses
                    on = sync.Onset(i) - latest;
                    off = on + sync.Width(i);
                    obj.traceX(k + 1:k + 4) = [on on off off];
                    obj.traceY(k + 1:k + 4) = base + [0 1 1 0] * obj.laneHeight;
                    k = k + 4;
                end
            end
            obj.traceX(k + 1) = 1;
            obj.traceY(k + 1) = base;
            set(obj.handles.trace, 'XData', obj.traceX, 'YData', obj.traceY);
        end

        function drawLightTrace(obj, light, nLight, latest)
            % Channels A and B over the same window, one lane each.
            obj.lightX(:) = NaN;
            obj.lightY(:) = NaN;
            lanes = [1.2 0];
            used = [1 1];
            obj.lightX(:, 1) = -obj.traceSeconds;
            obj.lightY(:, 1) = lanes';
            if nLight >= 1
                oldest = max(1, nLight - obj.nLightTrace + 1);
                while oldest < nLight && latest - light.Onset(oldest) > obj.traceSeconds
                    oldest = oldest + 1;
                end
                for i = oldest:nLight
                    c = obj.plan.Segments(i, 3);
                    on = light.Onset(i) - latest;
                    off = on + obj.plan.Segments(i, 2) * obj.plan.CyclePeriod;
                    k = used(c);
                    obj.lightX(c, k + 1:k + 4) = [on on off off];
                    obj.lightY(c, k + 1:k + 4) = lanes(c) + [0 0.9 0.9 0];
                    used(c) = k + 4;
                end
            end
            for c = 1:2
                obj.lightX(c, used(c) + 1) = 1;
                obj.lightY(c, used(c) + 1) = lanes(c);
                set(obj.handles.light(c), 'XData', obj.lightX(c, :), 'YData', obj.lightY(c, :));
            end
        end

        function countEpochs(obj, nLight)
            % Count each epoch once, at its first gate.
            segments = obj.plan.Segments;
            for i = obj.nLightShown + 1:nLight
                if i == 1 || any(segments(i, 4:5) ~= segments(i - 1, 4:5))
                    step = segments(i, 4);
                    obj.stepSent(step) = obj.stepSent(step) + 1;
                end
            end
            obj.nLightShown = max(obj.nLightShown, nLight);
            set(obj.handles.stepSent, 'YData', obj.stepSent);
            for step = find(obj.stepPlanned > 0)
                set(obj.handles.stepCounts(step), 'String', ...
                    sprintf('%d/%d', obj.stepSent(step), obj.stepPlanned(step)));
            end
        end

        function showEpoch(obj, step, epoch)
            % Redraw the latest-epoch panel for one epoch, into the existing patches.
            shape = lum.sleep.epochShape(obj.plan, step, epoch);
            [scale, unit] = timeScale(shape.Length);
            t = obj.theme;
            [vertices, colours] = rectangles(shape.Gates, obj.maxGates, scale, t);
            set(obj.handles.gates, 'Vertices', vertices, 'FaceVertexCData', colours);
            [vertices, colours] = rectangles(shape.Pulses, obj.maxEpochPulses, scale, t);
            set(obj.handles.pulses, 'Vertices', vertices, 'FaceVertexCData', colours);
            ax = obj.axesOf.epoch;
            set(ax, 'XLim', [-0.04, 1.04] * shape.Length * scale);
            ax.XLabel.String = sprintf('%s from the epoch''s onset', unit);
            ax.Title.String = sprintf('Latest epoch: step %d (%s), epoch %d', step, ...
                                      obj.plan.Steps(step).Kind, epoch);
        end

        function buildHeader(obj, S, subject)
            t = obj.theme;
            header = uipanel(obj.Figure, 'Units', 'normalized', 'Position', [0 0.86 1 0.14], ...
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
            titleText = sprintf('LuminoseFM  |  %s  |  sleep session, %.4g min  |  a %s pulse every %g s', ...
                                subject, obj.durationMinutes, widthText, sync.Interval);
            if sync.IntervalJitter > 0
                titleText = sprintf('%s +/- %g s', titleText, sync.IntervalJitter);
            end
            if obj.hasLight
                description = lum.sleep.describeTestPulses(S.Sleep.TestPulses, obj.plan);
                lightText = strjoin(description(1:2), '  |  ');
            else
                lightText = 'No test pulses';
            end
            uicontrol(header, 'Style', 'text', 'Units', 'normalized', 'Position', [0.06 0.74 0.92 0.22], ...
                      'String', titleText, 'FontSize', 12, 'FontWeight', 'bold', ...
                      'HorizontalAlignment', 'left', 'BackgroundColor', t.Background, 'ForegroundColor', t.Ink);
            uicontrol(header, 'Style', 'text', 'Units', 'normalized', 'Position', [0.06 0.50 0.92 0.22], ...
                      'String', lightText, 'FontSize', 10, 'HorizontalAlignment', 'left', ...
                      'BackgroundColor', t.Background, 'ForegroundColor', t.Ink);
            obj.handles.barcode = uicontrol(header, 'Style', 'text', 'Units', 'normalized', ...
                      'Position', [0.06 0.27 0.92 0.21], 'String', 'Barcode not sent yet', 'FontSize', 10, ...
                      'HorizontalAlignment', 'left', 'BackgroundColor', t.Background, 'ForegroundColor', t.Muted);
            obj.handles.summary = uicontrol(header, 'Style', 'text', 'Units', 'normalized', ...
                      'Position', [0.06 0.04 0.92 0.21], 'String', 'Waiting for the first pulses', ...
                      'FontSize', 10, 'HorizontalAlignment', 'left', 'BackgroundColor', t.Background, ...
                      'ForegroundColor', t.Muted);
        end

        function buildSchedulePanel(obj, ax)
            t = obj.theme;
            styleAxes(ax, t, 'Test-pulse schedule');
            obj.axesOf.schedule = ax;
            lum.gui.drawTestPulseSchedule(ax, obj.plan, t);
            hold(ax, 'on');
            obj.handles.done = patch(ax, 'XData', [0 0 0 0], 'YData', [0 0 2.5 2.5], ...
                                     'FaceColor', t.Ink, 'FaceAlpha', 0.08, 'EdgeColor', 'none');
            obj.handles.now = line(ax, [0 0], [0 2.5], 'Color', t.Ink, 'LineWidth', 1.5);
            set(ax, 'XGrid', 'off', 'YGrid', 'off');
        end

        function buildTracePanel(obj, ax)
            t = obj.theme;
            styleAxes(ax, t, sprintf('Lines, last %d s', obj.traceSeconds));
            obj.axesOf.trace = ax;
            obj.handles.trace = line(ax, obj.traceX, obj.traceY, 'Color', t.Accent, 'LineWidth', 1.5);
            if obj.hasLight
                obj.handles.light = [ ...
                    line(ax, obj.lightX(1, :), obj.lightY(1, :), 'Color', t.ChannelA, 'LineWidth', 1.5), ...
                    line(ax, obj.lightX(2, :), obj.lightY(2, :), 'Color', t.ChannelB, 'LineWidth', 1.5)];
                set(ax, 'XLim', [-obj.traceSeconds, 1], 'YLim', [-0.15 3.45], ...
                    'YTick', [0.45 1.65 2.85], 'YTickLabel', {'B', 'A', 'sync'});
            else
                set(ax, 'XLim', [-obj.traceSeconds, 1], 'YLim', [-0.15 1.25], 'YTick', [0 1], ...
                    'YTickLabel', {'low', 'high'});
            end
            xlabel(ax, 'Seconds before the latest pulse');
        end

        function buildEpochPanel(obj, ax)
            t = obj.theme;
            styleAxes(ax, t, 'Latest epoch');
            obj.axesOf.epoch = ax;
            for lane = [0.15 1.15]
                patch(ax, 'XData', [-1e6 1e6 1e6 -1e6], 'YData', lane + [0 0 0.7 0.7], ...
                      'FaceColor', t.Dark, 'EdgeColor', 'none');
            end
            obj.handles.gates = patch(ax, 'Faces', reshape(1:4 * obj.maxGates, 4, [])', ...
                'Vertices', zeros(4 * obj.maxGates, 2), 'FaceColor', 'flat', ...
                'FaceVertexCData', zeros(obj.maxGates, 3), 'FaceAlpha', 0.25, 'EdgeColor', 'none');
            obj.handles.pulses = patch(ax, 'Faces', reshape(1:4 * obj.maxEpochPulses, 4, [])', ...
                'Vertices', zeros(4 * obj.maxEpochPulses, 2), 'FaceColor', 'flat', ...
                'FaceVertexCData', zeros(obj.maxEpochPulses, 3), 'EdgeColor', 'none');
            set(ax, 'XLim', [0 1], 'YLim', [0 2], 'YTick', [0.5 1.5], 'YTickLabel', {'B', 'A'}, ...
                'YGrid', 'off');
            xlabel(ax, 'ms from the epoch''s onset');
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
            ylabel(ax, 'Sync pulse width (ms)');
        end

        function buildStepPanel(obj, ax)
            t = obj.theme;
            styleAxes(ax, t, 'Epochs sent, by step');
            obj.axesOf.steps = ax;
            planned = obj.stepPlanned;
            n = numel(planned);
            bar(ax, 1:n, planned, 0.7, 'FaceColor', t.Faint, 'EdgeColor', 'none');
            obj.handles.stepSent = bar(ax, 1:n, zeros(1, n), 0.4, 'FaceColor', t.Accent, ...
                                       'EdgeColor', 'none');
            % Counts over the bars, so a step of five trains reads beside one of 7200 probes.
            obj.handles.stepCounts = gobjects(1, n);
            for step = 1:n
                label = '';
                if planned(step) > 0
                    label = sprintf('0/%d', planned(step));
                end
                obj.handles.stepCounts(step) = text(ax, step, planned(step), label, ...
                    'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', ...
                    'FontSize', 8, 'Color', t.Muted);
            end
            set(ax, 'XLim', [0.4, n + 0.6], 'XTick', 1:n, 'YLim', [0, 1.2 * max(1, max(planned))], ...
                'XGrid', 'off');
            xlabel(ax, 'Step');
            ylabel(ax, 'Epochs');
        end
    end
end


function [scale, unit] = timeScale(seconds)
% Milliseconds for short epochs, seconds for long ones.
if seconds < 1
    scale = 1000;
    unit = 'ms';
else
    scale = 1;
    unit = 's';
end
end


function [vertices, colours] = rectangles(rows, capacity, scale, t)
% Patch vertices for [onset duration channel] rows in lanes A (above) and B (below);
% unused faces collapse to a point.
vertices = zeros(4 * capacity, 2);
colours = zeros(capacity, 3);
for r = 1:min(size(rows, 1), capacity)
    x0 = rows(r, 1) * scale;
    x1 = (rows(r, 1) + rows(r, 2)) * scale;
    if rows(r, 3) == 1
        y = [1.15 1.85];
        colours(r, :) = t.ChannelA;
    else
        y = [0.15 0.85];
        colours(r, :) = t.ChannelB;
    end
    vertices(4 * r - 3:4 * r, :) = [x0 y(1); x1 y(1); x1 y(2); x0 y(2)];
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
