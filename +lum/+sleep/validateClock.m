function [notes, S] = validateClock(S, rig, sync, kind, durationMinutes)
% lum.sleep.validateClock checks what every clock session shares: sync pulses and the rest.
%
% Sleep sessions and ePhys calibration sessions (D11, D18) put sync pulses on a clock and
% no task. Their validations (lum.sleep.validate, lum.ephys.validate) call this twice:
%
%   [notes, S] = lum.sleep.validateClock(S, rig, sync, kind, [])
%       the sync pulses as typed (mode, widths, jitter), then as fitted to the cameras
%       (lum.sync.fitToCameras): the interval must leave 1 ms after the longest pulse, and
%       two frames when there is video. Returns S fitted, so later checks see what is sent.
%   notes = lum.sleep.validateClock(S, rig, sync, kind, durationMinutes)
%       with the session's length known: the number of pulses, the barcode of this kind,
%       the drug's name, the cameras, and notes on the sync output.
%
% Arguments:
%   S                Settings struct
%   rig              Channel map from RigConfig
%   sync             The session's sync pulses: S.Sleep.Sync or S.Ephys.Sync
%   kind             'Sleep' or 'EphysCalibration': the barcode's kind
%   durationMinutes  [] for the first call; the session's length for the second
%
% Errors with 'lum:sleep:validate:<reason>'.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sleep.validate, lum.ephys.validate, lum.sync.fitToCameras

if isempty(durationMinutes)
    [notes, S] = checkPulses(S, sync, kind);
else
    notes = checkSession(S, rig, sync, kind, durationMinutes);
end


function [notes, S] = checkPulses(S, sync, kind)
notes = {};
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
        fail('badMode', 'Sync pulses on a clock must be Fixed width or Jittered width.');
end

% With video, what goes on the line is widened until the cameras can read it. What was
% typed is checked above; from here on the fitted values are.
[S, syncFit, framePeriod] = lum.sync.fitToCameras(S);
if ~isempty(syncFit)
    notes{end+1} = sprintf('Sync line widened so the %g Hz cameras can read it: %s.', ...
                           S.Camera.FrameRate, strjoin(syncFit, ', '));
end
sync = fittedSync(S, kind);
[longestPulse, shortestInterval] = extremes(sync);
if ~(sync.Interval > 0 && sync.IntervalJitter >= 0)
    fail('badInterval', 'The interval between pulses must be positive, and its jitter not negative.');
end
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


function notes = checkSession(S, rig, sync, kind, durationMinutes)
notes = {};
[~, shortestInterval] = extremes(sync);
shortestInterval = max(shortestInterval, 1e-3);
% The pulse record is preallocated and rewritten at every save, so a session is capped
% at a size one file handles comfortably (a pulse a second for 24 h is 86,400).
expectedPulses = 60 * durationMinutes / shortestInterval;
if expectedPulses > 5e5
    fail('tooManyPulses', ...
         ['This session would send about %d pulses; at most 500000 fit one session. '...
          'Lengthen the interval or shorten the session.'], round(expectedPulses));
end

if S.Sync.Barcode.Enabled
    lum.sync.barcode(0, S.Sync.Barcode, kind);
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


function sync = fittedSync(S, kind)
if strcmp(kind, 'EphysCalibration')
    sync = S.Ephys.Sync;
else
    sync = S.Sleep.Sync;
end


function [longestPulse, shortestInterval] = extremes(sync)
if sync.Mode == lum.SyncMode.FixedWidth
    longestPulse = sync.FixedWidth;
else
    longestPulse = sync.MeanWidth + sync.WidthJitter;
end
shortestInterval = sync.Interval - sync.IntervalJitter;


function fail(id, varargin)
% Raise a settings error with a lum:sleep:validate identifier.
error(['lum:sleep:validate:' id], varargin{:});
