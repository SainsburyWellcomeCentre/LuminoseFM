# LuminoseFM — Architecture

Design plan for the LuminoseFM protocol. Status: **decisions 1 and 2 confirmed**,
implementation not started. Update this file whenever the architecture changes.

---

## Confirmed decisions

### D1 — Bpod owns the pattern envelope, PulsePal owns the carrier

**Decision.** An optogenetic stimulus is split across the two devices by what each is
good at:

- **Bpod global timers** define the *spatiotemporal pattern* — which of BNC1/BNC2 is
  high, when, and for how long, using one-shot timers with `OnsetDelay` + `Duration`
  and `'Channel', 'BNC1'|'BNC2'`. Several timers can be started at once from a single
  state via `GlobalTimerTrig` with a bit mask.
- **PulsePal** defines the *carrier waveform* — 20 Hz train, pulse width, voltage —
  with both trigger channels in **gated mode**, so `OUT1`/`OUT2` pulse exactly while the
  corresponding Bpod BNC line is high.

A/B, overlapping A+B, and arbitrary A/B sequences are then all expressible as sets of
one-shot timers, with no MATLAB code in the timing path.

**Why this split and not the alternatives.**

1. *Timing stays in hardware.* The pattern is compiled into the state machine and
   uploaded before the trial starts; nothing in the stimulus path depends on MATLAB
   loop latency or USB scheduling.
2. *Composition is orthogonal.* Pattern (which channel, when) and waveform (how it
   pulses) vary independently, which is exactly how the GUI presents them. PulsePal only
   needs reprogramming when waveform parameters change — not per trial, and not per
   pattern.
3. **The emulator reproduces the envelope but could not reproduce a timer-built carrier.**
   `RunBpodEmulator.m` implements global timer triggering, onset delay, end events and
   channel setting, but **does not implement `LoopMode`** — a looping timer fires once and
   never repeats. Building a 20 Hz carrier from looping Bpod timers would therefore run
   correctly on the rig and silently differently under `Bpod('EMU')`, which breaks the
   emulator-first requirement (README §4.3). With this split, the emulator reproduces the
   full pattern structure faithfully and only omits the carrier — the part that has no
   hardware to drive offline anyway.
4. *Event budget.* A carrier built from looping timers would emit two events per pulse
   into the trial's event stream (or need `SendEvents = 0`, losing the timestamps). The
   envelope emits a handful of events per trial, all of them meaningful.

**Consequences / constraints.**

- 16 global timers is the hard ceiling on pattern complexity: one timer per contiguous
  ON segment per channel. Segment-count validation belongs in the pattern designer, not
  at trial-build time.
- PulsePal reprogramming happens only in the inter-trial window, never mid-stimulus.
- Non-uniform trains stay available via `SendCustomPulseTrain` (≤5000 pulses) without
  changing this architecture.
- **Gotcha:** `ProgramPulsePalParam(ch, 128, value)` passes the value straight to the
  firmware, which uses `0 = normal, 1 = toggle, 2 = gated` — the function's own header
  comment says `1/2/3` and is off by one. Send **2** for gated, and confirm on hardware
  at bring-up.
- PulsePal time values must be multiples of the 100 µs cycle.

### D2 — Two-tier GUI, split by when a parameter may legally change

**Decision.**

1. **Pre-session setup** — a custom `uifigure` shown once, before the trial loop:
   experiment metadata, training stage, contingency, cue/stimulus composition, the
   pattern designer, PulsePal waveform parameters. It writes a validated settings struct
   `S`, saved through Bpod's per-subject settings file mechanism
   (`.../LuminoseFM/Session Settings/<name>.mat`).
2. **Runtime `BpodParameterGUI` tabs** — only parameters that are safe to change with an
   animal in the box: reward amount, response window, centre-hold duration, timeouts,
   bias correction, LED intensity, stimulus on/off. Synced once per trial in the
   prepare step.

