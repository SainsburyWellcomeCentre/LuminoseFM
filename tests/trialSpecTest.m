function tests = trialSpecTest
% trialSpecTest exercises trial generation: lum.nextTrialSpec and the history helpers.
%
% This is the task's policy — following the stimulus order, contingency, bias
% correction, run limits, training stage, hold shaping — and it is pure, so it can be
% tested exhaustively without an animal.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
S = lum.defaultSettings;
S.Task.MaxSameSide = 0;     % Off unless a test asks for it
S.GUI.BiasCorrection = 0;   % Off unless a test asks for it
S.Session.MaxTrials = 2000;
S.Stimulus.Generator.Seed = 11;
testCase.TestData.S = S;
testCase.TestData.set = lum.pattern.stimulusSet(S, 16, 2);
end

function testWithoutPoliciesTheOrderIsFollowedExactly(testCase)
[S, stimulusSet] = fixture(testCase);
queue = stimulusSet.TrialPattern;
history = lum.newHistory(300);
for trial = 1:300
    [spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, trial);
    verifyEqual(testCase, spec.PatternIndex, stimulusSet.TrialPattern(trial));
end
verifyEqual(testCase, queue, stimulusSet.TrialPattern, 'Nothing may reorder the queue');
end

function testTheContingencyIsRespected(testCase)
% Group 1 pays left and group 2 right, so the rewarded side is determined.
[S, stimulusSet] = fixture(testCase);
queue = stimulusSet.TrialPattern;
history = lum.newHistory(200);
for trial = 1:200
    [spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, trial);
    verifyEqual(testCase, spec.CorrectSide, spec.StimulusGroup);
end
end

function testPsychometricGroupsDrawTheirSide(testCase)
S = testCase.TestData.S;
S.Stimulus.Generator.nGroups = 1;
S.Task.GroupPLeft = 0.7;
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
queue = stimulusSet.TrialPattern;
history = lum.newHistory(10);
rng(3);
sides = zeros(1, 2000);
for trial = 1:2000
    spec = lum.nextTrialSpec(S, stimulusSet, queue, history, trial);
    sides(trial) = spec.CorrectSide;
end
verifyEqual(testCase, mean(sides == 1), 0.7, 'AbsTol', 0.04);
end

function testBiasCorrectionPushesAgainstTheAnimalsPreference(testCase)
% An animal that always chooses left should be offered more right-rewarded trials.
% Correction reorders a balanced session, so it can front-load the avoided side only
% as far as the next 50 trials supply it: tested over the stretch where it can.
[S, stimulusSet] = fixture(testCase);
S.GUI.BiasCorrection = 1;
S.GUI.BiasWindow = 20;
history = leftBiasedHistory();
queue = stimulusSet.TrialPattern;
rng(4);
sides = zeros(1, 40);
for i = 1:40
    [spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, 20 + i);
    sides(i) = spec.CorrectSide;
end
verifyGreaterThan(testCase, mean(sides == 2), 0.7, ...
    'Bias correction should mostly offer the side the animal is avoiding');
end

function testBiasCorrectionOnlyReordersTheSession(testCase)
% Swapping trials must never add or remove one: every group is still delivered
% exactly as often as the generator balanced it.
[S, stimulusSet] = fixture(testCase);
S.GUI.BiasCorrection = 1;
history = leftBiasedHistory();
queue = stimulusSet.TrialPattern;
delivered = zeros(1, 1000);
rng(5);
for trial = 1:1000
    [spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, trial);
    delivered(trial) = spec.PatternIndex;
end
verifyEqual(testCase, sort(queue), sort(stimulusSet.TrialPattern));
verifyEqual(testCase, delivered, queue(1:1000));
end

function testBiasCorrectionIsOffWhenStrengthIsZero(testCase)
[S, stimulusSet] = fixture(testCase);
history = leftBiasedHistory();
queue = stimulusSet.TrialPattern;
for i = 1:500
    [spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, 20 + i);
    verifyEqual(testCase, spec.BiasTargetPLeft, 0.5);
