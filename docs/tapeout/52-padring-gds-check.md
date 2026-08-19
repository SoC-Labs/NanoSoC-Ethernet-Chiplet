# 52 — Padring GDS check

[← 16 Open defects](16-open-defects.md) · [index](00-index.md)

What IMEC signoff tools found that nothing local predicted, what a newcomer needs to know about "padframe" and "black-box submission" to make sense of it, the check this repo now has (scripts/check_padring_gds.py), and what it found when run against the exact GDS IMEC saw.

---

## 1. What happened

IMEC's signoff report on `nanosoc_eth_chiplet_pads.gds` (md5
`7f6214965501c911bd65069378ae911d`, byte-identical to
[`ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_outputs/nanosoc_eth_chiplet_pads_logo_full_L300.gds`](../../ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_outputs/))
came back with two related surprises:

```
CompareCells:   No identical cell names found!
                (comparing our GDS's cell names against TSMC's real pad
                library, tpbn65v.gds)
Padringcheck:   Design does not contain any TSMC IO cells or bondpads.
```

Nothing in this repo, before now, ever opened the actual streamed GDS to ask
"does the padframe I *think* I built actually look like a padframe from the
outside?" [`scripts/check_chip_boundary.py`](../../scripts/check_chip_boundary.py)'s
`check_pad_ring()` proves the **netlist** wires every bonded chip-boundary
port to a real pad-cell instance — but that is Verilog, not the stream that
actually goes to a broker. This chapter is about the gap between those two.

---

## 2. For anyone new: what "padframe" and "black-box submission" mean

The **padframe** is the ring of physical bond-pad and IO-driver cells around
the outside edge of the die — the structures a bond wire or bump actually
lands on, and the ESD-protected buffers that connect them to the chip's
internal logic. On this design that's 82 pad cells (see
[06 — Fill, antenna, bond pads](06-fill-antenna-bondpads.md)) plus 4 corner
cells, all licensed TSMC IP (`tphn65lpgv2od3` IO drivers, `tpbn65v` staggered
bond pads).

We do not hold usable rights to this site's *Back End* views of those
libraries — real transistor and metal geometry — only *Front End* (timing,
power, LEF abstracts). See
[`docs/TSMC_BACKEND_PACKAGE_REQUEST.md`](../TSMC_BACKEND_PACKAGE_REQUEST.md).
So our own GDS deliverable references these cells **by name only**:
[`place_bondpads.tcl`](../../ASIC/genus-innovus/scripts/place_bondpads.tcl)
creates instances named `PAD70GU`/`PAD70NU`, and
[`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`](../../ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v)
instantiates `PDDW16DGZ_G`, `PVDD1DGZ_G`, `PCORNER_G`, and so on. Called a
**black-box submission**: we submit the *shape* of the design (every cell
named and placed correctly) with the licensed cells' actual insides left
empty (or, per Section 3 of
[10 — Tapeout submission](10-tapeout-submission.md), reduced to their LEF
pin/obstruction geometry — the same 424-cell-master gap already declared as
`gds-completeness` in [`ci/signoff.yaml`](../../ci/signoff.yaml)).

**This is deliberate, standard practice, and not a bug to fix by drawing real
geometry.** The foundry — or here, the broker running signoff on our
behalf — is expected to hold the real libraries and merge the real geometry
back in, keyed on **cell name**. That is exactly why cell-name correctness is
not a formality: if our name for a cell does not match the name their
merge/compare tooling is keyed on, the substitution silently does nothing —
no error, no missing-cell warning, because as far as *our* tools are
concerned every name we used, we defined something for. The design "resolves"
locally and then arrives at the broker with a padframe their tools cannot
recognise. `CompareCells` and `Padringcheck` are exactly the foundry-side
tools built to catch that gap — and until now we had no local equivalent.

---

## 3. The check: `scripts/check_padring_gds.py`

```
scripts/check_padring_gds.py --gds <file.gds> [--top NAME] [--json OUT]
```

or, from `ASIC/genus-innovus/`:

```
make padring-gds            # checks $(GDS), defaults to outputs/$(BLOCK).gds
make padring-gds GDS=/path/to/other.gds
```

or from the repo root: `make asic-padring-gds`. Wired into
[`ci/signoff.yaml`](../../ci/signoff.yaml) as stage `padring-gds`
(`gate: block` since 2026-08-18 — see Section 6).

### What it checks, and where it gets "expected" from

It never hand-copies a list of expected pad names — that is exactly the trap
[`check_chip_boundary.py`](../../scripts/check_chip_boundary.py)'s own
docstring warns about (a list that only *claims* to track the source rots the
day the source moves). Every run parses the same three files fresh:

| Source | What it gives the check |
|---|---|
| [`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`](../../ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v) | instance name to functional cell type, for all 82 IO/power pads |
| [`ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io`](../../ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io) | the 4 corner cells, and each side's pad order as the floorplan intends it |
| [`ASIC/genus-innovus/scripts/place_bondpads.tcl`](../../ASIC/genus-innovus/scripts/place_bondpads.tcl) | which pads get `PAD70GU` (outer ring) vs `PAD70NU` (inner ring) |

From those three it cross-checks itself first (does every `.io`-listed pad
exist in `pads.v`? does every `place_bondpads.tcl` name land on the side the
`.io` file says?) — the same "both directions matter" discipline
`check_chip_boundary.py`'s `check_pad_ring()` already applies to the netlist.
On this design that cross-check is clean: 0 inconsistencies, 12 distinct
pad/corner cell families, counts exactly matching
[`docs/TSMC_BACKEND_PACKAGE_REQUEST.md`](../TSMC_BACKEND_PACKAGE_REQUEST.md)'s
independently-written table and
[06](06-fill-antenna-bondpads.md)'s per-side breakdown (top 17, left 26,
bottom 17, right 22 — each split outer/inner exactly as documented there).

Then it opens the **GDS itself** — stdlib Python only, no `gdstk`/`gdspy` and
no KLayout/Calibre Python bindings are installed on this site (checked; only
the KLayout GUI binary and a Ruby macro interpreter are on `PATH`). The
record-level parsing style (read a record's body only when you are actually
going to use it) follows the two GDSII stream-readers already in this tree,
[`scripts/ci/rom_gds_bits.py`](../../scripts/ci/rom_gds_bits.py) and
[`scripts/ci/gds_layer_census.py`](../../scripts/ci/gds_layer_census.py) — a
merged tapeout stream is ~300 MB of mostly standard-cell and macro geometry
that has nothing to do with the padframe, and paying to parse all of it here
would make the check unusably slow.

**The one fact this whole check is built around: GDSII has no instance-name
field.** An SREF/AREF placement carries a referenced *structure* name and a
transform, nothing else — confirmed empirically, not assumed:
`strings` over the reference GDS finds **zero** occurrences of any
`uPAD_*` instance name anywhere in the 305 MB file. So this check answers
four questions, and only four:

1. **Name + count.** Is every expected structure name (`PCORNER_G`,
   `PAD70GU`/`PAD70NU`, and the 9 `tphn65lpgv2od3` IO/power cell types)
   actually placed under the design's top cell the expected number of times,
   and is a structure by that name actually *defined* somewhere in the
   stream (not a dangling reference)?
2. **Misnamed / extra.** Any *defined* structure starting with one of our pad
   library's prefixes (`PAD7`, `PCORNER`, `PDDW`, `PDUW`, `PVDD`, `PVSS`) that
   is not one of the exact names expected — a version-suffix or case drift
   would show up here.
3. **Per-side order**, as far as anonymous geometry allows. The die's four
   edges are self-calibrated from the padframe placements' own bounding box
   (see the corner-calibration bug in Section 5 — **not** from the 4 corner
   cells alone, and never from a hard-coded floorplan size), every placement
   is bucketed to its nearest edge, and the per-edge cell-*type* sequence
   (ranked by position along that edge) is compared against the sequence the
   sources say the floorplan intends — accepting either direction, since
   geometry alone does not say which physical direction the source list's
   "first" entry corresponds to.
