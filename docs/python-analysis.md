# LuminoseFM — Reading the data in Python, and one HDF5 file per session

What a Python package needs to turn a LuminoseFM session (behaviour, sleep or ePhys calibration)
into one HDF5 file for plotting and analysis, and how that file should leave room for what comes
later: Neuropixels recordings from the acquisition PC, pose estimates (DeepLabCut, SLEAP),
movement tracking, behavioural segmentation (keypoint-MoSeq and the like), and histology
registered to an atlas.

This is a specification for the package, written from the MATLAB side. Every field is defined in
[`data-format.md`](data-format.md); the sync line and barcode in
[`sync-and-barcode.md`](sync-and-barcode.md); the stimulus families in
[`stimulus_family.md`](stimulus_family.md). Where this note and those disagree, they win. The Python
snippets have not been run on this computer (it has no Python scientific stack); the file layouts,
clocks and numbers quoted were checked in MATLAB against LUMS0014's sessions of 2026-09-25 to
2026-09-27.

---

## 1. What one session leaves on disk

Per subject: `<data root>\<subject>\LuminoseFM\`, with `<name>` = `<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>`
(the data file's name, Bpod's; the date and time are when the launch manager opened the session).

| File | Folder | Format | Size (LUMS0014, 87 min) | Needed for analysis |
|---|---|---|---|---|
| `<name>.mat` | Session Data | MATLAB v7 (v5 container, zlib), one variable `SessionData` | 21 MB | Yes: everything below that is not video or raw analog |
| `<name>_ANLG.dat` | Session Data | Raw Flex analog stream, `uint16` little-endian | 21 MB | No: the `.mat` holds it as `SessionData.Analog`; keep as the raw copy |
| `<name>_plots.png` | Session Data | The online figure at the end | 0.1 MB | No |
| `<name>_memory.csv` | Session Data | MATLAB's memory after a desktop session (diagnostic) | 5 kB | No |
| `<view>_<name>.avi` | Session Videos | MJPEG AVI (OpenDML), `Mono8` pixels stored as YCbCr 4:2:0 | 22 GB (side), 7 GB (top) | For pose; never copied into HDF5 |
| `<view>_<name>.csv` | Session Videos | One row per frame (SpinCam frame log) | 63 MB each | Yes: frame times and the sync line |
| `<name>_events.csv` | Session Videos | Marks on the camera host clock | 18 kB | Yes: trial ends, house light, session saved |
| `<name>_session.json` | Session Videos | SpinCam's record: cameras, crops, encoder, sync plan, summary | 5 kB | Yes: metadata |
| `NN_<Plot>_PP_<subject>_<stamp>.png` | Session Plots | Summary plots (0.9.8) | 0.5 MB | No |
| `<name>_log.md` | Session Logs | Session log for a notebook (0.9.8) | 5 kB | No (derived from the `.mat`) |
| `<settings>.mat` | Session Settings | `ProtocolSettings`, the last session's settings | 8 kB | No: each session's own are in its `.mat` |

`<view>` is `topview` (camera 24226887) or `sideview` (24226657) on this rig since 0.9.6; before
it, default-named videos are swapped (data-format.md, *Reading older files*): identify cameras by
serial (`CameraID` in the frame log), never by file name.

Neuropixels data are written on another computer (SpikeGLX or Open Ephys); they share nothing
with these files but the sync line (section 4).

## 2. Reading the `.mat`

The file is MATLAB's default `-v7` format, which `scipy.io.loadmat` reads (it is not HDF5; `h5py`
cannot open it). Load it once, as plain objects:

```python
from scipy.io import loadmat

