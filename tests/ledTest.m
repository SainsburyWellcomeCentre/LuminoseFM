function tests = ledTest
% ledTest covers LED intensity: light paths, calibrations and conversions (lum.led, D17).
%
% Pure functions and files in a temporary folder only; no device, no Bpod.
tests = functiontests(localfunctions);
end

function setup(testCase)
testCase.TestData.folder = tempname;
mkdir(testCase.TestData.folder);
end

function teardown(testCase)
if isfolder(testCase.TestData.folder)
    rmdir(testCase.TestData.folder, 's');
end
end

%% Light paths ----------------------------------------------------------------------

function testTheTwoTo19BundleDefaultsToBlueOnAAndGreenOnB(testCase)
S = lum.defaultSettings;
verifyEqual(testCase, {S.Light.Bundle, S.Light.Cables}, {'2-to-19', {'blue', 'green'}});
a = lum.led.lightPath(S, 1);
b = lum.led.lightPath(S, 2);
verifyEqual(testCase, {a.Channel, a.LEDChannel, a.Cable, a.nFibers}, {'A', 1, 'blue', 9});
verifyEqual(testCase, {b.Channel, b.LEDChannel, b.Cable, b.nFibers}, {'B', 2, 'green', 10});
verifyEqual(testCase, b.Area, 10 * pi * 0.05^2, 'AbsTol', 1e-12, 'Ten 100 um fibers');
S.Light.Cables = {'green', 'blue'};   % Swapped at the commutator
verifyEqual(testCase, lum.led.lightPath(S, 1).nFibers, 10);
end

function testTheFourTo19BundleDefaultsToOrangeOnAAndBlueOnB(testCase)
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
S.Light.Cables = {'orange', 'blue'};
a = lum.led.lightPath(S, 1);
b = lum.led.lightPath(S, 2);
verifyEqual(testCase, {a.Cable, a.nFibers, b.Cable, b.nFibers}, {'orange', 5, 'blue', 5});
bundles = lum.fiberBundles();
verifyEqual(testCase, bundles(strcmp({bundles.Name}, '4-to-19')).Defaults, {'orange', 'blue'});
S.Light.Cables = {'black', 'green'};
verifyEqual(testCase, lum.led.lightPath(S, 1).nFibers, 4);
end

function testAnUnknownCableIsRefused(testCase)
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
S.Light.Cables = {'purple', 'blue'};
verifyError(testCase, @() lum.led.lightPath(S, 1), 'lum:led:lightPath:unknownCable');
verifyError(testCase, @() lum.led.lightPath(S, 3), 'lum:led:lightPath:badChannel');
end

function testTheCalibrationFileNamesTheCableAndTheChannel(testCase)
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
S.Light.Cables = {'orange', 'blue'};
[~, name] = fileparts(lum.led.calibrationFile(lum.led.lightPath(S, 1), testCase.TestData.folder));
verifyEqual(testCase, name, 'DoricLED_4-to-19_orange_A');
S.Light.Cables = {'blue', 'orange'};
[~, onB] = fileparts(lum.led.calibrationFile(lum.led.lightPath(S, 2), testCase.TestData.folder));
verifyEqual(testCase, onB, 'DoricLED_4-to-19_orange_B', 'Another file on channel B');
S.Light.Bundle = '2-to-19';
S.Light.Cables = {'blue', 'green'};
[~, name] = fileparts(lum.led.calibrationFile(lum.led.lightPath(S, 2), testCase.TestData.folder));
verifyEqual(testCase, name, 'DoricLED_2-to-19_green_B');
end

