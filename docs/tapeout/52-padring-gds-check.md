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
(`gate: report` — see Section 6).

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
three questions, and only three:

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

It additionally reports, informationally only and never gated on, whether
each watched structure's own definition carries any real geometry
(`BOUNDARY`/`PATH`/`BOX`) and on how many distinct GDS layers — see Section 5.

### What it cannot do

- It cannot ask "is `uPAD_TL_RX_0` specifically in the right spot" — there is
  no `uPAD_TL_RX_0` anywhere in the stream to look for. It can prove the
  *type* sequence on an edge is right, not that two adjacent same-typed pads
  (e.g. two `PDDW16DGZ_G` instances next to each other) are not swapped.
- It cannot prove the padframe is DRC-clean, or that the streamed geometry
  electrically matches the real vendor cell. We hold no usable
  `tpbn65v`/`tphn65lpgv2od3` GDS or CDL on this site to diff against — the
  same gap [09](09-signoff-checklist.md) and
  [10](10-tapeout-submission.md) already declare for DRC and LVS.
- It is **not** a substitute for the broker's own `CompareCells` and
  `Padringcheck`. A clean run means "our own names, counts and order are
  internally consistent, and present in the stream" — not "this pad ring
  will clear the broker's tools." Section 5 is exactly why that distinction
  matters.

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

**Result: clean.** All 12 cell families present, defined, and at the exact
expected count; per-side type order matches the floorplan intent on all four
edges; 2,338,232 total placements read directly under the top cell in ~1
minute.

```
  cell families checked : 12  (12 name+count OK)
  top-cell placements   : 2338232 total (all cell types, direct children only)
  geometry (informational, not gated): 12 watched structure(s) carry BOUNDARY/PATH/BOX geometry, 0 are entirely empty
    PAD70GU            13 geometry record(s) on 3 layer(s) [38, 39, 74]
    PAD70NU            13 geometry record(s) on 3 layer(s) [38, 39, 74]
    PCORNER_G           7 geometry record(s) on 7 layer(s) [31, 32, 33, 34, 35, 36, 37]
    PDDW04DGZ_G        64 geometry record(s) on 13 layer(s) [...]
    ...
  OK -- every expected pad/corner/bond-pad name, count and per-side type order matches the floorplan sources
```

**This is the honest, reportable finding the task set out to get, and it
does not agree with a naive first guess.** If our names were wrong or
mis-counted, this check would have failed in exactly the shape IMEC's did.
It did not. Every pad/corner/bond-pad name, count and per-side order this
design's own sources intend is **present and correct** in the exact GDS
IMEC evaluated. **The "No identical cell names found!" failure is therefore
not explained by a local naming, counting, or ordering mistake on our side.**

Two candidates remain, neither confirmable from this site (we hold no real
`tpbn65v.gds`/`tphn65lpgv2od3` file to check against — see
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

Both: **clean on names, counts and order**, same 12/12 result. But the
informational geometry census differs from the reference build in a way
worth flagging: in both current builds, `PAD70GU`, `PAD70NU` **and**
`PCORNER_G` are **completely empty** (no `BOUNDARY`/`PATH`/`BOX` geometry at
all in their own structure definitions), where the reference GDS IMEC saw
had at least thin geometry (13 records on 3 layers) for the bond pads and 7
records on 7 layers for the corner cell. The functional IO/power cells
(`PDDW*`/`PVDD*`/`PVSS*`) carry geometry in both. This does not change the
name/count/order verdict (still exit 0), but it means: **if a broker's
tooling is at all sensitive to structure emptiness (candidate 2 above), the
current builds are a strictly worse case than the one IMEC already rejected,
not a better one.** Worth raising with whoever owns the next stream before it
goes out.

---

## 6. Wiring

`ci/signoff.yaml` stage `padring-gds`, phase `physical`, `gate: report` (not
`block`) — same policy as `lvs-preflight` and `cdc`: a real check, run for
visibility, not yet trusted enough on enough builds to fail a pipeline on.
Promote to `block` once it has run clean across several real builds and any
false-positive shape (like Section 5's corner-calibration bug) has been
shaken out.

```
make asic-padring-gds        # from the repo root
make -C ASIC/genus-innovus padring-gds   # equivalent, GDS=... to override
```

Report lands at `ASIC/genus-innovus/reports/padring_gds_report.json`
(machine-readable) alongside the printed summary.

---

## Related pages

[00-index.md](00-index.md) ·
[06 — Fill, antenna, bond pads](06-fill-antenna-bondpads.md) — the ring this
check verifies, and where the pad-cell names/counts/orientations come from ·
[09 — Signoff checklist](09-signoff-checklist.md) ·
[10 — Tapeout submission](10-tapeout-submission.md) — Sections 3-4, the
not-self-contained-GDS gap this check's geometry census corroborates ·
[`scripts/check_chip_boundary.py`](../../scripts/check_chip_boundary.py) —
the netlist-side sibling check ·
[`docs/TSMC_BACKEND_PACKAGE_REQUEST.md`](../TSMC_BACKEND_PACKAGE_REQUEST.md)

---

[← 16 Open defects](16-open-defects.md) · [index](00-index.md)
