# THE PLAN — `nanosoc_eth_chiplet_pads` to a submittable GDSII

**Date:** 2026-08-09 · **Flow:** `ASIC/genus-innovus` (Genus 21.15 → Innovus 21.11-s130_1 stylus → Calibre → Conformal 22.10)

Produced from four independent read-only audits (power grid, DRC/physical verification, GDS merge & signoff collateral, timing closure) plus a synthesis pass. Evidence markers: **[V]** verified against an artefact · **[I]** inferred, reasoning stated · **[U]** undetermined.

---

## 1. STATUS — one page, honest

### 1.1 The framing fact

**Nothing has ever been routed, filled, streamed or DRC'd with the `power_plan.tcl` that is on disk today.** [V]

`pnr_route_eval` resumes a post-CTS database (`4b_pnr_route_eval.tcl:103-104,455`, `Makefile:263-265`), so the two routed runs everyone quotes — `20260808T174047Z_full100-b2-route` (DRC 67) and `20260808T223829Z_stage1b-route` (DRC 265) — **never executed `power_plan.tcl` at all**. Their archived `config/` trees show a configuration that did not run. Only `reports/eval/route_manifest.txt` records what ran.

Consequence: "64 DRC", "104 FEP", "2204 opens", "1518 dangling" all describe configurations that no longer exist. Historical, not current.

### 1.2 What IS true of today's configuration — now measured

The PG probe was repaired and run. First-ever measurement of today's `power_plan.tcl`:

| quantity | uncapped baseline (`full100-b1`) | **today, measured** |
|---|---|---|
| PG opens `IMPVFC-200` | 350 | **337** |
| PG dangling `IMPVFC-94` | 1518 | **1432** |
| PG-only `check_drc` | never isolated | **280** (277 Special Wire, **0 Regular Wire**) |
| `check_power_vias` M8→AP | "8 missing VIA8" | **clean** |
| `check_power_vias` M1→M9 | **never run** | **921 missing — 889 of them M4→M5** |
| probe wall-clock | — | **238 s** single-threaded |

**Today's PG is not worse than baseline on connectivity and produces zero Regular-Wire DRC.** The 43,091 vias deleted by the `stacked_via_bottom_layer M5` ordering bug do not manifest as opens — that defect is an IR/current-distribution concern, not a connectivity defect.

Post-CTS timing on the PG-fixed database (`runs/20260809T070855Z_pgfix-verify/reports/`): [V]

```
setup  WNS -0.000  TNS -0.000  FEP 1     (reg2reg only; in2reg/reg2out/Async all positive)
DRV    max_transition WNS -1.321  FEP 6  (I2C SCL/SDA + QSPI_IO[0..3] pad nets)
density 77.79%   insts 201,783   area 1,579,232 um^2
place+CTS: 81.5 min stage time, 87 min end-to-end
```

**100 MHz is closed at post-CTS. It has never been demonstrated post-route on this netlist.**

### 1.3 The caveats that matter

1. **27.4% of the design has never been timed.** 16,653 of 60,706 sequential clock pins untimed. The SDC fix exists (`inputs/tidelink_constraints.sdc:71-88`), is **uncommitted**, and **has never been through synthesis** — the last synthesis snapshotted the 08-07 file with zero occurrences of `D2D_RX_WORD_CLK`, and its `_syn.sdc` has **0** word clocks. [V]
2. **Innovus reads exactly one SDC** — `outputs/nanosoc_eth_chiplet_pads_syn.sdc`, written by a bare `write_sdc` (`asic-flows/Cadence/1_synthesis.tcl:93`). `inputs/tidelink_constraints.sdc` reaches P&R **only** via `write_sdc`.
3. **No parasitic extraction deck is wired.** Every post-route number reads `Parasitics Mode: No SPEF/RCDB` with `extract_rc_effort low`. The cap tables at `nanosoc_eth_chiplet_pads.mmmc:69,79,89` are ARM `1p9m_6x2z` — **the wrong metal stack**, modelling M9 at 0.9 µm when the tech LEF says 3.4 µm. The 5→103 post-fill FEP swing is fill *and* re-extraction, not separable. [V]
4. **Calibre has never been run here.** Zero `.drc.summary`, `.drc.results`, `_lvs.rep`, `.ant.results` anywhere.
5. **Every archived database in `runs/` fails to load.** `read_db` dies with `TCLCMD-989` — `work/<design>/libs/mmmc/<design>_syn.sdc` is a symlink into the live `outputs/`, which `scripts/ci/new_run.sh:198-203` empties when archiving. One dangling link per DB. **This is why "just re-check the database" has never been done.** The pgfix-verify post-CTS DB *does* exist: a complete 57 MB tree saved 09:35:22. [V]
6. **The corners are occupied.** A `PCORNER_G` sits at each of the four die corners, and it is a full-height IO-row square — it fills the corner completely, so the triangular keep-out the shuttle demands is not merely encroached on, it is entirely covered. That is why the CSR keep-out is a real blocker and not a clearance tweak. Verified at GDS level: `grep -a -c PCORNER_G` on the streamed GDS → **5** (one `STRNAME` + four `SREF`s). [V] (Corner-cell LEF dimensions not reproduced — TSMC licence; read them from the `tphn65lpgv2od3_sl` IO LEF.)
7. **The evaluation gates cannot be trusted until repaired** (§6). Worst case: the route gate judged `setup FEP 5` on a run whose filled database measured **103**.

### 1.4 Good news, under-recorded

- Metal fill has already run (`EVR_METAL_FILL=1` in two manifests) and added **zero** DRC violations. Every doc says otherwise.
- Post-P&R LEC is logically clean: 61,375/61,375 equivalent, 0 non-equivalent, 0 abort. `RESULT=FAIL` is harness policy on 34 points matched on both sides.
- GDS stream-out is the best-executed part of the downstream flow: unmodified foundry map file, correct `-unit 1000`, layers agreeing with the deck.
- **The QRC deck for the exact stack exists on this machine**: `/tsmc65pdk/65/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile`, 178 MiB. The comment at `scripts/preplace.tcl:31-34` ("No correct dataset exists here") is **wrong** — it looked only in `CMOS/util/`. StarRC `.nxtgrd`/`.itf` for the same stack at `/tsmc65pdk/65/CMOS/LP/pdk/CCI/online/1p9m_6X1Z1U/`.

---

## 2. THE DESTINATION — exit criteria, stated testably

