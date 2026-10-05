function tests = reportTest
% reportTest covers the summary plots, log and trial lines a behaviour session writes.
%
% What a behaviour session writes for people to read as it ends: the summary plots
% (lum.report.summaryPlots), the log (lum.report.sessionLog), the locking of early
% withdrawals to the light's pulses (lum.report.pulseLocking), the online figure replayed
% from a saved file (lum.report.fromFile), and the runtime window's trial lines
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
result.EarlyWithdrawals = 14;
result.HoldCompleted = 0;
lines = lum.trialStatus(5, spec, result, [], []);
verifyEqual(testCase, lines, {'Trial 5: hold not completed in the hold window (14 hold attempts)'});
end

function testAHoldCompletedAfterEarlyWithdrawalsSaysAtWhichAttempt(testCase)
% The runtime window, the plots and the log count a hold completed after early withdrawals
% as completed (lum.holdMeasures): the line says so, and at which attempt.
spec = struct('RewardedSides', [1 2], 'CorrectSide', 2);
result = resultOf(lum.Outcome.Correct, 2, 1);
result.EarlyWithdrawals = 2;
result.HoldCompleted = 1;
verifyEqual(testCase, lum.trialStatus(6, spec, result, [], []), ...
            {'Trial 6: rewarded, chose right (held on attempt 3)'});
result.EarlyWithdrawals = 0;
verifyEqual(testCase, lum.trialStatus(6, spec, result, [], []), {'Trial 6: rewarded, chose right'});
ended = resultOf(lum.Outcome.EarlyWithdrawal, NaN, 0);
ended.EarlyWithdrawals = 1;
ended.HoldCompleted = 0;
verifyEqual(testCase, lum.trialStatus(7, spec, ended, [], []), {'Trial 7: early withdrawal'}, ...
            'Under End trial one attempt ends the trial');
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
            '11_PortActivity', '12_SessionTiming', '13_PulseLocking'};
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
verifySubstring(testCase, text, 'pulses the light would have had (no light: a control)', ...
                'A session without light is measured against its carrier as a control');
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
verifyNumElements(testCase, report.Plots, 13);
verifyTrue(testCase, isfile(report.Log));
end


function testTheOnlineFigureAndTheReportsAgreeOnTheHold(testCase)
% The replayed online figure, the summary plots' numbers and the log read the hold from the
% same states: a hold completed after early withdrawals is completed in all three, and only
% the attempts tell it from a first-attempt hold.
[Data, dataFile] = madeUpSession(testCase, 80, 2, '20260104_100000');
T = lum.report.sessionTrials(Data);
for k = 1:T.n
    measures = lum.holdMeasures(Data.RawEvents.Trial{k}.States);
    verifyEqual(testCase, [T.holdCompleted(k), T.heldFirstAttempt(k), T.attempts(k)], ...
                [measures.Completed, measures.FirstAttempt, measures.Attempts]);
end
verifyEqual(testCase, T.holdCompleted, double(~isnan(Data.Choice)), ...
            'Every trial with a choice completed its hold');
verifyEqual(testCase, T.attempts, Data.HoldAttempts, 'Without a latency, attempts are CentreHold visits');
retried = find(T.holdCompleted == 1 & T.heldFirstAttempt == 0);
verifyNotEmpty(testCase, retried, 'The made-up animal completes some holds after early withdrawals');

plots = lum.report.replayOnlinePlots(Data);
cleanup = onCleanup(@() plots.close());
holdAxes = findall(plots.Figure, 'Type', 'axes');
holdAxes = holdAxes(arrayfun(@(a) startsWith(string(a.Title.String), 'Centre hold'), holdAxes));
completedLine = findobj(holdAxes, 'Type', 'line', 'Marker', '.');
notLine = findobj(holdAxes, 'Type', 'line', 'Marker', 'x');
verifyEqual(testCase, find(~isnan(completedLine.YData)), find(T.holdCompleted == 1), ...
            'The online figure marks the same holds completed');
verifyEqual(testCase, find(~isnan(notLine.YData)), find(T.holdCompleted == 0));
verifyEqual(testCase, completedLine.Color, lum.gui.theme().Correct);

[~, lines] = lum.report.sessionLog(Data, dataFile, 'Write', false);
verifyTrue(testCase, any(startsWith(lines, sprintf('- Hold completed on %d of %d trials', ...
                                                   sum(T.holdCompleted), T.n))));
