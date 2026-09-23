# LuminoseFM — Rig checks

What has been checked on the rig itself, and what is still **waiting for someone at the rig**. An
agent can run Bpod, PulsePal, the HiFi module and the cameras when the operator allows it (no animal
in the box), but cannot see the light, hear the speaker, poke a port or move a cable. Checks that
need any of those are listed under *Pending*; run them the next time the operator is at the rig,
and move each one to *Done* with its result and session names.

---

## Pending — needs the operator at the rig

### P4. Calibrate the 2-to-19 bundle (0.9.1)

The 4-to-19 bundle is calibrated on both channels for every cable (2026-09-23, below). The 2-to-19
bundle has no calibration yet (blue on A, green on B by default): calibrate it from the Doric LED tab,
**Calibrate LED power…**, with the meter zeroed with the LED off, set to 465 nm. Green on A (4-to-19)
still has its 0.9.0 lit points with a replaced dark point; re-measure it when convenient. From 0.9.3
the window offers 0–1000 mA in 100 mA steps (P9).

Check on the way that **On** and **Off** switch only their own channel, that a lit channel follows
**Next**, and that closing the window switches both off; that the Doric LED tab shows mW/mm² with the
current beside it (8 mW/mm² in behaviour, 2 in the sleep dialog); and see the light at the tips at
those currents.

### P9. The LED to 1000 mA, and calibrations extended to it (0.9.3)

1. Turn the driver's front knob to 1000 mA on both channels: it caps the current whatever USB asks, so
   with it lower the limit of 1000 mA gives less light than the calibration says.
2. Open **Calibrate LED power…** with each 4-to-19 pair (orange A / blue B, then black A / green B,
   then the swapped pairs): each table must show the saved 0–700 mA readings with 800, 900 and
   1000 mA empty. Read those three and save; the graph must go on rising (a flat top means the knob is
   limiting). The dashed saved curve and the new points must meet at 700 mA.
3. Hold a channel at 1000 mA for the length of a calibration and check the LED head is not hot to the
   touch. Doric recommends 700 mA for light held on for long; sessions gate the light.
4. A behaviour session asking for more than the 700 mA reading (for example 20 mW/mm² on A) before
   step 2 runs at 700 mA with a note; after it, at the current that gives 20.

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

### 2026-09-23 — orange on A and blue on B re-measured, operator at the rig with the power meter

The 0.9.0 per-cable files for three light paths read light with the LED off (0.67–1.25 mW/mm² at 0 mA),
and two had a lit point out of line with the other cables on their channel: orange on A at 50 mA
(0.030 mW, where the other A cables read 2.24–2.65 mW/mm²) and blue on B at 100 mA (3.14 mW/mm², the
other B cables 2.10–2.65). Green on A had only the dark point off: it was replaced by the mean dark
reading of the re-measured A cables (1.25 → 0.04 mW/mm²; `DoricLED_4-to-19_green_A.mat`, noted in
the file); its lit points are as measured. Orange on A and blue on B were measured again in full: the
agent set each current in continuous mode through `lum.dev.DoricLED.lightOn` (one channel lit, the
other off), the operator read the meter (zeroed, 465 nm) and typed each value, and the agent switched
both channels off and released the driver at the end.

| mA | 0 | 50 | 100 | 150 | 200 | 250 | 300 | 350 | 400 | 450 | 500 | 550 | 600 | 650 | 700 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orange on A, mW | 0.002 | 0.093 | 0.164 | 0.222 | 0.267 | 0.311 | 0.364 | 0.430 | 0.462 | 0.513 | 0.54 | 0.592 | 0.626 | 0.667 | 0.703 |
| blue on B, mW | 0.002 | 0.0645 | 0.0956 | 0.135 | 0.165 | 0.198 | 0.221 | 0.249 | 0.271 | 0.292 | 0.316 | 0.337 | 0.362 | 0.379 | 0.404 |

Both rise at every step; 50 mA on orange A (2.37 mW/mm²) and 100 mA on blue B (2.43) now sit with the
other cables on their channels, and each cable's B/A ratio is 0.52–0.73, as for the others. The
defaults now run at: sleep 2 mW/mm² → orange A 42 mA (was 69), blue B 73 mA (was 67); behaviour
8 mW/mm² → 253 mA (was 235) and 496 mA (was 457). Saved as `DoricLED_4-to-19_orange_A.mat` and
`..._blue_B.mat`; the 0.9.0 per-cable files are kept but no longer used for these paths.

