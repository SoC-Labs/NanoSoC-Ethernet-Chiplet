# Enabling on-die M0 firmware in the integrated eth-chiplet — load path, boot-gate release, and first-firmware design

**Status:** DESIGN / HANDOVER. No RTL, firmware, or hardware is produced or run by
this document. It is the design of the *keystone unblock*: getting an on-die
Cortex-M0+ core to execute firmware in the integrated `nanosoc-ethernet-chiplet`
for the first time, which in turn enables cross-die IRQ→ISR delivery, a
burst-capable DMA master for AXI-burst / error-response tests, and real
software-in-the-loop.

**Background (verified this session).** On-die M0 firmware has **never executed**
in the integrated chiplet. Both cores are boot-gated in the PS flow and the shipped
bitstream has no proven firmware-load path; all testing to date is the PS
`0x4_0000_0000` backdoor. Firmware *does* build and run on the SoC-level
`nanosoc-multicore-system` benches (`cocotb/soc_multicore_*`) and on the bare
nanoSoC.

Grounding reads (all verified on disk):
`SYSTEM_APP_TRANSPARENT_BRIDGE.md:97-110`, `CROSS_DIE_INTERRUPTS.md:33-36`,
`../bringup/CROSS_DIE_TEST_BACKLOG.md:26,44-46`,
`tidelink/pynq_host/scripts/coverage/cov_cross_die_isr_plan.md`,
`nanosoc-multicore-system/src/rtl/wrappers/chip_core_remap_ctrl.v`,
`nanosoc-multicore-system/sys_desc/nanosoc_multicore_soc.yaml` (connectivity +
memory map), `nanosoc-multicore-system/cocotb/{soc_multicore_smoke,ipc_wedge_probe}`,
`tidelink/fpga/targets/kr260-eth-chiplet/{kr260_eth_chiplet_tidelink.xdc,tidelink_design.tcl}`,
`nanosoc-multicore-system/cocotb/soc_multicore_dap_swd/swd_sim_bridge/SIM_VS_BOARD.md`,
`nanosoc-multicore-system/firmware/{apps/network_core_swd_hello,bootloader/smoke_remap}/main.c`.

---

## 0. The one fact that reshapes everything: which core, reached by which master

The two on-die cores are **not** symmetric with respect to boot-gating or
backdoor reach. This drives the entire recommendation.

### 0.1 Boot-gate reality (Phase-2a "CPU1-chip-control inversion")

The deployed composition is the *inverted* boot, not "both cores symmetrically
gated":

- **CPU1 = `chip_core` (chip-control MANAGER).** Its boot-gate is **tied HIGH** —
  `cpu1_bootgate` is wired to `1'b1`, so CPU1 is **always released from
  power-on** and cannot be gated. It is the clock/reset master; gating it would
  deadlock the fabric it must drive. Evidence:
  `nanosoc_multicore_soc.yaml:1132-1142`.
- **CPU0 = `network_core` (Ethernet subsystem, the SECONDARY).** It is **held in
  reset at power-on** (`network_core_bootgate = 0`) until the boot-gate bit is
  written. Evidence: `nanosoc_multicore_soc.yaml:1143-1149`;
  `chip_core_remap_ctrl.v:20-37`.

The gate register is `chip_core_remap_ctrl` (SoC `0x2900_0000`), a single
write-1-set 32-bit register:

| bit | name | meaning | value to set |
|---|---|---|---|
| 0 | `REMAP` | CPU1's `0x0` aliases IMEM instead of BOOTROM (CPU1-local) | `0x1` |
| 1 | `CPU1_BOOTGATE` | legacy eth-releases-CPU1 gate — **retired/tied-high in this build** (kept for compat, no longer feeds `chip_core_resetn`) | `0x2` |
| 2 | `CPU0_BOOTGATE` | **release CPU0/eth from reset** (the live gate) | `0x4` |

