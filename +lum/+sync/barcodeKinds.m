function kinds = barcodeKinds()
% lum.sync.barcodeKinds lists the kinds of session a barcode can open, shortest marker first.
%
% They are the session types (S.Session.Type): 'Behaviour', 'Sleep' and
% 'EphysCalibration'. lum.sync.markerWidth gives each kind's marker.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sync.markerWidth, lum.sync.decodeBarcode

kinds = {'Behaviour', 'Sleep', 'EphysCalibration'};