**Why.** `BpodParameterGUI` handles scalars, checkboxes and popupmenus well, and its
`GUITabs`/`GUIPanels` mechanism is enough for the runtime tier. It has no sensible
representation for a pattern schedule (a channel × segment matrix), and every field it
owns is editable at any moment — which is wrong for parameters that must be constant
within a session for the data to be interpretable. Splitting by mutability makes that
constraint structural instead of a convention the operator has to remember, and makes
the whole pre-session configuration reproducible as a single saved settings file.

**Consequences.**

- Pattern definitions are frozen at session start and stored once in the data file; trials
  reference them by index (README §4.4).
- The setup dialog is the natural place for validation (segment count vs. timer budget,
  overlap rules, `duration(A+B) ≤ duration(A)+duration(B)`), so trial building can assume
  a valid schedule.
- Both tiers must work under `Bpod('EMU')`.

---

## Phased plan

### Phase 0 — Rig config, device shims, preflight
- `hardware/RigConfig.m` — the single source of truth for the channel map (ports 1–5, BNC
  1–2, Flex 1–2, module names). Nothing else hard-codes `PWM3` or `Valve1`.
- `+lum/+dev/` — HiFi, PulsePal and Flex behind interfaces, each with a real and a null
  implementation, selected **once** at startup on `BpodSystem.EmulatorMode`. No other file
  tests for emulator mode.
- `hardware/CheckRig.m` — preflight asserts (modules present, Flex config matches, PulsePal
  reachable, calibration files exist), all skipped in EMU.
- Outstanding rig config: Flex2 → digital output for the sync TTL; PulsePal added to the
  MATLAB path.

### Phase 1 — Trial engine
Fixed state graph, identical across stimulus modalities:

```
TrialStart → Cue → WaitForCenterPoke → CenterHold(stimulus) → [EarlyWithdrawal]
           → WaitForResponse → {Reward | Error} → Drinking/Timeout → ITI → exit
```

State *names* never change; only `OutputActions` and global timers do. Online plots,
`LiveOutcomePlot` configuration and downstream analysis all depend on this contract.

- `+lum/buildTrialSM(S, trialSpec, rig)` — assembles the state machine.
- `+lum/nextTrialSpec(S, history)` — pure function (trial type, contingency, bias
  correction, training stage), unit-testable with no hardware.

### Phase 2 — Stimulus components
`+lum/+stim/` with a common interface — `configure()` (inter-trial device programming) and
`outputActions()` / `addGlobalTimers()` (state machine contributions). Implementations:
`OptoPattern`, `Sound` (HiFi), `PortLight`, `Air`. Cue and Stimulus are each a *list* of
components, which is how arbitrary combinations are supported without touching the state
graph. Pattern schedules come from the designer (D2) as a validated channel × segment
struct.

### Phase 3 — Session loop
`BpodTrialManager`: `getCurrentEvents` → build trial *n+1* → `SendStateMachine('RunASAP')`
→ `getTrialData`. All per-trial work (PulsePal programming, plot update, saving) happens
inside that window. Per-trial timing (`prepare`/`send`/`plot`/`save` ms) is recorded into
the data file so lag regressions are visible rather than felt.

### Phase 4 — GUI
As decided in D2.

### Phase 5 — Online plots
One `+lum/OnlinePlots.m` owning a single figure (`tiledlayout`), registered in
`BpodSystem.ProtocolFigures`. Handles created once and updated via `set(h,'XData',...)`,
fed from an incrementally maintained `sessionStats` struct (never recomputed from `Data`),
per-panel throttling, one `drawnow limitrate` per trial. Panels per README §4.5.

### Phase 6 — Data
Save policy per README §4.4: session-level dictionary written once, small per-trial
records, interval saving, `Data.Info.EmulatorMode` flag, `AddFlexIOAnalogData` merge after
the session, metadata sidecar for downstream analysis.

### Phase 7 — Tests
`tests/` covering the pure functions (trial generation, bias correction, pattern
validation) and a short `Bpod('EMU')` smoke session, runnable from WSL via
`matlab.exe -batch`.

---

## Open questions

- Sync TTL: pseudo-random train generated per trial as a global timer, vs. a free-running
  train — depends on what the acquisition devices need for alignment.
- Doric LED control (`DoricSystemDLL`): separate package on the MATLAB path, or part of
  this repo. Deferred.
