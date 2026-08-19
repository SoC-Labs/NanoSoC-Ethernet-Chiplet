# CDC ↔ STA crossing register

**Compiled 2026-08-18.** One row per clock-domain crossing that this project can
name, with what CDC says about it, what STA does to it, and whether anyone has
actually checked it.

This document exists because CDC and STA have been disjoint universes on this
project. CDC is run by hand with SpyGlass out of `cdc/` and `*/cdc/`; STA is
constrained from `ASIC/genus-innovus/inputs/*.sdc`. Neither references the other.
The two use **different clock names, a different top, and a different set of
design units**, so a crossing can be suppressed on both sides at once and look
handled from either.

**Nothing here changes any constraint, waiver or RTL file.** It is analysis only.

---

## 0. How to read this — the priority ladder, stated once

Three facts do all the work below. They are established elsewhere and are used,
not re-derived:

1. **`set_clock_groups -asynchronous` is reciprocal false paths between groups.**
   It cuts *between* groups and never *within* one.
2. **False path outranks multicycle**, unconditionally and regardless of file
   order (verified from `$INNOVUS_DOC_ROOT/innovusTCR/set_max_delay.html`).
   So a multicycle written on a grouped clock pair is not redundant — it is
   **extinguished**. It never applied.
3. **This design expresses every clock-to-clock cut through one
   `set_clock_groups -asynchronous -name eth_chiplet_cdc`**
   (`ASIC/genus-innovus/inputs/constraints.sdc:395-399`). Resolve group
   membership first; only then ask which remaining exception survives.

Status vocabulary:

| Status | Meaning |
|---|---|
| **RED** | Neither lens checked it. CDC waived/black-boxed **and** STA cut it, or the crossing is real and both are silent. |
| **AMBER** | One lens covers it, or an argument exists but no tool has confirmed it, or the two lenses disagree. |
| **GREEN** | Checked on both sides, or correct-by-construction with a cited mechanism. |
| **ALIAS** | No crossing exists on the taped-out die — the two "domains" are one net. |

---

## 1. Method, and exactly what this covers

### 1.1 How the rows were found

Four independent enumerations, intersected:

1. **The STA exception set — complete census, by grep.** Every uncommented
   exception in the five files selected by `SDC_FILES`
   (`ASIC/eth-chiplet/design.mk:277`, which names `constraints.sdc`; that file
   sources the other four at `:241-247`). Measured, not quoted:

   | Statement | Count (live inputs) |
   |---|---:|
   | `set_false_path` | **9** |
   | `set_multicycle_path` | **1** |
   | `set_clock_groups` | **1** (**4** groups, 33 clocks) |
   | `set_max_delay` | **4** (2 in a `catch`, 2 in its fallback) |
   | `set_case_analysis` | **4** |
   | `set_min_delay` / `set_disable_timing` | 0 |

2. **The CDC crossing set — the chiplet-top SpyGlass run.** `cdc/nanosoc_eth_chiplet.sgdc`
   against top `nanosoc_eth_chiplet`, goal `cdc/cdc_verify_struct`, with
   **`cdc/waiver.swl` containing zero `waive` statements**. 137 unsynchronised
   crossings / 37 deduplicated findings / 10 classed REAL
   (`CDC_B7_ROUND2.md` §2a, §7). This is the only crossing enumeration in
   the tree that is not filtered by a waiver file, and it is the register's spine.

3. **The suppression set — every waiver file in the tree**, to answer "was this
   crossing hidden at block level?" (`CDC_WAIVER_INVENTORY.md`, re-measured
   against the current worktree — see §2.3, the counts have moved).

4. **Targeted RTL structural search** for synchroniser primitives, async FIFOs
   and gray/binary pointer crossings, in the D2D link and in the subsystems, to
   supply the "synchroniser type" column and to catch crossings that *neither*
   tool sees because the block is black-boxed.

### 1.2 What this register DOES cover

- **Every ordered clock-domain pair with a non-zero crossing count** in the
  chiplet CDC run (12 pairs), each mapped to an explicit STA verdict. Complete
  for the pairs the tool reported.
- **Every one of the 19 STA exception statements** in the live input set, each
  mapped to a CDC verdict. Complete.
- **The named synchroniser anchors STA cuts or bounds by name** — 69 first-stage
  demet pins (`constraints.sdc:517-518`) and 22 datapath cells
  (`constraints.sdc:568-577`). Complete for those anchors.
- **The D2D link's CDC structures read from RTL**, including the ones inside the
  black box that no CDC run has ever analysed.
- **The delta between the live constraint inputs and the constraint set the
  shipping database was actually built with** (§2.4). These are not the same
  file, and three rows below turn on that.

### 1.3 What this register does NOT cover — read before quoting it

- **It is not a per-flop enumeration.** The design has ~58,620 flops across 33
  declared clocks. This register has 42 rows. It covers crossing *families* and
  the named exceptions, not every path.
- **The D2D link is not CDC-measured anywhere.** `axi_chiplet_controller` and
  both XHB500 bridges are `stop_module` in the tidelink run
  (`tidelink/cdc/tidelink_top.prj:50`) and black-boxed at chiplet level. Every
  D2D row below is derived from **RTL reading**, not from a CDC measurement.
  Additionally, 18 black-box pins — including `pad_rx[7:0]`, the far-die receive
  data — carry an *inferred* five-clock virtual domain, and
  `cdc_verify_struct` sets `-check_multiclock_bbox=yes`, whose documented effect
  is that crossings into an unconstrained multi-clock black-box pin are
  **ignored** (`CDC_AND_CRC_ASSESSMENT_2026-08-17.md` §3.3).
- **Structural CDC only.** `cdc/cdc_verify` (the functional goal) does not
  terminate in batch here; the advanced-formal `Ac_cdc` metastability rules have
  never run on QSPI (`ahb_qspi/docs/cdc_signoff_status.md:5-12`). 14 rules from
  `clock_reset_integrity` — including `Reset_check07` and `Clock_Reset_check03` —
  were never registered by the goal that ran.
- **88 CDC findings are counted but never triaged** and are not represented
  row-by-row here: `Ac_coherency06` (41), `Reset_sync04` (14), `Ac_conv01/02/04`
  (24), `Ac_glitch03` (9). Their being unchanged across two runs is evidence
  nothing was *masked*; it is not evidence they are clean.
- **No STA run was made for this document.** Every STA verdict is read from the
  constraint text and from the written SDC of the shipping build
  (`ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_syn.sdc`).
  No timing report was consulted and no tool was invoked.
- **The Cadence HAL `cdc` signoff stage has produced no CDC information at all.**
  It aborts on synthesizability errors before a rule runs, and its liveness guard
  is anchored on a prefix this HAL never emits, so it cannot say PASS even once
  the abort is fixed (`CDC_AND_CRC_ASSESSMENT_2026-08-17.md` §1.2-1.3). The
  stage is `gate: report`, so the red is invisible.
- **Firmware-contract rows are a snapshot of today's firmware.**

---

## 2. The domain map — the reason nothing reconciled before

### 2.1 CDC and STA analyse different tops, with different clocks

This is the single fact that makes the two sets incomparable line-by-line, and
it is why a mapping table has to come before any row.

| | CDC | STA |
|---|---|---|
| Top | `nanosoc_eth_chiplet` (inner wrapper, 111 ports) | `nanosoc_eth_chiplet_pads` (pad ring) |
| Selected by | `cdc/nanosoc_eth_chiplet.sgdc` §1 | `ASIC/eth-chiplet/design.mk:78`, `ASIC/genus-innovus/scripts/config.tcl:157` |
| Clock objects | **13**, in **7** domains | **33**, in **4** groups |
| `rtc_clk`, `user_ref_clk` | distinct clock ports | **do not exist** — aliased onto the `sys_fclk` pad |

The alias is a two-line fact:

```
build/chip/rtl/nanosoc_eth_chiplet_chip.v:102    .rtc_clk       (sys_fclk),
build/chip/rtl/nanosoc_eth_chiplet_chip.v:103    .user_ref_clk  (sys_fclk),
```

with no pad for either (`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:137-139`,
`:267-272`), and `constraints.sdc:64-70` says so explicitly and refuses to
`create_clock` them.

**Both readings are correct and neither is wrong.** The SGDC deliberately
analyses the inner top so the RTL is exercised as if the clocks were independent —
right for RTL robustness, for the FPGA build, and for any respin that bonds
`rtc_clk` separately. The pad-ring SDC describes the die that was taped out.
What has been missing is anybody writing down that they are different questions.

### 2.2 The mapping table

