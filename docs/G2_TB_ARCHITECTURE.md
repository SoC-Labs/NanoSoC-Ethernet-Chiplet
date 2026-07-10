# G2 Pair-Simulation Testbench Architecture

**Two `nanosoc_eth_chiplet` dies talking over one TideLink, in cocotb.**

Scope: a concrete testbench architecture for `sim/soc_d2d_pair/` (working
name), the environment that closes the gate in `docs/G2_PAIR_SIM.md` — the
die-to-die port carrying a real transaction between two dies, not against a
memory model. This is a design document. It contains no RTL and modifies no
submodule.

Every structural claim is cited `file:line`. Paths are relative to this repo
(`~/SoCLabs/nanosoc-ethernet-chiplet`) unless prefixed.

---

## 0. Verdict — the harness question, answered first

> **`tidelink/cocotb/tidelink_top_pair/tb_top.sv` cannot be reused, and cannot
> be extended into G2. G2 needs a new `tb_top`. It should be *assembled* from
> two existing harnesses: the PHY-crossing skeleton of `tidelink_top_pair`
> (pads, `pad_skid`, POR-skew gates) and the drive model of the SoC's
> `soc_d2d_loopback` (no-firmware boot-halt, `eth_ss_0` AHB BFM, address map,
> assertions). Neither alone is close.**

Why `tidelink_top_pair` is the wrong harness — three structural reasons, each
load-bearing:

1. **Wrong DUT.** It instantiates two bare `tidelink_top` modules
   (`tidelink_top_pair/tb_top.sv:298`, `:522`). G2 must cross two
   `nanosoc_eth_chiplet` (each = a full `nanosoc_multicore_soc` +
   `tidelink_top` + `tidechart_shim`, `src/rtl/nanosoc_eth_chiplet.sv:258`,
   `:489`, `:687`). The chiplet is not a superset of `tidelink_top` — it
   *buries* it.

2. **The signals the harness drives do not exist at the chiplet boundary.**
   `tidelink_top_pair` drives `tidelink_top`'s clocks, resets, APB config
   port, AHB TX/FIFO apertures and role/autoneg straps as direct tb nets
   (`tb_top.sv:132-135` clocks/resets; `:260-276` APB; `:203-223` AHB TX;
   `:448`/`:654` `role_strap_i`; `:456`/`:660` `nego_priority_i`;
   `:451-452` `apb_debug_unlock_i`/`mask_hs_bypass_i`). In the chiplet **all
   of these are internal**: the SoC's clock/reset controller *drives*
   `sys_hclk`/`sys_poresetn`/`sys_hresetn` as chiplet **outputs**
   (`nanosoc_eth_chiplet.sv:53-54`, `:58`) and feeds them into the link
   (`:491-495`); the APB and AHB apertures are reachable **only** through the
   SoC's `d2d_ahb_m` window; and `apb_debug_unlock_i`/`mask_hs_bypass_i`/
   `nego_priority_i` are **hardwired to constants** (`:626`, `:627`, `:629`).
   The only link-facing pins the chiplet still exports are the PHY pads
   (`:146-151`), `role_strap_i` (`:162`) and the I2C sideband (`:156-161`).

3. **The bring-up method is incompatible.** `tidelink_top_pair` brings the link
   up by writing `ROLE_CFG` over a *direct* APB master
   (`test_tidelink_pair_doorbell.py:393-394`), which only latches because the
   tb holds `mask_hs_bypass_i=1`/`apb_debug_unlock_i=1`
   (`tb_top.sv:154-159`, and the test's own note at
   `test_tidelink_pair_doorbell.py:386-388`). The chiplet ties **both of those
   low** (`nanosoc_eth_chiplet.sv:626-627`), so that path is gated shut. G2
   must drive the APB **through** the SoC (`eth_ss_0` → `0x2E03xxxx`) and/or use
   autonomous autoneg — a different mechanism entirely.

Why `soc_d2d_loopback` is the right *drive model* but not a reusable *harness*:
it already proves the exact access path G2 needs — an `eth_ss_0` AHB BFM
reaching `0x2E`/`0x2F` with **no firmware**, both cores parked
(`soc_d2d_loopback/tb_top.sv:24-27`, test `:114-118`) — but it is single-die
and terminates the far side of the link in a `d2d_ahb_slave_model` memory
(`tb_top.sv:141-157`). G2 replaces that memory with a *real second die*.

**Conclusion: write `sim/soc_d2d_pair/tb_top.sv` fresh, cut-and-paste the PHY
cross + `pad_skid` + POR-gate block from `tidelink_top_pair/tb_top.sv:145-195`,
and cut-and-paste the per-die drive scaffold (QSPI tie-off, `eth_ss_0` idle
init, no-firmware settle) from `soc_d2d_loopback/tb_top.sv`.** Estimated new
code: ~250 lines of `tb_top.sv` (two chiplet instances + one PHY cross) plus a
Makefile and one test module.

---

## 1. Evidence for each required determination

### 1.1 PHY wiring — how the pads cross

`tidelink_top_pair` cross-wires the two dies through a per-direction `pad_skid`
(default `SKID_BITS=0` = passthrough), gated to 0 while the driving die is in
reset. The exact connections (`tidelink_top_pair/tb_top.sv`):

