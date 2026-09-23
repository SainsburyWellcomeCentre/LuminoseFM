function S = keepIntensity(S, type, cals, startmA, endmA)
% lum.led.keepIntensity writes an intensity changed during a session back into the settings.
%
%   S = lum.led.keepIntensity(S, 'Behaviour', cals, run.CurrentmA, devices.doricLED.CurrentmA)
%
% Used by both teardowns before the settings file is written (D16), so the next session
% starts where the operator left the LED window. Only a channel whose current changed is
% written: on a calibrated channel as the irradiance it gave (to 0.01 mW/mm2), otherwise
% as mA. A channel left alone keeps what was asked for, so a target the channel could not
% reach is not replaced by what it reached.
%
% Arguments:
%   S        Settings
%   type     Session type (lum.led.intensitySetting); ePhys writes nothing
%   cals     1 x 2 cell of calibrations, as the session used them
%   startmA  1 x 2, the currents the session started at (lum.led.intensity)
%   endmA    1 x 2, the currents at the end (NaN when unknown)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.intensity, lum.led.intensitySetting

irradiance = [NaN NaN];
currents = [NaN NaN];
for k = 1:2
    if isnan(endmA(k)) || endmA(k) == startmA(k)
        continue
    end
    value = lum.led.irradiance(cals{k}, endmA(k));
    if isnan(value)
        currents(k) = endmA(k);
    else
        irradiance(k) = round(value * 100) / 100;
    end
end
S = lum.led.intensitySetting(S, type, irradiance, currents);
