function history = updateHistory(history, trialNumber, spec, result)
% lum.updateHistory records one completed trial, in constant time.
%
% Arguments:
%   history      Struct from lum.newHistory
%   trialNumber  Index of the trial that just finished
%   spec         Trial spec from lum.nextTrialSpec
%   result       Struct from lum.scoreTrial
%
% Returns the updated history.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.newHistory, lum.scoreTrial

if trialNumber > history.capacity
    error('lum:updateHistory:overCapacity', ...
          'Trial %d exceeds the preallocated history capacity of %d.', ...
          trialNumber, history.capacity);
end

history.nTrials = trialNumber;
history.pattern(trialNumber)      = spec.PatternIndex;
history.group(trialNumber)        = spec.StimulusGroup;
history.correctSide(trialNumber)  = spec.CorrectSide;
history.choice(trialNumber)       = result.Choice;
history.correct(trialNumber)      = result.Correct;
history.rewarded(trialNumber)     = result.Rewarded;
history.outcome(trialNumber)      = result.Outcome;
history.reactionTime(trialNumber) = result.ReactionTime;
history.holdDuration(trialNumber) = spec.HoldDuration;
history.holdGrace(trialNumber)    = spec.HoldGrace;
history.holdBreaks(trialNumber)   = result.HoldBreaks;
history.holdAttempts(trialNumber) = result.HoldAttempts;
