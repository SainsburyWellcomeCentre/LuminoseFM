function sma = blockStateMachine(block, lines)
% lum.sleep.blockStateMachine builds the state machine that sends one block of a sleep session.
%
%   Level001 (every line at its level) -> Level002 -> ... -> exit
%
% A block from lum.sleep.nextBlock is a list of spans between successive edges of the
% sync line and channels A and B. Each span is one state that holds all three lines at
% their levels for its length: states rather than global timers, for the reasons the
% barcode uses states — the timing is the state machine's own 100 us cycle, nothing is
% spent from the timer budget, and it runs identically on the rig and under
% Bpod('EMU'). Each pulse's onset is then in the trial record as the entry time of the
% state it starts in.
%
% Arguments:
%   block  From lum.sleep.nextBlock
%   lines  1 x 3 cell of output channels: the sync line (rig.Sync.Channel) and
%          channels A and B (rig.Opto.Channels). '' drives nothing on that line — the
%          sync line in the emulator, A and B in a session without test pulses — while
%          the states keep their timing, so the session, its plots and its data still run.
%
% Returns the state machine description, ready for SendStateMachine. Needs Bpod
% running, because AddState resolves channel names against the connected machine.
%
% See also: lum.sleep.nextBlock, lum.sleep.run, lum.sync.barcodeStateMachine

sma = NewStateMachine();
n = numel(block.Durations);
for i = 1:n
    if i < n
        nextState = block.StateNames{i + 1};
    else
        nextState = '>exit';
    end
    actions = {};
    for line = 1:3
        if ~isempty(lines{line})
            actions(end+1:end+2) = {lines{line}, double(block.Levels(i, line))};
        end
    end
    sma = AddState(sma, 'Name', block.StateNames{i}, ...
        'Timer', block.Durations(i), ...
        'StateChangeConditions', {'Tup', nextState}, ...
        'OutputActions', actions);
end
