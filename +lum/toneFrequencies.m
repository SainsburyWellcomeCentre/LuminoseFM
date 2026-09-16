function frequencies = toneFrequencies(range, n)
% lum.toneFrequencies spreads n stimulus tone frequencies across a range, in Hz.
%
% Logarithmically, so neighbouring tones are about equally discriminable rather than
% equally spaced in Hz. One tone sits at the geometric middle of the range. Shared by
% lum.loadSounds, which loads the session's group tones, and lum.testSounds, which plays
% them from the setup dialog, so what the operator hears is what the animal will.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.loadSounds, lum.testSounds

if n == 1
    frequencies = sqrt(range(1) * range(2));
    return
end
frequencies = round(logspace(log10(range(1)), log10(range(2)), n));
