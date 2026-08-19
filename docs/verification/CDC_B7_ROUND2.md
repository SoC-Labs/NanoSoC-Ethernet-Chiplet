# B7 round 2 — fixing the SGDC declaration bugs, and what the delta actually means

**Date:** 2026-08-17 · **Status:** RUN COMPLETED, exit code 0 · **Predecessor:**
`CDC_B7_BASELINE.md` (not modified)

---

## 0. Read this paragraph before the numbers

**Unsynchronised crossings fell 152 → 137. Deduplicated findings fell 50 → 37.
No RTL changed. Not one bug was fixed.** Every crossing that left the report
left because a declaration in `cdc/nanosoc_eth_chiplet.sgdc` was wrong or
missing, and the fall measures the setup converging on the design — nothing
else. Reporting "13 CDC findings closed" would be false.

The number that moved in the *useful* direction moved the other way:

| | Baseline | Round 2 |
|---|---:|---:|
| Findings classed **REAL** | **5** | **10** |

Five findings the baseline filed as "setup artefact — just add a declaration"
turn out, on the RTL and firmware evidence, to be real unsynchronised crossings
that no declaration can honestly retire. They are named in §4. **That
reclassification is the actual result of this round.** The count going down is
the bookkeeping.

**All five of the baseline's REAL findings are still present, with unchanged
crossing counts.** Verified explicitly and individually — §5.

---

## 1. Invocation

Identical to the baseline except for the run directory. Same goal, same flist,
same black boxes, same `< /dev/null` discipline.

```bash
export CHIPLET=${CHIPLET_HOME}
export SPYGLASS_HOME=${SPYGLASS_HOME}
source $CHIPLET/set_env.sh
source $CHIPLET/nanosoc-multicore-system/set_env.sh
source $CHIPLET/tidelink/set_env.sh

export FLIST=$CHIPLET/build/cdc/b7/run-20260817/nanosoc_eth_chiplet_b7.flist  # unchanged
export SG_TOP=nanosoc_eth_chiplet
export SGDC=$CHIPLET/cdc/nanosoc_eth_chiplet.sgdc                             # EDITED
export SWL=$CHIPLET/cdc/waiver.swl                                            # still zero waivers

timeout --signal=TERM --kill-after=60 5700 \
  $SPYGLASS_HOME/bin/spyglass -batch \
      -project $CHIPLET/build/cdc/b7/run2-20260817/nanosoc_eth_chiplet_b7r2.prj \
      -goals "cdc/cdc_verify_struct" < /dev/null
```

Reproduce with `build/cdc/b7/run2-20260817/run_round2.sh`. Exit code 0 on all
three passes; licence released cleanly each time; no seat held.

| | |
|---|---|
| Goal | `cdc/cdc_verify_struct` — structural only, as the baseline requires |
| `axi_chiplet_controller` | **still black-boxed.** B8 not touched |
| `cdc/waiver.swl` | **still contains zero `waive` statements.** Nothing here is a waiver |
| Passes | 3 (pass 1 = groups A/B/C, pass 2 = + HA1588, pass 3 = final). All three logs kept |

### What changed, and what deliberately did not

Only `cdc/nanosoc_eth_chiplet.sgdc` (and a status paragraph in `cdc/README.md`)
were edited. In particular **no tool parameter was loosened**:
`cdc_qualifier_depth` stays at 3, `-allow_merged_qualifier` stays at `strict`.
Turning a global knob until a report goes green is not analysis, and §3c records
the one place that would have bought 33 crossings.

---

## 2. The delta

### 2a. Headline counts

| Level | Baseline | Round 2 | Δ |
|---|---:|---:|---:|
| Raw messages | 885 | 878 | −7 |
| — Errors | 175 | 160 | −15 |
| — Warnings | 92 | 91 | −1 |
| — Infos | 618 | 627 | **+9** |
| `Ac_unsync01` (scalar unsync) | 96 | 90 | −6 |
| `Ac_unsync02` (vector unsync) | 56 | 47 | −9 |
| **Unsynchronised crossings** | **152** | **137** | **−15** |
| Unique (source, dest) pairs | 150 | 135 | −15 |
| **Deduplicated findings (unique source)** | **50** | **37** | **−13** |
| `Ac_sync02` (**recognised** vector sync) | 65 | **71** | **+6** |
| `Clock_check07` (multi-definition on clock) | 1 | **0** | −1 |

