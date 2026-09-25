function mouse = startSessionMouse(behaviours)
% startSessionMouse plays an animal through a whole emulated session, one behaviour per trial.
%
%   mouse = startSessionMouse({correct, retry, {}, ...})
%
% behaviours{k} is what the animal does on trial k: rows {seconds after trial k's state
% machine starts, what, level}. What is an input channel ('Port2'), or one of
%   'Centre'   the centre port (rig port 2)
%   'Correct'  the side port that pays on this trial, read from the running state machine:
%              the one whose poke leads to LeftRewardDelay or RightRewardDelay from
%              WaitForResponse
%   'Wrong'    the other side port
%   'Set:<name>'  types level into the compact runtime window's <name> field, as the
%              operator would; the session reads it when it prepares its next trial
% An empty behaviour ({}) does nothing on that trial. Trials past the list do nothing.
%
% A trial is recognised by the state machine running (Status.InStateMatrix) with
% Data.nTrials trials already recorded: trial k runs while k - 1 are recorded, in the
% emulator's blocking runner. Pokes go in as the console's port buttons do (the 'V'
% override, as startMouse), never through ManualOverride. Keep rows a few hundred
% milliseconds apart: the emulator reads one override per loop and keeps no millisecond
% time. The caller stops and deletes the timer after the session; mouse.UserData.Played
% counts the rows played per trial, and .Error holds the first error the animal met
% ('' when none).
%
% See also: startMouse, animalSessionTest

mouse = timer('ExecutionMode', 'fixedSpacing', 'Period', 0.02, 'BusyMode', 'drop', ...
              'UserData', struct('Trial', 0, 'Next', 1, 'Started', [], 'Error', '', ...
                                 'Played', zeros(1, numel(behaviours)), 'Correct', {cell(1, numel(behaviours))}));
mouse.TimerFcn = @(source, ~) play(source, behaviours);
start(mouse);
end

function play(source, behaviours)
% Never lets an error out: a timer whose callback errors stops, and the session would go
% on with no animal. The first error is kept in UserData.Error for the caller.
try
    step(source, behaviours);
catch playError
    state = source.UserData;
    if isempty(state.Error)
        state.Error = playError.message;
        source.UserData = state;
    end
end
end

function step(source, behaviours)
global BpodSystem %#ok<GVMIS>
state = source.UserData;
if ~isfield(BpodSystem.Status, 'InStateMatrix') || BpodSystem.Status.InStateMatrix ~= 1
    return
end
recorded = 0;
if isfield(BpodSystem.Data, 'nTrials')
    recorded = BpodSystem.Data.nTrials;
end
if recorded + 1 ~= state.Trial
    state.Trial = recorded + 1;   % A new trial's state machine is running
    state.Next = 1;
    state.Started = tic;
end
trial = state.Trial;
if trial > numel(behaviours) || state.Next > size(behaviours{trial}, 1) || BpodSystem.ManualOverrideFlag ~= 0
    source.UserData = state;
    return
end
script = behaviours{trial};
if toc(state.Started) >= script{state.Next, 1}
    what = script{state.Next, 2};
    level = script{state.Next, 3};
    if strncmp(what, 'Set:', 4)
        setParameter(what(5:end), level);
    else
        [channel, side] = resolve(what);
        index = find(strcmp(BpodSystem.StateMachineInfo.InputChannelNames, channel), 1);
        BpodSystem.HardwareState.InputState(index) = level;
        BpodSystem.VirtualManualOverrideBytes = ['V' index-1 level];
        BpodSystem.ManualOverrideFlag = 1;
        if ~isempty(side)
            state.Correct{trial} = side;
        end
    end
    state.Next = state.Next + 1;
    state.Played(trial) = state.Played(trial) + 1;
end
source.UserData = state;
end

function [channel, correctSide] = resolve(what)
% The input channel for a role, and (for Correct/Wrong) which side paid.
correctSide = [];
switch what
    case 'Centre'
        channel = 'Port2';
    case {'Correct', 'Wrong'}
        correctSide = payingSide();
        if strcmp(what, 'Correct')
            side = correctSide;
        else
            side = 3 - correctSide;
        end
        ports = {'Port1', 'Port3'};
        channel = ports{side};
    otherwise
        channel = what;
end
end

function side = payingSide()
% 1 when a left poke in WaitForResponse leads to LeftRewardDelay, else 2.
global BpodSystem %#ok<GVMIS>
sma = BpodSystem.StateMatrix;
state = find(strcmp(sma.StateNames, 'WaitForResponse'), 1);
event = find(strcmp(BpodSystem.StateMachineInfo.EventNames, 'Port1In'), 1);
target = sma.InputMatrix(state, event);
side = 2;
if target >= 1 && target <= numel(sma.StateNames) && strcmp(sma.StateNames{target}, 'LeftRewardDelay')
    side = 1;
end
end

function setParameter(name, value)
% Type a value into Bpod's compact parameter window, as the operator would.
global BpodSystem %#ok<GVMIS>
index = find(strcmp(BpodSystem.GUIData.ParameterGUI.ParamNames, name), 1);
set(BpodSystem.GUIHandles.ParameterGUI.Params(index), 'String', num2str(value));
end
