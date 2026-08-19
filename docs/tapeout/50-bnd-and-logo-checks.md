# 50 — BND (pad-ring BEOL) and the LOGO keep-out rules

[← 48 IMEC signoff results](48-imec-signoff-results-analysis.md) · [index](00-index.md) · [12 Calibre DRC](12-calibre-drc.md) · [28 DRC status and attribution](28-drc-status-and-attribution.md)

Two pieces of unfinished work, consolidated: the BND (bond-pad / seal-ring BEOL) Calibre
deck, which had a working project wrapper but no `make` target and no comparison against
IMEC's real signoff numbers; and the LOGO keep-out rules, which had three undocumented,
unlabelled experiment directories and no tracked conclusion. Both are now real flows —
`make bnd` and `make logo` / `make drc-logo-check` — and both are measured against IMEC's
actual broker-side report on the actual reference GDS.

> Commands prefixed `make <target>` run from `ASIC/genus-innovus/`.
> Measured on `srv03335`, Calibre v2023.1_18.8, 2026-08-18.

---

## Part 0 — for someone new to this: what these decks are, and why they're separate

### BND is not "more DRC". It is a different rule *family*, for a different part of the die

The digital DRC deck (`make drc`, [12](12-calibre-drc.md)) checks the rules for the layers
a standard-cell/routing flow produces: metal width and spacing, via enclosure, density
windows, antenna ratios — the rules that apply to **core logic**. Bond pads and the seal
ring are built from a **completely different set of mask layers** that core logic never
touches:

- **PM** — the pad-metal / passivation-opening layer. This is the literal hole cut in the
  chip's final passivation coat so a bond wire can land on metal and actually make
  electrical and mechanical contact. Core logic is buried under passivation forever; a
  bond pad cannot be.
- **AP** — after-passivation (redistribution) metal. On this process the bond pads
  themselves are drawn largely in AP, the metal layer that sits *above* the passivation
  opening — a wire-bond RDL layer, not one of the M1-M9 routing layers logic uses.
- **CB / CB2** — the bond-pad cut/opening layers that define where PM meets the pad
  ring, and the layers the seal ring's own metal is built from.
- **the seal ring itself** — a continuous guard ring of metal + via stack running around
  the full perimeter of the die, whose job is purely mechanical/environmental (moisture
  and dicing-stress protection), not electrical routing.

None of PM/AP/CB/CB2/seal-ring is a routing layer, and none of it is exercised by the
digital DRC deck at all — `make drc`'s own header says so explicitly ("the GDS carries
routing, vias and macros but no standard-cell, IO or bond-pad geometry ... front-end,
density and seal-ring rules are meaningless here"). The foundry ships BND as a **separate
Calibre rule deck** — `CN65_WIRE_BOND_<stack>.<rev>`, not `CLN65S_<stack>.<rev>` — for
exactly this reason: a chip can be perfectly clean on core-logic DRC and still have a bond
pad that is too narrow to reliably wire-bond, or too close to a neighbour to survive
dicing. Both gates are foundry-mandated for tapeout; neither substitutes for the other.

### What LOGO is, and why a company logo has mandatory keep-out rules

A "chip logo" on a mini@sic shuttle is not a sticker applied after the fact — it is real
geometry, drawn on real mask layers (in this design's case, on AP: the same
after-passivation redistribution metal the bond pads use), sitting on the die alongside
everything else that gets manufactured. Because it is real metal on a real layer, it can
physically **interfere with the functional design** exactly the way any other polygon can:
short to real routing, break an antenna ratio, or blow a density window. The foundry's
rule deck therefore treats the 158/LOGO-tagged region as a keep-out:

- **LOGO.S.1** — real OD/PO/M1-M9 must stay **10 µm clear** of anything tagged LOGO.
- **LOGO.R.4** — OD/PO/M1x-M9x must not **cut through** (overlap) anything tagged LOGO.

Two consequences that are not obvious the first time you meet this: (1) the marker layer
(158/LOGO) is what makes the rule apply at all — nothing is checked against "the logo" as
a design intent, only against whatever is tagged 158; and (2) because the keep-out is
measured from the marker's *bounding box*, a full pictorial logo (ours is 727.75 × 320.25
µm) needs a 747.75 × 340.25 µm hole in the routing, and there is no such hole anywhere on
a die that is already placed and routed. See Part B.

---

## Part A — BND: bond-pad / seal-ring BEOL, re-run and compared against IMEC

### What existed before this pass

- `ASIC/genus-innovus/scripts/calibre/nanosoc_eth_chiplet_pads.bnd.rules` — a correct,
  well-evidenced project wrapper deck (`#DEFINE PITCH_70_STAGGER`, justified in its own
  header from the instantiated cell names, `PAD70GU`/`PAD70NU`). It fixed a real,
  previously undiscovered fault: with no pitch switch selected at all, the foundry deck's
  own `PITCH_OPTION.ERROR.1` rulecheck fires and every pad-row-derived layer the deck
  computes falls through to `EMPTY` — measured 2026-08-09
  (`calibre_runs/bnd_run_20260809`): 197 rulechecks executed, all but two exactly zero,
  and one of the two non-zero ones *was* `PITCH_OPTION.ERROR.1` itself. **That run's ~195
  zeros were a fabricated clean, not a pass.**
