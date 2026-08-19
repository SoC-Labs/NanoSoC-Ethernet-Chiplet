# TideLink D2D ASIC Constraints Audit — eth-chiplet tapeout

**Date:** 2026-08-17
**Question:** Are the TideLink D2D ASIC constraints correct and complete for the eth-chiplet tapeout?
**Scope:** READ-ONLY audit. No SDC/RTL/report modified, no flow run, no commit.
**Flow:** Genus/Innovus under `ASIC/genus-innovus/`.
**Answer in one line:** The constraints are **authored correctly and completely**, but the **tapeout as submitted is not fully constraint-correct** (TX word-clock domain timed at 0 ns source latency), and the **current input SDCs have never been synthesized**, so closure on the corrected constraints is **unverifiable from any report on disk.**

> **Independently verified (parent session, 2026-08-17):** the decisive facts hold against ground truth. Input `tidelink_constraints.sdc` mtime = **13:09 today**; every `*_syn.sdc` on disk is **Aug-14 or earlier** → the current constraints are un-synthesized. `pad_clk_tx` is the file's *own declared-correct* source for `D2D_TX_CLK_0` (line 303, "do not fix it") and was broken **only** for the TX *word* clocks (now re-sourced to `user_hsclk`). The TX-word GAP (0 ns source latency, un-run fix) and the required re-synth+P&R gate (`master_clk_edge_not_reaching`/`TA-1018` → 0) are confirmed. The RX-word "hold is fiction" worry is refuted.

---

## What "the D2D clocks" actually are (corrected count)

The task brief said "~18 named D2D clocks." The current input `tidelink_constraints.sdc` (39 KB, edited today 13:09) actually defines **26**:

| Clock | Count | Where |
|---|---|---|
| `D2D_RX_CLK_0` (create_clock on TL_CLK_RX) | 1 | tidelink_constraints.sdc:39 |
| `D2D_TX_CLK_0` (÷1 gen on pad_clk_tx → TL_CLK_TX) | 1 | tidelink_constraints.sdc:43 |
| `D2D_RX_WORD_CLK_0..7` (÷16 on gpiorx_n/io_link_clk) | 8 | :124 (foreach) |
| `D2D_RX_WORDN_CLK_0..7` (÷16 -invert on gpiorx_n/count_reg[3]/Q) | 8 | :196 (foreach) |
| `D2D_TX_WORD_CLK_0..7` (÷16 on gpiotx_n/io_link_clk) | 8 | :344 (foreach) |

The `D2D_TX_WORD_CLK_*` block (a third foreach loop, ~2k TX flops) was **added/corrected today** — the brief only listed the two RX loops.

---

## Per-item verdict table

| # | Item | Verdict | One-line basis |
|---|---|---|---|
| 1 | Do all D2D clocks reach the synthesized SDC P&R consumes? | **CORRECT** | 26/26 present as created clocks in the last-synthesized `..._syn.sdc`; gate A/C enforce it. |
| 2 | CDC handling D2D ↔ core clk | **CORRECT** (+ KNOWN-RISK) | All 26 in `set_clock_groups -asynchronous`; but the TX group cuts a *synchronous* boundary and the RX FIFO crossing is left timed. |
| 3 | Is HOLD actually closed on the D2D word domains? | **GAP** (TX) / **KNOWN-RISK** (RX) | RX word hold is genuinely analyzed; **TX word hold is fiction** — 0 ns source latency, 16 master-edge failures; fix un-run. |
| 4 | Placeholder link budget | **KNOWN-RISK** (design-accepted) | Uncertainty is the CDCM61001 *system-oscillator* figure (0.35/0.05 ns), not a characterized D2D link budget. |

---

## Item 1 — Do all D2D clocks reach the synthesized SDC? — **CORRECT**

**How P&R gets its constraints.** `scripts/nanosoc_eth_chiplet_pads.mmmc:234-235` hands Innovus exactly **one** SDC: `../outputs/nanosoc_eth_chiplet_pads_syn.sdc`, written by Genus `write_sdc`. A clock defined in the input SDC but dropped by `write_sdc` = untimed at P&R. So the test is what is actually *in* the written SDC.

