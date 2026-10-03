# LuminoseFM — Agent Instructions

Bpod protocol and helpers for a freely-moving 2-AFC olfactory-bulb optogenetics task (OSN-ChR mice,
patterned light through a fiber bundle), with home-cage sleep recordings and ePhys calibration
sessions on the same rig. The version is `lum.version`; what each release changed is in
`docs/naming-and-versions.md`.

`AGENTS.md` is a symlink to this file (for Codex, antigravity, OpenCode). If your platform did not
resolve the symlink, read `CLAUDE.md`.

**Contents:** [Start here](#start-here) · [Hard rules](#hard-rules) · [Environment](#environment) ·
[Code map](#code-map) · [Naming](#naming) · [Design rules](#design-rules) ·
[Comments and help text](#comments-and-help-text) · [Data](#data) ·
[The emulator](#the-emulator) · [Hardware map](#hardware-map) · [Gotchas](#gotchas) ·
[Tests and validation](#tests-and-validation) · [Docs](#docs) · [Git](#git)

---

## Start here

Read before changing anything: [`README.md`](README.md) (the operator's guide) and
[`docs/hardware.md`](docs/hardware.md) (the rig). Read [`docs/architecture.md`](docs/architecture.md)
before changing the stimulus path, the state graph, sleep blocks or the GUI. The rest of `docs/`:

| Document | Holds | Update it when |
|---|---|---|
| [`README.md`](README.md) | The operator's guide only: running a session, the task, the stimulus, the windows, the plots, sleep and ePhys sessions, utilities. It links to `docs/` for everything else, so reference material does not go back into it | anything the operator sees or does changes |
| [`docs/architecture.md`](docs/architecture.md) | Decisions D1–D22 (why, and what follows), the map from design to code, Bpod constraints, open questions | a design decision is made or changes |
| [`docs/hardware.md`](docs/hardware.md) | The box, the channel map, the light path, Flex I/O, the cameras, the software environment | the wiring, a device or a dependency changes |
| [`docs/data-format.md`](docs/data-format.md) | Every field of every session file, and reading older files | the data schema changes |
| [`docs/python-analysis.md`](docs/python-analysis.md) | Reading every file in Python, the clocks and their alignment, the planned HDF5 layout | any data file changes |
| [`docs/stimulus_family.md`](docs/stimulus_family.md) | The stimulus families from first principles (no biology): signal, descriptors, contingency, evidence, single-cue ceilings, each family, analysis recipes | a family, its defaults or the stimulus set's fields change |
| [`docs/sync-and-barcode.md`](docs/sync-and-barcode.md) | The sync TTL and the session barcode | anything on the sync line changes |
| [`docs/naming-and-versions.md`](docs/naming-and-versions.md) | The glossary, and what changed in each version (newest first) | every release, and every rename |
| [`docs/emulator.md`](docs/emulator.md) | What `Bpod('EMU')` does and does not reproduce | the emulator's behaviour or our reliance on it changes |
| [`docs/learning-time-literature.md`](docs/learning-time-literature.md) | Published learning times for odour and optogenetic-OB discrimination, each linked to its paper; the estimate for LuminoseFM's Training stage; LUMS0014's sessions so far; the light a trial delivers, the tissue heating it causes, the published light for OSN-ChR2 perception, ChR2(H134R) desensitization, the carrier options | an animal first shows a group split or reaches criterion, or the training procedure, the light's intensity or its carrier changes |
| [`docs/rig-checks.md`](docs/rig-checks.md) | How to run a rig check, the checks waiting for the operator (*Pending*), and every result (*Done*) | a rig check runs, or a change needs one |
| [`docs/validation-<date>.md`](docs/validation-2026-09-24.md) | A pre-deployment validation: inventory, results, fixes, open questions | a validation runs (a new file; old ones are records) |
| [`docs/repository.md`](docs/repository.md) | The repository layout and what each test file covers | files or tests are added |
| [`docs/code-style.md`](docs/code-style.md) | Getting help at the MATLAB prompt; how help text and comments are written; lint and the language server; what `helpTextTest` checks | the comment or help-text convention changes |
| `CLAUDE.md` (this file) | What an agent needs: rules, paths, conventions, hardware map, naming, gotchas | a convention, API or architectural decision changes |

**Where things stand** is in the docs, not here: the last release's changes in
`docs/naming-and-versions.md`, the checks waiting for someone at the rig in `docs/rig-checks.md`
*Pending* (P4–P13 now; all need someone at the rig or a desktop MATLAB, except P11 step 1, which
can run headless with permission; P13 step 4's file checks passed on 2026-09-27, and 0.9.11's
upload and 0.25 s ITI on 2026-09-28). The operator works remotely at times: run a pending check the next
time they say they are at the rig.

**Working loop.** Read the relevant docs and code → change `+lum` (the protocol file stays thin) →
add or update a test → bring the help text and comments of everything touched up to date
([Comments and help text](#comments-and-help-text)) → run the suite in one `-batch` MATLAB (zero
failures, zero lint, `helpTextTest` passing) → update every affected doc in the same change →
report what ran and what did not. Commit only when asked.

---

## Hard rules

1. **Never touch the rig without permission.** Do not open COM ports, call `Bpod` or `PulsePal`, or
   run the protocol against real hardware: the rig may be running an animal. Use `Bpod('EMU')` or
   pure-function tests, and hand hardware runs to the operator.
2. **Rig checks run only with the operator's permission**, given per request (no animal in the box);
   it covers that request only. Close nothing of theirs: if the desktop MATLAB holds COM3
   (`serialportlist('available')` lacks it), ask them to close it. Follow *How to run a check* in
   `docs/rig-checks.md`, record every result there under *Done*, and add to *Pending* anything that
   needs someone at the rig (seeing light, hearing sound, poking, moving a cable).
3. **Stay inside the working folder.** Create, edit or delete files only inside this repository.
   Everything else on the machine is read-only for you: `Bpod_Gen2/`, `Bpod Local/` (settings and
   calibration), `PulsePal/`, `SpinCam/`, `DoricLED/`, `generatePattern/`, `luminose_hf/`, the data
   folder, and MATLAB's own path and startup files. When something outside must change (Flex I/O
   configuration, the MATLAB path, a Bpod setting, a liquid calibration), tell the operator exactly
   what to change and where. SpinCam and DoricLED are changed only in their own repositories, under
   their own `CLAUDE.md`, and only when the operator asks.
4. **Resolve paths, do not hard-code them.** The absolute paths below describe this machine;
   `LuminoseFM` sits elsewhere on other setups. Resolve the repository root from the file you are
   editing or `lum.repoRoot`.
5. **Assume a fresh process.** The operator restarts MATLAB and power-cycles the state machine and
   PulsePal between sessions, and always after a session that ended in an error
   (`docs/hardware.md` §3). Do not add code that tries to recover a stale COM port.
6. **The emulator is a first-class target**: the protocol must run end to end under `Bpod('EMU')`
   with working windows, plots and data saving ([The emulator](#the-emulator)).
7. **Real-time first** ([Real-time](#real-time)): nothing slow, allocating or drawing in the trial
   loop outside its prepare window.
8. **Never replace a lit LED calibration point without a measurement.** Only a 0 mA (dark) point
   may be corrected in software, from the dark readings of other cables on the same channel; flag
   anything else for re-measurement (`docs/rig-checks.md` P4). Never change a liquid calibration.
9. **Docs in the same change** ([Docs](#docs)). If a doc statement turns out to be wrong, fix it.
10. **Commit only when asked** ([Git](#git)).

---

## Environment

Agents run in WSL; MATLAB and all hardware are on Windows.

| Thing | Path / value |
|---|---|
| Repo (edit here, from WSL) | `/mnt/c/Users/harrislab/Documents/MATLAB/HarrisLabBpodProtocols/LuminoseFM` |
| Same path from Windows | `C:\Users\harrislab\Documents\MATLAB\HarrisLabBpodProtocols\LuminoseFM` |
| MATLAB root | `/mnt/c/Users/harrislab/Documents/MATLAB` |
| MATLAB | R2025b (Update 3) primary; R2024b also installed. Base MATLAB only, no toolbox dependencies |
| Bpod_Gen2 | `../../Bpod_Gen2` (v1.9.0), on the saved MATLAB path |
| Bpod Local | `../../Bpod Local`: Bpod's settings and liquid calibration (not in this repo) |
| PulsePal | `../../PulsePal`, **not** on the saved MATLAB path; the protocol adds it |
| Examples | `../../Bpod_Gen2/Examples/Protocols`, and `../FreelyMoving2AFC` (the lab's earlier 2-AFC) |
| Stimulus generator origin | `../../generatePattern` (`generateStimuli.m`), ported into `+lum/+pattern/generate.m` |
| GUI inspiration | `../../luminose_hf` (head-fixed Luminose protocols): structure only, not its colours |
| SpinCam | `../../SpinCam`, the lab's camera package, its own repository (read its `CLAUDE.md` before touching the camera path). On the saved MATLAB path here; sessions name it by `S.Camera.SpinCamFolder`. Engine and package 1.3.0 (2026-09-28: the engine takes the Chameleon3's spurious 128 s timestamp steps out, `TimestampGuard`; changed in SpinCam's repository at the operator's request). Its `DefaultCameraNames` match ours: 24226887 `topview` |
| Spinnaker SDK | `C:\Program Files\Teledyne\Spinnaker` 4.2.0.83, .NET assemblies incl. `SpinVideoNET` in `bin64\vs2015`; SpinCam builds its engine against them with Windows' `csc.exe` (.NET Framework 4.8) |
| DoricLED | `../../DoricLED`, the Doric LED package (`doric.*`), its own project with its own `CLAUDE.md`; on the saved MATLAB path here, otherwise named by `S.Doric.Folder`. Its bridge `bin/doric_bridge.exe` runs `DoricSystem.dll` out of process. The driver is "LED Driver" on Doric port 4 (a rotary joint on port 3 is skipped by name) |
| LED calibrations | `calibration/` at the repo root: `DoricLED_<bundle>_<cable>_<A\|B>.mat` (+ `.png`) per cable and channel; a per-cable `DoricLED_<bundle>_<cable>.mat` (0.7.2–0.9.0) is still read for the channel it was measured on. Rig-local, git-ignored |
| Bpod `ProtocolFolder` | `C:\Users\harrislab\Documents\MATLAB\HarrisLabBpodProtocols\` |
| Bpod `DataFolder` | `D:\luminoseData\` = `/mnt/d/luminoseData`: session data live **outside** the repo |

```bash
# headless MATLAB from WSL: syntax checks and hardware-free tests
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch "checkcode('LuminoseFM.m')"
```

If that fails with `Exec format error` (or `MZ...: not found`), WSL's Windows interop is not
registered (systemd in `/etc/wsl.conf` often clears it). It is not a MATLAB problem, and an agent
cannot fix it without sudo. Ask the operator to run, in a WSL terminal:
`sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'`.

The rig's state as of the pre-deployment validation (2026-09-24, `docs/validation-2026-09-24.md`):
every device, and a behaviour, a sleep and an ePhys session with video, ran on the rig. Channel B
gives about 58% of A's irradiance on every cable.

---

## Code map

The protocol file is a thin session script; everything with logic in it lives in `+lum`, where it
can be tested with no hardware. `docs/repository.md` has the full tree.

| Path | What it owns |
|---|---|
| `LuminoseFM.m` | The session sequence: session type, setup, barcode, trial loop, teardown. Nothing else |
| `hardware/RigConfig.m` | The channel map and the connected machine's live limits |
| `hardware/CheckRig.m` | Preflight report |
| `hardware/TestHiFiSound.m` | Play a test sound outside a session |
| `hardware/TestSyncLine.m` | Drive the sync TTL outside a session, from states and from a global timer |
| `hardware/TestHouseLight.m` | Switch the house light through PulsePal and check each switch reaches BNC input 1 |
| `hardware/TestDoricLED.m` | Light A, then B, then both, through Bpod BNC → PulsePal → Doric driver, at one or more currents |
| `+lum/defaultSettings.m`, `mergeSettings.m` | The two-tier settings struct; old settings files converted (renames, reshapes, retirements) |
| `+lum/validateSettings.m` | Everything that must hold before a session starts; returns the stimulus set |
| `+lum/stageDefaults.m` | The session a training stage assumes: habituation is air and no light; shaping on in habituation and training |
| `+lum/timerBudget.m` | Global timers left for light after the hold window, hold clock, light clock and timed components |
| `+lum/buildTrialSM.m` | The state graph (fixed names; outputs, timers and transitions vary) |
| `+lum/cueTiming.m` | What each cue component does once the stimulus starts: continues, off, or timed (D12) |
| `+lum/nextTrialSpec.m` | Trial policy: follow the order, run limit and bias correction by swapping, stage, hold, centre reward |
| `+lum/newHistory.m`, `updateHistory.m` | The running history the policy reads, kept in O(1) per trial |
| `+lum/centreRewardAgain.m` | The centre reward asked for again mid-session: starts, ends and unticks its run |
| `+lum/HoldShaping.m` | Automatic shaping of the hold (active mode, next hold and grace, step back, description); break modes; the hold without growth (`fullHold`, `holdLength`, `isFixed`); whether the light may outlast the hold (`lightMayOutlastHold`) |
| `+lum/triggerStates.m` | The state that opens the prepare window: `WaitForCentrePoke`, as every trial starts (0.9.11) |
| `+lum/minimumITI.m` | The shortest ITI at which every trial starts on time (0.25 s with light, 0 without; the default ITI), and the warning for a shorter one |
| `+lum/scoreTrial.m`, `Outcome.m` | Outcome classification from states and events; the outcome codes |
| `+lum/punishmentFor.m` | Which mistakes are punished, and how; whether a wrong choice may be retried |
| `+lum/valveTimes.m` | Valve open times for a volume from Bpod's liquid calibration: 0 µL opens nothing, a volume past the fit's peak is refused, one outside the measurements noted. Every valve time goes through it |
| `+lum/SyncMode.m` | How trials drive the sync TTL; codes are part of the data format |
| `+lum/SessionRunner.m` | TrialManager on the rig, blocking in the emulator (D3) |
| `+lum/StartupTimes.m` | How long the session took to start, step by step (`Data.Session.Startup`) |
| `+lum/watchMemoryAfterSession.m` | A separate process sampling MATLAB's memory and threads for 4 min after a desktop session of any type (`<data file>_memory.csv`) |
| `+lum/OnlinePlots.m` | The behaviour session's live figure, nine panels: now and next, outcomes; performance, psychometric (along the family's evidence, or by group), evidence (u_A vs u_B with the contingency's boundary; *No light in this session* without light); by side, side bias, reaction time (log axis), centre hold (completed at any attempt, or not); header with water and the running hold. Habituation scores every trial by `Rewarded` (a trial without a choice is not rewarded); other stages score correct of the choices made. Hold attempts are not drawn here (no room): they are `09_HoldAttempts`. Every panel goes through `lum.gui.styleAxes` and every key through `lum.gui.panelLegend`: one row under the axis label, never over data |
| `+lum/holdMeasures.m` | What every plot, the log and the runtime window say about a trial's hold, from its states: hold completed (`CentreReward` or `WaitForCentreExit`), held on the first attempt, hold attempts (early withdrawals + the completed hold). `lum.scoreTrial` returns `HoldCompleted`, `HeldFirstAttempt`; not stored |
| `+lum/trialStatus.m` | The runtime window's header lines: how the last trial ended and what runs now |
| `+lum/loadSounds.m`, `testSounds.m`, `toneFrequencies.m` | The session's sounds, loaded once; a sound as `TestHiFiSound` arguments for the Play buttons; group tone spacing |
| `+lum/fiberBundles.m`, `experimentChoices.m` | Bundle cables and spot counts; the Experiment tab's lists |
| `+lum/mergeActions.m`, `timerMaskAction.m` | Output-action assembly (see [Gotchas](#bpod-and-firmware)) |
| `+lum/launchSubject.m`, `trainingStageNote.m` | The subject the session was launched for; one line on what the stage does to rewards |
| `+lum/+report/` | Summary plots and log (D22): `write` (the behaviour teardown's call; never throws), `summaryPlots` (12 plots, `09_HoldAttempts` the only one telling a first attempt from a later), `sessionLog`, `sessionTrials` (one pass over `SessionData`, hold measures included), `folder`, `fileTag`, `heading`, `replayOnlinePlots`, `fromFile` (a saved session, read only) |
| `+lum/+pattern/` | `generate` (families, groups, order, evidence, boundary) → `stimulusSet` (segments, budget) → `applyContingency` (P(left), reversal, checks, ceilings) → `patternAt`; `families`, `familyDefaults`, `typedPLeft`, `shortcuts`, `describeShortcuts`; `fromStates`, `canonicalise`, `check`, `validate`, `describe`; `withGeneratorDefaults`, `defaultPLeft`, `newSeed`, `prepareSeed` |
| `+lum/+stim/` | Components: `OptoPattern`, `TimedOutput` → `PortLight`, `Air`; `Sound`; `CueTone`; `build`; `isTimed`, `timerCost` |
| `+lum/+sync/` | Session barcode: `barcode` (kinds), `markerWidth`, `barcodeKinds`, `sleepMarkerWidth`, `barcodeValue`, `barcodeTime`, `decodeBarcode`, `barcodeStateMachine`; `fitToCameras` (widths the cameras can read) |
| `+lum/+sleep/` | Sleep and ePhys calibration sessions: `run`; sync pulses `pulseSchedule`, `syncPulseTimes`; test pulses `testPulsePlan`, `stepChoices`, `epochShape`, `describeTestPulses`, `describeTrain`, `untilRecordingEnds`; blocks `nextBlock`, `blockStateMachine`; `validate`, `validateClock`, `checkTimeline`, `validateTestPulses`, `deviceSettings`; `Plots` |
| `+lum/+ephys/` | ePhys calibration: `plan`, `validate`, `describe` |
| `+lum/+led/` | Light paths (`lightPath`); calibrations per cable and channel (`makeCalibration`, `saveCalibration`, `loadCalibration`, `calibrations`, `calibrationFile`, `calibrationFolder`, `checkCoverage`, `plotCalibration`); conversions (`irradiance`, `current`, `currentFor`, `toUnit`, `fromUnit`, `describe`); session intensity (`intensitySetting`, `intensity`, `keepIntensity`); `validate`; `sessionRecord` |
| `+lum/+dev/` | Device shims, real and null, selected by `open.m`: `PulsePal`, `HiFi`, `Flex` (also sends the barcode, opens the analog viewer, realigns the analog stream); `DoricLED` (`openDoricLED`); `HouseLight` real/null/disabled (`openHouseLight`); `Cameras` real/null (`openCameras`, `configureCameras`); `openPulsePal` |
| `+lum/+gui/` | `SessionTypeDialog`, `SetupDialog`, `SleepSetupDialog`, `EphysSetupDialog`, `DoricSetup` (Doric LED tab), `DoricCalibration`, `DoricWindow` (LED window), `IntensityField`, `CameraSetup` (Cameras tab, live preview), `CameraWindow`, `HelpLine`, `ExperimentForm`, `Form`, `StimulusDesigner`, `TestPulseDesigner`, `RuntimeWindow`, `PatternBrowser`, `savePlotsImage`, `houseLightSwitch`, `drawTrialFlow`, `drawTestPulseSchedule`, `drawTestPulseEpoch`, `runtimeFields`, `relabelParameterGUI`, `parseNumbers`, `theme` (colours and the plots' type scale), `styleAxes`, `panelLegend` (every plot panel and key), `logo` |
| `tests/` | `runLuminoseTests` runs everything; see [Tests and validation](#tests-and-validation) |

---

## Naming

Naming is part of the design: the operator, the plots and the data file all read the same words, and
a misleading name has already cost a data field its meaning once (`LeftProbabilityUsed`, which was
the bias target). Use these, and fix any code, label or doc that does not. The full glossary is in
`docs/naming-and-versions.md`.

| Word | Means | Not |
|---|---|---|
| channel A / B | optical channels, BNC1 / BNC2 | pattern 1/2, ch1/ch2, BNC in operator text |
| light pattern | what one trial delivers on A and B | schedule, spec, stimulus (alone) |
| joint state | 0 dark, 1 A only, 2 B only, 3 A and B | silence (for light) |
| group | one stimulus condition; K groups balanced over the session | stimulus index, trial type |
| stimulus set | patterns + groups + contingency + trial order | dictionary |
| stimulus family | the question a stimulus set asks: pure channel, mixture, sequence, order, motifs, hand-drawn pulses (`Generator.Family`: `pure`, `mixture`, `count`, `order`, `motif`, `arbitrary`) | paradigm, stimulus type |
| amount | how long a channel is lit: u_A, u_B (s), or a fraction of the window | duration (alone), occupancy |
| decision rule | the mixture's contingency (`MixtureRule`): `share` or `difference`, each against a boundary that can move, or the controls `A alone`, `B alone` | boundary (that is its line in the plane) |
| A share, mixture ratio | A's relative abundance, u_A / (u_A + u_B); typed as ratios A:B (`MixtureRatios`, `MixtureShareBoundary`) | proportion (in operator text), B share (its complement, `Descriptors.BShare`) |
| total light | u_A + u_B, what the relative rules rove (`MixtureShareTotals`, `MixtureDifferenceTotals`) | concentration, intensity |
| flash | one light segment in the sequence and motif families; slot, word, letter, turn as in `stimulus_family.md` | pulse (PulsePal's carrier pulses fill it) |
| evidence | a family's decision variable, the psychometric axis (`StimulusSet.Evidence`) | sweep |
| single-cue ceiling | best score reading one cue alone (`StimulusSet.Shortcuts`, `lum.pattern.shortcuts`) | shortcut score |
| family's contingency | the P(left) a family gives its groups (`FamilyPLeft`), used when `S.Task.GroupPLeft` is empty | default P(left) |
| stimulus window | `S.Stimulus.Duration` from stimulus onset | stimulus duration of the hold |
| latency | `S.Stimulus.Latency`, poke to stimulus onset, held with the cue on | delay, pre-stimulus hold (as a setting) |
| hold / hold break / grace | centre hold; leaving during it; forgiven break length | |
| hold window | `S.GUI.HoldWindow`, from trial start, across restarts | initiation window (0.2 name) |
| fixed hold | the hold without growth set in seconds from stimulus onset (*Hold without shaping* *Fixed*: `S.GUI.HoldLength` 2, `S.GUI.FixedHold`); *Whole stimulus* is the window plus the post-stimulus hold | minimum hold |
| drinking grace | after a side reward, time out of both side ports before the trial ends (`S.GUI.DrinkingGrace`, 0.3 s; a side poke restarts it) | grace (alone: that is the hold's) |
| light clock | the global timer as long as a trial's light that `WaitForLightEnd` waits for after a completed hold shorter than the light (`plan.lightClock`, `reserved.LightClock`, D21) | stimulus timer |
| automatic shaping | performance-driven training under one switch (`S.Task.AutoShaping`): now the centre hold, method `S.Task.HoldShaping`; later trial difficulty | hold shaping *Off* (the 0.5 mode) |
| step back | automatic shaping shortening the hold one growth step after `HoldStepBackAfter` early withdrawals at one hold | regress, reset (in names too) |
| early withdrawal | leaving the centre port before the hold is complete, unforgiven (state `EarlyWithdrawal`) | hold break (that is the forgiven kind) |
| hold completed | the hold ran its full length, at any attempt: `CentreReward` or `WaitForCentreExit` visited (`lum.holdMeasures`); a hold completed after early withdrawals is completed | successful hold, held (alone) |
| hold attempt | a poke that began a hold: each early withdrawal plus the completed hold; a forgiven break is part of its attempt (equals `Data.HoldAttempts` without a latency) | retry (that is the side choice's), try |
| held on the first attempt | hold completed with no early withdrawal before it (`HeldFirstAttempt`) | first-try hold, clean hold |
| centre reward | water at the centre port for a completed hold, habituation's first `CentreRewardTrials` trials (state `CentreReward`, `Data.CentreReward`) | centre drop, initiation reward |
| centre reward again | the centre reward given again in any stage, `CentreRewardAgainTrials` trials from a tick of `S.GUI.CentreRewardAgain` (`lum.centreRewardAgain`) | reactivated reward, bonus |
| retry | going on to the correct port after an unpunished incorrect choice (state `RetryResponse`, `Data.ResponseRetries`) | correction trial (it is the same trial) |
| centre hold time | seconds in the centre port on a trial's last hold, poke to exit (`Data.CentreHoldTime`) | hold duration (that is what the trial asked for) |
| task variant | which variant of the task a session runs: Familiar/Novel, Mixture, Sequence, Motifs (`S.Task.Variant`) | task type, paradigm |
| contingency reversal | swapping which side every group pays, P(left) to 1 - P(left) (`S.Task.ReverseContingency`) | flip, switch |
| session type | `'Behaviour'`, `'Sleep'` or `'EphysCalibration'` (`S.Session.Type`, `Data.Session.Type`); shown as Behaviour, Sleep, ePhys calibration (`lum.gui.Form.sessionLabel`) | protocol, mode |
| carrier | PulsePal per-channel frequency, pulse width, voltage | waveform |
| test pulses | light in a sleep session: probes and plasticity trains on a schedule (`S.Sleep.TestPulses`) | opto stimulation, stim |
| epoch | one probe (single pulse or pair) or one train; never split across state machines | trial, sweep |
| inter-pulse / inter-epoch interval | onset to onset: within a pair; between epochs | gap, ISI (unqualified) |
| plasticity train | named bursts-of-pulses definition (theta burst, high frequency, custom) | protocol, stimulation |
| schedule step | one row of `S.Sleep.TestPulses.Schedule`: probe, rest or a train name | block (a block is a state machine run) |
| light segment | one gate on A or B; a probe pulse, or a burst PulsePal fills (`LightSegments`) | pulse, when it is a burst |
| view | a camera's name and file prefix: `sideview`, `topview` | camera name, cam1 |
| camera clock | SpinCam's host clock: `HostTime_s`, `_events.csv`, `Data.CameraTime` | video time |
| house light | the white light in the box, on PulsePal OUT3, looped back into BNC input 1 (`S.Session.HouseLight`, `S.Sleep.HouseLight`, `S.Ephys.HouseLight`, `Data.HouseLight`, `Session.HouseLight`) | room light, port 5 light |
| LED current | the Doric driver's current on LED ch1 (A) or ch2 (B), mA: how bright a gated channel is (`Data.LEDCurrentA/B`, `LightSegments.CurrentmA`; asked for as `S.Doric.CurrentmA` on an uncalibrated channel) | LED power, voltage, intensity (as a stored value) |
| light path | one optical channel and the bundle cable on it (`lum.led.lightPath`) | fiber (alone) |
| irradiance | power at the fiber tips over their area, mW/mm²: what a session asks for on a calibrated light path (`S.Doric.IrradiancemWmm2`, `S.Sleep.TestPulses.IrradiancemWmm2`, `S.Ephys`) | power density, intensity (as a stored value) |
| LED calibration | power meter readings at several currents for one cable on one channel (`lum.led`, `calibration/`) | power curve |
| LED window | the session window that shows and changes each channel's LED current (`lum.gui.DoricWindow`) | runtime window (that is the parameters') |
| ePhys calibration | the third session type, `'EphysCalibration'` (`S.Ephys`, D18) | calibration session, ephys mode |
| input-output curve, paired-pulse ratio | the two ePhys calibration protocols (`S.Ephys.InputOutput`, `S.Ephys.PairedPulse`) | IO sweep, PPR (in operator text) |
| summary plots | a behaviour session's plots over the whole session, one image each, in `Session Plots` (`lum.report.summaryPlots`, D22) | report, figures |
| session log | a behaviour session's settings and behaviour as Markdown, in `Session Logs` (`lum.report.sessionLog`, D22) | notes, summary |
| centre | British spelling in identifiers too (`CentreHold`) | `Center` |

**Rename by migration.** Add the old → new path to the rename table in `lum.mergeSettings`, so
existing settings files keep their values, and record it in `docs/naming-and-versions.md`. Never
renumber a stored code (`lum.Outcome`, `lum.SyncMode`, punishment codes), and never reuse a retired
name (families `sequence`, `occupancy`, `overlap_order`, `tiled_order`) for something else: data files
keep them.

---

## Design rules

Each rule below is guarded in code; the decision behind it (D*n*) is in `docs/architecture.md`.

### Session structure

- **Entry point.** `LuminoseFM.m` in the repo root. Bpod's launch manager requires
  `<ProtocolFolder>/<Name>/<Name>.m`, so the file name must match the folder name `LuminoseFM`
  exactly (case included). Helpers go in subfolders, never nested protocols; the protocol file stays
  a thin session script, and reusable code goes in `+lum` (or `hardware/` for rig utilities usable
  outside a session, e.g. `TestHiFiSound.m`).
- **Code style.** 4-space indent, `camelCase` locals, `PascalCase` classes, no snake_case names.
  Follow Bpod idiom over general MATLAB idiom: `global BpodSystem`, settings struct `S`,
  `S.GUI.*` / `S.GUIMeta.*` / `S.GUIPanels.*` / `S.GUITabs.*`, `SaveBpodSessionData`. Never name a
  variable after a builtin (`set`, `image`, `now`): the stimulus set variable is `stimulusSet`. Write
  code that reads like the code around it, and help text and comments as
  [Comments and help text](#comments-and-help-text) says.
- **Three session types, one protocol (D11, D18).** `LuminoseFM` opens `lum.gui.SessionTypeDialog`
  first; *Sleep* and *ePhys calibration* hand the whole session to `lum.sleep.run`, which must release
  every `lum.*` object, the LED included, before returning. Headless runs
  (`setappdata(0, 'LuminoseFM_Headless', true)`) take the type from `S.Session.Type`. Sleep and ePhys
  sessions run blocks with blocking `RunStateMachine` on the rig too: they have nothing to prepare,
  so `SessionRunner` does not apply. All three setup dialogs build `S.Meta` through
  `lum.gui.ExperimentForm`; add an experiment field there once.
- **The subject** comes from `lum.launchSubject(BpodSystem.GUIData.SubjectName,
  BpodSystem.Status.CurrentSubjectName, BpodSystem.Path.CurrentDataFile)`: the launch manager's
  Launch button always sets `GUIData.SubjectName`, but `Status.CurrentSubjectName` only when the
  subject list's selection changes (sessions up to 0.6.1 had an empty subject).
- **Startup times (0.8.1).** Each startup step gets a `startup.lap(...)` in both `LuminoseFM` and
  `lum.sleep.run` (`lum.StartupTimes`, `Data.Session.Startup`: each step's seconds, dialogs marked as
  the operator's, `Parts.devices` per device from `lum.dev.open`'s `devices.openSeconds`; printed as
  the first trial or block starts). The object is cleared before the loop: no `lum.*` object may
  outlive `RunProtocol('Stop')`.
- **A cancelled launch leaves no files.** The launch manager opens `<data file>_ANLG.dat` before the
  protocol runs; every "setup cancelled" path calls `lum.dev.Flex.discardEmptyAnalogFile` (closes
  the handle, deletes the file while it is empty).
- **A failed session is torn down, not abandoned.** The trial loop is wrapped in a `try`: on an
  error the completed trials are saved, the analog stream merged, the windows closed, the devices
  released and `RunProtocol('Stop')` called (which flushes the serial link), and only then is the
  error warned about, with `Data.Session.StoppedReason` recording it. `lum.SessionRunner` reports a
  lost Bpod link as `lum:SessionRunner:linkLost`. Anything added to the loop must keep working when
  it is entered part way through. The setup from opening the devices to trial 1 is wrapped too
  (`abandonSetup`: windows closed, video stopped, devices released, then the error), and so are
  `lum.sleep.run`'s setup and block loop (an error there is the session's `StoppedReason`, and the
  normal teardown saves what was sent). Put new setup steps inside them.
- **Teardown order (D14, D16, D22)**, as `LuminoseFM.m` runs it: close the camera and LED windows
  (they are not Bpod's protocol figures) → save the plot figure as `<data file name>_plots.png`
  (`lum.gui.savePlotsImage`, path in `Data.Session.PlotsImage`) → session records, analog merge,
  final save → close the trial manager → write the settings back to the file captured at start
  (`settingsFile`; headless sessions write none) → stop the video with
  `finishRecording('SessionSaved', n)` and a second small save for its summary → close the runtime
  window and the plots → `closeDevices` (the LED first, the house light before PulsePal) →
  (behaviour) `lum.report.write` → (desktop) `lum.watchMemoryAfterSession` → `RunProtocol('Stop')`
  → `unlinkFromBaseWorkspace` → `announceFinished` (the console's *MATLAB can be closed*, 0.9.12:
  operators close MATLAB at once, and closed earlier the report or memory record is lost). Keep every step in both teardowns (`LuminoseFM` and `lum.sleep.run`)
  except the report, which is behaviour's alone; nothing from `+lum` may run after Stop.
- **`unlinkFromBaseWorkspace` is the last step of every session path** (0.9.7, local to
  `LuminoseFM.m`): `clear BpodSystem` in the base workspace; the global stays. With `BpodSystem`
  listed in the base workspace, R2025b's Workspace browser works through the session's changes to it
  once the prompt returns and ran MATLAB out of memory after rig behaviour sessions (D16). Never put
  `BpodSystem` back in the base workspace from our code. A desktop session of any type also ends by
  starting `lum.watchMemoryAfterSession`.
- **Settings written at Start and at teardown (D16)**, runtime changes included. Before every
  settings write, `lum.dev.Cameras.keepCrop` stores the session type's crops back and `lum.led.keepIntensity`
  the LED window's changes (teardown); keep both calls with any new settings write, in both scripts.
- **Crops per session type (0.9.6, D14).** `S.Camera.Crops.Behaviour/.Sleep/.EphysCalibration`
  (`Serial`, `Roi`). `lum.dev.Cameras.cropFor(S.Camera, type)` sets `S.Camera.Cameras(k).Roi` once
  the session type is known (`LuminoseFM` and `lum.sleep.run`); everything else (the Cameras tab,
  `configureCameras`, the record) reads `Cameras(k).Roi`.

### Settings and windows

- **One GUI, two tiers, one declaration (D2).** `S` is split by *when a parameter stops being
  editable*, not by who sets it; both tiers are editable in `lum.gui.SetupDialog`.
  - Declare a runtime parameter on one line of `lum.defaultSettings` through
    `numericParam`/`checkboxParam`/`menuParam` (value, `GUIMeta.Label` with units, `GUIMeta.Limits`,
    help), add it to an `S.GUIPanels` entry, and put the panel in an `S.GUITabs` entry. It then
    appears in the setup dialog (Runtime tab, or the Task tab for the `Shaping` panel), in the tabbed
    runtime window and in Bpod's compact one; there is no second list to update.
  - `GUIMeta.Label` and `GUIMeta.Limits` are ours. The tabbed `lum.gui.RuntimeWindow` shows and
    enforces them; Bpod's `BpodParameterGUI` (the compact window) ignores them, supports `GUIPanels`
    but **not** `GUITabs`, and labels controls with field names, so `lum.gui.relabelParameterGUI(S)`
    runs straight after its `init`.
  - Declarations always come from the defaults when settings are merged: GUIMeta, GUIPanels,
    GUITabs, `Sync.ModeNames`, `Task.TrainingStageNames`.
  - `lum.validateSettings` is the single definition of "can this session start": the setup dialog
    runs it on every edit (with the last compiled stimulus set passed in when the stimulus settings
    have not changed), the Start button runs it, and `LuminoseFM` runs it again before opening any
    device.
  - Components are switched on from the Task tab's checkboxes, which are the `Enabled` flags
    themselves; the Cue/Stimulus/Left/Right tabs time them and show on/off chips. Do not add a second
    enable control for a component on its own tab.
  - Settings shown in several places are one setting each: the hold (Task tab and the Runtime tab's
    Timing panel) and the stimulus window (Stimulus tab, Task tab, Timing panel) are kept in step by
    `linkTwins`/`syncTwins` in the setup dialog; add a copy the same way.
- **Help line.** Every runtime parameter declares its help as the last argument of its declaration
  (`GUIMeta.<name>.Help`); `lum.gui.HelpLine` shows it, and any control's `Tooltip`, at the foot of
  the setup dialogs and the tabbed runtime window. Give new controls a tooltip that explains them,
  not just names them; register the help line after the window's callbacks are set (it chains them).
- **Training stage (`lum.stageDefaults`).** Choosing *Habituation* in the setup dialog switches the
  light pattern off (`S.Session.UseOpto`, `S.GUI.OptoOn`), the stimulus air on for the whole window
  and the centre light cue on (unless the centre light is a stimulus component); *Training* and
  *Experiment* do the reverse. *Habituation* and *Training* also switch automatic shaping on,
  *Experiment* off. These are defaults, applied only on the dropdown's change, never during a
  session and never enforced by validation, **except** automatic shaping in an Experiment session,
  which `lum.validateSettings` refuses (`shapingInExperiment`). `stateMachineTest` checks a
  habituation trial built from the defaults.
- **Task variant.** `S.Task.Variant` (Familiar/Novel, Mixture, Sequence, Motifs;
  `lum.experimentChoices().TaskVariants`) names the task and is recorded; it chooses nothing yet.
  Per-variant defaults will go beside `lum.stageDefaults`.
- **Play buttons.** `lum.testSounds(S, which, nGroups)` turns the dialog's settings into
  `TestHiFiSound` argument lists; the dialog's `'SoundPlayer'` option lets tests record them. Group
  tone frequencies come from `lum.toneFrequencies`, shared with `lum.loadSounds`.
- **Look.** Windows draw with `lum.gui.theme`: light, neutral, colour only for meaning (channel A
  teal, B coral; left navy `#3E5C76`, right gold `#D4A72C`; correct sage `#78A874` filled,
  incorrect rust `#A6503F` open (chosen by the operator, 2026-09-27, from rendered options; they
  differ in lightness so they stay apart for a red-green colour-blind reader); held after early
  withdrawals pale sage; greys for trials
  without a choice; `t.Series` near black for a series with no side or outcome, `t.SeriesSoft` for
  its faint companions). The plot colours were checked with the dataviz skill's validator: rerun it
  before changing one, and keep a second cue (marker shape) where a pair is close under
  colour-vision simulation. Plots are for print: white figures (`t.PlotBackground`), dark axes and
  tick labels (`t.Axis`), marks large (dots 14, lines 1.6–2.4). Every plot panel is styled by
  `lum.gui.styleAxes` (theme `Font`: one family, title 12, label 11, tick and key 10 points; the
  live figures, `lum.OnlinePlots` and `lum.sleep.Plots`, use `FontCompact`, title 10, the rest 9;
  regular-weight sentence-case titles; horizontal gridlines only; no top or right edge) and keyed by
  `lum.gui.panelLegend`, in the online, sleep and summary plots alike; never style an axis by hand
  or add a second y-axis. The summary plots print at 150 dpi with the size set on the paper
  (`PaperPosition`): an invisible figure can apply a new `Position` late. `t.Good`, `t.Bad`,
  `t.Warn` are text colours for the dialogs, not plot marks. `windowsTest`'s
  `testOnlinePlotsKeepTheirTextInside` and `testSleepPlotsKeepTheirTextInside` fail when a title,
  label or key leaves the window or runs into another at the session size: keep them passing when
  changing type, labels or titles. Do not copy luminose_hf's dark palette.
  The logo comes from `lum.gui.logo(n)` (block-averaged, cached, no toolbox).
- **The hold in plots (0.9.9, D22).** Every plot, the log and the runtime window read the hold from
  `lum.holdMeasures` (through `lum.scoreTrial` or `lum.report.sessionTrials`), never from ad hoc
  state checks or the outcome code: a hold completed after early withdrawals is a completed hold,
  and early withdrawals are no outcome category or colour of their own. Only `09_HoldAttempts`
  tells a first attempt from a later one.
- **Every new uifigure waits for its view** (`lum.gui.Form.waitForView(fig)` straight after
  `uifigure(...)`), and is checked once from a desktop MATLAB ([Gotchas](#matlab-windows-and-tests)).

### The behaviour trial

**Trial-flow contract.** State names stay fixed across stimulus modalities, cues and hold shaping:
trial start, waiting for the poke with the cue on, pre-stimulus hold (the latency), centre hold,
hold break, resumed hold, centre reward, centre exit, response, reward, incorrect choice, retry,
waiting for the light to end, ITI. Settings change only the `OutputActions`, state timers, global
timers and where a poke, a completed hold or a wrong side poke leads. Plots, analysis and
`lum.scoreTrial` depend on this. Every state exists in every trial, reachable or not.

```
TrialStart → WaitForCentrePoke (cue) → [PreStimulusHold (latency)] → CentreHold (stimulus)
           → [CentreReward] → WaitForCentreExit → WaitForResponse
           → {*RewardDelay → *Reward → Drinking* → DrinkingGrace | IncorrectChoice | NoResponse}
           → WaitForLightEnd → ITI
WaitForResponse → RetryResponse → WaitForResponse            (wrong side, not punished)
CentreHold → EarlyWithdrawal (no grace) | HoldBreak ⇄ CentreHoldResumed (grace)
EarlyWithdrawal → WaitForCentrePoke (Restart stimulus) | WaitForLightEnd (End trial)
WaitForCentrePoke → NoInitiation → WaitForLightEnd           (hold window over)
```

- **The cue lasts until the stimulus starts, `S.Stimulus.Latency` after the poke (D12).** Every cue
  component is an output of `WaitForCentrePoke`, which has no timer. `Port2In` there leads to
  `PreStimulusHold` when the latency is above 0 and straight to `CentreHold` at 0, the default: never
  put a state or a delay on the zero-latency path. `PreStimulusHold` lasts the latency, starts
  nothing, leaves the cue on, and leaving it goes to `EarlyWithdrawal` (a broken hold; grace is timed
  from stimulus onset and does not apply). From stimulus onset each cue component follows
  `lum.cueTiming`: *Whole* (continues until the hold ends, the default), *Off* (off as the stimulus
  starts) or *Timed* (off that long into the stimulus). A timed centre light or air is a global
  timer triggered and cancelled with the stimulus's; the cue tone is a loop (`Cue`) replaced at
  stimulus onset by a tail (`CueTail`) or stopped, never a timer (`lum.stim.CueTone`). Cue components
  answer `onsetActions` for `CentreHold`. The latency is a pre-session setting, so `HoldDuration`
  stays the hold from stimulus onset.
- **The stimulus plays only while the animal holds (D10).** `EarlyWithdrawal` cancels it; with
  `S.Task.OnHoldBreak` *Restart stimulus* (default) it returns to `WaitForCentrePoke`, and the next
  `CentreHold` re-triggers every stimulus timer. The hold window is a global timer triggered only in
  `TrialStart` and never cancelled; `WaitForCentrePoke` has no state timer and leaves on that timer's
  end or condition 4. Never trigger or cancel the hold window anywhere else.
- **Grace (D6).** `HoldBreak` and `CentreHoldResumed` exist in every trial. Without grace they are
  unreachable; with it, `CentreHold` triggers the stimulus timers and the hold clock, and
  `CentreHoldResumed` must **not** re-trigger them.
- **A completed hold leaves the light to play to its end (D21).** The hold ending (`CentreReward`,
  `WaitForCentreExit`, `WaitForResponse`) stops the cue, the other stimulus components and the hold
  clock, never the light's timers or lines; only `EarlyWithdrawal` cancels the light. Every path that
  ends the trial goes through `WaitForLightEnd` to the `ITI`. When the trial's light ends after its
  hold, the builder adds the **light clock** (a global timer as long as the light, onset 0,
  triggered in `CentreHold`, cancelled in `EarlyWithdrawal`) and condition 5 (clock not running);
  `WaitForLightEnd` leaves on either, and otherwise passes straight on. Every session with light
  (`lum.HoldShaping.lightMayOutlastHold`, from 0.9.8, since the hold can be set shorter than the
  window between trials) reserves the clock (`lum.timerBudget`). Decide it from pre-session
  settings only; never let the light's timers be cancelled at the hold's end again, and never end a
  trial while the light may be on.
- **The next trial is prepared and uploaded as each trial starts (0.9.11, D3).** The prepare window
  opens on `WaitForCentrePoke` (`lum.triggerStates`), the state every trial enters from
  `TrialStart`: `lum.SessionRunner.awaitPrepareWindow` waits for the running trial to leave its
  first state (*Gotchas*, the dead time warning). The window may overlap the trial's light: building and uploading a state machine
  does not touch it (rig check 2026-09-28: no missed-deadline codes, every light timer exact), but a
  device command would. So `prepareTrial` sends nothing to a device; the loop asks
  `needsDevices` (`lum.dev.DoricLED.hasPending`, `lum.stim.Component.needsConfigure`), and a
  trial that needs an LED current or a PulsePal program waits for the running trial's `ITI`
  (`lum.SessionRunner.awaitState`: the light is over), gets them (`changeDevices`) and only then is
  uploaded (`Data.Timing.devices`). The default ITI covers that (`lum.minimumITI`), so it starts
  on time too; a shorter ITI delays it with one dead time warning. Any new device command a trial
  needs goes through the same two functions. A runtime setting or LED change made during trial *k*
  reaches trial *k*+2 when trial *k*+1 was already prepared. Because a trial is always queued, the
  End button starts it unrecorded (*Gotchas*, the End button); a change to how a session stops
  must deal with that trial.
- **The hold ends in `WaitForCentreExit`**, which waits for `Port2Out` (or condition 3, the centre
  port already clear) before opening the response window. Do not shortcut `CentreHold` straight
  into `WaitForResponse`: the side ports would be live with the animal's nose still in the centre
  port, and its withdrawal beam break would be scored as a choice.
- **The ITI is 0.25 s by default (0.9.11), `lum.minimumITI`: the shortest at which every trial
  starts one ITI after the last one's light.** The next trial was uploaded with `RunASAP` during
  this one, and the state machine starts it the cycle after the ITI (0.1 ms). A trial after an LED
  current change (the LED window; the stimulus window is fixed for the session, so PulsePal is
  programmed only before trial 1) is uploaded in the ITI instead, after the command; 0.25 s covers
  it and the upload (upload median 45 ms, at most 213 ms in 810 rig trials; rig check 2026-09-28:
  88–124 ms for the change and upload, every gap 0.1 ms). The operator
  may type less, 0 s included: kept, with a warning (`uialert` in the setup dialog, `warndlg` in
  the runtime window, a validation note, a console warning when changed mid-session), because such a
  trial then starts late. Without light the minimum is 0 (nothing waits). A settings file from
  before 0.9.11 (no `Session.SettingsVersion`) still at 0.9.8's 0 s takes 0.25 s. Nothing may rely
  on the ITI for time between trials: a sound, a valve, a line or a punishment that must last lasts
  in its own state (the drinking grace, the punishment states' noise, `NoInitiation` for
  task-event sync). `BpodTrialManager`'s *inter-trial dead time of >500 microseconds* warning means
  a trial started after its upload: expected only after an LED-window change with an ITI below
  the minimum (the console says so on the line before). From 0.9.8 to
  0.9.10 a session with light prepared in the ITI at 0 s, so every trial started 0.01–0.35 s late
  with the warning (LUMS0014, 2026-09-28: 332 of 332 gaps, median 196 ms, with no state machine
  running and no pokes recorded).
- **No reward delay, no withdrawal (0.9.6).** A side valve opens only after a poke at a paying
  port: `WaitForResponse` -`PortNIn`→ `*RewardDelay` -`Tup`→ `*Reward`, and nothing else enters those
  states (`stateMachineTest` checks it). With `S.GUI.RewardDelay` 0 the `*RewardDelay` states leave
  only on `Tup` (one cycle after the poke), so a beam flicker cannot forfeit the reward. With a
  delay, leaving goes to `WithdrewBeforeReward`.
- **Centre reward and retries (D19).** A completed hold goes through `CentreReward` (centre valve
  open for the calibrated time, response configuration up) only when `spec.CentreReward` (amount
  above 0 and either habituation with trial number ≤ `S.GUI.CentreRewardTrials`, or a run of
  *Centre reward again*; `lum.nextTrialSpec`); never put it on the poke's path. The run is kept by
  `lum.centreRewardAgain` in `history.centreRewardAgainFrom`, called as the next trial is prepared,
  before `nextTrialSpec`; it unticks `S.GUI.CentreRewardAgain` when its trials are done, and the session
  syncs the runtime window again so the box shows it at once. A wrong side poke goes to
  `RetryResponse` (0 s, back to `WaitForResponse`, whose timer restarts) when
  `lum.punishmentFor(S, 'IncorrectChoice').Retry` (the default, `PunishCondition` 1), and to
  `IncorrectChoice` (timeout, noise, no reward, ITI) when punished. A punishment that plays the noise
  lasts at least `S.Sound.NoiseDuration`, because the ITI sends the HiFi stop command.
- **The HiFi module plays one sound at a time**; a new play command replaces the sound playing.
  `lum.validateSettings` refuses two sounds that start with the stimulus (`soundClash`), and with
  restarts an early-withdrawal noise is let finish before `WaitForCentrePoke` plays the cue tone
  again.
- **States, not timers, for what happens outside the stimulus**: the cue before stimulus onset, the
  latency, the barcode, every trial sync pulse (D4), and a sleep session's sync and test pulses
  (D13). Global timers are for what happens inside the hold, where leaving the port must end it at
  any instant: light segments (D1), the grace hold clock (D6), stimulus components switched on late
  or off early (D9), cue components switched off part way through the stimulus (D12), and the light
  clock (D21).
- **Output actions do not persist across states** ([Gotchas](#bpod-and-firmware)).
  `lum.stim.Component.sustainActions`/`sustainOnsetActions` are the repetitions a later state writes
  to keep a level on: the same levels, without the timer triggers that must fire once and without
  the play commands that would restart a sound. `PreStimulusHold` sustains the cue; `HoldBreak` and
  `CentreHoldResumed` sustain the stimulus, so a forgiven break does not switch the air or the centre
  light off; `WaitForResponse` repeats `WaitForCentreExit`'s guide lights.
- **Automatic shaping (D6).** `S.Task.AutoShaping` (off by default) switches it; decide everything
  through `lum.HoldShaping.activeMode(S)` / `growsHold(S)` / `hasGrace(S)`, never by reading
  `S.Task.HoldShaping`, which has no *Off* any more (old files are migrated in `lum.mergeSettings`).
  Grow hold starts at `HoldStart` 0.2 s, grows `HoldGrowth` 1% per completed hold, targets
  `HoldTarget` 0.6 s (defaults since 0.9.7; a settings file keeps its own), and steps back one growth
  step after `S.GUI.HoldStepBackAfter` (10) early withdrawals at one hold (`history.withdrawalsAtHold`,
  kept by `lum.updateHistory`). Each step is taken from the hold of the trial still running
  (`lum.HoldShaping.notePrepared`, called as the next trial is prepared, after `nextTrialSpec`), so every
  completed hold is one step, one trial late. A session that grew the hold writes `S.GUI.HoldStart`
  = 90% of its last trial's `HoldDuration` into the settings file at teardown
  (`lum.HoldShaping.nextSessionStart`, `handOnHold` in `LuminoseFM`), from the settings file only,
  never from earlier data files. Future difficulty shaping goes under the same switch.
- **The hold without growth** is `lum.HoldShaping.fullHold(S)`: *Whole stimulus* (window plus
  post-stimulus hold) or *Fixed* (`S.GUI.HoldLength` 2, `S.GUI.FixedHold`), runtime settings on the
  Timing panel since 0.9.8, read through `lum.HoldShaping.holdLength`/`isFixed`. An Experiment session
  may use a fixed hold; a growing hold replaces either.
- **Trial *k*+1 is prepared before trial *k* is recorded** (both runners). A policy that steps from
  the last *recorded* trial splits the session into odd and even chains (automatic shaping did until
  0.9.4; the run limit lagged until 0.9.8). Step from the trial still running (`history.prepared*`,
  `lum.HoldShaping.notePrepared`), and test in the session's order.

### Stimulus

- **The stimulus is a stimulus set (D5).** `lum.pattern.generate` makes the patterns and a balanced
  order from `S.Stimulus.Generator` and a seed; `lum.pattern.stimulusSet` compiles it into segments
  and refuses a pattern over the timer budget; `lum.pattern.applyContingency` applies
  `S.Task.GroupPLeft` (empty: the family's `FamilyPLeft`) and then `S.Task.ReverseContingency`
  (`GroupPLeft` is the contingency as run, `BasePLeft` before the reversal, `Reversed` says which),
  refuses identical groups paying different sides, and measures the single-cue ceilings
  (`lum.pattern.shortcuts`). `lum.pattern.patternAt(set, k)` recovers one pattern.
- **Seeds.** `lum.pattern.prepareSeed` draws the seed per session before the setup dialog opens, so
  the preview is the session and no two sessions of an animal repeat their trials by default. To
  repeat one, the operator types its saved seed (`Session.StimulusSet.Seed`, also in the plots'
  header) into the Stimulus tab's *Seed*; *Randomise trials* draws a new one.
  `lum.pattern.newSeed` keeps one clock-seeded stream per MATLAB process. The generator uses a private
  `RandStream`, never the global rng. Never make a session depend on finding earlier data files:
  data move to the cloud.
- **A stimulus family is a question (D20, `docs/stimulus_family.md`).** `lum.pattern.families` is the
  one list (name, label, question, description, what a pattern per trial means). Each family derives
  its groups from its own settings (`nGroups` is the hand-drawn family's alone), gives each group a
  side (`FamilyPLeft`), and names its evidence and boundary. Choosing a family (designer, or the
  Stimulus tab's *Family*) applies `lum.pattern.familyDefaults(generator, family, budget, window)`;
  the mixture's cycles depend on all three (`MixtureLayout` `'spread'` shares each amount over
  `MixtureCycles` cycles, two timers each), and given the window it makes the bin finer, never
  coarser, when the defaults cannot be drawn in it.
- **Every family's defaults must compile with no warning at every budget a session can leave for
  light**: 4, 3 and 2 in the emulator, 15, 14 and 13 on the rig (a session with light has at most 3
  and 14), in the default window and in a coarse one. `generateTest` checks it; a new family or
  default must pass it. The setup dialog reloads an untouched family's defaults when the budget
  changes (`followBudget`: stage, shaping) and leaves an edited stimulus alone.
- **Typed P(left)** is kept only while the group labels are unchanged (`lum.pattern.typedPLeft`); the
  dialogs compile with the family's contingency and apply a typed one on top. Fractions of the window
  are shared over whole bins (never demand that one setting divides another), and the bin is adjusted
  to the window. Old families are converted in `lum.mergeSettings`.
- **The optical carrier is per channel.** `S.Light.Carrier` is a struct array, one element per
  optical channel, each with `Channel`, `Frequency`, `PulseWidth`, `Voltage`; `lum.stim.OptoPattern`
  adds `MaxDuration`. Element *k* programs PulsePal output *k*, and a mismatched `Channel` field is
  rejected (`lum.dev.PulsePal.validateCarrier`, static: no device and no log line). A pulse must be
  shorter than the period (80 ms at 20 Hz is refused); `Frequency` 0 is constant light while the
  gate is high (one pulse as long as the train, the window + 0.1 s), the pulse width ignored.
- **Determinism.** Anything that must be sub-millisecond accurate lives in the state machine or
  PulsePal, not in MATLAB loop code.

### Sync and barcode

- **The sync TTL is driven by states in every mode (D4).** `S.Session.UseSync` says whether the line
  is driven, `S.Sync.Mode` (`lum.SyncMode`: FixedWidth, JitteredWidth, TaskEvents) how trials drive
  it. A pulsed mode makes the pulse `TrialStart`'s own state timer and drops the line in
  `WaitForCentrePoke` as the cue comes on. `TaskEvents` leaves `TrialStart` at zero, holds the line
  high through `WaitForCentrePoke`, and drops it on the poke (in `PreStimulusHold`, or `CentreHold`
  without a latency) and in `NoInitiation`, which lasts two frame periods with video (0.9.8) because
  a 0 s ITI lets the next trial raise the line 0.1 ms later.
- **No mode costs a global timer, and none may.** Before 0.5.1 a pulsed mode was a global timer
  linked to the channel and triggered in `TrialStart`; its zero timer meant `WaitForCentrePoke`
  re-wrote the line low one cycle later, so every pulse reached the recording as a ~100 µs glitch
  while the barcode came through perfectly. Never drive the sync line from a global timer again.
- **The mode is part of the data format**: it decides what a rising edge in the ephys file means, so
  it is written to every trial record. Append modes, never renumber them.
- **The session barcode** (`lum.sync.barcode`, D7) is sent once, by `devices.flex.sendBarcode`, as
  its own state machine before the runner is created. Its markers carry the session type:
  `MarkerWidth` (behaviour), `SleepMarkerWidth` (sleep), `EphysMarkerWidth` (ePhys calibration;
  `lum.sync.markerWidth`).
- **Anything new on the sync line goes through `lum.sync.fitToCameras`.** A frame samples the line
  once, so with video the session fits the line to the cameras (barcode elements and sync pulses
  ≥ 2 frames, bit and marker widths ≥ 3 frames apart). Typed widths are minimums and stay in the
  settings file; sessions send and record the fitted ones (`Session.SyncFit`).
- `hardware/TestSyncLine.m` drives the line both ways outside a session, for the operator to scope.

### Devices

- **One reader of emulator mode.** `lum.dev.open` is the **only** file that reads
  `BpodSystem.EmulatorMode` (the rig utilities in `hardware/` read it for themselves). It builds
  real or null device shims once at startup, and every null shim logs what it would have done into
  `Data.Session.DeviceLog`. Anything else that behaves differently in the emulator is told so via
  `devices.emulated`; the runtime window choice in `LuminoseFM.m` is the example.
- **The Doric LED (D17).** Intensity is the driver's, timing stays Bpod's and PulsePal's: both LED
  channels in external TTL mode, the state machine untouched. `lum.dev.DoricLED` ('Device',
  'Simulated', 'Manual'), chosen by `lum.dev.openDoricLED`, wraps `doric.LightSource` through its
  public API only: `connect('Wait', false)`, `apply`, `startAll`,
  `Channels(k).setCurrent/MaxCurrentmA`, `stopAll`, `disconnect`, `record`, `poll`.
  - `LuminoseFM` opens it before the session type dialog (`lum.dev.open(rig, S, 'Only',
    'DoricLED')`, so `open.m` stays the only reader of emulator mode) and it connects in the
    background; the dialogs get it as `'DoricLED'`; `lum.dev.open(..., 'DoricLED', led)` waits
    (`ensureReady`) and sets it up (`setUp`), and refuses a session with light (or any ePhys session)
    on the rig when it fails. **Every return path releases it** (`releaseLED`), and both teardowns
    close it first (`closeDevices`).
  - Currents change only between trials, in the running trial's ITI (`applyPending(trial)`,
    which returns what the next trial runs at; the loop asks `hasPending` as it prepares, and holds
    that trial's upload back until then), or between blocks (`applyPending(block)`; ePhys
    `setCurrents(step.CurrentmA)`, blocking). Nothing is sent per trial otherwise: a change is one
    non-blocking command per channel (~0.8 ms MATLAB-side, 5–9 ms to the driver's acknowledgement),
    with no light gated.
  - **Intensity (0.9.1).** Each session type keeps its intensity per channel in two forms, read and
    written only through `lum.led.intensitySetting(S, type)`: irradiance for a calibrated channel and
    mA for one that is not. Behaviour `S.Doric.IrradiancemWmm2` [8 8] / `S.Doric.CurrentmA`; sleep
    `S.Sleep.TestPulses.IrradiancemWmm2` [2 2] / `.CurrentmA`; ePhys per protocol
    (`S.Ephys.InputOutput.Min/MaxIrradiancemWmm2` [0 0]/[12 12] with `MinmA`/`MaxmA`, NaN = the limit;
    `S.Ephys.PairedPulse.IrradiancemWmm2` [8 8] with `CurrentmA`). `lum.led.intensity(S, cals, type)`
    resolves the start currents (passed to `lum.dev.open` as `'LEDCurrentmA'`) through
    `lum.led.currentFor`, which never exceeds the limit and runs an out-of-reach irradiance at the
    channel's most with a note. Never refuse a session for either, nor for a missing calibration:
    that channel runs in mA. Both teardowns write LED-window changes back with
    `lum.led.keepIntensity`. `lum.gui.IntensityField` holds both forms and shows the one that
    applies; `DoricSetup` takes `'Intensity'` (`'Behaviour'`, `'Sleep'`, `'EphysCalibration'` greys it
    out).
  - **Calibrations are per cable and channel** (`lum.led.calibrationFile`): the orange cable on A and
    on B are two calibrations, because the light leaving a cable depends on the LED and commutator
    channel feeding it. `loadCalibration` falls back to a 0.7.2–0.9.0 per-cable file only when its
    `MeasuredOn` is the path's channel. They are measured two cables at a time from the Doric LED
    tab's **Calibrate LED power…** (`lum.gui.DoricCalibration(bundle, {cableA, cableB}, ...)`:
    continuous mode, 0–1000 mA in 100 mA steps from `S.Doric.CalibrationCurrentsmA`, capped at each
    channel's limit, starting from that cable's saved readings on that channel, loaded with
    `loadCalibration(path, folder, false)`), saved to `calibration/`, and replaced by the next one of
    that cable on that channel.
  - **A calibration is saved and used only when it covers the LED's range** (`lum.led.checkCoverage`:
    4 readings above 0 mA, the highest ≥ 400 mA); `saveCalibration` refuses one that does not, and
    `loadCalibration` treats it as none (the channel in mA, with a warning). One that stops below
    the limit is used to its highest reading (`currentFor`).
  - **The limit** `S.Doric.MaxCurrentmA` is 1000 mA by default since 0.9.3, the LED's rating and
    DoricLED's hard ceiling (`doric.Channel.DeviceMaxCurrentmA`). DoricLED's own default (700 mA,
    Doric's recommendation for light held on) is not changed from here: `lum.dev.DoricLED.setUp` sets
    the session's limit. `lum.mergeSettings` turns a 0.9.2 file's 700 mA into 1000 (a file without
    `Doric.CalibrationCurrentsmA`). The driver's front knob caps the current independently of USB.
  - `lum.led.validate(S, cals, type)` is the LED check every session's validation runs (errors
    independent of calibrations; notes only when given them). DoricLED is optional: without it, or
    with `S.Doric.Enabled` off, the driver is used as set by hand and currents are NaN.
- **PulsePal (D1, D15).** Every session on the rig opens PulsePal (`lum.dev.openPulsePal`, any
  session type), for the house light. A session with light refuses to start without it; one without
  light (`S.Session.UseOpto` off; sleep sets it from test pulses) runs on the null shim with a
  warning, and without the house light. `openPulsePal` stops every output (`stopOutputs`) on
  connecting and requires a handshake (`PulsePal.checkConnection`). Do not reintroduce a fallback for
  a light session ([Gotchas](#pulsepal)). Reprogram PulsePal only between trials or blocks, never
  mid-stimulus.
- **The house light (D15)** is PulsePal's, not Bpod's: **PulsePal OUT3** → BNC splitter → the
  light's LED driver, and the copy into **Bpod BNC input 1** (`rig.HouseLight`: `PulsePalChannel` 3,
  `Voltage` 5, `Input` `'BNC1'`, `OnEvent` `'BNC1High'`, `OffEvent` `'BNC1Low'`).
  - Switched at once, mid-trial and mid-block, by `devices.houseLight` (`lum.dev.HouseLight`:
    `RealHouseLight` on the rig, `NullHouseLight` in the emulator). It starts at
    `S.Session.HouseLight` (setup dialog, Experiment tab), `S.Sleep.HouseLight` or
    `S.Ephys.HouseLight`; during a session the only switch is the **House light** box in the live
    figure's header (`lum.gui.houseLightSwitch`, in `lum.OnlinePlots` and `lum.sleep.Plots`). It is
    not a runtime-tier parameter (a 0.6.1 file's `GUI.HouseLight` is renamed on load).
  - **Holding it**: `lum.dev.PulsePal.holdVoltage(3, 5|0, done)` sets OUT3's resting voltage
    (parameter 17), which the firmware returns to after every stop, abort and disconnect, then writes
    the voltage to the output (op 79), and unlinks OUT3 from both trigger inputs. Only outputs 3–4 may
    be held. Set when `lum.dev.open` builds the device; 0 V when it is closed, which `closeDevices`
    does **before** PulsePal. **The state machine has no part in it**: no timer, no output, no state.
    Never add one, and nothing else may use OUT3 or BNC input 1.
  - Choose the light only through `lum.dev.openHouseLight`: a session without PulsePal, or whose
    connected PulsePal refuses the light's level, gets `lum.dev.DisabledHouseLight` (off,
    `Switchable` false, the box greyed out), and both teardowns keep the settings' level rather than
    writing `On` back.
  - **Sharing the port**: a click's callback runs inside any `pause`/`drawnow`, including PulsePal's
    handshake (0.1 s) and serial code. `lum.dev.PulsePal` counts commands under way (`enter`/`leave`
    around `configure`, `stopOutputs`, `checkConnection`); `holdVoltage` during one is sent when it
    finishes (latest per output wins). **Any new PulsePal command must go through the same guard.**
    The light, the camera mark, the record and the windows change when PulsePal takes it (`done`), not
    at the click; a refusal warns and puts the boxes back.
  - **Recorded**: a switch during a state machine is a `BNC1High`/`BNC1Low` event on Bpod's clock
    (the loopback wire); in the emulator `NullHouseLight.echo` puts that edge into the running
    emulated state machine (`VirtualManualOverrideBytes` `'V'`, as the console's BNC input button). A
    switch between state machines has no Bpod event. Every switch is also `cameras.mark('HouseLight')`.
    `Data.HouseLight` per trial or block is `lum.dev.HouseLight.levelAtStart(events, rig.HouseLight,
    fallback)`: the first edge decides; with no edge, `houseLight.levelAt(arrival time − trial
    length)` on MATLAB's clock. `Data.Session.HouseLight = houseLight.record(BpodSystem.Data)`.
  - Check it on the rig with `hardware/TestHouseLight` (soft codes from a state machine call
    `houseLight.set`, restoring Bpod's `SoftCodeHandlerFunction` after; each switch must come back as
    a BNC1 edge). It runs under `Bpod('EMU')` too (`houseLightTest`).
- **Video (D14).** `devices.cameras` (`lum.dev.openCameras`): on the rig a session with
  `S.Camera.Enabled` refuses to start without SpinCam or a ticked camera; in the emulator it uses
  SpinCam's mock cameras or the null shim.
  - `lum.dev.configureCameras` is the only place settings become camera state (the session and the
    Cameras tab preview both use it). Recording starts right after `lum.dev.open`, before the
    barcode; per trial only `devices.cameras.mark` runs. It stops after the final save (teardown
    order above), so everything in the data file is on the video. Never write video anywhere but
    `lum.dev.Cameras.videoFolder(dataFile)`.
  - Only native formats (`lum.dev.Cameras.Formats`); `matlab-*` would be starved by the trial loop.
    The default is `avi-mjpeg-mt` (SpinCam's multi-core MJPEG, engine 1.2.0); SpinVideo's
    `avi-mjpeg` has 4 % headroom at 100 Hz full frame and fell behind with the camera window open,
    and `lum.dev.Cameras.formatNote` says so at validation. Each format has one sentence in
    `lum.dev.Cameras.FormatDescriptions` (same order as `Formats`; `cameraTest` checks one sentence
    each), shown as the dropdown's tooltip and on the help line through `CameraSetup.useHelpLine`
    (called by the setup dialogs after `registerTooltips`). Add a format to both lists together.
  - `lum.dev.openCameras` refuses a SpinVideo format (`needsSpinVideo`) when the engine lacks
    SpinVideo (`SpinCam.Engine.HasSpinVideo`), before recording starts;
    `Session.Cameras.EngineVersion` records `SpinCam.Engine.Version`.
  - The Cameras tab crops with the mouse (**Draw crop**, press–drag–release on a tile;
    `CameraSetup.cropTile` maps picture to sensor pixels) or a typed `x,y wxh`
    (`lum.dev.Cameras.parseCrop`); the drag borrows and returns the help line's pointer callbacks.
  - The camera window (`lum.gui.CameraWindow`) is not one of `BpodSystem.ProtocolFigures`: the
    teardown closes it ([Gotchas](#bpod-and-firmware), the End button). Use only SpinCam's public
    API (`spincam.CameraManager`, `VideoRecorder`, `SpinCam.Engine`), never `spincam.internal.*`.
    The dependency list is `docs/hardware.md` §3.

### Sleep and ePhys calibration sessions

- **Test pulses (D13).** Light in a sleep session goes the behaviour way: Bpod gates BNC1/BNC2,
  PulsePal fills each gate (constant light for a probe, the train's pulses for a burst).
  `lum.sleep.testPulsePlan` compiles the schedule into gates and epochs in integer 100 µs cycles
  before the session; `lum.sleep.syncPulseTimes` lays out the sync pulses; `lum.sleep.nextBlock`
  cuts both into ~10 s state machines **only where every line is low, never inside an epoch, and
  before the first epoch of a new step**; `lum.sleep.blockStateMachine` makes one `LevelNNN` state
  per span between edges. No global timers. PulsePal is programmed only between blocks, after
  `checkConnection`, and checked again at every save; a failure ends the session with
  `StoppedReason`. Open devices through `lum.sleep.deviceSettings`, so a session with test pulses is
  refused without PulsePal. `lum.sleep.validateTestPulses` is the one check the designer, the sleep
  dialog and the session share.
- **The default schedule (0.9.2)** is paired probes *Alternate A and B*, 30 s apart, so no epoch
  lights both channels; *A and B* stays a step's choice, never the default (presets and new steps in
  the designer alternate too). The last probe or rest step may have Minutes `Inf`: it goes on until
  the recording ends, which lasts `S.Sleep.DurationMinutes` (`lum.sleep.untilRecordingEnds`;
  `lum.sleep.testPulsePlan(tp, recordingMinutes)`); the default schedule is one such step. Otherwise,
  with test pulses on, the recording lasts as long as the schedule.
- **ePhys calibration (D18).** `lum.ephys.plan` compiles each step (an input-output level or a
  paired-pulse interval) through `lum.sleep.testPulsePlan` as a probe step and joins them into one
  plan of the same shape, adding per step `Protocol`, `Label`, `CurrentmA`, `IrradiancemWmm2`,
  `InterPulseInterval`, and returns notes (an irradiance out of reach, a channel in mA). Levels and
  pairs are in mW/mm² on a calibrated channel, in mA otherwise; the curve's top defaults to
  12 mW/mm² or the channel's most. `lum.ephys.validate` requires `S.Doric.Enabled` and uses the
  checks shared with sleep (`lum.sleep.validateClock`, `lum.sleep.checkTimeline`). `lum.sleep.run`
  runs it with `S.Ephys.Sync`, `S.Ephys.HouseLight`, `lum.gui.EphysSetupDialog` and barcode kind
  `'EphysCalibration'`.
- **A block stopped by the End button** returns no events from `RunStateMachine`, though its pulses up
  to the stop reach the recordings, so its plan is kept as `Data.Session.StoppedBlock` (0.9.7).

### Real-time

This is the hard constraint of the project.

- Drive trials through `lum.SessionRunner`, which uses `BpodTrialManager` on the rig and blocking
  `RunStateMachine` calls in the emulator (D3). All per-trial work belongs in the prepare window it
  opens as each trial starts; device commands wait for the trial's ITI (*The next trial is prepared
  and uploaded as each trial starts*).
- Preallocate; never grow arrays, structs or plot data inside the trial loop.
- No `figure`, `plot`, `cla` or bare `drawnow` in the loop: update existing handles
  (`set(h,'YData',...)`) and use `drawnow limitrate` at most once per trial. The setup dialog and
  designers may redraw freely; they never run during a session.
- Keep per-trial cost O(1): maintain running stats, don't re-scan `BpodSystem.Data`.
  `lum.nextTrialSpec` searches the rest of the queue for a swap (a vectorised test over at most
  `MaxTrials` indices, microseconds; `MaxTrials` is 3000 by default from 0.9.11 so bias correction
  does not run out of trials of the side it pushes towards, and nothing per trial grew with it:
  preallocate by `MaxTrials`, never loop over it in the trial loop); bias correction takes precedence over the run limit, and the
  run limit, like shaping, counts the trial still running (`history.preparedSide`, 0.9.8).
- Don't store large per-trial copies: a session-level set plus per-trial indices.
- Reprogram PulsePal and HiFi only between trials (in the running trial's ITI or later), never
  mid-stimulus. Sounds are loaded once (`lum.loadSounds`, only those the session can play).
- `SaveBpodSessionData` rewrites the whole file: keep the struct small, save on an interval, never
  inside the stimulus-critical window.

---

## Comments and help text

The comments are part of the code: MATLAB prints a file's help for `help` and `doc`, lists every
file of a package by its first help line (`help lum.led`), and the next reader trusts what a comment
says. `docs/code-style.md` has the full convention; this is what every change must keep.

- **Every file starts with help text** straight after its `function` or `classdef` line. The **H1**
  names the file as MATLAB calls it (`% lum.dev.PulsePal ...`, `% CheckRig ...`) and says what it
  does in one sentence, ending with a full stop, at most 100 characters, followed by a blank `%`
  line. Then, where they apply: what it is for and why (the decision Dn, the rig finding),
  `Usage:`, `Arguments:`, `Options:`, `Returns:` (units on every entry), the error identifiers, the
  *pure function* line, and last `% See also name, name` (no colon; MATLAB names only; every file
  outside `tests/` has one).
- **Public methods** carry their own help (`% configure() programs ...`); constructors and methods
  that implement a documented base-class interface need none. **Local functions** get one line
  saying what they return or do unless the name says it all; test functions are named for what they
  check.
- **Comments say why, not what**, in full sentences above the code they explain, with the glossary's
  words ([Naming](#naming)). A comment that describes a rule enforced elsewhere names where
  (`lum.triggerStates`).
- **Keep them true, in the same change.** Changing behaviour means reading and correcting the help
  of every function it touches and the comments around the edit; a wrong comment found anywhere is
  fixed like a wrong doc. Release history goes in `docs/naming-and-versions.md`, never in help text.
- **Typography**: 100 columns, comment paragraphs wrapped at about 92; ASCII only in comments and in
  printed text (a Windows console drops the rest from `help`: write ` - ` for a dash, `uL`,
  `mW/mm2`); no Markdown emphasis (help prints the asterisks); British spelling.
- **`%#ok<ID>`** only where the message is wrong for this code, with the reason when it is not plain.
  No `AGROW` in the trial loop.
- `helpTextTest` checks the mechanical parts (help present, H1 form, See also form and names,
  line length, ASCII, emphasis) and `lintTest` keeps zero Code Analyzer messages, the same
  `checkcode` the MATLAB language server (VS Code) and the Editor show. Whether a comment is true,
  needed and clear, no test checks: read it.

---

## Data

`docs/data-format.md` has every field; this is what code must respect.

- **Session file:** `D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.mat`,
  one variable `SessionData` (= `BpodSystem.Data`), written by `SaveBpodSessionData` (a full
  overwrite each call). Beside it: `_ANLG.dat` (Bpod's raw Flex analog stream, merged at teardown),
  `_plots.png` (D16), and after a desktop session `_memory.csv`.
- **Settings file:** `...\LuminoseFM\Session Settings\<name>.mat`, per subject, chosen in the launch
  manager. It holds the *last* session's settings: written on Start and again at teardown (D16).
  `lum.mergeSettings` converts old files (renames, reshapes, retirements, old defaults).
  `Session.SettingsVersion` (0.9.11) is the release that last wrote the file, always set from the
  defaults on merging; a file without it predates 0.9.11. Use it to tell an old default from an
  operator's choice in a future migration.
- **Store session-level things once** in `Data.Session` (settings, stimulus set, rig config, barcode,
  metadata); per-trial records hold only events, timestamps, outcome and indices into them
  (`PatternIndex` into `Session.StimulusSet`). Strip `States` from the stimulus set before storing
  it: segments are enough.
- **Per-trial series** are listed once, in `trialSeriesNames` in `LuminoseFM.m`;
  `docs/data-format.md` and `emulatorSessionTest` list them too: keep all three in step.
  `Choice`/`Correct`/`Outcome` are always the **first** side poke inside the first visit to
  `WaitForResponse` (0.9.6, `lum.scoreTrial`); a retried trial is `Incorrect` with `Rewarded` 1, so
  water totals use `Rewarded` and `CentreReward`, never `Outcome`.
- **`Data.TrialSettings{k}`** is `S.GUI` as trial *k* was prepared. The loop syncs S for trial *k*+1
  before trial *k* is recorded, so record from `nextGUI`/`trialGUI` in `LuminoseFM.m`, never from the
  current `S`. `Session.Settings` is S as trial 1 was prepared; `Session.LiquidCalibration` the
  valves' calibrations.
- **`Data.Session.StoppedReason`** is `''` for a behaviour session that ran to its end or was stopped
  from the console, and the error message for one that failed; sleep and ePhys sessions keep theirs
  in `Session.TestPulses.StoppedReason` / `Session.Ephys.StoppedReason`.
- **The hold and the light.** `Data.Session.LightMayOutlastHold` and `Data.Session.TriggerStates`
  (0.9.5, D21) say whether a completed hold could end before the light and where the next trial was
  prepared (from 0.9.8: true, and the ITI, in every session with light; from 0.9.11
  `WaitForCentrePoke` in every session, with `Data.Timing.devices` the seconds a trial's ITI spent
  on the next one's LED current or PulsePal program and upload, 0 on almost every trial). Every trial has the state
  `WaitForLightEnd` before the `ITI`. The hold without shaping is `TrialSettings{k}.HoldLength`
  (1 whole stimulus, 2 fixed) and `.FixedHold` from 0.9.8 (`Settings.Task.HoldLength`/`FixedHold`
  from 0.9.5 to 0.9.7).
- **Memory.** `Data.Timing.memoryGB` (0.9.6): MATLAB's memory (`memory`, Windows only, ~6 ms) at every
  save and as the session ends; a one-time warning past twice trial 1's and 8 GB.
- **LED currents are stored in mA everywhere**; irradiance is derived from them and the calibration
  stored in `Data.Session.DoricLED` (`lum.led.sessionRecord`).
- **Session types.** `Data.Session.Type` is `'Behaviour'`, `'Sleep'` or `'EphysCalibration'`. Sleep and
  ePhys sessions store `Data.SyncPulses` (each block is one Bpod trial) and, with light,
  `Data.LightSegments` (one per gate sent), with the compiled steps once in `Session.TestPulses` or
  `Session.Ephys`: never per-pulse carrier copies. Both store `Session.StoppedBlock`.
- **Flex analog stream.** Merged at teardown by `lum.dev.Flex.mergeAnalogData`, which re-anchors it
  with `lum.dev.Flex.alignAnalog`: the stream starts with the barcode's run, which Bpod counts as a
  trial and does not allow for (D7). Any new state machine run before trial 1 must go through the
  Flex shim so `RunsBeforeTrials` stays right.
- **Video (D14):** `...\LuminoseFM\Session Videos\<view>_<data file name>.avi` + `.csv` per camera,
  `<data file name>_events.csv` and `_session.json`, written by SpinCam; `Data.Session.Cameras` is
  `lum.dev.Cameras.sessionRecord`. `_events.csv` ends `SessionSaved`, `RecordingStop`. A frame
  log's `HardwareTimestamp_us` stepped forward by exactly 128 s now and then up to SpinCam engine
  1.2.0 (the Chameleon3's clock wrap counted twice; LUMS0014 2026-09-26 both views, 2026-09-28
  topview twice). Engine 1.3.0 takes them out as it records (`Session.Cameras.EngineVersion`;
  `Summary.Cameras(k).TimestampCorrections` counts them, kept by `lum.dev.RealCameras`, and the
  session log names any); `spincam.io.readFrameLog` repairs older logs (`docs/python-analysis.md`).
- **Summary plots and log (D22):** a behaviour session ends with `lum.report.write`: 12 images in
  `...\Session Plots\` (`NN_<Plot>_PP_<subject>_<YYYYMMDD_HHMMSS>.png`: `01_Outcomes` …
  `09_HoldAttempts` … `12_SessionTiming`, names and numbers unchanged since 0.9.8) and
  `...\Session Logs\<data file name>_log.md`, drawn from `BpodSystem.Data` alone
  (`lum.report.sessionTrials`); nothing in the data file refers to them.
  `lum.report.fromFile(dataFile)` does the same for a saved session and **only reads** it
  (rescoring pre-0.9.6 files in memory); `'OnlinePlots', true` also replaces `_plots.png` with the
  current `lum.OnlinePlots` replayed trial by trial. **Never write a `.mat` from `lum.report`.** Sleep and ePhys sessions write neither yet.
- **Unrecorded trials at the end.** A session ended with the End button (or on an error) can have
  trial pulses on the sync recordings after the last recorded trial: the trial it cut short
  (`nTrials` + 1, every version) and, from 0.9.11, the queued trial the halt let start
  (`nTrials` + 2; LUMS0014 2026-09-29: 374 pulses, 372 trials). Neither is in the data file. Analysis uses the first
  `nTrials` pulses and discards everything after `TrialEndTimestamp(nTrials)`
  (`docs/data-format.md`, *Video*; `docs/python-analysis.md` §4); an audit counts the extra pulses
  (0 to 2).
- **Emulated sessions** write a complete data file flagged `Data.Info.EmulatorMode = 1`.
- **Older files.** Trial pulses from 0.2 to 0.5.0 are ~100 µs glitches (D4): align those sessions by
  the barcode and `Data.TrialStartTimestamp`. Up to 0.9.5 a side poke after the response window was
  scored as a choice: rescore with `lum.scoreTrial`. Everything else is in `docs/data-format.md`,
  *Reading older files*.

---

## The emulator

The protocol must run end to end under `Bpod('EMU')` on a machine with no hardware, with working
GUI, plots and data saving. **The emulator is not this rig**: it emulates a state machine
**r0.7–1.0**, not the r2+. Design around this (`docs/emulator.md` has the operator's view):

- **5 global timers, 5 counters, 5 conditions**, against the rig's 16/8/16. Always read
  `rig.Limits.GlobalTimers` from `RigConfig`; never hard-code 16. The trial uses conditions 1–4 (left,
  right, centre port clear; hold window over) and always one timer, the hold window; a session with
  light also reserves the light clock and condition 5, the emulator's last (D21). The emulator
  therefore has three timers left for light, fewer with grace (the hold clock) or with a cue light or
  cue air that goes off part way through the stimulus (one each). The sync line and the house light
  take none, in any mode.
- **No Flex I/O**: no `Flex1` analog stream, no `Flex2DO`, so no airflow viewer, no sync pulses and
  no session barcode (recorded with `Sent = false`).
- **The Doric LED is DoricLED's `SimulatedTransport`** when the package is found (`Mode`
  'Simulated': the real `doric.LightSource`, logging every command), 'Manual' otherwise. The LED
  window's first drawing can hold up the emulator loop, so session tests that check emulated
  intervals set `S.Doric.ShowWindow = false`.
- **Cameras are SpinCam's `mock` backend** when SpinCam is found (synthetic frames through the real
  native engine, real files), `NullCameras` otherwise. Encoding loads the computer and stretches the
  emulator's loose timing: session tests that check emulated intervals set
  `S.Camera.Enabled = false`; `cameraTest` runs its own sessions with video.
- `BpodSystem.assertModule` **errors** in EMU, as does `BpodTrialManager`'s constructor (D3). Neither
  may be reached outside the device layer.
- **Global timers are emulated** (trigger, onset delay, duration, channel, end events), but
  **`LoopMode` is not**: a looping timer fires once and never repeats (`RunBpodEmulator.m`). Never put
  stimulus structure in a looping timer (D1).
- **`GlobalTimerCancel` is only partly emulated** (`RunStateMachine.m`): an active timer stops but
  emits no end event, so the console keeps its line drawn high; a timer still in its onset delay is
  not cancelled at all and starts later. A zero-onset timer triggered on entering a state emits no
  start event, so the console never draws it high: a light segment starting at stimulus onset looks
  missing, and later segments look as though light arrived late after the poke. The rig is
  unaffected; the emulated data lack those events.
- Conditions on a global timer (`'GlobalTimer<k>'`) **are** emulated; the hold window uses one.
  Conditions are evaluated every emulator loop, so a condition already true on entering a state
  fires at once (`WaitForCentreExit` relies on this, D6).
- A timer triggered in the *first* state is activated without emitting a start event.
- `RunStateMachine` zeroes `HardwareState.InputState` at the end of every trial, so a port held high
  from the console is forgotten between trials.
- **No millisecond time**: the emulator runs states from a MATLAB loop. A state never ends before its
  timer, but may end tens of ms after. Test emulated intervals from below only; exact timing is a
  property of the plan (pure tests) and of the rig.

**Playing the mouse.** In emulator mode the operator is the animal: the port buttons on the Bpod
console poke the ports through `ManualOverride`. A full trial is three clicks: centre to initiate,
centre again to withdraw once the hold is over, then a side port to choose. The response window does
not open until the centre port goes low, so the middle click is not optional; made before the hold
is over, it breaks the hold, and a further centre click restarts the stimulus. Expect to click a port
again each trial (the `InputState` note above). A sleep session needs no clicks. Do **not** drive
`ManualOverride` from a timer at high rate: it ends with `RefreshGUI` and `drawnow`, and calling it
tens of times a second from inside the emulator's own `drawnow` re-enters the console's callback
queue, which stops the session part way through as though the End button had been pressed. Tests use
`startMouse`/`startSessionMouse` instead (scripted `'V'` override bytes from a timer).

---

## Hardware map

Bpod state machine r2+, firmware 23, FSM `COM3`, App `COM4`. `docs/hardware.md` has the rig in full;
`RigConfig` is the single source of truth in code.

- **Behaviour ports:** 1 = Left, 2 = Centre, 3 = Right, 4 = air valve, 5 = unused (the house light's
  until it moved to PulsePal). Port *n* → `PWMn` (LED), `Valven` (solenoid), `PortnIn`/`PortnOut`
  (IR gate). Port 4 uses the valve line only. `Valve2` (centre) gives water only for the centre
  reward (D19), timed from valve 2's liquid calibration.
- **Optical channels:** `BNC1` → PulsePal `IN1` → `OUT1` → Doric LED ch1 is channel A; `BNC2` →
  `IN2` → `OUT2` → LED ch2 is channel B (`rig.Opto.Channels`, `rig.Opto.Labels`). The Doric driver
  (`LEDFLS_465_465`, USB, "LED Driver" on Doric port 4) runs both channels in **external TTL mode**
  at their LED currents (D17); PulsePal's 5 V is a TTL level, not the intensity. LED ch1 →
  commutator A, ch2 → commutator B.
- **On the animal:** OMP-ChR2(H134R)-YFP mice (genotype `OSN-ChR`); the bundle's fibre tips couple
  to a GRIN lens in contact with the olfactory bulb. LED calibrations (and so every irradiance in
  settings and data) are at the fibre tips, not the GRIN face. Light dose, heating, ChR2
  desensitization and the published intensities for OSN-ChR2 perception are in
  `docs/learning-time-literature.md`, *Light intensity and tissue heating*: read it before
  proposing an intensity or carrier change.
- **Fiber bundles** (`lum.fiberBundles`), cables named by colour, any two on A and B at the
  commutator, recorded in `S.Light.Cables` (A then B): 2-to-19 with blue (9 spots) and green (10),
  **blue on A and green on B** by default; 4-to-19 with black (4 spots), blue, orange, green (5 each),
  **orange on A and blue on B** by default. Each spot is a 100 µm fiber (`CoreDiameter`), so a
  cable's area is spots × π × (0.05 mm)². The cable is called orange everywhere; never red.
- **Flex I/O:** Flex1 = **analog input** (flow meter, 1 kHz); Flex2 = **digital output**, the sync
  TTL (barcode and trial pulses; configured since 0.5.0); Flex3–4 disabled. Channel types are
  0 = digital in, 1 = digital out, 2 = analog in, 3 = analog out, 4 = disabled. Read the live
  configuration (`BpodSystem.HW.FlexIO_ChannelTypes`), never the saved `FlexConfig.mat`.
  `docs/BpodSystemInfo.png` predates both; trust the live values where they disagree, and regenerate
  it (`BpodSystem.StateMachineInfo`) when the wiring or Flex configuration changes.
- **Modules:** `HiFi1` (Module#1, USB `COM8`) → amplifier → speaker. Modules 2–3 unregistered.
- **Cameras:** 2 × Chameleon3 CM3-U3-13Y3M on one USB 3.0 controller, recorded through SpinCam.
  **24226887 = topview, 24226657 = sideview** (`S.Camera.Cameras`; checked by the operator on
  2026-09-25; older default-named videos are swapped, and `lum.mergeSettings` converts that exact old
  pairing). Default 100 Hz full frame, `avi-mjpeg-mt`; both cameras together deliver at most 120 Hz
  full frame. Line0 (yellow/brown) is logged per frame, and **Flex2 is wired to both cameras'
  Line0** (through the splitter, 3.3 V TTL, since 2026-09-17), so `TTL_State` carries the barcode and
  trial pulses.
- **House light:** PulsePal OUT3 → BNC splitter → LED driver, and → Bpod BNC input 1
  (`BNC1High`/`BNC1Low`), `rig.HouseLight` (D15). BNC input 1 must be enabled in the console's port
  settings (`CheckRig`). If the wiring changes, change `RigConfig`, not the code. PulsePal OUT1/OUT2
  are channels A/B; OUT4 is free.

---

## Gotchas

Each has already cost time and is guarded in code; don't undo them.

### Bpod and firmware

- **Output actions are not sticky.** Bpod writes *every* output channel from the entered state's own
  row, so a line a state drove high goes low on the next state unless that state drives it high too.
  This made the trial sync pulse invisible for three releases (D4): a global timer set Flex2DO high
  on entering `TrialStart`, whose timer was 0, and `WaitForCentrePoke` wrote it low one 100 µs cycle
  later. Bpod's example protocols repeat `stimulusOutput` in consecutive states for this reason, and
  `SetGlobalTimer`'s help says "State output events can still manipulate the linked channel while the
  timer is running". Two exceptions: serial (module) channels (no action in a row sends nothing, so a
  sound plays on), and an **overridden** BNC/Wire/PWM/valve line (linked to a running global timer,
  or set by the output override command), which firmware 23 skips on state entry. Firmware 23 does
  **not** skip Flex lines, hence D4: never rely on a timer holding a Flex line. Every override is
  cleared when a state machine ends. Source: sanworks/Bpod_StateMachine_Firmware tag v23,
  `setStateOutputs`, `setGlobalTimerChannel`, `resetOutputs` and the `'O'` command.
- `AddState` rejects a repeated output channel in one state, so lists that switch something off and
  something else on go through `lum.mergeActions` first. Timer trigger and cancel masks from several
  components are built once by `buildTrialSM`, never merged: a second `GlobalTimerTrig` in one state
  would overwrite the first.
- `AddState` treats a one-character `GlobalTimerTrig`/`GlobalTimerCancel` value as a legacy timer
  *index*, evaluating `2^(value-1)` on the character: `'1'` becomes 2^48. Build masks with
  `lum.timerMaskAction`, which pads to two digits.
- `SetGlobalTimer` reads its optional arguments **by position**, not by name: pass `'Duration',
  'OnsetDelay', 'Channel', 'OnMessage'` in that order. On a PWM channel `OnMessage` is the brightness
  (0 would light nothing); Bpod's own `GlobalTimerExample_PWM.m` passes it under another name in that
  slot. Confirm on the rig.
- Transitions on a global timer ending live in `sma.GlobalTimerEndMatrix(state, timer)`, and on
  conditions in `sma.ConditionMatrix(state, condition)`, not in `InputMatrix`.
- **`BpodTrialManager`'s dead time warning** compares a trial's start with the previous one's end
  on the state machine's clock: past 0.5 ms (r2+), the next state machine reached the device after
  the trial ended, and nothing ran in between (no events, every output low). Its `getCurrentEvents`
  sets its trigger flag only on a *transition* into a trigger state, and learns the trigger states
  only when first called, so a transition processed before that call is missed and it waits for the
  trial's end (trial 1 with a short `TrialStart`: 153 ms late on the rig, 2026-09-28). So
  `lum.SessionRunner` does not call it: it polls `BpodSystem.Status.CurrentStateName` (written on
  every transition) and `Status.InStateMatrix` (0 at the trial's end), in `awaitPrepareWindow` and
  `awaitState`.
- **A condition on a BNC input reads the inverted level** on firmware 23 (2026-09-24): a condition
  `BNC1` = 1 is true with 0 V on BNC input 1, while `BNC1High`/`BNC1Low` events follow the voltage.
  Port lines are not inverted. Nothing here uses a BNC condition; test one on the rig before relying
  on it.
- **`RunProtocol('Stop')` removes the protocol folder from the MATLAB path.** Nothing needing `+lum`
  may run after it, object destructors included: release devices, close the runtime window and clear
  handles first, as `LuminoseFM` does.
- **The console's End button runs `RunProtocol('Stop')` *before* the protocol's teardown**, from its
  callback while the loop waits: it closes every figure in `BpodSystem.ProtocolFigures` and clears
  `BpodSystem.Path.Settings`. The teardown still resolves `+lum` only because the launch manager runs
  the protocol with MATLAB's `run`, which makes the repository the current folder until the protocol
  returns. Hence the plot figures' `CloseRequestFcn` only hides them (their `close()` deletes), and
  the settings file is captured before the loop, not read from `Path.Settings` at teardown (D16).
- **The End button starts the queued trial, and nothing stops it** (0.9.11; found 2026-09-29).
  `RunProtocol('Stop')` sends the state machine one halt command (`'X'`). With the next trial
  uploaded with `RunASAP` as each trial starts, that halt ends the running trial and the state
  machine starts the queued one; `getTrialData` returns at once because `BeingUsed` is 0, so nothing
  records it, and the teardown sends no second halt (it calls `RunProtocol('Stop')` only after a
  session that ran to its end or failed). The trial runs to its own end, cue light, ports, air and
  valves live. Not fixed: `docs/architecture.md` lists the fix (a second halt as the loop sees
  `BeingUsed` 0, checked on the rig) as an open question; the data docs say how to discard it.
- **A timer callback must not let the End button in.** The End button's callback runs inside any
  `drawnow` or `pause` that processes callbacks, including one inside a timer's callback. In 0.8.0 the
  camera window was a protocol figure whose timer drew with `drawnow limitrate`, so Stop closed the
  window and stopped its timer from inside that timer's callback, and MATLAB froze on the rig. So: a
  timer draws with `drawnow limitrate nocallbacks`; a window with a timer is not registered in
  `BpodSystem.ProtocolFigures` (the teardown closes it, through a `try`); the timer is stopped by its
  figure's `DeleteFcn`; and its callback is a local function that stops it with built-ins if the
  window cannot refresh (`lum.gui.CameraWindow`).
- **Never draw or export from a timer while an emulated session runs** (found 2026-09-27). A
  desktop check that captured the windows with `exportapp` from a 6 s timer stalled the emulator
  for good after trial 1: the capture ran inside the emulator loop's `drawnow`, and the loop never
  advanced again while the timer went on firing. The same session without that timer ran all 24
  trials. To watch a desktop session, screenshot it from outside MATLAB (PowerShell
  `CopyFromScreen`, as in *Tests and validation*), and read its figures after the teardown
  (`_plots.png`, the summary plots).
- **`RunStateMachine` leaves `Status.BeingUsed` at 1** when it runs outside a protocol, so the next rig
  utility refuses ("A protocol is running"). `TestHouseLight` and `TestSyncLine` restore `BeingUsed`
  and `InStateMatrix`; a new utility that runs a state machine must do the same.
- **The subject is not always in `Status.CurrentSubjectName`**: use `lum.launchSubject`.
- `RunStateMachine` starts the Flex analog stream on the session's **first run**, but
  `AddFlexIOAnalogData` stamps the stream from `TrialStartTimestamp(1)`, so a run before trial 1 (the
  barcode) shifts every analog timestamp by its length and every `TrialNumber` by one:
  `lum.dev.Flex.alignAnalog` corrects it. `AddFlexIOAnalogData(data, 'Volts', 0)` also *adds* the
  trial-aligned copy (it reads the first option as that flag): pass `'Volts'` alone.
- `BpodHiFi.load` reads `'LoopMode', 'LoopDuration'` by position too; `lum.dev.RealHiFi` passes them in
  that order. The cue tone loops for up to the hold window's upper limit.
- **Bpod's liquid calibration is a quadratic fit with no range check** (`GetValveTimes`): 0 µL gives
  its intercept (6–8 ms on this rig), past its peak (about 15 µL here) more µL gives less time, and
  further on Bpod errors on a negative time. Get every valve time through `lum.valveTimes`.
- A sleep session with test pulses must **never** cut a block inside an epoch or put two steps' light
  in one block: Bpod drops every line at the end of a state machine, so a gate split across runs
  becomes two gates with an upload between them, and PulsePal is only reprogrammed between runs.
  `lum.sleep.nextBlock` guards both; `lum.sleep.validateTestPulses` guarantees a safe cut exists.
- A `GlobalTimer<k>_Start`/`_End` pair in the trial record proves the *timer* ran, not that the
  *channel* moved. If a line is dead while its timer's events are there, look for a state that
  writes the same channel, not at the timer.
- Before blaming the stimulus path for "late" light or air, look at the session file: the
  `GlobalTimer<k>_Start/_End` events against `CentreHold`, the PulsePal device log (its first line says
  whether PulsePal was connected at all), and the flow meter aligned to the valve. The 0.2 report of
  "air at the reward port" was the analog shift above; the 0.4 report of light "at the side pokes"
  came from sessions where PulsePal was not connected in 13 of 16.

### PulsePal

- `ProgramPulsePalParam`'s header says trigger mode `1/2/3`; the firmware uses `0/1/2`, and the
  function sends the value unchanged. Gated is **2** (`lum.dev.PulsePal.GatedTriggerMode`).
- **A light session must never run with PulsePal unprogrammed.** Bpod gates BNC1/BNC2 anyway, and
  PulsePal answers with its last program (edge trigger, train delay, both LEDs on one input,
  continuous loop): the session file looks perfect while the LEDs fire at the wrong times.
  `lum.dev.openPulsePal` refuses to start instead of falling back to the null shim, and stops every
  output on connecting. Do not reintroduce a fallback.
- `PulsePal()` only prints "already open" and returns when a `PulsePalSystem` is left in the base
  workspace, even a dead one. Its scan lists only free ports, so a port a previous session did not
  release is never found, and it writes a handshake to every free COM port it tries.
  `PulsePalSystem` is a `PulsePalObject`, so `isfield` on it is always false. `ProgramPulsePalParam`
  returns `[]` on a timeout, and `[] ~= 1` is false: compare with `isequal`. `lum.dev.RealPulsePal`
  handles all of these.
- `SetPulsePalVersion`, the handshake behind `checkConnection`, pauses 0.1 s: call it between blocks or
  trials, never in a loop. A house light click can run inside that pause (the reason for the command
  guard, D15).
- PulsePal firmware v21 **does not change an output on its resting voltage alone**: parameter 17
  stores it and calls `dacWrite()` without setting that output's `DACFlags`. `SetPulsePalVoltage` (op
  79) does write, but alone it is lost at the next stop, abort or disconnect. So `holdVoltage` sends
  both, parameter 17 then op 79 (found on the rig 2026-09-21). `NullPulsePal` logs op 79 as
  `would write ch3 output = 5 V`.

### MATLAB, windows and tests

- **A new uifigure waits for its view before it is filled** (`lum.gui.Form.waitForView(fig)` straight
  after `uifigure(...)`, in every window). In a desktop MATLAB (R2025b), a window whose web view
  finished loading while components were still being added sometimes stayed as first drawn, and the
  next `drawnow` or `uiwait` never returned. `-batch` runs and invisible windows never show it, so the
  suite cannot: check a new window from a desktop MATLAB.
- `exportgraphics` refuses a classic figure holding more than one `uipanel`, and `print` refuses any
  figure with UI components (both plot figures have both). `exportapp` captures them, and the
  uifigure windows, headless under `-batch`.
- MATLAB resolves a package function from the **current folder** before the path, so a copy of a
  `+lum` file on the path does not override the repository's while MATLAB's current folder is the
  repository.
- **A test must start the emulator before anything reaches `lum.dev.open`.** Without a `BpodSystem`,
  `open` takes the rig path, and `lum.dev.openDoricLED` connects to the **real Doric driver** through
  the bridge (a test once did). Call `ensureEmulator()` first.
- A test that stops a session as the End button does (`RunProtocol('Stop')` from a timer) must run
  `LuminoseFM` from the repository folder, as the launch manager's `run()` does, or `+lum` is gone when
  Stop removes the path (`sleepSessionTest`'s `runSleepSession`); and must press it while a block runs
  (`Status.InStateMatrix`), or nothing is cut short.
- `functiontests` takes **every** local function whose name starts with `test` as a test, so a helper
  called `testPulses()` breaks the whole file. Name helpers otherwise.
- A `uitable`'s `Enable` wants `'on'`/`'off'` text, not the `OnOffSwitchState` that
  `lum.gui.Form.onOff` returns for other components.
- An invisible uifigure lays a newly selected tab out some time later: `getpixelposition` of its
  components reads the default 100 × 22 until then. Wait (drawnow and pause) before testing
  positions.
- The saved MATLAB path on this machine includes SpinCam, so a `-batch` session run with
  `S.Camera.Enabled` records simulated video; turn it off in tests that are not about video.
- Running `runLuminoseTests` twice in one MATLAB process breaks `emulatorSessionTest`: one `-batch`
  process per run.
- `animalSessionTest/testNoSessionWarnedOrFailed` fails now and then on a warning from DoricLED's
  own code as the simulated LED closes (`doric.LightSource/disconnect`: "The specified key is not
  present in this container"; 2026-09-26 once, 2026-09-28 in three of seven runs, a different session
  each time), and passes on a rerun. It is a race in DoricLED's teardown (its polling timer and a
  blocking request share the `Pending`/`Results` maps): DoricLED's, not ours; note it, do not change
  DoricLED from here. `windowsTest/testTheTrialTimelineStaysInsideItsAxes` failed once the same day
  (a label's `Extent` read before the invisible figure's layout) and passed on the rerun.
- The Chameleon3 quantizes `AcquisitionFrameRate`, and writing a read-back value lands one step higher
  (100.058 → 100.12). `CameraSetup` takes a frame rate back from SpinCam's viewer only when it differs
  by more than 0.2 Hz, rounded to 0.1 Hz.
- SpinVideo MJPEG (`avi-mjpeg`) encodes one frame at a time at ≈ 104 fps per full frame; at 100 Hz
  with the camera window open the writer queue grew 1–2 frames/s. A queue peak in
  `Session.Cameras.Summary.Cameras(k).QueuePeak` in the hundreds means the encoder fell behind.
- No debugger is installed on the rig PC. A thread's stack can be read with `dbghelp`'s `StackWalk64`
  from PowerShell (suspend the thread, walk, resume): that is how the Workspace browser was found
  behind the "Out of memory" of 0.9.6 (D16).

---

## Tests and validation

```bash
# whole suite, from WSL; no hardware touched; one -batch process per run
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch \
  "cd('C:\Users\harrislab\Documents\MATLAB\HarrisLabBpodProtocols\LuminoseFM'); addpath('tests'); runLuminoseTests"

# one file
... "runLuminoseTests('Filter', {'generateTest'})"
```

The suite **refuses to run against a real state machine** and starts `Bpod('EMU')` itself for the
tests that need one. `lintTest` keeps the repository at zero Code Analyzer messages: MATLAB has no
compile step, so that is the closest thing to one (the MATLAB language server in VS Code runs the
same `checkcode`, so zero here is zero there). `helpTextTest` holds help text and comments to the
convention above. `docs/repository.md` lists what each file covers.

- **Add a test with any behaviour change.** The pure functions (`+lum/*.m`, `+lum/+pattern/`,
  `+lum/+sync/`) are the cheap place to do it.
- `windowsTest` builds windows invisibly (`'Visible', 'off'`, and `'Wait', false` for the modal ones)
  and skips the uifigure tests where MATLAB cannot make one.
- Test doubles: `StubHiFi`, `StubPulsePal` (a PulsePal that can stop answering) and
  `StubCameraManager` (SpinCam's manager, no cameras); DoricLED's own `SimulatedTransport` is the
  LED's. `startMouse` plays scripted pokes into an emulated state machine.
- **A desktop check** (a new window, or how the plots look on screen) runs a real desktop MATLAB,
  never the rig: `matlab.exe -nosplash -r "..."` launched from WSL with `setsid nohup ... &` (a plain
  `&` dies with the shell), running `Bpod('EMU')` through `ensureEmulator`, the session set up as
  `animalSessionTest`'s `runSession` does (headless, data under `%TEMP%`, never the data folder),
  played by `startSessionMouse`, and ending with `exit`. Watch it with screenshots taken from WSL
  (`powershell.exe` `System.Drawing` `CopyFromScreen`), never with a MATLAB timer (see *Gotchas*).
  Check that no MATLAB is running first (`tasklist`): one may be running an animal. Screenshots
  come out blank white when the operator's remote-desktop session is disconnected and locked
  (`qwinsta` shows `Disc`, `LogonUI` runs): the windows still draw, so read `_plots.png` instead.
  The last checks (2026-09-27, 0.9.9): an emulated 24-trial session watched on screen, and a
  24-trial session on the rig (`docs/rig-checks.md`, *Done*); the online figure, tabbed runtime
  window, `_plots.png`, summary plots and log all drawn as in the headless renders. On 2026-09-28
  (0.9.11) a headless 30-trial rig session with an LED-window change (`docs/rig-checks.md`).
- For anything that depends on pokes: `stateMachineTest` plays whole trials with `startMouse`
  (scripted `'V'` override bytes from a timer, a few hundred ms apart, never `ManualOverride`);
  `animalSessionTest` plays four whole sessions with `startSessionMouse` (one behaviour per trial, the
  paying side read from the running state matrix, runtime values typed into the compact window),
  reaching every outcome path and rebuilding each trial from the saved file. Add a behaviour to
  `startSessionMouse`'s lists for any new path.
- Whole sessions: `emulatorSessionTest` (behaviour), `habituationSessionTest` (one trial played, the
  centre reward or its fallback where valve 2 has no calibration), `sleepSessionTest` (with and
  without test pulses), `ephysSessionTest`, all with video and the LED window off. `ledTest` and
  `ephysTest` are pure; `doricTest` runs the LED on DoricLED's simulated driver; the Doric and ePhys
  session tests are skipped without DoricLED, and `cameraTest`'s sessions without SpinCam.

### Validation procedure

Before a version is used for experiments, validate it the way `docs/validation-2026-09-24.md` did,
and write the report beside it:

1. **Inventory.** Walk `lum.defaultSettings` (every field and default), the state graph
   (`buildTrialSM`, `lum.sleep.blockStateMachine`), `RigConfig` and every file read or written. Every
   item gets a test or a reason it cannot be tested remotely.
2. **Suite.** `runLuminoseTests` in one `-batch` MATLAB: zero failures, zero lint.
3. **Played sessions.** `animalSessionTest` covers every outcome path. Replay the policies in the
   session's order (trial *k*+1 prepared before trial *k* is recorded); `holdShapingTest`'s
   `replaySession` is the pattern (a pure test of one step at a time missed the odd/even shaping of
   0.9.3).
4. **Boundaries.** Build a trial at each runtime parameter's `GUIMeta.Limits` (and each menu entry),
   with and without shaping, and check the state timers equal the parameters.
5. **Statistics.** Simulate `lum.nextTrialSpec` over a whole session, in the loop's order, with biased
   and unbiased animals: group balance, P(left) per group, bias correction's effect per 100 trials,
   the run limit.
6. **Calibrations, read only.** Every `calibration/*.mat` rises with current, `IrradiancemWmm2` =
   `PowermW` / `Area`, coverage passes; the liquid calibration's fit rises over the volumes in use.
   Never change either; flag a suspect point.
7. **Rig** (with the operator's permission, no animal): *How to run a check* in
   `docs/rig-checks.md`, in separate `-batch` processes: `CheckRig`; port and valve lines from a state
   machine (valves once each, at their calibrated times); `TestHouseLight`, `TestDoricLED`,
   `TestHiFiSound`; then short behaviour, sleep and ePhys sessions with video and virtual pokes,
   checked from the saved files: light timers against the stimulus set, reward states against
   `GetValveTimes(TrialSettings{k}.RewardAmount)`, `TrialStart` against `SyncPulseWidth`, and each
   camera's `TTL_State` decoded (`lum.sync.decodeBarcode`) and matched pulse by pulse. Record it all
   in `docs/rig-checks.md`.

---

## Docs

Keep documentation current in the same change that alters behaviour; [Start here](#start-here)
says which document holds what. If you change a public helper's signature, the state-machine flow,
the data schema, the GUI parameter set or the hardware map, update the affected doc in the same
commit. Every release gets a section in `docs/naming-and-versions.md`, and `lum.version` is bumped.

**Writing.** State facts plainly, for an operator and a developer who want to use or change the
code. No emphasis for its own sake, no reassurance, no lecturing (for example, not "This is not
superstition, and it is not optional"). Say what happens, what to do, and why when the why helps.

**Rendering.** Docs are read on GitHub and in editors. Put display maths on `$$` lines of their own
with blank lines around; in maths write `\lbrace \rbrace`, `^{\ast}`, `\thinspace` rather than
`\{ \}`, `^{*}`, `\,` (Markdown eats the first forms), and avoid `}_` (it can start emphasis). Escape
a `|` inside a table cell, code spans included (`<A\|B>`). Keep `<placeholders>` inside code spans,
or they vanish as HTML.

---

## Git

- Branch `main`, remote `SainsburyWellcomeCentre/LuminoseFM`.
- Commit only when asked. Don't commit session data, `.asv` files, `Bpod Local` state, or
  `calibration/` (rig-local LED calibrations; git-ignored).
