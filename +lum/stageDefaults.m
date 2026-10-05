function [S, changed] = stageDefaults(S, stage)
% lum.stageDefaults applies the session shape a training stage assumes.
%
% Choosing a training stage says what the animal is being asked to learn, and each
% stage has a session that goes with it. Habituation teaches an animal that the
% centre port starts a trial and the side ports pay, before there is anything to
% discriminate: it therefore delivers no light, and air alone during the hold,
% so that the hold is exactly as long and as salient as it will be later while
% carrying no information, and it switches the centre light cue on (on from trial start
% to the end of the hold, the cue's default), unless the centre light is a stimulus
% component. Training and Experiment deliver the light pattern and leave the cue as it
% is.
%
% Strategy correction (D23) follows it as well: Habituation and Experiment switch every part
% off - side pokes before the response ignored, bias correction for side bias without a
% reward floor, a random trial order - since habituation pays both sides and an experiment
% asks every animal for the same trial; Experiment also switches bias correction (strength
% 0) and the run limit (S.Task.MaxSameSide 0) off, which make the side predictable from the
% trials before. Training leaves them as they are. An Experiment session may still switch
% any of them on: nothing refuses it, and each trial records what applied.
%
% Automatic shaping follows the stage too: Habituation and Training switch it on, so the
% centre hold is grown from S.GUI.HoldStart as the animal learns (lum.HoldShaping) - in
% habituation, together with the centre reward (S.GUI.CentreRewardAmount), from a hold
% short enough to be completed on the first visits - and Experiment switches it off,
% because an experiment asks every animal for the same trial.
%
% These are defaults, not a lock. The setup dialog applies them the moment the stage
% is chosen and the operator may change anything afterwards - a habituation session
% with light, or a training session without, is a tick away. Nothing applies them
% during a session: the stage is a pre-session setting (D2).
%
% They are not validated here either. A session whose cue already includes air, for
% instance, cannot also deliver stimulus air (lum.validateSettings' cueClash: both
% would drive the valve during the stimulus), so choosing habituation on top of it
% leaves the dialog showing that message with Start disabled, and the operator
% unticks one of the two. Applying the defaults and then saying what is wrong is
% clearer than quietly changing a second thing they did choose.
%
% Arguments:
%   S      Settings struct
%   stage  Training stage index; defaults to S.Task.TrainingStage
%
% Returns:
%   S        The settings with the stage's defaults applied
%   changed  Cell array naming what was changed, empty when nothing was
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.trainingStageNote, lum.gui.SetupDialog, lum.nextTrialSpec

if nargin < 2 || isempty(stage)
    stage = S.Task.TrainingStage;
end

changed = {};
habituation = isequal(stage, 1);

% Light. Switched off at the whole-session level as well as the runtime one, so a
% habituation session needs no PulsePal at all (lum.dev.openPulsePal).
wantLight = ~habituation;
if ~isequal(logical(S.Session.UseOpto), wantLight)
    S.Session.UseOpto = wantLight;
    changed{end+1} = describe('the light pattern', wantLight);
end
if isfield(S, 'GUI') && isfield(S.GUI, 'OptoOn') && ~isequal(S.GUI.OptoOn == 1, wantLight)
    S.GUI.OptoOn = double(wantLight);
end

% Air, as the stimulus of a habituation trial: on for the whole stimulus window, so
% it costs no global timer (lum.stim.timerCost).
air = strcmp({S.Stimulus.Components.Type}, 'Air');
if any(air)
    k = find(air, 1);
    if ~isequal(logical(S.Stimulus.Components(k).Enabled), habituation)
        S.Stimulus.Components(k).Enabled = habituation;
        changed{end+1} = describe('the stimulus air', habituation);
    end
    if habituation
        S.Stimulus.Components(k).Onset = 0;
        S.Stimulus.Components(k).Duration = S.Stimulus.Duration;
    end
end

% The centre light as the cue, so the animal sees where to poke. Left alone when the
% centre light is a stimulus component, which the cue would clash with (cueClash).
cueLight = find(strcmp({S.Cue.Components.Type}, 'CentreLight'), 1);
stimulusLight = strcmp({S.Stimulus.Components.Type}, 'CentreLight');
if habituation && ~isempty(cueLight) && ~S.Cue.Components(cueLight).Enabled ...
        && ~any([S.Stimulus.Components(stimulusLight).Enabled])
    S.Cue.Components(cueLight).Enabled = true;
    changed{end+1} = describe('the centre light cue', true);
end

% Shaping: on in habituation and training (stages 1 and 2), never in an experiment (3).
if isscalar(stage) && ismember(stage, 1:3)
    wantShaping = stage ~= 3;
    if ~isequal(logical(S.Task.AutoShaping), wantShaping)
        S.Task.AutoShaping = wantShaping;
        changed{end+1} = describe('automatic shaping', wantShaping);
    end
end

% Strategy correction: off in habituation and in an experiment, as it was in training.
if isequal(stage, 1) || isequal(stage, 3)
    [S, changed] = strategyOff(S, changed, isequal(stage, 3));
end


function [S, changed] = strategyOff(S, changed, experiment)
% Every strategy correction part off; in an experiment, bias correction and the run limit too.
if ~isfield(S, 'GUI')
    return
end
off = {'SidePokeBeforeChoice', 1; 'BiasCorrectFor', 1; 'BiasRewardFloor', 0; 'TrialOrder', 1};
wasOn = false;
for i = 1:size(off, 1)
    if isfield(S.GUI, off{i, 1}) && ~isequal(S.GUI.(off{i, 1}), off{i, 2})
        S.GUI.(off{i, 1}) = off{i, 2};
        wasOn = true;
    end
end
if wasOn
    changed{end+1} = 'strategy correction off';
end
if ~experiment
    return
end
if isfield(S.GUI, 'BiasCorrection') && S.GUI.BiasCorrection ~= 0
    S.GUI.BiasCorrection = 0;
    changed{end+1} = 'bias correction off';
end
if S.Task.MaxSameSide ~= 0
    S.Task.MaxSameSide = 0;
    changed{end+1} = 'the run limit off';
end


function text = describe(what, on)
% 'the light pattern on' / 'the light pattern off'.
if on
    text = sprintf('%s on', what);
else
    text = sprintf('%s off', what);
end
