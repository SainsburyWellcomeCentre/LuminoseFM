function [S, changes, period] = fitToCameras(S)
% lum.sync.fitToCameras widens everything on the sync line until the cameras can read it.
%
%   [S, changes, period] = lum.sync.fitToCameras(S)
%
% The sync line reaches the cameras' Line0, and a camera logs it once per frame
% (TTL_State). A pulse or a gap shorter than a frame can fall between two frames, and one
% lost bit makes the barcode unreadable from the video. So when the session records video,
% every width the operator typed is a minimum, and this function raises what falls short
% of the frame period T = 1 / S.Camera.FrameRate (D7, D14):
%
%   element                          rule                              why
%   barcode 0 bit, gap               >= 2 T                            always sampled, even with
%                                                                      a frame rate a little low
%   barcode 1 bit                    >= 0 bit + 3 T                    a frame's error either way
%   behaviour marker                 >= 1 bit + 3 T                    cannot close the gap
%   sleep marker                     >= behaviour marker + 3 T
%   trial pulses, sleep sync pulses  shortest >= 2 T; a jittered range
%                                    keeps its spread, shifted up
%
% A frame samples the line at one instant, so a high or low time of n T is seen as n - 1
% to n + 1 frames. 2 T is therefore never missed, and 3 T between neighbouring widths keeps
% their ranges apart around the decoder's midpoint thresholds (lum.sync.decodeBarcode),
% which read widths in seconds from the frames' own timestamps. The number of bits and the
% sync mode never change; task events have no pulse to widen.
%
% Nothing changes without video (S.Camera.Enabled off, or no camera ticked), and fitting
% fitted settings changes nothing. At the 100 Hz default the defaults already fit.
%
% Where it is used: the settings file keeps what the operator typed. lum.validateSettings
% and lum.sleep.validate check the fitted values and say what was widened; LuminoseFM and
% lum.sleep.run fit S once, before anything is sent, so the barcode (Data.Session.Barcode.
% Params), the trial pulses (Data.SyncPulseWidth), the sleep pulses (Data.SyncPulses) and
% Data.Session.Settings are what went out, and Data.Session.SyncFit lists the changes. The
% setup dialogs preview the fitted barcode.
%
% Returns:
%   S        Settings with S.Sync.Barcode, S.Sync's widths and S.Sleep.Sync's widths fitted
%   changes  Cell array of text, one entry per value raised, e.g. '0 bit 10 -> 20 ms';
%            empty when nothing changed
%   period   The frame period used, seconds; NaN without video
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sync.barcode, lum.sync.decodeBarcode, lum.validateSettings, lum.sleep.validate

changes = {};
period = NaN;
camera = S.Camera;
recording = camera.Enabled && ~isempty(camera.Cameras) && any([camera.Cameras.Record]) ...
            && isscalar(camera.FrameRate) && camera.FrameRate > 0;
if ~recording
    return
end
period = 1 / camera.FrameRate;
minimum = 2 * period;
separation = 3 * period;

% The session barcode.
barcode = S.Sync.Barcode;
[barcode.ZeroWidth, changes] = raise(barcode.ZeroWidth, minimum, '0 bit', changes);
[barcode.Gap, changes] = raise(barcode.Gap, minimum, 'barcode gap', changes);
[barcode.OneWidth, changes] = raise(barcode.OneWidth, barcode.ZeroWidth + separation, '1 bit', changes);
[barcode.MarkerWidth, changes] = raise(barcode.MarkerWidth, barcode.OneWidth + separation, ...
                                       'behaviour marker', changes);
[barcode.SleepMarkerWidth, changes] = raise(lum.sync.sleepMarkerWidth(S.Sync.Barcode), ...
                                            barcode.MarkerWidth + separation, 'sleep marker', changes);
S.Sync.Barcode = barcode;

% Trial pulses, and a sleep session's sync pulses.
[S.Sync, changes] = fitPulses(S.Sync, minimum, 'trial pulse', changes);
if isfield(S, 'Sleep') && isfield(S.Sleep, 'Sync')
    [S.Sleep.Sync, changes] = fitPulses(S.Sleep.Sync, minimum, 'sleep pulse', changes);
end


function [sync, changes] = fitPulses(sync, minimum, name, changes)
% A fixed width is raised to the minimum; a jittered range keeps its spread and moves up
% until its shortest pulse is the minimum.
switch sync.Mode
    case lum.SyncMode.FixedWidth
        [sync.FixedWidth, changes] = raise(sync.FixedWidth, minimum, ['fixed ' name], changes);
    case lum.SyncMode.JitteredWidth
        shortest = sync.MeanWidth - sync.WidthJitter;
        [fitted, changes] = raise(shortest, minimum, ['shortest ' name], changes);
        sync.MeanWidth = sync.MeanWidth + (fitted - shortest);
end


function [value, changes] = raise(value, minimum, name, changes)
% Raise value to minimum, rounded up to the state machine's 100 us cycle, and say so.
minimum = ceil(minimum / 1e-4 - 1e-6) * 1e-4;
if value < minimum - 1e-9
    changes{end+1} = sprintf('%s %.4g -> %.4g ms', name, 1000 * value, 1000 * minimum);
    value = minimum;
end