Evidence: `chip_core_remap_ctrl.v:12-37`; `chip_core_remap_ctrl.yaml:22-54`. Bits
are set-only and cleared **only** by the stable `PORESETn` (external
`sys_sysresetn`), so a release persists across a CPU0 fabric reset
(`chip_core_remap_ctrl.v:39-56`).

**So "release a core" on this silicon means exactly one write: `0x4` →
`0x4_2900_0000`.** This is precisely what the sim harnesses already do
(`ipc_wedge_probe/test_probe.py:162-169`; `soc_multicore_smoke` TB surrogate).

### 0.2 The master-reach map (who can write what)

The PS `0x4_0000_0000` backdoor is physically
`PS M_AXI_HPM0_FPD → AXI SmartConnect → axi_ahblite_bridge → nanosoc_eth_chiplet/eth_ss_0`
with a clean base-strip (`PS 0x4_0000_0000 + A → SoC HADDR A`). Evidence:
`kr260_eth_bringup.py:27-37,68-69`; `tidelink_design.tcl:17-19,127-130,180-181,233`.

The `eth_ss_0` port is the ethernet subsystem's **external AHB slave** —
"external access to local memories and peripherals"
(`ethernet_ss_ahb_rmii.sv:74-84`; `nanosoc_multicore_soc.sv:66-76`). Anything it
addresses **inside** the eth subsystem is served locally; anything else exits via
the `network_core`/`eth_ss_m` initiator onto the top matrix. So the PS backdoor's
reach = eth-ss local memories **+** `eth_ss_m`'s target list.

| Target (SoC addr) | PS backdoor via `eth_ss_0` (`eth_ss_m`) | SWD DAP (`dap_ss_0_m`) | HOSTIO4 (`debug_m`) | Far die (`d2d_m`) |
|---|---|---|---|---|
| CPU0 IMEM `0x1000_0000` (32 KB) | **YES (local)** | yes | yes | **no** |
| CPU0 DMEM `0x1800_0000` (16 KB) | **YES (local)** | yes | yes | no |
| eth-ss sysctrl REMAP `~0x5000_2000` | likely (local periph — **VERIFY**) | yes (via added `0x5000_0000` window) | — | no |
| Boot-gate `chip_core_remap_ctrl` `0x2900_0000` | **YES** | yes | yes | **no (excluded)** |
| `reset_ctrl_0` `0x2A00_0000` | YES | yes | yes | no (excluded) |
| `shared_sram_0` `0x2D00_0000` (8 KB) | **YES** | yes | yes | **yes** |
| `ipc_mailbox_0` `0x2300_0000` | YES | yes | yes | **yes** |
| DMA-230 `dmac_0` regs | YES | yes | yes | no |
| CPU1 IMEM `0x9000_0000` (`cpu_ss_1_slave`) | **NO (only via DMAC or SWD)** | yes | yes | no (excluded) |
| d2d config APB `0x2E03_xxxx` / peer aperture `0x2F` | YES | yes | yes | (is the link) |

Evidence: `eth_ss_m` targets `nanosoc_multicore_soc.yaml:2214-2232` (note
line 2223-2226: `chip_core_remap_0` is *deliberately* in `eth_ss_m` so the
backdoor/CPU0 can write the boot-gate); `dap_ss_0_m` 2283-2328;
`debug_m` (HOSTIO4) 2336-2357; `dmac_0_m` reaches `cpu_ss_1_slave` 2266-2270;
`d2d_m` is **only** `shared_sram_0` + `ipc_mailbox_0` and *explicitly excludes*
`cpu_ss_1_slave`/`eth_ss_slave`/`chip_core_remap_0`/`reset_ctrl_0`
(2374-2387); eth-ss IMEM 32 KB / DMEM 16 KB (`:136-137`); shared_sram 8 KB
(`:173,2149`); mailbox base 0x23 (`:2167`); remap 0x29 (`:2171`); reset_ctrl 0x2A
(`:2172`); shared_sram 0x2D (`:2169`).

