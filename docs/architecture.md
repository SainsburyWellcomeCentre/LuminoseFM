# LuminoseFM — Architecture

Design record for the LuminoseFM protocol. Status: **implemented** (version 0.4); decisions
D1–D12 confirmed. Update this file whenever the architecture changes.

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
  broken hold ends the trial — with restarts, light can follow it, D10), and the next state
  machine is uploaded during the trial. Anything computed from history — bias correction, hold shaping — therefore
  follows trial *n-1* when preparing trial *n+1*.
- In the emulator the same calls run the trial to completion first.
- `lum.dev.open` is the only place that reads `BpodSystem.EmulatorMode`.

### D4 — Sync TTL: trial pulses in one of three modes

**Decision.** Trials drive the sync line (Flex2) in one of three modes, chosen before the
session and recorded per trial (`Data.SyncMode`):

- *Fixed width* — one pulse per trial on the trial's first state, from a global timer.
- *Jittered width* — one pulse per trial whose width is drawn uniformly from
  `S.Sync.MeanWidth ± S.Sync.WidthJitter`; recorded as `Data.SyncPulseWidth`.
- *Task events* — no pulse: the line goes high in `TrialStart` and low on the poke
  (`PreStimulusHold`, or `CentreHold` without a latency) and in `NoInitiation`. No timer.

**Why.** A train of identical pulses only supports alignment by counting edges, which breaks
if a device starts late or drops samples. Pulses of near-unique width are self-identifying:
any device that recorded the line can match its widths against `Data.SyncPulseWidth`. The
mode was called *Random width* until version 0.2; the new name says what the parameters are
(a mean and a jitter). Which session a recording belongs to is the barcode's job (D7).

**Consequences.**

- Requires Flex2 configured as a digital output. Where it is not, `hasSync()` is false and
  trials are built without the pulse — which is what emulator mode always gets.
- A pulsed mode costs one global timer; `lum.timerBudget` is the single place that is
  subtracted.

### D5 — The stimulus is a stimulus set, generated before the session

**Decision.** The patterns a session delivers, and the order its trials come in, are made
together before the first trial by `lum.pattern.generate` — a port of the generatePattern
library — and compiled by `lum.pattern.stimulusSet`:

- A **family** (pure channel, sequence motif, occupancy, overlap order, tiled order,
  hand-drawn pulses) and its parameters produce **K groups** of joint states (dark, A only,
  B only, both) over bins of the stimulus window, or in **continuous** mode a pattern per
  trial with a category (A-led or B-led).
- Groups are **balanced**: each is assigned ⌊N/K⌋ trials, the remainder to random groups,
  and the assignment shuffled — all from a private `RandStream` seeded with
  `S.Stimulus.Generator.Seed`, drawn per session (`lum.pattern.prepareSeed`) unless fixed.
- Each pattern is compiled to segments `[channel onset duration]` (`fromStates`), one per
  stretch of light, and stored in one table with row offsets per pattern (`Segments`,
  `SegmentStart`); `patternAt` recovers one in constant time.
- `S.Task.GroupPLeft` gives each group its chance of paying left; in continuous mode, one
  value for A-led and one for B-led patterns.
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
- Bias correction can front-load the avoided side only as far as the next 50 trials supply
  it; over hundreds of trials it cannot push one side above the set's own share (see open
  questions).
- A pattern with many stretches of light fits the rig's 16 timers and not the emulator's 5;
  both are checked against the connected machine.
- The generator is pure and tested (`generateTest`, `stimulusSetTest`); the designer and
  dialog only edit its parameters.

### D6 — Hold shaping without changing the state graph

**Decision.** Two ways to train the centre hold, chosen before the session
(`S.Task.HoldShaping`: Off, Grow hold, Shrink grace, Both) and tuned during it
(`S.GUI.Hold*`, `S.GUI.Grace*`), implemented by `lum.HoldShaping`:

- **Grow hold** sets the `CentreHold` state timer per trial: from `HoldStart`, grown by
  `HoldGrowth` percent after each trial whose hold was completed, up to `HoldTarget`.
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
- Values follow trial *n-1* when preparing *n+1* (D3). `HoldDuration`, `HoldGrace` and
  `HoldBreaks` (visits to `HoldBreak`) are recorded per trial.
- A shaped hold shorter than the stimulus window cuts the light off at the hold's end; the
  setup dialog notes it when the target is shorter than the window.

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

**Decision.** One vocabulary across code, windows, plots and data (README §5): channels A
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

