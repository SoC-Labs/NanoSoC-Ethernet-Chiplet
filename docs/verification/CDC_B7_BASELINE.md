# B7 — Chiplet-level SpyGlass CDC baseline (first ever run)

**Date:** 2026-08-17 · **Author:** B7 measurement pass · **Status:** RUN COMPLETED, exit code 0

This is the first time `cdc/nanosoc_eth_chiplet.{sgdc,prj}` has been through a tool.
It replaces a pass that hid 2,569 reset/clock-domain findings behind an eight-code
reporting regex, and it deliberately inherits **none** of the nine block-level waiver
files.

**Headline: 885 messages → 152 unsynchronised crossings → 50 deduplicated findings.
Of those 50, 5 (10%) are real crossings needing an engineering decision. 26 (52%) are
setup artefacts — declaration bugs in the brand-new `.sgdc`, not design bugs.**

The single most useful number in this document is that ratio. A first run against a
fresh SGDC is mostly measuring the SGDC.

---

## 1. Invocation

```bash
export CHIPLET=${CHIPLET_HOME}
export SPYGLASS_HOME=${SPYGLASS_HOME}

source $CHIPLET/set_env.sh
source $CHIPLET/nanosoc-multicore-system/set_env.sh
source $CHIPLET/tidelink/set_env.sh

export FLIST=$CHIPLET/build/cdc/b7/run-20260817/nanosoc_eth_chiplet_b7.flist
export SG_TOP=nanosoc_eth_chiplet
export SGDC=$CHIPLET/cdc/nanosoc_eth_chiplet.sgdc
export SWL=$CHIPLET/cdc/waiver.swl

timeout --signal=TERM --kill-after=60 5700 \
  $SPYGLASS_HOME/bin/spyglass -batch \
      -project $CHIPLET/build/cdc/b7/run-20260817/nanosoc_eth_chiplet_b7.prj \
      -goals "cdc/cdc_verify_struct" < /dev/null
```

Reproduce with `build/cdc/b7/run-20260817/run2.sh`.

| | |
|---|---|
| Tool | SpyGlass Predictive Analyzer, **T-2022.06-SP2** for linux64 (Nov 29 2022) |
| Goal | `cdc/cdc_verify_struct` — **structural only** |
| Exit code | **0** ("Rule-checking completed with errors") |
| Analysis time | **48 s** (wall clock ~80 s) |
| Peak memory | 1.93 GB |
| Flat instances | 212,065 |
| Licence | released cleanly; no seat held (`< /dev/null` on every invocation) |

The full `cdc/cdc_verify` goal was **not** run. It is documented in
`nanosoc-multicore-system/ahb_qspi/docs/cdc_signoff_status.md` as not terminating in
batch on this design (hangs at rule 429/533). The structural goal terminates in 48
seconds, so the 90-minute time-box was never approached.

### What the inputs were

`cdc/nanosoc_eth_chiplet.sgdc`, `cdc/waiver.swl` (zero waive statements) and
`cdc/nanosoc_eth_chiplet.prj` were used **unmodified** — they are the reviewable
inputs and were not edited. Two run-local copies were made instead, both under
`build/cdc/b7/run-20260817/`:

- **`nanosoc_eth_chiplet_b7.prj`** — byte-identical to `cdc/nanosoc_eth_chiplet.prj`
  plus exactly two appended options (§2).
- **`nanosoc_eth_chiplet_b7.flist`** — the flattened `flist/nanosoc_eth_chiplet_asic.flist`
  (597 source files, all resolving) with exactly **one** path substituted (§2).

Clock periods resolved as declared: 16 clocks, 9 domains, 6 resets, 7
`set_case_analysis`, 10 `quasi_static`. **No clock failed to bind and no inferred or
virtual clocks were created**, which is a good setup-health signal — every clock in the
SGDC matched a real object.

---

## 2. Two blockers had to be cleared before the run produced anything

The first attempt (`run.sh`, log `spyglass_run.log`) **died at exit code 6 after 26
seconds with 6 FATALs, before a single CDC rule ran.** Both causes are tool-strictness
issues, not design defects. Anyone re-running this will hit them, so they are recorded
in full.

### 2a. Five duplicate module definitions (`STX_VE_589`) — fixed by an option

SpyGlass makes a duplicate module definition FATAL; VCS reports the same condition as a
benign `Warning-[OPD]`, which `flist/nanosoc_eth_chiplet_asic.flist:17-21` already
documents as "NOT an error and NOT introduced by this integration".

All five colliding pairs were checked and are **byte-identical**, so `allow_module_override`
(last definition wins) is provably a no-op on the elaborated netlist:

| Module | Why two copies | Verified |
|---|---|---|
| `cmsdk_ahb_to_sram` | `CMSDK_DIR` points at Corstone-101 BP210 while `CMSDK_FPGA_SRAM_V` falls back to the standalone BP210 install (`tidelink/cdc/Makefile:5-11`) | md5 `26937f95…` on both |
| `xhb500_flop`, `xhb500_or`, `xhb500_sync`, `xhb500_xor` | per-instance generated copies under `tidelink/deps/xhb500/generated/xhb_chiplet_{mst,slv}/` | `diff` clean pairwise |

→ `set_option allow_module_override yes` in the run-local `.prj`.

### 2b. A constant function inside a generate block (`STX_VE_810`) — needed an RTL override

```
STX_VE_810  tidelink/src/rtl/local_overrides/WavD2DGpioRx_v2.v:960
  Non-constant expression ( wpa_bitrev16(TRAINING_WORD16) ) specified where only
  constant expressions are allowed
```

No tool option fixes this. `allow_fatal_downgrade` applies only to SGDC rules, not
syntax fatals; `allow_non_lrm` is SPEF-only.

Root cause was isolated with a 20-line micro-probe (`build/cdc/b7/run-20260817/probe/`):

| Probe variant | Result |
|---|---|
| function declared **inside** `generate`, `.v` | **FATAL** rc=6 |
| same, `.sv` extension | **FATAL** rc=6 |
| same, under `enableSV` / `enableSV09` / `enableSV12` | **FATAL** rc=6 |
| function **hoisted to module scope**, `.v` | **clean, rc=0** |

So it is not a Verilog-vs-SystemVerilog parse-mode issue: **SpyGlass 2022.06-SP2 cannot
evaluate a constant function that is declared inside a generate block.**

The fix is a run-local copy of the file at
`build/cdc/b7/run-20260817/local_overrides/WavD2DGpioRx_v2.v` with `wpa_bitrev16`
hoisted to module scope. This was **proven to be pure code motion**: stripping comments
and blank lines, the sorted code-line multisets of the two files are identical. The
function takes its operand as an argument and captures nothing from generate scope, so
hoisting is semantics-preserving and CDC-neutral.

`tidelink/` was **not** modified. The substitution is made in the run-local flist only.

> **Upstream fix wanted:** hoist `wpa_bitrev16` out of `g_word_pin_auto` in
> `tidelink/src/rtl/local_overrides/WavD2DGpioRx_v2.v` so the RTL is SpyGlass-clean and
> this override can be deleted.

### A trap worth recording

With `-project` and no `projectwdir`, SpyGlass writes its work tree **next to the
`.prj`** — i.e. into the reviewable `cdc/` directory. `-work_dir` is rejected outright
(`FATAL [SPG#2001]: Unsupported option "-work_dir" specified with -project`). Use
`set_option projectwdir`. The stray tree from attempt 1 was relocated to
`build/cdc/b7/run-20260817/attempt1_workdir`; the four files in `cdc/` are untouched.

---

## 3. What was black-boxed

Exactly as the reviewed `.prj` specifies — **nothing was added or removed**, and
`axi_chiplet_controller` was deliberately left stopped (un-black-boxing it is step B8, a
separate change).

| Stopped module | Instances | Pins |
|---|---|---|
| `axi_chiplet_controller` | 1 | 1667 |
| `xhb500_ahb_to_axi_bridge_chiplet_slv` / `..._mst` | 1 each | 423 each |
| `rf_01k` / `rf_08k` / `rf_16k` / `rf_32k` | 1 / 4 / 3 / 1 | ~113–118 |

`CM0PDAP` and `CORTEXM0PLUS` were left **elaborated**, per the SGDC's reasoning. This
paid off: the run recognised 35 CoreSight DAP synchronisers it would otherwise have
collapsed (§6).

A further **8 modules black-boxed themselves** because no Verilog model is in any
filelist this build reads (`ErrorAnalyzeBBox`, severity Error):

`flash_cache_data`, `flash_cache_tag`, `rf_01k`, `rf_08k`, `rf_16k`, `rf_32k`,
`eth_rom_via`, `rom_via`.

Four of these (`rf_*`) are on the stop list already. **`flash_cache_data`,
`flash_cache_tag`, `eth_rom_via` and `rom_via` are not** — they are inferred black
boxes with no `abstract_port` at all, which is precisely the configuration the SGDC's
own preamble warns manufactures crossings that do not exist. They produced no crossing
in this run, but they are an unguarded hole.

### `Setup_blackbox01` reports "0.00% unconstrained" and it does not mean what it says

All 24 black-box instances report **0.00% of pins unconstrained** — and the rule is
`Info`, not a violation. Yet §6 finding group A proves that five `axi_chiplet_controller`
output pins have no constraint and were silently defaulted onto `user_ref_clk`.

**SpyGlass counts a pin as "constrained" once it has a resolved domain — including a
domain it made up.** This metric cannot distinguish a declared port from a defaulted
one, so a green `Setup_blackbox01` is not evidence that the black-box constraints are
right. Do not use it as a gate.

