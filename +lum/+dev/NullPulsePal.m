classdef NullPulsePal < lum.dev.PulsePal
    % lum.dev.NullPulsePal is the PulsePal shim for sessions with no device.
    %
    % Every parameter that would have been sent is recorded in the device log
    % instead, so an emulated session can be checked against a real one, and
    % the validation in lum.dev.PulsePal still runs — a waveform that would be
    % rejected on the rig is rejected on a desk PC too.
    %
    % See also: lum.dev.PulsePal, lum.dev.RealPulsePal, lum.dev.open

    methods
        function obj = NullPulsePal(reason)
            obj@lum.dev.PulsePal(false);
            obj.announce('not connected (%s); carrier waveform will be logged only', reason);
        end
    end

    methods (Access = protected)
        function send(obj, channel, paramCode, value)
            % send() records the parameter that a real device would have received.
            obj.note('would set ch%d param %d = %g', channel, paramCode, value);
        end
    end
end
