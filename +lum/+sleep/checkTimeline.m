function checkTimeline(plan, sync, rig)
% lum.sleep.checkTimeline checks that light and sync pulses can be cut into state machines.
%
% Two things depend on the session around a plan of light (lum.sleep.testPulsePlan,
% lum.ephys.plan):
%
%   - Every epoch must be followed by enough darkness to hold a whole sync pulse with
%     1 ms to spare, so the timeline can always be cut between epochs with every line
%     low (lum.sleep.nextBlock).
%   - The busiest epoch, with every sync pulse that can fall inside it, must fit in one
%     state machine, since an epoch is never split across two.
%
% Arguments:
%   plan  The compiled plan
%   sync  The session's sync pulses (S.Sleep.Sync or S.Ephys.Sync)
%   rig   Channel map from RigConfig, for rig.Limits.MaxStates
%
% Errors with 'lum:sleep:validate:epochsCrowdSync' or 'lum:sleep:validate:epochTooBusy'.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.validateTestPulses, lum.ephys.validate, lum.sleep.nextBlock

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
