# Reset-domain analysis of the B7 CDC findings

**Date:** 2026-08-17 · **Scope:** the 5 "real" findings in `docs/CDC_B7_BASELINE.md` §5,
plus the repo-owned `Ar_unsync01` recorded there at §6 "Separately".
**Method:** RTL trace with file:line evidence, plus **two measured SpyGlass runs** (§6).

---

## 0. Verdict

**None of these is a must-fix-before-freeze. One is a should-fix, and it is not the
one the baseline pointed at.**

| # | Finding | Baseline class | This analysis | Verdict |
|---|---|---|---|---|
| 30 | `u_sys_hresetn_i_resetsync.sync_q` → 17 × `rtc_clk` | REAL | `rtc_clk` **is** `sys_fclk` on the taped-out die | **not a real finding (N1)** |
| 30 | same source → 2 × `mrx_clk` | REAL | real RDC, **structurally interlocked** (§3.2) | **accept-with-rationale** |
| 32 | PRMU `u_sys_hresetn_sync.rst_sync2_n` → `user_ref_clk` | REAL | black-box pin defaulted **and** `user_ref_clk` **is** `sys_fclk` | **not a real finding** |
| 33 | PRMU `u_sys_poresetn_sync.rst_sync2_n` → `user_ref_clk` | REAL | as 32 | **not a real finding** |
| A4B | `sys_hresetn_eff` → `SetTxCIrq_txclk` (`mtx_clk`) | Reset_sync02 | real RDC, **structurally interlocked** (§3.2) | **accept-with-rationale** |
| A4C | `ha_rst` → `u_ha1588.rst_rtc_s2` (`rtc_clk`) | Reset_sync02 | destination **is** the reset synchroniser | **not a real finding** |
| A4D | `rx_q_rst_combined` → `u_rx_tsu.queue.wr_bin` (`mrx_clk`) | Reset_sync02 | **real, unprotected, software-reachable** | **should-fix** |
| A4E | `tx_q_rst_combined` → `u_tx_tsu.queue.wr_bin` (`mtx_clk`) | Reset_sync02 | as A4D | **should-fix** |
| A4F | `role_locked_o` → `lock_thresh_sync2` (`link_rx_clk`) | Reset_sync02 | the deliberate design of `RESET_ORDERING.md` §2 | **not a real finding** |
| 65D | `sys_hresetn` → `u_d2d_decode.dph_code[0]` | `Ar_unsync01`, repo-owned | **SGDC declaration artefact — proven by measurement** | **not a real finding** |

The baseline's framing — "5 real findings concentrating in reset distribution, triage
this first" — was the right instinct and the wrong target. The reset distribution into
the MII domains **is already interlocked by construction**, and the tool cannot see the
interlock because it is a clock-gating property, not a synchroniser. The one genuine
exposure is a **software-triggered** reset pulse the baseline did not single out, and it
is a PTP-timestamp-quality defect, not a bring-up or wedge risk.

**Nothing here needs to land in the batched netlist.** The only RTL change proposed
(§7 R2) is optional and can wait for N2; the constraint changes (§7 R1) touch
`cdc/**` only and change no hardware.

---

## 1. The reset tree as actually built

Everything below is traced from the source this build compiles
(`build/cdc/b7/run-20260817/nanosoc_eth_chiplet_b7.flist`).