- No `run_bnd.sh`, no `make bnd` target, and no wiring from `drc_project.mk`/`common.mk`/
  `pdk_paths.sh` to resolve the BND foundry deck path — the wrapper's own header
  literally instructed `Run it with: DRC_GDS=/abs/path.gds scripts/calibre/run_bnd.sh`,
  a script that did not exist.
- A run at `calibre_runs/bnd_toolkit_20260817/` — current-toolkit vintage, but against
  `ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds`, **not** the
  file IMEC actually checked. That build's `PMi`/`APi` layer counts are 0/8 — essentially
  no pad-ring or AP content at all — so it reported 1 total result (a density window) and
  cannot be compared to IMEC's numbers. It is not wrong, it is just answering a different
  question (whether the *core-side* stream carries stray pad-ring geometry — it mostly
  doesn't) and should not be read as "our BND signoff number".

### What this pass did

1. Added `bnd-ruledeck` to `ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh` (same anchor
   and stack derivation as `drc-ruledeck`, different foundry subdirectory —
   `CMOS/LP/pdk/Calibre/drc/wire_bond/CN65_WIRE_BOND_<stack>.<rev>`), and `PDK_BND_DECK`
   to `ASIC/common.mk`, and `BND_FOUNDRY_DECK`/`BND_RUNDIR`/`BND_CPUS` to
   `ASIC/genus-innovus/drc_project.mk` — the same resolution chain `DRC_FOUNDRY_DECK`
   already uses, so the BND deck can never drift from the metal stack the design actually
   streams with.
2. Wrote `ASIC/genus-innovus/scripts/calibre/run_bnd.sh`, the script the wrapper's header
   already promised — same preflight/assert/summarise shape as `run_drc.sh`, but simpler:
   the BND wrapper needs no `make_project_deck.sh` splice (it sets no foundry default this
   design must override), so a plain `INCLUDE "$BND_FOUNDRY_DECK"` is enough.
3. Added `make bnd` to `ASIC/genus-innovus/Makefile`.
4. Re-ran it for real, against the **exact** file IMEC checked:
   `ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_outputs/nanosoc_eth_chiplet_pads_logo_full_L300.gds`,
   confirmed by hash before the run:

   ```
   $ md5sum nanosoc_eth_chiplet_pads_logo_full_L300.gds
   7f6214965501c911bd65069378ae911d  nanosoc_eth_chiplet_pads_logo_full_L300.gds
   ```

   — matching the md5 this design's own build recorded for that file, i.e. the same
   bytes IMEC's `Layout Path(s):` line names (their copy additionally carries **their**
   added dummy fill + seal ring merge, so the two are not byte-identical end to end, but
   the pad-ring/AP content under test is the same source stream). A real Calibre seat was
   available (`MGC_HOME`/`MGLS_LICENSE_FILE` both set, `calibre` on `PATH`), so this is a
   fresh run, not a re-read of stale data.

### The comparison, rule by rule

IMEC's standalone report:
`ASIC/imec_results/Archive_.../bnd/cali_bnd_nanosoc_eth_chiplet_pads_logo_full_L300_merged_dummy_with_sealring.rpt`
(cross-checked identical against the same section embedded in the master
`design/reports/Final_Report_....rpt`). Ours:
`calibre_runs/bnd_ref_pitch70/nanosoc_eth_chiplet_pads.bnd.summary` (this worktree; not
tracked — see "reproducing this" below).

| Rule | IMEC (theirs, merged dummy+sealring) | Ours (same reference GDS, no dummy/sealring) | Verdict |
|---|---:|---:|---|
| `PM.W.1` (pad metal width ≥ 30 µm) | 889 (967) | **0 (0)** | explained — see below |
| `AP.W.1` (AP interconnect width ≥ 3 µm) | 12 (12) | **12 (12)** | **exact match** |
| `AP.W.2` (AP interconnect width ≤ 35 µm) | 2 (82) | **2 (82)** | **exact match** |
| `AP.S.1` (AP spacing ≥ 2 µm) | 4 (4) | **4 (4)** | **exact match** |
| `AP.S.4` (space to CB2/PM ≥ 3.5 µm) | 131 (131) | **0 (0)** | explained — see below |

By cell, where both sides have comparable geometry, the match is exact down to the
individual result count:

| Cell | Rule | IMEC | Ours |
|---|---|---:|---:|
| `PAD70GU` | `AP.W.2` | 1 (42) | **1 (42)** |
| `PAD70NU` | `AP.W.2` | 1 (40) | **1 (40)** |
| top cell | `AP.W.1` | 12 (12) | **12 (12)** |
| top cell | `AP.S.1` | 4 (4) | **4 (4)** |
| `CORNER_B` | `PM.W.1` | 26 (104) | 0 (no `CORNER_B` PM content on our side) |

**Every rule where our reference GDS actually carries the geometry being checked matches
IMEC's published count exactly** — same true count, same capped-display count, same
by-cell attribution. That is strong, independent confirmation that (a) this is genuinely
the file IMEC checked, (b) `PITCH_70_STAGGER` is evaluating the pad-row geometry the same
way IMEC's config does for every AP-layer rule, and (c) our BND wrapper deck and its
switch selection are correct, not a second fabricated-clean.