**Two conclusions fall straight out of this table:**

1. **CPU0 (`network_core`) is directly preloadable and directly releasable over
   the already-proven PS backdoor.** Its IMEM is *local* to the eth subsystem, its
   boot-gate is `eth_ss_m`-reachable, and its liveness landing zones
   (`shared_sram_0`, DMEM, UART) are all backdoor-observable. No new hardware, no
   SWD, no rebuild.
2. **CPU1 (`chip_core`) is *not* directly backdoor-preloadable** — its IMEM
   (`0x9000_0000`) is only reachable via the on-chip DMA-230 (which the backdoor
   *can* program) or via SWD (unproven, see §1). And it is already released, so
   "release the gate" is a no-op for CPU1.

> **Correction to `cov_cross_die_isr_plan.md:90-91`.** That plan proposes
> "backdoor-write die_b IMEM over the `eth_ss_0` window" to bring up **CPU1** for
> the slot0→CPU1 ISR. Per the reach map, `eth_ss_0`/`eth_ss_m` has **no route to
> `cpu_ss_1_slave`** — a direct backdoor write to CPU1 IMEM DECERRs. CPU1 IMEM is
> reachable from the backdoor only *indirectly* by programming the DMA-230 to copy
> into it (exactly the `soc_multicore_smoke` `test_multicore_smoke_dma_to_chip_core_imem`
> pattern). The lower-lift ISR bring-up is therefore **CPU0 via mailbox slot1**
> (§3.2), not CPU1 via slot0.

---

## 1. Load-path options and recommendation

### (a) SWD-over-PMOD — scaffolded, in the bitstream, but NOT proven on the bench

- **Pins are constrained and wired.** SWD moved **off PMOD4** (PMOD4 is on the
  1.8 V HP banks 64/65 and rejected LVCMOS33, DRC BIVB-1) onto **PMOD2** (3.3 V):
  `SWCLK=J11`, `SWDIO=J10`, `SWD_NPORESETN=K13`. Evidence:
  `kr260_eth_chiplet_tidelink.xdc:49-64`.
- **The DAP is instantiated and connected** in the chiplet top
  (`nanosoc_eth_chiplet.sv:94-103,488-497`) and the KR260 block design wires
  `swclk/swdio_i/swdio_o/swdio_oe/swd_nporesetn` to the SoC
  (`tidelink_design.tcl:57-61,210-214`). The DAP master (`dap_ss_0_m`) has the
  broadest reach of any master, including both cores' IMEM and the PPB debug
  windows (`nanosoc_multicore_soc.yaml:2283-2328`).
- **A probe/flow exists:** OpenOCD/pyOCD, `network_core_run_imem.tcl` (Option A),
  SWD-loadable linker profiles (`eth_stage1_imem_xip`, `eth_stage1_imem_overlay`,
  IMEM at default base `0x1000_0000`, no REMAP —
  `nanosoc_multicore_soc.yaml:2537-2567`), and a ready CPU0 app
  (`network_core_swd_hello`, banner `CPU0-SWD-HELLO-OK`).
- **BUT there is a standing, unresolved bench failure:** *"no DPIDR on any SWD
  adapter"* — the `fix/swd-dap-reset` question. `SIM_VS_BOARD.md` exists precisely
  to localise it (physical-layer vs RTL/protocol) by diffing the identical pyOCD
  procedure in sim vs board. Until that closes, **SWD is not a dependable first
  bring-up path.** HOSTIO4 (`debug_m`), the other broad-reach host master, is
  **not wired on the KR260 bitstream at all** (absent from `tidelink_design.tcl`).

**Verdict:** valuable second path (it is the *only* direct route to CPU1 IMEM and
to per-core PPB/halt-debug), but blocked on a physical-layer bring-up unknown.
Not the first step.

