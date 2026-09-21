function tests = doricTest
% doricTest covers the Doric LED as sessions use it: lum.dev.DoricLED and TestDoricLED (D17).
%
% The LED runs on the DoricLED package's simulated driver (SimulatedTransport), which
% answers like the device and records every command, so the tests can check what a
% session would send. Skipped where the package is not found. TestDoricLED runs under
% Bpod('EMU').
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.assumeNotEmpty(lum.dev.DoricLED.locatePackage(''), 'The DoricLED package is not on the path.');
end

function setup(testCase)
S = lum.defaultSettings;
testCase.TestData.S = S;
led = lum.dev.openDoricLED(true, S);
testCase.TestData.led = led;
testCase.addTeardown(@() led.close());
end

function testTheEmulatorGetsTheSimulatedDriverConnectingAtOnce(testCase)
led = testCase.TestData.led;
verifyEqual(testCase, led.Mode, 'Simulated');
verifyTrue(testCase, led.isControlled());
verifyFalse(testCase, led.Available, 'Not real hardware');
led.ensureReady(10);
verifyEqual(testCase, led.state(), 'Ready');
verifyTrue(testCase, contains(led.describeState(), 'Connected'));
end

function testControlSwitchedOffIsManual(testCase)
S = testCase.TestData.S;
S.Doric.Enabled = false;
led = lum.dev.openDoricLED(true, S);
cleanup = onCleanup(@() led.close());
verifyEqual(testCase, led.Mode, 'Manual');
verifyFalse(testCase, led.isControlled());
led.ensureReady();                                % Nothing to wait for
led.setUp([100 100], [700 700]);                  % Nothing sent
verifyEqual(testCase, led.CurrentmA, [NaN NaN]);
verifyEqual(testCase, led.applyPending(1), [NaN NaN]);
verifyError(testCase, @() led.request(1, 50), 'lum:dev:DoricLED:manual');
end

function testThePackageIsFoundInItsFolderOrOnThePath(testCase)
onPath = lum.dev.DoricLED.locatePackage('');
verifyEqual(testCase, lum.dev.DoricLED.locatePackage(onPath), onPath, 'Its own folder');
verifyEqual(testCase, lum.dev.DoricLED.locatePackage(tempname), onPath, ...
            'A folder without it falls back to the path');
end

function testSetUpPutsBothChannelsInExternalTTLModeAtTheirCurrents(testCase)
led = testCase.TestData.led;
led.ensureReady(10);
transport = led.LightSource.Transport;
transport.clearCalls();
led.setUp([120 80], [500 400]);
settings = transport.callsOf('SETTINGS');
verifyNumElements(testCase, settings, 2);
sent = [settings.Args];
modes = arrayfun(@(a) char(a.Settings.Mode), sent, 'UniformOutput', false);
verifyEqual(testCase, modes, {'ExtTTL', 'ExtTTL'});
verifyEqual(testCase, arrayfun(@(a) a.Settings.CurrentmA, sent), [120 80]);
verifyNotEmpty(testCase, transport.callsOf('STARTALL'), 'Both channels started');
verifyEqual(testCase, led.CurrentmA, [120 80]);
verifyEqual(testCase, [led.LightSource.Channels.MaxCurrentmA], [500 400], 'Limits on the driver');
verifyTrue(testCase, led.IsSetUp);
end

function testARequestIsSentOnlyAtTheNextPrepareWindow(testCase)
led = testCase.TestData.led;
led.ensureReady(10);
led.setUp([100 100], [700 700]);
transport = led.LightSource.Transport;
transport.clearCalls();
led.request(2, 150);
verifyEmpty(testCase, transport.callsOf('CURRENT'), 'Nothing sent while a trial may run');
verifyEqual(testCase, led.Pending, [NaN 150]);
currents = led.applyPending(7);
verifyEqual(testCase, currents, [100 150]);
drainReplies(led);
calls = transport.callsOf('CURRENT');
verifyNumElements(testCase, calls, 1);
verifyEqual(testCase, calls.Args.ma, 150);
verifyEqual(testCase, calls.Args.ch, 1, 'Channel B is the driver''s second channel');
verifyEqual(testCase, led.Pending, [NaN NaN]);
changes = led.record().Changes;
verifyEqual(testCase, changes(end, 2:4), [2 150 7], 'Channel, mA and trial recorded');
verifyError(testCase, @() led.request(1, 800), 'lum:dev:DoricLED:overLimit');
verifyError(testCase, @() led.request(1, 10.5), 'lum:dev:DoricLED:badCurrent');
end

