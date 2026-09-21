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
%   .Retry      True if the animal may try again: an incorrect choice that is not
%               punished sends it back to the response window, where the correct
%               port still pays. Always false for an early withdrawal, whose retry
%               is decided by S.Task.OnHoldBreak.
%
% What each setting means for an incorrect choice:
%   not punished        RetryResponse, then the response window again (started anew);
%                       the correct port rewards, the wrong one retries again. The
%                       default.
%   Timeout             IncorrectChoice for PunishTimeout seconds, no reward, then the
%                       inter-trial interval and the next trial.
%   White noise         IncorrectChoice while the noise plays, no reward, then the next
%                       trial.
%   Timeout + noise     IncorrectChoice for the timeout (at least as long as the noise),
%                       with the noise at its start, no reward, then the next trial.
% lum.buildTrialSM stretches the state to the noise's length, because the ITI stops
% the sound module.
%
% The state graph does not change with these settings: RetryResponse and
% IncorrectChoice exist in every trial, and an unpunished early withdrawal passes
% through EarlyWithdrawal with a zero timer and no sound. That keeps the trial-flow
% contract intact, so scoring and analysis are the same whatever the punishment
% settings were.
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

punishment = struct('Applies', applies, 'Timeout', 0, 'PlayNoise', false, ...
                    'Retry', ~applies && strcmp(event, 'IncorrectChoice'));
if ~applies
    return
end

if ismember(S.GUI.PunishType, [TYPE_TIMEOUT, TYPE_BOTH])
    punishment.Timeout = S.GUI.PunishTimeout;
end
punishment.PlayNoise = ismember(S.GUI.PunishType, [TYPE_NOISE, TYPE_BOTH]);
