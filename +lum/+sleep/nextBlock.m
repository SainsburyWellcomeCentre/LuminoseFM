function [block, cursor] = nextBlock(plan, syncPulses, cursor, maxStates)
% lum.sleep.nextBlock cuts the next state machine run out of a sleep session's timeline.
%
% A sleep session sends its sync pulses and its test pulses (D11, D13) as a series of
% state machines of about 10 s each, run one after another with blocking
% RunStateMachine, so the plots and the data file follow the session without MATLAB
% timing any pulse. Every line is low between runs, and uploading the next one takes a
% few milliseconds, so a block may only end where nothing is lost by pausing:
%
%   - never inside a sync pulse or a gate of light;
%   - never inside an epoch, so a paired pulse keeps its interval and a train its
%     rhythm;
%   - before the first epoch of the next step, so PulsePal can be given that step's
%     carrier between runs.
%
% The block runs from cursor.Time to the latest such moment within 10 s, shortened
% until its states fit the state machine. Its states are the spans between successive
% edges of the three lines — sync, A, B — each holding every line at one level, so any
% mix of pulses costs one state per edge and no global timers.
%
% Arguments:
%   plan        From lum.sleep.testPulsePlan (empty when there are no test pulses)
%   syncPulses  From lum.sleep.syncPulseTimes
%   cursor      Where the session has got to: .Time and .End (cycles), .NextSync and
%               .NextEpoch (rows not yet sent). A session starts from
%               struct('Time', 0, 'End', endCycles, 'NextSync', 1, 'NextEpoch', 1).
%   maxStates   rig.Limits.MaxStates
%
% Returns the cursor moved past the block, and block:
%   .Start, .End       Cycles, session time
%   .Durations         nStates x 1 state timers, seconds
%   .Levels            nStates x 3 logical: sync, A, B
%   .StateNames        {'Level001', ...}
%   .SyncIndices       Rows of syncPulses in the block; .SyncStates the state each starts
%   .SegmentIndices    Rows of plan.Segments in the block; .SegmentStates likewise
%   .Step              The step whose light the block carries, 0 for none
%
% Errors with 'lum:sleep:nextBlock:<reason>' when the timeline cannot be cut, which
% lum.sleep.validate rules out before a session starts.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.blockStateMachine, lum.sleep.run, lum.sleep.validate

cycle = 1e-4;
blockCycles = round(10 / cycle);
budget = maxStates - 2;   % SendStateMachine may reserve one state of its own
t0 = cursor.Time;
if t0 >= cursor.End
    error('lum:sleep:nextBlock:sessionOver', 'The session''s timeline has already been sent.');
end

epochs = plan.Epochs;
nEpochs = size(epochs, 1);
nSync = size(syncPulses, 1);
firstEpoch = cursor.NextEpoch;
firstSync = cursor.NextSync;

limit = Inf;
if firstEpoch <= nEpochs && plan.NextStepEpoch(firstEpoch) <= nEpochs
    limit = epochs(plan.NextStepEpoch(firstEpoch), 1);
end
target = min([t0 + blockCycles, cursor.End, limit]);

previousEnd = Inf;
for attempt = 1:40
    finish = freePoint(target);
    lastEpoch = lastStartingBefore(epochs(:, 1), firstEpoch, nEpochs, finish);
    lastSync = lastStartingBefore(syncPulses(:, 1), firstSync, nSync, finish);
    [breaks, segmentRows, syncRows] = edges(finish, lastEpoch, lastSync);
    if numel(breaks) - 1 <= budget
        break
    end
    if finish >= previousEnd || finish - t0 <= 1 || attempt == 40
        error('lum:sleep:nextBlock:tooManyStates', ...
              ['At %.1f s the session cannot be cut into state machines of %d states: an epoch '...
               'and the sync pulses during it need more. Lengthen the sync interval or shorten '...
               'the epoch.'], t0 * cycle, maxStates);
    end
    previousEnd = finish;
    target = t0 + floor((finish - t0) / 2);
