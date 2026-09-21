function [sma, plan] = buildTrialSM(context)
% lum.buildTrialSM assembles the state machine for one trial.
%
% The state graph is fixed. Every trial, in every training stage, with every
% stimulus modality, every kind of hold shaping and either break mode, visits states
% drawn from the same named set; only the OutputActions, the state timers, the global
% timers and where EarlyWithdrawal leads change. Online plots, the outcome scorer and
% downstream analysis all depend on that contract, so a new modality is added as a
% lum.stim.Component, never as a new state.
%
%   TrialStart -> WaitForCentrePoke -> [PreStimulusHold] -> CentreHold
%   (the sync     (the cue is on)       (the latency, when   (the stimulus starts)
%    pulse)                              there is one)
%
%   CentreHold ------------------------> [CentreReward] -----> WaitForCentreExit
%     | leaves the centre port            (habituation's          ^
%     v                                    first trials)          |
%   HoldBreak --- returns within the grace ---> CentreHoldResumed ---+
%     | grace runs out                                (hold clock ends, from any of the three)
%     v
%   EarlyWithdrawal -> WaitForCentrePoke   Restart stimulus: the next poke starts it again
%                   -> ITI                 End trial
%
%   WaitForCentreExit -> WaitForResponse
%                          -> LeftRewardDelay  -> LeftReward  -> DrinkingLeft  -+
%                          -> RightRewardDelay -> RightReward -> DrinkingRight -+-> DrinkingGrace
%                          -> IncorrectChoice  (punished)                        |
%                          -> RetryResponse    (not punished) -> WaitForResponse |
%                          -> NoResponse                                        +-> ITI -> exit
%   WaitForCentrePoke -> NoInitiation         -> ITI   (the hold window ran out)
%   WaitForCentreExit -> NoResponse           -> ITI
%   *RewardDelay      -> WithdrewBeforeReward -> ITI
%
% The cue asks the animal to poke: every cue component is on in WaitForCentrePoke,
% however long the animal takes. With no stimulus latency (S.Stimulus.Latency, the
% default) the poke goes straight to CentreHold, which starts the stimulus; with one,
% the poke enters PreStimulusHold, which lasts the latency with the cue still on, and
% leaving it is a broken hold. PreStimulusHold exists in every trial and is unreachable
% at latency 0, so the poke never waits a state machine cycle it does not need. From
% stimulus onset each cue component stays on until the hold ends, goes off at once, or
% goes off on a global timer part way through the stimulus (lum.cueTiming).
%
% The stimulus is delivered only while the animal holds. Leaving the centre port
% before the hold is complete (beyond any grace) cancels it in EarlyWithdrawal, and
% with S.Task.OnHoldBreak 'Restart stimulus' — the default — the animal is sent back to
% WaitForCentrePoke with the cue on again: its next poke starts the latency and the
% stimulus again, from their beginning. The trial ends when a hold is completed or
% when the hold window runs out.
%
% The sync line is driven by states, not by a global timer (D4). In a pulsed mode
% TrialStart raises it and lasts the pulse's width, and WaitForCentrePoke drops it as
% the cue comes on; in task-event mode TrialStart has no timer, the line stays high
% through the wait for the poke, and the poke drops it. So a pulsed mode delays the
% cue by the pulse width — 20 to 100 ms by default, invisible to an animal whose only sign that
% a trial has started is the cue itself — and the rising edge marks the state machine
% starting in every mode.
%
% The hold window (S.GUI.HoldWindow) is a global timer started in TrialStart, so it
% keeps counting across every restart; a state timer would start again each time the
% animal came back to WaitForCentrePoke. WaitForCentrePoke leaves for NoInitiation on
% the timer ending, or at once on condition 4 (the timer no longer running) when it
% is re-entered after the window ran out during a hold. A hold under way when the
% window ends is allowed to finish.
%
% Without grace shaping, leaving the centre port during CentreHold goes straight to
% EarlyWithdrawal and the hold is CentreHold's own timer; HoldBreak and
% CentreHoldResumed still exist but cannot be reached. With grace, the hold is timed
% by a global timer instead, because a state timer would restart every time the
% animal came back, and the light pattern — its own global timers — carries on
% through a forgiven break.
%
% On the first S.GUI.CentreRewardTrials trials of a habituation session the completed
% hold passes through CentreReward, which opens the centre valve for the calibrated
% time of S.GUI.CentreRewardAmount with the response configuration already up, and then
% goes on to WaitForCentreExit. It is not on the poke's path, so the stimulus starts
% exactly as it would without it; on every other trial it cannot be reached.
%
% An incorrect choice is punished or forgiven by the runtime settings
% (lum.punishmentFor). Punished, it goes to IncorrectChoice, which lasts the timeout
% (and at least the noise, which the ITI would otherwise cut off) and ends the trial
% unrewarded. Not punished, it goes to RetryResponse and straight back to
% WaitForResponse, whose timer starts again: the correct port still pays. RetryResponse
% is not a trigger state (lum.triggerStates), because the trial goes on after it.
%
% The response window opens on the animal *leaving* the centre port, never while its
% nose is still in it. WaitForCentreExit is what enforces that: without it the side
% ports are live while the animal is still holding, and the first beam break as it
% backs out of the centre port is taken as its choice — which on this rig opens a
% reward valve almost the instant the hold ends. It leaves on Port2Out, or at once
% on the centre port already being clear (condition 3), which is how a hold that ends
% during a forgiven break still reaches the response window.
%
% Arguments:
%   context  Struct describing the trial:
%     .S           Settings
%     .rig         Channel map from RigConfig
%     .devices     Device shims from lum.dev.open
%     .spec        Trial spec from lum.nextTrialSpec
%     .pattern     This trial's light pattern (lum.pattern.patternAt)
%     .sounds      Map from sound name to HiFi slot
%     .cue         Cell array of lum.stim.Component for the cue
%     .stimulus    Cell array of lum.stim.Component for the stimulus
%     .valveTimes  Valve open times in seconds, [left right]
%     .centreValveTime  Centre valve open time in seconds for the centre reward;
%                  optional, used only when spec.CentreReward is true
%
% Returns:
%   sma   State machine description, ready for SendStateMachine
%   plan  What was allocated, for tests and the trial record
%
% See also: lum.nextTrialSpec, lum.stim.Component, lum.scoreTrial, lum.HoldShaping,
%           lum.triggerStates

