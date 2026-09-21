function text = describe(cal, currentmA)
% lum.led.describe says what an LED current delivers, in words for the windows and console.
%
%   lum.led.describe(cal, 120)   % '120 mA = 4.21 mW/mm2', or '120 mA (not calibrated)'
%
% NaN current (the driver set by hand) reads 'set on the driver'. A current outside the
% range calibrated says so.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.toUnit, lum.led.irradiance

if isnan(currentmA)
    text = 'set on the driver';
elseif isempty(cal)
    text = sprintf('%g mA (not calibrated)', currentmA);
else
    value = lum.led.irradiance(cal, currentmA);
    if isnan(value)
        text = sprintf('%g mA (outside the calibration, %g-%g mA)', currentmA, cal.CurrentmA(1), ...
                       cal.CurrentmA(end));
    else
        text = sprintf('%g mA = %.3g mW/mm2', currentmA, value);
    end
end