raw = loadmat(path, squeeze_me=True, struct_as_record=False, simplify_cells=True)
sd = raw["SessionData"]          # nested dicts, numpy arrays and lists
```

`simplify_cells=True` turns MATLAB structs into dicts and cell arrays into lists. Things to know:

- **Indices are MATLAB's, from 1**: `PatternIndex`, `StimulusGroup`, `CorrectSide` (1 left, 2
  right), `Choice`, `Session.StimulusSet.SegmentStart`, `LightSegments.Channel` (1 = A, 2 = B),
  `Step`, `Block`, and every menu setting in `TrialSettings` (an index into
  `Session.Settings.GUIMeta.<name>.String`). Keep them 1-based in the HDF5 file, and say so in an
  attribute, or convert all of them in one place; never some.
- **Outcome codes** are `Outcome` 0–6 with names `SessionData.OutcomeNames` (0-based: `Outcome` 0 is
  `OutcomeNames[0]`). They are never renumbered.
- **NaN means absent** (no choice, no video, a trial with no reaction time). Logical values may
  arrive as `uint8` or `bool`.
- **One field holds a MATLAB `string` object**, `Session.DoricLED.Device.Package.Stats.Command`,
  which scipy returns as an opaque `MatlabOpaque` value; skip it. Everything else is struct, cell,
  char, double, logical or small integers (checked on the 2026-09-27 file).
- **Squeezed shapes**: a session of one trial gives scalars where there are usually vectors; wrap
  with `np.atleast_1d`.
- **`RawEvents.Trial[k]`** is a dict with `States` (each state's `[start, end]` rows, one per visit,
  `[nan, nan]` when not visited, seconds from the trial's start) and `Events` (each event's times,
  seconds from the trial's start; a scalar when it happened once). A trial's times on the session
  clock are `TrialStartTimestamp[k] + t`.

The loader should read `Session.ProtocolVersion` first (e.g. `0.9.8+c116669`; before 0.9.8 the
commit is missing on the rig) and branch on it: section 7 lists what changed.

## 3. The clocks

| Clock | What runs it | Where it appears | Notes |
|---|---|---|---|
| **Bpod session clock** (s) | The state machine, 100 µs cycle | `TrialStartTimestamp`, `TrialEndTimestamp`, `RawEvents` (relative to trial start), `Analog.Timestamps`, `SyncPulses.Onset`, `LightSegments.Onset`, `Session.HouseLight.Edges.Time` | Reset when the session starts. **Use it as the session's reference clock.** |
| **Camera hardware clock** (µs) | Each camera | frame log `HardwareTimestamp_us` | One per camera; the best frame intervals. Up to SpinCam engine 1.2.0 (`Session.Cameras.EngineVersion`) it sometimes steps forward by exactly 128 s between two frames, the frame counters continuous (LUMS0014 2026-09-26 both views, 2026-09-28 topview twice): remove the steps before using it (§4). Engine 1.3.0 removes them as it records (`Summary.Cameras(k).TimestampCorrections` counts them); `spincam.io.readFrameLog` repairs older logs in MATLAB |
| **Camera host clock** (s) | SpinCam, on the PC | frame log `HostTime_s`, `_events.csv`, `SessionData.CameraTime` | Shared by both cameras; frame arrival, a few ms after exposure. Anchored to wall time by `_session.json` `HostClockAnchor` |
| **Wall clock** | Windows | `Session.StartTime`/`EndTime`, `HostTimestamp_datetime` | For people, not for alignment |
| **Neuropixels clock** | IMEC or NI card on the acquisition PC | the probe's sync channel | Aligned through the sync line |
| **Video frame index** | the AVI | frame log `VideoFrameIndex` (−1 if not written) | The key between pose estimates and everything else |

**The sync line** (Bpod `Flex2`, a digital output, D4 and D7) carries, in order: the session
barcode (once, before trial 1: two markers around 32 bits, markers 100 ms behaviour, 200 ms sleep,
300 ms ePhys; bit widths in `Session.Barcode.Params`), then one pulse per trial (behaviour; its
rising edge is `TrialStart`, its width `SyncPulseWidth[k]`, jittered 20–100 ms in the default
mode) or the sleep session's sync pulses (`SyncPulses`). It is wired to both cameras' Line0, so it
is in each frame log's `TTL_State` (sampled once a frame), and it is meant to be wired to the
Neuropixels sync input.

## 4. Aligning everything to the Bpod clock

The same recipe for any recording of the sync line (camera, Neuropixels, anything):

1. Find the line's rising and falling edges on that recording's own clock.
2. Decode the barcode (port `lum.sync.decodeBarcode`, below). It must equal
   `Session.Barcode.Value` (`Hex` in text): that proves the recording is this session. Its kind
   (behaviour, sleep, ePhys) comes from the opening marker's width.
3. The rising edges after the barcode's closing marker are the trial pulses: the first `nTrials`
   match `TrialStartTimestamp`. A behaviour session ended with the console's End button (or on an
   error) has
   pulses after them that belong to no recorded trial (*Unrecorded trials at the end*, below):
   up to 0.9.10 **one more**, the trial the End button cut short (LUMS0014: 308 pulses, 307
   trials, every session to 2026-09-28); from 0.9.11 **up to two more**. Use only the first
   `nTrials`. Sleep and ePhys sessions stopped mid-block have `Session.StoppedBlock` describing
   the extra pulses.
4. Fit `recording = a * bpod + b` by least squares over the matched pulses, and check the
   residuals: on LUMS0014 2026-09-27, fitting the camera host clock (`HostTime_s`) gave `a` =
   0.99999091 (9 ppm slower than Bpod's), residuals SD 2.8 ms, largest 6.1 ms (within one 10 ms
   frame).
5. Where pulse widths are jittered, confirm the match pulse by pulse (width in the recording
   against `SyncPulseWidth[k]`, to within a frame for cameras) before trusting it.
6. Discard everything the recording holds after the last recorded trial's end,
   `TrialEndTimestamp[nTrials - 1]` mapped through the fit: frames, spikes, analog samples.

**Unrecorded trials at the end.** From 0.9.11 the next trial is uploaded as each trial starts,
set to start by itself when the running one ends (`RunASAP`, D3). The End button's
`RunProtocol('Stop')` sends the state machine one halt command: it ends the running trial (cut
short, never recorded) and the state machine then starts the trial already queued. That trial
runs with nothing recording it and nothing halting it: the teardown sends no second halt after the
End button. It ends by itself, about a minute later without a poke (the hold window, 60 s by
default) and later if the animal does the trial: its cue light, ports, air and valves work as in
any trial, and its light as long as the LED driver is on (the teardown switches it off). Neither
trial is in the data file, `RawEvents`
or `_events.csv` (no `TrialEnd` row), and their `SyncPulseWidth` is not stored, so their pulses
cannot be matched by width. On the recording:

| Pulse | Starts | Is |
|---|---|---|
| `nTrials + 1` | 0.1 ms after `TrialEndTimestamp[nTrials - 1]` (0.01–0.35 s after it with light, 0.9.8–0.9.10) | the trial the End button cut short |
| `nTrials + 2` (from 0.9.11) | at the End button press | the queued trial, which ran unrecorded |

A session that ran to `MaxTrials` has none (nothing is queued after the last trial); one that ended
on an error can have them too, since its teardown's single `RunProtocol('Stop')` can release a
queued trial the same way. LUMS0014 2026-09-29 (0.9.11): 374
pulses for 372 trials; pulse 373 at trial 372's end, pulse 374 39.7 s later at the press, and the
video stopped 3.3 s after that, so the video does not show how trial 374 ended. Anything the animal did in either trial (a reward, the stimulus air,
pokes) is in the video and any neural recording but in no Bpod record, so the time after
`TrialEndTimestamp[nTrials - 1]` is not usable as a baseline, a rest period or a trial. The Flex
analog stream stops at the press (Bpod stops it in `RunProtocol('Stop')`), so its samples after the
last trial's end cover only the cut-short trial. More extra pulses than this means the pulses and
trials are misaligned: stop.

```python
import numpy as np
import pandas as pd

