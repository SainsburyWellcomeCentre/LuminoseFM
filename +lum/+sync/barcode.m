function code = barcode(value, params, kind)
% lum.sync.barcode encodes a number as the session barcode sent on the sync line.
%
% Before the first trial the sync line carries one barcode that identifies the
% session, so that a recording from any acquisition device can be matched to the
% behaviour file it belongs to without relying on file names, clocks or the order
% sessions were run in. Trial pulses (or, in a sleep session, sync pulses) then align
% the recording within the session.
%
% The code is pulse-width modulated, so a decoder needs no clock of its own:
%
%   marker | bit 1 | bit 2 | ... | bit n | marker
%
% Every element is a high pulse followed by a low gap of params.Gap. A 0 bit is
% params.ZeroWidth high and a 1 bit params.OneWidth. Bits go most significant first.
% The closing marker lets a decoder check it has the whole code and read it in the
% right direction.
%
% The markers say what kind of session the barcode opens (D11): params.MarkerWidth
% for a behaviour session, params.SleepMarkerWidth — longer — for a sleep session.
% lum.sync.decodeBarcode reads the kind back from the opening marker.
%
% Arguments:
%   value   Non-negative integer to encode; reduced modulo 2^nBits. The session
%           uses lum.sync.barcodeValue, the seconds since 2020-01-01 at session
%           start, so the code decodes to when the session began.
%   params  S.Sync.Barcode: nBits, MarkerWidth, ZeroWidth, OneWidth, Gap and
%           SleepMarkerWidth (seconds). Without SleepMarkerWidth — settings from
%           before 0.3 — it is twice MarkerWidth.
%   kind    'Behaviour' (default) or 'Sleep'
%
% Returns a struct:
%   .Value          The encoded value
%   .Hex            The value in hexadecimal, for logs
%   .Kind           'Behaviour' or 'Sleep'
%   .MarkerWidth    The marker width this kind uses, seconds
%   .Bits           1 x nBits logical, most significant first
%   .Levels         1 x nElements line level of each element, 0 or 1
%   .Durations      1 x nElements duration of each element, seconds
%   .TotalDuration  Seconds from the first rising edge to the line settling low
%   .Params         The parameters used
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.sync.barcodeValue, lum.sync.decodeBarcode, lum.sync.barcodeStateMachine

if nargin < 3 || isempty(kind)
    kind = 'Behaviour';
end

nBits = params.nBits;
if ~(isscalar(nBits) && nBits >= 1 && nBits <= 48 && mod(nBits, 1) == 0)
    error('lum:sync:barcode:badBitCount', 'The barcode needs between 1 and 48 bits.');
end
sleepMarker = lum.sync.sleepMarkerWidth(params);
widths = [params.ZeroWidth, params.OneWidth, params.MarkerWidth, sleepMarker, params.Gap];
if any(~isfinite(widths)) || any(widths < 1e-3)
    error('lum:sync:barcode:badWidths', ...
          'Barcode widths and gaps must each be at least 1 ms, so every edge is resolvable.');
end
if ~(params.ZeroWidth < params.OneWidth && params.OneWidth < params.MarkerWidth)
    error('lum:sync:barcode:badWidths', ...
          ['A 0 bit must be shorter than a 1 bit, and a 1 bit shorter than the marker '...
           '(%g < %g < %g s).'], params.ZeroWidth, params.OneWidth, params.MarkerWidth);
end
if ~(sleepMarker > params.MarkerWidth)
    error('lum:sync:barcode:badWidths', ...
          ['The sleep marker (%g s) must be longer than the behaviour marker (%g s), or the '...
           'two kinds of session could not be told apart.'], sleepMarker, params.MarkerWidth);
end
switch kind
    case 'Behaviour'
        marker = params.MarkerWidth;
    case 'Sleep'
        marker = sleepMarker;
    otherwise
        error('lum:sync:barcode:badKind', 'The barcode kind must be ''Behaviour'' or ''Sleep''.');
end
if ~(isscalar(value) && isfinite(value) && value >= 0)
    error('lum:sync:barcode:badValue', 'The barcode value must be a non-negative number.');
end

value = mod(round(value), 2^nBits);
bits = bitget(value, nBits:-1:1) == 1;

highs = [marker, params.ZeroWidth + bits * (params.OneWidth - params.ZeroWidth), marker];
durations = reshape([highs; repmat(params.Gap, 1, numel(highs))], 1, []);
levels = repmat([1 0], 1, numel(highs));

% Quantised to the state machine's 100 us cycle: what is stored is what is sent.
durations = round(durations / 1e-4) * 1e-4;

code = struct('Value', value, 'Hex', sprintf('%0*X', ceil(nBits / 4), value), ...
              'Kind', kind, 'MarkerWidth', marker, ...
              'Bits', bits, 'Levels', levels, 'Durations', durations, ...
              'TotalDuration', sum(durations), 'Params', params);
