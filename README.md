# LuminoseFM

Bpod protocol, helper functions and utilities for a **freely-moving two-alternative
forced-choice (2-AFC)** task for the Luminose project.

The task drives a custom behaviour box with three nose ports and delivers patterned
optogenetic stimulation to the olfactory bulb of OSN-ChR mice (channelrhodopsin in olfactory
sensory neurons) through a custom fiber bundle. It also records home-cage sleep, with optional
test pulses of light, runs ePhys calibration sessions (input-output curves and paired-pulse ratios
for the recorded response), sets the Doric LED's intensity from MATLAB, with a calibration to
mW/mm², and records every session on video (§10).

This file is the **operator's guide**: how to run a session and what everything on the screen
means. The rig, the data format and the design live in [`docs/`](docs):

| Document | What is in it |
|----------|---------------|
| [`docs/hardware.md`](docs/hardware.md) | The behaviour box, the channel map, the light path, Flex I/O, the software environment |
| [`docs/data-format.md`](docs/data-format.md) | Every field a session file contains, and how to read older ones |
| [`docs/sync-and-barcode.md`](docs/sync-and-barcode.md) | The sync TTL and the session barcode, for aligning other recordings |
| [`docs/naming-and-versions.md`](docs/naming-and-versions.md) | Glossary, and what changed between versions |
| [`docs/emulator.md`](docs/emulator.md) | Running the whole protocol with no hardware attached |
| [`docs/architecture.md`](docs/architecture.md) | Design decisions (D1–D18) and the map from design to code |
| [`docs/rig-checks.md`](docs/rig-checks.md) | What has been checked on the rig, and the checks still waiting for someone at it |
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
lines, the house light's BNC input, the HiFi module, the Flex I/O configuration, PulsePal, the Doric
LED (the DoricLED package, its bridge, and which cables are calibrated), the liquid calibration
and the data folder. Failures name the exact thing to change and where. The protocol runs it at startup too.

```matlab
report = CheckRig;          % also return it
CheckRig('Strict', true)    % error if anything failed
```

Close Doric Neuroscience Studio before launching: the Doric driver can be opened by one program at a
time.

Launch the protocol from Bpod's launch manager as usual: protocol `LuminoseFM`, subject, settings
file. The protocol starts connecting to the Doric LED driver at once, in the background; the Doric
LED tab of the setup dialog shows when it is connected. The subject you launch for fills the setup dialogs' *Subject* field and every record of the
session; there is nothing to type.

---

## 2. Choosing the kind of session

The first window LuminoseFM opens asks what kind of session is starting:

- **Behaviour** — the 2-AFC task (§3–§6).
- **Sleep** — a home-cage recording: a session barcode, sync pulses and, if chosen, test pulses of
  light on channels A and B (§7).
- **ePhys calibration** — light pulses stepping through intensities (an input-output curve) and
  paired pulses stepping through intervals (a paired-pulse ratio), for the response on the probe (§8).

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
| Habituation | **off** | **on**, for the whole stimulus window | left as it is |
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
| Experiment | Subject (the one launched in the launch manager); whether the **house light** is on as the session starts; genotype (OSN-ChR or wild type offered, any other typed into the box); *Neuropixels recording* (probe, implant, target, coordinates, serial), *EEG/EMG recording* (channel counts), *Drug administration* (name, delivery route, dose and unit, vehicle, time given); session length, devices, runtime window, notes |
| Task | Which task (Familiar/Novel, Mixture, Sequence, Motifs); training stage and what it does to rewards — choosing one sets the session up the way that stage is normally run; trial order, including the contingency reversal; centre hold — how long it is, what a broken hold does, and hold shaping; which components make up the cue, the stimulus and each side; a timeline of one trial, with the hold window |
| Cue | For each cue component (centre light, tone, air): whether it continues through the stimulus, and if not, how long it stays on into it; the cue tone's frequency and sound output, each sound with a **▶ Play** button; a timeline of the cue against the latency and the stimulus, one row per component |
| Stimulus | The stimulus window and its latency from the poke; a summary of the stimulus set with **Design stimuli…** and **New trial order**; P(left) per group; every trial of the session to scroll through; timing of air, centre light and tone, with **▶ Play tones** |
| Light path | The carrier for each channel: frequency, pulse width, and PulsePal's TTL level into the LED driver (5 V) |
| Doric LED | The LED driver (controlled from MATLAB, or set by hand), the fiber bundle and which cables are on A and B, each channel's intensity and limit, and **Calibrate…** (§9) |
| Left, Right | That side's port light and tone (with **▶ Play**), each timed from stimulus onset; its guide light; which groups pay that side |
| Sync | Trial sync pulse mode and widths — every mode is driven by states, and a pulsed one is the trial's first state, so the cue follows it; the session barcode (behaviour, sleep and ePhys calibration marker widths), with a preview. With video, widths are minimums, widened to what the cameras can read |
| Cameras | Video (§10): record or not, the SpinCam folder, format, cameras and their views, frame rate, exposure, gain, TTL input, the camera window — with a **live preview** |
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

