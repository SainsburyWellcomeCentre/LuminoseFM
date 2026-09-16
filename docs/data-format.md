# LuminoseFM — Data format

What a session writes, what every field means, and what to know when reading an older file.
The user-facing summary is in [`../README.md`](../README.md); the reasoning behind the layout is
D5 and D7 in [`architecture.md`](architecture.md).

---

## Where the files are

```
D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Settings\<settings name>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Data\<...>_ANLG.dat   (Flex analog stream)
```

The `.mat` holds one variable, `SessionData` (= `BpodSystem.Data`).

## How it is written

- `SaveBpodSessionData` writes `BpodSystem.Data` to the current data file as the variable
  `SessionData`, overwriting it each time; it is called every few trials so a crash costs at most
  a few trials.
- Because the whole struct is rewritten on every save, the per-trial record stays small:
  session-level information is stored **once**, and each trial stores only its own events,
  timestamps, outcome and indices into it.
- The settings chosen on the setup dialog are saved as the subject's settings file, so a session
  can be reproduced. A settings file from an older version is brought up to date when it is
  loaded (`lum.mergeSettings`); renamed settings keep their values, and the console lists what was
  converted.

---

## A behaviour session file

### `SessionData.Session` — written once

- `Type` — `'Behaviour'`
- `Subject`
- `Settings` — the frozen settings struct
- `StimulusSet` — every pattern as a segment table, the trial order, each group's label and
  `P(left)` as run (`GroupPLeft`), as typed (`BasePLeft`) and whether the contingency was
  `Reversed`, and descriptors of each pattern
- `Rig` — the channel map
- `DevicesAvailable` — which devices the session had (e.g. `FlexSync`)
- the runner and runtime window used
- `StartTime`, `EndTime`
- `Barcode` — value, kind, whether it was sent, its parameters
- the protocol version and the device log (`DeviceLog.PulsePal`, `DeviceLog.Flex`, …)
- `StoppedReason` — empty for a session that ran to its end or was stopped from the console, and
  the error message otherwise

### One value per trial

`StimulusGroup`, `PatternIndex`, `CorrectSide`, `Choice`, `Correct`, `Rewarded`, `Outcome`,
`ReactionTime`, `OptoOn`, `SoundOn`, `SyncMode`, `SyncPulseWidth`, `BiasTargetPLeft`,
`TrainingStage`, `HoldDuration`, `HoldGrace`, `HoldBreaks` and `HoldAttempts`, plus
`TrialSettings` (the runtime parameters only) and `OutcomeNames` for decoding `Outcome`.

Outcome codes are never renumbered. `HoldAttempts` counts how many times the stimulus started on
that trial.

To get trial *k*'s light:

```matlab
p = lum.pattern.patternAt(SessionData.Session.StimulusSet, SessionData.PatternIndex(k));
```

### `SessionData.Timing`

How long each trial's prepare, send, plot and save steps took, so lag regressions show up in the
data rather than only in the room.

---

## A sleep session file

`SessionData.Session` carries `Type` `'Sleep'` — subject, settings, rig, devices, whether sync was
sent, start and end time, barcode, `TestPulses`, version, PulsePal and Flex logs — and:

- `SessionData.SyncPulses` — `Onset` (state machine clock, s), `Width` (s) and `Block`, one value
  per pulse sent. Each block is one Bpod trial in `RawEvents`.
- `SessionData.LightSegments` (with test pulses) — `Onset` (state machine clock, s), `Duration`
  (s), `Channel` (1 = A, 2 = B), `Step`, `Epoch` and `Block`, one value per gate of light sent.
  For a probe step the gate is the pulse; for a train step it is a burst, and

  ```matlab
  plan = lum.sleep.testPulsePlan(SessionData.Session.Settings.Sleep.TestPulses);
  pulses = lum.sleep.epochShape(plan, step, epoch);
  ```

  gives the pulses PulsePal put in it.
- `Session.TestPulses` — `Enabled`, the compiled `Steps` (kind, channels, start, duration, epoch
  count, and each step's PulsePal carrier and train), the schedule's `Duration`, whether it
  `Completed`, and a `StoppedReason` when PulsePal stopped answering.

Per-pulse carrier copies are never stored: the compiled steps are written once.

---

## The Flex analog stream (flow meter)

Flex I/O analog data is streamed by Bpod to a separate `..._ANLG.dat` file next to the session
file, and merged into the session data at the end of the session as `SessionData.Analog`
(`Samples`, `Timestamps`, `TrialNumber`).

**The merge corrects Bpod's timeline for the session barcode.** Bpod starts the stream with the
barcode's own state machine but stamps its first sample with trial 1's start, which put every
analog timestamp about 1.8 s late and numbered every sample one trial too high — airflow then
appeared to arrive as the animal reached the reward port. Samples taken during the barcode now
have `TrialNumber` 0, and `Analog.info.Alignment` says the correction was applied.

Session files from version 0.2 with a barcode sent (e.g.
`FakeSubject_LuminoseFM_20260911_140213`) still carry the shifted timeline:

```matlab
Analog = lum.dev.Flex.alignAnalog(SessionData.Analog, SessionData.TrialStartTimestamp(1), 1);
```

---

## Emulated sessions

Sessions run under `Bpod('EMU')` still produce a complete, correctly structured data file, marked
with `Data.Info.EmulatorMode = 1` so it is never mistaken for real behaviour. Every hardware call
the null device shims swallowed is recorded in `Data.Session.DeviceLog`. See
[`emulator.md`](emulator.md).

---

## Reading older files

- **Trial sync pulses in sessions from 0.2 to 0.5.0** are ~100 µs glitches, not the recorded
  widths. Align those sessions by the barcode and `Data.TrialStartTimestamp`; see
  [`sync-and-barcode.md`](sync-and-barcode.md).
- **Analog timestamps from 0.2** need `lum.dev.Flex.alignAnalog`, above.
- **Field and state names changed** in 0.2, 0.3, 0.4, 0.5 and 0.5.1; the full old → new tables are
  in [`naming-and-versions.md`](naming-and-versions.md). Settings files are converted on load;
  analysis code reading old data files needs the old names.
