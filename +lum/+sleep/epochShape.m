function shape = epochShape(plan, step, epoch)
% lum.sleep.epochShape is the light of one epoch of a test-pulse schedule, from its onset.
%
% Bpod sends gates; PulsePal turns them into light (D13). For a probe step the gate is
% the pulse; for a train step each gate is a burst and holds PulsesPerBurst pulses at
% the train's pulse frequency. This returns both, so the designer, the sleep setup
% dialog and the sleep plots draw an epoch the same way, and analysis can recover the
% pulses a session file's LightSegments stand for.
%
% Arguments:
%   plan   From lum.sleep.testPulsePlan
%   step   Index into plan.Steps; the step must deliver light
%   epoch  Epoch number within the step (default 1)
%
% Returns:
%   .Gates   n x 3 [onset duration channel], seconds from the epoch's onset
%   .Pulses  m x 3 [onset duration channel]: the light PulsePal delivers
%   .Length  Seconds from the first gate's onset to the last gate's end
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.testPulsePlan, lum.sleep.Plots, lum.gui.TestPulseDesigner

if nargin < 3
    epoch = 1;
end
info = plan.Steps(step);
if info.nEpochs < 1 || epoch < 1 || epoch > info.nEpochs
    error('lum:sleep:epochShape:noEpoch', 'Step %d has no epoch %d.', step, epoch);
end
row = info.FirstEpoch + epoch - 1;
segments = plan.Segments(plan.Epochs(row, 3):plan.Epochs(row, 4), :);
cycle = plan.CyclePeriod;
shape.Gates = [(segments(:, 1) - plan.Epochs(row, 1)) * cycle, segments(:, 2) * cycle, segments(:, 3)];
shape.Length = (plan.Epochs(row, 2) - plan.Epochs(row, 1)) * cycle;

if isempty(info.Train)
    shape.Pulses = shape.Gates;
    return
end
train = info.Train;
period = lum.dev.PulsePal.quantise(1 / train.PulseFrequency);   % As PulsePal is programmed
offsets = (0:train.PulsesPerBurst - 1)' * period;
nGates = size(shape.Gates, 1);
gateOf = kron((1:nGates)', ones(train.PulsesPerBurst, 1));
shape.Pulses = [shape.Gates(gateOf, 1) + repmat(offsets, nGates, 1), ...
                repmat(info.Carrier(1).PulseWidth, numel(gateOf), 1), shape.Gates(gateOf, 3)];
