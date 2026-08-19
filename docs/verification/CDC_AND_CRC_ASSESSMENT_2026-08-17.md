# CDC flow assessment and the outstanding D2D CRC issue — 2026-08-17 (late)

**Everything here was produced by running the flows, not by reading the docs.**
Every number names the artefact it came from. No RTL was modified.

Superproject HEAD when the runs were made: `82e00d2` (it moved from `ac74bae`
mid-session — other sessions share this worktree).

| Run | Artefact | What it is |
|---|---|---|
| run0_repro | `build/cdc/cdcagent-20260817/run0_repro/` | SpyGlass `cdc/cdc_verify_struct`, current SGDC, zero waivers — the honest baseline |
| run1_waived | `build/cdc/cdcagent-20260817/run1_waived/` | + candidate waivers, first spelling |
| run2_waived_fixed | `build/cdc/cdcagent-20260817/run2_waived_fixed/` | + candidate waivers, second spelling |
| run3_final | `build/cdc/cdcagent-20260817/run3_final/` | + the shipped candidate waiver file |
| hal_real | `build/cdc/cdcagent-20260817/hal_real/` | the actual `ci/signoff.yaml` `cdc` stage (`make cdc`) |
| gate mutation suite | scratch | 7 fault injections through the unmodified `verif/cdc/run.sh` |

---

## 1. Is the CDC verdict trustworthy?

### 1.1 The `cdc` signoff stage can now fail — proven by mutation

`ci/signoff.yaml:174` `cdc` runs `make cdc` -> `verif/cdc/run.sh` (Cadence HAL,
**not** SpyGlass). The historical defect — "green by construction over a report
that hid 7,300 findings" — **is genuinely fixed**. Seven faults were planted in
the artefact the verdict reads, driving the real unmodified script through its
own `XRUN=` and `ASIC_LANE_OUT=` hooks:

| Case | Planted fault | rc | Verdict |
|---|---|---|---|
| abort | `*E,BLDSTP` + `Analysis failed` in the log | 1 | `cdc FAIL: HAL ABORTED` |
| no-halstruct | log with no rule lines | 1 | `cdc FAIL: halstruct never ran` |
| zero-findings | rule lines, no structural rules | 1 | `cdc FAIL: ... ZERO clock/reset-domain findings` |
| missing-log | no log written at all | 1 | `cdc FAIL: halstruct never ran` |
| **healthy** | valid log, 52 findings | **0** | `cdc PARTIAL-OK` (positive control) |
| ratchet | healthy + `CDC_MAX_MCKDMN=5` | 1 | `cdc FAIL: ... exceeds CDC_MAX_MCKDMN` |

**5/5 negative controls rejected, positive control accepted.** The gate
discriminates.

### 1.2 …but it is RED right now, and for a real reason

`build/cdc/cdcagent-20260817/hal_real/` — my own clean run of the stage —
ends:

```
hal: *E,BLDSTP: Further processing stopped because of synthesizability errors.
Analysis failed.
== cdc FAIL: HAL ABORTED before the rule set completed ==
```

The independently-produced `verif/cdc/build/xrun_hal.log` (2026-08-17 19:50,
26 MB) says the same. **HAL aborts before a single structural rule runs.** The
abort is caused by synthesizability errors — `*E,RTLINI` (declaration
initialisers) in `tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv`
and `i2c_master_axil.v`, `*E,VERCAS` (case-differing names) in
`src/rtl/chiplet_d2d_decode.sv:166` and `phc_ahb.sv:22`, `*E,METAEQ` (`!==`) in
`dma250_ahb5_to_ahbl.v:121`.

Because the stage is `gate: report`, this red is invisible. **The `cdc` stage
has produced no CDC information at all today.**

### 1.3 A second defect in the same guard — it can never say PASS

The liveness guard is anchored on `^halstruct:`. Measured on the 19:50 log,
this HAL emits **0** `halstruct:` lines, **88,691** `halcheck:` and **1,186**
`halsynth:`. The "realism probe" in the mutation suite feeds a log in the shape
this tool actually produces — `halcheck:` prefix, 52 real structural findings,
no abort — and the gate **rejects it**:

```
real-shape       rc=1   expect=0   FAIL   | == cdc FAIL: halstruct never ran ==
```

