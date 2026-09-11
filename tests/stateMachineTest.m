function tests = stateMachineTest
% stateMachineTest exercises trial assembly: lum.buildTrialSM.
%
% Needs Bpod running, because the state machine assembler resolves channel names
% against the connected machine. It runs against Bpod('EMU') and refuses to run
% against real hardware.
tests = functiontests(localfunctions);
end

function setupOnce(testCase) %#ok<INUSD>
ensureEmulator();
end

%% The contract ------------------------------------------------------------------

function testEveryDocumentedStateIsBuilt(testCase)
sma = lum.buildTrialSM(makeTestContext());
verifyEqual(testCase, sort(sma.StateNames), sort(contractStates()));
end

function testTheStateGraphIsTheSameWhateverTheTrialDelivers(testCase)
% Changing what a trial delivers, how its hold is shaped or what a broken hold does
% changes output actions, timers and transitions, never the states. Plots and analysis
% depend on it. The order AddState first meets the names in follows the transitions,
% so the set of names is what is compared.
reference = sort(lum.buildTrialSM(makeTestContext()).StateNames);
variants = {withSideLights(lum.defaultSettings, 0, 1), ...
            withStimulusRow(lum.defaultSettings, 'Air', true, 0.2, 0.3), ...
            withShaping(lum.defaultSettings, 'Both'), noLight(lum.defaultSettings), ...
            endingTrial(lum.defaultSettings), withCue(lum.defaultSettings, {'Tone', 'Air'}, 0.3), ...
            withCue(lum.defaultSettings, {}), withLatency(lum.defaultSettings, 0.2)};
for i = 1:numel(variants)
    names = sort(lum.buildTrialSM(makeTestContext('Settings', variants{i})).StateNames);
    verifyEqual(testCase, names, reference, sprintf('Variant %d changed the states', i));
end
end

%% The hold ----------------------------------------------------------------------

function testTheHoldLastsTheStimulusPlusThePostStimulusHold(testCase)
S = lum.defaultSettings;
S.Stimulus.Duration = 0.8;
S.GUI.PostStimulusHold = 0.2;
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, stateTimer(sma, 'CentreHold'), 1.0, 'AbsTol', 1e-9);
verifyEqual(testCase, plan.holdDuration, 1.0, 'AbsTol', 1e-9);
end

function testWithoutGraceLeavingTheHoldIsAnEarlyWithdrawal(testCase)
rig = RigConfig;
sma = lum.buildTrialSM(makeTestContext());
verifyEqual(testCase, targetOf(sma, 'CentreHold', rig.PokeOut.Centre), 'EarlyWithdrawal');
verifyEqual(testCase, tupTargetOf(sma, 'CentreHold'), 'WaitForCentreExit');
end

function testABrokenHoldRestartsTheStimulusByDefault(testCase)
% Leaving early stops the stimulus and sends the animal back to poke again; the next
% hold triggers every stimulus timer from its beginning.
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
[sma, plan] = lum.buildTrialSM(makeTestContext());
stimulusMask = sum(2 .^ ([plan.timers{:}] - 1));
verifyTrue(testCase, plan.restartsOnBreak);
verifyEqual(testCase, tupTargetOf(sma, 'EarlyWithdrawal'), 'WaitForCentrePoke');
verifyEqual(testCase, targetOf(sma, 'WaitForCentrePoke', rig.PokeIn.Centre), 'CentreHold');
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'EarlyWithdrawal'), ...
            BpodSystem.HW.Pos.GlobalTimerCancel), stimulusMask, ...
            'The stimulus must stop the moment the hold breaks');
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'CentreHold'), ...
            BpodSystem.HW.Pos.GlobalTimerTrig), stimulusMask, ...
            'Every hold must start the stimulus again');
end

function testEndTrialModeEndsTheTrialOnABrokenHold(testCase)
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', endingTrial(lum.defaultSettings)));
verifyFalse(testCase, plan.restartsOnBreak);
verifyEqual(testCase, tupTargetOf(sma, 'EarlyWithdrawal'), 'ITI');
end

function testWithGraceABreakBeyondTheGraceAlsoRestarts(testCase)
sma = lum.buildTrialSM(makeTestContext('Settings', withShaping(lum.defaultSettings, 'Shrink grace')));
verifyEqual(testCase, tupTargetOf(sma, 'HoldBreak'), 'EarlyWithdrawal');
verifyEqual(testCase, tupTargetOf(sma, 'EarlyWithdrawal'), 'WaitForCentrePoke');
end