| CDC domain (`cdc/nanosoc_eth_chiplet.sgdc`) | CDC clocks | STA clock(s) | STA group | Note |
|---|---|---|---|---|
| `sys_fclk_domain` | `sys_fclk` :82, `sys_hclk` :99, `qspi_sclk` :210 | `clk`, `QSPI_SCLK`, `QSPI_SCLK_o` | **1** | + the 9 D2D transmit clocks, per [C2] Option A |
| `rtc_domain` | `rtc_clk` :166 | **none** | folded into 1 | **ALIAS** — same net as `clk` |
| `wlink_ref_domain` | `user_ref_clk` :225, `pad_clk_tx` :238 | `D2D_TX_CLK_0`, `D2D_TX_WORD_CLK_0..7` | **1** (live) / own group (shipped) | `user_ref_clk` is an **ALIAS** of `clk` |
| `phy_rx_domain` | `pad_clk_rx` :233 | `D2D_RX_CLK_0`, `D2D_RX_WORD_CLK_0..7`, `D2D_RX_WORDN_CLK_0..7` | **2** | 17 clocks |
| `rmii_domain` | `rmii_ref_clk` :104, `mtx_clk` :157, `mrx_clk` :158 | `rmii_ref_clk`, `mii_tx_clk`, `mii_rx_clk` | **3** | genuinely async — own pad |
| `swclktck_domain` | `dap_swclktck` :216 | `swdclk` | **4** | |
| `idelay_domain` | `idelay_ref_clk` :246 | **none** | absent | Xilinx `IDELAYE2` — FPGA only |

33 STA clocks = 1 `clk` + 1 `swdclk` + 2 QSPI + 3 RMII/MII + 1 `D2D_RX_CLK_0` +
1 `D2D_TX_CLK_0` + 8 RX word + 8 RX wordN + 8 TX word.

### 2.3 Headline counts — measured against the current worktree

| | Value | Source |
|---|---:|---|
| **STA** — exception statements, live inputs | **19** | §1.1 census |
| — `set_clock_groups` groups / clocks | **4 / 33** | `constraints.sdc:395-399` |
| — synchroniser first-stage pins false-pathed by name | **69** | `constraints.sdc:491-518` |
| — datapath cells bounded by `set_max_delay` | **22** | `constraints.sdc:547-577` |
| **CDC** — waiver files | **9** | live tree |
| — total `waive` statements | **295** | live tree |
| — files with blanket `waive -rule "*" -du {X}` | **2** (152 statements) | eth-ss 116, eth-mac 36 |
| — remaining `-regexp` pattern waivers | **1** | `tidelink/cdc/waiver.swl` |
| — `cdc_false_path` | **19** | all in `ahb_qspi/cdc/top_ahb_qspi.sgdc` |
| — `quasi_static` | **21** | across 5 `.sgdc` |
| — waivers active in the chiplet-top run | **0** | `cdc/waiver.swl` |
| **CDC crossings** — unsynchronised, chiplet top | **137** | `CDC_B7_ROUND2.md` §2a |
| — deduplicated findings / classed REAL | **37 / 10** | ibid. §7 |

> **THE INVENTORY'S HEADLINE NUMBERS ARE STALE, AND IN THE GOOD DIRECTION.**
> `CDC_WAIVER_INVENTORY.md` §1 reports **7 files / 215 `waive` / 189 blanket
> `-du`**, and its §2.1 — the flagship finding — reports that
> `tidelink/cdc/waiver.swl:43-51` blanket-waives all Wlink design units while 34
> locally-modified copies of exactly those modules sit in
> `tidelink/src/rtl/local_overrides/`.
>
> **That hole has been closed.** In the current worktree
> `tidelink/cdc/waiver.swl` has been regenerated: 46 → **118** `waive`
> statements, all enumerated by explicit module name, with the four blanket
> patterns gone and an explicit do-not-waive list at `:63-92` naming
> `WavMultibitSync_18`, `WlinkGenericFCReplayV2_{1,3,5,12,13}`,
> `wlink_wlink_ptp_tl_a2l_48x4` and the rest. `waive -rule checkSGDC_05` has
> likewise gone from global to file-scoped (`:368`, `:370`). The generator and
> its drift gate exist and pass:
>
> ```
> $ python3 scripts/cdc/gen_tidelink_waivers.py --check
> OK  no -du waiver in tidelink/cdc/waiver.swl covers any of the 29 modules in src/rtl/local_overrides/
> ```
>
> **THREE CAVEATS, ALL LOAD-BEARING.**
> 1. **The fix is UNCOMMITTED.** `git status` in the submodule reports
>    `M cdc/waiver.swl`. `git show HEAD:cdc/waiver.swl` still has 46 waivers and
>    still carries `waive -du "Wav*" -regexp` at `:44`. **Any clone, any CI job,
>    any other session's checkout gets the blanket version.**
> 2. **The generator is not wired to anything.** `grep -rn gen_tidelink_waivers
>    ci/ Makefile` returns nothing. The `--check` gate the file's own header
>    advertises as a CI gate is not run by CI.
> 3. **The other two blanket files are untouched.** The 152 `waive -rule "*" -du
>    {X}` statements in the two Ethernet waiver files — the ones covering
>    `eth_wishbone`, `tsu`, `ptp_queue`, `reg`, `rtc`, all locally patched — are
>    exactly as `CDC_WAIVER_INVENTORY.md` §2.2 describes them. Rows E1, E2,
>    E3 and E7 below are all in that set.

### 2.4 The live constraints are not the constraints that built the chip

Three rows below turn on this and it is checkable in one command.

| | Live inputs (`ASIC/genus-innovus/inputs/`) | Shipped (`build/full-20260814/outputs/..._syn.sdc`, Aug 14 14:01) |
|---|---|---|
| `set_clock_groups` groups | **4** — D2D TX merged into the `clk` group | **5** — D2D TX in its own group (`:804-812`) |
| SWD `clk`↔`swdclk` | group only; MCPs retired under `[C5]` (`constraints.sdc:97-165`) | group **and** MCP 2/1 (`:237-240`) **and** `set_false_path -hold` (`:112`) |
| RMII/MII ↔ `clk` | group only; CDC 1/2/3 retired under `[C5]` (`ethernet_constraints.sdc:443+`) | group **and** clock-to-clock false paths (`:837`, `:841`) **and** named sync-flop false paths (`:113`, `:228`) **and** the `last_push_flags` MCP (`:790`, `:797`) |
| D2D TX word-clock `-source` | `$WL/user_hsclk` — the common ancestor | `.../u_wlink/pad_clk_tx` (`:39`) — **cannot resolve**; 24 × TA-1018, ~2k TX flops at 0 ns source latency |
| Synchroniser anchors cut by name | 69 pins + 22 datapath cells | **none** — the whole boundary was cut by group membership |

The shipping database therefore carries **two and in places three mechanisms for
the same boundary at once**, which is precisely the defect the `[C5]` blocks were
written to retire. In every case the false path wins and the extra mechanisms
were inert — so this is a **documentation** hazard in the shipped build, not a
timing one. It becomes a real hazard the moment somebody removes a group without
removing its companions.

---

## 3. The register

Paths are relative to the repo root unless absolute. `$WL` =
`u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink`, as
defined at `tidelink_constraints.sdc:243`.

### 3.1 D2D / TideLink

> **Coverage warning for this whole subsection.** No CDC tool has ever analysed
> inside this block. `tidelink/cdc/tidelink_top.prj:50` sets
> `stop_module {axi_chiplet_controller xhb500_axi_to_ahb_bridge_chiplet_mst
> xhb500_ahb_to_axi_bridge_chiplet_slv}`, and at chiplet level the same module is
> a black box whose `pad_rx[7:0]` / `pad_tx[7:0]` pins carry an inferred
> multi-clock virtual domain that `-check_multiclock_bbox=yes` causes crossings
> *into* to be discarded. Every row here is RTL-derived. The "CDC verdict" column
> records what the waiver/SGDC layer *says*, which in most of these rows is not
> the same as what a tool measured.

