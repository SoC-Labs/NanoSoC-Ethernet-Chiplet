# HOSTIO4 test-plan gap analysis — what a second debug port uniquely adds

**Written** 2026-08-25. **Method:** read-only inspection of the repo, the three sibling
IP repos, the generated interconnect RTL, the ASIC pad table and the shipping routed
netlist. **No hardware touched, no EDA tool run, no file in the repo modified.**

**Repo:** `/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet` @ `feat/padring-boundary-scan`

---

## 0. Executive summary — the five things that matter

1. **HOSTIO4 is real silicon, not a plan.** `HOSTIO4_P1[6:0]` is 7 bonded bidir pads
   (`uPAD_HOST_IO_0..6`, `PDDW16DGZ_G`, right side) in the as-built padring, and the ADP
   controller `u_debug_0/u_nanosoc_ss_debug/u_socdebug/u_adp_control` is placed and routed
   in the shipping netlist (1,613 instance references). It is one of only **23 bonded
   signal ports** on the die.

2. **On a standalone ASIC there is no PS backdoor — structurally, not just practically.**
   The chip has no external AHB/AXI slave port at all. `eth_ss_0` is an *internal* SoC port
   that on the KR260 happens to be driven by the Zynq PS through the PL. Off that carrier it
   does not exist on any pin. The complete external-host inventory on the die is: **SWD
   (2 pins) and HOSTIO4 (7 pins).** Everything else is QSPI (flash master), I²C (TideLink
   sideband), RMII (ethernet), TL_TX/TL_RX (D2D), and straps. **This is the crux and it is
   CONFIRMED, not assumed.**

3. **SWD has never returned a DPIDR on these boards.** So today HOSTIO4 is the *only*
   demonstrated host-to-bus path that survives the move off the KR260 carrier.

4. **HOSTIO4 reaches two address regions the PS backdoor cannot reach at all**, on the
   KR260 vehicle today: the entire **CPU1 subsystem** (`0x8000_0000–0x9FFF_FFFF`: CPU1
   bootrom / IMEM / DMEM) and **`cc_periph_0`** (`0x2800_0000`: CPU1 UART, timers,
   watchdog). Proven in the generated decoders, not inferred.

5. **HOSTIO4 has one hard blind spot the PS backdoor does not have: the Ethernet MAC.**
   `debug_m` enters at the *top* matrix, whose `eth_ss_slave` window is only
   `0x0000_0000–0x1FFF_FFFF`. ETHMAC lives at eth-subsystem-local `0x4000_0000`, which is
   inside the subsystem's own decode — reachable by the PS (which enters *at* `eth_ss_0`)
   and by CPU0 firmware, but **not by HOSTIO4 and not by SWD**. Any HOSTIO ethernet test
   must go indirectly, through firmware HOSTIO loads into CPU0 IMEM.

---

## 1. The access-path facts, established from generated RTL

Everything in §2/§3 rests on these. Each was read out of the *generated* decoder, with the
DAP decoder used as a positive control for the method (it shows the extra regions the YAML
says it should, so the method can discriminate).

### 1a. Top-matrix initiator reach (`tidelink/imp/fpga/eth_chiplet_ip/src/multicore_matrix_decode_*.v`)

