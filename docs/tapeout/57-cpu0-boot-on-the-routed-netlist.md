# CPU0 boots on the routed netlist — the measurement, and what the verdict must assert

*Revision of the 2026-08-19 design note. **World (a) is no longer prospective:
CPU0 has left reset and fetched its own mask ROM on `fp1505`, with a flash
device attached and no testbench force.** Nothing in this page is applied — the
bench, the `Makefile`, `ASIC/gls-netlist/flash/` and `ci/signoff.yaml` are owned
elsewhere. The drafts are in `ASIC/gls-netlist/docs/proposed/`.*

| | |
|---|---|
| draft signoff stage | [`ASIC/gls-netlist/docs/proposed/signoff-gls-netlist.yaml`](../../ASIC/gls-netlist/docs/proposed/signoff-gls-netlist.yaml) |
| draft bench | [`ASIC/gls-netlist/docs/proposed/eth_chiplet_fp1505_cc_handshake.json`](../../ASIC/gls-netlist/docs/proposed/eth_chiplet_fp1505_cc_handshake.json) |
| proof harness | [`ASIC/gls-netlist/docs/proposed/prove_draft.py`](../../ASIC/gls-netlist/docs/proposed/prove_draft.py) |
| fixtures | `ci/fixtures/gls-netlist/` (+ `mode-fetch/`, `mode-full/`) |

> **Why this page is in `docs/tapeout/` and not beside the bench.** The first
> draft lived at `ASIC/gls-netlist/docs/60-cpu0-boot-assertion-design.md`, in a
> directory that holds nothing else, has no index, and is not reachable from
> [`00-index.md`](00-index.md). Its subject is now a **measured property of the
> shipping netlist** — the same class as [13](13-lec.md), [44](44-eth-rom-sim-divergence.md)
> and [53](53-gate-promotion-plan.md) — so it belongs in the numbered series a
> tapeout reader actually reads. The `proposed/` drafts stay where they are:
> `prove_draft.py` resolves the repo root as `HERE.parents[3]`, and they are
> paste sources for files owned by other sessions, not documentation.

---

## 0. What changed since the first draft

Five measurements, all taken 2026-08-19, all after that draft was written.

| # | finding | where it is measured |
|---|---|---|
| 1 | **CPU0 boots for real** — and it is a *verified* boot, not the blank-flash release: both cores' post-CRC stores land | [evidence §A](evidence/57-cpu0-boot-verdicts.md), §2 |
| 2 | **`chip_core_remap_ctrl_w` is unobservable in the routed netlist** — three of its four bits have no driver at all, so the bus traces as `0xZ` even at the instant the bootgate rises, and two shipped assertions were false reds | netlist census + [evidence §A](evidence/57-cpu0-boot-verdicts.md); §4 |
| 3 | **Run time is a free discriminator** the draft did not have: forced and unforced differ by **916×** | §7.1 |
| 4 | The stage's real defect is worse than "it only asserts `cc_rom`": it **green-lights a published `RESULT FAIL`** today | §1 |
| 5 | `sim.log` was never collected — and meanwhile the toolkit **landed a force census inside `verdict.txt`**, which changes what the check should read first | §7.2 |

The two-world fallback is kept but **demoted**: world (a) is the shipped path
and world (b) is history (§10).

> **Read §11 before checking any path in this page.** The published evidence
> directory was rewritten twice on 2026-08-19 while this was being written, and
> one of the two rewrites made the earlier run un-rebuildable from the tree. The
> bytes every number here comes from are captured verbatim in
> [`evidence/57-cpu0-boot-verdicts.md`](evidence/57-cpu0-boot-verdicts.md);
> the build paths are named for provenance, not for re-reading.

---

## 1. The measured defect in the stage as it stands

Not "the eth half is ungraded". **The stage returns success on a run that
published a failure.**

`ci/signoff.yaml`'s `gls-netlist` check globs every published verdict and, for
each, asserts exactly four keys:

```
for k in cc_rom.content cc_rom_port.accessed cc_rom_msp_on_Q cc_rom_rstvec_on_Q; do
```

`ASIC/eth-chiplet/build/full-20260814/reports/gls/full0814_cc/verdict.txt`
(identical copy at `build/gls-netlist/full0814_cc/verdict.txt`) reads:

```
eth_rom_port.accessed FAIL accesses=0 xdata=0
eth_rom_port.data_nonx FAIL accesses=0 xdata=0
eth_rom_msp_on_Q FAIL never
eth_rom_rstvec_on_Q FAIL never
RESULT FAIL pass=10 fail=4
```

All four keys the check asserts are `PASS` in that same file. So the gate
**passes a run whose own RESULT line says FAIL**, and prints its `RESULT FAIL`
into the log on the way past. That is not a coverage gap; it is a gate whose
verdict contradicts the artefact it is reading. Fixture: `fail-eth-rom-red`.

The second half of the same defect is that the check never opens `sim.log`, and
`sim.log` was **not in `artifacts:`** — so a packaged bundle could not answer
"was anything held?" about its own PASS. §7 and the draft's `artifacts:` list
close that.

---

## 2. CPU0 boots — and exactly what that settles

### 2.1 The measurement

`ASIC/eth-chiplet/build/fp1505/reports/gls/fp1505_cc/`, written 2026-08-19
11:20 — **since overwritten in place**; the capture is
[evidence §B and §D](evidence/57-cpu0-boot-verdicts.md):

```
eth_rom_port.accessed  PASS accesses=12504 xdata=0
eth_rom_port.data_nonx PASS accesses=12504 xdata=0
eth_rom_msp_on_Q       PASS at=3179430000
eth_rom_rstvec_on_Q    PASS at=3179450000
RESULT FAIL pass=14 fail=2
```

and in the `sim.log` beside it:

```
$ grep -c GLSN-FORCE sim.log
0
GLSN-FLASH: gls_netlist_tb.u_qspi_flash loaded image "qspi_flash_image.hex"
```

Against the forced run of the previous evening
(`build/gls-netlist/fp1505_cc/verdict.txt`, `RESULT PASS pass=14 fail=0`, also
overwritten since — [evidence §B](evidence/57-cpu0-boot-verdicts.md)):

| | forced | real | ratio |
|---|---|---|---|
| first `eth_rom` MSP fetch | `at=3470000` ps (3.47 µs) | `at=3179430000` ps (3.179 ms) | **916×** |
| `eth_rom_port.accessed` | 2,602 | 12,504 | 4.8× |
| `cc_rom_port.accessed` | 2,857 | 15,313 | 5.4× |
| `cpu1_dmem_write.accessed` | 245 | 510 | 2.1× |

3,179,430,000 ps at the bench's 20 ns reference period (`clocks[0].period_ns`
in the spec) is **158,971 cycles**. An independent estimate from RTL cycle
counts predicted ~162,700; the measurement is 2.3 % under it.

### 2.2 What it settles

* CPU0 came out of reset **because the design released it**. There is no force
  in the run, and `sim.log` line 5 of the follow-up run carries the toolkit's
  new unconditional census, `GLSN-FORCES: 0 no testbench override was applied
  in this run`.
