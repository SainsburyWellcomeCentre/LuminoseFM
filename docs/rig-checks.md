# LuminoseFM — Rig checks

What has been checked on the rig itself, and what is still **waiting for someone at the rig**. An
agent can run Bpod, PulsePal, the HiFi module and the cameras when the operator allows it (no animal
in the box), but cannot see the light, hear the speaker, poke a port or move a cable. Checks that
need any of those are listed under *Pending*; run them the next time the operator is at the rig,
and move each one to *Done* with its result and session names.

---

## Pending — needs the operator at the rig

### P1. House light: does the light turn on?

The loopback works since 2026-09-21 (see *Done*): every switch reaches BNC1. Nobody has seen the light
itself. With Bpod running and no protocol:

```matlab
TestHouseLight('Count', 5, 'On', 2, 'Off', 2)   % 20 s, slow enough to watch
```

The light should be on for 2 s five times. If it does not light while BNC1 reports every edge, check
the splitter's leg into the LED driver, and the driver's power.

### P2. Light reaches the fiber on channels A and B, at the current set

Bpod, PulsePal and the Doric driver all took their commands on 2026-09-21 (`TestDoricLED`, three
sessions), but nobody watched the fiber. With the bundle's tip where it can be seen (or on a power
meter), no animal attached:

```matlab
TestDoricLED('Currents', [20 100 300], 'Count', 3)
```

- Channel A flashes 3 times, then B, then both together; each set brighter than the last.
- A flash on the wrong channel: swap PulsePal OUT1/OUT2 at the driver's TTL inputs, or LED channel
  1/2 at the commutator, so that LED channel 1 lights channel A.
- No light at all while the report says every gate ran: check PulsePal OUT1/OUT2 into the driver's
  TTL inputs, and that nothing else (Doric Neuroscience Studio) holds the driver.

### P3. A current changed during a session takes effect

The LED window sends a new current between trials with the driver's fast path (`ls_send_current`)
while the channel runs in external TTL mode. The driver acknowledges it; whether the brightness
follows needs a look. In a behaviour or sleep session with light, change a channel's current in the
LED window and watch the next trial's (or block's) light, or use a power meter.

### P4. First calibration of each light path

Calibrate channel A and channel B on the cables in use (Doric LED tab, **Calibrate…**) with a power
meter at the bundle's tip, set to 465 nm. Then check the tab shows mW/mm² and the sessions print
irradiance.

## Done

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
