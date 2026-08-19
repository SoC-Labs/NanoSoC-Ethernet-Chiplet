# CDC findings — first structural pass over the integrated top

Run `verif/cdc/run.sh` (Cadence HAL 22.03 via `xrun -hal`). This is a **starting
point** for the physical team's CDC signoff, not a clean bill — see "What this
pass does NOT cover".

> ## ⚠ CORRECTION — 2026-08-17
>
> **Three claims in the original pass were wrong and have been corrected in place.
> If you have quoted this document for a tapeout decision, re-read these first.**
>
> 1. **The MCKDMN count was under-reported by two-thirds** — 40 violations across
>    19 files, not 14 across 7. The original 14 are *exactly the first 14 lines of
>    the log in file order*; the pass was truncated, not filtered.
> 2. **The boundary conclusion is FALSIFIED and must be re-derived.** Two MCKDMN
>    fire inside `tidelink_top.sv` itself, and 26 of the 40 are in the D2D link.
>    The claim "the integration adds no new multi-clock-domain instance at its
>    boundary" is not supported by the evidence it cited. **Do not quote it.**
> 3. **SpyGlass is installed and licensed on this host.** The step this document
>    defers to another machine can be run here, today.
>
> Every number below rests on a command given inline. Re-run them.

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
3. ~~**The integration adds no new multi-clock-domain instance at its boundary.**~~
   **RETRACTED 2026-08-17 — falsified, see below.** The D2D link accounts for 26 of
   the 40 MCKDMN, two of them inside `tidelink_top.sv` itself. Whether the
   *wrapper* adds a crossing is now an open question, not an established result.

## CDC findings: 40 × MCKDMN across 19 files — the D2D link included

**Corrected 2026-08-17.** The original text of this section reported "14 ×
MCKDMN, all component-internal". That was wrong on both halves.

```sh
grep -aoE "MCKDMN" verif/cdc/build/xrun_hal.log | wc -l                      # 41
grep -a "MCKDMN" verif/cdc/build/xrun_hal.log \
  | grep -aoE "[A-Za-z0-9_]+\.(v|sv)" | sort -u | wc -l                      # 19
```

Read the 41 carefully: **40 are violations**, and the 41st is HAL's own tally
line `MCKDMN (40)` at the end of the log, which contains the token. Counting the
`halstruct: *W,MCKDMN` lines gives 40, and the per-file counts below sum to 40.
The honest number is **40 violations across 19 files**.

The original 14 were not a filtered subset — they are **the first 14 lines of the
log, in file order**, ending at `tsu.v`. The next line is `tidelink_top.sv:953`.
The pass was truncated at the point where the D2D link starts.

| Where | Count | Instances |
|---|---|---|
| **TideLink top (integration boundary)** | **2** | `tidelink_top.sv` `u_gpio_phy_apb_regs` (:953), `u_chiplet_controller` (:2041) |
| **Wlink a2l mailbox** | **4** | `WlinkGenericFCReplayAddrSync{,_3,_15,_18}.v` `addrsync` |
| **Wav D2D GPIO PHY** | **10** | `WavD2DGpio.v` `u_deskew` + `gpiorx_0..7` (9), `WlinkGPIOPHY.v` `gpio` |
| **Wlink AXI/bus adapters** | **8** | `AXI4ToWlink.v` `wlink_axi{aw,w,b,ar,r}FC` (5), `GeneralBusToWlink.v` `wlink_generalbusgb`, `TideLinkToWlink.v` `wlink_tidelinktl`, `axi_chiplet_controller.sv` `u_wlink` |
| Wlink ECC status | 2 | `Wlink.v` `ecc_corrected_sp`/`ecc_corrupted_sp` |
| SoC reset controller | 1 | `nanosoc_multicore_soc.sv` `u_reset_ctrl_0` |
| Ethernet-MAC / PTP subsystem | 5 | `ethmac_subsystem_ahb` `u_inner`, `ethmac_subsystem_apb` `u_eth_top`/`u_ha1588`/`u_eth_rx_cksum`/`u_ha1588_servo` |
| OpenCores EthMAC (vendor IP) | 4 | `eth_top` `ethreg1`/`wishbone`/`macstatus1`, `eth_maccontrol` `receivecontrol1` |
| HA1588 PTP timestamp unit | 4 | `ha1588` `u_rgs`/`u_rx_tsu`/`u_tx_tsu`, `tsu` `queue` |

