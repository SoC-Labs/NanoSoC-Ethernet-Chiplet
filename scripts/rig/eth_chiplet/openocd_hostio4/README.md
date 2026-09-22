# `hostio4` — an OpenOCD adapter driver for the HOSTIO4/ADP debug port

Lets OpenOCD talk to the nanoSoC eth chiplet over the 7-pin HOSTIO4 link, with
no CPU involved and no SWD probe.

**NOTHING HERE HAS EVER TOUCHED HARDWARE.** Every proof below ran against a
software monitor over TCP loopback. First contact with a board is still to come.

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
| `hostio4.c` | the driver, 1327 lines — **the only copy**, see below |
| `hostio4-openocd.patch` | registration hunks ONLY, against master (`43441cd`): `configure.ac`, `openocd.texi`, `Makefile.am`, `interface.h`, `interfaces.c`. Does **not** carry the driver. The bench does not use this — the recipe owns 0.12.0 registration. |
| `hostio4-fake.cfg` | OpenOCD config: adapter + a `mem_ap` target |
| `hostio4-bench.cfg` | OpenOCD config for the real bench path (via `adp-bridge`, no `--raw`) |
| `hostio4-gdb.cfg` | opt-in posture A (`-gdb-port 3333`). Read its header first. |
| `run_proof_real.sh` | runs the six proofs against the real reference monitor |

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
| memory read / write | **real** |
| `load_image` over telnet/tcl | **real** — proven end to end, 8224 bytes, cross-checked on the wire |
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

## Traps the driver handles, and you must too if you write another client

- **Always emit 8 hex digits.** The digit count selects the access size —
  `Ax1000` silently switches the port to 16-bit.
- Reply framing is **LF then CR**, not CRLF. Count `]` prompts instead.
- Only RX words with `(w & 0xf00) == 0` are data bytes.
- **`0x2E000000-0x2FFFFFFF` is blacklisted in the driver.** That is the D2D
  window; with the link down it stalls the AHB bus forever and the ADP monitor
  has no bus timeout in RTL. Only a reset recovers it.
- A short `U` payload parks the monitor indefinitely. Block write is opt-in
  (`hostio4_block_write on`) for that reason.
- The address pointer auto-increments even on an errored transfer.

## What the bench transport does to these bytes

Every proof in this directory ran `adp-bridge --raw`, which turns the
console-bridge translation **off**. **The bench path cannot pass `--raw`** — the
dongle runs a console bridge in front of the monitor. So the hardware path
crosses a layer no proof has exercised, and `to_board()`
(`HAPS-work fpga/haps-sx/hostio/adp-bridge:178-190`) is a **flat, stateless,
per-byte loop**: it has no notion of protocol state and cannot tell a command
from `U` payload.

    0x03  ->  dropped, counted     deletion:     byte count CHANGES
    0x1b  ->  replaced by ']'      substitution: byte count PRESERVED

**This driver never emits a bare `0x03`.** Every command is ASCII — `Ax%08X\r`,
`R\r`, `R%08X\r`, `Wx%08X\r`, `Ux%08X\r`, `X\r` — and the lowest byte any of
them produces is CR `0x0d`. The only raw-binary path is the payload loop in
`hostio4_do_block_write`.

**It does emit exactly one bare `ESC`, and it is load-bearing.**
`hostio4_enter_adp_mode` writes a single `0x1b` (`ADP_ESC`, `hostio4.c:69`) via
`hostio4_write_all(&esc, 1)` at `:1030`, bypassing `hostio4_exchange`. That is
the mode-entry byte, first on the wire before any command, and the bridge
rewrites it to `]` in flight. The translation belongs in the bridge and this
driver should stay ignorant of it — but note that **the one byte everything
else depends on has never crossed the layer that rewrites it.** If it fails,
`:1042` reports *"no prompt from the ADP monitor -- is the far end up and in
command mode?"*, which reads as a dead board. Treat "did ADP mode entry
succeed" as a discriminator **separate** from "is the board alive".

### `0x03` in a firmware image is a block-write problem, not a `load_image` problem

`hostio4_block_write` is off by default (`hostio4.c:77`, gated at `:626`). With
it off, `load_image` sends every word as `Wx%08X\r` — **ASCII hex** — so an
image made entirely of `0x03` crosses intact. Scanning an image for `0x03`
unconditionally rejects firmware that loads fine in the default configuration.
**Condition the check on the flag, not on the image.**

With block write **on**, on the bench path, both hazards are live and the worse
one is not corruption:

| payload byte | bridge does | monitor sees | result |
|---|---|---|---|
| `0x03` | deletes it | **short `U` payload** | monitor **parks forever**, reset the only way back |
| `0x1b` | substitutes `]` | full byte count | **silent corruption**, upload reports success |

**The driver's own defence does not cover either.** "The payload is built in
full before a single byte is sent, and if the stream write cannot complete the
link is declared dead" protects against a *local* write failure. The driver does
send all N bytes; the bridge removes one in transit. A guarantee made at one end
of a transport is not a guarantee about the transport.

So block write off is a **standing constraint on the bench path**, not
first-contact caution. Enabling it later needs a bridge that is protocol-aware
during `U` payload; neither a pre-scan nor `--stats` closes it — `translated_esc`
is already non-zero from the legitimate mode-entry `ESC`, so a second one does
not stand out.

> **Correction owed to `HAPS-work docs/bench/HOSTIO4_OPENOCD_FIRST_CONTACT.md:41-42`**,
> which reads *"A firmware image containing a `0x03` byte cannot be sent over the
> console-bridge transport. `0x00`, `0x04` and `0x1B` are safe."* Both halves are
> wrong on the bench path. The `0x03` claim holds only with block write on, and
> **`0x1B` is not safe** — the bridge substitutes it. That line states the
> *monitor's* payload rules (`hostio4.c:549`) as though they were the *bridge's*;
> they are different layers with different behaviour, and the monitor never sees
> a `0x1b` to apply its rule to.

## Where this is going

One shared OpenOCD build on haps-dev at `/opt/soclabs-openocd/`, carrying this
driver and the `ahb_qspi` flash driver together — `flash write_image` over
HOSTIO4 needs both compiled in, and OpenOCD has no plugin mechanism. The recipe
lives at `/home/dam1n19/SoCLabs/soclabs-openocd`; `HAPS_OPENOCD_BIN` is the seam
that makes every existing bench path pick it up with no code change.
