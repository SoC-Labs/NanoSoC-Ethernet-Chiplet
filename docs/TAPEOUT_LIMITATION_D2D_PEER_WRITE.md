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

The depth-4 hazard list is a **vendor default of the licensed bridge** — `HAZARD_LIST_SIZE = 4` in
the Arm CoreLink XHB-500 source template, not a value selected in this integration and
not exposed as a build-time parameter. In that template the neighbouring bus widths *are* generator
substitution tokens (`<<ADDR_WIDTH>>`, `<<ID_WIDTH>>`) while `HAZARD_LIST_SIZE` is a literal `4`, so
the depth is fixed by the IP rather than left unset by our configuration. The limitation is therefore
a property of the licensed IP as delivered, and is mitigated at the integration level (see below)
rather than by resizing the list.

**There is no automatic recovery.** The port's write-stall backstop is measured to have **never
fired since reset** during a stall (its status bit is set-only and clears only on reset), and its
arming condition is defeated two independent ways: the timers are re-zeroed by unrelated bus
activity, and the error path is not applicable to writes. Recovery requires a **power-on reset of the
die**, which drops the die-to-die link.

## Required usage

**Peer-path writes are forced non-bufferable in hardware in this revision — software no longer
selects this.** The integration ties `HPROT[3:2] = 00` at the peer choke point, downstream of the
bus matrix, so every initiator is covered whatever attributes it presents. The non-bufferable path
is limited to one outstanding write and cannot reach the condition; it has been exercised on
silicon and completes cleanly.

⚠ **This matters because software could not have solved it.** The Cortex-M0+ cores have **no MPU
fitted** — `MPU = 0` is a build parameter meaning the unit is not instantiated, not a disabled
feature — so the ARMv6-M default memory map applies and an ordinary CPU store to `0x2F000000`
presents `HPROT[3:2] = 11` unconditionally, with no software override available on this silicon.
The hardware tie-down is therefore not a belt-and-braces addition to a software rule; **it is the
only mechanism that closes the condition.**

Masters that **cannot** reach the condition by construction (`HPROT[2]` hardwired 0): the Ethernet
MAC DMA and the debug bridge. Masters that are **safe at reset but can be programmed into it**: the
DMA-250 (per-channel memory attributes) and the debug access port (CSW). All of these are now moot
on this path: the tie-down sanitises every one of them at the choke point.

The remote die **cannot** reach the peer aperture — note this is a *loopback* restriction: inbound
requests decode only to the shared SRAM and the IPC mailbox, so the remote die can reach this die's
memory but can never re-enter this die's own link block, and therefore can never be the master that
triggers the condition.

## Status and scope

- **Measured** on the FPGA vehicle by inducing the condition with a posted-burst DMA transfer, with
  an onset-bracketed capture establishing the causal order directly.
- **Reachability on the ASIC** is established by RTL trace, not by silicon reproduction on the ASIC.
- **The one-line RTL change that removes the condition at source IS in this revision.** (An earlier
  draft of this document said it was not; that text predated the change landing and was stale.) It
  forces the peer path non-bufferable for all masters, and it is verified present in the shipping
  gate netlist, not merely in RTL: at the `tidelink_top` instance `HPROT[3:2]` are constant-
  propagated away, and the depth-4 hazard list together with the early-write-response path have
  been **optimised out of the netlist entirely** — the saturating resource does not physically
  exist in the shipping silicon. Independently corroborated on the FPGA vehicle, where the
  hazard-list high-water reads **zero** on a live link across a sustained write soak.
- ⚠ **Diagnostic state is NOT readable during a stall by any on-die master.** An earlier draft of
  this document claimed it was; that is incorrect. The TideLink APB window and the peer aperture
  are two leaves of one bus-matrix slave port sharing a single HREADY, so the instrument shares
  fate with the stalled path. The measurements that produced diagnostic values on the FPGA vehicle
  came through a PS backdoor that is tied off on the ASIC. The debug access port is the exception —
  it carries a bounded AHB timeout, so a debugger reads either a valid marker or a bounded bus
  error rather than hanging. **Check the marker byte before interpreting any value** — an unmarked
  read means the instrument is not answering and must not be read as data.

## What is not claimed

- The underlying reason write responses cease has not been isolated to a single component; two
  candidate paths remain open and both lie outside the ASIC-sourced RTL.
- Multi-beat burst delivery is validated for the **non-bufferable** path only.
- **No software-reachable recovery exists for this condition.** The chip-level warm-reset request
  is tied inactive at the boundary, the subsystem reset controller resets only the CPU cores, and
  the bridge has no reset of its own — every recovery register sits behind the port that stalls.
  Recovery is a power-on reset of the die, which drops the link. This is stated so that no
  integrator plans a software recovery path that cannot exist.