* CPU0's ROM path in these gates is real end to end: 12,504 accesses,
  `xdata=0`, both vector words on `Q`.
* CPU1 got far enough to do QSPI I/O: the flash device was addressed (§2.4).

### 2.3 What the published run does **not** settle — and the follow-up that does

That published run asserts **only** the ROM ports and vector words. It carries
no copy rung and no CRC rung, so on its evidence alone the release could be
either of CPU1's two writes of `0x4` — the success path (`main.c:383`) or the
**unconditional all-candidates-failed path** (`main.c:403`, §3). Those are S4
and S2 in the ladder of §8 and **they are identical at the bootgate**. A
`RESULT` line quoted from the 11:20 run cannot tell you which.

So a second run was taken on the same netlist and the same flash image, with
the copy, strobe and post-CRC rungs added
(`RESULT FAIL pass=28 fail=4`; verdict and transcript captured verbatim as
[evidence §A](evidence/57-cpu0-boot-verdicts.md)). It settles it as **S4, a
verified boot of both cores**:

| rung | measured | what it proves |
|---|---|---|
| `qspi_xip_active_latched` | 64.970 µs | XiP came up; CPU1 did not take its silent `halt()` |
| `ipc_slot1_warm_word` | 72.710 µs | `0xD15C0001` reached IPC slot-1 storage |
| `cpu1_imem_write.accessed` | **220** writes | CPU1 copied its own image out of XiP — 220 words × 4 B = the 880 B `SLOT_A` |
| `remap_write_strobe` | 3.179210 ms | the remap block registered a bus write |
| `remap_ctrl_bit2_set` | 3.179230 ms | the CPU0 bootgate rose, one 20 ns cycle later |
| `cpu1_remap_after_verified_image_v2` | 3.179410 ms | **CPU1's own CRC passed** — the second write, `0x4` → `0x5`, which `main.c:403` never makes |
| `eth_rom_msp_on_Q` | 3.179430 ms | CPU0 out of reset, fetching |
| `eth_imem_write_after_release.accessed` | **220** writes | CPU0 copied its own image — the 880 B `SLOT_B` |
| `eth_imem_fetch.accessed` | **436,010** reads, `xdata=0` | CPU0 is **executing out of its IMEM**, not just fetching vectors |
| `eth_sysctrl_remap_set` | **5.484510 ms** | **CPU0's CRC passed.** `remap_and_jump()` was reached |

That is the whole chain: CPU1 brings up XiP, publishes the warm word, copies
and CRCs its own image, releases CPU0; CPU0 leaves reset, takes its vectors out
of the mask ROM, copies its image out of warm XiP, CRCs it and remaps. On the
routed netlist, out of these gates, with nothing held.

**Two things in that run are red and neither is a design failure**, which is
exactly why the gate has to be able to say so:

* `cpu0_bootgate_released_by_cpu1_BUS` and
  `cpu1_remap_after_verified_image_BUS` — the two bus-form probes, `FAIL
  never`, for the reason in §4.
* `eth_imem_prestaged` — **0 accesses.** CPU1 never wrote eth's IMEM before
  releasing it. See §5; the pre-stage does not exist in this build and the
  assertion is dropped rather than waived.

### 2.4 One number in circulation that is a log cap, not a count

"60 logged `QSPI_nCS` transactions" is **not** the number of flash
transactions. The trace primitive's `max_log` for `qspi_ncs` is 60, and the
sim.log holds exactly 60 lines ending at 235 µs — i.e. the log stopped, not the
flash. The run continued to 12 ms. This is the same shape as the capped-Calibre
trap: a count that equals its own limit is a limit, not a measurement.

---

## 3. The chain, in the order it actually happens

Worth restating because it is usually recited wrong, and because the timestamps
are now measured rather than assumed. Times are from the run in §2.3.

```
CPU1 (chip_core, MASTER, never gated)          CPU0 (network_core, SECONDARY, held in reset)
──────────────────────────────────────────     ────────────────────────────────────────────
 main() entry marker -> DMEM 0x18000200
 ULBPR 0x98 unlock
 AHB_SPI_SETUP <= 0x0000800B
 CTRL.XIP_ACTIVE <= 1  ── read back, else halt()      measured 64.97 µs
 warm-up read through the XiP aperture
 IPC slot-1 data[0] <= 0xD15C0001                     measured 72.71 µs
 boot-table scan
 pre-stage eth's image into eth IMEM
 copy own image into CPU1 IMEM
 CRC own image
 remap block write strobe                             measured 3.179210 ms
 chip_core_remap_ctrl <= 0x4   ◄── on BOTH the        measured 3.179230 ms
   success path (:383) AND the all-candidates-
   failed path (:403)
                                            reset released; fetch eth_rom[0] MSP  3.179430 ms
 chip_core_remap_ctrl <= 0x5  (own REMAP,     fetch eth_rom[1] rstvec 0x08000189   3.179450 ms
   success path only)          measured 3.179410 ms
                                            branch to word 0x62
                                            wait warm flag, confirm XIP_ACTIVE
                                            copy own image out of warm XiP -> IMEM
                                              220 words, measured
                                            CRC ── fails ⇒ 'X' on UART, WFI forever
                                            set VTOR, store 1 to sysctrl REMAP, jump
                                                          measured 5.484510 ms
```

**The pre-stage step is not in this build.** The recital above, and the first
draft, both had CPU1 "pre-stage eth's image into eth IMEM" before the release.
Measured: **zero** writes to the eth IMEM macro while the bootgate was low, and
220 after it — CPU0 copies its own image and nobody stages it for it. The step
is struck from the chain, not waived.

### The trap: the bootgate write happens on the failure path too

`stage0_bootrom_chip_core/main.c` writes `0x4` **twice**: at `:383` on the
success path, and at `:403` **unconditionally**, after every candidate
*including the golden recovery image* has failed, immediately before `halt()`.
Its own comment says why:

> *Every candidate — including the golden recovery image — failed (e.g. a blank
> / unprovisioned QSPI on a fresh board, the common bring-up case). Still
> RELEASE eth/CPU0 … otherwise a blank flash silently holds CPU0 in reset and
> the debug UART never transmits (the cpu0_bootgate silent-UART bug).*

So **a blank, absent or corrupt flash still releases CPU0**, deliberately.
Three consequences the assertion set is built around:

* **The bootgate rows are *sequence* rungs.** They order the chain and prove
  nothing about it succeeding.
* **The rungs a blank flash cannot fake are the IMEM writes** — there is
  nothing to copy.
* **The rung that separates "copied something" from "copied the right thing"
  is the post-CRC store** — `eth_sysctrl_remap_set` for CPU0, and for CPU1 the
  second remap write that sets bit 0.

The mailbox publish is early — 72.71 µs, more than 3 ms before the release — so
it is not a proxy for "about to release" either.

---

## 4. `chip_core_remap_ctrl_w` is unobservable — and two live assertions are false reds

