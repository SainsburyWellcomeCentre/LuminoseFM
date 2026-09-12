function devices = open(rig, S)
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
% Returns a struct with fields:
%   .emulated  True when Bpod is running as an emulator
%   .pulsePal  lum.dev.PulsePal subclass — optogenetic carrier waveform
%   .hifi      lum.dev.HiFi subclass — sound
%   .flex      lum.dev.Flex subclass — flow meter stream and sync TTL
%
% The HiFi module, when it is asked for but unreachable, degrades to its null shim
% with a warning rather than ending the session: a rig with a loose HiFi cable can
% still run a silent session. PulsePal does not: a session that delivers light
% refuses to start without it, because Bpod would still gate channels A and B into a
% PulsePal this session never programmed (lum.dev.openPulsePal). PulsePal is opened
% first, so a refusal leaves nothing else open.
%
% See also: RigConfig, CheckRig, lum.dev.Device, lum.dev.openPulsePal

global BpodSystem %#ok<GVMIS> % The one place emulator mode is read

devices = struct();
devices.emulated = ~isempty(BpodSystem) && isobject(BpodSystem) && BpodSystem.EmulatorMode == 1;

if devices.emulated
    fprintf(['LuminoseFM: emulator mode. Bpod emulates a state machine r0.7-1.0, so this '...
             'session has\n  %d global timers (the rig has 16) and no Flex I/O. '...
             'Hardware calls are logged, not sent.\n'], rig.Limits.GlobalTimers);
end

devices.pulsePal = lum.dev.openPulsePal(devices.emulated, S);
devices.hifi     = openHiFi(devices.emulated, rig, S);
devices.flex     = openFlex(devices.emulated, rig);


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
