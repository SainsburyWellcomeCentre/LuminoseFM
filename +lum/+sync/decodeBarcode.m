function [value, startIndex, kind] = decodeBarcode(risingTimes, fallingTimes, params)
% lum.sync.decodeBarcode reads the session barcode back from recorded sync edges.
%
% For analysis of any recording that captured the sync line. Pulse widths are what
% carry the code, so only the recording's own clock is needed: the edge times may
% be in seconds from any origin.
%
% Arguments:
%   risingTimes   Times of the line's rising edges, seconds
%   fallingTimes  Times of its falling edges, seconds
%   params        The S.Sync.Barcode the session used (stored in the session file,
%                 Data.Session.Barcode.Params)
%
% Returns:
%   value       The decoded value, or NaN if no complete barcode was found
%   startIndex  Index into risingTimes of the barcode's opening marker, or NaN
%   kind        'Behaviour' or 'Sleep', from the opening marker's width; '' when no
%               barcode was found
%
% The first pair of markers that encloses exactly nBits pulses is the barcode, so
% trial pulses recorded afterwards do not confuse it. A trial pulse as long as the
% marker could, which is why the marker defaults to twice the longest bit. Behaviour
% and sleep markers are both markers here; which one opened the code is the kind.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sync.barcode, lum.sync.barcodeTime

value = NaN;
startIndex = NaN;
kind = '';

risingTimes = risingTimes(:)';
fallingTimes = fallingTimes(:)';
widths = NaN(1, numel(risingTimes));
for i = 1:numel(risingTimes)
    nextFall = find(fallingTimes > risingTimes(i), 1);
    if ~isempty(nextFall)
        widths(i) = fallingTimes(nextFall) - risingTimes(i);
    end
end

markerThreshold = (params.OneWidth + params.MarkerWidth) / 2;
bitThreshold = (params.ZeroWidth + params.OneWidth) / 2;
sleepThreshold = (params.MarkerWidth + lum.sync.sleepMarkerWidth(params)) / 2;
markers = find(widths > markerThreshold);
for m = 1:numel(markers) - 1
    first = markers(m);
    last = markers(m + 1);
    if last - first - 1 ~= params.nBits
        continue
    end
    bitWidths = widths(first + 1:last - 1);
    if any(isnan(bitWidths))
        continue
    end
    bits = bitWidths > bitThreshold;
    value = sum(bits .* 2 .^ (params.nBits - 1:-1:0));
    startIndex = first;
    if widths(first) > sleepThreshold
        kind = 'Sleep';
    else
        kind = 'Behaviour';
    end
    return
end
