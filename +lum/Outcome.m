classdef Outcome
    % lum.Outcome enumerates how a LuminoseFM trial can end.
    %
    % Stored as an integer per trial (history.outcome, Data.Outcome) so the
    % per-trial record stays numeric and small, and read back through name() for
    % anything a person sees. Values are part of the data format: append new ones,
    % never renumber the existing ones, or old session files change meaning.
    %
    % See also: lum.scoreTrial, lum.OnlinePlots

    properties (Constant)
        NoInitiation      = 0   % The stimulus never started before the hold window ran
                                % out: no poke, or none that outlasted the pre-stimulus
                                % hold (state NoInitiation, no CentreHold)
        EarlyWithdrawal   = 1   % Left the centre port before the hold was complete, and
                                % the break ended the trial (S.Task.OnHoldBreak 'End trial')
        NoResponse        = 2   % Completed the hold but never chose a side port
        Correct           = 3   % Chose the side scored as correct
        Incorrect         = 4   % Chose the other side (state IncorrectChoice)
        CorrectNoReward   = 5   % Chose correctly but left before the valve opened
                                % (state WithdrewBeforeReward)
        HoldNotCompleted  = 6   % The stimulus started at least once, but every hold broke
                                % and the hold window ran out (state NoInitiation after
                                % CentreHold). Added in 0.3, with restarting holds.
    end

    methods (Static)
        function text = name(code)
            % name(code) returns the outcome's name, for logs and plot legends.
            names = lum.Outcome.allNames();
            if ~isscalar(code) || ~isfinite(code) || code < 0 || code >= numel(names)
                text = 'Unknown';
                return
            end
            text = names{code + 1};
        end

        function names = allNames()
            % allNames() lists every outcome name, ordered by code.
            names = {'NoInitiation', 'EarlyWithdrawal', 'NoResponse', ...
                     'Correct', 'Incorrect', 'CorrectNoReward', 'HoldNotCompleted'};
        end
    end
end