verifyTrue(testCase, any(startsWith(lines, sprintf('- Held on the first attempt on %d trials', ...
                                                   sum(T.heldFirstAttempt)))));
verifyFalse(testCase, any(contains(lines, 'early withdrawal 0')), ...
            'Early withdrawals are not an outcome of their own in the log');
delete(cleanup);
end


%% Early withdrawals and the light's pulses

function testWithdrawalsTiedToThePulsesAreFound(testCase)
% Withdrawals 39 ms after a 20 Hz pulse, more of them late in the window as in LUMS0014's
% sessions: locked, at that phase, on both channels.
stream = RandStream('mt19937ar', 'Seed', 3);
pulse = 1 + floor(6 * sqrt(rand(stream, 1, 600)));    % later pulses more often
times = (pulse - 1) * 0.05 + 0.039 + 0.006 * randn(stream, 1, 600);
times = times(times > 0.02 & times < 0.3);
L = lum.report.pulseLocking(madeUpWithdrawals(times, 1, 20, 0.005), 'Surrogates', 400);
verifyTrue(testCase, L.Measured);
verifyTrue(testCase, L.Light);
verifyLessThan(testCase, L.P, 0.01);
verifyGreaterThan(testCase, L.R, L.Threshold);
verifyEqual(testCase, L.MeanPhase, 0.039, 'AbsTol', 0.003);
verifyLessThan(testCase, L.ExcessP, 0.01, 'Locked beyond the shape');
verifyGreaterThan(testCase, L.Excess, L.ExcessThreshold);
verifyEqual(testCase, L.ExcessPhase, 0.039, 'AbsTol', 0.005, 'Pointing at the locked time');
verifyEqual(testCase, [L.ByChannel.n], [ceil(numel(times) / 2), floor(numel(times) / 2)]);
verifyLessThan(testCase, [L.ByChannel.P], 0.05);
verifyLessThan(testCase, [L.ByChannel.ExcessP], 0.05);
verifyEqual(testCase, L.Spectrum.Frequencies(1), 10, 'The spectrum starts at 10 Hz');
[~, best] = max(L.Spectrum.Excess - L.Spectrum.ExcessThreshold);
verifyEqual(testCase, L.Spectrum.Frequencies(best), 20, 'The carrier''s frequency stands out');
again = lum.report.pulseLocking(madeUpWithdrawals(times, 1, 20, 0.005), 'Surrogates', 400);
verifyEqual(testCase, again.P, L.P, 'The surrogates come from a private seeded stream');
end

function testTheWithdrawalTimesShapeAloneIsNotLocking(testCase)
% Withdrawals rising smoothly towards the end of the window, with no pulse in them: a
% Rayleigh test would call the shape locking; against the surrogates about 5% of such
% sessions fall below p 0.05, as a test at 0.05 should (60 here; 6% in 200 when measured),
% and so does the locking beyond the shape.
stream = RandStream('mt19937ar', 'Seed', 4);
[p, excessP] = deal(zeros(1, 60));
for r = 1:numel(p)
    times = 0.02 + 0.28 * sqrt(rand(stream, 1, 800));
    L = lum.report.pulseLocking(madeUpWithdrawals(times, 1, 20, 0.005), 'Surrogates', 200, ...
                                'Frequencies', 20, 'Seed', r);
    p(r) = L.P;
    excessP(r) = L.ExcessP;
end
verifyLessThanOrEqual(testCase, mean(p < 0.05), 0.15);
verifyGreaterThan(testCase, median(p), 0.25);
verifyLessThanOrEqual(testCase, mean(excessP < 0.05), 0.15);
verifyGreaterThan(testCase, median(excessP), 0.25);
end

function testTheShapeAloneHasAPhaseOfItsOwn(testCase)
% Withdrawals rising towards the end of the window point at some time after a pulse with no
% pulse in them (LUMS0014: about 36 ms, light or no light), so the observed mean vector is
% mostly the shape's, and the share the shape puts in each phase bin is not flat.
stream = RandStream('mt19937ar', 'Seed', 5);
times = 0.02 + 0.28 * sqrt(rand(stream, 1, 3000));
L = lum.report.pulseLocking(madeUpWithdrawals(times, 1, 20, 0.005), 'Surrogates', 400, ...
                            'Frequencies', 20);
