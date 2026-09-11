function cue = cueTiming(S)
% lum.cueTiming says what each part of the cue does, from trial start to the end of the hold.
%
% The cue tells the animal to start a trial. Every enabled component comes on at trial
% start and stays on until the stimulus starts: through the wait for the poke, however
% long that takes, and through the stimulus latency after it (S.Stimulus.Latency, 0 by
% default). It comes back on whenever a broken hold sends the animal back to poke
% again. From stimulus onset each component does one of three things, set per row of
% S.Cue.Components:
%
%   Whole  ThroughStimulus is ticked, or Duration spans the stimulus window: it continues
%          until the hold ends. The default. Free: the hold state keeps it on.
%   Off    Duration is 0: it goes off as the stimulus starts. Free.
%   Timed  Duration is shorter than the window: it goes off that long after stimulus
%          onset. The centre light and air need a global timer for it, for the same
%          reason timed stimulus components do (D9, lum.stim.timerCost); the tone plays
%          a tail of that length instead (lum.stim.CueTone), so it never costs one.
%
% The rule for "spans the window" is lum.stim.isTimed, shared with the stimulus
% components, so the timer budget and the trial builder cannot disagree.
%
% Arguments:
%   S  Settings struct; reads S.Cue.Components and S.Stimulus.Duration
%
% Returns a struct array, one element per enabled component, in settings order:
%   .Type      'CentreLight', 'Tone' or 'Air'
%   .Mode      'Whole', 'Off' or 'Timed'
%   .Duration  Seconds on from stimulus onset: Inf for Whole, 0 for Off, the row's
%              Duration for Timed
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.buildTrialSM, lum.stim.build, lum.stim.timerCost, lum.defaultSettings

cue = struct('Type', {}, 'Mode', {}, 'Duration', {});
window = S.Stimulus.Duration;

for row = S.Cue.Components(:)'
    if ~row.Enabled
        continue
    end
    if ~(row.Duration >= 0)
        error('lum:cueTiming:badDuration', ...
              ['The cue %s is on for %g s into the stimulus. Give 0 to switch it off as '...
               'the stimulus starts, or tick "continues" through the stimulus.'], ...
              readable(row.Type), row.Duration);
    end
    if row.ThroughStimulus || ~lum.stim.isTimed(0, row.Duration, window)
        mode = 'Whole';
        duration = Inf;
    elseif row.Duration == 0
        mode = 'Off';
        duration = 0;
    else
        mode = 'Timed';
        duration = row.Duration;
    end
    cue(end+1) = struct('Type', row.Type, 'Mode', mode, 'Duration', duration); %#ok<AGROW>
end


function text = readable(type)
% 'CentreLight' -> 'centre light'.
text = lower(regexprep(type, '(?<=[a-z])([A-Z])', ' $1'));