This kills assertions the first draft designed, and it invalidates two
assertions **already shipping in the bench**. Said plainly rather than dropped
quietly.

### 4.1 The symptom

The bench's own trace on the register prints, in both the 11:20 run and the
follow-up:

```
  GLSN-TRACE:      10000 bootgate_remap_ctrl = 0xZ
  GLSN-TRACE: 3179230000 bootgate_remap_ctrl = 0xZ
```

Line 449 is *the instant the bootgate rises*. The trace fires — something in
the bus changed — and still prints `Z`. It has been printing `Z` since the
probe was written; nobody read it.

Note the capital. IEEE 1364 `%h` prints lower-case `z` when **every** bit of the
nibble is `z` and **upper-case `Z` when only some are**. So `0xZ` is not "the
whole register is floating"; it is "part of it is".

### 4.2 The cause, from the netlist

In `build/gls-netlist/fp1505_cc/nanosoc_eth_chiplet_pads_pnr_pgc.v` (module
`nanosoc_multicore_soc_…`, i.e. the `u_soc_u_soc` instance):

```
398492:   wire [3:0] chip_core_remap_ctrl_w;
533608:   DFCNQD1 \u_chip_core_remap_0_remap_q_reg[2]  (...
533611:        .Q(chip_core_remap_ctrl_w[2]),
```

and `chip_core_remap_ctrl_w[0]`, `[1]` and `[3]` **appear nowhere else in the
file** — not as a driver, not as a load. The four flops all exist; the other
three drive the *readback* path instead:

```
501988: \u_chip_core_remap_0_remap_q_reg[0]  .Q(chip_core_remap_0_hrdata[0])
613894: \u_chip_core_remap_0_remap_q_reg[1]  .Q(chip_core_remap_0_hrdata[1])
600533: \u_chip_core_remap_0_remap_q_reg[3]  .Q(chip_core_remap_0_hrdata[3])
```

`cpu1_bootgate` is tied `1'b1` in `nanosoc_multicore_soc.sv`, so bit 1's control
fan-out is dead; bits 0 and 3 likewise have no control load. P&R kept the bus
name on the one bit that still drives something and gave the rest of the
register's outputs the `hrdata` net name. The declaration survives as a
`wire [3:0]`; three quarters of it is dangling. **That is the whole of the
"unobservability" — it is a net-naming outcome, not a missing register.**

### 4.3 What it invalidates, by name

The shipped spec (`ASIC/gls-netlist/bench/eth_chiplet_fp1505_cc.json`, and the
copy that produced the 11:20 evidence) declares two expects **on the 4-bit
bus**:

| key | expect | status |
|---|---|---|
| `cpu0_bootgate_released_by_cpu1` | `chip_core_remap_ctrl_w === 4'b0100` | **unsatisfiable by construction** |
| `cpu1_remap_after_verified_image` | `chip_core_remap_ctrl_w === 4'b0101` | **unsatisfiable by construction** |

Both are `FAIL never` in the published verdict, and both are **false reds**:
three of the four bits are `z`, so a `===` against a fully-defined 4-bit
literal can never match, whatever the design does. `RESULT FAIL pass=14 fail=2`
is therefore **not** evidence that the handshake failed. It is evidence that
two probes cannot see.

From the first draft, `remap_ctrl_bit2_set` and `remap_write_strobe` were the
two rungs at risk. Measured verdict:

* **`remap_write_strobe` survives untouched.** Its probe is
  `u_chip_core_remap_0_wr_en_q`, a scalar with a real driver
  (`DFCNQD1 u_chip_core_remap_0_wr_en_q_reg`, netlist line 501994, `.Q` at
  501997). Nothing about the bus affects it.
* **`remap_ctrl_bit2_set` survives, because it was already bit-scoped.** The
  draft probed `chip_core_remap_ctrl_w[2]`, not the bus. That single bit is the
  one bit that kept its driver.

So nothing in the draft's assertion list is dropped for unobservability. What
must change is **the bench's two shipped keys**, and the fix is a re-source,
not a deletion.

### 4.4 The re-source, measured

A probe run on the same netlist and the same flash image, with the bus form and
the bit form declared side by side ([evidence §A](evidence/57-cpu0-boot-verdicts.md)):

```
GLSN-FORCES: 0 no testbench override was applied in this run
GLSN-TRACE:      10000 bootgate_remap_ctrl = 0xZ     <- 4-bit bus, before
GLSN-TRACE:      10000 bootgate_bit2       = 0x0     <- bit 2, before
GLSN-TRACE: 3179230000 bootgate_remap_ctrl = 0xZ     <- 4-bit bus, AT THE EVENT
GLSN-TRACE: 3179230000 bootgate_bit2       = 0x1     <- bit 2, AT THE EVENT
```

Same instant, same register, one probe blind and one exact. And the expects:

| replacement key | probe | measured |
|---|---|---|
| `remap_ctrl_bit2_set` | `…chip_core_remap_ctrl_w[2] === 1'b1` | satisfied `at=3179230000` |
| `remap_bit2_at_flop_q` | `…\u_chip_core_remap_0_remap_q_reg[2] .Q === 1'b1` | satisfied `at=3179230000` |
| `remap_write_strobe` | `…u_chip_core_remap_0_wr_en_q === 1'b1` | satisfied `at=3179210000` |
| `cpu1_remap_bit0_set` | `…\u_chip_core_remap_0_remap_q_reg[0] .Q === 1'b1` | satisfied `at=3179410000` |
| `cpu1_remap_after_verified_image_v2` | `{…reg[0].Q, …ctrl_w[2]} === 2'b11` | satisfied `at=3179410000` |
| `qspi_xip_active_latched` | `…u_qspi_flash_0_u_top_ahb_qspi_XIP_ACTIVE === 1'b1` | satisfied `at=64970000` |
| `ipc_slot1_warm_word` | 32-way concat of `…u_slot1_data_regs[0][31:0]` | satisfied `at=72710000` |

Three things fall out of that table and each is load-bearing.

1. **Prefer the flop instance pin, `\…_remap_q_reg[2] .Q`, over the net.**
   Both read identically here, but the net name is a P&R artefact — it is
   exactly what went missing for the other three bits — while the instance name
   carries the RTL register name through synthesis and placement. A probe
   anchored on the instance pin cannot be silently emptied by the next route.
2. **`cpu1_remap_after_verified_image` is recoverable, not dead** — it comes
   back as `cpu1_remap_bit0_set` + `cpu1_remap_bit0_and_bit2`. Its
   `4'b0101` asked for bit 0 *and* bit 2 on a bus where bit 0 has no control
   net. Rebuilt as a two-signal concat over the flop pins, it fires — 180 ns
   after the bootgate, on a second write strobe (`remap_wr_en_q` pulses again
   3179390000 → 3179410000). **That second write is the success-path
   signature**: `main.c:383` writes `0x4` then `0x5`, `main.c:403` writes `0x4`
   and halts. It is the rung that separates S4 from S2 on the CPU1 side, and it
   was there all along behind an unobservable probe.
