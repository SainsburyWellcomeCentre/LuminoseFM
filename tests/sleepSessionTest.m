function tests = sleepSessionTest
% sleepSessionTest runs a whole sleep session under Bpod('EMU').
%
% The sleep counterpart of emulatorSessionTest: LuminoseFM, launched headless with
% S.Session.Type 'Sleep', must run its barcode and pulse blocks end to end on a machine
% with no hardware, and write a data file that says it is an emulated sleep session and
% records every pulse it would have sent.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
ensureEmulator();
testCase.TestData.dataFolder = fullfile(tempdir, 'LuminoseFM_sleep_test_data');
if ~isfolder(testCase.TestData.dataFolder)
    mkdir(testCase.TestData.dataFolder);
end
testCase.TestData.durationSeconds = 3;
testCase.TestData.interval = 0.25;
testCase.TestData.sessionData = runSleepSession(testCase);
end

function teardownOnce(testCase)
setappdata(0, 'LuminoseFM_Headless', false);
if isfolder(testCase.TestData.dataFolder)
    rmdir(testCase.TestData.dataFolder, 's');
end
end

function testTheSessionIsRecordedAsAnEmulatedSleepSession(testCase)
sessionData = testCase.TestData.sessionData;
verifyEqual(testCase, sessionData.Session.Type, 'Sleep');
verifyEqual(testCase, sessionData.Info.EmulatorMode, true);
verifyTrue(testCase, sessionData.Session.Emulated);
verifyFalse(testCase, sessionData.Session.SyncSent, 'The emulator has no sync line');
verifyFalse(testCase, isfield(sessionData, 'Outcome'), 'A sleep session has no trials to score');
end

function testEveryPulseIsRecordedWithItsOnsetAndWidth(testCase)
pulses = testCase.TestData.sessionData.SyncPulses;
expected = testCase.TestData.durationSeconds / testCase.TestData.interval;
n = numel(pulses.Onset);
verifyGreaterThanOrEqual(testCase, n, 0.6 * expected);
verifyLessThanOrEqual(testCase, n, 2 * expected);
verifyEqual(testCase, [numel(pulses.Width), numel(pulses.Block)], [n n]);
verifyGreaterThan(testCase, min(diff(pulses.Onset)), 0, 'Onsets must increase');
verifyGreaterThanOrEqual(testCase, min(pulses.Width), 0.010 - 1e-9);
verifyLessThanOrEqual(testCase, max(pulses.Width), 0.100 + 1e-9);
verifyEqual(testCase, max(pulses.Block), testCase.TestData.sessionData.nTrials, ...
            'Each block is one Bpod trial');
end

function testTheSleepBarcodeIsRecorded(testCase)
session = testCase.TestData.sessionData.Session;
verifyEqual(testCase, session.Barcode.Kind, 'Sleep');
verifyFalse(testCase, session.Barcode.Sent);
started = datetime(session.StartTime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
verifyLessThan(testCase, abs(seconds(lum.sync.barcodeTime(session.Barcode.Value) - started)), 2);
verifyTrue(testCase, any(contains(session.DeviceLog.FlexIO, 'sleep barcode')));
end

function testTheProtocolFolderIsStillUsableAfterTheSession(testCase)
verifyEqual(testCase, exist('lum.sleep.Plots', 'class'), 8);
end


function sessionData = runSleepSession(testCase)
% Set BpodSystem up the way RunProtocol would, then run the protocol for real.
global BpodSystem %#ok<GVMIS>

root = fileparts(fileparts(mfilename('fullpath')));

S = lum.defaultSettings;
S.Session.Type = 'Sleep';
S.Sleep.DurationMinutes = testCase.TestData.durationSeconds / 60;
S.Sleep.Sync.Interval = testCase.TestData.interval;
S.Sleep.Sync.IntervalJitter = 0.05;

BpodSystem.ProtocolSettings = S;
BpodSystem.Data = struct;
BpodSystem.Status.BeingUsed = 1;
BpodSystem.Status.SessionStartFlag = 1;
BpodSystem.Status.Live = 1;
BpodSystem.Status.Pause = 0;
BpodSystem.Status.CurrentProtocolName = 'LuminoseFM';
BpodSystem.Status.CurrentSubjectName = 'testSubject';
BpodSystem.Path.ProtocolFolder = fileparts(root);
BpodSystem.Path.CurrentDataFile = fullfile(testCase.TestData.dataFolder, ...
                                           'testSubject_LuminoseFM_sleep_test.mat');

setappdata(0, 'LuminoseFM_Headless', true);

LuminoseFM;

% RunProtocol('Stop') took the protocol folder off the path on its way out.
addpath(root, fullfile(root, 'hardware'), fullfile(root, 'tests'));

loaded = load(BpodSystem.Path.CurrentDataFile);
sessionData = loaded.SessionData;
end
