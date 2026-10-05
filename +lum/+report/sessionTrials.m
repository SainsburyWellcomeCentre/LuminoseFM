function T = sessionTrials(Data)
% lum.report.sessionTrials gathers what the summary plots and the log read from a session.
%
%   T = lum.report.sessionTrials(SessionData)
%
% One pass over a behaviour session's data (BpodSystem.Data as saved, or the SessionData of a
% saved file), into flat per-trial and per-session arrays, so every summary plot and the log
% read the same numbers. Nothing is changed in Data.
%
% Returns a struct:
%   .n                Trials recorded
%   .S                The settings the session started with, in the current layout
%                     (lum.mergeSettings 'AsRun': renamed and reshaped settings converted,
%                     values as the session ran them), so older files read like new ones
%   .stimulusSet      Session.StimulusSet
%   .subject, .name   The subject, and the data file's name when Data.Info has it
%   .bothSidesPay     1 x n: habituation, where both side ports pay and trials are scored by
%                     their reward (lum.OnlinePlots)
%   .scored           1 x n: what the online plots score: rewarded (habituation, every trial)
%                     or correct (other stages, NaN without a choice)
%   .outcome .choice .correct .rewarded .correctSide .group .pattern .reactionTime
%   .holdDuration .centreHoldTime .holdAttempts .earlyWithdrawals .centreReward
%   .responseRetries .biasTarget .optoOn .trainingStage .biasContext .sidePokeDelays
%                     The per-trial series (NaN where an older file has none)
%   .block, .blockSide  1 x n: the trial's block (0 in a random order, and in files from
%                     before 0.10.0) and its side (lum.Blocks)
%   .blockFirst       1 x n: the first trial of a block
%   .blockPosition    1 x n: the trial's place in its block, 1 for the first; NaN outside
%   .ranBlocks        True when any trial was in a block
%   .forStimulus      1 x n: the trials whose side the trials before did not set: outside
%                     blocks, and each block's first trial. The psychometric and evidence
%                     plots and the log's By group read these alone in a session with blocks
%   .choiceTime       1 x n: the choice poke, seconds from the first trial's start; NaN
%                     without a choice
%   .lastSidePoke     1 x n: the side (1, 2) of the side poke just before the choice poke,
%                     in this trial or an earlier one; NaN without a choice or before any
%   .sidePokesBeforeCentre, .sidePokesBetween  1 x n: side pokes before the response window
%                     opened (or the trial ended without it): before the trial's first
%                     centre poke, and after it (between hold attempts)
%   .firstPokeSide    1 x n: 1 or 2 when the trial's first poke was a side poke, 0 when it
%                     was the centre port, NaN with no poke
%   .holdCompleted    1 x n: 1 if the hold was completed, at any attempt (lum.holdMeasures)
%   .heldFirstAttempt 1 x n: 1 if it was completed with no early withdrawal before it
%   .attempts         1 x n: hold attempts, early withdrawals plus the completed hold
%                     (lum.holdMeasures; Data.HoldAttempts is .holdAttempts)
%   .holdAsked        1 x n: latency plus the hold asked for, as the centre hold panel shows it
%   .rewardAmount     1 x n: the side reward volume each trial was prepared with (uL)
%   .sideWater        1 x n: side water given (uL): rewardAmount where Rewarded
%   .start, .finish   1 x n: trial start and end, seconds from the first trial's start
%   .attemptTrial, .attemptTime, .attemptCompleted  One entry per visit to CentreHold: its
%                     trial, seconds from stimulus onset to leaving the state, and whether the
%                     hold was completed there
%   .pokes            Struct with Left, Centre, Right: times of every poke into that port,
%                     seconds from the first trial's start
%   .steppedBack      1 x n: the hold asked for fell from the trial before (a step back)
%   .runtimeChanges   Struct array: Trial, Name, From, To for every runtime setting changed
%                     during the session (Data.TrialSettings)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.report.summaryPlots, lum.report.sessionLog, lum.report.habits

