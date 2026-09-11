function tests = pulsePalTest
% pulsePalTest exercises the carrier translation: lum.dev.PulsePal.
%
% Run against the null shim, which shares all of its logic with the real one and
% differs only in whether send() reaches a device. Nothing here opens a port.
tests = functiontests(localfunctions);
end

function testAPulseTrainBecomesPulseWidthAndGap(testCase)
pulsePal = lum.dev.NullPulsePal('test');
pulsePal.configure(waveform(20, 0.005));
p = lum.dev.PulsePal.Param;
verifyEqual(testCase, pulsePal.sentValue(1, p.Phase1Duration), 0.005, 'AbsTol', 1e-12);
verifyEqual(testCase, pulsePal.sentValue(1, p.InterPulseInterval), 0.045, 'AbsTol', 1e-12);
end

function testConstantIlluminationIsOnePulseAsLongAsTheTrain(testCase)
pulsePal = lum.dev.NullPulsePal('test');
w = waveform(0, 0);
pulsePal.configure(w);
p = lum.dev.PulsePal.Param;
verifyEqual(testCase, pulsePal.sentValue(1, p.Phase1Duration), w(1).MaxDuration, ...
            'AbsTol', 1e-12);
end

function testBothTriggerChannelsAreGated(testCase)
% The whole D1 split depends on this: the BNC line has to gate the train, not
% just start it. The firmware encodes gated as 2, though
% ProgramPulsePalParam's header comment says 3.
pulsePal = lum.dev.NullPulsePal('test');
pulsePal.configure(waveform(20, 0.005));
p = lum.dev.PulsePal.Param;
verifyEqual(testCase, pulsePal.sentValue(1, p.TriggerMode), 2);
verifyEqual(testCase, pulsePal.sentValue(2, p.TriggerMode), 2);
end

function testEachOutputFollowsExactlyOneTrigger(testCase)
% Linking an output to both gated triggers would make the firmware wait for both
% lines to fall before stopping it, coupling the two patterns together.
pulsePal = lum.dev.NullPulsePal('test');
pulsePal.configure(waveform(20, 0.005));
p = lum.dev.PulsePal.Param;
verifyEqual(testCase, pulsePal.sentValue(1, p.LinkedToTriggerCH1), 1);
verifyEqual(testCase, pulsePal.sentValue(1, p.LinkedToTriggerCH2), 0);
verifyEqual(testCase, pulsePal.sentValue(2, p.LinkedToTriggerCH1), 0);
verifyEqual(testCase, pulsePal.sentValue(2, p.LinkedToTriggerCH2), 1);
end

function testUnusedOutputsAreLeftUnlinked(testCase)
pulsePal = lum.dev.NullPulsePal('test');
pulsePal.configure(waveform(20, 0.005));
p = lum.dev.PulsePal.Param;
for channel = 3:4
    verifyEqual(testCase, pulsePal.sentValue(channel, p.LinkedToTriggerCH1), 0);
    verifyEqual(testCase, pulsePal.sentValue(channel, p.LinkedToTriggerCH2), 0);
end
end

function testPerChannelVoltagesAreHonoured(testCase)
pulsePal = lum.dev.NullPulsePal('test');
w = waveform(20, 0.005);
w(1).Voltage = 3;
w(2).Voltage = 4.5;
pulsePal.configure(w);
p = lum.dev.PulsePal.Param;
verifyEqual(testCase, pulsePal.sentValue(1, p.Phase1Voltage), 3);
verifyEqual(testCase, pulsePal.sentValue(2, p.Phase1Voltage), 4.5);
end

function testEachChannelGetsItsOwnCarrier(testCase)
% The two channels drive different LEDs into different fiber bundles, so the
% whole carrier is per-channel, not just its amplitude.
pulsePal = lum.dev.NullPulsePal('test');
w = waveform(20, 0.005);
w(2).Frequency = 100;
w(2).PulseWidth = 0.002;
pulsePal.configure(w);
p = lum.dev.PulsePal.Param;
verifyEqual(testCase, pulsePal.sentValue(1, p.Phase1Duration), 0.005, 'AbsTol', 1e-12);
verifyEqual(testCase, pulsePal.sentValue(1, p.InterPulseInterval), 0.045, 'AbsTol', 1e-12);
verifyEqual(testCase, pulsePal.sentValue(2, p.Phase1Duration), 0.002, 'AbsTol', 1e-12);
verifyEqual(testCase, pulsePal.sentValue(2, p.InterPulseInterval), 0.008, 'AbsTol', 1e-12);
end

function testOneChannelMayBeConstantWhileTheOtherPulses(testCase)
pulsePal = lum.dev.NullPulsePal('test');
w = waveform(20, 0.005);
w(2).Frequency = 0;
pulsePal.configure(w);
p = lum.dev.PulsePal.Param;
verifyEqual(testCase, pulsePal.sentValue(1, p.Phase1Duration), 0.005, 'AbsTol', 1e-12);
verifyEqual(testCase, pulsePal.sentValue(2, p.Phase1Duration), w(2).MaxDuration, ...
            'AbsTol', 1e-12);
