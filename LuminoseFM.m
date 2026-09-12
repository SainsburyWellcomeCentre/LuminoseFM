function LuminoseFM
% LuminoseFM — freely-moving 2-AFC olfactory-bulb optogenetics task, and home-cage sleep.
%
% A two-alternative forced-choice task for OSN-ChR mice, in which the stimulus is a
% two-channel spatiotemporal pattern of light delivered to the olfactory bulb
% through a fiber bundle. See README.md for the rig and the science, and
% docs/architecture.md for the design decisions this file assumes.
%
% Launch it from the Bpod console's launch manager. The first window asks what kind
% of session this is (D11):
%   Behaviour  the task: setup dialog, trial loop, runtime window and online plots
%   Sleep      a home-cage sleep recording: a sleep barcode, then sync pulses on a
%              clock and, if chosen, test pulses of light on channels A and B through
%              PulsePal, with its own setup dialog, test-pulse designer and plots
%              (lum.sleep.run, D13)
% Either runs end to end under Bpod('EMU') on a machine with no hardware, with working
% GUI, plots and data saving; hardware calls fall back to shims that log what they
% would have done. The data file records which kind it was, in Data.Session.Type.
%
% This file is deliberately thin. It sequences a session and owns nothing else:
%   setup      settings, preflight, session type, stimulus set, devices, sounds,
%              windows, barcode
%   trial loop generate, build, upload, run, score, record, plot, save
%   teardown   merge the analog stream, write the final file, release devices
%
% Everything with logic in it lives in the +lum package, where it can be tested
% without hardware. See lum.buildTrialSM for the state graph, lum.nextTrialSpec for
% the trial-generation policy, lum.pattern.stimulusSet for the stimuli, and
% lum.SessionRunner for how the trial loop works with and without BpodTrialManager.
%
% See also: RigConfig, CheckRig, lum.dev.open, lum.sleep.run, tests/runLuminoseTests.m

global BpodSystem %#ok<GVMIS> % Bpod's own session object

protocolRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(protocolRoot, 'hardware'));  % Session only; the saved path is untouched

%% Settings
rig = RigConfig;
[S, changed] = lum.mergeSettings(lum.defaultSettings, BpodSystem.ProtocolSettings);
if ~isempty(changed)
    fprintf('LuminoseFM: %d setting(s) filled in or converted: %s\n', ...
            numel(changed), strjoin(changed, ', '));
end
subject = currentSubject();
S.Meta.Subject = subject;

CheckRig;

% The setup dialogs are modal, so an automated session (the emulator smoke tests)
% needs a way past them: the session type and every setting then come from the
% settings file. Nothing else in the protocol behaves differently.
headless = isequal(getappdata(0, 'LuminoseFM_Headless'), true);

%% Session type
if headless
    fprintf('LuminoseFM: headless mode; a %s session with the settings file as-is.\n', ...
            lower(S.Session.Type));
else
    sessionType = lum.gui.SessionTypeDialog('Default', S.Session.Type, 'Subject', subject);
    if isempty(sessionType)
        fprintf('LuminoseFM: session cancelled.\n');
        BpodSystem.Status.BeingUsed = 0;
        return
    end
    S.Session.Type = sessionType;
end

if strcmp(S.Session.Type, 'Sleep')
    % Everything a sleep session holds is released inside lum.sleep.run, so nothing
    % from +lum is left for RunProtocol('Stop') to strand when it removes the path.
    lum.sleep.run(S, rig, subject, headless);
    if BpodSystem.Status.BeingUsed == 1
        RunProtocol('Stop');
    end
    return
end

%% Behaviour setup
S = lum.pattern.prepareSeed(S);  % A new trial order, unless the settings fix the seed
if ~headless
    [S, accepted] = lum.gui.SetupDialog(S, rig, 'Subject', subject);
    if ~accepted
        fprintf('LuminoseFM: session setup cancelled.\n');
        BpodSystem.Status.BeingUsed = 0;
        return
    end
    SaveProtocolSettings(S);  % So the session can be reproduced or resumed
end

