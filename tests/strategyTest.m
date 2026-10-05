function tests = strategyTest
% strategyTest checks strategy correction's policies: context correction, its floor, blocks.
%
% Pure parts first: reading a choice from a state, the context codes, the target against a
% brute-force recount, the floor, when a choice is read live. Then the regression: with every
% strategy setting at its default and the swap partner 'first', lum.nextTrialSpec chooses the
% trials 0.9.14 chose (legacyNextTrialSpec), under one rng. Then simulated animals replayed in
% the session's order (trial k+1 prepared before trial k is recorded, the running trial's
% choice noted first when a context needs it): what each habit earns under context
% correction and in blocks, the first trial after a block switch, and the groups delivered.
%
% See also legacyNextTrialSpec, trialSpecTest, lum.BiasCorrection, lum.Blocks
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
S = lum.defaultSettings;
S.Task.MaxSameSide = 0;
S.GUI.BiasCorrection = 0;
S.Session.MaxTrials = 2000;
S.Stimulus.Generator.Seed = 11;
testCase.TestData.S = S;
testCase.TestData.set = lum.pattern.stimulusSet(S, 16, 2);   % Two groups: A pays left, B right
end

%% Reading the choice and the contexts

function testEveryPostChoiceStateIsRead(testCase)
read = @(state, correct) readState(state, correct);
verifyEqual(testCase, read('LeftRewardDelay', 1), [1 1 1]);
verifyEqual(testCase, read('LeftReward', 1), [1 1 1]);
verifyEqual(testCase, read('DrinkingLeft', 1), [1 1 1]);
verifyEqual(testCase, read('RightRewardDelay', 2), [2 1 1]);
verifyEqual(testCase, read('RightReward', 2), [2 1 1]);
verifyEqual(testCase, read('DrinkingRight', 2), [2 1 1]);
verifyEqual(testCase, read('IncorrectChoice', 1), [2 0 1], 'Wrong on a left trial: chose right');
verifyEqual(testCase, read('IncorrectChoice', 2), [1 0 1]);
for state = {'NoResponse', 'NoInitiation', 'SidePokeBeforeChoice'}
    verifyEqual(testCase, read(state{1}, 1), [NaN 0 1], state{1});
end
for state = {'WaitForLightEnd', 'ITI', 'RetryResponse', ''}
    verifyEqual(testCase, read(state{1}, 1), [NaN 0 0], ['Past knowing: ' state{1}]);
end
verifyEqual(testCase, read('DrinkingGrace', 2), [2 1 1], 'Only the paying side leads there');
verifyEqual(testCase, read('WithdrewBeforeReward', 1), [1 0 1]);
[choice, ~, known] = lum.BiasCorrection.choiceFromState('DrinkingGrace', 1, [1 2]);
verifyEqual(testCase, [choice, double(known)], [NaN 0], 'Habituation: either side leads there');
verifyTrue(testCase, all(ismember({'LeftRewardDelay', 'IncorrectChoice', 'ITI'}, ...
                                  lum.BiasCorrection.PostChoiceStates)));
end

function testContextCodesAreTheDataFormats(testCase)
c = @lum.BiasCorrection.contextOf;
verifyEqual(testCase, c(1, [1 2 NaN], [1 0 0]), [1 1 1], 'Side bias: one context');
verifyEqual(testCase, c(2, [1 2 NaN], [1 0 0]), [2 3 0], 'Last choice: left 2, right 3, none 0');
verifyEqual(testCase, c(3, [1 1 2 2 NaN], [1 0 1 0 0]), [4 5 6 7 0], ...
            'Last choice and reward: rewarded left 4, unrewarded left 5, rewarded right 6, unrewarded right 7');
end

