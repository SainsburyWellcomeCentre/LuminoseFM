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
for mode = lum.HoldShaping.modes()
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


function S = shaped(mode)
S = lum.defaultSettings;
S.Task.HoldShaping = mode;
end

function history = afterOneTrial(holdDuration, grace, outcome)
% A history holding one trial with this hold, grace and outcome.
history = lum.newHistory(5);
history.nTrials = 1;
history.holdDuration(1) = holdDuration;
history.holdGrace(1) = grace;
history.outcome(1) = outcome;
end