### LED window

Opens beside the plots in every session with light (untick *LED window in the session* on the Doric
LED tab to leave it closed). It shows each channel's LED current, and its irradiance when the channel
is calibrated. In behaviour and sleep sessions, type a new intensity and press **Apply**: it is sent
between trials (or sleep blocks), never while light is gated, the channel reads *waiting for the next
trial* until then, and each trial records the current it ran at. The intensity you leave it at is
kept for the next session. In an ePhys calibration session the schedule sets the current, and the
window only shows it.

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
time — and the **House light** box.

**The house light** (the white light inside the box) is switched with that box, and it changes **at
once**, in either direction, whatever the trial is doing. It starts as set on the setup dialog's
Experiment tab, and the level you leave it at is kept for the next session; it goes off when the
session ends. PulsePal drives it (output 3): a session with light does not start without PulsePal,
and one without light runs without it but **without the house light** — a warning says so, the box
is greyed out and the light stays off. Its line is also wired into Bpod's BNC input 1, so each switch during a trial is in the
trial's events (`BNC1High` on, `BNC1Low` off) on Bpod's clock, and on the video's clock too (see
[`docs/data-format.md`](docs/data-format.md) and [`docs/hardware.md`](docs/hardware.md)). If a click
comes while PulsePal is being programmed, the light switches the moment PulsePal is free.

Panels, in the order they are read:

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
legible at any point in it. **Closing the figure does not stop the session** — it only hides it.
When the session ends, however it ends, the figure is saved as it looks then, as
`<data file name>_plots.png` beside the data file.

Bpod's analog viewer also opens, showing the flow meter on Flex1.

---

## 7. Sleep sessions

For recording sleep in the home cage, before or after behaviour. Choose *Sleep* in the first
window; the **sleep setup dialog** then asks only for what a sleep recording needs:

- the animal and the experiment record — the same panels as the behaviour dialog (subject,
  genotype, Neuropixels recording, EEG/EMG recording, drug administration, notes)
- the recording length in minutes, whether Flex2 is driven, and whether the **house light** is on as
  it starts
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
- How bright the light is, the LED current, is set per channel on the sleep dialog's **Doric LED**
  tab (§9); the designer's voltages are PulsePal's TTL level into the driver (5 V).

A schedule is refused before the session starts if it cannot be sent: pulses of a pair that overlap,
epochs too long for their interval, a train step while trains are off, darkness after an epoch too
short to hold a sync pulse, or an epoch so busy that it and the sync pulses that can fall in it do
not fit one state machine.

**The test-pulse designer** sets the probe (single or paired, pulse width, inter-pulse and
inter-epoch intervals), the TTL level on A and B, the plasticity trains (one row per named train)
and the schedule as a table of steps, with presets, the minute each step starts, its epoch count,
and previews of the session and of one epoch of the selected step. Everything compiles on each
edit, and nothing leaves the window until the session could run it.

**PulsePal.** A sleep session with test pulses does not start without PulsePal; one without runs
without it, with the house light (which PulsePal drives) disabled. With test pulses, PulsePal must
also answer a handshake whenever it is given a new carrier and at every
save. If it stops answering, the
session stops, saves what it sent and records why (`Session.TestPulses.StoppedReason`).

