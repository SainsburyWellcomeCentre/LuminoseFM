function tests = holdMeasuresTest
% holdMeasuresTest covers what the plots, the log and the runtime window say about a trial's
% centre hold (lum.holdMeasures, through lum.scoreTrial): whether it was completed, whether
% at the first attempt, and how many attempts it took. Built from the fixed state names
% alone, so no Bpod.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.rig = RigConfig;
end


%% Restart stimulus: early withdrawals, then a completed hold

function testAHoldCompletedAtTheFirstAttempt(testCase)
trial = completedAfter(0);
[measures, result] = measure(testCase, trial);
verifyEqual(testCase, measures, struct('Completed', 1, 'FirstAttempt', 1, 'Attempts', 1, ...
                                       'EarlyWithdrawals', 0));
verifyEqual(testCase, [result.HoldCompleted, result.HeldFirstAttempt], [1 1]);
verifyEqual(testCase, result.Outcome, lum.Outcome.Correct);
end

function testOneEarlyWithdrawalThenACompletedHold(testCase)
% The operator's view: the mouse withdrew, came back and held for the full time. The hold
% was completed; it was not held on the first attempt.
[measures, result] = measure(testCase, completedAfter(1));
verifyEqual(testCase, [measures.Completed, measures.FirstAttempt, measures.Attempts], [1 0 2]);
verifyEqual(testCase, [result.HoldCompleted, result.HeldFirstAttempt, result.EarlyWithdrawals], [1 0 1]);
verifyEqual(testCase, result.Outcome, lum.Outcome.Correct, 'Scored by its choice, not its withdrawals');
verifyEqual(testCase, result.HoldAttempts, measures.Attempts, 'Without a latency, as Data.HoldAttempts');
end

function testTwoEarlyWithdrawalsThenACompletedHold(testCase)
[measures, result] = measure(testCase, completedAfter(2));
verifyEqual(testCase, [measures.Completed, measures.FirstAttempt, measures.Attempts], [1 0 3]);
verifyEqual(testCase, result.HoldAttempts, 3);
end

function testEveryHoldBrokenUntilTheWindowRanOut(testCase)
trial = trialWith('CentreHold', [0.5 0.6; 1.0 1.1; 1.5 1.6], ...
                  'EarlyWithdrawal', [0.6 0.6; 1.1 1.1; 1.6 1.6], 'NoInitiation', [60 60]);
[measures, result] = measure(testCase, trial);
verifyEqual(testCase, [measures.Completed, measures.FirstAttempt, measures.Attempts], [0 0 3]);
verifyEqual(testCase, result.Outcome, lum.Outcome.HoldNotCompleted);
end


%% End trial, grace, no initiation, the centre reward, a latency

function testAnEarlyWithdrawalThatEndsTheTrialIsAFailedHold(testCase)
% S.Task.OnHoldBreak 'End trial': one attempt, and the trial ends on it.
trial = trialWith('CentreHold', [0.5 0.8], 'EarlyWithdrawal', [0.8 0.8], 'WaitForLightEnd', [0.8 0.8], ...
                  'ITI', [0.8 1.8]);
[measures, result] = measure(testCase, trial);
verifyEqual(testCase, [measures.Completed, measures.FirstAttempt, measures.Attempts], [0 0 1]);
verifyEqual(testCase, result.Outcome, lum.Outcome.EarlyWithdrawal);
end

function testAForgivenBreakIsNotAnEarlyWithdrawal(testCase)
trial = trialWith('CentreHold', [0.5 0.7], 'HoldBreak', [0.7 0.8], 'CentreHoldResumed', [0.8 1.2], ...
                  'WaitForCentreExit', [1.2 1.3], 'WaitForResponse', [1.3 1.5], ...
                  'LeftRewardDelay', [1.5 1.5], 'LeftReward', [1.5 1.6], 'Port1In', 1.5);
[measures, result] = measure(testCase, trial);
verifyEqual(testCase, measures, struct('Completed', 1, 'FirstAttempt', 1, 'Attempts', 1, ...
                                       'EarlyWithdrawals', 0));