function testAnEphysStepSetsBothCurrentsAndWaits(testCase)
led = testCase.TestData.led;
led.ensureReady(10);
led.setUp([0 0], [700 700]);
transport = led.LightSource.Transport;
transport.clearCalls();
led.setCurrents([200 NaN], 3);
calls = transport.callsOf('CURRENT');
verifyNumElements(testCase, calls, 1, 'NaN leaves B alone');
verifyEqual(testCase, led.CurrentmA, [200 0]);
led.setCurrents([200 50], 4);
verifyNumElements(testCase, transport.callsOf('CURRENT'), 2, 'An unchanged current is not sent again');
end

function testCalibrationLightIsContinuousAndSwitchesOff(testCase)
led = testCase.TestData.led;
led.ensureReady(10);
transport = led.LightSource.Transport;
transport.clearCalls();
led.lightOn(1, 250);
settings = transport.callsOf('SETTINGS');
verifyEqual(testCase, char(settings(end).Args.Settings.Mode), 'CW');
verifyEqual(testCase, settings(end).Args.Settings.CurrentmA, 250);
verifyFalse(testCase, led.IsSetUp, 'The session sets the channels up again');
led.lightOff(1);
verifyNotEmpty(testCase, transport.callsOf('STOP'));
end

function testClosingSwitchesEverythingOff(testCase)
led = testCase.TestData.led;
led.ensureReady(10);
led.setUp([100 100], [700 700]);
record = led.record();
verifyEqual(testCase, record.Mode, 'Simulated');
verifyEqual(testCase, record.CurrentmA, [100 100]);
verifyNotEmpty(testCase, record.Package, 'The package''s own record of what was acknowledged');
led.close();
verifyFalse(testCase, led.isControlled());
verifyTrue(testCase, any(contains(led.log(), 'disconnected, light off')));
led.close();   % Twice is safe
end

function testTheProtocolCanOpenTheLEDAloneAsItLaunches(testCase)
ensureEmulator();   % lum.dev.open decides the emulator from Bpod; never the rig in a test
S = testCase.TestData.S;
S.Session.UseSound = false;
S.Camera.Enabled = false;
early = lum.dev.open(RigConfig, S, 'Only', 'DoricLED');
testCase.addTeardown(@() early.doricLED.close());
verifyEqual(testCase, fieldnames(early), {'emulated'; 'doricLED'});
verifyTrue(testCase, early.emulated);
verifyEqual(testCase, early.doricLED.Mode, 'Simulated');
end

function testTestDoricLEDRunsEndToEndInTheEmulator(testCase)
global BpodSystem %#ok<GVMIS>
ensureEmulator();
before = BpodSystem.Status.BeingUsed;
% Forced: the suite's own emulator, which earlier session tests can leave marked in use.
report = TestDoricLED('Currents', [20 60], 'Count', 2, 'On', 0.05, 'Off', 0.05, 'Force', true);
verifyTrue(testCase, report.Emulated);
verifyTrue(testCase, report.Passed);
verifyEqual(testCase, [report.Sets.Current], [20 60]);
gates = report.Sets(1).Gates;
verifyEqual(testCase, height(gates), 6, 'Two on A, two on B, two on both');
verifyTrue(testCase, all(~isnan(gates.Onset)));
verifyTrue(testCase, any(contains(report.PulsePalLog, 'would set ch1')), 'PulsePal programmed');
verifyTrue(testCase, any(contains(report.LEDLog, 'set A = 60 mA')));
verifyEqual(testCase, report.LEDMode, 'Simulated');
verifyEqual(testCase, BpodSystem.Status.BeingUsed, before, 'Bpod''s status is put back');
end


function drainReplies(led)
% Non-blocking commands complete on the package's polling; poll until nothing is pending.
for i = 1:20
    led.poll();
    pause(0.01);
end
end
