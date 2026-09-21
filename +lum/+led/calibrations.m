function cals = calibrations(S, folder)
% lum.led.calibrations reads the calibration of channel A's and channel B's light paths.
%
%   cals = lum.led.calibrations(S)     % 1 x 2 cell: a calibration struct, or [] for none
%
% See also: lum.led.lightPath, lum.led.loadCalibration

if nargin < 2
    folder = '';
end
cals = cell(1, 2);
for k = 1:2
    cals{k} = lum.led.loadCalibration(lum.led.lightPath(S, k), folder);
end
