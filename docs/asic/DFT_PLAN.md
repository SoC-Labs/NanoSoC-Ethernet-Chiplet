# Design-for-Test plan — `nanosoc_eth_chiplet_pads`

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.

Copyright 2026, SoC Labs (www.soclabs.org)

---

## 0. What this is, and how to read it

This is an **implementable plan for a future respin**, not a survey and not a
change to the live flow. Nothing here has been wired into `design.mk`,
`ci/signoff.yaml`, the hooks or the toolkit. rc4 is at the foundry and the main
checkout is frozen; every measurement below was taken from the **rc5
virtual-tapeout run `rc5vt-20260829`**, which is a complete RTL-to-GDS pass of
the same design.

**Every number in this document has a source.** Where a figure is measured, the
report and line are named. Where it is modelled, it says so and gives the model.
Where I could not determine something, §8 records it as an open question rather
than a plausible sentence. Section 1 corrects four claims that were handed to me
as fact and turned out not to be.

The load-bearing conclusions, up front:

| | |
|---|---|
| **There is no pin problem.** | The chip already re-purposes five bonded functional pins into a JTAG TAP under an `SE` strap. The same mechanism yields an 8-in/8-out scan port on the D2D link pins for **zero new pads**. |
| **There is a real area problem.** | Full scan costs **+133,435 µm²** of standard cell — measured from this design's own library data, 96 % of it from cell pairs both present in the rc5 netlist. That is **13 % more than the headroom** to the density at which a previous run's DRV recovery failed. Full scan does not fit at 1600 × 2000 µm. ~88 % of flops do. |
| **MBIST is cheap and should go first.** | **1,095 collar muxes, 3,548 µm², +0.18 density points**, plus a controller. Roughly one twentieth of what scan costs, for the 19 SRAMs that today have no test path at all. |
| **One defect blocks everything and costs almost nothing to fix.** | All **3,007** integrated clock gates in the rc5 netlist have their test-enable pin tied to `1'b0`. No scan chain can shift through them. Genus fixes this automatically once DFT is enabled properly. |
| **The toolkit already has the scan plumbing.** | `convert_to_scan`, `connect_scan_chains`, `write_scandef`, `reorder_scan` are all present and gated behind `DFT`, which is `0`. What is missing is one project file and one Innovus read. |

---

## 1. Verified current state

I was asked to verify every line of the state I was given. Four of the claims
are wrong or stale, and the corrections change the plan.

### 1.1 Corrections to the received brief

| Claim as received | Verified state | Evidence |
|---|---|---|
| "The SE pad's output is UNCONNECTED." | **False for rc5.** `SE` drives `bsp_se_i_in`, which is the boundary-scan mode select: it releases the TAP's `trst_n` and steers the TAP pin muxes. It has 6 real fanout uses. It was true of the shipping (rc2/rc4) netlist and the `feat/padring-boundary-scan` work changed it. | `..._gate.v:596577` (`uPAD_SE_I`), `:596581–596585` (`CKMUX2D4 g61__7098` selecting `bscan_tdo` onto `HOSTIO4_P1[1]`) |
| "SE case-analysis in the SDC is therefore inert." | **The case analysis has been deleted, deliberately.** `set_case_analysis 0 [get_ports SE]` was removed because constant-propagating it would let Genus correctly delete all 76 boundary cells. `SE` is now timed with an input delay and a `set_false_path`. | `ASIC/genus-innovus/inputs/bscan_constraints.sdc:16–25, 39–41, 57` |
| "26 of 33 boundary-scan `*_core_in` ports are UNCONNECTED." | **33 of 33.** Not 26. Every one of the 33 is bound to a distinct `UNCONNECTEDnnnn` dangling wire at the `u_nanosoc_eth_chiplet_bscan` instantiation. Zero are connected. | `..._gate.v:594274–594346`; enumerated in full, `UNCONNECTED2594`…`UNCONNECTED2626` |
| "85.8 % utilisation against a ~92.2 % wall, so there IS headroom." | **True, and I re-derived it** — but the two numbers come from different runs and the wall is empirical, not a budget. rc5 finished post-route at **85.84 %**. 92.17 % is the density at which an *earlier* lineage's DRV recovery failed with "exceeding max local density". | `reports/qor_05_route_opt.rep` (`opt_design_postroute` 85.84 %); `docs/tapeout/16-open-defects.md:121, 203–222`; `docs/tapeout/66-rc5-flow-findings.md:1059` |

The `TEST` pad, by contrast, **is** case-analysed to 0 and always has been —
`ASIC/genus-innovus/inputs/constraints.sdc:858`, one of only two
`set_case_analysis` statements in the entire constraint set (`:845`).

### 1.2 What actually exists today

**A complete, working IEEE 1149.1 TAP and boundary-scan register.** This is the
single most important asset for the plan and it is easy to miss because two
documents still say it does not exist (`docs/tapeout/24-d2d-link-physical-handover.md:284`
— "No boundary scan, no TAP" — is stale).

- 76 boundary cells over 48 signal pads (18 input, 15 output, 13 bidir, 2 open-drain).
- RTL and BSDL both generated from one `src/rtl/bscan/pad_table.json` so they
  cannot drift; `python3 scripts/gen_bscan.py --check` is the CI gate.
- IDCODE, EXTEST, SAMPLE/PRELOAD, CLAMP, BYPASS.
- A gate-level bench, `verif/bscan/tb_bscan_gate.sv`, that shifts through the
  **routed netlist** contacted only at its 48 package pads — 7 tests, 5,063
  comparisons, 4,418 TCK cycles — with a measured mutation table.
- **The output half works; the input half is not built.** All 33 `*_core_in`
  observe outputs dangle, so EXTEST can drive pads outward but the boundary
  register cannot capture a value *into* the core, and INTEST is impossible.

**The TAP's pin assignment is the precedent the whole pin-budget answer rests on**
(`src/rtl/bscan/pad_table.json`, `design.tap`):

| TAP function | Pad instance | Functional owner |
|---|---|---|
| mode strap / `trst_n` | `uPAD_SE_I` | (was dangling — chosen because it was free) |
| `TCK` | `uPAD_SWDCK_I` | SWD clock |
| `TMS` | `uPAD_SWDIO_IO` | SWD data |
| `TDI` | `uPAD_HOST_IO_0` | HOSTIO4 bit 0 |
| `TDO` | `uPAD_HOST_IO_1` | HOSTIO4 bit 1 |

Five bonded functional pins, re-purposed under a strap, zero new pads.

**A scan-enable port that reaches the CPUs and stops at the pad ring.**
`sys_scanenable` exists at every level from `src/rtl/nanosoc_eth_chiplet.sv:99`
down to `DFTSE` on both Cortex-M0+ cores
(`nanosoc-multicore-system/nanosoc_arch_tech/rtl/slcorem0p_tech/src/verilog/slcorem0p.v:273, 325, 375`).
At the chiplet top it is connected to nothing:
`.sys_scanenable (UNCONNECTED_HIER_Z1071)` — `..._gate.v:593578`.

**A test-mode signal that already does two of the three things scan needs.**
`TEST` → `bsp_test_i_in` → `sys_testmode`, which drives `CGBYPASS` **and**
`RSTBYPASS` on the system controller
(`nanosoc_arch_tech/rtl/src/subsystems/systemctrl/nanosoc_ss_systemctrl.v:148–149`).
`RSTBYPASS` makes `NRST` drive all resets directly, bypassing the 2-flop reset
synchronisers (`nanosoc_clkctrl.v:99, 184–187`); `CGBYPASS` disables the
system-controller clock gates (`:168, 177`). Measured in the netlist:
`sys_testmode` gates the reset-synchroniser outputs for `DBGRESETn`, `PORESETn`
and `HRESETn` (`..._gate.v:68126, 74390, 105576`).

**3,776 scan-footprint flops that are not a chain.** The netlist contains
`SDF*` cells, and it is a trap: they are functional mux-flops that Genus chose
for area, with `.SE` and `.SI` driven by functional logic. I parsed all 3,776
instantiations — **every one** has `.SE` and `.SI` on a net, none on a constant,
and there is no chain. (`docs/tapeout/16-open-defects.md:510–640` reaches the
same conclusion about the `IMPSP-9099` warning.)

### 1.3 The blocking defect: 3,007 clock gates tied off

Genus wraps every integrated clock gate in a `cg_RC_CG_MOD_*` module with a
`test` port that drives the `CKLNQD1`'s `TE` pin. I parsed every instantiation
in the rc5 netlist:

```
cg_* instantiations found: 3007
    3007  .test(1'b0)
```

**All 3,007 are hard-tied to zero.** A scan chain cannot shift through a clock
gate whose test-enable is 0 — the gate passes the clock only when its
*functional* enable happens to be high, which during shift is arbitrary. Any
scan insertion must drive all 3,007 from the shift-enable signal.

This is not expensive to fix. Genus connects the CGIC test pin to the declared
shift-enable automatically once `DFT` is on and `define_dft shift_enable` has
named a signal. The cost is the buffer tree, not the gates. But **it is
absolutely load-bearing**: an otherwise-correct scan insertion that misses this
produces a netlist whose chains do not shift, and neither Genus nor Innovus
will say so.

