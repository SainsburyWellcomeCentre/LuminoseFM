function tests = houseLightTest
% houseLightTest covers lum.dev.HouseLight: the light on PulsePal's output 3, and its record.
%
% The device runs against PulsePal's null shim and StubPulsePal, and the level a trial
% started at and the edges on Bpod's clock are read from hand-made trial events. Choosing
% the rig's light (lum.dev.openHouseLight) and hardware/TestHouseLight need Bpod('EMU').
% Switching during an emulated block is in sleepTest, and during whole sessions in
% emulatorSessionTest and sleepSessionTest.
tests = functiontests(localfunctions);
end

%% Holding and switching ------------------------------------------------------------

function testTheLightStartsWhereTheSettingsSay(testCase)
p = lum.dev.PulsePal.Param;
for on = [false true]
    pulsePal = lum.dev.NullPulsePal('test');
    houseLight = lum.dev.NullHouseLight(pulsePal, config(), on, 'test');
    verifyEqual(testCase, houseLight.On, on);
    verifyEqual(testCase, houseLight.OnAtStart, on);
    verifyEqual(testCase, pulsePal.sentValue(3, p.RestingVoltage), 5 * double(on), ...
                'Held on output 3 from the moment the session opens it');
end
end

function testASwitchIsHeldRecordedAndShown(testCase)
pulsePal = lum.dev.NullPulsePal('test');
houseLight = lum.dev.NullHouseLight(pulsePal, config(), false, 'test');
seen = containers.Map();
houseLight.addListener(@(on) remember(seen, on));
houseLight.set(true);
verifyTrue(testCase, houseLight.On);
verifyTrue(testCase, seen('last'), 'Listeners follow a switch');
verifyEqual(testCase, pulsePal.sentValue(3, lum.dev.PulsePal.Param.RestingVoltage), 5);
houseLight.set(true);   % Already on: nothing recorded
houseLight.set(false);
r = houseLight.record();
verifyEqual(testCase, r.Switches.On, [true false]);
verifyEqual(testCase, numel(r.Switches.WallTime), 2);
verifyTrue(testCase, all(isnan(r.Switches.HostTime)), 'No cameras attached');
verifyFalse(testCase, r.OnAtStart);
verifyFalse(testCase, r.OnAtEnd);
verifyEqual(testCase, {r.Input, r.OnEvent, r.OffEvent}, {'BNC1', 'BNC1High', 'BNC1Low'});
verifyEqual(testCase, [r.Output r.Voltage], [3 5]);
verifyEmpty(testCase, r.Edges.Time, 'No session data, no edges');
verifyTrue(testCase, any(strcmp(houseLight.log(), 'switched on')));
end

function testASwitchWhilePulsePalIsBusyLandsWhenItIsFree(testCase)
% The light, the record and the windows change when PulsePal takes the switch, not at the
% click: the click is inside the handshake.
pulsePal = StubPulsePal(true);
houseLight = lum.dev.NullHouseLight(pulsePal, config(), false, 'test');
seen = containers.Map();
houseLight.addListener(@(on) remember(seen, on));
pulsePal.DuringHandshake = @() clickInside(testCase, houseLight, seen);
pulsePal.checkConnection();
verifyTrue(testCase, houseLight.On, 'Switched once the handshake was over');
verifyTrue(testCase, seen('last'));
verifyEqual(testCase, houseLight.record().Switches.On, true);
end

function clickInside(testCase, houseLight, seen)
houseLight.set(true);
verifyFalse(testCase, houseLight.On, 'Not yet: PulsePal is busy');
verifyFalse(testCase, isKey(seen, 'last'));
end

function testASwitchPulsePalRefusesPutsTheBoxBack(testCase)
pulsePal = StubPulsePal(true);
houseLight = lum.dev.NullHouseLight(pulsePal, config(), false, 'test');
seen = containers.Map();
houseLight.addListener(@(on) remember(seen, on));
pulsePal.RefuseParams = true;
verifyWarning(testCase, @() houseLight.set(true), 'lum:dev:HouseLight:notSwitched');
verifyFalse(testCase, houseLight.On);
verifyFalse(testCase, seen('last'), 'The box shows the light as it is');
verifyEmpty(testCase, houseLight.record().Switches.On);
end

