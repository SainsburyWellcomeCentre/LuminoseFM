function tests = animalSessionTest
% animalSessionTest plays whole behaviour sessions as an animal, and rebuilds every trial
% from the saved file alone.
%
% Three sessions run through LuminoseFM under Bpod('EMU'), each trial played by
% startSessionMouse with a behaviour chosen to reach one outcome path:
%   training     restarts on a broken hold, wrong choices retried (the defaults): correct,
%                retried, withdrawn then completed, no poke, every hold broken, no side
%                poke, never leaving the centre port, rapid pokes while drinking; the ITI
%                and the reward are changed from the runtime window part way through
%   punished     a broken hold ends the trial, both mistakes punished with timeout and
%                noise, a latency and a reward delay: correct after the delay, leaving
%                before it, leaving in the latency, leaving in the hold, a punished wrong
%                choice, no poke
%   habituation  grow hold and shrink grace together (automatic shaping, 'Both'), the
%                centre reward on the first trials, forgiven and unforgiven breaks, and
%                enough early withdrawals to step the hold back
% Each saved trial is then checked against what its behaviour must give, re-scored from
% its raw events, and its timing compared with the settings it records (TrialSettings,
% HoldDuration, HoldGrace, the stimulus set). The emulator keeps no millisecond time, so
% durations are checked from below and within a loose bound above.
%
% Takes about two minutes.
%
% See also: startSessionMouse, emulatorSessionTest, stateMachineTest
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
ensureEmulator();
testCase.TestData.root = fileparts(fileparts(mfilename('fullpath')));
testCase.TestData.folder = tempname;
mkdir(testCase.TestData.folder);
[testCase.TestData.training, testCase.TestData.trainingLog] = ...
    runSession(testCase, 'training', trainingSettings(), trainingBehaviours());
[testCase.TestData.punished, testCase.TestData.punishedLog] = ...
    runSession(testCase, 'punished', punishedSettings(), punishedBehaviours());
[testCase.TestData.habituation, testCase.TestData.habituationLog] = ...
    runSession(testCase, 'habituation', habituationSettings(), habituationBehaviours());
end

function teardownOnce(testCase)
setappdata(0, 'LuminoseFM_Headless', false);
if isfolder(testCase.TestData.folder)
    rmdir(testCase.TestData.folder, 's');
end
end

%% Training: the defaults' paths

function testTrainingOutcomesFollowTheAnimal(testCase)
data = testCase.TestData.training;
O = @(name) lum.Outcome.(name);
expected = [O('Correct'), O('Incorrect'), O('Correct'), O('NoInitiation'), ...
            O('HoldNotCompleted'), O('NoResponse'), O('NoResponse'), O('Correct'), O('Correct')];
verifyEqual(testCase, data.nTrials, numel(expected));
verifyEqual(testCase, data.Outcome, expected);
verifyEqual(testCase, data.Rewarded, [1 1 1 0 0 0 0 1 1], 'A retried trial is rewarded');
verifyEqual(testCase, data.ResponseRetries, [0 1 0 0 0 0 0 0 0]);
verifyEqual(testCase, data.HoldAttempts, [1 1 2 0 2 1 1 1 1]);
verifyEqual(testCase, data.EarlyWithdrawals, [0 0 1 0 2 0 0 0 0]);
verifyEqual(testCase, data.Correct(2), 0, 'The first choice is the one scored');
verifyTrue(testCase, all(isnan(data.Choice([4 5 6 7]))), 'No side poke, no choice');
end

function testTrainingTimesAreThoseTheAnimalMade(testCase)
data = testCase.TestData.training;
verifyEqual(testCase, data.CentreHoldTime(1), 1.0, 'AbsTol', 0.2, 'Poked at 0.3 s, left at 1.3 s');
verifyEqual(testCase, data.ReactionTime(1), 0.4, 'AbsTol', 0.2, 'Left at 1.3 s, chose at 1.7 s');
verifyTrue(testCase, isnan(data.CentreHoldTime(4)), 'No poke');
verifyTrue(testCase, isnan(data.CentreHoldTime(7)), 'Never left the centre port');
end

