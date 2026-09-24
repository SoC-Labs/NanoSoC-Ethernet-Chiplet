# `hostio4` — an OpenOCD adapter driver for the HOSTIO4/ADP debug port

Lets OpenOCD talk to the nanoSoC eth chiplet over the 7-pin HOSTIO4 link, with
no CPU involved and no SWD probe.

**Hardware status, 2026-09-23.** Five things are proven on silicon through the
real bench transport: word read, word write, block read, fault reporting and the
D2D refusal (`PROOF-HARDWARE-2026-09-22.md`). `load_image` has one 16-byte
silicon run, which is too small to prove it; the real proof is pending (see
"`load_image`: what it was proven against"). Everything else here ran against a
software monitor over TCP loopback.

**Driver fixes, 2026-09-24: proven offline only.** Byte and halfword access, a
reply line lost in transit, a far end that never goes quiet, an absolute
exchange deadline, and a guard on the `U` block write. Each has a test in
`test_driver_fixes.sh` that fails on the driver before the fix and passes after
it. None of them has run on silicon.

## What it is

A *dapdirect* adapter driver that emulates a MEM-AP in software, modelled on
upstream `src/jtag/drivers/dmem.c`. The DP is entirely faked (`DP_CTRL_STAT`
returns `CDBGPWRUPACK|CSYSPWRUPACK`, everything else 0, writes are no-ops — all
`dap_dp_init` needs). The AP is a software CSW/TAR state machine whose DRW maps
onto the ADP monitor's set-address / read-word-auto-increment / write-word. An
ADIv5 MEM-AP *is* an auto-incrementing word port, so the fit is exact.

One departure from `dmem`: **deferred DRW batching.** `queue_ap_read(DRW)`
accumulates contiguous words so an N-word read collapses to a single `R<count>`
block read. `dmem` issues every access immediately, which would waste the block
form entirely. The driver also tracks the monitor's address pointer and omits a
redundant `Ax`.

## Files

| file | what |
|---|---|
| `hostio4.c` | the driver, 1452 lines — **the only copy**, see below |
| `hostio4-openocd.patch` | registration hunks ONLY, against master (`43441cd`): `configure.ac`, `openocd.texi`, `Makefile.am`, `interface.h`, `interfaces.c`. Does **not** carry the driver. The bench does not use this — the recipe owns 0.12.0 registration. |
| `hostio4-fake.cfg` | OpenOCD config: adapter + a `mem_ap` target |
| `hostio4-bench.cfg` | OpenOCD config for the real bench path (via `adp-bridge`, no `--raw`) |
| `hostio4-gdb.cfg` | opt-in posture A (`-gdb-port 3333`). Read its header first. |
| `run_proof_real.sh` | runs one proof against the real reference monitor; its `FAR=` knob swaps in `fake_mon.py` or HAPS-work's bench-transport fake instead (see its header) |
| `test_driver_fixes.sh` | the repeatable tests: one leg per 2026-09-24 fix, the six hardware-proof steps, and an 8224-byte `load_image`. Exit status = failed legs |
| `fake_mon.py` | a **deliberately misbehaving** monitor for fault injection (console chatter, a flood, a garbled reply line). Not a reference: use `adpmon.py` for that |
| `h4check.py` | reads a far end's `--trace` as evidence: the commands it received, the bytes inside `U` payloads, and a replay of `adpmon.py`'s memory |

## One source, both OpenOCD revisions

`hostio4.c` builds unmodified at **v0.12.0 (`9ea7f3d`)** and at master, guarded by
`#ifdef TRANSPORT_DAPDIRECT_SWD`. That symbol is a `#define` on master and does not
exist at 0.12.0, so it is a real feature test; master removed `.transports`, so no
single spelling works at both and the guard is required rather than stylistic.

There is deliberately no separate back-ported copy. An earlier
`hostio4-openocd-v0.12.0.patch` has been removed: two whole-driver patches that must
not both be applied is exactly the sort of thing someone gets wrong at 2am.

**`hostio4-openocd.patch` used to embed a whole copy of the driver too**, and it had
gone 28 lines stale — it still carried the `LOG_DEBUG` bus-error message that
`c136d77` replaced, so applying it would have reintroduced the off-by-one faulting
address that commit exists to prevent. The embedded copy has been stripped; the patch
is now registration-only, and `git apply --check -R` against a patched pristine
`43441cd` confirms the five remaining hunks are exact. **There is one `hostio4.c`.**