function testTheHoldWindowIsAGlobalTimerFromTrialStart(testCase)
global BpodSystem %#ok<GVMIS>
S = lum.defaultSettings;
S.GUI.HoldWindow = 12;
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
window = plan.holdWindowTimer;
verifyEqual(testCase, sma.GlobalTimers.Duration(window), 12);
trigger = sma.OutputMatrix(stateIndex(sma, 'TrialStart'), BpodSystem.HW.Pos.GlobalTimerTrig);
verifyEqual(testCase, bitget(trigger, window), 1, 'The window must start with the trial');
verifyEqual(testCase, timerEndTargetOf(sma, 'WaitForCentrePoke', window), 'NoInitiation');
verifyEqual(testCase, conditionTargetOf(sma, 'WaitForCentrePoke', 4), 'NoInitiation', ...
            'A window that ran out during a hold must end the trial on the way back');
verifyEqual(testCase, sma.ConditionChannels(4), BpodSystem.HW.n.Inputs + window);
verifyEqual(testCase, sma.ConditionValues(4), 0);
verifyEqual(testCase, tupTargetOf(sma, 'WaitForCentrePoke'), 'WaitForCentrePoke', ...
            'Coming back to poke again must not start a wait of its own');
end

function testTheHoldWindowIsNeverCancelledOrRetriggered(testCase)
global BpodSystem %#ok<GVMIS>
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', withShaping(lum.defaultSettings, 'Both')));
bit = 2 ^ (plan.holdWindowTimer - 1);
triggers = sma.OutputMatrix(:, BpodSystem.HW.Pos.GlobalTimerTrig);
cancels = sma.OutputMatrix(:, BpodSystem.HW.Pos.GlobalTimerCancel);
verifyEqual(testCase, find(bitand(triggers, bit))', stateIndex(sma, 'TrialStart'));
verifyEmpty(testCase, find(bitand(cancels, bit)));
end

function testAHoldUnderWayWhenTheWindowEndsMayFinish(testCase)
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', withShaping(lum.defaultSettings, 'Both')));
for state = {'PreStimulusHold', 'CentreHold', 'HoldBreak', 'CentreHoldResumed'}
    verifyEqual(testCase, timerEndTargetOf(sma, state{1}, plan.holdWindowTimer), state{1}, ...
                sprintf('%s must not end on the hold window', state{1}));
end
end

function testAGrownHoldSetsTheHoldTimer(testCase)
S = withShaping(lum.defaultSettings, 'Grow hold');
S.GUI.HoldStart = 0.25;
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, stateTimer(sma, 'CentreHold'), 0.25, 'AbsTol', 1e-9);
verifyEmpty(testCase, plan.holdClock, 'Growing the hold alone needs no global timer');
end

function testGraceTimesTheHoldWithAGlobalTimer(testCase)
rig = RigConfig;
S = withShaping(lum.defaultSettings, 'Shrink grace');
S.GUI.GraceStart = 0.3;
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
clock = plan.holdClock;
verifyNotEmpty(testCase, clock);
verifyEqual(testCase, sma.GlobalTimers.Duration(clock), plan.holdDuration, 'AbsTol', 1e-9);

verifyEqual(testCase, targetOf(sma, 'CentreHold', rig.PokeOut.Centre), 'HoldBreak');
verifyEqual(testCase, timerEndTargetOf(sma, 'CentreHold', clock), 'WaitForCentreExit');
verifyEqual(testCase, stateTimer(sma, 'HoldBreak'), 0.3, 'AbsTol', 1e-9);
verifyEqual(testCase, targetOf(sma, 'HoldBreak', rig.PokeIn.Centre), 'CentreHoldResumed');
verifyEqual(testCase, tupTargetOf(sma, 'HoldBreak'), 'EarlyWithdrawal');
verifyEqual(testCase, timerEndTargetOf(sma, 'HoldBreak', clock), 'WaitForCentreExit');
verifyEqual(testCase, targetOf(sma, 'CentreHoldResumed', rig.PokeOut.Centre), 'HoldBreak');
verifyEqual(testCase, timerEndTargetOf(sma, 'CentreHoldResumed', clock), 'WaitForCentreExit');
end

function testComingBackFromABreakDoesNotRestartTheStimulus(testCase)
global BpodSystem %#ok<GVMIS>
S = withShaping(lum.defaultSettings, 'Shrink grace');
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
triggers = sma.OutputMatrix(:, BpodSystem.HW.Pos.GlobalTimerTrig);
expected = sum(2 .^ ([plan.timers{:}, plan.holdClock] - 1));
verifyEqual(testCase, triggers(stateIndex(sma, 'CentreHold')), expected);
verifyEqual(testCase, triggers(stateIndex(sma, 'HoldBreak')), 0);
verifyEqual(testCase, triggers(stateIndex(sma, 'CentreHoldResumed')), 0);
end

