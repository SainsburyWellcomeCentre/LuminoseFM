# LuminoseFM — Agent Instructions

Bpod protocol + helpers for a freely-moving 2-AFC olfactory-bulb optogenetics task
(OSN-ChR mice, patterned light via fiber bundle). See `README.md` for the scientific
and hardware description — read it before changing anything.

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

Never open COM ports, call `Bpod`, `PulsePal`, or run the protocol against real hardware
from an agent session — the rig may be running an animal. Use `Bpod('EMU')` (emulator) or
pure-function tests instead, and hand hardware runs to the operator.

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
`BpodSystem.EmulatorMode`; it builds real or null device shims once at startup, and every
null shim logs what it would have done into `Data.Session.DeviceLog`. Anything else that
behaves differently in the emulator is told so via `devices.emulated` — the runtime window
choice in `LuminoseFM.m` is the example.

**The emulator is not this rig.** `Bpod('EMU')` emulates a state machine **r0.7-1.0**, not
the r2+. Design around this:

- **5 global timers, 5 counters, 5 conditions** — against the rig's 16/8/16. Always read
  `rig.Limits.GlobalTimers` from `RigConfig`; never hard-code 16. The trial uses conditions
  1–4 (left, right, centre port clear; hold window over) and always one timer for the hold
  window, so the emulator has four left for light — fewer when a cue light or cue air goes off
  part way through the stimulus, which takes one each.
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
  launch manager. `lum.mergeSettings` converts old files (renames, reshapes, retirements).
- `Data.Session.Type` is `'Behaviour'` or `'Sleep'`. Sleep sessions store `Data.SyncPulses`
  (`Onset`, `Width`, `Block`) instead of trial series; each pulse block is one Bpod trial.
- Flex analog stream: Bpod writes `..._ANLG.dat` beside the session file; merged at teardown
  with `AddFlexIOAnalogData` through `lum.dev.Flex.mergeAnalogData`, which then re-anchors it with
  `lum.dev.Flex.alignAnalog`: the stream starts with the barcode's run, which Bpod counts as a
  trial and does not allow for (D7). Any new state machine run before trial 1 must go through the
  Flex shim so `RunsBeforeTrials` stays right.
- Store session-level things (settings, stimulus set, rig config, barcode, metadata)
  **once** in `Data.Session`; per-trial records hold only events, timestamps, outcome and
  indices into them (`PatternIndex` into `Session.StimulusSet`). Strip `States` from the
  stimulus set before storing it — segments are enough.
- Per-trial series are listed once, in `trialSeriesNames` in `LuminoseFM.m`; the README and
  `emulatorSessionTest` list them too — keep all three in step.

## Hardware map (Bpod FSM r2+, firmware 23, FSM `COM3`, App `COM4`)

- Behavior ports: 1 = Left, 2 = Centre, 3 = Right, 4 = Air valve, 5 = House light.
  Port `n` → `PWMn` (LED), `Valven` (solenoid), `PortnIn`/`PortnOut` (IR gate).
  Ports 4 and 5 use the valve/LED line only; their IR gates are unused.
- Optical channels **A** and **B**: `BNC1` → PulsePal `IN1` → `OUT1` → Doric LED ch1 is
  channel A; `BNC2` → `IN2` → `OUT2` → LED ch2 is channel B (`rig.Opto.Channels`,
  `rig.Opto.Labels`). A light pattern is the ON/OFF sequence of A and B over the stimulus
  window.
- Fiber bundles (`lum.fiberBundles`): 2-to-19 (ch1 fiber 10 spots on A, ch2 fiber 9 on B);
  4-to-19 with cables black (4 spots), blue, orange, green (5 each), any two on A and B,
  recorded in `S.Light.Cables`. The drawing colours orange red.
- Flex I/O (`Bpod Local/Settings/FlexConfig.mat`, `channelTypes = [2 4 4 4]`):
  Flex1 = **analog input** (flow meter, 1 kHz) — already configured; Flex2 = sync TTL
  digital output (barcode and trial pulses) — **not yet configured** (set it in the Bpod
  console before `Flex2DO` exists as a channel name); Flex3-4 disabled. Note
  `docs/BpodSystemInfo.png` predates the Flex1 config, so trust `FlexConfig.mat` where
  they disagree.
