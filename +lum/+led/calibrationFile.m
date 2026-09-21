function file = calibrationFile(path, folder)
% lum.led.calibrationFile is the file that holds the calibration of one cable.
%
%   file = lum.led.calibrationFile(lum.led.lightPath(S, k))
%
% One file per bundle and cable, whichever channel it is on: DoricLED_<bundle>_<cable>.mat,
% for example DoricLED_4-to-19_orange.mat. The two LED channels are taken to give equal
% power at equal current, so a cable calibrated on channel A holds on channel B too, and
% moving a cable to the other channel at the commutator needs no new calibration.
% Calibrating the same cable again overwrites it.
%
% Arguments:
%   path    From lum.led.lightPath, or a calibration (anything with Bundle and Cable)
%   folder  Optional; default lum.led.calibrationFolder
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.lightPath, lum.led.loadCalibration, lum.led.saveCalibration

if nargin < 2 || isempty(folder)
    folder = lum.led.calibrationFolder();
end
name = sprintf('DoricLED_%s_%s.mat', clean(path.Bundle), clean(path.Cable));
file = fullfile(folder, name);


function text = clean(text)
% A name as a file name: spaces and anything unusual become hyphens.
text = regexprep(char(text), '[^A-Za-z0-9_-]+', '-');
