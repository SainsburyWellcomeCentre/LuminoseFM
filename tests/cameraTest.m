function tests = cameraTest
% cameraTest exercises video recording: lum.dev.Cameras and the windows around it.
%
% Most of it runs with StubCameraManager, so it needs neither cameras nor spincam: the
% settings check, where files go, how the settings become camera state, and what the
% session records. The last tests run a whole emulated behaviour session and a sleep
% session with spincam's simulated cameras, writing real video files; they need spincam
% (on the path, in SPINCAM_FOLDER, or beside the MATLAB folder this repository is in) and
% are skipped without it.
tests = functiontests(localfunctions);
end

%% Settings and files ----------------------------------------------------------------

function testTheDefaultsRecordBothViews(testCase)
camera = lum.defaultSettings().Camera;
verifyTrue(testCase, camera.Enabled, 'Recording is on by default');
verifyEqual(testCase, {camera.Cameras.Serial}, {'24226887', '24226657'});
verifyEqual(testCase, {camera.Cameras.Name}, {'sideview', 'topview'});
verifyEqual(testCase, camera.Format, 'avi-mjpeg-mt', 'Encoded on several cores');
verifyWarningFree(testCase, @() lum.dev.Cameras.validateSettings(camera));
verifyEmpty(testCase, lum.dev.Cameras.formatNote(camera), 'The default keeps up at the default rate');
end

function testAOneCoreEncoderAtFullRateIsWarnedAbout(testCase)
camera = lum.defaultSettings().Camera;
camera.Format = 'avi-mjpeg';
note = lum.dev.Cameras.formatNote(camera);
verifySubstring(testCase, note, 'avi-mjpeg-mt', 'SpinVideo MJPEG falls behind at 100 Hz full frame');
camera.Cameras(1).Roi = [0 0 640 512];
camera.Cameras(2).Roi = [0 0 640 512];
verifyEmpty(testCase, lum.dev.Cameras.formatNote(camera), 'A quarter of the pixels is within its reach');
camera.Enabled = false;
camera.Cameras(1).Roi = [];
verifyEmpty(testCase, lum.dev.Cameras.formatNote(camera), 'No note without video');
S = lum.defaultSettings;
S.Camera.Format = 'avi-mjpeg';
S.Camera.Enabled = true;
[~, ~, notes] = lum.validateSettings(S, RigConfig);
verifyTrue(testCase, any(contains(notes, 'avi-mjpeg-mt')), 'The session start says so');
end

function testEveryFormatIsDescribedInOneSentence(testCase)
formats = lum.dev.Cameras.Formats;
verifyNumElements(testCase, lum.dev.Cameras.FormatDescriptions, numel(formats));
for i = 1:numel(formats)
    text = lum.dev.Cameras.formatDescription(formats{i});
    verifyTrue(testCase, startsWith(text, [formats{i} ' ']) || startsWith(text, [formats{i} ':']), ...
               'Each description names its own format');
    verifyTrue(testCase, endsWith(text, '.') && ~contains(text(1:end-1), '. '), ...
               sprintf('One sentence: %s', text));
end
verifyEmpty(testCase, lum.dev.Cameras.formatDescription('matlab-avi'), 'Not offered, not described');
verifyEqual(testCase, cellfun(@lum.dev.Cameras.needsSpinVideo, formats), [false true true true false], ...
            'avi-mjpeg-mt and raw are SpinCam''s own; the others are SpinVideo''s');
end

function testCameraSettingsThatCannotRecordAreRefused(testCase)
camera = lum.defaultSettings().Camera;
cases = {@(c) setField(c, 'Format', 'matlab-avi'), 'badFormat'; ...
         @(c) setField(c, 'FrameRate', 200), 'badFrameRate'; ...
         @(c) manualExposure(c, 20000), 'badExposure'; ...
         @(c) sameNames(c), 'duplicateName'; ...
         @(c) noneRecorded(c), 'noCameras'; ...
         @(c) badCrop(c), 'badRoi'};
for i = 1:size(cases, 1)
    verifyError(testCase, @() lum.dev.Cameras.validateSettings(cases{i, 1}(camera)), ...
                ['lum:dev:Cameras:' cases{i, 2}]);
end
camera = noneRecorded(camera);
camera.Enabled = false;
verifyWarningFree(testCase, @() lum.dev.Cameras.validateSettings(camera), ...
                  'With recording off no camera has to be ticked');
end

