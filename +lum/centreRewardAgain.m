function [S, history, unticked] = centreRewardAgain(S, history, trialNumber)
% lum.centreRewardAgain starts and ends the centre reward the operator asks for again.
%
% Habituation rewards a completed hold at the centre port on its first trials. Later an
% animal may stop coming to the centre port, and the operator can tick Centre reward
% again (S.GUI.CentreRewardAgain) in the runtime window, in any stage, to give it once
% more on the next S.GUI.CentreRewardAgainTrials trials. This keeps that run: it starts
% at the first trial prepared with the box ticked, it ends when the trials are done, and
% the box is then unticked for the operator, which the runtime windows show at their
% next sync. Unticking the box ends the run sooner; raising the trial count while it
% runs makes it longer. lum.nextTrialSpec reads the run from history.
%
% Called once per trial as it is prepared, before lum.nextTrialSpec.
%
% Arguments:
%   S            Settings, as just synced from the runtime window
%   history      Struct from lum.newHistory; its centreRewardAgainFrom is the run's
%                first trial, 0 when none is running
%   trialNumber  The trial being prepared
%
% Returns S (with the box unticked when a run has just ended), history, and unticked,
% true when this call unticked the box, so the caller can show it at once.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.nextTrialSpec, lum.newHistory, lum.defaultSettings

unticked = false;
if ~isfield(S.GUI, 'CentreRewardAgain') || S.GUI.CentreRewardAgain ~= 1
    history.centreRewardAgainFrom = 0;  % Never ticked, or unticked by the operator
    return
end
from = history.centreRewardAgainFrom;
if from == 0
    history.centreRewardAgainFrom = trialNumber;  % Just ticked: the run starts here
elseif trialNumber >= from + S.GUI.CentreRewardAgainTrials
    history.centreRewardAgainFrom = 0;            % Its trials are done
    S.GUI.CentreRewardAgain = 0;
    unticked = true;
end