**The last-synthesized SDC carries all 26 D2D clocks.** In the shipped build `ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_syn.sdc` (written Aug 14 14:01), lines **21–46** hold exactly:

- `D2D_RX_CLK_0` ×1 (line 21), `D2D_TX_CLK_0` ×1 (line 22)
- `D2D_RX_WORD_CLK_0..7` ×8 (lines 23–30)
- `D2D_RX_WORDN_CLK_0..7` ×8 (lines 31–38)
- `D2D_TX_WORD_CLK_0..7` ×8 (lines 39–46)

**= 26/26, zero missing.** Same 26 verified in `runs/20260813T231658Z_fullrun-scratch-padfix/outputs/...syn.sdc:21-46`.

**Gates enforce it at synthesis.** `scripts/1b_synthesis_eval.tcl`:
- **GATE A** (lines 685–733): re-reads the written SDC and fails the flow if any of the 24 word clocks (`D2D_RX_WORD/RX_WORDN/TX_WORD_0..7`) is absent — the check exists precisely because Genus merges 7 of the 8 RX dividers at map time.
- **GATE C** (lines 766–812): asserts `D2D_RX_CLK_0` period == `CLK_PERIOD` and every word clock is still `-divide_by 16`.

**Caveat (does not change the verdict, but bounds it):** the *only* synthesized SDC on disk is the **Aug 14** one. The current input `tidelink_constraints.sdc` was edited **today at 13:09** (TX word-clock `-source` changed from `pad_clk_tx` to `$WL/user_hsclk`). No re-synthesis has happened since — see Item 3. So "26/26 reach P&R" is proven for the *Aug-14 constraint state*, and the Aug-14 TX word clocks carry the **old, broken** source (line 39: `-source .../u_wlink/pad_clk_tx`).

---

## Item 2 — CDC between D2D domains and core `clk` — **CORRECT** (with a KNOWN-RISK)

**`tidelink_constraints.sdc` has zero CDC commands.** `grep -cE 'set_clock_groups|set_false_path'` returns 1, and that one hit is a **comment** (line 368). All grouping lives in the main `constraints.sdc`, as the brief stated.

**The async grouping covers all 26 D2D clocks.** `constraints.sdc:381-398`:

```tcl
set _rx_grp {D2D_RX_CLK_0}          ;# + 8 D2D_RX_WORD_CLK_n + 8 D2D_RX_WORDN_CLK_n  => 17
set _tx_grp {D2D_TX_CLK_0}          ;# + 8 D2D_TX_WORD_CLK_n                          =>  9
...
if {[llength $_rx_grp] != 17 || [llength $_tx_grp] != 9} { error ... }   ;# self-check
set_clock_groups -asynchronous -name eth_chiplet_cdc \
    -group [get_clocks [list $EXTCLK QSPI_SCLK QSPI_SCLK_o]] \
    -group [get_clocks $_tx_grp] \
    -group [get_clocks $_rx_grp] \
    -group [get_clocks {rmii_ref_clk mii_rx_clk mii_tx_clk}] \
    -group [get_clocks [list $SWDCLK]]
```

17 (RX) + 9 (TX) = **26**, and the `llength` guard hard-errors if the group is miscounted. So every D2D clock is cut asynchronous from the system clock / QSPI / RMII / SWD. **No D2D clock is omitted.** This is correct and is the intended CDC handling for a mesochronous off-die link.

**KNOWN-RISK sub-items flagged in-file (design decisions, not omissions):**
- **[C2] TX group over-cuts a synchronous boundary** (`constraints.sdc:282-354`). `D2D_TX_CLK_0` and `D2D_TX_WORD_CLK_0..7` are grouped `-asynchronous` against `clk`, but they are *generated from* `clk` 1:1 on the same net — the tool resolves their master to `clk` (`build/full-20260814/logs/pnr_qor_after_opt_design_post_cts.rep:21-34`). The group therefore false-paths ~2k TX flops' worth of a boundary that is physically synchronous (RTL-synchronized, but not "asynchronous"). Safe/conservative for signoff timing, but hides real paths. Two open options recorded (A: merge TX group into `clk`; B: bond `user_ref_clk` to its own pad). **Owner decision pending — no SDC change made.**
- **Intra-RX-group crossings deliberately left TIMED** (`constraints.sdc:370-377`): `set_clock_groups` cuts *between* groups only, so word↔capture (`D2D_RX_CLK_0 → D2D_RX_WORD_CLK_n`) across the **async deskew FIFO**, and lane↔lane, remain timed. The file itself notes the FIFO crossing "probably DOES want a narrow `set_false_path` on the FIFO data path" and leaves it for the first run to characterize. This is a conservative bring-up choice, not a missing constraint.

