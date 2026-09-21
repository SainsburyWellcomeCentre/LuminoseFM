function lines = describe(S, plan)
% lum.ephys.describe sums an ePhys calibration session up in a few lines, for the windows.
%
% Arguments:
%   S     Settings struct; reads S.Ephys
%   plan  From lum.ephys.plan
%
% Returns a cell array of lines: the pulses and their timing, then one line per protocol
% with its steps and currents.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.ephys.plan, lum.gui.EphysSetupDialog, lum.sleep.Plots

e = S.Ephys;
lines = {sprintf('%g ms pulses of constant light on %s, one epoch every %g s, %d per step, %s order', ...
                 1000 * e.PulseWidth, channelText(e.Channels), e.InterEpochInterval, e.Repeats, ...
                 lower(e.Order)), ...
         sprintf('%d step(s), %.4g min', numel(plan.Steps), plan.Duration / 60)};
protocols = {'Input-output', 'Paired-pulse ratio'};
for i = 1:2
    steps = plan.Steps(strcmp({plan.Steps.Protocol}, protocols{i}));
    if isempty(steps)
        continue
    end
    currents = vertcat(steps.CurrentmA);
    parts = {};
    for k = find(any(~isnan(currents), 1))
        values = unique(currents(:, k))';
        parts{end+1} = sprintf('%s %s mA', char('A' + k - 1), rangeText(values)); %#ok<AGROW>
    end
    if i == 1
        lines{end+1} = sprintf('Input-output: %d levels, %s', numel(steps), strjoin(parts, ', ')); %#ok<AGROW>
    else
        intervals = sort([steps.InterPulseInterval]) * 1000;
        lines{end+1} = sprintf('Paired-pulse ratio: pairs %s ms apart, %s', ...
                               strjoin(arrayfun(@(v) sprintf('%g', v), intervals, 'UniformOutput', false), ', '), ...
                               strjoin(parts, ', ')); %#ok<AGROW>
    end
end


function text = channelText(channels)
if strcmp(channels, 'A and B')
    text = 'A and B together';
else
    text = channels;
end


function text = rangeText(values)
if isscalar(values)
    text = sprintf('%g', values);
else
    text = sprintf('%g-%g', values(1), values(end));
end
