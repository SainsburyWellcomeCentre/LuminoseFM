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
%   Sync       One per trial for a fixed or jittered sync pulse, when the line
%              exists. Task-event sync is driven by states and costs none.
%   HoldClock  One when breaks in the hold are forgiven (lum.HoldShaping), because
%              the hold has to be timed across the animal leaving and returning.
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
%   reserved  Struct with the HoldWindow, Sync, HoldClock and Components counts above
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: RigConfig, lum.pattern.stimulusSet, lum.buildTrialSM

reserved = struct();
reserved.HoldWindow = 1;
reserved.Sync = double(S.Session.UseSync && rig.Available.Sync ...
                       && S.Sync.Mode ~= lum.SyncMode.TaskEvents);
reserved.HoldClock = double(lum.HoldShaping.hasGrace(S.Task.HoldShaping));
reserved.Components = lum.stim.timerCost(S);
budget = rig.Limits.GlobalTimers - reserved.HoldWindow - reserved.Sync ...
         - reserved.HoldClock - reserved.Components;