n = Data.nTrials;
T = struct();
T.n = n;
T.S = lum.mergeSettings(lum.defaultSettings, Data.Session.Settings, 'AsRun', true);
T.stimulusSet = Data.Session.StimulusSet;
T.subject = '';
if isfield(Data.Session, 'Subject')
    T.subject = char(Data.Session.Subject);
end

series = {'Outcome', 'outcome'; 'Choice', 'choice'; 'Correct', 'correct'; ...
          'Rewarded', 'rewarded'; 'CorrectSide', 'correctSide'; 'StimulusGroup', 'group'; ...
          'PatternIndex', 'pattern'; 'ReactionTime', 'reactionTime'; ...
          'HoldDuration', 'holdDuration'; 'CentreHoldTime', 'centreHoldTime'; ...
          'HoldAttempts', 'holdAttempts'; 'EarlyWithdrawals', 'earlyWithdrawals'; ...
          'CentreReward', 'centreReward'; 'ResponseRetries', 'responseRetries'; ...
          'BiasTargetPLeft', 'biasTarget'; 'OptoOn', 'optoOn'; 'TrainingStage', 'trainingStage'; ...
          'BiasContext', 'biasContext'; 'Block', 'block'; 'BlockSide', 'blockSide'; ...
          'SidePokeDelays', 'sidePokeDelays'};
for i = 1:size(series, 1)
    if isfield(Data, series{i, 1})
        T.(series{i, 2}) = double(Data.(series{i, 1})(1:n));
    else
        T.(series{i, 2}) = NaN(1, n);  % A series older files do not have
    end
end
T.block(isnan(T.block)) = 0;   % Files from before 0.10.0: every trial in a random order
[T.blockFirst, T.blockPosition] = lum.Blocks.firstTrials(T.block);
T.ranBlocks = any(T.block > 0);
T.forStimulus = T.block == 0 | T.blockFirst;
T.sidePokeDelays(isnan(T.sidePokeDelays)) = 0;
T.bothSidesPay = T.trainingStage == 1;
T.scored = T.correct;
T.scored(T.bothSidesPay) = double(T.rewarded(T.bothSidesPay) == 1);
T.holdAsked = T.S.Stimulus.Latency + T.holdDuration;

T.rewardAmount = NaN(1, n);
for k = 1:min(n, numel(Data.TrialSettings))
    if isfield(Data.TrialSettings{k}, 'RewardAmount')
        T.rewardAmount(k) = Data.TrialSettings{k}.RewardAmount;
    end
end
T.sideWater = T.rewardAmount .* (T.rewarded == 1);
T.sideWater(isnan(T.sideWater)) = 0;

origin = Data.TrialStartTimestamp(1);
T.start = Data.TrialStartTimestamp(1:n) - origin;
T.finish = Data.TrialEndTimestamp(1:n) - origin;

% The hold measures, every visit to CentreHold, and every poke, from the raw events.
[T.holdCompleted, T.heldFirstAttempt, T.attempts] = deal(zeros(1, n));
attempts = cell(1, n);
completed = cell(1, n);
pokeNames = {'Port1In', 'Port2In', 'Port3In'};
if isfield(Data.Session, 'Rig') && isfield(Data.Session.Rig, 'PokeIn')
    pokeIn = Data.Session.Rig.PokeIn;
    pokeNames = {pokeIn.Left, pokeIn.Centre, pokeIn.Right};
