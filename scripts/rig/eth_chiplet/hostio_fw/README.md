# hostio_fw — three small images, and the loader that installs them

Raw Cortex-M0 binaries for the eth chiplet, plus a loader that puts one into
eth IMEM over the ADP debug port and proves it landed.

Nothing here is a stub. Every image does the thing it claims; every check in
the loader can be made to fail, and `fw_selftest.py` makes each of them fail on
purpose so that a green run means something.

```
make TARGET=fpga            # 25.010 MHz -- the measured KR260 fabric clock
make TARGET=asic            # 100 MHz    -- the ASIC signoff clock
make TARGET=asic FAULT=1    # heartbeat image also makes HIO-507's one
                            # deliberate access to 0x70000000
make selftest               # 49 checks, no hardware, no serial port
python3 fw_load.py --image build/fpga/fw_heartbeat.bin            # DRY RUN
python3 fw_load.py --image build/fpga/fw_heartbeat.bin --port /dev/ttyACM0
```

---

## 1. What got built

| image | bytes (fpga) | bytes (asic) | core | what it does |
|---|---|---|---|---|
| `fw_cpu1_park.bin` | 68 | 68 | CPU1 (chip core) | vector table + `nop; b .` |
| `fw_heartbeat.bin` | 356 | 356 | CPU0 (network core) | sentinel + incrementing heartbeat |
| `fw_mdio_probe.bin` | 1128 | 1128 | CPU0 (network core) | heartbeat + hardened MDIO/MAC scan |

`FAULT=1` builds into `build/<target>-fault/` and changes **only**
`fw_heartbeat.bin`, which grows to 372 bytes (verified: the other two are
byte-identical across the two builds, so the flag demonstrably changes the one
artefact it claims to and nothing else). The fpga and asic binaries differ from each other — the core clock is
genuinely compiled in, not read from a header at runtime.

Everything is linked at **`0x10000000`**, the remap-independent IMEM alias.
`0x00000000` is that same RAM only while the eth REMAP bit points at IMEM, and
the boot ROM otherwise, so nothing here is linked there.

### Toolchain

`arm-none-eabi-gcc (GNU Arm Embedded Toolchain 10.3-2021.10) 10.3.1`, already
on `PATH` from `/home/dam1n19/runthrough_itb/gcc-arm-none-eabi-10.3-2021.10/bin`.
It has the `thumb/v6-m/nofp` multilib, which is what `-mcpu=cortex-m0` needs.
Built freestanding: `-nostdlib -nostartfiles`, no CMSIS, no libc, no libgcc —
`arm-none-eabi-nm -u` reports **zero undefined symbols** in all three ELFs, so
there is no runtime dependency to go missing.

Built `-mcpu=cortex-m0` (armv6-m baseline) so one binary is correct on the M0
and the M0+ alike. The SoC's generated map declares
`NANOSOC_DEFAULT_CPU := cortex-m0`; the shipping ROMs are built m0plus.

### Clock

`FW_CORE_HZ` is a `-D` on every compile and `fw_rt.h` `#error`s without it.
There is deliberately **no default**: the header's `SystemCoreClock` is 100 MHz,
which is wrong by 4x on the KR260 (measured 25.010 MHz), and that is exactly
the kind of silent error that reads as a hardware fault three steps later. The
value is also published at `0x2D00000C` so an operator can see which build is
loaded rather than infer it.

---

## 2. The shared-SRAM ABI

One source of truth: **`fw_abi.h`**. `fw_abi.py` *parses* that header rather
than restating it, so the loader, the printed environment block and the
compiled images cannot drift apart.