%% Light -------------------------------------------------------------------------

function testEachStretchOfLightBecomesOneGlobalTimer(testCase)
S = withPulses(lum.defaultSettings, [1 1 0 0.75; 1 2 0.25 1.0]);
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
verifyNumElements(testCase, [plan.timers{:}], 2);
verifyEqual(testCase, plan.nTimersUsed, 3, 'Two for light, one for the hold window');
verifyEqual(testCase, sma.GlobalTimers.Duration(1:2), [0.75 0.75], 'AbsTol', 1e-9);
verifyEqual(testCase, sma.GlobalTimers.OnsetDelay(1:2), [0 0.25], 'AbsTol', 1e-9);
end

function testLightTimersDriveTheRightBncLines(testCase)
global BpodSystem %#ok<GVMIS>
S = withPulses(lum.defaultSettings, [1 2 0 0.5; 1 1 0.5 1.0]);
sma = lum.buildTrialSM(makeTestContext('Settings', S));
outputs = BpodSystem.StateMachineInfo.OutputChannelNames;
% Channel A's segments come first, so timer 1 is BNC1 (from 0.5 s) and timer 2 BNC2.
verifyEqual(testCase, outputs{sma.GlobalTimers.OutputChannel(1)}, 'BNC1');
verifyEqual(testCase, outputs{sma.GlobalTimers.OutputChannel(2)}, 'BNC2');
verifyEqual(testCase, sma.GlobalTimers.OnsetDelay(1:2), [0.5 0], 'AbsTol', 1e-9);
end

function testTheHoldTriggersEveryLightTimerAtOnce(testCase)
global BpodSystem %#ok<GVMIS>
S = withPulses(lum.defaultSettings, [1 1 0 0.25; 1 2 0.25 0.5; 1 1 0.5 0.75; 1 2 0.75 1]);
sma = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'CentreHold'), ...
            BpodSystem.HW.Pos.GlobalTimerTrig), 15, 'All four timers together (binary 1111)');
end

function testAnEarlyWithdrawalCancelsTheLight(testCase)
global BpodSystem %#ok<GVMIS>
sma = lum.buildTrialSM(makeTestContext());
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'EarlyWithdrawal'), ...
            BpodSystem.HW.Pos.GlobalTimerCancel), 1);
end

function testAControlTrialUsesNoTimersButHoldsJustAsLong(testCase)
context = makeTestContext();
context.spec.OptoOn = false;
[sma, plan] = lum.buildTrialSM(context);
verifyEmpty(testCase, [plan.timers{:}], 'No light, no light timers');
verifyEqual(testCase, plan.nTimersUsed, 1, 'Only the hold window');
verifyEqual(testCase, stateTimer(sma, 'CentreHold'), context.S.Stimulus.Duration, ...
            'AbsTol', 1e-9, 'The hold must not tell the animal whether light was delivered');
end

%% Other stimulus components ---------------------------------------------------------

function testASideLightLightsThePortThatPays(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
outputs = BpodSystem.StateMachineInfo.OutputChannelNames;
S = withSideLights(lum.defaultSettings, 0, 1);
for side = 1:2
    sma = lum.buildTrialSM(makeTestContext('Settings', S, 'Side', side));
    column = find(strcmp(outputs, rig.LED.(rig.Sides{side})));
    verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'CentreHold'), column), ...
                S.GUI.PortLightIntensity, sprintf('The %s port must light', rig.Sides{side}));
end
end

function testATimedSideLightIsAGlobalTimerAtPortBrightness(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
outputs = BpodSystem.StateMachineInfo.OutputChannelNames;
S = withSideLights(lum.defaultSettings, 0.2, 0.3);
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S, 'Side', 1));
light = plan.timers{end};   % The side light is the last stimulus component built
verifyEqual(testCase, numel(light), 1);
verifyEqual(testCase, outputs{sma.GlobalTimers.OutputChannel(light)}, rig.LED.Left);
verifyEqual(testCase, sma.GlobalTimers.OnsetDelay(light), 0.2, 'AbsTol', 1e-9);
verifyEqual(testCase, sma.GlobalTimers.Duration(light), 0.3, 'AbsTol', 1e-9);
verifyEqual(testCase, sma.GlobalTimers.OnMessage(light), S.GUI.PortLightIntensity, ...
            'A timer on a PWM line takes its brightness from OnMessage');
end

