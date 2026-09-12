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


%% Opening PulsePal for a session ---------------------------------------------------

function testStoppingOutputsReachesAllFourAndEndsContinuousPlayback(testCase)
% Parameters change what the next trigger does, not what PulsePal is doing: a train
% still running carries on, and an output left looping continuously plays with no
% trigger at all. Both are stopped, on every output, used or not.
pulsePal = lum.dev.NullPulsePal('test');
nBefore = numel(pulsePal.log());
pulsePal.stopOutputs();
lines = pulsePal.log();
expected = arrayfun(@(k) sprintf('would stop ch%d and switch its continuous playback off', k), ...
                    1:4, 'UniformOutput', false);
verifyEqual(testCase, lines(nBefore + 1:end), expected);
end

function testALightSessionDoesNotStartWithoutPulsePal(testCase)
% Bpod gates A and B into PulsePal whether or not the session programmed it, and an
% unprogrammed PulsePal answers with whatever program it last held: light at the wrong
% times while the data file shows a correct stimulus. There is no fallback on the rig.
S = lum.defaultSettings;
S.Session.UseOpto = true;
try
    lum.dev.openPulsePal(false, S, @unreachablePulsePal);
    verifyFail(testCase, 'A light session must not start without PulsePal');
catch refusal
    verifyEqual(testCase, refusal.identifier, 'lum:dev:openPulsePal:notConnected');
    verifySubstring(testCase, refusal.message, 'no Pulse Pal on any port');
end
end

function pulsePal = unreachablePulsePal() %#ok<STOUT>
% A connection attempt that finds no device. It declares an output, as a real one does:
% an anonymous @() error(...) asked for one fails on that instead of on its message.
error('test:noDevice', 'no Pulse Pal on any port');
end

function testAConnectedPulsePalIsStoppedBeforeTheSessionUsesIt(testCase)
S = lum.defaultSettings;
S.Session.UseOpto = true;
pulsePal = lum.dev.openPulsePal(false, S, @() lum.dev.NullPulsePal('stand-in for the device'));
verifyEqual(testCase, nnz(startsWith(pulsePal.log(), 'would stop ch')), 4);
end

function testASessionWithoutLightNeverOpensPulsePal(testCase)
S = lum.defaultSettings;
S.Session.UseOpto = false;
pulsePal = lum.dev.openPulsePal(false, S, @() error('test:opened', 'PulsePal was opened'));
verifyFalse(testCase, pulsePal.Available);
end

function testTheEmulatorNeverOpensPulsePal(testCase)
pulsePal = lum.dev.openPulsePal(true, lum.defaultSettings, ...
                                @() error('test:opened', 'PulsePal was opened'));
verifyFalse(testCase, pulsePal.Available);
verifyTrue(testCase, any(strcmp(pulsePal.log(), 'would check that PulsePal answers a handshake')), ...
           'The device log reads as it would on the rig');
end


%% A healthy connection -------------------------------------------------------------

function testAPulsePalThatAnswersPassesTheCheckAndIsLoggedOnce(testCase)
pulsePal = StubPulsePal(true);
pulsePal.checkConnection();
pulsePal.checkConnection();
verifyEqual(testCase, nnz(strcmp(pulsePal.log(), 'answered a handshake')), 1, ...
            'A long session must not fill the log with answers');
end

function testAPulsePalThatStopsAnsweringFailsTheCheck(testCase)
pulsePal = StubPulsePal(true);
pulsePal.checkConnection();
pulsePal.Answers = false;
verifyError(testCase, @() pulsePal.checkConnection(), 'lum:dev:PulsePal:notResponding');
verifyTrue(testCase, any(strcmp(pulsePal.log(), 'did not answer a handshake')));
end

function testASessionDoesNotStartWithAPulsePalThatDoesNotAnswer(testCase)
% A port that opens but reaches no live device is as bad as no port.
S = lum.defaultSettings;
S.Session.UseOpto = true;
try
    lum.dev.openPulsePal(false, S, @() StubPulsePal(false));
    verifyFail(testCase, 'A PulsePal that does not answer must not be used');
