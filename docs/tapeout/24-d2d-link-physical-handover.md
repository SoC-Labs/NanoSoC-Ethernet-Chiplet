# Handover → ASIC synthesis/P&R agent: the D2D link's physical-implementation gaps

**From:** TideLink integration assessment, 2026-08-07.
**Scope:** **NON-RTL only** — constraints, corners, extraction, flow coverage, DFT. RTL changes are
handed to the TideLink agent separately (`tidelink/docs/HANDOVER_ASIC_LINE_RTL_GAPS_2026-08-07.md`
and `HANDOVER_A2L_CDC_PORT_WEDGE_FIX_2026-08-07.md`). Where an item has both a constraint-side and
an RTL-side fix, it is flagged **[dual]** and both docs describe it.

**One line:** roughly a quarter of the sequential logic in this chip — the entire TideLink D2D
receive and transmit word-processing side — was placed and routed with **no clock, no clock tree, no
skew target, no hold check and no timing paths in or out**, and there is a known functional CDC bug
sitting inside that unanalysed region. Item 1 below is the single highest-value change in this doc.

> **Status of the numbers here:** verified by me against `runs/20260807T171905Z_eval-pnr-resume`
> unless stated. ⚠ The `runs/latest` symlink moved twice during the analysis (concurrent session) —
> **re-measure before quoting any figure**, and see `docs/tapeout/19-timing-audit.md` and
> `20-synthesis-audit.md` for the standing audits this doc extends rather than replaces.

---

## 1. PRIORITY 1 — the D2D RX and TX word clocks are undeclared

**Verified.** `ASIC/genus-innovus/inputs/tidelink_constraints.sdc` defines exactly two clocks:
`D2D_RX_CLK_0` on the `TL_CLK_RX` pad (`:2`) and `D2D_TX_CLK_0` on `TL_CLK_TX` (`:6`). The
**recovered ÷16 word clocks** that those pads feed are declared nowhere.

- RX word clock: `assign io_link_clk_mux_io_i_a = ~adj_count[3]` in
  `tidelink/src/rtl/local_overrides/WavD2DGpioRx.v` — a counter flop output, fanned out by `Wlink.v`
  to `llrx_clock`, `axi2wl_io_rx_clk`, `gb2wl_io_rx_clk`, `tl2wl_io_rx_clk`, `sp2wl_io_rx_clk`.
- `check_timing_intent` reports **15,197 sequential clock pins with no clock waveform**
  (`reports/eval/syn_timing_intent.rep`) — ~13.6k RX-side, ~1.6k TX-side, the rest ICG clock inputs.
- Independent corroboration: the netlist holds ~58.3k flops while CTS reports **44,018 total sinks**
  across all clock trees (`logs/run.log`). The gap is this domain.

**Why it is not merely a reporting gap.** `ccopt` identifies clock nets from the SDC, so **CTS builds
no tree**. The logic optimiser buffered it instead — in the routed netlist the RX word clock exists as
**39 distinct `FE_OFN*`/`FE_OFC*` replicas**, driven by a mix of `BUFFD2` (a general-purpose *data*
buffer), `CKND2`, `CKND4` and `CKBD3`, with no skew target, no `min_pulse_width` check and no
`max_skew` check. `timing_summary_05_route_opt.rep` records `min_pulse_width (clocktree) N/A / 0` —
which reads as clean and means *not analysed*. For scale: the domains that do have a tree were built
to a 0.097 ns skew target.

**This is an omission, not a deliberate exclusion** — there is no `set_false_path`, no
`set_clock_groups`, nothing touching the domain. The same pattern *is* applied correctly elsewhere in
this flow: `inputs/ethernet_constraints.sdc:41-42` declares `mii_rx_clk`/`mii_tx_clk` as ÷2 generated
clocks. And on the FPGA side, omitting the TX word clock broke the link outright — see
`tidelink/fpga/targets/kr260-pair-flip-ptp/kr260_tidelink_timing.xdc:456-467`
("`io_rreset` never sync-deasserts → `link_empty=1` ALWAYS → FCSM never drains → **NO V2 DATA TX**").
The ASIC has the same omission with no equivalent safety net.

### The drafted fix — NOT validated, please review before trusting

```tcl
set GPIO u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink/phy/gpio
foreach n {0 1 2 3 4 5 6 7} {
    create_generated_clock -name "D2D_RX_WORD_CLK_$n" \
        -source [get_ports TL_CLK_RX] -divide_by 16 \
        [get_pins $GPIO/gpiorx_$n/io_link_clk]
}
```