function testTheTargetIsTheShareOfLeftChoicesInTheContext(testCase)
% Against a brute-force recount: the last BiasWindow trials whose previous trial had the
% same choice and reward, and a choice of their own.
S = testCase.TestData.S;
S.GUI.BiasCorrection = 0.5;
S.GUI.BiasWindow = 10;
S.GUI.PunishCondition = 3;   % Incorrect choices punished: context correction available
stream = RandStream('mt19937ar', 'Seed', 2);
history = lum.newHistory(200);
for k = 1:120
    choice = 1 + (rand(stream) > 0.3);
    if rand(stream) < 0.1
        choice = NaN;
    end
    history.choice(k) = choice;
    history.rewarded(k) = double(~isnan(choice) && rand(stream) > 0.5);
end
history.nTrials = 120;
for mode = 2:3
    S.GUI.BiasCorrectFor = mode;
    [target, context] = lum.BiasCorrection.target(S, history, 121);
    expectedContext = lum.BiasCorrection.contextOf(mode, history.choice(120), history.rewarded(120));
    verifyEqual(testCase, context, expectedContext);
    matching = [];
    for k = 120:-1:2
        if lum.BiasCorrection.contextOf(mode, history.choice(k - 1), history.rewarded(k - 1)) == context ...
                && ~isnan(history.choice(k))
            matching(end + 1) = history.choice(k); %#ok<AGROW>
        end
        if numel(matching) == 10
            break
        end
    end
    expected = min(max(0.5 + 0.5 * (0.5 - mean(matching == 1)), 0.1), 0.9);
    verifyEqual(testCase, target, expected, 'AbsTol', 1e-12, sprintf('Mode %d', mode));
end
end

function testFewChoicesInAContextFallBackToSideBias(testCase)
S = testCase.TestData.S;
S.GUI.BiasCorrection = 1;
S.GUI.BiasCorrectFor = 2;
S.GUI.PunishCondition = 3;
history = lum.newHistory(20);
history.choice(1:6) = [1 1 1 1 1 2];   % One trial after a right choice: none yet with a choice
history.rewarded(1:6) = 1;
history.nTrials = 6;
[target, context] = lum.BiasCorrection.target(S, history, 7);
verifyEqual(testCase, context, 3, 'After a right choice');
verifyEqual(testCase, target, 0.5 + (0.5 - 5 / 6), 'AbsTol', 1e-12, 'Side bias over all six');
end

function testTheRunningTrialsChoiceGivesTheContext(testCase)
% Trial 7 is prepared while trial 6 runs: its context comes from the choice noted live.
S = testCase.TestData.S;
S.GUI.BiasCorrection = 0.5;
S.GUI.BiasCorrectFor = 3;
S.GUI.PunishCondition = 3;
history = lum.newHistory(20);
history.choice(1:5) = [1 2 1 2 1];
history.rewarded(1:5) = 1;
history.nTrials = 5;
history = lum.BiasCorrection.noteChoice(history, 6, 2, 0);
[~, context] = lum.BiasCorrection.target(S, history, 7);
verifyEqual(testCase, context, 7, 'An unrewarded right choice on the running trial');
[~, context] = lum.BiasCorrection.target(S, history, 8);
verifyEqual(testCase, context, 0, 'Trial 7 not known yet: no context');
end

function testTheRewardFloorEasesTheStrengthToNoneAtTheFloor(testCase)
S = testCase.TestData.S;
S.GUI.BiasRewardWindow = 20;
history = lum.newHistory(40);
history.choice(1:20) = 1;
history.nTrials = 20;
S.GUI.BiasRewardFloor = 40;
shares = [0.3 0.4 0.45 0.5 0.6];
scales = [0 0 0.5 1 1];
for i = 1:numel(shares)
    history.rewarded(1:20) = (1:20) <= round(20 * shares(i));
    verifyEqual(testCase, lum.BiasCorrection.floorScale(S, history), scales(i), 'AbsTol', 1e-12, ...
                sprintf('Rewarded on %.0f%%', 100 * shares(i)));