| # | Source domain | Dest domain | Synchroniser (RTL file:line) | CDC verdict | STA exception | Evidence | Status |
|---|---|---|---|---|---|---|---|
| **D1** | `pad_clk_rx` (`D2D_RX_CLK_0`) | `sys_hclk` (`clk`) | Wlink RX link layer + `WavDemetReset` 2FF chains; `tidelink/src/rtl/local_overrides/WlinkRxLinkLayer.v:1194` | **WAIVED** — `tidelink/cdc/waiver.swl:296` `waive -rule Ac_unsync02 -msg "*pad_rx*"`. Reported as REAL finding **50** at chiplet level, but the crossing's interior is black-boxed and `pad_rx[7:0]` is one of the 18 inferred-virtual-domain pins | **CUT** — group 2 vs group 1, `constraints.sdc:395-399` | `CDC_B7_BASELINE.md` §5 #50; `CDC_AND_CRC_ASSESSMENT_2026-08-17.md` §3.3 | **RED** |
| **D2** | `sys_hclk` (`clk`) | `pad_clk_tx` (`D2D_TX_CLK_0`) | none named; the TX chain hangs off the `clk` pad | REAL finding **49**, unchanged across both runs | **TIMED** in live inputs (Option A merge); **CUT** in the shipped build | `constraints.sdc:302-320`; shipped `..._syn.sdc:804-812` | **AMBER** |
| **D3** | `clk` / `user_hsclk` (app) | `D2D_TX_WORD_CLK_0` (link) | a2l flow-control replay: `WavFIFO*` gray pointers via `WavDemetReset` 2FF (`WavFIFO.v:59`, `:65`), `WavMultibitSync*` ping-pong mailbox (`.../wlink/WavMultibitSync.v:32`, `:38`) | **WAIVED at HEAD** by `waive -du "Wlink*" -regexp` (HEAD `:45`) — and these modules **are** locally modified. **Un-waived in the worktree** (`waiver.swl:63-92`) | **CUT BY NAME** — 69 first-stage `f1_reg*/D` pins built at `constraints.sdc:491-506` and cut at `:517-518`. Payload **BOUNDED**, not cut: `set_max_delay -datapath_only` on 22 cells, `:568-577` | `constraints.sdc:427-518`, `:547-577` | **AMBER** |
| **D4** | `D2D_RX_WORD_CLK_n` (lane *n*) | `D2D_RX_WORD_CLK_0` (`out_clk`) | **deskew FIFO** `tidelink_lane_deskew_v2.sv:190`, instantiated `WavD2DGpio_v2.v:851` as `u_deskew`. Write pointer: **gray**, 2FF + `gray2bin`, `:949-972` | **NOT ANALYSED** — inside the stop_module'd controller | **TIMED**, deliberately. Zero exceptions in the live or shipped SDC name it | `constraints.sdc:356-362` `[OWNER, DO NOT LET THIS SLIDE]`; `tidelink_constraints.sdc:500-503` | **RED** |
| **D5** | `D2D_RX_WORD_CLK_n` | `D2D_RX_WORD_CLK_0` | **`sync_idx_sync1` — 6-bit BINARY multi-bit, 2FF**, `tidelink_lane_deskew_v2.sv:985-1008`. Companion validity flag `sync_seen_sync1` is synchronised **in parallel in the same `always_ff`**, not used to gate the index capture | **NOT ANALYSED** | **TIMED** (intra-group) | present in the shipping netlist: 190 refs to `sync_idx_sync1` in `build/full-20260814/outputs/nanosoc_eth_chiplet_pads_gate.v` | **RED** |
| **D6** | `D2D_RX_CLK_0` (pad) | `D2D_RX_WORDN_CLK_n` | **single-flop re-register**, not a 2FF sync: `WavD2DGpioRx_v2.v:875` (pad-clock word) → `:1051-1057` (`link_data_reg <= link_data_handoff` on `io_link_clk`) | **NOT ANALYSED** | **TIMED** (intra-group) — and this domain did not exist in STA at all until 2026-08-09 | `tidelink_constraints.sdc:290-320`; the negedge-half declaration took untimed clock pins 128 → 0 | **AMBER** |
| **D7** | lane ↔ lane | `D2D_RX_WORD_CLK_n` ↔ `_m` | none — phase-aligned by construction, all 8 share `-source` and `-divide_by` | **NOT ANALYSED** | **TIMED**, deliberately | `constraints.sdc:357-359` | **AMBER** |
| **D8** | `phy_link_rx_rx_link_clk` | `apb_clk` (`clk`) | `WavSyncPulse` (2FF demet + edge-detect flop): `local_overrides/Wlink.v:2013` `ecc_corrected_sp`, `:2021` `ecc_corrupted_sp`; downstream `WavDemetReset ff2_demet_1/_2` `:2041`, `:2047` | **WAIVED at HEAD** (`Wlink` is locally modified); un-waived in worktree | **CUT** — group 2 vs group 1 | `CDC_FINDINGS.md` MCKDMN table | **AMBER** |
| **D9** | 3 × link-domain CRC error bits | `apb_clk` | `WavDemetReset ff2_demet` `local_overrides/Wlink.v:2035` — its **input is a combinational OR of three link-domain signals**, i.e. reconvergence *before* the synchroniser | as D8 | **CUT** | RTL, `Wlink.v:2035`, `:2535` | **AMBER** |
| **D10** | `apb_clk` (`clk`) ↔ `link_rx_clk_o` | both ways | `tidelink_gpio_phy_apb_regs.sv:31` — apb→rx: 24-bit `lock_thresh` + 2-bit `noise_mode` 2FF (`:131-149`), `clear_noise` 3FF toggle+edge (`:155-173`); rx→apb: ~272 observability bits, 2FF each, **no gray** (`:179-210`) | **WAIVED, well** — 4 file-scoped rule waivers with a 30-line rationale and named tests, `tidelink/cdc/waiver.swl:412-418` | **CUT** — group 2 vs group 1 | best-documented waiver in the tree per `CDC_WAIVER_INVENTORY.md` §3.1 | **GREEN** |
| **D11** | `app_clk` | `link_rx_clk_o` | `role_locked_o` used as the RX-side **reset** (`tidelink_top.sv:1314` `.link_rx_rst_n(role_locked_o)`), declared as a reset in `cdc/tidelink_top.sgdc` | `Reset_sync02` **A4F** — adjudicated "deliberate and documented" | **CUT** | `CDC_RESET_DOMAIN_ANALYSIS.md` §5; `../design/RESET_ORDERING.md` §2 | **GREEN** |
| **D12** | `sys_fclk` | `user_ref_clk` | PRMU reset synchronisers `u_sys_hresetn_sync.rst_sync2_n`, `u_sys_poresetn_sync.rst_sync2_n` | **WAIVED** at tidelink level (`waiver.swl:294-295`, "synchronised by WavDemetReset inside Wlink"); REAL findings **32/33** at chiplet level, deliberately left unretired | **no crossing** — `user_ref_clk` is an ALIAS of `clk` | `CDC_B7_ROUND2.md` §4d; `nanosoc_eth_chiplet_chip.v:103` | **ALIAS** / AMBER for a respin |
| **D13** | `D2D_TX_WORD_CLK_0..7` | — | — | n/a | **DEFECTIVE in the shipped build**: `-source .../u_wlink/pad_clk_tx` can never resolve (sibling, not ancestor); 24 × TA-1018, ~2k TX flops timed at **0 ns source latency**, then handed to CCOpt. Corrected in the live inputs to `$WL/user_hsclk` | `tidelink_constraints.sdc:355-420`; shipped `..._syn.sdc:39` | **RED** (shipped) / GREEN (live) |

#### Notes on the D2D rows

**D1 is the archetype this register was written to find.** The far-die receive
data path is (a) waived by a loose glob at block level, (b) discarded at chiplet
level by the black-box rule, and (c) cut in STA by group membership. Three
mechanisms, each of which individually looks like "handled by the other two". The
interface also has the project's only known marginal-eye data-drop failure mode.
`CDC_WAIVER_INVENTORY.md` §3.1 already marks the waiver **NARROW** for being
a loose glob; that recommendation is unactioned and is the cheapest close-out here.

**D4/D5 are the intra-RX-group pair the constraints deliberately left timed**, and
the two halves have opposite verdicts, which is why they are separate rows.
`constraints.sdc:356-362` says in terms:

> `word<->capture (D2D_RX_CLK_0 -> D2D_RX_WORD_CLK_n) across u_deskew, which is
> an async FIFO. This one probably DOES want a narrow set_false_path on the
> FIFO's data path only`

and `tidelink_constraints.sdc:500-503` repeats it as a FOLLOW-UP. Neither has been
actioned; verified by grep, **no exception in the live or the shipped SDC names
`u_deskew`**. The write pointer itself is safe — V2 made it gray (`:949-972`,
"Finding #2 fix") — but `sync_idx_sync1` is a 6-bit **binary** value crossing on
the same boundary, in the shipping netlist, and its `sync_seen` companion is
2FF'd alongside it rather than gating it.

> **A DUPLICATE-COPY TRAP, RECORDED BECAUSE IT ALMOST LANDED IN THIS DOCUMENT.**
> `tidelink/src/rtl/local_overrides/tidelink_lane_deskew.sv:214-233` (V1) crosses
> `wr_ptr` as a **plain binary counter**, 2FF, justified on a mesochronous
> argument at `:214-219`. That is a materially worse structure than V2's gray
> pointer — and it is **not what the ASIC builds**.
> `tidelink/flists/tidelink_top_full_asic_v2.flist:157` binds
> `tidelink_lane_deskew_v2.sv`, and `:182` binds `WavD2DGpioRx_v2.v`. Cite the
> V2 files for anything about the shipping chip.

**D3 is where STA is ahead of CDC.** The 69 named synchroniser anchors and the 22
`set_max_delay -datapath_only` bounds are a more precise statement about the a2l
mailbox than anything on the CDC side — and they were added on 2026-08-17, i.e.
*after* the shipping database was built, which had no named cut at all here.

