# LuminoseFM — Repository layout and tests

Where the code lives and what the test suite covers. The design behind it is in
[`architecture.md`](architecture.md); how to use the protocol is in [`../README.md`](../README.md).

---

## Layout

The protocol file sits in the root of the project, unnested: Bpod's launch manager requires
`<ProtocolFolder>/<Name>/<Name>.m`, so its name must match the folder's. Everything else is a
helper in a subfolder.

```
LuminoseFM/
├── LuminoseFM.m                  the protocol: session setup, trial loop, teardown
├── README.md                     the user guide
├── CLAUDE.md / AGENTS.md         instructions for coding agents
├── +lum/                         everything with logic in it, testable without hardware
│   ├── buildTrialSM.m            the state graph
│   ├── cueTiming.m               what each cue component does once the stimulus starts
│   ├── triggerStates.m           where the next trial may be prepared
│   ├── nextTrialSpec.m           trial policy: order, contingency, bias, run limit, stage
│   ├── centreRewardAgain.m       the centre reward asked for again mid-session: its run and its box
│   ├── HoldShaping.m             automatic shaping of the centre hold, and what a broken hold does
│   ├── scoreTrial.m              outcome classification
│   ├── punishmentFor.m           which mistakes are punished, and how
│   ├── valveTimes.m              valve open times for a volume, refusing one the liquid calibration cannot give
│   ├── launchSubject.m           the subject the session was launched for
│   ├── validateSettings.m        everything that must hold before a session starts
│   ├── stageDefaults.m           the session shape a training stage assumes
│   ├── timerBudget.m             global timers left for light
│   ├── SyncMode.m                how trials drive the sync TTL
│   ├── SessionRunner.m           TrialManager on the rig, blocking in the emulator
│   ├── StartupTimes.m            how long a session took to start, step by step (Session.Startup)
│   ├── OnlinePlots.m             the live figure
│   ├── loadSounds.m              the session's sounds, loaded once
│   ├── testSounds.m              a sound of the session as a test, for the setup dialog's Play buttons
│   ├── toneFrequencies.m         stimulus tone frequencies, shared by the two above
│   ├── defaultSettings.m         the two-tier settings struct
│   ├── mergeSettings.m           old settings files converted (renames, reshapes, retirements)
│   ├── +pattern/                 stimulus families and generator, stimulus set, contingency, single-cue ceilings, light patterns
│   ├── +stim/                    cue and stimulus components
│   ├── +sync/                    session barcode; the sync line fitted to the cameras' frame rate
│   ├── +sleep/                   sleep and ePhys calibration sessions: run, sync and test pulses, blocks, validation, plots
│   ├── +ephys/                   ePhys calibration: the steps of light, their checks and description
│   ├── +led/                     LED light paths, calibrations, mA and mW/mm2, the LED checks and session record
│   ├── +dev/                     device shims, real and null; cameras through SpinCam; the house light on PulsePal; the Doric LED
│   └── +gui/                     session type, setup dialogs, Doric LED tab, calibration and LED windows, camera tab and window, help line, designers, runtime window, theme, plots image
├── hardware/
│   ├── RigConfig.m               the channel map — the single source of truth
│   ├── CheckRig.m                preflight report
│   ├── TestHiFiSound.m           play a test sound through the HiFi module
│   ├── TestSyncLine.m            drive the sync TTL, from states and from a global timer
│   ├── TestHouseLight.m          switch the house light through PulsePal, check each switch reaches BNC1
│   └── TestDoricLED.m            light A, then B, then both, through Bpod, PulsePal and the Doric driver
├── calibration/                  LED calibrations of this rig (not tracked by git; made by Calibrate...)
├── tests/
│   ├── runLuminoseTests.m        the whole suite; needs no hardware
│   ├── startMouse.m              plays scripted pokes into an emulated state machine
│   ├── startSessionMouse.m       plays an animal through a whole emulated session, one behaviour per trial
│   └── Stub*.m                   test doubles: HiFi, PulsePal, SpinCam's CameraManager
└── docs/
    ├── architecture.md           design decisions and the map from design to code
    ├── hardware.md               the rig: box, ports, light path, Flex I/O, environment
    ├── data-format.md            what a session file contains
    ├── stimulus_family.md        the stimulus families from first principles, and analysing them
    ├── sync-and-barcode.md       the sync TTL and the session barcode
    ├── naming-and-versions.md    glossary and what changed between versions
    ├── emulator.md               running with no hardware attached
    ├── rig-checks.md             what has been checked on the rig; checks waiting for the operator
    ├── repository.md             this file
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

Or headless, from a terminal:

```bash
matlab -batch "cd('/path/to/LuminoseFM'); addpath('tests'); runLuminoseTests"
```

What it covers:

- **Pure functions** — the stimulus generator and stimulus set: every family's defaults compiling
  within the rig's and the emulator's timers, what each family varies and holds equal, the family's
  contingency and typed P(left) kept only for its groups, the single-cue ceilings (`generateTest`,
  `stimulusSetTest`); old families converted on load (`settingsTest`); the cue's timing once the
  stimulus starts, trial generation, the centre reward and its run when asked for again,
  bias correction, hold shaping and break modes, outcome scoring, the
  barcode and its kinds, the analog realignment, settings conversion and validation, the PulsePal
  carrier and its health check (against a stub PulsePal that can stop answering), holding an output
  at a voltage and sending it only once a command under way has finished, the sleep pulse
  schedule, the test-pulse plan and how a sleep session is cut into blocks.
- `houseLightTest` — the house light on PulsePal output 3: its starting level, switches recorded and
  shown, a click while PulsePal is busy landing when it is free, a refused switch putting the box
  back, off when closed, and reading the level a trial started at and the edges on Bpod's clock from
  the loopback input's events; the disabled light of a session without light and without PulsePal,
  and which light `lum.dev.openHouseLight` chooses; and `TestHouseLight` run end to end under
  `Bpod('EMU')`.
- `stateMachineTest` — the state graph itself, restarts and the hold window included, and that the
  house light costs a trial no timer and no line (and, in `sleepTest`, a switch part way through an
  emulated block landing in its events as `BNC1Low`); every punishment of an incorrect choice (none
  and a retry, timeout, noise to its end, both), the centre reward after a completed hold, and two
  trials played as the animal under `Bpod('EMU')` (`startMouse`): a wrong choice then the right one,
  rewarded, with the centre reward; and a punished wrong choice ending the trial.
- `windowsTest` — the runtime window, both plot figures (a close request hides them, they save as an
  image, both figures' house light switch), the session type chooser, both setup
  dialogs (automatic shaping by stage, Play buttons, the help line, the Cameras tab, the format's
  description on the help line, and its preview of simulated cameras, choosing each stimulus family
  on the Stimulus tab) and both designers (every family's defaults ready to run, typed P(left) kept
  and dropped as the groups change), built invisibly; the psychometric panel along each family's
  evidence and the contingency's boundary on the evidence panel.
- `cameraTest` — camera settings, the format note for single-threaded encoders, the note for a
  one sentence per
  format and which need SpinVideo, where videos go,
  how settings become camera state and what a recording records, against `StubCameraManager`;
  finishing a recording (the save marked before the stop); the camera window, and its timer going
  with its figure, whoever deletes it; and a whole behaviour
  and a sleep session under `Bpod('EMU')` recording SpinCam's simulated cameras, checking that the
  video stops after the final save and the file still carries the recording summary (skipped without SpinCam:
  on the path, in `SPINCAM_FOLDER`, or beside the MATLAB folder). The other session tests run
  without video, whose load would stretch the emulator's timings they check.
- `emulatorSessionTest`, `sleepSessionTest` — a whole behaviour session (with the LED current per
  trial) and two sleep sessions
  (with and without test pulses) under `Bpod('EMU')`, checking the files they produce — the house
  light clicked off from the live figure part way through (`startHouseLightClicker`): the edge in the
  trial or block, the level per trial or block and the session's record — and the plots image beside
  the data, and the startup times, step by step and device by device (`Session.Startup`).
- `habituationSessionTest` — a two-trial habituation session under `Bpod('EMU')`, its first trial
  played as the animal (`startMouse`): the side reward, the centre reward when valve 2 is calibrated
  (and none, with a warning, when it is not, as on the development machine), `CentreHoldTime`, and
  automatic shaping starting the hold at `HoldStart`.
- `animalSessionTest` — three whole behaviour sessions under `Bpod('EMU')` played by an animal
  (`startSessionMouse`), one behaviour per trial, reaching every outcome path: correct, retried,
  withdrawn and restarted, no poke, every hold broken, no side poke, never leaving the centre port,
  rapid pokes while drinking; with *End trial*, timeout and noise, a latency and a reward delay:
  leaving before the reward, in the latency and in the hold, a punished wrong choice; and habituation
  with grow hold and shrink grace together, the centre reward and a step back. Each saved trial is
  re-scored from its raw events and checked against its settings: `TrialSettings{k}` against the ITI
  the trial ran (the ITI and reward are typed into the runtime window mid-session), holds, the light
  pattern's timers, the centre valve's time, and the shaping sequence the session's order must give.
  About two minutes.
- `valveTimesTest` — `lum.valveTimes`: 0 µL opens no valve, a volume past the calibration fit's peak
  is refused, one within it gives Bpod's times, one outside the measurements is noted.
- `holdShapingTest` also replays the session's order (trial *k*+1 prepared before trial *k* is
  recorded): one growth step and one grace step per completed hold, and a single step back.
- `settingsTest` also covers where the subject comes from (`lum.launchSubject`), the house light's
  move out of the runtime tier, and a 0.9.2 file's 700 mA LED limit becoming 1000 mA.
- `barcodeTest` also samples fitted barcodes frame by frame at 25–150 Hz, at every phase and with
  the camera 5 % slow, and decodes every one (`lum.sync.fitToCameras`).
- `ledTest` — light paths and fiber areas (cables by colour, swapped between channels), calibrations
  (units, refusals, saving and replacing, one per cable and channel, a cable keeping two calibrations,
  a 0.9.0 per-cable file read only on its channel, a damaged file, readings too few or too low to be
  saved or used, a calibration to 700 mA used under a 1000 mA limit), conversions between mA and mW/mm²,
  the session intensity (defaults 8 and 2 mW/mm², an irradiance into mA within the limit and the
  channel's reach, an uncalibrated bundle in mA, a change from the LED window kept), the LED settings
  checks, and the session record.
- `doricTest` — the Doric LED shim on DoricLED's simulated driver: the emulator's mode, manual mode,
  setting both channels up in external TTL mode, a request sent only at the next prepare window, an
  ePhys step's currents, calibration light, closing; the LED opened alone as the protocol launches;
  and `TestDoricLED` end to end under `Bpod('EMU')` (skipped without the package).
- `ephysTest` — the ePhys calibration schedule (levels even in mA or, calibrated, in irradiance; the
  default curve to 12 mW/mm² or the channel's most, to the limit when not calibrated; pairs at 8 mW/mm²;
  paired-pulse intervals; order; refusals), its validation with its own sync pulses, the
  EphysCalibration barcode and its fitting to the cameras. `ephysSessionTest` runs a whole ePhys
  calibration session under `Bpod('EMU')` and checks each gate's current against its step.
- `windowsTest` also covers the Doric LED tab (light path, calibration turning mA into mW/mm², a
  limit stopping Start), the calibration window (two cables at a time: default currents 0–1000 mA,
  each channel's limit, readings too few to save, saving per cable and only what changed, saved
  readings shown again, Fill adding a current, the unit converting, a 0–700 mA calibration shown with
  800–1000 mA to measure, the next pair, one cable on both channels refused; and on
  DoricLED's simulated driver, continuous light that follows the selected row and Off), the LED
  window and the ePhys calibration dialog.
- `lintTest` — keeps the repository at zero MATLAB Code Analyzer messages.

Add a test with any behaviour change; the pure functions are the cheap place to do it.
