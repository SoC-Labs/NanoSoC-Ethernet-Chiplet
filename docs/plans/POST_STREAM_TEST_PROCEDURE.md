# Post-stream test procedure — gdsrun-20260820 / -20260820b

Written 2026-08-20 23:58, with run A in route and run B in CTS. Everything here is
queued deliberately: none of it runs before a stream exists, and none of it is on
the path to producing one.

Two streams are coming:

| | run A | run B |
|---|---|---|
| tag | `gdsrun-20260820` | `gdsrun-20260820b` |
| worktree | `/home/dam1n19/SoCLabs/gds-run-20260820` | `.../gds-run-20260820b` |
| commit | `0c746cf` | `bd7cdc5` (supplies as top-level ports) |
| IO LEF | vendor, unpatched | vendor, unpatched |
| LEFOBS | retained | retained |
| PG label mechanism | SPNET map rows | ports **and** SPNET rows |

Both carry the two things imec objected to as reverted.

---

## Order

Steps 1-4 are licence-free and take minutes. Run them on **both** streams as soon as
each lands. Steps 5-7 need a tool seat; queue them.

---

## 1. Provenance — before anything else

A number is worthless if it belongs to a different stream. This project has produced
four false greens by grading the wrong file.

```bash
TAG=gdsrun-20260820          # or gdsrun-20260820b
W=/home/dam1n19/SoCLabs/gds-run-${TAG#gdsrun-}
B=$W/ASIC/eth-chiplet/build/$TAG
ls -l --time-style=full-iso $B/outputs/nanosoc_eth_chiplet_pads.gds
md5sum      $B/outputs/nanosoc_eth_chiplet_pads.gds
grep -E 'prov.design.git_sha|toolkit_git_sha|git_dirty' $B/reports/route_manifest.txt
```

Record the md5. Every later result must cite it.

---

## 2. THE DISCRIMINATOR — did the PG ports do anything? (run B only, free)

This is the experiment run B exists for. Two label mechanisms are active and they
anchor in different places, so they are individually countable:

* SPNET emits **one label per special net**, on the ring
* PIN emits **one label per port**, at the pin anchor

```bash
klayout -b -zz -rd gds=$B/outputs/nanosoc_eth_chiplet_pads.gds -r topcell_text.rb
```

`topcell_text.rb` must count **TOP-CELL text only**. The hierarchy carries 3,721 `VDD`
and 9,104 `VSS` labels inside vendor memory macros; a hierarchical scan passes on a
stream with zero top-cell labels. That trap has already caught us once.

| result | meaning |
|---|---|
| **4 PG labels** | the ports did nothing. `bd7cdc5` is a no-op; the SPNET rows are still carrying the labels |
| **8 PG labels** | the PIN mechanism fired. The SPNET rows are provably redundant and can be removed |

Controls, both already measured and on disk:

* `gdsrun-20260819/outputs/..._remap.gds` — stock map, **48 signal / 0 PG**. This is
  what failure looks like.
* `gdsrun-20260819/outputs/...pads.gds` — our map, **48 signal / 4 PG**.

Also record which GDS layer the PG labels land on. Do **not** expect 137 (that was the
2024 tapeout's, because its pads' port stack topped out at M7). Ours should be 133 if
they come from pin anchors on the slim IO cells' M3.

---

## 3. Are the pads back? (free)

LEFOBS is restored, so the bond pads should carry geometry for the first time since
17 August.

```bash
python3 <scan the GDS, per-structure geometry census>
```

| cell | before (08-19) | expected now |
|---|---|---|
| `PAD70GU` | 0 shapes | **13** on M8/M9/AP |
| `PAD70NU` | 0 shapes | **13** on M8/M9/AP |
| `PCORNER_G` | 0 shapes | **7** on M1..M7 |
| `PDDW16DGZ_G` | 33 | **64** (M1..M7 + VIA1,VIA2) |

