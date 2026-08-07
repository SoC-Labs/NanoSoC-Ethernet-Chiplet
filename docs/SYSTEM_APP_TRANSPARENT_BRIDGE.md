# System application — a transparent two-port Ethernet bridge across the TideLink chiplet pair

**Status:** DESIGN. No RTL, firmware, or hardware is produced or run by this
document. It is the application-level "push" test that the V-plan says exists
nowhere: a single full-system artifact that drives the TideLink die-to-die link
*end to end* on the two-board KR260 eth-chiplet pair, and in doing so forces the
currently-untested features to work **together** — bulk + sparse transport, CAM
routing, credit flow-control, PTP across chiplets, and a cross-die interrupt that
actually reaches a far core's ISR.

**The headline.** Two nanoSoC eth-chiplet dies act as one **transparent wire**. A
frame arrives on die_a's Ethernet MAC (INGRESS), is carried across TideLink to
die_b, and leaves die_b's Ethernet MAC (EGRESS). Externally the two-chiplet
system looks like a single transparent bridge / repeater. Made 1588-transparent
(transparent-clock residence-time correction), it is also a legal PTP relay.

This design is deliberately **buildable in stages**, honest about the standing
prerequisites (both cores boot-gated, no proven SWD load path, the cross-die
write wedge, no PHY on the bench), and it reuses the four *already-passing*
co-sim benches (`eth_tidelink_pair`, `_m1`, `_shape_a`, `eth_ptp_chain`) as its
verified substrate rather than starting from a blank sheet.

Grounding read (all verified on disk for this document):
`docs/CROSS_DIE_TEST_BACKLOG.md`, `docs/PEER_APERTURE_PROGRAMMING.md`,
`docs/CROSS_DIE_INTERRUPTS.md`, `docs/CHIPLET_ALIGNMENT.md`,
`docs/CROSS_DIE_WEDGE_ROOTCAUSE.md`, `docs/PROPOSAL_AUTO_ANCHOR_RTL_2026_08_04.md`,
`tidelink/docs/ETHERNET_CHIPLET_INTEGRATION.md`, the four eth co-sim benches under
`tidelink/cocotb/eth_*`, `src/rtl/nanosoc_eth_chiplet.sv`, and the MAC / HA1588 /
PHC register sources under `ethernet-mac-ahb/`, `nanoSoC-refactor/ethernet-subsystem-ahb/`,
and `ptp-hardware-clock-ahb/`.

---

## 0. Load-bearing system facts (the constraints the design must obey)

Every number below is grounded; the design is built *around* these, not against
them.

**Cross-die transport.** The far die is reached through die_a's **peer aperture**
`0x2F00_0000` (16 MB) → TideLink `ahb_sub` → 8-rule address-translator CAM
(`0x2E03_4000`) → XHB500 AHB→AXI → Wlink AXI FC nodes → ribbon → die_b `ahb_mng`
→ die_b matrix. Inbound on the far die reaches **exactly two** targets:
`shared_sram_0 @ 0x2D` and `ipc_mailbox_0 @ 0x23`; everything else DECERRs
(`nanosoc_multicore_soc.yaml:2383-2387`).

**The one-aperture-one-region CAM constraint** (`PEER_APERTURE_PROGRAMMING.md §5`).
The CAM rewrites the *upper byte only*. One 16 MB aperture (`0x2F`) can map to
**one** remote 16 MB region: `0x2F→0x2D` (SRAM) **or** `0x2F→0x23` (mailbox), not
both, and the top matrix is 16/16 full so a second aperture byte is an RTL respin,
not a config tweak. **This single fact shapes the whole bridge datapath** (see §1.3).
CAM program for the bridge is three writes: `BASE_OFFSET=0`, `RULE_0=0x002D2F01`,
`CTRL=1`. The CAM clears on `hresetn` and **no existing test or bring-up script
programs it** — the bridge is the first thing that does.

**Two physically distinct link transports** (`CROSS_DIE_WEDGE_ROOTCAUSE.md`):
1. **BULK / AXI peer-aperture** — `ahb_sub → CAM → XHB500 → Wlink AXI FC nodes
   (AW/W/B/AR/R = `WlinkGenericFCSM`/`_1..4`)`. Carries frame bodies and descriptors.
2. **SPARSE / FC sideband (returner)** — `DOORBELL @0x2E03_2014`, credit-return,
   PTP FC word; rides `FCSM_6` and the returner master, **never** touches the SoC
   matrix. Carries the doorbell/credit/PTP-sync.
   The bridge uses **both at once** — the first time anything does.

**Ethernet subsystem map** (per die, reachable across the link; from
`ethernet_ss_ahb_memory_map.txt`, proven in `eth_tidelink_pair_m1/shape_a`):