**A gate for it ships with this plan:** `scripts/ci/dft_icg_census.py`. It is
read-only, needs no licence and no EDA tool, runs in seconds on the 51 MB
netlist, and carries a `--selftest` with two cases that must go red. Measured
output on rc5:

```
$ scripts/ci/dft_icg_census.py --netlist .../nanosoc_eth_chiplet_pads_gate.v
clock-gate instances found: 3007
    3007  tied_low
distinct test-pin drivers: 1
    3007  .test(1'b0)
```

**And the same defect looks different at different stages, which is a trap.**
On the *post-route* netlist the census reports `3007 no_test_pin`, not
`3007 tied_low` — Innovus drops the connection entirely once the constant is
propagated. **A checker that greps for `1'b0` reads the post-route netlist as
clean.** The script classifies an absent connection as the same failure and
fails on both; anything hand-rolled must do the same. This is the
report-misreading class this project has hit before.

The script is deliberately *not* wired into `ci/signoff.yaml` — it is a
measurement instrument for Stage 1 (§7), and it becomes a gate when `DFT=1`.

### 1.4 The two existing DFT plans, and why neither is usable here

| | `tidelink/docs/reference/DFT_PLAN_2026_05_28.md` | `nanosoc-multicore-system/ethernet-subsystem-ahb/docs/post-freeze/dft_plan.md` |
|---|---|---|
| Target top | `tidelink_top` via `tidelink_dft_wrapper` | `ethernet_ss_ahb` as a hardened macro |
| Chains | 8, mux-D | 4, mux-D |
| Tool | TestMAX / Tessent | Cadence Genus |
| Scan clock | dedicated `scan_clk`, 50 MHz shift | reuse `sys_fclk` |
| Compression | none | "not required" |
| TAP | "V1 decision: defer" (§5:254) | "delegate to parent" (line 26) |

**Neither targets `nanosoc_eth_chiplet_pads`.** One defers the TAP, the other
delegates it to a parent that never accepted the role. They disagree on chain
count, tool and scan-clock strategy. They are block-level plans for two
different blocks, and the chip they compose into has no plan — which is what
this document is.

### 1.5 The five tapeout blockers, assessed

`DFT_PLAN_2026_05_28.md` §1.2, lines 43–50, marks exactly five items
`BLOCKER`. All five shipped open; `docs/tapeout/61-respin-assessment.md:345`
records the decision as already made ("Not affordable").

| # | Blocker (verbatim) | Assessment now |
|---|---|---|
| 1 | Scan-insertion script (TestMAX / Tessent / SpyGlass DFT) — "No way to insert scan chains." | **Partly obsolete, and the plan named the wrong tool.** The asic-toolkit's Genus flow already contains `convert_to_scan` / `connect_scan_chains` / `write_scandef` (`ASIC/asic-toolkit/flow/genus/1_synthesis.tcl:987–992, 1184–1189`). The gap is one project `dft_setup.tcl`, not a tool. `tidelink/syn/asic/dft/insert_scan.tcl` is a self-declared scaffold that prints `TODO:` for every real command and targets a tool chain this project does not use. |
| 2 | ATPG flow — "No stuck-at / transition coverage number." | **Still fully open, and the hardest item.** Needs an ATPG licence (§8). Nothing in this repo generates or grades a pattern set. |
| 3 | MBIST controller around `tidelink_sram.sv` — "No way to test the 4 KiB rf_16k." | **Open, and under-scoped by a factor of 19.** The blocker names one `rf_16k`. The chip has **19 SRAMs across 6 cell types** plus 2 ROMs. `insert_mbist.tcl` is a scaffold whose own last line reads `no real work done — TODO above`. |
| 4 | BIST status APB register — "No SW-visible PASS/FAIL after BIST." | **Open, and cheap.** A handful of flops behind the existing APB fabric. Should be delivered with item 3, not after it. |
| 5 | Test-clock SDC (`create_clock` for `scan_clk`, gating disable on shift) | **Open, and its absence is worse than stated.** `TEST` is case-analysed to 0, so *no* test-mode path in this design has ever been timed at all — not just the shift clock. |

**Verdict on the set:** items 1, 3, 4 and 5 are tractable. Item 2 (ATPG) is
gated on tooling this document cannot assume. That asymmetry is why the adoption
path in §7 puts structural work first and pattern generation last.

### 1.6 `DFT_SETUP_TCL`

The flow contract reports `DFT_SETUP_TCL (not configured - no scan insertion)`.
That string is composed at runtime from `asic-flow-check:131` and `:385`; it is
an INFO, never a failure.

The switch is **unimplemented but honest**. `DFT_SETUP_TCL` defaults to empty
(`ASIC/asic-toolkit/mk/flow.mk:259`) and is exported as `ASIC_DFT_SETUP_TCL`
(`:373`). It is consumed only under `if {$DFT}`; setting it alone does nothing,
and setting `DFT=1` without it aborts with a `die` that names the missing
variable. `DFT` is `0` in two places: `ASIC/eth-chiplet/config/design_config.tcl:237`
and `ASIC/genus-innovus/scripts/config.tcl:212`.

**A real gap behind the switch:** Genus writes a SCANDEF
(`1_synthesis.tcl:1188`) and **no Innovus stage ever reads it.** I grepped the
whole toolkit and project flow for any `read_def` or scandef consumption and
found none. `reorder_scan -clock_aware true` at `3_cts.tcl:1323` therefore has
no chain definitions to reorder. Fixing this is one line in the Innovus
floorplan or place stage and it must be part of item 3 in §3.2.

### 1.7 Design facts the plan is sized against

All from run `rc5vt-20260829` unless noted.

| Quantity | Value | Source |
|---|---|---|
| Die | 1600 × 2000 µm = 3.20 mm², **FIXED** | `ASIC/genus-innovus/scripts/floorplan.tcl:61, 107` |
| Core box | 1190 × 1590 µm = 1.8921 mm² (59.1 % of die) | `reports/design_report.json` |
| Standard cells | 194,767 | `syn_gates.rep:414` |
| Sequential cells | **58,506** (54,698 `DF*` + 3,776 `SDF*` + 32 other) | `syn_gates.rep:421` |
| Sequential area | 463,655.52 µm² — **55.9 % of all standard-cell area** | `syn_gates.rep:421` |
| Integrated clock gates | 3,007 | `syn_gates.rep:424` |
| Latches | 1 (`LNQD1`) | `syn_gates.rep`, `cts_clock_trees.rep` |
| Macros | 21 instances, 8 cell types, 757,805 µm² (40 % of the core) | `syn_gates.rep` library table |
| Signal pads / total IO cells | 48 / 82 | `..._as_built_pads.csv` |
| Post-route density | **85.84 %**, 243,005 instances | `qor_05_route_opt.rep` |
| Synthesis runtime | 6,387 s (1 h 46 m) | `logs/syn.log2:8240` |

**The die is pad-limited, not core-limited** — the core is 59 % of the die area,
the rest is the 205 µm pad frame. And the ring is full at wire-bond pitch:
measured bond-pad pitch is **80 µm** on top, bottom and right, and **67 µm** on
the left, where 26 pads were already squeezed into space for 22. The 4,195 µm
of `PFILLER*` in the ring is not spare room; it is the mandated inter-pad
spacing (`space=55` between 25 µm cells in the `.io` file). **There is
approximately one spare pad slot on the right edge and none anywhere else.**

Clock domains and their flop populations (`cts_clock_trees.rep`, Clock Sink
Summary; note flops reachable from several generated clocks are counted under
each, so the column sums to more than 58,506):

| Clock | Period | Posedge flops | Negedge | Notes |
|---|---|---|---|---|
| `clk` | 10 ns | 39,276 | 175 | main system clock; **all 21 memory clock pins**; the 1 latch |
| `D2D_RX_CLK_0` | 10 ns | 13,356 | 0 | from `TL_CLK_RX` pad |
| `D2D_RX_WORDN_CLK_0` | 160 ns | 8,867 | 0 | **generated by an internal divider** |
| `D2D_RX_WORDN_CLK_1..7` | 160 ns | 567 each (3,969) | 0 | per-lane, internally generated |
| `D2D_RX_WORD_CLK_0..7` | 160 ns | — | — | second phase of the same dividers |
| `D2D_TX_WORD_CLK_0` | 160 ns | 1,481 | 0 | internally generated |
| `rmii_ref_clk` | 20 ns | 5,308 | 0 | from pad |
| `mii_rx_clk` | 40 ns | 5,272 | 0 | |
| `swdclk` | 40 ns | 323 | 49 | also the TAP's TCK while `SE`=1 |
| `QSPI_SCLK` (6 views) | 20 ns | 258 | 173 | generated; one flop set, six views |

Two facts here shape the architecture. **All 21 macros are on one clock
(`clk`)** — that makes MBIST single-domain and simple. And **17 of the clock
domains are generated by internal dividers in the D2D PHY**, which cannot be
controlled from a pin during shift; §2.4 deals with that.

---

## 2. Scan architecture

