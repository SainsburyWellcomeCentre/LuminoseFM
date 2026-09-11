function segments = fromStates(states, binDuration)
% lum.pattern.fromStates turns one pattern's joint states into light segments.
%
% The generator thinks in bins of joint state; the state machine thinks in global
% timers, one per contiguous stretch of light on one channel (architecture
% decision D1). This is the translation between the two: each maximal run of bins
% in which a channel is on becomes one segment, [channel, onset, duration].
%
% The result is already canonical — sorted by channel then onset, with no two
% segments on a channel touching — so its row count is exactly the number of
% global timers the pattern costs.
%
% Arguments:
%   states       nBins x 1 joint states: 0 dark, 1 A only, 2 B only, 3 A and B
%   binDuration  Bin width in seconds
%
% Returns an nSegments x 3 matrix [channel, onset (s), duration (s)], channel 1 = A
% (BNC1) and 2 = B (BNC2), times rounded to the state machine's 100 us cycle.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.generate, lum.pattern.canonicalise, lum.stim.OptoPattern

cyclePeriod = 1e-4;

states = uint8(states(:));
perChannel = cell(2, 1);
for channel = 1:2
    lit = bitand(states, uint8(channel)) ~= 0;
    edges = diff([false; lit; false]);
    starts = find(edges == 1);
    stops = find(edges == -1);
    perChannel{channel} = [repmat(channel, numel(starts), 1), ...
                           (starts - 1) * binDuration, (stops - starts) * binDuration];
end
segments = [perChannel{1}; perChannel{2}];
if isempty(segments)
    segments = zeros(0, 3);
    return
end
segments(:, 2:3) = round(segments(:, 2:3) / cyclePeriod) * cyclePeriod;
