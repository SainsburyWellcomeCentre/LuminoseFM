# Stimulus families

A **stimulus family** decides what a session's two-channel light patterns look like, and so what
the subject has to tell apart to choose the rewarded side. This document defines the families from
the ground up: the signal, what can be measured about it, how a session turns patterns into a
two-alternative task, and how to tell whether a task can be solved by a simpler cue than the one
it is meant to test. The last sections show how to use the same quantities when analysing
behaviour.

It is written for two readers. If you are new to this, read sections 1–5 in order; each builds on
the one before, and every symbol is defined where it first appears. If you know the ground, go
straight to the families (section 6) and the analysis recipes (section 7). The code is in
`+lum/+pattern/` (`generate`, `familyDefaults`, `stimulusSet`, `shortcuts`); the operator's view is in
the [README](../README.md#4-the-stimulus).

---

## 1. Two channels in time

### 1.1 The signal

There are two channels, **A** and **B**. During the **stimulus window**, a time interval of length
$T$ seconds that starts at stimulus onset, each channel is either on or off:

$$q_A(t),\; q_B(t) \in \{0, 1\}, \qquad 0 \le t < T .$$

$q_A(t) = 1$ means channel A is on at time $t$. Nothing else about a channel is varied by a
family: how bright a channel is when it is on, and what it carries while it is on, are set
elsewhere and are the same on every trial. A **light pattern** is the pair $x = (q_A, q_B)$.

### 1.2 Bins

Patterns are drawn on a grid of $N$ equal **bins** of width $\Delta = T/N$. Bin $n$ ($n = 1 \dots N$)
covers $[(n-1)\Delta,\, n\Delta)$, and each channel is on or off for a whole bin:
$q_A[n], q_B[n] \in \{0, 1\}$. You type a bin width; if it does not divide $T$ exactly, $N$ is
rounded to the nearest whole number and $\Delta = T/N$ is used (a 10 ms bin in a 0.333 s window
becomes 33 bins of 10.09 ms). Every quantity below is a sum over bins.

### 1.3 Joint states

At each bin the two channels together are in one of four **joint states**:

$$s[n] = q_A[n] + 2\,q_B[n] \in \{0, 1, 2, 3\}$$

| $s$ | name | $q_A$ | $q_B$ |
|:---:|------|:---:|:---:|
| 0 | dark | 0 | 0 |
| 1 | A only | 1 | 0 |
| 2 | B only | 0 | 1 |
| 3 | A and B (overlap) | 1 | 1 |

The pattern browser draws $s[n]$ as the coloured ribbon under the two channels.

### 1.4 Segments

A **light segment** is a maximal run of consecutive bins in which one channel is on. Write $k_A$ and
$k_B$ for the number of segments on each channel. Each segment is one global timer of the state
machine, so a pattern costs $k_A + k_B$ timers, and a machine with $B$ timers left for light can
deliver only patterns with $k_A + k_B \le B$ (section 8). Segment edges are rounded to the state
machine's 100 µs cycle.

In the sequence and motif families a segment is called a **flash**: one short stretch of light on
one channel, the unit the subject counts or reads.

---

## 2. Measuring a pattern

### 2.1 Amounts

The **amount** of a channel is how long it is on:

$$u_A = \Delta \sum_{n=1}^{N} q_A[n], \qquad u_B = \Delta \sum_{n=1}^{N} q_B[n] \qquad \text{(seconds)} .$$

Dividing by the window gives the **fraction lit**, $\bar u_A = u_A / T \in [0, 1]$. The online
plots and the families' settings use fractions; the data file stores seconds.

### 2.2 Overlap, dark, total and share

$$u_{AB} = \Delta \sum_n q_A[n]\,q_B[n] \quad\text{(both on)}, \qquad
u_0 = \Delta \sum_n (1 - q_A[n])(1 - q_B[n]) \quad\text{(dark)} .$$

A only lasts $u_A - u_{AB}$ and B only $u_B - u_{AB}$, and the four joint states fill the window:

$$u_0 + (u_A - u_{AB}) + (u_B - u_{AB}) + u_{AB} = T .$$

The **total light** is $u_A + u_B$; it exceeds $T$ when the channels overlap. The **B share** is

$$\beta = \frac{u_B}{u_A + u_B} \in [0, 1] \qquad (\beta = \tfrac12 \text{ for a dark pattern}),$$

0 for A alone, 1 for B alone, $\tfrac12$ for equal amounts. It depends only on the ratio
$u_A : u_B$, not on the total. Its complement $\pi = 1 - \beta = u_A/(u_A + u_B)$ is **A's share**, A's
relative abundance in the mixture of the two; the **difference** $\delta = \bar u_A - \bar u_B$ is the
other relative measure (section 6.2).

### 2.3 In the data file

`SessionData.Session.StimulusSet.Descriptors` holds these for every pattern:

| Field | Quantity |
|-------|----------|
| `AOn`, `BOn` | $u_A$, $u_B$ (s) |
| `Overlap` | $u_{AB}$ (s) |
| `Dark` | $u_0$ (s) |
| `BShare` | $\beta$ |
| `ASegments`, `BSegments` | $k_A$, $k_B$ |

### 2.4 The plane of amounts

Every pattern is a point $(\bar u_A, \bar u_B)$ in the unit square. The diagonal $\bar u_A = \bar u_B$
holds the patterns with equal amounts; below it A is on for longer, above it B. The online plots'
*Evidence* panel draws every choice at its trial's point, which shows at a glance which part of the
plane the subject sends to each side (section 4.4).

---

## 3. A session: groups, order and contingency

### 3.1 Groups

A session is made of $K$ **groups**, its stimulus conditions, $g = 1 \dots K$. In most families
each group is one fixed pattern $x_g$, delivered identically on every trial of that group. Some
families can instead give **every trial a pattern of its own**, $x_t$, drawn afresh within its group
(a new order of the flashes, new amounts, a new phase); the group is then the condition, and the
pattern a sample of it.

### 3.2 Balanced order

For a session of $M$ trials, each group is assigned $\lfloor M/K \rfloor$ trials, the remaining
$M - K\lfloor M/K \rfloor$ go to groups picked at random, and the list is shuffled. Group $g$ is
therefore delivered $n_g$ times, with $|n_g - n_{g'}| \le 1$, and its **weight** in the session is
$w_g = n_g / M$. Everything random (the shuffle, and whatever a family draws) comes from one
stream seeded by the session's **seed**, so the whole session is fixed by its settings: the preview
is exactly what runs. The run limit and bias correction reorder the list during the session but
never change $n_g$.

By default every session draws a new seed, one of $2^{31} - 1$ values, so two sessions of a
subject repeat their trials only by a one-in-a-billion chance. The seed is saved with the session
(`StimulusSet.Seed`); typing it again repeats the session's trials exactly, draws included, with no
other data from that session needed.

### 3.3 Contingency

Each group has a **contingency** $p_g = P(\text{left pays} \mid g)$:

- $p_g = 1$ or $0$: a fixed contingency; that group always pays left, or always right.
- $0 < p_g < 1$: on each trial the paying side is drawn, left with probability $p_g$. A group with
  $p_g = \tfrac12$ pays either side and so rewards no particular choice.

Each family knows which side each of its groups is meant to pay (`FamilyPLeft`) and the session
uses that unless the operator types values of their own (`S.Task.GroupPLeft`; typed values are
kept only while the groups stay the same ones). **Reversing the contingency** replaces every
$p_g$ by $1 - p_g$.

---

## 4. The decision problem

### 4.1 Rule and categories

On trial $t$ the subject receives $x_t$ and chooses $c_t \in \{L, R\}$. With a fixed contingency
the groups fall into two **categories**, those paying left and those paying right, and the task is a
**rule** $d(x)$ from patterns to sides. The subject can reach 100% only by computing $d$ (or
something that agrees with it on every pattern delivered).

### 4.2 Evidence

Most families define their rule as a threshold on one number computed from the pattern, the
family's **evidence** $e(x)$, also called its decision variable:

| Family | Evidence $e$ | Pays left when |
|--------|-------------|----------------|
| mixture, A share | A share $\pi$ | $\pi > \pi^{*}$ (default $\tfrac12$) |
| mixture, A minus B | $\delta = \bar u_A - \bar u_B$ | $\delta > \delta^{*}$ (default 0) |
| mixture, A alone | $\bar u_A$ | $\bar u_A > \theta$ |
| mixture, B alone | $\bar u_B$ | $\bar u_B < \theta$ |
| sequence | $n_A - n_B$, A flashes minus B flashes | $n_A > n_B$ |
| pure channel, order, motifs, hand-drawn | none: the groups are categories | the group's own contingency |

The stimulus set stores it per pattern (`Evidence`, `EvidenceName`).

### 4.3 Psychometric function

The **psychometric function** is the probability of choosing left as a function of the evidence,

$$\psi(e) = P(c = L \mid e) .$$

The online plot shows it with one point per value of $e$ (or eight bins when $e$ varies
continuously). A standard parametric form, with lapse rates $\gamma$ (left) and $\lambda$ (right),
bias $\mu$ and slope $s$:

$$\psi(e) = \gamma + (1 - \gamma - \lambda)\,\frac{1}{1 + \exp\!\big(-(e - \mu)/s\big)} .$$

For evidence that falls as the left side becomes less likely (B's amount, under *B alone*), expect
$s < 0$.

### 4.4 Decision boundaries in the plane

A rule that depends only on the amounts divides the plane of section 2.4 by a **boundary**:

- **vertical**, $\bar u_A = \theta$: only A's amount matters (*A alone decides*);
- **horizontal**, $\bar u_B = \theta$: only B's amount matters (*B alone decides*);
- **diagonal**, $\bar u_A = \bar u_B$: the side depends on which amount is larger (A share against
  ½, or A minus B against 0);
- **a line through the origin**, $\bar u_B = \frac{1-\pi^{*}}{\pi^{*}} \bar u_A$: A's share against a
  boundary ratio $\pi^{*}$;
- **a line parallel to the diagonal**, $\bar u_B = \bar u_A - \delta^{*}$: A minus B against
  $\delta^{*}$.

More generally a linear boundary is $w_0 + w_A \bar u_A + w_B \bar u_B = 0$, and the direction of
the weight vector $(w_A, w_B)$ says how much each channel counts. The stimulus set records the
contingency's own boundary (`Boundary.Kind`; `Boundary.Value` for a vertical or horizontal one,
`Boundary.Slope` and `Boundary.Intercept` for a line $\bar u_B = \text{Slope}\cdot\bar u_A +
\text{Intercept}$), and the *Evidence* panel draws it behind the choices. Section 7.3 fits the
subject's own boundary.

---

## 5. Cues and shortcuts

### 5.1 Cues

A task is designed to make the subject use one property of the light, but a set of patterns may
also be solvable from a simpler one. Call any function of the pattern a **cue** $f(x)$. Five cues
are measured for every stimulus set:

| Cue | $f(x)$ | Reading it means attending to |
|-----|--------|-------------------------------|
| A's amount | $u_A$ | how long A is on, ignoring B |
| B's amount | $u_B$ | how long B is on, ignoring A |
| total light | $u_A + u_B$ | how much light there is, ignoring which channel |
| A's time course | the whole trace $q_A[1..N]$ | when A is on, ignoring B |
| B's time course | $q_B[1..N]$ | when B is on, ignoring A |

### 5.2 The single-cue ceiling

Suppose an observer sees only the value $v = f(x)$ of one cue, and knows the contingency. The best
it can do is to answer, for each value $v$, the side more often paid when the cue takes that value.
Its accuracy is the **single-cue ceiling**

$$\kappa_f = \sum_{v} \max\Big( \sum_{g:\, f(x_g) = v} w_g\, p_g,\;\; \sum_{g:\, f(x_g) = v} w_g\,(1 - p_g) \Big) .$$

An observer that reads the whole pattern can reach

$$\kappa^{*} = \sum_g w_g \max(p_g,\, 1 - p_g),$$

which is 1 for a fixed contingency. Then:

- $\kappa_f = \kappa^{*}$: the cue alone solves the task as well as anything can;
- $\kappa_f = \tfrac12$: the cue tells nothing about the side;
- in between: the cue helps, up to that accuracy.

A task **needs both channels** when every single-channel cue (A's amount, B's amount, A's time
course, B's time course) has $\kappa_f < \kappa^{*}$: no strategy that ignores a channel can reach
the top. A subject that performs above a cue's ceiling must be using more than that cue.

When every trial has its own pattern, each $x_t$ is unique and the value-by-value rule above would
simply memorise the trials. The ceilings of the amount cues are then computed for the best single
**threshold** instead (answer one side below a cut on the cue, the other above it), and the time
course ceilings are not computed.

The stimulus designer and the setup dialog print the ceilings in one line (*One cue alone could
score at most: …*); the data file stores them in `StimulusSet.Shortcuts` (`AAmount`, `BAmount`,
`TotalLight`, `ATimeCourse`, `BTimeCourse`, `AllLight` $=\kappa^{*}$, and `Method`, `'exact'` or
`'threshold'`). `lum.pattern.shortcuts(stimulusSet)` recomputes them from a stored set.

### 5.3 Three common shortcuts

1. **Amount.** If the categories differ in how long A is on, A's amount alone reveals the side.
2. **Complement.** If every bin is lit by exactly one channel ($q_B[n] = 1 - q_A[n]$, no dark and
   no overlap), then A's trace determines B's, and A's time course alone carries all the
   information: $\kappa_{q_A} = \kappa^{*}$. The same holds for amounts when every slot of a
   sequence is filled: $n_B = m - n_A$.
3. **Total light.** If the categories differ in $u_A + u_B$, how much light there is, whichever the
   channel, reveals the side.

### 5.4 Comparing amounts can never hide both amounts completely

For a rule that pays the side with the larger amount, some information always leaks into one
amount or the other. Take any set of patterns with $u_A \ne u_B$ in each, paying left exactly when
$u_A > u_B$. Let $a^{*}$ be the smallest A amount in the set and $b^{*}$ the smallest B amount.

- If $b^{*} < a^{*}$: every pattern with $u_B = b^{*}$ has $u_A \ge a^{*} > u_B$, so it pays
  left. The value $b^{*}$ of B's amount only ever pays left.
- If $b^{*} \ge a^{*}$: every pattern with $u_A = a^{*}$ has $u_B \ge b^{*} \ge a^{*} = u_A$,
  so (no ties) it pays right. The value $a^{*}$ of A's amount only ever pays right.

Either way one amount has a value that gives the side away, so $\kappa_{u_A} > \tfrac12$ or
$\kappa_{u_B} > \tfrac12$. The leak can be made small but not zero; the mixture family's *ladder*
(section 6.2) keeps it to the two extreme amounts, and roves the total so that the total light
tells nothing.

---

## 6. The families

Each family below gives: the question, the construction, the groups and contingency, the evidence
and boundary, the single-cue ceilings of its defaults, its settings, and why the defaults are what
they are. Every family's defaults run without a warning on the rig and in the emulator.

| Family (`Family`) | The subject tells | Groups | Needs both channels (defaults) |
|---|---|---|---|
| Pure channel (`pure`) | which channel is lit | A only, B only | no: identity is the task |
| Mixture (`mixture`) | how much of the mixture is A | mixture ratios, or differences, at roving totals; a grid of levels (controls) | yes (A share, A minus B); no, by design (A or B alone) |
| Sequence (`count`) | which channel flashes more often | pairs of counts | no with every slot filled (default); yes with empty slots |
| Order (`order`) | which channel comes first | A first, B first | no (simple); yes (guarded cycle) |
| Motifs (`motif`) | which word it is | one per word | amounts: yes; time courses: no, unless words use X or - |
| Hand-drawn pulses (`arbitrary`) | whatever you draw | one per group | — |

### 6.1 Pure channel (`pure`)

**Question.** Which channel is lit?

**Construction.** For a lit fraction $f$ and a channel $c$, channel $c$ is on for the first
$\mathrm{round}(fN)$ bins (at least one) and the other channel is off.

**Groups.** One per lit fraction and channel: with channels *A and B* and fractions
$f_1, \dots, f_J$, the groups are $(A, f_1), (B, f_1), (A, f_2), \dots$ — $2J$ groups.

**Contingency.** A pays left, B right. With only one channel (*A only* or *B only*) there is nothing
to discriminate, and every group pays either side ($p = \tfrac12$).

**Evidence and boundary.** No evidence (the groups are categories); the diagonal separates A-only
patterns (on the $\bar u_A$ axis) from B-only ones (on the $\bar u_B$ axis).

**Ceilings of the defaults** (A and B, $f = 1$): every cue that sees a channel is at 100% — the
presence of a channel is the task. Total light: 50%.

| Setting | Field | Default |
|---------|-------|---------|
| Channels | `PureChannels` | `'A and B'` |
| Lit fraction(s) | `PureFractions` | `1` |

**Why.** The simplest discrimination, and the first one to train. Several fractions make the
duration vary within each channel, so a subject cannot solve the task by timing alone.

### 6.2 Mixture (`mixture`)

**Question.** How much of the mixture is A?

Both channels are lit, each for an amount. What decides the side is the **decision rule**: a
relative measure of A against B (both channels needed), or one channel's amount alone (the controls).

**Placement.** Where in the window the amounts are lit (`MixtureLayout`):

- *spread* (the default): the window is cut into $C$ **cycles** (`MixtureCycles`, bins shared out as
  evenly as possible), each channel's amount is shared out over the cycles in proportion to their
  length, and in every cycle both channels start together. A cycle holds both channels for the
  smaller amount, the larger one alone, then dark. The mixture is present throughout the window,
  and the dark is a gap at the end of each cycle.
- *onset*: each channel in one stretch from stimulus onset, overlapping for the smaller amount;
- *centred*: each channel in one stretch centred in the window.

The amounts, and so the rule, the evidence and every single-cue ceiling of amounts, are the same
under every placement; only the time course differs. Why spread is the default: the totals rove
(below), so most pairs light far less than the window. In one stretch from onset, the last part of the
window is then always dark, and the light is over within the first 20% of the window at the lowest
total. Spread over cycles, every part of the window carries the same mixture. The cost is timers:
each cycle is one light segment per channel, so $2C$ global timers. The defaults use 5 cycles where
10 timers are left for light (the rig) and fewer where not (2 in the emulator), and no more cycles
than the smallest default amount (0.1 of the window) has bins: 3 in a 0.3 s window of 10 ms bins.
An amount with fewer bins than there are cycles is refused, naming the group; so are two groups that
come to the same light once rounded to bins (a 0.3 s window in 100 ms bins has only three bins, and
2:1 and 1:2 at the low totals both become one bin of each). Choosing a family (any family) avoids
both: when its defaults cannot be drawn in the bin set, the bin is made finer, 10 ms, then 5, 2 or
1 ms, until they can; a bin that works is kept, and none is made coarser.

#### Relative rules: A's share, or A minus B

Two measures of how much A there is relative to B:

- **A's share** of the light, its relative abundance in the mixture:
  $$\pi = \frac{u_A}{u_A + u_B} \in [0, 1] \qquad (\pi = 1 - \beta);$$
- the **difference** $\delta = \bar u_A - \bar u_B \in [-1, 1]$.

Each rule pays left when its measure is above a **boundary**, $\pi^{*}$ or $\delta^{*}$, right when
below, and either side on it. The share boundary is typed as a mixture ratio A:B (1:1 is
$\pi^{*} = \tfrac12$, 60:40 is $\pi^{*} = 0.6$), the difference boundary as a fraction of the window.

**Groups.** A list of values of the measure crossed with a list of **totals**
$s = \bar u_A + \bar u_B$, the total light, which roves:

$$\text{share: } (\bar u_A, \bar u_B) = \big(\pi s,\ (1-\pi)\,s\big), \qquad
\text{difference: } (\bar u_A, \bar u_B) = \Big(\frac{s + \delta}{2},\ \frac{s - \delta}{2}\Big).$$

Share values are typed as **mixture ratios** A:B (2:1 is $\pi = \tfrac23$; 80:20 is $\pi = 0.8$; 1:0 is
A alone). A combination that would light a channel for more than the whole window, or for less than
nothing, is refused, naming it. The contingency is decided on the amounts as delivered, in whole bins.

**Evidence and boundary.** The measure itself ($\pi$, or $\delta$ as a fraction of the window). In the
plane of amounts the share boundary is a line through the origin, a mixture ratio,

$$\bar u_B = \frac{1 - \pi^{*}}{\pi^{*}}\,\bar u_A ,$$

and the difference boundary a line parallel to the diagonal, $\bar u_B = \bar u_A - \delta^{*}$. At
$\pi^{*} = \tfrac12$ and $\delta^{*} = 0$ both are the diagonal, and the two rules pay every pattern the
same side; they part as soon as the boundary moves. (`Boundary.Kind` is `'diagonal'`, or `'line'` with
`Slope` and `Intercept`.)

**Why the total roves.** At one fixed total, $\bar u_B = s - \bar u_A$: A's amount alone gives the
share and the difference away (the complement shortcut, section 5.3). Roving the total breaks that,
and one rove does it best, a **ladder**:

- share rule with the ratios $\pi$ and $1-\pi$: totals that grow by the factor $r = \pi/(1-\pi)$ (for
  2:1 and 1:2, totals that double), so that $\pi s_k = (1-\pi)\,s_{k+1}$;
- difference rule with $\pm\delta$: totals that grow by $2\delta$ (0.3 0.5 0.7 0.9 for $\pm 0.1$).

Then every amount is the larger in one group and the smaller in another, except the lowest and
highest, and each total occurs once on each side. With $n$ distinct amounts,

$$\kappa_{u_A} = \kappa_{u_B} = \frac{n}{2(n-1)}, \qquad \kappa_{u_A + u_B} = \tfrac12 ,$$

close to the least a comparison can leak (section 5.4 shows it cannot be nothing): 67% with 4
amounts, 62.5% with 5, 60% with 6. With a
moved boundary, or a psychometric set of ratios, no one rove balances every amount; the single-cue
line says how much is left, and a wider rove (more totals over a larger range) lowers it.

**Share or difference?** By Weber's law the discriminability of two amounts depends on their ratio.
In the share design every pair has the same ratio at every total, so all trials are equally hard. In
the difference design the ratio falls as the total rises (0.2 : 0.1 is 2:1, 0.5 : 0.4 is 1.25:1), so
trials get harder with the total if the subject reads ratios, and stay equally hard if it reads
differences. Accuracy against the total, in either design, says which of the two it uses. A moved
boundary asks a relative question that "which is larger?" cannot answer: is A more than 60% of the
mixture?

**New amounts every trial.** Each trial draws its measure evenly within the range of the listed
values, on the side of the boundary its group needs, and its total within the range of the listed
totals (evenly on a log scale for the share, evenly for the difference). A draw that would overrun
the window, or that lands on the other side once rounded to bins, is drawn again. The groups are the
two sides (*More A*, *More B*, or *A share above 60%*…), and the psychometric plot bins the evidence.

#### Rules *A alone* and *B alone* (controls)

**Groups.** A list of **amount levels** $\ell_1 < \dots < \ell_n$ (fractions of the window); every
level of A with every level of B: $n^2$ groups. Levels that come to the same number of bins are
refused.

**Contingency.** For *A alone*, the lower half of the levels of A pays right and the upper half left,
whatever B does; with an odd $n$ the middle level pays either side. *B alone* is the same for B, with
more B paying right. So a subject trained on a relative rule is rewarded for the same direction
(more A left, more B right) by either control.

**Evidence and boundary.** The deciding channel's fraction; a vertical (*A alone*) or horizontal
(*B alone*) boundary at $\theta$, halfway between the two middle levels (or at the middle level).

**Ceilings.** The deciding channel: 100%. The other channel: exactly 50% (every one of its levels
meets every level of the deciding channel). Total light: above 50%, since the total rises with the
deciding amount (75% for the default levels).

**Ceilings of the defaults.** A share, 2:1 and 1:2 at totals 0.3 0.6 1.2: A's amount 67%, B's amount
67%, total light 50%, A's and B's time courses 67%. A minus B, $\pm 0.1$ at totals 0.3 0.5 0.7 0.9:
62.5%, 62.5%, 50%. Drawn anew every trial, and read against a threshold: about two in three for each
amount, a little above 50% for total light.

| Setting | Field | Default |
|---------|-------|---------|
| Decision rule | `MixtureRule` | `'share'` (`'difference'`, `'A alone'`, `'B alone'`) |
| Mixture ratios, A:B | `MixtureRatios` | 2:1 1:2 |
| Sides change at, A:B | `MixtureShareBoundary` | 1:1 |
| Total light (share) | `MixtureShareTotals` | 0.3 0.6 1.2 |
| A minus B | `MixtureDifferences` | 0.1 −0.1 |
| Sides change at A minus B | `MixtureDifferenceBoundary` | 0 |
| Total light (difference) | `MixtureDifferenceTotals` | 0.3 0.5 0.7 0.9 |
| Amount levels (controls) | `MixtureLevels` | 0.1 0.2 0.4 0.8 |
| Placement | `MixtureLayout` | `'spread'` (`'onset'`, `'centred'`) |
| Cycles (spread) | `MixtureCycles` | 5 (fewer where the timers or bins are short) |
| Every trial | `Continuous` | off |

**Why.** Two mixture ratios, 2:1 and 1:2, at totals that double: every trial is as hard as every
other, neither amount alone does better than 67%, and the total light tells nothing. A minus B has
defaults with the same properties, to run beside it. Running the same range of amounts with *A alone*
or *B alone* is the control: the same kind of light, with a rule that one channel can solve.

### 6.3 Sequence (`count`)

**Question.** Which channel flashes more often?

**Construction.** The window is cut into $m$ **slots** (the bins shared out as evenly as possible).
Slot $j$ holds one flash of A, one flash of B, or nothing. A flash starts with its slot and lasts a
fraction $\phi$ of it (at least one bin, and at least one bin short of the slot when $\phi < 1$,
so that two flashes of one channel in neighbouring slots stay two flashes).

**Groups.** One per pair of counts $(n_A, n_B)$, $n_A + n_B \le m$ (typed as `A:B`). On each trial
the $n_A$ A flashes, $n_B$ B flashes and $m - n_A - n_B$ empty slots are put in a uniformly random
order, so the order carries no information; only the counts do. (Untick *a new order of the flashes*
to give each group one fixed order instead.)

**Contingency.** $p = 1$ when $n_A > n_B$, $0$ when $n_A < n_B$, $\tfrac12$ when equal.

**Evidence and boundary.** $e = n_A - n_B$; the diagonal (with equal flash lengths
$u_A \propto n_A$ and $u_B \propto n_B$).

**Every slot filled** ($n_A + n_B = m$): then $n_B = m - n_A$, the complement shortcut of section
5.3. Counting A alone (or B alone) solves the task: $\kappa_{u_A} = \kappa_{u_B} = 1$.
**Some slots empty**: the counts can rove like the mixture ladder. The pairs
$(k+1, k)$ and $(k, k+1)$ for $k = 0 \dots \lfloor (m-1)/2 \rfloor$ (*both channels needed* in the
designer: 1:0 0:1 2:1 1:2 3:2 2:3 for five slots) leave each count at
$\kappa = n/(2(n-1))$ with $n = \lfloor (m-1)/2 \rfloor + 2$ count values (67% for five slots) and
the total at 50%.

**Ceilings of the defaults** (every slot filled, new order each trial, read against a threshold):
A's amount 100%, B's amount 100%, total light 50%.

| Setting | Field | Default |
|---------|-------|---------|
| Slots in the window | `CountSlots` | 5 (3 on a machine with fewer than 5 timers left for light) |
| Counts, A:B | `CountPairs` | 5:0 4:1 3:2 2:3 1:4 0:5 |
| Flash length (of a slot) | `CountFill` | 0.5 |
| Every trial | `Continuous` | on: a new order of the flashes |

**Why.** A fixed-length sequence with every slot filled, and every split of it from all A to all B:
the easiest and hardest counts in one session, and a psychometric curve over $n_A - n_B$. Because
the order is drawn anew every trial, a subject cannot memorise sequences; it has to integrate the
flashes over the window. Switch to empty slots to make both counts matter.

**Cost.** Each flash is a segment: $n_A + n_B$ timers.

### 6.4 Order (`order`)

**Question.** Which channel comes first?

The window holds $C$ **turns**, each of width $W \approx N/C$ bins.

#### Simple design

A turn is: the first channel alone for $(1-o)/2$ of it, both together for $o$, then the second
channel alone for $(1-o)/2$ (fractions of the turn, $0 \le o < 1$). The groups are *A first* and
*B first*, the mirror images of each other; A first pays left.

Both channels are on for the same time, so every amount cue is at 50%. But A's time course alone
tells the side (A early or A late): $\kappa_{q_A} = \kappa_{q_B} = 1$.

#### Guarded cycle

A turn is $[\,\text{lead alone } \pi\,][\,\text{both } g_s\,][\,\text{other alone } \pi\,][\,\text{both } g_L\,]$ with
a short overlap $g_s$, a long overlap $g_L > g_s$, and $\pi = (1 - g_s - g_L)/2$. The groups are
*A leads* and *B leads*. Each channel is on in one stretch of $\pi + g_s + g_L$ per turn, and the
two stretches overlap twice: briefly where the leading channel hands over ($g_s$), for longer where
the other hands back ($g_L$). What separates the groups is which handover is the short one.

With **a random phase every trial** (the default for this design), the whole pattern is shifted
circularly by a uniformly random number of bins within a turn. Each channel on its own is then a
stretch of fixed length at a uniformly random place in both groups: its time course, its amount
and the total light are all distributed identically whichever channel leads. Only the timing of
one channel against the other tells the side; the pattern is never dark; and the amount ceilings
are exactly 50%.

**Ceilings of the defaults.** Simple: amounts 50%, total 50%, time courses 100%. Guarded with a
random phase: amounts 50%, total 50% (time courses not computed, but identically distributed by
construction).

| Setting | Field | Default |
|---------|-------|---------|
| Design | `OrderDesign` | `'simple'` (`'guarded'`) |
| Turns in the window | `OrderCycles` | 1 |
| Overlap (simple) | `OrderOverlap` | 0.2 |
| Short, long overlap (guarded) | `OrderShortOverlap`, `OrderLongOverlap` | 0.1, 0.3 |
| Every trial | `Continuous` | off (on is the guarded cycle's random phase) |

**Why.** One turn, the channels meeting in an overlap: the plainest question about order. The
guarded cycle is the version in which order is the only thing that differs.

**Cost.** Simple, one turn: 2 timers. Guarded with a random phase: up to 4 for one turn.

### 6.5 Motifs (`motif`)

**Question.** Which word is it?

**Construction.** A **word** is a string of $L$ letters from the alphabet
$\{\mathtt{A}, \mathtt{B}, \mathtt{X}, \mathtt{-}\}$: A lights channel A, B lights B, X lights both,
and - is dark. The window is cut into $L$ slots and letter $j$ is one flash in slot $j$, lasting a
fraction $\phi$ of it. Every word has the same length.

**Groups and contingency.** One group per word; the words listed for the left port pay left, those
for the right port pay right. A word listed for both sides is refused (identical light, different
sides).

**Evidence and boundary.** None: the mapping from words to sides is the task.

**What the default split rules out.** Take all eight words of three letters from {A, B}. Each word
is lit in every slot by one channel, so the complement shortcut applies to time courses: A's time
course identifies the word ($\kappa_{q_A} = 1$). The design question is which simpler features of a
word could give the side away. For the default split

$$\text{left} = \{\mathtt{AAA}, \mathtt{AAB}, \mathtt{ABB}, \mathtt{BAB}\}, \qquad
\text{right} = \{\mathtt{ABA}, \mathtt{BAA}, \mathtt{BBA}, \mathtt{BBB}\}$$

the best accuracy of each feature is:

| Feature of the word | Best accuracy |
|---------------------|:---:|
| number of A (= A's amount) | 75% |
| the letter in position 1, 2 or 3 | 75% each |
| whether letters 1 and 2 repeat; letters 2 and 3; first and last | 50% |
| number of changes between letters | 50% |
| which letter is in the majority | 50% |
| the whole word | 100% |

No split of the eight words can bring the count of A below 75%: AAA and BBB are the only words
with three and with no A, so their side is always given away, and the six others (three with one A,
three with two) leave at least two of three on the majority side of each count. The side can be
known for certain only from the word as a whole: the subject has to learn each word, not a rule.
For a rule instead, use a structural split: $\{\mathtt{AAB}, \mathtt{BBA}\}$ against
$\{\mathtt{ABA}, \mathtt{BAB}\}$ has the count and every position at 50%, but *the first two letters
repeat* at 100% — an abstract rule over any letters. To make a time course ambiguous, use X and -
letters, so that A's trace no longer determines B's.

**Ceilings of the defaults:** A's amount 75%, B's amount 75%, total light 50%, A's and B's time
courses 100%.

| Setting | Field | Default |
|---------|-------|---------|
| Words paying left | `MotifLeftWords` | `'AAA AAB ABB BAB'` |
| Words paying right | `MotifRightWords` | `'ABA BAA BBA BBB'` |
| Flash length (of a letter) | `MotifFill` | 0.5 |

**Cost.** One segment per lit letter (two for X).

### 6.6 Hand-drawn pulses (`arbitrary`)

Rows of $[g, c, t_{\mathrm{on}}, t_{\mathrm{off}}]$: in group $g$, channel $c$ (1 = A, 2 = B) is on
in every bin that overlaps $[t_{\mathrm{on}}, t_{\mathrm{off}})$ (seconds from stimulus onset).
There is no natural contingency, so the default one is: one group pays either side; two groups pay
left then right; $K$ groups sweep evenly from left ($p_1 = 1$) to right ($p_K = 0$). Type your own
P(left) in the group table. The default draws A in the first half of the window for group 1 and B
for group 2.

### 6.7 Offsets, in every family

A channel can be delayed by $\delta$ seconds, one value for every group or one per group:
$q'_A[n] = q_A[n - \mathrm{round}(\delta/\Delta)]$. *Circular* wraps light pushed past the end round
to the start, so the channel keeps its amount; *linear* drops it.

---

## 7. From the data file to the analysis

### 7.1 What is where

`SessionData.Session.StimulusSet` (one per session):

| Field | Meaning |
|-------|---------|
| `Family`, `GroupLabels`, `nGroups` | the family and its groups |
| `GroupPLeft` | $p_g$ as run (after any reversal); `BasePLeft` before it; `FamilyPLeft` the family's; `PLeftFromFamily`, `Reversed` |
| `PatternGroup`, `PatternPLeft` | each pattern's group and contingency |
| `Evidence`, `EvidenceName` | $e$ per pattern, and what it is |
| `Boundary` | `Kind` (`'diagonal'`, `'vertical'`, `'horizontal'`, `'line'`, `'none'`), `Value` ($\theta$), and `Slope`, `Intercept` of a line |
| `Descriptors` | $u_A, u_B, u_{AB}, u_0, \beta, k_A, k_B$ per pattern (section 2.3) |
| `Shortcuts` | the single-cue ceilings (section 5.2) |
| `Segments`, `SegmentStart` | every pattern's light, `lum.pattern.patternAt(stimulusSet, k)` |

Per trial: `SessionData.PatternIndex` (which pattern), `StimulusGroup`, `CorrectSide`, `Choice`
(1 left, 2 right, NaN none), `Correct`, `OptoOn` (1 when the light was delivered).

### 7.2 Per-trial quantities

```matlab
stimulusSet = SessionData.Session.StimulusSet;
k = SessionData.PatternIndex;                                      % pattern of each trial
uA = stimulusSet.Descriptors.AOn(k) / stimulusSet.Duration;        % fraction of the window A was lit
uB = stimulusSet.Descriptors.BOn(k) / stimulusSet.Duration;
e = stimulusSet.Evidence(k);                                       % the family's evidence (NaN if none)
choseLeft = SessionData.Choice == 1;
use = ~isnan(SessionData.Choice) & SessionData.OptoOn == 1;

% Psychometric points: P(chose left) at each value of the evidence
[values, ~, which] = unique(e(use));
pLeft = accumarray(which(:), double(choseLeft(use))', [], @mean);
nTrials = accumarray(which(:), 1);
```

### 7.3 Which channel does the subject weigh? Decision weights

Fit $P(c = L) = 1 / \big(1 + \exp(-(w_0 + w_A \bar u_A + w_B \bar u_B))\big)$ to the choices. The
angle

$$\alpha = \operatorname{atan2}(-w_B,\; w_A)$$

is 0° when only A counts (a vertical boundary), 90° when only B counts (horizontal), and 45° when
both count equally with opposite signs (the diagonal: more A left, more B right). With a moved share
boundary $\pi^{*}$, a subject that has learnt it weighs the channels as the boundary line does:
$\alpha = \arctan\big(\pi^{*}/(1-\pi^{*})\big)$, 56° for $\pi^{*} = 0.6$ (a boundary through the
origin also needs $w_0 \approx 0$).
Base MATLAB, no toolbox (a small ridge keeps the weights finite when the choices separate
perfectly):

```matlab
X = [ones(nnz(use), 1), uA(use)', uB(use)'];
y = double(choseLeft(use))';
w = zeros(3, 1);
ridge = 1e-3;
for iteration = 1:100
    p = 1 ./ (1 + exp(-X * w));
    gradient = X' * (y - p) - ridge * w;
    hessian = X' * (X .* (p .* (1 - p))) + ridge * eye(3);
    step = hessian \ gradient;
    w = w + step;
    if max(abs(step)) < 1e-9
        break
    end
end
angle = atan2d(-w(3), w(2));   % 0: A alone, 45: both equally, 90: B alone
```

Compare the angle across sessions: a subject trained on A's share against 1:1 should move towards
45°; on the *A alone* control, towards 0°.

### 7.4 Is the subject beating a shortcut?

If the subject's accuracy is reliably above a cue's ceiling $\kappa_f$, it uses more than that cue.
With $n$ trials of which $c$ were correct, a one-sided binomial test against $\kappa_f$ asks
whether $c$ is unusually high for an observer that reads only $f$:

```matlab
kappa = stimulusSet.Shortcuts.AAmount;         % e.g. A's amount alone
n = nnz(use);
c = sum(SessionData.Correct(use) == 1);
j = c:n;                                        % P(at least c correct), in logs
logTerms = gammaln(n + 1) - gammaln(j + 1) - gammaln(n - j + 1) ...
           + j * log(kappa) + (n - j) * log(1 - kappa);
pValue = sum(exp(logTerms));
```

(With $\kappa_f = 1$ the cue alone solves the task and there is nothing to beat.)

### 7.5 Where in the sequence? A temporal kernel

In the sequence family each trial's flashes are in a random order, so the choice can be regressed on
what was in each slot: $+1$ for A, $-1$ for B, $0$ for empty. The weights over slots are the
subject's temporal kernel (flat: it weighs every slot equally; falling: early flashes count more).
The slot of each flash is recovered from the segments:

```matlab
m = SessionData.Session.Settings.Stimulus.Generator.CountSlots;
slotLength = stimulusSet.Duration / m;
slots = zeros(numel(k), m);
for t = 1:numel(k)
    segments = lum.pattern.patternAt(stimulusSet, k(t)).Segments;   % [channel onset duration]
    slot = floor(segments(:, 2) / slotLength + 1e-9) + 1;
    slots(t, slot) = 3 - 2 * segments(:, 1);                % A: +1, B: -1
end
% Regress choseLeft on slots(use, :) as in 7.3, with m weights instead of two.
```

---

## 8. What the machine allows

Each segment is one of the state machine's global timers, and the timer budget is checked before a
session starts (`lum.timerBudget`): the rig's state machine has 16 timers and the emulator's 5; the
hold window always takes one; grace shaping and stimulus components timed within the window take
more. A pattern with more segments than the budget is refused, naming its group. The families'
defaults stay within 4 segments, except the sequence family on the rig (5 flashes), whose default
drops to 3 slots when fewer than 5 timers are left. Segment edges fall on the 100 µs cycle of the
state machine.

---

## 9. Choosing a design

| You want the subject to | Use | Settings | Cues left open |
|---|---|---|---|
| tell A from B | Pure channel | defaults | none needed: identity is the task |
| weigh A against B | Mixture, A share | two ratios (2:1, 1:2), totals growing by their ratio | each amount $n/(2(n-1))$ |
| judge relative abundance against a set point | Mixture, A share | boundary moved (e.g. 60:40), ratios either side of it | shown by the single-cue line; widen the rove to lower them |
| tell whether it reads ratios or differences | Mixture, A share and A minus B | each at its defaults; accuracy against the total | each amount about $n/(2(n-1))$ |
| show it can use one channel (control) | Mixture, A alone or B alone | the same range of amounts | the deciding channel |
| sweep difficulty | Mixture, A share | several ratios (80:20 60:40 40:60 20:80), or amounts drawn every trial | as the single-cue line shows |
| integrate discrete events over time | Sequence | every slot filled | each count alone (100%) |
| integrate events from both channels | Sequence | *both channels needed* counts | each count $n/(2(n-1))$ |
| tell which comes first | Order, simple | defaults | each time course (100%) |
| tell order from relative timing only | Order, guarded cycle, random phase | defaults of the design | none of the five cues |
| learn arbitrary patterns by heart | Motifs | default split | time courses; count and positions 75% |
| learn an abstract rule | Motifs | e.g. AAB BBA against ABA BAB | the rule itself (repeat or change) |
