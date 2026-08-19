# Eth Chiplet Convergence Plan — 2026-08-18 16:35 BST

Derived from a roll-call of 25 concurrent sessions and 14 closing notices.
Every figure below was re-measured against disk, not relayed. Where a session's
claim and the measurement disagreed, the measurement is what appears here.

    superproject HEAD   1b16380      remote bfbccf6, 1 ahead
    tidelink pin        aaa62ed8     tree checked out at 0a5857e4, +1, drifted
    eth toolkit pin     6d21f83      contains toolkit main (28ae8e8)
    compute origin/main 7c26f21      toolkit pinned 9feeca9, 13 behind main

---

## 1. The two blockers

### Synthesis is broken at HEAD, for every run

    gate1            SYN-FAIL: unexpected errors: SDC-202 x2, TIM-303 x2
    resyn-20260818   SYN-FAIL: unexpected errors: SDC-202 x1, TUI-66  x2
    full-20260814    0 SYN-FAIL — passed its own gate, outputs intact

Two independent runs, unmodified constraints, same gate. Cause is the C2
`set_max_delay` block: its `catch` can never fire because `read_sdc` reports
SDC-202 rather than raising a Tcl error, so the bound has NEVER applied on any
run in this project's history. Same latent pattern at
`tidelink_constraints.sdc:617`.

DO NOT allowlist SDC-202/TIM-303 — that converts a failing gate into one that
cannot fail. The fix is a timing-intent decision; standing recommendation is to
merge the TX group into `clk` rather than carry a datapath bound.

gate1's outputs are NOT reusable: written before the end-of-stage check, on a
stage that then failed its own gate. `full-20260814`'s ARE — which is what makes
the two tracks below independent.

### The stream intended for tapeout has never been route-gated

fp1505 has no `route_manifest.txt` and no `route_gate.txt`. `work/innovus.log5`
dies at `4_route.tcl:1625` on a `regexp` invoked without `--`, inside a toolkit
copy under a session scratchpad. The GDS exists only because `write_stream` ran
50 seconds before the crash.

The bug is ALREADY FIXED at our pin (`4_route.tcl:371` reads `regexp --`), so
the cost is one route re-run, not a redesign.

**The re-run is forced work — so spend it once.** Fold in the PG island feed,
metal fill for the 6,149 density windows, and route to completion together,
rather than paying for place-and-route three times. Register predicted numbers
before launching so the run is capable of failing.

---

## 2. Two tracks, not one chain

The P&R run consumes `SYN_RUN_TAG=full-20260814`, a netlist that passed its own
gate on 14 August. So broken HEAD synthesis blocks FLOW STABILITY but not THE
DELIVERABLE. These run side by side under separate owners.

**Track A — the stream** (owner: session `ad`)
1. One combined place–cts–route on the 08-14 netlist, PG island feed + metal fill folded in.
2. Gate it: route gate, DRC census, ROM at the reticle, and build the missing
   RTL→`_gate.v` LEC leg — which has never existed anywhere.
3. Make the evidence collectable. ROM and LEC proof are gitignored and outside
   `$ASIC_DIR`; `package_submission.sh:276` already states ROM verification is
   absent from the bundle.

   Constraint to state on the result: an 08-14 netlist excludes the D2D divider
   CDC fix and everything since. "PG fix validated" must not be read as
   "validated on current RTL".

**Track B — the flow**
1. Fix C2 so `make syn` completes at HEAD. One decision, then one edit.
2. Repair the two gates that cannot discriminate (section 3) — they are what
   will judge Track A.
3. Bump the tidelink pin to `0a5857e4` so the divider CDC fix reaches a clone.

---

## 3. Gates that cannot discriminate

**Vendor guard exits 0 when it has not run** — LIVE

    env -u TSMC_65_HOME  check_no_vendor_collateral.sh -> EXIT=0
                         "SKIPPED. It is not a pass."
    TSMC_65_HOME=...     check_no_vendor_collateral.sh -> EXIT=0
                         "OK (no vendor collateral tracked)"

Exit code alone cannot distinguish the two, and this is the script the licensing
question depends on.

**LVS preflight gives two answers for one design** — LIVE

    make -C ASIC/genus-innovus lvs-preflight -> OK — both layers clean
    make -C ASIC/eth-chiplet   lvs-preflight -> FAIL — rejected by layer 2

Related: the `ERC 8/8 clean` and `LVS 325,189/325,189` figures quoted repeatedly
today have no surviving artefact from the current flow.

**elab-strict** — FIXED today. `run.sh` now captures and tests `xrun_rc`; every
elab-strict pass from here is interpretable.

