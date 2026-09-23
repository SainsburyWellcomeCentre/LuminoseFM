function generator = withGeneratorDefaults(generator)
% lum.pattern.withGeneratorDefaults fills in any generator field that is missing.
%
% The generator struct has fields for every family, most of which any one family
% ignores, so that switching family and back keeps what was set. Settings files
% written before a field existed, and the short structs tests and scripts write by
% hand, would otherwise fail on the first field they lack. Present fields always win,
% including empty ones where empty is meaningful. docs/stimulus_family.md explains
% what each family does with its fields.
%
% Shared by every family:
%   Family              'pure'  Which family (lum.pattern.families)
%   Continuous          false   A new pattern for every trial, where the family offers
%                               it (lum.pattern.families, PerTrial)
%   BinDuration         0.01    Seconds per bin; adjusted to divide the window exactly
%   Seed                1       Stream seed; the session draws a fresh one unless
%   NewSeedEachSession  true    ... this is false
%   AOffset, BOffset    0       Latency of each channel (s), one or one per group
%   OffsetMode          'circular' 'circular' wraps round the window, 'linear' drops
%
% Pure channel ('pure'):
%   PureChannels        'A and B'  'A and B', or 'A' or 'B' alone (one group per fraction)
%   PureFractions       1       Lit fractions of the window, from onset; one group per
%                               fraction and channel
%
% Mixture ('mixture'):
%   MixtureRule         'share' 'share' (A's share of the light against a boundary),
%                               'difference' (A minus B against a boundary), or the
%                               controls 'A alone' and 'B alone'
%   MixtureRatios       [2 1; 1 2]  share: mixture ratios, rows of [A B] parts
%   MixtureShareBoundary [1 1]  share: the ratio A:B where the sides change
%   MixtureShareTotals  [0.3 0.6 1.2]  share: total light (A plus B, fractions of the
%                               window) each ratio is given at
%   MixtureDifferences  [0.1 -0.1]  difference: A minus B, fractions of the window
%   MixtureDifferenceBoundary 0 difference: the A minus B where the sides change
%   MixtureDifferenceTotals [0.3 0.5 0.7 0.9]  difference: total light each is given at
%   MixtureLevels       [0.1 0.2 0.4 0.8]  alone rules: amounts a channel can be lit for,
%                               as fractions of the window
%   MixtureLayout       'spread' 'spread' (each amount shared over MixtureCycles cycles,
%                               both channels starting every cycle, so the mixture is
%                               present throughout the window), 'onset' (both lit in one
%                               stretch from stimulus onset) or 'centred'
%   MixtureCycles       5       spread: cycles in the window; each costs a global timer
%                               per channel
%
% Sequence ('count'):
%   CountSlots          5       Slots in the window, one flash (or nothing) each
%   CountPairs          [5 0; 4 1; ... 0 5]  One row per group: [A flashes, B flashes]
%   CountFill           0.5     Fraction of each slot its flash lasts
%
% Order ('order'):
%   OrderDesign         'simple'  'simple' or 'guarded'
%   OrderCycles         1       Turns in the window
%   OrderOverlap        0.2     simple: fraction of a turn both channels are on
%   OrderShortOverlap   0.1     guarded: the overlap as the first channel hands over
%   OrderLongOverlap    0.3     guarded: the overlap at the end of the turn
%
% Motifs ('motif'):
%   MotifLeftWords      'AAA AAB ABB BAB'  Words that pay left (letters A, B, X, -)
%   MotifRightWords     'ABA BAA BBA BBB'  Words that pay right
%   MotifFill           0.5     Fraction of each letter's slot its flash lasts
%
% Hand-drawn pulses ('arbitrary'):
%   nGroups             2       Groups the table describes
%   Pulses              [1 1 0 0.5; 2 2 0 0.5]  Rows of [group channel start end] (s)
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.pattern.familyDefaults, lum.pattern.generate, lum.defaultSettings

defaults = struct('Family', 'pure', 'Continuous', false, 'BinDuration', 0.01, ...
                  'Seed', 1, 'NewSeedEachSession', true, ...
                  'AOffset', 0, 'BOffset', 0, 'OffsetMode', 'circular');
for family = {lum.pattern.families().Name}
    defaults = lum.pattern.familyDefaults(defaults, family{1});
end
% familyDefaults leaves the family it was last given chosen, and its Continuous.
defaults.Family = 'pure';
defaults.Continuous = false;

if ~isstruct(generator) || ~isscalar(generator)
    generator = struct();
end
names = fieldnames(defaults);
for i = 1:numel(names)
    if ~isfield(generator, names{i})
        generator.(names{i}) = defaults.(names{i});
    end
end
