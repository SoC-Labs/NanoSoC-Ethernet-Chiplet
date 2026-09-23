# Stated limitation — the TideLink ASIC DFT wrapper is not in the build

**For inclusion in the tapeout submission / partner-facing errata.**
Drafted 2026-09-23 from an RTL, netlist and elaboration audit. It describes the die that
was taped out:

    design     rc4-20260829, ASIC/eth-chiplet/build/rc4-20260829/outputs/
               nanosoc_eth_chiplet_pads_rc4_logo.gds, md5 6b0833c4216bdb683ed2427cd0deba75
    synthesis  gdsrun-20260826-rc1: eth 4b625c4, tidelink 5e8bdb5a
               (gdsrun-20260826-rc1/PRE_RUN_MANIFEST.txt)
    re-spin    NONE. The owner has decided not to re-spin, so this die is final.

The RTL cited here is at the current tidelink pin `785daee`. For every file cited,
`tidelink_top.sv`, `asic/tidelink_dft_wrapper.sv`, `local_overrides/axi_chiplet_controller.sv`
and `flists/`, it is byte-identical to the synthesis sha `5e8bdb5a`
(`git diff --stat 5e8bdb5 785daee -- <those paths>` is empty).

---

## 1. Summary

`tidelink/src/rtl/asic/tidelink_dft_wrapper.sv` is where TideLink records its ASIC parameter
decisions. **This chip does not use it.** `src/rtl/nanosoc_eth_chiplet.sv:925` instantiates
`tidelink_top` directly and overrides four parameters: `NUM_PHY_LANES`, `SELF_ARM_TRAIN_EN`,
`AUTO_ANCHOR_EN` and `TXGEN_PRESENT`. Every other parameter the wrapper sets arrives in
silicon as `tidelink_top`'s own default.

The wrapper forwards 24 parameters to `tidelink_top`. 21 of them have the same value on
silicon, because `tidelink_top`'s defaults have converged on the wrapper's. Two reach silicon
with a different value and no chip override (E1, E2). The chip deliberately sets one of them,
`SELF_ARM_TRAIN_EN`, the other way. It also sets `AUTO_ANCHOR_EN`, which the wrapper does not
forward. The wrapper's DFT logic loses nothing, because the chip ties every scan input to 0
and the wrapper is a skeleton with no scan, MBIST or TAP logic of its own.

| ID | Item | Wrapper value | Silicon value | Effect on silicon | Severity |
|---|---|---|---|---|---|
| **E1** | `DEBUG_UNLOCK_DEFAULT` | `1'b0` (follow the strap) | **`1'b1`** | APB debug is permanently unlocked. The `apb_debug_unlock_i` strap is dead. | **Low.** Bring-up uses the unlock (§3). |
| **E2** | `NEGO_CFG_RESET` | `7'h61` (autoneg on from POR) | **`7'h00`** | Autonegotiation, and the retire-autonomy behind it, is off at POR. | **None.** This die was designed and verified for this setting. Only the documentation is wrong. |
| — | `SELF_ARM_TRAIN_EN` | `1'b0` | `1'b1` | Deliberate chip override (`nanosoc_eth_chiplet.sv:915-919`). | — |
| — | `AUTO_ANCHOR_EN` | not a wrapper parameter (would give `1'b0`) | `1'b1` | Deliberate chip override. | — |

§5 lists everything else the wrapper sets. All of it is identical on silicon.

---

## 2. E1 — APB debug is permanently unlocked

**What the silicon does.** `tidelink_top.sv:178` declares `DEBUG_UNLOCK_DEFAULT = 1'b1`, and
`:3201` connects the controller as

```verilog
.apb_debug_unlock_i (DEBUG_UNLOCK_DEFAULT ? 1'b1 : apb_debug_unlock_i),
```

So the controller sees a constant 1. The chip ties the strap to `1'b0`
(`sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml:233`), and that tie has no effect. The
comment beside the tie says `0 = debug locked`. On this die that is false.

**What the unlock enables.** It has one use, in the Wlink APB mux
(`local_overrides/axi_chiplet_controller.sv:3897-3962`, the copy that elaborates).