So even after the BLDSTP errors are fixed, the stage stays red on a bogus
criterion. The counting function `count_rule()` is fine (`^hal[a-z]*:` matches
`halcheck:`); only the guard is wrong.

**Recommended fix (not applied — one line, `verif/cdc/run.sh`):**
replace `grep -aq '^halstruct:' "$LOG"` with
`grep -aqE '^hal[a-z]*: \*[ENW],' "$LOG"`, and re-run the mutation suite:
`real-shape` must flip to rc=0 while all five negative controls stay rc=1.

### 1.4 The flow that *can* measure CDC is gated by nothing

`grep -n "spyglass\|cdc_verify" ci/signoff.yaml Makefile` returns **nothing**.
The SpyGlass setup in `cdc/` — the only flow here that can report
unsynchronised crossings — has no Makefile target, no CI stage and no owner.
It is run by hand.

### 1.5 The published baseline is one RTL revision stale

`CDC_B7_ROUND2.md` reports **878** messages. My byte-identical
re-invocation (same flist, same SGDC, same goal, fresh workdir) reports **884**.
The delta is not the SGDC — it is the TideLink checkout moving underneath it:

* `tidelink_top.sv` line numbers shifted by ~18 (`:2773` -> `:2833`, `:1122` ->
  `:1140`).
* A new module `tidelink_link_clk_div` appears, instantiated at
  `tidelink_top.sv:2817`, **with no definition** — see §5.2.
* Three new `Ac_unsync01` and one changed `Ac_unsync02` at the D2D black-box
  boundary, including a new `axi_chiplet_controller/user_hsclk` crossing and
  `hresetn`/`poresetn` re-attributed from `user_ref_clk` to `pad_clk_rx`.

Quote 884, from run0_repro, not 878.

---

## 2. Census — run0_repro, 884 messages, 0 waived

`build/cdc/cdcagent-20260817/run0_repro/wd/repro/consolidated_reports/nanosoc_eth_chiplet_cdc_cdc_verify_struct/moresimple.rpt`
(row count parsed == header "Number of Reported Messages", asserted).

By severity: **Error 163, Warning 89, Info 630, SynthesisWarning 2.**
By provenance: **authored 393, vendor 403, generated 85, n/a 3.**

| Rule | Sev | n | authored | generated | vendor |
|---|---|---:|---:|---:|---:|
| Clock_info03b | Info | 253 | 131 | 76 | 46 |
| **Ac_unsync01** | **Error** | **92** | 22 | 0 | 70 |
| checkSGDC_05 | Info | 82 | 82 | 0 | 0 |
| Ac_sync01 | Info | 72 | 8 | 0 | 64 |
| Ac_sync02 | Info | 71 | 30 | 0 | 41 |
| **Ac_unsync02** | **Error** | **47** | 10 | 0 | 37 |
| Ac_coherency06 | Warning | 41 | 1 | 0 | 40 |
| Reset_info01 | Info | 36 | 21 | 1 | 14 |
| Ar_sync01 / Ar_syncdeassert01 | Info | 27 / 27 | 12 / 12 | 0 | 15 / 15 |
| Setup_blackbox01 | Info | 25 | 5 | 0 | 20 |
| Reset_sync04 | Warning | 14 | 6 | 0 | 8 |
| Ac_conv02 | Warning | 12 | 8 | 0 | 4 |
| Ac_glitch03 | Error | 9 | 1 | 0 | 8 |
| ErrorAnalyzeBBox | Error | 9 | 1 | 0 | 8 |
| Ac_conv01 | Warning | 7 | 3 | 1 | 3 |
| Clock_check10 | Warning | 7 | 7 | 0 | 0 |
| Reset_sync02 | Error | 5 | 3 | 0 | 2 |
| Ac_conv04 | Warning | 5 | 0 | 0 | 5 |
| Ar_unsync01 | Error | 1 | 1 | 0 | 0 |
| (18 further rules, <=3 each) | | 33 | | | |

**Unsynchronised crossings: 140** (`Ac_unsync01` 92 + `Ac_unsync02` 47 +
`Ar_unsync01` 1). Where they live:

