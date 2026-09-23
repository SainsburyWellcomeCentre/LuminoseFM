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
verifyEqual(testCase, S.Sync.WidthJitter, 0.04);
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

function testATwoTo19FileGetsTheColouredCables(testCase)
% Before 0.7.2 the 2-to-19 bundle's cables were fixed and S.Light.Cables was read only
% for the 4-to-19 bundle, so a 2-to-19 file holds a 4-to-19 pair.
loaded = lum.defaultSettings;
loaded.Light.Cables = {'orange', 'blue'};
[S, added] = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.Light.Cables, {'blue', 'green'});
verifyTrue(testCase, any(contains(added, 'Light.Cables')), 'The operator has to be told');
loaded.Light.Cables = {'green', 'blue'};   % A valid choice is kept
verifyEqual(testCase, lum.mergeSettings(lum.defaultSettings, loaded).Light.Cables, {'green', 'blue'});
loaded.Light.Bundle = '4-to-19';
loaded.Light.Cables = {'black', 'orange'};   % Other bundles are left alone
verifyEqual(testCase, lum.mergeSettings(lum.defaultSettings, loaded).Light.Cables, {'black', 'orange'});
end

function testALegacyPerChannelVoltageIsKeptPerChannel(testCase)
loaded = rmfield(lum.defaultSettings, 'Light');
loaded.Stimulus.Waveform = struct('Frequency', 20, 'PulseWidth', 0.005, 'Voltage', [2 7]);
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, [S.Light.Carrier.Voltage], [2 7]);
end

function testTheHouseLightSwitchMovedOutOfTheRuntimeTier(testCase)
% 0.6.1 first had it as a runtime parameter, synced once a trial; now it is switched at once
% from the plots, and a settings file saved in between keeps its value.
loaded = lum.defaultSettings;
loaded.Session = rmfield(loaded.Session, 'HouseLight');
loaded.GUI.HouseLight = 1;
S = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.Session.HouseLight, 1);
verifyFalse(testCase, isfield(S.GUI, 'HouseLight'));
end

function testTheSubjectIsTheOneLaunched(testCase)
file = 'D:\luminoseData\LUMS0013\LuminoseFM\Session Data\LUMS0013_LuminoseFM_20260917_091854.mat';
verifyEqual(testCase, lum.launchSubject('LUMS0013', '', file), 'LUMS0013', 'The launch button''s record');
verifyEqual(testCase, lum.launchSubject('', 'LUMS0013', ''), 'LUMS0013', 'The selection''s');
verifyEqual(testCase, lum.launchSubject('', '', file), 'LUMS0013', ...
            'The launch manager left both empty: the data file''s folder');
verifyEqual(testCase, lum.launchSubject([], 0, 'C:\temp\x.mat'), '', 'No subject anywhere');
verifyEqual(testCase, lum.launchSubject(" FakeSubject ", '', ''), 'FakeSubject');
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

function testOldStimulusFamiliesBecomeTheNewOnes(testCase)
% 0.9.0 redesigned the families: each old one is converted, and P(left) survives only
% where the groups are still the same ones.
old = oldGenerator('pure', 'OnFraction', 0.75);
[S, added] = lum.mergeSettings(lum.defaultSettings, withGenerator(old, [1 0]));
g = S.Stimulus.Generator;
verifyEqual(testCase, {g.Family, g.PureChannels}, {'pure', 'A and B'});
verifyEqual(testCase, g.PureFractions, 0.75);
verifyEqual(testCase, S.Task.GroupPLeft, [1 0]);
verifyFalse(testCase, any(isfield(g, {'OnFraction', 'PureChannel', 'Motif', 'CycleBins'})), ...
            'The old fields are removed');
verifyTrue(testCase, any(contains(added, 'stimulus families redesigned')));

old = oldGenerator('sequence', 'Motif', [1 3 2 0], 'NumCycles', 2, 'DutyCycle', [0.5 0.5]);
S = lum.mergeSettings(lum.defaultSettings, withGenerator(old, [1 0]));
g = S.Stimulus.Generator;
verifyEqual(testCase, {g.Family, g.MotifLeftWords, g.MotifRightWords}, ...
            {'motif', 'AXB-AXB-', 'BXA-BXA-'}, 'The motif and its mirror, as words');
verifyEqual(testCase, g.MotifFill, 0.5);
verifyEqual(testCase, S.Task.GroupPLeft, [1 0]);

old = oldGenerator('occupancy', 'nGroups', 5);
S = lum.mergeSettings(lum.defaultSettings, withGenerator(old, linspace(1, 0, 5)));
verifyEqual(testCase, S.Stimulus.Generator.Family, 'mixture');
verifyEmpty(testCase, S.Task.GroupPLeft, 'Other groups: the family''s contingency');
verifyEqual(testCase, lum.validateSettings(S, RigConfig).nGroups, 6, 'And it runs');

old = oldGenerator('overlap_order', 'Continuous', true, 'CycleBins', 50, 'PureWidth', 15, ...
                   'ShortGuard', 5);
S = lum.mergeSettings(lum.defaultSettings, withGenerator(old, [1 0]));
g = S.Stimulus.Generator;
verifyEqual(testCase, {g.Family, g.OrderDesign}, {'order', 'guarded'});
verifyEqual(testCase, [g.OrderCycles g.OrderShortOverlap g.OrderLongOverlap], [2 0.1 0.3], ...
            'AbsTol', 1e-12);
verifyTrue(testCase, g.Continuous, 'A random phase every trial, as before');

