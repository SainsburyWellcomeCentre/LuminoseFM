function fields = runtimeFields(S)
% lum.gui.runtimeFields describes the runtime parameter tier as a flat list.
%
% The runtime tier is declared once, in lum.defaultSettings, as S.GUI plus the
% S.GUIMeta, S.GUIPanels and S.GUITabs that describe it. Three windows render it: the
% tabbed runtime window and Bpod's own parameter window during the session, and the
% setup dialog before it starts. This is what the tabbed window and the dialog read,
% so that adding a runtime parameter means editing one line of lum.defaultSettings
% and nothing else.
%
% Parameters are returned in the order the panels are laid out: panel by panel in
% the order S.GUIPanels declares them, then in the order each panel lists them.
% Anything in S.GUI that no panel claims lands in a trailing 'Parameters' panel,
% which is what BpodParameterGUI does with it too; any panel no tab claims lands in
% an 'Other' tab.
%
% Arguments:
%   S  Settings struct with .GUI, and optionally .GUIMeta, .GUIPanels and .GUITabs
%
% Returns a struct array, one element per parameter:
%   .Name    Field name in S.GUI
%   .Panel   Panel it belongs to
%   .Tab     Tab that panel belongs to
%   .Label   Human-readable label with units, from GUIMeta.Label; the field name
%            when there is none, which is what BpodParameterGUI shows
%   .Style   'numeric', 'checkbox', 'dropdown', 'text', 'readonly' or 'button'
%   .Items   Choices, for 'dropdown'; empty otherwise
%   .Limits  [min max] for 'numeric', from GUIMeta.Limits; empty when unbounded
%   .Value   The current value
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.defaultSettings, lum.gui.SetupDialog, lum.gui.RuntimeWindow

meta = structOrEmpty(S, 'GUIMeta');
panels = structOrEmpty(S, 'GUIPanels');
tabs = structOrEmpty(S, 'GUITabs');

names = fieldnames(S.GUI);
panelNames = fieldnames(panels);

% Panel by panel, in declaration order, skipping anything a panel names that S.GUI
% does not actually have — a stale panel entry is a typo in the settings, not a
% reason to refuse to open a window.
order = {};
panelOf = struct();
for i = 1:numel(panelNames)
    members = cellstr(panels.(panelNames{i}));
    for k = 1:numel(members)
        if isfield(S.GUI, members{k}) && ~isfield(panelOf, members{k})
            order{end+1} = members{k}; %#ok<AGROW>
            panelOf.(members{k}) = panelNames{i};
        end
    end
end
for i = 1:numel(names)
    if ~isfield(panelOf, names{i})
        order{end+1} = names{i}; %#ok<AGROW>
        panelOf.(names{i}) = 'Parameters';
    end
end

tabOf = struct();
tabNames = fieldnames(tabs);
for i = 1:numel(tabNames)
    members = cellstr(tabs.(tabNames{i}));
    for k = 1:numel(members)
        if ~isfield(tabOf, members{k})
            tabOf.(members{k}) = tabNames{i};
        end
    end
end

fields = struct('Name', order, 'Panel', [], 'Tab', [], 'Label', [], 'Style', [], ...
                'Items', [], 'Limits', [], 'Value', []);
for i = 1:numel(order)
    name = order{i};
    entry = structOrEmpty(meta, name);
    fields(i).Panel = panelOf.(name);
    fields(i).Tab = fieldOr(tabOf, fields(i).Panel, 'Other');
    fields(i).Value = S.GUI.(name);
    fields(i).Label = fieldOr(entry, 'Label', name);
    fields(i).Items = cellstr(fieldOr(entry, 'String', {}));
    fields(i).Limits = fieldOr(entry, 'Limits', []);
    fields(i).Style = styleOf(fieldOr(entry, 'Style', 'edit'), fields(i).Value);
end


function style = styleOf(metaStyle, value)
% Translate BpodParameterGUI's style names into the control the windows build.
switch lower(metaStyle)
    case 'edit'
        if ischar(value) || isstring(value)
            style = 'text';
        else
            style = 'numeric';
        end
    case 'checkbox'
        style = 'checkbox';
    case 'popupmenu'
        style = 'dropdown';
    case 'text'
        style = 'readonly';
    case 'pushbutton'
        % An action to run during a session. There is nothing for it to act on
        % before one starts, so the dialog shows it disabled.
        style = 'button';
    otherwise
        error('lum:gui:runtimeFields:unknownStyle', ...
              ['Unknown GUIMeta style ''%s''. BpodParameterGUI accepts edit, text, '...
               'checkbox, popupmenu and pushbutton.'], metaStyle);
end


function value = structOrEmpty(container, name)
% One struct field, or an empty struct when it is absent or not a struct.
value = struct();
if isstruct(container) && isfield(container, name) && isstruct(container.(name))
    value = container.(name);
end


function value = fieldOr(container, name, default)
% One struct field, or a default when it is absent or empty.
value = default;
if isfield(container, name) && ~isempty(container.(name))
    value = container.(name);
end
