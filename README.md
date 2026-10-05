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

| If you want to… | Read |
|-----------------|------|
| know the box, the channel map, the light path, Flex I/O and what the computer needs | [`docs/hardware.md`](docs/hardware.md) |
| read a session file, field by field, including files from older versions | [`docs/data-format.md`](docs/data-format.md) |
| align another recording (Neuropixels, cameras) to the session | [`docs/sync-and-barcode.md`](docs/sync-and-barcode.md) |
| analyse the data in Python, or plan the lab's HDF5 files | [`docs/python-analysis.md`](docs/python-analysis.md) |
| understand the stimulus families: the maths of two-channel patterns, what each family asks, which cues could solve it, how to analyse the choices | [`docs/stimulus_family.md`](docs/stimulus_family.md) |
| look up a word, or what changed between versions | [`docs/naming-and-versions.md`](docs/naming-and-versions.md) |
| run everything with no hardware attached | [`docs/emulator.md`](docs/emulator.md) |
| know what has been checked on the rig, and what still needs someone there | [`docs/rig-checks.md`](docs/rig-checks.md), and the pre-deployment report [`docs/validation-2026-09-24.md`](docs/validation-2026-09-24.md) |
| change the code: design decisions D1–D23 and where each lives | [`docs/architecture.md`](docs/architecture.md), [`docs/repository.md`](docs/repository.md) (layout and tests) |
| look up any function or class at the MATLAB prompt, or write comments and help text | §15 below, and [`docs/code-style.md`](docs/code-style.md) |

Coding agents start from [`CLAUDE.md`](CLAUDE.md) (also `AGENTS.md`).

