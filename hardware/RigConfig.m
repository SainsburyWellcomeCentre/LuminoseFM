function rig = RigConfig()
% RigConfig returns the LuminoseFM channel map: the single source of truth.
%
% Nothing else in the protocol should hard-code 'PWM3', 'Valve1' or 'BNC2'.
% Everything reads the names from this struct, so re-wiring the rig is a
% one-file change.
%
% Usage:
%   rig = RigConfig;                      % the map, plus live limits if Bpod is running
%
% Fields:
%   rig.Ports        Behaviour port numbers by role (Left/Centre/Right/Air/HouseLight)
%   rig.Sides        {'Left','Right'}; side index 1 = Left, 2 = Right throughout
%   rig.LED          Output channel driving each port's LED, by role
%   rig.Valve        Output channel driving each port's solenoid, by role
%   rig.PokeIn       Event name for entry into each port, by role
%   rig.PokeOut      Event name for exit from each port, by role
%   rig.PortLine     Condition channel name for each port, by role
%   rig.Opto         Channel names of the two optical pattern lines (BNC1/BNC2)
%   rig.Sync         Output channel for the sync TTL (Flex2 as digital out)
%   rig.Sound        Module name for the HiFi module
%   rig.Limits       Global timer / counter / condition budget of the connected machine
%   rig.Available    Logical flags: which of the above actually exist right now
%   rig.MachineModel State machine model string, or 'unknown' if Bpod is not running
%
% rig.Limits and rig.Available are read from the connected state machine when
% Bpod is running. They differ between the rig and the emulator: Bpod('EMU')
% emulates a Bpod r0.7-1.0 with only 5 global timers and no Flex I/O, while the
% rig is an r2+ with 16 global timers and Flex I/O. Always size patterns against
% rig.Limits.GlobalTimers rather than assuming 16.
%
% See also: CheckRig, lum.pattern.validate

global BpodSystem %#ok<GVMIS> % Imported to read the connected machine's channel list

%% Fixed wiring (see README §2 and the hardware map in CLAUDE.md)
% Ports 1-3 are the behaviour ports proper: each has a photogate, an LED and a
% water valve. Reward is delivered at the left and right ports only; the centre
% port's valve is wired but the task does not use it. Ports 4 and 5 carry one
% line each — port 4 the air valve, port 5 the house light LED — so the other
% names generated below (rig.LED.Air, rig.Valve.HouseLight, and the port 4/5
% photogates) exist as state machine channels but are connected to nothing.
rig.Ports = struct('Left', 1, 'Centre', 2, 'Right', 3, 'Air', 4, 'HouseLight', 5);
rig.Sides = {'Left', 'Right'};      % Side index 1 = Left, 2 = Right
rig.SidePorts = [rig.Ports.Left rig.Ports.Right];

roles = fieldnames(rig.Ports);
for i = 1:numel(roles)
    portNumber = rig.Ports.(roles{i});
    rig.LED.(roles{i})      = sprintf('PWM%d', portNumber);
    rig.Valve.(roles{i})    = sprintf('Valve%d', portNumber);
    rig.PokeIn.(roles{i})   = sprintf('Port%dIn', portNumber);
    rig.PokeOut.(roles{i})  = sprintf('Port%dOut', portNumber);
    rig.PortLine.(roles{i}) = sprintf('Port%d', portNumber);
end

% Optical channels, named A and B wherever the operator sees them:
%   A = BNC1 -> PulsePal IN1 -> OUT1 -> Doric LED ch1
%   B = BNC2 -> PulsePal IN2 -> OUT2 -> Doric LED ch2
rig.Opto.Channels = {'BNC1', 'BNC2'};
rig.Opto.Labels = {'A', 'B'};
rig.Opto.nChannels = numel(rig.Opto.Channels);

% Sync TTL to the acquisition devices, via Flex2 configured as a digital output.
rig.Sync.Channel = 'Flex2DO';

% HiFi module, registered on Module#1.
rig.Sound.Module = 'HiFi1';

%% Live limits and availability
% Defaults describe the rig (Bpod r2+, firmware 23) so that RigConfig is still
% usable with Bpod not running, e.g. from a unit test or an analysis script.
rig.MachineModel = 'unknown';
rig.Limits = struct('GlobalTimers', 16, 'GlobalCounters', 8, 'Conditions', 16, ...
                    'MaxStates', 256);
rig.Available = struct('Opto', true, 'Sync', false, 'Sound', false, 'Valves', true);

if isempty(BpodSystem) || ~isobject(BpodSystem) || ~isprop(BpodSystem, 'StateMachineInfo') ...
        || ~isfield(BpodSystem.StateMachineInfo, 'OutputChannelNames')
    return
end

outputs = BpodSystem.StateMachineInfo.OutputChannelNames;
rig.MachineModel = BpodSystem.HW.StateMachineModel;
rig.Limits.GlobalTimers   = BpodSystem.HW.n.GlobalTimers;
rig.Limits.GlobalCounters = BpodSystem.HW.n.GlobalCounters;
rig.Limits.Conditions     = BpodSystem.HW.n.Conditions;
rig.Limits.MaxStates      = BpodSystem.StateMachineInfo.MaxStates;

rig.Available.Opto   = all(ismember(rig.Opto.Channels, outputs));
rig.Available.Sync   = ismember(rig.Sync.Channel, outputs);
rig.Available.Sound  = ismember(rig.Sound.Module, outputs);
rig.Available.Valves = all(ismember(struct2cell(rig.Valve)', outputs));
