function tests = settingsTest
% settingsTest exercises settings handling: lum.mergeSettings, lum.validateSettings,
% lum.timerBudget and the runtime tier's description.
%
% Settings files persist per subject and outlive the code that writes them, so the
% merge is what stops a new or renamed parameter breaking every existing animal's
% file, and validation is what stops a bad one reaching an animal.
tests = functiontests(localfunctions);
end

function testAnEmptySettingsFileGivesTheDefaults(testCase)
[S, added] = lum.mergeSettings(lum.defaultSettings, struct());
verifyEqual(testCase, S.Session.MaxTrials, 1000);
verifyNotEmpty(testCase, added);
end

function testMissingFieldsAreFilledIn(testCase)
loaded = lum.defaultSettings;
loaded.GUI = rmfield(loaded.GUI, 'ITI');
loaded.Sync = rmfield(loaded.Sync, 'WidthJitter');
[S, added] = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.GUI.ITI, 1);
verifyEqual(testCase, S.Sync.WidthJitter, 0.045);
verifyEqual(testCase, sort(added), {'GUI.ITI', 'Sync.WidthJitter'});
end

function testExistingValuesAreNeverOverwritten(testCase)
loaded = lum.defaultSettings;
loaded.GUI.RewardAmount = 7;
loaded.Task.GroupPLeft = [0.2 0.8];
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.GUI.RewardAmount, 7);
verifyEqual(testCase, S.Task.GroupPLeft, [0.2 0.8]);
end

function testUnknownFieldsFromAnOlderVersionAreKept(testCase)
loaded = lum.defaultSettings;
loaded.GUI.SomeRetiredParameter = 42;
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.GUI.SomeRetiredParameter, 42);
end

function testStructArraysAreTakenWhole(testCase)
% The cue rows are the operator's own design: merging into them element by element
% would quietly rewrite what they configured.
loaded = lum.defaultSettings;
loaded.Cue.Components = loaded.Cue.Components(2);
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, numel(S.Cue.Components), 1);
verifyEqual(testCase, S.Cue.Components(1).Type, 'Tone');
end

function testDeclarationsAlwaysComeFromTheDefaults(testCase)
% Labels, panels and name lists describe the code, so an old file's copies must lose.
loaded = lum.defaultSettings;
loaded.GUIMeta.RewardAmount.Label = 'an old label';
loaded.GUIPanels.Retired = {'Nothing'};
loaded.Sync.ModeNames = {'Fixed width', 'Random width', 'Task events'};
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.GUIMeta.RewardAmount.Label, 'Reward amount (uL)');
verifyFalse(testCase, isfield(S.GUIPanels, 'Retired'));
verifyEqual(testCase, S.Sync.ModeNames{2}, 'Jittered width');
end

function testALegacyScalarWaveformBecomesOneCarrierPerChannel(testCase)
loaded = rmfield(lum.defaultSettings, 'Light');
loaded.Stimulus.Waveform = struct('Frequency', 40, 'PulseWidth', 0.002, 'Voltage', 3);
[S, added] = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, [S.Light.Carrier.Channel], [1 2]);
verifyEqual(testCase, [S.Light.Carrier.Frequency], [40 40]);
verifyEqual(testCase, [S.Light.Carrier.PulseWidth], [0.002 0.002]);
verifyEqual(testCase, [S.Light.Carrier.Voltage], [3 3]);
verifyFalse(testCase, isfield(S.Stimulus, 'Waveform'));
verifyTrue(testCase, any(contains(added, 'Light.Carrier')), 'The operator has to be told');
end

function testALegacyPerChannelVoltageIsKeptPerChannel(testCase)
loaded = rmfield(lum.defaultSettings, 'Light');
loaded.Stimulus.Waveform = struct('Frequency', 20, 'PulseWidth', 0.005, 'Voltage', [2 7]);
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, [S.Light.Carrier.Voltage], [2 7]);
end

function testRenamedSettingsKeepTheOperatorsValues(testCase)
loaded = lum.defaultSettings;
loaded.GUI = rmfield(loaded.GUI, {'OptoOn', 'PortLightIntensity'});
loaded.GUI.StimulusOn = 0;
loaded.GUI.PortLEDIntensity = 40;
loaded.Sync = rmfield(loaded.Sync, {'WidthJitter', 'MeanWidth'});
loaded.Sync.Jitter = 0.01;
loaded.Sync.MeanDuration = 0.03;
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.GUI.OptoOn, 0);
verifyEqual(testCase, S.GUI.PortLightIntensity, 40);
verifyFalse(testCase, isfield(S.GUI, 'StimulusOn'), 'The old name must not linger');
verifyEqual(testCase, [S.Sync.MeanWidth S.Sync.WidthJitter], [0.03 0.01]);
end