4. **Corner orientation** (added 2026-08-18 — Section 7). Each `PCORNER_G`
   placement's own live rotation, read directly out of its SREF's
   STRANS/ANGLE transform, diffed against a reviewed expected-orientation
   table.

It additionally reports, informationally only and never gated on, whether
each watched structure's own definition carries any real geometry
(`BOUNDARY`/`PATH`/`BOX`) and on how many distinct GDS layers — see Section 5.

### What it cannot do

- It cannot ask "is `uPAD_TL_RX_0` specifically in the right spot" — there is
  no `uPAD_TL_RX_0` anywhere in the stream to look for. It can prove the
  *type* sequence on an edge is right, not that two adjacent same-typed pads
  (e.g. two `PDDW16DGZ_G` instances next to each other) are not swapped —
  and, for the same reason, it can prove a *corner's* orientation (there are
  exactly 4 `PCORNER_G` placements, one per corner, unambiguously
  identifiable by position) but not an ordinary pad's, since
  `nanosoc_eth_chiplet_pads.io` declares no `orientation=` for them in the
  first place — see Section 7.
- It cannot prove the padframe is DRC-clean, or that the streamed geometry
  electrically matches the real vendor cell. We hold no usable
  `tpbn65v`/`tphn65lpgv2od3` GDS or CDL on this site to diff against — the
  same gap [09](09-signoff-checklist.md) and
  [10](10-tapeout-submission.md) already declare for DRC and LVS.
- It is **not** a substitute for the broker's own `CompareCells` and
  `Padringcheck`. A clean run means "our own names, counts, order and corner
  orientation are internally consistent, and present in the stream" — not
  "this pad ring will clear the broker's tools." Section 5 is exactly why
  that distinction matters.

---

## 4. Cell inventory, for reference

Exactly what the check derives from source, reproduced here because it is
useful to have in one place (also independently cross-checked against
[`docs/TSMC_BACKEND_PACKAGE_REQUEST.md`](../TSMC_BACKEND_PACKAGE_REQUEST.md)
and [06](06-fill-antenna-bondpads.md), which agree exactly):

| Cell | Family | Expected count |
|---|---|---:|
| `PCORNER_G` | corner | 4 |
| `PAD70GU` | staggered bond pad, outer ring | 42 |
| `PAD70NU` | staggered bond pad, inner ring | 40 |
| `PDDW16DGZ_G` | IO driver | 36 |
| `PVSS2DGZ_G` | ground pad | 12 |
| `PDDW04DGZ_G` | IO driver | 9 |
| `PVDD2DGZ_G` | supply pad | 8 |
| `PVDD1DGZ_G` | supply pad | 6 |
| `PVSS1DGZ_G` | ground pad | 4 |
| `PVDD2POC_G` | supply pad | 4 |
| `PDUW16DGZ_G` | IO driver (pull-up) | 2 |
| `PDUW08DGZ_G` | IO driver (pull-up) | 1 |
| **Total** | | **168** |

82 functional pads + 82 staggered bond pads + 4 corners = 168 — the check's
own `top-cell placements` count of watched-family instances on every GDS it
has been run against so far.

---

## 5. Validation: run against the exact GDS IMEC saw

```
python3 scripts/check_padring_gds.py \
    --gds ASIC/genus-innovus/runs/20260811T103338Z_fill-verify/prev_outputs/nanosoc_eth_chiplet_pads_logo_full_L300.gds
```

**Result at the time this check was first built: clean on names, counts and
order.** All 12 cell families present, defined, and at the exact expected
count; per-side type order matches the floorplan intent on all four edges;
2,338,232 total placements read directly under the top cell in ~1 minute.
**Section 7 below re-runs this exact GDS with the orientation extension and
finds the check was blind to a real defect in it** — read this section as
"names/counts/order were never the problem", not as "this GDS was clean".