def edges(t, level):
    """Rising and falling edge times of a 0/1 series sampled at times t."""
    d = np.diff(level.astype(int))
    return t[1:][d == 1], t[1:][d == -1]

def decode_barcode(rise, fall, p):
    """Port of lum.sync.decodeBarcode. p = SessionData['Session']['Barcode']['Params']."""
    widths = np.full(len(rise), np.nan)
    for i, r in enumerate(rise):
        later = fall[fall > r]
        if later.size:
            widths[i] = later[0] - r
    marker = (p["OneWidth"] + p["MarkerWidth"]) / 2
    bit = (p["ZeroWidth"] + p["OneWidth"]) / 2
    markers = np.flatnonzero(widths > marker)
    for a, b in zip(markers[:-1], markers[1:]):
        if b - a - 1 == p["nBits"] and not np.isnan(widths[a + 1:b]).any():
            bits = (widths[a + 1:b] > bit).astype(int)
            value = int((bits * 2 ** np.arange(p["nBits"] - 1, -1, -1)).sum())
            return value, a            # a: index of the opening marker in rise
    return None, None

# Frames of one camera, on the Bpod clock
log = pd.read_csv(csv_path)                     # SpinCam frame log
t = log["HardwareTimestamp_us"].to_numpy() / 1e6
# Up to SpinCam engine 1.2.0 the camera clock sometimes steps forward by exactly 128 s with no
# frame missing: take them out (a no-op on logs from engine 1.3.0, which already did).
steps = np.abs(np.diff(t) - 128) < 0.5
t = t - 128 * np.concatenate([[0], np.cumsum(steps)])
rise, fall = edges(t, log["TTL_State"].to_numpy() == 1)
value, first = decode_barcode(rise, fall, params)
assert value == session["Barcode"]["Value"]
pulses = rise[first + params["nBits"] + 2:]     # one per trial, then up to two unrecorded ones
n = sd["nTrials"]
extra = len(pulses) - n                         # 0; 1: cut short by End; 2 (0.9.11 on): the queued trial too
assert 0 <= extra <= 2, "pulses and trials do not match"
a, b = np.polyfit(sd["TrialStartTimestamp"][:n], pulses[:n], 1)
frame_bpod_time = (t - b) / a
recorded = frame_bpod_time <= sd["TrialEndTimestamp"][n - 1]   # frames after this: discard
```

`TTL_State` is −1 when the line was not read; treat it as missing. Frame edges are known to one
frame period; each pulse lasts at least two frames (`lum.sync.fitToCameras`, 0.6.1), so none is
missed. For Neuropixels, take the edges from the sync channel at the probe's sample rate
(30 kHz AP), and fit per probe (each IMEC card has its own clock); the residuals should be
tens of µs.

Without a sync line (videos before 2026-09-17, or a camera not wired), fit the camera host clock
to `CameraTime` against `TrialEndTimestamp` instead (data-format.md, *Video*): good to a few ms.

## 5. The HDF5 file

One file per session, named as the session (`<name>.h5`), holding numbers and references, never
the video pixels or the raw Neuropixels data (hundreds of GB; referenced by path and checksum).
A subject-level or project-level index (a table of sessions) lives beside it. HDF5 via `h5py`,
chunked and compressed (gzip 4, or lz4 via `hdf5plugin`) for anything over a few thousand
elements.

Conventions for every dataset:

- **Time in seconds on the Bpod session clock** (`t_bpod`), float64. Raw clocks are kept as their
  own columns (`t_camera_hw`, `t_camera_host`, `t_probe`) and the fits in `/sync`.
- **SI units**, stated in an attribute `units` on every dataset (`s`, `uL`, `mA`, `mW/mm^2`, `V`).
- **Tables as groups of equal-length 1-D datasets** (one per column), readable straight into pandas,
  with `index_base` = 0 or 1 as an attribute where a column indexes something.
- **Categorical codes** stored as integers with their names in an attribute (`Outcome`,
  `OutcomeNames`), never as repeated strings.
- **Strings** UTF-8, variable length. Structs with no fixed shape (the settings) as JSON text in a
  dataset, plus the handful of fields analysis filters on promoted to attributes.
- **Missing** is NaN for floats and −1 for integer indices, stated in an attribute.
- **Provenance** on the root: schema version, the converter's version, the source files with their
  size and SHA-256, and the protocol version.

A layout to start from (groups in bold; arrows name the LuminoseFM source):

```
/                                    attrs: schema_version, session_id (<name>), subject, session_type,
                                     start_time, end_time, protocol_version, barcode_hex, emulated,
                                     stopped_reason, rig
