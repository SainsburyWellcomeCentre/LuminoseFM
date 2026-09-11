classdef RuntimeWindow < handle
    % lum.gui.RuntimeWindow is the parameter window the operator uses during a session.
    %
    % It shows the runtime tier (S.GUI) and nothing else, synced once per trial: a
    % value the operator changes takes effect on the next trial prepared. Two forms:
    %
    %   'Tabbed'   A window of its own, in tabs (S.GUITabs) of panels (S.GUIPanels),
    %              with readable labels and units, limits enforced as values are
    %              typed, and a header that says which trial is running and what
    %              comes next. Built from classic uicontrols, so creating it is quick
    %              and syncing it costs a few property reads per parameter.
    %   'Compact'  Bpod's own BpodParameterGUI, every panel on one page, relabelled
    %              by lum.gui.relabelParameterGUI. The reduced form, for emulator
    %              sessions and for anyone who prefers Bpod's window.
    %
    % S.Session.RuntimeWindow chooses; 'Automatic' means tabbed on the rig and compact
    % under the emulator, and LuminoseFM resolves it, because only the device layer
    % knows which is running.
    %
    % Usage:
    %   runtime = lum.gui.RuntimeWindow(S, 'Mode', 'Tabbed', 'Subject', 'M123');
    %   S = runtime.sync(S);            % once per trial, in the prepare window
    %   runtime.showStatus('Trial 12 running; next: B only');
    %   runtime.close();
    %
    % The sync rule is BpodParameterGUI's: a value changed in the window since the
    % last sync wins; otherwise a value the protocol changed in S is written back to
    % the window. Closing the window does not stop the session; sync then leaves S as
    % it is.
    %
    % See also: lum.gui.runtimeFields, lum.defaultSettings, BpodParameterGUI

    properties (SetAccess = private)
        Mode     % 'Tabbed' or 'Compact'
        Figure   % The window, or [] once closed
    end

    properties (Access = private)
        fields       % Struct array from lum.gui.runtimeFields
        controls     % One uicontrol per field
        lastValues   % Value of each field at the last sync
        status       % Header text control showing the running trial
    end

    methods
        function obj = RuntimeWindow(S, varargin)
            global BpodSystem %#ok<GVMIS> % Figures are registered so Bpod closes them at Stop

            p = inputParser;
            p.FunctionName = 'lum.gui.RuntimeWindow';
            addParameter(p, 'Mode', 'Tabbed', @(x) ismember(x, {'Tabbed', 'Compact'}));
            addParameter(p, 'Subject', '', @(x) ischar(x) || isstring(x));
            addParameter(p, 'Visible', 'on');
            parse(p, varargin{:});
            obj.Mode = p.Results.Mode;

            if strcmp(obj.Mode, 'Compact')
                BpodParameterGUI('init', S);
                lum.gui.relabelParameterGUI(S);
                obj.Figure = BpodSystem.ProtocolFigures.ParameterGUI;
                return
            end

            obj.fields = lum.gui.runtimeFields(S);
            obj.buildTabbed(char(p.Results.Subject), p.Results.Visible);
            if ~isempty(BpodSystem) && isobject(BpodSystem)
                BpodSystem.ProtocolFigures.LuminoseRuntimeWindow = obj.Figure;
            end
        end

        function S = sync(obj, S)
            % sync(S) exchanges values with the window: see the class help.
            if strcmp(obj.Mode, 'Compact')
                S = BpodParameterGUI('sync', S);
                return
            end
            if isempty(obj.Figure) || ~isvalid(obj.Figure)
                return
            end
            for i = 1:numel(obj.fields)
                field = obj.fields(i);
                control = obj.controls(i);
                last = obj.lastValues{i};
                current = S.GUI.(field.Name);
                switch field.Style
                    case 'numeric'
                        shown = str2double(get(control, 'String'));
                        if isnan(shown)
                            shown = last;
                        end
                        shown = clampTo(shown, field.Limits);
                        if single(shown) ~= single(last)
                            S.GUI.(field.Name) = shown;
                        elseif single(current) ~= single(last)
                            set(control, 'String', num2str(current, 8));
                        end
                    case {'checkbox', 'dropdown'}
                        shown = get(control, 'Value');
                        if shown ~= last
                            S.GUI.(field.Name) = shown;
                        elseif current ~= last
                            set(control, 'Value', current);
                        end
                    case 'text'
                        shown = get(control, 'String');
                        if ~strcmp(shown, last)
                            S.GUI.(field.Name) = shown;
                        elseif ~strcmp(current, last)
                            set(control, 'String', current);
                        end
                    otherwise
                        set(control, 'String', num2str(current));
                end
                obj.lastValues{i} = S.GUI.(field.Name);
            end
        end

        function showStatus(obj, text)
            % showStatus(text) puts one line in the header: the running trial, what next.
            if strcmp(obj.Mode, 'Tabbed') && ~isempty(obj.status) && isvalid(obj.status)
                set(obj.status, 'String', text);
            end
        end

        function close(obj)
            % close() closes a tabbed window. Bpod closes its own compact window at Stop.
            if strcmp(obj.Mode, 'Tabbed') && ~isempty(obj.Figure) && isvalid(obj.Figure)
                delete(obj.Figure);
            end
            obj.Figure = [];
        end
    end

    methods (Access = private)
        function buildTabbed(obj, subject, visible)
            % Lay the window out: header, then one tab per S.GUITabs entry.
            t = lum.gui.theme();
            rowHeight = 30;
            panelTitle = 26;
            panelGap = 10;
            width = 460;
            headerHeight = 64;

            tabNames = unique({obj.fields.Tab}, 'stable');
            tabHeights = zeros(1, numel(tabNames));
            for k = 1:numel(tabNames)
                inTab = obj.fields(strcmp({obj.fields.Tab}, tabNames{k}));
                nPanels = numel(unique({inTab.Panel}));
                tabHeights(k) = nPanels * (panelTitle + panelGap) + numel(inTab) * rowHeight + 20;
            end
            bodyHeight = max(tabHeights) + 34;
            height = headerHeight + bodyHeight;

            obj.Figure = figure('Name', 'LuminoseFM - runtime parameters', 'NumberTitle', 'off', ...
                                'MenuBar', 'none', 'ToolBar', 'none', 'Resize', 'off', ...
                                'Color', t.Background, 'Visible', visible, ...
                                'Position', [60 80 width height]);

            % Header: a small logo, the subject, and the live trial line.
            logoImage = lum.gui.logo(48);
            if ~isempty(logoImage)
                logoAxes = axes('Parent', obj.Figure, 'Units', 'pixels', ...
                                'Position', [12 height - 56 48 48], 'Visible', 'off');
                image(logoAxes, logoImage);
                axis(logoAxes, 'image', 'off');
            end
            titleText = 'LuminoseFM';
            if ~isempty(subject)
                titleText = sprintf('LuminoseFM  |  %s', subject);
            end
            uicontrol(obj.Figure, 'Style', 'text', 'String', titleText, 'FontSize', 13, ...
                      'FontWeight', 'bold', 'HorizontalAlignment', 'left', ...
                      'BackgroundColor', t.Background, 'ForegroundColor', t.Ink, ...
                      'Position', [70 height - 32 width - 80 22]);
            obj.status = uicontrol(obj.Figure, 'Style', 'text', ...
                                   'String', 'Waiting for the first trial', 'FontSize', 10, ...
                                   'HorizontalAlignment', 'left', 'BackgroundColor', t.Background, ...
                                   'ForegroundColor', t.Muted, ...
                                   'Position', [70 height - 56 width - 80 20]);

            group = uitabgroup(obj.Figure, 'Units', 'pixels', ...
                               'Position', [6 4 width - 12 bodyHeight]);
            obj.controls = gobjects(1, numel(obj.fields));
            obj.lastValues = cell(1, numel(obj.fields));

            for k = 1:numel(tabNames)
                tab = uitab(group, 'Title', tabNames{k}, 'BackgroundColor', t.Background);
                inTab = find(strcmp({obj.fields.Tab}, tabNames{k}));
                panelNames = unique({obj.fields(inTab).Panel}, 'stable');
                top = bodyHeight - 40;
                for j = 1:numel(panelNames)
                    members = inTab(strcmp({obj.fields(inTab).Panel}, panelNames{j}));
                    panelHeight = panelTitle + numel(members) * rowHeight;
                    panel = uipanel(tab, 'Units', 'pixels', 'Title', readable(panelNames{j}), ...
                                    'FontWeight', 'bold', 'FontSize', 10, ...
                                    'ForegroundColor', t.Accent, 'BackgroundColor', t.Panel, ...
                                    'HighlightColor', t.Faint, 'BorderType', 'line', ...
                                    'Position', [8 top - panelHeight width - 32 panelHeight]);
                    for r = 1:numel(members)
                        i = members(r);
                        y = panelHeight - panelTitle - r * rowHeight + 6;
                        uicontrol(panel, 'Style', 'text', 'String', obj.fields(i).Label, ...
                                  'HorizontalAlignment', 'right', 'FontSize', 10, ...
                                  'BackgroundColor', t.Panel, 'ForegroundColor', t.Ink, ...
                                  'Position', [8 y - 2 238 20]);
                        obj.controls(i) = obj.makeControl(panel, i, [256 y 160 24], t);
                        obj.lastValues{i} = obj.fields(i).Value;
                    end
                    top = top - panelHeight - panelGap;
                end
            end
        end

        function control = makeControl(obj, parent, i, position, t)
            % One uicontrol for one runtime parameter, in the style GUIMeta declares.
            % Tagged with the parameter name, so a control can be found by what it sets.
            field = obj.fields(i);
            common = {'FontSize', 10, 'BackgroundColor', t.Panel, 'ForegroundColor', t.Ink, ...
                      'Position', position, 'Tag', field.Name};
            switch field.Style
                case 'numeric'
                    control = uicontrol(parent, 'Style', 'edit', 'String', num2str(field.Value, 8), ...
                                        common{:}, 'Callback', @(source, ~) obj.onEdit(source, i));
                case 'checkbox'
                    control = uicontrol(parent, 'Style', 'checkbox', 'Value', field.Value, ...
                                        'String', '', common{:});
                case 'dropdown'
                    control = uicontrol(parent, 'Style', 'popupmenu', 'String', field.Items, ...
                                        'Value', field.Value, common{:});
                case 'text'
                    control = uicontrol(parent, 'Style', 'edit', 'String', field.Value, common{:});
                otherwise
                    control = uicontrol(parent, 'Style', 'text', 'String', num2str(field.Value), ...
                                        common{:});
            end
        end

        function onEdit(obj, source, i)
            % As a number is typed: refuse text that is not a number, and hold it to
            % its limits, so the operator sees what the next trial will use.
            value = str2double(get(source, 'String'));
            if isnan(value)
                value = obj.lastValues{i};
            end
            set(source, 'String', num2str(clampTo(value, obj.fields(i).Limits), 8));
        end
    end
end


function value = clampTo(value, limits)
% Hold a value within [min max]; no limits, no change.
if numel(limits) == 2
    value = min(max(value, limits(1)), limits(2));
end
end


function text = readable(name)
% 'HoldShaping' -> 'Hold shaping'.
text = regexprep(name, '(?<=[a-z])([A-Z])', ' ${lower($1)}');
end