```
  cell families checked : 12  (12 name+count OK)
  top-cell placements   : 2338232 total (all cell types, direct children only)
  geometry (informational, not gated): 12 watched structure(s) carry BOUNDARY/PATH/BOX geometry, 0 are entirely empty
    PAD70GU            13 geometry record(s) on 3 layer(s) [38, 39, 74]
    PAD70NU            13 geometry record(s) on 3 layer(s) [38, 39, 74]
    PCORNER_G           7 geometry record(s) on 7 layer(s) [31, 32, 33, 34, 35, 36, 37]
    PDDW04DGZ_G        64 geometry record(s) on 13 layer(s) [...]
    ...
```

**If our names were wrong or mis-counted, this check would have failed in
exactly the shape IMEC's `CompareCells`/`Padringcheck` name/count symptom
did. It did not.** Every pad/corner/bond-pad name, count and per-side order
this design's own sources intend is **present and correct** in the exact GDS
IMEC evaluated. **The "No identical cell names found!" failure is therefore
not explained by a local naming, counting, or ordering mistake on our side.**

Two candidates remained open at the time (neither confirmable from this
site — we hold no real `tpbn65v.gds`/`tphn65lpgv2od3` file to check
against — see
[`docs/TSMC_BACKEND_PACKAGE_REQUEST.md`](../TSMC_BACKEND_PACKAGE_REQUEST.md)):

