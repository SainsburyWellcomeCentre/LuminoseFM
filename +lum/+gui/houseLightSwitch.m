function control = houseLightSwitch(parent, position, houseLight, t)
% lum.gui.houseLightSwitch puts the house light's switch in a session window's header.
%
%   control = lum.gui.houseLightSwitch(parent, position, houseLight, t)
%
% A checkbox that switches the light the moment it is clicked (houseLight.set: PulsePal's
% output 3, D15), and follows the light as it is — a switch made any other way, or one
% PulsePal could not make. Greyed out, and off, when the light is not Switchable (a session
% without light and without PulsePal, lum.dev.DisabledHouseLight). Both live figures have one, lum.OnlinePlots and lum.sleep.Plots,
% in their header.
%
% Arguments:
%   parent      The header panel (a classic figure's uipanel)
%   position    Normalised [x y width height] in it
%   houseLight  The session's lum.dev.HouseLight; [] builds no switch and returns []
%   t           lum.gui.theme
%
% See also: lum.dev.HouseLight, lum.OnlinePlots, lum.sleep.Plots

control = [];
if isempty(houseLight)
    return
end
control = uicontrol(parent, 'Style', 'checkbox', 'Units', 'normalized', 'Position', position, ...
    'String', 'House light', 'Value', double(houseLight.On), 'FontSize', 11, 'FontWeight', 'bold', ...
    'BackgroundColor', t.Background, 'ForegroundColor', t.Ink, ...
    'TooltipString', ['The white house light inside the box (PulsePal output 3). Switches at once, '...
                      'during a trial or a block too; each switch is a BNC1 event in the trial.'], ...
    'Callback', @(source, ~) houseLight.set(get(source, 'Value') == 1));
if ~houseLight.Switchable
    set(control, 'Value', 0, 'Enable', 'off', 'TooltipString', ...
        ['The house light cannot be switched in this session: PulsePal, which drives it, is not '...
         'connected. It stays off.']);
end
houseLight.addListener(@(on) follow(control, on));


function follow(control, on)
% Show a switch made elsewhere.
if isgraphics(control)
    set(control, 'Value', double(on));
end
