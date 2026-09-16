# LuminoseFM

Bpod protocol, helper functions and utilities for a **freely-moving two-alternative
forced-choice (2-AFC)** task for the Luminose project.

The task drives a custom behaviour box with three nose ports and delivers patterned
optogenetic stimulation to the olfactory bulb of OSN-ChR mice (channelrhodopsin in olfactory
sensory neurons) through a custom fiber bundle. It also records home-cage sleep, with optional
test pulses of light, and records every session on video (§8).

This file is the **operator's guide**: how to run a session and what everything on the screen
means. The rig, the data format and the design live in [`docs/`](docs):

| Document | What is in it |
|----------|---------------|
| [`docs/hardware.md`](docs/hardware.md) | The behaviour box, the channel map, the light path, Flex I/O, the software environment |
| [`docs/data-format.md`](docs/data-format.md) | Every field a session file contains, and how to read older ones |
| [`docs/sync-and-barcode.md`](docs/sync-and-barcode.md) | The sync TTL and the session barcode, for aligning other recordings |
| [`docs/naming-and-versions.md`](docs/naming-and-versions.md) | Glossary, and what changed between versions |
| [`docs/emulator.md`](docs/emulator.md) | Running the whole protocol with no hardware attached |
| [`docs/architecture.md`](docs/architecture.md) | Design decisions (D1–D14) and the map from design to code |
| [`docs/repository.md`](docs/repository.md) | Where the code lives, and what the test suite covers |

---

## 1. Before the first animal of the day