function testTrainingRuntimeChangesAreRecordedForTheTrialsTheyRan(testCase)
% The ITI was typed as 1.5 s during trial 2, so trial 3 is the first prepared with it.
data = testCase.TestData.training;
itiTyped = cellfun(@(s) s.ITI, data.TrialSettings);
verifyEqual(testCase, itiTyped, [0.2 0.2 1.5 1.5 1.5 1.5 1.5 1.5 1.5], ...
            'TrialSettings{k} is what trial k was prepared with');
rewardTyped = cellfun(@(s) s.RewardAmount, data.TrialSettings);
verifyEqual(testCase, rewardTyped, [3 3 6 6 6 6 6 6 6], ...
            '40 uL typed during trial 4 is beyond the calibration: the reward stays at 6');
verifySubstring(testCase, testCase.TestData.trainingLog, 'The reward stays at 6 uL');
for k = 1:data.nTrials
    iti = diff(data.RawEvents.Trial{k}.States.ITI(end, :));
    verifyGreaterThanOrEqual(testCase, iti, itiTyped(k) - 1e-3, sprintf('Trial %d ITI', k));
    verifyLessThan(testCase, iti, itiTyped(k) + 0.25, sprintf('Trial %d ITI', k));
end
end

function testTrainingLightFollowsItsPatternForEveryCompletedHold(testCase)
verifyLightFollowsPattern(testCase, testCase.TestData.training);
end

function testTrainingHoldsLastTheStimulusWindow(testCase)
data = testCase.TestData.training;
verifyEqual(testCase, data.HoldDuration, 0.5 * ones(1, data.nTrials), 'AbsTol', 1e-9, ...
            'No shaping: the stimulus window plus the post-stimulus hold, every trial');
verifyCompletedHoldsLastTheirHold(testCase, data);
end

%% Punished: end trial, timeout and noise, latency, reward delay

function testPunishedOutcomesFollowTheAnimal(testCase)
data = testCase.TestData.punished;
O = @(name) lum.Outcome.(name);
expected = [O('Correct'), O('CorrectNoReward'), O('EarlyWithdrawal'), O('EarlyWithdrawal'), ...
            O('Incorrect'), O('NoInitiation')];
verifyEqual(testCase, data.Outcome, expected);
verifyEqual(testCase, data.Rewarded, [1 0 0 0 0 0]);
verifyEqual(testCase, data.HoldAttempts, [1 1 0 1 1 0], 'Leaving in the latency never starts the stimulus');
verifyEqual(testCase, data.ResponseRetries, zeros(1, 6), 'A punished wrong choice is not retried');
end

function testPunishmentsLastTheTimeoutAndTheNoise(testCase)
data = testCase.TestData.punished;
S = data.Session.Settings;
atLeast = max(S.GUI.PunishTimeout, S.Sound.NoiseDuration);
for k = [3 4]
    span = data.RawEvents.Trial{k}.States.EarlyWithdrawal(1, :);
    verifyGreaterThanOrEqual(testCase, diff(span), atLeast - 1e-3, sprintf('Trial %d', k));
    verifyTrue(testCase, isnan(data.RawEvents.Trial{k}.States.WaitForResponse(1)), 'The trial ended');
end
span = data.RawEvents.Trial{5}.States.IncorrectChoice(1, :);
verifyGreaterThanOrEqual(testCase, diff(span), atLeast - 1e-3);
end

function testTheLatencyAndTheRewardDelayAreHeld(testCase)
data = testCase.TestData.punished;
S = data.Session.Settings;
for k = [1 2 5]
    states = data.RawEvents.Trial{k}.States;
    verifyGreaterThanOrEqual(testCase, diff(states.PreStimulusHold(1, :)), S.Stimulus.Latency - 1e-3);
    verifyLessThan(testCase, diff(states.PreStimulusHold(1, :)), S.Stimulus.Latency + 0.2);
end
delay = data.RawEvents.Trial{1}.States;
side = {'LeftRewardDelay', 'RightRewardDelay'};
span = delay.(side{data.CorrectSide(1)})(1, :);
verifyGreaterThanOrEqual(testCase, diff(span), S.GUI.RewardDelay - 1e-3);
verifyCompletedHoldsLastTheirHold(testCase, data);
verifyLightFollowsPattern(testCase, data);
end

