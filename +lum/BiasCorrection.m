classdef BiasCorrection
    % lum.BiasCorrection sets the P(left) bias correction aims for, by context.
    %
    % Bias correction (S.GUI.BiasCorrection, strength s) pushes the trial order against the
    % animal's lean: with a share f of left choices, the next trial pays left with chance
    % 0.5 + s x (0.5 - f), within 0.1-0.9, and lum.nextTrialSpec brings forward a trial that
    % pays the side drawn. Context correction (D23) reads f from the animal's choices in the
    % same context as the trial being prepared, set by S.GUI.BiasCorrectFor:
    %
    %   Side bias               one context for every trial: f over its last BiasWindow
    %                           choices, as before 0.10.0 (context code 1)
    %   Last choice             after a left choice (2), after a right one (3): against
    %                           alternating, staying on one side and side bias
    %   Last choice and reward  after a rewarded left (4), unrewarded left (5), rewarded
    %                           right (6), unrewarded right (7): against win-stay and
    %                           lose-shift too
    %
    % A trial's context comes from the trial before it; code 0 is none (the first trial, no
    % choice on the trial before, or its choice not read in time), and such a trial, or one
    % whose context has fewer than 3 choices in the window, is corrected for side bias. The
    % contingency never changes, groups stay balanced, and an animal that follows the
    % stimulus is rewarded on every correct choice: only a habit pays less, by 2 s d^2 for a
    % lean d = f - 0.5 (docs/architecture.md, D23).
    %
    % The reward floor (S.GUI.BiasRewardFloor, F) keeps the correction from taking the
    % animal's reward too low: with r the share of its last BiasRewardWindow choices that
    % were rewarded, the strength used is s x min(1, max(0, (r - F) / (0.5 - F))), full at
    % 50% (what a habit earns uncorrected) and none at F or below. A habit then settles a
    % little above F. It applies to every context, side bias included.
    %
    % The trial running while the next is prepared is the trial before it, so a context
    % from it needs that trial's choice: with Last choice or Last choice and reward the
    % session prepares the next trial after the running one's choice (readsRunningChoice,
    % lum.SessionRunner.awaitChoice), reading it from the state it reached
    % (choiceFromState). A retried incorrect choice cannot be read that way (RetryResponse
    % lasts no time), so context correction needs incorrect choices punished: while they
    % are retried, the setting is greyed out and side bias is used (activeMode). For the same
    % reason a punished incorrect choice lasts at least ReadableState while choices are read
    % (lum.buildTrialSM), whatever the timeout.
    %
    % The codes are stored per trial (Data.BiasContext) and are part of the data format:
    % append, never renumber. NaN there means bias correction did not act on the trial
    % (strength 0, or the trial order in blocks).
    %
    % Static methods; nothing to construct. Pure: no hardware, no globals.
    %
    % See also lum.nextTrialSpec, lum.Blocks, lum.SessionRunner, lum.punishmentFor

    properties (Constant)
        % S.GUI.BiasCorrectFor's items, in code order
        Modes = {'Side bias', 'Last choice', 'Last choice and reward'}
        % States that tell the running trial's choice, or that it is past knowing
        % (choiceFromState); the session waits for one before preparing the next trial
        PostChoiceStates = {'LeftRewardDelay', 'LeftReward', 'DrinkingLeft', ...
                            'RightRewardDelay', 'RightReward', 'DrinkingRight', ...
                            'IncorrectChoice', 'IncorrectChoiceRestartLeft', ...
                            'IncorrectChoiceRestartRight', 'NoResponse', 'NoInitiation', ...
                            'SidePokeBeforeChoice', 'RetryResponse', 'DrinkingGrace', ...
                            'WithdrewBeforeReward', 'WaitForLightEnd', 'ITI'}
        % Fewer choices than this in a context, and the trial is corrected for side bias
        MinimumChoices = 3
        % Seconds IncorrectChoice lasts at least while choices are read live: the trial manager
        % reports the state once per batch of events (about 10 ms), and a 0 s timeout passed
        % unseen on the rig (2026-10-05: 12 of 30 contexts read as none)
        ReadableState = 0.05
        % The target is kept within this range, so both sides always pay
        TargetLimits = [0.1 0.9]
    end

    methods (Static)
        function mode = activeMode(S)
            % activeMode(S) is the Correct for in force: S.GUI.BiasCorrectFor, or 1 (Side
            % bias) while incorrect choices are retried (isAvailable) or in settings from
            % before 0.10.0.
            mode = 1;
            if isfield(S.GUI, 'BiasCorrectFor') && lum.BiasCorrection.isAvailable(S)
                mode = S.GUI.BiasCorrectFor;
            end
        end

        function tf = isAvailable(S)
            % isAvailable(S) is true when context correction can be used: incorrect choices
            % are punished, so the first choice is the trial's only one.
            tf = ~lum.punishmentFor(S, 'IncorrectChoice').Retry;
        end

        function tf = readsRunningChoice(S)
            % readsRunningChoice(S) is true when the next trial must wait for the running
            % trial's choice before it is prepared: a context mode, a strength above 0, and
            % a random trial order (blocks set the side without it).
            tf = S.GUI.BiasCorrection > 0 && lum.BiasCorrection.activeMode(S) > 1 ...
                 && ~lum.Blocks.isOn(S);
        end

        function context = contextOf(mode, choice, rewarded)
            % contextOf(mode, choice, rewarded) is the context code of a trial whose previous
            % trial made this choice (1, 2 or NaN) and was rewarded (1) or not; vectorised.
            choice = double(choice);
            rewarded = double(rewarded) == 1;
            switch mode
                case 1
                    context = ones(size(choice));
                case 2
                    context = 2 * (choice == 1) + 3 * (choice == 2);
                case 3
                    context = (choice == 1) .* (5 - rewarded) + (choice == 2) .* (7 - rewarded);
                otherwise
                    error('lum:BiasCorrection:badMode', ...
                          'Correct for is %g; it must be 1 to %d.', mode, ...
                          numel(lum.BiasCorrection.Modes));
            end
        end

        function [pLeftTarget, context, strength] = target(S, history, trialNumber)
            % target(S, history, trialNumber) is the P(left) to aim for on that trial, its
            % context code and the strength used (after the reward floor).
            %
            % history holds the recorded trials (lum.newHistory); the trial before trialNumber
            % may still be running, its choice noted by noteChoice.
            mode = lum.BiasCorrection.activeMode(S);
            [previousChoice, previousRewarded] = previousTrial(history, trialNumber);
            context = 1;
            if mode > 1
                context = lum.BiasCorrection.contextOf(mode, previousChoice, previousRewarded);
            end
            strength = S.GUI.BiasCorrection * lum.BiasCorrection.floorScale(S, history);
            pLeftTarget = 0.5;
            if strength <= 0
                return
            end
            n = history.nTrials;
            choices = history.choice(1:n);
            recent = [];
            if context > 1 && n > 1
                contexts = lum.BiasCorrection.contextOf(mode, [NaN choices(1:n - 1)], ...
                                                       [NaN history.rewarded(1:n - 1)]);
                recent = choices(find(contexts == context & ~isnan(choices), ...
                                      floor(S.GUI.BiasWindow), 'last'));
            end
            if numel(recent) < lum.BiasCorrection.MinimumChoices
                % Side bias: the last BiasWindow choices whatever their context
                recent = recentChoices(history, S.GUI.BiasWindow);
            end
            if numel(recent) >= lum.BiasCorrection.MinimumChoices
                fractionLeft = mean(recent == 1);
                % A strength of 1 fully compensates: an animal choosing left on every
                % recent trial gets p(left) pushed down, and vice versa.
                pLeftTarget = 0.5 + strength * (0.5 - fractionLeft);
                limits = lum.BiasCorrection.TargetLimits;
                pLeftTarget = min(max(pLeftTarget, limits(1)), limits(2));
            end
        end

        function scale = floorScale(S, history)
            % floorScale(S, history) is what the reward floor leaves of the strength, 0 to 1:
            % 1 without a floor or before any choice.
            scale = 1;
            if ~isfield(S.GUI, 'BiasRewardFloor') || ~(S.GUI.BiasRewardFloor > 0)
                return
            end
            n = history.nTrials;
            chose = find(~isnan(history.choice(1:n)), floor(S.GUI.BiasRewardWindow), 'last');
            if isempty(chose)
                return
            end
            share = mean(history.rewarded(chose) == 1);
            floorShare = S.GUI.BiasRewardFloor / 100;
            scale = min(1, max(0, (share - floorShare) / max(0.5 - floorShare, 1e-9)));
        end

        function [choice, rewarded, known] = choiceFromState(state, correctSide, rewardedSides)
            % choiceFromState(state, correctSide, rewardedSides) reads a running trial's choice
            % from a state it reached: choice 1, 2 or NaN (none), rewarded 1 or 0, and known
            % false when the state is past the choice and says nothing of it (the ITI, a
            % retry...), which gives the next trial no context. With one rewarded side
            % (rewardedSides, default correctSide), DrinkingGrace says that side was chosen and
            % rewarded and WithdrewBeforeReward that it was chosen and not rewarded, in case
            % the short states before them passed unseen; in habituation they say nothing.
            if nargin < 3
                rewardedSides = correctSide;
            end
            choice = NaN;
            rewarded = 0;
            known = true;
            if isscalar(rewardedSides) && any(strcmp(state, {'DrinkingGrace', 'WithdrewBeforeReward'}))
                choice = rewardedSides;
                rewarded = double(strcmp(state, 'DrinkingGrace'));
                return
            end
            switch state
                case {'LeftRewardDelay', 'LeftReward', 'DrinkingLeft'}
                    choice = 1;
                    rewarded = 1;
                case {'RightRewardDelay', 'RightReward', 'DrinkingRight'}
                    choice = 2;
                    rewarded = 1;
                case {'IncorrectChoice', 'IncorrectChoiceRestartLeft', ...
                      'IncorrectChoiceRestartRight'}
                    choice = 3 - correctSide;
                case {'NoResponse', 'NoInitiation', 'SidePokeBeforeChoice'}
                    % No choice
                otherwise
                    known = false;
            end
        end

        function history = noteChoice(history, trialNumber, choice, rewarded)
            % noteChoice(history, trial, choice, rewarded) notes the running trial's choice,
            % read live (choiceFromState), for the next trial's context. Call it before
            % lum.nextTrialSpec.
            history.runningTrial = trialNumber;
            history.runningChoice = choice;
            history.runningRewarded = rewarded;
        end

        function text = describe(S)
            % describe(S) says in one line what bias correction does in this session.
            if S.GUI.BiasCorrection <= 0
                text = 'bias correction off';
                return
            end
            requested = 1;
            if isfield(S.GUI, 'BiasCorrectFor')
                requested = S.GUI.BiasCorrectFor;
            end
            mode = lum.BiasCorrection.activeMode(S);
            text = sprintf('bias correction %g, for %s, over the last %d choices', ...
                           S.GUI.BiasCorrection, lower(lum.BiasCorrection.Modes{mode}), ...
                           round(S.GUI.BiasWindow));
            if mode == 1 && requested > 1
                text = sprintf('%s (%s asked for, but incorrect choices are retried)', text, ...
                               lower(lum.BiasCorrection.Modes{requested}));
            elseif mode > 1
                text = sprintf('%s in each context', text);
            end
            if isfield(S.GUI, 'BiasRewardFloor') && S.GUI.BiasRewardFloor > 0
                text = sprintf('%s, reward floor %g%% over %d choices', text, ...
                               S.GUI.BiasRewardFloor, round(S.GUI.BiasRewardWindow));
            end
        end

        function note = timingNote(S)
            % timingNote(S) warns when a context mode leaves little time to prepare the next
            % trial after a choice: below 0.75 s of timeout and ITI after an incorrect one,
            % a slow preparation (up to 0.55 s on the rig) starts the next trial late. ''
            % when there is nothing to say.
            note = '';
            if ~lum.BiasCorrection.readsRunningChoice(S)
                return
            end
            after = lum.punishmentFor(S, 'IncorrectChoice').Timeout + S.GUI.ITI;
            if after < 0.75
                note = sprintf(['Bias correction for %s prepares each trial after the running '...
                                'one''s choice: with %g s of timeout and ITI after an incorrect '...
                                'choice, a slow preparation starts the next trial late, with '...
                                'Bpod''s dead time warning. 0.75 s or more covers it.'], ...
                               lower(lum.BiasCorrection.Modes{lum.BiasCorrection.activeMode(S)}), ...
                               after);
            end
        end
    end
end


function [choice, rewarded] = previousTrial(history, trialNumber)
% The choice and reward of the trial before trialNumber: the running one's, noted live, or the
% recorded one's; NaN and 0 when neither is known.
choice = NaN;
rewarded = 0;
previous = trialNumber - 1;
if previous < 1
    return
end
if isfield(history, 'runningTrial') && history.runningTrial == previous
    choice = history.runningChoice;
    rewarded = history.runningRewarded;
elseif history.nTrials >= previous
    choice = history.choice(previous);
    rewarded = history.rewarded(previous);
end
end


function recent = recentChoices(history, window)
% The animal's last `window` choices, skipping trials with no choice.
recent = [];
if history.nTrials == 0 || window < 1
    return
end
choices = history.choice(1:history.nTrials);
recent = choices(find(~isnan(choices), floor(window), 'last'));
end