### 2.1 Style: mux-D, and the library already proves it works

Mux-D (`SDF*`) scan, not LSSD. This is not a preference — the design is already
built from these cells. `tcbn65lpwc` supplies 49 distinct `SDF*` variants and
Genus instantiated 3,776 of them in rc5 for functional mux-flops. Every `DF*`
cell in the design has an `SDF*` counterpart at the same drive strength, so
scan replacement is a like-for-like swap the mapper does without restructuring.

**The `.mdt` ATPG model for exactly this library is already on disk.** It ships
in the standard-cell release under `$TSMC_65_HOME`, as an `mdt` archive beside
the NLDM the design was timed against, and unpacks to a `mentor_dft/` directory
holding one `.mdt`. (Resolve it with
`ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh`. This document does not spell
site paths or release revisions, for the reason `ASIC/gls-netlist/Makefile`
gives: a mount point paired with a revision-coded release directory is together
an inventory of what this site is licensed to hold.) That is the
Mentor-DFT-format cell library ATPG needs, and it is version-matched to the
cells being timed.

### 2.2 Pin budget — the answer is "no new pads", and it is already precedented

**The pad ring cannot grow.** The die is fixed at 1600 × 2000 µm; measured bond
pitch is 80 µm on three edges and already compressed to 67 µm on the left to fit
26 pads where 22 belong. There is about one spare slot, on the right edge.

**And it does not need to.** The chip already re-purposes five bonded functional
pins into a JTAG TAP under the `SE` strap (§1.2). Apply the same rule to scan
and the pin problem disappears:

| Scan signal | Pad | Functional owner | Why it is free in scan mode |
|---|---|---|---|
| `scan_in[7:0]` | `TL_RX[7:0]` | D2D link receive | The die-to-die link is idle during scan. 8 inputs, one edge, `PDDW16DGZ_G`. |
| `scan_out[7:0]` | `TL_TX[7:0]` | D2D link transmit | Likewise. 8 outputs, same edge, 16 mA drivers. |
| `scan_clk` | `TL_CLK_RX` | D2D receive clock | Already a clock pad with a clock tree. |
| `scan_en` | `HOSTIO4_P1[2]` | HOSTIO4 bit 2 | Free whenever the TAP owns bits 0 and 1. |
| `test_mode` | `TEST` | — | Already exists and already does the right thing (§1.2). |
| mode strap | `SE` | — | Already the test strap. |
| async reset control | `NRST` | reset | `RSTBYPASS` already makes `NRST` the direct reset in test mode. |

All 17 of those pads sit on the **left edge** (`TL_*`) or are already test pins,
which is convenient for routing the chain endpoints: the scan I/O bus does not
have to cross the die.

**This is a recommendation with a caveat I want to be explicit about.** Sharing
`TL_RX`/`TL_TX` means a scan-mode mux on 16 pad paths, and those paths are the
D2D link's timing-critical ones. `docs/asic/TIDELINK_ASIC_CONSTRAINTS_AUDIT_2026-08-17.md`
should be read before committing, and the mux must sit where it costs the
functional path one gate, not one gate plus a re-time. The boundary-scan work
already measured the analogous cost: adding the BSR mux to pad paths moved the
I/O path groups by +2.435 ns (in2reg) and +5.039 ns (reg2out) **with zero
failing endpoints** (`scripts/bscan_syn_verdict.py`, docstring item 6). That is
the precedent for believing a second pad mux is affordable, and the same script
is the instrument for checking it.

**Three alternatives, and why they lose:**

- *A dedicated 1-bit chain through the existing TAP.* Zero new muxes, uses only
  pins already committed. But 54,698 flops on one chain is 54,698 TCK cycles per
  pattern; at a 10 MHz TCK a 3,000-pattern set takes ~4.6 hours of shift. Viable
  as a **bring-up and diagnostic** path, not as a test.
- *Scan compression (EDT / Modus compression).* Licensed here
  (`Test-Compression-ATPG`, `mttestkompress_c` 150 seats,
  `write_dft_compression_macro` in Genus). It would let 8 pad-level channels
  drive 100+ internal chains and cut pattern volume by ~10×. **I am not
  recommending it for the first respin** — it adds a decompressor/compactor
  block, an X-masking problem this design has not characterised, and a
  debug story nobody here has run. It is the right *second* step (§7).
- *New pads.* Not available (above).

### 2.3 Chain count and partitioning

**Eight chains, partitioned by clock domain first and balanced within a domain.**
Eight because that is what the pad budget yields for free, and because it puts
the longest chain near 5,000 flops — a 5,000-cycle shift, which at a 50 MHz
shift clock is 100 µs per pattern.

Partition by clock domain, not by hierarchy. Every flop on a chain must shift
on one clock; mixing domains inside a chain forces lockup latches at every
boundary and makes the shift-clock skew requirement a cross-domain problem.
Hierarchy-based partitioning would do exactly that here, because `clk` and
`D2D_RX_CLK_0` interleave throughout the TideLink hierarchy.

Sized from the measured per-domain populations in §1.7:

| Chain | Clock domain | Approx. flops | Note |
|---|---|---|---|
| 0–4 | `clk` | 39,276 posedge, 175 negedge, over 5 chains ≈ **7,900 each** | The bulk. Negedge flops lead each chain. |
| 5 | `D2D_RX_CLK_0` | 13,356 | Sourced from the `TL_CLK_RX` pad — directly controllable. |
| 6 | `rmii_ref_clk` + `mii_rx_clk` | 5,308 + 5,272 ≈ 10,580 | Two domains, one chain, **lockup latch at the join**. |
| 7 | `swdclk` + QSPI + spare | 323 + 431 + balance | Short; absorbs balancing. |

That is a first cut from sink counts that double-count flops reachable from
several generated clocks. **The real partition must come from
`report_scan_setup` on a trial insertion**, not from this table. Two things it
will change: the `clk` chains will be longer than 7,900 once the generated-clock
double-counting is removed, and the tool's auto-balance will move flops between
chains 6 and 7.

**Eight chains at ~7,900 is longer than ideal.** A 7,900-cycle shift is
acceptable but not comfortable. If the trial insertion shows the `clk` chains
above ~9,000, the answer is compression (§2.2), not more pads.

### 2.4 The generated-clock problem, which is the real architectural difficulty

Seventeen of this design's clock domains are **generated inside the D2D PHY by
divide-by-16 counters** — `D2D_RX_WORD_CLK_0..7`, `D2D_RX_WORDN_CLK_0..7`,
`D2D_TX_WORD_CLK_0`, all 160 ns, all sourced from flop outputs such as
`.../phy_gpio/gpiorx_0/count_reg[3]/Q` (`cts_clocks.rep`). Between them they
clock roughly **14,300 flops**.

A divided clock cannot be pulsed from a pin. During shift the divider itself is
shifting, so its output is not a clock at all. There are three ways out and only
one is right here:

1. **Bypass mux in test mode (recommended).** Add a `test_mode`-controlled mux
   at each divider output selecting the *undivided* source. All 17 domains then
   become directly controllable from `TL_CLK_RX`. Cost: 17 muxes plus the
   test-mode fanout — trivial. Precedent exists in this very design: the
   TideLink link-rate divider is already handled by `set_case_analysis` on
   `_div_en` / `_byp_en` in `ASIC/genus-innovus/inputs/tidelink_constraints.sdc:160–161`,
   so a bypass path is already in the RTL. **Check whether that existing bypass
   can be reused before adding new muxes** — see §8.
2. Leave them unscanned. Costs 14,300 flops of coverage — about a quarter of the
   design, and precisely the part (the D2D PHY) with the worst silicon history.
3. Scan them on the divided clock with a chain of their own. Works, but the
   shift then runs 16× slower on that chain and the chain must be a separate
   pattern set.

Option 1. And it must be decided *before* insertion, because it changes which
clock the tool sees at those flops.

### 2.5 What must not be scanned

Three populations, measured from the rc5 netlist by instance-name pattern:

| Population | Count | Reason |
|---|---|---|
| CDC synchronisers (`*_sync*`, `*_meta*`, `*Demet*`, `*MultibitSync*`, `*_cdc*`) | 2,965 | Scan-replacing a 2-flop synchroniser inserts a mux in the metastability-settling path. This is the one exclusion that is a correctness requirement, not a trade. |
| Reset synchronisers (`*rst_sync*`) | 51 | Same reason. |
| Boundary-scan cells (`u_bsc_*`) | 119 | Already a chain, clocked by TCK. |
| **Distinct total** | **3,343** | deduplicated union |

`tidelink/syn/asic/dft/insert_scan.tcl:96–108` already carries a
`dont_scan_patterns` list naming most of these by name. It is the right list;
it is in the wrong file (a scaffold for a different tool and a different top).
**It should be lifted verbatim into the new `dft_setup.tcl`** — that is the one
piece of the tidelink scaffold worth keeping.

There is exactly **one latch** in the design (`LNQD1`, an enable latch on `clk`,
per `cts_clock_trees.rep`). One latch is a non-problem: hold it transparent in
test mode or exclude it. Confirm which after insertion.

### 2.6 Boundary scan: finish the input half