> **A BUILD-BINDING DISCREPANCY worth an owner's answer before signoff.**
> The two `_18` local overrides are not bound together.
> `tidelink/flists/tidelink_top_full_asic_v2.flist:238` binds
> `src/rtl/local_overrides/WavMultibitSync_18.v` — the patched copy, which adds
> two new 2-flop reset synchronisers (`:75-84`) and retargets four sequential
> blocks and both demet reset pins onto coherent resets, fixing a
> pointer-parity reset deadlock. But `:263` binds the **vendor**
> `deps/axi-chiplet-controller/logical/wlink/WlinkGenericFCReplayAddrSync_18.v`,
> not the local override that adds the companion `raddr` reset-skew gate
> (`local_overrides/WlinkGenericFCReplayAddrSync_18.v:86-97`, `:115`). Both
> ASIC flists and `tidelink_fpga.flist` do this; only `tidelink_fpga_v2.flist`
> and `tidelink_a2l_replay_cdc.flist` bind both. Either the mailbox fix
> subsumes the `raddr` gate or the ASIC ships half a fix. Nobody has said which.

**A note on `WavDemetReset` in this flow.** Every `WavDemetReset*` cell carries an
`` `ifdef ASIC_TSMC65 `` arm that hard-instances `SDFCNQD1` pairs with **two
`BUFFD1` hold-fix buffers between f1.Q and f2.D** (`.../wlink/WavDemetReset.v:14-26`).
`ASIC_TSMC65` is **not** defined in this flow — it belongs to TideLink's Fusion
Compiler flow — so this design synthesises the behavioural branch and gets
**no hold-fix buffers between the two synchroniser stages**; the f1→f2 hold
margin is whatever CTS and hold repair leave. Confirmed from the netlist:
`u_f1` appears zero times, `f1_reg`/`f2_reg` 282 times each
(`constraints.sdc:404-412`). Not a defect — but it is the reason the 69 anchors
target `f1_reg*/D` and it should be stated wherever the vendor cell is called
"pre-verified".

**Two ports have no clock object anywhere in the flow.**
`tidelink/cdc/axi_chiplet_controller.sgdc` records `pad_clk_tx` as having no
clock object and `pad_tx` therefore left undeclared, as explicit **OPEN** items.
On the STA side `pad_clk_tx` *is* declared (`D2D_TX_CLK_0`,
`tidelink_constraints.sdc:177`). This is a one-line CDC fix that would let the
tool see row D2 properly.

### 3.2 Ethernet MAC + PTP

> `rmii_ref_clk` has its own pad (`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:416-421`),
> so `mii_rx_clk`/`mii_tx_clk` are the **only genuinely asynchronous domain on
> this die apart from D2D and SWD**. Everything in this subsystem that crosses to
> or from them is a real crossing on real silicon. Everything that crosses to
> `rtc_clk` is not — see row E11.

| # | Source domain | Dest domain | Synchroniser (RTL file:line) | CDC verdict | STA exception | Evidence | Status |
|---|---|---|---|---|---|---|---|
| **E1** | `sys_fclk` (`clk`) | `mrx_clk` / `mtx_clk` | **NONE for `r_LoopBck`** — combinational into the RX datapath: `$IP_LIBRARY_ROOT/ip_library/OpenCores-EthMAC/rtl/verilog/eth_top.v:598` `assign MRxDV_Lb = r_LoopBck? mtxen_pad_o : mrxdv_pad_i & RxEnSync;`. `RxEnSync` gets **one** flop, gated on `~mrxdv_pad_i` (`eth_top.v:731-739`) | **WAIVED at block level** — `eth_top` in `ethernet-subsystem-ahb/cdc/waiver.swl:118-139` as `"third-party-IP"`. **REAL, 26 crossings** at chiplet level — the largest single block in the run | **CUT** — group 3 vs group 1. Shipped build additionally `set_false_path -from clk -to {rmii_ref_clk mii_rx_clk mii_tx_clk}` (`..._syn.sdc:837`) | `CDC_B7_ROUND2.md` §4a; firmware toggles TXEN/RXEN/FULLD/LOOPBCK at runtime (`firmware/apps/eth_netapp/driver/ethmac.h:114-152`) | **RED** |
| **E2** | `sys_fclk` (`clk`) | `mrx_clk` / `mtx_clk` | **NONE** — raw async clear. `ha1588_patches/ha1588.v:107-116` registers a **one-fabric-cycle pulse** onto `rx_q_rst_combined`; `tsu.v:644-653` wires it to `ptp_queue.aclr`; `ptp_queue.v:48`, `:102` use it as `posedge aclr` on MII-clocked pointers | **WAIVED at block level** — `tsu`, `ptp_queue`, `ha1588`, `reg` all in `ethernet-subsystem-ahb/cdc/waiver.swl:150-156` as `"third-party-IP"`, though sourced from `ha1588_patches/` (`ethernet-mac-ahb/flist/ha1588_apb.flist:3-8`). Surfaces at chiplet level only as 2 of the 5 untriaged `Reset_sync02` | **CUT** — recovery/removal from fabric into MII is not timed | `CDC_RESET_DOMAIN_ANALYSIS.md` §4; RTL declares it: `ha1588.v:104-106` names `Reset_sync02` | **RED** |
| **E3** | `sys_fclk` | `mrx_clk` / `mtx_clk` | **NONE** — `reg.v:167`,`:173` write; `:244`,`:249` → `ha1588.v:183`,`:201` → `tsu.v:32` → `ptp_parser.v:226,229`. No load strobe, nothing for a qualifier to attach to | **WAIVED at block level** (`reg` as `"third-party-IP"`). **REAL** findings 28/29 at chiplet level; firmware rewrites both mid-run | **CUT** — group 3 vs group 1 | `CDC_B7_ROUND2.md` §4a; `ptp_parser.v:41` carries a stale comment calling it "quasi-static" | **RED** |
| **E4** | `sys_fclk` | `mrx_clk` / `mtx_clk` | 2-FF / 3-FF chains throughout `ethmac_patches/eth_wishbone.v` (e.g. `TxStartFrm_sync1/2` `:1248-1279`, `WriteRxDataToFifoSync1/2/3` `:2118-2146`, `RxAbortSync1..4` `:2299-2345`) | **WAIVED at block level** — `eth_wishbone` at `ethernet-subsystem-ahb/cdc/waiver.swl:140` and `ethernet-mac-ahb/cdc/waiver.swl:44` as `"third-party-IP"`, **but it is sourced from `src/rtl/ethmac_patches/`** (`ethmac_ahb_rmii.flist:27-28`). Chiplet level: findings 17/19/20/21/39/40/41 classed VENDOR | **CUT** | `CDC_WAIVER_INVENTORY.md` §2.2 | **RED** |
| **E5** | `mii_rx_clk` | `sys_fclk` (`clk`) | **model row** — `eth_rx_cksum.v`: gray write pointer + 2-FF (`:481`,`:489`), overflow toggle 3-FF (`:482`,`:490-491`), push toggle 3-FF (`:512-520`), async FIFO memory `:405` | **CLEAN** — not among the 50 findings; recognised as `Ac_sync01/02` | **CUT** — group. Shipped build also cut each sync flop by name (`..._syn.sdc:228`); those named cuts are retired in the live set (`ethernet_constraints.sdc:533-536`) | `CDC_B7_BASELINE.md` §5 | **GREEN** |
| **E6** | `mii_rx_clk` | `sys_fclk` | `last_push_flags_mrx[7:0]` latched on the same edge that flips `push_tog_mrx` (`eth_rx_cksum.v:379-380`, `:393-394`); consumed only after the toggle resyncs (`:579`, `:587-612`) | **CLEAN** | **EXTINGUISHED MCP.** The 2/1 multicycle is retired at `ethernet_constraints.sdc:554-555`; the group makes it a false path. The shipped build carries the MCP **live** at `..._syn.sdc:790`,`:797` alongside the group and the clock-to-clock cut — three mechanisms, false path wins | `ethernet_constraints.sdc:443-465`, `:543-555` | **GREEN** (silicon) / AMBER (bookkeeping) |
| **E7** | `mtx_clk` / `mrx_clk` | `sys_fclk` | TX/RX **status bundles** cross with **no per-bit synchroniser**, qualified by an already-synchronised valid: `eth_macstatus.v:357-405` → `ethmac_patches/eth_wishbone.v:1388`,`:1390`, gated by `TxDonePulse`/`TxAbortPulse`/`TxRetryPulse` (`:1395-1397`) and `RxStatusWriteLatched_sync2` | **WAIVED at block level** (`eth_macstatus` as `"third-party-IP"`); chiplet level: findings 6/7 classed LEGIT | **CUT** | agent RTL read, corroborated by `CDC_B7_BASELINE.md` §6F | **AMBER** |
| **E8** | `sys_fclk` (`Clk`) | `mtx_clk` (`TxClk`) | **VENDOR DEFECT — effectively a single flop.** `$IP_LIBRARY_ROOT/ip_library/OpenCores-EthMAC/rtl/verilog/eth_registers.v:1023` reads `ResetTxCIrq_sync2 <= SetTxCIrq_sync1;` — it taps a `Clk`-domain flop instead of `ResetTxCIrq_sync1`. `ResetTxCIrq_sync2` is the only clear term for `SetTxCIrq_txclk` (`:973`). The RxC twin at `:1086` is correct | **WAIVED at block level**; chiplet level findings 22/23 classed LEGIT — i.e. **the tool was told this is a synchroniser chain and it is not** | **CUT** | RTL read this session; **not previously recorded anywhere in this repo** | **RED** |
| **E9** | `RMII_MDIO` pad | `sys_fclk` | **single flop, no synchroniser** — `$IP_LIBRARY_ROOT/ip_library/OpenCores-EthMAC/rtl/verilog/eth_shiftreg.v:128` | **not reported** — the pad is declared fabric-domain (`cdc/nanosoc_eth_chiplet.sgdc:485` `md_pad_i -clock sys_hclk`), so no crossing exists to report | **CUT** — `ethernet_constraints.sdc:334-336` | `ethernet_constraints.sdc` WARNING S2 (`:355-362`) declares the exposure in terms | **AMBER** |
| **E10** | `rmii_ref_clk` | `mii_rx_clk` / `mii_tx_clk` | none needed — `mrx_clk`/`mtx_clk` are ÷2 toggle flops off `rmii_ref_clk` (`rmii_to_mii.v:277-283`, `:320-326`) | **CLEAN** — one `rmii_domain`; the run reports **zero** `mtx↔mrx` crossings, which confirms the domain choice | **TIMED** (intra-group) | `CDC_B7_BASELINE.md` §4c | **GREEN** |
| **E11** | `sys_fclk` | `rtc_clk` | 3-FF + edge-detect load strobes: `ha1588_patches/reg.v:266-278` (`time_ld`), `:280-292` (`period_ld`), `:294-306` (`adj_ld`); declared as object-scoped qualifiers in CDC round 2 and accepted | **18 crossings**, moved from `Ac_unsync02` to `Ac_sync02` by the round-2 qualifiers | **no crossing** — `rtc_clk` is an ALIAS of `clk` (`nanosoc_eth_chiplet_chip.v:102`). Timed as ordinary same-clock paths | `CDC_B7_ROUND2.md` §3d; `CDC_RESET_DOMAIN_ANALYSIS.md` §2 | **ALIAS** |
| **E12** | `rtc_clk` | `sys_fclk` | **86 bits, no synchroniser** — `reg.v:323-331` latches `time_reg_ns_int[37:0]`/`time_reg_sec_int[47:0]` in the rtc domain on `time_rd_ack`, read back in the `clk`-domain register mux at `:202-205`. Software-sequenced (write TIME_RD, then read) | 2 crossings; findings 8/34 classed LEGIT | **no crossing** — ALIAS | agent RTL read; largest data crossing in HA1588 | **ALIAS** / AMBER for a respin |
| **E13** | `sys_fclk` | `rtc_clk` | `reg_2c` (`period_adj`) is consumed on a counter terminal count, not on a load strobe: `rtc.v:65-68`. The `adj_ld` strobe opens a window but does not gate the sample | finding **44**, declined — genuine software contract | **no crossing** — ALIAS | `CDC_B7_ROUND2.md` §4c | **ALIAS** |
| **E14** | `mii_rx/tx_clk` | `sys_fclk` | PTP event toggle CDC, 3-FF + edge: `ethmac_subsystem_apb.v:576-592` (RX), `:595-611` (TX); reset bridges `:495-504`, `:506-515` | **CLEAN** — SoC-Labs-authored, recognised by name | **CUT**; shipped build additionally named `u_rx_ptp_det/ptp_event_reg` (`..._syn.sdc:113`), retired in the live set (`ethernet_constraints.sdc:541`) | agent RTL read | **GREEN** |
| **E15** | `sys_hclk` | `rmii_ref_clk` | **none — and none needed.** `rmii_mode_speed` is **hard-tied to `1'b1`** at `nanosoc-multicore-system/build_soc/rtl/nanosoc_multicore_soc.sv:923` (`u_network_core`) | n/a | n/a | verified this session | **GREEN (tie-off)** |

