function requester = startLEDRequest(ready)
% startLEDRequest asks the LED window for a new current on channel A once, as a trial runs.
%
%   requester = startLEDRequest(ready)
%
% The operator's Apply, played by a MATLAB timer: it waits for the LED window to exist, for a
% state machine to be running and for ready() to be true, then types into channel A's field
% half of what it shows and presses Apply, as the operator does (lum.gui.DoricWindow). One
% request, and nothing sent to the console. The caller stops and deletes the timer after the
% session; requester.UserData.Requested says whether it asked.
%
% Arguments:
%   ready  Function returning true once the session is far enough in to ask
%
% See also emulatorSessionTest, startHouseLightClicker, lum.gui.DoricWindow

requester = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.05, 'BusyMode', 'drop', ...
                  'UserData', struct('Requested', false));
requester.TimerFcn = @(source, ~) tryRequest(source, ready);
start(requester);
end

function tryRequest(source, ready)
global BpodSystem %#ok<GVMIS>
if source.UserData.Requested || BpodSystem.Status.InStateMatrix ~= 1 || ~ready()
    return
end
apply = findall(groot, 'Type', 'uibutton', 'Text', 'Apply');
if isempty(apply)
    return
end
% Channel A's field and Apply are on the window's upper row.
window = ancestor(apply(1), 'figure');
fieldA = upperOf(findall(window, 'Type', 'uinumericeditfield'));
applyA = upperOf(findall(window, 'Type', 'uibutton', 'Text', 'Apply'));
fieldA.Value = fieldA.Value / 2;
fieldA.ValueChangedFcn(fieldA, []);
applyA.ButtonPushedFcn(applyA, []);
source.UserData = struct('Requested', true);
stop(source);
end

function component = upperOf(components)
% The component on the lowest-numbered row of its grid.
rows = arrayfun(@(c) c.Layout.Row, components);
[~, first] = min(rows);
component = components(first);
end