S = context.S;
rig = context.rig;
spec = context.spec;

%% Allocate global timers
% Stimulus components first, then cue components that go off part way through the
% stimulus, the hold clock and the hold window. The sync line takes none. The stimulus
% set was validated against lum.timerBudget when the session started, and that budget
% reserves the others, so this cannot overflow by now.
nextTimer = 1;
[timerGrants, nextTimer] = grantTimers(context.stimulus, context, nextTimer);
[cueGrants, nextTimer] = grantTimers(context.cue, context, nextTimer);
stimulusTimers = [timerGrants{:}];
cueTimers = [cueGrants{:}];

hasGrace = lum.HoldShaping.hasGrace(S);
holdClock = [];
holdEnded = '';
if hasGrace
    holdClock = nextTimer;
    nextTimer = nextTimer + 1;
end

holdWindowTimer = nextTimer;
nextTimer = nextTimer + 1;

% The sync line costs no global timer in any mode: every edge it carries is an
% output action of a state, the way the barcode and a sleep session's pulses are
% (D4). A pulsed mode gives TrialStart the pulse's width as its state timer; a
% task-event mode leaves TrialStart at zero and the line high until the poke.
useSync = S.Session.UseSync && context.devices.flex.hasSync();
syncByTaskEvents = useSync && S.Sync.Mode == lum.SyncMode.TaskEvents;
syncPulse = 0;
if useSync && ~syncByTaskEvents
    syncPulse = spec.SyncPulseWidth;
    if ~isscalar(syncPulse) || ~isfinite(syncPulse) || syncPulse <= 0
        error('lum:buildTrialSM:badSyncPulse', ...
              ['Trial %d asks for a sync pulse of %g s. A pulsed sync mode needs a width '...
               'above 0 s; this should have been caught by lum.validateSettings.'], ...
              spec.TrialNumber, spec.SyncPulseWidth);
    end
