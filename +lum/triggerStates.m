function names = triggerStates()
% lum.triggerStates lists the states that open the prepare window for the next trial.
%
% With BpodTrialManager, MATLAB builds and uploads trial n+1 while trial n runs (D3), and
% the state machine starts it the moment trial n ends. The window opens as trial n leaves
% TrialStart for WaitForCentrePoke, which every trial passes through; the loop has by then
% recorded, plotted and saved trial n-1, so the whole of trial n is left for the work.
% TrialStart itself cannot be one: it is entered without a transition. lum.SessionRunner
% waits for the running trial to leave its first state (BpodSystem.Status.CurrentStateName),
% so each state named here must be entered straight from TrialStart.
%
% The window may overlap trial n's light. Building and uploading a state machine does not
% touch the light, but changing an LED current or reprogramming PulsePal would, so those
% wait for trial n's ITI (lum.stim.Component.needsConfigure, lum.dev.DoricLED.hasPending),
% and a trial that needs one is uploaded after them, on time when the ITI covers them
% (lum.minimumITI). Up to 0.9.10 a session with
% light opened the window in the ITI, after the light (D21): with the ITI at 0 s the
% trial had then already ended, and every trial began 0.01-0.35 s after the one before,
% with no state machine running and BpodTrialManager's inter-trial dead time warning
% printed after each.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.SessionRunner, lum.buildTrialSM, lum.dev.DoricLED

names = {'WaitForCentrePoke'};