### 2.0 The route question [U] — settle this first

Evidence points hard at Europractice/imec **mini@sic**: the manual is installed at `/tsmc65pdk/65/doc/TSMC_28nm_40nm_65nm_mini@sic_manual_ver_03_2026.pdf`, watermarked to the Southampton PDK admin, and `docs/TSMC_BACKEND_PACKAGE_REQUEST.md:7` names the Europractice licence. But the repo says "broker" in fourteen places, **never names one, and records no shuttle date**. [V]

Load-bearing sentences from the manual:

> *"You place the black-boxes of the cells in your GDS; the eptsmc team will import the layouts of the TSMC cells in your design."* (p.24)
> *"You do not need to add a sealring in your GDS. This is typically done by TSMC. … the area taken by the sealring is for free."* (p.20)
> *"In every of the 4 corners you need to leave a triangle area empty… Cleaning these violations is **mandatory even when you have not added sealring, otherwise TSMC will reject your submission**."* (p.21)
> *"The final GDS, after import of the back-ends of black-box IP (if any) and dummy filling, should be DRC/ANT/BND clean."* (p.22)
> *"A preliminary GDS should contain all the CAD layers you will use. The preliminary GDS does **NOT** need to be DRC/ANT/BND clean."* (p.22)

### 2.1 Branch A — mini@sic (assume until contradicted)

**Local cell-GDS merge is NOT a submission prerequisite.** The BE-package request is not on the critical path to submission; it is on the critical path to *local LVS and local density signoff*. That is a genuine downgrade of what the repo calls "the single blocker".

| # | Exit criterion | How checked | Owner |
|---|---|---|---|
| A1 | Streamed from a DB whose netlist SHA is recorded and matches the LEC'd `_pnr.v` | manifest records both SHAs; `lec-pnr` PASS on that pair | PD |
| A2 | Top cell correct, 1 top cell, 0 undefined references | already true (2467 cells) | PD |
| A3 | Contains all CAD layers used, **including CB (GDS 76)** bond-pad openings | grep stream report for layer 76 — **absent today** | PD |
| A4 | **Four corner triangles empty**, ≥74 µm legs, every mask layer | `CSR.R.1` == 0 with **imported** cell layouts — see §2.3 | PD + broker |
| A5 | Innovus `check_drc` == 0 hard, ≤N documented waivers | `check_drc` on routed DB | PD |
| A6 | Calibre DRC on our geometry: 0 non-waived + waiver dossier | `make drc GDS=…` | PD |
| A7 | Calibre ANT clean — *"never acceptable"* | never run | PD |
| A8 | Calibre BND clean — **mandatory per manual** | never run | PD |
| A9 | No seal ring in the GDS; `sealring.zip` **must not** ship | grep structure names | PD |
| A10 | No extra text/marker layers outside chip boundary | 349,272 text records + 2,498 `108/0` boxes today | PD |
| A11 | Density meets **foundry** rule (M1–M7 ≥10% @75×75/37.5; M8/M9 ≥20%; AP 10–70%) | never checked; LEF Innovus reads enforces **1% @20×20** | PD/broker |
| A12 | LVS run and clean (black-box acceptable) | needs CDL — procurement | Procurement |
| A13 | Die area 3.2 mm² accepted and paid for | 65 nm block is 1 mm²; extra per 0.1 mm² | Project lead |

### 2.2 Branch B — direct foundry / broker wanting a complete GDS

Everything in A **plus** `tcbn65lp_220a_BE`, `tphn65lpgv2od3_sl_210a_BE`, `tpbn65v_200b_BE` (GDS + CDL) procured and merged; seal ring added; full front-end DRC (`LUP.6`, `PO.R.19`, `SSD.DN.1`) clean. **4–8 weeks larger, unknown procurement lead.** Do not plan for it; do send an insurance request.

### 2.3 The corner criterion, and a trap in how you would check it

`/tsmc65pdk/65/CMOS/util/MAIN_DRC_TopMu/CLN65S_9M_6X1Z1U.26_2a`:

```
40:    #DEFINE FULL_CHIP                    // active — CSR.R.1 WILL run
3229:  CHIP        = EXTENT MT_LAYERS       // chip boundary from real mask layers
3508:  SR_EXC      = EXT SR_EDGE < 73.87 ABUT == 90 REGION INTERSECTING ONLY
3517:  EMPTY_AREA  = INT CHIP_NOSR < 74 ABUT == 90 REGION INTERSECTING ONLY
17105+: CSR.R.1:<layer> { EMPTY_AREA AND <layer> }   x 162 sub-rules
```

**74 µm legs at each 90° corner.** `PCORNER_G` is 135 × 135. 135 > 74. The violation is arithmetic, not opinion. [V]

**THE TRAP:** running Calibre on today's GDS will report **zero** CSR.R.1 — because `PCORNER_G` streams as an *empty* black-box cell and contributes no geometry to `EXTENT MT_LAYERS`. **The check is live and it is blind. A green CSR.R.1 from a local run on a black-box stream is a false green and must not be treated as evidence.**

**Two further deck-configuration defects, previously unrecorded** [V]:

- **`#DEFINE LP` (deck ~line 48) is commented out.** Our process *is* LP (`tcbn65lp`, CLN65LP). With LP off the deck checks the wrong `DPO.W.1`/`DPO.S.1/2/3` variants (:9008-9014 substitutes `.A` forms only under `#IFDEF LP`) and skips the N65LP `HVD_N` block (:10446). **Fix: add `#DEFINE LP` in the project wrapper before the INCLUDE** — one line; works because the deck never defines it.
- **`#DEFINE WLCSP_SEALRING` (deck line 62) is active.** We are wire-bond. This selects `SR_EDGE = CHIP_WISR NOT SCORE_WLCSP` (:3501) instead of the wire-bond branch (:3503), derived from `SROD = ODi INTERACT SEALRING` — and we have no `SEALRING` layer, so **CSR geometry may be computed on degenerate inputs.** SVRF has no `#UNDEFINE` here, so this cannot be fixed from the wrapper: it needs a project copy of the deck header (permitted — copy into the project tree, rewire, document) or a broker ruling. **Ask the broker for their exact switch set. That is the correct fix.**

---

## 3. PHASES

Binding rules: **one change per run** · every Genus/Innovus invocation redirected `< /dev/null` (on error the tool drops to a prompt and holds a licence — it has happened twice) · **a run without a `route_manifest.txt` did not happen**.