/meta/settings                       JSON  <- Session.Settings (as trial 1 was prepared)
/meta/rig                            JSON  <- Session.Rig
/meta/devices                        JSON  <- DevicesAvailable, DeviceLog (text), Startup, LiquidCalibration
/meta/experiment                     JSON  <- Settings.Meta (genotype, Neuropixels, EEG, drug, notes)
/meta/log                            text  <- Session Logs/<name>_log.md (optional)

/stimulus/set                        attrs <- StimulusSet scalars (Family, Duration, BinDuration, Seed, Continuous,
                                     nGroups, EvidenceName, Boundary, Shortcuts, Reversed)
/stimulus/groups                     table: label, p_left, base_p_left, family_p_left
/stimulus/patterns                   table: group, p_left, evidence, a_on, b_on, overlap, dark, b_share,
                                     a_segments, b_segments, n_timers  (one row per pattern)
/stimulus/segments                   table: pattern, channel (1 A, 2 B), onset, duration (s from stimulus onset)

/behaviour/trials                    table, one row per trial <- the per-trial series: t_start, t_end,
                                     pattern, group, correct_side, choice, correct, rewarded, outcome,
                                     reaction_time, hold_duration, hold_grace, hold_breaks, hold_attempts,
                                     early_withdrawals, centre_hold_time, centre_reward, response_retries,
                                     bias_target_p_left, opto_on, sound_on, house_light, training_stage,
                                     sync_mode, sync_pulse_width, led_current_a, led_current_b, camera_time,
                                     reward_amount (from TrialSettings), t_stimulus_onset (last CentreHold entry)
