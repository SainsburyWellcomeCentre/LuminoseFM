classdef StartupTimes < handle
    % lum.StartupTimes times a session's start, from launch to its first trial or block.
    %
    % The protocol marks the end of each step (lap); a step spent in a dialog is marked as
    % the operator's time, so what the protocol itself costs can be told from how long the
    % operator took to set the session up. lum.dev.open's own breakdown, device by device
    % (devices.openSeconds), is added under 'devices'. The session prints the result as
    % it starts (describe) and stores it once, in Data.Session.Startup (record).
    %
    % Usage:
    %   startup = lum.StartupTimes();
    %   ...                                   % settings, preflight
    %   startup.lap('preflight');
    %   ...                                   % a dialog
    %   startup.lap('setup dialog', true);    % the operator's time
    %   startup.addParts('devices', devices.openSeconds);
    %   fprintf('LuminoseFM: %s\n', startup.describe());
    %   BpodSystem.Data.Session.Startup = startup.record();
    %
    % See also: LuminoseFM, lum.dev.open, lum.sleep.run

    properties (SetAccess = private)
        Names = {}        % Each step, in order
        Seconds = []      % How long it took
        Operator = false(1, 0)  % True for a step spent waiting for the operator (a dialog)
        Parts = struct()  % Named breakdowns of a step (field: step name made valid)
    end

    properties (Access = private)
        clock
        last = 0
    end

    methods
        function obj = StartupTimes()
            obj.clock = tic;
        end

        function lap(obj, name, operator)
            % lap(name) ends a step: the time since the previous lap. lap(name, true)
            % marks it as the operator's time.
            if nargin < 3
                operator = false;
            end
            elapsed = toc(obj.clock);
            obj.Names{end+1} = char(name);
            obj.Seconds(end+1) = elapsed - obj.last;
            obj.Operator(end+1) = logical(operator);
            obj.last = elapsed;
        end

        function addParts(obj, name, parts)
            % addParts(name, parts) keeps a breakdown (a struct of seconds) of step name.
            if isstruct(parts) && ~isempty(fieldnames(parts))
                obj.Parts.(matlab.lang.makeValidName(name)) = parts;
            end
        end

        function seconds = total(obj)
            % total() is the time since the protocol started.
            seconds = toc(obj.clock);
        end

        function text = describe(obj)
            % describe() is one line: the total, the operator's part, and every other
            % step of 0.05 s or more, longest first, with any breakdown in brackets.
            own = ~obj.Operator;
            text = sprintf('ready %.1f s after launch; %.1f s of it the protocol''s own', ...
                           sum(obj.Seconds), sum(obj.Seconds(own)));
            if any(obj.Operator)
                text = sprintf('%s, %.1f s in the dialogs', text, sum(obj.Seconds(obj.Operator)));
            end
            steps = find(own & obj.Seconds >= 0.05);
            [~, order] = sort(obj.Seconds(steps), 'descend');
            parts = cell(1, numel(steps));
            for i = 1:numel(steps)
                k = steps(order(i));
                parts{i} = sprintf('%s %.1f s%s', obj.Names{k}, obj.Seconds(k), obj.partsText(obj.Names{k}));
            end
            if ~isempty(parts)
                text = sprintf('%s: %s', text, strjoin(parts, ', '));
            end
        end

        function record = record(obj)
            % record() is Data.Session.Startup: Steps (Name, Seconds, Operator), Parts,
            % TotalSeconds and OperatorSeconds.
            record = struct('Steps', struct('Name', obj.Names, 'Seconds', num2cell(obj.Seconds), ...
                                            'Operator', num2cell(obj.Operator)), ...
                            'Parts', obj.Parts, 'TotalSeconds', sum(obj.Seconds), ...
                            'OperatorSeconds', sum(obj.Seconds(obj.Operator)));
        end
    end

    methods (Access = private)
        function text = partsText(obj, name)
            text = '';
            field = matlab.lang.makeValidName(name);
            if ~isfield(obj.Parts, field)
                return
            end
            parts = obj.Parts.(field);
            names = fieldnames(parts);
            values = cellfun(@(n) parts.(n), names);
            [values, order] = sort(values, 'descend');
            names = names(order);
            shown = values >= 0.05;
            if ~any(shown)
                return
            end
            items = arrayfun(@(i) sprintf('%s %.1f', names{i}, values(i)), find(shown)', ...
                             'UniformOutput', false);
            text = sprintf(' (%s)', strjoin(items, ', '));
        end
    end
end
