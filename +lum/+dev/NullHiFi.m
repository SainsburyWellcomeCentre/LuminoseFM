classdef NullHiFi < lum.dev.HiFi
    % lum.dev.NullHiFi is the HiFi shim for sessions with no module.
    %
    % Waveform validation still runs, so a sound that would be rejected on the rig
    % is rejected on a desk PC too; the transfer itself is only logged. Because
    % playAction() and stopAction() return empty output actions when the device is
    % unavailable, a state machine built for sound runs unchanged in emulator mode
    % — it simply produces silence.
    %
    % See also: lum.dev.HiFi, lum.dev.RealHiFi, lum.dev.open, TestHiFiSound

    methods
        function obj = NullHiFi(moduleName, samplingRate, reason)
            obj@lum.dev.HiFi(moduleName, samplingRate, false);
            obj.announce('not connected (%s); sound states will run silently', reason);
        end
    end

    methods (Access = protected)
        function applyLoad(obj, slot, waveform, loopDuration)
            obj.note('would load slot %d (%d x %d samples, loop %g s)', slot, size(waveform, 1), ...
                     size(waveform, 2), loopDuration);
        end

        function applyPush(obj)
            obj.note('would push sound set');
        end
    end
end
