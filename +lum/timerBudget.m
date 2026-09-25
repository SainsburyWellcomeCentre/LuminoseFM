function [budget, reserved] = timerBudget(S, rig)
% lum.timerBudget returns the global timers left for light patterns.
%
% Every stretch of light in a pattern costs one global timer (D1). Other parts of
% the trial may take timers first, and each is decided before the session, so the
% budget is known when the stimulus set is validated:
%
%   HoldWindow One, always: the time the animal has to complete a hold, counted from
%              trial start across every restart (S.GUI.HoldWindow, D10). A state
%              timer would start again each time the animal came back.
%   Sync       None, in any mode: every edge of the sync line is a state's output
%              action (D4). Kept in the struct, always 0, so that a session file or a
%              message that quotes the reservation still reads the same.
%   HoldClock  One when breaks in the hold are forgiven (lum.HoldShaping), because
%              the hold has to be timed across the animal leaving and returning.
%   LightClock One when a completed hold may end before the light pattern does
%              (lum.HoldShaping.lightMayOutlastHold: a growing hold, or a fixed hold
%              shorter than the stimulus window). It lasts the light, from stimulus
%              onset, so the trial can wait for the light to end before the ITI (D21):
%              the pattern's own timers cannot tell the state machine whether light is
%              still to come.
%   Components One for each stimulus component that switches on after stimulus
%              onset or off before the window ends, and for a cue light or cue air
%              that goes off part way through the stimulus (lum.stim.timerCost).
%
% Otherwise the cue costs nothing, and neither does the session barcode: both are
% built from states.
%
% The total differs by an order of magnitude between machines: the rig's r2+ has
% 16 global timers, while Bpod('EMU') emulates an r0.7-1.0 with 5. Read it from
% rig.Limits rather than assuming either.
%
% Arguments:
%   S    Settings struct
%   rig  Channel map from RigConfig
%
% Returns:
%   budget    Timers left for light segments; may be zero or negative when the
%             other parts already take everything
%   reserved  Struct with the HoldWindow, Sync, HoldClock, LightClock and Components
%             counts above
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: RigConfig, lum.pattern.stimulusSet, lum.buildTrialSM

reserved = struct();
reserved.HoldWindow = 1;
reserved.Sync = 0;  % States, not timers, drive the sync line in every mode (D4)
reserved.HoldClock = double(lum.HoldShaping.hasGrace(S));
reserved.LightClock = double(lum.HoldShaping.lightMayOutlastHold(S));
reserved.Components = lum.stim.timerCost(S);
budget = rig.Limits.GlobalTimers - reserved.HoldWindow - reserved.Sync ...
         - reserved.HoldClock - reserved.LightClock - reserved.Components;
