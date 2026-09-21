function [plan, notes] = validate(S, rig, cals)
% lum.ephys.validate checks that an ePhys calibration session can start with these settings.
%
% The ePhys counterpart of lum.sleep.validate (D18): the ePhys setup dialog runs it on
% every edit and its Start button runs it, and lum.sleep.run runs it again before opening
% any device. It checks the schedule (lum.ephys.plan), that its light and the sync pulses
% can be cut into state machines (lum.sleep.checkTimeline), the sync pulses, barcode,
% drug and cameras (lum.sleep.validateClock), and that the LED is controlled from MATLAB,
% which changing the current step by step needs.
%
% Arguments:
%   S     Settings struct; reads S.Ephys, S.Doric, S.Sync.Barcode, S.Session.UseSync, S.Meta
%   rig   Channel map from RigConfig
%   cals  Optional 1 x 2 cell of calibrations (lum.led.calibrations); read from the
%         calibration folder when not given
%
% Returns the compiled plan and a cell array of notes that do not stop the session.
% Errors with 'lum:ephys:validate:<reason>', 'lum:ephys:plan:<reason>',
% 'lum:sleep:validate:<reason>' or 'lum:sleep:testPulsePlan:<reason>'.
%
% This is a pure function apart from reading calibration files: no hardware, no globals.
%
% See also: lum.ephys.plan, lum.gui.EphysSetupDialog, lum.sleep.run, lum.sleep.validateClock

if nargin < 3
    cals = lum.led.calibrations(S);
end
if ~S.Doric.Enabled
    error('lum:ephys:validate:noLEDControl', ...
          ['An ePhys calibration session changes the LED current step by step, so the LED must be '...
           'controlled from MATLAB. Tick "Control the LED from MATLAB" on the Doric LED tab.']);
end
notes = lum.led.validate(S, cals);
[clockNotes, S] = lum.sleep.validateClock(S, rig, S.Ephys.Sync, 'EphysCalibration', []);
notes = [notes clockNotes];
plan = lum.ephys.plan(S, cals);
lum.sleep.checkTimeline(plan, S.Ephys.Sync, rig);
notes = [notes lum.sleep.validateClock(S, rig, S.Ephys.Sync, 'EphysCalibration', plan.Duration / 60)];
if S.Ephys.Voltage(1) < 3 || S.Ephys.Voltage(2) < 3
    notes{end+1} = sprintf(['PulsePal sends %g V on A and %g V on B into the LED driver''s TTL inputs; '...
                            '5 V is a safe TTL high.'], S.Ephys.Voltage(1), S.Ephys.Voltage(2));
end
notes{end+1} = sprintf('The session lasts %.4g min: %d step(s) of %d epoch(s).', plan.Duration / 60, ...
                       numel(plan.Steps), S.Ephys.Repeats);
