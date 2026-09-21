function led = openDoricLED(emulated, S)
% lum.dev.openDoricLED gives a session its Doric LED, and starts connecting to it.
%
% Called by lum.dev.open (D17). The LED is controlled from MATLAB when S.Doric.Enabled
% is on and the DoricLED package is found (S.Doric.Folder, or already on the MATLAB
% path): on the rig through the package's bridge to the driver, in the emulator through
% its SimulatedTransport. Connecting takes several seconds, so it runs in the
% background and this returns at once; lum.dev.DoricLED.ensureReady waits for it when
% the session starts.
%
% Otherwise the LED is 'Manual': nothing is sent, and the driver is used as it was set by
% hand, which must be external TTL mode for PulsePal's outputs to light it. That is the
% case without the package (the protocol runs without it, with a warning), and with
% Enabled off. Whether a session with light may start that way is lum.dev.open's call.
%
% Arguments:
%   emulated  True under Bpod('EMU'), as lum.dev.open found it
%   S         Settings; reads S.Doric
%
% Returns a lum.dev.DoricLED.
%
% See also: lum.dev.open, lum.dev.DoricLED, lum.dev.DoricLED.locatePackage

if ~S.Doric.Enabled
    led = lum.dev.DoricLED('Manual', [], 'control from MATLAB switched off');
    return
end
folder = lum.dev.DoricLED.locatePackage(S.Doric.Folder);
if isempty(folder)
    led = lum.dev.DoricLED('Manual', [], 'the DoricLED package was not found');
    warning('lum:dev:openDoricLED:noPackage', ...
            ['The DoricLED package was not found, so the LED driver is used as it was set by hand. '...
             'Set it to external TTL mode, or give the package''s folder on the Doric LED tab.']);
    return
end
if isempty(which('doric.LightSource'))
    addpath(folder);  % Session only; the saved path is untouched
end

if emulated
    transport = doric.transport.SimulatedTransport();
    source = doric.LightSource('Transport', transport, 'LogCapacity', 500);
    led = lum.dev.DoricLED('Simulated', source, 'emulator mode', transport);
else
    source = doric.LightSource('LogCapacity', 500);
    led = lum.dev.DoricLED('Device', source, sprintf('DoricLED package in %s', folder));
end
led.connect();
