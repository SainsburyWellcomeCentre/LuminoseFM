function tests = holdShapingTest
% holdShapingTest exercises centre-hold shaping: lum.HoldShaping.
%
% Shaping decides how long every trial's hold is and how long a break in it may be,
% trial after trial, from the outcomes that went before. Pure; no Bpod.
tests = functiontests(localfunctions);
end

function testOffHoldsForTheWholeWindowWithNoGrace(testCase)
S = lum.defaultSettings;
S.Stimulus.Duration = 0.8;
S.GUI.PostStimulusHold = 0.2;
[holdDuration, grace] = lum.HoldShaping.next(S, lum.newHistory(5));
verifyEqual(testCase, holdDuration, 1.0, 'AbsTol', 1e-12);
verifyEqual(testCase, grace, 0);
end

function testTheHoldIsDescribedFromWhereItsLengthComesFrom(testCase)
S = lum.defaultSettings;
S.Stimulus.Duration = 0.8;
S.GUI.PostStimulusHold = 0.2;
text = lum.HoldShaping.describeHold(S);
verifySubstring(testCase, text, '1 s, from the poke');
verifySubstring(testCase, text, 'stimulus window (0.8 s');
verifySubstring(testCase, lum.HoldShaping.describeHold(shaped('Grow hold')), 'Grows from');
S.Stimulus.Latency = 0.2;
verifySubstring(testCase, lum.HoldShaping.describeHold(S), '1.2 s, from the poke: the latency (0.2 s)');
end

function testGrowthStartsAtTheStartValue(testCase)
S = shaped('Grow hold');
verifyEqual(testCase, lum.HoldShaping.next(S, lum.newHistory(5)), S.GUI.HoldStart, ...
            'AbsTol', 1e-12);
end

function testGrowthFollowsOnlyCompletedHolds(testCase)
S = shaped('Grow hold');
S.GUI.HoldGrowth = 10;
for outcome = [lum.Outcome.Correct, lum.Outcome.Incorrect, lum.Outcome.NoResponse, ...
               lum.Outcome.CorrectNoReward]
    history = afterOneTrial(0.5, 0, outcome);
    verifyEqual(testCase, lum.HoldShaping.next(S, history), 0.55, 'AbsTol', 1e-9, ...
                sprintf('Outcome %s completed the hold', lum.Outcome.name(outcome)));
end
for outcome = [lum.Outcome.EarlyWithdrawal, lum.Outcome.NoInitiation]
    history = afterOneTrial(0.5, 0, outcome);
    verifyEqual(testCase, lum.HoldShaping.next(S, history), 0.5, 'AbsTol', 1e-9, ...
                sprintf('Outcome %s must hold the shaping where it is', lum.Outcome.name(outcome)));
end
end

function testGrowthStopsAtTheTarget(testCase)
S = shaped('Grow hold');
S.GUI.HoldGrowth = 50;
S.GUI.HoldTarget = 0.6;
history = afterOneTrial(0.5, 0, lum.Outcome.Correct);
verifyEqual(testCase, lum.HoldShaping.next(S, history), 0.6, 'AbsTol', 1e-12);
end

function testLoweringTheTargetMidSessionTakesEffectAtOnce(testCase)
S = shaped('Grow hold');
S.GUI.HoldTarget = 0.3;
history = afterOneTrial(0.8, 0, lum.Outcome.EarlyWithdrawal);
verifyEqual(testCase, lum.HoldShaping.next(S, history), 0.3, 'AbsTol', 1e-12);
end

function testGraceShrinksAfterCompletedHoldsDownToItsTarget(testCase)
S = shaped('Shrink grace');
S.GUI.GraceStart = 0.4;
S.GUI.GraceShrink = 50;
S.GUI.GraceTarget = 0.15;
[holdDuration, grace] = lum.HoldShaping.next(S, lum.newHistory(5));
verifyEqual(testCase, grace, 0.4, 'AbsTol', 1e-12);
verifyEqual(testCase, holdDuration, S.Stimulus.Duration + S.GUI.PostStimulusHold, ...
            'AbsTol', 1e-12, 'Grace alone does not shorten the hold');

[~, grace] = lum.HoldShaping.next(S, afterOneTrial(1, 0.4, lum.Outcome.Correct));
verifyEqual(testCase, grace, 0.2, 'AbsTol', 1e-12);
[~, grace] = lum.HoldShaping.next(S, afterOneTrial(1, 0.2, lum.Outcome.Correct));
verifyEqual(testCase, grace, 0.15, 'AbsTol', 1e-12);
end

function testBothShapeTogether(testCase)
S = shaped('Both');
[holdDuration, grace] = lum.HoldShaping.next(S, lum.newHistory(5));
verifyEqual(testCase, holdDuration, S.GUI.HoldStart, 'AbsTol', 1e-12);
verifyEqual(testCase, grace, S.GUI.GraceStart, 'AbsTol', 1e-12);
end