If the pads are still empty, LEFOBS did not survive to stream-out and the map
transform needs re-checking before anything else here is meaningful.

**They should now be visible in KLayout**, which they have not been all week.

---

## 4. Padring and ERC (free, minutes)

```bash
python3 scripts/check_padring_gds.py --gds $B/outputs/nanosoc_eth_chiplet_pads.gds
make -C ASIC/genus-innovus erc-quick ERC_GDS=$B/outputs/nanosoc_eth_chiplet_pads.gds
```

Padring **must now pass**. On 08-19 it exited 1 with `PVDD2POC_G` placed 4x against a
mandatory 1 — the fix (`7581af0`) was seven hours younger than that run's launch
commit and is in both of tonight's. Also watch `PVDD2DGZ_G`, which read 8 against an
expected 11, and three edges one functional pad short. Those were never explained.

ERC passed on 08-19 (`OVERALL: OK`, all four supply names resolved) and should stay
passing. If it regresses, suspect the LEFOBS restoration.

---

## 5. Signoff DRC (one Calibre seat, ~1 h)

```bash
make -C $W/ASIC/eth-chiplet drc RUN_TAG=$TAG
make -C $W/ASIC/eth-chiplet signoff-report RUN_TAG=$TAG
```

Baseline is 08-19: **846 results**, of which `PO.R.8` = 691 is the vendor-macro
black-boxing artefact, leaving 155.

**Expect CSR.R.1 to go from 0 to roughly 56, and that is CORRECT.** Those are the four
`PCORNER_G` cells, whose 135x135 um obstruction is back in the corners. The 0 we have
been reporting was vacuous — we had stopped streaming the geometry the rule looks at.
Clearing them for real needs the ESD ruling on pad-ring bus continuity through the
corner, not a stream-map change.

Check the validity gate in the report before quoting any zero:

```
witness: CHIP=483  CHIP_NOSR=483  EMPTY_AREA=4  SEALRING=0  SR_EDGE=0
```

`EMPTY_AREA=4` means the corner check was armed. `EMPTY_AREA=0` would mean every
`CSR.R.1` subrule is vacuous, which is exactly how imec's own zero is produced.

Also expect BND-family results to appear for the first time — the pads now have AP
geometry, where 08-19 had 5 AP shapes on a 103-pad die.

---

## 6. GLS (53 s of simulation, no licence contention)

```bash
make -C ASIC/gls-netlist gls-netlist-gdsrun_cc          # adapt the item to the tag
GLSN_INITREG=random make ...                            # the reset-tree variant
```

08-19 passed 27/27 with `FORCES 0`, both CPUs booting, on zero-init **and** on
random-init. Anything less on the new streams is a regression and blocks submission.

---

## 7. LVS — QUEUED, needs a read-only Innovus session

Do this after the streams land, not before; it competes for Innovus.

**Current state, all committed today:**

| knob | value | effect |
|---|---|---|
| `BONDPAD_CELLS` | `PAD70GU PAD70NU` | got LVS to a verdict at all |
| `LVS_POWER/GROUND` | `VDD VDDIO` / `VSS VSSIO` | VDDIO/VSSIO are supplies now |
| `LVS_GLOBAL_NETS` | `VDD VDDIO VSSIO` | VSS omitted on purpose |
| `LVS_PG` | **0** | **the coverage gap** |
| `LVS_PG_PIN_TEXT` | **0** | **the coverage gap** |

Result on 08-19 after the first two: nets 62,493/62,493 with **0 unmatched both
sides**, `INCORRECT NETS` 0, `PROPERTY ERRORS` 0, and a residual of exactly **82** —
42 `PAD70GU` + 40 `PAD70NU`.

**But 98.5% of instances are boxed with zero pins and 216,632 source nets were deleted
before the comparison began. No standard-cell routing was checked.** A control run of
the same flow with `LVS_PG` on reconciled 268,171 nets against our 62,493.

