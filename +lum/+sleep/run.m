function run(S, rig, subject, headless)
% lum.sleep.run runs a home-cage sleep session: a sleep barcode, sync pulses and test pulses.
%
% The sleep half of LuminoseFM (D11), called by it once the operator has chosen a
% sleep session. There is no task: the session puts a timeline on the acquisition
% devices recording the animal's sleep, so it sends the session barcode with sleep
% markers (lum.sync.barcode, 'Sleep') and then a sync pulse every S.Sleep.Sync.Interval
% seconds on Flex2. With test pulses on (D13) it also sends light on channels A and B
% through PulsePal, following the schedule in S.Sleep.TestPulses, and the recording
% lasts as long as that schedule; otherwise it lasts S.Sleep.DurationMinutes. It ends
% early if the operator stops it from the console, or if PulsePal stops answering.
%
%   setup      sleep setup dialog, validation, the whole timeline laid out, devices
%              (PulsePal refused as for behaviour), plots, barcode
%   blocks     the timeline in state machines of about 10 s (lum.sleep.nextBlock), each
%              cut where every line is low and no epoch is split; PulsePal is given each
%              step's carrier between blocks; onsets read back from the states
%   teardown   the pulse and light records, the analog stream, the final file, devices
%              released
%
% Blocks run on blocking RunStateMachine calls, on the rig as in the emulator: with
% nothing to prepare between blocks there is no use for BpodTrialManager, and every
% onset is the state machine's own timestamp, so the upload between blocks only
% lengthens one interval by a few milliseconds and is recorded. Every lum.* object is
% released before this returns, so LuminoseFM can call RunProtocol('Stop').
%
% Data (Data.Session.Type is 'Sleep'):
%   Data.Session        Type, Subject, Settings, Rig, Emulated, DevicesAvailable,
%                       SyncSent, StartTime, EndTime, Barcode (Value, Hex, Kind, Sent,
%                       Params), TestPulses (Enabled, Steps, Duration, Completed,
%                       StoppedReason), ProtocolVersion, DeviceLog (PulsePal, FlexIO)
%   Data.SyncPulses     .Onset (s, state machine clock), .Width (s) and .Block, one value
%                       per pulse sent
%   Data.LightSegments  With test pulses: .Onset (s, state machine clock), .Duration (s),
%                       .Channel (1 A, 2 B), .Step, .Epoch and .Block, one value per gate
%                       of light sent (lum.sleep.epochShape gives the pulses in it)
%   Data.RawEvents      Bpod's own record, one "trial" per block
%
% Arguments:
%   S         Settings struct (merged)
%   rig       Channel map from RigConfig
%   subject   Subject chosen in the launch manager
%   headless  true to skip the setup dialog and use S as it is (tests)
%
% See also: LuminoseFM, lum.gui.SleepSetupDialog, lum.sleep.Plots, lum.sleep.validate,
%           lum.sleep.testPulsePlan, lum.sleep.nextBlock

global BpodSystem %#ok<GVMIS> % Bpod's own session object

%% Settings
if ~headless
    [S, accepted] = lum.gui.SleepSetupDialog(S, rig, 'Subject', subject);
    if ~accepted
        fprintf('LuminoseFM: sleep session setup cancelled.\n');
        BpodSystem.Status.BeingUsed = 0;
        return
    end
    SaveProtocolSettings(S);
end
S.Session.Type = 'Sleep';
notes = lum.sleep.validate(S, rig);
for i = 1:numel(notes)
    fprintf('LuminoseFM: note: %s\n', notes{i});
end

%% Timeline
% Every sync pulse and every gate of light is laid out now, in session time, so the
% blocks can be cut between them.
testPulses = S.Sleep.TestPulses;
plan = lum.sleep.testPulsePlan(testPulses);
sync = S.Sleep.Sync;
if testPulses.Enabled
    durationSeconds = plan.Duration;
else
    durationSeconds = 60 * S.Sleep.DurationMinutes;
end
syncPulses = lum.sleep.syncPulseTimes(sync, durationSeconds);
cycle = plan.CyclePeriod;

%% Hardware
% The Flex channels, and PulsePal when test pulses are on; never the HiFi module. A
% session with test pulses refuses to start without PulsePal (lum.dev.openPulsePal), and
% Bpod runs the protocol file with no try/catch of its own, so the console is released
% here before the error is shown.
try
    devices = lum.dev.open(rig, lum.sleep.deviceSettings(S));
catch openError
    BpodSystem.Status.BeingUsed = 0;
    rethrow(openError);
end

syncChannel = '';
if S.Session.UseSync && devices.flex.hasSync()
    syncChannel = rig.Sync.Channel;
end
lines = {syncChannel, '', ''};
if testPulses.Enabled
    lines(2:3) = rig.Opto.Channels;
end

plots = lum.sleep.Plots(S, 'Subject', subject, 'MaxPulses', size(syncPulses, 1), 'Plan', plan);

