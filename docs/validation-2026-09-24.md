# LuminoseFM — Pre-deployment validation, 2026-09-24

LuminoseFM 0.9.3 (commit 942fc8f) was validated before use in experiments, and fixed to 0.9.4. The
operator was away from the rig; there was no animal in the box and the fibers were terminated. The
agent drove the devices over their own ports, played sessions in the emulator, simulated the trial
policies and read the code afresh. Nothing was seen, heard or touched, so what needs eyes, ears or
hands is listed at the end.

**Verdict.** The protocol's command paths are right on the rig. That covers light timing (within
0.1 ms of plan), valve times (within 0.035 ms of the calibration), the LED currents calibrated for
each irradiance, sync pulses and barcodes (read back by both cameras) and every outcome path. Five
bugs were found and fixed; none raised an error, and three would have corrupted data or training
without a sign:

1. Automatic shaping grew odd and even trials apart. The hold grew every second trial, and an animal
   completing every other hold kept half its trials at the start hold.
2. `TrialSettings{k}` recorded trial *k*+1's runtime settings, which also put the water total off.
3. 0 µL still opened the reward valves. Volumes past the calibration fit's peak gave less water, and
   larger ones stopped the session.

Two others left windows, video and devices open after an error. Eight questions of design are left
for you (*Open questions*). After the fixes the suite passes 531 of 532 tests, with the one left
skipped because it needs the rig. Lint is clean.

Methods, used in the tables below:

| Code | Method |
|------|--------|
| CT | code trace: read and reasoned through |
| UT | unit test in the suite (existing, or added today: `valveTimesTest`, `holdShapingTest` replay tests) |
| ES | emulated session through `LuminoseFM`, played by a scripted animal and rebuilt from its saved file (`animalSessionTest`, `emulatorSessionTest`, `habituationSessionTest`, and a 1000-trial run) |
| SIM | simulation of the pure trial policy (`lum.nextTrialSpec`, `lum.HoldShaping`) over whole sessions |
| SWEEP | a trial state machine built at each runtime parameter's limits |
| RIG | driven on the rig today; read back from Bpod's events, the devices' acknowledgements, and the cameras' TTL record |
| LOG | inspection of calibration files and saved session files |

Results: **Pass**; **Fixed** (a bug found and fixed, then passed); **Open** (works as built, but a
question for you); **Physical** (cannot be checked remotely: see the last section).

---

## 1. Inventory, with results

Each table below lists one kind of item and carries its result and method, so the inventory and the
pass/fail table are one.

### 1.1 Session types and variants