| Owner | Crossings |
|---:|---|
| 94 | OpenCores EthMAC, read from the lab-wide read-only IP tree |
| 39 | `nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb` (the locally-patched EthMAC copies) |
| 3 | `tidelink/` |
| 2 | `src/` (this repository's own integration RTL) |
| 2 | other |

**96% of the unsynchronised-crossing count is the Ethernet MAC, not the D2D
link.** That is not because the D2D link is clean — see §3.

---

## 3. Coverage holes

### 3.1 The ICG hazard is confirmed NOT covered

Verified against the installed goal files, SpyGlass 2022.06-SP2:

* `GuideWare/2021.09/block/rtl_handoff/cdc/cdc_verify_struct.spq` — the goal
  actually used — registers `Ac_glitch03`, `Clock_glitch05`. It does **not**
  register `Clock_glitch02`, `Clock_glitch03` or `Clock_glitch04`.
* `.../cdc/clock_reset_integrity.spq` registers `Clock_glitch02`
  ("clocks that are gated without latching their enable signal properly"),
  `Clock_glitch03`, `Clock_glitch04`, all overloaded to Warning.
* `cdc_verify_struct.spq` nevertheless sets
  `-clock_reduce_pessimism=latch_en,mux_sel_derived,check_enable_for_glitch,ignore_same_domain`.
  `check_enable_for_glitch` is armed in a goal that never loads the rule it
  arms. **It is inert.**

**Correction to the brief:** there is no `Clock_glitch07` / `clock_glitch07`
rule in this SpyGlass. `grep -rhoE "Clock_glitch[0-9]+" GuideWare/2021.09`
returns only `Clock_glitch02` (21), `03` (21), `04` (21), `05` (33).

### 3.2 Everything else `cdc_verify_struct` does not cover

Rules in `clock_reset_integrity` and absent from the goal that ran — **14**:

`Clock_check01` (latch/tristate/XOR in a clock tree) · `Clock_check04` (both
clock edges used) · `Clock_glitch02` · `Clock_glitch03` · `Clock_glitch04` ·
`Clock_Reset_check01` (unwanted cells in clock/reset nets) ·
`Clock_Reset_check02` (FF output vs its own clock/reset pin race) ·
`Clock_Reset_check03` (clock vs reset pin race) · `Clock_Reset_info01`
(clock-reset matrix) · `Reset_check01` (reset mode vs synthesis pragma) ·
`Reset_check02` (latch/tristate/XOR in a reset tree) · `Reset_check04` (reset
used both async and sync) · `Reset_check06` (high-fanout reset nets) ·
`Reset_check07` (async reset pin driven by combinational logic).

`Reset_check07` and `Clock_Reset_check03` matter for a design whose reset
ordering is already a documented concern. **A second run at
`-goals "cdc/clock_reset_integrity"` is cheap — the whole flow is ~4 minutes on
a warm workdir — and is the single highest-value missing measurement.**

### 3.3 The D2D controller's port constraints are being migrated, not applied

`checkSGDC_05` fires **82** times, every one of the form:

```
SGDC command 'abstract_port' not supported for non-top current_design
'axi_chiplet_controller' has been migrated to top
```

76 `abstract_port` + 2 `clock` for `axi_chiplet_controller`, 4 more for the two
XHB500 bridges. `cdc/waiver.swl` §2 correctly refuses to waive this rule; the
message is telling us the §7a block is not binding the way it was written.

The consequence is measurable. `bbox_pin_virtual_domains.csv` shows **18 pins of
`nanosoc_eth_chiplet.u_tidelink.u_chiplet_controller`** carrying an *inferred
five-clock virtual domain* instead of a declared one:

```
poresetn  hresetn  pad_rx[7:0]  pad_tx[7:0]
```

`pad_rx[7:0]` is the far-die D2D receive data — the most important
asynchronous boundary on the chip. And `cdc_verify_struct` sets
`-check_multiclock_bbox=yes`, whose documented effect is that *crossings whose
destination is an unconstrained multi-clock black-box pin are ignored*.

**Combined with `axi_chiplet_controller` still being `stop_module`'d (B8 not
done), the D2D link is the least-analysed block in a CDC run that exists to
analyse the D2D link.**

### 3.4 Smaller holes

