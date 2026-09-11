function action = timerMaskAction(channelName, timerIndices)
% lum.timerMaskAction builds a GlobalTimerTrig or GlobalTimerCancel output action.
%
% AddState treats a *numeric* value for these channels as a single timer index
% (it computes 2^(value-1) for backwards compatibility) and only a char array of
% '0'/'1' as a bit mask. Triggering several timers from one state therefore needs
% the mask spelled out as a binary string, which is easy to get subtly wrong at
% each call site — hence this one function.
%
% Arguments:
%   channelName   'GlobalTimerTrig' or 'GlobalTimerCancel'
%   timerIndices  Indices of the global timers to act on; may be empty
%
% Returns a 1x2 OutputActions cell, or {} when there are no timers to act on, so
% the result can be concatenated unconditionally.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.stim.OptoPattern, lum.buildTrialSM

action = {};
if isempty(timerIndices)
    return
end
if any(timerIndices < 1) || any(mod(timerIndices, 1) ~= 0)
    error('lum:timerMaskAction:badIndices', 'Timer indices must be positive integers.');
end

mask = sum(2 .^ (timerIndices(:)' - 1));

% Padded to at least two digits. AddState only treats a value as a bit mask when
% it is longer than one character; a one-character value takes the legacy branch
% and is evaluated as 2^(value-1) — on the *character*, so the string '1' becomes
% 2^48 rather than timer 1. Padding to '01' keeps every mask on the binary path.
action = {channelName, dec2bin(mask, 2)};
