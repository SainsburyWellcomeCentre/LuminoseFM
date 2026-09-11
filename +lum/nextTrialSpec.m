function [spec, queue] = nextTrialSpec(S, stimulusSet, queue, history, trialNumber)
% lum.nextTrialSpec decides what the next trial will be.
%
% The stimulus set fixes a balanced, shuffled order of patterns for the session
% (lum.pattern.generate); the queue is that order as it stands. Normally the next
% trial simply takes the next pattern in the queue. Two policies may reorder it,
% by swapping the next pattern with a later one, so that every group is still
% delivered as often as the generator balanced it:
%
%   Run limit        After S.Task.MaxSameSide trials rewarded on one side, the next
%                    trial must be rewarded on the other.
%   Bias correction  When the animal favours one side, a side is drawn biased
%                    towards the one it avoids (strength S.GUI.BiasCorrection over
%                    the last S.GUI.BiasWindow choices) and the next pattern that
%                    can pay it is brought forward.
%
% Swaps look at most 50 trials ahead, so each decision is constant time and the
% queue changes only locally.
%
% The function is pure — it reads settings, the set, the queue and history, and
% returns a spec and the queue — so the whole trial-generation policy is testable
% with no hardware and no Bpod.
%
% Arguments:
%   S            Settings struct
%   stimulusSet  Stimulus set from lum.pattern.stimulusSet
%   queue        1 x nTrials pattern order; starts as stimulusSet.TrialPattern
%   history      Struct from lum.newHistory, holding completed trials
%   trialNumber  The trial being generated
%
% Returns the queue, possibly with two entries swapped, and a spec struct:
%   .TrialNumber      Trial index
%   .PatternIndex     Index into the stimulus set's patterns
%   .StimulusGroup    Group of that pattern (in continuous mode, its category)
%   .CorrectSide      1 = Left, 2 = Right; the side scored as correct
%   .RewardedSides    Sides whose valve will open. Both, during habituation.
%   .TrainingStage    Stage index, copied so the trial record is self-contained
%   .BiasTargetPLeft  The p(left) bias correction aimed for; 0.5 when inactive
%   .OptoOn           True if the light pattern is delivered on this trial
%   .SoundOn          True if sounds are played
%   .SyncMode         Sync mode this trial used, indexing S.Sync.ModeNames
%   .SyncPulseWidth   Sync pulse width for this trial, seconds; NaN in task-event
%                     mode, where the line follows the trial rather than pulsing
%   .HoldDuration     Centre hold this trial requires, seconds (lum.HoldShaping)
%   .HoldGrace        Longest break in the hold that is forgiven, seconds
%
% Side draws and pulse widths come from rand(), so seeding with rng() makes a
% session or a test reproducible. The pattern order does not: it is fixed by the
% generator's own seed.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.stimulusSet, lum.newHistory, lum.buildTrialSM, lum.scoreTrial

lookahead = 50;

if trialNumber > numel(queue)
    error('lum:nextTrialSpec:queueExhausted', ...
          'Trial %d is past the end of the %d-trial stimulus order.', trialNumber, numel(queue));
end
pLeftOf = stimulusSet.PatternPLeft;

%% Bias correction: the p(left) that would compensate the animal's recent choices
pLeftTarget = 0.5;
if S.GUI.BiasCorrection > 0
    recent = recentChoices(history, S.GUI.BiasWindow);
    if numel(recent) >= 3
        fractionLeft = mean(recent == 1);
        % A strength of 1 fully compensates: an animal choosing left on every
        % recent trial gets p(left) pushed down, and vice versa.
        pLeftTarget = 0.5 + S.GUI.BiasCorrection * (0.5 - fractionLeft);
        pLeftTarget = min(max(pLeftTarget, 0.1), 0.9);  % Never starve one side entirely
    end
end

%% The side the next trial should pay, if any policy asks for one
forcedSide = sideForcedByRunLimit(S, history);
wantedSide = forcedSide;
if isempty(wantedSide) && pLeftTarget ~= 0.5
    wantedSide = 1 + (rand >= pLeftTarget);
end

if ~isempty(wantedSide) && ~canPay(pLeftOf(queue(trialNumber)), wantedSide)
    ahead = trialNumber + 1:min(numel(queue), trialNumber + lookahead);
    swapWith = ahead(find(canPay(pLeftOf(queue(ahead)), wantedSide), 1));
    if ~isempty(swapWith)
        queue([trialNumber swapWith]) = queue([swapWith trialNumber]);
    end
end

patternIndex = queue(trialNumber);
pLeft = pLeftOf(patternIndex);
if ~isempty(forcedSide) && canPay(pLeft, forcedSide)
    correctSide = forcedSide;
else
    correctSide = 1 + (rand >= pLeft);  % 1 = Left, 2 = Right
end

%% Assemble
spec = struct();
spec.TrialNumber = trialNumber;
spec.PatternIndex = patternIndex;
spec.StimulusGroup = stimulusSet.PatternGroup(patternIndex);
spec.CorrectSide = correctSide;
spec.TrainingStage = S.Task.TrainingStage;
spec.BiasTargetPLeft = pLeftTarget;

% Habituation rewards either side, so the animal learns that the side ports pay
% before it has to learn which one. Later stages reward only the correct side.
if S.Task.TrainingStage == 1
    spec.RewardedSides = [1 2];
else
    spec.RewardedSides = correctSide;
end

spec.OptoOn = S.Session.UseOpto && S.GUI.OptoOn == 1;
spec.SoundOn = S.Session.UseSound && S.GUI.SoundOn == 1;
spec.SyncMode = S.Sync.Mode;
spec.SyncPulseWidth = syncPulseWidth(S);
[spec.HoldDuration, spec.HoldGrace] = lum.HoldShaping.next(S, history);


function tf = canPay(pLeft, side)
% Whether a pattern with this p(left) can be rewarded on this side.
if side == 1
    tf = pLeft > 0;
else
    tf = pLeft < 1;
end


function width = syncPulseWidth(S)
% This trial's sync pulse width, by mode.
switch S.Sync.Mode
    case lum.SyncMode.FixedWidth
        width = S.Sync.FixedWidth;
    case lum.SyncMode.JitteredWidth
        % Uniform about the mean, so the mean really is the average width and a
        % session's pulses spread across a known range rather than an open one.
        width = S.Sync.MeanWidth + (2 * rand - 1) * S.Sync.WidthJitter;
        width = max(width, 0);
    case lum.SyncMode.TaskEvents
        % No pulse: the line is high from trial start until the animal pokes.
        width = NaN;
    otherwise
        error('lum:nextTrialSpec:unknownSyncMode', ...
              'S.Sync.Mode is %g; it must index S.Sync.ModeNames (1 to %d).', ...
              S.Sync.Mode, numel(S.Sync.ModeNames));
end


function recent = recentChoices(history, window)
% The last `window` trials' choices, with no-response trials dropped.
if history.nTrials == 0 || window < 1
    recent = [];
    return
end
first = max(1, history.nTrials - floor(window) + 1);
recent = history.choice(first:history.nTrials);
recent = recent(~isnan(recent));


function side = sideForcedByRunLimit(S, history)
% The side that must be used next to keep same-side runs within MaxSameSide.
side = [];
limit = S.Task.MaxSameSide;
if limit < 1 || history.nTrials < limit
    return
end
lastSides = history.correctSide(history.nTrials - limit + 1:history.nTrials);
if all(lastSides == lastSides(1)) && ~isnan(lastSides(1))
    side = 3 - lastSides(1);  % Sides are 1 and 2, so 3 - s is the other one
end
