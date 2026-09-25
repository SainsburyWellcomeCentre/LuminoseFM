classdef Cameras < lum.dev.Device
    % lum.dev.Cameras records the session on video, through the spincam package.
    %
    % Video is recorded by spincam (github: the lab's SpinCam repository, cloned
    % anywhere; S.Camera.SpinCamFolder says where). spincam grabs, encodes and logs every
    % frame on native threads of its own, so recording costs the MATLAB thread nothing
    % while Bpod runs trials: MATLAB only starts the recording before the barcode, marks
    % each trial's end on the camera clock, shows a low-rate preview if asked, and stops
    % the recording at teardown. Frames are logged in passive TTL mode: each frame records
    % the state of the camera's TTL input (Line0), which Bpod's sync line is wired to, so
    % the barcode and the trial pulses are visible frame by frame.
    %
    % Files go beside the session's data, one set per session:
    %
    %   <subject>\LuminoseFM\Session Videos\<view>_<data file name>.avi   video (or .mp4/.raw)
    %   <subject>\LuminoseFM\Session Videos\<view>_<data file name>.csv   one row per frame
    %   <subject>\LuminoseFM\Session Videos\<data file name>_events.csv   marks, host clock
    %   <subject>\LuminoseFM\Session Videos\<data file name>_session.json settings, summary
    %
    % where <view> is the camera's name in S.Camera.Cameras (24226887 topview, 24226657
    % sideview on this rig, checked against the views 2026-09-25).
    %
    % Crops are kept per session type (S.Camera.Crops.Behaviour, .Sleep,
    % .EphysCalibration, by serial): a behaviour box and a home cage need different ones.
    % Once the session type is known, cropFor puts that type's last crops into
    % S.Camera.Cameras(k).Roi, which the Cameras tab edits and the session records with;
    % keepCrop stores them back when the settings file is written. The frame log's HostTime_s column is in seconds on the same
    % host clock as the events file and as Data.CameraTime, which pairs each trial's
    % TrialEndTimestamp with that clock (lum.dev.Cameras.mark).
    %
    % Subclasses: lum.dev.RealCameras (a spincam.CameraManager, with real cameras or, in
    % the emulator, spincam's simulated ones) and lum.dev.NullCameras (recording off, or
    % no spincam in the emulator). Construct through lum.dev.open.
    %
    % See also: lum.dev.openCameras, lum.dev.configureCameras, lum.gui.CameraWindow,
    %           lum.gui.CameraSetup

    properties (Constant)
        % Formats encoded on spincam's own threads. avi-mjpeg-mt (the default) encodes each
        % camera on several cores and keeps up with full frames at 120 Hz; avi-mjpeg is
        % SpinVideo's single-threaded encoder, which manages only ~104 fps per camera at full
        % frame and falls behind at 100 Hz once MATLAB is busy (formatNote). spincam's
        % matlab-* formats are drained by a MATLAB timer, which a trial loop would starve, so
        % they are not offered.
        Formats = {'avi-mjpeg-mt', 'avi-mjpeg', 'mp4-h264', 'avi-raw', 'raw'}
        % One sentence per format, in the order of Formats, for the setup dialogs' help line
        % (formatDescription). Figures are SpinCam's, for two full-frame cameras on the rig.
        FormatDescriptions = { ...
            ['avi-mjpeg-mt (recommended): compressed MJPEG that SpinCam encodes on several CPU '...
             'cores, keeping up with both cameras at full frame up to 120 Hz for hours, about 27 GB '...
             'an hour at 100 Hz, readable by VideoReader, ffmpeg and OpenCV.'], ...
            ['avi-mjpeg: compressed MJPEG from Spinnaker''s SpinVideo, encoded on one core at about '...
             '104 frames a second per full-frame camera, so at 100 Hz it falls behind once MATLAB is '...
             'busy and drops frames; use it only with a crop or a lower frame rate.'], ...
            ['mp4-h264: H.264 MP4 from Spinnaker''s SpinVideo, the slowest encoder (about 70 frames a '...
             'second per full-frame camera), for low frame rates or small crops only.'], ...
            ['avi-raw: SpinVideo''s "uncompressed" AVI, stored as YUV 4:2:0 (gray levels can shift '...
             'by a few counts) and encoded on one core at about 110 frames a second per full-frame '...
             'camera; choose raw instead when exact pixel values matter.'], ...
            ['raw: lossless 8-bit frames written straight to disk with no encoding, exact at any '...
             'frame rate but about 0.9 TB an hour for both cameras at 100 Hz; read with '...
             'spincam.io.RawVideoReader or convert afterwards with spincam.io.rawToAvi.']}
        % Frames per second per camera at 1280 x 1024 that the single-threaded SpinVideo
        % formats keep up with on the rig (spincam.VideoRecorder.MeasuredCapacity), less
        % the margin a busy session takes from them.
        SingleThreadSafeRate = struct('avi_mjpeg', 90, 'mp4_h264', 60, 'avi_raw', 95)
        FolderName = 'Session Videos'
        TtlLines = {'Line0', 'Line2', 'Line3'}
        MaxFrameRate = 150       % The Chameleon3's limit is 150.7 Hz
        MaxWindowRate = 30       % Preview refreshes per second, at most
        CropKinds = {'Behaviour', 'Sleep', 'EphysCalibration'}  % S.Camera.Crops fields
    end

    properties (SetAccess = protected)
        Backend = 'none'         % 'spinnaker', 'mock' or 'none'
        Settings = struct()      % S.Camera, as the session uses it
        SpinCamFolder = ''       % Where spincam was loaded from
        Plan = struct()          % What startRecording set up: folder, files, cameras
        Summary = struct()       % What stopRecording reported: frames, drops, files
        IsRecording = false
    end

    methods
        function obj = Cameras(available, backend, settings)
            obj@lum.dev.Device('Cameras', available);
            obj.Backend = backend;
            obj.Settings = settings;
        end

        function plan = startRecording(obj, dataFile)
            % startRecording(dataFile) starts recording every camera into the session's
            % video folder, with file names taken from the data file's.
            if obj.IsRecording
                plan = obj.Plan;
                return
            end
            folder = lum.dev.Cameras.videoFolder(dataFile);
            base = lum.dev.Cameras.baseName(dataFile);
            plan = obj.applyStart(folder, base);
            obj.Plan = plan;
            obj.IsRecording = obj.canRecord();
            obj.note('recording into %s as %s', folder, base);
        end

        function summary = stopRecording(obj)
            % stopRecording() finalises every file and returns what was recorded. Safe to
            % call when nothing is recording; it returns the last summary.
            summary = obj.Summary;
            if ~obj.IsRecording
                return
            end
            obj.IsRecording = false;
            summary = obj.applyStop();
            obj.Summary = summary;
            obj.note('recording stopped');
        end

        function summary = finishRecording(obj, event, value)
            % finishRecording(event, value) ends a session's video: marks the event (the
            % final save) on the camera clock, then stops the recording. Called in teardown
            % after the data file is written, so everything the file holds is on the video.
            obj.mark(event, value);
            summary = obj.stopRecording();
        end

        function hostTime = mark(obj, event, value)
            % mark(event, value) writes a row to the events file and returns the time on
            % the camera host clock (HostTime_s in the frame logs), in seconds; NaN when
            % nothing is recording. Called once per trial, outside the stimulus.
            hostTime = NaN;
            if obj.IsRecording
                hostTime = obj.applyMark(event, value);
            end
        end

        function [frames, info] = latestFrames(obj) %#ok<MANU> % Overridden where there are cameras
            % latestFrames() is the most recent preview frame of each camera and, per
            % camera, its Name and Serial.
            frames = {};
            info = struct('Name', {}, 'Serial', {});
        end

        function stats = statistics(obj) %#ok<MANU> % Overridden where there are cameras
            % statistics() is a struct array, one element per camera: Name, Serial, FPS,
            % FramesReceived, FramesMissed, FramesWritten, WriterDrops, QueueDepth, LastTTL,
            % Faulted and LastError.
            stats = struct('Name', {}, 'Serial', {}, 'FPS', {}, 'FramesReceived', {}, ...
                           'FramesMissed', {}, 'FramesWritten', {}, 'WriterDrops', {}, ...
                           'QueueDepth', {}, 'LastTTL', {}, 'Faulted', {}, 'LastError', {});
        end

        function tf = canPreview(obj) %#ok<MANU> % Overridden where there are cameras
            % canPreview() is true when there are frames to show.
            tf = false;
        end

        function record = sessionRecord(obj)
            % sessionRecord() is what the data file keeps about the video: stored once, in
            % Data.Session.Cameras.
            camera = obj.Settings;
            record = struct('Enabled', isfield(camera, 'Enabled') && logical(camera.Enabled), ...
                            'Backend', obj.Backend, 'Available', obj.Available, ...
                            'Recorded', ~isempty(fieldnames(obj.Plan)), ...
                            'SpinCamFolder', obj.SpinCamFolder, 'SpinCamVersion', obj.spinCamVersion(), ...
                            'EngineVersion', obj.engineVersion(), ...
                            'Settings', camera, 'Plan', obj.Plan, 'Summary', obj.Summary, ...
                            'TimeColumns', ['Data.CameraTime and the frame logs'' HostTime_s are '...
                                            'seconds on one host clock']);
        end
    end

    methods (Access = protected)
        function plan = applyStart(obj, folder, base)
            plan = struct();
            obj.note('would record into %s as %s', folder, base);
        end

        function summary = applyStop(obj) %#ok<MANU> % Overridden where there are cameras
            summary = struct();
        end

        function hostTime = applyMark(obj, event, value) %#ok<INUSD> % Overridden where there are cameras
            hostTime = NaN;
        end

        function tf = canRecord(obj) %#ok<MANU> % Overridden where there are cameras
            tf = false;
        end

        function version = spinCamVersion(obj) %#ok<MANU> % Overridden where spincam is loaded
            version = '';
        end

        function version = engineVersion(obj) %#ok<MANU> % Overridden where spincam is loaded
            version = '';
        end
    end

    methods (Static)
        function folder = videoFolder(dataFile)
            % videoFolder(dataFile) is where a session's videos go: 'Session Videos' beside
            % Bpod's 'Session Data' folder, or inside the data file's folder when it is not
            % in one (a test, a file saved by hand).
            dataFolder = fileparts(char(dataFile));
            [parent, name] = fileparts(dataFolder);
            if strcmpi(name, 'Session Data')
                folder = fullfile(parent, lum.dev.Cameras.FolderName);
            else
                folder = fullfile(dataFolder, lum.dev.Cameras.FolderName);
            end
        end

        function base = baseName(dataFile)
            % baseName(dataFile) is the data file's name, which every video file carries:
            % <subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.
            [~, base] = fileparts(char(dataFile));
        end

        function validateSettings(camera)
            % validateSettings(camera) checks S.Camera, erroring with an operator's
            % message at the first problem. Pure: it does not look for spincam or cameras.
            if ~isLogicalScalar(camera.Enabled)
                fail('badEnabled', 'Record video must be on or off.');
            end
            if ~(ischar(camera.SpinCamFolder) || isstring(camera.SpinCamFolder))
                fail('badFolder', 'The SpinCam folder must be a folder name.');
            end
            if ~ismember(camera.Format, lum.dev.Cameras.Formats)
                fail('badFormat', 'The video format must be one of: %s.', ...
                     strjoin(lum.dev.Cameras.Formats, ', '));
            end
            rate = camera.FrameRate;
            if ~(isscalar(rate) && rate > 0 && rate <= lum.dev.Cameras.MaxFrameRate)
                fail('badFrameRate', 'The camera frame rate must be above 0 and at most %d Hz.', ...
                     lum.dev.Cameras.MaxFrameRate);
            end
            if ~isLogicalScalar(camera.ExposureAuto) || ~isLogicalScalar(camera.GainAuto)
                fail('badAuto', 'Automatic exposure and gain must be on or off.');
            end
            if ~camera.ExposureAuto && ~(isscalar(camera.ExposureTime) && camera.ExposureTime > 0 ...
                                         && camera.ExposureTime < 1e6 / rate)
                fail('badExposure', ['A manual exposure must be above 0 and shorter than one frame '...
                                     '(%.0f us at %g Hz).'], 1e6 / rate, rate);
            end
            if ~camera.GainAuto && ~(isscalar(camera.Gain) && camera.Gain >= 0 && camera.Gain <= 48)
                fail('badGain', 'A manual gain must be between 0 and 48 dB.');
            end
            if ~ismember(camera.TtlLine, lum.dev.Cameras.TtlLines)
                fail('badTtlLine', 'The camera TTL input must be one of: %s.', ...
                     strjoin(lum.dev.Cameras.TtlLines, ', '));
            end
            if ~isLogicalScalar(camera.ShowWindow) || ~(isscalar(camera.WindowRate) ...
                    && camera.WindowRate > 0 && camera.WindowRate <= lum.dev.Cameras.MaxWindowRate)
                fail('badWindow', 'The camera window refreshes between 0 and %d times a second.', ...
                     lum.dev.Cameras.MaxWindowRate);
            end
            rows = camera.Cameras;
            if ~isstruct(rows) || ~all(isfield(rows, {'Serial', 'Name', 'Record', 'Roi'}))
                fail('badCameras', 'The camera list must give each camera a serial, a name and a crop.');
            end
            serials = arrayfun(@(r) strtrim(char(r.Serial)), rows, 'UniformOutput', false);
            if any(cellfun(@isempty, serials)) || numel(unique(serials)) < numel(serials)
                fail('badSerials', 'Every camera needs a serial number of its own.');
            end
            recorded = rows(arrayfun(@(r) logical(r.Record), rows));
            if camera.Enabled && isempty(recorded)
                fail('noCameras', 'Record video is on, but no camera is ticked to record.');
            end
            names = arrayfun(@(r) lum.dev.Cameras.cleanName(r.Name), recorded, 'UniformOutput', false);
            if any(cellfun(@isempty, names))
                fail('badName', ['Every recorded camera needs a view name (letters, digits, - and _), '...
                                 'such as sideview or topview.']);
            end
            if numel(unique(lower(names))) < numel(names)
                fail('duplicateName', 'Two recorded cameras have the same view name: %s.', ...
                     strjoin(names, ', '));
            end
            for i = 1:numel(rows)
                roi = rows(i).Roi;
                if ~isempty(roi) && ~(isnumeric(roi) && numel(roi) == 4 && all(roi >= 0) ...
                                      && all(roi(3:4) > 0))
                    fail('badRoi', 'The crop of camera %s must be empty (full frame) or [x y width height].', ...
                         serials{i});
                end
            end
        end

        function note = formatNote(camera)
            % formatNote(camera) is '' or a warning that the chosen format's single-threaded
            % encoder will fall behind at this frame rate and frame size (writer drops once
            % its queue fills). Not a refusal: the operator may crop, or accept it.
            note = '';
            key = strrep(char(camera.Format), '-', '_');
            if ~camera.Enabled || ~isfield(lum.dev.Cameras.SingleThreadSafeRate, key)
                return
            end
            rows = camera.Cameras(arrayfun(@(r) logical(r.Record), camera.Cameras));
            pixels = 1280 * 1024;
            for i = 1:numel(rows)
                if ~isempty(rows(i).Roi)
                    pixels = min(pixels, rows(i).Roi(3) * rows(i).Roi(4));
                end
            end
            safeRate = lum.dev.Cameras.SingleThreadSafeRate.(key) * (1280 * 1024) / pixels;
            if camera.FrameRate > safeRate
                note = sprintf(['%s encodes on one core and keeps up with about %.0f Hz at this frame '...
                                'size; at %g Hz its queue fills and frames are dropped from the video. '...
                                'Choose avi-mjpeg-mt.'], camera.Format, safeRate, camera.FrameRate);
            end
        end

        function text = formatDescription(format)
            % formatDescription(format) is one sentence on what a video format does, for the
            % help line; '' for a format not offered.
            index = find(strcmp(lum.dev.Cameras.Formats, char(format)), 1);
            text = '';
            if ~isempty(index)
                text = lum.dev.Cameras.FormatDescriptions{index};
            end
        end

        function tf = needsSpinVideo(format)
            % needsSpinVideo(format) is true for the formats written by Spinnaker's SpinVideo
            % component, which a Spinnaker installation may lack.
            tf = ismember(char(format), {'avi-mjpeg', 'mp4-h264', 'avi-raw'});
        end

        function camera = cropFor(camera, sessionType)
            % cropFor(camera, sessionType) sets each camera's Roi to the crop last kept for a
            % session of this type (S.Camera.Crops.<type>, matched by serial), or to the full
            % frame where there is none. A crop set for another session type is not used.
            crops = lum.dev.Cameras.cropsOf(camera, sessionType);
            for k = 1:numel(camera.Cameras)
                match = find(strcmp({crops.Serial}, strtrim(char(camera.Cameras(k).Serial))), 1);
                if isempty(match)
                    camera.Cameras(k).Roi = [];
                else
                    camera.Cameras(k).Roi = crops(match).Roi;
                end
            end
        end

        function camera = keepCrop(camera, sessionType)
            % keepCrop(camera, sessionType) keeps each camera's Roi as this session type's
            % crop (S.Camera.Crops.<type>), for the next session of the type: cropFor.
            kept = struct('Serial', {}, 'Roi', {});
            for k = 1:numel(camera.Cameras)
                roi = camera.Cameras(k).Roi;
                serial = strtrim(char(camera.Cameras(k).Serial));
                if ~isempty(roi) && ~isempty(serial)
                    kept(end+1) = struct('Serial', serial, 'Roi', double(roi(:)')); %#ok<AGROW>
                end
            end
            if ~isfield(camera, 'Crops') || ~isstruct(camera.Crops)
                camera.Crops = lum.dev.Cameras.noCrops();
            end
            camera.Crops.(lum.dev.Cameras.cropKind(sessionType)) = kept;
        end

        function crops = noCrops()
            % noCrops() is S.Camera.Crops with no crop for any session type.
            none = struct('Serial', {}, 'Roi', {});
            crops = struct('Behaviour', none, 'Sleep', none, 'EphysCalibration', none);
        end

        function roi = parseCrop(text)
            % parseCrop(text) reads a crop as the Cameras tab shows it: 'x,y wxh' (sensor
            % pixels, x and y from the top left) or 'full frame' (or nothing) for []. NaN when
            % it is neither.
            text = strtrim(lower(char(string(text))));
            if isempty(text) || any(strcmp(text, {'full frame', 'full', 'none'}))
                roi = [];
                return
            end
            numbers = str2double(regexp(text, '\d+(\.\d+)?', 'match'));
            if numel(numbers) ~= 4 || any(numbers(3:4) < 1) || any(mod(numbers, 1) ~= 0)
                roi = NaN;
                return
            end
            roi = numbers;
        end

        function name = cleanName(name)
            % cleanName(name) is a view name as spincam writes it into file names: letters,
            % digits, - and _, anything else becoming _.
            name = regexprep(strtrim(char(name)), '[^A-Za-z0-9_\-]+', '_');
            name = regexprep(name, '^_+|_+$', '');
        end

        function crops = cropsOf(camera, sessionType)
            % The crops kept for a session type, or none.
            crops = struct('Serial', {}, 'Roi', {});
            kind = lum.dev.Cameras.cropKind(sessionType);
            if isfield(camera, 'Crops') && isstruct(camera.Crops) && isfield(camera.Crops, kind) ...
                    && isstruct(camera.Crops.(kind)) && all(isfield(camera.Crops.(kind), {'Serial', 'Roi'}))
                crops = camera.Crops.(kind);
            end
        end

        function kind = cropKind(sessionType)
            % The S.Camera.Crops field of a session type; behaviour for anything else.
            kind = char(sessionType);
            if ~ismember(kind, lum.dev.Cameras.CropKinds)
                kind = 'Behaviour';
            end
        end

        function folder = locateSpinCam(folder)
            % locateSpinCam(folder) is the spincam folder to use: the one given, if it holds
            % the package, else wherever spincam already is on the MATLAB path; '' if neither.
            folder = strtrim(char(folder));
            if ~isempty(folder) && isfile(fullfile(folder, '+spincam', 'CameraManager.m'))
                return
            end
            folder = '';
            onPath = which('spincam.CameraManager');
            if ~isempty(onPath)
                folder = fileparts(fileparts(onPath));
            end
        end
    end
end


function tf = isLogicalScalar(value)
tf = isscalar(value) && (islogical(value) || (isnumeric(value) && ismember(value, [0 1])));
end


function fail(id, varargin)
error(['lum:dev:Cameras:' id], varargin{:});
end
