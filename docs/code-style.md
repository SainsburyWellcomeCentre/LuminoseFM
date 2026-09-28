# LuminoseFM — Comments, help text and lint

How the code explains itself, how MATLAB shows those explanations, and what keeps them from
drifting. The layout of the repository is in [`repository.md`](repository.md); the conventions for
changing it are in [`../CLAUDE.md`](../CLAUDE.md); the words to use are in
[`naming-and-versions.md`](naming-and-versions.md).

**Contents:** [Getting help at the MATLAB prompt](#getting-help-at-the-matlab-prompt) ·
[Help text](#help-text) · [Comments in code](#comments-in-code) · [Typography](#typography) ·
[Lint and the language server](#lint-and-the-language-server) ·
[What the tests check](#what-the-tests-check) ·
[Where this differs from MathWorks' own help](#where-this-differs-from-mathworks-own-help)

---

## Getting help at the MATLAB prompt

Every file in the repository starts with help text, so MATLAB's own help commands work on all of it.
They need the repository's folder on the MATLAB path or current (it is on this rig's saved path);
`hardware/` and `tests/` need `addpath` too, which a session and `runLuminoseTests` do for
themselves.

| To see | Type | For example |
|---|---|---|
| What a function or class does, its arguments and what it returns | `help <name>` | `help lum.cueTiming`, `help RigConfig`, `help TestSyncLine` |
| The same in the help browser, with the *See also* names as links | `doc <name>` | `doc lum.dev.PulsePal` |
| One method of a class | `help <class>.<method>` | `help lum.dev.PulsePal.holdVoltage`, `help lum.HoldShaping.fullHold` |
| Every file in a package, with its one-line summary | `help <package>` | `help lum`, `help lum.led`, `help lum.pattern` |
| The package's files and sub-packages, as a list | `what <package>` | `what lum`, `what lum.sleep` |
| A class's methods and properties | `methods <class>`, `properties <class>` | `methods lum.dev.DoricLED` |
| Where a name comes from (this repository, Bpod, a toolbox) | `which <name>` | `which lum.version`, `which GetValveTimes` |
| The source | `edit <name>` or `open <name>` | `edit lum.buildTrialSM` |
| Bpod's own functions | `help <name>` | `help BpodTrialManager`, `help AddState`, `help GetValveTimes` |

`lookfor` searches the one-line summaries of functions on the path, but not of files inside a
package (`+lum`): for those, `help lum.<package>` is the list to read. A package's list is built
from each file's first help line, so that line is written to be read on its own.

The design behind the code (decisions D1–D22) is in [`architecture.md`](architecture.md); a
comment that names a decision (`D21`) points there.

---

## Help text

Help text is the comment block straight after a file's `function` or `classdef` line, and straight
after each method's `function` line. MATLAB prints it for `help`, and the help browser shows it for
`doc`.

**The H1 line.** The first line names the file as MATLAB knows it and says what it does, in one
sentence that ends with a full stop and fits on one line (at most 100 characters):

```matlab
function cue = cueTiming(S)
% lum.cueTiming says what each part of the cue does, from trial start to the end of the hold.
```

A file in a package uses its full name (`lum.dev.PulsePal`, `lum.pattern.generate`); a file in the
root, `hardware/` or `tests/` its bare name (`LuminoseFM`, `CheckRig`, `stateMachineTest`). The line
after it is blank (`%`), so the sentence is never cut in half in `help lum`.

**The body**, in this order, each part only where it has something to say:

1. What the file is for and why it works the way it does: the design decision (Dn), the rig finding
   or the Bpod behaviour it answers to. The facts a caller needs, not a narration of the code.
2. Usage, as lines a reader can copy (`%   report = CheckRig;`).
3. `Arguments:`, `Options:` (name/value) and `Returns:` (for a struct, one line per field), each
   entry with its unit.
4. What it errors with, by identifier (`Errors with 'lum:ephys:plan:<reason>'`).
5. `This is a pure function: no hardware, no globals, unit-testable offline.` where that is true.
6. The `See also` line, last: the names a reader goes to next, written as MATLAB writes it, without
   a colon (`% See also lum.buildTrialSM, lum.stim.Component`), so the help browser links them. Only
   names MATLAB can find: a document is cited in the body (`D13 in docs/architecture.md`), never on
   this line. Every file outside `tests/` has one.

A **class** documents its purpose, its modes or subclasses and its usage in the class help, and
each public property with a trailing comment on its line. Each public **method** has its own help:
the first line shows the call and what it does (`% configure() programs both trigger channels for
the given carrier.`), then anything the caller must know (when to call it, what it costs, what it
refuses). A constructor, or a method that implements an interface documented on the base class
(`lum.stim.Component`, `lum.dev.Device`), needs no help of its own.

A **local function** gets one line saying what it returns or does when the name does not already
say it all (`% 'on' or 'off', for the log.`); a helper as plain as `orDash` still gets its line,
because the reader should not have to open it. Test functions are named for what they check
(`testAPulseWiderThanThePeriodIsRejected`) and need no comment unless the reason is not obvious.

**History does not go in help text.** What changed in each release is in
[`naming-and-versions.md`](naming-and-versions.md), and what to watch for in old data files in
[`data-format.md`](data-format.md#reading-older-files). A comment may say why the code is as it is
because of something that happened (`LUMS0014 on 2026-09-25`), when that is the reason.

---

## Comments in code

- **Say why, not what.** `% Kept, because the console's End button clears BpodSystem.Path.Settings
  before the teardown writes the settings back.` is worth its lines; `% Set the path` is not.
- **One comment per step** of a long function, above the code it explains, in full sentences. A
  trailing comment is for a unit, a code's meaning or a one-phrase reason (`% mW/mm2 into mA, per
  channel`).
- **Keep them true.** A change to code updates the comments that describe it, in the same change,
  and a comment found to be wrong is fixed, as a doc statement is. A comment that describes a rule
  another file enforces names that file (`lum.triggerStates`), so a reader can check it.
- **Name things as the glossary does** ([`naming-and-versions.md`](naming-and-versions.md)):
  channel A and B, hold attempt, early withdrawal, light clock. The same word in code, comments,
  windows and docs.
- **Suppressions** (`%#ok<ID>`) only where the message is wrong for this code, with the reason when
  it is not plain from the line (`%#ok<AGROW> % Once, at teardown`). The trial loop never grows an
  array, so no `AGROW` suppression belongs there.
- **Section markers** (`%% Settings`) divide a long script or function into the steps a reader
  follows (`LuminoseFM.m`, `lum.defaultSettings`); a short file needs none. A `%%` line followed by
  a row of dashes heads the groups of local functions in a long file (`%% Pieces ---`).
- No commented-out code, no `TODO` left for later: say it in `docs/architecture.md`, *Open
  questions*, or do it.

---

## Typography

- Lines at most **100 characters**, code and comments alike; comment paragraphs are wrapped at about
  92 so an edit rarely pushes them over.
- **ASCII only** in comments and in text MATLAB prints: a Windows console drops anything else, so
  `help` would lose it (an em dash became nothing in `help lum.dev.PulsePal` under `-batch`). Write
  ` - ` or a colon for a dash, `uL` and `mW/mm2` for units, `section 2.2` for §. Text drawn in a
  figure or a uifigure may use any character (the arrows in the plots are `char(8594)`).
- No Markdown in comments: `help` prints `**bold**` and `*emphasis*` as asterisks. Name a button
  as the window does (the Draw crop button). State wildcards such as `*RewardDelay` are fine.
- British spelling, in identifiers too (`centre`, `colour`, `behaviour`), as in the glossary.
- 4-space indent. In a function file whose functions have no `end`, two blank lines between local
  functions; in a test file, one between tests and two before the helpers.

---

## Lint and the language server

MATLAB's Code Analyzer (`checkcode`) is the closest thing to a compiler MATLAB has: it finds unused
variables, calls that cannot resolve, a variable used before it is set, and code that will fail on
another release. The repository is kept at **zero messages**, so that a new one is a signal.

- `lintTest` runs `checkcode` over every file, and the suite fails on any message.
- The MATLAB extension for VS Code (the MathWorks MATLAB language server) underlines code with the
  same engine: it calls `checkcode(code, '-id', '-severity', '-fix')`
  ([source](https://github.com/mathworks/MATLAB-language-server)). Zero messages here means no
  warnings in the editor. The MATLAB Editor's own warnings are the same messages.
- The repository has zero messages under MATLAB's factory settings too (`checkcode(file,
  '-config=factory')`), so a machine with different Code Analyzer preferences shows the same, and
  `codeIssues` (R2022b and later) reports nothing across the repository.

To check one file or the whole repository by hand:

```matlab
checkcode('LuminoseFM.m', '-id')        % messages for one file, with their identifiers
issues = codeIssues(pwd)                 % every file in the folder and its subfolders
checkcode('+lum/validateSettings.m', '-cyc')   % also each function's cyclomatic complexity
```

**Complexity** is reported, not enforced. The twelve functions above 25 on McCabe's measure are
the ones that sequence many independent checks or steps, such as `lum.validateSettings`,
`lum.mergeSettings`'s conversions, `LuminoseFM` itself, `lum.sleep.run`, `lum.buildTrialSM` and
`CheckRig`; each check in them is a short, commented block, and splitting them would scatter one
rule across files. A new function
that grows past that should be split where it has parts that stand alone.

---

## What the tests check

`helpTextTest` checks what a program can:

- every file starts with help text;
- its H1 line names the file, is one sentence ending in a full stop, fits in 100 characters and is
  followed by a blank help line;
- every file outside `tests/` has a `See also` line, none has `See also:` with a colon, and every
  name of this repository on a `See also` line exists (a file, a class, or a class's method);
- no comment line is longer than 100 characters, comments are ASCII, and none carries Markdown
  emphasis.

Whether a comment is **true**, **needed** and **clear** is for the author and the reviewer. Before a
change is finished, read the comments in the code it touches and the help of every function whose
behaviour it changes, as part of the same change: a comment that no longer matches the code is a
bug in waiting, because the next person trusts it.

---

## Where this differs from MathWorks' own help

MATLAB ships an internal auditor for its own help text (`matlab.internal.help.audit`). Run over this
repository it passes on tabs, trailing spaces and See also lines ending in a period. It also asks
for things this repository does differently, on purpose:

| MathWorks' own help | Here | Why |
|---|---|---|
| H1 starts with the bare name (`%cueTiming ...`) | the full name, `% lum.cueTiming ...` | a package file is called by its full name; `help lum` and `lookfor` read either |
| H1 without a full stop | a sentence with one | the H1 is a sentence, and reads as one in `help lum` |
| `%` then three spaces before help text | `% ` then the text | as the rest of the comments; `help` prints both alike |
| Help lines at most 75 characters | 100, like the code | the code is 100 columns wide; a narrower help would be wrapped twice as often |
| At most 40 lines of help | as long as the file needs | the design modules' help is their documentation (`lum.buildTrialSM` draws the state graph) |
| See also with two to seven names | as many as a reader needs, wrapped under the first | a See also line points where to go next |