Independently of internal scan, the 33 dangling `*_core_in` outputs should be
connected. Today the boundary register can drive pads outward (EXTEST) but
cannot capture into the core, so **INTEST is impossible and the observe cells
are unobservable**. The generator already emits the ports; what is missing is
the padring splice that uses them.

This is the cheapest DFT work available — 33 nets and a regenerated
`insert_bscan_padring.py` — and it makes the existing, already-verified TAP
about twice as useful. It is item 1 in §7 for that reason.

---

## 3. Where scan insertion belongs in this flow

### 3.1 Tooling — what is actually installed here

Verified by execution on 2026-08-31, not from documentation. **All three major
DFT flows are installed and licensed at this site**, which is the opposite of
what the repo's scaffolds assume.

| | Install | Licence (server, seats) | Verdict |
|---|---|---|---|
| **Genus 21.15** | Cadence tool tree; `genus` is on `PATH` | `Genus_Synthesis` 41, **checked out successfully** | Scan insertion. **35 `*dft*` commands** including `check_dft_rules`, `write_dft_atpg`, `write_dft_bsdl`, `write_dft_compression_macro`, `write_dft_pmbist_interface_files`. |
| **Cadence Modus 22.12** | Cadence tool tree, newest of four installed (**off `PATH`, no symlink**) | `modus_atpg` 41, `Modus_DFT_Opt` 41, **`Modus_PMBIST_Opt` 41** | ATPG + memory BIST. Best-integrated with the existing Genus→Innovus flow. |
| **Siemens Tessent 2023.3** | Siemens tool tree (**off `PATH`**; a setup script ships with it) | **150 seats each** of `mttsmemorybist_c`, `mttestkompress_c`, `fastscan`, `mtscanpro_c`, `mttsbscan_c`, `mtnslogicbist_c` | MemoryBIST, TestKompress, FastScan, boundary scan. Most seats by an order of magnitude. |
| **Synopsys TestMAX / DFT Compiler** | Synopsys 2022.12 tool tree (**off `PATH`**) | `Test-DFTC-TMAX` 8, `Test-Compiler` 4, `Test-Platform-MBIST` 4 | Works, but 2–8 seats means contention. |
| **SpyGlass DFT** | Synopsys tool tree (**off `PATH`**) | `dftso` 2, **`mbistso`** 2 | Pre-synthesis DFT rule checking; policies `dft`, `dft_dsm`, `mbist-dft` present. |

**Two traps.** (a) Only Genus, Innovus, Conformal, Calibre and the Synopsys
front-end are on `PATH` — Modus, Tessent, TestMAX and SpyGlass are all off-path
with no convenience symlink, which is very likely why every scaffold in this
repo was written as though the tools were absent. (b) **Genus 21.15 prints
`This build will expire on 12/23/2022`** and then runs anyway and checks out a
licence. It worked on 2026-08-31. Confirm before depending on it.

**One correction to the received brief:** there is no `insert_dft` command in
Genus. That is Synopsys DC nomenclature. Genus is attribute-driven — `set_db
dft_scan_style`, `define_dft shift_enable`, then `convert_to_scan` /
`connect_scan_chains`, which the toolkit already calls. I enumerated
`info commands *dft*` inside a live Genus; `insert_dft` would have matched the
glob and does not appear.

**Recommended tool split**, on the principle of least new machinery:

- **Scan insertion in Genus**, because the toolkit already calls the commands
  and the flow already runs Genus.
- **ATPG in Modus**, because it is Cadence-native, has 41 free seats, and
  `write_dft_atpg` in Genus writes its input directly. Tessent FastScan is the
  fallback and has more seats; the `tcbn65lp.mdt` cell library is in Mentor
  format, so Tessent needs *less* library preparation than Modus. Either is
  defensible; pick one and record why.
- **MBIST in Tessent MemoryBIST**, because the memory `.memlib` files are
  already in the LogicVision format Tessent consumes natively (§4.2).

### 3.2 The changes, in dependency order, with the files named

Nothing below has been applied. Each item names the file, and items are ordered
so that each one is testable when it lands.

**1 — `ASIC/eth-chiplet/config/design_config.tcl:237` — `set DFT 1`.**
One line. Aborts the run until item 2 exists, by design
(`ASIC/asic-toolkit/flow/genus/1_synthesis.tcl:912`). Note the sibling
`ASIC/genus-innovus/scripts/config.tcl:212` also says `set DFT 0`; the legacy
flow needs the same change or a decision that it stays non-DFT.

**2 — NEW `ASIC/eth-chiplet/config/dft_setup.tcl`, pointed at by
`DFT_SETUP_TCL` in `ASIC/eth-chiplet/design.mk:222`.** This is the one genuinely
new file and it is the heart of the change. It must declare, in Genus syntax:

- `set_db dft_scan_style muxed_scan`
- `define_dft shift_enable` on the `scan_en` port, active high — **this is what
  connects all 3,007 clock-gate `test` pins (§1.3) and it is the single most
  important line in the file**
- `define_dft test_mode` on `TEST`
- `define_dft test_clock` on the scan clock
- `define_dft scan_chain` × 8, with the `TL_RX`/`TL_TX` I/O of §2.2
- `set_db [get_db insts <pattern>] .dft_dont_scan true` for the 3,343 exclusions
  of §2.5 — lift the pattern list from
  `tidelink/syn/asic/dft/insert_scan.tcl:96–108`
- async-reset handling: declare `NRST` as the test reset, relying on the
  existing `RSTBYPASS` behaviour rather than adding new logic
- `check_dft_rules` before `convert_to_scan`, and **assert on its report**, not
  on the exit status

**3 — Innovus must read the SCANDEF. Currently nothing does (§1.6).** Genus
writes `$OUT_DIR/${block_name}.scandef` at `1_synthesis.tcl:1188`; no Innovus
stage reads it, so `reorder_scan -clock_aware true` at
`ASIC/asic-toolkit/flow/innovus/3_cts.tcl:1323` has no chains to reorder. Add
the read in the floorplan/place stage (`flow/innovus/2_place.tcl`) so the chain
order is known before placement. **This is a toolkit change, and the toolkit is
shared** — see the promotion route in `docs/bscan/TOOLKIT_PROMOTION_PLAN.md`.

**4 — RTL: connect `sys_scanenable`.** `src/rtl/nanosoc_eth_chiplet.sv:99`
already has the port and it already reaches `DFTSE` on both M0+ cores; at the
pad ring it is bound to a dangling wire. Drive it from the `scan_en` pad path.
Also add the §2.4 divider-bypass muxes here.

**5 — Padring: mux `TL_RX`/`TL_TX` into scan I/O.** Extend
`scripts/insert_bscan_padring.py`, which already does exactly this shape of
transformation for the TAP, rather than writing a second splicer. The scan mux
must be **downstream** of the boundary-scan cells so that EXTEST and scan do not
fight for the same pad; the ordering is a design decision that must be recorded
in `src/rtl/bscan/INTERFACE_CONTRACT.md`.

**6 — Constraints: a test-mode SDC.** New
`ASIC/genus-innovus/inputs/dft_constraints.sdc`, modelled on
`bscan_constraints.sdc`, which is the right template because it solves the same
problem (a mode pin that must stay a real net). It needs:

- `create_clock` on the scan clock at the shift period
- `set_case_analysis` for the **functional** mode, applied in the functional
  MMMC views only, so mission-mode timing is unchanged
- `set_false_path -from [get_ports SE]`-style treatment for the new static mode pins
- `set_multicycle_path` / `set_max_delay` on the shift paths
- **Do not** simply delete `set_case_analysis 0 [get_ports TEST]`
  (`constraints.sdc:858`) — read the warning at `:434–443` first, which says the
  line above it must be restored in the same change

**7 — MMMC: a shift view.** This is the part most likely to be underestimated.
Today's MMMC has `default_analysis_view_setup` and `typical_analysis_view` and
knows nothing about a test mode. Scan shift is a *different mode* — different
clock, different case analysis, different (usually relaxed) constraints — and
if it is not a view, it is not timed. `bscan_constraints.sdc` did **not** add a
view for the TAP either, which is a live gap: TCK is timed as `swdclk`.
Adding a shift view multiplies the corner count and therefore the runtime
(§6.4). At minimum: one setup view and one hold view at the shift clock.
Capture timing for at-speed patterns needs the functional views, which exist.

**8 — Gates: a scan verdict script.** New `scripts/ci/dft_scan_verdict.py`,
modelled directly on the existing `scripts/ci/bscan_syn_verdict.py`, whose
docstring already states the doctrine this needs: *"Synthesis exiting 0 says
nothing about whether the ... register is in the netlist ... This reads the
ARTEFACTS, never the exit status."* It must assert:
   - `syn_scan_chains.rep` exists and reports exactly 8 chains
   - the sum of chain lengths equals (sequential cells − declared exclusions),
     with both numbers read from reports rather than hardcoded
   - `report_scan_setup` shows zero unmapped/unscannable violations
   - **the ICG census: zero `cg_*` instances with `.test(1'b0)`** — this is the
     §1.3 defect and it is exactly the kind of thing that passes silently
   - the SCANDEF exists and Innovus read it
   - I/O path-group timing has not moved into the failing set, the same check
     `bscan_syn_verdict.py` already makes for the BSR