| address | word | written by |
|---|---|---|
| `0x2D000000` | heartbeat, **incremented every main-loop pass** | heartbeat, mdio |
| `0x2D000004` | sentinel `0x5E27C0DE`, **written once per boot, in `main()` only** | heartbeat, mdio |
| `0x2D000008` | image id: `0x48465700 \| n` (`"HFW"`, n = 1 park / 2 heartbeat / 3 mdio) | heartbeat, mdio |
| `0x2D00000C` | the core Hz this binary was built for | heartbeat, mdio |
| `0x2D000010` | **PHYID1** (PHY reg 2) — `HOSTIO_FW_MDIO_RESULT_ADDR` | mdio |
| `0x2D000014` | **PHYID2** (PHY reg 3) | mdio |
| `0x2D000018` | **third word = MIIMODER**, expect `0x00000064` | mdio |
| `0x2D00001C` | status: `[31:24] 0xB3 · [23:16] result code · [15:8] candidates · [7:0] selected PHY (0xFF none)` | mdio |
| `0x2D000020` | mask: addresses whose reg 2 was stably `0xFFFF` | mdio |
| `0x2D000024` | mask: stably `0x0000` | mdio |
| `0x2D000028` | mask: **unstable** (four reads not identical) | mdio |
| `0x2D00002C` | mask: stable and non-trivial | mdio |
| `0x2D000030` | mask: candidates (stable, `PHYID1 == 0x0007`) | mdio |
| `0x2D000034` | count of MDIO transactions where BUSY never cleared | mdio |
| `0x2D000038` | `MODER` **as read** (expect `0x0000A000`) — never written | mdio |
| `0x2D00003C` | `PACKETLEN` as read (expect `0x00400600`) | mdio |
| `0x2D000040` | completed scan passes | mdio |
| `0x2D000044` | fault info: 0 not built in · 1 attempted · 2 taken and resumed | heartbeat |
| `0x2D000048` | stacked PC at the HardFault (0 if none) | heartbeat |
| `0x2D00004C` | mask: addresses whose MDIO transaction timed out | mdio |
| `0x2D001FF0` | boot-confirm token `0xB007C0FE` | heartbeat, mdio |

**Why the heartbeat and the sentinel are two words.** HIO-503 zeroes the
sentinel, pulses `CPU0_SWRST`, and polls for it to come back. If the main loop
also wrote it, that poll would match without any reset having happened and the
relaunch test would be green on a CPU that never restarted. The sentinel is
written exactly once, from `main()`, on the way in — a reset re-enters `main()`
and writes it again, which *is* the signal HIO-503 wants. Nothing in either
loop touches `0x2D000004`.

**The heartbeat image stamps the MDIO block as `RC_NOT_RUN` (`0xFF`) on every
boot.** Otherwise a probe result left in SRAM by a previous load would still be
sitting there and HIO-506 would read it as a live result from the image that is
actually running now.

Ordering note: HIO-208 clobbers shared SRAM. Run it before loading firmware,
not after.

---

## 3. The images

### 3.1 `fw_cpu1_park.bin` — CPU1 parking loop (68 bytes)

A full 16-entry ARMv6-M vector table and two instructions:

```
10000000 <fw_park_vectors>:  10004000  10000041  10000041  10000041 ...
10000040 <fw_park>:          46c0   nop
10000042:                    e7fd   b.n 10000040
```

* **No DMEM, no peripheral, no shared SRAM.** It announces nothing. A parked
  CPU1 that still wrote a liveness word would be contending for the very bus
  the memory tests are trying to measure, which is the whole reason to park it.
* **No stack use.** The initial SP is a valid value the core loads at reset and
  never a target of any push, because nothing pushes.
* **No `WFI`, deliberately.** CPU1's PRMU sources the fabric's HCLK and
  HRESETn, and nothing in this tree establishes what CPU1's `SLEEPING` output
  does to it. A parking loop that gated the fabric clock would take the debug
  port down with it. Spinning costs one instruction fetch per iteration out of
  CPU1's **own** IMEM — no fabric traffic.
* Linked at `0x10000000`, which is **CPU1's own view of its 16 KB IMEM**
  (`nanosoc_multicore_soc_cc_stage1_imem_memory.ld`). `0x90000000` is the debug
  port's alias for the same RAM and is not an address CPU1 ever fetches from.

