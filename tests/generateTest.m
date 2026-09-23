function tests = generateTest
% generateTest exercises the stimulus generator: lum.pattern.generate and the families.
%
% The generator decides what light every trial of a session delivers and in what
% order, so a mistake here is a silently wrong session. Each family is checked for the
% property its design rests on (docs/stimulus_family.md): which side each group pays,
% what varies and what is held equal, and that every family's defaults compile within
% the rig's timers and the emulator's. Also the properties the protocol relies on:
% balanced groups, reproducibility from the seed, and a global random stream left
% untouched. All pure — no Bpod.
tests = functiontests(localfunctions);
end

%% Every family ---------------------------------------------------------------------

function testEveryFamilysDefaultsCompileOnTheRigAndTheEmulator(testCase)
% Choosing a family must never produce a set the machine refuses: 15 timers are left
% for light on the rig, 4 in the emulator.
for budget = [15 4]
    for family = {lum.pattern.families().Name}
        S = lum.defaultSettings;
        S.Stimulus.Generator = lum.pattern.familyDefaults(S.Stimulus.Generator, family{1}, ...
                                                          budget, S.Stimulus.Duration);
        stimulusSet = lum.pattern.stimulusSet(S, budget, 2);
        where = sprintf('%s, %d timers', family{1}, budget);
        verifyLessThanOrEqual(testCase, max(stimulusSet.nTimers), budget, where);
        verifyNumElements(testCase, stimulusSet.FamilyPLeft, stimulusSet.nGroups, where);
        verifyTrue(testCase, stimulusSet.PLeftFromFamily, where);
        verifyTrue(testCase, any(stimulusSet.GroupPLeft > 0.5) && any(stimulusSet.GroupPLeft < 0.5), ...
                   [where ': both sides are paid']);
    end
end
end

function testEveryListedFamilyGenerates(testCase)
% The windows offer exactly this list, so each entry must work with its defaults.
for family = {lum.pattern.families().Name}
    G = lum.pattern.generate(generator('Family', family{1}), 1.0, 20);
    verifyEqual(testCase, numel(G.TrialPattern), 20, family{1});
    verifyEqual(testCase, numel(G.GroupLabels), G.nGroups, family{1});
    verifyTrue(testCase, all(G.PatternGroup >= 1 & G.PatternGroup <= G.nGroups), family{1});
end
end

function testDefaultsGiveTwoBalancedPureGroups(testCase)
G = lum.pattern.generate(generator(), 2.0, 1000);
verifyEqual(testCase, G.nBins, 200);
verifyEqual(testCase, G.nGroups, 2);
verifyTrue(testCase, all(G.States(:, 1) == 1), 'Group 1 is channel A for the whole window');
verifyTrue(testCase, all(G.States(:, 2) == 2), 'Group 2 is channel B for the whole window');
verifyEqual(testCase, [sum(G.TrialPattern == 1), sum(G.TrialPattern == 2)], [500 500]);
verifyEqual(testCase, G.FamilyPLeft, [1 0]);
end

function testManyGroupsAreBalancedWithinOne(testCase)
G = lum.pattern.generate(generator('Family', 'mixture', 'MixtureRule', 'A alone'), 2.0, 1000);
counts = arrayfun(@(g) sum(G.TrialPattern == g), 1:G.nGroups);
verifyEqual(testCase, G.nGroups, 16);
verifyEqual(testCase, sum(counts), 1000);
verifyLessThanOrEqual(testCase, max(counts) - min(counts), 1);
end

function testTheSameSeedGivesTheSameSession(testCase)
a = lum.pattern.generate(generator('Seed', 42), 1.0, 300);
b = lum.pattern.generate(generator('Seed', 42), 1.0, 300);
c = lum.pattern.generate(generator('Seed', 43), 1.0, 300);
verifyEqual(testCase, a.TrialPattern, b.TrialPattern);
verifyNotEqual(testCase, a.TrialPattern, c.TrialPattern, 'Another seed must give another order');
d = lum.pattern.generate(generator('Family', 'count', 'Seed', 42), 1.0, 300);
e = lum.pattern.generate(generator('Family', 'count', 'Seed', 42), 1.0, 300);
verifyEqual(testCase, d.States, e.States, 'The flashes'' order comes from the seed too');
end

