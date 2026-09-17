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
%              (PulsePal and cameras refused as for behaviour), video, plots, barcode
%   blocks     the timeline in state machines of about 10 s (lum.sleep.nextBlock), each
%              cut where every line is low and no epoch is split; PulsePal is given each
%              step's carrier between blocks; onsets read back from the states
%   teardown   the plots saved as an image, the pulse and light records, the analog
%              stream, the final file, the settings kept for the next session, then the
%              video stopped and its summary added to the file, devices released
%
% The house light starts at S.Sleep.HouseLight and is switched from the sleep window's
% header at once, mid-block included (devices.houseLight, D15). PulsePal holds it on its
% output 3, so it stays as the operator left it between blocks too, and its loopback
% into BNC1 puts each switch made during a block among that block's events.
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
%                       StoppedReason), Cameras (lum.dev.Cameras.sessionRecord),
%                       ProtocolVersion, DeviceLog (PulsePal, FlexIO, Cameras, HouseLight),
%                       HouseLight (lum.dev.HouseLight.record: every switch, and every
%                       edge on Bpod's clock),
%                       PlotsImage (lum.gui.savePlotsImage), SyncFit (what
%                       lum.sync.fitToCameras widened)
%   Data.SyncPulses     .Onset (s, state machine clock), .Width (s) and .Block, one value
%                       per pulse sent
%   Data.LightSegments  With test pulses: .Onset (s, state machine clock), .Duration (s),
%                       .Channel (1 A, 2 B), .Step, .Epoch and .Block, one value per gate
%                       of light sent (lum.sleep.epochShape gives the pulses in it)
%   Data.HouseLight     1 or 0 per block: whether the house light was on as it started;
%                       switches during a block are BNC1High (on) and BNC1Low (off) in
%                       its events, and Data.Session.HouseLight lists every switch
%   Data.CameraTime     Seconds on the camera host clock when each block's events arrived,
%                       one value per block (NaN without video): pairs TrialEndTimestamp
%                       with the frame logs' HostTime_s
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
% Kept, because the console's End button clears BpodSystem.Path.Settings before the
% teardown writes the settings back.
settingsFile = BpodSystem.Path.Settings;
S.Session.Type = 'Sleep';
% With video, the barcode and sync pulses are widened until the cameras can read them
% (lum.sync.fitToCameras); the session runs and records the fitted values, and the
% settings file keeps what was typed.
typedSync = S.Sync;
typedSleepSync = S.Sleep.Sync;
[S, syncFit] = lum.sync.fitToCameras(S);
if ~isempty(syncFit)
    fprintf('LuminoseFM: sync line widened so the %g Hz cameras can read it: %s.\n', ...
            S.Camera.FrameRate, strjoin(syncFit, ', '));
end
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
% The Flex channels and PulsePal, which drives the house light and any test pulses;
% never the HiFi module. A session with test pulses does not start on the rig without
% PulsePal; one without runs, without the house light (lum.dev.openPulsePal,
% lum.dev.openHouseLight). Bpod runs the protocol file with no try/catch of its own,
% so the console is released here before the error is shown.
try
    devices = lum.dev.open(rig, lum.sleep.deviceSettings(S));
catch openError
    BpodSystem.Status.BeingUsed = 0;
    rethrow(openError);
end
% Video first, so the barcode is on it.
try
    devices.cameras.startRecording(BpodSystem.Path.CurrentDataFile);
catch recordError
    closeDevices(devices);
    BpodSystem.Status.BeingUsed = 0;
    rethrow(recordError);
end

syncChannel = '';
if S.Session.UseSync && devices.flex.hasSync()
    syncChannel = rig.Sync.Channel;
end
lines = {syncChannel, '', ''};
if testPulses.Enabled
    lines(2:3) = rig.Opto.Channels;
end

plots = lum.sleep.Plots(S, 'Subject', subject, 'MaxPulses', size(syncPulses, 1), 'Plan', plan, ...
                        'HouseLight', devices.houseLight);
cameraWindow = [];
if S.Camera.ShowWindow && devices.cameras.canPreview()
    cameraWindow = lum.gui.CameraWindow(devices.cameras, S.Camera, 'Subject', subject);
end

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
% Blocks last about 10 s and are never shorter than their shortest span, so one mark a
% second of recording is room enough.
cameraTimes = NaN(1, max(100, ceil(durationSeconds)));
houseLights = NaN(1, numel(cameraTimes));
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
    arrivedAt = devices.houseLight.sessionTime();  % For the block's house light level
    if isempty(fieldnames(rawEvents))
        break  % Stopped before the block began; nothing to record
    end

    BpodSystem.Data = AddTrialEvents(BpodSystem.Data, rawEvents);
    nBlocks = nBlocks + 1;
    if nBlocks <= numel(cameraTimes)
        cameraTimes(nBlocks) = devices.cameras.mark('BlockEnd', nBlocks);
        houseLights(nBlocks) = double(houseLightAtStart(devices.houseLight, nBlocks, arrivedAt));
    end
    if nBlocks == 1
        % AddTrialEvents builds Data.Info on the first block, so session-level
        % annotations go in after it.
        BpodSystem.Data.Info.EmulatorMode = devices.emulated;
        BpodSystem.Data.Session = sessionRecord(S, rig, devices, startTime, barcode, ...
                                                barcodeSent, syncChannel, plan);
        BpodSystem.Data.Session.SyncFit = syncFit;
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
        BpodSystem.Data.CameraTime = cameraTimes(1:min(nBlocks, numel(cameraTimes)));
        BpodSystem.Data.HouseLight = houseLights(1:min(nBlocks, numel(houseLights)));
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
if ~isempty(cameraWindow)
    cameraWindow.close();
end
saved = false;
plotsImage = '';
if nBlocks > 0
    [plotsImage, plotsProblem] = lum.gui.savePlotsImage(plots.Figure, BpodSystem.Path.CurrentDataFile);
    if ~isempty(plotsProblem)
        warning('lum:sleep:run:plotsNotSaved', 'The plots were not saved as an image: %s', ...
                plotsProblem);
    end
end
try
    BpodSystem.Data = publishPulses(BpodSystem.Data, syncOnsets, syncWidths, syncBlocks, ...
        nSyncSent, plan, segmentOnsets, segmentBlocks, nSegmentsSent, testPulses.Enabled);
    BpodSystem.Data.CameraTime = cameraTimes(1:min(nBlocks, numel(cameraTimes)));
    BpodSystem.Data.HouseLight = houseLights(1:min(nBlocks, numel(houseLights)));
    if isfield(BpodSystem.Data, 'Session')
        BpodSystem.Data.Session.PlotsImage = plotsImage;
        BpodSystem.Data.Session.HouseLight = devices.houseLight.record(BpodSystem.Data);
        BpodSystem.Data.Session.DeviceLog = struct('PulsePal', {devices.pulsePal.log()}, ...
                                                   'FlexIO', {devices.flex.log()}, ...
                                                   'Cameras', {devices.cameras.log()}, ...
                                                   'HouseLight', {devices.houseLight.log()});
        BpodSystem.Data.Session.Cameras = devices.cameras.sessionRecord();
        BpodSystem.Data.Session.EndTime = char(datetime('now'), 'yyyy-MM-dd HH:mm:ss');
        BpodSystem.Data.Session.TestPulses.Completed = testPulses.Enabled && completed;
        BpodSystem.Data.Session.TestPulses.StoppedReason = stoppedReason;
    end
    BpodSystem.Data = devices.flex.mergeAnalogData(BpodSystem.Data);
    if nBlocks > 0
        SaveBpodSessionData;
        saved = true;
    end
catch teardownError
    warning('lum:sleep:run:teardownFailed', 'Saving the sleep session failed: %s', ...
            teardownError.message);
end

% The house light as the operator left it is where the next sleep session starts; a session
% that could not switch it keeps what the settings asked for.
if ~headless
    if devices.houseLight.Switchable
        S.Sleep.HouseLight = devices.houseLight.On;
    end
    S.Sync = typedSync;             % What was typed, not what was fitted to the cameras
    S.Sleep.Sync = typedSleepSync;
    try
        ProtocolSettings = S;
        save(settingsFile, 'ProtocolSettings');
    catch settingsError
        warning('lum:sleep:run:settingsNotSaved', ...
                'The settings as they ended were not saved for the next session: %s', ...
                settingsError.message);
    end
end

% The video stops only once the data are saved, so everything the file holds is on it
% (D14); the recording summary is then added with a second, small save.
try
    devices.cameras.finishRecording('SessionSaved', nBlocks);
catch cameraError
    warning('lum:sleep:run:videoStopFailed', 'Stopping the video failed: %s', cameraError.message);
end
if saved && isfield(BpodSystem.Data, 'Session') && devices.cameras.sessionRecord().Recorded
    try
        BpodSystem.Data.Session.Cameras = devices.cameras.sessionRecord();
        BpodSystem.Data.Session.DeviceLog.Cameras = devices.cameras.log();
        SaveBpodSessionData;
    catch saveError
        warning('lum:sleep:run:videoSummaryNotSaved', ...
                'The session is saved, but the video summary could not be added to it: %s', ...
                saveError.message);
    end
end

plots.close();  % Only hidden by the console's End button, so it could be saved above
closeDevices(devices);
clear devices plots cameraWindow  % No lum.* object may outlive RunProtocol('Stop')

fprintf('LuminoseFM: sleep session ended after %d sync pulse(s) in %d block(s).\n', nSyncSent, nBlocks);
if testPulses.Enabled
    fprintf('  %d of %d gates of light sent; the schedule was %s.\n', nSegmentsSent, nSegments, ...
            completionText(completed));
end
if nBlocks > 0
    fprintf('  Data: %s\n', BpodSystem.Path.CurrentDataFile);
end


function closeDevices(devices)
% Release every device, whatever happened to the session.
for name = {'cameras', 'houseLight', 'pulsePal', 'hifi', 'flex'}  % The light off before PulsePal goes
    try
        devices.(name{1}).close();
    catch closeError
        warning('lum:sleep:run:closeFailed', 'Could not close %s cleanly: %s', name{1}, ...
                closeError.message);
    end
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
                                 'FlexSync', devices.flex.hasSync(), ...
                                 'Cameras', devices.cameras.Available, ...
                                 'HouseLight', devices.houseLight.Available);
