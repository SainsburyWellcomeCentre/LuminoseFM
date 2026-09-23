function varargout = intensitySetting(S, type, irradiance, currentmA)
% lum.led.intensitySetting reads or writes the LED intensity a session type asks for.
%
%   [mWmm2, mA] = lum.led.intensitySetting(S, 'Behaviour')
%   S = lum.led.intensitySetting(S, 'Sleep', mWmm2, mA)
%
% Each session type keeps its own intensity per channel, A then B, in two forms: the
% irradiance at the fiber tips (mW/mm2), used on a channel whose light path is calibrated,
% and the LED current (mA), used on one that is not (lum.led.intensity).
%
%   'Behaviour'         S.Doric.IrradiancemWmm2, S.Doric.CurrentmA (8 mW/mm2 by default)
%   'Sleep'             S.Sleep.TestPulses.IrradiancemWmm2, .CurrentmA (2 mW/mm2)
%   'EphysCalibration'  none: the schedule sets it step by step (S.Ephys); reads NaN,
%                       and writing it changes nothing
%
% Writing leaves a NaN argument's value as it was.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.intensity, lum.gui.DoricSetup

switch char(type)
    case 'Behaviour'
        path = {'Doric'};
    case 'Sleep'
        path = {'Sleep', 'TestPulses'};
    case 'EphysCalibration'
        path = {};
    otherwise
        error('lum:led:intensitySetting:badType', 'Unknown session type "%s".', char(type));
end
if nargin < 3
    if isempty(path)
        varargout = {[NaN NaN], [NaN NaN]};
    else
        holder = getfield(S, path{:});
        varargout = {double(holder.IrradiancemWmm2), double(holder.CurrentmA)};
    end
    return
end
if ~isempty(path)
    holder = getfield(S, path{:});
    for k = 1:2
        if ~isnan(irradiance(k))
            holder.IrradiancemWmm2(k) = irradiance(k);
        end
        if ~isnan(currentmA(k))
            holder.CurrentmA(k) = currentmA(k);
        end
    end
    S = setfield(S, path{:}, holder);
end
varargout = {S};
