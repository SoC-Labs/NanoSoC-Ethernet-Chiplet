# Cross-die test backlog — what to exercise next on the two-board bench

Post-M1 (link up FCSM=4 + die_a↔die_b memory transfer both ways, on silicon). This
prioritizes the remaining cross-SoC functionality by value-per-effort. All PS-side
tests go through the `eth_ss_0` backdoor (`0x4_0000_0000 + SoC_addr`); **never** the
bare-link `0x8403_xxxx`/`0xA400_xxxx` map — those are undecoded on the eth-chiplet
and hang the PS bus (JTAG-POR only).

**Load-bearing fact:** inbound from the far die reaches **exactly two** targets —
`shared_sram_0` @ `0x2D` and `ipc_mailbox_0` @ `0x23`; everything else DECERRs
(`nanosoc_multicore_soc.yaml:2383-2387`). The memory transfer exercised the first;
**the mailbox is the untested second one.** The CAM replaces one address byte, so
retargeting inbound `0x2D`→`0x23` is a one-value change to the proven flow.

## Backlog (highest value + lowest effort first)

| # | Test | Proves | PS-side today? | Method | Prereq | Success |
|---|---|---|---|---|---|---|
| **1** | **Cross-die doorbell / mailbox** (`ipc_mailbox_0` @ 0x23) | The *other* inbound target works; message-passing across the link | **Yes** | die_a: CAM `RULE_0=0x00232F01` (`0x2F`→`0x23`); peer-write payload words at `0x2F00_0000+0x00..0x0C`, then `SLOT0_CTRL`(+0x20)=`MSG_VALID`. die_b: poll `0x2300_0020` locally, read `0x2300_0000..0x0C` | Link FCSM=4; ~30-line variant of `kr260_eth_xfer.py` | die_b reads MSG_VALID=1 + the 4 words die_a wrote |
| **2** | **Reverse direction (die_b → die_a)** | The slave→master direction (TideLink's own harness flagged S→M as the hard one); everything so far is master→slave only | **Yes** | Run existing `xfer_send` on the **die_b** board, `xfer_recv` on **die_a** (the script is board-agnostic) | Link FCSM=4 | Payload lands in die_a `shared_sram_0[0x2D001000]`; round-trip matches |
| **3** | **Multi-word soak + credit/health observability** | Sustained integrity + first throughput/health numbers | **Yes** (RO config-plane reads are safe) | Loop N peer-write+readback beats; between batches read `OBS_FC_CREDIT` @ `0x2E03_219C`, `CREDIT_PATH_STATUS` in `SWI_LANE_STATUS[31:17]`, sticky faults `STATUS` @ `0x2E03_2010`, `CREDIT_COUNT` @ `0x2E03_200C`, FCSM held=4 | Link FCSM=4; small loop tool on the `0x4_2E03` backdoor | 100% readback over N; no sticky fault; FCSM stays 4; credit counters move+recover |
| 4 | **DMA-250 bulk cross-die** (`dmac_0_m` → peer aperture) | Bulk DMA-driven crossing vs single CPU beat (zero-copy) | **Partial** — needs firmware or PS-replicated DMAC APB writes | DMA ch0 src=local SRAM, **dst=`0x2F00_xxxx` peer aperture** (NOT `0x2E00` TX — that's the no-backpressure wedge), nbytes=N; poll done; die_b reads its SRAM | SWD M0 app on die_a, or PS replication of DMAC regs; CPU released from boot-gate | die_b SRAM == source block; DMA done, no ERR |
| 5 | **PTP / PHC cross-die time sync** (servo src-0 = TideLink) | Cross-die timebase discipline over the FC sideband | **Partial** — HW path in bitstream; needs setup tool + care | die_a (GM) arm `HW_SYNC_CTRL`/interval; die_b servo-0 disciplines its PHC; PS reads both PHC captures + compares. **Caveat:** `servo_locked` reports the ha1588 servo not src-0 — judge by PHC-offset convergence, not the lock bit | Link FCSM=4; PHC enabled both dies | die_b PHC offset to die_a converges/holds over N syncs |
| 6 | **Negative / confinement + error path** | Inbound confinement holds; DECERR returns cleanly (no wedge) | **Yes — but wedge-risk, do carefully** | Set CAM replace to an **excluded** byte (e.g. `0x2F`→`0x2C`); peer-write; expect die_b default-slave DECERR over the link, board not wedged | Link FCSM=4; JTAG-POR staged | Error returned without hang; excluded region never written |
| 7 | **Link teardown / re-bring-up robustness** | Deterministic re-convergence across power cycles | **Yes (operational)** | `role_lock` clears only on poresetn → teardown = JTAG-POR both boards, re-run bringup, repeat ×N | 2 boards, JTAG-POR (via mapstone-dev) | FCSM=4 + cal_done every cycle; transfer passes after each |
| 8 | **Cross-die interrupt → NVIC → ISR** | Real doorbell/credit IRQ delivery (not poll) | **No** — needs firmware (cores boot-gated in the PS flow) | `d2d_irq[7:0]`→CPU0 NVIC, `[15:8]`→CPU1 wired; PS can only poll the IRQ source regs | SWD ISR firmware both dies | Far-die write raises the near-die ISR flag |
| 9 | **Ethernet (M2)** | External MAC path | No — separate milestone | Per runbook §7 | Hub topology + eth firmware + LAN8720 | out of scope this session |

## Do these next 3

1. **Cross-die doorbell/mailbox (`0x2F`→`0x23`).** The only inbound target silicon
   hasn't touched, completes the data-plane+control-plane IPC story, and costs one
   CAM byte + mailbox offsets on the already-wedge-safe peer-write path. Nothing new
   can wedge that the memory transfer didn't already clear.
2. **Reverse direction (die_b→die_a).** Nearly free (board-symmetric flow) but closes
   a real named unknown — TideLink flagged slave→master as the problematic direction,
   and all silicon so far is master→slave.
3. **Multi-word soak + credit observability.** Turns the one-shot transfer into a
   *characterised* link (throughput + `OBS_FC_CREDIT`/`CREDIT_PATH_STATUS`/sticky-fault
   numbers), all via safe RO reads. **Build the loop tool on the `0x4_2E03` backdoor —
   do NOT reuse the bare-link `kr260_credit_tx.py`/`kr260_drain.py` (they poke
   `0xA400`/`0x8403` → wedge).**

DMA (#4) and PTP (#5) are the tier-2 follow-ons but need firmware / a new tool.
#8 (IRQ→NVIC) is parked: the HW is wired but delivery is unobservable while both
cores are boot-gated — it needs SWD firmware and belongs with #4/#5.

### Tooling note
Items 1-3 are all ~small extensions of `kr260_eth_xfer.py` + `kr260_eth_run.sh`
(new CAM byte, mailbox/soak modes). See [CHIPLET_HOST_TOOLING_PLAN.md](CHIPLET_HOST_TOOLING_PLAN.md)
— these new modes should land behind the per-target descriptor, not as more
hard-coded scripts.
