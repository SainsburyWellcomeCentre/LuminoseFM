function bundles = fiberBundles()
% lum.fiberBundles describes the fiber bundles that can carry light to the bulb.
%
% The Doric LED has two channels, A (BNC1 -> PulsePal OUT1 -> LED ch1) and B
% (BNC2 -> OUT2 -> LED ch2), and each drives one cable of the bundle. Cables are named
% by their colour. The 2-to-19 bundle has two cables, blue and green; the 4-to-19 bundle
% has four, of which any two can be on the commutator. Which cable is on which channel
% can be changed at the commutator, so it is part of the session record
% (S.Light.Cables, A then B). The defaults when a bundle is chosen: blue on A and green
% on B for the 2-to-19, orange on A and blue on B for the 4-to-19.
%
% Spot counts are from docs/fiber_bundle_design. Each spot is the end of one fiber,
% 100 um across, so a cable's light leaves the bundle through Spots x pi x 50^2 um^2:
% the area an LED calibration divides the measured power by (lum.led.lightPath).
%
% Returns a struct array:
%   .Name           Value of S.Light.Bundle
%   .Cables         Cable names, by colour
%   .Spots          Light spots each cable makes on the bulb: its fibers at the tip
%   .Defaults       The cables on A and B when the bundle is first chosen
%   .CoreDiameter   Diameter of one fiber at the tip, mm
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.defaultSettings, lum.gui.DoricSetup, lum.led.lightPath

bundles = struct( ...
    'Name',         {'2-to-19', '4-to-19'}, ...
    'Cables',       {{'blue', 'green'}, {'black', 'blue', 'orange', 'green'}}, ...
    'Spots',        {[9 10], [4 5 5 5]}, ...
    'Defaults',     {{'blue', 'green'}, {'orange', 'blue'}}, ...
    'CoreDiameter', {0.1, 0.1});
