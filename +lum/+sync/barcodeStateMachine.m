function sma = barcodeStateMachine(code, channel)
% lum.sync.barcodeStateMachine builds the state machine that sends a session barcode.
%
% One state per barcode element, each driving the sync line high or low for its
% duration. States rather than global timers, for the reasons the cue uses states:
% the timing is the state machine's own 100 us cycle, it costs nothing from the
% timer budget, and it runs identically on the rig and under Bpod('EMU').
%
% It runs once, on its own, before the first trial — not as states of trial 1 —
% so the trial-flow contract, the state names every trial carries, is untouched
% and the barcode never appears in the trial record.
%
% Arguments:
%   code     Barcode from lum.sync.barcode
%   channel  Output channel of the sync line, rig.Sync.Channel ('Flex2DO')
%
% Returns the state machine description, ready for SendStateMachine. Needs Bpod
% running, because AddState resolves channel names against the connected machine.
%
% See also: lum.sync.barcode, lum.dev.Flex

sma = NewStateMachine();
nElements = numel(code.Levels);
for i = 1:nElements
    if i < nElements
        nextState = sprintf('Barcode%03d', i + 1);
    else
        nextState = '>exit';
    end
    sma = AddState(sma, 'Name', sprintf('Barcode%03d', i), ...
        'Timer', code.Durations(i), ...
        'StateChangeConditions', {'Tup', nextState}, ...
        'OutputActions', {channel, code.Levels(i)});
end
