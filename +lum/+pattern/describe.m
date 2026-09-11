function text = describe(pattern)
% lum.pattern.describe returns a one-line summary of a light pattern.
%
% Used by the session log, the stimulus designer and the online plots, so that
% what was delivered is legible without decoding a segment matrix. Channels are
% named A and B, as they are everywhere the operator sees them.
%
% Example:
%   'A only: A 0-1000 ms; B dark (1 s window, 1 timer)'
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.patternAt

channelNames = 'AB';
segments = pattern.Segments;
if isempty(segments)
    text = sprintf('%s: dark (%g s window, 0 timers)', pattern.Name, pattern.Duration);
    return
end

parts = cell(1, 2);
for channel = 1:2
    onThisChannel = segments(segments(:, 1) == channel, :);
    if isempty(onThisChannel)
        parts{channel} = sprintf('%s dark', channelNames(channel));
        continue
    end
    spans = compose('%.0f-%.0f', onThisChannel(:, 2) * 1000, ...
                    (onThisChannel(:, 2) + onThisChannel(:, 3)) * 1000);
    parts{channel} = sprintf('%s %s ms', channelNames(channel), strjoin(spans', ','));
end

nTimers = size(segments, 1);
if nTimers == 1
    timerWord = 'timer';
else
    timerWord = 'timers';
end
text = sprintf('%s: %s (%g s window, %d %s)', pattern.Name, strjoin(parts, '; '), ...
               pattern.Duration, nTimers, timerWord);
