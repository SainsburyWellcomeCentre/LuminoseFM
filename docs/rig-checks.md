# LuminoseFM — Rig checks

What has been checked on the rig itself, and what is still **waiting for someone at the rig**. An
agent can run Bpod, PulsePal, the HiFi module and the cameras when the operator allows it (no animal
in the box), but cannot see the light, hear the speaker, poke a port or move a cable. Checks that
need any of those are listed under *Pending*; run them the next time the operator is at the rig,
and move each one to *Done* with its result and session names.

---

## How to run a check

**Permission.** The operator gives it per request, with no animal in the box. Close nothing of
theirs: if the desktop MATLAB holds COM3 (`serialportlist('available')` lacks it), ask them to close
it. Keep session files out of the data folder (`%TEMP%\LuminoseFM_rigcheck`, subject `FakeSubject`).

**Separate processes.** Run each utility or session in its own `-batch` MATLAB, each ending with
`EndBpod`, so one failure cannot leave a port open for the next.

**Virtual pokes.** Write the state machine's virtual input bytes from a MATLAB timer on a fixed
cycle, as the console's port buttons do: `BpodSystem.SerialPort.write(['V' ch-1 level], 'uint8')`.
Never drive `ManualOverride` from a timer. A timer that watches `BpodSystem.Status.CurrentStateName`,
starts a trial's script when it sees `TrialStart` (or `WaitForCentrePoke` after `ITI`), and writes
only when it pokes, loads the port far less than one writing every cycle (P15's
`rigCheckStrategy.m`, kept in `%TEMP%\LuminoseFM_rigcheck`).

**A headless session.** Set the appdata `LuminoseFM_Headless` and `BpodSystem` up as
`emulatorSessionTest` does, and also do what `RunProtocol` does before a session:
- open the Flex analog file (`BpodSystem.AnalogDataFile`, `Status.RecordAnalog = 1`,
  `Status.nAnalogSamples = 0`) and fill `Data.Analog`'s fields;
- set `ProtocolStartTime` and call `resetSessionClock`.

Otherwise the analog stream's timer writes to an invalid file and nothing is merged.

**Record** every result under *Done* below, with the session names, and move a pending check there
once it has passed.

---

## Pending — needs the operator at the rig