function testASessionDoesNotOpenALightPulsePalRefuses(testCase)
pulsePal = StubPulsePal(true);
pulsePal.RefuseParams = true;
verifyError(testCase, @() lum.dev.NullHouseLight(pulsePal, config(), true, 'test'), ...
            'lum:dev:HouseLight:notHeld');
end

function testClosingSwitchesTheLightOffOnce(testCase)
pulsePal = StubPulsePal(true);
houseLight = lum.dev.NullHouseLight(pulsePal, config(), true, 'test');
record = houseLight.record();
houseLight.close();
houseLight.close();
verifyFalse(testCase, houseLight.On);
verifyEqual(testCase, nnz(strcmp(pulsePal.log(), 'stub set ch3 param 17 = 0')), 1);
verifyTrue(testCase, record.OnAtEnd, 'The session''s record is taken before');
verifyEmpty(testCase, houseLight.record().Switches.On, 'Closing is not a switch');
houseLight.set(true);
verifyFalse(testCase, houseLight.On, 'A closed light is not switched again');
end

function testTheLevelIsKnownAtAnyMomentOfTheSession(testCase)
houseLight = lum.dev.NullHouseLight(lum.dev.NullPulsePal('test'), config(), true, 'test');
beforeSwitch = houseLight.sessionTime();
pause(0.01);
houseLight.set(false);
pause(0.01);
afterSwitch = houseLight.sessionTime();
verifyTrue(testCase, houseLight.levelAt(beforeSwitch));
verifyFalse(testCase, houseLight.levelAt(afterSwitch));
verifyTrue(testCase, houseLight.levelAt(-1), 'Before anything: the starting level');
end

%% Reading the loopback -------------------------------------------------------------

function testTheFirstEdgeGivesTheLevelATrialStartedAt(testCase)
c = config();
verifyTrue(testCase, lum.dev.HouseLight.levelAtStart(struct('BNC1Low', 2.5), c, false));
verifyFalse(testCase, lum.dev.HouseLight.levelAtStart(struct('BNC1High', 0.4), c, true));
verifyTrue(testCase, lum.dev.HouseLight.levelAtStart(struct('BNC1High', 3, 'BNC1Low', 1), c, false), ...
           'Off at 1 s, on again at 3 s: it started on');
verifyFalse(testCase, lum.dev.HouseLight.levelAtStart(struct('BNC1High', [1 3], 'BNC1Low', 2), c, true));
verifyTrue(testCase, lum.dev.HouseLight.levelAtStart(struct('Port2In', 1), c, true), ...
           'No edge: what the session knew');
verifyFalse(testCase, lum.dev.HouseLight.levelAtStart(struct(), c, false));
end

function testEdgesAreListedOnBpodsClockInTimeOrder(testCase)
sessionData = struct();
sessionData.TrialStartTimestamp = [10 20 30];
sessionData.RawEvents.Trial = {struct('Events', struct('BNC1Low', 1.5, 'Tup', 0)), ...
                               struct('Events', struct('Port1In', 2)), ...
                               struct('Events', struct('BNC1High', [0.5 2], 'BNC1Low', 1))};
edges = lum.dev.HouseLight.edges(sessionData, config());
verifyEqual(testCase, edges.Time, [11.5 30.5 31 32], 'AbsTol', 1e-12);
verifyEqual(testCase, edges.On, [false true false true]);
verifyEqual(testCase, edges.Trial, [1 3 3 3]);
none = lum.dev.HouseLight.edges(struct(), config());
verifyEmpty(testCase, none.Time);

houseLight = lum.dev.NullHouseLight(lum.dev.NullPulsePal('test'), config(), true, 'test');
verifyEqual(testCase, houseLight.record(sessionData).Edges, edges, 'In the session''s record');
end

%% Without PulsePal: a session without light ------------------------------------------

function testADisabledLightStaysOffAndCannotBeSwitched(testCase)
houseLight = lum.dev.DisabledHouseLight(config(), 'test');
seen = containers.Map();
houseLight.addListener(@(on) remember(seen, on));
verifyFalse(testCase, houseLight.Switchable);
verifyFalse(testCase, houseLight.Available);
verifyFalse(testCase, houseLight.On);
houseLight.set(true);
verifyFalse(testCase, houseLight.On);
verifyFalse(testCase, seen('last'), 'The box is put back off');
r = houseLight.record();
verifyFalse(testCase, r.Switchable);
verifyEmpty(testCase, r.Switches.On);
verifyEqual(testCase, [r.OnAtStart r.OnAtEnd], [false false]);
houseLight.close();
verifyTrue(testCase, any(contains(houseLight.log(), 'cannot be switched in this session (test)')));
end