- Modules: `HiFi1` (Module#1, USB `COM8`) → amplifier → speaker. Modules 2/3 unregistered.
- Budget: 16 global timers, 8 global counters, 16 conditions **on the rig**; the emulator
  has 5/5/5. Read `rig.Limits` rather than assuming either. The hold window always takes one
  timer (`lum.timerBudget`).
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
| session type | `'Behaviour'` or `'Sleep'` (`S.Session.Type`, `Data.Session.Type`) | protocol, mode |
| carrier | PulsePal per-channel frequency, pulse width, voltage | waveform |
| centre | British spelling in identifiers too (`CentreHold`) | `Center` |

Version 0.2 renamed states, data fields and settings accordingly; the full table is in
`README.md` §5 and `docs/architecture.md` D8. **Rename by migration**: add the old → new
path to the rename table in `lum.mergeSettings` so existing settings files keep their
values, and never renumber a stored code (`lum.Outcome`, `lum.SyncMode`, punishment codes).

## Conventions

- **Entry point**: `LuminoseFM.m` in the repo root. Bpod's launch manager requires
  `<ProtocolFolder>/<Name>/<Name>.m`, so the filename must match the folder name
  `LuminoseFM` exactly (case included). Helpers go in subfolders, never nested protocols.
- **Two session types, one protocol (D11).** `LuminoseFM` opens `lum.gui.SessionTypeDialog`
  first; *Sleep* hands the whole session to `lum.sleep.run`, which must release every `lum.*`
  object before returning. Headless runs (`setappdata(0, 'LuminoseFM_Headless', true)`) take the
  type from `S.Session.Type`. Sleep sessions run pulse blocks with blocking `RunStateMachine`
  on the rig too — they have nothing to prepare, so `SessionRunner` does not apply. Both setup
  dialogs build `S.Meta` through `lum.gui.ExperimentForm`; add an experiment field there once.
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
  into segments, applies `S.Task.GroupPLeft`, and refuses a pattern over the timer budget or
  identical groups paying different sides. `lum.pattern.patternAt(set, k)` recovers one
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
  / centre hold / hold break / resumed hold / centre exit / response / reward / incorrect
  choice / ITI); these change only the `OutputActions`, state timers, global timers and where a
  poke or `EarlyWithdrawal` leads. Plots, analysis and `lum.scoreTrial` depend on this. Version
  0.4 removed the `Cue`, `Cue2`… states (D12).
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
    onset, the latency, and the barcode. Global timers are for what happens inside the hold, where leaving the port
    must end it at any instant: light segments (D1), the grace hold clock (D6), stimulus
    components switched on late or off early (D9), and cue components switched off part way
    through the stimulus (D12).
  - **The HiFi module plays one sound at a time**; a new play command replaces the sound playing.
    `lum.validateSettings` refuses two sounds that start with the stimulus (`soundClash`), and
    with restarts an early-withdrawal noise is let finish before `WaitForCentrePoke` plays the
    cue tone again.
  - `HoldBreak` and `CentreHoldResumed` exist in every trial. Without grace shaping they are
    unreachable; with it, `CentreHold` triggers the stimulus timers and the hold clock, and
    `CentreHoldResumed` must **not** re-trigger them.