```
 CLK pad (uPAD_CLK_I)                       NRST pad
 nanosoc_eth_chiplet_pads.v:267-272         -> sys_sysresetn
        |                                         |
        | soc_sys_fclk                            |
        +---> sys_fclk ---+                       |
              (ALSO drives rtc_clk and user_ref_clk -- see §2)
                          |                       |
                  u_chip_core (CPU1) PRMU = CLOCK/RESET MASTER
                  slcorem0p_prmu.v:93     assign SYS_HCLK = SYS_FCLK   <-- 1:1, no divide
                  slcorem0p_rstctrl.v:88-95
                      cm0p_rst_sync u_sys_hresetn_sync (.CLK(SYS_HCLK))
                          |
                          +--> sys_hresetn   (chiplet OUTPUT port,
                          |     nanosoc_multicore_soc.sv:625-630)
                          |        |
                          |        +--> u_d2d_decode      (nanosoc_eth_chiplet.sv:653-654)  clk = sys_hclk
                          |        +--> u_tlapb_bridge    (:683-684)                        clk = sys_hclk
                          |        +--> u_tcapb_bridge    (:716-717)                        clk = sys_hclk
                          |        +--> u_tidelink        (:762-763, phc_resetn :766)       clk = sys_hclk
                          |        +--> u_tidechart       (:971-972)                        clk = sys_hclk
                          |        +--> top-level flop    (:311-312)                        clk = sys_hclk
                          |     ALL SAME DOMAIN AS THE SYNCHRONISER'S OWN CLOCK.
                          |
                          +--> u_network_core.sys_hresetn_i     (nanosoc_multicore_soc.sv:863)
                                    | CLK_RST_CONSUMER(1)       (:858)
                                    | ethernet_ss_ahb_rmii.sv:346-353
                                    |   soc_glue_reset_sync #(3) u_sys_hresetn_i_resetsync
                                    |       .clk(sys_hclk_eff)  <-- = u_chip_core_sys_hclk (:862)
                                    v
                              sync_q[2] = sys_hresetn_i_sync = sys_hresetn_eff  (:364-372)
                                    |
        +---------------------------+---------------------------------+
        |                                                             |
   u_ethmac_0.HRESETn                                        u_rmii_to_mii.RESETn
   (ethernet_ss_ahb_rmii.sv:490)                             (ethernet_ss_ahb_rmii.sv:556)
        |                                                             |
   ethmac_subsystem_ahb.v:183  .presetn(HRESETn)               rmii_to_mii.v:119-130
        |                                                        4-stage rstn_sync on
   ethmac_subsystem_apb.v:312  eth_top .wb_rst_i(~presetn)       rmii_ref_clk
        |                                                             |
   eth_top.v:568-569  TxReset = RxReset = wb_rst_i             rmii_to_mii.v:277-283 mrx_clk
        |                                                      rmii_to_mii.v:320-326 mtx_clk
        v                                                             |
   ~122 always-blocks of the form                                     |
   always @(posedge M{R,T}xClk or posedge Reset)  <-------------------+
                                              THE MII CLOCKS ARE GENERATED BY,
                                              AND HELD AT 0 BY, THIS SAME RESET.
```

Two facts in that diagram do the whole job, and neither is visible to a structural CDC
tool:

1. **`SYS_HCLK` *is* `SYS_FCLK`** — `slcorem0p_prmu.v:93`, a bare `assign`, no divider.
   *(This also closes the `[OWNER]` question left open at `cdc/nanosoc_eth_chiplet.sgdc`
   §1 and `constraints/nanosoc_eth_chiplet_cdc.sdc:65-71`: the ratio is 1:1.)*
2. **`u_rmii_to_mii` takes the same `sys_hresetn_eff` that resets the MAC**, and both
   MII clocks are async-cleared to `1'b0` by its `rstn_sync`. The MAC's clock cannot
   run until the MAC's reset has been released.

---

## 2. `rtc_clk` and `user_ref_clk` do not exist on the taped-out die

This is the single largest correction to the baseline, and it is a two-line fact.

```
build/chip/rtl/nanosoc_eth_chiplet_chip.v:102    .rtc_clk       (sys_fclk),  // tied
build/chip/rtl/nanosoc_eth_chiplet_chip.v:103    .user_ref_clk  (sys_fclk),  // tied
```

and there is no pad for either:

```
ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:137-139
  "rtc_clk and user_ref_clk are NOT connected here: the generated wrapper aliases
   both onto its own sys_fclk port ... All three therefore share uPAD_CLK_I."
ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:267-272   PDDW04DGZ_G uPAD_CLK_I
```