end

if nextTimer - 1 > rig.Limits.GlobalTimers
    error('lum:buildTrialSM:timerBudget', ...
          ['Trial %d needs %d global timers but this state machine has %d. This should '...
           'have been caught when the stimulus set was validated.'], ...
          spec.TrialNumber, nextTimer - 1, rig.Limits.GlobalTimers);
end

%% Assemble
sma = NewStateMachine();

% Conditions let states react to something already being true without waiting for
% an event: the drinking states wait for the animal to leave the reward port,
% WaitForCentreExit moves on if the hold ended while the animal was out, and
% WaitForCentrePoke gives up at once if the hold window is already over.
sma = SetCondition(sma, 1, rig.PortLine.Left, 0);
sma = SetCondition(sma, 2, rig.PortLine.Right, 0);
sma = SetCondition(sma, 3, rig.PortLine.Centre, 0);
sma = SetCondition(sma, 4, sprintf('GlobalTimer%d', holdWindowTimer), 0);

for i = 1:numel(context.stimulus)
    sma = context.stimulus{i}.addGlobalTimers(sma, context, timerGrants{i});
end
for i = 1:numel(context.cue)
    sma = context.cue{i}.addGlobalTimers(sma, context, cueGrants{i});
end
if hasGrace
    sma = SetGlobalTimer(sma, 'TimerID', holdClock, 'Duration', spec.HoldDuration, ...
                         'OnsetDelay', 0);
    holdEnded = sprintf('GlobalTimer%d_End', holdClock);
end
sma = SetGlobalTimer(sma, 'TimerID', holdWindowTimer, 'Duration', S.GUI.HoldWindow, ...
                     'OnsetDelay', 0);
holdWindowEnded = sprintf('GlobalTimer%d_End', holdWindowTimer);
% Every mode drives the line from states. A pulsed mode raises it in TrialStart,
% which lasts the pulse, and drops it as the cue comes on: one pulse per trial, of
% a fixed or a near-unique width, so the acquisition devices can align trial by
% trial rather than counting edges from the session start. Task-event mode marks the
% events themselves: high from trial start, low on the poke (in whichever state the
% poke enters), and low again where the animal never pokes at all.
syncHigh = {};
cueStateSync = {};
pokeSync = {};
if useSync
    syncHigh = {rig.Sync.Channel, 1};
    if syncByTaskEvents
        cueStateSync = syncHigh;   % Held high for as long as the animal is asked to poke
        pokeSync = {rig.Sync.Channel, 0};
    else
        cueStateSync = {rig.Sync.Channel, 0};  % The pulse ends as the cue comes on
    end
end

% Every cue component is on while the animal is asked to poke; at the poke each keeps
% going, stops, or is left to its timer; all of them stop when the hold ends. Every
% timer that belongs to the stimulus, the cue's included, starts with the hold and is
% cancelled with it.
%
% Bpod sets every output channel from the state's own row on entering it, so a level
% a state switched on is dropped by the next state unless that state writes it again.
% The sustain lists are exactly that repetition: the same levels, without the timer
% triggers that must fire once and without the play commands that would restart a
% sound (lum.stim.Component.sustainActions). PreStimulusHold sustains the cue through
% the latency; HoldBreak and CentreHoldResumed sustain the stimulus through a
% forgiven break.
centreOff = {rig.LED.Centre, 0};
cueOn = collect(context.cue, context, 'outputActions');
cueAtOnset = collect(context.cue, context, 'onsetActions');
cueOff = collect(context.cue, context, 'stopActions');
cueSustain = collect(context.cue, context, 'sustainActions');
deliveryTimers = [stimulusTimers cueTimers holdClock];
stimulusLevels = lum.mergeActions(cueAtOnset, collect(context.stimulus, context, 'outputActions'));
stimulusSustain = lum.mergeActions(collect(context.cue, context, 'sustainOnsetActions'), ...
                                   collect(context.stimulus, context, 'sustainActions'));
stimulusOn = lum.mergeActions(stimulusLevels, ...
                              lum.timerMaskAction('GlobalTimerTrig', deliveryTimers));
