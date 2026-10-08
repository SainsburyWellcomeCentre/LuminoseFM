function punishment = punishmentFor(S, event)
% lum.punishmentFor resolves what a punishable event costs on this trial.
%
% Each punishable mistake has its own runtime pair: what it costs and how long its timeout
% lasts, so an incorrect choice can cost a timeout while early withdrawals cost nothing,
% or the reverse, and either can be changed with an animal in the box.
%
% Arguments:
%   S      Settings struct; uses S.GUI.IncorrectChoicePunishment, IncorrectChoiceTimeout,
%          EarlyWithdrawalPunishment, EarlyWithdrawalTimeout and TimeoutSidePoke
%   event  'IncorrectChoice', 'EarlyWithdrawal' or 'SidePokeBeforeChoice' (a side poke
%          before the response window that ends the trial, S.GUI.SidePokeBeforeChoice
%          'End trial': it costs what an early withdrawal does, since both answer before
%          the response window opens)
%
% Returns:
%   .Timeout    Seconds to hold the animal before the next trial (or poke); 0 if none
%   .PlayNoise  True if the white noise burst should be played
%   .Applies    True if this event is punished at all
%   .Retry      True if the animal may try again: an incorrect choice that is not
%               punished sends it back to the response window, where the correct
%               port still pays. Always false for an early withdrawal, whose retry
%               is decided by S.Task.OnHoldBreak, and for a side poke before the
%               response window, which ends the trial.
%   .RestartOnSidePoke  True if a poke at the other side port during the timeout starts it
%               again (S.GUI.TimeoutSidePoke 'Restart the timeout'): for an incorrect
%               choice or an early withdrawal whose punishment has a timeout above 0;
%               never for 'SidePokeBeforeChoice', which ends the trial on a side poke
%
% What each punishment means for an incorrect choice:
%   None                RetryResponse, then the response window again (started anew);
%                       the correct port rewards, the wrong one retries again. The
%                       default.
%   Timeout             IncorrectChoice for the timeout, no reward, then the inter-trial
%                       interval and the next trial.
%   White noise         IncorrectChoice while the noise plays, no reward, then the next
%                       trial.
%   Timeout + noise     IncorrectChoice for the timeout (at least as long as the noise),
%                       with the noise at its start, no reward, then the next trial.
% lum.buildTrialSM stretches the state to the noise's length, because the ITI stops
% the sound module.
%
% The state graph does not change with these settings: RetryResponse, IncorrectChoice and
% the timeouts' restart states exist in every trial, and an unpunished early withdrawal
% passes through EarlyWithdrawal with a zero timer and no sound. That keeps the trial-flow
% contract intact, so scoring and analysis are the same whatever the punishment settings
% were.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.defaultSettings, lum.buildTrialSM

% Codes match the menu order in lum.defaultSettings. They are written into every trial
% record, so append new options rather than renumbering these.
NONE = 1;
TIMEOUT = 2;
NOISE = 3;
BOTH = 4;

switch event
    case 'IncorrectChoice'
        kind = S.GUI.IncorrectChoicePunishment;
        timeout = S.GUI.IncorrectChoiceTimeout;
    case {'EarlyWithdrawal', 'SidePokeBeforeChoice'}
        kind = S.GUI.EarlyWithdrawalPunishment;
        timeout = S.GUI.EarlyWithdrawalTimeout;
    otherwise
        error('lum:punishmentFor:unknownEvent', ...
              ['Unknown punishable event ''%s''. Use ''IncorrectChoice'', '...
               '''EarlyWithdrawal'' or ''SidePokeBeforeChoice''.'], event);
end
applies = kind ~= NONE;

punishment = struct('Applies', applies, 'Timeout', 0, 'PlayNoise', false, ...
                    'Retry', ~applies && strcmp(event, 'IncorrectChoice'), ...
                    'RestartOnSidePoke', false);
if ~applies
    return
end

if ismember(kind, [TIMEOUT, BOTH])
    punishment.Timeout = timeout;
end
punishment.PlayNoise = ismember(kind, [NOISE, BOTH]);
punishment.RestartOnSidePoke = punishment.Timeout > 0 && ~strcmp(event, 'SidePokeBeforeChoice') ...
    && isfield(S.GUI, 'TimeoutSidePoke') && S.GUI.TimeoutSidePoke == 2;