verifyEqual(testCase, result.HoldBreaks, 1, 'The break is still counted as a forgiven one');
end

function testNoInitiationHasNoAttempt(testCase)
trial = trialWith('WaitForCentrePoke', [0.1 60.1], 'NoInitiation', [60.1 60.1]);
[measures, result] = measure(testCase, trial);
verifyEqual(testCase, [measures.Completed, measures.FirstAttempt, measures.Attempts], [0 0 0]);
verifyEqual(testCase, result.Outcome, lum.Outcome.NoInitiation);
end

function testTheCentreRewardFollowsACompletedHold(testCase)
trial = trialWith('CentreHold', [0.5 1.1], 'CentreReward', [1.1 1.15], 'WaitForCentreExit', [1.15 1.3]);
measures = measure(testCase, trial);
verifyEqual(testCase, measures.Completed, 1);
end

function testAWithdrawalDuringTheLatencyIsAnAttempt(testCase)
% With a latency, leaving before the stimulus starts is an early withdrawal without a
% visit to CentreHold: an attempt here, not in Data.HoldAttempts.
trial = trialWith('PreStimulusHold', [0.5 0.6; 1.0 1.2], 'EarlyWithdrawal', [0.6 0.6], ...
                  'CentreHold', [1.2 1.8], 'WaitForCentreExit', [1.8 1.9]);
[measures, result] = measure(testCase, trial);
verifyEqual(testCase, [measures.Completed, measures.FirstAttempt, measures.Attempts], [1 0 2]);
verifyEqual(testCase, result.HoldAttempts, 1, 'Data.HoldAttempts counts stimulus starts');
end


%% Helpers

function [measures, result] = measure(testCase, trial)
measures = lum.holdMeasures(trial.States);
result = lum.scoreTrial(trial, struct('CorrectSide', 1), testCase.TestData.rig);
end

function trial = completedAfter(nWithdrawals)
% Restart stimulus: nWithdrawals broken holds, then a completed one and a correct left choice.
starts = 0.5 * (1:nWithdrawals + 1)';
holds = [starts, starts + 0.1];
holds(end, 2) = holds(end, 1) + 0.6;
finish = holds(end, 2);
withdrawals = holds(1:nWithdrawals, 2);
parts = {'CentreHold', holds, 'WaitForCentreExit', [finish finish + 0.1], ...
             'WaitForResponse', [finish + 0.1, finish + 0.4], 'LeftRewardDelay', finish + [0.4 0.4], ...
             'LeftReward', finish + [0.4 0.5], 'Port1In', finish + 0.4};
if nWithdrawals > 0
    parts = [parts, {'EarlyWithdrawal', [withdrawals withdrawals]}];
end
trial = trialWith(parts{:});
end

function trial = trialWith(varargin)
% trialWith('State', visits, ..., 'PortNIn', times) builds a raw trial; a state's visits are
% one row each. Every other state the trial builder makes is there, unvisited.
names = {'TrialStart', 'WaitForCentrePoke', 'PreStimulusHold', 'CentreHold', 'HoldBreak', ...
         'CentreHoldResumed', 'WaitForCentreExit', 'WaitForResponse', 'EarlyWithdrawal', ...
         'LeftRewardDelay', 'RightRewardDelay', 'LeftReward', 'RightReward', 'DrinkingLeft', ...
         'DrinkingRight', 'DrinkingGrace', 'WithdrewBeforeReward', 'IncorrectChoice', ...
         'NoResponse', 'NoInitiation', 'WaitForLightEnd', 'ITI', 'CentreReward', 'RetryResponse'};
trial = struct('States', struct(), 'Events', struct());
for i = 1:numel(names)
    trial.States.(names{i}) = [NaN NaN];
end
for i = 1:2:numel(varargin)
    if endsWith(varargin{i}, 'In') || endsWith(varargin{i}, 'Out')
        trial.Events.(varargin{i}) = varargin{i + 1};
    else
        trial.States.(varargin{i}) = varargin{i + 1};
    end
end
end