The **+6 on `Ac_sync02` is the honest half of the story**: those six crossings
did not disappear, they moved from "unsynchronised" to "synchronised, by a
user-defined qualifier". The tool now agrees they are safe and says why.

### 2b. Nothing else moved — checked, not assumed

| Rule | Baseline | Round 2 |
|---|---:|---:|
| `Ac_coherency06` | 41 | 41 |
| `Reset_sync04` | 14 | 14 |
| `Ac_conv02` / `Ac_conv01` / `Ac_conv04` | 12 / 7 / 5 | 12 / 7 / 5 |
| `Ac_glitch03` | 9 | 9 |
| `Reset_sync02` | **5** | **5** |
| `Ar_unsync01` | **1** | **1** |
| `Ar_sync01` / `Ac_sync01` | 27 / 72 | 27 / 72 |

`Reset_sync02` (5) and `Ar_unsync01` (1) are the two rules that corroborate the
baseline's real reset findings. **Both are unchanged.** If a declaration had
masked a reset crossing, this is where it would have shown.

### 2c. Where the crossings went, by domain pair

| Source → destination | Baseline | Round 2 | Δ | Why |
|---|---:|---:|---:|---|
| `sys_fclk` → `mrx_clk` | 44 | 44 | 0 | untouched |
| `dap_swclktck` → `sys_fclk` | 33 | 33 | **0** | qualifier declared, **not accepted** — §3c |
| `sys_fclk` → `mtx_clk` | 30 | 30 | 0 | untouched |
| `sys_fclk` → `rtc_clk` | 24 | 18 | −6 | HA1588 load-strobe qualifiers — §3d |
| `user_ref_clk` → `sys_hclk` | 5 | **0** | −5 | five defaulted black-box pins — §3a |
| `sys_fclk` → `qspi_sclk` | 3 | **0** | −3 | QSPI is not an async domain — §3b |
| `qspi_sclk` → `sys_fclk` | 1 | **0** | −1 | same |
| `mrx_clk`/`mtx_clk` → `sys_fclk` | 3 / 3 | 3 / 3 | 0 | untouched |
| `rtc_clk` → `sys_fclk` | 2 | 2 | 0 | untouched |
| **`sys_fclk` → `user_ref_clk`** | **2** | **2** | **0** | **real findings 32/33 — intact** |
| **`sys_hclk` → `pad_clk_tx`** | **1** | **1** | **0** | **real finding 49 — intact** |
| **`pad_clk_rx` → `sys_hclk`** | **1** | **1** | **0** | **real finding 50 — intact** |

### 2d. The 13 retired findings, individually

| Baseline # | Source | Xings | Retired by |
|---|---|---:|---|
| 1 | `u_tidelink.scan_out` | 1 | §3a `abstract_port` |
| 2 | `u_tidelink.i2c_sda_t` | 1 | §3a |
| 3 | `u_tidelink.i2c_sda_o` | 1 | §3a |
| 4 | `u_tidelink.i2c_scl_t` | 1 | §3a |
| 5 | `u_tidelink.i2c_scl_o` | 1 | §3a |
| 31 | `<qspi>…u_qspi_controller.current_state` | 1 | §3b clock domain |
| 37 | `qspi_io_i` | 1 | §3b |
| 47 | `<qspi>…qspi_qio_mode_latched` | 1 | §3b |
| 48 | `<qspi>…QSPI_IO_o_reg` | 1 | §3b |
| 42 | `<eth>.u_ha1588.u_rgs.reg_14` | 1 | §3d qualifier |
| 43 | `<eth>.u_ha1588.u_rgs.reg_18` | 3 | §3d |
| 45 | `<eth>.u_ha1588.u_rgs.reg_30` | 1 | §3d |
| 46 | `<eth>.u_ha1588.u_rgs.reg_24` | 1 | §3d |
| | **total** | **15** | |

**No finding appeared that was not in the baseline, and no surviving finding
changed its crossing count.** (Pass 2 briefly produced three "new" findings —
§6 explains why that was a measurement artefact and how it was closed.)

---

## 3. Every declaration added, with its RTL justification

### 3a. Five `abstract_port` lines on the black-boxed controller — **4 proven, 1 argued**

