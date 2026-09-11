function [stimulusSet, budget, notes] = validateSettings(S, rig, stimulusSet)
% lum.validateSettings checks that a session can start with these settings.
%
% Everything that has to hold before a session starts, in one place, so that the
% setup dialog's live check, the stimulus designer, the Start button and a headless
% session cannot disagree about what is valid. The expensive part is compiling the
% stimulus set, which is also the thing the session needs, so it is returned.
%
% Arguments:
%   S            Settings struct
%   rig          Channel map from RigConfig; supplies the timer budget and channels
%   stimulusSet  Optional: a set already compiled from these same stimulus settings
%                and timer budget, reused instead of compiled again. The setup
%                dialog passes its last one while only unrelated settings change.
%
% Returns:
%   stimulusSet  The stimulus set (lum.pattern.stimulusSet)
%   budget       Global timers left for light (lum.timerBudget)
%   notes        Cell array of things worth saying that do not stop the session
%
% Errors with a message the operator can act on at the first problem found.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.gui.SetupDialog, lum.gui.StimulusDesigner, lum.timerBudget

notes = {};

if ~ismember(S.Session.Type, lum.experimentChoices().SessionTypes)
    fail('badSessionType', 'The session type must be Behaviour or Sleep.');
end
if ~(S.Session.MaxTrials >= 1 && mod(S.Session.MaxTrials, 1) == 0)
    fail('badTrialCount', 'The maximum number of trials must be a positive integer.');
end
if ~(S.Stimulus.Duration > 0)
    fail('badWindow', 'The stimulus window must be longer than 0 s.');
end
if ~(isscalar(S.Stimulus.Latency) && S.Stimulus.Latency >= 0 && isfinite(S.Stimulus.Latency))
    fail('badLatency', 'The latency from the poke to the stimulus must be 0 s or more.');
end

%% Timers and light
[budget, reserved] = lum.timerBudget(S, rig);
if S.Session.UseOpto && budget < 1
    fail('noTimersForLight', ...
         ['No global timers are left for light: the hold window takes %d, sync %d, the '...
          'hold clock %d and timed stimulus components %d of this machine''s %d.'], ...
         reserved.HoldWindow, reserved.Sync, reserved.HoldClock, reserved.Components, ...
         rig.Limits.GlobalTimers);
end
if nargin < 3 || isempty(stimulusSet)
    stimulusSet = lum.pattern.stimulusSet(S, budget, rig.Opto.nChannels);
end

% Reading the cue is its own check: a negative time after the poke is rejected here
% rather than at the first trial.
cue = lum.cueTiming(S);

%% Stimulus and side components
window = S.Stimulus.Duration;
for component = S.Stimulus.Components(:)'
    checkTiming(component, window, sprintf('Stimulus %s', readable(component.Type)));
end
% A cue line that stays on after the poke and a stimulus component on the same line
% would both drive it during the stimulus.
for part = cue
    if ~ismember(part.Type, {'CentreLight', 'Air'}) || strcmp(part.Mode, 'Off')
        continue
    end
    row = S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, part.Type));
    if ~isempty(row) && row(1).Enabled
        fail('cueClash', ...
             ['The %s is in the cue and stays on after the poke, so it cannot also be a '...
              'stimulus component: both would drive the same line during the stimulus. '...
              'Give it 0 s after the poke on the Cue tab, or untick the stimulus %s on the '...
              'Task tab.'], readable(part.Type), readable(part.Type));
    end
end
choices = lum.experimentChoices();
for side = {'Left', 'Right'}
    checkTiming(S.(side{1}).Light, window, sprintf('%s port light', side{1}));
    checkTiming(S.(side{1}).Tone, window, sprintf('%s tone', side{1}));
    if ~ismember(S.(side{1}).GuideLight, choices.GuideLights)
        fail('badGuideLight', 'The %s guide light must be Never, Habituation only or Always.', ...
             side{1});
    end
end
range = S.Stimulus.ToneFrequencyRange;
if numel(range) ~= 2 || range(1) >= range(2)
    fail('badToneRange', 'The stimulus tone range must go from a lower frequency to a higher one.');
end

%% Sounds fit the module
if S.Session.UseSound
    cueTone = cue(strcmp({cue.Type}, 'Tone'));
    hasCueTail = ~isempty(cueTone) && strcmp(cueTone.Mode, 'Timed');
    stimulusTone = S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, 'Tone'));
    hasStimulusTone = ~isempty(stimulusTone) && stimulusTone.Enabled;
    nSounds = 1 + numel(cueTone) + double(hasCueTail) ...
              + double(hasStimulusTone) * stimulusSet.nGroups ...
              + double(S.Left.Tone.Enabled) + double(S.Right.Tone.Enabled);
    if nSounds > lum.dev.HiFi.MaxSlots
        fail('tooManySounds', ...
             ['This session needs %d sounds (a stimulus tone per group adds %d) but the HiFi '...
              'module holds %d. Use fewer groups or no stimulus tone.'], nSounds, stimulusSet.nGroups, ...
             lum.dev.HiFi.MaxSlots);
    end

    % The module plays one sound at a time, and a new one cuts off the one playing, so
    % two sounds that start with the stimulus would leave only the second.
    inHold = {};
    if ~isempty(cueTone) && ~strcmp(cueTone.Mode, 'Off')
        inHold{end+1} = 'the cue tone (it carries on after the poke)';
    end
    if hasStimulusTone
        inHold{end+1} = 'the stimulus tone';
    end
    if S.Left.Tone.Enabled || S.Right.Tone.Enabled
        inHold{end+1} = 'the side tone';
    end
    if numel(inHold) > 1
        fail('soundClash', ...
             ['The HiFi module plays one sound at a time, and each new sound cuts off the '...
              'one playing, so only one of these can sound during the stimulus: %s. Switch '...
              'the others off, or give the cue tone 0 s after the poke.'], strjoin(inHold, ', '));
    end