3. **The strobe-to-bit distance is 20,000 ps — exactly one 20 ns reference
   cycle.** The draft's proximity clause (`STROBE_WINDOW_PS = 200000`, ten
   cycles) is confirmed, and so is the fixture correction recorded in
   `ci/fixtures/gls-netlist/PROVENANCE.md`: the strobe is a registered
   write-enable and the bit updates on the next edge. That number was reasoned
   before; it is measured now.

### 4.5 The general lesson, because this will recur

**A name read out of the netlist is not a probe.** Every probe in the first
draft was justified with "read out of `nanosoc_eth_chiplet_pads_pnr_pgc.v`, not
guessed" — and that was true of `chip_core_remap_ctrl_w`, which is declared
there, in the right module, at the right width. Presence of a declaration says
nothing about whether the bits under it are connected. The check that would
have caught it is one line, and belongs in any bring-up of a new probe:

```
grep -c 'chip_core_remap_ctrl_w\[3\]' netlist.v      # 0 -> the bit is dangling
```

or, at run time, the one the bench already had and nobody read: a trace whose
first line is `Z`.

---

## 5. The assertions

`P = u_dut.u_nanosoc_eth_chiplet_chip_u_soc_u_soc`, `NC = P.u_network_core`.
Probes are at **macro port pins** or at **a named flop's own `Q` pin** — never
at a bus, for the reason §4 just gave, and never on the AHB fabric, because a
bus-level probe can be satisfied by the testbench.

### Tier A — the ROMs hold firmware and CPU1 runs

| assertion | probe | proves | does **not** prove |
|---|---|---|---|
| `cc_rom.content`, `eth_rom.content` | macro array vs the firmware `.bintxt` | both mask ROMs carry the firmware word for word, and it loaded (X counted separately from mismatch) | nothing about execution |
| `cc_rom_port.accessed` / `.data_nonx` | `CCROM.CEN/A/Q` | a core drove this macro's chip-enable and it returned non-X | not *which* core |
| `cc_rom_msp_on_Q`, `cc_rom_rstvec_on_Q` | `CCROM.Q` | the vector-table words came out of the macro | that the CPU consumed them |
| `cpu1_dmem_write.accessed` | `CCDM.CEN & GWEN` | a *store* landed in CPU1's DMEM: a side effect of execution | which store |
| **`cpu1_main_entered`** | `CCDM.CEN==0 && GWEN==0 && A==11'h080 && D==32'h0f1c0de1` | CPU1 executed the **first statement of `main()`** at the macro's own write port | that it got any further |

### Tier B — CPU0 reaches its own ROM

| assertion | probe | proves | does **not** prove |
|---|---|---|---|
| `eth_rom_port.accessed` / `.data_nonx` | `ETROM.CEN/A/Q` | CPU0 is out of reset, clocked, and its ROM path returns non-X | **nothing about how it was released** |
| `eth_rom_msp_on_Q`, `eth_rom_rstvec_on_Q` | `ETROM.Q` | the vector table was read out of the eth macro | as above |
| **`eth_rom_branch_word62`** | `ETROM.CEN==0 && ETROM.A==9'h062` | CPU0 **took** the reset vector: `0x08000189 → byte 0x188 → word 0x62`. Fetching a vector and fetching its target are different events | that anything after the branch executed correctly |

### Tier C — the handshake, split by what each rung can and cannot fake

*Sequence rungs — they place events in order. **None of them is a pass
criterion.***

| assertion | probe | measured | proves | does **not** prove |
|---|---|---|---|---|
| `qspi_xip_active_latched` | `P.u_qspi_flash_0_u_top_ahb_qspi_XIP_ACTIVE` | 64.97 µs | `CTRL.XIP_ACTIVE` latched. CPU1's bootrom `halt()`s here — silent `WFI`, no UART — if it is 0, so a red means everything downstream is dead for *exactly one reason* | that XiP *works*. The bit is `sw=rw hw=r`; it latches what was written |
| `ipc_slot1_warm_word` | 32-way concat of `P.\…u_slot1_data_regs[0][31:0]` | 72.71 µs | CPU1 reached step 3 and the AHB→APB→slot path delivered `0xD15C0001` into storage | **not that CPU0 will be released** — it fires 3.1 ms early |
| `remap_write_strobe` | `P.u_chip_core_remap_0_wr_en_q` | 3.179210 ms | a bus write **reached and was registered by** the remap block | which data; it fires for a write of 0, and on the `:403` failure path |
| `remap_ctrl_bit2_set` | `P.chip_core_remap_ctrl_w[2]` | 3.179230 ms | the CPU0 bootgate is high | **almost nothing.** Set on the failure path too. Never quote it as a boot |
| `remap_bit2_at_flop_q` | `P.\u_chip_core_remap_0_remap_q_reg[2] .Q` | 3.179230 ms | the same event, anchored on the RTL register name rather than a P&R net name (§4.4) | as above |

*Progress rungs — a blank or absent flash cannot produce these, because there is
nothing to copy.*

| assertion | probe | proves | does **not** prove |
|---|---|---|---|
| ~~`eth_imem_prestaged`~~ | `bit2==0 && ETIM.CEN==0 && ETIM.GWEN==0` | **DROPPED — measured 0 accesses.** There is no pre-stage in this build. Kept as a *diagnostic* row (it is the S2 discriminator when a red appears elsewhere), never as a required rung | — |
| `cpu1_imem_write.accessed` / `.data_nonx` | `CCIM.CEN==0 && GWEN==0` on the `rf_16k` (A[11:0]) | CPU1 copied its **own** image out of XiP into its own IMEM — 220 words measured, the rung that distinguishes a real flash from a blank one | that its CRC passed |
| `eth_imem_write_after_release` | `bit2==1 && ETIM.CEN==0 && GWEN==0` on the `rf_32k` (A[12:0]) | CPU0's own word-copy landed **after** release — 220 words measured. Sound because `+define+INITIALIZE_MEMORY` zero-fills `rf_32k` at t=0, so anything non-zero was put there by the design | that the payload is right |
| `eth_imem_fetch.accessed` / `.data_nonx` | `ETIM.CEN==0 && GWEN==1` on the `rf_32k` | CPU0 **read instructions back out of IMEM** — 436,010 accesses, `xdata=0`. This is the rung that says CPU0 is executing its copied image, not merely that it wrote one | which instructions |

*The verification rungs — the load-bearing ones. There is one per core.*

