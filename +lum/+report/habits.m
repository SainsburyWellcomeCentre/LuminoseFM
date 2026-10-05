function H = habits(T)
% lum.report.habits measures a behaviour session's side-port habits, and its blocks' switches.
%
%   H = lum.report.habits(lum.report.sessionTrials(SessionData))
%
% Strategy correction (D23) acts on habits; these say whether a session had them, so a lever
% can be judged and switched off when a habit has gone. Computed as in the 2026-10-05 audit
% of LUMS0014 (docs/plan-habit-levers.md): every side poke of the session in session time,
% sorted; a trial's choice poke is the first side poke at or after its response window opened;
% the last side poke is the side poke just before it, in this trial or an earlier one. A
% repeated poke at one port does not change the side.
%
% Returns a struct:
%   .nChoices              Trials with a choice
%   .oppositeLastSidePoke  Share of choices at the port opposite the last side poke
%                          (.nOpposite: the choices with one before them)
%   .otherSideAfterCentre  After a centre poke, the share of next side pokes at the other
%                          side from the side poke before it (.nAfterCentre pairs)
%   .repeatAfterReward     Share of choices repeating the last choice when it was rewarded
%                          (win-stay; .nAfterReward); .repeatAfterError when it was not
%                          (1 - lose-shift; .nAfterError)
%   .alternation           Share of choices on the other side from the last choice, and
%   .alternationExpected   what the side bias alone gives, 2 p (1 - p)
%   .sideBias              p, the share of choices to the left
%   .sidePokeTrials        Trials with a side poke before the response window, among the
%                          trials with a choice; split as .beforeCentreOnly, .betweenOnly
%                          (between hold attempts) and .both; .sidePokeShare as a share
%   .firstPokeSide         Trials with a choice whose first poke was a side poke, and
%   .firstPokeOpposite     the share of them at the side opposite the choice before
%   .sidePokesPerTrial     Side pokes before the response window, per trial (every trial)
%   .sidePokeDelays        Trials delayed by a side poke (S.GUI.SidePokeBeforeChoice 'Delay')
%   .endedBySidePoke       Trials ended by one ('End trial')
%   .Bins                  The same measures in blocks of 100 trials (.Trials, first and last
%                          of each), for the summary plot 14_Habits
%   .Blocks                In a session with blocks (T.ranBlocks), else empty:
%                          .n blocks, .nSwitches (blocks that follow another),
%                          .firstCorrect / .nFirst (a switch's first trial, choices only),
%                          .secondCorrect / .nSecond, .laterCorrect (trials 3 on),
%                          .trialsToNewSide (median, from the switch to the first choice of
%                          the new side), and .Curve: .Offsets -5..10 from each switch,
%                          .Correct and .NewSide (P(chose the new block's side)), .N
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.report.sessionTrials, lum.report.sessionLog, lum.report.summaryPlots,
% lum.Blocks

pairs = centreSeparatedPairs(T.pokes);
H = measure(T, 1:T.n, pairs);
H.nChoices = sum(~isnan(T.choice));
H.sidePokesPerTrial = mean(T.sidePokesBeforeCentre + T.sidePokesBetween);
H.sidePokeDelays = sum(T.sidePokeDelays > 0);
H.endedBySidePoke = sum(T.outcome == lum.Outcome.SidePokeBeforeChoice);

% In blocks of 100 trials, for the plot
starts = 1:100:max(1, T.n);
names = {'oppositeLastSidePoke', 'otherSideAfterCentre', 'repeatAfterReward', ...
         'repeatAfterError', 'alternation', 'alternationExpected', 'sideBias', 'sidePokeShare'};
bins = struct('Trials', [starts; min(T.n, starts + 99)]');
for i = 1:numel(names)
    bins.(names{i}) = NaN(1, numel(starts));
end
for b = 1:numel(starts)
    part = measure(T, starts(b):min(T.n, starts(b) + 99), pairs);
    for i = 1:numel(names)
        bins.(names{i})(b) = part.(names{i});
    end
end
H.Bins = bins;

H.Blocks = [];
if T.ranBlocks
    H.Blocks = blockMeasures(T);
end
end


function H = measure(T, trials, pairs)
% The habit measures over a range of trials; pairs from centreSeparatedPairs.
H = struct();
chose = trials(~isnan(T.choice(trials)));
valid = chose(~isnan(T.lastSidePoke(chose)));
H.nOpposite = numel(valid);
H.oppositeLastSidePoke = share(T.choice(valid) ~= T.lastSidePoke(valid));

inRange = pairs.Time >= T.start(trials(1)) & pairs.Time <= T.finish(trials(end));
H.nAfterCentre = sum(inRange);
H.otherSideAfterCentre = share(pairs.Other(inRange));

c = T.choice(chose);
r = T.rewarded(chose) == 1;
repeat = c(2:end) == c(1:end - 1);
afterReward = r(1:end - 1);
H.nAfterReward = sum(afterReward);
H.nAfterError = sum(~afterReward);
H.repeatAfterReward = share(repeat(afterReward));
H.repeatAfterError = share(repeat(~afterReward));
H.alternation = share(~repeat);
p = share(c == 1);
H.sideBias = p;
H.alternationExpected = 2 * p * (1 - p);

before = T.sidePokesBeforeCentre(chose) > 0;
between = T.sidePokesBetween(chose) > 0;
H.sidePokeTrials = sum(before | between);
H.sidePokeShare = share(before | between);
H.beforeCentreOnly = sum(before & ~between);
H.betweenOnly = sum(between & ~before);
H.both = sum(before & between);
firstSide = T.firstPokeSide(chose) >= 1;
H.firstPokeSide = sum(firstSide);
previous = [NaN, c(1:end - 1)];
previous = previous(1:numel(c));
opposite = firstSide & ~isnan(previous);
H.firstPokeOpposite = share(T.firstPokeSide(chose(opposite)) ~= previous(opposite));
end


function B = blockMeasures(T)
% The first trials after each block switch, and the switch-aligned curve.
B = struct();
B.n = numel(unique(T.block(T.block > 0)));
switches = find(T.blockFirst & [false, T.block(1:end - 1) > 0]);
B.nSwitches = numel(switches);
scored = T.correct;
first = switches(~isnan(scored(switches)));
B.nFirst = numel(first);
B.firstCorrect = sum(scored(first) == 1);
second = switches + 1;
second = second(second <= T.n);
second = second(T.block(second) == T.block(second - 1) & ~isnan(scored(second)));
B.nSecond = numel(second);
B.secondCorrect = sum(scored(second) == 1);
later = T.blockPosition >= 3 & ~isnan(scored);
B.laterCorrect = share(scored(later) == 1);
toNewSide = NaN(1, numel(switches));
for i = 1:numel(switches)
    s = switches(i);
    inBlock = s:find([T.block(s:end) ~= T.block(s), true], 1) + s - 2;
    found = find(T.choice(inBlock) == T.blockSide(s), 1);
    if ~isempty(found)
        toNewSide(i) = found;
    end
end
B.trialsToNewSide = median(toNewSide, 'omitnan');
offsets = -5:10;
[correct, newSide, counts] = deal(zeros(1, numel(offsets)));
for o = 1:numel(offsets)
    trials = switches + offsets(o);
    keep = trials >= 1 & trials <= T.n;
    trials = trials(keep);
    side = T.blockSide(switches(keep));
    chose = ~isnan(T.choice(trials));
    counts(o) = sum(chose);
    correct(o) = share(scored(trials(chose)) == 1);
    newSide(o) = share(T.choice(trials(chose)) == side(chose));
end
B.Curve = struct('Offsets', offsets, 'Correct', correct, 'NewSide', newSide, 'N', counts);
end


function pairs = centreSeparatedPairs(pokes)
% Every two consecutive side pokes with a centre poke between them: .Time of the first, and
% .Other, true when the second was at the other side.
nSide = numel(pokes.Left) + numel(pokes.Right);
times = [pokes.Left, pokes.Right, pokes.Centre];
kind = [ones(1, numel(pokes.Left)), 2 * ones(1, numel(pokes.Right)), zeros(1, numel(pokes.Centre))];
[times, order] = sort(times);
kind = kind(order);
isSide = kind > 0;
sideIndex = cumsum(isSide);            % Side pokes so far, at each poke
sideTimes = times(isSide);
sides = kind(isSide);
% A centre poke after side poke i and before side poke i + 1 joins the pair (i, i + 1)
after = unique(sideIndex(~isSide & sideIndex >= 1 & sideIndex < nSide));
pairs = struct('Time', sideTimes(after), 'Other', sides(after + 1) ~= sides(after));
end


function value = share(tf)
% The share of true values; NaN for none.
value = NaN;
if ~isempty(tf)
    value = mean(tf);
end
end
