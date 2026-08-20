# `bscan-probe` vs `bscan-probe2` — complete input diff

**Question asked:** two synthesis runs of the same design, 16 hours apart, same
`make -C ASIC/eth-chiplet syn RUN_TAG=...` command. `bscan-probe` (netlist 2026-08-19
14:06) was reported to contain 119 boundary-scan cells; `bscan-probe2` (netlist
2026-08-20 10:36) to contain 2. **What else changed besides the RTL?**

**Method:** every assertion below is measured off artefacts on disk — the two `syn.log`
files, the two `reports/syn_manifest.txt` / `syn_provenance.txt`, the two
`reports/syn_hierarchy.rep` (which record the *elaborated* design), the two netlists,
git history, git object store, and filesystem mtimes. Nothing was re-run and nothing was
modified.

---

## 0. The premise is wrong, and that matters for reading the rest

**The real census is 119 → 115, not 119 → 2.**

| | probe | probe2 |
|---|---|---|
| instances named `*u_bsc_*_q_reg` (statement-parsed, wrap-safe) | **119** | **115** |
| flops attributable to the boundary-scan register | 166 | **162** |
| distinct `u_bsc_NN` indices present | 76 | **76** |

In `bscan-probe2` the module `nanosoc_eth_chiplet_bscan` was **auto-ungrouped** — dissolved
into `nanosoc_eth_chiplet_pads`. Every instance inside it gained a 28-character
`u_nanosoc_eth_chiplet_bscan_` prefix, which pushes the instance name past Genus's ~80-column
wrap so the cell type and the name land on different lines. A line-oriented census then sees
only the two shortest names (`..._u_bsc_04_SE_I_obs_dr_q_reg`, `..._u_bsc_02_CLK_I_obs_dr_q_reg`)
and reports "2". `scripts/bscan_syn_verdict.py` fails one step earlier still — it looks for a
`module nanosoc_eth_chiplet_bscan ... endmodule` block, does not find one, and prints
*"the register was optimised away entirely"*.

Four flops **were** genuinely removed (names *and* nets absent from probe2):

```
u_bsc_05_SWDIO_IO_oe_update_q_reg
u_bsc_23_HOST_IO_1_oe_update_q_reg
u_bsc_24_HOST_IO_1_data_update_q_reg
u_bsc_26_HOST_IO_0_oe_update_q_reg
```

(43 update stages → 39. All 76 shift/capture stages and all 47 fixed stages survive.)

This matches, independently, the conclusion in `docs/bscan/DELETION_ROOTCAUSE.md`, written
by a concurrent session. The two analyses were performed separately from the same artefacts.

---

## 1. Run identity

| | `bscan-probe` | `bscan-probe2` |
|---|---|---|
| Genus start | 2026-08-19 **12:25:50** | 2026-08-20 **08:52:30** |
| RTL read (`read_flist`) | 12:26:15 → | 08:52:4x → |
| SDC read | ~12:31 | ~09:00 |
| gate netlist written | 14:06:41 | 10:36:10 |
| manifest written | 14:13:39 | 10:42:52 |
| runtime | 6451 s | 6607 s |
| Genus version | 21.15-s080_1 | 21.15-s080_1 (identical) |
| host | srv03335 | srv03335 |
| `project_git_sha` **as recorded** | 8c287ff | 587c3e3 |
| `toolkit_git_sha` | 8e23478 (dirty) | 8e23478 (dirty) |

> **Trap:** `prov.design.git_sha` is captured when provenance is written — at the *end* of
> the run — not when the inputs were read. `8c287ff` is timestamped 13:47, 80 minutes after
> probe read its RTL. Neither recorded SHA describes the inputs of its own run. The
> `SYN: ok: <path> (<N> bytes)` lines, captured at read time, are the only trustworthy
> input fingerprint in the log — and they cover only four files.

---

## 2. The input table

`SAME` / `DIFFERED` is about the bytes the tool actually read. "Functional?" is whether the
difference could change the netlist.

### 2.1 Files the flow fingerprints (`SYN: ok:` lines, log L1038/1188/1198/1203)

| Input | probe | probe2 | Differed | Functional |
|---|---|---|---|---|
| `ASIC/eth-chiplet/config/design_config.tcl` | **20039 B** | **18714 B** | **YES (−1325)** | **No** — proven |
| `ASIC/genus-innovus/inputs/constraints.sdc` | 44270 B, mtime 08-19 10:50:04 | 44270 B, same mtime | no | — |
| `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v` | **25759 B** | **26358 B** | **YES (+599)** | **Yes, but not on any signal path** |
| `ASIC/genus-innovus/inputs/nanosoc_eth_chiplet_pads.upf` | 8292 B | 8292 B | no | — |