**Registration is owned by the build recipe, not by this directory.**
`/home/dam1n19/SoCLabs/soclabs-openocd` carries
`patches/0002-register-hostio4-v0.12.0.patch` (configure.ac, `src/jtag/drivers/Makefile.am`,
`src/jtag/interfaces.c` — at 0.12.0 the adapter externs live in `interfaces.c`, master
moved them to `interface.h`, so the two are not interchangeable) and symlinks this
`hostio4.c` in at build time. `make build` there produces one binary carrying both this
driver and `ahb_qspi`, and its `verify` gate refuses a binary missing either.

## Reproducing the proofs

`run_proof_real.sh` drives the chain

    adpmon.py --tcp PA  <--  adp-bridge --raw --tcp PB  <--  openocd

where `adpmon.py` (861 lines, RTL-cited line by line) and `adp-bridge` live in
HAPS-work at `fpga/haps-sx/hostio/`. Six proofs: `dap init`; `mdw`; a multi-word
`mdw` proven **from the wire** to emit the `R<count>` form; `mww` round-trip; an
unmapped address reporting a fault rather than zeros; and the D2D window refused
in the driver with zero bytes emitted.

`test_driver_fixes.sh` runs those six steps as leg `R`, plus every fix leg:

    ./test_driver_fixes.sh --out DIR /path/to/openocd [LEG ...]

Legs `S D T C F G1 G2 Q1 Q2` each fail on the driver before its fix and pass after.
`Q3`, `R` and `R7` are controls and regressions and pass on both. Measured on
2026-09-24: the binary installed before the fixes passed 3 of 12, and the fixed
build passed 12 of 12. Writes are checked in the monitor's own memory, by
replaying its trace through a fresh `adpmon.py` (`h4check.py replay`). A read-back
through the same driver can be fooled by that driver twice. The header of
`test_driver_fixes.sh` says what each leg does.

There was a second, smaller fake (`fake_adp.py`) written to unblock driver
development. It disagreed with `adpmon.py` in **13 behavioural classes and was
wrong in all 13** when adjudicated against `socdebug_adp_control.v` — including
inventing a "first command after ESC is swallowed" rule that does not exist, and
modelling the D2D window as returning a bus error when the RTL says an
un-`HREADY`'d transfer hangs the monitor silently. It has been deleted. Use
`adpmon.py`.

## What you actually get, and what is a lie

The stock `mem_ap` target is the one to use. **It does not serve a gdb port** —
`mem_ap.c:53-54` sets `gdb_port_override = "disabled"` itself and
`gdb_server.c:3823-3827` honours it. (A widely-repeated claim that a gdb port
*is* served comes from reading `target_supports_gdb_connection()`, which is
genuinely true and never reached. Four sessions got this wrong before someone
ran OpenOCD and read the log line `gdb port disabled`.)

| | |
|---|---|
| memory read / write | **real for whole words**, on silicon. Byte and halfword access is emulated by read-modify-write, proven offline only: see "Byte and halfword access" below |
| `load_image` over telnet/tcl | **proven on loopback only; silicon pending**: see below |
| `verify_image` | **unavailable** — `checksum_memory` unimplemented for `mem_ap`; read back with `mdw` |
| registers | **fiction** — `mem_ap_reg_get/set` return OK and touch nothing |
| halt / reset / resume / step | **lies** — they flip a state flag; the wire counters are identical before and after |
| breakpoints | none |

So this is a **firmware loader and memory browser**, not a debugger. Halt,
registers and breakpoints need the per-core PPB windows granted to `debug_m` —
see branch `feat/hostio-ppb-window` in `nanosoc-multicore-system`. The driver
already carries the translation hook for that (`hostio4_ppb_xlat`, off by
default, `hostio4_ppb_base <ap> <hex>` to enable), so it needs no code change
when the RTL lands.

Forcing the gdb port on with `hostio4-gdb.cfg` does not give a usable session:
stock `arm-none-eabi-gdb` **crashes** on register 25, and is reachable only with
both `set remote p-packet off` and `set remote P-packet off`.

### `load_image`: what it was proven against

This row used to read "proven end to end, 8224 bytes, cross-checked on the wire".
That line arrived in the driver's first commit, `8035fe1`, before any hardware run.
It was proven against a software monitor over TCP loopback. No transcript or script
of that run survives. Leg `R7` of `test_driver_fixes.sh` now repeats that 8224-byte
load against `adpmon.py` and checks it byte for byte in the monitor's own memory,
but it still runs over loopback with `adp-bridge --raw`. That flag switches off the
byte translation the bench cannot avoid (see "What the bench transport does").

On silicon there is exactly one load: 16 bytes at `0x10007000` on 2026-09-22
(HAPS-work `docs/bench/PLAN_END_OF_DAY_2026-09-22.md:199-213`). None of its bytes is
`0x03`, `0x1b` or `0x5d`, so it crossed the layer that rewrites those bytes without
testing it.