function testTheGlobalRandomStreamIsLeftAlone(testCase)
% The session's side draws and pulse widths use the global stream; building the
% stimulus set in the middle of a test or a session must not shift them.
rng(5);
expected = rand;
rng(5);
lum.pattern.generate(generator('Family', 'mixture', 'Continuous', true), 1.0, 50);
lum.pattern.generate(generator('Family', 'count'), 1.0, 50);
verifyEqual(testCase, rand, expected);
end

function testFamiliesWithoutPerTrialPatternsIgnoreIt(testCase)
for family = {'pure', 'motif', 'arbitrary'}
    G = lum.pattern.generate(generator('Family', family{1}, 'Continuous', true), 1.0, 30);
    verifyFalse(testCase, G.Continuous, family{1});
    verifyEqual(testCase, size(G.States, 2), G.nGroups, family{1});
end
end

function testABinThatDoesNotDivideTheWindowIsAdjusted(testCase)
G = lum.pattern.generate(generator('BinDuration', 0.3), 1.0, 10);
verifyEqual(testCase, G.nBins, 3);
verifyEqual(testCase, G.BinDuration, 1 / 3, 'AbsTol', 1e-12);
G = lum.pattern.generate(generator('Family', 'count'), 0.333, 10);
verifyEqual(testCase, G.nBins, 33);
verifyEqual(testCase, G.nBins * G.BinDuration, 0.333, 'AbsTol', 1e-12);
end

function testAnUnknownFamilyIsRejected(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'nonsense'), 1.0, 10), ...
            'lum:pattern:generate:badFamily');
end

%% Seeds -----------------------------------------------------------------------------

function testEverySessionDrawsANewSeedUnlessItIsKept(testCase)
% No two sessions of an animal deliver the same trials by default, even when their seeds
% are drawn within one instant (lum.pattern.newSeed keeps its clock-seeded stream).
S = lum.defaultSettings;
seeds = zeros(1, 20);
for i = 1:20
    seeds(i) = lum.pattern.prepareSeed(S).Stimulus.Generator.Seed;
end
verifyNumElements(testCase, unique(seeds), 20, 'Twenty sessions, twenty seeds');
S.Stimulus.Generator.NewSeedEachSession = false;
S.Stimulus.Generator.Seed = 12345;
verifyEqual(testCase, lum.pattern.prepareSeed(S).Stimulus.Generator.Seed, 12345, ...
            'A kept seed stays');
end

function testASeedTypedInRepeatsASession(testCase)
% The seed saved with a session gives another the same trials, what the family draws
% at random included; nothing else from the first session is needed.
S = lum.defaultSettings;
S.Stimulus.Generator = lum.pattern.familyDefaults(S.Stimulus.Generator, 'count');
S = lum.pattern.prepareSeed(S);
first = lum.pattern.stimulusSet(S, 15, 2);
S = lum.pattern.prepareSeed(S);            % The next session: a new seed
second = lum.pattern.stimulusSet(S, 15, 2);
verifyNotEqual(testCase, second.Seed, first.Seed);
verifyNotEqual(testCase, second.Segments, first.Segments, 'Another seed, other trials');
S.Stimulus.Generator.Seed = first.Seed;    % Typed from the first session's data
again = lum.pattern.stimulusSet(S, 15, 2);
verifyEqual(testCase, again.TrialPattern, first.TrialPattern);
verifyEqual(testCase, again.Segments, first.Segments);
end

%% Pure channel ---------------------------------------------------------------------

