function plan = testPulsePlan(testPulses)
% lum.sleep.testPulsePlan compiles a sleep session's test-pulse schedule into light.
%
% Test pulses (D13) are light on channels A and B during a sleep recording, delivered
% the way a behaviour stimulus is (D1): Bpod gates BNC1/BNC2, and PulsePal fills each
% gate with a carrier. A probe step gates constant light, so each gate is one probe
% pulse; a plasticity-train step gates each burst, and PulsePal fills the burst with
% the train's pulses. This function turns S.Sleep.TestPulses into every gate the
% session will send, in session time, before the session starts — so the setup dialog
% refuses what cannot run, the plots can draw the whole schedule, and the session only
% has to cut the list into state machines (lum.sleep.nextBlock).
%
% Words:
%   epoch     One probe — a single pulse, or a pair InterPulseInterval apart — or, in a
%             train step, one train. Epochs never share a state machine run with a
%             boundary inside them.
%   segment   One gate on one channel: [onset duration] on A or B. In a train step a
%             segment is a burst; PulsePal puts PulsesPerBurst pulses in it.
%
% Timing. All times are integer cycles of the state machine's 100 us clock, so what is
% planned is what is sent. A probe step of M minutes holds floor(60 M / interval)
% epochs, each followed by a full inter-epoch interval inside its step; a train step
% lasts nTrains x TrainInterval. A burst's gate runs from its first pulse to half way
% through the gap after its last, so PulsePal completes the last pulse and cannot start
% another.
%
% Arguments:
%   testPulses  S.Sleep.TestPulses (see lum.defaultSettings)
%
% Returns plan, empty (no steps, Duration 0) when testPulses.Enabled is false:
%   .Steps            1 x nSteps struct: Kind, Channels, Start and Duration (s),
%                     nEpochs, EpochLength and EpochInterval (s), FirstEpoch (row of
%                     .Epochs, 0 for none), Carrier (1 x 2, for lum.dev.PulsePal;
%                     [] for rest), Train (the train's definition; [] otherwise)
%   .Duration         Seconds from the first step's start to the last step's end
%   .DurationCycles   The same in cycles
%   .Segments         nSegments x 5, sorted by onset: [onset duration channel step
%                     epoch]; onset and duration in cycles, channel 1 = A, 2 = B, epoch
%                     numbered within its step
%   .Epochs           nEpochs x 5, sorted: [start end firstSegment lastSegment step],
%                     start and end in cycles
%   .NextStepEpoch    For each epoch, the row of the next epoch of a different step
%                     (nEpochs + 1 when none): where the carrier may change
%   .MostSegmentsPerEpoch, .MostPulsesPerEpoch, .LongestEpoch (s)
%   .ShortestDark     Seconds of darkness after the most crowded epoch (Inf for none)
%   .CyclePeriod      1e-4
%
% Errors with 'lum:sleep:testPulsePlan:<reason>' and a message naming the step or train.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.nextBlock, lum.sleep.validate, lum.sleep.epochShape,
%           lum.gui.TestPulseDesigner, docs/architecture.md (D13)

cycle = 1e-4;
plan = emptyPlan(cycle);
if ~testPulses.Enabled
    return
end

voltage = checkVoltage(testPulses.Voltage);
probe = checkProbe(testPulses.Probe, voltage, cycle);
% Train definitions are only checked when trains may be used, so an unfinished one does
% not stop a session of probes.
if testPulses.PlasticityTrains
    trains = checkTrains(testPulses.Trains, voltage, cycle);
end
schedule = testPulses.Schedule;
if isempty(schedule)
    fail('emptySchedule', 'The test-pulse schedule has no steps. Add a probe step at least.');
end

choices = lum.sleep.stepChoices(testPulses);
nSteps = numel(schedule);
steps = repmat(struct('Kind', '', 'Channels', '', 'Start', 0, 'Duration', 0, 'nEpochs', 0, ...
                      'EpochLength', 0, 'EpochInterval', 0, 'FirstEpoch', 0, ...
                      'Carrier', [], 'Train', []), 1, nSteps);
segmentParts = cell(1, nSteps);
epochParts = cell(1, nSteps);
startCycles = 0;
nSegments = 0;
nEpochsSoFar = 0;
maxSegments = 5e5;
lit = false;
darkness = Inf;
for s = 1:nSteps
    kind = schedule(s).Kind;
    channels = schedule(s).Channels;
    if ~(ischar(kind) || isstring(kind)) || ~ismember(char(kind), choices.Kinds)
        fail('unknownKind', 'Step %d is "%s", which is neither Probe, Rest nor a defined train.', ...
             s, char(string(kind)));
    end
    kind = char(kind);
    if ~(ischar(channels) || isstring(channels)) || ~ismember(char(channels), choices.Channels)
        fail('badChannels', 'Step %d (%s): channels must be one of %s.', s, kind, ...
             strjoin(choices.Channels, ', '));
    end
    channels = char(channels);

    steps(s).Kind = kind;
    steps(s).Channels = channels;
    steps(s).Start = startCycles * cycle;
    switch kind
        case 'Rest'
            durationCycles = minutesToCycles(schedule(s).Minutes, s, kind, cycle);
            nEpochs = 0;
        case 'Probe'
            durationCycles = minutesToCycles(schedule(s).Minutes, s, kind, cycle);
            nEpochs = floor(durationCycles / probe.IntervalCycles);
            if nEpochs < 1
                fail('stepTooShort', ['Step %d (Probe) lasts %g min, shorter than one inter-epoch '...
                     'interval of %g s.'], s, schedule(s).Minutes, probe.IntervalCycles * cycle);
            end
            shape = probe.Shape;
            intervalCycles = probe.IntervalCycles;
            steps(s).Carrier = probe.Carrier;
        otherwise
            if ~testPulses.PlasticityTrains
                fail('trainsOff', ['Step %d delivers the train "%s", but plasticity trains are '...
                     'switched off. Switch them on, or remove the step.'], s, kind);
            end
            train = trains(strcmp(kind, {trains.Name}));
            train = train(1);
            nEpochs = train.Definition.nTrains;
            intervalCycles = train.IntervalCycles;
            durationCycles = nEpochs * intervalCycles;
            shape = train.Shape;
            steps(s).Carrier = train.Carrier;
            steps(s).Train = train.Definition;
    end
    steps(s).Duration = durationCycles * cycle;
    steps(s).nEpochs = nEpochs;

    if nEpochs > 0
        perEpoch = size(shape, 1) * (1 + strcmp(channels, 'A and B'));
        nSegments = nSegments + nEpochs * perEpoch;
        if nSegments > maxSegments
            fail('tooManySegments', ['The schedule sends more than %d gates of light, more than '...
                 'one session file holds comfortably. Lengthen the intervals or shorten the steps.'], ...
                 maxSegments);
        end
        [segmentParts{s}, epochParts{s}] = layOut(shape, channels, startCycles, intervalCycles, ...
                                                  nEpochs, s, nSegments - nEpochs * perEpoch);
        epochLength = max(shape(:, 1) + shape(:, 2));
        steps(s).EpochLength = epochLength * cycle;
        steps(s).EpochInterval = intervalCycles * cycle;
        steps(s).FirstEpoch = nEpochsSoFar + 1;
        nEpochsSoFar = nEpochsSoFar + nEpochs;
        darkness = min(darkness, (intervalCycles - epochLength) * cycle);
        lit = true;
    end
    startCycles = startCycles + durationCycles;
end

if startCycles * cycle > 24 * 3600
    fail('tooLong', 'The schedule lasts %.0f min; a session lasts at most 1440 min.', ...
         startCycles * cycle / 60);
end
if ~lit
    fail('noLight', 'No step of the schedule delivers light. Add a probe or a train step.');
end

plan.Steps = steps;
plan.DurationCycles = startCycles;
plan.Duration = startCycles * cycle;
plan.Segments = vertcat(segmentParts{:});
plan.Epochs = vertcat(epochParts{:});
plan.NextStepEpoch = nextStepEpoch(plan.Epochs(:, 5));
plan.MostSegmentsPerEpoch = max(plan.Epochs(:, 4) - plan.Epochs(:, 3) + 1);
plan.LongestEpoch = max(plan.Epochs(:, 2) - plan.Epochs(:, 1)) * cycle;
plan.ShortestDark = darkness;
pulsesPerEpoch = 0;
for s = find([steps.nEpochs] > 0)
    rows = plan.Epochs(steps(s).FirstEpoch, 4) - plan.Epochs(steps(s).FirstEpoch, 3) + 1;
    if ~isempty(steps(s).Train)
        rows = rows * steps(s).Train.PulsesPerBurst;
    end
    pulsesPerEpoch = max(pulsesPerEpoch, rows);
end
plan.MostPulsesPerEpoch = pulsesPerEpoch;


function plan = emptyPlan(cycle)
% A plan with no light, for a session without test pulses.
plan = struct('Steps', struct('Kind', {}, 'Channels', {}, 'Start', {}, 'Duration', {}, ...
                              'nEpochs', {}, 'EpochLength', {}, 'EpochInterval', {}, ...
                              'FirstEpoch', {}, 'Carrier', {}, 'Train', {}), ...
              'Duration', 0, 'DurationCycles', 0, 'Segments', zeros(0, 5), ...
              'Epochs', zeros(0, 5), 'NextStepEpoch', zeros(0, 1), ...
              'MostSegmentsPerEpoch', 0, 'MostPulsesPerEpoch', 0, 'LongestEpoch', 0, ...
              'ShortestDark', Inf, 'CyclePeriod', cycle);


function voltage = checkVoltage(voltage)
% The LED drive of channels A and B.
if ~isnumeric(voltage) || numel(voltage) ~= 2 || any(~isfinite(voltage)) ...
        || any(abs(voltage) > lum.dev.PulsePal.MaxVoltage)
    fail('badVoltage', 'The LED drive must be two values, for A and B, within +/-%g V.', ...
         lum.dev.PulsePal.MaxVoltage);
end
voltage = double(reshape(voltage, 1, 2));


function probe = checkProbe(settings, voltage, cycle)
% One probe epoch: its pulses as [onset width] rows in cycles, and its carrier.
choices = lum.sleep.stepChoices();
if ~(ischar(settings.Mode) || isstring(settings.Mode)) || ~ismember(char(settings.Mode), choices.ProbeModes)
    fail('badProbeMode', 'The probe must be Paired or Single.');
end
widthCycles = round(settings.PulseWidth / cycle);
if ~isscalar(settings.PulseWidth) || widthCycles < 1 || settings.PulseWidth > 10
    fail('badProbeWidth', 'The probe pulse must last between 0.1 ms and 10 s.');
end
probe.Shape = [0 widthCycles];
if strcmp(char(settings.Mode), 'Paired')
    pairCycles = round(settings.InterPulseInterval / cycle);
    if ~isscalar(settings.InterPulseInterval) || pairCycles - widthCycles < 10
        fail('pairOverlaps', ['The second probe pulse starts %g s after the first, which leaves '...
             'less than 1 ms after a %g s pulse. Lengthen the inter-pulse interval (onset to '...
             'onset) or shorten the pulse.'], settings.InterPulseInterval, settings.PulseWidth);
    end
    probe.Shape = [0 widthCycles; pairCycles widthCycles];
end
epochCycles = max(sum(probe.Shape, 2));
probe.IntervalCycles = round(settings.InterEpochInterval / cycle);
if ~isscalar(settings.InterEpochInterval) || probe.IntervalCycles - epochCycles < 10
    fail('badEpochInterval', ['Probe epochs every %g s cannot hold an epoch %g s long with 1 ms '...
         'to spare. Lengthen the inter-epoch interval.'], settings.InterEpochInterval, ...
         epochCycles * cycle);
end
% Constant light while gated: the gate is the pulse.
probe.Carrier = carrierFor('Probe', 0, 0, voltage, widthCycles * cycle);


function trains = checkTrains(definitions, voltage, cycle)
% Each train's bursts as [onset gate] rows in cycles, its interval and its carrier.
trains = struct('Name', {}, 'Definition', {}, 'Shape', {}, 'IntervalCycles', {}, 'Carrier', {});
names = {};
for k = 1:numel(definitions)
    d = definitions(k);
    name = d.Name;
    if ~(ischar(name) || isstring(name)) || strlength(strtrim(string(name))) == 0
        fail('badTrainName', 'Train %d has no name.', k);
    end
    name = char(name);
    if ismember(name, {'Probe', 'Rest'}) || ismember(name, names)
        fail('badTrainName', 'The train name "%s" is taken; every train needs a name of its own.', name);
    end
    names{end+1} = name; %#ok<AGROW>

    counts = [d.PulsesPerBurst, d.BurstsPerTrain, d.nTrains];
    if numel(counts) ~= 3 || any(counts < 1) || any(counts ~= round(counts))
        fail('badTrainCount', '%s: pulses per burst, bursts per train and trains must be whole numbers of 1 or more.', name);
    end
    if ~(isscalar(d.PulseFrequency) && d.PulseFrequency > 0 && isfinite(d.PulseFrequency))
        fail('badTrainPulse', '%s: the pulse frequency must be above 0 Hz.', name);
    end
    periodCycles = round(1 / d.PulseFrequency / cycle);
    widthCycles = round(d.PulseWidth / cycle);
    if ~isscalar(d.PulseWidth) || widthCycles < 1 || periodCycles - widthCycles < 1
        fail('badTrainPulse', ['%s: a %g s pulse at %g Hz leaves no gap between pulses. Shorten '...
             'the pulse below %g s.'], name, d.PulseWidth, d.PulseFrequency, periodCycles * cycle);
    end
    % From the first pulse's onset to half way through the gap after the last pulse.
    gateCycles = (d.PulsesPerBurst - 1) * periodCycles + widthCycles ...
                 + floor((periodCycles - widthCycles) / 2);
    burstCycles = 0;
    if d.BurstsPerTrain > 1
        if ~(isscalar(d.BurstFrequency) && d.BurstFrequency > 0 && isfinite(d.BurstFrequency))
            fail('badBurstFrequency', '%s: the burst frequency must be above 0 Hz.', name);
        end
        burstCycles = round(1 / d.BurstFrequency / cycle);
        if burstCycles - gateCycles < 10
            fail('burstsOverlap', ['%s: a burst of %d pulses at %g Hz lasts %g s, too long to '...
                 'repeat %g times a second with 1 ms between bursts.'], name, d.PulsesPerBurst, ...
                 d.PulseFrequency, gateCycles * cycle, d.BurstFrequency);
        end
    end
    lengthCycles = (d.BurstsPerTrain - 1) * burstCycles + gateCycles;
    intervalCycles = round(d.TrainInterval / cycle);
    if ~isscalar(d.TrainInterval) || intervalCycles - lengthCycles < 10
        fail('trainTooLong', ['%s: a train lasts %g s, which does not fit in a train interval of '...
             '%g s with 1 ms to spare.'], name, lengthCycles * cycle, d.TrainInterval);
    end
    trains(end+1).Name = name; %#ok<AGROW>
    trains(end).Definition = d;
    trains(end).Definition.Name = name;
    trains(end).Shape = [(0:d.BurstsPerTrain - 1)' * burstCycles, repmat(gateCycles, d.BurstsPerTrain, 1)];
    trains(end).IntervalCycles = intervalCycles;
    trains(end).Carrier = carrierFor(name, d.PulseFrequency, widthCycles * cycle, voltage, ...
                                     gateCycles * cycle);
end


function carrier = carrierFor(label, frequency, pulseWidth, voltage, longestGate)
% A carrier for both PulsePal outputs, checked the way the device will be programmed.
carrier = struct('Channel', {1, 2}, 'Frequency', frequency, 'PulseWidth', pulseWidth, ...
                 'Voltage', {voltage(1), voltage(2)}, ...
                 'MaxDuration', longestGate + lum.stim.OptoPattern.TrainMargin);
try
    carrier = lum.dev.PulsePal.validateCarrier(carrier);
catch carrierError
    fail('badCarrier', '%s: %s', label, carrierError.message);
end


function cycles = minutesToCycles(minutes, step, kind, cycle)
% A probe or rest step's length.
if ~(isnumeric(minutes) && isscalar(minutes) && isfinite(minutes) && minutes > 0)
    fail('badMinutes', 'Step %d (%s) must last more than 0 minutes.', step, kind);
end
cycles = round(60 * minutes / cycle);


function [segments, epochs] = layOut(shape, channels, startCycles, intervalCycles, nEpochs, step, before)
% Every segment and epoch of one step. shape holds one epoch's [onset duration] rows.
nShape = size(shape, 1);
switch channels
    case 'A and B'
        pattern = sortrows([repmat(shape, 2, 1), kron([1; 2], ones(nShape, 1))], [1 3]);
    case 'B'
        pattern = [shape, 2 * ones(nShape, 1)];
    otherwise   % 'A', and 'Alternate A and B', whose channel is set per epoch below
        pattern = [shape, ones(nShape, 1)];
end
perEpoch = size(pattern, 1);
epochOf = kron((1:nEpochs)', ones(perEpoch, 1));
epochStart = startCycles + ((1:nEpochs)' - 1) * intervalCycles;
segments = [epochStart(epochOf) + repmat(pattern(:, 1), nEpochs, 1), ...
            repmat(pattern(:, 2), nEpochs, 1), repmat(pattern(:, 3), nEpochs, 1), ...
            repmat(step, nEpochs * perEpoch, 1), epochOf];
if strcmp(channels, 'Alternate A and B')
    segments(:, 3) = 2 - mod(epochOf, 2);   % A on odd epochs, B on even
end
first = before + ((1:nEpochs)' - 1) * perEpoch + 1;
epochs = [epochStart, epochStart + max(pattern(:, 1) + pattern(:, 2)), first, ...
          first + perEpoch - 1, repmat(step, nEpochs, 1)];


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
% Raise a schedule error with a lum:sleep:testPulsePlan identifier.
error(['lum:sleep:testPulsePlan:' id], varargin{:});
