function report = CheckRig(varargin)
% CheckRig runs the LuminoseFM preflight checks and prints a report.
%
% Run it from the MATLAB prompt before starting a session, or let the protocol
% run it at startup. Each check is one line: OK, a warning, or a failure with the
% exact thing to change and where. Checks that cannot mean anything without
% hardware are reported as skipped in emulator mode rather than failing.
%
% Usage:
%   CheckRig                      % print the report
%   report = CheckRig;            % also return it
%   CheckRig('Strict', true)      % error if any check failed
%
% Returns a struct with:
%   .checks   Struct array with .name, .status ('ok'|'warn'|'fail'|'skip'), .message
%   .nFailed  Number of failed checks
%   .emulated True in emulator mode
%
% See also: RigConfig, lum.dev.open

global BpodSystem %#ok<GVMIS> % Imported to inspect the connected machine

p = inputParser;
p.FunctionName = 'CheckRig';
addParameter(p, 'Strict', false, @(x) islogical(x) || isnumeric(x));
addParameter(p, 'Quiet', false, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});

report = struct('checks', struct('name', {}, 'status', {}, 'message', {}), ...
                'nFailed', 0, 'emulated', false);

if isempty(BpodSystem) || ~isobject(BpodSystem) || ~isprop(BpodSystem, 'EmulatorMode')
    report = addCheck(report, 'Bpod running', 'fail', ...
                      'Bpod is not running. Start it with Bpod (or Bpod(''EMU'')) first.');
    report = finish(report, p.Results);
    return
end

report.emulated = BpodSystem.EmulatorMode == 1;
rig = RigConfig;

%% State machine
if report.emulated
    report = addCheck(report, 'State machine', 'skip', ...
        sprintf(['emulator mode: Bpod emulates a %s with %d global timers and no Flex I/O, '...
                 'not the rig''s r2+ with 16'], rig.MachineModel, rig.Limits.GlobalTimers));
else
    report = addCheck(report, 'State machine', 'ok', ...
        sprintf('%s, firmware v%d, %d behaviour ports, %d global timers', ...
                rig.MachineModel, BpodSystem.FirmwareVersion, BpodSystem.HW.n.Ports, ...
                rig.Limits.GlobalTimers));
end

%% Behaviour ports
missingPorts = {};
roles = fieldnames(rig.Ports);
for i = 1:numel(roles)
    if rig.Ports.(roles{i}) > BpodSystem.HW.n.Ports
        missingPorts{end+1} = sprintf('%s (port %d)', roles{i}, rig.Ports.(roles{i})); %#ok<AGROW>
    end
end
if isempty(missingPorts)
    report = addCheck(report, 'Behaviour ports', 'ok', ...
        sprintf('Left=%d Centre=%d Right=%d Air=%d HouseLight=%d', ...
                rig.Ports.Left, rig.Ports.Centre, rig.Ports.Right, rig.Ports.Air, ...
                rig.Ports.HouseLight));
else
    report = addCheck(report, 'Behaviour ports', 'fail', ...
        sprintf('this state machine has only %d ports; missing: %s', ...
                BpodSystem.HW.n.Ports, strjoin(missingPorts, ', ')));
end

%% Optical pattern lines
if rig.Available.Opto
    report = addCheck(report, 'Opto BNC lines', 'ok', ...
        sprintf('%s drive the PulsePal trigger inputs', strjoin(rig.Opto.Channels, ' and ')));
else
    report = addCheck(report, 'Opto BNC lines', 'fail', ...
        sprintf('%s not found in this machine''s output channels', ...
                strjoin(rig.Opto.Channels, '/')));
end

%% HiFi module
if report.emulated
    report = addCheck(report, 'HiFi module', 'skip', ...
        'not emulated; sound states will run silently');
elseif ~ismember(rig.Sound.Module, BpodSystem.Modules.Name)
    report = addCheck(report, 'HiFi module', 'fail', ...
        ['not registered. Connect it to a state machine Module port and click '...
         'refresh on the Bpod console.']);
elseif ~isfield(BpodSystem.ModuleUSB, rig.Sound.Module)
    report = addCheck(report, 'HiFi module', 'fail', ...
        'registered but not USB-paired. Click the USB config button on the Bpod console.');
else
    report = addCheck(report, 'HiFi module', 'ok', ...
        sprintf('%s paired with %s', rig.Sound.Module, BpodSystem.ModuleUSB.(rig.Sound.Module)));
end

%% Flex I/O
if report.emulated
    report = addCheck(report, 'Flex I/O', 'skip', ...
        'the emulated r0.7-1.0 has no Flex I/O: no flow meter, no sync TTL');