### (b) Backdoor SRAM/IMEM preload via `eth_ss_0` — RECOMMENDED first path

Preload the M0 image + vector table into CPU0's IMEM over the proven
`0x4_0000_0000` backdoor, then release the boot-gate. This is the exact mechanism
already proven in simulation by `soc_multicore_smoke`
(`test_multicore_smoke_dma_to_chip_core_imem` drives a register-direct copy into
IMEM *from the external `eth_ss_0` BFM port* and releases the secondary via
`remap[2]=0x4`) and by `ipc_wedge_probe/test_probe.py:162-169`. It needs **no new
hardware, no SWD, and (for CPU0) no rebuild** — see §4 for the one thing to
confirm (the masked CPU0 bootrom).

**Verdict: lowest-risk path to a first "M0 alive" on silicon. Recommended.**

### (c) Boot-from-flash (QSPI XiP) — the "real" production boot, heaviest lift

The designed production boot is: CPU1 (manager) boots its ROM
(`stage0_bootrom_chip_core`), brings up QSPI XiP, DMA-copies apps from flash into
each core's IMEM, and releases CPU0 (`remap[2]=0x4`)
(`soc_multicore_smoke.py` header; `ipc_wedge_probe/test_probe.py:14-28`). This is
sim-proven with a flash model (`sst26vf064b`) but on the KR260 it needs a
populated/modelled QSPI device and a packed flash image (BOOT table + per-core
entries). More moving parts than (b) and gated on flash availability on the
board. Keep it as the eventual resident-boot story, not the first proof.

### Recommendation

**Path (b), targeting CPU0 (`network_core`), is the recommended first step.** It
rides the one path already proven on this silicon (the PS backdoor), releases the
one core that is actually gated, and lands its liveness signal where the backdoor
can already read it. SWD (a) is the fast-follow for CPU1 and for halt-mode debug,
pending `fix/swd-dap-reset`. Flash (c) is the production end-state.

---

## 2. Boot-gate release sequence (exact writes, correct ordering)

All addresses are PS-physical (`0x4_0000_0000 + SoC addr`). Wedge-safe: every
write below is a *local* die access (never the peer aperture `0x2F..`, never the
bare-link `0x8403`/`0xA400` map).

**Ordering rule: preload and configure BEFORE releasing the gate.** The core
begins fetching the instant `network_core_resetn` deasserts, so IMEM, the vector
table, and any REMAP must be in place first.

```
# --- Step 1: (optional) quiesce / confirm the fabric is clocked --------------
#   The fabric clock comes from CPU1's PRMU; CPU1 is tied-released, so the
#   backdoor already works (bring-up scripts run). No action needed beyond
#   confirming a known RO register reads sane (e.g. TideLink FCSM at
#   0x4_2E03_2108) — proves the die is alive before we release CPU0.

# --- Step 2: PRELOAD CPU0 IMEM with the M0 image + vector table --------------
#   Write the .hex/.bin image word-by-word to CPU0 IMEM (32 KB @ 0x1000_0000):
for word in image:  wr(0x4_1000_0000 + i*4, word)     # local to eth-ss

# --- Step 3: ENSURE CPU0 executes from IMEM (choose per §4 bootrom finding) ---
#   Case A (masked bootrom = smoke_remap-style REMAP+jump): NOTHING to do here;
#          the bootrom sets eth-ss REMAP and jumps to the preloaded IMEM itself.
#   Case B (need explicit REMAP): wr(0x4_5000_2000, 0x1)  # eth-ss sysctrl REMAP
#          (VERIFY the backdoor reaches 0x5000_2000 — it is a local eth-ss
#           periph, NOT a DAP target; see §4.)

# --- Step 4: RELEASE the CPU0 boot-gate (the single keystone write) ----------
wr(0x4_2900_0000, 0x4)          # chip_core_remap_ctrl: CPU0_BOOTGATE = 1
#   write-1-set; only PORESETn clears it, so this survives a CPU0 fabric reset.
#   network_core_resetn deasserts -> CPU0 comes out of reset -> fetches reset
#   vector -> runs.

# --- Step 5: OBSERVE liveness (see §3) ---------------------------------------
rd(0x4_2D00_1F08)  == 0xD00DFEED     # alive signature in shared_sram, OR
#   watch the console UART for the firmware's banner.
```