```
master.pad_clk_tx (:389) → u_skid_m2s → m_pad_clk_tx_skid → slave.pad_clk_rx (:604, &m_por_gate)
master.pad_tx     (:390) → u_skid_m2s → m_pad_tx_skid     → slave.pad_rx     (:605, &{m_por_gate})
slave.pad_clk_tx  (:602) → u_skid_s2m → s_pad_clk_tx_skid → master.pad_clk_rx (:391, &s_por_gate)
slave.pad_tx      (:603) → u_skid_s2m → s_pad_tx_skid     → master.pad_rx    (:392, &{s_por_gate})
```

- **`NUM_PHY_LANES`**: the pair uses `8` (`tb_top.sv:124`), matching the chiplet
  default (`nanosoc_eth_chiplet.sv:42`) and the `tidelink_top` default
  (`INTEGRATION_GUIDE.md:159`). The crossing is `pad_clk` + `NUM_PHY_LANES` data
  wires per direction.
- **Skew/delay modelling**: yes — `pad_skid` inserts a configurable per-lane
  bit-slip (`tb_top.sv:171-195`), overridable per lane via `+define+TB_TOP_SKID_Lx`
  (`tb_top.sv:58-65`) to excite the cross-lane deskew bug. **For G2, keep
  `SKID_BITS=0`** — the deskew/IDELAY machinery is an FPGA-silicon concern; a
  zero-skew passthrough is the clean protocol path (`tb_top.sv:50-53` says
  exactly this).
- **X-poison guard**: the `&por_gate` / `&{NUM_PHY_LANES{por_gate}}` masks
  squash an in-reset die's pads to 0 so it cannot X-poison the live peer's RX
  (`tb_top.sv:391-392`, `:604-605`; rationale `:141-144`). **G2 must keep this**
  — with two independent SoC reset controllers the two dies *will* leave reset
  at different times.

**G2 reuses this block verbatim.** The pads are the one part of the chiplet
boundary that matches `tidelink_top` 1:1 (`nanosoc_eth_chiplet.sv:146-151`).

### 1.2 Clocking + reset

`tidelink_top_pair` generates **one** shared `hclk` and one `ref_clk` as tb nets
and feeds both dies from them (`tb_top.sv:132-133`, `:308`/`:385` master,
`:532`/`:600` slave). Resets `poresetn`/`hresetn` are tb-driven
(`tb_top.sv:134-135`), released `poresetn` → wait → `hresetn`
(`test_tidelink_pair_doorbell.py:360-367`). The two dies are deliberately on
the **same** `hclk` (`tb_top.sv:36-38` explains why: the HW MMCM feeds both
sides, so drift is out of scope), but per-die **POR skew** is injectable via
`m_por_gate`/`s_por_gate` (`tb_top.sv:145-150`).

**What changes for G2.** The chiplet has no `hclk`/`poresetn`/`hresetn` input —
its SoC *produces* them (`nanosoc_eth_chiplet.sv:53-54`, `:58`) from
`sys_fclk` + `sys_sysresetn` (`:51-52`), and feeds them into the link
internally (`:491-495`). So the G2 tb drives, **per die**, only:

| Chiplet input | G2 drive | Note |
|---|---|---|
| `sys_fclk` | free-running clock | `soc_d2d_loopback` uses 100 MHz / 10 ns (`tb_top.sv:33`,`:38-39`) |
| `sys_sysresetn` | active-low reset, released after ~200 ns | `soc_d2d_loopback/tb_top.sv:41-45` |
| `user_ref_clk` | Wlink PLL ref (~125 MHz / 8 ns) | pair uses 8 ns (`test…:103`) |
| `idelay_ref_clk` | tie `1'b0` in sim | `USE_IDELAY=0` default → passthrough (`tb_top.sv:394-395`) |
| `rtc_clk` | tie to `sys_fclk` | `soc_d2d_loopback/tb_top.sv:313` |
| `role_strap_i` | `0` die A / `1` die B | boundary port (`:162`) |

**Same clock or skewed?** Recommendation: **give each die its own `sys_fclk`
oscillator** (two `always #… ` generators), nominally identical, so the two
SoC reset controllers, PLLs and PHC servos are genuinely asynchronous — that is
the realistic chiplet condition and the reason the pair harness carries the
POR-gate machinery at all. Start them in phase for the first bring-up bring-up
test; add a deliberate ppm offset / phase skew in a follow-up test. A shared
clock is acceptable for a first green but hides real CDC on the pad crossing.

**Reset order (per die):** assert `sys_sysresetn=0`, run a few `sys_fclk`
edges, release `sys_sysresetn=1` (`soc_d2d_loopback/tb_top.sv:41-45`). The SoC's
internal controller then sequences `poresetn` → `hresetn` to the link
(`nanosoc_eth_chiplet.sv:491-495` wires the SoC-produced resets straight in).
G2 does **not** sequence `poresetn`/`hresetn` itself — that is inside each SoC.
The only cross-die ordering knob G2 owns is *when each die's `sys_sysresetn`
releases* — the analogue of `m_por_gate`/`s_por_gate`. Stagger it in a later
test to reproduce deploy-skew.

### 1.3 Role / autoneg — the minimum path to `link_active=1`

This is the sharpest finding in the whole study.

