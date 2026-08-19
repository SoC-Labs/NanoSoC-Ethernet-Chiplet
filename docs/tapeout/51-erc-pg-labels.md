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
| `run_erc.log` | **NEW 2026-08-18** -- `ci/signoff.yaml`'s `erc` stage tees the whole run_erc.sh transcript here, because that is where its `OVERALL:` verdict line lives (see section 6) |

**This did not exist before 2026-08-18.** `ci/signoff.yaml` had no `erc` stage at all
(`grep -c "id: erc" ci/signoff.yaml` gives 0), and the one hard error IMEC's own
signoff run returned in 2026-08-17/18 -- *"No labels found in topcell. At least
power/ground labels are required."* -- is exactly the class of thing nothing local
would have caught before sending a GDS out. This page and `run_erc.sh` are the fix.

**UPDATE, same day, later:** the VDDIO/VSSIO gap section 5 measured as "open" is now
root-caused, fixed, and validated -- see section 5.5 and section 6. The one-line
version: the LEF pin-type defect this page originally pointed at (and the promotion
plan named as still outstanding) turned out to be **already fixed and working**. The
actual, still-open defect was a completely different line in a completely different
file: `ASIC/genus-innovus/scripts/power_plan.tcl` never routed VDDIO/VSSIO at all --
every `add_rings`/`add_stripes`/`route_special` call in that script named only
`{VDD VSS}`. Section 5.5 has the measured evidence for both halves of that claim.

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

**`ci/signoff.yaml`'s `erc` stage does not read run_erc.sh's exit code at all any more**
-- `PARTIAL` and `OK` are the same exit code (0) by design (see the quote above), so a
gate that trusted `rc` would treat a half-fixed stream as clean. `scripts/ci/
erc_census.py` parses the `OVERALL:` line itself and fails on anything except `OK`.
Section 6 covers this.

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
*shipped* build (fixed on a validation replay -- section 5.5 -- but fp1505 itself has
not been rebuilt with the fix; see section 6 for exactly what that does and does not
prove). Section 5.4/5.5 below settle *why*.

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

### 5.4 The answer, as it stood before the root-cause investigation

**Does the SPNET fix work end-to-end? Partially, and it is now measured rather than
assumed:**

| Build | `VDD`/`VSS` | `VDDIO`/`VSSIO` | Calibre ERC | Notes |
|---|---|---|---|---|
| reference (IMEC's GDS) | no text | no text | NOT SIGNED OFF | reproduces IMEC exactly |
| `fp1505` (promoted) | labelled, resolved | no text anywhere | PARTIAL | SPNET fix works for the core supplies |
| `full-20260814` (superseded) | labelled, but shorted together | no text anywhere | NOT SIGNED OFF | independently reproduces the known 4-short defect (doc 43) |

The core `VDD`/`VSS` labelling gap IMEC actually flagged is fixed on the build that
matters (`fp1505`). The IO-supply (`VDDIO`/`VSSIO`) labelling gap was **not** fixed on
either build as of the last measurement -- but the mechanism behind it is now
understood and fixed. Section 5.5 has the investigation and the evidence.

### 5.5 Root cause of the VDDIO/VSSIO gap -- investigated, one claim refuted, the real one found and fixed (2026-08-18)

The gate-promotion plan (`docs/tapeout/53-gate-promotion-plan.md` §3) named a specific
suspect for this gap: *"a LEF pin-type defect at
`ASIC/eth-chiplet/config/design_config.tcl:177-189`, not yet fixed."* That claim was
checked directly against the source and the actual build evidence, not re-quoted.

**The claim, read literally, does not hold up.** `design_config.tcl:177-189` is a
comment block titled *"NO DESIGN_LEF_OVERRIDES, AND THAT IS DELIBERATE"* -- it explains
why *this file* declares no LEF override, because the fix already lives elsewhere: the
tech pack reads a patched IO-driver LEF through the `TSMC65_IO_DRIVER_LEF` environment
variable (`design.mk:318`, `ASIC/asic-toolkit/tech/tsmc65/tech.tcl:196-206`), generated
by `ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py` (`make pad-lef`, wired as a
prerequisite of `syn place cts route` in `design.mk:812`). That script inserts
`USE POWER ;` / `USE GROUND ;` after the `DIRECTION` line on exactly the three pins the
vendor left unclassified (`PVDD2DGZ_G`/`PVDD2POC_G` pin `VDDPST`, `PVSS2DGZ_G` pin
`VSSPST`) -- the mechanism `tech.tcl:1060-1082`'s `io_lef_pg_pin_override_note` (marked
"VERIFIED IN THE VENDOR FILE, not inferred") documents in full.