function testALegacyCueListBecomesRows(testCase)
loaded = lum.defaultSettings;
loaded.Cue.Components = {'PortLight', 'Sound'};
loaded.Cue.Duration = 0.2;
S = lum.mergeSettings(lum.defaultSettings, loaded);
enabled = S.Cue.Components([S.Cue.Components.Enabled]);
verifyEqual(testCase, {enabled.Type}, {'CentreLight', 'Tone'});
verifyEqual(testCase, [enabled.ThroughStimulus], [true false], ...
            'The light was kept on through the hold; the tone never was');
verifyEqual(testCase, [enabled.Duration], [0 0]);
verifyFalse(testCase, isfield(S.Cue, 'Duration'));
verifyFalse(testCase, isfield(S.Cue.Components, 'Latency'));
end

function testAVersion03CueKeepsWhatItDidDuringTheStimulus(testCase)
% Cue rows timed from trial start become rows timed from the poke. The centre light
% follows its old hold setting; the tone and air never lasted into the stimulus.
for keptOn = [true false]
    loaded = lum.defaultSettings;
    loaded.Cue.Components = struct('Type', {'CentreLight', 'Tone', 'Air'}, ...
        'Enabled', {true, true, false}, 'Latency', {0, 0.1, 0}, 'Duration', {0.1, 0.2, 0.1});
    loaded.Cue.CentreLightDuringHold = keptOn;
    [S, added] = lum.mergeSettings(lum.defaultSettings, loaded);
    rows = S.Cue.Components;
    verifyEqual(testCase, fieldnames(rows), fieldnames(lum.defaultSettings().Cue.Components));
    verifyEqual(testCase, [rows.Enabled], [true true false]);
    verifyEqual(testCase, [rows.ThroughStimulus], [keptOn false false]);
    verifyEqual(testCase, [rows.Duration], [0 0 0]);
    verifyFalse(testCase, isfield(S.Cue, 'CentreLightDuringHold'));
    verifyTrue(testCase, any(contains(added, 'Cue.Components')), 'The operator has to be told');
end
loaded.Cue = rmfield(loaded.Cue, 'CentreLightDuringHold');
loaded.Cue.KeepCentrePortLit = false;   % The 0.1 name of the same setting
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyFalse(testCase, S.Cue.Components(1).ThroughStimulus);
end

function testThePreStimulusHoldIsRetired(testCase)
% The stimulus starts on the poke, so an old file's pre-stimulus hold must not linger.
loaded = lum.defaultSettings;
loaded.GUI.PreStimulusHold = 0.05;
[S, added] = lum.mergeSettings(lum.defaultSettings, loaded);
verifyFalse(testCase, isfield(S.GUI, 'PreStimulusHold'));
verifyEqual(testCase, S.Stimulus.Latency, 0, ...
            'The old runtime debounce is not carried into the stimulus latency');
verifyTrue(testCase, any(contains(added, 'GUI.PreStimulusHold (retired)')));
end

function testALegacyStimulusListBecomesRowsAndSideLights(testCase)
loaded = lum.defaultSettings;
loaded.Stimulus.Components = {'Opto', 'PortLight', 'Air'};
S = lum.mergeSettings(lum.defaultSettings, loaded);
air = S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, 'Air'));
verifyTrue(testCase, air.Enabled);
verifyTrue(testCase, S.Left.Light.Enabled && S.Right.Light.Enabled, ...
           'A target port light is now each side''s light');
end

function testTheHandWrittenStimulusTableIsRetired(testCase)
loaded = lum.defaultSettings;
loaded.Stimulus.Patterns = struct('Name', {'A', 'B'}, 'Mode', {'single', 'single'});
loaded.Task.StimulusNames = {'A', 'B'};
loaded.Task.LeftProbability = [1 0];
[S, added] = lum.mergeSettings(lum.defaultSettings, loaded);
verifyFalse(testCase, isfield(S.Stimulus, 'Patterns'));
verifyFalse(testCase, isfield(S.Task, 'StimulusNames'));
verifyTrue(testCase, any(contains(added, 'retired')));
end

