function names = triggerStates(S)
% lum.triggerStates lists the states that open the prepare window for the next trial.
%
% With BpodTrialManager, MATLAB builds and uploads trial n+1 while trial n runs, from
% the moment trial n reaches one of these states (D3). Each must be a state after
% which the trial can only end, so that the work never overlaps a stimulus: every
% trial passes through exactly one of them, and the ITI follows.
%
% EarlyWithdrawal is one only when a broken hold ends the trial. When it restarts
% the stimulus instead (S.Task.OnHoldBreak, D10), the animal may poke again straight
% after it and receive light, so uploading a state machine or reprogramming PulsePal
% there would fall inside the stimulus.
%
% When a completed hold may end before the light pattern does
% (lum.HoldShaping.lightMayOutlastHold), the light can still be on in any of those
% states, and the prepare window changes LED currents and may program PulsePal. The
% ITI is then the only trigger state: every trial that ends reaches it through
% WaitForLightEnd, after the light (D21). The next trial is prepared in the ITI, as it
% already was after NoInitiation and NoResponse.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.SessionRunner, lum.buildTrialSM, lum.HoldShaping

if lum.HoldShaping.lightMayOutlastHold(S)
    names = {'ITI'};
    return
end
names = {'LeftReward', 'RightReward', 'IncorrectChoice', 'NoResponse', ...
         'NoInitiation', 'WithdrewBeforeReward'};
if ~lum.HoldShaping.restartsOnBreak(S)
    names{end+1} = 'EarlyWithdrawal';
end