**One gate that does mean something:** eth's `lec-gate` is genuinely non-vacuous
— `_gate.v` vs `_gate_power.v` differ, `.VDD` counts 18 against 190,208.
Compute's equivalent IS vacuous. Same gate name, different meaning per die.

---

## 4. Claim versus measurement

| Reported | Measured |
|---|---|
| gate1 in flight, in `place` | DEAD. Abnormal exit, `syn Error 1`; no process |
| `git add -A` publishes 195 MB of licensed Arm IP | FALSE. One stageable path — the symlink removal. Contents ignored by `tidelink/.gitignore:72` in BOTH trees |
| Public branch has 196+ vendor findings; origin/main 212 | WRONG INSTRUMENT — a different submodule's script. Superproject guard is clean with the PDK mounted |
| M5 absolute anchor fixes rail shorts 4→0 | RETRACTED. Same-harness control: functional stranded 55→305, plus a new M1 short |
| 116 commits unpushed; `fbb0e99` local-only | STALE. All session work on the remote bar one commit |
| Shared index stale, will revert commits | Clear at close — but cleared 5x through the day, once holding an already-pushed pin. Real and recurring |
| LEC fixtures orphaned | LANDED. Wired at `ci/signoff.yaml:1139/1143`; `prove lec` 7 cases / 14 checks / 0 problems |
| elab-strict can false-green a killed run | CLOSED. 6 cases / 14 checks / 0, incl. `must_fail:fail-killed` |
| Flists reference untracked file, clone won't compile | ALREADY COHERENT at the pin — 5 flists, 4 tracked files at `aaa62ed8`. Verified on the worktree, the wrong tree |

---

## 5. Decisions only you can make

- **Compute's toolkit pin** `9feeca9` → `28ae8e8`. A clone of compute gets a pin
  that cannot take the fill decision you already made. `28ae8e8` unlocks
  `METAL_FILL_OWNER=foundry`, clearing 15 of 16 route hard failures at zero
  re-run cost — but it also adds `pg_via_check_layer_bottom M1`, so set
  `ROUTE_BUDGET_PG_VIAS` deliberately or trade a silent pass for a new failure.
  **Eth is unaffected** — its pin `6d21f83` already contains toolkit main.
- **Eth tidelink pin bump** to `0a5857e4`, else the divider CDC fix (a
  correctness fix on shipped RTL) does not reach a clone.
- **Bond-pad pitch** — 42 µm D2D drivers give 84 µm same-row pads, down from
  130. Unconfirmed bondable. Needs a packaging house, not a session. If it
  fails, the compute frame transposes and every macro moves a fourth time.
- **XHB500 symlink** — leave as is (your instruction). Not a licensing leak.
  But committing the ` D` breaks every consumer resolving that path.
- **`ROM_GDS_GEOM_ROOT`**, 16 lines held as a patch. Without it the geometry
  assertion prints a NOTE instead of asserting.

---

## 6. What the roll-call actually found

The duplication is not in the lanes. It is in the coordination.

Five sessions edited `power_plan.tcl`. Three built one ROM gate. Three waited on
a run that had already died. Two proved the same SDC defect independently on two
separate synthesis runs. And two sessions ran the same roll-call simultaneously
— producing contradictory push guidance to a session being wound down, and three
compute sessions asked twice to commit.

Session count went from 20 to 25 DURING the roll-call. One owner per track is
the remedy, and it only holds if new sessions stop being added to the same tree.

**Consent note:** compute's authorised push carried 9 commits whose author had
explicitly declined to publish them (`git push` sends the branch, not the
commit). They are now public on compute `origin/main`. Disclosed immediately and
unprompted by the pushing session.

**Disposition**
- stays alive: tidelink ×2, eda-modulefiles ×3
- captured, ready to close: 1c 56 a3 b5 b8 58 8d b4 c0 41, compute ×3
- open: `a4` (PG island verdict never reduced), `ab` (board lease kr260_01 held)
- unscoped, spawned during the roll-call: ac c1 f7 60 ad

---

## 7. Carried forward, still open

- SI is dead in STA. IMPESI-2016 persists; reports print `Signoff Settings: SI On`, which is false.
- A 60x hold disagreement is undiagnosed — Tempus 438 vs Innovus 7 FEP, and it grew when parasitics were added.
- Corner-correctness needs foundry collateral — one typical deck across three RC corners; available packs are 6X2Y, not 6X1Z1U.
- 55 functional stranded cells never measured on a completed run. Mechanism confirmed at the via; fix unverified across all eight at-risk islands.
- Netlist GLS is not the tapeout file — PG-completed, 17,231 unsupplied instances; CPU1 boots, CPU0 red.
- `docs/tapeout/28` carries its own "attribution is wrong" banner, and the banner's own remediation text is now also out of date.
- Compute is ~200 commits behind, lacks both peer-write mitigations eth carries, and its DMA-250 is missing the qctrl power-up patch eth and multicore both have.
- tidelink-phy has genuinely forked — compute `5c76e764` vs eth `8c560c57`.

