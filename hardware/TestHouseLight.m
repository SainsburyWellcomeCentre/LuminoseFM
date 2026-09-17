function report = TestHouseLight(varargin)
% TestHouseLight switches the house light through PulsePal and checks Bpod logs each switch.
%
% The house light is PulsePal output 3; a BNC splitter sends the same line to the light's
% LED driver and to Bpod's BNC input 1 (D15, docs/hardware.md §2.3). This runs one state
% machine that asks MATLAB, by soft code, to switch the light on and off a few times — the
% same call the House light box makes during a session (lum.dev.HouseLight.set) — and then
% looks for each switch among the state machine's events:
%
%   command   the state that sent the soft code, entered at a time on Bpod's clock
%   edge      the BNC1High (on) or BNC1Low (off) event the loopback produced
%   latency   edge minus command: soft code to MATLAB, PulsePal's round trip, the wire
%
% Every command should find its edge, tens of milliseconds or less after it. No edge at all
% means the loopback is not reaching Bpod: the splitter, the cable into BNC input 1, or the
% input disabled in the console's port settings. Watch the light too: it should blink.
%
% Nothing here touches the animal beyond the house light itself: no valve, port LED, sync
% line or optical channel is driven. A protocol must not be running. The light is left off.
%
% Usage:
%   TestHouseLight                     % 5 switches on and off, 0.5 s each
%   TestHouseLight('Count', 20)        % more
%   TestHouseLight('On', 1, 'Off', 2)  % seconds on and off
%
% Options (name/value):
%   Count  Times the light is switched on, and off again (default 5)
%   On     Seconds on (default 0.5)
%   Off    Seconds off after each (default 0.5)
%   Force  true to run even while a protocol is in progress (default false)
%
% Returns a struct: the wiring (rig.HouseLight), Emulated, InputEnabled, and Commands with
% one row per switch — On, CommandTime, EdgeTime (NaN when no edge came) and Latency, in
% seconds on the state machine's clock — with nFound, nMissing, MedianLatency, MaxLatency,
% Passed and the PulsePal and HouseLight device logs.
%
% Requires Bpod to be running. Under Bpod('EMU') PulsePal is the null shim and the edges
% are the ones lum.dev.NullHouseLight puts into the emulated state machine, so the check
% runs end to end without hardware (houseLightTest does exactly that); latencies there mean
% nothing.
%
% See also: RigConfig, CheckRig, lum.dev.HouseLight, lum.dev.PulsePal.holdVoltage, TestSyncLine

global BpodSystem %#ok<GVMIS> % Imported to read the machine and run it