function testATimedAirPuffIsAGlobalTimerOnTheAirValve(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
outputs = BpodSystem.StateMachineInfo.OutputChannelNames;
S = withStimulusRow(lum.defaultSettings, 'Air', true, 0.1, 0.2);
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
air = plan.timers{2};
verifyEqual(testCase, outputs{sma.GlobalTimers.OutputChannel(air)}, rig.Valve.Air);
verifyEqual(testCase, [sma.GlobalTimers.OnsetDelay(air), sma.GlobalTimers.Duration(air)], ...
            [0.1 0.2], 'AbsTol', 1e-9);
end

function testAStimulusTonePlaysItsGroupsToneNotTheCue(testCase)
S = withStimulusRow(withCue(lum.defaultSettings, {'CentreLight', 'Tone'}), 'Tone', true, 0, 0.2);
context = withStubHiFi(makeTestContext('Settings', S));
tone = context.stimulus{cellfun(@(c) isa(c, 'lum.stim.Sound'), context.stimulus)};
slots = zeros(1, 2);
for group = 1:2
    context.spec.StimulusGroup = group;
    action = tone.outputActions(context);
    verifyNotEmpty(testCase, action, 'A stimulus tone must produce an output action');
    slots(group) = double(action{2}(2)) + 1;   % The module indexes slots from 0
end
verifyNotEqual(testCase, slots(1), slots(2), 'The two groups must sound different');
verifyFalse(testCase, any(slots == context.sounds('Cue')), 'Not the trial-start cue tone');
end

function testASideTonePlaysTheRewardedSidesTone(testCase)
S = lum.defaultSettings;
S.Left.Tone.Enabled = true;
S.Right.Tone.Enabled = true;
context = withStubHiFi(makeTestContext('Settings', S));
tone = context.stimulus{cellfun(@(c) isa(c, 'lum.stim.Sound'), context.stimulus)};
for side = 1:2
    context.spec.CorrectSide = side;
    action = tone.outputActions(context);
    verifyEqual(testCase, double(action{2}(2)) + 1, ...
                context.sounds([context.rig.Sides{side} 'Tone']));
end
end

%% Cue ---------------------------------------------------------------------------

function testThePokeStartsTheStimulusAtOnce(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
[sma, plan] = lum.buildTrialSM(makeTestContext());
verifyEqual(testCase, tupTargetOf(sma, 'TrialStart'), 'WaitForCentrePoke');
verifyEqual(testCase, targetOf(sma, 'WaitForCentrePoke', rig.PokeIn.Centre), 'CentreHold', ...
            'With no latency, no state may stand between the poke and the stimulus');
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'CentreHold'), ...
            BpodSystem.HW.Pos.GlobalTimerTrig), sum(2 .^ ([plan.timers{:}] - 1)));
end

function testALatencyIsHeldBeforeTheStimulusStarts(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
for S = {withLatency(lum.defaultSettings, 0.2), withShaping(withLatency(lum.defaultSettings, 0.2), 'Both')}
    [sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S{1}));
    verifyEqual(testCase, targetOf(sma, 'WaitForCentrePoke', rig.PokeIn.Centre), 'PreStimulusHold');
    verifyEqual(testCase, stateTimer(sma, 'PreStimulusHold'), 0.2, 'AbsTol', 1e-9);
    verifyEqual(testCase, tupTargetOf(sma, 'PreStimulusHold'), 'CentreHold');
    verifyEqual(testCase, targetOf(sma, 'PreStimulusHold', rig.PokeOut.Centre), 'EarlyWithdrawal', ...
                'Leaving during the latency is a broken hold, never forgiven by grace');
    triggers = sma.OutputMatrix(:, BpodSystem.HW.Pos.GlobalTimerTrig);
    verifyEqual(testCase, triggers(stateIndex(sma, 'PreStimulusHold')), 0, ...
                'Nothing of the stimulus starts before the latency is over');
    verifyEqual(testCase, triggers(stateIndex(sma, 'CentreHold')), ...
                sum(2 .^ ([plan.timers{:}, plan.holdClock] - 1)));
    verifyEqual(testCase, plan.latency, 0.2);
end
end

function testTheCueIsOnUntilThePoke(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
outputs = BpodSystem.StateMachineInfo.OutputChannelNames;
S = withCue(lum.defaultSettings, {'CentreLight', 'Air'});
sma = lum.buildTrialSM(makeTestContext('Settings', S));
row = stateIndex(sma, 'WaitForCentrePoke');
verifyEqual(testCase, sma.OutputMatrix(row, strcmp(outputs, rig.LED.Centre)), S.GUI.PortLightIntensity);
verifyEqual(testCase, sma.OutputMatrix(row, strcmp(outputs, rig.Valve.Air)), 1);
verifyEqual(testCase, stateTimer(sma, 'WaitForCentrePoke'), 0, ...
            'The cue lasts as long as the animal takes; only the hold window ends it');
end

function testTheCueStaysOnThroughTheStimulusByDefault(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
centreChannel = strcmp(BpodSystem.StateMachineInfo.OutputChannelNames, rig.LED.Centre);
sma = lum.buildTrialSM(makeTestContext());
intensity = lum.defaultSettings().GUI.PortLightIntensity;
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'CentreHold'), centreChannel), intensity);
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'WaitForCentreExit'), centreChannel), 0);
end