| Region | Target | `ETH_SS_M`<br>(= PS backdoor's exit) | `DEBUG_M`<br>(= HOSTIO4) | `DAP_SS_0_M`<br>(= SWD) | `D2D_M`<br>(= peer die) |
|---|---|:--:|:--:|:--:|:--:|
| `0x0000_0000–0x1FFF_FFFF` | `eth_ss_slave` (CPU0 bootrom/IMEM/DMEM) | – | ✅ | ✅ | – |
| `0x2000_0000` | `dmac_0` (DMA-230 APB cfg) | ✅ | ✅ | ✅ | – |
| `0x2100_0000` | `qspi_flash_0` | ✅ | ✅ | ✅ | – |
| `0x2200_0000` | **`phc_0` (PTP hardware clock)** | ✅ | ✅ | ✅ | – |
| `0x2300_0000` | `ipc_mailbox_0` | ✅ | ✅ | ✅ | ✅ |
| `0x2400_0000–0x27FF_FFFF` | `qspi_flash_xip` | ✅ | ✅ | ✅ | – |
| **`0x2800_0000`** | **`cc_periph_0` (CPU1 UART/timers/WDT)** | **❌** | **✅** | ✅ | – |
| `0x2900_0000` | `chip_core_remap_0` (BOOTGATE) | ✅ | ✅ | ✅ | – |
| `0x2A00_0000` | `reset_ctrl_0` | ✅ | ✅ | ✅ | – |
| `0x2B00_0000` | `evt_route_0` | ✅ | ✅ | ✅ | – |
| `0x2C00_0000` | `ctrl_dbg_group` (ETC/spinlock/perf/bus_dbg) | ✅ | ✅ | ✅ | – |
| `0x2D00_0000` | `shared_sram_0` | ✅ | ✅ | ✅ | ✅ |
| `0x2E00_0000–0x2FFF_FFFF` | **`d2d`** (TideLink cfg `0x2E` + peer aperture `0x2F`) | ✅ | ✅ | ✅ | – |
| `0x5000_0000–0x5FFF_FFFF` | eth-ss APB (incl. `eth_ss_sysctrl` REMAP `0x5000_2000`) | – (see 1b) | **❌** | ✅ *(DAP-only widening)* | – |
| **`0x8000_0000–0x9FFF_FFFF`** | **`cpu_ss_1_slave` (CPU1 bootrom/IMEM/DMEM)** | **❌** | **✅** | ✅ | – |
| `0xA000_0000` / `0xB000_0000` | per-core PPB debug windows | ❌ | **❌** | ✅ | – |

The YAML comment is explicit and matches the RTL:

> HOSTIO4 host-access debug master (`u_debug_0` ADP → AHB) … **Same broad reach as the SWD
> DAP master, minus the per-core PPB debug windows** (those are CoreSight-only).
> — `nanosoc-multicore-system/sys_desc/nanosoc_multicore_soc.yaml:2341-2348`

### 1b. Why the PS backdoor sees ETHMAC and HOSTIO4 does not

The PS enters the SoC **at `eth_ss_0`**, i.e. *inside* the ethernet subsystem, and so sees
that subsystem's full local decode
(`tidelink/imp/fpga/eth_chiplet_ip/src/eth_ss_matrix_decode_ETH_SS_0.v:383-422`):

```
0x0000_0000 bootrom | 0x1000_0000 imem | 0x1800_0000 dmem
0x2000_0000-0x2FFF_FFFF  passthrough -> top matrix (this is ETH_SS_M above)
0x3000_0000 eth_scratch_rx | 0x3800_0000 eth_scratch_tx
0x4000_0000 ETHMAC | 0x4800_0000 crc_checker | 0x5000_0000 apb_periph
```

HOSTIO4 enters at the **top** matrix, where the whole ethernet subsystem is one 512 MB
window at `0x0000_0000` size `0x2000_0000`. `0x4000_0000` is simply not in HOSTIO4's decode
table. This is the single most important asymmetry in the whole analysis and it runs the
*opposite* way to everything else.

### 1c. ASIC bonded-pin inventory (`src/rtl/bscan/pad_table.json`, `ASIC/submissions/padring_as_built_rzG_20260823/`)

23 signal ports: `SE CLK TEST NRST SWDIO SWDCK QSPI_IO QSPI_SCLK QSPI_nCS HOSTIO4_P1
RMII_* (7) TL_CLK_TX TL_TX TL_CLK_RX TL_RX I2C_SCL I2C_SDA`.

There is **no** external bus port. `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`
states what was given up: *"the v1 pad budget gives up the scan chain, both UARTs, the PL022
SPI, the JTAG TAP and the PTP 1PPS"*. Note `phc_pps_out` is **OPEN** — so on the ASIC there
is **no physical 1PPS output**, and PTP alignment can only ever be observed by *reading PHC
registers*, which on a standalone board means HOSTIO4 or SWD.

### 1d. HOSTIO4 ⟷ boundary-scan pin conflict (ASIC only)

`pad_table.json` `tap:` gives `tdi = uPAD_HOST_IO_0`, `tdo = uPAD_HOST_IO_1`, `en = uPAD_SE_I`.
So on the die, `HOSTIO4_P1[0]` and `[1]` are **shared with JTAG TDI/TDO** and are switched by
`SE`. From `docs/bscan/BRINGUP.md`:

> `HOSTIO4_P1[0]` — the pad that becomes **TDI** — is a functional bidirectional pad whose
> **output driver is enabled while `SE` is low**. A JTAG master that drives TDI onto it
> before `SE` goes high is fighting a 16 mA output. … the pad model prints `++BUS CONFLICT++`
> on every TDI edge

**Consequence for any ASIC HOSTIO test plan: `SE` must be 0, and boundary scan and HOSTIO4
are mutually exclusive.** Sequencing between them is a bench hazard, not a formality.

---

## 2. Part A — Inventory of existing test material

Legend: **Sim** / **HW** = where it runs. Status is what is *on disk*, not what a doc claims.

### 2a. Executable tests in THIS repo

| # | Item | Path | Access path | Covers | Sim/HW | Status |
|---|---|---|---|---|---|---|
| 1 | `g2_soc_pair` | `verif/g2_soc_pair/` | cocotb AHB BFM into two whole `nanosoc_multicore_soc` dies, cross-wired through PHY pads. Firmware-free — both CPU0s stay boot-gated | Cross-die write, peer aperture, CAM, burst corruption (`a1_incr16`…`a9`), EWR tiedown, TideChart root election | Sim | **PASS** — `results.xml` 15 cases / 0 fail, 2026-08-21 (after fix `4558696`). **But `build/signoff/regress/status.json` still records `"status": "fail"` at 2026-08-18 and has never been refreshed** |
| 2 | `g2_peer_aperture` | `verif/g2_peer_aperture/` | cocotb AHB + APB BFM on a bare TideLink pair (no chiplet wrapper) | Peer aperture crossing, CAM identity control | Sim | **PASS** — 1 case / 0 fail, 2026-08-18. **README names four tests that do not exist**; they were collapsed into `STAGE 1..4` inside one case, so a stage-1 failure masks 2–4 |
| 3 | `chiplet_d2d_decode` (2 benches) | `verif/chiplet_d2d_decode/` | raw self-checking VCS SV, no cocotb | `tb_tx_gate`: link-down TX access → 2-cycle AHB ERROR; `tb_hready_loop`: 4 back-to-back peer writes, no comb loop | Sim | **PASS** 2026-08-18 — **but measured against the pre-08-19 decoder** (`simv` 08-18 15:03, RTL 08-19 12:48). The `NO_HREADY_FIX` negative case is **never run by design** (a zero-delay comb loop cannot be timed out) |
| 4 | Verilator lint | `verif/lint/` (`make lint`) | static, 4 passes over **3 authored modules only**, all else black-boxed | `chiplet_d2d_decode`, `tidechart_shim`, `nanosoc_eth_chiplet`, + a bidirectional self-test | Static | **PASS** 2026-08-18, self-test proven both ways |
| 4b | Full lint / netlist lint | `verif/lint/full/`, `verif/lint/netlist/` | Verilator + HAL over all 590 files; HAL over a gate netlist | Whole-design lint | Static | **UNGATED.** `signoff.yaml`'s own gap list admits *"no signoff run has ever executed it"*; `verif/lint/netlist/` (added 08-24) is in no manifest at all |
| 5 | CDC (Cadence HAL) | `verif/cdc/` (`make cdc`) | `xrun -hal` over integrated `nanosoc_eth_chiplet` | Structural CDC | Static | **FAILS** — `"rc": 2`, *"HAL ABORTED before the rule set completed … halcheck: Total errors = 168"*. Gate is `report`, so it blocks nothing. Separately, the wired HAL takes **no SDC**, so the synchroniser rule class is zero by construction |
| 6 | `elab_strict` | `verif/elab_strict/` (`make elab-strict`) | `xrun -hal` MLTDRV over the dedup'd whole integration | No multiple-driver in authored RTL | Static | **PASS** 2026-08-18, 44 min. Best-hardened gate in the repo — three explicit anti-false-green guards added after it went green on an abort twice |
| 7a | Boundary-scan **RTL** bench | `verif/bscan/run.sh` (`make bscan-sim`) | self-checking VCS on `nanosoc_eth_chiplet_bscan` at its 152 ports | 11 tests: TAP reset, IDCODE, BYPASS, 76-cell chain, SAMPLE, EXTEST, open-drain I²C, `tdo_oe` | Sim | **PASS** 2026-08-20 — `BSCAN_SUMMARY: PASS checks=40136 fails=0 tests=11/11`. **In no CI gate** |
| 7b | Boundary-scan **gate-level** bench | `verif/bscan/run_gate.sh` | same bench on a routed netlist | chain shift in real gates | Sim | **CURRENTLY FAILS TO COMPILE** — `verif/bscan/build_gate/vcs.log` (2026-08-20 10:46) ends `4 errors`, `Error-[UPIMI-E] Undefined port` on `VDD/VDDIO/VSS/VSSIO`; no `simv`, never simulated. Its default netlist path does not exist. Commit `846d2ad` *"7/7 on the routed netlist"* was a past pass that **is not currently reproducible**. No Makefile target, no CI gate |
| 8 | ROM readback GLS (Tier 0) | `make -C ASIC/eth-chiplet gls-rom` | macro model readback vs firmware `.bintxt` | Both boot ROM contents at the reticle | Sim | **PASS**, mutation-proven (`gls-rom-selftest` 12/12) |
| 9 | **Netlist GLS (Tier 1)** | `ASIC/gls-netlist/`, 4 items | gate-level sim: CPU1 XiP-boots from an SST26 QSPI flash model, verifies its image, executes, releases CPU0, CPU0 fetches from mask ROM. 27 graded checks | Real boot on real gates | Sim | `rzg_cc` (**shipping lineage**) **PASS 27/27, FORCES 0**, 2026-08-24; `gdsrun_cc` **PASS 27/27**; `fp1505_cc` **PASS 27/27**; **`full0814_cc` FAIL 10/4** (`eth_rom_port.accessed accesses=0`). **`negative-control` FAILS as required on a blank flash — this gate demonstrably discriminates** |
| 10 | ASIC signoff manifest | `ci/signoff.yaml` (27 stages), `scripts/ci/signoff.py` | physical/EDA gates + `prove`/`lint` meta-gates | DRC/LVS/ERC/padring/ROM/LEC/IR/evidence | Static | ASIC-physical. **`regress` is the ONLY functional-simulation stage.** No stage times anything. `build/signoff/signoff_report.md` reads **`NOT SIGNED OFF`**, is dated 2026-08-18 (~150 commits stale) and covers **12 of 27** stages |
| 10b | `gls-netlist` signoff stage | `ci/signoff.yaml` | blocks | — | Sim | **NEVER EXECUTED under `signoff.py run`** (no `status.json`). It `run:`s all four GLS items but its `check:` grades only `fp1505` — a 08-19 floorplan build, not the shipping `gdsrun-20260823-rzG` |

### 2b. Rig tools (KR260 hardware, `scripts/rig/eth_chiplet/`)

All PS-backdoor except the last two.

| # | Tool | Access path | Covers | Status on disk |
|---|---|---|---|---|
| 11 | `ethmac_probe.py` | PS `/dev/mem` @ `0x4_4000_0000` | ETHMAC register plane, 4 non-trivial reset values | **PASS 2026-08-24, kr260_02** — MODER `0xA000`, IPGT `0x12`, TX_BD_NUM `0x40`, MIIMODER `0x64` all exact |
| 12 | `mdio_scan2.py` | PS backdoor → ETHMAC MDIO regs | Is a PHY answering? (stability + uniqueness + OUI plausibility) | **FAIL 2026-08-24** — MDC correct at ~230 kHz, BUSY asserts/clears, `NVALID` never sets, yet all 32 addresses return incoherent rotating patterns. **Unresolved.** |
| 13 | `mdc_rate.py` | PS backdoor | MDC frequency measurement | Ran — 230 kHz measured |
| 14 | `mac_loopback.py` | PS backdoor, `MODER.LOOPBK` | MAC TX/RX datapath **without** any PHY; doubles as `rmii_ref_clk` detector | **FAIL 2026-08-24** — *"transmit engine never started"*, TX descriptor READY still set after 2 s, `INT_SOURCE = 0`. Diagnosed as **FPGA board/XDC integration fault, not a MAC defect** |
| 15 | `rd21f8_eth.py` | PS backdoor RO | Read-path sticky witness `0x2E0321F8` (marker `0xB5`) | Works |
| 16 | `poll21f8.py`, `capture_readpark.sh` | PS backdoor RO | Read-park wedge signature capture | Ran |
| 17 | `hostio_which_board.py` | **HOSTIO4 write + PS-backdoor readback cross-check** | Which board holds the ribbon; that HOSTIO4 can master AHB | **NEVER RAN its positive arm** — returns 2 with *"NOT IMPLEMENTED HERE: needs REPL access to be granted first"* |
| 18 | **`hostio_adp.py`** | **HOSTIO4 / ADP over RP2350 MicroPython** | Arbitrary AHB read + write from the host | **PASS 2026-08-25 — FIRST WORKING HOSTIO4 LINK.** Bidirectional, cross-checked against the PS backdoor on 3 independent values (`0x2E0321F8→0xb5000001`, `0x2E0321E0→0xad800000`, `0x08000000→0x18003c00`); write proven by write/read-back/restore at IMEM `0x0000_1000` |

### 2c. Silicon regressions (`tidelink/pynq_host/scripts/`) — all PS backdoor

| # | Item | Covers | Status |
|---|---|---|---|
| 19 | `kr260_eth_regress.py` | deploy → link → backdoor → role → sram_fwd → sram_rtt → sram_rev → mailbox → soak → tidechart | **10/10 PASS** on a clean deploy (2026-07-29). **H1 is FIXED** — data plane is now ON by default with `--config-only` to opt out (`:34`, `:212`); `--include-peer-read` stays opt-in |
| 20 | `kr260_sysval.py` | T1 provenance, T2 obs, T3 delivery soak, T6 endurance, **T10 read soak (claims H2 closure)** | Runs; writes JSON evidence. **Asymmetric trust**: a sysval RED is not evidence (ssh-transport artefact relabels `rc=255` as "read mismatch"), a GREEN still is. 108 chunked cross-die readbacks over 9 bring-ups: **zero** genuine read failures |
| 21 | `kr260_eth_bringup.py` / `eth_ss_probe.py` / `kr260_eth_xfer.py` | Link bring-up, boot-ROM aliveness, cross-die transfer | **PASS on silicon** — M1 achieved 2026-07-27, both dies FCSM=4, `cal_done=1`, cross-die write both ways byte-exact |
| 22 | `cov_tidechart_election.py` | TideChart election determinism | **RAN 2026-08-08 and FAILED** — genuine **dual-root** on silicon; both dies `is_root=1`, die_b never adopted die_a's lower claim. Root cause OPEN |

### 2d. Sibling-repo simulation suites

| # | Suite | Access path | Covers | Status |
|---|---|---|---|---|
| 23 | **`nanosoc-multicore-system/cocotb/soc_multicore_hostio4/`** | **HOSTIO4 EXTIO byte-stream → ADP → `debug_m` → top matrix** | 001 enter ADP monitor; 002 ADP read of CPU0 IMEM vs firmware image; 003 ADP write+read-back on **CPU1 DMEM** after HOSTIO releases the CPU1 boot-gate | **PASS** — `results.xml` 1 case / 0 fail, 2026-07-18. In the standard suite list (`cocotb/Makefile:38`) |
| 24 | `nanosoc-multicore-system/cocotb/` (60 suites) | cocotb BFM / firmware images on `nanosoc_multicore_soc` | incl. `soc_ethernet` (5), `soc_eth_ping`, `soc_eth_loopback_ptp`, `soc_ptp` (8), `soc_multicore_dap_swd` (14), `coresight_soc400_*`, `soc_d2d_loopback` (2) | Broadly **PASS**, mostly 2026-07-18. One deliberate red: `ipc_wedge_repro` 1/1 fail |
| 25 | `ethernet-mac-ahb/cocotb/` (8 suites, 163 cases) | cocotb AHB/APB BFM + `cocotbext-eth` MiiSource/MiiSink; a TAP/Unix-socket bridge; a dlopen'd C HAL driver | **Real frame TX/RX through the MAC datapath**, PTP cosim, BD/DMA | **CANNOT DETERMINE** — no `results.xml`, no `.result`, no logs anywhere in that repo. README says the integrated wrapper suite *"is allowed to fail while known issues are resolved"* |
| 26 | `ptp-hardware-clock-ahb/cocotb/` (5 suites, 108 cases) | APB/AHB BFM, C driver | PHC core, regs, AHB wrapper, HA1588 servo loop | **ALL PASS**, `results.xml` + `.result` 2026-07-19 |
| 27 | `ptp-hardware-clock-ahb/uvm/phc/` | UVM APB master agent | 7 tests, block level | **PASS but cold** — logs 2026-04-05, `UVM_ERROR: 0` |
| 28 | `tidelink/cocotb/` (~57 suites, ~980 cases) | AHB/APB BFM, two-die GPIO-PHY pairs | Link, FC, PHY, deskew, autoneg, PTP, TideChart | `make sim_gate` **43 PASS / 2 deliberate XFAIL**, 2026-07-31 |
| 29 | `tidelink/cocotb/eth_tidelink_pair_m1` + `_shape_a` | AHB BFM across a real link into a real `ethernet_ss_ahb` | **Cross-die READ works in sim**, incl. *cold* reads of MAC constant registers across the link | **PASS**, gated (`eth_relay_m1`, `eth_regs_shape_a`) |
| 30 | `tidelink/cocotb/tidechart_tidelink_pair` | two-die TideChart shim | election smoke + datamode | **PASS**, but README concedes **G2**: no TideChart `PKT_EXT` observed crossing the real link, and **G1**: premature election ⇒ dual-root |
| 31 | `tidelink/uvm/tidelink_ptp_chain` | UVM, 3-chiplet chain, 4 `tidelink_top` + 3 PHCs | Cascaded PTP convergence | **NEVER RUN** — elaborates and links clean, `sim_build/` has `compile.log` only, zero test logs |
| 32 | `tidelink/uvm/tidelink_top_system` | UVM two-die pair | 44 tests | **KNOWN FAILING** (`allow_failure: true`) — FC-layer FCSM never leaves state 1 on either die; root-caused to backlog #14b |
| 33 | `tidelink/cocotb/tidelink_top_pair/sim_run_ptp` | two-die PTP short packet | cross-die PTP RX | **4/4 FAIL**, 2026-05-29, **never superseded by a passing two-die PTP run** |

**Inventory count: 36 distinct test/check items** — 13 in-repo, 8 rig tools, 4 silicon
regressions, 11 sibling-repo suite groups. Of these, exactly **two exercise HOSTIO4**
(#18 on hardware, #23 in sim), and **one** (#17) was written for HOSTIO4 and never ran.

### 2e. CI reality — read this before proposing any new gate

Two facts materially change what "add it to CI" means here.

1. **This repository has ZERO registered self-hosted runners** (measured 2026-08-25,
   `gh api …/actions/runners` → `total_count 0`, recorded in
   `.github/workflows/run-report.yml`). `nightly.yml`, `ci-ladder.yml`, `asic-signoff.yml`,
   `asic-gds.yml` and the PDK half of `vendor-guard.yml` **queue forever**. Nightly has been
   pending or cancelled every night since at least 08-20. Every PASS recorded anywhere under
   `build/` was produced by a hand-run on one machine, and `build/` is gitignored.
2. **The only workflow that runs on `pull_request` is `vendor-guard.yml`**, and its own
   run-report records that it *"fails on EVERY run"* at the toolkit-fetch step because the
   pinned toolkit commit was never pushed.

There are also **two overlapping, non-congruent gate ladders**: `ci/signoff.yaml` (27 stages)
and `ci-pipeline.conf` (24 stages). Neither contains a `bscan` stage; only `signoff.yaml` has
`gls-netlist`. And this repo's Makefile has **no `sim`, no `sim_gate`, no `gls`, and no
`design-report` target** — those names belong to the `tidelink` submodule or to
`ASIC/gls-netlist`, not here.

---

## 3. Part B — Access-path matrix

Columns are the five ways to touch the chiplet. **PS** = Zynq PS via `eth_ss_0` (KR260 only).
**HOSTIO4** = 7-wire ADP → `debug_m`. **SWD** = `dap_ss_0_m` (never returned a DPIDR on these
boards). **FW** = code executing on an on-die M0+. **Sim** = testbench only.

| Subsystem | PS backdoor | SWD (DAP) | **HOSTIO4** | Firmware on CPU | Sim-only |
|---|---|---|---|---|---|
| **CPU0 (`network_core`) bootrom/IMEM/DMEM** `0x00/0x10/0x18` | ✅ (via eth-ss local decode) | ✅ | **✅** | ✅ | ✅ |
| **CPU0 halt/step/regfile (PPB `0xA0`)** | ❌ | ✅ *(only path)* | ❌ | ❌ | ✅ |
| **CPU1 (`chip_core`) bootrom/IMEM/DMEM** `0x80/0x90/0x98` | **❌** | ✅ | **✅** | ✅ | ✅ |
| **CPU1 halt/step/regfile (PPB `0xB0`)** | ❌ | ✅ *(only path)* | ❌ | ❌ | ✅ |
| **CPU1 peripherals `cc_periph_0` `0x28`** (UART/timers/WDT) | **❌** | ✅ | **✅** | ✅ | ✅ |
| **CPU boot-gate / remap `0x29`** | ✅ | ✅ | **✅** | ✅ | ✅ |
| **Reset controller `0x2A`, event route `0x2B`** | ✅ | ✅ | **✅** | ✅ | ✅ |
| **`shared_sram_0` `0x2D`** | ✅ | ✅ | **✅** | ✅ | ✅ |
| **`ipc_mailbox_0` `0x23`** | ✅ | ✅ | **✅** | ✅ | ✅ |
| **`ctrl_dbg_group` `0x2C`** (ETC/spinlock/perf/bus_dbg) | ✅ | ✅ | **✅** | ✅ | ✅ |
| **QSPI cfg `0x21` + XIP `0x24`** | ✅ | ✅ | **✅** | ✅ | ✅ |
| **DMA-250/230 cfg `0x20`** | ✅ | ✅ | **✅** | ✅ | ✅ |
| **PHC / PTP registers `0x22`** | ✅ | ✅ | **✅** | ✅ | ✅ |
| **PHC 1PPS output pin** | n/a | n/a | n/a | n/a | ❌ **not bonded on the ASIC** |
| **TideLink D2D config `0x2E` (FCSM, cal, role)** | ✅ | ✅ | **✅** | ✅ | ✅ |
| **TideLink peer aperture `0x2F` (cross-die data)** | ✅ | ✅ | **✅** | ✅ | ✅ |
| **TideChart registers** (behind `0x2E` APB) | ✅ | ✅ | **✅** | ✅ | ✅ |
| **Ethernet MAC registers `0x4000_0000`** | ✅ *(only external path)* | **❌** | **❌** | ✅ | ✅ |
| **Ethernet MDIO engine** (inside ETHMAC) | ✅ | ❌ | ❌ | ✅ | ✅ |
| **eth scratch RX/TX `0x30`/`0x38`** | ✅ | ❌ | ❌ | ✅ | ✅ |
| **eth-ss APB / `eth_ss_sysctrl` REMAP `0x5000_2000`** | ✅ | ✅ *(DAP-only widening)* | **❌** | ✅ | ✅ |
| **PHY (LAN8720 / RMII pins)** | via ETHMAC only | ❌ | ❌ | via ETHMAC only | ✅ |

### What the matrix exposes

- **Nothing at all is reachable ONLY by HOSTIO4 on the KR260**, because the PS backdoor
  covers most of it and SWD covers the rest *in principle*. HOSTIO's KR260 value is that
  it is a **second, genuinely independent** path — which is exactly what made
  `hostio_which_board.py`'s discrimination design possible, and what made today's result
  trustworthy (three values cross-checked against the PS backdoor).
- **Two cells are HOSTIO-or-SWD only, i.e. unreachable from the PS today:**
  `cpu_ss_1_slave` (CPU1 code space) and `cc_periph_0` (CPU1 UART/timers). SWD is dead, so
  **HOSTIO4 is the only working path to CPU1's memory and peripherals right now.**
- **On the ASIC the whole PS column disappears**, so every ✅ in that column that is not also
  ✅ under HOSTIO4 or SWD becomes unreachable. That is: **the Ethernet MAC, the MDIO engine,
  the eth scratch buffers, and the eth-ss REMAP register** — reachable only by firmware.
- **Two cells are SWD-only, forever:** CPU0/CPU1 PPB halt/step/regfile. HOSTIO4 is a bus
  master, not a CoreSight AP; it cannot halt a core. If SWD stays dead, on-die core debug
  stays impossible and must be replaced by firmware-side instrumentation.

---

## 4. Part C — The gap list: what HOSTIO4 uniquely unlocks

### C-1. Things NOTHING can currently test on real silicon

These have no working path today on any vehicle. HOSTIO4 opens each because it is the only
demonstrated host master that reaches CPU1 code space and can run with the CPUs halted.

| # | Gap | Why nothing can test it now | What HOSTIO4 gives |
|---|---|---|---|
| **G1** | **CPU1 (`chip_core`) has never executed anything on silicon** | PS cannot reach `0x9000_0000`; SWD dead; DMA-230 boot copy needs a configured DMA and a source image the PS can't place | HOSTIO4 writes CPU1 IMEM directly and releases the boot-gate at `0x2900_0000`, both in its target list. **Sim-proven end to end** by `soc_multicore_hostio4` test 003, which does exactly this sequence |
| **G2** | **Cross-die IRQ → NVIC → ISR delivery** (`CROSS_DIE_TEST_BACKLOG.md` item 8) | Explicitly parked: *"the HW is wired but delivery is unobservable while both cores are boot-gated — it needs SWD firmware"* | HOSTIO4 is the missing firmware-load path. Load an ISR into CPU0 or CPU1, release, poke the far die's mailbox from the *other* board's host |
| **G3** | **CPU1 UART as a bring-up console** | `cc_periph_0` @ `0x2800_0000` is not in `ETH_SS_M`'s decode; on the ASIC neither UART is bonded anyway | HOSTIO4 reaches `cc_periph_0` directly, and the ADP monitor is itself a console — so HOSTIO becomes the console substitute |
| **G4** | **A debug path that survives a wedged bus** | Every existing silicon tool rides the PS AXI bus, which the runbook documents as hanging with **no timeout** on an undecoded read, JTAG-POR-only recovery | HOSTIO4's monitor is documented as surviving a bus error: *"An undecoded address does NOT hang the monitor: it answers `R!0x00000000` … The console stays fully usable."* This is a **materially better wedge-diagnosis instrument** than anything in the tree |
| **G5** | **PTP/PHC on silicon at all** | PHC regs @ `0x22` *are* PS-reachable, but link PTP has never synchronised on any board and `phc_pps_out` is **not bonded on the ASIC** | HOSTIO4 reads PHC registers on a standalone die — the only observability of PTP that will exist post-silicon |
| **G6** | **Standalone-ASIC bring-up of anything** | See §4 C-2 — the entire PS column vanishes | HOSTIO4 becomes the primary bring-up port |

### C-2. Things testable ONLY via the PS backdoor today — and whether that survives the move to ASIC

**VERIFIED, not assumed. The answer is: the PS backdoor will NOT exist, and this is
structural, not a board-choice.**

Evidence, in order of strength:

1. **The die has no external bus port.** `src/rtl/bscan/pad_table.json` enumerates the
   complete bonded set: 23 signal ports, listed in §1c. There is no AHB, AXI or any wide
   parallel bus among them. Cross-checked against the as-built padring
   (`ASIC/submissions/padring_as_built_rzG_20260823/nanosoc_eth_chiplet_pads_as_built.io`,
   407 instances of which the non-filler set matches the 23 ports exactly) and against the
   synthesis-top module header, which lists the ports and states the pad budget explicitly.
2. **`eth_ss_0` is an internal SoC port.** It is the ethernet subsystem's own AHB slave. On
   the KR260 it is reachable only because the *Vivado wrapper* connects the Zynq
   `M_AXI_HPM0_FPD` high aperture to it inside the PL. The runbook says so:
   *"the PS can reach **only** the SoC's AHB via the `eth_ss_0` backdoor at the HPM0_FPD
   HIGH aperture, PS phys `0x4_0000_0000`"* — a PL-internal connection, not a pin.
3. Therefore **any** ASIC bring-up board, with or without a Zynq beside it, has no way to
   present that port. A neighbouring PS could only reach the die through pins that exist:
   SWD, HOSTIO4, QSPI, I²C, RMII, TL.

**What that costs, concretely.** These are ✅-under-PS-only rows from §3, and on the ASIC they
lose their only external path:

| Capability | On KR260 | On standalone ASIC |
|---|---|---|
| ETHMAC register plane read/write | PS ✅ (`ethmac_probe.py` PASSes) | **firmware only** — HOSTIO4 and SWD both blind to `0x4000_0000` |
| MDIO scan / PHY presence | PS ✅ (currently failing, unresolved) | **firmware only** |
| MAC internal loopback (`MODER.LOOPBK`) | PS ✅ (currently failing) | **firmware only** |
| eth scratch RX/TX buffers `0x30`/`0x38` | PS ✅ | **firmware only** |
| `eth_ss_sysctrl` REMAP `0x5000_2000` | PS ✅ | **SWD only** (DAP-only window widening) — and SWD is dead |

**The strategic reading.** HOSTIO's value is *not* that it replaces the PS backdoor
one-for-one — it does not, and the ethernet blind spot is real. Its value is that:

- it is the **only demonstrated external master that will still exist on the ASIC**, and
- it can **bootstrap firmware into either CPU** and release the gate, and firmware *is* the
  path to everything HOSTIO cannot reach directly.

So on the ASIC the topology becomes **HOSTIO4 → CPU firmware → ethernet**, in two hops,
rather than **PS → ethernet** in one. That two-hop chain has **never been exercised on any
vehicle** and is the single highest-value new test the HOSTIO list should add.

**One caution on hop 1.** The record shows on-die firmware executed on silicon (2026-08-09)
only via the **IMEM-BAKE** route — a synth-init ROM — and that the *backdoor preload* route
failed to execute despite reading back 222/222 words byte-exact. The residual was diagnosed
as *"a preload contents/persistence/timing issue, NOT a fetch-path fault"*. HOSTIO4 preload
is a different master into the same IMEM, so it may or may not hit the same wall. Additionally,
on the KR260 bits the CPU0 mask ROM is the `hello_uart` banner demo which *never sets REMAP
and never jumps to IMEM*, and the REMAP register at `0x5000_2000` is **outside HOSTIO4's
decode**. **This is a real, identified risk to G1/G2 on the FPGA vehicle and should be the
first thing the HOSTIO plan tests.** On the ASIC the boot ROM is the real `eth_rom`, so the
risk may not carry over — but that is unverified.

### C-3. Two things worth stating that are neither of the above

- **`hostio_adp.py` is untracked.** `git status` shows `?? scripts/rig/eth_chiplet/` — the
  entire directory, including today's working client, is outside version control.
- **The bitstream HOSTIO4 was proven on is not identified by anything in this tree.** Both
  in-tree copies of the KR260 Vivado wrapper tie the port off —
  `tidelink/fpga/vivado_ip/nanosoc_eth_chiplet_vivado_wrapper.v:267-269` and the packaged
  IP copy both read `.hostio4_p1_in(7'b0000000), .hostio4_p1_out(), .hostio4_p1_outen()` —
  and neither `kr260-eth-chiplet*` XDC constrains a single HOSTIO4 pin. The only in-tree
  target that exposes them is **HAPS-SX**. `tidelink` HEAD (`5e8bdb5a`) has no uncommitted
  change to either file. **Reproducing today's result therefore depends on an artefact this
  repo cannot name.** Capture the bitstream provenance before the session's context is lost.

---

## 5. Part D — Duplication warning

Do **not** put these in the HOSTIO list; they re-do covered ground.

| Proposed HOSTIO test | Already covered by | Verdict |
|---|---|---|
| Read the boot ROM to prove liveness | `eth_ss_probe.py` (PS, PASS on silicon) **and** already done by `hostio_adp.py` today (`0x08000000 → 0x18003c00`) | **DONE — do not repeat.** Keep only as a one-line smoke step |
| Read `0x2E0321F8` / `0x21E0` stickies | `rd21f8_eth.py`, `poll21f8.py` (PS) — and `hostio_adp.py` already read both today | Keep as a **witness read inside other tests**, not as a test |
| HOSTIO write + read-back to `shared_sram_0` | `hostio_which_board.py` designed it; `hostio_adp.py` already proved write at IMEM `0x1000` | Fold into the board-identification run; not a standalone item |
| TideLink link bring-up over HOSTIO (role strap, cal poll, FCSM) | `kr260_eth_bringup.py` (PS) — **PASS on silicon, M1** | **Duplicate on FPGA.** Worth doing exactly once as an *equivalence* test, then only on the ASIC where it is the sole path |
| Cross-die peer write `0x2F → 0x2D` over HOSTIO | `kr260_eth_xfer.py` + `kr260_eth_regress.py` sram_fwd/rtt/rev — 10/10 PASS | **Duplicate.** One equivalence run only |
| Cross-die read soak over HOSTIO | `kr260_sysval.py` T10 — 108 clean readbacks over 9 bring-ups | **Duplicate on FPGA.** *But* HOSTIO is worth re-running this on a wedge, because of G4 |
| ADP monitor enter / read IMEM / write CPU1 DMEM | `soc_multicore_hostio4` cocotb, **PASS in sim** | Do it once on hardware as the sim↔silicon equivalence check, then stop |
| ETHMAC register probe over HOSTIO | **Impossible** — `0x4000_0000` is outside `debug_m`'s decode | **Do not write this test.** It will DECERR. Write the firmware-mediated version instead |
| Boundary-scan chain shift while HOSTIO is live | Mutually exclusive by construction (`SE` switches the pins) | **Cannot coexist.** Write the *sequencing* rule instead of a test |

---

## 6. Part E — Slot-in recommendation

### E-1. Primary home: `docs/bringup/CROSS_DIE_TEST_BACKLOG.md`

This is the right document and it is already shaped for it. Its table has a
**"PS-side today?"** column, which is precisely the axis HOSTIO changes. Concretely:

1. **Rename that column** `PS-side today?` → `Path` and give it values
   `PS` / `HOSTIO` / `PS+HOSTIO` / `firmware`.
2. **Re-grade the two items it currently blocks**, both of which HOSTIO unblocks:
   - Item **4 (DMA-250 bulk cross-die)** — currently *"Partial — needs firmware or
     PS-replicated DMAC APB writes"*. HOSTIO reaches `dmac_0` @ `0x2000_0000` directly.
   - Item **8 (cross-die IRQ → NVIC → ISR)** — currently *"No — needs firmware (cores
     boot-gated in the PS flow)"*. HOSTIO4 is the firmware-load path. **Un-park it.**
3. **Append a new section, "10. HOSTIO4 items"**, with the C-1 gaps G1–G6 as numbered rows in
   the same format, so they inherit the existing prioritisation discipline.

### E-2. Secondary: `docs/bringup/KR260_BENCH_RUNBOOK.md`

Add a new **§5b "HOSTIO4 — the second debug path"**, sitting immediately after §5 (SWD) and
before §6 (link bring-up), mirroring §5's structure. It must carry:

- the wiring (RP2350 on PMOD3, bank 43) and the note that **bank 43 works where bank 45
  (SWD + LAN8720 MDIO) does not** — a live clue to the MDIO defect;
- the three measured traps from `hostio_adp.py`'s docstring (blocking `sm0.put()`; the
  no-timeout host PIO that parks holding ACK high and pins the SoC FSM in OFFZ; the first
  post-ESC command always rejected);
