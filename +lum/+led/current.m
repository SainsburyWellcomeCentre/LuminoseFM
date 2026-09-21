function mA = current(cal, irradiance)
% lum.led.current converts irradiance at the fiber tips into the LED current that gives it.
%
%   mA = lum.led.current(cal, mWmm2)
%
% The inverse of lum.led.irradiance, by linear interpolation, rounded to whole mA (the
% driver takes whole mA). Where the calibration has several currents at one irradiance,
% the lowest is used. An irradiance outside the range measured is refused
% ('lum:led:current:outOfRange'), naming the range, rather than extrapolated.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.irradiance, lum.led.makeCalibration

if isempty(cal)
    error('lum:led:current:noCalibration', 'This light path has no calibration; give the current in mA.');
end
[levels, first] = unique(cal.IrradiancemWmm2, 'first');
currents = cal.CurrentmA(first);
irradiance = double(irradiance);
low = levels(1);
high = levels(end);
if any(irradiance(:) < low - 1e-12 | irradiance(:) > high + 1e-12 | isnan(irradiance(:)))
    error('lum:led:current:outOfRange', ...
          ['The %s cable is calibrated from %.4g to %.4g mW/mm2; %s is outside '...
           'that range. Calibrate further, or ask for less.'], cal.Cable, low, high, ...
          strjoin(arrayfun(@(v) sprintf('%.4g', v), irradiance(:)', 'UniformOutput', false), ', '));
end
mA = round(interp1(levels, currents, min(max(irradiance, low), high), 'linear'));