To **re-gate for a re-load**, the boot-gate cannot be cleared by a register write
(set-only); a `JTAG-POR` / `sys_sysresetn` (staged from `mapstone-dev`) clears
`remap_q` back to 0 and re-gates CPU0. Plan re-load cycles around a POR, exactly
as the reset-controller design intends (`chip_core_remap_ctrl.v:30-32`).

---

## 3. First firmware

### 3.1 The minimal "alive signature" program (Milestone M0-ALIVE)

A tiny Cortex-M0+ image with two independent, backdoor-observable liveness
signals so load-failure and run-failure are distinguishable:

- **Memory beacon (scriptable, wedge-safe):** write a signature to a fixed
  `shared_sram_0` address in a loop, incrementing a heartbeat so the host sees
  motion, not just a static value:
  ```c
  #define SHM   ((volatile uint32_t*)0x2D000000u)   /* CPU0 sees 0x2D.. locally */
  int main(void){
      SHM[0x1F08/4] = 0xD00DFEED;     /* ALIVE_SIG  — "core booted the app"      */
      uint32_t n = 0;
      for(;;){ SHM[0x1F0C/4] = ++n; } /* HEARTBEAT  — "core is still running"    */
  }
  ```
  Host reads `0x4_2D00_1F08` (== `0xD00DFEED`) and watches `0x4_2D00_1F0C`
  advance. `shared_sram_0` is chosen because it is readable by the host backdoor,
  by CPU0, *and* (later) by the far die — it is the same landing zone
  `cov_cross_die_isr_plan.md` uses (`ALIVE_SIG @ 0x2D00_1F08`,
  `RUN_COUNT @ 0x2D00_1F00`, `cov_cross_die_isr_plan.md:59-66,108-111`). Reading
  `shared_sram` locally on the die is wedge-safe (never a peer read).
- **UART banner (human-visible):** the existing `network_core_swd_hello` prints
  `CPU0-SWD-HELLO-OK` over the console UART (`main.c:57-60`), which the KR260 XDC
  routes to BCM20/21 (`kr260_eth_chiplet_tidelink.xdc:41-43`). Polled UART, no
  IRQs, so it runs regardless of vector-table/REMAP subtleties
  (`network_core_swd_hello/main.c:10-15`).

Build with the toolchain that already works: CMake + `gcc-m0plus-le`
(`nanosoc-multicore-system/build/cmake/gcc-m0plus-le`), linker profile
`stage1_imem` (REMAP path, Case A) or `eth_stage1_imem_xip` (IMEM-default base,
Case B) per `nanosoc_multicore_soc.yaml:2443-2452,2551-2555`. `smoke_remap`
(`firmware/bootloader/smoke_remap/main.c`) is the reference for the
preload-and-jump boot if a fresh stage-0 is needed.

### 3.2 The cross-die IRQ→ISR test firmware (Milestone CROSS-DIE-ISR)

Goal (backlog #8, `../bringup/CROSS_DIE_TEST_BACKLOG.md:26`;
`cov_cross_die_isr_plan.md`): the first proof that a cross-die interrupt is
*delivered to a far core's ISR*, not merely that a source bit latched.

**Mailbox mechanics (RTL-verified, `ipc_mailbox_apb_regs.sv:7-13`):**

