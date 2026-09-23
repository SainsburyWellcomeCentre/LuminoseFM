function tests = stimulusSetTest
% stimulusSetTest exercises the session's stimulus set: lum.pattern.stimulusSet, the
% contingency (lum.pattern.applyContingency, lum.pattern.typedPLeft) and the single-cue
% ceilings (lum.pattern.shortcuts).
%
% The set is what the trial records index into, what the data file stores once, and
% the place where a session that cannot be run — or cannot mean anything — is
% refused. All pure; no Bpod.
tests = functiontests(localfunctions);
end

function testPatternsArePackedAndRecoverable(testCase)
S = settingsWith();
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
verifyEqual(testCase, stimulusSet.nPatterns, 2);
verifyEqual(testCase, stimulusSet.SegmentStart, [1 2 3]);
first = lum.pattern.patternAt(stimulusSet, 1);
second = lum.pattern.patternAt(stimulusSet, 2);
verifyEqual(testCase, first.Segments, [1 0 1], 'AbsTol', 1e-9);
verifyEqual(testCase, second.Segments, [2 0 1], 'AbsTol', 1e-9);
verifyEqual(testCase, first.Name, 'A only');
verifyEqual(testCase, [first.PLeft second.PLeft], [1 0]);
end

function testEveryPackedPatternMatchesItsStates(testCase)
S = settingsWith('Family', 'order', 'OrderDesign', 'guarded', 'OrderCycles', 3, 'Continuous', true);
S.Session.MaxTrials = 100;
stimulusSet = lum.pattern.stimulusSet(S, 64, 2);
verifyEqual(testCase, stimulusSet.nPatterns, 100);
for k = [1 37 100]
    expected = lum.pattern.fromStates(stimulusSet.States(:, k), stimulusSet.BinDuration);
    verifyEqual(testCase, lum.pattern.patternAt(stimulusSet, k).Segments, expected);
    verifyEqual(testCase, stimulusSet.nTimers(k), size(expected, 1));
end
end

function testSegmentsNeverEndPastTheWindow(testCase)
% With the bin adjusted to the window (0.333 s in 10 ms bins), every edge is rounded to
% the state machine's cycle on its own, so no segment runs past the window.
S = settingsWith('Family', 'mixture', 'MixtureLayout', 'centred');
S.Stimulus.Duration = 0.333;
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
ends = stimulusSet.Segments(:, 3) + stimulusSet.Segments(:, 4);
verifyLessThanOrEqual(testCase, max(ends), 0.333 + 1e-12);
end

function testTheTimerBudgetIsEnforcedPerPattern(testCase)
S = settingsWith('Family', 'count', 'CountSlots', 20, 'CountPairs', [20 0; 0 20]);
verifyError(testCase, @() lum.pattern.stimulusSet(S, 16, 2), ...
            'lum:pattern:stimulusSet:timerBudget');
S.Session.UseOpto = false;   % No light, no timers spent on it
verifyEqual(testCase, lum.pattern.stimulusSet(S, 16, 2).nGroups, 2);
end

function testTheTimerErrorNamesTheGroup(testCase)
S = settingsWith('Family', 'count', 'CountSlots', 20, 'CountPairs', [20 0; 0 20]);
try
    lum.pattern.stimulusSet(S, 5, 2);
    verifyFail(testCase, 'A 20-flash pattern must not fit 5 timers');
catch rejection
    verifySubstring(testCase, rejection.message, 'Group 1 (20 A : 0 B)');
end
end

%% Contingency ------------------------------------------------------------------------

function testAnEmptyPLeftIsTheFamilys(testCase)
S = settingsWith('Family', 'mixture');
verifyEmpty(testCase, S.Task.GroupPLeft, 'The default settings leave it to the family');
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
verifyTrue(testCase, stimulusSet.PLeftFromFamily);
verifyEqual(testCase, stimulusSet.BasePLeft, stimulusSet.FamilyPLeft);
verifyEqual(testCase, stimulusSet.GroupPLeft, [1 0 1 0 1 0]);
end

function testTypedPLeftIsUsedAndRecorded(testCase)
S = settingsWith();
S.Task.GroupPLeft = [0.8 0.3];
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
verifyFalse(testCase, stimulusSet.PLeftFromFamily);
verifyEqual(testCase, stimulusSet.GroupPLeft, [0.8 0.3]);
verifyEqual(testCase, stimulusSet.FamilyPLeft, [1 0], 'The family''s is kept beside it');
end

function testTheContingencyMustMatchTheGroups(testCase)
S = settingsWith();
S.Task.GroupPLeft = [1 0 0.5];
verifyError(testCase, @() lum.pattern.stimulusSet(S, 16, 2), ...
            'lum:pattern:stimulusSet:contingencyMismatch');
end