stimulusOff = lum.mergeActions(collect(context.stimulus, context, 'stopActions'), cueOff, ...
                               lum.timerMaskAction('GlobalTimerCancel', deliveryTimers));
guideLights = guideLightActions(S, rig, spec);
guideOff = lightsOff(rig, [1 2]);

restartsOnBreak = lum.HoldShaping.restartsOnBreak(S);
if restartsOnBreak
    afterEarlyWithdrawal = 'WaitForCentrePoke';
else
    afterEarlyWithdrawal = 'ITI';
end

% What each punishable mistake costs is a pair of runtime settings, resolved once
% here. Both states exist whatever the settings say: an unpunished mistake passes
% through with a zero timer and no sound.
earlyWithdrawalPunishment = lum.punishmentFor(S, 'EarlyWithdrawal');
incorrectChoicePunishment = lum.punishmentFor(S, 'IncorrectChoice');

% With restarts, WaitForCentrePoke follows the break and plays the cue tone, which
% would cut the punishment noise off the moment it began; so the noise is let finish
% first. Decided from the settings, not from the module, so the emulator times it the
% same.
% Where the trial ends after a punishment, the ITI stops the sound module, which would
% cut the noise off one cycle after it started; there too the noise is let finish.
earlyWithdrawalTimer = earlyWithdrawalPunishment.Timeout;
hasCueTone = any(cellfun(@(component) isa(component, 'lum.stim.CueTone'), context.cue));
if (~restartsOnBreak || hasCueTone) && playsNoise(context, earlyWithdrawalPunishment)
    earlyWithdrawalTimer = max(earlyWithdrawalTimer, S.Sound.NoiseDuration);
end
incorrectChoiceTimer = incorrectChoicePunishment.Timeout;
if playsNoise(context, incorrectChoicePunishment)
    incorrectChoiceTimer = max(incorrectChoiceTimer, S.Sound.NoiseDuration);
end

% The hold window starts with the trial and is never cancelled or re-triggered.
% TrialStart also carries the sync line's rising edge, and in a pulsed mode it lasts
% the pulse: the cue therefore comes on one pulse width after the state machine
% starts, which is the only thing this state's timer delays.
sma = AddState(sma, 'Name', 'TrialStart', ...
    'Timer', syncPulse, ...
    'StateChangeConditions', {'Tup', 'WaitForCentrePoke'}, ...
    'OutputActions', lum.mergeActions(lum.timerMaskAction('GlobalTimerTrig', holdWindowTimer), ...
                                      syncHigh));

% The cue: on from trial start until the poke, and on again after every hold that broke
% when breaks restart the stimulus. It has no timer of its own: the hold window decides
% when it gives up.
latency = S.Stimulus.Latency;
if latency > 0
    afterPoke = 'PreStimulusHold';
else
    afterPoke = 'CentreHold';
end
sma = AddState(sma, 'Name', 'WaitForCentrePoke', ...
    'Timer', 0, ...
    'StateChangeConditions', {rig.PokeIn.Centre, afterPoke, ...
                              holdWindowEnded, 'NoInitiation', 'Condition4', 'NoInitiation'}, ...
    'OutputActions', lum.mergeActions(cueOn, cueStateSync));

% The latency: the animal holds with the cue still on, and nothing of the stimulus has
% started. Leaving is a broken hold, never forgiven by grace, which is timed from
% stimulus onset. Like the hold, it may finish after the hold window ends.
sma = AddState(sma, 'Name', 'PreStimulusHold', ...
    'Timer', latency, ...
    'StateChangeConditions', {rig.PokeOut.Centre, 'EarlyWithdrawal', 'Tup', 'CentreHold'}, ...
    'OutputActions', lum.mergeActions(cueSustain, pokeSync));