- **Slave role** (`ROLE_CFG[0]=1`, with the I²C slave path idle). Local APB writes to the
  **Wlink bank** (`0x2E03_0000–0x2E03_1FFF`) pass through because of the unlock (`:3941`).
  Locked, they would be demoted to reads (`pwrite=0`, `pstrb=0`, `:3952-3961`), and the APB
  transfer would still complete OKAY. The write would be lost with no error.
- **Master role.** The unlock has no effect: a master always has direct write access
  (`:3911`).
- **TideLink bank** (`0x2E03_2000+`: `ROLE_CFG`, `NEGO_*`, `SWI_*`, eye and status registers).
  The unlock has no effect in either role. These writes use `ctrl_reg_write` (`:627`),
  which is not gated.
- **Role lock.** The unlock has no effect. It was removed from the peer-mask gate on
  2026-07-24 (`:745`), and on this die `SELF_ARM_TRAIN_EN=1` lets a `ROLE_CFG[1]` write latch
  `role_lock` regardless (`:901-913`).
- **Who can use it.** Only local AHB masters that reach the TideLink APB window: both CPUs,
  DMA-250, the DAP (SWD) and the HOSTIO debug bridge. **The peer die cannot.** Inbound D2D
  requests decode only to the shared SRAM and the IPC mailbox
  ([TAPEOUT_LIMITATION_D2D_PEER_WRITE.md](TAPEOUT_LIMITATION_D2D_PEER_WRITE.md)).
- **Not to be confused with CPU debug.** Cortex-M debug authentication (`DBGEN`/`SPIDEN`) is
  a separate set of signals. This parameter does not affect it.

**Impact.** When this die is the slave, its own software or debugger can rewrite its
link-layer configuration. That covers the link enable and soft reset (`0x2E03_0208`), each
FC node's control register including its CRC enable (`0x2E03_1014 + n × 0x100`, n = 0..4)
and the lane mask (`0x2E03_0214`). Writing `0x208` on a live link desynchronises it and
wedges the sender (`NanoSoC-Compute-Chiplet/nanosoc-compute-system/compute-subsystem/firmware/common/tidelink_bringup.h:239-242`). A locked slave
could not do that to itself. No mission function is lost.

**Workaround.** No workaround is needed; §3 explains why bring-up depends on the unlock.
Firmware rule: on a slave-role die, write Wlink-bank registers only during bring-up, never
on a live link. Do not describe this die as debug-lockable. No register or pad can lock it.

---

## 3. Does bring-up rely on the unlock? Yes, when this die is the slave

Against the compute die, this die will be the slave. The pairing record leaves this die's
field blank, but compute has committed to `die_a`/master and the two must be complementary
([bringup/D2D_PAIRING_DECISION.md](bringup/D2D_PAIRING_DECISION.md) §2). This die's
autonegotiation is off (E2), so the link-layer writes are made by software, not by the
controller's handoff sequencer. The host recipe issues them after it locks the die as slave:

| Write (die_b, after `ROLE_CFG ← 0x03`) | `tidelink/pynq_host/scripts/kr260_eth_bringup.py` | Bank | Takes effect on a slave only because of E1? |
|---|---|---|---|
| `ROLE_CFG ← 0x03` | `:271` | TideLink | no |
| `SWI_TRAINING_MODE ← 1`, later `← 0` | `:287`, `:323` | TideLink | no |
| 3-write LL bootstrap to `0x2E03_0208` | `:325-327` | **Wlink** | **yes** |
| `--crc-check on\|off` (`SM_CONTROL[16]` on five FC nodes) | `:243-260`, `:349-351` | **Wlink** | **yes** |

