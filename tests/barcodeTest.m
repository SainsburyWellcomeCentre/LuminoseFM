function tests = barcodeTest
% barcodeTest exercises the session barcode: lum.sync.*
%
% The barcode is how a recording on another machine is matched to its behaviour
% file, so it has to decode back to exactly what was encoded, from edges alone, even
% with trial pulses after it. The encoder and decoder are pure; the state machine
% test runs under Bpod('EMU') on a stand-in channel, because the emulator has no Flex.
tests = functiontests(localfunctions);
end

function testTheBarcodeRoundTrips(testCase)
params = defaultParams();
for value = [0, 1, 123456789, 2^32 - 1]
    code = lum.sync.barcode(value, params);
    [rising, falling] = edgesOf(code);
    verifyEqual(testCase, lum.sync.decodeBarcode(rising, falling, params), value);
end
end

function testBitsGoMostSignificantFirst(testCase)
code = lum.sync.barcode(2^31, defaultParams());
verifyTrue(testCase, code.Bits(1));
verifyFalse(testCase, any(code.Bits(2:end)));
verifyEqual(testCase, code.Hex, '80000000');
end

function testTrialPulsesAfterTheBarcodeDoNotConfuseTheDecoder(testCase)
params = defaultParams();
code = lum.sync.barcode(987654, params);
[rising, falling] = edgesOf(code);
later = code.TotalDuration + (1:5);
verifyEqual(testCase, lum.sync.decodeBarcode([rising, later], [falling, later + 0.05], params), ...
            987654);
end

function testAnIncompleteBarcodeIsNotDecoded(testCase)
params = defaultParams();
[rising, falling] = edgesOf(lum.sync.barcode(42, params));
verifyTrue(testCase, isnan(lum.sync.decodeBarcode(rising(1:end-1), falling(1:end-1), params)));
end

function testTheValueIsTheSessionStartInSeconds(testCase)
start = datetime(2020, 1, 1, 0, 0, 10);
verifyEqual(testCase, lum.sync.barcodeValue(start), 10);
verifyEqual(testCase, lum.sync.barcodeTime(10), start);
sessionStart = datetime(2026, 9, 11, 14, 30, 0);
verifyEqual(testCase, lum.sync.barcodeTime(lum.sync.barcodeValue(sessionStart)), sessionStart);
end

function testWidthsMustBeTellableApart(testCase)
params = defaultParams();
params.OneWidth = params.ZeroWidth;
verifyError(testCase, @() lum.sync.barcode(1, params), 'lum:sync:barcode:badWidths');
end

function testTheDurationsAreQuantisedToTheCycle(testCase)
params = defaultParams();
params.ZeroWidth = 0.01234;
code = lum.sync.barcode(5, params);
verifyEqual(testCase, code.Durations, round(code.Durations * 1e4) / 1e4, 'AbsTol', 1e-12);
end

function testTheKindIsReadFromTheMarkers(testCase)
% A recording has to say whether it holds a behaviour or a sleep session.
params = defaultParams();
for kind = {'Behaviour', 'Sleep'}
    code = lum.sync.barcode(424242, params, kind{1});
    [rising, falling] = edgesOf(code);
    [value, ~, decodedKind] = lum.sync.decodeBarcode(rising, falling, params);
    verifyEqual(testCase, value, 424242, kind{1});
    verifyEqual(testCase, decodedKind, kind{1});
    verifyEqual(testCase, code.Kind, kind{1});
end
verifyEqual(testCase, lum.sync.barcode(1, params, 'Sleep').MarkerWidth, params.SleepMarkerWidth);
verifyEqual(testCase, lum.sync.barcode(1, params).MarkerWidth, params.MarkerWidth, ...
            'A barcode is a behaviour barcode unless it says otherwise');
end

function testTheSleepMarkerMustBeLongerThanTheBehaviourMarker(testCase)
params = defaultParams();
params.SleepMarkerWidth = params.MarkerWidth;
verifyError(testCase, @() lum.sync.barcode(1, params, 'Sleep'), 'lum:sync:barcode:badWidths');
end

