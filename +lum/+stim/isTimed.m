function tf = isTimed(onset, duration, window)
% lum.stim.isTimed is true when a stimulus component needs a global timer.
%
% A component that starts at stimulus onset and lasts at least the stimulus window
% is simply on for the whole centre hold, which an output action of the hold state
% does for free. Anything else — a delayed onset, or an offset before the window
% ends — is timed by a global timer. One rule, used both to size the timer budget
% before the session and to build each trial, so the two cannot disagree.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.stim.timerCost, lum.stim.TimedOutput

tolerance = 1e-9;
tf = onset > tolerance || duration < window - tolerance;
