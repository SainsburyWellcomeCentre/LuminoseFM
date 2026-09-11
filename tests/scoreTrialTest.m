function tests = scoreTrialTest
% scoreTrialTest exercises outcome classification: lum.scoreTrial.
%
% The scorer reads only the fixed state names and port events that lum.buildTrialSM
% guarantees, so these tests build those structures directly and need no Bpod.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.rig = RigConfig;
end

function testACorrectLeftChoiceIsScoredAndRewarded(testCase)
trial = makeTrial('WaitForResponse', [1.0 1.3], 'LeftRewardDelay', [1.3 1.3], ...
                  'LeftReward', [1.3 1.4], 'Port1In', 1.3);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.Correct);
verifyEqual(testCase, [result.Choice, result.Correct, result.Rewarded], [1 1 1]);
verifyEqual(testCase, result.ReactionTime, 0.3, 'AbsTol', 1e-9);
end

function testAnIncorrectChoiceIsScoredAndNotRewarded(testCase)
trial = makeTrial('WaitForResponse', [1.0 1.2], 'IncorrectChoice', [1.2 3.2], 'Port3In', 1.2);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.Incorrect);
verifyEqual(testCase, [result.Choice, result.Correct, result.Rewarded], [2 0 0]);
end

function testTheFirstSidePokeWinsWhenBothPortsAreVisited(testCase)
trial = makeTrial('WaitForResponse', [1.0 1.5], 'IncorrectChoice', [1.5 2.0], ...
                  'Port3In', 1.2, 'Port1In', 1.4);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Choice, 2, 'The earlier poke is the choice');
end

function testPokesBeforeTheResponseWindowAreIgnored(testCase)
% A nose poked into a side port during the stimulus must not count as a choice.
trial = makeTrial('WaitForResponse', [1.0 1.4], 'LeftRewardDelay', [1.4 1.4], ...
                  'LeftReward', [1.4 1.5], 'Port3In', 0.4, 'Port1In', 1.4);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Choice, 1);
verifyEqual(testCase, result.ReactionTime, 0.4, 'AbsTol', 1e-9);
end

function testAnEarlyWithdrawalIsItsOwnOutcome(testCase)
% With 'End trial', the break ends the trial straight after EarlyWithdrawal.
trial = makeTrial('CentreHold', [0.5 0.8], 'EarlyWithdrawal', [0.8 0.8], 'ITI', [0.8 1.8]);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.EarlyWithdrawal);
verifyEqual(testCase, result.HoldAttempts, 1);
verifyTrue(testCase, isnan(result.Choice));
verifyTrue(testCase, isnan(result.Correct), 'An unmade choice cannot be scored');
end

function testAnUninitiatedTrialIsItsOwnOutcome(testCase)
trial = makeTrial('WaitForCentrePoke', [0.1 60.1], 'NoInitiation', [60.1 60.1]);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.NoInitiation);
verifyEqual(testCase, result.HoldAttempts, 0);
end

function testLeavingDuringTheLatencyIsABrokenHold(testCase)
% The stimulus never started, so no hold attempt; ending the trial, it is an early
% withdrawal, and restarting until the window runs out, a trial never initiated.
trial = makeTrial('WaitForCentrePoke', [0.1 1.0], 'PreStimulusHold', [1.0 1.1], ...
                  'EarlyWithdrawal', [1.1 1.1]);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.EarlyWithdrawal);
verifyEqual(testCase, result.HoldAttempts, 0);
trial.States.NoInitiation = [60.1 60.1];
verifyEqual(testCase, lum.scoreTrial(trial, spec(1), testCase.TestData.rig).Outcome, ...
            lum.Outcome.NoInitiation);
end

function testARestartedHoldThatIsCompletedIsScoredByItsChoice(testCase)
% The first hold broke and restarted the stimulus; the second was completed.
trial = makeTrial('WaitForCentreExit', [2.5 2.7], 'WaitForResponse', [2.7 3.0], ...
                  'LeftRewardDelay', [3.0 3.0], 'LeftReward', [3.0 3.1], 'Port1In', 3.0);
trial.States.CentreHold = [0.5 0.8; 1.5 2.5];
trial.States.EarlyWithdrawal = [0.8 0.8];
trial.States.WaitForCentrePoke = [0.1 0.45; 0.8 1.45];
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.Correct);
verifyEqual(testCase, result.HoldAttempts, 2);
verifyEqual(testCase, result.ReactionTime, 0.3, 'AbsTol', 1e-9);
end

function testHoldsThatAllBrokeBeforeTheWindowRanOutAreNotCompleted(testCase)
trial = makeTrial('NoInitiation', [60.0 60.0]);
trial.States.CentreHold = [0.5 0.8; 1.5 1.7; 3.0 3.1];
trial.States.EarlyWithdrawal = [0.8 0.8; 1.7 1.7; 3.1 3.1];
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.HoldNotCompleted);
verifyEqual(testCase, result.HoldAttempts, 3);
verifyEqual(testCase, result.Rewarded, 0);
end

