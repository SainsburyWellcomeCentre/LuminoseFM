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
%                       (rewarded in habituation, correct otherwise), above each trial's
%                       outcome
%   02_Performance      Moving-window score, all and by rewarded side, and the running score
%   03_Psychometric     P(chose left) by group or evidence, whole session and each half,
%                       against the contingency
%   04_Evidence         Every choice at its trial's u_A and u_B, with the contingency's boundary
%   05_BySide           Score and choices by rewarded side, and trials without a choice
%   06_SideBias         P(chose left) over the last BiasWindow choices, with bias
%                       correction's target, and the side each trial paid
%   07_ReactionTime     Per trial by side with a running median, and their distribution
%   08_CentreHold       Time in the centre port on each trial's last hold against the hold
%                       asked for, and every hold attempt's time
%   09_HoldAttempts     Hold attempts and early withdrawals per trial, with the hold asked
%                       for and where automatic shaping stepped it back
%   10_Engagement       Trials by outcome in 5-minute bins, trial length, and water and
%                       trials accumulated over the session
%   11_PortActivity     Pokes per minute at each port over the session
%   12_SessionTiming    MATLAB's prepare, plot and save time per trial, and its memory
%
% Written after the session's data are saved, so nothing in the data file depends on them,
% and from the data alone (lum.report.sessionTrials), so an old file draws the same way
% (lum.report.fromFile). Each figure is made invisible, printed and deleted before the next.
%
% Arguments:
%   Data      The session's data (BpodSystem.Data, or a saved file's SessionData)
%   dataFile  The session's data file; names the images and places the folder
%
% Options:
%   'Folder'      Where to write (default lum.report.folder(dataFile, 'Plots'))
%   'Resolution'  Dots per inch of the images (default 110)
%
% Returns:
%   files     Full paths of the images written
%   problems  One message per plot that could not be drawn; the others are still written.
%             Never throws for a single plot.
%
% See also: lum.report.write, lum.report.sessionTrials, lum.OnlinePlots

p = inputParser;
p.FunctionName = 'lum.report.summaryPlots';
addParameter(p, 'Folder', '');
addParameter(p, 'Resolution', 110, @(x) isnumeric(x) && isscalar(x) && x > 0);
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
    plots(end+1, :) = {1, 'Outcomes', page, [1400 560], @(fig) drawOutcomes(fig, T, t, trialRange)}; %#ok<AGROW>
end
plots = [plots; ...
    {2, 'Performance', 1, [1400 520], @(fig) drawPerformance(fig, T, t)}; ...
    {3, 'Psychometric', 1, [1100 620], @(fig) drawPsychometric(fig, T, t)}; ...
    {4, 'Evidence', 1, [900 760], @(fig) drawEvidence(fig, T, t)}; ...
    {5, 'BySide', 1, [1100 520], @(fig) drawBySide(fig, T, t)}; ...
    {6, 'SideBias', 1, [1400 520], @(fig) drawSideBias(fig, T, t)}; ...
    {7, 'ReactionTime', 1, [1400 560], @(fig) drawReactionTime(fig, T, t)}; ...
    {8, 'CentreHold', 1, [1400 560], @(fig) drawCentreHold(fig, T, t)}; ...
    {9, 'HoldAttempts', 1, [1400 560], @(fig) drawHoldAttempts(fig, T, t)}; ...
    {10, 'Engagement', 1, [1400 720], @(fig) drawEngagement(fig, T, t)}; ...
    {11, 'PortActivity', 1, [1400 560], @(fig) drawPortActivity(fig, T, t)}; ...
    {12, 'SessionTiming', 1, [1400 560], @(fig) drawSessionTiming(fig, Data, T, t)}];

% One invisible figure, cleared between plots: making a figure costs more than drawing in it.
fig = figure('Visible', 'off', 'Color', t.Background, 'MenuBar', 'none', 'ToolBar', 'none', ...
             'NumberTitle', 'off', 'HandleVisibility', 'off', 'InvertHardcopy', 'off', ...
             'PaperPositionMode', 'auto');
