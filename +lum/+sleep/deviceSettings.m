function deviceSettings = deviceSettings(S)
% lum.sleep.deviceSettings is what a sleep session asks lum.dev.open for.
%
% A sleep session plays no sound, so the HiFi module is never opened. It delivers light
% only when it sends test pulses, and then it needs PulsePal on exactly the terms a
% behaviour session does: lum.dev.openPulsePal refuses to start without it and stops
% its outputs and checks that it answers first (D1, D13).
%
% Arguments:
%   S  Settings struct; reads S.Sleep.TestPulses.Enabled
%
% Returns S with S.Session.UseOpto set from the test pulses and S.Session.UseSound off.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.run, lum.dev.open, lum.dev.openPulsePal

deviceSettings = S;
deviceSettings.Session.UseOpto = logical(S.Sleep.TestPulses.Enabled);
deviceSettings.Session.UseSound = false;