#### Notes on the Ethernet rows

**E1, E2, E3, E4 are all in the same 152 blanket waivers.** Every one of them is
`waive -rule "*" -du {X}` — *all rules, whole design unit* — carrying the single
justification string `"third-party-IP"`, and in E2/E4's case that string is
**factually false**: the units are sourced from `ha1588_patches/` and
`ethmac_patches/`. This is the §2.2 finding of `CDC_WAIVER_INVENTORY.md`,
still entirely unactioned, and it is the direct counterpart of the tidelink
waiver fix recorded in §2.3 above. **The Ethernet subsystem is now the tree's
largest blanket-waiver blind spot, and it sits on the one genuinely asynchronous
non-D2D domain on the die.**

**E8 is new.** No document in this repo records it. The chiplet CDC run classed
findings 22/23 as "LEGIT — synchroniser chains flagged on their own stages"
(`CDC_B7_BASELINE.md` §6G), which is the correct classification *for the
structure the tool inferred* — a `sync1`/`sync2` pair. The RTL does not implement
that pair. It is a vendor defect in unmodified OpenCores RTL, it is inside a
blanket `-du` waiver at block level, and STA cuts the clock pair, so all three
lenses agree it is fine and none of them looked. Severity is bounded — a
metastable `ResetTxCIrq_sync2` costs at most a spurious or missed TxC interrupt
edge — but it should be recorded rather than discovered.

> **ONE AGENT-REPORTED FINDING REFUTED, recorded so it is not re-raised.** A
> structural search flagged `rmii_mode_speed` (`ethernet_ss_ahb_rmii.sv:121` →
> `rmii_to_mii.v:71`, used at `:145`,`:152`) as an unsynchronised, unwaived
> `sys_hclk → rmii_ref_clk` crossing. It is not: the port is tied to `1'b1` at
> `nanosoc_multicore_soc.sv:923`. `tick` (`rmii_to_mii.v:153`) is therefore a
> constant and the 10 Mbps divider is dead logic on this die. **Row E15, GREEN.**
> The corollary is worth its own line: **10 Mbps RMII is not reachable on this
> silicon.**

**Two RTL comments overstate their own structures** and should not be quoted as
evidence: `rmii_to_mii.v:36` claims an "8-stage" reset shift register where the
implementation is 4 flops (`:119-129`), and `:31-32` claims "two-stage RX input
synchronisation" where `rmii_crs_dv` gets exactly one capture flop (`:162`) and
`rmii_rxd`'s second stage is tick-gated (`:176-182`). Neither is a defect — the
RMII bus is source-synchronous and timed (`ethernet_constraints.sdc:67-68`) — but
a reader taking the comments at face value would mis-classify the interface as an
async CDC that is already double-synchronised.

### 3.3 QSPI

| # | Source domain | Dest domain | Synchroniser (RTL file:line) | CDC verdict | STA exception | Evidence | Status |
|---|---|---|---|---|---|---|---|
| **Q1** | `PCLK`/`HCLK` | `QSPI_SCLK_i` | **single-flop latch, not 2-FF** — `qspi_controller.sv:161-169` `_latched` regs loaded at IDLE→OP (`:183-233`), behind a 2-FF meta+sync pair (`:127-159`) | **WAIVED at block level** — 9 of the 19 `cdc_false_path` (`ahb_qspi/cdc/top_ahb_qspi.sgdc:150-160`). **0 crossings at chiplet level**: QSPI proven not an independent domain (`qspi_clock_div.v:10,13,19,23` — both mux arms are HCLK) | **TIMED** — `QSPI_SCLK` is a `create_generated_clock` off `CLK` (`qspi_constraints.sdc:84`) in group 1 | `CDC_B7_ROUND2.md` §3b; `ahb_qspi/docs/cdc_signoff_status.md:37-65` | **AMBER** |
| **Q2** | `HCLK` | `QSPI_SCLK_i` | **NO latch at all** — the SGDC's own **TODO** at `top_ahb_qspi.sgdc:164-165`: "add explicit latching regs for ADDR and WDATA". `addr_code` / `QSPI_WDATA_reg` loaded on a negedge block (`qspi_controller.sv:554`,`:556`) | **WAIVED** — `cdc_false_path` at `top_ahb_qspi.sgdc:166-170`. 0 at chiplet level | **TIMED** | QSPI six rows #4/#5/#6, all **OWNER** | **AMBER** |
| **Q3** | `HCLK` | `PCLKG` | ARM CG092 `cdc_capt_sync` / `p_flash_cache_f0_capt_sync` (RTL outside this repo: `$ARM_IP_LIBRARY_PATH/CG092/.../logical/models/cells/generic/`) | **NOT DECLARED** — `top_ahb_qspi.sgdc:52-67` declares only `HCLK`, `PCLK`, `QSPI_SCLK_i`. **`PCLKG` is not a domain in that file**, so the CG092's own crossing is not represented. The sync cells are separately `-du` waived (`ahb_qspi/cdc/waiver.swl:48-51`) | **TIMED** — both derive from `sys_hclk` (`qspi_flash_ahb.v:32-35`, `:102-105`) | agent RTL read; `cache_subsystem.v:95`,`:98` | **AMBER** |

#### Notes on the QSPI rows

