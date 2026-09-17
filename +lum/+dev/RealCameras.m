classdef RealCameras < lum.dev.Cameras
    % lum.dev.RealCameras records through a connected spincam.CameraManager.
    %
    % Constructed by lum.dev.openCameras once the cameras are connected and set up
    % (lum.dev.configureCameras). The manager may use real cameras ('spinnaker') or
    % spincam's simulated ones ('mock', in the emulator); both run the same native
    % engine, so an emulated session writes real, synthetic, video files.
    %
    % Nothing here runs per frame. Per trial there is one mark (a host-clock read and a
    % line in the events file); the camera window reads preview frames on its own timer.
    %
    % See also: lum.dev.Cameras, lum.dev.openCameras, lum.gui.CameraWindow

    properties (SetAccess = private)
        Connected   % Struct array from lum.dev.configureCameras: Serial, Name, Row
    end

    properties (Access = private)
        manager     % spincam.CameraManager
    end

    methods
        function obj = RealCameras(manager, settings, spinCamFolder, connected)
            obj@lum.dev.Cameras(strcmp(manager.Backend, 'spinnaker'), manager.Backend, settings);
            obj.manager = manager;
            obj.SpinCamFolder = spinCamFolder;
            obj.Connected = connected;
            described = arrayfun(@(c) sprintf('%s %s', c.Name, c.Serial), connected, ...
                                 'UniformOutput', false);
            if strcmp(manager.Backend, 'mock')
                obj.announce('simulated cameras (emulator mode): %s', strjoin(described, ', '));
            else
                obj.announce('connected: %s, %g Hz, %s', strjoin(described, ', '), ...
                             settings.FrameRate, settings.Format);
            end
        end

        function [frames, info] = latestFrames(obj)
            [frames, ~] = obj.manager.getLatestFrames();
            info = struct('Name', {obj.manager.Cameras.Name}, 'Serial', {obj.manager.Cameras.Serial});
        end

        function stats = statistics(obj)
            T = obj.manager.getStats();
            n = height(T);
            stats = struct('Name', T.Name', 'Serial', T.Serial', 'FPS', num2cell(T.FPS'), ...
                           'FramesReceived', num2cell(T.FramesReceived'), ...
                           'FramesMissed', num2cell(T.FramesMissed'), ...
                           'FramesWritten', num2cell(T.FramesWritten'), ...
                           'WriterDrops', num2cell(T.WriterDrops'), ...
                           'QueueDepth', num2cell(T.QueueDepth'), 'LastTTL', num2cell(T.LastTTL'), ...
                           'Faulted', num2cell(T.Faulted'), 'LastError', T.LastError');
            stats = reshape(stats, 1, n);
        end

        function tf = canPreview(obj)
            tf = ~isempty(obj.manager) && obj.manager.PreviewMaxHz > 0;
        end

        function close(obj)
            % close() finishes any recording and releases the cameras.
            if isempty(obj.manager)
                return
            end
            try
                obj.stopRecording();
            catch stopError
                warning('lum:dev:RealCameras:stopFailed', 'Stopping the recording failed: %s', ...
                        stopError.message);
            end
            try
                delete(obj.manager);
            catch closeError
                warning('lum:dev:RealCameras:closeFailed', 'Releasing the cameras failed: %s', ...
                        closeError.message);
            end
            obj.manager = [];
            obj.note('released');
        end
    end

    methods (Access = protected)
        function plan = applyStart(obj, folder, base)
            started = obj.manager.startRecording(folder, base);
            cameras = struct('Serial', {started.Cameras.Serial}, 'Name', {started.Cameras.Name}, ...
                             'VideoFile', {started.Cameras.VideoFile}, ...
                             'CsvFile', {started.Cameras.CsvFile});
            plan = struct('Folder', started.Folder, 'BaseName', started.BaseName, ...
                          'StartTime', started.StartTime, 'Format', started.Format, ...
                          'EventsFile', started.EventsFile, 'SessionFile', started.SessionFile, ...
                          'StartHostTime', obj.manager.hostTime(), 'Cameras', cameras);
            obj.manager.logEvent('LuminoseFM', base);
        end

        function summary = applyStop(obj)
            stopped = obj.manager.stopRecording();
            cameras = stopped.Cameras;
            keep = {'Serial', 'Name', 'VideoFiles', 'CsvFile', 'FramesLogged', 'FramesWritten', ...
                    'FramesMissed', 'WriterDrops', 'FramesIncomplete', 'QueuePeak', 'Error'};
            cameras = rmfield(cameras, setdiff(fieldnames(cameras), keep));
            summary = struct('Duration_s', stopped.Duration_s, 'Cameras', cameras);
            for k = 1:numel(cameras)
                if ~isempty(cameras(k).Error)
                    warning('lum:dev:RealCameras:recordingError', 'Camera %s (%s): %s', ...
                            cameras(k).Name, cameras(k).Serial, cameras(k).Error);
                end
            end
        end

        function hostTime = applyMark(obj, event, value)
            hostTime = obj.manager.hostTime();
            obj.manager.logEvent(event, value);
        end

        function tf = canRecord(obj)
            tf = strcmp(obj.manager.State, 'recording');
        end

        function version = spinCamVersion(obj) %#ok<MANU> % spincam is on the path once cameras are open
            version = spincam.version();
        end

        function version = engineVersion(obj)
            % The native engine that grabs and encodes carries its own version.
            version = '';
            if isempty(obj.manager) || ~isa(obj.manager, 'spincam.CameraManager')
                return
            end
            try
                version = char(SpinCam.Engine.Version);
            catch
                % Engine not loaded; the record says so by leaving it empty.
            end
        end
    end
end