### The two deltas, and why they are not a discrepancy

`PM.W.1` and `AP.S.4` are the only rules where we diverge, and both track one fact: our
reference GDS has **zero PM-layer geometry**.

```
LAYER PMi ...... TOTAL Original Geometry Count = 0   (0)     <- ours
LAYER APi ...... TOTAL Original Geometry Count = 40  (285)   <- ours
LAYER RVi ...... TOTAL Original Geometry Count = 3   (11)    <- ours
```

IMEC's copy has their added dummy fill and seal ring merged in — real PM and seal-ring
metal that ours simply does not carry yet. `PM.W.1` checks PM width directly (zero PM
shapes ⇒ zero results, not zero violations), and `AP.S.4` checks spacing *to* PM/CB2/seal
ring, which needs the same geometry to have anything to measure against. This is exactly
the class of delta the task brief predicted ("IMEC's file has their own added dummy fill
+ seal ring merged in ... don't expect byte-identical counts") — and it is now backed by
a layer-count measurement, not an assumption.

### A real discrepancy that turned out not to matter here — but is worth tracking

IMEC's report header declares:

```
'#DEFINE PITCH_80_STAGGER'
'#DEFINE with_AP'
```

Our wrapper deck sets `PITCH_70_STAGGER`, not `PITCH_80_STAGGER`. These are **not**
interchangeable spellings of the same thing — the foundry deck's own switch comments read
*"Turn on to use IO cell (>=70um pitch) of the staggered pad ONLY"* for the 70 option and
*"(>=80um pitch)"* for the 80 option: two mutually exclusive choices on the same axis, and
the deck's `PITCH_OPTION.ERROR.*` rules reject having both active. Our own wrapper's
70-pitch choice is evidenced (`PAD70GU`/`PAD70NU` are literally 70 µm-pitch parts); IMEC's
80 is unexplained from here. **This is exactly the kind of thing worth sending to the
broker as a question**, not resolving unilaterally.

It was tested, not just flagged. A controlled A/B — the identical wrapper deck, the
identical reference GDS, **only** the pitch `#DEFINE` changed — was run:

```
$ make bnd BND_DECK=<scratch copy with PITCH_80_STAGGER>
...
Checks with violations:
  AP.W.1                           12
  AP.S.1                           4
  AP.W.2                           2
```

Byte-for-byte identical result counts to the `PITCH_70_STAGGER` run. The only difference
between the two summaries at all is which `CB.*.P70.*` vs `CB.*.P80.*` rulecheck *names*
exist — every one of them reports 0 on both sides, because `CBi` (the bond-pad cut/opening
layer the pitch switch actually differentiates) has **zero geometry** in this reference
GDS on either config, same reason as the `PM.W.1`/`AP.S.4` gap above. **The pitch-switch
mismatch is real and should be asked about, but it is proven — not assumed — to be
unrelated to today's PM.W.1/AP.S.4 delta**: there is currently no PM/CB content on our
side for the switch to differentiate. Re-test this once a real dummy-fill + seal-ring
merge exists on our side; that is the point at which the two switches could start to
disagree on a shared, non-empty layer.

### Reproducing this

```sh
cd ASIC/genus-innovus
make bnd BND_GDS=runs/20260811T103338Z_fill-verify/prev_outputs/nanosoc_eth_chiplet_pads_logo_full_L300.gds \
         BND_RUNDIR=calibre_runs/bnd_ref_pitch70
```

`calibre_runs/` is gitignored host-only data (same as every other Calibre run directory in
this repo — see `ASIC/*/calibre_runs` in `.gitignore`), so the raw summaries this page
quotes from live only on the host they were run on; this page is the durable record.

---

## Part B — LOGO: three unlabelled experiments, one consolidated flow, a real fix

### What existed before this pass

Three ad hoc Calibre runs, none referenced from any doc, none named to say what varied
between them:

| Directory | Date | What changed | True `LOGO.R.4` |
|---|---|---|---:|
| `calibre_runs/drc_logo` | 2026-08-10 14:55 | full logo (pictures + text), centred at (663.875, 1000.0) | **5497** |
| `calibre_runs/drc_logo_text` | 2026-08-10 15:32 | jack picture stripped (`strip_logo_jack.py`), same position | **1186** |
| `calibre_runs/drc_logo_L300` | 2026-08-10 15:41 | text-only, moved so the left edge sits at x=300 | **1134** |

(`LOGO.S.1` is capped at 1000/1000 in all three — Calibre's `DRC MAXIMUM RESULTS 1000`
means the true count for that rule was never measured, only bounded below.)

Progress, but asymptoting: stripping the jack picture cut the true count by 78%; moving
the remainder barely helped (1186 → 1134, a 4% change). Both surviving experiments are
dominated by the **top-level cell** (763 and 964 of the true count respectively) — i.e.
real chip routing under the mark, not one unlucky macro instance. `strip_logo_layers.py`
already existed as a fourth, untested idea (its own header even claims a measurement:
*"AP-only measures +20 results, all cosmetic artwork rules, none capped"*) but had never
actually been run through Calibre — there was no `calibre_runs/drc_logo_aponly*`
directory, and `logos/nanosoc_eth_Logo_APonly.gds` sat in the tree unused, wired to
nothing.

### Why moving or shrinking the marked box was never going to reach zero

`LOGO.S.1` needs a 10 µm halo, clear of **all** OD/PO/M1-M9, around the entire marked
box. The full logo therefore needs 747.75 × 340.25 µm of routing-free space; text-only
needs 380.25 × 310.25 µm. This design's core is fully placed and routed at 1600 × 2000 µm
with no such hole anywhere in it — `merge_logo.py` itself already refuses to place the
logo inside the 135 µm pad-ring band (the pads' own AP claims that space) or inside the
74 µm chip-corner keep-outs, which only narrows the search further. Moving the box
(`drc_logo` → `drc_logo_L300`) changes *which* routing it lands on top of, not *whether*
it lands on routing — hence the 4%, not 90%, improvement between the two text-only
attempts. **Reaching zero this way requires reserving a genuine keep-out in the
floorplan** (a P&R change, out of scope for a Calibre-side fix), not a better placement of
the same marked shape.

### The measured fix: draw the logo on AP only, and drop the 158/LOGO marker

`LOGO.S.1` and `LOGO.R.4` are defined **entirely in terms of the LOGO marker layer vs.
OD/PO/M1-M9**. AP is not one of the layers either rule inspects. `strip_logo_layers.py`
keeps only the AP layer from the logo cell and drops everything else — including the
LOGO marker itself:

```
$ klayout -b -r scripts/strip_logo_layers.py -rd inp=logos/nanosoc_eth_Logo.gds -rd out=/tmp/aponly.gds
kept   : AP
dropped: 2 dummy-exclude layers (28 shapes each), LOGO marker (28 shapes)
```

(Real GDSII stream/datatype numbers for these layers are foundry-licensed and are not
reproduced here — same convention as `gdsmap_derive.py` and doc 49; resolve them locally
via `make gdsmap` or the derived stream-out map if you need the numeric pairs.)

Re-measured 2026-08-18 against the **current-toolkit signoff DRC deck** (not a diagnostic
subset — the same `make drc` deck that gates this design), via the new consolidated flow:

```sh
$ make logo GDS=<a real routed stream>          # LOGO_AP_ONLY=1 is now the default
$ make drc-logo-check GDS=<the same stream>
== LOGO rulecheck verdict (.../drc_logo_flow/nanosoc_eth_chiplet_pads.drc.summary) ==
RULECHECK LOGO.S.1 ...................... TOTAL Result Count = 0   (0)
RULECHECK LOGO.O.1 ...................... TOTAL Result Count = 0   (0)
RULECHECK LOGO.R.4 ...................... TOTAL Result Count = 0   (0)
PASS: LOGO.S.1 and LOGO.R.4 are both a real zero (not capped).
```

**A real zero, not a 1000-result cap hiding a larger true count.** This reproduces —
with an actual run rather than trusting an eight-day-old code comment —
`strip_logo_layers.py`'s claim of "+20 results, all cosmetic, none capped." It also
confirms the same result twice, independently: once via a direct `run_drc.sh` invocation
(`calibre_runs/drc_logo_aponly_verify/`) and once via the new `make logo` /
`make drc-logo-check` pipeline itself, proving the consolidated automation — not just the
underlying idea — actually works end to end.

### The trade-off, and why it is resolved rather than assumed

Dropping every layer but AP also drops the 158/LOGO **marker**. The zero above means "the
thing the rule checks for isn't there to violate", which is a different claim from "a
marked logo passed cleanly", and the Makefile used to flag this as an open question for
IMEC/the broker liaison. **It no longer needs to be asked**: IMEC's own `custom_drc`
report already answers it. `ASIC/imec_results/Archive_.../custom_drc/cali_custom_drc_...txt`
carries two informational checks aimed at exactly this pattern:

```
RULECHECK IM.LOGO.R.1:WARN ....... TOTAL Result Count = 92  (92)
IMEC WARNING: Missing Logo layer. Make sure chip has visible logo top metal or AP.
              Logo recognition layer is not a must have.

RULECHECK IM.FLOAT.AP ............ TOTAL Result Count = 138 (218)
IMEC WARNING: No net connected between AP and top metal. Possibly it's a logo.
```

Both fire on IMEC's *own* submission (which does carry a 158-marked, full-jack logo), at
**WARN** severity, not ERROR — and the first says outright that the 158/LOGO marker is
"not a must have", and that visible **AP alone** satisfies their intent. An AP-only logo
should therefore be expected to raise an `IM.LOGO.R.1:WARN` / `IM.FLOAT.AP` note on a
future broker-side custom_drc pass — that is expected and informational, not a rejection.

### The consolidated flow

Everything above is now one script and one set of Makefile targets, replacing three
unlabelled directories:

- `scripts/strip_logo_layers.py` (AP-only), `scripts/strip_logo_jack.py` (text-only),
  `scripts/merge_logo.py` (placement + keep-out checks) — unchanged, but now actually
  wired up.
- `ASIC/genus-innovus/Makefile`:
  - `LOGO_AP_ONLY` (new, **default 1**) selects the AP-only mark; `LOGO_STRIP_JACK`
    (existing) selects text-only when `LOGO_AP_ONLY=0`; both `0` reproduces the original
    full logo, for an A/B against this page's numbers.
  - `make logo` — merges the selected variant into `$(GDS)`, same as before.
  - `make drc-logo` — DRC's the merged submission artefact, own rundir
    (`calibre_runs/drc_logo_flow`), never overwrites the signoff run's results.
  - `make drc-logo-check` (**new**) — runs `drc-logo`, then greps the LOGO.\* rulechecks
    out of an 8000+ rulecheck summary and prints PASS/FAIL on the **true** (uncapped)
    count, so nobody has to go find these three lines by hand again.

```sh
make drc-logo-check                       # AP-only, the recommended default
make drc-logo-check LOGO_AP_ONLY=0 LOGO_STRIP_JACK=0   # A/B: full logo, expect ~5497 true
make drc-logo-check LOGO_AP_ONLY=0 LOGO_STRIP_JACK=1   # A/B: text-only, expect ~1134 true
```

### Status, for anyone re-opening this

- **Closed at the DRC-gate level.** `LOGO_AP_ONLY=1` (the new default) is measured, real
  zero, on the current signoff deck, reproduced twice.
- **Not yet decided: is the AP-only mark good enough for the actual submission?** That is
  a design/artwork call (does a bare AP-layer mark, with no visible jack picture and no
  158 tag, still read as "SoC Labs was here" the way the sponsors want?), not a DRC
  question. IMEC's custom_drc text says the broker will accept it; whether the project
  wants to is a separate conversation.
- **If a full pictorial, 158-marked logo is wanted anyway**, the only way to reach zero on
  `LOGO.S.1`/`LOGO.R.4` is a genuine floorplan keep-out — a P&R change reserving a
  routing-free 747.75 × 340.25 µm (full) or 380.25 × 310.25 µm (text-only) window before
  place/route, not a merge-step change after the fact. That is out of scope here; see
  [26](26-plan-to-submittable-gds.md) if this becomes a priority.
- `ASIC/genus-innovus/calibre_runs/drc_logo`, `drc_logo_text` and `drc_logo_L300` are the
  historical evidence this page is built from — they are gitignored host-only data like
  every other `calibre_runs/*` directory, kept as-is (not deleted) because they are the
  only record of the 5497 → 1186 → 1134 progression. Treat this page, not those
  directories, as the entry point from now on.

---

---

## Part C — Promotion pass (2026-08-18): real census scripts, a real waiver
## file, and the archive-2 cross-check

`docs/tapeout/53-gate-promotion-plan.md` §1 row 4 sets `bnd`'s promotion bar:
the rule-by-rule IMEC diff closed with a real script (not the by-hand
comparison Part A did), and the LOGO AP-only fix re-verified under full-merge
conditions. This section is that pass, done against the corner-rotation-fixed
`.io` (verified present: all four `PCORNER_G` instances carry the corrected
`orientation=` values) and a real Calibre seat.

### C.1 `scripts/ci/bnd_census.py` — same pattern as `drc_census.py`, a real waiver file

New sibling script, same shape as `scripts/ci/drc_census.py` (parse the
summary once, main section only; cell-scoped waivers from a yaml file;
refuse in code to ever waive the layout primary cell; fail on stale or
drifted waiver entries) and the same self-test discipline `docs/tapeout/
39-po-r8-resolved.md` §7-8 established: `ci/fixtures/bnd/{pass,
fail-design-results,fail-saturated-cap,fail-no-summary,fail-waiver-stale}`,
wired into `ci/signoff.yaml`'s new `bnd` stage as `check_proof`, all five
cases pass under `signoff.py prove bnd`. Deliberately NOT sharing code with
`drc_census.py` via an import — that script is the block-gated `drc` stage's
entire verdict, with its own fixture history; duplicating ~150 lines is the
lower-risk choice for a brand-new, unpromoted script. See the module
docstring for the full reasoning.

Re-run for real (`MGC_HOME`/`MGLS_LICENSE_FILE` both set, a real Calibre
seat), against the exact file IMEC checked (md5 `7f621496…`, same as Part A):

```
$ make bnd BND_GDS=runs/20260811T103338Z_fill-verify/prev_outputs/nanosoc_eth_chiplet_pads_logo_full_L300.gds \
           BND_RUNDIR=calibre_runs/bnd_postfix_check
...
TOTAL RESULTS GENERATED = 18 (98)
$ python3 scripts/ci/bnd_census.py calibre_runs/bnd_postfix_check
TOTAL results  : 18
  less waived  : 2
  REPORTED     : 16
owner split: design 16, io-pad-abstract 2
FAIL: 16 design-owned results > budget 0.
```

Reproduces Part A's numbers exactly (12 AP.W.1 + 2 AP.W.2 + 4 AP.S.1 = 18;
0 PM.W.1, 0 AP.S.4). `BND_GDS=` is also a real bugfix this pass made: the
Makefile's own header has documented that override since the target was
written, but the recipe hardcoded `$(GDS)` into the exported `BND_GDS`
regardless — the override never worked. Fixed in
`ASIC/genus-innovus/Makefile` (`BND_GDS ?= $(GDS)`, then the recipe uses
`$(BND_GDS)`), caught while reproducing this exact command.

### C.2 A genuine, previously undocumented finding: 16 un-rootcaused results in OUR OWN top cell

Part A's "exact match" framing answered *reproducibility*, not
*acceptability*. Pulling coordinates out of
`calibre_runs/bnd_postfix_check/nanosoc_eth_chiplet_pads.bnd.results`:
all 12 `AP.W.1` + 4 `AP.S.1` results are attributed to the **layout primary
cell itself** (`nanosoc_eth_chiplet_pads`), and every polygon sits at
x 314-1006µm, y 872-1125µm on a 1600×2000µm die with a 135µm pad row —
squarely in the **core**, nowhere near the pad ring or seal ring. This is
real AP-layer redistribution routing this design drew itself (plausibly,
not yet confirmed, near the `u_tidelink` SRAM macro at (230.6, 1210) —
proximate, not proven), not a pad-ring or vendor-abstraction artefact.

It is an **exact match** against IMEC's independent Calibre run on **both**
archives (see C.3) — which confirms the finding is real and reproducible,
but that is a different claim from "acceptable", and nothing in Part A ever
asked the second question. There is no mechanism argument here the way
`PO.R.8`'s black-boxing story provides one: a width-below-3µm or
spacing-below-2µm result in metal this design routed is either a real defect
to fix or a deliberate, undocumented design choice. `bnd_waivers.yaml`
records this explicitly as **DELIBERATELY NOT WAIVED** — the same positive-
control discipline `docs/tapeout/39-po-r8-resolved.md` §8 uses for PO.R.8's
six never-waived `VIA3.R.2` vendor-memory results — and it is the reason
`bnd` is not promoted to a zero-budget block gate by this pass. See §C.5.

### C.3 `scripts/ci/imec_rule_diff.py` — the rule-by-rule diff, as a real script

New generic comparison engine: N labelled Calibre-format reports (local
`*.summary` files and IMEC archive `*.rpt` files are the same grammar — IMEC
runs Calibre too, so the identical parser reads both), a rule-name list,
and a rule × report matrix with by-cell breakdown. This is what closes doc
53's "rule-by-rule diff against IMEC's report closed" criterion with a real
script rather than the side-by-side reading Part A and
`docs/tapeout/48-imec-signoff-results-analysis.md` did by hand.

```
$ python3 scripts/ci/imec_rule_diff.py --rules PM.W.1,AP.W.1,AP.W.2,AP.S.1,AP.S.4 \
    --report local=calibre_runs/bnd_postfix_check/nanosoc_eth_chiplet_pads.bnd.summary \
    --report archive1=ASIC/imec_results/Archive_..._17Aug26_15u14/bnd/*.rpt \
    --report archive2=ASIC/imec_results/Archive_..._18Aug26_19u28/bnd/*.rpt --by-cell
```

| rule | local | archive1 (17Aug, pad-ring merge) | archive2 (18Aug, full merge) | verdict |
|---|---:|---:|---:|---|
| `PM.W.1` | 0 | 889 (967) | 919 (**1000, now capped**) | DELTA — explained (Part A: no PM geometry locally) |
| `AP.W.1` | 12 | 12 | 12 | **EXACT_MATCH**, all 3 |
| `AP.W.2` | 2 (82) | 2 (82) | 2 (82) | **EXACT_MATCH**, all 3, by-cell too (`PAD70GU`=1, `PAD70NU`=1 identically) |
| `AP.S.1` | 4 | 4 | 4 | **EXACT_MATCH**, all 3 |
| `AP.S.4` | 0 | 131 (131) | 46 (46) | DELTA — explained (needs the same absent PM/CB2 geometry) |

By cell, `CORNER_B`'s `PM.W.1` count is **byte-identical across both
archives** (26/104 both times) — confirming
`CONVERGENCE_PLAN_2026-08-18.md` §8's claim with a script instead of a
by-hand read. One new cell appears only in archive2's by-cell breakdown:
`UCSRN_NOVIA` (`PM.W.1` = 1/4) — real vendor seal-ring-adjacent geometry
this design cannot see locally (no Back-End PDK), consistent with the
"needs-vendor-data" class `docs/tapeout/39-po-r8-resolved.md` names for
`PO.R.8`'s undirectly-demonstrated portion.

**`AP.W.1`/`AP.W.2`/`AP.S.1` all stay exact matches under full library
merge** — real standard-cell/seal-ring content being added nearby did not
move any of the three rules this design's own metal or the vendor pad cells
are responsible for. That is corroborating evidence, not proof, that these
are stable, geometry-local findings rather than something a black-boxing
artefact would eventually reveal more of — relevant to §C.2's still-open
question but not a substitute for actually root-causing it.

### C.4 `scripts/ci/logo_census.py` — LOGO census, and a third independent re-confirmation

New gate-facing script for `make drc-logo-check`'s output, reusing
`bnd_census.py`'s parser (imported, not copied — both are new, unpromoted
scripts, so the "duplicate to protect a promoted gate" argument in C.1 does
not apply between the two of them). Reports LOGO.S.1/R.4/O.1's TRUE
(uncapped) count specifically, because a naive grep of the Makefile's own
inline awk cannot tell `= 0 (0)` from `= 1000 (1199)` without reading the
parenthesised number.