**Silicon proof is pending:** HAPS-work `docs/bench/tools/prove-load-image.sh`
(branch `tool/prove-load-image`). It loads 4 KB into `0x10007000`, with every byte
value and the three hazard bytes in every byte lane. It then reads the region back
byte for byte, checks the wire form against the driver's counters, restores the
region and verifies the restore. Its `--selftest` shows, offline, that it passes on
a faithful monitor and fails when one byte is corrupted or the restore does not
take. It has not yet been run at the bench.

### Byte and halfword access

**Fixed 2026-09-24, proven offline only (leg `S`).** Until then the driver forced
the emulated CSW to 32-bit and stepped TAR by 4 per DRW, whatever size OpenOCD
asked for. So a byte or halfword write went out as a whole word with the other
lanes zeroed, and inside a multi-access sequence it landed in the wrong word.
`load_image` still reported success. Measured offline against `adpmon.py` on
2026-09-23:

| write | word before | word after |
|---|---|---|
| `mwb 0x10007101 0xAA` | `4d006c40` | `0000aa00` |
| `mwh 0x10007202 0xBEEF` | `db62d880` | `beef0000` |
| `load_image` of 3 bytes `aa bb cc` at `0x10007200` | `db62d880 792a5231` | `0000bbaa 00cc0000` |

Now the CSW keeps the size OpenOCD sets, TAR is byte-exact and steps by the
access size, and each 8- or 16-bit DRW transfer (`hostio4_subword`) works like
this:

- **A write** reads the containing word, merges the lane or lanes in, and writes
  the word back. The monitor itself has no sub-word access above address `0xff`:
  its access size is the digit count of `Ax`, and the driver always sends eight.
- **The read-modify-write is not atomic** on the bus. If the SoC writes the
  other lanes of that word between the read and the write, that write is lost.
- **Packed transfers are not emulated.** The CSW reads back `ADDRINC_SINGLE`, so
  OpenOCD sends one DRW per byte. An `mdb` of N bytes costs N word reads.
- An access that would cross a word boundary is refused.

So `load_image` of any length, at any alignment, is now byte-exact. Leg `S` checks
this with two 7-byte loads, one with a byte and a halfword at the head and one
with a halfword and a byte at the tail: no word outside the image changes. Whole
word traffic, including the aligned body of every `load_image`, is unchanged.

## Traps the driver handles, and you must too if you write another client

- **Always emit 8 hex digits.** The digit count selects the access size —
  `Ax1000` silently switches the port to 16-bit.
- Reply framing is **LF then CR**, not CRLF. Count `]` prompts instead.
- Only RX words with `(w & 0xf00) == 0` are data bytes.
- **`0x2E000000-0x2FFFFFFF` is blacklisted in the driver.** That is the D2D
  window; with the link down it stalls the AHB bus forever and the ADP monitor
  has no bus timeout in RTL. Only a reset recovers it.
- A short `U` payload parks the monitor indefinitely. Block write is opt-in
  (`hostio4_block_write on`) for that reason. Even when it is on, a block whose
  payload carries `0x03`, `0x1b` or `0x5d` goes as `Wx` words (see below).
- The address pointer auto-increments even on an errored transfer.

## What the bench transport does to these bytes

Every proof in this directory except leg `G1` of `test_driver_fixes.sh` ran
`adp-bridge --raw`, which turns the console-bridge translation **off**. **The
bench path cannot pass `--raw`**, because the dongle runs a console bridge in
front of the monitor. So the hardware path crosses a layer the other proofs have
not exercised, and `to_board()`
(`HAPS-work fpga/haps-sx/hostio/adp-bridge:178-190`) is a **flat, stateless,
per-byte loop**: it has no notion of protocol state and cannot tell a command
from `U` payload.

    0x03  ->  dropped, counted     deletion:     byte count CHANGES
    0x1b  ->  replaced by ']'      substitution: byte count PRESERVED

and the dongle's console loop (HAPS-work `haps-hostio:1515-1520`) then turns
every `]` into ESC, just as blindly:

    0x5d  ->  replaced by ESC      substitution: byte count PRESERVED

End to end, a `0x1b` makes the round trip back to `0x1b`, a `0x5d` arrives as
`0x1b`, and a `0x03` never arrives.

**This driver never emits a bare `0x03`.** Every command is ASCII — `Ax%08X\r`,
`R\r`, `R%08X\r`, `Wx%08X\r`, `Ux%08X\r`, `X\r` — and the lowest byte any of
them produces is CR `0x0d`. The only raw-binary path is the payload loop in
`hostio4_do_block_write`.

