# CDC Waiver Inventory

Complete inventory of every CDC waiver in the `nanosoc-ethernet-chiplet` tree,
plus the lint rule-level suppressions that act as waivers by another name.

Compiled 2026-08-17. Every row cites `file:line`. **Nothing has been removed** —
this document inventories and recommends only.

Recommendation vocabulary:

| Verdict | Meaning |
|---|---|
| **KEEP** | Legitimate by-design waiver. Scope is tight, justification holds. |
| **NARROW** | The waiver is defensible but its scope is wider than its justification. Re-scope to the specific rule/instance/signal. |
| **REMOVE** | Not justified, or the underlying condition it papered over has changed. |
| **OWNER** | Needs an explicit named accept/fix decision before tapeout. Not something an engineer should silently resolve. |

---

## 1. Headline counts

| Category | Count |
|---|---|
| `waiver.swl` files found | **7** |
| Total `waive` statements | **215** |
| ...of which are blanket **`-du`** (whole design-unit) waivers | **189** (88%) |
| ...of which are rule-scoped (`-rule` + `-msg`/`-file`) | **26** |
| `.sgdc` files carrying waiver-class constructs | **4** |
| `cdc_false_path` directives | **19** (all in `ahb_qspi`) |
| `quasi_static` declarations | **11** |
| `set_case_analysis` declarations (constraint, not waiver — listed for completeness) | **8** |
| **Grand total waiver-class constructs** | **245** |
| HAL lint rule-level `-nocheck` on CDC sign-off rules | **5** across 2 files |

The seven waiver files, and whether each is actually wired into a run:

| File | `waive` count | Loaded by |
|---|---|---|
| `nanosoc-multicore-system/ethernet-subsystem-ahb/cdc/waiver.swl` | 116 | `ethernet-subsystem-ahb/cdc/Makefile:22` |
| `tidelink/cdc/waiver.swl` | 46 | `tidelink/cdc/tidelink_top.prj:43` |
| `nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb/cdc/waiver.swl` | 36 | `ethernet-mac-ahb/cdc/Makefile:19` |
| `nanosoc-multicore-system/ahb_qspi/cdc/waiver.swl` | 14 | `ahb_qspi/cdc/Makefile:16` |
| `tidechart/cdc/waiver.swl` | 2 | `tidechart/cdc/Makefile:14` |
| `nanosoc-multicore-system/ptp-hardware-clock-ahb/cdc/waiver.swl` | 1 | `ptp-hardware-clock-ahb/cdc/Makefile:22` |
| `nanosoc-multicore-system/cdc/waiver.swl` | **0** (entirely commented out) | `nanosoc-multicore-system/cdc/Makefile:77` |

There is no chiplet-top waiver file. The SoC-top CDC run therefore carries **zero**
waivers, so every third-party crossing the block-level runs suppress is reported
raw at SoC level — noisy, but not a hiding place.

---

## 2. Worst offenders — read this section if you read nothing else

### 2.1 The entire vendor D2D IP is waived, including RTL this project modified

`tidelink/cdc/waiver.swl:43-51` blanket-waives every Wlink design unit:

```
43 waive -du "Wlink"              -comment "Wlink top — Chisel-generated, own CDC"
44 waive -du "Wav*" -regexp       -comment "Wlink primitives — verified CDC cells"
45 waive -du "Wlink*" -regexp     -comment "Wlink submodules — Chisel-generated"
51 waive -du "wlink_*" -regexp    -comment "Wlink internal modules — Chisel-generated"
```

**The justification is factually wrong for this build.** `tidelink/src/rtl/local_overrides/`
contains **34 files** — locally modified copies of exactly these modules, which the
flist substitutes for the vendor originals. Modules defined there and matched by
the patterns above include:

| Local override | Waived by | Why it matters |
|---|---|---|
| `WlinkGenericFCReplayV2_12.v`, `_13.v` | `:45` `Wlink*` | These carry the a2l CDC self-latch fix. The same fix was **never ported** to the AW/W/B replay instances (`WlinkGenericFCReplayV2_1/_3/_5`), which are waived by the identical pattern. |
| `wlink_wlink_ptp_tl_a2l_48x4.v` | `:51` `wlink_*` | The app-to-link mailbox FIFO itself. |
| `WavMultibitSync_18.v` | `:44` `Wav*` | A **synchroniser primitive**, locally modified, waived under the comment "verified CDC cells". |
| `WlinkGenericFCSM*.v` (7 variants) | `:45` `Wlink*` | Flow-control state machines. |
| `WlinkRxLinkLayer.v`, `Wlink.v`, `TideLinkToWlink.v` (`:49`), `WavD2DGpio*.v`, `WlinkGPIOPHY.v`, `WlinkEccSyndrome.v` | `:43`, `:44`, `:45`, `:49` | |
| `axi_chiplet_controller.sv` | `:63` **and** `stop_module` at `tidelink_top.prj:50` | Double-suppressed: black-boxed *and* waived. |

Every one of these is RTL this repository owns, has already had at least one CDC
defect in, and is nonetheless excluded from CDC analysis on the grounds that it is
untouched vendor IP. **This is the single largest blind spot in the tree.**

> **OWNER / NARROW.** The `-du` patterns should not match anything under
> `src/rtl/local_overrides/`. Recommended shape: keep the blanket waivers for
> genuinely-pristine vendor units, and add an explicit allow-list exception (or
> simply drop `Wav*`/`Wlink*`/`wlink_*` and enumerate the unmodified units) so the
> 34 overridden modules are analysed. Do this before the next TideLink sign-off.

### 2.2 SoCLabs-patched HA1588 and MAC RTL waived as "third-party-IP"

`ethernet-subsystem-ahb/cdc/waiver.swl:150-156` and `ethernet-mac-ahb/cdc/waiver.swl:54-60`
waive `ha1588`, `rtc`, `ptp_parser`, `ptp_queue`, `tsu`, `reg`, `wb_slv_wrapper`
with the comment `"third-party-IP"`.

