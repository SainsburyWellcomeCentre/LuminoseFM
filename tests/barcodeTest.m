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

function testEachSessionTypeSendsItsOwnBarcodeByDefault(testCase)
% Behaviour, sleep and ePhys calibration sessions started in the same second still send
% different barcodes, as typed and as fitted to the default cameras, and each decodes to
% its own kind; sessions a second apart carry different values.
S = lum.defaultSettings;
[fitted, ~] = lum.sync.fitToCameras(S);
kinds = lum.sync.barcodeKinds();
verifyEqual(testCase, kinds, {'Behaviour', 'Sleep', 'EphysCalibration'});
startTime = datetime(2026, 9, 25, 13, 23, 0);
for params = {S.Sync.Barcode, fitted.Sync.Barcode}
    codes = cellfun(@(kind) lum.sync.barcode(lum.sync.barcodeValue(startTime), params{1}, kind), ...
                    kinds);
    widths = [codes.MarkerWidth];
    verifyEqual(testCase, numel(unique(widths)), 3, 'Three kinds, three markers');
    verifyTrue(testCase, issorted(widths), 'Each kind''s marker is longer than the one before');
    for k = 1:3
        [rising, falling] = edgesOf(codes(k));
        [value, ~, kind] = lum.sync.decodeBarcode(rising, falling, params{1});
        verifyEqual(testCase, value, lum.sync.barcodeValue(startTime));
        verifyEqual(testCase, kind, kinds{k});
        for other = setdiff(1:3, k)
            verifyFalse(testCase, isequal(codes(k).Durations, codes(other).Durations));
        end
    end
end
verifyNotEqual(testCase, lum.sync.barcodeValue(startTime), lum.sync.barcodeValue(startTime + seconds(1)));
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

function testACancelledLaunchLeavesNoAnalogFile(testCase)
% The launch manager opens <data file>_ANLG.dat before the protocol runs; a session
% cancelled in a dialog left it behind, empty (LUMS0014, 2026-09-25 13:21:41).
ensureEmulator();
global BpodSystem %#ok<GVMIS>
saved = {BpodSystem.Data, BpodSystem.AnalogDataFile};
restore = onCleanup(@() restoreAnalog(saved));
file = [tempname '_ANLG.dat'];
BpodSystem.Data = struct('Analog', struct('FileName', file));
BpodSystem.AnalogDataFile = fopen(file, 'w');
fid = BpodSystem.AnalogDataFile;
verifyTrue(testCase, lum.dev.Flex.discardEmptyAnalogFile());
verifyFalse(testCase, isfile(file), 'The empty file is gone');
verifyEmpty(testCase, fopen(fid), 'And its handle closed');
BpodSystem.AnalogDataFile = fopen(file, 'w');
fwrite(BpodSystem.AnalogDataFile, 1:10, 'uint16');
fclose(BpodSystem.AnalogDataFile);
verifyFalse(testCase, lum.dev.Flex.discardEmptyAnalogFile(), 'A file with data is kept');
verifyTrue(testCase, isfile(file));
delete(file);
delete(restore);
end

function restoreAnalog(saved)
global BpodSystem %#ok<GVMIS>
BpodSystem.Data = saved{1};
BpodSystem.AnalogDataFile = saved{2};
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

function testTheBarcodeUsesNoGlobalTimer(testCase)
% Its elements are states, and the house light is PulsePal's (D15), so the barcode leaves
% every timer alone.
global BpodSystem %#ok<GVMIS>
ensureEmulator();
code = lum.sync.barcode(5, defaultParams());
sma = lum.sync.barcodeStateMachine(code, 'BNC2');
verifyFalse(testCase, any(sma.OutputMatrix(:, BpodSystem.HW.Pos.GlobalTimerTrig)));
verifyEqual(testCase, sma.OutputMatrix(:, strcmp(BpodSystem.StateMachineInfo.OutputChannelNames, 'BNC2'))', ...
            code.Levels);
end

%% Fitted to the cameras ------------------------------------------------------------

function testTheDefaultsAlreadyFitTheDefaultCameras(testCase)
S = lum.defaultSettings;
[fitted, changes, period] = lum.sync.fitToCameras(S);
verifyEmpty(testCase, changes, '100 Hz needs nothing widened');
verifyEqual(testCase, fitted, S);
verifyEqual(testCase, period, 0.01, 'AbsTol', 1e-12);
end

