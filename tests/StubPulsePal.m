classdef StubPulsePal < lum.dev.PulsePal
    % StubPulsePal is a PulsePal shim that reports itself connected, with no device.
    %
    % lum.dev.NullPulsePal always answers a handshake and says it is not connected,
    % which is right for the emulator and wrong for testing what a session does with a
    % device that has stopped answering. This stub is available, logs every transfer,
    % and answers handshakes only while Answers is true, so a test can take the device
    % away part way through.
    %
    % See also: lum.dev.PulsePal, lum.dev.NullPulsePal, pulsePalTest

    properties
        Answers = true   % Whether the next handshake is answered
    end

    methods
        function obj = StubPulsePal(answers)
            obj@lum.dev.PulsePal(true);
            if nargin >= 1
                obj.Answers = answers;
            end
        end
    end

    methods (Access = protected)
        function send(obj, channel, paramCode, value)
            obj.note('stub set ch%d param %d = %g', channel, paramCode, value);
        end

        function sendStopOutput(obj, channel)
            obj.note('stub stop ch%d', channel);
        end

        function tf = handshake(obj)
            tf = obj.Answers;
        end
    end
end
