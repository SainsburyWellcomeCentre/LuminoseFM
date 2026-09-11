classdef Device < handle
    % lum.dev.Device is the common base for the protocol's hardware shims.
    %
    % Every device that the protocol talks to has two implementations: a real
    % one that opens a port, and a null one that logs what it would have done.
    % Which one is constructed is decided once, at session startup, from
    % BpodSystem.EmulatorMode and from what the connected machine reports (see
    % lum.dev.open). No other file in the protocol tests for emulator mode.
    %
    % Subclasses implement the device's own methods; this class only provides
    % the availability flag and the log that makes an emulated session
    % inspectable afterwards.

    properties (SetAccess = protected)
        Name        % Human-readable device name, used in log lines
        Available   % True if this shim talks to real hardware
        Log         % Cell array of strings: what the device did, or would have done
    end

    properties (Access = private)
        nLogged = 0         % Number of lines written into Log
        maxLogLines = 2000  % Ceiling, so a long emulated session cannot grow without bound
        announced           % Containers.Map of messages already printed, to keep the console quiet
    end

    methods
        function obj = Device(name, available)
            obj.Name = name;
            obj.Available = available;
            obj.Log = cell(1, obj.maxLogLines);
            obj.announced = containers.Map('KeyType', 'char', 'ValueType', 'logical');
        end

        function note(obj, fmt, varargin)
            % note() records an action in the device log.
            %
            % Called by both the real and the null shims, so that the log reads the
            % same either way and an emulated session can be checked against a real
            % one. Never prints: printing on every trial would cost time in the
            % trial loop. Use announce() for messages the operator must see.
            if obj.nLogged >= obj.maxLogLines
                return
            end
            obj.nLogged = obj.nLogged + 1;
            obj.Log{obj.nLogged} = sprintf(fmt, varargin{:});
        end

        function announce(obj, fmt, varargin)
            % announce() prints a message to the command window, but only the first
            % time that exact message is seen. Session setup uses this to explain
            % which shim is in play without repeating itself once per trial.
            message = sprintf(fmt, varargin{:});
            if ~isKey(obj.announced, message)
                obj.announced(message) = true;
                fprintf('  [%s] %s\n', obj.Name, message);
            end
            obj.note('%s', message);
        end

        function entries = log(obj)
            % log() returns the log lines recorded so far, trimmed to length.
            entries = obj.Log(1:obj.nLogged);
        end

        function close(obj) %#ok<MANU> % Subclasses override where there is a port to release
            % close() releases any hardware resource. Safe to call more than once.
        end
    end
end
