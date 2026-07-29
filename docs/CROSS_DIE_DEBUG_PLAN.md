# Cross-die debug over the D2D bridge — one SWD probe debugs both dies

**Goal (deployment):** attach a **single SWD probe to die_a** and debug the Cortex-M0+
cores on **die_b** over the TideLink D2D link — halt / single-step / read CPUID /
read the register file, with no second probe and no far-die firmware running.

This is the SoC-Labs gap **D5 / goal G3** ("one probe halts a core on the far die",
`nanosoc-multicore-system/docs/CHIPLET_INTEGRATION_PLAN.md`). Two read-only
architecture investigations (DAP/CoreSight side + D2D transport side) mapped it end
to end; this is the synthesized plan.

---

## TL;DR

- **The outbound half already exists.** die_a's DAP (`dap_ss_0_m`) is already a
  master on the D2D window, so die_a's probe can *today* read/write die_b's
  `shared_sram_0` and `ipc_mailbox_0` over the link (this is the same path our
  proven cross-die SRAM transfer used).
- **Reaching die_b's core PPB needs three things**, only one of which is real RTL:
  1. a **CAM rule** (software-only register poke) to route the peer aperture to
     die_b's debug window,
  2. a **2-line inbound target-list edit + regen** on die_b to admit the debug
     window from the link (this is the *deliberate* security exclusion),
  3. a **security gate** (new, small RTL) so #2 is safe — because the RTL is
     symmetric, opening it exposes *both* dies.
- **Minimum viable = #1 + #2 + #3 driven by scripted raw AP pokes** from die_a —
  **no new die_a RTL**. A first-class OpenOCD `cortex_m` far-core target is an
  optional ergonomic upgrade (remote APs).
- **One far core at a time** (the CAM keys on the single `0x2F` peer-aperture byte;
  reprogram the rule to switch cores). Simultaneous dual-core remote debug would
  need a second aperture, which the **full 16/16 matrix can't provide** — so
  time-multiplex instead.

---

## What already works today (no changes)

```
die_a probe → SWJ-DP → AHB-AP → dap_ss_0_m → matrix MI12 (0x2E/0x2F → d2d_ahb_m)
   → chiplet_d2d_decode (hsel_peer = haddr[24], i.e. the 0x2F aperture)
   → TideLink ahb_sub → CAM rewrites addr[31:24] → across the link
   → die_b d2d_ahb_s → die_b matrix → { shared_sram_0 0x2D, ipc_mailbox_0 0x23 }
```

- Confirmed: `dap_ss_0_m` targets `d2d` (`nanosoc_multicore_soc.yaml:2326`;
  `multicore_matrix_decode_DAP_SS_0_M.v:548-550` decodes `0x2e000000-0x2fffffff`→MI12).
- die_a's DAP can therefore already master a transaction into the `0x2F` peer
  aperture — the exact path the silicon SRAM transfer used.
- **Not yet reachable:** die_b's core debug (PPB). Two independent gaps block it,
  below.

### Single-die DAP topology (for reference)
One SoC-400 SWJ-DP, **two AHB-APs**: `APSEL=0`→CPU0 debug (`0xA000_0000`),
`APSEL=1`→CPU1 debug (`0xB000_0000`) (`nanosoc_dap_ss.v:93-242`; OpenOCD cfg
`pynq/scripts/openocd/nanosoc_multicore.cfg:10-11`). **`APSEL 2..7` are already
reserved "for future remote-chiplet APs reached over an inter-chiplet link"**
(`nanosoc_dap_ss.v:21`) and currently answer as a NULL responder — i.e. the design
was drawn with this feature in mind. The per-core debug windows
(`network_core_dbg_window` @ `0xA0000000`, `chip_core_dbg_window` @ `0xB0000000`,
16 MB each; `nanosoc_multicore_soc.yaml:2204-2205`) front each core's PPB via
`nanosoc_dbg_ahb_bridge` (`SLVADDR={8'hE0,HADDR[23:0]}`). Halt/step/CPUID/regfile
is pure PPB register access (24-bit offset), so a 16 MB window is sufficient.

---

## The gap and the plan (phased)

### Phase 0 — minimum viable: scripted far-core halt (no die_a RTL)

