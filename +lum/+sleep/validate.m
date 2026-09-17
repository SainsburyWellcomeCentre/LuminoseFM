function notes = validate(S, rig)
% lum.sleep.validate checks that a sleep session can start with these settings.
%
% The sleep counterpart of lum.validateSettings: the sleep setup dialog runs it on
% every edit and its Start button runs it, and lum.sleep.run runs it again before
% opening any device, so a headless session cannot start on settings the dialog
% would have refused. Test pulses are checked by lum.sleep.validateTestPulses.
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
%           lum.sleep.validateTestPulses

notes = {};

sync = S.Sleep.Sync;
switch sync.Mode
    case lum.SyncMode.FixedWidth
        if ~(sync.FixedWidth > 0)
            fail('badWidth', 'The fixed sync pulse must be longer than 0 s.');
        end
    case lum.SyncMode.JitteredWidth
        if ~(sync.WidthJitter >= 0 && sync.WidthJitter < sync.MeanWidth)
            fail('badJitter', ...
                 ['A jitter of %g s around a mean of %g s would ask for pulses of zero width '...
                  'or less. Reduce the jitter below the mean.'], sync.WidthJitter, sync.MeanWidth);
        end
    otherwise
        fail('badMode', 'Sleep sync pulses must be Fixed width or Jittered width.');
end

% With video, what goes on the line is widened until the cameras can read it. What was
% typed is checked above; from here on the fitted values are.
[S, syncFit, framePeriod] = lum.sync.fitToCameras(S);
if ~isempty(syncFit)
    notes{end+1} = sprintf('Sync line widened so the %g Hz cameras can read it: %s.', ...
                           S.Camera.FrameRate, strjoin(syncFit, ', '));
end
sync = S.Sleep.Sync;
if sync.Mode == lum.SyncMode.FixedWidth
    longestPulse = sync.FixedWidth;
else
    longestPulse = sync.MeanWidth + sync.WidthJitter;
end
if ~(sync.Interval > 0 && sync.IntervalJitter >= 0)
    fail('badInterval', 'The interval between pulses must be positive, and its jitter not negative.');
end
shortestInterval = sync.Interval - sync.IntervalJitter;
if ~(shortestInterval - longestPulse >= 1e-3)
    fail('pulsesOverlap', ...
         ['The shortest interval between pulses (%g s) must leave at least 1 ms after the '...
          'longest pulse (%g s). Lengthen the interval or shorten the pulses.'], ...
         shortestInterval, longestPulse);
end
% The gap between pulses is on the video too, and cannot be widened for it.
if ~isnan(framePeriod) && ~(shortestInterval - longestPulse >= 2 * framePeriod - 1e-9)
    fail('gapTooShortForCameras', ...
         ['The shortest gap between sync pulses (%.4g ms) is under two video frames at %g Hz '...
          '(%.4g ms), so the cameras could miss it. Lengthen the interval.'], ...
         1000 * (shortestInterval - longestPulse), S.Camera.FrameRate, 2000 * framePeriod);
end

% With test pulses the recording lasts as long as their schedule; without, as set.
if S.Sleep.TestPulses.Enabled
    [plan, testPulseNotes] = lum.sleep.validateTestPulses(S, rig);
    durationMinutes = plan.Duration / 60;
    notes = [notes testPulseNotes];
else
    durationMinutes = S.Sleep.DurationMinutes;
    if ~(isscalar(durationMinutes) && durationMinutes > 0 && durationMinutes <= 24 * 60)
        fail('badDuration', 'The sleep recording must last more than 0 and at most 1440 minutes.');
    end
end

% The pulse record is preallocated and rewritten at every save, so a session is capped
% at a size one file handles comfortably (a pulse a second for 24 h is 86,400).
expectedPulses = 60 * durationMinutes / shortestInterval;
if expectedPulses > 5e5
    fail('tooManyPulses', ...
         ['This session would send about %d pulses; at most 500000 fit one session. '...
          'Lengthen the interval or shorten the session.'], round(expectedPulses));
end

if S.Sync.Barcode.Enabled
    lum.sync.barcode(0, S.Sync.Barcode, 'Sleep');
end

if S.Meta.Drug.Enabled && isempty(strtrim(S.Meta.Drug.Name))
    fail('noDrugName', 'A drug session needs the drug''s name.');
end

lum.dev.Cameras.validateSettings(S.Camera);
videoNote = lum.dev.Cameras.formatNote(S.Camera);
if ~isempty(videoNote)
    notes{end+1} = videoNote;
end

if ~S.Session.UseSync
    notes{end+1} = ['The sync output is off: no barcode and no pulses are sent, and the '...
                    'session records only the times they would have had.'];
elseif ~rig.Available.Sync
    notes{end+1} = sprintf(['%s is not available on this state machine, so no barcode and '...
                            'no sync pulses will be sent.'], rig.Sync.Channel);
end


function fail(id, varargin)
% Raise a settings error with a lum:sleep:validate identifier.
error(['lum:sleep:validate:' id], varargin{:});
