function text = describeStrategy(S)
% lum.describeStrategy says in one line which strategy correction levers a session runs.
%
% Strategy correction (D23) is three levers against side-port habits, each a runtime
% setting: what a side poke before the response window does (S.GUI.SidePokeBeforeChoice),
% bias correction and what it corrects for (lum.BiasCorrection), and the trial order
% (lum.Blocks). The console says it as a session starts, and the session log under Settings.
%
% Usage:
%   text = lum.describeStrategy(S)
%
% Returns one line, without a full stop, e.g. 'side pokes before the response ignored; bias
% correction 0.5, for side bias, over the last 20 choices; trial order random'.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also lum.BiasCorrection, lum.Blocks, lum.buildTrialSM

sidePokes = 'side pokes before the response ignored';
if isfield(S.GUI, 'SidePokeBeforeChoice')
    switch S.GUI.SidePokeBeforeChoice
        case 2
            sidePokes = sprintf('a side poke before the response delays the trial %g s', ...
                                S.GUI.SidePokeDelay);
        case 3
            sidePokes = 'a side poke before the response ends the trial';
    end
end
order = lum.Blocks.describe(S);
if lum.Blocks.isOn(S)
    bias = 'bias correction and the run limit do not act in blocks';
else
    bias = lum.BiasCorrection.describe(S);
end
text = sprintf('%s; %s; %s', sidePokes, bias, order);