cleanup = onCleanup(@() delete(fig));
for i = 1:size(plots, 1)
    [number, name, page, pixels, draw] = plots{i, :};
    file = fullfile(folder, sprintf('%02d_%s_%02d_%s.png', number, name, page, tag));
    try
        clf(fig);
        fig.Position = [20 20 pixels];
        draw(fig);
        pageText = '';
        if nPages > 1 && number == 1
            pageText = sprintf('  |  trials %d-%d', (page - 1) * pageSize + 1, ...
                               min(T.n, page * pageSize));
        end
        layout = findobj(fig, 'Type', 'tiledlayout');
        layout(1).Title.String = [heading pageText];
        layout(1).Title.FontSize = 10;
        layout(1).Title.FontWeight = 'bold';
        layout(1).Title.Color = t.Ink;
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
% Each trial's choice by group (or evidence), and each trial's outcome.
layout = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
trials = trialRange(1):trialRange(2);
xLimits = [trialRange(1) - 0.5, trialRange(1) + max(trialRange(2) - trialRange(1), 20) + 0.5];
ax = nexttile(layout, [2 1]);
styleAxes(ax, t, outcomeTitle(T));
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
         'MarkerSize', 5, 'MarkerFaceColor', t.Correct, 'MarkerEdgeColor', 'none'), ...
    dots(ax, trials(chose & ~scoredGood), y(chose & ~scoredGood), 'Marker', 'o', ...
         'MarkerSize', 5, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', t.Incorrect, 'LineWidth', 1.2), ...
    dots(ax, trials(~chose), y(~chose), 'Marker', 'x', 'MarkerSize', 5, 'Color', t.NoChoice)];
if byEvidence
    ylabel(ax, stimulusSet.EvidenceName);
else
    K = stimulusSet.nGroups;
    set(ax, 'YLim', [0.5 K + 0.5], 'YTick', 1:K, 'YTickLabel', stimulusSet.GroupLabels, 'YDir', 'reverse');
end
set(ax, 'XLim', xLimits);
keyLegend(ax, handles, [scoreLabels(T), {'no choice'}], t);

% Why each trial ended, a row per outcome.
ax = nexttile(layout);
styleAxes(ax, t, 'How each trial ended');
names = {'Rewarded / correct', 'Not rewarded / incorrect', 'No side poke in time', ...
         'Hold not completed', 'Early withdrawal (trial ended)', 'No hold started'};
if all(T.bothSidesPay)
    names(1:2) = {'Rewarded', 'Not rewarded'};
elseif ~any(T.bothSidesPay)
    names(1:2) = {'Correct', 'Incorrect'};
end
row = outcomeRow(T, trials);
colours = [t.Correct; t.Incorrect; t.NoChoice; t.Warn; t.Warn; t.Muted];
for r = 1:numel(names)
    members = trials(row == r);
    dots(ax, members, r * ones(size(members)), 'Marker', '|', 'MarkerSize', 7, ...
         'Color', colours(r, :), 'LineWidth', 1.2);
end
set(ax, 'YLim', [0.5 numel(names) + 0.5], 'YTick', 1:numel(names), 'YTickLabel', names, ...
     'YDir', 'reverse', 'XLim', xLimits);
xlabel(ax, 'Trial');
end


function drawPerformance(fig, T, t)
% The online figure's performance panel over every trial, and the running score.
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
styleAxes(ax, t, sprintf('Performance, %d-trial window', movingWindow(T)));
window = movingWindow(T);
x = 1:T.n;
line(ax, [0 T.n + 1], [0.5 0.5], 'Color', t.Faint, 'LineStyle', '--', 'LineWidth', 1);
left = line(ax, x, moving(T.scored, window, T.correctSide == 1), 'Color', t.Left, 'LineWidth', 1);
right = line(ax, x, moving(T.scored, window, T.correctSide == 2), 'Color', t.Right, 'LineWidth', 1);
whole = line(ax, x, moving(T.scored, window, true(1, T.n)), 'Color', t.Ink, 'LineWidth', 2);
running = line(ax, x, cumulativeMean(T.scored), 'Color', t.Accent, 'LineStyle', ':', 'LineWidth', 1.5);
set(ax, 'YLim', [0 1], 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, scoreAxisLabel(T));
keyLegend(ax, [whole, left, right, running], ...
          {'all', 'left-rewarded', 'right-rewarded', 'session so far'}, t);
end


