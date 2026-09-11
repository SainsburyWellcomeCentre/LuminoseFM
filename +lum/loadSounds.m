function sounds = loadSounds(S, devices, stimulusSet)
% lum.loadSounds builds the session's waveforms and loads them into the HiFi module.
%
% Called once, in session setup. Loading during the trial loop would block on a USB
% transfer of a few hundred thousand samples, so the device shim refuses it once the
% session has started (lum.dev.HiFi.freeze).
%
% Only the sounds the session can play are loaded:
%   Noise       the white noise burst used as punishment (always)
%   Cue         the cue tone, if the cue has a tone: a seamless loop, repeated for as
%               long as the longest hold window allows, because the cue lasts until
%               the animal pokes
%   CueTail     the cue tone's last part, if it stops part way through the stimulus:
%               that long, ramped off, played at the poke in place of the loop
%               (lum.stim.CueTone)
%   Group<k>    one tone per stimulus group, if the stimulus has a tone
%   LeftTone,   the tone of each side whose tone is enabled
%   RightTone
%
% Group tones have to differ, or an auditory version of the task has nothing to
% discriminate, so their frequencies are spread logarithmically across
% S.Stimulus.ToneFrequencyRange — about equally discriminable rather than equally
% spaced in Hz — and always match the number of groups the set has. A tone timed to
% start after stimulus onset is loaded with that much silence in front of it, which
% is how a sound gets an onset without a global timer.
%
% Every tone is ramped on and off: an abrupt start produces a broadband click that
% the animal could use in place of the tone. The cue loop is the exception, since a
% ramp would be heard at every repeat; the cue is itself a signal to act, so its onset
% click tells the animal nothing the tone does not.
%
% Arguments:
%   S            Settings struct
%   devices      Device shims from lum.dev.open
%   stimulusSet  Stimulus set, for the number of groups
%
% Returns a containers.Map from sound name to the module slot holding it; empty when
% the session uses no sound. lum.stim.Sound looks names up in it.
%
% See also: lum.dev.HiFi, lum.stim.Sound, TestHiFiSound

sounds = containers.Map('KeyType', 'char', 'ValueType', 'double');
if ~S.Session.UseSound
    return
end

rate = S.Sound.SamplingRate;
amplitude = S.Sound.Amplitude;

names = {'Noise'};
waves = {GenerateWhiteNoise(rate, S.Sound.NoiseDuration, amplitude, 1)};
loops = 0;   % Seconds each sound repeats for once played; 0 plays it once

cue = lum.cueTiming(S);
cueTone = cue(strcmp({cue.Type}, 'Tone'));
if ~isempty(cueTone)
    names{end+1} = 'Cue';
    waves{end+1} = loopedTone(rate, S.Cue.ToneFrequency, amplitude);
    loops(end+1) = S.GUIMeta.HoldWindow.Limits(2);
    if strcmp(cueTone.Mode, 'Timed')
        names{end+1} = 'CueTail';
        waves{end+1} = tail(rate, S.Cue.ToneFrequency, cueTone.Duration, amplitude);
        loops(end+1) = 0;
    end
end

stimulusTone = S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, 'Tone'));
if ~isempty(stimulusTone) && stimulusTone.Enabled
    frequencies = spreadFrequencies(S.Stimulus.ToneFrequencyRange, stimulusSet.nGroups);
    for k = 1:stimulusSet.nGroups
        names{end+1} = sprintf('Group%d', k); %#ok<AGROW>
        waves{end+1} = tone(rate, frequencies(k), stimulusTone.Duration, amplitude, ...
                            stimulusTone.Onset); %#ok<AGROW>
        loops(end+1) = 0; %#ok<AGROW>
    end
end

for side = {'Left', 'Right'}
    sideTone = S.(side{1}).Tone;
    if sideTone.Enabled
        names{end+1} = [side{1} 'Tone']; %#ok<AGROW>
        waves{end+1} = tone(rate, sideTone.Frequency, sideTone.Duration, amplitude, ...
                            sideTone.Onset); %#ok<AGROW>
        loops(end+1) = 0; %#ok<AGROW>
    end
end

if numel(names) > devices.hifi.MaxSlots
    error('lum:loadSounds:tooManySounds', ...
          'This session needs %d sounds but the HiFi module holds %d.', ...
          numel(names), devices.hifi.MaxSlots);
end

for i = 1:numel(names)
    wave = reshape(waves{i}(1, :), 1, []);
    devices.hifi.loadSound(i, [wave; wave], loops(i));  % Same signal to both speaker channels
    sounds(names{i}) = i;
end
devices.hifi.push();


function wave = tone(rate, frequency, duration, amplitude, onset)
% A ramped sine tone, with onset seconds of silence in front of it.
wave = GenerateSineWave(rate, frequency, duration) * amplitude;
wave = applyRamp(reshape(wave(1, :), 1, []), 0.005, rate);
if onset > 0
    wave = [zeros(1, round(onset * rate)), wave];
end


function wave = loopedTone(rate, frequency, amplitude)
% About a quarter of a second of sine tone that repeats without a seam: a whole number
% of cycles in a whole number of samples, which moves the frequency by a fraction of a
% hertz. Not ramped, or every repeat would be heard.
nCycles = max(1, round(frequency * 0.25));
nSamples = round(nCycles * rate / frequency);
wave = amplitude * sin(2 * pi * nCycles * (0:nSamples - 1) / nSamples);


function wave = tail(rate, frequency, duration, amplitude)
% The end of the cue tone: it takes over from the loop mid-tone, so it is ramped off
% but not on.
wave = GenerateSineWave(rate, frequency, duration) * amplitude;
wave = reshape(wave(1, :), 1, []);
nRampSamples = round(0.005 * rate);
if nRampSamples >= 2 && nRampSamples < numel(wave)
    wave(end-nRampSamples+1:end) = wave(end-nRampSamples+1:end) .* linspace(1, 0, nRampSamples);
end


function frequencies = spreadFrequencies(range, n)
% n frequencies spread logarithmically across range.
if n == 1
    frequencies = sqrt(range(1) * range(2));
    return
end
frequencies = round(logspace(log10(range(1)), log10(range(2)), n));


function wave = applyRamp(wave, rampDuration, rate)
% Linear onset and offset ramps, to keep the waveform from clicking.
nRampSamples = round(rampDuration * rate);
if nRampSamples < 2 || nRampSamples * 2 >= numel(wave)
    return  % Too short to ramp; leave it alone rather than distorting it
end
ramp = ones(1, numel(wave));
ramp(1:nRampSamples) = linspace(0, 1, nRampSamples);
ramp(end-nRampSamples+1:end) = linspace(1, 0, nRampSamples);
wave = wave .* ramp;
