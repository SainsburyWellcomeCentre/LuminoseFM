function relabelParameterGUI(S)
% lum.gui.relabelParameterGUI puts readable labels on the runtime parameter window.
%
% BpodParameterGUI labels every control with the field name of the parameter, so
% the window reads 'PostStimulusHold' and 'PortLightIntensity' and says nothing
% about units — and a MATLAB field name cannot say it, because it has no room for
% a space or a bracket. The names are also what the data file records and what
% the code refers to, so renaming them to read better is not an option either.
%
% So the label and the name are separated: S.GUIMeta.<param>.Label carries the
% readable text, and this function writes it over the labels BpodParameterGUI has
% already created. Nothing is rebuilt and no callback is touched; only the label
% text and its alignment change, so sync, styles and change detection go on
% working exactly as Bpod wrote them.
%
% Call it once, straight after BpodParameterGUI('init', S). It does nothing at
% all if the handles are not where this version of Bpod put them, because a
% cosmetic touch-up must never be what stops a session starting.
%
% See also: lum.defaultSettings, lum.gui.runtimeFields, BpodParameterGUI

global BpodSystem %#ok<GVMIS> % Bpod's own session object

if ~isfield(S, 'GUIMeta') || ~isstruct(S.GUIMeta)
    return
end
try
    handles = BpodSystem.GUIHandles.ParameterGUI.Labels;
    names = BpodSystem.GUIData.ParameterGUI.ParamNames;
catch
    return  % An older or newer BpodParameterGUI; the default labels stand
end

for i = 1:min(numel(handles), numel(names))
    name = names{i};
    if ~isfield(S.GUIMeta, name) || ~isfield(S.GUIMeta.(name), 'Label') ...
            || isempty(S.GUIMeta.(name).Label)
        continue
    end
    if ~ishandle(handles(i))
        continue
    end
    % Right-aligned, so each label sits against the field it names rather than
    % floating in the middle of a 200-pixel column.
    set(handles(i), 'String', S.GUIMeta.(name).Label, 'HorizontalAlignment', 'right');
end