function drawPsychometric(fig, T, t)
% P(chose left) along the family's evidence or by group, whole session and each half.
stimulusSet = T.stimulusSet;
layout = lum.OnlinePlots.psychometricLayoutOf(stimulusSet);
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
styleAxes(ax, t, layout.Title);
span = [min(layout.X), max(layout.X)];
pad = 0.5;
if isempty(layout.TickLabels) && diff(span) > 0
    pad = 0.08 * diff(span);
end
line(ax, span + [-pad pad], [0.5 0.5], 'Color', t.Faint, 'LineStyle', '--');
target = line(ax, layout.X, layout.Target, 'Color', t.Muted, 'LineStyle', ':', 'Marker', 'd', ...
              'MarkerSize', 5, 'LineWidth', 1);
chose = ~isnan(T.choice);
point = zeros(1, T.n);
point(chose) = layout.Index(T.pattern(chose));
halves = {1:floor(T.n / 2), floor(T.n / 2) + 1:T.n};
styles = {'--', '-.'};
halfHandles = gobjects(1, 2);
for h = 1:2
    [pLeft, ~] = psychometric(point(halves{h}), T.choice(halves{h}), numel(layout.X));
    halfHandles(h) = line(ax, layout.X, pLeft, 'Color', mix(t.Accent, 0.45), ...
                          'LineStyle', styles{h}, 'Marker', '.', 'MarkerSize', 10);
end
[pLeft, errors, counts] = psychometric(point, T.choice, numel(layout.X));
whole = errorbar(ax, layout.X, pLeft, errors, 'Color', t.Accent, 'LineWidth', 1.5, 'Marker', 'o', ...
                 'MarkerSize', 6, 'MarkerFaceColor', t.Accent, 'CapSize', 0);
for b = 1:numel(layout.X)
    if counts(b) > 0
        text(ax, layout.X(b), 0.04, sprintf('n=%d', counts(b)), 'HorizontalAlignment', 'center', ...
             'FontSize', 8, 'Color', t.Muted);
    end
end
set(ax, 'YLim', [0 1], 'XLim', span + [-pad pad]);
if ~isempty(layout.TickLabels)
    set(ax, 'XTick', layout.X, 'XTickLabel', layout.TickLabels);
end
xlabel(ax, layout.XLabel);
ylabel(ax, 'P(choose left)');
keyLegend(ax, [whole, halfHandles, target], ...
          {'chose left, whole session', 'first half', 'second half', 'contingency'}, t);
end


function drawEvidence(fig, T, t)
% Every choice at the light its trial delivered on A and B.
stimulusSet = T.stimulusSet;
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
styleAxes(ax, t, sprintf('Evidence, u_A vs u_B, by choice  (%s left, %s right)', char(9664), char(9654)));
edge = struct('Kind', 'diagonal', 'Value', NaN);
if isfield(stimulusSet, 'Boundary')
    edge = stimulusSet.Boundary;
end
switch edge.Kind
    case 'diagonal'
        line(ax, [0 1], [0 1], 'Color', t.Faint, 'LineStyle', '--');
    case 'vertical'
        line(ax, [1 1] * edge.Value, [0 1], 'Color', t.Faint, 'LineStyle', '--');
    case 'horizontal'
        line(ax, [0 1], [1 1] * edge.Value, 'Color', t.Faint, 'LineStyle', '--');
    case 'line'
        x = [-0.1 1.1];
        line(ax, x, edge.Slope * x + edge.Intercept, 'Color', t.Faint, 'LineStyle', '--');
end
lightA = reshape(stimulusSet.Descriptors.AOn, 1, []) / stimulusSet.Duration;
lightB = reshape(stimulusSet.Descriptors.BOn, 1, []) / stimulusSet.Duration;
chose = find(~isnan(T.choice));
lit = double(T.optoOn(chose) == 1);
x = lit .* lightA(T.pattern(chose)) + jitter(chose, 0.6180339887);
y = lit .* lightB(T.pattern(chose)) + jitter(chose, 0.7548776662);
good = T.scored(chose) == 1;
markers = {'<', '>'};
handles = gobjects(1, 2);
for side = 1:2
    mine = T.choice(chose) == side;
    handles(1) = dots(ax, x(mine & good), y(mine & good), 'Marker', markers{side}, ...
                      'MarkerSize', 5, 'MarkerFaceColor', t.Correct, 'MarkerEdgeColor', 'none');
    handles(2) = dots(ax, x(mine & ~good), y(mine & ~good), 'Marker', markers{side}, ...
                      'MarkerSize', 5, 'MarkerFaceColor', 'none', 'MarkerEdgeColor', t.Incorrect);
