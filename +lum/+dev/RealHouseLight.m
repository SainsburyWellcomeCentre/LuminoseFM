classdef RealHouseLight < lum.dev.HouseLight
    % lum.dev.RealHouseLight is the rig's house light: PulsePal output 3, looped back into BNC1.
    %
    % The switch itself is PulsePal's (lum.dev.HouseLight); the loopback is a wire, so a
    % switch reaches the running state machine's events with nothing sent to Bpod. The
    % constructor checks that the loopback input exists and is enabled in the console's
    % port settings, and says so when it is not: the light still switches, but the
    % switches are then on the camera clock only.
    %
    % See also: lum.dev.HouseLight, lum.dev.NullHouseLight, RigConfig

    methods
        function obj = RealHouseLight(pulsePal, config, on)
            obj@lum.dev.HouseLight(pulsePal, config, on, true);
            global BpodSystem %#ok<GVMIS>
            index = find(strcmp(BpodSystem.StateMachineInfo.InputChannelNames, config.Input), 1);
            if isempty(index)
                obj.announce(['the state machine has no input %s, so switches will not be timed '...
                              'on Bpod''s clock'], config.Input);
            elseif numel(BpodSystem.InputsEnabled) >= index && BpodSystem.InputsEnabled(index) ~= 1
                obj.announce(['input %s is disabled, so switches will not reach the trial events. '...
                              'Enable it in the Bpod console''s port settings'], config.Input);
            end
        end
    end
end
