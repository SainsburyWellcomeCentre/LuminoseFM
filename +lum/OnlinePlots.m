classdef OnlinePlots < handle
    % lum.OnlinePlots owns a behaviour session's live figure.
    %
    % One figure, all graphics handles created in the constructor and only ever
    % updated afterwards with set(h, 'YData', ...). Nothing in the trial loop calls
    % figure, plot or cla, and there is exactly one drawnow limitrate per trial — the
    % online display is the easiest place to accumulate per-trial cost, and this is
    % where the real-time requirement is most often lost.
    %
    % Every panel is fed from arrays this object maintains itself, updated from the
    % trial that just finished, so the per-trial cost does not grow with the session.
    % Axis limits follow the data: the per-trial panels scroll with the session and
    % rescale to what is on screen, so they stay legible at trial 5 and at trial 900.
    %
    % Panels (README §4.7), laid out in the order the operator reads them:
    %   Top row
    %     Now and next  The pattern of the running trial and the next three queued,
    %                   shown from the start of the session (showNext)
    %     Outcomes      Each trial's choice by stimulus group (or, in continuous mode,
    %                   by the B share of its light): correct, incorrect or no choice
    %   Middle row
    %     Performance   Fraction correct over a moving window: all, left- and
    %                   right-rewarded trials
    %     Psychometric  P(choose left) with binomial error bars, laid out for the set:
    %                   one point for one group, the two groups for two, the swept
    %                   parameter for more, B-share bins in continuous mode — with the
    %                   contingency the animal is trained on drawn behind it
    %     Evidence      Every choice at the latent evidence its trial's stimulus carried
    %                   on each channel, u_A against u_B (the fraction of the stimulus
    %                   window A and B were lit), coloured correct or incorrect and
    %                   pointing to the side chosen, so the animal's decision boundary
    %                   shows: vertical or horizontal if it reads one channel, diagonal
    %                   if it weighs both
    %   Bottom row
    %     By side       Fraction correct on left- and right-rewarded trials
    %     Side bias     P(chose left) over the last BiasWindow choices, with the
    %                   P(left) bias correction aimed for on each trial
    %     Reaction time Per trial, by side chosen, with a running median
    %
    % See also: lum.newHistory, lum.scoreTrial, lum.pattern.stimulusSet, lum.gui.theme,
    %           lum.sleep.Plots

    properties (SetAccess = private)
        Figure          % The single figure this object owns
        nTrialsToShow   % Width of the scrolling window on the per-trial panels
        RefreshEvery    % Aggregate panels are redrawn every this many trials
    end

    properties (Access = private)
        theme
        stimulusSet             % Stimulus set, without its States
        handles = struct()
        axesOf = struct()       % Each panel's axes, by panel
        movingWindow
        biasWindow              % Choices the side-bias panel averages over
        nSlots = 4
        maxSegments

        rasterOfPattern       % Outcome-raster y of each pattern
        psychometricIndex     % Psychometric point each pattern counts towards
        psychometricTrials
        psychometricLeft
        lightA                % Fraction of the stimulus window each pattern lights A
        lightB                % ... and B

        % Per-trial series, preallocated to the session's maximum length
        correctY
        incorrectY
        noChoiceY
        correctness
        sideOfTrial
        performanceY
        leftPerformanceY
        rightPerformanceY
        reactionTimes
        leftReactionY
        rightReactionY
        medianReactionY
        biasLeftY             % P(chose left) over the last biasWindow choices, per trial
        biasTargetY           % The P(left) bias correction aimed for, per trial
        choseLeft             % One entry per choice made: 1 left, 0 right
        planeX                % u_A of each choice, by correct/incorrect and side chosen:
        planeY                % 4 x nTrials, rows correct-left, correct-right,
                              % incorrect-left, incorrect-right

        % Running aggregates, updated in O(1)
        barTrials = zeros(1, 2)   % Left-rewarded, right-rewarded
        barCorrect = zeros(1, 2)
        nChoices = 0
        nCorrect = 0
        nRewarded = 0
        water = 0
        lastTrial = 0
        clock
    end

    methods
        function obj = OnlinePlots(S, stimulusSet, varargin)
            % OnlinePlots(S, stimulusSet) creates the figure and every handle in it.
            %
            % Options:
            %   'nTrialsToShow'  Scrolling window width (default 80)
            %   'RefreshEvery'   Trials between aggregate panel updates (default 5)
            %   'Subject'        Shown in the header
            %   'Visible'        'on' (default) or 'off', for tests
            global BpodSystem %#ok<GVMIS> % Figures are registered so Bpod can close them

            p = inputParser;
            p.FunctionName = 'lum.OnlinePlots';
            addParameter(p, 'nTrialsToShow', 80, @(x) isnumeric(x) && isscalar(x) && x > 1);
            addParameter(p, 'RefreshEvery', 5, @(x) isnumeric(x) && isscalar(x) && x >= 1);
            addParameter(p, 'Subject', '', @(x) ischar(x) || isstring(x));
            addParameter(p, 'Visible', 'on');
            parse(p, varargin{:});
            obj.nTrialsToShow = p.Results.nTrialsToShow;
            obj.RefreshEvery = p.Results.RefreshEvery;

            if isfield(stimulusSet, 'States')
                stimulusSet = rmfield(stimulusSet, 'States');
            end
            obj.stimulusSet = stimulusSet;
            obj.theme = lum.gui.theme();
            obj.clock = tic;

            nTrials = S.Session.MaxTrials;
            obj.movingWindow = min(50, max(10, round(nTrials / 20)));
            obj.biasWindow = max(1, round(S.GUI.BiasWindow));
            obj.maxSegments = max([1, stimulusSet.nTimers]);
            blank = NaN(1, nTrials);
            [obj.correctY, obj.incorrectY, obj.noChoiceY, obj.correctness, obj.sideOfTrial, ...
             obj.performanceY, obj.leftPerformanceY, obj.rightPerformanceY, ...
             obj.reactionTimes, obj.leftReactionY, obj.rightReactionY, ...
             obj.medianReactionY, obj.biasLeftY, obj.biasTargetY, obj.choseLeft] = deal(blank);
            obj.planeX = NaN(4, nTrials);
            obj.planeY = NaN(4, nTrials);

            if stimulusSet.Continuous
                obj.rasterOfPattern = stimulusSet.Descriptors.BShare;
            else
                obj.rasterOfPattern = stimulusSet.PatternGroup;
            end
            obj.lightA = stimulusSet.Descriptors.AOn / stimulusSet.Duration;
            obj.lightB = stimulusSet.Descriptors.BOn / stimulusSet.Duration;
            layout = psychometricLayout(stimulusSet);
            obj.psychometricIndex = layout.Index;
            obj.psychometricTrials = zeros(1, numel(layout.X));
            obj.psychometricLeft = zeros(1, numel(layout.X));

            t = obj.theme;
            obj.Figure = figure('Name', 'LuminoseFM - online', 'NumberTitle', 'off', ...
                                'MenuBar', 'none', 'ToolBar', 'none', 'Color', t.Background, ...
                                'Position', [80 60 1320 820], 'Visible', p.Results.Visible);
            if ~isempty(BpodSystem) && isobject(BpodSystem)
                BpodSystem.ProtocolFigures.LuminoseOnlinePlots = obj.Figure;
            end

            obj.buildHeader(S, char(p.Results.Subject));
            body = uipanel(obj.Figure, 'Units', 'normalized', 'Position', [0 0 1 0.93], ...
                           'BorderType', 'none', 'BackgroundColor', t.Background);
            % Twelve columns, so the top row keeps its one-to-three split and the two
            % rows below hold three panels of equal width.
            tiles = tiledlayout(body, 3, 12, 'TileSpacing', 'compact', 'Padding', 'compact');

            % Top left is what the animal is getting now and next, with the choices
            % beside it; how the session is going below; side and timing at the bottom.
            x = 1:nTrials;
            obj.buildUpcomingPanel(nexttile(tiles, 1, [1 3]));
            obj.buildOutcomePanel(nexttile(tiles, 4, [1 9]), x, S);
            obj.buildPerformancePanel(nexttile(tiles, 13, [1 4]), x);
            obj.buildPsychometricPanel(nexttile(tiles, 17, [1 4]), layout);
            obj.buildEvidencePanel(nexttile(tiles, 21, [1 4]));
            obj.buildBarPanel(nexttile(tiles, 25, [1 4]));
            obj.buildBiasPanel(nexttile(tiles, 29, [1 4]), x);
            obj.buildReactionTimePanel(nexttile(tiles, 33, [1 4]), x);
            drawnow;
        end

        function update(obj, trialNumber, spec, result, nextSpec, queue, rewardAmount)
            % update(n, spec, result, nextSpec, queue, rewardAmount) folds trial n in.
            %
            % nextSpec is the trial now running (empty after the last one) and queue
            % the pattern order, for the now-and-next panel; rewardAmount is the
            % volume this trial's reward was, for the water total. The per-trial
            % panels are refreshed every call, the aggregates every RefreshEvery
            % trials, and there is one drawnow at the end.
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return  % The operator closed the figure; carry on running the session
            end
            obj.recordTrial(trialNumber, spec, result, rewardAmount);

            first = max(1, trialNumber - obj.nTrialsToShow + 1);
            last = max(first + obj.nTrialsToShow - 1, trialNumber);
            xLimits = [first - 0.5, last + 0.5];

            h = obj.handles;
            set(h.correct, 'YData', obj.correctY);
            set(h.incorrect, 'YData', obj.incorrectY);
            set(h.noChoice, 'YData', obj.noChoiceY);
            set(obj.axesOf.outcome, 'XLim', xLimits);

            set(h.leftReaction, 'YData', obj.leftReactionY);
            set(h.rightReaction, 'YData', obj.rightReactionY);
            set(h.medianReaction, 'YData', obj.medianReactionY);
            set(obj.axesOf.reaction, 'XLim', xLimits, ...
                'YLim', [0, niceCeiling(obj.reactionTimes(first:trialNumber), 0.5)]);

            obj.showUpcoming(nextSpec, queue);

            if mod(trialNumber, obj.RefreshEvery) == 0 || trialNumber <= 2
                sessionLimits = [0, max(20, ceil(trialNumber * 1.08))];
                set(h.performance, 'YData', obj.performanceY);
                set(h.leftPerformance, 'YData', obj.leftPerformanceY);
                set(h.rightPerformance, 'YData', obj.rightPerformanceY);
                set(obj.axesOf.performance, 'XLim', sessionLimits);

                set(h.biasLeft, 'YData', obj.biasLeftY);
                set(h.biasTarget, 'YData', obj.biasTargetY);
                set(obj.axesOf.bias, 'XLim', sessionLimits);

                for k = 1:4
                    set(h.plane(k), 'XData', obj.planeX(k, :), 'YData', obj.planeY(k, :));
                end

                fractions = ratio(obj.barCorrect, obj.barTrials);
                set(h.bars, 'YData', fractions);
                for k = 1:2
                    set(h.barCounts(k), 'Position', [k, min(max(fractions(k), 0), 1) + 0.06, 0], ...
                        'String', sprintf('%d', obj.barTrials(k)));
                end

                [pLeft, errors] = binomial(obj.psychometricLeft, obj.psychometricTrials);
                set(h.psychometric, 'YData', pLeft, 'YNegativeDelta', errors, ...
                    'YPositiveDelta', errors);
            end

            set(h.summary, 'String', obj.summaryText(trialNumber));
            drawnow limitrate;
        end

        function showNext(obj, nextSpec, queue)
            % showNext(spec, queue) shows the trial about to run and the next three.
            %
            % For the start of the session, before any trial has ended: update()
            % keeps the panel current after that. Called before the first trial is
            % started, so its drawnow falls outside every trial.
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end
            obj.showUpcoming(nextSpec, queue);
            drawnow limitrate;
        end

        function text = summaryText(obj, trialNumber)
            % summaryText() is the one-line session summary.
            if nargin < 2
                trialNumber = obj.lastTrial;
            end
            elapsed = toc(obj.clock);
            if obj.nChoices == 0
                performance = 'no choices yet';
            else
                performance = sprintf('%.0f%% correct of %d choices', ...
                                      100 * obj.nCorrect / obj.nChoices, obj.nChoices);
            end
            text = sprintf('Trial %d  |  %s  |  %d rewards, %.0f uL  |  %02d:%02d:%02d', ...
                           trialNumber, performance, obj.nRewarded, obj.water, ...
                           floor(elapsed / 3600), floor(mod(elapsed, 3600) / 60), ...
                           floor(mod(elapsed, 60)));
        end

        function close(obj)
            % close() closes the figure, if it is still open.
            if ~isempty(obj.Figure) && isvalid(obj.Figure)
                close(obj.Figure);
            end
        end
    end

    methods (Access = private)
        function recordTrial(obj, n, spec, result, rewardAmount)
            % Fold one trial into the per-trial series and the running aggregates.
            obj.lastTrial = n;
            y = obj.rasterOfPattern(spec.PatternIndex);
            switch result.Outcome
                case lum.Outcome.Correct
                    obj.correctY(n) = y;
                case lum.Outcome.Incorrect
                    obj.incorrectY(n) = y;
                otherwise
                    obj.noChoiceY(n) = y;
            end
            obj.correctness(n) = result.Correct;
            obj.sideOfTrial(n) = spec.CorrectSide;
            obj.biasTargetY(n) = spec.BiasTargetPLeft;

            obj.reactionTimes(n) = result.ReactionTime;
            if result.Choice == 1
                obj.leftReactionY(n) = result.ReactionTime;
            elseif result.Choice == 2
                obj.rightReactionY(n) = result.ReactionTime;
            end
            recent = obj.reactionTimes(max(1, n - 60):n);
            recent = recent(~isnan(recent));
            if ~isempty(recent)
                obj.medianReactionY(n) = median(recent(max(1, end - 19):end));
            end

            if result.Rewarded
                obj.nRewarded = obj.nRewarded + 1;
                obj.water = obj.water + rewardAmount;
            end

            % Moving-window performance, from the window alone.
            first = max(1, n - obj.movingWindow + 1);
            correct = obj.correctness(first:n);
            sides = obj.sideOfTrial(first:n);
            obj.performanceY(n) = meanOfScored(correct);
            obj.leftPerformanceY(n) = meanOfScored(correct(sides == 1));
            obj.rightPerformanceY(n) = meanOfScored(correct(sides == 2));

            if isnan(result.Correct) || isnan(result.Choice)
                % No choice, no information about performance or bias: left out of every
                % aggregate rather than counted as an error. The bias line carries its
                % last value across, so it does not break at every missed trial.
                if obj.nChoices > 0
                    obj.biasLeftY(n) = obj.biasLeftY(n - 1);
                end
                return
            end
            obj.nChoices = obj.nChoices + 1;
            obj.nCorrect = obj.nCorrect + result.Correct;
            side = spec.CorrectSide;
            obj.barTrials(side) = obj.barTrials(side) + 1;
            obj.barCorrect(side) = obj.barCorrect(side) + result.Correct;

            obj.choseLeft(obj.nChoices) = double(result.Choice == 1);
            window = obj.choseLeft(max(1, obj.nChoices - obj.biasWindow + 1):obj.nChoices);
            obj.biasLeftY(n) = mean(window);

            % The light the trial actually delivered: none on a light-off trial. A small
            % fixed jitter per trial keeps repeated patterns from hiding one another,
            % without touching the global random stream that draws sides.
            lit = double(spec.OptoOn);
            series = 2 * (1 - result.Correct) + result.Choice;   % 1..4, see planeX
            obj.planeX(series, n) = lit * obj.lightA(spec.PatternIndex) + jitter(n, 0.6180339887);
            obj.planeY(series, n) = lit * obj.lightB(spec.PatternIndex) + jitter(n, 0.7548776662);

            point = obj.psychometricIndex(spec.PatternIndex);
            if point >= 1
                obj.psychometricTrials(point) = obj.psychometricTrials(point) + 1;
                obj.psychometricLeft(point) = obj.psychometricLeft(point) + (result.Choice == 1);
            end
        end

        function showUpcoming(obj, nextSpec, queue)
            % Redraw the running trial's pattern and the next three in the queue.
            t = obj.theme;
            window = obj.stimulusSet.Duration;
            arrow = char(8594);
            sideNames = {'L', 'R'};
            for s = 1:obj.nSlots
                patchHandle = obj.handles.slotPatches(s);
                label = obj.handles.slotLabels(s);
                if isempty(nextSpec)
                    set(patchHandle, 'Vertices', zeros(4 * obj.maxSegments, 2));
                    set(label, 'String', '');
                    continue
                end
                trial = nextSpec.TrialNumber + s - 1;
                if trial > numel(queue)
                    set(patchHandle, 'Vertices', zeros(4 * obj.maxSegments, 2));
                    set(label, 'String', '');
                    continue
                end
                if s == 1
                    index = nextSpec.PatternIndex;
                    role = sprintf('running #%d', trial);
                    sideText = sideNames{nextSpec.CorrectSide};
                else
                    % Queued trials have not drawn their side yet; say what the
                    % contingency allows.
                    index = queue(trial);
                    role = sprintf('queued #%d', trial);
                    sideText = sideOf(obj.stimulusSet.PatternPLeft(index));
                end
                lightOn = nextSpec.OptoOn;
                group = obj.stimulusSet.PatternGroup(index);
                groupText = 'no group';
                if group >= 1
                    groupText = obj.stimulusSet.GroupLabels{group};
                end
                if ~lightOn
                    groupText = sprintf('%s (light off)', groupText);
                end
                set(label, 'String', sprintf('%s\n%s %s %s', role, groupText, arrow, sideText));

                centre = obj.nSlots - s + 1;
                rows = obj.stimulusSet.SegmentStart(index):obj.stimulusSet.SegmentStart(index + 1) - 1;
                segments = obj.stimulusSet.Segments(rows, 2:4);
                vertices = repmat([0 centre], 4 * obj.maxSegments, 1);
                colours = repmat(t.ChannelA, obj.maxSegments, 1);
                for r = 1:min(size(segments, 1), obj.maxSegments)
                    x0 = segments(r, 2);
                    x1 = min(x0 + segments(r, 3), window);
                    if segments(r, 1) == 1
                        y = centre + [0.05 0.33];
                    else
                        y = centre - [0.33 0.05];
                        colours(r, :) = t.ChannelB;
                    end
                    vertices(4 * r - 3:4 * r, :) = [x0 y(1); x1 y(1); x1 y(2); x0 y(2)];
                end
                set(patchHandle, 'Vertices', vertices, 'FaceVertexCData', colours, ...
                    'FaceAlpha', 0.25 + 0.75 * double(lightOn));
            end
        end

        function buildHeader(obj, S, subject)
            % A strip across the top: logo, what session this is, and the summary.
            t = obj.theme;
            header = uipanel(obj.Figure, 'Units', 'normalized', 'Position', [0 0.93 1 0.07], ...
                             'BorderType', 'none', 'BackgroundColor', t.Background);
            logoImage = lum.gui.logo(48);
            if ~isempty(logoImage)
                logoAxes = axes('Parent', header, 'Units', 'normalized', ...
                                'Position', [0.004 0.06 0.04 0.88], 'Visible', 'off');
                image(logoAxes, logoImage);
                axis(logoAxes, 'image', 'off');
            end
            stage = 'unknown stage';
            if S.Task.TrainingStage >= 1 && S.Task.TrainingStage <= numel(S.Task.TrainingStageNames)
                stage = S.Task.TrainingStageNames{S.Task.TrainingStage};
            end
            if lum.HoldShaping.restartsOnBreak(S)
                breakText = 'a broken hold restarts the stimulus';
            else
                breakText = 'a broken hold ends the trial';
            end
            titleText = sprintf('LuminoseFM  |  %s  |  %s  |  %s, %d group(s)  |  %s', ...
                                orDash(subject), stage, obj.stimulusSet.Family, ...
                                obj.stimulusSet.nGroups, breakText);
            if S.Task.TrainingStage == 1
                titleText = [titleText '  |  habituation: both side ports pay'];
            end
            uicontrol(header, 'Style', 'text', 'Units', 'normalized', ...
                      'Position', [0.05 0.5 0.9 0.42], 'String', titleText, 'FontSize', 12, ...
                      'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
                      'BackgroundColor', t.Background, 'ForegroundColor', t.Ink);
            obj.handles.summary = uicontrol(header, 'Style', 'text', 'Units', 'normalized', ...
                      'Position', [0.05 0.06 0.9 0.4], 'String', 'Waiting for the first trial', ...
                      'FontSize', 10, 'HorizontalAlignment', 'left', ...
                      'BackgroundColor', t.Background, 'ForegroundColor', t.Muted);
        end

        function buildOutcomePanel(obj, ax, x, S)
            t = obj.theme;
            styleAxes(ax, t, 'Outcomes');
            obj.axesOf.outcome = ax;
            obj.handles.correct = line(ax, x, obj.correctY, 'LineStyle', 'none', 'Marker', 'o', ...
                'MarkerSize', 5, 'MarkerFaceColor', t.Correct, 'MarkerEdgeColor', 'none');
            obj.handles.incorrect = line(ax, x, obj.incorrectY, 'LineStyle', 'none', ...
                'Marker', 'o', 'MarkerSize', 5, 'MarkerFaceColor', 'none', ...
                'MarkerEdgeColor', t.Incorrect, 'LineWidth', 1.3);
            obj.handles.noChoice = line(ax, x, obj.noChoiceY, 'LineStyle', 'none', 'Marker', 'x', ...
                'MarkerSize', 5, 'MarkerEdgeColor', t.NoChoice);
            if obj.stimulusSet.Continuous
                set(ax, 'YLim', [-0.05 1.05], 'YTick', [0 0.5 1]);
                ylabel(ax, 'B share of the light');
            else
                K = obj.stimulusSet.nGroups;
                set(ax, 'YLim', [0.5 K + 0.5], 'YTick', 1:K, 'YTickLabel', obj.stimulusSet.GroupLabels, ...
                    'YDir', 'reverse');
            end
            xlabel(ax, 'Trial');
            set(ax, 'XLim', [0.5, obj.nTrialsToShow + 0.5]);
            legend(ax, {'correct', 'incorrect', 'no choice'}, 'Location', 'northeastoutside', ...
                   'Box', 'off', 'TextColor', t.Muted);
            if S.Task.TrainingStage == 1
                ax.Title.String = 'Outcomes  (habituation: both side ports pay)';
            end
        end

        function buildUpcomingPanel(obj, ax)
            t = obj.theme;
            styleAxes(ax, t, 'Now and next');
            obj.axesOf.upcoming = ax;
            window = obj.stimulusSet.Duration;
            faces = reshape(1:4 * obj.maxSegments, 4, obj.maxSegments)';
            obj.handles.slotPatches = gobjects(1, obj.nSlots);
            obj.handles.slotLabels = gobjects(1, obj.nSlots);
            for s = 1:obj.nSlots
                centre = obj.nSlots - s + 1;
                % Faint lanes for A (above) and B (below), so a dark trial still shows
                % its window.
                patch(ax, 'XData', [0 window window 0; 0 window window 0]', ...
                      'YData', [centre + [0.05 0.05 0.33 0.33]; centre - [0.33 0.33 0.05 0.05]]', ...
                      'FaceColor', t.Dark, 'EdgeColor', 'none');
                obj.handles.slotPatches(s) = patch(ax, 'Faces', faces, ...
                    'Vertices', repmat([0 centre], 4 * obj.maxSegments, 1), ...
                    'FaceColor', 'flat', 'FaceVertexCData', repmat(t.ChannelA, obj.maxSegments, 1), ...
                    'EdgeColor', 'none');
                obj.handles.slotLabels(s) = text(ax, -0.04 * window, centre, '', ...
                    'HorizontalAlignment', 'right', 'FontSize', 8, 'Color', t.Ink, ...
                    'Interpreter', 'none');
            end
            set(ax, 'XLim', [-0.9 * window, 1.02 * window], 'YLim', [0.45, obj.nSlots + 0.55], ...
                'YTick', [], 'XTick', [0 window], 'XGrid', 'off', 'YGrid', 'off');
            xlabel(ax, 'Stimulus window (s)');
            text(ax, 1.02 * window, obj.nSlots + 0.42, 'A', 'Color', t.ChannelA, ...
                 'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontSize', 8);
            text(ax, 1.02 * window, obj.nSlots + 0.62, 'B below', 'Color', t.ChannelB, ...
                 'FontWeight', 'bold', 'HorizontalAlignment', 'right', 'FontSize', 8);
        end

        function buildPerformancePanel(obj, ax, x)
            t = obj.theme;
            styleAxes(ax, t, sprintf('Performance, %d-trial window', obj.movingWindow));
            obj.axesOf.performance = ax;
            line(ax, [0 numel(x)], [0.5 0.5], 'Color', t.Faint, 'LineStyle', '--', 'LineWidth', 1);
            obj.handles.leftPerformance = line(ax, x, obj.leftPerformanceY, 'Color', t.Left, ...
                                               'LineWidth', 1);
            obj.handles.rightPerformance = line(ax, x, obj.rightPerformanceY, 'Color', t.Right, ...
                                                'LineWidth', 1);
            obj.handles.performance = line(ax, x, obj.performanceY, 'Color', t.Ink, 'LineWidth', 2);
            set(ax, 'YLim', [0 1], 'XLim', [0 20]);
            xlabel(ax, 'Trial');
            ylabel(ax, 'Fraction correct');
            legend(ax, [obj.handles.performance, obj.handles.leftPerformance, ...
                        obj.handles.rightPerformance], {'all', 'left-rewarded', 'right-rewarded'}, ...
                   'Location', 'southeast', 'Box', 'off', 'TextColor', t.Muted);
        end

        function buildPsychometricPanel(obj, ax, layout)
            t = obj.theme;
            styleAxes(ax, t, layout.Title);
            obj.axesOf.psychometric = ax;
            span = [min(layout.X), max(layout.X)];
            pad = max(0.5, 0.08 * diff(span));
            line(ax, span + [-pad pad], [0.5 0.5], 'Color', t.Faint, 'LineStyle', '--');
            line(ax, layout.X, layout.Target, 'Color', t.Muted, 'LineStyle', ':', ...
                 'Marker', 'd', 'MarkerSize', 5, 'MarkerEdgeColor', t.Muted, 'LineWidth', 1);
            nPoints = numel(layout.X);
            obj.handles.psychometric = errorbar(ax, layout.X, NaN(1, nPoints), ...
                zeros(1, nPoints), zeros(1, nPoints), 'Color', t.Accent, 'LineWidth', 1.5, ...
                'Marker', 'o', 'MarkerSize', 6, 'MarkerFaceColor', t.Accent, 'CapSize', 0);
            set(ax, 'YLim', [0 1], 'XLim', span + [-pad pad]);
            if ~isempty(layout.TickLabels)
                set(ax, 'XTick', layout.X, 'XTickLabel', layout.TickLabels);
            end
            xlabel(ax, layout.XLabel);
            ylabel(ax, 'P(choose left)');
        end

        function buildEvidencePanel(obj, ax)
            % Choices in the plane of the evidence on A against the evidence on B.
            t = obj.theme;
            styleAxes(ax, t, sprintf('Evidence, u_A vs u_B, by choice  (%s left, %s right)', ...
                                     char(9664), char(9654)));
            obj.axesOf.evidence = ax;
            line(ax, [0 1], [0 1], 'Color', t.Faint, 'LineStyle', '--', 'LineWidth', 1);
            nTrials = size(obj.planeX, 2);
            blank = NaN(1, nTrials);
            % Rows of planeX: correct-left, correct-right, incorrect-left, incorrect-right.
            markers = {'<', '>', '<', '>'};
            obj.handles.plane = gobjects(1, 4);
            for k = 1:4
                if k <= 2
                    style = {'MarkerFaceColor', t.Correct, 'MarkerEdgeColor', 'none'};
                else
                    style = {'MarkerFaceColor', 'none', 'MarkerEdgeColor', t.Incorrect, 'LineWidth', 1};
                end
                obj.handles.plane(k) = line(ax, blank, blank, 'LineStyle', 'none', ...
                    'Marker', markers{k}, 'MarkerSize', 5, style{:});
            end
            set(ax, 'XLim', [-0.06 1.06], 'YLim', [-0.06 1.06], 'XTick', 0:0.5:1, 'YTick', 0:0.5:1);
            xlabel(ax, 'u_A, evidence on A (fraction of the window lit)');
            ylabel(ax, 'u_B, evidence on B');
            legend(ax, obj.handles.plane([1 3]), {'correct', 'incorrect'}, ...
                   'Location', 'northeast', 'Box', 'off', 'TextColor', t.Muted, 'FontSize', 8);
        end

        function buildBarPanel(obj, ax)
            t = obj.theme;
            styleAxes(ax, t, 'By side');
            obj.axesOf.bars = ax;
            obj.handles.bars = bar(ax, 1:2, NaN(1, 2), 0.55, 'FaceColor', 'flat', ...
                                   'EdgeColor', 'none');
            obj.handles.bars.CData = [t.Left; t.Right];
            line(ax, [0.4 2.6], [0.5 0.5], 'Color', t.Faint, 'LineStyle', '--');
            obj.handles.barCounts = gobjects(1, 2);
            for k = 1:2
                obj.handles.barCounts(k) = text(ax, k, 0.06, '0', 'HorizontalAlignment', 'center', ...
                                                'FontSize', 8, 'Color', t.Muted);
            end
            set(ax, 'YLim', [0 1.12], 'XLim', [0.4 2.6], 'XTick', 1:2, ...
                'XTickLabel', {'left-rewarded', 'right-rewarded'}, 'XGrid', 'off');
            ylabel(ax, 'Fraction correct');
        end

        function buildBiasPanel(obj, ax, x)
            t = obj.theme;
            styleAxes(ax, t, sprintf('Side bias, last %d choices', obj.biasWindow));
            obj.axesOf.bias = ax;
            line(ax, [0 numel(x)], [0.5 0.5], 'Color', t.Faint, 'LineStyle', '--', 'LineWidth', 1);
            obj.handles.biasTarget = line(ax, x, obj.biasTargetY, 'Color', t.Muted, ...
                                          'LineStyle', ':', 'LineWidth', 1.2);
            obj.handles.biasLeft = line(ax, x, obj.biasLeftY, 'Color', t.Left, 'LineWidth', 2);
            set(ax, 'YLim', [0 1], 'XLim', [0 20]);
            xlabel(ax, 'Trial');
            ylabel(ax, 'P(left)');
            legend(ax, [obj.handles.biasLeft, obj.handles.biasTarget], ...
                   {'chose left', 'bias correction target'}, 'Location', 'southeast', ...
                   'Box', 'off', 'TextColor', t.Muted);
        end

        function buildReactionTimePanel(obj, ax, x)
            t = obj.theme;
            styleAxes(ax, t, 'Reaction time, from leaving the centre port');
            obj.axesOf.reaction = ax;
            obj.handles.leftReaction = line(ax, x, obj.leftReactionY, 'LineStyle', 'none', ...
                'Marker', '.', 'MarkerSize', 10, 'Color', t.Left);
            obj.handles.rightReaction = line(ax, x, obj.rightReactionY, 'LineStyle', 'none', ...
                'Marker', '.', 'MarkerSize', 10, 'Color', t.Right);
            obj.handles.medianReaction = line(ax, x, obj.medianReactionY, 'Color', t.Ink, ...
                                              'LineWidth', 1.2);
            set(ax, 'YLim', [0 0.5], 'XLim', [0.5, obj.nTrialsToShow + 0.5]);
            xlabel(ax, 'Trial');
            ylabel(ax, 'Seconds');
            legend(ax, [obj.handles.leftReaction, obj.handles.rightReaction, ...
                        obj.handles.medianReaction], {'chose left', 'chose right', 'median'}, ...
                   'Location', 'north', 'Orientation', 'horizontal', 'Box', 'off', ...
                   'TextColor', t.Muted);
        end
    end