function testACalibrationStaysOnTheChannelItWasMeasuredOn(testCase)
folder = testCase.TestData.folder;
S = lum.defaultSettings;   % 2-to-19: blue on A, green on B
cal = lum.led.makeCalibration(lum.led.lightPath(S, 1), 0:100:500, 0:5, 'mW');
verifyEqual(testCase, {cal.MeasuredOn, cal.MeasuredLEDChannel, cal.Cable}, {'A', 1, 'blue'});
lum.led.saveCalibration(cal, folder);
cals = lum.led.calibrations(S, folder);
verifyEqual(testCase, cals{1}.Cable, 'blue');
verifyEmpty(testCase, cals{2}, 'Green is not calibrated');
S.Light.Cables = {'green', 'blue'};   % The cables swapped at the commutator
cals = lum.led.calibrations(S, folder);
verifyEmpty(testCase, cals{1});
verifyEmpty(testCase, cals{2}, 'Blue on B is not blue on A');
end

function testOneCableOnEachChannelKeepsTwoCalibrations(testCase)
folder = testCase.TestData.folder;
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
S.Light.Cables = {'orange', 'blue'};
onA = lum.led.makeCalibration(lum.led.lightPath(S, 1), 0:100:500, 0:5, 'mW');
lum.led.saveCalibration(onA, folder);
S.Light.Cables = {'blue', 'orange'};
onB = lum.led.makeCalibration(lum.led.lightPath(S, 2), 0:100:500, 2 * (0:5), 'mW');
lum.led.saveCalibration(onB, folder);
verifyNumElements(testCase, dir(fullfile(folder, '*.mat')), 2);
cals = lum.led.calibrations(S, folder);
verifyEqual(testCase, {cals{2}.Cable, cals{2}.MeasuredOn}, {'orange', 'B'});
verifyEqual(testCase, cals{2}.PowermW, 2 * (0:5)');
S.Light.Cables = {'orange', 'blue'};
cals = lum.led.calibrations(S, folder);
verifyEqual(testCase, cals{1}.PowermW, (0:5)', 'Orange on A has its own');
end

function testAPerCableFileIsReadOnTheChannelItWasMeasuredOn(testCase)
% 0.7.2-0.9.0 named calibrations per cable, whichever channel.
folder = testCase.TestData.folder;
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
S.Light.Cables = {'orange', 'blue'};
Calibration = lum.led.makeCalibration(lum.led.lightPath(S, 1), 0:100:500, 0:5, 'mW');
save(fullfile(folder, 'DoricLED_4-to-19_orange.mat'), 'Calibration');
cals = lum.led.calibrations(S, folder);
verifyEqual(testCase, cals{1}.MeasuredOn, 'A');
S.Light.Cables = {'blue', 'orange'};
cals = lum.led.calibrations(S, folder);
verifyEmpty(testCase, cals{2}, 'Measured on A, so not used on B');
end

%% Calibrations ---------------------------------------------------------------------

function testIrradianceIsPowerOverTheFibersArea(testCase)
path = fourToNineteen(1);
cal = lum.led.makeCalibration(path, [0 100 200], [0 1 2], 'mW');
verifyEqual(testCase, cal.IrradiancemWmm2, [0; 1; 2] / path.Area, 'RelTol', 1e-12);
verifyEqual(testCase, cal.PowermW, [0; 1; 2]);
microwatts = lum.led.makeCalibration(path, [0 100 200], [0 1000 2000], 'uW');
verifyEqual(testCase, microwatts.PowermW, cal.PowermW, 'RelTol', 1e-12, 'uW read as thousandths of mW');
verifyEqual(testCase, microwatts.PowerTyped, [0; 1000; 2000], 'What was typed is kept');
end

function testReadingsAreSortedAndBlanksDropped(testCase)
cal = lum.led.makeCalibration(fourToNineteen(2), [200 NaN 0 100], [2 5 0 NaN], 'mW');
verifyEqual(testCase, cal.CurrentmA, [0; 200]);
verifyEqual(testCase, cal.PowermW, [0; 2]);
end

function testReadingsThatCannotCalibrateAreRefused(testCase)
path = fourToNineteen(1);
verifyError(testCase, @() lum.led.makeCalibration(path, 100, 1, 'mW'), 'lum:led:makeCalibration:tooFew');
verifyError(testCase, @() lum.led.makeCalibration(path, [0 100 200], [0 2 1], 'mW'), ...
            'lum:led:makeCalibration:notRising');
verifyError(testCase, @() lum.led.makeCalibration(path, [100 100], [1 2], 'mW'), ...
            'lum:led:makeCalibration:repeatedCurrent');
verifyError(testCase, @() lum.led.makeCalibration(path, [0 100], [1 1], 'mW'), 'lum:led:makeCalibration:flat');
verifyError(testCase, @() lum.led.makeCalibration(path, [0 100], [0 1], 'W'), 'lum:led:makeCalibration:badUnit');
end

function testCurrentAndIrradianceConvertBothWays(testCase)
cal = lum.led.makeCalibration(fourToNineteen(1), [0 100 300], [0 1 2], 'mW');
irradiance = lum.led.irradiance(cal, 200);
verifyEqual(testCase, irradiance, 1.5 / cal.Area, 'RelTol', 1e-12, 'Linear between readings');
verifyEqual(testCase, lum.led.current(cal, irradiance), 200);
verifyTrue(testCase, isnan(lum.led.irradiance(cal, 400)), 'No extrapolation above');
verifyError(testCase, @() lum.led.current(cal, 3 / cal.Area), 'lum:led:current:outOfRange');
verifyError(testCase, @() lum.led.current([], 1), 'lum:led:current:noCalibration');
verifyEqual(testCase, lum.led.current(cal, 0.123 / cal.Area), round(0.123 * 100), 'Whole mA');
end

function testWindowsShowMilliampsUntilCalibrated(testCase)
[value, unit] = lum.led.toUnit([], 120);
verifyEqual(testCase, {value, unit}, {120, 'mA'});
verifyEqual(testCase, lum.led.fromUnit([], 120.4), 120);
cal = lum.led.makeCalibration(fourToNineteen(1), [0 200], [0 2], 'mW');
[value, unit] = lum.led.toUnit(cal, 100);
verifyEqual(testCase, value, 1 / cal.Area, 'RelTol', 1e-12);
verifyEqual(testCase, unit, 'mW/mm2');
verifyEqual(testCase, lum.led.fromUnit(cal, value), 100);
verifyEqual(testCase, lum.led.describe([], 50), '50 mA (not calibrated)');
verifyTrue(testCase, contains(lum.led.describe(cal, 100), 'mW/mm2'));
verifyTrue(testCase, contains(lum.led.describe(cal, 300), 'outside'));
verifyEqual(testCase, lum.led.describe(cal, NaN), 'set on the driver');
end

function testASavedCalibrationIsReadBackAndReplacedByTheNext(testCase)
folder = testCase.TestData.folder;
path = fourToNineteen(1);
verifyEmpty(testCase, lum.led.loadCalibration(path, folder), 'Nothing before the first');
first = lum.led.makeCalibration(path, 0:100:500, 0:5, 'mW', 'Notes', 'first');
[file, image] = lum.led.saveCalibration(first, folder);
verifyTrue(testCase, isfile(file));
verifyTrue(testCase, isempty(image) || isfile(image), 'The graph beside it, when it can be drawn');
verifyEqual(testCase, lum.led.loadCalibration(path, folder).Notes, 'first');
second = lum.led.makeCalibration(path, 0:100:1000, 0:10, 'mW', 'Notes', 'second');
lum.led.saveCalibration(second, folder);
loaded = lum.led.loadCalibration(path, folder);
verifyEqual(testCase, loaded.Notes, 'second', 'Recalibrating overwrites');
verifyEqual(testCase, loaded.CurrentmA, (0:100:1000)');
verifyNumElements(testCase, dir(fullfile(folder, '*.mat')), 1);
other = fourToNineteen(2);
verifyEmpty(testCase, lum.led.loadCalibration(other, folder), 'The blue cable is another cable');
end

function testACalibrationMustCoverTheLEDsRange(testCase)
% A few low readings, or too few readings, are neither saved nor used.
folder = testCase.TestData.folder;
path = fourToNineteen(1);
[~, rules] = lum.led.checkCoverage();
verifyEqual(testCase, [rules.MinLitReadings rules.MinTopCurrentmA], [4 400]);
low = lum.led.makeCalibration(path, [0 50 100], [0 0.5 1], 'mW');
verifySubstring(testCase, lum.led.checkCoverage(low), 'the highest 100 mA');
sparse = lum.led.makeCalibration(path, [0 500 1000], [0 5 9], 'mW');
verifyNotEmpty(testCase, lum.led.checkCoverage(sparse), 'Two readings above 0 mA');
verifyEmpty(testCase, lum.led.checkCoverage(lum.led.makeCalibration(path, 0:100:400, 0:4, 'mW')));
verifyError(testCase, @() lum.led.saveCalibration(low, folder), 'lum:led:saveCalibration:tooNarrow');
verifyEmpty(testCase, dir(fullfile(folder, '*.mat')), 'Nothing written');
Calibration = low;   % A file written some other way
save(lum.led.calibrationFile(path, folder), 'Calibration');
cal = verifyWarning(testCase, @() lum.led.loadCalibration(path, folder), 'lum:led:loadCalibration:unreadable');
verifyEmpty(testCase, cal, 'Not used: the channel is in mA');
verifyEqual(testCase, lum.led.loadCalibration(path, folder, false).CurrentmA, [0; 50; 100], ...
            'The calibration window still shows it, to be added to');
end

function testACalibrationTo700mAWorksWithA1000mALimit(testCase)
% Readings to 700 mA stay in use when the limit is 1000: the most is the 700 mA reading.
path = fourToNineteen(1);
cal = lum.led.makeCalibration(path, 0:50:700, (0:50:700) / 100 * path.Area, 'mW');   % 1 mW/mm2 per 100 mA
[mA, reached, note] = lum.led.currentFor(cal, 5, 1000);
verifyEqual(testCase, {mA, note}, {500, ''});
verifyEqual(testCase, reached, 5, 'AbsTol', 1e-9);
[mA, reached, note] = lum.led.currentFor(cal, 9, 1000);
verifyEqual(testCase, mA, 700, 'Never beyond the readings');
verifyEqual(testCase, reached, 7, 'AbsTol', 1e-9);
verifySubstring(testCase, note, 'at 700 mA');
end

function testADamagedFileCountsAsNoCalibration(testCase)
folder = testCase.TestData.folder;
path = fourToNineteen(1);
Calibration = struct('Cable', 'blue');  % Another cable's record in orange's file
save(lum.led.calibrationFile(path, folder), 'Calibration');
cal = verifyWarning(testCase, @() lum.led.loadCalibration(path, folder), 'lum:led:loadCalibration:unreadable');
verifyEmpty(testCase, cal);
end

function testTheCalibrationFolderIsIgnoredByGit(testCase)
ignore = fileread(fullfile(lum.repoRoot, '.gitignore'));
verifyTrue(testCase, contains(ignore, 'calibration/'));
verifyEqual(testCase, lum.led.calibrationFolder(), fullfile(lum.repoRoot, 'calibration'));
end

%% Settings -------------------------------------------------------------------------

function testLEDSettingsAreChecked(testCase)
S = lum.defaultSettings;
verifyEmpty(testCase, lum.led.validate(S));
bad = S;
bad.Doric.CurrentmA = [1100 100];
verifyError(testCase, @() lum.led.validate(bad), 'lum:led:validate:overLimit');
bad = S;
bad.Doric.MaxCurrentmA = [1200 700];
verifyError(testCase, @() lum.led.validate(bad), 'lum:led:validate:badLimit');
bad = S;
bad.Doric.CurrentmA = [10.5 100];
verifyError(testCase, @() lum.led.validate(bad), 'lum:led:validate:badCurrent');
bad = S;
bad.Doric.IrradiancemWmm2 = [-1 8];
verifyError(testCase, @() lum.led.validate(bad), 'lum:led:validate:badIrradiance');
bad = S;
bad.Sleep.TestPulses.CurrentmA = [1100 100];
verifyEmpty(testCase, lum.led.validate(bad, {}, 'Behaviour'), 'Behaviour does not read the sleep intensity');
verifyError(testCase, @() lum.led.validate(bad, {}, 'Sleep'), 'lum:led:validate:overLimit');
bad = S;
bad.Light.Bundle = '4-to-19';
bad.Light.Cables = {'blue', 'blue'};
verifyError(testCase, @() lum.led.validate(bad), 'lum:led:validate:sameCable');
verifyError(testCase, @() lum.validateSettings(setField(S, 'Doric', 'CurrentmA', [1100 0]), RigConfig), ...
            'lum:led:validate:overLimit', 'A behaviour session runs the same check');
end

function testTheDefaultIntensitiesAreEightAndTwoMilliwatts(testCase)
S = lum.defaultSettings;
verifyEqual(testCase, lum.led.intensitySetting(S, 'Behaviour'), [8 8]);
verifyEqual(testCase, lum.led.intensitySetting(S, 'Sleep'), [2 2]);
verifyEqual(testCase, S.Ephys.PairedPulse.IrradiancemWmm2, [8 8]);
verifyEqual(testCase, [S.Ephys.InputOutput.MinIrradiancemWmm2; S.Ephys.InputOutput.MaxIrradiancemWmm2], ...
            [0 0; 12 12]);
S = lum.led.intensitySetting(S, 'Sleep', [3 NaN], [NaN 50]);
[irradiance, currents] = lum.led.intensitySetting(S, 'Sleep');
verifyEqual(testCase, {irradiance, currents}, {[3 2], [100 50]}, 'NaN leaves a value as it was');
verifyEqual(testCase, lum.led.intensitySetting(S, 'Behaviour'), [8 8], 'Behaviour keeps its own');
end

function testAnIrradianceBecomesTheCurrentThatGivesIt(testCase)
S = fourToNineteenSettings();
path = lum.led.lightPath(S, 1);
cal = lum.led.makeCalibration(path, [0 100 700], [0 1 7] * path.Area, 'mW');  % 1 mW/mm2 per 100 mA
run = lum.led.intensity(S, {cal, []}, 'Behaviour');
verifyEqual(testCase, run.CurrentmA(1), 700, 'The most A gives is 7 at 700 mA: 8 is out of reach');
verifyEqual(testCase, run.ReachedmWmm2(1), 7, 'AbsTol', 1e-9);
verifyTrue(testCase, any(contains(run.Notes, 'more than the orange cable gives')));
S = lum.led.intensitySetting(S, 'Behaviour', [5 5], [NaN NaN]);
run = lum.led.intensity(S, {cal, []}, 'Behaviour');
verifyEqual(testCase, run.CurrentmA, [500 100], 'B has no calibration: its mA');
verifyEqual(testCase, run.Calibrated, [true false]);
verifyEqual(testCase, numel(run.Notes), 1);
verifyTrue(testCase, contains(run.Notes{1}, 'not calibrated on channel B'));
S.Doric.MaxCurrentmA = [300 700];
run = lum.led.intensity(S, {cal, []}, 'Behaviour');
verifyEqual(testCase, run.CurrentmA(1), 300, 'Never above the limit');
verifyEqual(testCase, lum.led.intensity(S, {cal, []}, 'EphysCalibration').CurrentmA, [0 0]);
end

function testAnUncalibratedBundleRunsInMilliamps(testCase)
S = lum.defaultSettings;   % 2-to-19, never calibrated here
run = lum.led.intensity(S, {[], []}, 'Sleep');
verifyEqual(testCase, run.CurrentmA, S.Sleep.TestPulses.CurrentmA);
verifyEqual(testCase, run.ReachedmWmm2, [NaN NaN]);
verifyNumElements(testCase, lum.led.validate(S, {[], []}, 'Sleep'), 2, 'One note per channel, no error');
end

function testACalibrationThatIsLitAtZeroMilliampsIsNoted(testCase)
% Three 0.9.0 files on the rig read 0.67-1.25 mW/mm2 with the LED off: the meter was not
% zeroed, and low irradiances got too much current.
S = fourToNineteenSettings();
path = lum.led.lightPath(S, 1);
zeroed = lum.led.makeCalibration(path, [0 100 700], [0.001 1 7] * path.Area, 'mW');
offset = lum.led.makeCalibration(path, [0 100 700], [0.67 1 7] * path.Area, 'mW');
verifyFalse(testCase, any(contains(lum.led.validate(S, {zeroed, []}, 'Behaviour'), 'not zeroed')));
notes = lum.led.validate(S, {offset, []}, 'Behaviour');
verifyTrue(testCase, any(contains(notes, 'Channel A') & contains(notes, 'not zeroed')));
end

function testCurrentForStaysWithinTheCalibrationAndTheLimit(testCase)
S = fourToNineteenSettings();
path = lum.led.lightPath(S, 1);
cal = lum.led.makeCalibration(path, [0 100 700], [0.5 1 7] * path.Area, 'mW');
[mA, reached, note] = lum.led.currentFor(cal, 4, 700);
verifyEqual(testCase, {mA, note}, {400, ''});
verifyEqual(testCase, reached, 4, 'AbsTol', 1e-9);
[mA, ~, note] = lum.led.currentFor(cal, NaN, 700);
verifyEqual(testCase, {mA, note}, {700, ''}, 'NaN asks for the most');
[mA, ~, note] = lum.led.currentFor(cal, 0, 700);
verifyEqual(testCase, {mA, note}, {0, ''}, 'Nothing asked: the lowest current, no note');
[mA, ~, note] = lum.led.currentFor(cal, 0.2, 700);
verifyEqual(testCase, mA, 0);
verifyTrue(testCase, contains(note, 'below'));
[mA, reached] = lum.led.currentFor(cal, 12, 250);
verifyEqual(testCase, mA, 250);
verifyEqual(testCase, reached, 2.5, 'AbsTol', 1e-9);
end

function testAChangeFromTheLEDWindowIsKeptForTheNextSession(testCase)
S = fourToNineteenSettings();
path = lum.led.lightPath(S, 1);
cal = lum.led.makeCalibration(path, [0 700], [0 7] * path.Area, 'mW');
kept = lum.led.keepIntensity(S, 'Behaviour', {cal, []}, [700 100], [700 100]);
verifyEqual(testCase, kept.Doric.IrradiancemWmm2, [8 8], 'Unchanged: what was asked stays');
kept = lum.led.keepIntensity(S, 'Behaviour', {cal, []}, [700 100], [350 150]);
verifyEqual(testCase, kept.Doric.IrradiancemWmm2, [3.5 8]);
verifyEqual(testCase, kept.Doric.CurrentmA, [100 150]);
kept = lum.led.keepIntensity(S, 'EphysCalibration', {cal, []}, [0 0], [350 150]);
verifyEqual(testCase, kept, S);
end

function testTheLEDIsRecordedOncePerSession(testCase)
S = lum.defaultSettings;
led = lum.dev.DoricLED('Manual', [], 'test');
cleanup = onCleanup(@() led.close());
record = lum.led.sessionRecord(S, led, {[], []});
verifyFalse(testCase, record.Controlled);
verifyEqual(testCase, record.Mode, 'Manual');
verifyEqual(testCase, [record.LightPaths.nFibers], [9 10], 'Blue on A, green on B');
verifyEqual(testCase, record.Settings, S.Doric);
verifyEqual(testCase, record.Device.CurrentmA, [NaN NaN]);
end


function S = fourToNineteenSettings()
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
S.Light.Cables = {'orange', 'blue'};
end

function path = fourToNineteen(k)
% Channel k's light path with orange on A and blue on B.
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
S.Light.Cables = {'orange', 'blue'};
path = lum.led.lightPath(S, k);
end

function S = setField(S, group, name, value)
S.(group).(name) = value;
end
