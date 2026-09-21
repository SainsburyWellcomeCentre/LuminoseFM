function width = markerWidth(params, kind)
% lum.sync.markerWidth is the width of the markers that open and close a barcode of a kind.
%
% The markers of the session barcode say what kind of session it opens (D7, D11, D18):
%
%   'Behaviour'          params.MarkerWidth (100 ms by default)
%   'Sleep'              params.SleepMarkerWidth (200 ms); twice MarkerWidth in settings
%                        from before 0.3, which have no SleepMarkerWidth
%   'EphysCalibration'   params.EphysMarkerWidth (300 ms); the sleep marker plus the
%                        behaviour marker in settings from before 0.7, which have none
%
% Each kind's marker is longer than the one before, so lum.sync.decodeBarcode tells them
% apart by the opening marker's width.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sync.barcode, lum.sync.decodeBarcode, lum.sync.barcodeKinds

switch kind
    case 'Behaviour'
        width = params.MarkerWidth;
    case 'Sleep'
        width = lum.sync.sleepMarkerWidth(params);
    case 'EphysCalibration'
        if isfield(params, 'EphysMarkerWidth') && ~isempty(params.EphysMarkerWidth)
            width = params.EphysMarkerWidth;
        else
            width = lum.sync.sleepMarkerWidth(params) + params.MarkerWidth;
        end
    otherwise
        error('lum:sync:barcode:badKind', ['The barcode kind must be one of %s; ''%s'' is '...
              'not.'], strjoin(lum.sync.barcodeKinds(), ', '), char(string(kind)));
end
