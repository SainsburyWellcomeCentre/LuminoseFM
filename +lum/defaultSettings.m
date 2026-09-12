function S = defaultSettings()
% lum.defaultSettings returns the LuminoseFM settings struct with every field set.
%
% The struct has two tiers, split by when a parameter may legally change
% (architecture decision D2):
%
%   Pre-session tier — S.Meta, S.Session, S.Task, S.Cue, S.Stimulus, S.Left,
%   S.Right, S.Light, S.Sound, S.Sync, S.Sleep. Chosen once in the setup dialog (or
%   the sleep setup dialog), frozen for the session, and stored once in the data
%   file. Changing any of these mid-session would make the session's data
%   uninterpretable, so nothing in the runtime window can touch them.
%
%   S.Session.Type says which kind of session the settings were last used for,
%   'Behaviour' or 'Sleep' (D11); the chooser shown at launch starts on it. S.Sleep
%   is read only by sleep sessions, and the behaviour tiers only by behaviour ones.
%
%   Runtime tier — S.GUI, with S.GUIMeta, S.GUIPanels and S.GUITabs describing it
%   to the runtime window. Only parameters that are safe to change with an animal
%   in the box. Synced once per trial and recorded per trial, because they really
%   do vary within a session.
%
% Both tiers are editable before the session starts: the setup dialog builds its
% runtime controls from S.GUI, S.GUIMeta and S.GUIPanels, so a runtime parameter is
% declared once here and appears in both windows. The difference between the tiers
% is when they stop being editable, not whether the operator gets to set them.
%
% Naming, used everywhere the operator or an analyst sees these values:
%   channel A / B   The two optical channels: A = BNC1 -> PulsePal OUT1 -> LED ch1,
%                   B = BNC2 -> OUT2 -> LED ch2. Never 'pattern 1/2' or 'ch1/ch2'.
%   group           One stimulus condition of the session; K groups are balanced
%                   across trials. In continuous mode the groups are the two
%                   categories, A-led and B-led.
%   pattern         The light one trial delivers: joint states of A and B over the
%                   stimulus window. Several trials share a pattern within a group.
%   stimulus window S.Stimulus.Duration, from stimulus onset.
%   hold            The centre-port hold, from the poke: the stimulus latency, then
%                   the stimulus window and the post-stimulus hold.
%   latency         S.Stimulus.Latency, from the poke to stimulus onset.
%   centre          British spelling, in identifiers as well as text.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.gui.SetupDialog, lum.gui.runtimeFields, lum.mergeSettings,
%           lum.validateSettings, docs/architecture.md (D2)

%% Pre-session tier: the experiment
S.Meta.Subject = '';                % Filled from the Bpod launch manager at session start
S.Meta.Genotype = 'OSN-ChR';
S.Meta.Notes = '';
S.Meta.Neuropixels = struct('Enabled', false, 'Probe', 'Neuropixels 2.0 (4-shank)', ...
                            'Implant', 'Chronic', 'Target', '', 'Coordinates', '', ...
                            'SerialNumber', '');
S.Meta.EEG = struct('Enabled', false, 'EEGChannels', 2, 'EMGChannels', 1, 'Notes', '');
S.Meta.Drug = struct('Enabled', false, 'Name', '', 'Delivery', 'Intraperitoneal (i.p.)', ...
                     'Dose', 0, 'DoseUnit', 'mg/kg', 'Vehicle', 'Saline', ...
                     'MinutesBeforeSession', 0);

%% Pre-session tier: session composition
S.Session.Type = 'Behaviour';       % 'Behaviour' or 'Sleep' (lum.experimentChoices)
S.Session.MaxTrials = 1000;
S.Session.SaveEveryNTrials = 5;     % SaveBpodSessionData rewrites the whole file each call
S.Session.UseOpto = true;           % Connect to PulsePal and deliver patterned light
S.Session.UseSound = true;          % Connect to the HiFi module
S.Session.UseSync = true;           % Drive the sync TTL, if Flex2 is a digital output
S.Session.ShowAnalogViewer = true;  % Open Bpod's analog viewer (flow meter) at session start
% Which runtime parameter window to open. 'Automatic' is the tabbed window on the
% rig and Bpod's own single-page window under the emulator.
S.Session.RuntimeWindow = 'Automatic';

