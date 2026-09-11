function tests = punishmentTest
% punishmentTest exercises the punishment settings: lum.punishmentFor.
%
% Which mistakes are punished and what the punishment is are two separate
% runtime choices, and every combination has to behave. Pure function — no Bpod.
tests = functiontests(localfunctions);
end

function setupOnce(testCase)
testCase.TestData.S = lum.defaultSettings;
testCase.TestData.S.GUI.PunishTimeout = 4;
end

function testNoneMeansNeitherMistakeIsPunished(testCase)
S = testCase.TestData.S;
S.GUI.PunishCondition = 1;
for event = {'IncorrectChoice', 'EarlyWithdrawal'}
    punishment = lum.punishmentFor(S, event{1});
    verifyFalse(testCase, punishment.Applies);
    verifyEqual(testCase, punishment.Timeout, 0);
    verifyFalse(testCase, punishment.PlayNoise);
end
end

function testEarlyWithdrawalOnlyLeavesChoicesUnpunished(testCase)
S = testCase.TestData.S;
S.GUI.PunishCondition = 2;
verifyTrue(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').Applies);
verifyFalse(testCase, lum.punishmentFor(S, 'IncorrectChoice').Applies);
end

function testIncorrectChoiceOnlyLeavesWithdrawalsUnpunished(testCase)
S = testCase.TestData.S;
S.GUI.PunishCondition = 3;
verifyTrue(testCase, lum.punishmentFor(S, 'IncorrectChoice').Applies);
verifyFalse(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').Applies);
end

function testBothPunishesEitherMistake(testCase)
S = testCase.TestData.S;
S.GUI.PunishCondition = 4;
verifyTrue(testCase, lum.punishmentFor(S, 'IncorrectChoice').Applies);
verifyTrue(testCase, lum.punishmentFor(S, 'EarlyWithdrawal').Applies);
end

function testTimeoutOnlyIsSilent(testCase)
S = testCase.TestData.S;
S.GUI.PunishCondition = 4;
S.GUI.PunishType = 1;
punishment = lum.punishmentFor(S, 'IncorrectChoice');
verifyEqual(testCase, punishment.Timeout, 4);
verifyFalse(testCase, punishment.PlayNoise);
end

function testNoiseOnlyCostsNoTime(testCase)
S = testCase.TestData.S;
S.GUI.PunishCondition = 4;
S.GUI.PunishType = 2;
punishment = lum.punishmentFor(S, 'IncorrectChoice');
verifyEqual(testCase, punishment.Timeout, 0, ...
            'Noise-only punishment must not hold the animal');
verifyTrue(testCase, punishment.PlayNoise);
end

function testBothAppliesTimeoutAndNoise(testCase)
S = testCase.TestData.S;
S.GUI.PunishCondition = 4;
S.GUI.PunishType = 3;
punishment = lum.punishmentFor(S, 'IncorrectChoice');
verifyEqual(testCase, punishment.Timeout, 4);
verifyTrue(testCase, punishment.PlayNoise);
end

function testTheTypeIsIgnoredWhenTheEventIsNotPunished(testCase)
S = testCase.TestData.S;
S.GUI.PunishCondition = 3;   % Incorrect choice only
S.GUI.PunishType = 3;        % Timeout and noise
punishment = lum.punishmentFor(S, 'EarlyWithdrawal');
verifyEqual(testCase, punishment.Timeout, 0);
verifyFalse(testCase, punishment.PlayNoise);
end

function testAnUnknownEventIsRejected(testCase)
verifyError(testCase, @() lum.punishmentFor(testCase.TestData.S, 'Nonsense'), ...
            'lum:punishmentFor:unknownEvent');
end

function testTheGuiExposesEveryOption(testCase)
% The popupmenu strings and the codes in lum.punishmentFor have to stay in step:
% the codes are written into every trial record.
S = lum.defaultSettings;
verifyLength(testCase, S.GUIMeta.PunishCondition.String, 4);
verifyLength(testCase, S.GUIMeta.PunishType.String, 3);
verifyTrue(testCase, ismember('PunishCondition', S.GUIPanels.Punishment));
verifyTrue(testCase, ismember('PunishType', S.GUIPanels.Punishment));
verifyTrue(testCase, ismember('PunishTimeout', S.GUIPanels.Punishment));
end