- **Sync TTL**: `S.Session.UseSync` says whether the line is driven, `S.Sync.Mode`
  (`lum.SyncMode`: FixedWidth, JitteredWidth, TaskEvents) says how trials drive it.
  `TaskEvents` uses no timer, driving the line high in `TrialStart` and low on the poke — in
  `PreStimulusHold`, or `CentreHold` without a latency — and in `NoInitiation`. The mode is part of the data format — it decides what
  a rising edge in the ephys file means — so it is written to every trial record; append
  modes, never renumber them. The session barcode (`lum.sync.barcode`, D7) is sent once, by
  `devices.flex.sendBarcode`, as its own state machine before the runner is created. Its
  markers carry the session type: `MarkerWidth` for behaviour, `SleepMarkerWidth` for sleep.
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
| `+lum/defaultSettings.m`, `mergeSettings.m` | The two-tier settings struct; old settings files converted (renames, reshapes, retirements) |
| `+lum/validateSettings.m` | Everything that must hold before a session starts; returns the stimulus set |
| `+lum/timerBudget.m` | Global timers left for light after sync, hold clock and timed components |
| `+lum/buildTrialSM.m` | The state graph (fixed names; outputs, timers and transitions vary) |
| `+lum/cueTiming.m` | What each cue component does once the stimulus starts: continues, off, or timed (D12) |
| `+lum/nextTrialSpec.m` | Trial policy: follow the order, run limit and bias correction by swapping, stage, hold |
| `+lum/HoldShaping.m` | Centre-hold shaping: modes, next hold and grace, description; break modes (restart or end) |
| `+lum/triggerStates.m` | The states that open the prepare window, by break mode |
| `+lum/scoreTrial.m` | Outcome classification from states and events, including hold breaks and attempts |
| `+lum/punishmentFor.m` | Which mistakes are punished, and how |
| `+lum/SyncMode.m` | How trials drive the sync TTL; codes are part of the data format |
| `+lum/SessionRunner.m` | TrialManager on the rig, blocking in the emulator (D3) |
| `+lum/OnlinePlots.m` | The single live figure |
| `+lum/loadSounds.m` | The session's sounds, loaded once |
| `+lum/fiberBundles.m`, `experimentChoices.m` | Bundle cables and spot counts; the Experiment tab's lists |
| `+lum/mergeActions.m`, `timerMaskAction.m` | Output-action assembly; see the gotchas below |
| `+lum/trainingStageNote.m` | One line saying what the training stage does to rewards |
| `+lum/+pattern/` | `generate` (families, groups, order) → `stimulusSet` (segments, contingency, checks) → `patternAt`; `fromStates`, `canonicalise`, `check`, `validate`, `describe`; `families`, `withGeneratorDefaults`, `defaultPLeft`, `newSeed`, `prepareSeed` |
| `+lum/+stim/` | Components: `OptoPattern`, `TimedOutput` → `PortLight`, `Air`; `Sound`; `CueTone`; `build`; `isTimed`, `timerCost` |
| `+lum/+sync/` | Session barcode: `barcode` (kinds), `sleepMarkerWidth`, `barcodeValue`, `barcodeTime`, `decodeBarcode`, `barcodeStateMachine` |
| `+lum/+sleep/` | Sleep sessions: `run`, `pulseSchedule`, `pulsesPerBlock`, `blockStateMachine`, `validate`, `Plots` |
| `+lum/+dev/` | Device shims, real and null; `open.m` selects them. `Flex` also sends the barcode, opens the analog viewer and realigns the analog stream (`alignAnalog`) |
| `+lum/+gui/` | `SessionTypeDialog`, `SetupDialog`, `SleepSetupDialog`, `ExperimentForm`, `Form`, `StimulusDesigner`, `RuntimeWindow`, `PatternBrowser`, `drawTrialFlow`, `runtimeFields`, `relabelParameterGUI`, `parseNumbers`, `theme`, `logo` |
| `tests/` | `runLuminoseTests` runs everything; see below |

**Bpod gotchas that have already cost time.** Each is guarded in code; don't undo them.

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
- `ProgramPulsePalParam`'s header says trigger mode `1/2/3`; the firmware uses `0/1/2`, and
  the function sends the value unchanged. Gated is **2** (`lum.dev.PulsePal.GatedTriggerMode`).
- `RunStateMachine` starts the Flex analog stream on the session's **first run**, but
  `AddFlexIOAnalogData` stamps the stream from `TrialStartTimestamp(1)`, so a run before trial 1
  (the barcode) shifts every analog timestamp by its length and every `TrialNumber` by one.
  `lum.dev.Flex.alignAnalog` corrects it. `AddFlexIOAnalogData(data, 'Volts', 0)` also *adds* the
  trial-aligned copy (it reads the first option as that flag): pass `'Volts'` alone.
- `BpodHiFi.load` reads `'LoopMode', 'LoopDuration'` by position too; `lum.dev.RealHiFi` passes
  them in that order. The cue tone loops for up to the hold window's upper limit.
- Before blaming the stimulus path for "late" light or air, look at the session file: the
  `GlobalTimer<k>_Start/_End` events against `CentreHold`, the PulsePal device log, and the flow
  meter aligned to the valve (the 0.2 "air arrives at the reward port" report was the analog
  shift above, not the stimulus).

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
`emulatorSessionTest` and `sleepSessionTest` run a whole behaviour and sleep session headless.

## Docs rule

Keep documentation current in the same change that alters behaviour:

- `README.md` — hardware, wiring, task description, windows, data fields, names, workflow.
- `CLAUDE.md` (= `AGENTS.md`) — anything an agent needs: paths, conventions, hardware map,
  naming, new APIs or architectural decisions.
- `docs/architecture.md` — the confirmed architecture decisions (D1 envelope/carrier split,
  D2 two-tier GUI, D3 runner, D4 sync, D5 stimulus set, D6 hold shaping, D7 barcode,
  D8 naming, D9 timed components, D10 restarting holds and the hold window, D11 behaviour and
  sleep sessions, D12 the cue until the stimulus starts, and its latency). Read it before changing the stimulus path, the state graph or the GUI.
- `docs/` — rig drawings, `BpodSystemInfo.png`, logo.

If you change a public helper's signature, the state-machine flow, the data schema, the
GUI parameter set, or the hardware map, update the affected doc in the same commit. If a
doc statement turns out to be wrong, fix the doc — don't leave it for later.

## Git

- Branch `main`, remote `SainsburyWellcomeCentre/LuminoseFM`.
- Commit only when asked. Don't commit session data, `.asv` files, or `Bpod Local` state.
