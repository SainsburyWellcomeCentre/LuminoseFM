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
D:\luminoseData\<subject>\LuminoseFM\Session Videos\<view>_<data file name>.avi   (video, one per camera)
D:\luminoseData\<subject>\LuminoseFM\Session Videos\<view>_<data file name>.csv   (one row per frame)
D:\luminoseData\<subject>\LuminoseFM\Session Videos\<data file name>_events.csv  (marks, host clock)
D:\luminoseData\<subject>\LuminoseFM\Session Videos\<data file name>_session.json
```

`<view>` is the camera's name in `S.Camera.Cameras` (`sideview` = 24226887, `topview` = 24226657 on
this rig); `.avi` is `.mp4` or `.raw` (+ `.raw.json`) in those formats. The video files are
SpinCam's: see *Video* below and SpinCam's README (§7) for every column.

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
- `Cameras` — the video (below): `Enabled`, `Backend` (`'spinnaker'`, `'mock'` for the emulator's
  simulated cameras, `'none'`), `Recorded`, `SpinCamFolder`, `SpinCamVersion`, `Settings`
  (`S.Camera`), `Plan` (folder, base name, start time, format, events and session files, and per
  camera `Serial`, `Name`, `VideoFile`, `CsvFile`) and, written at teardown, `Summary` (`Duration_s`
  and per camera `FramesLogged`, `FramesWritten`, `FramesMissed`, `WriterDrops`,
  `FramesIncomplete`, `QueuePeak`, `VideoFiles`, `Error`)
- the protocol version and the device log (`DeviceLog.PulsePal`, `DeviceLog.HiFi`,
  `DeviceLog.FlexIO`, `DeviceLog.Cameras`)
- `StoppedReason` — empty for a session that ran to its end or was stopped from the console, and
  the error message otherwise

### One value per trial

`StimulusGroup`, `PatternIndex`, `CorrectSide`, `Choice`, `Correct`, `Rewarded`, `Outcome`,
`ReactionTime`, `OptoOn`, `SoundOn`, `SyncMode`, `SyncPulseWidth`, `BiasTargetPLeft`,
`TrainingStage`, `HoldDuration`, `HoldGrace`, `HoldBreaks`, `HoldAttempts`, `EarlyWithdrawals` and
`CameraTime`, plus `TrialSettings` (the runtime parameters only) and `OutcomeNames` for decoding
`Outcome`.

Outcome codes are never renumbered. `HoldAttempts` counts how many times the stimulus started on
that trial; `EarlyWithdrawals` how many times the animal left the centre port before the hold was
complete without the break being forgiven (visits to `EarlyWithdrawal`, during the latency or the
hold) — what automatic shaping counts before it steps the hold back. `HoldDuration` shows the
steps. `CameraTime` is the time, in seconds on the video's host clock, at which the trial's events
reached MATLAB (`NaN` without video); see *Video*.

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

- `SessionData.CameraTime` — one value per block: seconds on the video's host clock when the
  block's events reached MATLAB (`NaN` without video); `Session.Cameras` as for behaviour.

Per-pulse carrier copies are never stored: the compiled steps are written once.

---

## Video

Recorded by SpinCam in passive TTL mode (`lum.dev.Cameras`, D14). Per camera, the `.csv` has one row
per frame received while recording, with (among others):

| Column | Meaning |
|--------|---------|
| `FrameNumber` | 0-based row index |
| `HardwareTimestamp_us` | The camera's own clock, µs: use it for frame intervals |
| `HostTimestamp_datetime` | Wall-clock arrival time, ISO 8601 with µs and UTC offset |
| `TTL_State` | The camera's TTL input (`S.Camera.TtlLine`) at the end of the frame's exposure: 0, 1, or −1 |
| `DroppedFrameFlag`, `FramesMissedBefore` | Frames lost before this one |
| `HostTime_s` | Seconds on the host clock shared with `_events.csv` and `SessionData.CameraTime` |
| `VideoFrameIndex` | 0-based frame in the video file, −1 if it was not written |
| `WriterDropFlag` | The encoder fell behind and this frame was not written |

`_events.csv` has a `RecordingStart` row, a `LuminoseFM` row naming the data file, one `TrialEnd`
(behaviour) or `BlockEnd` (sleep) row per trial with its number, a `SessionSaved` row (the number of
trials or blocks in the file) and `RecordingStop`. The video stops after the data file is written,
so every trial in it is on the video; `Session.Cameras.Summary` (frames logged, written, missed,
writer drops, queue peak, per camera) is added by a second save right after the video stops.

Videos recorded with `avi-mjpeg-mt` (the default) are MJPEG AVI in OpenDML form (one file of any
length, readable by `VideoReader`, ffmpeg and OpenCV), gray stored as YCbCr 4:2:0 with constant
chroma: read the first channel. SpinCam's `_session.json` records the encoder settings
(`Recorder.JpegQuality`, `Recorder.EncoderThreads`).

**Aligning to Bpod.** Until the sync line is wired to the cameras (`TTL_State` then carries the
barcode and trial pulses frame by frame, D4/D7), fit Bpod's clock to the host clock from the
per-trial pairs:

```matlab
T = spincam.io.readFrameLog(SessionData.Session.Cameras.Plan.Cameras(1).CsvFile);
ok = ~isnan(SessionData.CameraTime);
fit = polyfit(SessionData.TrialEndTimestamp(ok), SessionData.CameraTime(ok), 1);  % host = a*bpod + b
bpodTime = (T.HostTime_s - fit(2)) / fit(1);   % each frame on Bpod's session clock
```

Each pair carries the few milliseconds the trial's events take to reach MATLAB, which the fit
averages over the session; `HostTime_s` is the frame's arrival, a few milliseconds after its
exposure.

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
- **Sessions before 0.6.0** have no `EarlyWithdrawals`, `CameraTime` or `Session.Cameras`, and their
  `Settings.Task.HoldShaping` may be `'Off'` (no `AutoShaping`).
- **Field and state names changed** in 0.2, 0.3, 0.4, 0.5, 0.5.1 and 0.6.0; the full old → new tables are
  in [`naming-and-versions.md`](naming-and-versions.md). Settings files are converted on load;
  analysis code reading old data files needs the old names.
