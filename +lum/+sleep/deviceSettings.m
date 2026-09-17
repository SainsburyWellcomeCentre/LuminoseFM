function deviceSettings = deviceSettings(S)
% lum.sleep.deviceSettings is what a sleep session asks lum.dev.open for.
%
% A sleep session plays no sound, so the HiFi module is never opened. It delivers light
% only when it sends test pulses. PulsePal is opened either way, because it drives the
% house light, on exactly the terms a behaviour session opens it: lum.dev.openPulsePal
% refuses to start without it and stops its outputs and checks that it answers first
% (D1, D13, D15).
%
% Arguments:
%   S  Settings struct; reads S.Sleep.TestPulses.Enabled
%
% Returns S with S.Session.UseOpto set from the test pulses, S.Session.UseSound off and
% S.Session.HouseLight from S.Sleep.HouseLight.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.run, lum.dev.open, lum.dev.openPulsePal

deviceSettings = S;
deviceSettings.Session.UseOpto = logical(S.Sleep.TestPulses.Enabled);
deviceSettings.Session.UseSound = false;
deviceSettings.Session.HouseLight = logical(S.Sleep.HouseLight);  % Where the house light starts