**`tidelink_top_pair` supports two modes:**
- `BYPASS_AUTONEG=1` (default): autoneg parks in `ST_BYPASS`; role-lock is driven
  by an APB `ROLE_CFG` W1S write (`test…:371-395`), which latches **only because
  the tb holds `mask_hs_bypass_i=1`** (`tb_top.sv:158-159`, note `test…:386-388`).
- `BYPASS_AUTONEG=0`: the tb `force`s `nego_cfg_reg=7'h61` and
  `nego_train_cfg_r=16'h00F1` onto both dies at time 0 (`tb_top.sv:776-779`) so
  the autoneg FSM walks the full chain with no APB stimulus — the "autonomous"
  path exercised by `test_10`, `test_30`, `test_31`.

**The chiplet as currently wired cannot do *either*.** Evidence:

- `nanosoc_eth_chiplet.sv:626` ties `apb_debug_unlock_i(1'b0)` and `:627`
  ties `mask_hs_bypass_i(1'b0)`. So the APB `ROLE_CFG` W1S gate is **shut** —
  the `BYPASS_AUTONEG=1` path is unavailable.
- The chiplet instantiates `tidelink_top #(.NUM_PHY_LANES(NUM_PHY_LANES))`
  (`:489`) and passes **no** `NEGO_CFG_RESET`. The `tidelink_top` default is
  **`7'h00`** (`tidelink/src/rtl/tidelink_top.sv:123`), and the chiplet
  controller resets `nego_cfg_reg <= NEGO_CFG_RESET`
  (`tidelink/src/rtl/local_overrides/axi_chiplet_controller.sv:79`, `:666`).
  So at POR `nego_en=0` → autoneg parks in `ST_BYPASS` → **`role_locked` never
  asserts and the link never comes up autonomously either.**
- `:629` ties `nego_priority_i(16'h0000)`, `:631` `puf_ready(1'b0)` — the
  pair harness deliberately supplies non-zero priority + `puf_ready=1`
  (`tb_top.sv:456`,`:458`,`:660`,`:662`) precisely so the negotiator settles;
  the chiplet supplies neither.

> **The `INTEGRATION_GUIDE.md:162` claim that `NEGO_CFG_RESET` defaults to
> `7'h61` is stale.** The pinned RTL default is `7'h00`
> (`tidelink_top.sv:123`, `axi_chiplet_controller.sv:79`). Do not trust the
> guide on this; trust the RTL.

**Consequence — G2 needs one of these three, and this is a decision the human
must make before G2 can be green:**

- **(A) Recommended: the chiplet overrides `NEGO_CFG_RESET(7'h61)` (and
  supplies a non-zero `nego_priority_i` + `puf_ready`) on its `tidelink_top`
  instance.** One-line RTL change at `nanosoc_eth_chiplet.sv:489`. This makes
  the die bring its own link up autonomously from `role_strap_i` alone — the
  correct silicon behaviour, and the only one that survives to a real chiplet
  with no test harness. **This is out of scope for *this* (read-only) task but
  is the right fix.**
- **(B) The chiplet exposes `mask_hs_bypass_i`/`apb_debug_unlock_i`/
  `nego_priority_i` as boundary ports or parameters**, and G2 drives them like
  the pair tb does, then uses the SW-coordinated `ROLE_CFG` path *through the
  `0x2E03` APB window*.
- **(C) G2 `force`s the hierarchical `nego_cfg_reg` per die** — the same trick
  as `tb_top.sv:776`, but the path is now
  `dut.u_die_a.u_tidelink.u_chiplet_controller.nego_cfg_reg` (3 levels deeper,
  through the SoC). Works in sim, proves nothing about silicon, and is brittle.

**Minimum bring-up sequence to `link_active=1` (assuming option A/C so autoneg
runs)**, mirroring the autonomous pair flow (`run_bringup_through_phase1`,
`test…:605-635`) plus data-mode entry (`do_to_data_mode`, `test…:447-463`):

1. Reset both dies (§1.2).
2. Shrink the calibrator dwell so the sweep fits the sim budget — the pair
   harness does this two ways: `force_calibrator_sim_bypass` sets
   `tb_early_exit_force_q=1` (`test…:502-519`) and/or `TB_TOP_SHORT_CAL_HOLD`/
   `_DWELL` defparams (`tb_top.sv:849-856`). Production `HOLD_CYCLES = 8·128·64
   = 65536` link cycles (`tidelink_phy_align_calibrator.sv:237`) ≫ sim budget.
   G2 sets the same defparam, path
   `u_die_{a,b}.u_tidelink.u_chiplet_controller.<g_phy_arm>.u_calibrator`
   (instance name preserved for exactly this, `axi_chiplet_controller.sv:4912`,
   `:4985`/`:5086`).
3. `role_strap_i` = 0 (A) / 1 (B); autoneg runs, `role_locked` rises on both.
   The pair budgets `wait_role_locked(max_cycles=20000)` (`test…:397`).
4. Wait for calibration: poll `SWI_LANE_STATUS` for `cal_done[16]=1` both sides;
   pair budgets `wait_cal_done(max_cycles=500000)` (`test…:631`). In G2 this
   read is `eth_ss_0` → `0x2E032108`.
