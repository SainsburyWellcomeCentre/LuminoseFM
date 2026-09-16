function plays = testSounds(S, which, nGroups)
% lum.testSounds says how to play one of the session's sounds as a test, from the setup dialog.
%
% The sound settings are easiest to set by ear. Each "Play" button in the setup dialog
% asks for one of the session's sounds, built from the settings as they stand in the
% dialog — sampling rate, amplitude, attenuation, and the sound's own frequency and
% duration — and plays it through TestHiFiSound: on the HiFi module when Bpod has one,
% on the PC's speakers otherwise (the emulator).
%
% Arguments:
%   S        Settings struct, as the dialog has it
%   which    'Cue', 'Noise', 'Stimulus', 'Left' or 'Right'
%   nGroups  Number of stimulus groups, for 'Stimulus' (one tone per group)
%
% Returns a cell array with one element per sound to play, in order; each is the
% name/value argument list for TestHiFiSound. The cue tone, which loops until the poke
% in a session, plays for 0.5 s.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: TestHiFiSound, lum.loadSounds, lum.gui.SetupDialog

if nargin < 3 || isempty(nGroups)
    nGroups = 2;
end
common = {'Amplitude', S.Sound.Amplitude, 'Attenuation', S.Sound.Attenuation_dB, ...
          'SamplingRate', S.Sound.SamplingRate, 'Force', true};
switch which
    case 'Cue'
        plays = {[{'Waveform', 'tone', 'Frequency', S.Cue.ToneFrequency, 'Duration', 0.5}, common]};
    case 'Noise'
        plays = {[{'Waveform', 'noise', 'Duration', S.Sound.NoiseDuration}, common]};
    case 'Stimulus'
        tone = S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, 'Tone'));
        frequencies = lum.toneFrequencies(S.Stimulus.ToneFrequencyRange, max(1, nGroups));
        plays = arrayfun(@(f) [{'Waveform', 'tone', 'Frequency', f, 'Duration', ...
                                max(tone(1).Duration, 0.01)}, common], frequencies, ...
                         'UniformOutput', false);
    case {'Left', 'Right'}
        side = S.(which).Tone;
        plays = {[{'Waveform', 'tone', 'Frequency', side.Frequency, 'Duration', ...
                   max(side.Duration, 0.01)}, common]};
    otherwise
        error('lum:testSounds:unknownSound', ...
              'Unknown sound ''%s''; use Cue, Noise, Stimulus, Left or Right.', which);
end