end
if finish > limit
    error('lum:sleep:nextBlock:stepOverlap', ...
          ['At %.1f s a sync pulse joins the last epoch of one step to the first of the next, so '...
           'PulsePal cannot change carrier between them.'], t0 * cycle);
end

starts = breaks(1:end-1);
segments = plan.Segments(segmentRows, :);
syncOn = syncPulses(syncRows, 1);
syncOff = syncOn + syncPulses(syncRows, 2);
segmentOn = segments(:, 1);
segmentOff = segmentOn + segments(:, 2);
onA = segments(:, 3) == 1;
levels = [covered(starts, syncOn, syncOff), covered(starts, segmentOn(onA), segmentOff(onA)), ...
          covered(starts, segmentOn(~onA), segmentOff(~onA))];
[~, syncStates] = ismember(syncOn, starts);
[~, segmentStates] = ismember(segmentOn, starts);

step = 0;
if ~isempty(segmentRows)
    step = segments(1, 4);
end
nStates = numel(starts);
block = struct('Start', t0, 'End', finish, 'Durations', diff(breaks) * cycle, ...
               'Levels', levels, ...
               'StateNames', {arrayfun(@(i) sprintf('Level%03d', i), 1:nStates, 'UniformOutput', false)}, ...
               'SyncIndices', syncRows, 'SyncStates', reshape(syncStates, 1, []), ...
               'SegmentIndices', segmentRows, 'SegmentStates', reshape(segmentStates, 1, []), ...
               'Step', step);
cursor.Time = finish;
cursor.NextEpoch = lastEpoch + 1;
cursor.NextSync = lastSync + 1;


    function point = freePoint(point)
        % The latest moment at or before point that is inside no gate, pulse or epoch —
        % or, where the run of activity starts at the block's own start, its end.
        for iteration = 1:1000
            moved = false;
            e = lastStartingBefore(epochs(:, 1), firstEpoch, nEpochs, point);
            if e >= firstEpoch && epochs(e, 2) > point
                if epochs(e, 1) > t0
                    point = epochs(e, 1);
                else
                    point = epochs(e, 2);
                end
                moved = true;
            end
            p = lastStartingBefore(syncPulses(:, 1), firstSync, nSync, point);
            if p >= firstSync && syncPulses(p, 1) + syncPulses(p, 2) > point
                if syncPulses(p, 1) > t0
                    point = syncPulses(p, 1);
                else
                    point = syncPulses(p, 1) + syncPulses(p, 2);
                end
                moved = true;
            end
            if ~moved
                return
            end
        end
        error('lum:sleep:nextBlock:noFreePoint', ...
              'At %.1f s no moment with every line low could be found.', t0 * cycle);
    end

    function [breaks, segmentRows, syncRows] = edges(finish, lastEpoch, lastSync)
        % Every edge in the block, as state boundaries.
        if lastEpoch >= firstEpoch
            segmentRows = epochs(firstEpoch, 3):epochs(lastEpoch, 4);
        else
            segmentRows = zeros(1, 0);
        end
        syncRows = firstSync:lastSync;
        on = plan.Segments(segmentRows, 1);
        sOn = syncPulses(syncRows, 1);
        breaks = unique([t0; sOn; sOn + syncPulses(syncRows, 2); on; ...
                         on + plan.Segments(segmentRows, 2); finish]);
    end
end


function last = lastStartingBefore(starts, first, n, point)
% The last row from first on whose start is before point; first - 1 when there is none.
last = first - 1;
while last < n && starts(last + 1) < point
    last = last + 1;
end
end


function high = covered(times, on, off)
% Whether a line is high at each time, given its pulses' onsets and ends.
if isempty(on)
    high = false(numel(times), 1);
    return
end
high = sum(reshape(on, 1, []) <= times, 2) > sum(reshape(off, 1, []) <= times, 2);
end
