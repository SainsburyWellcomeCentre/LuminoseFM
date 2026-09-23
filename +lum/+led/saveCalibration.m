function [file, imageFile] = saveCalibration(cal, folder)
% lum.led.saveCalibration writes an LED calibration, replacing any earlier one of that cable on that channel.
%
%   [file, imageFile] = lum.led.saveCalibration(cal)
%
% The calibration goes to lum.led.calibrationFile (variable Calibration), and its graph,
% current against irradiance, beside it as a .png of the same name. The folder is created
% if it is missing. Every later session, of any type, with the same cable on the same channel
% reads it (lum.led.loadCalibration).
%
% Arguments:
%   cal     From lum.led.makeCalibration
%   folder  Optional; default lum.led.calibrationFolder
%
% Returns the two file names; imageFile is '' when the graph could not be written (the
% calibration itself is saved regardless).
%
% See also: lum.led.makeCalibration, lum.led.loadCalibration, lum.led.plotCalibration

if nargin < 2 || isempty(folder)
    folder = lum.led.calibrationFolder();
end
if ~isfolder(folder)
    mkdir(folder);
end
file = lum.led.calibrationFile(cal, folder);
Calibration = cal;  % Saved under this name
save(file, 'Calibration');

imageFile = regexprep(file, '\.mat$', '.png');
figureHandle = [];
try
    figureHandle = figure('Visible', 'off', 'Color', 'w', 'Position', [100 100 640 440]);
    lum.led.plotCalibration(axes(figureHandle), cal, lum.gui.theme());
    exportgraphics(figureHandle, imageFile, 'Resolution', 120);
catch
    imageFile = '';
end
if ~isempty(figureHandle) && isvalid(figureHandle)
    delete(figureHandle);
end
