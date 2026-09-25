# LuminoseFM — Architecture

Design record for the LuminoseFM protocol. Status: **implemented** (version 0.9.5); decisions
D1–D21 confirmed. Update this file whenever the architecture changes.

---

## Confirmed decisions

### D1 — Bpod owns the light pattern, PulsePal owns the carrier

**Decision.** An optogenetic stimulus is split across the two devices by what each is
good at:

- **Bpod global timers** define the *light pattern* — which of channel A (BNC1) and channel
  B (BNC2) is high, when, and for how long, using one-shot timers with `OnsetDelay` +
  `Duration` and `'Channel', 'BNC1'|'BNC2'`. Every timer is started at once from the hold
  state via one `GlobalTimerTrig` bit mask.
- **PulsePal** defines the *carrier* — pulse train frequency, pulse width, voltage — with
  both trigger channels in **gated mode**, so `OUT1`/`OUT2` pulse exactly while the
  corresponding Bpod BNC line is high. The carrier is **per channel**: `S.Light.Carrier` is
  a struct array, element *k* programming output *k*, because the two channels drive
  different LEDs into different cables and equalising the light they deliver is a
  per-channel calibration, not one number for the rig.

Any pattern of A and B — one channel, one after the other, overlapping, a repeating motif —
is then a set of one-shot timers, with no MATLAB code in the timing path.

**Why this split and not the alternatives.**

1. *Timing stays in hardware.* The pattern is compiled into the state machine and uploaded
   before the trial starts; nothing in the stimulus path depends on MATLAB loop latency or
   USB scheduling.
2. *Composition is orthogonal.* Pattern (which channel, when) and carrier (how it pulses)
   vary independently, which is how the windows present them. PulsePal only needs
   reprogramming when the carrier changes — not per trial, and not per pattern.
3. **The emulator reproduces the pattern but could not reproduce a timer-built carrier.**
   `RunBpodEmulator.m` implements global timer triggering, onset delay, end events and
   channel setting, but **does not implement `LoopMode`**. A 20 Hz carrier built from
   looping Bpod timers would run correctly on the rig and silently differently under
   `Bpod('EMU')`. With this split, the emulator reproduces the full pattern and only omits
   the carrier — the part that has no hardware to drive offline anyway.
4. *Event budget.* A carrier built from looping timers would emit two events per pulse into
   the trial's event stream. The pattern emits a handful per trial, all meaningful.

**Consequences / constraints.**

- 16 global timers is the hard ceiling on pattern complexity: one timer per stretch of light
  per channel. Budget validation belongs to the stimulus set (D5), not trial building.
- PulsePal reprogramming happens only in the inter-trial window, never mid-stimulus.
- **The split only holds while PulsePal is programmed, so a light session never runs without
  it** (`lum.dev.openPulsePal`, 0.4.1). Bpod gates the BNC lines regardless, and an
  unprogrammed PulsePal answers with its last program: edge triggering, a train delay, both LED
  channels on one input, or continuous looping. Light then comes at the wrong times while every
  `GlobalTimer<k>_Start` in the session file is on the poke. Before 0.4.1 a failed connection fell
  back to the null shim with a warning that no light would be delivered, which was false. That
  happened in 13 of the first 16 rig sessions: every session after the first in a MATLAB
  instance. On connecting, every output is stopped with continuous playback off (`stopOutputs`,
  firmware op 82), because parameters change the next trigger, not a train already playing.
  Firmware v21 or later is required: v20 has a gated-mode bug with both inputs in use.
- Since 0.5 a connected, stopped PulsePal must also answer a handshake (`checkConnection`) before
  a session uses it. A session whose carrier never changes sends PulsePal nothing after trial 1,
  so nothing else would notice a device that went away; a sleep session with test pulses asks
  again at every carrier change and save, and stops if the answer does not come (D13).
- Non-uniform trains stay available via `SendCustomPulseTrain` (≤5000 pulses).
- **Gotcha:** `ProgramPulsePalParam(ch, 128, value)` passes the value straight to the
  firmware, which uses `0 = normal, 1 = toggle, 2 = gated` — the function's own header
  comment says `1/2/3`. Send **2** for gated, and confirm on hardware at bring-up.
- PulsePal time values must be multiples of the 100 µs cycle.

### D2 — Two-tier GUI, split by when a parameter may legally change

**Decision.**

1. **Pre-session setup** — `lum.gui.SetupDialog`, a `uifigure` in tabs, shown once before
   the trial loop: Experiment, Task, Cue, Stimulus, Light path, Left, Right, Sync, Runtime.
   It writes a validated settings struct `S`, saved as the subject's settings file. The
   stimulus designer (`lum.gui.StimulusDesigner`) opens from its Stimulus tab.
2. **Runtime window** — only parameters that are safe to change with an animal in the box:
   reward, timing, punishment, bias correction, hold shaping, light/sound switches and port
   light brightness. Synced once per trial in the prepare step, through
   `lum.gui.RuntimeWindow`, which has two forms:
   - *Tabbed* — its own classic-figure window, a tab per `S.GUITabs` entry, panels per
     `S.GUIPanels`, readable labels, limits enforced as values are typed, and a header with
     the last outcome and the running trial. The default on the rig.
   - *Compact* — Bpod's `BpodParameterGUI`, every panel on one page, relabelled by
     `lum.gui.relabelParameterGUI`. The default under the emulator, as the reduced form.

The tiers are split by **when a parameter stops being editable, not by who sets it**. Both
are editable before the session: runtime controls are generated from `S.GUI`, `S.GUIMeta`,
`S.GUIPanels` and `S.GUITabs` through `lum.gui.runtimeFields` — on the Runtime tab, and the
`Shaping` panel on the Task tab beside the choice that uses it.

**Why.** `BpodParameterGUI` handles scalars, checkboxes and popupmenus, but v1.9.0 supports
`GUIPanels` and not `GUITabs`, labels every control with its field name, and has no
representation for a stimulus set or a per-channel carrier; every field it owns is editable
at any moment, which is wrong for parameters that must be constant within a session.
Splitting by mutability makes that constraint structural and makes the whole pre-session
configuration reproducible as one settings file. The tabbed runtime window is built from
plain `uicontrol`s so that creating it is quick and syncing it costs a few property reads per
parameter; the structure (tabs, a header with the logo, component indicators on the tabs
that time them, a trial timeline) follows the lab's head-fixed Luminose GUI, without its
colour scheme or its per-sync redraws.

**Consequences.**

- The stimulus set is frozen at session start and stored once in the data file; trials
  reference it by index.
- `lum.validateSettings` is the one definition of a startable configuration: the dialog runs
  it on every edit (reusing the last compiled stimulus set when nothing it depends on has
  changed), the Start button runs it, and `LuminoseFM` runs it again before opening devices.
- A component is switched on by its checkbox on the Task tab — the `Enabled` flag itself —
  and timed on the tab named for where it is delivered, whose title counts what is on. One
  control per value.
- A runtime parameter is declared on one line of `lum.defaultSettings`, with its value,
  `GUIMeta.Label` and `GUIMeta.Limits`. All three windows read that declaration.
- Settings whose *name or shape* changes need a conversion, not just a default:
  `lum.mergeSettings` renames, reshapes and retires, and reports each; declarations
  (GUIMeta, GUIPanels, GUITabs, name lists) always come from the defaults.
- Both tiers work under `Bpod('EMU')`.

### D3 — One session rhythm, two execution strategies

**Decision.** `lum.SessionRunner` exposes a single four-call rhythm that the trial loop
follows unchanged, and implements it either over `BpodTrialManager` or over blocking
`RunStateMachine` calls:

```
runner.begin(smaForTrial1);
for trial = 1:nTrials
    runner.awaitPrepareWindow();   % returns when it is safe to work
    runner.queue(smaForNextTrial); % upload the next trial
    raw = runner.awaitTrialData(); % the finished trial's raw events
    runner.advance();              % start watching the next trial
end
```

**Why.** Real-time control needs `BpodTrialManager`, which lets trial *n+1* be built and
uploaded while trial *n* runs. But `BpodTrialManager`'s constructor **errors outright in
emulator mode**, and running end to end under `Bpod('EMU')` is equally non-negotiable.
Putting the difference behind one interface keeps the session loop free of any mode test,
and keeps the *observable* behaviour identical. The mode is recorded in
`Data.Session.RunnerMode`.

**Consequences.**

- On the rig the prepare window opens partway through the trial, at one of the trigger
  states `lum.triggerStates(S)` lists (`LeftReward`, `RightReward`, `IncorrectChoice`,
  `NoResponse`, `NoInitiation`, `WithdrewBeforeReward`, and `EarlyWithdrawal` only when a
  broken hold ends the trial — with restarts, light can follow it, D10; never `RetryResponse` or
  `CentreReward`, after which the trial goes on, D19), and the next state
  machine is uploaded during the trial. When a completed hold may end before the light
  (`lum.HoldShaping.lightMayOutlastHold`, D21) the light can still be on in any of those states,
  so the `ITI`, reached through `WaitForLightEnd` once the light is over, is the only trigger
  state; the next trial is then prepared in the ITI. Anything computed from history — bias correction, hold shaping — therefore
  follows trial *n-1* when preparing trial *n+1*.
- In the emulator the same calls run the trial to completion first.
- `lum.dev.open` is the only place that reads `BpodSystem.EmulatorMode`.

### D4 — Sync TTL: trial pulses in one of three modes, all driven by states

**Decision.** Trials drive the sync line (Flex2) in one of three modes, chosen before the
session and recorded per trial (`Data.SyncMode`). **Every mode drives the line from states**,
never from a global timer:

- *Fixed width* — one pulse per trial: `TrialStart` drives the line high and its state timer is
  the pulse's width; `WaitForCentrePoke` drives it low as the cue comes on.
- *Jittered width* — the same, with the width drawn uniformly from
  `S.Sync.MeanWidth ± S.Sync.WidthJitter`; recorded as `Data.SyncPulseWidth`.
- *Task events* — no pulse: the line goes high in `TrialStart`, is held high through
  `WaitForCentrePoke` for as long as the animal is asked to poke, and goes low on the poke
  (`PreStimulusHold`, or `CentreHold` without a latency) and in `NoInitiation`. `TrialStart`
  keeps a zero timer.

**Why.** A train of identical pulses only supports alignment by counting edges, which breaks
if a device starts late or drops samples. Pulses of near-unique width are self-identifying:
any device that recorded the line can match its widths against `Data.SyncPulseWidth`. The
mode was called *Random width* until version 0.2; the new name says what the parameters are
(a mean and a jitter). Which session a recording belongs to is the barcode's job (D7).

**Why states.** Until version 0.5.1 a pulsed mode was a global timer with the sync channel as
its `Channel`, triggered in `TrialStart`. It did not work, and could not: **Bpod writes every
output channel from the entered state's own row**, and `TrialStart` had a zero timer, so
`WaitForCentrePoke` — one state-machine cycle later — wrote the line low again. Every fixed-
and jittered-width pulse reached the recording as a ~100 us glitch, while the session barcode,
whose every edge is a state, came through perfectly. Bpod's own `SetGlobalTimer` help says as
much in passing: *"State output events can still manipulate the linked channel while the timer
is running."* (Firmware 23's source shows why for this line in particular: a timer marks BNC, Wire,
PWM and valve lines overridden, and state entries skip them, but it has no such check for Flex
outputs.) Driving the line the way the barcode and a sleep session's pulses are driven
removes the one thing that differed between what worked and what did not, and matches the rule
in the trial-flow contract: states for what happens outside the stimulus, global timers for what
happens inside the hold, where leaving the port must end it at any instant.

**Consequences.**

- Requires Flex2 configured as a digital output. Where it is not, `hasSync()` is false and
  trials are built without the pulse — which is what emulator mode always gets.
- **No mode costs a global timer.** `reserved.Sync` in `lum.timerBudget` is 0, and one more
  timer is free for light — which matters most in the emulator, with five.
- In a pulsed mode the cue starts one pulse width (10-100 ms) after the state machine does,
  because `TrialStart` now lasts that long. An animal has no sign that a trial has started other
  than the cue, so this delays nothing it can perceive, and it makes the rising edge an exact
  marker for cue onset as well as for trial start.