else
    types = BpodSystem.HW.FlexIO_ChannelTypes;  % 0=DI 1=DO 2=ADC 3=DAC 4=disabled
    analogChannels = find(types == 2);
    if isempty(analogChannels)
        report = addCheck(report, 'Flex I/O flow meter', 'warn', ...
            ['no analog input configured, so the flow meter will not be recorded. '...
             'Set Flex1 to analog input in the Bpod console.']);
    else
        report = addCheck(report, 'Flex I/O flow meter', 'ok', ...
            sprintf('analog input on Flex %s at %g Hz', mat2str(analogChannels), ...
                    BpodSystem.FlexIOConfig.analogSamplingRate));
    end
    if rig.Available.Sync
        report = addCheck(report, 'Flex I/O sync TTL', 'ok', ...
            sprintf('%s available as a digital output', rig.Sync.Channel));
    else
        report = addCheck(report, 'Flex I/O sync TTL', 'warn', sprintf( ...
            ['%s does not exist, so no sync pulse will be sent to the acquisition '...
             'devices. Set Flex2 to digital output in the Bpod console Flex I/O '...
             'settings.'], rig.Sync.Channel));
    end
    if isfield(BpodSystem.Status, 'RecordAnalog') && BpodSystem.Status.RecordAnalog ~= 1 ...
            && ~isempty(analogChannels)
        report = addCheck(report, 'Flex I/O recording', 'warn', ...
            'analog recording is disabled; enable it from the Bpod console analog viewer.');
    end
end

%% PulsePal
if report.emulated
    report = addCheck(report, 'PulsePal', 'skip', 'not reachable in emulator mode');
else
    pulsePalRoot = fullfile(fileparts(fileparts(lum.repoRoot)), 'PulsePal');
    if ~isfolder(fullfile(pulsePalRoot, 'MATLAB'))
        report = addCheck(report, 'PulsePal', 'fail', ...
            sprintf('MATLAB folder not found at %s', fullfile(pulsePalRoot, 'MATLAB')));
    else
        % Only report whether the code is reachable. Opening the port here would
        % leave it open, or collide with a session that is about to open it itself.
        report = addCheck(report, 'PulsePal', 'ok', ...
            sprintf('code found at %s; the port is opened at session start', pulsePalRoot));
    end
end

%% Liquid calibration
% Ask for the valve times the protocol will actually need. The calibration table
% is a struct in older Bpod versions and a ValveDataManager object in v1.9.0, so
% exercising GetValveTimes is both simpler and more truthful than inspecting it.
try
    valveTimes = GetValveTimes(1, rig.SidePorts);
    report = addCheck(report, 'Liquid calibration', 'ok', ...
        sprintf('reward ports %s calibrated (%s ms for 1 ul)', mat2str(rig.SidePorts), ...
                strjoin(compose('%.1f', valveTimes*1000), '/')));
catch calibrationError
    report = addCheck(report, 'Liquid calibration', 'fail', sprintf( ...
        ['reward ports %s: %s Run BpodLiquidCalibration(''Calibrate'') and calibrate '...
         'them around the session''s reward volume.'], mat2str(rig.SidePorts), ...
        calibrationError.message));
end

%% Data folder
if isempty(BpodSystem.Path.DataFolder) || ~isfolder(BpodSystem.Path.DataFolder)
    report = addCheck(report, 'Data folder', 'fail', ...
        sprintf('%s is not reachable. Set it from the Bpod console settings menu.', ...
                BpodSystem.Path.DataFolder));
else
    report = addCheck(report, 'Data folder', 'ok', BpodSystem.Path.DataFolder);
end

report = finish(report, p.Results);


function report = addCheck(report, name, status, message)
% Append one check result to the report.
report.checks(end+1) = struct('name', name, 'status', status, 'message', message);
if strcmp(status, 'fail')
    report.nFailed = report.nFailed + 1;
end


function report = finish(report, options)
% Print the report, and error if the caller asked for strict checking.
if ~options.Quiet
    fprintf('\nLuminoseFM preflight\n');
    labels = struct('ok', '  ok  ', 'warn', ' warn ', 'fail', ' FAIL ', 'skip', ' skip ');
    for i = 1:numel(report.checks)
        check = report.checks(i);
        fprintf('[%s] %-22s %s\n', labels.(check.status), check.name, check.message);
    end
    fprintf('\n');
end
if options.Strict && report.nFailed > 0
    error('lum:CheckRig:failed', ...
          '%d preflight check(s) failed. See the report above.', report.nFailed);
end
