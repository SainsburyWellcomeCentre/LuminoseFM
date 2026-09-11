function S = prepareSeed(S)
% lum.pattern.prepareSeed gives the session a new stimulus seed, unless it is fixed.
%
% A seed fixes both the patterns (where a family is random) and the order the
% trials come in. Reusing one seed session after session would give every session
% the same sequence, which an animal can learn, so by default each session draws a
% new one. Setting S.Stimulus.Generator.NewSeedEachSession to false keeps the seed
% in the settings file, for a session that has to be repeated exactly.
%
% Called once as a session is set up, before the setup dialog opens, so that the
% preview the operator scrolls through is the order the session will run.
%
% See also: lum.pattern.newSeed, lum.pattern.generate

generator = lum.pattern.withGeneratorDefaults(S.Stimulus.Generator);
if generator.NewSeedEachSession
    generator.Seed = lum.pattern.newSeed();
end
S.Stimulus.Generator = generator;