### Phase 0 — Repair the instruments (no EDA licence, ~1.5 days, PD)

Nothing downstream can be believed until this is done.

**0a. Fix the archiver symlink defect.** In `scripts/ci/new_run.sh`, after the archive move at :198-203, rewrite `$RUN/work/*/libs/mmmc/*_syn.sdc` to point at `$RUN/outputs/`, or copy the SDC into the DB. Then repair existing runs in place.
*Pass:* `read_db` on `runs/20260809T070855Z_pgfix-verify/work/nanosoc_eth_chiplet_pads` returns without `TCLCMD-989` and reports ≈201,783 insts.

**0b. Land the corrected PG probe.** Working scripts exist in session scratchpad, **not in the repo**. Land as `scripts/probe_pg_build.tcl` fixing three defects: add `set_db init_power_nets`/`init_ground_nets`, `read_power_intent -cpf`, `commit_power_intent` in the order `asic-flows/Cadence/2_pnr_setup.tcl:20,21,40,42` uses; pin the netlist rather than `[lsort -decreasing]` index 0 (which picks `runs/latest` by the ASCII accident `l > 2`); and note a fourth — `flow_utils.tcl:45` reserves `{flow_config say warn step die flow_fail try_step opt reports fresh_report mf}`, so a probe defining `say`/`step` *and* sourcing `config.tcl` dies with `IMPSE-110`. Print ViaGen totals in `PGBUILD-RESULT`.
*Pass (E0 acceptance gate):* reproduces `runs/latest` on all six quantities — pad_pin VDD/VSS wires 150/76; add_stripes M8/M9/M5 wires 46/52/300; Block ports 4360 with 3 open; Core ports 4426; Stripe ports 1 with 1 open; block_pin wires 9725 — in ≤240 s.

**0c. Repair the four gate defects that can hide a failure.**

| # | File:line | Defect | Fix |
|---|---|---|---|
| G1 | `4b:783-786` / `:1038` | gate judges pre-fill timing; comment at `:1039` is false | after `:1038`, `if {[info exists ::pnr_last(setup)]} {set setup_row $::pnr_last(setup)}` + same for hold; better, move the snapshot block after section 10 |
| G2 | `4b:288-303` | census has no bucket for `Blockage of Cell` with no `Wire`/`Pin`; `264+0+0 ≠ 265` | add `unclassified` bucket **and** assert `total == special+regular+pin_only+unclassified` |
| G3 | `4b:1698-1700`, `:794` | DRV arm `continue`s silently; fallback gated on setup/hold being empty, so DRV budgets vanish if only DRV fails to parse | `else { lappend hard … }`; ungate the fallback |
| G4 | `4b:1720-1751` | `route_gate.txt` prints "all within budget" with **no numbers** — a green gate is unauditable | print every budget and its measured value unconditionally |

*(Note: the manifest does dump budgets at `pnr_utils.tcl:977-983`, so "never prints" is half wrong — but `route_gate.txt` is what a reader sees.)*

**0d. `check_power_vias` looks at the wrong interface.** `4b:1166` uses `-layer_range {M8 AP}` — measured **clean** — and is blind to all 921 missing vias. Change to `{M1 M9}`. **Highest value-per-keystroke change in the plan.**

**0e. Mutation-test the gates before trusting them** (§6).

**0f. Set budgets that can fire.** Current vs measured: `DANGLING 1518` vs 1432 (and 37 routed — 41× headroom, dead gate); `DRV_TRAN 30` vs 6; `DRV_CAP 15` vs 0-1. Proposed: `SETUP_FEP 110` ratcheting to 0 · `HOLD_FEP 80` · `DRV_TRAN 8` · `DRV_CAP 3` · `DANGLING 60` · `OPENS` leave at 350 and document · `EVP_MIN_RV_VIAS 8→14` · **new `EVR_BUDGET_UNTIMED_PINS 50`**. **Never override a budget without recording why** — `HOLD_FEP` was overridden 3→70→110 against measurements of 37 and 29, twice, after being fixed in the file.

**0g. Add three constraint gates:**
- **A** — `1b_synthesis_eval.tcl` after `write_sdc` (:683): assert **24/24** word clocks in `outputs/*_syn.sdc`, counting **declarations**:
  `grep -c 'create_generated_clock.*D2D_\(RX_WORD\|RX_WORDN\|TX_WORD\)_CLK'` == 24.
  *~~Gate for the #1 open risk.~~* **RISK RESOLVED 2026-08-10 — see the note below; this is now a regression gate.*
- **B** — Genus `check_timing_intent` numeric assert: `untimed > 50` → fail.
- **C** — `3b_pnr_cts_eval.tcl` before `ccopt_design`: require 25 clocks **and** each word clock owning ≥1 sink. `:912-919` today fails only on *zero* trees.

**0h. Wire the selftest.** `scripts/selftest_route_gate.tcl` exists, is untracked, has **no Makefile target**, and none of its 7 cases would catch G1/G2/G3. Add a `route-gate-selftest` target; make `pnr_route_eval` depend on it.

**0i. Correct four false comments in `power_plan.tcl`:** `:221` "VIA1 collapsed 14149 → 111" (real: 14,061 → 23 → 14,075) · `:230-231` the M5-bottom claim is **inverted** · `:121`/`:153-154` the IMPPP-570 ×837 attribution (837→786, a 6% change) · plus a new one on the M4 crux (§3, E4).

*Phase 0 pass:* `make route-gate-selftest` green including a `Blockage of Cell` case; G1–G4 each demonstrated to *fail* on a mutated input; `read_db` works on an archived run; probe reproduces the six E0 quantities.

---

### Phase 1 — Harvest what we already own (1 day, 1 Calibre seat) — parallel with Phase 0

**1a. First Calibre run in this project's history.** `make drc GDS=$PWD/baseline_2026-08-07/outputs/nanosoc_eth_chiplet_pads.gds` — `GDS=` is **required**, `outputs/` is empty and the default path fails at `run_drc.sh:32`. First add `#DEFINE LP` to `scripts/calibre/nanosoc_eth_chiplet_pads.drc.rules` above the INCLUDE at :74.
*Settles:* whether DRC class (c) — the 40 M4-vs-macro records, 62% of the Innovus floor — survives in a tool that sees real polygons with real connectivity. LEF `OBS` carries no net name so Innovus cannot apply same-net exemption; the 8 memory GDS **are** merged (`config.tcl:190-199`). If they are the macro's own VDD strap, `Mx.S.*` different-net checks will not fire and 40 of 64 evaporate.
*Pass:* a `.drc.summary` exists; `Mx.S.*` counts for the 43 M4 SPACING sites enumerated. **Do not spend another P&R cycle on class (c) before this runs.**
*Do not conclude anything about CSR.R.1, density or front-end rules from this run* (§2.3).

