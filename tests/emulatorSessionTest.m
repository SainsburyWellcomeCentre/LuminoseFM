function tests = emulatorSessionTest
% emulatorSessionTest runs a whole LuminoseFM session under Bpod('EMU').
%
% This is the test that holds the emulator-first requirement in place: the protocol
% must run end to end on a machine with no hardware, produce a complete and correctly
% structured data file, and mark it as emulated so it can never be mistaken for real
% behaviour. Everything else in the suite tests a part; this tests that the parts
% still work when wired together.
%
% The session runs with no pokes, so every trial ends in NoInitiation. That is
% deliberate. Driving the emulated ports from a MATLAB timer via ManualOverride
% re-enters the console's callback queue and stops the session part way through, as
% though somebody had pressed End. The choice, reward, punishment and hold-shaping
% paths are state machine structure, covered in stateMachineTest, and outcome scoring
% is covered in scoreTrialTest — both without that fragility. To exercise the poking
% paths interactively, run Bpod('EMU') and play the mouse with the console's port
% buttons, which is what emulator mode is for.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
ensureEmulator();
testCase.TestData.dataFolder = fullfile(tempdir, 'LuminoseFM_test_data');
if ~isfolder(testCase.TestData.dataFolder)
    mkdir(testCase.TestData.dataFolder);
end
testCase.TestData.nTrials = 6;
testCase.TestData.sessionData = runEmulatedSession(testCase);
end

function teardownOnce(testCase)
setappdata(0, 'LuminoseFM_Headless', false);
if isfolder(testCase.TestData.dataFolder)
    rmdir(testCase.TestData.dataFolder, 's');
end
end

function testTheSessionCompletesEveryTrial(testCase)
verifyEqual(testCase, testCase.TestData.sessionData.nTrials, testCase.TestData.nTrials, ...
            'The session must run every trial it was asked for');
end

function testTheDataFileIsMarkedAsEmulated(testCase)
sessionData = testCase.TestData.sessionData;
verifyEqual(testCase, sessionData.Info.EmulatorMode, true);
verifyTrue(testCase, sessionData.Session.Emulated);
end

function testTheDataFileSaysItIsABehaviourSession(testCase)
session = testCase.TestData.sessionData.Session;
verifyEqual(testCase, session.Type, 'Behaviour');
verifyEqual(testCase, session.Barcode.Kind, 'Behaviour');
verifyEqual(testCase, testCase.TestData.sessionData.HoldAttempts, ...
            zeros(1, testCase.TestData.sessionData.nTrials), 'No poke, no stimulus started');
end

function testEveryPerTrialSeriesIsTrimmedToTheTrialsThatRan(testCase)
sessionData = testCase.TestData.sessionData;
series = {'StimulusGroup', 'PatternIndex', 'CorrectSide', 'Choice', 'Correct', 'Rewarded', ...
          'Outcome', 'ReactionTime', 'OptoOn', 'SoundOn', 'SyncMode', 'SyncPulseWidth', ...
          'BiasTargetPLeft', 'TrainingStage', 'HoldDuration', 'HoldGrace', 'HoldBreaks', ...
          'HoldAttempts'};
for i = 1:numel(series)
    verifyTrue(testCase, isfield(sessionData, series{i}), sprintf('Data.%s is missing', series{i}));
    verifyLength(testCase, sessionData.(series{i}), sessionData.nTrials, ...
                 sprintf('Data.%s is not one value per trial', series{i}));
end
verifyLength(testCase, sessionData.TrialSettings, sessionData.nTrials);
end

function testTheStimulusSetIsStoredOnceAndIndexed(testCase)
% README §4.6: patterns live at session level and trials hold indices into them, so
% rewriting the file on an interval stays cheap.
sessionData = testCase.TestData.sessionData;
stimulusSet = sessionData.Session.StimulusSet;
verifyFalse(testCase, isfield(stimulusSet, 'States'), 'Preview states must not be stored');
verifyTrue(testCase, all(ismember(sessionData.PatternIndex, 1:stimulusSet.nPatterns)));
verifyEqual(testCase, sessionData.StimulusGroup, stimulusSet.PatternGroup(sessionData.PatternIndex));
end

function testPerTrialRecordsHoldOnlyTheRuntimeTier(testCase)
perTrial = testCase.TestData.sessionData.TrialSettings{1};
verifyFalse(testCase, isfield(perTrial, 'Stimulus'));
verifyTrue(testCase, isfield(perTrial, 'RewardAmount'));
end

