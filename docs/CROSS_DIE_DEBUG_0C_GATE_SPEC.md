# 0c — REMOTE_DBG_EN security gate (implementation spec)

The one piece of **new RTL** for cross-die SWD debug. `0b` (add the debug windows to
`d2d_m`'s inbound target list) is sim-PROVEN (`CROSS_DIE_DEBUG_PLAN.md` — CPU1 CPUID
`0x410CC601` read over `d2d_m`), but it must **never ship without `0c`**: the SoC RTL
is symmetric, so opening the debug windows to `d2d_m` exposes *both* dies' cores to
the far die. `0c` gates that inbound path behind a runtime, default-closed,
locally-set enable.

## Security contract
- **Default closed.** `REMOTE_DBG_EN` resets to 0 → inbound `d2d_m` access to the
  debug windows (`0xA000_0000–0xBFFF_FFFF`) DECERRs, exactly as today (pre-`0b`).
- **Locally set only.** The enable lives in `reset_ctrl_0`, which is a target of the
  *local* masters (`eth_ss_m`/`cpu_ss_1_m`/`dap_ss_0_m`) but **not** of `d2d_m` — so
  the far die cannot self-authorize. A local agent (the die's own PS/DAP/CPU) opens
  the gate on the die it wants to expose.
- **Belt-and-braces.** Keep `0b`'s in-SoC default-slave DECERR as the outer boundary;
  the firewall is the runtime policy on top. If the enable mis-wires low, the range
  still DECERRs (fail-safe).

## Piece 1 — the enable bit (`nanosoc_reset_ctrl.v`)
Add a `REMOTE_DBG_EN` R/W bit in a free RAZ slot (`0x004`, the reserved `PMU_CTRL`
slot per the register map), mirroring the existing `LOCKUPRESETEN`-style W/R storage.
Reset value 0. Add an output port:
```verilog
output wire remote_dbg_en   // reset_ctrl 0x004[0]; 0 = closed (reset default)
```
- PS/host address (via the backdoor): `0x4_2A00_0004` — the `dbg_gate` host mode
  writes it (`kr260_eth_xfer.py --mode dbg_gate`).

## Piece 2 — the inbound firewall (`nanosoc_d2d_dbg_firewall.v`, new ~40 lines)
An AHB-Lite pass-through inserted on the `ahb_mng → d2d_ahb_s` path (currently a
direct wire in `nanosoc_eth_chiplet.sv`). It is transparent EXCEPT: an address in
`0xA000_0000–0xBFFF_FFFF` while `remote_dbg_en == 0` is answered with a two-cycle AHB
ERROR and never forwarded to the SoC.
```
module nanosoc_d2d_dbg_firewall (
    input  wire        hclk, hresetn,
    input  wire        remote_dbg_en,
    // upstream: from tidelink ahb_mng (the remote die's transaction)
    input  wire [31:0] up_haddr,  input wire [1:0] up_htrans, input wire up_hwrite,
    input  wire [2:0] up_hsize,   input wire [2:0] up_hburst, input wire [3:0] up_hprot,
    input  wire [31:0] up_hwdata, output wire up_hready, output wire [1:0] up_hresp,
    output wire [31:0] up_hrdata,
    // downstream: to SoC d2d_ahb_s
    output wire [31:0] dn_haddr,  output wire [1:0] dn_htrans, ... (mirror),
    input  wire        dn_hready, input wire [1:0] dn_hresp, input wire [31:0] dn_hrdata
);
```
Behaviour:
- `blocked = (up_haddr[31:28] == 4'hA || up_haddr[31:28] == 4'hB) && !remote_dbg_en`
  (the two 16 MB windows sit at `0xA0`/`0xB0`; gating on `[31:28]` covers both with
  margin — tighten to `[31:24] inside {0xA0,0xB0}` if a neighbouring region must stay
  reachable).
- When `blocked` and an active transfer (`htrans[1]`): drive the standard 2-cycle
  ERROR to `up_*` (mirror `chiplet_d2d_decode`'s error responder / the SoC default
  slave), and force `dn_htrans = IDLE` so nothing reaches the SoC.
- Otherwise: wire `up_* <-> dn_*` straight through (combinational passthrough), so it
  is invisible to the proven SRAM/mailbox paths.

## Piece 3 — wiring (`nanosoc_eth_chiplet.sv` + a new SoC output port)
The enable originates in `reset_ctrl_0` (inside `nanosoc_multicore_soc`) but the
firewall sits in the eth-chiplet wrapper. So:
1. Surface `remote_dbg_en` as a new **output port of `nanosoc_multicore_soc`** (a wire
   tap from `u_reset_ctrl_0.remote_dbg_en`) — a small sys_desc/generator addition.
2. In `nanosoc_eth_chiplet.sv`, insert `nanosoc_d2d_dbg_firewall` on the
   `ahb_mng → d2d_ahb_s` path, with `.remote_dbg_en(soc_remote_dbg_en)` from that new
   SoC port.
(Alternative that avoids the new SoC port: generate the firewall as a SoC-internal
wrapper on the `d2d_ahb_s` passthrough — heavier generator work; not recommended for
the first PR.)

## Validation
- **Sim (extend the proven prototype):** in `soc_d2d_loopback`, gate closed → the
  `test_dbg_halt` CPUID beat DECERRs; gate open → it returns `0x410CC601` (the `0b`
  positive). The firewall sits in the wrapper, so this needs either a TB-level
  firewall on `d2d_ahb_s` or driving through the wrapper — add a small
  `test_dbg_gate` alongside the committed `0b` test.
- **Silicon ladder** (`CROSS_DIE_DEBUG_PLAN.md` §D): gate default-closed → DECERR/no
  hang; `dbg_gate` open on die_b → CPUID reads; halt; resume; re-close.

## Effort / risk
Low logic risk (a simple range-DECERR gate + a stored bit). The one non-mechanical
part is the new `remote_dbg_en` SoC output port (generator/YAML). The firewall
DECERRs by default even if the enable mis-wires low, so the fail-safe is inherent.

## Host side (ready)
`kr260_eth_xfer.py`: `dbg_gate` (die_b writes `REMOTE_DBG_EN`), `dbg_halt`/`dbg_resume`
(die_a). Committed as batch-prep. **Caveat:** the far-core PPB polling crosses the AXI
FC nodes, so a dependable debug session also needs the FCSM-recovery fix
(`CROSS_DIE_WEDGE_ROOTCAUSE.md`).
