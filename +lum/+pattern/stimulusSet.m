function result = stimulusSet(S, timerBudget, nChannels)
% lum.pattern.stimulusSet builds and validates the session's stimulus set.
%
% The stimulus set is the session-level store of every light pattern the session
% can deliver, which group each belongs to, which side each group pays, and the
% order the trials come in. It is built once, validated once and written to the
% data file once; each trial records only indices into it (README §4.4).
%
% Patterns are held compactly, as one segment table with a row per light segment,
% so that a continuous session of a thousand distinct patterns still costs only a
% few hundred kilobytes to rewrite at each save, and one pattern is recovered in
% constant time (lum.pattern.patternAt).
%
% Arguments:
%   S            Settings: S.Stimulus.Generator, S.Stimulus.Duration,
%                S.Session.MaxTrials, S.Session.UseOpto and S.Task.GroupPLeft
%   timerBudget  Global timers left for light segments (lum.timerBudget). Ignored
%                when the session delivers no light.
%   nChannels    Optical channels the rig has (default 2)
%
% Returns a struct:
%   .Family, .Duration, .BinDuration, .nBins, .nTrials, .Continuous, .Seed
%   .nGroups       Groups, or 2 categories in continuous mode
%   .GroupLabels   1 x nGroups labels
%   .GroupPLeft    1 x nGroups chance that the left port pays
%   .SweepName     What the groups sweep, '' when nothing
%   .SweepValues   1 x nGroups
%   .nPatterns     Patterns: nGroups, or nTrials in continuous mode
%   .PatternGroup  1 x nPatterns group (or category; 0 = neither)
%   .PatternPLeft  1 x nPatterns chance that the left port pays
%   .TrialPattern  1 x nTrials pattern index, in session order
%   .Segments      nSegments x 4 [pattern, channel, onset (s), duration (s)]
%   .SegmentStart  1 x (nPatterns + 1); pattern k is rows SegmentStart(k) to
%                  SegmentStart(k+1) - 1
%   .nTimers       1 x nPatterns global timers each pattern costs
%   .Descriptors   AOn, BOn, Overlap, Dark and BShare per pattern
%   .States        nBins x nPatterns joint states. For previews only: strip it
%                  before storing the set in the data file.
%
% Errors, naming the group or trial, when a pattern needs more global timers than
% the budget, when the contingency does not have one P(left) per group, or when two
% groups deliver identical light but pay different sides — a task the animal
% cannot solve, which runs perfectly and means nothing.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.generate, lum.pattern.patternAt, lum.timerBudget

if nargin < 3 || isempty(nChannels)
    nChannels = 2;
end

G = lum.pattern.generate(S.Stimulus.Generator, S.Stimulus.Duration, S.Session.MaxTrials);

%% Contingency
groupPLeft = S.Task.GroupPLeft(:)';
if numel(groupPLeft) ~= G.nGroups
    if G.Continuous
        what = 'two values, one for A-led and one for B-led patterns';
    else
        what = sprintf('one per group (%d)', G.nGroups);
    end
    error('lum:pattern:stimulusSet:contingencyMismatch', ...
          'P(left) has %d value(s), but the stimulus set needs %s.', numel(groupPLeft), what);
end
if any(~isfinite(groupPLeft)) || any(groupPLeft < 0 | groupPLeft > 1)
    error('lum:pattern:stimulusSet:badPLeft', 'Every P(left) must lie in [0, 1].');
end

nPatterns = size(G.States, 2);
patternPLeft = 0.5 * ones(1, nPatterns);
decided = G.PatternGroup > 0;
patternPLeft(decided) = groupPLeft(G.PatternGroup(decided));

%% Compile each pattern into segments, one global timer each
pieces = cell(1, nPatterns);
nTimers = zeros(1, nPatterns);
for k = 1:nPatterns
    pieces{k} = lum.pattern.fromStates(G.States(:, k), G.BinDuration);
    nTimers(k) = size(pieces{k}, 1);
end

usesLight = ~isfield(S, 'Session') || ~isfield(S.Session, 'UseOpto') || S.Session.UseOpto;
if usesLight && any(nTimers > timerBudget)
    worst = find(nTimers > timerBudget, 1);
    if G.Continuous
        where = sprintf('The pattern for trial %d', worst);
    else
        where = sprintf('Group %d (%s)', worst, G.GroupLabels{worst});
    end
    error('lum:pattern:stimulusSet:timerBudget', ...
          ['%s has %d separate stretches of light, and each costs a global timer, but '...
           'only %d are left for light on this state machine. Use fewer cycles, a longer '...
           'duty cycle, a coarser bin, or blocks instead of a shuffled layout.'], ...
          where, nTimers(worst), timerBudget);
end
if nChannels < 2 && any(G.States(:) >= 2)
    error('lum:pattern:stimulusSet:tooFewChannels', ...
          'The patterns use channel B, but this rig has only %d optical channel.', nChannels);
end

segmentStart = [1, cumsum(nTimers) + 1];
segments = zeros(segmentStart(end) - 1, 4);
for k = 1:nPatterns
    rows = segmentStart(k):segmentStart(k + 1) - 1;
    segments(rows, 1) = k;
    segments(rows, 2:4) = pieces{k};
end

%% Groups the animal could not tell apart
% Identical light paying different sides is a task with no solution: performance
% sits at chance however well the animal learns, and nothing afterwards can tell
% that apart from an untrained animal. Identical groups paying the same side are
% only redundant, and allowed.
if ~G.Continuous
    for a = 1:nPatterns
        for b = a + 1:nPatterns
            if isequal(G.States(:, a), G.States(:, b)) && groupPLeft(a) ~= groupPLeft(b)
                error('lum:pattern:stimulusSet:indistinguishable', ...
                      ['Groups %d (%s) and %d (%s) deliver identical light but pay the left '...
                       'port with P = %g and %g, so nothing tells the animal which side is '...
                       'correct. Change the family''s parameters, or give them the same P(left).'], ...
                      a, G.GroupLabels{a}, b, G.GroupLabels{b}, groupPLeft(a), groupPLeft(b));
            end
        end
    end
end

result = struct('Family', G.Family, 'Duration', G.Duration, 'BinDuration', G.BinDuration, ...
             'nBins', G.nBins, 'nTrials', G.nTrials, 'Continuous', G.Continuous, ...
             'Seed', G.Seed, 'nGroups', G.nGroups, 'GroupLabels', {G.GroupLabels}, ...
             'GroupPLeft', groupPLeft, 'SweepName', G.SweepName, ...
             'SweepValues', G.SweepValues, 'nPatterns', nPatterns, ...
             'PatternGroup', G.PatternGroup, 'PatternPLeft', patternPLeft, ...
             'TrialPattern', G.TrialPattern, 'Segments', segments, ...
             'SegmentStart', segmentStart, 'nTimers', nTimers, ...
             'Descriptors', G.Descriptors, 'States', G.States);