**Contents:** [1 Before the first animal](#1-before-the-first-animal-of-the-day) ·
[2 Kind of session](#2-choosing-the-kind-of-session) · [3 The task](#3-the-task) ·
[4 The stimulus](#4-the-stimulus) · [5 The windows](#5-the-windows) ·
[6 Watching a session](#6-watching-a-session) · [7 Sleep sessions](#7-sleep-sessions) ·
[8 ePhys calibration](#8-ephys-calibration-sessions) ·
[9 LED intensity and calibration](#9-the-lights-intensity-the-doric-led-and-its-calibration) ·
[10 Video](#10-video) · [11 Aligning other recordings](#11-aligning-other-recordings) ·
[12 Your data](#12-your-data) · [13 Utilities](#13-utilities) ·
[14 Working away from the rig](#14-working-away-from-the-rig) ·
[15 Help at the MATLAB prompt](#15-help-at-the-matlab-prompt)

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
LED (the DoricLED package, its bridge, and which cables are calibrated on which channel), the liquid calibration
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
    starts; hold (the whole stimulus by default) → leave the centre port → poke a side port
    (left or right) → reward, or the cost of a mistake → next trial
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

### The hold

The hold is how long the animal must keep its nose in the centre port before it may
leave and choose. It is not the same thing as the **stimulus window** (Stimulus tab), which is how
long the light pattern lasts. Two settings set it when automatic shaping does not: *Hold without
shaping* and *Fixed hold*. They are runtime settings, so they can be changed between trials. They
are in three places, which always show the same values: the Task tab's *Centre hold* panel (whose
*Hold* line says how long the hold is), the Runtime tab's *Trial* column, *Timing* panel, and the
runtime window's *Trial* tab, *Timing* panel. The Timing panel also shows the **stimulus window**
(the Stimulus tab's *Duration*, editable in all three places before the session; the runtime window
names it in the panel's title, since it cannot change once the session has started):

- *Hold without shaping* **Whole stimulus** (the default): the stimulus window plus the
  post-stimulus hold (0 s by default). The hold and the light end together, or the hold after it.
- *Hold without shaping* **Fixed**: *Fixed hold* seconds from stimulus onset. The post-stimulus
  hold is not used. Shorter than the window, the animal may leave before the light is over;
  longer, it holds in the dark after the light for the difference.
- **Automatic shaping** with *Grow hold* or *Both* replaces either choice: the hold grows from
  `HoldStart` to `HoldTarget` (below), and the two controls are greyed out in the setup dialog (the
  runtime window leaves them editable, and ignores them while the hold grows). *Shrink grace* alone
  keeps the hold chosen here and only forgives breaks in it.

With a latency, the animal holds the latency first and the hold counts from stimulus onset, so
from the poke it holds latency + hold. An Experiment session cannot use automatic shaping, so a
fixed hold is how an experiment asks for a hold shorter than the stimulus. A change in the runtime
window applies from the next trial prepared (§5, *Runtime window*). Each trial's hold is recorded in `Data.HoldDuration`,
and the settings it came from in `Data.TrialSettings{k}.HoldLength` and `.FixedHold`.

For a 1 s stimulus window:

| *Hold without shaping* | The animal must hold | The light | It may choose |
|---|---|---|---|
| Whole stimulus, post-stimulus hold 0 s | 1 s | 0–1 s, inside the hold | after 1 s |
| Whole stimulus, post-stimulus hold 0.5 s | 1.5 s | 0–1 s, then 0.5 s of dark hold | after 1.5 s |
| Fixed, 0.3 s | 0.3 s | 0–1 s, playing on after it leaves | after 0.3 s |
| Fixed, 1.5 s | 1.5 s | 0–1 s, then 0.5 s of dark hold | after 1.5 s |

**The light plays to its end.** A completed hold never stops the light pattern: after a hold shorter
than the light the animal leaves and chooses while the light plays on, to the end the pattern gives
it, even through the reward or a punishment. Everything else in the stimulus (air, centre light,
tone) and the cue stops when the hold ends. So every trial delivers its whole pattern whatever the
hold, and a growing hold only decides how long the animal must sample before it may leave. With a
hold shorter than the window the animal can answer before it has seen the whole pattern; for a
family whose deciding part comes late (an order, a sequence) it may answer on part of the evidence.
Since the hold can be set shorter than the light at any time, every session with light keeps one
global timer ready to know when the light is over (the light clock): a light pattern can have 14
separate stretches of light on the rig (3 in the emulator), one fewer than a session without it
had before 0.9.8. A trial whose hold covers its light does not use it.

### A broken hold

**A broken hold stops the stimulus.** If the animal leaves the centre port before the hold is
over (beyond any forgiven break), the stimulus, light included, stops at once. What happens
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

### Choices, rewards and punishments

**A correct choice** is rewarded at that port (runtime window, *Reward*):

1. The reward starts only when the animal **pokes the paying port**: its beam break in the response
   window leads to the reward delay; no poke, no water (in habituation either side port's poke
   does). The poke starts the **reward delay** (`RewardDelay`, 0 s by default). Leaving the port
   during it forfeits the water: the trial is *CorrectNoReward*. At 0 s there is no delay to leave
   in: the valve opens on the next state machine cycle (0.1 ms) after the poke, and a beam flicker
   in that cycle no longer cancels it (before 0.9.6 a 0.1 ms flicker as the snout went in could).
   LUMS0014's first session: all 47 rewards opened 0.1 ms after a poke at that port.
2. The valve opens for the time Bpod's liquid calibration gives `RewardAmount` µL (3 by default).
3. **Drinking**: the trial waits, with no time limit, for the animal to leave the port.
4. **Drinking grace** (`DrinkingGrace`, **0.3 s** by default): once it is out, it must stay out of
   both side ports for this long. A poke at either side port within it sends the trial back to
   waiting for the animal to leave, and the grace starts again when it does; no more water is given.
   Centre pokes are ignored. A full grace ends the trial.

The grace keeps the next trial, and its cue, from starting while the animal is still at the water.
Lengthen it for an animal that keeps coming back to the port; 0 ends the trial the moment the
animal leaves. `Data.Rewarded` is 1 for a rewarded trial; the drinking is in the trial's states
(`DrinkingLeft`/`DrinkingRight`, `DrinkingGrace`).

**An incorrect choice** is handled as the runtime window's *Punishment* settings say:

| Punish on includes *Incorrect choice*? | Punishment | What happens |
|---|---|---|
| no (the default: *Punish on* is *None*) | — | no punishment: the animal may still go to the correct port within the response window, which starts again, and be rewarded there. It may try again after each wrong poke |
| yes | *Timeout* | no reward; `PunishTimeout` seconds, then the inter-trial interval and the next trial |
| yes | *White noise* | no reward; the noise burst plays to its end, then the inter-trial interval and the next trial |
| yes | *Timeout + noise* | no reward; the noise and the timeout together (the timeout lasts at least as long as the noise), then the inter-trial interval and the next trial |

Either way the trial is scored by the **first** side poked: a wrong choice followed by the correct
one is *Incorrect*, with `Data.Rewarded` 1 and `Data.ResponseRetries` counting the wrong pokes
forgiven.

### The end of a trial

Every trial that ends — after the drinking grace, a punishment, no response, no poke, or an early
withdrawal that ends the trial — goes through `WaitForLightEnd` and then the inter-trial interval
(`ITI`, **0.25 s** by default), and the next trial starts as the ITI ends (to 0.1 ms): MATLAB
prepared it and sent it to the state machine while this trial ran, so the time between trials is
the same on every trial. An LED current you set in the LED window waits for the ITI instead,
because it would change light already playing: it is sent in the ITI, then the next trial; 0.25 s
is the shortest ITI that always has room for both, so that trial starts on time too (the stimulus
window is fixed once the session starts).

You may set a shorter ITI, 0 s included (runtime window, *Trial* tab, *Timing*): it is kept, but a
warning pops up saying what it costs. With it, a trial after an LED current change starts late by what the ITI did not cover (tens of ms), with nothing running in between, and Bpod's
trial manager prints one *WARNING: TrialManager reported an inter-trial dead time of >500
microseconds* box in the command window after a line saying which trial waits. That box at any
other time means a trial started late: note it and tell whoever maintains the protocol. Without
light nothing waits, and any ITI is kept exactly. (Up to 0.9.10 the ITI was 0 s and the box came
after every trial of a session with light: each trial started 0.01–0.35 s after the last, with
nothing recorded in between. A settings file still at that 0 s takes 0.25 s when it is next
loaded.) `WaitForLightEnd`
waits for a light that is still playing after a short hold, and otherwise lasts no time: a broken
hold has already stopped the light. For example, with a fixed 0.3 s hold and a 1 s light, times from
the poke:

| The animal | Trial |
|---|---|
| holds, leaves at 0.35 s, pokes the correct port at 0.6 s, leaves it at 0.8 s | the grace runs to 1.1 s; the light ended at 1.0 s, so the ITI starts at 1.1 s |
| holds, leaves at 0.35 s, pokes the correct port at 0.5 s, leaves it at 0.55 s | the grace ends at 0.85 s; the trial waits for the light, and the ITI starts at 1.0 s |
| comes back to the port at 0.9 s, during the grace, and leaves at 1.2 s | the grace starts again at 1.2 s and ends at 1.5 s; the ITI starts at 1.5 s |

**Outcomes** (`Data.Outcome`, names in `Data.OutcomeNames`): *NoInitiation* — the hold window ran
out and the stimulus never started; *HoldNotCompleted* — the stimulus started at least once but
every hold broke before the window ran out; *EarlyWithdrawal* — a break ended the trial (*End
trial* only); *NoResponse*, *Correct*, *Incorrect*, *CorrectNoReward*. `Data.HoldAttempts` counts
how many times the stimulus started on each trial.

### Which task

The Task tab's first field says which variant of the task this session runs: *Familiar/Novel*,
*Mixture*, *Sequence* or *Motifs*. It names the kind of stimulus set the session is built around
and is stored with the data (`Session.Settings.Task.Variant`), so a data set can be selected by it.
Choosing one changes no other setting: the light patterns come from the stimulus family on the
Stimulus tab (§4), which has families of the same names to match (Mixture, Sequence, Motifs).

### Training stages

Stage 1 (*Habituation*) rewards **both** side ports, whichever way the animal goes, so it learns
that the side ports pay before it has to learn which one. By default the rewarded ports are also
lit during the response window in habituation (the *guide light*, set per side). Stages 2
(*Training*) and 3 (*Experiment*) reward only the correct side. With both sides paying there is no
wrong side, so in habituation the plots score every trial by whether it was rewarded, a trial
without a choice as not rewarded (§6); the data file still records `Correct` as the side the
stimulus group pays.

**Centre reward (habituation only).** To teach a new animal that the centre port is worth
visiting, the first trials of a habituation session also give water at the **centre port** as the
hold is completed: `CentreRewardAmount` µL (1.2 by default, valve 2's smallest measured volume; 1 µL is extrapolated and still allowed) on trials 1 to `CentreRewardTrials` (10 by
default). Both are runtime parameters (*Trial* tab, *Centre reward* panel, and the setup dialog's
Runtime tab): raise the trial count during the session to go on, set it (or the amount) to 0 to
stop. Trials whose hold was never completed count towards it too. The valve time comes from
**valve 2's** liquid calibration; without one the session runs without the centre reward and warns
once. The running trial's line in the runtime window says when it has a centre reward, and the
plots count centre water apart from side water. It is ignored in Training and Experiment.

Choosing a stage also sets the session up the way that stage is normally run, the moment it is
chosen:

| Stage | Light pattern | Stimulus air | Centre light cue | Automatic shaping | Strategy correction |
|-------|---------------|--------------|------------------|-------------------|---------------------|
| Habituation | **off** | **on**, for the whole stimulus window | **on** | **on** | **off** |
| Training | on | off | as it was (on by default) | **on** | as it was |
| Experiment | on | off | as it was (on by default) | **off** | **off**, with bias correction and *Max same side in a row* at 0 |

A habituation trial with the defaults:
1. The centre light comes on at trial start and stays on through the hold.
2. The animal pokes and holds; the air runs during the hold, which starts at 0.2 s and grows as
   holds are completed, up to 0.6 s.
3. A completed hold on trials 1–10 gives 1.2 µL at the centre port.
4. The centre light goes off, and both side port lights come on (guide lights, *Habituation only*).
5. Once the animal has left the centre port, a poke at either side pays 3 µL.
6. After the drinking grace and the ITI, the next trial starts.

The centre light cue is left alone when the centre light is a stimulus component.

Habituation therefore delivers **air alone**: the hold is exactly as long and as salient as it
will be later, and carries nothing to discriminate. Habituation and Training shape the centre hold
from the animal's performance — in habituation from a hold short enough to earn the centre reward
on the first visits; an experiment asks every animal for the same trial. These are defaults, not
a lock — untick or tick anything afterwards and the session runs as you leave it — with one
exception: **an Experiment session cannot start with automatic shaping on.** Strategy correction
(below) may be switched on in an experiment; the log then says which parts ran.

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
hold* panel): off by default, switched on by choosing *Habituation* or *Training* and off by
choosing *Experiment*; it may be used in either of the first two.
While it is on, the *shaping method* says how:

- *Grow hold* (the default) — the hold starts short (`HoldStart`, **0.2 s**) and grows by
  `HoldGrowth` percent (**1%**) after every trial on which the animal completed it, up to
  `HoldTarget` (**0.6 s**). The target can be as long as the stimulus window plus the
  post-stimulus hold, or longer; the defaults stop short of the 1 s window. After a shorter hold the
  light still plays to its end, so every trial delivers its whole pattern and the hold only
  decides how long the animal must stay before it may leave. When the animal **withdraws early `HoldStepBackAfter` times (10) at one hold
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

**The next session carries on.** When a session that grew the hold ends, `HoldStart` in the
settings file becomes **10% less than the hold its last trial asked for** (to the ms, no longer than
`HoldTarget`), so the animal's next session starts a little below where it stopped instead of at
the beginning; the session log says so (`the next session's hold starts at 0.78 s …`). It is an
ordinary value on the setup dialog's Runtime tab (*Shaping*): type another start to override it.
Headless sessions, and sessions whose hold does not grow, leave it as it was. The other shaping
values (growth, target, step back, grace) are kept in the settings file as the session last ran
them, runtime changes included, so each session starts with what the one before it ended with;
change any of them on the same tab before *Start*. The defaults above apply to a new settings
file only: a subject's file keeps its own values. A start longer than the target is not used: the
hold starts at the target, and the setup dialog says so.

Each trial is prepared while the one before it runs, so shaping follows the animal one trial late:
trial *n*+1's hold is trial *n*'s, grown if trial *n*−1 completed its hold. With every hold
completed and the defaults, the holds run 0.2, 0.2, 0.202, 0.204 … s, reaching 0.6 s after about
110 completed holds.

With automatic shaping off, every trial asks for the same hold: the whole stimulus (the default)
or the fixed hold. The
shaping parameters are tuned during the session from the runtime window. The hold each trial
required, its grace, the number of forgiven breaks and the number of early withdrawals are
recorded per trial. Later, automatic shaping will also choose easier or harder trial types.

### Strategy correction: levers against habits

A mouse can earn half its rewards with a habit that ignores the light: alternating between the side
ports, staying on one, repeating what was rewarded. In a random order every such habit earns 50%,
so nothing pushes it off. LUMS0014 alternated on every visit, its choice opposite the side port it
had poked last on 96–98% of choices (2026-09-28 to 10-05), with a free side poke between most
trials. **Strategy correction** (0.10.0) is three levers against habits, and a measure of them.
Every lever is a runtime setting on the runtime window's **Strategy** tab (and the setup dialog's
Runtime tab), **off by default**, switched off by choosing *Habituation* or *Experiment*, and can
be changed during the session (from the next trial prepared). Change one thing at a time, as for
the light, so a change in behaviour can be put down to it.

**The habits, every session.** The session log's *Habits* line and the summary plot `14_Habits`
say how often the animal chose the port opposite the last side port it poked, went to the other
side after a centre poke, alternated its choices (against what its side bias alone would give),
repeated its last choice after a reward and after an error, and poked a side port before the
response window (before the first centre poke, or between hold attempts). Judge every lever from
this line, not from % correct.

**1. Side pokes before the response** (*Side pokes* panel). A side poke while the trial waits for
a centre poke (from trial start, and after an early withdrawal) cost nothing before 0.10.0, and set
the habit's next side. `Side poke before the response`:

| Setting | What a side poke does | Cost to the animal |
|---|---|---|
| *Ignore* (default) | nothing | none |
| *Delay* | the cue goes off and centre pokes are ignored for `Side poke delay` (1 s), then the trial waits for a centre poke again; the hold window keeps running | time |
| *End trial* | the trial ends unrewarded (outcome *side poke before the response*), with the early withdrawal's punishment if early withdrawals are punished | the trial |

A trial ended by a side poke within half a second of its start can make the next one start a few
ms late (one *dead time* warning in the console); a punishment timeout for early withdrawals
avoids it. Start with *Delay*. Nothing in it makes the habit pay less, so % correct should stay near 50%; it
has done its job when side pokes before the response fall from about 0.6 a trial to under 0.1 (the
*Habits* line), after which the habit shows in the choices themselves. *End trial* is the harder
version. If the animal is rewarded on fewer than 40% of trials, or runs far fewer, shorten the delay
or go back.

**2. Context correction** (*Bias* panel). Bias correction normally reads the animal's lean over all
its recent choices. `Correct for` reads it in the trial's **context** instead:

| `Correct for` | Reads the lean | Counters |
|---|---|---|
| *Side bias* (default) | over the last `Bias window` choices, as before 0.10.0 | a side bias |
| *Last choice* | after a left choice, and after a right one, apart | alternating, staying on one side, side bias |
| *Last choice and reward* | after a rewarded and an unrewarded left or right choice | also win-stay and lose-shift |

In each context the next trial pays left with chance 0.5 + strength × (0.5 − *f*), *f* the share of
left choices there, as plain bias correction does. A habit is then right less often than chance (an
animal that alternates strictly, at strength 0.5: about 25%), while an animal that follows the
light is still rewarded on every correct choice: which side each light pays never changes, only the
order. `Reward floor (%)` keeps the habit's reward from falling too far: with the animal's share of
rewarded choices (over the last `Reward floor window`, 50 choices) at the floor or below, no
correction; at 50% or more, full strength; in between, in proportion. A strong habit then settles a
little above the floor (LUMS0014's at 40%: about 43%); a lower floor pushes harder. 0 is no floor.
Context correction needs incorrect choices **punished** (*Punish on* *Incorrect choice* or *Both*):
while they are retried, `Correct for` is greyed out and side bias is used, because the first choice
of a retried trial cannot be read in time. It also prepares each trial once the trial before has
chosen: with less than 0.75 s of timeout and ITI after an incorrect choice, a slow preparation can
start the next trial late (the setup dialog's note, and a console warning when changed during the
session). While it reads choices, a punished incorrect choice lasts at least 50 ms, even with a 0 s
timeout, so the session can see it.

**3. Blocks** (*Blocks* panel). `Trial order` *Blocks* holds the paying side for a block of trials,
`Block length, shortest`–`longest` (15–25, drawn at random per block, so a switch cannot be counted
to), then changes it; with `Switch after correct in a row` N above 0, a block ends once it has run
its shortest and the last N choices in it were correct. Bias correction and *Max same side in a
row* do not act in blocks. Staying with the side that just paid then earns about 95%, alternating
or one side still 50%, following the light 100%. A block's **first trial** is the test of the light:
correct on about 0% for an animal that stays, 50% for one that alternates, above 50% for one that
uses the light; with 15–25, about 30 switches in a 600-trial session decide it (20 or more correct of
30). The log's *Blocks* line and the summary plot `15_BlockSwitches` give it. Inside a block the
side is set by the block, so the psychometric and evidence panels and the log's *By group* count
only trials outside blocks and each block's first trial, and the performance panels shade the
blocks.

**The order for LUMS0014** (the operator's, 2026-10-05): side pokes *Delay* 1 s for two sessions;
then context correction, *Last choice and reward*, strength 0.5, floor 40%, side pokes kept; blocks
of 15–25 last, if nothing else works. When the first trial after a switch is at 20 or more of about
30 correct for two sessions, shorten the blocks (10–15, then 5–10), then go back to a random order
with context correction. A random order with no lever is what an experiment runs, so record which
sessions used which (the log's *Strategy correction* line says).

**Every trial records what applied** (`BiasContext`, `Block`, `BlockSide`, `SidePokeDelays`, outcome
7): see [`docs/data-format.md`](docs/data-format.md), *Sessions with strategy correction*, for which
measures compare across such sessions.

---

## 4. The stimulus

**What a trial delivers.** Each trial lights the two optical channels, A and B, in a *light
pattern* over the stimulus window (1 s from stimulus onset, by default): when A is on, when B is on.
A session has a handful of **groups** — its stimulus conditions — and every trial delivers the
pattern of one of them. The groups come equally often, in a shuffled order that is fixed before the
first trial, so the Stimulus tab lets you scroll through every trial of the session exactly as it
will run.

**The family is the question.** The **stimulus family**, chosen on the Stimulus tab (*Family*),
decides what the groups are, and so what the animal has to tell apart to find the paying side.
Choosing a family loads its defaults, and they run as they are: there is nothing to fix first and no
warning to clear. **Design stimuli…** opens the stimulus designer, which shows every setting of the
family, with a preview of every trial.

| Family | The animal tells | Defaults | Also |
|--------|------------------|----------|------|
| **Pure channel: A or B** | which channel is lit | A for the whole window pays left, B pays right | several lit fractions, so that duration varies too; one channel only |
| **Mixture: more A or more B** | how much of the mixture is A | both channels lit, as mixture ratios 2:1 (pays left) and 1:2 (pays right), each at three totals of light (0.3, 0.6 and 1.2 of the window), so that neither channel's amount alone tells the side. Each amount is spread over the window in cycles (5 on the rig), both channels starting every cycle, so the mixture lasts the whole window instead of ending early and leaving the rest dark | A's share judged against another boundary (is A more than 60% of the mixture?), a psychometric set of ratios (80:20 60:40 40:60 20:80), or *A minus B* instead of the share. *Placement* from onset or centred, in one stretch per channel. *A alone decides* or *B alone decides*, the control: one channel's amount decides and the other is a distractor. New amounts every trial |
| **Sequence: more A or more B flashes** | which channel flashes more often | the window cut into five slots (three in the emulator, which has fewer timers), each holding one flash of A or of B; every split from 5 A to 5 B, in a new order every trial | leave slots empty (*both channels needed*), so that counting one channel is not enough |
| **Order: A first or B first** | which channel comes first | A alone, then both, then B pays left; B alone, then both, then A pays right | the *guarded cycle*, where only the timing of one channel against the other tells |
| **Motifs: words of A and B** | which word it is | the eight three-letter words of A and B, four paying each side, split so that no simple rule tells them apart: each word has to be learnt | your own words; X lights both channels, - leaves a letter dark |
| **Hand-drawn pulses** | whatever you draw | two groups: A, or B, in the first half of the window | any pulses, typed into a table |

[`docs/stimulus_family.md`](docs/stimulus_family.md) defines every family, explains why its defaults
are what they are, and shows how to analyse the choices each one produces.

**Which side pays.** Each group has a `P(left)`, the chance the left port pays on its trials: 1 and 0
give a fixed contingency, values in between a psychometric one. The family sets it (more A, first A
or an A-heavy word pays left), and the group table shows it. Type your own values in the table to
change it; they are kept while the groups stay the same, and the family's come back as soon as the
groups change (another family, other ratios, levels or counts). *Reverse* on the Task tab swaps every
side (see *Reversing the contingency* in §3).

**Could one channel alone solve it?** Under the group table, a line says how well an animal could
do by reading only one simple cue: how long A is on, how long B is on, how much light there is in
all, or when A (or B) is on. For example, *One cue alone could score at most: A's amount 67%, B's
amount 67%, total light 50%…*. 100% means that cue alone solves the task; 50% means it tells nothing.
So you can see before the session whether a task really needs both channels (the mixture's defaults
do; a sequence with every slot filled does not). The data file keeps the numbers
(`StimulusSet.Shortcuts`), to compare with how well the animal does.

**Relative amounts.** The mixture family judges how much of the light is A in one of two ways: A's
**share** of the mixture, `u_A / (u_A + u_B)` (its relative abundance, typed as ratios A:B), or the
**difference** `u_A - u_B`. Either pays left above a boundary you set (1:1, or 0, by default), and the
total light changes from group to group, so the animal has to weigh A against B. The two differ once
the boundary moves (*more than 60% A* is a ratio, not a difference) and in what makes a trial hard:
equal ratios are equally hard at any total, equal differences are not.

### Trial order, seeds and limits

- **A new random session every time.** A number, the **seed**, fixes every trial of a session:
  their order, and whatever the family draws at random (the order of the flashes, the amounts, the
  phase). Each session draws a new seed, so by default no two sessions of an animal deliver the
  same trials, and nothing depends on earlier data being on this computer. **Randomise trials** on
  the Stimulus tab draws a new seed whenever you like before the start: every trial is drawn again,
  and what you scroll through is exactly what the session runs.
- **Repeating a session.** The seed is saved with the data (`SessionData.Session.StimulusSet.Seed`),
  printed in the command window as the session starts, and shown in the plots' header (so it is in
  the `_plots.png` beside the data file too). To give an animal the same trials again, type that
  seed in **Seed** on the Stimulus tab, from the data file or from wherever you noted it if the data
  have gone to the cloud. Untick *a new seed for every session* to keep the seed for the sessions
  after this one as well.
- **Bias correction and the run limit** reorder the trials, never change which are delivered: to offer the side
  the animal avoids, or to break a run of `MaxSameSide` trials on one side, the next trial is
  swapped with a later one in the session's order that pays the needed side, drawn at random from
  those that can (from 0.10.0; before, the next such one, so the trials it displaced came back as
  a run of one side once the correction eased). Blocks (§3, *Strategy correction*) use the same
  swap. Every group
  is still delivered as often as it was balanced. Bias correction takes precedence over the run
  limit. A run on the side it is pushing towards may go past `MaxSameSide`; a run on the other
  side is still broken at the limit. So correction holds its target for as long as the order has
  trials paying that side. Against an animal that always goes left, and a 1000-trial order, that
  was about 600 trials at strength 0.5; after that, the rest of the order pays the other side.
  The order is `MaxTrials` long (*Maximum trials*, Experiment tab), **3000 by default** from 0.9.11,
  so correction has trials to draw on for about 1800 trials against such an animal, far more than
  a session runs; raising it costs nothing measurable per trial. Groups are balanced over the whole
  order, not over the part a session runs: a biased animal gets more of the side it avoids (on
  2026-09-28, 217 B-only trials and 116 A-only in 333).
- **What a session refuses.** Every stretch of light on a channel costs one Bpod global timer.
  The rig has 16 and the emulator 5; the hold window always takes one and the light clock one
  (§3, *The light plays to its end*), leaving 14 for light on the rig and 3 in the emulator, and
  grace shaping or timed components take one more each. The families' defaults fit both; settings
  that need more are refused, naming the group. Two groups that deliver identical light but pay different sides are refused
  too: that is a task the animal cannot solve.
- **Offsets.** Any family can delay channel A or B (one value, or one per group), wrapping the
  light round the window or letting it fall off the end.

### Other stimulus components

Besides the light pattern, the stimulus can include air, a centre light flash and a tone (a
different frequency for each group), each timed from stimulus onset. The **Left** and **Right** tabs
set outputs delivered on trials rewarded on that side — the side port's light and a side tone, each
timed from stimulus onset — and the guide light.

A component on for the whole window is free, and stays on until the hold ends — through any
post-stimulus hold too; one that starts late or ends early uses a global timer. Sounds never do: a
delayed tone is loaded with silence in front of it. The same holds for the cue once the stimulus
starts: a cue light or air that goes off part way through the stimulus uses a timer, the cue tone
does not. Unlike the light, these components stop when the hold ends. The HiFi module plays **one sound at a time** — a new sound cuts off the
one playing — so a session is refused if more than one of the stimulus tone, the side tone and a
cue tone that continues into the stimulus would start with the stimulus.

---

## 5. The windows

As the first trial (or sleep block) starts, the command window prints how long the start took, and
where the time went:

```
LuminoseFM: ready 212.4 s after launch; 31.0 s of it the protocol's own, 181.4 s in the dialogs:
  devices 18.2 s (Cameras 14.1, PulsePal 2.3, ...), windows 5.1 s, barcode 4.2 s, ...
```

The same is stored in the data file (`Data.Session.Startup`).

When the session ends — at its last trial, on an error, or with the console's **End** button — the
protocol closes the camera and LED windows first, then saves; Bpod closes the other windows.

After the **End** button the box can run one more trial that nothing records and nothing stops:
its cue light comes on, and a poke starts the stimulus air (and the light, until the protocol has
switched the LED off) and can earn water that is counted nowhere. Without a poke it ends by itself
after the hold window (60 s); if the animal does the trial it ends after the choice. Take the animal
out once the cue is off (the centre port's light, with the default cue). Analysis leaves out everything after the last recorded trial
([`docs/data-format.md`](docs/data-format.md#video), *Unrecorded trials at the end*).

### Session setup

Shown once, before the first trial. Everything on it is validated on every edit; the status line
says what is wrong, and **Start session** stays disabled until nothing is.

| Tab | What it holds |
|-----|---------------|
| Experiment | Subject (the one launched in the launch manager); whether the **house light** is on as the session starts; genotype (OSN-ChR or wild type offered, any other typed into the box); *Neuropixels recording* (probe, implant, target, coordinates, serial), *EEG/EMG recording* (channel counts), *Drug administration* (name, delivery route, dose and unit, vehicle, time given); session length, devices, runtime window, notes |
| Task | Which task (Familiar/Novel, Mixture, Sequence, Motifs); training stage and what it does to rewards — choosing one sets the session up the way that stage is normally run; trial order, including the contingency reversal; centre hold — how long it is, what a broken hold does, and hold shaping; which components make up the cue, the stimulus and each side; a timeline of one trial, with the hold window |
| Cue | For each cue component (centre light, tone, air): whether it continues through the stimulus, and if not, how long it stays on into it; the cue tone's frequency and sound output, each sound with a **▶ Play** button; a timeline of the cue against the latency and the stimulus, one row per component |
| Stimulus | The stimulus window and its latency from the poke; the stimulus **family** (choosing one loads its defaults) and a summary of the stimulus set, with how well one cue alone could do; the **Seed**, **Randomise trials** and **Design stimuli…**, and whether each session draws a new seed; P(left) per group, the family's until you type your own; timing of air, centre light and tone, with **▶ Play tones**; every trial of the session to scroll through |
| Light path | The carrier for each channel: frequency, pulse width, and PulsePal's TTL level into the LED driver (5 V) |
| Doric LED | The LED driver (controlled from MATLAB, or set by hand), the fiber bundle and which cables are on A and B, each channel's intensity and limit, and **Calibrate LED power…** (§9) |
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

The parameters that are safe to change with an animal in the box, read once per trial as the next
trial is prepared, which happens as each trial starts: a change reaches the next trial if made in
its first moments, and otherwise the one after (the header's *next* line says what is prepared). On the
rig it is a window of its own, in tabs (*Trial*: reward, centre reward and timing, including the
hold without shaping; *Task*: punishment, hold shaping; *Delivery*: light, sound and port light
brightness; *Strategy*: bias correction, blocks and side pokes, §3), with labels and units, limits held as values are typed, and a header
saying how the last trial ended and what is running now, over as many lines as it needs. In
habituation, where both side ports pay, the header says whether the trial was **rewarded**, never
correct or incorrect; with a contingency (training, experiment) it says correct or incorrect.
Under the emulator the reduced form opens instead — Bpod's own single-page parameter window,
relabelled. `Runtime window` on the Experiment tab can force either.

- *Timing*: *Hold without shaping* and *Fixed hold* (§3, *The hold*); the panel's title gives the
  stimulus window they are set against. Then `PostStimulusHold`, `HoldWindow`, `ResponseWindow`
  and `ITI`.

- *Reward*: `RewardDelay` (0 s) and `DrinkingGrace` (0.3 s), as §3 describes under *A correct
  choice*. `RewardAmount` µL at the side port (3 by default), the valve time from Bpod's liquid
  calibration of valves 1 and 3. 0 opens no valve. A volume the calibration cannot give — beyond the
  point where its fitted curve stops rising (about 15 µL with the rig's calibration of 2026-09-24) —
  is refused: at the start the session does not begin; during it the reward stays as it was and the
  window is put back. A volume outside the measured ones (1.2–13.5 µL on the rig) is extrapolated,
  and the console says so. The same goes for the centre reward on valve 2, which is dropped instead.
- *Punishment* is two choices: which mistakes are punished (none / early withdrawal / incorrect
  choice / both; *None* by default) and how (timeout / white noise / both). An incorrect choice
  that is not punished lets the animal go on to the correct port (see *An incorrect choice* in §3).
  A noise always plays to its end before the next trial or the next poke.
- *Centre reward*: `CentreRewardAmount` µL at the centre port for a completed hold. In habituation
  it is given on trials 1 to `CentreRewardTrials`. In any stage, tick **Centre reward again** to give
  it on the next `Again for trials` trials (10 by default), for an animal that has stopped coming to
  the centre port: the box unticks itself when they are done, and unticking it stops sooner.
  `Data.CentreReward` records every centre reward given.
- *Bias correction* pushes trials towards the side the animal has been avoiding. If it chose left
  on a fraction *f* of its last `BiasWindow` choices, the next trial pays left with chance
  0.5 + strength × (0.5 − *f*), kept within 0.1–0.9, by bringing forward a trial that pays that side:
  0 is off, 1 full compensation. `BiasWindow` counts the animal's choices; trials with no side
  poke are skipped. Every group is still delivered as often; only the order changes. It takes
  precedence over `MaxSameSide` (see *Bias correction and the run limit* in §4). Why this form:
  the animal's lean, *d* = *f* − 0.5, is mirrored and scaled by the strength *s*, so an animal
  with no lean is left alone. An animal that goes left with chance *f* whatever the stimulus is
  then right with chance 0.5 − 2·*s*·*d*²: below chance by more the stronger its bias, while an
  animal that follows the stimulus loses nothing (always-left at strength 0.5: 25%). In simulation,
  an always-left animal got 74–84% right-paying trials at strength 0.5 (target 75%) and 86–92% at
  strength 1 (target 90%), for 500–600 trials of a 1000-trial order. With an unbiased animal,
  chance leanings in the window let runs reach 4–5 in 1000 trials. The trial still running counts
  towards the run (0.9.8): before, a run could reach `MaxSameSide` + 1 even without bias correction
  (LUMS0014 had 26 runs of 4 with a limit of 3 on 2026-09-27).

Every parameter describes itself on the help line at the foot of the window (a tooltip in the
compact window).

Bpod's notebook plugin is also initialised, for manual annotation during the session.

### LED window

Opens beside the plots in every session with light (untick *LED window in the session* on the Doric
LED tab to leave it closed). It shows each channel's LED current, and its irradiance when the channel
is calibrated. In behaviour and sleep sessions, type a new intensity (mW/mm² on a calibrated channel, mA
otherwise) and press **Apply**: it is sent
between trials (or sleep blocks), never while light is gated, the channel reads *waiting to be sent
between trials* until then, and each trial records the current it ran at. The trial already
prepared when you press it keeps the old current; the current is sent in its ITI, and the one after
starts on time (at an ITI below 0.25 s, a few tens of ms late with one dead time warning in the
command window: §3, *The end of a trial*). The intensity you leave it at is kept for the next
session. In an ePhys calibration session the schedule sets the current, and the
window only shows it.

### Designers

The **test-pulse designer** is described with sleep sessions (§7). The **stimulus designer**
(*Design stimuli…* on the Stimulus tab) holds everything about the light
patterns: the window and the bin, the seed (with **Randomise**, and whether each session draws a new
one), the family with the question it asks, the family's own
settings (with **Restore defaults**), channel offsets, the groups with their trials, timers and
P(left) (**Family's P(left)** forgets values you typed), the line on what one cue alone could score,
and every trial to scroll through. Each setting explains itself in its tooltip.

Both designers also open on their own, away from the rig, and return the settings they built:

```matlab
S = lum.gui.StimulusDesigner();    % sized to the connected machine's timers
S = lum.gui.TestPulseDesigner();   % defaults: paired-pulse probes alternating A and B, all recording long
```

---

## 6. Watching a session

One figure, updated in place once per trial, with a header giving the subject, stage, stimulus
set and its seed, what a broken hold does, trial count, performance, the **water drunk** (total, then side
rewards and centre rewards apart), the **centre hold** the running trial asks for (latency plus
hold), and session time — and the **House light** box. The trial number and the water total
are in bold colour so they read at a glance.

**What the performance counts.** In training and experiment it is *% correct of the choices made*
(`72% correct of 80 choices`): a trial without a choice (no poke, a hold not completed, no side
poke in time) says nothing about which side the animal thinks is right, so it is left out, as in
Performance, By side and the psychometric panel. How many trials paid is in the water line
(*side rewards*). In habituation both side ports pay, so what the animal learns is to finish the
trial: the header, Performance and By side count **every trial**, and one without a choice counts
as not rewarded (`57% of 140 trials rewarded (80 choices)`).

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
    channel A above B (the title is the key), with the side each pays; shown from the moment the
    session starts
  - **Outcomes** — each trial's choice by stimulus group (along the family's evidence, such as
    A's share of the light, when every trial has a pattern of its own): correct, incorrect or no
    choice. In habituation, where both
    side ports pay, a choice is *rewarded* (green) or *not rewarded* (it left before the valve
    opened), and a trial with no choice is grey; the header, Performance and By side count every
    trial, a trial with no choice as not rewarded, and Evidence scores choices by the reward
- Middle row
  - **Performance** — fraction correct of the choices over a moving window, for all, left- and
    right-rewarded trials; in habituation the fraction of trials rewarded
  - **Psychometric** — P(choose left) with error bars along the family's evidence: A's share of the
    light or A minus B (mixture), A flashes minus B flashes (sequence), or the deciding channel's
    amount (the mixture's controls), a point per value, or eight bins when the amounts are drawn every trial;
    one point per group for the pure channel, order, motif and hand-drawn families — with the
    contingency drawn behind it
  - **Evidence, u_A vs u_B** — every choice at the latent evidence its trial's stimulus carried on
    each channel: u_A and u_B, the fraction of the stimulus window channel A and channel B were lit.
    Points are filled green when correct and outlined red when not, and point left (◀) or right (▶)
    for the side chosen. An animal reading one channel separates its left and right choices along a
    vertical or horizontal boundary; one weighing both, along a diagonal. The dashed line is the
    boundary the contingency itself draws (diagonal for comparing, vertical or horizontal for the
    mixture's controls, none for order and words). Light-off trials sit at the origin, and a small
    fixed jitter keeps repeated patterns visible.
- Bottom row
  - **By side** — fraction correct on left- and right-rewarded trials (in habituation, fraction of
    each side's trials rewarded); the number above each bar is the trials it counts
  - **Side bias** — P(chose left) over the last `BiasWindow` choices (as set when the session
    started), with the P(left) that bias correction aimed for on each trial (in a block, its side:
    1 left, 0 right)
  - **Reaction time** — by side chosen, with a running median, on a log axis (0.1 to 1 s at least,
    widened to what is on screen), so a trained animal's fraction of a second and a new animal's
    several seconds both read
  - **Centre hold** — how long the animal stayed in the centre port on each trial's last hold,
    from the poke to leaving (`Data.CentreHoldTime`): green dots where the hold was completed,
    grey crosses where the trial ended without one, against a grey line for the time the trial
    asked for (latency plus hold), which follows automatic shaping

**A completed hold is a completed hold.** A mouse that withdrew early, came back and then held
for the full time *completed its hold* (it goes on to choose, and may be rewarded), so the
figure, the runtime window and the summary plots count it as such; early withdrawals are not an
outcome of their own. A trial that ended with no completed hold is a trial without a choice:
*hold not completed* (every hold broke until the hold window ran out, or, with *End trial*, the
first early withdrawal ended it) or *no hold started*. How many attempts a hold took, and how
often the animal held **on the first attempt**, is the summary plots' `09_HoldAttempts` (the
figure has no room for it); the runtime window says it per trial (*held on attempt 3*). A
forgiven break (grace) is part of the same attempt.

**Colours** mean one thing each, in this figure, the sleep figure and the summary plots alike:
channel A teal and channel B coral; left navy and right gold; correct or rewarded sage green (a
filled mark) and incorrect or not rewarded rust (an open mark); a hold completed after early
withdrawals pale sage; greys for trials without a choice (light: no side poke in time,
dark: hold not completed, mid: no hold started). A series with no side or outcome (the
psychometric curve, a median, the hold asked for, water) is near black. The plots are drawn for
print: white background, dark axes and labels, one font at 10–12 points (a step smaller in the
live figure, whose nine panels share one window), and the summary plots at 150 dpi.

Each panel's key is one row under its axis label, clear of the data. The per-trial panels scroll
with the session and rescale to what is on screen, so they stay legible at any point in it. **Closing the figure does not stop the session** — it only hides it.
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
console. Stopping it from the console (**End**) cuts the running block of about 10 s short: the
pulses and light it sent before the stop reach the cameras and the ePhys recording but not the
data file's pulse lists, so the file keeps what that block was to send (`Session.StoppedBlock`,
[`docs/data-format.md`](docs/data-format.md)). Letting the recording run to its end avoids this.

### Test pulses

Light on channels A and B during the recording, to probe the bulb's response to it and to change
that response. It goes out exactly as a behaviour stimulus does: Bpod drives BNC1 and BNC2, and
PulsePal, in gated mode, fills each gate.

- A **probe** is one *epoch* every *inter-epoch interval* (30 s by default): a single pulse, or a
  pair of pulses an *inter-pulse interval* apart (50 ms), each 10 ms of constant light. Both
  intervals are onset to onset.
- **Plasticity trains**, once switched on, are named definitions: bursts of pulses at a pulse
  frequency, bursts at a burst frequency, a number of trains a train interval apart. Bpod gates each
  burst and PulsePal puts the pulses in it. Provided: *Theta burst* — 10 bursts of 4 pulses (5 ms)
  at 100 Hz, bursts at 4 Hz, 5 trains 20 s apart — and *High frequency* — 100 pulses (5 ms) at
  100 Hz, 4 trains 20 s apart. Any other can be added.
- The **schedule** is a list of steps run in order from the start of the recording: a probe or rest
  for so many minutes, or a train (which lasts its trains), on A and B together, on one of them, or
  alternating between them epoch by epoch. The last probe or rest step can go on **until the
  recording ends** (Minutes `Inf` in the designer's table). The default is one such step of
  paired-pulse probes, alternating: a pair on A, 30 s, a pair on B, 30 s, and so on, for as long as
  the recording lasts (the sleep dialog's *Duration*, 120 min by default: 120 pairs on each channel).
  No epoch lights both channels, so each evoked response has one source. Choose *A and B* in a step's
  Channels to send each epoch on both at once. The designer's presets and new steps alternate too,
  and a new step goes in before a last step that runs to the end.
  **When the last step has a length of its own, the recording lasts as long as the schedule**, and
  *Duration* is greyed out.
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
  a baseline) to a highest one, in a number of levels (8). On a calibrated channel it runs from 0 to
  12 mW/mm² by default, levels evenly spaced in irradiance; if the channel gives less than 12 within
  its limit, the curve ends at the most it gives, and a note says so. On a channel that is not
  calibrated it runs in mA, from 0 to the channel's limit by default (leave *to* empty for the limit).
- **Paired-pulse ratio** — pairs of pulses at one intensity (8 mW/mm² by default, or 100 mA on a
  channel that is not calibrated), one step per inter-pulse interval (onset to onset): 20, 30, 50, 75,
  100, 200, 300 and 500 ms by default.
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
  the cables at the commutator, swap them here too. **Calibrate LED power…** measures the cables (below).
- **Intensity** — per channel: the intensity, the **limit** in mA (1000 by default, the LED's rating
  and the most the driver takes in continuous mode; the LED is never set above it. Doric recommends
  700 mA for light held on for long. The driver's front knob caps the current too, whatever the
  software asks, so turn it to 1000 mA to use it all), the light path (cable, fibers, area) and the
  calibration. On a channel whose cable is calibrated on that channel the intensity is irradiance at
  the fiber tips, in mW/mm², and the field shows the current that gives it; the session sets that
  current as it starts. By default **8 mW/mm²** on both channels in behaviour and **2 mW/mm²** for
  sleep test pulses (the sleep dialog's tab sets the test pulses' own). Asked for more than the
  channel gives within its limit, it runs at the most it gives, and the field and the session's notes
  say so. On a channel that is not calibrated the intensity is the LED current in mA (100 by default),
  so a bundle that has never been calibrated runs without one. In the ePhys calibration dialog the
  intensities are on its own tab (§8).

A session with light whose LED is controlled from MATLAB does not start if the driver does not
connect: check its USB cable and power and that Doric Neuroscience Studio is closed, or untick the
control. The protocol switches both channels off when the session ends.

**Calibrating.** Irradiance is the power leaving a cable divided by the area of its fibers at the tip
(each 100 µm across: blue 9 and green 10 on the 2-to-19 bundle; black 4, the others 5 on the
4-to-19). **Calibrate LED power…** opens one window for the two cables on the commutator, one on each
channel. It starts with the tab's bundle and cables; the 2-to-19 bundle is one pair (blue and green),
the 4-to-19 two (for example orange and blue, then black and green: plug the next pair into the
commutator and choose it). The line under the cables says which of the bundle's cables are calibrated
on A and on B, and when.

1. Hold the power meter at a cable's tip (set to 465 nm) and zero it with the LED off. Keep the
   fibers away from any animal: the light is continuous (the driver's continuous mode). A calibration
   that reads more than 0.3 mW/mm² at 0 mA gives low irradiances too much current, and every
   session using it says so.
2. Choose the meter's unit (**mW** or **uW**). Each channel has a table of currents, 0–1000 mA in
   100 mA steps (`S.Doric.CalibrationCurrentsmA`), never above that channel's limit. A cable already
   calibrated on that channel starts with its saved readings and currents, so only the empty rows need
   measuring: a calibration to 700 mA shows its readings with 800, 900 and 1000 mA left to read.
   **Fill** adds the From–To series to both tables and keeps every reading (From = To adds one
   current); a row's mA can be typed over. Changing the unit converts the powers already there. Rows
   left without a power are not part of the calibration.
3. Select a row of a channel and press its **On**; type the power read; press **Next**. A lit channel
   follows the selected row, so **Next** lights the next current. **Off** switches that channel off.
   Without a connected driver, set each current on the driver by hand.
4. Each channel's graph (current against mW/mm²) fills in as you type, with that cable's saved
   calibration dashed behind it. The line above each table says whether its readings can be saved: a
   calibration needs readings at 4 currents above 0 mA at least, the highest 400 mA or more
   (`lum.led.checkCoverage`), because a few low readings (0, 50, 100 mA) would cap every session at
   that channel's dimmest light. **Save calibrations** writes each channel with new readings. Choosing
   another cable drops that channel's unsaved readings, after asking. Closing the window switches both
   channels off.

A calibration is used up to its highest reading: with readings to 700 mA and a 1000 mA limit, a
session that asks for more than the 700 mA reading gives runs at 700 mA, and says so, until the
cable is measured further. A saved calibration with too few readings is not used (the channel is then
in mA, with a warning) but is still shown in the window to be added to.

A calibration belongs to a cable **on a channel**: the light leaving a cable depends on the LED and
the commutator channel feeding it, so the orange cable on A and the orange cable on B are two
calibrations. To use a cable on both channels, calibrate it on A, swap the pair at the commutator (and
on the tab), and calibrate it on B. Each is saved in `calibration/` in the protocol folder
(`DoricLED_<bundle>_<cable>_<A|B>.mat`, with a `.png` of the graph), which git does not track, so each
rig keeps its own; calibrating the same cable on the same channel again replaces it. A calibration
saved before 0.9.1 (`DoricLED_<bundle>_<cable>.mat`) is still used, on the channel it was measured on
only. From then on every session type, and the LED window, takes that channel's intensity in mW/mm².
Data keep the current sent, in mA, and each data file stores the calibrations it used and the
intensity asked for, so irradiance can always be worked out again.

**Delay.** Setting an intensity adds nothing to a trial. The current is set once as the session
starts; after that the driver is written to only when you press **Apply** in the LED window, once
in the running trial's ITI (or between sleep blocks, or before an ePhys step), one command per channel
that takes under a millisecond of MATLAB's time and that the driver acknowledges in 5–9 ms, while no
light is gated. Timing within the trial is Bpod's and PulsePal's alone.

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
| Cameras | 24226887 *topview*, 24226657 *sideview* | One row per camera: serial, view (the file prefix), record, crop (`x,y wxh` in sensor pixels, typed or drawn on the preview). **Find attached** adds attached cameras; **Full frame** clears the crops |
| Frame rate | 100 Hz | For every camera; up to 120 Hz at full frame, above that crop |
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
the finer controls; what it leaves (crop, names, frame rate, exposure, gain) is read back when it
closes. Preview releases the cameras when stopped and when the dialog closes, and **SpinView must
be closed**: a camera can be streamed by only one program.

**Cropping.** While previewing, press **Draw crop**, then press on a camera's picture, drag a
rectangle round what to keep and release: the camera is cropped to it at once (as close as the
camera's size steps allow, never larger) and the preview shows the crop. Draw again inside the crop
to crop further; **Full frame** undoes every crop. A crop can also be typed into the table's Crop
column (`240,192 640x640`, or `full frame`). A smaller crop encodes faster and allows higher frame
rates.

**Crops are kept per session type.** The crop a behaviour session used is loaded again for the next
behaviour session, a sleep session's for the next sleep session, and an ePhys calibration's for the
next of those: a box and a home cage film different places, so a crop drawn for one never crops the
other. A session type with no crop yet records the full frame. (A settings file from before 0.9.6
keeps its crops for the type of session it last ran.)

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
D:\luminoseData\<subject>\LuminoseFM\Session Plots\NN_<Plot>_PP_<subject>_<YYYYMMDD_HHMMSS>.png
D:\luminoseData\<subject>\LuminoseFM\Session Logs\<subject>_LuminoseFM_<YYYYMMDD_HHMMSS>_log.md
```

The `.mat` holds one variable, `SessionData`, saved every few trials, so a crash costs at most a
few trials.

- **`_ANLG.dat`** is Bpod's raw recording of the flow meter (Flex1, 1 kHz), written as the session
  runs because Bpod streams analog input straight to disk. At the end of the session it is read
  back into the `.mat` as `SessionData.Analog`, so for analysis the `.mat` is enough. Keep the
  `.dat` anyway: it is the only copy of the airflow if MATLAB or the computer fails before the
  session ends. It is written only when a Flex channel is an
  analog input — not in the emulator. The launch manager creates it before the protocol starts;
  a session cancelled in a setup dialog deletes its empty one (up to 0.9.5 it was left behind).
  Not always: opening the setup dialog to look and cancelling it left an empty
  `LUMS0014_LuminoseFM_20261003_142915_ANLG.dat` on 2026-10-03, cause not found. An empty
  `_ANLG.dat` with no `.mat` of the same name is such a launch: no session ran, and it can be
  deleted or left.
  Details in [`docs/data-format.md`](docs/data-format.md).
- **`_plots.png`** is the online figure as it looked when the session ended.
- **Session Plots** (0.9.8, behaviour sessions) holds the session's summary plots for you and
  colleagues to look through: every panel of the online figure over the **whole** session, each
  as its own image, and more (how each trial ended, hold attempts, engagement over time, pokes
  at each port, MATLAB's timing). Named `NN_<Plot>_PP_<subject>_<date>_<time>.png`, so sorting by
  name puts one kind of plot from every session together, by date: `01_Outcomes`,
  `02_Performance`, `03_Psychometric`, `04_Evidence`, `05_BySide`, `06_SideBias`,
  `07_ReactionTime`, `08_CentreHold`, `09_HoldAttempts`, `10_Engagement`, `11_PortActivity`,
  `12_SessionTiming`, `13_PulseLocking`, `14_Habits` (0.10.0), and in a session that ran blocks
  `15_BlockSwitches`. `PP` is the page: 01, unless the outcomes run over more than 400 trials.
  `14_Habits` and `15_BlockSwitches` are described in §3, *Strategy correction*; for an earlier
  session, `lum.report.fromFile(dataFile, 'Plots', 14)` adds `14_Habits`.
  About 0.5 MB a session. `08_CentreHold` is the time in the port on each trial's last hold
  (completed or not) with the hold asked for and the step backs, and how long the completed holds
  lasted. `09_HoldAttempts` is the one plot that tells a first attempt from a later one: in bins
  of trials, the share held on the first attempt, held after early withdrawals, not completed and
  with no hold started; the attempts each trial took; and the first-attempt rate by the hold
  asked for. `13_PulseLocking` (0.9.13) asks whether the animal senses the light, without asking
  it to tell A from B: an animal that senses the carrier's pulses tends to leave the centre port
  at a fixed time after one. It shows each early withdrawal made in the light by its time into the
  light, with the pulses drawn behind; the same folded on the carrier's period (at 20 Hz, 0–50 ms
  after a pulse began), by channel, beside the dashed share the withdrawal times' own shape would
  put there; and, at 10–50 Hz, the locking beyond that shape against the dashed line chance
  reaches. The shape matters because most withdrawals come late in the window, and that alone
  points the mean time after a pulse near 36 ms at 20 Hz, light or no light. So the title and the
  log give the locking *beyond their shape* (0 to 2; 0 when the shape explains everything), the
  time after a pulse it points to (the vertical line), and its p (0.9.14). A peak at the carrier's
  frequency above the dashed line is the sign. The pulses start at the poke, so anything the animal
  does at a fixed time after the poke, narrower than a period, looks the same: habituation's quick
  withdrawals 30–70 ms after the poke do, without light. Only a session at another carrier
  frequency tells them apart (`docs/learning-time-literature.md`, which also says why it cannot
  name the sense). Constant light has no pulses and says *Not measured*; a session without light
  is drawn against the pulses it would have had.
- **Session Logs** (0.9.8, behaviour sessions) holds `<data file name>_log.md`, a plain-text
  summary for the lab notebook: when and how the session ran, the animal, the settings
  that shape a trial, how the animal did (score, choices, water, the hold, early withdrawals
  against the light's pulses (the locking beyond their shape, where it points and its p, then R and
  its p), reaction time, side bias, the habits and, with blocks, the first trial after a switch,
  50-trial blocks), what was changed during the session, and the recordings.
- **Ending a session takes a few seconds longer** (0.9.8): once the data are saved, the video
  stopped and the rig released, the session draws the summary plots and writes the log, about
  0.3 s a plot (4–8 s in all). The console says *writing its summary plots and log* while it does,
  and where they went when it is done. Wait for the last line, *the session is finished; MATLAB
  can be closed* (0.9.12), before closing MATLAB: closed earlier, the plots, the log or the memory
  record below can be missing. The data, the settings and the video are written before them, and
  nothing in the data file depends on them.
- **Plots and log for an older session**, or again with the current version:
  `lum.report.fromFile(dataFile)`; add `'OnlinePlots', true` to redraw `_plots.png` too. The data
  file is only read. Sessions before 0.9.6 are rescored in memory with the current scorer (a side
  poke after the response window was counted as a choice then).
- **LED intensity.** Each behaviour trial records the LED current it ran at on A and B
  (`LEDCurrentA`, `LEDCurrentB`, mA); sleep and ePhys calibration sessions record it per gate of
  light (`LightSegments.CurrentmA`). `SessionData.Session.DoricLED` holds the light paths and the
  calibrations used, so `lum.led.irradiance(SessionData.Session.DoricLED.Calibrations{1}, mA)` gives
  channel A's irradiance.
- **Settings.** The settings file chosen in the launch manager (`DefaultSettings` unless you make
  another) holds the last session's settings: it is written when **Start** is pressed and again
  when the session ends, so runtime changes (reward, timing), the house light, a growing hold (§3)
  and each session type's camera crops (§10) carry over to the next session. To keep a set of settings apart — per animal, or per stage — create a new settings file
  in the launch manager and choose it. Every data file also holds the exact settings it ran with,
  in `SessionData.Session.Settings`.
- **Moving data off the rig: leave `Session Settings` behind.** The settings file is kept in the
  data folder, beside the data. If a subject's whole folder is moved away, the launch manager no
  longer lists the subject; created again, it gets an empty settings file, and the next session
  starts from the defaults: every setting, the hold a growing hold had reached (it starts again at 0.2 s) and the
  camera crops. Move `Session Data`, `Session Videos`, `Session Plots` and `Session Logs`, and leave
  `<subject>\LuminoseFM\Session Settings\` in `D:\luminoseData`, or copy it back before the next
  session: a settings file put back into a subject's `Session Settings` folder is used as it is. LED
  calibrations (`calibration/` in this repository) and the valves' liquid calibration (`Bpod Local`)
  are not in the data folder and are not affected.

Session-level information — the settings, the stimulus set, the rig map, the barcode —
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

MATLAB's memory is recorded with every save (`SessionData.Timing.memoryGB`, GB) and printed when the
session ends. If it grows past twice what it was at trial 1 (and past 8 GB) the session warns once;
end the session before MATLAB runs out of memory.

**After a session `BpodSystem` is no longer listed in MATLAB's Workspace panel** (0.9.7). With it
listed, MATLAB R2025b's Workspace browser went through every change the session had made to it once
the session ended, and ran MATLAB out of memory a few minutes later (LUMS0014's sessions of
2026-09-25 and -26). The session removes it from the base workspace as its last step; Bpod keeps it,
so `EndBpod`, the console and the next session work as before. For four minutes after a desktop
session (of any type) a small background process also writes `<data file name>_memory.csv` beside the data file,
MATLAB's memory once a second; it can be deleted. The console says until when. Closing MATLAB
sooner only shortens it, or leaves none when MATLAB is closed before the session is finished
(LUMS0014 2026-10-03); nothing else needs it.

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

**Passing on this rig since 2026-09-21**: the light switches on and off, and every switch reaches
BNC input 1, 18–33 ms after its command (P1 in [`docs/rig-checks.md`](docs/rig-checks.md)).

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
pattern with more than three stretches of light is refused there and accepted on the rig. Emulated
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

---

## 15. Help at the MATLAB prompt

Every function, class and utility in the repository explains itself: what it is for, its
arguments, what it returns and where to look next. MATLAB shows that text with its usual commands:

```matlab
help lum                           % every file in the lum package, one line each
help lum.led                       % the same for one part: lum.pattern, lum.sleep, lum.dev...
help lum.led.irradiance            % what one function does, its arguments and what it returns
doc lum.dev.PulsePal               % the same in the help browser, See also names as links
help lum.dev.PulsePal.holdVoltage  % one method of a class
methods lum.dev.DoricLED           % a class's methods (properties lists its properties)
help TestSyncLine                  % a utility's options (hardware/ must be on the path)
which lum.version                  % where a name comes from: this repository, Bpod, MATLAB
edit lum.buildTrialSM              % the source
```

`lookfor` does not search inside packages: `help lum.<part>` is the list to read. Bpod's own
functions answer the same way (`help BpodTrialManager`). The full table, and how the help text and
comments are written and checked, are in [`docs/code-style.md`](docs/code-style.md).