record.Cameras = devices.cameras.sessionRecord();  % Brought up to date at teardown
record.SyncSent = ~isempty(syncChannel);
record.StartTime = char(startTime, 'yyyy-MM-dd HH:mm:ss');
record.Barcode = struct('Value', barcode.Value, 'Hex', barcode.Hex, 'Kind', barcode.Kind, ...
                        'Sent', barcodeSent, 'Params', barcode.Params);
record.TestPulses = struct('Enabled', S.Sleep.TestPulses.Enabled, 'Steps', plan.Steps, ...
                           'Duration', plan.Duration, 'Completed', false, 'StoppedReason', '');
record.ProtocolVersion = lum.version();


function on = houseLightAtStart(houseLight, blockNumber, arrivedAt)
% The house light's level as a block started: from the loopback input's first edge in the
% block when there is one, otherwise the level PulsePal held when the block started on
% MATLAB's clock — its events arrived arrivedAt, one block's length after it started.
global BpodSystem %#ok<GVMIS>
duration = BpodSystem.Data.TrialEndTimestamp(blockNumber) - BpodSystem.Data.TrialStartTimestamp(blockNumber);
on = lum.dev.HouseLight.levelAtStart(BpodSystem.Data.RawEvents.Trial{blockNumber}.Events, ...
                                     houseLight, houseLight.levelAt(arrivedAt - duration));


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
