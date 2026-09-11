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
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.SessionRunner, lum.buildTrialSM, lum.HoldShaping

names = {'LeftReward', 'RightReward', 'IncorrectChoice', 'NoResponse', ...
         'NoInitiation', 'WithdrewBeforeReward'};
if ~lum.HoldShaping.restartsOnBreak(S)
    names{end+1} = 'EarlyWithdrawal';
end
