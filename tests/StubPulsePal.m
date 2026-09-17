classdef StubPulsePal < lum.dev.PulsePal
    % StubPulsePal is a PulsePal shim that reports itself connected, with no device.
    %
    % lum.dev.NullPulsePal always answers a handshake and says it is not connected,
    % which is right for the emulator and wrong for testing what a session does with a
    % device that has stopped answering. This stub is available, logs every transfer,
    % and answers handshakes only while Answers is true, so a test can take the device
    % away part way through.
    %
    % DuringHandshake, when set, is called in the middle of the handshake, where the real
    % one pauses and MATLAB would run a click's callback; RefuseParams makes every
    % parameter fail, as a device that stopped confirming them would.
    %
    % See also: lum.dev.PulsePal, lum.dev.NullPulsePal, pulsePalTest

    properties
        Answers = true          % Whether the next handshake is answered
        DuringHandshake = []    % Function called inside the handshake, or []
        RefuseParams = false    % Whether sending a parameter fails
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
            if obj.RefuseParams
                error('StubPulsePal:refused', 'PulsePal did not acknowledge parameter %d on channel %d.', ...
                      paramCode, channel);
            end
            obj.note('stub set ch%d param %d = %g', channel, paramCode, value);
        end

        function sendStopOutput(obj, channel)
            obj.note('stub stop ch%d', channel);
        end

        function tf = handshake(obj)
            if ~isempty(obj.DuringHandshake)
                callback = obj.DuringHandshake;
                obj.DuringHandshake = [];
                callback();
            end
            obj.note('stub handshake');
            tf = obj.Answers;
        end
    end
end
