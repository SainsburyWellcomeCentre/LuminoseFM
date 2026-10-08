function tests = punishmentTest
% punishmentTest exercises the punishment settings: lum.punishmentFor, and old files' conversion.
%
% Each mistake - an incorrect choice, an early withdrawal - has its own punishment and
% timeout, and every combination has to behave. Pure functions - no Bpod.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
S = lum.defaultSettings;
S.GUI.IncorrectChoiceTimeout = 4;
S.GUI.EarlyWithdrawalTimeout = 1.5;
testCase.TestData.S = S;
end

function testNoPunishmentIsTheDefaultAndAWrongChoiceMayBeRetried(testCase)
S = lum.defaultSettings;
verifyEqual(testCase, S.GUI.IncorrectChoicePunishment, 1);
verifyEqual(testCase, S.GUI.EarlyWithdrawalPunishment, 1);
punishment = lum.punishmentFor(S, 'IncorrectChoice');
verifyFalse(testCase, punishment.Applies);
verifyTrue(testCase, punishment.Retry);
verifyFalse(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').Retry, ...
            'An early withdrawal''s retry is the break mode''s');
for kind = 2:4
    S.GUI.IncorrectChoicePunishment = kind;
    verifyFalse(testCase, lum.punishmentFor(S, 'IncorrectChoice').Retry);
end
end

function testNoneMeansNeitherMistakeIsPunished(testCase)
S = testCase.TestData.S;
for event = {'IncorrectChoice', 'EarlyWithdrawal', 'SidePokeBeforeChoice'}
    punishment = lum.punishmentFor(S, event{1});
    verifyFalse(testCase, punishment.Applies);
    verifyEqual(testCase, punishment.Timeout, 0);
    verifyFalse(testCase, punishment.PlayNoise);
    verifyFalse(testCase, punishment.RestartOnSidePoke);
end
end