Re-ran `make drc-logo-check` (AP-only, the default) for real against
`ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads.gds` — the
current, route-complete, TOOLKIT-lineage stream, denser and more realistic
than either of Part B's original test streams:

```
$ make drc-logo-check GDS=.../fp1505/outputs/nanosoc_eth_chiplet_pads.gds \
      DRC_LOGO_RUNDIR=.../fp1505/work/drc_logo_run
... 1904 rulechecks, 930 raw results (PO.R.8 691, real routing findings, unrelated to LOGO) ...
RULECHECK LOGO.S.1 ...... TOTAL Result Count = 0 (0)
RULECHECK LOGO.O.1 ...... TOTAL Result Count = 0 (0)
RULECHECK LOGO.R.4 ...... TOTAL Result Count = 0 (0)
$ python3 scripts/ci/logo_census.py .../fp1505/work/drc_logo_run
PASS (on THIS local stream only): every measured LOGO.* rule is a real zero...
```

**Third independent zero** for LOGO_AP_ONLY: Part B's original measurement,
Part B's direct `run_drc.sh` cross-check, and now this pass's run against a
different, denser, real-full-chip-routed stream. `DRC_LOGO_RUNDIR` is also a
real bugfix landed alongside this: `drc-logo`/`drc-logo-check` used to
hardcode their rundir into the gitignored `calibre_runs/` tree with **no
override at all**, unlike `bnd`/`drc`/`erc` — the exact "CI clones the repo
and finds nothing there" defect `ci/signoff.yaml`'s `drc` stage comment
already describes fixing for the main deck, never applied here until now.