end
verifyEqual(testCase, queue, stimulusSet.TrialPattern);
end

function testBiasCorrectionNeverStarvesOneSide(testCase)
[S, stimulusSet] = fixture(testCase);
S.GUI.BiasCorrection = 1;
history = leftBiasedHistory();
queue = stimulusSet.TrialPattern;
rng(6);
sides = zeros(1, 1500);
for i = 1:1500
    [spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, 20 + i);
    sides(i) = spec.CorrectSide;
end
% p(left) is clamped to [0.1, 0.9], so the avoided side keeps appearing.
verifyGreaterThan(testCase, mean(sides == 1), 0.03);
end

function testTheRunLimitBreaksLongSameSideRuns(testCase)
[S, stimulusSet] = fixture(testCase);
S.Task.MaxSameSide = 3;
history = lum.newHistory(100);
history.nTrials = 3;
history.correctSide(1:3) = 2;   % Three right-rewarded trials in a row
queue = stimulusSet.TrialPattern;
for trial = 4:60
    spec = lum.nextTrialSpec(S, stimulusSet, queue, history, trial);
    verifyEqual(testCase, spec.CorrectSide, 1, 'The run limit must force the other side');
    verifyEqual(testCase, spec.StimulusGroup, 1, ...
                'The stimulus must stay consistent with the forced side');
end
end

function testTheRunLimitIsInactiveBelowItsThreshold(testCase)
[S, stimulusSet] = fixture(testCase);
S.Task.MaxSameSide = 3;
history = lum.newHistory(100);
history.nTrials = 2;
history.correctSide(1:2) = 2;
queue = stimulusSet.TrialPattern;
for trial = 3:40
    [spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, trial);
    verifyEqual(testCase, spec.PatternIndex, stimulusSet.TrialPattern(trial));
end
end

function testHabituationRewardsBothSides(testCase)
[S, stimulusSet] = fixture(testCase);
S.Task.TrainingStage = 1;
spec = lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, lum.newHistory(10), 1);
verifyEqual(testCase, sort(spec.RewardedSides), [1 2]);
end

function testLaterStagesRewardOnlyTheCorrectSide(testCase)
[S, stimulusSet] = fixture(testCase);
S.Task.TrainingStage = 3;
spec = lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, lum.newHistory(10), 1);
verifyEqual(testCase, spec.RewardedSides, spec.CorrectSide);
end

function testLightFollowsBothTheSessionAndTheRuntimeSwitch(testCase)
[S, stimulusSet] = fixture(testCase);
queue = stimulusSet.TrialPattern;
S.GUI.OptoOn = 1;
verifyTrue(testCase, lum.nextTrialSpec(S, stimulusSet, queue, lum.newHistory(10), 1).OptoOn);
S.GUI.OptoOn = 0;
verifyFalse(testCase, lum.nextTrialSpec(S, stimulusSet, queue, lum.newHistory(10), 1).OptoOn);
S.GUI.OptoOn = 1;
S.Session.UseOpto = false;
verifyFalse(testCase, lum.nextTrialSpec(S, stimulusSet, queue, lum.newHistory(10), 1).OptoOn);
end

function testTheHoldComesFromHoldShaping(testCase)
[S, stimulusSet] = fixture(testCase);
S.Task.HoldShaping = 'Both';
spec = lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, lum.newHistory(10), 1);
verifyEqual(testCase, spec.HoldDuration, S.GUI.HoldStart, 'AbsTol', 1e-12);
verifyEqual(testCase, spec.HoldGrace, S.GUI.GraceStart, 'AbsTol', 1e-12);
end

function testAFixedWidthSyncPulseIsTheSameEveryTrial(testCase)
[S, stimulusSet] = fixture(testCase);
S.Sync.Mode = lum.SyncMode.FixedWidth;
S.Sync.FixedWidth = 0.02;
for trial = 1:50
    spec = lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, lum.newHistory(10), trial);
    verifyEqual(testCase, spec.SyncPulseWidth, 0.02);
    verifyEqual(testCase, spec.SyncMode, lum.SyncMode.FixedWidth);
