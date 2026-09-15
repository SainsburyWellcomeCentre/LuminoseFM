function tests = trainingStageTest
% trainingStageTest exercises lum.trainingStageNote and the contingency it describes.
%
% Habituation rewarding both side ports looks exactly like a broken contingency from
% the console, so the note that warns about it has to stay true to what
% lum.nextTrialSpec actually does. These tests hold the two together.
tests = functiontests(localfunctions);
end

function testHabituationSaysBothPortsReward(testCase)
S = lum.defaultSettings;
S.Task.TrainingStage = 1;
note = lum.trainingStageNote(S);
verifySubstring(testCase, note, 'Habituation');
verifySubstring(testCase, note, 'BOTH side ports reward');
end

function testLaterStagesSayOnlyTheCorrectPortRewards(testCase)
S = lum.defaultSettings;
for stage = 2:3
    S.Task.TrainingStage = stage;
    note = lum.trainingStageNote(S);
    verifySubstring(testCase, note, 'only the correct side port rewards');
    verifySubstring(testCase, note, S.Task.TrainingStageNames{stage});
end
end

function testTheNoteMatchesWhatTheTrialSpecActuallyDoes(testCase)
S = lum.defaultSettings;
S.Session.MaxTrials = 20;
stimulusSet = lum.pattern.stimulusSet(S, 16, 2);
for stage = 1:3
    S.Task.TrainingStage = stage;
    spec = lum.nextTrialSpec(S, stimulusSet, stimulusSet.TrialPattern, lum.newHistory(10), 1);
    saysBoth = contains(lum.trainingStageNote(S), 'BOTH');
    verifyEqual(testCase, saysBoth, isequal(sort(spec.RewardedSides), [1 2]), ...
                sprintf('Stage %d: the note and the rewarded sides disagree', stage));
end
end

function testHabituationDefaultsToAirAndNoLight(testCase)
% Choosing habituation shapes the session: the hold is as long and as salient as it
% will be later, and carries nothing to discriminate.
S = lum.stageDefaults(lum.defaultSettings, 1);
verifyFalse(testCase, S.Session.UseOpto, 'Habituation delivers no light');
verifyEqual(testCase, S.GUI.OptoOn, 0);
air = S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, 'Air'));
verifyTrue(testCase, air.Enabled, 'Habituation delivers air');
verifyEqual(testCase, air.Onset, 0);
verifyEqual(testCase, air.Duration, S.Stimulus.Duration, ...
            'Air spanning the window costs no global timer');
end

function testTheLaterStagesBringTheLightBack(testCase)
habituation = lum.stageDefaults(lum.defaultSettings, 1);
for stage = 2:3
    [S, changed] = lum.stageDefaults(habituation, stage);
    verifyTrue(testCase, S.Session.UseOpto, sprintf('Stage %d delivers light', stage));
    verifyEqual(testCase, S.GUI.OptoOn, 1);
    air = S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, 'Air'));
    verifyFalse(testCase, air.Enabled);
    verifyNotEmpty(testCase, changed, 'Leaving habituation changes the session');
end
end

function testApplyingAStagesDefaultsTwiceChangesNothingTheSecondTime(testCase)
[S, first] = lum.stageDefaults(lum.defaultSettings, 1);
[~, second] = lum.stageDefaults(S, 1);
verifyNotEmpty(testCase, first);
verifyEmpty(testCase, second);
end

function testAStageDefaultSessionStillValidates(testCase)
rig = RigConfig;
for stage = 1:3
    S = lum.stageDefaults(lum.defaultSettings, stage);
    S.Task.TrainingStage = stage;
    S.Session.MaxTrials = 20;
    verifyWarningFree(testCase, @() lum.validateSettings(S, rig), ...
                      sprintf('Stage %d''s defaults must be a session that can start', stage));
end
end

function testAnOutOfRangeStageDoesNotThrow(testCase)
S = lum.defaultSettings;
S.Task.TrainingStage = 9;
verifySubstring(testCase, lum.trainingStageNote(S), 'unknown');
end
