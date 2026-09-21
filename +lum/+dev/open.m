function devices = open(rig, S, varargin)
% lum.dev.open constructs the session's hardware shims, once, at startup.
%
% This is the only place in the protocol that reads BpodSystem.EmulatorMode.
% Everything downstream asks a device whether it is Available, or simply calls it
% and lets the null shim log the call. That keeps emulator support structural
% rather than a condition sprinkled through the trial-building code.
%
% Arguments:
%   rig  Channel map from RigConfig
%   S    Settings struct; S.Session decides which devices the session needs
%
% Options:
%   'Only'      'DoricLED' to open the Doric LED alone, at once, as the protocol launches:
%               it connects in the background while the setup dialogs are open, and they
%               use it (the Doric LED tab, calibration). Returns .emulated and .doricLED.
%   'DoricLED'  That lum.dev.DoricLED, for the session to use rather than open another.
%               The caller keeps it: a refusal here does not close it.
%
% Returns a struct with fields:
%   .emulated  True when Bpod is running as an emulator
%   .pulsePal  lum.dev.PulsePal subclass — optogenetic carrier waveform
%   .hifi      lum.dev.HiFi subclass — sound
%   .flex      lum.dev.Flex subclass — flow meter stream and sync TTL
%   .cameras   lum.dev.Cameras subclass — video, through spincam (lum.dev.openCameras)
%   .houseLight lum.dev.HouseLight subclass — the house light on PulsePal output 3,
%              starting at S.Session.HouseLight, switched at once; disabled in a session
%              without light that has no PulsePal (lum.dev.openHouseLight)
%   .doricLED  lum.dev.DoricLED — the LED driver, both channels in external TTL mode at
%              S.Doric.CurrentmA (lum.dev.openDoricLED, D17); 'Manual' when it is set by
%              hand
%
% The HiFi module, when it is asked for but unreachable, degrades to its null shim
% with a warning rather than ending the session: a rig with a loose HiFi cable can
% still run a silent session. PulsePal does too in a session without light, which then runs
% without the house light (lum.dev.openHouseLight greys its switch out). A session that
% delivers light does not: Bpod would gate channels A and B into a PulsePal it never
% programmed, so it refuses to start without it (lum.dev.openPulsePal). Cameras refuse the same way when video is asked for and cannot
% be recorded (lum.dev.openCameras). PulsePal is opened first, the cameras second and the
% house light third, and a refusal closes what was opened before it, so it leaves nothing
% open and the light off.
%
% See also: RigConfig, CheckRig, lum.dev.Device, lum.dev.openPulsePal

global BpodSystem %#ok<GVMIS> % The one place emulator mode is read

p = inputParser;
p.FunctionName = 'lum.dev.open';
addParameter(p, 'Only', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'DoricLED', [], @(x) isempty(x) || isa(x, 'lum.dev.DoricLED'));
parse(p, varargin{:});

devices = struct();
devices.emulated = ~isempty(BpodSystem) && isobject(BpodSystem) && BpodSystem.EmulatorMode == 1;
if strcmp(p.Results.Only, 'DoricLED')
    devices.doricLED = lum.dev.openDoricLED(devices.emulated, S);
    return
end

if devices.emulated
    fprintf(['LuminoseFM: emulator mode. Bpod emulates a state machine r0.7-1.0, so this '...
             'session has\n  %d global timers (the rig has 16) and no Flex I/O. '...
             'Hardware calls are logged, not sent.\n'], rig.Limits.GlobalTimers);
end

led = p.Results.DoricLED;
if isempty(led)
    led = lum.dev.openDoricLED(devices.emulated, S);
end
setUpDoricLED(led, devices.emulated, S);
devices.doricLED = led;

devices.pulsePal = lum.dev.openPulsePal(devices.emulated, S);
try
    devices.cameras = lum.dev.openCameras(devices.emulated, S);
catch cameraError
    devices.pulsePal.close();
    rethrow(cameraError);
end
try
    devices.houseLight = lum.dev.openHouseLight(devices.emulated, rig.HouseLight, S, devices.pulsePal);