end
S.GUI.BiasRewardFloor = 0;
verifyEqual(testCase, lum.BiasCorrection.floorScale(S, history), 1, 'No floor, full strength');
S.GUI.BiasRewardFloor = 30;
history.rewarded(1:20) = (1:20) <= 8;   % 40%: half way from 30% to 50%
verifyEqual(testCase, lum.BiasCorrection.floorScale(S, history), 0.5, 'AbsTol', 1e-12);
history.choice(1:10) = NaN;            % Trials without a choice do not count
history.rewarded(1:10) = 0;
history.rewarded(11:20) = (11:20) <= 14;   % 4 of the 10 choices: 40%
verifyEqual(testCase, lum.BiasCorrection.floorScale(S, history), 0.5, 'AbsTol', 1e-12);
end

function testContextCorrectionNeedsAPunishedIncorrectChoice(testCase)
S = testCase.TestData.S;
S.GUI.BiasCorrection = 0.5;
S.GUI.BiasCorrectFor = 3;
for condition = [1 2]   % None, early withdrawal: an incorrect choice is retried
    S.GUI.PunishCondition = condition;
    verifyFalse(testCase, lum.BiasCorrection.isAvailable(S));
    verifyEqual(testCase, lum.BiasCorrection.activeMode(S), 1, 'Side bias instead');
    verifyFalse(testCase, lum.BiasCorrection.readsRunningChoice(S));
end
for condition = [3 4]
    S.GUI.PunishCondition = condition;
    verifyEqual(testCase, lum.BiasCorrection.activeMode(S), 3);
    verifyTrue(testCase, lum.BiasCorrection.readsRunningChoice(S));
end
S.GUI.BiasCorrection = 0;
verifyFalse(testCase, lum.BiasCorrection.readsRunningChoice(S), 'No strength, nothing to wait for');
S.GUI.BiasCorrection = 0.5;
S.GUI.TrialOrder = 2;
verifyFalse(testCase, lum.BiasCorrection.readsRunningChoice(S), 'Blocks set the side without it');
end

function testAnIncorrectChoiceLastsLongEnoughToBeReadLive(testCase)
% At a 0 s timeout a punished incorrect choice lasts ReadableState while choices are read, so
% the trial manager reports it; otherwise it lasts the timeout, as before.
ensureEmulator();
S = testCase.TestData.S;
S.GUI.PunishCondition = 3;
S.GUI.PunishType = 1;
S.GUI.PunishTimeout = 0;
S.GUI.BiasCorrection = 0.5;
S.GUI.BiasCorrectFor = 3;
[~, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, plan.incorrectChoiceTimer, lum.BiasCorrection.ReadableState);
S.GUI.BiasCorrectFor = 1;
[~, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, plan.incorrectChoiceTimer, 0, 'Side bias: the timeout as typed');
S.GUI.BiasCorrectFor = 3;
S.GUI.PunishTimeout = 1;
[~, plan] = lum.buildTrialSM(makeTestContext('Settings', S));
verifyEqual(testCase, plan.incorrectChoiceTimer, 1, 'A longer timeout is kept');
end

function testValidationNotesARetriedContextAndAShortTimeout(testCase)
rig = RigConfig;
S = testCase.TestData.S;
S.Session.MaxTrials = 50;
S.GUI.BiasCorrection = 0.5;
S.GUI.BiasCorrectFor = 2;
S.GUI.PunishCondition = 1;
[~, ~, notes] = lum.validateSettings(S, rig);
verifyTrue(testCase, any(contains(notes, 'needs incorrect choices punished')), strjoin(notes, ' | '));
S.GUI.PunishCondition = 3;
S.GUI.PunishType = 1;
S.GUI.PunishTimeout = 0;
S.GUI.ITI = 0.25;
[~, ~, notes] = lum.validateSettings(S, rig);
verifyTrue(testCase, any(contains(notes, 'prepares each trial after')), strjoin(notes, ' | '));
S.GUI.PunishTimeout = 1;
[~, ~, notes] = lum.validateSettings(S, rig);
verifyFalse(testCase, any(contains(notes, 'prepares each trial after')), 'A 1 s timeout covers it');
S.GUI.BlockMin = 30;
S.GUI.BlockMax = 20;
verifyError(testCase, @() lum.validateSettings(S, rig), 'lum:validateSettings:blockLengths');
end