---

## Item 3 — Is HOLD actually closed on the D2D word domains? — **GAP (TX) / KNOWN-RISK (RX)**

This was the priority item. The prior concern — *"the post-CTS uncertainty/latency writeback covered only ~5 of 33 clocks and NONE of the 16 D2D word clocks, so hold on those domains is fiction while the gate reads green"* — is **half confirmed and half refuted** against the current shipped reports. The blanket claim is too strong; the reality splits cleanly RX vs TX.

### The writeback census is literally as described
`build/full-20260814/reports/cts_latency_writeback.rep` — the `ccopt_design` I/O source-latency writeback, gated on `-max > 0 && -max == -min` in `default_analysis_view_hold` — writes back **only 5 clock roots**:

```
default_analysis_view_hold   D2D_RX_CLK_0        4  4
default_analysis_view_hold   D2D_TX_WORD_CLK_0   4  4
default_analysis_view_hold   clk                 4  4
default_analysis_view_hold   rmii_ref_clk        4  4
default_analysis_view_hold   swdclk              4  4
```

`cts_uncertainty.rep` lists **33** clocks total (clk, swdclk, QSPI ×2, the 26 D2D, rmii+mii ×3). So writeback = **5 of 33**, and **none of the 16 RX word clocks** appear. The "5 of 33 / none of the 16" finding is **literally true.**

### But "no writeback" is not the same as "hold unanalyzed" — and RX proves it
`check_timing` at every stage through final route (`check_timing_05_route_opt.rep`, TIMING CHECK SUMMARY) reports:

```
master_clk_edge_not_reaching   Master clock edge does not reach the generated clock target   16
```

and the DETAIL names them: **all 16 are `D2D_TX_WORD_CLK_0..7`** across the 2 setup views (8 × 2 = 16). A grep for `D2D_RX` in that warning returns **0** — **not one RX word clock** fails master-edge reaching. Corroborated by `cts_msg_census.rep`: `TA-1018 = 464` "generated clocks timed with 0 ns source latency" (the raw tool count of the same TX-only defect the SDC comment tallies as 8×3 views).

Meaning:
- **RX word clocks (16):** their `TL_CLK_RX` master **does** reach them; they are derived off `D2D_RX_CLK_0`'s real clock tree (which has a written-back 1.09 ns insertion), and they **appear in the routed hold report** — `nanosoc_eth_chiplet_pads_routed_all_hold.tarpt.gz` shows `D2D_RX_WORD_CLK_0` and `D2D_RX_WORDN_CLK_1` (and `D2D_RX_CLK_0`) among the sampled worst-hold paths. So RX-word hold **is genuinely analyzed with propagated latency**, not fiction. The absence of a *separate* source-latency writeback is expected-by-construction for a clock divided off an already-built tree. → **KNOWN-RISK**, not a gap: analyzed, but with placeholder uncertainty (Item 4) and with the intra-domain FIFO/lane crossings deliberately left timed (Item 2), so there is no per-domain signoff proof — but it is not "fiction."
- **TX word clocks (8):** master edge does **not** reach (16 warnings, final route), so ~2k TX-word flops are timed against a clock the tool believes arrives **instantly (0 ns source latency)**. Their hold numbers are **not physically meaningful.** → **GAP**, and it is a real one that survived into the shipped database.

### Aggregate hold looks green — and that is exactly the trap
`hold_05_route_opt.rep` (final routed): **hold WNS -0.001 ns, TNS -0.002 ns, FEP 7.** Essentially met in aggregate, 7 endpoints marginally failing. But that single number cannot be decomposed to prove real per-domain margin on the TX word flops that were timed at 0 ns source latency — a domain timed against an instant clock will *report* balanced hold whether or not it is.

