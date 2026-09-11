classdef Air < lum.stim.TimedOutput
    % lum.stim.Air opens the air valve, switching compressed air flow at the centre port.
    %
    % Port 4 carries the air valve only: it has no LED and no photogate, so this
    % component drives the valve line and nothing else. In the cue it is timed by
    % its S.Cue.Components row (lum.cueTiming); as a stimulus, by the 'Air' row of
    % S.Stimulus.Components.
    %
    % See also: lum.stim.TimedOutput, lum.stim.build

    methods
        function obj = Air(source)
            obj@lum.stim.TimedOutput('Air', source);
        end
    end

    methods (Access = protected)
        function name = channel(~, context)
            name = context.rig.Valve.Air;
        end

        function value = onValue(~, ~)
            value = 1;
        end

        function [enabled, onset, duration] = timing(obj, context)
            if strcmp(obj.Source, 'Cue')
                [enabled, onset, duration] = lum.stim.TimedOutput.cueRow(context.S, 'Air');
            else
                [enabled, onset, duration] = lum.stim.TimedOutput.stimulusRow(context.S, 'Air');
            end
        end
    end
end
