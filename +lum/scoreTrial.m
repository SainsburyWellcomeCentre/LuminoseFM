function result = scoreTrial(trialEvents, spec, rig)
% lum.scoreTrial classifies one completed trial from the states and events it visited.
%
% The scorer reads only the fixed state names and port events that
% lum.buildTrialSM guarantees, so it works for every stimulus modality, every
% training stage, every kind of hold shaping and either break mode, and can be run
% offline over an old session file.
%
% Arguments:
%   trialEvents  One element of Data.RawEvents.Trial, with .States and .Events
%   spec         The trial spec from lum.nextTrialSpec
%   rig          Channel map from RigConfig, for the port event names
%
% Returns:
%   .Outcome       lum.Outcome code
%   .Choice        Side poked first: 1 = Left, 2 = Right, NaN if no choice was made.
%                  An unpunished wrong choice may be followed by the correct one
%                  (RetryResponse); the first is the animal's choice.
%   .Correct       1, 0, or NaN if there was no choice to score
%   .Rewarded      1 if a side reward valve opened, else 0 (also after a retry)
%   .ReactionTime  Seconds from the response window opening — the animal leaving
%                  the centre port — to the choice poke
%   .HoldBreaks    Times the animal left the centre port during the hold and was
%                  forgiven (visits to HoldBreak); 0 without grace shaping
%   .HoldAttempts  Times the stimulus started (visits to CentreHold): 1 for a trial
%                  held at the first try, more when broken holds restarted it, 0
%                  when it never started
%   .EarlyWithdrawals  Times the animal left the centre port before the hold was
%                  complete and the break was not forgiven (visits to
%                  EarlyWithdrawal), during the latency or the hold
%   .CentreRewarded  1 if the centre valve opened for a completed hold
%                  (CentreReward), else 0
%   .ResponseRetries  Unpunished wrong choices the animal was let retry after (visits
%                  to RetryResponse); 0 when incorrect choices are punished
%   .CentreHoldTime  Seconds from the poke that began the trial's last hold (or
%                  latency) to the animal first leaving the centre port after it;
%                  NaN if the stimulus never started or the animal never left
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.buildTrialSM, lum.Outcome, lum.updateHistory

states = trialEvents.States;
events = trialEvents.Events;

result = struct('Outcome', lum.Outcome.NoResponse, 'Choice', NaN, ...
                'Correct', NaN, 'Rewarded', 0, 'ReactionTime', NaN, 'HoldBreaks', 0, ...
                'HoldAttempts', 0, 'EarlyWithdrawals', 0, 'CentreRewarded', 0, ...
                'ResponseRetries', 0, 'CentreHoldTime', NaN);

%% Which side was poked, and how quickly
responseWindow = getState(states, 'WaitForResponse');
if ~isnan(responseWindow(1))
    leftTime  = firstEventAfter(events, rig.PokeIn.Left,  responseWindow(1));
    rightTime = firstEventAfter(events, rig.PokeIn.Right, responseWindow(1));
    if ~isnan(leftTime) || ~isnan(rightTime)
        if isnan(rightTime) || leftTime < rightTime
            result.Choice = 1;
            choiceTime = leftTime;
        else
            result.Choice = 2;
            choiceTime = rightTime;
        end
        result.ReactionTime = choiceTime - responseWindow(1);
    end
end

result.Rewarded = double(visited(states, 'LeftReward') || visited(states, 'RightReward'));
result.HoldBreaks = nVisits(states, 'HoldBreak');
result.HoldAttempts = nVisits(states, 'CentreHold');
result.EarlyWithdrawals = nVisits(states, 'EarlyWithdrawal');
result.CentreRewarded = double(visited(states, 'CentreReward'));
result.ResponseRetries = nVisits(states, 'RetryResponse');
result.CentreHoldTime = centreHoldTime(states, events, rig);

%% Outcome, in the order the trial could have ended
% An EarlyWithdrawal visit ends the trial only if the hold was never completed
% afterwards: when a break restarts the stimulus, the same trial can pass through
% EarlyWithdrawal and still go on to a choice.
if visited(states, 'NoInitiation')
    if result.HoldAttempts > 0
        result.Outcome = lum.Outcome.HoldNotCompleted;
    else
        result.Outcome = lum.Outcome.NoInitiation;
    end
elseif visited(states, 'EarlyWithdrawal') && ~visited(states, 'WaitForCentreExit')
    result.Outcome = lum.Outcome.EarlyWithdrawal;
elseif visited(states, 'WithdrewBeforeReward') && ~isnan(result.Choice) ...
        && result.Choice == spec.CorrectSide
    % Only a correct first choice: after a retry the trial is scored by the first
    result.Outcome = lum.Outcome.CorrectNoReward;
elseif isnan(result.Choice)
    result.Outcome = lum.Outcome.NoResponse;
elseif result.Choice == spec.CorrectSide
    result.Outcome = lum.Outcome.Correct;
else
    result.Outcome = lum.Outcome.Incorrect;
end

if ~isnan(result.Choice)
    result.Correct = double(result.Choice == spec.CorrectSide);
end


function duration = centreHoldTime(states, events, rig)
% How long the animal stayed in the centre port on the poke that began its last hold:
% from that poke (the last centre poke at or before the hold's, or the latency's, last
% entry) to the first time it left the port afterwards.
duration = NaN;
entry = max([lastEntry(states, 'CentreHold'), lastEntry(states, 'PreStimulusHold')]);
if isempty(entry) || isnan(entry)
    return
end
pokeTime = entry;
if isfield(events, rig.PokeIn.Centre)
    pokes = events.(rig.PokeIn.Centre);
    pokes = pokes(pokes <= entry + 1e-4);
    if ~isempty(pokes)
        pokeTime = pokes(end);
    end
end
exitTime = firstEventAfter(events, rig.PokeOut.Centre, pokeTime);
duration = exitTime - pokeTime;


function t = lastEntry(states, name)
% Entry time of a state's last visit, or NaN if never visited.
t = NaN;
if isfield(states, name)
    entries = states.(name)(:, 1);
    entries = entries(~isnan(entries));
    if ~isempty(entries)
        t = entries(end);
    end
end


function span = getState(states, name)
% Entry and exit time of a state's first visit, or [NaN NaN] if never visited.
if isfield(states, name)
    span = states.(name)(1, :);
else
    span = [NaN NaN];
end


function tf = visited(states, name)
% True if the state was entered at least once.
span = getState(states, name);
tf = ~isnan(span(1));


function n = nVisits(states, name)
% How many times a state was entered.
n = 0;
if isfield(states, name)
    n = sum(~isnan(states.(name)(:, 1)));
end


function t = firstEventAfter(events, eventName, afterTime)
% Time of the first occurrence of an event at or after afterTime, else NaN.
t = NaN;
if ~isfield(events, eventName)
    return
end
times = events.(eventName);
times = times(times >= afterTime);
if ~isempty(times)
    t = times(1);
end