old = oldGenerator('tiled_order');
S = lum.mergeSettings(lum.defaultSettings, withGenerator(old, [1 0]));
g = S.Stimulus.Generator;
verifyEqual(testCase, {g.Family, g.OrderDesign, g.OrderOverlap}, {'order', 'simple', 0});
end

function testTheCurrentGeneratorIsLeftAlone(testCase)
S = lum.defaultSettings;
S.Stimulus.Generator = lum.pattern.familyDefaults(S.Stimulus.Generator, 'count');
S.Task.GroupPLeft = [1 1 1 0 0 0];
[merged, added] = lum.mergeSettings(lum.defaultSettings, S);
verifyEqual(testCase, merged.Stimulus.Generator, S.Stimulus.Generator);
verifyEqual(testCase, merged.Task.GroupPLeft, [1 1 1 0 0 0]);
verifyFalse(testCase, any(contains(added, 'Generator')));
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

function testTheSyncPulseCostsNoTimerInAnyMode(testCase)
% The hold window always takes one; the sync line takes none, in any mode, because every
% edge it carries is a state's output action (D4). Nor does the house light: PulsePal holds
% it (D15).
S = lum.defaultSettings;
rig = struct('Limits', struct('GlobalTimers', 16), 'Available', struct('Sync', true));
[budget, reserved] = lum.timerBudget(S, rig);
verifyEqual(testCase, budget, 15);
verifyEqual(testCase, reserved.HoldWindow, 1);
verifyFalse(testCase, isfield(reserved, 'HouseLight'));
verifyEqual(testCase, reserved.Sync, 0);
for mode = [lum.SyncMode.FixedWidth lum.SyncMode.JitteredWidth lum.SyncMode.TaskEvents]
    S.Sync.Mode = mode;
    verifyEqual(testCase, lum.timerBudget(S, rig), 15, ...
                'Every sync mode is driven by states');
end
S.Session.UseSync = false;
verifyEqual(testCase, lum.timerBudget(S, rig), 15);
S.Session.UseSync = true;
rig.Available.Sync = false;   % Flex2 not configured as a digital output
verifyEqual(testCase, lum.timerBudget(S, rig), 15);
end

function testATaskVariantAndAContingencyReversalAreRecorded(testCase)
% Both are pre-session settings, stored once with the session, and validated.
S = lum.defaultSettings;
rig = RigConfig;
verifyTrue(testCase, ismember(S.Task.Variant, lum.experimentChoices().TaskVariants));
verifyFalse(testCase, S.Task.ReverseContingency);
for variant = lum.experimentChoices().TaskVariants
    S.Task.Variant = variant{1};
    verifyWarningFree(testCase, @() lum.validateSettings(S, rig));
end
S.Task.Variant = 'Something else entirely';
verifyError(testCase, @() lum.validateSettings(S, rig), 'lum:validateSettings:badTaskVariant');
end

function testASettingsFileFromBeforeTheTaskVariantGetsOne(testCase)
loaded = lum.defaultSettings;
loaded.Task = rmfield(loaded.Task, {'Variant', 'ReverseContingency'});
[S, added] = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.Task.Variant, 'Familiar/Novel');
verifyFalse(testCase, S.Task.ReverseContingency);
verifyTrue(testCase, any(strcmp(added, 'Task.Variant')));
verifyTrue(testCase, any(strcmp(added, 'Task.ReverseContingency')));
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

function testTestPulsesAreFilledIntoOldSleepSettings(testCase)
% A 0.4 settings file has a sleep section with no test pulses; they come in switched off,
% and the operator's own sleep settings stay.
loaded = lum.defaultSettings;
loaded.Sleep = rmfield(loaded.Sleep, 'TestPulses');
loaded.Sleep.DurationMinutes = 90;
[S, added] = lum.mergeSettings(lum.defaultSettings, loaded);
verifyEqual(testCase, S.Sleep.TestPulses, lum.defaultSettings().Sleep.TestPulses);
verifyFalse(testCase, S.Sleep.TestPulses.Enabled);
verifyEqual(testCase, S.Sleep.DurationMinutes, 90);
verifyTrue(testCase, any(strcmp(added, 'Sleep.TestPulses')));
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


function g = oldGenerator(family, varargin)
% A generator as a settings file from before 0.9.0 held it.
g = struct('Family', family, 'nGroups', 2, 'Continuous', false, 'BinDuration', 0.01, ...
           'Seed', 1, 'NewSeedEachSession', true, 'PureChannel', 'A', 'OnFraction', 1, ...
           'Motif', [1 2], 'DutyCycle', [1 1], 'SlotWeights', [], 'NumCycles', 2, ...
           'BPhase', [], 'AOnFraction', 0.5, 'BOnFraction', 0.5, 'Overlap', 0.2, 'Beta', NaN, ...
           'Layout', 'blocks', 'BlockOrder', [1 3 2 0], 'CycleBins', 10, 'PureWidth', 2, ...
           'ShortGuard', 1, 'Phase', NaN, 'Pulses', zeros(0, 4), 'AOffset', 0, 'BOffset', 0, ...
           'OffsetMode', 'circular');
for i = 1:2:numel(varargin)
    g.(varargin{i}) = varargin{i + 1};
end
end

function loaded = withGenerator(generator, pLeft)
% Settings holding an old generator and the P(left) typed for it.
loaded = lum.defaultSettings;
loaded.Stimulus.Generator = generator;
loaded.Task.GroupPLeft = pLeft;
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
