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
| automatic shaping | Training the animal by its performance: now the centre hold (`S.Task.AutoShaping`, method `S.Task.HoldShaping`); later easier and harder trials. On for Training, never in an Experiment |
| step back | Automatic shaping shortening the hold one growth step after `HoldStepBackAfter` early withdrawals at one hold |
| early withdrawal | Leaving the centre port before the hold is complete, unforgiven (state `EarlyWithdrawal`; `Data.EarlyWithdrawals`) |
| view | A camera's name, the prefix of its files: `sideview` (24226887), `topview` (24226657) |
| camera clock | SpinCam's host clock: `HostTime_s` in the frame logs, `_events.csv`, `Data.CameraTime` |
| help line | The strip at the foot of a setup or runtime window describing the field under the pointer |
| house light | The white light inside the box, on PulsePal output 3 and looped back into BNC input 1: `S.Session.HouseLight` (behaviour), `S.Sleep.HouseLight` (sleep), `Data.HouseLight`, `Session.HouseLight`; switched from the live figure's header. Not "room light" or "port 5 light" |
| plots image | The online figure saved at the end of a session, `<data file name>_plots.png` (`Session.PlotsImage`) |
| LED current | The Doric driver's current on LED channel 1 (A) or 2 (B), in mA: how bright a channel is while it is gated (`S.Doric.CurrentmA`, `Data.LEDCurrentA`/`B`, `LightSegments.CurrentmA`). Not "LED power" or "intensity" as a stored value |
| light path | One optical channel and the bundle cable on it, with that cable's fibers at the tip (`lum.led.lightPath`) |
| irradiance | Power at the fiber tips over their total area, mW/mm2; shown in place of mA once a light path is calibrated |
| LED calibration | Power meter readings at several LED currents for one cable, stored per bundle and cable (not per channel) in `calibration/` (`lum.led`) |
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
