function lines = describeTestPulses(testPulses, plan)
% lum.sleep.describeTestPulses says what a sleep session's test pulses will deliver.
%
% One description for the sleep setup dialog, the console and the sleep plots:
%
%   Probe: paired 10 ms pulses, 50 ms apart (onset to onset), every 2 s; constant light, 5 V on A, 5 V on B
%   Schedule: 1 step, 240 min
%   1. Probe on A and B, 240 min: 7200 epochs
%
% Arguments:
%   testPulses  S.Sleep.TestPulses
%   plan        Optional, from lum.sleep.testPulsePlan; compiled here when omitted
%
% Returns a cell array of lines.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.testPulsePlan, lum.sleep.describeTrain

if ~testPulses.Enabled
    lines = {'No test pulses: the session sends sync pulses only.'};
    return
end
if nargin < 2
    plan = lum.sleep.testPulsePlan(testPulses);
end
probe = testPulses.Probe;
if strcmp(probe.Mode, 'Paired')
    probeText = sprintf('paired %g ms pulses, %g ms apart (onset to onset)', 1000 * probe.PulseWidth, ...
                        1000 * probe.InterPulseInterval);
else
    probeText = sprintf('a single %g ms pulse', 1000 * probe.PulseWidth);
end
lines = {sprintf('Probe: %s, every %g s; constant light, %g V on A, %g V on B', probeText, ...
                 probe.InterEpochInterval, testPulses.Voltage(1), testPulses.Voltage(2)), ...
         sprintf('Schedule: %d step(s), %s', numel(plan.Steps), minutesText(plan.Duration))};
for s = 1:numel(plan.Steps)
    step = plan.Steps(s);
    switch step.Kind
        case 'Rest'
            lines{end+1} = sprintf('%d. Rest, %s', s, minutesText(step.Duration)); %#ok<AGROW>
        case 'Probe'
            lines{end+1} = sprintf('%d. Probe %s, %s: %d epoch(s)', s, channelsText(step.Channels), ...
                                   minutesText(step.Duration), step.nEpochs); %#ok<AGROW>
        otherwise
            lines{end+1} = sprintf('%d. %s, %s, %s', s, lum.sleep.describeTrain(step.Train), ...
                                   channelsText(step.Channels), minutesText(step.Duration)); %#ok<AGROW>
    end
end


function text = channelsText(channels)
% Where a step's light goes, as a phrase.
if strcmp(channels, 'Alternate A and B')
    text = 'alternating A and B';
else
    text = ['on ' channels];
end


function text = minutesText(seconds)
% A length, in minutes with sensible precision.
text = sprintf('%.4g min', seconds / 60);