%% Habituation: shaping and the centre reward

function testHabituationOutcomesFollowTheAnimal(testCase)
data = testCase.TestData.habituation;
verifyEqual(testCase, data.HoldBreaks(1), 1, 'The break within the grace is forgiven');
verifyEqual(testCase, data.EarlyWithdrawals(1:2), [0 1], 'The break beyond it is not');
verifyEqual(testCase, data.HoldAttempts(2), 2, 'The next poke restarts the stimulus');
verifyEqual(testCase, data.Rewarded([1 2 3 4 5]), [1 1 1 1 1], 'Habituation pays either side');
verifyEqual(testCase, data.Outcome([6 7 8]), lum.Outcome.HoldNotCompleted * [1 1 1]);
end

function testTheCentreRewardIsGivenOnlyOnItsTrials(testCase)
data = testCase.TestData.habituation;
S = data.Session.Settings;
assumeGreaterThan(testCase, S.GUI.CentreRewardAmount, 0, 'Valve 2 has no liquid calibration here');
verifyEqual(testCase, data.CentreReward(1:5), [1 1 0 0 0] * S.GUI.CentreRewardAmount, ...
            'Trials 1 and 2 (CentreRewardTrials), each with a completed hold');
valveTime = GetValveTimes(S.GUI.CentreRewardAmount, 2);
for k = 1:2
    span = data.RawEvents.Trial{k}.States.CentreReward(1, :);
    verifyGreaterThanOrEqual(testCase, diff(span), valveTime - 1e-3);
    verifyLessThan(testCase, diff(span), valveTime + 0.15);
end
end

function testShapingGrowsOnceForEveryCompletedHold(testCase)
% Trial k+1 is prepared while trial k runs, so it follows trial k-1's outcome, from trial
% k's hold: one growth step per completed hold, one step back after HoldStepBackAfter
% early withdrawals, never below the start or above the target.
data = testCase.TestData.habituation;
S = data.Session.Settings;
[hold, grace] = expectedShaping(S, data.Outcome, data.EarlyWithdrawals);
verifyEqual(testCase, data.HoldDuration, hold, 'AbsTol', 1e-4);
verifyEqual(testCase, data.HoldGrace, grace, 'AbsTol', 1e-4);
verifyEqual(testCase, data.HoldDuration(1:5), [0.6 0.6 0.72 0.864 1], 'AbsTol', 1e-4, ...
            'Grows 20% per completed hold, lagging one trial, up to the 1 s target');
verifyLessThan(testCase, min(data.HoldDuration(9:end)), 1, 'Stepped back after the withdrawals');
end

%% Every session

function testEverySavedTrialRescoresToWhatWasSaved(testCase)
for name = {'training', 'punished', 'habituation'}
    data = testCase.TestData.(name{1});
    for k = 1:data.nTrials
        spec = struct('CorrectSide', data.CorrectSide(k));
        result = lum.scoreTrial(data.RawEvents.Trial{k}, spec, data.Session.Rig);
        what = sprintf('%s trial %d', name{1}, k);
        verifyEqual(testCase, result.Outcome, data.Outcome(k), what);
        verifyEqual(testCase, result.Choice, data.Choice(k), what);
        verifyEqual(testCase, result.Rewarded, data.Rewarded(k), what);
        verifyEqual(testCase, result.HoldAttempts, data.HoldAttempts(k), what);
    end
end
end

function testEveryTrialRecordsItsStimulusAndSettings(testCase)
for name = {'training', 'punished', 'habituation'}
    data = testCase.TestData.(name{1});
    set = data.Session.StimulusSet;
    verifyEqual(testCase, data.StimulusGroup, set.PatternGroup(data.PatternIndex), name{1});
    pLeft = set.PatternPLeft(data.PatternIndex);
    paysLeft = data.CorrectSide == 1;
    verifyTrue(testCase, all(pLeft(paysLeft) > 0) && all(pLeft(~paysLeft) < 1), ...
               [name{1} ': every trial pays a side its pattern can pay']);
    verifyEqual(testCase, numel(data.TrialSettings), data.nTrials, name{1});
    verifyEqual(testCase, data.TrainingStage, data.Session.Settings.Task.TrainingStage * ones(1, data.nTrials));
