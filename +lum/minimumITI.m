function [minimum, note] = minimumITI(S)
% lum.minimumITI is the shortest ITI at which every trial starts on time, and why S's is short.
%
% The next trial is uploaded while the running one plays (lum.triggerStates), so it starts
% one ITI after the running one's light is over, whatever the ITI. The exception is a trial
% that needs a device command first: an LED current asked for from the LED window (and a
% PulsePal program, which with the stimulus window fixed for the session only trial 1 needs,
% before anything runs). It waits for the ITI, when the light is over, and the trial is
% uploaded after it. With the ITI at this minimum the command and the upload fit inside it
% and that trial starts on time too; with a shorter ITI (0 s, say) it starts late by what
% the ITI did not cover, with no state machine running in between and BpodTrialManager's
% dead time warning, so the time between trials is not the same on every trial. The upload
% took 45 ms (median) and at most 213 ms in 810 trials on the rig (2026-09-26 to -28,
% Data.Timing.send) and an LED current about 1 ms: 0.25 s covers them with the time to notice
% the ITI (rig check 2026-09-28: 88-124 ms for an LED change and upload).
% Without light nothing waits, and any ITI, 0 s included, is kept on every trial.
%
% Usage:
%   minimum = lum.minimumITI()        % the minimum in a session with light: the default ITI
%   [minimum, note] = lum.minimumITI(S)
%
% Returns:
%   minimum  Seconds: 0.25 in a session with light (S.Session.UseOpto), 0 without
%   note     Why S.GUI.ITI is too short, for the setup dialog, the runtime window and the
%            console; '' when it is not
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.triggerStates, lum.dev.DoricLED, lum.validateSettings

withLight = 0.25;
minimum = withLight;
note = '';
if nargin < 1
    return
end
if ~S.Session.UseOpto
    minimum = 0;
    return
end
if S.GUI.ITI < minimum
    note = sprintf(['An inter-trial interval of %g s is shorter than %g s: a trial after a '...
                    'change of LED current (the LED window) will start late, with no state '...
                    'machine running and a dead time warning, so the time between trials will '...
                    'not be the same on every trial.'], S.GUI.ITI, minimum);
end