**Decision.** The stimulus is delivered only while the animal holds. When a hold breaks
beyond its grace, `EarlyWithdrawal` cancels the stimulus and, with `S.Task.OnHoldBreak` set to
*Restart stimulus* (the default), leads back to `WaitForCentrePoke`, where the cue comes back
on: the next poke starts the latency (D12) and `CentreHold` again, and `CentreHold` triggers every
stimulus timer from its beginning. *End trial* keeps the 0.2 behaviour (`EarlyWithdrawal` → `ITI`). Either way the trial
is bounded by the **hold window**, `S.GUI.HoldWindow`: a global timer triggered in `TrialStart`,
never cancelled or re-triggered. `WaitForCentrePoke` has no state timer; it leaves for
`NoInitiation` on that timer's end, or at once on condition 4 (`GlobalTimer<w>` low) when it is
re-entered after the window ran out during a hold. A hold under way when the window ends may
finish.

```
CentreHold --Port2Out--> EarlyWithdrawal --Tup--> WaitForCentrePoke --Port2In--> [PreStimulusHold] --> CentreHold
                                                        | hold window over (timer end, or condition 4)
                                                        v
                                                   NoInitiation --> ITI
```

**Why.** The animal has to receive the whole stimulus before it may choose, and a naive animal
breaks often; ending the trial at each break wastes the cue and the trial. Restarting from the
beginning keeps every delivered stimulus identical. The bound has to span restarts, which a state
timer cannot (it restarts on each entry), so it is a global timer from trial start — the window
the old `InitiationWindow` state timer only approximated, and renamed so the name says so. Adding
transitions rather than states keeps the trial-flow contract.

**Consequences.**

- The hold window costs one global timer on every trial (`lum.timerBudget`, `reserved.HoldWindow`),
  and condition 4 is used. The emulator's five timers leave four for light.
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
Pulses go out in blocks of about 10 s (`lum.sleep.pulsesPerBlock`), each a state machine of
`PulseNNN`/`GapNNN` states (`lum.sleep.blockStateMachine`) run with blocking `RunStateMachine`, on
the rig as in the emulator. The data file records `Session.Type` and, for sleep, `SyncPulses`
(`Onset`, `Width`, `Block`).

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

---

## What is built, and where

### Rig config, device shims, preflight
- `hardware/RigConfig.m` — the channel map (ports 1–5, channels A/B on BNC 1–2, Flex 2,
  module names) and the connected machine's live limits.
- `+lum/+dev/` — PulsePal, HiFi and Flex behind a common base (`lum.dev.Device`), each with a
  real and a null implementation, selected once by `lum.dev.open`. `Flex` also sends the
  barcode and opens Bpod's analog viewer.
- `hardware/CheckRig.m` — preflight report, hardware-only checks skipped in emulator mode.

### Trial engine
`+lum/buildTrialSM.m` assembles one trial. State *names* never change across modalities,
training stages or hold shaping.

```
TrialStart → WaitForCentrePoke (cue) → [PreStimulusHold (latency)] → CentreHold (stimulus) → WaitForCentreExit
           → WaitForResponse → {*RewardDelay → *Reward → Drinking* → DrinkingGrace
                                | IncorrectChoice | NoResponse} → ITI → exit
PreStimulusHold   → EarlyWithdrawal            (left during the latency)
CentreHold        → EarlyWithdrawal (no grace) | HoldBreak ⇄ CentreHoldResumed (grace)
HoldBreak         → EarlyWithdrawal            (grace ran out)
EarlyWithdrawal   → WaitForCentrePoke          (Restart stimulus) | ITI (End trial)
WaitForCentrePoke → NoInitiation               → ITI   (hold window over)
WaitForCentreExit → NoResponse                 → ITI
*RewardDelay      → WithdrewBeforeReward       → ITI
```

The cue is on in `WaitForCentrePoke`; the poke enters `CentreHold` directly, or after the latency
in `PreStimulusHold` (D12). The hold
window is a global timer from `TrialStart` (D10).

**`WaitForCentreExit`: the response window opens on the withdrawal, not on the hold ending.**
Without it the side ports are live while the animal's nose is still in the centre port, and
the beam break it makes on its way out is accepted as its choice — a reward valve opens the
moment the hold ends, whatever the animal intended. So:

- Reaction time is measured from `WaitForResponse` onset: from leaving the centre port to the
  choice poke.