end
end

function testNoSessionWarnedOrFailed(testCase)
for name = {'training', 'punished', 'habituation'}
    log = testCase.TestData.([name{1} 'Log']);
    % The one warning expected: the training session's refused reward
    log = regexprep(log, 'Warning: The reward stays at 6 uL[^\n]*', '');
    verifyEmpty(testCase, regexp(log, 'Warning:', 'once'), [name{1} ': ' log]);
    verifyEqual(testCase, testCase.TestData.(name{1}).Session.StoppedReason, '', name{1});
end
end


%% Sessions ---------------------------------------------------------------------

function S = baseSettings()
S = lum.defaultSettings;
S.Session.Type = 'Behaviour';
S.Session.SaveEveryNTrials = 2;
S.Session.RuntimeWindow = 'Compact';
S.Session.HouseLight = false;
S.Camera.Enabled = false;
S.Doric.ShowWindow = false;
S.Stimulus.Duration = 0.5;
S.Task.TrainingStage = 2;
S.Task.AutoShaping = false;
S.Task.MaxSameSide = 0;
S.GUI.BiasCorrection = 0;
S.GUI.DrinkingGrace = 0.5;
S.GUI.ITI = 0.2;
S.GUI.RewardAmount = 3;
S.Stimulus.Generator.NewSeedEachSession = false;
S.Stimulus.Generator.Seed = 7;
end

function S = trainingSettings()
S = baseSettings();
S.Session.MaxTrials = 9;
S.GUI.HoldWindow = 3;
S.GUI.ResponseWindow = 1.2;
end

function behaviours = trainingBehaviours()
correct = {0.3, 'Centre', 1; 1.3, 'Centre', 0; 1.7, 'Correct', 1; 2.1, 'Correct', 0};
retry = {0.3, 'Centre', 1; 0.9, 'Set:ITI', 1.5; 1.0, 'Set:RewardAmount', 6; 1.3, 'Centre', 0; ...
         1.7, 'Wrong', 1; 2.0, 'Wrong', 0; 2.4, 'Correct', 1; 2.8, 'Correct', 0};
withdrawThenComplete = {0.3, 'Centre', 1; 0.5, 'Centre', 0; 1.0, 'Centre', 1; 2.0, 'Centre', 0; ...
                        2.4, 'Correct', 1; 2.8, 'Correct', 0};
allBroken = {0.3, 'Centre', 1; 0.45, 'Centre', 0; 1.0, 'Centre', 1; 1.15, 'Centre', 0};
noResponse = {0.3, 'Centre', 1; 1.3, 'Centre', 0};
staysInCentre = {0.3, 'Centre', 1};
rapidWhileDrinking = {0.3, 'Centre', 1; 1.3, 'Centre', 0; 1.7, 'Correct', 1; 1.9, 'Correct', 0; ...
                      2.1, 'Correct', 1; 2.3, 'Correct', 0; 2.5, 'Wrong', 1; 2.7, 'Wrong', 0};
typesTooMuch = {0.5, 'Set:RewardAmount', 40};   % Beyond the calibration: refused
behaviours = {correct, retry, withdrawThenComplete, typesTooMuch, allBroken, noResponse, staysInCentre, ...
              rapidWhileDrinking, correct};
end

function S = punishedSettings()
S = baseSettings();
S.Session.MaxTrials = 6;
S.Task.OnHoldBreak = 'End trial';
S.Stimulus.Latency = 0.3;
S.GUI.HoldWindow = 3;
S.GUI.ResponseWindow = 1.2;
S.GUI.RewardDelay = 0.4;
S.GUI.PunishCondition = 4;   % Both
S.GUI.PunishType = 3;        % Timeout + noise
S.GUI.PunishTimeout = 0.3;
S.Sound.NoiseDuration = 0.5;
end