- Sessions from 0.2 to 0.5.0 have no usable trial pulses. Align them by the barcode and
  `Data.TrialStartTimestamp`. `TestSyncLine` sends both kinds of train on demand, so the line
  and the way it is driven can be told apart on a scope.

### D5 — The stimulus is a stimulus set, generated before the session

**Decision.** The patterns a session delivers, and the order its trials come in, are made
together before the first trial by `lum.pattern.generate` — a port of the generatePattern
library — and compiled by `lum.pattern.stimulusSet`:

- A **family** (pure channel, mixture, sequence, order, motifs, hand-drawn pulses; D20) and its
  parameters produce **K groups** of joint states (dark, A only, B only, both) over bins of the
  stimulus window. Families that offer it (`Generator.Continuous`) give every trial a pattern of
  its own, drawn within its group.
- Groups are **balanced**: each is assigned ⌊N/K⌋ trials, the remainder to random groups,
  and the assignment shuffled — all from a private `RandStream` seeded with
  `S.Stimulus.Generator.Seed`, drawn per session (`lum.pattern.prepareSeed`) unless fixed, so no
  two sessions repeat their trials by default. The Stimulus tab's *Randomise trials* draws a new
  one and its *Seed* takes one typed in, which repeats a session from the seed saved in its data
  and nothing else of it; nothing reads earlier data files, which may have moved off the rig.
- Each pattern is compiled to segments `[channel onset duration]` (`fromStates`), one per
  stretch of light, and stored in one table with row offsets per pattern (`Segments`,
  `SegmentStart`); `patternAt` recovers one in constant time.
- Each group's chance of paying left is the family's (`FamilyPLeft`) unless
  `S.Task.GroupPLeft` gives one value per group (D20).
- The set is **refused** if any pattern needs more global timers than `lum.timerBudget`
  leaves for light, or if two groups deliver identical light but pay different sides.
- `lum.nextTrialSpec` takes the next pattern from a queue initialised to the order. The run
  limit and bias correction **swap** the next entry with a later one (within 50) that pays
  the needed side, so every group is still delivered exactly as often as it was balanced.

**Why.** A pre-generated set makes the preview the session: the operator scrolls through the
very trials that will run (`lum.gui.PatternBrowser`), sees each group's timer cost, and the
data file stores the set once. Balanced, shuffled groups are how the generatePattern designs
are meant to be used, and they make the psychometric panel's points comparable. Storing
segments rather than joint states keeps a continuous session of a thousand patterns small
enough to rewrite at each save. A private stream keeps the global rng — which side draws and
sync widths use — independent of when the set was built.

**Consequences.**

- The old hand-written stimulus table (`S.Task.StimulusNames`, `LeftProbability`,
  `StimulusWeights`, `S.Stimulus.Patterns`, `lum.pattern.fromSpec`, `dictionary`) is retired;
  `lum.mergeSettings` removes it from old settings files and says so.
- Bias correction brings forward the next trial in the rest of the order that pays the side
  it draws (from 0.9.4; before, only from the next 50, and it faded after about 100 trials). It
  holds its target for as long as the order has trials paying that side. It takes precedence
  over the run limit, which then only breaks runs on the side the correction is not pushing
  towards.
- A pattern with many stretches of light fits the rig's 16 timers and not the emulator's 5;
  both are checked against the connected machine.
- The generator is pure and tested (`generateTest`, `stimulusSetTest`); the designer and
  dialog only edit its parameters.

### D6 — Hold shaping without changing the state graph

**Decision.** Two ways to train the centre hold, under one switch, **automatic shaping**
(`S.Task.AutoShaping`, off by default; since 0.6.0), with the way chosen before the session
(`S.Task.HoldShaping`: Grow hold, Shrink grace, Both) and tuned during it (`S.GUI.Hold*`,
`S.GUI.Grace*`), implemented by `lum.HoldShaping`. Every decision goes through
`lum.HoldShaping.activeMode(S)`, which is `'Off'` while the switch is off. Choosing *Training*
switches it on and *Experiment* off (`lum.stageDefaults`), and `lum.validateSettings` refuses it in
an Experiment session — the one stage default that is enforced, because an experiment's trials
must not vary with the animal's performance.

- **Grow hold** sets the `CentreHold` state timer per trial: from `HoldStart` (0.1 s), grown by
  `HoldGrowth` percent after each trial whose hold was completed, up to `HoldTarget` (1 s). After
  `HoldStepBackAfter` (10) early withdrawals at one hold with no completed hold since, it **steps
  back** one growth step (`lastHold / (1 + growth)`, never below `HoldStart`).
  `lum.updateHistory` keeps the count (`history.withdrawalsAtHold`, O(1)): visits to
  `EarlyWithdrawal` are added, a completed hold clears it, a hold different from the previous
  trial's starts it again.
