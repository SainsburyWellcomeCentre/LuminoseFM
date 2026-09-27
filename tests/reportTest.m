function tests = reportTest
% reportTest covers what a behaviour session writes for people to read as it ends: the
% summary plots (lum.report.summaryPlots), the log (lum.report.sessionLog), the online figure
% replayed from a saved file (lum.report.fromFile), and the runtime window's trial lines
% (lum.trialStatus). No hardware: sessions are made up here, and files go to a temporary
% folder laid out like a subject's.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.root = fullfile(tempname, 'SUBJ01', 'LuminoseFM');
mkdir(fullfile(testCase.TestData.root, 'Session Data'));
testCase.TestData.rig = RigConfig;
end

function teardownOnce(testCase)
if isfolder(fileparts(testCase.TestData.root))
    rmdir(fileparts(testCase.TestData.root), 's');
end
end


%% The runtime window's trial lines

function testHabituationSaysRewardedNotCorrect(testCase)
spec = struct('RewardedSides', [1 2], 'CorrectSide', 1);
result = resultOf(lum.Outcome.Incorrect, 2, 1);
lines = lum.trialStatus(7, spec, result, [], []);
verifyEqual(testCase, lines, {'Trial 7: rewarded, chose right'});
result = resultOf(lum.Outcome.CorrectNoReward, 1, 0);
lines = lum.trialStatus(8, spec, result, [], []);
verifySubstring(testCase, lines{1}, 'not rewarded: chose left, left before the valve opened');
verifyFalse(testCase, contains(lower(strjoin(lines)), 'correct'), 'No correct or incorrect in habituation');
end

function testTrainingSaysCorrectOrIncorrect(testCase)
spec = struct('RewardedSides', 1, 'CorrectSide', 1);
verifyEqual(testCase, lum.trialStatus(3, spec, resultOf(lum.Outcome.Correct, 1, 1), [], []), ...
            {'Trial 3: correct, chose left'});
retried = resultOf(lum.Outcome.Incorrect, 2, 1);
verifyEqual(testCase, lum.trialStatus(4, spec, retried, [], []), ...
            {'Trial 4: incorrect, chose right, then rewarded on a retry'});
end

function testATrialWithoutAChoiceSaysWhy(testCase)
spec = struct('RewardedSides', [1 2], 'CorrectSide', 2);
result = resultOf(lum.Outcome.HoldNotCompleted, NaN, 0);
result.HoldAttempts = 14;
lines = lum.trialStatus(5, spec, result, [], []);
verifyEqual(testCase, lines, {'Trial 5: hold not completed in the hold window (14 holds)'});
end

function testTheRunningTrialSaysWhoPays(testCase)
stimulusSet = struct('GroupLabels', {{'A only', 'B only'}});
running = struct('TrialNumber', 9, 'StimulusGroup', 2, 'CorrectSide', 2, 'RewardedSides', [1 2], ...
                 'OptoOn', false, 'HoldDuration', 0.6, 'HoldSteppedBack', true, ...
                 'CentreReward', true, 'CentreRewardAgain', false, 'CentreRewardAmount', 1.2);
lines = lum.trialStatus(0, [], [], running, stimulusSet);
verifyEqual(testCase, lines{1}, 'Session started');
verifyEqual(testCase, lines{2}, ['Running 9: B only (light off), both sides pay, hold 0.60 s '...
                                 '(stepped back after early withdrawals), centre reward 1.2 uL']);
running.RewardedSides = 2;
running.OptoOn = true;
lines = lum.trialStatus(0, [], [], running, stimulusSet);
verifySubstring(testCase, lines{2}, 'B only, pays right');
end


%% Where the reports go

function testReportsGoBesideSessionData(testCase)
dataFile = fullfile('D:', 'data', 'M1', 'LuminoseFM', 'Session Data', 'M1_LuminoseFM_20260927_130459.mat');
verifyEqual(testCase, lum.report.folder(dataFile, 'Plots'), ...
            fullfile('D:', 'data', 'M1', 'LuminoseFM', 'Session Plots'));
verifyEqual(testCase, lum.report.folder(dataFile, 'Logs'), ...
            fullfile('D:', 'data', 'M1', 'LuminoseFM', 'Session Logs'));
verifyEqual(testCase, lum.report.fileTag(dataFile, 'M1'), 'M1_20260927_130459');
verifyEqual(testCase, lum.report.fileTag(dataFile, ''), 'M1_20260927_130459');
verifyError(testCase, @() lum.report.folder(dataFile, 'Videos'), 'lum:report:folder:unknownKind');
end


