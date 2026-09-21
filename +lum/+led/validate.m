function notes = validate(S, cals)
% lum.led.validate checks the LED settings every session type shares (D17).
%
%   lum.led.validate(S)          % errors only
%   notes = lum.led.validate(S, cals)
%
% S.Doric: two whole, non-negative currents (A, B), each within its limit, and two limits
% within the LED's 1000 mA rating; and a light path for each channel (lum.led.lightPath).
% None of this depends on a calibration, so lum.validateSettings, lum.sleep.validate and
% lum.ephys.validate run it without one. Given the channels' calibrations, it also says
% what each current delivers, and warns of a current outside its calibration.
%
% Arguments:
%   S     Settings struct; reads S.Doric and S.Light
%   cals  Optional 1 x 2 cell of calibrations (lum.led.calibrations)
%
% Returns notes (empty without cals). Errors with 'lum:led:validate:<reason>'.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.lightPath, lum.validateSettings, lum.gui.DoricSetup

notes = {};
d = S.Doric;
labels = 'AB';
if ~(isscalar(d.Enabled) && (islogical(d.Enabled) || ismember(d.Enabled, [0 1])))
    fail('badEnabled', 'S.Doric.Enabled must be true or false.');
end
limits = double(d.MaxCurrentmA);
currents = double(d.CurrentmA);
if numel(limits) ~= 2 || any(~isfinite(limits)) || any(limits < 0) || any(limits > 1000)
    fail('badLimit', 'Each channel''s current limit must be between 0 and 1000 mA, the LED''s rating.');
end
if numel(currents) ~= 2 || any(~isfinite(currents)) || any(currents < 0) || any(currents ~= round(currents))
    fail('badCurrent', 'Each channel''s LED current must be a whole number of mA, 0 or more.');
end
for k = 1:2
    if currents(k) > limits(k)
        fail('overLimit', 'Channel %s: the LED current (%g mA) is above its limit (%g mA).', ...
             labels(k), currents(k), limits(k));
    end
end
paths = {lum.led.lightPath(S, 1), lum.led.lightPath(S, 2)};
if strcmp(paths{1}.Cable, paths{2}.Cable)
    fail('sameCable', 'Channels A and B are both on the %s cable. Choose two cables.', paths{1}.Cable);
end

if nargin < 2 || ~d.Enabled
    return
end
for k = 1:2
    cal = cals{k};
    if ~isempty(cal) && isnan(lum.led.irradiance(cal, currents(k)))
        notes{end+1} = sprintf(['Channel %s: %g mA is outside its calibration (%g-%g mA), so its '...
                                'irradiance is not known.'], labels(k), currents(k), ...
                               cal.CurrentmA(1), cal.CurrentmA(end)); %#ok<AGROW>
    end
end


function fail(id, varargin)
error(['lum:led:validate:' id], varargin{:});