| offset | register | direction / meaning |
|---|---|---|
| `0x00-0x0C` | Slot 0 data | CPU0→CPU1 payload |
| `0x10-0x1C` | Slot 1 data | **CPU1→CPU0 payload** |
| `0x20` | Slot 0 control | `MSG_VALID`/`MSG_ACK` → raises `cpu1_irq` |
| `0x24` | Slot 1 control | `MSG_VALID`/`MSG_ACK` → **raises `cpu0_irq`** |
| `0x28` | IRQ status | edge-set on `MSG_VALID` rising edge, **R/W1C**, latches regardless of enable |
| `0x2C` | IRQ enable | gates only the NVIC output line, not the status latch |

`slot0 → cpu1_irq → CPU1 NVIC IRQ0`; `slot1 → cpu0_irq → CPU0 NVIC IRQ0`
(`CROSS_DIE_INTERRUPTS.md:19`; `ipc_mailbox_apb_regs.sv:48-66`). Delivery needs
**both** `irq_enable` set **and** the core's NVIC `ISER` bit set
(`cov_cross_die_isr_plan.md:42-49`).

**Design choice — run the ISR on CPU0 via slot1 (aligned with the loadable core).**
Because CPU0 is the backdoor-loadable core (§0.2), target **mailbox slot1 →
CPU0 IRQ0** rather than the plan's slot0→CPU1. The firmware is the mirror of
`cov_die_b_mbox_isr_stub.c`:

```c
/* CPU0 (network_core) on the EGRESS die. */
#define MBOX ((volatile uint32_t*)0x23000000u)    /* ipc_mailbox_0, local view */
#define SHM  ((volatile uint32_t*)0x2D000000u)
void IRQ0_Handler(void){                          /* CPU0 IRQ0 = slot1 line    */
    if (MBOX[0x28/4] & 1u){                        /* IRQ_STATUS[0]            */
        SHM[0x1F04/4] = MBOX[0x10/4];             /* copy SLOT1_DATA0          */
        SHM[0x1F00/4]++;                           /* RUN_COUNT                 */
        MBOX[0x28/4] = 1u;                         /* W1C ack (edge reg)        */
    }
}
int main(void){
    MBOX[0x28/4] = 0xF;                            /* clear stale sources       */
    MBOX[0x2C/4] |= 1u;                            /* irq_enable[0]             */
    *(volatile uint32_t*)0xE000E100u = 1u;         /* NVIC_ISER: enable IRQ0    */
    SHM[0x1F08/4] = 0xD00DFEED;                    /* ALIVE_SIG                 */
    for(;;) __asm volatile("wfi");
}
```

**Firing it (host, wedge-safe):** the far die writes SLOT1 payload + `MSG_VALID`
through its peer aperture with the CAM programmed `0x2F→0x23`
(`RULE_0=0x00232F01`, `../bringup/CROSS_DIE_TEST_BACKLOG.md:19`); the near die reads
`RUN_COUNT @ 0x4_2D00_1F00` **locally** (never a peer read — the delivery verdict
stays wedge-safe, `cov_cross_die_isr_plan.md:118-126`).

**De-risk the NVIC hookup in sim first.** Prototype the mailbox→NVIC→ISR path in
`nanosoc-multicore-system/cocotb/soc_d2d_loopback` (it already masters
`d2d_ahb_s` through the real matrix into the mailbox) before spending a silicon
session (`cov_cross_die_isr_plan.md:99-102`).

**Success ladder** (`cov_cross_die_isr_plan.md:106-116`): (1) liveness
`ALIVE_SIG==0xD00DFEED`, `RUN_COUNT==0`; (2) delivery `RUN_COUNT==1` after
arm+send; (3) re-arm `RUN_COUNT==2` (proves the W1C ack); (4) isolation
(`irq_enable=0` ⇒ source latches but `RUN_COUNT` stays 0).

---

## 4. RTL / bitstream change required (vs. what works on current bits)

### Runs on the CURRENT bitstream — no RTL, no rebuild