1. **Library revision / naming-convention mismatch.** Our design pulls
   `tpbn65v_<rev>` (`config.tcl`'s `$IO_PAD_LEF`) and `tphn65lpgv2od3_sl_<rev>`
   — specific package/revision variants, resolved locally via `pdk_paths.sh` and never
   spelled here. If IMEC's `CompareCells` diffs
   against a differently-suffixed or differently-revved `tpbn65v.gds`, the
   names inside it may simply not be `PDDW16DGZ_G`/`PAD70GU`/etc. This is a
   question for the broker, not something fixable here — add it to
   [10 Section 4.1](10-tapeout-submission.md#41-who-merges-the-cell-level-gds)'s
   list of things to confirm in writing.
2. **Geometry-content sensitivity.** Section 4 of [10](10-tapeout-submission.md)
   and the `gds-completeness` entry in [`ci/signoff.yaml`](../../ci/signoff.yaml)
   already document that our streamed cells are LEF-abstract shells, not real
   layout (`PAD70GU is AP/RDL only` — confirmed again below). If a tool
   billed as "a pure cell-name diff" is in practice also sensitive to a
   structure being empty or near-empty, that would explain a "no identical
   cells" verdict even with perfectly correct names. This is stated as a
   possibility, not a proven mechanism — we have no way to inspect
   `CompareCells`'s own logic from here.

**Section 7 supersedes this list with a THIRD, now-CONFIRMED candidate: a
real corner-orientation defect, found independently by IMEC's own
`Padringcheck` and reproduced exactly by this check's own 2026-08-18
extension.** Candidates 1 and 2 above remain open and unconfirmed; they are
not mutually exclusive with the orientation defect.

**A process note on how this result was reached, left in deliberately:** the
first version of this check's per-side order logic calibrated the die's four
edges from the 4 `PCORNER_G` placements alone, and on that basis reported
mismatches on **all four sides**. Investigating with a one-off dump of raw
placement coordinates showed why: `PCORNER_G`'s own placement origin sits
~135 um *inset* from the true die edge on both axes (its LEF origin is not at
the cell's outer corner), while the ordinary pad cells sit exactly on the
edge (`x=0`/`x=1,600,000`, `y=0`/`y=2,000,000` — die `1600x2000 um` in 1 nm
units, matching `create_floorplan -site core -die_size 1600 2000 ...` in
[`floorplan.tcl`](../../ASIC/genus-innovus/scripts/floorplan.tcl) exactly).
Calibrating from corners alone put every edge ~135 um in the wrong place and
misclassified pads near a corner onto the wrong side — a bug in the
*heuristic*, not a defect in the chip. Calibrating instead from the full
population of padframe placements fixed it, and the result above is from the
corrected version. This is exactly the kind of measured-not-assumed
correction this handbook tries to model throughout.

### Also run against the current build outputs

```
python3 scripts/check_padring_gds.py --gds ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads.gds
python3 scripts/check_padring_gds.py --gds ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds
```

Both: **clean on names, counts and order** at the time this was first
checked, same 12/12 result (Section 7 below adds the orientation result for
fp1505). But the informational geometry census differs from the reference
build in a way worth flagging: in both current builds, `PAD70GU`, `PAD70NU`
**and** `PCORNER_G` are **completely empty** (no `BOUNDARY`/`PATH`/`BOX`
geometry at all in their own structure definitions), where the reference GDS
IMEC saw had at least thin geometry (13 records on 3 layers) for the bond
pads and 7 records on 7 layers for the corner cell. The functional IO/power
cells (`PDDW*`/`PVDD*`/`PVSS*`) carry geometry in both. This does not change
the name/count/order verdict, but it means: **if a broker's tooling is at all
sensitive to structure emptiness (candidate 2 above), the current builds are
a strictly worse case than the one IMEC already rejected, not a better
one.** Worth raising with whoever owns the next stream before it goes out.

---

## 6. Wiring

`ci/signoff.yaml` stage `padring-gds`, phase `physical`, **`gate: block`**
since 2026-08-18 (promoted from `report` — see Section 7 for why now, and
[53 — Gate-hardening plan](53-gate-promotion-plan.md) §1 row 1 for the
promotion criteria this satisfies).

```
make asic-padring-gds        # from the repo root
make -C ASIC/genus-innovus padring-gds   # equivalent, GDS=... to override
```

Report lands at `ASIC/genus-innovus/reports/padring_gds_report.json`
(machine-readable) alongside the printed summary. The signoff stage's
`check:` re-parses that JSON (never trusts the tool's exit code alone) and
fails on any non-empty `problems` list or on vacuity (zero cell families
measured, fewer than 4 corners resolved) — proven both directions by
`scripts/ci/signoff.py prove padring-gds` against
[`ci/fixtures/padring-gds/`](../../ci/fixtures/padring-gds/).

---

## 7. Corner orientation — the check IMEC's foundry tool caught and ours didn't

Added 2026-08-18, alongside the `report` → `block` promotion. Before this,
`check_padring_gds.py` read the `orientation=` attribute out of
`nanosoc_eth_chiplet_pads.io` (for the cross-checks in Section 3) but never
compared it against what the GDS actually shipped — it had no notion of
"expected orientation" at all, and could not have caught the defect below.

### What IMEC's foundry tool found, the same day

IMEC's `Padringcheck` (a **different** finding from the CompareCells/
name-recognition surprise in Section 1) reported all four `PCORNER_G`
corner cells rotated wrong:

```
Error-padringcheck, Lower left corner pad: PCORNER_G has wrong orientation R180 (it should be R0)
Error-padringcheck, Upper left corner pad: PCORNER_G has wrong orientation R90 (it should be R270)
Error-padringcheck, upper right corner pad: PCORNER_G has wrong orientation R0 (it should be R180)
Error-padringcheck, lower right corner pad: PCORNER_G has wrong orientation R270 (it should be R90)
```

(`ASIC/imec_results/Archive_nanosoc_eth_chiplet_pads_logo_full_L300_dummy_merged_dummyWithSealRing_18Aug26_19u28/padring/Padring_check.rpt`)

Every corner is exactly 180° from correct. The root cause was
`ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io`'s four
`orientation=` values, hand-edited once at commit `9f57214` and never
touched again until today's fix (commit `d93331f`):

| Corner | `.io` at 9f57214 (shipped) | `.io` today (fixed) |
|---|---|---|
| `uPAD_CORNER_TL` (topleft) | R90 | **R270** |
| `uPAD_CORNER_BL` (bottomleft) | R180 | **R0** |
| `uPAD_CORNER_BR` (bottomright) | R270 | **R90** |
| `uPAD_CORNER_TR` (topright) | R0 | **R180** |

### How the check reads it

GDSII carries a placement's rotation in the SREF's optional `STRANS`
(bit 15 = mirror flag) and `ANGLE` (an 8-byte GDSII REAL, not IEEE754 —
excess-64 exponent, base 16) records, which sit between `SNAME` and `XY` in
the element body. `scan_gds()` now reads both, but **only** for the cell
types an `EXPECTED_ORIENTATION` table names (today: just `PCORNER_G`) — the
other ~160 padframe placements are left alone, both because parsing a
transform for every one of them would cost real time on a 300 MB stream for
no benefit, and because (see below) there is nothing to diff them against.

Each corner's live placement is matched to a physical die corner
(topleft/topright/bottomleft/bottomright) using the same bounding-box
self-calibration `classify_sides()` already uses — never GDSII names, which
per Section 3 do not exist — and diffed against `EXPECTED_ORIENTATION`. A
mismatch is reported as a new `orientation-mismatch` problem kind, alongside
`name-or-count`, `misnamed-or-unexpected` and `padframe-order`, in both the
printed report and the JSON.

### Why `EXPECTED_ORIENTATION` is a hand-written table, not re-derived

This is the one design decision in this extension worth arguing for
explicitly, because two more convenient alternatives were both rejected on
purpose:

- **Not re-parsed from `nanosoc_eth_chiplet_pads.io` at runtime**, the way
  every other "expected" value in this script is. The `.io` file's
  `orientation=` field is *exactly what was wrong* — it held incorrect
  values for months. A check whose "expected" value is re-read from the same
  file every run would drift in lockstep with a repeat of the identical bug:
  someone edits `orientation=` back to wrong, "expected" silently follows,
  and the two always agree. A trip-wire cannot be wired to the thing it is
  guarding.
- **Not a derived formula** (e.g. "+90° per corner, walking the ring"). This
  repo has already made that exact mistake once: `04-floorplan-and-io.md`
  §4.2 (commit `b5d249c8`) *asserted* a "verified" rotational pattern from
  symmetry reasoning, stated with confidence, and it was wrong — `PCORNER_G`
  is rotation-symmetric for `CSR.R.1` (ESD ruling) purposes, which says
  nothing about which of the four TL/TR/BL/BR *positions* a given rotation
  belongs in relative to the pad rows that corner must abut.

So `EXPECTED_ORIENTATION` in `scripts/check_padring_gds.py` is a small,
hand-written, commented table — read directly from the corrected `.io` file
by a human on 2026-08-18 (not from memory) and pinned as an independent
static reference, each entry commented with which die corner it is and
which two pad-ring edges it must abut. If the floorplan is ever deliberately
re-designed, this table needs a human to update it by hand; it will never
silently track a bad edit to the `.io` file the way the rest of this
script's "expected" data deliberately does.

### Validation

**(a) Pre-fix values, real GDSII bytes — fires correctly.**
`ci/fixtures/padring-orientation/fail-corner-180/corner_test.gds` (generated
by `scripts/ci/gen_padring_orientation_fixture.py`, a tiny 858-byte real
GDSII stream carrying real STRANS/ANGLE records for the 4 corners at the
exact `9f57214` values):

```
$ python3 scripts/check_padring_gds.py --gds ci/fixtures/padring-orientation/fail-corner-180/corner_test.gds --top nanosoc_eth_chiplet_pads
  [orientation-mismatch]
    uPAD_CORNER_TL (PCORNER_G @ topleft): placed at ANGLE=90 ... expected ANGLE=270 ...
    uPAD_CORNER_BL (PCORNER_G @ bottomleft): placed at ANGLE=180 ... expected ANGLE=0 ...
    uPAD_CORNER_BR (PCORNER_G @ bottomright): placed at ANGLE=270 ... expected ANGLE=90 ...
    uPAD_CORNER_TR (PCORNER_G @ topright): placed at ANGLE=0 ... expected ANGLE=180 ...
exit 1
```

**(b) Fixed values, real GDSII bytes — passes.**
`ci/fixtures/padring-orientation/pass-corner-fixed/corner_test.gds` (same
generator, today's corrected angles): all 4 corners `OK`, `orientation-mismatch`
does not appear in `problems`, exit 0. (The fixture's minimal padframe still
reports real, expected `name-or-count`/`padframe-order` findings for the
other ~160 instances it does not include — orientation checking is
independent of those and unaffected.)

**(c) The exact GDS IMEC evaluated — reproduces IMEC's finding exactly.**
Re-running Section 5's reference GDS
(`ASIC/imec_results/Archive_..._18Aug26_19u28/nanosoc_eth_chiplet_pads_logo_full_L300.gds`,
byte-identical to the earlier reference, 2,338,232 placements, ~70s):

```
cell families checked : 12  (12 name+count OK)
corner orientation    : 4 corner(s) checked (0 OK)
  uPAD_CORNER_BL   expected ANGLE=  0  observed ANGLE=180  MISMATCH
  uPAD_CORNER_BR   expected ANGLE= 90  observed ANGLE=270  MISMATCH
  uPAD_CORNER_TL   expected ANGLE=270  observed ANGLE= 90  MISMATCH
  uPAD_CORNER_TR   expected ANGLE=180  observed ANGLE=  0  MISMATCH
```

Structurally identical to IMEC's own four `Error-padringcheck` lines quoted
above — same corners, same wrong values, same expected values, arrived at
independently by a completely different tool reading the same bytes. This
is the strongest evidence available on this site that `EXPECTED_ORIENTATION`
is correct and that the new check works.

**(d) fp1505 — the build that would actually ship — carries the same
defect, and the promoted gate now says so.**

```
$ make -C ASIC/genus-innovus padring-gds GDS=$PWD/ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads.gds
... 12/12 name+count OK, 0 corners OK on orientation ... Error 1
$ scripts/ci/signoff.py run padring-gds
-- padring-gds: FAIL  rc=2  74.8s  artefacts=1
```

fp1505 was placed and routed *before* today's `.io` fix, so this is
expected and correct, not a regression: fixing the source does not
retroactively fix an already-streamed GDS. **No re-stream against the
corrected `.io` has happened on this site yet** — there is currently no real
GDS anywhere in this repo's build trees that would pass the orientation
check. `ci/fixtures/padring-gds/pass` is therefore a *constructed* fixture
(clearly labelled as such — see `ci/fixtures/README.md`), not a captured
one, and this stage stays `block`-gated and RED on real evidence until a
fresh Innovus run picks up the fix.

---

## Related pages

[00-index.md](00-index.md) ·
[06 — Fill, antenna, bond pads](06-fill-antenna-bondpads.md) — the ring this
check verifies, and where the pad-cell names/counts/orientations come from ·
[09 — Signoff checklist](09-signoff-checklist.md) ·
[10 — Tapeout submission](10-tapeout-submission.md) — Sections 3-4, the
not-self-contained-GDS gap this check's geometry census corroborates ·
[53 — Gate-hardening plan](53-gate-promotion-plan.md) — the promotion this
page's Section 7 implements ·
[`scripts/check_padring_gds.py`](../../scripts/check_padring_gds.py) —
the check itself, `EXPECTED_ORIENTATION`'s own header comment has the full
reasoning Section 7 summarises ·
[`scripts/ci/gen_padring_orientation_fixture.py`](../../scripts/ci/gen_padring_orientation_fixture.py) —
generates the Section 7 regression fixtures ·
[`scripts/check_chip_boundary.py`](../../scripts/check_chip_boundary.py) —
the netlist-side sibling check ·
[`docs/TSMC_BACKEND_PACKAGE_REQUEST.md`](../TSMC_BACKEND_PACKAGE_REQUEST.md)

---

[← 16 Open defects](16-open-defects.md) · [index](00-index.md)