**1b. Byte-compare the 59 duplicate GDS structures.** `IMPOGDS-4004` ×59: `rf_16k.gds2` redefines structures already in `rf_32k.gds2`; Innovus keeps the **first** and discards the rest. If the compiler emitted different leaf tiles per macro size, the merged GDS silently uses one library's tiles for all eight. **Free, minutes, and a genuine silent-corruption channel.**

**1c. Name the 3 open block ports.** With 0a done, `read_db` and `get_obj_in_area` over block-pin sites. Already bounded to "not an unpowered macro" (each macro PG pin is a comb of 40-288 PORT rects on one PIN; 3/4363 = 0.07%; no `MUSTJOIN` in any LEF) — consequence is local EM margin, but it must be named.

**1d. Confirm the corner cells at DB level** and determine what the pad-ring VDDIO/VSSIO/VDD/VSS buses do at the corners. **Either answer is a problem:** cells present → CSR.R.1 rejection; cells absent → four disconnected side-buses plus the manual's ESD guidance (p.33).

**1e. Wire the QRC deck** (`preplace.tcl`) and fix the cap tables (`mmmc:69,79,89`). **Worth more than any optimisation on the timing list** — without it every post-route number has an unquantified error bar and the `design_top_routing_layer` clamp rests on a stack model wrong by 3.8× on M9 thickness.
*Pass:* a post-route timing report whose header reads a real RC corner, not `No SPEF/RCDB`.

**1f. Delete dead files.** `scripts/calibre_lvs` is 0 bytes; `scripts/calibre_drc` is a stale Calibre Interactive runset; neither is referenced by the Makefile.

---

### Phase 2 — External clock starts on day 0 (project lead + procurement). **Send today.**

**2a.** The broker email (§9). Three questions gate design work: confirm the route; the exact corner requirement and acceptable remedy; their Calibre switch set.
**2b.** **Book the shuttle seat.** ~3 months lead, no date recorded anywhere. **Until booked, no submission date is real.**
**2c.** Die area: 3.2 mm² against a 1 mm² block → extra charge per 0.1 mm². Aspect 1:1.25 and <6 mm² both fine. Get the quote.
**2d.** BE-package request as insurance — not on the critical path under Branch A, but the only thing that unblocks local LVS and density signoff, and free to ask.
**2e.** Offer a **preliminary GDS** now. The manual permits it unclean. It de-risks layer-map and boundary surprises weeks early.

---

### Phase 3 — PG convergence on the probe (1 afternoon, 1 Innovus seat)

Now 238 s/experiment instead of 3.5 h. **One knob per run.**

| exp | change | expectation / note |
|---|---|---|
| E1 | restore the single `route_special` + `-block_pin_layer_range {M4 M5}` | Stripe ports 1→13, Block opens 3→0. `route_special` in Innovus 21.11 **does** have per-connect-type bounds — the justification at `power_plan.tcl:209-212` is **false for this tool version**. Additionally justified: the split buys nothing on the 0.155 family. |
| E2 | `floating_stripe` top `M9(9)` → `AP(10)` | the surviving `open: 1` closes. Pad-ring risers have AP geometry, unreachable at top=9. Run alone. |
| E3 | `stacked_via_bottom_layer` ordering fix (move M5 pass at `:200` before M9 pass at `:171`, or bottom=M1) | M9 ViaGen 1,144 → ~44,235. **Re-measure the M8 SPACING at (1188.955,191.000)-(1190.450,203.000) afterwards** — it will likely return, and then the lever is `-pad_pin_width`, *not* `-start_offset`. |
| E4 | *(nothing to run — settled)* | **The M4 0.155 cliff cannot be fixed by changing our wire.** Measured: our special wire is 0.350 µm, and a substantial minority of `rf_16k`'s M4 **OBS** rectangles are wide enough — over long enough run lengths — to select a stricter band of the M4 `SPACINGTABLE` than our own wire ever would. The object that triggers the stricter requirement is **the macro's own geometry**, not ours. Remedies are lateral only: gain 5 nm clearance, or stop routing at those sites. (Vendor macro-LEF obstruction geometry and the M4 `SPACINGTABLE` operands are not reproduced — TSMC licence forbids it.) |
| E5 | M6/M7 stripes (1.0 µm pairs, sp 0.5, 15 µm pitch, offsets 39.5/8) after the M5 pass | close some of the **889 missing M4→M5** vias. M6/M7 have 0.01%/0.00% routing overflow — free. M2/M3 congested (2.81%/0.60%) — do **not** put PG there. **No DRC reduction predicted.** |

**Do NOT:** apply the M8 `-start_offset 39.5 → 39.6` fix (the violation does not exist in today's config — today's PG DRC has one M8 record, an NSMETAL at (876.325, 246.195); and M8 stripe edges sit at 1144.5-1152.9 and 1204.5-1212.9, nowhere near the reported box). Do **not** re-try `route_special_block_pin_route_with_pin_width true` — the null test ran and is **bit-identical** (DRC 280 vs 280, 0.155 records 53 vs 53, zero differing signatures).

*Phase 3 pass:* Stripe ports 13, Block ports 0 open, `IMPSR-486` == 0, PG-only DRC ≤280 with 0 Regular Wire, and `check_power_vias {M1 M9}` missing-count materially below 921 — each attributable to exactly one change.

**Keep two conclusions separate:** the **opens** attribution (route_special split → 2204 opens; VIA1 14,061→23→14,075; mechanism `IMPSR-486`) is *proven*. The **DRC** delta 64→265 is confounded five ways and **not attributable from artefacts**. Do not let the first lend credibility to the second.

---

### Phase 4 — Get the word clocks into the file Innovus actually reads (1 synthesis run ~1.5 h)