function testPureLitFractionLightsTheStartOfTheWindow(testCase)
G = lum.pattern.generate(generator('PureFractions', 0.25), 2.0, 10);
verifyEqual(testCase, find(G.States(:, 1) == 1)', 1:50);
verifyEqual(testCase, find(G.States(:, 2) == 2)', 1:50);
verifyEqual(testCase, G.Descriptors.AOn(1), 0.5, 'AbsTol', 1e-9);
verifyEqual(testCase, G.GroupLabels, {'A 25%', 'B 25%'});
end

function testEveryPureFractionIsGivenToBothChannels(testCase)
% Duration varies within each channel, so only which channel is lit tells the side.
G = lum.pattern.generate(generator('PureFractions', [0.25 0.5 1]), 1.0, 60);
verifyEqual(testCase, G.nGroups, 6);
verifyEqual(testCase, G.Descriptors.AOn + G.Descriptors.BOn, [0.25 0.25 0.5 0.5 1 1], 'AbsTol', 1e-9);
verifyEqual(testCase, G.FamilyPLeft, [1 0 1 0 1 0]);
end

function testOnePureChannelPaysEitherSide(testCase)
G = lum.pattern.generate(generator('PureChannels', 'B'), 1.0, 10);
verifyEqual(testCase, G.nGroups, 1);
verifyTrue(testCase, all(G.States == 2));
verifyEqual(testCase, G.FamilyPLeft, 0.5, 'One condition: nothing to discriminate');
end

%% Mixture -----------------------------------------------------------------------------

function testTheShareRulePaysByAsRelativeAbundance(testCase)
% Mixture ratios 2:1 and 1:2 at totals that double: every amount but the extremes pays
% left in one group and right in another, so neither amount alone tells the side.
G = lum.pattern.generate(generator('Family', 'mixture'), 1.0, 60);
a = round(G.Descriptors.AOn * 100);
b = round(G.Descriptors.BOn * 100);
verifyEqual(testCase, [a; b], [20 10 40 20 80 40; 10 20 20 40 40 80]);
verifyEqual(testCase, G.FamilyPLeft, [1 0 1 0 1 0]);
verifyEqual(testCase, G.Evidence, [2 1 2 1 2 1] / 3, 'AbsTol', 1e-12);
verifyEqual(testCase, G.EvidenceName, 'A share of the light');
verifyEqual(testCase, G.Boundary.Kind, 'diagonal');
for amount = [20 40]
    verifyEqual(testCase, sort(G.FamilyPLeft(a == amount)), [0 1], sprintf('A lit %d bins', amount));
end
verifyTrue(testCase, all(G.States(1, :) == 3), 'Both from stimulus onset');
end

function testTheShareBoundaryCanMove(testCase)
% "Is A more than 60% of the mixture?": 4:1 pays left, 3:2 either side, the rest right,
% and the boundary is the ratio line u_B = (2/3) u_A through the origin.
G = lum.pattern.generate(generator('Family', 'mixture', 'MixtureRatios', ...
                                   [4 1; 3 2; 1 1; 2 3; 1 4], 'MixtureShareBoundary', [3 2]), 1.0, 60);
verifyEqual(testCase, G.nGroups, 15);
verifyEqual(testCase, G.FamilyPLeft(1:5), [1 0.5 0 0 0]);
verifyEqual(testCase, G.Evidence(1:5), [0.8 0.6 0.5 0.4 0.2], 'AbsTol', 1e-12);
verifyEqual(testCase, G.Boundary.Kind, 'line');
verifyEqual(testCase, [G.Boundary.Slope G.Boundary.Intercept], [2/3 0], 'AbsTol', 1e-12);
end

function testTheDifferenceRulePaysByAMinusB(testCase)
% A minus B = +-0.1 at totals 0.2 apart: the amounts form one ladder, 0.1 to 0.5.
G = lum.pattern.generate(generator('Family', 'mixture', 'MixtureRule', 'difference'), 1.0, 80);
a = round(G.Descriptors.AOn * 100);
b = round(G.Descriptors.BOn * 100);
verifyEqual(testCase, a - b, repmat([10 -10], 1, 4));
verifyEqual(testCase, a + b, [30 30 50 50 70 70 90 90]);
verifyEqual(testCase, G.FamilyPLeft, repmat([1 0], 1, 4));
verifyEqual(testCase, G.Evidence, repmat([0.1 -0.1], 1, 4), 'AbsTol', 1e-12);
verifyEqual(testCase, G.EvidenceName, 'A minus B, fraction of the window');
H = lum.pattern.generate(generator('Family', 'mixture', 'MixtureRule', 'difference', ...
                                   'MixtureDifferences', [0.2 0.1 0 -0.1], ...
                                   'MixtureDifferenceBoundary', 0.1), 1.0, 80);
verifyEqual(testCase, H.FamilyPLeft(1:4), [1 0.5 0 0], 'Above 0.1 left, at it either side');
verifyEqual(testCase, [H.Boundary.Slope H.Boundary.Intercept], [1 -0.1], 'AbsTol', 1e-12, ...
            'Parallel to the diagonal');
end

function testPerTrialRelativeAmountsFallOnTheirSide(testCase)
G = lum.pattern.generate(generator('Family', 'mixture', 'Continuous', true, ...
                                   'MixtureShareBoundary', [3 2], 'MixtureRatios', [4 1; 1 4]), ...
                         1.0, 400);
verifyEqual(testCase, [sum(G.PatternGroup == 1), sum(G.PatternGroup == 2)], [200 200]);
share = G.Descriptors.AOn ./ (G.Descriptors.AOn + G.Descriptors.BOn);
verifyTrue(testCase, all(share(G.PatternGroup == 1) > 0.6) && all(share(G.PatternGroup == 2) < 0.6));
verifyEqual(testCase, G.Evidence, share, 'AbsTol', 1e-12);
verifyEqual(testCase, G.GroupLabels, {'A share above 60%', 'A share below 60%'});
H = lum.pattern.generate(generator('Family', 'mixture', 'MixtureRule', 'difference', ...
                                   'Continuous', true), 1.0, 400);
delta = H.Descriptors.AOn - H.Descriptors.BOn;
verifyTrue(testCase, all(delta(H.PatternGroup == 1) > 0) && all(delta(H.PatternGroup == 2) < 0));
end

function testMixtureAmountsBeyondTheWindowAreRefused(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'mixture', ...
            'MixtureShareTotals', [0.3 1.8]), 1.0, 10), 'lum:pattern:generate:badMixtureAmounts');
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'mixture', 'MixtureRule', ...
            'difference', 'MixtureDifferenceTotals', 0.05), 1.0, 10), ...
            'lum:pattern:generate:badMixtureAmounts');
