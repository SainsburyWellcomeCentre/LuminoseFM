function file = calibrationFile(path, folder)
% lum.led.calibrationFile is the file that holds the calibration of one light path.
%
%   file = lum.led.calibrationFile(lum.led.lightPath(S, k))
%
% One file per optical channel and cable: DoricLED_<channel>_<bundle>_<cable>.mat, for
% example DoricLED_A_4-to-19_orange.mat. Calibrating the same path again overwrites it.
%
% Arguments:
%   path    From lum.led.lightPath
%   folder  Optional; default lum.led.calibrationFolder
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.lightPath, lum.led.loadCalibration, lum.led.saveCalibration

if nargin < 2 || isempty(folder)
    folder = lum.led.calibrationFolder();
end
name = sprintf('DoricLED_%s_%s_%s.mat', path.Channel, clean(path.Bundle), clean(path.Cable));
file = fullfile(folder, name);


function text = clean(text)
% A name as a file name: spaces and anything unusual become hyphens.
text = regexprep(char(text), '[^A-Za-z0-9_-]+', '-');
