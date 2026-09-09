# LuminoseFM

Bpod protocol, helper functions and utilities for a **freely-moving two-alternative
forced-choice (2-AFC)** task for the Luminose project.

The task drives a custom behaviour box with three nose ports and delivers patterned
optogenetic stimulation to the olfactory bulb of OSN-ChR mice (channelrhodopsin in
olfactory sensory neurons) through a custom fiber bundle.

---

## 1. Behaviour box

Red acrylic box, **18 × 18 × 23 cm** (w × l × h). Three behaviour ports sit at a height of
1.2 cm, spaced 6 cm centre-to-centre. The box stands on a base plate and has a cover that
lets wires pass through while making it hard for the mouse to climb out.

Drawings: [`docs/behaviour_box_design/`](docs/behaviour_box_design)

**Sleep recordings.** A red acrylic cover slots onto the home cage so that pre- or
post-behaviour sleep can be recorded without disconnecting tethered optical patch cords
and/or Neuropixels cables.

---

## 2. Hardware

The rig is controlled by a [Bpod Finite State Machine r2+](https://sanworks.github.io/Bpod_Wiki/assembly/state-machine-assembly-2%2B/),
connected to the computer over USB. The full list of channels and events is available from
`BpodSystem.StateMachineInfo`, and is captured in [`docs/BpodSystemInfo.png`](docs/BpodSystemInfo.png).

### 2.1 Behaviour ports

Each port is wired through a [port interface board](https://sanworks.github.io/Bpod_Wiki/assembly/port-breakout-board-assembly/),
which connects one infrared photogate, one LED and one solenoid valve to the state machine
over an Ethernet cable. This state machine has five behaviour ports:

| Port | Use | Photogate | LED | Valve |
|------|-----|-----------|-----|-------|
| 1 | Left port | ✔ | ✔ | ✔ (water) |
| 2 | Centre port | ✔ | ✔ | ✔ (water) |
| 3 | Right port | ✔ | ✔ | ✔ (water) |
| 4 | Air valve — switches compressed air flow | — | — | ✔ |
| 5 | House light — LED driver for the white light inside the rig, used for pre/post-behaviour sleep | — | ✔ | — |

### 2.2 Optogenetic stimulation (digital out → PulsePal → Doric LED)

The optogenetic stimulus is a **spatiotemporal pattern of 100 µm light spots** delivered to
the olfactory bulb through a custom fiber bundle
([`docs/fiber_bundle_design/`](docs/fiber_bundle_design)). Two bundle versions exist:

- **2-to-19** — ch1 and ch2 drive a 10-spot and a 9-spot pattern.
- **4-to-19** — ch1–ch4 drive 5-, 5-, 5- and 4-spot patterns. Only two channels can be
  connected to the commutator at a time, so switching to a different pair of patterns
  requires physically re-plugging the bundle.

The two active channels feed a Doric blue LED with two independently driven LED channels:

```
Bpod BNC1 → PulsePal IN1 → PulsePal OUT1 → Doric LED ch1 → optical pattern 1
Bpod BNC2 → PulsePal IN2 → PulsePal OUT2 → Doric LED ch2 → optical pattern 2
```

An optical pattern stimulus is therefore a **sequence of ON/OFF states of BNC1 and BNC2**
over the stimulus delivery period.

### 2.3 Flex I/O

The r2+ adds four Flex I/O channels, each configurable as digital output (5 V TTL), digital
input (5 V tolerant), analog input (12-bit, 0–5 V, 1 kHz) or analog output (12-bit, 0–5 V).

| Channel | Use | Configured as |
|---------|-----|---------------|
| Flex 1 | Flow meter | Analog input (currently configured, 1 kHz) |
| Flex 2 | Sync TTL | Digital output (**not yet configured**) |
| Flex 3–4 | unused | disabled |

The sync TTL is a train of pseudo-random TTL pulses sent to an externally powered,
scalable BNC splitter, and from there to the other acquisition devices (Neuropixels OneBox
or NI-1083, camera 1, camera 2, and so on).

### 2.4 Modules

Module ports are high-speed communication channels for external Bpod hardware extensions.

- **[HiFi module](https://sanworks.github.io/Bpod_Wiki/assembly/hifi-module-assembly/)** —
  connected to the state machine over Ethernet and to the computer over USB, and driving an
  amplifier card wired to a custom-made speaker.

---

## 3. Software environment

| Item | Location |
|------|----------|
| MATLAB working directory | `C:\Users\harrislab\Documents\MATLAB` |
| This project | `...\MATLAB\HarrisLabBpodProtocols\LuminoseFM` |
| Bpod protocol folder | `...\MATLAB\HarrisLabBpodProtocols\` (Bpod's `ProtocolFolder`) |
| Data folder | `D:\luminoseData\` (Bpod's `DataFolder`) |
| Bpod_Gen2, Bpod Local, PulsePal | cloned into `...\MATLAB\`; Bpod_Gen2 is on the MATLAB path, PulsePal must be added to the path before use |
| Protocol examples | `...\MATLAB\Bpod_Gen2\Examples\Protocols` |

Bpod user guide: <https://sanworks.github.io/Bpod_Wiki/user-guide/>

---

## 4. Protocol

The protocol lives as `LuminoseFM.m` in the root of this project (no nesting — Bpod's
launch manager requires the protocol file name to match its folder name). Helper functions,
classes and utilities are organised in subfolders.

### 4.1 Task structure

The protocol and its GUI should be general enough for any 2-AFC task with this schema:

```
cue → poke into centre port → wait for stimulus → hold nose poke until stimulus
delivery ends → collect reward at the correct port (left or right) → next trial
```

The rig can produce port light (LED), sound, air (centre port) and optogenetic stimuli
(BNC1/BNC2). A general workflow lets the operator pick freely among these — a stimulus may
be an optogenetic pattern, a sound, and so on.

**Performance requirement.** The task needs fast real-time control of the rig, so memory
use must be optimised to avoid lags between state transitions. This includes (but is not
limited to) using the `BpodTrialManager` object, managing static/dynamic allocation inside
the trial loop, saving data at sensible intervals, and displaying only the online plots
that are genuinely needed.

### 4.2 GUI

A proposed layout (open to alternatives — better workflows are welcome). Bpod also offers
a notebook feature for manual annotation. Tabs:

- **Experiment metadata**
- **Training** — stage (habituation, training, experiment), contingency (e.g. stimulus A →
  go left, and vice versa), bias correction
- **Cue** — light, sound and/or air, alone or in combination, each with its own parameters
- **Stimulus** — total duration, frequency (e.g. 20 Hz for ChR, or constant on), pattern 1
  and pattern 2
  - modality: LED / sound / opto pattern / air
  - PulsePal parameters
  - for patterns: A vs B; mixtures of A and B (spatiotemporal patterns with or without
    overlap, with or without `duration(A + B) ≤ duration(A) + duration(B)`); arbitrary
    sequences of A and B; possibly a graphical stimulus designer at the start of a session
- **Reward** — water delivered by opening the left or right port valve

### 4.3 Emulator mode

The protocol must run **end to end on a machine with no hardware attached** (e.g. a desk PC),
so that task logic, GUI, plots and data saving can be developed and tested offline.

- Start Bpod with `Bpod('EMU')`, or use the emulator button on the console.
- The protocol must detect `BpodSystem.EmulatorMode` and skip or stub every call that needs
  real hardware, rather than erroring out.
- Known emulator limits: only the state machine's **onboard** channels are emulated, so
  `BpodSystem.assertModule` fails, the HiFi module is unavailable, PulsePal cannot be
  programmed, and Flex I/O (including the flow-meter analog stream) is not emulated.
- Emulated sessions must still produce a complete, correctly structured data file, clearly
  marked as emulated so it is never mistaken for real behaviour.

### 4.4 Data saving

Bpod writes session data to the `DataFolder` set above:

```
D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Settings\<settings name>.mat
```

- `SaveBpodSessionData` writes `BpodSystem.Data` to the current data file as the variable
  `SessionData`, overwriting it each time; it is called periodically during the session so
  that a crash costs at most a few trials.
- Because the whole struct is rewritten on every save, the per-trial record must stay small:
  session-level information (settings, stimulus/pattern definitions, rig configuration,
  metadata) is stored **once** per session, and each trial stores only its own events,
  timestamps, outcome and indices into those session-level definitions.
- GUI parameters chosen in the launch manager are saved as a per-subject settings file, so a
  session can be reproduced or resumed with the same configuration.
- Flex I/O analog data (the flow meter) is streamed by Bpod to a separate `..._ANLG.dat`
  file next to the session file, and merged into the session data after the session with
  `AddFlexIOAnalogData`.
- Alongside the Bpod file, the protocol saves session-level metadata (subject, date, rig,
  training stage, contingency, stimulus definitions, software versions) for downstream
  analysis.

### 4.5 Online plots

- Stimulus and choice plot, with choices colour-coded as correct/incorrect
- Learning curve — trial vs performance
- Bar graph of performance on left vs right trials
- Trial vs reaction time
- Opto vs control trials, where relevant
- Psychometric curve, where relevant

---

## 5. Utilities

Helpers for working with the rig outside a session live in `hardware/`.

### `TestHiFiSound` — play a test sound

The Bpod console can exercise ports, valves, LEDs and BNC lines by hand, but not sound.
`TestHiFiSound` connects to the HiFi module, plays a waveform and disconnects, without
launching a protocol:

```matlab
TestHiFiSound                                   % 1 kHz tone, 0.5 s, both channels
TestHiFiSound('Frequency', 8000)                % 8 kHz tone
TestHiFiSound('Waveform', 'noise')              % white noise burst
TestHiFiSound('Waveform', 'sweep', 'FreqRange', [2000 20000])
TestHiFiSound('Channel', 'left')                % check speaker wiring
TestHiFiSound('Repeat', 5, 'Interval', 0.25)    % repeated beeps
TestHiFiSound('Attenuation', -20)               % quieter (dB FS, <= 0)
TestHiFiSound('Port', 'COM8')                   % explicit port, Bpod not running
TestHiFiSound('Device', 'pc')                   % play on the PC's own speakers
```

The module's USB port is taken from `BpodSystem.ModuleUSB.HiFi1`, so Bpod must be running
and the module USB-paired (console USB button) — otherwise pass `'Port'` explicitly. With
no module reachable, or in emulator mode, playback falls back to the PC audio device so
sound can still be checked on a desk PC. Because loading a sound overwrites a slot in the
module's active sound set, the utility refuses to run while a protocol is in progress
unless `'Force', true` is passed. `help TestHiFiSound` lists all options.

---

## 6. Later: controlling the Doric LED from MATLAB

*Not in scope yet.* The API for controlling the Doric LEDs lives in
`C:\Users\harrislab\Documents\MATLAB\DoricSystemDLL`. It would let the operator set LED
power and other parameters directly from MATLAB. Open question: should this live in its own
package, or be integrated into this protocol folder?

---

## 7. Repository layout

```
LuminoseFM/
├── README.md                     this file
├── CLAUDE.md / AGENTS.md         instructions for coding agents
├── hardware/
│   └── TestHiFiSound.m           play a test sound through the HiFi module
└── docs/
    ├── architecture.md           design plan and architecture decisions
    ├── BpodSystemInfo.png        channel, event and output list of the rig
    ├── behaviour_box_design/     box, base plate and home-cage cover drawings
    └── fiber_bundle_design/      2-to-19 and 4-to-19 fiber bundle drawings
```
