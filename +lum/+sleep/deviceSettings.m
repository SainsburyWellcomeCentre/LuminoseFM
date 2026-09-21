function deviceSettings = deviceSettings(S)
% lum.sleep.deviceSettings is what a sleep or ePhys calibration session asks lum.dev.open for.
%
% Neither plays sound, so the HiFi module is never opened. A sleep session delivers light
% only when it sends test pulses; an ePhys calibration session always does (D18). PulsePal
% is opened either way, because it drives the house light, on exactly the terms a
% behaviour session opens it: lum.dev.openPulsePal refuses to start a session with light
% without it, and stops its outputs and checks that it answers first (D1, D13, D15).
%
% Arguments:
%   S  Settings struct; reads S.Session.Type, and S.Sleep or S.Ephys
%
% Returns S with S.Session.UseOpto set from the light the session sends, S.Session.UseSound
% off and S.Session.HouseLight from S.Sleep.HouseLight or S.Ephys.HouseLight.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.run, lum.dev.open, lum.dev.openPulsePal

deviceSettings = S;
deviceSettings.Session.UseSound = false;
if strcmp(S.Session.Type, 'EphysCalibration')
    deviceSettings.Session.UseOpto = true;
    deviceSettings.Session.HouseLight = logical(S.Ephys.HouseLight);
else
    deviceSettings.Session.UseOpto = logical(S.Sleep.TestPulses.Enabled);
    deviceSettings.Session.HouseLight = logical(S.Sleep.HouseLight);  % Where the house light starts
end
