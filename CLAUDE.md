# LuminoseFM — Agent Instructions

Bpod protocol + helpers for a freely-moving 2-AFC olfactory-bulb optogenetics task
(OSN-ChR mice, patterned light via fiber bundle). `README.md` is the operator's guide and
`docs/hardware.md` the rig description — read both before changing anything.

`AGENTS.md` is a symlink to this file (for Codex / antigravity / OpenCode). If your
platform did not resolve the symlink, read `CLAUDE.md`.

## Environment

| Thing | Path / value |
|---|---|
| Repo (edit here, from WSL) | `/mnt/c/Users/harrislab/Documents/MATLAB/HarrisLabBpodProtocols/LuminoseFM` |
| Same path from Windows | `C:\Users\harrislab\Documents\MATLAB\HarrisLabBpodProtocols\LuminoseFM` |
| MATLAB root | `/mnt/c/Users/harrislab/Documents/MATLAB` |
| MATLAB | R2025b (Update 3) primary; R2024b also installed. Base MATLAB only — no toolbox deps |
| Bpod_Gen2 | `../../Bpod_Gen2` (v1.9.0), on the saved MATLAB path |
| Bpod Local | `../../Bpod Local` — settings, calibration files (not in this repo) |
| PulsePal | `../../PulsePal` — **not** on the saved MATLAB path; add it explicitly |
| Examples | `../../Bpod_Gen2/Examples/Protocols`, and `../FreelyMoving2AFC` (lab's prior 2-AFC) |
| Stimulus generator origin | `../../generatePattern` (`generateStimuli.m`), ported into `+lum/+pattern/generate.m` |
| SpinCam | `../../SpinCam` — the lab's camera package, its own repository (read its `CLAUDE.md` before touching the camera path). On this machine's saved MATLAB path; sessions name it by `S.Camera.SpinCamFolder`. Engine 1.2.0; `spincam.version()` still returns 1.1.0 (SpinCam's to bump, not ours) |
| Spinnaker SDK | `C:\Program Files\Teledyne\Spinnaker` 4.2.0.83, .NET assemblies incl. `SpinVideoNET` in `bin64\vs2015`. SpinCam compiles its engine against them with Windows' `csc.exe` (.NET Framework 4.8) |
| DoricLED | `../../DoricLED` — the Doric LED package (`doric.*`), its own project with its own `CLAUDE.md`; on this machine's saved MATLAB path; sessions name it by `S.Doric.Folder` when it is not. Its bridge `bin/doric_bridge.exe` runs `DoricSystem.dll` out of process. The driver is "LED Driver" on Doric port 4 (a rotary joint on port 3 is skipped by name). Never modify it from here |
| LED calibrations | `calibration/` at the repo root: one `DoricLED_<bundle>_<cable>.mat` (+ `.png`) per cable, used on either channel; rig-local, git-ignored |
| GUI inspiration | `../../luminose_hf` (head-fixed Luminose protocols) — structure only, not its colours |
| Bpod `ProtocolFolder` | `C:\Users\harrislab\Documents\MATLAB\HarrisLabBpodProtocols\` |
| Bpod `DataFolder` | `D:\luminoseData\` = `/mnt/d/luminoseData` — session data live **outside** the repo |

Agents run in WSL; MATLAB and all hardware are on Windows.

```bash
# headless MATLAB from WSL — use for syntax checks and hardware-free unit tests
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch "checkcode('LuminoseFM.m')"
```

If that fails with `Exec format error` (or `MZ...: not found`), WSL's Windows interop is not
registered — systemd in `/etc/wsl.conf` often clears it. It is not a MATLAB problem, and an
agent cannot fix it without sudo. Ask the operator to run, in a WSL terminal:
`sudo sh -c 'echo :WSLInterop:M::MZ::/init:PF > /proc/sys/fs/binfmt_misc/register'`.

The operator restarts MATLAB and power-cycles the state machine and PulsePal between sessions,
and always after a session that ended in an error (`docs/hardware.md` §3). Assume a fresh process when
reasoning about device state; do not add code that tries to recover a stale COM port.

Never open COM ports, call `Bpod`, `PulsePal`, or run the protocol against real hardware
from an agent session — the rig may be running an animal. Use `Bpod('EMU')` (emulator) or
pure-function tests instead, and hand hardware runs to the operator.

**Rig checks.** The operator may give one-time permission to run the hardware (no animal in the
box). Permission covers that request only. Close nothing of theirs: if the MATLAB desktop holds COM3
(`serialportlist('available')` lacks it), ask them to close it. Record every result in
`docs/rig-checks.md`, and add to its *Pending* list anything that needs someone at the rig: seeing
light, hearing sound, poking, moving a cable. The operator works remotely at times, so run those checks
the next time they say they are at the rig. That doc also says how to run a headless session on the
rig: do what `RunProtocol` does, open `_ANLG.dat` and reset the session clock. **Pending now (all need
eyes at the rig): P4 the first calibration of each cable; P5 valve 2's calibration, the centre reward
and the punishment noise heard to its end.** (P1–P3 passed on 2026-09-21.)

## Stay inside the working folder

**Only create, edit or delete files inside this repository** — the `LuminoseFM` folder that
contains this file. Everything else on the machine is off limits for writes, including
`Bpod_Gen2/`, `Bpod Local/` (settings and calibration), `PulsePal/`, `generatePattern/`,
`luminose_hf/`, the data folder, and MATLAB's own path/startup files. Reading them is fine
and encouraged.

The absolute paths in the table above describe *this* machine; `LuminoseFM` sits elsewhere
on other setups, so resolve the repo root from the location of the file you are editing
(or `lum.repoRoot`) rather than hard-coding them.

When something outside the repo genuinely has to change — Flex I/O configuration, the
MATLAB path, a Bpod setting, a calibration file — do not change it. Tell the operator
exactly what to change and where, and let them do it.

## Emulator mode is a first-class requirement

The protocol must run end to end under `Bpod('EMU')` on a machine with no hardware, with
working GUI, plots and data saving. `lum.dev.open` is the **only** file that reads
`BpodSystem.EmulatorMode` (the rig utilities in `hardware/` read it for themselves); it builds real or null device shims once at startup, and every
null shim logs what it would have done into `Data.Session.DeviceLog`. Anything else that
behaves differently in the emulator is told so via `devices.emulated` — the runtime window
choice in `LuminoseFM.m` is the example.

**The emulator is not this rig.** `Bpod('EMU')` emulates a state machine **r0.7-1.0**, not
the r2+. Design around this:

- **The Doric LED is DoricLED's `SimulatedTransport`** when the package is found (`Mode` 'Simulated':
  the real `doric.LightSource`, logging every command), 'Manual' otherwise. The LED window's first
  drawing can hold up the emulator loop, so session tests that check emulated intervals set
  `S.Doric.ShowWindow = false`.
- **Cameras are SpinCam's `mock` backend** when SpinCam is found (synthetic frames through the real
  native engine, real files), `NullCameras` otherwise. Encoding them loads the computer and
  stretches the emulator's already loose timing: session tests that check emulated intervals set
  `S.Camera.Enabled = false`; `cameraTest` runs its own sessions with video.
- **5 global timers, 5 counters, 5 conditions** — against the rig's 16/8/16. Always read
  `rig.Limits.GlobalTimers` from `RigConfig`; never hard-code 16. The trial uses conditions
  1–4 (left, right, centre port clear; hold window over) and always one timer, the hold
  window, so the emulator has four left for light — fewer when a cue light or cue air goes off
  part way through the stimulus, which takes one each. The sync line and the house light take
  none, in any mode.
- **No Flex I/O at all**: no `Flex1` analog stream, no `Flex2DO`, so no airflow viewer, no
  sync pulses and no session barcode (it is recorded with `Sent = false`).
- `BpodSystem.assertModule` **errors** in EMU, as does `BpodTrialManager`'s constructor
  (see D3 in `docs/architecture.md`). Neither may be reached outside the device layer.
- Global timers **are** emulated (trigger, onset delay, duration, channel, end events), but
  `LoopMode` is **not** — a looping timer fires once and never repeats
  (`RunBpodEmulator.m`). Never put stimulus structure in a looping timer; see D1.
  `GlobalTimerCancel` is only **partly** emulated (`RunStateMachine.m`): an active timer stops
  but emits no end event, so the console keeps its line drawn high, and a timer still in its
  onset delay is not cancelled at all and starts later. A zero-onset timer triggered on entering
  a state emits no start event, so the console never draws it high: a light segment starting at
  stimulus onset looks missing on the console, and only later segments are drawn, which reads
  as light arriving late after the poke. The data and the rig are unaffected.
- Conditions on a global timer (`'GlobalTimer<k>'`) **are** emulated; the hold window uses one.
- Conditions are evaluated every emulator loop, so a condition already true on entering a
  state fires at once — `WaitForCentreExit` relies on this (D6).
- A timer triggered in the *first* state is activated without emitting a start event.
- `RunStateMachine` zeroes `HardwareState.InputState` at the end of every trial, so a port
  held high from the console is forgotten between trials.
- The emulator runs states from a MATLAB loop and keeps **no millisecond time**: a state never
  ends before its timer, but may end tens of ms after. Test emulated intervals from below only;
  exact timing is a property of the plan (pure tests) and of the rig.
- Emulated sessions still write a complete data file, flagged as emulated
  (`Data.Info.EmulatorMode = 1`) so it can never be mistaken for real behaviour.

**Playing the mouse.** In emulator mode the operator is the animal: the port buttons on the
Bpod console poke the ports, through `ManualOverride`. A full trial is three clicks — centre
to initiate, centre again to withdraw once the hold is over, then a side port to choose;
the response window does not open until the centre port goes low, so the middle click is
not optional; made before the hold is over, it breaks the hold and a further centre click
restarts the stimulus. Expect to click a port again each trial (see the `InputState` note
above). A sleep session needs no clicks. Do **not** drive `ManualOverride` from a timer at
high rate — it ends with `RefreshGUI` and `drawnow`, and calling it tens of times a second
from inside the emulator's own `drawnow` re-enters the console's callback queue, which
stops the session part way through as though the End button had been pressed.

## Data

- Session file: `D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.mat`,
  containing one variable `SessionData` (= `BpodSystem.Data`), written by
  `SaveBpodSessionData` (full overwrite each call — keep the struct small, save on an
  interval, never inside the stimulus-critical window).
- Settings file: `.../LuminoseFM/Session Settings/<name>.mat`, per subject, chosen in the
  launch manager. `lum.mergeSettings` converts old files (renames, reshapes, retirements). It holds
  the *last* session's settings: written on Start and again at teardown (D16).
- `Data.Session.Type` is `'Behaviour'`, `'Sleep'` or `'EphysCalibration'`. Sleep sessions store `Data.SyncPulses`
  (`Onset`, `Width`, `Block`) instead of trial series; each block is one Bpod trial. With test
  pulses they also store `Data.LightSegments` (`Onset`, `Duration`, `Channel`, `Step`, `Epoch`,
  `Block`, `CurrentmA`, one per gate of light sent) and the compiled steps once in
  `Data.Session.TestPulses` (with `Completed` and `StoppedReason`) — never per-pulse carrier copies.
  ePhys calibration sessions store the same, with `Data.Session.Ephys` (`Settings`, `Steps` with
  `Protocol`, `Label`, `CurrentmA`, `IrradiancemWmm2`, `InterPulseInterval`; `Completed`,
  `StoppedReason`) in place of `TestPulses`.
- Every session stores `Data.Session.DoricLED` (`lum.led.sessionRecord`: `Controlled`, `Mode`,
  `Settings`, `LightPaths`, `Calibrations` as used, `Device` with every current sent in `Changes`)
  and `DeviceLog.DoricLED`. LED currents are stored in mA everywhere; irradiance is derived.
- Flex analog stream: Bpod writes `..._ANLG.dat` beside the session file; merged at teardown
  with `AddFlexIOAnalogData` through `lum.dev.Flex.mergeAnalogData`, which then re-anchors it with
  `lum.dev.Flex.alignAnalog`: the stream starts with the barcode's run, which Bpod counts as a
  trial and does not allow for (D7). Any new state machine run before trial 1 must go through the
  Flex shim so `RunsBeforeTrials` stays right.
- Store session-level things (settings, stimulus set, rig config, barcode, metadata)
  **once** in `Data.Session`; per-trial records hold only events, timestamps, outcome and
  indices into them (`PatternIndex` into `Session.StimulusSet`). Strip `States` from the
  stimulus set before storing it — segments are enough.
- `Data.Session.StoppedReason` is `''` for a session that ran to its end or was stopped from
  the console, and the error message for one that failed. `Session.StimulusSet.GroupPLeft` is
  the contingency as run, `BasePLeft` the one typed in, `Reversed` says whether
  `S.Task.ReverseContingency` swapped them.
- Trial pulses in sessions from 0.2 to 0.5.0 are ~100 us glitches, not the recorded widths
  (D4); align those sessions by the barcode and `Data.TrialStartTimestamp`.
- Per-trial series are listed once, in `trialSeriesNames` in `LuminoseFM.m`; `docs/data-format.md`
  and `emulatorSessionTest` list them too — keep all three in step. Since 0.6.0 they include
  `EarlyWithdrawals` (visits to `EarlyWithdrawal`) and `CameraTime` (seconds on SpinCam's host clock
  when the trial's events arrived; sleep sessions store one per block); since 0.6.1 `HouseLight`
  (the level the trial started at; sleep sessions store one per block too; switches are
  `Data.Session.HouseLight` and `BNC1High`/`BNC1Low` events); since 0.7.0 `LEDCurrentA`,
  `LEDCurrentB` (mA the trial ran at; NaN when the LED was set by hand); since 0.8.0
  `CentreReward` (µL given at the centre port, 0 when none), `ResponseRetries` (visits to
  `RetryResponse`) and `CentreHoldTime` (s in the centre port on the last hold, poke to exit).
  `Choice`/`Correct`/`Outcome` are always the **first** side poke; a retried trial is `Incorrect`
  with `Rewarded` 1, so water totals use `Rewarded` and `CentreReward`, never `Outcome`.
- `..._ANLG.dat` is Bpod's raw stream of the Flex analog input (flow meter), opened by the launch
  manager and written as samples arrive; the `.mat` gets it as `Data.Analog` at teardown. Kept as
  the raw copy; see `docs/data-format.md`.
- Teardown (D16) saves the plot figure as `<data file name>_plots.png` beside the data file
  (`lum.gui.savePlotsImage`, path in `Data.Session.PlotsImage`) before the final save, and after it
  writes the settings back to the settings file captured at session start (`settingsFile`), runtime
  changes included; headless sessions write no settings. Keep both in both teardowns.
- Video (D14): `...\LuminoseFM\Session Videos\<view>_<data file name>.avi` + `.csv` per camera,
  `<data file name>_events.csv` and `_session.json`, written by SpinCam; `Data.Session.Cameras`
  (`lum.dev.Cameras.sessionRecord`) records settings, plan and per-camera summary (the summary is
  written by the second save after the video stops). `_events.csv` ends `SessionSaved`,
  `RecordingStop`. The folder is `lum.dev.Cameras.videoFolder(dataFile)`; never write video
  anywhere else.

## Hardware map (Bpod FSM r2+, firmware 23, FSM `COM3`, App `COM4`)

- Behavior ports: 1 = Left, 2 = Centre, 3 = Right, 4 = Air valve, 5 = unused (the house light's
  until it moved to PulsePal). Port `n` → `PWMn` (LED), `Valven` (solenoid), `PortnIn`/`PortnOut`
  (IR gate). Port 4 uses the valve line only; its IR gate is unused. `Valve2` (centre) gives
  water only for habituation's centre reward (D19), timed from valve 2's liquid calibration.
- Optical channels **A** and **B**: `BNC1` → PulsePal `IN1` → `OUT1` → Doric LED ch1 is
  channel A; `BNC2` → `IN2` → `OUT2` → LED ch2 is channel B (`rig.Opto.Channels`,
  `rig.Opto.Labels`). A light pattern is the ON/OFF sequence of A and B over the stimulus
  window. The Doric driver (`LEDFLS_465_465`, USB, "LED Driver" on Doric port 4) runs both channels
  in **external TTL mode** at their LED currents (D17); PulsePal's 5 V is a TTL level, not the
  intensity. LED ch1 → commutator A, ch2 → commutator B.
- Fiber bundles (`lum.fiberBundles`), cables named by colour, any two on A and B at the commutator,
  recorded in `S.Light.Cables` (A then B): 2-to-19 with blue (9 spots) and green (10), **blue on A and
  green on B** by default; 4-to-19 with black (4 spots), blue, orange, green (5 each), **orange on A
  and blue on B** by default (`Defaults`). Each spot is a
  100 µm fiber (`CoreDiameter`), so a cable's area is spots × π × (0.05 mm)². The cable is called
  orange everywhere; do not call it red.
- Flex I/O (`Bpod Local/Settings/FlexConfig.mat`): channel types are 0 = digital in,
  1 = digital out, 2 = analog in, 3 = analog out, 4 = disabled. Flex1 = **analog input**
  (flow meter, 1 kHz); Flex2 = **digital output**, the sync TTL (barcode and trial pulses) —
  configured on this rig since 0.5.0 (sessions from 2026-09-15 record
  `Session.DevicesAvailable.FlexSync = 1`); Flex3-4 disabled. Read the live configuration
  (`BpodSystem.HW.FlexIO_ChannelTypes`), never the saved file. Note `docs/BpodSystemInfo.png`
  predates both, so trust the live values where they disagree.
- Modules: `HiFi1` (Module#1, USB `COM8`) → amplifier → speaker. Modules 2/3 unregistered.
- Cameras: 2 × Chameleon3 CM3-U3-13Y3M on one USB 3.0 controller, recorded through SpinCam.
  **24226887 = sideview, 24226657 = topview** (`S.Camera.Cameras`). Default 100 Hz full frame,
  `avi-mjpeg-mt`; both cameras on one USB 3.0 controller deliver at most 120 Hz full frame together.
  Line0 (yellow/brown) is logged per frame; **Flex2 is wired to both cameras' Line0** (through the splitter,
  3.3 V TTL, since 2026-09-17), so `TTL_State` carries the barcode and trial pulses. The first wired session
  (`FakeSubject_LuminoseFM_20260917_082143`) logged all 79 pulses on both cameras and decoded the barcode from each;
  0.6.1 rig sessions `..._20260917_111703` (behaviour) and `..._112004` (sleep with test pulses) did the same.
  A frame samples the line once, so with video the session fits the line to the cameras
  (`lum.sync.fitToCameras`): barcode elements and sync pulses ≥ 2 frames, bit/marker widths ≥ 3 frames
  apart. Typed widths are minimums and stay in the settings file; sessions send and record the fitted
  ones (`Session.SyncFit`). Anything new put on the sync line must go through it.
- House light: **PulsePal OUT3** (5 V on: resting voltage, then written with op 79) → BNC splitter →
  LED driver, and → **Bpod BNC input 1** (`BNC1High`/`BNC1Low`), `rig.HouseLight` (D15). BNC input 1
  must be enabled in the console's port settings (`CheckRig`). The loopback works since 2026-09-21
  (18–33 ms, command to edge); before 0.7.0 the light never switched on, because firmware v21 does
  not write an output on its resting voltage alone (see the PulsePal gotcha). If the wiring changes,
  change `RigConfig`, not the code. PulsePal OUT1/OUT2 are channels A/B; OUT4 is free.
- Budget: 16 global timers, 8 global counters, 16 conditions **on the rig**; the emulator
  has 5/5/5. Read `rig.Limits` rather than assuming either. The hold window always takes one
  timer (`lum.timerBudget`); the house light takes none.
- `docs/BpodSystemInfo.png` is the authoritative event/output list. Regenerate it
  (`BpodSystem.StateMachineInfo`) if the rig wiring or Flex config changes.

## Naming

Naming is part of the design here: the operator, the plots and the data file all read the
same words, and a misleading name has already cost a data field its meaning once
(`LeftProbabilityUsed`, which was the bias target). Use these, and fix any code, label or
doc that does not:

| Word | Means | Not |
|---|---|---|
| channel A / B | optical channels, BNC1 / BNC2 | pattern 1/2, ch1/ch2, BNC in operator text |
| light pattern | what one trial delivers on A and B | schedule, spec, stimulus (alone) |
| joint state | 0 dark, 1 A only, 2 B only, 3 A and B | silence (for light) |
| group | one stimulus condition; K groups balanced over the session | stimulus index, trial type |
| stimulus set | patterns + groups + contingency + trial order | dictionary |
| stimulus window | `S.Stimulus.Duration` from stimulus onset | stimulus duration of the hold |
| latency | `S.Stimulus.Latency`, poke to stimulus onset, held with the cue on | delay, pre-stimulus hold (as a setting) |
| hold / hold break / grace | centre hold; leaving during it; forgiven break length | |
| hold window | `S.GUI.HoldWindow`, from trial start, across restarts | initiation window (0.2 name) |
| session type | `'Behaviour'`, `'Sleep'` or `'EphysCalibration'` (`S.Session.Type`, `Data.Session.Type`); shown as Behaviour, Sleep, ePhys calibration (`lum.gui.Form.sessionLabel`) | protocol, mode |
| carrier | PulsePal per-channel frequency, pulse width, voltage | waveform |
| centre | British spelling in identifiers too (`CentreHold`) | `Center` |
| task variant | which variant of the task a session runs: Familiar/Novel, Mixture, Sequence, Motifs (`S.Task.Variant`) | task type, paradigm |
| contingency reversal | swapping which side every group pays, P(left) to 1 - P(left) (`S.Task.ReverseContingency`) | flip, switch |
| test pulses | light in a sleep session: probes and plasticity trains on a schedule (`S.Sleep.TestPulses`) | opto stimulation, stim |
| epoch | one probe (single pulse or pair) or one train; never split across state machines | trial, sweep |
| inter-pulse / inter-epoch interval | onset to onset: within a pair; between epochs | gap, ISI (unqualified) |
| plasticity train | named bursts-of-pulses definition (theta burst, high frequency, custom) | protocol, stimulation |
| schedule step | one row of `S.Sleep.TestPulses.Schedule`: probe, rest or a train name | block (a block is a state machine run) |
| light segment | one gate on A or B; a probe pulse, or a burst PulsePal fills (`LightSegments`) | pulse, when it is a burst |
| automatic shaping | performance-driven training under one switch (`S.Task.AutoShaping`): now the centre hold, method `S.Task.HoldShaping`; later trial difficulty | hold shaping *Off* (the 0.5 mode) |
| step back | automatic shaping shortening the hold one growth step after `HoldStepBackAfter` early withdrawals at one hold | regress, reset (in names too) |
| early withdrawal | leaving the centre port before the hold is complete, unforgiven (state `EarlyWithdrawal`) | hold break (that is the forgiven kind) |
| centre reward | water at the centre port for a completed hold, habituation's first `CentreRewardTrials` trials (state `CentreReward`, `Data.CentreReward`) | centre drop, initiation reward |
| retry | going on to the correct port after an unpunished incorrect choice (state `RetryResponse`, `Data.ResponseRetries`) | correction trial (it is the same trial) |
| centre hold time | seconds in the centre port on a trial's last hold, poke to exit (`Data.CentreHoldTime`) | hold duration (that is what the trial asked for) |
| view | a camera's name and file prefix: `sideview`, `topview` | camera name, cam1 |
| camera clock | SpinCam's host clock: `HostTime_s`, `_events.csv`, `Data.CameraTime` | video time |
| house light | the white light in the box, on PulsePal OUT3, looped back into BNC input 1 (`S.Session.HouseLight`, `S.Sleep.HouseLight`, `S.Ephys.HouseLight`, `Data.HouseLight`, `Session.HouseLight`) | room light, port 5 light |
| LED current | the Doric driver's current on LED ch1 (A) or ch2 (B), mA: how bright a gated channel is (`S.Doric.CurrentmA`, `Data.LEDCurrentA/B`, `LightSegments.CurrentmA`) | LED power, voltage, intensity (as a stored value) |
| light path | one optical channel and the bundle cable on it (`lum.led.lightPath`) | fiber (alone) |
| irradiance | power at the fiber tips over their area, mW/mm², shown in place of mA once the cable is calibrated | power density, intensity (as a stored value) |
| LED calibration | power meter readings at several currents for one cable, used on either channel (`lum.led`, `calibration/`) | power curve, channel calibration |
| LED window | the session window that shows and changes each channel's LED current (`lum.gui.DoricWindow`) | runtime window (that is the parameters') |
| ePhys calibration | the third session type, `'EphysCalibration'` (`S.Ephys`, D18) | calibration session, ephys mode |
| input-output curve, paired-pulse ratio | the two ePhys calibration protocols (`S.Ephys.InputOutput`, `S.Ephys.PairedPulse`) | IO sweep, PPR (in operator text) |

Version 0.2 renamed states, data fields and settings accordingly; the full table is in
`docs/naming-and-versions.md` and `docs/architecture.md` D8. **Rename by migration**: add the old → new
path to the rename table in `lum.mergeSettings` so existing settings files keep their
values, and never renumber a stored code (`lum.Outcome`, `lum.SyncMode`, punishment codes).

## Conventions

- **Entry point**: `LuminoseFM.m` in the repo root. Bpod's launch manager requires
  `<ProtocolFolder>/<Name>/<Name>.m`, so the filename must match the folder name
  `LuminoseFM` exactly (case included). Helpers go in subfolders, never nested protocols.
- **Three session types, one protocol (D11, D18).** `LuminoseFM` opens `lum.gui.SessionTypeDialog`
  first; *Sleep* and *ePhys calibration* hand the whole session to `lum.sleep.run`, which must
  release every `lum.*` object, the LED included, before returning. Headless runs (`setappdata(0, 'LuminoseFM_Headless', true)`) take the
  type from `S.Session.Type`. Sleep and ePhys sessions run blocks with blocking `RunStateMachine`
  on the rig too — they have nothing to prepare, so `SessionRunner` does not apply. All three setup
  dialogs build `S.Meta` through `lum.gui.ExperimentForm`; add an experiment field there once.
- **The Doric LED (D17).** Intensity is the driver's, timing stays Bpod's and PulsePal's: both LED
  channels in external TTL mode, the state machine untouched. `lum.dev.DoricLED` ('Device',
  'Simulated', 'Manual'), chosen by `lum.dev.openDoricLED`, wraps `doric.LightSource` (public API
  only: `connect('Wait', false)`, `apply`, `startAll`, `Channels(k).setCurrent/MaxCurrentmA`,
  `stopAll`, `disconnect`, `record`, `poll`). `LuminoseFM` opens it before the session type dialog
  (`lum.dev.open(rig, S, 'Only', 'DoricLED')`, so `open.m` stays the only reader of emulator mode);
  it connects in the background; the dialogs get it as `'DoricLED'`; `lum.dev.open(..., 'DoricLED',
  led)` waits (`ensureReady`) and sets it up (`setUp`), and refuses a session with light (or any ePhys
  session) on the rig when it fails. **Every return path releases it** (`releaseLED`), and both
  teardowns close it first (`closeDevices`). Currents change only in the prepare window
  (`applyPending(trial)`, which returns what the next trial runs at) or between blocks
  (`applyPending(block)`; ePhys `setCurrents(step.CurrentmA)`, blocking). Settings and data hold mA;
  windows show mW/mm² for a channel whose cable is calibrated, through `lum.gui.IntensityField`. A
  calibration is per **cable** (bundle and colour), not per channel (`lum.led.calibrationFile`): the
  two LED channels are taken to give equal power at equal current, so a cable swapped to the other
  channel keeps its calibration. It records the channel it was measured on (`MeasuredOn`). Saved to
  `calibration/` by `lum.gui.DoricCalibration`, replaced by the next one of that cable. `lum.led.validate(S)` is the LED
  check every session's validation runs (errors cals-independent; notes only when given cals).
  The DoricLED package is optional: without it, or with `S.Doric.Enabled` off, the driver is used as
  set by hand and currents are NaN.
- **ePhys calibration (D18).** `lum.ephys.plan` compiles each step (an input-output level or a
  paired-pulse interval) through `lum.sleep.testPulsePlan` as a probe step and joins them into one
  plan of the same shape, adding per step `Protocol`, `Label`, `CurrentmA`, `IrradiancemWmm2`,
  `InterPulseInterval`. `lum.ephys.validate` requires `S.Doric.Enabled` and uses the checks shared
  with sleep (`lum.sleep.validateClock`, `lum.sleep.checkTimeline`). `lum.sleep.run` runs it with
  `S.Ephys.Sync`, `S.Ephys.HouseLight`, `lum.gui.EphysSetupDialog` and barcode kind
  `'EphysCalibration'` (`S.Sync.Barcode.EphysMarkerWidth`, 300 ms; `lum.sync.markerWidth`).
- **Sleep test pulses (D13).** Light in a sleep session goes the behaviour way: Bpod gates
  BNC1/BNC2, PulsePal fills each gate (constant light for a probe, the train's pulses for a
  burst). `lum.sleep.testPulsePlan` compiles the schedule into gates and epochs in integer
  100 µs cycles before the session; `lum.sleep.syncPulseTimes` lays out the sync pulses;
  `lum.sleep.nextBlock` cuts both into ~10 s state machines **only where every line is low,
  never inside an epoch, and before the first epoch of a new step**; `lum.sleep.blockStateMachine`
  makes one `LevelNNN` state per span between edges. No global timers. PulsePal is programmed
  only between blocks, after `checkConnection`, and checked again at every save; a failure ends
  the session with `StoppedReason`. Open devices through `lum.sleep.deviceSettings`, so a
  session with test pulses is refused without PulsePal. `lum.sleep.validateTestPulses` is the
  one check the designer, the sleep dialog and the session share. With test pulses on, the
  recording lasts as long as the schedule; `S.Sleep.DurationMinutes` is kept but unused.
- **The training stage shapes the session (`lum.stageDefaults`).** Choosing *Habituation* in the
  setup dialog switches the light pattern off (`S.Session.UseOpto`, `S.GUI.OptoOn`) and the
  stimulus air on for the whole window; choosing *Training* or *Experiment* does the reverse.
  *Habituation* and *Training* also switch automatic shaping on, *Experiment* off. Defaults, applied only on the
  dropdown's change, never during a session and never enforced by validation — the operator may
  untick anything afterwards — **except** automatic shaping in an Experiment session, which
  `lum.validateSettings` refuses (`shapingInExperiment`).
- **Automatic shaping (D6).** `S.Task.AutoShaping` (off by default) switches it; decide everything
  through `lum.HoldShaping.activeMode(S)` / `growsHold(S)` / `hasGrace(S)`, never by reading
  `S.Task.HoldShaping`, which has no *Off* any more (old files are migrated in `lum.mergeSettings`).
  Grow hold starts at 0.1 s, targets 1 s, and steps back one growth step after
  `S.GUI.HoldStepBackAfter` (10) early withdrawals at one hold; the count is
  `history.withdrawalsAtHold`, kept by `lum.updateHistory`. Future difficulty shaping goes under the
  same switch.
- **House light (D15).** PulsePal's, not Bpod's: **PulsePal OUT3** → BNC splitter → the light's LED
  driver, and the copy into **Bpod BNC input 1** (`rig.HouseLight`: `PulsePalChannel` 3, `Voltage` 5,
  `Input` `'BNC1'`, `OnEvent` `'BNC1High'`, `OffEvent` `'BNC1Low'`). Switched at once, mid-trial and
  mid-block, by `devices.houseLight` (`lum.dev.HouseLight`: `RealHouseLight` on the rig,
  `NullHouseLight` in the emulator). Where it starts: `S.Session.HouseLight` (setup dialog, Experiment
  tab) and `S.Sleep.HouseLight` (sleep setup dialog); during a session the only switch is the
  **House light** box in the live figure's header (`lum.gui.houseLightSwitch`, in `lum.OnlinePlots` and
  `lum.sleep.Plots`). It is not a runtime-tier parameter (a 0.6.1 settings file's `GUI.HouseLight` is
  renamed on load).
  - **Holding it**: `lum.dev.PulsePal.holdVoltage(3, 5|0, done)` sets OUT3's *resting voltage*
    (parameter 17), which the firmware returns to after every stop, abort and disconnect
    (`PulsePal_2_0_1.ino`, `killChannel`), then writes the voltage to the output (op 79,
    `sendOutputVoltage`); it also unlinks OUT3 from both trigger inputs.
    Only outputs 3–4 may be held. Set when `lum.dev.open` builds the device; 0 V when it is closed,
    which `closeDevices` does **before** PulsePal. **The state machine has no part in it**: no timer,
    no output, no state — never add one, and nothing else may use OUT3 or BNC input 1.
  - **Every session on the rig opens PulsePal** (`lum.dev.openPulsePal`, any session type). One
    with light refuses to start without it. One without light (`S.Session.UseOpto` off; sleep sets it
    from test pulses) runs on the null shim with a warning, and `lum.dev.openHouseLight` gives it
    `lum.dev.DisabledHouseLight` — also when a connected PulsePal refuses the light's level: off,
    `Switchable` false, the box greyed out (`lum.gui.houseLightSwitch`), and both teardowns keep the
    settings' level rather than writing `On` back. Choose the light only through `openHouseLight`.
    Port 5 is unused.
  - **Checking it on the rig**: `hardware/TestHouseLight` — soft codes from a state machine call
    `houseLight.set` (restoring Bpod's `SoftCodeHandlerFunction` after), and each switch must come
    back as a BNC1 edge; it prints latencies. It runs under `Bpod('EMU')` too (`houseLightTest`).
    Hand the rig run to the operator.
  - **Sharing the port**: a click's callback runs inside any `pause`/`drawnow`, including PulsePal's
    handshake (0.1 s) and serial code. `lum.dev.PulsePal` counts commands under way (`enter`/`leave`
    around `configure`, `stopOutputs`, `checkConnection`); `holdVoltage` during one is sent when it
    finishes (latest per output wins). Any new PulsePal command must go through the same guard. The
    light, the camera mark, the record and the windows change when PulsePal takes it (`done`), not at
    the click; a refusal warns and puts the boxes back.
  - **Timing it**: a switch during a state machine is a `BNC1High`/`BNC1Low` event on Bpod's clock
    (the loopback wire). In the emulator `NullHouseLight.echo` puts that edge into the running
    emulated state machine (`VirtualManualOverrideBytes` `'V'`, as the console's BNC input button). A
    switch between state machines has no Bpod event. Every switch is also `cameras.mark('HouseLight')`.
  - **Recorded**: `Data.HouseLight` per trial/block is `lum.dev.HouseLight.levelAtStart(events, rig
    .HouseLight, fallback)` — the first edge decides; with no edge, `houseLight.levelAt(arrival time −
    trial length)` on MATLAB's clock (`sessionTime`). `Data.Session.HouseLight = houseLight.record(
    BpodSystem.Data)`: wiring, `OnAtStart`/`OnAtEnd`, `Switches` (camera and wall time) and `Edges`
    (Bpod clock, trial). `DeviceLog.HouseLight`, and PulsePal's log has `ch3 param 17` and
    `ch3 output = <V> V` lines. The
    level at the end is saved to the settings file.
- **Subject.** `LuminoseFM` takes it from `lum.launchSubject(BpodSystem.GUIData.SubjectName,
  BpodSystem.Status.CurrentSubjectName, BpodSystem.Path.CurrentDataFile)`: the launch manager's
  Launch button always sets `GUIData.SubjectName`, but `Status.CurrentSubjectName` only when the
  subject list's selection changes, which left sessions up to 0.6.1 with an empty subject.
- **Video (D14).** `devices.cameras` (`lum.dev.openCameras`): on the rig a session with
  `S.Camera.Enabled` refuses to start without SpinCam or a ticked camera; in the emulator it uses
  SpinCam's mock cameras or the null shim. `lum.dev.configureCameras` is the only place settings
  become camera state (the session and the Cameras tab preview both use it). Recording starts
  right after `lum.dev.open`, before the barcode; per trial only `devices.cameras.mark` runs. It
  stops **after** the final save (and, in behaviour, after the trial manager is closed), through
  `devices.cameras.finishRecording('SessionSaved', n)`, and a second small save adds the recording
  summary to `Data.Session.Cameras` — so everything in the data file is on the video. Keep that
  order in both teardowns. Only native formats (`lum.dev.Cameras.Formats`); `matlab-*` would be
  starved by the trial loop. The default is `avi-mjpeg-mt` (SpinCam's multi-core MJPEG, engine
  1.2.0): SpinVideo's `avi-mjpeg` has 4 % headroom at 100 Hz full frame and fell behind with the
  camera window open, and `lum.dev.Cameras.formatNote` says so at validation. Each offered format has one sentence in
  `lum.dev.Cameras.FormatDescriptions` (same order as `Formats`; `cameraTest` checks one sentence
  each): it is the dropdown's tooltip and, through `CameraSetup.useHelpLine` (called by both setup
  dialogs after `registerTooltips`), the help line, updated on every change. Add a format to both
  lists together. `lum.dev.openCameras` refuses a SpinVideo format (`needsSpinVideo`) when the
  engine lacks SpinVideo (`SpinCam.Engine.HasSpinVideo`), before recording starts;
  `Session.Cameras.EngineVersion` records `SpinCam.Engine.Version`. Use only SpinCam's public API
  (`spincam.CameraManager`, `VideoRecorder`, `SpinCam.Engine`), never `spincam.internal.*`. The
  dependency list is `docs/hardware.md` §3. Never modify SpinCam
  from this repository — it is outside the working folder; changes to it are made in its own
  repository, under its own `CLAUDE.md`, only when the operator asks.
- **Help line.** Every runtime parameter declares its help as the last argument of
  `numericParam`/`checkboxParam`/`menuParam` (`GUIMeta.<name>.Help`); `lum.gui.HelpLine` shows it,
  and any control's `Tooltip`, at the foot of the setup dialogs and the tabbed runtime window. Give
  new controls a tooltip that explains them, not just names them; register the help line after the
  window's callbacks are set (it chains them).
- **Play buttons.** `lum.testSounds(S, which, nGroups)` turns the dialog's settings into
  `TestHiFiSound` argument lists; the dialog's `'SoundPlayer'` option lets tests record them.
  Group tone frequencies come from `lum.toneFrequencies`, shared with `lum.loadSounds`. `S.Task.Variant` (Familiar/Novel,
  Mixture, Sequence, Motifs; `lum.experimentChoices().TaskVariants`) names the task and is
  recorded; per-variant defaults will go in `lum.stageDefaults`'s neighbourhood when they exist.
- **A failed session is torn down, not abandoned.** The trial loop in `LuminoseFM` is wrapped in
  a `try`: on an error the trials that completed are saved, the analog stream merged, the
  windows closed, the devices released and `RunProtocol('Stop')` called (which flushes the serial
  link), and only then is the error warned about, with `Data.Session.StoppedReason` recording it.
  `lum.SessionRunner` reports a lost Bpod link as `lum:SessionRunner:linkLost`. Anything added to
  the loop must keep working when it is entered part way through.
- **Namespacing**: put reusable code in a MATLAB package (`+lum/...`) or clearly named
  helper folders; the protocol file stays a thin session script. `hardware/` holds rig
  utilities usable outside a session (e.g. `TestHiFiSound.m`).
- **Style**: 4-space indent, `camelCase` locals, `PascalCase` classes, `snake`-free names.
  Follow Bpod idiom over general MATLAB idiom: `global BpodSystem`, settings struct `S`,
  `S.GUI.*` / `S.GUIMeta.*` / `S.GUIPanels.*` / `S.GUITabs.*`, `SaveBpodSessionData`.
  Never name a variable after a builtin (`set`, `image`, `now`): the stimulus set variable is
  `stimulusSet`.
- **One GUI, two tiers, one declaration.** D2 splits `S` by *when a parameter stops being
  editable*, not by who sets it. Both tiers are editable in `lum.gui.SetupDialog`.
  - Declare a runtime parameter on one line of `lum.defaultSettings`, through
    `numericParam`/`checkboxParam`/`menuParam`, add it to an `S.GUIPanels` entry, and put
    the panel in an `S.GUITabs` entry. It then appears in the setup dialog (Runtime tab, or
    the Task tab for the `Shaping` panel), in the tabbed runtime window and in Bpod's
    compact one; there is no second list to update.
  - `GUIMeta.Label` (readable name with units) and `GUIMeta.Limits` are ours. The tabbed
    `lum.gui.RuntimeWindow` shows and enforces them; Bpod's `BpodParameterGUI` (the compact
    window) ignores them, supports `GUIPanels` but **not** `GUITabs`, and labels controls with
    field names, so `lum.gui.relabelParameterGUI(S)` runs straight after its `init`.
  - Declarations are always taken from the defaults when settings are merged: GUIMeta,
    GUIPanels, GUITabs, `Sync.ModeNames`, `Task.TrainingStageNames`.
  - `lum.validateSettings` is the single definition of "can this session start"; the setup
    dialog runs it on every edit (with the last compiled stimulus set passed in when the
    stimulus settings have not changed), the Start button runs it, and `LuminoseFM` runs it
    again before opening any device.
  - Components are switched on from the Task tab's checkboxes, which are the `Enabled` flags
    themselves; the Cue/Stimulus/Left/Right tabs time them and show on/off chips. Do not add a
    second enable control for a component on its own tab.
  - Windows draw with `lum.gui.theme` — light, neutral, colour only for meaning (channel A
    teal, B coral, sides indigo/ochre, outcomes green/red/grey). Do not copy luminose_hf's
    dark palette. The logo comes from `lum.gui.logo(n)` (block-averaged, cached, no toolbox).
- **The stimulus is a stimulus set (D5).** `lum.pattern.generate` makes the patterns and a
  balanced order from `S.Stimulus.Generator` and a seed; `lum.pattern.stimulusSet` compiles it
  into segments, applies `S.Task.GroupPLeft` and then `S.Task.ReverseContingency` (`GroupPLeft`
  is the contingency as run, `BasePLeft` as typed, `Reversed` says which), and refuses a pattern
  over the timer budget or identical groups paying different sides. `lum.pattern.patternAt(set, k)` recovers one
  pattern. The seed is drawn per session by `lum.pattern.prepareSeed` before the setup dialog
  opens, so the preview is the session. The generator uses a private `RandStream` — never the
  global rng.
- **The optical carrier is per channel.** `S.Light.Carrier` is a struct array, one element per
  optical channel, each with `Channel`, `Frequency`, `PulseWidth`, `Voltage`;
  `lum.stim.OptoPattern` adds `MaxDuration`. Element *k* programs PulsePal output *k*, and a
  mismatched `Channel` field is rejected (`lum.dev.PulsePal.validateCarrier`, static, so no
  device and no log line).
- **Real-time first.** This is the hard constraint of the project:
  - Drive trials through `lum.SessionRunner`, which uses `BpodTrialManager` on the rig and
    blocking `RunStateMachine` calls in the emulator (D3). All per-trial work belongs in
    the prepare window it opens.
  - Preallocate; never grow arrays, structs or plot data inside the trial loop.
  - No `figure`, `plot`, `cla` or bare `drawnow` in the loop — update existing handles
    (`set(h,'YData',...)`) and use `drawnow limitrate` at most once per trial. The setup
    dialog and designer may redraw freely; they never run during a session.
  - Keep per-trial cost O(1): maintain running stats, don't re-scan `BpodSystem.Data`.
    `lum.nextTrialSpec` looks at most 50 trials ahead of the queue.
  - Don't store large per-trial copies; store a session-level set plus per-trial indices.
  - Reprogram PulsePal / HiFi during the inter-trial window, never mid-stimulus. Sounds are
    loaded once (`lum.loadSounds`, only those the session can play).
- **Trial-flow contract**: state names stay fixed across stimulus modalities, cues and hold
  shaping (trial start / waiting for the poke with the cue on / pre-stimulus hold (the latency)
  / centre hold / hold break / resumed hold / centre reward / centre exit / response / reward /
  incorrect choice / retry / ITI); these change only the `OutputActions`, state timers, global timers and where a
  poke, a completed hold or a wrong side poke leads. Plots, analysis and `lum.scoreTrial` depend
  on this. Version 0.4 removed the `Cue`, `Cue2`… states (D12); 0.8.0 added `CentreReward` and
  `RetryResponse` (D19).
  - **The cue lasts until the stimulus starts, `S.Stimulus.Latency` after the poke (D12).** Every
    cue component is an output of `WaitForCentrePoke`, which has no timer. `Port2In` there leads
    to `PreStimulusHold` when the latency is above 0 and straight to `CentreHold` at 0, the
    default — never put a state or a delay on the zero-latency path. `PreStimulusHold` lasts the
    latency, starts nothing, leaves the cue on, and leaving it goes to `EarlyWithdrawal` (a broken
    hold; grace is timed from stimulus onset and does not apply). From stimulus onset each cue
    component follows `lum.cueTiming`: *Whole* (continues until the hold ends, the default),
    *Off* (off as the stimulus starts) or *Timed* (off that long into the stimulus). A timed centre
    light or air is a global timer triggered and cancelled with the stimulus's; the cue tone is a
    loop (`Cue`) replaced at stimulus onset by a tail (`CueTail`) or stopped, never a timer
    (`lum.stim.CueTone`). Cue components answer `onsetActions` for `CentreHold`. The latency is a
    pre-session setting, so `HoldDuration` stays the hold from stimulus onset.
  - **The stimulus plays only while the animal holds (D10).** `EarlyWithdrawal` cancels it; with
    `S.Task.OnHoldBreak` *Restart stimulus* (default) it returns to `WaitForCentrePoke`, and the
    next `CentreHold` re-triggers every stimulus timer. The hold window is a global timer
    triggered only in `TrialStart` and never cancelled; `WaitForCentrePoke` has no state timer
    and leaves on that timer's end or condition 4. Never trigger or cancel the hold window
    anywhere else, and keep `EarlyWithdrawal` out of the trigger states in restart mode
    (`lum.triggerStates`).
  The
  hold ends in `WaitForCentreExit`, which waits for `Port2Out` (or condition 3, the centre
  port already clear) before opening the response window — do not shortcut `CentreHold`
  straight into `WaitForResponse`, or the side ports are live with the animal's nose still in
  the centre port and its withdrawal beam break is scored as a choice.
  - **States, not timers, for what happens outside the stimulus** — the cue before stimulus
    onset, the latency, the barcode, every trial sync pulse (D4), and a sleep session's sync and
    test pulses (D13). Global timers are for what happens inside the hold, where leaving the port
    must end it at any instant: light segments (D1), the grace hold clock (D6), stimulus
    components switched on late or off early (D9), and cue components switched off part way
    through the stimulus (D12). What a timer's `Channel` does across state entries depends on the
    line (firmware 23): a BNC, Wire, PWM or valve line is marked overridden while the timer runs,
    and a state entry skips it; a **Flex** output has no such check, and the state wins on every
    entry — which is what broke the Flex2DO sync pulse (D4). Never rely on a timer holding a Flex
    line.
  - **Output actions do not persist across states.** Bpod writes *every* output channel from the
    entered state's own row, so a level a state switched on is dropped by the next state unless
    that state writes it again. `lum.stim.Component.sustainActions` / `sustainOnsetActions` are
    those repetitions — the same levels, without the timer triggers that must fire once and
    without the play commands that would restart a sound (a serial channel with no action in a
    row is sent nothing, so sound plays on by itself). `PreStimulusHold` sustains the cue;
    `HoldBreak` and `CentreHoldResumed` sustain the stimulus, so a forgiven break does not switch
    the air or the centre light off; `WaitForResponse` repeats `WaitForCentreExit`'s guide lights.
  - **The HiFi module plays one sound at a time**; a new play command replaces the sound playing.
    `lum.validateSettings` refuses two sounds that start with the stimulus (`soundClash`), and
    with restarts an early-withdrawal noise is let finish before `WaitForCentrePoke` plays the
    cue tone again.
  - `HoldBreak` and `CentreHoldResumed` exist in every trial. Without grace shaping they are
    unreachable; with it, `CentreHold` triggers the stimulus timers and the hold clock, and
    `CentreHoldResumed` must **not** re-trigger them.
  - **Centre reward and retries (D19).** `CentreReward` and `RetryResponse` exist in every trial.
    A completed hold goes through `CentreReward` (centre valve open for the calibrated time,
    response configuration up) only when `spec.CentreReward` (habituation, trial number ≤
    `S.GUI.CentreRewardTrials`, amount > 0; `lum.nextTrialSpec`); never put it on the poke's path.
    A wrong side poke goes to `RetryResponse` (0 s, back to `WaitForResponse`, whose timer restarts)
    when `lum.punishmentFor(S, 'IncorrectChoice').Retry` — the default, `PunishCondition` 1 — and to
    `IncorrectChoice` (a trigger state; timeout, noise, no reward, ITI) when punished. Neither new
    state may be a trigger state: the trial passes through exactly one. A punishment that plays the
    noise and is followed by the ITI lasts at least `S.Sound.NoiseDuration`, because the ITI sends
    the HiFi stop command.
- **Sync TTL, driven by states in every mode (D4)**: `S.Session.UseSync` says whether the line
  is driven, `S.Sync.Mode` (`lum.SyncMode`: FixedWidth, JitteredWidth, TaskEvents) says how
  trials drive it. A pulsed mode makes the pulse `TrialStart`'s own state timer and drops the
  line in `WaitForCentrePoke` as the cue comes on; `TaskEvents` leaves `TrialStart` at zero,
  holds the line high through `WaitForCentrePoke`, and drops it on the poke — in
  `PreStimulusHold`, or `CentreHold` without a latency — and in `NoInitiation`. **No mode costs
  a global timer**, and none may: before 0.5.1 a pulsed mode was a global timer linked to the
  channel and triggered in `TrialStart`, whose zero timer meant `WaitForCentrePoke` re-wrote the
  line low one cycle later, so every pulse reached the recording as a ~100 us glitch while the
  barcode came through perfectly. Never drive the sync line from a global timer again. The mode
  is part of the data format — it decides what a rising edge in the ephys file means — so it is
  written to every trial record; append modes, never renumber them. The session barcode
  (`lum.sync.barcode`, D7) is sent once, by `devices.flex.sendBarcode`, as its own state machine
  before the runner is created. Its markers carry the session type: `MarkerWidth` for behaviour,
  `SleepMarkerWidth` for sleep. `hardware/TestSyncLine.m` drives the line both ways outside a
  session, for the operator to scope.
- **Determinism**: anything that must be sub-millisecond accurate lives in the state machine
  or PulsePal, not in MATLAB loop code.

## Code map

The protocol file is a thin session script; everything with logic in it lives in `+lum`,
where it can be tested with no hardware.

| Path | What it owns |
|---|---|
| `LuminoseFM.m` | Session sequence: session type, set up, barcode, trial loop, tear down. Nothing else. |
| `hardware/RigConfig.m` | The channel map and the connected machine's live limits |
| `hardware/CheckRig.m` | Preflight report |
| `hardware/TestHiFiSound.m` | Play a test sound outside a session |
| `hardware/TestSyncLine.m` | Drive the sync TTL outside a session, from states and from a global timer |
| `hardware/TestHouseLight.m` | Switch the house light through PulsePal outside a session and check each switch reaches BNC input 1 |
| `hardware/TestDoricLED.m` | Light A, then B, then both, through Bpod BNC → PulsePal → Doric driver, at one or more currents |
| `+lum/+led/` | Light paths (`lightPath`), calibrations (`makeCalibration`, `saveCalibration`, `loadCalibration`, `calibrations`, `calibrationFile`, `calibrationFolder`, `plotCalibration`), conversions (`irradiance`, `current`, `toUnit`, `fromUnit`, `describe`), `validate`, `sessionRecord` |
| `+lum/+ephys/` | ePhys calibration: `plan`, `validate`, `describe` |
| `+lum/defaultSettings.m`, `mergeSettings.m` | The two-tier settings struct; old settings files converted (renames, reshapes, retirements) |
| `+lum/validateSettings.m` | Everything that must hold before a session starts; returns the stimulus set |
| `+lum/stageDefaults.m` | The session a training stage assumes: habituation is air and no light; shaping on in habituation and training |
| `+lum/timerBudget.m` | Global timers left for light after sync, hold clock and timed components |
| `+lum/buildTrialSM.m` | The state graph (fixed names; outputs, timers and transitions vary) |
| `+lum/cueTiming.m` | What each cue component does once the stimulus starts: continues, off, or timed (D12) |
| `+lum/nextTrialSpec.m` | Trial policy: follow the order, run limit and bias correction by swapping, stage, hold |
| `+lum/HoldShaping.m` | Automatic shaping of the centre hold: active mode, next hold and grace, step back after early withdrawals, description; break modes (restart or end) |
| `+lum/triggerStates.m` | The states that open the prepare window, by break mode |
| `+lum/scoreTrial.m` | Outcome classification from states and events, including hold breaks and attempts |
| `+lum/punishmentFor.m` | Which mistakes are punished, and how; whether a wrong choice may be retried |
| `+lum/SyncMode.m` | How trials drive the sync TTL; codes are part of the data format |
| `+lum/SessionRunner.m` | TrialManager on the rig, blocking in the emulator (D3) |
| `+lum/OnlinePlots.m` | The behaviour session's live figure: now and next, outcomes; performance, psychometric, evidence (u_A vs u_B: fraction of the window each channel is lit); by side, side bias, reaction time, centre hold (time in the port vs asked for); header: water (side and centre) and the running hold |
| `+lum/loadSounds.m` | The session's sounds, loaded once |
| `+lum/testSounds.m`, `toneFrequencies.m` | A session sound as `TestHiFiSound` arguments, for the Play buttons; group tone spacing |
| `+lum/fiberBundles.m`, `experimentChoices.m` | Bundle cables and spot counts; the Experiment tab's lists |
| `+lum/mergeActions.m`, `timerMaskAction.m` | Output-action assembly; see the gotchas below |
| `+lum/launchSubject.m` | The subject the session was launched for, from wherever Bpod kept it |
| `+lum/trainingStageNote.m` | One line saying what the training stage does to rewards |
| `+lum/+pattern/` | `generate` (families, groups, order) → `stimulusSet` (segments, contingency, checks) → `patternAt`; `fromStates`, `canonicalise`, `check`, `validate`, `describe`; `families`, `withGeneratorDefaults`, `defaultPLeft`, `newSeed`, `prepareSeed` |
| `+lum/+stim/` | Components: `OptoPattern`, `TimedOutput` → `PortLight`, `Air`; `Sound`; `CueTone`; `build`; `isTimed`, `timerCost` |
| `+lum/+sync/` | Session barcode: `barcode` (kinds), `markerWidth`, `barcodeKinds`, `sleepMarkerWidth`, `barcodeValue`, `barcodeTime`, `decodeBarcode`, `barcodeStateMachine`; `fitToCameras` (widths the cameras can read) |
| `+lum/+sleep/` | Sleep and ePhys calibration sessions: `run`; sync pulses `pulseSchedule`, `syncPulseTimes`; test pulses `testPulsePlan`, `stepChoices`, `epochShape`, `describeTestPulses`, `describeTrain`; blocks `nextBlock`, `blockStateMachine`; `validate`, `validateClock`, `checkTimeline`, `validateTestPulses`, `deviceSettings`; `Plots` |
| `+lum/+dev/` | Device shims, real and null; `open.m` selects them. `DoricLED`, chosen by `openDoricLED`: the LED driver through DoricLED, both channels in external TTL mode, currents changed between trials or blocks (D17). `HouseLight`/`RealHouseLight`/`NullHouseLight`/`DisabledHouseLight`, chosen by `openHouseLight`: the house light on PulsePal OUT3, switched at once, its level per trial and edges read from the BNC1 loopback (D15). `PulsePal.holdVoltage` holds an untriggered output, guarded against a click mid-command. `Cameras`/`RealCameras`/`NullCameras`, `openCameras`, `configureCameras`: video through SpinCam (D14). `openPulsePal` refuses a light session without PulsePal, stops its outputs on connecting and requires a handshake (`PulsePal.checkConnection`). `Flex` also sends the barcode, opens the analog viewer and realigns the analog stream (`alignAnalog`) |
| `+lum/+gui/` | `SessionTypeDialog`, `SetupDialog`, `SleepSetupDialog`, `EphysSetupDialog`, `DoricSetup` (Doric LED tab), `DoricCalibration`, `DoricWindow` (LED window), `IntensityField`, `CameraSetup` (Cameras tab, live preview), `CameraWindow` (during sessions), `HelpLine`, `ExperimentForm`, `Form`, `StimulusDesigner`, `TestPulseDesigner`, `RuntimeWindow`, `PatternBrowser`, `savePlotsImage`, `houseLightSwitch`, `drawTrialFlow`, `drawTestPulseSchedule`, `drawTestPulseEpoch`, `runtimeFields`, `relabelParameterGUI`, `parseNumbers`, `theme`, `logo` |
| `tests/` | `runLuminoseTests` runs everything; `StubHiFi`, `StubPulsePal` (a PulsePal that can stop answering) and `StubCameraManager` (SpinCam's manager, no cameras) are test doubles; DoricLED's own `SimulatedTransport` is the LED's; `startMouse` plays scripted pokes into an emulated state machine; see below |

**Bpod gotchas that have already cost time.** Each is guarded in code; don't undo them.

- **Output actions are not sticky.** Bpod writes every output channel from the entered state's
  own row, so a line a state drove high goes low on the next state unless that state drives it
  high too. This is what made the trial sync pulse invisible for three releases (D4): a global
  timer set Flex2DO high on entering `TrialStart`, whose timer was 0, and `WaitForCentrePoke`
  wrote it low one 100 us cycle later. Bpod's own example protocols repeat `stimulusOutput` in
  consecutive states for the same reason, and `SetGlobalTimer`'s help says "State output events
  can still manipulate the linked channel while the timer is running". Serial (module) channels
  are the exception: no action in a row means nothing is sent, so a sound plays on. The other
  exception is an **overridden** BNC/Wire/PWM/valve line — linked to a running global timer, or
  set by the output override command — which firmware 23 skips on state entry (it does not
  skip Flex lines, hence D4). Every override is cleared when a state machine ends. The firmware
  source is sanworks/Bpod_StateMachine_Firmware tag v23, `setStateOutputs`, `setGlobalTimerChannel`,
  `resetOutputs` and the `'O'` command. (0.6.1 first held the house light on `PWM5` this way; D15
  explains why it moved to PulsePal.)
- **`RunStateMachine` leaves `Status.BeingUsed` at 1** when it runs outside a protocol, so the next
  rig utility refuses ("A protocol is running"). `TestHouseLight` and `TestSyncLine` restore
  `BeingUsed` and `InStateMatrix`; a new utility that runs a state machine must do the same.
- **The subject is not always in `Status.CurrentSubjectName`.** The launch manager sets it only
  when the subject list's selection changes; its Launch button sets `GUIData.SubjectName` every
  time. Use `lum.launchSubject`.
- `AddState` rejects a repeated output channel in one state, so lists that switch something
  off and something else on must go through `lum.mergeActions` first. Timer trigger and
  cancel masks from several components are built once by `buildTrialSM`, never merged — a
  second `GlobalTimerTrig` in one state would overwrite the first.
- `AddState` treats a one-character `GlobalTimerTrig`/`GlobalTimerCancel` value as a legacy
  timer *index*, evaluating `2^(value-1)` on the character: `'1'` becomes 2^48. Build masks
  with `lum.timerMaskAction`, which pads to two digits.
- `SetGlobalTimer` reads its optional arguments **by position**, not by name: pass
  `'Duration', 'OnsetDelay', 'Channel', 'OnMessage'` in that order. On a PWM channel
  `OnMessage` is the brightness (0 would light nothing) — Bpod's own
  `GlobalTimerExample_PWM.m` passes it under another name in that slot. Confirm on the rig.
- Transitions on a global timer ending live in `sma.GlobalTimerEndMatrix(state, timer)`, and
  on conditions in `sma.ConditionMatrix(state, condition)`, not in `InputMatrix`.
- `RunProtocol('Stop')` removes the protocol folder from the MATLAB path. Nothing needing
  `+lum` may run after it, object destructors included — release devices, close the runtime
  window and clear handles first, as `LuminoseFM` does.
- **The console's End button runs `RunProtocol('Stop')` *before* the protocol's teardown**, from its
  callback while the loop waits: it closes every figure in `BpodSystem.ProtocolFigures` and clears
  `BpodSystem.Path.Settings`. The teardown still resolves `+lum` only because the launch manager
  runs the protocol with MATLAB's `run`, which makes the repository the current folder until the
  protocol returns (a function removed from the path is otherwise gone, loaded or not). Hence the
  plot figures' `CloseRequestFcn` only hides them (their `close()` deletes), and the settings file
  is captured before the loop, not read from `Path.Settings` at teardown (D16).
- `ProgramPulsePalParam`'s header says trigger mode `1/2/3`; the firmware uses `0/1/2`, and
  the function sends the value unchanged. Gated is **2** (`lum.dev.PulsePal.GatedTriggerMode`).
- **A light session must never run with PulsePal unprogrammed.** Bpod gates BNC1/BNC2 anyway,
  and PulsePal answers with its last program (edge trigger, train delay, both LEDs on one input,
  continuous loop). The session file then looks perfect while the LEDs fire at the wrong times.
  `lum.dev.openPulsePal` refuses to start instead of falling back to the null shim, and stops
  every output (`stopOutputs`) on connecting. Do not reintroduce a fallback. Since the house light
  moved to PulsePal (D15), a session without light also opens it, but runs without it — and
  without the house light — rather than refusing.
- PulsePal's own connection code: `PulsePal()` only prints "already open" and returns when a
  `PulsePalSystem` is left in the base workspace, even a dead one. Its scan lists only free
  ports, so a port a previous session did not release is never found, and it writes a handshake
  to every free COM port it tries. `PulsePalSystem` is a `PulsePalObject`, so `isfield` on it is
  always false. `ProgramPulsePalParam` returns `[]` on a timeout, and `[] ~= 1` is false: compare
  with `isequal`. `lum.dev.RealPulsePal` handles all of these. `SetPulsePalVersion`, the
  handshake behind `checkConnection`, pauses 0.1 s: call it between blocks or trials, never in a
  loop. A house light click can run inside that pause — the reason for the command guard in
  `lum.dev.PulsePal` (D15).
- PulsePal firmware v21 **does not change an output on its resting voltage alone**: parameter 17
  stores it and calls `dacWrite()` without setting that output's `DACFlags`, so the DAC is untouched
  until a stop or abort kills the channel. `SetPulsePalVoltage` (op 79) does write, but alone it is
  lost at the next stop, abort or disconnect (`killChannel` returns to the resting voltage). So
  `holdVoltage` sends both, parameter 17 then op 79 (found on the rig 2026-09-21: until then the
  house light never switched on). `NullPulsePal` logs op 79 as `would write ch3 output = 5 V`.
- A sleep session with test pulses must **never** cut a block inside an epoch or put two steps'
  light in one block: Bpod drops every line at the end of a state machine, so a gate split across
  runs becomes two gates with an upload between them, and PulsePal is only reprogrammed between
  runs. `lum.sleep.nextBlock` guards both; `lum.sleep.validateTestPulses` guarantees a safe cut
  exists.
- `RunStateMachine` starts the Flex analog stream on the session's **first run**, but
  `AddFlexIOAnalogData` stamps the stream from `TrialStartTimestamp(1)`, so a run before trial 1
  (the barcode) shifts every analog timestamp by its length and every `TrialNumber` by one.
  `lum.dev.Flex.alignAnalog` corrects it. `AddFlexIOAnalogData(data, 'Volts', 0)` also *adds* the
  trial-aligned copy (it reads the first option as that flag): pass `'Volts'` alone.
- `BpodHiFi.load` reads `'LoopMode', 'LoopDuration'` by position too; `lum.dev.RealHiFi` passes
  them in that order. The cue tone loops for up to the hold window's upper limit.
- The Chameleon3 quantizes `AcquisitionFrameRate`, and writing a read-back value lands one step
  higher (100.058 → 100.12). Keep what the operator typed: `CameraSetup` takes a frame rate back
  from SpinCam's viewer only when it differs by more than 0.2 Hz, rounded to 0.1 Hz.
- SpinVideo MJPEG (`avi-mjpeg`) encodes one frame at a time at ≈ 104 fps per full frame. At the
  100 Hz default a session with the camera window open grew its writer queue 1–2 frames/s (writer
  drops after ~15 min), though a bare recording stayed flat. Record `avi-mjpeg-mt`; a queue peak in
  `Session.Cameras.Summary.Cameras(k).QueuePeak` in the hundreds means the encoder fell behind.
- **A test must start the emulator before anything reaches `lum.dev.open`.** Without a
  `BpodSystem`, `open` takes the rig path, and `lum.dev.openDoricLED` connects to the **real Doric
  driver** through the bridge (a test once did). Call `ensureEmulator()` first.
- MATLAB resolves a package function from the **current folder** before the path, so a copy of a
  `+lum` file on the path does not override the repository's while MATLAB's current folder is the
  repository (it cost a diagnostic run: a scratch opener meant to force real cameras was ignored).
- A `GlobalTimer<k>_Start` / `_End` pair in the trial record proves the *timer* ran, not that
  the *channel* moved. If a line is dead while its timer's events are there, look for a state
  that writes the same channel, not at the timer.
- Before blaming the stimulus path for "late" light or air, look at the session file: the
  `GlobalTimer<k>_Start/_End` events against `CentreHold`, the PulsePal device log, and the flow
  meter aligned to the valve (the 0.2 "air arrives at the reward port" report was the analog
  shift above, not the stimulus). The PulsePal log's first line says whether PulsePal was
  connected at all. The 0.4 report of light pulses "at the side pokes" came from rig sessions
  whose light timers all started on the poke (39 of 39 across 0.2–0.4), while PulsePal was not
  connected in 13 of 16 of them.

## Tests

```bash
# whole suite, from WSL; no hardware touched
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch \
  "cd('/path/to/LuminoseFM'); addpath('tests'); runLuminoseTests"

# one file
... "runLuminoseTests('Filter', {'generateTest'})"
```

The suite **refuses to run against a real state machine** and starts `Bpod('EMU')` itself
for the tests that need one. `lintTest` keeps the repository at zero Code Analyzer
messages — MATLAB has no compile step, so that is the closest thing to one. Add a test with
any behaviour change; the pure functions (`+lum/*.m`, `+lum/+pattern/`, `+lum/+sync/`) are
the cheap place to do it. `windowsTest` builds windows invisibly (`'Visible', 'off'`, and
`'Wait', false` for the modal ones) and skips the uifigure tests where MATLAB cannot make one.
`emulatorSessionTest` runs a whole behaviour session headless, `habituationSessionTest` a
habituation session with one trial played as the animal (centre reward; valve 2 is not calibrated on
this machine, so it checks the fallback), `sleepSessionTest` two sleep
sessions, with and without test pulses, and `ephysSessionTest` an ePhys calibration session — all
with video and the LED window off. `ledTest` (pure), `doricTest` (the LED on DoricLED's simulated
driver, and `TestDoricLED` under the emulator) and `ephysTest` (pure) cover D17 and D18; the Doric
and ePhys session tests are skipped without the DoricLED package. `cameraTest` covers video against
`StubCameraManager` and runs a behaviour and a sleep session with SpinCam's simulated cameras
(skipped without SpinCam). `stateMachineTest` plays whole trials as the animal with `startMouse`
(scripted `'V'` override bytes from a timer, a few hundred ms apart, never `ManualOverride`): use it
for anything that depends on pokes.

MATLAB and test gotchas that have already cost time:

- `functiontests` takes **every** local function whose name starts with `test` as a test, so a
  helper called `testPulses()` breaks the whole file. Name helpers otherwise.
- A `uitable`'s `Enable` wants `'on'`/`'off'` text, not the `OnOffSwitchState` that
  `lum.gui.Form.onOff` returns for other components.
- An invisible uifigure lays a newly selected tab out some time later: `getpixelposition` of its
  components reads the default 100 × 22 until then. Wait (drawnow and pause) before testing positions.
- The saved MATLAB path on this machine includes SpinCam, so a `-batch` session run with
  `S.Camera.Enabled` records simulated video; turn it off in tests that are not about video.
- **A new uifigure waits for its view before it is filled** (`lum.gui.Form.waitForView(fig)`, straight
  after `uifigure(...)`, in every window). In a desktop MATLAB (R2025b), a window whose web view finished
  loading while components were still being added sometimes never confirmed the next update: it stayed as
  first drawn, and the next `drawnow` or `uiwait` in that MATLAB never returned. The behaviour setup dialog
  did this in more than half of desktop launches (2026-09-21); the operator saw a dialog that did not update
  and a MATLAB that hung at the next window. `-batch` runs and invisible windows never show it, so the test
  suite cannot; check a new window from a desktop MATLAB.
- `exportgraphics` refuses a classic figure holding more than one `uipanel`, and `print` refuses
  any figure with UI components (both plot figures have both). `exportapp` captures them, and the
  uifigure windows, headless under `-batch`.

## Docs rule

Keep documentation current in the same change that alters behaviour:

- `README.md` — the operator's guide only: running a session, the task, the stimulus, the
  windows, the plots, sleep sessions, utilities. It links to `docs/` for everything else, so
  reference material added there does not go back into it.
- `docs/hardware.md` — the box, the channel map, the light path, Flex I/O, the cameras, the environment.
- `docs/data-format.md` — the session file's every field, and reading older files.
- `docs/sync-and-barcode.md` — the sync TTL and the session barcode.
- `docs/naming-and-versions.md` — the glossary, and what changed between versions.
- `docs/emulator.md` — what the emulator does and does not reproduce.
- `docs/rig-checks.md` — what has been checked on the rig, with session names, and the checks
  pending until the operator is at the rig.
- `docs/repository.md` — the repository layout and what the test suite covers.
- `CLAUDE.md` (= `AGENTS.md`) — anything an agent needs: paths, conventions, hardware map,
  naming, new APIs or architectural decisions.
- `docs/architecture.md` — the confirmed architecture decisions (D1 envelope/carrier split,
  D2 two-tier GUI, D3 runner, D4 sync, D5 stimulus set, D6 hold shaping, D7 barcode,
  D8 naming, D9 timed components, D10 restarting holds and the hold window, D11 behaviour and
  sleep sessions, D12 the cue until the stimulus starts, and its latency, D13 test pulses in
  sleep sessions, D14 video through SpinCam, D15 the house light on PulsePal, looped back into Bpod, D16 the plots
  image and settings kept at teardown, D17 the Doric LED sets the intensity, D18 ePhys calibration
  sessions, D19 the centre reward and the retry after an unpunished incorrect choice). Read it before changing the stimulus path, the state graph, sleep blocks or
  the GUI.
- `docs/` — rig drawings, `BpodSystemInfo.png`, logo.

If you change a public helper's signature, the state-machine flow, the data schema, the
GUI parameter set, or the hardware map, update the affected doc in the same commit. If a
doc statement turns out to be wrong, fix the doc — don't leave it for later.

**Writing.** State facts plainly, for an operator and a developer who want to use or change the
code. No emphasis for its own sake, no reassurance, no lecturing (for example, not "This is not
superstition, and it is not optional"). Say what happens, what to do, and why when the why helps.

## Git

- Branch `main`, remote `SainsburyWellcomeCentre/LuminoseFM`.
- Commit only when asked. Don't commit session data, `.asv` files, `Bpod Local` state, or
  `calibration/` (rig-local LED calibrations; git-ignored).
