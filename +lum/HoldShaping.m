classdef HoldShaping
    % lum.HoldShaping trains the centre-port hold up to its full length.
    %
    % A naive animal cannot hold its nose in the centre port for a whole stimulus.
    % Two ways to bring it there, usable alone or together, chosen before the
    % session by S.Task.HoldShaping and tuned during it from the runtime window:
    %
    %   Grow hold     The hold starts at S.GUI.HoldStart and grows by
    %                 S.GUI.HoldGrowth percent after every trial on which the
    %                 animal completed it, until it reaches S.GUI.HoldTarget —
    %                 normally the stimulus window plus the post-stimulus hold.
    %                 Light is cut off where a shaped hold ends.
    %
    %   Shrink grace  The animal may leave the centre port during the hold and
    %                 come back within a grace period without the trial counting
    %                 as an early withdrawal; the hold clock keeps running while it
    %                 is out, and the stimulus carries on. The grace starts at
    %                 S.GUI.GraceStart and shrinks by S.GUI.GraceShrink percent
    %                 after every completed hold, down to S.GUI.GraceTarget
    %                 (normally 0, an unbroken hold).
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
    % for trial n+1 follow the outcome of trial n-1. Trials without a centre poke do
    % not change the shaping; early withdrawals hold it where it is.
    %
    % See also: lum.nextTrialSpec, lum.buildTrialSM, lum.timerBudget

    methods (Static)
        function names = modes()
            % modes() lists the choices for S.Task.HoldShaping.
            names = {'Off', 'Grow hold', 'Shrink grace', 'Both'};
        end

        function tf = growsHold(mode)
            % growsHold(mode) is true when the hold length is shaped.
            tf = any(strcmp(mode, {'Grow hold', 'Both'}));
        end

        function tf = hasGrace(mode)
            % hasGrace(mode) is true when breaks in the hold are forgiven.
            tf = any(strcmp(mode, {'Shrink grace', 'Both'}));
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

        function [holdDuration, grace] = next(S, history)
            % next(S, history) is the hold and grace for the next trial, in seconds.
            %
            % Without hold growth the hold is the whole stimulus window plus the
            % post-stimulus hold; without grace, the grace is 0.
            mode = S.Task.HoldShaping;
            [lastHold, lastGrace, completed] = lum.HoldShaping.lastTrial(history);

            if lum.HoldShaping.growsHold(mode)
                start = S.GUI.HoldStart;
                target = S.GUI.HoldTarget;
                if isnan(lastHold)
                    holdDuration = start;
                elseif completed
                    holdDuration = lastHold * (1 + S.GUI.HoldGrowth / 100);
                else
                    holdDuration = lastHold;
                end
                holdDuration = min(max(holdDuration, min(start, target)), target);
            else
                holdDuration = S.Stimulus.Duration + S.GUI.PostStimulusHold;
            end

            if lum.HoldShaping.hasGrace(mode)
                start = S.GUI.GraceStart;
                target = S.GUI.GraceTarget;
                if isnan(lastGrace)
                    grace = start;
                elseif completed
                    grace = lastGrace * (1 - S.GUI.GraceShrink / 100);
                else
                    grace = lastGrace;
                end
                grace = max(min(grace, max(start, target)), target);
            else
                grace = 0;
            end

            % The state machine's cycle is 100 us; store what it will run.
            holdDuration = round(max(holdDuration, 0) / 1e-4) * 1e-4;
            grace = round(max(grace, 0) / 1e-4) * 1e-4;
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
            if lum.HoldShaping.growsHold(S.Task.HoldShaping)
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
            % describe(S) says in one line what the chosen shaping does.
            switch S.Task.HoldShaping
                case 'Grow hold'
                    text = sprintf(['The hold starts at %g s and grows %g%% per completed '...
                                    'hold, up to %g s.'], S.GUI.HoldStart, ...
                                   S.GUI.HoldGrowth, S.GUI.HoldTarget);
                case 'Shrink grace'
                    text = sprintf(['Breaks of up to %g s are forgiven, shrinking %g%% per '...
                                    'completed hold, down to %g s. Costs one global timer.'], ...
                                   S.GUI.GraceStart, S.GUI.GraceShrink, S.GUI.GraceTarget);
                case 'Both'
                    text = sprintf(['The hold grows from %g s to %g s while forgiven breaks '...
                                    'shrink from %g s to %g s. Costs one global timer.'], ...
                                   S.GUI.HoldStart, S.GUI.HoldTarget, S.GUI.GraceStart, ...
                                   S.GUI.GraceTarget);
                otherwise
                    text = 'The animal holds for the whole stimulus window on every trial.';
            end
        end
    end

    methods (Static, Access = private)
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
            completed = ismember(history.outcome(n), [lum.Outcome.Correct, ...
                lum.Outcome.Incorrect, lum.Outcome.NoResponse, lum.Outcome.CorrectNoReward]);
        end
    end
end
