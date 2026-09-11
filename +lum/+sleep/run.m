function run(S, rig, subject, headless)
% lum.sleep.run runs a home-cage sleep session: a sleep barcode, then sync pulses.
%
% The sleep half of LuminoseFM (D11), called by it once the operator has chosen a
% sleep session. There is no task: the session exists to put a timeline on the
% acquisition devices recording the animal's sleep, so it sends the session barcode
% with sleep markers (lum.sync.barcode, 'Sleep') and then a sync pulse every
% S.Sleep.Sync.Interval seconds on Flex2 for S.Sleep.DurationMinutes, until the time is
% up or the operator stops it from the console.
%
%   setup      sleep setup dialog, validation, Flex I/O, plots, barcode
%   blocks     pulses in blocks of about 10 s, each its own state machine
%              (lum.sleep.blockStateMachine); onsets read back from the states
%   teardown   the pulse record, the analog stream, the final file, devices released
%
% Pulses run on blocking RunStateMachine calls, on the rig as in the emulator: with
% nothing to prepare between blocks there is no use for BpodTrialManager, and every
% pulse's onset is the state machine's own timestamp, so the upload between blocks
% only lengthens one interval by a few milliseconds and is recorded. Every lum.*
% object is released before this returns, so LuminoseFM can call RunProtocol('Stop').
%
% Data (Data.Session.Type is 'Sleep'):
%   Data.Session     Type, Subject, Settings, Rig, Emulated, DevicesAvailable,
%                    SyncSent, StartTime, EndTime, Barcode (Value, Hex, Kind, Sent,
%                    Params), ProtocolVersion, DeviceLog
%   Data.SyncPulses  .Onset (s, state machine clock), .Width (s) and .Block, one value
%                    per pulse sent
%   Data.RawEvents   Bpod's own record, one "trial" per block
%
% Arguments:
%   S         Settings struct (merged)
%   rig       Channel map from RigConfig
%   subject   Subject chosen in the launch manager
%   headless  true to skip the setup dialog and use S as it is (tests)
%
% See also: LuminoseFM, lum.gui.SleepSetupDialog, lum.sleep.Plots, lum.sleep.validate

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

%% Hardware
% Only the Flex channels: no light and no sound in the home cage, so PulsePal and the
% HiFi module are not opened.
deviceSettings = S;
deviceSettings.Session.UseOpto = false;
deviceSettings.Session.UseSound = false;
devices = lum.dev.open(rig, deviceSettings);

sync = S.Sleep.Sync;
syncChannel = '';
if S.Session.UseSync && devices.flex.hasSync()
    syncChannel = rig.Sync.Channel;
end
durationSeconds = 60 * S.Sleep.DurationMinutes;
maxPulses = ceil(durationSeconds / (sync.Interval - sync.IntervalJitter)) + floor(rig.Limits.MaxStates / 2);

plots = lum.sleep.Plots(S, 'Subject', subject, 'MaxPulses', maxPulses);

%% Session barcode
startTime = datetime('now');
barcode = lum.sync.barcode(lum.sync.barcodeValue(startTime), S.Sync.Barcode, 'Sleep');
barcodeSent = false;
if S.Session.UseSync && S.Sync.Barcode.Enabled
    barcodeSent = devices.flex.sendBarcode(barcode);
end
plots.showBarcode(barcode, barcodeSent);
fprintf('LuminoseFM: sleep session, %g min, a %s sync pulse every %g s%s.\n', ...
        S.Sleep.DurationMinutes, lower(S.Sync.ModeNames{sync.Mode}), sync.Interval, ...
        barcodeText(barcode, barcodeSent));

