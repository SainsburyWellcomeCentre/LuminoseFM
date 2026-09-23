function tf = untilRecordingEnds(testPulses)
% lum.sleep.untilRecordingEnds says whether a test-pulse schedule lasts the whole recording.
%
% True when test pulses are on and the schedule's last step has Minutes Inf: that step
% runs until the recording ends, so the recording lasts S.Sleep.DurationMinutes, as it
% does without test pulses. Otherwise, with test pulses on, the recording lasts as long
% as the schedule (lum.sleep.testPulsePlan).
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.testPulsePlan, lum.sleep.validate, lum.gui.SleepSetupDialog

tf = false;
if ~isstruct(testPulses) || ~isfield(testPulses, 'Schedule') || isempty(testPulses.Schedule) ...
        || ~logical(testPulses.Enabled)
    return
end
minutes = testPulses.Schedule(end).Minutes;
tf = isnumeric(minutes) && isscalar(minutes) && isinf(minutes) && minutes > 0;
