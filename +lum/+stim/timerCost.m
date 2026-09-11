function nTimers = timerCost(S)
% lum.stim.timerCost counts the global timers the non-light stimulus components need.
%
% A component that is on for the whole centre hold is an output action of the hold
% state and costs nothing. One that switches on after stimulus onset, or off
% before the window ends, needs a global timer to do it: the hold is a single state,
% because leaving the centre port has to end it at any instant, so there is no
% later state to switch the component in.
%
% Sounds never cost a timer — a delayed onset is silence at the start of the loaded
% waveform, and a cue tone that stops early is a tail that replaces its loop — so only
% the centre light, the air valve and the side port light count. The side light costs
% at most one: only the rewarded side's light is used on a trial. A cue centre light
% or cue air that goes off part way through the stimulus costs one as well
% (lum.cueTiming): it is switched off inside the hold, like a timed component.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.stim.isTimed, lum.cueTiming, lum.timerBudget, lum.stim.build

nTimers = 0;
window = S.Stimulus.Duration;
for component = S.Stimulus.Components(:)'
    if component.Enabled && ismember(component.Type, {'Air', 'CentreLight'}) ...
            && lum.stim.isTimed(component.Onset, component.Duration, window)
        nTimers = nTimers + 1;
    end
end
if isTimedLight(S.Left.Light, window) || isTimedLight(S.Right.Light, window)
    nTimers = nTimers + 1;
end
for part = lum.cueTiming(S)
    if ismember(part.Type, {'Air', 'CentreLight'}) && strcmp(part.Mode, 'Timed')
        nTimers = nTimers + 1;
    end
end


function tf = isTimedLight(light, window)
% A side light that is enabled and does not span the whole window.
tf = light.Enabled && lum.stim.isTimed(light.Onset, light.Duration, window);
