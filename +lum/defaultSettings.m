function S = defaultSettings()
% lum.defaultSettings returns the LuminoseFM settings struct with every field set.
%
% The struct has two tiers, split by when a parameter may legally change
% (architecture decision D2):
%
%   Pre-session tier - S.Meta, S.Session, S.Task, S.Cue, S.Stimulus, S.Left,
%   S.Right, S.Light, S.Doric, S.Sound, S.Camera, S.Sync, S.Sleep, S.Ephys. Chosen once in
%   the setup dialog (or the sleep or ePhys calibration setup dialog), frozen for the
%   session, and stored once in the data file. Changing any of these mid-session would
%   make the session's data uninterpretable, so nothing in the runtime window can touch
%   them. The one exception is the LED intensity (S.Doric.IrradiancemWmm2 or CurrentmA,
%   and a sleep session's test pulses'), which the LED window changes between trials or
%   blocks and each trial or gate of light records (D17).
%
%   S.Session.Type says which kind of session the settings were last used for,
%   'Behaviour', 'Sleep' or 'EphysCalibration' (D11, D18); the chooser shown at launch
%   starts on it. S.Sleep is read only by sleep sessions, S.Ephys only by ePhys
%   calibration sessions, and the behaviour tiers only by behaviour ones.
%
%   Runtime tier - S.GUI, with S.GUIMeta, S.GUIPanels and S.GUITabs describing it
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
%                   across trials. The family decides what they are (A only and B
%                   only, pairs of amounts, counts of flashes, words...).
%   pattern         The light one trial delivers: joint states of A and B over the
%                   stimulus window. Trials of a group share a pattern, unless the
%                   family gives every trial its own (Generator.Continuous).
%   stimulus window S.Stimulus.Duration, from stimulus onset.
%   hold            The centre-port hold, from the poke: the stimulus latency, then
%                   the stimulus window and the post-stimulus hold, or a fixed or
%                   growing hold from stimulus onset. The light pattern plays to its
%                   end after a hold shorter than it.
%   latency         S.Stimulus.Latency, from the poke to stimulus onset.
%   centre          British spelling, in identifiers as well as text.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.gui.SetupDialog, lum.gui.runtimeFields, lum.mergeSettings,
%          lum.validateSettings

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
S.Session.Type = 'Behaviour';       % 'Behaviour', 'Sleep' or 'EphysCalibration' (lum.experimentChoices)
S.Session.SettingsVersion = lum.version('release');  % The release that last wrote these settings
% The session's trial order is built for MaxTrials trials, balanced over all of them, and bias
% correction brings trials forward from the rest of it (lum.nextTrialSpec): 3000 leaves it
% trials to draw on in any session an animal runs. Costs nothing measurable per trial.
S.Session.MaxTrials = 3000;
S.Session.SaveEveryNTrials = 5;     % SaveBpodSessionData rewrites the whole file each call
S.Session.UseOpto = true;           % Connect to PulsePal and deliver patterned light
S.Session.UseSound = true;          % Connect to the HiFi module
S.Session.UseSync = true;           % Drive the sync TTL, if Flex2 is a digital output
S.Session.ShowAnalogViewer = true;  % Open Bpod's analog viewer (flow meter) at session start
% The white house light inside the box (PulsePal output 3) as a behaviour session starts. It
% is switched during the session from the online plots' header, at once (lum.dev.HouseLight,
% D15), and the level it ends at is kept for the next session. S.Sleep.HouseLight is the
% sleep session's, so one settings file can light sleep and leave behaviour dark.
S.Session.HouseLight = false;
% Which runtime parameter window to open. 'Automatic' is the tabbed window on the
% rig and Bpod's own single-page window under the emulator.
S.Session.RuntimeWindow = 'Automatic';

%% Pre-session tier: task structure
% Which variant of the task this session runs (lum.experimentChoices). It names the
% kind of stimulus set the session is built around, so a data set can be selected by
% it; picking one in the setup dialog will later fill in that variant's defaults.
S.Task.Variant = 'Familiar/Novel';
S.Task.TrainingStage = 2;           % 1 Habituation, 2 Training, 3 Experiment
S.Task.TrainingStageNames = {'Habituation', 'Training', 'Experiment'};
% Swap which side each group pays: every group's P(left) becomes 1 - P(left), so the
% light that paid left pays right. Applied where the stimulus set is compiled, so the
% set, the plots and every trial record agree on the contingency actually in force;
% S.Task.GroupPLeft keeps the unreversed values, and the set records both.
S.Task.ReverseContingency = false;
% Chance that the left port pays, one value per stimulus group: 1 and 0 give a fixed
% contingency, values in between a psychometric one. Empty means the family's own
% contingency (lum.pattern.generate, FamilyPLeft), which is what a family is designed
% around; the setup dialog and the designer store values here only once the operator
% types them, and forget them when the groups change.
S.Task.GroupPLeft = [];
S.Task.MaxSameSide = 3;             % Cap on consecutive same-side trials; 0 = no cap. Bias
                                    % correction takes precedence on the side it pushes towards