---

## 4. Counts

### 4a. Raw message counts, by rule and severity

885 messages: **175 Error, 92 Warning, 618 Info.** No fatals.

| Rule | n | Severity | Class |
|---|---:|---|---|
| `Clock_info03b` | 253 | Info | clock/domain census |
| `Ac_unsync01` | 96 | **Error** | **unsynchronised scalar crossing** |
| `checkSGDC_05` | 77 | Info | SGDC echo |
| `Ac_sync01` | 72 | Info | *recognised* scalar synchroniser |
| `Ac_sync02` | 65 | Info | *recognised* vector synchroniser |
| `Ac_unsync02` | 56 | **Error** | **unsynchronised vector crossing** |
| `Ac_coherency06` | 41 | Warning | multi-synchronised control signal |
| `Reset_info01` | 36 | Info | reset census |
| `Ar_sync01` | 27 | Info | *recognised* reset synchroniser |
| `Ar_syncdeassert01` | 27 | Info | reset with synchronous deassertion |
| `Setup_blackbox01` | 24 | Info | black-box port coverage (see §3) |
| `Reset_sync04` | 14 | Warning | reset synchronised twice in one domain |
| `Ac_conv02` | 12 | Warning | combinational convergence |
| `Ac_glitch03` | 9 | **Error** | glitch on synchronised control path |
| `ErrorAnalyzeBBox` | 8 | **Error** | module with no definition |
| `Clock_info01`, `Propagate_Clocks` | 8, 8 | Info | setup |
| `Ac_conv01` | 7 | Warning | sequential convergence |
| `Clock_check10` | 7 | Warning | — |
| `Propagate_Resets` | 6 | Info | setup |
| `Reset_sync02` | 5 | **Error** | **reset generated from a different domain** |
| `Ac_conv04` | 5 | Warning | non-converging bus |
| `WRN_1024` | 3 | Warning | — |
| `Ar_unsync01` | 1 | **Error** | **async reset with no synchroniser** |
| `Clock_check07` | 1 | Warning | multi-definition on clock |
| 12 further rules | 1–3 each | Info | setup/census |

**Critically, 618 of the 885 (70%) are Info, and 191 of those Infos are the tool
reporting synchronisers it successfully recognised** (`Ac_sync01` 72 + `Ac_sync02` 65 +
`Ar_sync01` 27 + `Ar_syncdeassert01` 27). Those are good news, not findings. Quoting
"885 CDC findings" would be wrong by an order of magnitude.

### 4b. Deduplicated finding count

**Dedup method, stated explicitly:**

1. **Source of truth is the per-rule CSVs**, not the message log. For every rule,
   `rows == unique IDs == the count in `CDC-report.rpt``, verified programmatically. So
   SpyGlass has *already* collapsed each crossing to one row carrying the full flat
   hierarchical path of source and destination. There is **no multi-hierarchy-level
   duplication left to remove** — the classic "same crossing reported at three levels"
   problem does not arise in this report format.
2. **Bit-select normalisation.** Trailing `[n]` / `[n:m]` stripped from source and
   destination names, so a bus reported per-bit collapses to one bus.
3. **Cross-rule collapse.** A crossing appearing under more than one rule is counted
   once, keeping the most severe. 13 signals appear under 2–4 rules
   (e.g. `MODER_1.DataOut` under `Ac_unsync01`, `Ac_unsync02`, `Ac_coherency06` **and**
   `Ac_conv04`).
4. **Fan-out collapse.** One source driving many destinations is **one finding**, because
   one mis-declared source generates all of them and one fix retires all of them. This is
   the number that prices the workstream.

| Level | Count |
|---|---:|
| Raw messages | 885 |
| — of which Info (census + recognised synchronisers) | 618 |
| Unsynchronised crossing rows (`Ac_unsync01` + `Ac_unsync02`) | **152** |
| Unique (source, destination) pairs after bit-normalisation | 150 |
| **Unique source signals — the deduplicated finding count** | **50** |
| Distinct clock-domain pairs involved | **13** |

**152 raw crossings deduplicate to 50 findings — a 3.0× fan-out.**

Other violation classes, deduplicated the same way: `Ac_coherency06` 41,
`Reset_sync04` 14, `Ac_conv02` 12, `Ac_glitch03` 9, `Ac_conv01` 7, `Ac_conv04` 5,
`Reset_sync02` 5, `Ar_unsync01` 1, `Clock_check07` 1. These overlap heavily with the 50
(13 signals confirmed shared) and are **not** additive.

### 4c. Where the 152 crossings live

