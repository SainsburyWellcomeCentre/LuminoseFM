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
| 5 | House light — LED driver for the white light inside the rig, used for pre/post-behaviour sleep | — | ✔ | — |

Port *n* is `PWMn` (LED), `Valven` (solenoid) and `PortnIn`/`PortnOut` (IR gate). Ports 4 and 5
use the valve/LED line only; their IR gates are unused.

### 2.2 Optogenetic stimulation (digital out → PulsePal → Doric LED)

The optogenetic stimulus is a **spatiotemporal pattern of 100 µm light spots** delivered to
the olfactory bulb through a custom fiber bundle
([`fiber_bundle_design/`](fiber_bundle_design)). There are two optical channels,
called **A** and **B** everywhere in the protocol, its windows and its data:

```
Channel A:  Bpod BNC1 → PulsePal IN1 → PulsePal OUT1 → Doric LED ch1
Channel B:  Bpod BNC2 → PulsePal IN2 → PulsePal OUT2 → Doric LED ch2
```

Each channel drives one cable of the bundle on the animal:

| Bundle | Cables | Spots per cable | Which two are used |
|--------|--------|-----------------|--------------------|
| 2-to-19 | ch1 fiber, ch2 fiber | 10, 9 | both, fixed: ch1 on A, ch2 on B |
| 4-to-19 | black, blue, orange, green | 4, 5, 5, 5 | any two on the commutator; chosen on the setup dialog's Light path tab and recorded with the session |

The design drawing colours the orange cable red.

A **light pattern** is the sequence of ON/OFF states of channels A and B over the stimulus
window. At any instant the pair is in one of four joint states: dark, A only, B only, or A
and B together. While a channel is on, PulsePal fills it with that channel's carrier
(frequency, pulse width, voltage — set per channel on the Light path tab). The split between
Bpod-owned pattern and PulsePal-owned carrier is decision D1 in [`architecture.md`](architecture.md).

**A session that delivers light does not start without PulsePal.** The protocol programs
PulsePal at the start of every session: both trigger inputs gated, output 1 on input 1 and
output 2 on input 2, the carrier, no train delay, and every output stopped with continuous
playback off. Bpod gates BNC1 and BNC2 whether or not that has happened, and a PulsePal the
session has not programmed answers with whatever program it last held. That can be edge
triggering with a long train, a train delay, both LED channels on one input, or an output
looping on its own, so light comes at the wrong times. Meanwhile the session file shows every
light timer starting on the poke. If PulsePal cannot be connected the session stops with
PulsePal's own error message. Check its USB cable, close anything else holding its port
(restarting MATLAB releases it), or untick **Light pattern** on the Task tab to run without
light. Sessions before version 0.4.1 ran on regardless; the first line of their
`Session.DeviceLog.PulsePal` says whether PulsePal was connected.

Once connected and stopped, PulsePal must also **answer a handshake** before a session uses it
(since 0.5). A sleep session that sends test pulses is refused on the same terms, asks
again whenever it gives PulsePal a new carrier and at every save (about once a minute), and stops,
saving what it sent, if PulsePal stops answering.

PulsePal lives in `...\MATLAB\PulsePal` and is **not** on the saved MATLAB path; the protocol
adds it when it needs it.

### 2.3 Flex I/O

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
other acquisition devices (Neuropixels OneBox or NI-1083, camera 1, camera 2, and so on).
See [`sync-and-barcode.md`](sync-and-barcode.md). Bpod's analog viewer opens at the start of
each session so the airflow can be watched.

### 2.4 Modules

Module ports are high-speed communication channels for external Bpod hardware extensions.

- **[HiFi module](https://sanworks.github.io/Bpod_Wiki/assembly/hifi-module-assembly/)**
  (`HiFi1`, Module#1, USB `COM8`) — connected to the state machine over Ethernet and to the
  computer over USB, and driving an amplifier card wired to a custom-made speaker. It plays
  **one sound at a time**: a new play command replaces the sound playing.
- Module ports 2 and 3 are unregistered.

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

MATLAB R2025b, base MATLAB only; no toolboxes. Bpod_Gen2 v1.9.0.
Bpod user guide: <https://sanworks.github.io/Bpod_Wiki/user-guide/>

### Why every session starts from a clean slate

Close MATLAB, then power-cycle the Bpod state machine and PulsePal (unplug their USB, or switch
the powered hub off and on) before the first session of a run, and again after any session that
ended in an error. This is not superstition, and it is not optional after a failure. Both devices
talk over a USB serial port that only the process holding it can use, and both keep state between
sessions:

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

---

## 4. Later: controlling the Doric LED from MATLAB

*Not in scope yet.* The API for controlling the Doric LEDs lives in
`C:\Users\harrislab\Documents\MATLAB\DoricSystemDLL`. It would let the operator set LED power and
other parameters directly from MATLAB. Open question: should this live in its own package, or be
integrated into this protocol folder?
