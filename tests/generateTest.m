function tests = generateTest
% generateTest exercises the stimulus generator: lum.pattern.generate.
%
% The generator decides what light every trial of a session delivers and in what
% order, so a mistake here is a silently wrong session. These are the checks the
% generatePattern library's own suite made, for the families the protocol uses, plus
% the properties the protocol relies on: balanced groups, reproducibility from the
% seed, and a global random stream left untouched. All pure — no Bpod.
tests = functiontests(localfunctions);
end

function testDefaultsGiveTwoBalancedPureGroups(testCase)
G = lum.pattern.generate(generator(), 2.0, 1000);
verifyEqual(testCase, G.nBins, 200);
verifyEqual(testCase, G.nGroups, 2);
verifyTrue(testCase, all(G.States(:, 1) == 1), 'Group 1 is channel A for the whole window');
verifyTrue(testCase, all(G.States(:, 2) == 2), 'Group 2 is channel B for the whole window');
verifyEqual(testCase, [sum(G.TrialPattern == 1), sum(G.TrialPattern == 2)], [500 500]);
end

function testSevenGroupsAreBalancedWithinOne(testCase)
G = lum.pattern.generate(generator('Family', 'sequence', 'nGroups', 7), 2.0, 1000);
counts = arrayfun(@(g) sum(G.TrialPattern == g), 1:7);
verifyEqual(testCase, sum(counts), 1000);
verifyLessThanOrEqual(testCase, max(counts) - min(counts), 1);
verifyEqual(testCase, numel(G.SweepValues), 7);
verifyNotEmpty(testCase, G.SweepName);
end

function testTheSameSeedGivesTheSameSession(testCase)
a = lum.pattern.generate(generator('Seed', 42), 1.0, 300);
b = lum.pattern.generate(generator('Seed', 42), 1.0, 300);
c = lum.pattern.generate(generator('Seed', 43), 1.0, 300);
verifyEqual(testCase, a.TrialPattern, b.TrialPattern);
verifyNotEqual(testCase, a.TrialPattern, c.TrialPattern, 'Another seed must give another order');
end

function testTheGlobalRandomStreamIsLeftAlone(testCase)
% The session's side draws and pulse widths use the global stream; building the
% stimulus set in the middle of a test or a session must not shift them.
rng(5);
expected = rand;
rng(5);
lum.pattern.generate(generator('Family', 'occupancy', 'Continuous', true, ...
                               'Layout', 'shuffle'), 1.0, 50);
verifyEqual(testCase, rand, expected);
end

function testPureLitFractionLightsTheStartOfTheWindow(testCase)
G = lum.pattern.generate(generator('OnFraction', 0.25), 2.0, 10);
verifyEqual(testCase, find(G.States(:, 1) == 1)', 1:50);
verifyEqual(testCase, G.Descriptors.AOn(1), 0.5, 'AbsTol', 1e-9);
end

function testMoreThanTwoPureGroupsSweepTheLitFraction(testCase)
G = lum.pattern.generate(generator('nGroups', 4, 'OnFraction', [0.25 0.5 0.75 1]), 1.0, 40);
verifyEqual(testCase, G.SweepValues, [0.25 0.5 0.75 1]);
verifyEqual(testCase, G.Descriptors.AOn + G.Descriptors.BOn, [0.25 0.5 0.75 1], 'AbsTol', 1e-9);
end

function testSequenceMirrorSwapsTheChannels(testCase)
G = lum.pattern.generate(generator('Family', 'sequence', 'Motif', [1 2], 'NumCycles', 2), 1.0, 10);
swapped = G.States(:, 1);
swapped(G.States(:, 1) == 1) = 2;
swapped(G.States(:, 1) == 2) = 1;
verifyEqual(testCase, G.States(:, 2), swapped);
verifyEqual(testCase, G.Descriptors.AOn(1), 0.5, 'AbsTol', 1e-9);
end

function testSequenceDutyCycleShortensEachSlot(testCase)
% One cycle of two 50-bin slots, so half a slot is a whole number of bins.
G = lum.pattern.generate(generator('Family', 'sequence', 'Motif', [1 2], 'NumCycles', 1, ...
                                   'DutyCycle', [0.5 1], 'nGroups', 1), 1.0, 10);
verifyEqual(testCase, G.Descriptors.AOn(1), 0.25, 'AbsTol', 1e-9);
verifyEqual(testCase, G.Descriptors.BOn(1), 0.5, 'AbsTol', 1e-9);
end

function testSequenceCyclesMustDivideTheBins(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'sequence', ...
            'NumCycles', 3), 1.0, 10), 'lum:pattern:generate:badCycleCount');