**4a. Complete the SDC change — all three parts in ONE edit:**
1. Harden the RX guard at `tidelink_constraints.sdc:74-79`: `error`, not `continue`.
2. **Add the TX block.** No `D2D_TX_WORD_CLK` exists anywhere. The residual 1,979 untimed pins are *entirely* TX (lltx 154, txpstate 21, txrouter 5, sp2wl/tx_fifo 14, plus TX halves of four axi2wl FC-replay blocks). Anchor `-source [get_pins $WL/pad_clk_tx]`.
3. **Extend the async groups.** `constraints.sdc:156-161` groups only `D2D_TX_CLK_0` and `D2D_RX_CLK_0`. Sixteen ungrouped clocks means every lane↔lane and word↔capture crossing through the deskew async FIFO gets timed, producing spurious violations. Required in the same change.

**4b. Run synthesis and check gate A.** *Pass:*
`grep -c 'create_generated_clock.*D2D_\(RX_WORD\|RX_WORDN\|TX_WORD\)_CLK' outputs/*_syn.sdc` == **24**
**and** `check_timing_intent` untimed < 50.

> **The earlier form of this gate could not work, in both directions.** It was
> `grep -c 'D2D_\(RX\|TX\)_WORD_CLK' outputs/*_syn.sdc` == 16. Measured against the
> SDC the 08-10 P&R run actually consumed:
>
> * as written it scores **89** — it counts every *occurrence* line, including the two
>   `set_clock_uncertainty` lines per clock — so it **fails on a correct design**;
> * restricted to `create_generated_clock` lines it scores **16**, but there are **24**,
>   because `D2D_RX_WORDN_CLK` does not match `_WORD_CLK` (after `WORD` comes `N`, not `_`).
>   So it then **passes while blind to the eight inverted RX word clocks** — a third of
>   the fix.
>
> Count declarations, expect 24.

**The risk that made this a phase — RESOLVED 2026-08-10.** [V] `io_link_clk` is a
hierarchical RTL pin that does not exist post-map, and Genus had to re-express the word
clocks onto merged pins through a bare `write_sdc`. **It did.** Verified by reading the
file P&R consumed —
`runs/20260810T065131Z_honest-full-pnr2/work/..._cts/libs/mmmc/..._syn.sdc` (08-09 19:37):
8 `D2D_RX_WORD_CLK_*` + 8 `D2D_RX_WORDN_CLK_*` + 8 `D2D_TX_WORD_CLK_*`, 29
`create_generated_clock` and 4 `create_clock` in total. The fallback below was not needed.

Consequence for everything above and elsewhere: **stop quoting 16,653 untimed / 27%.**
That figure describes runs before this landed. Gate A is now a regression gate, not a
gate on an unproven step.

~~**Never tried; the #1 open technical risk.**~~ [U] Fallback: a post-`write_sdc` SDC appendix read as a second `-sdc_files` entry in `mmmc:186-188` — a design change, pre-design it now rather than improvising.

**Expect FEP to go UP.** 16,653 flops become visible to timing for the first time. **The success metric is the `check_timing_intent` collapse, not the violation count.** Say this before the run, not after.

**4c. Do NOT schedule the "tie `io_scan_mode`/`io_scan_clk`" RTL change. It is already done, one level up** — `build/chip/rtl/nanosoc_eth_chiplet_chip.v:119,121` reads `.scan_mode (1'b0), // tied` / `.scan_clk (1'b0), // tied`. The `UNCONNECTED_HIER_Z428/Z430` in the gate netlist is the *consequence* of that constant propagating, not evidence of a missing connection. A redundant tie would be a no-op. [V] The exact RTL origin of `Case constant(0)` stays **[U]**; the SDC is the fix that has been *measured* to work.

---

### Phase 5 — Enable CPPR, at the right point (folded into the next CTS run)

`grep -rn cppr ASIC/genus-innovus/scripts/` → **zero hits**. OCV is on (`cts_setup.tcl:72`) **without** CPPR — the maximally pessimistic combination. In `cts_setup.tcl` immediately after `:72`, **before `ccopt_design`**:

```tcl
set_db timing_analysis_type ocv
set_db timing_analysis_cppr true          ;# default threshold 20 ps
set_timing_derate -early -data  0.95
set_timing_derate -late  -data  1.05
set_timing_derate -early -clock 0.97
set_timing_derate -late  -clock 1.03
```

Spelling verified in `/eda/cadence/innovus/doc/UGcom/Timing_Analysis.html`. The four values already exist as `EVC_DERATE_*` at `3b:130-133` with exactly these defaults and `EVC_DERATE 0` — **simply off**. All four arms, always: `3b:747` documents that specifying some leaves the others inheriting the last defined value.

**Order matters and this flow has been burned by it.** `cts_setup.tcl:26-67` records that enabling OCV *after* ccopt cost 96,545 fictional hold violations and ~37,000 hold buffers.

*Expected:* hold 75 FEP @ −0.008 → near zero (8 ps is below the 20 ps threshold). Setup gain smaller — the −0.195 path is wire-dominated with little common clock.
**Defer useful skew.** The ~30 DEL005 count was never verified and CPPR probably erases the problem for free.

---

### Phase 6 — The first honest full run (~5.5 h, 1 Innovus seat)

`scripts/ci/new_run.sh honest-full syn pnr_place pnr_cts pnr_route`. Contains **exactly** the Phase 3 PG winner + Phase 4 SDC + Phase 5 CPPR, and nothing else. QRC wired.

Measured stage costs: synthesis ~1.5 h · place 17 m · pre-CTS opt 25 m · ccopt 25 m · post-CTS opt 9 m · hold opt 4.5 m · route+fill+stream ~2-2.5 h.

*Pass — all of:* `route_manifest.txt` exists · gate reports **post-fill** setup/hold (G1 proven by the two lines agreeing) · `check_drc` total recorded with the class-sum invariant holding · `check_power_vias {M1 M9}` recorded · GDS ≥200 MB **and** its per-layer shape inventory non-empty (`-report_file` today writes a 7-line header and nothing else) · `lec-pnr` PASS on *this* `_pnr.v` · netlist SHA recorded beside the GDS SHA.

**Provisional if the corner remedy is not yet known.**

---

### Phase 7 — Physical verification for real (2-3 days, Calibre seat)