- **CPU0 IMEM preload + boot-gate release + liveness read** (§1b, §2, §3.1). Every
  address is in the proven backdoor reach map (§0.2). The boot-gate write is a
  single `0x4 → 0x4_2900_0000`.
- **Cross-die ISR on CPU0 via slot1** (§3.2), once M0-ALIVE passes. The
  mailbox→NVIC wiring already exists in RTL (`CROSS_DIE_INTERRUPTS.md:9-13`).
- **DMA/burst master:** CPU0 programs the DMA-230 (`dmac_0`, in `eth_ss_m`'s
  reach) to drive AXI bursts into the peer aperture for backlog #4 and the
  AXI-burst / error-response tests. No RTL change to *enable* it (the burst
  *throughput* unlock — XHB AXI→AHB emitting `INCR` — is a separate,
  already-tracked RTL item, `SYSTEM_APP_TRANSPARENT_BRIDGE.md:217`).

### The ONE thing to confirm before §1b "just works" (blocking checklist item)

**What bootrom is masked into CPU0/eth in the shipped bitstream?** CPU0 leaves
reset fetching its vector from `0x0` = BOOTROM (the M0+ leaves `VTOR=0`,
`chip_core_remap_ctrl.yaml:18-20`). Two cases:

- **Case A — masked bootrom is `smoke_remap`-style** (reads user MSP/PC from the
  always-mapped IMEM aperture, sets eth-ss REMAP, `BX` into IMEM;
  `smoke_remap/main.c:1-24`). Then §1b works with a **pure IMEM preload + gate
  release** and no REMAP write. This is the sim (`soc_smoke`) configuration.
- **Case B — masked bootrom is `stage0_bootrom` (DMA-boot-from-flash)** or a plain
  0x0-linked stage0. Then either (i) the host must set the eth-ss REMAP
  (`~0x5000_2000`) over the backdoor before releasing — **VERIFY the `eth_ss_0`
  port reaches `0x5000_2000`**; it is a *local* eth-ss APB peripheral (so it
  should, unlike the DAP which needed a widened window,
  `nanosoc_multicore_soc.yaml:2287-2297`), but this has not been exercised — or
  (ii) fall back to a small rebuild that masks `smoke_remap` as the CPU0 bootrom
  (Case A), or bakes the alive app straight into the bitstream via
  `ETH_IMEM_MEM_FPGA_IMG` (`nanosoc_multicore_soc.yaml:140,475`).

This is the single verification that decides "no rebuild" vs "one small rebuild".
Everything else in §1b is confirmed reachable.

### Needs a bitstream/RTL change only if you insist on SWD or on direct CPU1 load

- **SWD path (a):** no RTL change to *enable* (DAP is in the bits) — but the
  `fix/swd-dap-reset` "no DPIDR" issue must be resolved; `SIM_VS_BOARD.md` is the
  diagnostic. If it turns out to be RTL/protocol (not physical), that is a respin.
- **Direct CPU1 IMEM over the backdoor:** not possible on current bits without
  going through the DMA-230 (backdoor programs `dmac_0`, source in
  `shared_sram_0`/flash, dest `0x9000_0000`), because `eth_ss_m`/`d2d_m` have no
  route to `cpu_ss_1_slave` (§0.2). Adding a direct route would be an RTL/security
  change (`nanosoc_multicore_soc.yaml:2377-2380` calls remote code-space writes a
  security-review item).

### Phased validation plan

