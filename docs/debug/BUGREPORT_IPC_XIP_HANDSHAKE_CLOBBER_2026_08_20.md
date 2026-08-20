# CPU1 applications clobber the XiP-WARM handshake CPU0 boots on

**Status:** open, firmware. Not a design or netlist defect — no RTL change is implied.
**Found:** 2026-08-20, out of gate-level boot simulation of the eth chiplet.
**Severity:** delays CPU0's boot by ~14x in simulation. On silicon the same window exists.
**Owner:** needs a firmware owner. The GLS bench works around it and does not fix it.

## The contract

`stage0_bootrom_chip_core` publishes a handshake word after bringing up QSPI XiP
(`firmware/bootloader/stage0_bootrom_chip_core/main.c:317`):

```c
/* ---- 3. Publish the XiP-WARM handshake ------------------------------
 * IPC mailbox slot-1 data[0] = 0xD15C0001. The SECONDARY (eth/CPU0)
 * stage-0 polls this before it touches the shared XiP aperture,
 * serialising both ROM instances against the single CG092 cache port. */
REG32(NANOSOC_IPC_MAILBOX_BASE + NANOSOC_IPC_SLOT1_DATA_OFFSET) = 0xD15C0001u;
```

So **IPC mailbox slot-1 data[0] is a boot-critical word**: CPU0 polls it to know when it
may touch the shared XiP aperture. The reservation is documented independently in
`firmware/include/nanosoc_app_library.h:23`, which rejects the mailbox for a different
purpose precisely because that slot is taken:

> its slot-1 data[0] is ALREADY claimed at cold-boot for the XiP-WARM handshake
> (stage0 writes 0xD15C0001 there)

## The violation

`apps/chip_core_banner/main.c:59` writes its message to the same address:

```c
static const char banner[16] = "hello from CPU1!";
...
REG32(slot1_data + 0x0u) = src[0];   /* 0x6C6C6568 — "hell" */
```

`slot1_data + 0x0` **is** the handshake word. Once CPU1's application runs, the value
CPU0 is polling for is gone, replaced by ASCII text.

Nothing in the app is wrong on its own terms — the mailbox is a message-passing
peripheral and this is a message. The defect is that a documented, boot-critical
reservation is enforced only by comments in two headers.

## Evidence

Measured on the fp1505 gate-level boot run, 2026-08-19:

| Time | Event |
|---|---|
| 72.71 us | CPU1 stage0 writes `0xD15C0001` — handshake published |
| 3.47393 ms | CPU1 app writes `0x6C6C6568` — handshake destroyed |
| 3.50359 ms | CPU0 first reads the word — **29.66 us too late**, sees `"hell"` |

CPU0 does recover, but does not complete until **74.167 ms**. With a CPU1 application
that leaves the word alone, CPU0 completes at **~5.73 ms** — a ~13x difference
attributable entirely to the choice of CPU1 test image.

## Blast radius

14 applications reference `NANOSOC_IPC_SLOT1_DATA_OFFSET` or `NANOSOC_IPC_MAILBOX_BASE`:

    bus_walker  chip_core_banner  chip_core_nvic_irq  ipc_master  ipc_perf_master
    ipc_perf_slave  ipc_reg_semantics  ipc_slave  ipc_uart_print  reg_reset_audit
    soc_agent  soc_char_chip_core  spinlock_torture_master  spinlock_torture_slave

Not all of them write data[0] of slot 1 — this list is the set worth auditing, not a
list of confirmed offenders. `chip_core_banner` is confirmed.

## What the GLS bench does about it, and what it does not

`ASIC/gls-netlist/flash/mkflash.sh` now defaults `--cpu1-app` to `chip_core_event_sev`,
which does not reference the mailbox at all. That is why the netlist GLS gate can
observe CPU0 finishing inside a 320,000-cycle window.

**This is a mask, not a fix.** The race is untouched. Anyone passing `--cpu1-app` with
one of the apps above re-creates it, and will see CPU0's rungs go red on a chip that
boots correctly — a false red caused by the test image.

## Suggested directions, for whoever owns this

1. **Move the handshake out of a shared message slot.** The reservation is real but the
   location is a general-purpose mailbox that applications are entitled to use. A
   private ROM-owned word — the reasoning in `nanosoc_app_library.h` for the resident
   loader's control word applies verbatim here.
2. **Have CPU0 latch rather than poll.** If CPU0 records "handshake seen" once, a later
   clobber is harmless. Today the window between publish and observe is unguarded.
3. **Fail loudly.** CPU0 currently recovers silently and slowly. Reading something that
   is neither the handshake value nor a plausible successor should be an error, not a
   ~70 ms stall nobody attributes.

Options 2 and 3 are small and do not move the word. Option 1 is the structural fix.

## What this report does NOT claim

- Not observed on silicon. The evidence is gate-level simulation.
- No claim about which of the 14 apps beyond `chip_core_banner` actually collide.
- No claim that 74 ms is a hard bound; it is what this image did in this window.
