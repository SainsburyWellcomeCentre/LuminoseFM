function pattern = canonicalise(pattern)
% lum.pattern.canonicalise puts a light pattern into its normal form.
%
% A pattern says which optical channel is on, when, during the stimulus window.
% Its normal form is what the trial builder compiles into global timers: segments
% sorted by channel then onset, with segments that overlap or touch on the same
% channel merged into one.
%
% Merging matters for more than tidiness. Each contiguous segment costs one global
% timer, and two timers driving the same BNC line would fight: the first to elapse
% pulls the line low while the other still considers itself on. Two segments that
% overlap on one channel are optically one longer segment, so this is the
% representation that both saves timers and is correct.
%
% Patterns from lum.pattern.fromStates are already canonical; this is for patterns
% built by hand, in tests or analysis scripts.
%
% Arguments:
%   pattern  Struct with fields Name, Duration, Segments, nChannels. Segments is
%            nSegments x 3: [channel, onset (s), duration (s)].
%
% Returns the pattern with Segments in normal form and missing fields defaulted.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.check, lum.pattern.validate, lum.pattern.fromStates

tolerance = 1e-9;  % Segments closer than a nanosecond are the same instant

if ~isstruct(pattern) || ~isscalar(pattern)
    error('lum:pattern:canonicalise:badInput', 'A light pattern must be a scalar struct.');
end

defaults = struct('Name', 'unnamed', 'Duration', 0, 'Segments', zeros(0, 3), 'nChannels', 2);
fields = fieldnames(defaults);
for i = 1:numel(fields)
    if ~isfield(pattern, fields{i}) || isempty(pattern.(fields{i}))
        pattern.(fields{i}) = defaults.(fields{i});
    end
end
% A dark pattern legitimately has no segments, so restore the right shape.
if isempty(pattern.Segments)
    pattern.Segments = zeros(0, 3);
end

segments = pattern.Segments;
if size(segments, 2) ~= 3
    % Leave malformed input alone: lum.pattern.check reports it with a useful message.
    return
end

segments = sortrows(segments, [1 2]);

merged = zeros(size(segments));
nMerged = 0;
for i = 1:size(segments, 1)
    channel = segments(i, 1);
    onset = segments(i, 2);
    offset = onset + segments(i, 3);
    if nMerged > 0 && merged(nMerged, 1) == channel ...
            && onset <= merged(nMerged, 2) + merged(nMerged, 3) + tolerance
        % Overlapping or touching the previous segment on this channel: extend it.
        previousOffset = merged(nMerged, 2) + merged(nMerged, 3);
        merged(nMerged, 3) = max(previousOffset, offset) - merged(nMerged, 2);
    else
        nMerged = nMerged + 1;
        merged(nMerged, :) = [channel onset offset - onset];
    end
end

pattern.Segments = merged(1:nMerged, :);