* `pass2_reports/{CDC-report,moresimple,no_msg_reporting_rules}.rpt` in the
  published B7 round-2 directory are **broken symlinks** (`../../../../` resolves
  above the tree). The real reports are under `wd/*/consolidated_reports/`.
* `cdc/README.md` §7.1 still says "It has never been run" while the same file's
  header says "run twice".

---

## 4. `r_LoopBck` (`eth_top.v:598`) — REAL, reachable, low severity

Verified in the source this build compiles (OpenCores EthMAC, read from the
lab-wide read-only IP tree; flist line 152):

```verilog
:598  assign MRxDV_Lb    = r_LoopBck ? mtxen_pad_o    : mrxdv_pad_i & RxEnSync;
:601  assign MRxErr_Lb   = r_LoopBck ? mtxerr_pad_o   : mrxerr_pad_i & RxEnSync;
:604  assign MRxD_Lb[3:0]= r_LoopBck ? mtxd_pad_o[3:0]: mrxd_pad_i[3:0];
```

`r_LoopBck` is `MODER[7]`, launched in the `wb_clk`/`sys_fclk` domain, and it
selects **three combinational muxes on the `mrx_clk` receive datapath with no
synchroniser at all**. Its sibling `r_RxEn` at least gets a re-timing flop
(`:738`, `RxEnSync <= r_RxEn`) — though that is a single flop, gated on
`~mrxdv_pad_i`, not a 2-FF chain.

**Is it real on silicon?** Yes, and the firmware reaches it:
`nanosoc-multicore-system/firmware/apps/eth_netapp/driver/ethmac.h:147-152`
(`ethmac_set_loopback`) is a plain read-modify-write of `MODER`. In seven of the
nine calling apps the flip precedes `ethmac_enable()`, i.e. RX is quiescent —
safe. **Two apps flip it with RX already enabled**:

* `apps/eth_loopback_diag/main.c:293` — phase A -> B, `ethmac_enable()` was
  called at `:266` and there is no `ethmac_disable()` in between.
* `apps/ptp_tsu_loopdiag/main.c:233` — same shape, enable at `:212`.

**Severity: LOW-to-MEDIUM, not a tapeout blocker.** The failure mode is a glitch
or metastable sample on `MRxDV` at the instant of the flip: one corrupted or
spuriously-started receive frame, caught by the MAC's own frame CRC, and
self-clearing on the next `MRxDV` deassert. It cannot corrupt data silently and
it cannot wedge the link.

**Disposition — two actions, neither an RTL edit today:**

1. **Software contract (do now):** call `ethmac_disable()` before any
   `ethmac_set_loopback()` while the MAC is running, and re-enable after. That
   makes the two diagnostic apps match the other seven.
2. **RTL fix (log for the next netlist window):** 2-FF synchronise `r_LoopBck`
   into `mrx_clk` before the muxes, exactly as `RxEnSync` is handled. **This
   requires a local override** — `eth_top.v` is read straight from the
   lab-wide read-only IP tree, so the fix is a new file under
   `src/rtl/local_overrides/` plus a flist re-point, never an upstream edit.

---

## 5. The D2D CRC issue — verdict

### 5.1 What the defect actually is

TL-018 is one bug split across two lines that behave oppositely.

`out_prepend_swi_disable_crc` is an APB RW bit (FC-node base + `0x14`, bit[16]),
`1` = CRC checking **off**. It is not a parameter and not a `define`; which
value ships is decided purely by **which copy of `WlinkGenericFCSM*.v` the flist
selects**.

| | AW/W/B/AR/R | sideband `_6` | ECC |
|---|---|---|---|
| FPGA line (`tidelink_fpga_v2.flist`) | `src/rtl/local_overrides/` -> `<= 1'h1` **CRC OFF** | local -> `1'h0` ON | restored |
| **ASIC line (`tidelink_top_full_asic_v2.flist`)** | **`deps/…/wlink/` -> `<= 1'h0` CRC ON** | local -> `1'h0` ON | restored |

With CRC off, a payload bit-flip is committed **silently**: the peer memory
holds the wrong word, the master is told SUCCESS, `crc_errors` stays 0 and no
NACK fires. That is measured, not asserted — `imp/hw_gate/tl018/w_node_ab.log`
pins both arms.