5. Data-mode entry (`do_to_data_mode`): write `SWI_TRAINING_MODE 0x2E032100 = 0`,
   then cycle `WL_EnableReset 0x2E030208 = 0x00027f08 → 0x00027f00 → 0x00027f07`
   on both dies (`test…:453-463`; guide §7 step 3, `INTEGRATION_GUIDE.md:269-272`).
6. `link_active` asserts. **Note: `link_active` is NOT a chiplet boundary port**
   — it feeds `tidechart_shim` internally (`nanosoc_eth_chiplet.sv:619`,
   net `tc_link_active`). Probe it hierarchically:
   `dut.u_die_a.u_tidelink.link_active` (or the `tc_link_active` wire).

### 1.4 Runtime cost / does G2 need a reduced-memory SoC?

The pair sim's dominant cost is the **calibration sweep**, not the SoCs. The
pair budgets **500 000 `hclk` cycles** for `cal_done` (`test…:631`) and only
gets there by shrinking the calibrator (`tb_early_exit_force_q` /
`SHORT_CAL_HOLD`, §1.3 step 2); without the shrink the calibrator's
`VALIDATION_TIMEOUT` alone is ~2 M link cycles (`test…:507-513`). Layer on:

- **2× full `nanosoc_multicore_soc`** elaboration + per-die settle. The SoC
  settle to a quiet bus (CPU1 stage-0 halt) is `SETTLE_CYCLES=3000`
  (`soc_d2d_loopback/test…:65`,`:116`).
- 2× `tidelink_top` (Wlink, FIFO SRAM, calibrator, address translator, PTP).
- 2× `tidechart_shim`.

**Estimate:** compile/elaborate is roughly 2× the `soc_d2d_loopback` build
(minutes). Per-test wall clock is driven by the ~10⁵–10⁶ cycles of link
bring-up multiplied by the cost of stepping two full SoCs; expect **tens of
minutes per test**, possibly worse for the sustained-traffic tests.

**Reduced-memory SoC: optional, and not the main lever.** This env preloads
**no firmware** (`soc_d2d_loopback/tb_top.sv:24-27`), so IMEM/DMEM *contents*
don't matter and their *size* affects elaboration/compile, not the cycle count.
Shrinking IMEM/DMEM (the FPGA `soc_model_fpga` split is 16 KB/4 KB per
`MEMORY.md`) would cut elaboration a little. **The real levers are: (a) bound
the calibrator (mandatory), (b) `SKID_BITS=0`, (c) shared `sys_fclk` for the
first green, (d) `TB_TOP_NO_DUMP`-style VCD gating — the pair harness OOM'd the
host at >4 GB VCD (`tb_top.sv:830-838`, Makefile `:72-79`); G2 with two SoCs is
far worse, so default waves OFF.**

### 1.5 What drives the CPUs

`soc_d2d_loopback` runs **no firmware**: CPU0 is the boot-gated secondary and
is never released (never fetches); CPU1 runs stage-0, reads the unprogrammed
(all-`0xFF`) flash, fails the BOOT-table magic check and halts — both cores
leave the bus free for the BFM (`soc_d2d_loopback/tb_top.sv:24-27`,
`test…:63-64`). **This trick transfers to a chiplet pair directly**, applied
**per die**:

- Each die gets its own `eth_ss_0` AHB BFM (`cocotbext-ahb` `AHBLiteMaster`
  on the `eth_ss_0_*` boundary, `nanosoc_eth_chiplet.sv:60-69`; the loopback
  pattern is `test…:114-118`). Two BFMs, one per die prefix.
- Each die needs its CPU1 to halt, which needs its flash read to return
  non-magic. **The QSPI VIP is *not* required** — tie each die's `qspi_io_i =
  4'hF` so the read returns `0xFFFFFFFF` and CPU1 halts on the magic mismatch
  (the loopback comment `tb_top.sv:69-71` confirms `0xFFFFFFFF` is what causes
  the halt). Dropping the two `sst26vf064b` instances also removes their
  `defparam` timing (`soc_d2d_loopback/tb_top.sv:345-354`) and speeds the
  build. Keep the VIP only if a later test exercises real DMA-boot.

So G2 drives everything from **two `eth_ss_0` BFMs** — one per die — exactly as
`soc_d2d_loopback` drives one. No firmware, no CPU model, no QSPI VIP.

### 1.6 TideChart — does the election gate the data plane?

**No. The AHB data plane is independent of TideChart root election.** Evidence:

- The CPU data plane crosses the link through `tidelink_top`'s AHB ports
  (`ahb_tx`/`ahb_sub`/`ahb_fifo`/`ahb_mng`), fed by the chiplet's `d2d_ahb_m`
  sub-decode (`nanosoc_eth_chiplet.sv:498-542`). TideChart sits on the separate
  `tc_axis_*` FC-stream seam (`:604-610`, `:694-700`) carrying its own
  `PKT_EXT` packets (`INTEGRATION_GUIDE.md:145`). Root election floods on
  `tc_axis_*`; it does not sit in the AHB path.
- In a **2-die point-to-point** link, cross-die addressing is done by the
  TideLink **address translator** (peer aperture `0x2F`, config at `0x2E034xxx`),
  **not** by TideChart logical IDs. `soc_d2d_loopback` proves the AHB path end
  to end with TideChart's seam **tied off entirely** (`tb_top.sv` never touches
  `tc_axis_*`; the pair harness ties `tc_axis_tx_tvalid=0`,
  `tc_axis_rx_tready=1`, `tidelink_top_pair/tb_top.sv:429-435`).

