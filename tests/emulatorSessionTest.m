function tests = emulatorSessionTest
% emulatorSessionTest runs a whole LuminoseFM session under Bpod('EMU').
%
% This is the test that holds the emulator-first requirement in place: the protocol
% must run end to end on a machine with no hardware, produce a complete and correctly
% structured data file, and mark it as emulated so it can never be mistaken for real
% behaviour. Everything else in the suite tests a part; this tests that the parts
% still work when wired together.
%
% The session runs with no pokes, so every trial ends in NoInitiation: this test is about
% the session around the trials (every per-trial series, the LED current and a change of it
% from the LED window, a house light switch part way through, the plots image, the startup
% times, the summary plots and log).
% The choice, reward, punishment and hold-shaping paths are played as an animal in
% animalSessionTest (startSessionMouse), and built and scored in stateMachineTest and
% scoreTrialTest.
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
          'Outcome', 'ReactionTime', 'OptoOn', 'SoundOn', 'HouseLight', 'SyncMode', 'SyncPulseWidth', ...
          'BiasTargetPLeft', 'TrainingStage', 'HoldDuration', 'HoldGrace', 'HoldBreaks', ...
          'HoldAttempts', 'EarlyWithdrawals', 'CameraTime', 'LEDCurrentA', 'LEDCurrentB', ...
          'CentreReward', 'ResponseRetries', 'CentreHoldTime'};
for i = 1:numel(series)
    verifyTrue(testCase, isfield(sessionData, series{i}), sprintf('Data.%s is missing', series{i}));
    verifyLength(testCase, sessionData.(series{i}), sessionData.nTrials, ...
                 sprintf('Data.%s is not one value per trial', series{i}));
end
verifyLength(testCase, sessionData.TrialSettings, sessionData.nTrials);
end

function testEachTrialRecordsTheLEDCurrentItRanAt(testCase)
% The emulator's LED is the DoricLED package's simulated driver, set up at the currents
% the session's intensity gives (lum.led.intensity); B, never changed, ran at them on every
% trial. Without the package the LED is set by hand and the currents are unknown (NaN).
sessionData = testCase.TestData.sessionData;
record = sessionData.Session.DoricLED;
verifyEqual(testCase, record.Intensity.Type, 'Behaviour');
verifyEqual(testCase, record.Intensity.IrradiancemWmm2, record.Settings.IrradiancemWmm2);
if record.Controlled
    expected = record.Intensity.CurrentmA;
    verifyEqual(testCase, record.Mode, 'Simulated');
    verifyTrue(testCase, any(contains(sessionData.Session.DeviceLog.DoricLED, 'external TTL mode')));
else
    expected = [NaN NaN];
    verifyEqual(testCase, unique(sessionData.LEDCurrentA), expected(1));
end
verifyEqual(testCase, sessionData.LEDCurrentA(1), expected(1));
verifyEqual(testCase, unique(sessionData.LEDCurrentB), expected(2));
verifyEqual(testCase, [record.LightPaths.nFibers], [9 10], 'Blue on A, green on B');
end

function testALEDWindowChangeWaitsForTheRunningTrialToEnd(testCase)
% The next trial is uploaded while the running one may still be lit, so a current asked for
% from the LED window is sent once the running trial has ended, and the trial after it is
% uploaded only then (Data.Timing.devices): the only trial that starts late. Every other
% trial needed nothing from a device and was uploaded during the one before.
sessionData = testCase.TestData.sessionData;
record = sessionData.Session.DoricLED;
assumeTrue(testCase, record.Controlled, 'Without DoricLED the LED window cannot change the LED');
verifyTrue(testCase, testCase.TestData.requested, 'Apply was pressed during a trial');
first = find(sessionData.LEDCurrentA ~= sessionData.LEDCurrentA(1), 1);
verifyNotEmpty(testCase, first, 'A later trial ran at the new current');
verifyEqual(testCase, unique(sessionData.LEDCurrentA(first:end)), sessionData.LEDCurrentA(end));
changes = record.Device.Changes;
sent = changes(changes(:, 2) == 1 & changes(:, 4) > 0, :);
verifyEqual(testCase, sent(:, [3 4]), [sessionData.LEDCurrentA(first) first], ...
            'One change on A, sent for the trial that first ran at it');
