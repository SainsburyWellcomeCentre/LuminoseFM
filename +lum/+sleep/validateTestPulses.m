function [plan, notes] = validateTestPulses(S, rig)
% lum.sleep.validateTestPulses checks that a sleep session's test pulses can be sent.
%
% The schedule compiler (lum.sleep.testPulsePlan) refuses what cannot be expressed as
% light. Two more things depend on the session around it, and are checked here:
%
%   - Every epoch must be followed by enough darkness to hold a whole sync pulse with
%     1 ms to spare, so the timeline can always be cut between epochs with every line
%     low (lum.sleep.nextBlock).
%   - The busiest epoch, with every sync pulse that can fall inside it, must fit in one
%     state machine, since an epoch is never split across two.
%
% The test-pulse designer runs this on every edit, and lum.sleep.validate runs it too,
% so the designer and the session refuse the same schedules.
%
% Arguments:
%   S    Settings struct; reads S.Sleep.TestPulses, S.Sleep.Sync and S.Sleep.DurationMinutes
%   rig  Channel map from RigConfig, for rig.Limits.MaxStates
%
% Returns the compiled plan (empty when test pulses are off) and notes worth showing.
% Errors with 'lum:sleep:testPulsePlan:<reason>' or 'lum:sleep:validate:<reason>'.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.testPulsePlan, lum.sleep.validate, lum.gui.TestPulseDesigner

notes = {};
plan = lum.sleep.testPulsePlan(S.Sleep.TestPulses, S.Sleep.DurationMinutes);
if ~S.Sleep.TestPulses.Enabled
    return
end

lum.sleep.checkTimeline(plan, S.Sleep.Sync, rig);

if plan.UntilEnd
    notes{end+1} = sprintf(['Test pulses go on for the whole recording, %.4g min, and need '...
                            'PulsePal.'], plan.Duration / 60);
else
    notes{end+1} = sprintf(['With test pulses on, the recording lasts as long as their schedule, '...
                            '%.4g min, and needs PulsePal.'], plan.Duration / 60);
end