function testVideosGoBesideTheSessionData(testCase)
dataFile = fullfile('D:', 'luminoseData', 'M1', 'LuminoseFM', 'Session Data', 'M1_LuminoseFM_20260916_101500.mat');
verifyEqual(testCase, lum.dev.Cameras.videoFolder(dataFile), ...
            fullfile('D:', 'luminoseData', 'M1', 'LuminoseFM', 'Session Videos'));
verifyEqual(testCase, lum.dev.Cameras.baseName(dataFile), 'M1_LuminoseFM_20260916_101500');
verifyEqual(testCase, lum.dev.Cameras.videoFolder(fullfile(tempdir, 'x.mat')), ...
            fullfile(fileparts(fullfile(tempdir, 'x.mat')), 'Session Videos'));
end

function testRecordingOffGivesTheNullShim(testCase)
S = lum.defaultSettings;
S.Camera.Enabled = false;
cameras = lum.dev.openCameras(false, S);
verifyClass(testCase, cameras, 'lum.dev.NullCameras');
verifyTrue(testCase, isnan(cameras.mark('TrialEnd', 1)));
verifyFalse(testCase, cameras.sessionRecord().Recorded);
end

function testTheRigRefusesVideoWithoutSpinCam(testCase)
S = lum.defaultSettings;
S.Camera.SpinCamFolder = fullfile(tempdir, 'no_spincam_here');
assumeEmpty(testCase, which('spincam.CameraManager'), 'spincam is on the path');
verifyError(testCase, @() lum.dev.openCameras(false, S), 'lum:dev:openCameras:noSpinCam');
verifyClass(testCase, lum.dev.openCameras(true, S), 'lum.dev.NullCameras', ...
            'The emulator degrades instead');
end

%% Setting the cameras up --------------------------------------------------------------

function testEachSerialGetsItsViewAndTheSettings(testCase)
camera = lum.defaultSettings().Camera;
camera.ExposureAuto = false;
camera.ExposureTime = 4000;
camera.Cameras(2).Roi = [0 0 960 720];
manager = StubCameraManager({'24226657', '24226887'});
connected = lum.dev.configureCameras(manager, camera, 'PreviewRate', 5);
verifyEqual(testCase, {connected.Serial}, {'24226887', '24226657'});
verifyEqual(testCase, {manager.Cameras.Name}, {'sideview', 'topview'});
calls = manager.Calls;
verifyTrue(testCase, any(strcmp(calls, 'full frame 24226887')), 'An empty crop is the full frame');
verifyTrue(testCase, any(strcmp(calls, 'crop 24226657 [0 0 960 720]')));
verifyLessThan(testCase, find(strcmp(calls, 'set ExposureTime 4000')), ...
               find(strcmp(calls, 'set FrameRate 100')), 'A shorter exposure goes first');
verifyTrue(testCase, any(startsWith(calls, 'sync passive TtlLine Line0')));
verifyFalse(testCase, manager.AppendDateTime, 'The data file''s name already has the date');
verifyTrue(testCase, manager.Recorder.CsvExtended, 'HostTime_s is in the extended log');
verifyEqual(testCase, manager.PreviewMaxHz, 5);
end

function testAMissingCameraStopsTheSessionButNotThePreview(testCase)
camera = lum.defaultSettings().Camera;
verifyError(testCase, @() lum.dev.configureCameras(StubCameraManager({'24226657'}), camera), ...
            'lum:dev:configureCameras:notAttached');
connected = lum.dev.configureCameras(StubCameraManager({'24226657'}), camera, 'Strict', false);
verifyEqual(testCase, {connected.Name}, {'topview'});
end

function testSimulatedCamerasTakeTheRowsInOrder(testCase)
camera = lum.defaultSettings().Camera;
connected = lum.dev.configureCameras(StubCameraManager({'90000001', '90000002'}, 'mock'), camera);
verifyEqual(testCase, {connected.Serial}, {'90000001', '90000002'});
verifyEqual(testCase, {connected.Name}, {'sideview', 'topview'});
end

function testARecordingIsMarkedAndSummarised(testCase)
camera = lum.defaultSettings().Camera;
manager = StubCameraManager({'24226887', '24226657'});
connected = lum.dev.configureCameras(manager, camera, 'PreviewRate', 5);
cameras = lum.dev.RealCameras(manager, camera, 'C:\SpinCam', connected);
dataFile = fullfile(tempdir, 'Session Data', 'M1_LuminoseFM_20260916_101500.mat');
plan = cameras.startRecording(dataFile);
verifyEqual(testCase, plan.BaseName, 'M1_LuminoseFM_20260916_101500');
verifyEqual(testCase, plan.Cameras(1).VideoFile, ...
            fullfile(tempdir, 'Session Videos', 'sideview_M1_LuminoseFM_20260916_101500.avi'));