The bottom four rows are the original 14 — still correct, still legitimate,
pre-existing RX/TX/host/PTP domains owned inside those components. The top five
rows are the 26 the original pass never saw.

**The boundary conclusion is falsified.** The original said "none at the
`nanosoc_eth_chiplet` / `tidelink` / `chiplet_d2d_decode` boundary". Two fire in
`tidelink_top.sv` — one of the three named boundaries — and the a2l mailbox
(`WlinkGenericFCReplayAddrSync`) is the structure implicated in the TL-009 wedge.
The claim that "the integration keeps the D2D link's CDC inside TideLink" may
still be true as a *design intent*; what is no longer true is that **this log
demonstrates it**. MCKDMN is an instance-level "has two clocks" observation, so
it cannot by itself distinguish a correctly-synchronised crossing from a broken
one — which is precisely why the retracted conclusion needs re-deriving with a
tool that can (see the SpyGlass section, now unblocked).

**This needs re-deriving, not patching.** Nobody should read the corrected table
as a new clean bill: it is the same null-strength evidence, merely counted
correctly.

## The ~33k CBPAHI are structural noise, not CDC

`CBPAHI` ("combinatorial path crossing multiple units") is a `halstruct`
*structural style* check, not a CDC rule. It fires on any combinational signal
that spans a module boundary — every AHB fabric passthrough, the `hostio4` bidir,
the `eth_ss_0` response nets, the `d2d_ahb_m_hwdata_q` register's input. That is
how a hierarchical design with combinational interconnect looks; it is pervasive
(tens of thousands) and **waivable**. It is not a bug and not a CDC issue.

## The CDC rules that matter never fired — zero here is a null result

**Added 2026-08-17.** Every CDC rule except `MCKDMN` reports zero:

```sh
for r in MCKDMN CLKDMN CMBCDC INSYNC RSTSYN FLSYNC RSTSCB; do
  printf "%-8s %s\n" "$r" "$(grep -aoE "$r" verif/cdc/build/xrun_hal.log | wc -l)"
done
```

| Rule | Count | What it would have caught |
|---|---|---|
| `MCKDMN` | 40 | instance has clocks from >1 domain |
| `CLKDMN` | **0** | signal crosses a domain **without a synchroniser** |
| `CMBCDC` | **0** | combinational logic in a crossing |
| `INSYNC` | **0** | improperly synchronised input |
| `RSTSYN` | **0** | unsynchronised reset |
| `FLSYNC` | **0** | flip-flop synchroniser structure defect |
| `RSTSCB` | **0** | reset/clock scoreboard |

**Those six zeros are not evidence of anything.** They were not waived, and they
did not pass — **they never ran**. Two independent reasons, both checkable:

1. **No ruleset was requested.** `verif/cdc/run.sh:92-93` is a bare elaboration:
   ```sh
   timeout 2400 "$XRUN" -sv -hal -elaborate \
       -f "$BUILD/merged_dedup.f" -top "$TOP" -l "$BUILD/xrun_hal.log"
   ```
   There is no `-hal_ruleset`, no CDC policy selection — nothing that asks HAL for
   the CDC rules. What ran is the default `halstruct` structural set, which is why
   the only things in the log are structural codes (`MCKDMN`, `CBPAHI`, `MPCMPE`,
   `MICAWS`, `MEMSIZ`).
2. **No SDC was consumed, so the rules are unanswerable in principle.** HAL infers
   clocks from the netlist and takes no constraint input. `CLKDMN` asks "do these
   two clocks belong to *asynchronous* domains?" — a question about clock
   *relationships*, which live in an SDC. Without it HAL can say "this instance has
   two clocks" (`MCKDMN`) but never "this signal crosses without a synchroniser".

The mechanism in (2) was already correctly described further down this document
and in the comment at `verif/cdc/run.sh:85-90` — **what was missing is the
consequence**: a reader scanning the summary sees six zeros next to real rule
names and reasonably concludes the design is clean of unsynchronised crossings.
It does not say that. It says nothing at all about them.