catch houseLightError
    devices.cameras.close();
    devices.pulsePal.close();
    rethrow(houseLightError);
end
devices.houseLight.attachCameras(devices.cameras);
devices.hifi     = openHiFi(devices.emulated, rig, S);
devices.flex     = openFlex(devices.emulated, rig);


function setUpDoricLED(led, emulated, S)
% Both LED channels in external TTL mode at the session's currents, or a refusal.
needsControl = strcmp(S.Session.Type, 'EphysCalibration');
if ~led.isControlled()
    if needsControl && ~emulated
        error('lum:dev:open:noDoricLED', ...
              ['An ePhys calibration session changes the LED current step by step, so it needs the '...
               'Doric LED controlled from MATLAB (%s). Tick "Control the LED from MATLAB" on the Doric '...
               'LED tab, with the DoricLED package found.'], led.Reason);
    end
    return
end
try
    led.ensureReady();
    led.setUp(S.Doric.CurrentmA, S.Doric.MaxCurrentmA);
    led.beginSession();
catch ledError
    if (S.Session.UseOpto || needsControl) && ~emulated
        error('lum:dev:open:noDoricLED', ...
              ['The Doric LED driver could not be set up:\n  %s\n\nThe session has not started. '...
               'Check the driver''s USB cable and power, and close Doric Neuroscience Studio or any '...
               'other program using it. Then start the session again, or untick "Control the LED '...
               'from MATLAB" on the Doric LED tab to use the driver as set by hand (external TTL '...
               'mode).'], ledError.message);
    end
    warning('lum:dev:open:doricLEDNotSetUp', ...
            'The Doric LED driver could not be set up (%s). The session runs without it.', ...
            ledError.message);
end


function hifi = openHiFi(emulated, rig, S)
% Connect to the HiFi module, or explain why the session will run silently.
global BpodSystem %#ok<GVMIS>

samplingRate = S.Sound.SamplingRate;
if ~S.Session.UseSound
    hifi = lum.dev.NullHiFi(rig.Sound.Module, samplingRate, 'sound disabled for this session');
    return
end
if emulated
    % assertModule errors outright in emulator mode, so it must not be reached here.
    hifi = lum.dev.NullHiFi(rig.Sound.Module, samplingRate, 'emulator mode');
    return
end
try
    BpodSystem.assertModule('HiFi', 1);  % 1 = must also be paired with its USB port
    hifi = lum.dev.RealHiFi(rig.Sound.Module, BpodSystem.ModuleUSB.(rig.Sound.Module), ...
                            samplingRate, S.Sound.Attenuation_dB);
catch connectionError
    warning('lum:dev:open:noHiFi', ...
            ['Could not connect to the HiFi module: %s\n'...
             'The session will run, but sound states will be silent.'], ...
            connectionError.message);
    hifi = lum.dev.NullHiFi(rig.Sound.Module, samplingRate, 'connection failed');
end


function flex = openFlex(emulated, rig)
% Describe the Flex I/O configuration, which the operator sets in the Bpod console.
global BpodSystem %#ok<GVMIS>

if emulated
    flex = lum.dev.NullFlex('emulator mode: the emulated r0.7-1.0 has no Flex I/O');
    return
end
if BpodSystem.HW.n.FlexIO == 0
    flex = lum.dev.NullFlex('this state machine has no Flex I/O channels');
    return
end
analogChannels = find(BpodSystem.HW.FlexIO_ChannelTypes == 2);  % 2 = analog input
% Read the rate from FlexIOConfig, not HW.FlexIO_SamplingRate: the latter is only
% assigned when the channel types are changed (BpodObject.m:523), so it can be
% undefined in a session that started with the saved configuration already applied.
samplingRate = BpodSystem.FlexIOConfig.analogSamplingRate;
syncChannel = '';
if rig.Available.Sync
    syncChannel = rig.Sync.Channel;
end
flex = lum.dev.RealFlex(analogChannels, samplingRate, syncChannel);