**Three levels disagree about mechanism and agree about outcome.** The block-level
SGDC treats HCLK↔QSPI_SCLK as a metastability risk mitigated by protocol and
19 `cdc_false_path`s; the chiplet-level run **proved** it is not an independent
oscillator, so no metastability window can exist; STA has always timed it as a
generated clock. All three end up safe, by different arguments, and the block
level has never been told the chiplet-level proof.

**But the residual risk is real and no lens expresses it.** Because the domains
are synchronous, the exposure is not metastability — it is the **latch-enable
window** and the software two-write-hold convention that the QSPI six depend on
(`ahb_qspi/docs/cdc_signoff_status.md:54-56`), which is unenforced in hardware.
An STA `set_max_delay` cannot express it, a `cdc_false_path` positively hides it,
and the advanced-formal rules that could check it **hang** and have never run on
this block (`cdc_signoff_status.md:5-12`). Row #1 of the six — "qualifier not
found" — is still the highest-risk of them and still **OWNER**.

`ahb_qspi/lint/hal.tcl:128` also carries a blanket `-nocheck CLKDMN`, so the one
block in the tree that deliberately crosses three declared clocks has the
unsynchronised-crossing rule turned off in its own unit lint.

### 3.4 I2C

There is **no I2C RTL outside TideLink** — an exhaustive filename search over
`nanosoc-multicore-system/`, `src/rtl/` and `tidechart/` returns nothing. The
chiplet top only passes the pads through (`src/rtl/nanosoc_eth_chiplet.sv:161-166`,
`:949-955`). So the "synchronised inside the chiplet controller" claim made by
two waivers is TideLink's to substantiate, and TideLink black-boxes the module
that would substantiate it.

| # | Source domain | Dest domain | Synchroniser (RTL file:line) | CDC verdict | STA exception | Evidence | Status |
|---|---|---|---|---|---|---|---|
| **I1** | `I2C_SCL` / `I2C_SDA` pads (peer die / peer clock) | `apb_clk` (`clk`) | **master: single flop, no second stage** — `tidelink/.../i2c/rtl/i2c_master.v:862-863`, combinational edge detect `:290-291`. **slave: 4-deep filter** — `i2c_slave.v:199-200`, `:468` | **DOUBLE-WAIVED, one justification factually wrong.** `tidelink/cdc/waiver.swl:292-293` waives `Ac_unsync01` on `*i2c_sda_i*`/`*i2c_scl_i*` (correct and tightly scoped) **and** `tidelink/cdc/tidelink_top.sgdc:129-130` declares both `quasi_static` — which is false: I2C lines toggle continuously during a transfer. At chiplet level findings 2-5 were retired as `abstract_port` setup artefacts | **CUT** — `set_false_path` both directions on both ports, `i2c_constraints.sdc:329-332` | `CDC_WAIVER_INVENTORY.md` §3.8; `i2c_constraints.sdc` WARNING 5 at `:439-450` | **AMBER** |

**Why AMBER and not RED.** Every lens is silent, which is the RED pattern — but
unusually, the *silence is documented*. `i2c_constraints.sdc:439-450` states the
single-flop master sample explicitly, says the false path is what makes it
invisible to STA, and gives the mitigating argument in numbers: 500:1
oversampling (`:118-124`), so a metastable sample costs at most one `apb_clk` of
edge-detection jitter out of 500, and in master mode the incoming edge is mostly
our own SCL echoed back. That argument is sound and is the reason this is not a
top-5 row. What is wrong is the **bookkeeping**: `quasi_static` asserts a
guarantee the signal does not provide, and it is redundant with a waiver that
already models the signal correctly. `CDC_WAIVER_INVENTORY.md` checklist
item 13 recommends dropping it; unactioned.

### 3.5 SWD / debug

| # | Source domain | Dest domain | Synchroniser (RTL file:line) | CDC verdict | STA exception | Evidence | Status |
|---|---|---|---|---|---|---|---|
| **S1** | `SWDIO` pad | `swclktck` | **3 flops, all in `swclktck`** — `$ARM_IP_LIBRARY_PATH/.../cxdapswjdp/verilog/cxdapswjdp_swj_watcher.v:87-93` (first flop) + `cxdapswjdp_dp_sync` (2 more, `.../models/cells/generic/cxdapswjdp_dp_sync.v:41`, `:56`) | not a domain crossing — pad input synchroniser | **TIMED** — `set_input_delay -clock swdclk 0.1 [get_ports SWDIO]` (`constraints.sdc:265`) | agent RTL read | **GREEN** |
| **S2** | `dap_swclktck` | `sys_fclk` | **control synchronised, data not — a textbook qualified crossing.** `busreq` through `cx_en_sync` (`cxdapswjdp_dp_apb_sync.v:78-86`); `ap_sel`/`ap_bank_sel`/`ibuswdata` cross raw, gated in the destination FSM (`cxdapswjdp_sw_dp_apb_if.v:142-145`, `:335-347`); ARM's own OVL asserts the stability property (`:386-400`) | **33 crossings, NOT RETIRED.** The qualifier declaration is correct and SpyGlass **rejected** it under `-allow_merged_qualifier: strict` — 2 crossings changed reason, 0 retired. Separately, the SoC block run waives ARM's own synchroniser cells (`ethernet-subsystem-ahb/cdc/waiver.swl:82-88`, `:92-109`), so the DAP↔core boundary is unexamined there too | **CUT** — `swdclk` in group 4. Shipped build additionally MCP 2/1 (`..._syn.sdc:237-240`) + `set_false_path -hold` (`:112`), all extinguished; retired in the live set under `[C5]` (`constraints.sdc:97-165`) | `CDC_B7_ROUND2.md` §3c | **AMBER** |
| **S3** | `swclktck` | `dapclk` | `cxdapswjdp_dapclk.v:99-105` forward, `cxdapswjdp_swclktck.v:252` return | as S2 | **`dapclk` IS `HCLK`** — `nanosoc-multicore-system/coresight_soc400/rtl/nanosoc_dap_ss.v:37-38`, `:123`, `:192`, with `.dapclken(1'b1)`. So S2 and S3 are the same crossing under two names, and everything downstream (AHB-AP, `nanosoc_dap_ahb_xlate/arb/timeout`, `nanosoc_dbg_ahb_bridge`) is single-domain HCLK | agent RTL read | **AMBER** |

**S2 is the largest unproven block in the design: 33 crossings, no tool
confirmation, no STA backstop.** The evidence is as strong as RTL evidence gets —
ARM implements the handshake, gates the destination unconditionally on the
synchronised `busreq`, and ships assertions stating the data-stability property
verbatim. But `CDC_B7_ROUND2.md` §3c is explicit that the route to closing
them is the functional `cdc/cdc_verify` goal or a formal check, **not** a larger
`cdc_qualifier_depth` — and neither has been run. Note the honesty of that
round: raising the global knob would have retired these 33 *and* silently
retired crossings on 18 self-inferred qualifiers nobody has examined.

### 3.6 TideChart

| # | Source domain | Dest domain | Synchroniser | CDC verdict | STA exception | Evidence | Status |
|---|---|---|---|---|---|---|---|
| **T1** | — | — | none — single clock | **CLEAN, but the evidence is partly self-referential.** `tidechart/cdc/waiver.swl:9` waives `Setup_clockreset01`, which is the check that would report a missing clock/reset declaration; the file's own claim that CDC "reports 0 unsynchronized crossings" is partly a consequence of that waiver | `clk` — group 1; nothing TideChart-specific | see below | **GREEN** |

**The single-clock claim is independently verified, by RTL.** All 11 module
declarations across the nine files in `tidechart/src/rtl/` have exactly one clock
input and no module has two: `tidechart_ahb_master.sv:28`/`:32`,
`tidechart_apb_regs.sv:17`/`:39`, `tidechart_election_fsm.sv:31`/`:45`,
`tidechart_puf_sampler.sv:21`/`:26`, `tidechart_link_state_agent.sv:32`/`:41`,
`tidechart_controller.sv:20`/`:38`, `:699`/`:706`, `:953`/`:954`,
`tidechart_crossbar.sv:20`/`:26`, `tidechart_enum_fsm.sv:143`/`:150`,
`tidechart_route_table.sv:19`/`:24`. Every sequential block is
`always_ff @(posedge clk|hclk or negedge resetn|hresetn)`; there is no `negedge
clk`, no second clock, and no gray/toggle/meta structure in the tree. The shim
(`src/rtl/tidechart_shim.sv:70`, `:185`) passes one clock straight through.

**But no SpyGlass run backs it in this checkout.**
`tidechart/cdc/tidechart_controller_cdc_summary.rpt` reads
`(no report files found — run 'make cdc' first)`. The verdict above is by RTL
inspection only, and should be recorded as such rather than as a tool result.
`CDC_WAIVER_INVENTORY.md` checklist item 14 — declare `clk`/`resetn`
properly in `tidechart.sgdc` and delete the waiver — remains the right fix and
would make the run's zero mean something.

### 3.7 Reset domains

