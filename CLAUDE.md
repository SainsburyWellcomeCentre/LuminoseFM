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
| Bpod `ProtocolFolder` | `C:\Users\harrislab\Documents\MATLAB\HarrisLabBpodProtocols\` |
| Bpod `DataFolder` | `D:\luminoseData\` = `/mnt/d/luminoseData` — session data live **outside** the repo |

Agents run in WSL; MATLAB and all hardware are on Windows.

```bash
# headless MATLAB from WSL — use for syntax checks and hardware-free unit tests
"/mnt/c/Program Files/MATLAB/R2025b/bin/matlab.exe" -batch "checkcode('LuminoseFM.m')"
```

Never open COM ports, call `Bpod`, `PulsePal`, or run the protocol against real hardware
from an agent session — the rig may be running an animal. Use `Bpod('EMU')` (emulator) or
pure-function tests instead, and hand hardware runs to the operator.

## Stay inside the working folder

**Only create, edit or delete files inside this repository** — the `LuminoseFM` folder that
contains this file. Everything else on the machine is off limits for writes, including
`Bpod_Gen2/`, `Bpod Local/` (settings and calibration), `PulsePal/`, the data folder, and
MATLAB's own path/startup files. Reading them is fine and encouraged.

The absolute paths in the table above describe *this* machine; `LuminoseFM` sits elsewhere
on other setups, so resolve the repo root from the location of the file you are editing
(or `fileparts(mfilename('fullpath'))` in MATLAB) rather than hard-coding them.

When something outside the repo genuinely has to change — Flex I/O configuration, the
MATLAB path, a Bpod setting, a calibration file — do not change it. Tell the operator
exactly what to change and where, and let them do it.

## Emulator mode is a first-class requirement

The protocol must run end to end under `Bpod('EMU')` on a machine with no hardware, with
working GUI, plots and data saving. Every hardware-touching call is guarded by
`BpodSystem.EmulatorMode` and falls back to a no-op shim that logs what it would have done.
Emulator limits to design around:

- `BpodSystem.assertModule` **errors** in EMU (only onboard FSM channels are emulated), so
  it must be inside the guard — same for `BpodHiFi`, any `HiFi1` output action, and every
  PulsePal call.
- Flex I/O is not emulated: no `Flex1` analog stream, no `Flex2DO` output.
- Global timers **are** emulated (trigger, onset delay, duration, channel), but
  `LoopMode` is **not** — a looping timer fires once and never repeats
  (`RunBpodEmulator.m`). Never put stimulus structure in a looping timer; see D1.
- Emulated sessions still write a complete data file, flagged as emulated
  (`Data.Info.EmulatorMode = 1`) so it can never be mistaken for real behaviour.

## Data

- Session file: `D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.mat`,
  containing one variable `SessionData` (= `BpodSystem.Data`), written by
  `SaveBpodSessionData` (full overwrite each call — keep the struct small, save on an
  interval, never inside the stimulus-critical window).
- Settings file: `.../LuminoseFM/Session Settings/<name>.mat`, per subject, chosen in the
  launch manager.
- Flex analog stream: Bpod writes `..._ANLG.dat` beside the session file; merge post-session
  with `AddFlexIOAnalogData`.
- Store session-level things (settings, pattern/stimulus dictionary, rig config, metadata)
  **once**; per-trial records hold only events, timestamps, outcome and indices into them.

## Hardware map (Bpod FSM r2+, firmware 23, FSM `COM3`, App `COM4`)

- Behavior ports: 1 = Left, 2 = Centre, 3 = Right, 4 = Air valve, 5 = House light.
  Port `n` → `PWMn` (LED), `Valven` (solenoid), `PortnIn`/`PortnOut` (IR gate).
  Ports 4 and 5 use the valve/LED line only; their IR gates are unused.
- `BNC1` → PulsePal `IN1` → PulsePal `OUT1` → Doric LED ch1 → optical pattern 1.
  `BNC2` → PulsePal `IN2` → `OUT2` → LED ch2 → pattern 2. A "pattern" is the
  spatiotemporal ON/OFF sequence of BNC1/BNC2 during the stimulus window.
- Flex I/O (`Bpod Local/Settings/FlexConfig.mat`, `channelTypes = [2 4 4 4]`):
  Flex1 = **analog input** (flow meter, 1 kHz) — already configured; Flex2 = sync TTL
  digital output — **not yet configured** (set it in the Bpod console before `Flex2DO`
  exists as a channel name); Flex3-4 disabled. Note `docs/BpodSystemInfo.png` predates the
  Flex1 config, so trust `FlexConfig.mat` where they disagree.
- Modules: `HiFi1` (Module#1, USB `COM8`) → amplifier → speaker. Modules 2/3 unregistered.
- Budget: 16 global timers, 8 global counters, 16 conditions.
- `docs/BpodSystemInfo.png` is the authoritative event/output list. Regenerate it
  (`BpodSystem.StateMachineInfo`) if the rig wiring or Flex config changes.

## Conventions

- **Entry point**: `LuminoseFM.m` in the repo root. Bpod's launch manager requires
  `<ProtocolFolder>/<Name>/<Name>.m`, so the filename must match the folder name
  `LuminoseFM` exactly (case included). Helpers go in subfolders, never nested protocols.
- **Namespacing**: put reusable code in a MATLAB package (`+lum/...`) or clearly named
  helper folders; the protocol file stays a thin session script. `hardware/` holds rig
  utilities usable outside a session (e.g. `TestHiFiSound.m`, which plays a test sound
  through the HiFi module — the one thing the Bpod console cannot test by hand).
- **Style**: 4-space indent, `camelCase` locals, `PascalCase` classes, `snake`-free names.
  Follow Bpod idiom over general MATLAB idiom: `global BpodSystem`, settings struct `S`,
  `S.GUI.*` / `S.GUIMeta.*` / `S.GUITabs.*` for the parameter GUI, `SaveBpodSessionData`.
- **Real-time first.** This is the hard constraint of the project:
  - Use `BpodTrialManager`; build and `SendStateMachine(..., 'RunASAP')` for trial *n+1*
    while trial *n* runs. All per-trial work belongs in that window.
  - Preallocate; never grow arrays, structs or plot data inside the trial loop.
  - No `figure`, `plot`, `cla` or bare `drawnow` in the loop — update existing handles
    (`set(h,'YData',...)`) and use `drawnow limitrate` at most once per trial.
  - Keep per-trial cost O(1): maintain running stats, don't re-scan `BpodSystem.Data`.
  - Don't store large per-trial copies (e.g. full pattern arrays in `Data.TrialSettings`);
    store a session-level dictionary plus per-trial indices/deltas.
  - Reprogram PulsePal / HiFi during the inter-trial window, never mid-stimulus.
- **Trial-flow contract**: state names stay fixed across stimulus modalities
  (cue / centre poke / hold / response / reward / punish / ITI); modality changes only the
  `OutputActions`. Plots, analysis, and `LiveOutcomePlot` config depend on this.
- **Determinism**: anything that must be sub-millisecond accurate lives in the state
  machine or PulsePal, not in MATLAB loop code.

## Docs rule

Keep documentation current in the same change that alters behaviour:

- `README.md` — hardware, wiring, task description, user-facing workflow.
- `CLAUDE.md` (= `AGENTS.md`) — anything an agent needs: paths, conventions, hardware map,
  new APIs or architectural decisions.
- `docs/architecture.md` — the phased design plan and the confirmed architecture
  decisions (D1: Bpod pattern envelope + PulsePal gated carrier; D2: two-tier GUI).
  Read it before changing the stimulus path, the state graph or the GUI.
- `docs/` — rig drawings, `BpodSystemInfo.png`.

If you change a public helper's signature, the state-machine flow, the data schema, the
GUI parameter set, or the hardware map, update the affected doc in the same commit. If a
doc statement turns out to be wrong, fix the doc — don't leave it for later.

## Git

- Branch `main`, remote `SainsburyWellcomeCentre/LuminoseFM`.
- Commit only when asked. Don't commit session data, `.asv` files, or `Bpod Local` state.