%% Session barcode
startTime = datetime('now');
barcode = lum.sync.barcode(lum.sync.barcodeValue(startTime), S.Sync.Barcode, 'Sleep');
barcodeSent = false;
if S.Session.UseSync && S.Sync.Barcode.Enabled
    barcodeSent = devices.flex.sendBarcode(barcode);
end
plots.showBarcode(barcode, barcodeSent);
fprintf('LuminoseFM: sleep session, %.4g min, a %s sync pulse every %g s%s.\n', ...
        durationSeconds / 60, lower(S.Sync.ModeNames{sync.Mode}), sync.Interval, ...
        barcodeText(barcode, barcodeSent));
if testPulses.Enabled
    fprintf('LuminoseFM: test pulses on channels A and B through PulsePal.\n  %s\n', ...
            strjoin(lum.sleep.describeTestPulses(testPulses, plan), sprintf('\n  ')));
end

%% Blocks
nSync = size(syncPulses, 1);
nSegments = size(plan.Segments, 1);
syncOnsets = NaN(1, nSync);
syncWidths = syncPulses(:, 2)' * cycle;
syncBlocks = NaN(1, nSync);
segmentOnsets = NaN(1, nSegments);
segmentBlocks = NaN(1, nSegments);
nSyncSent = 0;
nSegmentsSent = 0;
nBlocks = 0;
saveEveryNBlocks = 6;   % About a minute of 10 s blocks
stoppedReason = '';
cursor = struct('Time', 0, 'End', round(durationSeconds / cycle), 'NextSync', 1, 'NextEpoch', 1);
sessionTimer = tic;
while BpodSystem.Status.BeingUsed == 1 && cursor.Time < cursor.End
    [block, cursor] = lum.sleep.nextBlock(plan, syncPulses, cursor, rig.Limits.MaxStates);
    if block.Step > 0
        % The step's carrier goes to PulsePal between blocks, with every line low, and
        % only to a PulsePal that still answers.
        carrier = plan.Steps(block.Step).Carrier;
        if devices.pulsePal.needsReprogramming(carrier)
            try
                devices.pulsePal.checkConnection();
                devices.pulsePal.configure(carrier);
            catch pulsePalError
                stoppedReason = pulsePalError.message;
                break
            end
        end
    end
    SendStateMachine(lum.sleep.blockStateMachine(block, lines));
    rawEvents = RunStateMachine;
    if isempty(fieldnames(rawEvents))
        break  % Stopped before the block began; nothing to record
    end

    BpodSystem.Data = AddTrialEvents(BpodSystem.Data, rawEvents);
    nBlocks = nBlocks + 1;
    if nBlocks == 1
        % AddTrialEvents builds Data.Info on the first block, so session-level
        % annotations go in after it.
        BpodSystem.Data.Info.EmulatorMode = devices.emulated;
        BpodSystem.Data.Session = sessionRecord(S, rig, devices, startTime, barcode, ...
                                                barcodeSent, syncChannel, plan);
    end
    trial = BpodSystem.Data.RawEvents.Trial{nBlocks};
    trialStart = BpodSystem.Data.TrialStartTimestamp(nBlocks);
    [syncOnsets, syncBlocks, nSyncSent] = recordStarts(syncOnsets, syncBlocks, nSyncSent, ...
        trial, trialStart, block.SyncIndices, block.SyncStates, block.StateNames, nBlocks);
    [segmentOnsets, segmentBlocks, nSegmentsSent] = recordStarts(segmentOnsets, segmentBlocks, ...
        nSegmentsSent, trial, trialStart, block.SegmentIndices, block.SegmentStates, ...
        block.StateNames, nBlocks);
    plots.update(struct('Onset', syncOnsets, 'Width', syncWidths, 'n', nSyncSent), ...
                 struct('Onset', segmentOnsets, 'n', nSegmentsSent), toc(sessionTimer), ...
                 cursor.Time * cycle);

    HandlePauseCondition;
    if mod(nBlocks, saveEveryNBlocks) == 0
        if testPulses.Enabled
            try
                devices.pulsePal.checkConnection();
            catch pulsePalError
                stoppedReason = pulsePalError.message;
            end
        end
        BpodSystem.Data = publishPulses(BpodSystem.Data, syncOnsets, syncWidths, syncBlocks, ...
            nSyncSent, plan, segmentOnsets, segmentBlocks, nSegmentsSent, testPulses.Enabled);
        SaveBpodSessionData;
        if ~isempty(stoppedReason)
            break
        end
    end
end
completed = isempty(stoppedReason) && nSyncSent == nSync && nSegmentsSent == nSegments;
if ~isempty(stoppedReason)
    warning('lum:sleep:run:pulsePalStopped', ...
            ['The sleep session stopped early, after %d of %d gates of light, because PulsePal '...
             'stopped answering: %s\nWhat was sent is saved.'], nSegmentsSent, nSegments, stoppedReason);
end