/behaviour/runtime_settings          table, one row per trial <- TrialSettings (one column per runtime setting)
/behaviour/states                    table: trial, state (code), visit, t_start, t_end (t_bpod)
                                     attrs: state_names
/behaviour/events                    table: trial, event (code), t (t_bpod); attrs: event_names
                                     (Port1In..Port3Out, BNC1High/Low, GlobalTimer<i>_Start/_End, Condition<i>)
/behaviour/light                     table: trial, segment, channel, t_on, t_off (t_bpod), current_mA,
                                     irradiance_mW_mm2  <- GlobalTimer<i>_Start/_End with the pattern's segments
/behaviour/timing                    table <- SessionData.Timing (prepare, send, plot, save, memoryGB)

/sleep/sync_pulses                   table <- SyncPulses (onset, width, block)          (sleep and ePhys)
/sleep/light_segments                table <- LightSegments (onset, duration, channel, step, epoch, block, current_mA)
/sleep/steps                         table <- Session.TestPulses.Steps or Session.Ephys.Steps
/sleep/stopped_block                 attrs/table <- Session.StoppedBlock

/analog/flow                         samples (V, float32), t_bpod, trial  <- SessionData.Analog; attrs: rate 1000 Hz,
                                     channel Flex1, device: flow meter

/led/calibration/A, /led/calibration/B   current_mA, power_mW, irradiance_mW_mm2; attrs: bundle, cable, area_mm2,
                                     measured_on, date  <- Session.DoricLED.Calibrations
/led/changes                         table <- Session.DoricLED.Device.Changes

/video/<view>                        attrs: serial, model, file (relative path), sha256, codec (MJPEG), width,
                                     height, offset_x, offset_y (crop on the sensor), frame_rate, exposure, gain,
                                     frames_logged, frames_written, frames_missed, writer_drops
/video/<view>/frames                 table, one row per frame: frame_number, video_frame_index, t_camera_hw,
                                     t_camera_host, ttl, t_bpod (from the fit), dropped, writer_drop
/video/events                        table <- _events.csv (t_camera_host, t_bpod, event, value)

/sync/<recording>                    rising, falling (own clock), barcode_value, pulse_index (-> trial),
                                     attrs: a, b (own = a * t_bpod + b), residual_sd, residual_max, n_matched

/ephys/<probe>                       attrs: probe type, serial, implant, target, coordinates, raw_path (AP/LFP .bin),
                                     sha256, sample_rate, n_channels, software (SpikeGLX/Open Ephys) and version
/ephys/<probe>/channels              table: channel, x_um, y_um, shank, bank, reference, region (after histology)
/ephys/<probe>/units                 table: unit, cluster_id, label (good/mua/noise), best_channel, depth_um,
                                     firing_rate, amplitude, quality metrics, region
/ephys/<probe>/spikes                spike_unit (int32), spike_time (t_bpod, float64); ragged-by-index:
                                     unit_index = start offset per unit, for fast per-unit reads