verifyGreaterThan(testCase, L.Shape, 0.02);
verifyEqual(testCase, L.MeanPhase, L.ShapePhase, 'AbsTol', 0.005);
verifyLessThan(testCase, L.Excess, L.ExcessThreshold);
verifyEqual(testCase, sum(L.ShapeShare), 1, 'AbsTol', 1e-9);
verifySize(testCase, L.ShapeShare, [1 10]);
verifyGreaterThan(testCase, max(L.ShapeShare) - min(L.ShapeShare), 0.01);
end

function testWithdrawalsOutsideTheLightAreLeftOut(testCase)
% Before MinTime, after the light, completed holds and trials with the light off.
T = madeUpWithdrawals([0.01 0.1 0.2 0.35], 1, 20, 0.005);
T.attemptCompleted(3) = true;
L = lum.report.pulseLocking(T, 'Surrogates', 50);
verifyEqual(testCase, L.Time, 0.1, 'AbsTol', 1e-12);
T.optoOn(:) = 0;
T.optoOn(1) = 1;
L = lum.report.pulseLocking(T, 'Surrogates', 50);
verifyFalse(testCase, L.Measured, 'Only trial 1 had light, and its withdrawal came too early');
verifySubstring(testCase, L.Reason, 'no early withdrawals');
end

function testASessionWithoutLightIsAControl(testCase)
T = madeUpWithdrawals(linspace(0.03, 0.29, 50), 0, 20, 0.005);
L = lum.report.pulseLocking(T, 'Surrogates', 50);
verifyTrue(testCase, L.Measured);
verifyFalse(testCase, L.Light);
verifyEqual(testCase, L.n, 50);
end

function testConstantLightHasNoPulsesToLockTo(testCase)
L = lum.report.pulseLocking(madeUpWithdrawals([0.1 0.2], 1, 0, 0.005), 'Surrogates', 50);
verifyFalse(testCase, L.Measured);
verifySubstring(testCase, L.Reason, 'constant light');
T = madeUpWithdrawals([0.1 0.2], 1, 20, 0.005);
T.S.Light.Carrier(2).Frequency = 10;
L = lum.report.pulseLocking(T, 'Surrogates', 50);
verifyFalse(testCase, L.Measured);
verifySubstring(testCase, L.Reason, 'different carriers');
end


%% Helpers

function T = madeUpWithdrawals(times, optoOn, frequency, pulseWidth)
% The fields of lum.report.sessionTrials that lum.report.pulseLocking reads: one trial per
% early withdrawal, alternating A only and B only, each lit for the whole 0.3 s window.
n = numel(times);
S = lum.defaultSettings;
for c = 1:2
    S.Light.Carrier(c).Frequency = frequency;
    S.Light.Carrier(c).PulseWidth = pulseWidth;
end
stimulusSet = struct('Segments', [1 1 0 0.3; 2 2 0 0.3], 'SegmentStart', [1 2 3]);
T = struct('S', S, 'stimulusSet', stimulusSet, 'optoOn', optoOn * ones(1, n), ...
           'pattern', 2 - mod(1:n, 2), 'attemptTrial', 1:n, 'attemptTime', times, ...
           'attemptCompleted', false(1, n));
end


function result = resultOf(outcome, choice, rewarded)
result = struct('Outcome', outcome, 'Choice', choice, 'Rewarded', rewarded, 'HoldAttempts', 1, ...
                'EarlyWithdrawals', 0, 'HoldCompleted', double(~isnan(choice)));
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
    % Every attempt but a completed last one ends in EarlyWithdrawal; a completed hold goes on
    % to WaitForCentreExit, and one never completed to NoInitiation.
    withdrawals = visits(1:attempts - completed, 2);
    states = struct('CentreHold', visits, 'EarlyWithdrawal', [withdrawals withdrawals], ...
                    'WaitForCentreExit', [NaN NaN], 'NoInitiation', [NaN NaN]);
    if isempty(withdrawals)
        states.EarlyWithdrawal = [NaN NaN];
    end
    if completed
        states.WaitForCentreExit = visits(end, 2) + [0 0.1];
    else
        states.NoInitiation = [3 3];
    end
    Data.RawEvents.Trial{k} = struct('States', states, ...
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