%% The defaults are 0.9.14's trials

function testTheDefaultsChooseTheTrials0914Chose(testCase)
% Bias correction and the run limit on, as by default, with animals that lean and that do
% not, over a pure set and a probabilistic one: identical specs and queues.
S = testCase.TestData.S;
S.GUI.BiasCorrection = 0.5;
S.Task.MaxSameSide = 3;
sets = {testCase.TestData.set, probabilisticSet(testCase.TestData.set)};
animals = {@(spec, last) 1 + (rand > 0.8), @(spec, last) 1 + (rand > 0.5), @alternator};
for i = 1:numel(sets)
    for j = 1:numel(animals)
        [old, oldQueue] = replay(S, sets{i}, animals{j}, 400, @legacyNextTrialSpec, 5 * i + j);
        [new, newQueue] = replay(S, sets{i}, animals{j}, 400, ...
            @(varargin) lum.nextTrialSpec(varargin{:}, 'SwapPartner', 'first'), 5 * i + j);
        what = sprintf('set %d, animal %d', i, j);
        verifyEqual(testCase, newQueue, oldQueue, what);
        for name = fieldnames(old)'
            verifyEqual(testCase, [new.(name{1})], [old.(name{1})], [what ': ' name{1}]);
        end
        verifyEqual(testCase, unique([new.BiasContext]), 1, 'Side bias, every trial');
        verifyEqual(testCase, unique([new.Block]), 0, 'A random order');
    end
end
end

%% The swap partner

function testARandomPartnerLeavesNoRunOfOneSideBehind(testCase)
% An always-left animal for 300 trials pushes right-paying trials forward; then the
% correction stops. With the first partner the displaced left-paying patterns wait just ahead
% (2026-10-01: 83% left); with a random one the next 100 trials pay about half and half.
S = testCase.TestData.S;
S.GUI.BiasCorrection = 1;
history = lum.newHistory(400);
history.choice(1:20) = 1;
history.nTrials = 20;
paidLeft = zeros(1, 2);
partners = {'first', 'random'};
for p = 1:2
    rng(5);
    queue = testCase.TestData.set.TrialPattern;
    for trial = 21:320
        [~, queue] = lum.nextTrialSpec(S, testCase.TestData.set, queue, history, trial, ...
                                       'SwapPartner', partners{p});
    end
    later = queue(321:420);
    paidLeft(p) = mean(testCase.TestData.set.PatternPLeft(later) == 1);
    verifyEqual(testCase, sort(queue), sort(testCase.TestData.set.TrialPattern), ...
                'Only reordered: every group as often');
end
verifyGreaterThan(testCase, paidLeft(1), 0.8, 'The first partner piles left-paying trials up');
verifyLessThan(testCase, abs(paidLeft(2) - 0.5), 0.15, 'A random partner does not');
end

%% Context correction with simulated animals

function testContextCorrectionMakesAlternatingPayLess(testCase)
S = contextSettings(testCase, 2);
[specs, results] = replay(S, testCase.TestData.set, @alternator, 600, [], 21);
rewarded = mean([results.Rewarded]);
verifyLessThan(testCase, rewarded, 0.33, 'A strict alternator under Last choice, strength 0.5: about 25%');
verifyEqual(testCase, sum(isnan([specs.BiasContext])), 0);
verifyTrue(testCase, all(ismember([specs(2:end).BiasContext], [2 3])), 'After left or right');
end

function testContextCorrectionWithAFloorHoldsTheRewardAboveIt(testCase)
S = contextSettings(testCase, 3);
S.GUI.BiasRewardFloor = 40;
[~, results] = replay(S, testCase.TestData.set, @alternator, 800, [], 22);
rewarded = mean([results(201:end).Rewarded]);
verifyGreaterThan(testCase, rewarded, 0.37, 'Settles a little above the floor');
verifyLessThan(testCase, rewarded, 0.5);
end

