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
% PulsePal also drives the house light (output 3, lum.dev.HouseLight), so on the rig
% every session tries to open it — with or without light, behaviour or sleep. A session
% without light (S.Session.UseOpto off) that cannot have it runs on the null shim, with a
% warning, and without the house light (lum.dev.openHouseLight disables its switch). The
% emulator gets the null shim.
%
% Arguments:
%   emulated  True under Bpod('EMU'), as lum.dev.open found it
%   S         Settings; S.Session.UseOpto says whether the session delivers light, and so
%             whether it may run without PulsePal
%   connect   Optional function handle returning a connected lum.dev.PulsePal. Defaults
%             to lum.dev.RealPulsePal on the PulsePal folder beside Bpod_Gen2; tests pass
%             their own, because nothing in the test suite may open a port.
%
% Errors with 'lum:dev:openPulsePal:notConnected', quoting PulsePal's own message, when a
% session with light cannot have PulsePal connected, stopped and made to answer; warns with
% 'lum:dev:openPulsePal:noHouseLight' when a session without light cannot.
%
% See also: lum.dev.open, lum.dev.RealPulsePal, lum.dev.PulsePal.stopOutputs, lum.dev.HouseLight

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
    if ~S.Session.UseOpto
        % Nothing gates A and B in this session, so it may run; only the house light is lost.
        warning('lum:dev:openPulsePal:noHouseLight', ...
                ['PulsePal could not be connected: %s\nThis session delivers no light, so it '...
                 'runs, but without the house light, which PulsePal drives.'], connectionError.message);
        pulsePal = lum.dev.NullPulsePal(sprintf('connection failed: %s', connectionError.message));
        return
    end
    error('lum:dev:openPulsePal:notConnected', ...
          ['PulsePal could not be connected:\n  %s\n\n'...
           'The session has not started. This session delivers light, and without PulsePal '...
           'Bpod would still gate channels A and B into it, which would answer with whatever '...
           'program it last held, so light would come at the wrong times.\n'...
           'Check PulsePal''s USB cable and power, and close any PulsePal window or other '...
           'MATLAB that holds its port (restarting MATLAB releases it). Then start the '...
           'session again, or untick "Light pattern" on the Task tab to run without light '...
           '(and without the house light).'], connectionError.message);
end