The taped-out block is `nanosoc_eth_chiplet_pads` (`ASIC/eth-chiplet/design.mk:78`,
`ASIC/genus-innovus/scripts/config.tcl:157`), which instantiates that wrapper. So on N1
silicon `sys_fclk`, `sys_hclk`, `rtc_clk` and `user_ref_clk` are **one physical net off
one pad**. There is no `sys_fclk → rtc_clk` crossing and no `sys_fclk → user_ref_clk`
crossing to have.

`rmii_ref_clk` is different — it has its own pad (`nanosoc_eth_chiplet_pads.v:416-421`),
so `mrx_clk`/`mtx_clk` **are** genuinely asynchronous to the fabric. That distinction is
what separates the findings that survive from the ones that do not.

**This does not make the SGDC's top-level choice wrong.** `cdc/nanosoc_eth_chiplet.sgdc`
§1 deliberately analyses `nanosoc_eth_chiplet`, not `_chip`, so the RTL is exercised as
if the clocks were independent. That is the correct choice for *RTL robustness* — a
future respin, or the FPGA build, may bond `rtc_clk` separately. It is the wrong lens
for *"is this an N1 silicon risk"*, and the baseline read the answer in the first lens
while asking the second question. Both readings should be recorded; they are not in
conflict.

Measured effect: **17 of finding 30's 19 crossings, and both of findings 32 and 33, are
in the aliased domains.** Verified against the current SGDC:

```
17  ... -> nanosoc_eth_chiplet.rtc_clk
 2  ... -> nanosoc_eth_chiplet.u_soc.u_network_core.u_rmii_to_mii.mrx_clk
```

Note also that finding 30's `rtc_clk` destinations are **synchronous** resets, not async
clears — `reg.v:252-262` (`rtc_rst_s1/s2/s3`), `:309-320` (`time_rd_s1/s2/s3`) and
siblings are all `always @(posedge rtc_clk_in) if (rst) ...`. Even with `rtc_clk`
independent, these are ordinary data crossings of a long-held level, not
recovery/removal hazards. The baseline's premise for finding 30 — "used as an async
clear on a flop in domain B" — is not what the RTL does at those 17 destinations.

---

## 3. The `mrx_clk` / `mtx_clk` half — real crossings, structurally interlocked

### 3.1 The exposure is real as stated

`eth_top.v:568-569` ties both `TxReset` and `RxReset` to `wb_rst_i`, and `wb_rst_i` is
`~presetn` = `~sys_hresetn_eff` (`ethmac_subsystem_apb.v:312`). The OpenCores MAC then
uses that fabric-domain net as an **asynchronous** reset throughout the MII domains:

| File (compiled set) | `posedge M{R,T}xClk or posedge <rst>` blocks | reset-branch reg targets |
|---|---:|---:|
| `ethmac_patches/eth_wishbone.v` | 37 | 40 |
| `eth_receivecontrol.v` | 15 | 16 |
| `eth_macstatus.v` | 15 | 15 |
| `eth_txethmac.v` | 13 | 14 |
| `eth_transmitcontrol.v` | 10 | 10 |
| `eth_registers.v` (`TxClk`/`RxClk`) | 7 | 7 |
| `eth_rxethmac.v` | 6 | 13 |
| `eth_maccontrol.v`, `eth_rxaddrcheck.v` | 4 + 4 | 5 + 4 |
| `eth_rxcounters.v`, `eth_txcounters.v` | 3 + 3 | 3 + 3 |
| `eth_random.v`, `eth_txstatem.v`, `eth_rxstatem.v` | 2 + 2 + 1 | 2 + 11 + 6 |
| **Total** | **122** | **149** |

(Counted over the files in the b7 flist — i.e. `ethmac_patches/eth_wishbone.v`, not the
vendor copy. "reg targets" counts named registers cleared in the reset branch, so the
flop count is higher again once vectors are expanded.)