% Automatic shaping (lum.HoldShaping): trains the centre hold from the animal's
% performance. Off by default; choosing the Habituation or Training stage switches it on
% and choosing Experiment switches it off (lum.stageDefaults), and an Experiment session
% never runs with it. HoldShaping says how, while it is on, tuned by S.GUI.Hold*/Grace*.
S.Task.AutoShaping = false;
S.Task.HoldShaping = 'Grow hold';   % lum.HoldShaping.modes()
% What a hold broken beyond its grace does (lum.HoldShaping.breakModes): restart the
% stimulus on the next poke, within S.GUI.HoldWindow of trial start, or end the trial.
S.Task.OnHoldBreak = 'Restart stimulus';
% The centre hold while automatic shaping does not grow it is a runtime setting since
% 0.9.8: S.GUI.HoldLength and S.GUI.FixedHold, on the Timing panel (below).

%% Pre-session tier: cue
% What asks the animal to start a trial. One row per component, each switched on
% independently. An enabled component is on from trial start until the stimulus starts
% - through the wait for the poke and any latency after it - and again whenever a
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
% The light patterns and the order trials come in: a stimulus family and its settings
% (docs/stimulus_family.md). lum.pattern.withGeneratorDefaults documents every field;
% lum.gui.StimulusDesigner edits them, and choosing a family loads its defaults
% (lum.pattern.familyDefaults).
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
% Which fiber bundle is on the animal, and which two of its cables, named by colour, are
% on channels A and B (lum.fiberBundles).
S.Light.Bundle = '2-to-19';
S.Light.Cables = {'blue', 'green'};   % A, then B
% Carrier, delivered by PulsePal while a channel is gated high. One element per
% optical channel, because the two channels drive different LEDs into different
% cables: matching the light they deliver is a per-channel calibration.
S.Light.Carrier = struct( ...
    'Channel',    {1,      2}, ...
    'Frequency',  {20,     20}, ...    % Hz; 0 means constant light while gated
    'PulseWidth', {0.005,  0.005}, ... % Seconds; ignored when Frequency is 0
    'Voltage',    {5,      5});        % Volts: the TTL into the Doric LED driver's input