function testACueComponentCanGoOffAsTheStimulusStarts(testCase)
rig = RigConfig;
context = makeTestContext('Settings', withCue(lum.defaultSettings, {'CentreLight'}, 0));
[~, plan] = lum.buildTrialSM(context);
verifyEqual(testCase, context.cue{1}.onsetActions(context), {rig.LED.Centre, 0});
verifyEmpty(testCase, [plan.cueTimers{:}], 'Off at the poke needs no timer');
end

function testACueComponentThatStopsPartWayIsATimerFromThePoke(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
outputs = BpodSystem.StateMachineInfo.OutputChannelNames;
S = withCue(lum.defaultSettings, {'Air'}, 0.3);
S.Stimulus.Duration = 1;
context = makeTestContext('Settings', S);
[sma, plan] = lum.buildTrialSM(context);
air = [plan.cueTimers{:}];
verifyNumElements(testCase, air, 1);
verifyEqual(testCase, outputs{sma.GlobalTimers.OutputChannel(air)}, rig.Valve.Air);
verifyEqual(testCase, [sma.GlobalTimers.OnsetDelay(air), sma.GlobalTimers.Duration(air)], ...
            [0 0.3], 'AbsTol', 1e-9);
triggers = sma.OutputMatrix(:, BpodSystem.HW.Pos.GlobalTimerTrig);
cancels = sma.OutputMatrix(:, BpodSystem.HW.Pos.GlobalTimerCancel);
verifyEqual(testCase, bitget(triggers(stateIndex(sma, 'CentreHold')), air), 1, ...
            'Timed from the poke, so started with the stimulus');
verifyEqual(testCase, bitget(cancels(stateIndex(sma, 'EarlyWithdrawal')), air), 1);
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'WaitForCentrePoke'), ...
            strcmp(outputs, rig.Valve.Air)), 1, 'Still on until the poke');
[~, reserved] = lum.timerBudget(context.S, context.rig);
verifyEqual(testCase, reserved.Components, 1, 'The budget must count it');
verifyEqual(testCase, plan.nTimersUsed, size(context.pattern.Segments, 1) ...
            + reserved.HoldWindow + reserved.Components);
end

function testTheCueTonePlaysUntilThePokeThenAsItsRowSays(testCase)
S = withCue(lum.defaultSettings, {'Tone'}, 0.3);
context = withStubHiFi(makeTestContext('Settings', S));
tone = context.cue{1};
verifyClass(testCase, tone, 'lum.stim.CueTone');
loop = tone.outputActions(context);
verifyEqual(testCase, double(loop{2}(2)) + 1, context.sounds('Cue'));
tail = tone.onsetActions(context);
verifyEqual(testCase, double(tail{2}(2)) + 1, context.sounds('CueTail'), ...
            'Part way: the tail replaces the loop, with no timer');
verifyEqual(testCase, tone.nTimersNeeded(context), 0);

context.S = withCue(lum.defaultSettings, {'Tone'}, 0);
verifyEqual(testCase, tone.onsetActions(context), context.devices.hifi.stopAction());
context.S = withCue(lum.defaultSettings, {'Tone'});
verifyEmpty(testCase, tone.onsetActions(context), 'The whole stimulus: the loop plays on');
end

function testAPunishmentNoiseFinishesBeforeTheCueToneReturns(testCase)
S = withCue(lum.defaultSettings, {'CentreLight', 'Tone'});
S.GUI.PunishCondition = 4;   % Both mistakes
S.GUI.PunishType = 2;        % White noise only
S.GUI.PunishTimeout = 0;
S.Sound.NoiseDuration = 0.5;
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, stateTimer(sma, 'EarlyWithdrawal'), 0.5, 'AbsTol', 1e-9);
verifyEqual(testCase, plan.earlyWithdrawalTimer, 0.5, 'AbsTol', 1e-9);
[~, plan] = lum.buildTrialSM(makeTestContext('Settings', endingTrial(S)));
verifyEqual(testCase, plan.earlyWithdrawalTimer, 0, 'Ending the trial, nothing follows to cut it');
[~, plan] = lum.buildTrialSM(makeTestContext('Settings', withCue(S, {'CentreLight'})));
verifyEqual(testCase, plan.earlyWithdrawalTimer, 0, 'No cue tone, nothing to cut it');
end

