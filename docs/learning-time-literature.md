# How long mice take to learn the task

How many days and trials published mice needed to learn an odour discrimination, or a
discrimination of optogenetic input to the olfactory bulb. From these numbers, an estimate for
LuminoseFM's Training stage (pure channel: A pays left, B pays right). Written 2026-09-29, after
LUMS0014's fifth session.

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

The procedure took 3 days, in line with the 2–7 days of pretraining above. LUMS0014 now does 350
to 500 trials a session and completes nearly every hold. There is no sign yet that the light
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
