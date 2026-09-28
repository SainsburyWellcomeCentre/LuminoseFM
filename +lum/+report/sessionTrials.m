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
%   .S                The settings the session started with, brought up to date
%                     (lum.mergeSettings), so older files read like new ones
%   .stimulusSet      Session.StimulusSet
%   .subject, .name   The subject, and the data file's name when Data.Info has it
%   .bothSidesPay     1 x n: habituation, where both side ports pay and trials are scored by
%                     their reward (lum.OnlinePlots)
%   .scored           1 x n: what the online plots score: rewarded (habituation, every trial)
%                     or correct (other stages, NaN without a choice)
%   .outcome .choice .correct .rewarded .correctSide .group .pattern .reactionTime
%   .holdDuration .centreHoldTime .holdAttempts .earlyWithdrawals .centreReward
%   .responseRetries .biasTarget .optoOn .trainingStage   The per-trial series
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
% See also lum.report.summaryPlots, lum.report.sessionLog

n = Data.nTrials;
T = struct();
T.n = n;
T.S = lum.mergeSettings(lum.defaultSettings, Data.Session.Settings);
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
          'BiasTargetPLeft', 'biasTarget'; 'OptoOn', 'optoOn'; 'TrainingStage', 'trainingStage'};
for i = 1:size(series, 1)
    if isfield(Data, series{i, 1})
        T.(series{i, 2}) = double(Data.(series{i, 1})(1:n));
    else
        T.(series{i, 2}) = NaN(1, n);  % A series older files do not have
    end
end
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
end
counts = cellfun(@numel, attempts);
T.attemptTrial = repelem(1:n, counts);
T.attemptTime = [attempts{:}];
T.attemptCompleted = [completed{:}];
T.pokes = struct('Left', [pokes{1, :}], 'Centre', [pokes{2, :}], 'Right', [pokes{3, :}]);

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