%% Response ----------------------------------------------------------------------

function testTheResponseWindowOpensOnlyAfterTheAnimalLeavesTheCentrePort(testCase)
% With the side ports live while the nose is still in the centre port, the beam break
% on the way out would be scored as a choice and a valve would open as the hold ends.
rig = RigConfig;
sma = lum.buildTrialSM(makeTestContext());
verifyEqual(testCase, tupTargetOf(sma, 'CentreHold'), 'WaitForCentreExit');
verifyEqual(testCase, targetOf(sma, 'WaitForCentreExit', rig.PokeOut.Centre), 'WaitForResponse');
verifyEqual(testCase, conditionTargetOf(sma, 'WaitForCentreExit', 3), 'WaitForResponse', ...
            'A hold that ended during a forgiven break must still reach the response window');
for state = sma.StateNames
    if ~strcmp(state{1}, 'WaitForCentreExit')
        verifyNotEqual(testCase, tupTargetOf(sma, state{1}), 'WaitForResponse', ...
                       sprintf('%s must not open the response window on its timer', state{1}));
    end
end
for event = {rig.PokeIn.Left, rig.PokeIn.Right}
    verifyEqual(testCase, targetOf(sma, 'WaitForCentreExit', event{1}), 'WaitForCentreExit', ...
                sprintf('%s must be ignored until the animal has withdrawn', event{1}));
end
end

function testFailingToLeaveTheCentrePortIsANoResponse(testCase)
S = lum.defaultSettings;
S.GUI.ResponseWindow = 7;
sma = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, stateTimer(sma, 'WaitForCentreExit'), 7);
verifyEqual(testCase, tupTargetOf(sma, 'WaitForCentreExit'), 'NoResponse');
end

function testTheStimulusStopsWhenTheHoldEnds(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
sma = lum.buildTrialSM(makeTestContext());
row = stateIndex(sma, 'WaitForCentreExit');
centreChannel = find(strcmp(BpodSystem.StateMachineInfo.OutputChannelNames, rig.LED.Centre));
verifyEqual(testCase, sma.OutputMatrix(row, BpodSystem.HW.Pos.GlobalTimerCancel), 1);
verifyEqual(testCase, sma.OutputMatrix(row, centreChannel), 0);
end

function testBothSidesLeadToRewardDuringHabituation(testCase)
context = makeTestContext();
context.spec.RewardedSides = [1 2];
sma = lum.buildTrialSM(context);
verifyEqual(testCase, targetOf(sma, 'WaitForResponse', 'Port1In'), 'LeftRewardDelay');
verifyEqual(testCase, targetOf(sma, 'WaitForResponse', 'Port3In'), 'RightRewardDelay');
end

function testTheWrongSideIsAnIncorrectChoiceOnceTrainingStarts(testCase)
sma = lum.buildTrialSM(makeTestContext());
verifyEqual(testCase, targetOf(sma, 'WaitForResponse', 'Port1In'), 'LeftRewardDelay');
verifyEqual(testCase, targetOf(sma, 'WaitForResponse', 'Port3In'), 'IncorrectChoice');
end

function testTheGuideLightFollowsEachSidesSetting(testCase)
global BpodSystem %#ok<GVMIS>
rig = RigConfig;
leftChannel = find(strcmp(BpodSystem.StateMachineInfo.OutputChannelNames, rig.LED.Left));
S = lum.defaultSettings;   % Training stage 2
S.Left.GuideLight = 'Always';
sma = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'WaitForResponse'), leftChannel), ...
            S.GUI.PortLightIntensity);
S.Left.GuideLight = 'Habituation only';
sma = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'WaitForResponse'), leftChannel), 0);
S.Task.TrainingStage = 1;
sma = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'WaitForResponse'), leftChannel), ...
            S.GUI.PortLightIntensity);
end

%% Punishment --------------------------------------------------------------------

function testPunishmentSettingsChangeTimersNotStates(testCase)
S = lum.defaultSettings;
S.GUI.PunishTimeout = 3;
S.GUI.PunishCondition = 1;  % None
[unpunished, unpunishedPlan] = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, stateTimer(unpunished, 'IncorrectChoice'), 0);
verifyEqual(testCase, stateTimer(unpunished, 'EarlyWithdrawal'), 0);
verifyFalse(testCase, unpunishedPlan.incorrectChoicePunishment.Applies);

S.GUI.PunishCondition = 4;  % Both mistakes
S.GUI.PunishType = 1;       % Timeout only
punished = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, stateTimer(punished, 'IncorrectChoice'), 3);
verifyEqual(testCase, stateTimer(punished, 'EarlyWithdrawal'), 3);
verifyEqual(testCase, sort(unpunished.StateNames), sort(punished.StateNames));
end