### 5.2 Is it live in the tapeout configuration? — **No, and this is measured on the netlist**

`build/chip/flist/tidelink_asic.flist` (what `ASIC/eth-chiplet/design.mk:138`
feeds synthesis) selects the `deps/` FC state machines. Confirmed at both the
recorded pin and the checkout. But flists can go stale, so I checked the frozen
gate netlist directly —
`ASIC/genus-innovus/baseline_2026-08-07/outputs/nanosoc_eth_chiplet_pads_pnr.v`:

```
7 x DFCNQD1   (D-FF, async active-low CLEAR -> resets to 0 -> CRC CHECKING ON)
  axi2wl_wlink_axi{aw,w,b,ar,r}FC_out_prepend_swi_disable_crc_reg
  gb2wl_wlink_generalbusgb_out_prepend_swi_disable_crc_reg
  tl2wl_wlink_tidelinktl_out_prepend_swi_disable_crc_reg
```

All seven FC nodes, no exceptions, no set-type flop anywhere. **CRC checking is
ON at reset in the taped-out silicon.** The silent-corruption arm of TL-018 is
an **FPGA-line** exposure only.

**Two corrections that fall out of the same measurement:**

* **"ECC bypassed" is true of the frozen netlist and false of the source.** The
  ASIC flist was re-pointed to the restored `WlinkEccSyndrome.v` by TideLink
  commit `d78268a` on **2026-08-08 05:38**. Both baselines on disk
  (`baseline_2026-08-06`, `baseline_2026-08-07/outputs/…_pnr.v`, 2026-08-07
  12:27) **predate it**. Netlist evidence: **zero** `ecc_corrupted_cnt` registers
  survive (the counter is optimised away, exactly what a hard-tied
  `corrupted = 1'h0` produces) while **10** distinct `crc_err*_reg` registers do.
  Anyone re-synthesising today gets functional ECC; the shipping stream does not.
* **The recorded TideLink pin is `e21e274`, not `d7fe5d5`.**
  `git rev-parse HEAD:tidelink` = `e21e274`; the on-disk checkout is `d7fe5d5`,
  **11 commits ahead**. Every tool reads the checkout; the repository records the
  older commit. A fresh clone builds something else.

### 5.3 Is the fix in the pinned commit? — **There is no fix, and the instrumentation is not in the pin either**

`d1adec2` "fix(tl018): make link-CRC state visible; sim-prove the silent
corruption" changes:

```
 Makefile | cocotb/tidelink_axi_datanode_recovery/{Makefile,test_axi_datanode_gaps.py}
 imp/hw_gate/tl018/TL018_RESULT_2026_08_14.md | pynq_host/scripts/kr260_eth_bringup.py
```

`git show --name-only d1adec2 | grep -E '\.(v|sv)$|flist'` -> **nothing**.
**No RTL. No flist.** TL-018 is **INSTRUMENTED, not FIXED** — a blocking
`gaps_crc` sim gate that pins both arms, plus a bring-up script option. And
`d1adec2` is one of the 11 commits *ahead* of the recorded pin `e21e274`, so
even the instrumentation is absent from what the superproject records.

`docs/BUG_REGISTRY.yaml` still carries `status: root_caused`, `fix.commit: null`,
`verification.sim_test: none`, `in_sim_gate: false`, `signoff.approved: false`.
The last two are now factually wrong.

### 5.4 What IS live in the tapeout — TL-036, and it is reachable *because* CRC is on

CRC-on is the right choice, and it arms a different defect.

`src/rtl/local_overrides/WlinkGenericFCSM_6.v` — the **only** FC state machine
the ASIC flist takes from `local_overrides/` — carries the sticky
`socl_l7_real_crc_seen` self-latch **without** the `TL033_LEGACY_WDOG` guard:

```verilog
:644  reg socl_l7_real_crc_seen;              // sticky: any real CRC error since reset
:646  wire socl_l7_wdog_force_clear =
:647     (socl_l7_wdog_cnt == SOCL_L7_WDOG_THRESHOLD)
:648     & ~socl_l7_real_crc_seen;            // <-- the kill
:1624 socl_l7_real_crc_seen <= 1'h1;          // set on first crcCorruptSeen, never cleared
:1638 else if (socl_l7_real_crc_seen) socl_l7_wdog_cnt <= 16'h0;
```