- the **polarity fix** — the reference PIO driver idles the status nibble active-**low**,
  the shipping RTL (`hostio4_controller_fsm.v:301`) is active-**high**, and used unmodified
  the link *looks simply dead*;
- the hex-digit rule: **digit count sets AHB HSIZE and `0x` resets it**, so `W0x7` is a byte
  write, not a word;
- the bitstream-provenance warning from §C-3.

Also update **§8 (Known state / caveats)** — the line *"SWD works without it"* about the
UART is now misleading, since SWD has never attached on these boards.

### E-3. Update the stale claims in `docs/verification/SYSTEM_VALIDATION_HOLES_REPORT_2026-08-08.md`

The premise the task was given ("only cross-die writes validated; reads/PTP/TideChart/
ethernet/M0-firmware untested") is **partly stale**. Against disk today:

| 08-08 claim | Status now |
|---|---|
| **H1** regression ships data-plane OFF by default | **FIXED 2026-08-10.** Data plane is ON by default; `--config-only` opts out (`kr260_eth_regress.py:34,212`) |
| **H2** no gated cross-die READ on silicon | **LARGELY CLOSED.** `kr260_sysval.py` T10 is a gated read soak; 108 clean chunked readbacks over 9 bring-ups. The "read failures" corpus was **retracted 2026-08-24** as an ssh-transport artefact |
| **H3** ASIC ships ECC bypassed + CRC on + recovery stripped | **PARTLY FIXED.** ECC is re-pointed to `local_overrides/WlinkEccSyndrome.v` (TL-006, flist line 253). **FCSM 0-4 recovery is STILL deps/stripped** (ASIC flist `:315-320` vs FPGA `:322-326`), so CRC-on-at-reset persists too. The a2l CDC self-heal *is* now on the ASIC flist for nodes `_1/_3/_5` |
| **H4** PTP never synchronised on silicon | **STILL TRUE.** No passing two-die PTP result exists in any of the three repos. `tidelink/uvm/tidelink_ptp_chain` has never been run; `tidelink_top_pair/sim_run_ptp` is 4/4 FAIL and never superseded |
| **H5** TideChart never driven at system level | **PARTLY SUPERSEDED, and worse than stated.** The HW gate HAS now run (2026-08-08) and **FAILED**: genuine dual-root on silicon, both dies `is_root=1` |
| **H6** ethernet never driven; no LAN8720 fitted | **SUPERSEDED.** LAN8720s ARE fitted on both boards; ETHMAC register plane is **ALIVE and exact** on kr260_02 (2026-08-24). But MDIO returns incoherent data and the MAC TX engine never starts — diagnosed as an **FPGA XDC/board fault, not a MAC defect** |
| **H6** M0 firmware never executed integrated | **SUPERSEDED.** First on-die user-firmware execution 2026-08-09 via IMEM-BAKE (CPU0 only). Backdoor-*preload* execution still fails |

**Recommendation:** add a dated "Status as of 2026-08-25" block at the top of §0 with the
above, rather than editing the body — the report's value is as a snapshot.

### E-4. Can an existing gate/CI target run any of it?

**Honest answer: one item cleanly, one item already exists, and "CI" currently means
"a hand-run on srv03335" — see §2e. Adding a workflow buys nothing until a runner is
registered; adding a `make` target and a `signoff.yaml` stage still buys something,
because both are hand-runnable and both are recorded.**

| Candidate | Verdict |
|---|---|
| `scripts/ci/signoff.py` / `ci/signoff.yaml` | **Partly.** Its 27 stages are ASIC-physical apart from one — `regress` is the *only* functional-simulation stage, and it already runs `scripts/regress.sh`'s four proofs. A HOSTIO **sim** proof belongs there. A HOSTIO **hardware** test does not: nothing in the manifest touches a board |
| `signoff.py prove` / `signoff.py lint` | **Use these, they are the repo's best idea.** `prove` runs each gate's `check:` against `must_pass`/`must_fail` fixtures; `cmd_lint` refuses a `check:` with no `check_proof:` and refuses an *empty* fixture dir. Any HOSTIO gate added must ship a must-fail fixture, or it will be rejected — correctly |
| `make lint` / `make cdc` / `make elab-strict` | **No.** Static. And `cdc` is currently **failing** (HAL aborted, 168 errors) as a report-only stage, so it is not a place to add anything |
| **`ASIC/gls-netlist`** | **Yes — the one real opportunity.** It already boots both CPUs on the routed gates, 27/27 with `FORCES 0` on the shipping `rzg_cc` item, and its `negative-control` proves it discriminates. Add a **gate-level ADP-over-HOSTIO4 read of the boot ROM** as a 28th check. The sim driver already exists and passes (`soc_multicore_hostio4`) and needs only re-pointing at the gate netlist. **This proves the HOSTIO4 path on the actual tapeout netlist before silicon — the highest-value addition in this document.** Fix two pre-existing defects while you are there: the stage `run:`s four items but grades only `fp1505`, and it has never executed under `signoff.py run` |
| `nanosoc-multicore-system/cocotb` | **Already done, so extend rather than add.** `soc_multicore_hostio4` is in the suite list (`cocotb/Makefile:38`) and passes. Add ADP reads of `phc_0` @ `0x2200_0000`, `cc_periph_0` @ `0x2800_0000` and the `d2d` window @ `0x2E00_0000` — all in `debug_m`'s target list, none in the current three checks. Add a **negative** check too: an ADP access to `0x4000_0000` (ETHMAC) must return the bus-error flag, which pins the §1b asymmetry as a tested property instead of a deduction |
| `verif/bscan` | **Adjacent, and needs a guard — but fix the bench first.** `run_gate.sh` does not currently compile (§2a item 7b) and neither bscan bench is in any CI ladder. Once it builds, add an assertion that HOSTIO4 is quiescent whenever `SE=1`, so the two features cannot be silently co-enabled |
| `kr260_eth_regress.py` | **Yes, as a new non-gating stage** — the cheapest real win. It already has the `record(name, ok, detail, gating)` shape. A `hostio` stage doing one HOSTIO write + PS read-back cross-check turns the two paths into mutual controls on every regression run, and costs one function |
| `scripts/rig/eth_chiplet/` | **Commit it first.** The whole directory is untracked (`?? scripts/rig/eth_chiplet/`), including today's working client. Nothing can be gated on a file that is not in the repo |

---

## 7. What I could not determine

1. **Whether an ASIC bring-up board exists or is specified at all.** There is no
   post-silicon / bring-up-board / socket / load-board document anywhere in `docs/`. The only
   bring-up documentation targets the KR260 FPGA vehicle. `docs/plans/POST_STREAM_TEST_PROCEDURE.md`
   is physical signoff (DRC/LVS/GLS), not silicon bring-up. **The conclusion in §C-2 rests on
   the pad list, which is decisive regardless of what board is built** — but the board itself
   is unplanned, and that is itself a finding.
2. **Which bitstream carries HOSTIO4 on the KR260** — see §C-3. Not answerable from this tree.
3. **Whether HOSTIO4 IMEM preload will execute** where the PS backdoor preload did not. The
   failure was diagnosed as preload persistence/timing, not a fetch-path fault, but no test
   has distinguished master-specific from master-independent causes.
4. **Pass/fail status of the `ethernet-mac-ahb` cocotb suites.** That repo has no
   `results.xml`, no `.result`, no logs. Its own README says the integrated wrapper suite
   *"is allowed to fail"*, which implies red, but there is no artefact either way.
5. **Whether the MDIO defect and the SWD failure share a root cause.** `hostio_which_board.py`
   frames it as *"bank 43 works, which bears on why bank 45 (LAN8720 MDIO, SWD) does not"* —
   a strong hypothesis, but it needs the scope check the rig README specifies (PMOD1.10 should
   carry 50 MHz; PMOD1.4 should show MDC bursts) and that is bench work.
6. **Whether the FCSM 0-4 recovery divergence has a landing plan.** It is still deps-pointed
   on the ASIC flist today; I found the divergence but no dated decision to close it.
7. **Whether the boundary-scan gate bench ever passed on the *shipping* netlist.** Commit
   `846d2ad` claims 7/7 on a routed netlist, but the on-disk residue is a compile failure
   against a *different* netlist (`bscan-probe2/…_gate.v`) and the bench's default path
   (`bscan-probe/…_pnr.v`) does not exist. The claim may be true of a build that is gone.
8. **Whether `ASIC/gls-netlist`'s `flash-selftest` has ever run.** The bench and build
   directory exist; no run log with a verifiable `SELFTEST: OVERALL PASS` was found.

---

## 8. Recommended HOSTIO test list (the actual deliverable to slot in)

Ordered by value-per-effort, with duplication already stripped out.

| # | Test | Proves | Where it runs | Prereq |
|---|---|---|---|---|
| **H-1** | **Gate-level ADP read over HOSTIO4 on the routed netlist** | The HOSTIO4 path works *on the tapeout gates*, before silicon | `ASIC/gls-netlist` (CI) | Re-point the existing passing cocotb driver at the gate netlist |
| **H-2** | HOSTIO write ↔ PS read-back cross-check, both directions, with the NULL arm | Board identity **and** that the two paths are mutually independent controls | KR260 | Finish `hostio_which_board.py`'s positive arm |
| **H-3** | **HOSTIO loads and starts CPU1 firmware** (write `0x9000_0000`, release BOOTGATE `0x2900_0000`, observe via `cc_periph_0` UART or `shared_sram_0`) | **G1** — CPU1 has never executed on silicon | KR260, then ASIC | Sim-proven by `soc_multicore_hostio4` test 003 |
| **H-4** | HOSTIO loads CPU0 firmware; firmware drives ETHMAC | **The two-hop ASIC topology.** Closes the ethernet blind spot | KR260 | Watch the REMAP/`hello_uart` risk in §C-2 |
| **H-5** | Cross-die IRQ → NVIC → ISR, firmware loaded by HOSTIO on both dies | **G2** — backlog item 8, currently parked | KR260 pair | H-3 |
| **H-6** | **Wedge autopsy: induce the read-park wedge, then interrogate over HOSTIO** | **G4** — the first debug path that survives a hung bus | KR260 | Use `capture_readpark.sh` to induce |
| **H-7** | HOSTIO reads `phc_0` on both dies, compares offsets | **G5** — the only PTP observability that will exist on the ASIC (no 1PPS pin) | KR260 pair, then ASIC | — |
| **H-8** | Equivalence run: full `kr260_eth_regress.py` sequence driven over HOSTIO instead of PS | HOSTIO can carry the whole existing regression when the PS is gone | KR260 | Do **once**; do not maintain two copies |
| **H-9** | `SE`/HOSTIO4 mutual-exclusion assertion | Boundary scan and HOSTIO cannot be silently co-enabled | `verif/bscan` (CI) | — |