**This still does not answer the full-library-merge question** — see C.5.
fp1505 carries real full-chip routing but no real TSMC standard-cell/pad/
seal-ring geometry; it is a better LOCAL approximation, not a merge.

### C.5 The genuine open question: does LOGO_AP_ONLY's zero survive full-merge conditions?

**Answered honestly: NOT DIRECTLY TESTABLE from what exists, and here is the
real evidence rather than an assumption.**

Neither IMEC archive ever checked the AP-only artefact. Both the 17Aug
(pad-ring-only merge) and 18Aug (full std-cell + seal-ring merge) archives
checked the **original**, 158-marked, full-pictorial logo — the one already
known (Part B) to saturate the 1000-result cap. `scripts/ci/imec_rule_diff.py`
against both archives' `drc/*.rpt`:

| rule | archive1 (17Aug) | archive2 (18Aug, full merge) | verdict |
|---|---:|---:|---|
| `LOGO.S.1` | 1000 (1000) | 1000 (1000) | unchanged displayed value — **still capped, true count beyond 1000 is unknown either time** |
| `LOGO.R.4` | 1000 (1000) | 1000 (**1199**) | **true count grew +19.9%** under full merge |
| `LOGO.O.1` | absent | absent | IMEC's real deck does not report this rule at all, either archive |

