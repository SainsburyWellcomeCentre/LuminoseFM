function startTime = barcodeTime(value)
% lum.sync.barcodeTime turns a decoded session barcode back into the session start.
%
% The inverse of lum.sync.barcodeValue, for analysis: decode the barcode from a
% recording's sync channel with lum.sync.decodeBarcode, then look for the behaviour
% file started at this time.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sync.barcodeValue, lum.sync.decodeBarcode

startTime = datetime(2020, 1, 1) + seconds(value);