**(a) CAM rule — software only.** die_a's ADDRXLAT CAM (APB `0x2E034000`, PS-side
`0x4_2E034000`). Program one rule: `match = 0x2F` (normalized), `replace = 0xA0`
(CPU0) or `0xB0` (CPU1), `global_enable = 1`. The CAM replaces `addr[31:24]` and
passes `addr[23:0]` through unchanged (`tl_addr_trans_cam.sv:47-93`), so the full
PPB offset is preserved. This is identical in mechanism to the proven SRAM rule
(`0x2F→0x2D`), just a different replace byte. Add a mode to `kr260_eth_xfer.py`
(e.g. `--mode dbg_route --core {net,chip}`).

**(b) Inbound target-list edit — die_b, 2 lines + regen (THE CRUX).** Today
`d2d_m` inbound reaches only `shared_sram_0` + `ipc_mailbox_0`
(`nanosoc_multicore_soc.yaml:2383-2387`; enforced in
`multicore_matrix_decode_D2D_M.v:203-238`, everything else → DECERR). Add
`network_core_dbg_window` and/or `chip_core_dbg_window` to the `d2d_m` target list
and regenerate the matrix (adds the `0xA0…`/`0xB0…` decode region + grows each
window's arbiter from 1→2 request ports). **This is the deliberately-excluded,
security-sensitive change — must not ship without (c).**

**(c) Security gate — new small RTL (makes (b) safe).** The RTL is symmetric, so
(b) exposes debug on *both* dies; a runtime gate is required (a build-time
asymmetry is impossible). Recommended: add a `REMOTE_DBG_EN` bit in
`nanosoc_reset_ctrl.v` (reuse a free RAZ slot at `0x000`/`0x004`) plus a small AHB
firewall on the inbound `d2d_ahb_s` port that DECERRs any address in the
debug-window range **unless** the bit is set. Resets to 0 (closed/safe). Reachable
only by a *local* master (CPU1/DAP), so the far die cannot self-authorize. Note:
the DAP's own `dbgen`/`spiden` are tied high and gate the *local* DAP only — they
cannot distinguish a `d2d_m`-origin access, so a dedicated inbound gate is needed.

**Host flow (Phase 0):** reuse the existing `halt_via_apreg` / `dhcsr_write_via_apreg`
raw CSW/TAR/DRW sequence (`pynq/scripts/openocd/multicore_smoke_lib.tcl:113-127`)
with `TAR` aimed at the `0x2F` peer aperture (which the CAM maps to die_b's DHCSR).
DHCSR write `DBGKEY|C_HALT|C_DEBUGEN`, poll `S_HALT`, read CPUID, DCRSR/DCRDR for
the regfile. No new OpenOCD target needed.

**Deliverable of Phase 0:** die_a's single probe halts/steps/inspects-registers of
a die_b core (one core at a time). This is G3.

### Phase 1 — ergonomic: native OpenOCD far-core target (die_a RTL)

For a first-class `cortex_m` target instead of scripted pokes: in
`nanosoc_dap_ss.v`, instantiate real `cxdapahbap` at `APSEL=2` (and `=3` for the
second core), each with a `nanosoc_dap_ahb_xlate` whose base maps PPB into the
`0x2F` peer window; widen `nanosoc_dap_ahb_arb` from 2→3/4 masters
(`nanosoc_dap_ahb_arb.v:24-54`); replace the `APSEL≥2` NULL responder with the real
AP mux; give each remote AP a `rombaseaddr` into the peer window for ROM discovery.
OpenOCD then adds `target create nanosoc.cpu2 cortex_m -dap nanosoc.dap -ap-num 2
-defer-examine` (the cfg already anticipates this at `nanosoc_multicore.cfg:12`).

### Phase 2 — full far-core memory/flash debug (biggest, security decision)

Halt/step/regfile (Phase 0) do **not** need far-die *memory* access. To let the
remote AP inspect memory, download code, or set software breakpoints, die_b's
`d2d_m` must additionally reach `eth_ss_slave`/`cpu_ss_1_slave` (IMEM/DMEM) — the
CPU code space deliberately excluded pending a security review
(`nanosoc_multicore_soc.yaml:2377-2380`; gap D4). Gate it with the same
`REMOTE_DBG_EN` mechanism. Defer until Phase 0/1 prove the concept.

---

## Constraints & caveats (from the RTL)

- **One core at a time.** CAM keys on `addr[31:24]`; the peer aperture is a single
  `0x2F` byte, so a rule maps to *one* debug window. Switch cores by reprogramming
  `replace` (0xA0↔0xB0) — software, instant. Simultaneous dual-core needs a second
  peer aperture; the **matrix is full at 16/16 slots** (`D2D_PORT.md §2`) so that
  would displace an existing target — avoid; time-multiplex instead.
- **`hmastlock` is dropped** across the link (tied 0 into the peer XHB bridge,
  `tidelink_top.sv:1995`). Cortex-M0 DAP debug uses single non-locked 32-bit
  accesses, so this is not a functional blocker — but any locked/exclusive debug
  sequence would silently lose atomicity.
- **High latency.** Debug is poll-heavy (DHCSR); every access is a full die-to-die
  round trip. Functional (wait-states are honoured over the link) but slow — expect
  low debug throughput.
- **Transaction shape is carried unchanged.** The proven TideLink data path
  transports `haddr`(32b)/`hsize`/`hburst`/`hprot`/`hwrite`/`hwdata`/`htrans` and
  honours wait-states — a PPB debug access is the same shape as the SRAM write
  already working on silicon. No transport blocker for basic remote debug.
- **Unverified:** that die_b's `nanosoc_dbg_ahb_bridge` + core authentication accept
  a `d2d_m`-origin debug access identically to a `dap_ss_0_m`-origin one. The
  transport delivers a byte-identical AHB transaction to the same target port, so it
  should — but this wants a directed sim/bench check (the `soc_d2d_loopback` env only
  exercises SRAM/mailbox inbound today).

---

## Effort ranking

| # | Change | Where | Effort | Risk |
|---|--------|-------|--------|------|
| 0a | CAM rule `0x2F→0xA0/0xB0` | die_a ADDRXLAT `0x2E034000` — **software** | Trivial | Low |
| 0b | Add dbg window(s) to `d2d_m` targets | `nanosoc_multicore_soc.yaml:2385` + regen | Low | **High** (unsafe без 0c) |
| 0c | `REMOTE_DBG_EN` gate + inbound firewall | `nanosoc_reset_ctrl.v` + new RTL + regen | Medium | Medium |
| 1 | Remote AHB-AP(s) + arbiter widen | `nanosoc_dap_ss.v`, `nanosoc_dap_ahb_arb.v` | Medium | Medium |
| 2 | Far-core memory/flash (code-space inbound) | `d2d_m` targets + security | High | High |

**Recommended first step:** implement 0a in `kr260_eth_xfer.py` (pure software — a
`dbg_route` mode) and prototype the Phase-0 scripted halt in a sim/loopback env
*before* touching the matrix, to de-risk the CoreSight-accepts-inbound question.
Then 0b+0c together (never 0b alone).

---

## References
- DAP/CoreSight: `nanosoc_dap_ss.v`, `nanosoc_swj_dap_ss.v`, `nanosoc_dap_ahb_xlate.v`,
  `nanosoc_dbg_ahb_bridge.v`, `pynq/scripts/openocd/nanosoc_multicore.cfg`,
  `.../multicore_smoke_lib.tcl`, `docs/ARCHITECTURE.md §CoreSight`.
- Transport: `nanosoc_multicore_soc.yaml` (`:2283-2328` outbound, `:2372-2387` inbound),
  `build_soc/rtl/.../multicore_matrix_decode_{DAP_SS_0_M,D2D_M}.v`,
  `src/rtl/chiplet_d2d_decode.sv`, `src/rtl/nanosoc_eth_chiplet.sv`,
  `tidelink/src/rtl/tl_addr_trans_cam.sv`, `tidelink_top.sv:2161-2196`,
  `nanosoc_arch_tech/rtl/src/regions/reset_ctrl/nanosoc_reset_ctrl.v`.
- Tracking: gap **D5** / goal **G3** (and D4 for Phase 2) in
  `nanosoc-multicore-system/docs/CHIPLET_INTEGRATION_PLAN.md`.

---

## Implementation roadmap (2026-07-29) — first PR

Deep-dive established this is buildable, and the risky parts are already retired by
existing sims.

### Prototype in SIMULATION first (no bitstream, no silicon)
`nanosoc-multicore-system/cocotb/soc_d2d_loopback` masters `d2d_ahb_s` through the
*real* SoC matrix and already has a single-beat inbound driver (`_d2d_s_beat`,
`test_soc_d2d_loopback.py:69`) + a DECERR-confinement test (`:257-272`).
- **Proves the negative TODAY, zero changes:** a beat to `0xA000EDF0` DECERRs (the
  `d2d_m` decode only routes `0x23`+`0x2D`, `multicore_matrix_decode_D2D_M.v:203-212`).
- **Proves the positive** after the 0b YAML edit + a local `make soc`: `_d2d_s_beat`
  DHCSR write `DBGKEY|C_HALT|C_DEBUGEN` (`0xA05F0003`) → poll `S_HALT` → CPUID
  `0x410CC200`. The dbg bridge does **no origin check** (`nanosoc_dbg_ahb_bridge.v:106-165`)
  and `coresight_soc400_dap_to_core` already halts a core via this exact bridge, so
  the CoreSight-accepts-inbound risk is essentially retired.
- Full-fidelity dress rehearsal (CAM+PHY+far SoC): `verif/g2_soc_pair` with the CAM
  rule changed `0x2F→0x2D` → `0x2F→0xA0` (`test_g2_soc_pair.py:79`).

### The RTL diff (never land 0b without 0c)
- **0b (2 lines + regen):** add `network_core_dbg_window` + `chip_core_dbg_window`
  to the `d2d_m` targets in `nanosoc_multicore_soc.yaml:2383-2387`; `make soc`
  regenerates the matrix (adds `0xA0…`/`0xB0…` decode + grows each window's arbiter
  1→2). Both windows already exist as `dap_ss_0_m` targets, so this only adds edges.
- **0c (the real new RTL — the security gate):** a `REMOTE_DBG_EN` bit in
  `nanosoc_reset_ctrl.v` (free RAZ slot `0x004`, reset 0 = closed; reachable only by
  a *local* master, so the far die can't self-authorize) + a ~40-line inbound
  firewall `nanosoc_d2d_dbg_firewall.v` on the `ahb_mng→d2d_ahb_s` path in
  `nanosoc_eth_chiplet.sv:642-651` that DECERRs `0xA0000000-0xBFFFFFFF` unless the
  bit is set. **Wiring cost to flag:** `REMOTE_DBG_EN` originates in the SoC but the
  firewall is in the wrapper → needs a new SoC output port (a generator/YAML change).

### Host tool (pure /dev/mem — no OpenOCD for the scripted path)
New `kr260_eth_xfer.py --mode dbg_halt --core {net,chip}`, reusing `program_cam`
+ `rd/wr`. PPB regs via the peer aperture (die_a PS = `0x4_0000_0000 + SoC_addr`;
CAM `0x2F→0xA0` CPU0 / `0x2F→0xB0` CPU1; low 24 bits pass through):

| PPB reg | SoC (CPU0) | die_a PS-side |
|---|---|---|
| DHCSR | `0xA000EDF0` | `0x4_2F00_EDF0` |
| CPUID | `0xA000ED00` | `0x4_2F00_ED00` |
| DCRSR/DCRDR | `0xA000EDF4/8` | `0x4_2F00_EDF4/8` |

Sequence: die_b set `REMOTE_DBG_EN` (`wr 0x4_2A00_0004 = 1`) → die_a `program_cam`
`RULE_0=(0xA0<<16)|(0x2F<<8)|1` → write DHCSR halt → poll `S_HALT` → read CPUID →
regfile via DCRSR/DCRDR. One core per CAM rule (reprogram `0xA0↔0xB0` to switch).

### Silicon validation ladder + regression hook
1. gate default-closed (DECERR, no hang) → 2. `REMOTE_DBG_EN=1`, CPUID reads
`0x410CC200` → 3. halt (S_HALT=1) → 4. resume → 5. isolation (halt CPU1, CPU0 runs)
→ 6. gate re-close. Add `t_dbg_halt` to `kr260_eth_regress.py` after `t_mailbox`,
gating once stable.

### 🔴 Caveat linking to the read-reliability finding (2026-07-29)
Cross-die debug is **poll-heavy — every DHCSR check is a peer READ over the link.**
The regression's repeatability run found the **peer read-round-trip intermittently
hangs and wedges the PS** (writes are reliable; reads are not — see
`docs/OVERNIGHT_WORKLOG.md`). **A poll-based far-core debug session would inherit
that intermittent wedge**, and a hung debug poll wedges the whole board. So the
read-return reliability must be root-caused/fixed (the sim says reads cross via the
`local_overrides/tidelink_top.sv` read-pipe fix; confirm that fix is robust in the
FPGA build) **before** cross-die debug is dependable (ROOT-CAUSED 2026-07-29 —
the silicon ships recovery-stripped FCSM on the AXI data nodes; see
[CROSS_DIE_WEDGE_ROOTCAUSE.md](CROSS_DIE_WEDGE_ROOTCAUSE.md)). Treat read reliability as a
prerequisite of G3, not just a nice-to-have.
