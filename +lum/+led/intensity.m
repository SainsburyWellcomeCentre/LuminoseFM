function run = intensity(S, cals, type)
% lum.led.intensity is the LED current each channel starts a session at, and why.
%
%   run = lum.led.intensity(S, lum.led.calibrations(S), 'Behaviour')
%
% A session type asks for an intensity per channel (lum.led.intensitySetting). On a
% channel whose light path is calibrated it is the irradiance, turned into the current
% that gives it (lum.led.currentFor: never more than the channel's limit, and the most the
% channel gives when more is asked for). On a channel that is not calibrated it is the
% current typed in mA, so a bundle nobody has calibrated runs as before. An ePhys
% calibration session starts both channels at 0 mA; each step sets its own current.
%
% Arguments:
%   S     Settings; reads S.Doric.MaxCurrentmA, S.Light and the type's intensity
%   cals  1 x 2 cell of calibrations (lum.led.calibrations)
%   type  'Behaviour', 'Sleep' or 'EphysCalibration'; default S.Session.Type
%
% Returns a struct, stored as Data.Session.DoricLED.Intensity:
%   .Type             The session type
%   .IrradiancemWmm2  1 x 2, asked for (NaN for ePhys)
%   .TypedmA          1 x 2, the mA asked for where a channel is not calibrated
%   .Calibrated       1 x 2 logical
%   .CurrentmA        1 x 2, what the session sets up (whole mA)
%   .ReachedmWmm2     1 x 2, the irradiance CurrentmA gives (NaN without a calibration)
%   .Notes            Cell of sentences: out of reach, not calibrated
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.led.currentFor, lum.led.intensitySetting, lum.dev.open

if nargin < 3 || isempty(type)
    type = S.Session.Type;
end
labels = 'AB';
[asked, typed] = lum.led.intensitySetting(S, type);
limits = double(S.Doric.MaxCurrentmA);
run = struct('Type', char(type), 'IrradiancemWmm2', asked, 'TypedmA', typed, ...
             'Calibrated', [~isempty(cals{1}), ~isempty(cals{2})], 'CurrentmA', [0 0], ...
             'ReachedmWmm2', [NaN NaN], 'Notes', {{}});
if strcmp(type, 'EphysCalibration')
    for k = 1:2
        run.ReachedmWmm2(k) = lum.led.irradiance(cals{k}, 0);
    end
    return
end
for k = 1:2
    if run.Calibrated(k)
        [run.CurrentmA(k), run.ReachedmWmm2(k), note] = lum.led.currentFor(cals{k}, asked(k), limits(k));
        if ~isempty(note)
            run.Notes{end+1} = note;
        end
    else
        run.CurrentmA(k) = typed(k);
        path = lum.led.lightPath(S, k);
        run.Notes{end+1} = sprintf(['Channel %s: the %s cable is not calibrated on channel %s, so it runs '...
                                    'at %g mA.'], labels(k), path.Cable, labels(k), typed(k));
    end
end
