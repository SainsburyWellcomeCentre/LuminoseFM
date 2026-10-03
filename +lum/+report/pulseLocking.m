function L = pulseLocking(T, varargin)
% lum.report.pulseLocking measures how early withdrawals line up with the light's carrier pulses.
%
%   L = lum.report.pulseLocking(lum.report.sessionTrials(SessionData))
%
% A sign that the animal senses the light that needs no discrimination between groups: PulsePal
% fills each light segment with its carrier's pulses, starting as the segment starts (D1), so
% an animal that senses the pulses tends to leave the centre port at a fixed time after one.
% Each early withdrawal made while a light segment was on, and at least MinTime into it, is
% taken as the time since that segment began, folded on the carrier's period (its phase). The
% locking is the length of the mean phase vector, R: 0 for withdrawals spread evenly over the
% period, 1 for all at one phase. Found in LUMS0014's sessions of 2026-09-28 to 2026-10-03
% (docs/learning-time-literature.md).
%
% R is not judged by a Rayleigh test: the withdrawal times have a shape of their own (most
% come late in the window), which alone gives R above 0. P compares R with withdrawal times
% drawn from that shape smoothed with a Gaussian of half the period, which keeps the shape
% and removes any structure at the carrier's frequency. The same test at other frequencies
% (Spectrum) shows whether the carrier's stands out.
%
% Sessions without light are measured against the pulses their trials would have had (the
% session's carrier on the stimulus set's segments) as a control: no locking is expected.
% Trials with the light switched off are left out of a session with light.
%
% Arguments:
%   T  The session's trials (lum.report.sessionTrials)
%
% Options:
%   'MinTime'      Withdrawals earlier into a segment are left out (s, default 0.02): poke
%                  bounces cluster in the first few ms
%   'Frequencies'  Frequencies of the spectrum (Hz, default 5:50)
%   'Surrogates'   Surrogate sets for P (default 2000); a fifth of that for each frequency of
%                  the spectrum
%   'Seed'         Seed of the surrogates' private stream (default 1): the same session always
%                  gives the same P
%
% Returns a struct:
%   .Measured    true when there was something to measure; false with .Reason saying why
%   .Reason      '' or why not (constant light, different carriers on A and B, no withdrawals)
%   .Light       true for trials with light, false for a session without (the control)
%   .Frequency   The carrier's frequency (Hz); .PulseWidth (s); .Period (s)
%   .n           Withdrawals measured
%   .Time        1 x n: seconds from the segment's start to the withdrawal
%   .Phase       1 x n: seconds from the last pulse's start (0 to Period)
%   .Channel     1 x n: the segment's channel, 1 (A) or 2 (B)
%   .R, .P       Locking at the carrier's frequency and its surrogate p-value
%   .MeanPhase   Seconds after a pulse's start the withdrawals gather at (NaN when n is 0)
%   .Threshold   R that 95% of the surrogates stay below
%   .ByChannel   1 x 2 struct: n, R, P, MeanPhase of A's and B's withdrawals
%   .Spectrum    Struct: Frequencies (Hz), R, Threshold (each frequency's 95th percentile)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.report.sessionTrials, lum.report.summaryPlots, lum.report.sessionLog

p = inputParser;
p.FunctionName = 'lum.report.pulseLocking';
addParameter(p, 'MinTime', 0.02, @(x) isscalar(x) && x >= 0);
addParameter(p, 'Frequencies', 5:50, @(x) isnumeric(x) && all(x > 0));
addParameter(p, 'Surrogates', 2000, @(x) isscalar(x) && x >= 20);
addParameter(p, 'Seed', 1, @isscalar);
parse(p, varargin{:});
options = p.Results;

carrier = T.S.Light.Carrier;
emptyChannel = struct('n', 0, 'R', NaN, 'P', NaN, 'MeanPhase', NaN);
L = struct('Measured', false, 'Reason', '', 'Light', any(T.optoOn == 1), ...
           'Frequency', carrier(1).Frequency, 'PulseWidth', carrier(1).PulseWidth, ...
           'Period', NaN, 'n', 0, 'Time', [], 'Phase', [], 'Channel', [], 'R', NaN, 'P', NaN, ...
           'MeanPhase', NaN, 'Threshold', NaN, 'ByChannel', [emptyChannel emptyChannel], ...
           'Spectrum', struct('Frequencies', options.Frequencies, ...
                              'R', NaN(size(options.Frequencies)), ...
                              'Threshold', NaN(size(options.Frequencies))));

[time, channel, reach] = withdrawalsInLight(T, L.Light, options.MinTime);
frequencies = [carrier.Frequency];
used = unique(channel);
if isempty(used)
    used = 1:numel(carrier);
end
if any(frequencies(used) == 0)
    L.Reason = 'constant light has no pulses to lock to';
    return
end
if numel(unique(frequencies(used))) > 1
    L.Reason = 'channels A and B have different carriers';
    return
end
L.Frequency = carrier(used(1)).Frequency;
L.PulseWidth = carrier(used(1)).PulseWidth;
L.Period = 1 / L.Frequency;
if isempty(time)
    L.Reason = 'no early withdrawals while the light was on';
    return
end

L.Measured = true;
L.n = numel(time);
L.Time = time;
L.Channel = channel;
L.Phase = mod(time, L.Period);
stream = RandStream('mt19937ar', 'Seed', options.Seed);
window = [options.MinTime, reach];
[L.R, L.P, L.MeanPhase, L.Threshold] = locking(time, L.Frequency, window, options.Surrogates, stream);
for c = 1:2
    mine = time(channel == c);
    L.ByChannel(c).n = numel(mine);
    if ~isempty(mine)
        [L.ByChannel(c).R, L.ByChannel(c).P, L.ByChannel(c).MeanPhase] = ...
            locking(mine, L.Frequency, window, options.Surrogates, stream);
    end
end
nSpectrum = max(20, round(options.Surrogates / 5));
for i = 1:numel(options.Frequencies)
    [L.Spectrum.R(i), ~, ~, L.Spectrum.Threshold(i)] = ...
        locking(time, options.Frequencies(i), window, nSpectrum, stream);
end
end


function [time, channel, reach] = withdrawalsInLight(T, withLight, minTime)
% Each early withdrawal made while a segment was on: seconds into the latest segment then on,
% and its channel; reach is the longest such segment. Without light, the segments the trials
% would have had.
stimulusSet = T.stimulusSet;
segments = stimulusSet.Segments;   % rows: pattern, channel, onset, duration
withdrawals = find(~T.attemptCompleted);
time = zeros(1, numel(withdrawals));
channel = zeros(1, numel(withdrawals));
reach = minTime;
kept = 0;
for w = withdrawals
    trial = T.attemptTrial(w);
    if withLight && T.optoOn(trial) ~= 1
        continue
    end
    pattern = T.pattern(trial);
    if isnan(pattern)
        continue
    end
    rows = stimulusSet.SegmentStart(pattern):stimulusSet.SegmentStart(pattern + 1) - 1;
    since = T.attemptTime(w) - segments(rows, 3);
    lit = since >= minTime & since < segments(rows, 4);
    if ~any(lit)
        continue
    end
    % The latest segment to start is the one whose pulses came last.
    candidates = find(lit);
    [~, latest] = min(since(candidates));
    row = rows(candidates(latest));
    kept = kept + 1;
    time(kept) = since(candidates(latest));
    channel(kept) = segments(row, 2);
    reach = max(reach, segments(row, 4));
end
time = time(1:kept);
channel = channel(1:kept);
end


function [R, P, meanPhase, threshold] = locking(time, frequency, window, nSurrogates, stream)
% R at one frequency, its p-value and 95th percentile against surrogates drawn from the
% times' distribution smoothed over half a period, and the mean phase (s).
vector = mean(exp(2i * pi * frequency * time));
R = abs(vector);
meanPhase = mod(angle(vector), 2 * pi) / (2 * pi * frequency);
[grid, cdf] = smoothedDistribution(time, window, 1 / (2 * frequency));
n = numel(time);
nulls = zeros(nSurrogates, 1);
for s = 1:nSurrogates
    drawn = interp1(cdf, grid, rand(stream, n, 1), 'linear', window(1));
    nulls(s) = abs(mean(exp(2i * pi * frequency * drawn)));
end
P = (1 + sum(nulls >= R)) / (1 + nSurrogates);
sorted = sort(nulls);
threshold = sorted(max(1, ceil(0.95 * nSurrogates)));
end


function [grid, cdf] = smoothedDistribution(time, window, sigma)
% The times' distribution smoothed with a Gaussian, reflected at both ends of the window,
% as a cumulative distribution on a fine grid with strictly rising values.
step = min(5e-4, sigma / 10);
grid = (window(1):step:max(window(2), window(1) + step))';
density = zeros(size(grid));
mirrors = [time(:); 2 * window(1) - time(:); 2 * window(2) - time(:)];
for chunk = 1:500:numel(mirrors)
    part = mirrors(chunk:min(end, chunk + 499))';
    density = density + sum(exp(-(grid - part) .^ 2 / (2 * sigma ^ 2)), 2);
end
density = density + eps;
cdf = cumsum(density) / sum(density);
[cdf, keep] = unique(cdf);
grid = grid(keep);
end