end

function testOccupancyFractionsAreRealised(testCase)
G = lum.pattern.generate(generator('Family', 'occupancy', 'nGroups', 1, 'AOnFraction', 0.4, ...
                                   'BOnFraction', 0.45, 'Overlap', 0.15), 2.0, 10);
d = G.Descriptors;
verifyEqual(testCase, [d.AOn d.BOn d.Overlap d.Dark], [0.8 0.9 0.3 0.6], 'AbsTol', 1e-9);
end

function testOccupancyBetaSweepsTheBShare(testCase)
G = lum.pattern.generate(generator('Family', 'occupancy', 'nGroups', 5), 2.0, 50);
verifyEqual(testCase, G.SweepValues, linspace(0.1, 0.9, 5), 'AbsTol', 1e-12);
verifyTrue(testCase, all(diff(G.Descriptors.BShare) > 0), 'B share must rise with beta');
end

function testAnImpossibleOverlapIsRejected(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'occupancy', ...
            'nGroups', 1, 'Overlap', 0.6), 1.0, 10), 'lum:pattern:generate:badOccupancy');
end

function testOverlapOrderIsNeverDarkAndBalancesTheChannels(testCase)
G = lum.pattern.generate(generator('Family', 'overlap_order'), 2.0, 20);
verifyEqual(testCase, G.Descriptors.Dark, [0 0]);
verifyEqual(testCase, G.Descriptors.AOn, G.Descriptors.BOn, 'AbsTol', 1e-9);
verifyNotEqual(testCase, G.States(:, 1), G.States(:, 2), 'The categories must differ');
end

function testContinuousOverlapOrderGivesBalancedCategories(testCase)
G = lum.pattern.generate(generator('Family', 'overlap_order', 'Continuous', true), 2.0, 1000);
verifyEqual(testCase, size(G.States, 2), 1000);
verifyEqual(testCase, G.TrialPattern, 1:1000);
verifyEqual(testCase, [sum(G.PatternGroup == 1), sum(G.PatternGroup == 2)], [500 500]);
verifyEqual(testCase, G.GroupLabels, {'A-led', 'B-led'});
end

function testTiledOrderIsTheComplement(testCase)
G = lum.pattern.generate(generator('Family', 'tiled_order', 'BinDuration', 0.1), 1.0, 10);
lightA = bitand(G.States, 1) ~= 0;
lightB = bitand(G.States, 2) ~= 0;
verifyEqual(testCase, lightA, ~lightB);
end

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
g = generator('nGroups', 1, 'OnFraction', 0.5, 'AOffset', 1.5);
circular = lum.pattern.generate(g, 2.0, 10);
g.OffsetMode = 'linear';
linear = lum.pattern.generate(g, 2.0, 10);
verifyEqual(testCase, circular.Descriptors.AOn, 1.0, 'AbsTol', 1e-9);
verifyEqual(testCase, linear.Descriptors.AOn, 0.5, 'AbsTol', 1e-9);
end

function testPerGroupOffsetsApplyToTheirOwnGroup(testCase)
G = lum.pattern.generate(generator('OnFraction', 0.5, 'BOffset', [0 0.1]), 1.0, 10);
verifyEqual(testCase, find(G.States(:, 2) == 2, 1), 11, 'Group 2 starts 10 bins late');
verifyEqual(testCase, find(G.States(:, 1) == 1, 1), 1, 'Group 1 is not shifted');
end

function testABinThatDoesNotDivideTheWindowIsRejected(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('BinDuration', 0.3), 1.0, 10), ...
            'lum:pattern:generate:binMismatch');
end

function testAnUnknownFamilyIsRejected(testCase)
verifyError(testCase, @() lum.pattern.generate(generator('Family', 'nonsense'), 1.0, 10), ...
            'lum:pattern:generate:badFamily');
end

function testEveryListedFamilyGenerates(testCase)
% The designer offers exactly this list, so each entry must work with the defaults.
families = lum.pattern.families();
for family = {families.Name}
    G = lum.pattern.generate(generator('Family', family{1}), 1.0, 20);
    verifyEqual(testCase, numel(G.TrialPattern), 20, family{1});
end
end


function g = generator(varargin)
% Generator defaults with a fixed seed, overridden by name/value pairs.
g = lum.pattern.withGeneratorDefaults(struct('Seed', 7));
for i = 1:2:numel(varargin)
    g.(varargin{i}) = varargin{i + 1};
end
if strcmp(g.Family, 'arbitrary') && isempty(g.Pulses)
    g.Pulses = [1 1 0 0.5; 2 2 0 0.5];
end
end