Baseline group A, findings 1–5. Five `axi_chiplet_controller` output pins had no
`abstract_port`, were silently defaulted to `user_ref_clk`, and contradicted the
chiplet-port declarations in §5 of the SGDC — manufacturing a
`user_ref_clk → sys_hclk` crossing on five wires that carry **no logic at all**
between the two ends (`tidelink_top.sv:3028-3032,3040` connect them straight to
the chiplet ports).

**The four I2C pins — proven.**

```
axi_chiplet_controller.sv:3378   i2c_master_axil       u_i2c_master ( .clk(apb_clk) ...
axi_chiplet_controller.sv:3443   i2c_slave_axil_master u_i2c_slave  ( .clk(apb_clk) ...
axi_chiplet_controller.sv:3542   assign i2c_scl_o = role_is_master ? mst_scl_o : slv_scl_o;
axi_chiplet_controller.sv:3549   assign i2c_scl_t = role_is_master ? mst_scl_t : slv_scl_t;
axi_chiplet_controller.sv:3550   assign i2c_sda_o = role_is_master ? mst_sda_o : slv_sda_o;
axi_chiplet_controller.sv:3551   assign i2c_sda_t = role_is_master ? mst_sda_t : slv_sda_t;
axi_chiplet_controller.sv:676-679  role_effective / role_is_master  (apb_clk-domain)
tidelink_top.sv:2815-2816        .apb_clk(hclk), .app_clk(hclk)
```

Both cores that drive the mux inputs run on `apb_clk`; the mux select is
`apb_clk`-domain; `apb_clk` is `hclk`. So `app_clk` is the correct declaration
and it *agrees with* the existing chiplet-port declaration rather than
contradicting it.

**`scan_out` — argued, and the argument is stated rather than hidden.** The RTL
cannot tell us which internal flop terminates the scan chain, because the module
is stopped. What is checkable is narrower: the pin is a pure feedthrough to a
chiplet primary output with no flop or gate on the path, and §3 of the SGDC
case-analyses `scan_mode`/`scan_shift`/`scan_clk`/`scan_in` to 0 so no functional
path exists on it. Two ends of one logic-free wire had contradictory domains;
the report was measuring the contradiction. The SGDC comment flags it for revisit
if the DFT case analysis is removed or when B8 lands.

### 3b. QSPI is not an independent clock domain — **proven**

Baseline group B, findings 31/37/47/48. The baseline's own reasoning ("the
divider is programmable, so the phase relationship is not guaranteed") is wrong.

```verilog
// nanosoc-multicore-system/ahb_qspi/logical/qspi_controller/logical/qspi_clock_div.v
:10  assign QSPI_SCLK_i = (QSPI_CLK_DIV==5'h00) ? HCLK : QSPI_SCLK_reg;
:13  always @(posedge HCLK or negedge HRESETn) begin
:19,23   QSPI_SCLK_reg <= ~QSPI_SCLK_reg;
```

Both arms of that mux are HCLK. Every QSPI_SCLK edge is an HCLK edge. A
programmable *integer* divide off one launch edge changes frequency; it does not
create an independent oscillator and cannot present a metastability window. The
chip SDC already agrees — `qspi_constraints.sdc:2` is a
`create_generated_clock`, not a `create_clock`.

Change: `clock -name qspi_sclk -domain qspi_domain` → `-domain sys_fclk_domain`.
It stays a declared clock object, so launch attribution and STA are unaffected;
only the CDC domain changed. As a bonus the stray `Clock_check07`
multi-definition warning (which named exactly `sys_fclk` / `qspi_sclk`) went to
zero.

*What this does not claim:* nothing about setup/hold on the divided path or the
`qspi_io_i` pad return timing. Both are STA questions the chip SDC owns.

### 3c. CoreSight DP→AP `busreq`/`busack` qualifier — **RTL proven, tool would not accept it, 0 of 33 retired**

This was the baseline's flagship prediction: *"One declaration retires 33
crossings."* **It retires zero.** The declaration is correct; SpyGlass will not
carry it.

**The RTL evidence is as strong as it gets** — ARM asserts the contract itself.
Three registers are written in the probe-clock domain and read in `dapclk`:

```
cxdapswjdp_sw_dp_protocol.v:228,1049-1051   ap_sel[7:0]  <= shift_reg[31:24]
cxdapswjdp_sw_dp_protocol.v:221,1049-1052   ap_bank_sel  <= shift_reg[7:4]
cxdapswjdp_sw_dp_protocol.v:157,1337-1341   ibuswdata_cdc_check <= shift_reg
cxdapswjdp_sw_dp_protocol.v:1366-1369       busreq=i_bus_req_d; busaddr_31to24=ap_sel;
                                            busaddr_7to2={ap_bank_sel,ap_reg_sel};
                                            buswdata=i_bus_wdata
```

