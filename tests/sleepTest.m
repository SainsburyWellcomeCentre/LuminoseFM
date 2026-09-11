function tests = sleepTest
% sleepTest exercises the parts of a sleep session: lum.sleep.*
%
% The pulse schedule, the block size and validation are pure. The block state machine
% is assembled and run under Bpod('EMU') on a stand-in channel, because the emulator has
% no Flex I/O, and again with no channel at all, which is what an emulated session gets.
tests = functiontests(localfunctions);
end

function testFixedWidthPulsesAreAllTheSameWidth(testCase)
sync = sleepSync('Mode', lum.SyncMode.FixedWidth, 'FixedWidth', 0.02, 'Interval', 0.5);
[widths, gaps] = lum.sleep.pulseSchedule(sync, 40);
verifyEqual(testCase, widths, repmat(0.02, 1, 40), 'AbsTol', 1e-12);
verifyEqual(testCase, widths + gaps, repmat(0.5, 1, 40), 'AbsTol', 1e-9);
end

function testJitteredPulsesSpreadWithinTheirJitter(testCase)
sync = sleepSync('MeanWidth', 0.055, 'WidthJitter', 0.045, 'Interval', 1, 'IntervalJitter', 0.2);
rng(21);
[widths, gaps] = lum.sleep.pulseSchedule(sync, 2000);
verifyGreaterThanOrEqual(testCase, min(widths), 0.010 - 1e-12);
verifyLessThanOrEqual(testCase, max(widths), 0.100 + 1e-12);
verifyGreaterThan(testCase, numel(unique(widths)), 300, 'Jittered widths must identify pulses');
intervals = widths + gaps;
verifyGreaterThanOrEqual(testCase, min(intervals), 0.8 - 1e-9);
verifyLessThanOrEqual(testCase, max(intervals), 1.2 + 1e-9);
verifyEqual(testCase, mean(intervals), 1, 'AbsTol', 0.01);
verifyEqual(testCase, widths, round(widths * 1e4) / 1e4, 'AbsTol', 1e-12, 'Quantised to the cycle');
end

function testAnUnknownModeIsRejected(testCase)
sync = sleepSync('Mode', lum.SyncMode.TaskEvents);
verifyError(testCase, @() lum.sleep.pulseSchedule(sync, 3), 'lum:sleep:pulseSchedule:badMode');
end

function testABlockIsAboutTenSecondsAndFitsTheStateMachine(testCase)
verifyEqual(testCase, lum.sleep.pulsesPerBlock(sleepSync('Interval', 1), 256, 3600), 10);
verifyEqual(testCase, lum.sleep.pulsesPerBlock(sleepSync('Interval', 0.01), 256, 3600), 128, ...
            'Two states per pulse, at most MaxStates');
verifyEqual(testCase, lum.sleep.pulsesPerBlock(sleepSync('Interval', 1), 256, 2.5), 2);
verifyEqual(testCase, lum.sleep.pulsesPerBlock(sleepSync('Interval', 30), 256, 3600), 1, ...
            'A block is never empty');
end

function testTheBlockStateMachineDrivesTheLine(testCase)
global BpodSystem %#ok<GVMIS>
ensureEmulator();
widths = [0.004 0.006 0.005];
gaps = [0.010 0.012 0.011];
sma = lum.sleep.blockStateMachine(widths, gaps, 'BNC2');
verifyEqual(testCase, sma.StateNames, {'Pulse001', 'Gap001', 'Pulse002', 'Gap002', 'Pulse003', 'Gap003'});
verifyEqual(testCase, sma.StateTimers, reshape([widths; gaps], 1, []), 'AbsTol', 1e-9);
column = find(strcmp(BpodSystem.StateMachineInfo.OutputChannelNames, 'BNC2'));
verifyEqual(testCase, sma.OutputMatrix(:, column)', [1 0 1 0 1 0]);

trial = runOnce(sma);
for name = {'Pulse001', 'Pulse002', 'Pulse003', 'Gap003'}
    verifyFalse(testCase, isnan(trial.States.(name{1})(1)), sprintf('%s must run', name{1}));
end
end

function testWithoutASyncLineTheBlockKeepsItsTiming(testCase)
ensureEmulator();
sma = lum.sleep.blockStateMachine([0.004 0.004], [0.01 0.01], '');
verifyEqual(testCase, numel(sma.StateNames), 4);
verifyFalse(testCase, any(sma.OutputMatrix(:)), 'No line, no output');
trial = runOnce(sma);
verifyFalse(testCase, isnan(trial.States.Gap002(1)));
end

function testTheDefaultsValidate(testCase)
S = lum.defaultSettings;
rig = RigConfig;
rig.Available.Sync = true;
verifyEmpty(testCase, lum.sleep.validate(S, rig));
rig.Available.Sync = false;
verifySubstring(testCase, strjoin(lum.sleep.validate(S, rig)), 'no sync pulses');
end

function testValidationRefusesWhatCannotRun(testCase)
rig = RigConfig;
cases = {@(S) setSleep(S, 'DurationMinutes', 0), 'badDuration'; ...
         @(S) setSync(S, 'Mode', lum.SyncMode.TaskEvents), 'badMode'; ...
         @(S) setSync(S, 'WidthJitter', 0.06), 'badJitter'; ...
         @(S) setSync(S, 'Interval', 0.1), 'pulsesOverlap'; ...
         @(S) setSync(S, 'Interval', 0.2, 'IntervalJitter', 0.1), 'pulsesOverlap'; ...
         @(S) setSync(setSleep(S, 'DurationMinutes', 1440), 'Interval', 0.11), 'tooManyPulses'; ...
         @unnamedDrug, 'noDrugName'};
for i = 1:size(cases, 1)
    S = cases{i, 1}(lum.defaultSettings);
    verifyError(testCase, @() lum.sleep.validate(S, rig), ['lum:sleep:validate:' cases{i, 2}], ...
                cases{i, 2});
end
end


function sync = sleepSync(varargin)
sync = lum.defaultSettings().Sleep.Sync;
for i = 1:2:numel(varargin)
    sync.(varargin{i}) = varargin{i + 1};
end
end

function S = setSleep(S, varargin)
for i = 1:2:numel(varargin)
    S.Sleep.(varargin{i}) = varargin{i + 1};
end
end

function S = setSync(S, varargin)
for i = 1:2:numel(varargin)
    S.Sleep.Sync.(varargin{i}) = varargin{i + 1};
end
end

function S = unnamedDrug(S)
S.Meta.Drug.Enabled = true;
end

function trial = runOnce(sma)
SendStateMachine(sma);
raw = RunStateMachine;
data = AddTrialEvents(struct(), raw);
trial = data.RawEvents.Trial{1};
end