end

%% Hold shaping
if lum.HoldShaping.growsHold(S.Task.HoldShaping)
    if S.GUI.HoldTarget <= 0
        fail('badHoldTarget', 'The target hold must be longer than 0 s.');
    end
    fullHold = window + S.GUI.PostStimulusHold;
    if S.GUI.HoldTarget < fullHold
        notes{end+1} = sprintf(['The target hold (%g s) is shorter than the stimulus '...
                                'window plus the post-stimulus hold (%g s): light will be '...
                                'cut short on every trial.'], S.GUI.HoldTarget, fullHold);
    end
end
if ~ismember(S.Task.HoldShaping, lum.HoldShaping.modes())
    fail('badHoldShaping', 'Hold shaping must be one of: %s.', ...
         strjoin(lum.HoldShaping.modes(), ', '));
end
if ~ismember(S.Task.OnHoldBreak, lum.HoldShaping.breakModes())
    fail('badHoldBreak', 'What a broken hold does must be one of: %s.', ...
         strjoin(lum.HoldShaping.breakModes(), ', '));
end
% The hold window runs from trial start, so it has to be longer than the latency and
% the first hold the session asks for, or no trial could ever be completed.
if lum.HoldShaping.growsHold(S.Task.HoldShaping)
    firstHold = min(S.GUI.HoldStart, S.GUI.HoldTarget);
else
    firstHold = window + S.GUI.PostStimulusHold;
end
firstHold = S.Stimulus.Latency + firstHold;
if ~(S.GUI.HoldWindow > firstHold)
    fail('holdWindowTooShort', ...
         ['The hold window (%g s) is not longer than the hold from the poke (%g s), so no '...
          'trial could be completed. Lengthen the hold window.'], S.GUI.HoldWindow, firstHold);
end

%% Sync
switch S.Sync.Mode
    case lum.SyncMode.FixedWidth
        if ~(S.Sync.FixedWidth > 0)
            fail('badSyncWidth', 'The fixed sync pulse must be longer than 0 s.');
        end
    case lum.SyncMode.JitteredWidth
        if ~(S.Sync.WidthJitter < S.Sync.MeanWidth)
            fail('badSyncJitter', ...
                 ['A jitter of %g s around a mean of %g s would ask for pulses of zero width '...
                  'or less. Reduce the jitter below the mean.'], S.Sync.WidthJitter, ...
                 S.Sync.MeanWidth);
        end
end
if S.Sync.Barcode.Enabled
    lum.sync.barcode(0, S.Sync.Barcode);
end
if S.Session.UseSync && ~rig.Available.Sync
    notes{end+1} = sprintf(['%s is not available on this state machine, so no sync pulses '...
                            'and no session barcode will be sent.'], rig.Sync.Channel);
end

%% Light path
bundles = lum.fiberBundles();
bundle = bundles(strcmp({bundles.Name}, S.Light.Bundle));
if isempty(bundle)
    fail('badBundle', 'Unknown fiber bundle ''%s''.', S.Light.Bundle);
end
if bundle.Choose
    cables = S.Light.Cables;
    if numel(cables) ~= 2 || ~all(ismember(cables, bundle.Cables)) || strcmp(cables{1}, cables{2})
        fail('badCables', ...
             'Choose two different cables of the %s bundle for channels A and B.', bundle.Name);
    end
end
carrier = S.Light.Carrier;
[carrier.MaxDuration] = deal(window + lum.stim.OptoPattern.TrainMargin);
lum.dev.PulsePal.validateCarrier(carrier);

%% Experiment record
if S.Meta.Drug.Enabled && isempty(strtrim(S.Meta.Drug.Name))
    fail('noDrugName', 'A drug session needs the drug''s name.');
end


function checkTiming(component, window, what)
% An enabled component must start within the window and last some time.
if ~component.Enabled
    return
end
if component.Onset < 0 || component.Onset >= window
    fail('badOnset', '%s must start within the %g s stimulus window.', what, window);
end
if ~(component.Duration > 0)
    fail('badDuration', '%s must last longer than 0 s.', what);
end


function text = readable(type)
% 'CentreLight' -> 'centre light'.
text = lower(regexprep(type, '(?<=[a-z])([A-Z])', ' $1'));


function fail(id, varargin)
% Raise a settings error with a lum:validateSettings identifier.
error(['lum:validateSettings:' id], varargin{:});
