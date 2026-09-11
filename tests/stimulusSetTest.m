function tests = stimulusSetTest
% stimulusSetTest exercises the session's stimulus set: lum.pattern.stimulusSet.
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
S = settingsWith('Family', 'overlap_order', 'Continuous', true);
S.Session.MaxTrials = 100;
% Packing is under test, not the budget: the default overlap-order cycle puts about
% twenty stretches of light in a 1 s window, more than the rig's 16 timers.
stimulusSet = lum.pattern.stimulusSet(S, 64, 2);
verifyEqual(testCase, stimulusSet.nPatterns, 100);
for k = [1 37 100]
    expected = lum.pattern.fromStates(stimulusSet.States(:, k), stimulusSet.BinDuration);
    verifyEqual(testCase, lum.pattern.patternAt(stimulusSet, k).Segments, expected);
    verifyEqual(testCase, stimulusSet.nTimers(k), size(expected, 1));
end
end

function testTheTimerBudgetIsEnforcedPerPattern(testCase)
S = settingsWith('Family', 'sequence', 'NumCycles', 10);   % 10 stretches per channel
verifyError(testCase, @() lum.pattern.stimulusSet(S, 16, 2), ...
            'lum:pattern:stimulusSet:timerBudget');
S.Session.UseOpto = false;   % No light, no timers spent on it
verifyEqual(testCase, lum.pattern.stimulusSet(S, 16, 2).nGroups, 2);
end

function testTheTimerErrorNamesTheGroup(testCase)
S = settingsWith('Family', 'sequence', 'NumCycles', 10);
try
    lum.pattern.stimulusSet(S, 5, 2);
    verifyFail(testCase, 'A 20-segment pattern must not fit 5 timers');
catch rejection
    verifySubstring(testCase, rejection.message, 'Group 1');
end
end

function testTheContingencyMustMatchTheGroups(testCase)
S = settingsWith();
S.Task.GroupPLeft = [1 0 0.5];
verifyError(testCase, @() lum.pattern.stimulusSet(S, 16, 2), ...
            'lum:pattern:stimulusSet:contingencyMismatch');
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

function testContinuousPatternsTakeTheirCategorysPLeft(testCase)
S = settingsWith('Continuous', true);
S.Session.MaxTrials = 60;
S.Task.GroupPLeft = [0.9 0.2];
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
verifyEqual(testCase, stimulusSet.PatternPLeft(stimulusSet.PatternGroup == 1), ...
            repmat(0.9, 1, 30));
verifyEqual(testCase, stimulusSet.PatternPLeft(stimulusSet.PatternGroup == 2), ...
            repmat(0.2, 1, 30));
end

function testAContinuousSetWithoutCategoriesUsesTheBShare(testCase)
S = settingsWith('Family', 'occupancy', 'Continuous', true, 'AOnFraction', 0.7, ...
                 'BOnFraction', 0.3, 'Overlap', 0.1);
S.Session.MaxTrials = 20;
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
verifyTrue(testCase, all(stimulusSet.PatternGroup == 1), 'A carries more light: A-led');
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


function S = settingsWith(varargin)
% Default settings with a fixed seed and generator fields overridden.
S = lum.defaultSettings;
S.Session.MaxTrials = 200;
S.Stimulus.Generator.Seed = 3;
for i = 1:2:numel(varargin)
    S.Stimulus.Generator.(varargin{i}) = varargin{i + 1};
end
end