function testSettingsFromBeforeSleepSessionsStillEncode(testCase)
params = rmfield(defaultParams(), 'SleepMarkerWidth');
code = lum.sync.barcode(9, params, 'Sleep');
verifyEqual(testCase, code.MarkerWidth, 2 * params.MarkerWidth);
[rising, falling] = edgesOf(code);
[~, ~, kind] = lum.sync.decodeBarcode(rising, falling, params);
verifyEqual(testCase, kind, 'Sleep');
end

function testTheAnalogStreamIsRealignedAfterTheBarcode(testCase)
% Bpod streams from the barcode's run onwards but stamps the first sample with trial
% 1's start, so everything was 1.8 s late and a trial too high (session 20260911_140213).
rate = 1000;
barcodeSamples = 1796;
analog = struct('SamplingRate', rate, 'nSamples', barcodeSamples + 3000, ...
                'TrialNumber', [ones(1, barcodeSamples), 2 * ones(1, 2000), 3 * ones(1, 1000)], ...
                'Timestamps', 410.4853 + (0:barcodeSamples + 2999) / rate, ...
                'TrialData', {{}}, 'info', struct());
aligned = lum.dev.Flex.alignAnalog(analog, 410.4853, 1);
verifyEqual(testCase, aligned.Timestamps(barcodeSamples + 1), 410.4853, 'AbsTol', 1e-9, ...
            'The first sample of trial 1 must sit at trial 1''s start');
verifyEqual(testCase, aligned.Timestamps(1), 410.4853 - barcodeSamples / rate, 'AbsTol', 1e-9);
verifyEqual(testCase, aligned.TrialNumber([1, barcodeSamples, barcodeSamples + 1, end]), [0 0 1 2]);
verifyFalse(testCase, isfield(aligned, 'TrialData'), 'The misaligned per-trial copy must go');
verifySubstring(testCase, aligned.info.Alignment, 'barcode');

untouched = lum.dev.Flex.alignAnalog(analog, 410.4853, 0);
verifyEqual(testCase, untouched.Timestamps, analog.Timestamps, ...
            'A session with nothing before trial 1 is already aligned');
verifyEqual(testCase, untouched.TrialNumber, analog.TrialNumber);
end

function testAFlexShimWithoutASyncLineDoesNotSend(testCase)
flex = lum.dev.NullFlex('test');
code = lum.sync.barcode(7, defaultParams());
verifyFalse(testCase, flex.sendBarcode(code));
verifyTrue(testCase, any(contains(flex.log(), 'not sent')));
end

function testTheStateMachineDrivesTheLineElementByElement(testCase)
global BpodSystem %#ok<GVMIS>
ensureEmulator();
params = struct('Enabled', true, 'nBits', 8, 'MarkerWidth', 0.01, 'ZeroWidth', 0.002, ...
                'OneWidth', 0.005, 'Gap', 0.002);
code = lum.sync.barcode(173, params);
sma = lum.sync.barcodeStateMachine(code, 'BNC2');
verifyEqual(testCase, numel(sma.StateNames), numel(code.Levels));
verifyEqual(testCase, sma.StateTimers, code.Durations, 'AbsTol', 1e-9);
column = find(strcmp(BpodSystem.StateMachineInfo.OutputChannelNames, 'BNC2'));
verifyEqual(testCase, sma.OutputMatrix(:, column)', code.Levels);

SendStateMachine(sma);
raw = RunStateMachine;
data = AddTrialEvents(struct(), raw);
states = data.RawEvents.Trial{1}.States;
visited = cellfun(@(name) ~isnan(states.(name)(1)), fieldnames(states));
verifyEqual(testCase, numel(visited), numel(code.Levels));
verifyTrue(testCase, all(visited), 'Every element of the barcode must run');
end


function params = defaultParams()
params = lum.defaultSettings().Sync.Barcode;
end

function [rising, falling] = edgesOf(code)
% The line's edge times, as a recording would see them.
times = [0 cumsum(code.Durations)];
highs = find(code.Levels == 1);
rising = times(highs);
falling = times(highs + 1);
end