| assertion | probe | proves | does **not** prove |
|---|---|---|---|
| **`cpu1_remap_bit0_and_bit2`** *(re-sourced, §4.4; with `cpu1_remap_bit0_set` as its pair)* | `{P.\u_chip_core_remap_0_remap_q_reg[0] .Q, P.chip_core_remap_ctrl_w[2]} === 2'b11` | **CPU1's CRC passed.** `main.c:383` writes `0x4` then `0x5`; `main.c:403` writes `0x4` and halts. The second write is the discriminator, and it is what separates S4 from S2 on the CPU1 side | anything about CPU0's own image |
| **`eth_sysctrl_remap_set`** | `NC.sys_remap_ctrl[0]`, driven by `NC.\u_apb_periph_u_sysctrl_remap_reg_reg[0]` (netlist 197475/197472) | **CPU0's CRC passed.** eth's stage-0 stores 1 here only from `remap_and_jump()`, reached only after `nanosoc_crc32()` over the copied image matches the boot-table CRC. The only pass-path side effect either ROM produces | **not that the image is the right image.** The ROM compares the copy against a CRC field *from the same flash blob*, so a consistent-but-wrong payload passes. Faithful *transport*, not correct *payload* |
| `eth_uart_first_start_bit` *(diagnostic, non-gating)* | `NC.uart_txd` falling | eth's stage-0 drove its debug UART | **which** byte. `'X'` and the `hello` banner are both UART activity |

**Ordering**, checked from the `at=` fields the verdict already records — no new
bench primitive, no waveform. Every `≤` below is satisfied by the measured run:

```
qspi_xip_active_latched            64.970    µs
  <= ipc_slot1_warm_word           72.710    µs
  <= remap_write_strobe          3179.210    µs
  <= remap_ctrl_bit2_set         3179.230    µs
  <= eth_rom_msp_on_Q            3179.430    µs
  <= eth_sysctrl_remap_set       5484.510    µs

  and on the CPU1 side, concurrently:
  remap_ctrl_bit2_set            3179.230    µs
  <= cpu1_remap_bit0_and_bit2        3179.410 µs
```

A per-rung green with the rungs in the wrong sequence is not a boot. Two
subtleties the pair list has to respect, both of which a naive single chain
gets wrong:

* **CPU1's post-CRC write interleaves with CPU0's first fetch.** It lands at
  3.179410 ms, CPU0 fetches at 3.179430 ms — 20 ns apart, and the order between
  them is not architecturally guaranteed, because the two cores run
  concurrently from the release onwards. So `cpu1_remap_bit0_and_bit2` is
  ordered against `remap_ctrl_bit2_set` and **not** against anything on CPU0's
  side.
* **`cpu1_imem_write` and `eth_imem_write_after_release` have no `at=`.** They
  are `romwatch` rows, and `romwatch` publishes `accesses=` and `xdata=`, not a
  timestamp. They are required to be **green**, and their ordering is carried
  implicitly by the gate condition already built into their `cen` expressions —
  `eth_imem_write_after_release` cannot count anything before the bootgate rises
  because the bit is ANDed into its enable. That is a stronger ordering
  guarantee than a timestamp comparison, and it costs nothing.

---

## 6. What is deliberately **not** asserted, and why

* **`eth_imem.content` (macro array vs a golden image).** The obvious "copied
  the *right* thing" check, and it does not work here. `rf_32k`'s storage is
  `reg [511:0] mem [0:511]` — 512 rows × 512 bits, column-muxed — while the
  ROMs' `rom_via` stores 32-bit words, so a word-oriented golden would mismatch
  every row of a *perfectly copied* image. Doing it properly needs a row-format
  golden through the same de-interleave `scripts/ci/rom_gds_bits.py` does.
  Until that exists, the payload evidence is the ROM's own CRC, with the limit
  stated in §5.
* **A UART decode of `'X'` vs `hello`.** There is **no UART pad** on
  `nanosoc_eth_chiplet_pads` — the port list is SE/CLK/TEST/NRST/SWD/QSPI/
  HOSTIO4_P1/RMII/TL/I2C only — so eth's debug UART is internal or muxed onto
  HOSTIO. The RTL env's success criterion (the banner) has no gate-level
  equivalent, and `expect`/`romwatch`/`trace` cannot decode a serial byte.
  `eth_sysctrl_remap_set` answers the same question structurally.
* **A pass criterion built on the bootgate.** The trap of §3. The bootgate rung
  is still *asserted* — the chain needs it — but the four-state classifier means
  a green bootgate with no IMEM writes reads as S2, not as a boot.
* **A count of eth_rom accesses *before* the release.** `romwatch` has no
  windowing over an arbitrary condition… except that it does, in effect: the
  `cen` field is an expression, and `eth_imem_prestaged` /
  `eth_imem_write_after_release` above are built by ANDing the bootgate bit into
  it. The same trick would give a pre-release ROM-access count. It is not in the
  draft because the release-ordering is already covered by the `at=` fields, but
  it is now cheap and no longer blocked on the toolkit.

---

## 7. The force-is-gone check

The requirement has not changed: **fail if a force is present**, so that a bench
which holds the bootgate cannot pass identically while proving far less. What
has changed is that two of the three layers the first draft needed are now
either measured or obsolete.

### 7.1 Run time is a free discriminator

A forced run reaches `eth_rom_msp_on_Q` at **3.47 µs**; the real one at
**3.179 ms**. That is **916×**, and it is not a tunable — the delay is the QSPI
bring-up plus a boot-table scan plus two 880-byte copies over a serial flash at
a divided clock. Nothing that shortens it leaves the boot intact.

So: **the cheapest possible check that a force is absent is to look at when
CPU0 first fetched.** A bench that forces the bootgate releases CPU0 a few
cycles after reset; a bench that lets the design do it cannot get there in under
a millisecond of simulated time. One `at=` field, already in every verdict file,
already published, no new primitive, and it is immune to somebody editing a log.

The draft asserts it as `EARLIEST_REAL_RELEASE_PS = 1000000` (1 µs is
deliberately three orders below the measured 3.179 ms, so it fails only on the
unmistakable case) with the message naming both numbers. It is a **corroborating**
layer, not the primary one — a force applied late would pass it — which is why
it sits alongside §7.2 rather than replacing it.

### 7.2 The verdict file now carries a force census — read that first

The first draft's §7 asked the toolkit for exactly this. **It has landed.**
`ASIC/asic-toolkit/flow/verify/gls/gen_netlist_tb.py` now documents and emits a
grammar for the verdict file (its own comment, lines ~50–62):

```
<key> PASS|FAIL <detail>       one per check; lower-case key
RESULT PASS|FAIL pass=n fail=n
FORCES <n> <prose>             exactly one, ALWAYS present
FORCE <name> <signal> = <value> : <reason>     one per declared force
```

with the rule that **an upper-case first token is a record about the run and a
lower-case one is a check**. Measured in the §4.4 run, line 1 of `verdict.txt`:

```
FORCES 0 no testbench override was applied; no design signal was held by the bench during this run.
```

Two properties of that design matter to the check and both are deliberate:

* **The zero case is written out.** A gate that concluded "nothing was held"
  from the *absence* of a `FORCE` line would conclude it equally from a verdict
  written before this code existed, from one truncated by a crash, and from one
  produced by a generator where somebody deleted the block. With `FORCES 0`
  always present, **absence means UNKNOWN and only `FORCES 0` means unaided.**
* **It is written first, at time 0**, before the run loop — so a run killed by a
  watchdog or a `SIGTERM` has already published what the bench was holding, even
  though it has none of the check rows.