function testAnExpiredResponseWindowIsNoResponse(testCase)
trial = makeTrial('WaitForResponse', [1.0 11.0], 'NoResponse', [11.0 11.0]);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.NoResponse);
verifyEqual(testCase, result.Rewarded, 0);
end

function testNeverLeavingTheCentrePortIsANoResponse(testCase)
trial = makeTrial('CentreHold', [0.5 1.5], 'WaitForCentreExit', [1.5 11.5], ...
                  'NoResponse', [11.5 11.5]);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.NoResponse);
verifyTrue(testCase, isnan(result.Choice));
end

function testReactionTimeIsMeasuredFromTheWithdrawalNotTheEndOfTheHold(testCase)
trial = makeTrial('CentreHold', [0.5 1.5], 'WaitForCentreExit', [1.5 1.8], ...
                  'WaitForResponse', [1.8 2.1], 'LeftRewardDelay', [2.1 2.1], ...
                  'LeftReward', [2.1 2.2], 'Port2Out', 1.8, 'Port1In', 2.1);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.ReactionTime, 0.3, 'AbsTol', 1e-9);
end

function testLeavingTheRewardPortEarlyIsScoredSeparately(testCase)
trial = makeTrial('WaitForResponse', [1.0 1.2], 'LeftRewardDelay', [1.2 1.4], ...
                  'WithdrewBeforeReward', [1.4 1.4], 'Port1In', 1.2);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.Outcome, lum.Outcome.CorrectNoReward);
verifyEqual(testCase, result.Rewarded, 0, 'The valve never opened');
verifyEqual(testCase, result.Choice, 1);
end

function testHabituationRewardsTheWrongSideButScoresItWrong(testCase)
% Both sides pay during habituation, so a trial can be rewarded and incorrect.
trial = makeTrial('WaitForResponse', [1.0 1.2], 'RightRewardDelay', [1.2 1.2], ...
                  'RightReward', [1.2 1.3], 'Port3In', 1.2);
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, [result.Rewarded, result.Correct], [1 0]);
verifyEqual(testCase, result.Outcome, lum.Outcome.Incorrect);
end

function testForgivenBreaksInTheHoldAreCounted(testCase)
trial = makeTrial('CentreHold', [0.5 0.7], 'WaitForResponse', [2.0 2.3], ...
                  'LeftRewardDelay', [2.3 2.3], 'LeftReward', [2.3 2.4], 'Port1In', 2.3);
trial.States.HoldBreak = [0.7 0.8; 1.1 1.15];
trial.States.CentreHoldResumed = [0.8 1.1; 1.15 1.9];
result = lum.scoreTrial(trial, spec(1), testCase.TestData.rig);
verifyEqual(testCase, result.HoldBreaks, 2);
verifyEqual(testCase, result.Outcome, lum.Outcome.Correct, 'Forgiven breaks do not end the trial');
end

function testATrialWithoutBreaksCountsNone(testCase)
trial = makeTrial('WaitForCentrePoke', [0.1 60.1], 'NoInitiation', [60.1 60.1]);
verifyEqual(testCase, lum.scoreTrial(trial, spec(1), testCase.TestData.rig).HoldBreaks, 0);
end

function testOutcomeNamesCoverEveryCode(testCase)
verifyEqual(testCase, numel(lum.Outcome.allNames()), 7);
verifyEqual(testCase, lum.Outcome.name(lum.Outcome.HoldNotCompleted), 'HoldNotCompleted');
verifyEqual(testCase, lum.Outcome.name(lum.Outcome.Correct), 'Correct');
verifyEqual(testCase, lum.Outcome.name(99), 'Unknown');
end


function trial = trialTemplate()
% Every state the trial builder can produce, all unvisited.
stateNames = {'TrialStart', 'WaitForCentrePoke', 'PreStimulusHold', 'CentreHold', ...
              'HoldBreak', 'CentreHoldResumed', 'WaitForCentreExit', 'WaitForResponse', ...
              'EarlyWithdrawal', 'LeftRewardDelay', 'RightRewardDelay', 'LeftReward', ...
              'RightReward', 'DrinkingLeft', 'DrinkingRight', 'DrinkingGrace', ...
              'WithdrewBeforeReward', 'IncorrectChoice', 'NoResponse', 'NoInitiation', 'ITI'};
trial = struct('States', struct(), 'Events', struct());
for i = 1:numel(stateNames)
    trial.States.(stateNames{i}) = [NaN NaN];
end
end

function trial = makeTrial(varargin)
% makeTrial('StateName', [start end], ..., 'PortNIn', time, ...) builds a raw trial.
trial = trialTemplate();
for i = 1:2:numel(varargin)
    name = varargin{i};
    value = varargin{i+1};
    if numel(value) == 2
        trial.States.(name) = value;
    elseif isfield(trial.Events, name)
        trial.Events.(name) = [trial.Events.(name) value];
    else
        trial.Events.(name) = value;
    end
end
end

function s = spec(correctSide)
s = struct('CorrectSide', correctSide);
end
