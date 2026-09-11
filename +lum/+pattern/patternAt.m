function pattern = patternAt(stimulusSet, index)
% lum.pattern.patternAt recovers one pattern from a stimulus set.
%
% The set stores every pattern in one segment table; this slices out one, in
% constant time, as the struct the trial builder and lum.pattern.describe take.
%
% Arguments:
%   stimulusSet  Stimulus set from lum.pattern.stimulusSet (States may be stripped)
%   index        Pattern index, e.g. spec.PatternIndex
%
% Returns a struct:
%   .Name       Group label, or 'Trial <k>' plus its category in continuous mode
%   .Group      Group (or category) index; 0 when neither
%   .PLeft      Chance that the left port pays
%   .Duration   Stimulus window, seconds
%   .Segments   nSegments x 3 [channel, onset (s), duration (s)], canonical
%   .nChannels  Always 2: channel A (BNC1) and channel B (BNC2)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.stimulusSet, lum.pattern.describe, lum.stim.OptoPattern

if index < 1 || index > stimulusSet.nPatterns || mod(index, 1) ~= 0
    error('lum:pattern:patternAt:badIndex', ...
          'Pattern %g does not exist; the set has %d.', index, stimulusSet.nPatterns);
end
group = stimulusSet.PatternGroup(index);
if stimulusSet.Continuous
    if group > 0
        name = sprintf('Trial %d (%s)', index, stimulusSet.GroupLabels{group});
    else
        name = sprintf('Trial %d', index);
    end
else
    name = stimulusSet.GroupLabels{group};
end
rows = stimulusSet.SegmentStart(index):stimulusSet.SegmentStart(index + 1) - 1;
pattern = struct('Name', name, 'Group', group, 'PLeft', stimulusSet.PatternPLeft(index), ...
                 'Duration', stimulusSet.Duration, 'Segments', stimulusSet.Segments(rows, 2:4), ...
                 'nChannels', 2);
