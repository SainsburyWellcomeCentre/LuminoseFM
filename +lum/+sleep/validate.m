function notes = validate(S, rig)
% lum.sleep.validate checks that a sleep session can start with these settings.
%
% The sleep counterpart of lum.validateSettings: the sleep setup dialog runs it on
% every edit and its Start button runs it, and lum.sleep.run runs it again before
% opening any device, so a headless session cannot start on settings the dialog
% would have refused. The sync pulses and what every clock session shares are checked
% by lum.sleep.validateClock (also used by ePhys calibration sessions); test pulses by
% lum.sleep.validateTestPulses.
%
% Arguments:
%   S    Settings struct; reads S.Sleep, S.Sync.Barcode, S.Session.UseSync, S.Meta
%   rig  Channel map from RigConfig
%
% Returns a cell array of things worth saying that do not stop the session. Errors
% with a message the operator can act on at the first problem found.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.gui.SleepSetupDialog, lum.sleep.run, lum.validateSettings,
%           lum.sleep.validateTestPulses, lum.sleep.validateClock

[notes, S] = lum.sleep.validateClock(S, rig, S.Sleep.Sync, 'Sleep', []);

% With test pulses the recording lasts as long as their schedule; without, as set.
if S.Sleep.TestPulses.Enabled
    [plan, testPulseNotes] = lum.sleep.validateTestPulses(S, rig);
    durationMinutes = plan.Duration / 60;
    notes = [notes testPulseNotes];
else
    durationMinutes = S.Sleep.DurationMinutes;
    if ~(isscalar(durationMinutes) && durationMinutes > 0 && durationMinutes <= 24 * 60)
        error('lum:sleep:validate:badDuration', ...
              'The sleep recording must last more than 0 and at most 1440 minutes.');
    end
end
notes = [notes lum.sleep.validateClock(S, rig, S.Sleep.Sync, 'Sleep', durationMinutes)];
if S.Sleep.TestPulses.Enabled
    lum.led.validate(S);   % The LED currents and their limits (D17)
end