end


function layout = psychometricLayout(stimulusSet)
% Where each pattern's choices land on the psychometric panel, and how it is labelled.
layout = struct();
if stimulusSet.Continuous
    edges = linspace(0, 1, 9);
    layout.X = edges(1:end-1) + diff(edges) / 2;
    layout.Index = discretize(stimulusSet.Descriptors.BShare, edges);
    layout.Target = NaN(1, numel(layout.X));
    for b = 1:numel(layout.X)
        members = layout.Index == b;
        if any(members)
            layout.Target(b) = mean(stimulusSet.PatternPLeft(members));
        end
    end
    layout.TickLabels = {};
    layout.XLabel = 'B share of the light';
    layout.Title = 'Psychometric, continuous patterns';
    return
end

nGroups = stimulusSet.nGroups;
layout.Target = stimulusSet.GroupPLeft;
layout.Index = stimulusSet.PatternGroup;
swept = nGroups > 2 && ~isempty(stimulusSet.SweepName) && numel(unique(stimulusSet.SweepValues)) == nGroups;
if swept
    % Plotted along the swept parameter, in its order, with each group mapped to
    % its place so the line joins neighbours rather than groups in index order.
    [layout.X, order] = sort(stimulusSet.SweepValues);
    position = zeros(1, nGroups);
    position(order) = 1:nGroups;
    layout.Index = position(stimulusSet.PatternGroup);
    layout.Target = stimulusSet.GroupPLeft(order);
    layout.TickLabels = {};
    layout.XLabel = stimulusSet.SweepName;
