classdef Component < handle
    % lum.stim.Component is the interface every cue and stimulus element implements.
    %
    % The cue and the stimulus are each a *list* of components. That is what lets
    % the operator combine light patterns, port lights, tones and air freely
    % without the state graph changing: the trial builder asks each component in
    % the list for its contributions and merges them. State names stay fixed across
    % modalities; only OutputActions and global timers differ.
    %
    % A component contributes in five ways, asked in this order:
    %   nTimersNeeded    How many global timers it needs this trial
    %   configure        Device programming, run in the inter-trial window
    %   addGlobalTimers  Global timer definitions, given the indices it was granted
    %   outputActions    OutputActions for the state that delivers it
    %   stopActions      OutputActions that switch it off again
    %
    % Timers a component was granted are triggered and cancelled by the trial
    % builder, in one bit mask with every other component's: two components each
    % naming GlobalTimerTrig in one state would overwrite each other's timers.
    %
    % Every method takes a context struct with fields:
    %   .S         Settings
    %   .rig       Channel map from RigConfig
    %   .devices   Device shims from lum.dev.open
    %   .spec      Trial spec from lum.nextTrialSpec
    %   .pattern   The trial's light pattern (lum.pattern.patternAt)
    %   .sounds    Map from sound name to HiFi slot index
    %
    % Defaults are no-ops, so a component overrides only what it actually uses.
    %
    % See also: lum.stim.build, lum.buildTrialSM

    properties (SetAccess = protected)
        Name  % Short name, used in logs and in the session's component list
    end

    methods
        function obj = Component(name)
            obj.Name = name;
        end

        function n = nTimersNeeded(obj, context) %#ok<INUSD>
            % nTimersNeeded() reports how many global timers this trial needs.
            n = 0;
        end

        function configure(obj, context) %#ok<INUSD>
            % configure() does any device programming this component needs.
            % Called in the inter-trial window, never during the stimulus.
        end

        function sma = addGlobalTimers(obj, sma, context, timerIndices) %#ok<INUSD>
            % addGlobalTimers() defines the timers this component was granted.
        end

        function actions = outputActions(obj, context) %#ok<INUSD>
            % outputActions() returns OutputActions pairs for the delivering state.
            actions = {};
        end

        function actions = onsetActions(obj, context) %#ok<INUSD>
            % onsetActions() returns OutputActions pairs for the moment the stimulus
            % starts, for a cue component that is already delivering: keep it on,
            % switch it off, or leave it to its timer. Stimulus components ignore it.
            actions = {};
        end

        function actions = stopActions(obj, context) %#ok<INUSD>
            % stopActions() returns OutputActions pairs that switch delivery off.
            actions = {};
        end
    end
end