**7a.** Calibre **DRC** on the Phase 6 stream with the agreed switch set.
**7b.** Calibre **ANT** (`/tsmc65pdk/65/CMOS/util/ANTENNA_DRC/CN65S_9M_ANT.26_2a`) — never run; *"antenna violations are never acceptable"*.
**7c.** Calibre **BND** (`/tsmc65pdk/65/CMOS/LP/pdk/Calibre/drc/wire_bond/CN65_WIRE_BOND_9M_6X1Z1U.20a`) — **mandatory**, never run.
**7d. Density against the foundry rule.** `grep -c "75.0um X 75.0um"` on the density report today = 0. Measured minima at the *wrong* window (20×20): M8 **7.60%**, M2 18.60%, M4 18.03%. M8's real floor is 20% @75×75 — roughly a third of it. Either metal fill closes this or the broker's dummy fill does.
**7e. CB layer.** GDS 76 appears nowhere — as streamed the die has no bond-pad openings. Determine whether `place_bondpads.tcl` should emit it or whether it arrives with the imported `PAD70GU/NU` layouts. [U]
**7f. Text and marker layers.** 349,272 text records, 2,498 `108/0` boxes.
**7g. Waiver dossier.** Per record: GDS extract with net label · macro LEF excerpt showing `OBS` not `PIN` · the `.drc.results` entry · **and LVS proving chip VDD connects to macro VDD — which cannot be produced today** (no CDL). Flag that gap to the broker in advance.

---

### Phase 8 — The corner fix (schedule-driven, cost unknown until 2a answers)

**Upstream floorplan work; it invalidates everything downstream.** Sequence as early as the broker's answer allows.

Good news: **the corner cells are not in the gate netlist.** `grep -c uPAD_CORNER *_gate_power.v` → 0; they are placed from `scripts/nanosoc_eth_chiplet_pads.io:23,47,78,101` as physical-only instances. [V] So a corner change is **P&R-only (~4 h), not a resynthesis** — *provided* the remedy does not move the pad ring or core box.

| remedy | change | cost | risk |
|---|---|---|---|
| **R-a** | delete the 4 `PCORNER_G`, fill with `PFILLER*_G` | `.io` edit + P&R (~4 h) | **breaks pad-ring bus continuity at all four corners** → four independent side-buses; ESD guidance violated; needs an electrical ruling |
| **R-b** | keep corner cells, chamfer top-level geometry inside the 74 µm triangles | needs a post-stream boolean **on geometry we do not own** → **not possible locally** | high; only the broker can execute |
| **R-c** | move the pad ring inward ≥74 µm at corners, keeping the die outline | `.io` + `floorplan.tcl` + possibly `CORE_TO_IO` → core box moves → macro placement, PG offsets, timing all move | full re-run incl. synthesis; highest cost |

**Do not choose between these on our own judgement** — it is a broker question, and they differ by an order of magnitude.

*Pass:* CSR.R.1 == 0 **as evaluated on a stream containing real corner geometry** — under Branch A that means *their* acceptance report. Ours can only be a proxy.

---

### Phase 9 — Bundle and submit

