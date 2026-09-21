function bundles = fiberBundles()
% lum.fiberBundles describes the fiber bundles that can carry light to the bulb.
%
% The Doric LED has two channels, A (BNC1 -> PulsePal OUT1 -> LED ch1) and B
% (BNC2 -> OUT2 -> LED ch2), and each drives one cable of the bundle. The 2-to-19
% bundle has exactly two cables, so its mapping is fixed. The 4-to-19 bundle has
% four, of which any two can be on the commutator, so which cable is on which
% channel is part of the session record (S.Light.Cables). On this rig the orange
% cable is on A and the blue on B, the defaults when the 4-to-19 bundle is chosen.
%
% Spot counts are from docs/fiber_bundle_design. Each spot is the end of one fiber,
% 100 um across, so a cable's light leaves the bundle through Spots x pi x 50^2 um^2:
% the area an LED calibration divides the measured power by (lum.led.lightPath).
%
% Returns a struct array:
%   .Name           Value of S.Light.Bundle
%   .Cables         Cable names; for 2-to-19 the fixed channel 1 and channel 2 fibers
%   .Spots          Light spots each cable makes on the bulb: its fibers at the tip
%   .Choose         True when the operator picks which cables are connected
%   .Defaults       The cables on A and B when the bundle is first chosen
%   .CoreDiameter   Diameter of one fiber at the tip, mm
%
% This is a pure function: no hardware, no globals, unit-testable offline.
%
% See also: lum.defaultSettings, lum.gui.DoricSetup, lum.led.lightPath

bundles = struct( ...
    'Name',         {'2-to-19', '4-to-19'}, ...
    'Cables',       {{'ch1 fiber', 'ch2 fiber'}, {'black', 'blue', 'orange', 'green'}}, ...
    'Spots',        {[10 9], [4 5 5 5]}, ...
    'Choose',       {false, true}, ...
    'Defaults',     {{'ch1 fiber', 'ch2 fiber'}, {'orange', 'blue'}}, ...
    'CoreDiameter', {0.1, 0.1});