%% Pre-session tier: task structure
S.Task.TrainingStage = 2;           % 1 Habituation, 2 Training, 3 Experiment
S.Task.TrainingStageNames = {'Habituation', 'Training', 'Experiment'};
% Chance that the left port pays, one value per stimulus group; in continuous mode
% one for A-led and one for B-led patterns. 1 and 0 give a fixed contingency,
% values in between a psychometric one.
S.Task.GroupPLeft = [1 0];
S.Task.MaxSameSide = 3;             % Cap on consecutive same-side trials; 0 = no cap
S.Task.HoldShaping = 'Off';         % lum.HoldShaping.modes(); tuned by S.GUI.Hold*/Grace*
% What a hold broken beyond its grace does (lum.HoldShaping.breakModes): restart the
% stimulus on the next poke, within S.GUI.HoldWindow of trial start, or end the trial.
S.Task.OnHoldBreak = 'Restart stimulus';

%% Pre-session tier: cue
% What asks the animal to start a trial. One row per component, each switched on
% independently. An enabled component is on from trial start until the stimulus starts
% — through the wait for the poke and any latency after it — and again whenever a
% broken hold sends the animal back to poke. From stimulus onset it continues through
% the whole stimulus (ThroughStimulus, the default) or stays on for Duration seconds,
% 0 switching it off as the stimulus starts (lum.cueTiming). Every row is kept even
% when it is off, so enabling one later is a tick.
S.Cue.Components = struct( ...
    'Type',            {'CentreLight', 'Tone', 'Air'}, ...
    'Enabled',         {true,          false,  false}, ...
    'ThroughStimulus', {true,          true,   true}, ...
    'Duration',        {0,             0,      0});
S.Cue.ToneFrequency = 4000;         % Hz

%% Pre-session tier: stimulus
S.Stimulus.Duration = 1.0;          % The stimulus window, seconds from stimulus onset
% Seconds the animal holds the centre port after poking before the stimulus starts. 0
% starts it on the poke. Leaving during it is a broken hold (S.Task.OnHoldBreak).
S.Stimulus.Latency = 0;
% The light patterns and the order trials come in. lum.pattern.withGeneratorDefaults
% documents every field; lum.gui.StimulusDesigner edits them.
S.Stimulus.Generator = lum.pattern.withGeneratorDefaults(struct());
% What else is delivered during the hold, each timed from stimulus onset. A
% component on for the whole window is free; one timed within it costs a global
% timer (lum.stim.timerCost). The stimulus tone plays a different frequency for each
% group, spread across ToneFrequencyRange.
S.Stimulus.Components = struct( ...
    'Type',     {'Air', 'CentreLight', 'Tone'}, ...
    'Enabled',  {false, false,         false}, ...
    'Onset',    {0,     0,             0}, ...
    'Duration', {1,     1,             0.2});
S.Stimulus.ToneFrequencyRange = [6000 16000];

%% Pre-session tier: side-specific outputs
% Delivered on trials rewarded on that side, so they tell the animal where to go.
% Light and tone are timed from stimulus onset. The guide light lights the rewarded
% port during the response window.
S.Left = sideDefaults(8000);
S.Right = sideDefaults(12000);

%% Pre-session tier: light path
% Which fiber bundle is on the animal and, for the 4-to-19 bundle, which two of its
% cables are on channels A and B (lum.fiberBundles).
S.Light.Bundle = '2-to-19';
S.Light.Cables = {'blue', 'green'};
% Carrier, delivered by PulsePal while a channel is gated high. One element per
% optical channel, because the two channels drive different LEDs into different
% cables: matching the light they deliver is a per-channel calibration.
S.Light.Carrier = struct( ...
    'Channel',    {1,      2}, ...
    'Frequency',  {20,     20}, ...    % Hz; 0 means constant light while gated
    'PulseWidth', {0.005,  0.005}, ... % Seconds; ignored when Frequency is 0
    'Voltage',    {5,      5});        % Volts into the Doric LED driver

%% Pre-session tier: sound
S.Sound.SamplingRate = 192000;
S.Sound.Amplitude = 0.5;            % Fraction of full scale, 0..1
S.Sound.Attenuation_dB = -20;       % Digital volume, dB full scale, <= 0
S.Sound.NoiseDuration = 0.5;        % White noise burst used as punishment, seconds