Netlist↔GDS pairing enforced (nothing enforces it today; the LEC'd `_pnr.v` sha1 `45a6c089…` is a *different* netlist from the `baseline_2026-08-07` GDS). Full-chip RTL→gate LEC produces **no verdict** today — `lec_rtl_shadow/` has a dofile and work tree, no log. Close it. `make lec`'s dofile ends `exit -f`, so **a non-equivalent result exits 0** — fix or replace with `lec-pnr`'s harness.

---

## 4. CRITICAL PATH AND LONG POLES

**Schedule-driven:**
1. **Shuttle seat, ~3 months lead, not booked.** The long pole. No submission date exists until it is.
2. **Broker's answer on the corner remedy.** Days. Gates Phase 8, and Phase 8 invalidates Phases 6-7 if it lands after them.
3. **BE packages** (Branch B insurance, and the only route to local LVS). Unknown lead.

**Effort-driven, genuinely parallel:** Phase 0 (1.5 d, no licence, **now**) · Phase 1 (1 d, Calibre, **now**) · Phase 3 (0.5 d, after 0b) · Phase 4 (0.5 d, after 0g) · TideLink RTL (2-3 d, **now**) · Phase 6 (6 h, after 3+4+5) · Phase 7 (2-3 d, after 6).

**The true critical path: [broker answer on corners] → Phase 8 → Phase 6 re-run → Phase 7 → submit.** Everything else fits inside it. **The engineering is not the constraint; the unbooked seat and the unanswered corner question are.**

**Start today, in parallel:** the broker email (2a-2e), Phase 0 in full, Phase 1a/1b/1e, and the TideLink RTL items.

---

## 5. OWNERSHIP

### (a) Flow / PD engineer
All of Phase 0, 1, 3, 5, 6, 7, 9; Phase 4b; Phase 8 execution once the remedy is chosen.

### (b) RTL owner — TideLink

> **⚠ THE TWO-CHECKOUTS TRAP.** The build uses the **submodule** `nanosoc-ethernet-chiplet/tidelink`, HEAD `1112d638`. The standalone `/home/dam1n19/SoCLabs/tidelink` is at `9eaafb71`, where `651a71b` exists only on branch `integ/tidelink-consolidated-2026-08-07` and is **not checked out**. **A fix landed on the standalone checkout will not reach this tapeout.** Land on the submodule, bump the parent pointer, record it in `MANIFEST.txt`.

**R1 — `doorbell_response_acc` (16 endpoints, largest failing group).** `tidelink/src/rtl/fifo/tidelink_apb_regs.sv`, declaration **:358**, `always_ff` **:364-378**. Two 17-bit adders rooted on the unregistered module input `pwdata[15:0]` (:32), qualified by purely combinational `apb_write` (:212-213):
```
373:  if ({1'b0, doorbell_response_acc} + {1'b0, pwdata[15:0]} > 17'h0FFFF)
376:      doorbell_response_acc <= doorbell_response_acc + pwdata[15:0];
```
Change: register `pwdata[15:0]` plus qualified strobes; collapse add→compare→add into ONE 17-bit carry chain taking saturation from `acc1_sum[16]`. Exactly the transform `pair_credit` already got (**:435-457, :483-485**, rationale at **:397-420**).
Cost: one cycle APB-write→accumulator-update; self-recurrence untouched so throughput unchanged; both IRQs are level IRQs into an M0+ NVIC so a one-cycle shift is unobservable. **Not the credit-return loop** — `credit_delta_data`/`release_credits_trigger` untouched, so the 2026-06-12 credit-leak fix is unaffected.
Test: cocotb, back-to-back zero-wait-state APB accesses to the same accumulator.

**R2 — `released_credits_acc` (3 endpoints).** Same file, declaration **:327**, `always_ff` **:337-352**, `:347`/`:350`. Same transform.

**R3 — DO NOT TOUCH `pair_credit_next`.** Fixed by `651a71b`, present in the submodule, worst slack **+0.423 ns**, and **zero** of its 97 endpoints among the 102 failing.

**R4 — DO NOT do the scan-pin tie.** Already done at `build/chip/rtl/nanosoc_eth_chiplet_chip.v:119,121`.

### (c) Procurement / licence holder
2c (die-area quote), 2d (BE packages — the exact ask is written up in `docs/TSMC_BACKEND_PACKAGE_REQUEST.md`). The manual notes RC extraction decks are available on request from `IC-link.foundrysupport@imec.be` — a fallback if the local QRC deck proves unusable.

### (d) External / broker — §9.

### (e) Project lead — decisions required

| # | Decision | Blocks | Needs |
|---|---|---|---|
| D1 | Confirm route; name the broker; book the shuttle seat | **everything** | nothing — send today |
| D2 | Choose corner remedy R-a / R-b / R-c | Phase 8, and validity of Phases 6-7 | broker Q3 |
| D3 | Accept 3.2 mm² and its extra-area charge, or shrink | seat booking | quote |
| D4 | If timing does not close post-route with word clocks in: accept lower f_max, or spend a floorplan cycle | Phase 6 exit | Phase 6 result |
| D5 | Class (c): waiver dossier vs P&R cycles | Phase 7 | Phase 1a result |
| D6 | Pursue Branch B as parallel insurance, or not | procurement effort | cost of the ask |

---

## 6. VERIFICATION OF THE VERIFICATION

**The repeating failure mode is gates that cannot discriminate.** Not anecdotal:

- DRC budget set to the day's measured count
- `EVR_BUDGET_HOLD_FEP` overridden 3→70→110 against measurements of 37 and 29 — **after** being documented and fixed in the file
- `DRV_TRAN` 107 vs measured 6 (18×); `DRV_CAP` 32 vs 0-1 (32×); `DANGLING` 1518 vs 37 (41×)
- a census class that silently swallows a `Blockage of Cell` record — the gate printed `HARD FAILURES: none` on a 265-violation run
- the route gate judging pre-fill numbers while its own comment claims otherwise
- `EVR_CHECKS=0` producing a vacuous green with DRC, antenna and connectivity skipped and nothing recording the skip
- `1b_synthesis_eval.tcl` having **no** numeric gate at all — synthesis can close at WNS −50 ns and print `Status : OK`
- `make lec` exiting 0 on a non-equivalent result
- the CSR trap in §2.3, which would have produced a false green on the *rejection-grade* defect

**Rule: a gate is not trusted until it has been shown to fail.** Before Phase 6, mutation-test each:

| gate | mutation | must produce |
|---|---|---|
| G1 timing snapshot | synthetic post-fill row worse than pre-fill | fails on the post-fill number |
| G2 DRC census | `MINCUT … Blockage of Cell` with no `Wire`/`Pin` | `unclassified 1`, invariant fires |
| G3 DRV | a DRV summary that parses while setup/hold do | hard failure, not silent `continue` |
| G4 budget print | any run | every budget and its measurement in `route_gate.txt` |
| A word-clock | `_syn.sdc` with 15 of 16 | synthesis stage fails |
| B untimed | `check_timing_intent` returning 200 | fails |
| C clock trees | a spec with 9 trees when 25 expected | fails (today it passes) |
| `EVR_CHECKS` | set to 0 | gate refuses to emit `HARD FAILURES: none` |
| `lec` | selftest already exists and is the model the others should copy | |

**Re-read every historical green with this in mind.** "DRC 64 across ten runs" is genuinely strong — 63 distinct geometries, bit-identical across a full re-synthesis — but it was measured by a census with a hole in it, at a stage whose budget was the measurement.

---

## 7. RISK REGISTER

| # | Risk | Likelihood | Consequence | Cheapest experiment | Fallback |
|---|---|---|---|---|---|
| **R1** | Word clocks do not survive `write_sdc` **[U]** | Medium | 27% of the design stays untimed through tapeout | Phase 4b — one synthesis run + gate A, ~1.5 h | mmmc second `-sdc_files` appendix; pre-design now |
| **R2** | Corner remedy turns out to be R-c | Medium | full re-run incl. synthesis; ~2 weeks | broker Q3; days, free | book the extra P&R cycle now |
| **R3** | Route is **not** mini@sic **[U]** | Low-Med | BE packages become a hard blocker; +4-8 weeks | broker Q1; today, free | D6 insurance track |
| **R4** | Merged GDS has silent duplicate-cell corruption **[U]** | Low | wrong leaf tiles for 7 of 8 macros | Phase 1b — free, minutes | re-merge with `-uniquify_cell_names` |
| **R5** | IR drop unacceptable — **no IR analysis has ever run** | Medium | silicon fails at speed or at all | needs `generate_pg_library` PGV, possibly blocked by missing std-cell GDS/CDL **[U]** | 6 VDD @16.5 mA vs 4 VSS @24.8 mA (107 mW ≈ 99 mA @1.08 V) — **ground carries 50% more per pad**, ~595 µm worst lateral, M8↔M9 tie down 25%. Add VSS pads on L/R (currently 0) |
| **R6** | 3 open block ports are real EM defects **[U]** | Low | local reliability | Phase 1c — free with 0a | route them explicitly |
| **R7** | Corner triangles not what we think (chamfer geometry, `WLCSP_SEALRING` skew) **[U]** | Medium | wrong fix applied | broker Q3 + Q4 | over-clear: 100 µm not 74 |
| **R8** | Clock inversion: RTL clocks `link_data_reg` on `posedge ~count[3]`, netlist on `posedge count[3]` via positive-edge `DFCNQD1` **[U]** | Low-Med | 8-cycle phase shift if uncompensated | confirm LEC scope covers this mapping — do not assume | targeted equivalence run on `WavD2DGpioRx` |
| **R9** | Post-fill DRC on today's PG worse than 280 | Medium | more Phase 3 cycles | Phase 3 de-risks it | one-knob bisect on the probe |
| **R10** | Density fails the real rule (M8 ~7.6% vs 20% floor) | **High** | broker refuses to run dummy fill | Phase 7d | aggressive `add_metal_fill`, or broker runs it |
| **R11** | Antenna violations exist, never checked | Medium | *"never acceptable"* — hard reject | Phase 7b | diode insertion; `EVR_MIN_DIODES` floor exists |
| **R12** | LUP.6 tap cells — libraries are tapless; flow inserts `add_endcaps DCAP4` and **no well taps**. Manual warns it *"will only become visible after eptsmc has imported the layouts"* **[U]** | Medium | discovered in their acceptance report | broker Q5 | `add_well_tap` pass; P&R-only |
| **R13** | Calibre deck switches wrong (`LP` off, `WLCSP_SEALRING` on) | **Confirmed** | every local DRC result against the wrong rule set | Phase 1a with `#DEFINE LP` | project copy of the deck header, documented |
| **R14** | Concurrent sessions mutate the repo | High | lost or conflicting edits | `git status` before every stage; never `git add -A` | per-change branches |

---

## 8. SCHEDULE

**Assumptions:** one Innovus and one Calibre seat on demand · 14 local CPUs · measured stage costs hold · no more than one full re-run forced by the corner remedy · broker replies within 5 working days.

| Phase | Elapsed | Licence | Can start |
|---|---|---|---|
| 0 Instruments | 1.5 d | none | **now** |
| 1 Harvest | 1 d | 1 Calibre | **now** (1c after 0a) |
| 3 PG convergence | 0.5 d | 1 Innovus | after 0b |
| 4 Word clocks | 0.5 d | 1 Genus | after 0g |
| 5 CPPR | folded into 6 | — | after 4 |
| 6 First honest full run | 6 h + 0.5 d analysis | 1 Innovus | after 3,4,5 |
| 7 Physical verification | 2-3 d | 1 Calibre | after 6 |
| RTL R1/R2 + cocotb | 2-3 d, parallel | none | **now** |
| 8 Corner fix — R-a | +0.5 d + 4 h P&R | 1 Innovus | after D2 |
| 8 Corner fix — R-c | +1.5 wk incl. full re-run | seats | after D2 |
| 9 Bundle + LEC | 1 d | 1 Conformal | after 7 |

**Engineering total: ~9 working days to a verified, DRC/ANT/BND-measured GDS under remedy R-a; ~3 working weeks under R-c.**

**Waiting on others:** route confirmation (days, not started) · **shuttle seat (~3 months, not booked)** · corner ruling (days, not asked) · Calibre switch set (days, not asked) · die-area quote (days, not asked) · BE packages (unknown, requested in a doc but not sent).

### The honest answer on a date

**A submission date cannot be given today.** The engineering is roughly two weeks of work; the seat is roughly three months of lead and has not been booked; and the one rejection-grade defect is waiting on a broker email that has not been sent. **Send that email today, book the seat, and the schedule becomes real. Until then any date would be invented.**

---

## 9. QUESTIONS FOR THE BROKER — send today

1. **Confirm the route.** Is this Europractice/imec mini@sic 65 nm? If not, who, and does the flow require a complete GDS with imported cell layouts and a seal ring?
2. **Confirm the black-box model.** We will ship a GDS in which TSMC standard cells, IO drivers and bond pads are empty cell references, with only our routing, vias and the 8 compiled memory macros as real geometry. Confirm you import the TSMC layouts.
3. **Corners.** Our pad ring places `PCORNER_G` (135 × 135 µm) at all four corners of a 1600 × 2000 µm die. The deck's `EMPTY_AREA` is `INT CHIP_NOSR < 74 ABUT == 90`. **What exactly must be empty, and what is your accepted remedy?** Delete the corner cells (and what about pad-ring bus continuity and the ESD guidance on p.33)? Move the ring inward? A chamfer you apply at import? *Largest schedule leverage of any question here.*
4. **Deck switches.** Send your exact `#DEFINE` set for `CLN65S_9M_6X1Z1U.26_2a`. Specifically: is `LP` on? Is `WLCSP_SEALRING` off for a wire-bond design? `FULL_CHIP`, `MIXED_SCHEME`, `CHECK_LOW_DENSITY`, `ChipWindowUsed`?
5. **Tap cells / LUP.6.** We use `tcbn65lp` 9-track with `add_endcaps DCAP4` and no explicit well-tap insertion. Will LUP.6 fire after your import, and what tap spacing do you require?
6. **Dummy fill.** Do you run it, or do we? Our M8 density is ~7.6% at 20×20 against a 20% foundry floor at 75×75.
7. **Antenna and BND.** Do you run ANT and BND as part of acceptance, or are they ours to clean before submission?
8. **LVS.** We hold Front-End packages only — no CDL for standard cells, IO or bond pads. Confirm black-box LVS is acceptable and send the application note. Our DRC waivers for macro-`OBS`-vs-PG spacing would normally need LVS evidence we cannot produce; how do you want that handled?
9. **Preliminary GDS.** We would like to submit one early. What is the deadline and what must it contain?
10. **Area and seat.** 1600 × 2000 µm = 3.2 mm², aspect 1:1.25. Quote the extra-area charge and confirm the next available 65 nm shuttle date and the cut-off for a revised stream.
11. **RC deck.** We have `/tsmc65pdk/65/CMOS/LP/pdk/Assura/online/1p9m_6X1Z1U/qrcTechFile` locally. Confirm this is the right dataset for the 9M 6X1Z1U stack, or send yours.

---

## 10. WHERE THE CURRENT APPROACH IS WRONG

1. **"Procurement is the blocker" is wrong under Branch A.** `docs/TSMC_BACKEND_PACKAGE_REQUEST.md` calls the BE packages *"the single blocker on delivering a manufacturable GDS"*. Under mini@sic they are not — the broker imports the cell layouts. They block *local LVS and local density signoff*, which matter, but they are not the path to submission. Meanwhile the actual rejection-grade defect — the corners — was recorded nowhere.
2. **Chasing DRC 64→63→50→31→1 through P&R runs is the wrong economics.** The 40-record class (c) is very likely a LEF-abstraction artefact that a single Calibre run settles for free. Run Calibre before spending another P&R cycle on it.
3. **The 64→265 delta should be abandoned as an investigation.** Confounded five ways across a run that never executed `power_plan.tcl`. The one-knob probe now costs 4 minutes; re-derive from today's measured 280, do not archaeologise.
4. **Optimising timing before wiring the extraction deck is backwards.** The deck exists on this machine and the cap tables are the wrong stack. Every FEP number quoted in the last week has an unquantified error bar, and the "fill cost us 5→103" story is partly a re-extraction artefact nobody can separate.
5. **The gates are the deliverable, not the overhead.** Every day lost so far traces to a green that could not have been red. Phase 0 is not preparation for the work; on this project it *is* the work.
