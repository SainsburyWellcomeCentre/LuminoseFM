function houseLight = openHouseLight(emulated, config, S, pulsePal)
% lum.dev.openHouseLight gives a session its house light, or a disabled one.
%
% The house light is PulsePal's output 3 (D15). A session that delivers light has already
% refused to start without PulsePal (lum.dev.openPulsePal); one without light has not, so
% for it PulsePal may be the null shim, and the house light is then
% lum.dev.DisabledHouseLight: off, with its switch greyed out. The same happens when a
% connected PulsePal does not take the light's starting level — in a session without light
% only; a session with light is refused, since that PulsePal is not fit to fill A and B
% either. The emulator gets lum.dev.NullHouseLight.
%
% Arguments:
%   emulated  True under Bpod('EMU'), as lum.dev.open found it
%   config    rig.HouseLight
%   S         Settings; S.Session.HouseLight is where the light starts, S.Session.UseOpto
%             whether the session delivers light
%   pulsePal  The session's lum.dev.PulsePal, from lum.dev.openPulsePal
%
% Warns with 'lum:dev:openHouseLight:disabled' when a rig session runs without the house
% light, and errors with 'lum:dev:HouseLight:notHeld' when a session with light cannot have it.
%
% See also: lum.dev.open, lum.dev.openPulsePal, lum.dev.HouseLight, lum.dev.DisabledHouseLight

if emulated
    houseLight = lum.dev.NullHouseLight(pulsePal, config, S.Session.HouseLight, 'emulator mode');
    return
end
if ~pulsePal.Available
    houseLight = disabled(config, S, 'PulsePal is not connected');
    return
end
try
    houseLight = lum.dev.RealHouseLight(pulsePal, config, S.Session.HouseLight);
catch houseLightError
    if S.Session.UseOpto
        rethrow(houseLightError);
    end
    houseLight = disabled(config, S, houseLightError.message);
end


function houseLight = disabled(config, S, reason)
% The light nothing drives, and a warning the operator cannot miss.
houseLight = lum.dev.DisabledHouseLight(config, reason);
wanted = '';
if S.Session.HouseLight
    wanted = ' The settings asked for it on; it is off.';
end
warning('lum:dev:openHouseLight:disabled', ...
        ['This session runs without the house light (%s): it stays off and its switch is '...
         'disabled.%s Connect PulsePal and restart the session to have it.'], reason, wanted);