% Validated here as well as in the dialog, so a headless session cannot start on a
% settings file the dialog would have refused. Nothing is open yet to release.
[stimulusSet, ~, notes] = lum.validateSettings(S, rig);
for i = 1:numel(notes)
    fprintf('LuminoseFM: note: %s\n', notes{i});
end

%% Hardware
% A session that delivers light refuses to start without PulsePal (lum.dev.openPulsePal).
% Bpod runs the protocol file with no try/catch of its own, so the console is released
% here before the error is shown.
try
    devices = lum.dev.open(rig, S);
catch openError
    BpodSystem.Status.BeingUsed = 0;
    rethrow(openError);
end

fprintf('LuminoseFM: %s\n', lum.trainingStageNote(S));
fprintf('LuminoseFM: %s\n', lum.HoldShaping.describe(S));
fprintf('LuminoseFM: %s\n', lum.HoldShaping.describeBreak(S));
fprintf('LuminoseFM: %s stimulus set, %d group(s), %d trial(s) ordered (seed %d)\n', ...
        stimulusSet.Family, stimulusSet.nGroups, stimulusSet.nTrials, stimulusSet.Seed);
if ~stimulusSet.Continuous
    for k = 1:stimulusSet.nPatterns
        fprintf('  %s  P(left) %.2f\n', lum.pattern.describe(lum.pattern.patternAt(stimulusSet, k)), ...
                stimulusSet.PatternPLeft(k));
    end
end

sounds = lum.loadSounds(S, devices, stimulusSet);
devices.hifi.freeze();  % No more USB transfers once the trial loop owns the module

[cueComponents, stimulusComponents] = lum.stim.build(S);

%% Interface
BpodNotebook('init');
windowMode = S.Session.RuntimeWindow;
if strcmp(windowMode, 'Automatic')
    if devices.emulated
        windowMode = 'Compact';  % The reduced form, for the emulator
    else
        windowMode = 'Tabbed';
    end
end
runtime = lum.gui.RuntimeWindow(S, 'Mode', windowMode, 'Subject', subject);
plots = lum.OnlinePlots(S, stimulusSet, 'Subject', subject);
if S.Session.ShowAnalogViewer
    devices.flex.openAnalogViewer();  % Airflow, from the flow meter on Flex1
end

%% Session barcode
% One barcode before the first trial identifies the session on every acquisition
% device's sync channel. It runs as a state machine of its own, before the trial
% manager exists, so no trial carries its states; the analog merge at the end
% corrects for Bpod counting it as a trial.
startTime = datetime('now');
barcode = lum.sync.barcode(lum.sync.barcodeValue(startTime), S.Sync.Barcode, 'Behaviour');
barcodeSent = false;
if S.Session.UseSync && S.Sync.Barcode.Enabled
    barcodeSent = devices.flex.sendBarcode(barcode);
end
if barcodeSent
    fprintf('LuminoseFM: session barcode %s sent (%.2f s).\n', barcode.Hex, barcode.TotalDuration);
end

%% Session state
maxTrials = S.Session.MaxTrials;
history = lum.newHistory(maxTrials);
data = initialiseDataFields(maxTrials);
valveCache = struct('amount', NaN, 'times', [0 0]);
queue = stimulusSet.TrialPattern;

% Trigger states open the window in which MATLAB may prepare the next trial. Every
% trial passes through exactly one of these, and each leaves at least the ITI
% afterwards for the work to finish in.
runner = lum.SessionRunner(devices.emulated, lum.triggerStates(S));
fprintf('LuminoseFM: running in %s mode, %s runtime window.\n', runner.Mode, lower(windowMode));

[S, spec, sma, valveCache, queue] = prepareTrial(S, rig, devices, history, stimulusSet, queue, ...
    sounds, cueComponents, stimulusComponents, 1, valveCache, runtime);
% What the first trials will deliver is known now, so it is shown before trial 1 starts
% rather than after it ends.
plots.showNext(spec, queue);
runtime.showStatus(sprintf('Session started  |  %s', runningText(spec, stimulusSet)));
runner.begin(sma);
nextSpec = spec;