### 3.3 Ordering constraint

Items 1–2 are inert without 4 (nothing drives `scan_en`). Item 5 is inert
without 4. Item 3 only matters once 1–2 produce a SCANDEF. **Item 6/7 must land
with or before 1–2**, because a scan-inserted netlist timed without a shift view
is a netlist whose shift path has never been timed — and that is item 5 of the
five original blockers (§1.5), still open for the same reason.

---

## 4. MBIST for the 21 macros

### 4.1 The inventory, and the split that decides everything

21 macro instances, 8 cell types, 757,805 µm² — **40 % of the core area**. All
21 clock pins are on the single `clk` domain (`cts_clock_trees.rep`), which
makes this a single-domain BIST problem.

| Cell | Inst | Words × bits | Capacity | Test ports? | Needs |
|---|---|---|---|---|---|
| `rf_01k` | 1 | 256 × 32 | 1 KiB | **no** | collar |
| `rf_08k` | 4 | 2048 × 32 | 32 KiB | **no** | collar |
| `rf_16k` | 3 | 4096 × 32 | 48 KiB | **no** | collar |
| `rf_32k` | 1 | 8192 × 32 | 32 KiB | **no** | collar |
| `flash_cache_data` | 8 | 256 × 32 | 8 KiB | **no** | collar |
| `flash_cache_tag` | 2 | 256 × 11 | 0.7 KiB | **no** | collar |
| `rom_via` | 1 | 512 × 32 | 2 KiB ROM | **YES** | signature test |
| `eth_rom_via` | 1 | 512 × 32 | 2 KiB ROM | **YES** | signature test |

**19 RAMs totalling 121.7 KiB (996,864 bits) with no test path of any kind, and
2 ROMs with a full test port.** That asymmetry is the plan.

### 4.2 The RAMs: collars, because the compiler will not give us ports

Every RAM here was compiled with **`Test Muxes: Off`**. The port list is
`CLK, CEN, WEN[], GWEN, A[], D[], Q[], EMA[2:0], EMAW[1:0], RET1N` and nothing
else — no `TEN`, no `SI`/`SE`/`SO`, no `DFTRAMBYP`. The only way into the array
is the functional port, so every RAM needs an integrator-authored collar: a mux
on each input that selects BIST drive when `mbist_en` is asserted.

**Recompiling is not a way out for the register files.** The `sram_sp_hde`
compiler *does* support test muxes — the unused `sram_16k` instance in the same
collateral tree has the full `TEN`/`TCEN`/`TWEN`/`TA`/`TD`/`SI`/`SE`/`SO`/`DFTRAMBYP`
collar, which proves the capability exists. But the register files come from
`rf_sp_hdf`, whose `.spec` exposes no test-mux or redundancy knob at all. The
compiler binaries are runnable by this user
(each compiler ships its own `bin/` under `$PHYS_IP`), so this is worth
**five minutes of checking** before accepting it — but the working assumption is
collars for all 19. See §8.

**All the tool-side collateral already exists**, per memory, in the read-only
tree: `.ctl` (IEEE 1450.6, for ATPG), `.masis`, `.mdt`, `.tv`, `.bitmap`, and
crucially **`.memlib`**, which is LogicVision format — the format Tessent
MemoryBIST consumes natively, LogicVision having become Tessent MemoryBIST. The
`.memlib` files already declare, per memory, the BIST algorithm, the memory
type, the port configuration and the logical-to-physical address map — i.e. the
whole of what a BIST generator needs to know, so nothing has to be hand-written
per macro. (Not reproduced here; read them in the PDK.) Each compiler also ships
`doc/README-...-tessentmbist.txt`. **There is no memory-BIST controller IP
anywhere in the ARM or TSMC trees** — the controller must be tool-generated, and
three tools here can generate it.

### 4.3 Topology: one shared controller, one serial BIST bus

**One controller, all 19 RAMs, daisy-chained.** Not per-memory controllers, and
not one controller per subsystem.

- All 19 are on one clock, so there is no reason to split by domain.
- The memories differ in address width (8–13) and data width (11–32), so the
  controller must be width-parameterised anyway; that is the same work whether
  it drives 1 memory or 19.
- Serial (a BIST access chain visiting each memory) rather than parallel keeps
  the controller-to-memory routing to a few wires per macro instead of a
  ~75-bit bus × 19. At this utilisation, routing is the scarce resource.
- Cost of serial is runtime, and the runtime is irrelevant (below).

**Runtime, March C− at 10 operations per address, 100 MHz:**

| | cycles | time |
|---|---|---|
| Fully serial (one memory at a time) | 314,880 | **3.15 ms** |
| Fully parallel (bounded by `rf_32k`) | 81,920 | 0.82 ms |

Three milliseconds. **Runtime is not a design constraint here**, which is why
the serial topology wins on area and routing without costing anything that
matters. Add retention (a ~1 ms hold) and an EMA sweep over `{000, 011, 111}`
and the total is still under 20 ms.

**Status must be software-visible.** That is original blocker #4 (§1.5) and it
is a handful of flops: a `done`/`pass` pair, a first-failing-address register,
and a per-memory fail bitmap, behind the existing APB fabric. Deliver it *with*
the controller; a BIST whose result cannot be read is not a test.

### 4.4 The ROMs: what is testable and what is not

A ROM cannot be march-tested. There is nothing to write, so the entire
stuck-at-cell fault model that MBIST addresses does not apply. What *is*
testable, and what this plan proposes:

**A ROM signature test, and the hardware for it already exists.** `rom_via` and
`eth_rom_via` both expose a full test port — `TA[8:0]` (test address),
`TQ[31:0]` (test data), `TEN`, `TCEN`, plus `AY[8:0]`/`CENY` observation
outputs and `KEN`/`BEN`/`PGEN`. So the array can be swept independently of the
functional address path. The test is: drive `TA` 0…511, compress `TQ` into a
MISR, compare against a golden signature. ~512 cycles per ROM. The same
controller that runs the RAM march can do this; it is one extra state.

**What that catches:** a broken via in the array, a bad decode, an open on the
data path. **What it does not catch:** the ROM having the *wrong contents* —
because the golden signature is computed from the same image, so a
mis-programmed mask matches its own signature.

That gap is **already closed by other means in this repo**, and the ROM test
should not duplicate it:

- `rom_gds_bits.py` extracts the programmed bits from the GDS and diffs them
  against the firmware. Both ROMs verified clean against the `full-20260814`
  stream.
- The GLS `romwatch` probes in `ASIC/gls-netlist/bench/*.json` check `CEN`/`A`/`Q`
  at the macro pins with a `golden` bintxt.

So the honest division: **GDS extraction proves the ROM contains the right
bits; the signature test proves the silicon reads them back.** Neither
substitutes for the other, and the plan needs both. State this explicitly in
any coverage claim, because "the ROM passed BIST" is exactly the sentence that
will be read as "the ROM contains the right firmware".

**The ROMs also need an ATPG bypass.** For logic ATPG, a memory is an opaque
block that blocks propagation. `DFTRAMBYP`-style bypass does not exist on these
macros, so the collar must provide it: in ATPG mode, `Q` is driven from a
scannable register rather than the array, so faults can propagate through. This
applies to all 21 macros, RAMs and ROMs alike, and it is the reason the collar
work benefits ATPG as well as MBIST.

### 4.5 The one thing that makes this verifiable

The compiled `rf_01k` collateral under `$MEM_BASE` ships an
`rf_01k_error_injection` wrapper module beside the memory model — an
**error-injection wrapper supplied by the memory vendor for exactly this
purpose**. It is the ready-made failing case for §5.3: bind it around a macro in
simulation, inject a fault, and require the BIST to report `pass=0` with the
correct failing address. A BIST that has never been shown to fail is not
evidence of anything, and this removes the excuse for not showing it.

---

## 5. How to verify it in gate-level simulation

This is the section most DFT plans skip. It is also the section this project is
best equipped for, because two working precedents already exist here and
between them they solve most of the problem.

### 5.1 What already exists, and what it gives us

**`ASIC/gls-netlist/` — a netlist GLS gate with a real discrimination story.**
It simulates the **routed** netlist (`..._pnr.v`) of the taped-out top cell with
a vendor QSPI flash model attached and a validated boot image, and it is built
around the right doctrine:

- A JSON bench spec (`bench/*.json`) drives a **generated** testbench via
  `ASIC/asic-toolkit/mk/gls_netlist.mk`. Schema: `clocks`, `resets`, `tie0`,
  `tie1`, `pullup`, `mems`, `romwatch`, `traces`, `expects`, `forces`,
  `run_cycles`.
- `make negative-control` runs a **deliberately blank flash and requires the
  gate to go red**, and then checks that the *specific* rungs that must fail did
  fail — not merely that something failed.
- `make no-force` proves mechanically that the run contained no testbench
  override, by checking the generated bench, the transcript and `verdict.txt`.