| Block | Base | Key registers (offset · reset · meaning) |
|---|---|---|
| `eth_scratch_rx` | `0x3000_0000` (16 KB) | MAC RX frame buffers |
| `eth_scratch_tx` | `0x3800_0000` (16 KB) | MAC TX frame buffers |
| `ethmac` (OpenCores `eth_top`, rel_10/27) | `0x4000_0000` | `MODER@0x00` bit0 TXEN, bit1 RXEN, bit7 LOOPBK, bit10 FULLD (RTL-truth reset **0xA000** — the RDL/generated header say 0xE000, a documented drift; trust the RTL, per `shape_a` finding 3; run value 0xA423); `INT_SOURCE@0x04` W1C (bit0 TXB done, bit2 RXB rcvd, bit1/3 TXE/RXE err, bit4 BUSY=no buffer); `INT_MASK@0x08`; `PACKETLEN@0x18`=0x00400600 (OpenCores meaning: MINFL=0x40=64 B, MAXFL=0x600=1536 B — the RDL field *labels* are swapped); `TX_BD_NUM@0x20`=0x40 (64 TX / 64 RX BDs); **BD table `0x4000_0400..0x07FF`** in the core's 1 KB `bd_ram` (128 × 8 B: TX word0={len[31:16],RD bit15,IRQ bit14,WRAP bit13,PAD,CRC}; RX word0={len[31:16],E bit15,IRQ,WRAP}; word1=payload ptr into `eth_scratch_*`). DMA path `SWAP_DMA_BYTES=1` |
| `HA1588` PTP | `0x4000_1000` | `RTC_CTRL@+0x00` (pulse RTC_RST/TIME_LD — do **not** poke casually); `SCRATCH@+0x04`; **TSU** queues: `TX_TSU_DATA0..3@+0x70..0x7C`, `RX_TSU_DATA0..3`, depth in `TSU_STAT`; entry latches on `ptp_found && eop` |
| `phc_0` (PHC variant) | `0x1A00_0000` (4 KB) | see §1.5 |

**PHC (transparent-clock timebase), `ptp-hardware-clock-ahb`** — 48 b sec + 30 b
ns + 32 b sub-ns counter. `CTRL@0x00` (EN, SET_TIME, CAPTURE); `NS_INCR@0x08` /
`NS_INCR_FRAC@0x0C` (rate knob); `ETH_RX_CAP@0x60` (ingress ts bank);
`ETH_TX_CAP@0x80` (egress ts bank); `SERVO_CTRL@0xA0` bit0 `SRC_SEL` (**0 =
TideLink servo source 0**, 1 = HA1588); `SYNC_INTERVAL@0xA4`; `SERVO_STATUS@0xA8`
bit0 LOCKED. The capture is driven by `ethernet-mac-ahb/src/rtl/ptp_event_detector.v`
(SFD → 24 nibbles → EtherType `0x88F7` match, fires ~960 ns after first bit;
**L2-PTP only**). **Critical constraint:** each ETH capture bank is a
**single-entry, overwrite-on-next, no-FIFO, no-IRQ** register — software must
read the ingress/egress timestamp before the next PTP frame, or serialize PTP
frames. There is **no hardware residence-time or correctionField logic anywhere**
in either repo — the residence subtraction and the correctionField write are
**firmware's job** (see §1.5).

**Interrupts** (`CROSS_DIE_INTERRUPTS.md`). `d2d_irq[7:0] → CPU0 (network_core)
NVIC IRQ[17:10]`; `d2d_irq[15:8] → CPU1 (chip_core) NVIC IRQ[16:9]`. `eth_irq`
(MAC RX/TX done) → CPU0 NVIC. Cross-die doorbell options to wake the **egress
network_core (CPU0)**: returner `DOORBELL → d2d_irq[0] → CPU0 IRQ10` (sideband,
unverified on silicon, payload = free-credit count so 0 credits ⇒ no IRQ);
`packet_committed STATUS[4] → d2d_irq[2] → CPU0 IRQ12`; or the **proven** IPC
mailbox `slot1` doorbell → CPU0 IRQ0 (but the mailbox needs the CAM at `0x23`,
which collides with the `0x2D` bulk rule — see §1.3).

**Standing prerequisites (be honest).**
- Both M0 cores are **boot-gated** in the PS flow; there is **no proven SWD
  firmware-load path in the bitstream**. Everything firmware-based (Stage 1+) is
  gated on solving this first.
- The cross-die **write path intermittently wedges**: the silicon build ships the
  upstream recovery-stripped FCSM on the five AXI data nodes, so one bit-error has
  no recovery → the `B`/`R` beat never returns → PS AXI saturates → wedge (JTAG-POR
  to recover). Today only **A→B, non-sustained is clean**. Fixes in flight:
  `AUTO_ANCHOR_EN` (folds the manual `force_sync R8=0x1C→0x00` deskew re-anchor
  into RTL) and the AXI data-node recovery graft — **neither fully closes the
  sustained-write wedge yet** (`MEMORY: axirec fix doesn't fix silicon wedge`).
- **No Ethernet PHY on the bench**: J21 is consumed by the ribbon; the M2 PMOD
  RMII adapter is not built. A loopback / PS-injected frame source is the runnable
  substitute (§2, Variant L).

---

## 1. Transparent bridge — architecture

### 1.1 The frame path across both dies (text block diagram)

