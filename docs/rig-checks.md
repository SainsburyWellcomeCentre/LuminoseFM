# LuminoseFM — Rig checks

What has been checked on the rig itself, and what is still **waiting for someone at the rig**. An
agent can run Bpod, PulsePal, the HiFi module and the cameras when the operator allows it (no animal
in the box), but cannot see the light, hear the speaker, poke a port or move a cable. Checks that
need any of those are listed under *Pending*; run them the next time the operator is at the rig,
and move each one to *Done* with its result and session names.

---

## Pending — needs the operator at the rig

### P4. First calibration of each cable on each channel (0.9.1)

Calibrate each cable in use on each channel it will be used on (Doric LED tab, **Calibrate LED
power…**, two cables at a time, one on each channel) with a power meter at its tip, set to 465 nm:
blue on A and green on B on the 2-to-19 bundle (and swapped, if they will be); on the 4-to-19, each of
black, blue, orange and green on the channels it will use. From 0.9.1 a calibration is per cable and
channel; the three per-cable files in `calibration/` from 2026-09-23 (4-to-19 blue measured on B,
green and orange on A) are still used on those channels only. Check on the way that **On** and **Off**
switch only their own channel, that a lit channel follows **Next**, and that closing the window
switches both off. Then check the tab shows mW/mm² with the current beside it (8 mW/mm² in
behaviour, 2 in the sleep dialog), that a behaviour session's console line prints the irradiance, and
that a channel asked for more than it gives (for example 12 mW/mm² on blue, which reached 10.6 at
700 mA) runs at its most with a note.

### P5. Centre reward and punishments (0.8.0)

1. Calibrate **valve 2** (the centre port) from the Bpod console's liquid calibration, as for valves 1
   and 3. Without it a habituation session warns *No centre reward* and runs without one.
2. A habituation session with the default centre reward (1 µL, trials 1 to 10), playing the animal at
   the ports: water appears at the centre port as each of the first 10 holds is completed, and not on
   trial 11; raising *Centre reward for trials* in the runtime window gives it again from the next
   trial prepared. `Data.CentreReward` is 1 (µL) on those trials.
3. A training session, with *Punish on* set to *Incorrect choice* and each *Punishment* in turn: with
   *White noise* and *Timeout + noise* the whole burst (`S.Sound.NoiseDuration`, 0.5 s) is heard
   before the next trial; before 0.8.0 the ITI cut it off at once. With *Punish on* *None*, a wrong
   poke followed by the correct one opens the correct valve.

### P6. The End button with the camera and LED windows open (0.8.1)

A behaviour session with video, the camera window and the LED window (the defaults), ended with the
console's **End** button part way through a trial; then the same during a sleep session. MATLAB must
not freeze: both windows close, the command window prints *session ended*, and no `TimerFcn`
error about `lum.gui.CameraWindow` or destructor warning about `lum.SessionRunner` follows. The data
file and `_plots.png` are written. Before 0.8.1 this froze MATLAB (2026-09-22, sessions
`FakeSubject_LuminoseFM_20260922_132416` and `..._135918`, which have no `.mat`).

### P7. Where the start-up time goes (0.8.1)

Start a behaviour session with everything on (light, video, sound) and note the line *LuminoseFM:
ready ... after launch* (also `Data.Session.Startup`). In the one 0.8.0 rig session with video,
opening the cameras to starting the recording took 22 s (SpinCam's `HostClockAnchor` against
`RecordingStart`), which covers the cameras, the house light, the HiFi module and Flex: the line now
splits it. Record it here; it decides what to speed up next.

### P8. The stimulus families at the fiber tips, and centre reward again (0.9.0)

1. From a desktop MATLAB, launch a behaviour session and open the Stimulus tab: choose each family in
   *Family* and open **Design stimuli…**; both windows must keep updating (the desktop-only stall of
   0.7.0 cannot be seen by the test suite). Check the family's line *One cue alone could score at
   most…* appears under the group table.
2. With the LED on and a card (or the power meter) at the fiber tips, run a few trials of each family,
   playing the animal from the console, and compare the light with the designer's preview: the
   sequence family's five 100 ms flashes in a new order each trial, the guarded order's overlaps, a
   motif's three flashes. The state machine side is checked (2026-09-22, below); this is the light.
3. In a Training session, tick **Centre reward again** in the runtime window: water at the centre port
   on the next 10 completed holds, and the box unticks itself after them (needs valve 2's
   calibration, P5).

## Done

### 2026-09-22 — 0.9.0 stimulus families on the state machine, no animal, run by an agent with the operator's permission

