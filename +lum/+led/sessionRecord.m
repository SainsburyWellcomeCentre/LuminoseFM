function record = sessionRecord(S, led, cals, run)
% lum.led.sessionRecord is Data.Session.DoricLED: the light's intensity as the session ran it.
%
%   Data.Session.DoricLED = lum.led.sessionRecord(S, devices.doricLED, cals, ledIntensity)
%
% Written once, at teardown, by every session type (D17). Small: the LED's own record, the
% two light paths and their calibrations. What each trial or gate ran at is in the per-trial
% series (behaviour: LEDCurrentA, LEDCurrentB) or in LightSegments.CurrentmA (sleep and
% ePhys calibration); lum.led.irradiance(Data.Session.DoricLED.Calibrations{k}, mA) turns
% a current into irradiance.
%
% Returns a struct:
%   .Controlled     True when the session set the LED (Mode 'Device' or 'Simulated')
%   .Mode, .Reason  From lum.dev.DoricLED ('Manual' when set by hand)
%   .Settings       S.Doric as the session started
%   .LightPaths     1 x 2 struct from lum.led.lightPath: channel, cable, fibers, area
%   .Calibrations   1 x 2 cell, A then B: the calibration of the cable on each channel,
%                   measured on that channel, or [], as used
%   .Intensity      lum.led.intensity: what each channel was asked for (mW/mm2 or mA)
%                   and the current it started at; [] when not given
%   .Device         lum.dev.DoricLED.record(): currents, limits, every change, and the
%                   package's record of what the driver acknowledged
%
% See also: lum.dev.DoricLED, lum.led.lightPath, lum.led.calibrations

if nargin < 4
    run = [];
end
paths = [lum.led.lightPath(S, 1), lum.led.lightPath(S, 2)];
record = struct('Controlled', led.isControlled(), 'Mode', led.Mode, 'Reason', led.Reason, ...
                'Settings', S.Doric, 'LightPaths', paths, 'Calibrations', {cals}, ...
                'Intensity', run, 'Device', led.record());
