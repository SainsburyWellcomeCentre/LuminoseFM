function mA = fromUnit(cal, value)
% lum.led.fromUnit is the LED current for a value typed in a window's unit.
%
%   mA = lum.led.fromUnit(cal, value)
%
% With a calibration the value is irradiance in mW/mm2, converted by lum.led.current
% (refused outside the range measured); without one it is the current in mA. Either way
% the result is whole mA, which is what the driver takes.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.toUnit, lum.led.current

if isempty(cal)
    mA = round(double(value));
else
    mA = lum.led.current(cal, value);
end