%% Plots and log from a session

function testASessionWritesItsPlotsAndLog(testCase)
[Data, dataFile] = madeUpSession(testCase, 120, 1, '20260101_100000');
report = lum.report.write(Data, dataFile);
verifyEmpty(testCase, report.Problems, strjoin(report.Problems, ' | '));
names = cellfun(@fileNameOf, report.Plots, 'UniformOutput', false);
expected = {'01_Outcomes', '02_Performance', '03_Psychometric', '04_Evidence', '05_BySide', ...
            '06_SideBias', '07_ReactionTime', '08_CentreHold', '09_HoldAttempts', '10_Engagement', ...
            '11_PortActivity', '12_SessionTiming'};
for i = 1:numel(expected)
    verifyTrue(testCase, any(strcmp(names, sprintf('%s_01_SUBJ01_20260101_100000.png', expected{i}))), ...
               expected{i});
end
for i = 1:numel(report.Plots)
    info = dir(report.Plots{i});
    verifyLessThan(testCase, info.bytes, 400e3, 'A summary plot stays small');
end
verifyEqual(testCase, fileparts(report.Plots{1}), fullfile(testCase.TestData.root, 'Session Plots'));
verifyEqual(testCase, report.Log, fullfile(testCase.TestData.root, 'Session Logs', ...
                                           'SUBJ01_LuminoseFM_20260101_100000_log.md'));
text = fileread(report.Log);
verifySubstring(testCase, text, 'Rewarded on');
verifySubstring(testCase, text, '## Changed during the session');
verifySubstring(testCase, text, 'Reward amount (uL) 3 -> 2', 'A runtime change is listed');
verifyFalse(testCase, contains(text, 'Correct on'), 'Habituation is scored by the reward');
end

function testALongSessionPagesItsOutcomes(testCase)
[Data, dataFile] = madeUpSession(testCase, 450, 2, '20260102_100000');
files = lum.report.summaryPlots(Data, dataFile);
names = cellfun(@fileNameOf, files, 'UniformOutput', false);
verifyTrue(testCase, any(strcmp(names, '01_Outcomes_02_SUBJ01_20260102_100000.png')));
[~, lines] = lum.report.sessionLog(Data, dataFile, 'Write', false);
verifyTrue(testCase, any(startsWith(lines, '- Correct on')), 'Training is scored by the side');
end

function testASavedFileIsReadAndNeverChanged(testCase)
[Data, dataFile] = madeUpSession(testCase, 60, 1, '20260103_100000');
SessionData = Data;
save(dataFile, 'SessionData');
before = fileBytes(dataFile);
info = dir(dataFile);
report = lum.report.fromFile(dataFile, 'OnlinePlots', true);
verifyEmpty(testCase, report.Problems, strjoin(report.Problems, ' | '));
verifyEqual(testCase, fileBytes(dataFile), before, 'The data file is only read');
after = dir(dataFile);
verifyEqual(testCase, after.datenum, info.datenum);
[folder, name] = fileparts(dataFile);
verifyEqual(testCase, report.OnlinePlots, fullfile(folder, [name '_plots.png']));
verifyTrue(testCase, isfile(report.OnlinePlots));
verifyNumElements(testCase, report.Plots, 12);
verifyTrue(testCase, isfile(report.Log));
end


%% Helpers

function result = resultOf(outcome, choice, rewarded)
result = struct('Outcome', outcome, 'Choice', choice, 'Rewarded', rewarded, 'HoldAttempts', 1);
end

function name = fileNameOf(file)
[~, stem, extension] = fileparts(file);
name = [stem extension];
end

function bytes = fileBytes(file)
handle = fopen(file, 'r');
bytes = fread(handle, Inf, '*uint8');
fclose(handle);
end

