classdef HelpLine < handle
    % lum.gui.HelpLine shows what a field means, at the bottom of a window.
    %
    % A label or a limit says little about a parameter such as bias correction, and a
    % tooltip only shows after the pointer rests on the field. The help line is one
    % strip of text at the foot of the window that describes the field the operator is
    % on: the one under the pointer, the dropdown just opened, the value just changed.
    % It stays until another described field takes its place, so it can be read while
    % typing.
    %
    % Descriptions come from where the field is declared: GUIMeta.<name>.Help for the
    % runtime tier (lum.defaultSettings), and a component's Tooltip for everything else,
    % so a field that already explains itself on hover needs nothing new.
    %
    % Works in uifigures (the setup dialogs) and classic figures (the tabbed runtime
    % window). Neither kind of edit field reports gaining focus, so a field is found by
    % where it is: the figure's WindowButtonMotionFcn compares the pointer with each
    % described component's position, recomputed when the window's size or its selected
    % tabs change, and every few seconds for layouts that change by themselves. Value-changed callbacks are chained, not replaced, so the
    % field's own callback runs as before.
    %
    % Usage:
    %   help = lum.gui.HelpLine(fig, label, 'Point at a field to see what it does.');
    %   help.register(control, 'What this control does.');
    %   help.registerTooltips();          % every component with a Tooltip, once built
    %   help.show('Anything');            % set the text directly
    %
    % See also: lum.gui.SetupDialog, lum.gui.SleepSetupDialog, lum.gui.RuntimeWindow

    properties (SetAccess = private)
        Label        % The text component the descriptions are written into
        Text = ''    % The description on show
    end

    properties (Access = private)
        Figure
        Handles = {}          % Described components
        Texts = {}            % Their descriptions
        Tabs = {}             % The uitab each sits on, or [] when on none
        Rects = zeros(0, 4)   % Their absolute pixel rectangles, cached
        CacheKey = {}         % What the cached rectangles were computed for
        CacheTimer = []       % tic of the last computation; stale after a few seconds
        Shown = 0             % Index of the component described now; 0 for none
        DefaultText = ''
    end

    methods
        function obj = HelpLine(fig, label, defaultText)
            if nargin < 3
                defaultText = '';
            end
            obj.Figure = fig;
            obj.Label = label;
            obj.DefaultText = defaultText;
            obj.show(defaultText);
            fig.WindowButtonMotionFcn = @(~, ~) obj.pointerMoved();
        end

        function register(obj, handles, text)
            % register(handles, text) describes one component, or several that share a
            % description (a label and its field).
            if isempty(text)
                return
            end
            if ~iscell(handles)
                handles = num2cell(handles);
            end
            for i = 1:numel(handles)
                handle = handles{i};
                if isempty(handle) || ~isvalid(handle)
                    continue
                end
                known = find(cellfun(@(h) isequal(h, handle), obj.Handles), 1);
                if ~isempty(known)
                    obj.Texts{known} = text;
                    continue
                end
                obj.Handles{end+1} = handle;
                obj.Texts{end+1} = text;
                obj.Tabs{end+1} = ancestorTab(handle);
                obj.chainCallbacks(handle, numel(obj.Handles));
            end
            obj.CacheKey = {};
        end

        function registerTooltips(obj)
            % registerTooltips() describes every component in the window that has a
            % tooltip and no description yet, with that tooltip.
            candidates = findall(obj.Figure);
            for i = 1:numel(candidates)
                handle = candidates(i);
                tip = tooltipOf(handle);
                if isempty(tip) || any(cellfun(@(h) isequal(h, handle), obj.Handles))
                    continue
                end
                obj.register(handle, tip);
            end
        end

        function show(obj, text)
            % show(text) puts a description on the line.
            if isempty(obj.Label) || ~isvalid(obj.Label)
                return
            end
            obj.Text = char(text);
            if isprop(obj.Label, 'Text')
                obj.Label.Text = obj.Text;
            else
                set(obj.Label, 'String', obj.Text);
            end
        end

        function describeAt(obj, point)
            % describeAt(point) shows the description of the component under a pixel
            % point [x y] of the figure, if there is one. What the pointer callback
            % does; public so it can be tested without a pointer.
            obj.refreshRects();
            if isempty(obj.Rects)
                return
            end
            inside = point(1) >= obj.Rects(:, 1) & point(1) <= obj.Rects(:, 1) + obj.Rects(:, 3) ...
                   & point(2) >= obj.Rects(:, 2) & point(2) <= obj.Rects(:, 2) + obj.Rects(:, 4);
            index = find(inside, 1, 'last');   % The innermost, when components nest
            if ~isempty(index) && index ~= obj.Shown
                obj.Shown = index;
                obj.show(obj.Texts{index});
            end
        end

        function describe(obj, handle)
            % describe(handle) shows a registered component's description.
            index = find(cellfun(@(h) isequal(h, handle), obj.Handles), 1);
            if ~isempty(index)
                obj.Shown = index;
                obj.show(obj.Texts{index});
            end
        end
    end

    methods (Access = private)
        function pointerMoved(obj)
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end
            try
                obj.describeAt(obj.Figure.CurrentPoint);
            catch
                % A component deleted under the pointer; the next move recomputes.
                obj.CacheKey = {};
            end
        end

        function refreshRects(obj)
            % Recompute the rectangles when the window or its selected tabs changed.
            key = [{obj.Figure.Position}, cellfun(@selectedState, obj.Tabs, 'UniformOutput', false)];
            if isequal(key, obj.CacheKey) && ~isempty(obj.CacheTimer) && toc(obj.CacheTimer) < 3
                return
            end
            obj.CacheTimer = tic;
            n = numel(obj.Handles);
            rects = NaN(n, 4);
            for i = 1:n
                handle = obj.Handles{i};
                if ~isvalid(handle) || ~isShowing(handle, obj.Tabs{i})
                    continue
                end
                try
                    rects(i, :) = getpixelposition(handle, true);
                catch
                    % Not a positionable component; it is never under the pointer.
                end
            end
            obj.Rects = rects;
            obj.CacheKey = key;
        end

        function chainCallbacks(obj, handle, index)
            % Show the description when the field is used, keeping its own callback.
            for name = {'ValueChangedFcn', 'ValueChangingFcn', 'DropDownOpeningFcn', ...
                        'ButtonPushedFcn', 'CellEditCallback', 'CellSelectionCallback', 'Callback'}
                if ~isprop(handle, name{1})
                    continue
                end
                original = handle.(name{1});
                handle.(name{1}) = @(source, event) obj.used(index, original, source, event);
            end
        end

        function used(obj, index, original, source, event)
            if index <= numel(obj.Texts)
                obj.Shown = index;
                obj.show(obj.Texts{index});
            end
            if isempty(original)
                return
            end
            if isa(original, 'function_handle')
                original(source, event);
            elseif iscell(original)
                original{1}(source, event, original{2:end});
            end
        end
    end