% The hold from stimulus onset, entered on the poke or at the end of the latency. The
% hold is the same length whether or not light is delivered, so that its duration never
% tells the animal what kind of trial it is on.
% Every entry triggers the stimulus from its beginning, which is what restarts it
% after a break.
% A completed hold goes to the centre reward on the trials that have one, and straight
% to the wait for the centre exit on all others.
centreValveTime = 0;
if isfield(spec, 'CentreReward') && spec.CentreReward
    centreValveTime = context.centreValveTime;
    if ~isscalar(centreValveTime) || ~isfinite(centreValveTime) || centreValveTime <= 0
        error('lum:buildTrialSM:badCentreValveTime', ...
              ['Trial %d asks for a centre reward but the centre valve time is %g s. '...
               'LuminoseFM drops the centre reward when valve 2 has no calibration.'], ...
              spec.TrialNumber, centreValveTime);
    end
    holdDone = 'CentreReward';
else
    holdDone = 'WaitForCentreExit';
end

if hasGrace
    holdTransitions = {rig.PokeOut.Centre, 'HoldBreak', holdEnded, holdDone};
    holdTimer = 0;
    breakTransitions = {rig.PokeIn.Centre, 'CentreHoldResumed', ...
                        holdEnded, holdDone, 'Tup', 'EarlyWithdrawal'};
    breakTimer = spec.HoldGrace;
    resumedTransitions = {rig.PokeOut.Centre, 'HoldBreak', holdEnded, holdDone};
else
    holdTransitions = {rig.PokeOut.Centre, 'EarlyWithdrawal', 'Tup', holdDone};
    holdTimer = spec.HoldDuration;
    breakTransitions = {'Tup', 'EarlyWithdrawal'};
    breakTimer = 0;
    resumedTransitions = {'Tup', holdDone};
end

sma = AddState(sma, 'Name', 'CentreHold', ...
    'Timer', holdTimer, ...
    'StateChangeConditions', holdTransitions, ...
    'OutputActions', lum.mergeActions(stimulusOn, pokeSync));

% A forgiven break: nothing is switched off, so the stimulus carries on while the
% animal is out, and nothing is re-triggered when it returns. The levels the hold
% state switched on are written again, because Bpod would otherwise drop them on
% entering this state; the timer triggers are not, so no timer restarts.
sma = AddState(sma, 'Name', 'HoldBreak', ...
    'Timer', breakTimer, ...
    'StateChangeConditions', breakTransitions, ...
    'OutputActions', stimulusSustain);

sma = AddState(sma, 'Name', 'CentreHoldResumed', ...
    'Timer', 0, ...
    'StateChangeConditions', resumedTransitions, ...
    'OutputActions', stimulusSustain);

% Water at the centre port for a completed hold, on the trials that have it. The response
% configuration goes up with it, as in WaitForCentreExit, so the stimulus ends with the
% hold whether or not the reward is given. Leaving the port during it changes nothing:
% WaitForCentreExit then moves on at once (condition 3). Unreachable on other trials.
sma = AddState(sma, 'Name', 'CentreReward', ...
    'Timer', centreValveTime, ...
    'StateChangeConditions', {'Tup', 'WaitForCentreExit'}, ...
    'OutputActions', lum.mergeActions(stimulusOff, centreOff, guideLights, ...
                                      {rig.Valve.Centre, 1}));

% The hold is over and the animal now has to leave the centre port before it can
% answer; the side ports stay dead until it does. The response configuration goes up
% here — stimulus and cue off, centre light off, guide lights on — so that everything is
% ready the moment the animal withdraws. Bounded by the response window, because
% failing to leave is a failure to respond.
sma = AddState(sma, 'Name', 'WaitForCentreExit', ...
    'Timer', S.GUI.ResponseWindow, ...
    'StateChangeConditions', {rig.PokeOut.Centre, 'WaitForResponse', ...
                              'Condition3', 'WaitForResponse', 'Tup', 'NoResponse'}, ...
    'OutputActions', lum.mergeActions(stimulusOff, centreOff, guideLights));

% Reached only from WaitForCentreExit, so the animal is out of the centre port for
% the whole of this state and every side poke here is a fresh entry. The output
% actions repeat WaitForCentreExit's, because Bpod writes every channel from the
% entered state's own row and would otherwise drop the guide lights here.
[leftAction, rightAction] = responseActions(spec, incorrectChoicePunishment);
sma = AddState(sma, 'Name', 'WaitForResponse', ...
    'Timer', S.GUI.ResponseWindow, ...
    'StateChangeConditions', {rig.PokeIn.Left, leftAction, ...
                              rig.PokeIn.Right, rightAction, ...
                              'Tup', 'NoResponse'}, ...
    'OutputActions', lum.mergeActions(stimulusOff, centreOff, guideLights));

