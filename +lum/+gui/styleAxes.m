function styleAxes(ax, titleText, t)
% lum.gui.styleAxes gives a plot panel the look every LuminoseFM plot shares.
%
%   lum.gui.styleAxes(ax, 'Reaction time')
%   lum.gui.styleAxes(ax, 'Reaction time', lum.gui.theme())
%
% White panel; dark axes (theme Axis) with ticks out and no top or right edge, tick labels and
% axis labels in the same dark grey; faint horizontal gridlines only; the title in sentence
% case at the top left, in ink and regular weight; the type from lum.gui.theme's Font (one
% family, one scale: title 12, axis label 11, tick label 10 points). Holds the axes, so what is drawn next adds to them. A panel
% that wants vertical gridlines too (a plane) turns them on after this call.
%
% Used by the online figure (lum.OnlinePlots), the sleep figure (lum.sleep.Plots) and the
% summary plots (lum.report.summaryPlots), so the three read the same.
%
% See also: lum.gui.panelLegend, lum.gui.theme

if nargin < 3
    t = lum.gui.theme();
end
f = t.Font;
set(ax, 'Color', t.Panel, 'XColor', t.Axis, 'YColor', t.Axis, 'GridColor', t.Grid, ...
    'GridAlpha', 1, 'Box', 'off', 'TickDir', 'out', 'TickLength', [0.008 0.008], ...
    'FontName', f.Name, 'FontSize', f.Tick, 'LabelFontSizeMultiplier', f.Label / f.Tick, ...
    'TitleFontSizeMultiplier', f.Title / f.Tick, 'TitleFontWeight', 'normal', ...
    'LineWidth', 0.9, 'XGrid', 'off', 'YGrid', 'on', 'XMinorGrid', 'off', 'YMinorGrid', 'off');
ax.Title.String = titleText;
ax.Title.Color = t.Ink;
ax.TitleHorizontalAlignment = 'left';
hold(ax, 'on');