**It does emit exactly one bare `ESC`, and it is load-bearing.**
`hostio4_enter_adp_mode` writes a single `0x1b` (`ADP_ESC`, `hostio4.c:69`) via
`hostio4_write_all(&esc, 1)` at `:1155`, bypassing `hostio4_exchange`. That is
the mode-entry byte, first on the wire before any command, and the bridge
rewrites it to `]` in flight. The translation belongs in the bridge and this
driver should stay ignorant of it — but note that **the one byte everything
else depends on has never crossed the layer that rewrites it.** If it fails,
`:1168` reports *"no prompt from the ADP monitor -- is the far end up and in
command mode?"*, which reads as a dead board. Treat "did ADP mode entry
succeed" as a discriminator **separate** from "is the board alive".

### `0x03` in a firmware image is a block-write problem, not a `load_image` problem

`hostio4_block_write` is off by default (`hostio4.c:77`, gated at `:678`). With
it off, `load_image` sends every word as `Wx%08X\r` — **ASCII hex** — so an
image made entirely of `0x03` crosses intact. Scanning an image for `0x03`
unconditionally rejects firmware that loads fine in the default configuration.
**Condition the check on the flag, not on the image.**

Before 2026-09-24, with block write **on** on the bench path, these were the
hazards, and the worst was not corruption:

| payload byte | transport does | monitor sees | result |
|---|---|---|---|
| `0x03` | bridge deletes it | **short `U` payload** | monitor **parks forever**, reset the only way back |
| `0x5d` | dongle substitutes ESC | full byte count | **silent corruption**, upload reports success |
| `0x1b` | bridge substitutes `]`, dongle substitutes ESC back | `0x1b` | intact on the bench; **corrupted** on any path without the dongle's half |

The driver's defence at the time covered none of them. "The payload is built in
full before a single byte is sent, and if the stream write cannot complete the
link is declared dead" protects against a *local* write failure. The driver does
send all N bytes, and the transport removes one in transit. A guarantee made at
one end of a transport is not a guarantee about the transport.

**The guard, 2026-09-24** (`hostio4_payload_mangled`, `:642`, checked at `:678`):
a pending block whose payload carries `0x03`, `0x1b` or `0x5d` is sent as ASCII
`Wx` words instead of `U`. Leg `G1` checks this through `adp-bridge` without
`--raw` and HAPS-work's model of the dongle (`prove-load-image-fakebench.py`).
It loads four 16-byte blocks: one clean and three that each carry one hazard byte
in every lane. The region arrives intact, the clean block goes as one `U`, and
each hazard block goes as four `Wx`. On the driver before the guard, the `0x5d`
block arrived as `0x1b` and the `0x03` block parked the monitor. The reviewed
patch guarded only `0x03` and `0x1b`, and on it the `0x5d` block still arrived
as `0x1b`, with rc 0.

Block write off is **still a standing constraint on the bench path**. The guard
covers only the three byte values known to be rewritten. The dongle feeds
MicroPython's text-mode stdin, and what that does to other raw bytes (`0x04`,
CR/LF, anything at `0x80` or above) is not modelled anywhere
(`prove-load-image-fakebench.py` says so). Enabling block write needs a transport
that is protocol-aware during a `U` payload, or a bench run that proves the whole
byte range.

> **Correction owed to `HAPS-work docs/bench/HOSTIO4_OPENOCD_FIRST_CONTACT.md:41-42`**,
> which reads *"A firmware image containing a `0x03` byte cannot be sent over the
> console-bridge transport. `0x00`, `0x04` and `0x1B` are safe."* Both halves are
> wrong on the bench path. The `0x03` claim holds only with block write on, and
> **`0x1B` is not safe** — the bridge substitutes it. That line states the
> *monitor's* payload rules (`hostio4.c:577`) as though they were the *bridge's*;
> they are different layers with different behaviour.
> **Refined 2026-09-24:** the dongle turns the bridge's `]` back into ESC, so on
> the full bench path a payload `0x1b` does arrive intact. The byte that arrives
> rewritten is **`0x5d`**, as `0x1b`. `0x1B` is still unsafe on any path without
> the dongle, and the guard treats all three bytes alike.

## Where this is going

One shared OpenOCD build on haps-dev at `/opt/soclabs-openocd/`, carrying this
driver and the `ahb_qspi` flash driver together — `flash write_image` over
HOSTIO4 needs both compiled in, and OpenOCD has no plugin mechanism. The recipe
lives at `/home/dam1n19/SoCLabs/soclabs-openocd`; `HAPS_OPENOCD_BIN` is the seam
that makes every existing bench path pick it up with no code change.