---

## 8. IMEC re-check, 18Aug archive — full library merge changes the DRC picture, doesn't close it

A second IMEC archive arrived (`Archive_..._dummy_merged_dummyWithSealRing_18Aug26_19u28/`)
checking the **same original GDS** as the first (`nanosoc_eth_chiplet_pads_logo_full_L300.gds`,
md5 `7f621496…`, unchanged) — but this time IMEC's merge substituted BOTH the standard-cell
library (`tphn65lpgv2od3_sl.gds`) and a second library (`tcbn65lp.gds`), not just the pad ring.
First time real standard-cell geometry has been present around this design in any check we've
had. Four agents re-analysed against the 17Aug archive; findings below are cross-verified,
not single-sourced.

### PO.R.8 — CLOSED, confirmed by direct test

691 (4282) → **0, zero occurrences anywhere** — rule summary, by-cell breakdown, and the raw
892K-line RVE dump all agree. This is the controlled test the black-boxing theory
(`docs/tapeout/39-po-r8-resolved.md`) predicted: real standard-cell diffusion now drives the
macro-periphery gates that were reading as floating. No further action; keep as the reference
proof point if the theory is ever questioned again.

### Antenna — still a clean pass, now on 34% more real geometry

Device census 6,420,952 → 8,599,725 (+33.9%), antenna deck still 782/782 checks at zero.
Stronger confirmatory evidence of the same conclusion, not a new one. Does not by itself close
signoff — ERC and padring below still hard-error.

### P-corner rotation — exact fix identified, but it does NOT clear CSR on its own

**Root cause, triple-verified** (source `.io` file, live GDS instance transforms via klayout,
IMEC's own checker — all three agree exactly): `ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io`
hardcodes all four `PCORNER_G` corner instances 180° wrong. No generator/template touches this
file — it was hand-edited once (commit `9f57214`) and never revisited, so this is a direct
4-line fix, not a formula:

```
uPAD_CORNER_TL   orientation R90  -> R270
uPAD_CORNER_BL   orientation R180 -> R0
uPAD_CORNER_BR   orientation R270 -> R90
uPAD_CORNER_TR   orientation R0   -> R180
```
(Two frozen LEC-shadow copies of the same `.io` file exist and are not live P&R inputs — same
fix, lower priority.) **Not yet applied** — ready to apply on request.

**What this fix will and will not do, checked against the actual cell geometry, not assumed:**
- **Will** clear IMEC's mechanical `Padringcheck` orientation error outright.
- **Will NOT clear `CSR.R.1`** (the die-corner chamfer-triangle blocker, ~28–56 hits
  historically). `PCORNER_G`'s actual GDS content is a uniform 135×135µm solid block on M1–M7
  with LEF `SYMMETRY X Y R90` — i.e. the cell is geometrically identical under all four
  rotations. Rotating it changes nothing; `CSR.R.1` fires because the block itself sits inside
  the mandatory-empty 74µm chamfer, which is a placement/keepout problem
  (`floorplan.tcl:219-223`, gated on the still-outstanding ESD ruling), not an orientation one.
- **Plausibly helps, does not provably fix, `CSR.R.2:B/D` and `CSR.EN.8`.** These rules are
  attributed by IMEC to a cell named `CORNER_B`, which does not exist in our own merged GDS —
  IMEC substitutes real vendor corner-cell content we cannot see locally, and that content
  plausibly has orientation-sensitive seal-ring features our blank placeholder doesn't.
- **Does NOT explain most of the actual growth.** `CSR.R.2:B` 104→644 (+519%), `CSR.R.2:D`
  91→804 (+783%), `CSR.EN.8` 28→96 (+243%) between the two archives — but `CORNER_B`'s own
  by-cell count is **byte-identical** in the `bnd` deck between both archives, and in the main
  `drc` deck carries only **4 of 804** `CSR.R.2:D` hits (was 91/91 = 100% in the 17Aug archive).
  **The bulk of the CSR growth — roughly 800 of 804, 644 of 644, 96 of 96 — is NOT attributed
  to the corner cells at all**, and the reports truncate before naming what is. This is
  unresolved: raw RVE polygons carry coordinates, not instance names, so full attribution needs
  either a fuller by-cell report from the broker or a local re-check against a
  corner-rotation-fixed, fully-merged stream.

**Bottom line on CSR: fix the rotation because it's free, real, and requested — but budget for
CSR remaining the single largest open item afterward, not treat it as closed.**

### LOGO — unchanged, still open, fix already built and not yet wired into a submission stream

`LOGO.S.1`/`LOGO.R.4` stay saturated at the 1000-result cap in both archives — real geometry
did not move this at all, confirming it's a genuine, independent design gap (logo artwork vs.
keep-out), not a black-boxing artefact. **A fix already exists locally**
(`make -C ASIC/genus-innovus drc-logo-check`, `LOGO_AP_ONLY=1`, measured 2026-08-18 at a real
zero — see `docs/tapeout/50-bnd-and-logo-checks.md`) but has never been run through a
full-library-merge check, and is not yet part of whatever stream would actually ship. Needs:
(a) confirm the AP-only logo survives a full merge the same way, (b) wire it into the real
submission path.