So G2's three data-plane assertions (§4) do **not** require election to run.

**But the `DEVICE_CLASS` collision is real and must be handled if you *do* run
election.** The chiplet instantiates `tidechart_shim #(.NUM_PORTS(1),
.FC_DATA_W(48))` (`nanosoc_eth_chiplet.sv:687-690`) and passes **no**
`DEVICE_CLASS`, so it takes the shim default **`16'h0001`**
(`src/rtl/tidechart_shim.sv:57`), which is also the controller/FSM default
(`tidechart/src/rtl/tidechart_election_fsm.sv:33`,`:224`;
`tidechart_controller.sv:22`). **Both dies therefore claim
`{DEVICE_CLASS=0x0001, random_id}`.** In the election, lower `DEVICE_CLASS`
wins and ties break on the 16-bit LFSR `random_id` (`README.md:7`). With equal
`DEVICE_CLASS` the outcome is decided **solely by the random IDs** — non-
deterministic across seeds, and if both LFSRs are seeded identically (same
reset, same clock) it risks a **dual-root** (`TC_ERROR[2]`, `README.md:103`).

**Recommendation:** for any G2 test that runs TideChart election, strap the two
dies to **different `DEVICE_CLASS`** (e.g. die A `0x0001`, die B `0x0002`) so
one deterministically becomes root — the same asymmetry the pair harness
imposes on `nego_priority_i` (`tb_top.sv:456`/`:660`). This needs the chiplet
to expose/override `DEVICE_CLASS` on the `tidechart_shim` instance (currently it
does not). Until then, **keep G2's data-plane assertions independent of
election** (they already are, per above) and defer an election test.

---

## 2. Proposed `sim/soc_d2d_pair/tb_top.sv` — block diagram

```
                          sim/soc_d2d_pair/tb_top.sv
 ┌───────────────────────────────────────────────────────────────────────────┐
 │                                                                           │
 │   fclk_a osc ─┐                                          ┌─ fclk_b osc      │
 │   ref_clk_a ──┤                                          ├── ref_clk_b      │
 │   srstn_a  ───┤ (release skew = the m/s_por_gate analogue)├── srstn_b       │
 │               │                                          │                  │
 │        ┌──────▼───────────────────┐          ┌───────────▼──────────────┐   │
 │        │   u_die_a                │          │   u_die_b                │   │
 │        │   nanosoc_eth_chiplet    │          │   nanosoc_eth_chiplet    │   │
 │        │   role_strap_i = 0 (mst) │          │   role_strap_i = 1 (slv) │   │
 │        │                          │          │                          │   │
 │  ┌────►│ eth_ss_0_*  (AHB slave)  │    ┌────►│ eth_ss_0_*  (AHB slave)  │   │
 │  │     │ qspi_io_i = 4'hF         │    │     │ qspi_io_i = 4'hF         │   │
 │  │     │                          │    │     │                          │   │
 │  │     │ pad_clk_tx ─┐  pad_clk_rx │    │     │ pad_clk_tx ─┐ pad_clk_rx │   │
 │  │     │ pad_tx[7:0]─┤  pad_rx[7:0]│    │     │ pad_tx[7:0]─┤ pad_rx[7:0]│   │
 │  │     └─────────────┼──────▲──────┘    │     └─────────────┼─────▲──────┘   │
 │  │                   │      │           │                   │     │          │
 │  │      a2b ┌────────▼──────┼───────────┼──── pad_skid ─────▼─────┘ (to B.rx)│
 │  │          │ u_skid_a2b (SKID_BITS=0, & a_por_gate)                         │
 │  │          └───────────────┼───────────┼──────────────────────────┐        │
 │  │      b2a                  │           │  u_skid_b2a (& b_por_gate)│        │
 │  │          ┌────────────────┘           └──────────────────────────┘        │
 │  │          │ (B.pad_tx → A.pad_rx)                                          │
 │  │          └──────────────────────────────────────────────► (to A.rx)      │
 │  │                                                                           │
 │  │   i2c_scl / i2c_sda : wired-AND pull-up bus across both dies              │
 │  │        (tidelink_top_pair/tb_top.sv:290-293 pattern)                      │
 │  │                                                                           │
 │  └── cocotbext-ahb AHBLiteMaster("eth_ss_0")  ×2  (one per die)   ──┐        │
 │                                                                    │        │
 │   PROBES (hierarchical, no boundary port):                         │        │
 │     u_die_{a,b}.u_tidelink.link_active                             │        │
 │     u_die_{a,b}.u_soc.network_core_irq_bus   (doorbell → CPU0 NVIC)│        │
 │     u_die_{a,b}.u_tidelink.u_chiplet_controller.<phy>.u_calibrator │        │
 └────────────────────────────────────────────────────────────────────────────┘
        test_soc_d2d_pair.py drives both eth_ss_0 BFMs + the bring-up regs
```

Directionality of the cross (mirror of `tidelink_top_pair/tb_top.sv:389-392`,
`:604-605`):

