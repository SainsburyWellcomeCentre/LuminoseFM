function cals = calibrations(S, folder)
% lum.led.calibrations reads the calibrations of the cables on channels A and B.
%
%   cals = lum.led.calibrations(S)     % 1 x 2 cell, A then B: a calibration struct, or [] for none
%
% Each is the calibration of the cable on that channel (S.Light.Cables), whichever channel
% it was measured on (lum.led.calibrationFile).
%
% See also: lum.led.lightPath, lum.led.loadCalibration

if nargin < 2
    folder = '';
end
cals = cell(1, 2);
for k = 1:2
    cals{k} = lum.led.loadCalibration(lum.led.lightPath(S, k), folder);
end