waited = sessionData.Timing.devices > 0;
verifyEqual(testCase, find(waited), first - 1, ...
            'Only the trial before it waited, after its end, for the LED');
end

function testTheStimulusSetIsStoredOnceAndIndexed(testCase)
% docs/data-format.md: patterns live at session level and trials hold indices into them, so
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
% The emulator has no Flex I/O, so the barcode is recorded but not sent - and the
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
for field = {'prepare', 'send', 'devices', 'plot', 'save', 'memoryGB'}
    verifyLength(testCase, sessionData.Timing.(field{1}), sessionData.nTrials);
end
if ispc
    verifyGreaterThan(testCase, sessionData.Timing.memoryGB(end), 0, ...
                      'MATLAB''s memory is recorded as the session ends');
end
verifyLessThan(testCase, max(sessionData.Timing.prepare), 1, ...
               'Preparing a trial should take well under a second');
end

function testDeviceLogsRecordWhatWouldHaveHappened(testCase)
verifyNotEmpty(testCase, testCase.TestData.sessionData.Session.DeviceLog.PulsePal, ...
               'The PulsePal shim should have logged the carrier it would have sent');
end

function testASessionWithoutVideoSaysSo(testCase)
sessionData = testCase.TestData.sessionData;
verifyFalse(testCase, sessionData.Session.Cameras.Recorded);
verifyEqual(testCase, sessionData.Session.Cameras.Backend, 'none');
verifyTrue(testCase, all(isnan(sessionData.CameraTime)), 'No video, no camera clock');
end

function testTheHouseLightIsRecordedPerTrialAndForTheSession(testCase)
% It starts on, and the House light box in the plots is clicked off part way through a
% trial: PulsePal's output 3 goes to 0 V, the emulated loopback puts BNC1Low in that
% trial's events, and each trial's level is read from them (D15).
sessionData = testCase.TestData.sessionData;
verifyTrue(testCase, testCase.TestData.clicked, 'The box was clicked during a trial');
record = sessionData.Session.HouseLight;
verifyTrue(testCase, record.OnAtStart);
verifyFalse(testCase, record.OnAtEnd);
verifyEqual(testCase, record.Switches.On, false, 'One switch, off');
verifyEqual(testCase, {record.Input, record.OffEvent}, {'BNC1', 'BNC1Low'});
verifyNumElements(testCase, record.Edges.Time, 1, 'One edge on Bpod''s clock');
verifyFalse(testCase, record.Edges.On);
k = record.Edges.Trial;
verifyTrue(testCase, isfield(sessionData.RawEvents.Trial{k}.Events, 'BNC1Low'));
verifyEqual(testCase, record.Edges.Time, sessionData.TrialStartTimestamp(k) ...
            + sessionData.RawEvents.Trial{k}.Events.BNC1Low, 'AbsTol', 1e-9);
verifyEqual(testCase, sessionData.HouseLight, double((1:sessionData.nTrials) <= k), ...
            'On until the trial it was switched off in, off after');
verifyTrue(testCase, any(strcmp(sessionData.Session.DeviceLog.PulsePal, 'would set ch3 param 17 = 5')));
verifyTrue(testCase, any(strcmp(sessionData.Session.DeviceLog.PulsePal, 'would set ch3 param 17 = 0')));
verifyTrue(testCase, sessionData.Session.DevicesAvailable.HouseLight == false, 'Emulated');
end

function testThePlotsAreSavedAsAnImageBesideTheData(testCase)
sessionData = testCase.TestData.sessionData;
[folder, name] = fileparts(sessionData.Session.PlotsImage);
verifyEqual(testCase, name, 'testSubject_LuminoseFM_test_plots');
verifyEqual(testCase, folder, testCase.TestData.dataFolder);
verifyTrue(testCase, isfile(sessionData.Session.PlotsImage), 'The image must be written');
info = imfinfo(sessionData.Session.PlotsImage);
verifyGreaterThan(testCase, info.Width, 500);
end

