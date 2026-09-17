classdef HouseLight < lum.dev.Device
    % lum.dev.HouseLight is the white light inside the box, switched the moment the operator asks.
    %
    % PulsePal drives it (rig.HouseLight): output 3 goes through a BNC splitter to the
    % light's LED driver, and a copy of the same line into Bpod's BNC input 1 (D15).
    %
    %   Holding it   the level is output 3's resting voltage (lum.dev.PulsePal.holdVoltage):
    %                5 V on, 0 V off. PulsePal writes it at once and keeps it through every
    %                trial, block, barcode and the gaps between them — the state machine
    %                has no part in it, so it costs no output and no global timer.
    %   Timing it    the loopback makes every switch an event of the running state machine,
    %                BNC1High (on) and BNC1Low (off), timestamped on Bpod's clock to 100 us.
    %                Between state machines there is nothing to timestamp it, as for any
    %                input. Every switch is also marked on the camera clock (a HouseLight
    %                mark, when there is video) and kept with its wall-clock time (record()).
    %
    % set(on) is what the switch in the session windows calls. PulsePal is programmed
    % between trials and blocks, and a click can arrive in the middle of that; PulsePal
    % then sends the switch the moment it is free, and the light, the camera mark and the
    % windows follow at that moment, not at the click.
    %
    % The light is switched off when the device is closed, at the end of the session.
    %
    % A session without light runs even when PulsePal cannot be connected; its house light
    % is then lum.dev.DisabledHouseLight: off, not Switchable, and the windows' boxes are
    % greyed out (lum.dev.openHouseLight).
    %
    % See also: lum.dev.RealHouseLight, lum.dev.NullHouseLight, lum.dev.DisabledHouseLight,
    %           lum.dev.openHouseLight, lum.dev.PulsePal.holdVoltage, lum.gui.houseLightSwitch

    properties (SetAccess = protected)
        Output          % PulsePal output that drives the light, rig.HouseLight.PulsePalChannel
        Voltage         % Volts on that output when the light is on
        Input           % Bpod input the line is looped back into, e.g. 'BNC1'
        OnEvent         % The input's event when the light comes on, e.g. 'BNC1High'
        OffEvent        % The input's event when it goes off, e.g. 'BNC1Low'
        On = false      % The level PulsePal holds now
        OnAtStart = false  % The level it was set to when the session opened the device
        Switchable = true  % False when nothing drives the light this session (DisabledHouseLight)
    end

    properties (Access = private)
        pulsePal                % lum.dev.PulsePal that drives the light
        cameras = []            % lum.dev.Cameras, for a HouseLight mark on the camera clock
        listeners = {}          % Functions called with the level after every switch
        clock                   % tic at construction: the session's MATLAB clock for levelAt
        switchOn                % Preallocated switch record
        switchHostTime
        switchWallTime
        switchClock
        nSwitches = 0
        maxSwitches = 2000
        closed = false
    end

    methods
        function obj = HouseLight(pulsePal, config, on, available)
            % HouseLight(pulsePal, config, on, available) holds the light at its starting level.
            %
            % pulsePal is the session's lum.dev.PulsePal, config is rig.HouseLight, on the
            % level to start at. Errors with 'lum:dev:HouseLight:notHeld' when PulsePal
            % does not take it. An empty pulsePal makes a light nothing drives: off, and not
            % Switchable.
            obj@lum.dev.Device('HouseLight', available);
            obj.pulsePal = pulsePal;
            obj.Output = config.PulsePalChannel;
            obj.Voltage = config.Voltage;
            obj.Input = config.Input;
            obj.OnEvent = config.OnEvent;
            obj.OffEvent = config.OffEvent;
            obj.clock = tic;
            obj.switchOn = false(1, obj.maxSwitches);
            obj.switchHostTime = NaN(1, obj.maxSwitches);
            obj.switchWallTime = cell(1, obj.maxSwitches);
            obj.switchClock = NaN(1, obj.maxSwitches);
            obj.note('house light on PulsePal output %d (%g V on), looped back into %s', ...
                     obj.Output, obj.Voltage, obj.Input);
            if isempty(pulsePal)
                obj.Switchable = false;
                obj.closed = true;  % Nothing to switch off at the end
                return
            end

            on = logical(on);
            problem = [];
            pulsePal.holdVoltage(obj.Output, obj.Voltage * double(on), @(p) assignProblem(p));
            if ~isempty(problem)
                error('lum:dev:HouseLight:notHeld', ...
                      'PulsePal did not take the house light''s starting level: %s', problem.message);
            end
            obj.On = on;
            obj.OnAtStart = on;
            obj.note('%s at start', onOff(on));

            function assignProblem(p)
                problem = p;
            end
        end

        function attachCameras(obj, cameras)
            % attachCameras(cameras) marks every switch on the video's clock.
            obj.cameras = cameras;
        end

        function addListener(obj, callback)
            % addListener(callback) calls callback(on) after every switch, and after a
            % switch that could not be made, so a window's box always shows the light.
            obj.listeners{end+1} = callback;
        end

        function set(obj, on)
            % set(on) switches the light now — or, while PulsePal is busy, the moment it
            % is free — and records it. Nothing is recorded when the light is already there.
            if ~obj.Switchable
                obj.note('switch %s ignored: the house light cannot be switched in this session', ...
                         onOff(logical(on)));
                obj.tell(false);  % The box stays off
                return
            end
            if obj.closed
                return
            end
            on = logical(on);
            obj.pulsePal.holdVoltage(obj.Output, obj.Voltage * double(on), ...
                                     @(problem) obj.applied(on, problem));
        end

        function t = sessionTime(obj)
            % sessionTime() is seconds on MATLAB's clock since the device was opened: the
            % clock levelAt reads.
            t = toc(obj.clock);
        end

        function on = levelAt(obj, t)
            % levelAt(t) is the level the light was held at sessionTime t.
            on = obj.OnAtStart;
            last = find(obj.switchClock(1:obj.nSwitches) <= t, 1, 'last');
            if ~isempty(last)
                on = obj.switchOn(last);
            end
        end

        function r = record(obj, sessionData)
            % record(sessionData) is Data.Session.HouseLight: the wiring, the level at the
            % start and end, every switch with its camera-clock time (NaN without video)
            % and wall-clock time, and — given the session data — every edge the loopback
            % input put among the trial events, on Bpod's clock (edges()).
            n = obj.nSwitches;
            r = struct('Output', obj.Output, 'Voltage', obj.Voltage, 'Input', obj.Input, ...
                       'OnEvent', obj.OnEvent, 'OffEvent', obj.OffEvent, ...
                       'Switchable', obj.Switchable, 'OnAtStart', obj.OnAtStart, 'OnAtEnd', obj.On, ...
                       'Switches', struct('On', obj.switchOn(1:n), ...
                                          'HostTime', obj.switchHostTime(1:n), ...
                                          'WallTime', {obj.switchWallTime(1:n)}), ...
                       'Edges', struct('Time', zeros(1, 0), 'On', false(1, 0), 'Trial', zeros(1, 0)));
            if nargin >= 2
                r.Edges = lum.dev.HouseLight.edges(sessionData, obj);
            end
        end

        function close(obj)
            % close() switches the light off for the end of the session. Not a recorded
            % switch: the session's record is taken before its devices are closed. Safe
            % to call more than once, and before PulsePal is closed.
            if obj.closed
                return
            end
            obj.closed = true;
            if ~obj.On
                return
            end
            problem = [];
            try
                obj.pulsePal.holdVoltage(obj.Output, 0, @(p) assignProblem(p));
            catch closeError
                problem = closeError;
            end
            if isempty(problem)
                obj.On = false;
                obj.note('switched off at the end of the session');
            else
                obj.note('could not be switched off at the end of the session: %s', problem.message);
            end

            function assignProblem(p)
                problem = p;
            end
        end
    end

    methods (Static)
        function on = levelAtStart(events, config, fallback)
            % levelAtStart(events, config, fallback) is the level a trial or block started at.
            %
            % events is the trial's Events struct (RawEvents.Trial{k}.Events), config
            % anything with OnEvent and OffEvent (rig.HouseLight). The first edge of the
            % loopback input gives the level before it exactly: an off edge means it
            % started on. Without an edge the light did not change during the trial, and
            % fallback — what the session knew of the level — is returned.
            onTimes = eventTimes(events, config.OnEvent);
            offTimes = eventTimes(events, config.OffEvent);
            if isempty(onTimes) && isempty(offTimes)
                on = logical(fallback);
                return
            end
            on = min([offTimes Inf]) < min([onTimes Inf]);
        end

        function edges = edges(sessionData, config)
            % edges(sessionData, config) lists the loopback input's edges on Bpod's clock.
            %
            % Returns struct .Time (s, TrialStartTimestamp plus the event time), .On (true
            % for OnEvent) and .Trial, one value per edge, in time order. A switch made
            % between state machines has no edge; the camera clock and Switches have it.
            times = zeros(1, 0);
            levels = false(1, 0);
            trials = zeros(1, 0);
            if isfield(sessionData, 'RawEvents') && isfield(sessionData.RawEvents, 'Trial')
                for k = 1:numel(sessionData.RawEvents.Trial)
                    events = sessionData.RawEvents.Trial{k}.Events;
                    onTimes = eventTimes(events, config.OnEvent);
                    offTimes = eventTimes(events, config.OffEvent);
                    start = sessionData.TrialStartTimestamp(k);
                    times = [times, start + onTimes, start + offTimes]; %#ok<AGROW> % Once, at teardown
                    levels = [levels, true(size(onTimes)), false(size(offTimes))]; %#ok<AGROW>
                    trials = [trials, k * ones(1, numel(onTimes) + numel(offTimes))]; %#ok<AGROW>
                end
            end
            [times, order] = sort(times);
            edges = struct('Time', times, 'On', levels(order), 'Trial', trials(order));
        end
    end

    methods (Access = protected)
        function echo(obj, on) %#ok<INUSD> % Overridden by the emulator's shim
            % echo(on) is the loopback: on the rig the wire does it, so nothing here.
        end
    end

    methods (Access = private)
        function applied(obj, on, problem)
            % PulsePal took the switch, or refused it.
            if ~isempty(problem)
                warning('lum:dev:HouseLight:notSwitched', ...
                        'The house light could not be switched %s: %s', onOff(on), problem.message);
                obj.tell(obj.On);  % The boxes go back to the light as it is
                return
            end
            if on == obj.On
                obj.tell(on);
                return
            end
            obj.On = on;
            obj.echo(on);
            hostTime = NaN;
            if ~isempty(obj.cameras)
                hostTime = obj.cameras.mark('HouseLight', double(on));
            end
            if obj.nSwitches < obj.maxSwitches
                obj.nSwitches = obj.nSwitches + 1;
                obj.switchOn(obj.nSwitches) = on;
                obj.switchHostTime(obj.nSwitches) = hostTime;
                obj.switchWallTime{obj.nSwitches} = char(datetime('now'), 'yyyy-MM-dd HH:mm:ss.SSS');
                obj.switchClock(obj.nSwitches) = toc(obj.clock);
            end
            obj.note('switched %s', onOff(on));
            obj.tell(on);
        end

        function tell(obj, on)
            for i = 1:numel(obj.listeners)
                obj.listeners{i}(on);
            end
        end
    end
end


function times = eventTimes(events, name)
% The times of one event in a trial's Events struct, as a row; empty when it did not occur.
times = zeros(1, 0);
if isstruct(events) && isfield(events, name)
    times = reshape(events.(name), 1, []);
end
end


function text = onOff(on)
if on
    text = 'on';
else
    text = 'off';
end
end