The file's own header states the consequence: *"production silicon with genuine
link errors disarms the watchdog permanently."* The state-7 SEND_NACK watchdog
— the routing-insensitive backup recovery — is killed by the **first** genuine
CRC error, for the lifetime of the reset cycle.

The fix exists: `WlinkGenericFCSM{,_1,_2,_3,_4}.v` in `local_overrides/` wrap
that expression in `` `ifdef TL033_LEGACY_WDOG `` / `` `else `` (the `else` arm
drops the `& ~socl_l7_real_crc_seen`). `grep -c TL033_LEGACY_WDOG` = **2** for
each of those five and **0** for `_6`. **The ASIC compiles none of those five —
it takes them from `deps/`, which has no watchdog at all — and it does compile
`_6`, the one file the fix was never ported to.**

**This is in the taped-out netlist.** From the same 08-07 `_pnr.v`:

```
DFCNQD1  tl2wl_wlink_tidelinktl_socl_l7_real_crc_seen_reg
```

Exactly one instance, prefix `tl2wl_wlink_tidelinktl_` = the sideband node.

**Severity: this is a conditional loss of a recovery mechanism, not silent data
corruption.** It cannot corrupt data — CRC is on and detection works. It removes
the backup that clears a stuck SEND_NACK after the first real link error. And
the `gaps_crc` blocking gate does **not** cover it: those tests drive the AXI
data nodes, not `_6`.

### 5.5 The residual silent-corruption risk on silicon is a *software* footgun

`tidelink/src/sw/wlink.h:214-226` ships `wlink_fc_disable_all_crc()`, which sets
bit[16] on **all seven** nodes including the sideband. It currently has **zero
callers** and no `.c` in this tree includes `wlink.h`, so nothing turns CRC off
today. But it is one call away from converting the tapeout's safe default into
the FPGA line's silent-corruption configuration.

**Recommendation:** rename it `wlink_fc_disable_all_crc_UNSAFE_bringup_only()`
and put the `w_node_ab.log` result in its doc comment, or delete it. Zero
netlist impact.

### 5.6 Verdict

| Question | Answer |
|---|---|
| What is the defect? | Link-CRC checking reset value is decided by flist choice; with it off, payload corruption is committed silently (measured, both arms) |
| Live in the tapeout configuration? | **No.** All 7 FC nodes reset CRC **ON** — proven on the frozen gate netlist, not inferred from a flist |
| Is the fix in the pinned commit? | **There is no fix.** `d1adec2` touches no RTL and no flist — instrumentation only. And it is not in the recorded pin `e21e274` either |
| What remains, tapeout-relevant? | **TL-036**: `WlinkGenericFCSM_6.v` sticky `socl_l7_real_crc_seen` disarms the state-7 watchdog on the first CRC error. Present in the 08-07 netlist. Fix exists on five sibling files the ASIC does not compile |
| What remains, process? | ECC-bypassed netlist vs ECC-restored source; recorded pin 11 commits behind the checkout; registry entry stale on three fields |

**The loud part:** silent link corruption is **not** live in the tapeout. It is
live on the **FPGA** line, where all five AXI data nodes reset CRC-off and the
project's own gated test `test_axi_b_crc_off_silent_payload` **passes** — i.e.
proves the corruption. Anyone reasoning about FPGA-measured link data today is
reasoning about a link with its integrity check switched off.

---

## 6. Waivers — every claim proved by a count that moved

`cdc/waiver_bbox_macros.swl` (new, **candidate**, wired into no flow —
`cdc/waiver.swl` stays empty). Scope: one BuiltIn bookkeeping rule
(`ErrorAnalyzeBBox`) on eight compiled hard macros that are undefined *by
construction* (models come from `.lib`, not from any filelist).

**Proved to fire** (run0_repro -> run3_final):

```
ErrorAnalyzeBBox     9 ->  1   (-8)
TOTAL              884 -> 876   Waived messages 0 -> 8
Ac_*/Ar_*/Reset_*/Clock_* rules that moved:  NONE
```

**Proved not to over-reach** — the deliberately un-waived member of the *same
rule* still reports:

```
ErrorAnalyzeBBox survivor: tidelink_link_clk_div
```