end

function testAnAloneRuleCrossesEveryLevelWithEveryLevel(testCase)
% A decides: its lower levels pay right, its upper levels left, and B tells nothing.
G = lum.pattern.generate(generator('Family', 'mixture', 'MixtureRule', 'A alone'), 1.0, 160);
a = round(G.Descriptors.AOn * 100);
b = round(G.Descriptors.BOn * 100);
verifyEqual(testCase, G.FamilyPLeft(a >= 40), ones(1, 8));
verifyEqual(testCase, G.FamilyPLeft(a <= 20), zeros(1, 8));
for level = [10 20 40 80]
    verifyEqual(testCase, mean(G.FamilyPLeft(b == level)), 0.5, sprintf('B at %d bins', level));
end
verifyEqual(testCase, G.Boundary.Kind, 'vertical');
verifyEqual(testCase, G.Boundary.Value, 0.3, 'AbsTol', 1e-12);
H = lum.pattern.generate(generator('Family', 'mixture', 'MixtureRule', 'B alone'), 1.0, 160);
verifyEqual(testCase, H.FamilyPLeft(round(H.Descriptors.BOn * 100) >= 40), zeros(1, 8), ...
            'More B pays right');
verifyEqual(testCase, H.Boundary.Kind, 'horizontal');
end

function testPerTrialAmountsFallOnTheSideTheirGroupPays(testCase)
G = lum.pattern.generate(generator('Family', 'mixture', 'Continuous', true), 1.0, 1000);
verifyTrue(testCase, G.Continuous);
verifyEqual(testCase, size(G.States, 2), 1000);
verifyEqual(testCase, [sum(G.PatternGroup == 1), sum(G.PatternGroup == 2)], [500 500]);
moreA = G.Descriptors.AOn > G.Descriptors.BOn;
verifyEqual(testCase, moreA, G.PatternGroup == 1);
verifyTrue(testCase, all(G.Descriptors.AOn >= 0.1 - 1e-9 & G.Descriptors.AOn <= 0.8 + 1e-9));
verifyEqual(testCase, G.GroupLabels, {'More A', 'More B'});
end

function testLevelsThatRoundToOneAmountAreRefused(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'mixture', 'MixtureRule', ...
            'A alone', 'MixtureLevels', [0.001 0.002 0.5]), 1.0, 10), ...
            'lum:pattern:generate:levelsTooClose');
end

function testCentredAmountsShareTheirMiddle(testCase)
G = lum.pattern.generate(generator('Family', 'mixture', 'MixtureLayout', 'centred'), 1.0, 10);
lightA = find(bitand(G.States(:, 1), 1))';   % 20 bins
lightB = find(bitand(G.States(:, 1), 2))';   % 10 bins
verifyEqual(testCase, lightA, 41:60);
verifyEqual(testCase, lightB, 46:55);
end

%% Sequence (count) ---------------------------------------------------------------