### 7.3 So the check reads three sources, in a stated order

The draft is written to work whether or not the census is present, because
evidence bundles from before 2026-08-19 do not have it:

| order | source | verdict |
|---|---|---|
| 1 | `FORCES <n>` in `verdict.txt` | **authoritative.** `0` → unaided. `n>0` → the `FORCE` rows name them, matched against `ALLOWED_FORCES` |
| 2 | `GLSN-FORCE: declared <name> -> …` in `sim.log` | used **only** when no `FORCES` line exists. Enough to name a force, not enough to prove absence on its own |
| 3 | neither | **FAIL.** "Not shown" is not "not present" |

**It prefers source 1**, and says so in its own output, for three reasons:
`verdict.txt` is the file the publish step collects and the one a reader opens a
year later; the census is unconditional so its silence is informative; and it
survives a killed run. `sim.log` remains in `artifacts:` regardless — it is the
only place the *application time* of a force is recorded (`GLSN-FORCE: <t>
applied …`), and a force applied after the event it would have faked is a
different thing from one applied at reset.

If both are present and they disagree — a `FORCES 0` next to a `GLSN-FORCE`
line — the draft **fails**, naming the contradiction. Two records of the same
fact that disagree mean one of them is stale, and picking a winner silently is
how a gate ends up quoting the wrong one.

### 7.4 The two experiments that are now historical

Recorded because they cost time and will be re-proposed otherwise.

**(a) Reading the flop's own `Q` port to see through a force. REFUTED.** The
appealing idea: the force is on the net, the flop drives the net, so
`…_reg[2].Q` should still read 0 under it. Built as a faithful miniature of the
real topology (`DFCNQD1` → `CKBD1` → `AO211D1` hold path, the actual cells)
against the real `tcbn65lp_pwr.v`:

```
PRE-FORCE   net=0 cellQ=0 cellD=0 buf=0
FORCED      net=1 cellQ=1 cellD=1 buf=1
VERDICT force-hidden-from-cell-Q: NO
```

VCS coerces the port and the hierarchical read follows the force. `D` follows
too, because the real `AO211D1 g2165` takes its hold term from
`FE_OFN116461_chip_core_remap_ctrl_w_2`, the buffered *forced* net. **There is
no downstream signal that can distinguish.** (This is orthogonal to §4.4's
recommendation to probe the flop pin — that is about *observability*, which the
instance pin wins on; it is not a force-detection mechanism, and never was.)

**(b) `$countdrivers` as an in-sim force detector. WORKS, but is now
unnecessary.** VCS 2022.06-SP2 does report it:

```
BEFORE force: forced=0 val=0
AFTER  force: forced=1 val=1
AFTER release: forced=0 val=0
```

The first draft asked for a `noforce` primitive built on it. **Withdraw that
ask**: the `FORCES` census of §7.2 answers the same question from the
generator's own bookkeeping, needs no per-signal declaration, and cannot be
defeated by forcing a signal nobody thought to list. `$countdrivers` would only
beat it against an adversary who edits the generator, and such an adversary can
delete the `$countdrivers` call just as easily.

### 7.5 The layers that remain, and none is sufficient alone

**Layer 1 — the design's own write strobe, `u_chip_core_remap_0_wr_en_q`.**
It rises only when a bus write reaches the remap block. Is it inside the force's
influence? Measured by parsing the SoC module (41,781 instances, 43,110 driven
nets) and walking the fan-in cone of that flop's `D` pin:

| | cone size | `chip_core_remap_ctrl_w[2]` present? |
|---|---|---|
| depth 1 (one clock of combinational logic) | 3,720 nets | **No** |
| depth 2 (across one more flop boundary) | 17,539 nets | **Yes** |

So the strobe is **immune to the force for one cycle and not beyond it**, stated
as a bound because "CPU0 would never write that register anyway" is exactly the
in-practice reasoning this project distrusts.

**Layer 2 — proximity, from the `at=` fields.** The strobe must rise **with**
the bit. Measured: 3.179210 ms and 3.179230 ms, **20,000 ps apart — one
reference cycle**. The draft's window is 200,000 ps (ten cycles): generous
against a flop-to-flop handoff, tight against 8.8 ms of run. Two failure shapes,
both fixture-proven — bit set with **no strobe at all**, and strobe present but
1.9 ms away.

**Layer 3 — the allow-list of §7.3**, which is the layer that catches a force
placed **somewhere else**: on `wr_en_q` itself to satisfy layer 1, or on
`XIP_ACTIVE` to get past the halt.

**And a fourth, quieter one: the chain itself.** A force injects at exactly one
point. Everything upstream of it — XIP_ACTIVE at 64.97 µs, the warm word at
72.71 µs, CPU1's own 220-word copy — is untouched by it and all of it is
required. A bench that forces the bootgate fails those rungs whatever the gate
can or cannot see about forces.

---

## 8. Four outcomes, not two

`"CPU0 did not boot"` hides four states with four different owners, and — because
the bootgate is written on the failure path too — the bootgate bit cannot
separate them. The gate classifies and **names** the state, and passes only on
S4. All four are fixture-proven.

| state | evidence | meaning | owner |
|---|---|---|---|
| **S0** release not attributable to the design | bit set, `remap_write_strobe` never fired | something outside the design put that bit there — a force, a deposit, a tie | the bench |
| **S1** no release | bit never set | CPU1 reached neither `0x4` write, so it halted before the boot-table scan — suspect XiP bring-up | firmware / QSPI |
| **S2** released, nothing copied | bit set, **no IMEM writes anywhere** | the `main.c:403` unconditional release. A blank/absent flash produces exactly this and **it is not a design failure** | the bench / the flash image |
| **S3** released and copied, not verified | IMEM writes present, `eth_sysctrl_remap_set` never | flash present, payload or copy wrong — expect `'X'` on the UART | the image |
| **S4** boot | every rung green, in order, no override | the real thing — **and this is what `fp1505` measures today** | — |

Two refinements the ladder needs, both of which it would otherwise get wrong:

* **S0 takes priority over the plain walk.** The natural reading of a missing
  strobe is *"CPU1 halted before its release"* — correct when the bit is **0**,
  badly wrong when the bit is **1**. CPU1 halting leaves the bit at 0; a bit
  that rose with nothing writing it came from outside. The message says so and
  ends *"Do NOT read the green `eth_rom` rows below it as CPU0 booting."*
* **An all-green verdict that classifies below S4 is itself a failure.** If
  every declared assertion is green and the state is still S2, the bench is not
  asking enough — *"add the rung that would have been red."*

A fifth state has now been measured and it is not on that ladder, because it is
not about the design at all: **a rung that is red because its probe cannot see.**
§4's two bus-form keys are `FAIL never` in a run that unambiguously did the
thing they assert. The gate carries an explicit `UNOBSERVABLE` list for exactly
these, fails on them with a *different* message — "re-source this probe", not
"the handshake did not happen" — and refuses to let them contribute to the S-state.
Without that, the strongest boot evidence this project has ever produced
classifies as a failure.