**STA gives no backstop.** `ASIC/genus-innovus/inputs/constraints.sdc:392-397` puts
`{rmii_ref_clk mii_rx_clk mii_tx_clk}` in a different `set_clock_groups -asynchronous`
group from `$EXTCLK`, which is a reciprocal false path. Recovery/removal from the
fabric reset into the MII flops is therefore **not timed**. If the hazard were live,
nothing downstream would catch it.

### 3.2 Why it is nevertheless safe — the clock-gating interlock

The same net that resets the MAC also resets the module that *generates the MAC's
clocks*:

```
ethernet_ss_ahb_rmii.sv:490   u_ethmac_0     .HRESETn (sys_hresetn_eff)
ethernet_ss_ahb_rmii.sv:556   u_rmii_to_mii  .RESETn  (sys_hresetn_eff)
```

and inside `rmii_to_mii`:

```verilog
rmii_to_mii.v:122   always @(posedge rmii_ref_clk or negedge RESETn) begin
rmii_to_mii.v:123-125   if (!RESETn) begin rstn_sync <= 1'b0; rstn_shift <= 3'b000; end
rmii_to_mii.v:127        else {rstn_sync, rstn_shift} <= {rstn_shift, 1'b1};

rmii_to_mii.v:277-283   always @(posedge rmii_ref_clk or negedge rstn_sync)
                            if (!rstn_sync) mrx_clk <= 1'b0; else if (tick) mrx_clk <= ~mrx_clk;
rmii_to_mii.v:320-326   ... identical for mtx_clk
```

Sequence on any reset release, warm or cold:

1. `sys_hresetn_eff` rises. The MAC's async reset is now released — but `mrx_clk` and
   `mtx_clk` are still clamped at `1'b0` because `rstn_sync` is still 0.
2. `rstn_sync` rises on the **4th** `rmii_ref_clk` rising edge after that (the shift
   register is `{rstn_sync, rstn_shift[2:0]}`, reset to all-zero).
3. The first `mrx_clk`/`mtx_clk` rising edge follows on the next `tick` — the **5th**
   `rmii_ref_clk` edge at 100 Mbps, later at 10 Mbps.

So the MAC's asynchronous reset has been **stably deasserted for ≥5 `rmii_ref_clk`
periods (≥100 ns at 50 MHz) before any MII flop sees a clock edge at all.** There is no
recovery/removal window, because there is no clock edge near the removal edge. On
assertion the reset is asynchronous and immediate, which is correct and unchanged.

This is a *structural* argument, not a timing-margin one: the ordering is enforced by
the shift register, not by a race between two clock trees. It holds for a cold start,
for a `SYSRESETREQ` warm reset, and for a PHY whose reference clock appears late or
never.

**This retires findings 30 (`mrx_clk` half) and A4B as silicon risks.** They remain
genuine *structural* crossings — SpyGlass is not wrong to print them — but the design
already answers them by a mechanism the tool has no rule for.

### 3.3 What would make §3.2 wrong

Stated so it can be checked rather than trusted:

- If any MII-domain flop were reset by a net **other** than `sys_hresetn_eff`. Checked:
  `ethmac_subsystem_ahb.v:183` passes `HRESETn` straight through as `presetn`, with no
  soft-reset or gating term, and `eth_top.v:568-569` derives `TxReset`/`RxReset` from it
  alone. The only exception is the PTP queue — which is §4, and is exactly the case
  where this argument fails.
- If `mrx_clk`/`mtx_clk` could come from anywhere but `u_rmii_to_mii`. There are no MII
  clock pads on this die (`nanosoc_eth_chiplet_pads.v` bonds `RMII_REF_CLK` only), and
  the chiplet instantiates the RMII variant.
- If `rmii_to_mii`'s `rstn_sync` were ever bypassed in scan/DFT. `scan_asyncrst_ctrl` is
  tied 0 in the chip wrapper, so mission mode is the only mode on this die.