| Check | What it needs | Version |
|---|---|---|
| [P4](#p4-calibrate-the-2-to-19-bundle-091) | the power meter at the 2-to-19 cables; two 4-to-19 points to read again | 0.9.1 |
| [P5](#p5-centre-reward-and-punishments-080) | water at each port, air from valve 4, the punishment noise heard | 0.8.0 |
| [P6](#p6-the-end-button-with-the-camera-and-led-windows-open-081) | the End button pressed in a desktop session | 0.8.1 |
| [P7](#p7-where-the-start-up-time-goes-081) | the startup line of a desktop launch | 0.8.1 |
| [P8](#p8-the-stimulus-families-at-the-fiber-tips-and-centre-reward-again-090) | light at the fiber tips per family; the designer in a desktop MATLAB | 0.9.0 |
| [P9](#p9-the-led-to-1000-ma-and-calibrations-extended-to-it-093) | the driver's front knob; the LED head's temperature | 0.9.3 |
| [P10](#p10-what-094-changed-seen-in-a-desktop-session-094) | a refused reward volume and the hold plot in a desktop session | 0.9.4 |
| [P11](#p11-the-light-playing-on-after-a-short-hold-095) | light at the fiber tips after a short hold (step 1 can run headless) | 0.9.5 |
| [P12](#p12-what-096-changed-in-a-desktop-session-096) | the mouse-drawn crop, crops per session type, the carried hold, the memory after a desktop behaviour session | 0.9.6 |
| [P16](#p16-the-strategy-tab-in-a-desktop-session-0100) | the Strategy tab in the setup dialog and both runtime windows, *Correct for* greying out | 0.10.0 |
| [P17](#p17-the-behaviour-setup-dialog-drawn-whole-on-every-launch-0101) | five launches of LUMS0014 in behaviour, each dialog drawn to its buttons | 0.10.1 |
| [P18](#p18-the-side-poke-sound-and-the-per-mistake-punishment-seen-and-heard-0110) | the side-poke sound heard; the new punishment and side-poke rows in the windows | 0.11.0 |
| [P13](#p13-the-hold-on-the-timing-panel-the-wrapped-header-and-the-summary-plots-098) | the runtime hold, the wrapped header, the teardown's plots on screen, the animal at the new timing (step 4's file checks passed 2026-09-27 and, for 0.9.11's upload, 2026-09-28) | 0.9.8, 0.9.11 |

### P4. Calibrate the 2-to-19 bundle (0.9.1)

The 4-to-19 bundle is calibrated on both channels for every cable, 0–1000 mA (2026-09-23 and
2026-09-24, below). The 2-to-19 bundle has no calibration yet (blue on A, green on B by default): its
sessions run in mA (100 mA). Calibrate it from the Doric LED tab, **Calibrate LED power…**, with the
meter zeroed with the LED off, set to 465 nm. Green on A (4-to-19) still has its 0.9.0 points from 50
to 700 mA with a dark point replaced in software (2026-09-23), extended to 1000 mA on 2026-09-24; the
file's note saying so was lost when it was extended. Re-measure it from 0 mA when convenient. On
black on A the 900 → 1000 mA step (0.635 → 0.724 mW) is 2.4 times the step before it: read 1000 mA
again when it is next on the meter.

Check on the way that **On** and **Off** switch only their own channel, that a lit channel follows
**Next**, and that closing the window switches both off; that the Doric LED tab shows mW/mm² with the
current beside it (8 mW/mm² in behaviour, 2 in the sleep dialog); and see the light at the tips at
those currents.

### P5. Centre reward and punishments (0.8.0)

1. Valve 2 is calibrated (2026-09-24), and on 2026-09-24 valves 1–3 opened for exactly their
   calibrated times (below). Still to see: water at each port at the default volumes (3 µL at the
   sides, 1.2 µL at the centre, valve 2's smallest measurement, from 0.9.4), and air from valve 4.
2. A habituation session with the default centre reward (1.2 µL, trials 1 to 10), playing the animal at
   the ports: water appears at the centre port as each of the first 10 holds is completed, and not on
   trial 11; raising *Centre reward for trials* in the runtime window gives it again from the next
   trial prepared. `Data.CentreReward` is 1.2 (µL) on those trials.
3. A training session, with `Incorrect choice` (*Punishment* panel; *Punish on* and *Punishment*
   before 0.11.0) set to each punishment in turn: with *White noise* and *Timeout + noise* the
   whole burst (`S.Sound.NoiseDuration`, 0.5 s) is heard before the next trial; before 0.8.0 the
   ITI cut it off at once. With *None*, a wrong poke followed by the correct one opens the correct
   valve.

### P6. The End button with the camera and LED windows open (0.8.1)

A behaviour session with video, the camera window and the LED window (the defaults), ended with the
console's **End** button part way through a trial; then the same during a sleep session. MATLAB must
not freeze: both windows close, the command window prints *session ended*, and no `TimerFcn`
error about `lum.gui.CameraWindow` or destructor warning about `lum.SessionRunner` follows. The data
file and `_plots.png` are written. Before 0.8.1 this froze MATLAB (2026-09-22, sessions
`FakeSubject_LuminoseFM_20260922_132416` and `..._135918`, which have no `.mat`).

### P7. Where the start-up time goes (0.8.1)

Start a behaviour session with everything on (light, video, sound) and note the line *LuminoseFM:
ready ... after launch* (also `Data.Session.Startup`). In the one 0.8.0 rig session with video,
opening the cameras to starting the recording took 22 s (SpinCam's `HostClockAnchor` against
`RecordingStart`), which covers the cameras, the house light, the HiFi module and Flex: the line now
splits it. Record it here; it decides what to speed up next.

Headless on 2026-09-24 (no dialogs): ready 22–29 s after launch, of which the Doric LED's connection
took 16.2–16.4 s, the cameras 0.6–2.8 s, the HiFi module 1.3 s, PulsePal 1.0 s and the barcode
2.1–2.5 s. In a desktop launch the LED connects while the operator is in the dialogs, so its share
there is what this check is for.

### P8. The stimulus families at the fiber tips, and centre reward again (0.9.0)

1. From a desktop MATLAB, launch a behaviour session and open the Stimulus tab: choose each family in
   *Family* and open **Design stimuli…**; both windows must keep updating (the desktop-only stall of
   0.7.0 cannot be seen by the test suite). Check the family's line *One cue alone could score at
   most…* appears under the group table.
2. With the LED on and a card (or the power meter) at the fiber tips, run a few trials of each family,
   playing the animal from the console, and compare the light with the designer's preview: the
   sequence family's five 100 ms flashes in a new order each trial, the guarded order's overlaps, a
   motif's three flashes. The state machine side is checked (2026-09-22, below); this is the light.
3. In a Training session, tick **Centre reward again** in the runtime window: water at the centre port
   on the next 10 completed holds, and the box unticks itself after them (needs valve 2's
   calibration, P5).

### P9. The LED to 1000 mA, and calibrations extended to it (0.9.3)

1. Turn the driver's front knob to 1000 mA on both channels: it caps the current whatever USB asks, so
   with it lower the limit of 1000 mA gives less light than the calibration says. The driver reports
   what USB asked for, not the knob, so this cannot be checked remotely.
2. Done 2026-09-24: all eight 4-to-19 cable/channel calibrations go to 1000 mA and rise at every
   step (checked offline, below), which a knob below 1000 mA would have flattened.
3. Hold a channel at 1000 mA for the length of a calibration and check the LED head is not hot to the
   touch. Doric recommends 700 mA for light held on for long; sessions gate the light.
4. A behaviour session asking for more than the 700 mA reading (for example 20 mW/mm² on A) before
   step 2 runs at 700 mA with a note; after it, at the current that gives 20.

### P10. What 0.9.4 changed, seen in a desktop session (0.9.4)

1. In a Training session, type 40 µL as the reward in the runtime window: the console warns that the
   reward stays at the previous volume, and the box shows it again from the next trial. Type 0: the
   next rewarded trial opens no valve (no water, no click).
2. With automatic shaping on, the *Centre hold* plot's asked-for line rises one step after each
   completed hold, not every second trial.

### P11. The light playing on after a short hold (0.9.5)

The emulator shows the state machine's side (`stateMachineTest`, `animalSessionTest`); on the rig the
light's lines survive the states after the hold only because firmware 23 skips a BNC line linked to a
running timer on state entry, and `WaitForLightEnd` relies on a condition on the light clock.

1. With the operator's permission (no animal; an agent can run this headless): an Experiment session
   with *Hold without shaping* *Fixed* and *Fixed hold* 0.2 s, a 1 s window and virtual pokes that leave at 0.3 s and choose at
   0.5 s. From the saved file: every light segment's `GlobalTimer<i>_End` at its planned time after
   `CentreHold`, `WaitForLightEnd` lasting until the light is over, `ITI` after it,
   `Session.TriggerStates` `{'ITI'}`, and `Timing.prepare` well inside the ITI. With video, the
   cameras' `TTL_State` still matched pulse by pulse.
2. At the rig, with a card (or the power meter) at the fiber tips: the same session played from the
   console. Poke, leave after the hold and choose at once: the light carries on to the end of the
   window while the side port is poked and the water is given. Poke and leave before the hold: the
   light stops at once.
3. A Training session with automatic shaping: early trials (0.2 s holds) still show the whole pattern.

### P12. What 0.9.6 changed, in a desktop session (0.9.6)

The pieces are tested under the emulator; these need the desktop MATLAB and the cameras.

1. **Crop with the mouse.** Setup dialog, Cameras tab, **Preview**, **Draw crop**: press on the
   topview picture, drag round the arena, release. The preview shows only the crop and the table's
   Crop column its `x,y wxh`; the help line still follows the pointer afterwards. Type a crop into the
   column: the preview follows. **Full frame** undoes both.
2. **Crops per session type.** Start a behaviour session with a crop, end it; open a sleep session:
   its Cameras tab shows full frame (or the sleep crop last kept). Open a behaviour session again:
   the behaviour crop is back. From the files: `Session.Settings.Camera.Cameras(k).Roi` and each
   `_session.json`'s camera `Settings` (`Width`, `Height`, `OffsetX`, `OffsetY`) match.
3. **Hold carried over.** After a habituation or training session with *Grow hold*, the log's last
   lines say where the next session's hold starts, and the next session's Runtime tab shows it as
   *Hold at start*.
4. **Habituation plots.** Every rewarded side poke is a green dot in *Outcomes*, the header says
   "% of N trials rewarded (M choices)", counting the trials with no choice as not rewarded (0.9.7),
   and reaction times sit on a log axis.
5. **Memory.** Found and fixed on 2026-09-26 (see *Done*). In the next desktop session, from the
   launch manager: the log's last lines say `BpodSystem is no longer listed in the base workspace`,
   the Workspace panel is empty, MATLAB stays responsive after the session, and
   `<data file>_memory.csv` stays flat (about 2 GB) for its 4 minutes. `EndBpod` still works.

### P13. The hold on the Timing panel, the wrapped header, and the summary plots (0.9.8)

1. From a desktop MATLAB, open a behaviour session's setup dialog. On the Task tab set *Hold without
   shaping* to Fixed and *Fixed hold* to 0.3: the Runtime tab's *Trial* column, *Timing* panel shows
   the same two values, and changing them there changes the Task tab's. Change the stimulus window on
   the Timing panel: the Stimulus tab's *Duration* follows. The dialog must keep updating (the
   desktop-only stall, 0.7.1).
2. In a habituation session, watch the runtime window's header: *rewarded, chose left*, never
   *correct*; a long line (a stepped-back hold, a centre reward) wraps rather than running off the
   window. In a Training session with shaping off, change *Fixed hold* in the runtime window's
   *Timing* panel mid-session: the *Centre hold* plot line and the header's *hold* follow from the
   next trial prepared (the next trial, or the one after when the next was already prepared).
3. End the session with the End button. The console says *writing its summary plots and log* and then
   where they went; note how many seconds it took (the line after it). Open `Session Plots` and
   `Session Logs` beside `Session Data`, and look through one of each.
4. **The 0 s ITI.** The file and camera checks passed on 2026-09-27 (0.9.9) and again on
   2026-09-28 with 0.9.11's upload during the trial (*Done*): from the file, every trial after the
   first starts (`TrialStartTimestamp(k+1)`) 0.1 ms after the previous one's end
   (`TrialEndTimestamp(k)`), except the trial after one with `Timing.devices` above 0. With *Task
   events* sync and video, each camera's `TTL_State` is low for at least two frames between a
   `NoInitiation` and the next trial's rise. What is left is at the rig, with the animal: it is not
   hurried by it (the drinking grace still ends each rewarded trial); the command window shows no
   *inter-trial dead time* box; the LED window reads *waiting to be sent between trials* after
   **Apply** until the current is sent.

### P16. The Strategy tab in a desktop session (0.10.0)

In a desktop MATLAB (emulator or rig, no animal): the setup dialog's Runtime tab shows four tabs'
panels in three columns (Delivery under Task) with every label readable; choosing *Experiment* on
the Task tab sets *Bias correction* 0, *Max same side in a row* 0, *Correct for* *Side bias*,
*Reward floor* 0, *Trial order* *Random* and *Side poke before the response* *Ignore*; *Correct for*
greys out when `Incorrect choice` (*Punishment* panel) is *None* and comes back with any other,
in the setup dialog, the tabbed runtime window (at once, on choosing) and Bpod's compact window
(from the next trial). In a session: a side poke while the cue is on switches it off for the delay.

### P18. The side-poke sound and the per-mistake punishment, seen and heard (0.11.0)

At the rig, no animal. The state machine side was checked by an agent on 2026-10-08 (*Done*); what
needs a person:
1. The setup dialog's Cue tab, *Sound output*: *Side-poke sound (s)* 0.15 with its **Play** button
   gives a short noise burst, shorter than the punishment noise's **Play**.
2. The *Punishment* panel shows four rows (`Incorrect choice`, its timeout, `Early withdrawal`, its
   timeout) and the *Side pokes* panel two more (`Side poke in a timeout`, `Sound on a side poke
   that costs time`), labels readable, in the setup dialog's Runtime tab, the tabbed runtime
   window and Bpod's compact window.
3. In a session with `Incorrect choice` *Timeout* 2 s, *Restart the timeout* and the sound on,
   playing the animal at the ports: a wrong choice, then a poke at the other side port within the
   2 s, plays the burst and the next trial starts 2 s after that poke; a poke back into the port
   just chosen plays nothing and restarts nothing. With *Side poke before the response* *Delay*, a
   side poke before the centre poke plays the burst and switches the cue off.

### P17. The behaviour setup dialog drawn whole on every launch (0.10.1)

From Bpod's launch manager on the rig, no animal: launch LUMS0014 five times and choose
*Behaviour*. Each time the setup dialog must draw every tab up to *Runtime* and the *Cancel* and
*Start session* buttons, then close with *Cancel*. Do the same once for FakeSubject. A dialog that
stops part way means the freeze of 2026-10-06 is still there. Note the launch, and whether the LED
had finished connecting.

## Done

### 2026-10-08 — 0.11.0, side pokes in a timeout and each mistake's punishment, on the rig, no animal, fibers terminated, run by an agent with the operator's permission

No other MATLAB running, COM3 free. Behaviour sessions headless in `-batch`, LUMS0014's settings
file as the base (read, not written), files in `%TEMP%\LuminoseFM_rigcheck`, subject
`FakeSubject`, virtual pokes from a timer watching `Status.CurrentStateName` (P15's way;
`rigCheckRestart.m` and `rigCheckRestartReport.m` in that day's agent scratchpad). Hold window 6 s,
response window 3 s, ITI 0.25 s, no video. Version `0.11.0+65de755` (uncommitted).

| Check | Result |
|-------|--------|
| LUMS0014's settings file converted | `PunishCondition` 3, `PunishType` 1, `PunishTimeout` 3 became `Incorrect choice` *Timeout* 3 s and `Early withdrawal` *None*: its punishment as run on 10-08 |
| `_162108` (16 trials): both mistakes a 1 s timeout, *Restart the timeout*, the side-poke sound on, *Delay* 1 s | After a wrong left choice, a poke back into the left port 0.3 s later restarted nothing (`IncorrectChoice` ran on); the right-port poke ended `IncorrectChoice` at that poke (to 0.1 ms) and started `IncorrectChoiceRestartRight`; a left poke 0.5 s later moved to `IncorrectChoiceRestartLeft`, which ran its full 1.000 s and ended the trial (trials 1, 5, 9). Early withdrawals likewise: `EarlyWithdrawal` cut at the right poke, `EarlyWithdrawalRestartRight`, then `...Left` for the full 1.000 s, then the next poke and a choice (trials 2, 6, 10, 14). Pokes during a rewarded trial's drinking grace restarted nothing (trial 13). Side pokes before the centre poke: 1.000 s delays. `TimeoutRestarts` 2 on each restarted trial; every trial rescored to what was saved; every gap between trials 0.1 ms, no dead time warning; `prepare` at most 0.19 s. The state machine took the HiFi play commands (HiFi on COM8); the sound itself not heard (P18). Log: *Punishment: incorrect choice timeout 1 s, ends the trial; early withdrawal timeout 1 s* |
| `_162425` (8 trials): LUMS0014's settings as converted | `IncorrectChoice` 3.000 s, no restart, *Delay* 3 s; every gap 0.1 ms; rescored as saved; log *incorrect choice timeout 3 s, ends the trial; early withdrawal none* |

### 2026-10-06 — the behaviour setup dialog freezing part way (0.10.0 → 0.10.1), desktop MATLAB on the rig PC, no Bpod, run by an agent

The operator reported that the behaviour setup dialog hung for LUMS0014 (no *Runtime* tab, no
*Cancel* or *Start session*) but not for FakeSubject. No MATLAB was running when the checks began;
no COM port was opened. Each subject's settings file was copied out of the data folder, merged,
cropped and seeded as `LuminoseFM` does, and the dialog opened after `lum.gui.SessionTypeDialog`
with DoricLED's simulated driver, connected.

- `-batch`, visible or not, with or without the LED: both subjects' dialogs built every time
  (3–11 s), validation *Ready to start*. The two files differ only in values the operator set.
- Desktop MATLAB, one opening after another: 5 of 33 froze, LUMS0014 and FakeSubject alike. The
  window showed three or four tabs and no buttons, its title bar greyed out; MATLAB sat at 0% CPU.
  Logged build steps showed every component added (to the *Start session* button) in 3–4 s, and
  MATLAB then waiting in the `drawnow` after the build for over 30 s.
- With `drawnow` after the header and each tab: 0 of 24. With the 0.10.1 code (`drawnow
  nocallbacks` after each): 0 of 24. Opening takes about 1 s longer.
- Not checked: the launch from Bpod's launch manager with the real LED (P17).

### 2026-10-05 — P15, strategy correction (0.10.0) on the rig, no animal, fibers terminated, run by an agent with the operator's permission

No other MATLAB running, COM3 free. Behaviour sessions headless in `-batch` (LUMS0014's settings
file as the base: pure channel A or B, 0.3 s window and hold, 20 Hz carrier, jittered sync; hold
window 4 s, response window 3 s, ITI 0.25 s; files in `%TEMP%\LuminoseFM_rigcheck`, subject
`FakeSubject`), poked by a timer that watched `Status.CurrentStateName` and wrote `'V'` bytes only
to poke (`rigCheckStrategy.m` and `rigCheckReport.m` in that folder). Version `0.10.0+676ff9a`
(uncommitted).

| Check | Result |
|-------|--------|
| Part 1, *Delay* 1 s, `_163026` (16 trials, a side poke before the first centre poke or between attempts on half of them) | 8 delays, each 1.0000 s; the trial went on to a choice every time; every gap between trials 0.1 ms; no dead time warning; no state machine error codes; every trial through `WaitForLightEnd`; every trial rescored to what was saved |
| Part 1, *End trial*, `_163315` (15 trials, a side poke 0.2 s into every third) | 5 trials ended `SidePokeBeforeChoice` (outcome 7), unrewarded, with no timeout (early withdrawals not punished). Every gap 0.1 ms but one, 3.1 ms with one dead time warning, after trial 10: a trial ended 0.45 s after it started is shorter than the loop's work while it runs (the trial before's plot, about 0.2 s, and the next trial's preparation, 0.08–0.25 s). A quick early withdrawal under *End trial* does the same; a punishment timeout covers it |
| Part 1, blocks of 3–5, `_163529` (24 trials) | Blocks of 3, 4, 3, 5, 3, 3 and 3 (cut by the session's end), sides alternating, `CorrectSide` = `BlockSide` on every trial, `BiasTargetPLeft` 1/0, `BiasContext` NaN; every gap 0.1 ms; log lines *Strategy correction*, *Habits*, *Blocks*, *By group (trials outside blocks ...)*; 15 summary plots |
| Part 2, context correction, *Last choice and reward*, strength 0.5, floor 40%, timeout 1 s, with video, `_163952` (30 trials) | Every gap 0.1 ms; `awaitChoice` median 2.6 s; `prepare` after the choice median 37 ms, at most 151 ms; the 30 contexts as recorded all equal those computed from the file's choices and rewards |
| Part 2, the same at a 0 s timeout, `_164309` (30 trials) | One gap of 36 ms with one dead time warning (a 163 ms build inside the 0.25 s ITI), as the validation note says. **12 of 30 contexts recorded as none** where the trial before was an unrewarded choice: a 0 s `IncorrectChoice` passed inside one of `BpodTrialManager`'s 10 ms batches, unseen by `CurrentStateName`. Fixed: while choices are read live, `IncorrectChoice` lasts at least 50 ms (`lum.BiasCorrection.ReadableState`), and `DrinkingGrace` and `WithdrewBeforeReward` also say the side outside habituation |
| After the fix, `_164800` (30 trials, 0 s timeout) | Every context equals the file's; every gap 0.1 ms; no warning |
| MATLAB's time per trial | `Timing.build` (the state machine) is the slow part of `prepare`: median 4–95 ms across sessions, at most 238 ms; `sync` at most 71 ms, `spec` at most 26 ms. The 0.4–0.55 s preparations of LUMS0014's sessions were not reproduced here |

The videos of the two context sessions (about 1 GB) are in that folder's `Session Videos`. Not seen:
an animal under any lever, and the windows on screen (headless; the Strategy tab is P16).

### 2026-10-05 — P14, light or sound the mouse could sense without the bulb, operator at the rig

Checked by the operator, no animal, after LUMS0014's session of 2026-10-05 (the light then 20 Hz ×
20 ms at 12 mW/mm², A 409 mA, B 893 mA). With the box dark, no blue light leaked from the cables,
the commutator or the ferrule, and the LED driver made no sound while the channels pulsed. So the
pulse locking in `docs/learning-time-literature.md` (*Do the pulses reach the mouse?*), if it is
real, does not come from light escaping outside the bulb or from the driver's sound.

### 2026-09-28 (evening) — the 0.25 s ITI and SpinCam 1.3.0 on the rig, no animal, run by an agent with the operator's permission

No other MATLAB running, COM3 free, SpinView closed. Behaviour sessions headless in `-batch` as in
the entry below (LUMS0014's settings of that day, virtual pokes, video, files in
`%TEMP%\LuminoseFM_rigcheck`), each LED change made from the LED window (`startLEDRequest`):

| Check | Result |
|-------|--------|
| The settings file's 0 s ITI (0.9.8's default) | Converted on loading: `GUI.ITI (the 0.9.8 default, 0 s, became the new one: 0.25 s ...)`, `Session.SettingsVersion` filled in |
| `FakeSubject_LuminoseFM_20260928_165901`: 40 trials at 0.25 s, A's current changed twice (from trials 12 and 27) | All 39 gaps 0.1 ms; no dead time warning. `Timing.devices` 120.1 and 91.2 ms on trials 11 and 26 only, inside the ITI; every `ITI` state lasted `TrialSettings{k}.ITI`. LED A 253 → 95 → 42 mA from those trials. No missed-deadline codes; 40 light timers exact; 40 trial pulses on both cameras (residuals ≤ 6.0 ms) |
| `FakeSubject_LuminoseFM_20260928_170356`: 20 trials at 0 s, one change | The change's trial 10 started 103 ms late with one warning after the console's *trial 10 waits for its LED current* line, as designed. **Trial 2 also started 153 ms late**: trial 1's prepare + upload (102 ms) plus the time to notice, so trial 2 had been prepared after trial 1 ended. `BpodTrialManager.getCurrentEvents` learns its trigger states only when first called; trial 1's `TrialStart` (29 ms, the shortest of the sessions) had already been left when it was. Fixed: `lum.SessionRunner.awaitPrepareWindow` polls `BpodSystem.Status.CurrentStateName` |
| After the fix, `_170849` and `_171130` (12 trials each at 0 s, one change) and `_171407` (15 at 0.25 s, one change) | At 0 s every gap 0.1 ms, trial 2 included, but the change's (107.4 and 99.4 ms, one warning each). At 0.25 s all 14 gaps 0.1 ms, no warning, the change 123.7 ms. No missed-deadline codes; light timers exact; trial pulses on both cameras |
| MATLAB's time per trial | Uploads during a trial reached 241–380 ms three times in these sessions, under the virtual-poke timer writing to the state machine's port 50 times a second (LUMS0014's session that day: at most 213 ms). An upload of an LED change's trial has so far taken ≤ 124 ms |
| The ITI warnings on screen (desktop MATLAB, emulator) | The setup dialog's alert and status-line note on typing 0 in *Inter-trial interval*; the tabbed runtime window's floating warning over the session, which goes on. The text named a stimulus-window change, which cannot happen mid-session (the window is fixed; the runtime window only shows it): reworded to the LED current |
| SpinCam 1.3.0, `runTests('hardware')` | 128 of 128, the 10 hardware tests on both cameras included; `spincam.tools.probeCameras` afterwards: full frame and the 640×640 behaviour crop, 100.058 Hz, trigger off, FRAME_INFO `0x87FF0000`, as before |

Not seen: the animal at the new timing (P13 step 4), and the 128 s correction on a real camera
(about one an hour; the next long session's log names any).

### 2026-09-28 — LUMS0014's first session with light audited, and 0.9.11's upload during the trial on the rig, no animal, fibers terminated, run by an agent with the operator's permission

**The session** `LUMS0014_LuminoseFM_20260928_123501` (Training, 333 trials, 0.9.10) was audited
from its files: everything in it held (the numbers are in `naming-and-versions.md`, 0.9.11) but
two things. Every trial after the first started 9–351 ms (median 196 ms) after the one before
ended, with no state machine running, and `BpodTrialManager` warned of the dead time 332 times: the
next trial was prepared in the ITI. The topview camera's hardware clock stepped forward by 128 s
twice (SpinCam's; `docs/python-analysis.md`). 0.9.11 prepares and uploads the next trial as each
trial starts, and holds back only an LED current or PulsePal program, until the trial's end.

**On the rig** (no other MATLAB running, COM3 free), after the suite's affected files passed under
the emulator:

| Check | Result |
|-------|--------|
| Behaviour session `FakeSubject_LuminoseFM_20260928_153508`, headless `-batch` (files in `%TEMP%\LuminoseFM_rigcheck`): LUMS0014's settings of that day (4-to-19, orange on A 253 mA and blue on B 496 mA, pure channel A or B, 0.5 s, 20 Hz carrier, jittered sync, video), hold window and response window 3 s, ITI 0 s; virtual pokes on a 4 s cycle from a timer writing `'V'` bytes (every 6th cycle an early withdrawal first, every 7th none); channel A's current changed from the LED window (`startLEDRequest`) once 10 trials were recorded | Ran its 30 trials under `BpodTrialManager` with `TriggerStates` `{'WaitForCentrePoke'}`: 11 correct, 12 incorrect (retried to the reward), 6 `NoInitiation`, 1 `HoldNotCompleted`. Version `0.9.11+25a5601` |
| The gap between trials | 28 of 29 were 0.1 ms, one state machine cycle. Trial 12, the first at the new LED current, started 22.9 ms after trial 11 ended (`Timing.devices(11)` 19.8 ms): the only *inter-trial dead time* warning of the session, after the console's line naming trial 12 |
| The light while the next trial uploaded during it | No trial has a state machine error code (missed deadlines); all 27 `CentreHold` visits started the light timer one cycle later, every completed hold's light lasted 0.5000 s, every broken hold's ended with the withdrawal |
| The LED | A 253 mA on trials 1–11, 95 mA from trial 12 (the request halved the typed irradiance), B 496 mA throughout; the driver's record has the change tagged trial 12 |
| MATLAB's time per trial | prepare 112 ms (median; up to 424), send 21 ms, plot 232 ms: all while the trial ran |
| Cameras | 11,977 frames each, none missed; both decoded barcode `0CAEA84B` as Behaviour, and 30 trial pulses for 30 trials, within 6.0 ms of `TrialStartTimestamp` after a straight-line fit, widths within one frame of `SyncPulseWidth` |

Not seen: the windows on screen (headless), and the animal at the new timing (P13 step 4).

Later the same day, at the operator's request: the default ITI became 0.25 s and device changes
moved into the ITI (0.9.11; on the rig that evening, entry above), SpinCam 1.3.0 takes the 128 s steps out
(its unit and integration tests 118/118; `spincam.io.readFrameLog` repaired LUMS0014's topview log
of that day: 2 steps), and the rig-check folder's videos and extras were deleted (17 GB; the
session `.mat` files kept).

### 2026-09-27 — 0.9.9's plots on the rig and P13 step 4, no animal, fibers terminated, run by an agent with the operator's permission

The operator was away from the rig. First the whole suite under the emulator: 602 of 603 passed
(the usual SpinCam skip), no lint messages, including the two new rendering tests (every title,
label and key of the live figures inside the window, none running into another). Then, in
separate processes on COM3 (no other MATLAB running, COM3 free):

| Check | Result |
|-------|--------|
| `CheckRig` (`-batch`) | 11 of 11 ok: r2_Plus, firmware 23, 16 global timers; HiFi1 on COM8; Flex analog in and sync out; PulsePal; Doric LED; liquid calibration 14.4 / 13.1 ms for 1 µL |
| Behaviour session `FakeSubject_LuminoseFM_20260927_215021` in a **desktop** MATLAB (files in `%TEMP%\LuminoseFM_rigcheck`): Training, light on both channels (2-to-19, uncalibrated: 100 mA), video, *Task events* sync, ITI 0 s, hold window 3 s, tabbed runtime window, LED and camera windows open; 96 virtual pokes from a timer writing `'V'` bytes (the timer draws nothing) | Ran to its 24 trials in 130 s under `BpodTrialManager`: 10 correct, 3 incorrect, 11 lapses (`NoInitiation`); 13 holds completed, 9 of them at the first attempt. Version recorded `0.9.9+267e103`. The online figure saved at teardown (`_plots.png`) and the 12 summary plots and log are drawn in the 0.9.9 scheme with every label inside; summary plots and log took 18.5 s (150 dpi) |
| MATLAB's time per trial | prepare 123 ms, send 32, plot **231** (LUMS0014's 0.9.7 session: 236), save 38 (medians): the 0.9.9 plots cost no more |
| P13 step 4, the 0 s ITI | Every trial started 11–338 ms after the one before ended (median 176 ms), 16 ms (median) more than that trial's prepare + send; none lost or late. `BpodTrialManager` printed its *inter-trial dead time > 500 µs* warning 23 times: expected with a 0 s ITI in a session with light (CLAUDE.md, *The ITI is 0 s*) |
| Cameras | 10,630 / 10,631 frames, none missed or dropped; both decoded barcode `0CADAEBA` as Behaviour; every `NoInitiation` (20 ms, two frame periods) followed by the line low for at least 3 frames before the next trial's rise; the only 2-frame low runs are the barcode's bits |
| Flex analog | 100,253 samples merged |

Not seen: the windows on screen during the rig session. The operator's remote-desktop session
disconnected part way (`qwinsta`: `Disc`, the lock screen up), so screenshots were blank; the
windows kept drawing, and `_plots.png` is the online figure as drawn. An emulated session in a
desktop MATLAB earlier the same evening was watched on screen (CLAUDE.md, *Tests and validation*).

### 2026-09-26 — "Out of memory" after a session found and fixed (0.9.7), no animal, run by an agent with the operator's permission

LUMS0014's sessions of 2026-09-25 and 2026-09-26 ended normally, then MATLAB committed ~180 GB and
printed "Out of memory." two minutes later. Reproduced on the rig in a desktop MATLAB launched by
the agent: headless habituation sessions as `FakeSubject` (files in `%TEMP%\LuminoseFM_rigcheck`),
virtual pokes, ended by `RunProtocol('Stop')` from a timer as the End button does, then MATLAB left
at the prompt with the memory sampler (`lum.watchMemoryAfterSession`) running. Peak private memory
in the minute or minutes after the session:

| Run | What differed | After the session |
|-----|---------------|-------------------|
| r1 | 5 min, 42 trials, all devices and video | 3 → **141 GB** in 5 min, still climbing (stopped) |
| e1 | emulator, 1 min | flat, 1.3 GB |
| b1 | `Bpod('COM3')` only, no session | flat, 1.1 GB |
| r3 | 2 min, all devices | 15 GB within 20 s |
| r2, r13 | 2 min, `BpodSystem` cleared from the base workspace before the prompt (r13: another variable there instead) | flat, 1.8 / 1.6 GB |
| r4, r6, r7, r8, r9 | 2 min, `BpodSystem` kept but `Data.Analog`, `Data`, the analog port, half, then nearly all of its properties emptied | 10–17 GB, over in 25–45 s |
| r10, r11 | 2 min, video off; then video and the Doric LED off | 17.6 / 27.5 GB |
| r12, r15 | cleared and declared again before the prompt; hidden during the session and declared again after | 27.7 / 26.4 GB |
| r14 | stacks of the busy thread sampled (`dbghelp` `StackWalk64`) | every sample in `datatools_view_core.dll` / `mwwsb_startup_impl.dll` (`workspace_browser_startup`, `PubSubDSImpl::sizeUpdated`, `WSViewModel::updateStatsSettings`): MATLAB's Workspace browser |
| **r16** | **r1 again (5 min, 42 trials, all devices and video) with the fix** | **flat, 1.85 GB for 3 min** |
| s1, s2 | sleep, test pulses (alternating probes), video; s1 ran its 3 min, s2 stopped at 2 min; fix | flat, 1.74 / 1.81 GB for 2 min |
| p1, p3 | ePhys calibration, defaults (16 steps, 0–1000 mA on A in mA, 2-to-19 uncalibrated), video; p1 ran to its end, p3 stopped at 1.5 min; fix | flat, 1.75 / 1.77 GB |
| s3, p2 | sleep and ePhys stopped at 2 min, `BpodSystem` put back in the base workspace (no fix) | flat, 1.8 GB: blocking sessions did not trigger it in this time |

Cause: MATLAB R2025b's Workspace browser, after a session, works through the session's changes to
the `BpodSystem` object listed in the base workspace, taking memory in proportion to the session's
length. It came with rig behaviour, which runs through Bpod's trial manager (a 10 ms timer updating
`BpodSystem`); sleep and ePhys sessions, emulated behaviour and `Bpod()` alone did not trigger it.
Fix: every session's last step removes `BpodSystem` from the base workspace (D16). Not yet seen: a
launch from the launch manager (P12).

The sleep and ePhys files were checked as well:

| Session | Result |
|---------|--------|
| s1 `FakeSubject_LuminoseFM_20260926_194942` (sleep, 3 min, ran to its end) | 18 blocks; 180 of 180 sync pulses, 20–99 ms, 1.00–1.26 s apart; 12 of 12 gates, 10 ms, A and B alternating, pairs 50 ms apart every ~30 s, 100 mA (2-to-19 uncalibrated: mA); `TestPulses.Completed` 1; analog 184 s; both cameras 18,818 frames, none missed, barcode `0CAC40FF` read as Sleep, 180 of 180 pulses, widths within 10.2 ms (one frame), onsets within 5.4 ms |
| p1 `..._200431` (ePhys, defaults, ran to its end) | 16 blocks = 16 steps; 160 sync pulses; 240 of 240 gates, 5 ms on A; each step's gates at its asked current: input-output 0, 143, 286 … 1000 mA, then pairs 20–500 ms at 100 mA; `Ephys.Completed` 1; both cameras 16,784 frames, barcode `0CAC4466` read as EphysCalibration, 160 of 160 pulses within one frame |
| s2 `..._195554`, p2 `..._201006` (stopped at 2 min, before 0.9.7's `StoppedBlock`) | 9 blocks each, `Completed` 0, `StoppedReason` empty; the cameras logged 4 and 3 sync pulses after the last recorded one: the block running at the stop, recorded nowhere. Led to `Session.StoppedBlock` |
| p3 `..._202123` (ePhys stopped at 1.5 min, with `StoppedBlock`) | 6 blocks recorded, `StoppedBlock` = block 7 (step 7, 10 pulses 1 s apart, 10 gates at 857 mA), `BlockStopped` in `_events.csv` 0.98 s after block 6 ended; both cameras logged 1 pulse after the recorded ones, 41 ms wide against the first planned 47 ms |


### 2026-09-24 — pre-deployment validation (0.9.4), no animal, fibers terminated, run by an agent with the operator's permission

The operator was away from the rig. Everything below was driven over the devices' own ports; nothing
was seen, heard or touched. Session files in `%TEMP%\LuminoseFM_rigcheck`, not the data folder. The
full report is `docs/validation-2026-09-24.md`.

| Check | Result |
|-------|--------|
| Machine | r2_Plus on COM3, firmware 23, 16 global timers, 8 counters, 16 conditions; Flex types [2 1 1 4] (analog in, sync out); HiFi1 paired on COM8 |
| `CheckRig` | 11 of 11 ok (liquid calibration: 14.4 / 13.1 ms for 1 µL on valves 1 / 3) |
| Port sensors | Port1, Port2, Port3 read clear (no animal), through state-machine conditions |
| Valves, one opening each | Valve1 26.60 ms (3 µL asked: 26.64), Valve2 14.70 ms (1 µL: 14.72), Valve3 25.60 ms (3 µL: 25.60), Valve4 100 ms; port LEDs PWM1–3 200 ms each. The state machine ran each for its time; water not seen (P5) |
| `TestHouseLight('Count', 2)` | 4 of 4 switches reached BNC1, 20–34 ms |
| `TestDoricLED` at 496 mA, one flash each | Device mode, external TTL, 3 of 3 gates, every command acknowledged |
| `TestHiFiSound` | 4 kHz tone loaded and played (not heard) |
| Behaviour session `FakeSubject_LuminoseFM_20260924_150202`: mixture (spread, 10 timers), orange A / blue B at 8 mW/mm², video, jittered sync, 6 trials of virtual pokes | LED 253 / 496 mA on every trial; **60 of 60 light segments within 0.10 ms** of plan; **6 valve openings within 0.035 ms** of the calibrated time of the volume each trial records; TrialStart = `SyncPulseWidth` within 0.05 ms; holds exact; analog 34 419 samples; **both cameras decoded barcode `0CA95A85` (Behaviour) and logged all 6 trial pulses** within one frame (−4.7 to +5.5 ms); 3850 frames each, none dropped |
| Sleep session `FakeSubject_LuminoseFM_20260924_150528`: 1 min, default test pulses | 4 of 4 gates: pairs on A (42 mA = 2.00 mW/mm²) then B (73 mA = 2.01), 10 ms, 50 ms apart, 30.2 s between pairs; 60 sync pulses; both cameras decoded the Sleep barcode and logged 60 of 60 pulses (within 9.7 ms, one frame) |
| ePhys session `FakeSubject_LuminoseFM_20260924_150658`: A and B, input-output in 4 levels, pairs 20 / 50 ms | 6 steps, 32 of 32 gates; the driver acknowledged each step's currents: A 0 / 96 / 254 / 409 mA and B 0 / 189 / 498 / 893 mA for 0.05 / 4 / 8 / 12 mW/mm², pairs 253 / 496 mA; every gate's recorded current is its step's; EphysCalibration barcode and 6 of 6 pulses on both cameras |
| Behaviour `..._151150`: fixed-width sync, grow hold 20% | holds 0.1, 0.1, 0.12, 0.144, 0.1728 s (one step per completed hold, 0.9.4), `CentreHold` exact; pulses 50.0 ms on Bpod, 50.1–50.5 ms on camera |
| Behaviour `..._151247`: task-event sync, 0.2 s latency, a break in every latency | the line high from trial start to each poke and again on each restart: 10 of 10 high periods on camera within 8.4 ms of the states |
| BNC input 1 read through a condition | reads the **inverted** level: a condition `BNC1` = 1 is true with PulsePal OUT3 at 0 V, false at 5 V, while `BNC1High`/`BNC1Low` events follow the voltage. Nothing in LuminoseFM uses a BNC condition |

### 2026-09-23 — orange on A and blue on B re-measured, operator at the rig with the power meter

The 0.9.0 per-cable files for three light paths read light with the LED off (0.67–1.25 mW/mm² at 0 mA),
and two had a lit point out of line with the other cables on their channel: orange on A at 50 mA
(0.030 mW, where the other A cables read 2.24–2.65 mW/mm²) and blue on B at 100 mA (3.14 mW/mm², the
other B cables 2.10–2.65). Green on A had only the dark point off: it was replaced by the mean dark
reading of the re-measured A cables (1.25 → 0.04 mW/mm²; `DoricLED_4-to-19_green_A.mat`, noted in
the file); its lit points are as measured. Orange on A and blue on B were measured again in full: the
agent set each current in continuous mode through `lum.dev.DoricLED.lightOn` (one channel lit, the
other off), the operator read the meter (zeroed, 465 nm) and typed each value, and the agent switched
both channels off and released the driver at the end.

| mA | 0 | 50 | 100 | 150 | 200 | 250 | 300 | 350 | 400 | 450 | 500 | 550 | 600 | 650 | 700 |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| orange on A, mW | 0.002 | 0.093 | 0.164 | 0.222 | 0.267 | 0.311 | 0.364 | 0.430 | 0.462 | 0.513 | 0.54 | 0.592 | 0.626 | 0.667 | 0.703 |
| blue on B, mW | 0.002 | 0.0645 | 0.0956 | 0.135 | 0.165 | 0.198 | 0.221 | 0.249 | 0.271 | 0.292 | 0.316 | 0.337 | 0.362 | 0.379 | 0.404 |

Both rise at every step; 50 mA on orange A (2.37 mW/mm²) and 100 mA on blue B (2.43) now sit with the
other cables on their channels, and each cable's B/A ratio is 0.52–0.73, as for the others. The
defaults now run at: sleep 2 mW/mm² → orange A 42 mA (was 69), blue B 73 mA (was 67); behaviour
8 mW/mm² → 253 mA (was 235) and 496 mA (was 457). Saved as `DoricLED_4-to-19_orange_A.mat` and
`..._blue_B.mat`; the 0.9.0 per-cable files are kept but no longer used for these paths.

### 2026-09-23 — 0.9.2, the 4-to-19 calibrations, the spread mixture and alternating sleep probes, no animal, run by an agent with the operator's permission

Bpod r2+ on COM3 (16 global timers), PulsePal firmware v21 on COM9, the Doric driver in Device mode
("LED Driver", Doric port 4), HiFi1 on COM8, Flex1 analog and Flex2 sync. No video (checked before).
Bundle 4-to-19, orange on A and blue on B (the defaults). Session files in `%TEMP%\LuminoseFM_rigcheck`,
not the data folder.

**The calibrations** (`calibration/`, read offline). All eight cable/channel pairs of the 4-to-19
bundle resolve to a calibration: black on A and B, blue on A, green on B and orange on B from 0.9.1
files; blue on B, green on A and orange on A from the 0.9.0 per-cable files, each measured on that
channel. Every curve rises with current, and irradiance is power over the cable's area (4 or 5 fibers
of 100 µm). **Channel B gives about 58% of channel A for every cable**: 10.5–10.6 mW/mm² at 700 mA on
B, 17.5–18.6 on A. The cables agree with each other on each channel, so the difference is the LED
channel or the commutator, not the cables. B needs 457–520 mA for 8 mW/mm², and the ePhys curve's top
(12 mW/mm²) is out of reach on B (it runs at 10.6, with a note). The three 0.9.0 files had an offset
at 0 mA, since corrected, and two have a suspect lit point: P4. The table below is as the sessions
ran, before the correction.

| Cable | A: mA for 2 / 8 mW/mm², most at 700 mA | B: mA for 2 / 8 mW/mm², most at 700 mA |
|-------|:---:|:---:|
| black | 38 / 233, 17.5 | 70 / 504, 10.5 |
| blue | 44 / 236, 18.6 | 67 / 457, 10.6 (0.9.0 file, offset) |
| green | 25 / 227, 18.3 (0.9.0 file, offset) | 94 / 511, 10.5 |
| orange | 69 / 235, 17.9 (0.9.0 file, offset) | 85 / 520, 10.5 |

| Check | Result |
|-------|--------|
| `CheckRig` | 11 of 11 ok |
| `TestDoricLED('Currents', [50 250], 'Count', 2)` | every command acknowledged, 12 of 12 gates (A, B, both at each current). Light not watched |
| Behaviour session `FakeSubject_LuminoseFM_20260923_132857`: mixture at its new defaults (spread over 5 cycles, 10 timers), Experiment stage, 6 trials, virtual pokes | the console printed *LED channel A 235 mA = 8 mW/mm2, channel B 457 mA = 8 mW/mm2*; `LEDCurrentA` 235 and `LEDCurrentB` 457 on every trial, `Intensity.ReachedmWmm2` [8.00 8.00]. **All 60 light segments (10 per trial) had a timer start and end at the planned times, within 0.10 ms.** Ready 26.4 s after launch, 16.2 s of it waiting for the Doric driver |
| Sleep session `FakeSubject_LuminoseFM_20260923_133000`: the new default test pulses (paired probes alternating A and B, 30 s), shortened to 2 min | LED A 69 mA = 2.02 mW/mm², B 67 mA = 2.01 (P4 for A). 8 of 8 gates: pairs on A, B, A, B, 50 ms apart, 10 ms each, never both channels in one epoch; epochs 30.24, 30.19 and 30.05 s apart, each interval longer by the time between the ~10 s blocks it spans (D13) |
| ePhys calibration session `FakeSubject_LuminoseFM_20260923_133226`: A and B, input-output in 4 levels, pairs 20 and 50 ms | 32 of 32 gates, completed. The LED stepped A 0, 110, 247, 398 mA and B 0, 184, 393, 700 mA (B's top level at its most, 10.6 mW/mm², with a note), then 235 / 457 mA for the pairs, between blocks; every gate's recorded current is its step's. The lowest level reads 0.67 mW/mm² at 0 mA because of the 0.9.0 orange and blue offsets (P4) |

### 2026-09-22 — 0.9.0 stimulus families on the state machine, no animal, run by an agent with the operator's permission

Bpod r2+ on COM3 (16 global timers), PulsePal firmware v21 on COM9 (connected, outputs stopped,
handshake answered, programmed for each session), Flex2 sync (barcode sent each session). No sound, no
video; the Doric LED left as set by hand (`S.Doric.Enabled` off), so this checks timing, not light
(P8). One headless behaviour session per family at its defaults (Experiment stage: 1 s window, 1 s
hold), 4 trials each, the animal played by virtual input events written to the state machine's serial
port (`'V'`, what the console's port buttons send), every 5 s from the first trial: centre poke, 1.35 s
hold, leave, left poke, right poke. Session files written to `%TEMP%\LuminoseFM_rigcheck`, not the data
folder, and not kept.

A trial *matches* when each light segment of its pattern has its `GlobalTimer<k>_Start` at the
segment's onset after the last `CentreHold` entry, and its `_End` at onset plus duration, within 1.5 ms.

| Family (defaults) | Segments per pattern | Trials with a hold | Matching | Worst difference |
|-------------------|:---:|:---:|:---:|:---:|
| Pure channel | 1 | 4 | 4 of 4 | 0.10 ms |
| Mixture, compare | 2 | 4 | 4 of 4 | 0.10 ms |
| Sequence, 5 flashes in a new order each trial | 5 | 4 | 4 of 4 | 0.10 ms |
| Order, guarded cycle, random phase | 3 | 4 | 4 of 4 | 0.10 ms |
| Motifs | 3 | 4 | 4 of 4 | 0.10 ms |

Every session reached its first trial 5–7 s after launch (`Session.Startup`), printed its family and
its single-cue ceilings, and ended with Correct or Incorrect on every trial (a wrong left poke was
followed by the right one, as the script plays both). With 4 trials the ceilings are the session's own
(the mixture's amounts read 75%, not the 67% of a full session, because 4 trials cannot cover 6
groups evenly).

### 2026-09-21 — P1, P2 and P3, operator at the rig, run by an agent (0.7.1)

| Check | Result |
|-------|--------|
| P1 `TestHouseLight('Count', 5, 'On', 2, 'Off', 2)` | the operator saw the house light on for 2 s five times; 10 of 10 switches reached BNC1, 19–32 ms after each command (median 25 ms) |
| Desktop launches of the protocol by the operator (0.7.1) | behaviour setup: the cue count and trial timeline follow a cue tick at once; launch → sleep → cancel → launch → behaviour opens and updates (where MATLAB hung in 0.7.0) |
| P3 sleep session with test pulses and the LED window, channel A's current changed mid-session | the operator saw the brightness change from the next block |
| P2 `TestDoricLED('Currents', [20 100 300], 'Count', 3)` | the operator saw A flash, then B, then both, brighter at each current; LED in Device mode ("LED Driver", Doric port 4), 27 of 27 gates, every command acknowledged. The first attempt stopped before sending anything: Bpod connected on COM3 but `BpodSystem.HW.n` was never filled in, straight after the P1 run had released the port. It ran after the state machine and PulsePal were power-cycled |

### 2026-09-21 — 0.7.0 → 0.7.1, setup windows hanging in the desktop, run by an agent with the operator's permission

The operator reported that the behaviour setup dialog did not update (the *Cue (1 on)* count, the trial
timeline) and that MATLAB hung at the next window after a cancelled sleep setup. No animal; Bpod in
emulator mode throughout (no COM ports).

- Doric driver, real, through DoricLED's bridge: three cycles of connect, sleep setup dialog, cancel, close,
  connect again, behaviour setup dialog, cancel, close, headless. No hang: each close took 0.7–1.8 s, and the
  dialog updated on a cue click (0.04–0.12 s). The driver was still *Connecting* 7 s after each connect
  (INIT and OPEN wait up to 5 s each), so a dialog opened straight after launch shows that state.
- Desktop MATLAB, no LED at all: the behaviour setup dialog was fully drawn but its view never confirmed the
  next update, so `drawnow` did not return, in more than half of the launches; the 0.6.1 code did the
  same (2 of 3). The cause was not a component, the axes toolbars, Bpod's console or a timer. It happened
  when the window's view finished loading while components were still being added. With `lum.gui.Form.waitForView` (0.7.1):
  0 of 16 hung, the type → sleep (cancelled) → type → behaviour sequence included.

### 2026-09-21 — 0.7.0, no animal, run by an agent with the operator's permission

Bpod r2_Plus, firmware 23, COM3; PulsePal firmware v21 on COM9; Doric LEDFLS_465_465 ("LED Driver",
Doric port 4) through DoricLED's bridge; HiFi1 on COM8; both cameras. The operator had replaced the
BNC cable from the house light's splitter into Bpod's BNC input 1 beforehand.

| Check | Result |
|-------|--------|
| `CheckRig` | all 11 checks ok, the Doric LED included |
| `TestHouseLight` (5 switches, 1 s) as in 0.6.1 | 0 of 10 switches reached BNC1 |
| Every Bpod input read directly (`'I'` command) while PulsePal OUT3 was driven | resting voltage (parameter 17) 5 V: BNC1 stays 0. A software-triggered 5 V train on OUT3: BNC1 reads 1. OUT4 reaches no input. **The cable is right; the resting voltage alone never changes the output.** Firmware v21 (`PulsePal_2_0_1.ino`) stores parameter 17 and calls `dacWrite()` without setting that output's `DACFlags`, so the DAC is not updated until a stop or abort kills the channel |
| Parameter 17 then op 79 (`SetPulsePalVoltage`) | BNC1 follows at once; the level survives op 82 (stop, every output) and op 80 (abort). 10 op 79 in 134 ms. `lum.dev.PulsePal.holdVoltage` now sends both |
| `TestHouseLight` (5 switches, 1 s) after the fix | **10 of 10 switches reached BNC1**, latency 18–33 ms (median 28 ms) |
| `TestDoricLED('Currents', [50 200], 'Count', 3)` | connected in the background, both channels in external TTL mode at 50 mA, then 200 mA; every command acknowledged; PulsePal gated with constant light; 18 of 18 gates ran (A, B, both). Light not watched: P2 |
| Behaviour session `FakeSubject_LuminoseFM_20260921_133846`: 4 trials, no animal (each lapsed), LED A 80 mA, B 120 mA | ran and saved; `LEDCurrentA` [80 80 80 80], `LEDCurrentB` [120 120 120 120]; `Session.DoricLED.Mode` Device; the driver released at teardown |
| Sleep session `FakeSubject_LuminoseFM_20260921_133929`: paired probes on A and B every 1 s, 15 s, LED 60 mA | 60 of 60 gates, each `LightSegments.CurrentmA` 60; schedule completed |
| ePhys calibration session `FakeSubject_LuminoseFM_20260921_134051`: A and B, input-output 0–200 mA in 4 levels, paired pulses 20/50/100 ms at 100 mA, 3 repeats, 0.5 s apart, video at 100 Hz | 7 steps, 60 of 60 gates, completed. The LED stepped 0, 67, 133, 200 mA, then 100 mA, between blocks; every gate's recorded current is its step's. **Barcode `0CA552FB` decoded from both cameras' `TTL_State`, kind EphysCalibration**, and all 11 sync pulses logged; 1863 / 1862 frames, none dropped |

One MATLAB process ended in an access violation (0xc0000005) during the first attempt at these
sessions, which stopped at a validation error in the test settings; no crash dump was written, and
the same path, closing the LED while it connects (six times), and the three sessions then ran without
it. If it happens again, note what was running and look for `matlab_crash_dump.*` in `%TEMP%`.

### 2026-09-17 — 0.6.1, no animal, run by an agent with the operator's permission

Bpod r2_Plus, firmware 23, COM3; PulsePal firmware v21 on COM9; HiFi1 on COM8; both cameras.
Sessions were headless (`LuminoseFM_Headless`), with subject `FakeSubject`.

| Check | Result |
|-------|--------|
| `CheckRig` | all 10 checks ok |
| `TestSyncLine('Drive', 'states', 'Barcode', true)` | ran after `TestHouseLight` in the same MATLAB (this needed the fix below) |
| Behaviour session `FakeSubject_LuminoseFM_20260917_111703`: 15 trials, light, sound, jittered-width sync, video at 100 Hz | both cameras: 3588 / 3587 frames, none dropped, missed or incomplete, queue peak ≤ 2. **Barcode `0C9FEB37` decoded from each camera's `TTL_State`**, kind Behaviour, and **all 15 trial pulses logged**. Widths match Bpod's within one frame (−5.4 to +8.4 ms), and so do intervals (≤ 6.9 ms) |
| Sleep session `FakeSubject_LuminoseFM_20260917_112004`: test pulses (probes A and B, a train alternating A and B, probes A), video, analog | 5 blocks. **Barcode `0C9FEBEA` decoded from both cameras**, kind Sleep, and **all 32 sync pulses logged**. Widths match within one frame (−7.5 to +8.3 ms), and so do intervals (≤ 6.5 ms). 102 of 102 light gates sent, schedule completed. Analog stream merged. Frames: 3761 each, none lost |
| House light, both sessions | 5 and 6 switches recorded on the camera clock (`_events.csv`) and in `Session.HouseLight.Switches`, and `Data.HouseLight` follows them. **No BNC1 edges: see P1** |

Fixed during the check: `RunStateMachine` leaves `BpodSystem.Status.BeingUsed` at 1 after a
run outside a protocol, so a second rig utility in the same MATLAB refused to start ("A protocol is
running"). `TestHouseLight` and `TestSyncLine` now put `BeingUsed` and `InStateMatrix` back when they
finish.

