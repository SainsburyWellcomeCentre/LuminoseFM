function [problem, rules] = checkCoverage(cal)
% lum.led.checkCoverage says whether a calibration covers enough currents to be used.
%
%   problem = lum.led.checkCoverage(cal)     % '' when it can be used
%   [~, rules] = lum.led.checkCoverage()     % the rules, for help text and tests
%
% A calibration turns irradiance into current by interpolating between its readings, and
% the most a channel gives is the irradiance at its highest reading. Readings at a few low
% currents (0, 50, 100 mA) would make the most a session can ask for a fraction of what
% the LED gives, and a curve through two or three points misses its bend. So a calibration
% is used only with readings at MinLitReadings currents above 0 mA at least, the highest
% at MinTopCurrentmA or more. A calibration that stops below the channel's limit is
% still used, up to its highest reading (lum.led.currentFor): readings to 700 mA work
% with a 1000 mA limit, and the session runs no brighter than the 700 mA reading.
%
% Arguments:
%   cal  A calibration (lum.led.makeCalibration), or empty
%
% Returns:
%   problem  '' when the calibration can be used, else one sentence saying what is missing
%   rules    Struct with MinLitReadings and MinTopCurrentmA
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.makeCalibration, lum.led.loadCalibration, lum.gui.DoricCalibration

rules = struct('MinLitReadings', 4, 'MinTopCurrentmA', 400);
problem = '';
if nargin < 1
    return
end
if isempty(cal)
    problem = 'There are no readings.';
    return
end
currents = double(cal.CurrentmA(:));
nLit = sum(currents > 0);
top = max(currents);
if nLit < rules.MinLitReadings || top < rules.MinTopCurrentmA
    problem = sprintf(['Readings at %d currents above 0 mA, the highest %g mA: a calibration needs '...
                       '%d at least, up to %g mA or more, to give irradiance across the LED''s range.'], ...
                      nLit, top, rules.MinLitReadings, rules.MinTopCurrentmA);
end
