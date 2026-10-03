function LuminoseFM
% LuminoseFM runs a 2-AFC optogenetics session, a sleep recording or an ePhys calibration.
%
% A two-alternative forced-choice task for OSN-ChR mice, in which the stimulus is a
% two-channel spatiotemporal pattern of light delivered to the olfactory bulb
% through a fiber bundle. See README.md for how a session is run, docs/hardware.md for
% the rig, and docs/architecture.md for the design decisions this file assumes.
%
% Launch it from the Bpod console's launch manager. The first window asks what kind
% of session this is (D11):
%   Behaviour  the task: setup dialog, trial loop, runtime window and online plots
%   Sleep      a home-cage sleep recording: a sleep barcode, then sync pulses on a
%              clock and, if chosen, test pulses of light on channels A and B through
%              PulsePal, with its own setup dialog, test-pulse designer and plots
%              (lum.sleep.run, D13)
%   EphysCalibration  light pulses stepping through intensities and paired-pulse
%              intervals, for input-output curves and paired-pulse ratios on the probe;
%              run by lum.sleep.run too, with its own dialog and barcode (D18)
% The Doric LED driver starts connecting as the protocol launches, so the setup
% dialogs can use it (their Doric LED tab); each session sets its channels up (D17).
% Each kind runs end to end under Bpod('EMU') on a machine with no hardware, with working
% GUI, plots and data saving; hardware calls fall back to shims that log what they
% would have done. The data file records which kind it was, in Data.Session.Type.
%
% This file is deliberately thin. It sequences a session and owns nothing else:
%   setup      settings, preflight, the LED connecting, session type, stimulus set,
%              devices, video, sounds, windows, barcode
%   trial loop build and upload the next trial as this one starts (an LED current or
%              PulsePal program it needs waits for this one's ITI), run, mark the
%              camera clock, score, record, plot, save
%   teardown   save the plots as an image, merge the analog stream, write the final
%              file, keep the settings as they ended for the next session, stop the
%              video and add its summary to the file, release devices, then draw the
%              summary plots and write the log from the saved data (lum.report.write)
%
% Everything with logic in it lives in the +lum package, where it can be tested
% without hardware. See lum.buildTrialSM for the state graph, lum.nextTrialSpec for
% the trial-generation policy, lum.pattern.stimulusSet for the stimuli, and
% lum.SessionRunner for how the trial loop works with and without BpodTrialManager.
%
% The tests are in tests/: runLuminoseTests runs them all (docs/repository.md).
%
% See also RigConfig, CheckRig, lum.dev.open, lum.sleep.run, runLuminoseTests

global BpodSystem %#ok<GVMIS> % Bpod's own session object

protocolRoot = fileparts(mfilename('fullpath'));
addpath(fullfile(protocolRoot, 'hardware'));  % Session only; the saved path is untouched
startup = lum.StartupTimes();  % Printed as the first trial starts; Data.Session.Startup

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

%% The Doric LED
% Connecting takes several seconds, so it starts now and runs while the operator chooses
% and sets the session up (lum.dev.openDoricLED). Every way out of the protocol from here
% releases it.
doricLED = openLED(rig, S);
startup.lap('preflight');

%% Session type
if headless
    fprintf('LuminoseFM: headless mode; a %s session with the settings file as-is.\n', ...
            lower(S.Session.Type));
else
    sessionType = lum.gui.SessionTypeDialog('Default', S.Session.Type, 'Subject', subject);
    if isempty(sessionType)
        fprintf('LuminoseFM: session cancelled.\n');
        lum.dev.Flex.discardEmptyAnalogFile();
        releaseLED(doricLED);
        BpodSystem.Status.BeingUsed = 0;
        return
    end
    S.Session.Type = sessionType;
    startup.lap('session type dialog', true);
end
% The cameras' crops are this session type's: a box and a home cage film different places.
S.Camera = lum.dev.Cameras.cropFor(S.Camera, S.Session.Type);

if ismember(S.Session.Type, {'Sleep', 'EphysCalibration'})
    % Everything a sleep or ePhys calibration session holds, the LED included, is
    % released inside lum.sleep.run, so nothing from +lum is left for RunProtocol('Stop')
    % to strand when it removes the path.
    lum.sleep.run(S, rig, subject, headless, doricLED, startup);
    clear doricLED startup
    if BpodSystem.Status.BeingUsed == 1
        RunProtocol('Stop');
    end
    unlinkFromBaseWorkspace();
    announceFinished();
    return
end

%% Behaviour setup
S = lum.pattern.prepareSeed(S);  % A new trial order, unless the settings fix the seed
if ~headless
    [S, accepted] = lum.gui.SetupDialog(S, rig, 'Subject', subject, 'DoricLED', doricLED);
    if ~accepted
        fprintf('LuminoseFM: session setup cancelled.\n');
        lum.dev.Flex.discardEmptyAnalogFile();
        releaseLED(doricLED);
        clear startup
        BpodSystem.Status.BeingUsed = 0;
        return
    end
    S.Camera = lum.dev.Cameras.keepCrop(S.Camera, 'Behaviour');
    SaveProtocolSettings(S);  % So the session can be reproduced or resumed
    startup.lap('setup dialog', true);
end
% Kept, because the console's End button clears BpodSystem.Path.Settings before the
% teardown writes the settings back.
settingsFile = BpodSystem.Path.Settings;

% With video, the barcode and trial pulses are widened until the cameras can read them
% (lum.sync.fitToCameras). The session runs, and records, the fitted values; the settings
% file keeps what was typed.
typedSync = S.Sync;
[S, syncFit] = lum.sync.fitToCameras(S);
if ~isempty(syncFit)
    fprintf('LuminoseFM: sync line widened so the %g Hz cameras can read it: %s.\n', ...
            S.Camera.FrameRate, strjoin(syncFit, ', '));
end

% Validated here as well as in the dialog, so a headless session cannot start on a
% settings file the dialog would have refused. Only the LED is open yet to release.
try
    [stimulusSet, ~, notes] = lum.validateSettings(S, rig);
    % The reward's valve times, from the liquid calibration: a volume the side valves'
    % calibration cannot give, or a side valve with none, refuses the session here.
    lum.valveTimes(S.GUI.RewardAmount, rig.SidePorts);
catch settingsError
    releaseLED(doricLED);
    BpodSystem.Status.BeingUsed = 0;
    rethrow(settingsError);
end
for i = 1:numel(notes)
    fprintf('LuminoseFM: note: %s\n', notes{i});
end
cals = lum.led.calibrations(S);  % Each channel's light path's calibration, or none
ledIntensity = lum.led.intensity(S, cals, 'Behaviour');  % mW/mm2 into mA, per channel
if S.Session.UseOpto && S.Doric.Enabled
    for i = 1:numel(ledIntensity.Notes)
        fprintf('LuminoseFM: note: %s\n', ledIntensity.Notes{i});
    end
end
startup.lap('checks');

%% Hardware
% A session that delivers light refuses to start without PulsePal; one without light runs
% without it, and without the house light PulsePal drives (lum.dev.openPulsePal,
% lum.dev.openHouseLight).
% Bpod runs the protocol file with no try/catch of its own, so the console is released
% here before the error is shown.
try
    devices = lum.dev.open(rig, S, 'DoricLED', doricLED, 'LEDCurrentmA', ledIntensity.CurrentmA);
catch openError
    releaseLED(doricLED);
    BpodSystem.Status.BeingUsed = 0;
    rethrow(openError);
end
clear doricLED  % devices.doricLED from here on
startup.lap('devices');
startup.addParts('devices', devices.openSeconds);

% Video starts before anything is sent to the rig, so the barcode is on it. spincam
% records on threads of its own; the trial loop only marks each trial's end on its clock.
try
    devices.cameras.startRecording(BpodSystem.Path.CurrentDataFile);
catch recordError
    closeDevices(devices);
    BpodSystem.Status.BeingUsed = 0;
    rethrow(recordError);
end
startup.lap('video start');

fprintf('LuminoseFM: %s\n', lum.trainingStageNote(S));
if S.Task.TrainingStage == 1 && S.GUI.CentreRewardAmount > 0 && S.GUI.CentreRewardTrials > 0
    fprintf('LuminoseFM: centre reward %g uL for a completed hold on trials 1 to %d.\n', ...
            S.GUI.CentreRewardAmount, S.GUI.CentreRewardTrials);
end
if S.Session.UseOpto
    fprintf('LuminoseFM: LED channel A %s, channel B %s.\n', ...
            lum.led.describe(cals{1}, devices.doricLED.CurrentmA(1)), ...
            lum.led.describe(cals{2}, devices.doricLED.CurrentmA(2)));
end
fprintf('LuminoseFM: %s\n', lum.HoldShaping.describe(S));
fprintf('LuminoseFM: %s\n', lum.HoldShaping.describeBreak(S));
families = lum.pattern.families();
fprintf('LuminoseFM: stimulus set "%s", %d group(s), %d trial(s) ordered (seed %d)\n', ...
        families(strcmp({families.Name}, stimulusSet.Family)).Label, stimulusSet.nGroups, ...
        stimulusSet.nTrials, stimulusSet.Seed);
fprintf('LuminoseFM: %s\n', lum.pattern.describeShortcuts(stimulusSet.Shortcuts));
if ~stimulusSet.Continuous
    for k = 1:stimulusSet.nPatterns
        fprintf('  %s  P(left) %.2f\n', lum.pattern.describe(lum.pattern.patternAt(stimulusSet, k)), ...
                stimulusSet.PatternPLeft(k));
    end
end

% Everything from here to trial 1 can fail with the devices open and the video recording
% (a sound the module refuses, a window, the barcode, the first trial's valve times), so
% a failure here is torn down as one in the trial loop is: windows closed, video stopped,
% devices released, the console freed, and then the error.
runtime = [];
plots = [];
runner = [];
cameraWindow = [];
ledWindow = [];
try
    sounds = lum.loadSounds(S, devices, stimulusSet);
    devices.hifi.freeze();  % No more USB transfers once the trial loop owns the module

    [cueComponents, stimulusComponents] = lum.stim.build(S);
    startup.lap('sounds');

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
    plots = lum.OnlinePlots(S, stimulusSet, 'Subject', subject, 'HouseLight', devices.houseLight);
    if S.Session.ShowAnalogViewer
        devices.flex.openAnalogViewer();  % Airflow, from the flow meter on Flex1
    end
    if S.Camera.ShowWindow && devices.cameras.canPreview()
        cameraWindow = lum.gui.CameraWindow(devices.cameras, S.Camera, 'Subject', subject);
    end
    if S.Doric.ShowWindow && S.Session.UseOpto
        ledWindow = lum.gui.DoricWindow(devices.doricLED, S, 'Subject', subject, 'Calibrations', cals);
    end
    startup.lap('windows');

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
    startup.lap('barcode');

    %% Session state
    maxTrials = S.Session.MaxTrials;
    history = lum.newHistory(maxTrials);
    data = initialiseDataFields(maxTrials);
    valveCache = struct('amount', NaN, 'times', [0 0], 'centreAmount', NaN, 'centreTime', NaN);
    queue = stimulusSet.TrialPattern;

    % The window in which MATLAB prepares the next trial opens as each trial starts
    % (lum.triggerStates), so the next is uploaded long before this one ends and starts
    % the moment it does (D3). One that needs a device command first is uploaded in the ITI.
    runner = lum.SessionRunner(devices.emulated, lum.triggerStates());
    fprintf('LuminoseFM: running in %s mode, %s runtime window.\n', runner.Mode, lower(windowMode));

    [S, spec, sma, valveCache, queue, context, history] = prepareTrial(S, rig, devices, history, ...
        stimulusSet, queue, sounds, cueComponents, stimulusComponents, 1, valveCache, runtime);
    ledCurrent = changeDevices(context, 1);  % Nothing is running yet
    % What the first trials will deliver is known now, so it is shown before trial 1 starts
    % rather than after it ends.
    plots.showNext(spec, queue);
    runtime.showStatus(lum.trialStatus(0, [], [], spec, stimulusSet));
    nextSpec = spec;
    nextLEDCurrent = ledCurrent;
    % The runtime settings each trial was prepared with, kept beside its spec: the loop
    % syncs S for the next trial before this one is recorded.
    nextGUI = S.GUI;
    startSettings = S;   % As trial 1 was prepared: Data.Session.Settings
    startup.lap('first trial');
    startMemoryGB = matlabMemoryGB();  % What MATLAB holds as trial 1 starts
    memoryWarned = false;
    fprintf('LuminoseFM: %s.\n', startup.describe());
    startupRecord = startup.record();  % Data.Session.Startup, written with trial 1
    clear startup
catch setupError
    abandonSetup(devices, runtime, plots, runner, cameraWindow, ledWindow);
    BpodSystem.Status.BeingUsed = 0;
    rethrow(setupError);
end

%% Trial loop
% Wrapped, because a session that fails part way through must still be torn down:
% Bpod runs the protocol file with no try/catch of its own, so an error thrown from
% here would leave the trial manager's polling timer running, the runtime window and
% plots open, the analog file handle unflushed and the console believing the rig is
% free - which is what the operator sees as a frozen protocol. Whatever went wrong,
% the trials that completed are saved and every device is released below.
stoppedReason = '';
try
    runner.begin(sma);
    for currentTrial = 1:maxTrials
        spec = nextSpec;
        ledCurrent = nextLEDCurrent;
        trialGUI = nextGUI;

        runner.awaitPrepareWindow();
        if BpodSystem.Status.BeingUsed == 0; break; end

        prepareTimer = tic;
        waitsForDevices = false;
        if currentTrial < maxTrials
            [S, nextSpec, sma, valveCache, queue, nextContext, history] = prepareTrial(S, rig, ...
                devices, history, stimulusSet, queue, sounds, cueComponents, stimulusComponents, ...
                currentTrial + 1, valveCache, runtime);
            nextGUI = S.GUI;
            % This trial may still be lit, so an LED current or PulsePal program the next
            % one needs waits for this one's ITI, and the next is uploaded after that.
            waitsForDevices = needsDevices(nextContext);
            nextLEDCurrent = devices.doricLED.CurrentmA;
        else
            nextSpec = [];
        end
        prepareSeconds = toc(prepareTimer);

        sendTimer = tic;
        if currentTrial < maxTrials && ~waitsForDevices
            runner.queue(sma);
        end
        sendSeconds = toc(sendTimer);

        devicesSeconds = 0;
        if waitsForDevices
            % In the ITI the light is over: the commands go out, then the upload, and the next
            % trial starts on time if the ITI covers them (lum.minimumITI, Data.Timing.devices).
            runner.awaitState('ITI');
            if BpodSystem.Status.BeingUsed == 1
                devicesTimer = tic;
                if trialGUI.ITI < lum.minimumITI(S)
                    fprintf(['LuminoseFM: trial %d waits for its LED current or PulsePal program '...
                             'after a %g s ITI; Bpod warns of the dead time once.\n'], ...
                            currentTrial + 1, trialGUI.ITI);
                end
                nextLEDCurrent = changeDevices(nextContext, currentTrial + 1);
                runner.queue(sma);
                devicesSeconds = toc(devicesTimer);
            end
        end

        rawEvents = runner.awaitTrialData();
        arrivedAt = devices.houseLight.sessionTime();  % For the trial's house light level
        cameraTime = NaN;
        if ~isempty(fieldnames(rawEvents))
            % As soon as the trial's events arrive: pairs the trial's end with the video's
            % clock (Data.CameraTime against TrialEndTimestamp).
            cameraTime = devices.cameras.mark('TrialEnd', currentTrial);
        end
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
            BpodSystem.Data.Session = sessionRecord(startSettings, rig, stimulusSet, runner, devices, ...
                                                    startTime, barcode, barcodeSent, windowMode);
            BpodSystem.Data.Session.SyncFit = syncFit;
            BpodSystem.Data.Session.Startup = startupRecord;
        end

        result = lum.scoreTrial(BpodSystem.Data.RawEvents.Trial{currentTrial}, spec, rig);
        history = lum.updateHistory(history, currentTrial, spec, result);
        data = recordTrial(data, currentTrial, spec, result, trialGUI);
        data.CameraTime(currentTrial) = cameraTime;
        data.LEDCurrentA(currentTrial) = ledCurrent(1);
        data.LEDCurrentB(currentTrial) = ledCurrent(2);
        data.HouseLight(currentTrial) = houseLightAtStart(devices.houseLight, currentTrial, arrivedAt);

        plotTimer = tic;
        plots.update(currentTrial, spec, result, nextSpec, queue, trialGUI.RewardAmount);
        runtime.showStatus(lum.trialStatus(currentTrial, spec, result, nextSpec, stimulusSet));
        plotSeconds = toc(plotTimer);

        % Recorded before the save, so the file written this trial already carries this
        % trial's timing. The save's own cost lands in the next file.
        data.Timing.prepare(currentTrial) = prepareSeconds;
        data.Timing.send(currentTrial) = sendSeconds;
        data.Timing.devices(currentTrial) = devicesSeconds;
        data.Timing.plot(currentTrial) = plotSeconds;

        saveTimer = tic;
        if mod(currentTrial, S.Session.SaveEveryNTrials) == 0
            % MATLAB's memory with each save (about 6 ms): a session on 2026-09-25 ended in
            % "Out of memory", and this says when the next one starts to grow.
            data.Timing.memoryGB(currentTrial) = matlabMemoryGB();
            if ~memoryWarned && data.Timing.memoryGB(currentTrial) > max(8, 2 * startMemoryGB)
                memoryWarned = true;
                warning('lum:LuminoseFM:memoryGrowing', ['MATLAB is using %.1f GB, up from %.1f GB '...
                        'at trial 1. If it keeps growing (Data.Timing.memoryGB), end the session '...
                        'before MATLAB runs out of memory.'], ...
                        data.Timing.memoryGB(currentTrial), startMemoryGB);
            end
            BpodSystem.Data = publishTrialFields(BpodSystem.Data, data, currentTrial);
            SaveBpodSessionData;
        end
        data.Timing.save(currentTrial) = toc(saveTimer);
    end
catch sessionError
    % Nothing more may be sent to the state machine, so stop the loop here and let
    % the teardown below save, close and release. The error is shown after the
    % teardown, so the operator reads it with the rig already free.
    stoppedReason = sessionError.message;
    BpodSystem.Status.BeingUsed = 0;
end

%% Teardown
% Every step from here on has to finish before RunProtocol('Stop'), because Stop
% removes the protocol folder from the MATLAB path - and with it the +lum package.
% Anything left holding a lum.* object would then fail in its own destructor. So the
% session is torn down explicitly, in order, and only then handed back to Bpod.
nCompleted = history.nTrials;
summary = 'no trials completed';
% The camera and LED windows first, and never at the console's End button (they are not
% Bpod's protocol figures): the camera window's timer is stopped here, from the protocol,
% not from inside a callback.
closeWindow(cameraWindow, 'camera');
closeWindow(ledWindow, 'LED');
saved = false;
% The plots as the operator last saw them, beside the data file; written before the
% final save so the file can say where the image is.
plotsImage = '';
if nCompleted > 0
    [plotsImage, plotsProblem] = lum.gui.savePlotsImage(plots.Figure, BpodSystem.Path.CurrentDataFile);
    if ~isempty(plotsProblem)
        warning('lum:LuminoseFM:plotsNotSaved', 'The plots were not saved as an image: %s', ...
                plotsProblem);
    end
end
try
    if nCompleted > 0
        data.Timing.memoryGB(nCompleted) = matlabMemoryGB();  % As the session ends
    end
    BpodSystem.Data = publishTrialFields(BpodSystem.Data, data, nCompleted);
    if isfield(BpodSystem.Data, 'Session')
        BpodSystem.Data.Session.PlotsImage = plotsImage;
        BpodSystem.Data.Session.HouseLight = devices.houseLight.record(BpodSystem.Data);
        BpodSystem.Data.Session.DoricLED = lum.led.sessionRecord(S, devices.doricLED, cals, ledIntensity);
        BpodSystem.Data.Session.DeviceLog = deviceLogs(devices);
        BpodSystem.Data.Session.Cameras = devices.cameras.sessionRecord();
        BpodSystem.Data.Session.EndTime = char(datetime('now'), 'yyyy-MM-dd HH:mm:ss');
        BpodSystem.Data.Session.StoppedReason = stoppedReason;
    end
    BpodSystem.Data = devices.flex.mergeAnalogData(BpodSystem.Data);
    if nCompleted > 0
        SaveBpodSessionData;
        saved = true;
        summary = plots.summaryText(nCompleted);
    end
catch teardownError
    % A failure while saving must not cost the operator their devices as well.
    warning('lum:LuminoseFM:teardownFailed', ...
            'Saving the session data failed: %s', teardownError.message);
end
runner.close();

% The settings file chosen in the launch manager was written when the setup dialog was
% accepted; it is written again now, so runtime changes made during the session (reward,
% timing, the house light...) are where the next session starts.
if ~headless
    try
        S = runtime.sync(S);  % Changes typed since the last trial was prepared
    catch
        % Bpod's compact window, already closed by the End button: S is as last synced.
    end
    S.Sync = typedSync;  % What was typed, not what was fitted to the cameras
    S = handOnHold(S, data, nCompleted);  % The next session's hold starts near this one's
    S.Camera = lum.dev.Cameras.keepCrop(S.Camera, 'Behaviour');
    if devices.houseLight.Switchable
        S.Session.HouseLight = devices.houseLight.On;  % Where the operator left it
    end
    if devices.doricLED.isControlled()
        S = lum.led.keepIntensity(S, 'Behaviour', cals, ledIntensity.CurrentmA, ...
                                  devices.doricLED.CurrentmA);  % As changed from the LED window
    end
    saveSettings(settingsFile, S);
end

% The video stops only once the data are saved and the trial manager is closed, so
% everything the data file holds is on it (D14). What the recording summary says is
% then added to the file with a second, small save.
finishVideo(devices, nCompleted, saved);

runtime.close();
plots.close();  % Only hidden by the console's End button, so it could be saved above
closeDevices(devices);
% No lum.* object may outlive Stop: the trial contexts hold the devices too.
clear runner runtime devices plots cueComponents stimulusComponents cameraWindow ledWindow ...
      context nextContext

% The summary plots and the log, from the saved data, once the rig is released: they take a
% few seconds and change nothing in the data file (lum.report.write).
report = [];
if saved
    fprintf(['LuminoseFM: the session is saved and the rig released; writing its summary plots '...
             'and log (a few seconds; leave MATLAB open until the console says the session is '...
             'finished)...\n']);
    report = lum.report.write(BpodSystem.Data, BpodSystem.Path.CurrentDataFile);
end

fprintf('LuminoseFM: session ended after %d trial(s); MATLAB is using %.1f GB.\n', nCompleted, ...
        matlabMemoryGB());
if nCompleted > 0
    fprintf('  %s\n  Data: %s\n', summary, BpodSystem.Path.CurrentDataFile);
end
if ~isempty(report)
    reportFolder = '';
    if ~isempty(report.Plots)
        reportFolder = fileparts(report.Plots{1});
    end
    fprintf('  Summary plots: %d in %s (%.1f s)\n  Log: %s\n', numel(report.Plots), reportFolder, ...
            report.Seconds, report.Log);
    for i = 1:numel(report.Problems)
        warning('lum:LuminoseFM:reportIncomplete', 'Not written: %s', report.Problems{i});
    end
end
if ~headless && nCompleted > 0
    % A desktop MATLAB has twice run out of memory minutes after a session ended; the
    % sampler records what it was doing (lum.watchMemoryAfterSession).
    lum.watchMemoryAfterSession(BpodSystem.Path.CurrentDataFile);
end

% If the loop ran to completion, or ended in an error rather than at the console's
% stop button, end the session the way the stop button does: release the ports, flush
% the serial link, close the protocol figures and let the console show that the rig
% is free. Only a session the operator stopped has had this done for it already.
if BpodSystem.Status.BeingUsed == 1 || ~isempty(stoppedReason)
    RunProtocol('Stop');
end

unlinkFromBaseWorkspace();
announceFinished();

if ~isempty(stoppedReason)
    % After the teardown, so the rig is already free when the operator reads it.
    warning('lum:LuminoseFM:sessionFailed', ...
            'The session ended early: %s', stoppedReason);
end


function [S, spec, sma, valveCache, queue, context, history] = prepareTrial(S, rig, devices, ...
    history, stimulusSet, queue, sounds, cueComponents, stimulusComponents, trialNumber, ...
    valveCache, runtime)
% Everything needed to run one trial but the device commands, done while the previous trial
% runs, perhaps during its light: context carries what changeDevices needs in its ITI.
itiBefore = S.GUI.ITI;
S = runtime.sync(S);
if S.GUI.ITI ~= itiBefore
    % Typed in the runtime window: the tabbed one has said so already, the compact one not.
    [~, itiNote] = lum.minimumITI(S);
    if ~isempty(itiNote)
        warning('lum:LuminoseFM:shortITI', '%s', itiNote);
    end
end

% The centre reward the operator asked for again: its run starts, goes on or ends here,
% and a run that has just ended unticks its box in the runtime window straight away.
[S, history, unticked] = lum.centreRewardAgain(S, history, trialNumber);
if unticked
    S = runtime.sync(S);
end

[spec, queue] = lum.nextTrialSpec(S, stimulusSet, queue, history, trialNumber);
history = lum.HoldShaping.notePrepared(history, spec);  % Shaping grows the next from this one

% Valve times come from the liquid calibration, so they are recomputed only when the
% operator changes the volume rather than on every trial. A volume the calibration
% cannot give (lum.valveTimes) is refused: the reward stays as it was, and the runtime
% window is put back to it.
if valveCache.amount ~= S.GUI.RewardAmount
    try
        [valveCache.times, valveNote] = lum.valveTimes(S.GUI.RewardAmount, rig.SidePorts);
        valveCache.amount = S.GUI.RewardAmount;
        if ~isempty(valveNote)
            fprintf('LuminoseFM: note: reward %g uL: %s\n', valveCache.amount, valveNote);
        end
    catch valveError
        if isnan(valveCache.amount)
            rethrow(valveError);  % The first trial: checked before the session started
        end
        warning('lum:LuminoseFM:rewardKept', 'The reward stays at %g uL: %s', ...
                valveCache.amount, valveError.message);
        S.GUI.RewardAmount = valveCache.amount;
        S = runtime.sync(S);
    end
end
% The centre valve's, only on trials with a centre reward. Without a calibration for it,
% or for a volume it cannot give, the session goes on without the centre reward, and
% says so once per amount.
if spec.CentreReward
    if valveCache.centreAmount ~= S.GUI.CentreRewardAmount
        valveCache.centreAmount = S.GUI.CentreRewardAmount;
        try
            [valveCache.centreTime, valveNote] = lum.valveTimes(S.GUI.CentreRewardAmount, rig.Ports.Centre);
            if ~isempty(valveNote)
                fprintf('LuminoseFM: note: centre reward %g uL: %s\n', valveCache.centreAmount, valveNote);
            end
        catch valveError
            valveCache.centreTime = NaN;
            warning('lum:LuminoseFM:noCentreValveTime', ...
                    ['No centre reward: valve %d cannot give %g uL (%s). '...
                     'Calibrate it from the Bpod console.'], rig.Ports.Centre, ...
                    S.GUI.CentreRewardAmount, valveError.message);
        end
    end
    if ~(valveCache.centreTime > 0)
        spec.CentreReward = false;
        spec.CentreRewardAmount = 0;
    end
end

context = struct('S', S, 'rig', rig, 'devices', devices, 'spec', spec, ...
                 'pattern', lum.pattern.patternAt(stimulusSet, spec.PatternIndex), ...
                 'sounds', sounds, 'cue', {cueComponents}, ...
                 'stimulus', {stimulusComponents}, 'valveTimes', valveCache.times, ...
                 'centreValveTime', valveCache.centreTime);

sma = lum.buildTrialSM(context);


function tf = needsDevices(context)
% Whether the trial prepared in context needs a command sent to a device before it runs: an
% LED current asked for from the LED window, or a component to program (PulsePal's carrier
% before trial 1, the stimulus window being fixed for the session). Rare; such a trial is
% uploaded in this one's ITI.
tf = context.devices.doricLED.hasPending();
components = [context.stimulus, context.cue];
for i = 1:numel(components)
    tf = tf || components{i}.needsConfigure(context);
end


function ledCurrent = changeDevices(context, trialNumber)
% Send what the trial prepared in context needs from the devices, with no light playing:
% any LED current asked for from the LED window, and each component's programming. Returns
% the LED currents on A and B the trial runs at (NaN when the LED is set by hand).
ledCurrent = context.devices.doricLED.applyPending(trialNumber);
components = [context.stimulus, context.cue];
for i = 1:numel(components)
    components{i}.configure(context);
end


function subject = currentSubject()
% The subject the session was launched for in the launch manager, or '' when there is none
% (lum.launchSubject says where Bpod keeps it, and why Status.CurrentSubjectName alone is
% not enough).
global BpodSystem %#ok<GVMIS>
subject = '';
try
    launched = '';
    if isfield(BpodSystem.GUIData, 'SubjectName')
        launched = BpodSystem.GUIData.SubjectName;
    end
    subject = lum.launchSubject(launched, BpodSystem.Status.CurrentSubjectName, ...
                                BpodSystem.Path.CurrentDataFile);
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
data.Timing = struct('prepare', blank, 'send', blank, 'devices', blank, 'plot', blank, ...
                     'save', blank, 'memoryGB', blank);
data.RuntimeSettings = cell(1, maxTrials);


function names = trialSeriesNames()
% Every per-trial series written to the data file, one value per trial. docs/data-format.md
% and emulatorSessionTest list them too; keep all three in step.
names = {'StimulusGroup', 'PatternIndex', 'CorrectSide', 'Choice', 'Correct', 'Rewarded', ...
         'Outcome', 'ReactionTime', 'OptoOn', 'SoundOn', 'HouseLight', 'SyncMode', 'SyncPulseWidth', ...
         'BiasTargetPLeft', 'TrainingStage', 'HoldDuration', 'HoldGrace', 'HoldBreaks', ...
         'HoldAttempts', 'EarlyWithdrawals', 'CameraTime', 'LEDCurrentA', 'LEDCurrentB', ...
         'CentreReward', 'ResponseRetries', 'CentreHoldTime'};


function data = recordTrial(data, trialNumber, spec, result, gui)
% Store one trial. Only scalars and the runtime settings tier (gui: S.GUI as the trial
% was prepared, not as the next one was): the stimulus set, the rig map and the frozen
% settings are stored once per session, and each trial holds indices into them
% (docs/data-format.md).
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
data.EarlyWithdrawals(trialNumber) = result.EarlyWithdrawals;
data.CentreReward(trialNumber) = result.CentreRewarded * spec.CentreRewardAmount;
data.ResponseRetries(trialNumber) = result.ResponseRetries;
data.CentreHoldTime(trialNumber) = result.CentreHoldTime;
data.RuntimeSettings{trialNumber} = gui;


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
record.TriggerStates = runner.TriggerStates;
% Whether a completed hold may end before the light (D21): the trial then waits for the
% light in WaitForLightEnd, timed by the light clock.
record.LightMayOutlastHold = lum.HoldShaping.lightMayOutlastHold(S);
record.RuntimeWindow = windowMode;
record.Emulated = devices.emulated;
record.DevicesAvailable = struct('PulsePal', devices.pulsePal.Available, ...
                                 'HiFi', devices.hifi.Available, ...
                                 'FlexAnalog', devices.flex.hasAnalog(), ...
                                 'FlexSync', devices.flex.hasSync(), ...
                                 'Cameras', devices.cameras.Available, ...
                                 'HouseLight', devices.houseLight.Available, ...
                                 'DoricLED', devices.doricLED.Available);
record.Cameras = devices.cameras.sessionRecord();  % Brought up to date at teardown
record.StartTime = char(startTime, 'yyyy-MM-dd HH:mm:ss');
record.StoppedReason = '';  % Filled in at teardown if the session ended in an error
record.Barcode = struct('Value', barcode.Value, 'Hex', barcode.Hex, 'Kind', barcode.Kind, ...
                        'Sent', barcodeSent, 'Params', barcode.Params);
record.ProtocolVersion = lum.version();
record.LiquidCalibration = liquidCalibration(rig);


function record = liquidCalibration(rig)
% The liquid calibration the valve times came from, for valves 1 to 3 (side and centre
% ports): each valve's measurements (ms, uL) and the fit GetValveTimes uses. Empty when
% Bpod keeps it in a form other than its calibration file's struct.
global BpodSystem %#ok<GVMIS>
record = struct('Valve', {}, 'Table', {}, 'Coeffs', {});
try
    cal = BpodSystem.CalibrationTables.LiquidCal;
catch
    return
end
if ~isstruct(cal)
    return
end
for valve = sort([rig.SidePorts rig.Ports.Centre])
    if numel(cal) >= valve
        record(end+1) = struct('Valve', valve, 'Table', cal(valve).Table, ...
                               'Coeffs', cal(valve).Coeffs); %#ok<AGROW>
    end
end


function logs = deviceLogs(devices)
% What each device did, or would have done. Small, and the only record of an emulated
% session's hardware intent.
logs = struct('PulsePal', {devices.pulsePal.log()}, ...
              'HiFi', {devices.hifi.log()}, ...
              'FlexIO', {devices.flex.log()}, ...
              'Cameras', {devices.cameras.log()}, ...
              'HouseLight', {devices.houseLight.log()}, ...
              'DoricLED', {devices.doricLED.log()});


function finishVideo(devices, nCompleted, saved)
% Stop the video after the final save, then add its summary to the saved file.
global BpodSystem %#ok<GVMIS>
try
    devices.cameras.finishRecording('SessionSaved', nCompleted);
catch cameraError
    warning('lum:LuminoseFM:videoStopFailed', 'Stopping the video failed: %s', cameraError.message);
end
if ~saved || ~isfield(BpodSystem.Data, 'Session') || ~devices.cameras.sessionRecord().Recorded
    return
end
try
    BpodSystem.Data.Session.Cameras = devices.cameras.sessionRecord();
    BpodSystem.Data.Session.DeviceLog.Cameras = devices.cameras.log();
    SaveBpodSessionData;
catch saveError
    warning('lum:LuminoseFM:videoSummaryNotSaved', ...
            'The session is saved, but the video summary could not be added to it: %s', ...
            saveError.message);
end


function on = houseLightAtStart(houseLight, trialNumber, arrivedAt)
% The house light's level as a trial started: from the loopback input's first edge in the
% trial when there is one, otherwise the level PulsePal held when the trial started on
% MATLAB's clock - its data arrived arrivedAt, one trial's length after it started.
global BpodSystem %#ok<GVMIS>
duration = BpodSystem.Data.TrialEndTimestamp(trialNumber) - BpodSystem.Data.TrialStartTimestamp(trialNumber);
fallback = houseLight.levelAt(arrivedAt - duration);
on = lum.dev.HouseLight.levelAtStart(BpodSystem.Data.RawEvents.Trial{trialNumber}.Events, ...
                                     houseLight, fallback);


function S = handOnHold(S, data, nCompleted)
% While shaping grows the hold, the next session starts 10% below the hold this one's last
% trial asked for (lum.HoldShaping.nextSessionStart), written to the settings file with
% the rest.
if nCompleted < 1
    return
end
lastHold = data.HoldDuration(nCompleted);
start = lum.HoldShaping.nextSessionStart(S, lastHold);
if isnan(start)
    return
end
S.GUI.HoldStart = start;
if start < lum.HoldShaping.NextSessionFraction * lastHold - 5e-4
    fprintf(['LuminoseFM: the next session''s hold starts at %g s, the target hold (this '...
             'session''s last: %.3g s).\n'], start, lastHold);
else
    fprintf(['LuminoseFM: the next session''s hold starts at %g s, 10%% below this session''s '...
             'last (%.3g s).\n'], start, lastHold);
end


function gigabytes = matlabMemoryGB()
% The memory MATLAB is using, GB; NaN where MATLAB cannot say (memory is Windows only).
gigabytes = NaN;
try
    usage = memory;
    gigabytes = usage.MemUsedMATLAB / 1e9;
catch
    % Not Windows
end


function saveSettings(settingsFile, ProtocolSettings)
% Write the settings back to the launch manager's settings file, as SaveProtocolSettings
% does but to the file the session started with, warning rather than failing: the
% session's data are already saved.
try
    save(settingsFile, 'ProtocolSettings');
catch settingsError
    warning('lum:LuminoseFM:settingsNotSaved', ...
            'The settings as they ended were not saved for the next session: %s', ...
            settingsError.message);
end


function doricLED = openLED(rig, S)
% The Doric LED, connecting in the background (lum.dev.open with 'Only'). A failure here
% only means the session opens it again later, and says why then.
doricLED = [];
try
    early = lum.dev.open(rig, S, 'Only', 'DoricLED');
    doricLED = early.doricLED;
catch ledError
    warning('lum:LuminoseFM:ledNotOpened', 'The Doric LED could not be opened yet: %s', ledError.message);
end


function releaseLED(doricLED)
% The LED opened at launch, released when the protocol ends before the session has it.
if ~isempty(doricLED)
    doricLED.close();
end


function closeWindow(window, name)
% Close a session window, warning rather than failing: the teardown must go on.
if isempty(window)
    return
end
try
    window.close();
catch closeError
    warning('lum:LuminoseFM:windowNotClosed', 'The %s window did not close cleanly: %s', ...
            name, closeError.message);
end


function abandonSetup(devices, runtime, plots, runner, cameraWindow, ledWindow)
% Undo a setup that failed before trial 1: every window closed, the trial manager
% deleted, the video stopped and every device released, warning rather than failing, so
% the error that caused it is the one the operator reads.
closeWindow(cameraWindow, 'camera');
closeWindow(ledWindow, 'LED');
closeWindow(runtime, 'runtime');
closeWindow(plots, 'plots');
if ~isempty(runner)
    runner.close();
end
closeDevices(devices);  % The cameras' close stops the recording


function announceFinished()
% Tells the operator the teardown is over. MATLAB closed during it can leave the summary
% plots, the log or the memory record unwritten (LUMS0014 2026-10-03: closed as the log was
% written, so no _memory.csv); the data, settings and video are written before them. A
% local function, because it runs after RunProtocol('Stop') has removed +lum from the path.
fprintf('LuminoseFM: the session is finished; MATLAB can be closed.\n');


function unlinkFromBaseWorkspace()
% Takes BpodSystem out of the base workspace as the session ends; the global itself, and
% every function that declares it, are untouched. MATLAB R2025b's Workspace browser
% otherwise works through every change the session made to the BpodSystem object once the
% prompt returns, on a background thread (datatools_view_core, mwwsb_startup_impl), with
% memory in proportion to the session: 30 GB after 2 minutes, 141 GB after 5, and "Out
% of memory." after LUMS0014's 93-minute sessions (found on the rig 2026-09-26; D16 in
% docs/architecture.md). With BpodSystem gone from the base workspace when the prompt
% returns, the browser has nothing to redraw. A local function, because it runs after
% RunProtocol('Stop') has removed +lum from the path.
try
    if evalin('base', 'exist(''BpodSystem'', ''var'')') == 1
        evalin('base', 'clear BpodSystem');
        fprintf(['LuminoseFM: BpodSystem is no longer listed in the base workspace: MATLAB''s '...
                 'Workspace browser runs out of memory on it after a session. EndBpod and the '...
                 'next session work as usual.\n']);
    end
catch
    % No base workspace to tidy (a deployed or unusual MATLAB): nothing to do.
end


function closeDevices(devices)
% Release every device, whatever happened to the session. Safe to call twice: the
% shims' close methods are idempotent.
% The LED and the house light go off before PulsePal, which drives the house light, is released.
names = {'doricLED', 'cameras', 'houseLight', 'pulsePal', 'hifi', 'flex'};
for i = 1:numel(names)
    try
        devices.(names{i}).close();
    catch closeError
        warning('lum:LuminoseFM:closeFailed', ...
                'Could not close %s cleanly: %s', names{i}, closeError.message);
    end
end
