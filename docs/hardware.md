# LuminoseFM — Rig and hardware

The behaviour box, the state machine channel map, the optogenetic light path and the software
environment. The user-facing guide is [`../README.md`](../README.md); the design record is
[`architecture.md`](architecture.md).

---

## 1. Behaviour box

Red acrylic box, **18 × 18 × 23 cm** (w × l × h). Three behaviour ports sit at a height of
1.2 cm, spaced 6 cm centre-to-centre. The box stands on a base plate and has a cover that
lets wires pass through while making it hard for the mouse to climb out.

Drawings: [`behaviour_box_design/`](behaviour_box_design)

**Sleep recordings.** A red acrylic cover slots onto the home cage so that pre- or
post-behaviour sleep can be recorded without disconnecting tethered optical patch cords
and/or Neuropixels cables. The protocol runs these as *sleep sessions*.

---

## 2. State machine

The rig is controlled by a [Bpod Finite State Machine r2+](https://sanworks.github.io/Bpod_Wiki/assembly/state-machine-assembly-2%2B/),
connected to the computer over USB (FSM `COM3`, App `COM4`, firmware 23). The full list of
channels and events is available from `BpodSystem.StateMachineInfo`, and is captured in
[`BpodSystemInfo.png`](BpodSystemInfo.png).

Budget on this machine: **16 global timers, 8 global counters, 16 conditions**. The channel map
and the connected machine's live limits are read by `hardware/RigConfig.m`, which is the single
source of truth — nothing in the protocol hard-codes them.

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
| 5 | Unused (the house light's line until it moved to PulsePal, §2.3) | — | — | — |

Port *n* is `PWMn` (LED), `Valven` (solenoid) and `PortnIn`/`PortnOut` (IR gate). Port 4 uses
the valve line only; its IR gate is unused.

### 2.2 Optogenetic stimulation (digital out → PulsePal → Doric LED)

The optogenetic stimulus is a **spatiotemporal pattern of 100 µm light spots** delivered to
the olfactory bulb through a custom fiber bundle
([`fiber_bundle_design/`](fiber_bundle_design)). There are two optical channels,
called **A** and **B** everywhere in the protocol, its windows and its data:

```
Channel A:  Bpod BNC1 → PulsePal IN1 → PulsePal OUT1 → Doric LED ch1
Channel B:  Bpod BNC2 → PulsePal IN2 → PulsePal OUT2 → Doric LED ch2
```

The driver is a Doric 2-channel LED fiber light source, `LEDFLS_465_465` (2 × 465 nm), USB, shown to
the DoricLED package as "LED Driver" on Doric port 4. LED channel 1 lights channel A and LED channel 2
lights B; each goes to the commutator and on to one cable of the bundle on the animal:

| Bundle | Cables | Spots per cable | Which two are used |
|--------|--------|-----------------|--------------------|
| 2-to-19 | blue, green | 9, 10 | both: blue on A and green on B by default |
| 4-to-19 | black, blue, orange, green | 4, 5, 5, 5 | any two on the commutator: orange on A and blue on B by default |

Which cable is on which channel is chosen on the setup dialogs' Doric LED tab and recorded with the
session (`S.Light.Cables`, A then B); it must match the commutator.

Each spot is the end of one 100 µm fiber, so a cable's light leaves through its spot count × π × (50 µm)²
(`lum.led.lightPath`).

**Who sets what.** Bpod and PulsePal time the light (D1); the driver sets how bright it is. Both LED
channels run in **external TTL mode**: a channel is lit at its LED current while PulsePal's output
into its TTL input is high. With the DoricLED package found and **Control the LED from MATLAB** ticked
(`S.Doric.Enabled`, the default), the protocol connects to the driver as it launches, each session sets
both channels up at the session's intensity (limit `S.Doric.MaxCurrentmA`, at most 1000 mA, the LED's
rating), and currents change only between trials, sleep blocks or ePhys calibration steps (D17). The
state machine is not involved. Without the package, or with the control off, the driver is used as it
was set by hand (its front panel or Doric Neuroscience Studio), which must then be external TTL mode;
PulsePal's voltage (5 V) is a TTL level either way, not the intensity.

**Calibration.** A cable's LED current can be calibrated against irradiance at its fiber tips: the
Doric LED tab's **Calibrate LED power…** takes the two cables on the commutator at once, one per
channel, and lights each channel continuously (the driver's continuous mode) at a series of currents,
0–700 mA in 50 mA steps by default, while a power meter reads the power leaving the cable (mW or µW). Irradiance is that power over the
cable's fiber area. A calibration belongs to a cable on a channel (bundle, colour and A or B): the light
leaving a cable depends on the LED and the commutator channel that feed it, so the orange cable on A and
the orange cable on B are calibrated separately. It is kept in `calibration/` in the repository as
`DoricLED_<bundle>_<cable>_<A|B>.mat` (not tracked by git, so each rig keeps its own), and is replaced by
the next calibration of the same cable on the same channel. A per-cable file from 0.7.2–0.9.0
(`DoricLED_<bundle>_<cable>.mat`) is still used, on the channel it was measured on only.

**Intensity.** On a calibrated channel every session type asks for irradiance at the fiber tips
(mW/mm²) and sets the LED current that gives it as it starts: 8 mW/mm² by default in behaviour, 2 for
sleep test pulses, 8 for ePhys paired pulses and 0–12 for the ePhys input-output curve. Asked for more
than the channel gives within its limit, it runs at the most it gives and says so. A channel with no
calibration runs at the current typed in mA (100 mA by default; the input-output curve up to the
channel's limit), so a bundle nobody has calibrated runs as before. Data keep the mA sent.

A **light pattern** is the sequence of ON/OFF states of channels A and B over the stimulus
window. At any instant the pair is in one of four joint states: dark, A only, B only, or A
and B together. While a channel is on, PulsePal fills it with that channel's carrier
(frequency, pulse width, voltage — set per channel on the Light path tab). The split between
Bpod-owned pattern and PulsePal-owned carrier is decision D1 in [`architecture.md`](architecture.md).

**A session that delivers light does not start without PulsePal**, which fills channels A and B.
PulsePal also drives the house light (§2.3), so every session opens it; a session without light
that cannot runs anyway, without the house light. The protocol programs
PulsePal at the start of every session: both trigger inputs gated, output 1 on input 1 and
output 2 on input 2, the carrier, no train delay, and every output stopped with continuous
playback off. Bpod gates BNC1 and BNC2 whether or not that has happened, and a PulsePal the
session has not programmed answers with whatever program it last held. That can be edge
triggering with a long train, a train delay, both LED channels on one input, or an output
looping on its own, so light comes at the wrong times. Meanwhile the session file shows every
light timer starting on the poke. If PulsePal cannot be connected the session stops with
PulsePal's own error message. Check its USB cable, and close anything else holding its port
(restarting MATLAB releases it), or untick **Light pattern** on the Task tab to run without light
(and without the house light). Sessions before version 0.4.1 ran on regardless; the first line of their
`Session.DeviceLog.PulsePal` says whether PulsePal was connected.

Once connected and stopped, PulsePal must also **answer a handshake** before a session uses it
(since 0.5). A sleep session that sends test pulses is refused on the same terms, asks
again whenever it gives PulsePal a new carrier and at every save (about once a minute), and stops,
saving what it sent, if PulsePal stops answering.

PulsePal lives in `...\MATLAB\PulsePal` and is **not** on the saved MATLAB path; the protocol
adds it when it needs it.

### 2.3 House light (PulsePal OUT3 → LED driver, looped back into Bpod)

```
House light:  PulsePal OUT3 → BNC splitter ─┬→ house light LED driver
                                            └→ Bpod BNC input 1  (BNC1High / BNC1Low)
```

The white light inside the box is driven by **PulsePal output 3** (`rig.HouseLight`), 5 V on and
0 V off. It is set per session (`S.Session.HouseLight`, `S.Sleep.HouseLight`) and switched at once
during it from the **House light** box in the plots' header (D15 in
[`architecture.md`](architecture.md)).

- **PulsePal holds the level.** Each switch sets output 3's *resting voltage*, which the firmware
  returns every output to after a stop, an abort or a disconnect, and then writes the voltage to the
  output (op 79): firmware v21 does not update an output on its resting voltage alone. The light
  stays where the operator left it through programming, trials, sleep blocks and the gaps between
  them. No trigger input reaches output 3 (the protocol unlinks it from both), so gates on BNC1/BNC2
  never play on it. The session switches it off when it ends; after a crash, power-cycling PulsePal
  (§3) puts it at 0 V.
- **Bpod times each switch.** The splitter's second leg goes into Bpod's **BNC input 1**, so a switch
  made while a state machine runs is an event of the trial, `BNC1High` (on) or `BNC1Low` (off), on
  Bpod's clock. BNC input 1 must be **enabled** in the console's port settings (`CheckRig` says so);
  nothing else may use it. A switch between state machines has no Bpod event; every switch is also
  marked on the camera clock.
- **It costs Bpod nothing**: no output line, no state and no global timer.
- **Without PulsePal** a session without light still runs, with the house light off and its switch
  greyed out (`Session.HouseLight.Switchable` false); a session with light does not start.

**Checking it.** With Bpod running and no protocol, run `TestHouseLight` (in `hardware/`). It
switches the light through PulsePal from a state machine and reports each `BNC1High` / `BNC1Low`
edge and its latency; the light should blink, and every switch should arrive.

**Status (2026-09-21): the loopback works.** Every switch in `TestHouseLight` reached BNC1, 18–33 ms
after its command. Until then no switch had changed the output at all: 0.6.1 set only the resting
voltage, which firmware v21 stores without writing (see [`rig-checks.md`](rig-checks.md), P1). Sessions
up to 0.6.1 on this rig never lit the house light. Whether the light itself turns on is still to be
seen at the rig.

The light moved here from port 5's LED line (`PWM5`) during 0.6.1, where a global timer had to hold it
in every state machine and it went dark between them.

**Why not a Flex channel.** A Flex digital output cannot be held against the states — the firmware
(v23) lets every state entry overwrite it, the reason a global timer could not carry the Flex2 sync
pulse before 0.5.1 (D4) — and would need a driver of its own.

### 2.4 Flex I/O

The r2+ adds four Flex I/O channels, each configurable as digital output (5 V TTL), digital
input (5 V tolerant), analog input (12-bit, 0–5 V, 1 kHz) or analog output (12-bit, 0–5 V).

| Channel | Use | Configured as |
|---------|-----|---------------|
| Flex 1 | Flow meter (airflow) | Analog input, 1 kHz |
| Flex 2 | Sync TTL: session barcode and trial pulses | Digital output (configured on this rig since 0.5.0) |
| Flex 3–4 | unused | disabled |

Channel types in `Bpod Local/Settings/FlexConfig.mat` are 0 = digital in, 1 = digital out,
2 = analog in, 3 = analog out, 4 = disabled. Read the live configuration
(`BpodSystem.HW.FlexIO_ChannelTypes`) rather than the saved file; `BpodSystemInfo.png` predates
the current configuration, so trust the live values where they disagree.

The sync TTL goes to an externally powered, scalable BNC splitter, and from there to the
other acquisition devices (Neuropixels OneBox or NI-1083, the two cameras' Line0, and so on).
See [`sync-and-barcode.md`](sync-and-barcode.md). Bpod's analog viewer opens at the start of
each session so the airflow can be watched.

### 2.5 Modules

Module ports are high-speed communication channels for external Bpod hardware extensions.

- **[HiFi module](https://sanworks.github.io/Bpod_Wiki/assembly/hifi-module-assembly/)**
  (`HiFi1`, Module#1, USB `COM8`) — connected to the state machine over Ethernet and to the
  computer over USB, and driving an amplifier card wired to a custom-made speaker. It plays
  **one sound at a time**: a new play command replaces the sound playing.
- Module ports 2 and 3 are unregistered.

### 2.6 Cameras

Two FLIR / Point Grey **Chameleon3 CM3-U3-13Y3M** USB3 cameras (1280 × 1024 mono, up to 150 Hz),
both on one USB 3.0 controller, recorded by SpinCam (§3):

| Serial | View (file prefix) |
|--------|--------------------|
| 24226887 | `sideview` |
| 24226657 | `topview` |

Each camera's opto-isolated input **Line0** is on the yellow (signal) and brown (ground) wires of
its GPIO cable, logged with every frame (passive TTL logging, `S.Camera.TtlLine`). **The Bpod sync line
(Flex2) is wired to both cameras' Line0**, through the splitter, at **3.3 V TTL** (since 2026-09-17).
That level was reliable in the first wired session (`FakeSubject_LuminoseFM_20260917_082143`, 100 Hz,
3 min): both cameras logged all 79 pulses (34 barcode elements and 45 trial pulses) with no missed or
extra edges, the barcode decoded from each camera, and every trial pulse's width matched Bpod's to
within one frame. Rig sessions on 0.6.1 confirmed it again on 2026-09-17 ([`rig-checks.md`](rig-checks.md)).
In a behaviour session (`..._20260917_111703`) both cameras decoded the barcode and logged all 15 trial
pulses. In a sleep session with test pulses (`..._20260917_112004`) they decoded the sleep barcode and
logged all 32 sync pulses. Neither session dropped a frame. If pulses are ever missing from `TTL_State` while the frame log shows no dropped
frames, raise the level to 5 V. A frame samples the line once, so a pulse or gap shorter than one
frame period could be missed; with video on, the session widens the barcode and sync pulses to at
least two frames each at whatever frame rate is set (`lum.sync.fitToCameras`,
[`sync-and-barcode.md`](sync-and-barcode.md#reading-it-from-the-video)). Two full-frame cameras deliver at
most 120 Hz together on the one USB 3.0 controller (at 150 Hz the cameras skip frames; crop to
960 × 720). SpinCam's multi-core MJPEG (`avi-mjpeg-mt`, the default) keeps up with both at 120 Hz;
SpinVideo's `avi-mjpeg` only has 4 % headroom at 100 Hz full frame and falls behind in a session. Close SpinView before a session: a camera can be streamed by
one program only.

---

## 3. Software environment

| Item | Location |
|------|----------|
| MATLAB working directory | `C:\Users\harrislab\Documents\MATLAB` |
| This project | `...\MATLAB\HarrisLabBpodProtocols\LuminoseFM` |
| Bpod protocol folder | `...\MATLAB\HarrisLabBpodProtocols\` (Bpod's `ProtocolFolder`) |
| Data folder | `D:\luminoseData\` (Bpod's `DataFolder`) |
| Bpod_Gen2, Bpod Local, PulsePal | cloned into `...\MATLAB\`; Bpod_Gen2 is on the MATLAB path, PulsePal must be added to the path before use |
| SpinCam | `...\MATLAB\SpinCam` (its own repository); set up once with `spincam.setup`, then named in the Cameras tab (`S.Camera.SpinCamFolder`) or left on the MATLAB path. Needs Spinnaker with its .NET components (4.2.0.83 here) |
| DoricLED | `...\MATLAB\DoricLED` (its own package, on the saved MATLAB path here); its bridge is built once with `doric.build()`. Named on the Doric LED tab (`S.Doric.Folder`) when not on the path |
| Spinnaker SDK | `C:\Program Files\Teledyne\Spinnaker` (4.2.0.83), .NET assemblies in `bin64\vs2015` |
| Protocol examples | `...\MATLAB\Bpod_Gen2\Examples\Protocols` |

Bpod user guide: <https://sanworks.github.io/Bpod_Wiki/user-guide/>

### Dependencies

Checked 2026-09-16 (`matlab.codetools.requiredFilesAndProducts` over the protocol, `+lum`,
`hardware` and SpinCam's `+spincam`: base MATLAB only, and code from Bpod_Gen2, PulsePal and
SpinCam outside the repository).

| Dependency | Needed for | Version here | Notes |
|---|---|---|---|
| MATLAB | everything | R2025b Update 3 (R2024b also installed) | **No toolboxes.** SpinCam needs R2023b or newer, so that is the floor; only R2025b is tested |
| Bpod_Gen2 | every session | 1.9.0, on the saved path | Flex I/O and `BpodTrialManager` as in 1.9.0; the emulator is a state machine r0.7–1.0 ([`emulator.md`](emulator.md)) |
| PulsePal (MATLAB) | sessions with light; the house light | cloned beside Bpod_Gen2 | Not on the saved path: the session adds it for itself. A light session refuses to start without the device; one without light runs without the house light |
| SpinCam | video | engine 1.2.0 (`spincam.version` still says 1.1.0) | Its own repository, never modified from here. `Session.Cameras` records both versions |
| DoricLED | the LED current from MATLAB, calibration, ePhys calibration sessions | as of 2026-09-21, `DoricSystem.dll` 1.3.0, bridge `bin\doric_bridge.exe` | Its own package, never modified from here. Optional: without it the driver is used as set by hand, and ePhys calibration sessions do not run on the rig. `Session.DoricLED.Device.Package` records its version |
| Spinnaker SDK with .NET components | video on the rig | 4.2.0.83 | Install the .NET components. SpinVideo (`SpinVideoNET`) is needed only for `avi-mjpeg`, `mp4-h264` and `avi-raw`; the default `avi-mjpeg-mt` and `raw` do without it. Not needed for the emulator's simulated cameras |
| .NET Framework 4.8 and `csc.exe` | building SpinCam's engine | ship with Windows 10/11 | `spincam.setup` compiles the engine once, and again after a Spinnaker or SpinCam update (restart MATLAB after) |
| SpinView | nothing during a session | — | Close it: a camera can be streamed by one program only. FlyCapture2 is not used; do not move the cameras to its driver |
| git | optional | — | `lum.version` appends the commit to the recorded version when git runs |
| Disk | video | `D:` | ≈ 27 GB an hour for two cameras at 100 Hz full frame with `avi-mjpeg-mt`; `raw` ≈ 0.9 TB an hour |
| USB | cameras | one USB 3.0 controller for both | Up to 120 Hz full frame together (§2.6) |

### Why every session starts from a clean slate

Close MATLAB, then power-cycle the Bpod state machine and PulsePal (unplug their USB, or switch
the powered hub off and on) before the first session of a run, and again after any session that
ended in an error. Both devices talk over a USB serial port that only the process holding it can
use, and both keep state between sessions:

- A MATLAB that was killed, or a protocol that errored, can leave the port open. Bpod's own
  scan lists only *free* ports, so the next session either cannot find the device or opens it
  with bytes from the last one still in the buffer. A state machine link that has lost its place
  in the byte stream shows up mid-session as a missed-deadline warning with an absurd number in
  it, followed by *"The last state machine sent was not acknowledged by the Bpod device"*. From
  version 0.5.1 LuminoseFM saves the trials that completed, releases the rig and says so instead
  of freezing — but the session is over, and only a restart brings the link back.
- PulsePal answers with **its last program** when nothing has reprogrammed it. `PulsePal()`
  prints "already open" and returns if a `PulsePalSystem` object is left in the base workspace,
  even a dead one, so a stale object hides a disconnected device.
- A stale `BpodSystem` also keeps the old Flex I/O configuration and module list, so a channel
  reconfigured in the console since startup may not be the one the protocol sees.
- The Doric driver is opened by one program at a time. Close Doric Neuroscience Studio, and any other
  MATLAB using DoricLED, before a session. The protocol switches both LED channels off when it ends.

---

## 4. Checking the light path

| Utility | What it checks |
|---------|----------------|
| `CheckRig` | the DoricLED package and its bridge are there, and which cables are calibrated on which channel |
| `TestDoricLED` | the whole path: connects the driver, sets both channels to external TTL mode, programs PulsePal and gates BNC1, then BNC2, then both, at each current given (`TestDoricLED('Currents', [20 100 300])`). Watch the fiber: A flashes, then B, then both, brighter at each current |
| `TestHouseLight` | PulsePal output 3 and its loopback into BNC input 1 |

The driver cannot be read back and nothing loops its output into Bpod, so whether light comes out is
checked by eye or with a power meter.
