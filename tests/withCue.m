function S = withCue(S, types, afterPoke)
% withCue enables exactly the named cue components, each timed the same after the poke.
%
% The cue is a struct array with a row per component, which is right for the
% operator and verbose in a test that only cares which parts are on. This says it
% in one line.
%
% Usage:
%   S = withCue(S, {'CentreLight'});           % light only, on through the stimulus
%   S = withCue(S, {'Tone'}, 0);               % a tone that stops at the poke
%   S = withCue(S, {'Air'}, 0.3);              % air for 0.3 s after the poke
%   S = withCue(S, {});                        % no cue at all
%
% See also: makeTestContext, lum.cueTiming

types = cellstr(types);
for k = 1:numel(S.Cue.Components)
    S.Cue.Components(k).Enabled = ismember(S.Cue.Components(k).Type, types);
    if nargin < 3
        S.Cue.Components(k).ThroughStimulus = true;
        S.Cue.Components(k).Duration = 0;
    else
        S.Cue.Components(k).ThroughStimulus = false;
        S.Cue.Components(k).Duration = afterPoke;
    end
end