function testEachTrialHasItsGroupsCountsInANewOrder(testCase)
G = lum.pattern.generate(generator('Family', 'count', 'Continuous', true), 1.0, 600);
pairs = [5 0; 4 1; 3 2; 2 3; 1 4; 0 5];
verifyTrue(testCase, G.Continuous);
verifyEqual(testCase, G.nGroups, 6);
verifyEqual(testCase, G.Descriptors.ASegments, pairs(G.PatternGroup, 1)');
verifyEqual(testCase, G.Descriptors.BSegments, pairs(G.PatternGroup, 2)');
verifyEqual(testCase, G.Evidence, (pairs(G.PatternGroup, 1) - pairs(G.PatternGroup, 2))');
verifyEqual(testCase, G.FamilyPLeft, [1 1 1 0 0 0]);
threeTwo = G.States(:, G.PatternGroup == 3);
verifyGreaterThan(testCase, size(unique(threeTwo', 'rows'), 1), 5, ...
                  'The 3:2 trials come in several orders');
verifyEqual(testCase, round(G.Descriptors.AOn(G.PatternGroup == 1) * 100), 50 * ones(1, 100), ...
            'Five flashes of 10 bins each');
end

function testFixedOrderGivesOnePatternPerGroup(testCase)
G = lum.pattern.generate(generator('Family', 'count', 'Continuous', false), 1.0, 60);
verifyFalse(testCase, G.Continuous);
verifyEqual(testCase, size(G.States, 2), 6);
end

function testSlotsTooShortForAFlashAndAGapAreRefused(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'count', 'CountSlots', 60, ...
            'CountPairs', [1 0; 0 1]), 1.0, 10), 'lum:pattern:generate:slotsTooShort');
G = lum.pattern.generate(generator('Family', 'count', 'CountSlots', 60, 'CountFill', 1, ...
                                   'CountPairs', [1 0; 0 1]), 1.0, 10);
verifyEqual(testCase, G.nGroups, 2, 'A fill of 1 needs no gap');
end

function testACountNeedingMoreSlotsThanThereAreIsRefused(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'count', ...
            'CountPairs', [4 3; 3 4]), 1.0, 10), 'lum:pattern:generate:badCountPairs');
end

function testTheEmulatorsCountDefaultsFitItsTimers(testCase)
g = lum.pattern.familyDefaults(generator(), 'count', 4);
verifyEqual(testCase, g.CountSlots, 3);
verifyEqual(testCase, g.CountPairs, [3 0; 2 1; 1 2; 0 3]);
verifyEqual(testCase, lum.pattern.familyDefaults(generator(), 'count', 15).CountSlots, 5);
end

%% Order -------------------------------------------------------------------------------

function testSimpleOrderIsTheMirrorOfItself(testCase)
G = lum.pattern.generate(generator('Family', 'order'), 1.0, 10);
verifyEqual(testCase, G.GroupLabels, {'A first', 'B first'});
verifyEqual(testCase, G.States(:, 2), swapped(G.States(:, 1)));
verifyEqual(testCase, [G.States(1, 1), G.States(50, 1), G.States(end, 1)], uint8([1 3 2]));
verifyEqual(testCase, G.Descriptors.AOn, G.Descriptors.BOn, 'AbsTol', 1e-9);
verifyEqual(testCase, G.Boundary.Kind, 'none');
end

function testTheGuardedCycleIsNeverDarkAndBalancesTheChannels(testCase)
G = lum.pattern.generate(generator('Family', 'order', 'OrderDesign', 'guarded', ...
                                   'OrderCycles', 2), 2.0, 20);
verifyEqual(testCase, G.Descriptors.Dark, [0 0]);
verifyEqual(testCase, G.Descriptors.AOn, G.Descriptors.BOn, 'AbsTol', 1e-9);
verifyNotEqual(testCase, G.States(:, 1), G.States(:, 2), 'The categories must differ');
verifyEqual(testCase, G.GroupLabels, {'A leads', 'B leads'});
end

function testARandomPhaseHidesTheOrderFromEachChannelAlone(testCase)
% Each channel on its own is one stretch of light of fixed length at a random place,
% whichever leads: only the two together tell the side.
S = lum.defaultSettings;
S.Stimulus.Generator = generator('Family', 'order', 'OrderDesign', 'guarded', 'Continuous', true);
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
verifyTrue(testCase, stimulusSet.Continuous);
verifyEqual(testCase, numel(unique(round(stimulusSet.Descriptors.AOn * 1e4))), 1);
verifyEqual(testCase, stimulusSet.Shortcuts.AAmount, 0.5, 'AbsTol', 1e-12);
verifyEqual(testCase, stimulusSet.Shortcuts.TotalLight, 0.5, 'AbsTol', 1e-12);
end

function testTooManyTurnsForTheWindowAreRefused(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'order', 'OrderCycles', 60), ...
            1.0, 10), 'lum:pattern:generate:orderTooShort');
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'order', 'OrderDesign', ...
            'guarded', 'OrderShortOverlap', 0.3, 'OrderLongOverlap', 0.2), 1.0, 10), ...
            'lum:pattern:generate:badOrderGuards');
