# LuminoseFM — Names and version history

The same words mean the same thing in the code, the windows, the plots and the data. This file is
the glossary, and the record of what was renamed when. Naming is a design decision in its own
right — D8 in [`architecture.md`](architecture.md).

---

## Glossary

| Name | Means |
|------|-------|
| channel A, channel B | The two optical channels (BNC1 and BNC2). Never "pattern 1/2" or "ch1/ch2". |
| light pattern | The light one trial delivers: channels A and B over the stimulus window |
| joint state | What A and B are doing together at one moment: dark, A only, B only, A and B |
| group | One stimulus condition; groups are balanced across a session |
| stimulus set | A session's patterns, their groups and contingency, and the trial order |
| stimulus family | The kind of question a stimulus set asks: pure channel, mixture, sequence, order, motifs, or hand-drawn pulses (`S.Stimulus.Generator.Family`: `pure`, `mixture`, `count`, `order`, `motif`, `arbitrary`). Defined in [`stimulus_family.md`](stimulus_family.md) |
| amount | How long a channel is lit in a pattern: u_A, u_B in seconds, or as a fraction of the window (the plots' axes) |
| amount level | One of the amounts the mixture family pairs, as a fraction of the window (`MixtureLevels`) |
| decision rule | The mixture's contingency (`MixtureRule`): A's *share* of the light or A *minus* B against a boundary (relative rules, both channels needed), or *A alone* / *B alone* (the controls: a vertical or horizontal boundary) |
| A share | A's relative abundance in the mixture, `u_A / (u_A + u_B)` (π in `stimulus_family.md`); set as mixture ratios A:B (`MixtureRatios`, boundary `MixtureShareBoundary`) |
| total light | `u_A + u_B` as a fraction of the window: what the mixture's relative rules rove, so that no amount alone tells the side (`MixtureShareTotals`, `MixtureDifferenceTotals`) |
| flash | One stretch of light on one channel in the sequence and motif families: one light segment, filled by the carrier like any other |
| slot | One of the equal parts the sequence family cuts the window into, holding one flash or nothing |
| word, letter | The motif family's group, and its parts: letters A, B, X (both) and - (dark), one flash each |
| turn | One handover from one channel to the other and back in the order family; the guarded cycle's turn has a short and a long overlap |
| evidence | A family's decision variable, the psychometric axis: B share, A flashes minus B flashes, the deciding amount (`StimulusSet.Evidence`) |
| family's contingency | The P(left) a family gives its groups (`FamilyPLeft`), used when `S.Task.GroupPLeft` is empty |
| seed | The number that fixes every trial of a session, their order and whatever the family draws at random (`S.Stimulus.Generator.Seed`, `Session.StimulusSet.Seed`). New every session by default; typed in to repeat a session |
| single-cue ceiling | The best score an observer reading one cue alone (A's amount, B's amount, total light, A's or B's time course) could reach (`StimulusSet.Shortcuts`) |
| stimulus window | `S.Stimulus.Duration`, from stimulus onset |
| latency | `S.Stimulus.Latency`: from the poke to stimulus onset, held with the cue on |
| hold, hold break, grace | The centre-port hold; leaving during it; how long a break may last unpunished |
| hold window | `HoldWindow`: the time from trial start in which a hold must be completed, restarts included |
| session type | Behaviour, sleep or ePhys calibration; `Session.Type` is `'Behaviour'`, `'Sleep'` or `'EphysCalibration'` |
| carrier | What PulsePal does on a channel while it is on (frequency, pulse width, voltage) |
| centre | British spelling, in identifiers as well as text: `CentreHold`, `WaitForCentrePoke` |
| test pulses | Light during a sleep recording, probes and plasticity trains on a schedule: `S.Sleep.TestPulses` |
| epoch | One probe — a single pulse or a pair — or one train: what a schedule step repeats |
| inter-pulse interval, inter-epoch interval | Onset to onset: between the two pulses of a pair; between successive epochs |
| plasticity train | Bursts of pulses meant to change the response: theta burst, high frequency, or one of your own |
| schedule step | One row of the schedule: probe, rest or a train, for its length, on its channels |
| light segment | One gate on channel A or B: a probe pulse, or a burst PulsePal fills with pulses (`LightSegments`) |
| task variant | Which variant of the task a session runs: Familiar/Novel, Mixture, Sequence, Motifs (`S.Task.Variant`) |
| contingency reversal | Swapping which side every group pays, `P(left)` to `1 - P(left)` (`S.Task.ReverseContingency`) |
| automatic shaping | Training the animal by its performance: now the centre hold (`S.Task.AutoShaping`, method `S.Task.HoldShaping`); later easier and harder trials. On for Habituation and Training, never in an Experiment |
| step back | Automatic shaping shortening the hold one growth step after `HoldStepBackAfter` early withdrawals at one hold |
| early withdrawal | Leaving the centre port before the hold is complete, unforgiven (state `EarlyWithdrawal`; `Data.EarlyWithdrawals`) |
| centre reward | Water at the centre port for a completed hold, on habituation's first trials (`S.GUI.CentreRewardAmount`, `S.GUI.CentreRewardTrials`; state `CentreReward`; `Data.CentreReward`, µL) |
| centre reward again | The centre reward given again, in any stage, on a set number of trials after the operator ticks it in the runtime window (`S.GUI.CentreRewardAgain`, `S.GUI.CentreRewardAgainTrials`) |
| retry | Going on to the correct port after an unpunished incorrect choice: state `RetryResponse`, then the response window again (`Data.ResponseRetries`). Not "correction trial": the trial is the same one |
| centre hold time | How long the animal stayed in the centre port on a trial's last hold, from the poke to leaving (`Data.CentreHoldTime`); the time asked for is the latency plus `HoldDuration` |
| view | A camera's name, the prefix of its files: `sideview` (24226887), `topview` (24226657) |
| camera clock | SpinCam's host clock: `HostTime_s` in the frame logs, `_events.csv`, `Data.CameraTime` |
| help line | The strip at the foot of a setup or runtime window describing the field under the pointer |
| house light | The white light inside the box, on PulsePal output 3 and looped back into BNC input 1: `S.Session.HouseLight` (behaviour), `S.Sleep.HouseLight` (sleep), `Data.HouseLight`, `Session.HouseLight`; switched from the live figure's header. Not "room light" or "port 5 light" |
| plots image | The online figure saved at the end of a session, `<data file name>_plots.png` (`Session.PlotsImage`) |
| LED current | The Doric driver's current on LED channel 1 (A) or 2 (B), in mA: how bright a channel is while it is gated (`Data.LEDCurrentA`/`B`, `LightSegments.CurrentmA`; asked for as `S.Doric.CurrentmA` on a channel that is not calibrated). Not "LED power" or "intensity" as a stored value |
| light path | One optical channel and the bundle cable on it, with that cable's fibers at the tip (`lum.led.lightPath`) |
| irradiance | Power at the fiber tips over their total area, mW/mm2; what a session asks for on a calibrated light path (`S.Doric.IrradiancemWmm2`, `S.Sleep.TestPulses.IrradiancemWmm2`, `S.Ephys`), turned into the LED current that gives it (`lum.led.intensity`) |
| LED calibration | Power meter readings at several LED currents for one cable on one channel, stored per bundle, cable and channel in `calibration/` (`lum.led`) |
| LED window | The window that shows each channel's LED current during a session and changes it between trials (`lum.gui.DoricWindow`) |
| ePhys calibration | The session type that sends light pulses stepping through intensities and paired-pulse intervals, for the recorded response (`S.Ephys`, D18) |
| input-output curve | Single pulses at intensities from lowest to highest, one step per level (`S.Ephys.InputOutput`) |
| paired-pulse ratio | Pairs of pulses at one intensity, one step per inter-pulse interval (`S.Ephys.PairedPulse`) |

---

## Version history

Settings files are converted when loaded. Analysis code reading older **data** files needs the old
names.

### 0.1 → 0.2 — things say what they are

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

### 0.2 → 0.3 — a broken hold restarts the stimulus

| 0.2 | 0.3 |
|-----|-----|
| runtime `InitiationWindow` (state timer of `WaitForCentrePoke`) | `HoldWindow` (a global timer from trial start, across restarts); converted on load |
| a broken hold always ended the trial (`EarlyWithdrawal` → `ITI`) | `S.Task.OnHoldBreak`: *Restart stimulus* (default, `EarlyWithdrawal` → `WaitForCentrePoke`) or *End trial* |
| — | outcome `HoldNotCompleted` (code 6), series `HoldAttempts`, `Session.Type`, `Barcode.Kind`, `SyncPulses` (sleep) |
| analog `Timestamps`/`TrialNumber` shifted by the barcode | corrected at merge |

### 0.3 → 0.4 — the cue lasts until the stimulus starts

| 0.3 | 0.4 |
|-----|-----|
| states `Cue`, `Cue2`, `Cue3`… (the cue, from trial start) | gone: the cue is on in `WaitForCentrePoke` |
| runtime `PreStimulusHold`, 0.05 s by default; leaving it re-armed the trial unpunished | pre-session `S.Stimulus.Latency` (Stimulus tab), 0 by default; leaving it is a broken hold. State `PreStimulusHold` is entered only when the latency is above 0, otherwise the poke enters `CentreHold`. The runtime setting is retired on load, not converted |
| cue rows `Latency`, `Duration` from trial start; `Cue.CentreLightDuringHold` | cue rows `ThroughStimulus`, `Duration` from stimulus onset; converted on load (the centre light keeps its hold setting, tone and air go off as the stimulus starts) |
| task-event sync low in `PreStimulusHold` | low on the poke: in `PreStimulusHold`, or `CentreHold` without a latency |

### 0.4 → 0.5 — test pulses in sleep sessions

| 0.4 | 0.5 |
|-----|-----|
| sleep block states `Pulse001`, `Gap001`… | `Level001`…: one state per span between edges of the sync line and channels A and B |
| sleep sessions never open PulsePal | they do when test pulses are on, and are refused without it |
| — | `S.Sleep.TestPulses` (filled in, switched off, on load), `SessionData.LightSegments`, `Session.TestPulses`, `Session.DeviceLog.PulsePal` |
| PulsePal connected and stopped | also answers a handshake before a session uses it |
| online panel *By side and light* | *By side*; new *Evidence, u_A vs u_B* and *Side bias* panels |

### 0.5.0 → 0.5.1 — the trial sync pulse works

| 0.5.0 | 0.5.1 |
|-------|-------|
| trial sync pulse from a global timer, overwritten one cycle later (so ~100 µs reached the recording) | the pulse is `TrialStart`'s own state timer; no mode costs a global timer |
| `TrialStart` had a zero timer in every mode | it lasts the pulse in a pulsed mode, zero in task-event mode |
| task-event sync went low on leaving `TrialStart` | the line is held high through `WaitForCentrePoke` until the poke |
| the cue and the stimulus were dropped by `PreStimulusHold`, `HoldBreak` and `CentreHoldResumed` | their levels are written again there (`lum.stim.Component.sustainActions`) |
| — | `S.Task.Variant`, `S.Task.ReverseContingency`, `Session.StoppedReason`, `StimulusSet.BasePLeft` / `.Reversed` |
| habituation was set up by hand | `lum.stageDefaults`: air and no light, applied when the stage is chosen |
| a session that lost the Bpod link froze the protocol | the trials so far are saved, the rig is released, the error is reported |

### 0.5.1 → 0.6.0 — automatic shaping, video, sound checks, help

| 0.5.1 | 0.6.0 |
|-------|-------|
| `S.Task.HoldShaping` Off / Grow hold / Shrink grace / Both | switch `S.Task.AutoShaping` (off by default) and method `S.Task.HoldShaping` (Grow hold / Shrink grace / Both); converted on load: *Off* becomes the switch off with *Grow hold*, any other keeps shaping |
| stage defaults set light and air | also automatic shaping: on for Training, off for Experiment; an Experiment session refuses it |
| a hold stopped growing while the animal withdrew | it steps back one growth step after `HoldStepBackAfter` (10) early withdrawals at one hold; `HoldStart` default 0.2 → 0.1 s (existing settings files keep theirs) |
| — | per-trial `EarlyWithdrawals` and `CameraTime`; `Session.Cameras`, `DevicesAvailable.Cameras`, `DeviceLog.Cameras`; sleep `CameraTime` per block |
| — | `S.Camera` and video through SpinCam into `Session Videos` (D14); Cameras tab with live preview in both setup dialogs; camera window during sessions |
| — | the video stops after the final save (`SessionSaved` event), and a second save adds its summary; default format `avi-mjpeg-mt` (SpinCam 1.2.0 engine, multi-core MJPEG), with a note when a single-threaded format cannot keep up; the help line describes the format chosen; a SpinVideo format without SpinVideo is refused when the devices open; `Session.Cameras.EngineVersion` |
| — | `GUIMeta.<name>.Help` for every runtime parameter; help line in the setup and runtime windows |
| — | **▶ Play** buttons for the session's sounds in the setup dialog (`lum.testSounds`) |

### 0.9.2 → 0.9.3 — the LED to its rating, calibrations added to

| 0.9.2 | 0.9.3 |
|-------|-------|
| each LED channel's limit 700 mA by default (`S.Doric.MaxCurrentmA`), Doric's recommended current for an LED held on | **1000 mA**, the LED's rating and the driver's continuous-mode maximum (the DoricLED package's hard ceiling, unchanged). A settings file holding 700 mA on a channel takes 1000 mA there; any other limit is kept. The driver's front knob must allow 1000 mA too |
| the calibration window started every table at 0–700 mA in 50 mA steps, empty; Fill replaced the currents and cleared the readings | 0–1000 mA in 100 mA steps (`S.Doric.CalibrationCurrentsmA`), with the cable's saved readings on that channel filled in and its saved currents added, so only the empty rows are measured; Fill adds currents and keeps readings; changing the unit converts the powers; Save writes only channels with new readings |
| any two readings made a calibration | a calibration is saved and used only with readings at 4 currents above 0 mA, up to 400 mA or more (`lum.led.checkCoverage`); a saved one with fewer is not used (the channel runs in mA, with a warning), but the window shows it to be added to. A calibration to 700 mA is used to 700 mA under a 1000 mA limit |

### 0.9.1 → 0.9.2 — the mixture spread over the window, sleep probes one channel at a time

| 0.9.1 | 0.9.2 |
|-------|-------|
| the mixture lit each amount in one stretch from stimulus onset (`MixtureLayout` `'onset'`), so the end of the window was always dark, and at the lowest total the light was over within 20% of it | spread over the window in cycles (`'spread'`, new field `MixtureCycles`: 5 on the rig, 2 in the emulator, fewer when the window has too few bins), both channels starting every cycle; `'onset'` and `'centred'` remain. Amounts, rules and ceilings of amounts are unchanged. Settings files keep the placement they have; choosing the family again loads the new defaults |
| mixture groups that rounded to the same light at a coarse bin ran as duplicates, paying either side | refused, naming the two groups (`lum:pattern:generate:groupsTooClose`) |
| sleep test pulses: paired probes on A and B together, every 2 s, for 240 min; the recording lasted as long as the schedule and `S.Sleep.DurationMinutes` was unused | paired probes **alternating** A and B, every 30 s (`S.Sleep.TestPulses.Probe.InterEpochInterval` 30, schedule channels *Alternate A and B*), so no epoch lights both channels, **for as long as the recording** (last step Minutes `Inf`: until the recording ends, which lasts `S.Sleep.DurationMinutes` again; `Session.TestPulses.UntilEnd`). The designer's presets and new steps alternate too. *A and B* is still a step's choice. A settings file holding exactly the old default schedule takes the new one; any other schedule is kept |
| choosing a family kept the bin, so a coarse bin (100 ms in a 0.3 s window) could leave its defaults refused | choosing a family makes the bin finer (10, 5, 2 or 1 ms) when its defaults cannot be drawn in the one set, never coarser (`lum.pattern.familyDefaults`) |

### 0.9.0 → 0.9.1 — LED calibrations per channel, intensity in mW/mm²

| 0.9.0 | 0.9.1 |
|-------|-------|
| a calibration per cable, `DoricLED_<bundle>_<cable>.mat`, used on either channel | per cable **and channel**, `DoricLED_<bundle>_<cable>_<A or B>.mat`: the orange cable on A and on B are calibrated apart. A 0.9.0 file is still read, for the channel it was measured on (`MeasuredOn`) only |
| settings held the LED current (`S.Doric.CurrentmA`, 100 mA), shown as mW/mm² when calibrated | a calibrated channel asks for **irradiance** and the session sets the current that gives it: `S.Doric.IrradiancemWmm2` (behaviour, **8**), `S.Sleep.TestPulses.IrradiancemWmm2` (sleep, **2**); a channel without a calibration uses the mA (`S.Doric.CurrentmA`, `S.Sleep.TestPulses.CurrentmA`, 100). Existing settings files take the new defaults |
| sleep test pulses ran at behaviour's `S.Doric.CurrentmA` | at their own intensity, `S.Sleep.TestPulses` |
| an irradiance outside the calibration was refused | it runs at the most (or least) the channel gives within its limit, with a note (`lum.led.currentFor`) |
| ePhys curve `MinmA`–`MaxmA`, `MaxmA` with no default (refused until typed); pairs at `CurrentmA` 100 | calibrated: `InputOutput.MinIrradiancemWmm2`–`MaxIrradiancemWmm2`, **0–12** (or the channel's most), pairs at `PairedPulse.IrradiancemWmm2` **8**; not calibrated: `MinmA`–`MaxmA` with `MaxmA` NaN meaning the channel's limit, pairs at `CurrentmA` |
| — | `Session.DoricLED.Intensity`: what each channel was asked for and the current it started at (`lum.led.intensity`) |
| the LED window's change was written back as `S.Doric.CurrentmA` | as the irradiance it gave on a calibrated channel, the mA otherwise, and only for a channel that changed (`lum.led.keepIntensity`) |

### 0.8.1 → 0.9.0 — stimulus families that say what the animal tells apart; centre reward again

| 0.8.1 | 0.9.0 |
|-------|-------|
| families *pure*, *sequence* (a motif of joint states in cycles), *occupancy*, *overlap order*, *tiled order*, *hand-drawn*, organised by how a pattern is built | *pure channel*, *mixture*, *sequence* (`count`), *order*, *motifs*, *hand-drawn*, each named by what the animal tells apart; choosing one loads defaults that run on the machine, in the designer and on the Stimulus tab ([`stimulus_family.md`](stimulus_family.md)) |
| generator fields `PureChannel`, `OnFraction`, `Motif`, `DutyCycle`, `SlotWeights`, `NumCycles`, `BPhase`, `AOnFraction`, `BOnFraction`, `Overlap`, `Beta`, `Layout`, `BlockOrder`, `CycleBins`, `PureWidth`, `ShortGuard`, `Phase` | `PureChannels`, `PureFractions`; `MixtureRule`, `MixtureRatios`, `MixtureShareBoundary`, `MixtureShareTotals`, `MixtureDifferences`, `MixtureDifferenceBoundary`, `MixtureDifferenceTotals`, `MixtureLevels`, `MixtureLayout`; `CountSlots`, `CountPairs`, `CountFill`; `OrderDesign`, `OrderCycles`, `OrderOverlap`, `OrderShortOverlap`, `OrderLongOverlap`; `MotifLeftWords`, `MotifRightWords`, `MotifFill`. Settings files are converted on load: the sequence motif becomes two words, the overlap order the guarded cycle, the tiled order the simple order, occupancy the mixture's defaults |
| `nGroups` for every family | only for hand-drawn pulses; every other family's groups follow from its settings |
| continuous mode: a pattern per trial in two categories, *A-led* and *B-led* | a pattern per trial within the family's own groups: new amounts, a new order of the flashes, a random phase |
| `S.Task.GroupPLeft`: one value per group, default `[1 0]` | empty by default, meaning the family's contingency (`StimulusSet.FamilyPLeft`); typed values are kept while the groups stay the same |
| `StimulusSet.SweepName`, `SweepValues` | `Evidence`, `EvidenceName`, `Boundary`, `FamilyPLeft`, `PLeftFromFamily`, `Shortcuts`, `Descriptors.ASegments`/`BSegments` |
| a bin that did not divide the window, or cycles that did not divide the bins, was refused | the bin is adjusted to the window, and fractions of the window are shared out over whole bins |
| — | the single-cue ceilings: how well one cue alone could do, in the designer, the setup dialog, the session log and the data file |
| — | the mixture's relative rules: A's share of the light (mixture ratios A:B) or A minus B, each against a boundary that can move, at roving totals; `Boundary` gains `'line'` with `Slope` and `Intercept` |
| psychometric panel by group or swept parameter; the evidence panel always drew the diagonal | psychometric along the family's evidence; the evidence panel draws the contingency's own boundary |
| centre reward on habituation's first trials only | also **Centre reward again**, in any stage, for `CentreRewardAgainTrials` (10) trials, unticking itself |
| *New trial order* on the Stimulus tab; the seed typed and kept only in the designer | **Seed**, **Randomise trials** and *a new seed for every session* on the Stimulus tab; the seed in the plots' header; `lum.pattern.newSeed` keeps one clock-seeded stream, so seeds drawn in quick succession differ |

### 0.8.0 → 0.8.1 — the End button, LED calibration by pairs, startup times

| 0.8.0 | 0.8.1 |
|-------|-------|
| the console's End button closed the camera window through Bpod (it was one of `BpodSystem.ProtocolFigures`), and could do so inside the window's own timer callback, whose `drawnow limitrate` let the button's callback in; on the rig MATLAB froze, and after Ctrl+C the timer went on calling `lum.gui.CameraWindow.refresh`, off the path | the camera and LED windows are closed by the protocol's teardown, first; the camera window's timer draws with `drawnow limitrate nocallbacks`, stops with its figure (`DeleteFcn`), and stops itself if the window cannot refresh for any reason. The setup dialog's camera preview draws the same way |
| a **Calibrate…** button per channel on the Doric LED tab, for the cable on that channel; currents 0–500 mA | one **Calibrate LED power…** button: a window for the pair of cables on the commutator, one table, On/Off and graph per channel, currents 0–700 mA in 50 mA steps (never above the channel's limit), a line saying which of the bundle's cables are calibrated. Saved calibrations are unchanged (`DoricLED_<bundle>_<cable>.mat`) |
| keys inside the plots (performance, evidence, side bias, reaction time, centre hold) covered data; *Now and next*'s A/B labels ran into its title | every key is one row under its panel's axis label; the A/B key is in *Now and next*'s title; the psychometric panel has a key |
| — | `Data.Session.Startup`: each startup step's time, the dialogs as the operator's, and `lum.dev.open`'s per device; printed as the first trial or block starts |

### 0.7.2 → 0.8.0 — centre reward, retry after a wrong choice, centre hold plot

| 0.7.2 | 0.8.0 |
|-------|-------|
| — | **centre reward** in habituation: `S.GUI.CentreRewardAmount` (1 µL) at the centre port for a completed hold on trials 1 to `S.GUI.CentreRewardTrials` (10), both runtime parameters (*Centre reward* panel, *Trial* tab); state `CentreReward`; per-trial `CentreReward` (µL). Needs valve 2's liquid calibration |
| an unpunished incorrect choice passed through `IncorrectChoice` with a zero timer and ended the trial unrewarded; `PunishCondition` defaulted to 3 (incorrect choice) | not punished, the animal may go on to the correct port and be rewarded: state `RetryResponse`, then `WaitForResponse` again with its timer started anew; per-trial `ResponseRetries`. `PunishCondition` defaults to 1 (none); existing settings files keep theirs. The trial is still scored by its first choice (`Incorrect`, `Rewarded` 1) |
| a noise-only punishment (incorrect choice, or an early withdrawal ending the trial) was cut off by the ITI's stop command on the rig | the punishment state lasts at least `S.Sound.NoiseDuration` when it plays the noise |
| stage defaults: shaping on for Training only | on for Habituation too |
| no centre hold panel; summary gave rewards and water | **Centre hold** panel (time in the port on each trial's last hold, against latency plus hold); the summary gives water as total, side and centre, and the running trial's hold; per-trial `CentreHoldTime` |

### 0.7.1 → 0.7.2 — cables by colour, calibrations per cable

| 0.7.1 | 0.7.2 |
|-------|-------|
| 2-to-19 cables `ch1 fiber` (10 fibers) and `ch2 fiber` (9), fixed on A and B | **blue** (9) and **green** (10), blue on A and green on B by default, either on either channel (`S.Light.Cables`, as for the 4-to-19). A 2-to-19 settings file gets blue and green on load |
| a calibration per channel and cable, `DoricLED_<A or B>_<bundle>_<cable>.mat` | per cable, `DoricLED_<bundle>_<cable>.mat`, used on whichever channel the cable is on: the two LED channels are taken to give equal power at equal current. The calibration records the channel it was measured on (`MeasuredOn`, `MeasuredLEDChannel`, in place of `Channel`, `LEDChannel`) |

### 0.7.0 → 0.7.1 — setup windows that keep updating

| 0.7.0 | 0.7.1 |
|-------|-------|
| in a desktop MATLAB the behaviour setup dialog often (more than half of launches on the rig) showed its first state and took no change after it (tab counts such as *Cue (1 on)*, the trial timeline); the next window in that MATLAB, such as the setup dialog after a cancelled sleep setup, then hung until MATLAB was killed. Not caused by the Doric LED: the 0.6.1 dialog did the same | every window waits for its view to load before its components are added (`lum.gui.Form.waitForView`); 0 hangs in 16 desktop launches. Data format unchanged |

### 0.6.1 → 0.7.0 — the Doric LED, LED calibration, ePhys calibration sessions

| 0.6.1 | 0.7.0 |
|-------|-------|
| the Doric LED driver was set by hand | controlled from MATLAB through the DoricLED package (D17): the protocol connects as it launches, each session puts both channels in external TTL mode at `S.Doric.CurrentmA`, and the LED window changes the current between trials or blocks. Without the package, or with the control off, the driver is used as set by hand |
| — | **Doric LED** tab in every setup dialog: the driver, the fiber bundle and cables (moved from the Light path tab), each channel's current and limit, and **Calibrate…** |
| — | LED calibration per channel and cable (`calibration/`, not tracked by git); a calibrated channel's intensity is shown and typed in mW/mm2 |
| — | per-trial `LEDCurrentA`, `LEDCurrentB`; sleep `LightSegments.CurrentmA`; `Session.DoricLED`; `DeviceLog.DoricLED`; `DevicesAvailable.DoricLED` |
| two session types | a third, **ePhys calibration** (`S.Ephys`, D18): an input-output curve and a paired-pulse ratio, run by `lum.sleep.run`; `Session.Ephys` |
| two barcode markers | a third: `S.Sync.Barcode.EphysMarkerWidth` (300 ms; the sleep marker plus the behaviour marker in older settings files); `decodeBarcode` returns `'EphysCalibration'` |
| 4-to-19 default cables blue on A, green on B | orange on A, blue on B (existing settings files keep theirs) |
| `S.Light.Carrier.Voltage`, `S.Sleep.TestPulses.Voltage` "LED drive" | the TTL level into the driver's inputs (5 V); intensity is the LED current |
| the house light never switched on: firmware v21 does not write an output on its resting voltage alone | `holdVoltage` sends the resting voltage and then the voltage itself (op 79); checked on the rig 2026-09-21, every switch reaches BNC1 |
| sleep validation in one function | `lum.sleep.validateClock` (sync pulses, barcode, drug, cameras) and `lum.sleep.checkTimeline` (light against sync pulses), shared with ePhys calibration |

### 0.6.0 → 0.6.1 — house light, plots image, settings kept, cameras on the sync line

| 0.6.0 | 0.6.1 |
|-------|-------|
| the house light (port 5) was never driven | driven by **PulsePal output 3**, held as its resting voltage, with the line looped back into Bpod's **BNC input 1** (D15). `S.Session.HouseLight` (setup dialog, Experiment tab) and `S.Sleep.HouseLight` (sleep setup dialog) where it starts; the **House light** box in both live figures switches it at once; `Data.HouseLight` per trial or block, `BNC1High`/`BNC1Low` events, `Session.HouseLight` (switches on the camera clock, edges on Bpod's clock). Port 5 is unused. Builds of 0.6.1 before it had `S.GUI.HouseLight` (renamed on load) and drove port 5 from the states, then from a global timer and output override; no data file records the latter |
| PulsePal opened only for sessions with light | opened in every session on the rig, for the house light; a session without light runs without it, with the house light disabled (`Session.HouseLight.Switchable`); `hardware/TestHouseLight` checks the loopback |
| the subject came from `Status.CurrentSubjectName`, empty unless the launch manager's selection changed | `lum.launchSubject`: the launch button's `GUIData.SubjectName`, then the selection, then the data file's folder |
| the plots closed with the session | saved as `<data file name>_plots.png` beside the data file, `Session.PlotsImage`; closing a plot window hides it (D16) |
| the settings file held the settings as Start was pressed | written again at teardown, with runtime changes (D16) |
| Flex2 went to the scope only; `TTL_State` 0 | Flex2 wired to both cameras' Line0 (3.3 V); `TTL_State` carries the barcode and trial pulses; with video, the barcode and sync pulses are widened to what the cameras can read (`lum.sync.fitToCameras`, `Session.SyncFit`) |
| a second rig utility in the same MATLAB refused to run ("A protocol is running"): `RunStateMachine` leaves `Status.BeingUsed` at 1 | `TestHouseLight` and `TestSyncLine` put `BeingUsed` and `InStateMatrix` back when they finish |
| barcode bits 10 / 30 ms, trial and sleep pulses 55 ± 45 ms | defaults 20 / 50 ms and 60 ± 40 ms (existing settings files keep theirs, fitted at session time) |