catch refusal
    verifyEqual(testCase, refusal.identifier, 'lum:dev:openPulsePal:notConnected');
    verifySubstring(testCase, refusal.message, 'did not answer a handshake');
end
end

function testAConnectedPulsePalIsStoppedAndThenMustAnswer(testCase)
S = lum.defaultSettings;
S.Session.UseOpto = true;
pulsePal = lum.dev.openPulsePal(false, S, @() StubPulsePal(true));
lines = pulsePal.log();
stops = find(startsWith(lines, 'stub stop ch'));
answer = find(strcmp(lines, 'answered a handshake'));
verifyNumElements(testCase, stops, 4);
verifyNumElements(testCase, answer, 1);
verifyGreaterThan(testCase, answer, max(stops), 'Stopped first, then checked');
end


%% Sleep sessions -------------------------------------------------------------------

function testASleepSessionWithTestPulsesDoesNotStartWithoutPulsePal(testCase)
% A sleep session gates channels A and B into PulsePal exactly as a behaviour session
% does, so it is refused on the same terms, whatever the behaviour light switch says.
S = lum.defaultSettings;
S.Sleep.TestPulses.Enabled = true;
S.Session.UseOpto = false;
try
    lum.dev.openPulsePal(false, lum.sleep.deviceSettings(S), @unreachablePulsePal);
    verifyFail(testCase, 'A sleep session with test pulses must not start without PulsePal');
catch refusal
    verifyEqual(testCase, refusal.identifier, 'lum:dev:openPulsePal:notConnected');
end
end

function testASleepSessionWithoutTestPulsesNeverOpensPulsePal(testCase)
S = lum.defaultSettings;
S.Session.UseOpto = true;
settings = lum.sleep.deviceSettings(S);
pulsePal = lum.dev.openPulsePal(false, settings, @() error('test:opened', 'PulsePal was opened'));
verifyFalse(testCase, pulsePal.Available);
verifyFalse(testCase, settings.Session.UseSound, 'Sleep sessions never open the HiFi module');
end

function testEveryTestPulseCarrierIsWhatTheDeviceAccepts(testCase)
% The carriers a sleep schedule compiles must be the carriers the device takes, gated.
design = lum.defaultSettings().Sleep.TestPulses;
design.Enabled = true;
design.PlasticityTrains = true;
design.Schedule = struct('Kind', {'Probe', 'Theta burst', 'High frequency'}, 'Channels', 'A and B', ...
                         'Minutes', {1, 0, 0});
plan = lum.sleep.testPulsePlan(design);
pulsePal = lum.dev.NullPulsePal('test');
p = lum.dev.PulsePal.Param;
pulsePal.configure(plan.Steps(1).Carrier);
verifyEqual(testCase, pulsePal.sentValue(1, p.Phase1Duration), 0.11, 'AbsTol', 1e-12, ...
            'Constant light outlasts the 10 ms gate');
pulsePal.configure(plan.Steps(2).Carrier);
verifyEqual(testCase, pulsePal.sentValue(2, p.Phase1Duration), 0.005, 'AbsTol', 1e-12);
verifyEqual(testCase, pulsePal.sentValue(2, p.InterPulseInterval), 0.005, 'AbsTol', 1e-12, '100 Hz');
verifyGreaterThan(testCase, pulsePal.sentValue(1, p.PulseTrainDuration), 0.0375, ...
                  'The train outlasts each burst''s gate');
pulsePal.configure(plan.Steps(3).Carrier);
verifyEqual(testCase, [pulsePal.sentValue(1, p.TriggerMode), pulsePal.sentValue(2, p.TriggerMode)], [2 2]);
verifyGreaterThan(testCase, pulsePal.sentValue(1, p.PulseTrainDuration), 0.9975, ...
                  'A one-second burst is not cut short');
end


function w = waveform(frequency, pulseWidth)
% One carrier per optical channel, both the same unless a test says otherwise.
w = struct('Channel', {1, 2}, 'Frequency', frequency, 'PulseWidth', pulseWidth, ...
           'Voltage', 5, 'MaxDuration', 1.1);
end
