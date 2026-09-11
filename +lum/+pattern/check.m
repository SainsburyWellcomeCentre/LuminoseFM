function problems = check(pattern, timerBudget)
% lum.pattern.check reports everything wrong with a light pattern.
%
% Returns a cell array of problem descriptions, empty when the pattern is usable,
% so that a caller can show the operator what is wrong without throwing;
% lum.pattern.validate calls it and turns any result into an error.
%
% Arguments:
%   pattern      Light pattern, ideally already through lum.pattern.canonicalise
%   timerBudget  Global timers available for light segments. Pass the result of
%                lum.timerBudget: the emulated state machine has 5 in all, the rig 16.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.canonicalise, lum.pattern.validate

problems = {};
tolerance = 1e-9;

if ~isstruct(pattern) || ~isscalar(pattern)
    problems{end+1} = 'A light pattern must be a scalar struct.';
    return
end

required = {'Name', 'Duration', 'Segments', 'nChannels'};
missing = required(~isfield(pattern, required));
if ~isempty(missing)
    problems{end+1} = sprintf('Missing field(s): %s.', strjoin(missing, ', '));
    return
end

if ~isnumeric(pattern.Duration) || ~isscalar(pattern.Duration) ...
        || ~isfinite(pattern.Duration) || pattern.Duration < 0
    problems{end+1} = 'Duration must be a finite, non-negative scalar (seconds).';
end

segments = pattern.Segments;
if ~isnumeric(segments) || (~isempty(segments) && size(segments, 2) ~= 3)
    problems{end+1} = ['Segments must be an nSegments x 3 numeric matrix: '...
                       '[channel, onset, duration].'];
    return
end
if any(~isfinite(segments(:)))
    problems{end+1} = 'Segments contains non-finite values.';
    return
end

nSegments = size(segments, 1);
if nSegments > timerBudget
    problems{end+1} = sprintf( ...
        ['Pattern "%s" needs %d global timers (one per stretch of light) but only %d are '...
         'available. Reduce the number of segments, or run on hardware with a larger '...
         'timer budget.'], pattern.Name, nSegments, timerBudget);
end

badChannels = unique(segments(:, 1));
badChannels = badChannels(badChannels < 1 | badChannels > pattern.nChannels ...
                          | mod(badChannels, 1) ~= 0);
if ~isempty(badChannels)
    problems{end+1} = sprintf('Channel(s) %s are outside 1..%d.', ...
                              mat2str(badChannels(:)'), pattern.nChannels);
end

if any(segments(:, 2) < -tolerance)
    problems{end+1} = 'Segment onsets must not be negative.';
end
if any(segments(:, 3) <= tolerance)
    problems{end+1} = 'Every segment must have a strictly positive duration.';
end

offsets = segments(:, 2) + segments(:, 3);
if any(offsets > pattern.Duration + tolerance)
    problems{end+1} = sprintf( ...
        'Segment(s) extend to %.4f s, past the pattern duration of %.4f s.', ...
        max(offsets), pattern.Duration);
end

% Segments on the same channel must not overlap. canonicalise() merges those, so
% this only fires on a pattern that skipped it — worth catching, because two
% timers on one BNC line cut each other short.
for channel = 1:pattern.nChannels
    onThisChannel = sortrows(segments(segments(:, 1) == channel, :), 2);
    for i = 2:size(onThisChannel, 1)
        previousOffset = onThisChannel(i-1, 2) + onThisChannel(i-1, 3);
        if onThisChannel(i, 2) < previousOffset - tolerance
            problems{end+1} = sprintf( ...
                ['Channel %d has overlapping segments (one ends at %.4f s, the next '...
                 'starts at %.4f s). Run the pattern through '...
                 'lum.pattern.canonicalise first.'], channel, previousOffset, ...
                onThisChannel(i, 2)); %#ok<AGROW>
            break
        end
    end
end
