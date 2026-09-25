classdef HoldShaping
    % lum.HoldShaping trains the centre-port hold up to its full length.
    %
    % A naive animal cannot hold its nose in the centre port for a whole stimulus.
    % Automatic shaping (S.Task.AutoShaping) brings it there, following the animal's
    % performance. It is switched off by default, switched on by choosing the Habituation
    % or Training stage and off by choosing Experiment (lum.stageDefaults), and an Experiment session
    % never runs with it (lum.validateSettings). While it is on, S.Task.HoldShaping says
    % how the hold is shaped, tuned during the session from the runtime window:
    %
    %   Grow hold     (default) The hold starts at S.GUI.HoldStart and grows by
    %                 S.GUI.HoldGrowth percent after every trial on which the
    %                 animal completed it, until it reaches S.GUI.HoldTarget —
    %                 normally the stimulus window plus the post-stimulus hold.
    %                 Light is cut off where a shaped hold ends. When the animal
    %                 withdraws early S.GUI.HoldStepBackAfter times without completing
    %                 a hold at that length, the hold steps back one growth step, so
    %                 the animal can go on learning (0 never steps back).
    %
    %   Shrink grace  The animal may leave the centre port during the hold and
    %                 come back within a grace period without the trial counting
    %                 as an early withdrawal; the hold clock keeps running while it
    %                 is out, and the stimulus carries on. The grace starts at
    %                 S.GUI.GraceStart and shrinks by S.GUI.GraceShrink percent
    %                 after every completed hold, down to S.GUI.GraceTarget
    %                 (normally 0, an unbroken hold).
    %
    %   Both          The two together.
    %
    % With automatic shaping off the animal holds for the whole stimulus window on every
    % trial, whatever S.Task.HoldShaping says; activeMode(S) is 'Off'. Every decision about
    % the hold goes through activeMode, never S.Task.HoldShaping directly.
    %
    % What a break that is not forgiven does is a separate choice, S.Task.OnHoldBreak:
    %
    %   Restart stimulus  (default) The stimulus stops, and the animal has to poke
    %                     again; the next poke starts the stimulus from its beginning.
    %                     The trial goes on until a hold is completed or the hold
    %                     window (S.GUI.HoldWindow, from trial start) runs out.
    %   End trial         The break is an early withdrawal and the trial ends.
    %
    % Neither changes the state graph: the states that shaping uses exist in every
    % trial and are simply unreachable when it is off (lum.buildTrialSM). Grace
    % needs a global timer as the hold clock, because a state timer restarts each
    % time the animal comes back; that timer comes out of the budget the light
    % patterns share (lum.timerBudget).
    %
    % A trial is prepared while the one before it is still running, so the values
    % for trial n+1 follow the outcome of trial n-1, and are taken from trial n's hold
    % and grace (the trial still running, which the session notes with notePrepared):
    % every completed hold is one growth step, one trial late. Before 0.9.4 they were
    % taken from trial n-1's, so odd and even trials shaped apart: the hold grew every
    % second trial, and an animal completing every other hold kept one of the two at its
    % start. Trials without a centre poke do not change the shaping; early withdrawals
    % hold it where it is until there have been S.GUI.HoldStepBackAfter of them at that
    % hold (history.withdrawalsAtHold, lum.updateHistory). The hold steps back only while
    % the trial still running has the hold those withdrawals were made at, so it never
    % steps back twice for the same withdrawals.
    %
    % Later, automatic shaping will also choose easier or harder trial types; that
    % belongs under the same switch.
    %
    % See also: lum.nextTrialSpec, lum.buildTrialSM, lum.timerBudget, lum.stageDefaults

    methods (Static)
        function names = modes()
            % modes() lists the choices for S.Task.HoldShaping. The first is the default.
            names = {'Grow hold', 'Shrink grace', 'Both'};
        end

        function mode = activeMode(S)
            % activeMode(S) is the hold shaping in force: S.Task.HoldShaping while
            % automatic shaping is on, 'Off' otherwise.
            if isfield(S.Task, 'AutoShaping') && isscalar(S.Task.AutoShaping) ...
                    && logical(S.Task.AutoShaping)
                mode = S.Task.HoldShaping;
            else
                mode = 'Off';
            end
        end

        function tf = growsHold(S)
            % growsHold(S) is true when the hold length is shaped. S may be a settings
            % struct or a mode name.
            tf = any(strcmp(lum.HoldShaping.modeOf(S), {'Grow hold', 'Both'}));
        end

        function tf = hasGrace(S)
            % hasGrace(S) is true when breaks in the hold are forgiven. S may be a
            % settings struct or a mode name.
            tf = any(strcmp(lum.HoldShaping.modeOf(S), {'Shrink grace', 'Both'}));
        end

        function names = breakModes()
            % breakModes() lists the choices for S.Task.OnHoldBreak. The first is the
            % default.
            names = {'Restart stimulus', 'End trial'};
        end

        function tf = restartsOnBreak(S)
            % restartsOnBreak(S) is true when a broken hold restarts the stimulus on
            % the next poke rather than ending the trial.
            tf = strcmp(S.Task.OnHoldBreak, 'Restart stimulus');
        end

        function text = describeBreak(S)
            % describeBreak(S) says in one line what a broken hold does.
            if lum.HoldShaping.restartsOnBreak(S)
                text = sprintf(['Leaving the centre port early stops the stimulus; the next '...
                                'poke restarts it. The trial lapses if no hold is completed '...
                                'within %g s of trial start.'], S.GUI.HoldWindow);
            else
                text = sprintf(['Leaving the centre port early ends the trial as an early '...
                                'withdrawal. The animal has %g s from trial start to start '...
                                'the stimulus.'], S.GUI.HoldWindow);
            end
        end

        function [holdDuration, grace, steppedBack] = next(S, history)
            % next(S, history) is the hold and grace for the next trial, in seconds, and
            % whether the hold stepped back after too many early withdrawals.
            %
            % Without hold growth the hold is the whole stimulus window plus the
            % post-stimulus hold; without grace, the grace is 0.
            [lastHold, ~, completed] = lum.HoldShaping.lastTrial(history);
            [baseHold, baseGrace] = lum.HoldShaping.running(history);
            steppedBack = false;

            if lum.HoldShaping.growsHold(S)
                start = S.GUI.HoldStart;
                target = S.GUI.HoldTarget;
                growth = 1 + S.GUI.HoldGrowth / 100;
                % The withdrawals counted were made at the last recorded trial's hold;
                % they step back only the hold still in force.
                sameHold = abs(lastHold - baseHold) < 5e-5;
                if isnan(baseHold)
                    holdDuration = start;
                elseif completed
                    holdDuration = baseHold * growth;
                elseif sameHold && lum.HoldShaping.stepBackDue(S, history)
                    % One growth step back: the hold the animal last managed.
                    holdDuration = baseHold / growth;
                    steppedBack = true;
                else
                    holdDuration = baseHold;
                end
                floorHold = min(start, target);
                steppedBack = steppedBack && baseHold > floorHold;
                holdDuration = min(max(holdDuration, floorHold), target);
            else
                holdDuration = S.Stimulus.Duration + S.GUI.PostStimulusHold;
            end

            if lum.HoldShaping.hasGrace(S)
                start = S.GUI.GraceStart;
                target = S.GUI.GraceTarget;
                if isnan(baseGrace)
                    grace = start;
                elseif completed
                    grace = baseGrace * (1 - S.GUI.GraceShrink / 100);
                else
                    grace = baseGrace;
                end
                grace = max(min(grace, max(start, target)), target);
            else
                grace = 0;
            end

            % The state machine's cycle is 100 us; store what it will run.
            holdDuration = round(max(holdDuration, 0) / 1e-4) * 1e-4;
            grace = round(max(grace, 0) / 1e-4) * 1e-4;
        end

        function history = notePrepared(history, spec)
            % notePrepared(history, spec) notes the hold and grace of the trial just
            % prepared, which will be running while the next one is prepared: next()
            % shapes from it. Call it after lum.nextTrialSpec, in the prepare window.
            history.preparedTrial = spec.TrialNumber;
            history.preparedHold = spec.HoldDuration;
            history.preparedGrace = spec.HoldGrace;
        end

        function text = describeHold(S)
            % describeHold(S) says how long the centre hold is and where that comes from.
            latency = S.Stimulus.Latency;
            fullHold = S.Stimulus.Duration + S.GUI.PostStimulusHold;
            if latency > 0
                latencyText = sprintf('the latency (%g s) and ', latency);
            else
                latencyText = '';
            end
            if lum.HoldShaping.growsHold(S)
                if latency > 0
                    lead = sprintf('After a latency of %g s from the poke, grows', latency);
                else
                    lead = 'Grows';
                end
                text = sprintf('%s from %g s to %g s (below). The whole stimulus needs %g s.', ...
                               lead, min(S.GUI.HoldStart, S.GUI.HoldTarget), S.GUI.HoldTarget, ...
                               fullHold);
            else
                text = sprintf(['%g s, from the poke: %sthe stimulus window (%g s, Stimulus tab) '...
                                'plus the post-stimulus hold (%g s, Runtime tab).'], ...
                               latency + fullHold, latencyText, S.Stimulus.Duration, ...
                               S.GUI.PostStimulusHold);
            end
        end

        function text = describe(S)
            % describe(S) says in one line what the shaping in force does.
            switch lum.HoldShaping.activeMode(S)
                case 'Grow hold'
                    text = sprintf(['Automatic shaping: the hold starts at %g s and grows %g%% '...
                                    'per completed hold, up to %g s%s.'], S.GUI.HoldStart, ...
                                   S.GUI.HoldGrowth, S.GUI.HoldTarget, stepBackText(S));
                case 'Shrink grace'
                    text = sprintf(['Automatic shaping: breaks of up to %g s are forgiven, '...
                                    'shrinking %g%% per completed hold, down to %g s. Costs one '...
                                    'global timer.'], ...
                                   S.GUI.GraceStart, S.GUI.GraceShrink, S.GUI.GraceTarget);
                case 'Both'
                    text = sprintf(['Automatic shaping: the hold grows from %g s to %g s%s, while '...
                                    'forgiven breaks shrink from %g s to %g s. Costs one global '...
                                    'timer.'], S.GUI.HoldStart, S.GUI.HoldTarget, ...
                                   stepBackText(S), S.GUI.GraceStart, S.GUI.GraceTarget);
                otherwise
                    text = ['No shaping: the animal holds for the whole stimulus window on every '...
                            'trial.'];
            end
        end
    end

    methods (Static, Access = private)
        function mode = modeOf(S)
            % A mode name, from a settings struct or the name itself.
            if isstruct(S)
                mode = lum.HoldShaping.activeMode(S);
            else
                mode = S;
            end
        end

        function tf = stepBackDue(S, history)
            % Whether enough early withdrawals have piled up at the current hold.
            limit = 0;
            if isfield(S.GUI, 'HoldStepBackAfter')
                limit = S.GUI.HoldStepBackAfter;
            end
            tf = limit >= 1 && isfield(history, 'withdrawalsAtHold') ...
                 && history.withdrawalsAtHold >= limit;
        end

        function [hold, grace] = running(history)
            % The hold and grace to shape from: the trial prepared but not yet recorded
            % (the one running while the next is prepared, notePrepared), or else the
            % last recorded trial's.
            if isfield(history, 'preparedTrial') && history.preparedTrial > history.nTrials
                hold = history.preparedHold;
                grace = history.preparedGrace;
            else
                [hold, grace] = lum.HoldShaping.lastTrial(history);
            end
        end

        function [lastHold, lastGrace, completed] = lastTrial(history)
            % The hold and grace of the last recorded trial, and whether it held.
            lastHold = NaN;
            lastGrace = NaN;
            completed = false;
            n = history.nTrials;
            if n < 1
                return
            end
            lastHold = history.holdDuration(n);
            lastGrace = history.holdGrace(n);
            completed = lum.HoldShaping.completedHold(history.outcome(n));
        end
    end

    methods (Static, Hidden)
        function tf = completedHold(outcome)
            % completedHold(outcome) is true for the outcomes of a trial whose hold was
            % completed. Shared with lum.updateHistory, so the two cannot disagree.
            tf = ismember(outcome, [lum.Outcome.Correct, lum.Outcome.Incorrect, ...
                                    lum.Outcome.NoResponse, lum.Outcome.CorrectNoReward]);
        end
    end
end


function text = stepBackText(S)
% ', stepping back after 10 early withdrawals at one hold', or nothing when it never does.
text = '';
if isfield(S.GUI, 'HoldStepBackAfter') && S.GUI.HoldStepBackAfter >= 1
    text = sprintf(', stepping back after %d early withdrawals at one hold', ...
                   round(S.GUI.HoldStepBackAfter));
end
end