**Why "locked" would have been the defect.** The wrapper's case for locking (commit
`749a2715`, wrapper `:105-128`) rests on an FPGA proof that ran with autonomy on. That
build set `NEGO_CFG_RESET = 7'h61` alongside `DEBUG_UNLOCK_DEFAULT = 1'b0`
(`tidelink/fpga/targets/kr260-pair-onchip/tidelink_design.tcl:341-343` at `749a2715`).
With autonomy on, the controller's handoff sequencer makes the
three `0x208` writes itself. The sequencer arms only on
`autonomy_armed = nego_en & role_locked & …` (`axi_chiplet_controller.sv:1428`, `:4216`).
So the wrapper's two settings are a pair: locking is safe only with autonomy on. **This chip
took neither.** Taking only the lock would have made the slave's `0x208` writes and its CRC
control silently ineffective. On the FPGA on 2026-07-24, a run with the strap driven to 0
stalled both dies at `fcsm=2`. The controller's own comment attributes that stall to the
slave's dropped Wlink writes (`axi_chiplet_controller.sv:729-741`). At the time the strap
also fed the peer-mask gate, so that run was not a clean A/B test.
`tidelink/docs/AUTONOMY_STATUS_2026_07_24.md:149-152` draws the same conclusion ("Flipping it
to 0 is not free"). The wrapper itself says what to do in this case (`:125-128`): override it
to `1'b1` at the tapeout top. The chip ended up there by default.

Qualifications, stated so nothing is over-claimed:

- **Link-up may not need the `0x208` writes.** `swi_enable` resets to 1
  (`local_overrides/Wlink.v:2642-2643`). A 2026-09-23 simulation (V2 PHY, ideal pads, one
  seed) trained both dies with only a `ROLE_CFG` write. This has not been measured on
  silicon. The CRC control has no alternative path.
- **`kr260_eth_bringup.py` cannot drive the ASIC as written.** It reaches the SoC through
  the `eth_ss_0` backdoor, which is tied idle on the ASIC
  (`sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml:281-290`). On silicon the same writes come
  from SWD, HOSTIO4 or firmware. They enter through the same TideLink APB port, so the answer
  above still holds.
- **Compute's firmware does not depend on this die's unlock.** Compute's
  `tidelink_bringup.h:254-255` and `:297-299` write only compute's own registers
  (`COMPUTE_TLAPB(link)`). Compute is master (`compute-subsystem/firmware/Makefile:80`),
  and the unlock has no effect on a master.

---

## 4. E2 — autonegotiation is off at POR

The wrapper ships `NEGO_CFG_RESET = 7'h61` (`:152-167`: "DECISION (David, 2026-07-19): the
ASIC integration ships 7'h61"). Silicon has `tidelink_top`'s default, `7'h00`
(`tidelink_top.sv:141`). `nego_en` is therefore 0 at POR. The autonegotiation FSM stays in
`ST_BYPASS`, and the role comes from `role_strap_i` (tied 0, so master) until software writes
`ROLE_CFG`. `ROLE_FROM_STRAP` and `RETIRE_EN` are present but inert, because both act only
under `nego_en`.

**This is the right value for this die, not a loss.** It is the documented posture
(`nanosoc_eth_chiplet.yaml:213-233`). The SELF_ARM bring-up, the g2 benches and the 09-23
no-host simulation were all built on it. The wrapper's `7'h61` would have armed I²C
autonegotiation between two dies tied to identical priority. That is Bug N7
(`nanosoc_eth_chiplet.yaml:222-226`). Compute never drives its I²C master
(`tidelink_bringup.h` invariants 3-4).

**Workaround / override.** `NEGO_CFG` is software-writable at `0x2E03_2090`
(`axi_chiplet_controller.sv:929`, `:943`). Before enabling autonegotiation, write a distinct
`NEGO_PRIORITY` (`0x2E03_2098`) on each die.

---

## 5. Everything else the wrapper does — identical on silicon

**Parameters.** The chip does not override these (they are absent from the netlist module
name, §6), and `tidelink_top`'s default equals the wrapper's value:

| Parameter | Wrapper | Silicon | Proof |
|---|---|---|---|
| `SYS_ADDR_W` / `SYS_DATA_W` / `RAM_ADDR_W` / `RAM_DATA_W` / `APB_ADDR_W` / `FC_DATA_W` | 32/32/14/32/12/48 | same | defaults |
| `NUM_PHY_LANES` | 8 | 8 | name `…NUM_PHY_LANES8…` |
| `TIDELINK_PAIR_BASE` / `PHC_LOCK_GATE_EN` | `'0` / 0 | same | defaults |
| `USE_IDELAY` / `USE_CLKBUF` / `USE_T3A` | 0 / 0 / 0 | same | controller name `…USE_IDELAY1h0_USE_CLKBUF1h0_USE_T3A1h0…` |
| `EPOCH_ANCHOR_EN` | 0 | 0 | controller and `Wlink` names `…EPOCH_ANCHOR_EN1h0…` |
| `HARDEN_SWI_ENABLE` | 1 | 1 | default (consumed in `tidelink_top`, `:2917-2920`) |
| `HONEST_MASK_HS` | 1 | 1 | default; `mask_hs_bypass_i` follows its strap (tied 0) |
| `USE_PHY_V2` | 0 | 0 | default; no `g_phy_v2` in netlist. The V2 PHY is selected by `+define+TIDELINK_PHY_V2`, not by this parameter |
| `RETIRE_EN` | 1 | 1 | controller name `…RETIRE_EN1` (inert, E2) |
| `ROLE_FROM_STRAP` | 1 | 1 | controller name `…ROLE_FROM_STRAP1…` (inert, E2) |
| `TRAIN_ENTRY_FALLBACK` | 0 | 0 | controller name `…TRAIN_ENTRY_FALLBACK0…` |
| `ENABLE_AHB_WRITE` | 1 | 1 | default |
| `TXGEN_PRESENT` | 0 | 0 | chip override; name `…TXGEN_PRESENT1h0…`; no `tidelink_tx_gen` in netlist |

Parameters that neither the wrapper nor the chip forwards take the same default either way:
`STUB_*`, `BYPASS_ADDR_XLAT`, `TXGEN_CREDIT_GATE_DIS`, `NEGO_TRAIN_CFG_RESET` (`16'h0001`),
`WINSCAN_CONVERGE_LOCK_EN` (0) and `LINK_RATE_REGS_PRESENT` (0).

**Ports, ties and logic.** The wrapper passes every functional port through 1:1 and contains
no reset synchroniser and no clock gate. Its own logic is DFT scaffolding:

| Wrapper behaviour | Silicon | Consequence |
|---|---|---|
| `scan_mode = test_mode \| scan_en \| mbist_en` | `scan_mode` tied `1'b0` (`nanosoc_eth_chiplet.yaml:257`) | none. 0 in functional mode either way. No scan was inserted, so the `scan_mode` bypasses in `tidelink_phc_cdc` and `tidelink_link_clk_div` have nothing to serve. |
| `scan_shift = scan_en`, `scan_in = scan_in[0]`, chains 1-7 wired head to tail | scan inputs tied 0, `scan_out` open | none. No scan chain exists on this die. |
| `mbist_done = mbist_pass = 0` | no MBIST ports | none. No MBIST either way. |
| TAP pads tied off (`INCLUDE_TAP = 0`) | no TideLink TAP | none. The die's IEEE 1149.1 TAP is separate, at the pad ring. |
| `scan_asyncrst_ctrl` passed through | tied 0 | none |

The chip's other ties (`phc_clk = sys_hclk`, `phc_locked_i = 1`, `tc_qos_priority = 0`,
`s_i2c_axi_*` idle, `link_clk_div_ratio_i = 0`, `nego_priority_i = 16'h0001`, `puf_* = 0`) are
chip decisions. The wrapper passes those ports through and would not have changed them.

---

## 6. Evidence

**Netlist module names.** Genus writes every parameter overridden at an instantiation into
the module name, including overrides equal to the default (`NUM_PHY_LANES8` is one). A
parameter absent from the name was not overridden. It is identical in the rc4 netlist and in
all three GLS netlists:

    ASIC/eth-chiplet/build/rc4-20260829/outputs/nanosoc_eth_chiplet_pads_rc4_pnr.v
    build/gls-netlist/{gdsrun_cc,fp1505_cc,rzg_cc}/nanosoc_eth_chiplet_pads_pnr_*.v

    module tidelink_top_NUM_PHY_LANES8_TXGEN_PRESENT1h0_SELF_ARM_TRAIN_EN1_AUTO_ANCHOR_EN1
    module axi_chiplet_controller_AUTOCAL_ENABLE1h1_USE_IDELAY1h0_USE_CLKBUF1h0_USE_T3A1h0_
           EPOCH_ANCHOR_EN1h0_NEGO_TRAIN_CFG_RESET1_NEGO_CFG_RESET0_ROLE_FROM_STRAP1_
           TRAIN_ENTRY_FALLBACK0_SELF_ARM_TRAIN_EN1_AUTO_ANCHOR_EN1_WINSCAN_CONVERGE_LOCK_EN0_
           RETIRE_EN1

`build/gls-netlist-negative/` is a negative control and was not used as evidence. The rc4
instance pins `.apb_debug_unlock_i(UNCONNECTED_HIER_Z657)` prove nothing: the netlist writer
gives constant-folded pins the same name.

**RTL elaboration (VCS, 2026-09-23).** Elaborating the ASIC flist
(`flist/nanosoc_eth_chiplet_asic.flist` with its generated sub-flists, top
`nanosoc_eth_chiplet_chip`, so the boundary ties are included) and probing the hierarchy
gives:

    tl.DEBUG_UNLOCK_DEFAULT = 1        tl.NEGO_CFG_RESET = 7'h00
    tl.HONEST_MASK_HS       = 1        ctrl.NEGO_CFG_RESET = 7'h00
    chip-boundary strap  apb_debug_unlock_i = 0
    controller SEES      apb_debug_unlock_i = 1
    chip-boundary strap  mask_hs_bypass_i   = 0
    controller SEES      mask_hs_bypass_i   = 0

The strap is 0 and the controller sees 1.

**Why nothing caught it.** TideLink's `sim_gate_dftelab` (`tidelink/Makefile:1509-1538`)
elaborates the wrapper and calls it "The ACTUAL TAPEOUT TOP … where the silicon-param
DEFAULTS live". It guards a top this chip never builds. The chip's own comment at
`nanosoc_eth_chiplet.sv:920-924` records that the wrapper "is in no flist". It used that
fact to fix `TXGEN_PRESENT` and applied it to none of the wrapper's other settings.

---

## 7. Documents that are wrong about this die

| Where | Says | On silicon |
|---|---|---|
| `sys_desc/chip_boundary/nanosoc_eth_chiplet.yaml:233` | `apb_debug_unlock_i` tie `# 0 = debug locked` | the tie is dead and debug is unlocked (E1) |
| `docs/design/PIN_MAP.md` §4b, `apb_debug_unlock_i` row | "tied 0 = debug locked" | **corrected in the commit that adds this page** |
| `src/rtl/nanosoc_eth_chiplet.sv:211-214` | `mask_hs_bypass_i` + `apb_debug_unlock_i` "open the software-driven role-lock path … both low keeps that path shut" | neither strap touches role lock on this die (§2) |
| `tidelink/src/rtl/asic/tidelink_dft_wrapper.sv:172-173` | "this wrapper passes the param down explicitly, so its default … is what the ASIC gets" | this ASIC does not use the wrapper |
| `tidelink/Makefile:1509` | "The ACTUAL TAPEOUT TOP: tidelink_dft_wrapper" | not for this chip |

The RTL and YAML rows cannot change on the submission branch. They are corrected on the
next-revision branch (§8).

---

## 8. Next revision

Branch **`next/tidelink-top-explicit-params`** makes every TideLink parameter decision
explicit at `nanosoc_eth_chiplet.sv`'s `tidelink_top` instance, and fixes the RTL and YAML
comments in §7. It keeps the silicon values, so the die's behaviour does not change. After
the change, every value is visible in the netlist module name.

The wrapper is **not** restored. It does not declare three ports this chip needs:
`ahb_sub_w_beat_consumed_o` (peer-write steering), `link_clk_div_ratio_i` and
`train_fail_irq`. It has no `AUTO_ANCHOR_EN`. Its `SELF_ARM_TRAIN_EN = 0` and
`NEGO_CFG_RESET = 7'h61` would each have to be overridden back to this chip's values. None
of its DFT scaffolding does anything on a die with no scan.

**If a later revision wants debug locked,** changing `DEBUG_UNLOCK_DEFAULT` to `1'b0` is not
enough on its own. It must come with one of:
(a) autonomy on (`NEGO_CFG_RESET` with `nego_en`), plus per-die `NEGO_PRIORITY` and a peer
that runs autonegotiation, so the hardware makes the `0x208` writes;
(b) a real unlock source, such as a bonded strap or a sticky register, that bring-up can
assert.
The g2 benches tie `apb_debug_unlock_i = 1` (`verif/g2_soc_pair/tb_g2_soc_pair.sv:320`,
`:459`), so they would not see a locked die.