% The stimulus stops the moment the hold breaks. With restarts, the punishment (if
% any) runs here and the animal is then free to poke again; otherwise the trial ends.
sma = AddState(sma, 'Name', 'EarlyWithdrawal', ...
    'Timer', earlyWithdrawalTimer, ...
    'StateChangeConditions', {'Tup', afterEarlyWithdrawal}, ...
    'OutputActions', lum.mergeActions(stimulusOff, centreOff, ...
                                      noiseActions(context, earlyWithdrawalPunishment)));

sma = AddState(sma, 'Name', 'LeftRewardDelay', ...
    'Timer', S.GUI.RewardDelay, ...
    'StateChangeConditions', {rig.PokeOut.Left, 'WithdrewBeforeReward', 'Tup', 'LeftReward'}, ...
    'OutputActions', guideOff);

sma = AddState(sma, 'Name', 'RightRewardDelay', ...
    'Timer', S.GUI.RewardDelay, ...
    'StateChangeConditions', {rig.PokeOut.Right, 'WithdrewBeforeReward', 'Tup', 'RightReward'}, ...
    'OutputActions', guideOff);

sma = AddState(sma, 'Name', 'LeftReward', ...
    'Timer', context.valveTimes(1), ...
    'StateChangeConditions', {'Tup', 'DrinkingLeft'}, ...
    'OutputActions', {rig.Valve.Left, 1});

sma = AddState(sma, 'Name', 'RightReward', ...
    'Timer', context.valveTimes(2), ...
    'StateChangeConditions', {'Tup', 'DrinkingRight'}, ...
    'OutputActions', {rig.Valve.Right, 1});

sma = AddState(sma, 'Name', 'DrinkingLeft', ...
    'Timer', 0, ...
    'StateChangeConditions', {'Condition1', 'DrinkingGrace'}, ...
    'OutputActions', {rig.Valve.Left, 0});

sma = AddState(sma, 'Name', 'DrinkingRight', ...
    'Timer', 0, ...
    'StateChangeConditions', {'Condition2', 'DrinkingGrace'}, ...
    'OutputActions', {rig.Valve.Right, 0});

sma = AddState(sma, 'Name', 'DrinkingGrace', ...
    'Timer', S.GUI.DrinkingGrace, ...
    'StateChangeConditions', {'Tup', 'ITI', rig.PokeIn.Left, '>back', rig.PokeIn.Right, '>back'}, ...
    'OutputActions', {});

sma = AddState(sma, 'Name', 'WithdrewBeforeReward', ...
    'Timer', 0, ...
    'StateChangeConditions', {'Tup', 'ITI'}, ...
    'OutputActions', {});

% A punished incorrect choice: no reward, the timeout, the noise, and the trial ends.
% The ITI stops the sound module, so the state lasts at least as long as the noise.
sma = AddState(sma, 'Name', 'IncorrectChoice', ...
    'Timer', incorrectChoiceTimer, ...
    'StateChangeConditions', {'Tup', 'ITI'}, ...
    'OutputActions', lum.mergeActions(guideOff, ...
                                      noiseActions(context, incorrectChoicePunishment)));

% An incorrect choice that is not punished: back to the response window, where the
% correct port still pays. Zero length; it marks the wrong choice in the trial record.
sma = AddState(sma, 'Name', 'RetryResponse', ...
    'Timer', 0, ...
    'StateChangeConditions', {'Tup', 'WaitForResponse'}, ...
    'OutputActions', {});

sma = AddState(sma, 'Name', 'NoResponse', ...
    'Timer', 0, ...
    'StateChangeConditions', {'Tup', 'ITI'}, ...
    'OutputActions', guideOff);

