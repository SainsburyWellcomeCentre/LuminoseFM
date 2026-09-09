function TestHiFiSound(varargin)
% TestHiFiSound plays a test sound through the HiFi module.
%
% The Bpod console can test ports, valves, LEDs and BNC lines by hand, but not
% sound. This utility fills that gap: it connects to the HiFi module, plays a
% waveform, and disconnects, without launching a protocol.
%
% Usage:
%   TestHiFiSound                                  % 1 kHz tone, 0.5 s, both channels
%   TestHiFiSound('Frequency', 8000)               % 8 kHz tone
%   TestHiFiSound('Waveform', 'noise')             % white noise burst
%   TestHiFiSound('Waveform', 'sweep', 'FreqRange', [2000 20000])
%   TestHiFiSound('Channel', 'left')               % check speaker wiring
%   TestHiFiSound('Repeat', 5, 'Interval', 0.25)   % repeated beeps
%   TestHiFiSound('Attenuation', -20)              % quieter (dB FS, <= 0)
%   TestHiFiSound('Port', 'COM8')                  % explicit port, Bpod not running
%   TestHiFiSound('HiFi', H)                       % reuse an open BpodHiFi object
%   TestHiFiSound('Device', 'pc')                  % play on PC speakers instead
%
% Options (name/value):
%   Waveform     'tone' (default) | 'noise' | 'sweep' | 'chord'
%   Frequency    Tone frequency in Hz (default 1000). For 'chord', a vector of Hz.
%   FreqRange    [start end] Hz for 'sweep' (default [1000 20000])
%   Duration     Seconds (default 0.5)
%   Amplitude    Fraction of full scale, 0-1 (default 0.5)
%   Channel      'both' (default) | 'left' | 'right'
%   Repeat       Number of plays (default 1)
%   Interval     Seconds of silence between repeats (default 0.5)
%   SamplingRate 44100 | 48000 | 96000 | 192000 (default 192000)
%   Attenuation  Digital attenuation in dB FS, <= 0 (default 0)
%   RampDuration Onset/offset ramp in seconds, avoids clicks (default 0.005)
%   SlotIndex    HiFi memory slot to load into (default 20, the last slot)
%   Port         COM port of the HiFi module, e.g. 'COM8'
%   HiFi         An existing BpodHiFi object to reuse (not closed on exit)
%   Device       'hifi' (default) | 'pc' to force playback through MATLAB's sound()
%   Force        true to run even while a protocol is in progress (default false)
%
% Notes:
% - With no 'Port' or 'HiFi' argument, the module's port is taken from
%   BpodSystem.ModuleUSB.HiFi1, so Bpod must be running and the module USB-paired
%   via the console's USB button.
% - The HiFi module is not available in emulator mode; there the utility falls back
%   to MATLAB's sound() on the PC's own audio device, so the rest of a session can
%   still be rehearsed offline. Pass 'Device','pc' to force that path deliberately.
% - Loading a sound overwrites the target slot in the module's active sound set, so
%   the utility refuses to run while a protocol is in progress unless 'Force' is set.

global BpodSystem %#ok<GVMIS> % Imported to find the module's USB port

%% Parse arguments
p = inputParser;
p.FunctionName = 'TestHiFiSound';
addParameter(p, 'Waveform', 'tone', @(x) ischar(x) || isstring(x));
addParameter(p, 'Frequency', 1000, @(x) isnumeric(x) && all(x > 0));
addParameter(p, 'FreqRange', [1000 20000], @(x) isnumeric(x) && numel(x) == 2);
addParameter(p, 'Duration', 0.5, @(x) isnumeric(x) && isscalar(x) && x > 0);
addParameter(p, 'Amplitude', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0 && x <= 1);
addParameter(p, 'Channel', 'both', @(x) ischar(x) || isstring(x));
addParameter(p, 'Repeat', 1, @(x) isnumeric(x) && isscalar(x) && x >= 1);
addParameter(p, 'Interval', 0.5, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'SamplingRate', 192000, @(x) ismember(x, [44100 48000 96000 192000]));
addParameter(p, 'Attenuation', 0, @(x) isnumeric(x) && isscalar(x) && x <= 0);
addParameter(p, 'RampDuration', 0.005, @(x) isnumeric(x) && isscalar(x) && x >= 0);
addParameter(p, 'SlotIndex', 20, @(x) isnumeric(x) && isscalar(x) && x >= 1 && x <= 20);
addParameter(p, 'Port', '', @(x) ischar(x) || isstring(x));
addParameter(p, 'HiFi', [], @(x) isempty(x) || isa(x, 'BpodHiFi'));
addParameter(p, 'Device', 'hifi', @(x) ischar(x) || isstring(x));
addParameter(p, 'Force', false, @(x) islogical(x) || isnumeric(x));
parse(p, varargin{:});
opt = p.Results;
waveformType = lower(char(opt.Waveform));
channel = lower(char(opt.Channel));
device = lower(char(opt.Device));