**Read section 5 before trying to install it.**

### 3.2 `fw_heartbeat.bin` — liveness (356 bytes)

`main()` publishes the identity words and the boot token, stamps the MDIO block
`NOT_RUN`, writes the sentinel **once**, optionally makes the deliberate fault,
then loops: increment, store to `0x2D000000`, spin ~1 ms. ~1 kHz is three
orders of magnitude faster than HIO-504's one-second interval and leaves the
bus almost entirely idle; a free-running store loop would hammer the same SRAM
the debug port is reading, for no extra information.

**`FAULT=1`** adds one deliberate **read** of `0x70000000` — a read, not a
write, because an M0/M0+ store can be buffered, which makes the resulting fault
imprecise and the captured PC meaningless, while a load stalls the core until
the ERROR response returns. Confirmed present in the `FAULT=1` disassembly
(`movs r3,#224; lsls r3,r3,#23` → `0x70000000`; `ldr r2,[r3]`) and absent from
`FAULT=0`.

The HardFault handler **records and resumes properly**: it rewrites the stacked
PC to a resume point and performs a real exception return, which clears the
HardFault's active state. It does not branch out of handler mode with the fault
still active — that leaves the core at priority −1 where the next fault is a
lockup rather than a fault, and from the debug port the two look identical. So
the heartbeat survives the fault and HIO-504 stays green while HIO-507 reads
the capture.

If a particular fabric build only captures writes, change `FW_R32` to `FW_W32`
at that one line in `fw_heartbeat.c`.

### 3.3 `fw_mdio_probe.bin` — MDIO/MAC probe (1128 bytes)

The only route to MDIO from this port: the MAC at `0x40000000` is outside
`debug_m`'s decode, so ADP cannot reach it and CPU0 can. It **also carries the
full heartbeat ABI**, because HIO-506 declares `needs=["HIO-502","HIO-504"]` and
an MDIO-only image would leave the test voided. The heartbeat keeps advancing
*during* a scan (a scan where every transaction times out takes seconds, and a
heartbeat frozen that long would fail HIO-504's advance check for the wrong
reason). It rescans every ~2 s, so fixing wiring or powering the PHY updates
the answer without a reload.

**It configures nothing.**

* `MIIMODER` CLKDIV is **left at its reset `0x64`**. The real law is
  `MDC = hclk / (2 · floor(CLKDIV/2))` (`eth_clockgen.v`), so `0x64` gives
  250 kHz at 25.010 MHz and 1.000 MHz at 100 MHz — in spec on both, with
  margin, and needing no write at all. The driver library's
  `ethmac_mii_set_clkdiv(&eth, 49u)` and its "250 kHz" comment are wrong by 2x;
  not writing the register sidesteps that entirely.
* **`MODER` is not written.** Some existing apps set `MODER = 0` before
  scanning, but the MIIM block is clocked from the host clock alone
  (`eth_top.v:374-377`) and is independent of `MODER.RXEN/TXEN` and of the RMII
  reference clock — so zeroing it buys nothing and costs the ability to read
  its reset value back as a witness. It is read and published instead.
* `MIICOMMAND` is always written **absolutely**, never read-modify-write: bit 0
  (SCANSTAT) is not self-clearing, and once set it leaves BUSY asserted forever.

**There is no MAC ID or version register.** The ethmac map is `0x000`–`0x054`
and contains none; the phrase in HIO-506 was invented by the test. The third
result word is therefore **`MIIMODER`** (expect `0x00000064`) — an untouched
reset-value witness rather than an invented one. `MODER` (`0x0000A000`) and
`PACKETLEN` (`0x00400600`) are published beside it as two more.