The control path is properly synchronised and the data path is not — the
textbook qualified crossing:

```
cxdapswjdp_dapclk.v:100-108      cxdapswjdp_dp_apb_sync u_..._dp_apb_sync (.busreq(busreq_c), .busreq_d(busreq_d))
cxdapswjdp_dp_apb_sync.v:78-86   cx_en_sync u_sync_bus_req (.clk(dapclk), .sync_do(busreq_d))
cxdapswjdp_dapclk.v:89           u_cxdapswjdp_sw_dp_apb_if .busreq (busreq_d)   <-- SYNCHRONISED
```

and the destination-domain gating is unconditional on it:

```
cxdapswjdp_sw_dp_apb_if.v:142-145   DAP_APBIDLE : apb_next_en = dapclken & busreq;
cxdapswjdp_sw_dp_apb_if.v:342-347   dapaddr_31to24 / dapaddr_7to2 / dapwdata driven only when
                                    apb_curr==DAP_APBENABLE | DAP_APBSETUP
cxdapswjdp_sw_dp_apb_if.v:335       dapsel = apb_curr==ENABLE | SETUP
cxdapswjdp_sw_dp_apb_if.v:258-264   busack asserted only in DAP_APBEND
cxdapswjdp_sw_dp_apb_if.v:171-174   APBEND -> APBIDLE only on ~busreq
cxdapswjdp_sw_dp_protocol.v:1304-1309  while i_bus_req: request drops only on busack
cxdapswjdp_sw_dp_protocol.v:910     write buffer reloads only when ~i_bus_req & ~busack
```

and ARM's own OVL assertions state the data-stability property verbatim:

```
cxdapswjdp_sw_dp_apb_if.v:356-357  hs_start = busreq & apb_curr==DAP_APBIDLE
                                   hs_end   = busreq & apb_curr==DAP_APBEND & !busacki
cxdapswjdp_sw_dp_apb_if.v:386-392  assert_win_unchange "busaddr_* must remain static during handshake."
cxdapswjdp_sw_dp_apb_if.v:395-400  assert_win_unchange "buswdata must remain static during handshake."
```

**What the tool did, measured over two passes.** With
`qualifier -name .../busreq_d -from_clk dap_swclktck -to_clk sys_fclk`, the name
resolved and the qualifier *was used*: two crossings changed their reason from
`Qualifier not found` to `User-defined qualifier merges with another source with
non-deterministic enable condition before gating logic`. So SpyGlass agrees this
is a qualifier and rejects it on the merge under `-allow_merged_qualifier:
strict`. The other 21 still read `Qualifier not found` — never reached.

A second form (`-dest_qual` with a per-declaration `-dest_qual_depth 5`, on the
theory that the default `cdc_qualifier_depth: 3` cannot span the two state
machines in series here — the DP's `apb_curr` and then the AP's own `cur_state`)
produced `QualifierSetup` **Warning**: *"'qualifier' constraint 'dest_qual :
…busreq_d' is not used to synchronize any crossing"*. Depth was not the blocker.
That line was removed rather than left emitting a standing warning.

**The declaration was kept anyway**, because it is true and because it improves
the diagnosis on the two crossings it reaches. The 33 crossings stay in the
report.

**What was NOT done to make the number move:** raising the global
`cdc_qualifier_depth` or relaxing `-allow_merged_qualifier`. Either would have
retired crossings across the whole design — including on the 18 qualifiers
SpyGlass inferred by itself, on paths nobody has examined. If someone wants these
33 closed, the route is the functional `cdc/cdc_verify` goal or a formal check of
the handshake, not a bigger depth number.

### 3d. HA1588 RTC load strobes — **proven, and it corrects the baseline**

Baseline group E filed `reg_14/18/24/2c/30` (findings 42–46) as "static
configuration registers … the textbook `quasi_static` case", needing only a
software contract. **Both halves of that are wrong.**

*They are not static.* They are the PTP servo's live discipline path. `reg_24`
is the frequency-trim word, rewritten on essentially every PTP exchange
(`firmware/apps/ptp_slave/ptp_slave.c:151-158`, `servo_set_trim` →
`ha1588_rtc_set_period`); `reg_14`/`reg_18` are rewritten on every phase step
(`ptp_slave.c:204,227`). A `quasi_static` here would have asserted something the
firmware in this repository visibly violates several times a second.