Six of those seven are **not** third-party in this build. `ethernet-mac-ahb/flist/ha1588_apb.flist:3-8`
sources them from `src/rtl/ha1588_patches/`:

```
3 ${ETHMAC_AHB_HOME}/src/rtl/ha1588_patches/rtc.v
4 ${ETHMAC_AHB_HOME}/src/rtl/ha1588_patches/ptp_parser.v
5 ${ETHMAC_AHB_HOME}/src/rtl/ha1588_patches/ptp_queue.v
6 ${ETHMAC_AHB_HOME}/src/rtl/ha1588_patches/tsu.v
7 ${ETHMAC_AHB_HOME}/src/rtl/ha1588_patches/reg.v
8 ${ETHMAC_AHB_HOME}/src/rtl/ha1588_patches/ha1588.v
```

`tsu.v` is the most acute case: it is 29 KB of locally rewritten RTL whose own header
(`src/rtl/ha1588_patches/tsu.v:47-48`) documents a **silicon defect** it exists to fix
(`t2=0`, traced to the `rmii_to_mii` RX di-bit-pair lock phase). It sits directly on the
`rtc_clk` ↔ MII boundary and is entirely excluded from CDC analysis.

Same pattern for the MAC: `ethmac_ahb_rmii.flist:27-28` sources `eth_spram_256x32.v` and
`eth_wishbone.v` from `src/rtl/ethmac_patches/`, while
`ethernet-subsystem-ahb/cdc/waiver.swl:140-141` waives both as `"third-party-IP"`.
`eth_wishbone` is the MAC's DMA/descriptor engine — the busiest WB↔MII crossing in the block.

> **OWNER.** Eight locally-patched design units are excluded from CDC by a
> justification that no longer describes them. At minimum, `tsu` and `eth_wishbone`
> should be un-waived and analysed.

### 2.3 Two design-unit names are dangerously generic

`ethernet-subsystem-ahb/cdc/waiver.swl:151` — `waive -rule "*" -du {rtc}`
`ethernet-subsystem-ahb/cdc/waiver.swl:155` — `waive -rule "*" -du {reg}`
(and `ethernet-mac-ahb/cdc/waiver.swl:55, :59` identically)

`waive -rule "*"` means *all rules*, and `reg`/`rtc` are names any future block could
plausibly reuse. A new module called `reg` anywhere in the SoC would be silently and
totally exempted from CDC without anyone touching a waiver file.

> **NARROW.** Qualify with the file or hierarchy, e.g. `-file "ha1588_patches/reg.v"`.

### 2.4 Two global waivers with no scope at all

`tidelink/cdc/waiver.swl:133` — `waive -rule checkSGDC_05` (no `-du`, no `-file`, no `-msg`)
`tidelink/cdc/waiver.swl:135` — `waive -rule Ac_clockperiod01` (same)

`checkSGDC_05` is the rule that reports **unmatched `abstract_port` declarations** — the
exact failure class that produced the stale-constraint bug fixed in
`nanosoc-multicore-system/cdc/nanosoc_multicore_soc.sgdc` (Task B1), and the same class
that `tidelink/cdc/axi_chiplet_controller.sgdc:60-65` records as having previously caused
a fatal early-termination and a false "0 clocks / 0 crossings" result. Globally waiving
it removes the tree's only automatic detector for constraint files drifting out of sync
with the RTL.

