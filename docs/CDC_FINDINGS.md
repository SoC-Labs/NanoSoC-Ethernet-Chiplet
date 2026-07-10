# CDC findings — first structural pass over the integrated top

Run `verif/cdc/run.sh` (Cadence HAL 22.03 via `xrun -hal`). This is a **starting
point** for the physical team's CDC signoff, not a clean bill — see "What this
pass does NOT cover".

## What this establishes

1. **The CDC tool is available and licensed here** — HAL 22.03. The flow is
   `xrun -hal` (Xcelium elaborates the whole integration with a full SV parser,
   then HAL runs its structural + CDC rules on the netlist). Standalone `hal` has
   a weaker front-end and cannot parse this design.
2. **The integrated netlist is now tool-independent.** `flist/dedup_merged_flist.py`
   removes the duplicate module definitions the three component flists share (the
   Arm CMSDK cells, the XHB500 `mst`/`slv` generic cells, `ahb3lite_to_wb` — 11
   files). VCS tolerated these ("last wins"); Xcelium and Verilator treat a
   duplicate module as an **error**, and a first-wins tool would bind a *different*
   copy than the simulator. After the dedup, every tool binds exactly one
   definition of every module — the netlist is a property of the filelist, not the
   tool. (This generalises what `resolve_tidelink_flist.py` does within TideLink.)
3. **The integration adds no new multi-clock-domain instance at its boundary.**

## CDC findings: 14 × MCKDMN, all component-internal

HAL's `MCKDMN` ("in instance, clocks belong to different clock domains") is the
CDC rule that fired. All 14 are **inside the components**, none at the
`nanosoc_eth_chiplet` / `tidelink` / `chiplet_d2d_decode` boundary:

| Where | Instances |
|---|---|
| SoC reset controller | `u_reset_ctrl_0` |
| Ethernet-MAC / PTP subsystem | `ethmac_subsystem_ahb` `u_inner`, `ethmac_subsystem_apb` `u_eth_top`/`u_ha1588`/`u_eth_rx_cksum`/`u_ha1588_servo` |
| OpenCores EthMAC (vendor IP) | `eth_top` `ethreg1`/`wishbone`/`macstatus1`, `eth_maccontrol` `receivecontrol1` |
| HA1588 PTP timestamp unit | `ha1588` `u_rgs`/`u_rx_tsu`/`u_tx_tsu`, `tsu` `queue` |

These are the ethernet MAC's own RX/TX/host/PTP clock domains — legitimate,
pre-existing, and owned inside those components. **Critically, none of them is
`user_ref_clk` or `pad_clk_rx` crossing into `sys_hclk` at the wrapper**: the
integration keeps the D2D link's CDC inside TideLink (`cdc_tear`, `phc_cdc`), as
`PHYSICAL_HANDOFF.md §1` documents. The wrapper does not introduce a new
multi-clock instance.

## The ~33k CBPAHI are structural noise, not CDC

`CBPAHI` ("combinatorial path crossing multiple units") is a `halstruct`
*structural style* check, not a CDC rule. It fires on any combinational signal
that spans a module boundary — every AHB fabric passthrough, the `hostio4` bidir,
the `eth_ss_0` response nets, the `d2d_ahb_m_hwdata_q` register's input. That is
how a hierarchical design with combinational interconnect looks; it is pervasive
(tens of thousands) and **waivable**. It is not a bug and not a CDC issue.

## What HAL covers, and what the full `CLKDMN` sign-off needs

**HAL's structural CDC infers clocks from the netlist** — it does not take an SDC
or async-clock declaration (confirmed: `hal -help` exposes no clock-domain input).
So it reports `MCKDMN` (instances with multiple clocks) but not a full `CLKDMN`
("signal crosses a clock domain without a synchroniser") analysis, which needs the
async-clock *relationships*. That analysis is a dedicated CDC tool's job.

**The constraints now exist.** `constraints/nanosoc_eth_chiplet_cdc.sdc` declares
the primary clocks at the chiplet ports and the async clock groups that are the
D2D CDC boundary:

- `sys_fclk` → `sys_hclk` (SoC core)
- `user_ref_clk` (Wlink PLL ref, **async** to `sys_hclk`)
- `pad_clk_rx` (the **far die's** clock, async to everything — `RESET_ORDERING.md §2`)
- `pad_clk_tx` (generated from `user_ref_clk`), `rtc_clk`, `rmii_ref_clk`, `swd_clk`

It is a **starting point**: the async cuts (the load-bearing part) are declared,
but the generated-clock ratios (`sys_hclk`'s PRMU divide), the SoC-internal
MAC/PTP clocks, and the real source-sync I/O delays carry `[OWNER]` markers for the
clock-tree owner. It composes the SoC and TideLink component SDCs.

**To complete the `CLKDMN` sign-off:**
1. Fill the `[OWNER]` items in the SDC (generated-clock ratios, MAC/PTP clocks, I/O
   delays).
2. Run a dedicated CDC tool with it. **SpyGlass** is the flow TideLink already uses
   (`make -C tidelink/cdc cdc`, driven by `.sgdc`) — it is **not installed on this
   host**, so this step runs where SpyGlass is licensed. Point it at
   `nanosoc_eth_chiplet` with this SDC + TideLink's `.sgdc` waivers.
3. Triage the `CLKDMN` findings, focusing on `sys_hclk` ↔ `{user_ref_clk,
   pad_clk_rx}` — the crossings this integration owns. HAL's `MCKDMN` result above
   already says the wrapper adds none of its own.

The same SDC is the starting point for the ASIC STA constraints, which the
multicore programme flags as the standing timing blocker.

## Reproduce

```sh
source set_env.sh
./verif/cdc/run.sh            # ~25 min: full elaboration + HAL
# findings: verif/cdc/build/xrun_hal.log
```
