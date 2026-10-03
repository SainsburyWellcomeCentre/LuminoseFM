function [files, problems] = summaryPlots(Data, dataFile, varargin)
% lum.report.summaryPlots writes a behaviour session's summary plots, one image per plot.
%
%   [files, problems] = lum.report.summaryPlots(SessionData, dataFile)
%
% For the experimenter and colleagues going through an animal's sessions: every panel of the
% online figure (lum.OnlinePlots) drawn over the whole session rather than its last 80
% trials, each as its own image, and a few more that the live figure has no room for. Written
% into 'Session Plots' beside 'Session Data' (lum.report.folder), named
%
%   NN_<Plot>_PP_<subject>_<YYYYMMDD_HHMMSS>.png
%
% so that sorting by name puts one kind of plot from every session together, in date order:
% NN numbers the kind, PP the page (01 unless the plot runs over several pages; the outcome
% raster takes up to 400 trials a page). The plots:
%
%   01_Outcomes         Each trial's choice by stimulus group, as the online figure scores it
%                       (rewarded in habituation, correct otherwise), above how each trial
%                       ended
%   02_Performance      Moving-window score, all and by rewarded side, and the running score
%   03_Psychometric     P(chose left) by group or evidence, whole session and each half,
%                       against the contingency
%   04_Evidence         Every choice at its trial's u_A and u_B, with the contingency's boundary
%   05_BySide           Score by rewarded side, and the side chosen
%   06_SideBias         P(chose left) over the last BiasWindow choices, with bias
%                       correction's target, and the side each trial paid
%   07_ReactionTime     Per trial by side with a running median, and their distribution
%   08_CentreHold       Time in the centre port on each trial's last hold against the hold
%                       asked for (and where automatic shaping stepped it back), and the
%                       distribution on completed holds
%   09_HoldAttempts     How the hold went: held on the first attempt, held after early
%                       withdrawals, not completed, or no hold started, in bins of trials;
%                       hold attempts per trial; and the first-attempt rate by the hold asked
%                       for
%   10_Engagement       Trials by outcome in 5-minute bins, trial length, and water
%                       accumulated over the session
%   11_PortActivity     Pokes per minute at each port over the session
%   12_SessionTiming    MATLAB's prepare, send, plot and save time per trial, and its memory
%   13_PulseLocking     Early withdrawals against the light's carrier pulses: when they came
%                       in the light, folded on the carrier's period, and the locking at each
%                       frequency against the withdrawal times' shape alone
%                       (lum.report.pulseLocking; a control in a session without light)
%
% A hold counts as completed however many early withdrawals came before it
% (lum.holdMeasures): only 09_HoldAttempts tells a first attempt from a later one. The
% other plots show whether the hold was completed, and a trial with no completed hold as a
% trial without a choice.
%
% Colours, type, gridlines and keys come from lum.gui.theme, lum.gui.styleAxes and
% lum.gui.panelLegend, as in the online figure.
%
% Written after the session's data are saved, so nothing in the data file depends on them,
% and from the data alone (lum.report.sessionTrials), so an old file draws the same way
% (lum.report.fromFile). One invisible figure is cleared and printed for each plot.
%
% Arguments:
%   Data      The session's data (BpodSystem.Data, or a saved file's SessionData)
%   dataFile  The session's data file; names the images and places the folder
%
% Options:
%   'Folder'      Where to write (default lum.report.folder(dataFile, 'Plots'))
%   'Resolution'  Dots per inch of the images (default 150)
%   'Plots'       The numbers (NN) of the plots to draw (default: all), e.g. 13 to add a new
%                 plot to sessions drawn before it existed
%
% Returns:
%   files     Full paths of the images written
%   problems  One message per plot that could not be drawn; the others are still written.
%             Never throws for a single plot.
%
% See also lum.report.write, lum.report.sessionTrials, lum.OnlinePlots, lum.holdMeasures,
% lum.report.pulseLocking