- `census` statically resolves every cell before compiling, because a run over a
  design that is entirely `z` compiles, elaborates, links and completes cleanly.
- **`GLSN_COMPILE_ARGS_<item>` accepts arbitrary extra SystemVerilog.** That is
  how `flash/gls_flash_attach.sv` is bound in, and **it is the attachment point
  for a scan-protocol driver.** No engine change is needed to host one.

**`verif/bscan/tb_bscan_gate.sv` + `run_gate.sh` — a serial-protocol bench on
the routed netlist, already mutation-proven.** 7 tests, 5,063 comparisons, 4,418
TCK cycles, ~85 s. Its design rules are exactly the ones a scan bench needs:

- **One contact surface: the 48 signal pads.** No hierarchical references
  anywhere. "A probe at `u_dut...u_bsc_75_..._update_q` would prove the flop
  exists, not that it is REACHABLE from the package."
- Zero-delay (`+nospecify +notimingcheck`); stimulus driven `T_DRV` after the
  falling edge, sampled `T_SMP` before the rising edge, so the only races are
  the ones the bench creates.
- **The verdict is not `$?`.** A `BSCAN_GATE_SUMMARY:` line must *exist*, say
  `PASS` with `fails=0`, report `tests=N/N` with `N ≥ 7`, and report
  `checks ≥ 4000`. This rule exists because the first run of the script produced
  "a clean compile, a clean elaboration, a clean link and a completed run over a
  design that was entirely `z`".
- A measured mutation table (README §"Mutation tests — measured, on the
  netlist"), each entry a **single-token edit on a scratch copy** of the routed
  netlist, with the column "caught by" filled in from a real run — including one
  honest row, M4, recorded as *"nothing — a genuine no-op"*.

**Gap:** the JSON schema has `clocks` with a fixed period and no way to express
a shift/capture protocol, and today's runs use **no SDF** at all. Timed
verification is new capability.

### 5.2 The plan: two tiers, because one of them needs a licence and the other does not

#### Tier A — structural chain verification. No ATPG tool. Lands with insertion.

A new `verif/dft/tb_scan_gate.sv` and `run_scan_gate.sh`, built as a sibling of
`verif/bscan/`, contacting the netlist **only at the 48 pads** and driving the
§2.2 port map. Zero-delay. Seven tests:

| | Test | Method | Proves |
|---|---|---|---|
| **T1** | **Chain length** | `SE`=1, `TEST`=1, `scan_en`=1. Shift a marker (`1` followed by zeros) into each `scan_in[i]` and count cycles until it emerges on `scan_out[i]`. | The chain is exactly the declared length. Catches a broken link, a bypassed flop, a shorted segment. |
| **T2** | **Flush integrity** | Shift `0101…` then `0011…` through all 8 chains simultaneously, full length, compare every bit out. | No bit is lost, inverted or duplicated; no chain drives another. |
| **T3** | **Chain independence** | A distinct pattern per chain (e.g. chain *i* gets a walking-1 offset by *i*). | Chains are 8 separate registers, not one accidentally-merged one. |
| **T4** | **Clock-gate transparency** | T1/T2 at full length, plus an explicit count: the number of shift cycles required must equal chain length with **no** stalls. | **The §1.3 defect.** A clock gate whose `test` pin is still 0 stops its flops shifting; the chain then reads short or freezes. This is the test that would have caught 3,007 tied-off ICGs. |
| **T5** | **Scan-enable actually selects** | Repeat T2 with `scan_en`=0. The chain must **not** shift. | `scan_en` reaches every `SDF*` `.SE` pin. A tied-high shift-enable passes T1–T4 and fails only here. |
| **T6** | **Reset control in shift** | Hold `NRST` through a full flush; assert and release it mid-shift. | Async resets are held inactive during shift (via `RSTBYPASS`), so shifting does not clear the chain. |
| **T7** | **Mode exit** | `SE`=0 → functional. Boot the existing `fp1505_cc` bench unchanged. | Scan insertion did not break mission mode — the transparency property the boundary-scan work already established for the BSR. |

T1–T6 need roughly `8 × chain_length × 3` cycles ≈ 200,000 simulation cycles,
comparable to the existing 250,000-cycle boot bench, so runtime is known to be
tolerable.

#### Tier B — pattern validation. Needs ATPG. Follows.

Tier A proves the chains are *wires*. It says nothing about whether the flops
are connected to the right *logic*, and no hand-written bench can, because there
is no independent source of the expected capture values. The only honest source
is the ATPG tool itself, which emits patterns **and expected responses**
together.

So Tier B is **serial pattern simulation**, the standard step:

1. Modus `write_vectors -verilog` (or Tessent `write_patterns -verilog`) emits a
   self-checking testbench plus the pattern set.
2. Run the **first 32–64 patterns serially, zero-delay**, against the routed
   netlist. Any mismatch here is a scan-model error — the tool's view of the
   netlist disagrees with the simulator's. This catches the whole class of
   "ATPG reported 98 % coverage of a circuit that is not the one on the die".
3. Run the same subset **with the SDF** (`..._pnr.sdf` exists, 367 MB) and
   `+notimingcheck` off, to validate the capture timing at the shift and
   at-speed clock rates. This is new capability for this project.
4. Run the **full** pattern set zero-delay if runtime allows; otherwise record
   that only the subset was simulated, which is normal and must be stated.

The coverage number itself comes from the ATPG tool's fault report, **not** from
simulation. A GLS pass says "the patterns are consistent with the netlist"; it
does not say "the patterns detect 98 % of faults". Conflating the two is the
most common way a DFT signoff overstates itself.

#### MBIST verification

Runs in the same Tier A bench, and the JSON engine can host most of it directly:

- **Completion**: a `traces` entry on the BIST `done` signal at the APB status
  register, plus an `expects` on `pass`. If the controller is reachable over
  HOSTIO4 or the TAP, prefer reading it the way the bench-top would.
- **Coverage of the sweep**: `romwatch`-style probes at each RAM's own `A`/`CEN`
  pins — *at the macro boundary, not on the bus*, following the existing bench's
  rule that "a bus-level probe can be satisfied by the testbench itself". Assert
  that every address of every one of the 19 RAMs was visited. A BIST that runs
  for 3 ms and touches 3 memories reports `done`/`pass` exactly like one that
  touches 19.
- **ROM signature**: assert the MISR result and, separately, keep the existing
  `mems.golden` bintxt check. §4.4 explains why both.

### 5.3 The failing case — what makes any of this evidence

Following `verif/bscan/README.md`'s method exactly: **single-token edits applied
to a scratch copy of the routed netlist**, fed back through the runner via a
netlist override, with column 3 filled in from a real run. `ASIC/` is never
written and no RTL is touched.

| # | Mutation | Must be caught by |
|---|---|---|
| **S1** | One chain link bypassed: `.SI(scan_chain_3[412])` → `.SI(scan_chain_3[411])`. Chain 3 becomes one flop shorter. | **T1** (length off by one), T2 |
| **S2** | **One clock gate re-tied off**: a `cg_RC_CG_MOD_*` instance's `.test(scan_en_net)` → `.test(1'b0)`. | **T4** — and this is the mutation that matters most, because it reproduces the exact defect that exists in rc5 today at 3,007 instances |
| **S3** | Two adjacent flops' `.SI` swapped. **Chain length is unchanged.** | **T2/T3 only. T1 passes.** This is the honest limit of a length test and the reason T2 exists. |
| **S4** | Scan-enable tied high: the `scan_en` buffer's output forced to `1'b1`. | **T5 only.** T1–T4 all pass — the chain shifts perfectly and can never capture. |
| **S5** | The `scan_out[5]` pad mux takes the functional net instead of the chain tail. | **T1** (chain 5 never emerges) |
| **S6** | `NRST` gating removed from one chain's flops, so shifting clears them. | **T6 only** |
| **S7** | **MBIST**: bind `rf_01k_error_injection` (§4.5, vendor-supplied) around one `rf_08k` and inject a stuck cell. | **MBIST `pass`=0 with the correct failing address.** Not merely `pass`=0 — the address must be right, or the diagnostic is a coin flip. |
| **S8** | **ROM**: corrupt one word in the ROM `.v` behavioural model. | **ROM signature red**, and — separately — the existing `mems.golden` check red |
| **S9** | Delete four flops from a chain's declared length in the verdict script's expectation. | **The verdict script**, not the bench. This tests the *gate*, not the design. |

Two rules that the existing benches learned the hard way and this one must
inherit:

- **The verdict may not be `$?`.** Require a `SCAN_GATE_SUMMARY:` line to exist,
  to say `PASS` with `fails=0`, to report `tests=7/7`, and to report
  `checks ≥` a declared floor. The `_pnr_pg.v` trap on the bscan bench produced a
  clean compile and a completed run over an all-`z` design; the same trap is
  waiting here.
- **Record the mutations that catch nothing.** The bscan table's M4 row —
  *"nothing — a genuine no-op"* — is the most valuable row in it, because it
  stops the next reader repeating the experiment. Expect at least one here.

Register the count in `ci/MUTATION_COVERAGE` so
`scripts/ci/check_mutation_coverage.py` fails in **both** directions: fewer than
declared means a proof was dropped, more means one was added unreviewed.

