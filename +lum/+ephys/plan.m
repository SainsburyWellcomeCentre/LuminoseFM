function [plan, notes] = plan(S, cals)
% lum.ephys.plan compiles an ePhys calibration session into steps of light (D18).
%
% An ePhys calibration session sends light pulses whose intensity or pairing changes step
% by step, for the response recorded on the Neuropixels probe:
%
%   Input-output        one step per intensity, nLevels of them from the lowest to the
%                       highest; single pulses of PulseWidth
%   Paired-pulse ratio  one step per inter-pulse interval (onset to onset, within a
%                       pair) in PairedPulse.Intervals; pairs of PulseWidth pulses at
%                       one intensity
%
% Each step sends Repeats epochs, one every InterEpochInterval seconds, on Channels (A,
% B, or A and B together, each at its own current). Input-output steps come first, then
% paired-pulse steps; within each, Order is 'Ascending', 'Descending' or 'Shuffled'
% (drawn from Seed, with a random stream of its own).
%
% Each channel's intensities are in mW/mm2 where its light path is calibrated, in mA where
% it is not. Calibrated: the input-output curve runs from InputOutput.MinIrradiancemWmm2 to
% MaxIrradiancemWmm2, levels spaced evenly in irradiance, and the pairs are at
% PairedPulse.IrradiancemWmm2; each is turned into whole mA by lum.led.currentFor, so an
% irradiance above what the channel gives within its limit runs at the most it gives, and
% says so in notes. Not calibrated: from InputOutput.MinmA to MaxmA (NaN: the channel's
% limit), spaced evenly in mA, and pairs at PairedPulse.CurrentmA.
%
% Light goes out as in a sleep session with test pulses (D13): Bpod gates BNC1/BNC2 and
% PulsePal, gated, fills each gate with constant light, so the gate is the pulse. Each
% step is compiled by lum.sleep.testPulsePlan as a probe step, and the steps are joined
% into one plan of the same shape, so lum.sleep.nextBlock cuts the session into state
% machines with a cut before every step: the LED current changes there, between blocks.
%
% Arguments:
%   S     Settings struct; reads S.Ephys, S.Doric.MaxCurrentmA and S.Light
%   cals  Optional 1 x 2 cell of calibrations (lum.led.calibrations); default none, so
%         every intensity is in mA
%
% Returns plan, as lum.sleep.testPulsePlan returns it, whose Steps also have:
%   .Protocol            'Input-output' or 'Paired-pulse ratio'
%   .Label               A few words for the plots, e.g. 'IO 3/8' or 'PPR 50 ms'
%   .CurrentmA           1 x 2, the LED current on A and B during the step (NaN unused)
%   .IrradiancemWmm2     1 x 2, the same as irradiance (NaN without a calibration)
%   .InterPulseInterval  Seconds within a pair; NaN for single pulses
% and notes, a cell of sentences: an irradiance out of a channel's reach, or a channel
% without a calibration, in mA.
%
% Errors with 'lum:ephys:plan:<reason>', or a 'lum:sleep:testPulsePlan:<reason>' for a step
% that cannot be sent.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.ephys.validate, lum.sleep.testPulsePlan, lum.sleep.nextBlock, lum.sleep.run

if nargin < 2 || isempty(cals)
    cals = {[], []};
end
e = S.Ephys;
used = channelsUsed(e.Channels);
checkCommon(e);
notes = {};
labels = 'AB';
for k = used
    if isempty(cals{k})
        path = lum.led.lightPath(S, k);
        notes{end+1} = sprintf(['Channel %s: the %s cable is not calibrated on channel %s, so its '...
                                'intensities are in mA.'], labels(k), path.Cable, labels(k)); %#ok<AGROW>
    end
end

definitions = struct('Protocol', {}, 'Label', {}, 'CurrentmA', {}, 'Mode', {}, 'Interval', {});
if e.InputOutput.Enabled
    [steps, stepNotes] = inputOutputSteps(e, used, cals, S.Doric.MaxCurrentmA);
    definitions = [definitions, steps];
    notes = [notes stepNotes];
end
if e.PairedPulse.Enabled
    [steps, stepNotes] = pairedPulseSteps(e, used, cals, S.Doric.MaxCurrentmA);
    definitions = [definitions, steps];
    notes = [notes stepNotes];
end
if isempty(definitions)
    fail('noProtocol', 'Choose input-output, paired-pulse ratio, or both.');
end

cycle = 1e-4;
trains = struct('Name', {}, 'PulseFrequency', {}, 'PulseWidth', {}, 'PulsesPerBurst', {}, ...
                'BurstFrequency', {}, 'BurstsPerTrain', {}, 'nTrains', {}, 'TrainInterval', {});
