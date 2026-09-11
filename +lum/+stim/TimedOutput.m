classdef (Abstract) TimedOutput < lum.stim.Component
    % lum.stim.TimedOutput is a component that drives one output line, on a timetable.
    %
    % The port lights and the air valve share everything but which line they drive
    % and what they drive it to, so the timing lives here once. A component belongs
    % to one of two places in the trial:
    %
    %   'Cue'       On from trial start (outputActions, in WaitForCentrePoke) until the
    %               stimulus starts, then kept on until the hold ends, switched off, or
    %               switched off by a global timer part way through the stimulus
    %               (onsetActions, in CentreHold), as lum.cueTiming says.
    %   'Stimulus'  Timed from stimulus onset. On for the whole window it is an
    %               output action of the hold state and costs nothing; switching on
    %               late or off early needs a global timer, because the hold is one
    %               state that leaving the centre port can end at any instant.
    %
    % lum.stim.isTimed decides which, for this class and for the timer budget alike.
    %
    % See also: lum.stim.PortLight, lum.stim.Air, lum.stim.isTimed, lum.timerBudget

    properties (SetAccess = protected)
        Source  % 'Cue' or 'Stimulus'
    end

    methods
        function obj = TimedOutput(name, source)
            obj@lum.stim.Component(name);
            if ~ismember(source, {'Cue', 'Stimulus'})
                error('lum:stim:TimedOutput:badSource', ...
                      'A component belongs to the ''Cue'' or the ''Stimulus''; got ''%s''.', source);
            end
            obj.Source = source;
        end

        function n = nTimersNeeded(obj, context)
            n = double(obj.needsTimer(context));
        end

        function sma = addGlobalTimers(obj, sma, context, timerIndices)
            % One timer: onset delay and duration from stimulus onset, driving the
            % line to its on value. Argument order matters, because SetGlobalTimer
            % reads its optional arguments by position.
            if isempty(timerIndices)
                return
            end
            [~, onset, duration] = obj.timing(context);
            sma = SetGlobalTimer(sma, 'TimerID', timerIndices(1), 'Duration', duration, ...
                                 'OnsetDelay', onset, 'Channel', obj.channel(context), ...
                                 'OnMessage', obj.onValue(context));
        end

        function actions = outputActions(obj, context)
            actions = {};
            enabled = obj.timing(context);
            if enabled && (strcmp(obj.Source, 'Cue') || ~obj.needsTimer(context))
                actions = {obj.channel(context), obj.onValue(context)};
            end
        end

        function actions = onsetActions(obj, context)
            % A cue component at stimulus onset: on until the hold ends, off now, or
            % left to the timer triggered with the stimulus, which switches it off.
            actions = {};
            [enabled, ~, duration] = obj.timing(context);
            if ~enabled || ~strcmp(obj.Source, 'Cue')
                return
            end
            if duration == 0
                actions = {obj.channel(context), 0};
            elseif isinf(duration)
                actions = {obj.channel(context), obj.onValue(context)};
            end
        end

        function actions = stopActions(obj, context)
            actions = {};
            if obj.timing(context)
                actions = {obj.channel(context), 0};
            end
        end
    end

    methods (Access = protected)
        function tf = needsTimer(obj, context)
            % True when this trial times the line with a global timer: a stimulus
            % component that does not span the window, or a cue component that goes
            % off part way through it.
            [enabled, onset, duration] = obj.timing(context);
            if strcmp(obj.Source, 'Cue')
                tf = enabled && duration > 0 && isfinite(duration);
            else
                tf = enabled && lum.stim.isTimed(onset, duration, context.S.Stimulus.Duration);
            end
        end
    end

    methods (Abstract, Access = protected)
        % channel(context) is the output channel name, e.g. 'PWM2' or 'Valve4'.
        name = channel(obj, context)
        % onValue(context) is the value the line is driven to while on.
        value = onValue(obj, context)
        % timing(context) says whether it is on this trial, and when from stimulus onset.
        % A cue component has onset 0 and lum.cueTiming's duration: Inf until the hold
        % ends, 0 off at the poke.
        [enabled, onset, duration] = timing(obj, context)
    end

    methods (Static, Access = protected)
        function [enabled, onset, duration] = stimulusRow(S, type)
            % The Enabled, Onset and Duration of one S.Stimulus.Components row.
            row = S.Stimulus.Components(strcmp({S.Stimulus.Components.Type}, type));
            if isempty(row)
                enabled = false;
                onset = 0;
                duration = 0;
                return
            end
            enabled = row(1).Enabled;
            onset = row(1).Onset;
            duration = row(1).Duration;
        end

        function [enabled, onset, duration] = cueRow(S, type)
            % Whether a component is in the cue, and how long it stays on from
            % stimulus onset (lum.cueTiming).
            parts = lum.cueTiming(S);
            part = parts(strcmp({parts.Type}, type));
            enabled = ~isempty(part);
            onset = 0;
            duration = 0;
            if enabled
                duration = part(1).Duration;
            end
        end
    end
end