| Source domain → destination domain | Crossings |
|---|---:|
| `sys_fclk` → `mrx_clk` | 44 |
| `dap_swclktck` → `sys_fclk` | 33 |
| `sys_fclk` → `mtx_clk` | 30 |
| `sys_fclk` → `rtc_clk` | 24 |
| `user_ref_clk` → `sys_hclk` | 5 |
| `mrx_clk`/`mtx_clk` → `sys_fclk` | 3 + 3 |
| `sys_fclk` → `qspi_sclk` | 3 |
| `rtc_clk` → `sys_fclk` | 2 |
| `sys_fclk` → `user_ref_clk` | 2 |
| `qspi_sclk` → `sys_fclk` | 1 |
| `sys_hclk` → `pad_clk_tx` | 1 |
| `pad_clk_rx` → `sys_hclk` | 1 |

**131 of 152 (86%) sit in just four domain pairs.** Note also what is *absent*: there
are **zero `mtx_clk` ↔ `mrx_clk` crossings**, which confirms the SGDC's decision
(README §4.6) to put both MII clocks in one `rmii_domain` was correct and did not mask
anything.

### 4d. Why the crossings are unsynchronised — the most diagnostic number here

| Reason | n | % |
|---|---:|---:|
| Qualifier not found | 82 | 54% |
| Qualifier merges with another source with non-deterministic enable condition | 43 | 28% |
| Sync reset used in multi-flop synchronizer | 7 | 5% |
| Qualifier merges with the same source before gating logic | 5 | 3% |
| Destination instance is driving multiple paths | 4 | 3% |
| Gating logic not accepted: source drives MUX select input | 4 | 3% |
| Gating logic not accepted: only sources drive MUX data inputs | 4 | 3% |
| Qualifier not accepted / gate-type invalid | 3 | 2% |

**125 of 152 (82%) are qualifier-related** — the crossing *is* gated by a control
signal, but the setup gives SpyGlass nothing to validate that gating against. The
report confirms it: **"User-defined qualifiers used to synchronize data crossings: 0"**.
The SGDC declares no `qualifier` at all.

For contrast, the tool *did* recognise 137 synchronised crossings by five distinct
methods — 66 conventional multi-flop, 35 mux-select sync, 22 AND-gate sync, 11
enable-based, 3 via an inferred qualifier. The setup is producing real analysis, not
noise.

---

## 5. Triage sample — all 50 deduplicated findings

**Time taken: 3 min 42 s** (18:13:41 → 18:17:23), covering all 50 findings and seven
targeted RTL evidence lookups (§6). Recorded honestly, with the caveat that this is
agent wall-clock on a machine with the RTL already indexed; a human doing the same
adjudication with the same evidence would be slower, and the seven RTL lookups are the
part that does not compress. The reason it is this fast is structural: the 50 findings
collapse into **nine mechanism groups**, and once a group's root cause is proven from
RTL, every member of that group classifies immediately.