%% Pulses
onsets = NaN(1, maxPulses);
widths = NaN(1, maxPulses);
blocks = NaN(1, maxPulses);
nPulses = 0;
nBlocks = 0;
saveEveryNBlocks = 6;   % About a minute of 10 s blocks
sessionTimer = tic;
while BpodSystem.Status.BeingUsed == 1
    secondsLeft = durationSeconds - toc(sessionTimer);
    if secondsLeft <= 0
        break
    end
    n = min(lum.sleep.pulsesPerBlock(sync, rig.Limits.MaxStates, secondsLeft), maxPulses - nPulses);
    if n < 1
        break
    end
    [blockWidths, blockGaps] = lum.sleep.pulseSchedule(sync, n);
    SendStateMachine(lum.sleep.blockStateMachine(blockWidths, blockGaps, syncChannel));
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
                                                barcodeSent, syncChannel);
    end
    [onsets, widths, blocks, nPulses] = recordBlock(onsets, widths, blocks, nPulses, ...
        BpodSystem.Data.RawEvents.Trial{nBlocks}, BpodSystem.Data.TrialStartTimestamp(nBlocks), ...
        blockWidths, nBlocks);
    plots.update(onsets, widths, nPulses, toc(sessionTimer));

    HandlePauseCondition;
    if mod(nBlocks, saveEveryNBlocks) == 0
        BpodSystem.Data = publishPulses(BpodSystem.Data, onsets, widths, blocks, nPulses);
        SaveBpodSessionData;
    end
end

%% Teardown
% Everything is released here, before LuminoseFM hands the rig back with
% RunProtocol('Stop'), which removes +lum from the path.
try
    BpodSystem.Data = publishPulses(BpodSystem.Data, onsets, widths, blocks, nPulses);
    if isfield(BpodSystem.Data, 'Session')
        BpodSystem.Data.Session.DeviceLog = struct('FlexIO', {devices.flex.log()});
        BpodSystem.Data.Session.EndTime = char(datetime('now'), 'yyyy-MM-dd HH:mm:ss');
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

fprintf('LuminoseFM: sleep session ended after %d pulse(s) in %d block(s).\n', nPulses, nBlocks);
if nBlocks > 0
    fprintf('  Data: %s\n', BpodSystem.Path.CurrentDataFile);
end


function [onsets, widths, blocks, nPulses] = recordBlock(onsets, widths, blocks, nPulses, ...
                                                          trial, trialStart, blockWidths, block)
% Append the pulses a block actually sent, each at its Pulse state's entry time. A
% block stopped part way through records only the pulses that began.
for i = 1:numel(blockWidths)
    name = sprintf('Pulse%03d', i);
    if ~isfield(trial.States, name) || isnan(trial.States.(name)(1))
        break
    end
    nPulses = nPulses + 1;
    onsets(nPulses) = trialStart + trial.States.(name)(1);
    widths(nPulses) = blockWidths(i);
    blocks(nPulses) = block;
end


function sessionData = publishPulses(sessionData, onsets, widths, blocks, nPulses)
% The pulse record, trimmed to the pulses sent.
sessionData.SyncPulses = struct('Onset', onsets(1:nPulses), 'Width', widths(1:nPulses), ...
                                'Block', blocks(1:nPulses));


function record = sessionRecord(S, rig, devices, startTime, barcode, barcodeSent, syncChannel)
% Session-level information, written once.
record = struct();
record.Type = 'Sleep';
record.Subject = S.Meta.Subject;
record.Settings = S;
record.Rig = rig;
record.Emulated = devices.emulated;
record.DevicesAvailable = struct('FlexAnalog', devices.flex.hasAnalog(), ...
                                 'FlexSync', devices.flex.hasSync());
record.SyncSent = ~isempty(syncChannel);
record.StartTime = char(startTime, 'yyyy-MM-dd HH:mm:ss');
record.Barcode = struct('Value', barcode.Value, 'Hex', barcode.Hex, 'Kind', barcode.Kind, ...
                        'Sent', barcodeSent, 'Params', barcode.Params);
record.ProtocolVersion = lum.version();


function text = barcodeText(barcode, sent)
% How the barcode went, for the console.
if sent
    text = sprintf(', after barcode %s (%.2f s)', barcode.Hex, barcode.TotalDuration);
else
    text = sprintf(', barcode %s not sent', barcode.Hex);
end
