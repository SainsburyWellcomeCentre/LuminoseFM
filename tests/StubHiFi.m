classdef StubHiFi < lum.dev.HiFi
    % StubHiFi is a HiFi shim that reports itself available without a module.
    %
    % lum.dev.NullHiFi deliberately returns empty output actions, because a
    % session with no module has to run silently. That makes it the wrong double
    % for testing *which* sound a component chose: there is nothing to read back.
    % This stub keeps the availability flag true, so playAction returns the real
    % output action, while every transfer is only logged.
    %
    % See also: lum.dev.HiFi, lum.dev.NullHiFi, stateMachineTest

    methods
        function obj = StubHiFi(moduleName, samplingRate)
            obj@lum.dev.HiFi(moduleName, samplingRate, true);
        end
    end

    methods (Access = protected)
        function applyLoad(obj, slot, waveform, loopDuration)
            obj.note('stub load of slot %d (%d samples, loop %g s)', slot, size(waveform, 2), ...
                     loopDuration);
        end

        function applyPush(obj)
            obj.note('stub push');
        end
    end
end