function testTheSummaryPlotsAndLogAreWrittenAfterTheData(testCase)
% Beside the data folder, once the data file is saved (lum.report.write), so nothing in it
% depends on them.
folder = testCase.TestData.dataFolder;
plots = dir(fullfile(folder, 'Session Plots', '*_testSubject_LuminoseFM_test.png'));
verifyNumElements(testCase, plots, 12, strjoin({plots.name}, ', '));
verifyTrue(testCase, any(strcmp({plots.name}, '01_Outcomes_01_testSubject_LuminoseFM_test.png')));
logFile = fullfile(folder, 'Session Logs', 'testSubject_LuminoseFM_test_log.md');
verifyTrue(testCase, isfile(logFile));
verifySubstring(testCase, fileread(logFile), 'EMULATED');
data = dir(fullfile(folder, 'testSubject_LuminoseFM_test.mat'));
verifyLessThanOrEqual(testCase, data.datenum, min([plots.datenum]), ...
                      'The plots are drawn from the saved data, after it');
end

function testTheStartupIsTimedStepByStep(testCase)
% Where the time from launch to the first trial went, device by device.
startup = testCase.TestData.sessionData.Session.Startup;
names = {startup.Steps.Name};
verifyEqual(testCase, names, {'preflight', 'checks', 'devices', 'video start', 'sounds', ...
                              'windows', 'barcode', 'first trial'}, 'Headless: no dialogs');
verifyEqual(testCase, startup.TotalSeconds, sum([startup.Steps.Seconds]), 'AbsTol', 1e-9);
verifyEqual(testCase, startup.OperatorSeconds, 0);
verifyEqual(testCase, sort(fieldnames(startup.Parts.devices))', ...
            sort({'DoricLED', 'PulsePal', 'Cameras', 'HouseLight', 'HiFi', 'Flex'}));
end

function testTheEmulatorGetsTheRunnerAndWindowItCanRun(testCase)
session = testCase.TestData.sessionData.Session;
verifyEqual(testCase, session.RunnerMode, 'blocking');
verifyEqual(testCase, session.RuntimeWindow, 'Compact');
verifyEqual(testCase, session.TriggerStates, {'WaitForCentrePoke'});
end

function testStateNamesMatchTheTrialFlowContract(testCase)
states = fieldnames(testCase.TestData.sessionData.RawEvents.Trial{1}.States);
for name = {'TrialStart', 'WaitForCentrePoke', 'PreStimulusHold', 'CentreHold', 'HoldBreak', ...
            'WaitForCentreExit', 'WaitForResponse', 'NoInitiation', 'ITI', 'CentreReward', ...
            'RetryResponse'}
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
S.Session.HouseLight = true;  % And clicked off part way through (startHouseLightClicker)
S.Camera.Enabled = false;  % cameraTest runs a session with simulated cameras

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

% Off during the third trial or later, so trials run both ways; channel A's current changed
% from the LED window during the fourth trial or later.
clicker = startHouseLightClicker(@() isfield(BpodSystem.Data, 'nTrials') && BpodSystem.Data.nTrials >= 2);
requester = startLEDRequest(@() isfield(BpodSystem.Data, 'nTrials') && BpodSystem.Data.nTrials >= 3);
cleanup = onCleanup(@() delete([clicker requester]));
LuminoseFM;
stop([clicker requester]);
testCase.TestData.clicked = clicker.UserData.Clicked;
testCase.TestData.requested = requester.UserData.Requested;
delete(cleanup);

% RunProtocol('Stop') took the protocol folder off the path on its way out, which is
% correct on the rig but would leave the rest of the suite unable to resolve lum.*.
addpath(root, fullfile(root, 'hardware'), fullfile(root, 'tests'));

loaded = load(BpodSystem.Path.CurrentDataFile);
sessionData = loaded.SessionData;
end
