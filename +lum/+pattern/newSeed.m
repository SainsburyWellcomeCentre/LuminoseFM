function seed = newSeed()
% lum.pattern.newSeed draws a fresh seed for the stimulus generator.
%
% Every session draws one by default (lum.pattern.prepareSeed), and the Randomise
% buttons draw one on demand, so that no two sessions of an animal deliver the same
% trials unless the operator types an earlier session's seed to repeat it. Seeds come
% from 2^31 - 1 values, so two sessions meeting on one by chance is about one in a
% billion.
%
% Drawn from a stream of this function's own, seeded from the clock once per MATLAB
% process, not from the global rng: a test or a script that has called rng(1) must not
% make every session it sets up deliver trials in the same order, and drawing a seed
% must not disturb the global stream either. Keeping the stream, rather than seeding
% one from the clock at every call, means two draws in quick succession (a double click)
% still differ.
%
% Returns an integer in [1, 2^31 - 1].
%
% See also: lum.pattern.generate, lum.pattern.prepareSeed

persistent stream
if isempty(stream)
    stream = RandStream('mt19937ar', 'Seed', 'shuffle');
end
seed = randi(stream, 2^31 - 1);
