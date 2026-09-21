function tests = ephysSessionTest
% ephysSessionTest runs a whole ePhys calibration session under Bpod('EMU') (D18).
%
% LuminoseFM, launched headless with S.Session.Type 'EphysCalibration', must send its
% barcode and every step of light end to end on a machine with no hardware, with the
% LED on the DoricLED package's simulated driver, and write a data file that records
% each gate of light with the LED current it ran at. Skipped where DoricLED is not found.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.assumeNotEmpty(lum.dev.DoricLED.locatePackage(''), 'The DoricLED package is not on the path.');
ensureEmulator();
testCase.TestData.dataFolder = fullfile(tempdir, 'LuminoseFM_ephys_test_data');
if ~isfolder(testCase.TestData.dataFolder)
    mkdir(testCase.TestData.dataFolder);
end
S = ephysSettings();
testCase.TestData.S = S;
testCase.TestData.plan = lum.ephys.plan(S, lum.led.calibrations(S));
testCase.TestData.sessionData = runSession(testCase, S, 'testSubject_LuminoseFM_ephys_test.mat');
end

function teardownOnce(testCase)
setappdata(0, 'LuminoseFM_Headless', false);
if isfield(testCase.TestData, 'dataFolder') && isfolder(testCase.TestData.dataFolder)
    rmdir(testCase.TestData.dataFolder, 's');
end
end

function testTheSessionIsRecordedAsAnEmulatedEphysCalibration(testCase)
session = testCase.TestData.sessionData.Session;
verifyEqual(testCase, session.Type, 'EphysCalibration');
verifyTrue(testCase, session.Emulated);
verifyTrue(testCase, session.Ephys.Completed);
verifyEmpty(testCase, session.Ephys.StoppedReason);
verifyEqual(testCase, numel(session.Ephys.Steps), numel(testCase.TestData.plan.Steps));
verifyFalse(testCase, isfield(session, 'TestPulses'), 'Not a sleep session');
end

function testTheBarcodeIsOfTheEphysKind(testCase)
barcode = testCase.TestData.sessionData.Session.Barcode;
verifyEqual(testCase, barcode.Kind, 'EphysCalibration');
verifyFalse(testCase, barcode.Sent, 'The emulator has no sync line');
verifyTrue(testCase, any(contains(testCase.TestData.sessionData.Session.DeviceLog.FlexIO, 'barcode')));
end

function testEveryGateIsSentWithTheCurrentOfItsStep(testCase)
sessionData = testCase.TestData.sessionData;
plan = testCase.TestData.plan;
light = sessionData.LightSegments;
verifyEqual(testCase, numel(light.Onset), size(plan.Segments, 1));
verifyEqual(testCase, light.Step, plan.Segments(:, 4)');
steps = vertcat(plan.Steps.CurrentmA);
expected = steps(sub2ind(size(steps), light.Step, light.Channel));
verifyEqual(testCase, light.CurrentmA, expected, 'Each gate at its step''s current');
verifyGreaterThan(testCase, min(diff(light.Onset)), 0);
end

function testTheLEDWasSetUpAndSteppedBetweenBlocks(testCase)
session = testCase.TestData.sessionData.Session;
record = session.DoricLED;
verifyTrue(testCase, record.Controlled);
verifyEqual(testCase, record.Mode, 'Simulated');
log = session.DeviceLog.DoricLED;
verifyTrue(testCase, any(contains(log, 'external TTL mode')));
changes = record.Device.Changes;
steps = vertcat(testCase.TestData.plan.Steps.CurrentmA);
sentA = changes(changes(:, 2) == 1, 3)';
verifyEqual(testCase, unique(sentA), unique(steps(:, 1))', 'Every level of the curve was sent');
end

function testPulsePalGivesConstantLight(testCase)
log = testCase.TestData.sessionData.Session.DeviceLog.PulsePal;
verifyTrue(testCase, any(contains(log, 'would set ch1')));
end

function testTheProtocolFolderIsStillUsableAfterTheSession(testCase)
verifyNotEmpty(testCase, which('lum.ephys.plan'));
end


function S = ephysSettings()
% Three input-output levels on A and two paired-pulse intervals, two repeats, 0.4 s apart.
S = lum.defaultSettings;
S.Session.Type = 'EphysCalibration';
S.Camera.Enabled = false;   % Keeps the emulator's loop light; cameraTest covers video
S.Doric.ShowWindow = false;
S.Ephys.InterEpochInterval = 0.4;
S.Ephys.Repeats = 2;
S.Ephys.InputOutput.MaxmA = [200 NaN];
S.Ephys.InputOutput.nLevels = 3;
S.Ephys.PairedPulse.Intervals = [0.02 0.05];
S.Ephys.Sync.Interval = 0.3;
S.Ephys.Sync.IntervalJitter = 0;
end

function sessionData = runSession(testCase, S, fileName)
% Set BpodSystem up the way RunProtocol would, then run the protocol for real.
global BpodSystem %#ok<GVMIS>

root = fileparts(fileparts(mfilename('fullpath')));
BpodSystem.ProtocolSettings = S;
BpodSystem.Data = struct;
BpodSystem.Status.BeingUsed = 1;
BpodSystem.Status.SessionStartFlag = 1;
BpodSystem.Status.Live = 1;
BpodSystem.Status.Pause = 0;
BpodSystem.Status.CurrentProtocolName = 'LuminoseFM';
BpodSystem.Status.CurrentSubjectName = 'testSubject';
BpodSystem.Path.ProtocolFolder = fileparts(root);
BpodSystem.Path.CurrentDataFile = fullfile(testCase.TestData.dataFolder, fileName);

setappdata(0, 'LuminoseFM_Headless', true);

LuminoseFM;

% RunProtocol('Stop') took the protocol folder off the path on its way out.
addpath(root, fullfile(root, 'hardware'), fullfile(root, 'tests'));

loaded = load(BpodSystem.Path.CurrentDataFile);
sessionData = loaded.SessionData;
end