| # | Source domain | Dest domain | Synchroniser (RTL file:line) | CDC verdict | STA exception | Evidence | Status |
|---|---|---|---|---|---|---|---|
| **R1** | `sys_fclk` (`sys_hresetn_eff`) | `mrx_clk` / `mtx_clk` | **none, by design** — the MAC uses the fabric reset as an **async** reset throughout the MII domains: **122 `posedge M{R,T}xClk or posedge rst` blocks / 149 reg targets** across the compiled MAC set | finding **30** (`mrx` half, 2 crossings) + `Reset_sync02` **A4B** | **CUT** — recovery/removal not timed | `CDC_RESET_DOMAIN_ANALYSIS.md` §3.1 | **GREEN with rationale — see below** |
| **R2** | `sys_fclk` | `mrx_clk` / `mtx_clk` | **none** — the PTP queue `aclr`. See row **E2** | `Reset_sync02` **A4D/A4E** | **CUT** | `CDC_RESET_DOMAIN_ANALYSIS.md` §4 | **RED** |
| **R3** | `sys_fclk` | `user_ref_clk` | PRMU `rst_sync2_n`. See row **D12** | findings 32/33 | **no crossing** — ALIAS | ibid. §2 | **ALIAS** |
| **R4** | `sys_fclk` | `rtc_clk` | `reg.v:252-264` `rtc_rst_s1/s2/s3`; the 17 `rtc_clk` destinations of finding 30 are **synchronous** resets (`always @(posedge rtc_clk_in) if (rst)`), not async clears | 17 of finding 30's 19 crossings | **no crossing** — ALIAS | ibid. §2 | **ALIAS** |
| **R5** | `sys_hresetn` | `u_d2d_decode.dph_code[0]` | — | `Ar_unsync01` × 1, **repo-owned RTL** — proven by measurement to be an SGDC declaration artefact (`cdc/nanosoc_eth_chiplet.sgdc:269-270` declare resets the tool should have propagated) | n/a | ibid. §6 | **GREEN (measured)** |
| **R6** | `HCLK` | `FCLK` | **none** — `nanosoc_reset_ctrl.v` samples HCLK-domain register writes directly into FCLK flops: `:210-215`, `:271-285`, `:288-301`, `:325-330`, `:343-348`. The comment at `:205-209` acknowledges the arrangement | **not reported** — HCLK and FCLK are one `sys_fclk_domain` in the SGDC | **TIMED** as one clock | agent RTL read; instance `nanosoc_multicore_soc.sv:1359-1391` | **GREEN (same net)** |

**R1 is the reset row most likely to be misread, in both directions.** The
exposure is real as stated and STA gives no backstop. It is nevertheless safe,
and the mechanism is **structural, not a timing margin**: the same net that
resets the MAC also resets the module that *generates the MAC's clocks*
(`ethernet_ss_ahb_rmii.sv:490`, `:556`), and `rmii_to_mii.v:119-129`, `:277-283`,
`:320-326` hold `mrx_clk`/`mtx_clk` at `1'b0` until `rstn_sync` rises on the 4th
`rmii_ref_clk` edge after release. The MAC's async reset is therefore stably
deasserted for ≥5 `rmii_ref_clk` periods — ≥100 ns at 50 MHz — **before any MII
flop sees a clock edge at all**. No clock edge, no recovery/removal window.

Two things follow that both belong in a signoff file and are in neither:
1. **The argument is invisible to both tools.** SpyGlass has no rule for a
   clock-gating interlock; STA cannot see it because the pair is cut. It will be
   re-found and re-litigated by every future run. `CDC_RESET_DOMAIN_ANALYSIS.md`
   §7 R3 recommends recording it as a written waiver — unactioned.
2. **It has been verified by reading RTL, not by simulation.** The directed test —
   assert `sys_hresetn` mid-traffic, release, check no MII edge falls in the
   removal window — is short, is a cocotb test, and nobody has written it.
   **R2 is precisely the case where this argument does not hold**, because the
   queue reset is a software-issued one-cycle pulse arriving while the MII clocks
   are already free-running.

**There is no canonical reset-synchroniser cell on the non-TideLink side.**
Eleven distinct hand-rolled bridges do the job: `soc_glue_reset_sync.sv:30-51`
(STAGES=3), `ethernet_ss_ahb_rmii.sv:347-353` and `:356-362`,
`ethmac_subsystem_apb.v:495-504` and `:506-515`, `tsu.v:110-119` and `:121-130`,
`ha1588.v:76-85`, `ha1588_servo.sv:115-120`, `rmii_to_mii.v:119-129`,
`qspi_controller.sv:103-114`. `WavDemetReset` appears **zero** times outside
`tidelink/`. That matters for reconciliation because the STA mechanism that cuts
synchroniser first stages by name (`constraints.sdc:491-518`) keys on the
TideLink cell's `f1_reg` naming and **covers none of these eleven**. They are
cut by group membership instead — which is correct today, and is the thing that
silently stops being correct if a group is ever split.

---

## 4. The rows that matter — ranked

Ranked by *how little anyone has looked*, not by severity alone. A severe defect
that three people have argued about is safer than a mild one nobody has read.

### 4.1 Category 1 — CDC waived AND STA cut. Nobody has ever checked these.

| Rank | Row | Why it is first |
|---:|---|---|
| **1** | **E2 — PTP timestamp-queue async clear** | The only genuine, **software-reachable** reset exposure in the design, and all three lenses are blind. CDC: waived at block level as `"third-party-IP"` when the unit is locally patched. STA: recovery/removal into the MII domains is cut by the group. RTL: the crossing is declared, by rule name, in a comment nobody actioned (`ha1588.v:104-106`). And the interlock that makes every *other* fabric→MII reset safe (R1) **does not cover this one**, because `aclr` is a one-fabric-cycle pulse (10 ns) arriving asynchronously at a free-running 25 MHz clock (40 ns) — narrower than the destination period, so it may not straddle an edge, and its removal edge has no relationship to `mrx_clk`. Blast radius 40 flops (`wr_bin`, `wr_gray`, `rd_gray_wr1/2`, ×2 queues); a metastable gray pointer breaks the adjacency invariant `wrfull`/`rdempty` depend on. Shipped firmware pulses it deliberately (`ha1588.c:131-137`, `:148-152`, called from three apps). Severity is bounded — degraded PTP timestamp quality, not a bus wedge — but it is reachable today, and a **zero-RTL mitigation exists**: only reset the queues with `MODER.RXEN/TXEN` clear. |
| **2** | **D1 — D2D `pad_rx` → fabric** | The receive datapath of the die-to-die link, on the one interface with a known marginal-eye data-drop failure mode. Waived by a **loose glob** at block level (`tidelink/cdc/waiver.swl:296` `-msg "*pad_rx*"`), discarded at chiplet level by `-check_multiclock_bbox=yes` on an *inferred* virtual domain, and cut in STA by the RX/system group split. Three independent suppressions, each of which reads as if the other two were doing the work. `CDC_WAIVER_INVENTORY.md` §3.1 already marks the glob **NARROW**; nobody has scoped it. |
| **3** | **E1 — EthMAC `MODER` → `mrx_clk`, especially `r_LoopBck`** | 26 crossings, the **largest real finding in the design**, and one declaration away from having been invisible — the CDC baseline proposed `quasi_static` on `MODER` and round 2 refuted it from firmware. `r_LoopBck` reaches the RX datapath **combinationally, with no synchroniser at all** (`eth_top.v:598`), and firmware toggles it at runtime. Waived at block level as `"third-party-IP"`, cut in STA by the rmii group. |
| **4** | **E4 — `eth_wishbone` (patched) WB↔MII** | The MAC's DMA/descriptor engine — the busiest crossing in the block — excluded from CDC by a `"third-party-IP"` justification that is **factually wrong for this build** (`ethmac_ahb_rmii.flist:27-28` sources it from `src/rtl/ethmac_patches/`), and cut in STA. It contains ~15 distinct synchroniser chains; none has been examined by a tool. |
| **5** | **E3 — HA1588 `reg_44` / `reg_64` → MII** | Only 2 crossings, and it ranks because it is the **cheapest real fix in the set**: no load strobe, no synchroniser, nothing for a qualifier to attach to, and firmware rewrites both mid-run to change which PTP message IDs get timestamped. Waived at block level, cut in STA. `ptp_parser.v:41` even carries a stale comment calling the crossing "quasi-static" — the exact assumption the firmware violates. |

### 4.2 Category 2 — crossings that STA times but no CDC tool has ever seen

These are more dangerous than they look, because a clean timing report on them
reads as positive evidence.