- **Timing (0.9.4).** Trial *n+1* is prepared while trial *n* runs, so it knows trial *n-1*'s
  outcome and trial *n*'s hold and grace (`lum.HoldShaping.notePrepared` keeps them in the history).
  It grows, shrinks or steps back **from trial *n*'s values**: one step per completed hold, one
  trial late. It steps back only while trial *n* has the hold the counted withdrawals were made at
  (the last recorded trial's), so the withdrawals that stepped it back cannot do so twice. Up to
  0.9.3 each step was taken from trial *n-1*'s values, which made odd and even trials two shaping
  sequences: every completed hold grew only its own half, the hold grew every second trial, an
  animal completing every other hold kept half its trials at the start, and with the two halves
  apart the withdrawal count was reset nearly every trial.
- **Shrink grace** lets the animal leave during the hold and return within `HoldGrace`
  seconds. The graph always contains `HoldBreak` and `CentreHoldResumed`:

```
CentreHold  --Port2Out-->  HoldBreak  --Port2In-->  CentreHoldResumed  --Port2Out--> HoldBreak
    |                         |  Tup (grace over)  --> EarlyWithdrawal
    +---- GlobalTimerK_End ---+---- GlobalTimerK_End ---- CentreHoldResumed ----> WaitForCentreExit
```

  With grace, the hold is timed by a **global timer** (the hold clock) triggered in
  `CentreHold` together with the stimulus timers; `CentreHoldResumed` re-triggers nothing,
  so a return does not restart the light or the clock. Grace starts with the stimulus: a break
  during the latency before it (D12) is not forgiven. `WaitForCentreExit` also leaves on
  **condition 3** (centre port low), so a hold that ends during a forgiven break still opens
  the response window. Without grace, `CentreHold` times itself, leaving goes straight to
  `EarlyWithdrawal`, and the two extra states are unreachable. Where `EarlyWithdrawal` leads
  is D10's business.

**Why.** A state timer restarts on every entry, so it cannot time a hold the animal leaves
and re-enters; a global timer can. Keeping the states in every trial holds the trial-flow
contract: scoring, plots and analysis see the same names whatever the shaping, and an
unreachable state costs nothing. Growth follows only completed holds, so an animal that keeps
withdrawing is not asked for more.

**Consequences.**

- Grace costs one global timer, reserved by `lum.timerBudget`; growth costs none.
- Values follow trial *n-1* when preparing *n+1* (D3). `HoldDuration`, `HoldGrace`,
  `HoldBreaks` (visits to `HoldBreak`) and `EarlyWithdrawals` (visits to `EarlyWithdrawal`) are
  recorded per trial; a step back shows as a shorter `HoldDuration`.
- Automatic shaping is meant to grow: choosing easier or harder trial types by performance belongs
  under the same switch.
- A shaped hold shorter than the stimulus window no longer cuts the light off (it did up to
  0.9.4): the light plays to its end while the animal chooses, and a growing hold under light
  costs the light clock (D21).
- Without growth the hold is `lum.HoldShaping.fullHold(S)`: the stimulus window plus the
  post-stimulus hold, or a fixed hold (`S.Task.HoldLength` *Fixed*, `S.Task.FixedHold`), which an
  Experiment session may use (D21).

### D7 — A session barcode before the first trial

**Decision.** Before the first trial, `devices.flex.sendBarcode` runs a state machine of its
own (`lum.sync.barcodeStateMachine`) that drives the sync line through a pulse-width barcode:
a marker pulse, one pulse per bit (0 short, 1 long, most significant first, each followed by
a gap), and a closing marker. The value is the seconds from 2020-01-01 to the session start
(`lum.sync.barcodeValue`), 32 bits by default. It is recorded in `Data.Session.Barcode`
(value, hex, sent, parameters); `lum.sync.decodeBarcode` and `lum.sync.barcodeTime` read it
back from any recording's edge times.

**Why.** Trial pulses align trials within a session but cannot say which session a recording
belongs to. Pulse widths need no shared clock to decode, a closing marker proves a code is
complete, and trial pulses afterwards do not confuse it. Encoding the start time makes the
barcode unique per rig and legible against the data file's own timestamped name. Running it
as a separate state machine before the runner exists keeps it out of trial 1's states and out
of the trial record, and states cost no timers.

**Consequences.**

- About 1.5 s of blocking before the first trial on the rig; nothing in the emulator, which
  has no Flex I/O — the barcode is recorded with `Sent = false` and the device log says why.
- A trial pulse as long as the marker could be mistaken for one; the defaults keep the marker
  at 100 ms against trial pulses of at most 100 ms, and the decoder requires exactly `nBits`
  pulses between markers.
- The markers carry the session type (D11): `MarkerWidth` (100 ms) for behaviour,
  `SleepMarkerWidth` (200 ms) for sleep. `decodeBarcode` returns the kind from the opening
  marker; `Barcode.Kind` is recorded.
- **The barcode shifts Bpod's analog timeline.** `RunStateMachine` starts the Flex analog stream
  on a session's *first* run — the barcode's — and the firmware numbers each sample by run, but
  `AddFlexIOAnalogData` stamps the first sample with `TrialStartTimestamp(1)`. In version 0.2 every
  analog timestamp was therefore ~1.8 s late and every `TrialNumber` one too high, so airflow
  aligned to trial events appeared as the animal reached the reward port (session
  `20260911_140213`; all ten 0.1 sessions, which had no barcode, align to the millisecond). The
  Flex shim counts the runs it makes before trial 1 (`RunsBeforeTrials`), and
  `lum.dev.Flex.alignAnalog` re-anchors the first sample tagged with trial 1 at trial 1's start
  and renumbers the tags at merge.

### D8 — Names say what things are

**Decision.** One vocabulary across code, windows, plots and data
(see [`naming-and-versions.md`](naming-and-versions.md)): channels A
and B; light pattern; joint state; group; stimulus set; stimulus window; hold, hold break,
grace; carrier; British *centre* in identifiers too. Version 0.2 applied it:

| Kind | 0.1 | 0.2 |
|---|---|---|
| States | `WaitForCenterPoke`, `CenterHold`, `WaitForPortOut` | `WaitForCentrePoke`, `CentreHold`, `WaitForCentreExit` |
| States | `Punish` | `IncorrectChoice` (also reached when nothing is punished) |
| States | `CorrectEarlyWithdrawal` | `WithdrewBeforeReward` |
| Data | `StimulusIndex` | `StimulusGroup`, `PatternIndex` |
| Data | `SyncDuration`, `LeftProbabilityUsed` | `SyncPulseWidth`, `BiasTargetPLeft` |
| Data | `Session.Patterns`, `PatternDescriptions` | `Session.StimulusSet` |
| Sync | *Random width* | *Jittered width* (code 2) |
| Settings | `S.Stimulus.Waveform`, `S.Meta.FiberBundle` | `S.Light.Carrier`, `S.Light.Bundle` |
| Settings | `S.Cue.KeepCentrePortLit`, `S.Sound.CueFrequency` | `S.Cue.CentreLightDuringHold`, `S.Cue.ToneFrequency` |
| Settings | `S.Sound.ErrorDuration`, `S.Sound.StimulusFreqRange` | `S.Sound.NoiseDuration`, `S.Stimulus.ToneFrequencyRange` |
| Settings | `S.Sync.Duration`, `MeanDuration`, `Jitter` | `S.Sync.FixedWidth`, `MeanWidth`, `WidthJitter` |
| Runtime | `StimulusOn`, `PortLEDIntensity` | `OptoOn`, `PortLightIntensity` |
| Cue types | `PortLight`, `Sound` | `CentreLight`, `Tone` |
| Code | `lum.pattern.dictionary`, "schedule" | `lum.pattern.stimulusSet`, "pattern" |
| Code | `lum.gui.patternTimerBudget` | `lum.timerBudget` (not a GUI concern) |
| Code | `PulsePal.validateWaveform` | `PulsePal.validateCarrier` |

**Why.** Several 0.1 names were not just awkward but wrong: `LeftProbabilityUsed` held the
bias target, not the stimulus's P(left); `Punish` was visited by unpunished mistakes;
`CorrectEarlyWithdrawal` read as a centre-port event; `Center` and `Centre` sat side by side;
"pattern", "schedule" and "spec" named the same thing. A name that misleads is how a data
field loses its meaning without anyone noticing.

**Consequences.** Outcome, sync mode and punishment *codes* are unchanged. Settings files are
converted on load. Analysis of 0.1 session files must use the 0.1 names; `ProtocolVersion`
says which applies.

### D9 — Stimulus components timed within the hold

**Decision.** Besides the light pattern, stimulus components (air, centre light, a tone per
group) and side components (the rewarded side's port light and tone) each have an onset and
duration from stimulus onset. `lum.stim.isTimed` decides how each is delivered: on for the
whole window, it is an output action of `CentreHold`; otherwise it is a global timer on its
line (`lum.stim.TimedOutput`, with `OnMessage` carrying a port light's brightness). Sounds
never use timers: a delayed onset is silence at the start of the waveform loaded once.

**Why.** The hold must be one state that leaving the port ends at any instant, so there is no
later state to switch a component in; states work for the cue because the cue ends on a poke
or a timer, not on a withdrawal. The same rule sizes the budget (`lum.stim.timerCost`) and
builds each trial, so they cannot disagree.

**Consequences.** Each timed component costs a timer; the side light at most one (only the
rewarded side's runs). A cue component switched off part way through the stimulus follows the
same rule and costs one too (D12). All stimulus timers are triggered and cancelled in one mask built by
`buildTrialSM`. In the emulator, cancel is only partly implemented, so a timed component still
waiting for its onset starts after an early withdrawal.

### D10 — A broken hold restarts the stimulus, within a hold window

**Decision.** The stimulus is delivered only while the animal holds: a broken hold stops it (a
completed one leaves the light to play to its end, D21). When a hold breaks
beyond its grace, `EarlyWithdrawal` cancels the stimulus and, with `S.Task.OnHoldBreak` set to
*Restart stimulus* (the default), leads back to `WaitForCentrePoke`, where the cue comes back
on: the next poke starts the latency (D12) and `CentreHold` again, and `CentreHold` triggers every
stimulus timer from its beginning. *End trial* keeps the 0.2 behaviour (`EarlyWithdrawal` → the
ITI, through `WaitForLightEnd`, which passes straight on: the light and its clock were cancelled). Either way the trial
is bounded by the **hold window**, `S.GUI.HoldWindow`: a global timer triggered in `TrialStart`,
never cancelled or re-triggered. `WaitForCentrePoke` has no state timer; it leaves for
`NoInitiation` on that timer's end, or at once on condition 4 (`GlobalTimer<w>` low) when it is
re-entered after the window ran out during a hold. A hold under way when the window ends may
finish.

```
CentreHold --Port2Out--> EarlyWithdrawal --Tup--> WaitForCentrePoke --Port2In--> [PreStimulusHold] --> CentreHold
                                                        | hold window over (timer end, or condition 4)
                                                        v
                                                   NoInitiation --> WaitForLightEnd --> ITI
```

**Why.** The animal has to receive the whole stimulus before it may choose, and a naive animal
breaks often; ending the trial at each break wastes the cue and the trial. Restarting from the
beginning keeps every delivered stimulus identical. The bound has to span restarts, which a state
timer cannot (it restarts on each entry), so it is a global timer from trial start — the window
the old `InitiationWindow` state timer only approximated, and renamed so the name says so. Adding
transitions rather than states keeps the trial-flow contract.

**Consequences.**

- The hold window costs one global timer on every trial (`lum.timerBudget`, `reserved.HoldWindow`),
  and condition 4 is used. The emulator's five timers leave four for light (three when the light
  clock is reserved, D21).
- Outcome `HoldNotCompleted` (code 6): `NoInitiation` reached after `CentreHold` was visited.
  `NoInitiation` now means the stimulus never started. `EarlyWithdrawal` is the outcome only when
  `EarlyWithdrawal` was visited and `WaitForCentreExit` was not. `HoldAttempts` (visits to
  `CentreHold`) is recorded per trial.
- The early-withdrawal punishment runs at each break, before the animal may poke again.
- `EarlyWithdrawal` is not a trigger state in restart mode (D3).
- `WaitForCentrePoke` plays the cue again, and a cue tone would cut a punishment noise off, so
  with a cue tone `EarlyWithdrawal` lasts at least the noise (D12).
- `lum.validateSettings` refuses a hold window no longer than the latency and the first hold.
  `mergeSettings` renames `GUI.InitiationWindow` → `GUI.HoldWindow`.

### D11 — Two session types: behaviour and sleep

**Decision.** `LuminoseFM` first asks what kind of session is starting
(`lum.gui.SessionTypeDialog`, preselected from `S.Session.Type`). *Behaviour* runs the task as
before. *Sleep* hands over to `lum.sleep.run`: a reduced setup dialog
(`lum.gui.SleepSetupDialog`, sharing the experiment panels through `lum.gui.ExperimentForm`),
validation (`lum.sleep.validate`), Flex I/O only, the session barcode with sleep markers, then
sync pulses on a clock — `S.Sleep.Sync.Interval` ± `IntervalJitter`, widths fixed or jittered as
for trials — for `S.Sleep.DurationMinutes`, with a figure of the pulses sent (`lum.sleep.Plots`).
Pulses go out in blocks of about 10 s, run with blocking `RunStateMachine`, on the rig as in the
emulator. Since 0.5 the pulses are laid out before the first block (`lum.sleep.syncPulseTimes`),
cut into blocks by `lum.sleep.nextBlock`, and each block is a state machine of `LevelNNN` states,
one per span between edges of its lines (`lum.sleep.blockStateMachine`) — which is what lets test
pulses share the blocks (D13); before, a block was `PulseNNN`/`GapNNN` states sized by
`lum.sleep.pulsesPerBlock`. The data file records `Session.Type` and, for sleep, `SyncPulses`
(`Onset`, `Width`, `Block`), and `LightSegments` with test pulses.

**Why.** Pre- and post-behaviour sleep is recorded on the same acquisition devices, so it needs
the same kind of timeline and a barcode that says which kind of session a recording holds. States
give pulse widths the state machine's own cycle and cost no timers; blocks let the plot and the
file follow the session without MATLAB in the timing of any pulse. With nothing to prepare between
blocks, `BpodTrialManager` buys nothing; each onset is read from the state machine's timestamps,
so the upload between blocks only lengthens one interval, visibly.

**Consequences.**

- One protocol, one settings file per subject: `S.Sleep` is read only by sleep sessions.
- Sleep data use the same `Session` record shape and the analog realignment (D7).
- `lum.sleep.run` releases every `lum.*` object before `LuminoseFM` calls `RunProtocol('Stop')`.
- A session is capped at 500,000 pulses, since the pulse record is preallocated and rewritten at
  every save.

### D12 — The cue lasts until the stimulus starts, a set latency after the poke

**Decision.** The cue asks the animal to start a trial, so it is on until the animal has: every
enabled cue component (centre light, tone, air) is an output of `WaitForCentrePoke`, which has no
timer of its own and is bounded only by the hold window (D10). The stimulus starts
`S.Stimulus.Latency` seconds after the poke (Stimulus tab; 0 by default):

- **Latency 0** — the poke leads straight to `CentreHold`, which starts the stimulus; there is no
  state between them.
- **Latency above 0** — the poke enters `PreStimulusHold`, which lasts the latency, starts
  nothing and leaves the cue on. Its timer leads to `CentreHold`; leaving the port leads to
  `EarlyWithdrawal`, a broken hold like any other (punished, then restart or end, as
  `S.Task.OnHoldBreak` says). Grace is timed from stimulus onset and does not forgive it.

`PreStimulusHold` exists in every trial, unreachable at latency 0, as `HoldBreak` is without grace.
From stimulus onset each cue component does what its row of `S.Cue.Components` says, as compiled
by `lum.cueTiming`:

- *Whole* — `ThroughStimulus` ticked ("continues", the default), or a `Duration` spanning the
  stimulus window: on until the hold ends. Re-asserted by `CentreHold`, switched off in
  `WaitForCentreExit`, `EarlyWithdrawal` and `NoInitiation`.
- *Off* — `Duration` 0: switched off by `CentreHold`, as the stimulus starts.
- *Timed* — a shorter `Duration`: a centre light or air is a global timer (onset 0, that
  duration, on its line) triggered with the stimulus in `CentreHold` and cancelled with it;
  the tone plays `CueTail`, that much of the tone ramped off, in place of its loop.

Cue components contribute `outputActions` (the wait), `onsetActions` (stimulus onset) and
`stopActions`. The cue tone is loaded as a seamless loop (`Cue`, `LoopMode` on, looping for up
to the hold window's upper limit) so it lasts however long the wait does.

```
TrialStart --> WaitForCentrePoke (cue on) --Port2In--> [PreStimulusHold (latency, cue on)] --> CentreHold (stimulus on; cue continues, off or timed)
                    ^                                            |                               |
                    +---------------------------- EarlyWithdrawal <------------------------------+  (Restart stimulus: the cue comes back)
```

**Why.** A cue of fixed length from trial start does not say what it is for: an animal that
poked after it had ended got nothing to act on. Keeping it on until the stimulus makes it the
instruction "poke and hold", and returning it after a broken hold says the same again. In 0.3 a
runtime pre-stimulus hold of 50 ms put a delay between every poke and the light that nobody had
chosen, and leaving during it re-armed the trial unpunished; the operator saw the stimulus
arrive late. Here the delay is a pre-session setting whose default is none, and when it is set,
holding through it is part of the task, so leaving is a broken hold. It is pre-session rather
than runtime because it changes what a trial is, like the stimulus window beside it. Timing the
cue's end from stimulus onset puts it on the same clock as every other stimulus component (D9).

**Consequences.**

- The `Cue`, `Cue2`… states, `lum.cueSchedule`, the cue rows' `Latency`,
  `S.Cue.CentreLightDuringHold` and `S.GUI.PreStimulusHold` are gone. `lum.mergeSettings`
  converts 0.3 cue rows so that each component keeps doing what it did during the stimulus (the
  centre light follows its old hold setting, the tone and air go off as the stimulus starts), and
  retires the runtime pre-stimulus hold rather than carrying it into `Latency`.
- At latency 0 a brief beam break starts the stimulus, and leaving at once is a broken hold. A
  latency is the debounce, and costs the delay (see open questions).
- The latency adds to the hold from the poke: `lum.validateSettings` requires the hold window to
  be longer than the latency plus the first hold. `HoldDuration` (and hold shaping) stays the hold
  from stimulus onset. Scoring needs nothing new: leaving during the latency visits
  `EarlyWithdrawal` without `CentreHold`, so `HoldAttempts` is 0 and the outcome is
  `EarlyWithdrawal` (End trial) or, if the window then runs out, `NoInitiation`.
- A timed cue light or cue air costs a timer (`lum.stim.timerCost`). A cue component that stays
  on into the stimulus cannot share its line with a stimulus component (`cueClash`).
- The HiFi module plays one sound at a time, and a play command replaces the sound playing. Two
  sounds that start with the stimulus — stimulus tone, side tone, a cue tone that continues into
  it — are refused (`soundClash`). With restarts and a cue tone, `EarlyWithdrawal` lasts at least
  `S.Sound.NoiseDuration` when it plays the noise, so the returning cue tone does not cut it off.
- Task-event sync goes low on the poke: in `PreStimulusHold`, or in `CentreHold` without a
  latency.
- The cue loop has no onset ramp (a ramp would be heard at every repeat); its tail is ramped off
  but not on, since it takes over mid-tone.

### D13 — Test pulses in sleep sessions: one timeline of gates, cut into blocks where it is safe

**Decision.** A sleep session may send *test pulses* (`S.Sleep.TestPulses`, off by default): probes
— a single pulse or a pair, one epoch every inter-epoch interval — and named plasticity trains
(theta burst and high frequency provided), in a schedule of steps: probe, rest or a train, on A and
B, on one of them, or alternating epoch by epoch. The default (0.9.2) is paired probes alternating
between A and B every 30 s, for as long as the recording lasts: light on both channels at once would give an evoked response
with two sources, so both at once is the operator's choice (*A and B*), never the default. They are
delivered by the D1 split: Bpod gates
BNC1/BNC2, and PulsePal, gated, fills each gate — with constant light for a probe, so the gate is the
pulse, and with the train's pulses for a burst.

- `lum.sleep.testPulsePlan` compiles the schedule before the session into every gate of light
  (*segment*: onset, duration, channel, step, epoch) and every *epoch* (a probe, or one train), in
  integer cycles of the 100 µs clock, and each step's carrier. A burst's gate runs from its first
  pulse to half way through the gap after its last, so PulsePal completes the last pulse and cannot
  begin another. A probe step of M minutes holds `floor(60 M / interval)` epochs, each followed by a
  whole interval inside the step; a train step lasts `nTrains × TrainInterval`. The last probe or
  rest step may last until the recording ends (Minutes `Inf`, the default schedule): it takes what
  the earlier steps leave of `S.Sleep.DurationMinutes`, and the recording lasts that long. Otherwise
  the recording lasts as long as the schedule. The sleep dialog's duration is editable exactly when
  the recording has a length of its own (`lum.sleep.untilRecordingEnds`).
- `lum.sleep.syncPulseTimes` lays out the sync pulses over the same span, and `lum.sleep.nextBlock`
  cuts the two into state machines of about 10 s: only at a moment when every line is low, never
  inside an epoch, and before the first epoch of the next step — shortened until the block fits
  `MaxStates − 2`. `lum.sleep.blockStateMachine` makes one state per span between edges of the sync
  line, A and B, holding each at its level.
- PulsePal is given a step's carrier between blocks, with every line low, after answering a
  handshake, and is asked again at every save; a failure ends the session with what was sent saved
  and `Session.TestPulses.StoppedReason` set. A sleep session opens PulsePal through
  `lum.dev.openPulsePal` (via `lum.sleep.deviceSettings`), so a session with test pulses is refused
  without it, on the same terms as behaviour.
- `lum.sleep.validateTestPulses` adds the checks that depend on the session around the schedule:
  darkness after every epoch long enough for a whole sync pulse plus 1 ms, and the busiest epoch,
  with the sync pulses that can fall inside it, within one state machine.
- The file stores the compiled steps once (`Session.TestPulses`) and one row per gate sent
  (`LightSegments`); `lum.sleep.epochShape` recovers the pulses PulsePal put in a gate.

**Why.**

1. *The same light path as behaviour.* A probe during sleep and a stimulus during the task reach the
   bulb through the same BNC → PulsePal → LED chain with the same programming code, so responses are
   comparable, and the refusal that protects behaviour (D1) protects sleep.
2. *States, not timers or MATLAB.* Four hours of paired probes is 28,800 gates. Global timers cannot
   hold that (16 on the rig, 5 in the emulator, and no `LoopMode` in the emulator), and MATLAB cannot
   time it. Edges as states cost nothing from the timer budget, run the same in the emulator, and put
   every onset in the trial record. A second of 100 Hz pulses as states would be 200 of them; as one
   gate that PulsePal fills, it is two.
3. *One timeline, cut where pausing costs nothing.* Sync pulses and light share each state machine,
   so they are laid out together. Between blocks every line is low for the few milliseconds of the
   upload; cutting only there makes that pause lengthen one dark interval, visibly in the data, and
   never a pulse. Never splitting an epoch keeps a pair's interval and a theta rhythm exact. Cutting
   before a new step's first epoch is what lets PulsePal change carrier with no light in flight.
4. *A handshake, repeatedly.* A sleep session holds one carrier for hours and sends PulsePal nothing
   that could fail; a device lost in hour two would go unnoticed while the file recorded light.

**Consequences.**

- Sleep block states are `Level001`… (were `Pulse001`/`Gap001`); `lum.sleep.pulsesPerBlock` is gone.
- Every epoch must be followed by the longest sync pulse plus 1 ms of darkness, and one session holds
  at most 500,000 gates.
- Intervals across a block boundary are longer by the time spent between blocks (upload, plot, and
  a save every sixth block), so a long session runs somewhat longer than its schedule; onsets in the
  data are the state machine's own.
- Train definitions are checked only while plasticity trains are on, so an unfinished one does not
  block a session of probes.
- In the emulator the gates drive BNC1/BNC2 on the console and PulsePal's programming is logged;
  the emulator keeps no millisecond time, so an emulated interval is only a lower bound.
- The designer (`lum.gui.TestPulseDesigner`) and the sleep setup dialog run the same compilation
  and validation as the session.

### D14 — Video through SpinCam, recorded off the MATLAB thread

**Decision.** Every session is recorded on video by SpinCam, the lab's multi-camera package — a
repository of its own, named by `S.Camera.SpinCamFolder` or found on the path, never copied in.
`lum.dev.open` gives a `lum.dev.Cameras` shim like any other device: `RealCameras` wrapping a
`spincam.CameraManager` (Spinnaker cameras on the rig; SpinCam's `mock` cameras in the emulator,
which run the same native engine) or `NullCameras`. `lum.dev.configureCameras` is the one
definition of how `S.Camera` becomes camera state — used by the session and by the setup dialogs'
live preview (`lum.gui.CameraSetup`), so the preview is what will be recorded. Recording starts
right after the devices open, before the barcode, and stops only after the final save (and, in a
behaviour session, after the trial manager is closed): `Cameras.finishRecording` marks
`SessionSaved` on the camera clock and stops, and a second small save adds the recording summary
to `Data.Session.Cameras`. Everything the data file holds is therefore on the video. The default
format is `avi-mjpeg-mt`, SpinCam's multi-core MJPEG encoder. Files go to
`Session Videos` beside `Session Data`, each named `<view>_<data file name>` (spincam's
`<camera>_<fileName>` with no date appended). Frames log the cameras' TTL input passively. Once per
trial (per block in sleep) MATLAB marks the host clock (`Cameras.mark`: one `hostTime` read and one
`_events.csv` line), stored as `Data.CameraTime`. The session's camera window
(`lum.gui.CameraWindow`) reads one preview frame per camera at `S.Camera.WindowRate` (5 Hz) from a
timer, and SpinCam keeps preview snapshots at that rate only (`PreviewMaxHz`, 0 when the window is
off). On the rig a session asking for video refuses to start without SpinCam or a ticked camera.

**Why.** MATLAB is single-threaded and blocks in `RunStateMachine` in the emulator; copying a
frame into MATLAB costs ~0.7 ms. SpinCam grabs, decodes the embedded TTL, queues and encodes on
native threads, so the video costs the trial loop nothing but the per-trial mark, and a slow
encoder never delays a trial (overflow is flagged per frame, never silent). A second MATLAB process
would isolate the cameras further but adds start-up, IPC and failure modes for no gain in the
recording, which is already off-thread. Passive logging keeps the cameras free-running, so a
missing or unwired sync line costs alignment precision, not frames. The per-trial mark gives an
alignment to within a few ms (the time a trial's events take to reach MATLAB, averaged by a fit)
until Flex2 is wired to the cameras' Line0, when the barcode and trial pulses mark frames directly.
A session that silently records no video is found only afterwards, hence the refusal (as for
PulsePal, D1).

**Consequences.**

- The camera window's timer runs in MATLAB and may delay a prepare window by a few ms; it is
  optional, closable, and never touches the recording. Its frame copies and drawing do cost CPU:
  with SpinVideo's single-threaded `avi-mjpeg`, which is only 4 % faster than 100 Hz full frame,
  that was enough for the writer queue to grow 1–2 frames/s (writer drops after ~15 min). With
  `avi-mjpeg-mt` (several encoder threads per camera) the queue stays at 1–2 frames at 100 and
  120 Hz; `lum.dev.Cameras.formatNote` warns when a single-threaded format is chosen above its
  rate.
- The video stops after the save, so the final save's `Session.Cameras` has no summary yet; the
  second save adds it. A session whose second save fails keeps a file without the summary, and
  SpinCam's `_session.json` still has it.
- In a session that failed, the state machine may run the trial it was in until
  `RunProtocol('Stop')`, which comes after the video has stopped (nothing from `+lum` may run
  after Stop). That trial is not in the data file either.
- `matlab-*` formats are refused: they drain from a MATLAB timer the trial loop would starve.
  Each offered format has one sentence in `lum.dev.Cameras.FormatDescriptions`, shown as the
  dropdown's tooltip and so on the setup dialogs' help line, changing with the choice.
- SpinCam checks for Spinnaker's SpinVideo component only when recording starts;
  `lum.dev.openCameras` checks for the formats that need it when the devices open, so a session
  is refused (or, in the emulator, records no video) before anything is sent to the rig.
- The emulator's timing stretches further with simulated video, so the timing tests run without
  it and `cameraTest` runs its own sessions with it.
- Crops are part of the settings (`Roi`, `[]` = full frame): a crop left in a camera by another
  program is reset, not silently recorded.
- `lum.dev.Cameras.sessionRecord` is `Data.Session.Cameras`; SpinCam's own `_session.json` holds the
  full camera state.
- Flex2 has reached both cameras' Line0 since 2026-09-17 (3.3 V TTL through the splitter). The first
  wired session logged all 79 pulses on both cameras and decoded the barcode from each, so
  `TTL_State` is the frame-accurate alignment and `CameraTime` the fallback. A frame samples the
  line once, so with video the line is fitted to the cameras: `lum.sync.fitToCameras` widens every
  barcode element and sync pulse to ≥ 2 frames, with bit and marker widths ≥ 3 frames apart, at
  session time (typed widths are minimums, kept in the settings file; the fitted ones are sent,
  recorded and listed in `Session.SyncFit`). A warning would rely on the operator; this cannot be
  got wrong. Its decoding is tested by sampling barcodes at 25–150 Hz, every phase, 5 % rate error.

### D15 — The house light is PulsePal's, looped back into Bpod

**Decision.** The house light is driven by **PulsePal output 3**, not by Bpod. OUT3 goes through a
BNC splitter to the light's LED driver, and the copy into **Bpod's BNC input 1** (`rig.HouseLight`:
`PulsePalChannel` 3, `Voltage` 5, `Input` `'BNC1'`, events `BNC1High` / `BNC1Low`). It switches the
moment the operator asks, during a trial or a sleep block included. It starts at `S.Session.HouseLight`
(behaviour, setup dialog's Experiment tab) or `S.Sleep.HouseLight` (sleep setup dialog) — two settings,
so one settings file can light sleep and leave behaviour dark — and is switched during the session
from the **House light** box in the live figure's header (`lum.gui.houseLightSwitch`, in both
`lum.OnlinePlots` and `lum.sleep.Plots`). The device is `devices.houseLight` (`lum.dev.HouseLight`:
`RealHouseLight` on the rig, `NullHouseLight` in the emulator).

- **Holding it.** The level is OUT3's *resting voltage* (`lum.dev.PulsePal.holdVoltage`, parameter
  17), 5 V on and 0 V off, which the firmware returns every output to after a stop, an abort or a
  disconnect (`killChannel`), so the level holds through `stopOutputs`, carrier programming and
  everything the state machine does. The resting voltage alone does not change the output:
  firmware v21 (`PulsePal_2_0_1.ino`, op 74 with parameter 17) calls `dacWrite()` without setting
  that output's `DACFlags`, and `dacWrite()` updates only flagged outputs. So `holdVoltage` then
  writes the voltage itself (op 79, `SetPulsePalVoltage`), which sets the flag. Until 0.7.0 only
  parameter 17 was sent, and the light never switched on (found on the rig 2026-09-21). `holdVoltage` also unlinks the output from both
  trigger inputs, so no gate on BNC1 or BNC2 can play a train on it. It is set when `lum.dev.open`
  opens the device, and to 0 V when the device is closed at teardown, before PulsePal.
- **Timing it.** The loopback makes a switch an input edge of the running state machine, timestamped
  on Bpod's clock to 100 µs like any other event: `BNC1High` (on), `BNC1Low` (off). Every switch is
  also a `HouseLight` mark on the camera clock and a wall-clock time in `Session.HouseLight.Switches`.
- **Recording it.** `Data.HouseLight`, the level each trial or block started at, is read from the
  trial's own events (`lum.dev.HouseLight.levelAtStart`): an off edge first means it started on. A
  trial with no edge held one level throughout, which is the level PulsePal held at its start on
  MATLAB's clock (`levelAt`, the arrival of its events less its length). At teardown
  `Session.HouseLight` gets every edge on Bpod's clock, with its trial (`edges`).
- **Sharing PulsePal.** A click runs its callback inside any `pause` or `drawnow` — PulsePal's
  handshake pauses 0.1 s, and its serial code pauses too. So `lum.dev.PulsePal` counts the commands
  talking to the device, and a voltage asked for during one is sent the moment it finishes (the
  latest request per output wins). The light, the camera mark and the windows change then, not at the
  click. A switch PulsePal refuses warns and puts the boxes back to the light as it is.

**Why.** 0.6.1 first drove the light from port 5's LED line (`PWM5`): a long global timer linked to
the line held it through each state machine, and Bpod's output override switched it. It worked, but
cost one global timer in every trial (three left for light in the emulator), had to be threaded into
every state machine the session ran (trial, barcode, sleep block), dropped the light between state
machines (one cycle between trials, an upload between sleep blocks), and needed a trial queued before
a switch to be corrected once it started. The switch is the operator's, not the task's: nothing in the
state machine reacts to it, so it has no reason to live there. PulsePal holds a level with no state
machine at all, and the loopback keeps what Bpod did give — the switch on Bpod's clock — for the price
of a cable. Soft codes (the other way to mark it) are sent from MATLAB after the fact, ms late; the
edge is the light's own command line.

**Consequences.**

- The house light costs no global timer, no output and no state: 15 timers for light on the rig, 4 in
  the emulator. No state machine takes it into account.
- **Every session on the rig opens PulsePal**, behaviour, sleep or ePhys calibration. One with light refuses to start
  without it (`lum.dev.openPulsePal`); one without light runs on the null shim, warned, and
  `lum.dev.openHouseLight` gives it `lum.dev.DisabledHouseLight`: off, `Switchable` false, the box
  greyed out, `Data.HouseLight` all 0, and the level the settings asked for kept in the settings
  file. The same happens when a connected PulsePal does not take the light's level, in a session
  without light only. Port 5 is unused.
- `hardware/TestHouseLight` checks the whole path on the rig: soft codes from a state machine switch
  the light through `lum.dev.HouseLight.set`, and every switch must come back as a BNC1 edge; it
  prints the latency of each.
- A switch between state machines (before the first, between sleep blocks, in the gap before a
  blocking emulator trial) has no Bpod timestamp; it is on the camera clock and in `Switches`.
- BNC input 1 must stay enabled in the console's port settings (`CheckRig`, and `RealHouseLight`
  announces it when it is not). Nothing else may use BNC input 1 or PulsePal output 3.
- In the emulator `NullHouseLight` puts the edge into the running emulated state machine (the route
  the console's BNC input button takes), so the data look as on the rig.

### D16 — A session leaves its figure and its settings behind

**Decision.** At teardown, before the final save, the online figure (behaviour or sleep) is saved as
`<data file name>_plots.png` beside the data file by `lum.gui.savePlotsImage` (`exportapp`), and its
path is recorded as `Data.Session.PlotsImage`. The plot figures' `CloseRequestFcn` only hides them;
their `close()` deletes. After the final save the settings are written back to the settings file the
session started with (captured as `settingsFile` before the loop), with the runtime tier as the
session left it and the house light where the operator left it. Headless sessions write no settings.

**Why.** The console's End button runs `RunProtocol('Stop')` *before* the protocol's teardown: it
closes every figure in `BpodSystem.ProtocolFigures` and clears `BpodSystem.Path.Settings`. A figure
that could be closed would be gone by the time the teardown saves it, and `SaveProtocolSettings`
would have no file. `exportapp` is the one exporter that takes these figures (D14's notes:
`exportgraphics` and `print` refuse them). The settings file already held the settings as Start was
pressed; writing it again means runtime changes (reward, timing, the house light) carry over, which
is what an operator adjusting an animal over days expects, while each data file keeps the exact
settings it ran with.

**Consequences.**

- Closing a plot window during a session hides it; it is still updated and saved.
- The protocol runs through MATLAB's `run`, which makes the protocol folder the current folder, so
  `+lum` still resolves in a teardown that follows the End button's `rmpath`.
- Windows with a timer are not protocol figures (0.8.1). The End button's callback can run inside
  any `drawnow` or `pause` that processes callbacks, including one in a timer callback. The camera
  window was registered with Bpod and drew with `drawnow limitrate` from its timer, so Stop could
  close it, and stop and delete its timer, from inside that timer's own callback; on the rig this
  froze MATLAB, and after Ctrl+C the protocol's workspace was cleared outside the protocol folder,
  so the timer and `lum.SessionRunner`'s destructor could no longer find their classes. Now the
  camera and LED windows are closed by the teardown, first; the camera timer draws with
  `drawnow limitrate nocallbacks`, is stopped by its figure's `DeleteFcn`, and runs through a local
  function that stops it, with built-ins only, whenever the window cannot refresh. Any new timer
  that draws follows the same rules.
- A settings file is a *last session* file: to keep a set of settings apart, create another settings
  file in the launch manager.

### D17 — The Doric LED sets the intensity; Bpod and PulsePal keep the timing

**Decision.** The Doric LED driver (`LEDFLS_465_465`) is controlled from MATLAB through the DoricLED
package, a package of its own outside this repository, found on the path or in `S.Doric.Folder`.
Both LED channels run in **external TTL mode** for every session: a channel is lit at its LED current
while PulsePal's output into its TTL input is high, so D1's split stands and the state machine is
unchanged. What MATLAB adds is the current:

- **One device shim.** `lum.dev.DoricLED` wraps a `doric.LightSource`: on the rig through the
  package's bridge ('Device'), in the emulator through its `SimulatedTransport` ('Simulated'), and
  none at all ('Manual') without the package or with `S.Doric.Enabled` off, when the driver is used
  as set by hand. `lum.dev.openDoricLED` chooses; `lum.dev.open` stays the only reader of emulator
  mode, through `lum.dev.open(rig, S, 'Only', 'DoricLED')`.
- **Connected at launch.** Connecting takes several seconds, so `LuminoseFM` opens the LED before the
  session type dialog and it connects in the background while the operator sets up. The setup
  dialogs' Doric LED tab (`lum.gui.DoricSetup`) shows it, calibrates with it and opens the package's
  own window on it; the session then waits for it (`ensureReady`) and sets both channels up
  (`setUp`: limits, external TTL at the currents `lum.led.intensity` gives, started). Every way out of the protocol
  releases it, and teardown closes it first, so both channels are off before PulsePal is released.
- **Changed only between light.** The LED window (`lum.gui.DoricWindow`) asks for a current
  (`request`); `applyPending` sends it in the next prepare window (behaviour, after the running
  trial's stimulus: every trigger state follows it, D3) or between sleep blocks, with the
  package's non-blocking fast path, and returns the current the next trial runs at. An ePhys
  calibration step's current is sent between blocks and waited for (`setCurrents`, D18).
- **Refused, not degraded, on the rig.** A session with light whose LED is controlled does not start
  if the driver does not connect or refuses its settings; unticking the control runs it with the
  driver as set by hand. A session without light runs on with a warning. An ePhys calibration
  session needs the control. The emulator never refuses.
- **Asked for in mW/mm² where calibrated, sent and recorded in mA (0.9.1).** Each channel's light
  path (the channel and the bundle cable on it, `lum.led.lightPath`) uses the calibration of that
  cable measured on that channel, if there is one (`lum.led`): power meter readings at several
  currents, divided by the cable's fiber area (spots × π × (50 µm)²). Each session type keeps its
  intensity per channel in two forms (`lum.led.intensitySetting`): irradiance
  (`S.Doric.IrradiancemWmm2`, 8 mW/mm² for behaviour; `S.Sleep.TestPulses.IrradiancemWmm2`, 2 for sleep
  test pulses; `S.Ephys` per protocol) and current (`S.Doric.CurrentmA`, `S.Sleep.TestPulses.CurrentmA`,
  `S.Ephys.*mA`). As the session starts, `lum.led.intensity` turns each calibrated channel's
  irradiance into whole mA (`lum.led.currentFor`: linear interpolation, never extrapolating, never
  above the channel's limit; asked for more than the channel gives, it runs at the most it gives, with
  a note) and uses the mA on a channel that is not calibrated. What was sent is mA
  (`Data.LEDCurrentA/B`, `LightSegments.CurrentmA`), and `Session.DoricLED.Intensity` records what
  was asked for and started at. Windows show and take a calibrated channel's intensity in mW/mm²
  (`lum.gui.IntensityField`), an uncalibrated one's in mA. Calibrations live in `calibration/` at
  the repository root, one file per bundle, cable and channel (`DoricLED_<bundle>_<cable>_<A|B>.mat`),
  replaced by the next calibration of that cable on that channel, and ignored by git; a per-cable
  file from 0.7.2–0.9.0 is still read for the channel it was measured on. They are measured two cables
  at a time (`lum.gui.DoricCalibration`, 0.8.1), because the commutator takes two: one table, On/Off
  and graph per channel, the channel lit in the driver's continuous mode at the selected current,
  0–1000 mA in 100 mA steps by default (0.9.3; 0–700 mA in 50 mA steps before), starting from the
  cable's saved readings on that channel so that only new currents are measured. A calibration is
  saved and used only when its readings cover the LED's range (`lum.led.checkCoverage`: 4 currents
  above 0 mA, up to 400 mA or more), and is used up to its highest reading whatever the limit.

**Why.**

1. *Timing stays in hardware.* A TTL-gated LED lights exactly while PulsePal's output is high; MATLAB
   and USB latency never enter the light's timing, and the emulator reproduces the pattern as
   before (D1). Nothing is sent per trial: the current is set once at session start, and again only
   when the LED window asks, in the next prepare window, as one non-blocking command per channel
   (about 0.8 ms MATLAB-side; the driver acknowledges in 5–9 ms, DoricLED's `docs/rig-checks.md`),
   while the running trial's light is over.
2. *No cost to Bpod.* No state, output, timer or event is added; the per-trial record gains two
   scalars and the session record one small struct (`Session.DoricLED`, the package's own record
   without its log, which goes to `DeviceLog.DoricLED`).
3. *The operator thinks in irradiance; the driver takes mA.* A setting in mW/mm² keeps its meaning
   when a cable moves or is recalibrated: the session finds the current that gives it on the day.
   The data hold what was sent, in mA, with the calibration used, so irradiance can be recomputed
   from the data and a later recalibration never changes what a file says. The mA form is kept for
   channels without a calibration, so an uncalibrated bundle runs as it did before.
4. *A calibration belongs to a cable on a channel.* Until 0.9.0 the two LED channels were taken to
   give equal power at equal current and a calibration was keyed by bundle and cable only. On the rig
   the light leaving a cable also depends on the LED and the commutator channel feeding it, so from
   0.9.1 it is keyed by bundle, cable and channel: a cable used on both channels is calibrated on each.
5. *Optional by design.* The protocol runs without the package, as it did before 0.7.0, with the
   driver set by hand; nothing else changes.

**Consequences.**

- `Data.LEDCurrentA/B` is NaN when the LED was set by hand. `Session.DoricLED.Controlled` says which.
- The emulator's LED answers like the device and logs every command; the LED window's first drawing
  can hold up the emulator's loop, so timing tests run without it (`S.Doric.ShowWindow`).
- A current changed during a session is acknowledged by the driver; whether the brightness follows
  at once in external TTL mode is a rig check (`rig-checks.md` P3).
- The package keeps the 1000 mA ceiling of the 465 nm LED (`doric.Channel.DeviceMaxCurrentmA`);
  `S.Doric.MaxCurrentmA` is refused above it here as well. It is 1000 mA by default since 0.9.3
  (700 mA, Doric's recommended current for an LED held on, before): the LED is rated 1000 mA, the
  driver's front panel offers 1000 mA in continuous mode, and in a session the light is gated, not
  held. The package's own default limit stays 700 mA; `lum.dev.DoricLED.setUp` sets the session's.
  0.9.2 settings files holding 700 mA take 1000 mA (`lum.mergeSettings`). The driver's front knob
  caps the current independently of USB, so it must be turned up to 1000 mA as well.
- `hardware/TestDoricLED` checks the whole light path on the rig, from Bpod's BNC outputs through
  PulsePal to the driver, at one or more currents. Whether light comes out is checked by eye: the
  driver cannot be read back.

### D18 — ePhys calibration sessions: steps of light, run as a sleep session is

**Decision.** A third session type, `'EphysCalibration'`, sends light pulses whose intensity or pairing
changes step by step, for the response recorded on the probe: an **input-output curve** (single pulses
in `nLevels` steps; on a calibrated channel from `S.Ephys.InputOutput.MinIrradiancemWmm2` to
`MaxIrradiancemWmm2`, 0–12 mW/mm² by default and capped at the most the channel gives, evenly spaced
in irradiance; on one that is not, from `MinmA` to `MaxmA`, NaN meaning the channel's limit, spaced in
mA) and a **paired-pulse ratio** (pairs at `S.Ephys.PairedPulse.IrradiancemWmm2`, 8 mW/mm², or
`CurrentmA` where not calibrated; one step per inter-pulse interval, 20–500 ms by default). Each step sends `Repeats` epochs, one every
`InterEpochInterval` (1 s by default), on A, B or both; the steps of each protocol run ascending,
descending or shuffled from a seed.

- `lum.ephys.plan` compiles each step through `lum.sleep.testPulsePlan` as a probe step and joins them
  into one plan of the same shape, with each step's `CurrentmA`, `IrradiancemWmm2`, `Protocol`,
  `Label` and `InterPulseInterval`. `lum.ephys.validate` checks it with the checks sleep sessions use,
  now shared (`lum.sleep.validateClock`, `lum.sleep.checkTimeline`), and requires the LED control.
- `lum.sleep.run` runs it: the same blocks (`nextBlock` cuts before every new step), sync pulses from
  `S.Ephys.Sync`, the house light from `S.Ephys.HouseLight`, `lum.gui.EphysSetupDialog` for setup and
  `lum.sleep.Plots` for the live figure. Between blocks, before a step's first epoch, the step's
  current goes to the driver and is waited for; a refusal ends the session with what was sent saved.
- Its barcode has a marker of its own, `S.Sync.Barcode.EphysMarkerWidth` (300 ms: longer than the
  sleep marker, which is longer than the behaviour marker), fitted to the cameras like the others;
  `lum.sync.decodeBarcode` returns the kind. `lum.sync.markerWidth` gives each kind's marker.
- The data file stores `Session.Ephys` (settings, steps, completion) in place of `Session.TestPulses`,
  and `LightSegments` with each gate's step and `CurrentmA`.

**Why.** The light and the timeline are the same problem as sleep test pulses (D13): gates of light
and sync pulses in state machines, cut only where every line is low, with a device reprogrammed
between blocks. Reusing that engine keeps pulse timing in the state machine, costs no global timers,
and gives the ePhys session the same guarantees and data layout. The current changes where PulsePal's
carrier already could, before a step's first epoch, so no light is ever in flight when it does. A
distinct barcode marker lets a continuous Neuropixels or camera recording say which kind of session
each stretch holds.

**Consequences.**

- Bpod does not see the recorded response, so the session's plots show what was sent; the
  input-output and paired-pulse curves are drawn from the probe's data, aligned by the barcode and
  sync pulses, with each gate's step, current and interval from `LightSegments` and `Session.Ephys`.
- `IO` levels that round to the same whole mA are sent as separate steps at that current.
- Settings files from before 0.7.0 have no `EphysMarkerWidth`; their ePhys marker is the sleep marker
  plus the behaviour marker (300 ms with the defaults).

### D19 — Centre reward in habituation, and a retry after an unpunished incorrect choice

**Decision.** Two additions to the behaviour trial, both as states that exist in every trial and
are reached only when the runtime settings ask for them (the centre reward can also be asked for
again later in a session, below):

- **`CentreReward`**, between a completed hold and `WaitForCentreExit`. On trials 1 to
  `S.GUI.CentreRewardTrials` (10) of a habituation session, with `S.GUI.CentreRewardAmount` (1.2 µL since 0.9.4; 1 µL before)
  above 0, the end of the hold (`CentreHold`'s timer, or the hold clock from `CentreHold`,
  `HoldBreak` or `CentreHoldResumed`) leads there; it opens the centre valve (`rig.Valve.Centre`,
  valve 2) for the calibrated time and puts the response configuration up as `WaitForCentreExit`
  does. `lum.nextTrialSpec` decides it (`spec.CentreReward`, `spec.CentreRewardAmount`); the session
  looks up valve 2's time in the prepare window, and without a calibration drops the centre reward
  with one warning.
- **`RetryResponse`**, after a wrong side poke that is not punished (`lum.punishmentFor(...).Retry`:
  `PunishCondition` without *Incorrect choice*, now the default). It lasts 0 s and returns to
  `WaitForResponse`, whose timer starts again; the correct port still pays. A punished wrong poke
  goes to `IncorrectChoice`, which ends the trial unrewarded after the timeout, and lasts at least
  the noise (`S.Sound.NoiseDuration`) when the punishment plays one, because the ITI stops the sound
  module. `EarlyWithdrawal` is stretched the same way when it ends the trial.

The scorer keeps scoring by the first side poke, and adds `CentreRewarded`, `ResponseRetries`
(visits to `RetryResponse`) and `CentreHoldTime`; the data file stores them as `CentreReward` (µL),
`ResponseRetries` and `CentreHoldTime`.

**Why.** A new animal has to learn that the centre port is worth visiting before the hold means
anything, and water there does it fastest; paying the completed hold rather than the poke keeps the
poke's path free of any state (D12), so the stimulus starts exactly as in every other trial, and with
automatic shaping (now on in habituation too) the first holds are 0.1 s. Counting the centre reward
in trials rather than in rewards given keeps `nextTrialSpec` pure: on the rig trial *n+1* is prepared
before trial *n* is scored (D3), so a count of rewards given would overshoot by one. The retry needs its
own state because `IncorrectChoice` opens the prepare window (`lum.triggerStates`): the trial must pass
through exactly one trigger state, and after a retry it still reaches a reward, `NoResponse` or
`WithdrewBeforeReward`. The response window starts again on the retry rather than running on, because
holding it across the retry would take a global timer from the light's budget, which the emulator's
five cannot spare.

**Consequences.**

- The state graph has two more names; analysis that lists states must include them.
- `Outcome` stays the first choice's, so psychometrics are unchanged; a retried trial is `Incorrect`
  with `Rewarded` 1, and water totals must use `Rewarded`, not `Outcome`.
- Settings files keep their `PunishCondition`; only new settings start with no punishment.
- Valve 2 needs a liquid calibration before the centre reward can be used.

**Centre reward again (0.9.0).** In any stage, ticking `S.GUI.CentreRewardAgain` in the runtime
window gives the centre reward on the next `S.GUI.CentreRewardAgainTrials` (10) trials prepared, for
an animal that has stopped coming to the centre port. `lum.centreRewardAgain`, called in the prepare
window before `lum.nextTrialSpec`, keeps the run in the history (`history.centreRewardAgainFrom`, its
first trial; 0 when none): it starts on the first trial prepared with the box ticked, ends when its
trials are done or the box is unticked, and on ending unticks the box, which both runtime windows show
at once (the protocol syncs again; a value the protocol changed is written back to the window).
`nextTrialSpec` rewards a trial the run covers (`spec.CentreRewardAgain`). The latch is outside
`nextTrialSpec` so that it stays pure and returns only the spec and the queue; it counts trials, not
rewards, for the reason above. Nothing in the state graph changes.

### D20 — A stimulus family is a question, with its own contingency and its shortcuts measured

**Decision.** The families are organised by what the subject has to tell apart:

| Family | Question | Groups from |
|--------|----------|-------------|
| `pure` | which channel is lit? | channels × lit fractions |
| `mixture` | how much of the mixture is A? | relative rules: mixture ratios (A's share) or differences (A minus B) at roving totals of light, against a boundary that can move; controls *A alone* / *B alone*: every level with every level |
| `count` (sequence) | which channel flashes more often? | pairs of counts over slots, in a new order every trial |
| `order` | which channel comes first? | A first / B first; the guarded cycle, with a random phase |
| `motif` | which word is it? | words listed for each side |
| `arbitrary` | — | pulses typed by hand |

Each family:

- derives its groups from its own settings, not from a separate group count (only the hand-drawn
  family keeps `nGroups`);
- says which side each group pays (`FamilyPLeft`), and the session uses it whenever
  `S.Task.GroupPLeft` is empty, which is the default. Values the operator types are kept only while
  the group labels stay the same (`lum.pattern.typedPLeft`, in the setup dialog and the designer), and
  are applied to a compiled set by `lum.pattern.applyContingency` without compiling it again;
- names its evidence (`Evidence`, `EvidenceName`) and the boundary its contingency draws in the plane
  of the fractions of the window A and B are lit (`Boundary`: diagonal, vertical, horizontal, or a
  line with a slope and intercept, for a moved mixture boundary); the online plots use both;
- has defaults that compile on the rig and in the emulator, sized to the timer budget
  (`lum.pattern.familyDefaults`), and choosing a family loads them, in the designer and on the setup
  dialog's Stimulus tab.

Every stimulus set measures its **single-cue ceilings** (`lum.pattern.shortcuts`): the best accuracy
of an observer reading only A's amount, B's amount, the total light, A's time course or B's time
course, exactly over the groups, or for the best threshold when every trial has its own pattern. The
dialogs show them in one line and the data file keeps them. Fractions of the window (levels, slots,
overlaps) are shared out over whole bins with the remainder spread one bin at a time, and the bin is
adjusted to divide the window, so no setting has to divide another exactly; segment edges, not
durations, are rounded to the state machine's cycle.

**Why.** The earlier families came from a signal-generation library and were organised by how a
pattern is built (a repeated motif, occupancy of joint states, overlap guards), so choosing one said
nothing about the task. Several defaults did not fit the machine (the overlap order's ten cycles took
20 timers, the tiled order a timer per bin), and cycle counts had to divide bin counts. A task is its
question and its contingency, and whether it tests what it is meant to depends on which simpler cues
also solve it, which the design can state exactly ([`stimulus_family.md`](stimulus_family.md) §5)
rather than leave to be found in the data. Keeping the family's contingency as the default removes the
commonest setup error: a contingency typed for one set of groups applied to another.

**Consequences.**

- Data format: `StimulusSet` gains `FamilyPLeft`, `PLeftFromFamily`, `Evidence`, `EvidenceName`,
  `Boundary`, `Shortcuts` and `Descriptors.ASegments`/`BSegments`, and loses `SweepName`/`SweepValues`;
  `Settings.Task.GroupPLeft` may be empty.
- `lum.mergeSettings` converts old generators: the sequence motif becomes two words, the overlap order
  the guarded cycle, the tiled order the simple order with no overlap, occupancy the mixture's
  defaults; P(left) is kept only where the groups are the same.
- The sequence family's default draws a new order every trial, so a session holds a pattern per trial
  (about five segments each): within what the segment table was designed for (D5).
- Single-cue ceilings of per-trial designs are threshold-based and leave the time courses out.
- The task variant (`S.Task.Variant`) is still only recorded; it does not choose the family.
- The mixture's roving totals leave most pairs lighting far less than the window. From 0.9.2 its
  amounts are spread over the window in cycles by default (`MixtureLayout` `'spread'`,
  `MixtureCycles`), both channels starting every cycle, so the mixture lasts the whole window rather
  than ending early and leaving the rest dark; each cycle costs a timer per channel, so the defaults
  take 5 cycles on the rig and 2 in the emulator. Groups that round to the same light are refused.
  Coding amount as intensity (the LED current per trial) instead of time lit would remove the dark
  altogether; it is not built.

### D21 — The light plays to its end after a completed hold

**Decision.** A completed hold never stops the light pattern (0.9.5). The hold decides only when
the animal may leave and choose; the light runs to the end its pattern gives it, up to the stimulus
window, while the animal leaves the centre port, chooses, drinks or is punished. Only the light
does: the cue, the timed stimulus air, centre light and tone, and the hold clock stop as the hold
ends, as before. A broken hold still stops everything (D10). Before the ITI every trial passes
through **`WaitForLightEnd`**, which waits for the light to end: Bpod drops every output line when
a state machine ends, so the trial must not end before it.

The hold can be shorter than the light in two ways, both decided before the session:

- **A growing hold** (automatic shaping, D6), in habituation or training.
- **A fixed hold** (`S.Task.HoldLength` *Fixed*, `S.Task.FixedHold` seconds from stimulus onset),
  in any stage, an Experiment session included. *Whole stimulus* (the default) is the stimulus
  window plus the post-stimulus hold, as before; a fixed hold ignores the post-stimulus hold, and
  one longer than the window holds past it. A growing hold replaces either.

`lum.HoldShaping.lightMayOutlastHold(S)` says whether a session can have such a trial (light on, and
a growing hold or a fixed one shorter than the window). Such a session:

- reserves **the light clock** (`lum.timerBudget`, `reserved.LightClock`): a global timer as long as
  the trial's light, from stimulus onset, triggered in `CentreHold` with the light and cancelled
  with it in `EarlyWithdrawal`. `WaitForLightEnd` leaves for the ITI on its end, or at once on
  **condition 5** (the clock not running: ended, cancelled, or never started). A trial whose light
  ends within its hold (the growing hold has reached it, or no light this trial) defines no light
  clock, and `WaitForLightEnd` passes straight on (`Tup`);
- prepares the next trial in the **ITI**, its only trigger state (`lum.triggerStates`, D3), because
  the prepare window changes LED currents and may program PulsePal, and the light can still be on
  in every earlier trigger state.

**Why.** Cutting the light off at a shaped hold's end (up to 0.9.4) gave a short hold only the
start of the pattern, so what the animal saw depended on the hold as well as on the pattern, and a
family whose evidence comes late in the window (an order, a sequence, a spread mixture) was not
the same question at every hold. Squeezing the pattern into the hold was the alternative; it would
change amounts in seconds (the evidence of an absolute rule) and leave a short hold only a pulse or
two of the carrier. Letting the pattern run keeps every trial's light what the stimulus set says,
whatever the hold, which also makes a fixed short hold usable in an experiment. The light reaches
the olfactory bulb through the fibres wherever the animal is, so light after the animal has left
the centre port is still delivered. The pattern's own timers cannot tell the state machine whether
light is still to come: a segment waiting for its onset is as not-running as one that has ended.
One timer running from onset can, hence the light clock.

**Consequences.**

- The animal may answer before the light is over. Reward, drinking, a retry or a punishment
  noise can come with the light on. The light's timers (`GlobalTimer<k>_Start/_End`) against
  `WaitForCentreExit` and the side poke show it per trial; `WaitForLightEnd`'s span is the wait.
- One global timer while the hold may be shorter than the light: the rig's 16 leave 14 for light
  (13 with grace), the emulator's 5 leave 3 (2 with grace). Every family's defaults fit each of
  these (`generateTest`); in the emulator the mixture takes fewer cycles and, with 2 timers, the
  motif family two-letter words. The setup dialog loads a family's defaults again when the budget
  changes while the stimulus is still those defaults (choosing Training after a family, say); an
  edited stimulus over the budget is refused, naming its group. Condition 5 is the emulator's last.
- The light clock is numbered after the light, the timed components' and the cue's timers and the
  hold clock, before the hold window; its index varies with the trial's number of segments.
- The next trial is prepared in the ITI: at least `S.GUI.ITI` for the work, as after
  `NoInitiation` and `NoResponse` already. An ITI of 0 s would make the next trial start once it is
  prepared and uploaded.
- `WaitForLightEnd` is a new state in every trial (the trial-flow contract, *Trial engine* below); `Data.Session`
  records `LightMayOutlastHold` and `TriggerStates`.
- `lum.validateSettings` notes a session whose light may outlast the hold, refuses an unknown
  `HoldLength` and a fixed hold of 0 s or less, and checks the hold window against the fixed hold.
  `lum.buildTrialSM` refuses a trial whose light outlasts its hold in a session that did not
  reserve the clock.

---

## What is built, and where

### Rig config, device shims, preflight
- `hardware/RigConfig.m` — the channel map (ports 1–4, channels A/B on BNC 1–2, Flex 2, the house
  light on PulsePal output 3 and BNC input 1, module names) and the connected machine's live limits.
- `+lum/+dev/HouseLight.m` (real, null and disabled; `openHouseLight` chooses) — the house light on
  PulsePal output 3, looped back into BNC input 1, switched at once (D15). `hardware/TestHouseLight.m`
  checks the loopback on the rig. `+lum/launchSubject.m` — the subject the session was launched
  for.
- `+lum/+dev/DoricLED.m` (`openDoricLED` chooses Device, Simulated or Manual) — the Doric LED
  driver: both channels in external TTL mode at their currents, changed between trials (D17).
  `hardware/TestDoricLED.m` checks the light path on the rig. `+lum/+led/` — light paths,
  calibrations, conversions between mA and mW/mm², the LED checks and `Session.DoricLED`.
- `+lum/+dev/` — PulsePal, HiFi and Flex behind a common base (`lum.dev.Device`), each with a
  real and a null implementation, selected once by `lum.dev.open`. The HiFi module falls back
  to its null shim when unreachable; PulsePal does only in a session without light, which then has
  no house light (`lum.dev.openPulsePal`, `lum.dev.openHouseLight`, see D1, D15), and must
  answer a handshake (`checkConnection`) before it is
  used. `Flex` also sends the barcode and opens Bpod's analog viewer. `Cameras` (D14) records
  video through SpinCam: `openCameras`, `configureCameras`, `RealCameras`, `NullCameras`.
- `hardware/CheckRig.m` — preflight report, hardware-only checks skipped in emulator mode.

### Trial engine
`+lum/buildTrialSM.m` assembles one trial. State *names* never change across modalities,
training stages or hold shaping.

```
TrialStart → WaitForCentrePoke (cue) → [PreStimulusHold (latency)] → CentreHold (stimulus)
           → [CentreReward (habituation's first trials)] → WaitForCentreExit
           → WaitForResponse → {*RewardDelay → *Reward → Drinking* → DrinkingGrace
                                | IncorrectChoice (punished) | NoResponse}
           → WaitForLightEnd → ITI → exit
WaitForResponse   → RetryResponse → WaitForResponse   (wrong side, not punished; D19)
PreStimulusHold   → EarlyWithdrawal            (left during the latency)
CentreHold        → EarlyWithdrawal (no grace) | HoldBreak ⇄ CentreHoldResumed (grace)
HoldBreak         → EarlyWithdrawal            (grace ran out)
EarlyWithdrawal   → WaitForCentrePoke          (Restart stimulus) | WaitForLightEnd (End trial)
WaitForCentrePoke → NoInitiation               → WaitForLightEnd   (hold window over)
WaitForCentreExit → NoResponse                 → WaitForLightEnd
*RewardDelay      → WithdrewBeforeReward       → WaitForLightEnd
```

Every trial that ends reaches the ITI through `WaitForLightEnd`, which waits for a light that
outlasts the hold and otherwise passes straight on (D21).

A side reward: `LeftRewardDelay`/`RightRewardDelay` last `S.GUI.RewardDelay` (leaving the port
goes to `WithdrewBeforeReward`); `LeftReward`/`RightReward` open the valve for its calibrated time;
`DrinkingLeft`/`DrinkingRight` close it and wait, with no timer, for the port to be clear
(condition 1 or 2); `DrinkingGrace` lasts `S.GUI.DrinkingGrace` (0.3 s from 0.5), and a poke at
either side port there returns (`>back`) to the drinking state, which leaves again once the rewarded
port is clear, so the grace restarts; its end goes to `WaitForLightEnd`. No drinking state has a
time limit, and none gives more water.

The cue is on in `WaitForCentrePoke`; the poke enters `CentreHold` directly, or after the latency
in `PreStimulusHold` (D12). The hold
window is a global timer from `TrialStart` (D10).

**`WaitForCentreExit`: the response window opens on the withdrawal, not on the hold ending.**
Without it the side ports are live while the animal's nose is still in the centre port, and
the beam break it makes on its way out is accepted as its choice — a reward valve opens the
moment the hold ends, whatever the animal intended. So:

- Reaction time is measured from `WaitForResponse` onset: from leaving the centre port to the
  choice poke.
- `WaitForCentreExit` is where the response configuration goes up: the cue and the stimulus
  components other than the light stop (their timers cancelled, their lines low), the centre
  marker goes off and the guide lights on. The light plays on to its end (D21).
- The wait is bounded by `S.GUI.ResponseWindow` and falls through to `NoResponse`.

Around it:

- `+lum/nextTrialSpec.m` — pure: the queue, run limit and bias correction by swapping,
  contingency, stage, sync width, hold and grace.
- `+lum/HoldShaping.m` — pure: automatic shaping's active mode, the next hold and grace and when
  the hold steps back (D6), break modes (D10).
- `+lum/triggerStates.m` — pure: where the next trial may be prepared (D3, D10).
- `+lum/scoreTrial.m` — pure: outcome, choice, correctness, reward, reaction time, hold
  breaks and hold attempts, centre reward, retries and centre hold time from the fixed state names
  and port events.
- `+lum/punishmentFor.m` — pure: which mistakes are punished and how, and whether a wrong choice
  may be retried (D19). Every punishment state exists whatever the settings; an unpunished early
  withdrawal passes through with a zero timer, an unpunished incorrect choice through
  `RetryResponse`.

### Stimuli
`+lum/+pattern/`: `generate` (families, groups, balanced order, offsets, descriptors, evidence,
boundary, the family's contingency) → `stimulusSet` (segments, budget check) → `applyContingency`
(typed or the family's P(left), `S.Task.ReverseContingency`, the identical-group check, `shortcuts`)
→ `patternAt`. A reversal is applied once, there, so the set, the plots and every trial record read
one contingency; `BasePLeft` keeps the operator's own numbers beside it. `families` lists the
families with their questions, `familyDefaults` loads one's defaults for a timer budget, `typedPLeft`
keeps typed P(left) only for its groups, `shortcuts` and `describeShortcuts` measure and word the
single-cue ceilings (D20). `fromStates`, `canonicalise`, `check`, `validate` and `describe` work on
single patterns; `withGeneratorDefaults`, `defaultPLeft`, `newSeed` and `prepareSeed` support the
windows and the session.

`+lum/+stim/` components share the interface `nTimersNeeded` → `configure` →
`addGlobalTimers` → `outputActions` / `onsetActions` / `stopActions`, plus `sustainActions` and
`sustainOnsetActions` — what a *later* state has to write again to keep a level on, since Bpod
sets every channel from the entered state's own row: `OptoPattern`; `TimedOutput` and its
`PortLight` (roles `Centre` and `Target`, the rewarded side) and `Air`; `Sound` (names
`Stimulus` → `Group<k>` and `Side` → `<Side>Tone`) and `CueTone`, both of which sustain nothing
because replaying a sound would restart it. `build(S)` makes the cue and stimulus lists. Timer
masks for all of them are built once by `buildTrialSM`.

`canonicalise` merges segments that overlap or touch on the same channel: two global timers
driving one BNC line fight, because the first to elapse pulls the line low while the other
still considers itself on.

### Cue
`lum.cueTiming` says what each enabled cue component does once the stimulus starts (D12);
`lum.stim.build` makes a `PortLight('Centre', 'Cue')`, `CueTone` or `Air('Cue')` for each, and
`buildTrialSM` asks them for the wait, the poke and the stop. Before the poke the cue needs
neither sub-millisecond structure nor withdrawal handling, so it is a state's outputs and costs
no timer, through the latency too; only a light or air switched off inside the hold takes one.

### Sync TTL and barcode
`lum.SyncMode` (D4) for trials, driven by states in every mode; `+lum/+sync/` for the session
barcode (D7) and its kinds (`markerWidth`, `barcodeKinds`, `sleepMarkerWidth`; D11, D18), and `fitToCameras`, which widens the barcode and
sync pulses to what the cameras can read (D14); `lum.dev.Flex.alignAnalog` for the analog
timeline. `hardware/TestSyncLine.m` drives the line outside a session, from states and from a
global timer, so the line and the way it is driven can be told apart on a scope.

### Session loop
`LuminoseFM.m` is a thin session script: merge settings, start the LED connecting (D17), ask the
session type (D11; sleep and ePhys calibration hand over to `lum.sleep.run`), seed, set up (dialog), validate, open devices, load sounds, build
components, open the runtime window, plots and analog viewer, send the barcode, then the D3 loop.
All per-trial work — runtime sync, any LED current asked for, trial spec, PulsePal programming, plot
update, saving — happens
inside the prepare window, and its cost is written to `Data.Timing`. Each step before the first trial
is timed (`lum.StartupTimes`, dialogs counted as the operator's time, `lum.dev.open` device by device),
printed as the first trial starts and written to `Data.Session.Startup`. Teardown closes the camera
and LED windows, saves the plots as an image, writes the final file, writes the settings back and
stops the video (D14, D16).

The loop is wrapped in a `try`. Bpod runs a protocol file with no `try` of its own, so an error
thrown from the loop used to leave the trial manager's polling timer running, the runtime window
and plots open, the analog file handle unflushed and the console believing the rig was free —
what the operator sees as a frozen protocol, usually followed by a *DestroyedObject Callback*
error on the next click. Now the trials that completed are saved, the analog stream is merged,
every device is released, `RunProtocol('Stop')` flushes the serial link and frees the console,
and only then is the error reported — as a warning, with `Data.Session.StoppedReason` recording
it. `lum.SessionRunner` turns the one failure this exists for, a USB link that has lost its place
in the byte stream, into `lum:SessionRunner:linkLost` and says what to do about it (restart
MATLAB, power-cycle the state machine and PulsePal).

### Sleep sessions
`+lum/+sleep/`: `run` (the session sequence), `pulseSchedule` and `syncPulseTimes` (sync pulses),
`testPulsePlan`, `stepChoices`, `epochShape`, `describeTestPulses`, `describeTrain` (test pulses),
`nextBlock` and `blockStateMachine` (blocks), `validate`, `validateClock`, `checkTimeline` and
`validateTestPulses`, `deviceSettings`, `Plots` (D11, D13). `run` also runs ePhys calibration
sessions (D18), whose steps come from `+lum/+ephys/` (`plan`, `validate`, `describe`).

### GUI
As decided in D2. `lum.gui.SessionTypeDialog` (behaviour, sleep or ePhys calibration),
`lum.gui.EphysSetupDialog` (D18), `lum.gui.DoricSetup` (every setup dialog's Doric LED tab, with
`lum.gui.IntensityField` and `lum.gui.DoricCalibration`) and `lum.gui.DoricWindow` (the LED window,
D17), `lum.gui.SetupDialog` (tabs;
live validation; the Task tab's task variant, training stage — which applies `lum.stageDefaults`
as it is chosen — and contingency reversal; `PatternBrowser` on the Stimulus tab; `drawTrialFlow`
on the Task tab),
`lum.gui.SleepSetupDialog` (with the test-pulse panel), `lum.gui.StimulusDesigner` (every generator
parameter, groups table, browser), `lum.gui.TestPulseDesigner` (probe, TTL level, trains, schedule
table and presets; previews through `drawTestPulseSchedule` and `drawTestPulseEpoch`),
`lum.gui.RuntimeWindow` (tabbed or compact), `lum.gui.CameraSetup` (both dialogs' Cameras tab, with
live preview) and `lum.gui.CameraWindow` (D14). `lum.gui.savePlotsImage` saves a plot figure beside
the data file at teardown (D16). `lum.gui.HelpLine` puts a description of the field
under the pointer at the foot of both setup dialogs and the tabbed runtime window, from
`GUIMeta.<name>.Help` (declared with each runtime parameter, D2) and every other control's tooltip;
Bpod's compact window gets the help as tooltips. The setup dialog's Play buttons play the session's
sounds through `TestHiFiSound` (`lum.testSounds`). Both setup dialogs build the experiment
record through `lum.gui.ExperimentForm` and lay out forms with `lum.gui.Form`; all draw with
`lum.gui.theme` and a small `lum.gui.logo`.

### Online plots
`+lum/OnlinePlots.m` owns one figure on a 12-column grid: header; top row now and next (left) and
outcomes; middle row performance, psychometric (laid out by `psychometricLayout` from the set: along
the family's evidence, a point per value or eight bins, or a point per group when it has none) and
evidence (each choice at the latent evidence u_A and u_B its stimulus carried, the fraction of the
window A and B were lit, by correctness and side chosen, jittered by a fixed sequence rather than
`rand`, which the trial policy draws sides from, with the contingency's boundary behind it); bottom row by side, side bias (P(chose left) over the bias window,
and the correction target), reaction time and centre hold (time in the port on each trial's last
hold, completed or broken, against latency plus hold). The header's summary gives the water drunk,
side and centre apart, and the running trial's hold. Handles created once; aggregates kept incrementally;
per-trial panels scroll and rescale to what is on screen; one `drawnow limitrate` per trial.
`lum.sleep.Plots` is the sleep session's figure: with test pulses, the schedule with progress, the
lines (sync, A, B), the latest epoch, sync widths and epochs by step; without, lines and widths.

### Data
Per [`data-format.md`](data-format.md). The stimulus set (without preview states), settings, rig map, barcode, session
type and device logs are stored once in `Data.Session`; each trial holds scalars and indices.
Per-trial series live outside `BpodSystem.Data` during the session and are copied in trimmed at
each save. Video is SpinCam's files in `Session Videos`, with `Data.Session.Cameras` and
`Data.CameraTime` (D14). Sleep sessions store `Data.SyncPulses` instead of trial series, and with test pulses
`Data.LightSegments` and `Data.Session.TestPulses` (D13); ePhys calibration sessions the same, with
`Data.Session.Ephys` (D18). Every session stores `Data.Session.DoricLED` (D17).

### Tests
`tests/runLuminoseTests.m` runs the suite from WSL via `matlab.exe -batch`. It refuses to run
against a real state machine, and starts `Bpod('EMU')` for the tests that need one.

---

## Constraints worth knowing before changing anything

These are properties of Bpod v1.9.0 that shaped the code and are easy to rediscover painfully.

- **The emulator is not the rig.** `Bpod('EMU')` emulates a state machine r0.7-1.0:
  **5 global timers, 5 counters, 5 conditions, and no Flex I/O**, against the rig's 16/8/16
  plus Flex. Size everything against `rig.Limits`.
- **The emulator does not implement `LoopMode`, and implements `GlobalTimerCancel` only
  partly** (`RunStateMachine.m`): a cancelled active timer stops without an end event, so the
  console leaves a line it had drawn high drawn high; a timer still waiting out its onset delay
  is not cancelled and starts anyway. A zero-onset timer triggered on entering a state (not the
  first) emits no start event.
- **Conditions can watch a global timer**: `SetCondition(sma, n, 'GlobalTimer<k>', 0)` is true
  while timer *k* is not running, on the rig and in the emulator (D10).
- **`AddFlexIOAnalogData` (v1.9.0) anchors the analog stream at `TrialStartTimestamp(1)`**, though
  the stream starts with the session's first `RunStateMachine` — which may not be a trial (D7).
  Given two options it also reads the *first* as the trial-aligned-copy flag, so
  `('Volts', 0)` switched the copy on. Call it with `'Volts'` alone.
- **`BpodTrialManager` errors in emulator mode.** See D3.
- **`BpodParameterGUI` in v1.9.0 supports `S.GUIPanels` but not `S.GUITabs`.**
- **Output actions do not persist across states.** Bpod writes *every* output channel from the
  entered state's own row (`BpodTrialManager.update_hardwarestate_new_state` mirrors it), so a
  level a state switched on — a port light, the air valve, a TTL line — is dropped by the next
  state unless that state writes it again. Bpod's own example protocols repeat `stimulusOutput`
  in consecutive states for this reason. It is what broke the trial sync pulse (D4), and it is
  why `PreStimulusHold` writes the cue's levels again and `HoldBreak`/`CentreHoldResumed` write
  the stimulus's: `lum.stim.Component.sustainActions` and `sustainOnsetActions` are those
  repetitions, without the timer triggers that must fire once and without the play commands that
  would restart a sound. A sound is the exception: a serial channel with no action in a row is
  sent nothing, so the module plays on.
- **A global timer's channel and a state's output action fight over the same line.** The state
  wins on every state entry. Never rely on a timer to hold a line high across a state change.
- **`AddState` rejects a repeated output channel** ("Only one value for PWM2 is allowed"), so
  lists that switch something off and something on must be merged first: `lum.mergeActions`.
- **A one-character binary string is not a bit mask.** `'1'` as a `GlobalTimerTrig` value
  takes the legacy branch and becomes 2^48. `lum.timerMaskAction` pads to two digits.
- **`SetGlobalTimer` reads optional arguments by position.** Give `Duration`, `OnsetDelay`,
  `Channel`, `OnMessage` in that order. On PWM lines `OnMessage` is the brightness.
- **Timer-end and condition transitions are separate matrices**: `GlobalTimerEndMatrix` and
  `ConditionMatrix`, not `InputMatrix`.
- **`RunProtocol('Stop')` removes the protocol folder from the MATLAB path.** Nothing that
  needs `+lum` may run after it — including destructors. `LuminoseFM` closes the runtime
  window, releases every device and clears every handle before calling it.
- **`RunStateMachine` zeroes `HardwareState.InputState` at the end of every trial.**
- **The HiFi module plays one sound at a time**, and `BpodHiFi.load` reads `LoopMode` and
  `LoopDuration` by position (D12).
- **Do not drive `ManualOverride` programmatically at high rate.** It re-enters the console's
  callback queue and stops the session. Human clicking is fine.

---

## Open questions

- Whether a current changed with `ls_send_current` while a channel runs in external TTL mode changes
  the light at once (D17; `rig-checks.md` P3). If not, `applyPending` must re-apply the settings
  instead, which restarts the channel.
- Bias correction reorders a balanced order (D5), so its long-run effect is bounded by the
  set's own side proportion. If sustained correction is needed, the alternative is to let it
  draw outside the balance and record the imbalance.
- Confirm on the rig that a global timer on a PWM line lights it at `OnMessage` brightness
  (D9), as Bpod's example implies.
- Whether leaving during the latency should re-arm the trial unpunished, as the 0.3 pre-stimulus
  hold did, rather than count as a broken hold (D12). At latency 0 a flick of the nose starts the
  stimulus and, if the animal leaves at once, is a broken hold.
- Confirm on the rig that the HiFi module loops the cue tone without a seam and that the tail
  replaces it cleanly at the poke.
- Confirm on the rig that a sleep session's pulses and sleep barcode reach the acquisition
  devices on Flex2. (A behaviour session's merged airflow does rise with `CentreHold`: 44 of 44
  trials, 4–11 ms after it, in `FakeSubject_LuminoseFM_20260917_082143`.)
- Confirm on the rig, with `TestSyncLine` and a scope on Flex2, that the state-driven train
  arrives at full width and that the global-timer train is the one that did not (D4). If the
  timer train arrives too, the diagnosis stands anyway — the state write one cycle later is what
  truncated the pulse — but it is worth recording which.
- `TestHouseLight` on the rig (2026-09-21): every switch reaches BNC input 1, 18–33 ms after its
  command. Still to confirm by eye that the light switches both ways, mid-trial and mid-block, and
  stays on through a behaviour and a sleep session and between sleep blocks (D15).
- Whether a sleep session's sync pulses (20–100 ms jittered) all reach the cameras as well as the
  barcode did in behaviour (D14).
- Confirm on the rig that the camera window at 5 Hz leaves `Data.Timing.prepare` unchanged, and
  that a multi-hour session records with 0 missed frames and 0 writer drops.
- Whether stepping the hold back should also grow the grace back when *Shrink grace* is in force (D6).
- Confirm on the rig, with a scope downstream of PulsePal, that a sleep session's probes are 10 ms of
  light 50 ms apart, that a theta-burst gate holds exactly four pulses, and that PulsePal changes
  carrier between steps with nothing emitted.
- Whether 5 ms is the right pulse width for the provided 100 Hz trains in OSN-ChR mice. (Paired
  probes alternate between A and B by default since 0.9.2, 30 s apart; see D13.)
