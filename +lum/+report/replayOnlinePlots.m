function plots = replayOnlinePlots(Data, varargin)
% lum.report.replayOnlinePlots draws a saved session's online figure again, trial by trial.
%
%   plots = lum.report.replayOnlinePlots(SessionData);
%   lum.gui.savePlotsImage(plots.Figure, dataFile);
%   plots.close();
%
% Feeds every recorded trial to a new lum.OnlinePlots, as the session did, so the figure is
% the current version's (its colours, panels and scoring) for a session recorded with an
% older one; the header's clock shows each trial's session time. Nothing is running once the
% session has ended, so the now-and-next panel is empty. The house light switch is not drawn.
%
% Options:
%   'Visible'  'off' (default) or 'on'
%
% See also lum.report.fromFile, lum.OnlinePlots

p = inputParser;
p.FunctionName = 'lum.report.replayOnlinePlots';
addParameter(p, 'Visible', 'off');
parse(p, varargin{:});

T = lum.report.sessionTrials(Data);
S = T.S;
S.Session.MaxTrials = max(S.Session.MaxTrials, T.n);
stimulusSet = T.stimulusSet;
plots = lum.OnlinePlots(S, stimulusSet, 'Subject', T.subject, 'Visible', p.Results.Visible);
queue = stimulusSet.TrialPattern;
queue(1:T.n) = T.pattern;
for k = 1:T.n
    spec = specOf(T, k);
    nextSpec = [];
    if k < T.n
        nextSpec = specOf(T, k + 1);
    end
    result = struct('Outcome', T.outcome(k), 'Choice', T.choice(k), 'Correct', T.correct(k), ...
                    'Rewarded', T.rewarded(k), 'ReactionTime', T.reactionTime(k), ...
                    'CentreRewarded', double(T.centreReward(k) > 0), ...
                    'CentreHoldTime', T.centreHoldTime(k), 'HoldAttempts', T.holdAttempts(k), ...
                    'EarlyWithdrawals', T.attempts(k) - T.holdCompleted(k), ...
                    'HoldCompleted', T.holdCompleted(k), 'HeldFirstAttempt', T.heldFirstAttempt(k));
    plots.setElapsed(T.finish(k));
    plots.update(k, spec, result, nextSpec, queue, T.rewardAmount(k));
end
end


function spec = specOf(T, k)
% The fields of trial k's spec the online figure reads.
centre = T.centreReward(k);
if isnan(centre)
    centre = 0;
end
sides = T.correctSide(k);
if T.bothSidesPay(k)
    sides = [1 2];
end
spec = struct('TrialNumber', k, 'PatternIndex', T.pattern(k), 'StimulusGroup', T.group(k), ...
              'CorrectSide', T.correctSide(k), 'RewardedSides', sides, ...
              'BiasTargetPLeft', T.biasTarget(k), 'OptoOn', T.optoOn(k) == 1, ...
              'HoldDuration', T.holdDuration(k), 'CentreRewardAmount', centre);
end
