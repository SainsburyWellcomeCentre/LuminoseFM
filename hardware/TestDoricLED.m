function report = TestDoricLED(varargin)
% TestDoricLED lights channels A and B through the whole light path, as a session does.
%
% The light path (docs/hardware.md §2.2, D1, D17):
%
%   Bpod BNC1 -> PulsePal IN1 -> OUT1 -> Doric LED channel 1 (TTL input) -> channel A
%   Bpod BNC2 -> PulsePal IN2 -> OUT2 -> Doric LED channel 2 (TTL input) -> channel B
%
% This connects the Doric driver through the DoricLED package and puts both channels in
% external TTL mode at a current (lum.dev.DoricLED.setUp), programs PulsePal gated with
% constant light, as a probe is programmed, and runs a state machine that gates BNC1 Count
% times, then BNC2, then both together. With several currents it does this once per
% current, setting the current between state machines, so the light should get brighter
% from one set to the next. Watch the fiber (or a power meter) at the bundle's tip:
%
%   channel A flashes Count times, then channel B, then both together; per current
%
% The software path is checked and reported: the driver's connection and every command
% it acknowledged, PulsePal's programming, and each gate's times on Bpod's clock. Whether
% light came out needs someone to see it: the driver cannot be read back, and nothing
% loops its output into Bpod.
%
% No valve, port LED, sync line or house light is driven. A protocol must not be running.
% The light is left off and both devices released.
%
% Usage:
%   TestDoricLED                              % 50 mA, 3 flashes each, 0.5 s on, 0.5 s off
%   TestDoricLED('Currents', [20 100 300])    % three sets, one per current
%   TestDoricLED('Count', 5, 'On', 1)
%
% Options (name/value):
%   Currents  LED current per set, mA, same on both channels (default 50); each at most
%             MaxCurrent
%   MaxCurrent  The channels' limit, mA (default 700, Doric's recommended maximum)
%   Count     Flashes per channel and per set (default 3)
%   On, Off   Seconds of light, and of dark after it (default 0.5, 0.5)
%   Folder    The DoricLED folder, when it is not on the MATLAB path (default '')
%   Force     true to run even while a protocol is in progress (default false)
%
% Returns a struct: Emulated, LEDMode, LEDDevice, Currents, Sets (per current: Current and
% Gates, a table of Channel, Onset and Offset on Bpod's clock), PulsePalLog, LEDLog,
% LEDRecord and Passed (every command acknowledged and every gate run).
%
% Requires Bpod to be running. Under Bpod('EMU') the driver is the package's simulated one
% and PulsePal the null shim, so the check runs end to end without hardware (doricTest).
%
% See also: TestHouseLight, TestSyncLine, lum.dev.DoricLED, lum.dev.openDoricLED, RigConfig

global BpodSystem %#ok<GVMIS> % Imported to read the machine and run it

p = inputParser;
p.FunctionName = 'TestDoricLED';
addParameter(p, 'Currents', 50, @(x) isnumeric(x) && ~isempty(x) && all(x >= 0) && all(x == round(x)));
addParameter(p, 'MaxCurrent', 700, @(x) isnumeric(x) && isscalar(x) && x > 0 && x <= 1000);
addParameter(p, 'Count', 3, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'On', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0.01);
addParameter(p, 'Off', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0.01);
addParameter(p, 'Folder', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'Force', false, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;

if isempty(BpodSystem) || ~isobject(BpodSystem)
    error('TestDoricLED:noBpod', 'Bpod is not running. Start it with Bpod or Bpod(''EMU'') first.');
end
if BpodSystem.Status.BeingUsed == 1 && ~opt.Force
    error('TestDoricLED:protocolRunning', ...
          ['A protocol is running. Stop it first, or pass ''Force'', true if you are '...
           'certain the rig is free.']);
end
if any(opt.Currents > opt.MaxCurrent)
    error('TestDoricLED:overLimit', 'Every current must be at most MaxCurrent (%g mA).', opt.MaxCurrent);
end

rig = RigConfig;
emulated = BpodSystem.EmulatorMode == 1;
S = lum.defaultSettings();
S.Doric.Enabled = true;
S.Doric.Folder = char(opt.Folder);
S.Doric.CurrentmA = [opt.Currents(1) opt.Currents(1)];
S.Doric.MaxCurrentmA = [opt.MaxCurrent opt.MaxCurrent];
fprintf(['TestDoricLED: channels A (BNC1 -> PulsePal OUT1 -> LED ch1) and B (BNC2 -> OUT2 -> LED ch2), '...
         '%d flash(es) each and then together, %g s on, %g s off, at %s mA.\n'], round(opt.Count), ...
        opt.On, opt.Off, strjoin(arrayfun(@(c) sprintf('%g', c), opt.Currents, 'UniformOutput', false), ', '));

previousStatus = [BpodSystem.Status.BeingUsed, BpodSystem.Status.InStateMatrix];
led = lum.dev.openDoricLED(emulated, S);
cleanup = onCleanup(@() restore(previousStatus, led));
if ~led.isControlled()
    error('TestDoricLED:noPackage', ['The Doric driver is not controlled from MATLAB (%s). Put the '...
          'DoricLED package on the path, or pass its folder.'], led.Reason);
end
led.ensureReady();
led.setUp(S.Doric.CurrentmA, S.Doric.MaxCurrentmA);
fprintf('  LED: %s\n', led.describeState());
pulsePal = openPulsePal(emulated, opt.On);
releasePulsePal = onCleanup(@() closePulsePal(pulsePal));

sets = struct('Current', {}, 'Gates', {});
allRan = true;
for i = 1:numel(opt.Currents)
    current = opt.Currents(i);
    led.setCurrents([current current], i);
    SendStateMachine(gatingMachine(rig, round(opt.Count), opt.On, opt.Off));
    raw = RunStateMachine;
    data = AddTrialEvents(struct(), raw);
    gates = gateTimes(data.RawEvents.Trial{1}, round(opt.Count));
    allRan = allRan && all(~isnan(gates.Onset));
    sets(end+1) = struct('Current', current, 'Gates', gates); %#ok<AGROW> % One per current
    fprintf('  %g mA: %d of %d gates ran (A %d, B %d, A and B %d).\n', current, nnz(~isnan(gates.Onset)), ...
            height(gates), nnz(gates.Channel == "A" & ~isnan(gates.Onset)), ...
            nnz(gates.Channel == "B" & ~isnan(gates.Onset)), ...
            nnz(gates.Channel == "A and B" & ~isnan(gates.Onset)));
end

ledLog = led.log();
failures = ledLog(contains(ledLog, 'could not') | contains(ledLog, 'failed'));
report = struct('Emulated', emulated, 'LEDMode', led.Mode, 'LEDDevice', led.describeState(), ...
                'Currents', opt.Currents, 'Sets', sets, 'PulsePalLog', {pulsePal.log()}, ...
                'LEDLog', {ledLog}, 'LEDRecord', led.record(), ...
                'Passed', allRan && isempty(failures));
delete(releasePulsePal);
delete(cleanup);

if emulated
    fprintf('TestDoricLED: emulator mode; the driver is simulated, and no light was made.\n');
elseif report.Passed
    fprintf(['TestDoricLED: every command was acknowledged and every gate ran. Did channel A flash, '...
             'then B, then both, brighter at each current? If not, check PulsePal OUT1/OUT2 into '...
             'the driver''s TTL inputs, and the driver''s channel 1/2 outputs into the commutator.\n']);
else
    fprintf('TestDoricLED: failed. %s\n', strjoin(failures, ' | '));
end


function pulsePal = openPulsePal(emulated, onSeconds)
% PulsePal as a light session opens it, with constant light while each gate is high.
if emulated
    pulsePal = lum.dev.NullPulsePal('emulator mode');
else
    pulsePal = lum.dev.RealPulsePal(fullfile(fileparts(fileparts(lum.repoRoot)), 'PulsePal'));
end
try
    pulsePal.stopOutputs();
    pulsePal.checkConnection();
    carrier = struct('Channel', {1, 2}, 'Frequency', 0, 'PulseWidth', 0, 'Voltage', 5, ...
                     'MaxDuration', onSeconds + lum.stim.OptoPattern.TrainMargin);
    pulsePal.configure(carrier);
catch openError
    pulsePal.close();
    rethrow(openError);
end


function sma = gatingMachine(rig, count, onSeconds, offSeconds)
% Settle; A001/DarkA001 ... ; B001/DarkB001 ... ; AB001/DarkAB001 ... ; settle.
lanes = {'A', {rig.Opto.Channels{1}, 1}; 'B', {rig.Opto.Channels{2}, 1}; ...
         'AB', {rig.Opto.Channels{1}, 1, rig.Opto.Channels{2}, 1}};
names = {};
for lane = 1:size(lanes, 1)
    for k = 1:count
        names{end+1} = sprintf('%s%03d', lanes{lane, 1}, k); %#ok<AGROW>
    end
end
sma = NewStateMachine();
sma = AddState(sma, 'Name', 'Settle', 'Timer', 0.3, 'StateChangeConditions', {'Tup', names{1}}, ...
               'OutputActions', {});
n = 0;
for lane = 1:size(lanes, 1)
    for k = 1:count
        n = n + 1;
        next = 'SettleEnd';
        if n < numel(names)
            next = names{n + 1};
        end
        sma = AddState(sma, 'Name', names{n}, 'Timer', onSeconds, ...
                       'StateChangeConditions', {'Tup', ['Dark' names{n}]}, 'OutputActions', lanes{lane, 2});
        sma = AddState(sma, 'Name', ['Dark' names{n}], 'Timer', offSeconds, ...
                       'StateChangeConditions', {'Tup', next}, 'OutputActions', {});
    end
end
sma = AddState(sma, 'Name', 'SettleEnd', 'Timer', 0.3, 'StateChangeConditions', {'Tup', '>exit'}, ...
               'OutputActions', {});


function gates = gateTimes(trial, count)
% Each gate's onset and offset, from its light state's entry and exit.
channels = strings(0, 1);
onsets = [];
offsets = [];
labels = {'A', 'A'; 'B', 'B'; 'AB', 'A and B'};
for lane = 1:3
    for k = 1:count
        name = sprintf('%s%03d', labels{lane, 1}, k);
        times = [NaN NaN];
        if isfield(trial.States, name)
            times = trial.States.(name)(1, :);
        end
        channels(end+1, 1) = string(labels{lane, 2}); %#ok<AGROW>
        onsets(end+1, 1) = times(1); %#ok<AGROW>
        offsets(end+1, 1) = times(2); %#ok<AGROW>
    end
end
gates = table(channels, onsets, offsets, 'VariableNames', {'Channel', 'Onset', 'Offset'});


function restore(previousStatus, led)
% The LED off and released, and Bpod's status as it was: RunStateMachine leaves
% Status.BeingUsed at 1, which would make the next utility think a protocol is running.
global BpodSystem %#ok<GVMIS>
BpodSystem.Status.BeingUsed = previousStatus(1);
BpodSystem.Status.InStateMatrix = previousStatus(2);
led.close();


function closePulsePal(pulsePal)
% PulsePal's outputs stopped and its port released.
try
    pulsePal.stopOutputs();
catch
end
pulsePal.close();