nSteps = numel(definitions);
parts = cell(1, nSteps);
startCycles = 0;
for s = 1:nSteps
    d = definitions(s);
    interval = d.Interval;
    if isnan(interval)
        interval = 2 * e.PulseWidth;   % Unused by a single pulse, but checked
    end
    testPulses = struct('Enabled', true, 'Voltage', e.Voltage, 'PlasticityTrains', false, ...
                        'Trains', trains, ...
                        'Probe', struct('Mode', d.Mode, 'PulseWidth', e.PulseWidth, ...
                                        'InterPulseInterval', interval, ...
                                        'InterEpochInterval', e.InterEpochInterval), ...
                        'Schedule', struct('Kind', 'Probe', 'Channels', e.Channels, ...
                                           'Minutes', e.Repeats * e.InterEpochInterval / 60));
    part = lum.sleep.testPulsePlan(testPulses);
    part.Steps.Protocol = d.Protocol;
    part.Steps.Label = d.Label;
    part.Steps.CurrentmA = d.CurrentmA;
    part.Steps.IrradiancemWmm2 = [lum.led.irradiance(cals{1}, d.CurrentmA(1)), ...
                                  lum.led.irradiance(cals{2}, d.CurrentmA(2))];
    part.Steps.InterPulseInterval = d.Interval;
    part.Offset = startCycles;
    parts{s} = part;
    startCycles = startCycles + part.DurationCycles;
end
plan = join(parts, cycle);
plan.Seed = e.Seed;


function used = channelsUsed(channels)
switch char(channels)
    case 'A'
        used = 1;
    case 'B'
        used = 2;
    case 'A and B'
        used = [1 2];
    otherwise
        fail('badChannels', 'The channels must be A, B, or A and B.');
end


function checkCommon(e)
if ~(isscalar(e.Repeats) && e.Repeats >= 1 && e.Repeats == round(e.Repeats) && e.Repeats <= 10000)
    fail('badRepeats', 'Each step needs a whole number of repeats, from 1 to 10000.');
end
if ~(isscalar(e.InterEpochInterval) && e.InterEpochInterval > 0 && e.InterEpochInterval <= 3600)
    fail('badInterval', 'The interval between epochs must be above 0 and at most 3600 s.');
end
if abs(e.InterEpochInterval / 1e-4 - round(e.InterEpochInterval / 1e-4)) > 1e-6
    fail('badInterval', 'The interval between epochs must be a whole number of 0.1 ms.');
end
if ~ismember(char(e.Order), {'Ascending', 'Descending', 'Shuffled'})
    fail('badOrder', 'The order must be Ascending, Descending or Shuffled.');
end


function [steps, notes] = inputOutputSteps(e, used, cals, limits)
io = e.InputOutput;
n = io.nLevels;
if ~(isscalar(n) && n >= 2 && n == round(n) && n <= 100)
    fail('badLevels', 'An input-output curve needs a whole number of levels, from 2 to 100.');
end
labels = 'AB';
levels = NaN(2, n);
notes = {};
for k = used
    if isempty(cals{k})
        low = io.MinmA(k);
        high = io.MaxmA(k);
        if isnan(high)
            high = limits(k);   % The most the channel may run at
        end
        if ~(low >= 0 && high > low)
            fail('badRange', ['Channel %s: the input-output curve must rise from its lowest intensity '...
                 '(%g mA) to a higher one (%g mA).'], labels(k), low, high);
        end
        if high > limits(k)
            fail('overLimit', ['Channel %s: the input-output curve reaches %g mA, above the channel''s '...
                 'limit of %g mA on the Doric LED tab.'], labels(k), high, limits(k));
        end
        levels(k, :) = round(linspace(low, high, n));
    else
        low = io.MinIrradiancemWmm2(k);
        high = io.MaxIrradiancemWmm2(k);
        if ~(low >= 0 && (isnan(high) || high > low))
            fail('badRange', ['Channel %s: the input-output curve must rise from its lowest intensity '...
                 '(%g mW/mm2) to a higher one (%g mW/mm2).'], labels(k), low, high);
        end
        [~, lowReached, lowNote] = lum.led.currentFor(cals{k}, low, limits(k));
        [~, highReached, highNote] = lum.led.currentFor(cals{k}, high, limits(k));
        if isnan(highReached) || ~(highReached > lowReached)
            fail('outOfReach', ['Channel %s: the %s cable gives no more than %.3g mW/mm2 on this channel '...
                 'within its limit, so the input-output curve cannot rise. Raise the limit or '...
                 'calibrate again.'], labels(k), cals{k}.Cable, lowReached);
        end
        notes = [notes prefixed('Input-output curve', {lowNote, highNote})]; %#ok<AGROW>
        levels(k, :) = min(lum.led.current(cals{k}, linspace(lowReached, highReached, n)), limits(k));
    end
