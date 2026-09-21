function plotCalibration(ax, cal, t)
% lum.led.plotCalibration draws an LED calibration: current against irradiance.
%
% Current (mA) on the x axis and irradiance at the fiber tips (mW/mm2) on the y axis,
% the readings as points joined by the lines lum.led.irradiance interpolates along.
% Used by the calibration window as the readings are typed, and for the .png saved
% with each calibration. Works on axes and uiaxes.
%
% Arguments:
%   ax   Axes to draw into (cleared first)
%   cal  From lum.led.makeCalibration, or a struct with CurrentmA, IrradiancemWmm2,
%        MeasuredOn, MeasuredLEDChannel and the path fields (partial readings are
%        fine); [] draws empty axes
%   t    lum.gui.theme
%
% See also: lum.led.makeCalibration, lum.gui.DoricCalibration

cla(ax);
colours = {t.ChannelA, t.ChannelB};
colour = t.Ink;
titleText = 'No readings yet';
if ~isempty(cal) && isfield(cal, 'CurrentmA') && ~isempty(cal.CurrentmA)
    if isfield(cal, 'MeasuredLEDChannel')
        colour = colours{cal.MeasuredLEDChannel};
    end
    x = cal.CurrentmA(:);
    y = cal.IrradiancemWmm2(:);
    keep = ~isnan(x) & ~isnan(y);
    plot(ax, x(keep), y(keep), '-o', 'Color', colour, 'MarkerFaceColor', colour, 'LineWidth', 1.5);
    titleText = sprintf('%s cable (%s), %d fibers, %.4g mm^2, measured on channel %s', cal.Cable, ...
                        cal.Bundle, cal.nFibers, cal.Area, cal.MeasuredOn);
    if isfield(cal, 'Date') && ~isempty(cal.Date)
        titleText = sprintf('%s  |  %s', titleText, cal.Date);
    end
end
set(ax, 'Color', t.Panel, 'XColor', t.Muted, 'YColor', t.Muted, 'TickDir', 'out', 'Box', 'off');
grid(ax, 'on');
xlabel(ax, 'LED current (mA)');
ylabel(ax, 'Irradiance (mW/mm^2)');
title(ax, titleText, 'FontWeight', 'normal', 'FontSize', 10, 'Color', t.Ink);
