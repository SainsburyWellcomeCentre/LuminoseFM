function clicker = startHouseLightClicker(ready)
% startHouseLightClicker clicks a session window's House light box once, while a state machine runs.
%
%   clicker = startHouseLightClicker(ready)
%
% The operator's click, played by a MATLAB timer: it waits for the box to exist, for a
% state machine to be running and for ready() to be true, then flips the box and runs its
% callback, as a click does. One click, and nothing sent to the console, so none of the
% trouble of driving ManualOverride from a timer (emulatorSessionTest). The caller stops and
% deletes the timer after the session; clicker.UserData.Clicked says whether it clicked and
% .Level which level it asked for.
%
% Arguments:
%   ready  Function returning true once the session is far enough in to click
%
% See also: emulatorSessionTest, sleepSessionTest, lum.gui.houseLightSwitch

clicker = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.05, 'BusyMode', 'drop', ...
                'UserData', struct('Clicked', false, 'Level', NaN));
clicker.TimerFcn = @(source, ~) tryClick(source, ready);
start(clicker);
end

function tryClick(source, ready)
global BpodSystem %#ok<GVMIS>
if source.UserData.Clicked || BpodSystem.Status.InStateMatrix ~= 1 || ~ready()
    return
end
box = findall(groot, 'Type', 'uicontrol', 'Style', 'checkbox', 'String', 'House light');
if isempty(box)
    return
end
box = box(1);
box.Value = 1 - box.Value;
source.UserData = struct('Clicked', true, 'Level', box.Value);
box.Callback(box, []);
stop(source);
end
