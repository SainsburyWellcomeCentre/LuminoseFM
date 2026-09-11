function note = trainingStageNote(S)
% lum.trainingStageNote says in one line what the training stage does to rewards.
%
% Habituation rewards *both* side ports, whichever way the animal goes, so that it
% learns the side ports pay before it has to learn which one. Watched from the
% console that is indistinguishable from a broken contingency — every poke gets
% water — so the stage and its consequence are stated wherever the operator can
% still act on them: in the setup dialog, and in the session log.
%
% The rule described here is the one lum.nextTrialSpec applies; the two must stay
% in step.
%
% Arguments:
%   S  Settings struct; uses S.Task.TrainingStage and S.Task.TrainingStageNames
%
% Returns a one-line description, e.g.
%   'stage 1 (Habituation): BOTH side ports reward, whichever side is chosen'
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.nextTrialSpec, lum.gui.SetupDialog

stage = S.Task.TrainingStage;
names = S.Task.TrainingStageNames;
if stage >= 1 && stage <= numel(names)
    label = names{stage};
else
    label = 'unknown';
end

if stage == 1
    consequence = 'BOTH side ports reward, whichever side is chosen';
else
    consequence = 'only the correct side port rewards';
end
% ASCII only: this line is printed to the Bpod console and to a terminal, where
% a Windows code page silently drops characters outside it.
note = sprintf('stage %d (%s): %s', stage, label, consequence);
