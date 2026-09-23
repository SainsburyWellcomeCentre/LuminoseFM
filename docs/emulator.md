# LuminoseFM — Running without hardware (emulator mode)

The protocol runs **end to end on a machine with no hardware attached** (e.g. a desk PC), so that
task logic, windows, plots and data saving can be developed and tested offline. This is a
first-class requirement, not a debugging aid.

Start Bpod with `Bpod('EMU')`, or use the emulator button on the console, then launch
`LuminoseFM` from the launch manager as usual.

---

## Playing the mouse

The port buttons on the Bpod console poke the ports. A full behaviour trial is three clicks:

1. click the **centre port** to initiate,
2. leave it pressed through the stimulus, then **click it again to withdraw** once the hold is
   over — the response window does not open until the centre port goes low, so this click is not
   optional,
3. click a **side port** to choose.

Clicking the centre port *before* the hold is over breaks the hold: click it once more to restart
the stimulus. With no punishment for incorrect choices (the default), a wrong side port sends the
trial back to the response window: click the wrong port again to leave it, then the correct one to
be rewarded. Bpod forgets the port states at the end of each trial, so expect to click a port
again on the next trial. A sleep session needs no clicks.

Tests play the mouse with `tests/startMouse.m`: a timer that puts scripted pokes into the running
emulated state machine, the way the console's buttons do, without calling `ManualOverride` (see
below).

---

## How the emulator differs from this rig

`Bpod('EMU')` emulates a state machine **r0.7–1.0**, not the r2+:

- **Five global timers, five counters, five conditions** instead of 16/8/16. A pattern with more
  than four stretches of light is refused in the emulator (the hold window always takes one timer)
  and accepted on the rig. Every stimulus family's defaults fit in four; the sequence family, whose
  default is five flashes, loads three slots instead when it is chosen in the emulator
  (`lum.pattern.familyDefaults`).
- **No Flex I/O at all** — so no airflow stream, no sync pulses and no session barcode (it is
  recorded as not sent).
- **PulsePal and the HiFi module are unavailable**, so sound states run silently and no light is
  delivered. The runtime window opens in its reduced, single-page form (Bpod's own parameter
  window, relabelled). The setup dialog's **▶ Play** buttons play through the PC's speakers.
- **The Doric LED is simulated.** With the DoricLED package found, the session runs the package's
  `SimulatedTransport`: the same `doric.LightSource`, answering like the driver and logging every
  command (`Session.DoricLED.Mode = 'Simulated'`, `DeviceLog.DoricLED`), so the Doric LED tab, the
  calibration window, the LED window, `TestDoricLED` and an ePhys calibration session all run.
  Without the package the LED is 'Manual' and the currents in the data are NaN. The LED window's
  first drawing can hold up the emulator's loop for a moment, so the tests that check emulated
  intervals run without it.
- **Cameras are simulated.** With SpinCam found, the session records SpinCam's synthetic cameras
  (640 × 512 frames through the real engine, into real files in `Session Videos`,
  `Session.Cameras.Backend = 'mock'`); without it, no video, logged. Encoding simulated video loads
  the computer, and the emulator runs its states from a MATLAB loop, so expect emulated intervals
  to stretch further with video on. Real cameras can still be previewed on the setup dialog's
  Cameras tab.
- **Light can look late on the console.** The emulator emits no start event for a light segment
  that starts at stimulus onset, so the console never draws it; only segments that start later are
  drawn, and the light seems to arrive some time after the poke. The state machine starts every
  segment at stimulus onset, and the rig is unaffected.
- **Timer cancellation is only partly emulated**: a light segment still waiting for its onset
  starts after an early withdrawal anyway, and the console can leave a cancelled line drawn high.
  The data and the rig are not affected.
- **`LoopMode` is not emulated** — a looping timer fires once and never repeats. This is why no
  stimulus structure is ever put in a looping timer (D1 in [`architecture.md`](architecture.md)).
- **The house light's loopback is emulated.** On the rig PulsePal's output 3 drives the light and a
  copy of the line comes into Bpod's BNC input 1. The emulator has neither, so `NullHouseLight` logs
  each level in PulsePal's device log (`would set ch3 param 17 = 5`) and, while a state machine runs,
  puts the input's edge into it the way the console's BNC input button does — so a switch is a
  `BNC1High` / `BNC1Low` event in the data file, as on the rig, and the console's BNC 1 input shows the
  level. A switch between state machines has no event, as on the rig.
- **Plots are saved as an image** at the end of an emulated session too (`_plots.png` beside the
  data file), and a headless (test) session never writes the settings file.
- **No millisecond time.** The emulator runs states from a MATLAB loop: a state never ends before
  its timer, but may end tens of ms after. Emulated intervals are lower bounds only; exact timing
  is a property of the plan and of the rig.

---

## Sleep and ePhys calibration sessions in the emulator

A sleep or ePhys calibration session runs the same way: it drives BNC1 and BNC2 on the console but no sync line, logs
PulsePal's programming instead of sending it, and records the barcode and every pulse it would
have sent. Because the emulator keeps no millisecond time, emulated intervals are lower bounds.

---

## How it is implemented

The protocol detects emulator mode in exactly **one** place — `lum.dev.open` — which builds real
or null device shims once at startup; for cameras, `lum.dev.openCameras` picks SpinCam's simulated
backend there, and for the LED `lum.dev.openDoricLED` picks DoricLED's simulated driver (the protocol
opens the LED early through `lum.dev.open(rig, S, 'Only', 'DoricLED')`, so this still holds). Every hardware call on a null shim is logged rather than
sent, and the log is written into the data file as `Data.Session.DeviceLog`. Anything else that
must behave differently is told so through `devices.emulated`.

Emulated sessions still produce a complete, correctly structured data file, marked with
`Data.Info.EmulatorMode = 1` so it is never mistaken for real behaviour.

The test suite (`tests/runLuminoseTests.m`) starts `Bpod('EMU')` itself and **refuses to run against
a real state machine**; `emulatorSessionTest`, `sleepSessionTest` and `ephysSessionTest` run whole
sessions this way.