function behaviours = punishedBehaviours()
correctAfterDelay = {0.3, 'Centre', 1; 1.5, 'Centre', 0; 1.9, 'Correct', 1; 2.7, 'Correct', 0};
leavesBeforeReward = {0.3, 'Centre', 1; 1.5, 'Centre', 0; 1.9, 'Correct', 1; 2.1, 'Correct', 0};
leavesInLatency = {0.3, 'Centre', 1; 0.45, 'Centre', 0};
leavesInHold = {0.3, 'Centre', 1; 0.9, 'Centre', 0};
wrong = {0.3, 'Centre', 1; 1.5, 'Centre', 0; 1.9, 'Wrong', 1; 2.2, 'Wrong', 0};
behaviours = {correctAfterDelay, leavesBeforeReward, leavesInLatency, leavesInHold, wrong, {}};
end

function S = habituationSettings()
S = baseSettings();
S.Session.MaxTrials = 11;
S = lum.stageDefaults(S, 1);           % Air instead of light; shaping on
S.Task.TrainingStage = 1;
S.Task.HoldShaping = 'Both';
S.Stimulus.Duration = 1;
S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, 'Air')).Duration = 1;
S.GUI.HoldStart = 0.6;
S.GUI.HoldGrowth = 20;
S.GUI.HoldTarget = 1;
S.GUI.HoldStepBackAfter = 3;
S.GUI.GraceStart = 0.25;
S.GUI.GraceShrink = 50;
S.GUI.GraceTarget = 0;
S.GUI.HoldWindow = 2.5;
S.GUI.ResponseWindow = 1.2;
S.GUI.CentreRewardAmount = 1;
S.GUI.CentreRewardTrials = 2;
if ~valve2Calibrated()
    S.GUI.CentreRewardAmount = 0;   % This machine cannot give it; its test is skipped
end
end

function behaviours = habituationBehaviours()
breakWithinGrace = {0.3, 'Centre', 1; 0.5, 'Centre', 0; 0.65, 'Centre', 1; 1.6, 'Centre', 0; ...
                    2.0, 'Port1', 1; 2.3, 'Port1', 0};
breakBeyondGrace = {0.3, 'Centre', 1; 0.45, 'Centre', 0; 1.3, 'Centre', 1; 2.5, 'Centre', 0; ...
                    2.9, 'Port1', 1; 3.2, 'Port1', 0};
complete = {0.3, 'Centre', 1; 1.6, 'Centre', 0; 2.0, 'Port1', 1; 2.3, 'Port1', 0};
allBroken = {0.3, 'Centre', 1; 0.4, 'Centre', 0; 1.0, 'Centre', 1; 1.1, 'Centre', 0};
behaviours = {breakWithinGrace, breakBeyondGrace, complete, complete, complete, ...
              allBroken, allBroken, allBroken, complete, complete, complete};
end

function tf = valve2Calibrated()
try
    tf = lum.valveTimes(1, 2) > 0;
catch
    tf = false;
end
end

function [data, log] = runSession(testCase, name, S, behaviours)
% Set BpodSystem up the way RunProtocol would, then run the protocol with the animal.
global BpodSystem %#ok<GVMIS>
root = testCase.TestData.root;
BpodSystem.ProtocolSettings = S;
BpodSystem.Data = struct;
BpodSystem.Status.BeingUsed = 1;
BpodSystem.Status.SessionStartFlag = 1;
BpodSystem.Status.Live = 1;
BpodSystem.Status.Pause = 0;
BpodSystem.Status.CurrentProtocolName = 'LuminoseFM';
BpodSystem.Status.CurrentSubjectName = 'testAnimal';
BpodSystem.Path.ProtocolFolder = fileparts(root);
BpodSystem.Path.CurrentDataFile = fullfile(testCase.TestData.folder, ...
                                           sprintf('testAnimal_LuminoseFM_%s.mat', name));
setappdata(0, 'LuminoseFM_Headless', true);
mouse = startSessionMouse(behaviours);
cleanup = onCleanup(@() delete(mouse));
log = evalc('LuminoseFM');
stop(mouse);
played = mouse.UserData;
delete(cleanup);
expected = cellfun(@(b) size(b, 1), behaviours);
assert(isempty(played.Error), 'The animal failed on %s: %s', name, played.Error);
assert(isequal(played.Played, expected), 'The animal played %s of %s rows on %s', ...
       mat2str(played.Played), mat2str(expected), name);
addpath(root, fullfile(root, 'hardware'), fullfile(root, 'tests'));
loaded = load(BpodSystem.Path.CurrentDataFile);
data = loaded.SessionData;
end