```
        DIE_A  (INGRESS, grandmaster/pinned root)                       DIE_B  (EGRESS, boundary/slave clock)
  ┌──────────────────────────────────────────────┐               ┌──────────────────────────────────────────────┐
  │ Ethernet MAC RX  (OpenCores, 0x4000_0000)     │               │ Ethernet MAC TX  (OpenCores, 0x4000_0000)     │
  │   RX BD ring ── DMA ──► eth_scratch_rx 0x3000  │               │   eth_scratch_tx 0x3800 ──► TX BD ── DMA ──►TX │
  │        │  eth_irq(RXB)                         │               │        ▲                         eth_irq(TXB)  │
  │        ▼                                       │               │        │                                      │
  │  HA1588 RX TSU  ← ptp_event_detector(0x88F7)   │               │  HA1588 TX TSU (egress ts T_out)              │
  │  PHC ETH_RX_CAP 0x1A..0x60  (ingress ts T_in)  │               │  PHC ETH_TX_CAP 0x1A..0x80                    │
  │        │                                       │               │        ▲ residence = T_out − T_in (firmware)  │
  │  ┌─────┴───────────────────────────────┐       │               │  ┌─────┴───────────────────────────────┐      │
  │  │ network_core (CPU0) INGRESS ENGINE  │       │               │  │ network_core (CPU0) EGRESS ENGINE   │      │
  │  │  1. read RX BD + T_in               │       │               │  │  a. doorbell ISR / poll prod-idx    │      │
  │  │  2. BULK-copy body → peer aperture  │       │               │  │  b. read descriptor + body from     │      │
  │  │     0x2F00_0000 (CAM 0x2F→0x2D)     │       │               │  │     local shared_sram 0x2D (landed) │      │
  │  │  3. write descriptor into ring hdr  │       │               │  │  c. patch correctionField += resid  │      │
  │  │  4. SPARSE doorbell (sideband)      │       │               │  │  d. stage → eth_scratch_tx, arm BD  │      │
  │  └──────────────┬──────────────────────┘       │               │  │  e. MODER.TXEN → MAC DMAs it out    │      │
  │   d2d_ahb_m / peer window 0x2F  ▼               │               │  │  f. write consumer-idx back (B→A)   │      │
  │  ┌──────────────┴──────────────────────┐       │               │  └──────────────▲──────────────────────┘      │
  │  │ TideLink die_a                        │      │               │  ┌──────────────┴──────────────────────┐      │
  │  │  ahb_sub ─CAM─► XHB500 ─► AXI FC ═════╪══BULK (AW/W/B/AR/R)══►╪══► ahb_mng ─► d2d_ahb_s ─► matrix ─►   │      │
  │  │  returner ════════════════════════════╪══SPARSE (FCSM_6)═════►╪══► DOORBELL→irq_status→d2d_irq[0]→CPU0 │      │
  │  │  phc servo src0 ══════════════════════╪══PTP FC word═════════►╪══► PHC hw_set/hw_adj (SERVO_CTRL[0]=0) │      │
  │  │  GPIO-PHY  pad_clk/pad_tx[7:0]/rx[7:0]│      │               │  │  GPIO-PHY                            │      │
  │  └──────────────┬────────────────────────┘      │               │  └──────────────┬─────────────────────┘      │
  └─────────────────┼───────────────────────────────┘               └─────────────────┼────────────────────────────┘
                    └───────────── J21 Pi-header ribbon (clk+8 TX, clk+8 RX, I²C) STRAIGHT-THROUGH ─────────────────┘
        chip_core (CPU1) on each die = LINK MANAGER: role strap, cal/FCSM, AUTO_ANCHOR, credit health, PHC grandmaster discipline, link-mgmt IRQ[15:8]
```

Externally: a frame that enters die_a's MAC RX port leaves die_b's MAC TX port,
byte-for-byte (plus the 1588 correctionField update) — a transparent 2-port
bridge. Full duplex adds the mirror-image engine on the other pair of ports.

### 1.2 Firmware split (per die, two cores)

Each die runs the **same** two-core image; a build/strap picks INGRESS vs EGRESS
role per port (a full-duplex bridge runs both engines on each die).

- **`network_core` (CPU0) — the data plane.** INGRESS side: serves `eth_irq`
  (MAC `INT_SOURCE.RXB`), walks the RX BD ring, pulls the frame from
  `eth_scratch_rx`, reads `PHC.ETH_RX_CAP` for `T_in`, then performs the BULK body
  copy + descriptor write + SPARSE doorbell (§1.4). EGRESS side: doorbell ISR (or
  polls the ring producer index), reads descriptor + body out of local
  `shared_sram_0`, applies the residence correction, stages into `eth_scratch_tx`,
  arms a TX BD, sets `MODER.TXEN`, and — for flow control — writes the consumer
  index back to die_a.
- **`chip_core` (CPU1) — link management.** Owns TideLink bring-up (`ROLE_CFG`
  strap, cal poll `SWI_LANE_STATUS[16]`, the `AUTO_ANCHOR`/`force_sync` deskew
  re-anchor), credit/health monitoring (`OBS_FC_CREDIT`, `CREDIT_COUNT`, sticky
  `STATUS`), the PTP grandmaster/servo discipline over `d2d_phc_*` (servo source 0),
  and the link-mgmt IRQs `d2d_irq[15:8]`. Keeping bring-up and health on CPU1
  isolates the data-plane core from link churn.