end
end

function testAJitteredSyncPulseStaysWithinItsJitterAndAveragesTheMean(testCase)
% The point of the mode is that the width identifies the trial, so the widths have
% to spread; the point of naming it a mean is that it is one.
[S, stimulusSet] = fixture(testCase);
S.Sync.Mode = lum.SyncMode.JitteredWidth;
S.Sync.MeanWidth = 0.055;
S.Sync.WidthJitter = 0.045;
rng(9);
widths = zeros(1, 2000);
for trial = 1:numel(widths)
    spec = lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, lum.newHistory(10), trial);
    widths(trial) = spec.SyncPulseWidth;
end
verifyGreaterThanOrEqual(testCase, min(widths), 0.010 - 1e-12);
verifyLessThanOrEqual(testCase, max(widths), 0.100 + 1e-12);
verifyEqual(testCase, mean(widths), 0.055, 'AbsTol', 0.003);
verifyGreaterThan(testCase, numel(unique(widths)), 1900, 'Widths that repeat cannot identify a trial');
end

function testTaskEventSyncAsksForNoPulse(testCase)
[S, stimulusSet] = fixture(testCase);
S.Sync.Mode = lum.SyncMode.TaskEvents;
spec = lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, lum.newHistory(10), 1);
verifyTrue(testCase, isnan(spec.SyncPulseWidth));
end

function testAnUnknownSyncModeIsRejected(testCase)
[S, stimulusSet] = fixture(testCase);
S.Sync.Mode = 7;
verifyError(testCase, @() lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, ...
            lum.newHistory(10), 1), 'lum:nextTrialSpec:unknownSyncMode');
end

function testATrialPastTheOrderIsRejected(testCase)
[S, stimulusSet] = fixture(testCase);
verifyError(testCase, @() lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern(1:5), ...
            lum.newHistory(10), 6), 'lum:nextTrialSpec:queueExhausted');
end

function testHistoryRecordsATrial(testCase)
history = lum.newHistory(10);
spec = struct('PatternIndex', 2, 'StimulusGroup', 2, 'CorrectSide', 1, ...
              'HoldDuration', 0.6, 'HoldGrace', 0.1);
result = struct('Choice', 1, 'Correct', 1, 'Rewarded', 1, 'Outcome', lum.Outcome.Correct, ...
                'ReactionTime', 0.4, 'HoldBreaks', 2, 'HoldAttempts', 3);
history = lum.updateHistory(history, 1, spec, result);
verifyEqual(testCase, history.nTrials, 1);
verifyEqual(testCase, [history.choice(1), history.correct(1), history.reactionTime(1)], [1 1 0.4]);
verifyEqual(testCase, [history.holdDuration(1), history.holdGrace(1), history.holdBreaks(1), ...
                       history.holdAttempts(1)], [0.6 0.1 2 3]);
verifyTrue(testCase, isnan(history.choice(2)), 'Future trials must stay blank');
end

function testHistoryRefusesToOverrunItsCapacity(testCase)
history = lum.newHistory(2);
spec = struct('PatternIndex', 1, 'StimulusGroup', 1, 'CorrectSide', 1, 'HoldDuration', 1, ...
              'HoldGrace', 0);
result = struct('Choice', 1, 'Correct', 1, 'Rewarded', 1, 'Outcome', 3, 'ReactionTime', 0, ...
                'HoldBreaks', 0, 'HoldAttempts', 1);
verifyError(testCase, @() lum.updateHistory(history, 3, spec, result), ...
            'lum:updateHistory:overCapacity');
end


function [S, stimulusSet] = fixture(testCase)
S = testCase.TestData.S;
stimulusSet = testCase.TestData.set;
end

function history = leftBiasedHistory()
% Twenty trials on which the animal chose left every time.
history = lum.newHistory(100);
history.nTrials = 20;
history.choice(1:20) = 1;
history.correctSide(1:20) = [1 2 1 2 1 2 1 2 1 2 1 2 1 2 1 2 1 2 1 2];
end