**The sleep plot** shows, under a header with the pulse rule, the test pulses, the barcode and the
counts: with test pulses, the schedule across the session with the part already sent shaded; the
last 30 s of the sync line (and of A and B); with test pulses, the latest epoch at millisecond scale
— its gates, and the light in them; the width of every sync pulse against session time; and, with
test pulses, epochs sent against planned, step by step. Its header has the **House light** box,
which switches the light at once, in the middle of a block too; every switch is recorded, and one
made during a block is a `BNC1High`/`BNC1Low` event in it. The light stays as you left it between
blocks. No sound or runtime window is used. Like the behaviour figure, closing it only
hides it, and it is saved as `<data file name>_plots.png` when the session ends.

Every sync pulse and every gate of light is laid out before the first block, and the timeline goes
out in state machines of about 10 s. Uploading the next one lengthens an interval by a few
milliseconds, so a long session runs a little longer than its schedule; every onset in the data is
read from the state machine's clock, not from the plan. How the timeline is cut, and why it is
never cut inside an epoch, is D13 in [`docs/architecture.md`](docs/architecture.md).

---

## 8. ePhys calibration sessions

For calibrating the response to light on the probe: how it grows with intensity, and how a second
pulse compares with the first at different intervals. Choose *ePhys calibration* in the first window.
The **ePhys calibration setup dialog** has three tabs: the session, **Doric LED** (§9) and
**Cameras** (§10).

- **Pulses** — which channels (A, B, or A and B together, each at its own intensity), the pulse width
  (5 ms by default), the interval between epochs (1 s, onset to onset), the repeats per step (10),
  and the order of the steps within each protocol: ascending, descending, or shuffled from a seed.
- **Input-output curve** — single pulses from a lowest intensity (0 by default: pulses with no light,
  a baseline) to a highest one, which has no default and must be given, in a number of levels (8).
  Levels are evenly spaced in irradiance when the channel is calibrated, in mA when not.
- **Paired-pulse ratio** — pairs of pulses at one intensity, one step per inter-pulse interval
  (onset to onset): 20, 30, 50, 75, 100, 200, 300 and 500 ms by default.
- The sync pulses, the house light and the session barcode, as for sleep. The barcode's markers are
  **300 ms** (behaviour 100 ms, sleep 200 ms), so a continuous recording says which kind of session
  each stretch holds.

Intensities are in mW/mm² for a calibrated channel and in mA otherwise. The preview shows the steps
across the session and the intensity of each; the summary says how long it runs. The input-output
curve runs first, then the paired pulses.