That survivor is itself a real finding: `tidelink/src/rtl/tidelink_top.sv:2817`
instantiates `tidelink_link_clk_div`, the module exists at
`tidelink/src/rtl/tidelink_link_clk_div.sv`, `tidelink_top_full_asic_v2.flist:410`
lists it — and the **generated** `build/chip/flist/tidelink_asic.flist`
(2026-08-14 12:29) does **not**. `make asic-flist` must be re-rendered before the
next synthesis, or the divider goes in as an inferred black box.

### 6.1 The failure mode the brief warned about, caught in the act

Two spellings of a `Setup_blackbox01` waiver were tried on the same eight macros:

| Run | Spelling | Matched |
|---|---|---:|
| run1_waived | `waive -du "<macro>" -rule Setup_blackbox01` | **0** |
| run2_waived_fixed | `waive -rule Setup_blackbox01 -msg "black-box .<macro>."` | **0** |

In both runs `Setup_blackbox01` stayed at exactly **25** and the header's
"Number of Waived Messages" stayed at **8**. **SpyGlass said nothing.** Its
thirteen dedicated waiver-hygiene rules `SGDC_waive01..13` all ran in the same
goal and reported zero findings. `-du` resolves this rule to the design unit
that *instantiates* the black box, not the one named in the message.

Those eight statements were **removed rather than shipped**, and the file now
carries the measured prediction so the next inert waiver is caught by a number
rather than by luck.

---

## 7. Should CDC be `report` or `block`?

**Keep `cdc` at `report`. Do not promote it. Promoting it would gate on
something that is not CDC.**

The `cdc` stage runs HAL with no SDC. Its own script says so: the nine
synchroniser rules (`CLKDMN CMBCDC INSYNC FLSYNC RSTSYN RSTSCB RSTDMN RSTDAS
ACNCPI`) are **zero by construction**, and it labels them NOT-MEASURED. Making
that stage blocking buys a gate on `MCKDMN` counts and nothing about
metastability.

**Instead, in this order:**

1. **Fix the two defects in the existing `cdc` stage** (§1.2 BLDSTP errors,
   §1.3 the `^halstruct:` guard) so the stage stops being a red nobody reads.
   Re-run the mutation suite as the acceptance test.
2. **Add a second stage `cdc-spyglass`, `gate: report` on day one**, running
   `cdc/cdc_verify_struct` from `cdc/nanosoc_eth_chiplet.prj`. The run is
   ~4 minutes on a warm workdir. Its acceptance criterion should be a **census
   comparison against a checked-in baseline**, not a threshold — this repository
   has been bitten repeatedly by budgets set to the day's number.
3. **Then add `cdc/clock_reset_integrity`** as a third goal (§3.2). This is
   where `Clock_glitch02` and the reset-tree checks live, and it is the largest
   unmeasured area.
4. **Only after B8** (un-black-box `axi_chiplet_controller` — one token in the
   `.prj`) and after §3.3's 18 undeclared D2D pins are declared, is a `block`
   gate on unsynchronised crossings meaningful. Until then a green D2D result is
   a result that cannot be dirty.

**Do not set a `CDC_MAX_*` ratchet to today's number.** The mutation suite shows
the ratchet mechanism works; what it needs is a triaged budget, and 140
unsynchronised crossings have not been triaged.

---

## 8. Reproduce

```bash
export CHIPLET=$(git rev-parse --show-toplevel)

# SpyGlass baseline (~4 min warm, ~6 min cold)
$CHIPLET/build/cdc/cdcagent-20260817/run0_repro/run.sh

# same, with the candidate waivers
SWL_OVERRIDE=$CHIPLET/cdc/waiver_bbox_macros.swl \
    $CHIPLET/build/cdc/cdcagent-20260817/run0_repro/run.sh

# the real signoff stage, in its own output dir so it cannot collide
ASIC_LANE_OUT=$CHIPLET/build/cdc/cdcagent-20260817/hal_real $CHIPLET/verif/cdc/run.sh
```

Census any run (asserts row count == the report header's own total, and exits 2
if they disagree):

```bash
python3 scripts/cdc/spyglass_census.py <run>/wd/*/consolidated_reports/*/moresimple.rpt
```