Rationale for the split: it mirrors the SoC's own `network_core`/`chip_core`
division and the NVIC routing (`eth_irq` + data doorbells land on CPU0; link
IRQs on CPU1), so no interrupt re-plumbing is required.

> **Build caveat to confirm before Stage 1:** the MAC's `int_o` is exposed at the
> subsystem boundary as `eth_irq` but is **not** internally connected to the M0
> NVIC (`ethernet_ss_ahb.sv:422` drives it out; `cpu_0_irq` is a separate top
> input). The chiplet top must route `eth_irq → cpu_0_irq[n]` on a chosen network_core
> vector (no CMSIS IRQn is pre-assigned to Ethernet). Until then the INGRESS
> engine must **poll** `INT_SOURCE.RXB` / the RX BD `E` bit rather than take an
> interrupt — which is exactly the Stage-1 (polling) posture anyway.

### 1.3 Link framing — a ring in the far SRAM (the CAM-constraint-driven design)

Because one `0x2F` aperture reaches only one 16 MB far region, the bridge puts
**both the descriptors and the frame bodies in the same region** — far
`shared_sram_0` at `0x2D` — and reserves the *sideband* transport for the
doorbell. The link "wire format" is therefore a classic producer/consumer **ring
buffer laid out in far SRAM**, written entirely by BULK peer-aperture writes:

```
far shared_sram_0  (die_b view 0x2D00_0000 ; die_a writes it as 0x2F00_0000 via CAM 0x2F→0x2D)
  0x2D00_0000  ring control:  [prod_idx | consumer_idx | ring_depth | flags]   (consumer_idx written back B→A)
  0x2D00_0040  slot[0] descriptor:  word0 = {VALID, byte_count[13:0], msg_class, last}
                                     word1 = seq / frame_id
                                     word2 = T_in.nanoseconds[29:0]     (ingress PTP capture)
                                     word3 = T_in.seconds_lo[31:0]
  0x2D00_0050  slot[0] body:  ceil(byte_count/4) words  (32-bit granular; last-word valid bytes = byte_count mod 4)
  0x2D00_0840  slot[1] ...   (slot stride = 2 KB → fits max 1536 B frame + descriptor; 16 MB / 2 KB ≈ 8192 slots)
```

- **Descriptor = SPARSE-shaped metadata carried on the BULK transport** (4 small
  words per frame), immediately followed by the **BULK body** (up to 384 words).
  This is exactly the "descriptors + frame bodies" split the task calls for, both
  landing in far SRAM by one CAM rule.
- **Word size / MTU / fragmentation.** The AXI transport is 32-bit-word granular
  and today **single-beat** (`eth_tidelink_pair_m1` finding #2 — the XHB AXI→AHB
  bridge does not yet emit AHB bursts). A minimum 64 B frame = 16 words (already
  relayed byte-exact in sim); a max 1536 B frame (`PACKETLEN` max `0x600`) = 384
  words. **No fragmentation is needed** — a whole frame is far smaller than the
  16 MB aperture and the 2 KB slot; the byte-count in word0 carries the exact
  length (AXI cannot infer it) and the last-word valid-byte count. **Endianness is
  load-bearing:** `eth_ptp_chain` proved the OpenCores MAC DMA emits **LSB-of-word
  first** — the stager must match DMA byte order or the frame comes out reversed.
- **Bursts are the throughput unlock** (M1/M2 follow-on): when the XHB AXI→AHB
  path emits `INCR`, a whole frame body relays as one burst instead of 384 singles.

### 1.4 Credit-based flow control (two layers)