The session runs like a sleep session with test pulses: Bpod gates BNC1/BNC2, PulsePal fills each gate
with constant light, and the timeline goes out in state machines cut before every step. **The LED
current is set between steps**, never with light in flight, and each gate is recorded with its step
and current (`LightSegments`, `Session.Ephys`). It needs the LED controlled from MATLAB: on the rig it
does not start otherwise. The live figure shows the steps with progress, the lines, the latest epoch
and the sync pulses. Bpod does not see the response itself: the curves are made from the probe's
recording, aligned by the barcode and sync pulses (§11). How the file is laid out is in
[`docs/data-format.md`](docs/data-format.md#an-ephys-calibration-session-file).

---

## 9. The light's intensity: the Doric LED and its calibration

Bpod and PulsePal decide **when** channels A and B are lit; the Doric LED driver decides **how
bright**. Both LED channels run in *external TTL mode*: channel 1 lights A and channel 2 lights B at
their LED current while PulsePal's output into them is high.

**The Doric LED tab** is in every setup dialog:

- **Control the LED from MATLAB** (on by default) — the session connects to the driver through the
  DoricLED package and sets both channels up. Untick it, or run without the package, and the driver
  is used as set by hand (front panel or Doric Neuroscience Studio), which must then be external TTL
  mode. The tab says where the package was found and whether the driver is connected; **Connect**
  tries again after a replug, and **Doric controls…** opens the package's own window on the same
  connection.
- **Fiber bundle** — the bundle on the animal, and the cable, by colour, on each channel: blue on A and
  green on B by default on the 2-to-19 bundle, orange on A and blue on B on the 4-to-19. If you swap
  the cables at the commutator, swap them here too.
- **Intensity** — per channel: the intensity (mA, or mW/mm² when calibrated), the **limit** in mA
  (700 by default, at most 1000, the LED's rating; anything above is refused, never reduced), the
  light path (cable, fibers, area), the calibration, and **Calibrate…**.

A session with light whose LED is controlled from MATLAB does not start if the driver does not
connect: check its USB cable and power and that Doric Neuroscience Studio is closed, or untick the
control. The protocol switches both channels off when the session ends.

**Calibrating.** Irradiance is the power leaving a cable divided by the area of its fibers at the tip
(each 100 µm across: blue 9 and green 10 on the 2-to-19 bundle; black 4, the others 5 on the
4-to-19). **Calibrate…** opens a window for the cable on that channel, lit through that channel:

1. Hold the power meter at the cable's tip (set to 465 nm). Keep the fiber away from any animal: the
   light is continuous.
2. Choose the meter's unit (**mW** or **uW**). The table lists currents (0–500 mA in 50 mA steps; change
   the range and **Fill**).
3. Select a row and press **Light on**; type the power read; press **Next**, which lights the next row.
   Without a connected driver, set each current on the driver by hand.
4. The graph (current against mW/mm²) fills in as you type. **Save calibration** writes it.

A calibration belongs to the cable, not the channel: the two LED channels are taken to give equal power
at equal current, so a cable moved to the other channel at the commutator keeps its calibration. Each
cable used needs one calibration, on either channel. It is saved in `calibration/` in the protocol
folder (`DoricLED_<bundle>_<cable>.mat`, with a `.png` of the graph), which git does not track, so each
rig keeps its own. Calibrating the same cable again replaces it. From then on every session type, and
the LED window, shows and takes the intensity of whichever channel that cable is on in mW/mm²,
converting with the calibration; a value
outside the currents measured is refused. Settings and data keep mA, and each data file stores the
calibration it used, so irradiance can always be worked out again.

**Checking the light path:** `TestDoricLED` (§13).

---

## 10. Video

Every session — behaviour, sleep or ePhys calibration — is recorded on the box's cameras by
**SpinCam**, the lab's multi-camera package for FLIR cameras (a repository of its own, cloned anywhere). It is on by
default and set up on the setup dialog's **Cameras** tab.

**Once per computer:** install the **Spinnaker SDK with its .NET components** (4.2.0.83 on the rig),
clone SpinCam and run `spincam.setup` in it (it finds Spinnaker and builds its engine with the C#
compiler that ships with Windows). Then, on the Cameras tab, set **SpinCam folder** to where it was
cloned (**Browse…**), or leave it empty if SpinCam is on the MATLAB path. The tab says whether it
found it. After updating Spinnaker or SpinCam, restart MATLAB: the engine rebuilds itself on the
next load. Everything else the computer needs is listed in
[`docs/hardware.md` §3](docs/hardware.md#3-software-environment).

| Field | Default | What it does |
|-------|---------|--------------|
| Record video | on | Record every camera ticked below for the whole session. Untick to run without video |
| Video format | `avi-mjpeg-mt` | How frames are stored (below). Choosing one puts a sentence on what it does in the help line at the foot of the dialog |
| Cameras | 24226887 *sideview*, 24226657 *topview* | One row per camera: serial, view (the file prefix), record, crop. **Find attached** adds attached cameras; **Full frame** clears the crops |
| Frame rate | 100 Hz | For every camera; up to 120 Hz at full frame, above that crop (full viewer) |
| Exposure, gain | Auto | Or a manual value (µs, dB) |
| TTL input | Line0 | The camera input logged with every frame (yellow signal, brown ground) |
| Camera window | shown, 5 Hz | A window with every camera during the session |

Every format is written on SpinCam's own threads, never MATLAB's. Figures are for both cameras at
full frame on the rig:

| Format | What it does |
|--------|--------------|
| `avi-mjpeg-mt` | **Use this.** Compressed MJPEG encoded on several CPU cores: keeps up at 100 Hz for hours and up to 120 Hz, ≈ 27 GB an hour at 100 Hz; opens in `VideoReader`, ffmpeg, OpenCV |
| `avi-mjpeg` | Spinnaker SpinVideo's MJPEG, encoded on one core (≈ 104 frames/s per camera): falls behind at 100 Hz once MATLAB is busy, and the dialog says so. Only with a crop or a lower rate |
| `mp4-h264` | SpinVideo's H.264, the slowest encoder (≈ 70 frames/s per camera): low rates or small crops only |
| `avi-raw` | SpinVideo's "uncompressed" AVI, stored as YUV 4:2:0 (gray levels can shift by a few counts), one core (≈ 110 frames/s per camera) |
| `raw` | Lossless 8-bit frames straight to disk, exact at any rate, ≈ 0.9 TB an hour; read with `spincam.io.RawVideoReader`, convert with `spincam.io.rawToAvi` |

The three SpinVideo formats need Spinnaker's SpinVideo component; without it the session refuses
to start and says so. Leave room on `D:`: a 6-hour sleep session at the defaults is ≈ 160 GB of
video.

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
Bpod's clock onto the video to within a few milliseconds. **The Bpod sync line (Flex2) reaches both
cameras' Line0**, so `TTL_State` also carries the session barcode and every trial pulse frame by
frame: in the first wired session (2026-09-17, 3.3 V TTL, 100 Hz) both cameras logged every one of
the 79 pulses, the barcode decoded from each, and every pulse width matched Bpod's to within a frame.
A frame logs the line once, so a pulse or gap shorter than a frame could be missed: whenever video is
recorded, the session **widens the barcode and the sync pulses to what the cameras can read at the
chosen frame rate** (at least two frames for every pulse and gap), so any frame rate works. The
barcode preview and the status line show the widened values; the settings keep what you typed. `SessionData.Session.Cameras` records the files, the settings and, per camera,
the frames logged, written, missed and dropped.

In the emulator the session records SpinCam's simulated cameras (synthetic video, real files) when
SpinCam is found, and no video otherwise.

---

## 11. Aligning other recordings

The sync TTL on Flex2 marks the session for every other device that records the animal:

- a **session barcode** before the first trial, identifying the session — 32 bits, the seconds
  from 2020-01-01 to the session start, with markers that say whether it was a behaviour (100 ms),
  a sleep (200 ms) or an ePhys calibration (300 ms) session;
- then one **pulse per trial**, in one of three modes (fixed width, jittered width, or task events
  — no pulse, the line's own edges marking trial start and the poke), or, in a sleep or ePhys
  calibration session, one pulse every interval.

To read the barcode back:

```matlab
[value, ~, kind] = lum.sync.decodeBarcode(risingEdges, fallingEdges, SessionData.Session.Barcode.Params);
startTime = lum.sync.barcodeTime(value);   % kind is 'Behaviour', 'Sleep' or 'EphysCalibration'
```

To see what actually reaches the line, put a scope on it and run `TestSyncLine` (§13). Video is
aligned the same way, from each frame's `TTL_State`, and `SessionData.CameraTime` gives a second,
coarser alignment (§10; the code is in [`docs/data-format.md`](docs/data-format.md#video)).

**Sessions before 0.5.1 have no usable trial pulses** — align them by the barcode and
`Data.TrialStartTimestamp`. The full specification, and that story, are in
[`docs/sync-and-barcode.md`](docs/sync-and-barcode.md).

---

## 12. Your data

```
D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>_ANLG.dat
D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>_plots.png
D:\luminoseData\<subject>\LuminoseFM\Session Settings\<settings name>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Videos\<view>_<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.avi / .csv
```

The `.mat` holds one variable, `SessionData`, saved every few trials, so a crash costs at most a
few trials.

- **`_ANLG.dat`** is Bpod's raw recording of the flow meter (Flex1, 1 kHz), written as the session
  runs because Bpod streams analog input straight to disk. At the end of the session it is read
  back into the `.mat` as `SessionData.Analog`, so for analysis the `.mat` is enough. Keep the
  `.dat` anyway: it is the only copy of the airflow if MATLAB or the computer fails before the
  session ends. It is written only when a Flex channel is an
  analog input — not in the emulator. Details in [`docs/data-format.md`](docs/data-format.md).
- **`_plots.png`** is the online figure as it looked when the session ended.
- **LED intensity.** Each behaviour trial records the LED current it ran at on A and B
  (`LEDCurrentA`, `LEDCurrentB`, mA); sleep and ePhys calibration sessions record it per gate of
  light (`LightSegments.CurrentmA`). `SessionData.Session.DoricLED` holds the light paths and the
  calibrations used, so `lum.led.irradiance(SessionData.Session.DoricLED.Calibrations{1}, mA)` gives
  channel A's irradiance.
- **Settings.** The settings file chosen in the launch manager (`DefaultSettings` unless you make
  another) holds the last session's settings: it is written when **Start** is pressed and again
  when the session ends, so runtime changes (reward, timing) and the house light carry over to the next
  session. To keep a set of settings apart — per animal, or per stage — create a new settings file
  in the launch manager and choose it. Every data file also holds the exact settings it ran with,
  in `SessionData.Session.Settings`. Session-level information — the settings, the stimulus set, the rig map, the barcode —
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

## 13. Utilities

Helpers for working with the rig outside a session live in `hardware/`. All of them refuse to run
while a protocol is in progress unless `'Force', true` is passed, and they can be run one after
another from the same MATLAB. What they have shown on this rig, and the checks still to do in person,
are in [`docs/rig-checks.md`](docs/rig-checks.md).

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

### `TestHouseLight` — check the house light and its loopback into Bpod

```matlab
TestHouseLight                     % switch it on and off 5 times, 0.5 s each
TestHouseLight('Count', 20)        % more switches
TestHouseLight('On', 1, 'Off', 2)  % seconds on and off
```

With Bpod running and no protocol in progress, it connects PulsePal, switches the house light on and
off through the same call the House light box makes, and looks for each switch among the state
machine's events as `BNC1High` / `BNC1Low`. It prints one line per switch with its latency (command to
edge, typically a few ms) and says what to check when edges are missing: the light blinking but no
edges means the splitter, the cable into BNC input 1, or the input disabled in the console's port
settings; no blinking means PulsePal output 3 or the LED driver. The light is left off and PulsePal's
port released. Under `Bpod('EMU')` it runs too, with emulated edges.

**Passing on this rig since 2026-09-21**: every switch reaches BNC input 1, 18–33 ms after its
command. Whether the light itself turns on is still to be seen; see P1 in
[`docs/rig-checks.md`](docs/rig-checks.md).

### `TestDoricLED` — check the light path to the fiber

```matlab
TestDoricLED                              % 50 mA, 3 flashes on A, then B, then both
TestDoricLED('Currents', [20 100 300])    % one set per current, brighter each time
TestDoricLED('Count', 5, 'On', 1)         % more, longer flashes
```

With Bpod running and no protocol in progress, it connects the Doric driver, puts both channels in
external TTL mode at the current, programs PulsePal for constant light, and gates BNC1, then BNC2, then
both. Watch the bundle's tip (or a power meter): channel A flashes, then B, then both together, brighter
at each current. It reports every command the driver acknowledged and every gate Bpod ran; the
driver cannot be read back, so the light itself is checked by eye. The light is left off and both
devices released. Under `Bpod('EMU')` it runs on the package's simulated driver.

---

## 14. Working away from the rig

The protocol runs **end to end on a machine with no hardware attached**. Start Bpod with
`Bpod('EMU')` and launch `LuminoseFM` as usual; the port buttons on the Bpod console are how you
poke the ports (centre to initiate, centre again to withdraw, then a side port). No light and no
sound are delivered, there is no sync line, the Doric LED is the DoricLED package's simulated driver
(when the package is found), and the emulator has only five global timers, so a
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