function testRuntimeFieldsCoverEveryRuntimeParameter(testCase)
S = lum.defaultSettings;
fields = lum.gui.runtimeFields(S);
verifyEqual(testCase, sort({fields.Name}), sort(fieldnames(S.GUI))');
end

function testRuntimeFieldsFollowPanelOrderAndKnowTheirTab(testCase)
S = lum.defaultSettings;
fields = lum.gui.runtimeFields(S);
verifyEqual(testCase, fields(1).Name, 'RewardAmount');
verifyEqual(testCase, fields(1).Label, 'Reward amount (uL)');
verifyEqual(testCase, fields(1).Limits, [0 100]);
byName = containers.Map({fields.Name}, num2cell(1:numel(fields)));
verifyEqual(testCase, fields(byName('RewardAmount')).Tab, 'Trial');
verifyEqual(testCase, fields(byName('HoldStart')).Tab, 'Task');
verifyEqual(testCase, fields(byName('OptoOn')).Tab, 'Delivery');
verifyEqual(testCase, fields(byName('OptoOn')).Style, 'checkbox');
verifyEqual(testCase, fields(byName('PunishType')).Items, S.GUIMeta.PunishType.String);
end

function testAnUnpanelledParameterStillAppears(testCase)
S = lum.defaultSettings;
S.GUI.LooseParameter = 5;
fields = lum.gui.runtimeFields(S);
loose = fields(strcmp({fields.Name}, 'LooseParameter'));
verifyEqual(testCase, {loose.Panel, loose.Tab, loose.Label}, {'Parameters', 'Other', 'LooseParameter'});
end

function testAStalePanelEntryIsIgnored(testCase)
S = lum.defaultSettings;
S.GUIPanels.Reward{end+1} = 'RetiredParameter';
fields = lum.gui.runtimeFields(S);
verifyEqual(testCase, sort({fields.Name}), sort(fieldnames(S.GUI))');
end

function testTheSyncPulseCostsOneTimerFromTheBudget(testCase)
% The hold window always takes one; a pulsed sync mode takes one more.
S = lum.defaultSettings;
rig = struct('Limits', struct('GlobalTimers', 16), 'Available', struct('Sync', true));
[budget, reserved] = lum.timerBudget(S, rig);
verifyEqual(testCase, budget, 14);
verifyEqual(testCase, reserved.HoldWindow, 1);
S.Sync.Mode = lum.SyncMode.TaskEvents;
verifyEqual(testCase, lum.timerBudget(S, rig), 15, 'Task-event sync is driven by states');
S.Sync.Mode = lum.SyncMode.FixedWidth;
S.Session.UseSync = false;
verifyEqual(testCase, lum.timerBudget(S, rig), 15);
S.Session.UseSync = true;
rig.Available.Sync = false;   % Flex2 not configured as a digital output
verifyEqual(testCase, lum.timerBudget(S, rig), 15);
end

function testTheInitiationWindowBecomesTheHoldWindow(testCase)
loaded = lum.defaultSettings;
loaded.GUI = rmfield(loaded.GUI, 'HoldWindow');
loaded.GUI.InitiationWindow = 25;
loaded.Task = rmfield(loaded.Task, 'OnHoldBreak');
[S, added] = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.GUI.HoldWindow, 25);
verifyFalse(testCase, isfield(S.GUI, 'InitiationWindow'), 'The old name must not linger');
verifyEqual(testCase, S.Task.OnHoldBreak, 'Restart stimulus', 'Old files take the new default');
verifyTrue(testCase, any(contains(added, 'GUI.HoldWindow (was GUI.InitiationWindow)')));
end

function testASleepSectionIsFilledIntoOldFiles(testCase)
loaded = rmfield(lum.defaultSettings, 'Sleep');
loaded.Session = rmfield(loaded.Session, 'Type');
loaded.Sync.Barcode = rmfield(loaded.Sync.Barcode, 'SleepMarkerWidth');
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.Sleep, lum.defaultSettings().Sleep);
verifyEqual(testCase, S.Session.Type, 'Behaviour');
verifyEqual(testCase, S.Sync.Barcode.SleepMarkerWidth, 0.2);
end

function testOnlyTimedComponentsCostTimers(testCase)
S = lum.defaultSettings;
S.Stimulus.Duration = 1;
air = strcmp({S.Stimulus.Components.Type}, 'Air');
S.Stimulus.Components(air).Enabled = true;
S.Stimulus.Components(air).Onset = 0;
S.Stimulus.Components(air).Duration = 1;
verifyEqual(testCase, lum.stim.timerCost(S), 0, 'On for the whole window is free');
S.Stimulus.Components(air).Onset = 0.2;
verifyEqual(testCase, lum.stim.timerCost(S), 1);
S.Left.Light = struct('Enabled', true, 'Onset', 0.1, 'Duration', 0.2);
S.Right.Light = struct('Enabled', true, 'Onset', 0.3, 'Duration', 0.2);
verifyEqual(testCase, lum.stim.timerCost(S), 2, 'Only one side''s light runs on a trial');
end

