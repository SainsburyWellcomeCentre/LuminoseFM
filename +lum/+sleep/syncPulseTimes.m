function pulses = syncPulseTimes(sync, durationSeconds)
% lum.sleep.syncPulseTimes lays out every sync pulse of a sleep session in session time.
%
% A sleep session sends a sync pulse every sync.Interval seconds (jittered by up to
% sync.IntervalJitter either side), with widths drawn by lum.sleep.pulseSchedule, from
% the start of the recording until durationSeconds. They are drawn all at once, before
% the session, so that lum.sleep.nextBlock can cut the sync line and the test pulses
% into the same state machines without cutting through either.
%
% Arguments:
%   sync             S.Sleep.Sync
%   durationSeconds  Length of the recording
%
% Returns nPulses x 2 [onset width], in cycles of the state machine's 100 us clock,
% the first pulse at 0 and every onset before durationSeconds. Widths and intervals
% come from rand(), so seeding with rng() makes a session's pulses reproducible.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.pulseSchedule, lum.sleep.nextBlock, lum.sleep.run

cycle = 1e-4;
endCycles = round(durationSeconds / cycle);
shortest = max(sync.Interval - sync.IntervalJitter, cycle);
n = ceil(durationSeconds / shortest) + 1;
[widths, gaps] = lum.sleep.pulseSchedule(sync, n);
widthCycles = round(widths / cycle);
intervalCycles = round((widths + gaps) / cycle);
onsets = [0, cumsum(intervalCycles(1:end-1))];
keep = onsets < endCycles;
pulses = [onsets(keep)', widthCycles(keep)'];
