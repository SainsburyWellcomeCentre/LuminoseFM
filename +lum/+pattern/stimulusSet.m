function result = stimulusSet(S, timerBudget, nChannels)
% lum.pattern.stimulusSet builds and validates the session's stimulus set.
%
% The stimulus set is the session-level store of every light pattern the session
% can deliver, which group each belongs to, which side each group pays, and the
% order the trials come in. It is built once, validated once and written to the
% data file once; each trial records only indices into it (docs/data-format.md).
%
% Patterns are held compactly, as one segment table with a row per light segment,
% so that a session of a thousand distinct patterns still costs only a few hundred
% kilobytes to rewrite at each save, and one pattern is recovered in constant time
% (lum.pattern.patternAt).
%
% Arguments:
%   S            Settings: S.Stimulus.Generator, S.Stimulus.Duration,
%                S.Session.MaxTrials, S.Session.UseOpto, S.Task.GroupPLeft and
%                S.Task.ReverseContingency
%   timerBudget  Global timers left for light segments (lum.timerBudget). Ignored
%                when the session delivers no light.
%   nChannels    Optical channels the rig has (default 2)
%
% Returns a struct:
%   .Family, .Duration, .BinDuration, .nBins, .nTrials, .Continuous, .Seed
%   .nGroups       Groups
%   .GroupLabels   1 x nGroups labels
%   .FamilyPLeft   1 x nGroups chance of paying left the family intends
%   .GroupPLeft    1 x nGroups chance that the left port pays, as the session will
%                  run it: reversed already, when the contingency is reversed
%   .BasePLeft     1 x nGroups the same before any reversal: S.Task.GroupPLeft, or
%                  FamilyPLeft when that is empty
%   .PLeftFromFamily  True when the family's contingency was used (S.Task.GroupPLeft
%                  empty), false when the operator typed their own
%   .Reversed      True when S.Task.ReverseContingency swapped the sides
%   .EvidenceName, .Evidence, .Boundary   The decision variable per pattern and the
%                  boundary in the plane of u_A and u_B (lum.pattern.generate)
%   .nPatterns     Patterns: nGroups, or nTrials when every trial has its own
%   .PatternGroup  1 x nPatterns group
%   .PatternPLeft  1 x nPatterns chance that the left port pays
%   .TrialPattern  1 x nTrials pattern index, in session order
%   .Segments      nSegments x 4 [pattern, channel, onset (s), duration (s)]
%   .SegmentStart  1 x (nPatterns + 1); pattern k is rows SegmentStart(k) to
%                  SegmentStart(k+1) - 1
%   .nTimers       1 x nPatterns global timers each pattern costs
%   .Descriptors   AOn, BOn, Overlap, Dark, BShare, ASegments, BSegments per pattern
%   .Shortcuts     The best score one cue alone could reach (lum.pattern.shortcuts)
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
% See also: lum.pattern.generate, lum.pattern.applyContingency, lum.pattern.patternAt,
%           lum.timerBudget

if nargin < 3 || isempty(nChannels)
    nChannels = 2;
end

G = lum.pattern.generate(S.Stimulus.Generator, S.Stimulus.Duration, S.Session.MaxTrials);

%% Compile each pattern into segments, one global timer each
nPatterns = size(G.States, 2);
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
        where = sprintf('The pattern for trial %d (%s)', worst, ...
                        G.GroupLabels{G.PatternGroup(worst)});
    else
        where = sprintf('Group %d (%s)', worst, G.GroupLabels{worst});
    end
    error('lum:pattern:stimulusSet:timerBudget', ...
          ['%s has %d separate stretches of light, and each costs a global timer, but '...
           'only %d are left for light on this state machine. Use fewer slots, letters or '...
           'turns, a fill of 1 so that neighbouring flashes on one channel join, or a '...
           'coarser bin.'], where, nTimers(worst), timerBudget);
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

result = struct('Family', G.Family, 'Duration', G.Duration, 'BinDuration', G.BinDuration, ...
             'nBins', G.nBins, 'nTrials', G.nTrials, 'Continuous', G.Continuous, ...
             'Seed', G.Seed, 'nGroups', G.nGroups, 'GroupLabels', {G.GroupLabels}, ...
             'FamilyPLeft', G.FamilyPLeft, 'GroupPLeft', G.FamilyPLeft, ...
             'BasePLeft', G.FamilyPLeft, 'PLeftFromFamily', true, 'Reversed', false, ...
             'EvidenceName', G.EvidenceName, 'Evidence', G.Evidence, 'Boundary', G.Boundary, ...
             'nPatterns', nPatterns, 'PatternGroup', G.PatternGroup, ...
             'PatternPLeft', 0.5 * ones(1, nPatterns), 'TrialPattern', G.TrialPattern, ...
             'Segments', segments, 'SegmentStart', segmentStart, 'nTimers', nTimers, ...
             'Descriptors', G.Descriptors, 'Shortcuts', struct(), 'States', G.States);

% Reversing the contingency swaps the sides for every group at once: the light that
% paid left pays right and the other way about. It is applied here, once, so that the
% set, the online plots, lum.nextTrialSpec and every trial record read the same
% contingency; S.Task.GroupPLeft keeps the operator's own numbers (or stays empty for
% the family's), and BasePLeft carries them into the data file beside the reversed ones.
reversed = isfield(S, 'Task') && isfield(S.Task, 'ReverseContingency') ...
           && isequal(logical(S.Task.ReverseContingency), true);
groupPLeft = [];
if isfield(S, 'Task') && isfield(S.Task, 'GroupPLeft')
    groupPLeft = S.Task.GroupPLeft;
end
result = lum.pattern.applyContingency(result, groupPLeft, reversed);
