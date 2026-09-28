function measures = holdMeasures(states)
% lum.holdMeasures says whether a trial's centre hold was completed, and at which attempt.
%
%   measures = lum.holdMeasures(trialEvents.States)
%
% The plots, the log and the runtime window read the hold from here, so that they all say the
% same thing (lum.scoreTrial returns it with the rest of the trial's score, and
% lum.report.sessionTrials reads it from a saved file's states):
%
%   hold completed            The trial reached CentreReward or WaitForCentreExit: the animal
%                             held for the full time, at some attempt. A trial whose earlier
%                             holds broke and restarted the stimulus (S.Task.OnHoldBreak
%                             'Restart stimulus') still completed its hold.
%   hold attempt              A poke that began a hold: each early withdrawal (a visit to
%                             EarlyWithdrawal, during the latency or the hold) and the
%                             completed hold. A forgiven break (grace: HoldBreak, then
%                             CentreHoldResumed) is part of the same attempt. Without a
%                             latency this equals Data.HoldAttempts (visits to CentreHold).
%   held on the first attempt The hold was completed with no early withdrawal before it.
%
% Under 'End trial' an early withdrawal ends the trial, so such a trial has one attempt and
% did not complete its hold. A trial with no poke in the hold window has none.
%
% Returns a struct:
%   .Completed         1 if the hold was completed, else 0
%   .FirstAttempt      1 if it was completed with no early withdrawal, else 0
%   .Attempts          Hold attempts: EarlyWithdrawals + Completed
%   .EarlyWithdrawals  Visits to EarlyWithdrawal
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.scoreTrial, lum.report.sessionTrials, lum.OnlinePlots

completed = double(visited(states, 'CentreReward') || visited(states, 'WaitForCentreExit'));
withdrawals = nVisits(states, 'EarlyWithdrawal');
measures = struct('Completed', completed, ...
                  'FirstAttempt', double(completed == 1 && withdrawals == 0), ...
                  'Attempts', withdrawals + completed, ...
                  'EarlyWithdrawals', withdrawals);


function tf = visited(states, name)
% True if the state was entered at least once.
tf = nVisits(states, name) > 0;


function n = nVisits(states, name)
% How many times a state was entered.
n = 0;
if isfield(states, name)
    n = sum(~isnan(states.(name)(:, 1)));
end
