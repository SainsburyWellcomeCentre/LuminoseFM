# LuminoseFM — Repository layout and tests

Where the code lives and what the test suite covers. The design behind it is in
[`architecture.md`](architecture.md); how to use the protocol is in [`../README.md`](../README.md);
the conventions for changing it are in [`../CLAUDE.md`](../CLAUDE.md), and how its help text and
comments are written and checked in [`code-style.md`](code-style.md).

---

## Layout

The protocol file sits in the root of the project, unnested: Bpod's launch manager requires
`<ProtocolFolder>/<Name>/<Name>.m`, so its name must match the folder's. Everything with logic in it
is in the `+lum` package, where it can be tested without hardware; rig utilities are in `hardware/`.

```
LuminoseFM/
├── LuminoseFM.m                  the protocol: session type, setup, barcode, trial loop, teardown
├── README.md                     the operator's guide
├── CLAUDE.md, AGENTS.md          instructions for coding agents (AGENTS.md is a symlink)
├── +lum/
│   ├── defaultSettings.m         the two-tier settings struct; every runtime parameter declared once
│   ├── mergeSettings.m           old settings files converted (renames, reshapes, retirements)
│   ├── validateSettings.m        everything that must hold before a session starts
│   ├── stageDefaults.m           the session shape a training stage assumes
│   ├── experimentChoices.m       the Experiment tab's lists (session types, genotypes, task variants)
│   ├── fiberBundles.m            bundle cables and spot counts
│   ├── launchSubject.m           the subject the session was launched for
│   ├── timerBudget.m             global timers left for light
│   ├── buildTrialSM.m            the state graph
│   ├── mergeActions.m            output actions merged, so no channel repeats in a state
│   ├── timerMaskAction.m         global timer masks padded so Bpod reads them as masks
│   ├── cueTiming.m               what each cue component does once the stimulus starts
│   ├── triggerStates.m           where the next trial may be prepared
│   ├── nextTrialSpec.m           trial policy: order, contingency, bias, run limit, stage, hold, centre reward
│   ├── newHistory.m, updateHistory.m   the running history the policy reads (O(1) per trial)
│   ├── centreRewardAgain.m       the centre reward asked for again mid-session: its run and its box
│   ├── HoldShaping.m             automatic shaping of the centre hold, the hold without it, break modes
│   ├── scoreTrial.m              outcome classification from states and events
│   ├── holdMeasures.m            hold completed, held on the first attempt, hold attempts
│   ├── Outcome.m                 outcome codes (part of the data format)
│   ├── punishmentFor.m           which mistakes are punished, and how
│   ├── valveTimes.m              valve open times for a volume, refusing one the calibration cannot give
│   ├── trainingStageNote.m       one line on what the training stage does to rewards
│   ├── trialStatus.m             the runtime window's lines: how the last trial ended, what runs now
│   ├── SyncMode.m                how trials drive the sync TTL (codes are part of the data format)
│   ├── SessionRunner.m           TrialManager on the rig, blocking in the emulator
│   ├── StartupTimes.m            how long a session took to start, step by step (Session.Startup)
│   ├── OnlinePlots.m             the live figure
│   ├── loadSounds.m              the session's sounds, loaded once
│   ├── testSounds.m              a sound of the session as a test, for the setup dialog's Play buttons
│   ├── toneFrequencies.m         stimulus tone frequencies, shared by the two above
│   ├── watchMemoryAfterSession.m MATLAB's memory for 4 min after a desktop session (_memory.csv)
│   ├── version.m, repoRoot.m     the version recorded in every file; the repository's folder
│   ├── +pattern/                 stimulus families and generator, stimulus set, contingency, single-cue ceilings
│   ├── +stim/                    cue and stimulus components
│   ├── +sync/                    session barcode; the sync line fitted to the cameras' frame rate
│   ├── +report/                  a behaviour session's summary plots and log, at its end or from its file
│   ├── +sleep/                   sleep and ePhys calibration sessions: run, sync and test pulses, blocks, checks, plots
│   ├── +ephys/                   ePhys calibration: the steps of light, their checks and description
│   ├── +led/                     LED light paths, calibrations, mA and mW/mm², the LED checks and session record
│   ├── +dev/                     device shims, real and null; cameras through SpinCam; the house light; the Doric LED
│   └── +gui/                     session type, setup dialogs, Doric LED tab, calibration and LED windows,
│                                 camera tab and window, help line, designers, runtime window, theme,
│                                 plot panel style and keys (styleAxes, panelLegend), plots image
├── hardware/
│   ├── RigConfig.m               the channel map and the connected machine's live limits
│   ├── CheckRig.m                preflight report
│   ├── TestHiFiSound.m           play a test sound through the HiFi module
│   ├── TestSyncLine.m            drive the sync TTL, from states and from a global timer
│   ├── TestHouseLight.m          switch the house light through PulsePal, check each switch reaches BNC1
│   └── TestDoricLED.m            light A, then B, then both, through Bpod, PulsePal and the Doric driver
├── calibration/                  this rig's LED calibrations (not tracked by git; made by Calibrate LED power…)
├── tests/
│   ├── runLuminoseTests.m        the whole suite; needs no hardware
│   ├── *Test.m                   one file per area (below)
│   ├── ensureEmulator.m          starts Bpod('EMU') and refuses a real state machine
│   ├── makeTestContext.m         a trial builder's context with null devices
│   ├── withCue.m                 switches on exactly the named cue components
│   ├── startMouse.m              plays scripted pokes into an emulated state machine
│   ├── startSessionMouse.m       plays an animal through a whole emulated session, one behaviour per trial
│   ├── startHouseLightClicker.m  clicks the live figure's house light box part way through a session
│   └── Stub*.m                   test doubles: HiFi, PulsePal (one that can stop answering), SpinCam's CameraManager
└── docs/
    ├── architecture.md           design decisions D1–D22 and the map from design to code
    ├── hardware.md               the rig: box, ports, light path, Flex I/O, cameras, environment
    ├── data-format.md            what a session file contains, and reading older ones
    ├── python-analysis.md        reading the data in Python; the HDF5 layout for the lab's package
    ├── stimulus_family.md        the stimulus families from first principles, and analysing them
    ├── sync-and-barcode.md       the sync TTL and the session barcode
    ├── naming-and-versions.md    glossary and what changed between versions
    ├── emulator.md               running with no hardware attached
    ├── rig-checks.md             how to run a rig check, what has been checked, what waits for the operator
    ├── validation-2026-09-24.md  the pre-deployment validation of 0.9.3 → 0.9.4
    ├── repository.md             this file
    ├── code-style.md             help at the MATLAB prompt; help text, comments and lint
    ├── BpodSystemInfo.png        channel, event and output list of the rig
    ├── logo/                     the Luminose logo
    ├── behaviour_box_design/     box, base plate and home-cage cover drawings
    └── fiber_bundle_design/      2-to-19 and 4-to-19 fiber bundle drawings
```

