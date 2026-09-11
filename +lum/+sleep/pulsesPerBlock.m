function n = pulsesPerBlock(sync, maxStates, secondsLeft)
% lum.sleep.pulsesPerBlock decides how many sync pulses the next block sends.
%
% A sleep session sends its pulses as a series of state machines, each a block of
% pulses (lum.sleep.blockStateMachine), so the online plot and the data file follow
% the session every few seconds without MATLAB touching the timing of any pulse. A
% block is about BlockSeconds long, holds at most what one state machine can (two
% states per pulse), and stops at what is left of the session. It is never empty: the
% last block may run up to one interval past the end.
%
% Arguments:
%   sync         S.Sleep.Sync (uses Interval)
%   maxStates    rig.Limits.MaxStates
%   secondsLeft  Session time remaining, seconds
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.run, lum.sleep.pulseSchedule

blockSeconds = 10;
n = floor(min(blockSeconds, secondsLeft) / sync.Interval);
n = min(max(n, 1), floor(maxStates / 2));