**Is that fix actually landing on `fp1505`? Checked directly against the build's own
log, not assumed:**

```
$ grep 'Loading LEF file' .../fp1505/work/innovus.log1
Loading LEF file .../ASIC/tech_wrappers/tsmc65/generated/tphn65lpgv2od3_sl_9lm.patched.lef ...
$ grep VSSPST .../fp1505/work/innovus.log1
Pin 'VSSPST' of cell 'PVSS2DGZ_G' is declared as power/ground in LEF but as signal
    in timing library.  Treat it as power/ground.
Pin 'VDDPST' of cell 'PVDD2POC_G' is declared as power/ground in LEF but as signal
    in timing library.  Treat it as power/ground.
Pin 'VDDPST' of cell 'PVDD2DGZ_G' is declared as power/ground in LEF but as signal
    in timing library.  Treat it as power/ground.
```

The patched LEF loads, and Innovus itself confirms it reads the three pins as
power/ground. **The LEF pin-type fix is landed and is taking effect on `fp1505`. It is
not the open defect, and "not yet fixed" was wrong about this specific file.** The
promotion plan's underlying *mechanism* (three vendor pins misdeclared as signal pins)
is real and well-evidenced -- it was simply already closed, via a different file than
the one named, before this investigation started.

**So why is VDDIO/VSSIO still empty?** `connect_global_net VDDIO -type pg_pin
-pin_base_name VDDPST -inst_base_name *` (`power_plan.tcl:68`) only establishes *pin
membership* -- it tells Innovus which physical pins belong to net `VDDIO`. It creates no
metal. Geometry is created separately, by `add_rings`, `add_stripes` and
`route_special`, and a full read of `ASIC/genus-innovus/scripts/power_plan.tcl`
(692 executable lines) found that **every single one of those calls names only
`{VDD VSS}`** -- `add_rings -nets {VDD VSS} ...` (:76), both early
`route_special -nets {VDD}` / `{VSS}` pad-ring passes (:77-93), both `add_stripes -nets
{VDD VSS}` M8/M9 passes (:124, :178), the M5 island-feed and main ladder (:478, :827),
the later combined `route_special -nets {VDD VSS}` pad-ring pass (:834), and the final
block/core/floating-stripe pass (:960-968). `VDDIO`/`VSSIO` appear **nowhere** in this
file except the two `connect_global_net` lines. So the two IO-supply nets reach
`write_stream` with pins registered but **zero routed special-net geometry** -- which is
exactly "empty special nets" (the phrase `design_config.tcl:180` uses), and exactly why
`gdsmap_derive`'s `NAME <layer>/SPNET` rows -- which fixed `VDD`/`VSS` -- have nothing to
attach a label to for `VDDIO`/`VSSIO`: SPNET text is emitted where there is routed
special-net metal, and there was none.

**Verdict: the promotion plan's named location was wrong; the mechanism it half-pointed
at (a vendor LEF pin-type defect) was real but already fixed; the actual, still-open
defect is a separate, un-investigated omission in `ASIC/genus-innovus/scripts/
power_plan.tcl` -- it was never given `add_rings`/`add_stripes`/`route_special` calls
for the IO supplies at all.**

**The fix.** Two new `route_special -connect {pad_pin pad_ring}` calls, added to
`power_plan.tcl` immediately after the existing VDD/VSS pad-ring passes, naming
`VDDIO`/`VSSIO`, mirroring the existing VDD/VSS calls' options exactly with one
deliberate difference: `-pad_pin_width` is **omitted**. Innovus 21.11's own reference
(`TCRcom/route_special.html`) states leaving it unset lets the tool compute the pad pin
width itself and that specifying one "is usually not necessary" -- there is no
measured/vendor-derived width for `VDDPST`/`VSSPST`'s connecting wire the way 1.63/1.5
were derived for VDD/VSS, and guessing one risks a DRC width mismatch for no reason the
documented default doesn't already cover.

**Validated -- against the real database, not reasoned about:**

