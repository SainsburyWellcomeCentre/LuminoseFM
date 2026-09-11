function [cue, stimulus] = build(S)
% lum.stim.build turns the settings into the session's cue and stimulus components.
%
% The only place that maps settings onto component objects:
%
%   Cue       One component per enabled row of S.Cue.Components, in row order
%             (lum.cueTiming): CentreLight -> PortLight('Centre', 'Cue'),
%             Tone -> CueTone, Air -> Air('Cue').
%   Stimulus  The light pattern when the session uses light; each enabled row of
%             S.Stimulus.Components (Air, CentreLight, Tone -> the group's tone);
%             the rewarded side's port light if either side's is enabled; and the
%             rewarded side's tone if either side's is enabled.
%
% Components are built once per session and reused every trial; anything that
% varies by trial is resolved from the trial spec when the trial is built.
%
% Arguments:
%   S  Settings struct
%
% Returns two cell arrays of lum.stim.Component objects.
%
% See also: lum.stim.Component, lum.cueTiming, lum.buildTrialSM

cueNames = {lum.cueTiming(S).Type};
cue = cell(1, numel(cueNames));
for i = 1:numel(cueNames)
    switch cueNames{i}
        case 'CentreLight'
            cue{i} = lum.stim.PortLight('Centre', 'Cue');
        case 'Tone'
            cue{i} = lum.stim.CueTone();
        case 'Air'
            cue{i} = lum.stim.Air('Cue');
        otherwise
            error('lum:stim:build:unknownComponent', ...
                  'Unknown cue component ''%s''. Known: CentreLight, Tone, Air.', cueNames{i});
    end
end

stimulus = {};
if S.Session.UseOpto
    stimulus{end+1} = lum.stim.OptoPattern();
end
for row = S.Stimulus.Components(:)'
    if ~row.Enabled
        continue
    end
    switch row.Type
        case 'Air'
            stimulus{end+1} = lum.stim.Air('Stimulus'); %#ok<AGROW>
        case 'CentreLight'
            stimulus{end+1} = lum.stim.PortLight('Centre', 'Stimulus'); %#ok<AGROW>
        case 'Tone'
            stimulus{end+1} = lum.stim.Sound(lum.stim.Sound.PerGroupName); %#ok<AGROW>
        otherwise
            error('lum:stim:build:unknownComponent', ...
                  'Unknown stimulus component ''%s''. Known: Air, CentreLight, Tone.', row.Type);
    end
end
if S.Left.Light.Enabled || S.Right.Light.Enabled
    stimulus{end+1} = lum.stim.PortLight(lum.stim.PortLight.TargetRole, 'Stimulus');
end
if S.Left.Tone.Enabled || S.Right.Tone.Enabled
    stimulus{end+1} = lum.stim.Sound(lum.stim.Sound.PerSideName);
end
