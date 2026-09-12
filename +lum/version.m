function text = version()
% lum.version returns a version string for the LuminoseFM protocol.
%
% Recorded in every session file, so a data set can be traced back to the code
% that produced it. The git commit is appended when the repository is available
% and git can be run; otherwise the release number alone is returned.
%
% 0.2.0 renamed states and data fields (see docs/architecture.md, "Naming"), so
% analysis code has to read the version before it reads a session. 0.3.0 made a
% broken hold restart the stimulus, added the HoldNotCompleted outcome and the
% HoldAttempts series, added sleep sessions (Data.Session.Type) and corrected the
% analog timeline for the barcode (D10, D11). 0.4.0 keeps the cue on until the poke,
% starts the stimulus on the poke (the Cue, Cue2... and PreStimulusHold states are gone)
% and times each cue component from stimulus onset (D12). 0.4.1 refuses to start a
% session that delivers light without PulsePal, and stops PulsePal's outputs on
% connecting; before it, a session ran on with PulsePal unprogrammed, which its device
% log's first line records ("not connected (connection failed)"). 0.5.0 adds test
% pulses to sleep sessions (S.Sleep.TestPulses, Data.LightSegments, Session.TestPulses;
% D13), sends a sleep session's blocks as LevelNNN states in place of PulseNNN/GapNNN,
% has PulsePal answer a handshake before a session uses it, and rearranges the online
% plots (evidence u_A vs u_B and side bias; light on and off no longer compared).
%
% See also: LuminoseFM

release = '0.5.0';
text = release;

try
    [status, output] = system(sprintf('git -C "%s" rev-parse --short HEAD', lum.repoRoot));
    if status == 0
        text = sprintf('%s+%s', release, strtrim(output));
    end
catch
    % No git, or no repository: the release number on its own is still useful.
end