p = inputParser;
p.FunctionName = 'lum.report.summaryPlots';
addParameter(p, 'Folder', '');
addParameter(p, 'Resolution', 150, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Plots', [], @isnumeric);
parse(p, varargin{:});
folder = char(p.Results.Folder);
if isempty(folder)
    folder = lum.report.folder(dataFile, 'Plots');
end

files = {};
problems = {};
T = lum.report.sessionTrials(Data);
if T.n < 1
    problems{end+1} = 'no trials to plot';
    return
end
if ~isfolder(folder)
    mkdir(folder);
end
t = lum.gui.theme();
tag = lum.report.fileTag(dataFile, T.subject);
heading = lum.report.heading(Data, T);

% Name, width, height (pixels), and what draws it. The outcome raster pages.
nPages = max(1, ceil(T.n / 400));
pageSize = ceil(T.n / nPages);
plots = cell(0, 5);
for page = 1:nPages
    trialRange = [(page - 1) * pageSize + 1, min(T.n, page * pageSize)];
    plots(end+1, :) = {1, 'Outcomes', page, [1400 600], @(fig) drawOutcomes(fig, T, t, trialRange)}; %#ok<AGROW>
end
plots = [plots; ...
    {2, 'Performance', 1, [1400 520], @(fig) drawPerformance(fig, T, t)}; ...
    {3, 'Psychometric', 1, [1000 580], @(fig) drawPsychometric(fig, T, t)}; ...
    {4, 'Evidence', 1, [820 760], @(fig) drawEvidence(fig, T, t)}; ...
    {5, 'BySide', 1, [1000 480], @(fig) drawBySide(fig, T, t)}; ...
    {6, 'SideBias', 1, [1400 520], @(fig) drawSideBias(fig, T, t)}; ...
    {7, 'ReactionTime', 1, [1400 560], @(fig) drawReactionTime(fig, T, t)}; ...
    {8, 'CentreHold', 1, [1400 560], @(fig) drawCentreHold(fig, T, t)}; ...
    {9, 'HoldAttempts', 1, [1400 760], @(fig) drawHoldAttempts(fig, T, t)}; ...
    {10, 'Engagement', 1, [1400 800], @(fig) drawEngagement(fig, T, t)}; ...
    {11, 'PortActivity', 1, [1400 520], @(fig) drawPortActivity(fig, T, t)}; ...
    {12, 'SessionTiming', 1, [1400 640], @(fig) drawSessionTiming(fig, Data, T, t)}; ...
    {13, 'PulseLocking', 1, [1400 860], @(fig) drawPulseLocking(fig, T, t)}];

if ~isempty(p.Results.Plots)
    plots = plots(ismember([plots{:, 1}], p.Results.Plots), :);
end

% One invisible figure, cleared between plots: making a figure costs more than drawing in it.
fig = figure('Visible', 'off', 'Color', t.PlotBackground, 'MenuBar', 'none', 'ToolBar', 'none', ...
             'NumberTitle', 'off', 'HandleVisibility', 'off', 'InvertHardcopy', 'off', ...
             'PaperUnits', 'inches', 'PaperPositionMode', 'manual');
cleanup = onCleanup(@() delete(fig));
for i = 1:size(plots, 1)
    [number, name, page, pixels, draw] = plots{i, :};
    file = fullfile(folder, sprintf('%02d_%s_%02d_%s.png', number, name, page, tag));
    try
        clf(fig);
        % The printed size is set on the paper: an invisible figure can apply a new Position
        % late, and print would then lay the plot out at the one before.
        fig.Position = [20 20 pixels];
        fig.PaperSize = pixels / 96;
        fig.PaperPosition = [0 0 pixels / 96];
        draw(fig);
        pageText = '';
        if nPages > 1 && number == 1
            pageText = sprintf('  |  trials %d-%d', (page - 1) * pageSize + 1, ...
                               min(T.n, page * pageSize));
        end
        layout = findobj(fig, 'Type', 'tiledlayout');
        layout(1).Title.String = headingLines([heading pageText], pixels(1), t);
        layout(1).Title.FontName = t.Font.Name;
        layout(1).Title.FontSize = t.Font.Title;
        layout(1).Title.FontWeight = 'normal';
        layout(1).Title.Color = t.Axis;
        layout(1).Title.Interpreter = 'none';
        % print, not exportgraphics: these figures hold only axes, and print is quicker.
        print(fig, file, '-dpng', sprintf('-r%d', round(p.Results.Resolution)));
        files{end+1} = file; %#ok<AGROW>
    catch plotError
        problems{end+1} = sprintf('%s: %s', name, plotError.message); %#ok<AGROW>
    end
end
clear cleanup
end


%% The plots -------------------------------------------------------------------

function drawOutcomes(fig, T, t, trialRange)
% Each trial's choice by group (or evidence), and how each trial ended.
layout = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
trials = trialRange(1):trialRange(2);
xLimits = [trialRange(1) - 0.5, trialRange(1) + max(trialRange(2) - trialRange(1), 20) + 0.5];
ax = nexttile(layout, [2 1]);
lum.gui.styleAxes(ax, outcomeTitle(T), t);
stimulusSet = T.stimulusSet;
byEvidence = lum.OnlinePlots.rasterByEvidenceOf(stimulusSet);
if byEvidence
    y = stimulusSet.Evidence(T.pattern(trials));
else
    y = stimulusSet.PatternGroup(T.pattern(trials));
end
chose = ~isnan(T.choice(trials));
scoredGood = T.scored(trials) == 1;
handles = [ ...
    dots(ax, trials(chose & scoredGood), y(chose & scoredGood), 'Marker', 'o', ...
         'MarkerSize', 6, 'MarkerFaceColor', t.Correct, 'MarkerEdgeColor', 'none'), ...
    dots(ax, trials(chose & ~scoredGood), y(chose & ~scoredGood), 'Marker', 'o', ...
         'MarkerSize', 6, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', t.Incorrect, 'LineWidth', 1.6), ...
    dots(ax, trials(~chose), y(~chose), 'Marker', 'x', 'MarkerSize', 6, 'Color', t.NoChoice, ...
         'LineWidth', 1.2)];
if byEvidence
    ylabel(ax, stimulusSet.EvidenceName);
else
    K = stimulusSet.nGroups;
    set(ax, 'YLim', [0.5 K + 0.5], 'YTick', 1:K, 'YTickLabel', stimulusSet.GroupLabels, 'YDir', 'reverse');
end
set(ax, 'XLim', xLimits);
lum.gui.panelLegend(ax, handles, [scoreLabels(T), {'no choice'}], t);

% How each trial ended, a row per outcome: a trial whose hold was not completed is one row,
% whether the hold window ran out or an early withdrawal ended it ('End trial').
ax = nexttile(layout);
lum.gui.styleAxes(ax, 'How each trial ended', t);
[names, colours] = outcomeRows(T, t);
row = outcomeRow(T, trials);
for r = 1:numel(names)
    members = trials(row == r);
    dots(ax, members, r * ones(size(members)), 'Marker', '|', 'MarkerSize', 9, ...
         'Color', colours(r, :), 'LineWidth', 2);
end
set(ax, 'YLim', [0.5 numel(names) + 0.5], 'YTick', 1:numel(names), 'YTickLabel', names, ...
     'YDir', 'reverse', 'XLim', xLimits);
xlabel(ax, 'Trial');
end


function drawPerformance(fig, T, t)
% The online figure's performance panel over every trial, and the running score.
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
window = movingWindow(T);
lum.gui.styleAxes(ax, sprintf('Performance, %d-trial window', window), t);
x = 1:T.n;
chanceLine(ax, [0 T.n + 1], t);
left = line(ax, x, moving(T.scored, window, T.correctSide == 1), 'Color', t.Left, 'LineWidth', 1.6);
right = line(ax, x, moving(T.scored, window, T.correctSide == 2), 'Color', t.Right, 'LineWidth', 1.6);
whole = line(ax, x, moving(T.scored, window, true(1, T.n)), 'Color', t.Series, 'LineWidth', 2.4);
running = line(ax, x, cumulativeMean(T.scored), 'Color', t.SeriesSoft, 'LineStyle', '--', 'LineWidth', 1.6);
set(ax, 'YLim', [0 1], 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, scoreAxisLabel(T));
lum.gui.panelLegend(ax, [whole, left, right, running], ...
                    {'all', 'left-rewarded', 'right-rewarded', 'session so far'}, t);
end


function drawPsychometric(fig, T, t)
% P(chose left) along the family's evidence or by group, whole session and each half.
stimulusSet = T.stimulusSet;
layout = lum.OnlinePlots.psychometricLayoutOf(stimulusSet);
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
lum.gui.styleAxes(ax, layout.Title, t);
span = [min(layout.X), max(layout.X)];
pad = 0.5;
if isempty(layout.TickLabels) && diff(span) > 0
    pad = 0.08 * diff(span);
end
chanceLine(ax, span + [-pad pad], t);
target = line(ax, layout.X, layout.Target, 'Color', t.SeriesSoft, 'LineStyle', ':', 'Marker', 'd', ...
              'MarkerSize', 7, 'LineWidth', 1.4);
chose = ~isnan(T.choice);
point = zeros(1, T.n);
point(chose) = layout.Index(T.pattern(chose));
halves = {1:floor(T.n / 2), floor(T.n / 2) + 1:T.n};
styles = {'--', '-.'};
halfHandles = gobjects(1, 2);
for h = 1:2
    [pLeft, ~] = psychometric(point(halves{h}), T.choice(halves{h}), numel(layout.X));
    halfHandles(h) = line(ax, layout.X, pLeft, 'Color', t.SeriesSoft, 'LineWidth', 1.2, ...
                          'LineStyle', styles{h}, 'Marker', '.', 'MarkerSize', 16);
end
[pLeft, errors, counts] = psychometric(point, T.choice, numel(layout.X));
whole = errorbar(ax, layout.X, pLeft, errors, 'Color', t.Series, 'LineWidth', 2, 'Marker', 'o', ...
                 'MarkerSize', 8, 'MarkerFaceColor', t.Series, 'CapSize', 0);
for b = 1:numel(layout.X)
    if counts(b) > 0
        note(ax, layout.X(b), 0.04, sprintf('n=%d', counts(b)), t, 'HorizontalAlignment', 'center');
    end
end
set(ax, 'YLim', [0 1], 'XLim', span + [-pad pad]);
if ~isempty(layout.TickLabels)
    set(ax, 'XTick', layout.X, 'XTickLabel', layout.TickLabels);
end
xlabel(ax, layout.XLabel);
ylabel(ax, 'P(choose left)');
lum.gui.panelLegend(ax, [whole, halfHandles, target], ...
                    {'chose left, whole session', 'first half', 'second half', 'contingency'}, t);
end


function drawEvidence(fig, T, t)
% Every choice at the light its trial delivered on A and B.
stimulusSet = T.stimulusSet;
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
lum.gui.styleAxes(ax, sprintf('Evidence, u_A vs u_B, by choice (%s left, %s right)', char(9664), char(9654)), t);
edge = struct('Kind', 'diagonal', 'Value', NaN);
if isfield(stimulusSet, 'Boundary')
    edge = stimulusSet.Boundary;
end
boundary = {'Color', t.SeriesSoft, 'LineStyle', '--', 'LineWidth', 1};
switch edge.Kind
    case 'diagonal'
        line(ax, [0 1], [0 1], boundary{:});
    case 'vertical'
        line(ax, [1 1] * edge.Value, [0 1], boundary{:});
    case 'horizontal'
        line(ax, [0 1], [1 1] * edge.Value, boundary{:});
    case 'line'
        x = [-0.1 1.1];
        line(ax, x, edge.Slope * x + edge.Intercept, boundary{:});
end
set(ax, 'XLim', [-0.06 1.06], 'YLim', [-0.06 1.06], 'XTick', 0:0.25:1, 'YTick', 0:0.25:1, 'XGrid', 'on');
axis(ax, 'square');
xlabel(ax, 'u_A, evidence on A (fraction of the window lit)');
ylabel(ax, 'u_B, evidence on B');
chose = find(~isnan(T.choice));
lit = double(T.optoOn(chose) == 1);
if ~any(lit)
    % Every choice would sit at the origin: say why rather than show a blob.
    note(ax, 0.5, 0.5, 'No light in this session', t, 'HorizontalAlignment', 'center', ...
         'FontSize', t.Font.Label);
    return
end
lightA = reshape(stimulusSet.Descriptors.AOn, 1, []) / stimulusSet.Duration;
lightB = reshape(stimulusSet.Descriptors.BOn, 1, []) / stimulusSet.Duration;
x = lit .* lightA(T.pattern(chose)) + jitter(chose, 0.6180339887);
y = lit .* lightB(T.pattern(chose)) + jitter(chose, 0.7548776662);
good = T.scored(chose) == 1;
markers = {'<', '>'};
handles = gobjects(1, 2);
for side = 1:2
    mine = T.choice(chose) == side;
    handles(1) = dots(ax, x(mine & good), y(mine & good), 'Marker', markers{side}, ...
                      'MarkerSize', 7, 'MarkerFaceColor', t.Correct, 'MarkerEdgeColor', 'none');
    handles(2) = dots(ax, x(mine & ~good), y(mine & ~good), 'Marker', markers{side}, ...
                      'MarkerSize', 7, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', t.Incorrect, ...
                      'LineWidth', 1.4);
end
lum.gui.panelLegend(ax, handles, scoreLabels(T), t);
end


function drawBySide(fig, T, t)
% Score by the side a trial paid, and the side chosen.
layout = tiledlayout(fig, 1, 2, 'TileSpacing', 'loose', 'Padding', 'compact');
ax = nexttile(layout);
lum.gui.styleAxes(ax, 'Score by rewarded side', t);
fractions = NaN(1, 2);
counts = zeros(1, 2);
for side = 1:2
    scored = T.scored(T.correctSide == side & ~isnan(T.scored));
    counts(side) = numel(scored);
    if counts(side) > 0
        fractions(side) = mean(scored);
    end
end
chanceLine(ax, [0.4 2.6], t);
bars = bar(ax, 1:2, fractions, 0.5, 'FaceColor', 'flat', 'EdgeColor', 'none');
bars.CData = [t.Left; t.Right];
for side = 1:2
    if counts(side) > 0
        note(ax, side, fractions(side) + 0.02, sprintf('%.0f%% of %d', 100 * fractions(side), counts(side)), ...
             t, 'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom');
    end
end
set(ax, 'YLim', [0 1.1], 'YTick', 0:0.25:1, 'XLim', [0.4 2.6], 'XTick', 1:2, ...
     'XTickLabel', {'left-rewarded', 'right-rewarded'});
ylabel(ax, scoreAxisLabel(T));

ax = nexttile(layout);
noChoice = sum(isnan(T.choice));
lum.gui.styleAxes(ax, sprintf('Side chosen (%d trials without a choice)', noChoice), t);
chosen = [sum(T.choice == 1), sum(T.choice == 2)];
bars = bar(ax, 1:2, chosen, 0.5, 'FaceColor', 'flat', 'EdgeColor', 'none');
bars.CData = [t.Left; t.Right];
top = max(1, max(chosen)) * 1.15;
for side = 1:2
    note(ax, side, chosen(side) + 0.02 * top, sprintf('%d (%.0f%%)', chosen(side), ...
         100 * chosen(side) / max(1, sum(chosen))), t, 'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'bottom');
end
set(ax, 'XLim', [0.4 2.6], 'XTick', 1:2, 'XTickLabel', {'left', 'right'}, 'YLim', [0, top]);
ylabel(ax, 'Choices');
end


function drawSideBias(fig, T, t)
% P(chose left) over the last BiasWindow choices, the correction's target, each trial's side.
window = max(1, round(T.S.GUI.BiasWindow));
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
lum.gui.styleAxes(ax, sprintf('Side bias, last %d choices', window), t);
chanceLine(ax, [0 T.n + 1], t);
chose = find(~isnan(T.choice));
leftChoice = double(T.choice(chose) == 1);
biasLeft = NaN(1, T.n);
for i = 1:numel(chose)
    biasLeft(chose(i)) = mean(leftChoice(max(1, i - window + 1):i));
end
biasLeft = fillForward(biasLeft);
target = line(ax, 1:T.n, T.biasTarget, 'Color', t.SeriesSoft, 'LineStyle', ':', 'LineWidth', 1.6);
leftLine = line(ax, 1:T.n, biasLeft, 'Color', t.Left, 'LineWidth', 2.4);
% The side each trial paid, as ticks along the top and bottom.
leftTrials = find(T.correctSide == 1);
rightTrials = find(T.correctSide == 2);
paidLeft = dots(ax, leftTrials, 1.03 * ones(size(leftTrials)), 'Marker', '|', 'MarkerSize', 7, ...
                'Color', t.Left);
paidRight = dots(ax, rightTrials, -0.03 * ones(size(rightTrials)), 'Marker', '|', 'MarkerSize', 7, ...
                 'Color', t.Right);
set(ax, 'YLim', [-0.06 1.06], 'YTick', 0:0.25:1, 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'P(chose left)');
lum.gui.panelLegend(ax, [leftLine, target, paidLeft, paidRight], ...
                    {'chose left', 'bias correction target', 'trial paid left', 'trial paid right'}, t);
end


function drawReactionTime(fig, T, t)
% Reaction time per trial on a log axis, by side, and its distribution.
layout = tiledlayout(fig, 1, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(layout, [1 3]);
lum.gui.styleAxes(ax, 'Reaction time, from leaving the centre port', t);
rt = T.reactionTime;
leftDots = dots(ax, find(T.choice == 1), rt(T.choice == 1), 'Marker', '.', 'MarkerSize', 14, ...
                'Color', t.Left);
rightDots = dots(ax, find(T.choice == 2), rt(T.choice == 2), 'Marker', '.', 'MarkerSize', 14, ...
                 'Color', t.Right);
medianLine = line(ax, 1:T.n, runningMedian(rt, 20), 'Color', t.Series, 'LineWidth', 2);
limits = logLimits(rt);
ticks = logTicks(limits);
set(ax, 'YScale', 'log', 'YLim', limits, 'YTick', ticks, 'YTickLabel', compose('%g', ticks), ...
     'YMinorTick', 'off', 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'Reaction time (s, log)');
lum.gui.panelLegend(ax, [leftDots, rightDots, medianLine], {'chose left', 'chose right', 'median of last 20'}, t);

% The distribution of every choice's reaction time, on the same log axis (the sides are told
% apart on the left): bins a fixed fraction of a decade wide, from the data's own range,
% fewer for fewer choices.
ax = nexttile(layout);
lum.gui.styleAxes(ax, 'Distribution', t);
values = rt(~isnan(T.choice) & rt > 0);
edges = logEdges(rt, limits, min(24, max(8, round(2 * sqrt(numel(values))))));
if isempty(values)
    values = NaN;
end
histogram(ax, values, edges, 'Orientation', 'horizontal', 'FaceColor', t.SeriesSoft, ...
          'FaceAlpha', 1, 'EdgeColor', t.Panel, 'LineWidth', 0.5);
typical = median(rt, 'omitnan');
set(ax, 'YScale', 'log', 'YLim', limits, 'YTick', ticks, 'YTickLabel', compose('%g', ticks), ...
     'YMinorTick', 'off', 'XGrid', 'on');
if ~isnan(typical)
    referenceLine(ax, typical, sprintf('median %.2f s', typical), t);
end
xlabel(ax, 'Choices');
end


function drawCentreHold(fig, T, t)
% Time in the centre port on each trial's last hold against the hold asked for, and its
% distribution on completed holds.
layout = tiledlayout(fig, 1, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(layout, [1 3]);
lum.gui.styleAxes(ax, 'Centre hold, time in the port on each trial''s last hold', t);
completed = T.holdCompleted == 1;
asked = line(ax, 1:T.n, T.holdAsked, 'Color', t.Series, 'LineWidth', 1.8);
back = find(T.steppedBack);
stepped = dots(ax, back, T.holdAsked(back), 'Marker', 'v', 'MarkerSize', 7, ...
               'MarkerFaceColor', t.Series, 'MarkerEdgeColor', 'none');
% The axis holds 98% of the holds and every hold asked for, so a few long early holds do not
% flatten the rest; those above it sit on its top edge, counted in the corner.
top = niceCeiling([quantileOf(T.centreHoldTime, 0.98), 2 * max(T.holdAsked)], 0.5);
shown = min(T.centreHoldTime, top);
done = dots(ax, find(completed), shown(completed), 'Marker', '.', 'MarkerSize', 14, 'Color', t.Correct);
notDone = dots(ax, find(~completed), shown(~completed), 'Marker', 'x', 'MarkerSize', 7, ...
               'Color', t.NotHeld, 'LineWidth', 1.4);
above = sum(T.centreHoldTime > top);
if above > 0
    note(ax, 0.99, 0.98, sprintf('%d above %.2g s, drawn at the top', above, top), t, ...
         'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top');
end
set(ax, 'YLim', [0 top], 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'Time in the port from the poke (s)');
lum.gui.panelLegend(ax, [done, notDone, asked, stepped], ...
                    {sprintf('hold completed (%d)', sum(completed)), ...
                     sprintf('not completed (%d)', sum(~completed & ~isnan(T.centreHoldTime))), ...
                     'hold asked for', 'stepped back'}, t);

ax = nexttile(layout);
lum.gui.styleAxes(ax, 'Completed holds', t);
edges = linspace(0, top, 31);
values = min(T.centreHoldTime(completed), top);
if isempty(values)
    values = NaN;
end
histogram(ax, values, edges, 'Orientation', 'horizontal', 'FaceColor', t.Correct, ...
          'FaceAlpha', 0.8, 'EdgeColor', 'none');
set(ax, 'YLim', [0 top], 'XGrid', 'on');
typical = median(T.holdAsked(completed), 'omitnan');
if ~isnan(typical)
    referenceLine(ax, typical, sprintf('asked for, median %.2f s', typical), t);
end
xlabel(ax, 'Trials');
end


function drawHoldAttempts(fig, T, t)
% How each trial's hold went, in bins of trials; attempts per trial; first-attempt rate by the
% hold asked for. The one plot that tells a first attempt from a later one.
layout = tiledlayout(fig, 2, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
binSize = max(10, 5 * ceil(T.n / 100));
edges = 0:binSize:T.n;
if edges(end) < T.n
    edges(end + 1) = T.n;
end
bins = discretize(1:T.n, edges + 0.5);
nBins = numel(edges) - 1;
kinds = [T.heldFirstAttempt == 1; T.holdCompleted == 1 & T.heldFirstAttempt ~= 1; ...
         T.holdCompleted ~= 1 & T.attempts > 0; T.attempts == 0];
fractions = zeros(nBins, 4);
for b = 1:nBins
    fractions(b, :) = mean(kinds(:, bins == b), 2)';
end

ax = nexttile(layout, [1 3]);
lum.gui.styleAxes(ax, sprintf(['How the hold went, per %d trials: held on the first attempt on ' ...
    '%.0f%% of trials, completed on %.0f%%'], binSize, 100 * mean(T.heldFirstAttempt), ...
    100 * mean(T.holdCompleted)), t);
% Each bin spans its own trials, so a shorter last bin is drawn narrower, not off the axis.
centres = (edges(1:end-1) + edges(2:end)) / 2 + 0.5;
colours = [t.Correct; t.HeldLater; t.NotHeld; t.NoHold];
stacked = stackedBins(ax, edges + 0.5, fractions, colours);
set(ax, 'YLim', [0 1], 'YTick', 0:0.25:1, 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'Fraction of trials');
lum.gui.panelLegend(ax, stacked, {'held on the first attempt', 'held after early withdrawals', ...
                                  'hold not completed', 'no hold started'}, t);

% Attempts per trial: every trial faint, the mean of each bin over it.
ax = nexttile(layout, [1 2]);
lum.gui.styleAxes(ax, 'Hold attempts per trial', t);
top = max(5, ceil(1.1 * quantileOf(T.attempts, 0.98)));
each = dots(ax, 1:T.n, min(T.attempts, top), 'Marker', '.', 'MarkerSize', 11, 'Color', t.SeriesSoft);
means = arrayfun(@(b) mean(T.attempts(bins == b)), 1:nBins);
binMean = line(ax, centres, means, 'Color', t.Series, 'LineWidth', 2.2, 'Marker', 'o', ...
               'MarkerSize', 6, 'MarkerFaceColor', t.Series);
above = sum(T.attempts > top);
if above > 0
    note(ax, 0.99, 0.98, sprintf('%d trial(s) above %d, drawn at the top', above, top), t, ...
         'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top');
end
set(ax, 'YLim', [0 top], 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'Attempts');
lum.gui.panelLegend(ax, [each, binMean], {'each trial', sprintf('mean per %d trials', binSize)}, t);

% The first-attempt rate by the hold asked for, over trials that started a hold.
ax = nexttile(layout);
lum.gui.styleAxes(ax, 'Held on the first attempt, by hold asked for', t);
started = T.attempts > 0;
if ~any(started)
    note(ax, 0.5, 0.5, 'No hold started', t, 'Units', 'normalized', 'HorizontalAlignment', 'center');
    return
end
[labels, members] = holdGroups(T.holdAsked, started);
rates = cellfun(@(m) mean(T.heldFirstAttempt(m)), members);
counts = cellfun(@nnz, members);
bar(ax, 1:numel(rates), rates, 0.5, 'FaceColor', t.Correct, 'EdgeColor', 'none');
for k = 1:numel(rates)
    note(ax, k, rates(k) + 0.02, sprintf('n=%d', counts(k)), t, 'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'bottom');
end
set(ax, 'YLim', [0 1.1], 'YTick', 0:0.25:1, 'XLim', [0.4, numel(rates) + 0.6], ...
    'XTick', 1:numel(rates), 'XTickLabel', labels);
xlabel(ax, 'Hold asked for (s, from the poke)');
ylabel(ax, 'Fraction of trials with a hold');
end


function drawEngagement(fig, T, t)
% Trials by outcome over session time, trial length, water accumulated.
layout = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
minutes = T.finish / 60;
binMinutes = 5;
edges = 0:binMinutes:max(2 * binMinutes, ceil(max(minutes) / binMinutes) * binMinutes);
[names, colours] = outcomeRows(T, t);
row = outcomeRow(T, 1:T.n);
counts = zeros(numel(edges) - 1, numel(names));
for g = 1:numel(names)
    counts(:, g) = histcounts(minutes(row == g), edges)';
end
ax = nexttile(layout);
lum.gui.styleAxes(ax, sprintf('Trials ended in each %d minutes, by how they ended', binMinutes), t);
bars = bar(ax, edges(1:end-1) + binMinutes / 2, counts, 0.85, 'stacked', 'EdgeColor', 'none');
bars(1).BaseLine.Visible = 'off';
for g = 1:numel(bars)
    bars(g).FaceColor = colours(g, :);
end
set(ax, 'XLim', [0 edges(end)]);
ylabel(ax, 'Trials');
lum.gui.panelLegend(ax, bars, lower(names), t);

ax = nexttile(layout);
lum.gui.styleAxes(ax, 'Trial length', t);
lengths = T.finish - T.start;
dots(ax, T.start / 60, lengths, 'Marker', '.', 'MarkerSize', 12, 'Color', t.Series);
limits = logLimits(lengths, false);
ticks = logTicks(limits);
set(ax, 'XLim', [0 edges(end)], 'YScale', 'log', 'YLim', limits, ...
    'YTick', ticks, 'YTickLabel', compose('%g', ticks), 'YMinorTick', 'off');
ylabel(ax, 'Seconds (log)');

ax = nexttile(layout);
water = cumsum(T.sideWater + nanToZero(T.centreReward));
lum.gui.styleAxes(ax, sprintf('Water accumulated: %.0f uL in %d trials', water(end), T.n), t);
line(ax, minutes, water, 'Color', t.Series, 'LineWidth', 2.4);
set(ax, 'XLim', [0 edges(end)], 'YLim', [0, max(10, water(end) * 1.08)]);
ylabel(ax, 'Water (uL)');
xlabel(ax, 'Minutes from the first trial');
end


function drawPortActivity(fig, T, t)
% Pokes per minute at each port over the session.
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
lum.gui.styleAxes(ax, 'Pokes per minute, each port', t);
last = max([T.finish, 1]) / 60;
edges = 0:1:ceil(last);
if numel(edges) < 2
    edges = [0 1];
end
ports = {'Left', 'Centre', 'Right'};
colours = [t.Left; t.Series; t.Right];
handles = gobjects(1, 3);
for p = 1:3
    counts = histcounts(T.pokes.(ports{p}) / 60, edges);
    handles(p) = stairs(ax, edges, [counts counts(end)], 'Color', colours(p, :), 'LineWidth', 1.8);
end
set(ax, 'XLim', [0 edges(end)]);
xlabel(ax, 'Minutes from the first trial');
ylabel(ax, 'Pokes per minute');
lum.gui.panelLegend(ax, handles, {sprintf('left (%d)', numel(T.pokes.Left)), ...
                                  sprintf('centre (%d)', numel(T.pokes.Centre)), ...
                                  sprintf('right (%d)', numel(T.pokes.Right))}, t);
end


function drawSessionTiming(fig, Data, T, t)
% MATLAB's time per trial for each step, a small panel each, and its memory.
layout = tiledlayout(fig, 2, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
names = {'prepare', 'send', 'plot', 'save'};
for i = 1:numel(names)
    ax = nexttile(layout);
    values = NaN(1, T.n);
    if isfield(Data, 'Timing') && isfield(Data.Timing, names{i})
        values = 1000 * Data.Timing.(names{i})(1:T.n);
    end
    if strcmp(names{i}, 'save')
        values(values <= 1) = NaN;   % Only the trials that saved
    end
    typical = median(values, 'omitnan');
    lum.gui.styleAxes(ax, sprintf('%s, median %.0f ms', names{i}, typical), t);
    dots(ax, 1:T.n, values, 'Marker', '.', 'MarkerSize', 10, 'Color', t.SeriesSoft);
    if ~isnan(typical)
        line(ax, [0, T.n + 1], [typical typical], 'Color', t.Series, 'LineWidth', 1.6);
    end
    top = niceCeiling(quantileOf(values, 0.99), 1);
    set(ax, 'XLim', [0, max(T.n, 20) + 1], 'YLim', [0 top]);
    if i == 1
        ylabel(ax, 'MATLAB''s time per trial (ms)');
    end
    xlabel(ax, 'Trial');
end

ax = nexttile(layout, [1 4]);
lum.gui.styleAxes(ax, 'MATLAB''s memory at each save', t);
if isfield(Data, 'Timing') && isfield(Data.Timing, 'memoryGB')
    values = Data.Timing.memoryGB(1:T.n);
    kept = find(~isnan(values));
    line(ax, kept, values(kept), 'Marker', '.', 'MarkerSize', 14, 'Color', t.Series, 'LineWidth', 1.6);
end
set(ax, 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'Memory (GB)');
end


function drawPulseLocking(fig, T, t)
% Early withdrawals against the light's carrier pulses (lum.report.pulseLocking): when they
% came in the light, folded on the carrier's period, and the locking at each frequency.
L = lum.report.pulseLocking(T);
if ~L.Measured
    ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
    lum.gui.styleAxes(ax, 'Early withdrawals and the light''s pulses', t);
    note(ax, 0.5, 0.5, sprintf('Not measured: %s', L.Reason), t, 'Units', 'normalized', ...
         'HorizontalAlignment', 'center');
    set(ax, 'XTick', [], 'YTick', []);
    return
end
layout = tiledlayout(fig, 2, 2, 'TileSpacing', 'compact', 'Padding', 'compact');
heading = 'Early withdrawals during the light';
intoLight = 'Time into the light (ms)';
if ~L.Light
    heading = 'Without light (a control): withdrawals';
    intoLight = 'Time into the stimulus (ms)';
end
colours = [t.ChannelA; t.ChannelB];
names = {'channel A', 'channel B'};
channels = find([L.ByChannel.n] > 0);

% When in the light each withdrawal came, with the pulses behind, across the top.
ax = nexttile(layout, [1 2]);
lum.gui.styleAxes(ax, heading, t);
reach = L.Period * ceil(max(L.Time) / L.Period + 1e-9);
edges = 0:0.005:reach;
counts = zeros(2, numel(edges) - 1);
for c = channels
    counts(c, :) = histcounts(L.Time(L.Channel == c), edges);
end
top = niceCeiling(max(counts(:)), 5);
pulses = pulseBands(ax, 1000 * (0:L.Period:reach - 1e-9), 1000 * L.PulseWidth, top, t);
handles = pulses;
labels = {sprintf('pulse (%g ms)', 1000 * L.PulseWidth)};
for c = channels
    handles(end+1) = stairs(ax, 1000 * edges, [counts(c, :) counts(c, end)], 'Color', ...
                            colours(c, :), 'LineWidth', 1.8); %#ok<AGROW>
    labels{end+1} = sprintf('%s (%d)', names{c}, L.ByChannel(c).n); %#ok<AGROW>
end
set(ax, 'XLim', 1000 * [0 reach], 'YLim', [0 top]);
xlabel(ax, intoLight);
ylabel(ax, 'Withdrawals per 5 ms');
lum.gui.panelLegend(ax, handles, labels, t);

% Folded on the period: the share of withdrawals at each time after a pulse began.
ax = nexttile(layout);
lum.gui.styleAxes(ax, sprintf('Folded on the %g Hz period: R %.3f, p %s', L.Frequency, L.R, ...
                              pText(L.P)), t);
bins = 10;
edges = linspace(0, L.Period, bins + 1);
shares = NaN(2, bins);
for c = channels
    shares(c, :) = histcounts(L.Phase(L.Channel == c), edges) / L.ByChannel(c).n;
end
top = max(0.2, 0.05 * ceil(max(shares(:)) / 0.05 + 0.5));
pulses = pulseBands(ax, 0, 1000 * L.PulseWidth, top, t);
line(ax, 1000 * [0 L.Period], [1 1] / bins, 'Color', t.SeriesSoft, 'LineStyle', '--', 'LineWidth', 1);
handles = pulses;
labels = {'pulse'};
for c = channels
    handles(end+1) = stairs(ax, 1000 * edges, [shares(c, :) shares(c, end)], 'Color', ...
                            colours(c, :), 'LineWidth', 1.8); %#ok<AGROW>
    labels{end+1} = sprintf('%s: R %.3f, p %s', names{c}(end), L.ByChannel(c).R, ...
                            pText(L.ByChannel(c).P)); %#ok<AGROW>
end
handles(end+1) = line(ax, 1000 * [L.MeanPhase L.MeanPhase], [0 top], 'Color', t.Series, ...
                      'LineWidth', 1.6);
labels{end+1} = sprintf('mean %.0f ms', 1000 * L.MeanPhase);
set(ax, 'XLim', 1000 * [0 L.Period], 'YLim', [0 top]);
xlabel(ax, 'Time after a pulse began (ms)');
ylabel(ax, 'Share of withdrawals');
lum.gui.panelLegend(ax, handles, labels, t);

% The locking at each frequency against what the withdrawal times' shape alone gives.
ax = nexttile(layout);
lum.gui.styleAxes(ax, sprintf('Locking by frequency, %d withdrawals', L.n), t);
spectrum = L.Spectrum;
expected = line(ax, spectrum.Frequencies, spectrum.Threshold, 'Color', t.SeriesSoft, ...
                'LineStyle', '--', 'LineWidth', 1.6);
measured = line(ax, spectrum.Frequencies, spectrum.R, 'Color', t.Series, 'LineWidth', 2, ...
                'Marker', '.', 'MarkerSize', 12);
top = niceCeiling(max([spectrum.R spectrum.Threshold L.R]), 0.05);
carrier = line(ax, [L.Frequency L.Frequency], [0 top], 'Color', t.Muted, 'LineWidth', 1.4);
set(ax, 'XLim', [min(spectrum.Frequencies) max(spectrum.Frequencies)], 'YLim', [0 top]);
xlabel(ax, 'Frequency (Hz)');
ylabel(ax, 'Locking R');
lum.gui.panelLegend(ax, [measured, expected, carrier], ...
                    {'withdrawals', '95% from their shape alone', 'carrier'}, t);
end


%% Helpers ----------------------------------------------------------------------

function handle = pulseBands(ax, starts, width, top, t)
% A pale band for each light pulse, starting at starts (ms), behind the data. Returns one
% band, for the key.
x = [starts; starts + width; starts + width; starts];
y = repmat([0; 0; top; top], 1, numel(starts));
bands = patch(ax, x, y, t.Faint, 'EdgeColor', 'none');
handle = bands(1);
end


function words = pText(p)
% A p-value as the plots and the log print it.
if p < 0.001
    words = '< 0.001';
else
    words = sprintf('%.3f', p);
end
end

function handles = stackedBins(ax, edges, fractions, colours)
% Stacked bars, one per bin from edges(b) to edges(b + 1) with a small gap either side, so
% bins of unequal size keep their own width. fractions is nBins x nKinds. Returns a patch per
% kind, for the key.
[nBins, nKinds] = size(fractions);
gap = 0.06 * min(diff(edges));
handles = gobjects(1, nKinds);
bottom = zeros(nBins, 1);
for k = 1:nKinds
    x0 = edges(1:end-1)' + gap;
    x1 = edges(2:end)' - gap;
    y0 = bottom;
    y1 = bottom + fractions(:, k);
    handles(k) = patch(ax, [x0 x1 x1 x0]', [y0 y0 y1 y1]', colours(k, :), 'EdgeColor', 'none');
    bottom = y1;
end
end


function words = headingLines(words, width, t)
% The heading on one line, or on two, split at the middle separator, when it would not fit
% the figure's width at the title size (about 0.55 em a character).
if numel(words) * 0.55 * t.Font.Title * 96 / 72 < 0.95 * width
    return
end
parts = strsplit(words, '  |  ');
half = ceil(numel(parts) / 2);
words = {strjoin(parts(1:half), '  |  '), strjoin(parts(half + 1:end), '  |  ')};
end


function handle = dots(ax, x, y, varargin)
% Markers without a line; one invisible point when there are none, so a key can still name
% the series.
if isempty(x)
    x = NaN;
    y = NaN;
end
handle = line(ax, x, y, 'LineStyle', 'none', varargin{:});
end


function handle = note(ax, x, y, words, t, varargin)
% A small muted annotation in the plots' type.
handle = text(ax, x, y, words, 'FontName', t.Font.Name, 'FontSize', t.Font.Note, ...
              'Color', t.Axis, 'Interpreter', 'none', varargin{:});
end


function chanceLine(ax, xSpan, t)
% The 0.5 line a score or a probability is read against: thin, dashed, behind the data.
line(ax, xSpan, [0.5 0.5], 'Color', t.SeriesSoft, 'LineStyle', '--', 'LineWidth', 1);
end


function referenceLine(ax, y, label, t)
% A thin labelled horizontal line across a distribution panel.
limits = xlim(ax);
line(ax, limits, [y y], 'Color', t.Series, 'LineWidth', 1.4);
note(ax, limits(2), y, label, t, 'HorizontalAlignment', 'right', 'VerticalAlignment', 'bottom', ...
     'Color', t.Ink, 'BackgroundColor', t.Panel, 'Margin', 1);
xlim(ax, limits);
end


function value = quantileOf(values, q)
% A quantile without the Statistics Toolbox: linear between order statistics.
values = sort(values(~isnan(values)));
if isempty(values)
    value = NaN;
    return
end
position = 1 + q * (numel(values) - 1);
low = floor(position);
high = ceil(position);
value = values(low) + (position - low) * (values(high) - values(low));
end


function titleText = outcomeTitle(T)
% The outcome raster's title; habituation's says both side ports pay.
if all(T.bothSidesPay)
    titleText = 'Outcomes (habituation: both side ports pay)';
else
    titleText = 'Outcomes';
end
end


function labels = scoreLabels(T)
% The keys of a scored and an unscored choice, as the stage scores them.
if all(T.bothSidesPay)
    labels = {'rewarded', 'not rewarded'};
elseif any(T.bothSidesPay)
    labels = {'rewarded or correct', 'not rewarded or incorrect'};
else
    labels = {'correct', 'incorrect'};
end
end


function label = scoreAxisLabel(T)
% What the score axis measures: trials rewarded in habituation, choices correct otherwise.
if all(T.bothSidesPay)
    label = 'Fraction of trials rewarded';
else
    label = 'Fraction correct';
end
end


function [names, colours] = outcomeRows(T, t)
% How a trial can end, in the order the rows and the stacks show it, and their colours.
names = {'Rewarded or correct', 'Not rewarded or incorrect', 'No side poke in time', ...
         'Hold not completed', 'No hold started'};
if all(T.bothSidesPay)
    names(1:2) = {'Rewarded', 'Not rewarded'};
elseif ~any(T.bothSidesPay)
    names(1:2) = {'Correct', 'Incorrect'};
end
colours = [t.Correct; t.Incorrect; t.NoSidePoke; t.NotHeld; t.NoHold];
end


function row = outcomeRow(T, trials)
% 1 scored good, 2 scored bad, 3 no side poke, 4 hold not completed (the hold window ran out,
% or an early withdrawal ended the trial), 5 no hold started.
row = zeros(size(trials));
outcome = T.outcome(trials);
chose = ~isnan(T.choice(trials));
row(chose & T.scored(trials) == 1) = 1;
row(chose & T.scored(trials) ~= 1) = 2;
row(~chose & outcome == lum.Outcome.NoResponse) = 3;
row(~chose & ismember(outcome, [lum.Outcome.HoldNotCompleted, lum.Outcome.EarlyWithdrawal])) = 4;
row(~chose & outcome == lum.Outcome.NoInitiation) = 5;
row(row == 0) = 2;   % CorrectNoReward without a choice cannot happen; kept visible if it does
end


function [labels, members] = holdGroups(holdAsked, started)
% Trials that started a hold, grouped by the hold asked for: a group per value (to 10 ms)
% when there are five or fewer, otherwise five equal ranges.
values = round(holdAsked(started) * 100) / 100;
distinct = unique(values);
if numel(distinct) <= 5
    labels = compose('%.2f', distinct);
    members = arrayfun(@(v) started & round(holdAsked * 100) / 100 == v, distinct, ...
                       'UniformOutput', false);
    return
end
edges = linspace(min(values), max(values), 6);
labels = compose('%.2f-%.2f', [edges(1:end-1); edges(2:end)]');
group = discretize(holdAsked, edges);
members = arrayfun(@(g) started & group == g, 1:5, 'UniformOutput', false);
end


function window = movingWindow(T)
% The online figure's performance window.
window = min(50, max(10, round(T.S.Session.MaxTrials / 20)));
end


function values = moving(scored, window, members)
% Mean of the scored values in each trial's window, over the members only.
n = numel(scored);
values = NaN(1, n);
for k = 1:n
    first = max(1, k - window + 1);
    inWindow = scored(first:k);
    inWindow = inWindow(members(first:k) & ~isnan(inWindow));
    if ~isempty(inWindow)
        values(k) = mean(inWindow);
    end
end
end


function values = cumulativeMean(scored)
% The running mean of the scored values from trial 1, NaN until the first.
counted = ~isnan(scored);
sums = cumsum(nanToZero(scored));
values = sums ./ max(1, cumsum(counted));
values(cumsum(counted) == 0) = NaN;
end


function [pLeft, standardError, counts] = psychometric(point, choice, nPoints)
% P(chose left) per point with its binomial standard error, over trials with a choice.
counts = zeros(1, nPoints);
lefts = zeros(1, nPoints);
for k = 1:numel(point)
    if point(k) >= 1 && ~isnan(choice(k))
        counts(point(k)) = counts(point(k)) + 1;
        lefts(point(k)) = lefts(point(k)) + (choice(k) == 1);
    end
end
pLeft = lefts ./ counts;
pLeft(counts == 0) = NaN;
standardError = sqrt(pLeft .* (1 - pLeft) ./ max(counts, 1));
standardError(counts == 0) = 0;
end


function values = runningMedian(values, window)
% Median of the last `window` values that exist, at every trial that has one.
out = NaN(size(values));
present = find(~isnan(values));
for i = 1:numel(present)
    recent = values(present(max(1, i - window + 1):i));
    out(present(i)) = median(recent);
end
values = fillForward(out);
end


function values = fillForward(values)
% Carry the last value across the gaps, so a line does not break at every missing trial.
last = NaN;
for k = 1:numel(values)
    if isnan(values(k))
        values(k) = last;
    else
        last = values(k);
    end
end
end


function values = nanToZero(values)
% NaN counted as 0.
values(isnan(values)) = 0;
end


function offset = jitter(n, step)
% The online figure's fixed jitter per trial.
offset = 0.025 * (2 * mod(n * step, 1) - 1);
end


function upper = niceCeiling(values, minimum)
% An upper axis limit a little above the largest value, at least minimum.
values = values(~isnan(values));
if isempty(values)
    upper = minimum;
    return
end
upper = max(minimum, 1.15 * max(values));
end


function limits = logLimits(values, reachSecond)
% The online figure's log-axis limits: a 1-2-5 step holding every value, and (unless
% reachSecond is false) at least 0.1-1 s.
if nargin < 2
    reachSecond = true;
end
values = values(values > 0 & isfinite(values));
steps = [1 2 5];
if isempty(values)
    limits = [0.1 10];
    return
end
low = min(values) / 1.1;
high = max(values) * 1.1;
decade = 10 ^ floor(log10(low));
lower = decade * steps(find(steps * decade <= low, 1, 'last'));
decade = 10 ^ floor(log10(high));
candidates = [steps 10] * decade;
upper = candidates(find(candidates >= high, 1));
limits = [max(lower, 0.001), upper];
if reachSecond
    limits = [min(0.1, limits(1)), max(1, limits(2))];
end
end


function ticks = logTicks(limits)
% Ticks on a 1-2-5 step inside the limits; only 1 and 5 of each decade when that is too many.
decades = floor(log10(limits(1))):ceil(log10(limits(2)));
ticks = reshape([1; 2; 5] * 10 .^ decades, 1, []);
ticks = ticks(ticks >= limits(1) * 0.999 & ticks <= limits(2) * 1.001);
if numel(ticks) > 8
    ticks = ticks(ismember(round(ticks ./ 10 .^ floor(log10(ticks))), [1 5]));
end
end


function edges = logEdges(values, limits, nBins)
% Histogram edges on a log scale, spanning the data's own range inside the axis limits.
values = values(values > 0 & isfinite(values));
if isempty(values)
    edges = logspace(log10(limits(1)), log10(limits(2)), nBins + 1);
    return
end
low = max(limits(1), min(values));
high = min(limits(2), max(values));
if high <= low
    high = low * 1.5;
end
edges = logspace(log10(low) - 0.01, log10(high) + 0.01, nBins + 1);
end

