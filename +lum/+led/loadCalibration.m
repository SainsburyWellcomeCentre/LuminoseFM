function cal = loadCalibration(path, folder)
% lum.led.loadCalibration reads the calibration of a light path's cable, or [] when there is none.
%
%   cal = lum.led.loadCalibration(lum.led.lightPath(S, k))
%
% The calibration is the cable's, whichever channel it was measured on
% (lum.led.calibrationFile). A file that cannot be read, or that belongs to another
% cable, counts as none, with a
% warning ('lum:led:loadCalibration:unreadable'), so a damaged file never stops a session;
% intensities are then in mA until the path is calibrated again.
%
% Arguments:
%   path    From lum.led.lightPath
%   folder  Optional; default lum.led.calibrationFolder
%
% See also: lum.led.saveCalibration, lum.led.calibrations, lum.led.irradiance

if nargin < 2 || isempty(folder)
    folder = lum.led.calibrationFolder();
end
cal = [];
file = lum.led.calibrationFile(path, folder);
if ~isfile(file)
    return
end
try
    loaded = load(file, 'Calibration');
    candidate = loaded.Calibration;
    if ~strcmp(candidate.Cable, path.Cable) || ~strcmp(candidate.Bundle, path.Bundle) ...
            || numel(candidate.CurrentmA) < 2
        error('lum:led:loadCalibration:otherPath', 'it describes another cable');
    end
    cal = candidate;
catch readError
    warning('lum:led:loadCalibration:unreadable', ...
            'The LED calibration %s could not be used (%s); the %s cable is in mA until it is calibrated again.', ...
            file, readError.message, path.Cable);
end
