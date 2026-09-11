function history = newHistory(capacity)
% lum.newHistory creates the preallocated trial history used by the session loop.
%
% Everything the protocol needs to know about the past — for bias correction, run
% limits, hold shaping and the running performance figures — is kept here, updated
% in O(1) per trial. Nothing re-scans BpodSystem.Data, which would make the
% inter-trial work grow with the session and eventually show up as lag.
%
% Arguments:
%   capacity  Number of trials to preallocate for (S.Session.MaxTrials)
%
% Returns a struct of 1 x capacity arrays, all NaN, plus nTrials = 0:
%   .pattern       Index into the session's stimulus set
%   .group         Stimulus group (or category, in continuous mode)
%   .correctSide   1 = Left, 2 = Right
%   .choice        Side poked: 1, 2, or NaN if the trial had no response
%   .correct       1 correct, 0 incorrect, NaN if no choice was made
%   .rewarded      1 if a reward valve opened, else 0
%   .outcome       lum.Outcome code for the trial
%   .reactionTime  Seconds from leaving the centre port to the choice poke
%   .holdDuration  Centre hold the trial required, seconds
%   .holdGrace     Longest forgiven break in the hold, seconds
%   .holdBreaks    Times the animal left and came back during the hold
%   .holdAttempts  Times the stimulus started; more than 1 when breaks restarted it
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.updateHistory, lum.nextTrialSpec, lum.Outcome

blank = NaN(1, capacity);
history = struct('capacity', capacity, 'nTrials', 0, ...
                 'pattern', blank, 'group', blank, 'correctSide', blank, ...
                 'choice', blank, 'correct', blank, 'rewarded', blank, ...
                 'outcome', blank, 'reactionTime', blank, 'holdDuration', blank, ...
                 'holdGrace', blank, 'holdBreaks', blank, 'holdAttempts', blank);