**`design_config.tcl`** — changed by `7a9f06d` (08-19 13:45, *"make help is generated from the
targets"*), a comment sweep. Verified rather than trusted: stripping comments and blank lines
from both blobs gives **byte-identical code**. The log confirms every executed statement is the
same, only at shifted line numbers (`set ::DONT_TOUCH_PATTERNS {uPAD*}` at L375 → L351,
`set DFT 0` at L254 → L237). Every `SYN_*` / `FLIST_*` knob in the two manifests is identical.

**`nanosoc_eth_chiplet_pads.v`** — probe read the blob from `2b9932e`; probe2 read the blob from
`7581af0` (*"padring: one PVDD2POC per domain, not one per side"*, 08-19 17:27). The delta is
three supply pads swapped `PVDD2POC_G` → `PVDD2DGZ_G` on sides B/L/R, plus comments and one
doc-path fix (`c31afd7`). **Control:** the netlists carry it — `PVDD2POC_G` 4 → 1,
`PVDD2DGZ_G` 8 → 11, `uPAD_*` instance count 82 → 82. These are power pads with a single
`VDDPST` connection and no signal port; the boundary-scan instantiation in this file is
byte-identical between the two versions.

### 2.2 SDC files the flow does **not** fingerprint (sourced from `constraints.sdc`)

| Input | probe | probe2 | Differed | Functional |
|---|---|---|---|---|
| **`inputs/bscan_constraints.sdc`** | **5255 B** (`f2467d8`) | **6724 B** (`a2ca938`) | **YES** | **YES — this is the trigger** |
| `inputs/ethernet_constraints.sdc` | pre-`c31afd7` | post-`c31afd7` | YES | **No** — 0 non-comment lines changed |
| `inputs/i2c_constraints.sdc` | pre-`c31afd7` | post-`c31afd7` | YES | **No** — 0 non-comment lines changed |
| `inputs/qspi_constraints.sdc` | pre-`c31afd7` | post-`c31afd7` | YES | **No** — 0 non-comment lines changed |
| `inputs/tidelink_constraints.sdc` | `9d2d79f`, 08-17 21:14 | same | no | — |

`a2ca938` (08-19 **16:44**, i.e. between the runs) removed two constraints:

```tcl
set_multicycle_path -setup 2 -from [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*] \
                             -to   [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*]
set_multicycle_path -hold  1 -from [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*] \
                             -to   [get_pins -quiet u_nanosoc_eth_chiplet_bscan/*]
```

and replaced the "register missing" *warning* with a hard `error`.

Measured in the `read_sdc` statistics of the two logs — not inferred:

| | probe | probe2 |
|---|---|---|
| `get_pins` successful | **40** | **36** (−4) |
| `set_multicycle_path` successful | **3** | **1** (−2) |
| `TIM-316` / `TIM-317` warnings on `hpin:.../u_nanosoc_eth_chiplet_bscan/tck` | 3 / 3 | 1 / 1 |
| `GLO-51` *hierarchical instance automatically ungrouped* | **45** | **47** |
| `reports/syn_area.generic.rep` row `u_nanosoc_eth_chiplet_bscan` | present, **368 cells** | **absent** |

`get_pins <inst>/*` anchors the exception to the instance's hierarchical boundary pins.
Genus will not auto-ungroup a hinst whose boundary pins carry SDC exceptions, so the
multicycle was acting as an **accidental `ungroup_ok false`**. Removing it — for entirely
correct timing reasons, documented in the commit — removed the pin. The module was already
gone by the *generic* area report, which is the right stage: constraints are read after
`elaborate` and before `syn_generic`.

`DONT_TOUCH_PATTERNS` is `{uPAD*}` in both runs and never covered the register. The only
`ungroup_ok false` set anywhere in the flow is `protect_link_clk_div_pre_generic` on
`u_link_clk_div`, identical in both runs (`hooks/pre_synth.tcl`, mtime 08-18 00:34,
unchanged).

> **Mechanism confidence:** the *ungrouping* is measured. The *reason* (hierarchical-pin
> exception pinning the boundary) is the leading hypothesis — it is the only input delta in
> the entire diff that names the bscan hierarchy — but it is not proven here, because proving
> it needs a run with the multicycle restored, and this was a read-only investigation.

### 2.3 RTL

| Input | probe | probe2 | Differed | Functional |
|---|---|---|---|---|
| `flist/nanosoc_eth_chiplet_asic.flist` | sha256 `2ee7611…`, 6901 B | **identical sha256** | no | — |
| **`src/rtl/nanosoc_eth_chiplet.sv`** | **71705 B** (`0ec54af`, clean) | **67749 B, UNCOMMITTED at the time** | **YES** | **YES** |
| `src/rtl/chiplet_d2d_decode.sv` | pre-`e6a3f70` | post | YES | No (comment sweep) |
| `src/rtl/tidechart_shim.sv` | pre-12:29 08-19 | post | YES | No (comment sweep) |
| `src/rtl/bscan/bscan_cell.sv` | 8046 B | 8046 B | no | — |
| `src/rtl/bscan/bscan_tap.sv` | 14530 B (`2b9932e`) | 14442 B (`e6a3f70`) | YES | No — elaborates to the same `bmux_840`, line 155 → 157 |
| `src/rtl/bscan/bscan_ir.sv` | 11376 B (`2b9932e`) | 11516 B (`c3ab594`) | YES | No — same `mux_4555`, line 199 → 201 |
| `src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv` | 54658 B (`7a83014`) | 55282 B (`61aa090`) | YES | **IDCODE default only** `32'h1000_05A1` → `32'h1000_1001`; rest comments |
| `src/rtl/bscan/pad_table.json` | 17055 B | 17055 B | no | — |
| vendor RTL under `$ARM_IP_LIBRARY_PATH` | — | — | **no** | swept: zero files in the referenced subtrees have an mtime in the window |
| `tidelink/`, `tidechart/`, `nanosoc-multicore-system/` RTL | — | — | **no** | swept for `*.v/*.sv/*.vh/*.svh` in the window: zero hits |

**The uncommitted one.** `src/rtl/nanosoc_eth_chiplet.sv` was rewritten in the working tree at
**2026-08-19 16:38:46** and stayed uncommitted across the whole of run 2. It is now commit
`4558696` (*"fix(d2d): force the peer path non-bufferable — closes the measured wedge"*,
2026-08-20 **11:54**, i.e. landed *during this investigation*). Code-only diff
`0ec54af` → `4558696`:

```verilog
-    reg  ewr_reject_dph_r;                                  // 2-cycle HRESP=ERROR reject FSM
-    reg  ewr_err2_r;                                        // ... deleted entirely
-    assign hreadyout_peer = ewr_reject_active ? ewr_err2_r : hreadyout_peer_tl;
-    assign hresp_peer     = ewr_reject_active ? 1'b1       : hresp_peer_tl;
+    assign hreadyout_peer = hreadyout_peer_tl;
+    assign hresp_peer     = hresp_peer_tl;
-        .ahb_sub_hprot      (d2d_ahb_m_hprot),
+        .ahb_sub_hprot      ({2'b00, d2d_ahb_m_hprot[1:0]}),      // HPROT tie-down
-        .ETH_IMEM_MEM_FPGA_IMG ("/home/dam1n19/.../src/rtl/eth_imem_alive.hex")
+        .ETH_IMEM_MEM_FPGA_IMG (ETH_IMEM_IMG)                     // defaults "image.hex"
```

**Recovered, not assumed.** probe's `syn_hierarchy.rep` records the *elaborated* design, and it
carries both distinguishing markers of the `0ec54af` blob:

```
probe   3 u_soc ( nanosoc_multicore_soc_ETH_IMEM_MEM_FPGA_IMG584h2f686f6d652f...  -> "/home/.../eth_imem_alive.hex"
probe2  3 u_soc ( nanosoc_multicore_soc_ETH_IMEM_MEM_FPGA_IMG72h696d6167652e686578 -> "image.hex"

probe-only:  3 mux_ewr_err2_r_431_21 ( bmux_1 )
probe-only:  3 mux_445_29 ( bmux_1 )
probe-only:  3 mux_446_29 ( bmux_1 )
```

(That is a content match on two independent markers, not a byte-identity proof.)

**This is the change that moves the instance counts.** The HPROT tie-down feeds constant
`2'b00` into TideLink/XHB500 and propagates:

| | probe | probe2 |
|---|---|---|
| `GLO-12` *replacing a flip-flop with a logic constant 0* | 2459 | **2568** (+109) |
| `total_insts` (manifest) | 187642 | **186782** (−860) |
| `icg_insts` | 3012 | **3007** |
| `CG-400` *removed a clock-gating instance* | — | **8** |

It is **not** the cause of the boundary-scan census change: the boundary-scan hierarchy is
identical in the two elaborated designs (see §3).

### 2.4 Generated / regenerated inputs

| Input | probe | probe2 | Differed | Recoverable |
|---|---|---|---|---|
| `build/chip/rtl/nanosoc_eth_chiplet_chip.v` | 8622 B, mtime **2026-07-17 11:14** | same file, same mtime | **no** | n/a — never regenerated |
| `build/chip/flist/soc.flist` | overwritten | 56691 B, mtime **08-20 08:52:25** | **UNKNOWN** | **NO — see below** |
| `build/chip/flist/tidelink_asic.flist` | overwritten | 22975 B, mtime **08-20 08:52:25** | **UNKNOWN** | **NO — see below** |
| `build/<tag>/romlibs/**.lib` (10 files) | — | — | **no** | byte-identical, md5-compared |
| `prov.rom.{eth,cc}.content_sha256` | — | — | **no** | identical in both manifests |

`make asic-flist` rewrote both `build/chip/flist/*.flist` **five seconds before** Genus started
in run 2. Their run-1 content is gone and **cannot be recovered** — this is exactly the class of
input the manifest is blind to, since `prov.flist.sha256` hashes only the *top* flist and not
its `-f` includes.

**But the effect is bounded, and measured.** Their generators (`flist/flatten_soc_flist.py`,
`flist/resolve_tidelink_flist.py`) changed between the runs only in `dd27ac1`, a docstring
sweep — the `OVERRIDES` list in `resolve_tidelink_flist.py` is empty in both. Both manifests
record `source_files 603`. `init_hdl_search_path` is identical in the two logs. And the
normalised elaborated-hierarchy diff (§3) is 9 lines, all attributable to
`nanosoc_eth_chiplet.sv`. **The two runs read the same source set.**

### 2.5 Flow / build layer

| Input | probe | probe2 | Differed | Functional |
|---|---|---|---|---|
| `ASIC/asic-toolkit` HEAD | 8e23478 (dirty) | 8e23478 (dirty) | no | — |
| `asic-toolkit/flow/genus/1_synthesis.tcl` | mtime 08-17 18:13 | same | **no** | — |
| `asic-toolkit/flow/common/*.tcl` | mtime ≤ 08-17 20:31 | same | **no** | — |
| `asic-toolkit/tech/tsmc65/*` | mtime ≤ 08-14 | same | **no** | — |
| asic-toolkit dirty files touched in the window | `ci/check-vendor-collateral.sh` (08-20 08:51:20), `flow/verify/gls/*`, `test/shell/*` | | YES | **No** — none is on the Genus path |
| `ASIC/eth-chiplet/hooks/pre_synth.tcl`, `post_synth.tcl` | 08-18 | same | no | — |
| `ASIC/genus-innovus/scripts/protect_link_clk_div.tcl` | 08-18 11:03 | same | no | — |
| `ASIC/eth-chiplet/design.mk` | pre-`3742492` | post-`4bd9f41`/`c31c2f4` | YES | **No** — every `SYN_*` knob in the two manifests is identical |
| `ASIC/common.mk` | mtime 08-19 13:36 (dirty) | same | **no** | — |
| `ASIC/eth-chiplet/Makefile`, root `Makefile` | changed 08-19 12:34 / 22:17 | | YES | No — knob dump identical |
| `ASIC/eth-chiplet/overrides/filler.tcl` | changed 08-19 12:44 | | YES | No — PnR-only, comment sweep |

---

## 3. What the elaborated designs actually differ by

`reports/syn_hierarchy.rep` is written right after `elaborate` (probe: 12:29:32). Normalising
away line numbers and Genus's generated-object serial numbers, the two 21 000-line reports
differ by **9 lines**:

* **3 lines** — the `ETH_IMEM_MEM_FPGA_IMG` parameter string, mangled into
  `u_soc` / `u_network_core` / `u_region_imem_0`'s module names.
* **3 lines** — `mux_ewr_err2_r_431_21`, `mux_445_29`, `mux_446_29`, present in probe only.
* **3 lines** — the paired `u_soc` / `u_network_core` / `u_region_imem_0` names in probe2.

**All nine are the uncommitted `nanosoc_eth_chiplet.sv` edit. Nothing else in the elaborated
design differs — including the entire boundary-scan hierarchy**, whose only deltas are RTL
line numbers moving under comment edits (`mux_shift_q_155_14` → `_157_14`,
`ctl_insn_q_199_11` → `_201_11`, same `bmux_840` / `mux_4555` behind them).

---

## 4. The four hypotheses you asked me to test

| Hypothesis | Verdict | Evidence |
|---|---|---|
| **a flist entry dropped** | **REFUTED** | top flist sha256 identical; `source_files 603` in both; `init_hdl_search_path` identical; elaborated hierarchy identical bar §3 |
| **the wrapper regenerated with different tie-offs** | **REFUTED** | `build/chip/rtl/nanosoc_eth_chiplet_chip.v` has mtime **2026-07-17**; it was not regenerated at all |
| **an SDC `set_case_analysis` added** | **REFUTED by direct measurement** | `reports/syn_case_analysis.rep` is byte-identical apart from its timestamp: 3 entries in both (`TEST`=0, `div_en_r_reg/q`=0, `byp_en_r_reg/q`=1). **`SE` is not case-analysed in either run.** |
| **a `dont_touch` removed** | **REFUTED as stated; a different pin was removed** | `DONT_TOUCH_PATTERNS` is `{uPAD*}` in both. The thing that was removed is an **SDC hierarchical-pin exception** in `bscan_constraints.sdc`, which was pinning the hierarchy as a side effect nobody had written down |

---

## 5. Verdict

**A NON-RTL CAUSE, plus a separate uncommitted RTL change that is not responsible for the
boundary-scan symptom.**

1. The reported symptom (**119 → 2**) is **96.6 % a measurement artefact**. The real figure is
   119 → 115; the 76-bit shift chain is complete in both netlists.
2. The artefact was produced by **auto-ungrouping**, and the ungrouping was caused by a
   **non-RTL input**: `ASIC/genus-innovus/inputs/bscan_constraints.sdc`, changed by `a2ca938` at
   16:44 on 08-19 — squarely between the two runs. It is a *sourced* SDC: not asserted with a
   byte count, not hashed in `syn_provenance.txt`, invisible to the manifest.
3. **Four update flops were genuinely removed.** That delta is real and outside this document's
   scope — see `docs/bscan/DELETION_ROOTCAUSE.md` §4.
4. **A concurrent session did mutate a shared synthesis input between the runs**, exactly as
   suspected: `src/rtl/nanosoc_eth_chiplet.sv`, edited in the working tree at 16:38 on 08-19,
   uncommitted throughout run 2, and landed only at 11:54 on 08-20 as `4558696`. It moves
   `total_insts` by −860 and constant-folded flops by +109 — but it does not touch the
   boundary-scan hierarchy, and the elaborated hierarchy proves it.
5. `design_config.tcl` (−1325 B) and `nanosoc_eth_chiplet_pads.v` (+599 B) also differed and are
   **both ruled non-causal**, by stripped-comment equality and by netlist control respectively.

## 6. What could NOT be determined retrospectively

* **`build/chip/flist/soc.flist` and `build/chip/flist/tidelink_asic.flist` at run 1.**
  Both were overwritten by `make asic-flist` at 08-20 08:52:25. Their run-1 bytes are
  unrecoverable. Bounded — not eliminated — by identical `source_files` counts, identical HDL
  search paths, comment-only generator changes and a 9-line elaborated-hierarchy diff.
* **`src/rtl/bscan/bscan_tap.sv` at run 1.** Its on-disk mtime is 12:29:52, three minutes
  *after* probe read it. The read content is inferred to be the `2b9932e` blob (14530 B); an
  intermediate uncommitted state between 10:47 and 12:26 would leave no trace. The hierarchy
  report shows the TAP elaborated identically in both runs, so any such state was
  behaviour-neutral.
* **`src/rtl/nanosoc_eth_chiplet.sv` at run 1** is recovered by content match on two
  independent elaboration markers, not by byte identity.
* **Whether the removed multicycle is the *mechanism* of the ungrouping.** It is the only input
  delta naming the bscan hierarchy, and Genus's boundary-pin behaviour explains it, but the
  confirming experiment (re-run with the multicycle restored) was out of scope here.
* **Genus's own choice of which 2 extra hierarchies to ungroup** (`GLO-51` 45 → 47). One is the
  bscan register, confirmed by the area report. The second is not identified: `GLO-51` appears
  in these logs **only as a summary-table count**, with no per-instance detail line anywhere.
  (`set_message -no_limit` in `design_config.tcl` is guarded on `info commands` and is
  Innovus-only, so it does not widen the Genus log.)

## 7. Two flow defects this exposed

1. **`prov.flist.sha256` hashes only the top-level flist.** `build/chip/flist/*.flist` are
   `-f`-included, regenerated before every synth, and unhashed. A run's real source set is not
   recorded anywhere.
2. **Sourced SDC files are never fingerprinted.** `constraints.sdc` was byte-identical across
   the two runs while `bscan_constraints.sdc` — which it sources, and which changed the netlist
   structure — was not recorded at all. The `SYN: ok:` byte-count assertion stops at the top file.

Both would have turned this investigation into a one-line diff.