**The scan is hardened.** The library's `ethmac_phy_scan()` accepts anything
that is not `0x0000` or `0xFFFF`, which on a floating line returns a false low
address with total confidence. This one requires all three of: register 2 read
**four times identically**, `PHYID1 == 0x0007`, and **uniqueness across the
bus** — and when they do not hold it says *which* failed, per address, in six
32-bit masks. The only PHY address ever measured on this hardware is 1
(LAN8720, `0x0007C0F1`); it is still scanned for.

**Result codes** (`0x2D00001C` bits `[23:16]`, and mirrored in bits `[23:16]`
of the PHYID1 word):

| code | meaning | what it distinguishes |
|---|---|---|
| `0x00` OK | exactly one candidate, `PHYID1 == 0x0007` | a real, unique LAN8720 |
| `0x01` AMBIGUOUS | more than one address answered `0x0007` | aliasing / a decode fault |
| `0x02` OTHER_ID | one stable non-trivial address, id ≠ `0x0007` | a PHY that is not a LAN8720, or a shifted read |
| `0x03` MULTI_OTHER | several stable non-trivial addresses | bus contention |
| `0x04` UNSTABLE | reg 2 differed across four reads | **the KR260 rotating-garbage signature** |
| `0x05` FLOATING | every address stably `0xFFFF` | nothing drives MDIO — absent or unpowered PHY, or wrong strap |
| `0x06` LOW | every address stably `0x0000` | MDIO held low — a different fault from `0xFFFF` |
| `0x07` TRIVIAL_MIX | only `0x0000` and `0xFFFF` seen, both present | partially driven bus |
| `0x08` TIMEOUT | `MIISTATUS.BUSY` never cleared | **the MIIM block itself is not running** — not a PHY result at all |
| `0xFF` NOT_RUN | no scan was run by the loaded image | a stale result, refusing to look live |

`0xFFFF` and `0x0000` are reported as themselves and never collapsed into
"failed". A timeout is its own class and is never folded into "the PHY did not
answer".

The low 16 bits of the PHYID1/PHYID2 words are always the raw register value,
so HIO-506's `& 0xFFFF` compares something honest. Above bit 16 the same words
carry the verdict, which HIO-506 records raw: **bit 31 set means "this is not a
confirmed PHY"**, `[23:16]` of PHYID1 is the result code, and `[23:16]` of
PHYID2 is the address the values came from (`0xFF` = none). FLOATING,
TRIVIAL_MIX and TIMEOUT all put `0xFFFF` in the low half — "nothing came back"
is what that looks like on the wire — and the status word is what says which of
the three it was.

Context, not this image's problem: MDIO does not currently work on the KR260
boards (all 32 addresses return rotating garbage; PMOD1 is on a bank where
nothing has ever worked). This image will report that as `0x04 UNSTABLE` with
the unstable mask full, which is the correct description of it.

---

## 4. The loader

```
python3 fw_load.py --image build/fpga/fw_heartbeat.bin                 # DRY RUN
python3 fw_load.py --image build/fpga/fw_heartbeat.bin --port /dev/ttyACM0 \
                   --json /tmp/fw_load.json
```

**Without `--port` it is a dry run** and opens no serial port at all. It still
validates the image, builds the burst plan and runs every address guard. That
is the default on purpose: the only way to find out that a plan is wrong should
not be to have already executed it.

What it does, in order:

1. **Validates the image first** (`fw_check.py`). A reset vector without its
   Thumb bit, an ELF passed off as a raw binary, an image too big for the
   memory — all of those upload and verify perfectly and then do nothing, and a
   clean load report would be the most misleading possible result.
2. **Splits into bursts** of at most 4096 bytes (`UPLOAD_MAX_BYTES`). Sizes are
   *levelled*, not "cap, cap, …, remainder": a remainder can be one word, and
   `F` refuses fewer than two for a real reason (`FNcount_down_zero_next` is
   `(x >> 1) == 0` on the parameter, so a count of 0 or 1 fills nothing while
   echoing a clean reply). Levelling makes such a tail unconstructible rather
   than handled — swept over every size from 8 to 20000 bytes in the selftest.