```
u_die_a.pad_clk_tx → u_skid_a2b → (& a_por_gate) → u_die_b.pad_clk_rx
u_die_a.pad_tx[7:0]→ u_skid_a2b → (& {8{a_por_gate}}) → u_die_b.pad_rx[7:0]
u_die_b.pad_clk_tx → u_skid_b2a → (& b_por_gate) → u_die_a.pad_clk_rx
u_die_b.pad_tx[7:0]→ u_skid_b2a → (& {8{b_por_gate}}) → u_die_a.pad_rx[7:0]
```

`idelay_ref_clk = 1'b0`, `rtc_clk = fclk`, I2C wired-AND idle-high, all other
chiplet outputs left open, all other chiplet inputs tied to their idle values
(follow `soc_d2d_loopback/tb_top.sv:286-342` for the SoC-side idle set).

---

## 3. File list — RTL, flists, env

**No new RTL.** G2 instantiates `nanosoc_eth_chiplet` twice. Reused files:

| File | Role in G2 | Source |
|---|---|---|
| `src/rtl/nanosoc_eth_chiplet.sv` (+ `chiplet_d2d_decode.sv`, `tidechart_shim.sv`) | the DUT, ×2 | this repo |
| `flist/nanosoc_eth_chiplet.flist` | compiles SoC + tidelink (`tidelink_fpga.flist`) + tidechart, once; instantiated twice | this repo `:35-60` |
| `tidelink/cocotb/tidelink_top_pair/pad_skid.sv` | the PHY-cross delay element | copy into `sim/soc_d2d_pair/` |
| **new** `sim/soc_d2d_pair/tb_top.sv` | two chiplets + one PHY cross (§2) | write |
| **new** `sim/soc_d2d_pair/Makefile` | see below | write |
| **new** `sim/soc_d2d_pair/test_soc_d2d_pair.py` | the assertions (§4) | write |

**Makefile** — model on `soc_d2d_loopback/Makefile`, but the DUT flist is the
chiplet's, not the SoC's:

- `VERILOG_SOURCES = tb_top.sv pad_skid.sv`, `TOPLEVEL = tb_top`.
- Consume `flist/nanosoc_eth_chiplet.flist` the same way the chiplet's own
  `make elab` does — it flattens the SoC's `$(VAR)` flist to
  `${CHIPLET_SOC_VCS_FLIST}` first (chiplet `flist/nanosoc_eth_chiplet.flist:35`,
  `flatten_soc_flist.py`). Reuse that machinery; do not re-invent it.
- `COCOTB_RESOLVE_X ?= ZEROS` (the OpenCores MAC drives X on `hrdata` during
  APB writes; `soc_d2d_loopback/Makefile:50`). **Caveat from `MEMORY.md`:
  `ZEROS` silently X-resolves missing handles — keep every G2 probe behind an
  `is_resolvable` check** (the loopback tests already do, `test…:105`).
- **Default `WAVES` OFF** (§1.4). Two SoCs + link ≫ the pair's >4 GB VCD.
- **Flist duplicate-module note:** the chiplet flist already documents that the
  SoC and TideLink flists both compile three CMSDK cells (`OPD` "override
  previous declaration", benign — `nanosoc_eth_chiplet.flist:16-21`). Compiling
  the chiplet once and instantiating twice does **not** add new duplicates.

**Env prerequisites** (chiplet `README.md:125-129`): `git submodule update
--init --recursive`, then source all three `set_env.sh` in order. G2's Makefile
inherits this from the chiplet's `make elab` path.

---

## 4. The three `G2_PAIR_SIM.md` assertions as concrete cocotb steps

Addresses use the chiplet window map (`README.md` sub-map; the SoC's
`0x44030000`/`0x44032000` reference base rebased to `0x2E030000`/`0x2E032000`,
`README.md:65-95`). All register access is `eth_ss_0` BFM → `0x2E`/`0x2F`, the
`soc_d2d_loopback` access path (`test…:31-32`). Prerequisite for all three:
run §1.3 bring-up until `dut.u_die_a.u_tidelink.link_active == 1` **and**
`dut.u_die_b.u_tidelink.link_active == 1`.

### Assertion 1 — cross-die write (the data plane)

*CPU0/BFM on die A writes shared SRAM on die B; die B reads it back.*

1. Configure the address translator so die A's peer aperture `0x2F…` maps to die
   B's `shared_sram` window. Translator config lives in the `0x2E034xxx` APB
   bank (`README.md:90-92`); set the peer-base so `0x2F000000 + X` →
   `0x2D000000 + X` on the far die (`SHARED_SRAM = 0x2D000000`,
   `soc_d2d_loopback/test…:51`). *(If the reduced d2d target list only admits
   `shared_sram` + `ipc_mailbox` on the inbound side — it does,
   `soc_d2d_loopback/test…:257-294` — the translated address must land in one
   of those two.)*
2. `await ahb_a.write(0x2F00_0000 + 0x10, 0x5A5A1234)` — die A peer-aperture
   write (`ahb_sub` path, `nanosoc_eth_chiplet.sv:498-509`). This is
   link-safe with the link **up**.
3. Let the link carry it: die B's `ahb_mng` drives die B's `d2d_ahb_s` into
   `shared_sram` (`nanosoc_eth_chiplet.sv:532-542`; mirror of the inbound leg in
   `soc_d2d_loopback/test…:229-238`).
4. `got = await ahb_b.read(0x2D00_0000 + 0x10)`; **assert `got == 0x5A5A1234`.**
5. Reverse the direction (die B → die A) as a symmetry check — this is where the
   historical S→M asymmetry bites (§5, Risk 3).

### Assertion 2 — cross-die doorbell (the interrupt seam)

*A write to the doorbell on die A raises `doorbell_irq` on die B's CPU0 NVIC at
`IRQ[10]`.*

1. Clear die B's read-to-clear accumulator: `await ahb_b.read(0x2E03_2024)`
   (`DOORBELL_RESPONSE_ACC`, W-add/R-clear, `test…:882-892`).
2. Ring the doorbell on die A: `await ahb_a.write(0x2E03_2014, 1)`
   (`DOORBELL`, `OFF_DOORBELL=0x014` + base `0x2E032000`, `test…:66-67`,`:906`).
3. Assert the packet crossed and landed as an interrupt on **die B**:
   - `assert int(dut.u_die_b.u_soc.network_core_irq_bus.value) >> 10 & 1`
     — `tl_doorbell_irq` → `d2d_irq[0]` (`nanosoc_eth_chiplet.sv:745`) →
     CPU0 NVIC bit 10 (`CPU0_D2D_IRQ_BASE=10`,
     `soc_d2d_loopback/test…:48`,`:328-331`). This is the "lands at `IRQ[10]`"
     claim in `G2_PAIR_SIM.md:26-27`.
   - and `assert (await ahb_b.read(0x2E03_2024)) != 0`
     — `DOORBELL_RESPONSE_ACC` ticked (`test…:913-916`).
4. Cross-check die A's CPU0 bus was **not** disturbed (the loopback isolation
   pattern, `test…:339-341`).