%% Trial loop
for currentTrial = 1:maxTrials
    spec = nextSpec;

    runner.awaitPrepareWindow();
    if BpodSystem.Status.BeingUsed == 0; break; end

    prepareTimer = tic;
    if currentTrial < maxTrials
        [S, nextSpec, sma, valveCache, queue] = prepareTrial(S, rig, devices, history, stimulusSet, ...
            queue, sounds, cueComponents, stimulusComponents, currentTrial + 1, valveCache, runtime);
    else
        nextSpec = [];
    end
    prepareSeconds = toc(prepareTimer);

    sendTimer = tic;
    if currentTrial < maxTrials
        runner.queue(sma);
    end
    sendSeconds = toc(sendTimer);

    rawEvents = runner.awaitTrialData();
    if BpodSystem.Status.BeingUsed == 0; break; end
    HandlePauseCondition;
    if currentTrial < maxTrials
        runner.advance();
    end
    if isempty(fieldnames(rawEvents))
        continue  % The session was stopped mid-trial; nothing to record
    end

    %% Record
    BpodSystem.Data = AddTrialEvents(BpodSystem.Data, rawEvents);
    BpodSystem.Data = BpodNotebook('sync', BpodSystem.Data);
    if currentTrial == 1
        % AddTrialEvents builds Data.Info from scratch on the first trial, so
        % session-level annotations have to be added after it, not before.
        BpodSystem.Data.Info.EmulatorMode = devices.emulated;
        BpodSystem.Data.Session = sessionRecord(S, rig, stimulusSet, runner, devices, startTime, ...
                                                barcode, barcodeSent, windowMode);
    end

    result = lum.scoreTrial(BpodSystem.Data.RawEvents.Trial{currentTrial}, spec, rig);
    history = lum.updateHistory(history, currentTrial, spec, result);
    data = recordTrial(data, currentTrial, spec, result, S);

    plotTimer = tic;
    plots.update(currentTrial, spec, result, nextSpec, queue, S.GUI.RewardAmount);
    runtime.showStatus(statusLine(currentTrial, result, nextSpec, stimulusSet));
    plotSeconds = toc(plotTimer);

    % Recorded before the save, so the file written this trial already carries this
    % trial's timing. The save's own cost lands in the next file.
    data.Timing.prepare(currentTrial) = prepareSeconds;
    data.Timing.send(currentTrial) = sendSeconds;
    data.Timing.plot(currentTrial) = plotSeconds;

    saveTimer = tic;
    if mod(currentTrial, S.Session.SaveEveryNTrials) == 0
        BpodSystem.Data = publishTrialFields(BpodSystem.Data, data, currentTrial);
        SaveBpodSessionData;
    end
    data.Timing.save(currentTrial) = toc(saveTimer);
end

%% Teardown
% Every step from here on has to finish before RunProtocol('Stop'), because Stop
% removes the protocol folder from the MATLAB path — and with it the +lum package.
% Anything left holding a lum.* object would then fail in its own destructor. So the
% session is torn down explicitly, in order, and only then handed back to Bpod.
nCompleted = history.nTrials;
summary = 'no trials completed';
try
    BpodSystem.Data = publishTrialFields(BpodSystem.Data, data, nCompleted);
    if isfield(BpodSystem.Data, 'Session')
        BpodSystem.Data.Session.DeviceLog = deviceLogs(devices);
        BpodSystem.Data.Session.EndTime = char(datetime('now'), 'yyyy-MM-dd HH:mm:ss');
    end
    BpodSystem.Data = devices.flex.mergeAnalogData(BpodSystem.Data);
    if nCompleted > 0
        SaveBpodSessionData;
        summary = plots.summaryText(nCompleted);
    end
catch teardownError
    % A failure while saving must not cost the operator their devices as well.
    warning('lum:LuminoseFM:teardownFailed', ...
            'Saving the session data failed: %s', teardownError.message);
end

runner.close();
runtime.close();
closeDevices(devices);
clear runner runtime devices plots cueComponents stimulusComponents  % No lum.* object may outlive Stop

