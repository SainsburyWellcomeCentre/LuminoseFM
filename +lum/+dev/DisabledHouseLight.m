classdef DisabledHouseLight < lum.dev.HouseLight
    % lum.dev.DisabledHouseLight is a house light nothing drives: off for the whole session.
    %
    % A session without light does not need PulsePal for channels A and B, so on the rig it
    % runs when PulsePal cannot be connected, or does not take the house light's level —
    % without the house light (lum.dev.openHouseLight). The light stays off, set() changes
    % nothing, and the windows grey their House light box out. Data.HouseLight is 0 for every
    % trial or block, Session.HouseLight.Switchable is false, and the level the settings
    % asked for is kept in the settings file for the next session.
    %
    % See also: lum.dev.HouseLight, lum.dev.openHouseLight, lum.gui.houseLightSwitch

    methods
        function obj = DisabledHouseLight(config, reason)
            obj@lum.dev.HouseLight([], config, false, false);
            obj.announce('cannot be switched in this session (%s); it stays off', reason);
        end
    end
end