/ephys/<probe>/sorting               attrs: sorter (Kilosort 4...), version, parameters (JSON), curation

/derived/pose/<tool>/<view>          x, y, likelihood: float32 [frames x keypoints]; attrs: keypoints, skeleton,
                                     model name, training set, tool version, video file + sha256, frame index base
/derived/tracking/<name>             per frame or resampled: centroid, head direction, speed, port occupancy
/derived/segmentation/<tool>         syllable per frame (int), syllable names, model id and version
/derived/<anything>                  one group per derived product, each with its provenance attrs

/histology                           attrs: atlas (e.g. Allen CCF v3, 10 um, via brainglobe), registration tool
                                     and version, transform (JSON or dataset), image paths
/histology/probe_tracks/<probe>      points (x, y, z in atlas space), channel -> region table
```

Keep per-frame data (video frames, pose, segmentation) indexed by `video_frame_index` of one view,
with `t_bpod` for that view alongside, so a pose file from DeepLabCut or SLEAP (which count frames
of the video) joins without resampling. Resample only in derived groups, and record the rate.

**Why not NWB?** NWB (Neurodata Without Borders, `pynwb`) is itself HDF5, and has conventions for
most of the above (`ndx-pose` for DeepLabCut and SLEAP output, `ecephys` for Neuropixels and
sorted units, `TimeIntervals` for trials). The package can write NWB from the same intermediate
objects if the lab needs to share with the DANDI archive; designing the in-memory model first
(section 6) keeps that option open without tying day-to-day analysis to NWB's schema.

## 6. Shape of the Python package

A suggestion:

```
luminose/
  io/
    bpod.py        load the .mat (section 2); version checks; rescoring rules (section 7)
    spincam.py     frame logs, _events.csv, _session.json
    flex.py        _ANLG.dat reader (when the .mat is missing or incomplete)
    ephys.py       SpikeGLX / Open Ephys sync channel, sorter output (Kilosort, phy)
    pose.py        DeepLabCut .h5/.csv, SLEAP .slp/.h5 readers
  sync.py          edges, barcode decode, pulse matching, clock fits, checks
  model.py         dataclasses: Session, Trials, Stimulus, Video, Probe, ... (the in-memory form)
  h5.py            write/read the layout of section 5, versioned
  checks.py        the audits in section 8
  plots/           the summary plots, drawn from an h5 file
  index.py         the subject and project tables