verifyFalse(testCase, isnan(cameras.mark('TrialEnd', 1)));
verifyTrue(testCase, any(strcmp(manager.Calls, 'event TrialEnd 1')));
verifyTrue(testCase, cameras.canPreview());
stats = cameras.statistics();
verifyEqual(testCase, {stats.Name}, {'sideview', 'topview'});
cameras.stopRecording();
record = cameras.sessionRecord();
verifyTrue(testCase, record.Recorded);
verifyEqual(testCase, record.EngineVersion, '', 'A stub has no native engine');
verifyEqual(testCase, record.Summary.Cameras(1).FramesWritten, 10);
verifyTrue(testCase, isnan(cameras.mark('TrialEnd', 2)), 'No clock once stopped');
end

function testFinishingMarksTheSaveThenStops(testCase)
camera = lum.defaultSettings().Camera;
manager = StubCameraManager({'24226887', '24226657'});
connected = lum.dev.configureCameras(manager, camera);
cameras = lum.dev.RealCameras(manager, camera, '', connected);
cameras.startRecording(fullfile(tempdir, 'Session Data', 'M1_LuminoseFM_20260916_101500.mat'));
summary = cameras.finishRecording('SessionSaved', 12);
calls = manager.Calls;
saved = find(strcmp(calls, 'event SessionSaved 12'));
verifyNotEmpty(testCase, saved, 'The final save is marked on the camera clock');
verifyLessThan(testCase, saved, find(strcmp(calls, 'stop')), 'Marked before the video stops');
verifyEqual(testCase, summary.Cameras(1).FramesWritten, 10);
verifyFalse(testCase, cameras.IsRecording);
verifyWarningFree(testCase, @() cameras.finishRecording('SessionSaved', 12), 'Safe to call twice');
end

function testTheCameraWindowShowsEveryCamera(testCase)
camera = lum.defaultSettings().Camera;
manager = StubCameraManager({'24226887', '24226657'});
connected = lum.dev.configureCameras(manager, camera, 'PreviewRate', 5);
cameras = lum.dev.RealCameras(manager, camera, '', connected);
window = lum.gui.CameraWindow(cameras, camera, 'Visible', 'off', 'StartTimer', false);
cleanup = onCleanup(@() window.close());
window.refresh();
verifyNotEmpty(testCase, window.Figure);
details = findobj(window.Figure, 'Style', 'text');
verifyTrue(testCase, any(contains(get(details, 'String'), '100.0 fps')));
window.close();
verifyEmpty(testCase, window.Figure);
end

%% Whole sessions with simulated cameras --------------------------------------------------

function testAnEmulatedBehaviourSessionRecordsVideo(testCase)
folder = locateSpinCamForTests();
assumeNotEmpty(testCase, folder, 'spincam is not available on this machine');
ensureEmulator();
S = shortSession(lum.defaultSettings, folder);
[sessionData, dataFile] = runSession(testCase, S, 'camSubject_LuminoseFM_camtest.mat');
record = sessionData.Session.Cameras;
verifyEqual(testCase, record.Backend, 'mock');
verifyTrue(testCase, record.Recorded);
verifyNotEmpty(testCase, record.EngineVersion, 'The native engine''s version is recorded');
verifyEqual(testCase, {record.Summary.Cameras.Name}, {'sideview', 'topview'});
verifyGreaterThan(testCase, [record.Summary.Cameras.FramesWritten], 0);
videos = lum.dev.Cameras.videoFolder(dataFile);
for name = {'sideview', 'topview'}
    verifyTrue(testCase, isfile(fullfile(videos, [name{1} '_camSubject_LuminoseFM_camtest.avi'])));
    verifyTrue(testCase, isfile(fullfile(videos, [name{1} '_camSubject_LuminoseFM_camtest.csv'])));
end
verifyLength(testCase, sessionData.CameraTime, sessionData.nTrials);
verifyTrue(testCase, all(diff(sessionData.CameraTime) > 0), 'One clock, running forward');
events = fileread(fullfile(videos, 'camSubject_LuminoseFM_camtest_events.csv'));
verifySubstring(testCase, events, 'TrialEnd');
verifyVideoOutlastsTheData(testCase, events, sessionData);
end

