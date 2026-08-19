# Stated limitation — D2D peer-aperture posted writes

**For inclusion in the tapeout submission / partner-facing errata.**
Drafted 2026-08-19 from silicon measurement. Supersedes any earlier description attributing this
to flow-control credit starvation — that mechanism was measured and **refuted**.

---

## Limitation

Sustained **bufferable (posted)** writes to the die-to-die peer aperture at **`0x2F000000`** can
saturate the AHB-to-AXI bridge's outstanding-write hazard list (depth 4) while it awaits write
responses. Once saturated, the bridge holds its AHB ready signal low and the **D2D subordinate port
stalls permanently**.

**There is no automatic recovery.** The port's write-stall backstop is measured to have **never
fired since reset** during a stall (its status bit is set-only and clears only on reset), and its
arming condition is defeated two independent ways: the timers are re-zeroed by unrelated bus
activity, and the error path is not applicable to writes. Recovery requires a **power-on reset of the
die**, which drops the die-to-die link.

## Required usage

**Cross-die writes to the peer aperture must be issued non-bufferable (`HPROT[2] = 0`).**
The non-bufferable path is limited to one outstanding write and cannot reach the condition; it has
been exercised on silicon and completes cleanly.

⚠ **This is not simply "do not point a DMA at the peer aperture."** On this SoC the Cortex-M0+ cores
have no MPU fitted, so the ARMv6-M default memory map applies and **an ordinary CPU store to
`0x2F000000` is bufferable by default**. Software must therefore either avoid direct CPU stores to
the peer aperture, or route peer writes through a master that presents `HPROT[2] = 0`.

Masters that **cannot** reach the condition by construction (`HPROT[2]` hardwired 0): the Ethernet
MAC DMA and the debug bridge. Masters that are **safe at reset but can be programmed into it**: the
DMA-250 (per-channel memory attributes) and the debug access port (CSW). The remote die **cannot**
reach the peer aperture at all.

## Status and scope

- **Measured** on the FPGA vehicle by inducing the condition with a posted-burst DMA transfer, with
  an onset-bracketed capture establishing the causal order directly.
- **Reachability on the ASIC** is established by RTL trace, not by silicon reproduction on the ASIC.
- A one-line RTL change that removes the condition at source (forcing the peer path non-bufferable
  for all masters) has been validated in simulation and its mechanism confirmed on silicon, but is
  **not** in this revision.
- Diagnostic state remains readable over APB during a stall. **Check the register's marker byte
  before interpreting any value** — an unmarked read means the instrument is not answering and must
  not be read as data.

## What is not claimed

- The underlying reason write responses cease has not been isolated to a single component; two
  candidate paths remain open and both lie outside the ASIC-sourced RTL.
- Multi-beat burst delivery is validated for the **non-bufferable** path only.
