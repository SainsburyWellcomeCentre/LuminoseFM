function notes = validate(S, cals, type)
% lum.led.validate checks the LED settings every session type shares (D17).
%
%   lum.led.validate(S)                  % errors only
%   notes = lum.led.validate(S, cals)
%   notes = lum.led.validate(S, cals, 'Sleep')
%
% S.Doric: two limits within the LED's 1000 mA rating; the calibration window's currents
% within it too; the session type's intensity
% (lum.led.intensitySetting): two irradiances, 0 or more, and two whole currents, 0 or
% more, each within its limit; and a light path for each channel on two different cables
% (lum.led.lightPath). None of this depends on a calibration, so lum.validateSettings,
% lum.sleep.validate and lum.ephys.validate run it without one. Given the channels'
% calibrations, it also says what each channel will run at where that is not what was
% asked (lum.led.intensity): an irradiance out of the channel's reach, or a channel with
% no calibration, which runs at the current in mA. It also notes a calibration that reads
% more than DarkLimit mW/mm2 with the LED at 0 mA: the power meter was not zeroed, so the
% current for a low irradiance comes out too high. None of these stops a session.
%
% Arguments:
%   S     Settings struct; reads S.Doric, S.Light and the type's intensity
%   cals  Optional 1 x 2 cell of calibrations (lum.led.calibrations)
%   type  Optional session type; default S.Session.Type
%
% Returns notes (empty without cals). Errors with 'lum:led:validate:<reason>'.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.intensity, lum.led.lightPath, lum.validateSettings, lum.gui.DoricSetup

if nargin < 3 || isempty(type)
    type = S.Session.Type;
end
notes = {};
d = S.Doric;
labels = 'AB';
if ~(isscalar(d.Enabled) && (islogical(d.Enabled) || ismember(d.Enabled, [0 1])))
    fail('badEnabled', 'S.Doric.Enabled must be true or false.');
end
limits = double(d.MaxCurrentmA);
if numel(limits) ~= 2 || any(~isfinite(limits)) || any(limits < 0) || any(limits > 1000)
    fail('badLimit', 'Each channel''s current limit must be between 0 and 1000 mA, the LED''s rating.');
end
if isfield(d, 'CalibrationCurrentsmA')
    start = double(d.CalibrationCurrentsmA);
    if isempty(start) || any(~isfinite(start(:))) || any(start(:) < 0) || any(start(:) > 1000)
        fail('badCalibrationCurrents', ['The calibration window''s currents must be between 0 and '...
             '1000 mA.']);
    end
end
[irradiance, currents] = lum.led.intensitySetting(S, type);
if ~strcmp(type, 'EphysCalibration')
    if numel(irradiance) ~= 2 || any(~isfinite(irradiance)) || any(irradiance < 0)
        fail('badIrradiance', 'Each channel''s irradiance must be a number of mW/mm2, 0 or more.');
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
end
paths = {lum.led.lightPath(S, 1), lum.led.lightPath(S, 2)};
if strcmp(paths{1}.Cable, paths{2}.Cable)
    fail('sameCable', 'Channels A and B are both on the %s cable. Choose two cables.', paths{1}.Cable);
end

if nargin < 2 || isempty(cals) || ~d.Enabled
    return
end
run = lum.led.intensity(S, cals, type);
notes = run.Notes;
darkLimit = 0.3;   % mW/mm2; calibrations made with the meter zeroed read <= 0.16 on the rig
for k = 1:min(2, numel(cals))
    cal = cals{k};
    if isempty(cal) || ~isfield(cal, 'CurrentmA') || ~isfield(cal, 'IrradiancemWmm2')
        continue
    end
    dark = cal.IrradiancemWmm2(cal.CurrentmA == 0);
    if ~isempty(dark) && dark(1) > darkLimit
        notes{end+1} = sprintf(['Channel %s: the %s cable''s calibration (%s) reads %.2f mW/mm2 '...
            'with the LED at 0 mA, so the power meter was probably not zeroed and low irradiances '...
            'get too much current. Calibrate it again.'], labels(k), cal.Cable, cal.Date, dark(1)); %#ok<AGROW>
    end
end


function fail(id, varargin)
error(['lum:led:validate:' id], varargin{:});