function testContextCorrectionMakesWinStayLoseShiftPayLess(testCase)
S = contextSettings(testCase, 3);
[~, results] = replay(S, testCase.TestData.set, @winStayLoseShift, 600, [], 23);
verifyLessThan(testCase, mean([results.Rewarded]), 0.4);
S.GUI.BiasCorrectFor = 2;   % Last choice alone cannot see it
[~, results] = replay(S, testCase.TestData.set, @winStayLoseShift, 600, [], 23);
verifyGreaterThan(testCase, mean([results.Rewarded]), 0.42);
end

function testAnAnimalThatFollowsTheStimulusLosesNothing(testCase)
S = contextSettings(testCase, 3);
S.GUI.BiasRewardFloor = 40;
[specs, results] = replay(S, testCase.TestData.set, @follower, 400, [], 24);
verifyEqual(testCase, mean([results.Rewarded]), 1);
verifyEqual(testCase, [specs.CorrectSide], 2 - testCase.TestData.set.PatternPLeft([specs.PatternIndex]), ...
            'Every group still pays its side');
end

function testABiasedAnimalIsCorrectedInEveryContext(testCase)
S = contextSettings(testCase, 2);
[specs, ~] = replay(S, testCase.TestData.set, @(spec, last) 1 + (rand > 0.9), 600, [], 25);
verifyGreaterThan(testCase, mean([specs(101:end).CorrectSide] == 2), 0.65, ...
                  'Mostly right-paying trials for an animal going left');
end

%% Blocks

function testBlocksAlternateSidesWithinTheirLengths(testCase)
S = blockSettings(testCase);
[specs, ~] = replay(S, testCase.TestData.set, @(spec, last) 1 + (rand > 0.5), 600, [], 31);
blocks = [specs.Block];
verifyTrue(testCase, all(blocks > 0));
verifyEqual(testCase, [specs.CorrectSide], [specs.BlockSide], 'A pure set pays the block''s side');
[first, ~] = lum.Blocks.firstTrials(blocks);
starts = [find(first), numel(blocks) + 1];
lengths = diff(starts);
verifyGreaterThanOrEqual(testCase, min(lengths(1:end - 1)), 15);
verifyLessThanOrEqual(testCase, max(lengths), 25);
sides = [specs(starts(1:end - 1)).BlockSide];
verifyTrue(testCase, all(diff(sides) ~= 0), 'Each block takes the other side');
verifyEqual(testCase, [specs.BiasTargetPLeft], double([specs.BlockSide] == 1));
verifyTrue(testCase, all(isnan([specs.BiasContext])), 'Bias correction does not act');
end

function testBlocksPayWinStayAndTestTheFirstTrialAfterASwitch(testCase)
S = blockSettings(testCase);
set = testCase.TestData.set;
animals = {@winStayLoseShift, @alternator, @follower};
earns = [0.9 1; 0.4 0.6; 1 1];
firstCorrect = [0 0.1; 0.3 0.7; 1 1];
for i = 1:numel(animals)
    [specs, results] = replay(S, set, animals{i}, 600, [], 40 + i);
    verifyGreaterThanOrEqual(testCase, mean([results.Rewarded]), earns(i, 1), func2str(animals{i}));
    verifyLessThanOrEqual(testCase, mean([results.Rewarded]), earns(i, 2), func2str(animals{i}));
    [first, ~] = lum.Blocks.firstTrials([specs.Block]);
    switches = find(first);
    switches = switches(2:end);
    correct = mean([results(switches).Correct]);
    verifyGreaterThanOrEqual(testCase, correct, firstCorrect(i, 1), func2str(animals{i}));
    verifyLessThanOrEqual(testCase, correct, firstCorrect(i, 2), func2str(animals{i}));
end
end