Each lane has its own divider; only lane 0's leaves the module, and `u_deskew` is entirely on lane 0
(`always @(posedge gpiorx_0_io_link_clk)` in `WavD2DGpio_v2.v`), so lane N → lane 0 is a real crossing
needing both ends declared. Shared `-source`/`-divide_by` makes them phase-aligned, giving cross-lane
paths the full period — correct, since absorbing that skew is what `u_deskew` and the calibrator are for.

**Caveats you must resolve before applying:**
1. **Verify the source pins.** The drafted fix is per-lane; netlist evidence points at
   `gpiorx_7_count_reg[3]/Q` (RX) and `gpiotx_0_count_reg[3]/Q` (TX). Reconcile these before trusting
   either form. **Assert each `get_pins` is non-empty** — a constraint matching nothing looks applied.
2. **A TX word clock is needed too.** The draft above covers RX only.
3. **Confirm `TL_CLK_RX` really is 100 MHz** — the 160 ns word period inherits `$EXTCLK_PERIOD`.
4. **Expect the next run to look WORSE.** ~15k newly-timed flops in a never-constrained domain will
   surface violations. That is the fix working, not a regression.

**Falsifiable success criterion:** `check_timing_intent`'s "sequential clock pins without clock
waveform" drops 15,197 → ~0, and CTS sink count moves 44,018 → ~58.3k. If it lands near 130, a domain
was missed.

---

## 2. PRIORITY 2 — the source-synchronous D2D I/O constraints are wrong, and TideLink's own set was never carried over

**a) The RX eye window has zero width.** `tidelink_constraints.sdc:4` applies
`set_input_delay 1.0` with **neither `-min` nor `-max`**, so SDC applies it to both — asserting data
can never arrive early. The file's own note at `:214-222` admits this. Same defect on the TX side
(`set_output_delay 0.8`, no `-min`/`-max`).

**b) TideLink ships a correct constraint set that this flow does not use.**
`tidelink/syn/asic/fusion-compiler/inputs/constraints.sdc:143-206` carries symmetric `-min`/`-max`
delays, `set_max_delay -datapath_only`, and a `set_data_check` for lane skew — the partition SDC calls
these "the CRITICAL #2 fix". **Zero of them appear in the elaborated chiplet SDC.** Porting that block
is the obvious next step after item 1.

**c) The TX eye is not analysed at all.** `D2D_TX_CLK_0` has an **empty path group** ("No paths" in
`reports/eval/syn_qor.rep`), because `clk` and `D2D_TX_CLK_0` sit in different asynchronous clock
groups (`constraints.sdc:156-161`) so the launch↔capture relationship is cut.

**d) The blanket async cut is self-declared as provisional.** `constraints.sdc:152-155` labels the
5-group `set_clock_groups -asynchronous eth_chiplet_cdc` as the *bring-up* cut, to be "narrowed at
signoff". It has not been narrowed. It currently subsumes and silently deadens the ethernet CDC false
paths and the `last_push_flags` multicycle (`ethernet_constraints.sdc:305-334`).

---

## 3. PRIORITY 3 — timing does not close, and the variation budget is zero

**Verified from `reports/qor_05_route_opt.rep`:**

| Snapshot | WNS | TNS | FEPS |
|---|---|---|---|
| `opt_design_postcts_hold` | **+0.012** | 0 | **0** |
| `opt_design_postroute_hold` | **−0.487** | −44 | **319** |

Setup was clean post-CTS and was **destroyed by routing plus post-route hold repair** — 279 of the 319
are reg2reg, 40 are ClockGate. Worst path is CM0+ `core_op_q_reg[10]` → DMA250 `hwdata_reg[4]`.
DRV also fails: `max_transition −1.328 / 107 FEP`, `max_capacitance −0.019 / 32 FEP`.

Hold, in fairness, is essentially closed (**−0.007 ns**) — the OCV-ordering fix in
`scripts/cts_setup.tcl:72` worked, down from −1.167 ns / 96,545 violating paths. The commit's headline
claim is supported.

**`set_timing_derate` appears nowhere.** OCV is enabled with **zero variation margin** at 65 nm — the
entire on-chip-variation budget is the 0.35 ns / 0.05 ns uncertainty. Adding derate will reopen setup;
that is the correct order of operations, not a reason to defer it.

---

## 4. Corners and extraction — the accuracy floor (relevant to your open `2b_pnr_place_eval.tcl` notes)

Your own mmmc commentary already states the three facts that bound every number above, and they are
worth restating as a block because items 1–3 are only as trustworthy as this:

- **Signoff is SINGLE-CORNER**: setup at SS/1.08 V/125 °C, hold at FF/1.32 V/−40 °C, nothing else.
  No SS-hold corner, no `tcbn65lpwcl` (`nanosoc_eth_chiplet_pads.mmmc:198`;
  `docs/tapeout/19-timing-audit.md:215-247`).