This is the load-bearing new data point: for the **marked** logo,
`LOGO.R.4`'s true count demonstrably grows once real standard-cell/seal-ring
geometry is merged in — the same class of change `PO.R.8` (691→0) and the
`CSR.R.2`/`CSR.EN.8` cluster (+519%/+783%/+243%) already showed for other
rules. "More real geometry changes LOGO numbers" is not a hypothetical for
this project; it is demonstrated, twice now, for two different rule
families. That is precisely why LOGO_AP_ONLY's zero cannot be assumed to
generalise on the strength of Part B's local measurement alone — which is
what this task set out to check, rather than assume.

**Why the answer leans towards "yes, it survives" anyway — a mechanism
argument, not a repeat of the same untested assumption:** `LOGO.S.1` and
`LOGO.R.4` are defined **entirely** in terms of the LOGO marker layer's
bounding box versus real OD/PO/M1-M9 (Part 0 above). `strip_logo_layers.py`
drops that marker layer entirely — the AP-only artefact has **no
LOGO marker shape anywhere in the stream**. The mechanism that grew `LOGO.R.4`
under full merge is "more real geometry now falls inside the fixed 10µm halo
measured from the marker" — a mechanism that requires a marker to measure
from. An AP-only mark has nothing for the rule to measure from, at any
merge density, by construction of the rule itself, not by an assumption
about how much geometry happens to be nearby. This is the same shape of
argument that resolved `PO.R.8` (net-based mechanism, confirmed by a
controlled experiment) rather than trusting a single measurement's
generalisation.