---

## 9. The signoff gate

Full text in [`ASIC/gls-netlist/docs/proposed/signoff-gls-netlist.yaml`](../../ASIC/gls-netlist/docs/proposed/signoff-gls-netlist.yaml);
its own header carries the ten-point change list. What matters here is the
shape.

### 9.1 One check, three declared modes

`MODE` is **declared**, never inferred from the evidence — a mode inferred from
the evidence silently *downgrades* the gate the day a force returns, which is
the same silent-regression shape the stage exists to catch.

| MODE | claim | forces | required | other half |
|---|---|---|---|---|
| `fetch_path_only` | the netlist proves CPU0's ROM **fetch path**; the release is supplied by the bench | allow-list non-empty, and a run that declares **none** fails as a stale declaration | Tier A + B | the RTL leg, pinned to the same eth firmware |
| `unforced_fetch` | the design releases CPU0, but the bench does not yet assert the chain | **zero** | Tier A + B, plus the release-time floor | the RTL leg, pinned |
| `full_handshake` | the design brings up XiP, verifies both images and releases CPU0 unaided | **zero** | Tier A + B + C, ordering, proximity, probe pairs, outcome S4 | none — the netlist leg carries it |

The declared mode is **`full_handshake`**, because that is what the netlist now
does. `gate:` stays `report` until the check passes against the **published**
evidence rather than a scratch run.

The ratchet runs in both directions. A lesser mode whose evidence carries every
Tier-C rung green fails with *"promote"*; `full_handshake` with a non-empty
allow-list fails as self-contradictory; and an all-green verdict that still
classifies below S4 fails with *"the bench is not asking enough: add the rung
that would have been red."*

### 9.2 The two clauses that are new in kind

**Probe-form pinning.** A verdict file records a key **name** and a **result**.
It cannot record what expression the probe used — which is exactly how §4 went
unnoticed. So each re-sourced signal is asserted **twice under two names**, and
their `at=` must be **identical**:

```
remap_ctrl_bit2_set   (the net)        }  same flop, so same instant
remap_bit2_at_flop_q  (the flop pin)   }  -- a difference means one is elsewhere
cpu1_remap_bit0_set   (the flop pin)   }
cpu1_remap_bit0_and_bit2 (the concat)  }
```

One re-used name cannot satisfy two keys, and a bus-form probe cannot produce a
matching pair. Fixture: `fail-probe-pair-disagree`.

**"Not declared" is not a design failure.** The gate carries an `SU` state for a
verdict that does not assert the release at all, and a `RETIRED` list for probes
known to be unsatisfiable. Without both, this draft would have done to the
shipped bench exactly what §4 warns about: read a bench gap as *"S1 NO
RELEASE — CPU1 halted before the boot-table scan"*. It said that once, in
development, against a run that had booted perfectly. That is why the state
exists.

### 9.3 What it says on the evidence published right now

Run against `ASIC/eth-chiplet/build/fp1505/reports/gls/fp1505_cc/` as
republished 2026-08-19 12:25 (`RESULT PASS pass=22 fail=0`), the draft is
**red**, with **20** findings, and every one of them is a work item rather than
a diagnosis:

```
  OUTCOME : SU UNCLASSIFIABLE - THE RELEASE IS NOT ASSERTED
  FAIL - THE RUN IS TOO SHORT TO REACH THE RUNG THAT PROVES THE BOOT VERIFIED.
         This simulation ended at 4999990000 ps; CPU0's post-CRC sysctrl REMAP
         store was measured at 5484510000 ps.
  FAIL - qspi_xip_active_latched:  NOT DECLARED   (+ 11 more Tier-C rungs)
  FAIL - ordering … cannot be checked: one of them has no at= timestamp
```

**The run-length finding is the actionable one and it is easy to miss.** The
shipped bench's `run_cycles` is 250,000 — the simulation stops at **5.000 ms**,
and the rung that says CPU0's image *verified* lands at **5.4845 ms**. Adding
`eth_sysctrl_remap_set` without raising `run_cycles` would produce a red meaning
*"the clock ran out"* that reads as *"the CRC failed"*. Raise it first.

### 9.4 Proof

`prove_draft.py` extracts the check **out of the draft YAML** — it does not
carry a second copy — and runs it in `signoff.py`'s own `_sandbox`, in all three
modes, asserting each `MODE` substitution actually took:

```
-- declared MODE=full_handshake (check_proof)   1 must_pass + 17 must_fail
-- rehearsal MODE=unforced_fetch                1 must_pass +  6 must_fail
-- rehearsal MODE=fetch_path_only               1 must_pass +  3 must_fail
DISCRIMINATES -- 29 case(s) over 3 modes, 0 problem(s)
```

Two fixtures earned their place by catching the check rather than the other way
round, and both are recorded in `ci/fixtures/gls-netlist/PROVENANCE.md`:

* `fail-release-too-early` first failed on **ordering** rather than on the
  release-time floor, because only the release rungs had been moved. A fixture
  that fails for the wrong reason proves the wrong clause. Fixed by compressing
  the whole chain, ordering intact.
* the run-length clause first fired under `fetch_path_only`, where a short run
  is *correct* — the forced bench never claimed to reach the CRC. Gated by mode.

---

## 10. The two-world fallback, demoted

World (a) is the shipped path. World (b) is kept only because a bundle written
before 2026-08-19 is in world (b) and must still be gradeable.

### (a) Real handshake at gate level — `MODE=full_handshake`

**What it proves:** on this routed netlist, out of these gates, CPU1 brings up
XiP, publishes the warm word, copies its own image out of XiP, CRCs it, and
releases CPU0; CPU0 leaves reset, fetches its vectors from the mask ROM,
branches, copies its own image out of warm XiP, executes it, CRCs it and
remaps. Measured end to end, §2.3.

**What it still does not prove:** it is not the tapeout netlist (17,231
instances get their supplies completed into a copy — `pg_complete.txt`); it is
not timing (zero-delay, no SDF, cell models older than the Liberty the design
was timed against); the CRC rungs prove faithful *transport*, not a correct
*payload*; and the flash is a bench-supplied model, so everything the boot read
came from the testbench.

### (b) Handshake at RTL only — `MODE=fetch_path_only`

The netlist leg runs with a declared bootgate force and evidences a fetch path;
the handshake is evidenced by
`nanosoc-multicore-system/cocotb/soc_boot_flash`. **Nothing joins them**, and
a reader must not conclude:

1. **that CPU0 boots on the routed netlist.** Two legs on different models of
   the design with an untested joint — the shape of the already-recorded broken
   LEC chain.
2. **that it is the eth firmware on the die.** Measured 2026-08-19:
   `nanosoc-multicore-system/src/rtl/bootrom/eth_ss_bootrom.sv` — the file the
   cocotb flist compiles — differs from the mask ROM contents in **172 of 512
   words**, while the freshly generated `.sv` beside the `.bintxt` in the
   firmware build tree differs in **0 of 512**. The CPU1 half **does** compose
   (`nanosoc_bootrom_chip_core.sv`, 0 of 512). The gate enforces this as a hard
   clause; the fix is a file copy.