### Assertion 3 — wedge hazard (the one worth building the env for)

*A TX-aperture write while `link_active=0` must wait-state, not wedge, and must
complete once the link comes up.*

1. **Before** bring-up (link down), issue a TX-aperture write on die A **in a
   forked coroutine with a bounded timeout**:
   `write_task = cocotb.start_soon(ahb_a.write(0x2E00_0000, 0xC0FFEE00))`
   (`0x2E000000` = `ahb_tx` aperture, the documented **WEDGE HAZARD** —
   `README.md:76`, `INTEGRATION_GUIDE.md:131`).
2. Assert it is **stalled, not hung**: after N cycles `write_task` has **not**
   completed *and* `dut.d2d_ahb_m` HREADY is low (transaction wait-stated) —
   distinguish "wait-stating" from "hung" only by whether it later completes.
3. Bring the link up (§1.3).
4. **Assert `write_task` completes within a bounded window after
   `link_active==1`**, and read the word back from the far die's committed RX
   (`ahb_fifo` / the GP1 RX aperture, `MILESTONE_V2_A2B_DATA…:14-18`).

> **This assertion is likely to *fail* on the current chiplet, and that failure
> is the finding.** `README.md:76` states the `0x2E00` TX aperture is a wedge
> hazard that "hangs the bus — Gate it", and the wrapper's sub-decode does
> **not** implement a link-up gate (it forwards `hsel_tx` straight to
> `ahb_tx_hsel`, `nanosoc_eth_chiplet.sv:511-520`). So a link-down TX write may
> **wedge forever** rather than wait-state — which is exactly the silicon
> hazard G2 exists to catch. The cocotb test **must** use a timeout so a wedge
> reports as a clean `assert`, not a hung simulation. If it wedges, the fix
> (gate `hsel_tx` behind `link_active` in `chiplet_d2d_decode`) is a wrapper
> change, not an RTL-IP change — the right place for it per `G2_PAIR_SIM.md:31-35`.

**Prerequisite gate (run first, `G2_PAIR_SIM.md:38-43`):** confirm
`soc_d2d_loopback::test_d2d_outbound_slave_can_wait_state`
(`soc_d2d_loopback/test…:192-222`) is green on the pinned SoC — it proves the
matrix honours `d2d_ahb_m_hready`. Without that, assertion 3 fails in a way that
looks like a link bug but is a matrix bug.

---

## 5. Risks, ranked