fp1505's own routed checkpoint (`work/nanosoc_eth_chiplet_pads_routed`, the exact
database `write_stream` produced the shipped GDS from) was reloaded **read-only**
(`read_db`, the same discipline `ASIC/asic-toolkit/flow/verify/restream.tcl` already
uses for a map-only A/B: no `write_db`, nothing written back to the checkpoint on disk),
the two new `route_special` calls were run against it, and the result was streamed to a
new GDS with the same map (`work/tech/gdsout.stream.map`, unchanged) and the same merge
list fp1505's own `write_stream` used:

```
VDDIOFIX: === BEFORE FIX ===
VDDIOFIX:   net VDD     pins=0     special_wires=8066
VDDIOFIX:   net VSS     pins=0     special_wires=6905
VDDIOFIX:   net VDDIO   pins=0     special_wires=0
VDDIOFIX:   net VSSIO   pins=0     special_wires=0
VDDIOFIX: === APPLYING route_special for VDDIO / VSSIO ===
VDDIOFIX: === AFTER FIX ===
VDDIOFIX:   net VDD     pins=0     special_wires=8066
VDDIOFIX:   net VSS     pins=0     special_wires=6905
VDDIOFIX:   net VDDIO   pins=0     special_wires=60
VDDIOFIX:   net VSSIO   pins=0     special_wires=60
VDDIOFIX: wrote 312384876 bytes to .../nanosoc_eth_chiplet_pads_vddiofix.gds
```

(the `pins=0` field is a `get_db .pins` query that reads 0 for all four nets including
`VDD`/`VSS`, which visibly do have pins -- it is the wrong DB attribute for what it was
meant to show and is not evidence of anything here; `special_wires` is the metric that
matters and is the one this section's claims rest on.)

`VDD`/`VSS` are unchanged (the fix touches nothing about them -- same 8066/6905 special
wires before and after), and `VDDIO`/`VSSIO` go from **zero** routed special-net
geometry to **60 each**. Then `run_erc.sh` was run for real -- full Calibre ERC plus the
klayout structural cross-check, same as every other run on this page -- against that new
GDS:

```
== Calibre verdict (PATHCHK POWER/GROUND + the deck's own per-name check) ==
  OK — Calibre found at least one resolving power name and one resolving
  ground name, and none of [VDD VDDIO] / [VSS VSSIO] hit the deck's own
  no-data list...

== Structural cross-check (klayout, independent of the deck's PATHCHK/
   POWER_NAME-GROUND_NAME universe): does EACH of [VDD VDDIO] / [VSS VSSIO]
   have text anywhere in the top cell? ==
  OK — every declared name has top-cell text.

== OVERALL: OK — labels present and resolved for [VDD VDDIO] / [VSS VSSIO]. ==
```

**`OVERALL: OK`, for the first time this page has ever recorded it against a real,
Calibre-checked, non-reference GDS.** `VDD`, `VSS`, `VDDIO` and `VSSIO` all resolve, on
both signals.

**What this does and does not prove.** This is a real Calibre run against a real,
routed database -- not a simulation, not reasoning about what *should* happen. It proves
the fix mechanism works: the missing `route_special` calls are the actual cause, and
adding them produces real, Calibre-recognised, klayout-visible labels for both IO
supplies. It does **not** prove `fp1505` itself is fixed: the validation reloaded
fp1505's routed checkpoint and streamed a *side* GDS from it (deliberately never
overwriting the signoff artefact, same discipline `restream.tcl` documents for exactly
this reason) rather than rebuilding `fp1505` through `place`/`cts`/`route`. `fp1505`'s
own shipped GDS is untouched and will still read `PARTIAL` until it -- or a successor
build -- is regenerated with the corrected `power_plan.tcl`. See section 6 for what a
real rebuild would need and why it was not attempted here.

## 6. `ci/signoff.yaml`'s `erc` stage, and its `check:` (added 2026-08-18)

The stage existed (added earlier 2026-08-18) with `gate: report` and **no `check:`** --
its own comment explained why: *"run_erc.sh's own exit code IS the verdict ... PARTIAL
is deliberately not distinguished from OK at the exit-code level ... A block-gate
promotion should add a real check: that greps OVERALL and fails the census on PARTIAL
specifically."* That is `scripts/ci/erc_census.py`, added alongside this section,
following the same doctrine `scripts/ci/drc_census.py` established: *"the tool exited 0"
is never sufficient; each promoted gate needs its own explicit pass/fail predicate.*

