function tests = valveTimesTest
% valveTimesTest checks lum.valveTimes: the reward's valve times from the liquid calibration.
%
% Bpod's fit is a quadratic through a few measurements: 0 uL still gives its intercept, and
% past its peak a larger volume gets less time, then a negative one. The checks use a
% calibration of the same shape as the rig's; the times themselves come from Bpod's own
% calibration under the emulator, when this machine has one.
tests = functiontests(localfunctions);
end

function testNoWaterOpensNoValve(testCase)
verifyEqual(testCase, lum.valveTimes(0, [1 3], rigLikeCalibration()), [0 0]);
end

function testAVolumeIsANonNegativeNumber(testCase)
verifyError(testCase, @() lum.valveTimes(-1, 1, rigLikeCalibration()), 'lum:valveTimes:badAmount');
verifyError(testCase, @() lum.valveTimes(NaN, 1, rigLikeCalibration()), 'lum:valveTimes:badAmount');
end

function testAVolumePastTheFitsPeakIsRefused(testCase)
% The rig-like fit peaks near 17 uL and is negative beyond about 31 uL.
cal = rigLikeCalibration();
verifyError(testCase, @() lum.valveTimes(20, [1 3], cal), 'lum:valveTimes:outsideCalibration');
verifyError(testCase, @() lum.valveTimes(40, [1 3], cal), 'lum:valveTimes:outsideCalibration');
verifyError(testCase, @() lum.valveTimes(100, 1, cal), 'lum:valveTimes:outsideCalibration');
end

function testAVolumeWithinTheFitGivesBpodsTimes(testCase)
ensureEmulator();
assumeTrue(testCase, calibrated([1 3]), 'Valves 1 and 3 have no liquid calibration on this machine');
[times, note] = lum.valveTimes(3, [1 3]);
verifyEqual(testCase, times, GetValveTimes(3, [1 3]), 'AbsTol', 1e-12);
verifyGreaterThan(testCase, times, [0 0]);
verifyEmpty(testCase, note, '3 uL is within the rig''s measurements');
end

function testAVolumeOutsideTheMeasurementsIsNoted(testCase)
ensureEmulator();
assumeTrue(testCase, calibrated(1), 'Valve 1 has no liquid calibration on this machine');
cal = rigLikeCalibration();   % Measured from 1.2 uL
[times, note] = lum.valveTimes(1, 1, cal);
verifyGreaterThan(testCase, times, 0);
verifySubstring(testCase, note, 'extrapolated');
end


function cal = rigLikeCalibration()
% Valves 1-3 as calibrated on the rig in 2026-09: five points, 15-60 ms.
table = [15 1.2; 20 1.7; 30 3.5; 45 7; 60 13.5];
coeffs = [-0.1962 6.6762 8.2354];
cal = struct('Table', {table, table, table}, 'Coeffs', {coeffs, coeffs, coeffs});
end

function tf = calibrated(valves)
try
    tf = all(GetValveTimes(3, valves) > 0);
catch
    tf = false;
end
end
