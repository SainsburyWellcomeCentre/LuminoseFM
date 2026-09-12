function tests = sleepTest
% sleepTest exercises the parts of a sleep session: lum.sleep.*
%
% The sync pulse schedule, the test-pulse plan, the block cutter and validation are
% pure. The block state machine is assembled and run under Bpod('EMU') on channels A and
% B, with no sync channel, which is what an emulated session gets: the emulator has no
% Flex I/O.
tests = functiontests(localfunctions);
end

%% Sync pulses ----------------------------------------------------------------------

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

function testSyncPulsesAreLaidOutOverTheWholeSession(testCase)
sync = sleepSync('Mode', lum.SyncMode.FixedWidth, 'FixedWidth', 0.02, 'Interval', 0.5);
pulses = lum.sleep.syncPulseTimes(sync, 10);
verifyEqual(testCase, pulses(:, 1)', 0:5000:95000, 'One every 0.5 s, in cycles, all before the end');
verifyEqual(testCase, unique(pulses(:, 2)), 200);
end

%% Test-pulse plan ------------------------------------------------------------------

function testTheDefaultScheduleIsFourHoursOfPairedProbes(testCase)
plan = lum.sleep.testPulsePlan(enabledDesign());
verifyEqual(testCase, plan.Duration, 4 * 3600, 'AbsTol', 1e-9);
verifyEqual(testCase, numel(plan.Steps), 1);
verifyEqual(testCase, plan.Steps(1).Kind, 'Probe');
verifyEqual(testCase, plan.Steps(1).nEpochs, 7200, 'One epoch every 2 s');
verifyEqual(testCase, size(plan.Segments, 1), 7200 * 4, 'A pair of pulses on A and on B');
first = plan.Segments(plan.Segments(:, 5) == 1, :);
verifyEqual(testCase, first(:, 1)', [0 0 500 500], 'Pulses at 0 and 50 ms, in cycles');
verifyEqual(testCase, first(:, 2)', [100 100 100 100], '10 ms wide');
verifyEqual(testCase, first(:, 3)', [1 2 1 2]);
second = plan.Segments(plan.Segments(:, 5) == 2, 1);
verifyEqual(testCase, second(1), 20000, 'The next epoch 2 s later');
verifyEqual(testCase, [plan.Steps(1).Carrier.Frequency], [0 0], 'Constant light: the gate is the pulse');
verifyEqual(testCase, [plan.Steps(1).Carrier.Voltage], [5 5]);
end

function testWithTestPulsesOffThereIsNoLight(testCase)
plan = lum.sleep.testPulsePlan(lum.defaultSettings().Sleep.TestPulses);
verifyEmpty(testCase, plan.Steps);
verifyEmpty(testCase, plan.Segments);
verifyEqual(testCase, plan.Duration, 0);
end

function testASingleProbeCanAlternateChannels(testCase)
design = enabledDesign();
design.Probe.Mode = 'Single';
design.Schedule = struct('Kind', 'Probe', 'Channels', 'Alternate A and B', 'Minutes', 1);
plan = lum.sleep.testPulsePlan(design);
verifyEqual(testCase, size(plan.Segments, 1), 30);
verifyEqual(testCase, plan.Segments(1:4, 3)', [1 2 1 2], 'A, then B, then A');
end

function testAThetaBurstIsGatedBurstsThatPulsePalFills(testCase)
design = enabledDesign();
design.PlasticityTrains = true;
design.Schedule = struct('Kind', {'Probe', 'Theta burst', 'Probe'}, ...
                         'Channels', {'A and B', 'A', 'A and B'}, 'Minutes', {1, 0, 1});
plan = lum.sleep.testPulsePlan(design);
step = plan.Steps(2);
verifyEqual(testCase, step.Start, 60, 'AbsTol', 1e-9);
verifyEqual(testCase, step.nEpochs, 5);
verifyEqual(testCase, step.Duration, 100, 'AbsTol', 1e-9, 'Five trains, 20 s apart');
verifyEqual(testCase, plan.Steps(3).Start, 160, 'AbsTol', 1e-9);
verifyEqual(testCase, [step.Carrier.Frequency], [100 100]);
verifyEqual(testCase, [step.Carrier.PulseWidth], [0.005 0.005], 'AbsTol', 1e-12);

shape = lum.sleep.epochShape(plan, 2, 1);
verifyEqual(testCase, size(shape.Gates, 1), 10, 'Ten bursts a train');
verifyEqual(testCase, diff(shape.Gates(1:2, 1)), 0.25, 'AbsTol', 1e-9, 'Bursts at 4 Hz');
verifyEqual(testCase, shape.Gates(1, 2), 0.0375, 'AbsTol', 1e-9, ...
            'From the first pulse to half way through the gap after the fourth');
verifyEqual(testCase, size(shape.Pulses, 1), 40);
verifyEqual(testCase, shape.Pulses(1:4, 1)', [0 0.01 0.02 0.03], 'AbsTol', 1e-9, '100 Hz');
verifyTrue(testCase, all(shape.Pulses(1:4, 1) + shape.Pulses(1:4, 2) <= shape.Gates(1, 2) + 1e-9), ...
           'Every pulse inside its gate');
verifyEqual(testCase, unique(shape.Gates(:, 3))', 1, 'On A only');
end

function testTheScheduleRefusesWhatCannotBeSent(testCase)
cases = {@(d) setProbe(d, 'InterPulseInterval', 0.0105), 'pairOverlaps'; ...
         @(d) setProbe(d, 'InterEpochInterval', 0.06), 'badEpochInterval'; ...
         @(d) setProbe(d, 'Mode', 'Triple'), 'badProbeMode'; ...
         @(d) withSchedule(d, struct('Kind', {}, 'Channels', {}, 'Minutes', {})), 'emptySchedule'; ...
         @(d) withSchedule(d, struct('Kind', 'Gamma', 'Channels', 'A', 'Minutes', 1)), 'unknownKind'; ...
         @(d) withSchedule(d, struct('Kind', 'Probe', 'Channels', 'C', 'Minutes', 1)), 'badChannels'; ...
         @(d) withSchedule(d, struct('Kind', 'Rest', 'Channels', 'A', 'Minutes', 10)), 'noLight'; ...
         @(d) withSchedule(d, struct('Kind', 'Theta burst', 'Channels', 'A', 'Minutes', 0)), 'trainsOff'; ...
         @(d) withSchedule(d, struct('Kind', 'Probe', 'Channels', 'A', 'Minutes', 0.01)), 'stepTooShort'; ...
         @(d) withSchedule(d, struct('Kind', 'Probe', 'Channels', 'A', 'Minutes', 1500)), 'tooLong'; ...
         @(d) setTrain(d, 1, 'PulseWidth', 0.01), 'badTrainPulse'; ...
         @(d) setTrain(d, 1, 'BurstFrequency', 30), 'burstsOverlap'; ...
         @(d) setTrain(d, 1, 'TrainInterval', 2), 'trainTooLong'; ...
         @(d) setTrain(d, 2, 'Name', 'Theta burst'), 'badTrainName'; ...
         @(d) setField(d, 'Voltage', [5 12]), 'badVoltage'};
for i = 1:size(cases, 1)
    design = cases{i, 1}(enabledDesign());
    verifyError(testCase, @() lum.sleep.testPulsePlan(design), ...
                ['lum:sleep:testPulsePlan:' cases{i, 2}], cases{i, 2});
end
end

function testAnUnusedTrainDoesNotStopAProbeSession(testCase)
design = enabledDesign();
design.Trains(1).PulseWidth = 0.02;   % Impossible at 100 Hz, but trains are off
verifyEqual(testCase, lum.sleep.testPulsePlan(design).Steps(1).nEpochs, 7200);
end

%% Blocks ---------------------------------------------------------------------------

function testBlocksCoverTheSessionWithoutCuttingAPulseOrAnEpoch(testCase)
design = enabledDesign();
design.PlasticityTrains = true;
design.Schedule = struct('Kind', {'Probe', 'Theta burst', 'Rest', 'High frequency', 'Probe'}, ...
                         'Channels', {'A and B', 'A', 'A', 'Alternate A and B', 'B'}, ...
                         'Minutes', {2, 0, 0.5, 0, 2});
plan = lum.sleep.testPulsePlan(design);
rng(3);
syncPulses = lum.sleep.syncPulseTimes(sleepSync('Interval', 1, 'IntervalJitter', 0.3), plan.Duration);
for maxStates = [256 40]
    blocks = cutWholeSession(plan, syncPulses, plan.DurationCycles, maxStates);
    label = sprintf(' (%d states)', maxStates);
    verifyEqual(testCase, blocks(1).Start, 0);
    verifyEqual(testCase, [blocks(2:end).Start], [blocks(1:end-1).End], ['Blocks follow on' label]);
    verifyGreaterThanOrEqual(testCase, blocks(end).End, plan.DurationCycles);
    verifyEqual(testCase, sort([blocks.SyncIndices]), 1:size(syncPulses, 1), ['Every sync pulse, once' label]);
    verifyEqual(testCase, sort([blocks.SegmentIndices]), 1:size(plan.Segments, 1), ['Every gate, once' label]);

    blockOfSegment = zeros(1, size(plan.Segments, 1));
    for b = 1:numel(blocks)
        block = blocks(b);
        blockOfSegment(block.SegmentIndices) = b;
        verifyLessThanOrEqual(testCase, numel(block.Durations), maxStates - 2);
        verifyEqual(testCase, sum(round(block.Durations / 1e-4)), block.End - block.Start, ...
                    'The states last the block');
        on = syncPulses(block.SyncIndices, 1);
        verifyTrue(testCase, all(on >= block.Start & on + syncPulses(block.SyncIndices, 2) <= block.End), ...
                   'No sync pulse crosses a block boundary');
        segments = plan.Segments(block.SegmentIndices, :);
        verifyTrue(testCase, all(segments(:, 1) >= block.Start & sum(segments(:, 1:2), 2) <= block.End), ...
                   'No gate crosses a block boundary');
        verifyLessThanOrEqual(testCase, numel(unique(segments(:, 4))), 1, ...
                              'One step per block, so the carrier changes between blocks');
        for k = 1:numel(block.SegmentIndices)
            verifyTrue(testCase, block.Levels(block.SegmentStates(k), 1 + segments(k, 3)), ...
                       'The gate''s line is high in the state it starts in');
        end
        for k = 1:numel(block.SyncIndices)
            verifyTrue(testCase, block.Levels(block.SyncStates(k), 1));
        end
    end
    for e = 1:size(plan.Epochs, 1)
        rows = plan.Epochs(e, 3):plan.Epochs(e, 4);
        verifyEqual(testCase, numel(unique(blockOfSegment(rows))), 1, ...
                    sprintf('Epoch %d is split across blocks%s', e, label));
    end
end
end

function testWithoutTestPulsesBlocksCarryTheSyncLineAlone(testCase)
plan = lum.sleep.testPulsePlan(lum.defaultSettings().Sleep.TestPulses);
syncPulses = lum.sleep.syncPulseTimes(sleepSync('Interval', 0.5), 60);
blocks = cutWholeSession(plan, syncPulses, 60e4, 256);
verifyEqual(testCase, numel(blocks), 6, 'About 10 s each');
verifyEqual(testCase, sort([blocks.SyncIndices]), 1:size(syncPulses, 1));
verifyFalse(testCase, any(arrayfun(@(b) any(any(b.Levels(:, 2:3))), blocks)), 'No light');
verifyEqual(testCase, [blocks.Step], zeros(1, 6));
end

function testTheBlockStateMachineDrivesChannelsAAndB(testCase)
global BpodSystem %#ok<GVMIS>
ensureEmulator();
design = enabledDesign();
design.Probe.InterEpochInterval = 0.3;
design.Schedule = struct('Kind', 'Probe', 'Channels', 'A and B', 'Minutes', 0.02);
plan = lum.sleep.testPulsePlan(design);
syncPulses = lum.sleep.syncPulseTimes(sleepSync('Mode', lum.SyncMode.FixedWidth, 'FixedWidth', 0.02, ...
                                                'Interval', 0.25), plan.Duration);
cursor = struct('Time', 0, 'End', plan.DurationCycles, 'NextSync', 1, 'NextEpoch', 1);
[block, cursor] = lum.sleep.nextBlock(plan, syncPulses, cursor, BpodSystem.StateMachineInfo.MaxStates);
verifyEqual(testCase, cursor.Time, plan.DurationCycles, 'A 1.2 s session is one block');

sma = lum.sleep.blockStateMachine(block, {'', 'BNC1', 'BNC2'});
verifyEqual(testCase, sma.StateNames, block.StateNames);
names = BpodSystem.StateMachineInfo.OutputChannelNames;
verifyEqual(testCase, sma.OutputMatrix(:, strcmp(names, 'BNC1'))', double(block.Levels(:, 2))');
verifyEqual(testCase, sma.OutputMatrix(:, strcmp(names, 'BNC2'))', double(block.Levels(:, 3))');

trial = runOnce(sma);
for k = 1:numel(block.SegmentIndices)
    name = block.StateNames{block.SegmentStates(k)};
    verifyFalse(testCase, isnan(trial.States.(name)(1)), sprintf('%s must run', name));
end
end

function testWithoutLinesTheBlockKeepsItsTiming(testCase)
ensureEmulator();
plan = lum.sleep.testPulsePlan(lum.defaultSettings().Sleep.TestPulses);
syncPulses = lum.sleep.syncPulseTimes(sleepSync('Mode', lum.SyncMode.FixedWidth, 'FixedWidth', 0.004, ...
                                                'Interval', 0.014), 0.028);
cursor = struct('Time', 0, 'End', 280, 'NextSync', 1, 'NextEpoch', 1);
block = lum.sleep.nextBlock(plan, syncPulses, cursor, 256);
sma = lum.sleep.blockStateMachine(block, {'', '', ''});
verifyEqual(testCase, numel(sma.StateNames), 4, 'Two pulses, two gaps');
verifyFalse(testCase, any(sma.OutputMatrix(:)), 'No line, no output');
trial = runOnce(sma);
verifyFalse(testCase, isnan(trial.States.Level004(1)));
end

%% Validation -----------------------------------------------------------------------

function testTheDefaultsValidate(testCase)
S = lum.defaultSettings;
rig = RigConfig;
rig.Available.Sync = true;
verifyEmpty(testCase, lum.sleep.validate(S, rig));
rig.Available.Sync = false;
verifySubstring(testCase, strjoin(lum.sleep.validate(S, rig)), 'no sync pulses');
S.Sleep.TestPulses.Enabled = true;
S.Sleep.DurationMinutes = 0;   % Not used: the schedule decides
verifySubstring(testCase, strjoin(lum.sleep.validate(S, rig)), 'lasts as long as their schedule');
end

function testValidationRefusesWhatCannotRun(testCase)
rig = RigConfig;
cases = {@(S) setSleep(S, 'DurationMinutes', 0), 'badDuration'; ...
         @(S) setSync(S, 'Mode', lum.SyncMode.TaskEvents), 'badMode'; ...
         @(S) setSync(S, 'WidthJitter', 0.06), 'badJitter'; ...
         @(S) setSync(S, 'Interval', 0.1), 'pulsesOverlap'; ...
         @(S) setSync(S, 'Interval', 0.2, 'IntervalJitter', 0.1), 'pulsesOverlap'; ...
         @(S) setSync(setSleep(S, 'DurationMinutes', 1440), 'Interval', 0.11), 'tooManyPulses'; ...
         @unnamedDrug, 'noDrugName'; ...
         @crowdedProbes, 'epochsCrowdSync'; ...
         @busyTrain, 'epochTooBusy'};
for i = 1:size(cases, 1)
    S = cases{i, 1}(lum.defaultSettings);
    verifyError(testCase, @() lum.sleep.validate(S, rig), ['lum:sleep:validate:' cases{i, 2}], ...
                cases{i, 2});
end
end

function testTestPulsesAreDescribedStepByStep(testCase)
design = enabledDesign();
design.PlasticityTrains = true;
design.Schedule = struct('Kind', {'Probe', 'Theta burst'}, 'Channels', {'A and B', 'A'}, 'Minutes', {30, 0});
lines = lum.sleep.describeTestPulses(design);
verifySubstring(testCase, lines{1}, 'paired 10 ms pulses, 50 ms apart');
verifySubstring(testCase, lines{2}, '2 step(s)');
verifySubstring(testCase, lines{3}, '900 epoch(s)');
verifySubstring(testCase, lines{4}, 'Theta burst: 5 train(s) of 10 bursts of 4 pulse(s) (5 ms) at 100 Hz');
end


%% Helpers --------------------------------------------------------------------------

function blocks = cutWholeSession(plan, syncPulses, endCycles, maxStates)
cursor = struct('Time', 0, 'End', endCycles, 'NextSync', 1, 'NextEpoch', 1);
blocks = [];
while cursor.Time < cursor.End
    [block, cursor] = lum.sleep.nextBlock(plan, syncPulses, cursor, maxStates);
    blocks = [blocks block]; %#ok<AGROW>
end
end

function design = enabledDesign()
design = lum.defaultSettings().Sleep.TestPulses;
design.Enabled = true;
end

function sync = sleepSync(varargin)
sync = lum.defaultSettings().Sleep.Sync;
for i = 1:2:numel(varargin)
    sync.(varargin{i}) = varargin{i + 1};
end
end

function design = setProbe(design, name, value)
design.Probe.(name) = value;
end

function design = setTrain(design, k, name, value)
design.PlasticityTrains = true;
design.Trains(k).(name) = value;
end

function design = setField(design, name, value)
design.(name) = value;
end

function design = withSchedule(design, schedule)
design.Schedule = schedule;
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

function S = crowdedProbes(S)
% 40 ms of darkness after each 60 ms epoch, against sync pulses of up to 100 ms.
S.Sleep.TestPulses.Enabled = true;
S.Sleep.TestPulses.Probe.InterEpochInterval = 0.1;
S.Sleep.TestPulses.Schedule.Minutes = 10;
end

function S = busyTrain(S)
% 300 gates in one epoch, more than one state machine holds.
S.Sleep.TestPulses.Enabled = true;
S.Sleep.TestPulses.PlasticityTrains = true;
train = S.Sleep.TestPulses.Trains(1);
train.PulsesPerBurst = 1;
train.BurstFrequency = 50;
train.BurstsPerTrain = 150;
train.TrainInterval = 10;
S.Sleep.TestPulses.Trains(1) = train;
S.Sleep.TestPulses.Schedule = struct('Kind', 'Theta burst', 'Channels', 'A and B', 'Minutes', 0);
end

function trial = runOnce(sma)
SendStateMachine(sma);
raw = RunStateMachine;
data = AddTrialEvents(struct(), raw);
trial = data.RawEvents.Trial{1};
end