end

function testAMislabelledChannelIsRejected(testCase)
% Elements out of channel order would drive output 1 with channel 2's carrier,
% which on the rig is silent: the light is wrong, not absent.
pulsePal = lum.dev.NullPulsePal('test');
w = waveform(20, 0.005);
w(1).Channel = 2;
w(2).Channel = 1;
verifyError(testCase, @() pulsePal.configure(w), 'lum:dev:PulsePal:badCarrier');
end

function testAWaveformWithMoreChannelsThanTriggersIsRejected(testCase)
pulsePal = lum.dev.NullPulsePal('test');
w = waveform(20, 0.005);
w(3) = w(2);
w(3).Channel = 3;
verifyError(testCase, @() pulsePal.configure(w), 'lum:dev:PulsePal:badCarrier');
end

function testTheErrorNamesTheOffendingChannel(testCase)
pulsePal = lum.dev.NullPulsePal('test');
w = waveform(20, 0.005);
w(2).Voltage = 12;
try
    pulsePal.configure(w);
    verifyFail(testCase, 'An out-of-range voltage must be rejected');
catch rejection
    verifyEqual(testCase, rejection.identifier, 'lum:dev:PulsePal:badCarrier');
    verifySubstring(testCase, rejection.message, 'Channel B');
end
end

function testUnchangedParametersAreNotResent(testCase)
pulsePal = lum.dev.NullPulsePal('test');
w = waveform(20, 0.005);
pulsePal.configure(w);
nAfterFirst = numel(pulsePal.log());

pulsePal.configure(w);
verifyEqual(testCase, numel(pulsePal.log()), nAfterFirst, ...
            'Reprogramming an unchanged waveform must send nothing');
verifyFalse(testCase, pulsePal.needsReprogramming(w));

w(2).Frequency = 40;
verifyTrue(testCase, pulsePal.needsReprogramming(w), ...
           'A change on one channel alone must still reprogram the device');
pulsePal.configure(w);
verifyGreaterThan(testCase, numel(pulsePal.log()), nAfterFirst);
end

function testTimesAreQuantisedToThePulsePalCycle(testCase)
% ProgramPulsePalParam errors outright on a time that is not a multiple of 100 us.
pulsePal = lum.dev.NullPulsePal('test');
pulsePal.configure(waveform(30, 0.00333));  % 1/30 s is not a round number
p = lum.dev.PulsePal.Param;
for code = [p.Phase1Duration, p.InterPulseInterval, p.PulseTrainDuration]
    value = pulsePal.sentValue(1, code);
    verifyEqual(testCase, rem(round(value * 1e6), 100), 0, ...
                sprintf('Parameter %d is not a multiple of 100 us', code));
end
end

function testAPulseWiderThanThePeriodIsRejected(testCase)
pulsePal = lum.dev.NullPulsePal('test');
verifyError(testCase, @() pulsePal.configure(waveform(20, 0.06)), ...
            'lum:dev:PulsePal:badCarrier');
end

function testAnOutOfRangeVoltageIsRejected(testCase)
pulsePal = lum.dev.NullPulsePal('test');
w = waveform(20, 0.005);
w(1).Voltage = 12;
verifyError(testCase, @() pulsePal.configure(w), 'lum:dev:PulsePal:badCarrier');
end

function testAnIncompleteWaveformIsRejected(testCase)
pulsePal = lum.dev.NullPulsePal('test');
verifyError(testCase, @() pulsePal.configure(struct('Frequency', 20)), ...
            'lum:dev:PulsePal:badCarrier');
end

function testTheSettingsCarrierIsWhatTheDeviceAccepts(testCase)
% The carrier the setup dialog writes has to be the carrier the device takes.
% Nothing else checks that the two shapes still agree.
S = lum.defaultSettings;
w = S.Light.Carrier;
[w.MaxDuration] = deal(S.Stimulus.Duration + lum.stim.OptoPattern.TrainMargin);
pulsePal = lum.dev.NullPulsePal('test');
pulsePal.configure(w);
p = lum.dev.PulsePal.Param;
verifyEqual(testCase, pulsePal.sentValue(1, p.Phase1Voltage), S.Light.Carrier(1).Voltage);
end

function testTheNullShimReportsItselfUnavailable(testCase)
pulsePal = lum.dev.NullPulsePal('test');
verifyFalse(testCase, pulsePal.Available);
verifyNotEmpty(testCase, pulsePal.log(), 'The shim must say why it is not connected');
end


function w = waveform(frequency, pulseWidth)
% One carrier per optical channel, both the same unless a test says otherwise.
w = struct('Channel', {1, 2}, 'Frequency', frequency, 'PulseWidth', pulseWidth, ...
           'Voltage', 5, 'MaxDuration', 1.1);
end
