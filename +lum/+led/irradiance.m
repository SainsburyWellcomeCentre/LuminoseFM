function value = irradiance(cal, currentmA)
% lum.led.irradiance converts LED current into irradiance at the fiber tips.
%
%   mWmm2 = lum.led.irradiance(cal, mA)
%
% Linear interpolation between the calibration's points. A current outside the range
% measured has no calibrated irradiance: NaN, never an extrapolation. With cal empty
% (no calibration) every value is NaN.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.current, lum.led.makeCalibration

value = NaN(size(currentmA));
if isempty(cal)
    return
end
value = interp1(cal.CurrentmA, cal.IrradiancemWmm2, double(currentmA), 'linear', NaN);
