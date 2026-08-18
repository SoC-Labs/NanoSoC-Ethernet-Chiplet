# 51 -- Calibre ERC: power/ground labels

[Back to 48 IMEC signoff results](48-imec-signoff-results-analysis.md) . [index](00-index.md)

> Commands prefixed `make <target>` run from `ASIC/genus-innovus/`.
> Verified on `srv03335` against **Calibre v2023.1_18.8** and **KLayout** (both already
> unlicensed dependencies of this project -- see `scripts/calibre/run_drc.sh` and
> `make logo`), 2026-08-18.

---

## TL;DR

```sh
make erc-preflight                    # tools + deck reachable? no licence taken
make erc-quick ERC_GDS=some/stream.gds   # licence-free klayout text scan, fast triage
make erc ERC_GDS=some/stream.gds         # the real answer: Calibre ERC + klayout, combined
```

or, without make:

```sh
ASIC/genus-innovus/scripts/calibre/run_erc.sh some/stream.gds nanosoc_eth_chiplet_pads
```

Results land in `ERC_RUNDIR` (default `../work/erc_run`, override it -- see
[Two things not to break](#two-things-not-to-break) below):

| File | What it is |
|---|---|
| `calibre_erc.sum` | Calibre's own ERC summary -- rulecheck counts, PATHCHK diagnostics |
| `calibre_lvs.log` | full transcript, incl. the short-isolation report path |
| `*.lvs.rep.shorts` | which nets Calibre found electrically shorted, if any |
| `run.deck` | the assembled deck actually run (foundry body + our substitutions) |

**This did not exist before 2026-08-18.** `ci/signoff.yaml` had no `erc` stage at all
(`grep -c "id: erc" ci/signoff.yaml` gives 0), and the one hard error IMEC's own signoff
run returned in 2026-08-17/18 -- *"No labels found in topcell. At least power/ground
labels are required."* -- is exactly the class of thing nothing local would have caught
before sending a GDS out. This page and `run_erc.sh` are the fix.

---

## 1. What ERC actually checks, for someone new to this

**"Electrical Rule Check" is an overloaded name.** Historically -- and in a lot of what
you'll read about it -- ERC means *general circuit-correctness* checking: floating
gates, gates with no path to a supply, that kind of thing. On the TSMC 65nm deck this
project holds, **that checking has moved out of ERC and into DRC**: rule `PO.R.8`
(floating-gate at SRAM/ROM macro periphery -- see [39](39-po-r8-resolved.md)) is a *DRC*
rule, not an ERC one, per the deck's own changelog.

What is actually left in *this deck's* ERC section, and what `run_erc.sh` exists to run,
is narrower and more specific: **supply labelling and connectivity**. Concretely, does
the layout carry text naming `VDD`/`VSS`/`VDDIO`/`VSSIO` (or whichever names a design
uses), and does the geometry that text sits on actually form a connected net reaching
the devices it's supposed to power. So on this design, **"ERC" effectively means "the
power/ground labelling check"**, not "does the circuit work". Say it that way to anyone
new -- the name alone will mislead them otherwise.

## 2. Why a missing PG label is a real defect, not a cosmetic one

A streamed GDS carries **geometry**, not connectivity. A net's *name* only reaches the
layout side of any downstream tool as literal GDS *text* sitting on top of the metal.
Nothing about a rectangle on a power-grid layer says "this is VDD" -- a human, or
Calibre, or any other tool has to read a text label to know that.

Every tool that runs *after* us -- the foundry's own signoff flow, package/bond-out
tooling, anything that needs to know "which shapes are supply rails" -- **locates power
and ground nets by these labels, not by inference from geometry or position.** A supply
grid with perfect metal and zero labels is, to those tools, an anonymous mesh: present,
routed, electrically fine inside our own database, and *invisible as a supply* to
anything reading the GDS cold. That is exactly what IMEC's ERC found and exactly why it
is a hard error rather than a warning.

## 3. Root cause, and what fixed it

A legacy Innovus GDS-out stream map had `NAME <layer>/PIN` rows (signal-pin text) but no
`NAME <layer>/SPNET` rows (special-net text), so `write_stream` emitted the routed
VDD/VSS/VDDIO/VSSIO grid with **zero text labels** -- the pin/IO signal names streamed
out fine (48 of them: `CLK`, `NRST`, `RMII_*`, `TL_*`, `QSPI_*`, `SWD*`,
`HOSTIO4_P1[*]` -- see section 5.1 below), only the supply grid was silent. The current
toolkit's `ASIC/asic-toolkit/tech/tsmc65/derive.tcl` (`gdsmap_derive`) auto-appends the
missing `SPNET` rows, and the maps actually used to build `fp1505`/`full-20260814`
(`work/tech/gdsout.stream.map`) do contain them. Whether that actually produces labels
in the *output* GDS had never been checked end-to-end before this page -- see section 5.

## 4. How to run it and read the output

### 4.1 The three modes

`run_erc.sh` (full header comment has the complete reference) has three modes:

- **`--check`** -- preflight only. Confirms `calibre` is on `PATH`, the foundry LVS deck
  (ERC is declared *inside* the Calibre nmLVS deck -- there is no separate `.erc` file
  to point at) resolves and is readable, and `klayout` is available. No licence taken.
- **`--quick <gds> [names...]`** -- a **licence-free** structural scan: does the GDS's
  **top cell** carry a text object with this literal string, on any layer? Uses
  klayout, which this project already relies on unlicensed (`make logo`). Fast (~seconds
  even on a 300+ MB stream) and good for triage, but **not authoritative** -- see 4.2.
- **default** (`run_erc.sh <gds> [top]`) -- the real answer. Runs Calibre's ERC for
  real, *and* folds in the klayout structural scan as a **mandatory** second signal, and
  reports both. Takes a Calibre licence. This is what `make erc` runs.

### 4.2 Why the default mode runs BOTH checks, always

This was not a design choice made in advance -- it is a direct consequence of what
happened when this page's author ran the two checks separately against the current
shipping stream (`fp1505`, section 5.2). **Calibre's own ERC reported a clean pass with
zero mention of `VDDIO`/`VSSIO` anywhere in the transcript, while klayout showed those
two names have no text anywhere in the entire GDS hierarchy.** Neither tool was wrong;
they answer genuinely different questions, and this deck's specific wiring makes the gap
between them wider than you'd expect:

- The deck's `PATHCHK` ERC checks (`PATHCHK !POWER`, `PATHCHK !GROUND`) only test for a
  **total** absence of power text or a total absence of ground text. They pass the
  moment **one** power name and **one** ground name resolve -- here, `VDD` and `VSS` --
  regardless of how many *other* declared supply names (`VDDIO`, `VSSIO`) do not.
- The deck's own per-name "no data for layout net name X" signal -- what
  `ASIC/lvs-flow/run_lvs.sh`'s `pg_scan()` reads, and what this script's `pg_verdict()`
  (ported from it, with attribution, in the script itself) also reads -- only ever
  enumerates the **foundry's own internal `VARIABLE POWER_NAME`/`GROUND_NAME` list** (a
  few dozen generic analog/IO supply names). `VDDIO` and `VSSIO` are not members of that
  list, so this signal is structurally blind to them too -- it can say nothing about
  them either way.

So a Calibre-only run can call a stream fully fixed when it is only partially fixed.
klayout alone has the opposite problem: it can only tell you a name has *text*
somewhere, never whether that text actually names *connected* metal (see section 5.3
for a real example where text was present and the net still failed). **Neither
substitutes for the other; the default mode runs both and makes you read both.**

### 4.3 Reading a result

```
== Calibre verdict (PATHCHK POWER/GROUND + the deck's own per-name check) ==
  OK -- Calibre found at least one resolving power name and one resolving ground name...

== Structural cross-check (klayout, ...) ==
  WARNING: NO top-cell text for: VDDIO VSSIO
           (present for the rest of [VDD VDDIO] / [VSS VSSIO].)

== OVERALL: PARTIAL -- Calibre's own checks are clean, but VDDIO VSSIO has/have no
   layout text anywhere. Report this before calling the design PG-clean. ==
```

`OVERALL` is the line to quote. Three shapes it can take:

- **`OK`** -- every declared name resolved on both signals.
- **`PARTIAL`** (exit 0, still worth reading) -- Calibre's own checks are clean but the
  structural scan found at least one declared name with no text anywhere. Not a hard
  failure by design (a name genuinely never routed as a special net is not a defect),
  but never silent -- read which name and decide.
- **`NOT SIGNED OFF`** (exit 4 / `RC_NOPG`) -- at least one side (power or ground) has
  **no** text at all anywhere the checks looked. This is the IMEC failure mode.

## 5. Validation -- does the fix actually work? (measured 2026-08-18)

Three real runs, same script, same deck, same two supply-name lists (`VDD VDDIO` /
`VSS VSSIO` -- `ASIC/genus-innovus/lvs_project.mk:184-185`). No result below is
inferred; every number came from an actual `calibre -lvs -hier -64` invocation or an
actual klayout read of the GDS.

### 5.1 Calibration: the exact GDS IMEC checked

`ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_outputs/`
`nanosoc_eth_chiplet_pads_logo_full_L300.gds` (md5 `7f6214965501c911bd65069378ae911d`,
byte-identical to what IMEC ran):

```
$ make erc ERC_GDS=.../nanosoc_eth_chiplet_pads_logo_full_L300.gds
...
--- WARNING: POWER, GROUND, LABELED or TEXT nets required by ERC operations do not exist.
--- TOTAL RULECHECKS EXECUTED = 6
--- TOTAL RESULTS GENERATED = 0 (0)
  NOT MEANINGFUL -- the layout carries NO power/ground text at all.
  This is the exact IMEC failure mode: "No labels found in topcell."
== Structural cross-check ==
  NO TEXT AT ALL for any declared name, anywhere in the top cell.
== OVERALL: NOT SIGNED OFF ==
```

The independent klayout scan is worth stating in full because it is the sharpest
evidence of the root cause: the top cell carries exactly **48 text objects**, and every
single one is a **signal I/O pin name** (`CLK`, `NRST`, `SWDIO`, `SWDCK`, `QSPI_*`,
`RMII_*`, `TL_*`, `I2C_*`, `HOSTIO4_P1[*]`) -- **zero** are `VDD`, `VSS`, `VDDIO` or
`VSSIO`. The signal-pin labels streamed out fine; the supply grid streamed out silent.
**Both checks reproduce IMEC's exact finding. The flow is calibrated correctly against a
known real-foundry result.**

### 5.2 The current toolkit's promoted build: `fp1505`

`ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads.gds` -- the build
promoted in `ci/signoff.yaml`'s `drc` stage specifically *because* it has zero
rail-to-rail VDD/VSS shorts (Innovus `check_drc`; see section 5.3):

```
$ make erc ERC_GDS=.../fp1505/outputs/nanosoc_eth_chiplet_pads.gds
...
--- TOTAL RULECHECKS EXECUTED = 6
--- TOTAL RESULTS GENERATED = 0 (0)
  OK -- Calibre found at least one resolving power name and one resolving ground name...
== Structural cross-check ==
  WARNING: NO top-cell text for: VDDIO VSSIO
           (present for the rest of [VDD VDDIO] / [VSS VSSIO].)
== OVERALL: PARTIAL ==
```

klayout, independently: `VDD` and `VSS` each have exactly **one** text object in the top
cell, on the M9 text/SPNET layer, at (191.000, 191.000) and (175.000, 175.000) respectively.
`VDDIO` and `VSSIO` have **zero** occurrences anywhere in the *entire* GDS hierarchy --
not merely absent from the top cell; a whole-hierarchy walk over every cell and every
layer found none.

**The SPNET fix works, partially.** It produces real, Calibre-recognised `VDD`/`VSS`
labels where before there were none. It does **not** label `VDDIO`/`VSSIO` on this
build. Whether that is because those two supplies are genuinely never routed as
top-level special nets (a legitimate reason for absent text -- see `run_erc.sh`'s own
`pg_partial_warn()`) or because of something else is **open** --
`ASIC/eth-chiplet/config/design_config.tcl:177-189` separately documents a *different*,
already-identified defect specific to `VDDIO`/`VSSIO`: the vendor IO-driver LEF declares
three pad-cell supply pins as plain signal pins, which the comment says previously left
"the VDDIO/VSSIO special nets empty" outright (no routed special-net geometry at all,
not just no label) and cost 76 DRC records. If that geometry gap is why there's no label
here either, the SPNET map fix cannot be expected to help -- there is nothing for it to
label. **This needs its own follow-up**; this page proves the symptom (no label) with
hard evidence, not the deeper mechanism.

### 5.3 The superseded build: `full-20260814` -- a second, independent finding

Run for completeness (same script, same GDS-shape, same expected result -- it was not):

```
$ make erc ERC_GDS=.../full-20260814/outputs/nanosoc_eth_chiplet_pads.gds
...
--- TOTAL RULECHECKS EXECUTED = 6
--- TOTAL RESULTS GENERATED = 1942 (67413)
  NOT MEANINGFUL -- the layout has no GROUND net at all.
  Invalid PATHCHK request "! GROUND": no GROUND nets present, operation aborted.
== Structural cross-check ==
  WARNING: NO top-cell text for: VDDIO VSSIO
== OVERALL: NOT SIGNED OFF ==
```

klayout shows the identical text picture to `fp1505` -- `VDD` and `VSS` each have one
text object, `VDDIO`/`VSSIO` have none -- **yet Calibre says the GROUND net does not
exist at all.** The short-isolation report explains why:

```
SHORT 1.  VDD - VSS in nanosoc_eth_chiplet_pads
  "VDD" at (191.000, 191.000) on layer "139" SN 1
  "VSS" at (175.000, 175.000) on layer "139" SN 2318
```

`VDD` and `VSS` are electrically **shorted**. Calibre keeps one name for the merged net
(here, `POWER` -- hence `GROUND` reads as entirely absent) and drops the other, exactly
the failure mode `run_erc.sh`'s `pg_partial_warn()`/deck-caveat text describes for a
single missing side. This is **not a new defect** -- it independently reproduces, via a
completely different tool (Calibre LVS short-isolation, not Innovus `check_drc`), the
*already known and already documented* reason `fp1505` was promoted over
`full-20260814` in the first place: `docs/tapeout/43-drc-fp1505.md` section 3 records
`full-20260814` has 4 rail-to-rail VDD/VSS shorts against `fp1505`'s zero. **This ERC
run is a second, independent confirmation of that finding, from a tool path nobody had
pointed at it before.**

One rulecheck in this run also needs a caveat rather than a plain count:
`floating.psub` reported `TOTAL Result Count = 1000 (26067) FAILED PATHCHK IN LAYER
DERIVATION` -- the check itself reports a derivation failure alongside a capped,
non-trivial count. Given the GROUND-net loss just above, treat that 26067 as *evidence
something is badly wrong on this build*, not as a trustworthy violation count in its own
right -- the same "a capped, erroring check is not a measurement" caution this project
applies elsewhere (density windows, DRC saturation).

### 5.4 The answer

**Does the SPNET fix work end-to-end? Partially, and it is now measured rather than
assumed:**

| Build | `VDD`/`VSS` | `VDDIO`/`VSSIO` | Calibre ERC | Notes |
|---|---|---|---|---|
| reference (IMEC's GDS) | no text | no text | NOT SIGNED OFF | reproduces IMEC exactly |
| `fp1505` (promoted) | labelled, resolved | no text anywhere | PARTIAL | SPNET fix works for the core supplies |
| `full-20260814` (superseded) | labelled, but shorted together | no text anywhere | NOT SIGNED OFF | independently reproduces the known 4-short defect (doc 43) |

The core `VDD`/`VSS` labelling gap IMEC actually flagged is fixed on the build that
matters (`fp1505`). The IO-supply (`VDDIO`/`VSSIO`) labelling gap is **not** fixed on
either build, and is now a named, evidenced, open item rather than an "unconfirmed" one
-- see punch-list item 4 in [48](48-imec-signoff-results-analysis.md).

## 6. If Calibre is not available

`run_erc.sh --check` fails fast and names exactly what is missing, without ever
launching Calibre or taking a licence. If it reports `calibre` missing or the deck
unreadable (usually `TSMC_65_HOME` unset -- run through `make erc-preflight`, which
includes `ASIC/common.mk`), you still have `run_erc.sh --quick`/`make erc-quick`: a
licence-free klayout structural scan that will at least tell you which names have *no
text at all* anywhere in the top cell -- read section 4.2 first so you know what that
answer does and does not prove.

## Two things not to break

**1. `ERC_RUNDIR` must land inside the build tree that will actually be graded**, not
beside it. `ci/signoff.yaml`'s `drc` stage note explains why in detail: CI clones the
repository and only ever sees what git tracked or what a build step wrote *into the
build tree*; `ASIC/genus-innovus/work/` is gitignored and disconnected from
`ASIC/eth-chiplet/build/<tag>/`. Point `ERC_RUNDIR` at
`ASIC/eth-chiplet/build/<tag>/work/erc_run` when grading a toolkit build.

**2. The dummy source is deliberately empty and its LVS *compare* is deliberately never
read.** `run_erc.sh` writes a trivial `.SUBCKT <top> .ENDS` as the SOURCE side purely so
Calibre's LAYOUT extraction and the deck's embedded ERC checks can run without a real
post-P&R netlist. The resulting LVS *comparison* against that dummy is garbage (every
layout instance reads as unmatched) -- this is expected, and the script never inspects
it. If you need a real LVS compare, use `ASIC/lvs-flow/run_lvs.sh` instead.

## Gotchas

- `calibre` exiting non-zero (this deck's ERC-only runs typically report Calibre exit
  status `4`, since the source side never compares) does **not** mean the ERC check
  failed -- read the summary, same discipline as `run_drc.sh`.
- The foundry deck's per-name "no data" signal only ever lists the foundry's own generic
  `POWER_NAME`/`GROUND_NAME` variable -- a design-specific supply name absent from
  *that* list (this design's `VDDIO`/`VSSIO`) will never appear there even if it is
  genuinely unlabelled. Trust the structural cross-check for names outside that list.
- Text present is not proof of a real, connected supply net -- section 5.3 is a real
  example of exactly that gap (label present, net shorted to the other supply). Only
  Calibre's own checks see connectivity; klayout only sees text.
