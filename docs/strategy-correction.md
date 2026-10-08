# Strategy correction: how each setting works

This is the reference for the runtime window's **Strategy** tab (and the setup dialog's Runtime
tab, where the same settings appear). For each setting it gives what is computed, the formula, a
worked example and the reason for it. How to use the levers with an animal is in the README
(§3, *Strategy correction*), the design decision in [`architecture.md`](architecture.md) (D23),
the order of use for LUMS0014 in [`plan-habit-levers.md`](plan-habit-levers.md), and what each
trial records in [`data-format.md`](data-format.md) (*Sessions with strategy correction*).

Every example uses LUMS0014's session of 2026-10-05 where it can: 600 trials in 80 min (about 8 s
a trial), left on 66% of choices, rewarded on 47%, a side poke before the response 0.6 times a
trial, and its choice at the port opposite the last side port it poked on 98% of choices.

**Contents:** [The problem](#1-the-problem) · [How a trial's side is chosen](#2-how-a-trials-side-is-chosen) ·
[Bias correction](#3-bias-correction-bias-panel) · [Correct for](#4-correct-for-context-correction) ·
[Reward floor](#5-reward-floor) · [Blocks](#6-blocks-blocks-panel) ·
[Side pokes](#7-side-pokes-before-the-response-side-pokes-panel) ·
[Habit measures](#8-the-habit-measures) · [Code](#9-where-it-is-in-the-code)

---

## 1. The problem

In a random trial order every way of choosing that ignores the stimulus earns 50%: always left,
alternating, staying after a reward, switching after an error. Nothing makes the animal give one
up, so it keeps the one it has. Each lever on the Strategy tab changes that in one of three ways:

| Lever | What it changes | So that |
|---|---|---|
| Bias correction, *Correct for* | which side the next trials pay, from the animal's recent choices | the habit it has earns less than 50% |
| Blocks | which side the next trials pay, held for a run of trials | a different habit (stay with the side that paid) earns more, and the first trial after each switch tests the light |
| Side pokes before the response | what a side poke does before the trial's choice | the visits that drive the alternation cost time or the trial |

None of them changes which side a pattern pays (the contingency) or how often each group is
delivered. An animal that follows the light is rewarded on every correct choice whatever the
settings.

---

## 2. How a trial's side is chosen

The stimulus set fixes a balanced, shuffled order of patterns for the whole session (the queue).
Each pattern has a P(left): 1 for a pattern that always pays left, 0 for one that always pays right,
something between for a probabilistic one. As each trial is prepared (`lum.nextTrialSpec`):

1. **A wanted side, if any.** Blocks, bias correction and the run limit may each ask for a side, in
   that order of precedence (below).
2. **The swap.** If the next pattern in the queue cannot pay the wanted side, it is swapped with a
   pattern drawn at random from those later in the queue that can. The queue keeps every pattern,
   so every group is still delivered as often; only the order changes.
3. **The side.** The trial's correct side is drawn from its pattern's own P(left). For a pattern
   with P(left) 1 or 0 that is the wanted side; for a probabilistic one it is only more likely.

| Precedence | Policy | Asks for |
|---|---|---|
| 1 | Blocks (*Trial order* *Blocks*) | the block's side, on every trial; the two below do not act |
| 2 | Bias correction (*Bias correction* above 0) | a side drawn with chance P(left) = the target (sections 3–5) |
| 3 | Run limit (`S.Task.MaxSameSide`, setup dialog, Task tab; 3 by default) | the other side after that many trials paying one side, unless bias correction is pushing towards the side the run is on |

**Why a swap, not a new draw.** Drawing a new side would change the contingency or the group
balance. The swap keeps both: the stimulus still predicts the side exactly as the stimulus set
says, so analysis of the light stays valid, and the animal can always do best by following it.

---

## 3. Bias correction (*Bias* panel)

**Settings.** *Bias correction* s (0–1; 0 is off; 0.5 by default), *Bias window* N (20 choices).

**What is computed.** f, the share of left choices among the animal's last N choices (trials with
no choice skipped). The target, the chance that the next trial is asked to pay left, is

$$
\text{target} = 0.5 + s \times (0.5 - f)
$$

kept within 0.1–0.9. Fewer than 3 choices so far: no correction (target 0.5).

**Example.** On 2026-10-05, f = 0.66 and s = 0.5:

- target = 0.5 + 0.5 × (0.5 − 0.66) = 0.42: about 42% of trials asked to pay left (left paid on
  41% of the session's trials).
- At s = 1 the target would be 0.34; an animal that went left on every one of its last 20 choices
  (f = 1) would get 0.5 + 1 × (−0.5) = 0, kept at 0.1: 90% of trials paying right.

**What it costs a habit.** Call the lean d = f − 0.5. An animal that keeps choosing left with
chance f, on trials that pay left with chance 0.5 − s d, is correct on

$$
P(\text{correct}) = f \thinspace (0.5 - s d) + (1 - f) \thinspace (0.5 + s d) = 0.5 - 2 s d^2
$$

On 2026-10-05, d = 0.16 and s = 0.5: 0.5 − 2 × 0.5 × 0.16² = 0.474, which is the 47% the session
scored. The cost grows with the square of the lean: a small lean costs almost nothing, a strong one
a lot.

**Why this form.** It is linear in the lean, so the push is proportional to the problem; s = 1
compensates fully (the target mirrors the lean). The 0.1–0.9 limits keep both sides paying, so
the animal never learns that one side is not worth visiting and the order stays unpredictable.

**Its blind spot.** An animal that alternates strictly goes left on 50% of choices: f = 0.5, the
target stays 0.5, and the habit still earns 50%. That is what *Correct for* is for.

---

## 4. *Correct for* (context correction)

**Setting.** *Correct for*: *Side bias* (default), *Last choice*, *Last choice and reward*.

**What is computed.** The same target as in section 3, but f is counted only over the animal's
choices made in the same **context** as the trial being prepared. A trial's context is set by the
trial before it:

| *Correct for* | Contexts (code in `Data.BiasContext`) | Counters |
|---|---|---|
| *Side bias* | one for every trial (1) | always going one way |
| *Last choice* | after a left choice (2), after a right choice (3) | alternating, staying on one side, side bias |
| *Last choice and reward* | after a rewarded left (4), unrewarded left (5), rewarded right (6), unrewarded right (7) | also win-stay and lose-shift |

So with *Last choice*, to prepare a trial that follows a left choice, f is the share of left
choices among the last N choices that themselves followed a left choice. Each context keeps its own
window of N choices, so with two contexts the correction looks back over about 2N choices in all.

A trial whose context has fewer than 3 choices in its window, or whose previous trial had no
choice (code 0), is corrected for side bias as in section 3.

**Example: a strict alternator under *Last choice*, s = 0.5.**

- After a left choice it always goes right: in that context f = 0, so the target is
  0.5 + 0.5 × 0.5 = 0.75: three trials in four after a left choice pay left, and it is correct
  on one in four.
- After a right choice, the mirror image: target 0.25, correct one in four.
- Its reward falls from 50% to 0.5 − 2 × 0.5 × 0.5² = 25%. An animal that follows the light still
  gets every correct choice rewarded.

**Example: win-stay, lose-shift under *Last choice and reward*.** After a rewarded left it stays
left on 90% of choices: f = 0.9 in context 4, target 0.5 + 0.5 × (0.5 − 0.9) = 0.3. After an
unrewarded left it shifts right on 90%: f = 0.1 in context 5, target 0.7. Each habit is pushed
against in its own context.

**Example: does *Last choice* also correct a side bias?** Yes. An animal that goes left 70% of the
time in both contexts has f = 0.7 in each, and is pushed right in each, as *Side bias* would. So
there is no need to run *Side bias* and *Last choice* together, and the menu offers one.

**Why it needs incorrect choices punished.** The context is read from the running trial's choice
as it happens (the next trial is prepared while it runs). With retries on, a wrong poke passes
through `RetryResponse`, which lasts no time, and the animal is then rewarded at the other port:
the first choice cannot be seen. So while incorrect choices are retried, *Correct for* is greyed
out and *Side bias* is used. With a context mode on, a punished incorrect choice lasts at least
50 ms, even with a 0 s timeout, so the session can read it, and a timeout plus ITI under 0.75 s can
make the next trial start late (validation notes it).

---

## 5. *Reward floor*

**Settings.** *Reward floor (%)* F (0–50%; 0 by default, no floor), *Reward floor window* W
(50 choices).

**What it does.** It turns bias correction down when the correction is costing the animal too much
water. It can only weaken bias correction, never strengthen it. Over the animal's last W choices,
r is the share that were rewarded, and the strength used is the set strength s times a scale:

| r | Scale | Strength used |
|---|---|---|
| 50% or more | 1 | s |
| between F and 50% | (r − F) / (50% − F), a straight line from 0 to 1 | between 0 and s |
| F or below | 0 | 0: no correction; the trial order as it comes |

F = 0 is no floor: the scale is always 1, and bias correction always acts at the set strength.
That is the most correction; a higher floor gives less.

**Example: F = 40%, s = 0.5.**

| Rewarded on (last 50 choices) | Scale | Strength used |
|---|---|---|
| 55% | 1 | 0.5 |
| 50% | 1 | 0.5 |
| 45% | (45 − 40) / (50 − 40) = 0.5 | 0.25 |
| 42% | 0.2 | 0.1 |
| 40% or less | 0 | 0 |

**Where a habit settles.** A habit that earns 0.5 − c at full strength (c = 2 s d², section 3)
earns 0.5 − c × scale under the floor, and the scale depends on what it earns. The two meet at

$$
r^{\ast} = \frac{0.5 + c F / w}{1 + c / w}, \qquad w = 0.5 - F
$$

For a strict alternator under *Last choice and reward* at s = 0.5 (c = 0.25) and F = 40%
(w = 0.1): r\* = (0.5 + 0.25 × 4) / (1 + 2.5) = 0.43. The habit keeps paying about 43%, instead of
25% with no floor, while an animal that follows the light still earns 100%.

**Why it ramps to none at F.** Below the floor the habit earns 50% again, so the animal's reward
rises back above F, and it settles between F and 50%. A floor that only scaled the strength down
(the first design, s × r / F) never switched the correction off, so the habit settled below the
floor it was meant to hold (33% at F = 40%). It applies in every *Correct for* mode, *Side bias*
included.

---

## 6. Blocks (*Blocks* panel)

**Settings.** *Trial order* (*Random* by default, *Blocks*), *Block length, shortest* and
*longest* (15 and 25 trials), *Switch after correct in a row* N (0 by default: by length only).

**What is computed.** The first block's side is drawn at random; each block after takes the other
side. Its length is drawn evenly from shortest to longest, in whole trials (15, 16, …, 25, each
with chance 1/11; mean 20). Within a block, every trial gets a pattern that leans to the block's
side (or to neither), brought forward by the swap of section 2. With N above 0, a block ends
instead once it has run its shortest length and the animal's last N choices in it were correct,
or at its longest. Bias correction and the run limit do not act while blocks run.

**Example: blocks of 15–25 in a 600-trial session.** About 600 / 20 = 30 blocks, so about 30
switches. What each way of choosing earns (patterns that always pay one side):

| Way of choosing | Earns | First trial after a switch |
|---|---|---|
| Stay with the side that just paid (win-stay) | about 1 − 1/20 = 95%: wrong only on each block's first trial | about 0% correct |
| Alternate, or always go one way | 50% | about 50% |
| Follow the light | 100% | 100% |

**The first trial after a switch is the test of the light.** Only the light tells the animal the
side has changed. 20 or more correct of 30 first trials has p = 0.049 against an animal at 50%
(binomial, one-sided), so one session can tell.

**Why 15–25, by length, at random.** A mean of 20 makes staying pay well (95%) while giving about
30 switches a session. Ending blocks by length keeps the number of switches independent of the
animal. A random length means a switch cannot be counted to.

**Example: *Switch after correct in a row* N = 5, shortest 15, longest 25.** A block can end from
its 15th trial once the last 5 choices in it were correct, and ends at 25 regardless. The count uses
recorded trials, and the next trial is prepared while the last one runs, so a block ends one trial
after the criterion is met.

**What it does to analysis.** Inside a block the side is predictable from the trials before, so the
psychometric and evidence plots and the log's *By group* use only trials outside blocks and each
block's first trial; `15_BlockSwitches` and the log's *Blocks* line are the session's measure of
the light.

---

## 7. Side pokes before the response (*Side pokes* panel)

**Settings.** *Side poke before the response* (*Ignore* by default, *Delay*, *End trial*), *Side
poke delay* (1 s; used by *Delay* only), *Side poke in a timeout* (*Ignore* by default, *Restart
the timeout*; 0.11.0), *Sound on a side poke that costs time* (off; 0.11.0).

**When it acts.** *Side poke before the response* only while the trial waits for a centre poke
(state `WaitForCentrePoke`): from the trial's start, and after an early withdrawal that restarts
the stimulus. *Side poke in a timeout* during the timeout of a punished incorrect choice or early
withdrawal. Side pokes during the drinking grace or the ITI are not affected.

| Setting | What a side poke does | Cost |
|---|---|---|
| *Ignore* | nothing | none |
| *Delay* | the cue goes off and centre pokes are ignored for the delay (state `SidePokeDelay`); further side pokes in the delay are ignored and do not restart it; then the trial waits for a centre poke again, cue on. The hold window keeps running: if it ends during the delay, the trial is *No initiation* | the delay, each time |
| *End trial* | the trial ends unrewarded (state `SidePokeBeforeChoice`, outcome 7), with the early withdrawal's punishment if early withdrawals are punished | the trial; with early withdrawals unpunished no timeout, so the next trial starts after the ITI (less than a 1 s delay), and context correction uses side bias on it (no previous choice) |

**In a timeout.** With *Restart the timeout*, a poke at the side port other than the one the
animal was last in starts the timeout again, from its beginning (states
`IncorrectChoiceRestartLeft`/`Right`, `EarlyWithdrawalRestartLeft`/`Right`); a poke back into the
same port does not. After an incorrect choice the animal is in the port it chose, so the habit's
visit to the other port restarts it; a nose moving in and out of the chosen port, or a beam
flickering, does not. Only a timeout above 0 s is restarted (*Punishment* panel: each mistake's
punishment and timeout are set apart). Counted per trial in `Data.TimeoutRestarts`.

**Why the timeout too.** On 2026-10-08, at a 3 s delay and a 3 s timeout, LUMS0014's habit visit
moved into the timeout, which cost nothing: a side poke came during 32% of timeouts (6% and 11% at
1 s on 10-06 and 10-07), and the next choice went opposite the last of them on 83%, repeating the
error on 73% of those trials.

**The sound.** *Sound on a side poke that costs time* plays a 0.15 s noise burst
(`S.Sound.SidePokeSoundDuration`, Cue tab, *Sound output*) as a side poke enters `SidePokeDelay`,
`SidePokeBeforeChoice` (unless the punishment noise plays there) or a restart state, so the
animal hears which poke cost it time. A punishment noise still playing stops. Off by default, and
silent with *Play sounds* unticked.

**Example: *Delay* 1 s on 2026-10-05's behaviour.** At 0.6 side pokes a trial, about 0.6 s a
trial, against about 8 s a trial: a 7% slower session if nothing changes. Each delay is counted
per trial in `Data.SidePokeDelays`.

**Why this lever comes first, and why it is needed at all.** The side poke before the response
set which side the animal chose next (opposite it on 98% of choices). Trial *k*+1 is chosen before
its own side pokes happen, so no trial-order policy can react to them; only a cost on the poke
itself can. *Delay* costs time and nothing else, so % correct should stay near 50% while the
visits fall; the habit is then expected to show in the choices themselves, where *Correct for*
can see it.

---

## 8. The habit measures

Every behaviour session's log has a *Habits* line, and `14_Habits` plots the same measures per 100
trials (`lum.report.habits`). Judge each lever from these, not from % correct.

| Measure | Computed as | 2026-10-05 |
|---|---|---|
| Chose opposite the last side poke | share of choices at the port opposite the side port poked just before (in this trial or earlier) | 98% |
| After a centre poke, the other side | share of side pokes, after a centre poke, at the other side from the side poke before it | 96% |
| Alternation (and expected) | share of choices on the other side from the last choice; expected from the side bias alone, 2p(1 − p) with p the share of left choices | |
| Repeat after a reward / after an error | share of choices repeating the last choice when it was rewarded (win-stay) / not rewarded (1 − lose-shift) | 49% / 50% |
| Side pokes before the response | per trial, before the first centre poke or between hold attempts | 0.6 |
| Delayed / ended by a side poke | trials delayed (*Delay*) / ended (*End trial*) | |
| Timeouts restarted by a side poke | trials with one, and the restarts (*Restart the timeout*) | |
| Blocks (with blocks only) | correct on each switch's first trial, second trial, trials 3 on; trials to the new side | |

---

## 9. Where it is in the code

| What | Where |
|---|---|
| The wanted side, precedence, the swap | `lum.nextTrialSpec` |
| The target, contexts, reward floor, reading the running choice | `lum.BiasCorrection` (`target`, `contextOf`, `floorScale`, `choiceFromState`) |
| Blocks | `lum.Blocks` |
| The side-poke states | `lum.buildTrialSM` (`SidePokeDelay`, `SidePokeBeforeChoice`, `IncorrectChoiceRestartLeft`/`Right`, `EarlyWithdrawalRestartLeft`/`Right`); each mistake's punishment, and whether its timeout restarts: `lum.punishmentFor` |
| Habit measures | `lum.report.habits` |
| The settings and their help | `lum.defaultSettings` (*Bias*, *Blocks*, *SidePokes* panels) |
| Simulated animals under each lever | `tests/strategyTest.m` |