| Row | What | Why it matters |
|---|---|---|
| **D4** | deskew FIFO, `D2D_RX_CLK_0`/lane word clocks → `out_clk` | An **async FIFO timed as if it were synchronous**. Both constraint files flag it as unfinished business — `constraints.sdc:356-362` `[OWNER, DO NOT LET THIS SLIDE]` and `tidelink_constraints.sdc:500-503` — and neither has been actioned. Verified by grep: **no exception in the live or shipped SDC names `u_deskew`.** The write pointer is gray and safe (V2, `:949-972`); the danger is that timing closure on this boundary will be read as CDC assurance. |
| **D5** | `sync_idx_sync1`, 6-bit **binary** multi-bit, 2FF | In the shipping gate netlist (190 refs). Its companion validity flag `sync_seen_sync1` is synchronised **in parallel in the same `always_ff`** rather than gating the index capture, so the index can be sampled mid-change. Never CDC-analysed; timed intra-group by STA. |
| **D6** | `link_data_reg` — **single-flop** re-register, pad clock → word clock | The 128-bit recovered RX word. Sound only because the two clocks are ÷16-related and phase-coherent by construction — a **clock-tree obligation, not a synchroniser**. This whole domain was invisible to STA until 2026-08-09 (16,653 untimed clock pins). |
| **E8** | `eth_registers.v:1023` vendor defect | The TxC-IRQ clear back-sync taps a `Clk`-domain flop instead of its own first stage, making it a single-flop capture into `TxClk`. Classed LEGIT by the chiplet run — correctly, *for the structure the tool inferred*, which the RTL does not implement. **Not recorded anywhere in this repo before now.** |
| **Q3** | CG092 `HCLK` ↔ `PCLKG` | Not declared as a domain pair in `top_ahb_qspi.sgdc` at all, and the sync cells are separately `-du` waived. Benign because both derive from `sys_hclk`, but the SGDC does not say so — it simply never asks. |

### 4.3 Category 3 — the asymmetries

| Asymmetry | Direction | Reading |
|---|---|---|
| **`rtc_clk` / `user_ref_clk`** (rows E11-E13, D12, R3-R4) | CDC reports **~40 crossings** across pairs that do not exist in STA | **Both are right.** CDC analyses the inner top where the clocks are separate ports; the pad ring aliases all three onto one pad (`nanosoc_eth_chiplet_chip.v:102-103`). CDC over-reports, which is the safe direction, and its lens is the correct one for the FPGA build and for any respin that bonds them separately. What was missing is anyone writing down that they are different questions. |
| **QSPI** (rows Q1-Q2) | CDC block level says **6 real crossings**; CDC chiplet level says **0**; STA says **timed** | The chiplet level **proved** QSPI is not an independent domain (`qspi_clock_div.v:10`, both mux arms are HCLK). The block level has never been told. Its 19 `cdc_false_path`s describe a metastability risk that cannot exist — while the risk that *does* exist (the latch-enable window) is expressible in neither tool. |
| **D2 — `sys_hclk → pad_clk_tx`** | CDC says **REAL**; live STA says **timed**; shipped STA says **cut** | The live and shipped constraint sets give opposite answers on the same row. `constraints.sdc:302-320` resolves it: the Wlink transmit chain hangs off the `CLK` pad, so the live answer (timed) is the correct one and the shipped build false-pathed 1184 endpoints it should have timed. |
| **D3 — a2l flow-control** | STA cuts and bounds it **by name**; CDC waives it wholesale at HEAD | **STA is ahead of CDC here**, which is the reverse of every other row. The 69 named anchors and 22 datapath bounds are a more precise statement about the a2l mailbox than anything on the CDC side — and they were added *after* the shipping database was built. |
| **E6 — `last_push_flags`** | CDC clean; STA carries an MCP that has never applied | The 2/1 multicycle is **extinguished**, not redundant: false path outranks multicycle, and the rmii group makes the pair a false path. It is retired in the live inputs (`ethernet_constraints.sdc:554-555`) and still **live in the shipped SDC** (`..._syn.sdc:790`, `:797`) alongside two other mechanisms for the same boundary. |
| **S2 — SWD** | CDC **cannot confirm** 33 crossings; STA cuts them | The one row where the tool's refusal is the honest answer. SpyGlass rejected a correct qualifier under `strict` merge rules rather than accept it on the author's word; nobody raised the global knob to make the number go away. |

---

## 5. Corrections this exercise produced

Recorded because each one currently misleads a reader of an existing document.

1. **`CDC_WAIVER_INVENTORY.md` §1 and §2.1 are stale.** The tidelink blanket
   `-du` patterns — its flagship finding — have been replaced by an enumerated,
   generated allow-list with a working drift gate. Counts are now 9 files / 295
   `waive` / 1 remaining `-regexp`. **But the fix is uncommitted, the generator is
   not in CI, and the two Ethernet blanket files (152 statements) are untouched.**
   See §2.3.
2. **The task framing "exactly 7 `set_false_path`, 5 groups" does not match the
   live files.** Measured: **9** `set_false_path` and **4** groups
   (`constraints.sdc:395-399`). Five groups is the **shipped** SDC
   (`..._syn.sdc:804-812`), pre-[C2] Option A. Both numbers are real; they
   describe different files.
3. **`rmii_mode_speed` is not a crossing.** Tied `1'b1` at
   `nanosoc_multicore_soc.sv:923`. Corollary: **10 Mbps RMII is unreachable on
   this die.**
4. **`CDC_FINDINGS.md`'s MCKDMN line numbers no longer resolve.**
   `tidelink_top.sv` has grown: `u_gpio_phy_apb_regs` is at `:1286`, not `:953`;
   `u_chiplet_controller` at `:2874`, not `:2041`.
5. **The V1/V2 deskew trap.** `tidelink_lane_deskew.sv:214-233` crosses `wr_ptr`
   as a plain **binary** counter; `tidelink_lane_deskew_v2.sv:949-972` uses gray.
   The ASIC binds **V2** (`tidelink_top_full_asic_v2.flist:157`, `:182`). Citing
   V1 for the shipping chip overstates the defect.
6. **`eth_registers.v:1023`** — vendor single-flop back-sync, previously unrecorded.
7. **Two `rmii_to_mii.v` comments overstate the implementation** (`:36` "8-stage"
   vs 4 flops; `:31-32` "two-stage RX sync" vs one flop on `rmii_crs_dv`).
8. **TideChart's single-clock claim is true but has no tool behind it in this
   checkout** — `tidechart/cdc/tidechart_controller_cdc_summary.rpt` reads
   "(no report files found)". Verified here by RTL inspection instead.

---

## 6. What would close the largest gaps, cheapest first

None of these is a change to a `.sdc` or a CDC deck by this document; they are
the actions the register makes visible.

| # | Action | Where | Cost |
|---|---|---|---|
| 1 | **Commit the tidelink waiver regeneration and wire `--check` into CI.** The fix exists, passes, and is invisible to every clone. | `tidelink/cdc/waiver.swl`; `scripts/cdc/gen_tidelink_waivers.py` | minutes |
| 2 | **Run `-goals "cdc/clock_reset_integrity"`.** 14 unregistered rules including `Reset_check07` and `Clock_Reset_check03`, on a design whose reset ordering is already a documented concern. ~4 min on a warm workdir. | `cdc/` | minutes |
| 3 | **Stop calling `ha1588_{rx,tx}_queue_reset()` while the MAC is enabled.** Zero-RTL mitigation for the #1 row. | firmware | hours |
| 4 | **Un-waive `tsu`, `ptp_queue`, `eth_wishbone`** — the locally-patched units excluded as `"third-party-IP"`. Rows E2 and E4. | `ethernet-subsystem-ahb/cdc/waiver.swl:140-141`, `:150-156` | hours |
| 5 | **Scope `Ac_unsync02 -msg "*pad_rx*"` to the specific instance.** Row D1; already recommended and unactioned. | `tidelink/cdc/waiver.swl:296` | minutes |
| 6 | **Decide the deskew boundary** — a narrow `set_false_path` on the FIFO data path, or a written statement that timing it is the intent. Rows D4/D5. | `constraints.sdc:356-362` | hours |
| 7 | **Answer the `_18` flist question**: does the mailbox reset-coherence fix subsume the `raddr` reset-skew gate, or does the ASIC ship half a fix? | `tidelink_top_full_asic_v2.flist:238`, `:263` | hours |
| 8 | **Fix the `cdc` signoff stage's liveness guard** so it can say PASS, and unblock the HAL abort. Today the stage produces no CDC information and the red is invisible behind `gate: report`. | `verif/cdc/run.sh` | hours |
| 9 | **Write the R1 interlock down as a waiver with its citations**, so it stops being re-derived every run. | `cdc/waiver.swl` or this file | minutes |
| 10 | **B8 — un-black-box `axi_chiplet_controller`.** The only thing that turns the whole of §3.1 from RTL reading into measurement. | `tidelink/cdc/tidelink_top.prj:50` | days |

---

## 7. Provenance

Every number in this document was measured against the working tree on
2026-08-18, not quoted from a prior document, except where a `docs/CDC_*` file is
cited by section for an analysis result. The five constraint files were read in
full; the shipped `nanosoc_eth_chiplet_pads_syn.sdc` (16.7 MB, Aug 14 14:01) was
queried directly for what reached P&R; RTL citations were spot-verified against
the copies the **flists actually bind**, not the first match on disk — this tree
carries up to four copies of some modules and only the flist says which one
builds.

No file outside this document was created, modified or deleted.