1. **Link-level (TideLink FC credits).** The AXI transport is credit-gated;
   `chip_core` watches `OBS_FC_CREDIT @0x2E03_219C`, `CREDIT_COUNT @0x2E03_200C`,
   and `SWI_LANE_STATUS[31:17]` (credit-path status). When AW/W credits run low
   the INGRESS engine must stall issuing body words rather than let the SmartConnect
   saturate (the wedge trigger). This is the first time the credit counters are
   exercised under *sustained* frame traffic (backlog #3 only soaked memory beats).
2. **Application-level (ring producer/consumer).** INGRESS advances `prod_idx`
   only after the descriptor+body are fully written; EGRESS advances `consumer_idx`
   after the MAC has DMA'd the frame out (`INT_SOURCE.TXB`). `prod_idx − consumer_idx
   == ring_depth` ⇒ ring full ⇒ INGRESS applies **back-pressure to its own MAC RX**
   (stop recycling RX BDs / assert `CTRLMODER.TXFLOW` to emit PAUSE on the ingress
   wire). The `consumer_idx` write-back is genuine **die_b→die_a (reverse-direction)
   traffic** — so the bridge exercises the "hard" S→M direction (backlog #2, flagged
   by TideLink as the problematic one) as an intrinsic part of flow control, not a
   bolt-on test.

### 1.5 PTP transparent-clock hook (1588 transparency)

A transparent clock (TC) does not terminate PTP; it forwards event messages and
adds the **residence time** (egress − ingress) to each message's `correctionField`
so downstream slaves see the bridge as delay-free. The bridge implements a
**two-step-style, firmware-computed TC** because the hardware provides timestamps
only:

1. **Ingress capture.** die_a's `ptp_event_detector` fires on the `0x88F7` frame;
   `PHC.ETH_RX_CAP` latches `T_in`. INGRESS reads it and puts it in the descriptor
   (word2/word3). *(Constraint: single-entry bank — read it in the RX ISR before
   the next PTP frame; at PTP rates, ≤ 1 event / 8 ms, this is comfortable.)*
2. **Time base.** For `T_out − T_in` to be meaningful, both PHCs must share a
   timebase. `chip_core` disciplines die_b's PHC from die_a over **servo source 0**
   (`SERVO_CTRL[0]=0`, the port explicitly labelled "TideLink PTP" in `phc.sv`):
   die_a is grandmaster, its time crosses as the SPARSE PTP FC word →
   `hw_set_time`/`hw_adj` on die_b. Judge convergence by PHC-offset (not the
   HA1588 `servo_locked` bit — it reports the wrong servo, per backlog #5).
3. **Egress capture + correction.** die_b transmits; its `ptp_event_detector`
   fires; `PHC.ETH_TX_CAP` latches `T_out`. EGRESS computes `residence = T_out −
   T_in` and **writes `correctionField += residence` into the staged frame in
   `eth_scratch_tx` before setting TXEN** (so the MAC computes FCS over the
   corrected bytes — there is no hardware that mutates a passing frame). Because RX
   and TX use the identical MII detection point, the fixed ~960 ns detector latency
   cancels in the subtraction.
   *(One-step TC — hardware inserts the correction on the fly — is out of scope:
   no such RTL exists. A follow-up-message (two-step) scheme avoids needing T_out
   before transmit, at the cost of an extra message.)*

**Known RTL gap to close for this hook:** `eth_ptp_chain` proved the TSU
**captures** a real looped-back PTP event both TX and RX and that die_a can read
the entry's identity across the link — but the **80-bit timestamp *value*** only
loads into the readable DATA registers on a queue-*pop*, and that pop currently
**stalls the cross-link read** (`eth_ptp_chain` §1.7). Reading the residence value
across the link is blocked on fixing that pop path (or reading the PHC `ETH_*_CAP`
banks locally on each die instead of the HA1588 TSU across the link — the PHC banks
are simple RO registers with no pop). **Recommend the PHC-bank path** for the
bridge: each die reads its *own* PHC capture locally, and only the small residence
scalar (or `T_in`) crosses the link — avoiding the stalling TSU pop entirely.

### 1.6 Exactly which untested features this forces to work *together*

No prior test combines these; the bridge is the first artifact that does, in one
frame's lifetime:

| Feature | Proven so far | This bridge forces |
|---|---|---|
| **BULK** (AXI peer aperture) | one-shot A→B into far SRAM (`_m1`) | sustained, ring-structured, both directions |
| **SPARSE** (FC sideband doorbell) | source-latch observed PS-side | a real doorbell → far-core ISR, concurrent with BULK |
| **CAM routing** | never programmed by any test | `0x2F→0x2D` armed + mutation-checked, per die |
| **Credits** | memory-beat soak (#3) | sustained frame flow, exhaustion + recovery |
| **PTP across chiplets** | loopback-on-one-die capture (`eth_ptp_chain`) | die_a→die_b time transfer + residence correction |
| **Cross-die IRQ → ISR** | source latch only (#8 parked) | doorbell fires the egress network_core's ISR |
| **Reverse (S→M)** | never on silicon (#2) | consumer-index write-back every frame |

**BULK + SPARSE run on two physically distinct FC transports simultaneously** (AXI
nodes vs `FCSM_6`) — the exact concurrency no bench has stressed. That is how one
artifact closes the full-system gap.

---

## 2. Staged bring-up

Each stage is independently valuable, gates the next, and is measured. Stages 0–1
have a **Variant L (loopback / PS-injected frames)** so they run before any PHY
exists; Stage 3 adds the real wire.

### Stage 0 — host-driven "software bridge" over the PS backdoor (runnable soonest, NO firmware)

**Idea.** The two Zynq-MP PS hosts *are* the bridge. No M0 firmware, no boot-gate
release. PS-A pushes a frame through die_a's peer aperture; the CAM lands it in
die_b's `shared_sram_0`; PS-B reads it out and (Variant L) verifies byte-exact,
or (with PHY, later) stages it into `eth_scratch_tx` and emits it. This is a
direct, ~100-line extension of `kr260_eth_xfer.py` (backlog items #1–#3).

**Datapath (all via `0x4_0000_0000 + SoC_addr` backdoor; never bare-link `0x8403`/`0xA400`):**
1. PS-A (or PS-B) programs the CAM on both dies: `0x4_2E03_4000=0`,
   `0x4_2E03_4010=0x002D2F01`, `0x4_2E03_4004=1`. **Mutation check:** disable CTRL
   ⇒ far write DECERRs (proves the rule is load-bearing, per `PEER_APERTURE §8.2`).
2. PS-A injects a frame: write the descriptor + body words to `0x4_2F00_0040+`;
   they cross to die_b `0x2D00_0040+`.
3. PS-B reads back `0x4_2D00_0040+` and checks byte-exact; advances the ring;
   writes `consumer_idx` back to die_a (`0x4_2F00_0000`), exercising B→A.
4. Doorbell (source-only, firmware-free): PS-A rings the mailbox (`slot`,
   `MSG_VALID`) or the returner `DOORBELL`; PS-B reads the far `irq_status
   @0x4_2300_0028` / `DOORBELL_RESPONSE_ACC` to confirm the source latched.

**Proves:** CAM programming on silicon (first ever); the bulk peer-aperture
crossing *sustained and bidirectional*; credit counters move + recover under load;
the doorbell IRQ *source* latches; the whole ring/flow-control protocol end-to-end
in software. **Needs:** link FCSM=4 + a clean deskew anchor (`AUTO_ANCHOR` or the
manual `force_sync R8=0x1C→0x00`); nothing else. **Measured:** throughput
(words/s over the backdoor), frame-loss (byte-exact over N frames), credit
occupancy (`OBS_FC_CREDIT` trend), wedge-free soak length (the honest headline
metric given the wedge). **Honesty:** backdoor `devmem` throughput is low and this
is *not* a line-rate bridge — Stage 0 proves *correctness and protocol*, and is
the safest way to characterise the sustained-write wedge before firmware is on the
core.

### Stage 1 — firmware on `network_core`, one direction

**Idea.** SWD-load the INGRESS engine on die_a's `network_core` and the EGRESS
engine on die_b's `network_core`. die_a services `eth_irq` (Variant L: a
PS-injected pseudo-RX, or MAC internal loopback as in `eth_ptp_chain`), copies the
frame across the peer aperture, writes the descriptor, advances `prod_idx`. die_b
**polls** `prod_idx` (no ISR yet), stages to `eth_scratch_tx`, arms a TX BD, sets
TXEN; the MAC DMAs it out (Variant L: MII loopback back into RX to close the
byte-exact check).

**Proves:** the real firmware datapath — MAC RX/TX BD handling, DMA out of far
SRAM (backlog #4, the DMA-bulk-cross-die item), the ring protocol running on the
cores instead of the PS. **Needs (the gating prerequisite):** a **proven SWD
firmware-load path** and boot-gate release — this does not exist in the bitstream
today and must be solved first. **Measured:** end-to-end latency (`eth_irq` RXB →
egress TXEN), sustained throughput vs Stage 0, frame-loss under a soak.

### Stage 2 — bidirectional + cross-die ISR + PTP transparent clock

**Idea.** Both ports live (full duplex). The doorbell now fires the **egress
network_core's ISR** (closes backlog #8): use the returner `DOORBELL → d2d_irq[0]
→ CPU0 IRQ10` (native SPARSE, distinct transport — the elegant path), with the
proven **mailbox `slot1` → CPU0 IRQ0** as fallback (requires the CAM-flip or a
second-aperture respin, §0). `chip_core` brings up the PHC servo (source 0) so
die_b's clock tracks die_a's; INGRESS stamps `T_in`, EGRESS stamps `T_out` and
patches `correctionField` (§1.5, PHC-bank path).

**Proves:** cross-die IRQ→ISR delivery; PTP across chiplets with real
residence-time correction; and **BULK + SPARSE + CAM + credits + PTP + cross-die
IRQ all interlocked in one frame's lifetime** — the full-system push. **Needs:**
`AUTO_ANCHOR` (or robust `force_sync`) so sustained bidirectional writes don't
wedge; the PHC servo chain wired end-to-end; grandmaster pinned (finding G1 —
don't auto-elect); the residence read on the PHC-bank path (avoids the TSU-pop
stall). **Measured:** **PTP residence-time error** (correctionField vs an
independent reference — a scope on the two MII SFDs, or a commercial 1588 tester),
PHC offset convergence, ISR latency (doorbell → ISR entry), zero frame-loss under
duplex load.

### Stage 3 — real RMII PHY (M2)

**Idea.** Add a PMOD LAN8720-class RMII adapter on die_a's ingress port and die_b's
egress port (`rmii_ref_clk/txd/tx_en/rxd/crs_dv` + MDIO, already re-exported at
`nanosoc_eth_chiplet.sv:100-109`). Real frames enter die_a's wire and leave
die_b's wire: externally a genuine transparent Ethernet bridge/repeater, and a
genuine 1588 transparent clock on a real segment.

**Proves:** the real-wire bridge and the *real* 1588 proof point (Stages 0–2 use
loopback, where a common systematic timestamp offset is undetectable — arch §9
risk 3). **Needs:** the PMOD RMII XDC + `rmii_to_mii` bridge + PHY bring-up
runbook + 50 MHz `ref_clk` PMOD timing closure (the real risk). **Measured:** ping
/ iperf across the bridge; **real-wire residence-time error vs a commercial 1588
tester**; frame-loss at line rate.

---

## 3. Coverage it closes (map to the V-plan gaps)

| V-plan / backlog gap | Where it stood | Closed by |
|---|---|---|
| **Full-system application** (exists nowhere) | no artifact drives the link end-to-end | the bridge itself, Stage 0 up |
| **Cross-die IRQ → NVIC → ISR** (backlog #8, *parked*) | source latch PS-observable only | Stage 2 doorbell → egress `network_core` ISR |
| **PTP across chiplets** (backlog #5, *partial*) | loopback capture on one die (`eth_ptp_chain`) | Stage 2 servo-source-0 discipline + residence correction; Stage 3 real-wire |
| **BULK + SPARSE together** (never) | `_m1` bulk-only, single direction | §1.3/§1.6 — descriptor+body BULK, doorbell SPARSE, concurrent |
| **Reverse direction S→M** (backlog #2, the "hard" one) | never on silicon | §1.4 consumer-index write-back, every frame |
| **CAM programmed** (`PEER_APERTURE` open Q2 — no test does) | reset-state identity only | Stage 0 arms `0x2F→0x2D` + mutation-check |
| **DMA-250 bulk cross-die** (backlog #4, *partial*) | needs firmware/DMA | Stage 1 MAC DMA out of far SRAM |
| **Credit soak + health** (backlog #3) | memory-beat soak only | Stages 0–2 sustained frame flow |

The bridge is the single artifact that turns the "partial / parked / never" column
into "exercised", and it does so incrementally so each closure is independently
measurable.

---

## 4. Alternative / complementary full-system application ideas

Each reuses most of the bridge substrate (peer aperture + CAM + doorbell + PHC),
so they are cheap follow-ons, not restarts.

1. **Cross-die shared-memory RPC / remote-DMA.** die_a writes call args + a
   function id into far `shared_sram_0`, rings the doorbell; die_b executes and
   writes results back (B→A). *Stresses:* peer-aperture BULK + doorbell IRQ +
   reverse direction. *Difficulty:* **low** (it is Stage 0's mechanism,
   generalised — closest to backlog #1). *Compelling:* the minimal general
   substrate every other demo sits on; the natural companion to the bridge and the
   cleanest first "it's a computer talking to a computer" story.

2. **Distributed PTP-synchronised sensor fusion / dual-core signal pipeline.**
   die_a samples a sensor (ADC/GPIO), PHC-timestamps each sample, streams
   timestamped samples to die_b, which fuses/filters against its own timestamped
   stream — correct fusion *requires* the cross-die PTP sync. *Stresses:* PHC servo
   (source 0) + sustained BULK streaming + credits. *Difficulty:* **medium-high**
   (needs the PTP sync rock-solid and a real sample source). *Compelling:* the
   canonical *reason* you put 1588 across a chiplet link — it makes the time-sync
   the point of the demo, not a side feature.

3. **Cross-die packet-processing / filtering pipeline (a "smart bridge").** Parse
   / classify on die_a (`network_core`), forward-or-drop / rewrite / act on die_b —
   a split NIC / inline firewall. *Stresses:* BULK body + SPARSE verdict descriptor
   + IRQ + reverse (stats/counters). *Difficulty:* **medium**. *Compelling:* it is
   the transparent bridge plus one classification step, so it reuses the entire
   datapath and adds an obvious product narrative (offloaded filtering across two
   dies). **Best "next demo" after the bridge.**

4. **Fault-tolerant lock-step / checkpointing pair.** die_a runs a workload and
   periodically checkpoints state into die_b's SRAM over the link; a heartbeat
   (B→A) proves die_b is alive; on die_a fault, die_b resumes from the last
   checkpoint. *Stresses:* sustained BULK + credits + reverse heartbeat + fault IRQ
   — it hammers *sustained link integrity*, which is exactly the wedge risk.
   *Difficulty:* **high** (state-capture firmware + fault injection). *Compelling:*
   the reliability / redundancy story for chiplets, and the harshest torture test
   of the very failure mode (`CROSS_DIE_WEDGE_ROOTCAUSE`) the program most needs to
   characterise.

5. **Load-balancer / NIC-offload split.** die_a = front-end MAC + RX classifier;
   die_b = offload engine (checksum / CRC / crypto / bulk DMA); frames routed to
   die_b by flow, results returned. *Stresses:* BULK + **per-flow CAM routing**
   (multiple rules) + credits + IRQ. *Difficulty:* **medium-high**. *Compelling:*
   the economic "why two chiplets" argument (put the expensive engine on its own
   die) and the first use of *multiple* CAM rules for real routing.

6. **TideChart-routed 3+-chiplet mesh.** Add a third die (or the compute chiplet)
   and route frames by TideChart fabric address across a mesh instead of a
   point-to-point pair. *Stresses:* TideChart election/enumeration + multi-hop
   credits + per-destination CAM. *Difficulty:* **very high** — blocked on the
   TideChart dual-root RTL fix (P4), a third board, and the het address-map
   reconciliation (`CHIPLET_ALIGNMENT` G4/G11). *Compelling:* the real chiplet-mesh
   scalability vision — but the furthest out; keep it as the north star, not the
   next build.

---

## 5. Recommendation

**Build the transparent bridge, Stage 0 first.** It is the highest value per unit
risk:

- **Runnable now.** No firmware, no boot-gate release, no PHY — just a ~100-line
  extension of `kr260_eth_xfer.py` over the proven backdoor, on top of the
  already-passing `eth_tidelink_pair*` sim substrate.
- **It closes the most gaps per artifact.** In one script it programs the CAM for
  the first time, drives sustained bidirectional peer-aperture BULK, moves and
  recovers credits under real load, latches the cross-die doorbell source, and
  runs the full ring/flow-control protocol — turning six "never/partial/parked"
  V-plan rows into "exercised".
- **It de-risks everything downstream.** Stage 0 is also the *safest and most
  instrumented* way to characterise the sustained-write wedge (the program's #1
  hazard) before any firmware sits on a core — you learn exactly how far a soak
  runs, and whether `AUTO_ANCHOR` fixes it, from software you can JTAG-POR out of.

**Sequence.** Stage 0 now → land the **SWD firmware-load path** (the hard
prerequisite) and `AUTO_ANCHOR`, then Stage 1 → wire the PHC servo + fix the TSU
read (PHC-bank path) and pin the grandmaster, then Stage 2 → build the PMOD RMII
adapter for Stage 3. Among the alternatives, **RPC/remote-DMA (#1)** is the natural
companion (it *is* Stage 0's mechanism generalised) and the **smart-bridge packet
filter (#3)** is the best follow-on demo because it reuses the entire bridge
datapath and adds an immediately legible application story. The 3-chiplet mesh
(#6) is the north star, gated on the TideChart fix — plan the address map for it
now (per `CHIPLET_ALIGNMENT §5`), build it later.

---

## Appendix A — key absolute addresses (per die, nanoSoC-internal view)

PS backdoor prefixes each with `0x4_0000_0000` (e.g. peer aperture from PS =
`0x4_2F00_xxxx`, CAM = `0x4_2E03_4xxx`, far SRAM readback = `0x4_2D00_xxxx`).

| Function | Address |
|---|---|
| Peer aperture (BULK egress into far die) | `0x2F00_0000` (16 MB) |
| CAM `BASE_OFFSET` / `CTRL` / `RULE_0` | `0x2E03_4000` / `0x2E03_4004` / `0x2E03_4010` (`=0x002D2F01`) |
| Far inbound targets | `shared_sram_0 @0x2D00_0000`, `ipc_mailbox_0 @0x2300_0000` |
| TideLink `DOORBELL` / `DOORBELL_RESPONSE_ACC` | `0x2E03_2014` / `0x2E03_2024` |
| Mailbox `slot`/`MSG_VALID`/`irq_status`/`irq_enable` | `0x2300_00xx` / `+0x20` / `+0x28` / `+0x2C` |
| Credit/health `CREDIT_COUNT`/`OBS_FC_CREDIT`/`SWI_LANE_STATUS`/`STATUS` | `0x2E03_200C` / `0x2E03_219C` / `0x2E03_2108` (bit16=cal_done) / `0x2E03_2010` (bit4=pkt_committed) |
| `ROLE_CFG` / `PAIR_BASE_ADDR` / deskew `R8` | `0x2E03_2080` / `0x2E03_2000` / `0x2E03_2100` |
| MAC `MODER`/`INT_SOURCE`/`INT_MASK`/`PACKETLEN`/`TX_BD_NUM`/BDs | `0x4000_0000` / `+0x04` / `+0x08` / `+0x18` / `+0x20` / `0x4000_0400..07FF` |
| `eth_scratch_rx` / `eth_scratch_tx` | `0x3000_0000` / `0x3800_0000` (16 KB each) |
| HA1588 `RTC_CTRL`/`SCRATCH`/TSU DATA | `0x4000_1000` / `+0x04` / `+0x70..0x7C` |
| PHC `CTRL`/`ETH_RX_CAP`/`ETH_TX_CAP`/`SERVO_CTRL` | `0x1A00_0000` / `+0x60` / `+0x80` / `+0xA0` (bit0=0 ⇒ TideLink servo src 0) |

## Appendix B — proven sim substrate this design builds on

| Bench | Proven (all PASS on `EPOCH_PROFILE=zero`) | The bridge inherits |
|---|---|---|
| `eth_tidelink_pair` (M0) | frame → die_b `nanosoc_region_sram`, byte-exact | the BULK crossing skeleton |
| `eth_tidelink_pair_m1` (Shape B) | frame → real `ethernet_ss_ahb` matrix → `eth_scratch_rx` | matrix wait-states honoured; single-beat / X-init / burst gaps documented |
| `eth_tidelink_pair_shape_a` | MAC + HA1588 *registers* read/written across the link | far-die register visibility (MODER, TSU, BDs) |
| `eth_ptp_chain` | real L2 PTP frame die_a→die_b→MAC DMA→MII TX→loopback→RX→**HA1588 TSU captured**, identity read back across link | the PTP capture path; the TSU-pop stall gap (§1.5) motivating the PHC-bank residence read |

Common gate caveat: all four pass on the clean skew profile; `EPOCH_PROFILE=
silicon` stalls the S→M peer-window *return* path identically to the unmodified
`pair_v2` reference — a PHY/harness item (`AUTO_ANCHOR` territory), not an eth
blocker, but the reason Stage 0 must gate on a healthy link and measure soak
length honestly.

---

*Design document for SoC Labs, under Arm Academic Access license. Copyright 2026,
SoC Labs (www.soclabs.org). No RTL/firmware/hardware produced or executed.*
