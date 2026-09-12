function drawTestPulseEpoch(ax, plan, step, t)
% lum.gui.drawTestPulseEpoch draws one epoch of a test-pulse step: the gates and the light.
%
% Channel A above B, time from the epoch's onset. Each gate Bpod sends is drawn faintly
% and the light PulsePal delivers in it solidly, so a probe shows its pulse or pair and
% a plasticity train its bursts and the pulses inside them (lum.sleep.epochShape). An
% alternating step's first epoch is on A; the next is the same on B.
%
% Arguments:
%   ax    Axes or uiaxes to draw into; cleared first
%   plan  From lum.sleep.testPulsePlan
%   step  Index of the step to show; one without light shows a note
%   t     lum.gui.theme
%
% See also: lum.sleep.epochShape, lum.gui.drawTestPulseSchedule, lum.gui.TestPulseDesigner

cla(ax);
hold(ax, 'on');
set(ax, 'Color', t.Panel, 'XColor', t.Muted, 'YColor', t.Muted, 'TickDir', 'out', 'Box', 'off');
if isempty(step) || step < 1 || step > numel(plan.Steps) || plan.Steps(step).nEpochs < 1
    text(ax, 0.5, 1, 'This step delivers no light', 'HorizontalAlignment', 'center', ...
         'Color', t.Muted);
    set(ax, 'XLim', [0 1], 'YLim', [0 2], 'YTick', []);
    title(ax, '', 'FontWeight', 'normal');
    return
end

shape = lum.sleep.epochShape(plan, step, 1);
if shape.Length < 1
    scale = 1000;
    unit = 'ms';
else
    scale = 1;
    unit = 's';
end
drawRows(ax, shape.Gates, scale, t, 0.25);
drawRows(ax, shape.Pulses, scale, t, 1);
set(ax, 'XLim', [-0.04, 1.04] * shape.Length * scale, 'YLim', [0 2], 'YTick', [0.5 1.5], ...
    'YTickLabel', {'B', 'A'});
xlabel(ax, sprintf('%s from the epoch''s onset', unit));
info = plan.Steps(step);
nChannels = numel(unique(shape.Gates(:, 3)));
switch info.Channels
    case 'A and B'
        where = 'on A and B together';
    case 'Alternate A and B'
        where = 'on A, the next epoch on B';
    otherwise
        where = ['on ' info.Channels];
end
if isempty(info.Train)
    what = sprintf('probe, %d pulse(s) of constant light %s', size(shape.Pulses, 1) / nChannels, where);
else
    what = sprintf('%s, %d burst(s) of %d pulse(s) %s', info.Kind, size(shape.Gates, 1) / nChannels, ...
                   info.Train.PulsesPerBurst, where);
end
title(ax, sprintf('Step %d, one epoch: %s', step, what), 'FontWeight', 'normal', 'FontSize', 10, ...
      'Color', t.Ink, 'Interpreter', 'none');


function drawRows(ax, rows, scale, t, alpha)
% One patch for every [onset duration channel] row, in lanes A (above) and B (below).
n = size(rows, 1);
if n == 0
    return
end
x0 = rows(:, 1) * scale;
x1 = (rows(:, 1) + rows(:, 2)) * scale;
onA = rows(:, 3) == 1;
y0 = 0.15 + onA;
y1 = y0 + 0.7;
vertices = zeros(4 * n, 2);
vertices(1:4:end, :) = [x0 y0];
vertices(2:4:end, :) = [x1 y0];
vertices(3:4:end, :) = [x1 y1];
vertices(4:4:end, :) = [x0 y1];
colours = repmat(t.ChannelB, n, 1);
colours(onA, :) = repmat(t.ChannelA, nnz(onA), 1);
patch(ax, 'Faces', reshape(1:4 * n, 4, n)', 'Vertices', vertices, 'FaceVertexCData', colours, ...
      'FaceColor', 'flat', 'FaceAlpha', alpha, 'EdgeColor', 'none');
