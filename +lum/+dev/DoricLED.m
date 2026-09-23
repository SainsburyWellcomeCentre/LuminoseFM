classdef DoricLED < lum.dev.Device
    % lum.dev.DoricLED is the Doric LED driver as a session sees it (D17).
    %
    % The driver (LEDFLS_465_465) lights channel A with its LED channel 1 and B with
    % channel 2. PulsePal's OUT1 and OUT2 go into the driver's TTL inputs, so the light's
    % timing stays Bpod's and PulsePal's (D1); this object sets how bright it is: both
    % channels in external TTL mode at a current each, changed only between trials,
    % sleep blocks or ePhys steps. It never enters a state machine.
    %
    % Three modes, chosen once by lum.dev.openDoricLED:
    %
    %   'Device'     The DoricLED package's doric.LightSource on the real driver, through
    %                its bridge. Available is true.
    %   'Simulated'  The same doric.LightSource on the package's SimulatedTransport: the
    %                emulator's LED, which answers like the device and logs every call.
    %   'Manual'     No package, or S.Doric.Enabled off: nothing is sent, and the driver is
    %                used as it was set by hand (external TTL mode, its own current).
    %                Currents are NaN: unknown to the session.
    %
    % A doric.LightSource connects in the background (connect), so the protocol starts it
    % as it launches and the setup dialogs use it (the Doric LED tab, calibration) while
    % the operator sets the session up. The session then waits for it (ensureReady), sets
    % both channels up (setUp) and changes currents between trials: a runtime request
    % (request, from the LED window) is sent by applyPending in the next prepare window,
    % and an ePhys step's current by setCurrents between blocks.
    %
    % Usage:
    %   led = lum.dev.openDoricLED(emulated, S);   % connecting starts at once
    %   led.ensureReady();                         % session start: wait, or error
    %   led.setUp(lum.led.intensity(S, cals).CurrentmA, S.Doric.MaxCurrentmA);
    %   mA = led.applyPending();                   % prepare window, every trial
    %   record = led.record();                     % teardown, before close
    %   led.close();                               % light off, driver released
    %
    % Every command is also a line in the device log (log(), Data.Session.DeviceLog).
    %
    % See also: lum.dev.openDoricLED, lum.led.lightPath, lum.gui.DoricSetup,
    %           lum.gui.DoricWindow, doric.LightSource

    properties (SetAccess = private)
        Mode = 'Manual'       % 'Device', 'Simulated' or 'Manual'
        Reason = ''           % Why the mode is what it is, for the windows and the log
        LightSource = []      % The doric.LightSource, or [] in Manual mode
        CurrentmA = [NaN NaN] % Current commanded on A and B and acknowledged; NaN unknown
        MaxCurrentmA = [NaN NaN]
        Pending = [NaN NaN]   % Requested from the LED window, not yet sent
        IsSetUp = false       % Both channels in external TTL mode and started
        Changes               % n x 4 [session seconds, channel, mA, tag]: every current sent
    end

    properties (Access = private)
        transport = []        % A SimulatedTransport this object made and must delete
        nChanges = 0
        clock
        listeners = {}
        faultText = ''
    end

    properties (Constant)
        MaxChanges = 5000     % Current changes kept in the record
    end

    events
        Changed               % The connection's state or a current changed; windows redraw
    end

    methods
        function obj = DoricLED(mode, lightSource, reason, transport)
            % DoricLED(mode, lightSource, reason, transport) — use lum.dev.openDoricLED.
            obj@lum.dev.Device('DoricLED', strcmp(mode, 'Device'));
            obj.Mode = mode;
            obj.Reason = reason;
            obj.clock = tic;
            obj.Changes = NaN(obj.MaxChanges, 4);
            if nargin >= 4
                obj.transport = transport;
            end
            if ~isempty(lightSource)
                obj.LightSource = lightSource;
                obj.listeners{end+1} = addlistener(lightSource, 'StateChanged', ...
                                                   @(~, ~) obj.notifyChanged());
                obj.listeners{end+1} = addlistener(lightSource, 'Faulted', ...
                                                   @(~, event) obj.onFault(event));
            end
            obj.note('%s: %s', mode, reason);
        end

        function tf = isControlled(obj)
            % isControlled() is true when this session sets the LED (Device or Simulated).
            tf = ~isempty(obj.LightSource);
        end

        function text = state(obj)
            % state() is the connection in a few words: 'Manual', 'Connecting',
            % 'Ready', 'Faulted', 'Disconnected'.
            if ~obj.isControlled()
                text = 'Manual';
                return
            end
            switch obj.LightSource.State
                case {'Initialising', 'Opening'}
                    text = 'Connecting';
                otherwise
                    text = obj.LightSource.State;
            end
        end

        function text = describeState(obj)
            % describeState() is one line for the windows: mode, device and state.
            switch obj.Mode
                case 'Manual'
                    text = sprintf('Not controlled from MATLAB (%s): set the driver by hand to external TTL mode.', ...
                                   obj.Reason);
                    return
                case 'Simulated'
                    where = 'simulated driver (emulator)';
                otherwise
                    where = 'Doric driver';
                    if ~isempty(obj.LightSource.DeviceName)
                        where = sprintf('%s on Doric port %d', obj.LightSource.DeviceName, ...
                                        obj.LightSource.Port);
                    end
            end
            switch obj.state()
                case 'Ready'
                    text = sprintf('Connected: %s.', where);
                case 'Connecting'
                    text = sprintf('Connecting to the %s (a few seconds)...', where);
                case 'Faulted'
                    text = sprintf('The %s is not responding: %s', where, obj.faultReason());
                otherwise
                    text = sprintf('Not connected (%s).', where);
            end
        end

        function connect(obj)
            % connect() starts connecting in the background; state() follows it. Does
            % nothing when connected or connecting, or in Manual mode.
            if ~obj.isControlled() || ismember(obj.state(), {'Ready', 'Connecting'})
                return
            end
            obj.faultText = '';
            obj.note('connecting');
            try
                obj.LightSource.connect('Wait', false, 'OnDone', @(result) obj.connected(result));
            catch connectError
                obj.faultText = connectError.message;
                obj.note('could not start connecting: %s', connectError.message);
            end
            obj.notifyChanged();
        end

        function ensureReady(obj, timeoutSeconds)
            % ensureReady(timeoutSeconds) waits for the connection, connecting first if
            % need be. Errors with 'lum:dev:DoricLED:notConnected' when it does not come.
            % Nothing to wait for in Manual mode.
            if ~obj.isControlled()
                return
            end
            if nargin < 2
                timeoutSeconds = 60;
            end
            if ~strcmp(obj.state(), 'Ready')
                if ~strcmp(obj.state(), 'Connecting')
                    obj.LightSource.disconnect();
                    obj.connect();
                end
                waited = tic;
                while strcmp(obj.state(), 'Connecting') && toc(waited) < timeoutSeconds
                    obj.LightSource.poll();
                    pause(0.05);
                end
            end
            if ~strcmp(obj.state(), 'Ready')
                error('lum:dev:DoricLED:notConnected', 'The Doric LED driver did not connect: %s', ...
                      obj.faultReason());
            end
        end

        function setUp(obj, currentmA, maxCurrentmA)
            % setUp(currentmA, maxCurrentmA) puts both channels in external TTL mode at
            % their currents, with their limits, and starts them: from here each LED lights
            % while PulsePal's output into it is high. Blocking; errors when the driver
            % refuses. Nothing is sent in Manual mode.
            if ~obj.isControlled()
                obj.note('manual: the driver is used as it was set by hand');
                return
            end
            checkCurrents(currentmA, maxCurrentmA);
            source = obj.LightSource;
            for k = 1:2
                if ~isempty(source.Channels(k).CommandedCurrentmA) && ...
                        source.Channels(k).CommandedCurrentmA > maxCurrentmA(k)
                    source.Channels(k).setCurrent(0);  % So the lower limit can be set
                end
                source.Channels(k).MaxCurrentmA = maxCurrentmA(k);
            end
            source.apply(doric.ChannelSettings.extTTL(currentmA(1)), ...
                         doric.ChannelSettings.extTTL(currentmA(2)));
            source.startAll();
            obj.MaxCurrentmA = double(maxCurrentmA(:)');
            obj.IsSetUp = true;
            obj.Pending = [NaN NaN];
            for k = 1:2
                obj.recordCurrent(k, currentmA(k), 0);
            end
            obj.note('external TTL mode, A %g mA, B %g mA (limits %g, %g mA), started', ...
                     currentmA(1), currentmA(2), maxCurrentmA(1), maxCurrentmA(2));
            obj.notifyChanged();
        end

        function request(obj, k, currentmA)
            % request(k, mA) asks for channel k's current to change at the next prepare
            % window (applyPending). Refused above the channel's limit, so the LED window
            % can say so at once.
            if ~obj.isControlled()
                error('lum:dev:DoricLED:manual', 'The LED is set by hand in this session.');
            end
            if ~(isscalar(currentmA) && isfinite(currentmA) && currentmA >= 0 && currentmA == round(currentmA))
                error('lum:dev:DoricLED:badCurrent', 'An LED current is a whole number of mA, 0 or more.');
            end
            if currentmA > obj.MaxCurrentmA(k)
                error('lum:dev:DoricLED:overLimit', ...
                      'Channel %s: %g mA is above its limit of %g mA.', char('A' + k - 1), ...
                      currentmA, obj.MaxCurrentmA(k));
            end
            obj.Pending(k) = currentmA;
            obj.note('requested %s = %g mA', char('A' + k - 1), currentmA);
            obj.notifyChanged();
        end

        function currents = applyPending(obj, tag)
            % applyPending(tag) sends any current the LED window asked for, without waiting
            % for the driver, and returns the currents on A and B from now on (NaN in
            % Manual mode). Call it in a prepare window or between blocks, never with light
            % in flight. tag (a trial or block number) goes into the record of changes.
            if nargin < 2
                tag = NaN;
            end
            currents = obj.CurrentmA;
            if ~obj.isControlled() || all(isnan(obj.Pending))
                return
            end
            for k = find(~isnan(obj.Pending))
                value = obj.Pending(k);
                obj.Pending(k) = NaN;
                try
                    obj.LightSource.Channels(k).setCurrent(value, 'Wait', false, 'SettleMs', 0);
                    obj.recordCurrent(k, value, tag);
                    obj.note('sent %s = %g mA (at %g)', char('A' + k - 1), value, tag);
                catch sendError
                    obj.note('could not send %s = %g mA: %s', char('A' + k - 1), value, sendError.message);
                    warning('lum:dev:DoricLED:notSent', 'The LED current was not changed: %s', ...
                            sendError.message);
                end
            end
            currents = obj.CurrentmA;
            obj.notifyChanged();
        end

        function setCurrents(obj, currentmA, tag)
            % setCurrents(mA, tag) sets both channels' currents now and waits for the
            % driver: an ePhys calibration step between blocks. NaN leaves a channel as it
            % is. Errors when the driver refuses, so the session can stop.
            if ~obj.isControlled()
                return
            end
            if nargin < 3
                tag = NaN;
            end
            for k = 1:2
                value = currentmA(k);
                if isnan(value) || value == obj.CurrentmA(k)
                    continue
                end
                obj.LightSource.Channels(k).setCurrent(value);
                obj.recordCurrent(k, value, tag);
                obj.note('set %s = %g mA (at %g)', char('A' + k - 1), value, tag);
            end
            obj.notifyChanged();
        end

        function lightOn(obj, k, currentmA)
            % lightOn(k, mA) lights channel k continuously at a current: for a power
            % meter while calibrating. Blocking. setUp puts it back in external TTL mode.
            obj.requireReady();
            source = obj.LightSource;
            if currentmA > source.Channels(k).MaxCurrentmA
                source.Channels(k).MaxCurrentmA = min(currentmA, source.Channels(k).DeviceMaxCurrentmA);
            end
            source.Channels(k).apply(doric.ChannelSettings.cw(currentmA));
            source.Channels(k).start();
            obj.IsSetUp = false;
            obj.recordCurrent(k, currentmA, NaN);
            obj.note('%s continuous at %g mA', char('A' + k - 1), currentmA);
            obj.notifyChanged();
        end

        function lightOff(obj, k)
            % lightOff(k) stops channel k, or every channel with k empty. Safe in any state.
            if ~obj.isControlled()
                return
            end
            try
                if nargin < 2 || isempty(k)
                    obj.LightSource.stopAll();
                    obj.note('all channels stopped');
                else
                    obj.LightSource.Channels(k).stop();
                    obj.note('%s stopped', char('A' + k - 1));
                end
            catch stopError
                obj.note('stop failed: %s', stopError.message);
            end
            obj.IsSetUp = false;
            obj.notifyChanged();
        end

        function beginSession(obj)
            % beginSession() slows the package's polling timer for the session: replies
            % are then read ten times a second while MATLAB waits, not fifty.
            if obj.isControlled()
                obj.LightSource.PollPeriodMs = 100;
            end
        end

        function poll(obj)
            % poll() reads the driver's replies now.
            if obj.isControlled()
                obj.LightSource.poll();
            end
        end

        function record = record(obj)
            % record() is Data.Session.DoricLED's device part: mode, device, limits, every
            % current sent, and the package's own record (settings as sent, latencies).
            record = struct('Mode', obj.Mode, 'Reason', obj.Reason, 'State', obj.state(), ...
                            'CurrentmA', obj.CurrentmA, 'MaxCurrentmA', obj.MaxCurrentmA, ...
                            'Changes', obj.Changes(1:obj.nChanges, :), ...
                            'ChangeColumns', {{'SessionSeconds', 'Channel', 'CurrentmA', 'TrialOrBlock'}}, ...
                            'Package', []);
            if obj.isControlled()
                try
                    package = obj.LightSource.record();
                    if isfield(package, 'Log')
                        package = rmfield(package, 'Log');  % Kept in DeviceLog instead
                    end
                    record.Package = package;
                catch
                    % A record is never worth failing a teardown for.
                end
            end
        end

        function seconds = sessionTime(obj)
            % sessionTime() is seconds since this object was made, the clock of Changes.
            seconds = toc(obj.clock);
        end

        function close(obj)
            % close() switches both channels off and releases the driver. Safe to call
            % more than once; never throws.
            for i = 1:numel(obj.listeners)
                delete(obj.listeners{i});
            end
            obj.listeners = {};
            if obj.isControlled()
                try
                    if isvalid(obj.LightSource)
                        obj.LightSource.disconnect();  % Stops every channel first
                        delete(obj.LightSource);
                        obj.note('disconnected, light off');
                    end
                catch closeError
                    warning('lum:dev:DoricLED:closeFailed', 'Could not release the Doric LED cleanly: %s', ...
                            closeError.message);
                end
                obj.LightSource = [];
            end
            if ~isempty(obj.transport)
                try
                    delete(obj.transport);
                catch
                end
                obj.transport = [];
            end
            obj.IsSetUp = false;
        end

        function delete(obj)
            obj.close();
        end
    end

    methods (Static)
        function folder = locatePackage(folder)
            % locatePackage(folder) is the DoricLED folder to use: the one given, if it
            % holds the package, else wherever the package already is on the MATLAB path;
            % '' if neither.
            folder = strtrim(char(folder));
            if ~isempty(folder) && isfile(fullfile(folder, '+doric', 'LightSource.m'))
                return
            end
            folder = '';
            onPath = which('doric.LightSource');
            if ~isempty(onPath)
                folder = fileparts(fileparts(onPath));
            end
        end
    end

    methods (Access = private)
        function connected(obj, result)
            % What a background connection came to.
            if isfield(result, 'Ok') && isequal(result.Ok, true)
                obj.note('connected: %s, port %s', obj.LightSource.DeviceName, ...
                         num2str(obj.LightSource.Port));
            else
                obj.faultText = result.Message;
                obj.note('connection failed: %s', result.Message);
            end
            obj.notifyChanged();
        end

        function onFault(obj, event)
            obj.faultText = event.Reason;
            obj.note('faulted: %s', event.Reason);
            obj.notifyChanged();
        end

        function text = faultReason(obj)
            text = obj.faultText;
            if isempty(text) && obj.isControlled()
                text = obj.LightSource.FaultReason;
            end
            if isempty(text)
                text = 'no reply';
            end
        end

        function requireReady(obj)
            if ~obj.isControlled() || ~strcmp(obj.state(), 'Ready')
                error('lum:dev:DoricLED:notConnected', ...
                      'The Doric LED driver is not connected (%s).', obj.describeState());
            end
        end

        function recordCurrent(obj, k, currentmA, tag)
            obj.CurrentmA(k) = currentmA;
            if obj.nChanges < obj.MaxChanges
                obj.nChanges = obj.nChanges + 1;
                obj.Changes(obj.nChanges, :) = [toc(obj.clock), k, currentmA, tag];
            end
        end

        function notifyChanged(obj)
            if isvalid(obj)
                notify(obj, 'Changed');
            end
        end
    end
end


function checkCurrents(currentmA, maxCurrentmA)
% Two whole currents within two limits, each limit within the LED's rating.
if numel(currentmA) ~= 2 || numel(maxCurrentmA) ~= 2 || any(~isfinite(currentmA)) ...
        || any(currentmA < 0) || any(currentmA ~= round(currentmA))
    error('lum:dev:DoricLED:badCurrent', 'The LED currents must be two whole numbers of mA, A then B.');
end
if any(currentmA > maxCurrentmA)
    error('lum:dev:DoricLED:overLimit', 'An LED current (%g, %g mA) is above its limit (%g, %g mA).', ...
          currentmA(1), currentmA(2), maxCurrentmA(1), maxCurrentmA(2));
end
end
