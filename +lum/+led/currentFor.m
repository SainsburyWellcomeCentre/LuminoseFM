function [mA, reached, note] = currentFor(cal, irradiance, limitmA)
% lum.led.currentFor is the LED current that gives an irradiance, within what the channel reaches.
%
%   [mA, reached, note] = lum.led.currentFor(cal, 8, 700)
%
% The whole mA that give the irradiance asked for (lum.led.current), where the calibration
% reaches it. The most a channel gives is the irradiance at its highest current: the top
% of the calibration or the channel's limit, whichever is lower. More than that runs at
% that most, and less than the lowest reading at the lowest current measured; either way
% note says so. NaN asks for the most. The session never refuses an intensity for being
% out of reach, so a cable that gives less than the default still runs.
%
% Arguments:
%   cal         A calibration (lum.led.loadCalibration); not empty
%   irradiance  mW/mm2 asked for, or NaN for the most the channel gives
%   limitmA     The channel's current limit (S.Doric.MaxCurrentmA(k))
%
% Returns:
%   mA       Whole mA, within the limit
%   reached  The irradiance those mA give, mW/mm2
%   note     '' when the irradiance was reached, else one sentence saying what runs instead
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.current, lum.led.irradiance, lum.led.intensity

if isempty(cal)
    error('lum:led:currentFor:noCalibration', 'This light path has no calibration; give the current in mA.');
end
note = '';
tolerance = 1e-9;
topCurrent = min(double(limitmA), cal.CurrentmA(end));
if topCurrent < cal.CurrentmA(1)
    % The limit is below every current measured: the lowest the channel may run at.
    mA = floor(topCurrent);
    reached = NaN;
    note = sprintf(['Channel %s: its limit (%g mA) is below the %s cable''s calibration (from %g mA), '...
                    'so it runs at %g mA, irradiance unknown.'], cal.MeasuredOn, limitmA, cal.Cable, ...
                   cal.CurrentmA(1), mA);
    return
end
top = lum.led.irradiance(cal, topCurrent);
low = cal.IrradiancemWmm2(1);
if isnan(irradiance)
    target = top;
elseif irradiance > top + tolerance
    target = top;
    note = sprintf(['Channel %s: %.3g mW/mm2 is more than the %s cable gives on this channel '...
                    '(%.3g mW/mm2 at %g mA); it runs at %.3g mW/mm2.'], cal.MeasuredOn, irradiance, ...
                   cal.Cable, top, topCurrent, top);
elseif irradiance < low - tolerance
    target = low;
    if irradiance > 0
        note = sprintf(['Channel %s: %.3g mW/mm2 is below the %s cable''s lowest reading on this '...
                        'channel (%.3g mW/mm2 at %g mA); it runs at %g mA.'], cal.MeasuredOn, ...
                       irradiance, cal.Cable, low, cal.CurrentmA(1), cal.CurrentmA(1));
    end
else
    target = irradiance;
end
mA = min(lum.led.current(cal, target), floor(topCurrent));
reached = lum.led.irradiance(cal, mA);
