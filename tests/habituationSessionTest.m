function tests = habituationSessionTest
% habituationSessionTest runs a short habituation session end to end under Bpod('EMU').
%
% The first trial is played as the animal (startMouse): a centre poke held past the shaped
% hold, the withdrawal, and a side poke. It checks what the session script adds around the
% state machine for the centre reward: valve 2's time looked up in the prepare window (or
% the centre reward dropped, with a warning, when valve 2 has no calibration; which one this
% machine has decides what is checked), and the
% CentreReward, ResponseRetries and CentreHoldTime series in the data file.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
ensureEmulator();
testCase.TestData.dataFolder = tempname;
mkdir(testCase.TestData.dataFolder);
testCase.TestData.valve2 = valve2Calibrated();
testCase.TestData.sessionData = runHabituationSession(testCase);
end

function teardownOnce(testCase)
setappdata(0, 'LuminoseFM_Headless', false);
if isfolder(testCase.TestData.dataFolder)
    rmdir(testCase.TestData.dataFolder, 's');
end
end

function testThePlayedTrialIsRewardedAtTheSide(testCase)
data = testCase.TestData.sessionData;
verifyEqual(testCase, data.Rewarded(1), 1, 'Habituation pays either side');
verifyEqual(testCase, data.ResponseRetries(1), 0);
end

function testTheCentreRewardIsGivenWhenValveTwoIsCalibrated(testCase)
data = testCase.TestData.sessionData;
if testCase.TestData.valve2
    verifyEqual(testCase, data.CentreReward(1), 1, 'The centre reward, in uL');
    verifyFalse(testCase, isnan(data.RawEvents.Trial{1}.States.CentreReward(1)));
else
    verifyEqual(testCase, data.CentreReward(1), 0, 'No calibration, no centre reward');
    verifyTrue(testCase, isnan(data.RawEvents.Trial{1}.States.CentreReward(1)));
end
verifyEqual(testCase, data.CentreReward(2), 0, 'No hold completed on the unplayed trial');
end

function testTheCentreHoldTimeIsRecorded(testCase)
data = testCase.TestData.sessionData;
verifyGreaterThan(testCase, data.CentreHoldTime(1), 0.3, 'From the poke to leaving');
verifyTrue(testCase, isnan(data.CentreHoldTime(2)), 'No poke, no hold time');
end

function testShapingRanTheHoldFromItsStart(testCase)
data = testCase.TestData.sessionData;
verifyEqual(testCase, data.HoldDuration(1), data.Session.Settings.GUI.HoldStart, 'AbsTol', 1e-9);
end


function tf = valve2Calibrated()
try
    tf = GetValveTimes(1, 2) > 0;
catch
    tf = false;
end
end

function sessionData = runHabituationSession(testCase)
% Set BpodSystem up the way RunProtocol would, then run the protocol for real.
global BpodSystem %#ok<GVMIS>
root = fileparts(fileparts(mfilename('fullpath')));

S = lum.defaultSettings;
S.Session.Type = 'Behaviour';
S.Session.MaxTrials = 2;
S.Session.SaveEveryNTrials = 1;
S.Task.TrainingStage = 1;
S = lum.stageDefaults(S, 1);           % Air, no light, automatic shaping on
S.Stimulus.Duration = 0.2;
S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, 'Air')).Duration = 0.2;
S.GUI.HoldStart = 0.1;
S.GUI.HoldWindow = 3;
S.GUI.ResponseWindow = 3;
S.GUI.DrinkingGrace = 0.05;
S.GUI.ITI = 0.05;
S.GUI.RewardAmount = 1;
S.GUI.CentreRewardAmount = 1;
S.GUI.CentreRewardTrials = 10;
S.Camera.Enabled = false;
S.Doric.ShowWindow = false;

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
                                           'testSubject_LuminoseFM_habituation.mat');
setappdata(0, 'LuminoseFM_Headless', true);

% Trial 1 only: poke, hold past the shaped hold, withdraw, choose left.
mouse = startMouse({0.4, 'Port2', 1; 1.0, 'Port2', 0; 1.4, 'Port1', 1; 1.7, 'Port1', 0});
cleanup = onCleanup(@() delete(mouse));
LuminoseFM;
stop(mouse);
delete(cleanup);

addpath(root, fullfile(root, 'hardware'), fullfile(root, 'tests'));
loaded = load(BpodSystem.Path.CurrentDataFile);
sessionData = loaded.SessionData;
end