Bpod r2+ on COM3 (16 global timers), PulsePal firmware v21 on COM9 (connected, outputs stopped,
handshake answered, programmed for each session), Flex2 sync (barcode sent each session). No sound, no
video; the Doric LED left as set by hand (`S.Doric.Enabled` off), so this checks timing, not light
(P8). One headless behaviour session per family at its defaults (Experiment stage: 1 s window, 1 s
hold), 4 trials each, the animal played by virtual input events written to the state machine's serial
port (`'V'`, what the console's port buttons send), every 5 s from the first trial: centre poke, 1.35 s
hold, leave, left poke, right poke. Session files written to `%TEMP%\LuminoseFM_rigcheck`, not the data
folder, and not kept.

A trial *matches* when each light segment of its pattern has its `GlobalTimer<k>_Start` at the
segment's onset after the last `CentreHold` entry, and its `_End` at onset plus duration, within 1.5 ms.

| Family (defaults) | Segments per pattern | Trials with a hold | Matching | Worst difference |
|-------------------|:---:|:---:|:---:|:---:|
| Pure channel | 1 | 4 | 4 of 4 | 0.10 ms |
| Mixture, compare | 2 | 4 | 4 of 4 | 0.10 ms |
| Sequence, 5 flashes in a new order each trial | 5 | 4 | 4 of 4 | 0.10 ms |
| Order, guarded cycle, random phase | 3 | 4 | 4 of 4 | 0.10 ms |
| Motifs | 3 | 4 | 4 of 4 | 0.10 ms |

Every session reached its first trial 5–7 s after launch (`Session.Startup`), printed its family and
its single-cue ceilings, and ended with Correct or Incorrect on every trial (a wrong left poke was
followed by the right one, as the script plays both). With 4 trials the ceilings are the session's own
(the mixture's amounts read 75%, not the 67% of a full session, because 4 trials cannot cover 6
groups evenly).

### 2026-09-21 — P1, P2 and P3, operator at the rig, run by an agent (0.7.1)

| Check | Result |
|-------|--------|
| P1 `TestHouseLight('Count', 5, 'On', 2, 'Off', 2)` | the operator saw the house light on for 2 s five times; 10 of 10 switches reached BNC1, 19–32 ms after each command (median 25 ms) |
| Desktop launches of the protocol by the operator (0.7.1) | behaviour setup: the cue count and trial timeline follow a cue tick at once; launch → sleep → cancel → launch → behaviour opens and updates (where MATLAB hung in 0.7.0) |
| P3 sleep session with test pulses and the LED window, channel A's current changed mid-session | the operator saw the brightness change from the next block |
| P2 `TestDoricLED('Currents', [20 100 300], 'Count', 3)` | the operator saw A flash, then B, then both, brighter at each current; LED in Device mode ("LED Driver", Doric port 4), 27 of 27 gates, every command acknowledged. The first attempt stopped before sending anything: Bpod connected on COM3 but `BpodSystem.HW.n` was never filled in, straight after the P1 run had released the port. It ran after the state machine and PulsePal were power-cycled |

### 2026-09-21 — 0.7.0 → 0.7.1, setup windows hanging in the desktop, run by an agent with the operator's permission

The operator reported that the behaviour setup dialog did not update (the *Cue (1 on)* count, the trial
timeline) and that MATLAB hung at the next window after a cancelled sleep setup. No animal; Bpod in
emulator mode throughout (no COM ports).

- Doric driver, real, through DoricLED's bridge: three cycles of connect, sleep setup dialog, cancel, close,
  connect again, behaviour setup dialog, cancel, close, headless. No hang: each close took 0.7–1.8 s, and the
  dialog updated on a cue click (0.04–0.12 s). The driver was still *Connecting* 7 s after each connect
  (INIT and OPEN wait up to 5 s each), so a dialog opened straight after launch shows that state.
- Desktop MATLAB, no LED at all: the behaviour setup dialog was fully drawn but its view never confirmed the
  next update, so `drawnow` did not return, in more than half of the launches; the 0.6.1 code did the
  same (2 of 3). The cause was not a component, the axes toolbars, Bpod's console or a timer. It happened
  when the window's view finished loading while components were still being added. With `lum.gui.Form.waitForView` (0.7.1):
  0 of 16 hung, the type → sleep (cancelled) → type → behaviour sequence included.

### 2026-09-21 — 0.7.0, no animal, run by an agent with the operator's permission

Bpod r2_Plus, firmware 23, COM3; PulsePal firmware v21 on COM9; Doric LEDFLS_465_465 ("LED Driver",
Doric port 4) through DoricLED's bridge; HiFi1 on COM8; both cameras. The operator had replaced the
BNC cable from the house light's splitter into Bpod's BNC input 1 beforehand.

| Check | Result |
|-------|--------|
| `CheckRig` | all 11 checks ok, the Doric LED included |
| `TestHouseLight` (5 switches, 1 s) as in 0.6.1 | 0 of 10 switches reached BNC1 |
| Every Bpod input read directly (`'I'` command) while PulsePal OUT3 was driven | resting voltage (parameter 17) 5 V: BNC1 stays 0. A software-triggered 5 V train on OUT3: BNC1 reads 1. OUT4 reaches no input. **The cable is right; the resting voltage alone never changes the output.** Firmware v21 (`PulsePal_2_0_1.ino`) stores parameter 17 and calls `dacWrite()` without setting that output's `DACFlags`, so the DAC is not updated until a stop or abort kills the channel |
| Parameter 17 then op 79 (`SetPulsePalVoltage`) | BNC1 follows at once; the level survives op 82 (stop, every output) and op 80 (abort). 10 op 79 in 134 ms. `lum.dev.PulsePal.holdVoltage` now sends both |
| `TestHouseLight` (5 switches, 1 s) after the fix | **10 of 10 switches reached BNC1**, latency 18–33 ms (median 28 ms) |
| `TestDoricLED('Currents', [50 200], 'Count', 3)` | connected in the background, both channels in external TTL mode at 50 mA, then 200 mA; every command acknowledged; PulsePal gated with constant light; 18 of 18 gates ran (A, B, both). Light not watched: P2 |
| Behaviour session `FakeSubject_LuminoseFM_20260921_133846`: 4 trials, no animal (each lapsed), LED A 80 mA, B 120 mA | ran and saved; `LEDCurrentA` [80 80 80 80], `LEDCurrentB` [120 120 120 120]; `Session.DoricLED.Mode` Device; the driver released at teardown |
| Sleep session `FakeSubject_LuminoseFM_20260921_133929`: paired probes on A and B every 1 s, 15 s, LED 60 mA | 60 of 60 gates, each `LightSegments.CurrentmA` 60; schedule completed |
| ePhys calibration session `FakeSubject_LuminoseFM_20260921_134051`: A and B, input-output 0–200 mA in 4 levels, paired pulses 20/50/100 ms at 100 mA, 3 repeats, 0.5 s apart, video at 100 Hz | 7 steps, 60 of 60 gates, completed. The LED stepped 0, 67, 133, 200 mA, then 100 mA, between blocks; every gate's recorded current is its step's. **Barcode `0CA552FB` decoded from both cameras' `TTL_State`, kind EphysCalibration**, and all 11 sync pulses logged; 1863 / 1862 frames, none dropped |

One MATLAB process ended in an access violation (0xc0000005) during the first attempt at these
sessions, which stopped at a validation error in the test settings; no crash dump was written, and
the same path, closing the LED while it connects (six times), and the three sessions then ran without
it. If it happens again, note what was running and look for `matlab_crash_dump.*` in `%TEMP%`.

### 2026-09-17 — 0.6.1, no animal, run by an agent with the operator's permission

Bpod r2_Plus, firmware 23, COM3; PulsePal firmware v21 on COM9; HiFi1 on COM8; both cameras.
Sessions were headless (`LuminoseFM_Headless`), with subject `FakeSubject`.

| Check | Result |
|-------|--------|
| `CheckRig` | all 10 checks ok |
| `TestSyncLine('Drive', 'states', 'Barcode', true)` | ran after `TestHouseLight` in the same MATLAB (this needed the fix below) |
| Behaviour session `FakeSubject_LuminoseFM_20260917_111703`: 15 trials, light, sound, jittered-width sync, video at 100 Hz | both cameras: 3588 / 3587 frames, none dropped, missed or incomplete, queue peak ≤ 2. **Barcode `0C9FEB37` decoded from each camera's `TTL_State`**, kind Behaviour, and **all 15 trial pulses logged**. Widths match Bpod's within one frame (−5.4 to +8.4 ms), and so do intervals (≤ 6.9 ms) |
| Sleep session `FakeSubject_LuminoseFM_20260917_112004`: test pulses (probes A and B, a train alternating A and B, probes A), video, analog | 5 blocks. **Barcode `0C9FEBEA` decoded from both cameras**, kind Sleep, and **all 32 sync pulses logged**. Widths match within one frame (−7.5 to +8.3 ms), and so do intervals (≤ 6.5 ms). 102 of 102 light gates sent, schedule completed. Analog stream merged. Frames: 3761 each, none lost |
| House light, both sessions | 5 and 6 switches recorded on the camera clock (`_events.csv`) and in `Session.HouseLight.Switches`, and `Data.HouseLight` follows them. **No BNC1 edges: see P1** |

Fixed during the check: `RunStateMachine` leaves `BpodSystem.Status.BeingUsed` at 1 after a
run outside a protocol, so a second rig utility in the same MATLAB refused to start ("A protocol is
running"). `TestHouseLight` and `TestSyncLine` now put `BeingUsed` and `InStateMatrix` back when they
finish.

**Running a session headless on the rig.** Set `BpodSystem` up as `emulatorSessionTest` does. Also do
what `RunProtocol` does before a session:
- open the Flex analog file (`BpodSystem.AnalogDataFile`, `Status.RecordAnalog = 1`,
  `Status.nAnalogSamples = 0`) and fill `Data.Analog`'s fields;
- set `ProtocolStartTime` and call `resetSessionClock`.

Otherwise the analog stream's timer writes to an invalid file and nothing is merged.