function [Data, dataFile] = madeUpSession(testCase, n, stage, stamp)
% A behaviour session's data as LuminoseFM saves it, made up: n trials of an animal that
% chooses at random, with some holds broken and one runtime change.
rig = testCase.TestData.rig;
S = lum.defaultSettings;
S.Task.TrainingStage = stage;
S.Session.UseOpto = stage > 1;
S.Session.MaxTrials = 1000;
S.Meta.Subject = 'SUBJ01';
stimulusSet = lum.validateSettings(S, rig);
stream = RandStream('mt19937ar', 'Seed', n);
Data = struct();
Data.nTrials = n;
Data.Info = struct('EmulatorMode', 1);
Data.TrialStartTimestamp = (0:n - 1) * 10 + 5;
Data.TrialEndTimestamp = Data.TrialStartTimestamp + 8;
Data.RawEvents.Trial = cell(1, n);
names = {'StimulusGroup', 'PatternIndex', 'CorrectSide', 'Choice', 'Correct', 'Rewarded', ...
         'Outcome', 'ReactionTime', 'OptoOn', 'SoundOn', 'HouseLight', 'SyncMode', 'SyncPulseWidth', ...
         'BiasTargetPLeft', 'TrainingStage', 'HoldDuration', 'HoldGrace', 'HoldBreaks', ...
         'HoldAttempts', 'EarlyWithdrawals', 'CameraTime', 'LEDCurrentA', 'LEDCurrentB', ...
         'CentreReward', 'ResponseRetries', 'CentreHoldTime'};
for i = 1:numel(names)
    Data.(names{i}) = NaN(1, n);
end
Data.TrialSettings = cell(1, n);
for k = 1:n
    pattern = stimulusSet.TrialPattern(k);
    side = 1 + (stimulusSet.PatternPLeft(pattern) < 0.5);
    attempts = 1 + floor(3 * rand(stream));
    completed = rand(stream) > 0.1;
    choice = NaN;
    if completed
        choice = 1 + (rand(stream) > 0.5);
    end
    holdSeconds = 0.2 + 0.4 * k / n;
    Data.StimulusGroup(k) = stimulusSet.PatternGroup(pattern);
    Data.PatternIndex(k) = pattern;
    Data.CorrectSide(k) = side;
    Data.Choice(k) = choice;
    Data.Correct(k) = double(choice == side) + 0 * choice;
    Data.Rewarded(k) = double(~isnan(choice) && (stage == 1 || choice == side));
    if isnan(choice)
        Data.Outcome(k) = lum.Outcome.HoldNotCompleted;
    elseif choice == side
        Data.Outcome(k) = lum.Outcome.Correct;
    else
        Data.Outcome(k) = lum.Outcome.Incorrect;
    end
    Data.ReactionTime(k) = choice * 0 + 0.3 + rand(stream);
    Data.OptoOn(k) = double(S.Session.UseOpto);
    Data.TrainingStage(k) = stage;
    Data.HoldDuration(k) = holdSeconds;
    Data.HoldAttempts(k) = attempts;
    Data.EarlyWithdrawals(k) = attempts - completed;
    Data.BiasTargetPLeft(k) = 0.5;
    Data.CentreReward(k) = 1.2 * (stage == 1 && k <= 10 && completed);
    Data.ResponseRetries(k) = 0;
    Data.CentreHoldTime(k) = holdSeconds + 0.2 * completed;
    Data.SyncMode(k) = 2;
    gui = S.GUI;
    if k > n / 2
        gui.RewardAmount = 2;
    end
    Data.TrialSettings{k} = gui;
    visits = [(1:attempts)' * 0.5, (1:attempts)' * 0.5 + 0.1];
    visits(end, 2) = visits(end, 1) + holdSeconds * completed + 0.1 * ~completed;
    Data.RawEvents.Trial{k} = struct('States', struct('CentreHold', visits), ...
        'Events', struct('Port2In', visits(:, 1)', 'Port1In', 3 + (choice == 1), ...
                         'Port3In', 3 + (choice == 2)));
end
Data.Timing = struct('prepare', 0.1 * ones(1, n), 'send', 0.01 * ones(1, n), ...
                     'plot', 0.2 * ones(1, n), 'save', 0.05 * ones(1, n), 'memoryGB', 4 * ones(1, n));
Data.Session = struct('Type', 'Behaviour', 'Subject', 'SUBJ01', 'Settings', S, ...
                      'StimulusSet', rmfield(stimulusSet, 'States'), 'Rig', rig, ...
                      'StartTime', '2026-01-01 10:00:00', 'EndTime', '2026-01-01 10:20:00', ...
                      'StoppedReason', '', 'ProtocolVersion', lum.version(), 'Emulated', true, ...
                      'Barcode', struct('Hex', '0000ABCD', 'Kind', 'Behaviour', 'Sent', false));
dataFile = fullfile(testCase.TestData.root, 'Session Data', sprintf('SUBJ01_LuminoseFM_%s.mat', stamp));
end