**Risk 1 — BLOCKER: the chiplet cannot bring its link up as wired.**
`NEGO_CFG_RESET` defaults to `7'h00` (`tidelink_top.sv:123`,
`axi_chiplet_controller.sv:79`/`:666`) so autoneg parks in `ST_BYPASS`, and the
chiplet ties `mask_hs_bypass_i`/`apb_debug_unlock_i` low
(`nanosoc_eth_chiplet.sv:626-627`) so the SW `ROLE_CFG` path is shut too. **G2
cannot reach `link_active=1` without one of the three options in §1.3.** The
right fix (option A: override `NEGO_CFG_RESET(7'h61)` + non-zero
`nego_priority_i`/`puf_ready` on the chiplet's `tidelink_top`) is a chiplet RTL
change, out of scope for this read-only task, and **must be decided before G2
can pass**. This is the single biggest finding.

**Risk 2 — the S→M / bidirectional-crossing asymmetry may still be open.**
The pair harness's own tests document a **real RTL residual** where the
slave→master direction does not cross: `test_04_pair_credit_counter_nonzero`
and `test_06_doorbell_slave_to_master` are written to go green **only once that
bug is fixed** (`test…:759-771`, `:944-951` — "Bug A: master LL_RX never decodes
the slave's transmissions", the bridge1 b24 `PAIR_CREDIT_COUNTER==0` symptom).
The M→S direction (`test_05`) works. **G2 assertion 2 (doorbell) and the reverse
leg of assertion 1 depend on bidirectional crossing.** *Mitigation, and it is
cheap:* the tidelink pin is now `a2b-credit-max-fix-silicon-2026-07-09`
(`git submodule status`), whose `MILESTONE_V2_A2B_DATA` reports **deterministic
byte-exact A→B data** — so the fix may have landed. **Before building G2, re-run
the plain `tidelink_top_pair` env on the pinned commit and check `test_04`,
`test_05`, `test_06` all green.** If `test_06`/`test_04` are still red, G2's
doorbell assertion will only pass one direction, and that is a link bug to fix
upstream, not in G2.

**Risk 3 — V1 vs V2 PHY mismatch.** The chiplet flist compiles
`tidelink_fpga.flist` (V1 PHY, `nanosoc_eth_chiplet.flist:41`), but the proven
deterministic data path is `TIDELINK_PHY_V2=1` with a reduced lane mask
(`MILESTONE_V2_A2B_DATA…:4-6`). In sim with `SKID_BITS=0` the V1 PHY is
exercised by the existing pair tests and reaches `cal_done` + M→S doorbell, so
V1-in-sim is probably adequate — but if G2 needs the V2 credit/deskew fixes to
cross deterministically, the chiplet must be re-pointed at
`tidelink_fpga_v2.flist`. Unverified until §Risk-2's re-run. Ranked below 2
because it likely rides on the same re-run.

**Risk 4 — the wedge gate is missing (assertion 3 may wedge).** The wrapper
forwards `hsel_tx` ungated (`nanosoc_eth_chiplet.sv:511-520`) despite the
documented hazard (`README.md:76`). Assertion 3 must be written with a timeout
so a wedge is a clean failure. If it wedges, the fix is a `chiplet_d2d_decode`
change (gate `hsel_tx` behind `link_active`) — a wrapper change, in this repo's
scope, and arguably a follow-on deliverable G2 justifies.

**Risk 5 — runtime / VCD blow-up.** Two full SoCs + 2× link bring-up of
10⁵–10⁶ cycles is tens of minutes per test with waves off; the pair harness
already OOM'd a host at >4 GB VCD with **one** pair (`tb_top.sv:830-838`).
Mitigations in §1.4 (bound the calibrator, waves off by default, per-test not
per-suite). Non-blocking but will shape how many tests are practical.

**Risk 6 — `DEVICE_CLASS=0x0001` on both dies → dual-root if election runs.**
Both dies default to `16'h0001` (`tidechart_shim.sv:57`,
`nanosoc_eth_chiplet.sv:687-690`). Harmless as long as G2's data-plane
assertions stay election-independent (they are, §1.6), but any TideChart test
must strap different classes or risk a non-deterministic / dual-root election.

**Risk 7 — stale pins / docs.** The README claims tidelink is pinned to
`integ/tidelink-soc` and tidechart to `main` (`README.md:106-108`); the actual
pins are `a2b-credit-max-fix-silicon-2026-07-09` and
`add-subtree-and-irqc-axis`. `INTEGRATION_GUIDE.md:162` misstates the
`NEGO_CFG_RESET` default. **Trust the RTL and `git submodule status`, not the
prose**, throughout G2 bring-up.

---

## 6. What I am unsure about (stated plainly)

- **Whether the S→M direction crosses on the pinned tidelink.** I read the
  tests that document the bug and the milestone that claims the fix; I did not
  run either. This is the one thing that most changes G2's outcome, and it is a
  ~10-minute check (`make -C tidelink/cocotb/tidelink_top_pair
  MODULE=test_tidelink_pair_doorbell TESTCASE=test_04_pair_credit_counter_nonzero`
  etc.). **Do this before writing G2.**
- **Whether the chiplet's V1 PHY reaches data-mode deterministically in a
  two-SoC sim.** The pair tests reach `cal_done` on V1, but the *deterministic*
  data path was demonstrated on V2. Unverified for the chiplet.
- **The exact address-translator programming for assertion 1.** I know the bank
  is `0x2E034xxx` (`README.md:90-92`) and the reference offsets are preserved
  from TideLink's map, but I did not read the translator register detail; the
  concrete `PAIR_BASE`/mask writes need `tidelink/docs/REGISTER_MAP.md` §addr-
  translator before coding step 4.1.
- **Whether `link_active` is a sufficient gate for assertion 3, or whether the
  test should gate on `cr_pkt_seen_rx`/`PAIR_CREDIT_COUNTER` instead.** The pair
  tests never assert on `link_active` at all (`grep` finds no assertion) — they
  gate on credit/doorbell accumulators. `link_active` may assert earlier than
  the link can actually carry a TX packet, which would make assertion 3's
  "completes once link up" fire too early. Prefer gating the *completion* check
  on a real credit handshake, not just `link_active`.

---

*Design study for SoC Labs. Read-only investigation; no submodule or IP-library
file was modified. Copyright 2026, SoC Labs (www.soclabs.org).*