### 2026-09-23 — 0.9.2, the 4-to-19 calibrations, the spread mixture and alternating sleep probes, no animal, run by an agent with the operator's permission

Bpod r2+ on COM3 (16 global timers), PulsePal firmware v21 on COM9, the Doric driver in Device mode
("LED Driver", Doric port 4), HiFi1 on COM8, Flex1 analog and Flex2 sync. No video (checked before).
Bundle 4-to-19, orange on A and blue on B (the defaults). Session files in `%TEMP%\LuminoseFM_rigcheck`,
not the data folder.

**The calibrations** (`calibration/`, read offline). All eight cable/channel pairs of the 4-to-19
bundle resolve to a calibration: black on A and B, blue on A, green on B and orange on B from 0.9.1
files; blue on B, green on A and orange on A from the 0.9.0 per-cable files, each measured on that
channel. Every curve rises with current, and irradiance is power over the cable's area (4 or 5 fibers
of 100 µm). **Channel B gives about 58% of channel A for every cable**: 10.5–10.6 mW/mm² at 700 mA on
B, 17.5–18.6 on A. The cables agree with each other on each channel, so the difference is the LED
channel or the commutator, not the cables. B needs 457–520 mA for 8 mW/mm², and the ePhys curve's top
(12 mW/mm²) is out of reach on B (it runs at 10.6, with a note). The three 0.9.0 files had an offset
at 0 mA, since corrected, and two have a suspect lit point: P4. The table below is as the sessions
ran, before the correction.

| Cable | A: mA for 2 / 8 mW/mm², most at 700 mA | B: mA for 2 / 8 mW/mm², most at 700 mA |
|-------|:---:|:---:|
| black | 38 / 233, 17.5 | 70 / 504, 10.5 |
| blue | 44 / 236, 18.6 | 67 / 457, 10.6 (0.9.0 file, offset) |
| green | 25 / 227, 18.3 (0.9.0 file, offset) | 94 / 511, 10.5 |
| orange | 69 / 235, 17.9 (0.9.0 file, offset) | 85 / 520, 10.5 |

| Check | Result |
|-------|--------|
| `CheckRig` | 11 of 11 ok |
| `TestDoricLED('Currents', [50 250], 'Count', 2)` | every command acknowledged, 12 of 12 gates (A, B, both at each current). Light not watched |
| Behaviour session `FakeSubject_LuminoseFM_20260923_132857`: mixture at its new defaults (spread over 5 cycles, 10 timers), Experiment stage, 6 trials, virtual pokes | the console printed *LED channel A 235 mA = 8 mW/mm2, channel B 457 mA = 8 mW/mm2*; `LEDCurrentA` 235 and `LEDCurrentB` 457 on every trial, `Intensity.ReachedmWmm2` [8.00 8.00]. **All 60 light segments (10 per trial) had a timer start and end at the planned times, within 0.10 ms.** Ready 26.4 s after launch, 16.2 s of it waiting for the Doric driver |
| Sleep session `FakeSubject_LuminoseFM_20260923_133000`: the new default test pulses (paired probes alternating A and B, 30 s), shortened to 2 min | LED A 69 mA = 2.02 mW/mm², B 67 mA = 2.01 (P4 for A). 8 of 8 gates: pairs on A, B, A, B, 50 ms apart, 10 ms each, never both channels in one epoch; epochs 30.24, 30.19 and 30.05 s apart, each interval longer by the time between the ~10 s blocks it spans (D13) |
| ePhys calibration session `FakeSubject_LuminoseFM_20260923_133226`: A and B, input-output in 4 levels, pairs 20 and 50 ms | 32 of 32 gates, completed. The LED stepped A 0, 110, 247, 398 mA and B 0, 184, 393, 700 mA (B's top level at its most, 10.6 mW/mm², with a note), then 235 / 457 mA for the pairs, between blocks; every gate's recorded current is its step's. The lowest level reads 0.67 mW/mm² at 0 mA because of the 0.9.0 orange and blue offsets (P4) |

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