function testAnEmulatedSleepSessionRecordsVideo(testCase)
folder = locateSpinCamForTests();
assumeNotEmpty(testCase, folder, 'spincam is not available on this machine');
ensureEmulator();
S = shortSession(lum.defaultSettings, folder);
S.Session.Type = 'Sleep';
S.Sleep.DurationMinutes = 2 / 60;
S.Sleep.Sync.Interval = 0.5;
[sessionData, dataFile] = runSession(testCase, S, 'camSubject_LuminoseFM_camsleep.mat');
verifyTrue(testCase, sessionData.Session.Cameras.Recorded);
events = fileread(fullfile(lum.dev.Cameras.videoFolder(dataFile), 'camSubject_LuminoseFM_camsleep_events.csv'));
verifyVideoOutlastsTheData(testCase, events, sessionData);
verifyLength(testCase, sessionData.CameraTime, sessionData.nTrials, 'One mark per block');
verifyFalse(testCase, any(isnan(sessionData.CameraTime)));
end


%% Helpers ---------------------------------------------------------------------------------

function verifyVideoOutlastsTheData(testCase, events, sessionData)
% The video stops after the final save, and the file still carries the recording summary.
saved = strfind(events, 'SessionSaved');
stopped = strfind(events, 'RecordingStop');
verifyNotEmpty(testCase, saved, 'The final save is marked on the camera clock');
verifyNotEmpty(testCase, stopped);
verifyLessThan(testCase, saved(end), stopped(end), 'The video stops after the data are saved');
summary = sessionData.Session.Cameras.Summary;
verifyTrue(testCase, isfield(summary, 'Cameras') && all([summary.Cameras.FramesWritten] > 0), ...
           'The second save adds the recording summary');
verifyTrue(testCase, any(contains(sessionData.Session.DeviceLog.Cameras, 'recording stopped')), ...
           'The camera log in the file includes the stop');
end

function S = shortSession(S, folder)
S.Session.MaxTrials = 3;
S.Session.SaveEveryNTrials = 1;
S.Stimulus.Duration = 0.05;
S = withCue(S, {'CentreLight'});
S.GUI.HoldWindow = 0.3;
S.GUI.ResponseWindow = 0.2;
S.GUI.ITI = 0.2;
S.Camera.SpinCamFolder = folder;
S.Camera.FrameRate = 30;
S.Camera.ShowWindow = false;
end

function [sessionData, dataFile] = runSession(testCase, S, fileName)
global BpodSystem %#ok<GVMIS>
root = fileparts(fileparts(mfilename('fullpath')));
dataFolder = fullfile(tempdir, 'LuminoseFM_camera_test', 'Session Data');
if isfolder(fileparts(dataFolder))
    rmdir(fileparts(dataFolder), 's');
end
mkdir(dataFolder);
testCase.addTeardown(@() rmdir(fileparts(dataFolder), 's'));
BpodSystem.ProtocolSettings = S;
BpodSystem.Data = struct;
BpodSystem.Status.BeingUsed = 1;
BpodSystem.Status.SessionStartFlag = 1;
BpodSystem.Status.Live = 1;
BpodSystem.Status.Pause = 0;
BpodSystem.Status.CurrentProtocolName = 'LuminoseFM';
BpodSystem.Status.CurrentSubjectName = 'camSubject';
BpodSystem.Path.ProtocolFolder = fileparts(root);
dataFile = fullfile(dataFolder, fileName);
BpodSystem.Path.CurrentDataFile = dataFile;
setappdata(0, 'LuminoseFM_Headless', true);
testCase.addTeardown(@() setappdata(0, 'LuminoseFM_Headless', false));
LuminoseFM;
addpath(root, fullfile(root, 'hardware'), fullfile(root, 'tests'));
loaded = load(dataFile);
sessionData = loaded.SessionData;
end

function folder = locateSpinCamForTests()
% spincam on the path, in SPINCAM_FOLDER, or a SpinCam folder beside the MATLAB folder.
root = fileparts(fileparts(mfilename('fullpath')));
candidates = {getenv('SPINCAM_FOLDER'), fullfile(fileparts(fileparts(fileparts(root))), 'SpinCam')};
folder = lum.dev.Cameras.locateSpinCam('');
for i = 1:numel(candidates)
    if isempty(folder)
        folder = lum.dev.Cameras.locateSpinCam(candidates{i});
    end
end
end

function c = setField(c, name, value)
c.(name) = value;
end

function c = manualExposure(c, microseconds)
c.ExposureAuto = false;
c.ExposureTime = microseconds;
end

function c = sameNames(c)
c.Cameras(2).Name = 'sideview';
end

function c = noneRecorded(c)
[c.Cameras.Record] = deal(false);
end

function c = badCrop(c)
c.Cameras(1).Roi = [0 0 100];
end
