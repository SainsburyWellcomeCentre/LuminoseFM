classdef PortLight < lum.stim.TimedOutput
    % lum.stim.PortLight lights a behaviour port's LED.
    %
    % Three uses, one class:
    %   PortLight('Centre', 'Cue')       the centre light in the cue, on until the poke
    %   PortLight('Centre', 'Stimulus')  a centre light flash during the stimulus,
    %                                    timed by S.Stimulus.Components
    %   PortLight('Target', 'Stimulus')  the side port this trial rewards, timed by
    %                                    S.Left.Light or S.Right.Light
    %
    % The 'Target' role is what makes a port light usable as a 2-AFC stimulus: a light
    % on the centre port carries no information about which side is correct, so a
    % visual version of the task lights the port the animal should choose, with that
    % side's own timing. Brightness comes from the runtime window, so it can be tuned
    % with an animal in the box.
    %
    % See also: lum.stim.TimedOutput, lum.stim.build, lum.buildTrialSM

    properties (Constant)
        TargetRole = 'Target'  % Resolved per trial to the rewarded side port
    end

    properties (SetAccess = private)
        PortRole  % Field name in rig.LED, e.g. 'Centre', or 'Target'
    end

    methods
        function obj = PortLight(portRole, source)
            obj@lum.stim.TimedOutput(['PortLight:' portRole], source);
            obj.PortRole = portRole;
        end
    end

    methods (Access = protected)
        function name = channel(obj, context)
            role = obj.PortRole;
            if strcmp(role, obj.TargetRole)
                role = context.rig.Sides{context.spec.CorrectSide};
            end
            if ~isfield(context.rig.LED, role)
                error('lum:stim:PortLight:unknownPort', ...
                      ['''%s'' is not a port role. Use one of %s, or ''%s'' for the side port '...
                       'this trial rewards.'], role, strjoin(fieldnames(context.rig.LED)', ', '), ...
                      obj.TargetRole);
            end
            name = context.rig.LED.(role);
        end

        function value = onValue(~, context)
            value = context.S.GUI.PortLightIntensity;
        end

        function [enabled, onset, duration] = timing(obj, context)
            if strcmp(obj.Source, 'Cue')
                [enabled, onset, duration] = lum.stim.TimedOutput.cueRow(context.S, 'CentreLight');
            elseif strcmp(obj.PortRole, obj.TargetRole)
                light = context.S.(context.rig.Sides{context.spec.CorrectSide}).Light;
                [enabled, onset, duration] = deal(light.Enabled, light.Onset, light.Duration);
            else
                [enabled, onset, duration] = ...
                    lum.stim.TimedOutput.stimulusRow(context.S, 'CentreLight');
            end
        end
    end
end
