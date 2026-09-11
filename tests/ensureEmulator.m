function ensureEmulator()
% ensureEmulator starts Bpod in emulator mode for the tests, or refuses to run.
%
% The tests must never touch the rig: a session may be running with an animal in
% the box. If a real state machine is already connected, this errors rather than
% quietly testing against hardware.
%
% See also: runLuminoseTests

global BpodSystem %#ok<GVMIS>

if ~isempty(BpodSystem) && isobject(BpodSystem) && isprop(BpodSystem, 'EmulatorMode')
    if BpodSystem.EmulatorMode == 1
        return
    end
    error('lum:tests:realHardware', ...
          ['A real Bpod state machine is connected. The tests refuse to run against '...
           'hardware. Close Bpod and start it with Bpod(''EMU'') instead.']);
end

Bpod('EMU');