end

%% Motifs ------------------------------------------------------------------------------

function testEachLetterIsAFlash(testCase)
G = lum.pattern.generate(generator('Family', 'motif'), 1.0, 80);
verifyEqual(testCase, G.GroupLabels, {'AAA', 'AAB', 'ABB', 'BAB', 'ABA', 'BAA', 'BBA', 'BBB'});
verifyEqual(testCase, G.FamilyPLeft, [1 1 1 1 0 0 0 0]);
verifyEqual(testCase, G.Descriptors.ASegments, [3 2 1 1 2 2 1 0]);
verifyEqual(testCase, G.Descriptors.BSegments, [0 1 2 2 1 1 2 3]);
end

function testXLightsBothAndADashIsDark(testCase)
G = lum.pattern.generate(generator('Family', 'motif', 'MotifLeftWords', 'X-A', ...
                                   'MotifRightWords', 'b.x', 'MotifFill', 1), 0.3, 10);
verifyEqual(testCase, G.GroupLabels, {'X-A', 'B-X'});
verifyEqual(testCase, G.States(:, 1)', uint8([3 3 3 3 3 3 3 3 3 3, zeros(1, 10), ones(1, 10)]));
end

function testWordsMustShareOneLengthAndAlphabet(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'motif', 'MotifLeftWords', ...
            'AB', 'MotifRightWords', 'ABA'), 1.0, 10), 'lum:pattern:generate:badWords');
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'motif', 'MotifLeftWords', ...
            'AQB'), 1.0, 10), 'lum:pattern:generate:badWords');
end

%% Hand-drawn pulses and offsets --------------------------------------------------------

function testArbitraryPulsesAreRasterised(testCase)
g = generator('Family', 'arbitrary', 'nGroups', 1, 'Pulses', [1 1 0.2 0.8; 1 2 0.5 1.0]);
G = lum.pattern.generate(g, 2.0, 10);
lightA = find(bitand(G.States(:, 1), 1))';
lightB = find(bitand(G.States(:, 1), 2))';
verifyEqual(testCase, lightA, 21:80);
verifyEqual(testCase, lightB, 51:100);
end

function testAPulseOutsideTheWindowIsRejected(testCase)
g = generator('Family', 'arbitrary', 'nGroups', 1, 'Pulses', [1 1 0.5 3]);
verifyError(testCase, @() lum.pattern.generate(g, 2.0, 10), 'lum:pattern:generate:badPulses');
end

function testCircularOffsetKeepsTheLightAndLinearDropsIt(testCase)
g = generator('PureChannels', 'A', 'PureFractions', 0.5, 'AOffset', 1.5);
circular = lum.pattern.generate(g, 2.0, 10);
g.OffsetMode = 'linear';
linear = lum.pattern.generate(g, 2.0, 10);
verifyEqual(testCase, circular.Descriptors.AOn, 1.0, 'AbsTol', 1e-9);
verifyEqual(testCase, linear.Descriptors.AOn, 0.5, 'AbsTol', 1e-9);
end

function testPerGroupOffsetsApplyToTheirOwnGroup(testCase)
G = lum.pattern.generate(generator('PureFractions', 0.5, 'BOffset', [0 0.1]), 1.0, 10);
verifyEqual(testCase, find(G.States(:, 2) == 2, 1), 11, 'Group 2 starts 10 bins late');
verifyEqual(testCase, find(G.States(:, 1) == 1, 1), 1, 'Group 1 is not shifted');
% Per-trial patterns take their group's offset.
G = lum.pattern.generate(generator('Family', 'count', 'CountPairs', [2 0; 0 2], ...
                                   'Continuous', true, 'AOffset', [0.1 0]), 1.0, 20);
firstA = arrayfun(@(k) find(bitand(G.States(:, k), 1), 1), find(G.PatternGroup == 1));
verifyTrue(testCase, all(firstA > 10), 'Group 1''s flashes all start at least 10 bins late');
end


function g = generator(varargin)
% Generator defaults with a fixed seed, overridden by name/value pairs.
g = lum.pattern.withGeneratorDefaults(struct('Seed', 7));
for i = 1:2:numel(varargin)
    g.(varargin{i}) = varargin{i + 1};
end
end


function states = swapped(states)
% A and B exchanged.
out = states;
out(states == 1) = 2;
out(states == 2) = 1;
states = out;
end