function testValuesAreQuantisedToTheCycle(testCase)
S = shaped('Grow hold');
S.GUI.HoldGrowth = 3.3333;
holdDuration = lum.HoldShaping.next(S, afterOneTrial(0.123456, 0, lum.Outcome.Correct));
verifyEqual(testCase, holdDuration, round(holdDuration * 1e4) / 1e4, 'AbsTol', 1e-12);
end

function testOnlyGraceCostsAGlobalTimer(testCase)
rig = struct('Limits', struct('GlobalTimers', 16), 'Available', struct('Sync', false));
for mode = [{'Off'}, lum.HoldShaping.modes()]
    S = shaped(mode{1});
    [~, reserved] = lum.timerBudget(S, rig);
    verifyEqual(testCase, reserved.HoldClock, double(lum.HoldShaping.hasGrace(mode{1})), mode{1});
end
end

function testABrokenHoldRestartsTheStimulusByDefault(testCase)
S = lum.defaultSettings;
modes = lum.HoldShaping.breakModes();
verifyEqual(testCase, S.Task.OnHoldBreak, modes{1});
verifyTrue(testCase, lum.HoldShaping.restartsOnBreak(S));
verifySubstring(testCase, lum.HoldShaping.describeBreak(S), 'restarts');
S.Task.OnHoldBreak = 'End trial';
verifyFalse(testCase, lum.HoldShaping.restartsOnBreak(S));
verifySubstring(testCase, lum.HoldShaping.describeBreak(S), 'ends the trial');
end

function testEarlyWithdrawalOpensThePrepareWindowOnlyWhenItEndsTheTrial(testCase)
% A restarted hold can deliver light straight after EarlyWithdrawal, so preparing the
% next trial there would put USB traffic inside the stimulus.
S = lum.defaultSettings;
verifyFalse(testCase, ismember('EarlyWithdrawal', lum.triggerStates(S)));
verifyTrue(testCase, all(ismember({'LeftReward', 'RightReward', 'IncorrectChoice', ...
    'NoResponse', 'NoInitiation', 'WithdrewBeforeReward'}, lum.triggerStates(S))));
S.Task.OnHoldBreak = 'End trial';
verifyTrue(testCase, ismember('EarlyWithdrawal', lum.triggerStates(S)));
end

function testDescribeSaysWhatShapingDoes(testCase)
verifySubstring(testCase, lum.HoldShaping.describe(shaped('Grow hold')), 'grows');
verifySubstring(testCase, lum.HoldShaping.describe(shaped('Shrink grace')), 'global timer');
verifySubstring(testCase, lum.HoldShaping.describe(shaped('Off')), 'whole stimulus window');
end


function testShapingIsOffByDefaultAndGrowsTheHoldWhenSwitchedOn(testCase)
S = lum.defaultSettings;
verifyFalse(testCase, S.Task.AutoShaping, 'Automatic shaping is off by default');
verifyEqual(testCase, lum.HoldShaping.activeMode(S), 'Off');
verifyEqual(testCase, S.Task.HoldShaping, 'Grow hold', 'Grow hold is the default method');
verifyEqual(testCase, [S.GUI.HoldStart, S.GUI.HoldTarget, S.GUI.HoldStepBackAfter], [0.1 1 10]);
S.Task.AutoShaping = true;
verifyEqual(testCase, lum.HoldShaping.activeMode(S), 'Grow hold');
verifyEqual(testCase, lum.HoldShaping.next(S, lum.newHistory(5)), 0.1, 'AbsTol', 1e-12);
end

function testTheMethodIsIgnoredWhileShapingIsOff(testCase)
S = lum.defaultSettings;
S.Task.HoldShaping = 'Both';
[holdDuration, grace] = lum.HoldShaping.next(S, lum.newHistory(5));
verifyEqual(testCase, holdDuration, S.Stimulus.Duration + S.GUI.PostStimulusHold, 'AbsTol', 1e-12);
verifyEqual(testCase, grace, 0);
end

function testTooManyEarlyWithdrawalsStepTheHoldBack(testCase)
% Ten withdrawals at one hold, with no completed hold in between, step it back one
% growth step; fewer hold it where it is.
S = shaped('Grow hold');
S.GUI.HoldGrowth = 10;
history = withdrawals(0.55, 9);
[holdDuration, ~, steppedBack] = lum.HoldShaping.next(S, history);
verifyEqual(testCase, holdDuration, 0.55, 'AbsTol', 1e-9);
verifyFalse(testCase, steppedBack);
history = withdrawals(0.55, 10);
[holdDuration, ~, steppedBack] = lum.HoldShaping.next(S, history);
verifyEqual(testCase, holdDuration, 0.5, 'AbsTol', 1e-9, 'One growth step back');
verifyTrue(testCase, steppedBack);
S.GUI.HoldStepBackAfter = 0;
verifyEqual(testCase, lum.HoldShaping.next(S, history), 0.55, 'AbsTol', 1e-9, '0 never steps back');
end

