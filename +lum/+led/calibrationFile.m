function file = calibrationFile(path, folder)
% lum.led.calibrationFile is the file that holds the calibration of one cable on one channel.
%
%   file = lum.led.calibrationFile(lum.led.lightPath(S, k))
%
% One file per bundle, cable and optical channel: DoricLED_<bundle>_<cable>_<A|B>.mat, for
% example DoricLED_4-to-19_orange_A.mat. The light leaving a cable depends on the LED
% channel and the commutator channel that feed it, so the orange cable on A and the orange
% cable on B are two calibrations. Calibrating the same cable on the same channel again
% overwrites it.
%
% Files from 0.7.2 to 0.9.0 were named per cable only (DoricLED_<bundle>_<cable>.mat);
% lum.led.loadCalibration still reads one for the channel it was measured on.
%
% Arguments:
%   path    From lum.led.lightPath (uses .Channel), or a calibration (uses .MeasuredOn)
%   folder  Optional; default lum.led.calibrationFolder
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.lightPath, lum.led.loadCalibration, lum.led.saveCalibration

if nargin < 2 || isempty(folder)
    folder = lum.led.calibrationFolder();
end
if isfield(path, 'Channel')
    channel = path.Channel;
else
    channel = path.MeasuredOn;
end
name = sprintf('DoricLED_%s_%s_%s.mat', clean(path.Bundle), clean(path.Cable), clean(channel));
file = fullfile(folder, name);


function text = clean(text)
% A name as a file name: spaces and anything unusual become hyphens.
text = regexprep(char(text), '[^A-Za-z0-9_-]+', '-');