The SoC-Labs-authored blocks in the same subsystem do **not** rely on this argument —
they carry their own per-domain reset bridges (`ethmac_subsystem_apb.v:480-515`,
"ASIC sign-off bug 6"), which SpyGlass recognises by name (`mrx_rstn_sync`,
`mtx_rstn_sync`). That is the belt-and-braces treatment and it is the right precedent
for anything new.

---

## 4. The one that is actually exposed: the PTP timestamp-queue reset

`A4D` / `A4E` are a different mechanism from everything above, and the §3.2 interlock
does **not** cover them.

```verilog
ha1588.v:107-116
  reg rx_q_rst_combined;
  always @(posedge clk or posedge rst) begin        // clk = fabric (pclk), rst = ~presetn
    if (rst) rx_q_rst_combined <= 1'b1;
    else     rx_q_rst_combined <= rx_q_rst;         // <-- SOFTWARE-CONTROLLED
  end
  ... tx_q_rst_combined identical

ha1588.v:186 / :204   tsu u_rx_tsu ( .q_rst(rx_q_rst_combined) ) / u_tx_tsu ( .q_rst(tx_q_rst_combined) )
tsu.v:644-653          ptp_queue queue ( .aclr(q_rst), .wrclk(q_wr_clk /* = MII clk */), .rdclk(q_rd_clk /* = fabric */) )

ptp_queue.v:48-56      always @(posedge wrclk or posedge aclr)   // MII domain
                         if (aclr) begin wr_bin <= 0; wr_gray <= 0; end
ptp_queue.v:102-108    always @(posedge wrclk or posedge aclr)   // MII domain
                         if (aclr) begin rd_gray_wr1 <= 0; rd_gray_wr2 <= 0; end
```

`rx_q_rst` is not a power-on reset. It is a register bit, and it arrives as a
**one-fabric-cycle pulse**:

```
reg.v:242    wire rxq_rst = reg_40[1];
reg.v:355    assign rx_q_rst_out = rxq_rst_d2 && !rxq_rst_d3;   // rising-edge detect on `clk`
reg.v:247/413  identical for the TX queue (reg_60[1])
```

So `aclr` on a 25 MHz MII-clocked FIFO write pointer is asserted for **one 10 ns fabric
cycle** and then released, at an arbitrary phase, **while `mrx_clk`/`mtx_clk` are
free-running**. That is:

- an async-clear pulse **narrower than the destination clock period** (10 ns vs 40 ns),
  which may not straddle a single MII edge; and
- a removal edge with **no relationship whatsoever** to the MII clock — the genuine
  recovery/removal violation the baseline was looking for.

`wr_bin`/`wr_gray` leaving reset metastable breaks the gray-code adjacency invariant the
FIFO's `wrfull`/`rdempty` depend on. Symptom class: PTP timestamps silently dropped,
duplicated, or the queue reporting the wrong occupancy.

**It is reachable by shipped software, and the driver deliberately pulses it:**

```c
ha1588.c:131-137   void ha1588_rx_queue_reset(...) { REG(RX_TSU_CTRL) = Q_RST; REG(RX_TSU_CTRL) = 0; }
ha1588.c:148-152   void ha1588_tx_queue_reset(...) { ... }
```
called from `firmware/apps/ptp_slave/main.c:597-598`,
`firmware/apps/ptp_slave/ptp_slave.c:710-711` and
`firmware/apps/eth_tsu_watermark/main.c:166`.

**This was already known and written down** — the RTL says so, by rule name:

> `ha1588.v:104-106` — "Cross-domain async-reset deassertion to gmii_clk remains a
> known CDC limitation of the OpenCores queue interface (**Reset_sync02**)."

So B7 did not discover it; B7 *re-found a documented, un-actioned limitation*. That is
still a useful result — it is the only reset finding in the run that survives scrutiny —
but the honest classification is (a) already-known, not (b) a documentation gap.

