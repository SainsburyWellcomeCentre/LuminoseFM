function tests = cueTimingTest
% cueTimingTest exercises what each part of the cue does once the stimulus starts:
% lum.cueTiming.
%
% Every cue component is on until the stimulus starts; what it does from stimulus onset
% decides the state machine's outputs and the timer budget. Pure; no Bpod.
tests = functiontests(localfunctions);
end

function testTheCueStaysOnThroughTheStimulusByDefault(testCase)
cue = lum.cueTiming(lum.defaultSettings);
verifyEqual(testCase, {cue.Type}, {'CentreLight'});
verifyEqual(testCase, cue.Mode, 'Whole');
verifyEqual(testCase, cue.Duration, Inf);
end

function testZeroSwitchesAComponentOffAsTheStimulusStarts(testCase)
cue = lum.cueTiming(withCue(lum.defaultSettings, {'Tone'}, 0));
verifyEqual(testCase, cue.Mode, 'Off');
verifyEqual(testCase, cue.Duration, 0);
end

function testAShorterTimeGoesOffPartWayThroughTheStimulus(testCase)
S = withCue(lum.defaultSettings, {'Air'}, 0.3);
S.Stimulus.Duration = 1;
cue = lum.cueTiming(S);
verifyEqual(testCase, cue.Mode, 'Timed');
verifyEqual(testCase, cue.Duration, 0.3);
end

function testATimeSpanningTheWindowIsTheWholeStimulus(testCase)
S = withCue(lum.defaultSettings, {'CentreLight'}, 1.5);
S.Stimulus.Duration = 1;
verifyEqual(testCase, lum.cueTiming(S).Mode, 'Whole', 'Nothing to switch off inside the hold');
end

function testComponentsComeInSettingsOrderAndOnlyWhenOn(testCase)
cue = lum.cueTiming(withCue(lum.defaultSettings, {'Air', 'CentreLight'}));
verifyEqual(testCase, {cue.Type}, {'CentreLight', 'Air'});
verifyEmpty(testCase, lum.cueTiming(withCue(lum.defaultSettings, {})));
end

function testANegativeTimeIsRejected(testCase)
S = withCue(lum.defaultSettings, {'CentreLight'}, -0.1);
verifyError(testCase, @() lum.cueTiming(S), 'lum:cueTiming:badDuration');
end

function testOnlyALightOrAirStoppingPartWayCostsATimer(testCase)
S = lum.defaultSettings;
S.Stimulus.Duration = 1;
verifyEqual(testCase, lum.stim.timerCost(withCue(S, {'CentreLight', 'Tone', 'Air'})), 0, ...
            'Through the whole stimulus is free');
verifyEqual(testCase, lum.stim.timerCost(withCue(S, {'CentreLight', 'Tone', 'Air'}, 0)), 0, ...
            'Off as the stimulus starts is free');
verifyEqual(testCase, lum.stim.timerCost(withCue(S, {'CentreLight', 'Air'}, 0.3)), 2);
verifyEqual(testCase, lum.stim.timerCost(withCue(S, {'Tone'}, 0.3)), 0, 'A tone never costs one');
end