*They do not need a software contract, because the hardware carries the
handshake.* This is a multi-cycle-path bus with a properly synchronised load
strobe — a **qualifier**:

```
reg.v:158-165   software writes the DATA register    (if (wr_in && cs_24) reg_24 <= data_in;)
reg.v:231-233   software then sets a COMMAND bit     (time_ld=reg_00[3], perd_ld=[2], adjt_ld=[1])
reg.v:266-276   3-FF sync + edge detect, all `always @(posedge rtc_clk_in)`:
                  time_ld_out   = time_ld_s2 && !time_ld_s3
reg.v:280-290     period_ld_out = perd_ld_s2 && !perd_ld_s3
reg.v:294-304     adj_ld_out    = adjt_ld_s2 && !adjt_ld_s3
rtc.v:53-54     if (period_ld) period_fix <= period_in;        <- reg_20,reg_24
rtc.v:58-59     if (adj_ld)    adj_cnt    <= adj_ld_data;      <- reg_30
rtc.v:103-105   if (time_ld)   time_acc_30n_08f_pre_pos/_pre_neg <= ...
rtc.v:129-131   if (time_ld)   time_acc_30n_08f <= time_reg_ns_in;
                               time_acc_48s     <= time_reg_sec_in;
ha1588.v:156-174  the rtc instance wiring
```

Three qualifiers declared, **object-scoped** (`-from_obj` / `-to_obj`), not
clock-scoped. That choice is load-bearing: the `sys_fclk → rtc_clk` clock pair
holds 24 baseline crossings and **17 of them belong to finding 30**, the largest
REAL finding in the run. A clock-pair-scoped qualifier here would have been
pointed straight at the one finding this exercise most needs to keep.

**Result, and it is the right kind of result:** all six crossings moved out of
`Ac_unsync02` and into `Ac_sync02`, attributed explicitly to the user
declaration —

```
reg_14 -> time_acc_48s                "Mux-select sync (user-defined qualifier)"
reg_18 -> time_acc_30n_08f            "Mux-select sync (user-defined qualifier)"
reg_18 -> time_acc_30n_08f_pre_neg    "Mux-select sync (user-defined qualifier)"
reg_18 -> time_acc_30n_08f_pre_pos    "Mux-select sync (user-defined qualifier)"
reg_30 -> adj_cnt                     "Mux-select sync (user-defined qualifier)"
reg_24 -> period_fix                  "Enable Based User-Defined Qualifier"
```

They are not gone from the report; they are now *recognised as synchronised*,
which is a stronger statement than silence.

---

## 4. What was NOT declared, and why — including five reclassifications

Everything here is a crossing still in the report, left there on purpose. Full
detail lives in §9 of `cdc/nanosoc_eth_chiplet.sgdc`.

### 4a. FIVE FINDINGS RECLASSIFIED FROM "SETUP ARTEFACT" TO **REAL**

These are the round's real output. Each was on the baseline's list of 26
declaration bugs; each turns out to be a genuine unsynchronised crossing.

**Findings 11, 12, 14 — EthMAC `MODER` (26 crossings).** The baseline proposed
`quasi_static`. `MODER` is not configuration, it is the run/stop control:

```
eth_registers.v:902-918   [1] TXEN  [0] RXEN  [10] FULLD  [7] LOOPBCK
```

and firmware toggles all four *while the MAC is running*:
`firmware/apps/eth_netapp/driver/ethmac.h:114-122` (enable/disable RMW of
TXEN|RXEN), `:126-134` (FULLD, and `:260-261` says to call it after
autonegotiation — so again on every renegotiation), `:147-152` (LOOPBCK);
`firmware/apps/eth_mac_loopback/main.c:138-140` explicitly depends on RXEN rising
0→1 as a runtime event; `firmware/apps/ptp_slave/main.c:192,466-470` does a live
read-modify-write of MODER over the SWD proxy during operation.

The consumption side is genuinely unprotected. `r_RxEn` at least gets a flop
(`eth_top.v:738`, `RxEnSync <= r_RxEn` in `mrx_clk`), but **`r_LoopBck` reaches
the RX datapath combinationally with no synchroniser at all**:

```verilog
eth_top.v:598   assign MRxDV_Lb = r_LoopBck ? mtxen_pad_o : mrxdv_pad_i & RxEnSync;
```

A `quasi_static` on MODER would have deleted that from the report. **26 crossings
— the single largest block in the run — were one declaration away from being
hidden.**

**Findings 28, 29 — HA1588 `reg_44` / `reg_64` (2 crossings).** The only two
HA1588 registers that cross into the MII domains rather than `rtc_clk`
(`reg.v:244,249` → `ha1588.v:183,201` → `tsu.v:32` → `ptp_parser.v:226,229`).
Unlike their `rtc_clk` siblings in §3d there is **no load strobe and no
synchroniser** on the path — nothing for a qualifier to attach to. Meanwhile
firmware rewrites them mid-run to change which PTP message IDs get timestamped
(`ptp_tsu_loopdiag/main.c:206-207` then `:300`; `ptp_slave/main.c:599-600` vs
`:654-655`). `ptp_parser.v:41` even carries a stale comment calling the crossing
*"quasi-static"* — precisely the assumption the firmware violates.

### 4b. Declined — a software contract that needs a name against it

| Finding(s) | Register | Evidence | Verdict |
|---|---|---|---|
| 13, 26 | `COLLCONF` | no writer in RTL or firmware; IEEE collision constants | safe, but still a software claim |
| 16, 24 | `PACKETLEN` | written once at bring-up, always the literal `0x002E0600` (`eth_rx_diag/main.c:64` + 4 siblings) | safe, but still a software claim |
| 25 | `IPGR2` | no writer anywhere; sits at reset default `7'h12` (`eth_defines.v:219`) | safe, but still a software claim |
| 15 | `CTRLMODER` | no writer today, but carries TXFLOW/RXFLOW/PASSALL (`eth_registers.v:932-934`) — PAUSE control is normally toggled on link-state change | contract-dependent |
| 27 | `MAC_ADDR0` | no writer today, but feeds the `mrx` address filter (`eth_top.v:653`) and changing a MAC address is a legitimate runtime op | contract-dependent |

The baseline's own §6E point stands: this class has never been adjudicated at
*any* level, block or integration, and a declaration encoding "software
configures before it enables" should carry a name against it. **The three
lines for the safe subset are pre-drafted in §9a of the SGDC** so approving them
is a one-minute job for the owner. They were not enabled here.

### 4c. Declined — the hardware does not implement the contract

**Findings 35, 36 — HA1588 TSU timestamp queues (4 crossings).** The baseline
called these "safe by construction … needs a qualifier or a targeted waiver".
The FIFO half is right — `ptp_queue.v` is a clean gray-code design
(`:39` `mem[0:15]`, `:61` write, `:87,93-94` `wr_gray_rd1/rd2`, `:116`
`rdempty = (rd_gray == wr_gray_rd2)`, `:68` `rd_bin_next = rd_bin + (rdreq &
~rdempty)`), so the read address can never overtake the synchronised write
pointer.

But a qualifier asserts the **destination** only samples when the qualifier says
valid, and this RTL does not do that: `ptp_queue.v:82` is a combinational array
read live even when empty, and the capture flops `reg.v:403` / `reg.v:461` have
**no enable** — `rdempty` never reaches them. Declaring a qualifier would assert
a hardware property the design does not implement. Closing these needs a
`cdc_false_path` with a written justification, or an RTL change to enable the
capture flop. Owner decision. Left in the report.

**Finding 44 — HA1588 `reg_2c` → `u_rtc.time_adj` (1 crossing).** Looks like a
fourth member of the §3d group; is not. `reg_2c` is `period_adj`, consumed live
on a counter terminal count, not on a load strobe:

```verilog
rtc.v:65-68   if (adj_cnt==0) time_adj <= period_fix + period_adj;
              else            time_adj <= period_fix + 0;
```

The `adj_ld` strobe loads `adj_cnt` (from `reg_30`) and `period_adj` is sampled
an arbitrary number of `rtc_clk` cycles later. The strobe opens a window but does
not gate the sample. A genuine software contract, and an owner's assertion.

### 4d. Declined — and this is the important one

**Findings 32, 33 — `axi_chiplet_controller` `hresetn` / `poresetn`.** These two
REAL findings are caused by *exactly the same silent-defaulting mechanism* as
group A:

```
u_soc.u_chip_core.u_cpu_0.…u_sys_hresetn_sync.rst_sync2_n  [sys_fclk]
    -> u_tidelink.u_chiplet_controller(axi_chiplet_controller/hresetn)  [user_ref_clk]
u_soc.u_chip_core.u_cpu_0.…u_sys_poresetn_sync.rst_sync2_n [sys_fclk]
    -> u_tidelink.u_chiplet_controller(axi_chiplet_controller/poresetn) [user_ref_clk]
```

Two `abstract_port` lines would have made both vanish, and the round-2 count
would have read 135 instead of 137. **They were deliberately not added.** Unlike
the four I2C pins, these are *inputs* fanning into more than one internal reset
regime of a stopped module — §2 of the SGDC records `hresetn` feeding
`app_clk_reset` (`axi_chiplet_controller.sv:2686`) while `poresetn` feeds
`wlink_por_reset` (`:2681`), with a third recovered-RX regime behind
`role_locked`. Either line would collapse a real multi-domain reset question into
"same domain" and delete it.

The `user_ref_clk` default is arbitrary, but it errs toward **over**-reporting,
which is the safe direction. Resolving them properly needs B8.

*This is the clearest illustration in the round of the asymmetry rule: the same
mechanism, the same one-line fix, safe in one place and masking in the other, and
the difference is only visible from the RTL.*

---

## 5. THE FIVE BASELINE "REAL" FINDINGS — EXPLICIT STATUS

Checked individually against the round-2 CSVs by
`build/cdc/b7/run2-20260817/compare.py`; machine-readable result in
`build/cdc/b7/run2-20260817/real_findings_status.json`.

| # | Source signal | Baseline xings | Round-2 xings | Status |
|---|---|---:|---:|---|
| **30** | `u_soc.u_network_core.u_sys_hresetn_i_resetsync.sync_q` | 19 | **19** | **PRESENT, unchanged** |
| **32** | `…u_cpu_0.u_core_prmu.u_rstctrl.u_sys_hresetn_sync.rst_sync2_n` | 1 | **1** | **PRESENT, unchanged** |
| **33** | `…u_cpu_0.u_core_prmu.u_rstctrl.u_sys_poresetn_sync.rst_sync2_n` | 1 | **1** | **PRESENT, unchanged** |
| **49** | `u_tidelink.pad_tx` (sys_hclk→pad_clk_tx) | 1 | **1** | **PRESENT, unchanged** |
| **50** | `pad_rx` (pad_clk_rx→sys_hclk) | 1 | **1** | **PRESENT, unchanged** |

**None of the five disappeared. None changed its crossing count. No declaration
added in this round touches any of them.**

Corroborating rules are also unchanged: `Reset_sync02` still 5 (the independent
"asynchronous reset generated from a different domain" evidence behind finding
30), `Ar_unsync01` still 1 (`u_d2d_decode.dph_code[0]`, this repository's own
integration RTL).

The two declarations that came closest to these were both declined on purpose:
the `hresetn`/`poresetn` `abstract_port` lines (§4d) which would have erased 32
and 33, and a clock-scoped rather than object-scoped HA1588 qualifier (§3d) which
would have been aimed at finding 30's clock pair.

---

## 6. Two methodology findings worth carrying forward

**6a. "Unique source signals" under-counts, and retiring a source can
re-attribute rather than retire.** Round-2 pass 2 declared the HA1588 qualifiers
against `reg_14`/`reg_18`/`reg_24` only. Three findings then appeared that had
never been in the baseline's 50 — `reg_10`, `reg_1c`, `reg_20` — and the
`sys_fclk → rtc_clk` count barely moved. The buses are concatenations
(`reg.v:235-237`: `{reg_10, reg_14}`, `{reg_18, reg_1c}`, `{reg_20, reg_24}`),
so SpyGlass qualified the halves that were named and re-reported the *same*
crossings against the halves that were not. Those three registers had been
crossing all along; a multi-source crossing is reported against one named source,
so the baseline's headline "50 findings" is a lower bound, not a census. Pass 3
named both halves of each concatenation and the three absorbed cleanly.

**6b. The report's own qualifier counter is unreliable, like
`Setup_blackbox01`.** `CDC-report.rpt` states *"User-defined qualifiers used to
synchronize data crossings: 0"* — in a run where user-defined qualifiers
demonstrably moved six crossings into `Ac_sync02` with the reasons
`"Mux-select sync (user-defined qualifier)"` and `"Enable Based User-defined
qualifier"` written into the CSV. The summary line appears to count only
clock-scoped declarations. **Do not gate on it.** This is the second
false-comfort summary metric found in this setup; the baseline §3 found the
first.