3. **`F`-zeroes each burst's span before uploading it, and proves the zero
   landed.** Without the pre-zero a `U` that wrote nothing still verifies
   against whatever was there — and the case where that bites is the ordinary
   one, reloading the *same* image after a reset, where the stale bytes are
   byte-for-byte what the verify expects. Proving the zero landed is what makes
   the pre-zero more than a gesture.
4. **Uploads via `tier4_5._upload()`** — not a reimplementation. That
   function's count guard is structural: the count is formatted from
   `len(payload)`, command and payload become one byte string, and the count is
   parsed back *out* of that same string and required to equal the bytes after
   the CR. A count that disagrees with its payload cannot be constructed there.
   Reimplementing it here would mean reimplementing the guard, badly.
5. **Verifies every burst** and reports how many words it actually compared
   against how many the image has. `--verify ends` compares only the first and
   last 16 words per burst and *says so* in the summary. A word that could not
   be read is counted as unread, never as a word that matched.
6. **Verifies the final byte explicitly**, with the byte-precise `R1` form.
   `F` and `U` OR their `HRESP` into the error flag only in the loop-continue
   branch, so the last beat of a carpet write is the one place a bus error can
   be dropped — and a word read cannot cover it, because at word size
   `HADDR[1:0]` is forced to `00`.
7. **Reads the vector table back** and prints the initial SP and the reset
   vector, checks the Thumb bit *on the die*, and checks that both words match
   the image. The operator sees what the core will load before anything runs.

**It does not release a CPU, and it cannot.** It issues no `W` at all: every
write it can make goes through `_fill_words`/`_upload`, both gated by
`_check_bulk_write`, which permits eth IMEM and nothing else — so the boot gate
(`0x29000000`) and `SW_RESET` (`0x2A000020`) are unreachable from it.
`_assert_no_release()` re-reads this file before opening the port and refuses to
run if a register-write call has been added; `fw_selftest.py` injects three
different ones and confirms each is caught.

It names every symbol it borrows from `tier4_5` and checks for all of them
**before opening the port**: that module is edited by other sessions while this
runs, and an `AttributeError` discovered halfway through burst 5 of 8 would
leave the target span half written with no report. A rename there stops this
tool at the door, saying which name went.

It also refuses, and exits non-zero: a CPU1 image aimed at `0x10000000` (that is
eth **CPU0**'s IMEM from this port — both cores see their own local IMEM at the
same address, so the two images are not interchangeable), any base inside a
hazard band, and `0x90000000`.

---

## 5. CPU1 delivery verdict

**There is no route from the ADP debug port into CPU1 IMEM today.** The image
is built and correct; it cannot be installed by this loader, and that is a
property of the SoC, not of the loader.

Routes that do **not** work:

* **ADP `F`/`U`** — refused in code (`0x90000000` is deliberately absent from
  `_BULK_WRITE_REGIONS`) and refused for cause. CPU1 is executing out of the
  memory the write would overwrite and cannot be stopped first:
  `.cpu1_bootgate (1'b1)` is tied high at the SoC top, so unlike CPU0 there is
  no hold-in-reset / load / release order available. The only stop is
  `CPU1_SWRST`, which is HZ-5 and resets the whole SoC including the ADP, so no
  upload survives it.
* **ADP single-register writes** — the bulk guard is not what makes this unsafe,
  so word-at-a-time writes are not a loophole. Same live core, same memory.
* **The PS backdoor** (`0x4_0000_0000` → `eth_ss_0`) — reaches CPU0 IMEM, the
  boot-gate register, shared SRAM, mailbox and d2d, but **not** `0x90000000`.
* **DMA-250** (`dmac_0`, reachable from `debug_m`) — mechanically it could copy
  eth IMEM → CPU1 IMEM, but it would still be writing under a live CPU1. No
  improvement on the hazard, and now with an initiator that cannot be aborted.