p = inputParser;
p.FunctionName = 'TestHouseLight';
addParameter(p, 'Count', 5, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'On', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0.05);
addParameter(p, 'Off', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0.05);
addParameter(p, 'Force', false, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

if isempty(BpodSystem) || ~isobject(BpodSystem)
    error('TestHouseLight:noBpod', 'Bpod is not running. Start it with Bpod or Bpod(''EMU'') first.');
end
if BpodSystem.Status.BeingUsed == 1 && ~opt.Force
    error('TestHouseLight:protocolRunning', ...
          ['A protocol is running. Stop it first, or pass ''Force'', true if you are '...
           'certain the rig is free.']);
end

rig = RigConfig;
config = rig.HouseLight;
emulated = BpodSystem.EmulatorMode == 1;
inputIndex = find(strcmp(BpodSystem.StateMachineInfo.InputChannelNames, config.Input), 1);
if isempty(inputIndex)
    error('TestHouseLight:noInput', 'This state machine has no input %s to loop the house light into.', ...
          config.Input);
end
inputEnabled = numel(BpodSystem.InputsEnabled) < inputIndex || BpodSystem.InputsEnabled(inputIndex) == 1;
nSwitches = round(opt.Count);

fprintf('TestHouseLight: PulsePal output %d at %g V, looped back into %s; %d switch(es), %g s on, %g s off.\n', ...
        config.PulsePalChannel, config.Voltage, config.Input, nSwitches, opt.On, opt.Off);
if ~inputEnabled
    fprintf(['  %s is disabled in the console''s port settings, so no edge can arrive. Enable it '...
             '(and run this again).\n'], config.Input);
end

% The devices a session would have. PulsePal is connected for this call only and closed on
% the way out, with the light off, whatever happens.
[pulsePal, houseLight] = openDevices(emulated, config);
previousHandler = BpodSystem.SoftCodeHandlerFunction;
previousStatus = [BpodSystem.Status.BeingUsed, BpodSystem.Status.InStateMatrix];
cleanup = onCleanup(@() restore(previousHandler, previousStatus, houseLight, pulsePal));
BpodSystem.SoftCodeHandlerFunction = @(code) houseLight.set(code == softCodeOn());

SendStateMachine(switchingMachine(nSwitches, opt.On, opt.Off));
raw = RunStateMachine;
data = AddTrialEvents(struct(), raw);
trial = data.RawEvents.Trial{1};

commands = matchEdges(trial, config, nSwitches);
report = struct('Wiring', config, 'Emulated', emulated, 'InputEnabled', inputEnabled, ...
                'Commands', commands, 'nFound', nnz(~isnan([commands.EdgeTime])), ...
                'nMissing', nnz(isnan([commands.EdgeTime])), ...
                'MedianLatency', median([commands.Latency], 'omitnan'), ...
                'MaxLatency', max([commands.Latency], [], 'omitnan'), 'Passed', false, ...
                'PulsePalLog', {pulsePal.log()}, 'HouseLightLog', {houseLight.log()});
report.Passed = report.nMissing == 0;
delete(cleanup);

printReport(report, config);


function [pulsePal, houseLight] = openDevices(emulated, config)
% PulsePal and the house light, as a session opens them — but refusing, not falling back.
if emulated
    pulsePal = lum.dev.NullPulsePal('emulator mode');
    houseLight = lum.dev.NullHouseLight(pulsePal, config, false, 'emulator mode');
    return
end
pulsePal = lum.dev.RealPulsePal(fullfile(fileparts(fileparts(lum.repoRoot)), 'PulsePal'));
try
    pulsePal.stopOutputs();
    pulsePal.checkConnection();
    houseLight = lum.dev.RealHouseLight(pulsePal, config, false);
catch openError
    pulsePal.close();
    rethrow(openError);
end


function sma = switchingMachine(nSwitches, onSeconds, offSeconds)
% Settle, then On001 / Off001 ... each sending its soft code on entry, then settle again.
sma = NewStateMachine();
sma = AddState(sma, 'Name', 'Settle', 'Timer', 0.3, 'StateChangeConditions', {'Tup', 'On001'}, ...
               'OutputActions', {});
for k = 1:nSwitches
    afterOff = 'SettleEnd';
    if k < nSwitches
        afterOff = sprintf('On%03d', k + 1);
    end
    sma = AddState(sma, 'Name', sprintf('On%03d', k), 'Timer', onSeconds, ...
                   'StateChangeConditions', {'Tup', sprintf('Off%03d', k)}, ...
                   'OutputActions', {'SoftCode', softCodeOn()});
    sma = AddState(sma, 'Name', sprintf('Off%03d', k), 'Timer', offSeconds, ...
                   'StateChangeConditions', {'Tup', afterOff}, ...
                   'OutputActions', {'SoftCode', softCodeOff()});
end
sma = AddState(sma, 'Name', 'SettleEnd', 'Timer', 0.3, 'StateChangeConditions', {'Tup', '>exit'}, ...
               'OutputActions', {});


function code = softCodeOn()
% The soft code that asks MATLAB to switch the light on; softCodeOff() asks for off.
code = 1;


function code = softCodeOff()
code = 2;


function commands = matchEdges(trial, config, nSwitches)
% For each command state, the first edge of its kind after it and before the next command.
commands = struct('On', {}, 'CommandTime', {}, 'EdgeTime', {}, 'Latency', {});
times = NaN(1, 2 * nSwitches);
levels = false(1, 2 * nSwitches);
for k = 1:nSwitches
    times(2*k - 1) = stateEntry(trial, sprintf('On%03d', k));
    levels(2*k - 1) = true;
    times(2*k) = stateEntry(trial, sprintf('Off%03d', k));
end
for i = 1:numel(times)
    if i < numel(times)
        until = times(i + 1);
    else
        until = Inf;
    end
    name = config.OffEvent;
    if levels(i)
        name = config.OnEvent;
    end
    edges = [];
    if isfield(trial.Events, name)
        edges = trial.Events.(name);
    end
    edge = edges(find(edges >= times(i) & edges < until, 1));
    if isempty(edge)
        edge = NaN;
    end
    commands(end+1) = struct('On', levels(i), 'CommandTime', times(i), 'EdgeTime', edge, ...
                             'Latency', edge - times(i)); %#ok<AGROW> % 2 x Count rows, once
end


function t = stateEntry(trial, name)
t = NaN;
if isfield(trial.States, name) && ~isnan(trial.States.(name)(1))
    t = trial.States.(name)(1);
end


function restore(previousHandler, previousStatus, houseLight, pulsePal)
% Put Bpod's soft code handler and status back, the light off and PulsePal's port free.
% RunStateMachine leaves Status.BeingUsed at 1, which would make the next utility (or this
% one again) think a protocol is running.
global BpodSystem %#ok<GVMIS>
BpodSystem.SoftCodeHandlerFunction = previousHandler;
BpodSystem.Status.BeingUsed = previousStatus(1);
BpodSystem.Status.InStateMatrix = previousStatus(2);
houseLight.close();
pulsePal.close();


function printReport(report, config)
fprintf('  %d of %d switch(es) reached %s', report.nFound, numel(report.Commands), config.Input);
if report.nFound > 0
    fprintf(', latency median %.1f ms, max %.1f ms', 1000 * report.MedianLatency, 1000 * report.MaxLatency);
end
fprintf('.\n');
for c = report.Commands
    level = 'off';
    event = config.OffEvent;
    if c.On
        level = 'on ';
        event = config.OnEvent;
    end
    if isnan(c.EdgeTime)
        fprintf('    %s at %8.4f s: no %s\n', level, c.CommandTime, event);
    else
        fprintf('    %s at %8.4f s: %s at %8.4f s (+%.1f ms)\n', level, c.CommandTime, event, ...
                c.EdgeTime, 1000 * c.Latency);
    end
end
if report.Emulated
    fprintf('TestHouseLight: emulator mode; the edges are emulated and the latencies mean nothing.\n');
elseif report.Passed
    fprintf('TestHouseLight: passed. Bpod logs every house light switch.\n');
elseif report.nFound == 0
    fprintf(['TestHouseLight: no edge reached Bpod. Did the light blink? If it did, check the '...
             'splitter and the cable into %s, and that the input is enabled. If it did not, '...
             'check PulsePal output %d and the LED driver.\n'], config.Input, config.PulsePalChannel);
else
    fprintf('TestHouseLight: some switches did not reach Bpod; check the cable into %s.\n', config.Input);
end