---

## Tests

The suite runs without any hardware attached, and **refuses to run against a real state
machine** — it starts `Bpod('EMU')` itself for the tests that need one. It is safe to run on the
rig computer whenever a session is not in progress.

```matlab
addpath('tests');
runLuminoseTests                              % everything
runLuminoseTests('Filter', {'generateTest'})  % one file
```

Or headless, from WSL (one `-batch` process per run: running the suite twice in one MATLAB breaks
`emulatorSessionTest`):

```bash
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch \
  "cd('C:\Users\harrislab\Documents\MATLAB\HarrisLabBpodProtocols\LuminoseFM'); addpath('tests'); runLuminoseTests"
```

`animalSessionTest` alone takes about two minutes. Tests that need the DoricLED package or SpinCam are
skipped where the package is not found.

### What each file covers

**Pure functions** (no Bpod):

| File | Covers |
|------|--------|
| `generateTest` | the stimulus generator: each family's defining property (which side each group pays, what varies, what is held equal), every family's defaults compiling within the rig's and the emulator's timer budgets (15, 14, 13 and 4, 3, 2) in the default and a coarse window, balanced groups, reproducibility from the seed, the global random stream left alone |
| `stimulusSetTest` | the stimulus set, the contingency (the family's, typed P(left) kept only for its groups, the reversal) and the single-cue ceilings |
| `patternTest` | light patterns as the state machine sees them: joint states to segments, their normal form |
| `cueTimingTest` | what each cue component does once the stimulus starts |
| `trialSpecTest` | the trial policy: the order, contingency, bias correction (and its precedence over the run limit), the run limit counting the trial still running, training stage, centre reward and its run when asked for again; a whole session replayed in the loop's order |
| `holdShapingTest` | automatic shaping: growth, grace, step back, the defaults and a settings file keeping its own, a start above the target; the session's order replayed (one step per completed hold, a single step back); the next session's hold 10% below the last; the hold without shaping as a runtime choice, and every session with light keeping the light clock with the ITI as its only trigger state |
| `scoreTrialTest` | outcome scoring, including a side poke after the response window not being a choice |
| `holdMeasuresTest` | `lum.holdMeasures` and `lum.scoreTrial` on the hold: restart mode with 0, 1 and 2 early withdrawals before a completed hold, every hold broken, *End trial*, a forgiven break, no initiation, the centre reward, a withdrawal during the latency |
| `punishmentTest` | every combination of what is punished and how |
| `trainingStageTest` | the training stage's note staying true to what `nextTrialSpec` does |
| `valveTimesTest` | `lum.valveTimes`: 0 µL opens no valve, a volume past the fit's peak is refused, one outside the measurements is noted |
| `settingsTest` | settings conversion and validation: old families, renamed and retired fields, the house light out of the runtime tier, a 0.9.2 file's 700 mA limit becoming 1000 mA, an old file's crops kept for its last session type, `Task.HoldLength`/`FixedHold` moved into the runtime tier, a missing ITI getting 0 s and a pre-0.9.8 file's 1 s becoming 0 s; refusals (an unknown hold length, a fixed hold of 0 s or one the hold window cannot hold); an Experiment session with a fixed hold shorter than the light; where the subject comes from (`lum.launchSubject`) |
| `barcodeTest` | the barcode's encoding and decoding, its kinds (behaviour, sleep, ePhys calibration, typed and fitted), fitted barcodes sampled frame by frame at 25–150 Hz at every phase and with the camera 5 % slow; a launch cancelled in a dialog leaving no empty `_ANLG.dat` |
| `pulsePalTest` | the carrier translation, PulsePal's health check against a stub that can stop answering, holding an output at a voltage and sending it only once a command under way has finished |
| `ledTest` | light paths and fiber areas, calibrations (units, refusals, saving and replacing, one per cable and channel, a 0.9.0 per-cable file read only on its channel, a damaged file, too few readings, a 700 mA calibration under a 1000 mA limit), mA ↔ mW/mm², the session intensity, the LED checks, the session record |
| `ephysTest` | the ePhys calibration schedule (levels even in mA or in irradiance, the default curve's top, pairs, intervals, order, refusals), its validation, the EphysCalibration barcode fitted to the cameras |
| `reportTest` | the runtime window's trial lines in habituation and training, and the attempt a hold was completed at; where the summary plots and log go and how they are named; twelve plots and a log from a made-up session; the outcome raster paging past 400 trials; `lum.report.fromFile` reading a saved file without changing a byte; the replayed online figure, the summary plots' numbers and the log agreeing on which holds were completed and at which attempt |
| `memoryWatchTest` | the memory sampler lists the running timers and writes a row a second (Windows only) |
| `lintTest` | zero MATLAB Code Analyzer messages over the whole repository (what the MATLAB language server and the Editor show) |
| `helpTextTest` | every file's help text and comments (`code-style.md`): help present; an H1 that names the file in one sentence on one line; a `See also` line (no colon) outside `tests/`, whose names of this repository exist; comment lines within 100 characters, ASCII, with no Markdown emphasis |

**Under `Bpod('EMU')`**:

| File | Covers |
|------|--------|
| `stateMachineTest` | the state graph: restarts and the hold window; every punishment of an incorrect choice (none and a retry, timeout, noise to its end, both); the centre reward after a completed hold; a habituation trial built from the defaults; the house light costing no timer and no line; no reward delay meaning a beam flicker cannot forfeit the reward, and the valve reachable only through a poke; the light after the hold (every ending path through `WaitForLightEnd`, the light clock, its condition and what cancels it, only the light left running as the hold ends); the 0 s ITI and `NoInitiation` holding task-event sync low for two frames with video; trials played as the animal (`startMouse`) |
| `sleepTest` | sleep sessions' parts: the sync pulse schedule, the test-pulse plan, the block cutter, validation; a block run on channels A and B, and a house light switch landing in its events as `BNC1Low` |
| `houseLightTest` | the house light: its starting level, switches recorded and shown, a click while PulsePal is busy landing when it is free, a refused switch putting the box back, off when closed, the level a trial started at and the edges on Bpod's clock; the disabled light without PulsePal; which light `lum.dev.openHouseLight` chooses; `TestHouseLight` end to end |
| `doricTest` | the Doric LED on DoricLED's simulated driver: modes, both channels set up in external TTL mode, a request sent only at the next prepare window, an ePhys step's currents, calibration light, closing, the LED opened alone at launch; `TestDoricLED` end to end |
| `cameraTest` | camera settings, format notes and descriptions (one sentence each), which formats need SpinVideo, where videos go, settings to camera state, what a recording records, finishing a recording, the camera window and its timer, crops per session type and typed crops, against `StubCameraManager`; then a behaviour and a sleep session with SpinCam's simulated cameras (the video stops after the final save, the file keeps the recording summary) |
| `windowsTest` | every window, built invisibly: the runtime window (header wrapping); both plot figures (a close request hides them, they save as an image, the house light box, every panel in the theme's type and a colour per meaning, every title, label and key inside the window at the session size with no title or key running into another, habituation scoring every trial, reaction time on a log axis, the psychometric panel along each family's evidence, the contingency's boundary); the session type chooser; the setup dialogs (shaping by stage, Play buttons, the help line, the Cameras tab and its format description, a crop drawn on the preview, each stimulus family and its defaults following the timer budget, the copies of the hold and the stimulus window following each other); both designers; the Doric LED tab, the calibration window, the LED window and the ePhys dialog |

**Whole sessions under `Bpod('EMU')`**, launched headless through `LuminoseFM`:

| File | Covers |
|------|--------|
| `emulatorSessionTest` | a behaviour session: every per-trial series, the LED current per trial, the house light switched part way through (`startHouseLightClicker`), the plots image, the startup times, `Timing.memoryGB`, the summary plots and log written after the data |
| `habituationSessionTest` | a two-trial habituation session, its first trial played as the animal: the side reward, the centre reward (or none, with a warning, where valve 2 has no calibration), `CentreHoldTime`, shaping starting at `HoldStart` |
| `animalSessionTest` | four sessions played as an animal (`startSessionMouse`), one behaviour per trial, reaching every outcome path: training defaults (correct, retried, withdrawn and restarted, no poke, every hold broken, no side poke, never leaving the centre port, rapid pokes while drinking); *End trial* with timeout and noise, a latency and a reward delay; habituation with grow hold and shrink grace, the centre reward and a step back; an Experiment session with a fixed 0.2 s hold under 1 s of light. Each saved trial is rescored from its raw events and checked against its settings (the ITI and reward typed into the runtime window mid-session), holds, light timers, the centre valve's time and the shaping sequence |
| `sleepSessionTest` | two sleep sessions, with and without test pulses; one stopped by `RunProtocol('Stop')` mid-block keeps that block's plan (`Session.StoppedBlock`) |
| `ephysSessionTest` | an ePhys calibration session: each gate's current against its step; a stopped session's `StoppedBlock` |

The session tests run without video and without the LED window, whose load stretches the emulator's
timings; `cameraTest` runs its own sessions with video.

Add a test with any behaviour change; the pure functions are the cheap place to do it.