function testTheHoldNeverStepsBackBelowItsStart(testCase)
S = shaped('Grow hold');
[holdDuration, ~, steppedBack] = lum.HoldShaping.next(S, withdrawals(S.GUI.HoldStart, 50));
verifyEqual(testCase, holdDuration, S.GUI.HoldStart, 'AbsTol', 1e-12);
verifyFalse(testCase, steppedBack);
end

function testWithdrawalsAreCountedPerHoldAndForgivenByACompletedHold(testCase)
% A restarted trial that ends in a completed hold clears the count; a new hold starts
% it again; a trial that lapses adds every withdrawal in it.
history = lum.newHistory(10);
spec = struct('PatternIndex', 1, 'StimulusGroup', 1, 'CorrectSide', 1, 'HoldDuration', 0.5, ...
              'HoldGrace', 0);
lapsed = struct('Choice', NaN, 'Correct', NaN, 'Rewarded', 0, 'ReactionTime', NaN, ...
                'Outcome', lum.Outcome.HoldNotCompleted, 'HoldBreaks', 0, 'HoldAttempts', 4, ...
                'EarlyWithdrawals', 4);
history = lum.updateHistory(history, 1, spec, lapsed);
history = lum.updateHistory(history, 2, spec, lapsed);
verifyEqual(testCase, history.withdrawalsAtHold, 8);
completed = lapsed;
completed.Outcome = lum.Outcome.Correct;
completed.EarlyWithdrawals = 2;
history = lum.updateHistory(history, 3, spec, completed);
verifyEqual(testCase, history.withdrawalsAtHold, 0, 'A completed hold clears the count');
history = lum.updateHistory(history, 4, spec, lapsed);
spec.HoldDuration = 0.45;
history = lum.updateHistory(history, 5, spec, lapsed);
verifyEqual(testCase, history.withdrawalsAtHold, 4, 'A new hold starts the count again');
end

function testTheTrialStillRunningCannotStepTheHoldBackTwice(testCase)
% Trial n+1 is prepared from trial n-1: when n+1 stepped back, n (still at the old hold)
% can add withdrawals, but n+2 steps back from n's hold to the same value, not further.
S = shaped('Grow hold');
S.GUI.HoldGrowth = 10;
history = withdrawals(0.55, 12);
first = lum.HoldShaping.next(S, history);
history.nTrials = 2;
history.holdDuration(2) = 0.55;
history.outcome(2) = lum.Outcome.EarlyWithdrawal;
history.withdrawalsAtHold = 13;
verifyEqual(testCase, lum.HoldShaping.next(S, history), first, 'AbsTol', 1e-12);
end

function testASettingsFileWithoutShapingMigratesToTheSwitch(testCase)
old = lum.defaultSettings;
old.Task = rmfield(old.Task, 'AutoShaping');
old.Task.HoldShaping = 'Off';
[S, changed] = lum.mergeSettings(lum.defaultSettings, old);
verifyFalse(testCase, S.Task.AutoShaping);
verifyEqual(testCase, S.Task.HoldShaping, 'Grow hold');
verifyTrue(testCase, any(contains(changed, 'AutoShaping')));
old.Task.HoldShaping = 'Shrink grace';
S = lum.mergeSettings(lum.defaultSettings, old);
verifyTrue(testCase, S.Task.AutoShaping, 'A file that shaped keeps shaping');
verifyEqual(testCase, S.Task.HoldShaping, 'Shrink grace');
end

function testTrainingSwitchesShapingOnAndExperimentOff(testCase)
S = lum.stageDefaults(lum.defaultSettings, 2);
verifyTrue(testCase, S.Task.AutoShaping);
S = lum.stageDefaults(S, 3);
verifyFalse(testCase, S.Task.AutoShaping);
S.Task.AutoShaping = true;
S.Task.TrainingStage = 3;
S.Session.MaxTrials = 20;
verifyError(testCase, @() lum.validateSettings(S, RigConfig), ...
            'lum:validateSettings:shapingInExperiment');
end


function S = shaped(mode)
S = lum.defaultSettings;
S.Task.AutoShaping = ~strcmp(mode, 'Off');
if ~strcmp(mode, 'Off')
    S.Task.HoldShaping = mode;
end
end

function history = withdrawals(holdDuration, n)
% A history whose last trial lapsed at this hold, with n early withdrawals counted.
history = afterOneTrial(holdDuration, 0, lum.Outcome.HoldNotCompleted);
history.withdrawalsAtHold = n;
end

function history = afterOneTrial(holdDuration, grace, outcome)
% A history holding one trial with this hold, grace and outcome.
history = lum.newHistory(5);
history.nTrials = 1;
history.holdDuration(1) = holdDuration;
history.holdGrace(1) = grace;
history.outcome(1) = outcome;
end