| # | Source signal | Xings | Domains | Class |
|---|---|---:|---|---|
| 1 | `u_tidelink.scan_out` | 1 | user_ref_clk→sys_hclk | **SETUP** |
| 2 | `u_tidelink.i2c_sda_t` | 1 | user_ref_clk→sys_hclk | **SETUP** |
| 3 | `u_tidelink.i2c_sda_o` | 1 | user_ref_clk→sys_hclk | **SETUP** |
| 4 | `u_tidelink.i2c_scl_t` | 1 | user_ref_clk→sys_hclk | **SETUP** |
| 5 | `u_tidelink.i2c_scl_o` | 1 | user_ref_clk→sys_hclk | **SETUP** |
| 6 | `<ethmac>.u_eth_top.wishbone.ShiftEnded_rck` | 1 | mrx_clk→sys_fclk | **LEGIT** |
| 7 | `<ethmac>.u_eth_top.ethreg1.SetTxCIrq_txclk` | 1 | mtx_clk→sys_fclk | **LEGIT** |
| 8 | `<ethmac>.u_ha1588.u_rgs.time_rd_s2` | 1 | rtc_clk→sys_fclk | **LEGIT** |
| 9 | `<dap>.…sw_dp_protocol.ap_sel` | 25 | dap_swclktck→sys_fclk | **LEGIT** |
| 10 | `<dap>.…sw_dp_protocol.ibuswdata_cdc_check` | 6 | dap_swclktck→sys_fclk | **LEGIT** |
| 11 | `<ethmac>.u_eth_top.ethreg1.MODER_1.DataOut` | 17 | sys_fclk→mrx/mtx | **SETUP** |
| 12 | `<ethmac>.u_eth_top.ethreg1.MODER_0.DataOut` | 8 | sys_fclk→mrx/mtx | **SETUP** |
| 13 | `<ethmac>.u_eth_top.ethreg1.COLLCONF_2.DataOut` | 5 | sys_fclk→mtx_clk | **SETUP** |
| 14 | `<ethmac>.u_eth_top.ethreg1.MODER_2.DataOut` | 1 | sys_fclk→mrx_clk | **SETUP** |
| 15 | `<ethmac>.u_eth_top.ethreg1.CTRLMODER_0.DataOut` | 4 | sys_fclk→mrx/mtx | **SETUP** |
| 16 | `<ethmac>.u_eth_top.ethreg1.PACKETLEN_0.DataOut` | 14 | sys_fclk→mrx_clk | **SETUP** |
| 17 | `<ethmac>.u_eth_top.wishbone.SyncRxStartFrm_q` | 1 | sys_fclk→mrx_clk | **VENDOR** |
| 18 | `<ethmac>.u_eth_top.wishbone.ShiftEndedSync2` | 1 | sys_fclk→mrx_clk | **LEGIT** |
| 19 | `<ethmac>.u_eth_top.wishbone.RxReady` | 5 | sys_fclk→mrx_clk | **VENDOR** |
| 20 | `<ethmac>.u_eth_top.wishbone.TxUnderRun_wb` | 1 | sys_fclk→mtx_clk | **VENDOR** |
| 21 | `<ethmac>.u_eth_top.RxAbort_wb` | 1 | sys_fclk→mrx_clk | **VENDOR** |
| 22 | `<ethmac>.u_eth_top.ethreg1.SetTxCIrq_sync1` | 1 | sys_fclk→mtx_clk | **LEGIT** |
| 23 | `<ethmac>.u_eth_top.ethreg1.SetTxCIrq_sync2` | 1 | sys_fclk→mtx_clk | **LEGIT** |
| 24 | `<ethmac>.u_eth_top.ethreg1.PACKETLEN_2.DataOut` | 2 | sys_fclk→mtx_clk | **SETUP** |
| 25 | `<ethmac>.u_eth_top.ethreg1.IPGR2_0.DataOut` | 1 | sys_fclk→mtx_clk | **SETUP** |
| 26 | `<ethmac>.u_eth_top.ethreg1.COLLCONF_0.DataOut` | 2 | sys_fclk→mrx/mtx | **SETUP** |
| 27 | `<ethmac>.u_eth_top.ethreg1.MAC_ADDR0_0.DataOut` | 2 | sys_fclk→mrx/mtx | **SETUP** |
| 28 | `<ethmac>.u_ha1588.u_rgs.reg_44` | 1 | sys_fclk→mrx_clk | **SETUP** |
| 29 | `<ethmac>.u_ha1588.u_rgs.reg_64` | 1 | sys_fclk→mtx_clk | **SETUP** |
| 30 | `u_soc.u_network_core.u_sys_hresetn_i_resetsync.sync_q` | **19** | sys_fclk→mrx_clk,rtc_clk | **REAL** |
| 31 | `<qspi>.u_qspi_controller.current_state` | 1 | sys_fclk→qspi_sclk | **SETUP** |
| 32 | `…u_cpu_0.u_core_prmu.u_rstctrl.u_sys_hresetn_sync.rst_sync2_n` | 1 | sys_fclk→user_ref_clk | **REAL** |
| 33 | `…u_cpu_0.u_core_prmu.u_rstctrl.u_sys_poresetn_sync.rst_sync2_n` | 1 | sys_fclk→user_ref_clk | **REAL** |
| 34 | `<ethmac>.u_ha1588.u_rgs.time_reg_sec_int` | 1 | rtc_clk→sys_fclk | **LEGIT** |
| 35 | `<ethmac>.u_ha1588.u_tx_tsu.queue.mem[15:0]` | 2 | mtx_clk→sys_fclk | **LEGIT** |
| 36 | `<ethmac>.u_ha1588.u_rx_tsu.queue.mem[15:0]` | 2 | mrx_clk→sys_fclk | **LEGIT** |
| 37 | `qspi_io_i` | 1 | qspi_sclk→sys_fclk | **SETUP** |
| 38 | `<dap>.…sw_dp_protocol.ap_bank_sel` | 2 | dap_swclktck→sys_fclk | **LEGIT** |
| 39 | `<ethmac>.u_eth_top.wishbone.tx_fifo.fifo[15:0]` | 1 | sys_fclk→mtx_clk | **VENDOR** |
| 40 | `<ethmac>.u_eth_top.wishbone.RxOverrun` | 1 | sys_fclk→mrx_clk | **VENDOR** |
| 41 | `<ethmac>.u_eth_top.wishbone.RxPointerLSB_rst` | 1 | sys_fclk→mrx_clk | **VENDOR** |
| 42 | `<ethmac>.u_ha1588.u_rgs.reg_14` | 1 | sys_fclk→rtc_clk | **SETUP** |
| 43 | `<ethmac>.u_ha1588.u_rgs.reg_18` | 3 | sys_fclk→rtc_clk | **SETUP** |
| 44 | `<ethmac>.u_ha1588.u_rgs.reg_2c` | 1 | sys_fclk→rtc_clk | **SETUP** |
| 45 | `<ethmac>.u_ha1588.u_rgs.reg_30` | 1 | sys_fclk→rtc_clk | **SETUP** |
| 46 | `<ethmac>.u_ha1588.u_rgs.reg_24` | 1 | sys_fclk→rtc_clk | **SETUP** |
| 47 | `<qspi>.u_qspi_controller.qspi_qio_mode_latched` | 1 | sys_fclk→qspi_sclk | **SETUP** |
| 48 | `<qspi>.u_qspi_controller.QSPI_IO_o_reg` | 1 | sys_fclk→qspi_sclk | **SETUP** |
| 49 | `u_tidelink.pad_tx` | 1 | sys_hclk→pad_clk_tx | **REAL** |
| 50 | `pad_rx` | 1 | pad_clk_rx→sys_hclk | **REAL** |

