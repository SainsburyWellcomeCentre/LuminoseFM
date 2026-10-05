function L = pulseLocking(T, varargin)
% lum.report.pulseLocking measures how early withdrawals line up with the light's carrier pulses.
%
%   L = lum.report.pulseLocking(lum.report.sessionTrials(SessionData))
%
% A sign that the animal senses the light that needs no discrimination between groups: PulsePal
% fills each light segment with its carrier's pulses, starting as the segment starts (D1), so
% an animal that senses the pulses tends to leave the centre port at a fixed time after one.
% Each early withdrawal made while a light segment was on, and at least MinTime into it, is
% taken as the time since that segment began, folded on the carrier's period (its phase), and
% becomes a unit vector at that phase. Found in LUMS0014's sessions of 2026-09-28 to
% 2026-10-03 (docs/learning-time-literature.md).
%
% The withdrawal times have a shape of their own (most come late in the window), and that
% shape alone gives a mean vector of some length at some phase: in LUMS0014's sessions about
% 0.05 at 36 ms after a 20 Hz pulse began, light or no light. So the mean vector's length R and
% its phase say little by themselves. Surrogate withdrawal times are drawn from the times'
% distribution smoothed with a Gaussian of half the period, which keeps the shape and removes
% any structure at the carrier's frequency; their mean vector is the shape's. What the shape
% does not explain is the observed mean vector minus the shape's: its length (Excess), its
% phase (ExcessPhase, the time after a pulse began that the locking points to) and ExcessP,
% how often a surrogate lies as far from the shape's vector, in any direction. The same at
% other frequencies (Spectrum) shows whether the carrier's stands out; below about 10 Hz the
% half-period smoothing blurs the shape itself, so the spectrum starts there.
%
% The pulses start at light onset, which is the poke at latency 0, so a feature of the
% withdrawal times narrower than about a period passes for locking: the smoothing takes it out
% of the surrogates. LUMS0014's habituation sessions have one (a peak of withdrawals 30-70 ms
% after the poke), and two of the three show locking beyond their shape without any light;
% simulated withdrawals with such a peak and no pulses do in 80% of sets, against 5-8% for
% withdrawals rising smoothly to the end of the window, as in the sessions with light. Only a
% change of the carrier's frequency tells pulse locking from such a feature.
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
%   'Frequencies'  Frequencies of the spectrum (Hz, default 10:50)
%   'Surrogates'   Surrogate sets for P (default 2000); a fifth of that for each frequency of
%                  the spectrum
%   'Seed'         Seed of the surrogates' private stream (default 1): the same session always
%                  gives the same P
%
% Returns a struct:
%   .Measured     true when there was something to measure; false with .Reason saying why
%   .Reason       '' or why not (constant light, different carriers on A and B, no withdrawals)
%   .Light        true for trials with light, false for a session without (the control)
%   .Frequency    The carrier's frequency (Hz); .PulseWidth (s); .Period (s)
%   .n            Withdrawals measured
%   .Time         1 x n: seconds from the segment's start to the withdrawal
%   .Phase        1 x n: seconds from the last pulse's start (0 to Period)
%   .Channel      1 x n: the segment's channel, 1 (A) or 2 (B)
%   .Excess       Length of the mean vector beyond the shape's (0 to 2)
%   .ExcessPhase  Seconds after a pulse's start the locking beyond the shape points to
%   .ExcessP      Its surrogate p-value
%   .ExcessThreshold  Excess that 95% of the surrogates stay below
%   .R, .P        Length of the observed mean vector, and how often a surrogate's is as long
%   .MeanPhase    Seconds after a pulse's start of the observed mean vector
%   .Threshold    R that 95% of the surrogates stay below
%   .Shape, .ShapePhase  Length and phase (s) of the shape's mean vector
%   .ShapeEdges   1 x 11: phase bins over the period (s); .ShapeShare 1 x 10: the share of
%                 withdrawals the shape alone puts in each
%   .ByChannel    1 x 2 struct: n, Excess, ExcessPhase, ExcessP, R, P, MeanPhase of A's and
%                 B's withdrawals
%   .Spectrum     Struct: Frequencies (Hz), Excess, ExcessThreshold, R, Threshold (each
%                 frequency's 95th percentiles)
% Phases are NaN when n is 0.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.report.sessionTrials, lum.report.summaryPlots, lum.report.sessionLog

p = inputParser;
p.FunctionName = 'lum.report.pulseLocking';
addParameter(p, 'MinTime', 0.02, @(x) isscalar(x) && x >= 0);
addParameter(p, 'Frequencies', 10:50, @(x) isnumeric(x) && all(x > 0));
addParameter(p, 'Surrogates', 2000, @(x) isscalar(x) && x >= 20);
addParameter(p, 'Seed', 1, @isscalar);
parse(p, varargin{:});
options = p.Results;

carrier = T.S.Light.Carrier;
emptyChannel = struct('n', 0, 'Excess', NaN, 'ExcessPhase', NaN, 'ExcessP', NaN, 'R', NaN, ...
                      'P', NaN, 'MeanPhase', NaN);
noSpectrum = NaN(size(options.Frequencies));
L = struct('Measured', false, 'Reason', '', 'Light', any(T.optoOn == 1), ...
           'Frequency', carrier(1).Frequency, 'PulseWidth', carrier(1).PulseWidth, ...
           'Period', NaN, 'n', 0, 'Time', [], 'Phase', [], 'Channel', [], ...
           'Excess', NaN, 'ExcessPhase', NaN, 'ExcessP', NaN, 'ExcessThreshold', NaN, ...
           'R', NaN, 'P', NaN, 'MeanPhase', NaN, 'Threshold', NaN, 'Shape', NaN, ...
           'ShapePhase', NaN, 'ShapeEdges', [], 'ShapeShare', [], ...
           'ByChannel', [emptyChannel emptyChannel], ...
           'Spectrum', struct('Frequencies', options.Frequencies, 'Excess', noSpectrum, ...
                              'ExcessThreshold', noSpectrum, 'R', noSpectrum, ...
                              'Threshold', noSpectrum));

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
whole = locking(time, L.Frequency, window, options.Surrogates, stream);
for name = {'Excess', 'ExcessPhase', 'ExcessP', 'ExcessThreshold', 'R', 'P', 'MeanPhase', ...
            'Threshold', 'Shape', 'ShapePhase'}
    L.(name{1}) = whole.(name{1});
end
L.ShapeEdges = linspace(0, L.Period, 11);
L.ShapeShare = foldedShare(whole.Grid, whole.Density, L.ShapeEdges);
for c = 1:2
    mine = time(channel == c);
    L.ByChannel(c).n = numel(mine);
    if ~isempty(mine)
        part = locking(mine, L.Frequency, window, options.Surrogates, stream);
        for name = {'Excess', 'ExcessPhase', 'ExcessP', 'R', 'P', 'MeanPhase'}
            L.ByChannel(c).(name{1}) = part.(name{1});
        end
    end
end
nSpectrum = max(20, round(options.Surrogates / 5));
for i = 1:numel(options.Frequencies)
    one = locking(time, options.Frequencies(i), window, nSpectrum, stream);
    L.Spectrum.Excess(i) = one.Excess;
    L.Spectrum.ExcessThreshold(i) = one.ExcessThreshold;
    L.Spectrum.R(i) = one.R;
    L.Spectrum.Threshold(i) = one.Threshold;
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


function result = locking(time, frequency, window, nSurrogates, stream)
% The observed mean vector at one frequency against surrogates drawn from the times'
% distribution smoothed over half a period: its length and phase, the shape's (the surrogates'
% mean vector), the part beyond the shape, p-values and 95th percentiles. Phases in seconds.
% Also the smoothed distribution, for the shape's folded share.
vector = mean(exp(2i * pi * frequency * time));
[grid, cdf, fullGrid, density] = smoothedDistribution(time, window, 1 / (2 * frequency));
n = numel(time);
nulls = complex(zeros(nSurrogates, 1));
for s = 1:nSurrogates
    drawn = interp1(cdf, grid, rand(stream, n, 1), 'linear', window(1));
    nulls(s) = mean(exp(2i * pi * frequency * drawn));