- **Cap tables but no QRC file** — signoff extraction is silently downgraded. No QRC exists on this
  site; this is procurement, not engineering.
- **The cap tables model M9 at 0.9 µm; real M9 is 3.4 µm** — a 3.8× error, which is why
  `preplace.tcl` confines signal routing to M1–M7.

~~**And there is no signoff STA at all**: `ci/signoff.yaml:238` — "No Tempus or PrimeTime installed.
Timing evidence is limited to Genus/Innovus in-tool reports, which is not signoff STA."~~

> **⚠ CORRECTED 2026-08-18 — "no Tempus or PrimeTime installed" is FALSE.** Both are
> installed and completely idle, measured today: **Tempus** `SSV_21.11.000`
> (`Tempus_Timing_Signoff_XL/_MP/_TSO`, 41 issued / 0 in use) and **PrimeTime** `2022.12`
> (200 + 4 issued / 0 in use). Tempus 21.11 is **version-matched to the
> `INNOVUS_21.11.000` that built this database**, so it is the low-friction option.
>
> **The true statement is narrower:** signoff STA has *not been run*, and no extraction is
> wired — that is a wiring gap, not a licence gap. Note items 2–3 of this section were
> corrected on 2026-08-17 but this line was left behind.
>
> **This is a quotation, and the source string is still wrong.** `ci/signoff.yaml` still
> carries the "No Tempus or PrimeTime installed" `reason:`, so any new document that cites
> the manifest will re-import the error. Flagged to whoever owns that file — the Voltus
> entry in the same file has already been rewritten correctly and is the model to follow.
> See `40-signoff-sta-plan.md`.

**Implication for item 1:** once the word clocks are declared, the newly-surfaced violations will be
computed with downgraded extraction on a single corner with no derate. Treat the first post-fix number
as a *ranking*, not a *margin*.

---

## 5. `check_timing_intent` — the rest of what it says

It runs, and it is not clean (`reports/eval/syn_timing_intent.rep`, 16,378 lines):

| Finding | Count | Note |
|---|---|---|
| Sequential clock pins with no clock waveform | **15,197** | item 1 |
| Pins with multiple clock waveforms | 6 | |
| Nets with multiple drivers | 18 | worth triaging separately |
| Inert exceptions | 8 | incl. `D2D_TX_CLK_0`, `QSPI_SCLK_o` |
| Inputs with no I/O delay | 4 | `QSPI_nCS`, `SWDIO`, … |
| Outputs with no I/O delay | 13 | `HOSTIO4_P1[6:0]`, `I2C_*`, `RMII_MD*`, `SE` |
| Exceptions with invalid start/endpoints | 1 | `constraints.sdc_line_107` — the pad MCP `set_multicycle_path 2 -from uPAD*/*` is **malformed and inert** |

Also absent design-wide: `set_data_check` (0), `set_max_delay`/`set_min_delay` (0),
`set_case_analysis` (0 — `syn_case_analysis.rep` is 0 bytes), `set_disable_timing` (0).

Two generated clocks have **broken source latency** because they are defined on hierarchical module
pins: `QSPI_SCLK` (`TA-1018` "will use 0 ns source latency", `IMPCCOPT-2248`) and `mii_rx_clk` —
which CCOpt then re-sources at `mtx_clk_reg/Q`, i.e. the **TX** register. See
`19-timing-audit.md:162-204`.

---

## 6. Flow-coverage gaps — checks that exist but do not run on the GDS-producing path

1. **`check_timing` / `report_analysis_coverage` are not in the production P&R targets.** The
   instrumentation exists (`scripts/pnr_utils.tcl:736-738`, `scripts/3b_pnr_cts_eval.tcl:794-795`) but
   `runs/latest/MANIFEST.txt` shows the run executed `pnr_place pnr_cts pnr_route`, not the eval
   variants — so the run that produced the current GDS emitted **neither report**. Wire them in.
2. **No gate-level simulation anywhere.** The `_gate.sdf` (203 MB) is written and never consumed.
   GLS is exactly what would expose reset-ordering X's and the runt-pulse behaviour in §7.
   *Nothing blocks it.* Measured 2026-08-17: TSMC ships standard-cell and IO Verilog in the same
   `Front_End` packages this flow already takes its Liberty from, all six RAM macros have `.v`
   models, and VCS, Xcelium and Verilator are all installed here. See
   [13 §3](13-lec.md) for where they sit and the one caveat: within each package the `verilog/`
   subdirectory carries an **older release revision** than the `NLDM/` one the Liberty comes
   from, so compare those two directory names on your installation before trusting a GLS run.
