function seed = newSeed()
% lum.pattern.newSeed draws a fresh seed for the stimulus generator.
%
% Drawn from a stream seeded from the clock, not from the global rng: a test or a
% script that has called rng(1) must not make every session it sets up deliver
% trials in the same order, and drawing a seed must not disturb the global stream
% either.
%
% Returns an integer in [1, 2^31 - 1].
%
% See also: lum.pattern.generate, lum.pattern.prepareSeed

stream = RandStream('mt19937ar', 'Seed', 'shuffle');
seed = randi(stream, 2^31 - 1);
