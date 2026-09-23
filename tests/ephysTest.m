function tests = ephysTest
% ephysTest covers ePhys calibration sessions' schedule, checks and barcode (D18).
%
% Pure functions only: lum.ephys.plan, lum.ephys.validate, lum.ephys.describe and the
% EphysCalibration barcode kind.
tests = functiontests(localfunctions);
end

function testAnInputOutputCurveStepsEvenlyFromLowestToHighest(testCase)
S = ephysSettings();
S.Ephys.PairedPulse.Enabled = false;
plan = lum.ephys.plan(S);
verifyEqual(testCase, numel(plan.Steps), 5);
currents = vertcat(plan.Steps.CurrentmA);
verifyEqual(testCase, currents(:, 1)', [0 50 100 150 200]);
verifyTrue(testCase, all(isnan(currents(:, 2))), 'Channel B is not used');
verifyEqual(testCase, {plan.Steps.Protocol}, repmat({'Input-output'}, 1, 5));
verifyEqual(testCase, [plan.Steps.nEpochs], repmat(3, 1, 5));
verifyEqual(testCase, size(plan.Segments, 1), 15, 'One single pulse per epoch, on A');
verifyTrue(testCase, all(plan.Segments(:, 3) == 1));
verifyEqual(testCase, plan.Segments(:, 2), repmat(round(0.005 / 1e-4), 15, 1));
verifyEqual(testCase, plan.Duration, 15 * 0.5, 'AbsTol', 1e-9);
end

function testStepsFollowOneAnotherWithoutGaps(testCase)
S = ephysSettings();
plan = lum.ephys.plan(S);
starts = [plan.Steps.Start];
lengths = [plan.Steps.Duration];
verifyEqual(testCase, starts(2:end), starts(1:end-1) + lengths(1:end-1), 'AbsTol', 1e-9);
verifyEqual(testCase, [plan.Steps.FirstEpoch], 1 + [0 cumsum([plan.Steps(1:end-1).nEpochs])]);
verifyEqual(testCase, plan.Epochs(:, 5)', repelem(1:numel(plan.Steps), 3));
% Every epoch's segments are its own, in order.
for e = 1:size(plan.Epochs, 1)
    rows = plan.Epochs(e, 3):plan.Epochs(e, 4);
    verifyTrue(testCase, all(plan.Segments(rows, 4) == plan.Epochs(e, 5)));
end
% The block cutter may stop before every new step.
verifyEqual(testCase, plan.NextStepEpoch(3), 4);
end

function testPairedPulsesStepThroughTheIntervals(testCase)
S = ephysSettings();
S.Ephys.InputOutput.Enabled = false;
S.Ephys.Channels = 'A and B';
S.Ephys.PairedPulse.CurrentmA = [120 80];
plan = lum.ephys.plan(S);
verifyEqual(testCase, [plan.Steps.InterPulseInterval], [0.02 0.05 0.1]);
verifyEqual(testCase, vertcat(plan.Steps.CurrentmA), repmat([120 80], 3, 1));
first = plan.Steps(1).FirstEpoch;
rows = plan.Epochs(first, 3):plan.Epochs(first, 4);
verifyEqual(testCase, numel(rows), 4, 'Two pulses on each of A and B');
onsets = unique(plan.Segments(rows, 1));
verifyEqual(testCase, diff(onsets) * 1e-4, 0.02, 'AbsTol', 1e-9, 'Onset to onset');
verifyEqual(testCase, {plan.Steps.Label}, {'PPR 20 ms', 'PPR 50 ms', 'PPR 100 ms'});
end

function testTheOrderCanBeReversedOrShuffledReproducibly(testCase)
S = ephysSettings();
S.Ephys.PairedPulse.Enabled = false;
S.Ephys.Order = 'Descending';
plan = lum.ephys.plan(S);
currents = vertcat(plan.Steps.CurrentmA);
verifyEqual(testCase, currents(:, 1)', [200 150 100 50 0]);
S.Ephys.Order = 'Shuffled';
first = vertcat(lum.ephys.plan(S).Steps.CurrentmA);
again = vertcat(lum.ephys.plan(S).Steps.CurrentmA);
verifyEqual(testCase, first, again, 'The same seed, the same order');
verifyEqual(testCase, sort(first(:, 1))', [0 50 100 150 200]);
S.Ephys.Seed = 12345;
other = vertcat(lum.ephys.plan(S).Steps.CurrentmA);
verifyEqual(testCase, sort(other(:, 1))', [0 50 100 150 200]);
end

function testCalibratedLevelsAreEvenInIrradiance(testCase)
S = ephysSettings();
S.Ephys.PairedPulse.Enabled = false;
path = lum.led.lightPath(S, 1);
% Irradiance rising faster at first: even irradiance is uneven current.
cal = lum.led.makeCalibration(path, [0 100 200], [0 3 4], 'mW');
S.Ephys.InputOutput.MaxIrradiancemWmm2 = [NaN 12];   % The most channel A gives
plan = lum.ephys.plan(S, {cal, []});
currents = vertcat(plan.Steps.CurrentmA);
irradiance = lum.led.irradiance(cal, currents(:, 1));
% Even to within the rounding to whole mA (here up to half a mA, about 3 % of a step).
verifyEqual(testCase, diff(irradiance)', repmat(irradiance(end) / 4, 1, 4), 'RelTol', 0.05);
verifyLessThan(testCase, currents(2, 1), 50, 'A quarter of the irradiance is under a quarter of the current');
verifyEqual(testCase, vertcat(plan.Steps.IrradiancemWmm2), [irradiance, NaN(5, 1)], 'RelTol', 1e-9);
verifyEqual(testCase, currents(end, 1), 200, 'The top of the calibration');
end

function testTheDefaultCurveRunsToTwelveOrTheChannelsMost(testCase)
S = ephysSettings();
S.Ephys.InputOutput = lum.defaultSettings().Ephys.InputOutput;   % 0-12 mW/mm2
S.Ephys.InputOutput.nLevels = 5;
S.Ephys.Channels = 'A and B';
S.Ephys.PairedPulse.Enabled = false;
area = lum.led.lightPath(S, 1).Area;
bright = lum.led.makeCalibration(lum.led.lightPath(S, 1), [0 700], [0 14] * area, 'mW');
dim = lum.led.makeCalibration(lum.led.lightPath(S, 2), [0 700], [0 7] * lum.led.lightPath(S, 2).Area, 'mW');
[plan, notes] = lum.ephys.plan(S, {bright, dim});
irradiance = vertcat(plan.Steps.IrradiancemWmm2);
verifyEqual(testCase, irradiance(end, 1), 12, 'AbsTol', 0.02, 'A reaches 12');
verifyEqual(testCase, irradiance(end, 2), 7, 'AbsTol', 1e-9, 'B stops at the most it gives');
verifyEqual(testCase, plan.Steps(end).CurrentmA(2), 700);
verifyTrue(testCase, any(contains(notes, 'Input-output curve: Channel B')));
[plan, notes] = lum.ephys.plan(S, {[], []});
currents = vertcat(plan.Steps.CurrentmA);
verifyEqual(testCase, currents(end, :), S.Doric.MaxCurrentmA, 'Uncalibrated: 0 mA to the limit');
verifyNumElements(testCase, notes, 2, 'Each channel says it is in mA');
end

function testCalibratedPairsAreAtEightMilliwatts(testCase)
S = ephysSettings();
S.Ephys.InputOutput.Enabled = false;
path = lum.led.lightPath(S, 1);
cal = lum.led.makeCalibration(path, [0 700], [0 14] * path.Area, 'mW');
plan = lum.ephys.plan(S, {cal, []});
verifyEqual(testCase, plan.Steps(1).CurrentmA(1), 400, '8 of 14 mW/mm2 at 700 mA');
verifyEqual(testCase, plan.Steps(1).IrradiancemWmm2(1), 8, 'AbsTol', 1e-9);
end

function testWhatCannotRunIsRefused(testCase)
S = ephysSettings();
bad = S;
bad.Ephys.InputOutput.MaxmA = [800 NaN];
verifyError(testCase, @() lum.ephys.plan(bad), 'lum:ephys:plan:overLimit');
bad = S;
bad.Ephys.InputOutput.Enabled = false;
bad.Ephys.PairedPulse.Enabled = false;
verifyError(testCase, @() lum.ephys.plan(bad), 'lum:ephys:plan:noProtocol');
bad = S;
bad.Ephys.PairedPulse.Intervals = 0.004;   % Shorter than a 5 ms pulse plus 1 ms
verifyError(testCase, @() lum.ephys.plan(bad), 'lum:sleep:testPulsePlan:pairOverlaps');
bad = S;
bad.Ephys.PairedPulse.Intervals = 0.6;     % A pair longer than the 0.5 s between epochs
verifyError(testCase, @() lum.ephys.plan(bad), 'lum:sleep:testPulsePlan:badEpochInterval');
bad = S;
bad.Ephys.Channels = 'Alternate A and B';
verifyError(testCase, @() lum.ephys.plan(bad), 'lum:ephys:plan:badChannels');
bad = S;
bad.Doric.Enabled = false;
verifyError(testCase, @() lum.ephys.validate(bad, RigConfig, {[], []}), 'lum:ephys:validate:noLEDControl');
end

function testTheSessionIsValidatedWithItsOwnSyncPulses(testCase)
S = ephysSettings();
[plan, notes] = lum.ephys.validate(S, RigConfig, {[], []});
verifyEqual(testCase, numel(plan.Steps), 8);
verifyTrue(testCase, any(contains(notes, 'The session lasts')));
bad = S;
bad.Ephys.Sync.Interval = 0.05;       % Pulses up to 100 ms every 50 ms
verifyError(testCase, @() lum.ephys.validate(bad, RigConfig, {[], []}), 'lum:sleep:validate:pulsesOverlap');
bad = S;
bad.Ephys.InterEpochInterval = 0.05;  % No room after a pair for a sync pulse
bad.Ephys.PairedPulse.Enabled = false;
verifyError(testCase, @() lum.ephys.validate(bad, RigConfig, {[], []}), 'lum:sleep:validate:epochsCrowdSync');
end

function testTheDescriptionNamesBothProtocols(testCase)
S = ephysSettings();
plan = lum.ephys.plan(S);
lines = lum.ephys.describe(S, plan);
verifyTrue(testCase, any(startsWith(lines, 'Input-output: 5 levels, A 0-200 mA')));
verifyTrue(testCase, any(startsWith(lines, 'Paired-pulse ratio: pairs 20, 50, 100 ms apart')));
end

function testTheEphysBarcodeHasItsOwnMarker(testCase)
params = lum.defaultSettings().Sync.Barcode;
code = lum.sync.barcode(77, params, 'EphysCalibration');
verifyEqual(testCase, code.MarkerWidth, 0.3);
verifyEqual(testCase, code.Kind, 'EphysCalibration');
edges = [0 cumsum(code.Durations)];
rising = edges(code.Levels == 1);
falling = rising + code.Durations(code.Levels == 1);
[value, ~, kind] = lum.sync.decodeBarcode(rising, falling, params);
verifyEqual(testCase, value, 77);
verifyEqual(testCase, kind, 'EphysCalibration');
for other = {'Behaviour', 'Sleep'}
    code = lum.sync.barcode(5, params, other{1});
    edges = [0 cumsum(code.Durations)];
    rising = edges(code.Levels == 1);
    [~, ~, kind] = lum.sync.decodeBarcode(rising, rising + code.Durations(code.Levels == 1), params);
    verifyEqual(testCase, kind, other{1});
end
old = rmfield(params, 'EphysMarkerWidth');
verifyEqual(testCase, lum.sync.markerWidth(old, 'EphysCalibration'), 0.3, 'AbsTol', 1e-12, ...
            'Settings from before 0.7: sleep marker plus behaviour marker');
params.EphysMarkerWidth = 0.15;
verifyError(testCase, @() lum.sync.barcode(1, params, 'EphysCalibration'), 'lum:sync:barcode:badWidths');
end

function testTheCamerasWidenTheEphysMarkerAndPulses(testCase)
S = ephysSettings();
S.Camera.Enabled = true;
S.Camera.FrameRate = 30;
[fitted, changes] = lum.sync.fitToCameras(S);
T = 1 / 30;
verifyGreaterThanOrEqual(testCase, fitted.Sync.Barcode.EphysMarkerWidth, ...
                         fitted.Sync.Barcode.SleepMarkerWidth + 3 * T - 1e-9);
verifyTrue(testCase, any(contains(changes, 'ePhys calibration marker')));
verifyGreaterThanOrEqual(testCase, fitted.Ephys.Sync.MeanWidth - fitted.Ephys.Sync.WidthJitter, 2 * T - 1e-9);
end


function S = ephysSettings()
% Five input-output levels on A, three paired-pulse intervals, three repeats, 0.5 s apart.
S = lum.defaultSettings;
S.Session.Type = 'EphysCalibration';
S.Camera.Enabled = false;
S.Ephys.InterEpochInterval = 0.5;
S.Ephys.Repeats = 3;
S.Ephys.InputOutput.MaxmA = [200 NaN];
S.Ephys.InputOutput.nLevels = 5;
S.Ephys.PairedPulse.Intervals = [0.02 0.05 0.1];
S.Ephys.Sync.Interval = 0.25;
end