3. **Post-P&R LEC is stale, not absent** *(corrected 2026-08-17; this item read "No post-P&R LEC")*.
   It ran clean on 2026-08-08 — 61,375/61,375 equivalent — but against a `_pnr.v` that has since
   been superseded, and the RTL → synthesised leg has still never completed.
   `docs/tapeout/11-known-issues.md` issue (i); full account in `docs/tapeout/13-lec.md` §7.
   The precedent is not hypothetical: a July GDS shipped with TideLink's **entire TX datapath
   removed by Genus `GLO-34`** and passed every physical check — and `GLO-34` is caught by the
   RTL → synthesised leg, the one still missing.
4. **GDS completeness** — the streamed artefact has **424 cell masters with no transistors**
   (`ci/signoff.yaml`, `gds-completeness`), blocked on TSMC Back-End packages. Any DRC over it must be
   *withdrawn*, not caveated.

---

## 7. **[dual]** The clock-gating hazard on the a2l mailbox — synthesis-side mitigation

This is the mechanism that makes the known CDC bug *more* likely on ASIC than on FPGA, and you own
half of the fix.

Genus converted the mailbox's RTL enable `if (we && ~rptr)` into an **integrated clock gate**:

```
eval_cg_RC_CG_MOD_355_16386 eval_cg_RC_CG_HIER_INST355 (
    .enable(..._addrsync_n_23), .ck_in(FE_OFN1565_phy_link_tx_tx_link_clk), .ck_out(eval_cg_rc_gclk_309027));
DFCNQD1 \..._addrsync_mem_0_reg[0] (.CP(eval_cg_rc_gclk_309027), ...)   # and [1]..[4]
NR2D0 g548089 (.A1(..._we), .A2(..._rptr), .ZN(..._n_23));
```

`rptr` is a register from the **other** clock domain, used raw. A `CKLNQD1` is glitch-free only if its
enable meets setup/hold to the low-phase latch; an async enable cannot. When it violates, the ICG emits
a **runt pulse**, and a runt pulse on a domain with **no clock tree** (item 1) does not clock the 5 bits
atomically — a subset capture, the rest hold. **That is a torn multi-bit word**, which is precisely the
documented failure at `tidelink/src/rtl/local_overrides/WlinkGenericFCReplayV2_13.v:207-224`.

On FPGA this cannot happen: Vivado maps the same RTL to an `FDRE` **CE pin** — a *data* input, where a
marginal enable resolves per-flop and cannot produce a partial clock edge. This is an ASIC-only hazard.

**Your options, in preference order:**
1. **Preferred: let the RTL fix land** — driving the mailbox slot-select from the *synchronised* `rptr`
   removes the async signal from the ICG enable at source. Requested in the TideLink RTL handover.
2. **Interim, synthesis-side:** exclude the `WavMultibitSync` register banks from clock gating so
   the enable reverts to a mux on the D pin. Cheap, local, and reversible.

   **Corrected 2026-08-17 — this step previously named the wrong command, and following it as
   written would have cost a day.** It is neither `set_clock_gating_style` (a Design Compiler
   command; this flow is Genus) nor `set_dont_touch` (which preserves an ICG that is already there
   rather than preventing its insertion). The Genus attribute is **`lp_clock_gating_exclude`**, and
   the **module** form is the one to use — it applies to all instances of the module and sidesteps
   the `dedicate_module` trap the `inst`/`hinst` forms carry. Set it after `elaborate` and before
   `syn_generic`, alongside the existing `lp_clock_gating_min_flops` block.

   Measured cost: **174 of 50,754 gated flops, 0.34%**, one re-synthesis, fully reversible. Do
   **not** reach for `lp_clock_gating_min_flops` instead — raising it would ungate every narrow
   bank in the design, not just these.

   **Prove the attribute took.** This flow sets no `auto_ungroup`, but the netlist shows heavy
   ungrouping in exactly this hierarchy, so a module-scoped attribute may bind to a module that no
   longer exists by the time gating runs. Re-run `scripts/cdc/icg_enable_domain_audit.py --gate`
   after re-synthesis and confirm the count goes to zero; do not assume it applied.

   **Scope note — the hazard is larger than this document says.** §Above describes one instance on
   a2l. A gate-level audit of the current tapeout netlist finds **36** `WavMultibitSync` ICGs
   gating **174** flops, across both directions and four domain pairs, with the enable toggling on
   every transaction. Separately there are 32 replay-FIFO memory gates whose foreign-domain enable
   is a quasi-static SWI config register rather than a pointer — a **different and lower-severity
   class**. Do not bundle those into this fix: it is 4× the cost for a window that may never open.
   Resolve the firmware question ("is that register written on a live link?") first.