---

## 7. Where the finding set stands now

| Class | Baseline | Round 2 | Note |
|---|---:|---:|---|
| Setup artefact — retired by a declaration | 26 | **13 retired** | the −13 in the count |
| Setup artefact — awaiting an owner's software contract | — | **8** | §4b, §4c; lines pre-drafted |
| **REAL — needs a fix or an explicit decision** | **5** | **10** | §4a adds MODER ×3 and reg_44/reg_64 ×2 |
| Legitimate synchroniser the tool cannot validate | 12 | 12 | 33 DAP crossings still open — §3c |
| Vendor-IP noise | 7 | 7 | untouched |

The 26 setup artefacts resolve as: **13 genuinely were declaration bugs and are
gone; 5 were misclassified and are real; 8 are software contracts needing an
owner.**

### Recommended order from here

1. **`MODER` → `mrx_clk`, especially `r_LoopBck` (`eth_top.v:598`).** 26
   crossings, unsynchronised, firmware-toggled at runtime. The largest real
   finding in the design and it was one declaration away from being invisible.
2. **Reset distribution** — finding 30 (19 crossings) plus `Reset_sync02` (5) and
   `Ar_unsync01` (1). Unchanged from the baseline's recommendation; still the
   only coherent multi-domain design question, and still first among the resets.
3. **`reg_44` / `reg_64`** — 2 crossings, no synchroniser, changed mid-run.
   Cheapest real fix in the set.
4. **Owner sign-off on §4b** — three pre-drafted `quasi_static` lines retire ~5
   more findings in minutes once someone owns the contract.
5. **D2D pad `cdc_false_path`** (findings 49/50) with written justification.
6. **B8** — un-black-box `axi_chiplet_controller`. Resolves findings 32/33
   honestly and opens the a2l replay CDC.

---

## 8. What this round does *not* cover

Everything in `CDC_B7_BASELINE.md` §7 "What this baseline does not cover"
still applies unchanged — structural goal only, `axi_chiplet_controller` still
black-boxed, four inferred black boxes still unconstrained, the one-file RTL
code-motion override still in the flist. Additionally:

- **The 33 CoreSight crossings are not closed**, only better diagnosed (§3c).
- **`Ac_coherency06` (41), `Reset_sync04` (14), `Ac_conv01/02/04` (24) and
  `Ac_glitch03` (9) were counted, not triaged** — as in the baseline. All are
  unchanged, which is evidence nothing was masked, not evidence they are clean.
- **The firmware evidence in §4a/§4b is a snapshot of today's firmware.** "No
  writer exists" is a statement about the code in this tree, which is exactly why
  §4b was left for an owner rather than declared.
- **`cdc/waiver.swl` still has zero waivers.** Nothing in this round is a waiver;
  every change is a declaration the tool re-validates structurally.

---

## 9. Artefacts

Under `build/cdc/b7/run2-20260817/`:

| Path | What |
|---|---|
| `run_round2.sh` | the invocation |
| `nanosoc_eth_chiplet_b7r2.prj` | run-local `.prj` (= baseline's + a re-pointed `projectwdir`) |
| `spyglass_round2_pass1.log` | groups A/B/C only — the pass that proved the DAP qualifier binds |
| `spyglass_round2_pass2.log` | + HA1588 qualifiers — the pass that exposed §6a |
| `spyglass_round2_pass3.log` | **final** |
| `pass1_reports/`, `pass2_reports/` | per-rule CSVs from the intermediate passes |
| `wd/…/spyglass_reports/clock-reset/*.csv` | final per-rule crossing detail |
| `compare.py` | the delta script — reproduces every number in §2 and §5 |
| `real_findings_status.json` | machine-readable §5 verdict |

Inputs edited: `cdc/nanosoc_eth_chiplet.sgdc` (§1 QSPI clock, §7a five
`abstract_port` + the `hresetn`/`poresetn` note, new §8 qualifiers, new §9
owner-decision block) and a status paragraph in `cdc/README.md`.
`cdc/nanosoc_eth_chiplet.prj` and `cdc/waiver.swl` are unchanged.
`CDC_B7_BASELINE.md` is unchanged.
