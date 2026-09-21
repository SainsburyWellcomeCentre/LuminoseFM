function mouse = startMouse(script)
% startMouse plays the animal's pokes into the emulated state machine from a timer.
%
%   mouse = startMouse({0.3, 'Port2', 1; 0.9, 'Port2', 0; 1.3, 'Port1', 1; ...})
%
% Each row is {seconds after the state machine starts, input channel, level}. The rows are
% put into the running emulated state machine one at a time, the way the console's port
% buttons do (ManualOverride's 'V' message), but without ManualOverride itself, whose
% console refresh and drawnow must not run from a timer (emulatorSessionTest). Keep rows
% a few hundred milliseconds apart: the emulator reads one override per loop. The caller
% stops and deletes the timer after RunStateMachine returns; mouse.UserData.Next - 1 is
% how many rows were played.
%
% See also: startHouseLightClicker, stateMachineTest

mouse = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.02, 'BusyMode', 'drop', ...
              'UserData', struct('Next', 1, 'Started', []));
mouse.TimerFcn = @(source, ~) play(source, script);
start(mouse);
end

function play(source, script)
global BpodSystem %#ok<GVMIS>
state = source.UserData;
if state.Next > size(script, 1)
    stop(source);
    return
end
if isempty(state.Started)
    if BpodSystem.Status.InStateMatrix ~= 1
        return
    end
    state.Started = tic;
end
if toc(state.Started) >= script{state.Next, 1} && BpodSystem.ManualOverrideFlag == 0
    index = find(strcmp(BpodSystem.StateMachineInfo.InputChannelNames, script{state.Next, 2}), 1);
    level = script{state.Next, 3};
    BpodSystem.HardwareState.InputState(index) = level;
    BpodSystem.VirtualManualOverrideBytes = ['V' index-1 level];
    BpodSystem.ManualOverrideFlag = 1;
    state.Next = state.Next + 1;
end
source.UserData = state;
end
