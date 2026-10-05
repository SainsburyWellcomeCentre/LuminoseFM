function [spec, queue] = legacyNextTrialSpec(S, stimulusSet, queue, history, trialNumber)
% legacyNextTrialSpec is lum.nextTrialSpec as released in 0.9.14, kept for the regression test.
%
% strategyTest replays sessions through this and through the current lum.nextTrialSpec with
% its swap partner set to 'first' and every strategy correction setting at its default, under
% one rng, and requires the same specs and queues: the defaults reproduce the trials 0.9.14
% chose. Copied unchanged from git (676ff9a) but for this help and its name; never edit it.
%
% See also strategyTest
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
favouredSide = [];   % The side bias correction pushes towards, if any
if pLeftTarget < 0.5
    favouredSide = 2;
elseif pLeftTarget > 0.5
    favouredSide = 1;
end

%% The side the next trial should pay, if any policy asks for one
% Bias correction takes precedence over the run limit: a run on the side it is pushing
% towards may go past MaxSameSide, and the side is drawn by the correction instead.
forcedSide = sideForcedByRunLimit(S, history);
if ~isempty(forcedSide) && isequal(forcedSide, 3 - favouredSide)
    forcedSide = [];
end
wantedSide = forcedSide;
if isempty(wantedSide) && ~isempty(favouredSide)
    wantedSide = 1 + (rand >= pLeftTarget);
end

if ~isempty(wantedSide) && ~canPay(pLeftOf(queue(trialNumber)), wantedSide)
    ahead = trialNumber + 1:numel(queue);
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
[spec.HoldDuration, spec.HoldGrace, spec.HoldSteppedBack] = lum.HoldShaping.next(S, history);

% The centre reward teaches a new animal that the centre port is worth visiting, so it
% belongs to habituation's first trials, and to any run the operator starts again later
% for an animal that has stopped coming to it. Counted in trials, not in rewards given,
% so it does not depend on a trial still running while this one is prepared; the
% settings are runtime ones, and raising a count mid-session carries it on.
habituation = S.Task.TrainingStage == 1 && trialNumber <= S.GUI.CentreRewardTrials;
from = 0;
if isfield(history, 'centreRewardAgainFrom')
    from = history.centreRewardAgainFrom;
end
spec.CentreRewardAgain = from > 0 && isfield(S.GUI, 'CentreRewardAgainTrials') ...
                         && trialNumber >= from ...
                         && trialNumber < from + S.GUI.CentreRewardAgainTrials;
spec.CentreReward = S.GUI.CentreRewardAmount > 0 && (habituation || spec.CentreRewardAgain);
spec.CentreRewardAmount = double(spec.CentreReward) * S.GUI.CentreRewardAmount;


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
% The animal's last `window` choices, skipping trials with no choice.
recent = [];
if history.nTrials == 0 || window < 1
    return
end
choices = history.choice(1:history.nTrials);
recent = choices(find(~isnan(choices), floor(window), 'last'));


function side = sideForcedByRunLimit(S, history)
% The side that must be used next to keep same-side runs within MaxSameSide. The trial
% before this one is usually still running, prepared but not yet recorded
% (history.preparedSide, lum.HoldShaping.notePrepared): its side ends the run. Up to 0.9.7
% it was left out, and runs reached MaxSameSide + 1 (LUMS0014, 2026-09-27: 26 runs of 4
% with a limit of 3).
side = [];
limit = S.Task.MaxSameSide;
sides = history.correctSide(1:history.nTrials);
if isfield(history, 'preparedTrial') && history.preparedTrial == history.nTrials + 1
    sides = [sides, history.preparedSide];
end
if limit < 1 || numel(sides) < limit
    return
end
lastSides = sides(end - limit + 1:end);
if all(lastSides == lastSides(1)) && ~isnan(lastSides(1))
    side = 3 - lastSides(1);  % Sides are 1 and 2, so 3 - s is the other one
end
