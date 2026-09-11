function punishment = punishmentFor(S, event)
% lum.punishmentFor resolves what a punishable event costs on this trial.
%
% Punishment is configured as two independent runtime choices: which events are
% punished at all, and what the punishment consists of. Keeping them separate
% means the operator can, for example, switch an animal from "timeout only" to
% "timeout and noise" without also changing which mistakes are penalised, and
% either can be changed with an animal in the box.
%
% Arguments:
%   S      Settings struct; uses S.GUI.PunishCondition, PunishType, PunishTimeout
%   event  'IncorrectChoice' or 'EarlyWithdrawal'
%
% Returns:
%   .Timeout    Seconds to hold the animal before the next trial; 0 if none
%   .PlayNoise  True if the white noise burst should be played
%   .Applies    True if this event is punished at all
%
% The state graph does not change with these settings: an unpunished incorrect
% choice still passes through the IncorrectChoice state, with a zero timer and no
% sound, and an unpunished early withdrawal through EarlyWithdrawal.
% That keeps the trial-flow contract intact, so scoring and analysis are the same
% whatever the punishment settings were.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.defaultSettings, lum.buildTrialSM

% Codes match the popupmenu order in lum.defaultSettings. They are written into
% every trial record, so append new options rather than renumbering these.
CONDITION_NONE = 1;
CONDITION_EARLY_WITHDRAWAL = 2;
CONDITION_INCORRECT_CHOICE = 3;
CONDITION_BOTH = 4;

TYPE_TIMEOUT = 1;
TYPE_NOISE = 2;
TYPE_BOTH = 3;

switch event
    case 'IncorrectChoice'
        applies = ismember(S.GUI.PunishCondition, [CONDITION_INCORRECT_CHOICE, CONDITION_BOTH]);
    case 'EarlyWithdrawal'
        applies = ismember(S.GUI.PunishCondition, [CONDITION_EARLY_WITHDRAWAL, CONDITION_BOTH]);
    otherwise
        error('lum:punishmentFor:unknownEvent', ...
              ['Unknown punishable event ''%s''. Use ''IncorrectChoice'' or '...
               '''EarlyWithdrawal''.'], event);
end
applies = applies && S.GUI.PunishCondition ~= CONDITION_NONE;

punishment = struct('Applies', applies, 'Timeout', 0, 'PlayNoise', false);
if ~applies
    return
end

if ismember(S.GUI.PunishType, [TYPE_TIMEOUT, TYPE_BOTH])
    punishment.Timeout = S.GUI.PunishTimeout;
end
punishment.PlayNoise = ismember(S.GUI.PunishType, [TYPE_NOISE, TYPE_BOTH]);
