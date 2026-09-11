classdef Sound < lum.stim.Component
    % lum.stim.Sound plays a waveform from the HiFi module's sound set.
    %
    % Waveforms are loaded once in session setup (lum.loadSounds) and referenced
    % here by name, so the trial builder never handles slot numbers. Two names are
    % resolved per trial, because a sound that is meant to tell the animal something
    % has to differ between the trials it distinguishes:
    %
    %   'Stimulus'  -> 'Group<k>', the tone of this trial's stimulus group
    %   'Side'      -> 'LeftTone' or 'RightTone', the tone of the rewarded side
    %
    % Any other name ('Cue', 'Noise') is played as it is. A delayed onset is silence
    % at the start of the loaded waveform, so a sound never costs a global timer.
    % When there is no module — emulator mode, sound switched off, or a sound that
    % was not loaded because its component is off — the state runs silently.
    %
    % See also: lum.stim.Component, lum.loadSounds, lum.dev.HiFi

    properties (Constant)
        PerGroupName = 'Stimulus'  % Resolved per trial to 'Group<k>'
        PerSideName = 'Side'       % Resolved per trial to '<Side>Tone'
    end

    properties (SetAccess = private)
        SoundName  % Key into context.sounds, or one of the per-trial names above
    end

    methods
        function obj = Sound(soundName)
            obj@lum.stim.Component(['Sound:' soundName]);
            obj.SoundName = soundName;
        end

        function actions = outputActions(obj, context)
            actions = {};
            key = obj.resolvedName(context);
            if ~context.spec.SoundOn || ~isKey(context.sounds, key)
                return
            end
            actions = context.devices.hifi.playAction(context.sounds(key));
        end

        function actions = stopActions(~, context)
            actions = context.devices.hifi.stopAction();
        end
    end

    methods (Access = private)
        function key = resolvedName(obj, context)
            % The sound this component plays on this trial.
            switch obj.SoundName
                case obj.PerGroupName
                    key = sprintf('Group%d', context.spec.StimulusGroup);
                case obj.PerSideName
                    key = [context.rig.Sides{context.spec.CorrectSide} 'Tone'];
                otherwise
                    key = obj.SoundName;
            end
        end
    end
end
