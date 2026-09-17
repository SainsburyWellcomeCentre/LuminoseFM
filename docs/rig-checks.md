# LuminoseFM — Rig checks

What has been checked on the rig itself, and what is still **waiting for someone at the rig**. An
agent can run Bpod, PulsePal, the HiFi module and the cameras when the operator allows it (no animal
in the box), but cannot see the light, hear the speaker, poke a port or move a cable. Checks that
need any of those are listed under *Pending*; run them the next time the operator is at the rig,
and move each one to *Done* with its result and session names.

---

## Pending — needs the operator at the rig

### P1. House light loopback into BNC input 1 — **failing**

**Found 2026-09-17 (0.6.1).** Every switch reaches PulsePal, and none reaches Bpod. Across
`TestHouseLight` twice (26 switches) and the two sessions below (11 switches), PulsePal confirmed
every `ch3 param 17 = 5 / 0` command, BNC1 is enabled in the console's port settings
(`InputsEnabled(10) = 1`) and `CheckRig` is clean, but **no `BNC1High` or `BNC1Low` event arrived**.
The software path is confirmed up to PulsePal's acknowledgement: soft code → `houseLight.set` →
`ProgramPulsePalParam(3, 17, V)` → firmware v21, which writes the DAC as soon as parameter 17 arrives.
Nobody was at the rig, so it is not known whether the light blinked.

Until it is fixed, rig sessions have `Session.HouseLight.Edges` empty and every `HouseLight` value
per trial or block read from MATLAB's clock (the level PulsePal held when the trial started), not from
Bpod's; `Switches` on the camera clock are unaffected.

At the rig, with Bpod running and no protocol:

```matlab
TestHouseLight('Count', 5, 'On', 2, 'Off', 2)   % 20 s, slow enough to watch
```

- **The light blinks, no edges.** Follow the splitter's second leg: it must go into Bpod's
  **BNC IN 1**, not BNC OUT 1 (which drives PulsePal IN1, channel A). Check the splitter and cable
  with a meter or scope (≈ 5 V on, 0 V off at the Bpod end).
- **The light does not blink.** Check that the cable leaves PulsePal **OUT3** (not OUT4), and the LED
  driver's input and power. A scope on OUT3 should show 5 V / 0 V following the test.
- If a cable or channel had to change, update `hardware/RigConfig.m` (`rig.HouseLight`) and
  [`hardware.md`](hardware.md) §2.3 to match, then re-run the test: every switch should report an
  edge a few ms after its command.

### P2. Light reaches the LEDs on channels A and B

Bpod's side is confirmed. A sleep session sent all 102 of 102 planned gates, and PulsePal was
programmed and checked for each step. But nobody saw the fiber output or scoped PulsePal OUT1 / OUT2.
At the rig, run a short sleep session with test pulses (probes on A and B, one train) and watch the
bundle's output, or scope OUT1 and OUT2. Each probe should show as two 10 ms flashes, and each train
as bursts.

---

## Done

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