And the failure mode is the die, not one core: CPU1's PRMU sources the fabric's
HCLK and HRESETn, so a CPU1 that faults on half-overwritten code can take the
fabric, the ADP and HOSTIO itself down — the port that would diagnose it. That
is a power cycle, not a red.

Routes that **do** exist — neither of them a load over the debug port:

* **ASIC: the QSPI flash boot table.** CPU1 is the MASTER and boots
  `stage0_bootrom_chip_core` from its own ROM, which copies the PRIMARY image
  from flash into CPU1 IMEM, **CRC-verifies it**, sets CPU1's REMAP and branches
  into it — having already brought up XiP, published the XiP-WARM handshake and
  released CPU0. Put `fw_cpu1_park.bin` in the PRIMARY (MASTER) slot with the
  right CRC. Nothing writes CPU1 IMEM over ADP at any point, and a parked CPU1
  app is safe here because the ROM does the XiP bring-up and the CPU0 release
  *before* it branches, and the PRMU is hardware.
* **FPGA: bake it into the bitstream.** `CC_IMEM_MEM_FPGA_IMG` plus the
  `SMOKE_REMAP_RELEASE_CPU1` bootrom variant, which releases CPU1 with REMAP
  already set so it fetches its reset vector straight from the preloaded image.
  That is a rebuild, not a load.

So the honest statement for tonight: **the image exists, is 68 bytes, is
correct, and has no delivery route that this port can take.** HIO-508's
permanent refusal names the plan's "park CPU1 in a two-instruction spin loop"
option and observes that loading it needs exactly the write it refuses — this
image is that spin loop, and the observation still stands.

---

## 6. Will a loaded CPU0 image actually run? Check the boot ROM first

This is a separate precondition from loading, and it differs between the two
platforms. **Loading and verifying an image does not mean the core will
execute it.**

| platform | masked eth boot ROM | does an ADP-preloaded IMEM image run? |
|---|---|---|
| KR260 FPGA bits | `smoke_remap` | **Yes** |
| ASIC reticle | `stage0_bootrom` | **No** — see below |

*How that was established.* Counting non-zero words in the 512-word ROM image
discriminates the three candidates: `smoke_remap` 188, `hello_uart` 205,
`stage0_bootrom` 277. The packaged FPGA IP
(`tidelink/imp/fpga/eth_chiplet_ip/src/eth_ss_bootrom.sv`, rebuilt 2026-08-21)
has **188** — smoke_remap, so the 2026-08-09 finding that the bits masked
`hello_uart` is stale and the repackage happened. For the ASIC, `ASIC/common.mk`
names `build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom/` as the
source of the burned code file, that file has **277** non-zero words, and the
reticle extraction recorded 277/512 diffing clean against that same `.bintxt`.
Two independent lines, same conclusion.

* **`smoke_remap`** brings up QSPI XiP, publishes the mailbox handshake, then
  reads SP and the reset PC from the always-mapped IMEM aperture and `bx`es to
  it. It **never writes IMEM**. A preloaded image runs, and because these
  images are linked at `0x10000000` the jump is correct whether or not REMAP
  took.
* **`stage0_bootrom`** is a QSPI flash loader. It waits (bounded) for the
  XiP-WARM flag, then **halts** — prints `'X'` and spins — if `XIP_ACTIVE` is
  clear; otherwise it **copies a flash image over IMEM `0x10000000`** and only
  then CRC-checks it and jumps. So on the ASIC an ADP preload is either never
  executed (the halt path leaves IMEM intact but never branches to it) or
  overwritten (the flash path). **On the ASIC the delivery route for all three
  images is the QSPI flash boot table**, exactly as for CPU1.

If a CPU0 image loads and verifies clean but the sentinel never appears, this
is the first thing to check — it is not a firmware bug.

---

## 7. Loading, releasing, and reading back