### 5.4 What this verification does not prove

Stated plainly, so nobody quotes it as more than it is:

- **Not fault coverage.** Tier A proves the chains are intact. Coverage is an
  ATPG number, from Tier B, and it is a claim about a fault model, not about the
  chip.
- **Not the pads.** The 48 pad cells' own behaviour is boundary-scan's job, and
  the IO library `tphn65lpgv2od3_sl` has **no ATPG model on disk** (§8), so IO
  cells will be black boxes to ATPG regardless.
- **Not silicon.** Everything here is simulation. The first thing that will be
  true on silicon and false in simulation is the shift-clock skew across a
  7,900-flop chain, which is a CTS and STA question (§3.2 item 7), not a GLS one.
- **Not at-speed, unless step 3 of Tier B is actually run.** Zero-delay
  simulation of a transition-fault pattern set validates the pattern's logic and
  nothing about its timing.

---

## 6. Cost

> **A note on what is quoted here.** This repository is public under an Arm
> Academic Access licence and the TSMC libraries are confidential. The figures
> below are **this design's own measurements** — totals, percentages and derived
> per-flop averages computed from the rc5 run's reports. No vendor library table
> is reproduced, and no Liberty timing value is quoted. Where a number could only
> come from reading the vendor Liberty, §8 records it as an open question with
> the local method to answer it, rather than answering it here.

### 6.1 Area — the binding constraint

Computed from the rc5 gate report by pairing each `DF*` population with its
`SDF*` counterpart. **96 % of the total comes from cell pairs where both
variants are instantiated in this very netlist**, so it is a measurement of the
design, not a library estimate. The remaining 4 % uses the measured median delta
of the co-instantiated pairs.

| | µm² | as % of stdcell | density points |
|---|---:|---:|---:|
| Scan-flop swap, 54,698 flops | **133,435** | +16.1 % | **+6.88** |
| Scan-enable buffer tree (~3,000 buffers, *modelled*) | ~5,650 | +0.7 % | +0.29 |
| **Full scan subtotal** | **~139,100** | **+16.8 %** | **+7.17** |
| MBIST collars, 1,095 muxes over 19 RAMs | 3,548 | +0.4 % | +0.18 |
| MBIST controller + APB status (*modelled, 5–10 k*) | 5,000–10,000 | +0.6–1.2 % | +0.26–0.52 |
| **MBIST subtotal** | **8,500–13,500** | **+1.0–1.6 %** | **+0.44–0.70** |
| Boundary-scan input half (33 connections) | ~0 | ~0 | ~0 |

The average is **+2.44 µm² per flop**, a ~30 % increase on the flop. That looks
large and it is correct for *this* design, because **sequential cells are 55.9 %
of all standard-cell area here** (463,655 of 829,971 µm²). This is an unusually
flop-heavy design, and scan therefore costs unusually much.

**Against the headroom:**

```
rc5 post-route density                        85.84 %
empirical wall (DRV recovery failed above)    92.17 %
headroom                                       6.33 points  =  122,740 um2

full scan needs                                            ~139,100 um2
overshoot                                                   ~16,300 um2   (13 % over)
projected density with full scan                            ~93.0 %
```

**Full scan does not fit at 1600 × 2000 µm.** It overshoots the density at which
a previous lineage's DRV recovery failed with *"Could not be fixed because of
exceeding max local density"* (`docs/tapeout/16-open-defects.md:219`) by about
13 %.

**What does fit:** subtracting the scan-enable tree, the budget supports
**~48,000 of 54,698 flops — about 88 %.** So ~6,700 flops must be excluded.
Of those, **3,343 must be excluded anyway** for correctness (CDC and reset
synchronisers, boundary-scan cells — §2.5). The remaining **~3,350 flops
(6 % of the design) is a deliberate partial-scan decision that has to be made
by someone**, and the natural candidate is the D2D PHY's divided-clock domains,
which are also the hardest to scan (§2.4).

Three honest caveats on this arithmetic:

1. The density denominator (1,939,026 µm²) is back-derived from the measured
   post-route pair (1,664,460 µm² at 85.84 %). It is 2.5 % larger than the
   nominal core box, presumably because Innovus excludes some blocked area. The
   *ratio* is what the projection uses, and it is measured.
2. **92.17 % is an observation, not a specification.** It is where one earlier
   run failed. A different floorplan might route at 93 % or choke at 91 %. Treat
   it as the best available evidence, not a contract.
3. Scan insertion at synthesis changes the whole optimisation, not just the
   flops. Genus may recover some area elsewhere, or lose more. **The only way to
   know is a trial synthesis**, which is ~1 h 46 m and item 1 of §7.

### 6.2 Timing

This is where I am least able to give you a number, and the reason is worth
stating precisely: **rc5 closed with a setup WNS of +0.105 ns post-route and
0 failing endpoints.** That is 105 picoseconds of margin on a 10 ns clock. Any
per-flop setup-time increase eats directly into it.

- **Mux-D scan raises the D-pin setup time**, because the mux is inside the
  cell. The magnitude is a Liberty value I have deliberately not quoted (§8 has
  the one-command method to get it). At 105 ps of margin, this is the single
  biggest timing risk in the plan and it must be measured before committing.
- **The scan-enable net is a 54,698-sink high-fanout net.** The design already
  has a cautionary example: `postplace.tcl:25–27` records the `TEST`
  distribution net at fanout 11,009 reaching a 190 ns delay before CTS. A
  scan-enable net with five times that fanout must be planned as a tree from the
  start, not left to `opt_design`.
- **Shift-clock skew across a ~7,900-flop chain** is a new CTS requirement.
  Scan shift usually tolerates more skew than functional operation, but only if
  the shift view exists to check it (§3.2 item 7).
- **Pad-path muxes** on `TL_RX`/`TL_TX`: the boundary-scan precedent moved the
  I/O path groups by +2.435/+5.039 ns with zero failing endpoints, so there is
  evidence this class of change is absorbable — but the D2D paths are the
  design's tightest.

**MBIST timing cost is genuinely small**: one mux delay in front of each RAM
input, on paths that are not the critical ones, plus a slow controller.

### 6.3 Pins

**Zero.** That is the whole point of §2.2. Seventeen already-bonded pads are
re-purposed under a mode strap, using the mechanism the TAP already uses. The
cost is 16 pad-path muxes (above) and a BSDL/contract update, not silicon area
in the ring.

### 6.4 Runtime

Baseline for rc5 (`logs/syn.log2:8240`, `qor_05_route_opt.rep`):

| Stage | rc5 wall time |
|---|---|
| Synthesis | 1 h 46 m |
| place → opt_prects | 45 m |
| ccopt → post-CTS hold | 58 m |
| post-route opt (hold + setup) | 63 m |
| **Full RTL→GDS** | **~6.5 h observed** |

Projected additions, all **estimates and flagged as such**:

| | Estimate | Confidence |
|---|---|---|
| Genus `convert_to_scan` + `connect_scan_chains` + DFT DRC | +15–30 min | medium — scales with flop count |
| Extra MMMC shift view (setup + hold) | +20–40 % of all timing-analysis time | **low — this is the one most likely to be underestimated.** Views multiply, and every `report_timing` runs per view |
| Placement/route at +8 % instances and +7 density points | +10–20 % of P&R | medium |
| `reorder_scan` at CTS | minutes | high |
| **Revised RTL→GDS** | **~8–9 h** | low-to-medium |
| ATPG (Modus or Tessent), separate run | 2–8 h for the first closure, then ~1 h | **guess** — no ATPG run has ever happened on this design |
| MBIST generation (Tessent MemoryBIST) | under an hour | medium |
| Tier-A scan GLS (§5.2) | ~200 k cycles, comparable to the 250 k-cycle boot bench | medium |
| Tier-B serial pattern sim, 32–64 patterns with SDF | **hours** — the SDF is 367 MB | low |

### 6.5 Power

Not estimated, and I am not going to guess. rc5 measures 83.18 mW total, 0.419
mW leakage. Scan adds ~16 % more sequential area, so leakage rises roughly in
proportion — call it +0.05 mW, negligible. Dynamic power *during shift* is a
different matter entirely: every flop toggles every cycle, which is far above
functional activity and is a real concern for a device tested in a socket. That
is a test-engineering constraint (limit shift frequency, or use a low-power
shift mode) and it is out of scope here, but it must not be forgotten at bring-up.

---

## 7. Staged adoption path

Ordered so that **every stage yields something on its own** and no stage
depends on a decision the previous one did not force. Effort figures are for one
engineer familiar with this flow; they are estimates, and the confidence column
says how much to trust them.

### Stage 0 — Finish the boundary scan you already have · **3–5 days** · confidence: high

Connect the 33 dangling `*_core_in` nets (§2.6). No new tool, no licence, no
area, no timing risk, and the verification bench (`verif/bscan/tb_bscan_gate.sv`)
already exists and is mutation-proven.

**Value on its own:** EXTEST becomes bidirectional and INTEST becomes possible,
so a bench-top JTAG master can drive the core's inputs on a chip that does not
boot. Given the silicon history in this project, that is worth having
independently of anything else here.

