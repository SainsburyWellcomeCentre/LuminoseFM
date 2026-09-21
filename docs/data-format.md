# LuminoseFM — Data format

What a session writes, what every field means, and what to know when reading an older file.
The user-facing summary is in [`../README.md`](../README.md); the reasoning behind the layout is
D5 and D7 in [`architecture.md`](architecture.md).

---

## Where the files are

```
D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Settings\<settings name>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Data\<...>_ANLG.dat   (Flex analog stream, raw)
D:\luminoseData\<subject>\LuminoseFM\Session Data\<...>_plots.png  (the online figure at the end)
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
- The settings are saved to the settings file chosen in the launch manager
  (`Session Settings\<settings name>.mat`, variable `ProtocolSettings`) twice: when the setup
  dialog's **Start** is pressed, and again at teardown with the runtime tier as the session left it
  and the house light where the operator left it — so the file always holds the last session's
  settings, and the next session opens on them. Headless (test) sessions do not write it. The
  exact settings a session ran with are in its own data file, `SessionData.Session.Settings`
  (and, per trial, `TrialSettings`); to reuse them in a new settings file, load that struct and
  save it as `ProtocolSettings`. A settings file from an older version is brought up to date when
  it is loaded (`lum.mergeSettings`); renamed settings keep their values, and the console lists
  what was converted.
- At teardown the online figure is saved as `<data file name>_plots.png` beside the data file
  (`lum.gui.savePlotsImage`), before the final save, which records its path in
  `Session.PlotsImage` (`''` if it could not be written; the console says why).

---

## A behaviour session file

### `SessionData.Session` — written once

- `Type` — `'Behaviour'`
- `Settings` — the frozen settings struct
- `StimulusSet` — every pattern as a segment table, the trial order, each group's label and
  `P(left)` as run (`GroupPLeft`), as typed (`BasePLeft`) and whether the contingency was
  `Reversed`, and descriptors of each pattern
- `Subject` — the subject the session was launched for (`lum.launchSubject`)
- `Rig` — the channel map
- `DevicesAvailable` — which devices the session had (e.g. `FlexSync`)
- the runner and runtime window used
- `StartTime`, `EndTime`
- `Barcode` — value, kind, whether it was sent, its parameters
- `Cameras` — the video (below): `Enabled`, `Backend` (`'spinnaker'`, `'mock'` for the emulator's
  simulated cameras, `'none'`), `Recorded`, `SpinCamFolder`, `SpinCamVersion`, `EngineVersion` (SpinCam's native engine, which
  grabs and encodes; `''` without one), `Settings`
  (`S.Camera`), `Plan` (folder, base name, start time, format, events and session files, and per
  camera `Serial`, `Name`, `VideoFile`, `CsvFile`) and, written at teardown, `Summary` (`Duration_s`
  and per camera `FramesLogged`, `FramesWritten`, `FramesMissed`, `WriterDrops`,
  `FramesIncomplete`, `QueuePeak`, `VideoFiles`, `Error`)
- the protocol version and the device log (`DeviceLog.PulsePal`, `DeviceLog.HiFi`,
  `DeviceLog.FlexIO`, `DeviceLog.Cameras`, `DeviceLog.DoricLED`)
- `StoppedReason` — empty for a session that ran to its end or was stopped from the console, and
  the error message otherwise
- `PlotsImage` — full path of the `_plots.png` saved at teardown, or `''`
- `HouseLight` — the wiring: `Output` (PulsePal output, 3), `Voltage` (on, 5 V), `Input` (`'BNC1'`),
  `OnEvent` (`'BNC1High'`), `OffEvent` (`'BNC1Low'`); `Switchable` (false when a session without light
  ran without PulsePal: the light was off throughout); `OnAtStart`, `OnAtEnd`; `Switches`, one per
  switch the operator made: `On` (1 × n logical), `HostTime` (camera clock, s; `NaN` without video —
  also a `HouseLight` row in `_events.csv`) and `WallTime` (text); and `Edges`, one per edge of the
  loopback input among the trial events: `Time` (s, Bpod's clock: `TrialStartTimestamp` plus the
  event time), `On` (logical) and `Trial`. A switch made while no state machine ran is in
  `Switches` but has no edge. Rig sessions before 0.7.0 have no edges at all, because the light
  was never switched on: PulsePal did not change its output on the resting voltage alone (P1 in
  [`rig-checks.md`](rig-checks.md))
- `DeviceLog.HouseLight`, and `DevicesAvailable.HouseLight` (false in the emulator, and when the light
  could not be switched). PulsePal is opened in every session on the rig, since it drives the light:
  `DevicesAvailable.PulsePal` is true with or without light when it connected, and
  `DeviceLog.PulsePal` has a `set ch3 param 17 = 5` (on) or `= 0` (off) line, followed from 0.7.0 by
  `ch3 output = 5 V` (or `0 V`), for the start and every switch
- `DoricLED` — the LED (D17), from `lum.led.sessionRecord`: `Controlled` (true when the session set
  the driver), `Mode` (`'Device'`, `'Simulated'` in the emulator, `'Manual'` when set by hand) and
  `Reason`; `Settings` (`S.Doric`); `LightPaths`, one per channel: `Channel`, `LEDChannel`, `Bundle`,
  `Cable`, `nFibers`, `FiberDiameter` (mm), `Area` (mm²); `Calibrations`, a 1 × 2 cell holding each
  path's calibration as used, or `[]` (`CurrentmA`, `PowermW`, `IrradiancemWmm2`, `PowerUnit`,
  `PowerTyped`, `Date`, `Notes`); and `Device`: `CurrentmA` and `MaxCurrentmA` at the end, `Changes`
  (one row per current sent: session seconds on the LED's clock, channel 1 = A, mA, trial or block)
  and `Package`, the DoricLED package's record of what the driver acknowledged (without its log).
  Irradiance for any current: `lum.led.irradiance(Session.DoricLED.Calibrations{k}, mA)`.
  `DevicesAvailable.DoricLED` is true when the real driver was used
- `SyncFit` — what `lum.sync.fitToCameras` widened so the cameras could read the sync line, one text
  per value (e.g. `'0 bit 20 -> 66.7 ms'`); empty when nothing was. `Settings` and `Barcode.Params`
  hold the fitted values; the settings file keeps the typed ones

### One value per trial

`StimulusGroup`, `PatternIndex`, `CorrectSide`, `Choice`, `Correct`, `Rewarded`, `Outcome`,
`ReactionTime`, `OptoOn`, `SoundOn`, `HouseLight`, `SyncMode`, `SyncPulseWidth`, `BiasTargetPLeft`,
`TrainingStage`, `HoldDuration`, `HoldGrace`, `HoldBreaks`, `HoldAttempts`, `EarlyWithdrawals`,
`CameraTime`, `LEDCurrentA` and `LEDCurrentB`, plus `TrialSettings` (the runtime parameters only) and `OutcomeNames` for decoding
`Outcome`.

Outcome codes are never renumbered. `HoldAttempts` counts how many times the stimulus started on
that trial; `EarlyWithdrawals` how many times the animal left the centre port before the hold was
complete without the break being forgiven (visits to `EarlyWithdrawal`, during the latency or the
hold) — what automatic shaping counts before it steps the hold back. `HoldDuration` shows the
steps. `CameraTime` is the time, in seconds on the video's host clock, at which the trial's events
reached MATLAB (`NaN` without video); see *Video*. `HouseLight` is 1 when the trial started with the
house light on, 0 when off. PulsePal switches the light at once, and its line is looped back into
Bpod's BNC input 1, so a switch during a trial is an event in it: `BNC1High` (switched on) or
`BNC1Low` (switched off) in `RawEvents.Trial{k}.Events`, on the trial's clock (all of them, on the
session's clock, are `Session.HouseLight.Edges`). `HouseLight` is read from those events when there are
any (the first edge gives the level before it), and otherwise is the level PulsePal held as the trial
started. `LEDCurrentA` and `LEDCurrentB` are the LED currents, in mA, the trial ran at on channels A
and B (NaN when the driver was set by hand); a change made in the LED window takes effect from the
next trial prepared after it.

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
  (s), `Channel` (1 = A, 2 = B), `Step`, `Epoch`, `Block` and `CurrentmA` (the LED current of the
  gate's channel as its block was sent; NaN when the driver was set by hand, and absent before
  0.7.0), one value per gate of light sent.
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
- `SessionData.HouseLight` — one value per block: 1 when the block started with the house light on,
  0 when off; switches during a block are `BNC1High`/`BNC1Low` events in it.
- `Session.PlotsImage`, `Session.SyncFit`, `Session.HouseLight`, `DeviceLog.HouseLight`,
  `Session.DoricLED`, `DeviceLog.DoricLED` — as for behaviour.

Per-pulse carrier copies are never stored: the compiled steps are written once.

---

## An ePhys calibration session file

Laid out as a sleep session with test pulses (D18): `Session.Type` is `'EphysCalibration'`,
`Session.Barcode.Kind` is `'EphysCalibration'`, and `SyncPulses`, `LightSegments` (with `CurrentmA`),
`CameraTime`, `HouseLight`, `Session.DoricLED` and the logs are as above. In place of `TestPulses`:

- `Session.Ephys` — `Settings` (`S.Ephys`), `Steps`, `Duration`, `Completed` and `StoppedReason`
  (when PulsePal or the LED driver stopped answering). Each step has, beside the fields of a probe
  step: `Protocol` (`'Input-output'` or `'Paired-pulse ratio'`), `Label` (e.g. `'IO 3/8'`,
  `'PPR 50 ms'`), `CurrentmA` and `IrradiancemWmm2` (1 × 2, A then B; NaN for a channel not used, or
  without a calibration) and `InterPulseInterval` (s, onset to onset; NaN for single pulses).

Each gate's `Step` indexes `Session.Ephys.Steps`, so an input-output curve is the response to each
gate grouped by `LightSegments.CurrentmA` (or the step's irradiance), and a paired-pulse ratio the
second response over the first, grouped by the step's `InterPulseInterval`. Onsets are on Bpod's
clock; the barcode and sync pulses put them on the probe's.

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

**Aligning to Bpod.** Bpod's sync line reaches both cameras' Line0 (from 2026-09-17; `TTL_State` is 0
throughout earlier videos), so each frame log carries the session barcode and every trial pulse (or
sleep sync pulse). Frame-accurate alignment reads them from `TTL_State`, on the camera's own clock:

```matlab
S = SessionData.Session;
T = readtable(S.Cameras.Plan.Cameras(1).CsvFile);             % or spincam.io.readFrameLog
t = double(T.HardwareTimestamp_us) / 1e6;                      % camera clock, s
rise = find(diff(T.TTL_State) == 1) + 1;
fall = find(diff(T.TTL_State) == -1) + 1;
[value, first] = lum.sync.decodeBarcode(t(rise), t(fall), S.Barcode.Params);
assert(isequal(value, S.Barcode.Value), 'This video is not this session');
pulses = rise(first + S.Barcode.Params.nBits + 2:end);         % one per trial after the barcode
n = SessionData.nTrials;                                       % a stopped trial may add one more
fit = polyfit(SessionData.TrialStartTimestamp, t(pulses(1:n))', 1);  % camera = a*bpod + b
bpodTime = (t - fit(2)) / fit(1);                              % each frame on Bpod's session clock
```

A frame samples the line once, so edges are known to one frame period (10 ms at 100 Hz) and each
pulse's width in frames is its Bpod width to within one frame (jittered widths can also match trials
one by one). In a pulsed sync mode the rising edge is `TrialStart`. From 0.6.1 every pulse and gap
is at least two frames long (`lum.sync.fitToCameras`), so none is missed at any frame rate. In the first wired session the camera clock ran 0.037 % fast against Bpod's, and the
straight-line fit left residuals under 6 ms (within a frame).

Without the TTL (older videos, or a camera not wired), fit Bpod's clock to the host clock from the
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

**What the `_ANLG.dat` file is, and whether it is needed.** Bpod's state machine sends Flex analog
samples (here the flow meter on Flex1, at 1 kHz) over its second USB serial link continuously, and
Bpod writes them straight to this binary file as they arrive — a whole session of samples is too much
to keep growing in `BpodSystem.Data` and rewrite at every save. Bpod opens it when the launch
manager starts a session on a state machine with a Flex channel configured as an analog input, and
the samples start with the session's first state machine (the barcode): every session on this rig
has one, and no emulated session does. A session cancelled in its setup dialog leaves an empty
`_ANLG.dat` and no `.mat`; it can be deleted. At teardown `lum.dev.Flex.mergeAnalogData`
closes it and reads it into `SessionData.Analog` (in volts, realigned — below), so **for analysis
the `.mat` is enough**. Keep the `.dat` all the same: it is the raw copy, and the only copy of the
airflow when a session never reaches its teardown (MATLAB or the computer failing). It is about
4 bytes per sample — 0.7 MB for a 3-minute session, 14 MB an hour.

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

- **Sessions before 0.7.0** have no `LEDCurrentA`/`LEDCurrentB`, `LightSegments.CurrentmA` or
  `Session.DoricLED`: the LED was set by hand. Their barcode parameters have no `EphysMarkerWidth`,
  and their house light never switched on at the rig (see `Session.HouseLight` above).
- **Trial sync pulses in sessions from 0.2 to 0.5.0** are ~100 µs glitches, not the recorded
  widths. Align those sessions by the barcode and `Data.TrialStartTimestamp`; see
  [`sync-and-barcode.md`](sync-and-barcode.md).
- **Analog timestamps from 0.2** need `lum.dev.Flex.alignAnalog`, above.
- **The first 0.6.1 sessions** (`FakeSubject_LuminoseFM_20260917_091854` and any other run before the
  house light moved to the plots' header and to PulsePal) have `Settings.GUI.HouseLight` or only
  `Settings.Sleep.HouseLight`, no `Session.HouseLight` record, and switches took effect only at the
  next trial or block: their `Data.HouseLight` is the level through the whole trial or block. Their
  `Session.Subject` may be empty; the subject is in the file name.
- **Sessions before 0.6.1** have 10 ms / 30 ms barcode bits by default, no `Session.SyncFit`, no
  `HouseLight` series and no `Session.PlotsImage` (the house light
  was off in every state), and their settings file holds the settings as Start was pressed, not as
  the session ended.
- **Videos before 2026-09-17** have `TTL_State` 0 in every frame: align them by `CameraTime`.
- **Sessions before 0.6.0** have no `EarlyWithdrawals`, `CameraTime` or `Session.Cameras`, and their
  `Settings.Task.HoldShaping` may be `'Off'` (no `AutoShaping`).
- **Field and state names changed** in 0.2, 0.3, 0.4, 0.5, 0.5.1 and 0.6.0; the full old → new tables are
  in [`naming-and-versions.md`](naming-and-versions.md). Settings files are converted on load;
  analysis code reading old data files needs the old names.