### ERC — unchanged, same single error both archives, byte-identical

`[ Error ] - No labels found in topcell.` Full library merge changes nothing here, as
expected — this is a text-label gap in our own stream-out, orthogonal to library completeness.
A local fix exists (`make -C ASIC/genus-innovus erc`, doc 51) and partially resolves it on
`fp1505` (VDD/VSS now label; VDDIO/VSSIO still don't) — not yet re-checked against a
full-merge-equivalent stream.

### New: PVDD2POC "multiple cells in digital domain" — plausible fix identified, needs confirmation

`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:215,228,241,249` instantiates
`PVDD2POC_G` once per side (4 total), all wired to the same VDDIO net — electrically
redundant with the neighbouring `PVDD2DGZ_G` pads. Best-evidenced read: Calibre expects this
domain-boundary/anchor cell **once per ring**, not once per side. Likely fix: keep one
instance, convert the other three to `PVDD2DGZ_G`. **Not confirmable from what's on disk** —
no TSMC POC-cell datasheet is in-repo; needs a broker question or vendor doc before applying.

### New: 157 previously-invisible rule categories fired for the first time

Two groups, neither yet triaged: (1) transistor/standard-cell-internal geometry rules
(OD/PO/CO/PP/NP/NW/VIA-spacing/G.2/ESD families) that can only fire once real diffusion
exists to check — several capped at 1000, plausible merge-duplication artefacts rather than
design defects, unconfirmed; (2) seal-ring/corner construction rules (`CSR.S.*`, `CSR.EN.*`,
`CSR.R.3`, `SR.*`) coinciding with the second merged library, suggesting `tcbn65lp` supplied
real seal-ring/ESD-guard content the first archive's pad-only merge never showed us.

### Updated priority order for a DRC-clean push

1. **Apply the 4-line `.io` corner-rotation fix** — free, correct, triple-verified, clears the
   mechanical padring error outright. Ready on request.
2. **Trace the ~800/644/96 unattributed CSR.R.2/EN.8 hits** — the corner fix will not touch
   these; need a fuller by-cell report (ask the broker) or a local re-check post-rotation-fix.
3. **CSR.R.1's real fix** — the gated ESD ruling on corner-cell keepout/geometry
   (`floorplan.tcl:219-223`), independent of rotation.
4. **Triage the 157 new rule categories** — separate real defects from merge-duplication noise
   before treating any of them as work.
5. **Wire the already-built LOGO AP-only and ERC fixes into whatever stream actually ships**,
   and re-validate both against a full-library-merge-equivalent check.
6. **PVDD2POC**: raise with the broker/vendor docs before changing pad instantiation.
7. **PO.R.8 and antenna**: no action — both independently confirmed clean.

---

## 9. Retrospective — what should we have caught ourselves, and what's the approach

The corner-rotation fix (§8) is applied
(`ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io`, not yet committed). Before moving
on, every distinct finding across both IMEC archives was classified: could our own process or
tooling have caught this before a broker ever had to tell us?

| # | Finding | Classification | Evidence |
|---|---|---|---|
| 1 | `PO.R.8` (691→0) | **Structurally undetectable locally** | No vendor std-cell/IO GDS on site; the resolving proof borrowed a previously-taped-out reference chip's real geometry — nothing in our own flow can supply that. |
| 2 | `LOGO.S.1`/`LOGO.R.4` (1000-capped, both archives) | **Already detected, lost to process** | Three unlabeled Calibre runs, all dated 2026-08-10, true count 5497→1186→1134 — found and worked on, never written up, no Makefile target, until forced by archive 2 eight days later. |
| 3 | `CSR.R.1` (die-corner, ~28–56) | **Known and tracked, blocked on a decision** | `floorplan.tcl:219-223` names the exact mechanism in-code; the real fix needs an ESD ruling on pad-ring bus continuity that was never made. |
| 4 | `CSR.R.2:B/D`, `CSR.EN.8` growth | **Split** — the `CORNER_B`-attributed slice is undetectable (real vendor geometry we don't hold); the ~800/644/96-hit majority is **ambiguous**, unattributed even in IMEC's own by-cell report. |
| 5 | Padring 180° rotation (4× `PCORNER_G`) | **Split: tooling gap + a real process miss** | No orientation checker ever existed — a pure tooling gap. But `docs/tapeout/scripts/04-floorplan-and-io.md` §4.2 (commit `b5d249c8`, 2026-08-07) explicitly documented these exact four wrong values as a "verified," correct +90°/step pattern. Position and instance count were checked; rotation correctness never was. A document was written that looked directly at this and signed off on the wrong pattern. |
| 6 | ERC "no PG labels" | **Detectable, tooling gap (dominant)** | `ci/signoff.yaml` had zero `erc` stage. But the raw data already existed: four `calibre_erc.sum` files from 2026-08-10, LVS-experiment byproducts, each reading `TOTAL ERC RuleCheck Results Generated: 0 (0)` — sat unread for eight days because nothing framed that zero as an answer to "are PG labels present." |
| 7 | Padring "no TSMC IO cells found" | **Structurally undetectable locally** | Deliberate black-box submission (IP licensing); `check_padring_gds.py` proves our own names/counts/order were already fully correct. |
| 8 | `PVDD2POC` cardinality | **Ambiguous / needs external input** | No TSMC POC datasheet in-repo; fix plausible, unconfirmable without vendor documentation. |
| 9 | 157 newly-firing rule categories | **Structurally undetectable locally** | Only fire with real library geometry merged in — same mechanism class as items 1 and 7. |

**Roughly a third of the 9 named findings (1, 7, 9) are genuinely, structurally
undetectable** — they need licensed vendor geometry we neither hold nor are permitted to hold.
One (3) was correctly found and tracked but stalled on an external decision. Two (4's majority,
and 8) are honestly ambiguous.

**That leaves roughly a third (2, 5, 6) as failures inside our own process or tooling — say
this plainly: at least a third of what IMEC caught, we should have caught first, and in one
case (LOGO) we literally already had.** Item 5 is the sharpest: it isn't just that no
orientation check existed, it's that a document asserted the wrong pattern was correct nine
days before archive 2 arrived, checking the properties that didn't matter (position, count) and
never the one that did (rotation).

### The approach going forward

Both precedents in this project's own history (LOGO, CSR.R.1) point at the same root cause: **a
finding with no forcing function to close it decays into nothing** — whether that's silence
(LOGO sat in a gitignored directory) or false confidence (a wrong-but-asserted-verified doc
stood unquestioned for 12 days).

1. **Mandatory triage-or-defer on every local investigative run, in writing, within a fixed
   window (e.g. 3 business days).** Any Calibre/klayout/script run that produces a non-zero,
   capped, or "interesting" result gets exactly one of two outcomes on record: formalized into
   a `docs/tapeout/NN` page + wired Makefile/CI target, or explicitly deferred with a named
   owner and the specific blocking decision (the shape `floorplan.tcl:219-223` already gets
   right for CSR.R.1 — it just needs a companion punch-list entry checked at signoff time, not
   discovery-by-reading-Tcl). No result may live only in a dated `calibre_runs/` directory name
   as its sole record.
2. **A standing "IMEC/signoff finding triage" doc — one file, append-only, never scattered.**
   Each entry: finding, evidence, classification (the five buckets above), owner, status.
   Replaces the current pattern of writing a fresh doc reactively only after a broker archive
   forces the issue.
3. **A specific self-consistency review step for hand-edited floorplan/pad-ring files.**
   "Verified in the placed database" (position, size, instance count) is not the same claim as
   "verified correct" (does the rotation value match what the cell's actual geometry requires).
   Any hand-edit to `.io`/pad-ring files needs a second check against the cell's real
   orientation requirement — cheap, needs no vendor data, and would have caught this without
   waiting for IMEC. See `docs/tapeout/53-gate-promotion-plan.md` for the concrete gate this
   becomes.

Full IMEC-tool parity map and the phased gate-promotion plan: `docs/tapeout/53-gate-promotion-plan.md`.
