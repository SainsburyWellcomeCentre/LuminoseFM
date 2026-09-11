classdef RealHiFi < lum.dev.HiFi
    % lum.dev.RealHiFi is the HiFi shim that talks to the module.
    %
    % Constructed by lum.dev.open when the HiFi module is registered with the
    % state machine and paired with its USB serial port. The assertModule check
    % lives in lum.dev.open, not here: it errors in emulator mode.
    %
    % See also: lum.dev.HiFi, lum.dev.NullHiFi, lum.dev.open

    properties (Access = private)
        module  % BpodHiFi object
    end

    methods
        function obj = RealHiFi(moduleName, usbPort, samplingRate, attenuation_dB)
            obj@lum.dev.HiFi(moduleName, samplingRate, true);
            obj.module = BpodHiFi(usbPort);
            obj.module.SamplingRate = samplingRate;
            obj.module.DigitalAttenuation_dB = attenuation_dB;
            obj.announce('connected on %s, hardware v%s, firmware v%s', usbPort, ...
                         num2str(obj.module.Info.hardwareVersion), ...
                         num2str(obj.module.Info.firmwareVersion));
        end

        function close(obj)
            % close() stops playback and releases the module's serial port.
            try
                obj.module.stop;
            catch
                % Nothing useful to do if the module has already gone away
            end
            obj.module = [];
            obj.note('disconnected');
        end
    end

    methods (Access = protected)
        function applyLoad(obj, slot, waveform, loopDuration)
            if loopDuration > 0
                % BpodHiFi.load reads these by position: LoopMode, then LoopDuration.
                obj.module.load(slot, waveform, 'LoopMode', 1, 'LoopDuration', loopDuration);
            else
                obj.module.load(slot, waveform);
            end
        end

        function applyPush(obj)
            obj.module.push;
        end
    end
end
