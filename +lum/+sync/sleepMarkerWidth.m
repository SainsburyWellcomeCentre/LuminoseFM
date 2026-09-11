function width = sleepMarkerWidth(params)
% lum.sync.sleepMarkerWidth is the marker width of a sleep session's barcode.
%
% A behaviour session's barcode opens and closes with params.MarkerWidth, a sleep
% session's with params.SleepMarkerWidth (D11). Settings written before version 0.3
% have no SleepMarkerWidth; their sleep marker is twice the behaviour marker.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sync.barcode, lum.sync.decodeBarcode

if isfield(params, 'SleepMarkerWidth') && ~isempty(params.SleepMarkerWidth)
    width = params.SleepMarkerWidth;
else
    width = 2 * params.MarkerWidth;
end
