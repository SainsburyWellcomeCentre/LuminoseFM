classdef RealPulsePal < lum.dev.PulsePal
    % lum.dev.RealPulsePal is the PulsePal shim that talks to the device.
    %
    % Constructed by lum.dev.open when Bpod is not in emulator mode and a PulsePal
    % is reachable. The PulsePal MATLAB folder is not on the saved MATLAB path on
    % this rig, so the constructor adds it for the current session only — it never
    % calls savepath.
    %
    % See also: lum.dev.PulsePal, lum.dev.NullPulsePal, lum.dev.open

    methods
        function obj = RealPulsePal(pulsePalRoot)
            % RealPulsePal(pulsePalRoot) connects to the device.
            %
            % pulsePalRoot is the PulsePal repository folder, e.g.
            % 'C:\Users\...\MATLAB\PulsePal'. Errors if the folder is missing or the
            % device cannot be reached; lum.dev.open catches that and falls back to
            % the null shim.
            obj@lum.dev.PulsePal(true);

            lum.dev.RealPulsePal.addToPath(pulsePalRoot);

            global PulsePalSystem %#ok<GVMIS> % PulsePal's own connection handle

            if isempty(PulsePalSystem) || ~isfield(PulsePalSystem, 'SerialPort') ...
                    || isempty(PulsePalSystem.SerialPort)
                PulsePal;  % Opens the port and populates PulsePalSystem
            end
            obj.announce('connected, firmware v%s', num2str(PulsePalSystem.FirmwareVersion));
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
            end
        end
    end

    methods (Access = protected)
        function send(obj, channel, paramCode, value)
            % send() writes one parameter to the device and checks the confirm byte.
            confirmed = ProgramPulsePalParam(channel, paramCode, value);
            if confirmed ~= 1
                error('lum:dev:RealPulsePal:notConfirmed', ...
                      'PulsePal did not acknowledge parameter %d on channel %d.', ...
                      paramCode, channel);
            end
            obj.note('ch%d param %d = %g', channel, paramCode, value);
        end
    end

    methods (Static)
        function addToPath(pulsePalRoot)
            % addToPath() puts the PulsePal MATLAB folders on the path for this session.
            matlabFolder = fullfile(pulsePalRoot, 'MATLAB');
            if ~isfolder(matlabFolder)
                error('lum:dev:RealPulsePal:noFolder', ...
                      ['PulsePal MATLAB folder not found at %s. Clone the PulsePal '...
                       'repository next to Bpod_Gen2, or turn the optogenetic '...
                       'stimulus off in the setup dialog.'], matlabFolder);
            end
            if exist('ProgramPulsePalParam', 'file') ~= 2
                addpath(genpath(matlabFolder));  % Session only; the saved path is left alone
            end
        end
    end
end
