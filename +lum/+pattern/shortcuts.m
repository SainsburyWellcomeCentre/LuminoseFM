function ceilings = shortcuts(stimulusSet)
% lum.pattern.shortcuts says how well one cue alone could tell the side.
%
% A stimulus set is meant to make the animal use a particular property of the light:
% which channel, how much of A against how much of B, which comes first. If some
% simpler property also tells the side, an animal can succeed without ever using the
% intended one, and its data cannot tell the two apart. This measures that, for the
% simple cues an animal might read (docs/stimulus_family.md, "Cues and shortcuts"):
%
%   AAmount      how long A is lit (u_A)
%   BAmount      how long B is lit (u_B)
%   TotalLight   how long either is lit, added (u_A + u_B)
%   ATimeCourse  when A is lit: A's whole trace, B ignored
%   BTimeCourse  when B is lit
%
% Each value is the best fraction correct an observer could reach reading only that
% cue and knowing the contingency, over the session's trials. AllLight is the same for
% an observer reading everything: 1 for a fixed contingency, less when some groups pay
% either side. A cue at AllLight is enough on its own; a cue at 0.5 tells nothing.
%
% With one pattern per group ('exact') each value is exact: for every value v the cue
% takes, the observer answers the side more often paid when the cue is v. With a
% pattern per trial ('threshold'), where every trial differs, the observer instead
% answers one side below a threshold on the cue and the other above it, the best such
% threshold; the time courses are not computed (every trial's is its own).
%
% Arguments:
%   stimulusSet  A set from lum.pattern.stimulusSet, with PatternPLeft set (its States
%                are not needed, so a set read back from a data file will do)
%
% Returns a struct: AAmount, BAmount, TotalLight, ATimeCourse, BTimeCourse, AllLight
% (fractions correct, NaN when not computed) and Method ('exact' or 'threshold').
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.describeShortcuts, lum.pattern.applyContingency

nPatterns = stimulusSet.nPatterns;
weight = accumarray(stimulusSet.TrialPattern(:), 1, [nPatterns 1])';
pLeft = stimulusSet.PatternPLeft;
d = stimulusSet.Descriptors;
bin = stimulusSet.BinDuration;
aBins = round(d.AOn / bin);  % Whole bins, so equal amounts compare equal
bBins = round(d.BOn / bin);

ceilings = struct('AAmount', NaN, 'BAmount', NaN, 'TotalLight', NaN, 'ATimeCourse', NaN, ...
                  'BTimeCourse', NaN, 'AllLight', NaN, 'Method', 'exact');
total = sum(weight);
if total == 0
    return
end
ceilings.AllLight = sum(weight .* max(pLeft, 1 - pLeft)) / total;

if ~stimulusSet.Continuous
    ceilings.AAmount = lookupScore(aBins, weight, pLeft);
    ceilings.BAmount = lookupScore(bBins, weight, pLeft);
    ceilings.TotalLight = lookupScore(aBins + bBins, weight, pLeft);
    ceilings.ATimeCourse = lookupScore(traceKeys(stimulusSet, 1), weight, pLeft);
    ceilings.BTimeCourse = lookupScore(traceKeys(stimulusSet, 2), weight, pLeft);
else
    ceilings.Method = 'threshold';
    trials = stimulusSet.TrialPattern;
    ceilings.AAmount = thresholdScore(aBins(trials), pLeft(trials));
    ceilings.BAmount = thresholdScore(bBins(trials), pLeft(trials));
    ceilings.TotalLight = thresholdScore(aBins(trials) + bBins(trials), pLeft(trials));
end


function score = lookupScore(values, weight, pLeft)
% Best accuracy answering, for each value of the cue, the side it most often pays.
[~, ~, index] = unique(values(:));
left = accumarray(index, weight(:) .* pLeft(:));
right = accumarray(index, weight(:) .* (1 - pLeft(:)));
score = sum(max(left, right)) / sum(weight);


function score = thresholdScore(values, pLeft)
% Best accuracy answering one side below a threshold on the cue and the other above.
[~, ~, index] = unique(values(:));
left = accumarray(index, pLeft(:));
right = accumarray(index, 1 - pLeft(:));
total = numel(values);
belowLeft = [0; cumsum(left)];
belowRight = [0; cumsum(right)];
leftBelow = belowLeft + (sum(right) - belowRight);   % Left below, right above
rightBelow = belowRight + (sum(left) - belowLeft);   % Right below, left above
score = max([leftBelow; rightBelow]) / total;


function keys = traceKeys(stimulusSet, channel)
% One key per pattern naming when the channel is lit: equal keys, equal traces.
keys = cell(1, stimulusSet.nPatterns);
segments = stimulusSet.Segments;
cycles = round(segments(:, 3:4) / 1e-4);  % The state machine's 100 us cycles
for k = 1:stimulusSet.nPatterns
    rows = stimulusSet.SegmentStart(k):stimulusSet.SegmentStart(k + 1) - 1;
    rows = rows(segments(rows, 2) == channel);
    keys{k} = sprintf('%d,', cycles(rows, :)');
end