> **REMOVE `checkSGDC_05` (`:133`).** Its stated purpose ("abstract_port auto-migrated
> for stop_module'd subblocks") justifies a `-file`-scoped waiver on the two black-boxed
> SGDCs, not a global one. `Ac_clockperiod01` (`:135`) is cosmetic — **KEEP**, but scope it.

---

## 3. Per-file inventory

### 3.1 `tidelink/cdc/waiver.swl` — 46 waivers

| Line(s) | Waives | Scope | Justification given | Verdict |
|---|---|---|---|---|
| 22-25 | `cmsdk_ahb_to_sram`, `cmsdk_fpga_sram`, `cmsdk_ahb_to_apb`, `cmsdk_apb_slave_mux` | 4 × `-du` | "ARM CMSDK IP — single-clock, no real CDC" | **KEEP** — true single-clock vendor blocks. |
| 34 | `xhb500_*` (regexp) | `-du` pattern | "pre-verified CDC"; also `stop_module` at `tidelink_top.prj:50` | **KEEP** — vendor IP, unmodified, and already black-boxed. Waiver is a redundant safety net (`:32` says so). |
| **43-45, 51** | `Wlink`, `Wav*`, `Wlink*`, `wlink_*` | 4 × `-du` pattern — **the whole D2D IP** | "Chisel-generated, own CDC" / "verified CDC cells" | **OWNER / NARROW — see §2.1.** Matches 34 locally-modified files incl. the a2l mailbox and a synchroniser primitive. |
| 46-50 | `AXI4ToWlink`, `GeneralBusToWlink`, `ShortPacketToWlink`, `TideLinkToWlink`, `APBFanout*` | 5 × `-du` | "Chisel-generated" | **NARROW** — `ShortPacketToWlink` and `TideLinkToWlink` both have local overrides. |
| 63 | `axi_chiplet_controller` | `-du` | "pre-verified internal CDC"; `:60-61` calls it a safety net behind `stop_module` | **NARROW** — but there *is* a local override (`local_overrides/axi_chiplet_controller.sv`), so "pre-verified" is inaccurate. The `stop_module` is doing the real work. |
| 66-70 | `i2c_master`, `i2c_master_wbs`, `i2c_slave`, `i2c_slave_axil_master`, `axis_fifo` | 5 × `-du` | third-party I2C/AXIS IP | **KEEP** — genuine external IP. Note `i2c_master`/`i2c_master_axil` *do* appear in `local_overrides/`; worth a spot-check. |
| 73-77 | `mkAXI4_to_AXI4_Lite_Adapter`, `mkAPB_Master_Xactor`, `FIFO2`, `FIFOL1`, `SizedFIFO` | 5 × `-du` | Bluespec-generated primitives | **KEEP** — inside the black-boxed controller anyway. |
| 83 | `wav_latch_model` | `-du` | "simulation primitive" | **KEEP**. |
| 97-98 | `Ac_unsync01` on `*i2c_sda_i*` / `*i2c_scl_i*` | rule + msg | "async external bus, synchronised inside chiplet controller" | **KEEP** — correct and tightly scoped. Doubly covered by `quasi_static` at `tidelink_top.sgdc:129-130`. |
| 99-100 | `Ac_unsync01` on `*axi_chiplet_controller/hresetn*` / `*poresetn*` | rule + msg | "synchronised by WavDemetReset inside Wlink" | **KEEP** — the claim is checkable and the scope is one signal each. |
| 101 | `Ac_unsync02` on `*pad_rx*` | rule + msg | "PHY RX data — async recovered clock, synchronised by Wlink SerDes" | **NARROW** — `pad_rx` is the D2D receive data path and `*pad_rx*` is a loose glob. Given the known RX-side framing history, scope this to the specific instance. |
| 115, 117, 119 | `Ac_cdc01a`, `Ac_datahold01a`, `Reset_sync04` on `tidelink_phc_cdc.sv` | rule + file | Toggle/ack handshake, data held stable by FSM contract; cites `docs/reference/SPYGLASS_CDC_SIGNOFF.md §3.2`; says it is exercised by `cocotb/phc_ahb` + `uvm/phc` | **KEEP** — model waiver: named rule, one file, a mechanism argument, and a named test that exercises it. |
| 123 | `ErrorAnalyzeBBox` on `tidelink_mul_iter` | rule + du | "DesignWare multiplier — port-safe vendor blackbox" | **KEEP** — cosmetic. |
| 127, 129 | `SGDC_waive24`, `SGDC_waive25` on `waiver.swl` | rule + file | "safety-net waivers for stop_module'd hierarchy" | **KEEP** — self-referential noise suppression. Note these exist *because* of the redundant `-du` safety nets; removing those removes the need for these. |
| 131 | `checkSGDC_01` on `xhb500.sgdc` | rule + file | "current_design auto-migrated" | **KEEP** — file-scoped. |
| **133** | `checkSGDC_05` | **rule only — GLOBAL** | "abstract_port auto-migrated for stop_module'd subblocks" | **REMOVE / re-scope — see §2.4.** This is the unmatched-`abstract_port` detector. |
| 135 | `Ac_clockperiod01` | **rule only — GLOBAL** | "Edge-List autocompleted — no functional impact" | **NARROW** — cosmetic, but should not be global. |
| 139 | `WRN_1024` on `tidelink_perf.sv` | rule + file | signed-cast width-safe by inspection | **KEEP**. |
| 175-182 | `Ac_cdc01a`, `Ac_conv04`, `Reset_sync02`, `Reset_sync04` on `tidelink_gpio_phy_apb_regs.sv` | 4 × rule + file | Long rationale at `:142-173` covering four specific paths, citing `docs/SPYGLASS_CDC_RE_RUN_2026_05_28.md §4` and spec §6.1 | **KEEP** — the best-documented waivers in the tree. One caveat: `Ac_cdc01a` file-scoped covers *all* crossings in that file, while the rationale enumerates only paths (1) and (2). **NARROW** if the file grows. |
| 190 | `Ac_unsync01` on `*idelay_rst*` | rule + msg | POR to `idelay_rst`; IDELAYE2 is async-reset-only; covered by `set_clock_groups -asynchronous` in `syn/asic` | **KEEP** — FPGA-primitive-specific and correct. |

### 3.2 `nanosoc-multicore-system/ethernet-subsystem-ahb/cdc/waiver.swl` — 116 waivers

> **Read checklist item 19 first.** These 116 waivers are loaded into a run whose
> elaboration top (`ethernet_ss_ahb`) no longer exists in the RTL — the built top is
> `ethernet_ss_ahb_rmii`. Whatever that run reports, the waivers below have not been
> validated against the design that actually ships.

Every line here is `waive -rule "*" -du {X}` — **all rules, whole design unit** — with the
single justification string `"third-party-IP"`. That is the weakest justification format
in the tree: it records no mechanism and no evidence.

| Line(s) | Waives | Count | Verdict |
|---|---|---|---|
| 21-52 | Cortex-M0 core + DAP (`CORTEXM0`, `cm0_*`) | 32 | **KEEP** — genuine ARM IP, unmodified. |
| 63-109 | Cortex-M0+ core + DAP (`CORTEXM0PLUS`, `cm0p_*`) | 47 | **KEEP** — same. Note `:82-88, :92-109` waive ARM's *own synchroniser cells* (`cm0p_*_cdc_*`, `cm0p_*_sync`); correct, but it means the DAP↔core boundary is entirely unexamined. |
| 118-139 | OpenCores MAC units (`eth_top`, `eth_rxethmac`, `eth_txethmac`, …) | 22 | **NARROW** — pristine vendor units; the "in production use for years" argument (`:114-116`) is weak for an ASIC but acceptable. |
| **140-141** | `eth_wishbone`, `eth_spram_256x32` | 2 | **OWNER — see §2.2.** Both are sourced from `src/rtl/ethmac_patches/`. `eth_wishbone` is the DMA engine on the WB↔MII boundary. |
| **150-156** | `ha1588`, `rtc`, `ptp_parser`, `ptp_queue`, `tsu`, `reg`, `wb_slv_wrapper` | 7 | **OWNER — see §2.2.** Six of seven come from `src/rtl/ha1588_patches/`. `tsu` fixes a known silicon defect and sits on `rtc_clk`↔MII. Only `wb_slv_wrapper` is genuinely upstream. Additionally **NARROW** `reg` and `rtc` per §2.3. |
| 162-164 | `cmsdk_fpga_sram`, `cmsdk_ahb_to_sram`, `cmsdk_apb_slave_mux` | 3 | **KEEP**. |
| 171-173 | `ahb3lite_to_wb`, `wb_to_ahb3lite`, `apb_to_wb` | 3 | **NARROW** — justification at `:169` is "single-clock (operates in system clock domain)", which is a *design claim*, not a vendor-preverification claim. If true, these produce no crossings and the waiver is unnecessary; if false, the waiver hides the AHB↔WB boundary. Verify, then delete or re-scope. |

### 3.3 `nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb/cdc/waiver.swl` — 36 waivers

A strict subset of §3.2, same `waive -rule "*" -du {X}` / `"third-party-IP"` format.

| Line(s) | Waives | Count | Verdict |
|---|---|---|---|
| 22-43 | OpenCores MAC units | 22 | **NARROW** — as §3.2. |
| **44-45** | `eth_wishbone`, `eth_spram_256x32` | 2 | **OWNER** — locally patched. |
| **54-60** | `ha1588`, `rtc`, `ptp_parser`, `ptp_queue`, `tsu`, `reg`, `wb_slv_wrapper` | 7 | **OWNER** — locally patched; see §2.2/§2.3. |
| 66-67 | `cmsdk_fpga_sram`, `cmsdk_apb_slave_mux` | 2 | **KEEP**. |
| 74-76 | `ahb3lite_to_wb`, `wb_to_ahb3lite`, `apb_to_wb` | 3 | **NARROW** — as §3.2. |

> Note the duplication: these 36 rows are maintained by hand in two places. They have
> already drifted — `cmsdk_ahb_to_sram` is waived at the subsystem level
> (`ethernet-subsystem-ahb/cdc/waiver.swl:163`) but not at the MAC level. **Recommend a
> shared include** rather than two copies.

### 3.4 `nanosoc-multicore-system/ahb_qspi/cdc/waiver.swl` — 14 waivers

The best-governed waiver file in the tree. Its header (`:8-24`) states an explicit policy:
prefer an RTL assertion over a waiver, and it documents a waiver that was **removed**
because it masked a real bug (`:71-93`, the `Ac_conv03` waiver that hid Bug D).

| Line(s) | Waives | Scope | Justification | Verdict |
|---|---|---|---|---|
| 39 | `cmsdk_apb_slave_mux` | `-du` | "combinational mux, no real CDC" | **KEEP**. |
| 48-51 | `p_flash_cache_f0_capt_sync`, `cdc_capt_sync`, `p_flash_cache_f0_static_reg`, `static_reg` | 4 × `-du` | ARM CG092 sync cells, pre-verified | **NARROW** — `static_reg` and `cdc_capt_sync` are generic enough to collide with other IP. Prefix-qualify. |
| 54-57 | `p_flash_cache_f0_core`, `_reg_block`, `_bus_logic`, `_mrb` | 4 × `-du` | "CDC pre-verified by ARM" — covers the PCLK→HCLK register crossings | **KEEP** — genuine unmodified vendor IP. |
| 68 | `Ac_unsync01` on `*AHB_QSPI_BUSY_del*QSPI_nCS*` | rule + msg | Same-domain path mis-identified because `QSPI_nCS` is a top-level wire | **KEEP** — explicitly self-described as "targeted waiver, not a blanket rule suppression" (`:67`). |
| 100 | `Clock_sync05a` on `*HRESETn*` | rule + msg | System-wide async reset sampled in 3 domains by design | **KEEP**. |
| 102, 104 | `Reset_sync04` on `*HRESETn*` / `*PRESETn*` | rule + msg | Independent sync chains sharing one async reset | **KEEP**. |
| 114 | `Clock_check07` on `*HCLK*QSPI_SCLK_i*` | rule + msg | SCLK intentionally divided from HCLK | **KEEP** — matches the divider described at `top_ahb_qspi.sgdc:11-15`. |

### 3.5 `nanosoc-multicore-system/ptp-hardware-clock-ahb/cdc/waiver.swl` — 1 waiver

| Line | Waives | Verdict |
|---|---|---|
| 18 | `-du cmsdk_ahb_to_apb`, "single-clock AHB-to-APB bridge" | **KEEP** — PHC is single-clock (`phc_ahb.sgdc:24`); nothing to hide. |

### 3.6 `tidechart/cdc/waiver.swl` — 2 waivers

| Line | Waives | Verdict |
|---|---|---|
| 8 | `Clock_info03a`, "single-clock design, clk auto-detected" | **KEEP** — informational rule only. |
| 9 | `Setup_clockreset01`, "clock/reset auto-detected" | **NARROW** — this suppresses the *setup* check that would report a missing clock/reset declaration. In a single-clock design the risk is low, but the header's own claim (`:4-5`) that "CDC analysis correctly reports 0 unsynchronized crossings" is partly a consequence of this waiver. Prefer declaring `clk`/`resetn` properly in `tidechart.sgdc` and deleting the waiver. |

### 3.7 `nanosoc-multicore-system/cdc/waiver.swl` — 0 active waivers

Everything is commented out (`:24-25`, `:30`, `:35`) and the file says so at `:8`
("intentionally starts empty"). **KEEP as-is.**

Two flow observations, neither a waiver but both affecting what a run means:

- `nanosoc-multicore-system/cdc/Makefile:76-77` hardcodes `SGDC` and `SWL` to the
  **SoC-top** files regardless of `MODULE`. So `make cdc MODULE=top_ahb_qspi` from that
  directory runs the QSPI top against the SoC's constraints and an empty waiver file —
  a meaningless result that will not look like an error. **OWNER.**
- `tidelink/cdc/tidelink_top.prj:50` sets
  `stop_module {axi_chiplet_controller xhb500_axi_to_ahb_bridge_chiplet_mst xhb500_ahb_to_axi_bridge_chiplet_slv}`.
  Black-boxing is a stronger suppression than any waiver — nothing inside is analysed at
  all — and it is invisible in the waiver files. Port domains are supplied by
  `axi_chiplet_controller.sgdc` and `xhb500.sgdc`. **Record as a waiver-equivalent.**

### 3.8 SGDC-embedded waiver constructs

#### `quasi_static` (11) — treated as "cannot change during operation"

| File:line | Signal | Verdict |
|---|---|---|
| `tidelink/cdc/tidelink_top.sgdc:118` | `role_strap_i` | **KEEP** — hardware strap, stable before reset deassert. |
| `tidelink_top.sgdc:122-124` | `puf_seed*`, `nego_priority_i*`, `mask_hs_bypass_i` | **KEEP** — bring-up straps, never re-driven. |
| `tidelink_top.sgdc:129-130` | `i2c_scl_i`, `i2c_sda_i` | **NARROW** — I2C lines are *not* quasi-static; they toggle continuously during a transfer. The correct model is "async input synchronised inside the black box", which is what the `-msg` waivers at `waiver.swl:97-98` already say. Using `quasi_static` as well overstates the guarantee. |
| `ahb_qspi/cdc/top_ahb_qspi.sgdc:114` | `u_apb_qspi_regs/reg13[*]` (`QSPI_CLK_DIV`) | **KEEP** — well argued at `:112-113`; changing it mid-transaction is a software error, not a CDC path. |
| `ahb_qspi/cdc/top_ahb_qspi.sgdc:121` | `u_apb_qspi_regs/reg12[*]` (XiP cmd/dummy cycles) | **KEEP** — and the failure mode if software violates it is bounded by the Layer-1 watchdog (`:118-120`). |
| `ethernet-subsystem-ahb/cdc/ethernet_ss_ahb.sgdc:54-55` | `sys_testmode`, `sys_scanenable` | **KEEP** — the comment at `:49-52` documents exactly why: without them SpyGlass defaults these to `mrx_clk_i` and manufactures 3 false crossings. This is the reference example of the defaulting trap. |
| `nanosoc-multicore-system/cdc/nanosoc_multicore_soc.sgdc:273` | `sys_sysresetreq` | **KEEP**. |

> The QSPI SGDC header (`top_ahb_qspi.sgdc:17-36`) records that a previous version used
> `quasi_static` on **whole APB register words** (`reg0`, `reg2`, `reg3`) and that this
> "hid real CDC vulnerabilities — specifically Bug A … and Bug D". That is the single
> best-documented instance in this repo of a blanket waiver hiding a real bug, and it is
> the reason the remaining QSPI waivers are as tight as they are.

#### `cdc_false_path` (19) — all in `ahb_qspi/cdc/top_ahb_qspi.sgdc`

These are deliberate: the author chose `cdc_false_path` over `quasi_static` specifically
so the report still shows where the protection lives (`:144-147`). They are **not**
suppressions of unknown risk — they are the documented form of the six known crossings
in §5. Grouped:

| Lines | From → To | Protection claimed | Verdict |
|---|---|---|---|
| 150-154 | `reg2[*]` → 5 × `qspi_*_latched` | Latched at IDLE→OP transition (Bug A fix) | **OWNER** — single-flop latch, not 2-FF; see §5 row 3. |
| 157-160 | `reg0[*]` → 4 × `qspi_*_latched` | Same | **OWNER** — same. |
| 166-170 | `reg3[*]` → `addr_code[*]`; `reg8-11[*]` → `QSPI_WDATA_reg[*]` | "Same protection pattern", with an explicit **TODO** at `:164-165` to add real latch regs | **OWNER** — see §5 rows 4/5/6. The SGDC itself marks this incomplete. |
| 190-191 | `data_in_reg[*]` → `HRDATA[*]`, `PRDATA[*]` | Valid-qualified by synchronised BUSY; caveat + named test `test_cdc_rdata_stability_at_low_clkdiv` at `:186-189` | **KEEP** — a mechanism argument plus a regression test that would catch its violation. Model waiver. |
| 201-203 | `HRESETn` → 3 × `AHB_QSPI_BUSY_del*` | SCLK edges aligned to HCLK edges by the divider | **KEEP**. |

#### `set_case_analysis` (8) — constraint, not waiver

`nanosoc_multicore_soc.sgdc` (`sys_scanenable=0`, `sys_testmode=0`, `dap_swj_enable=1`) and
`tidelink_top.sgdc:57-60, :133` (`scan_mode`, `scan_asyncrst_ctrl`, `scan_shift`, `scan_in`,
`scan_clk`). All **KEEP** — standard mission-mode DFT tie-off. Flagged only because
`dap_swj_enable=1` is a *strap*, not a scan pin: it pins the SWD path permanently active,
which is correct for a single-chiplet build and documented as such.

---

## 4. Rule-level suppressions in the lint rulesets

**Framing correction:** these are **Cadence HAL** rule files (`hal -file <rules>.tcl`), not
SpyGlass. SpyGlass in this tree is used only for CDC. None of these files contains a
`define_goal`/`current_goal` block — each is a **flat, unscoped list**, so every `-nocheck`
applies globally to whatever HAL invocation loads that file.

### 4.1 The two halves — both verified

**Half A — the per-unit rulesets suppress CDC sign-off rules. CONFIRMED.**

| File:line | Directive | Stated justification |
|---|---|---|
| `nanosoc-multicore-system/lint/hal.tcl:157` | `-nocheck CLKDMN` | ":152-156 — CDC inside Cortex-M0 / CG092 is properly synchronised; HAL doesn't recognise the in-IP patterns. *(CDC is covered separately by SpyGlass.)*" |
| `nanosoc-multicore-system/lint/hal.tcl:158` | `-nocheck INSYNC` | same block |
| `nanosoc-multicore-system/lint/hal.tcl:161` | `-nocheck GLTASR` | ":159-160 — Cortex-M0 `RSTBYPASS` mux in `cm0_rst_sync.v`" |
| `nanosoc-multicore-system/lint/hal.tcl:182` | `-nocheck MLTDRV` | ":178-181 — cross-subsystem passthrough outputs share wires by design" |
| `nanosoc-multicore-system/ahb_qspi/lint/hal.tcl:128` | `-nocheck CLKDMN` | ":124-127 — the design intentionally crosses HCLK/PCLK → `QSPI_SCLK_i`; *analysed by SpyGlass CDC separately*" |

Also suppressed in the same files: `UNCONI` (`lint/hal.tcl:173`, `ahb_qspi/lint/hal.tcl:122`)
and `SIZMIS` (`lint/hal.tcl:177`).

**Half B — the merged ruleset really is protected. CONFIRMED.**

`verif/lint/full/merge_hal_rules.py:30-32` holds the protected list, and `:75-79` drops any
matching `-nocheck` before dedup:

```python
30 # Must match hal_lint.sh:SIGNOFF_RULES and hal_report.py:NEVER_WAIVE.
31 SIGNOFF_RULES = {"MLTDRV", "CLKDMN", "INSYNC", "SIZMIS", "GLTASR",
32                  "LATINF", "NODRIV", "UNCONI", "RSTSCB", "CMBCDC"}
...
76             if rule in SIGNOFF_RULES:
77                 dropped.append((rule, rel))
78                 body.append(f"// DROPPED (sign-off rule, never waivable): -nocheck {rule}")
79                 continue
```

The generated `verif/lint/full/hal_rules.tcl` carries the six drop markers at
`:158, :159, :162, :173, :177, :182`, with the original justification prose preserved above
each and only the directive removed. No active `-nocheck` for any of the ten sign-off rules
survives in that file. A runtime preflight re-checks it at `verif/lint/full/hal_lint.sh:54-61`
and aborts with `FATAL` if one reappears. The merged file is currently in step
(`merge_hal_rules.py --check` passes, 104 rules).

### 4.2 So: are the per-unit `make lint` runs a false green? YES — for both.

`nanosoc-multicore-system`:
`lint/Makefile:127-128` runs HAL with `HAL_FLAGS`; `lint/Makefile:109` puts
`-file .../lint/hal.tcl` in those flags; that file suppresses CLKDMN, INSYNC, GLTASR and
MLTDRV at `:157, :158, :161, :182`. Nothing in this path consults `SIGNOFF_RULES` — the
preflight lives only in `verif/lint/full/hal_lint.sh` and only inspects
`verif/lint/full/hal_rules.tcl`, which this Makefile never reads.
→ **All four rules are off. A clean report proves nothing about them.**

`ahb_qspi`:
`ahb_qspi/lint/Makefile:54-55` + `:46` (`-file $(SOCLABS_AHB_QSPI_DIR)/lint/hal.tcl`) →
`ahb_qspi/lint/hal.tcl:128` suppresses **CLKDMN** — the rule that matters most for the one
block in the tree that deliberately crosses three clock domains. INSYNC/GLTASR/MLTDRV are
*not* waived there and do run.

Three aggravating factors:

1. **The unit lint is what CI runs, and it cannot fail.**
   `nanosoc-multicore-system/.gitlab-ci.yml:152-166` — job `hal_lint`, `allow_failure: true`
   (`:158`), `script: make -C "$WORK_DIR/lint" lint-each` (`:166`) — i.e. the suppressed
   ruleset, non-gating.
2. **The named compensating control is not running.** Both waiver comments defer to
   SpyGlass CDC (`lint/hal.tcl:156`; `ahb_qspi/lint/hal.tcl:127`). The `spyglass_cdc` job is
   also `allow_failure: true` (`.gitlab-ci.yml:184`) and its own comment at `:180-183` records
   that the tool "aborts with SCL-602 before it runs" on a licence-daemon mismatch.
3. **The protection in Half B is unwired from CI.** Nothing invokes `hal_lint.sh`,
   `verif/lint/full/run.sh`, or `merge_hal_rules.py --check` — `grep -rn merge_hal_rules`
   returns only self-references. The root `make lint` (`Makefile:108-110`) is **Verilator**,
   not HAL. `ci/signoff.yaml:410-411` already records full-design lint as a known gap.

Two internal contradictions worth recording, because they will mislead a reader:

- `lint/hal.tcl:377-379` states MLTDRV "is NOT waived at integration level" — true of
  `verif/lint/full/hal_rules.tcl`, but the comment sits 195 lines below `-nocheck MLTDRV`
  in the very file the unit run consumes.
- `lint/hal.tcl:209-211` states UNCONI is "NOT waived, and must never be" — while `:173` of
  the same file waives it.
- `lint/hal_design_info.txt:64-66` states "a blanket `-nocheck GLTASR` is still refused",
  and demonstrates the correct narrow form at `:69-72` (file-scoped `GLTASR off;` for
  `soc_glue_and_gate.sv`) — yet the blanket form is present at `lint/hal.tcl:161`.

**Coverage gap in the merge itself:** `merge_hal_rules.py:34-42` lists seven units.
`.../ethernet-mac-ahb/amba_wb_bridges/lint/hal.tcl` (66 `-nocheck` lines) is **not** among
them. It waives no sign-off rule today, so it is not a hole yet — but a future one added
there would bypass both the merge and its preflight.

### 4.3 Recommendations

| # | Item | Verdict |
|---|---|---|
| L1 | `lint/hal.tcl:157,158,161,182` + `ahb_qspi/lint/hal.tcl:128` | **NARROW** — replace the blanket `-nocheck` with file-scoped `lint_checking file = … { RULE off; }` entries in `hal_design_info.txt`, exactly as `:69-72` already does for GLTASR. That preserves the vendor-IP intent without disarming the rule for authored RTL. |
| L2 | Unit `make lint` has no `SIGNOFF_RULES` preflight | **OWNER** — port the `hal_lint.sh:54-61` preflight into the unit lint Makefiles, or make them consume the merged ruleset. |
| L3 | `merge_hal_rules.py --check` never runs in CI | **OWNER** — add it to the ladder. The drift guard exists and is free. |
| L4 | `hal_lint` and `spyglass_cdc` are both `allow_failure: true`, and SpyGlass aborts on SCL-602 | **OWNER** — the entire CDC/lint sign-off chain is currently advisory. This is the highest-leverage fix on this list. |
| L5 | `amba_wb_bridges/lint/hal.tcl` absent from `merge_hal_rules.py:34-42` | **NARROW** — add it. |
| L6 | Contradictory comments at `lint/hal.tcl:209-211, :377-379` | **REMOVE/fix the comments** — they currently assert the opposite of the file's own behaviour. |

---

## 5. The QSPI six — protocol-protected crossings on the N1 critical path

Source: `nanosoc-multicore-system/ahb_qspi/docs/cdc_signoff_status.md:37-65`.
Run validated 2026-05-18, goal `cdc/cdc_verify_struct`: **141 messages, 21 waived, 0 fatal**.
Per-rule: 22 `Ac_conv03`, 14 `Ac_sync01` (properly synced), 10 `Ac_glitch03`,
**6 `Ac_unsync02`**, 5 `Clock_sync06`, 5 `Ac_conv04`, 3 misc.

All six are **real CDC crossings protected by protocol / single-flop latching plus a
software two-write-hold convention — NOT by true 2-FF synchronisers**
(`cdc_signoff_status.md:54-56`). That is a deliberate area tradeoff: a full 2-FF sync on
22-bit addr + 128-bit WDATA + ~15 flag bits ≈ **165 flops** (`top_ahb_qspi.sgdc:139-142`).

| # | Crossing | Protection | SGDC ref | Status | Verdict |
|---|---|---|---|---|---|
| 1 | `apb_qspi_regs.reg0[8]` (PCLK) → `ahb_qspi_interface.current_state[1:0]` (HCLK) — **"qualifier not found"** | ENABLE/ACK handshake | `top_ahb_qspi.sgdc:157-160` | **Flagged as the highest-risk row.** SpyGlass could not locate the qualifier, so the protection is asserted but *not tool-confirmed*. | **OWNER — do this one first.** Either supply the qualifier so the tool can prove it, or convert to a real synchroniser. |
| 2 | `qspi_controller.qspi_n_rw_bytes_latched` (SCLK) → `ahb_qspi_interface.HRDATA[127:0]` (HCLK) | RDATA safe-by-protocol, BUSY-qualified | `top_ahb_qspi.sgdc:172-191` | Argued in full, with a stated low-CLK_DIV caveat and a named regression test (`test_cdc_rdata_stability_at_low_clkdiv`). | **KEEP** — accept-by-protocol, provided that test is in the gating suite. Confirm it is. |
| 3 | `apb_qspi_regs.reg3[21:0]` (PCLK) → `qspi_controller.current_state[1]` (SCLK) | Control bus latched at IDLE→OP | `top_ahb_qspi.sgdc:123-170` | Bug-A fix landed; latch is **single-flop, not 2-FF** (`:132-138`). Metastability bounded to a narrow window at IDLE→OP; safety depends on software holding config stable ≥2 HCLK before ENABLE. | **OWNER** — accept-by-convention. The convention is real (the two-write-to-SPI_CMD pattern) but unenforced in hardware. |
| 4 | `ahb_qspi_interface.AHB_QSPI_ADDR` (HCLK) → `qspi_controller.addr_code[21:4]` (SCLK) | Addr loaded at OP-entry | `top_ahb_qspi.sgdc:162-166` | **The SGDC marks this incomplete**: `:164-165` "TODO: add explicit latching regs for ADDR and WDATA (low cost, completes the Bug A fix for the data path)". | **OWNER → fix.** The SGDC's own TODO is the cheapest close-out available. |
| 5 | `HWDATA[31:0]` (HCLK, primary input) → `qspi_controller.QSPI_WDATA_reg[127:0]` (SCLK) | WDATA loaded at OP-entry | `top_ahb_qspi.sgdc:167-170` | Same TODO as #4. Note the source is a **primary input**, so there is no upstream register to argue stability from. | **OWNER → fix.** Highest data-width exposure of the six. |
| 6 | `apb_qspi_regs.reg3[21:0]` (PCLK) → `qspi_controller.last_QSPI_ADDR[21:0]` (SCLK) | Addr-compare, same OP-entry latch family | `top_ahb_qspi.sgdc:166` | Same family as #4. Feeds the continuous-read address-match comparison. | **OWNER** — closes automatically if #4 is fixed. |

Supporting findings from the same document:

- **Infra gap CLOSED** (`:69-71`): `make cdc` now defaults to `cdc/cdc_verify_struct` and
  completes. The full `cdc/cdc_verify` goal **hangs** — `spyglass.out` stops at
  "Checking Rule Ac_cdc01a (Rule 429 of 533)" and never rolls up (`:5-12`). That hang is
  why `spyglass-cdc` is `allow_failure: true` and why no summary artefact existed. **The
  advanced formal `Ac_cdc` metastability rules therefore still do not run on this block.**
- **Sign-off NOT clean** (`:72-76`): "a CDC owner must record an explicit accept/fix
  decision per row before tape-out".
- The 10 `Ac_glitch03` are 2-FF first-stage meta flops with multi-source fan-in — "typical,
  review alongside" (`:62-63`). The 5 `Clock_sync06` are `PRDATA` read-mux multi-domain
  fan-out — expected (`:63-65`). Neither is inventoried per-row here; both are **OWNER**
  review items bundled with the six.

---

## 6. Consolidated checklist

Ordered by risk. Tick as each is dispositioned.

| # | Action | Where | Verdict |
|---|---|---|---|
| ☐ 1 | Stop the Wlink `-du` patterns matching `src/rtl/local_overrides/*` (34 files, incl. the a2l mailbox, `WavMultibitSync_18`, and the FCReplayV2 family) | `tidelink/cdc/waiver.swl:43-51` | OWNER |
| ☐ 2 | Un-gate the sign-off chain: `hal_lint` and `spyglass_cdc` are both `allow_failure: true`, and SpyGlass aborts on SCL-602 | `nanosoc-multicore-system/.gitlab-ci.yml:158, :184` | OWNER |
| ☐ 3 | Decide QSPI six rows #1 (qualifier not found), #4, #5 — the SGDC's own TODO closes #4/#5/#6 | `ahb_qspi/cdc/top_ahb_qspi.sgdc:164-165`; `ahb_qspi/docs/cdc_signoff_status.md:45-52` | OWNER |
| ☐ 4 | Un-waive the eight locally-patched units now excluded as "third-party-IP" — `tsu`, `eth_wishbone` first | `ethernet-subsystem-ahb/cdc/waiver.swl:140-141, :150-156`; `ethernet-mac-ahb/cdc/waiver.swl:44-45, :54-60` | OWNER |
| ☐ 5 | Remove or file-scope the global `checkSGDC_05` waiver — it is the unmatched-`abstract_port` detector | `tidelink/cdc/waiver.swl:133` | REMOVE |
| ☐ 6 | Replace blanket `-nocheck` on CLKDMN/INSYNC/GLTASR/MLTDRV with file-scoped `hal_design_info.txt` entries | `nanosoc-multicore-system/lint/hal.tcl:157,158,161,182`; `ahb_qspi/lint/hal.tcl:128` | NARROW |
| ☐ 7 | Add a `SIGNOFF_RULES` preflight to the unit lint Makefiles, and run `merge_hal_rules.py --check` in CI | `verif/lint/full/hal_lint.sh:54-61`; `nanosoc-multicore-system/lint/Makefile:109`; `ahb_qspi/lint/Makefile:46` | OWNER |
| ☐ 8 | Resolve the `Ac_cdc` advanced-formal hang so metastability rules actually run on QSPI | `ahb_qspi/docs/cdc_signoff_status.md:5-12` | OWNER |
| ☐ 9 | Fix `MODULE`-independent `SGDC`/`SWL` — block-level runs silently use the SoC's constraints | `nanosoc-multicore-system/cdc/Makefile:76-77` | OWNER |
| ☐ 10 | Qualify the generic `-du` names `{reg}`, `{rtc}`, `static_reg`, `cdc_capt_sync` | `ethernet-subsystem-ahb/cdc/waiver.swl:151,155`; `ahb_qspi/cdc/waiver.swl:49,51` | NARROW |
| ☐ 11 | Verify or delete the "single-clock by design" bridge waivers — if the claim holds they are unnecessary | `ethernet-subsystem-ahb/cdc/waiver.swl:171-173`; `ethernet-mac-ahb/cdc/waiver.swl:74-76` | NARROW |
| ☐ 12 | Re-scope `Ac_unsync02` on `*pad_rx*` from a loose glob to the specific instance | `tidelink/cdc/waiver.swl:101` | NARROW |
| ☐ 13 | Drop `quasi_static` on the I2C lines — they are async, not quasi-static; `waiver.swl:97-98` already models them correctly | `tidelink/cdc/tidelink_top.sgdc:129-130` | NARROW |
| ☐ 14 | Declare `clk`/`resetn` in `tidechart.sgdc` and delete the `Setup_clockreset01` waiver | `tidechart/cdc/waiver.swl:9` | NARROW |
| ☐ 15 | De-duplicate the 36 shared rows between the eth-ss and MAC waiver files (already drifted) | `ethernet-subsystem-ahb/cdc/waiver.swl` vs `ethernet-mac-ahb/cdc/waiver.swl` | NARROW |
| ☐ 16 | Add `amba_wb_bridges/lint/hal.tcl` to the merge unit list | `verif/lint/full/merge_hal_rules.py:34-42` | NARROW |
| ☐ 17 | Fix the three self-contradicting comments that assert rules are unwaived while waiving them | `lint/hal.tcl:209-211, :377-379`; `hal_design_info.txt:64-66` | REMOVE |
| ☐ 18 | Record the `stop_module` black-boxing as a waiver-equivalent in review — it suppresses more than any `waive` line | `tidelink/cdc/tidelink_top.prj:50` | KEEP (document) |
| ☐ 19 | **The eth-ss block CDC run targets a module that no longer exists.** `current_design ethernet_ss_ahb` and `MODULE ?= ethernet_ss_ahb`, but no `module ethernet_ss_ahb` is in the RTL or in `flist/ethernet_ss_ahb_common.flist` — the built top is `ethernet_ss_ahb_rmii`. Its `mtx_clk_i`/`mrx_clk_i` clock declarations are the same stale MII boundary corrected at SoC level in `nanosoc_multicore_soc.sgdc`. So all 116 waivers in §3.2 are being applied to a run whose elaboration top is wrong. | `ethernet-subsystem-ahb/cdc/ethernet_ss_ahb.sgdc:19, :32-35`; `ethernet-subsystem-ahb/cdc/Makefile:11` | OWNER |
