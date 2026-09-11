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

function testAnOutOfRangeStageDoesNotThrow(testCase)
S = lum.defaultSettings;
S.Task.TrainingStage = 9;
verifySubstring(testCase, lum.trainingStageNote(S), 'unknown');
end