- `WaitForCentreExit` is where the stimulus stops and the response configuration goes up
  (stimulus timers cancelled and lines low, centre marker off, guide lights on).
- The wait is bounded by `S.GUI.ResponseWindow` and falls through to `NoResponse`.

Around it:

- `+lum/nextTrialSpec.m` — pure: the queue, run limit and bias correction by swapping,
  contingency, stage, sync width, hold and grace.
- `+lum/HoldShaping.m` — pure: modes and the next hold and grace (D6), break modes (D10).
- `+lum/triggerStates.m` — pure: where the next trial may be prepared (D3, D10).
- `+lum/scoreTrial.m` — pure: outcome, choice, correctness, reward, reaction time, hold
  breaks and hold attempts from the fixed state names and port events.
- `+lum/punishmentFor.m` — pure: which mistakes are punished and how. Both punishable states
  exist whatever the settings; an unpunished mistake passes through with a zero timer.

### Stimuli
`+lum/+pattern/`: `generate` (families, groups, balanced order, offsets, descriptors) →
`stimulusSet` (segments, contingency, budget and identical-group checks) → `patternAt`.
`fromStates`, `canonicalise`, `check`, `validate` and `describe` work on single patterns;
`families`, `withGeneratorDefaults`, `defaultPLeft`, `newSeed` and `prepareSeed` support the
windows and the session.

`+lum/+stim/` components share the interface `nTimersNeeded` → `configure` →
`addGlobalTimers` → `outputActions` / `stopActions`: `OptoPattern`; `TimedOutput` and its
`PortLight` (roles `Centre` and `Target`, the rewarded side) and `Air`; `Sound` (names
`Stimulus` → `Group<k>` and `Side` → `<Side>Tone`). `build(S)` makes the cue and stimulus
lists. Timer masks for all of them are built once by `buildTrialSM`.

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
`lum.SyncMode` (D4) for trials; `+lum/+sync/` for the session barcode (D7) and its kinds
(`sleepMarkerWidth`, D11); `lum.dev.Flex.alignAnalog` for the analog timeline.

### Session loop
`LuminoseFM.m` is a thin session script: merge settings, ask the session type (D11; sleep hands
over to `lum.sleep.run`), seed, set up (dialog), validate, open devices, load sounds, build
components, open the runtime window, plots and analog viewer, send the barcode, then the D3 loop.
All per-trial work — runtime sync, trial spec, PulsePal programming, plot update, saving — happens
inside the prepare window, and its cost is written to `Data.Timing`.

### Sleep sessions
`+lum/+sleep/`: `run` (the session sequence), `pulseSchedule`, `pulsesPerBlock`,
`blockStateMachine`, `validate`, `Plots` (D11).

### GUI
As decided in D2. `lum.gui.SessionTypeDialog` (behaviour or sleep), `lum.gui.SetupDialog` (tabs;
live validation; `PatternBrowser` on the Stimulus tab; `drawTrialFlow` on the Task tab),
`lum.gui.SleepSetupDialog`, `lum.gui.StimulusDesigner` (every generator parameter, groups table,
browser), `lum.gui.RuntimeWindow` (tabbed or compact). Both setup dialogs build the experiment
record through `lum.gui.ExperimentForm` and lay out forms with `lum.gui.Form`; all draw with
`lum.gui.theme` and a small `lum.gui.logo`.

### Online plots
`+lum/OnlinePlots.m` owns one figure: header; top row now and next (left) and outcomes; middle row
performance, psychometric (laid out by `psychometricLayout` from the set: one point, pair, sweep or
B-share bins) and by side and light; bottom row reaction time. Handles created once; aggregates
kept incrementally; per-trial panels scroll and rescale to what is on screen; one
`drawnow limitrate` per trial. `lum.sleep.Plots` is the sleep session's figure.

### Data
Per README §4.6. The stimulus set (without preview states), settings, rig map, barcode, session
type and device logs are stored once in `Data.Session`; each trial holds scalars and indices.
Per-trial series live outside `BpodSystem.Data` during the session and are copied in trimmed at
each save. Sleep sessions store `Data.SyncPulses` instead of trial series.

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

- Doric LED control (`DoricSystemDLL`): separate package on the MATLAB path, or part of this
  repo. Deferred.
- Whether habituation should also deliver a drop at the centre port on initiation. The centre
  port's valve is wired but the task does not use it.
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
  devices on Flex2, and that a behaviour session's merged airflow now rises with `CentreHold`.
- Whether sleep sessions should drive the house light (port 5).