%% Pre-session tier: sync TTL
% Switched on by S.Session.UseSync, and requires Flex2 configured as a digital
% output. lum.SyncMode documents the three ways trials drive the line.
S.Sync.Mode = lum.SyncMode.JitteredWidth;
S.Sync.ModeNames = lum.SyncMode.allNames();
S.Sync.FixedWidth = 0.050;          % Fixed width: every trial's pulse, seconds
S.Sync.MeanWidth = 0.055;           % Jittered width: average pulse, seconds
S.Sync.WidthJitter = 0.045;         % Jittered width: drawn uniformly within +/- this
% One barcode before the first trial identifies the session (lum.sync.barcode). Its
% markers say what kind of session it opens: MarkerWidth for behaviour,
% SleepMarkerWidth for sleep, so the two are told apart on any recording.
S.Sync.Barcode = struct('Enabled', true, 'nBits', 32, 'MarkerWidth', 0.1, ...
                        'ZeroWidth', 0.01, 'OneWidth', 0.03, 'Gap', 0.02, ...
                        'SleepMarkerWidth', 0.2);

%% Pre-session tier: sleep sessions
% A home-cage sleep recording: the session barcode, then sync pulses on the same line
% for DurationMinutes, one every Interval seconds (jittered by up to IntervalJitter
% either side). Pulse widths follow Mode, a lum.SyncMode code — Fixed width or
% Jittered width; task events mean nothing without a task (lum.sleep).
S.Sleep.DurationMinutes = 120;
S.Sleep.Sync = struct('Mode', lum.SyncMode.JitteredWidth, 'FixedWidth', 0.05, ...
                      'MeanWidth', 0.055, 'WidthJitter', 0.045, ...
                      'Interval', 1, 'IntervalJitter', 0);

% Test pulses: light on channels A and B during a sleep recording, to probe the
% response to it and to change it (lum.sleep.testPulsePlan, D13). As in behaviour, Bpod
% gates BNC1/BNC2 and PulsePal fills each gate: with constant light for a probe, so the
% gate is the pulse, and with a train's pulses for a plasticity train. When Enabled,
% the recording lasts as long as the schedule, and DurationMinutes is not used.
%   Probe     One epoch every InterEpochInterval seconds: a single pulse, or a pair of
%             pulses InterPulseInterval apart (Mode 'Paired'). Both intervals are
%             onset to onset; widths and intervals in seconds.
%   Voltage   LED drive into the Doric driver, channel A then B, volts
%   Trains    Named plasticity trains, used by name in the schedule, and only when
%             PlasticityTrains is on: bursts of PulsesPerBurst pulses at
%             PulseFrequency, BurstsPerTrain bursts at BurstFrequency, nTrains trains
%             TrainInterval seconds apart (onset to onset). Theta burst is the first.
%   Schedule  Steps run in order from the start of the recording. Kind is 'Probe',
%             'Rest' or a train's name; Channels one of lum.sleep.stepChoices; Minutes
%             the length of a probe or rest step (a train step lasts its trains).
S.Sleep.TestPulses.Enabled = false;
S.Sleep.TestPulses.Voltage = [5 5];
S.Sleep.TestPulses.Probe = struct('Mode', 'Paired', 'PulseWidth', 0.010, ...
                                  'InterPulseInterval', 0.050, 'InterEpochInterval', 2);
S.Sleep.TestPulses.PlasticityTrains = false;
S.Sleep.TestPulses.Trains = struct( ...
    'Name',           {'Theta burst', 'High frequency'}, ...
    'PulseFrequency', {100,           100}, ...
    'PulseWidth',     {0.005,         0.005}, ...
    'PulsesPerBurst', {4,             100}, ...
    'BurstFrequency', {4,             1}, ...
    'BurstsPerTrain', {10,            1}, ...
    'nTrains',        {5,             4}, ...
    'TrainInterval',  {20,            20});
S.Sleep.TestPulses.Schedule = struct('Kind', {'Probe'}, 'Channels', {'A and B'}, 'Minutes', {240});

%% Runtime tier: parameters that may change with an animal in the box
%
% Declared through the three helpers below rather than by hand, so that a
% parameter's value, its label and its allowed range are written once, on one line,
% and cannot drift apart.
S.GUI = struct();
S.GUIMeta = struct();

S = numericParam(S, 'RewardAmount',     3,    'Reward amount (uL)',       [0 100]);
S = numericParam(S, 'RewardDelay',      0,    'Reward delay (s)',         [0 60]);
S = numericParam(S, 'DrinkingGrace',    0.5,  'Drinking grace (s)',       [0 60]);