function testBlocksDeliverEveryGroupAsOftenOverTheOrder(testCase)
S = blockSettings(testCase);
set = testCase.TestData.set;
[~, ~, queue] = replay(S, set, @(spec, last) 1 + (rand > 0.5), 600, [], 51);
verifyEqual(testCase, sort(queue), sort(set.TrialPattern));
end

function testABlockSwitchesAfterCorrectInARowOneTrialLate(testCase)
% With Switch after correct in a row 3 and a follower, a block of at least 5 ends once 3
% recorded choices in it are correct: the trial already prepared stays in it.
S = blockSettings(testCase);
S.GUI.BlockMin = 5;
S.GUI.BlockMax = 25;
S.GUI.BlockSwitchAfterCorrect = 3;
[specs, ~] = replay(S, testCase.TestData.set, @follower, 200, [], 61);
[first, ~] = lum.Blocks.firstTrials([specs.Block]);
lengths = diff(find(first));
verifyEqual(testCase, unique(lengths), 5, 'Five trials: at its shortest the run is long enough');
S.GUI.BlockMin = 1;
[specs, ~] = replay(S, testCase.TestData.set, @follower, 200, [], 62);
[first, ~] = lum.Blocks.firstTrials([specs.Block]);
verifyEqual(testCase, unique(diff(find(first))), 4, ...
            'Three correct recorded, and the fourth trial already prepared');
[specs, ~] = replay(S, testCase.TestData.set, @alternator, 200, [], 63);
[first, ~] = lum.Blocks.firstTrials([specs.Block]);
lengths = diff(find(first));
verifyEqual(testCase, unique(lengths), 25, 'An alternator never gets three in a row');
end

function testBlocksUsePatternsThatLeanToTheirSide(testCase)
verifyEqual(testCase, lum.Blocks.canUse([1 0.8 0.5 0.2 0], 1), logical([1 1 1 0 0]));
verifyEqual(testCase, lum.Blocks.canUse([1 0.8 0.5 0.2 0], 2), logical([0 0 1 1 1]));
S = blockSettings(testCase);
set = probabilisticSet(testCase.TestData.set);   % 0.8 and 0.2
[specs, ~] = replay(S, set, @(spec, last) 1 + (rand > 0.5), 600, [], 71);
pLeft = set.PatternPLeft([specs.PatternIndex]);
verifyTrue(testCase, all(pLeft([specs.BlockSide] == 1) > 0.5));
verifyTrue(testCase, all(pLeft([specs.BlockSide] == 2) < 0.5));
paysBlock = mean([specs.CorrectSide] == [specs.BlockSide]);
verifyEqual(testCase, paysBlock, 0.8, 'AbsTol', 0.05, 'The side still drawn from P(left)');
end

function testABlockEndsWhenTheOrderCannotServeIt(testCase)
S = blockSettings(testCase);
set = testCase.TestData.set;
history = lum.newHistory(10);
queue = set.TrialPattern;
leftPatterns = find(set.PatternPLeft == 1);
queue(:) = leftPatterns(1);   % Nothing left can pay right
history.preparedBlock = 1;
history.preparedTrial = 4;
history.blockIndex = 1;
history.blockSide = 2;
history.blockStart = 1;
history.blockLength = 20;
block = lum.Blocks.next(S, history, 5, queue, set.PatternPLeft);
verifyEqual(testCase, [block.Block, block.Side, block.Start], [2 1 5], 'A left block at once');
end

function testBlocksStartAndStopMidSession(testCase)
S = blockSettings(testCase);
S.GUI.TrialOrder = 1;
set = testCase.TestData.set;
history = lum.newHistory(400);
queue = set.TrialPattern;
blocks = zeros(1, 120);
rng(81);
for trial = 1:120
    if trial == 41
        S.GUI.TrialOrder = 2;   % Blocks from trial 41
    elseif trial == 91
        S.GUI.TrialOrder = 1;   % Random again
    end
    [spec, queue] = lum.nextTrialSpec(S, set, queue, history, trial);
    history = lum.HoldShaping.notePrepared(history, spec);
    history = lum.Blocks.notePrepared(history, spec);
    blocks(trial) = spec.Block;
