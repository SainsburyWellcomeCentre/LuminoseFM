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
% 0.5.1 drives the behaviour trial's sync pulse from states rather than a global timer:
% before it, TrialStart's zero timer meant the next state re-wrote the line low within
% one cycle, so every fixed- and jittered-width pulse reached the recording as a ~100 us
% glitch (D4). Sessions from 0.2 to 0.5.0 have no usable trial pulses, though their
% barcode is sound; use Data.TrialStartTimestamp and the barcode to align them. The same
% release writes the cue's levels again in PreStimulusHold and the stimulus's in
% HoldBreak and CentreHoldResumed, adds S.Task.Variant and S.Task.ReverseContingency,
% gives habituation its own session shape (lum.stageDefaults) and tears a failed session
% down instead of leaving the protocol frozen. 0.6.0 adds automatic shaping, video through
% SpinCam (Session.Cameras, Data.CameraTime) and per-trial EarlyWithdrawals. 0.6.1 drives the
% house light (Data.HouseLight), saves the plots as an image (Session.PlotsImage) and writes
% the settings file again at the end of a session, fits the sync line to the cameras' frame
% rate (Session.SyncFit), switches the house light at once from PulsePal's output 3, looped
% back into BNC1 so each switch is a BNC1High/BNC1Low event (Session.HouseLight), and takes
% the subject from wherever the launch manager kept it. 0.7.0 adds the Doric LED, LED
% calibration and ePhys calibration sessions. 0.7.1 waits for each window's view to load
% before filling it (lum.gui.Form.waitForView): until then the behaviour setup dialog
% often stopped updating in a desktop session, and MATLAB then hung at the next window.
% The data format is unchanged. 0.7.2 names the 2-to-19 bundle's cables by colour (blue,
% green) and keys LED calibrations by bundle and cable, not channel. 0.8.0 adds habituation's
% centre reward (state CentreReward, Data.CentreReward), lets an unpunished incorrect choice
% go on to the correct port (state RetryResponse, Data.ResponseRetries; no punishment is the
% new default), lets a punishment noise play to its end, records Data.CentreHoldTime and
% plots it, and switches automatic shaping on for habituation as well as training. 0.8.1
% stops the camera window's timer from the teardown rather than from the console's End
% button (which froze MATLAB on the rig), calibrates LED power two cables at a time from
% one window, keeps the plots' keys off their data, and records how long the session
% took to start (Data.Session.Startup). 0.9.0 redesigns the stimulus families around what
% the animal tells apart (pure channel, mixture, sequence, order, motifs, hand-drawn;
% docs/stimulus_family.md, D20): each gives its groups a contingency of its own, used when
% S.Task.GroupPLeft is empty, and names its evidence and boundary (the mixture judges A's share
% of the light, or A minus B, against a boundary that can move); every stimulus set records
% how well one cue alone could do (StimulusSet.Shortcuts), and SweepName/SweepValues are gone.
% The same release lets the operator give the centre reward again, in any stage, for a set
% number of trials (S.GUI.CentreRewardAgain). 0.9.1 keys LED calibrations by cable and
% channel (the orange cable on A and on B are two calibrations), asks for the light's
% intensity in mW/mm2 on a calibrated channel (S.Doric.IrradiancemWmm2 8, sleep test pulses 2,
% ePhys pairs 8 and curve 0-12, or the channel's most) and in mA on one that is not, and
% records what each channel started at (Session.DoricLED.Intensity).
%
% See also: LuminoseFM

release = '0.9.1';
text = release;

try
    [status, output] = system(sprintf('git -C "%s" rev-parse --short HEAD', lum.repoRoot));
    if status == 0
        text = sprintf('%s+%s', release, strtrim(output));
    end
catch
    % No git, or no repository: the release number on its own is still useful.
end