**Done when:** `bscan_syn_verdict.py` passes with the core_in count asserted, and
a new mutation row in `verif/bscan/README.md` shows a broken observe path going
red.

### Stage 1 — Fix the clock gates and prove scan is *possible* · **1–2 weeks** · confidence: medium-high

Do §3.2 items 1, 2 and 4 only — `DFT=1`, a first `dft_setup.tcl`, and
`sys_scanenable` connected — and run **synthesis only**. Do not touch the
padring, the MMMC or P&R.

**Value on its own:** this is the measurement that decides everything else. It
answers, from the tool rather than from this document:

- the real flop count after exclusions, and the real chain lengths
- **whether all 3,007 clock gates picked up the shift-enable** (§1.3) — the
  headline defect, confirmed fixed or not in one report
- the actual area delta, against the 133,435 µm² projected in §6.1
- the actual setup-time cost, which §6.2 could not give you

**Effort is dominated by `dft_setup.tcl` and by DFT DRC debug**, not by the
one-line switch. Expect the first `check_dft_rules` run to produce a long list;
that list *is* the deliverable, because it enumerates every uncontrollable clock
and unconstrained async reset in the design.

**Done when:** `syn_scan_chains.rep` shows 8 chains, and a first cut of
`scripts/ci/dft_scan_verdict.py` (§3.2 item 8) asserts the ICG census at zero.
**A synthesis that runs is not the deliverable; the numbers are.**

### Stage 2 — MBIST · **3–4 weeks** · confidence: medium

Independent of scan and **should not wait for it**. Generate collars and a
shared controller with Tessent MemoryBIST from the existing `.memlib` files
(§4.2–4.3), add the APB status register, and verify with the vendor's own
`rf_01k_error_injection` wrapper (§4.5, mutation S7).

**Value on its own:** 121.7 KiB of SRAM across 19 instances currently has **no
test path at all**. This is the largest untested area on the die, it is 40 % of
the core, and MBIST costs **+0.44 to +0.70 density points** — one fifteenth of
what scan costs. If only one thing on this list is done, it should be this one.

**Why it can go before scan:** the collar muxes and the ATPG bypass they provide
are needed by scan too (§4.4), so this is not throwaway work.

### Stage 3 — Partial scan, physically closed · **4–6 weeks** · confidence: medium-low

Everything else in §3.2 — padring muxes, test SDC, MMMC shift view, SCANDEF read
into Innovus — and a full RTL→GDS at the flop count Stage 1 measured.

**The decision this stage forces**, and it should be taken deliberately rather
than discovered at 92 %: **which ~3,350 flops beyond the mandatory 3,343 are
left out** (§6.1). Recommendation: the D2D divided-clock domains, because they
are also the hardest to make controllable (§2.4) — but that is precisely the
block with the worst silicon history, so this is a real trade and not an obvious
one.

**Confidence is lower here** because it is the first time the design sees a new
MMMC view, a higher density and a new class of pad mux together.

**Done when:** the run closes at a density Stage 1's numbers predicted, with the
Tier-A GLS bench (§5.2) green and its mutation table filled in from real runs.

### Stage 4 — ATPG and a coverage number · **3–5 weeks** · confidence: low

Modus (or Tessent FastScan) against the Stage-3 netlist, using
`write_dft_atpg` from Genus and the `tcbn65lp.mdt` cell library. Then Tier-B
pattern validation in GLS (§5.2).

**Confidence is low because nobody here has run ATPG on this design.** The
estimate assumes the tool is cooperative; the memory `.ctl` models, the IO black
boxes and the two M0+ cores are each capable of costing a week on their own.

**Value on its own:** the first real coverage number this project has ever had.
Everything before it is structure; this is the only stage that produces a
percentage anyone should quote.

### Stage 5 (optional) — Scan compression · **3–4 weeks** · confidence: low

Only if Stage 4's pattern count or test time turns out to be a problem, and only
with the Stage-4 flow working first. Licensed and installed (§3.1). §2.2 says
why it is not stage 1.

### Summary

| Stage | Effort | Area cost | Needs a licence beyond Genus? | Value alone |
|---|---|---|---|---|
| 0 · finish boundary scan | 3–5 d | ~0 | no | INTEST/EXTEST on a dead chip |
| 1 · scan-possible measurement | 1–2 w | 0 (no tapeout) | no | the real numbers; ICG fix confirmed |
| 2 · **MBIST** | 3–4 w | **+0.44–0.70 pts** | Tessent (150 seats) | **121.7 KiB goes from untested to tested** |
| 3 · partial scan closed | 4–6 w | +6.0–6.5 pts | no | a scannable die |
| 4 · ATPG | 3–5 w | 0 | Modus (41) or Tessent (150) | a coverage number |
| 5 · compression | 3–4 w | +~1 pt | Modus/Tessent | shorter test time |

**If the respin budget allows only one item: Stage 2.** If it allows two:
Stage 0 and Stage 2 — together they are under 5 weeks, cost under one density
point, need no new pads, and turn the two largest untested structures on the
die (the SRAMs, and the core-facing half of the boundary register) into tested
ones. Scan is the right long-term answer and it is why Stages 1 and 3 are
specified here, but it is the expensive half of this plan and it does not fit
without a partial-scan decision.

---

## 8. Open questions, and everywhere I am guessing

Flagged explicitly, as required. Each has the method to close it.

**Measured facts I am confident in:** the 33/33 dangling `core_in`; the 3,007
tied-off clock gates; the 3,776 `SDF*` cells that are not a chain; the 133,435
µm² scan area delta (96 % from co-instantiated pairs); the per-domain flop
counts; the 85.84 % post-route density; the bond pitches; the pad-table TAP map;
the memory inventory and their absent test ports; the installed tools and their
licence seats.

**Open questions:**

1. **The `SDF*` setup-time penalty (§6.2).** Deliberately not quoted — it is a
   confidential Liberty value and this repo is public. It is also the biggest
   timing risk, at 105 ps of margin. *Close it locally, do not publish it:*
   read `setup_rising` for `D` on a `DF*`/`SDF*` pair in the worst-case
   standard-cell Liberty (a run's own `work/*/libs/mmmc/` symlink resolves to
   it), or just read the WNS delta out of Stage 1's trial synthesis, which
   answers the real question directly and involves no vendor file at all.
2. **Can the register files be recompiled with test muxes?** §4.2 says no —
   `sram_16k` (same tree, `sram_sp_hde` compiler) has a full collar, but
   `rf_sp_hdf`'s `.spec` exposes no test-mux knob. The compiler binaries are
   runnable by this user. **Half an hour of checking could delete the entire
   collar workstream**, so check before building collars.
3. **Is the TideLink link-rate divider bypass reusable for scan (§2.4)?**
   `tidelink_constraints.sdc:160–161` case-analyses `_div_en`/`_byp_en`, so a
   bypass path exists in the RTL. If it reaches all 17 generated clocks, the
   §2.4 muxes are free. I did not trace it to the PHY word-clock dividers.
4. **The IO library has no ATPG model.** `tphn65lpgv2od3_sl` is not under
   the PDK's own `iolib` tree (which holds three other IO families) and I
   found no `.mdt` for it anywhere readable. The 9 IO cell types will be ATPG black boxes unless a
   model is written. Impact is bounded — pad faults are boundary-scan's job —
   but it must be declared, not discovered.
5. **Genus 21.15 prints a 2022 build-expiry warning** and runs anyway, having
   checked out a licence on 2026-08-31. Confirm before a schedule depends on it.
6. **Does `reorder_scan` need more than a SCANDEF read?** §1.6 establishes that
   nothing reads the SCANDEF today. I have not verified that adding the read is
   sufficient for Innovus 21.11 to reorder — there may be a `set_db` alongside it.
7. **My chain partition (§2.3) double-counts.** The per-domain flop numbers come
   from CTS sink counts, where a flop reachable from several generated clocks is
   counted under each. The table is a sizing sketch; `report_scan_setup` from
   Stage 1 replaces it.
8. **The scan-enable buffer tree (~5,650 µm²) is modelled**, at 3,000 buffers for
   54,698 sinks. Same for the MBIST controller (5–10 k µm²). Both are engineering
   estimates, not measurements, and both are small relative to the 133,435 µm²
   that is measured.
9. **Every Stage-4 and Stage-5 effort figure is a guess**, because no ATPG run
   has ever happened on this design. Stages 0–2 I would defend; Stages 3–5 are
   planning numbers.
10. **The 92.17 % wall is one observation from one earlier run** (§6.1 caveat 2).
    The whole "full scan does not fit" conclusion rests on it. It is the best
    evidence available and it is not a specification.

**One process note.** Two documents in this repo still assert there is no
boundary scan and no TAP (`docs/tapeout/24-d2d-link-physical-handover.md:284`,
and the DFT plan's own §2.4/§5 deferral). Both are stale — the TAP is in the rc5
netlist and has a gate-level bench. A future reader who greps for "boundary
scan" will find the wrong answer first. That is worth a correcting line in those
files, in a separate change from this one.