%% Teardown
% Everything is released here, before LuminoseFM hands the rig back with
% RunProtocol('Stop'), which removes +lum from the path.
try
    BpodSystem.Data = publishPulses(BpodSystem.Data, syncOnsets, syncWidths, syncBlocks, ...
        nSyncSent, plan, segmentOnsets, segmentBlocks, nSegmentsSent, testPulses.Enabled);
    if isfield(BpodSystem.Data, 'Session')
        BpodSystem.Data.Session.DeviceLog = struct('PulsePal', {devices.pulsePal.log()}, ...
                                                   'FlexIO', {devices.flex.log()});
        BpodSystem.Data.Session.EndTime = char(datetime('now'), 'yyyy-MM-dd HH:mm:ss');
        BpodSystem.Data.Session.TestPulses.Completed = testPulses.Enabled && completed;
        BpodSystem.Data.Session.TestPulses.StoppedReason = stoppedReason;
    end
    BpodSystem.Data = devices.flex.mergeAnalogData(BpodSystem.Data);
    if nBlocks > 0
        SaveBpodSessionData;
    end
catch teardownError
    warning('lum:sleep:run:teardownFailed', 'Saving the sleep session failed: %s', ...
            teardownError.message);
end

for name = {'pulsePal', 'hifi', 'flex'}
    try
        devices.(name{1}).close();
    catch closeError
        warning('lum:sleep:run:closeFailed', 'Could not close %s cleanly: %s', name{1}, ...
                closeError.message);
    end
end
clear devices plots  % No lum.* object may outlive RunProtocol('Stop')

fprintf('LuminoseFM: sleep session ended after %d sync pulse(s) in %d block(s).\n', nSyncSent, nBlocks);
if testPulses.Enabled
    fprintf('  %d of %d gates of light sent; the schedule was %s.\n', nSegmentsSent, nSegments, ...
            completionText(completed));
end
if nBlocks > 0
    fprintf('  Data: %s\n', BpodSystem.Path.CurrentDataFile);
end


function [onsets, blocks, nSent] = recordStarts(onsets, blocks, nSent, trial, trialStart, rows, ...
                                                states, stateNames, block)
% Record the onsets a block actually sent, each at the entry time of the state it starts
% in. Rows follow on from those already sent; a block stopped part way through records
% only what began.
for j = 1:numel(rows)
    name = stateNames{states(j)};
    if ~isfield(trial.States, name) || isnan(trial.States.(name)(1))
        break
    end
    onsets(rows(j)) = trialStart + trial.States.(name)(1);
    blocks(rows(j)) = block;
    nSent = rows(j);
end


function sessionData = publishPulses(sessionData, syncOnsets, syncWidths, syncBlocks, nSync, ...
                                     plan, segmentOnsets, segmentBlocks, nSegments, testPulsesOn)
% The pulse and light records, trimmed to what was sent.
sessionData.SyncPulses = struct('Onset', syncOnsets(1:nSync), 'Width', syncWidths(1:nSync), ...
                                'Block', syncBlocks(1:nSync));
if testPulsesOn
    rows = plan.Segments(1:nSegments, :);
    sessionData.LightSegments = struct('Onset', segmentOnsets(1:nSegments), ...
        'Duration', rows(:, 2)' * plan.CyclePeriod, 'Channel', rows(:, 3)', 'Step', rows(:, 4)', ...
        'Epoch', rows(:, 5)', 'Block', segmentBlocks(1:nSegments));
end


function record = sessionRecord(S, rig, devices, startTime, barcode, barcodeSent, syncChannel, plan)
% Session-level information, written once.
record = struct();
record.Type = 'Sleep';
record.Subject = S.Meta.Subject;
record.Settings = S;
record.Rig = rig;
record.Emulated = devices.emulated;
record.DevicesAvailable = struct('PulsePal', devices.pulsePal.Available, ...
                                 'FlexAnalog', devices.flex.hasAnalog(), ...
                                 'FlexSync', devices.flex.hasSync());
record.SyncSent = ~isempty(syncChannel);
record.StartTime = char(startTime, 'yyyy-MM-dd HH:mm:ss');
record.Barcode = struct('Value', barcode.Value, 'Hex', barcode.Hex, 'Kind', barcode.Kind, ...
                        'Sent', barcodeSent, 'Params', barcode.Params);
record.TestPulses = struct('Enabled', S.Sleep.TestPulses.Enabled, 'Steps', plan.Steps, ...
                           'Duration', plan.Duration, 'Completed', false, 'StoppedReason', '');
record.ProtocolVersion = lum.version();


function text = barcodeText(barcode, sent)
% How the barcode went, for the console.
if sent
    text = sprintf(', after barcode %s (%.2f s)', barcode.Hex, barcode.TotalDuration);
else
    text = sprintf(', barcode %s not sent', barcode.Hex);
end


function text = completionText(completed)
% Whether the schedule ran to its end, for the console.
if completed
    text = 'completed';
else
    text = 'not completed';
end
