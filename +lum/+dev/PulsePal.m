classdef PulsePal < lum.dev.Device
    % lum.dev.PulsePal programs the carrier of the optogenetic stimulus.
    %
    % Architecture decision D1 splits the stimulus across two devices: Bpod global
    % timers gate BNC1/BNC2 to define the light *pattern* of channels A and B, and
    % PulsePal turns each gate into the *carrier* — a pulse train, or constant
    % light. Both PulsePal trigger channels run in gated mode, so OUT1 pulses
    % exactly while BNC1 is high, and OUT2 while BNC2 is high.
    %
    % This class owns the translation from a carrier struct to PulsePal parameters
    % and the caching that keeps reprogramming cheap. Subclasses RealPulsePal and
    % NullPulsePal differ only in send(): whether the bytes reach a device or only
    % the log. Construct through lum.dev.open.
    %
    % Carrier: a struct array with one element per optical channel, element k
    % programming PulsePal output k (S.Light.Carrier, plus MaxDuration). The two
    % channels drive different LEDs into different cables, so each carries its own
    % numbers — equalising the light two channels deliver is a per-channel
    % calibration, not one number.
    %
    %   .Frequency    Carrier frequency in Hz. 0 means constant-on for the gate.
    %   .PulseWidth   Pulse duration in seconds (ignored when Frequency is 0)
    %   .Voltage      Output amplitude in volts
    %   .MaxDuration  Pulse train duration in seconds. Must exceed the longest gate,
    %                 or the train ends while the gate is still open.
    %   .Channel      Optional; when present it must equal the element's index, so
    %                 a reordered settings file cannot silently swap the channels.
    %
    % Usage:
    %   devices = lum.dev.open(rig, S);
    %   devices.pulsePal.configure(carrier);  % inter-trial window only
    %
    % See also: lum.dev.open, lum.stim.OptoPattern, docs/architecture.md (D1)

    properties (Constant)
        % PulsePal parameter codes, from ProgramPulsePalParam's header.
        Param = struct('IsBiphasic', 1, 'Phase1Voltage', 2, 'Phase1Duration', 4, ...
                       'InterPulseInterval', 7, 'BurstDuration', 8, 'BurstInterval', 9, ...
                       'PulseTrainDuration', 10, 'PulseTrainDelay', 11, ...
                       'LinkedToTriggerCH1', 12, 'LinkedToTriggerCH2', 13, ...
                       'CustomTrainID', 14, 'CustomTrainTarget', 15, ...
                       'CustomTrainLoop', 16, 'RestingVoltage', 17, 'TriggerMode', 128);

        % Trigger mode as the *firmware* encodes it: 0 = normal, 1 = toggle, 2 = gated.
        % ProgramPulsePalParam's header comment says 1/2/3 and is off by one; the
        % firmware's own comment (PulsePal_2_0_1.ino:95) and its comparisons against
        % TriggerMode == 2 for the gated case are what this follows.
        GatedTriggerMode = 2;

        CyclePeriod = 1e-4;   % PulsePal time base: all times must be multiples of 100 us
        MaxTime = 3600;       % Longest time value PulsePal accepts, in seconds
        MaxVoltage = 10;      % Output range is -10 V to +10 V
        nOutputChannels = 4;  % PulsePal has four output channels; this rig uses 1 and 2
    end

    properties (SetAccess = protected)
        LastCarrier = []  % The carrier most recently applied, or [] before the first
    end

    properties (Access = private)
        sentValues  % Map from 'channel/paramCode' to the value last sent, for change detection
    end

    methods
        function obj = PulsePal(available)
            obj@lum.dev.Device('PulsePal', available);
            obj.sentValues = containers.Map('KeyType', 'char', 'ValueType', 'double');
        end

        function configure(obj, carrier)
            % configure() programs both trigger channels for the given carrier.
            %
            % Only parameters whose value has changed since the last call are sent,
            % so a session that never changes its carrier costs one round trip on
            % trial 1 and nothing afterwards. Call this in the inter-trial window.
            carrier = obj.validateCarrier(carrier);
            p = obj.Param;

            for channel = 1:obj.nOutputChannels
                if channel <= numel(carrier)
                    thisChannel = carrier(channel);
                    [phase1Duration, interPulseInterval] = obj.carrierTimes(thisChannel);
                    obj.set(channel, p.IsBiphasic, 0);
                    obj.set(channel, p.Phase1Voltage, thisChannel.Voltage);
                    obj.set(channel, p.RestingVoltage, 0);
                    obj.set(channel, p.Phase1Duration, phase1Duration);
                    obj.set(channel, p.InterPulseInterval, interPulseInterval);
                    obj.set(channel, p.BurstDuration, 0);   % 0 disables bursting: one continuous train
                    obj.set(channel, p.BurstInterval, 0);
                    obj.set(channel, p.PulseTrainDuration, thisChannel.MaxDuration);
                    obj.set(channel, p.PulseTrainDelay, 0);
                    obj.set(channel, p.CustomTrainID, 0);
                    obj.set(channel, p.CustomTrainTarget, 0);
                    obj.set(channel, p.CustomTrainLoop, 0);
                end
                % Output n follows trigger n alone. Linking an output to both gated
                % triggers would make the firmware wait for both lines to fall before
                % stopping it (PulsePal_2_0_1.ino:655), coupling the two channels.
                obj.set(channel, p.LinkedToTriggerCH1, double(channel == 1));
                obj.set(channel, p.LinkedToTriggerCH2, double(channel == 2));
            end

            for triggerChannel = 1:2
                obj.set(triggerChannel, p.TriggerMode, obj.GatedTriggerMode);
            end

            obj.LastCarrier = carrier;
        end

        function value = sentValue(obj, channel, paramCode)
            % sentValue(channel, paramCode) returns the value last sent for one
            % parameter, or NaN if it has never been sent. The device holds state
            % across trials, so this is the only way to see what it is actually set
            % to without asking it over the wire.
            key = sprintf('%d/%d', channel, paramCode);
            if isKey(obj.sentValues, key)
                value = obj.sentValues(key);
            else
                value = NaN;
            end
        end

        function tf = needsReprogramming(obj, carrier)
            % needsReprogramming() reports whether configure() would send anything.
            % The session loop uses it to skip the call entirely on unchanged trials.
            tf = true;
            if isempty(obj.LastCarrier)
                return
            end
            try
                candidate = obj.validateCarrier(carrier);
            catch
                return  % Invalid carriers are reported by configure(), not here
            end
            tf = ~isequal(candidate, obj.LastCarrier);
        end
    end

    methods (Access = protected)
        function send(obj, channel, paramCode, value) %#ok<INUSD> % Overridden by subclasses
            % send() delivers one parameter to the device. Subclass responsibility.
            error('lum:dev:PulsePal:abstract', 'send() must be implemented by a subclass.');
        end
    end

    methods (Access = private)
        function set(obj, channel, paramCode, value)
            % set() sends one parameter, unless that exact value was already sent.
            key = sprintf('%d/%d', channel, paramCode);
            if isKey(obj.sentValues, key) && obj.sentValues(key) == value
                return
            end
            obj.send(channel, paramCode, value);
            obj.sentValues(key) = value;
        end

        function [phase1Duration, interPulseInterval] = carrierTimes(obj, carrier)
            % carrierTimes() converts one channel's frequency and pulse width into
            % PulsePal times.
            if carrier.Frequency == 0
                % Constant on: a single pulse as long as the train, so the gate alone
                % decides when light is delivered.
                phase1Duration = carrier.MaxDuration;
                interPulseInterval = obj.CyclePeriod;
            else
                phase1Duration = obj.quantise(carrier.PulseWidth);
                interPulseInterval = obj.quantise(obj.quantise(1/carrier.Frequency) - phase1Duration);
            end
        end
    end

    methods (Static)
        function carrier = validateCarrier(carrier)
            % validateCarrier(carrier) checks and quantises a per-channel carrier.
            %
            % Static, so that the setup dialog can check a carrier the operator is
            % still typing without a device, a shim, or a line in the device log.
            % The rig and the dialog then reject exactly the same carriers, which is
            % the point: a carrier PulsePal would refuse should be refused while
            % there is still someone at the keyboard to fix it.
            if ~isstruct(carrier) || isempty(carrier)
                error('lum:dev:PulsePal:badCarrier', ...
                      ['The carrier must be a struct array with one element per optical '...
                       'channel. See lum.defaultSettings, S.Light.Carrier.']);
            end
            nTriggerChannels = 2;   % OUT1 follows IN1, OUT2 follows IN2; nothing gates 3-4
            if numel(carrier) > nTriggerChannels
                error('lum:dev:PulsePal:badCarrier', ...
                      ['The carrier has %d channels, but only %d PulsePal outputs are '...
                       'gated by a BNC line.'], numel(carrier), nTriggerChannels);
            end
            required = {'Frequency', 'PulseWidth', 'Voltage', 'MaxDuration'};
            missing = required(~isfield(carrier, required));
            if ~isempty(missing)
                error('lum:dev:PulsePal:badCarrier', ...
                      'The carrier is missing field(s): %s.', strjoin(missing, ', '));
            end
            for channel = 1:numel(carrier)
                carrier(channel) = lum.dev.PulsePal.validateChannel(carrier(channel), channel);
            end
        end

        function carrier = validateChannel(carrier, channel)
            % validateChannel() checks and quantises one channel's carrier.
            %
            % Every message names the channel, A or B, because with independent
            % carriers a rejected one is otherwise a puzzle: which of the two rows on
            % the setup dialog was the problem?
            names = 'AB';
            label = sprintf('Channel %s', names(min(channel, 2)));
            if isfield(carrier, 'Channel') && ~isequal(carrier.Channel, channel)
                error('lum:dev:PulsePal:badCarrier', ...
                      ['Carrier element %d is labelled channel %s. The elements must be in '...
                       'channel order, or output %d would be driven with another channel''s '...
                       'carrier.'], channel, mat2str(carrier.Channel), channel);
            end
            if ~isscalar(carrier.Frequency) || carrier.Frequency < 0
                error('lum:dev:PulsePal:badCarrier', ...
                      '%s: Frequency must be a non-negative scalar.', label);
            end
            if ~isscalar(carrier.Voltage) || abs(carrier.Voltage) > lum.dev.PulsePal.MaxVoltage
                error('lum:dev:PulsePal:badCarrier', ...
                      '%s: Voltage must be one value within +/-%g V.', ...
                      label, lum.dev.PulsePal.MaxVoltage);
            end
            if carrier.MaxDuration <= 0 || carrier.MaxDuration > lum.dev.PulsePal.MaxTime
                error('lum:dev:PulsePal:badCarrier', ...
                      '%s: MaxDuration must be in (0, %g] s.', label, lum.dev.PulsePal.MaxTime);
            end
            carrier.MaxDuration = lum.dev.PulsePal.quantise(carrier.MaxDuration);

            if carrier.Frequency > 0
                period = lum.dev.PulsePal.quantise(1/carrier.Frequency);
                carrier.PulseWidth = lum.dev.PulsePal.quantise(carrier.PulseWidth);
                if carrier.PulseWidth < lum.dev.PulsePal.CyclePeriod
                    error('lum:dev:PulsePal:badCarrier', ...
                          '%s: PulseWidth rounds to 0; the shortest PulsePal pulse is %g s.', ...
                          label, lum.dev.PulsePal.CyclePeriod);
                end
                if carrier.PulseWidth >= period
                    error('lum:dev:PulsePal:badCarrier', ...
                          ['%s: PulseWidth (%g s) leaves no gap at %g Hz. Reduce the pulse '...
                           'width below the %g s period, or set Frequency to 0 for constant '...
                           'light.'], label, carrier.PulseWidth, carrier.Frequency, period);
                end
            else
                carrier.PulseWidth = 0;
            end
        end

        function t = quantise(t)
            % quantise() rounds a time to PulsePal's 100 us cycle.
            % ProgramPulsePalParam errors on times that are not exact multiples, so
            % every time value is rounded here rather than at each call site.
            t = round(t / lum.dev.PulsePal.CyclePeriod) * lum.dev.PulsePal.CyclePeriod;
        end
    end
end
