classdef NullFlex < lum.dev.Flex
    % lum.dev.NullFlex is the Flex I/O shim for a state machine with no Flex channels.
    %
    % This is what emulator mode gets: Bpod('EMU') presents a Bpod r0.7-1.0, which
    % has no Flex I/O, so there is no flow-meter stream and no sync TTL. Both
    % hasAnalog() and hasSync() are false, and every caller degrades to a state
    % machine without them rather than erroring.
    %
    % See also: lum.dev.Flex, lum.dev.RealFlex, lum.dev.open

    methods
        function obj = NullFlex(reason)
            obj@lum.dev.Flex([], NaN, '', false);
            obj.announce('not available (%s); no flow meter stream and no sync TTL', reason);
        end
    end
end
