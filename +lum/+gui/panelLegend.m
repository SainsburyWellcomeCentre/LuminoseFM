function key = panelLegend(ax, handles, labels, t)
% lum.gui.panelLegend gives a plot panel its key: one row under its axis label.
%
%   lum.gui.panelLegend(ax, [h1 h2], {'correct', 'incorrect'})
%
% Under the panel, where it covers no data and leaves the title where every panel has it;
% no box; dark text at the theme's legend size. Every key in the online, sleep and summary
% plots goes through here.
%
% See also lum.gui.styleAxes, lum.gui.theme

if nargin < 4
    t = lum.gui.theme();
end
key = legend(ax, handles, labels, 'Location', 'southoutside', 'Orientation', 'horizontal', ...
             'Box', 'off', 'TextColor', t.Axis, 'FontName', t.Font.Name, ...
             'FontSize', t.Font.Legend, 'AutoUpdate', 'off', 'Interpreter', 'tex');