function testNoiseOnlyPunishmentDoesNotHoldTheAnimal(testCase)
S = lum.defaultSettings;
S.GUI.PunishTimeout = 3;
S.GUI.PunishCondition = 4;
S.GUI.PunishType = 2;  % White noise only
[sma, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, stateTimer(sma, 'IncorrectChoice'), 0);
verifyTrue(testCase, plan.incorrectChoicePunishment.PlayNoise);
end

%% Sync and timers -----------------------------------------------------------------

function testNoSyncTimerIsBuiltWithoutFlexOutput(testCase)
[~, plan] = lum.buildTrialSM(makeTestContext());
verifyEmpty(testCase, plan.syncTimer);
end

function testAPulsedSyncModeUsesAGlobalTimer(testCase)
S = lum.defaultSettings;
S.Sync.Mode = lum.SyncMode.FixedWidth;
context = makeTestContext('Settings', S, 'SyncChannel', 'BNC2');
context.spec.SyncMode = lum.SyncMode.FixedWidth;
context.spec.SyncPulseWidth = 0.02;
[sma, plan] = lum.buildTrialSM(context);
verifyNotEmpty(testCase, plan.syncTimer);
verifyEqual(testCase, sma.GlobalTimers.Duration(plan.syncTimer), 0.02, 'AbsTol', 1e-9);
end

function testTaskEventSyncNeedsNoTimerAndFollowsTheTrial(testCase)
global BpodSystem %#ok<GVMIS>
column = find(strcmp(BpodSystem.StateMachineInfo.OutputChannelNames, 'BNC2'));
S = lum.defaultSettings;
S.Sync.Mode = lum.SyncMode.TaskEvents;
context = makeTestContext('Settings', S, 'SyncChannel', 'BNC2');
context.spec.SyncMode = lum.SyncMode.TaskEvents;
context.spec.SyncPulseWidth = NaN;
[sma, plan] = lum.buildTrialSM(context);
verifyEmpty(testCase, plan.syncTimer, 'Task-event sync must cost no global timer');
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'TrialStart'), column), 1);
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'CentreHold'), column), 0);
latencySma = lum.buildTrialSM(makeTestContext('Settings', withLatency(S, 0.1), 'SyncChannel', 'BNC2', ...
                                              'Spec', context.spec));
verifyEqual(testCase, latencySma.OutputMatrix(stateIndex(latencySma, 'PreStimulusHold'), column), 0);
verifyEqual(testCase, sma.OutputMatrix(stateIndex(sma, 'NoInitiation'), column), 0);
end

function testTheBuilderUsesExactlyTheTimersTheBudgetReserved(testCase)
% lum.timerBudget sizes the stimulus set before the session; the builder spends the
% timers trial by trial. If they disagreed, a valid set could overflow a trial.
S = withShaping(withStimulusRow(lum.defaultSettings, 'Air', true, 0.1, 0.2), 'Shrink grace');
S.Sync.Mode = lum.SyncMode.FixedWidth;
context = makeTestContext('Settings', S, 'SyncChannel', 'BNC2');
context.spec.SyncMode = lum.SyncMode.FixedWidth;
context.spec.SyncPulseWidth = 0.02;
[~, plan] = lum.buildTrialSM(context);
[budget, reserved] = lum.timerBudget(context.S, context.rig);
nLight = size(context.pattern.Segments, 1);
verifyEqual(testCase, plan.nTimersUsed, ...
            nLight + reserved.HoldWindow + reserved.Sync + reserved.HoldClock + reserved.Components);
verifyLessThanOrEqual(testCase, nLight, budget);
end

%% Running -----------------------------------------------------------------------

function testATrialRunsToCompletionInTheEmulator(testCase)
% The state machine must not merely assemble: it has to run. With no pokes the hold
% window runs out in WaitForCentrePoke, and the trial goes to NoInitiation and exits.
context = makeTestContext('Settings', quickSettings(lum.defaultSettings));
assertRunsToNoInitiation(testCase, context);
end

function testAGraceTrialRunsInTheEmulator(testCase)
% The hold clock, the timer-end transitions and condition 3 all have to be accepted by
% SendStateMachine and run, even on a trial that never reaches the hold.
context = makeTestContext('Settings', quickSettings(withShaping(lum.defaultSettings, 'Both')));
assertRunsToNoInitiation(testCase, context);
end

function testALatencyTrialRunsInTheEmulator(testCase)
context = makeTestContext('Settings', quickSettings(withLatency(lum.defaultSettings, 0.01)));
assertRunsToNoInitiation(testCase, context);
end

