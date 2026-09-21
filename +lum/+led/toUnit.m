function [value, unit] = toUnit(cal, currentmA)
% lum.led.toUnit is an LED current as the windows show it: irradiance when calibrated.
%
%   [value, unit] = lum.led.toUnit(cal, mA)
%
% With a calibration, value is the irradiance in mW/mm2 (NaN outside the range measured)
% and unit 'mW/mm2'; without one, value is the current and unit 'mA'. Settings keep the
% current (S.Doric.CurrentmA), so a new calibration changes what the windows show, never
% what is stored.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.fromUnit, lum.led.describe, lum.led.irradiance

if isempty(cal)
    value = double(currentmA);
    unit = 'mA';
else
    value = lum.led.irradiance(cal, currentmA);
    unit = 'mW/mm2';
end