**Do not report "0 CLKDMN" as a result.** The correct statement is: *no
unsynchronised-crossing analysis has been performed on this integration.* The
tool to perform it is installed on this host — see below.

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
- `pad_clk_rx` (the **far die's** clock, async to everything — `../design/RESET_ORDERING.md §2`)
- `pad_clk_tx` (generated from `user_ref_clk`), `rtc_clk`, `rmii_ref_clk`, `swd_clk`

It is a **starting point**: the async cuts (the load-bearing part) are declared,
but the generated-clock ratios (`sys_hclk`'s PRMU divide), the SoC-internal
MAC/PTP clocks, and the real source-sync I/O delays carry `[OWNER]` markers for the
clock-tree owner. It composes the SoC and TideLink component SDCs.

**To complete the `CLKDMN` sign-off:**
1. Fill the `[OWNER]` items in the SDC (generated-clock ratios, MAC/PTP clocks, I/O
   delays).
2. Run a dedicated CDC tool with it. **SpyGlass** is the flow TideLink already uses
   (`make -C tidelink/cdc cdc`, driven by `.sgdc`). **CORRECTED 2026-08-17: it IS
   installed and licensed on this host.** Point it at `nanosoc_eth_chiplet` with
   this SDC + TideLink's `.sgdc` waivers.
3. Triage the `CLKDMN` findings, focusing on `sys_hclk` ↔ `{user_ref_clk,
   pad_clk_rx}` — the crossings this integration owns. ~~HAL's `MCKDMN` result above
   already says the wrapper adds none of its own.~~ **Retracted — HAL's MCKDMN says
   no such thing** (see the corrected findings section); treat the wrapper's
   crossings as unexamined.

### SpyGlass availability — corrected 2026-08-17

The claim that SpyGlass "is not installed on this host, so this step runs where
SpyGlass is licensed" was **wrong, and it deferred a signoff step that could have
been run here at any point.**

```sh
ls $SPYGLASS_HOME/bin/
# sg_shell  sg_ame  spyglass  spyglass_main  spyencrypt  sgsat  … (18 entries)
```

Installed: **SpyGlass T-2022.06-SP2 for linux64**. And licensed — not inferred
from the install, but proven by running it end-to-end on a planted defect:

```sh
# a two-flop design, clk_a -> clk_b with no synchroniser
$SPYGLASS_HOME/bin/spyglass -batch -project probe.prj -goals "cdc/cdc_verify"
#   Technology Reports:    CDC( Advance CDC - CDC Verification )
#   Technology Summary: CDC( Advance CDC )
#       Unsynchronized crossings= 1
# Ac_unsync01  Error  cdc_probe.v:13  Unsynchronized Crossing: destination flop
#   cdc_probe.q_b, clocked by cdc_probe.clk_b, source flop cdc_probe.d_a_r,
#   clocked by cdc_probe.clk_a. Reason: Qualifier not found
```

The `Advance CDC` licence checked out against the Synopsys daemon named by this
site's `SNPSLMD_LICENSE_FILE` (two `port@host` entries; values redacted — a
licence server address is infrastructure somebody has to defend, and it is
per-site, so it belongs in the environment and not in a tracked file). The
`cdc/cdc_verify` goal ran, and `Ac_unsync01` correctly flagged the crossing.
This is the exact rule class the `CLKDMN` sign-off needs, and it works here.

**Why the original was wrong — and the general lesson.** The evidence for
"absent" was a `which` miss (`LINT_FINDINGS.md §1` records the same error).
**A `which` miss proves absence from `$PATH`, not absence from the machine.**
SpyGlass is not on the default `$PATH` on this host and never was; it is reached
by absolute path, which is exactly what the working driver already does —
`tidelink/cdc/Makefile:12` hardcodes:

```make
SPYGLASS_HOME ?= $SPYGLASS_HOME
```

So **the repo contradicted itself**: a working, checked-in SpyGlass CDC driver
pointed at the very install this document called absent. Any tool reached by
absolute path in a Makefile will fail a `which` test — check the path before
recording a tool as unavailable.

**Consequence: the deferral is void.** There is no external-host dependency on
the critical path to a `CLKDMN` sign-off for this integration. Given the
retraction above — the D2D link owns 26 of the 40 MCKDMN and the boundary claim
no longer stands — this is now the load-bearing next step, not a formality.

The same SDC is the starting point for the ASIC STA constraints, which the
multicore programme flags as the standing timing blocker.

## Reproduce

```sh
source set_env.sh
./verif/cdc/run.sh            # ~25 min: full elaboration + HAL
# findings: verif/cdc/build/xrun_hal.log
```
