classdef NullHouseLight < lum.dev.HouseLight
    % lum.dev.NullHouseLight is the emulator's house light: PulsePal's shim, and the loopback emulated.
    %
    % The level goes to the session's PulsePal shim, whose log records it. There is no
    % wire from PulsePal into the emulated state machine, so a switch made while one runs
    % is put into it as the loopback input's edge — the event the console's BNC input
    % button sends — and the trial's events carry BNC1High / BNC1Low as on the rig.
    %
    % See also: lum.dev.HouseLight, lum.dev.RealHouseLight

    methods
        function obj = NullHouseLight(pulsePal, config, on, reason)
            obj@lum.dev.HouseLight(pulsePal, config, on, false);
            obj.announce('not driven (%s); switches are logged and put into the emulated state machine as %s', ...
                         reason, config.Input);
        end
    end

    methods (Access = protected)
        function echo(obj, on)
            % The emulator's own route for an input's edge (ManualOverride's 'V' message),
            % taken only while a state machine runs: between runs Bpod has nothing to
            % timestamp it with, as on the rig.
            global BpodSystem %#ok<GVMIS>
            try
                if BpodSystem.Status.InStateMatrix ~= 1
                    return
                end
                index = find(strcmp(BpodSystem.StateMachineInfo.InputChannelNames, obj.Input), 1);
                BpodSystem.HardwareState.InputState(index) = double(on);
                BpodSystem.VirtualManualOverrideBytes = ['V' index-1 double(on)];
                BpodSystem.ManualOverrideFlag = 1;
                obj.note('%s put into the emulated state machine', obj.Input);
            catch
                % No Bpod (a unit test): the log line is the record.
            end
        end
    end
end
