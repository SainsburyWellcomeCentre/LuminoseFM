function [widths, gaps] = pulseSchedule(sync, nPulses)
% lum.sleep.pulseSchedule draws one block of a sleep session's sync pulses.
%
% A sleep session has no trials to hang sync pulses on, so it sends them on a clock:
% one pulse every sync.Interval seconds, the interval jittered uniformly by up to
% sync.IntervalJitter either side. Each pulse is sync.FixedWidth long (Fixed width) or
% drawn uniformly within sync.WidthJitter of sync.MeanWidth (Jittered width), the same
% rule behaviour trials use (lum.nextTrialSpec). Near-unique widths let a recording be
% matched to Data.SyncPulses pulse by pulse rather than by counting edges.
%
% Arguments:
%   sync     S.Sleep.Sync: Mode (a lum.SyncMode code), FixedWidth, MeanWidth,
%            WidthJitter, Interval, IntervalJitter, all in seconds
%   nPulses  Pulses in the block
%
% Returns 1 x nPulses widths, and the low gap after each pulse, in seconds, quantised
% to the state machine's 100 us cycle. A pulse's interval is its width plus its gap.
%
% Widths and intervals come from rand(), so seeding with rng() makes a schedule
% reproducible. lum.sleep.validate guarantees a gap of at least 1 ms.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.blockStateMachine, lum.sleep.run, lum.SyncMode

switch sync.Mode
    case lum.SyncMode.FixedWidth
        widths = repmat(sync.FixedWidth, 1, nPulses);
    case lum.SyncMode.JitteredWidth
        widths = sync.MeanWidth + (2 * rand(1, nPulses) - 1) * sync.WidthJitter;
    otherwise
        error('lum:sleep:pulseSchedule:badMode', ...
              'Sleep sync pulses must be Fixed width (%d) or Jittered width (%d); got %g.', ...
              lum.SyncMode.FixedWidth, lum.SyncMode.JitteredWidth, sync.Mode);
end
intervals = sync.Interval + (2 * rand(1, nPulses) - 1) * sync.IntervalJitter;

widths = max(quantise(widths), 1e-4);
gaps = max(quantise(intervals) - widths, 1e-4);


function t = quantise(t)
% Round to the state machine's 100 us cycle, so what is stored is what is sent.
t = round(t / 1e-4) * 1e-4;