```

The raw Flex analog file, should the `.mat` lack it, is `uint16` samples interleaved as
`[trial, channel 1, …, channel n]` per sample, `n` = `Analog.nChannels` (1 here); volts are
`bits / 4095 * 5`; the rate is `Analog.SamplingRate` (1 kHz):

```python
raw = np.fromfile(dat_path, dtype="<u2")
block = raw.reshape(-1, 1 + n_channels)
trial, volts = block[:, 0], block[:, 1:] / 4095 * 5
```

Its samples start with the barcode's run, which Bpod counts as a trial: in the `.mat`, samples
taken during the barcode have `Analog.TrialNumber` 0 and timestamps corrected to the Bpod clock
(data-format.md). The raw file needs the same correction (`lum.dev.Flex.alignAnalog`).
`Analog.Timestamps` count samples, so they run early after a trial in which the state machine
missed a deadline (`RawData.StateMachineErrorCodes`, 10 ms in LUMS0014 2026-09-29 from trial 316):
for millisecond alignment, take each trial's first sample (`Analog.TrialNumber`) as its
`TrialStartTimestamp`.

## 7. What changed between versions (for the loader)

Read `Session.ProtocolVersion` and apply these; data-format.md, *Reading older files*, has the
full list.

| Before | What to do |
|---|---|
| 0.9.11 | At most one unrecorded trial pulse after the last trial (two from 0.9.11, §4). No `Timing.devices`. From 0.9.8, a session with light has a 0.01–0.35 s gap between every trial's end and the next one's start (`TrialStartTimestamp(k+1) - TrialEndTimestamp(k)`) with no state machine running: pokes then are not in `RawEvents`. The ITI was 0 s by default (0.25 s from 0.9.11). Video from SpinCam engine 1.2.0 or earlier may have 128 s steps in `HardwareTimestamp_us` (§3) |
| 0.9.8 | `Settings.Task.HoldLength` / `FixedHold` are `Settings.GUI.HoldLength` (index: 1 whole stimulus, 2 fixed) / `GUI.FixedHold` from 0.9.8, and per trial in `TrialSettings`. A session with light always reserves the light clock from 0.9.8. Same-side runs could reach `MaxSameSide` + 1. The version string has no commit on the rig |
| 0.9.7 | Sleep and ePhys sessions stopped mid-block have no `StoppedBlock` |
| 0.9.6 | **Rescore**: a side poke after the response window was scored as a choice. Rescore from `RawEvents` (port `lum.scoreTrial`; LUMS0014's first session: 3 trials change). Default-named videos have `topview`/`sideview` swapped: use the camera serial |
| 0.9.5 | No `WaitForLightEnd`; a completed hold shorter than the light cut the light off |
| 0.9.4 | `TrialSettings{k}` is trial *k*+1's runtime tier; shaping stepped from the trial two before |
| 0.9.0 | Older stimulus families and fields (`SweepName`/`SweepValues`) |
| 0.8.0 | No `CentreReward`, `ResponseRetries`, `CentreHoldTime` |
| 0.7.0 | No LED currents; LED set by hand |
| 0.5.1 | Trial sync pulses are ~100 µs glitches: align by the barcode and `TrialStartTimestamp` |
| 0.2 | Analog timestamps need realigning |

Emulated sessions (`Info.EmulatorMode` 1, `Session.Emulated` true) are tests: refuse them unless
asked.

## 8. Checks a conversion should run

The audit done by hand on each LUMS0014 session, which the package should run on every file and
record in the HDF5 file (`/checks`, one row per check with its value and pass/fail):

- every per-trial series has `nTrials` values; `Rewarded` equals the trials that visited a reward
  state; rescoring from `RawEvents` reproduces `Outcome`, `Choice` and `Rewarded` (for 0.9.6 on)
- each completed hold's last `CentreHold` lasted `HoldDuration` (to 0.2 ms)
- side and centre valve states lasted what `Session.LiquidCalibration` gives for the trial's
  volumes
- same-side runs of `CorrectSide` stay within `Settings.Task.MaxSameSide` except where
  `BiasTargetPLeft` pushed towards that side (from 0.9.8)
- the barcode decodes from every recording of the sync line and equals `Session.Barcode.Value`;
  pulses after it = `nTrials`, `nTrials` + 1 or (from 0.9.11, End button) `nTrials` + 2, the extra
  ones where §4 puts them, and everything after the last trial's end flagged unrecorded and left out
  of the analysis; the clock fit's residuals are under one frame
  (cameras) or 0.1 ms (Neuropixels); jittered widths match trial by trial
- per camera: frames logged = frames written, none missed or dropped (`Session.Cameras.Summary`,
  the frame log's `FramesMissedBefore`, `WriterDropFlag`)
- `CameraTime` against the `TrialEnd` rows of `_events.csv` (they agree to a few ms: `CameraTime` is
  read as the mark is made)
- the analog stream covers the session (samples ≈ duration × rate)
- from 0.9.11, each trial starts 0.1 ms after the one before ends, except after a trial with
  `Timing.devices` above its ITI's remaining time (an ITI below 0.25 s); the camera hardware clock
  has no step (engine 1.3.0), or none left once the 128 s ones are removed
- `StoppedReason` is empty, and the session's settings are as the log says

## 9. Numbers from one session, for testing a reader

`LUMS0014_LuminoseFM_20260927_130459` (habituation, 0.9.7): 307 trials in 87 min; 296 rewarded
(152 `Correct`, 144 `Incorrect`, both sides paying), 10 `HoldNotCompleted`, 1 `NoInitiation`;
1177 hold attempts, 881 early withdrawals; 604 µL of water (592 side, 12 centre); barcode
`0CAD3402`; 522,605 frames per camera, none missed or dropped; 308 trial pulses on each camera's
`TTL_State`, the first 307 matching `TrialStartTimestamp` with residuals SD 2.8 ms; 5,235,046
analog samples.