end
order = ordered(1:n, e.Order, e.Seed);
steps = struct('Protocol', {}, 'Label', {}, 'CurrentmA', {}, 'Mode', {}, 'Interval', {});
for j = 1:n
    level = order(j);
    steps(end+1) = struct('Protocol', 'Input-output', 'Label', sprintf('IO %d/%d', level, n), ...
                          'CurrentmA', levels(:, level)', 'Mode', 'Single', 'Interval', NaN); %#ok<AGROW>
end


function [steps, notes] = pairedPulseSteps(e, used, cals, limits)
pp = e.PairedPulse;
intervals = double(pp.Intervals(:)');
if isempty(intervals) || any(~isfinite(intervals)) || any(intervals <= 0)
    fail('badIntervals', 'Give at least one inter-pulse interval, above 0 s.');
end
labels = 'AB';
current = NaN(1, 2);
notes = {};
for k = used
    if isempty(cals{k})
        value = pp.CurrentmA(k);
        if ~(isfinite(value) && value >= 0 && value == round(value))
            fail('badCurrent', 'Channel %s: the paired-pulse current must be a whole number of mA.', labels(k));
        end
        if value > limits(k)
            fail('overLimit', 'Channel %s: the paired pulses at %g mA are above the channel''s limit of %g mA.', ...
                 labels(k), value, limits(k));
        end
    else
        asked = pp.IrradiancemWmm2(k);
        if ~(isfinite(asked) && asked >= 0)
            fail('badIrradiance', 'Channel %s: the paired pulses'' irradiance must be 0 mW/mm2 or more.', ...
                 labels(k));
        end
        [value, ~, note] = lum.led.currentFor(cals{k}, asked, limits(k));
        notes = [notes prefixed('Paired pulses', {note})]; %#ok<AGROW>
    end
    current(k) = value;
end
order = ordered(1:numel(intervals), e.Order, e.Seed + 1);
steps = struct('Protocol', {}, 'Label', {}, 'CurrentmA', {}, 'Mode', {}, 'Interval', {});
for j = order
    steps(end+1) = struct('Protocol', 'Paired-pulse ratio', ...
                          'Label', sprintf('PPR %g ms', 1000 * intervals(j)), 'CurrentmA', current, ...
                          'Mode', 'Paired', 'Interval', intervals(j)); %#ok<AGROW>
end


function notes = prefixed(what, notes)
% Notes that say something, each saying what it is about.
notes = notes(~cellfun(@isempty, notes));
notes = cellfun(@(note) sprintf('%s: %s', what, note), notes, 'UniformOutput', false);


function order = ordered(indices, how, seed)
switch char(how)
    case 'Descending'
        order = fliplr(indices);
    case 'Shuffled'
        stream = RandStream('mt19937ar', 'Seed', seed);
        order = indices(randperm(stream, numel(indices)));
    otherwise
        order = indices;
end


function plan = join(parts, cycle)
% One plan from steps compiled one at a time: times offset, rows renumbered.
nSteps = numel(parts);
steps = cell(1, nSteps);
segments = cell(1, nSteps);
epochs = cell(1, nSteps);
nSegments = 0;
nEpochs = 0;
darkness = Inf;
mostPulses = 0;
for s = 1:nSteps
    part = parts{s};
    offset = part.Offset;
    step = part.Steps(1);
    step.Start = offset * cycle;
    step.FirstEpoch = nEpochs + 1;
    steps{s} = step;
    rows = part.Segments;
    rows(:, 1) = rows(:, 1) + offset;
    rows(:, 4) = s;
    segments{s} = rows;
    rows = part.Epochs;
    rows(:, 1:2) = rows(:, 1:2) + offset;
    rows(:, 3:4) = rows(:, 3:4) + nSegments;
    rows(:, 5) = s;
    epochs{s} = rows;
    nSegments = nSegments + size(part.Segments, 1);
    nEpochs = nEpochs + size(part.Epochs, 1);
    darkness = min(darkness, part.ShortestDark);
    mostPulses = max(mostPulses, part.MostPulsesPerEpoch);
end
if nSegments > 5e5
    fail('tooManySegments', ['The session sends more than 500000 gates of light. Use fewer steps '...
         'or repeats.']);
end
plan = parts{1};
plan = rmfield(plan, 'Offset');
plan.Steps = [steps{:}];
plan.Segments = vertcat(segments{:});
plan.Epochs = vertcat(epochs{:});
plan.DurationCycles = parts{end}.Offset + parts{end}.DurationCycles;
plan.Duration = plan.DurationCycles * cycle;
if plan.Duration > 24 * 3600
    fail('tooLong', 'The session lasts %.0f min; a session lasts at most 1440 min.', plan.Duration / 60);
end
plan.NextStepEpoch = nextStepEpoch(plan.Epochs(:, 5));
plan.MostSegmentsPerEpoch = max(plan.Epochs(:, 4) - plan.Epochs(:, 3) + 1);
plan.LongestEpoch = max(plan.Epochs(:, 2) - plan.Epochs(:, 1)) * cycle;
plan.ShortestDark = darkness;
plan.MostPulsesPerEpoch = mostPulses;


function next = nextStepEpoch(stepOfEpoch)
% For each epoch, the row of the first later epoch of another step.
n = numel(stepOfEpoch);
next = repmat(n + 1, n, 1);
for e = n - 1:-1:1
    if stepOfEpoch(e + 1) ~= stepOfEpoch(e)
        next(e) = e + 1;
    else
        next(e) = next(e + 1);
    end
end


function fail(id, varargin)
error(['lum:ephys:plan:' id], varargin{:});