% The hold window ran out without a completed hold: the trial lapses, and the cue
% goes off. The scorer tells a trial whose stimulus never started from one whose holds
% all broke.
sma = AddState(sma, 'Name', 'NoInitiation', ...
    'Timer', 0, ...
    'StateChangeConditions', {'Tup', 'ITI'}, ...
    'OutputActions', lum.mergeActions(cueOff, centreOff, pokeSync));

% The ITI is where the trial manager builds and uploads the next trial, so it is
% also the protocol's slack: every per-trial cost has to fit inside it.
sma = AddState(sma, 'Name', 'ITI', ...
    'Timer', S.GUI.ITI, ...
    'StateChangeConditions', {'Tup', '>exit'}, ...
    'OutputActions', lum.mergeActions(centreOff, guideOff, context.devices.hifi.stopAction()));

plan = struct('timers', {timerGrants}, 'cueTimers', {cueGrants}, 'holdClock', holdClock, ...
              'syncPulse', syncPulse, 'syncDriven', useSync, ...
              'syncByTaskEvents', syncByTaskEvents, 'holdWindowTimer', holdWindowTimer, ...
              'restartsOnBreak', restartsOnBreak, 'nTimersUsed', nextTimer - 1, ...
              'holdDuration', spec.HoldDuration, 'holdGrace', spec.HoldGrace, ...
              'latency', latency, ...
              'earlyWithdrawalTimer', earlyWithdrawalTimer, ...
              'incorrectChoiceTimer', incorrectChoiceTimer, ...
              'centreReward', strcmp(holdDone, 'CentreReward'), ...
              'centreValveTime', centreValveTime, ...
              'earlyWithdrawalPunishment', earlyWithdrawalPunishment, ...
              'incorrectChoicePunishment', incorrectChoicePunishment);


function [grants, nextTimer] = grantTimers(components, context, nextTimer)
% The global timer indices each component asked for, from nextTimer on.
grants = cell(1, numel(components));
for i = 1:numel(components)
    nTimers = components{i}.nTimersNeeded(context);
    grants{i} = nextTimer:(nextTimer + nTimers - 1);
    nextTimer = nextTimer + nTimers;
end


function actions = collect(components, context, method)
% Merge one kind of output action across a list of components. Merged rather than
% concatenated, because AddState refuses a channel named twice.
lists = cell(1, numel(components));
for i = 1:numel(components)
    lists{i} = components{i}.(method)(context);
end
actions = lum.mergeActions(lists{:});


function [leftAction, rightAction] = responseActions(spec, punishment)
% Where each side poke leads, given which sides this trial rewards and whether a wrong
% choice is punished (IncorrectChoice) or may be followed by the right one (RetryResponse).
wrong = 'IncorrectChoice';
if punishment.Retry
    wrong = 'RetryResponse';
end
if ismember(1, spec.RewardedSides)
    leftAction = 'LeftRewardDelay';
else
    leftAction = wrong;
end
if ismember(2, spec.RewardedSides)
    rightAction = 'RightRewardDelay';
else
    rightAction = wrong;
end


function actions = guideLightActions(S, rig, spec)
% Light the rewarded ports during the response window, as each side's GuideLight
% setting asks: never, only during habituation, or always.
actions = {};
for side = spec.RewardedSides
    sideName = rig.Sides{side};
    switch S.(sideName).GuideLight
        case 'Always'
            lit = true;
        case 'Habituation only'
            lit = S.Task.TrainingStage == 1;
        otherwise
            lit = false;
    end
    if lit
        actions = lum.mergeActions(actions, {rig.LED.(sideName), S.GUI.PortLightIntensity});
    end
end


function actions = lightsOff(rig, sides)
% Switch the named side port LEDs off.
actions = {};
for side = sides
    actions = lum.mergeActions(actions, {rig.LED.(rig.Sides{side}), 0});
end


function actions = noiseActions(context, punishment)
% Play the white noise burst, if this punishment includes it and the session has
% sound to play it with.
actions = {};
if ~playsNoise(context, punishment)
    return
end
actions = context.devices.hifi.playAction(context.sounds('Noise'));


function tf = playsNoise(context, punishment)
% Whether this punishment plays the noise on this trial.
tf = punishment.PlayNoise && context.spec.SoundOn && isKey(context.sounds, 'Noise');
