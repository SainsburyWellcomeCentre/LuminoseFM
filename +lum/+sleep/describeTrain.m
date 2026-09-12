function text = describeTrain(train)
% lum.sleep.describeTrain says in one line what a plasticity train delivers.
%
%   Theta burst: 5 trains of 10 bursts of 4 pulses (5 ms) at 100 Hz, bursts at 4 Hz, trains every 20 s
%
% Arguments:
%   train  One element of S.Sleep.TestPulses.Trains
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.describeTestPulses, lum.gui.TestPulseDesigner

pulses = sprintf('%d pulse(s) (%g ms) at %g Hz', train.PulsesPerBurst, 1000 * train.PulseWidth, ...
                 train.PulseFrequency);
if train.BurstsPerTrain > 1
    burst = sprintf('%d bursts of %s, bursts at %g Hz', train.BurstsPerTrain, pulses, ...
                    train.BurstFrequency);
else
    burst = pulses;
end
text = sprintf('%s: %d train(s) of %s, trains every %g s', char(train.Name), train.nTrains, ...
               burst, train.TrainInterval);
