classdef StubCameraManager < handle
    % StubCameraManager stands in for spincam.CameraManager, with no cameras and no spincam.
    %
    % It has the part of spincam's interface LuminoseFM uses, records every call, and
    % "attaches" the serial numbers it is given, so lum.dev.configureCameras and
    % lum.dev.RealCameras can be tested on any machine.
    %
    % See also: lum.dev.configureCameras, lum.dev.RealCameras, cameraTest

    properties
        DefaultFrameRate = 100
        AppendDateTime = true
        PreviewMaxHz = 30
        Recorder = struct('Format', 'avi-mjpeg', 'CsvExtended', false)
        Calls = {}
    end

    properties (SetAccess = private)
        Backend = 'spinnaker'
        Attached = {}
        Cameras = struct('Serial', {}, 'Name', {})
        State = 'idle'
    end

    methods
        function obj = StubCameraManager(attached, backend)
            obj.Attached = attached;
            if nargin > 1
                obj.Backend = backend;
            end
        end

        function T = listCameras(obj)
            T = table(obj.Attached(:), 'VariableNames', {'Serial'});
        end

        function connect(obj, serials)
            obj.log('connect %s', strjoin(serials, ','));
            for i = 1:numel(serials)
                obj.Cameras(end+1) = struct('Serial', serials{i}, 'Name', sprintf('default%d', i));
            end
        end

        function setCameraName(obj, serial, name)
            obj.log('name %s %s', serial, name);
            obj.Cameras(strcmp({obj.Cameras.Serial}, serial)).Name = name;
        end

        function setProperty(obj, name, value, ~)
            obj.log('set %s %s', name, num2str(value));
        end

        function resetRoi(obj, serials)
            obj.log('full frame %s', strjoin(serials, ','));
        end

        function setRoi(obj, roi, serials)
            obj.log('crop %s %s', strjoin(serials, ','), mat2str(roi));
        end

        function configureSync(obj, mode, varargin)
            obj.log('sync %s %s', mode, strjoin(cellfun(@char, varargin, 'UniformOutput', false), ' '));
        end

        function startPreview(obj)
            obj.State = 'preview';
        end

        function stopPreview(obj)
            obj.State = 'idle';
        end

        function plan = startRecording(obj, folder, fileName)
            obj.State = 'recording';
            obj.log('record %s %s', folder, fileName);
            cameras = struct('Serial', {obj.Cameras.Serial}, 'Name', {obj.Cameras.Name}, ...
                             'VideoFile', '', 'CsvFile', '');
            for k = 1:numel(cameras)
                stem = fullfile(folder, [cameras(k).Name '_' fileName]);
                cameras(k).VideoFile = [stem '.avi'];
                cameras(k).CsvFile = [stem '.csv'];
            end
            plan = struct('Folder', folder, 'BaseName', fileName, 'StartTime', '2026-09-16T12:00:00', ...
                          'Format', obj.Recorder.Format, 'EventsFile', fullfile(folder, [fileName '_events.csv']), ...
                          'SessionFile', fullfile(folder, [fileName '_session.json']), 'Cameras', cameras);
        end

        function summary = stopRecording(obj)
            obj.State = 'idle';
            obj.log('stop');
            cameras = struct('Serial', {obj.Cameras.Serial}, 'Name', {obj.Cameras.Name}, ...
                             'VideoFiles', {{}}, 'CsvFile', '', 'FramesLogged', 10, 'FramesWritten', 10, ...
                             'FramesMissed', 0, 'WriterDrops', 0, 'FramesIncomplete', 0, 'QueuePeak', 1, ...
                             'GateOpened', true, 'Error', '');
            summary = struct('Duration_s', 1, 'Cameras', cameras);
        end

        function logEvent(obj, name, value)
            obj.log('event %s %s', name, num2str(value));
        end

        function t = hostTime(obj)
            t = numel(obj.Calls);
        end

        function [frames, meta] = getLatestFrames(obj)
            frames = repmat({zeros(4, 6, 'uint8')}, 1, numel(obj.Cameras));
            meta = struct([]);
        end

        function T = getStats(obj)
            n = numel(obj.Cameras);
            T = table({obj.Cameras.Serial}', {obj.Cameras.Name}', 100 * ones(n, 1), zeros(n, 1), ...
                      zeros(n, 1), zeros(n, 1), zeros(n, 1), zeros(n, 1), zeros(n, 1), false(n, 1), ...
                      repmat({''}, n, 1), 'VariableNames', {'Serial', 'Name', 'FPS', 'FramesReceived', ...
                      'FramesMissed', 'FramesWritten', 'WriterDrops', 'QueueDepth', 'LastTTL', ...
                      'Faulted', 'LastError'});
        end
    end

    methods (Access = private)
        function log(obj, fmt, varargin)
            obj.Calls{end+1} = sprintf(fmt, varargin{:});
        end
    end
end