function testTheSessionBarcodeIsRecorded(testCase)
% The emulator has no Flex I/O, so the barcode is recorded but not sent — and the
% device log says so.
session = testCase.TestData.sessionData.Session;
verifyFalse(testCase, session.Barcode.Sent);
started = datetime(session.StartTime, 'InputFormat', 'yyyy-MM-dd HH:mm:ss');
verifyLessThan(testCase, abs(seconds(lum.sync.barcodeTime(session.Barcode.Value) - started)), 2, ...
               'The barcode must decode to the session start');
verifyTrue(testCase, any(contains(session.DeviceLog.FlexIO, 'barcode')));
end

function testUnpokedTrialsAreScoredAsUninitiated(testCase)
sessionData = testCase.TestData.sessionData;
verifyEqual(testCase, sessionData.Outcome, repmat(lum.Outcome.NoInitiation, 1, sessionData.nTrials));
verifyTrue(testCase, all(isnan(sessionData.Choice)));
verifyEqual(testCase, sessionData.Rewarded, zeros(1, sessionData.nTrials));
end

function testTimingIsRecordedForEveryTrial(testCase)
sessionData = testCase.TestData.sessionData;
for field = {'prepare', 'send', 'plot', 'save'}
    verifyLength(testCase, sessionData.Timing.(field{1}), sessionData.nTrials);
end
verifyLessThan(testCase, max(sessionData.Timing.prepare), 1, ...
               'Preparing a trial should take well under a second');
end

function testDeviceLogsRecordWhatWouldHaveHappened(testCase)
verifyNotEmpty(testCase, testCase.TestData.sessionData.Session.DeviceLog.PulsePal, ...
               'The PulsePal shim should have logged the carrier it would have sent');
end

function testTheEmulatorGetsTheRunnerAndWindowItCanRun(testCase)
session = testCase.TestData.sessionData.Session;
verifyEqual(testCase, session.RunnerMode, 'blocking');
verifyEqual(testCase, session.RuntimeWindow, 'Compact');
end

function testStateNamesMatchTheTrialFlowContract(testCase)
states = fieldnames(testCase.TestData.sessionData.RawEvents.Trial{1}.States);
for name = {'TrialStart', 'WaitForCentrePoke', 'PreStimulusHold', 'CentreHold', 'HoldBreak', ...
            'WaitForCentreExit', 'WaitForResponse', 'NoInitiation', 'ITI'}
    verifyTrue(testCase, ismember(name{1}, states), sprintf('State %s is missing', name{1}));
end
end

function testTheProtocolFolderIsStillUsableAfterTheSession(testCase)
% LuminoseFM ends with RunProtocol('Stop'), which removes the protocol folder from the
% MATLAB path. If a lum.* object outlived that, the session's last act would be a
% destructor that cannot find its own class.
verifyEqual(testCase, exist('lum.Outcome', 'class'), 8);
end


function sessionData = runEmulatedSession(testCase)
% Set BpodSystem up the way RunProtocol would, then run the protocol for real.
global BpodSystem %#ok<GVMIS>

root = fileparts(fileparts(mfilename('fullpath')));

S = lum.defaultSettings;
S.Session.Type = 'Behaviour';
S.Session.MaxTrials = testCase.TestData.nTrials;
S.Session.SaveEveryNTrials = 2;
% Short everywhere, so the whole session takes seconds rather than minutes. The hold
% window is what each unpoked trial waits out, so it dominates.
S.Stimulus.Duration = 0.05;
S = withCue(S, {'CentreLight'});
S.GUI.HoldWindow = 0.2;
S.GUI.ResponseWindow = 0.2;
S.GUI.DrinkingGrace = 0.05;
S.GUI.PunishTimeout = 0.05;
S.GUI.ITI = 0.05;
S.GUI.RewardAmount = 1;

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
                                           'testSubject_LuminoseFM_test.mat');

setappdata(0, 'LuminoseFM_Headless', true);

LuminoseFM;

% RunProtocol('Stop') took the protocol folder off the path on its way out, which is
% correct on the rig but would leave the rest of the suite unable to resolve lum.*.
addpath(root, fullfile(root, 'hardware'), fullfile(root, 'tests'));

loaded = load(BpodSystem.Path.CurrentDataFile);
sessionData = loaded.SessionData;
end
