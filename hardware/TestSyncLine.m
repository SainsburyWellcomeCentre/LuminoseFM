function report = TestSyncLine(varargin)
% TestSyncLine drives the sync TTL line outside a session, to see that it works.
%
% The sync line (Flex2 as a digital output, rig.Sync.Channel) can be driven two
% ways, and a rig can support one without the other:
%
%   states   Each edge is an output action of a state, the way the session barcode
%            and a sleep session's pulses are sent. This is what LuminoseFM uses for
%            trial pulses from version 0.5.1 on (D4).
%   timer    One global timer with the line as its Channel, which sets it high when
%            the timer starts and low when it ends. This is what trial pulses used
%            before 0.5.1; if the timer train below is flat on a scope while the
%            state train is not, that is why no pulses were reaching the recording.
%
% Run it with a scope, a logic analyser or the acquisition system itself on the
% line, and watch which trains arrive. Nothing here touches the animal: no valve,
% no LED and no optical channel is driven, and a protocol must not be running.
%
% Usage:
%   TestSyncLine                       % 10 x 50 ms pulses, both ways, 200 ms apart
%   TestSyncLine('Width', 0.02)        % 20 ms pulses
%   TestSyncLine('Count', 40)          % a longer train
%   TestSyncLine('Drive', 'states')    % only the state-driven train
%   TestSyncLine('Channel', 'BNC2')    % check a different output channel
%   TestSyncLine('Barcode', true)      % also send a decodable session barcode
%
% Options (name/value):
%   Channel  Output channel to drive (default rig.Sync.Channel, i.e. Flex2DO)
%   Width    Pulse width in seconds (default 0.05)
%   Gap      Seconds between pulses, low (default 0.2)
%   Count    Pulses per train (default 10)
%   Drive    'both' (default) | 'states' | 'timer'
%   Barcode  true to finish with a real session barcode (default false)
%   Force    true to run even while a protocol is in progress (default false)
%
% Returns a struct with what was sent, what the state machine reported, and the
% channel it used, so a test or a log can record the result.
%
% Requires Bpod to be running. Under Bpod('EMU') the emulated r0.7-1.0 has no Flex
% I/O, so pass a 'Channel' that exists there (e.g. 'BNC2') or the call is refused.
%
% See also: RigConfig, CheckRig, lum.sync.barcode, lum.dev.Flex, lum.SyncMode

global BpodSystem %#ok<GVMIS> % Imported to read the channel list and run the machine

p = inputParser;
p.FunctionName = 'TestSyncLine';
addParameter(p, 'Channel', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'Width', 0.05, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Gap', 0.2, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Count', 10, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'Drive', 'both', @(x) ischar(x) || isstring(x));
addParameter(p, 'Barcode', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'Force', false, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;
drive = lower(char(opt.Drive));
if ~ismember(drive, {'both', 'states', 'timer'})
    error('TestSyncLine:badDrive', 'Drive must be one of: both, states, timer.');
end

if isempty(BpodSystem) || ~isobject(BpodSystem)
    error('TestSyncLine:noBpod', 'Bpod is not running. Start it with Bpod or Bpod(''EMU'') first.');
end
if BpodSystem.Status.BeingUsed == 1 && ~opt.Force
    error('TestSyncLine:protocolRunning', ...
          ['A protocol is running. Stop it first, or pass ''Force'', true if you are '...
           'certain the rig is free.']);
end

rig = RigConfig;
channel = char(opt.Channel);
if isempty(channel)
    channel = rig.Sync.Channel;
end
outputs = BpodSystem.StateMachineInfo.OutputChannelNames;
if ~ismember(channel, outputs)
    error('TestSyncLine:noChannel', ...
          ['''%s'' is not an output channel on this state machine. Configure Flex2 as a '...
           'digital output in the Bpod console (Settings -> Flex I/O), or pass a channel '...
           'that exists, e.g. ''BNC2''.'], channel);
end

nPulses = round(opt.Count);
report = struct('Channel', channel, 'Width', opt.Width, 'Gap', opt.Gap, ...
                'Count', nPulses, 'Drive', drive, 'States', [], 'Timer', [], 'Barcode', []);

fprintf('TestSyncLine: %s on %s, %d pulse(s) of %g s every %g s.\n', ...
        BpodSystem.HW.StateMachineModel, channel, nPulses, opt.Width, opt.Width + opt.Gap);

if ismember(drive, {'both', 'states'})
    fprintf('  state-driven train (the way the barcode and trial pulses are sent)...\n');
    report.States = runMachine(statesTrain(channel, opt.Width, opt.Gap, nPulses));
    fprintf('    done, %d state(s) visited.\n', report.States.nStates);
end

if ismember(drive, {'both', 'timer'})
    if BpodSystem.HW.n.GlobalTimers < 1
        fprintf('  global-timer train skipped: this state machine has no global timers.\n');
    else
        fprintf('  global-timer train (the way trial pulses were sent before 0.5.1)...\n');
        report.Timer = runMachine(timerTrain(channel, opt.Width, opt.Gap, nPulses));
        fprintf('    done, %d state(s) visited.\n', report.Timer.nStates);
    end
end

if opt.Barcode
    defaults = lum.defaultSettings();
    code = lum.sync.barcode(lum.sync.barcodeValue(datetime('now')), defaults.Sync.Barcode, ...
                            'Behaviour');
    fprintf('  session barcode %s (%.2f s)...\n', code.Hex, code.TotalDuration);
    report.Barcode = code;
    runMachine(lum.sync.barcodeStateMachine(code, channel));
    fprintf('    done.\n');
end

fprintf(['TestSyncLine: if one train reached the recording and the other did not, the line '...
         'is fine and\n  the way it was driven is not. Say which in the session notes and in '...
         'docs/architecture.md (D4).\n']);


function sma = statesTrain(channel, width, gap, nPulses)
% One state per edge: high for width, low for gap, nPulses times.
sma = NewStateMachine();
for i = 1:nPulses
    if i < nPulses
        after = sprintf('Low%03d', i);
        next = sprintf('High%03d', i + 1);
    else
        after = sprintf('Low%03d', i);
        next = '>exit';
    end
    sma = AddState(sma, 'Name', sprintf('High%03d', i), ...
        'Timer', width, 'StateChangeConditions', {'Tup', after}, ...
        'OutputActions', {channel, 1});
    sma = AddState(sma, 'Name', sprintf('Low%03d', i), ...
        'Timer', gap, 'StateChangeConditions', {'Tup', next}, ...
        'OutputActions', {channel, 0});
end


function sma = timerTrain(channel, width, gap, nPulses)
% One global timer linked to the channel, re-triggered once per pulse. The states
% only wait; the timer is what should drive the line.
sma = NewStateMachine();
sma = SetGlobalTimer(sma, 'TimerID', 1, 'Duration', width, 'OnsetDelay', 0, 'Channel', channel);
for i = 1:nPulses
    if i < nPulses
        next = sprintf('Pulse%03d', i + 1);
    else
        next = '>exit';
    end
    sma = AddState(sma, 'Name', sprintf('Pulse%03d', i), ...
        'Timer', width + gap, 'StateChangeConditions', {'Tup', next}, ...
        'OutputActions', lum.timerMaskAction('GlobalTimerTrig', 1));
end


function result = runMachine(sma)
% Send one state machine, run it to completion, and report what came back.
SendStateMachine(sma);
raw = RunStateMachine;
result = struct('nStates', 0, 'Raw', raw);
if isstruct(raw) && isfield(raw, 'States')
    result.nStates = numel(raw.States);
end