end


function tab = ancestorTab(handle)
% The uitab a component sits on, or [] when it sits on none.
tab = [];
parent = handle;
while ~isempty(parent) && isprop(parent, 'Parent')
    parent = parent.Parent;
    if isa(parent, 'matlab.ui.container.Tab')
        tab = parent;
        return
    end
    if isa(parent, 'matlab.ui.Figure')
        return
    end
end
end


function state = selectedState(tab)
% Whether a tab is the one showing, for the cache key.
state = isShowing([], tab);
end


function tf = isShowing(handle, tab)
% Whether a component can be under the pointer: visible, and on the selected tab.
tf = true;
if ~isempty(handle) && isprop(handle, 'Visible') && ~strcmp(char(handle.Visible), 'on')
    tf = false;
    return
end
while ~isempty(tab)
    if ~isvalid(tab)
        tf = false;
        return
    end
    group = tab.Parent;
    if ~isequal(group.SelectedTab, tab)
        tf = false;
        return
    end
    tab = ancestorTab(group);
end
end


function tip = tooltipOf(handle)
% A component's tooltip as text, or '' when it has none.
tip = '';
if ~isprop(handle, 'Tooltip')
    return
end
value = handle.Tooltip;
if iscell(value)
    value = strjoin(cellstr(value), ' ');
end
tip = strtrim(char(string(value)));
end
