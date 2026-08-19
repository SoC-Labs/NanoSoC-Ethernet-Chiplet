# Cross-die interrupts over TideLink — mechanisms to a far-die core's ISR

What we have for sending an interrupt from one die to a core on the other die.
Verified against the deployed RTL (`src/rtl/nanosoc_eth_chiplet.sv` + the SoC
`nanosoc_multicore_soc.sv`). All far-die IRQ *source* registers are readable
PS-side over the eth_ss_0 backdoor (`0x4_0000_0000 + SoC_addr`); firing an actual
ISR needs firmware (both cores are boot-gated in the PS flow).

## The `d2d_irq[15:0]` → NVIC map

Assembled at `nanosoc_eth_chiplet.sv:841-855`, split in the SoC: **`d2d_irq[7:0]` →
CPU0 (network_core) NVIC IRQ[17:10]**, **`d2d_irq[15:8]` → CPU1 (chip_core) NVIC
IRQ[16:9]**. No mask between source and NVIC — only each core's ISER (firmware).

## Every cross-die interrupt mechanism

| # | Mechanism | die_a action | crosses link → far-die source reg | → NVIC | Notes |
|---|---|---|---|---|---|
| **1** | **IPC mailbox doorbell** | write mailbox slot + `MSG_VALID` (via peer aperture, CAM `0x2F→0x23`) | `ipc_mailbox_0` `irq_status @ 0x2300_0028` bit latches on the MSG_VALID edge | **CPU1 IRQ0** (slot0) / CPU0 IRQ0 (slot1) | **The general-purpose cross-die IPC interrupt.** P1's `mbox_send` already drove the write; `mbox_recv` now reads `irq_status` to prove the source latched. **PS-observable, firmware-free source. Recommended first demo.** |
| 2 | TideLink doorbell | write `DOORBELL @ 0x2014` | returner AHB-writes peer's `DOORBELL_RESPONSE_ACC @ 0x2024` (saturating add of *free-credit count*) | `d2d_irq[0]` → CPU0 IRQ10 | General-purpose to CPU0, BUT payload = free credits, so **0 credits ⇒ no IRQ**. Uses the **returner** master (distinct from the ahb_sub+CAM path — **unverified on silicon**). Needs `PAIR_BASE_ADDR @ 0x2000` set. |
| 3 | Packet committed | send a data packet to peer RX FIFO | `STATUS[4] @ 0x2010` (packet_committed) | `d2d_irq[2]` → CPU0 IRQ12 | Far-die data arrival. Level, cleared by reading FIFO. |
| 4 | PTP sync | send a PTP FC word | `PTP_CTRL[2] @ 0x2034` (rx_valid) | `d2d_irq[3]` → CPU0 IRQ13 | Gated by `PTP_CTRL.enable`; behind a generate guard — confirm `TIDELINK_PTP` in the image. |
| 5 | TideChart fabric | election/enum/hotplug event | `TC_STATUS` election_done/enum_done edge; `TC_HOTPLUG` sticky | `d2d_irq[14]` → CPU1 IRQ15 | Pulse on election/enum edges. **Dead until the TideChart RTL fix** (P4: dual-root, reset doesn't clear — see [`../verification/TIDECHART_TEST_PLAN.md`](../verification/TIDECHART_TEST_PLAN.md)). |
| — | Link-mgmt (CPU1 IRQ9-14) | — | wlink CRC/ECC, nego_error, train_fail, perf, I²C | `d2d_irq[8:13]` | **Die-local** (reflect this die's link hardware), not "messages from the far core". |
| — | Spare | — | tied `1'b0` | `d2d_irq[7:4]`, `[15]` | reserved headroom, no source. |

## PS-observable today vs needs firmware

**Source (arrival) — 100% PS-observable** over the backdoor, even with both cores
boot-gated: mailbox `irq_status @ 0x4_2300_0028`, doorbell acc `@ 0x4_2E03_2024`,
packet `STATUS[4] @ 0x4_2E03_2010`, PTP `@ 0x4_2E03_2034`, TideChart `@ 0x4_2E04_xxxx`.

**Delivery (an actual ISR) — needs firmware:** the core must be released from the
boot-gate and its NVIC ISER set (mailbox also needs `irq_enable @ 0x02C`). Both
cores are boot-gated in the PS flow — this is backlog item #8, parked for a
SWD-firmware session. There is no intermediate PS-armable mask.

## Simplest demonstrations (firmware-free, PS-side)

1. **Mailbox IRQ source (DONE in the tool).** `kr260_eth_xfer.py mbox_recv` now
   reads `irq_status @ 0x2300_0028` after a cross-die `mbox_send` and reports
   whether the slot0 MSG_VALID edge latched the source that feeds CPU1 IRQ0. This
   proves a far-die write raises the near-die interrupt *source* on silicon.
2. **SW doorbell (next, needs a little setup).** die_a writes `DOORBELL @
   0x4_2E03_2014`; die_b reads `DOORBELL_RESPONSE_ACC @ 0x4_2E03_2024` (expect
   nonzero). This is the only test of the **returner** cross-die master (unverified
   on silicon) and is wedge-safe (local APB writes/reads). **Prereq:** set
   `PAIR_BASE_ADDR @ 0x2000` to the peer's TideLink APB base during bring-up.
3. **Full ISR delivery** (item #8): SWD-load a tiny firmware on die_b that enables
   the mailbox IRQ + NVIC and toggles an LED/DMEM flag in the ISR; die_a's
   `mbox_send` then fires it. Needs the SWD probe + firmware.

## Caveats
- The **returner path** (doorbell/credit IRQs) is a *different* cross-die master
  than the proven ahb_sub+CAM transfers — not yet validated on silicon.
- The doorbell is payload-dependent (free-credit count), not a pure edge.
- Everything is credit-gated and needs the link at FCSM=4.
