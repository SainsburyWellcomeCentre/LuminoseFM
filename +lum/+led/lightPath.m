function path = lightPath(S, k)
% lum.led.lightPath says what carries optical channel k's light, and through what area.
%
% Channel A is lit by the Doric LED's channel 1 and B by its channel 2 (rig.Opto,
% docs/hardware.md). Each drives one cable of the fiber bundle on the animal
% (S.Light.Bundle, S.Light.Cables, lum.fiberBundles), and that cable ends in Spots
% fibers of CoreDiameter each. An LED calibration measures the power leaving that cable
% and divides it by the fibers' total area. It belongs to the cable on this channel: the
% same cable on the other channel is lit by another LED through another commutator
% channel, and has a calibration of its own (lum.led.calibrationFile).
%
% Arguments:
%   S  Settings struct; reads S.Light.Bundle and S.Light.Cables
%   k  1 for channel A, 2 for channel B
%
% Returns a struct:
%   .Channel      'A' or 'B'
%   .LEDChannel   The Doric driver's channel, 1 or 2
%   .Bundle       S.Light.Bundle
%   .Cable        The cable on channel k
%   .nFibers      Fibers at the cable's tip
%   .FiberDiameter  mm
%   .Area         Total fiber area at the tip, mm2
%
% Errors with 'lum:led:lightPath:<reason>' for an unknown bundle or cable.
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.fiberBundles, lum.led.calibrationFile, lum.led.loadCalibration

labels = {'A', 'B'};
if ~(isscalar(k) && any(k == [1 2]))
    error('lum:led:lightPath:badChannel', 'The optical channel must be 1 (A) or 2 (B).');
end
bundles = lum.fiberBundles();
bundle = bundles(strcmp({bundles.Name}, S.Light.Bundle));
if isempty(bundle)
    error('lum:led:lightPath:unknownBundle', 'Unknown fiber bundle "%s".', char(string(S.Light.Bundle)));
end
cables = S.Light.Cables;
if ~iscell(cables) || numel(cables) ~= 2
    error('lum:led:lightPath:badCables', 'S.Light.Cables must name two cables, A then B.');
end
cable = char(cables{k});
index = find(strcmp(bundle.Cables, cable), 1);
if isempty(index)
    error('lum:led:lightPath:unknownCable', 'The %s bundle has no %s cable.', bundle.Name, cable);
end
radius = bundle.CoreDiameter / 2;
path = struct('Channel', labels{k}, 'LEDChannel', k, 'Bundle', bundle.Name, 'Cable', cable, ...
              'nFibers', bundle.Spots(index), 'FiberDiameter', bundle.CoreDiameter, ...
              'Area', bundle.Spots(index) * pi * radius^2);