if ~ismember(waveformType, {'tone', 'noise', 'sweep', 'chord'})
    error('TestHiFiSound:badWaveform', ...
          'Waveform must be one of: tone, noise, sweep, chord.');
end
if ~ismember(channel, {'both', 'left', 'right'})
    error('TestHiFiSound:badChannel', 'Channel must be one of: both, left, right.');
end
if ~ismember(device, {'hifi', 'pc'})
    error('TestHiFiSound:badDevice', 'Device must be one of: hifi, pc.');
end

%% Refuse to clobber a running session
if ~opt.Force && ~isempty(BpodSystem) && isobject(BpodSystem) ...
        && isprop(BpodSystem, 'Status') && isstruct(BpodSystem.Status) ...
        && isfield(BpodSystem.Status, 'BeingUsed') && BpodSystem.Status.BeingUsed == 1
    error('TestHiFiSound:protocolRunning', ...
          ['A protocol is currently running. Playing a test sound would overwrite '...
           'sound slot %d in the active sound set. Stop the protocol first, or pass '...
           '''Force'', true if you are sure.'], opt.SlotIndex);
end

%% Build the waveform
sf = opt.SamplingRate;
stereoWave = buildStereoWaveform(waveformType, opt, channel, sf);

% Ramp coefficients, applied at onset and in reverse at offset. The module applies these
% itself via AMenvelope; on the PC path they are multiplied into the waveform below.
envelope = buildEnvelope(opt.RampDuration, sf, size(stereoWave, 2));

%% Resolve the playback device
useHiFi = strcmp(device, 'hifi');
hifi = opt.HiFi;
ownsConnection = false;

if useHiFi && isempty(hifi)
    portString = char(opt.Port);
    if isempty(portString)
        if ~isempty(BpodSystem) && isobject(BpodSystem) ...
                && isprop(BpodSystem, 'EmulatorMode') && BpodSystem.EmulatorMode == 1
            fprintf(['TestHiFiSound: Bpod is in emulator mode, where the HiFi module is '...
                     'not available.\n  Falling back to the PC audio device.\n']);
            useHiFi = false;
        elseif ~isempty(BpodSystem) && isobject(BpodSystem) ...
                && isprop(BpodSystem, 'ModuleUSB') && isfield(BpodSystem.ModuleUSB, 'HiFi1') ...
                && ~isempty(BpodSystem.ModuleUSB.HiFi1)
            portString = BpodSystem.ModuleUSB.HiFi1;
        else
            fprintf(['TestHiFiSound: no HiFi module found. Start Bpod and pair the module '...
                     'with its USB port\n  (console USB button), or pass ''Port'', ''COM8''.'...
                     '\n  Falling back to the PC audio device.\n']);
            useHiFi = false;
        end
    end
    if useHiFi
        fprintf('TestHiFiSound: connecting to HiFi module on %s...\n', portString);
        hifi = BpodHiFi(portString);
        ownsConnection = true;
    end
end

%% Play
cleanup = onCleanup(@() closeConnection(hifi, ownsConnection));

if useHiFi
    fprintf('  HiFi module: hardware v%s, firmware v%s\n', ...
            num2str(hifi.Info.hardwareVersion), num2str(hifi.Info.firmwareVersion));
    hifi.SamplingRate = sf;
    hifi.DigitalAttenuation_dB = opt.Attenuation;
    if ~isempty(envelope)
        hifi.AMenvelope = envelope;
    end
    hifi.load(opt.SlotIndex, stereoWave);
    hifi.push;
    describePlayback(waveformType, opt, channel, sf, 'HiFi module');
    for i = 1:opt.Repeat
        hifi.play(opt.SlotIndex);
        pause(opt.Duration);
        hifi.stop;
        if i < opt.Repeat
            pause(opt.Interval);
        end
    end
else
    % PC fallback. Rebuild the waveform at a rate the PC's audio device can handle,
    % rather than decimating the 192 kHz version, which would alias.
    pcSamplingRate = min(sf, 48000);
    pcWave = stereoWave;
    if pcSamplingRate ~= sf
        pcWave = buildStereoWaveform(waveformType, opt, channel, pcSamplingRate);
    end
    pcEnvelope = buildEnvelope(opt.RampDuration, pcSamplingRate, size(pcWave, 2));
    if ~isempty(pcEnvelope)
        nRamp = numel(pcEnvelope);
        ramp = ones(1, size(pcWave, 2));
        ramp(1:nRamp) = pcEnvelope;
        ramp(end-nRamp+1:end) = fliplr(pcEnvelope);
        pcWave = pcWave .* ramp;
    end
    pcWave = pcWave * 10^(opt.Attenuation/20);
    describePlayback(waveformType, opt, channel, pcSamplingRate, 'PC audio device');
    for i = 1:opt.Repeat
        sound(pcWave', pcSamplingRate);
        pause(size(pcWave, 2)/pcSamplingRate);
        if i < opt.Repeat
            pause(opt.Interval);
        end
    end
end

fprintf('  Done.\n');


function stereoWave = buildStereoWaveform(waveformType, opt, channel, sf)
% Generate the test waveform at sampling rate sf and map it to the output channel(s)
switch waveformType
    case 'tone'
        wave = GenerateSineWave(sf, opt.Frequency(1), opt.Duration) * opt.Amplitude;
    case 'noise'
        wave = GenerateWhiteNoise(sf, opt.Duration, opt.Amplitude, 1);
    case 'sweep'
        wave = GenerateSineSweep(sf, opt.FreqRange(1), opt.FreqRange(2), opt.Duration) ...
               * opt.Amplitude;
    case 'chord'
        wave = GenerateSineChord(sf, opt.Frequency, opt.Duration) * opt.Amplitude;
end
wave = reshape(wave(1, :), 1, []); % Ensure a 1 x nSamples row vector
switch channel
    case 'both'
        stereoWave = [wave; wave];
    case 'left'
        stereoWave = [wave; zeros(1, numel(wave))];
    case 'right'
        stereoWave = [zeros(1, numel(wave)); wave];
end


function envelope = buildEnvelope(rampDuration, sf, nSamples)
% Linear onset ramp of amplitude coefficients, or empty if the sound is too short to ramp
nRampSamples = round(rampDuration * sf);
if nRampSamples > 1 && nRampSamples * 2 < nSamples
    envelope = (1:nRampSamples) / nRampSamples;
else
    envelope = [];
end


function describePlayback(waveformType, opt, channel, sf, deviceName)
% Print a one-line summary of what is about to play
switch waveformType
    case 'tone'
        detail = sprintf('%g Hz tone', opt.Frequency(1));
    case 'noise'
        detail = 'white noise';
    case 'sweep'
        detail = sprintf('%g-%g Hz sweep', opt.FreqRange(1), opt.FreqRange(2));
    case 'chord'
        detail = sprintf('%d-tone chord', numel(opt.Frequency));
end
fprintf('  Playing %s, %g s, amplitude %g, %s channel(s), %g Hz, on the %s.\n', ...
        detail, opt.Duration, opt.Amplitude, channel, sf, deviceName);


function closeConnection(hifi, ownsConnection)
% Release the serial port if this function opened it
if ownsConnection && ~isempty(hifi)
    clear hifi
end