**What it reads.** `run_erc.sh` prints its `OVERALL:` line to its own stdout -- it is
not written into `calibre_erc.sum` or any other Calibre artefact. So the stage's `run:`
now tees the whole transcript into `ERC_RUNDIR/run_erc.log`, inside the build tree (same
reasoning as the `drc` stage's own note: CI clones the repo and only ever sees what's in
`ASIC/eth-chiplet/build/<tag>/`, not the gitignored `ASIC/genus-innovus/work/`), and
`erc_census.py` reads that file.

**The predicate.** Strips ANSI colour (`run_erc.sh`'s `red()`/`grn()` wrap `OK` and
`NOT SIGNED OFF` in escape codes), matches the `OVERALL:` line, and:

- `OK` -> pass.
- `PARTIAL` -> **hard fail**, even though `run_erc.sh` itself exits 0 on this result.
  This is the one substantive change from "trust the exit code": PARTIAL must never be
  folded into a pass at the gate level, or the gate would have called `fp1505` clean
  while `VDDIO`/`VSSIO` carried no text anywhere in the GDS.
- `NOT SIGNED OFF`, no `OVERALL:` line at all, an empty transcript, or no transcript file
  -> fail, each with a distinct, printed reason.

**Proof it can fail, both directions -- `signoff.py prove erc`, run for real:**

```
stage           case                                        result     detail
--------------------------------------------------------------------------------------------------------------
erc             must_pass:pass                              ok         rc=0  0.1s
erc             must_fail:fail-partial                      ok         rc=1  0.1s
erc             must_fail:fail-not-signed-off               ok         rc=1  0.2s
erc             must_fail:fail-no-output                    ok         rc=1  0.1s

4 case(s) over 16 check(s); 0 problem(s)
```

Four fixtures, `ci/fixtures/erc/`:

| Fixture | Content | Provenance |
|---|---|---|
| `pass` | trimmed real transcript, `OVERALL: OK` | this page's own section 5.5 validation run, 2026-08-18 |
| `fail-partial` | real transcript excerpt, `OVERALL: PARTIAL` | section 5.2's `fp1505` measurement, verbatim |
| `fail-not-signed-off` | real transcript excerpt, `OVERALL: NOT SIGNED OFF` | section 5.1's reference-GDS calibration run, verbatim |
| `fail-no-output` | synthetic: Calibre licence never granted, script dies before any `OVERALL:` line | not a capture -- proves the "ran, but never reached a verdict" arm, distinct from a missing or empty log |

Each fixture's `erc_run/` directory carries a `.__exclusive__` marker (the same
mechanism `drc`'s fixtures use, `signoff.py`'s `_sandbox()`) so a real `erc_run` present
on the host that runs `prove` cannot leak into the sandbox and decide the case instead
of the fixture.

**Still `gate: report`, deliberately.** The check can now fail -- that part of the
promotion is done and proven. The design still cannot pass it as shipped: `fp1505`'s own
GDS is unchanged and reads `PARTIAL`. Promoting to `gate: block` before a rebuilt
`fp1505` (or successor) actually reads `OK` would manufacture a green gate the way this
project's own culture explicitly refuses to -- see `ci/signoff.yaml`'s `drc` stage
comment on the same question. Promote once a real `place`-onward rebuild with the
corrected `power_plan.tcl` produces a GDS this stage's `run:` reads as `OK`.

## 7. If Calibre is not available

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

**3. NEW -- `power_plan.tcl`'s VDDIO/VSSIO `route_special` calls omit `-pad_pin_width`
on purpose.** Do not "complete the pattern" by copying VDD's `1.63` or VSS's `1.5` onto
them -- those numbers were derived for a different pin family and were never measured
for `VDDPST`/`VSSPST`. Innovus's own documented default (auto-computed pad pin width) is
what section 5.5's validation actually ran against.

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
- **NEW -- `run_erc.sh`'s exit code and `ci/signoff.yaml`'s `erc` stage verdict can now
  disagree, by design.** The script exits 0 on both `OK` and `PARTIAL`; the stage's
  `check:` (`erc_census.py`) fails on `PARTIAL`. Read the `OVERALL:` line, not the exit
  code, whichever way you ran it.