### The fix exists but has never been synthesized
Today's `tidelink_constraints.sdc:327-345` re-anchors the TX word `-source` to `$WL/user_hsclk` (the common ancestor) precisely to make the master edge reachable and kill the 0 ns source latency, with an explicit gate note (line 326): *"THE GATE IS THE TA-1018 / master_clk_edge_not_reaching COUNT IN THE NEXT RUN, AND IT MUST BE 0."* **That next run has not happened.** Searched every `..._syn.sdc` under `ASIC/` (42 of them): **zero** carry the `user_hsclk` source; **all** still carry `pad_clk_tx`. syn.log is Aug 14 14:03; the SDC fix is Aug 17 13:09. The tapeout submission zip `build/full-20260814/submission/nanosoc_eth_chiplet_pads_cd8b47d-dirty_20260817T165655Z.zip` (Aug 17 17:57) packages the **pre-fix** database. **So the shipped tapeout still has 8 TX word domains timed at 0 ns source latency; the correction is un-run and unverified.**

---

## Item 4 — Placeholder link budget — **KNOWN-RISK** (design-accepted)

- **Values:** `set CLK_ERROR 0.35` (`constraints.sdc:21`), `set CLK_HOLD_ERROR 0.05` (`constraints.sdc:58`).
- **Provenance:** the CDCM61001 **system oscillator**, not the D2D link. The in-file analysis (`constraints.sdc:22-58`) is candid that the 0.35 ns is ~0.2 ns duty-cycle distortion + ~0.01 ns jitter + margin — a legitimate *system-clock* signoff number, explicitly **not** a D2D-link characterization.
- **Applied to every D2D clock** as the placeholder: `tidelink_constraints.sdc:62-65` (RX/TX CLK), `:130-131` (RX_WORD), `:198-199` (RX_WORDN), `:346-347` (TX_WORD).
- **Confirmed in the built database:** `cts_uncertainty.rep` shows all 26 D2D clocks (and all 33 total) carrying **0.35 setup / 0.05 hold** — the number CCOpt optimized against and STA signed off with.
- **No characterized D2D-specific budget exists.** The file flags this repeatedly and honestly (`tidelink_constraints.sdc:33-37, 55-61, 127-129, 580-583`): the real terms — the two dies' independent clock-tree jitter, pad/package flight variation, and the deskew FIFO tolerance — are not measured. This is a *deliberately-not-closed-for-this-tapeout* item, i.e. a documented design-accepted risk, not a bug. It is strictly more conservative than the zero margin that preceded it.

---

## Bottom line — are these tapeout-correct?

**As authored, yes; as taped out, not yet — and unverified.** The D2D constraint set is genuinely thorough: all 26 D2D clocks are declared, all 26 provably reach the single SDC that P&R consumes (gated at synthesis by GATE A/C), all 26 are placed in the correct `-asynchronous` clock group cutting them from the core/QSPI/RMII/SWD domains, and all 26 carry clock uncertainty. Hold on the 16 **RX** word domains is genuinely analyzed (their master reaches them, they inherit `D2D_RX_CLK_0`'s real tree, they appear in the routed hold report) — so the "hold is fiction on the D2D word domains" concern is **refuted for RX**. However three things stop this from being tapeout-correct **today**: (1) the 8 **TX** word domains (~2k flops) are timed at **0 ns source latency** in the shipped Aug-14 database — 16 `master_clk_edge_not_reaching` and 464 `TA-1018` in the final routed reports — so hold/setup on them is not physically meaningful (**GAP, and the concern is confirmed for TX**); (2) the TX-source fix that closes exactly this, plus the [C2]/[C5] group cleanup, were edited into the input SDCs **today at 13:09/18:47 and have never been synthesized** — every `_syn.sdc` on disk (and the Aug-17 17:57 submission zip) still carries the broken `pad_clk_tx` source, so closure on the *current* constraints is **unverifiable from any report that exists**; and (3) the link-budget uncertainty is a **system-oscillator placeholder**, not a characterized D2D budget (design-accepted KNOWN-RISK). **Required before this is signed off: re-run synthesis + P&R on the current SDCs and confirm `master_clk_edge_not_reaching` and `TA-1018` collapse to 0, then re-check hold on the TX word domains with real source latency.**
