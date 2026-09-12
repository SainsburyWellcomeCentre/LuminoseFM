function pulsePal = openPulsePal(emulated, S, connect)
% lum.dev.openPulsePal connects PulsePal for a session, or refuses to start it.
%
% Bpod gates channels A and B into PulsePal's trigger inputs whether or not the session
% has programmed PulsePal, and PulsePal answers a gate with whatever program it last
% held: its power-on program, another protocol's, or a front-panel setting. That can be
% a trigger mode that starts a train on an edge and lets it run on, a train delay, both
% LED channels on one trigger, or an output looping continuously with no trigger at all.
% Light then comes at the wrong time or on the wrong channel, while the session file
% shows every light timer starting on the poke. So on the rig a session that delivers
% light does not start without PulsePal — there is no fallback to the null shim — and a
% connected PulsePal has every output stopped before anything else is sent.
%
% Once its outputs are stopped, PulsePal must answer a handshake (checkConnection): the
% explicit proof that the port reaches a live device before any light is gated.
%
% A session without light (S.Session.UseOpto off) never opens PulsePal, and the
% emulator gets the null shim. A sleep session sets UseOpto from its test pulses
% (lum.sleep.deviceSettings), so it is refused on the same terms.
%
% Arguments:
%   emulated  True under Bpod('EMU'), as lum.dev.open found it
%   S         Settings; S.Session.UseOpto says whether the session delivers light
%   connect   Optional function handle returning a connected lum.dev.PulsePal. Defaults
%             to lum.dev.RealPulsePal on the PulsePal folder beside Bpod_Gen2; tests pass
%             their own, because nothing in the test suite may open a port.
%
% Errors with 'lum:dev:openPulsePal:notConnected', quoting PulsePal's own message, when
% the session needs PulsePal and it cannot be connected and stopped.
%
% See also: lum.dev.open, lum.dev.RealPulsePal, lum.dev.PulsePal.stopOutputs

if ~S.Session.UseOpto
    pulsePal = lum.dev.NullPulsePal('optogenetic stimulus disabled for this session');
    return
end
if emulated
    pulsePal = lum.dev.NullPulsePal('emulator mode');
    pulsePal.stopOutputs();  % Logged, so the device log reads as it would on the rig
    pulsePal.checkConnection();
    return
end

if nargin < 3
    pulsePalRoot = fullfile(fileparts(fileparts(lum.repoRoot)), 'PulsePal');
    connect = @() lum.dev.RealPulsePal(pulsePalRoot);
end

pulsePal = [];
try
    pulsePal = connect();
    pulsePal.stopOutputs();
    pulsePal.checkConnection();
catch connectionError
    if ~isempty(pulsePal)
        pulsePal.close();
    end
    error('lum:dev:openPulsePal:notConnected', ...
          ['This session delivers light, but PulsePal could not be connected:\n  %s\n\n'...
           'The session has not started. Bpod would still gate channels A and B into '...
           'PulsePal, which would answer with whatever program it last held, so light '...
           'would come at the wrong times.\n'...
           'Check PulsePal''s USB cable, and close any PulsePal window or other MATLAB '...
           'that holds its port (restarting MATLAB releases it). Then start the session '...
           'again. To run without light, untick "Light pattern" on the setup dialog''s '...
           'Task tab.'], connectionError.message);
end