% From trial start, across every restart of the stimulus: the trial lapses if no hold
% is completed in time. Was the initiation window before 0.3.
S = numericParam(S, 'HoldWindow',       60,   'Hold window (s)',          [0.1 3600]);
S = numericParam(S, 'PostStimulusHold', 0,    'Post-stimulus hold (s)',   [0 60]);
S = numericParam(S, 'ResponseWindow',   10,   'Response window (s)',      [0.1 3600]);
S = numericParam(S, 'ITI',              1,    'Inter-trial interval (s)', [0 3600]);

% Punishment is two independent choices: which mistakes are punished, and what the
% punishment is. The codes are written into every trial record.
S = menuParam(S, 'PunishCondition', 3, 'Punish on', ...
              {'None', 'Early withdrawal', 'Incorrect choice', 'Both'});
S = menuParam(S, 'PunishType', 3, 'Punishment', ...
              {'Timeout', 'White noise', 'Timeout + noise'});
S = numericParam(S, 'PunishTimeout', 2, 'Timeout (s)', [0 3600]);

S = numericParam(S, 'BiasCorrection', 0.5, 'Bias correction (0 = off)', [0 1]);
S = numericParam(S, 'BiasWindow',     20,  'Bias window (trials)',      [1 1000]);

% Hold shaping (lum.HoldShaping). Used only when S.Task.HoldShaping asks for it.
S = numericParam(S, 'HoldStart',   0.2, 'Hold at start (s)',            [0 60]);
S = numericParam(S, 'HoldGrowth',  5,   'Hold growth per trial (%)',    [0 100]);
S = numericParam(S, 'HoldTarget',  1,   'Target hold (s)',              [0 60]);
S = numericParam(S, 'GraceStart',  0.3, 'Break grace at start (s)',     [0 10]);
S = numericParam(S, 'GraceShrink', 5,   'Grace shrink per trial (%)',   [0 100]);
S = numericParam(S, 'GraceTarget', 0,   'Target break grace (s)',       [0 10]);

S = checkboxParam(S, 'OptoOn',  true, 'Deliver light');
S = checkboxParam(S, 'SoundOn', true, 'Play sounds');
S = numericParam(S, 'PortLightIntensity', 100, 'Port light brightness (0-255)', [0 255]);

% Panel order is the order the windows lay them out in; tabs group panels in the
% tabbed runtime window (Bpod's own window shows the panels on one page).
S.GUIPanels.Reward = {'RewardAmount', 'RewardDelay', 'DrinkingGrace'};
S.GUIPanels.Timing = {'HoldWindow', 'PostStimulusHold', 'ResponseWindow', 'ITI'};
S.GUIPanels.Punishment = {'PunishCondition', 'PunishType', 'PunishTimeout'};
S.GUIPanels.Bias = {'BiasCorrection', 'BiasWindow'};
S.GUIPanels.Shaping = {'HoldStart', 'HoldGrowth', 'HoldTarget', ...
                       'GraceStart', 'GraceShrink', 'GraceTarget'};
S.GUIPanels.Delivery = {'OptoOn', 'SoundOn', 'PortLightIntensity'};

S.GUITabs.Trial = {'Reward', 'Timing'};
S.GUITabs.Task = {'Punishment', 'Bias', 'Shaping'};
S.GUITabs.Delivery = {'Delivery'};


%% Declarations -----------------------------------------------------------------

function side = sideDefaults(toneFrequency)
% The outputs of one side port, all off.
side = struct();
side.Light = struct('Enabled', false, 'Onset', 0, 'Duration', 1);
side.Tone = struct('Enabled', false, 'Frequency', toneFrequency, 'Onset', 0, 'Duration', 0.2);
side.GuideLight = 'Habituation only';   % 'Never', 'Habituation only' or 'Always'


function S = numericParam(S, name, value, label, limits)
% A number the operator types. Limits are enforced by both windows.
S.GUI.(name) = value;
S.GUIMeta.(name).Style = 'edit';
S.GUIMeta.(name).Label = label;
S.GUIMeta.(name).Limits = limits;


function S = checkboxParam(S, name, value, label)
% An on/off switch. Stored as a double, because Bpod's parameter window reads the
% checkbox's Value back as one and the trial builder compares it with == 1.
S.GUI.(name) = double(value);
S.GUIMeta.(name).Style = 'checkbox';
S.GUIMeta.(name).Label = label;


function S = menuParam(S, name, value, label, items)
% A choice from a fixed list, stored as the 1-based index of the chosen item.
S.GUI.(name) = value;
S.GUIMeta.(name).Style = 'popupmenu';
S.GUIMeta.(name).String = items;
S.GUIMeta.(name).Label = label;