else
    layout.X = 1:nGroups;
    layout.TickLabels = stimulusSet.GroupLabels;
    layout.XLabel = 'Stimulus group';
end
layout.Title = sprintf('Psychometric, %d group(s)', nGroups);
end


function styleAxes(ax, t, titleText)
% The look every panel shares.
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


function value = ratio(numerator, denominator)
% Fraction, with NaN where nothing has been counted yet, so empty bars stay blank.
value = numerator ./ denominator;
value(denominator == 0) = NaN;
end


function [p, standardError] = binomial(successes, trials)
% Proportion and its binomial standard error; NaN and 0 where nothing is counted.
p = ratio(successes, trials);
standardError = sqrt(p .* (1 - p) ./ max(trials, 1));
standardError(trials == 0) = 0;
end


function value = meanOfScored(values)
% Mean of the non-NaN values; NaN when there are none.
values = values(~isnan(values));
if isempty(values)
    value = NaN;
else
    value = mean(values);
end
end


function offset = jitter(n, step)
% A small offset for trial n, from a low-discrepancy sequence: deterministic, spread
% evenly, and independent of rand, which the trial policy draws sides from.
offset = 0.025 * (2 * mod(n * step, 1) - 1);
end


function upper = niceCeiling(values, minimum)
% An upper axis limit a little above the largest value on screen.
values = values(~isnan(values));
if isempty(values)
    upper = minimum;
    return
end
upper = max(minimum, 1.15 * max(values));
end


function text = sideOf(pLeft)
% Which side a queued pattern will pay, as far as its contingency says.
if pLeft >= 1
    text = 'L';
elseif pLeft <= 0
    text = 'R';
else
    text = 'L or R';
end
end


function text = orDash(text)
% A placeholder for an empty name.
if isempty(text)
    text = '-';
end
end