end
shape = mean(nulls);
asPhase = @(z) mod(angle(z), 2 * pi) / (2 * pi * frequency);
result.R = abs(vector);
result.P = (1 + sum(abs(nulls) >= result.R)) / (1 + nSurrogates);
result.MeanPhase = asPhase(vector);
result.Threshold = percentile95(abs(nulls));
result.Shape = abs(shape);
result.ShapePhase = asPhase(shape);
result.Excess = abs(vector - shape);
result.ExcessPhase = asPhase(vector - shape);
result.ExcessP = (1 + sum(abs(nulls - shape) >= result.Excess)) / (1 + nSurrogates);
result.ExcessThreshold = percentile95(abs(nulls - shape));
result.Grid = fullGrid;
result.Density = density;
end


function value = percentile95(values)
% The value 95% of values stay below.
sorted = sort(values);
value = sorted(max(1, ceil(0.95 * numel(sorted))));
end


function share = foldedShare(grid, density, edges)
% The share of a distribution on grid (s) that falls in each phase bin of edges, folded on
% the period edges(end).
phase = mod(grid, edges(end));
bin = discretize(phase, edges);
bin(isnan(bin)) = numel(edges) - 1;
share = accumarray(bin(:), density(:), [numel(edges) - 1, 1])' / sum(density);
end


function [grid, cdf, fullGrid, density] = smoothedDistribution(time, window, sigma)
% The times' distribution smoothed with a Gaussian, reflected at both ends of the window, as a
% cumulative distribution on a fine grid with strictly rising values; and the density on the
% whole grid.
step = min(5e-4, sigma / 10);
fullGrid = (window(1):step:max(window(2), window(1) + step))';
density = zeros(size(fullGrid));
mirrors = [time(:); 2 * window(1) - time(:); 2 * window(2) - time(:)];
for chunk = 1:500:numel(mirrors)
    part = mirrors(chunk:min(end, chunk + 499))';
    density = density + sum(exp(-(fullGrid - part) .^ 2 / (2 * sigma ^ 2)), 2);
end
density = density + eps;
cdf = cumsum(density) / sum(density);
[cdf, keep] = unique(cdf);
grid = fullGrid(keep);
end