function testWithoutVideoNothingIsWidened(testCase)
S = lum.defaultSettings;
S.Camera.FrameRate = 20;
S.Camera.Enabled = false;
[fitted, changes, period] = lum.sync.fitToCameras(S);
verifyEqual(testCase, fitted, S);
verifyEmpty(testCase, changes);
verifyTrue(testCase, isnan(period));
S.Camera.Enabled = true;
[S.Camera.Cameras.Record] = deal(false);
verifyEmpty(testCase, nthOutput(2, @lum.sync.fitToCameras, S), 'No camera ticked, no video');
end

function testASlowCameraWidensTheLineAndSaysSo(testCase)
S = lum.defaultSettings;
S.Camera.FrameRate = 30;
S.Sleep.Sync.Mode = lum.SyncMode.FixedWidth;
S.Sleep.Sync.FixedWidth = 0.01;
[fitted, changes] = lum.sync.fitToCameras(S);
T = 1 / 30;
b = fitted.Sync.Barcode;
verifyGreaterThanOrEqual(testCase, [b.ZeroWidth b.Gap], 2 * T * [1 1] - 1e-9);
verifyGreaterThanOrEqual(testCase, b.OneWidth - b.ZeroWidth, 3 * T - 1e-9);
verifyGreaterThanOrEqual(testCase, b.MarkerWidth - b.OneWidth, 3 * T - 1e-9);
verifyGreaterThanOrEqual(testCase, b.SleepMarkerWidth - b.MarkerWidth, 3 * T - 1e-9);
verifyEqual(testCase, b.nBits, S.Sync.Barcode.nBits, 'Bits never change');
verifyEqual(testCase, fitted.Sync.MeanWidth - fitted.Sync.WidthJitter, 0.0667, 'AbsTol', 1e-9, ...
            'The shortest trial pulse is two frames, rounded up to the cycle');
verifyEqual(testCase, fitted.Sync.WidthJitter, S.Sync.WidthJitter, 'The spread is kept');
verifyEqual(testCase, fitted.Sleep.Sync.FixedWidth, 0.0667, 'AbsTol', 1e-9);
verifyTrue(testCase, any(contains(changes, '0 bit 20 -> 66.7 ms')));
verifyEqual(testCase, lum.sync.fitToCameras(fitted), fitted, 'Fitting twice changes nothing');
[~, ~, notes] = lum.validateSettings(S, RigConfig);
verifyTrue(testCase, any(contains(notes, 'widened so the 30 Hz cameras')));
end

function testAFittedBarcodeDecodesFromFramesAtAnyRateAndPhase(testCase)
% The claim the fitting makes: sampled once per frame, at any phase, with the camera running
% up to 5 % slower than set and each frame's timestamp jittered, every barcode still decodes.
S = lum.defaultSettings;
stream = RandStream('mt19937ar', 'Seed', 7);
for rate = [25 30 50 60 90 100 120 150]
    S.Camera.FrameRate = rate;
    fitted = lum.sync.fitToCameras(S);
    for kind = {'Behaviour', 'Sleep'}
        for trial = 1:25
            value = floor(rand(stream) * 2^32);
            code = lum.sync.barcode(value, fitted.Sync.Barcode, kind{1});
            period = (1 + 0.05 * rand(stream)) / rate;
            edges = 0.5 + [0 cumsum(code.Durations)];  % Recording starts before the barcode
            frames = rand(stream) * period + (0:floor(edges(end) / period)) * period;
            level = zeros(size(frames));
            for k = find(code.Levels == 1)
                level(frames >= edges(k) & frames < edges(k + 1)) = 1;
            end
            stamps = frames + 1e-4 * randn(stream, size(frames));
            rise = find(diff(level) == 1) + 1;
            fall = find(diff(level) == -1) + 1;
            [decoded, ~, decodedKind] = lum.sync.decodeBarcode(stamps(rise), stamps(fall), ...
                                                               fitted.Sync.Barcode);
            verifyEqual(testCase, [decoded, double(strcmp(decodedKind, kind{1}))], [value 1], ...
                        sprintf('%s barcode at %g Hz', kind{1}, rate));
        end
    end
end
end

function testASleepGapTooShortForTheCamerasIsRefused(testCase)
S = lum.defaultSettings;
S.Camera.FrameRate = 25;
S.Sleep.Sync.Mode = lum.SyncMode.FixedWidth;
S.Sleep.Sync.FixedWidth = 0.05;
S.Sleep.Sync.Interval = 0.12;
S.Sleep.Sync.IntervalJitter = 0;
verifyError(testCase, @() lum.sleep.validate(S, RigConfig), 'lum:sleep:validate:gapTooShortForCameras');
S.Camera.Enabled = false;
verifyWarningFree(testCase, @() lum.sleep.validate(S, RigConfig));
end


function value = nthOutput(n, f, varargin)
outputs = cell(1, n);
[outputs{:}] = f(varargin{:});
value = outputs{n};
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
