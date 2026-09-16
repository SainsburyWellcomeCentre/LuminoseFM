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
- one pulse per bit — 10 ms for 0, 30 ms for 1, most significant bit first, each followed by a
  20 ms gap,
- a closing marker.

The markers say what kind of session it is: **100 ms for a behaviour session, 200 ms for a sleep
session**. Its 32 bits are the seconds from 2020-01-01 to the session start, which is also in the
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
therefore starts one pulse width (10–100 ms) after the state machine does — invisible to an
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