| Mode | What varies | Result | Method |
|------|-------------|--------|--------|
| Behaviour, stage 1 *Habituation* | both sides pay; guide lights by default; centre reward on trials 1–`CentreRewardTrials`; light off and air on by default; shaping on by default | Pass | ES (habituation session), UT, RIG (valve 2) |
| Behaviour, stage 2 *Training* | correct side pays; shaping on by default | Pass | ES, RIG (sessions B, D) |
| Behaviour, stage 3 *Experiment* | correct side pays; shaping refused | Pass | UT (`shapingInExperiment`), CT |
| Task variant (Familiar/Novel, Mixture, Sequence, Motifs) | recorded only (`S.Task.Variant`); no behaviour depends on it | Pass (recorded) | CT, LOG |
| Stimulus families: pure, mixture, count, order, motif, arbitrary; per-trial patterns | patterns, groups, contingency, evidence | Pass | UT (`generateTest`: every family's defaults within 4 and 15 timers), RIG (mixture: 60 of 60 segments; all families on 2026-09-22) |
| Break mode *Restart stimulus* / *End trial* | where `EarlyWithdrawal` leads, trigger states | Pass | ES (training / punished sessions), UT |
| Shaping *Off* / *Grow hold* / *Shrink grace* / *Both* | hold, grace, hold clock | **Fixed** (B1), then Pass | SIM, ES, RIG (D1), UT |
| Sync modes *Fixed width* / *Jittered width* / *Task events* | how trials drive Flex2 | Pass | RIG (D1, B, D2 against the cameras) |
| Sleep, without test pulses | sync pulses on a clock | Pass | UT (`sleepSessionTest`) |
| Sleep, with test pulses (probes single / paired, per channel / alternating / A and B; plasticity trains; Minutes Inf) | gates, blocks, carriers | Pass | RIG (default schedule), UT (`sleepTest`, `sleepSessionTest`) |
| ePhys calibration: input-output curve, paired-pulse ratio; ascending / descending / shuffled | current per step | Pass | RIG, UT (`ephysTest`, `ephysSessionTest`) |
| Emulator mode | null or simulated shims; blocking runner; compact window | Pass | ES (every session test) |

### 1.2 The behaviour trial's states and transitions (`lum.buildTrialSM`)

Every trial carries all 23 states. Some are unreachable by design, depending on the settings:
`PreStimulusHold` at latency 0, `HoldBreak`/`CentreHoldResumed` without grace, `CentreReward` on
trials without it, `RetryResponse` when wrong choices are punished and `IncorrectChoice` when they are
not. Every trial passes through exactly one trigger state (`LeftReward`, `RightReward`,
`IncorrectChoice`, `NoResponse`, `NoInitiation`, `WithdrewBeforeReward`, plus `EarlyWithdrawal` in
*End trial*), and every path ends in `ITI` → exit. The one loop, `EarlyWithdrawal` →
`WaitForCentrePoke`, is bounded by the hold window (its timer's end, or condition 4 on re-entry).

| State | Entered from | Leaves to (on) | Timer | Result | Method |
|-------|--------------|----------------|-------|--------|--------|
| TrialStart | start | WaitForCentrePoke (Tup) | sync pulse width (pulsed modes), else 0; triggers the hold window | Pass | ES, RIG (widths within 0.05 ms) |
| WaitForCentrePoke | TrialStart; EarlyWithdrawal (restart) | PreStimulusHold or CentreHold (Port2In); NoInitiation (hold window end, or condition 4) | none | Pass | ES (no poke, all broken), RIG (D2) |
| PreStimulusHold | WaitForCentrePoke, latency > 0 | EarlyWithdrawal (Port2Out); CentreHold (Tup) | latency | Pass | ES (punished), RIG (D2) |
| CentreHold | WaitForCentrePoke / PreStimulusHold | no grace: EarlyWithdrawal (Port2Out), CentreReward or WaitForCentreExit (Tup); grace: HoldBreak (Port2Out), the same on the hold clock's end | hold (no grace), else 0; triggers every stimulus timer | Pass | ES, RIG (holds exact) |
| HoldBreak | CentreHold, CentreHoldResumed (grace) | CentreHoldResumed (Port2In); hold done (clock end); EarlyWithdrawal (Tup) | grace | Pass | ES (habituation trials 1, 2) |
| CentreHoldResumed | HoldBreak | HoldBreak (Port2Out); hold done (clock end) | 0 | Pass | ES |
| CentreReward | hold done, on centre-reward trials | WaitForCentreExit (Tup) | valve 2's time | Pass | ES, RIG (14.70 ms for 1 µL) |
| WaitForCentreExit | hold done / CentreReward | WaitForResponse (Port2Out or condition 3); NoResponse (Tup) | `ResponseWindow` | Pass | ES (stays in centre) |
| WaitForResponse | WaitForCentreExit, RetryResponse | Left/RightRewardDelay (a paying side); IncorrectChoice or RetryResponse (the other); NoResponse (Tup) | `ResponseWindow` | Pass | ES, RIG |
| RetryResponse | WaitForResponse | WaitForResponse | 0 | Pass | ES, RIG |
| Left/RightRewardDelay | WaitForResponse | WithdrewBeforeReward (leaving that port); Left/RightReward (Tup) | `RewardDelay` | Pass | ES (punished trials 1, 2) |
| Left/RightReward | reward delay | DrinkingLeft/Right (Tup) | valve 1/3 time | Pass | ES, RIG (within 0.035 ms of calibration) |
| DrinkingLeft/Right | reward | DrinkingGrace (the port clear, condition 1/2) | none | Pass; Open (Q6) | ES |
| DrinkingGrace | drinking | ITI (Tup); back to drinking (either side poke) | `DrinkingGrace` | Pass; Open (Q6) | ES (rapid pokes) |
| WithdrewBeforeReward | reward delay | ITI | 0 | Pass | ES |
| IncorrectChoice | WaitForResponse, punished | ITI (Tup) | timeout, at least the noise | Pass | ES, UT |
| EarlyWithdrawal | PreStimulusHold, CentreHold, HoldBreak | WaitForCentrePoke (restart) or ITI (end trial) | punishment timeout, at least the noise when the next state would cut it | Pass | ES |
| NoResponse | WaitForCentreExit, WaitForResponse | ITI | 0 | Pass | ES |
| NoInitiation | WaitForCentrePoke | ITI | 0 | Pass | ES |
| ITI | every end | exit (Tup) | `ITI`; stops the HiFi module | Pass | ES (every trial's ITI against its settings) |

Two waits have no time limit, by design. `DrinkingLeft/Right` waits for the animal to leave the
reward port. Each unpunished wrong poke restarts the response window, so an animal alternating wrong
pokes keeps the trial going. Both come after the trigger state, so the next trial is prepared anyway.

Other state machines: the session barcode (`Barcode001…`, one per edge, Tup to the next, then exit;
RIG, decoded from both cameras for all three kinds) and the sleep/ePhys blocks (`Level001…`, Tup
chains; RIG). Neither has a branch.

Session end: `MaxTrials` reached (ES, 1000 trials, stopped exactly), the console's End button (CT;
P6 physical), an error (CT; fixed B4, B5).

### 1.3 Runtime parameters (`S.GUI`, changeable during a session)

All runtime parameters were built at the minimum and maximum of their limits, with and without shaping
(SWEEP). That gave 106 trial state machines, each state timer equal to its parameter, with no error
or warning. The only refusals were the correct ones: a hold window shorter than the hold, and a
target hold of 0.

| Parameter | Default | Units | Limits | Consumed by | Result | Method |
|-----------|---------|-------|--------|-------------|--------|--------|
| RewardAmount | 3 | µL | 0–100 | `lum.valveTimes` → reward states' timers; plots' water | **Fixed** (B3), then Pass | RIG, ES, UT |
| RewardDelay | 0 | s | 0–60 | `Left/RightRewardDelay` timer | Pass | ES, SWEEP |
| DrinkingGrace | 0.5 | s | 0–60 | `DrinkingGrace` timer | Pass | ES, SWEEP |
| CentreRewardAmount | 1.2 (was 1; Q7) | µL | 0–100 | `lum.valveTimes` (valve 2); `nextTrialSpec` (0 = none) | Pass | ES, RIG |
| CentreRewardTrials | 10 | trials | 0–100000 | `nextTrialSpec` (habituation only) | Pass | ES (trials 1–2 only), UT |
| CentreRewardAgain | off | tick | — | `lum.centreRewardAgain` (unticks itself) | Pass | UT (`trialSpecTest`) |
| CentreRewardAgainTrials | 10 | trials | 1–100000 | `lum.centreRewardAgain` | Pass | UT |
| HoldWindow | 60 | s | 0.1–3600 | hold window global timer | Pass | ES, SWEEP, UT |
| PostStimulusHold | 0 | s | 0–60 | hold without shaping | Pass (Q2: as intended) | ES, SWEEP |
| ResponseWindow | 10 | s | 0.1–3600 | `WaitForCentreExit`, `WaitForResponse` timers | Pass | ES, SWEEP |
| ITI | 1 | s | 0–3600 | `ITI` timer | Pass | ES (every trial), SWEEP |
| PunishCondition | 1 None | menu | 4 entries | `lum.punishmentFor` | Pass | ES, UT |
| PunishType | 3 Timeout + noise | menu | 3 entries | `lum.punishmentFor` | Pass | ES, UT |
| PunishTimeout | 2 | s | 0–3600 | `IncorrectChoice`, `EarlyWithdrawal` timers | Pass | ES, SWEEP |
| BiasCorrection | 0.5 | strength | 0–1 | `nextTrialSpec` | Changed per Q1, then Pass | SIM, UT |
| BiasWindow | 20 | choices (was trials; Q5) | 1–1000 | `nextTrialSpec` | Pass | SIM, UT, SWEEP |
| HoldStart | 0.1 | s | 0–60 | `lum.HoldShaping` | **Fixed** (B1), then Pass | SIM, ES, RIG |
| HoldGrowth | 5 | % | 0–100 | `lum.HoldShaping` | **Fixed** (B1), then Pass | SIM, ES, RIG |
| HoldTarget | 1 | s | 0–60 | `lum.HoldShaping` (cap) | Pass | ES (capped at 1 s), UT |
| HoldStepBackAfter | 10 | early withdrawals | 0–1000 | `lum.HoldShaping` | **Fixed** (B1), then Pass | SIM, ES |
| GraceStart / GraceShrink / GraceTarget | 0.3 / 5 / 0 | s / % / s | 0–10 / 0–100 / 0–10 | `lum.HoldShaping` | **Fixed** (B1), then Pass | SIM, ES |
| OptoOn | on | tick | — | `nextTrialSpec` → light timers | Pass | UT, SWEEP |
| SoundOn | on | tick | — | `nextTrialSpec` → play actions | Pass | UT, SWEEP |
| PortLightIntensity | 100 | PWM 0–255 | 0–255 | every port light's level | Pass (command); Physical (brightness) | SWEEP, RIG (PWM ran) |

Changing a value during the session: it applies from the next trial prepared (CT, ES). It is now
recorded against the trial that ran it (B2, ES), and the settings file keeps the values the session
ended with (CT, UT `settingsTest`).

### 1.4 Pre-session settings

Frozen for the session and stored once in `Data.Session.Settings`. Each field was traced from
`lum.defaultSettings` to its consumer (CT); none is read without being used, except the experiment
metadata, which exists to be recorded.

| Group | Fields (default) | Consumed by | Result | Method |
|-------|------------------|-------------|--------|--------|
| `Meta` | Subject (from the launch manager), Genotype (OSN-ChR), Notes, Neuropixels.*, EEG.*, Drug.* (Name required when Enabled) | recorded; `lum.launchSubject`; `validateSettings` (drug name) | Pass | CT, UT |
| `Session` | Type (Behaviour), MaxTrials (1000), SaveEveryNTrials (5), UseOpto (on), UseSound (on), UseSync (on), ShowAnalogViewer (on), HouseLight (off), RuntimeWindow (Automatic) | `LuminoseFM`, `lum.dev.open`, `lum.stim.build`, `buildTrialSM`, generator (order length) | Pass | ES (1000 trials; saves every 5), RIG |
| `Task` | Variant, TrainingStage (2), ReverseContingency (off), GroupPLeft ([] = family's), MaxSameSide (3), AutoShaping (off), HoldShaping (Grow hold), OnHoldBreak (Restart) | `nextTrialSpec`, `applyContingency`, `HoldShaping`, `buildTrialSM`, `triggerStates` | Pass (contingency, reversal: SIM; run limit: Open Q1) | SIM, ES, UT |
| `Cue` | Components: centre light (on, through the stimulus), tone, air; ToneFrequency (4000 Hz) | `lum.cueTiming`, `lum.stim.build`, `lum.loadSounds` | Pass (commands); Physical (light, tone) | UT (`stateMachineTest`, `cueTimingTest`) |
| `Stimulus` | Duration (1 s), Latency (0 s), Generator (family pure, bin 10 ms, a new seed each session), Components (air, centre light, tone: off), ToneFrequencyRange (6–16 kHz) | `lum.pattern.*`, `buildTrialSM`, carrier's train length | Pass | UT, RIG, ES |
| `Left`, `Right` | Light (off, 0–1 s), Tone (off, 8 / 12 kHz, 0–0.2 s), GuideLight (Habituation only) | `lum.stim.PortLight` (the paying side), `lum.stim.Sound`, guide lights | Pass | UT (`stateMachineTest`) |
| `Light` | Bundle (2-to-19), Cables (blue, green), Carrier per channel (20 Hz, 5 ms, 5 V) | `lum.led.lightPath`, `lum.dev.PulsePal.configure` | Pass; Open (Q8, the default bundle) | RIG (PulsePal log: 5 ms pulses, 45 ms gaps, gated), UT |
| `Doric` | Enabled (on), Folder, IrradiancemWmm2 ([8 8]), CurrentmA ([100 100]), MaxCurrentmA ([1000 1000]), CalibrationCurrentsmA (0:100:1000), ShowWindow (on) | `lum.led.*`, `lum.dev.DoricLED`, LED window, calibration window | Pass | RIG (currents per irradiance), UT (`ledTest`, `doricTest`) |
| `Sound` | SamplingRate (192 kHz), Amplitude (0.5), Attenuation_dB (−20), NoiseDuration (0.5 s) | `lum.loadSounds`, `RealHiFi`, punishment timers | Pass (commands); Open (Q9); Physical (level) | ES, RIG (tone played) |
| `Camera` | Enabled (on), Format (avi-mjpeg-mt), FrameRate (100 Hz), exposure and gain (auto), TtlLine (Line0), ShowWindow, WindowRate (5 Hz), Cameras (sideview 24226887, topview 24226657) | `lum.dev.openCameras`, `configureCameras`, `lum.sync.fitToCameras` | Pass | RIG (3850 / 6530 / 1202 frames, none dropped) |
| `Sync` | Mode (Jittered width), FixedWidth (50 ms), MeanWidth (60 ms), WidthJitter (40 ms), Barcode (32 bits; markers 0.1 / 0.2 / 0.3 s for behaviour / sleep / ePhys; bits 20 / 50 ms; gap 20 ms) | `nextTrialSpec`, `buildTrialSM`, `lum.sync.*` | Pass | RIG (all modes and kinds read back by both cameras) |
| `Sleep` | DurationMinutes (120), HouseLight (off), Sync (jittered, every 1 s), TestPulses (off; paired 10 ms, 50 ms apart, 30 s; 2 mW/mm²; alternate A and B until the recording ends; trains) | `lum.sleep.*` | Pass | RIG, UT |
| `Ephys` | Channels (A), PulseWidth (5 ms), InterEpochInterval (1 s), Repeats (10), Order, Seed, Voltage, InputOutput (0–12 mW/mm², 8 levels), PairedPulse (8 mW/mm², 20–500 ms), HouseLight, Sync | `lum.ephys.plan`, `lum.sleep.run` | Pass | RIG, UT |

### 1.5 Features and toggles

Each feature was checked enabled (a), disabled (b) and at its boundaries (c).

| Feature | (a) Enabled | (b) Disabled | (c) Boundaries | Result |
|---------|-------------|--------------|----------------|--------|
| Hold growth | +`HoldGrowth` % per completed hold, one trial late (after B1); only completed holds count | shaping off: hold = window + post-stimulus hold on every trial (ES: 0.5 s × 9) | capped at `HoldTarget` and stays (ES: 1.0 s from trial 5; UT); never below `HoldStart`; growth 0 holds it; target 0 refused | **Fixed** (B1), Pass — SIM, ES, RIG D1 |
| Step back | one growth step after `HoldStepBackAfter` early withdrawals at one hold, once (SIM, ES) | 0: never (UT) | never below the start (UT) | **Fixed** (B1), Pass |
| Shrink grace | a break within the grace is forgiven and the stimulus runs on; beyond it is an early withdrawal (ES) | no hold clock, `HoldBreak` unreachable (UT) | shrinks to `GraceTarget` (UT, SIM) | **Fixed** (B1), Pass |
| Restart on a broken hold | back to the poke with the cue; the stimulus restarts; bounded by the hold window (ES) | *End trial* ends it as an early withdrawal (ES) | hold window shorter than a hold refused (UT, SWEEP) | Pass |
| Latency | cue held; leaving is a broken hold, grace never applies (ES, RIG D2) | 0: the poke goes straight to `CentreHold` (UT) | — | Pass |
| Centre reward | trials 1–N in habituation, valve 2 for its calibrated time (ES, RIG) | Training / Experiment: none (UT); amount 0: none | valve 2 uncalibrated: none, with a warning (CT); 1 µL runs extrapolated (UT) | Pass |
| Retry after a wrong choice | the correct port still pays; `Incorrect`, `Rewarded` 1 (ES, RIG) | punished: `IncorrectChoice`, no reward (ES) | — | Pass |
| Punishment | timeout, noise, both; the noise plays to its end (ES, UT) | *None*: zero timers, no sound (UT) | timeout 0–3600 (SWEEP) | Pass (commands); Physical (the noise heard, P5) |
| Bias correction | after Q1: always-left animal, 74–84% right-paying trials at strength 0.5 (target 75%), 86–92% at 1 (target 90%), for 500–600 trials (SIM, UT); over the last `BiasWindow` choices (UT) | 0: target 0.5 on every trial, order untouched (SIM) | target kept within 0.1–0.9 (SIM); groups still balanced exactly (500 / 500) | Changed per Q1, then Pass |
| Run limit (`MaxSameSide`) | breaks runs; after Q1 yields to bias correction on the side it pushes towards (UT); unbiased animal: runs of at most 4–5 in 1000 trials (SIM) | 0 or correction off: at most 3 in a row (SIM) | a run the correction does not want is always broken (UT) | Changed per Q1, then Pass |
| Trial order | groups balanced over the session (500 / 500); lag-1 same-group rate 0.504; a new clock-drawn seed per session, 5 of 5 differ (SIM) | a typed seed repeats a session (UT) | balance is over the whole order, not within blocks (Q4) | Pass; Open (Q4) |
| Side draw for intermediate P(left) | P(left) 0.8 / 0.3 delivered 0.774 / 0.290 over 500 trials each (SIM) | P(left) 1 / 0: fixed side | the global rng is seeded from the clock by Bpod at start (CT) | Pass; Open (Q3) |
| Contingency reversal | P(left) [1 0] runs as [0 1] and is recorded (SIM, UT) | off: as typed | — | Pass |
| Light pattern | one global timer per segment, triggered with the hold (RIG: 60 of 60 within 0.1 ms) | `OptoOn` off or `UseOpto` off: no timers (UT) | refused over the timer budget (UT) | Pass |
| LED intensity | calibrated channels run the current for the asked irradiance (RIG: 8 mW/mm² → 253 / 496 mA; 2 → 42 / 73) | uncalibrated channel runs in mA with a note (LOG: 2-to-19) | an irradiance out of reach runs at the channel's most with a note (UT); limit 1000 mA | Pass |
| LED window change mid-session | sent in the prepare window, recorded per trial (UT `emulatorSessionTest`) | — | — | Pass |
| Stimulus components (air, centre light, tone) | whole window: an output of the hold; part of it: a global timer (UT) | off: nothing | whole window lasts the whole hold (Q2: as intended) | Pass |
| Side light, side tone, guide lights | the paying side (UT) | off | — | Pass (commands); Physical |
| Sync pulses | on every trial, at trial start, logged as `SyncPulseWidth` and on both cameras (RIG B, D1, D2) | `UseSync` off: the line is not driven (UT) | widths fitted to the cameras (UT `barcodeTest`) | Pass |
| Session barcode | behaviour, sleep and ePhys kinds decoded from both cameras (RIG) | off: not sent, recorded `Sent` false (UT) | — | Pass |
| House light | switches reach BNC1 in 20–34 ms (RIG) | a session without PulsePal disables it (UT) | — | Pass (loopback); Physical (light seen) |
| Video | both cameras, none dropped, TTL logged (RIG) | off: no files, recorded (UT) | — | Pass |
| Flow meter (Flex1) | stream recorded and merged (RIG: 34 419 samples) | — | realigned for the barcode's run (UT) | Pass (stream); Physical (air flow) |
| Saving | every `SaveEveryNTrials`, teardown, video summary (ES) | — | 1000 trials: 0.5 MB file, save ≤ 0.26 s, per-trial costs flat (ES) | Pass |
| Error handling | a failure in the trial loop saves and releases (CT, UT) | — | a failure before trial 1, or in a sleep block, now does too (B4, B5) | **Fixed**, Pass (CT, suite) |

### 1.6 Hardware outputs and inputs

| Line | Role | Result | Method |
|------|------|--------|--------|
| Valve1 / Valve3 | left / right reward | Pass (26.60 / 25.60 ms for 3 µL, as calibrated; in sessions within 0.035 ms). Water: Physical | RIG |
| Valve2 | centre reward | Pass (14.70 ms for 1 µL). Water: Physical | RIG |
| Valve4 | air (cue / stimulus) | Pass (100 ms). Air flow: Physical | RIG |
| PWM1–3 | port lights, guide lights | Pass (200 ms each at 100). Light: Physical | RIG |
| BNC1 / BNC2 out → PulsePal IN1 / IN2 | channels A / B gates | Pass (gates in every light session) | RIG |
| PulsePal OUT1 / OUT2 → Doric TTL in | carrier into the LED | Pass (programmed gated, 5 V, 5 ms pulses at 20 Hz; acknowledged). Light: Physical | RIG, LOG |
| Doric LED ch1 / ch2 | intensity (external TTL mode) | Pass (every current acknowledged, 0–893 mA) | RIG |
| PulsePal OUT3 | house light | Pass (loopback) | RIG |
| Flex2 (digital out) | sync TTL, barcode | Pass (both cameras, every mode) | RIG |
| HiFi1 | sounds | Pass (loaded, played). Sound: Physical | RIG |
| Port1–3 IR in | pokes | Pass (read clear; virtual pokes drove every path). A real beam break: Physical | RIG |
| BNC1 in | house light loopback | Pass (events). A *condition* on it reads inverted (gotcha recorded) | RIG |
| Flex1 (analog in) | flow meter | Pass (samples recorded) | RIG |
| Camera Line0 | sync line into both cameras | Pass | RIG |
| Port4 IR, Port5, PulsePal OUT4, Flex3–4 | unused | — | CT |

### 1.7 Files read and written

| File | Read / written by | Result | Method |
|------|-------------------|--------|--------|
| `Session Settings\<name>.mat` (`ProtocolSettings`) | read at launch (`lum.mergeSettings` converts old ones); written at Start and at teardown | Pass | UT (`settingsTest`), CT |
| `calibration\DoricLED_<bundle>_<cable>_<A|B>.mat` | read at session start (`lum.led.calibrations`); written only by the calibration window | Pass: 8 of 8 4-to-19 files, 18 points 0–1000 mA, rising, irradiance = power / area; Open (Q10) | LOG |
| `Bpod Local\Calibration Files\LiquidCalibration.mat` | read by Bpod; used through `lum.valveTimes`; now copied into `Session.LiquidCalibration` | Pass | LOG, RIG |
| `Bpod Local\Calibration Files\SoundCalibration.mat` | not used | Open (Q9) | CT |
| `Session Data\<subject>_LuminoseFM_<date>.mat` | `SaveBpodSessionData`: every N trials, teardown, video summary | Pass; trials rebuilt from it alone (ES, RIG) | ES, RIG |
| `..._ANLG.dat` | Bpod's raw flow-meter stream; merged into the `.mat` | Pass | RIG |
| `..._plots.png` | teardown | Pass | UT |
| `Session Videos\<view>_<file>.avi` / `.csv`, `_events.csv`, `_session.json` | SpinCam | Pass | RIG |
| FlexConfig, Bpod settings | read live from the machine, never from file | Pass | CT |

### 1.8 Data logged per trial, and rebuilding trials from the file

Each emulated and rig trial was rebuilt from its saved file alone, from these sources:
- the pattern (`PatternIndex` into `Session.StimulusSet`);
- the light timers' events against the last `CentreHold` entry;
- the hold (`HoldDuration`) against `CentreHold`'s length;
- the reward (`TrialSettings{k}.RewardAmount` through the liquid calibration) against the reward
  state's length;
- the sync pulse (`SyncPulseWidth`) against `TrialStart`;
- the ITI (`TrialSettings{k}.ITI`) against `ITI`;
- the outcome, by re-scoring the raw events with `lum.scoreTrial`.

Every series is one value per trial (1000 of 1000 in the long run). `LEDCurrentA/B`, `HouseLight`
and `CameraTime` are per trial; `Session.Settings`, `StimulusSet`, `Rig`, `DoricLED`, `Barcode`,
`Cameras`, `Startup` and (new) `LiquidCalibration` are per session. Result: Pass after B2. Before it,
`TrialSettings` could not rebuild a trial whose runtime values had just changed.

---

## 2. Bugs found and fixed

| # | File, line | What was wrong | Before | After | Verified |
|---|-----------|----------------|--------|-------|----------|
| B1 | `+lum/HoldShaping.m` `next`, 124–160; `notePrepared`, `running`; `+lum/newHistory.m`; `LuminoseFM.m` 509 | Trial *k*+1 is prepared while trial *k* runs, and shaping stepped from trial *k*−1's hold: odd and even trials were two separate shaping sequences | every hold completed: 0.1, 0.1, 0.105, 0.105, 0.110 … (a step every second trial); every other hold completed: odd trials grew, even trials stayed at 0.1 s (a saw-tooth); the withdrawal count reset whenever the two halves differed, so the hold rarely stepped back | steps from the running trial's hold: 0.1, 0.1, 0.105, 0.110 …; every other completed: 0.1, 0.1, 0.105, 0.105, 0.110 …; one step back, never twice for the same withdrawals. Grace the same. At the same `HoldGrowth` the target comes in about half the trials | SIM, `holdShapingTest` (3 new replay tests), `animalSessionTest`, RIG D1 |
| B2 | `LuminoseFM.m` 281–367 (`nextGUI`, `trialGUI`, `startSettings`) and `recordTrial` | `TrialSettings{k}` was `S.GUI` after the next trial was synced; `Session.Settings` was taken at trial 1's record, after trial 2's sync; the plots' water used the current value | a reward changed during trial 2 (3 → 6 µL) was recorded against trial 2, which gave 3 µL; the plots' water total said 27 µL where 24 µL were given | each trial records the runtime values it was prepared with; `Session.Settings` is trial 1's; water from each trial's own reward | `animalSessionTest` (ITI and reward typed mid-session; every trial's ITI against its record) |
| B3 | `+lum/valveTimes.m` (new); `LuminoseFM.m` 133, 510–552 | Valve times came straight from Bpod's quadratic fit | 0 µL: 7.5 / 8.2 / 6.1 ms on valves 1 / 2 / 3; 20 µL: 54 ms (less than 15 µL's 60 ms); 30 µL: 6 ms on valve 1; from about 31 µL Bpod errored mid-session, ending it | 0 µL opens nothing; a volume where the fit no longer rises is refused (at start: the session does not begin; mid-session: the previous volume is kept and the window put back); outside the measured volumes, a printed note; `Session.LiquidCalibration` recorded | `valveTimesTest`, `animalSessionTest` (40 µL typed mid-session, kept at 6), RIG (valves within 0.035 ms) |
| B4 | `LuminoseFM.m` 205–292, `abandonSetup` | An error between opening the devices and trial 1 (a sound, a window, the barcode, the first trial's valve lookup) left the windows, the video recording and PulsePal, the LED and the cameras open | the protocol stopped with everything open | torn down (windows, trial manager, video, devices), the console freed, then the error | CT, full suite |
| B5 | `+lum/+sleep/run.m` 205–249, 274–362 | In a sleep or ePhys session, only PulsePal and LED errors were caught: any other error during the blocks, or before the first, skipped the teardown | a 2-hour recording failing at 1 h 50 min: no final save, no analog merge, no video summary, devices open | the error becomes `StoppedReason`, a warning, and the normal teardown saves what was sent and releases everything | CT, `sleepSessionTest`, `ephysSessionTest` |

Tests added: `animalSessionTest` (3 played sessions, 15 checks, about 2 min), `startSessionMouse`
(its animal), `valveTimesTest` (5), and three replay tests in `holdShapingTest`. Docs updated:
README, `data-format.md`, `architecture.md` (D6), `naming-and-versions.md` (0.9.4),
`repository.md`, `rig-checks.md`, CLAUDE.md. `lum.version` is 0.9.4.

---

## 3. Open questions

Your decisions (2026-09-24), now implemented:
- **Q1.** Bias correction works over the window you set, and takes precedence over the run limit
  (`nextTrialSpec`; 4 new tests).
- **Q2.** The post-stimulus hold is as intended (default 0).
- **Q5.** `BiasWindow` counts choices, as its help said.
- **Q7.** The centre reward default is 1.2 µL; 1 µL still runs, extrapolated.
- **Q8.** The 2-to-19 stays the default. A 2-to-19 session uses mW/mm² once its cables are
  calibrated: checked with calibrations saved to a temporary folder through the calibration
  window's own save function.

Also on request: choosing *Habituation* now switches the centre light cue on, and a new
`stateMachineTest` builds a habituation trial from the defaults and checks it:
- the centre light is on through the hold;
- air runs during the hold;
- the hold is shaped;
- the centre reward is 1.2 µL;
- both side lights are lit and both sides pay 3 µL;
- the trial ends in ITI and exit.

The text below is as first written; the questions left open are Q3, Q4, Q6, Q9 and Q10.

**Q1. Bias correction fades, and then breaks the run limit.** It can only bring forward trials already
in the balanced order, at most 50 ahead. Against an animal that always goes left (strength 0.5 or 1),
right-paying trials were 69–70% of the first 100, then about 50%, then fewer (39% in trials 301–400).
Once the right-paying trials within reach were used up, runs longer than `MaxSameSide` (3) followed,
the first ending at trials 125–356. With an unbiased animal the limit held over 1000 trials. Options:
- look further ahead when the limit or the correction needs a trial (cheap, but the end of the
  session becomes one-sided);
- draw the side independently of the group order for groups that can pay either side;
- keep it, and document it (done: README).

**Q2. A whole-window stimulus component lasts the whole hold.** Air, centre light or side light with
onset 0 and duration ≥ the window is an output of `CentreHold`, so with `PostStimulusHold` > 0 it
stays on through the post-stimulus hold. A 1 s air with a 0.5 s post-stimulus hold gives 1.5 s. The
light pattern does not do this. The default post-stimulus hold is 0. Fixing it would cost a global
timer whenever the post-stimulus hold is above 0.

**Q3. The run limit forces the side of psychometric groups.** For a group with P(left) between 0 and
1, the run limit sets the side outright, so the group's delivered P(left) moves toward 0.5. It was
0.766 against 0.80 in simulation, within noise at 500 trials.

**Q4. Balance is over the whole session, not in blocks.** Groups are balanced over `MaxTrials` (1000)
and shuffled once. A session that stops at 200 trials had 97 / 103; the longest run of one group was
8. Block randomisation would balance every prefix.

**Q5. `BiasWindow` counts trials, not choices.** The help says "the last `BiasWindow` choices"; the
code takes the last `BiasWindow` trials and drops those without a choice, so fewer choices may count.
Either the text or the code should change.

**Q6. The drinking grace restarts on either side poke.** During `DrinkingGrace`, a poke at the
unrewarded side returns to `Drinking*`, which leaves at once since the rewarded port is clear, and
the grace starts again. This only lengthens the trial. No drinking state has a time limit.

**Q7. The centre reward's default is below valve 2's measurements.** 1 µL is less than the smallest
volume measured (1.2 µL at 15 ms), so its 14.7 ms is extrapolated, and the session now says so. The
side default (3 µL) is within the measurements. Consider a calibration point near 1 µL, or a 1.5 µL
default.

**Q8. The default settings name the 2-to-19 bundle, which has no calibration.** A new subject's
settings file starts on it and runs both channels at 100 mA with a note, not at 8 mW/mm². The rig
uses the 4-to-19 (orange A / blue B, all calibrated). Either default to 4-to-19 or calibrate the
2-to-19 (P4).

**Q9. Sound level is not calibrated.** Tones and noise play at `Amplitude` 0.5 and −20 dB digital
attenuation; Bpod's `SoundCalibration.mat` is not used. Fine if the level only needs to be constant.

**Q10. Two LED calibration points to look at again** (not changed):
- Green on A: the points from 50 to 700 mA are still the 0.9.0 measurement, with the dark point
  replaced in software on 2026-09-23, and the file's note saying so was lost when it was extended to
  1000 mA today.
- Black on A: the 900 → 1000 mA step (0.635 → 0.724 mW) is 2.4 times the step before it. Every other
  point on every cable is monotonic and within about 10% of the other cables on its channel.

---

## 4. What still needs someone at the rig

Listed in `docs/rig-checks.md` as P4–P10:
- **Light at the fiber tips** for the families and intensities (P8). Everything upstream of the
  light — gates, PulsePal program, LED currents — was acknowledged.
- **The driver's front knob** at 1000 mA on both channels, and the LED head's temperature (P9). The
  driver reports what USB asked for, not the knob. The calibrations rising to 1000 mA suggest the
  knob was up when they were measured.
- **Water at each port and air from valve 4** (P5). The valves opened for their calibrated times;
  that is all Bpod can report.
- **The punishment noise and cue tones heard**, at a sensible level (P5).
- **Port lights and guide lights seen** at `PortLightIntensity`.
- **A real beam break at each port.** Only virtual pokes were used, and all three sensors read clear.
- **The End button** with the camera and LED windows open (P6); the startup line in a desktop
  launch (P7).
- **The 2-to-19 calibration** (P4), and the two points in Q10.
- **0.9.4 in a desktop session** (P10): a refused reward volume shown back in the runtime window, and
  the *Centre hold* plot stepping once per completed hold.

Rig sessions of today, in `%TEMP%\LuminoseFM_rigcheck\FakeSubject\LuminoseFM\`:
`FakeSubject_LuminoseFM_20260924_150202` (behaviour), `_150528` (sleep), `_150658` (ePhys),
`_151150` (fixed-width sync, shaping) and `_151247` (task-event sync).
