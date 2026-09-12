function drawTestPulseSchedule(ax, plan, t)
% lum.gui.drawTestPulseSchedule draws a test-pulse schedule across the session.
%
% Two lanes, channel A above B, over session time in minutes. Each step that delivers
% light fills the lanes it uses: probes faintly, plasticity trains strongly, and a
% step alternating A and B both lanes more faintly still. Rest is left empty. Each
% step is labelled above the lanes.
%
% Used by the test-pulse designer and the sleep setup dialog as a preview, and by the
% sleep plots, once, as the background of their schedule panel. Works on axes and
% uiaxes; clears the axes first, and leaves their title alone.
%
% Arguments:
%   ax    Axes to draw into
%   plan  From lum.sleep.testPulsePlan
%   t     lum.gui.theme
%
% See also: lum.sleep.testPulsePlan, lum.gui.drawTestPulseEpoch, lum.sleep.Plots

cla(ax);
hold(ax, 'on');
set(ax, 'Color', t.Panel, 'XColor', t.Muted, 'YColor', t.Muted, 'TickDir', 'out', 'Box', 'off');
if isempty(plan.Steps)
    text(ax, 0.5, 1.2, 'No test pulses', 'HorizontalAlignment', 'center', 'Color', t.Muted);
    set(ax, 'XLim', [0 1], 'YLim', [0 2.45], 'YTick', []);
    return
end

lanes = {[1.1 1.9], [0.1 0.9]};
colours = {t.ChannelA, t.ChannelB};
nNarrow = 0;   % Labels of short steps alternate between two heights, so neighbours do not collide
for s = 1:numel(plan.Steps)
    step = plan.Steps(s);
    x0 = step.Start / 60;
    x1 = x0 + step.Duration / 60;
    if s > 1
        line(ax, [x0 x0], [0 2.45], 'Color', t.Faint, 'LineWidth', 1);
    end
    if step.nEpochs > 0
        alpha = 0.35;
        label = 'Probe';
        if ~isempty(step.Train)
            alpha = 0.85;
            label = step.Kind;
        end
        switch step.Channels
            case 'A'
                used = 1;
            case 'B'
                used = 2;
            case 'Alternate A and B'
                used = [1 2];
                alpha = 0.6 * alpha;
                label = sprintf('%s, alternating', label);
            otherwise
                used = [1 2];
        end
        for c = used
            patch(ax, [x0 x1 x1 x0], lanes{c}([1 1 2 2]), colours{c}, 'FaceAlpha', alpha, ...
                  'EdgeColor', 'none');
        end
        labelColour = t.Ink;
    else
        label = 'Rest';
        labelColour = t.Muted;
    end
    y = 2.17;
    if step.Duration < 0.08 * plan.Duration
        nNarrow = nNarrow + 1;
        y = 2.08 + 0.25 * mod(nNarrow - 1, 2);
    end
    text(ax, (x0 + x1) / 2, y, label, 'HorizontalAlignment', 'center', 'FontSize', 9, ...
         'Color', labelColour, 'Interpreter', 'none', 'Clipping', 'on');
end
set(ax, 'XLim', [0, max(plan.Duration / 60, 1e-3)], 'YLim', [0 2.5], 'YTick', [0.5 1.5], ...
    'YTickLabel', {'B', 'A'});
xlabel(ax, 'Session time (min)');