end
pokes = cell(3, n);
[T.sidePokesBeforeCentre, T.sidePokesBetween] = deal(zeros(1, n));
[T.firstPokeSide, T.choiceTime] = deal(NaN(1, n));
for k = 1:n
    trial = Data.RawEvents.Trial{k};
    measures = lum.holdMeasures(trial.States);
    T.holdCompleted(k) = measures.Completed;
    T.heldFirstAttempt(k) = measures.FirstAttempt;
    T.attempts(k) = measures.Attempts;
    if isfield(trial.States, 'CentreHold')
        visits = trial.States.CentreHold;
        visits = visits(~isnan(visits(:, 1)), :);
        attempts{k} = (visits(:, 2) - visits(:, 1))';
        done = false(1, size(visits, 1));
        if measures.Completed && ~isempty(done)
            done(end) = true;
        end
        completed{k} = done;
    end
    for p = 1:3
        if isfield(trial.Events, pokeNames{p})
            pokes{p, k} = trial.Events.(pokeNames{p}) + T.start(k);
        end
    end
    [T.sidePokesBeforeCentre(k), T.sidePokesBetween(k), T.firstPokeSide(k), T.choiceTime(k)] = ...
        pokesBeforeResponse(trial, pokeNames, T.choice(k), T.finish(k) - T.start(k));
    T.choiceTime(k) = T.choiceTime(k) + T.start(k);
end
counts = cellfun(@numel, attempts);
T.attemptTrial = repelem(1:n, counts);
T.attemptTime = [attempts{:}];
T.attemptCompleted = [completed{:}];
T.pokes = struct('Left', [pokes{1, :}], 'Centre', [pokes{2, :}], 'Right', [pokes{3, :}]);

T.lastSidePoke = lastSidePoke(T.pokes, T.choiceTime);

T.steppedBack = [false, diff(T.holdDuration) < -5e-5];
T.runtimeChanges = runtimeChanges(Data.TrialSettings(1:min(n, numel(Data.TrialSettings))));
end


function changes = runtimeChanges(settings)
% Every runtime setting that differs from the trial before, with the trial it took effect on.
changes = struct('Trial', {}, 'Name', {}, 'From', {}, 'To', {});
for k = 2:numel(settings)
    names = fieldnames(settings{k});
    for i = 1:numel(names)
        name = names{i};
        if ~isfield(settings{k - 1}, name)
            continue
        end
        before = settings{k - 1}.(name);
        after = settings{k}.(name);
        if ~isequal(before, after)
            changes(end + 1) = struct('Trial', k, 'Name', name, 'From', {before}, 'To', {after}); %#ok<AGROW>
        end
    end
end
end


function [beforeCentre, between, firstSide, choiceTime] = pokesBeforeResponse(trial, pokeNames, choice, duration)
% One trial's side pokes before its response window opened (or, without one, before it ended):
% before its first centre poke and after it; the side of its first poke (0 the centre); and
% the time of the choice poke, from the trial's start: the first poke at the chosen port at or
% after the response window opened.
events = trial.Events;
times = {[], [], []};
for p = 1:3
    if isfield(events, pokeNames{p})
        times{p} = events.(pokeNames{p});
    end
end
opened = duration;
if isfield(trial.States, 'WaitForResponse') && ~isnan(trial.States.WaitForResponse(1, 1))
    opened = trial.States.WaitForResponse(1, 1);
end
side = [times{1}, times{3}];
side = side(side < opened);
firstCentre = min([times{2}, Inf]);
beforeCentre = sum(side < firstCentre);
between = numel(side) - beforeCentre;
firstSide = NaN;
first = min([times{:}, Inf]);
if isfinite(first)
    firstSide = 0;
    if any(times{1} == first)
        firstSide = 1;
    elseif any(times{3} == first)
        firstSide = 2;
    end
end
choiceTime = NaN;
if any(choice == [1 2])
    chosen = times{2 * choice - 1};
    chosen = chosen(chosen >= opened - 1e-6);
    if ~isempty(chosen)
        choiceTime = chosen(1);
    end
end
end


function sides = lastSidePoke(pokes, choiceTimes)
% For each choice, the side of the side poke just before it in the session's sorted side pokes.
[times, order] = sort([pokes.Left, pokes.Right]);
pokeSide = [ones(1, numel(pokes.Left)), 2 * ones(1, numel(pokes.Right))];
pokeSide = pokeSide(order);
sides = NaN(size(choiceTimes));
for k = find(~isnan(choiceTimes))
    before = find(times < choiceTimes(k) - 1e-6, 1, 'last');
    if ~isempty(before)
        sides(k) = pokeSide(before);
    end
end
end
