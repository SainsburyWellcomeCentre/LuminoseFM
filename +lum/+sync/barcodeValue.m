function value = barcodeValue(startTime)
% lum.sync.barcodeValue turns a session start time into the number its barcode carries.
%
% Whole seconds since 2020-01-01 00:00:00, local time. That is unique for sessions
% started on this rig at least a second apart, fits in 32 bits until 2156, and
% decodes straight back to the start time (lum.sync.barcodeTime) — which is also in
% the session file's name, so a recording and its behaviour file can be paired by
% eye as well as by program.
%
% Arguments:
%   startTime  datetime of the session start (default: now)
%
% This is a pure function when startTime is given: no hardware, no globals.
%
% See also: lum.sync.barcode, lum.sync.barcodeTime

if nargin < 1 || isempty(startTime)
    startTime = datetime('now');
end
startTime.TimeZone = '';
value = round(seconds(startTime - datetime(2020, 1, 1)));
if value < 0
    error('lum:sync:barcodeValue:beforeEpoch', ...
          'Session start times before 2020-01-01 cannot be encoded.');
end
