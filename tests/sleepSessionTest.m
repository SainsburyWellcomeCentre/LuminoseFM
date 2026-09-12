function tests = sleepSessionTest
% sleepSessionTest runs whole sleep sessions under Bpod('EMU').
%
% The sleep counterpart of emulatorSessionTest: LuminoseFM, launched headless with
% S.Session.Type 'Sleep', must run its barcode and blocks end to end on a machine with no
% hardware, and write a data file that says it is an emulated sleep session and records
% every pulse it would have sent. It runs twice: sync pulses alone, and with test pulses
% on channels A and B — probes, a plasticity train, probes on one channel — through the
% emulator's PulsePal shim.
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

S = baseSettings(testCase);
S.Sleep.DurationMinutes = testCase.TestData.durationSeconds / 60;
testCase.TestData.sessionData = runSleepSession(testCase, S, 'testSubject_LuminoseFM_sleep_test.mat');

S = withTestPulses(baseSettings(testCase));
testCase.TestData.lightPlan = lum.sleep.testPulsePlan(S.Sleep.TestPulses);
testCase.TestData.lightSessionData = runSleepSession(testCase, S, ...
                                                     'testSubject_LuminoseFM_sleep_light_test.mat');
end

function teardownOnce(testCase)
setappdata(0, 'LuminoseFM_Headless', false);
if isfolder(testCase.TestData.dataFolder)
    rmdir(testCase.TestData.dataFolder, 's');
end
end

%% Sync pulses alone ----------------------------------------------------------------

function testTheSessionIsRecordedAsAnEmulatedSleepSession(testCase)
sessionData = testCase.TestData.sessionData;
verifyEqual(testCase, sessionData.Session.Type, 'Sleep');
verifyEqual(testCase, sessionData.Info.EmulatorMode, true);
verifyTrue(testCase, sessionData.Session.Emulated);
verifyFalse(testCase, sessionData.Session.SyncSent, 'The emulator has no sync line');
verifyFalse(testCase, isfield(sessionData, 'Outcome'), 'A sleep session has no trials to score');
verifyFalse(testCase, isfield(sessionData, 'LightSegments'), 'No test pulses, no light record');
verifyFalse(testCase, sessionData.Session.TestPulses.Enabled);
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

function testASessionWithoutTestPulsesNeverOpensPulsePal(testCase)
log = testCase.TestData.sessionData.Session.DeviceLog.PulsePal;
verifyTrue(testCase, any(contains(log, 'optogenetic stimulus disabled')));
verifyFalse(testCase, any(contains(log, 'would set')), 'Nothing is programmed');
end

%% With test pulses -----------------------------------------------------------------

function testEveryGateOfLightIsSentAsPlanned(testCase)
sessionData = testCase.TestData.lightSessionData;
plan = testCase.TestData.lightPlan;
light = sessionData.LightSegments;
verifyEqual(testCase, numel(light.Onset), size(plan.Segments, 1), 'Every gate of light is sent');
verifyEqual(testCase, light.Channel, plan.Segments(:, 3)');
verifyEqual(testCase, light.Step, plan.Segments(:, 4)');
verifyEqual(testCase, light.Epoch, plan.Segments(:, 5)');
verifyEqual(testCase, light.Duration, plan.Segments(:, 2)' * 1e-4, 'AbsTol', 1e-9);
verifyEqual(testCase, [nnz(light.Step == 1), nnz(light.Step == 2), nnz(light.Step == 3)], [24 6 6], ...
            'Six pairs on A and B, two trains of three bursts, three pairs on A');
verifyGreaterThanOrEqual(testCase, min(diff(light.Onset)), -1e-6, 'Onsets in order');
verifyTrue(testCase, sessionData.Session.TestPulses.Completed);
verifyEmpty(testCase, sessionData.Session.TestPulses.StoppedReason);
verifyNumElements(testCase, sessionData.Session.TestPulses.Steps, 3);
end

function testAPairOfProbesKeepsItsOrderAndChannels(testCase)
% The emulator runs its states from a MATLAB loop and keeps no millisecond time, so an
% emulated interval can only be checked from below: a state never ends before its timer.
% The exact 50 ms is the state machine's own clock on the rig (sleepTest checks the plan).
light = testCase.TestData.lightSessionData.LightSegments;
onA = light.Onset(light.Step == 1 & light.Channel == 1);
pairs = reshape(onA, 2, []);
verifyGreaterThanOrEqual(testCase, diff(pairs), 0.05 - 1e-3, ...
                         'The second pulse no sooner than 50 ms after the first');
verifyLessThan(testCase, diff(pairs), 0.5, 'Both pulses within their epoch');
onB = light.Onset(light.Step == 1 & light.Channel == 2);
verifyEqual(testCase, onB, onA, 'AbsTol', 1e-6, 'A and B together');
trains = light.Channel(light.Step == 2);
verifyEqual(testCase, trains, [1 1 1 2 2 2], 'Alternate trains on A, then B');
end

function testPulsePalIsProgrammedForEachStepAndChecked(testCase)
sessionData = testCase.TestData.lightSessionData;
log = sessionData.Session.DeviceLog.PulsePal;
verifyTrue(testCase, any(contains(log, 'would stop ch1')), 'Outputs stopped on opening');
verifyTrue(testCase, any(strcmp(log, 'would check that PulsePal answers a handshake')));
verifyTrue(testCase, any(strcmp(log, 'would set ch1 param 2 = 3')), 'Channel A''s LED drive');
verifyTrue(testCase, any(strcmp(log, 'would set ch2 param 2 = 4')), 'Channel B''s LED drive');
verifyTrue(testCase, any(strcmp(log, 'would set ch1 param 4 = 0.11')), 'Constant light for probes');
verifyTrue(testCase, any(strcmp(log, 'would set ch1 param 4 = 0.005')), 'The train''s pulse width');
verifyTrue(testCase, any(strcmp(log, 'would set ch1 param 128 = 2')), 'Gated');
verifyFalse(testCase, sessionData.Session.DevicesAvailable.PulsePal, 'The emulator has no PulsePal');
verifyEqual(testCase, max(sessionData.LightSegments.Block), sessionData.nTrials);
end

function testTheProtocolFolderIsStillUsableAfterTheSession(testCase)
verifyEqual(testCase, exist('lum.sleep.Plots', 'class'), 8);
end


function S = baseSettings(testCase)
S = lum.defaultSettings;
S.Session.Type = 'Sleep';
S.Sleep.Sync.Interval = testCase.TestData.interval;
S.Sleep.Sync.IntervalJitter = 0.05;
end

function S = withTestPulses(S)
% 6.5 s: probes on A and B every 0.5 s, two short trains alternating A and B, probes on A.
tp = S.Sleep.TestPulses;
tp.Enabled = true;
tp.Voltage = [3 4];
tp.Probe.InterEpochInterval = 0.5;
tp.PlasticityTrains = true;
tp.Trains(end + 1) = struct('Name', 'Test train', 'PulseFrequency', 50, 'PulseWidth', 0.005, ...
                            'PulsesPerBurst', 2, 'BurstFrequency', 5, 'BurstsPerTrain', 3, ...
                            'nTrains', 2, 'TrainInterval', 1);
tp.Schedule = struct('Kind', {'Probe', 'Test train', 'Probe'}, ...
                     'Channels', {'A and B', 'Alternate A and B', 'A'}, 'Minutes', {0.05, 0, 0.025});
S.Sleep.TestPulses = tp;
end

function sessionData = runSleepSession(testCase, S, fileName)
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