function testTypedPLeftIsKeptOnlyForTheGroupsItWasTypedFor(testCase)
labels = {'A only', 'B only'};
[pLeft, typedFor] = lum.pattern.typedPLeft([0.9 0.1], {}, labels);
verifyEqual(testCase, pLeft, [0.9 0.1], 'Groups unknown, one value per group: kept');
verifyEqual(testCase, typedFor, labels);
[pLeft, typedFor] = lum.pattern.typedPLeft(pLeft, typedFor', labels);
verifyEqual(testCase, pLeft, [0.9 0.1], 'The same groups, as a column: kept');
[pLeft, typedFor] = lum.pattern.typedPLeft(pLeft, typedFor, {'A first', 'B first'});
verifyEmpty(testCase, pLeft, 'Other groups: back to the family''s');
verifyEmpty(testCase, typedFor);
verifyEmpty(testCase, lum.pattern.typedPLeft([1 0 1], {}, labels), 'Wrong count: the family''s');
end

function testIdenticalLightPayingDifferentSidesIsRefused(testCase)
% Both groups deliver the same light but pay opposite sides: the animal cannot
% solve it, the session runs perfectly and its data mean nothing.
S = settingsWith('Family', 'arbitrary', 'Pulses', [1 1 0 0.5; 2 1 0 0.5]);
verifyError(testCase, @() lum.pattern.stimulusSet(S, 16, 2), ...
            'lum:pattern:stimulusSet:indistinguishable');
S.Task.GroupPLeft = [0.5 0.5];   % Redundant, but not unsolvable
verifyEqual(testCase, lum.pattern.stimulusSet(S, 16, 2).nGroups, 2);
end

function testAWordOnBothListsIsRefused(testCase)
S = settingsWith('Family', 'motif', 'MotifLeftWords', 'AAB ABA', 'MotifRightWords', 'ABA BBA');
verifyError(testCase, @() lum.pattern.stimulusSet(S, 16, 2), ...
            'lum:pattern:stimulusSet:indistinguishable');
end

function testPerTrialPatternsTakeTheirGroupsPLeft(testCase)
S = settingsWith('Family', 'mixture', 'Continuous', true);
S.Session.MaxTrials = 60;
S.Task.GroupPLeft = [0.9 0.2];
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
verifyEqual(testCase, stimulusSet.PatternPLeft(stimulusSet.PatternGroup == 1), ...
            repmat(0.9, 1, 30));
verifyEqual(testCase, stimulusSet.PatternPLeft(stimulusSet.PatternGroup == 2), ...
            repmat(0.2, 1, 30));
end

function testAPerTrialSequenceKeepsItsCountsAsGroups(testCase)
S = settingsWith('Family', 'count', 'Continuous', true);
S.Session.MaxTrials = 120;
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
verifyEqual(testCase, stimulusSet.nGroups, 6);
verifyEqual(testCase, stimulusSet.nPatterns, 120);
verifyEqual(testCase, stimulusSet.TrialPattern, 1:120);
verifyEqual(testCase, lum.pattern.patternAt(stimulusSet, 5).Name, ...
            sprintf('Trial 5 (%s)', stimulusSet.GroupLabels{stimulusSet.PatternGroup(5)}));
end

function testDefaultPLeftSweepsFromLeftToRight(testCase)
verifyEqual(testCase, lum.pattern.defaultPLeft(1), 0.5);
verifyEqual(testCase, lum.pattern.defaultPLeft(2), [1 0]);
verifyEqual(testCase, lum.pattern.defaultPLeft(5), linspace(1, 0, 5));
verifyEqual(testCase, lum.pattern.defaultPLeft(3, [0.9 0.5 0.1]), [0.9 0.5 0.1], ...
            'The operator''s own values are kept while the group count is unchanged');
end

function testThePreviewStatesCanBeStrippedForStorage(testCase)
stimulusSet = rmfield(lum.pattern.stimulusSet(settingsWith(), 16, 2), 'States');
verifyEqual(testCase, lum.pattern.patternAt(stimulusSet, 2).Segments, [2 0 1], 'AbsTol', 1e-9);
end

function testReversingTheContingencySwapsEverySide(testCase)
% The reversal is applied once, where the set is compiled, so everything downstream
% reads the contingency actually in force; the operator's own numbers stay in
% S.Task.GroupPLeft and come back as BasePLeft.
S = settingsWith('Family', 'arbitrary', 'nGroups', 3, ...
                 'Pulses', [1 1 0 0.5; 2 2 0 0.5; 3 1 0.5 1]);
S.Task.GroupPLeft = [1 0.25 0];
plain = lum.pattern.stimulusSet(S, 16, 2);
S.Task.ReverseContingency = true;
reversed = lum.pattern.stimulusSet(S, 16, 2);
verifyFalse(testCase, plain.Reversed);
verifyTrue(testCase, reversed.Reversed);
verifyEqual(testCase, reversed.GroupPLeft, 1 - plain.GroupPLeft, 'AbsTol', 1e-12);
verifyEqual(testCase, reversed.BasePLeft, plain.GroupPLeft, 'AbsTol', 1e-12);
verifyEqual(testCase, reversed.PatternPLeft, 1 - plain.PatternPLeft, 'AbsTol', 1e-12);
verifyEqual(testCase, reversed.TrialPattern, plain.TrialPattern, ...
            'Reversing pays the other side; it does not reorder the trials');
end

function testAReversedSetIsStillCheckedForIndistinguishableGroups(testCase)
% The check has to see the contingency the animal meets, not the one typed in.
S = settingsWith('Family', 'arbitrary', 'nGroups', 2, ...
                 'Pulses', [1 1 0 0.5; 2 1 0 0.5]);
S.Task.GroupPLeft = [1 0];
S.Task.ReverseContingency = true;
verifyError(testCase, @() lum.pattern.stimulusSet(S, 16, 2), ...
            'lum:pattern:stimulusSet:indistinguishable');
end

function testAContingencyCanBeAppliedToACompiledSet(testCase)
S = settingsWith('Family', 'mixture');
compiled = lum.pattern.stimulusSet(S, 16, 2);
typed = lum.pattern.applyContingency(compiled, [0.9 0.1 0.9 0.1 0.9 0.1], true);
S.Task.GroupPLeft = [0.9 0.1 0.9 0.1 0.9 0.1];
S.Task.ReverseContingency = true;
direct = lum.pattern.stimulusSet(S, 16, 2);
verifyEqual(testCase, typed, direct);
end

%% Single-cue ceilings -----------------------------------------------------------------

function testTheMixtureLadderLeavesEachAmountAmbiguous(testCase)
% Four levels, neighbours compared: each channel's amount alone is right in four of six
% groups (only the lowest and highest amounts give the side away), total light in half.
stimulusSet = lum.pattern.stimulusSet(settingsWith('Family', 'mixture'), 16, 2);
c = stimulusSet.Shortcuts;
verifyEqual(testCase, c.Method, 'exact');
verifyEqual(testCase, [c.AAmount c.BAmount c.TotalLight], [4 4 3] / 6, 'AbsTol', 0.01);
verifyEqual(testCase, c.AllLight, 1);
end

function testAnAloneRuleIsSolvedByItsChannel(testCase)
S = settingsWith('Family', 'mixture', 'MixtureRule', 'B alone');
S.Session.MaxTrials = 1600;   % 100 trials in each of the 16 groups
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
c = stimulusSet.Shortcuts;
verifyEqual(testCase, [c.BAmount c.BTimeCourse], [1 1]);
verifyEqual(testCase, [c.AAmount c.ATimeCourse], [0.5 0.5], 'AbsTol', 1e-12);
end

function testTheSimpleOrderIsSolvedByEitherTimeCourse(testCase)
% A first against B first: equal amounts, but A's time course alone gives it away.
stimulusSet = lum.pattern.stimulusSet(settingsWith('Family', 'order'), 16, 2);
c = stimulusSet.Shortcuts;
verifyEqual(testCase, [c.AAmount c.BAmount c.TotalLight], [0.5 0.5 0.5]);
verifyEqual(testCase, [c.ATimeCourse c.BTimeCourse], [1 1]);
end

function testGroupsPayingEitherSideLowerTheWholePatternsScore(testCase)
% A 1:1 mixture sits on the boundary and pays either side: 3 of the 9 groups.
S = settingsWith('Family', 'mixture', 'MixtureRatios', [2 1; 1 1; 1 2]);
S.Session.MaxTrials = 900;
c = lum.pattern.stimulusSet(S, 16, 2).Shortcuts;
verifyEqual(testCase, c.AllLight, (6 + 3 * 0.5) / 9, 'AbsTol', 1e-12);
end

function testTheDifferenceLadderLeavesEachAmountAmbiguous(testCase)
% A minus B = +-0.1 at totals 0.3 to 0.9: five amounts, only the lowest and highest give
% the side away, so each amount alone is right in 5 of 8 groups; the total in half.
S = settingsWith('Family', 'mixture', 'MixtureRule', 'difference');
S.Session.MaxTrials = 800;
c = lum.pattern.stimulusSet(S, 16, 2).Shortcuts;
verifyEqual(testCase, [c.AAmount c.BAmount c.TotalLight], [5 5 4] / 8, 'AbsTol', 1e-12);
end

function testShortcutsCanBeRecomputedFromAStoredSet(testCase)
stimulusSet = lum.pattern.stimulusSet(settingsWith('Family', 'motif'), 16, 2);
stored = rmfield(stimulusSet, 'States');
verifyEqual(testCase, lum.pattern.shortcuts(stored), stimulusSet.Shortcuts);
text = lum.pattern.describeShortcuts(stimulusSet.Shortcuts);
verifySubstring(testCase, text, 'A''s amount 75%');
verifySubstring(testCase, text, 'the whole pattern: 100%');
end


function S = settingsWith(varargin)
% Default settings with a fixed seed and generator fields overridden.
S = lum.defaultSettings;
S.Session.MaxTrials = 200;
S.Stimulus.Generator.Seed = 3;
for i = 1:2:numel(varargin)
    S.Stimulus.Generator.(varargin{i}) = varargin{i + 1};
end
end