Load (does **not** release anything):

```
python3 fw_load.py --image build/fpga/fw_heartbeat.bin --port /dev/ttyACM0
```

The loader prints the environment block for the suite. Release is a **separate
operator decision** — it is HIO-502, it is irreversible (the boot gate is W1S,
cleared only by a power-on reset), and this tool will not do it:

```
A x29000000 ; W x00000004      # NETWORK_CORE_BOOTGATE, bit 2 -- releases CPU0
```

Read back, from the ADP monitor (`R` auto-increments, so re-issue `A`):

| what | command | expect |
|---|---|---|
| it booted at all | `A x2D001FF0 ; R` | `B007C0FE` |
| which image | `A x2D000008 ; R` | `48465702` heartbeat, `48465703` mdio |
| which clock it was built for | `A x2D00000C ; R` | `017D9F50` fpga, `05F5E100` asic |
| it ran `main()` | `A x2D000004 ; R` | `5E27C0DE` |
| it is still running | `A x2D000000 ; R`, wait, repeat | a **different** value |
| MDIO verdict | `A x2D00001C ; R` | `B3` then the result code |
| MDIO PHY id | `A x2D000010 ; R x00000003` | `0007`, `C0F1`, `00000064` |
| the whole MDIO block in one go | `A x2D000010 ; R x00000010` | 16 words |
| fault capture (FAULT=1) | `A x2D000044 ; R` | `00000002` = taken and resumed |

Or let the suite do it — the loader prints exactly this:

```
export HOSTIO_CPU0_IMAGE=.../build/fpga/fw_mdio_probe.bin
export HOSTIO_FW_HEARTBEAT_ADDR=0x2D000000
export HOSTIO_FW_SENTINEL_ADDR=0x2D000004
export HOSTIO_FW_SENTINEL=0x5E27C0DE
export HOSTIO_FW_MDIO_RESULT_ADDR=0x2D000010
# FAULT=1 heartbeat only:
export HOSTIO_FW_FAULT_ADDR=0x70000000
```

---

## 8. Files

```
fw_abi.h          the ABI, and the ONLY copy of these numbers
fw_abi.py         parses fw_abi.h -- does not restate it
fw_rt.h           the freestanding runtime the CPU0 images share
fw_start.c        vector table, reset, .bss zeroing, the resuming HardFault handler
fw_heartbeat.c    image 2
fw_mdio_probe.c   image 3
fw_cpu1_park.S    image 1 (pure assembly, no C runtime at all)
fw_link.ld.in     one linker template, preprocessed into two geometries
fw_check.py       validates a built .bin -- reads the vector table OUT OF THE BINARY
fw_load.py        the loader
fw_selftest.py    49 mutation checks, no hardware
Makefile          make [TARGET=fpga|asic] [FAULT=0|1] / check / selftest / clean
```

Nothing under `hostio_suite/` is modified. `fw_load.py` *imports*
`tier4_5`/`harness` and reuses their transport and address guards unchanged.

---

## 9. What is not done

* **Nothing here has touched hardware.** No serial port was opened, no board
  and no host was reached. Every image is validated statically and by
  disassembly; the loader is exercised only in dry-run and by the selftest.
  The `F`/`U`/verify sequence has never been run against a die by this tool.
* **The CPU1 image has no delivery route this port can take** (section 5).
* **On the ASIC, neither CPU0 image can be delivered over ADP either** — the
  masked ROM is the flash loader (section 6). The FPGA path is the one that
  works today.
* **`--verify ends` is untested against real link behaviour**; only its
  comparator is unit-tested. `full` is the default.
* The deliberate fault uses a **read**. If a fabric build captures only writes,
  it is a one-line change, flagged in `fw_heartbeat.c`.
* `FW_SPIN_1MS` is a spin-count estimate at ~4 cycles/iteration, not a
  calibrated delay. Nothing depends on it to better than a factor of a few.