fprintf('LuminoseFM: session ended after %d trial(s).\n', nCompleted);
if nCompleted > 0
    fprintf('  %s\n  Data: %s\n', summary, BpodSystem.Path.CurrentDataFile);
end

% If the loop ran to completion rather than being stopped from the console, end the
% session the way the stop button does: release the ports, close the protocol figures
% and let the console show that the rig is free.
if BpodSystem.Status.BeingUsed == 1
    RunProtocol('Stop');
end


%% ---------------------------------------------------------------------------

function [S, spec, sma, valveCache, queue] = prepareTrial(S, rig, devices, history, stimulusSet, ...
    queue, sounds, cueComponents, stimulusComponents, trialNumber, valveCache, runtime)
% Everything needed to run one trial, done inside the previous trial's window.
S = runtime.sync(S);

[spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, trialNumber);

% Valve times come from a calibration lookup, so they are recomputed only when the
% operator changes the reward volume rather than on every trial.
if valveCache.amount ~= S.GUI.RewardAmount
    valveCache.times = GetValveTimes(S.GUI.RewardAmount, rig.SidePorts);
    valveCache.amount = S.GUI.RewardAmount;
end

context = struct('S', S, 'rig', rig, 'devices', devices, 'spec', spec, ...
                 'pattern', lum.pattern.patternAt(stimulusSet, spec.PatternIndex), ...
                 'sounds', sounds, 'cue', {cueComponents}, ...
                 'stimulus', {stimulusComponents}, 'valveTimes', valveCache.times);

% Device programming belongs here, in the inter-trial window, never mid-stimulus.
for i = 1:numel(stimulusComponents)
    stimulusComponents{i}.configure(context);
end
for i = 1:numel(cueComponents)
    cueComponents{i}.configure(context);
end

sma = lum.buildTrialSM(context);


function text = statusLine(trialNumber, result, nextSpec, stimulusSet)
% The runtime window's header: how the last trial ended and what is running now.
text = sprintf('Trial %d: %s', trialNumber, lum.Outcome.name(result.Outcome));
if result.HoldAttempts > 1
    text = sprintf('%s after %d holds', text, result.HoldAttempts);
end
if ~isempty(nextSpec)
    text = sprintf('%s  |  %s', text, runningText(nextSpec, stimulusSet));
end


function text = runningText(spec, stimulusSet)
% What the running trial delivers, in a few words.
label = 'no group';
if spec.StimulusGroup >= 1
    label = stimulusSet.GroupLabels{spec.StimulusGroup};
end
sides = {'left', 'right'};
text = sprintf('running %d: %s, pays %s, hold %.2f s', spec.TrialNumber, label, ...
               sides{spec.CorrectSide}, spec.HoldDuration);


function subject = currentSubject()
% The subject chosen in the launch manager, or '' when there is none.
global BpodSystem %#ok<GVMIS>
subject = '';
try
    subject = char(BpodSystem.Status.CurrentSubjectName);
catch
    % No launch manager, as in a headless test.
end


function data = initialiseDataFields(maxTrials)
% Preallocate every per-trial series, so the trial loop never grows an array.
blank = NaN(1, maxTrials);
data = struct();
for name = trialSeriesNames()
    data.(name{1}) = blank;
end
data.Timing = struct('prepare', blank, 'send', blank, 'plot', blank, 'save', blank);
data.RuntimeSettings = cell(1, maxTrials);


function names = trialSeriesNames()
% Every per-trial series written to the data file, one value per trial. The README
% (§4.6) and emulatorSessionTest list them too; keep all three in step.
names = {'StimulusGroup', 'PatternIndex', 'CorrectSide', 'Choice', 'Correct', 'Rewarded', ...
         'Outcome', 'ReactionTime', 'OptoOn', 'SoundOn', 'SyncMode', 'SyncPulseWidth', ...
         'BiasTargetPLeft', 'TrainingStage', 'HoldDuration', 'HoldGrace', 'HoldBreaks', ...
         'HoldAttempts'};


