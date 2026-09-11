classdef CueTone < lum.stim.Component
    % lum.stim.CueTone is the cue's tone: on until the stimulus starts, then as its row says.
    %
    % The HiFi module plays one sound at a time, and a new sound replaces the one
    % playing. lum.loadSounds therefore loads the tone twice:
    %
    %   'Cue'      A seamless loop, repeated for as long as a trial can wait for a
    %              poke, played while the animal is asked to poke.
    %   'CueTail'  Only when the tone stops part way through the stimulus: that much of
    %              the same tone, ramped off, which replaces the loop as the stimulus
    %              starts.
    %
    % As the stimulus starts the loop is left playing (Whole), stopped (Off), or replaced
    % by the tail (Timed), so the tone never costs a global timer (lum.cueTiming).
    %
    % See also: lum.stim.Component, lum.cueTiming, lum.loadSounds, lum.dev.HiFi

    methods
        function obj = CueTone()
            obj@lum.stim.Component('CueTone');
        end

        function actions = outputActions(~, context)
            % The loop, in the state that waits for the poke.
            actions = lum.stim.CueTone.play(context, 'Cue');
        end

        function actions = onsetActions(~, context)
            % At stimulus onset: carry on, stop, or play the tail in place of the loop.
            parts = lum.cueTiming(context.S);
            part = parts(strcmp({parts.Type}, 'Tone'));
            actions = {};
            if isempty(part)
                return
            end
            switch part.Mode
                case 'Off'
                    actions = context.devices.hifi.stopAction();
                case 'Timed'
                    actions = lum.stim.CueTone.play(context, 'CueTail');
            end
        end

        function actions = stopActions(~, context)
            actions = context.devices.hifi.stopAction();
        end
    end

    methods (Static, Access = private)
        function actions = play(context, name)
            % Play a loaded sound, if the trial has sound and the sound was loaded.
            actions = {};
            if ~context.spec.SoundOn || ~isKey(context.sounds, name)
                return
            end
            actions = context.devices.hifi.playAction(context.sounds(name));
        end
    end
end