%% Checks -----------------------------------------------------------------------

function verifyCompletedHoldsLastTheirHold(testCase, data)
% Without grace the hold is CentreHold's own timer: every completed hold lasted it.
for k = 1:data.nTrials
    states = data.RawEvents.Trial{k}.States;
    if isnan(states.WaitForCentreExit(1))
        continue
    end
    span = states.CentreHold(end, :);
    verifyGreaterThanOrEqual(testCase, diff(span), data.HoldDuration(k) - 1e-3, sprintf('Trial %d', k));
    verifyLessThan(testCase, diff(span), data.HoldDuration(k) + 0.2, sprintf('Trial %d', k));
end
end

function verifyLightFollowsPattern(testCase, data)
% From the saved file alone: the trial's pattern (PatternIndex into the stored stimulus
% set) gives one global timer per light segment, triggered with the last hold; each ends
% at its onset plus duration.
set = data.Session.StimulusSet;
nChecked = 0;
for k = 1:data.nTrials
    trial = data.RawEvents.Trial{k};
    if ~data.OptoOn(k) || isnan(trial.States.WaitForCentreExit(1))
        continue
    end
    holdStart = trial.States.CentreHold(end, 1);
    rows = set.SegmentStart(data.PatternIndex(k)):set.SegmentStart(data.PatternIndex(k) + 1) - 1;
    segments = set.Segments(rows, :);
    for i = 1:size(segments, 1)
        name = sprintf('GlobalTimer%d_End', i);
        verifyTrue(testCase, isfield(trial.Events, name), sprintf('Trial %d segment %d', k, i));
        ends = trial.Events.(name);
        ends = ends(ends >= holdStart);
        verifyNotEmpty(testCase, ends, sprintf('Trial %d segment %d', k, i));
        if ~isempty(ends)
            planned = holdStart + segments(i, 3) + segments(i, 4);
            verifyGreaterThanOrEqual(testCase, ends(1), planned - 1e-3, sprintf('Trial %d segment %d', k, i));
            verifyLessThan(testCase, ends(1), planned + 0.2, sprintf('Trial %d segment %d', k, i));
        end
        nChecked = nChecked + 1;
    end
end
verifyGreaterThan(testCase, nChecked, 0, 'At least one trial delivered light');
end

function [hold, grace] = expectedShaping(S, outcome, earlyWithdrawals)
% The holds and graces automatic shaping should have given, trial by trial, in the order
% the session prepares them: trial k+1 while trial k runs, from trial k-1's outcome.
n = numel(outcome);
g = 1 + S.GUI.HoldGrowth / 100;
shrink = 1 - S.GUI.GraceShrink / 100;
hold = NaN(1, n);
grace = NaN(1, n);
count = 0;   % Early withdrawals at the hold in force, since it last changed or was completed
for k = 1:n
    known = k - 2;   % The last trial recorded when trial k was prepared
    if k == 1
        hold(k) = S.GUI.HoldStart;
        grace(k) = S.GUI.GraceStart;
        continue
    end
    hold(k) = hold(k - 1);
    grace(k) = grace(k - 1);
    if known >= 1
        if lum.HoldShaping.completedHold(outcome(known))
            hold(k) = hold(k - 1) * g;
            grace(k) = grace(k - 1) * shrink;
        elseif count >= S.GUI.HoldStepBackAfter && abs(hold(known) - hold(k - 1)) < 5e-5
            hold(k) = hold(k - 1) / g;
        end
    end
    hold(k) = round(min(max(hold(k), S.GUI.HoldStart), S.GUI.HoldTarget) / 1e-4) * 1e-4;
    grace(k) = round(max(min(grace(k), S.GUI.GraceStart), S.GUI.GraceTarget) / 1e-4) * 1e-4;
    % Record trial k-1 into the count, as lum.updateHistory does once k-1 ends
    if k >= 2
        done = k - 1;
        if done > 1 && abs(hold(done) - hold(done - 1)) > 5e-5
            count = 0;
        end
        if lum.HoldShaping.completedHold(outcome(done))
            count = 0;
        else
            count = count + earlyWithdrawals(done);
        end
    end
end
end