function data = recordTrial(data, trialNumber, spec, result, S)
% Store one trial. Only scalars and the runtime settings tier: the stimulus set, the
% rig map and the frozen settings are stored once per session, and each trial holds
% indices into them (README §4.6).
data.StimulusGroup(trialNumber) = spec.StimulusGroup;
data.PatternIndex(trialNumber) = spec.PatternIndex;
data.CorrectSide(trialNumber) = spec.CorrectSide;
data.Choice(trialNumber) = result.Choice;
data.Correct(trialNumber) = result.Correct;
data.Rewarded(trialNumber) = result.Rewarded;
data.Outcome(trialNumber) = result.Outcome;
data.ReactionTime(trialNumber) = result.ReactionTime;
data.OptoOn(trialNumber) = spec.OptoOn;
data.SoundOn(trialNumber) = spec.SoundOn;
data.SyncMode(trialNumber) = spec.SyncMode;
data.SyncPulseWidth(trialNumber) = spec.SyncPulseWidth;
data.BiasTargetPLeft(trialNumber) = spec.BiasTargetPLeft;
data.TrainingStage(trialNumber) = spec.TrainingStage;
data.HoldDuration(trialNumber) = spec.HoldDuration;
data.HoldGrace(trialNumber) = spec.HoldGrace;
data.HoldBreaks(trialNumber) = result.HoldBreaks;
data.HoldAttempts(trialNumber) = result.HoldAttempts;
data.RuntimeSettings{trialNumber} = S.GUI;


function sessionData = publishTrialFields(sessionData, data, nTrials)
% Copy the per-trial series into BpodSystem.Data, trimmed to the trials that ran.
%
% The series live outside BpodSystem.Data during the session so that the preallocated
% tails are never written to disk, and so that a save costs the same at trial 900 as
% at trial 9.
if nTrials < 1
    return
end
for name = trialSeriesNames()
    sessionData.(name{1}) = data.(name{1})(1:nTrials);
end
timingFields = fieldnames(data.Timing);
for i = 1:numel(timingFields)
    sessionData.Timing.(timingFields{i}) = data.Timing.(timingFields{i})(1:nTrials);
end
sessionData.TrialSettings = data.RuntimeSettings(1:nTrials);
sessionData.OutcomeNames = lum.Outcome.allNames();


function record = sessionRecord(S, rig, stimulusSet, runner, devices, startTime, barcode, ...
                                barcodeSent, windowMode)
% Session-level information, written once: the stimulus set the trial records index
% into, plus everything needed to interpret them later.
record = struct();
record.Type = 'Behaviour';
record.Subject = S.Meta.Subject;
record.Settings = S;
record.StimulusSet = rmfield(stimulusSet, 'States');  % Segments are enough; States are for previews
record.Rig = rig;
record.RunnerMode = runner.Mode;
record.RuntimeWindow = windowMode;
record.Emulated = devices.emulated;
record.DevicesAvailable = struct('PulsePal', devices.pulsePal.Available, ...
                                 'HiFi', devices.hifi.Available, ...
                                 'FlexAnalog', devices.flex.hasAnalog(), ...
                                 'FlexSync', devices.flex.hasSync());
record.StartTime = char(startTime, 'yyyy-MM-dd HH:mm:ss');
record.Barcode = struct('Value', barcode.Value, 'Hex', barcode.Hex, 'Kind', barcode.Kind, ...
                        'Sent', barcodeSent, 'Params', barcode.Params);
record.ProtocolVersion = lum.version();


function logs = deviceLogs(devices)
% What each device did, or would have done. Small, and the only record of an emulated
% session's hardware intent.
logs = struct('PulsePal', {devices.pulsePal.log()}, ...
              'HiFi', {devices.hifi.log()}, ...
              'FlexIO', {devices.flex.log()});


function closeDevices(devices)
% Release every device, whatever happened to the session. Safe to call twice: the
% shims' close methods are idempotent.
names = {'pulsePal', 'hifi', 'flex'};
for i = 1:numel(names)
    try
        devices.(names{i}).close();
    catch closeError
        warning('lum:LuminoseFM:closeFailed', ...
                'Could not close %s cleanly: %s', names{i}, closeError.message);
    end
end