### 7a. Turn the coverage on

```bash
make -C $W/ASIC/eth-chiplet lvs_pg_gds RUN_TAG=$TAG LVS_PG=1 LVS_PG_PIN_TEXT=1
make -C $W/ASIC/eth-chiplet lvs-batch  RUN_TAG=$TAG LVS_PG=1
```

`lvs_pg_emit.tcl` opens the routed database **read-only**, writes its own stream with
its own derived map, and never touches the tape-out GDS. So this is compatible with
imec's instruction to stop modifying the map — the LVS stream is a different artefact.

**EXPECT THE VERDICT TO GET WORSE.** The control surfaced 203 unmatched layout nets and
16,848 unmatched source. Those are real discrepancies currently invisible because the
nets are deleted before comparison. Going from `INCORRECT (82)` to `INCORRECT
(thousands)` is coverage arriving, not a regression, and must be reported that way.

Pass criterion is **not** a clean verdict. It is `nets reconciled` moving from ~62k
toward ~268k.

### 7b. What will NOT be fixed, ever, here

The 82 bond pads. `PAD70GU`/`PAD70NU` have **zero `PIN` sections** in their LEF, so
`LEFPIN` text has nothing to label. And TSMC has never released a SPICE netlist for
TPBN65V — the release note's own kit table shows the `spi` column empty at 200b, 200a,
140b and 140a. A `_BE` package would deliver GDS, not CDL.

Evidence this is inherent rather than ours: the same stock deck on the **accepted
Feb-2024 tapeout's own GDS** fails identically with `No matching ".SUBCKT" statement
for "PAD60LU"` x38. Different chip, different fabric library, same wall.

Declare it. Do not chase it, and do not clear it by excluding the pads — that deletes
the objects rather than checking them.

---

## 8. Open question worth one experiment

Restoring LEFOBS puts obstruction back on M1-M7 for 325 fillers and 4 corners. On the
LVS side that rebuilds a spacer sheet measured at **34 shorts, 1 of 52 ports
resolvable, one net with 6,147,666 connections**.

The two obstruction populations are on **disjoint layers** — pads on M8/M9/AP, spacers
on M1..M7 — so `LVS_PG_STRIP_OBS` could be made layer-aware and keep one while exiling
the other. `gdsmap_derive.py` already has that pattern in `OBS_KEEP_ON_MASK`;
`lvs_pg_emit.tcl` has no equivalent.

Cheap way to find out whether it is needed: finish the Feb-2024 control by adding an
empty `.SUBCKT PAD60LU` stub and re-running. If the accepted stream survives its own
M1-M7 sheet, we may be solving a problem we do not have.

Working directory for that control, already set up:
`<scratch>/fanis_lvs/` — deck, translated source, and the v2lvs logs are in place.

---

## 9. Also worth doing, cheap

* `NAME <layer>/NET` at **datatype 83** is the PDK's own second text channel
  (`virtuoso_65nm_1P9M_6X1Z1U_2.0a.map`, 24 layers carry it) and our stream-out does
  not use it. Our `SPNET` rows currently reuse datatype 0 and so share a layer with
  pin text. Datatype 83 would keep the channels separable, using the vendor's
  convention rather than an invention.
* Ask imec for the black-box LVS **Application Note** their user guide refers to, and
  for the cost and turnaround of their LVS service. Our `LEFPIN`-text method is
  inferred; theirs would be sanctioned. Free to ask.

---

## What "good" looks like tonight

A stream where padring passes, ERC passes, GLS is 27/27, DRC is ~846 plus a returned
`CSR.R.1` of ~56, the bond pads are visible in KLayout, and LVS reaches a verdict with
a declared 82-instance pad residual. That is submittable with a cover note, and it is
materially better than anything this project has produced before.

What it will still **not** have: verified standard-cell routing (until 7a), any
verification of the pad ring (never, here), and a foundry-sanctioned black-box LVS
method (until imec answer).
