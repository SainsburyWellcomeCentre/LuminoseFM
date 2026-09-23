function cal = loadCalibration(path, folder)
% lum.led.loadCalibration reads the calibration of a light path, or [] when there is none.
%
%   cal = lum.led.loadCalibration(lum.led.lightPath(S, k))
%
% The calibration of the path's cable measured on the path's channel
% (lum.led.calibrationFile). When there is none, a per-cable file from 0.7.2-0.9.0
% (DoricLED_<bundle>_<cable>.mat) is used if it was measured on this channel, and not
% otherwise. No calibration is not an error: the channel's intensity is then in mA.
%
% A file that cannot be read, or that belongs to another cable or channel, counts as none,
% with a warning ('lum:led:loadCalibration:unreadable'), so a damaged file never stops a
% session; the channel is then in mA until it is calibrated again.
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
legacy = false;
if ~isfile(file)
    file = regexprep(file, '_[^_]+\.mat$', '.mat');   % The per-cable name of 0.7.2-0.9.0
    legacy = true;
    if ~isfile(file)
        return
    end
end
try
    loaded = load(file, 'Calibration');
    candidate = loaded.Calibration;
    if ~strcmp(candidate.Cable, path.Cable) || ~strcmp(candidate.Bundle, path.Bundle) ...
            || numel(candidate.CurrentmA) < 2
        error('lum:led:loadCalibration:otherPath', 'it describes another cable');
    end
    if ~strcmp(candidate.MeasuredOn, path.Channel)
        if legacy
            return   % Measured on the other channel: it says nothing about this one
        end
        error('lum:led:loadCalibration:otherPath', 'it was measured on channel %s', candidate.MeasuredOn);
    end
    cal = candidate;
catch readError
    warning('lum:led:loadCalibration:unreadable', ...
            ['The LED calibration %s could not be used (%s); the %s cable on channel %s is in mA '...
             'until it is calibrated again.'], file, readError.message, path.Cable, path.Channel);
end
