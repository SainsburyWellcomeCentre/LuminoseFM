function cal = makeCalibration(path, currents, powers, powerUnit, varargin)
% lum.led.makeCalibration turns power meter readings into an LED calibration.
%
%   cal = lum.led.makeCalibration(path, currentsmA, powers, 'mW')
%
% The operator sets the LED channel to each current in turn (continuous light) and
% reads the power leaving the cable's tip on a power meter, in mW or uW. Irradiance is
% that power over the area of the cable's fibers (path.Area, lum.led.lightPath):
%
%   irradiance (mW/mm2) = power (mW) / (nFibers x pi x (0.1 mm / 2)^2)
%
% Rows with no reading (NaN) are dropped. What is left must hold at least two currents,
% all different, and irradiance must rise with current (equal readings are allowed), or
% converting between the two would not be one-to-one.
%
% Arguments:
%   path       From lum.led.lightPath
%   currents   Currents set, mA
%   powers     Readings, in powerUnit, one per current (NaN for none)
%   powerUnit  'mW' or 'uW'
%
% Options:
%   'Date'     datetime of the calibration (default now)
%   'Notes'    Free text, e.g. the power meter and its wavelength setting
%
% The calibration belongs to the cable (Bundle, Cable) on the channel it was measured on
% (MeasuredOn, MeasuredLEDChannel): the same cable on the other channel needs its own.
%
% Returns a struct: MeasuredOn ('A' or 'B'), MeasuredLEDChannel, Bundle, Cable, nFibers, FiberDiameter (mm),
% Area (mm2), CurrentmA and PowermW and IrradiancemWmm2 (column vectors, sorted by
% current), PowerUnit and PowerTyped (as read), Date ('yyyy-MM-dd HH:mm:ss'), Notes and
% ProtocolVersion.
%
% Errors with 'lum:led:makeCalibration:<reason>'.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.saveCalibration, lum.led.irradiance, lum.led.current

p = inputParser;
addParameter(p, 'Date', datetime('now'));
addParameter(p, 'Notes', '');
parse(p, varargin{:});

currents = double(currents(:));
powers = double(powers(:));
if numel(currents) ~= numel(powers)
    fail('sizeMismatch', 'Give one power reading per current.');
end
switch char(powerUnit)
    case 'mW'
        scale = 1;
    case 'uW'
        scale = 1e-3;
    otherwise
        fail('badUnit', 'The power unit must be mW or uW.');
end
typed = powers;
keep = ~isnan(powers) & ~isnan(currents);
currents = currents(keep);
powers = powers(keep) * scale;
typed = typed(keep);
if numel(currents) < 2
    fail('tooFew', 'A calibration needs power readings at two currents at least.');
end
if any(currents < 0) || any(~isfinite(currents)) || any(powers < 0) || any(~isfinite(powers))
    fail('negative', 'Currents and powers must be finite and not negative.');
end
[currents, order] = sort(currents);
powers = powers(order);
typed = typed(order);
if any(diff(currents) == 0)
    fail('repeatedCurrent', 'Each current may appear once; %g mA is there twice.', ...
         currents(find(diff(currents) == 0, 1)));
end
if any(diff(powers) < 0)
    at = find(diff(powers) < 0, 1);
    fail('notRising', ['The power falls from %g to %g mA. Check the readings: the light '...
         'must not get dimmer as the current rises.'], currents(at), currents(at + 1));
end
if powers(end) <= powers(1)
    fail('flat', 'The power does not rise over the currents measured, so it cannot be calibrated.');
end

cal = struct('MeasuredOn', path.Channel, 'MeasuredLEDChannel', path.LEDChannel, 'Bundle', path.Bundle, ...
             'Cable', path.Cable, 'nFibers', path.nFibers, 'FiberDiameter', path.FiberDiameter, ...
             'Area', path.Area, 'CurrentmA', currents, 'PowermW', powers, ...
             'IrradiancemWmm2', powers / path.Area, 'PowerUnit', char(powerUnit), ...
             'PowerTyped', typed, 'Date', char(p.Results.Date, 'yyyy-MM-dd HH:mm:ss'), ...
             'Notes', char(p.Results.Notes), 'ProtocolVersion', lum.version());


function fail(id, varargin)
error(['lum:led:makeCalibration:' id], varargin{:});
