function sma = blockStateMachine(widths, gaps, channel)
% lum.sleep.blockStateMachine builds the state machine that sends one block of sync pulses.
%
%   Pulse001 (line high, width 1) -> Gap001 (line low, gap 1) -> Pulse002 -> ... -> exit
%
% States rather than global timers, for the reasons the barcode uses states: the
% widths are the state machine's own 100 us cycle, nothing is spent from the timer
% budget, and it runs identically on the rig and under Bpod('EMU'). Each pulse's onset
% is then in the trial record as the entry time of its Pulse state.
%
% Arguments:
%   widths   1 x n pulse widths, seconds (lum.sleep.pulseSchedule)
%   gaps     1 x n low gaps after each pulse, seconds
%   channel  Output channel of the sync line, rig.Sync.Channel, or '' when there is
%            no line (the emulator): the states keep the same timing and drive nothing,
%            so the session, its plots and its data still run
%
% Returns the state machine description, ready for SendStateMachine. Needs Bpod
% running, because AddState resolves channel names against the connected machine.
%
% See also: lum.sleep.run, lum.sync.barcodeStateMachine

sma = NewStateMachine();
high = {};
low = {};
if ~isempty(channel)
    high = {channel, 1};
    low = {channel, 0};
end
n = numel(widths);
for i = 1:n
    if i < n
        nextState = sprintf('Pulse%03d', i + 1);
    else
        nextState = '>exit';
    end
    gapState = sprintf('Gap%03d', i);
    sma = AddState(sma, 'Name', sprintf('Pulse%03d', i), ...
        'Timer', widths(i), ...
        'StateChangeConditions', {'Tup', gapState}, ...
        'OutputActions', high);
    sma = AddState(sma, 'Name', gapState, ...
        'Timer', gaps(i), ...
        'StateChangeConditions', {'Tup', nextState}, ...
        'OutputActions', low);
end
