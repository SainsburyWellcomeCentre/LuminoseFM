classdef HiFi < lum.dev.Device
    % lum.dev.HiFi drives the Bpod HiFi module that produces the task's sounds.
    %
    % The class owns waveform bookkeeping and the state machine output actions
    % that trigger playback; subclasses RealHiFi and NullHiFi differ only in
    % whether applyLoad/applyPush reach the module. Construct through lum.dev.open.
    %
    % Sounds are loaded once per session, in setup, and referenced afterwards by
    % slot index. Loading during the trial loop would block on a USB transfer of
    % up to a few hundred thousand samples, so loadSound() refuses to run once
    % the session loop has started (see freeze()).
    %
    % See also: lum.dev.open, lum.stim.Sound, TestHiFiSound

    properties (Constant)
        MaxSlots = 20  % Waveform slots in the module's active sound set
    end

    properties (SetAccess = protected)
        ModuleName    % Output channel name of the module, e.g. 'HiFi1'
        SamplingRate  % Playback sampling rate in Hz
        Loaded        % Logical, one element per slot: whether a waveform has been loaded
        Frozen = false % True once the session loop owns the module and loading is closed
    end

    methods
        function obj = HiFi(moduleName, samplingRate, available)
            obj@lum.dev.Device('HiFi', available);
            obj.ModuleName = moduleName;
            obj.SamplingRate = samplingRate;
            obj.Loaded = false(1, obj.MaxSlots);
        end

        function loadSound(obj, slot, waveform, loopDuration)
            % loadSound(slot, waveform) puts a waveform in a slot of the sound set.
            % loadSound(slot, waveform, loopDuration) loads it to repeat for up to
            % loopDuration seconds once played, until stopped or replaced.
            %
            % waveform is 1 x nSamples for mono or 2 x nSamples for stereo, with
            % samples in [-1, 1]. Call only during session setup.
            if obj.Frozen
                error('lum:dev:HiFi:frozen', ...
                      ['Sounds cannot be loaded once the session loop has started: the '...
                       'USB transfer would stall the trial. Load every sound in setup.']);
            end
            if ~isscalar(slot) || slot < 1 || slot > obj.MaxSlots || mod(slot, 1) ~= 0
                error('lum:dev:HiFi:badSlot', 'Slot must be an integer in 1..%d.', obj.MaxSlots);
            end
            if isempty(waveform) || size(waveform, 1) > 2
                error('lum:dev:HiFi:badWaveform', ...
                      'Waveform must be 1 x nSamples (mono) or 2 x nSamples (stereo).');
            end
            if max(abs(waveform(:))) > 1
                error('lum:dev:HiFi:clipping', 'Waveform samples must lie within [-1, 1].');
            end
            if nargin < 4
                loopDuration = 0;
            end
            if ~(isscalar(loopDuration) && loopDuration >= 0)
                error('lum:dev:HiFi:badLoop', 'Loop duration must be 0 (no loop) or positive seconds.');
            end
            obj.applyLoad(slot, waveform, loopDuration);
            obj.Loaded(slot) = true;
            obj.note('loaded slot %d: %d channel(s), %d samples (%.3f s)%s', ...
                     slot, size(waveform, 1), size(waveform, 2), ...
                     size(waveform, 2)/obj.SamplingRate, loopText(loopDuration));
        end

        function push(obj)
            % push() moves newly loaded waveforms into the module's playback buffers.
            obj.applyPush();
            obj.note('pushed sound set');
        end

        function freeze(obj)
            % freeze() closes the module to further loading, for the rest of the session.
            obj.Frozen = true;
        end

        function action = playAction(obj, slot)
            % playAction(slot) returns the OutputActions pair that starts playback.
            % Empty when there is no module, so a state built around it still runs.
            if ~obj.Available || slot < 1 || ~obj.Loaded(slot)
                action = {};
                return
            end
            action = {obj.ModuleName, ['P' slot-1]};  % The module indexes slots from 0
        end

        function action = stopAction(obj)
            % stopAction() returns the OutputActions pair that stops playback.
            if ~obj.Available
                action = {};
                return
            end
            action = {obj.ModuleName, 'X'};
        end
    end

    methods (Access = protected)
        function applyLoad(obj, slot, waveform, loopDuration) %#ok<INUSD> % Overridden by subclasses
            % applyLoad() transfers one waveform to the module, looped for loopDuration
            % seconds when that is positive. Subclass responsibility.
        end

        function applyPush(obj) %#ok<MANU> % Overridden by subclasses
            % applyPush() commits the loaded sound set. Subclass responsibility.
        end
    end
end


function text = loopText(loopDuration)
% ', looped for up to N s' for a looped sound, nothing otherwise.
text = '';
if loopDuration > 0
    text = sprintf(', looped for up to %g s', loopDuration);
end
end