end
set(ax, 'XLim', [-0.06 1.06], 'YLim', [-0.06 1.06], 'XTick', 0:0.25:1, 'YTick', 0:0.25:1);
axis(ax, 'square');
xlabel(ax, 'u_A, evidence on A (fraction of the window lit)');
ylabel(ax, 'u_B, evidence on B');
keyLegend(ax, handles, scoreLabels(T), t);
end


function drawBySide(fig, T, t)
% Score by the side a trial paid; choices made by side; trials without a choice.
layout = tiledlayout(fig, 1, 3, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(layout);
styleAxes(ax, t, 'Score by rewarded side');
fractions = zeros(1, 2);
counts = zeros(1, 2);
for side = 1:2
    scored = T.scored(T.correctSide == side & ~isnan(T.scored));
    counts(side) = numel(scored);
    fractions(side) = mean(scored);
end
bars = bar(ax, 1:2, fractions, 0.55, 'FaceColor', 'flat', 'EdgeColor', 'none');
bars.CData = [t.Left; t.Right];
line(ax, [0.4 2.6], [0.5 0.5], 'Color', t.Faint, 'LineStyle', '--');
for side = 1:2
    text(ax, side, min(max(fractions(side), 0), 1) + 0.05, sprintf('%d trials', counts(side)), ...
         'HorizontalAlignment', 'center', 'FontSize', 8, 'Color', t.Muted);
end
set(ax, 'YLim', [0 1.12], 'XLim', [0.4 2.6], 'XTick', 1:2, ...
     'XTickLabel', {'left-rewarded', 'right-rewarded'}, 'XGrid', 'off');
ylabel(ax, scoreAxisLabel(T));

ax = nexttile(layout);
styleAxes(ax, t, 'Choices made');
chosen = [sum(T.choice == 1), sum(T.choice == 2)];
bars = bar(ax, 1:2, chosen, 0.55, 'FaceColor', 'flat', 'EdgeColor', 'none');
bars.CData = [t.Left; t.Right];
for side = 1:2
    text(ax, side, chosen(side), sprintf('%d (%.0f%%)', chosen(side), 100 * chosen(side) / max(1, sum(chosen))), ...
         'HorizontalAlignment', 'center', 'VerticalAlignment', 'bottom', 'FontSize', 8, 'Color', t.Muted);
end
set(ax, 'XLim', [0.4 2.6], 'XTick', 1:2, 'XTickLabel', {'chose left', 'chose right'}, ...
     'XGrid', 'off', 'YLim', [0, max(1, max(chosen)) * 1.15]);
ylabel(ax, 'Trials');

ax = nexttile(layout);
styleAxes(ax, t, 'Trials without a choice, by rewarded side');
none = [sum(isnan(T.choice) & T.correctSide == 1), sum(isnan(T.choice) & T.correctSide == 2)];
bars = bar(ax, 1:2, none, 0.55, 'FaceColor', 'flat', 'EdgeColor', 'none');
bars.CData = [mix(t.Left, 0.5); mix(t.Right, 0.5)];
for side = 1:2
    text(ax, side, none(side), sprintf('%d', none(side)), 'HorizontalAlignment', 'center', ...
         'VerticalAlignment', 'bottom', 'FontSize', 8, 'Color', t.Muted);
end
set(ax, 'XLim', [0.4 2.6], 'XTick', 1:2, 'XTickLabel', {'left-rewarded', 'right-rewarded'}, ...
     'XGrid', 'off', 'YLim', [0, max(1, max(none)) * 1.15]);
ylabel(ax, 'Trials');
end


function drawSideBias(fig, T, t)
% P(chose left) over the last BiasWindow choices, the correction's target, each trial's side.
window = max(1, round(T.S.GUI.BiasWindow));
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
styleAxes(ax, t, sprintf('Side bias, last %d choices', window));
line(ax, [0 T.n + 1], [0.5 0.5], 'Color', t.Faint, 'LineStyle', '--');
chose = find(~isnan(T.choice));
leftChoice = double(T.choice(chose) == 1);
biasLeft = NaN(1, T.n);
for i = 1:numel(chose)
    biasLeft(chose(i)) = mean(leftChoice(max(1, i - window + 1):i));
end
biasLeft = fillForward(biasLeft);
target = line(ax, 1:T.n, T.biasTarget, 'Color', t.Muted, 'LineStyle', ':', 'LineWidth', 1.2);
leftLine = line(ax, 1:T.n, biasLeft, 'Color', t.Left, 'LineWidth', 2);
% The side each trial paid, as ticks along the top and bottom.
leftTrials = find(T.correctSide == 1);
rightTrials = find(T.correctSide == 2);
paidLeft = dots(ax, leftTrials, 1.03 * ones(size(leftTrials)), 'Marker', '|', 'MarkerSize', 5, ...
                'Color', t.Left);
paidRight = dots(ax, rightTrials, -0.03 * ones(size(rightTrials)), 'Marker', '|', 'MarkerSize', 5, ...
                 'Color', t.Right);
set(ax, 'YLim', [-0.06 1.06], 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'P(left)');
keyLegend(ax, [leftLine, target, paidLeft, paidRight], ...
          {'chose left', 'bias correction target', 'trial paid left', 'trial paid right'}, t);
end


function drawReactionTime(fig, T, t)
% Reaction time per trial on a log axis, by side, and its distribution.
layout = tiledlayout(fig, 1, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(layout, [1 3]);
styleAxes(ax, t, 'Reaction time, from leaving the centre port');
rt = T.reactionTime;
leftDots = dots(ax, find(T.choice == 1), rt(T.choice == 1), 'Marker', '.', 'MarkerSize', 10, ...
                'Color', t.Left);
rightDots = dots(ax, find(T.choice == 2), rt(T.choice == 2), 'Marker', '.', 'MarkerSize', 10, ...
                 'Color', t.Right);
median20 = runningMedian(rt, 20);
medianLine = line(ax, 1:T.n, median20, 'Color', t.Ink, 'LineWidth', 1.2);
limits = logLimits(rt);
ticks = [0.01 0.02 0.05 0.1 0.2 0.5 1 2 5 10 20 50 100];
set(ax, 'YScale', 'log', 'YLim', limits, 'YTick', ticks, 'YTickLabel', compose('%g', ticks), ...
     'YMinorGrid', 'off', 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'Seconds (log)');
keyLegend(ax, [leftDots, rightDots, medianLine], {'chose left', 'chose right', 'median of last 20'}, t);

ax = nexttile(layout);
styleAxes(ax, t, 'Distribution');
edges = logspace(log10(limits(1)), log10(limits(2)), 30);
sideColours = [t.Left; t.Right];
for side = 1:2
    values = rt(T.choice == side & rt > 0);
    if ~isempty(values)
        histogram(ax, values, edges, 'Orientation', 'horizontal', 'DisplayStyle', 'stairs', ...
                  'EdgeColor', sideColours(side, :), 'LineWidth', 1.5);
    end
end
set(ax, 'YScale', 'log', 'YLim', limits, 'YTick', ticks, 'YTickLabel', compose('%g', ticks), ...
     'YMinorGrid', 'off');
xlabel(ax, 'Choices');
text(ax, 0.95, 0.97, sprintf('median %.2f s', median(rt, 'omitnan')), 'Units', 'normalized', ...
     'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', 'FontSize', 8, 'Color', t.Muted);
end


function drawCentreHold(fig, T, t)
% Time in the centre port on each trial's last hold, and on every attempt.
layout = tiledlayout(fig, 1, 4, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(layout, [1 3]);
styleAxes(ax, t, 'Centre hold, time in the port on each trial''s last hold');
completed = lum.HoldShaping.completedHold(T.outcome);
asked = line(ax, 1:T.n, T.holdAsked, 'Color', t.Muted, 'LineWidth', 1.2);
% The axis holds 98% of the holds and every hold asked for, so a few long early holds do not
% flatten the rest; those above it sit on its top edge, counted in the corner.
top = niceCeiling([quantileOf(T.centreHoldTime, 0.98), 2 * max(T.holdAsked)], 0.5);
shown = min(T.centreHoldTime, top);
done = dots(ax, find(completed), shown(completed), 'Marker', '.', 'MarkerSize', 10, 'Color', t.Correct);
broken = dots(ax, find(~completed), shown(~completed), 'Marker', 'x', 'MarkerSize', 5, ...
              'Color', t.Incorrect);
above = sum(T.centreHoldTime > top);
if above > 0
    text(ax, 0.99, 0.97, sprintf('%d hold(s) above %.2g s drawn at the top', above, top), ...
         'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
         'FontSize', 8, 'Color', t.Muted);
end
set(ax, 'YLim', [0 top], 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'Seconds from the poke');
keyLegend(ax, [done, broken, asked], {'completed', 'broken', 'asked for'}, t);

ax = nexttile(layout);
styleAxes(ax, t, 'Every hold attempt');
edges = linspace(0, max(top, 0.1), 31);
brokenCounts = histcounts(T.attemptTime(~T.attemptCompleted), edges);
doneCounts = histcounts(T.attemptTime(T.attemptCompleted), edges);
stacked = barh(ax, edges(1:end-1) + diff(edges) / 2, [doneCounts; brokenCounts]', 1, 'stacked', ...
               'EdgeColor', 'none');
stacked(1).FaceColor = t.Correct;
stacked(2).FaceColor = mix(t.Incorrect, 0.6);
askedRange = [min(T.holdDuration), max(T.holdDuration)];
patch(ax, [0 1 1 0] * max([1, doneCounts + brokenCounts]) * 1.05, ...
      askedRange([1 1 2 2]), t.Accent, 'FaceAlpha', 0.08, 'EdgeColor', 'none');
set(ax, 'YLim', [0 top]);
xlabel(ax, 'Attempts');
ylabel(ax, 'Seconds from stimulus onset');
text(ax, 0.95, 0.97, sprintf('%d attempts, %d completed', numel(T.attemptTime), sum(T.attemptCompleted)), ...
     'Units', 'normalized', 'HorizontalAlignment', 'right', 'VerticalAlignment', 'top', ...
     'FontSize', 8, 'Color', t.Muted);
end


function drawHoldAttempts(fig, T, t)
% Attempts and early withdrawals per trial, with the hold asked for and its step backs.
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
styleAxes(ax, t, 'Hold attempts per trial, and the hold asked for');
yyaxis(ax, 'left');
attempts = bar(ax, 1:T.n, T.holdAttempts, 1, 'FaceColor', mix(t.Accent, 0.35), 'EdgeColor', 'none');
hold(ax, 'on');
withdrawals = dots(ax, 1:T.n, T.earlyWithdrawals, 'Marker', '.', 'MarkerSize', 8, ...
                   'Color', t.Incorrect);
ylabel(ax, 'Per trial');
ax.YColor = t.Muted;
set(ax, 'YLim', [0, max(5, max(T.holdAttempts) * 1.1)]);
yyaxis(ax, 'right');
asked = line(ax, 1:T.n, T.holdAsked, 'Color', t.Ink, 'LineWidth', 1.5);
back = find(T.steppedBack);
stepped = dots(ax, back, T.holdAsked(back), 'Marker', 'v', 'MarkerSize', 6, ...
               'MarkerFaceColor', t.Warn, 'MarkerEdgeColor', 'none');
ylabel(ax, 'Hold asked for (s, from the poke)');
ax.YColor = t.Ink;
set(ax, 'YLim', [0, niceCeiling(T.holdAsked, 0.5)]);
set(ax, 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
keyLegend(ax, [attempts, withdrawals, asked, stepped], ...
          {'hold attempts', 'early withdrawals', 'hold asked for', 'stepped back'}, t);
end


function drawEngagement(fig, T, t)
% Trials by outcome over session time, trial length, water and trials accumulated.
layout = tiledlayout(fig, 3, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
minutes = T.finish / 60;
binMinutes = 5;
edges = 0:binMinutes:max(2 * binMinutes, ceil(max(minutes) / binMinutes) * binMinutes);
row = outcomeRow(T, 1:T.n);
groups = {row == 1, row == 2, row == 3, row == 4 | row == 5, row == 6};
names = {'rewarded / correct', 'not rewarded / incorrect', 'no side poke', ...
         'hold not completed', 'no hold started'};
colours = [t.Correct; t.Incorrect; t.NoChoice; t.Warn; t.Muted];
counts = zeros(numel(edges) - 1, numel(groups));
for g = 1:numel(groups)
    counts(:, g) = histcounts(minutes(groups{g}), edges)';
end
ax = nexttile(layout);
styleAxes(ax, t, sprintf('Trials ended in each %d minutes, by outcome', binMinutes));
bars = bar(ax, edges(1:end-1) + binMinutes / 2, counts, 1, 'stacked', 'EdgeColor', 'none');
for g = 1:numel(bars)
    bars(g).FaceColor = colours(g, :);
end
set(ax, 'XLim', [0 edges(end)]);
ylabel(ax, 'Trials');
keyLegend(ax, bars, names, t);

ax = nexttile(layout);
styleAxes(ax, t, 'Trial length');
dots(ax, T.start / 60, T.finish - T.start, 'Marker', '.', 'MarkerSize', 8, 'Color', t.Accent);
ticks = [0.5 1 2 5 10 20 50 100 200 500 1000];
set(ax, 'XLim', [0 edges(end)], 'YScale', 'log', 'YLim', logLimits(T.finish - T.start), ...
    'YTick', ticks, 'YTickLabel', compose('%g', ticks), 'YMinorGrid', 'off');
ylabel(ax, 'Seconds (log)');

ax = nexttile(layout);
styleAxes(ax, t, 'Water and trials, accumulated');
yyaxis(ax, 'left');
water = cumsum(T.sideWater + nanToZero(T.centreReward));
waterLine = line(ax, minutes, water, 'Color', t.Accent, 'LineWidth', 2);
ylabel(ax, 'Water (uL)');
ax.YColor = t.Accent;
yyaxis(ax, 'right');
trialsLine = line(ax, minutes, 1:T.n, 'Color', t.Ink, 'LineWidth', 1.2, 'LineStyle', '--');
ylabel(ax, 'Trials');
ax.YColor = t.Ink;
set(ax, 'XLim', [0 edges(end)]);
xlabel(ax, 'Minutes from the first trial');
keyLegend(ax, [waterLine, trialsLine], {sprintf('water, %.0f uL', water(end)), ...
                                        sprintf('trials, %d', T.n)}, t);
end


function drawPortActivity(fig, T, t)
% Pokes per minute at each port over the session.
ax = nexttile(tiledlayout(fig, 1, 1, 'Padding', 'compact'));
styleAxes(ax, t, 'Pokes per minute, each port');
last = max([T.finish, 1]) / 60;
edges = 0:1:ceil(last);
if numel(edges) < 2
    edges = [0 1];
end
ports = {'Left', 'Centre', 'Right'};
colours = [t.Left; t.Ink; t.Right];
handles = gobjects(1, 3);
for p = 1:3
    counts = histcounts(T.pokes.(ports{p}) / 60, edges);
    handles(p) = stairs(ax, edges, [counts counts(end)], 'Color', colours(p, :), 'LineWidth', 1.5);
end
set(ax, 'XLim', [0 edges(end)]);
xlabel(ax, 'Minutes from the first trial');
ylabel(ax, 'Pokes per minute');
keyLegend(ax, handles, {sprintf('left (%d)', numel(T.pokes.Left)), ...
                        sprintf('centre (%d)', numel(T.pokes.Centre)), ...
                        sprintf('right (%d)', numel(T.pokes.Right))}, t);
end


function drawSessionTiming(fig, Data, T, t)
% MATLAB's time per trial for preparing, plotting and saving, and its memory.
layout = tiledlayout(fig, 2, 1, 'TileSpacing', 'compact', 'Padding', 'compact');
ax = nexttile(layout);
styleAxes(ax, t, 'MATLAB''s work per trial (outside the state machine)');
names = {'prepare', 'send', 'plot', 'save'};
colours = [t.Accent; t.ChannelA; t.ChannelB; t.Muted];
handles = gobjects(0);
labels = {};
if isfield(Data, 'Timing')
    for i = 1:numel(names)
        if isfield(Data.Timing, names{i})
            values = 1000 * Data.Timing.(names{i})(1:T.n);
            handles(end+1) = dots(ax, 1:T.n, values, 'Marker', '.', 'MarkerSize', 7, ...
                                  'Color', colours(i, :)); %#ok<AGROW>
            counted = values(values > 1);   % save: only the trials that saved
            if ~strcmp(names{i}, 'save')
                counted = values;
            end
            labels{end+1} = sprintf('%s (median %.0f ms)', names{i}, median(counted, 'omitnan')); %#ok<AGROW>
        end
    end
end
set(ax, 'XLim', [0, max(T.n, 20) + 1]);
ylabel(ax, 'ms');
if ~isempty(handles)
    keyLegend(ax, handles, labels, t);
end

ax = nexttile(layout);
styleAxes(ax, t, 'MATLAB''s memory at each save');
if isfield(Data, 'Timing') && isfield(Data.Timing, 'memoryGB')
    values = Data.Timing.memoryGB(1:T.n);
    kept = find(~isnan(values));
    line(ax, kept, values(kept), 'Marker', '.', 'MarkerSize', 8, 'Color', t.Accent);
end
set(ax, 'XLim', [0, max(T.n, 20) + 1]);
xlabel(ax, 'Trial');
ylabel(ax, 'GB');
end


%% Helpers ----------------------------------------------------------------------

function styleAxes(ax, t, titleText)
% The online figure's panel style (lum.OnlinePlots).
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


function handle = dots(ax, x, y, varargin)
% Markers without a line; one invisible point when there are none, so a key can still name
% the series.
if isempty(x)
    x = NaN;
    y = NaN;
end
handle = line(ax, x, y, 'LineStyle', 'none', varargin{:});
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


function keyLegend(ax, handles, labels, t)
% A panel's key under its axis label, as in the online figure.
legend(ax, handles, labels, 'Location', 'southoutside', 'Orientation', 'horizontal', ...
       'Box', 'off', 'TextColor', t.Muted, 'FontSize', 8, 'AutoUpdate', 'off');
end


function titleText = outcomeTitle(T)
if all(T.bothSidesPay)
    titleText = 'Outcomes  (habituation: both side ports pay)';
else
    titleText = 'Outcomes';
end
end


function labels = scoreLabels(T)
if all(T.bothSidesPay)
    labels = {'rewarded', 'not rewarded'};
elseif any(T.bothSidesPay)
    labels = {'rewarded or correct', 'not rewarded or incorrect'};
else
    labels = {'correct', 'incorrect'};
end
end


function label = scoreAxisLabel(T)
if all(T.bothSidesPay)
    label = 'Fraction of trials rewarded';
else
    label = 'Fraction correct';
end
end


function row = outcomeRow(T, trials)
% 1 scored good, 2 scored bad, 3 no side poke, 4 hold not completed, 5 early withdrawal that
% ended the trial, 6 no hold started.
row = zeros(size(trials));
outcome = T.outcome(trials);
chose = ~isnan(T.choice(trials));
row(chose & T.scored(trials) == 1) = 1;
row(chose & T.scored(trials) ~= 1) = 2;
row(~chose & outcome == lum.Outcome.NoResponse) = 3;
row(~chose & outcome == lum.Outcome.HoldNotCompleted) = 4;
row(~chose & outcome == lum.Outcome.EarlyWithdrawal) = 5;
row(~chose & outcome == lum.Outcome.NoInitiation) = 6;
row(row == 0) = 2;   % CorrectNoReward without a choice cannot happen; kept visible if it does
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
values(isnan(values)) = 0;
end


function offset = jitter(n, step)
% The online figure's fixed jitter per trial.
offset = 0.025 * (2 * mod(n * step, 1) - 1);
end


function upper = niceCeiling(values, minimum)
values = values(~isnan(values));
if isempty(values)
    upper = minimum;
    return
end
upper = max(minimum, 1.15 * max(values));
end


function limits = logLimits(values)
% The online figure's log-axis limits: a 1-2-5 step holding every value, at least 0.1-1 s.
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
limits = [min(0.1, max(lower, 0.001)), max(1, upper)];
end


function colour = mix(colour, amount)
% A colour faded towards white by (1 - amount).
colour = 1 - amount * (1 - colour);
end