3. Ensure that whichever path is taken, `wptr_reg` and the `mem_*_reg` bits end up on the **same**
   clock tap. They currently are not — `wptr_reg` is clocked from `FE_OFN1565_phy_link_tx_tx_link_clk`
   with no ICG, while the data bits sit behind the gate on a different replica.

---

## 8. DFT — there is none, and retrofitting is not a stitching job

- `ASIC/genus-innovus/scripts/config.tcl:113` → `set DFT 0`, identically in all four archived run
  configs. The genuine Genus DFT commands exist but are gated; `DFT=1` would `die` because
  `dft_setup.tcl` was never written.
- `insert_scan.tcl` and `insert_mbist.tcl` contain **zero executable commands** — every stage is
  `puts "TODO: ..."`, self-declared at `insert_scan.tcl:232` and `insert_mbist.tcl:167`.
- **No boundary scan, no TAP.** 48 signal pads, no TCK/TMS/TDI/TDO/TRST. Debug is 2-pin SWD.
- **No MBIST** across seven memory macros, including the TideLink RX FIFO `rf_16k`.
- `SE` and `TEST` pads are bonded but drive nothing.
- **The trap:** the ~3.6k `SDF*` cells in the netlist are **not a chain** — Genus used them as
  recirculation muxes with `SI`/`SE` carrying *functional* logic. Retrofitting scan therefore requires
  **re-synthesis**, not stitching. Budget accordingly.
- `DFT_PLAN_2026_05_28.md:11-14` declares "SCAFFOLD ONLY" and lists five items marked "**BLOCKER for
  tape-out**". All five are still open and GDS was produced anyway.

**Chiplet-specific consequence, worth escalating:** with no scan and no boundary scan you cannot screen
a bad die before assembly, and a D2D failure cannot be attributed to a die without swapping parts. If
only one DFT item is affordable, the highest-value pair is **MBIST on the TideLink `rf_16k`** plus a
**far-end D2D loopback mode** — the latter would let two packaged dies self-test the link without a
working AXI path.

---

## 9. Suggested order of work

| # | Action | Cost | Unblocks |
|---|---|---|---|
| 1 | Declare RX **and** TX word clocks (§1) | SDC only + one re-run | Everything below; makes 25% of the chip visible to STA |
| 2 | Port TideLink's source-sync D2D I/O constraints, split `-min`/`-max` (§2) | SDC only | Real RX/TX eye analysis |
| 3 | Add `set_timing_derate` (§3) | SDC only | Meaningful margin; expect setup to reopen |
| 4 | Wire `check_timing` + `report_analysis_coverage` into production P&R (§6.1) | flow edit | Stops this recurring |
| 5 | ICG exclusion on the mailbox banks, if the RTL fix has not landed (§7.2) | synthesis directive | Reduces CDC tear probability |
| 6 | Close setup + DRV (§3) | iteration | — |
| 7 | Narrow the blanket async clock group (§2d) | analysis | Signoff quality |
| 8 | Multi-corner; then GLS and post-P&R LEC (§4, §6) | infrastructure | Signoff credibility |

**Do not** treat items 6–8 as gating item 1. Closing timing on a netlist where a quarter of the flops
are invisible to the tool optimises the wrong thing.

## 10. Provenance
- Timing: `runs/20260807T171905Z_eval-pnr-resume/reports/qor_05_route_opt.rep`,
  `timing_summary_05_route_opt.rep`, `reports/eval/syn_timing_intent.rep`, `reports/eval/syn_qor.rep`.
- Constraints: `ASIC/genus-innovus/inputs/{tidelink,ethernet,qspi,i2c,}constraints.sdc`;
  elaborated `runs/.../outputs/nanosoc_eth_chiplet_pads_syn.sdc`.
- Netlist: `runs/latest/outputs/nanosoc_eth_chiplet_pads_pnr.v` (`WavD2DGpio_USE_CLKBUF1h0` confirms
  the passthrough, i.e. no clock buffer, on the ASIC elaboration).
- Standing audits this extends: `docs/tapeout/19-timing-audit.md`, `20-synthesis-audit.md`,
  `21-physical-audit.md`, `11-known-issues.md`, `17-silent-noops.md`.
- RTL counterparts: `tidelink/docs/HANDOVER_A2L_CDC_PORT_WEDGE_FIX_2026-08-07.md`,
  `tidelink/docs/HANDOVER_ASIC_LINE_RTL_GAPS_2026-08-07.md`.
