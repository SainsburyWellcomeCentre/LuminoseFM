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
%   S    Settings struct; reads S.Sleep.TestPulses and S.Sleep.Sync
%   rig  Channel map from RigConfig, for rig.Limits.MaxStates
%
% Returns the compiled plan (empty when test pulses are off) and notes worth showing.
% Errors with 'lum:sleep:testPulsePlan:<reason>' or 'lum:sleep:validate:<reason>'.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.testPulsePlan, lum.sleep.validate, lum.gui.TestPulseDesigner

notes = {};
plan = lum.sleep.testPulsePlan(S.Sleep.TestPulses);
if ~S.Sleep.TestPulses.Enabled
    return
end

sync = S.Sleep.Sync;
if sync.Mode == lum.SyncMode.FixedWidth
    longestPulse = sync.FixedWidth;
else
    longestPulse = sync.MeanWidth + sync.WidthJitter;
end
shortestInterval = max(sync.Interval - sync.IntervalJitter, 1e-3);

if plan.ShortestDark - longestPulse < 1e-3
    error('lum:sleep:validate:epochsCrowdSync', ...
          ['An epoch is followed by only %g s of darkness, too little for a sync pulse of up to '...
           '%g s with 1 ms to spare, so the session could not pause between epochs. Lengthen '...
           'the inter-epoch or train interval, or shorten the sync pulses.'], ...
          plan.ShortestDark, longestPulse);
end

statesNeeded = 2 * plan.MostSegmentsPerEpoch + 2 * (ceil(plan.LongestEpoch / shortestInterval) + 1) + 1;
if statesNeeded > rig.Limits.MaxStates - 2
    error('lum:sleep:validate:epochTooBusy', ...
          ['The longest epoch (%g s, %d gates of light) and the sync pulses that can fall in it '...
           'need %d states in one state machine, which holds %d. Shorten the epoch or train, or '...
           'lengthen the sync interval.'], plan.LongestEpoch, plan.MostSegmentsPerEpoch, ...
          statesNeeded, rig.Limits.MaxStates - 2);
end

notes{end+1} = sprintf(['With test pulses on, the recording lasts as long as their schedule, '...
                        '%.4g min, and needs PulsePal.'], plan.Duration / 60);