end
verifyTrue(testCase, all(blocks(1:40) == 0));
verifyEqual(testCase, blocks(41), 1, 'A block starts at once');
verifyTrue(testCase, all(blocks(41:90) > 0));
verifyTrue(testCase, all(blocks(91:end) == 0));
end


%% Helpers ----------------------------------------------------------------------

function out = readState(state, correctSide)
[choice, rewarded, known] = lum.BiasCorrection.choiceFromState(state, correctSide);
out = [choice, rewarded, double(known)];
end

function S = contextSettings(testCase, mode)
S = testCase.TestData.S;
S.GUI.BiasCorrection = 0.5;
S.GUI.BiasCorrectFor = mode;
S.GUI.PunishCondition = 3;   % Incorrect choices punished
end

function S = blockSettings(testCase)
S = testCase.TestData.S;
S.GUI.BiasCorrection = 0.5;
S.Task.MaxSameSide = 3;
S.GUI.TrialOrder = 2;
end

function set = probabilisticSet(set)
% The same order, its groups paying their side with chance 0.8 rather than always.
set.PatternPLeft(set.PatternPLeft == 1) = 0.8;
set.PatternPLeft(set.PatternPLeft == 0) = 0.2;
end

function choice = alternator(~, last)
% The other side from its last choice.
choice = 3 - last.choice;
end

function choice = winStayLoseShift(~, last)
% Stays after a reward, moves after none.
choice = last.choice;
if ~last.rewarded
    choice = 3 - last.choice;
end
end

function choice = follower(spec, ~)
% Reads the stimulus: chooses the side its group pays.
choice = spec.CorrectSide;
end

function [specs, results, queue] = replay(S, set, animal, n, policy, seed)
% A session in the loop's order: trial k+1 prepared while k runs (after k's choice, noted,
% when a context needs it), k recorded after. animal(spec, last) chooses, last holding its
% previous choice and reward.
if isempty(policy)
    policy = @lum.nextTrialSpec;
end
rng(seed);
history = lum.newHistory(n);
queue = set.TrialPattern;
[running, queue] = policy(S, set, queue, history, 1);
history = lum.HoldShaping.notePrepared(history, running);
history = lum.Blocks.notePrepared(history, running);
last = struct('choice', 1, 'rewarded', true);
specs = repmat(running, 1, n);
results = repmat(resultOf(1, 1), 1, n);
for k = 1:n
    choice = animal(running, last);
    rewarded = choice == running.CorrectSide;
    if k < n
        if lum.BiasCorrection.readsRunningChoice(S)
            history = lum.BiasCorrection.noteChoice(history, k, choice, double(rewarded));
        end
        [next, queue] = policy(S, set, queue, history, k + 1);
        history = lum.HoldShaping.notePrepared(history, next);
        history = lum.Blocks.notePrepared(history, next);
    end
    result = resultOf(choice, running.CorrectSide);
    history = lum.updateHistory(history, k, running, result);
    specs(k) = running;
    results(k) = result;
    last = struct('choice', choice, 'rewarded', rewarded);
    if k < n
        running = next;
    end
end
end

function result = resultOf(choice, correctSide)
% What lum.scoreTrial returns for a choice, every hold completed.
correct = double(choice == correctSide);
outcome = lum.Outcome.Incorrect;
if correct
    outcome = lum.Outcome.Correct;
end
result = struct('Choice', choice, 'Correct', correct, 'Rewarded', correct, 'ReactionTime', 0.3, ...
                'Outcome', outcome, 'HoldBreaks', 0, 'HoldAttempts', 1, 'EarlyWithdrawals', 0, ...
                'CentreRewarded', 0, 'ResponseRetries', 0, 'CentreHoldTime', 1, 'SidePokeDelays', 0);
end