function testTheDefaultsValidate(testCase)
[stimulusSet, budget] = lum.validateSettings(lum.defaultSettings, RigConfig);
verifyEqual(testCase, stimulusSet.nGroups, 2);
verifyGreaterThanOrEqual(testCase, budget, 1);
end

function testValidationRefusesWhatCannotRun(testCase)
rig = RigConfig;
cases = {@wideJitter, 'badSyncJitter'; @unknownBundle, 'badBundle'; ...
         @sameCableTwice, 'badCables'; @unnamedDrug, 'noDrugName'; ...
         @centreLightStimulus, 'cueClash'; @airCueAndStimulus, 'cueClash'; ...
         @cueToneAndStimulusTone, 'soundClash'; @stimulusAndSideTones, 'soundClash'; ...
         @shortHoldWindow, 'holdWindowTooShort'; @longLatency, 'holdWindowTooShort'; ...
         @negativeLatency, 'badLatency'; ...
         @unknownBreakMode, 'badHoldBreak'; @unknownSessionType, 'badSessionType'};
for i = 1:size(cases, 1)
    S = cases{i, 1}(lum.defaultSettings);
    verifyError(testCase, @() lum.validateSettings(S, rig), ...
                ['lum:validateSettings:' cases{i, 2}], cases{i, 2});
end
verifyError(testCase, @() lum.validateSettings(negativeCueTime(lum.defaultSettings), rig), ...
            'lum:cueTiming:badDuration', 'A negative time after the poke');
end

function testACueThatStopsAtThePokeLeavesItsLineToTheStimulus(testCase)
S = centreLightStimulus(withCue(lum.defaultSettings, {'CentreLight', 'Tone'}, 0));
row = strcmp({S.Stimulus.Components.Type}, 'Tone');
S.Stimulus.Components(row).Enabled = true;
verifyWarningFree(testCase, @() lum.validateSettings(S, RigConfig));
end

function testValidationCanReuseACompiledSet(testCase)
S = lum.defaultSettings;
rig = RigConfig;
compiled = lum.validateSettings(S, rig);
reused = lum.validateSettings(S, rig, compiled);
verifyEqual(testCase, reused, compiled);
end


function S = wideJitter(S)
S.Sync.WidthJitter = 1;
end

function S = unknownBundle(S)
S.Light.Bundle = 'nonsense';
end

function S = sameCableTwice(S)
S.Light.Bundle = '4-to-19';
S.Light.Cables = {'blue', 'blue'};
end

function S = unnamedDrug(S)
S.Meta.Drug.Enabled = true;
end

function S = centreLightStimulus(S)
% The default cue keeps the centre light on through the stimulus.
row = strcmp({S.Stimulus.Components.Type}, 'CentreLight');
S.Stimulus.Components(row).Enabled = true;
end

function S = airCueAndStimulus(S)
S = withCue(S, {'Air'}, 0.2);
row = strcmp({S.Stimulus.Components.Type}, 'Air');
S.Stimulus.Components(row).Enabled = true;
end

function S = cueToneAndStimulusTone(S)
S = withCue(S, {'Tone'});
row = strcmp({S.Stimulus.Components.Type}, 'Tone');
S.Stimulus.Components(row).Enabled = true;
end

function S = stimulusAndSideTones(S)
row = strcmp({S.Stimulus.Components.Type}, 'Tone');
S.Stimulus.Components(row).Enabled = true;
S.Left.Tone.Enabled = true;
end

function S = negativeCueTime(S)
S = withCue(S, {'CentreLight'}, -1);
end

function S = longLatency(S)
% A 1 s stimulus 0.6 s after the poke cannot be held inside a 1.5 s window.
S.Stimulus.Latency = 0.6;
S.GUI.HoldWindow = 1.5;
end

function S = negativeLatency(S)
S.Stimulus.Latency = -0.1;
end

function S = shortHoldWindow(S)
% A 1 s stimulus cannot be held inside a 1 s window.
S.GUI.HoldWindow = 1;
end

function S = unknownBreakMode(S)
S.Task.OnHoldBreak = 'Shrug';
end

function S = unknownSessionType(S)
S.Session.Type = 'Nap';
end