**Start from a clean slate.** Close MATLAB, then power-cycle the Bpod state machine and PulsePal
(unplug their USB, or switch the powered hub off and on). Do this again after **any session that
ended in an error** — both devices keep state and hold their serial ports, and a stale one gives a
session that looks fine and is not ([why](docs/hardware.md#why-every-session-starts-from-a-clean-slate)).

Then, in MATLAB:

```matlab
Bpod                % start Bpod (or Bpod('EMU') for no hardware)
CheckRig            % preflight report — worth reading before the first animal
```

`CheckRig` prints one line per check: the state machine, the behaviour ports, the optogenetic BNC
lines, the HiFi module, the Flex I/O configuration, PulsePal, the liquid calibration and the data
folder. Failures name the exact thing to change and where. The protocol runs it at startup too.

```matlab
report = CheckRig;          % also return it
CheckRig('Strict', true)    % error if anything failed
```

Launch the protocol from Bpod's launch manager as usual: protocol `LuminoseFM`, subject, settings
file.

---

## 2. Choosing the kind of session

The first window LuminoseFM opens asks what kind of session is starting:

- **Behaviour** — the 2-AFC task (§3–§6).
- **Sleep** — a home-cage recording: a session barcode, sync pulses and, if chosen, test pulses of
  light on channels A and B (§7).

The choice is saved with the subject's settings, so the next launch starts on it, and the data file
records it as `SessionData.Session.Type`.

---

## 3. The task

```
cue on → poke into the centre port → hold through the latency (0 s by default) → the stimulus
    starts; hold while it plays → leave the centre port → poke a side port (left or right)
    → reward, or the cost of a mistake → next trial
```

**The cue lasts until the stimulus starts.** The cue — the centre light, a tone, air, in any
combination (Cue tab) — asks the animal to start a trial. It comes on at trial start and stays
on however long the animal takes to poke the centre port, up to the hold window.

**The latency.** The stimulus starts `Latency` seconds after the poke (Stimulus tab, under the
stimulus window's duration). At 0, the default, it starts on the poke itself, with no state in
between. With a latency the animal holds the centre port through it with the cue still on, and
leaving during it is a broken hold, exactly like leaving during the stimulus.

Once the stimulus starts, each part of the cue either **continues through the stimulus** (the
default) or stays on for a set time into it; 0 switches it off as the stimulus starts.

**The hold.** The animal has to keep its nose in the centre port for the latency, the whole
stimulus window and the post-stimulus hold, counted from the poke; the Task tab shows how long
that is. Only then may it choose.

**The stimulus is delivered only while the animal holds.** If it leaves the centre port
before the hold is over (beyond any forgiven break), the stimulus stops at once. What happens
next is the Task tab's *When the hold breaks*:

- *Restart stimulus* (default) — the stimulus stops, the cue comes back on and the animal has to
  poke again; its next poke starts the latency and the stimulus **from the beginning**. This
  repeats until a hold is completed, or until the **hold window** runs out: `HoldWindow` seconds
  from trial start, counted across every restart. Then the trial lapses and the next one starts.
  The early-withdrawal punishment, if chosen, is applied at each break, before the animal may poke
  again.
- *End trial* — the break is an early withdrawal and the trial ends.

A hold already under way when the hold window ends is allowed to finish.

The withdrawal after a completed hold is part of the contract, not a formality. The side ports
stay inert until the animal has left the centre port, so the beam break it makes on the way out
cannot be scored as a choice, and the reaction time is measured from the withdrawal rather than
from the end of the hold. Never leaving it at all is a non-response.

**Outcomes** (`Data.Outcome`, names in `Data.OutcomeNames`): *NoInitiation* — the hold window ran
out and the stimulus never started; *HoldNotCompleted* — the stimulus started at least once but
every hold broke before the window ran out; *EarlyWithdrawal* — a break ended the trial (*End
trial* only); *NoResponse*, *Correct*, *Incorrect*, *CorrectNoReward*. `Data.HoldAttempts` counts
how many times the stimulus started on each trial.

### Which task

The Task tab's first field says which variant of the task this session runs: *Familiar/Novel*,
*Mixture*, *Sequence* or *Motifs*. It names the kind of stimulus set the session is built around
and is stored with the data (`Session.Settings.Task.Variant`), so a data set can be selected by it.
Choosing one does not yet change any other setting; the per-variant defaults will be added here.

### Training stages

Stage 1 (*Habituation*) rewards **both** side ports, whichever way the animal goes, so it learns
that the side ports pay before it has to learn which one. By default the rewarded ports are also
lit during the response window in habituation (the *guide light*, set per side). Stages 2
(*Training*) and 3 (*Experiment*) reward only the correct side.

Choosing a stage also sets the session up the way that stage is normally run, the moment it is
chosen:

| Stage | Light pattern | Stimulus air | Automatic shaping |
|-------|---------------|--------------|-------------------|
| Habituation | **off** (no PulsePal needed) | **on**, for the whole stimulus window | left as it is |
| Training | on | off | **on** |
| Experiment | on | off | **off** |

Habituation therefore delivers **air alone**: the hold is exactly as long and as salient as it
will be later, and carries nothing to discriminate. Training shapes the centre hold from the
animal's performance; an experiment asks every animal for the same trial. These are defaults, not
a lock — untick or tick anything afterwards and the session runs as you leave it — with one
exception: **an Experiment session cannot start with automatic shaping on.**

### Reversing the contingency

The Task tab's *Contingency: reverse* tick swaps the sides for every group at once: each group's
`P(left)` becomes `1 - P(left)`, so the light that paid left pays right. The table of groups on
the Stimulus tab keeps showing the unreversed numbers — they are what you type — and the status
line says when a reversal is in force. It is applied once, where the stimulus set is compiled, so
the set, the online plots and every trial record agree on the contingency the animal actually
meets: `Session.StimulusSet.GroupPLeft` is the reversed contingency, `BasePLeft` the typed one,
and `Reversed` says which happened.

### Automatic shaping of the centre hold

A naive animal cannot hold its nose in the centre port for a whole stimulus, so the hold is trained
up following the animal's performance. **Automatic shaping** is a tick on the Task tab (*Centre
hold* panel): off by default, switched on by choosing *Training* and off by choosing *Experiment*.
While it is on, the *shaping method* says how:

- *Grow hold* (the default) — the hold starts short (`HoldStart`, **0.1 s**) and grows by
  `HoldGrowth` percent after every trial on which the animal completed it, up to `HoldTarget`
  (**1 s**), normally the stimulus window plus the post-stimulus hold. Light is cut off where a
  shaped hold ends. When the animal **withdraws early `HoldStepBackAfter` times (10) at one hold
  without completing it**, the hold **steps back** one growth step — to the hold it last
  managed — so it can go on learning; withdrawals it makes up for with a completed hold are
  forgiven, and a new hold starts the count again. `HoldStepBackAfter` 0 never steps back. The
  runtime window's header says when a trial's hold stepped back.
- *Shrink grace* — the animal may leave the centre port during the hold and come back within
  a grace period without the break counting. The hold keeps timing while it is out, and the
  stimulus carries on. The grace starts at `GraceStart` and shrinks by `GraceShrink` percent
  after every completed hold, down to `GraceTarget` (normally 0). A break longer than the grace
  is treated as *When the hold breaks* says. Grace is timed from stimulus onset, so a break
  during the latency is never forgiven.

- *Both* — the two together.

With automatic shaping off, the animal holds for the whole stimulus window on every trial. The
shaping parameters are tuned during the session from the runtime window. The hold each trial
required, its grace, the number of forgiven breaks and the number of early withdrawals are
recorded per trial. Later, automatic shaping will also choose easier or harder trial types.

---

## 4. The stimulus

**The stimulus set.** A session's light patterns and the order its trials come in are generated
together, before the first trial, by a port of the generatePattern library. The **stimulus designer** (a button on the setup dialog's
Stimulus tab, or `lum.gui.StimulusDesigner` on its own) shows every parameter and every trial.

A session has **K groups** — its stimulus conditions — delivered equally often in a shuffled
order, or, in **continuous** mode, a new pattern on every trial. The **family** decides what
the patterns look like:

| Family | Patterns | Two groups | More groups sweep |
|--------|----------|------------|-------------------|
| Pure channel | One channel lit from onset for a fraction of the window | A against B | the lit fraction |
| Sequence motif | A motif of joint states repeated for a number of cycles, with a duty cycle per channel | the motif and its A/B mirror | the phase of B against A |
| Occupancy | The window shared between dark, A only, B only and both, as blocks or shuffled | which channel's block comes first | beta, B's share of the light |
| Overlap order | Pure blocks joined by a short and a long overlap guard, never dark | which channel leads across the short guard | the phase of the cycle |
| Tiled order | A and B alternating bin by bin, B the complement of A (a control) | A first against B first | — |
| Hand-drawn pulses | Pulses typed as group, channel, start and end | — | — |

Every family also takes a latency offset per channel (one value, or one per group), wrapping
round the window or falling off the end.

- **Order and seed.** The order is fixed by a seed, so what the setup dialog lets you scroll
  through is exactly what the session runs. Each session draws a new seed unless *draws a new
  seed* is unticked in the designer, for a session that must be repeated exactly.
- **Contingency.** Each group has `P(left)`, the chance the left port pays on its trials: 1
  and 0 give a fixed contingency, values in between a psychometric one. In continuous mode the
  two rows are *A-led* and *B-led* patterns: the channel that leads (overlap order) or is the
  pure channel, or else the one carrying more of the light.
- **Bias correction and the run limit** reorder the order, never change it: to offer the side
  the animal avoids, or to break a run of `MaxSameSide` trials on one side, the next trial is
  swapped with a later one within 50 trials that pays the needed side. Every group is still
  delivered as often as it was balanced. The flip side is that correction can front-load a
  side for a few dozen trials but cannot hold one side above the set's own share for hundreds.
- **What a session refuses.** Every stretch of light on a channel costs one Bpod global timer
  (the rig has 16, the emulator 5; the hold window always takes one, and grace shaping or timed
  components take more). A pattern that needs more is refused, naming its group. Two groups that
  deliver identical light but pay different sides are refused too: that is a task the animal
  cannot solve.

**Other components.** Besides the light pattern, the stimulus can include air, a centre light
flash and a tone (a different frequency for each group), each timed from stimulus onset. The
**Left** and **Right** tabs set outputs delivered on trials rewarded on that side — the side
port's light and a side tone, each timed from stimulus onset — and the guide light. A component
on for the whole window is free; one that starts late or ends early uses a global timer. Sounds
never do: a delayed tone is loaded with silence in front of it. The same holds for the cue once
the stimulus starts: a cue light or air that goes off part way through the stimulus uses a timer,
the cue tone does not. The HiFi module plays **one sound at a time** — a new sound cuts off the
one playing — so a session is refused if more than one of the stimulus tone, the side tone and a
cue tone that continues into the stimulus would start with the stimulus.

---

## 5. The windows

### Session setup

Shown once, before the first trial. Everything on it is validated on every edit; the status line
says what is wrong, and **Start session** stays disabled until nothing is.

| Tab | What it holds |
|-----|---------------|
| Experiment | Subject (from the launch manager); genotype (OSN-ChR or wild type offered, any other typed into the box); *Neuropixels recording* (probe, implant, target, coordinates, serial), *EEG/EMG recording* (channel counts), *Drug administration* (name, delivery route, dose and unit, vehicle, time given); session length, devices, runtime window, notes |
| Task | Which task (Familiar/Novel, Mixture, Sequence, Motifs); training stage and what it does to rewards — choosing one sets the session up the way that stage is normally run; trial order, including the contingency reversal; centre hold — how long it is, what a broken hold does, and hold shaping; which components make up the cue, the stimulus and each side; a timeline of one trial, with the hold window |
| Cue | For each cue component (centre light, tone, air): whether it continues through the stimulus, and if not, how long it stays on into it; the cue tone's frequency and sound output, each sound with a **▶ Play** button; a timeline of the cue against the latency and the stimulus, one row per component |
| Stimulus | The stimulus window and its latency from the poke; a summary of the stimulus set with **Design stimuli…** and **New trial order**; P(left) per group; every trial of the session to scroll through; timing of air, centre light and tone, with **▶ Play tones** |
| Light path | The fiber bundle and which cables are on A and B; the carrier for each channel (frequency, pulse width, LED drive voltage) |
| Left, Right | That side's port light and tone (with **▶ Play**), each timed from stimulus onset; its guide light; which groups pay that side |
| Sync | Trial sync pulse mode and widths — every mode is driven by states, and a pulsed one is the trial's first state, so the cue follows it; the session barcode (behaviour and sleep marker widths), with a preview |
| Cameras | Video (§8): record or not, the SpinCam folder, format, cameras and their views, frame rate, exposure, gain, TTL input, the camera window — with a **live preview** |
| Runtime | Starting values of the parameters that stay editable during the session |

Ticking a component on the Task tab switches it on: its rows light up on the tab that times it,
and that tab's title counts the components on.

**The help line** at the foot of the window says what the field under the pointer does — or the
one you just used — so a setting such as bias correction is explained where it is set.

**Play buttons** play a sound of the session with the settings as they stand in the dialog —
sampling rate, amplitude, attenuation, and the sound's own frequency and duration — through the
HiFi module, or the PC's speakers when there is none (the emulator). The cue tone plays for 0.5 s;
*Play tones* plays each group's stimulus tone in turn. The small logo in the header is from
[`docs/logo`](docs/logo).

### Runtime window

The parameters that are safe to change with an animal in the box, synced once per trial. On the
rig it is a window of its own, in tabs (*Trial*: reward and timing; *Task*: punishment, bias
correction, hold shaping; *Delivery*: light, sound and port light brightness), with labels and
units, limits held as values are typed, and a header saying how the last trial ended and what is
running now. Under the emulator the reduced form opens instead — Bpod's own single-page parameter
window, relabelled. `Runtime window` on the Experiment tab can force either.

- *Punishment* is two choices: which mistakes are punished (none / early withdrawal / incorrect
  choice / both) and how (timeout / white noise / both).
- *Bias correction* pushes trials towards the side the animal has been avoiding. If it chose left
  on a fraction *f* of its last `BiasWindow` choices, the next trial pays left with chance
  0.5 + strength × (0.5 − *f*), kept within 0.1–0.9, by bringing forward a trial that pays that side:
  0 is off, 1 full compensation. Every group is still delivered as often; only the order changes.

Every parameter describes itself on the help line at the foot of the window (a tooltip in the
compact window).

Bpod's notebook plugin is also initialised, for manual annotation during the session.

### Designers

Both open on their own, away from the rig, and return the settings they built:

```matlab
S = lum.gui.StimulusDesigner();    % sized to the connected machine's timers
S = lum.gui.TestPulseDesigner();   % defaults: paired-pulse probes on A and B for 4 hours
```

---

## 6. Watching a session

One figure, updated in place once per trial, with a header giving the subject, stage, stimulus
set, what a broken hold does, trial count, performance, rewards and water delivered, and session
time. Panels, in the order they are read:

- Top row
  - **Now and next** (top left) — the pattern of the running trial and the next three in the order,
    channel A above B, with the side each pays; shown from the moment the session starts
  - **Outcomes** — each trial's choice by stimulus group (by the B share of its light in continuous
    mode): correct, incorrect or no choice
- Middle row
  - **Performance** — fraction correct over a moving window, for all, left- and right-rewarded trials
  - **Psychometric** — P(choose left) with error bars, laid out for the stimulus set: one point for
    one group, the groups for two, along the swept parameter for more, in B-share bins for
    continuous patterns — with the contingency drawn behind it
  - **Evidence, u_A vs u_B** — every choice at the latent evidence its trial's stimulus carried on
    each channel: u_A and u_B, the fraction of the stimulus window channel A and channel B were lit.
    Points are filled green when correct and outlined red when not, and point left (◀) or right (▶)
    for the side chosen. An animal reading one channel separates its left and right choices along a
    vertical or horizontal boundary; one weighing both, along a diagonal. Light-off trials sit at
    the origin, and a small fixed jitter keeps repeated patterns visible.
- Bottom row
  - **By side** — fraction correct on left- and right-rewarded trials
  - **Side bias** — P(chose left) over the last `BiasWindow` choices (as set when the session
    started), with the P(left) that bias correction aimed for on each trial
  - **Reaction time** — by side chosen, with a running median

The per-trial panels scroll with the session and rescale to what is on screen, so they stay
legible at any point in it. **Closing the figure does not stop the session.**

Bpod's analog viewer also opens, showing the flow meter on Flex1.

---

## 7. Sleep sessions

For recording sleep in the home cage, before or after behaviour. Choose *Sleep* in the first
window; the **sleep setup dialog** then asks only for what a sleep recording needs:

- the animal and the experiment record — the same panels as the behaviour dialog (subject,
  genotype, Neuropixels recording, EEG/EMG recording, drug administration, notes)
- the recording length in minutes, and whether Flex2 is driven
- the sync pulses: widths (*Fixed width* or *Jittered width*, as for behaviour trials), the
  interval between pulses and an optional jitter on it
- the session barcode, with its **sleep marker** (200 ms by default) and a preview
- the **test pulses**, if any, designed in the test-pulse designer (below)

When started, the session sends the sleep barcode, then one sync pulse every interval — and the
test pulses, on their schedule — until the recording is over or the session is stopped from the
console.

### Test pulses

Light on channels A and B during the recording, to probe the bulb's response to it and to change
that response. It goes out exactly as a behaviour stimulus does: Bpod drives BNC1 and BNC2, and
PulsePal, in gated mode, fills each gate.

- A **probe** is one *epoch* every *inter-epoch interval* (2 s by default): a single pulse, or a
  pair of pulses an *inter-pulse interval* apart (50 ms), each 10 ms of constant light. Both
  intervals are onset to onset.
- **Plasticity trains**, once switched on, are named definitions: bursts of pulses at a pulse
  frequency, bursts at a burst frequency, a number of trains a train interval apart. Bpod gates each
  burst and PulsePal puts the pulses in it. Provided: *Theta burst* — 10 bursts of 4 pulses (5 ms)
  at 100 Hz, bursts at 4 Hz, 5 trains 20 s apart — and *High frequency* — 100 pulses (5 ms) at
  100 Hz, 4 trains 20 s apart. Any other can be added.
- The **schedule** is a list of steps run in order from the start of the recording: a probe or rest
  for so many minutes, or a train (which lasts its trains), on A and B together, on one of them, or
  alternating between them epoch by epoch. The default is paired-pulse probes on A and B for
  4 hours. **The recording lasts as long as the schedule.**
- The LED drive is set per channel, in volts.

A schedule is refused before the session starts if it cannot be sent: pulses of a pair that overlap,
epochs too long for their interval, a train step while trains are off, darkness after an epoch too
short to hold a sync pulse, or an epoch so busy that it and the sync pulses that can fall in it do
not fit one state machine.

**The test-pulse designer** sets the probe (single or paired, pulse width, inter-pulse and
inter-epoch intervals), the LED drive on A and B, the plasticity trains (one row per named train)
and the schedule as a table of steps, with presets, the minute each step starts, its epoch count,
and previews of the session and of one epoch of the selected step. Everything compiles on each
edit, and nothing leaves the window until the session could run it.

**PulsePal.** A sleep session with test pulses does not start without PulsePal, and PulsePal must
answer a handshake whenever it is given a new carrier and at every save. If it stops answering, the
session stops, saves what it sent and records why (`Session.TestPulses.StoppedReason`).

**The sleep plot** shows, under a header with the pulse rule, the test pulses, the barcode and the
counts: with test pulses, the schedule across the session with the part already sent shaded; the
last 30 s of the sync line (and of A and B); with test pulses, the latest epoch at millisecond scale
— its gates, and the light in them; the width of every sync pulse against session time; and, with
test pulses, epochs sent against planned, step by step. No sound or runtime window is used.

Every sync pulse and every gate of light is laid out before the first block, and the timeline goes
out in state machines of about 10 s. Uploading the next one lengthens an interval by a few
milliseconds, so a long session runs a little longer than its schedule; every onset in the data is
read from the state machine's clock, not from the plan. How the timeline is cut, and why it is
never cut inside an epoch, is D13 in [`docs/architecture.md`](docs/architecture.md).

---

## 8. Video

Every session — behaviour or sleep — is recorded on the box's cameras by
**SpinCam**, the lab's multi-camera package for FLIR cameras (a repository of its own, cloned anywhere). It is on by
default and set up on the setup dialog's **Cameras** tab.

**Once per computer:** clone SpinCam and run `spincam.setup` in it (it finds Spinnaker and builds its
engine). Then, on the Cameras tab, set **SpinCam folder** to where it was cloned (**Browse…**), or
leave it empty if SpinCam is on the MATLAB path. The tab says whether it found it.

| Field | Default | What it does |
|-------|---------|--------------|
| Record video | on | Record every camera ticked below for the whole session. Untick to run without video |
| Video format | `avi-mjpeg-mt` | `avi-mjpeg-mt` is MJPEG encoded on several cores: two full-frame cameras at 100 Hz for hours (≈ 27 GB/h), and up to 120 Hz. `avi-mjpeg` is SpinVideo's one-core encoder, which falls behind at 100 Hz full frame (the dialog says so); `raw` is lossless (≈ 0.9 TB/h); `mp4-h264`, `avi-raw` |
| Cameras | 24226887 *sideview*, 24226657 *topview* | One row per camera: serial, view (the file prefix), record, crop. **Find attached** adds attached cameras; **Full frame** clears the crops |
| Frame rate | 100 Hz | For every camera; up to 120 Hz at full frame, above that crop (full viewer) |
| Exposure, gain | Auto | Or a manual value (µs, dB) |
| TTL input | Line0 | The camera input logged with every frame (yellow signal, brown ground) |
| Camera window | shown, 5 Hz | A window with every camera during the session |

**Preview** connects the ticked cameras exactly as the session will and shows them; frame rate,
exposure and gain apply live. **Simulated cameras** previews SpinCam's synthetic cameras on a
computer without cameras. **Full viewer…** opens SpinCam's own viewer on the same cameras, for
cropping and the finer controls; what it leaves (crop, names, frame rate, exposure, gain) is read
back when it closes. Preview releases the cameras when stopped and when the dialog closes, and
**SpinView must be closed**: a camera can be streamed by only one program.

**During the session** recording starts before the session barcode and stops only once the session's
data are saved, so every trial in the data file is on the video (the recording summary is then added
to the file).
SpinCam grabs, encodes and logs every frame on threads of its own, so the video never waits for
Bpod and Bpod never waits for the video. The **camera window** shows each camera with its frame
rate, missed frames, frames written, writer drops and TTL input; closing it does not stop the
recording. On the rig, a session that asks for video **does not start** when SpinCam or a ticked
camera is missing — untick *Record video* or the camera to run without it.

**Files**, beside the session's data, named after it:

```
D:\luminoseData\<subject>\LuminoseFM\Session Videos\sideview_<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.avi
D:\luminoseData\<subject>\LuminoseFM\Session Videos\sideview_<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.csv
D:\luminoseData\<subject>\LuminoseFM\Session Videos\topview_<...>.avi / .csv
D:\luminoseData\<subject>\LuminoseFM\Session Videos\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>_events.csv
D:\luminoseData\<subject>\LuminoseFM\Session Videos\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>_session.json
```

Each `.csv` has one row per frame: `HostTime_s` (seconds on the host clock), `HardwareTimestamp_us`
(the camera's clock — use it for intervals), `TTL_State`, `VideoFrameIndex` and drop flags. Every
trial (every block, in a sleep session) is marked on the same host clock: a `TrialEnd` row in
`_events.csv`, and `SessionData.CameraTime`, so `CameraTime` against `TrialEndTimestamp` maps
Bpod's clock onto the video to within a few milliseconds. **The Bpod sync line is not yet wired to
the cameras**, so `TTL_State` stays 0; once it is, the barcode and the trial pulses mark the video
frame by frame. `SessionData.Session.Cameras` records the files, the settings and, per camera,
the frames logged, written, missed and dropped.

In the emulator the session records SpinCam's simulated cameras (synthetic video, real files) when
SpinCam is found, and no video otherwise.

---

## 9. Aligning other recordings

The sync TTL on Flex2 marks the session for every other device that records the animal:

- a **session barcode** before the first trial, identifying the session — 32 bits, the seconds
  from 2020-01-01 to the session start, with markers that say whether it was a behaviour (100 ms)
  or a sleep (200 ms) session;
- then one **pulse per trial**, in one of three modes (fixed width, jittered width, or task events
  — no pulse, the line's own edges marking trial start and the poke), or, in a sleep session, one
  pulse every interval.

To read the barcode back:

```matlab
[value, ~, kind] = lum.sync.decodeBarcode(risingEdges, fallingEdges, SessionData.Session.Barcode.Params);
startTime = lum.sync.barcodeTime(value);   % kind is 'Behaviour' or 'Sleep'
```

To see what actually reaches the line, put a scope on it and run `TestSyncLine` (§11). Video is
aligned the same way once the sync line reaches the cameras, and by `SessionData.CameraTime` until
then (§8).

**Sessions before 0.5.1 have no usable trial pulses** — align them by the barcode and
`Data.TrialStartTimestamp`. The full specification, and that story, are in
[`docs/sync-and-barcode.md`](docs/sync-and-barcode.md).

---

## 10. Your data

```
D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Settings\<settings name>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Videos\<view>_<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.avi / .csv
```

The `.mat` holds one variable, `SessionData`, saved every few trials, so a crash costs at most a
few trials. Session-level information — the settings, the stimulus set, the rig map, the barcode —
is stored **once** in `SessionData.Session`; each trial stores only its own events, timestamps,
outcome and indices into it. Airflow from the flow meter is merged in at the end of the session as
`SessionData.Analog`.

To get trial *k*'s light:

```matlab
p = lum.pattern.patternAt(SessionData.Session.StimulusSet, SessionData.PatternIndex(k));
```

`SessionData.Session.StoppedReason` is empty for a session that ran to its end or was stopped from
the console, and the error message for one that failed — a session that errors still saves the
trials that completed, merges the analog stream and releases the rig.

Every field, and what to watch for in files from older versions, is in
[`docs/data-format.md`](docs/data-format.md).

---

## 11. Utilities

Helpers for working with the rig outside a session live in `hardware/`. All of them refuse to run
while a protocol is in progress unless `'Force', true` is passed.

### `CheckRig` — preflight

See §1. Checks that cannot mean anything without hardware are reported as skipped in emulator mode.

### `TestHiFiSound` — play a test sound

The setup dialog's **▶ Play** buttons play the session's own sounds (§5). The Bpod console can
exercise ports, valves, LEDs and BNC lines by hand, but not sound.
`TestHiFiSound` connects to the HiFi module, plays a waveform and disconnects, without launching
a protocol:

```matlab
TestHiFiSound                                   % 1 kHz tone, 0.5 s, both channels
TestHiFiSound('Frequency', 8000)                % 8 kHz tone
TestHiFiSound('Waveform', 'noise')              % white noise burst
TestHiFiSound('Waveform', 'sweep', 'FreqRange', [2000 20000])
TestHiFiSound('Channel', 'left')                % check speaker wiring
TestHiFiSound('Repeat', 5, 'Interval', 0.25)    % repeated beeps
TestHiFiSound('Attenuation', -20)               % quieter (dB FS, <= 0)
TestHiFiSound('Port', 'COM8')                   % explicit port, Bpod not running
TestHiFiSound('Device', 'pc')                   % play on the PC's own speakers
```

The module's USB port is taken from `BpodSystem.ModuleUSB.HiFi1`, so Bpod must be running and the
module USB-paired — otherwise pass `'Port'`. With no module reachable, or in emulator mode,
playback falls back to the PC audio device. `help TestHiFiSound` lists all options.

### `TestSyncLine` — see what reaches the sync line

```matlab
TestSyncLine                       % 10 x 50 ms pulses on Flex2DO, driven both ways
TestSyncLine('Drive', 'states')    % only the way the protocol drives it
TestSyncLine('Channel', 'BNC2')    % a different output channel
TestSyncLine('Barcode', true)      % finish with a real, decodable session barcode
```

Put a scope, a logic analyser or the acquisition system itself on the line and run it. It sends the
same train twice — once from **states**, the way the protocol drives it, and once from a **global
timer** — so the line and the way it is driven can be told apart. Nothing here touches the animal:
no valve, no LED, no optical channel.

---

## 12. Working away from the rig

The protocol runs **end to end on a machine with no hardware attached**. Start Bpod with
`Bpod('EMU')` and launch `LuminoseFM` as usual; the port buttons on the Bpod console are how you
poke the ports (centre to initiate, centre again to withdraw, then a side port). No light and no
sound are delivered, there is no sync line, and the emulator has only five global timers, so a
pattern with more than four stretches of light is refused there and accepted on the rig. Emulated
sessions still write a complete data file, flagged `Data.Info.EmulatorMode = 1`, and record video
from SpinCam's simulated cameras when SpinCam is found.

The differences that matter, and how to read the console when it disagrees with the rig, are in
[`docs/emulator.md`](docs/emulator.md).

The test suite needs no hardware and **refuses to run against a real state machine**, so it is safe
on the rig computer whenever a session is not in progress:

```matlab
addpath('tests');
runLuminoseTests                              % everything
runLuminoseTests('Filter', {'generateTest'})  % one file
```

What it covers is listed in [`docs/repository.md`](docs/repository.md).
