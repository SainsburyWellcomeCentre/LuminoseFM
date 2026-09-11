function tests = patternTest
% patternTest exercises light patterns as the state machine sees them: lum.pattern.*
%
% A pattern becomes one global timer per stretch of light on a channel, so the
% translation from joint states to segments, and the normal form segments are kept
% in, decide both what light is delivered and what it costs. All pure functions.
tests = functiontests(localfunctions);
end

function testEachRunOfLightBecomesOneSegment(testCase)
states = uint8([1 1 3 3 2 2 0 0 1 1]');
segments = lum.pattern.fromStates(states, 0.1);
verifyEqual(testCase, segments, [1 0 0.4; 1 0.8 0.2; 2 0.2 0.4], 'AbsTol', 1e-9);
end

function testADarkPatternHasNoSegments(testCase)
verifyEmpty(testCase, lum.pattern.fromStates(zeros(20, 1, 'uint8'), 0.01));
verifySize(testCase, lum.pattern.fromStates(zeros(20, 1, 'uint8'), 0.01), [0 3]);
end

function testSegmentTimesAreQuantisedToTheStateMachineCycle(testCase)
segments = lum.pattern.fromStates(uint8([1 1 1 0 2]'), 1/3);
verifyEqual(testCase, segments(:, 2:3), round(segments(:, 2:3) * 1e4) / 1e4, 'AbsTol', 1e-12);
end

function testFromStatesIsAlreadyCanonical(testCase)
states = uint8([3 3 1 2 2 3 0 1]');
segments = lum.pattern.fromStates(states, 0.05);
pattern = struct('Name', 'x', 'Duration', 0.4, 'Segments', segments, 'nChannels', 2);
verifyEqual(testCase, lum.pattern.canonicalise(pattern).Segments, segments, 'AbsTol', 1e-12);
end

function testTouchingSegmentsOnOneChannelAreMerged(testCase)
% Two timers driving one BNC line would fight, and the union is optically one
% longer segment, so canonicalise must merge them.
pattern = lum.pattern.canonicalise(struct('Name', 'merge', 'Duration', 1, 'nChannels', 2, ...
                                          'Segments', [1 0 0.5; 1 0.5 0.5]));
verifyEqual(testCase, pattern.Segments, [1 0 1.0], 'AbsTol', 1e-9);
end

function testOverlappingSegmentsOnOneChannelAreMerged(testCase)
pattern = lum.pattern.canonicalise(struct('Name', 'merge', 'Duration', 1, 'nChannels', 2, ...
                                          'Segments', [1 0.4 0.4; 1 0 0.5]));
verifyEqual(testCase, pattern.Segments, [1 0 0.8], 'AbsTol', 1e-9);
end

function testSegmentsOnDifferentChannelsAreNotMerged(testCase)
pattern = lum.pattern.canonicalise(struct('Name', 'keep', 'Duration', 1, 'nChannels', 2, ...
                                          'Segments', [1 0 0.5; 2 0 0.5]));
verifySize(testCase, pattern.Segments, [2 3]);
end

function testTooManySegmentsForTheTimerBudgetIsReported(testCase)
segments = lum.pattern.fromStates(uint8(repmat([1; 2], 4, 1)), 0.1);
pattern = struct('Name', 'busy', 'Duration', 0.8, 'Segments', segments, 'nChannels', 2);
problems = lum.pattern.check(pattern, 5);
verifyNotEmpty(testCase, problems, 'An 8-segment pattern must not fit 5 global timers');
verifySubstring(testCase, problems{1}, 'global timers');
verifyEmpty(testCase, lum.pattern.check(pattern, 16), 'The same pattern must fit the rig''s 16');
end

function testSegmentsPastTheWindowAreReported(testCase)
pattern = lum.pattern.canonicalise(struct('Name', 'late', 'Duration', 1, 'nChannels', 2, ...
                                          'Segments', [1 0.8 0.5]));
verifyNotEmpty(testCase, lum.pattern.check(pattern, 16));
end

function testValidateThrowsOnAnUnusablePattern(testCase)
pattern = struct('Name', 'bad', 'Duration', 1, 'nChannels', 2, 'Segments', [3 0 0.5]);
verifyError(testCase, @() lum.pattern.validate(pattern, 16), 'lum:pattern:invalid');
end

function testDescribeNamesTheChannelsAAndB(testCase)
pattern = struct('Name', 'AB', 'Duration', 1, 'nChannels', 2, ...
                 'Segments', [1 0 0.5; 2 0.25 0.75]);
text = lum.pattern.describe(pattern);
verifySubstring(testCase, text, 'A 0-500 ms');
verifySubstring(testCase, text, 'B 250-1000 ms');
verifySubstring(testCase, text, '2 timers');
end

function testDescribeSaysWhenAPatternIsDark(testCase)
pattern = struct('Name', 'control', 'Duration', 0.5, 'nChannels', 2, 'Segments', zeros(0, 3));
verifySubstring(testCase, lum.pattern.describe(pattern), 'dark');
end

function testParseNumbersAcceptsAnySeparator(testCase)
verifyEqual(testCase, lum.gui.parseNumbers('1, 2;3  4', 'x'), [1 2 3 4]);
verifyEmpty(testCase, lum.gui.parseNumbers('  ', 'x'));
verifyTrue(testCase, isnan(lum.gui.parseNumbers('NaN', 'x')));
verifyError(testCase, @() lum.gui.parseNumbers('1 two', 'x'), 'lum:gui:parseNumbers:notNumbers');
end