### Classification breakdown

| Class | Findings | % of 50 | Raw crossings | % of 152 |
|---|---:|---:|---:|---:|
| **Setup artefact** — wrong/missing declaration in the `.sgdc` | **26** | **52%** | 74 | 49% |
| **Legitimate synchroniser** the tool should have recognised | **12** | **24%** | 44 | 29% |
| **Vendor-IP noise** | **7** | **14%** | 11 | 7% |
| **Real crossing needing a fix or an explicit decision** | **5** | **10%** | 23 | 15% |

---

## 6. The evidence behind the classifications

Nine mechanism groups, each proven from RTL rather than inferred.

### A. Findings 1–5 — black-box output pins with no `abstract_port` → **SETUP** *(proven)*

`i2c_scl_o`, `i2c_sda_o`, `i2c_scl_t`, `i2c_sda_t` and `scan_out` are driven directly by
the black-boxed controller instance
(`tidelink/src/rtl/tidelink_top.sv:3028-3040` → `u_chiplet_controller`). The SGDC's §7a
`axi_chiplet_controller` block declares `i2c_nbsy_irq` but **not these five**. With no
`abstract_port`, SpyGlass defaulted them to `user_ref_clk`; the chiplet-top declaration
says `sys_hclk` (`cdc/nanosoc_eth_chiplet.sgdc:539-542,553`), so the tool sees a
`user_ref_clk → sys_hclk` crossing that does not exist.

**This is a recurrence of the exact failure documented in `cdc/README.md` §4.4** — where
three renamed ports defaulted to `user_ref_clk` and manufactured two spurious crossings.
It has now happened on five more ports of the same block. *Fix: add five
`abstract_port` lines to §7a.*

### B. Findings 31, 37, 47, 48 — `qspi_sclk` is not an independent domain → **SETUP** *(proven)*

`nanosoc-multicore-system/ahb_qspi/logical/qspi_controller/logical/qspi_clock_div.v:10`:

```verilog
assign QSPI_SCLK_i = (QSPI_CLK_DIV==5'h00) ? HCLK : QSPI_SCLK_reg;
```

and `QSPI_SCLK_reg` toggles inside `always @(posedge HCLK)`. **QSPI_SCLK is a
synchronously-derived divided clock off HCLK**, exactly as the chip SDC says
(`qspi_constraints.sdc:2`, `QSPI_SCLK = clk ÷ 2`). The SGDC declares it as an
independent `qspi_domain` (`cdc/nanosoc_eth_chiplet.sgdc:184`), which manufactures all
four crossings. *Fix: declare it a generated clock inside `sys_fclk_domain`.* Finding
37 (`qspi_io_i`) is the pad return path — source-synchronous and STA-timed, not a
metastability risk.

### C. Findings 9, 10, 38 — CoreSight DP→AP bus, qualified handshake → **LEGIT** *(strong evidence)*

33 of the 152 crossings are `ap_sel` / `ap_bank_sel` / `ibuswdata` from
`dap_swclktck` into `sys_fclk`. In the same block SpyGlass **already recognised 35
synchronisers** (`Ac_sync01` 20 + `Ac_sync02` 15), including
`u_cxdapswjdp_dp_apb_sync.u_sync_bus_req.sync_reg` and `…u_sync_bus_abort.sync_reg`.
These three are the DP→AP address/data bus qualified by that `busreq`/`busack`
handshake — the classic "data bus held stable by a synchronised request" pattern. The
tool's reasons are `Gating logic not accepted: source drives MUX select input` and
`Qualifier merges with another source with non-deterministic enable condition`, i.e. it
found gating but had no `qualifier` declaration to validate it against. *Fix: declare
the `busreq`/`busack` qualifier.* One declaration retires 33 crossings.

### D. Findings 35, 36 — HA1588 TSU gray-code async FIFO → **LEGIT** *(proven)*

`…/ha1588_patches/ptp_queue.v` is a textbook gray-code async FIFO: binary+gray write and
read pointers (`wr_gray`, `rd_gray`, `x ^ (x>>1)`) with explicit 2-FF cross-domain
pointer synchronisers (`wr_gray_rd1`/`wr_gray_rd2`), header comment "implements a
generic async FIFO using gray-code". The flagged objects are the FIFO **memory array**,
which is safe by construction. The goal runs with `-fa_disable_sync_fifo:yes`, which
disables the tool's FIFO recognition. *Fix: a qualifier or a targeted waiver.*

