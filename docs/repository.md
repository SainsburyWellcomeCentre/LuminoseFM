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
│   ├── HoldShaping.m             automatic shaping of the centre hold, and what a broken hold does
│   ├── scoreTrial.m              outcome classification
│   ├── punishmentFor.m           which mistakes are punished, and how
│   ├── launchSubject.m           the subject the session was launched for
│   ├── validateSettings.m        everything that must hold before a session starts
│   ├── stageDefaults.m           the session shape a training stage assumes
│   ├── timerBudget.m             global timers left for light
│   ├── SyncMode.m                how trials drive the sync TTL
│   ├── SessionRunner.m           TrialManager on the rig, blocking in the emulator
│   ├── OnlinePlots.m             the live figure
│   ├── loadSounds.m              the session's sounds, loaded once
│   ├── testSounds.m              a sound of the session as a test, for the setup dialog's Play buttons
│   ├── toneFrequencies.m         stimulus tone frequencies, shared by the two above
│   ├── defaultSettings.m         the two-tier settings struct
│   ├── mergeSettings.m           old settings files converted (renames, reshapes, retirements)
│   ├── +pattern/                 stimulus generator, stimulus set, light patterns
│   ├── +stim/                    cue and stimulus components
│   ├── +sync/                    session barcode; the sync line fitted to the cameras' frame rate
│   ├── +sleep/                   sleep sessions: run, sync and test pulses, blocks, validation, plots
│   ├── +dev/                     device shims, real and null; cameras through SpinCam; the house light on PulsePal
│   └── +gui/                     session type, setup dialogs, camera tab and window, help line, designers, runtime window, theme, plots image
├── hardware/
│   ├── RigConfig.m               the channel map — the single source of truth
│   ├── CheckRig.m                preflight report
│   ├── TestHiFiSound.m           play a test sound through the HiFi module
│   ├── TestSyncLine.m            drive the sync TTL, from states and from a global timer
│   └── TestHouseLight.m          switch the house light through PulsePal, check each switch reaches BNC1
├── tests/
│   ├── runLuminoseTests.m        the whole suite; needs no hardware
│   └── Stub*.m                   test doubles: HiFi, PulsePal, SpinCam's CameraManager
└── docs/
    ├── architecture.md           design decisions and the map from design to code
    ├── hardware.md               the rig: box, ports, light path, Flex I/O, environment
    ├── data-format.md            what a session file contains
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

- **Pure functions** — the stimulus generator and stimulus set, the cue's timing once the stimulus
  starts, trial generation, bias correction, hold shaping and break modes, outcome scoring, the
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
  emulated block landing in its events as `BNC1Low`).
- `windowsTest` — the runtime window, both plot figures (a close request hides them, they save as an
  image, both figures' house light switch), the session type chooser, both setup
  dialogs (automatic shaping by stage, Play buttons, the help line, the Cameras tab, the format's
  description on the help line, and its preview of simulated cameras) and both designers, built invisibly.
- `cameraTest` — camera settings, the format note for single-threaded encoders, the note for a
  one sentence per
  format and which need SpinVideo, where videos go,
  how settings become camera state and what a recording records, against `StubCameraManager`;
  finishing a recording (the save marked before the stop); the camera window; and a whole behaviour
  and a sleep session under `Bpod('EMU')` recording SpinCam's simulated cameras, checking that the
  video stops after the final save and the file still carries the recording summary (skipped without SpinCam:
  on the path, in `SPINCAM_FOLDER`, or beside the MATLAB folder). The other session tests run
  without video, whose load would stretch the emulator's timings they check.
- `emulatorSessionTest`, `sleepSessionTest` — a whole behaviour session and two sleep sessions
  (with and without test pulses) under `Bpod('EMU')`, checking the files they produce — the house
  light clicked off from the live figure part way through (`startHouseLightClicker`): the edge in the
  trial or block, the level per trial or block and the session's record — and the plots image beside
  the data.
- `settingsTest` also covers where the subject comes from (`lum.launchSubject`) and the house light's
  move out of the runtime tier.
- `barcodeTest` also samples fitted barcodes frame by frame at 25–150 Hz, at every phase and with
  the camera 5 % slow, and decodes every one (`lum.sync.fitToCameras`).
- `lintTest` — keeps the repository at zero MATLAB Code Analyzer messages.

Add a test with any behaviour change; the pure functions are the cheap place to do it.
