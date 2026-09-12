# LuminoseFM

Bpod protocol, helper functions and utilities for a **freely-moving two-alternative
forced-choice (2-AFC)** task for the Luminose project.

The task drives a custom behaviour box with three nose ports and delivers patterned
optogenetic stimulation to the olfactory bulb of OSN-ChR mice (channelrhodopsin in
olfactory sensory neurons) through a custom fiber bundle.

---

## 1. Behaviour box

Red acrylic box, **18 × 18 × 23 cm** (w × l × h). Three behaviour ports sit at a height of
1.2 cm, spaced 6 cm centre-to-centre. The box stands on a base plate and has a cover that
lets wires pass through while making it hard for the mouse to climb out.

Drawings: [`docs/behaviour_box_design/`](docs/behaviour_box_design)

**Sleep recordings.** A red acrylic cover slots onto the home cage so that pre- or
post-behaviour sleep can be recorded without disconnecting tethered optical patch cords
and/or Neuropixels cables. The protocol runs these as *sleep sessions* (§4.8).

---

## 2. Hardware

The rig is controlled by a [Bpod Finite State Machine r2+](https://sanworks.github.io/Bpod_Wiki/assembly/state-machine-assembly-2%2B/),
connected to the computer over USB. The full list of channels and events is available from
`BpodSystem.StateMachineInfo`, and is captured in [`docs/BpodSystemInfo.png`](docs/BpodSystemInfo.png).

### 2.1 Behaviour ports

Each port is wired through a [port interface board](https://sanworks.github.io/Bpod_Wiki/assembly/port-breakout-board-assembly/),
which connects one infrared photogate, one LED and one solenoid valve to the state machine
over an Ethernet cable. This state machine has five behaviour ports:

| Port | Use | Photogate | LED | Valve |
|------|-----|-----------|-----|-------|
| 1 | Left port | ✔ | ✔ | ✔ (water) |
| 2 | Centre port | ✔ | ✔ | ✔ (water) |
| 3 | Right port | ✔ | ✔ | ✔ (water) |
| 4 | Air valve — switches compressed air flow | — | — | ✔ |
| 5 | House light — LED driver for the white light inside the rig, used for pre/post-behaviour sleep | — | ✔ | — |

### 2.2 Optogenetic stimulation (digital out → PulsePal → Doric LED)

The optogenetic stimulus is a **spatiotemporal pattern of 100 µm light spots** delivered to
the olfactory bulb through a custom fiber bundle
([`docs/fiber_bundle_design/`](docs/fiber_bundle_design)). There are two optical channels,
called **A** and **B** everywhere in the protocol, its windows and its data:

```
Channel A:  Bpod BNC1 → PulsePal IN1 → PulsePal OUT1 → Doric LED ch1
Channel B:  Bpod BNC2 → PulsePal IN2 → PulsePal OUT2 → Doric LED ch2
```

Each channel drives one cable of the bundle on the animal:

| Bundle | Cables | Spots per cable | Which two are used |
|--------|--------|-----------------|--------------------|
| 2-to-19 | ch1 fiber, ch2 fiber | 10, 9 | both, fixed: ch1 on A, ch2 on B |
| 4-to-19 | black, blue, orange, green | 4, 5, 5, 5 | any two on the commutator; chosen on the setup dialog's Light path tab and recorded with the session |

The design drawing colours the orange cable red.

A **light pattern** is the sequence of ON/OFF states of channels A and B over the stimulus
window. At any instant the pair is in one of four joint states: dark, A only, B only, or A
and B together. While a channel is on, PulsePal fills it with that channel's carrier.

**A session that delivers light does not start without PulsePal.** The protocol programs
PulsePal at the start of every session: both trigger inputs gated, output 1 on input 1 and
output 2 on input 2, the carrier, no train delay, and every output stopped with continuous
playback off. Bpod gates BNC1 and BNC2 whether or not that has happened, and a PulsePal the
session has not programmed answers with whatever program it last held. That can be edge
triggering with a long train, a train delay, both LED channels on one input, or an output
looping on its own, so light comes at the wrong times. Meanwhile the session file shows every
light timer starting on the poke. If PulsePal cannot be connected the session stops with
PulsePal's own error message. Check its USB cable, close anything else holding its port
(restarting MATLAB releases it), or untick **Light pattern** on the Task tab to run without
light. Sessions before version 0.4.1 ran on regardless; the first line of their
`Session.DeviceLog.PulsePal` says whether PulsePal was connected.

Once connected and stopped, PulsePal must also **answer a handshake** before a session uses it
(since 0.5). A sleep session that sends test pulses (§4.8) is refused on the same terms, asks
again whenever it gives PulsePal a new carrier and at every save (about once a minute), and stops,
saving what it sent, if PulsePal stops answering.

### 2.3 Flex I/O

The r2+ adds four Flex I/O channels, each configurable as digital output (5 V TTL), digital
input (5 V tolerant), analog input (12-bit, 0–5 V, 1 kHz) or analog output (12-bit, 0–5 V).

| Channel | Use | Configured as |
|---------|-----|---------------|
| Flex 1 | Flow meter (airflow) | Analog input (currently configured, 1 kHz) |
| Flex 2 | Sync TTL: session barcode and trial pulses | Digital output (**not yet configured**) |
| Flex 3–4 | unused | disabled |

The sync TTL goes to an externally powered, scalable BNC splitter, and from there to the
other acquisition devices (Neuropixels OneBox or NI-1083, camera 1, camera 2, and so on).
Bpod's analog viewer opens at the start of each session so the airflow can be watched.

### 2.4 Modules

Module ports are high-speed communication channels for external Bpod hardware extensions.

- **[HiFi module](https://sanworks.github.io/Bpod_Wiki/assembly/hifi-module-assembly/)** —
  connected to the state machine over Ethernet and to the computer over USB, and driving an
  amplifier card wired to a custom-made speaker.

---

## 3. Software environment

| Item | Location |
|------|----------|
| MATLAB working directory | `C:\Users\harrislab\Documents\MATLAB` |
| This project | `...\MATLAB\HarrisLabBpodProtocols\LuminoseFM` |
| Bpod protocol folder | `...\MATLAB\HarrisLabBpodProtocols\` (Bpod's `ProtocolFolder`) |
| Data folder | `D:\luminoseData\` (Bpod's `DataFolder`) |
| Bpod_Gen2, Bpod Local, PulsePal | cloned into `...\MATLAB\`; Bpod_Gen2 is on the MATLAB path, PulsePal must be added to the path before use |
| Protocol examples | `...\MATLAB\Bpod_Gen2\Examples\Protocols` |

Base MATLAB only; no toolboxes. Bpod user guide: <https://sanworks.github.io/Bpod_Wiki/user-guide/>

---

## 4. Protocol

The protocol lives as `LuminoseFM.m` in the root of this project (no nesting — Bpod's
launch manager requires the protocol file name to match its folder name). Helper functions,
classes and utilities are organised in subfolders.

**Two kinds of session.** The first window LuminoseFM opens asks what kind of session is
starting. *Behaviour* opens the setup dialog and runs the task below. *Sleep* opens its own
setup dialog and records home-cage sleep: a session barcode, sync pulses and, if chosen, test
pulses of light on channels A and B (§4.8). The
choice is saved with the subject's settings, so the next launch starts on it, and the data file
records it as `SessionData.Session.Type` (`'Behaviour'` or `'Sleep'`).

### 4.1 Task structure

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
  poke again; its next poke starts the latency and the stimulus **from the beginning**. This repeats until a hold is completed, or until the **hold window** runs out:
  `HoldWindow` seconds from trial start, counted across every restart. Then the trial lapses
  and the next one starts. The early-withdrawal punishment, if chosen, is applied at each break,
  before the animal may poke again.
- *End trial* — the break is an early withdrawal and the trial ends.

A hold already under way when the hold window ends is allowed to finish.

The withdrawal after a completed hold is part of the contract, not a formality. The side ports
stay inert until the animal has left the centre port, so the beam break it makes on the way out
cannot be scored as a choice, and the reaction time is measured from the withdrawal rather than
from the end of the hold. Never leaving it at all is a non-response.

Outcomes (`Data.Outcome`, names in `Data.OutcomeNames`): *NoInitiation* — the hold window ran out
and the stimulus never started; *HoldNotCompleted* — the stimulus started at least once but every
hold broke before the window ran out; *EarlyWithdrawal* — a break ended the trial (*End trial*
only); *NoResponse*, *Correct*, *Incorrect*, *CorrectNoReward*. `Data.HoldAttempts` counts how many
times the stimulus started on each trial.

**Training stages.** Stage 1 (*Habituation*) rewards **both** side ports, whichever way the
animal goes, so it learns that the side ports pay before it has to learn which one. By
default the rewarded ports are also lit during the response window in habituation (the
*guide light*, set per side). Stages 2 (*Training*) and 3 (*Experiment*) reward only the
correct side.

**Centre-hold shaping.** A naive animal cannot hold its nose in the centre port for a whole
stimulus, so the hold can be trained up in two ways, alone or together (Task tab):

- *Grow hold* — the hold starts short (`HoldStart`) and grows by `HoldGrowth` percent after
  every trial on which the animal completed it, up to `HoldTarget`, normally the stimulus
  window plus the post-stimulus hold. Light is cut off where a shaped hold ends.
- *Shrink grace* — the animal may leave the centre port during the hold and come back within
  a grace period without the break counting. The hold keeps timing while it is out, and the
  stimulus carries on. The grace starts at `GraceStart` and shrinks by `GraceShrink` percent
  after every completed hold, down to `GraceTarget` (normally 0). A break longer than the grace
  is treated as *When the hold breaks* says. Grace is timed from stimulus onset, so a break
  during the latency is never forgiven.

Both are tuned during the session from the runtime window. Neither changes the trial's state
graph, and the hold each trial required, its grace and the number of forgiven breaks are
recorded per trial.

### 4.2 Stimuli

**The stimulus set.** A session's light patterns and the order its trials come in are
generated together, before the first trial, by a port of the generatePattern library. The
**stimulus designer** (a button on the setup dialog's Stimulus tab, or
`lum.gui.StimulusDesigner` on its own) shows every parameter and every trial.

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
  (the rig has 16, the emulator 5; the hold window always takes one, and sync pulses, grace
  shaping or timed components take more). A pattern that needs more is refused, naming its group. Two groups that deliver
  identical light but pay different sides are refused too: that is a task the animal cannot
  solve.

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

### 4.3 Windows

**Session type** — the first window: *Behaviour* or *Sleep*, with the subject's last choice
preselected.

**Session setup** — shown once, before the first trial. Everything on it is validated on every
edit; the status line says what is wrong, and **Start session** stays disabled until nothing is.

| Tab | What it holds |
|-----|---------------|
| Experiment | Subject (from the launch manager); genotype (OSN-ChR or wild type offered, any other typed into the box); *Neuropixels recording* (probe, implant, target, coordinates, serial), *EEG/EMG recording* (channel counts), *Drug administration* (name, delivery route, dose and unit, vehicle, time given); session length, devices, runtime window, notes |
| Task | Training stage and what it does to rewards; trial order; centre hold — how long it is, what a broken hold does, and hold shaping; which components make up the cue, the stimulus and each side; a timeline of one trial, with the hold window |
| Cue | For each cue component (centre light, tone, air): whether it continues through the stimulus, and if not, how long it stays on into it; the cue tone's frequency; sound output; a timeline of the cue against the latency and the stimulus, one row per component |
| Stimulus | The stimulus window and its latency from the poke; a summary of the stimulus set with **Design stimuli…** and **New trial order**; P(left) per group; every trial of the session to scroll through; timing of air, centre light and tone |
| Light path | The fiber bundle and which cables are on A and B; the carrier for each channel (frequency, pulse width, LED drive voltage) |
| Left, Right | That side's port light and tone, each timed from stimulus onset; its guide light; which groups pay that side |
| Sync | Trial sync pulse mode and widths; the session barcode (behaviour and sleep marker widths), with a preview |
| Runtime | Starting values of the parameters that stay editable during the session |

Ticking a component on the Task tab switches it on: its rows light up on the tab that times it,
and that tab's title counts the components on. The small logo in the header is from
[`docs/logo`](docs/logo).

**Sleep session setup** — three columns: the animal, the recording length and the sync pulses; the
recordings and the session barcode; and **Test pulses** — whether light is sent on channels A and
B, a summary of the probe and the schedule, a preview of the whole session and of one epoch, and
**Design test-pulse schedule…**. With test pulses on, the recording lasts as long as their schedule,
and the duration field shows it.

**Test-pulse designer** — the probe (single or paired, pulse width, inter-pulse and inter-epoch
intervals, both onset to onset), the LED drive on A and B, the plasticity trains (switched on here;
one row per named train, *Theta burst* and *High frequency* to start with, and any added), and the
schedule as a table of steps — probe, rest or a train, on A and B together, on one of them, or
alternating — with presets, the minute each step starts, its epoch count, and previews of the
session and of one epoch of the selected step. Everything compiles on each edit, and nothing
leaves the window until the session could run it. It opens on its own too:
`S = lum.gui.TestPulseDesigner();`.

**Runtime window** — the parameters that are safe to change with an animal in the box,
synced once per trial. On the rig it is a window of its own, in tabs (*Trial*: reward and
timing; *Task*: punishment, bias correction, hold shaping; *Delivery*: light, sound and port
light brightness), with labels and units, limits held as values are typed, and a header saying
how the last trial ended and what is running now. Under the emulator the reduced form opens
instead — Bpod's own single-page parameter window, relabelled. `Runtime window` on the
Experiment tab can force either.

- *Punishment* is two choices: which mistakes are punished (none / early withdrawal / incorrect
  choice / both) and how (timeout / white noise / both).
- *Bias correction* is a strength (0 disables it) and the window of choices it is estimated over.

Bpod's notebook plugin is also initialised, for manual annotation during the session.

### 4.4 Sync TTL and session barcode

Both go out on Flex2, which has to be configured as a digital output.

**Session barcode.** Before the first trial the line carries one barcode that identifies the
session on every device that records it: a marker pulse, one pulse per bit — 10 ms for 0, 30 ms
for 1, most significant bit first, each followed by a 20 ms gap — and a closing marker. The
markers say what kind of session it is: **100 ms for a behaviour session, 200 ms for a sleep
session**. Its 32 bits are the seconds from 2020-01-01 to the session start, which is also in the
data file's name. To read it from a recording:

```matlab
[value, ~, kind] = lum.sync.decodeBarcode(risingEdges, fallingEdges, SessionData.Session.Barcode.Params);
startTime = lum.sync.barcodeTime(value);   % kind is 'Behaviour' or 'Sleep'
```

**Trial pulses** have three modes:

- *Fixed width* — one pulse per trial, always the same length: enough to count trials.
- *Jittered width* — one pulse per trial, its width drawn uniformly within a jitter either side of
  a mean. The widths are near-unique, so a recording is matched to `Data.SyncPulseWidth` trial by
  trial rather than by counting edges. (Called *Random width* before version 0.2.)
- *Task events* — no pulse: the line goes high at trial start and low when the animal pokes the
  centre port, so its own edges mark the events. Costs no global timer.

### 4.5 Emulator mode

The protocol runs **end to end on a machine with no hardware attached** (e.g. a desk PC), so
that task logic, windows, plots and data saving can be developed and tested offline.

- Start Bpod with `Bpod('EMU')`, or use the emulator button on the console, then launch
  `LuminoseFM` from the launch manager as usual.
- **You play the mouse.** The port buttons on the Bpod console poke the ports: click the centre
  port to initiate, leave it pressed through the stimulus, **click it again to withdraw** once
  the hold is over, then click a side port to choose. The second centre click matters — the
  response window does not open until the centre port goes low. Clicking it *before* the hold
  is over breaks the hold: click it once more to restart the stimulus. Bpod forgets the port
  states at the end of each trial, so expect to click a port again on the next trial.
- **Light can look late on the console.** The emulator emits no start event for a light segment
  that starts at stimulus onset, so the console never draws it; only segments that start later are
  drawn, and the light seems to arrive some time after the poke. The state machine starts every
  segment at stimulus onset, and the rig is unaffected.
- The protocol detects emulator mode in exactly one place (`lum.dev.open`), which builds no-op
  device shims. Every hardware call is logged rather than sent, and the log is written into the
  data file.
- **The emulator is not this rig.** `Bpod('EMU')` emulates a state machine r0.7-1.0: five global
  timers instead of sixteen, and no Flex I/O — so no airflow stream, no sync pulses and no barcode
  (it is recorded as not sent). A pattern with more than four stretches of light is refused in
  the emulator (the hold window takes one of its five timers) and accepted on the rig. The
  emulator cancels timers only partly: a light segment still waiting for its onset starts after
  an early withdrawal anyway, and the console can leave a cancelled line drawn high. The data
  and the rig are not affected.
- The HiFi module and PulsePal are unavailable, so sound states run silently and no light is
  delivered. The runtime window opens in its reduced, single-page form.
- Emulated sessions still produce a complete, correctly structured data file, marked with
  `Data.Info.EmulatorMode = 1` so it is never mistaken for real behaviour.

### 4.6 Data saving

Bpod writes session data to the `DataFolder` set above:

```
D:\luminoseData\<subject>\LuminoseFM\Session Data\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>.mat
D:\luminoseData\<subject>\LuminoseFM\Session Settings\<settings name>.mat
```

- `SaveBpodSessionData` writes `BpodSystem.Data` to the current data file as the variable
  `SessionData`, overwriting it each time; it is called every few trials so a crash costs at most
  a few trials.
- Because the whole struct is rewritten on every save, the per-trial record stays small:
  session-level information is stored **once**, and each trial stores only its own events,
  timestamps, outcome and indices into it.
- The settings chosen on the setup dialog are saved as the subject's settings file, so a session
  can be reproduced. A settings file from an older version is brought up to date when it is
  loaded; renamed settings keep their values, and the console lists what was converted.
- Flex I/O analog data (the flow meter) is streamed by Bpod to a separate `..._ANLG.dat` file next
  to the session file, and merged into the session data at the end of the session as
  `SessionData.Analog` (`Samples`, `Timestamps`, `TrialNumber`). **The merge corrects Bpod's
  timeline for the session barcode:** Bpod starts the stream with the barcode's own state machine
  but stamps its first sample with trial 1's start, which put every analog timestamp about 1.8 s
  late and numbered every sample one trial too high — airflow then appeared to arrive as the
  animal reached the reward port. Samples taken during the barcode now have `TrialNumber` 0, and
  `Analog.info.Alignment` says the correction was applied. Session files from version 0.2 with a
  barcode sent (e.g. `FakeSubject_LuminoseFM_20260911_140213`) still carry the shifted timeline:
  pass their `Analog` through `lum.dev.Flex.alignAnalog(Analog, TrialStartTimestamp(1), 1)`.
- Alongside Bpod's own fields, a behaviour session file carries:
  - `SessionData.Session` — written once: `Type` (`'Behaviour'`), `Subject`, the frozen `Settings`,
    the `StimulusSet` (every pattern as a segment table, the trial order, each group's label and
    `P(left)`, and descriptors of each pattern), the rig channel map, which devices were available,
    the runner and runtime window used, `StartTime` and `EndTime`, the `Barcode` (value, kind,
    whether it was sent, its parameters), the protocol version, and the device log.
  - One value per trial for `StimulusGroup`, `PatternIndex`, `CorrectSide`, `Choice`, `Correct`,
    `Rewarded`, `Outcome`, `ReactionTime`, `OptoOn`, `SoundOn`, `SyncMode`, `SyncPulseWidth`,
    `BiasTargetPLeft`, `TrainingStage`, `HoldDuration`, `HoldGrace`, `HoldBreaks` and
    `HoldAttempts`, plus `TrialSettings` (the runtime parameters only) and `OutcomeNames` for
    decoding `Outcome`.
- A sleep session file carries `SessionData.Session` with `Type` `'Sleep'` (subject, settings, rig,
  devices, whether sync was sent, start and end time, barcode, `TestPulses`, version, PulsePal and
  Flex logs) and `SessionData.SyncPulses` — `Onset` (state machine clock, s), `Width` (s) and
  `Block`, one value per pulse sent. Each block is one Bpod trial in `RawEvents`.
  - With test pulses, `SessionData.LightSegments` — `Onset` (state machine clock, s), `Duration`
    (s), `Channel` (1 = A, 2 = B), `Step`, `Epoch` and `Block`, one value per gate of light sent.
    For a probe step the gate is the pulse; for a train step it is a burst, and
    `lum.sleep.epochShape(lum.sleep.testPulsePlan(SessionData.Session.Settings.Sleep.TestPulses), step, epoch)`
    gives the pulses PulsePal put in it.
  - `Session.TestPulses` — `Enabled`, the compiled `Steps` (kind, channels, start, duration, epoch
    count, and each step's PulsePal carrier and train), the schedule's `Duration`, whether it
    `Completed`, and a `StoppedReason` when PulsePal stopped answering.
  - `SessionData.Timing` — how long each trial's prepare, send, plot and save steps took, so lag
    regressions show up in the data rather than only in the room.

To get trial *k*'s light: `lum.pattern.patternAt(SessionData.Session.StimulusSet, SessionData.PatternIndex(k))`.

### 4.7 Online plots

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
    for the side chosen. An animal reading one channel separates
    its left and right choices along a vertical or horizontal boundary; one weighing both, along a
    diagonal. Light-off trials sit at the origin, and a small fixed jitter keeps repeated patterns
    visible.
- Bottom row
  - **By side** — fraction correct on left- and right-rewarded trials
  - **Side bias** — P(chose left) over the last `BiasWindow` choices (as set when the session
    started), with the P(left) that bias correction aimed for on each trial
  - **Reaction time** — by side chosen, with a running median

The per-trial panels scroll with the session and rescale to what is on screen, so they stay
legible at any point in it. Handles are created once and only updated, aggregates are kept
incrementally, and there is exactly one `drawnow limitrate` per trial. Closing the figure does not
stop the session.

### 4.8 Sleep sessions

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

**Test pulses.** Light on channels A and B during the recording, to probe the bulb's response to it
and to change that response. It goes out exactly as a behaviour stimulus does (§2.2): Bpod drives
BNC1 and BNC2, and PulsePal, in gated mode, fills each gate.

- A **probe** is one *epoch* every *inter-epoch interval* (2 s by default): a single pulse, or a pair
  of pulses an *inter-pulse interval* apart (50 ms), each 10 ms of constant light. Both intervals are
  onset to onset.
- **Plasticity trains**, once switched on, are named definitions: bursts of pulses at a pulse
  frequency, bursts at a burst frequency, a number of trains a train interval apart. Bpod gates each
  burst and PulsePal puts the pulses in it. Provided: *Theta burst* — 10 bursts of 4 pulses (5 ms)
  at 100 Hz, bursts at 4 Hz, 5 trains 20 s apart — and *High frequency* — 100 pulses (5 ms) at
  100 Hz, 4 trains 20 s apart. Any other can be added.
- The **schedule** is a list of steps run in order from the start of the recording: a probe or rest
  for so many minutes, or a train (which lasts its trains), on A and B together, on one of them, or
  alternating between them epoch by epoch. The default is paired-pulse probes on A and B for
  4 hours. The recording lasts as long as the schedule.
- The LED drive is set per channel, in volts.

A schedule is refused before the session starts if it cannot be sent: pulses of a pair that overlap,
epochs too long for their interval, a train step while trains are off, darkness after an epoch too
short to hold a sync pulse, or an epoch so busy that it and the sync pulses that can fall in it do
not fit one state machine.

**How it is sent.** Every sync pulse and every gate of light is laid out before the first block, and
the timeline goes out in state machines of about 10 s. Each is cut only where every line is low,
never inside an epoch — so a pair keeps its interval and a train its rhythm — and before the first
epoch of a new step, so PulsePal is given that step's carrier with no light in flight. Each state
holds the sync line, A and B at one level until the next edge, so no global timers are used.
Uploading the next block lengthens one interval by a few milliseconds, and the time spent between
blocks makes a long session run a little longer than its schedule; every onset in the data is read
from the state machine's clock.

**PulsePal.** A sleep session with test pulses does not start without PulsePal, and PulsePal must
answer a handshake whenever it is given a new carrier and at every save. If it stops answering, the
session stops, saves what it sent and records why (`Session.TestPulses.StoppedReason`).

The **sleep plot** shows, under a header with the pulse rule, the test pulses, the barcode and the
counts: with test pulses, the schedule across the session with the part already sent shaded; the
last 30 s of the sync line (and of A and B); with test pulses, the latest epoch at millisecond scale
— its gates, and the light in them; the width of every sync pulse against session time; and, with
test pulses, epochs sent against planned, step by step. No sound or runtime window is used. In the
emulator the session runs the same: it drives BNC1 and BNC2 on the console but no sync line, logs
PulsePal's programming, and records the barcode and every pulse it would have sent. The emulator
keeps no millisecond time, so emulated intervals are only lower bounds.

---

## 5. Names used throughout

The same words mean the same thing in the code, the windows, the plots and the data.

| Name | Means |
|------|-------|
| channel A, channel B | The two optical channels (BNC1 and BNC2). Never "pattern 1/2" or "ch1/ch2". |
| light pattern | The light one trial delivers: channels A and B over the stimulus window |
| joint state | What A and B are doing together at one moment: dark, A only, B only, A and B |
| group | One stimulus condition; groups are balanced across a session |
| stimulus set | A session's patterns, their groups and contingency, and the trial order |
| stimulus window | `S.Stimulus.Duration`, from stimulus onset |
| latency | `S.Stimulus.Latency`: from the poke to stimulus onset, held with the cue on |
| hold, hold break, grace | The centre-port hold; leaving during it; how long a break may last unpunished |
| hold window | `HoldWindow`: the time from trial start in which a hold must be completed, restarts included |
| session type | Behaviour or sleep; `Session.Type` |
| carrier | What PulsePal does on a channel while it is on (frequency, pulse width, voltage) |
| centre | British spelling, in identifiers as well as text: `CentreHold`, `WaitForCentrePoke` |
| test pulses | Light during a sleep recording, probes and plasticity trains on a schedule: `S.Sleep.TestPulses` |
| epoch | One probe — a single pulse or a pair — or one train: what a schedule step repeats |
| inter-pulse interval, inter-epoch interval | Onset to onset: between the two pulses of a pair; between successive epochs |
| plasticity train | Bursts of pulses meant to change the response: theta burst, high frequency, or one of your own |
| schedule step | One row of the schedule: probe, rest or a train, for its length, on its channels |
| light segment | One gate on channel A or B: a probe pulse, or a burst PulsePal fills with pulses (`LightSegments`) |

Version 0.2 renamed several states, data fields and settings so that they say what they are.
Settings files are converted when loaded; analysis code reading 0.1 files needs the old names:

| 0.1 | 0.2 |
|-----|-----|
| states `WaitForCenterPoke`, `CenterHold`, `WaitForPortOut` | `WaitForCentrePoke`, `CentreHold`, `WaitForCentreExit` |
| state `Punish` (also reached by unpunished mistakes) | `IncorrectChoice` |
| state `CorrectEarlyWithdrawal` (left the reward port early) | `WithdrewBeforeReward` |
| — | new states `HoldBreak`, `CentreHoldResumed` |
| `Data.StimulusIndex` | `Data.StimulusGroup` and `Data.PatternIndex` |
| `Data.SyncDuration` | `Data.SyncPulseWidth` |
| `Data.LeftProbabilityUsed` (was the bias target, not the stimulus's P(left)) | `Data.BiasTargetPLeft` |
| `Session.Patterns` | `Session.StimulusSet` |
| sync mode *Random width* | *Jittered width* (code 2 unchanged) |
| runtime `StimulusOn`, `PortLEDIntensity` | `OptoOn`, `PortLightIntensity` |
| `S.Stimulus.Waveform`, `S.Meta.FiberBundle` | `S.Light.Carrier`, `S.Light.Bundle` |

Version 0.3 changed what a broken hold does, so:

| 0.2 | 0.3 |
|-----|-----|
| runtime `InitiationWindow` (state timer of `WaitForCentrePoke`) | `HoldWindow` (a global timer from trial start, across restarts); converted on load |
| a broken hold always ended the trial (`EarlyWithdrawal` → `ITI`) | `S.Task.OnHoldBreak`: *Restart stimulus* (default, `EarlyWithdrawal` → `WaitForCentrePoke`) or *End trial* |
| — | outcome `HoldNotCompleted` (code 6), series `HoldAttempts`, `Session.Type`, `Barcode.Kind`, `SyncPulses` (sleep) |
| analog `Timestamps`/`TrialNumber` shifted by the barcode | corrected at merge |

Version 0.4 keeps the cue on until the poke and starts the stimulus on it:

| 0.3 | 0.4 |
|-----|-----|
| states `Cue`, `Cue2`, `Cue3`… (the cue, from trial start) | gone: the cue is on in `WaitForCentrePoke` |
| runtime `PreStimulusHold`, 0.05 s by default; leaving it re-armed the trial unpunished | pre-session `S.Stimulus.Latency` (Stimulus tab), 0 by default; leaving it is a broken hold. State `PreStimulusHold` is entered only when the latency is above 0, otherwise the poke enters `CentreHold`. The runtime setting is retired on load, not converted |
| cue rows `Latency`, `Duration` from trial start; `Cue.CentreLightDuringHold` | cue rows `ThroughStimulus`, `Duration` from stimulus onset; converted on load (the centre light keeps its hold setting, tone and air go off as the stimulus starts) |
| task-event sync low in `PreStimulusHold` | low on the poke: in `PreStimulusHold`, or `CentreHold` without a latency |

Version 0.5 adds test pulses to sleep sessions and rearranges the online plots:

| 0.4 | 0.5 |
|-----|-----|
| sleep block states `Pulse001`, `Gap001`… | `Level001`…: one state per span between edges of the sync line and channels A and B |
| sleep sessions never open PulsePal | they do when test pulses are on, and are refused without it |
| — | `S.Sleep.TestPulses` (filled in, switched off, on load), `SessionData.LightSegments`, `Session.TestPulses`, `Session.DeviceLog.PulsePal` |
| PulsePal connected and stopped | also answers a handshake before a session uses it |
| online panel *By side and light* | *By side*; new *Evidence, u_A vs u_B* and *Side bias* panels |

---

## 6. Utilities

Helpers for working with the rig outside a session live in `hardware/`.

### `CheckRig` — preflight

`CheckRig` prints one line per check: the state machine, the behaviour ports, the optogenetic
BNC lines, the HiFi module, the Flex I/O configuration, PulsePal, the liquid calibration and the
data folder. Failures name the exact thing to change and where. The protocol runs it at startup,
but it is worth running by hand before the first animal of the day:

```matlab
CheckRig                    % print the report
report = CheckRig;          % also return it
CheckRig('Strict', true)    % error if anything failed
```

Checks that cannot mean anything without hardware are reported as skipped in emulator mode.

### `TestHiFiSound` — play a test sound

The Bpod console can exercise ports, valves, LEDs and BNC lines by hand, but not sound.
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
playback falls back to the PC audio device. Because loading a sound overwrites a slot in the
module's active sound set, the utility refuses to run while a protocol is in progress unless
`'Force', true` is passed. `help TestHiFiSound` lists all options.

### `lum.gui.StimulusDesigner` — design stimuli away from the rig

```matlab
S = lum.gui.StimulusDesigner();   % defaults, sized to the connected machine's timers
```

### `lum.gui.TestPulseDesigner` — design sleep test pulses away from the rig

```matlab
S = lum.gui.TestPulseDesigner();  % defaults: paired-pulse probes on A and B for 4 hours
```

---

## 7. Later: controlling the Doric LED from MATLAB

*Not in scope yet.* The API for controlling the Doric LEDs lives in
`C:\Users\harrislab\Documents\MATLAB\DoricSystemDLL`. It would let the operator set LED power and
other parameters directly from MATLAB. Open question: should this live in its own package, or be
integrated into this protocol folder?

---

## 8. Repository layout

```
LuminoseFM/
├── LuminoseFM.m                  the protocol: session setup, trial loop, teardown
├── README.md                     this file
├── CLAUDE.md / AGENTS.md         instructions for coding agents
├── +lum/                         everything with logic in it, testable without hardware
│   ├── buildTrialSM.m            the state graph
│   ├── triggerStates.m           where the next trial may be prepared
│   ├── nextTrialSpec.m           trial policy: order, contingency, bias, run limit, stage
│   ├── HoldShaping.m             centre-hold shaping and what a broken hold does
│   ├── scoreTrial.m              outcome classification
│   ├── validateSettings.m        everything that must hold before a session starts
│   ├── timerBudget.m             global timers left for light
│   ├── SessionRunner.m           TrialManager on the rig, blocking in the emulator
│   ├── OnlinePlots.m             the live figure
│   ├── defaultSettings.m         the two-tier settings struct
│   ├── +pattern/                 stimulus generator, stimulus set, light patterns
│   ├── +stim/                    cue and stimulus components
│   ├── +sync/                    session barcode
│   ├── +sleep/                   sleep sessions: run, sync and test pulses, blocks, validation, plots
│   ├── +dev/                     device shims, real and null
│   └── +gui/                     session type, setup dialogs, stimulus and test-pulse designers, runtime window, theme
├── hardware/
│   ├── RigConfig.m               the channel map — the single source of truth
│   ├── CheckRig.m                preflight report
│   └── TestHiFiSound.m           play a test sound through the HiFi module
├── tests/
│   └── runLuminoseTests.m        the whole suite; needs no hardware
└── docs/
    ├── architecture.md           design decisions and the map from design to code
    ├── BpodSystemInfo.png        channel, event and output list of the rig
    ├── logo/                     the Luminose logo
    ├── behaviour_box_design/     box, base plate and home-cage cover drawings
    └── fiber_bundle_design/      2-to-19 and 4-to-19 fiber bundle drawings
```

## 9. Tests

The suite runs without any hardware attached, and **refuses to run against a real state
machine** — it starts `Bpod('EMU')` itself for the tests that need one. Safe to run on the rig
computer whenever a session is not in progress.

```matlab
addpath('tests');
runLuminoseTests                              % everything
runLuminoseTests('Filter', {'generateTest'})  % one file
```

Or headless, from a terminal:

```bash
matlab -batch "cd('/path/to/LuminoseFM'); addpath('tests'); runLuminoseTests"
```

Most of it is pure functions — the stimulus generator and stimulus set, the cue's timing once the
stimulus starts, trial generation, bias correction, hold shaping and break modes, outcome scoring, the barcode and its kinds, the analog
realignment, settings conversion and validation, the PulsePal carrier and its health check (against
a stub PulsePal that can stop answering), the sleep pulse schedule, the test-pulse plan and how a
sleep session is cut into blocks. `stateMachineTest` asserts the state graph itself (restarts and
the hold window included), `windowsTest` drives the runtime window, both plot figures, the session
type chooser, both setup dialogs and both designers invisibly, and `emulatorSessionTest` and
`sleepSessionTest` run a whole behaviour session and two sleep sessions — with and without test
pulses — under `Bpod('EMU')` and check the files they produce. `lintTest` keeps the repository at
zero MATLAB Code Analyzer messages.