function testEachMistakeIsPunishedOnItsOwn(testCase)
S = testCase.TestData.S;
S.GUI.EarlyWithdrawalPunishment = 2;
verifyTrue(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').Applies);
verifyFalse(testCase, lum.punishmentFor(S, 'IncorrectChoice').Applies);
S.GUI.EarlyWithdrawalPunishment = 1;
S.GUI.IncorrectChoicePunishment = 2;
verifyTrue(testCase, lum.punishmentFor(S, 'IncorrectChoice').Applies);
verifyFalse(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').Applies);
end

function testEachMistakeHasItsOwnPunishmentAndTimeout(testCase)
S = testCase.TestData.S;
S.GUI.IncorrectChoicePunishment = 2;   % Timeout
S.GUI.EarlyWithdrawalPunishment = 4;   % Timeout + noise
choice = lum.punishmentFor(S, 'IncorrectChoice');
withdrawal = lum.punishmentFor(S, 'EarlyWithdrawal');
verifyEqual(testCase, choice.Timeout, 4);
verifyFalse(testCase, choice.PlayNoise);
verifyEqual(testCase, withdrawal.Timeout, 1.5);
verifyTrue(testCase, withdrawal.PlayNoise);
end

function testASidePokeThatEndsTheTrialCostsWhatAnEarlyWithdrawalDoes(testCase)
S = testCase.TestData.S;
S.GUI.EarlyWithdrawalPunishment = 4;
S.GUI.IncorrectChoicePunishment = 2;
sidePoke = lum.punishmentFor(S, 'SidePokeBeforeChoice');
withdrawal = lum.punishmentFor(S, 'EarlyWithdrawal');
verifyEqual(testCase, sidePoke.Timeout, withdrawal.Timeout);
verifyEqual(testCase, sidePoke.PlayNoise, withdrawal.PlayNoise);
end

function testTimeoutOnlyIsSilent(testCase)
S = testCase.TestData.S;
S.GUI.IncorrectChoicePunishment = 2;
punishment = lum.punishmentFor(S, 'IncorrectChoice');
verifyEqual(testCase, punishment.Timeout, 4);
verifyFalse(testCase, punishment.PlayNoise);
end

function testNoiseOnlyCostsNoTime(testCase)
S = testCase.TestData.S;
S.GUI.IncorrectChoicePunishment = 3;
punishment = lum.punishmentFor(S, 'IncorrectChoice');
verifyEqual(testCase, punishment.Timeout, 0, ...
            'Noise-only punishment must not hold the animal');
verifyTrue(testCase, punishment.PlayNoise);
end

function testBothAppliesTimeoutAndNoise(testCase)
S = testCase.TestData.S;
S.GUI.IncorrectChoicePunishment = 4;
punishment = lum.punishmentFor(S, 'IncorrectChoice');
verifyEqual(testCase, punishment.Timeout, 4);
verifyTrue(testCase, punishment.PlayNoise);
end

function testASidePokeRestartsOnlyATimeoutThatExists(testCase)
S = testCase.TestData.S;
S.GUI.TimeoutSidePoke = 2;   % Restart the timeout
S.GUI.IncorrectChoicePunishment = 2;
S.GUI.EarlyWithdrawalPunishment = 3;   % Noise only: no timeout to restart
verifyTrue(testCase, lum.punishmentFor(S, 'IncorrectChoice').RestartOnSidePoke);
verifyFalse(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').RestartOnSidePoke);
S.GUI.EarlyWithdrawalPunishment = 4;
verifyTrue(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').RestartOnSidePoke);
verifyFalse(testCase, lum.punishmentFor(S, 'SidePokeBeforeChoice').RestartOnSidePoke, ...
            'A side poke that ends the trial has nothing to restart');
S.GUI.IncorrectChoiceTimeout = 0;
verifyFalse(testCase, lum.punishmentFor(S, 'IncorrectChoice').RestartOnSidePoke);
S.GUI.TimeoutSidePoke = 1;
verifyFalse(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').RestartOnSidePoke);
end

function testAnUnknownEventIsRejected(testCase)
verifyError(testCase, @() lum.punishmentFor(testCase.TestData.S, 'Nonsense'), ...
            'lum:punishmentFor:unknownEvent');
end

function testTheGuiExposesEveryOption(testCase)
% The menu items and the codes in lum.punishmentFor have to stay in step: the codes are
% written into every trial record.
S = lum.defaultSettings;
verifyEqual(testCase, S.GUIMeta.IncorrectChoicePunishment.String, ...
            {'None', 'Timeout', 'White noise', 'Timeout + noise'});
verifyEqual(testCase, S.GUIMeta.EarlyWithdrawalPunishment.String, ...
            S.GUIMeta.IncorrectChoicePunishment.String);
verifyEqual(testCase, S.GUIPanels.Punishment, {'IncorrectChoicePunishment', ...
            'IncorrectChoiceTimeout', 'EarlyWithdrawalPunishment', 'EarlyWithdrawalTimeout'});
verifyTrue(testCase, all(ismember({'TimeoutSidePoke', 'SidePokeSound'}, S.GUIPanels.SidePokes)));
end

function testOldSharedPunishmentSettingsAreConverted(testCase)
% 0.10 files: which mistakes (PunishCondition), what (PunishType) and one timeout
defaults = lum.defaultSettings;
cases = {1, 3, [1 1]; 2, 1, [1 2]; 3, 1, [2 1]; 4, 3, [4 4]; 3, 2, [3 1]};
for i = 1:size(cases, 1)
    old = struct('GUI', struct('PunishCondition', cases{i, 1}, 'PunishType', cases{i, 2}, ...
                               'PunishTimeout', 3));
    S = lum.mergeSettings(defaults, old);
    verifyEqual(testCase, [S.GUI.IncorrectChoicePunishment, S.GUI.EarlyWithdrawalPunishment], ...
                cases{i, 3}, sprintf('PunishCondition %d, PunishType %d', cases{i, 1:2}));
    verifyEqual(testCase, [S.GUI.IncorrectChoiceTimeout, S.GUI.EarlyWithdrawalTimeout], [3 3]);
    verifyFalse(testCase, any(isfield(S.GUI, {'PunishCondition', 'PunishType', 'PunishTimeout'})), ...
                'The old settings are retired');
    asRun = lum.mergeSettings(defaults, old, 'AsRun', true);
    verifyEqual(testCase, asRun.GUI.IncorrectChoicePunishment, S.GUI.IncorrectChoicePunishment, ...
                'A data file''s settings are converted too, for the report');
end
end

function testLUMS0014sSettingsKeepTheirPunishment(testCase)
% Incorrect choice punished with a 3 s timeout, early withdrawals not (2026-10-08)
old = struct('GUI', struct('PunishCondition', 3, 'PunishType', 1, 'PunishTimeout', 3));
S = lum.mergeSettings(lum.defaultSettings, old);
choice = lum.punishmentFor(S, 'IncorrectChoice');
verifyEqual(testCase, [choice.Timeout, choice.PlayNoise], [3 0]);
verifyFalse(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').Applies);
end
