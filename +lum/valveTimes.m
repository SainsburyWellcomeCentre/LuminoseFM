function [times, note] = valveTimes(amount, valves, liquidCal)
% lum.valveTimes gives each valve's open time for a volume of water, from Bpod's liquid
% calibration, and refuses a volume the calibration cannot give.
%
% Bpod's GetValveTimes turns microlitres into milliseconds with the calibration's fitted
% polynomial and checks nothing else. The fit is a quadratic through a few measurements,
% so outside them it goes wrong without a sign: 0 uL still opens the valve for the fit's
% intercept (several ms), past the fit's peak a larger volume gets a shorter time, and
% further on the time is negative and GetValveTimes errors. So here:
%   0 uL          no water: every time is 0, and the calibration is not read
%   rising fit    the time GetValveTimes gives, while the fit still rises there
%   falling fit   an error (lum:valveTimes:outsideCalibration): a larger volume would
%                 give less water, or none
%   outside the measured volumes, but rising: the time, and a note saying it is
%                 extrapolated, for the operator to see
%
% Arguments:
%   amount     Microlitres, 0 or more
%   valves     Valve numbers (behaviour ports), e.g. rig.SidePorts or rig.Ports.Centre
%   liquidCal  Optional: Bpod's liquid calibration struct array (Table: ms, uL; Coeffs),
%              as BpodSystem.CalibrationTables.LiquidCal. By default it is read from
%              BpodSystem; the fit's slope and range are checked only when it is a struct
%              (Bpod's calibration file; the newer calibration objects are trusted as they
%              are)
%
% Returns the times in seconds, one per valve, and a note ('' when there is nothing to
% say). Errors as GetValveTimes does when a valve has no calibration.
%
% See also: GetValveTimes, LuminoseFM, CheckRig

global BpodSystem %#ok<GVMIS> % Where Bpod keeps the liquid calibration

if ~(isscalar(amount) && isnumeric(amount) && isfinite(amount) && amount >= 0)
    error('lum:valveTimes:badAmount', 'A volume of water is a number of microlitres, 0 or more.');
end
times = zeros(1, numel(valves));
note = '';
if amount == 0
    return
end
if nargin < 3
    liquidCal = [];
    try
        liquidCal = BpodSystem.CalibrationTables.LiquidCal;
    catch
        % No Bpod: GetValveTimes below says so
    end
end
notes = {};
for i = 1:numel(valves)
    valve = valves(i);
    if ~isstruct(liquidCal) || numel(liquidCal) < valve || isempty(liquidCal(valve).Coeffs)
        continue   % GetValveTimes below says what is missing
    end
    fitted = polyval(liquidCal(valve).Coeffs, amount);
    slope = polyval(polyder(liquidCal(valve).Coeffs), amount);
    measured = liquidCal(valve).Table(:, 2);
    if ~(fitted > 0) || ~(slope > 0)
        error('lum:valveTimes:outsideCalibration', ...
              ['Valve %d cannot give %g uL: its liquid calibration, measured from %g to %g uL, '...
               'gives %.1f ms there, and a larger volume would give less water. Ask for a volume '...
               'within its measurements, or calibrate the valve further.'], valve, amount, ...
              min(measured), max(measured), fitted);
    end
    if amount < min(measured) || amount > max(measured)
        notes{end+1} = sprintf('valve %d is measured from %g to %g uL, so %g uL (%.1f ms) is extrapolated', ...
                               valve, min(measured), max(measured), amount, fitted); %#ok<AGROW>
    end
end
times = GetValveTimes(amount, valves);
if ~isempty(notes)
    note = [strjoin(notes, '; ') '.'];
    note(1) = upper(note(1));
end