%% Pre-session tier: the Doric LED (D17)
% The two-channel Doric LED driver (LEDFLS_465_465): LED channel 1 lights channel A and
% channel 2 lights B. With Enabled, the session connects to it through the DoricLED
% package (Folder, or the MATLAB path when '') and puts both channels in external TTL
% mode, so each lights while PulsePal's output into it is high. Without the package, or
% with Enabled off, the driver is used as it was set by hand (its own front panel or
% Doric Neuroscience Studio), which must then be external TTL mode.
% A behaviour session's intensity per channel is IrradiancemWmm2 where the channel's light
% path (the cable on it, measured on that channel) has a calibration
% (lum.led.loadCalibration), turned into the LED current that gives it as the session
% starts; and CurrentmA where it has none (lum.led.intensity). A sleep session keeps its
% own (S.Sleep.TestPulses), an ePhys calibration session its own per step (S.Ephys).
% MaxCurrentmA is the driver's own limit per channel: a current above it is never sent
% (at most 1000 mA, the LED's rating; doric.Channel). It is 1000 mA by default since 0.9.3;
% Doric recommends 700 mA for a 1000 mA LED held on, and the light here is gated.
% CalibrationCurrentsmA are the currents the calibration window's tables start with.
S.Doric.Enabled = true;             % Control the LED from MATLAB (the DoricLED package)
S.Doric.Folder = '';                % Where DoricLED was cloned; '' when it is on the MATLAB path
S.Doric.IrradiancemWmm2 = [8 8];    % Behaviour: irradiance at the fiber tips on A, B, calibrated channels
S.Doric.CurrentmA = [100 100];      % Behaviour: LED current on A, B where not calibrated, mA
S.Doric.MaxCurrentmA = [1000 1000]; % Refuse anything above, mA (the LED's rating)
S.Doric.CalibrationCurrentsmA = 0:100:1000;   % The calibration window's starting currents, mA
S.Doric.ShowWindow = true;          % The LED window during the session

%% Pre-session tier: sound
S.Sound.SamplingRate = 192000;
S.Sound.Amplitude = 0.5;            % Fraction of full scale, 0..1
S.Sound.Attenuation_dB = -20;       % Digital volume, dB full scale, <= 0
S.Sound.NoiseDuration = 0.5;        % White noise burst used as punishment, seconds
S.Sound.SidePokeSoundDuration = 0.15;  % Noise burst on a side poke that costs time (GUI.SidePokeSound), s

%% Pre-session tier: cameras
% Video of the session, recorded by spincam (lum.dev.Cameras) into 'Session Videos'
% beside 'Session Data', every file named after the data file and prefixed with its
% camera's view. spincam is a separate repository: SpinCamFolder is where it was cloned
% ('' when it is already on the MATLAB path). Frames log the cameras' TTL input
% passively (TtlLine), so the sync line (barcode and trial pulses) shows up frame by frame.
S.Camera.Enabled = true;            % Record video
S.Camera.SpinCamFolder = '';
S.Camera.Format = 'avi-mjpeg-mt';   % lum.dev.Cameras.Formats; MJPEG encoded on several cores
S.Camera.FrameRate = 100;           % Hz; avi-mjpeg-mt keeps up with two full frames up to 120
S.Camera.ExposureAuto = true;
S.Camera.ExposureTime = 5000;       % Microseconds, when not automatic
S.Camera.GainAuto = true;
S.Camera.Gain = 0;                  % dB, when not automatic
S.Camera.TtlLine = 'Line0';         % Yellow (signal) and brown (ground) wires
S.Camera.ShowWindow = true;         % Show the cameras during the session
S.Camera.WindowRate = 5;            % Hz; frames copied into MATLAB for the window
% One row per camera, by serial number. Name is the view, the prefix of its files; Roi
% is its crop, [x y width height] in sensor pixels, or [] for the full frame.
S.Camera.Cameras = struct('Serial', {'24226887', '24226657'}, 'Name', {'topview', 'sideview'}, ...
                          'Record', {true, true}, 'Roi', {[], []});
% The crop each session type last used, by serial (lum.dev.Cameras.cropFor, keepCrop): a
% behaviour session and a sleep session film different places. Cameras(k).Roi is the
% session's own, set from here once the session type is chosen.
S.Camera.Crops = lum.dev.Cameras.noCrops();

%% Pre-session tier: sync TTL
% Switched on by S.Session.UseSync, and requires Flex2 configured as a digital
% output. lum.SyncMode documents the three ways trials drive the line.
S.Sync.Mode = lum.SyncMode.JitteredWidth;
S.Sync.ModeNames = lum.SyncMode.allNames();
S.Sync.FixedWidth = 0.050;          % Fixed width: every trial's pulse, seconds
S.Sync.MeanWidth = 0.060;           % Jittered width: average pulse, seconds
S.Sync.WidthJitter = 0.040;         % Jittered width: drawn uniformly within +/- this (20-100 ms)
% One barcode before the first trial identifies the session (lum.sync.barcode). Its
% markers say what kind of session it opens: MarkerWidth for behaviour,
% SleepMarkerWidth for sleep, EphysMarkerWidth for ePhys calibration, so the three are
% told apart on any recording.
% Every width on the sync line here (and in S.Sleep.Sync) is a minimum: with video they are
% widened at session time until the cameras can read them frame by frame
% (lum.sync.fitToCameras). These defaults already fit the 100 Hz default.
S.Sync.Barcode = struct('Enabled', true, 'nBits', 32, 'MarkerWidth', 0.1, ...
                        'ZeroWidth', 0.02, 'OneWidth', 0.05, 'Gap', 0.02, ...
                        'SleepMarkerWidth', 0.2, 'EphysMarkerWidth', 0.3);

%% Pre-session tier: sleep sessions
% A home-cage sleep recording: the session barcode, then sync pulses on the same line
% for DurationMinutes, one every Interval seconds (jittered by up to IntervalJitter
% either side). Pulse widths follow Mode, a lum.SyncMode code - Fixed width or
% Jittered width; task events mean nothing without a task (lum.sleep).
S.Sleep.DurationMinutes = 120;
% The white house light inside the box during a sleep recording (PulsePal output 3). The
% behaviour session's is S.Session.HouseLight; the two are kept apart so one settings
% file can light sleep and darken behaviour. Switched at once from the sleep window.
S.Sleep.HouseLight = false;
S.Sleep.Sync = struct('Mode', lum.SyncMode.JitteredWidth, 'FixedWidth', 0.05, ...
                      'MeanWidth', 0.06, 'WidthJitter', 0.04, ...
                      'Interval', 1, 'IntervalJitter', 0);

% Test pulses: light on channels A and B during a sleep recording, to probe the
% response to it and to change it (lum.sleep.testPulsePlan, D13). As in behaviour, Bpod
% gates BNC1/BNC2 and PulsePal fills each gate: with constant light for a probe, so the
% gate is the pulse, and with a train's pulses for a plasticity train. By default they go
% on for the whole recording (DurationMinutes); a schedule whose last step has a length of
% its own makes the recording last as long as the schedule instead.
%   Probe     One epoch every InterEpochInterval seconds: a single pulse, or a pair of
%             pulses InterPulseInterval apart (Mode 'Paired'). Both intervals are
%             onset to onset; widths and intervals in seconds.
%   Voltage   PulsePal's output into the Doric driver's TTL input, channel A then B,
%             volts
%   IrradiancemWmm2, CurrentmA  The test pulses' intensity on A and B, as behaviour's
%             S.Doric.IrradiancemWmm2 and CurrentmA: irradiance on a calibrated channel,
%             mA on one that is not (lum.led.intensity)
%   Trains    Named plasticity trains, used by name in the schedule, and only when
%             PlasticityTrains is on: bursts of PulsesPerBurst pulses at
%             PulseFrequency, BurstsPerTrain bursts at BurstFrequency, nTrains trains
%             TrainInterval seconds apart (onset to onset). Theta burst is the first.
%   Schedule  Steps run in order from the start of the recording. Kind is 'Probe',
%             'Rest' or a train's name; Channels one of lum.sleep.stepChoices; Minutes
%             the length of a probe or rest step (a train step lasts its trains), or Inf
%             for a last probe or rest step that goes on until the recording ends
%             (lum.sleep.untilRecordingEnds), the default. By default probes alternate:
%             a pair on A, 30 s, a pair on B, 30 s, and so on, so no epoch lights both
%             channels and each evoked response has one source; 'A and B' sends each
%             epoch on both channels at once.
S.Sleep.TestPulses.Enabled = false;
S.Sleep.TestPulses.Voltage = [5 5];
S.Sleep.TestPulses.IrradiancemWmm2 = [2 2];
S.Sleep.TestPulses.CurrentmA = [100 100];
S.Sleep.TestPulses.Probe = struct('Mode', 'Paired', 'PulseWidth', 0.010, ...
                                  'InterPulseInterval', 0.050, 'InterEpochInterval', 30);
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
S.Sleep.TestPulses.Schedule = struct('Kind', {'Probe'}, 'Channels', {'Alternate A and B'}, 'Minutes', {Inf});

%% Pre-session tier: ePhys calibration sessions (D18)
% Light pulses whose intensity or pairing changes step by step, for the recorded
% response: an input-output curve (nLevels steps from the lowest intensity to the
% highest) and a paired-pulse ratio (pairs at one intensity, one step per inter-pulse
% interval, onset to onset). Every step sends Repeats epochs, one every InterEpochInterval
% seconds, on Channels ('A', 'B' or 'A and B', each channel at its own intensity). The LED
% current changes between steps (lum.ephys.plan), so the session needs S.Doric.Enabled.
% Intensities are per channel, A then B, as in behaviour: in mW/mm2 on a channel whose
% light path is calibrated (MinIrradiancemWmm2 to MaxIrradiancemWmm2, levels spaced evenly
% in irradiance; PairedPulse.IrradiancemWmm2), in mA on one that is not (MinmA to MaxmA,
% spaced in mA; PairedPulse.CurrentmA). An irradiance above what the channel gives runs
% at the most it gives (lum.led.currentFor), and MaxmA NaN is the channel's current
% limit, so the curve by default goes from 0 to 12 mW/mm2 or the channel's most, if
% less. Order 'Shuffled' runs the steps of each protocol in an order drawn from Seed.
% Sync pulses and the house light work as in sleep sessions; the session barcode has
% the ePhys marker (S.Sync.Barcode.EphysMarkerWidth).
S.Ephys.Channels = 'A';
S.Ephys.PulseWidth = 0.005;         % Seconds
S.Ephys.InterEpochInterval = 1;     % Seconds, onset to onset
S.Ephys.Repeats = 10;               % Epochs per step
S.Ephys.Order = 'Ascending';        % 'Ascending', 'Descending' or 'Shuffled'
S.Ephys.Seed = 1;
S.Ephys.Voltage = [5 5];            % PulsePal's output into the driver's TTL input, volts
S.Ephys.InputOutput = struct('Enabled', true, 'MinIrradiancemWmm2', [0 0], ...
                             'MaxIrradiancemWmm2', [12 12], 'MinmA', [0 0], 'MaxmA', [NaN NaN], ...
                             'nLevels', 8);
S.Ephys.PairedPulse = struct('Enabled', true, 'IrradiancemWmm2', [8 8], 'CurrentmA', [100 100], ...
                             'Intervals', [0.02 0.03 0.05 0.075 0.1 0.2 0.3 0.5]);
S.Ephys.HouseLight = false;
S.Ephys.Sync = struct('Mode', lum.SyncMode.JitteredWidth, 'FixedWidth', 0.05, ...
                      'MeanWidth', 0.06, 'WidthJitter', 0.04, ...
                      'Interval', 1, 'IntervalJitter', 0);

%% Runtime tier: parameters that may change with an animal in the box
%
% Declared through the three helpers below rather than by hand, so that a
% parameter's value, its label and its allowed range are written once, on one line,
% and cannot drift apart.
S.GUI = struct();
S.GUIMeta = struct();

S = numericParam(S, 'RewardAmount',     3,    'Reward amount (uL)',       [0 100], ...
    'Water per correct choice, in microlitres; the valve time comes from the calibration file.');
S = numericParam(S, 'RewardDelay',      0,    'Reward delay (s)',         [0 60], ...
    ['Seconds between the choice poke and the valve opening. Leaving the port within it '...
     'forfeits the reward (CorrectNoReward); at 0 the valve opens on the next cycle after the poke, '...
     'and a beam flicker in that cycle does not cancel it.']);
S = numericParam(S, 'DrinkingGrace',    0.3,  'Drinking grace (s)',       [0 60], ...
    ['After a reward, how long the animal must stay out of both side ports before the trial '...
     'ends. A side poke within it waits for the animal to leave again and starts it over; no '...
     'more water is given.']);

% Centre reward (lum.nextTrialSpec): water at the centre port when a hold is completed.
% Habituation gives it on the first CentreRewardTrials trials of the session, so a new
% animal learns the centre port is worth visiting; raising the count mid-session extends
% it, 0 ends it. In any stage, ticking CentreRewardAgain gives it again on the next
% CentreRewardAgainTrials trials, and the box unticks itself when they are done
% (lum.centreRewardAgain), for an animal that has stopped coming to the centre port.
S = numericParam(S, 'CentreRewardAmount', 1.2, 'Centre reward (uL)',     [0 100], ...
    ['Water at the centre port as the hold is completed, in microlitres; the valve time '...
     'comes from valve 2''s calibration (1.2 uL is its smallest measurement; less is '...
     'extrapolated). Used on habituation''s first trials and whenever Centre reward again '...
     'is ticked. 0 = no centre reward.']);
S = numericParam(S, 'CentreRewardTrials', 10, 'Centre reward for trials', [0 100000], ...
    ['Habituation only: the centre reward is given on trials 1 to N of the session, when the '...
     'hold is completed; trials with no completed hold count too. Raise it during the session '...
     'to go on, or set 0 to stop. Ignored in Training and Experiment.']);
S = checkboxParam(S, 'CentreRewardAgain', false, 'Centre reward again', ...
    ['Tick to give the centre reward again, in any stage, on the next trials (how many: the '...
     'field below), counted from the next trial prepared. It unticks itself when they are '...
     'done; untick it to stop sooner.']);
S = numericParam(S, 'CentreRewardAgainTrials', 10, 'Again for trials', [1 100000], ...
    ['How many trials one tick of Centre reward again rewards at the centre port. Raise it '...
     'while the box is ticked to go on for longer.']);

% From trial start, across every restart of the stimulus: the trial lapses if no hold
% is completed in time. Was the initiation window before 0.3.
S = numericParam(S, 'HoldWindow',       60,   'Hold window (s)',          [0.1 3600], ...
    ['From trial start: the time the animal has to complete a hold, across every restart '...
     'of the stimulus. The trial lapses when it runs out.']);
% The centre hold while automatic shaping does not grow it (lum.HoldShaping.holdLengths,
% fullHold): 'Whole stimulus', the stimulus window plus PostStimulusHold, or 'Fixed',
% FixedHold seconds from stimulus onset. Runtime settings since 0.9.8 (they were
% S.Task.HoldLength and S.Task.FixedHold), so the operator can set the hold between trials;
% a session with light therefore always keeps the light clock ready for a hold shorter than
% the light (lum.HoldShaping.lightMayOutlastHold, D21).
S = menuParam(S, 'HoldLength', 1, 'Hold without shaping', {'Whole stimulus', 'Fixed'}, ...
    ['The centre hold while automatic shaping does not grow it. Whole stimulus: the stimulus '...
     'window plus the post-stimulus hold. Fixed: the fixed hold below, from stimulus onset; '...
     'shorter than the window, the animal may leave and choose while the light plays on to '...
     'its end. Ignored while automatic shaping grows the hold.']);
S = numericParam(S, 'FixedHold',        0.5,  'Fixed hold (s)',           [0.001 60], ...
    ['Seconds from stimulus onset the animal holds the centre port when Hold without shaping '...
     'is Fixed (plus the latency, if any, before the stimulus). The light pattern always plays '...
     'to its end; a shorter hold only lets the animal leave sooner.']);
S = numericParam(S, 'PostStimulusHold', 0,    'Post-stimulus hold (s)',   [0 60], ...
    ['Seconds the animal keeps holding the centre port after the stimulus window ends, when '...
     'Hold without shaping is Whole stimulus; not used with a fixed or growing hold.']);
S = numericParam(S, 'ResponseWindow',   10,   'Response window (s)',      [0.1 3600], ...
    'From leaving the centre port: the time the animal has to poke a side port.');
S = numericParam(S, 'ITI', lum.minimumITI(), 'Inter-trial interval (s)', [0 3600], ...
    ['Seconds from the end of a trial''s light to the start of the next trial, the same on '...
     'every trial. 0.25 s is the shortest that holds with light: an LED current set in the LED '...
     'window is sent in the ITI, and a shorter one delays the next trial (lum.minimumITI).']);

% Each punishable mistake has its own punishment and timeout (lum.punishmentFor). The codes
% are written into every trial record: append, never renumber.
% An incorrect choice that is not punished (the default) is not the end of the trial:
% the animal may still go to the correct port and be rewarded.
punishments = {'None', 'Timeout', 'White noise', 'Timeout + noise'};  % lum.punishmentFor's codes
S = menuParam(S, 'IncorrectChoicePunishment', 1, 'Incorrect choice', punishments, ...
    ['What choosing the wrong side costs. None: the animal may go on to the correct port for '...
     'its reward, with the response window started again. Timeout, white noise or both: no '...
     'reward, and the trial ends after the timeout below (at least the noise).']);
S = numericParam(S, 'IncorrectChoiceTimeout', 2, 'Incorrect choice timeout (s)', [0 3600], ...
    ['Seconds from a punished incorrect choice to the inter-trial interval, when its '...
     'punishment includes a timeout. The noise plays during it.']);
S = menuParam(S, 'EarlyWithdrawalPunishment', 1, 'Early withdrawal', punishments, ...
    ['What leaving the centre port before the hold is complete costs: nothing, a timeout '...
     '(below), a white noise burst, or both. After it the animal pokes again or the trial '...
     'ends (Break: restart stimulus or end trial). A side poke that ends the trial (Side poke '...
     'before the response: End trial) costs the same.']);
S = numericParam(S, 'EarlyWithdrawalTimeout', 2, 'Early withdrawal timeout (s)', [0 3600], ...
    ['Seconds from a punished early withdrawal until the animal may poke again (or the trial '...
     'ends), when its punishment includes a timeout. The noise plays during it.']);

S = numericParam(S, 'BiasCorrection', 0.5, 'Bias correction (0 = off)', [0 1], ...
    ['Pushes trials towards the side the animal has been avoiding. If it chose left on a '...
     'fraction f of its last choices (Bias window), the next trial pays left with chance '...
     '0.5 + strength x (0.5 - f), kept within 0.1-0.9, by bringing forward a trial that pays '...
     'that side from anywhere later in the session. 0 = off; 1 = full compensation (an animal '...
     'always going left gets right trials 90% of the time). It takes precedence over Max same '...
     'side in a row. Every group is still delivered as often; only the order changes.']);
S = numericParam(S, 'BiasWindow',     20,  'Bias window (choices)',     [1 1000], ...
    ['How many of the most recent choices bias correction looks at. Trials with no choice are '...
     'skipped; nothing is corrected until there are 3 choices.']);

% Strategy correction (D23): levers against habits such as alternating between the side
% ports, all off by default so a session runs as before 0.10.0. Every one is a runtime
% setting, on the runtime window's Strategy tab. Context correction (lum.BiasCorrection)
% widens bias correction to the animal's choice in the same context; blocks (lum.Blocks)
% hold the paying side for runs of trials; a side poke before the response window can delay
% or end the trial, and one in a punishment's timeout restart it, with a sound if asked for
% (lum.buildTrialSM).
S = menuParam(S, 'BiasCorrectFor', 1, 'Correct for', lum.BiasCorrection.Modes, ...
    ['What bias correction reads the animal''s lean from. Side bias: all its recent choices. '...
     'Last choice: its choices after a left and after a right choice, apart, against '...
     'alternating or staying. Last choice and reward: after a rewarded and an unrewarded '...
     'left or right choice, against win-stay and lose-shift too. Needs incorrect choices '...
     'punished (Punishment: Incorrect choice): greyed out while they are retried, and side '...
     'bias is used.']);
S = numericParam(S, 'BiasRewardFloor', 0, 'Reward floor (%)', [0 50], ...
    ['Turns bias correction down when it costs the animal too much water. Over its last '...
     'Reward floor window choices: rewarded on 50% or more, bias correction acts at the '...
     'strength set in Bias correction; at this floor or below, it stops; in between, its '...
     'strength falls in a straight line towards none (floor 40%, strength 0.5, rewarded on '...
     '45%: 0.25). 0 = no floor: bias correction always acts at the set strength. A higher '...
     'floor corrects less.']);
S = numericParam(S, 'BiasRewardWindow', 50, 'Reward floor window (choices)', [1 1000], ...
    ['How many of the most recent choices the reward floor counts rewards over. Trials with '...
     'no choice are skipped.']);
S = menuParam(S, 'TrialOrder', 1, 'Trial order', lum.Blocks.Orders, ...
    ['Random: each trial pays the side its pattern draws, as the order comes. Blocks: the '...
     'paying side is held for a block of trials, then changes; bias correction and Max same '...
     'side in a row do not act. Changed during a session, from the next trial prepared.']);
S = numericParam(S, 'BlockMin', 15, 'Block length, shortest (trials)', [1 1000], ...
    'Blocks: the shortest a block can be, in trials.');
S = numericParam(S, 'BlockMax', 25, 'Block length, longest (trials)', [1 1000], ...
    ['Blocks: the longest a block can be, in trials. With Switch after correct in a row at 0, '...
     'each block''s length is drawn evenly from shortest to longest.']);
S = numericParam(S, 'BlockSwitchAfterCorrect', 0, 'Switch after correct in a row', [0 100], ...
    ['Blocks: end a block once it has run its shortest length and the animal''s last N '...
     'choices in it were correct (or at its longest). 0 = by length only.']);
S = menuParam(S, 'SidePokeBeforeChoice', 1, 'Side poke before the response', ...
    {'Ignore', 'Delay', 'End trial'}, ...
    ['What a side poke does while the trial waits for a centre poke (from trial start, and '...
     'after an early withdrawal). Ignore: nothing. Delay: the cue goes off and centre pokes '...
     'are ignored for the delay below. End trial: the trial ends unrewarded, with the '...
     'punishment of an early withdrawal if those are punished.']);
S = numericParam(S, 'SidePokeDelay', 1, 'Side poke delay (s)', [0 60], ...
    ['Delay: seconds after a side poke before the trial waits for a centre poke again, with '...
     'the cue off. The hold window keeps running.']);
S = menuParam(S, 'TimeoutSidePoke', 1, 'Side poke in a timeout', {'Ignore', 'Restart the timeout'}, ...
    ['What a side poke does during the timeout of a punished incorrect choice or early '...
     'withdrawal. Ignore: nothing. Restart the timeout: a poke at the side port other than '...
     'the one the animal was last in starts the timeout again from its beginning; a poke back '...
     'into the same port does not, so a nose moving in and out of a port is not counted.']);
S = checkboxParam(S, 'SidePokeSound', false, 'Sound on a side poke that costs time', ...
    ['Plays a short noise burst (Sound output: side-poke sound) on each side poke that delays '...
     'the trial, ends it, or restarts a timeout, so the animal hears which poke cost it '...
     'time. A punishment noise playing then stops. Needs Play sounds.']);

% Hold shaping (lum.HoldShaping). Used only while S.Task.AutoShaping is on.
S = numericParam(S, 'HoldStart',   0.2, 'Hold at start (s)',            [0 60], ...
    ['Automatic shaping: the centre hold asked for on the first trial. After a session that '...
     'grew the hold, the settings file holds 90% of its last trial''s hold here (never past '...
     'the target); type another value to start elsewhere.']);
S = numericParam(S, 'HoldGrowth',  1,   'Hold growth per trial (%)',    [0 100], ...
    'Automatic shaping: how much longer the hold gets after each trial on which it was completed.');
S = numericParam(S, 'HoldTarget',  0.6, 'Target hold (s)',              [0 60], ...
    ['Automatic shaping: the hold stops growing here. It may be shorter than the stimulus '...
     'window: the light pattern plays to its end whether or not the hold lasts that long.']);
S = numericParam(S, 'HoldStepBackAfter', 10, 'Step back after N early withdrawals', [0 1000], ...
    ['Automatic shaping: after this many early withdrawals at one hold, with no completed hold '...
     'in between, the hold steps back one growth step so the animal can go on learning. '...
     '0 = never step back.']);
S = numericParam(S, 'GraceStart',  0.3, 'Break grace at start (s)',     [0 10], ...
    'Automatic shaping: the longest break in the hold forgiven on the first trial.');
S = numericParam(S, 'GraceShrink', 5,   'Grace shrink per trial (%)',   [0 100], ...
    'Automatic shaping: how much shorter the forgiven break gets after each completed hold.');
S = numericParam(S, 'GraceTarget', 0,   'Target break grace (s)',       [0 10], ...
    'Automatic shaping: the grace stops shrinking here; 0 is an unbroken hold.');

S = checkboxParam(S, 'OptoOn',  true, 'Deliver light', ...
    'Untick to run trials without the light pattern, for as long as it stays unticked.');
S = checkboxParam(S, 'SoundOn', true, 'Play sounds', ...
    'Untick to run trials silently, for as long as it stays unticked.');
S = numericParam(S, 'PortLightIntensity', 100, 'Port light brightness (0-255)', [0 255], ...
    'PWM brightness of the port lights: centre cue, side lights and guide lights.');

% Panel order is the order the windows lay them out in; tabs group panels in the
% tabbed runtime window (Bpod's own window shows the panels on one page).
S.GUIPanels.Reward = {'RewardAmount', 'RewardDelay', 'DrinkingGrace'};
S.GUIPanels.CentreReward = {'CentreRewardAmount', 'CentreRewardTrials', 'CentreRewardAgain', ...
                            'CentreRewardAgainTrials'};
S.GUIPanels.Timing = {'HoldLength', 'FixedHold', 'PostStimulusHold', 'HoldWindow', ...
                      'ResponseWindow', 'ITI'};
S.GUIPanels.Punishment = {'IncorrectChoicePunishment', 'IncorrectChoiceTimeout', ...
                           'EarlyWithdrawalPunishment', 'EarlyWithdrawalTimeout'};
S.GUIPanels.Bias = {'BiasCorrection', 'BiasWindow', 'BiasCorrectFor', 'BiasRewardFloor', ...
                    'BiasRewardWindow'};
S.GUIPanels.Blocks = {'TrialOrder', 'BlockMin', 'BlockMax', 'BlockSwitchAfterCorrect'};
S.GUIPanels.SidePokes = {'SidePokeBeforeChoice', 'SidePokeDelay', 'TimeoutSidePoke', ...
                         'SidePokeSound'};
S.GUIPanels.Shaping = {'HoldStart', 'HoldGrowth', 'HoldTarget', 'HoldStepBackAfter', ...
                       'GraceStart', 'GraceShrink', 'GraceTarget'};
S.GUIPanels.Delivery = {'OptoOn', 'SoundOn', 'PortLightIntensity'};

S.GUITabs.Trial = {'Reward', 'CentreReward', 'Timing'};
S.GUITabs.Task = {'Punishment', 'Shaping'};
S.GUITabs.Delivery = {'Delivery'};
S.GUITabs.Strategy = {'Bias', 'Blocks', 'SidePokes'};


function side = sideDefaults(toneFrequency)
% The outputs of one side port, all off.
side = struct();
side.Light = struct('Enabled', false, 'Onset', 0, 'Duration', 1);
side.Tone = struct('Enabled', false, 'Frequency', toneFrequency, 'Onset', 0, 'Duration', 0.2);
side.GuideLight = 'Habituation only';   % 'Never', 'Habituation only' or 'Always'


function S = numericParam(S, name, value, label, limits, help)
% A number the operator types. Limits are enforced by both windows. The help is the
% sentence or two the windows show while the operator is on the field.
S.GUI.(name) = value;
S.GUIMeta.(name).Style = 'edit';
S.GUIMeta.(name).Label = label;
S.GUIMeta.(name).Limits = limits;
S.GUIMeta.(name).Help = help;


function S = checkboxParam(S, name, value, label, help)
% An on/off switch. Stored as a double, because Bpod's parameter window reads the
% checkbox's Value back as one and the trial builder compares it with == 1.
S.GUI.(name) = double(value);
S.GUIMeta.(name).Style = 'checkbox';
S.GUIMeta.(name).Label = label;
S.GUIMeta.(name).Help = help;


function S = menuParam(S, name, value, label, items, help)
% A choice from a fixed list, stored as the 1-based index of the chosen item.
S.GUI.(name) = value;
S.GUIMeta.(name).Style = 'popupmenu';
S.GUIMeta.(name).String = items;
S.GUIMeta.(name).Label = label;
S.GUIMeta.(name).Help = help;