**What this pass could NOT do, said plainly:** actually run Calibre with
real TSMC standard-cell/seal-ring geometry merged in locally — this project
holds no Back-End PDK (`docs/tapeout/53-gate-promotion-plan.md` §4, `docs/
DRC_WAIVER_INVENTORY.md`), so a true full-merge local re-run of the AP-only
artefact is not possible here. The only way to close this for real is
either (a) a fresh IMEC/broker check-only submission of the actual AP-only
merged stream, or (b) waiting for real vendor geometry to become available
locally. Neither happened in this pass.

**Verdict: `LOGO_AP_ONLY`'s zero is HIGH CONFIDENCE, NOT PROVEN, under
full-merge conditions.** `logo` stays `gate: report` for exactly this
reason — see §C.6.

### C.5.1 A minor, new, informational finding — triaged here, not chased further

`custom_drc`'s archive comparison surfaced one new rule category:
`IM.RADHARD.1:WARN` ("Potential radiation hardened device detected... Possible
military application") fires 22 times in archive2, **absent entirely from
archive1**. Mechanism: this can only fire once real transistor-level device
geometry exists to pattern-match against, which archive2's `tcbn65lp` merge
supplied for the first time — same structural class as items 1/7/9 in
`CONVERGENCE_PLAN_2026-08-18.md` §9's retrospective table
("structurally undetectable locally"). WARN severity, informational, no
action — recorded here per doc 53 §9's "mandatory triage-or-defer" discipline
so it does not repeat item 2's mistake (a real finding sitting unwritten for
eight days).