**Blast radius:** `wr_bin[4:0]`, `wr_gray[4:0]`, `rd_gray_wr1[4:0]`, `rd_gray_wr2[4:0]`
= 20 flops per queue × 2 queues = **40 flops**, all in the MII domains. The read side
(`rd_bin`, `rd_gray`, `wr_gray_rd1/2`, `ptp_queue.v:71-78, 88-95`) is fabric-clocked and
same-domain as the `aclr` deassertion, so it is safe.

**Severity:** degrades PTP timestamp quality after a software queue reset. It cannot
wedge a bus, cannot corrupt the MAC datapath, and cannot affect bring-up (the power-on
path is covered by §3.2, since `rst` forces `rx_q_rst_combined` high and it clears on
the first fabric edge — ~10 ns — long before `mrx_clk`'s first edge at ~100 ns). It is a
**should-fix**, not a blocker.

---

## 5. `role_locked_o` (A4F) — deliberate and documented

```
Reset_sync02 A4F: role_locked_o (app_clk) -> u_gpio_phy_apb_regs.lock_thresh_sync2[0] (link_rx_clk_o)
                  tidelink/deps/tidelink-phy/rtl/tidelink_gpio_phy_apb_regs.sv:145
```

This is precisely the mechanism `docs/RESET_ORDERING.md` §2 exists to describe: the
recovered-RX-clock domain's *only* release path is `role_locked`, async-asserted and
sync-deasserted into `pad_clk_rx`. The destination SpyGlass names — `lock_thresh_sync2`,
with `lock_thresh_sync1` alongside it under `Reset_sync04` (row `65A`) — **is** the
synchroniser chain. Flagging a reset synchroniser's own stages for "reset generated from
a different domain" is definitionally true of every reset synchroniser ever built; it is
what the cell is for.

Same reasoning retires **A4C**: `ha_rst → u_ha1588.rst_rtc_s2` is the input of the
2-flop `rst_rtc_s1/s2` reset synchroniser at `ha1588.v:76-85`, which the same patch
added on purpose.

Cross-check answer for `RESET_ORDERING.md`: it covers the D2D/TideLink reset regimes
correctly and completely, and A4F is category **(a) already-known and deliberately
designed**. It says **nothing** about the eth-subsystem reset distribution — that
material lives only in RTL comments (`ethmac_subsystem_apb.v:480-494`,
`ha1588.v:99-106`). That is a genuine documentation gap, though not a design gap.

---

## 6. The `Ar_unsync01` on repo-owned RTL is an SGDC artefact — measured, not argued

The baseline flagged this as "this repository's own integration RTL and deserves a look":

```
Ar_unsync01 [65D]  src/rtl/chiplet_d2d_decode.sv:181
  Reset signal 'nanosoc_eth_chiplet.sys_hresetn' for 'clear' pin of flop
  'nanosoc_eth_chiplet.u_d2d_decode.dph_code[0]', clocked by 'nanosoc_eth_chiplet.sys_hclk',
  is unsynchronized by reason: Missing synchronizer
```

Read the two names in that message: reset `sys_hresetn`, clock `sys_hclk`. They are the
**matched output pair of one reset controller**:

```verilog
slcorem0p_rstctrl.v:88-95
  cm0p_rst_sync u_sys_hresetn_sync (
     .RSTINn (SYS_GLOBALRESETn),
     .CLK    (SYS_HCLK),          // <-- the very clock the flop uses
     .RSTOUTn(SYS_HRESETn) );
```

`sys_hresetn` is therefore already async-assert / sync-deassert **on `sys_hclk`**, and
`dph_code` is a `sys_hclk` flop (`chiplet_d2d_decode.sv:179-182`). Same domain. No
crossing. SpyGlass cannot see this because
`cdc/nanosoc_eth_chiplet.sgdc:270` declares

```
reset -name sys_hresetn   -value 0
```

which **re-roots the reset at the top-level port** and discards everything upstream of
it — including the synchroniser. The SGDC's own §2 comment states the intent ("they must
be declared here, not left to propagate"); that intent is what manufactures the finding.

### The measurement

Two runs, same flist, same `.prj`, same goal, differing only in whether
`reset -name sys_poresetn` / `reset -name sys_hresetn`
(`cdc/nanosoc_eth_chiplet.sgdc:269-270`) are present. **`cdc/**` was not modified** —
both runs used copies under a scratch directory, with `projectwdir` redirected there.

| | control (current SGDC) | experiment (2 lines removed) |
|---|---:|---:|
| Exit code | 0 | 0 |
| `Ar_unsync01` | **1** | **0** |
| `Ar_sync01` | 27 | **28** |
| `Ar_syncdeassert01` | 27 | **28** |
| `Reset_sync02` | 5 | **5** |
| `Reset_sync04` | 14 | 14 |
| Errors / Warnings | 165 / 91 | 165 / 91 |
| Unsync crossings | 142 | 143 |

Removing the two declarations makes the `Ar_unsync01` Error disappear and turns it into
one *more* recognised synchroniser (`Ar_sync01`/`Ar_syncdeassert01` both 27 → 28) —
SpyGlass traces back to `u_sys_hresetn_sync` and accepts it. **The finding was created by
the declaration.**

**And it hid nothing.** A set-diff of all 142/143 `Ac_unsync01`+`Ac_unsync02` rows shows
the only differences are five HA1588 RTC register crossings re-reported under a
different bit-slice grouping (`reg_10`/`reg_14` are halves of the same 48-bit seconds
register; `reg_18`/`reg_1c` of the nanoseconds; `reg_20`/`reg_24` of the period). Same
crossings, different representative slices, net +1 row. No real crossing was masked —
which matters, because the SGDC is explicitly written to the rule "an absent declaration
over-reports, a wrong declaration masks".

**Two corrections to the baseline follow:**

1. `Ar_unsync01 = 1` does **not** mean "the only such flop group in the design". It is
   one representative row for the `(sys_hresetn, sys_hclk)` pair, which stands for every
   flop in `u_d2d_decode`, `u_tlapb_bridge`, `u_tcapb_bridge`, `u_tidelink` and
   `u_tidechart` — thousands of flops, all of them same-domain and all of them fine.
   Conversely, `Ar_unsync01 = 1` is **not** evidence that only one reset lacks a
   synchroniser: the rule counts resets with no synchroniser *anywhere* in the path, so
   the genuine wrong-domain cases (§3, §4) score under `Reset_sync02` instead and would
   be missed by anyone gating on `Ar_unsync01`.
2. **The B7 numbers are already stale.** The control run against the *current*
   `cdc/nanosoc_eth_chiplet.sgdc` gives 142 unsync crossings / 165 Errors, against B7's
   152 / 175 — a concurrent session has been editing the SGDC (`git diff --stat cdc/`
   shows +368 lines in the working tree). Re-measure before quoting B7's counts.

---

## 7. Ranked recommendation

**R1 — Drop two lines from the SGDC and re-run. Cost: minutes. Retires the only
repo-owned reset Error.**
Delete or comment `reset -name sys_poresetn` and `reset -name sys_hresetn`
(`cdc/nanosoc_eth_chiplet.sgdc:269-270`) and let SpyGlass propagate them from the PRMU
synchronisers. Measured above: `Ar_unsync01` 1 → 0, one more recognised synchroniser,
nothing masked. Replace them with a comment recording *why* they are absent
(`slcorem0p_rstctrl.v:88-95` — the PRMU emits reset and clock as a matched pair), so the
next reader does not re-add them. **This file is owned by another session — hand them
this section rather than editing it.**

**R2 — Give the PTP queue reset a write-side bridge. RTL, optional, N2 is fine.**
The only genuine exposure (§4). The fix is one instance per queue, mirroring the
precedent already in the same subsystem (`ethmac_subsystem_apb.v:480-515`): synchronise
`q_rst` into the write clock before it reaches `ptp_queue.aclr`, i.e. in `tsu.v` around
`:644-653`, async-assert on `q_rst` and sync-deassert on `q_wr_clk`. Because the write
clock is itself held at 0 by the system reset (§3.2), a 2-FF bridge cannot deadlock:
power-on still forces the queue reset immediately and the bridge releases once the MII
clock exists.
**Do not put this in the batched netlist.** It touches vendor-adjacent patched RTL
(`ha1588_patches/`), it needs a PTP regression to prove it did not break timestamp
capture, and the defect it fixes degrades timestamp quality after a *software* action —
there is no power-up or bring-up path to it. Landing an unvalidated reset change into a
tapeout batch to fix a non-blocking defect is the worse trade.
**Cheaper interim, zero RTL:** stop calling `ha1588_{rx,tx}_queue_reset()` while the MAC
is enabled — do queue resets only with `MODER.RXEN/TXEN` clear, or only during init. If
the MII clocks are quiescent the removal edge has no capture edge to race, and the
hazard is unreachable. That is a firmware-side change and it is available today.

**R3 — Record §2 and §3.2 as written waivers, not silence.**
`sys_fclk → rtc_clk` and `sys_fclk → user_ref_clk` are same-net on the taped-out die
(`nanosoc_eth_chiplet_chip.v:102-103`); `sys_fclk → mrx/mtx_clk` reset distribution is
interlocked by `rmii_to_mii`'s clock gating (§3.2). Both are correct-by-construction and
both are invisible to the tool, so both will be re-found by every future run and
re-litigated by every future reader. Put the argument, with these file:line citations,
in `cdc/waiver.swl` or a documented waiver inventory entry. A waiver with this reasoning
attached is worth having; a bare `waive -rule Reset_sync02` is not.

**R4 — Extend `docs/RESET_ORDERING.md` to cover the eth-subsystem.**
It documents the D2D reset regimes well and says nothing about the MII/RTC side. §1 and
§3.2 of this document are the missing section. Low priority, but it is the reason this
analysis took a day rather than an hour.

**R5 — Do not gate on `Ar_unsync01`.** §6 correction 1. The rule's zero is not a clean
bill for reset-domain crossings; `Reset_sync02` is the rule that carries them, and it is
an Error-severity rule with only five rows — cheap to adjudicate every run.

---

## 8. What this does not cover

- **`axi_chiplet_controller` is still black-boxed.** Everything said here about
  TideLink's reset regimes is taken from `RESET_ORDERING.md` and the RTL, not from a CDC
  run. B8 will change that. `role_locked_o`'s treatment inside the controller
  (`axi_chiplet_controller.sv:3542`, `:2681`, `:2686`) was **not** analysed by this run.
- **Structural goal only**, as in B7. `cdc/cdc_verify` does not terminate in batch here.
- **The 122-block / 149-target census in §3.1 is a source-level count**, from parsing
  `always` blocks, not an elaborated flop count. The true flop number is higher once
  vectors expand. It is an order-of-magnitude figure for blast radius, not a netlist
  statistic.
- **§3.2's interlock was verified by reading RTL, not by simulation.** A directed
  reset-release test — assert `sys_hresetn` mid-traffic, release it, check no MII edge
  occurs within the removal window — would convert the argument into a measurement. It
  is a short cocotb test and nobody has written it.
- **`Ac_glitch03` (9 Errors) was checked for reset involvement and has none** — all nine
  are data-path reconvergence in the MAC and the DAP. Out of scope here, still untriaged.
- **The two runs in §6 used the b7 flist**, which carries the `WavD2DGpioRx_v2.v`
  code-motion override (`CDC_B7_BASELINE.md` §2b). The analysed netlist is not
  byte-identical to what the ASIC flow compiles.