| Phase | Milestone | Path | Gate / measure | RTL? |
|---|---|---|---|---|
| P0 | **M0-ALIVE** (CPU0) | §1b backdoor preload + `remap[2]=0x4` | `ALIVE_SIG==0xD00DFEED`, heartbeat advances, or UART banner | none (pending §4 bootrom check) |
| P1 | **Boot-gate release characterised** | same | CPU0 runs clean; JTAG-POR re-gates for re-load; no fabric disturbance to the backdoor | none |
| P2 | **CROSS-DIE IRQ→ISR** | §3.2, slot1→CPU0 IRQ0 | ladder rungs 1-4 (`RUN_COUNT` 0→1→2); prototype in `soc_d2d_loopback` first | none |
| P3 | **DMA / burst master** | CPU0 drives `dmac_0` → peer aperture | backlog #4 (bulk cross-die), AXI-burst + DECERR/error-response tests; watch credits `OBS_FC_CREDIT @0x2E03_219C`, wedge-free soak | none to enable (INCR-burst throughput is a separate tracked item) |
| P4 | **CPU1 firmware** (optional) | DMA-copy into `0x9000_0000`, or SWD once fixed | slot0→CPU1 ISR (the original `cov_cross_die_isr_plan` shape) | none (DMA) / SWD-fix dependent |

Sequencing note: P0→P2 all run on the current bits (modulo §4), so the keystone
and its two highest-value follow-ons (ISR delivery, DMA master) do **not** wait on
either the SWD fix or a respin.

---

## 5. Ownership and dependencies

- **Rebuild?** *Probably not* for P0-P3. The decision hinges on the single §4
  bootrom check. If the masked CPU0 bootrom is `smoke_remap`-style (Case A),
  P0-P3 need no rebuild. If not, either a backdoor REMAP write suffices (verify
  `0x5000_2000` reach) or a one-target rebuild masks `smoke_remap` / bakes the
  alive app into `ETH_IMEM_MEM_FPGA_IMG`. Owner: whoever owns the
  `kr260-eth-chiplet` bitstream build (`tidelink/fpga/targets/kr260-eth-chiplet`).
- **Firmware toolchain:** already in place and working — CMake + `gcc-m0plus-le`
  (`nanosoc-multicore-system/build/cmake/gcc-m0plus-le`), existing apps
  (`network_core_swd_hello`, `smoke_remap`, `hello_uart`) and a built
  `stage0_bootrom_chip_core.hex`. The alive app and the CPU0-slot1 ISR stub are
  ~30-50 lines each (§3). Owner: firmware.
- **SWD probe:** an ordinary 3.3 V CMSIS-DAP / ST-Link on PMOD2
  (`SWCLK=J11/SWDIO=J10/SWD_NPORESETN=K13`). Needed only for path (a) / CPU1
  halt-debug; blocked on `fix/swd-dap-reset` ("no DPIDR"), diagnosable via
  `SIM_VS_BOARD.md`. **Not** on the P0 critical path. Owner: debug/bring-up.
- **Host tooling:** a small extension of the existing PS backdoor scripts
  (`kr260_eth_bringup.py`, `kr260_eth_xfer.py`) — add an "IMEM preload + gate
  release + liveness read" mode. Land it behind the per-target descriptor, not as
  a new hard-coded script (`../bringup/CROSS_DIE_TEST_BACKLOG.md:48-52`). Owner: host tooling.
- **Rig:** ATTENDED, one KR260 die for P0/P1; the pair for P2 (cross-die). Stage a
  JTAG-POR from `mapstone-dev`. **Do not** contend with the concurrent tidelink
  rig session. Owner: bench.

---

## Recommended first step (one line)

**On a single KR260 eth-chiplet die: over the proven `0x4_0000_0000` backdoor,
preload the ~30-line alive app into CPU0 IMEM (`0x4_1000_0000`), write `0x4` to
the boot-gate (`0x4_2900_0000`), and read back `0xD00DFEED` at `0x4_2D00_1F08`** —
after first confirming the masked CPU0 bootrom does the REMAP+jump (§4). That
single transaction sequence is the first on-die M0 execution in the integrated
chiplet, and it unlocks P2 (cross-die ISR) and P3 (DMA/burst master) on the same
bits.

---

*Design document for SoC Labs, under Arm Academic Access license. Copyright 2026,
SoC Labs (www.soclabs.org). No RTL/firmware/hardware produced or executed.*
