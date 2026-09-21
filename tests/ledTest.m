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

function testTheTwoTo19BundleHasFixedFibers(testCase)
S = lum.defaultSettings;
S.Light.Bundle = '2-to-19';
a = lum.led.lightPath(S, 1);
b = lum.led.lightPath(S, 2);
verifyEqual(testCase, {a.Channel, a.LEDChannel, a.Cable, a.nFibers}, {'A', 1, 'ch1 fiber', 10});
verifyEqual(testCase, {b.Channel, b.LEDChannel, b.Cable, b.nFibers}, {'B', 2, 'ch2 fiber', 9});
verifyEqual(testCase, a.Area, 10 * pi * 0.05^2, 'AbsTol', 1e-12, 'Ten 100 um fibers');
end

function testTheFourTo19BundleDefaultsToOrangeOnAAndBlueOnB(testCase)
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
verifyEqual(testCase, S.Light.Cables, {'orange', 'blue'});
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

function testTheCalibrationFileNamesTheChannelAndCable(testCase)
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
[~, name] = fileparts(lum.led.calibrationFile(lum.led.lightPath(S, 1), testCase.TestData.folder));
verifyEqual(testCase, name, 'DoricLED_A_4-to-19_orange');
S.Light.Bundle = '2-to-19';
[~, name] = fileparts(lum.led.calibrationFile(lum.led.lightPath(S, 2), testCase.TestData.folder));
verifyEqual(testCase, name, 'DoricLED_B_2-to-19_ch2-fiber');
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
first = lum.led.makeCalibration(path, [0 100], [0 1], 'mW', 'Notes', 'first');
[file, image] = lum.led.saveCalibration(first, folder);
verifyTrue(testCase, isfile(file));
verifyTrue(testCase, isempty(image) || isfile(image), 'The graph beside it, when it can be drawn');
verifyEqual(testCase, lum.led.loadCalibration(path, folder).Notes, 'first');
second = lum.led.makeCalibration(path, [0 100 200], [0 2 3], 'mW', 'Notes', 'second');
lum.led.saveCalibration(second, folder);
loaded = lum.led.loadCalibration(path, folder);
verifyEqual(testCase, loaded.Notes, 'second', 'Recalibrating overwrites');
verifyEqual(testCase, loaded.CurrentmA, [0; 100; 200]);
verifyNumElements(testCase, dir(fullfile(folder, '*.mat')), 1);
other = fourToNineteen(2);
verifyEmpty(testCase, lum.led.loadCalibration(other, folder), 'Channel B on the blue cable is another path');
end

function testADamagedFileCountsAsNoCalibration(testCase)
folder = testCase.TestData.folder;
path = fourToNineteen(1);
Calibration = struct('Channel', 'B');  % The wrong path in the right file
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
bad.Doric.CurrentmA = [800 100];
verifyError(testCase, @() lum.led.validate(bad), 'lum:led:validate:overLimit');
bad = S;
bad.Doric.MaxCurrentmA = [1200 700];
verifyError(testCase, @() lum.led.validate(bad), 'lum:led:validate:badLimit');
bad = S;
bad.Doric.CurrentmA = [10.5 100];
verifyError(testCase, @() lum.led.validate(bad), 'lum:led:validate:badCurrent');
bad = S;
bad.Light.Bundle = '4-to-19';
bad.Light.Cables = {'blue', 'blue'};
verifyError(testCase, @() lum.led.validate(bad), 'lum:led:validate:sameCable');
verifyError(testCase, @() lum.validateSettings(setField(S, 'Doric', 'CurrentmA', [900 0]), RigConfig), ...
            'lum:led:validate:overLimit', 'A behaviour session runs the same check');
end

function testACurrentOutsideItsCalibrationIsNoted(testCase)
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
cal = lum.led.makeCalibration(lum.led.lightPath(S, 1), [0 50], [0 1], 'mW');
S.Doric.CurrentmA = [100 100];
notes = lum.led.validate(S, {cal, []});
verifyNumElements(testCase, notes, 1);
verifyTrue(testCase, contains(notes{1}, 'outside its calibration'));
end

function testTheLEDIsRecordedOncePerSession(testCase)
S = lum.defaultSettings;
led = lum.dev.DoricLED('Manual', [], 'test');
cleanup = onCleanup(@() led.close());
record = lum.led.sessionRecord(S, led, {[], []});
verifyFalse(testCase, record.Controlled);
verifyEqual(testCase, record.Mode, 'Manual');
verifyEqual(testCase, [record.LightPaths.nFibers], [10 9]);
verifyEqual(testCase, record.Settings, S.Doric);
verifyEqual(testCase, record.Device.CurrentmA, [NaN NaN]);
end


function path = fourToNineteen(k)
S = lum.defaultSettings;
S.Light.Bundle = '4-to-19';
path = lum.led.lightPath(S, k);
end

function S = setField(S, group, name, value)
S.(group).(name) = value;
end