function testACueTimedFromThePokeRunsInTheEmulator(testCase)
% A cue timer on the air valve and the cue's outputs have to be accepted and run.
context = makeTestContext('Settings', quickSettings(withCue(lum.defaultSettings, ...
                                                            {'CentreLight', 'Air'}, 0.02)));
assertRunsToNoInitiation(testCase, context);
end


%% Helpers -----------------------------------------------------------------------

function names = contractStates()
names = {'TrialStart', 'WaitForCentrePoke', 'PreStimulusHold', 'CentreHold', ...
         'HoldBreak', 'CentreHoldResumed', 'WaitForCentreExit', 'WaitForResponse', ...
         'EarlyWithdrawal', 'LeftRewardDelay', 'RightRewardDelay', 'LeftReward', ...
         'RightReward', 'DrinkingLeft', 'DrinkingRight', 'DrinkingGrace', ...
         'WithdrewBeforeReward', 'IncorrectChoice', 'NoResponse', 'NoInitiation', 'ITI'};
end

function S = withShaping(S, mode)
S.Task.HoldShaping = mode;
end

function S = withLatency(S, latency)
S.Stimulus.Latency = latency;
end

function S = endingTrial(S)
S.Task.OnHoldBreak = 'End trial';
end

function S = noLight(S)
S.Session.UseOpto = false;
end

function S = withSideLights(S, onset, duration)
S.Left.Light = struct('Enabled', true, 'Onset', onset, 'Duration', duration);
S.Right.Light = struct('Enabled', true, 'Onset', onset, 'Duration', duration);
end

function S = withStimulusRow(S, type, enabled, onset, duration)
row = strcmp({S.Stimulus.Components.Type}, type);
S.Stimulus.Components(row).Enabled = enabled;
S.Stimulus.Components(row).Onset = onset;
S.Stimulus.Components(row).Duration = duration;
end

function S = withPulses(S, pulses)
% One hand-drawn group, paying left, over a 1 s window.
S.Stimulus.Duration = 1;
S.Stimulus.Generator.Family = 'arbitrary';
S.Stimulus.Generator.nGroups = 1;
S.Stimulus.Generator.Pulses = pulses;
S.Task.GroupPLeft = 1;
end

function S = quickSettings(S)
% Short everywhere, so an emulated trial takes a fraction of a second.
S.GUI.HoldWindow = 0.05;
S.GUI.ITI = 0.05;
end

function context = withStubHiFi(context)
% A HiFi shim that reports itself available, with slots loaded, so a sound component's
% output action can be read back.
context.devices.hifi = StubHiFi(context.rig.Sound.Module, context.S.Sound.SamplingRate);
for slot = 1:8
    context.devices.hifi.loadSound(slot, zeros(1, 100));
end
end

function trial = assertRunsToNoInitiation(testCase, context)
sma = lum.buildTrialSM(context);
SendStateMachine(sma);
raw = RunStateMachine;
data = AddTrialEvents(struct(), raw);
trial = data.RawEvents.Trial{1};
verifyFalse(testCase, isnan(trial.States.NoInitiation(1)), 'An unpoked trial must end in NoInitiation');
verifyFalse(testCase, isnan(trial.States.ITI(1)));
verifyEqual(testCase, lum.scoreTrial(trial, context.spec, context.rig).Outcome, ...
            lum.Outcome.NoInitiation);
end

function index = stateIndex(sma, stateName)
index = find(strcmp(sma.StateNames, stateName));
end

function value = stateTimer(sma, stateName)
value = sma.StateTimers(stateIndex(sma, stateName));
end

function target = targetOf(sma, stateName, eventName)
% The state an input event leads to.
global BpodSystem %#ok<GVMIS>
eventIndex = find(strcmp(BpodSystem.StateMachineInfo.EventNames, eventName));
target = sma.StateNames{sma.InputMatrix(stateIndex(sma, stateName), eventIndex)};
end

function target = tupTargetOf(sma, stateName)
% The state a state timer elapsing leads to; '>exit' is one past the last state.
targetIndex = sma.StateTimerMatrix(stateIndex(sma, stateName));
if targetIndex > numel(sma.StateNames)
    target = '>exit';
else
    target = sma.StateNames{targetIndex};
end
end

function target = timerEndTargetOf(sma, stateName, timer)
% The state a global timer ending leads to.
target = sma.StateNames{sma.GlobalTimerEndMatrix(stateIndex(sma, stateName), timer)};
end

function target = conditionTargetOf(sma, stateName, condition)
% The state a condition being true leads to.
target = sma.StateNames{sma.ConditionMatrix(stateIndex(sma, stateName), condition)};
end