### E. Findings 11–16, 24–29, 42–46 — static configuration registers → **SETUP** *(needs a software contract)*

OpenCores EthMAC configuration registers (`MODER`, `COLLCONF`, `PACKETLEN`,
`CTRLMODER`, `IPGR2`, `MAC_ADDR0`) and HA1588 register-file entries, written by the
fabric and read continuously in the MII/RTC domains. These are static after
configuration and are the textbook `quasi_static` case.

**They are not waived anywhere today.** I checked `ethmac_ahb.sgdc`,
`ethmac_subsystem_apb.sgdc` and `ethernet_ss_ahb.sgdc`: none declares any of these
`quasi_static`, and none declares a qualifier — the only `quasi_static` in the three
files is `sys_testmode`/`sys_scanenable`. So this class has never been adjudicated at
*any* level, block or integration. Classifying it SETUP asserts that the right fix is a
declaration, **but that declaration is a claim about software** ("configure before
enable"), and it needs an owner's sign-off, not a silent waiver.

### F. Findings 17, 19, 20, 21, 39, 40, 41 — EthMAC internal control/status → **VENDOR**

`RxReady`, `RxAbort_wb`, `RxOverrun`, `TxUnderRun_wb`, `SyncRxStartFrm_q`,
`RxPointerLSB_rst`, `tx_fifo.fifo` — OpenCores EthMAC's own cross-domain control logic,
reported mostly as "qualifier merges with the same source" / "non-deterministic enable".
Long-standing third-party RTL with its own ad-hoc synchronisation. Low value to chase at
integration level; needs a block-level decision if the MAC is ever signed off.

### G. Findings 6, 7, 18, 22, 23, 8, 34 — synchroniser chains flagged on their own stages → **LEGIT**

`ShiftEnded_rck → ShiftEndedSync1 → ShiftEndedSync2` and
`SetTxCIrq_txclk → SetTxCIrq_sync1 → SetTxCIrq_sync2` are genuine 2-FF synchronisers;
the tool flags them with `Destination instance is driving multiple paths` because the
first stage fans out. Findings 8 and 34 are the HA1588 time-capture handshake
(`time_rd_s2` → `time_ok`). Real synchronisation, tool pessimism about fan-out.
*Note: sync-stage fan-out is worth a look — reconvergence off a first sync stage is a
genuine (if lower-severity) concern.*

### H. Findings 30, 32, 33 — reset-domain crossings → **REAL** *(highest value in the sample)*

`soc_glue_reset_sync.sv:30-51` is a textbook async-assert / sync-deassert reset
synchroniser. Finding **30 is the single biggest finding in the run — 19 crossings from
one source**: the synchronised reset `sync_q`, produced in the `sys_fclk` domain, fans
out into `mrx_clk` and `rtc_clk` flops **without being re-synchronised into those
domains**. Its deassertion edge is asynchronous to those clocks. Findings 32 and 33 are
the same mechanism from the Cortex-M0+ PRMU reset synchronisers into `user_ref_clk`.

This is corroborated independently by `Reset_sync02` (5 Errors, "asynchronous resets
generated from a different domain"), which names
`u_soc.u_network_core.sys_hresetn_eff` (sys_fclk→mtx_clk),
`u_ha1588.rx_q_rst_combined` (sys_fclk→mrx_clk), `tx_q_rst_combined`
(sys_fclk→mtx_clk), `u_ethmac_0.u_inner.ha_rst` (sys_fclk→rtc_clk) and
`role_locked_o` (app_clk→link_rx_clk_o).

**Recommend this group is triaged first.** It is a coherent, real, multi-domain
reset-distribution question, and it is invisible to every block-level file because it
only exists once the blocks are wired together — precisely the class of finding this
setup was built to expose.

### I. Findings 49, 50 — D2D PHY source-synchronous pads → **REAL (by design)**

`u_tidelink.pad_tx` (sys_hclk→pad_clk_tx) and `pad_rx` (pad_clk_rx→sys_hclk) are the
GPIO PHY's source-synchronous data paths. Genuine crossings, intentionally timed by SDC
rather than synchronised. They need an explicit `cdc_false_path` with a written
justification — not a silent waiver.

### Separately: one repo-owned reset finding outside the 50

`Ar_unsync01` (1 Error) flags `u_d2d_decode.dph_code[0]`, reason **"Missing
synchronizer"**. `src/rtl/nanosoc_eth_chiplet.sv` connects `u_d2d_decode.hresetn` to the
**raw top-level `sys_hresetn`** pad, and `src/rtl/chiplet_d2d_decode.sv:179-180` uses it
as an async clear on `sys_hclk` flops. It is the only such flop group in the design —
`Ar_sync01`/`Ar_syncdeassert01` found 27 resets that *do* have synchronisers. **This is
this repository's own integration RTL** and deserves a look.

---

## 7. Honest assessment — how much is setup artefact vs real

**About half the finding set is a declaration bug, and roughly one finding in ten is a
real design question.**

- **26/50 (52%) are setup artefacts** — five missing `abstract_port` lines on a black
  box, a wrongly-split QSPI clock domain, and a large block of static configuration
  registers with no `quasi_static` declaration.
- **12/50 (24%) are real synchronisers the tool could not validate**, essentially all
  because **the SGDC declares zero qualifiers** while 82% of the unsynchronised
  crossings are qualifier-related. One qualifier declaration on the CoreSight DP→AP
  handshake retires 33 of 152 crossings on its own.
- **7/50 (14%) are third-party EthMAC noise.**
- **5/50 (10%) are real** — and they concentrate almost entirely in one mechanism:
  **reset distribution across domains** (findings 30/32/33, 21 crossings), plus the two
  D2D pad paths.

So **76% of the sample (setup + unrecognised-synchroniser) is fixed by editing
`cdc/nanosoc_eth_chiplet.sgdc`, not by touching RTL.** The count will fall steeply on
the second run, and that fall is not progress on the design — it is the setup
converging. Do not report it as bugs fixed.

### What this re-prices

The finding set is much smaller and much more structured than a raw count suggests:
885 messages → 152 crossings → **50 findings → 9 mechanism groups**. The work is
group-shaped, not finding-shaped. A realistic ordering:

1. **Reset distribution (group H + `Ar_unsync01` + `Reset_sync02`)** — the only genuinely
   open design question in the sample. Do this first, before the count is cosmetically
   reduced by declaration fixes.
2. **Five `abstract_port` lines** (group A) — minutes, and it closes a recurrence of an
   already-documented bug.
3. **QSPI generated-clock declaration** (group B) — one clock declaration, 4 crossings.
4. **CoreSight qualifier declaration** (group C) — one declaration, 33 crossings.
5. **EthMAC/HA1588 `quasi_static`** (group E) — cheap to declare, but it encodes a
   software contract and needs an owner's decision, not a silent waiver.
6. **D2D pad `cdc_false_path`** (group I) — with written justification.

### What this baseline does *not* cover — read before quoting it

- **`axi_chiplet_controller` is black-boxed.** ~6,800 lines including the a2l replay CDC
  and the recovered-RX-clock domain are **not analysed**. That is step B8 and it will
  grow the report substantially. Nothing here is a statement about TideLink's internal
  CDC.
- **Structural goal only.** `cdc/cdc_verify` (functional CDC) does not terminate in batch
  on this design. Glitch, convergence and data-hold results here are the structural
  subset.
- **`Setup_blackbox01` = 0.00% unconstrained is not a clean bill** (§3). It cannot
  distinguish a declared pin from a defaulted one, and §6A proves five defaulted pins.
- **Four inferred black boxes have no port constraints at all** —
  `flash_cache_data`, `flash_cache_tag`, `eth_rom_via`, `rom_via`. They produced no
  crossing this run; that is luck, not coverage.
- **The 152 unsynchronised crossings are the `Ac_unsync01/02` set only.**
  `Ac_coherency06` (41), `Reset_sync04` (14), `Ac_conv01/02/04` (24) and `Ac_glitch03`
  (9) were counted but not individually triaged; they overlap the 50 substantially
  (13 shared signals confirmed) but not completely.
- **This run required a one-file RTL override** (§2b). It is pure code motion and
  proven so, but the analysed netlist is not byte-identical to the one the ASIC flow
  compiles.

---

## 8. Artefacts

Everything is under `build/cdc/b7/run-20260817/`:

| Path | What |
|---|---|
| `run2.sh` | the successful invocation (`run.sh` = failed attempt 1) |
| `spyglass_run2.log` | full stdout (`spyglass_run.log` = attempt 1, the 6 FATALs) |
| `nanosoc_eth_chiplet_b7.prj` | run-local `.prj` = reviewed copy + 2 options |
| `nanosoc_eth_chiplet_b7.flist` | flattened flist, 597 files, 1 substitution |
| `local_overrides/WavD2DGpioRx_v2.v` | the code-motion override |
| `probe/` | the 20-line micro-probe isolating `STX_VE_810` |
| `wd/…/consolidated_reports/…/CDC-report.rpt` | the authoritative structured report |
| `wd/…/spyglass_reports/clock-reset/*.csv` | per-rule crossing detail |
| `triage_50.json`, `triage_table.md` | the triage sample, machine-readable |
| `attempt1_workdir/` | attempt-1 work tree, relocated out of `cdc/` |

The four reviewable inputs in `cdc/` were **not modified** by this run.
