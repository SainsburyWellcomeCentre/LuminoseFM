# How long mice take to learn the task

How many days and trials published mice needed to learn an odour discrimination, or a
discrimination of optogenetic input to the olfactory bulb. From these numbers, an estimate for
LuminoseFM's Training stage (pure channel: A pays left, B pays right). Written 2026-09-29, after
LUMS0014's fifth session. The last section, [Light intensity and tissue
heating](#light-intensity-and-tissue-heating) (2026-10-03), works out how much light a trial
delivers, what that does to the temperature of the brain, how it compares with the light that made
mice perceive OSN-ChR2 activation, and what the PulsePal carrier can change.

Every number below comes from the linked peer-reviewed paper. Each was checked against the paper's
text (full text or abstract) and its DOI against Crossref. The [estimate](#estimate-for-luminosefm)
is ours, worked out from those numbers.

## What the papers report

### Odour discrimination

| Paper | Task | Pretraining | Learning the discrimination | Cost of an error |
|---|---|---|---|---|
| [Erskine et al. 2019, PLOS ONE](https://doi.org/10.1371/journal.pone.0211571) (AutonoMouse) | Home cage, self-initiated go/no-go | 7 days of automated habituation and pretraining | First odour pair: 1–2 days, 54–398 trials to 80% over 20 trials. Second pair: 20–246 trials. 150–560 trials a day (mean 333) | Timeout ITI of 8–12 s after a lick on S− (4 s otherwise) |
| [Caglayan et al. 2021, Front. Behav. Neurosci.](https://doi.org/10.3389/fnbeh.2021.684936) | Home cage with a sorter, go/no-go | 3 days (4 days for one mouse) | Four odour pairs and their reversals in 6–17 days (median 11). Criterion 85% over 20 trials. Mice usually moved to the next stage within a day. 149–224 trials a day | 30 s timeout after a false alarm |
| [Abraham et al. 2012, PLoS ONE](https://doi.org/10.1371/journal.pone.0051789) | Head-restrained go/no-go, compared with freely moving | Lick shaping: "most animals learned this task in 2–3 days (4–6 sessions of 30 min each)" | Simple and complex odours learned "in a few hundred trials with high accuracy". Accuracy was similar in head-restrained and freely moving mice | – |
| [Berners-Lee et al. 2023, PLOS Biol.](https://doi.org/10.1371/journal.pbio.3002086) | Head-fixed 2-AFC (lick left or right), target mixture vs other mixtures | Habituation, then shaping, then blocked trials, then about 2 days of forced trials (an incorrect trial's stimulus comes again) | "Mice learned the task within a few days" | Early phases: a lick at the correct port after an incorrect first lick still paid, but the trial counted as incorrect. That allowance was removed once the mouse was above 70% on both sides |

### Optogenetic input to the olfactory bulb

| Paper | Task | Pretraining | Learning the light discrimination | Cost of an error |
|---|---|---|---|---|
| [Rebello et al. 2014, PLoS Biol.](https://doi.org/10.1371/journal.pbio.1002021) | Head-fixed go/no-go, Thy1-ChR2 | Odour go/no-go: "1–3 d to acquire the odor discrimination task" (>80%) | Two light patterns with the same spots and different timing: ">75% accuracy within 7 d on average" (n = 4). Criterion 80% over one 20-trial block, or 75% over two | A drop of 1 M NaCl for a lick on S− |
| [Li et al. 2014, J. Neurosci.](https://doi.org/10.1523/JNEUROSCI.3382-14.2014) | Freely moving go/no-go, OMP-hChR2V | Odour pair first. Then the odours were replaced by light for 100 ms (S+) against no light (S−) | Then 100 ms against a new duration: "at least two blocks >80% correct within one or two sessions". Blocks of 20 trials | Go/no-go (no reward on S−) |
| [Chong et al. 2020, Science](https://doi.org/10.1126/science.aba2357) ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8237706/)) | Head-fixed 2-AFC, patterned light on glomeruli | – | Shaped on one target pattern against one non-target to 0.8, then moved to several non-targets. The text gives no days or trial counts | Not stated. Only 70% of trials were rewarded |
| [Smear et al. 2011, Nature](https://doi.org/10.1038/nature10521) | Optogenetic OSN activation timed to the sniff | – | Mice reported the sniff phase of the light and told apart inputs shifted by 10 ms. The abstract gives no training duration, and we could not read the full text | – |

### A large 2-AFC benchmark (vision, not olfaction)

[International Brain Laboratory 2021, eLife](https://doi.org/10.7554/eLife.63711)
([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8137147/)): 140 head-fixed mice in seven labs,
choosing left or right with a wheel.

- **Days:** training took 18.4 ± 13.0 days (s.d.). The fastest mouse took 3 days and the slowest 59.
- **Trials:** 10.8 ± 8.6 thousand trials (range 1–43 thousand). Reaching 80% on easy trials took
  about 7.4 thousand trials on average.
- **Cost of an error:** a noise burst and a 2 s timeout. Errors on easy trials were more likely to be
  followed by a repeat of the same trial.
- **Early sessions:** "At first, performance hovered around or below 50%" because of response
  biases, among other causes.

## What these studies have in common

- **Procedure first.** Before any discrimination, pretraining took 2–7 days (Abraham, Caglayan,
  Erskine, Berners-Lee).
- **Odour pairs are fast once the procedure is known.** Go/no-go mice learned a pair in tens to a
  few hundred trials, within 1–3 days (Erskine, Abraham, Rebello). The head-fixed 2-AFC took "a few
  days" (Berners-Lee).
- **Light was learned after odours.** Both behavioural studies of optogenetic OB input with
  learning times (Rebello, Li) trained the task with odours first. They then swapped in light, and
  Li started with light against no light. Learning light patterns after odours took about a week
  (Rebello).
- **In every study that states it, an error cost something.** The costs were a timeout (2–30 s), punishment (NaCl,
  noise) or no reward. Berners-Lee let a mouse correct itself only in the early phases, and still
  scored the first lick. IBL repeated trials after errors, but kept the noise and timeout.
- **We found no study where freely moving mice learned a 2-AFC between two optogenetic OB patterns
  without odour pretraining.** That is LuminoseFM's case, so the estimate below extrapolates.

## LUMS0014 so far

| Date | Stage | Light | Trials | Correct | Chose left, A trials / B trials |
|---|---|---|---|---|---|
| 2026-09-25 | Habituation | off | 98 | – | 29% / 45% |
| 2026-09-26 | Habituation | off | 140 | – | 46% / 29% |
| 2026-09-27 | Habituation | off | 307 | – | 52% / 49% |
| 2026-09-28 | Training | on, window 0.5 s | 333 | 41% | 73% / 78% |
| 2026-09-29 | Training | on, window 0.3 s | 372 | 37% | 87% / 86% |
| 2026-09-30 | Training, a wrong choice ends the trial | on, window 0.3 s | 506 | 52% | 60% / 56% |
| 2026-10-01 | Training, a wrong choice ends the trial | on, window 0.3 s | 559 | 44% | 54% / 64% |
| 2026-10-02 | Training, a wrong choice ends the trial | on, window 0.3 s | 733 | 47% | 58% / 62% |
| 2026-10-03 | Training, a wrong choice ends the trial | on, window 0.3 s | 471 | 49% | 58% / 59% |

The procedure took 3 days, in line with the 2–7 days of pretraining above. LUMS0014 now does 350
to 730 trials a session and completes nearly every hold. There is no sign yet that the light
controls its choices: it goes left as often on A trials as on B trials.

Up to 2026-09-29 errors cost almost nothing, unlike in the studies above. Punishment was off
(`S.GUI.PunishCondition` = None), so after a wrong choice the mouse could go to the other port and
still be paid. On 2026-09-29 it was rewarded on 345 of 372 trials while choosing correctly 37% of
the time.

**2026-09-30 is day 1 of the estimate below.** `PunishCondition` is *Incorrect choice* with a
timeout of 0 s: a wrong choice ends the trial with no reward, and the next trial starts after the
0.25 s ITI. The cost of an error is the missed reward alone. The side bias of the two sessions
before went (left on 58% of choices, from 86%), and the choices followed the last trial instead:
the mouse chose the side that had paid on the trial before on 65% of trials (it stayed after 59%
of rewards and changed side after 71% of errors). The paying side repeats on about half of the
trials, so that rule earns 52%. In a logistic fit of the choice, the side that paid last has a
weight of 1.35 ± 0.20 and the stimulus 0.07 ± 0.19; P(left | A) − P(left | B) is 0.04 ± 0.04.

On 2026-10-01 (day 2) the mouse went on following the last trial: it chose the side that had paid
on the trial before on 66% of trials, mostly by changing side after an error (75% of errors, against
54% staying after a reward). The paying side repeated on only 46% of trials (bias correction pushed
towards the right on 409 of 559, against a left bias of 59%), so that rule earns 46%, and the
session scored 44%. The first 300 trials showed no split (P(left | A) 59%, P(left | B) 57%). In
trials 301–559 the mouse chose left on 48% of A trials and 72% of B trials, against the
contingency; with the last trial's choice and reward, the paying side two trials back, the bias
correction's target and the last five choices in the fit, the stimulus weight there is −0.47 ±
0.15 (a permutation of the groups gives p = 0.002), and −0.15 ± 0.10 over the whole session. The
split into halves was chosen after seeing the session, so this is a hint to look for in the next
sessions rather than a finding: the first sign that the light affects the choice at all, in the
wrong direction.

On 2026-10-02 (day 3) the hint did not come back. Fitted the same way, the stimulus weight was
+0.16 ± 0.11 in trials 301–733 (p = 0.12) and +0.06 ± 0.08 over the session; P(left | A) was 58%
and P(left | B) 62%, with no split in any block of 100 trials. Over the three punished sessions the
six half-session weights run from −0.49 to +0.35, in both directions, so they read as noise around
zero. The mouse leaned on the last trial less (it chose the side that had paid last on 57% of
trials; changed side after 63% of errors and stayed after 50% of rewards) and kept its left bias
(60% of choices, against bias correction aiming right on 523 of 733 trials). Reaction times, centre
hold times and early withdrawals did not differ between A and B trials either. Most early withdrawals
came 175–300 ms after stimulus onset, just short of the 0.3 s hold, as on the two days before.

On 2026-10-03 (day 4) there was again no split: P(left | A) 58%, P(left | B) 59%, the stimulus
weight −0.01 ± 0.10 over the session (p = 0.95), and no block of 100 trials past ±0.10. The four
punished sessions (2,269 trials) give whole-session weights of +0.18, −0.15, +0.06 and −0.01. The
mouse chose the side that had paid last on 57% of trials (stayed after 46% of rewards, changed
side after 66% of errors) and kept its left bias (59%; bias correction aimed right on 353 of 471
trials). Early withdrawals rose to 0.96 a trial (0.66–0.76 on the three days before), and holds
completed on the first attempt fell from 84% of the first 50 trials to 33–48% after trial 300;
withdrawals came a median 231 ms after stimulus onset (quartiles 185–262 ms). The light was 8
mW/mm² on each channel, as on every training day (A 253 mA of the 1000 mA limit, orange cable, up
to 21.9 mW/mm²; B 496 mA, blue cable, up to 12.9 mW/mm²), delivered as six 5 ms pulses at 20 Hz.

## Estimate for LuminoseFM

Scaled from the numbers above at about 350 trials a session, one session a day. **The estimate
starts on the first day incorrect choices cost something:** `PunishCondition` set to *Incorrect
choice*, as in the studies above. Sessions with retries are not counted, because no study measured
learning under them.

| Scenario | Based on | Trials | Sessions |
|---|---|---|---|
| Fast | Light patterns learned after odour pretraining, about a week (Rebello) | ~2,500 | ~7 |
| Typical | 80% on easy trials in a 2-AFC (IBL mean: ~7.4 thousand trials) up to full training (10.8 thousand) | 7,000–11,000 | 20–30 |
| Slow | IBL's slowest mouse (43 thousand trials, 59 days) | ~40,000 | 60+ |

**Estimate:** **3–4 weeks** of punished training (7,000–11,000 trials) to reach about 80% correct on
A vs B. The first split between the groups (more left choices on A trials than on B trials) could
appear within **1–2 weeks**. This assumes A and B are perceptibly different. The fast row would
likely need odour pretraining, as both optogenetic studies used. The typical row applies a visual
2-AFC's pace to a light-only olfactory one. Neither assumption has been tested for this preparation.

**How to read the sessions.** Early 2-AFC performance sits around or below 50% because of side
biases (IBL). Overall % correct is therefore a slow first sign. Watch P(left | A) − P(left | B) in
the session log's *By group* line (the psychometric panel shows the same).

**When to question the stimulus.** If there is still no split between the groups by about 7,000
punished trials (IBL's mean to 80% on easy trials, about 3 weeks here), keep training only after a
check that the mouse can perceive the light. Two options follow the papers:

- **Light against no light** first, as Li et al. did.
- **Odour pretraining**, then swap in light (Rebello, Li), if the air line can carry an odour.

Update this file with the session at which LUMS0014, and later animals, first show a group split
and first reach 80%. Those numbers will replace the extrapolation.

## Light intensity and tissue heating

Written 2026-10-03, when raising the light was first considered for LUMS0014.

### What a trial delivers

The session sets **irradiance**, the power per area at the fibre tips (`S.Doric.IrradiancemWmm2`).
Heating depends on the **power**: irradiance times the area of the cable's fibre cores. A 4-to-19
cable (orange, blue, green) has 5 fibres of 100 µm core, so its area is 5 × π × (0.05 mm)² =
0.0393 mm², and 8 mW/mm² leaves the cable as 8 × 0.0393 ≈ 0.31 mW.

That power is on only during a carrier pulse. PulsePal fills the 0.3 s window with 5 ms pulses at
20 Hz (`S.Light.Carrier`), so the light is on 10% of the window: six pulses, 30 ms of light a trial.
A pure-channel trial lights one channel, A or B, and only while the mouse holds; an early
withdrawal ends it. On 2026-10-03 a trial started every 9.4 s (471 trials in 74 min).

| Irradiance (mW/mm²) | Where it comes from | Power during a pulse | Average over the 0.3 s window | Average over the session |
|---|---|---|---|---|
| 8 | every training session up to 2026-10-03 (A 253 mA, B 496 mA) | 0.31 mW | 0.031 mW | about 1.0 µW |
| 12 | a step below the most A and B can share (A 409 mA, B 893 mA) | 0.47 mW | 0.047 mW | about 1.5 µW |
| 12.9 | the most A and B can share (A 444 mA, B 999 mA: the blue cable at the 1000 mA limit) | 0.51 mW | 0.051 mW | about 1.6 µW |
| 21.9 | A (orange cable) at the 1000 mA limit | 0.86 mW | 0.086 mW | about 2.7 µW |

The limits come from the LED calibrations of 2026-09-24 (`calibration/`), measured at the fibre
tips. At the same current, B with the blue cable gives about 59% of A's irradiance with the orange
one (channel B gives about 58% of A's on every cable), so B sets the most A and B can share.

### What the papers measured

| Paper | Light | Heating |
|---|---|---|
| [Stujenske, Spellman & Gordon 2015, Cell Reports](https://doi.org/10.1016/j.celrep.2015.06.036) ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC4512881/)) | Model of light and heat in the brain, checked against measurements | "Peak temperature changes of .42°C/mW for blue (445 nm; 200 μm fiber) light stimulation"; the model gives 0.35 °C/mW at 445 nm. Pulsed light: "the heat buildup was otherwise equivalent to continuous light at a reduced power" (10 mW pulsed at 50% and 10% duty). "80% of the steady state temperature change is achieved within 5 seconds of light onset and 90% … by 14 seconds" (400 µm depth). A 62 µm fibre heated the tissue near its tip over 50% more than a 200 µm fibre |
| [Owen, Liu & Kreitzer 2019, Nat. Neurosci.](https://doi.org/10.1038/s41593-019-0422-3) ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC6592769/)) | 532 nm, 200 µm fibre, continuous light at powers common in optogenetics (10–15 mW), and 5 s of 3 or 15 mW | "Commonly-used illumination protocols increased temperature by 0.2–2°C and suppressed spiking in multiple brain regions." Effects in wild-type striatal neurons began at about 3 mW for 1 s, a change of about 0.1 °C. For photometry they advise "less than 0.25 mW average power" |

### For LuminoseFM

At 12 mW/mm², heating stays far below the levels at which either paper saw an effect:

- **Upper bound.** Held on without a break (it never is), 0.47 mW would warm the tissue by about
  0.2 °C at 0.42 °C/mW, once at steady state, which takes seconds.
- **With the carrier.** Pulsed light heats like continuous light at the average power (Stujenske),
  0.047 mW in the window: about 0.02 °C at steady state. A 0.3 s window is far shorter than the
  5–14 s the tissue takes to approach that, so the rise in a trial is smaller still.
- **Against Owen et al.** Their first effects came at about 3 mW for 1 s (about 0.1 °C). The
  average power in our window is 60 times lower, and lasts 0.3 s. It is a fifth of their 0.25 mW
  limit for photometry, and the session's average is about 170 times below that limit.
- **Even A's maximum** (21.9 mW/mm², 0.86 mW during a pulse) averages 0.086 mW over the window.

The papers' figures are for one 200 µm fibre deep in the brain at 445 or 532 nm. Here 465 nm light
leaves 5 fibres of 100 µm at the surface of the olfactory bulb. A thinner fibre heats more near its
tip for the same power (Stujenske), but each of our fibres carries a fifth of the cable's power,
and less reaches the tissue than leaves the tips. None of this changes the order of magnitude.

The part working hardest is the LED, not the brain. At 12 mW/mm², B runs close to the LED's
1000 mA rating (`S.Doric.MaxCurrentmA`), which is fine at a 10% duty cycle; Doric's 700 mA
recommendation is for light held on.

### The light path to the bulb

LUMS0014 is an OMP-ChR2(H134R)-YFP mouse (genotype `OSN-ChR` in the session's metadata): ChR2 with
the H134R mutation in every mature olfactory sensory neuron, so the light acts on OSN axons and
their terminals in the glomeruli. The bundle's fibre tips couple to a GRIN lens whose far face is
in contact with the bulb.

The LED calibrations measure the light at the fibre tips, not at the GRIN lens's face. Light lost in
the lens lowers the irradiance at the bulb, and a lens that magnifies the spot pattern by *M* divides
it by *M*²; a 1:1 relay keeps it. The irradiances in this section are those at the fibre tips. A
power meter reading through a spare GRIN lens of the same type would give the factor.

### What activates OSN terminals

The behavioural studies that made mice perceive light on OSN-ChR2 glomeruli, each checked against
the paper's full text:

| Paper | Preparation | Light | Result |
|---|---|---|---|
| [Chong et al. 2020, Science](https://doi.org/10.1126/science.aba2357) ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC8237706/)) | OMP-ChR2-YFP, head-fixed; light patterned on the dorsal bulb through a chronic glass window | Spots of 120 × 120 µm, 15 mW/mm², 80 ms of constant light | At 15 mW/mm² every spot was perceptually detectable (not in ChR2-negative mice). Lowering the intensity below the training level gave "a graded decrease in like-Target responses" |
| [Smear et al. 2013, Nat. Neurosci.](https://doi.org/10.1038/nn.3519) ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC13445371/)) | M72-ChR2(H134R)-YFP: one glomerulus. 488 nm; a fibre stub over the glomerulus, on thinned bone; power measured at the ferrule; fibre diameter not given | Trained at 40 mW, 10 ms. Tested with 1 ms pulses | Detection was high from 5 to 40 mW; "Performance decreased at 1 mW, reaching chance level at 250 μW" |
| [Li et al. 2014, J. Neurosci.](https://doi.org/10.1523/JNEUROSCI.3382-14.2014) ([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC4244471/)) | OMP-hChR2V (H134R, the same opsin as LUMS0014), freely moving; a fibre in a guide cannula into the bulb | 473 nm laser, 19.5–21.5 mW, five pulses of 10–200 ms a trial | Mice discriminated durations 10 ms apart; a subset of mitral/tufted cells responded tonically through the light |

**Against Chong**, the closest preparation (light at the bulb's surface, spots about 100 µm), the
light per area per trial at the fibre tips, for each carrier (*Carrier options* below):

| Carrier (light per trial) | 8 mW/mm² | 12 mW/mm² | 12.9 mW/mm² |
|---|---|---|---|
| 20 Hz × 5 ms (30 ms), every session to 2026-10-03 | 0.24 mJ/mm² (0.2×) | 0.36 mJ/mm² (0.3×) | 0.39 mJ/mm² (0.3×) |
| 20 Hz × 20 ms (120 ms) | 0.96 mJ/mm² (0.8×) | 1.44 mJ/mm² (1.2×) | 1.55 mJ/mm² (1.3×) |
| 20 Hz × 25 ms (150 ms) | 1.20 mJ/mm² (1.0×) | 1.80 mJ/mm² (1.5×) | 1.94 mJ/mm² (1.6×) |
| 10 Hz × 80 ms (240 ms) | 1.92 mJ/mm² (1.6×) | 2.88 mJ/mm² (2.4×) | 3.10 mJ/mm² (2.6×) |
| Constant (300 ms) | 2.40 mJ/mm² (2.0×) | 3.60 mJ/mm² (3.0×) | 3.87 mJ/mm² (3.2×) |
| Irradiance against Chong's 15 mW/mm² | 53% | 80% | 86% |

In brackets, the ratio to Chong's 15 mW/mm² × 80 ms = 1.2 mJ/mm². With the 5 ms carrier, raising the
irradiance alone leaves the light per trial at a third of Chong's at most; the light-on time is the
larger gap.

**Against Smear**, per pulse: one 5 ms pulse puts 1.6 µJ into a cable at 8 mW/mm², 2.4 µJ at 12 and
2.5 µJ at 12.9, or 0.31, 0.47 and 0.51 µJ through each of its 5 fibres. Smear's mice began to fail at
1 µJ a pulse (1 mW for 1 ms) and were at chance at 0.25 µJ. Their fibre size is not given and their
light went through thinned bone, so this comparison is loose, but each of our spots gets per pulse
about what failed there. Six pulses and five spots a trial may add up; no study tested that.

### ChR2 desensitization

Constant light desensitizes ChR2: its current falls from a peak to a lower plateau and recovers only
in the dark. From [Lin et al. 2009, Biophys. J.](https://doi.org/10.1016/j.bpj.2008.11.034)
([PMC](https://pmc.ncbi.nlm.nih.gov/articles/PMC2717302/)), in cultured cells:

| | ChR2 | ChR2(H134R) |
|---|---|---|
| Current lost during 500 ms of light at 470 nm | "77% of the initial current" | a "modest reduction" on ChR2 |
| Recovery in the dark | "50% recovery at 5.3 s", complete within 25 s | not given separately |
| Closing time constant, τ off | 13.5 ± 1.4 ms | 17.9 ± 1.4 ms |
| Irradiance for half the maximal current | 0.215 mW/mm² | 0.387 mW/mm² |

- **Gaps inside the window do not let ChR2 recover.** Recovery takes seconds; the gaps of a 20 Hz
  carrier are 5–45 ms. Pulsing lowers desensitization only by delivering fewer photons. ChR2
  recovers between trials (9.4 s apart on 2026-10-03).
- **A gap shorter than about τ off (18 ms) blurs the pulses together**: the channels have not closed
  when the next pulse starts, so 40 ms on and 10 ms off behaves like constant light with a ripple. A
  gap of about 1.5 τ off or more keeps each pulse a separate event.
- **Constant light works in practice with this opsin.** Li et al. used continuous pulses of up to
  200 ms in OMP-hChR2V (H134R) mice, and Chong et al. 80 ms of constant light.

### Carrier options

The carrier is `S.Light.Carrier`, one row per channel on the setup dialog's *Light path* tab
(*Frequency (Hz)*, *Pulse width (s)*, *TTL level (V)*). PulsePal fills each gate with it (D1).

- **A pulse must be shorter than the period, 1/Frequency.** At 20 Hz the period is 50 ms, so 80 ms
  pulses at 20 Hz cannot exist: `lum.dev.PulsePal.validateChannel` refuses them (*PulseWidth leaves
  no gap*). 80 ms pulses need 12.5 Hz or less; at 10 Hz the 0.3 s window holds three, 240 ms of
  light, with 20 ms gaps (about 1 τ off, so nearly constant light).
- **Constant light is Frequency 0** on both rows, with *TTL level* 5 V; the pulse width is then
  ignored (leave it as it is). PulsePal is sent one pulse as long as the train (the window + 0.1 s, `lum.stim.OptoPattern`),
  in gated mode, so the light is on exactly while Bpod holds the channel's BNC line high and stops
  with an early withdrawal. Sleep and ePhys probes already use it.
- **20 Hz × 20–25 ms** keeps the 20 Hz structure with gaps of 25–30 ms (1.4–1.7 τ off), 40–50% of
  the window lit.

Checked on 2026-10-03 against LUMS0014's settings file, without hardware (`lum.validateSettings`
and the null PulsePal): every carrier above is accepted with 14 timers left for light, and PulsePal
would be sent, on both outputs, gated mode (2), each output linked to its own trigger input, a
train of 0.4 s at 5 V, and pulse and gap of 5 and 45 ms, 20 and 30 ms, 25 and 25 ms, 80 and 20 ms,
or, for Frequency 0, one 0.4 s pulse. 80 ms at 20 Hz is refused: *Channel A: PulseWidth (0.08 s)
leaves no gap at 20 Hz. Reduce the pulse width below the 0.05 s period, or set Frequency to 0 for
constant light.*

Heating for each, as the average power over the 0.3 s window (irradiance × 0.0393 mm² × the lit
fraction):

| Carrier | 8 mW/mm² | 12 mW/mm² | 12.9 mW/mm² |
|---|---|---|---|
| 20 Hz × 5 ms | 0.031 mW | 0.047 mW | 0.051 mW |
| 20 Hz × 20 ms | 0.13 mW | 0.19 mW | 0.20 mW |
| 20 Hz × 25 ms | 0.16 mW | 0.24 mW | 0.25 mW |
| 10 Hz × 80 ms | 0.25 mW | 0.38 mW | 0.41 mW |
| Constant | 0.31 mW | 0.47 mW | 0.51 mW |

The highest, constant light at 12.9 mW/mm², is 0.51 mW for 0.3 s: a sixth of the 3 mW at which Owen
et al. first saw effects, for under a third of their 1 s. It is above their 0.25 mW photometry
limit for those 0.3 s, but that limit is for an average held for the whole recording, and over a
session it averages about 16 µW (a trial every 9.4 s). The heating figures above (upper bound
about 0.2 °C, held without a break for seconds) still apply.

### Raising the light

After four punished sessions (2,269 trials) with no split between A and B, the options considered
on 2026-10-03:

- No session has shown that LUMS0014 perceives the light at all, and the estimate above assumes it
  does. LUMS0014 has had no ePhys calibration, so 8 mW/mm² was never checked against a response
  in the olfactory bulb.
- With the 5 ms carrier the light per trial is a fifth of Chong's at 8 mW/mm² and a third at 12 or
  12.9, and each spot gets per pulse about what Smear's mice could not detect.
- 12.9 mW/mm² is the most A and B can share (B on the blue cable at 1000 mA); 12 leaves a margin.
  Keeping them equal keeps brightness from being a cue.
- Four sessions without a split is not yet a failure by the estimate (a first split in 1–2 weeks;
  question the stimulus after about 7,000 punished trials).

The step closest to Chong's light is 12 mW/mm² with 20 Hz × 20 ms pulses (1.2× Chong's light per
trial, pulses still separate), or constant light (3× at 12 mW/mm², 2× at 8). Whichever is chosen,
change nothing else in the same session, so that a change in behaviour can be put down to the
light, and count that session as a new start for a first split. Note the irradiance and carrier in
the *Light* column of the table above. If the stronger light changes nothing, a session of light
against no light tests perception directly. More light also makes it likelier that the mouse sees
blue light escaping at the implant: that cannot tell A from B, since both are equal, but it matters
in a light-against-dark test.