3. **that a green suite is a green handshake.** The suite has **20** testcases.
   **Seven** of them reach the testbench backstop `_release_network_core_bootgate()`
   and set `u_chip_core_remap_0.remap_q` themselves; **13** do not. Measured by
   an AST call-graph closure over `test_soc_boot_flash.py`, so it counts the
   tests that reach the backstop *through a helper* as well as the two that call
   it directly:

   | | count | which |
   |---|---|---|
   | reach the backstop | 7 | the six `*_halts` corrupt-image tests, plus `test_s8b_halt_persists_only_when_golden_bad` |
   | do not | 13 | everything else, including `test_network_core_stage0_boot_from_flash` |

   **This corrects the figure the first draft carried.** It said "15 of 20 tests
   observe a genuine CPU1-driven gate write", taken from a feasibility report and
   flagged as not re-derived. The 7 is right; the 15 is not — 13 is the number
   that avoid the surrogate, and *observing a release* is a smaller set again,
   because several of the 13 (`test_remap_reset_default_then_set`,
   `test_xip_first_access_completes_and_latency`) are not boot tests at all. The
   gate therefore names **one testcase** rather than counting green rows.
4. **that the result is current.** `results.xml` and `run.log` are both dated
   **2026-07-18 12:27**, and both bootrom sources changed afterwards (Jul 28 and
   Aug 9). Re-run before quoting.
5. **the `tb_top.sv` header's own caveat.** It says the env "runs as a hybrid:
   IMEM is preloaded via `RAM_PRELOAD`" and cannot do a true stage-0 boot. That
   comment is **stale and contradicted by the run**: no `+define+RAM_PRELOAD` on
   the VCS line, the `sim_build/image.hex` it names does not exist, and the
   Makefile says so at line 49. The env is *better* than its header claims and
   *weaker* than a green suite implies.

---

## 11. The evidence moves under you — two measured cases

Both happened inside three hours on 2026-08-19, while this page was being
written, and both are the reason [`evidence/57-cpu0-boot-verdicts.md`](evidence/57-cpu0-boot-verdicts.md)
holds the bytes rather than the paths.

**The published `fp1505` evidence was rewritten twice.** The 11:20 run
(`RESULT FAIL pass=14 fail=2`) that first showed CPU0 booting was replaced at
12:25 by a corrected bench (`RESULT PASS pass=22 fail=0`), and
`build/gls-netlist/fp1505_cc/verdict.txt` — the forced comparator — was
overwritten in the same window. A page that cites a path rather than the bytes
becomes uncheckable the moment somebody re-runs, and here "somebody" was another
session, working in parallel, correctly.

**The 11:20 run cannot be rebuilt from the tree as it stands.** Its `inputs.txt`
names the model `ASIC/gls-netlist/flash/nanosoc_gls_qspi_flash.v` (sha256
`e31050f1…`), and that file **does not exist any more**: the flash attachment
was reshaped into `ASIC/gls-netlist/flash/gls_flash_attach.sv`, which binds the
vendor `sst26vf064b` into the generated bench instead. At the same time the
toolkit **removed the `devices` primitive** that produced the `DEVICE …` line in
that verdict —

> *"THERE IS DELIBERATELY NO `devices` PRIMITIVE HERE. Read this before adding
> one; it was built, measured and removed on 2026-08-19"* —
> `gen_netlist_tb.py:166`

so a verdict line quoting a bench device is now a record from a mechanism that
is gone. **This is not a complaint about either change** — the `bind` approach
is better, and the census that replaced it is what §7.2 is built on. It is a
statement about what "reproducible" means here: the strongest boot evidence this
project has produced was, for about an hour, un-rebuildable, and only the
captured bytes survived.

### The corrected bench landed independently, and reached the same probe

The 12:25 bench traces the bootgate as `bootgate_cpu0`, a **single bit**, and it
goes `0x0 → 0x1` at `3457630000`. Whoever wrote it hit §4 and fixed it without
this page. Three things follow, and only the first is comfortable:

* The two dead 4-bit-bus expects are **gone from the shipped bench**. §4 is now
  a *root cause* and a *regression guard*, not a live defect. The draft's
  `RETIRED` list keeps them from coming back.
* The bench added three rungs better than what this note had drafted:
  `qspi_flash_addressed` (the S2 discriminator this note listed as unresolved),
  `cpu0_rom_idle_at_1ms` (the pre-release windowing this note said `romwatch`
  could not express), and a `cpu1_imem_fetch` pair. **The draft adopts all three
  by their shipped names rather than renaming them.**
* The bootgate is a **trace, not an expect** — so it still does not reach
  `verdict.txt`, and the published `RESULT PASS pass=22 fail=0` still contains
  no row for CPU0's release. That is the `SU` state of §9.2, and it is the top
  item on the draft's work list.

---

## 12. Things this page could not determine

* **Whether the payload is the right payload.** Each ROM CRCs its copy against a
  field taken from the *same* flash blob, so a consistent-but-wrong image
  passes. Closing it needs a row-format golden for `rf_32k` through the same
  de-interleave `scripts/ci/rom_gds_bits.py` does (§6).
* **The dummy-cycle encoding** for `AHB_SPI_SETUP.AHB_DUMMY_CYCLES`. The RDL
  says "(N-1)", the ROM writes `0x8` commented as "8 dummies", and
  `qspi_flash.h` mentions a "+1 compensation". Three statements, not mutually
  consistent; the SCLK counter was not traced. It cannot be badly wrong — XiP
  demonstrably works — but the three descriptions should be reconciled.
* **Why the two runs' timelines differ.** This page's probe run reaches
  `eth_rom_msp_on_Q` at 3.179430 ms; the 12:25 shipped run at 3.457830 ms, with
  23,919 eth ROM accesses against 12,504. Different flash images
  (`qspi_flash_image.hex` vs `flash_image.hex`) and a 5 ms rather than 20 ms
  run. Both are real boots; the *absolute* numbers in this page belong to the
  probe run, and the 916× ratio and the 20 ns strobe-to-bit distance are the
  parts that should be quoted, because they are ratios and not absolutes.
* **Whether `eth_sysctrl_remap_set` lands before 6 ms on the shipped image.**
  Measured 5.4845 ms on the probe image; the shipped image's chain is 0.28 ms
  later throughout, so ~5.77 ms is the expectation and 6 ms of run would be
  tight. Measure it rather than budgeting from this page.
* **The one-way gating comment in the bench.** `chip_core_remap_ctrl.v` is
  described as holding "each core in reset until the other writes its bootgate
  bit". In this build `nanosoc_multicore_soc.sv` wires `.cpu1_bootgate(1'b1)`,
  so `remap_q[1]` drives nothing and CPU1 is not gated at all — which is also
  why bit 1 has no control net in the routed netlist (§4.2). Flagged rather than
  fixed: the bench is owned elsewhere.
