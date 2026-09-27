function lines = trialStatus(trialNumber, spec, result, nextSpec, stimulusSet)
% lum.trialStatus is the runtime window's header: how the last trial ended, and what runs now.
%
% Returns a 1 x 2 cell array of lines (one when nextSpec is empty):
%   'Trial 12: correct, chose left'
%   'Running 13: A only, pays right, hold 0.60 s'
% Before the first trial ends, lum.trialStatus(0, [], [], spec, stimulusSet) gives
% 'Session started' and the running line.
%
% In habituation both side ports pay (spec.RewardedSides), so a choice has no right or
% wrong side: the last trial is described by its reward ('rewarded, chose left', 'not
% rewarded: chose left, left before the valve opened') and the running one as 'both sides
% pay'. In training and experiment it is correct or incorrect, as the contingency scores
% it. A trial without a choice says why (no poke, early withdrawal, hold not completed, no
% side poke in time) in every stage. A trial that took more than one hold attempt says so:
% 'held on attempt 3' when the hold was completed, '14 hold attempts' when it was not.
%
% Arguments:
%   trialNumber  The trial that just ended
%   spec         Its spec (lum.nextTrialSpec); RewardedSides says whether both sides paid
%   result       Its result (lum.scoreTrial)
%   nextSpec     The trial now running, or [] after the last
%   stimulusSet  The session's stimulus set, for group labels
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.gui.RuntimeWindow, lum.Outcome, lum.scoreTrial

if isempty(result)
    lines = {'Session started', runningText(nextSpec, stimulusSet)};
    return
end
sides = {'left', 'right'};
bothPay = isfield(spec, 'RewardedSides') && numel(spec.RewardedSides) > 1;
chose = '';
if any(result.Choice == [1 2])
    chose = sprintf('chose %s', sides{result.Choice});
end

switch result.Outcome
    case lum.Outcome.NoInitiation
        what = 'no hold started in the hold window';
    case lum.Outcome.EarlyWithdrawal
        what = 'early withdrawal';
    case lum.Outcome.HoldNotCompleted
        what = 'hold not completed in the hold window';
    case lum.Outcome.NoResponse
        what = 'no side poke in the response window';
    otherwise
        if bothPay
            if result.Rewarded
                what = sprintf('rewarded, %s', chose);
            else
                what = sprintf('not rewarded: %s, left before the valve opened', chose);
            end
        elseif result.Outcome == lum.Outcome.Correct
            what = sprintf('correct, %s', chose);
        elseif result.Outcome == lum.Outcome.CorrectNoReward
            what = sprintf('correct, %s, left before the valve opened', chose);
        else
            what = sprintf('incorrect, %s', chose);
            if result.Rewarded
                what = sprintf('%s, then rewarded on a retry', what);
            end
        end
end
last = sprintf('Trial %d: %s', trialNumber, what);
% Hold attempts as the plots count them (lum.holdMeasures): a completed hold after early
% withdrawals is a completed hold, and says at which attempt.
attempts = result.EarlyWithdrawals + result.HoldCompleted;
if result.HoldCompleted && attempts > 1
    last = sprintf('%s (held on attempt %d)', last, attempts);
elseif ~result.HoldCompleted && attempts > 1
    last = sprintf('%s (%d hold attempts)', last, attempts);
end
lines = {last};
if ~isempty(nextSpec)
    lines{2} = runningText(nextSpec, stimulusSet);
end
end


function text = runningText(spec, stimulusSet)
% What the running trial delivers, in a few words.
label = 'no group';
if spec.StimulusGroup >= 1
    label = stimulusSet.GroupLabels{spec.StimulusGroup};
end
if isfield(spec, 'OptoOn') && ~spec.OptoOn
    label = sprintf('%s (light off)', label);
end
sides = {'left', 'right'};
if isfield(spec, 'RewardedSides') && numel(spec.RewardedSides) > 1
    pays = 'both sides pay';
else
    pays = sprintf('pays %s', sides{spec.CorrectSide});
end
text = sprintf('Running %d: %s, %s, hold %.2f s', spec.TrialNumber, label, pays, spec.HoldDuration);
if spec.HoldSteppedBack
    text = sprintf('%s (stepped back after early withdrawals)', text);
end
if spec.CentreReward && spec.CentreRewardAgain
    text = sprintf('%s, centre reward %g uL (again)', text, spec.CentreRewardAmount);
elseif spec.CentreReward
    text = sprintf('%s, centre reward %g uL', text, spec.CentreRewardAmount);
end
end
