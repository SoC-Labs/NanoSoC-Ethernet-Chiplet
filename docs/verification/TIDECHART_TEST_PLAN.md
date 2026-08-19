# TideChart two-SoC bench test plan

How to test TideChart functionality between the two live SoCs. PS-side over the
`eth_ss_0` backdoor (TideChart APB at PS `0x4_2E04_0000` = SoC `0x2E04_0000`,
`NANOSOC_D2D_TIDECHART_APB`). Verified against the deployed RTL — where the spec's
register map disagrees with silicon, the RTL (`tidechart_apb_regs.sv` + `src/sw/
tidechart.h`) wins.

## What TideChart is (not what its name suggests)

TideChart is **not** PTP/time-sync (that's the PHC/TideLink servo). It's a **chiplet
identity + routing bootstrap** — USB/SpaceWire-style enumeration for a TideLink mesh:
1. **Root (grandmaster) election** — priority flooding; lowest `{device_class,
   random_id}` wins, self-assigns ID 0.
2. **Enumeration** — root walks the tree, assigns 5-bit IDs, programs routing tables,
   broadcasts `ENUM_DONE`.
3. **Telemetry** — a link-state/congestion agent distributes per-port load over the FC
   sideband.

This build: `tidechart_shim` with `NUM_PORTS=1` facing the single D2D link; APB sliced
to 8 bits so only offsets `0x00–0xFF` are reachable (the `0x100+` subtree regs + IRQC
streams are absent). **Packets only cross once the link is in data mode (FCSM=4)** —
so every inter-die TideChart test requires `kr260_eth_bringup.py --bringup` on both
boards first.

## Register map (authoritative, PS addr = `0x4_2E04_0000 + off`)

| Off | Name | Dir | Key fields |
|---|---|---|---|
| 0x00 | TC_STATUS | RO | [0] election_done, [1] is_root, [2] enum_done, [7:3] local_id, [12:8] total_chiplets |
| 0x04 | TC_BEST_CLAIM | RO | [31:16] winning device_class, [15:0] winning random_id |
| 0x08 | TC_CTRL | RW/W1S | [0] election_start, [1] enum_start, **[2] force_root — decoded but UNUSED**, [3] reset |
| 0x0C | TC_TIMEOUT | RW | [15:0] election_timeout, [31:16] enum_timeout (reset 0x03E8_0100) |
| 0x10 | TC_DEVICE_CLASS | RO | [15:0] = **0x0001 on BOTH dies** (see G1) |
| 0x14/0x18 | TC_ROUTE_WR/RD | WO/RW | route table program / readback (egress, hop) |
| 0x1C | TC_RANDOM_ID | RO | [15:0] own random_id (the election tie-break) |
| 0x20 | TC_UPLINK_PORT | RO | [2:0] uplink port, [7] valid |
| 0x24 | TC_PORT_COUNT | RO | [2:0] = 1 |
| 0x28 | TC_ENUM_STATE | RO | 0 UNENUM / 1 DISCOVERED / 2 ASSIGNED / 3 ACTIVE |
| 0x2C | TC_ERROR | R/W1C | [0] election_timeout, [1] enum_timeout, **[2] dual_root — NEVER set by HW**, [3] cap_timeout |
| 0x74/0x78 | TC_CONG_CTRL/STATUS | RW/RO | telemetry broadcast enable/trigger; rx/tx bcast counts |
| 0x7C | TC_COST_RD | RW | per-dest link cost |

(Full map incl. neighbour/DAP/descriptor regs in `tidechart_apb_regs.sv:170-236`.)

## Test matrix

Prereq for all inter-die tests: **link UP (FCSM=4)** on both boards.

| # | Function | Method | Success |
|---|---|---|---|
| T0 | Register plane alive | read TC_STATUS/DEVICE_CLASS/PORT_COUNT/TIMEOUT both dies | DEVICE_CLASS=0x0001, PORT_COUNT=1, local_id=0x1F, is_root=0 |
| T1 | **Root election** | raise TC_TIMEOUT; write TC_CTRL=0x1 on **both together**; poll TC_STATUS | **exactly one** is_root=1; both election_done=1; TC_BEST_CLAIM identical both sides |
| T2 | Tie-break observability (G1) | read TC_DEVICE_CLASS + TC_RANDOM_ID both | class equal (0x0001), random_ids **differ**; winner = lower random_id |
| T3 | Enumeration | on **root only** write TC_CTRL=0x2; poll both | root {local_id=0, total=2, done, state ACTIVE}; leaf {id=1, done, ACTIVE} |
| T4 | Route table | write TC_ROUTE_RD=peer_id, read back | root→dest1 egress0 hop1; leaf→dest0 egress0(uplink) hop1 |
| T5 | Telemetry | TC_CONG_CTRL enable+pulse; read peer TC_CONG_STATUS/TC_COST_RD | peer rx_bcast_count↑, local tx↑, cost valid |
| T6 | Status IRQ | watch tidechart_irq / TC_STATUS transitions | IRQ pulses on election_done & enum_done edges |
| N1 | enum-on-leaf = no-op | write TC_CTRL=0x2 on leaf | leaf does not self-enumerate/become root |
| N2 | dual/no-root detect | if T1 shows both/neither root | FAIL; diagnose via TC_RANDOM_ID (equal ⇒ collision). **TC_ERROR[2] won't flag it** |
| N3 | reset recovery | TC_CTRL=0x8 both, re-read | local_id→0x1F, routes cleared, T1 repeatable |
| N4 | telemetry pre-enum | enable bcast before T3 | peer count stays 0 (SRC_ID 0x1F dropped) |
| N5 | election-timeout path | run T1 with only ONE die | started die self-elects (single-node), TC_ERROR may show election_timeout |

## Ordered bench runbook

`TC = 0x4_2E04_0000`; root via `/dev/mem` (as the existing tools).
0. **Link up** — `kr260_eth_run.sh bringup` both boards; confirm FCSM=4.
1. **Baseline (T0)** — read `TC+0x00/0x10/0x24`.
2. **Widen timeout (G-TMO)** — write `TC+0x0C = 0x4000_8000` (the 256-cycle default is
   shorter than the D2D round-trip).
3. **Election (T1/T2)** — write `TC+0x08 = 0x1` on **both, as simultaneously as
   possible**; wait ~50 ms; read TC_STATUS both. Pass = exactly one is_root. On fail,
   read TC_RANDOM_ID (equal ⇒ collision) → reset + retry, escalate to G1.
4. **Enumeration (T3/T4)** — on **root only** `TC+0x08 = 0x2`; wait ~20 ms; read both;
   check routes via `TC+0x18`.
5. **Telemetry (T5, optional)** — `TC+0x74=0x1` then `0x3`; read peer `TC+0x78/0x7C`.
6. **Controls** — N1, N3 (reset both, repeat step 3), N5.

## Gaps / prerequisites (what to build or change first)

- **Build a host tool.** No PS-side TideChart tool exists. Write `kr260_tidechart.py`
  modeled on `kr260_eth_xfer.py` (`/dev/mem`, `WINDOW_BASE=0x4_0000_0000`, base
  `0x2E04_0000`); gate on FCSM=4; run election on both dies; diagnose dual-root via
  TC_RANDOM_ID. It touches only the 4 KB in-window register file — no peer-aperture
  wedge risk. Add a mode to `kr260_eth_run.sh`. **Do this behind the target descriptor**
  ([../bringup/CHIPLET_HOST_TOOLING_PLAN.md](../bringup/CHIPLET_HOST_TOOLING_PLAN.md)).
- **G1 — DEVICE_CLASS not strapped per die (the core finding).** Both builds
  instantiate the shim with default `DEVICE_CLASS=0x0001` (`nanosoc_eth_chiplet.sv:796`);
  the `-flip` build differs only in role/CAM. PUF is disabled, so election falls entirely
  to `random_id` (a free-running counter). ⇒ a unique root is *likely* (start-skew) but
  **non-deterministic**, you can't choose the grandmaster, and equal random_ids ⇒ silent
  dual-root. **Deterministic fix:** pass different DEVICE_CLASS to the two builds (die_a
  0x0001 < die_b 0x0002) — a build-time strap; requires rebuilding **both** bitstreams.
- **G-FORCE — `force_root` (TC_CTRL[2]) is decoded but never consumed in RTL.** The
  documented software escape hatch does not work on silicon. Either wire it into the
  election FSM or use the DEVICE_CLASS strap.
- **G-DUALROOT — `TC_ERROR[2]` never asserted.** Infer dual-root from `is_root` on both
  dies, not from TC_ERROR.
- **G-TMO — default election timeout (256 cyc) too short.** Raise TC_TIMEOUT before
  election (step 2). A poke, not a rebuild.
- **G-VERIF — root election + enumeration were never simulated** (VPLAN "Planned"; only
  responder-side + single-node self-election are PASS). T1/T3 are the **first real test
  of the root logic anywhere** — budget for iteration; dump TC_BEST_CLAIM/RANDOM_ID/
  ENUM_STATE every attempt; use N3 reset-and-retry liberally.
- **Out of scope this build:** `0x100+` subtree regs + IRQC streams (APB is 8-bit here);
  PUF entropy path (disabled).

## Bottom line
T0-T6 + N1-N5 are all **reachable PS-side today** once the link is up and a
`kr260_tidechart.py` tool exists. The one thing you cannot do without a rebuild is
**choose which die is grandmaster** (G1/G-FORCE) — for deterministic election, strap
DEVICE_CLASS per die and rebuild both bitstreams.