function testASessionWithoutLightAndWithoutPulsePalGetsADisabledLight(testCase)
S = lum.defaultSettings;
S.Session.UseOpto = false;
S.Session.HouseLight = true;
houseLight = verifyWarning(testCase, ...
    @() lum.dev.openHouseLight(false, config(), S, lum.dev.NullPulsePal('connection failed')), ...
    'lum:dev:openHouseLight:disabled');
verifyClass(testCase, houseLight, 'lum.dev.DisabledHouseLight');
end

function testAPulsePalThatRefusesTheLightDisablesItOnlyWithoutLight(testCase)
ensureEmulator();  % RealHouseLight reads the state machine's inputs
S = lum.defaultSettings;
S.Session.UseOpto = false;
pulsePal = StubPulsePal(true);
pulsePal.RefuseParams = true;
houseLight = verifyWarning(testCase, @() lum.dev.openHouseLight(false, config(), S, pulsePal), ...
                           'lum:dev:openHouseLight:disabled');
verifyFalse(testCase, houseLight.Switchable);
S.Session.UseOpto = true;
verifyError(testCase, @() lum.dev.openHouseLight(false, config(), S, pulsePal), 'lum:dev:HouseLight:notHeld');
end

function testTheRigAndTheEmulatorGetTheirOwnLight(testCase)
ensureEmulator();
S = lum.defaultSettings;
S.Session.HouseLight = true;
houseLight = lum.dev.openHouseLight(false, config(), S, StubPulsePal(true));
verifyClass(testCase, houseLight, 'lum.dev.RealHouseLight');
verifyTrue(testCase, houseLight.On && houseLight.Switchable);
houseLight = lum.dev.openHouseLight(true, config(), S, lum.dev.NullPulsePal('emulator mode'));
verifyClass(testCase, houseLight, 'lum.dev.NullHouseLight');
verifyTrue(testCase, houseLight.On && houseLight.Switchable);
end

%% The loopback check the operator runs on the rig ----------------------------------------

function testTestHouseLightFindsEveryEdgeInTheEmulator(testCase)
% hardware/TestHouseLight on the emulator: soft codes switch the light through the same
% device a session uses, and each switch comes back as the loopback input's edge.
global BpodSystem %#ok<GVMIS>
ensureEmulator();
handler = BpodSystem.SoftCodeHandlerFunction;
% Forced: the suite's own emulator, which earlier session tests can leave marked in use.
report = TestHouseLight('Count', 3, 'On', 0.15, 'Off', 0.15, 'Force', true);
verifyTrue(testCase, report.Emulated);
verifyNumElements(testCase, report.Commands, 6);
verifyEqual(testCase, [report.Commands.On], logical([1 0 1 0 1 0]));
verifyEqual(testCase, report.nMissing, 0, 'Every switch reached BNC1');
verifyTrue(testCase, report.Passed);
verifyGreaterThanOrEqual(testCase, min([report.Commands.Latency]), 0, 'Each edge after its command');
verifyEqual(testCase, nnz(strcmp(report.PulsePalLog, 'would set ch3 param 17 = 5')), 3);
verifyEqual(testCase, BpodSystem.SoftCodeHandlerFunction, handler, 'Bpod''s handler put back');
end

%% The rig's wiring -----------------------------------------------------------------

function testTheRigMapNamesPulsePalOutput3AndBnc1(testCase)
rig = RigConfig;
verifyEqual(testCase, rig.HouseLight, struct('PulsePalChannel', 3, 'Voltage', 5, 'Input', 'BNC1', ...
                                             'OnEvent', 'BNC1High', 'OffEvent', 'BNC1Low'));
verifyFalse(testCase, isfield(rig.Ports, 'HouseLight'), 'Port 5 is no longer the house light');
verifyGreaterThan(testCase, rig.HouseLight.PulsePalChannel, lum.dev.PulsePal.nTriggerChannels, ...
                  'An output no BNC line gates');
end


function c = config()
c = RigConfig().HouseLight;
end

function remember(seen, on)
seen('last') = on; %#ok<NASGU> % A containers.Map is a handle
end
