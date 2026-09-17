# LuminoseFM — Sync TTL and session barcode

How LuminoseFM marks time for every other device that records the animal. The design record is
D4 and D7 in [`architecture.md`](architecture.md); the user-facing summary is in
[`../README.md`](../README.md).

Both the barcode and the trial pulses go out on **Flex2**, which has to be configured as a
digital output, and from there to a powered BNC splitter feeding the acquisition devices
(Neuropixels OneBox or NI-1083, cameras, and so on). `S.Session.UseSync` says whether the line
is driven at all.

---

## Session barcode

Before the first trial the line carries one barcode that identifies the session on every device
that records it:

- a marker pulse,
- one pulse per bit — 20 ms for 0, 50 ms for 1, most significant bit first, each followed by a
  20 ms gap,
- a closing marker.

The markers say what kind of session it is: **100 ms for a behaviour session, 200 ms for a sleep
session**. These are the defaults, and minimums: with video they are widened to what the cameras
can read (below). Before 0.6.1 the bits were 10 and 30 ms. Its 32 bits are the seconds from 2020-01-01 to the session start, which is also in the
data file's name.

To read it from a recording:

```matlab
[value, ~, kind] = lum.sync.decodeBarcode(risingEdges, fallingEdges, SessionData.Session.Barcode.Params);
startTime = lum.sync.barcodeTime(value);   % kind is 'Behaviour' or 'Sleep'
```

The barcode is sent as its own state machine before the trial runner is created, which is why
Bpod counts it as a trial for the Flex analog stream — see the realignment note in
[`data-format.md`](data-format.md).

---

## Trial pulses

Three modes (`S.Sync.Mode`, `lum.SyncMode`), and every one of them drives the line from
**states**, so none costs a global timer:

- *Fixed width* — one pulse per trial, always the same length: enough to count trials.
- *Jittered width* — one pulse per trial, its width drawn uniformly within a jitter either side of
  a mean. The widths are near-unique, so a recording is matched to `Data.SyncPulseWidth` trial by
  trial rather than by counting edges. (Called *Random width* before version 0.2.)
- *Task events* — no pulse: the line goes high at trial start, stays high while the animal is
  asked to poke, and goes low when it pokes the centre port, so its own edges mark the events.

In a pulsed mode the pulse **is** the trial's first state: `TrialStart` drives the line high and
lasts the pulse's width, and `WaitForCentrePoke` drives it low as the cue comes on. The cue
therefore starts one pulse width (20–100 ms by default) after the state machine does — invisible to an
animal whose only sign that a trial has begun is the cue itself, and it makes the rising edge an
exact marker for the cue as well.

The mode is part of the data format — it decides what a rising edge in the ephys file means — so
it is written to every trial record as `Data.SyncMode`. Modes are appended, never renumbered.

### Sessions before 0.5.1 have no usable trial pulses

Until then the pulse was a global timer linked to the sync channel, triggered in `TrialStart` —
whose state timer was 0. Bpod writes every output channel from the entered state's own row, so
`WaitForCentrePoke`, reached one state-machine cycle later, wrote the line low again and the pulse
reached the recording as a ~100 µs glitch. The session barcode was never affected: its every edge
is a state.

To align a session from 0.2–0.5.0, use the barcode and `Data.TrialStartTimestamp` rather than
looking for trial pulses.

---

## Reading it from the video

Flex2 reaches both cameras' Line0 through the splitter (3.3 V TTL, since 2026-09-17), and SpinCam
logs the line with every frame as `TTL_State`, so the barcode and every trial pulse are in each
camera's frame log. A frame samples the line once: an edge is known to one frame period, a pulse's
width to within one frame, and a pulse or gap shorter than a frame can be missed.

**So the line is fitted to the cameras, automatically** (`lum.sync.fitToCameras`, from 0.6.1).
Whenever a session records video, every width typed for the barcode, the trial pulses and a sleep
session's sync pulses is treated as a minimum, and at session time whatever the frame period *T*
(1 / frame rate) could make unreadable is widened:

| Element | Rule | At 100 Hz (defaults) | At 30 Hz |
|---------|------|----------------------|----------|
| 0 bit, gap after each pulse | ≥ 2 *T* | 20 ms, 20 ms | 66.7 ms, 66.7 ms |
| 1 bit | ≥ 0 bit + 3 *T* | 50 ms | 166.7 ms |
| behaviour marker | ≥ 1 bit + 3 *T* | 100 ms | 266.7 ms |
| sleep marker | ≥ behaviour marker + 3 *T* | 200 ms | 366.7 ms |
| trial or sleep pulse | shortest ≥ 2 *T*; a jittered range keeps its spread | 20–100 ms | 66.7–146.7 ms |

A high or low time of *n T* is seen as *n* − 1 to *n* + 1 frames, so 2 *T* is never missed, and 3 *T*
between neighbouring widths keeps them apart at the decoder's thresholds even when the camera runs
5 % slower than set (tested at 25–150 Hz, every phase, both kinds). The number of bits never changes,
and the barcode takes longer at a low rate (about 2 s at 100 Hz, 7 s at 30 Hz). The settings file
keeps what was typed; the session sends and records the fitted values (`Session.Barcode.Params`,
`SyncPulseWidth`, `SyncPulses.Width`, `Session.Settings`), lists what changed in `Session.SyncFit`,
and prints it; the setup dialogs' barcode preview and status line show it before Start. A sleep
interval that leaves under two frames between pulses cannot be widened, and is refused. Task-event
mode has no pulse to widen: its high time is the wait for the poke.

In the first wired session,
at 100 Hz, both cameras logged all 34 barcode pulses and all 45 trial pulses (the last from the trial
the End button stopped, which is not in the data file), decoded the barcode, and matched every trial
pulse's width to Bpod's within a frame. The code to align frames to Bpod's clock is in
[`data-format.md`](data-format.md#video).

---

## Sleep sessions

A sleep session sends the sleep barcode and then one sync pulse every interval (fixed or jittered
width, with an optional jitter on the interval), recorded in `SessionData.SyncPulses`. Test
pulses of light share the same timeline; both are laid out before the first block and sent as
state machines of about 10 s. See D13 in [`architecture.md`](architecture.md).

---

## Checking the line

`TestSyncLine` drives the line outside a session, so the line and the way it is driven can be
told apart on a scope:

```matlab
TestSyncLine                       % 10 x 50 ms pulses on Flex2DO, driven both ways
TestSyncLine('Drive', 'states')    % only the way the protocol drives it
TestSyncLine('Channel', 'BNC2')    % a different output channel
TestSyncLine('Barcode', true)      % finish with a real, decodable session barcode
```

It sends the same train twice: once from **states**, the way the barcode and (from 0.5.1) the
trial pulses are sent, and once from a **global timer** linked to the channel, the way trial
pulses were sent before. If one train arrives and the other does not, the line is fine and the way
it was driven is not.

On 2026-09-17 (0.6.1) both cameras' `TTL_State` decoded the barcode and logged every pulse, in a
behaviour session (15 trial pulses) and in a sleep session with test pulses (32 sync pulses). Each
width and interval matched Bpod's to within one frame ([`rig-checks.md`](rig-checks.md)).
