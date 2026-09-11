classdef OptoPattern < lum.stim.Component
    % lum.stim.OptoPattern delivers a trial's two-channel light pattern.
    %
    % This is the component that implements architecture decision D1. The
    % pattern's envelope — which of channel A (BNC1) and channel B (BNC2) is high,
    % when, for how long — is compiled into one-shot Bpod global timers, all
    % triggered together from the hold state. PulsePal, programmed in the
    % inter-trial window, turns each gate into its channel's carrier. Nothing in the
    % timing path runs in MATLAB.
    %
    % One global timer per stretch of light, so the stimulus set is validated
    % against the machine's timer budget when the session starts, not here: by
    % trial-build time the pattern is known to fit.
    %
    % See also: lum.stim.Component, lum.pattern.stimulusSet, lum.dev.PulsePal

    properties (Constant)
        % Margin added to the PulsePal pulse train duration. The train must outlast
        % the longest gate, or it stops while the BNC line is still high and the
        % light cuts out early.
        TrainMargin = 0.1
    end

    methods
        function obj = OptoPattern()
            obj@lum.stim.Component('OptoPattern');
        end

        function n = nTimersNeeded(~, context)
            n = 0;
            if context.spec.OptoOn
                n = size(context.pattern.Segments, 1);
            end
        end

        function configure(obj, context)
            % configure() programs the PulsePal carrier for this session.
            % Cheap on every trial after the first: nothing is sent unless a value
            % changed.
            if ~context.spec.OptoOn
                return
            end
            % Every channel's train has to outlast the longest gate, so its length
            % comes from the stimulus window rather than from the operator.
            carrier = context.S.Light.Carrier;
            [carrier.MaxDuration] = deal(context.S.Stimulus.Duration + obj.TrainMargin);
            if context.devices.pulsePal.needsReprogramming(carrier)
                context.devices.pulsePal.configure(carrier);
            end
        end

        function sma = addGlobalTimers(~, sma, context, timerIndices)
            % addGlobalTimers() turns each stretch of light into a one-shot timer.
            segments = context.pattern.Segments;
            for i = 1:numel(timerIndices)
                sma = SetGlobalTimer(sma, 'TimerID', timerIndices(i), ...
                                     'Duration', segments(i, 3), ...
                                     'OnsetDelay', segments(i, 2), ...
                                     'Channel', context.rig.Opto.Channels{segments(i, 1)});
            end
        end

        function actions = stopActions(~, context)
            % stopActions() pulls the lines the pattern uses low. The trial builder
            % also cancels the timers; the emulator does not implement cancelling, so
            % driving the lines low as well keeps light from outliving the hold there.
            actions = {};
            if ~context.spec.OptoOn || isempty(context.pattern.Segments)
                return
            end
            channels = unique(context.pattern.Segments(:, 1))';
            actions = cell(1, 2 * numel(channels));
            actions(1:2:end) = context.rig.Opto.Channels(channels);
            actions(2:2:end) = {0};
        end
    end
end