### C.6 Promotion decision

Per `docs/tapeout/53-gate-promotion-plan.md`'s own bar — "promote to `block`
ONLY if validation gives real confidence; if a specific piece is uncertain,
keep it `report`-gated even if the rest promotes":

- **`bnd` (new `ci/signoff.yaml` stage, `gate: report`, NOT block.)** The
  rule-by-rule IMEC diff IS closed with a real script (C.3). But C.2's 16
  design-owned, exact-IMEC-matching, un-rootcaused `AP.W.1`/`AP.S.1` results
  are a **new** finding this pass surfaced, not an old one this pass closed
  — a zero-budget block gate would fail on them permanently and
  uninformatively starting today, which is exactly the failure mode doc 53's
  promotion bar exists to prevent. Wired for real (`check:`, cell-scoped
  `bnd_waivers.yaml`, `check_proof` with all 5 cases proven via `signoff.py
  prove bnd`) so the finding is measured and printed on every run, not
  silently deferred.
- **`logo` (new `ci/signoff.yaml` stage, `gate: report`.)** Per §C.5: high
  confidence, not proven, under full-merge conditions — the task's explicit
  instruction to keep an uncertain piece `report`-gated even if a sibling
  promotes applies directly here.
- **CI reality check, stated plainly:** both new stages' `run:` targets
  `ASIC/eth-chiplet/build/fp1505` (matching `drc`/`erc`'s own convention, so
  a bare CI clone can reproduce them at all) — but fp1505 carries almost no
  pad-ring/AP content (`LAYER APi`: 7 (12) shapes there against 40 (285) on
  the legacy reference stream), so `bnd`'s CI number is a structurally weak,
  near-null measurement (`bnd_census.py`'s new `AP.DN.1` "sparse density,
  never gated" bucket exists specifically because of this). The REAL,
  validated `bnd` numbers in this document come from a host-local run
  against the legacy pad-ring-merged snapshot, which is gitignored/host-only
  and not yet reproducible from a fresh clone — a real, named gap, same
  class as doc 53 §3's "needs a Calibre seat" items, not swept under the
  `report` gate.

---

## Files touched by this pass

| File | What changed |
|---|---|
| `ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh` | added `bnd-ruledeck` key |
| `ASIC/common.mk` | resolves `PDK_BND_DECK` alongside `PDK_DRC_DECK` |
| `ASIC/genus-innovus/drc_project.mk` | added `BND_FOUNDRY_DECK`, `BND_RUNDIR`, `BND_CPUS` |
| `ASIC/genus-innovus/scripts/calibre/run_bnd.sh` | **new** — the driver the wrapper's header already promised |
| `ASIC/genus-innovus/scripts/calibre/README.md` | documents the BND flow alongside DRC |
| `ASIC/genus-innovus/Makefile` | `make bnd` (new); `LOGO_AP_ONLY` (new, default on) added to `logo`; `make drc-logo-check` (new) |
| `docs/tapeout/00-index.md` | this page listed |
| `docs/tapeout/50-bnd-and-logo-checks.md` | this page |

No foundry-owned file was read into, copied, or modified — the PDK mount (`$TSMC_65_HOME`)
stays read-only, per every existing convention in this repo (`ci/check-vendor-collateral.sh`,
`scripts/calibre/README.md` §"Two things not to break").

### Files touched by the promotion pass (2026-08-18, Part C)

| File | What changed |
|---|---|
| `scripts/ci/bnd_census.py` | **new** — BND census + waiver engine, sibling to `drc_census.py` |
| `scripts/ci/logo_census.py` | **new** — LOGO census over `drc-logo-check`'s output, imports `bnd_census.py` |
| `scripts/ci/imec_rule_diff.py` | **new** — generic N-way rule-by-rule diff engine against IMEC archive reports |
| `ASIC/genus-innovus/scripts/calibre/bnd_waivers.yaml` | **new** — cell-scoped BND waivers (AP.W.2 only; AP.W.1/AP.S.1 deliberately NOT waived, see §C.2) |
| `ASIC/genus-innovus/Makefile` | `BND_GDS ?= $(GDS)` bugfix (the override never worked); `DRC_LOGO_RUNDIR` added (was hardcoded into gitignored `calibre_runs/`, no override existed) |
| `ci/signoff.yaml` | new `bnd` and `logo` stages, both `gate: report`, both with real `check:`/`check_proof:` |
| `ci/fixtures/bnd/{pass,fail-design-results,fail-saturated-cap,fail-no-summary,fail-waiver-stale}` | **new** — `bnd` stage's `check_proof` fixtures |
| `ci/fixtures/logo/{pass,fail-nonzero-true,fail-no-summary}` | **new** — `logo` stage's `check_proof` fixtures |

No foundry-owned file was read into, copied, or modified in this pass either.
