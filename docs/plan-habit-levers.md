# Strategy correction: what is still open, and using it with LUMS0014

Strategy correction was planned on 2026-10-05, after the audit of LUMS0014's session of that day,
and built the same day in 0.10.0: habit measures, side pokes before the response, context
correction and blocks. Its design is decision D23 in [`architecture.md`](architecture.md), the
operator's side is the README (§3, *Strategy correction*), the data are in
[`data-format.md`](data-format.md) (*Sessions with strategy correction*), and the rig check is P15
in [`rig-checks.md`](rig-checks.md). This file keeps what is still open and the order of use for
LUMS0014; delete it once nothing is.

**Contents:** [Decisions](#decisions) · [Using it with LUMS0014](#using-it-with-lums0014) ·
[Still open](#still-open)

---

## Decisions

Made by the operator on 2026-10-05:

1. All four parts as one feature, one release (0.10.0), all runtime settings, off by default.
2. Side pokes before the response first for LUMS0014, *Delay* before *End trial*.
3. Every setting runtime, *Correct for* included.
4. The reward floor F in 0–50%, the correction rising in a straight line from none at F to full at
   50% (no separate ramp width); its window 50 choices.
5. Context correction while incorrect choices are retried: *Correct for* greyed out, side bias
   used (not a refusal).
6. The swap partner drawn at random from every later pattern that can serve (the pile-up fix),
   with the regression test against 0.9.14 using the first.
7. Blocks, when used: 15–25 trials, switching by length (the agent's call; reasons below).
8. Choosing *Experiment* sets the run limit (`S.Task.MaxSameSide`) to 0 with bias correction's
   strength and every part off.

---

## Using it with LUMS0014

The order is the operator's: from the lever that leaves the trial order alone to the one that
changes it most, so the analysis of each step stays as clean as it can, and from no cost to the
habit to a cost. Change one thing at a time, as for the light. Read each step from the log's
*Habits* line (and *Blocks* line), not from % correct.

**Step 1: side pokes before the response, two sessions.** *Delay*, 1 s, everything else as on
2026-10-05 (random order, bias correction *Side bias* 0.5, timeout 1 s, the light at 20 Hz × 20 ms,
12 mW/mm²). P15 part 1 has passed.

- Nothing in it makes the habit pay less, so % correct is expected to stay near 50%: the habit
  should move from the visits into the choices (choices alternating more often, from about 50%
  towards the visits' 96%).
- It has done its job when side pokes before the response fall from 0.6 a trial to under 0.1.
- If the mouse is rewarded on fewer than 40% of trials, or runs far fewer trials, shorten the delay
  or go back. *End trial* is the harder version, for a third session if the free pokes do not fall.

**Step 2: context correction.** *Last choice and reward*, strength 0.5, floor 40%, side pokes kept
(P15 part 2 has passed; incorrect choices must be punished, as they are at the 1 s timeout).

- The habit should earn about 43%. If the mouse drops it, % correct and the stimulus weight
  (fitted with the history terms, `python-analysis.md`) should move.
- Continue while P(left | A) − P(left | B) or the stimulus weight rises; if neither passes 0.10
  after three or four sessions, go to step 3. Watch the reward share and the trial count.

**Step 3: blocks, if nothing else has worked.** 15–25 trials by length, side pokes still on *Delay*:

| What the log shows | Next |
|---|---|
| First trial after a switch at 20 or more of about 30 correct, two sessions running | shorten the blocks to 10–15; then 5–10 on the same criterion; then a random order with context correction again |
| Accuracy within blocks rising (trials 3 onwards at 80% or more), first trial at about 0% | win-stay learned, the light not used: keep blocks two more sessions; if the first trial stays at 50% or less, test perception directly (light against no light, `learning-time-literature.md`) |
| Choices still alternating within blocks (trials 3 onwards near 50%) after two sessions | *End trial* for side pokes, blocks unchanged |
| Rewarded on fewer than 40% of trials, or fewer trials than usual | go back to the settings before |

Why 15–25 by length:

- **About 30 switches in a 600-trial session,** so the first trial after a switch decides in one
  session: 20 or more correct of 30 has p 0.049 against an alternator's 50% (binomial, one-sided).
  Longer blocks halve the switches; shorter ones give win-stay less to gain (about 90%) and the
  pairing of A with left fewer repeats.
- **A mean of 20** makes win-stay pay about 95% against the habit's 50%, and repeats A with left
  (or B with right) about twenty times in a row.
- **By length, not performance:** the number of switches does not depend on the animal; an
  alternator is not held in every block to its longest; the longest, 25, caps a run on the side it
  avoids (it chose left on 66% of choices on 10-05).
- **A random length**, so a switch cannot be counted to.

Blocks are also the most direct test of whether the mouse can use the light at all: if steps 1 and
2 fail, the reason may be that it cannot, and the first trial after a switch answers that.

---

## Still open

- **The animal.** No session has run any lever on an animal yet. Record each in
  `learning-time-literature.md` (the LUMS0014 table: which levers, the *Habits* line, for blocks the
  first trial after a switch rather than % correct).
- **P16**, the Strategy tab seen in a desktop session (`rig-checks.md`, *Pending*).
- **Slow preparations after the choice.** LUMS0014's sessions had preparations up to 0.55 s on 1%
  of trials; on the rig (P15) the state machine's build was the slow part (at most 238 ms). With
  context correction at the 1 s timeout, check `Timing.awaitChoice`, `.spec`, `.build` and the gaps
  between trials in the first animal session.
- **Blocks shortened automatically**, under automatic shaping, once the first trial after a switch
  is reliably correct: not built; by hand from day to day for now.
- **Drawing one length per pair of blocks** (the right block as long as the left before it) would
  make the sides even to within the last block (12 trials from even in the worst of 20,000 simulated
  600-trial sessions, against 45 with a length per block) but would let the second block's length
  be counted. Not built; listed in case exact balance matters more to an analysis than an
  unpredictable switch.
