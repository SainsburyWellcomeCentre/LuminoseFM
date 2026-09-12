classdef RealPulsePal < lum.dev.PulsePal
    % lum.dev.RealPulsePal is the PulsePal shim that talks to the device.
    %
    % Constructed by lum.dev.openPulsePal when Bpod is not in emulator mode and the
    % session delivers light. The PulsePal MATLAB folder is not on the saved MATLAB path
    % on this rig, so the constructor adds it for the current session only — it never
    % calls savepath.
    %
    % The connection itself is PulsePal's own code, which keeps it in the global
    % PulsePalSystem. Two of its habits matter here:
    %   - PulsePal() only prints "Pulse Pal is already open" when a PulsePalSystem is
    %     left in the base workspace, even one whose port no longer answers, so the
    %     session would carry on with a dead connection.
    %   - Its port scan lists only ports nobody holds, so a connection left open by a
    %     session that did not release it cannot be found again.
    % So a connection already held is reused only if the device answers a handshake on
    % it; otherwise it is dropped, which releases the port, and PulsePal connects afresh.
    %
    % See also: lum.dev.PulsePal, lum.dev.NullPulsePal, lum.dev.openPulsePal

    properties (Constant)
        % Firmware 20 has a bug in gated trigger mode with both trigger inputs in use
        % (SetPulsePalVersion says so on connecting), and both are in use here.
        MinFirmware = 21
    end

    methods
        function obj = RealPulsePal(pulsePalRoot)
            % RealPulsePal(pulsePalRoot) connects to the device.
            %
            % pulsePalRoot is the PulsePal repository folder, e.g.
            % 'C:\Users\...\MATLAB\PulsePal'. Errors if the folder is missing, the
            % device cannot be reached, or its firmware is too old; lum.dev.openPulsePal
            % turns that into a refusal to start the session.
            obj@lum.dev.PulsePal(true);

            lum.dev.RealPulsePal.addToPath(pulsePalRoot);

            if ~lum.dev.RealPulsePal.answersHandshake()
                clear global PulsePalSystem  % Releases a dead connection's port
                PulsePal;  % Finds the device on a serial port and fills in PulsePalSystem
            end

            firmware = lum.dev.RealPulsePal.firmwareVersion();
            if isempty(firmware) || firmware < lum.dev.RealPulsePal.MinFirmware
                clear global PulsePalSystem
                error('lum:dev:RealPulsePal:badFirmware', ...
                      ['The device found did not identify itself as a Pulse Pal 2 with '...
                       'firmware v%d or later (it reported %s).'], ...
                      lum.dev.RealPulsePal.MinFirmware, mat2str(firmware));
            end
            obj.announce('connected, firmware v%d', firmware);
        end

        function close(obj)
            % close() disconnects from the device and releases the serial port.
            global PulsePalSystem %#ok<GVMIS>
            if isempty(PulsePalSystem)
                return
            end
            try
                EndPulsePal;
                obj.note('disconnected');
            catch closeError
                warning('lum:dev:RealPulsePal:closeFailed', ...
                        'Could not close PulsePal cleanly: %s', closeError.message);
                clear global PulsePalSystem  % Release the port all the same
            end
        end
    end

    methods (Access = protected)
        function send(obj, channel, paramCode, value)
            % send() writes one parameter to the device and checks the confirm byte.
            % A read that times out returns nothing, which must count as a failure.
            confirmed = ProgramPulsePalParam(channel, paramCode, value);
            if ~isequal(confirmed, 1)
                error('lum:dev:RealPulsePal:notConfirmed', ...
                      'PulsePal did not acknowledge parameter %d on channel %d.', ...
                      paramCode, channel);
            end
            obj.note('ch%d param %d = %g', channel, paramCode, value);
        end

        function sendStopOutput(obj, channel)
            % sendStopOutput() switches continuous playback off on one output, which
            % the firmware also takes as an order to stop what the output is playing.
            confirmed = SetContinuousPlay(channel, 0);
            if ~isequal(confirmed, 1)
                error('lum:dev:RealPulsePal:notConfirmed', ...
                      'PulsePal did not acknowledge stopping output %d.', channel);
            end
            obj.note('ch%d stopped, continuous playback off', channel);
        end

        function tf = handshake(obj) %#ok<MANU> % The connection lives in PulsePal's global
            % handshake() asks the device for its firmware version on the open port.
            tf = lum.dev.RealPulsePal.answersHandshake();
        end
    end

    methods (Static)
        function addToPath(pulsePalRoot)
            % addToPath() puts the PulsePal MATLAB folders on the path for this session.
            matlabFolder = fullfile(pulsePalRoot, 'MATLAB');
            if ~isfolder(matlabFolder)
                error('lum:dev:RealPulsePal:noFolder', ...
                      ['PulsePal MATLAB folder not found at %s. Clone the PulsePal '...
                       'repository next to Bpod_Gen2, or turn the light pattern off in '...
                       'the setup dialog.'], matlabFolder);
            end
            if exist('ProgramPulsePalParam', 'file') ~= 2
                addpath(genpath(matlabFolder));  % Session only; the saved path is left alone
            end
        end
    end

    methods (Static, Access = private)
        function tf = answersHandshake()
            % Whether a connection PulsePal's code already holds still reaches the device.
            global PulsePalSystem %#ok<GVMIS>
            tf = false;
            if ~isa(PulsePalSystem, 'PulsePalObject') || ~isvalid(PulsePalSystem) ...
                    || isempty(PulsePalSystem.SerialPort)
                return
            end
            try
                PulsePalSystem.FirmwareVersion = [];
                SetPulsePalVersion;  % Fills FirmwareVersion only if the device answers
                tf = ~isempty(PulsePalSystem.FirmwareVersion);
            catch
                tf = false;
            end
        end

        function version = firmwareVersion()
            % The firmware version the last handshake reported, or [] without one.
            global PulsePalSystem %#ok<GVMIS>
            version = [];
            if isa(PulsePalSystem, 'PulsePalObject') && isvalid(PulsePalSystem)
                version = double(PulsePalSystem.FirmwareVersion);
            end
        end
    end
end
