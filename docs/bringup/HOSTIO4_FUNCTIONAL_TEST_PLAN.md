# HOSTIO4 / ADP Functional Test Plan — nanoSoC Ethernet Chiplet

**Status:** draft for inclusion in the chiplet functional test plan and for use at ASIC bring-up.
**Author basis:** RTL analysis 2026-08-25 + the FPGA measurements of 2026-08-25 supplied with the task. **Revision 2, 2026-08-25 evening: corrected against the executable implementation of this plan and a hardware run — see the box below.**
**Scope:** everything executable over the 7-wire HOSTIO4 port via the ADP monitor. No SWD, no PS backdoor, no firmware unless a test says so.

---

## REVISION 2 — READ THIS BEFORE YOU FOLLOW ANY PROCEDURE BELOW

Revision 1 was written from RTL analysis plus a short FPGA session. It was then **implemented as an executable suite** — `scripts/rig/eth_chiplet/hostio_suite/{tier0,tier1,tier2_3,tier4_5}.py` — and run against real silicon. Implementing it and running it found **ten material errors in this document**. Several of them would have produced confident false greens, or false reds on a perfectly healthy die, at a bench with one part in front of you. This document has a history of being trusted literally, so every correction is marked **`[R2]`** in place and says what Revision 1 claimed and why it was wrong.

**Where this document and the suite disagree, the suite is right.** Each of its tests was adjudicated against the RTL and measured on the die; the corresponding row here was not. If you are at a bench, run the suite; read this for the reasoning.

| # | What Revision 1 said | What is actually true | Corrected in |
|---|---|---|---|
| 1 | `R100` is a 3-digit parameter, i.e. one 16-bit read | **`R100` is a 256-line block dump.** The digit COUNT sets the access size; the parameter VALUE sets the number of reads. Use **`R000`**. | §1.2, HIO-006 |
| 2 | twelve sequences written `A x<addr>` ; `R` ; `W…` (or `R` ; `P…`) | **`W` auto-increments as well as `R`**, so every one of those writes lands at **addr+4**. **HIO-209 wrote ROM word 1 and checked word 0 — it passed on RAM too.** | §1.2, HIO-203/204, HIO-209, HIO-301/302/303/305/306/307/309/312/313, **HIO-502** (the irreversible one), **HIO-504** |
| 3 | HIO-313 passes if the boot gate "did not change" | **A completely dead ADP write path satisfies that perfectly.** The gate authorising the irreversible CPU0 release could not detect the one failure that matters. It now carries a contemporaneous reversible positive control. | HIO-313, §3 C2, §4.3 |
| 4 | `0x2C200040` `P0_CYC` is a live free-running counter | **The readout is a SHADOW**, frozen until `CTRL[0]` SNAP. `CTRL` is write-only and self-clearing. The counters **saturate**, they do not wrap. This broke four tests. | §1.4, HIO-110, HIO-307, HIO-402, HIO-404, HIO-405 |
| 5 | HIO-402 PASSES on "strictly increasing"; HIO-406 reload `0x00010000` | Both criteria are unreachable. HIO-402 compared a frozen shadow with itself and **FAILED on a healthy cold die**; at reload `0x00010000` the timer expires in **0.65 ms**, long before a poll can start through a ~130 ms link, so every count returns 1. | HIO-402, HIO-406 |
| 6 | HIO-002 sends ESC to a port that starts outside the monitor | **ESC is an entry event ONLY** (`FNvalid_adp_entry` is evaluated only in `STD_RXD1`). Inside the monitor it is swallowed as a command letter, returns nothing, and arms a spurious `?` on the next line. It reported ABORT GATE 2 on a healthy die. | HIO-002, HIO-003, §3 A2 |
| 7 | `RESET_INFO` is non-zero on a cold die | **Polarity backwards.** A power-on **clears** it (`nanosoc_reset_ctrl.v:326-331`), and `ext_sysresetreq` is tied `1'b0` on this board so EXTRESET can never set. | HIO-105 |
| 8 | `LINK_CAPABILITIES = 0x00080008`; `evt_route` PID0 = `0x22`; perf-probe ID = `0x50524601` | All three are **specification artefacts the RTL never implemented**. Measured: `0x00000088`, `0x00000000`, `0x50524631`. | §0, HIO-110, HIO-121, HIO-125 |
| 9 | — | **A general warning about `B`-class constants**, which is now the largest single false-red source in this plan and has already fired four times. | §0 |
| 10 | — | **Hardware results recorded** for Tiers 0–4 (Tier 5 deliberately not run), **and the run's one FAIL is a real finding: the PHC does not keep real time — it runs 10× slow.** | §6 |

---

### Summary of findings

1. **`P`, `U` and `F` are real hardware engines, not conveniences.** `P` is a masked-compare poll loop with a bounded budget that runs at `HCLK`, distinguishes match from timeout, and *returns the iteration count at match* — a hardware latency measurement free of link latency. `F` fills a whole RAM in one command. `U` streams raw binary into memory at one link byte per data byte. Together they remove the need for firmware for most of Tiers 1–4. `M`/`V` are their operand registers. **`S` and `C` are not what their names suggest** and are inert at the system level on this SoC.
2. **HOSTIO is alive on a cold die before either CPU's firmware matters.** The fabric clock and reset come from CPU1's PRMU, which is ungated; CPU0 is held in reset at power-on by a boot gate at `0x29000000` bit 2 that **ADP itself can write**. So ADP can preload IMEM and release a CPU — via the AHB, not via GPO.
3. **The reachable address space is narrower than "anything on the AHB matrix".** `debug_m` cannot decode `0x30000000`–`0x7FFFFFFF`, so **the Ethernet MAC and MDIO are structurally unreachable from this port**, as are the eth APB peripherals and the eth REMAP control. Nor can it reach either CPU debug window. §1.4.
4. **ADP is immune to undecoded addresses but not to stalling ones.** There is no `HREADY` timeout anywhere in the FSM. The peer aperture and the TideLink quarantine band can still hang it.

### Contents

| § | |
|---|---|
| 0 | Sources; measured vs. derived; **which configuration each test assumes (ASIC ≠ FPGA)** |
| 1 | Capability analysis — the command set, the P/U/F/M/V/S verdict, the reachable map, hazards, the boot architecture |
| 2 | The test list — Tiers 0–5, 87 tests, each with a DISCRIMINATION column |
| 3 | ASIC bring-up ordering, with abort gates; **and what HOSTIO tells you when SWD returns nothing** |
| 4 | Coverage honesty — throughput, what this port cannot test, and **`[R2]` the six likeliest false greens** |
| 5 | Hardware verification of the *draft*, 2026-08-25 daytime (FPGA) |
| 6 | **`[R2]` Hardware results of the IMPLEMENTED suite, 2026-08-25 evening — Tiers 0–4 run, Tier 5 held; the one FAIL (the PHC runs 10× slow); state readings; what is still open** |

---

## 0. Sources, and what is measured vs. derived

Everything in this document is traceable to one of three classes. Rows in the test tables are marked with the class of their *expected value*, because a test whose expected value is derived from a build artefact can go red for a build reason rather than a silicon reason.

| Class | Meaning |
|---|---|
| **M** | Measured on FPGA 2026-08-25 and supplied as ground truth in the task brief. |
| **R** | Read out of RTL / generated RTL in this repo (file:line given). A hardware constant. |
| **B** | Read out of a *build artefact* (firmware hex, generated memmap, discovery yaml). **Build-dependent** — re-derive per die/per image before use. |

> ### `[R2]` WARNING — NEVER ASSERT A `B`-CLASS CONSTANT. FOUR OF THIS PLAN'S HAVE ALREADY FIRED.
>
> This is the most important thing Revision 2 adds, and Revision 1's own class system already implied it without ever drawing the consequence. **A yaml register map, an RDL file, or a firmware header is a *specification*. The RTL is what was built.** Where a generator does not read the spec, where a hand-maintained map was never reconciled, or where a header describes a different block of the same name, the two disagree **silently** — and the die is right. Four Revision-1 expectations turned out to be exactly that:
>
> | Constant | Revision 1 expected | Silicon reads (**M**) | The artefact that was wrong |
> |---|---|---|---|
> | `evt_route` PID0 @ `0x2B000FE0` | `0x00000022` | `0x00000000` | `sys_desc/register_maps/evt_route_ctrl.yaml:27` — the block has **no CoreSight ID space at all**, and `0x…FE0` is an **alias**, not an unmapped address. HIO-125. |
> | `LINK_CAPABILITIES` @ `0x2E030200` | `0x00080008` | `0x00000088` | `tidelink/src/rdl/wlink_regs.rdl:269,274` declares two 16-bit fields; the RTL is generated from **Chisel**, which never reads the RDL. HIO-121. |
> | perf-probe ID @ `0x2C200000` | `0x50524601` | `0x50524631` | `firmware/include/perf_probe.h:40-44` describes a **different block**. `ctrl_ahb_perf_probe_regs.v:72` has `0x50524631`. HIO-110. |
> | `RESET_INFO_CPU0/1` @ `0x2A000010/14` | non-zero on a cold die | `0x00000000` | not a spec file but the same failure of reconciliation: **the polarity was read backwards.** A power-on *clears* the record. HIO-105. |
>
> **The rule that follows: a `B`-class expected value is RECORDED and CLASSIFIED, never asserted.** State which artefact the reading agrees with. A `B`-class row that goes red is a documentation finding until proven otherwise on the RTL. Asserting one blind costs the most expensive kind of red there is — **a good die failed by a bad expectation**, which is how HIO-105, HIO-110, HIO-121 and HIO-125 all behaved on their first hardware run.
>
> **Constants in this plan that are STILL `B`-class — build-artefact-derived and NOT yet verified against instantiated RTL. Treat every one as record-and-classify:**
>
> - **HIO-101** eth boot-ROM vector-table anchors — `build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom/stage0_bootrom.hex`. Only `[0] = 0x18003c00` is **M**. The structural back-stop in that row (alignment, Thumb bit, in-range) is the part that is sound with no golden file.
> - **HIO-102** the two `+0xE4` discriminator words (`0x08000678` / `0x0800048c`) — same hex artefact. The *test* (the two ROMs must differ at `+0xE4`) is sound; the two literal values are not.
> - **HIO-119** the whole discovery-table header (`SOCD`, version, `TABLE_SIZE`, `INTERCONNECT_NAME`) — `build_soc/discovery/*.yaml`. Its base address is **still unresolved in the built RTL**, so the test SKIPs. See §6.
> - **HIO-308 / HIO-507** the `bus_fault_monitor` **register offsets** and the initiator-index map (0 `eth_ss_m`, 1 `cpu_ss_1_m`, 2 `dmac_0_m`, 3 `dap_ss_0_m`) — `firmware/include/bus_dbg.h:11-13`. **The `BFM1` magic itself is now `R`-class** (`src/rtl/wrappers/bus_fault_monitor.v:282`); the offsets around it are not.
> - **HIO-412** every DMA-250 channel offset, start bit and done bit — `dma250_regdef.h`. Unresolved; the test stays NOT-YET-EXECUTABLE.
> - **HIO-414** the boot-confirm token `0xB007C0FE` — `firmware/include/nanosoc_boot_confirm.h:73-74`. It is written by *firmware*, so it is doubly build-dependent.
> - **HIO-309** the `NS_INCR` reset value — RDL default 4, and **the chiplet override was never located**. Read-then-restore; never write it blind.
>
> **`[R2]` Upgraded from `B` to `R` since Revision 1** — each confirmed against the instantiated RTL while implementing the suite, so these may now be asserted: **HIO-108** `BFM1` = `0x42464D31` (`bus_fault_monitor.v:282`), **HIO-109** `ETC1` = `0x45544331` (`src/rtl/wrappers/etc_capture.v:104`), **HIO-111** IPC `PERIPH_ID` = `0xC0DE0001` (`ipc_mailbox_apb_regs.sv:29`, served from slot `6'd13` at `:286`), **HIO-110** perf-probe ID = `0x50524631` (`ctrl_ahb_perf_probe_regs.v:72`, and **M**).

Primary sources:

- ADP monitor FSM: `/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/nanosoc-multicore-system/nanosoc_arch_tech/rtl/socdebug_tech/controller/verilog/socdebug_adp_control.v` (746 lines)
- ADP wrapper: `.../socdebug_tech/controller/verilog/socdebug_ahb.v`
- HOSTIO4 link: `.../nanosoc_arch_tech/rtl/hostio4/soc_rtl/hostio4_controller_fsm.v`, `.../README.md`
- SoC integration: `/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/nanosoc-multicore-system/build_soc/rtl/nanosoc_multicore_soc.sv`
- Matrix decode for the ADP master: `.../build_soc/rtl/multicore_ahb_interconnect/multicore_ahb_interconnect/multicore_matrix_decode_DEBUG_M.v`
- Ethernet-subsystem decode: `.../build_soc/rtl/eth_ss_ahb_interconnect/eth_ss_ahb_interconnect/eth_ss_matrix_decode_ETH_SS_0.v`
- CPU1 subsystem decode: `.../build_soc/rtl/nanosoc_cpu_ss_ahb_interconnect/nanosoc_cpu_ss_ahb_interconnect/nanosoc_cpu_ss_matrix_decode_CPU_SS.v`
- Reset/boot gate: `.../nanosoc_arch_tech/rtl/src/regions/reset_ctrl/nanosoc_reset_ctrl.v`, `.../src/rtl/wrappers/chip_core_remap_ctrl.v`
- D2D sub-decode: `/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/src/rtl/chiplet_d2d_decode.sv`
- Client: `/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/scripts/rig/eth_chiplet/hostio_adp.py`

### 0.1 Which configuration each test assumes

**The ASIC is not the FPGA.** Three differences are already known and they change what a "correct" answer is:

| | FPGA (where the 2026-08-25 measurements were taken) | ASIC (what you will bring up) |
|---|---|---|
| TideLink ECC | active | **bypassed** |
| TideLink CRC | `disable_crc = 1'h1` → **OFF** | `disable_crc = 1'h0` → **ON at reset** |
| FCSM recovery | present | **stripped** |

Consequences for this plan, stated once so no test has to re-argue them:

- **Tiers 0, 1 (except the TideLink block), 2, 3 (except TideLink) and 5 are configuration-independent.** The ADP monitor, the matrix decode, the memory map, the RAMs, the boot gates, the reset controller, the CMSDK peripherals and the boot ROMs behave identically. Every `M`-class value quoted in those tiers transfers.
- **Every TideLink test — HIO-121, HIO-122, HIO-310, HIO-407, HIO-408, HIO-409, HIO-413 — is written against the FPGA configuration** because that is where the reference values were measured. On the ASIC:
  - `0x2E0321F8` and `0x2E0321E0` **marker bytes** (`0xB5`, `0xAD`) are structural and transfer. The **status bits below them may legitimately differ**, so on first ASIC silicon treat HIO-409 as *record-and-classify*, not as a golden compare, until an ASIC baseline exists.
  - **CRC being ON at reset changes link bring-up behaviour**, so HIO-408's time-to-`calibration_done` and HIO-407's FCSM trajectory are not expected to match the FPGA numbers. Record the ASIC values as the new baseline; do not fail a die for differing from an FPGA figure.
  - **FCSM recovery being stripped means a link that enters a bad state will not self-heal.** HIO-407's `fcsm = 1` / `fcsm = 2` signatures are therefore *terminal* on the ASIC where they might have been transient on the FPGA. Budget a power cycle rather than a retry.
- **Every test in this document states its class (`M`/`R`/`B`) in its own row**, and `M`-class TideLink values carry the caveat above. `R`-class values come from RTL that is common to both builds unless the row says otherwise.

---

## 1. Capability analysis

### 1.1 What ADP is

`socdebug_adp_control` is an ASCII command monitor with its own **AHB-Lite master port**. On the eth chiplet that port is the interconnect initiator **`debug_m`** on the *multicore* matrix (`nanosoc_multicore_soc.sv:1544-1587`, initiator index 4 in `build_soc/discovery/multicore_ahb_interconnect_discovery.yaml`). It is not attached to a CPU, needs no firmware, and works with both CPUs halted or held in reset.

The bus interface is fixed (`socdebug_adp_control.v:329-341`):

| Signal | Value | Consequence |
|---|---|---|
| `HPROT` | `4'b0011` | privileged, data, **non-bufferable, non-cacheable** — read-after-write is coherent |
| `HBURST` | `3'b001` (INCR) | always, even for a single beat |
| `HTRANS` | NONSEQ only | never SEQ; every beat is a fresh address phase |
| `HMASTLOCK` | 0 | ADP never locks the bus |
| `HADDR[1:0]` | forced to `00` for word size (`byteaddr`, line 331) | **a misaligned word access cannot be generated** |

### 1.2 The command set, exactly

Parsed by `FNvalid_cmd` (`socdebug_adp_control.v:87-121`). Case-insensitive.

| Cmd | State reached | What it does |
|---|---|---|
| `A [hex]` | `ADP_ACTION` :551 | with param: set address. without: **report** current address. |
| `C [hex]` | `ADP_SYSCTL` :554-566, :674 | GPO8 register: `0x000001xx` clear bits, `0x000002xx` set, `0x000003xx` overwrite, no param = report. Read returns `{GPI8, GPO8, param[15:0]}`. |
| `R [hex]` | `ADP_READ` :567 | bus read at address, **address auto-increments**. With a non-zero param it **repeats that many times** (`ADP_LINEACK2` :727-729) — a block dump. **`[R2]` The parameter does TWO jobs at once: its digit COUNT sets `HSIZE`, its VALUE sets the repeat count. See the second trap below.** |
| `S [hex]` | `ADP_SYSCHK` :664 | push `param[7:0]` into the SoC-side USRT **STDIN** FIFO; `!` if that FIFO will not accept. Not a "self test". |
| `W <hex>` | `ADP_WRITE` :574 | bus write at address, auto-increment. **`[R2]` `W` auto-increments too — ten of Revision 1's literal sequences forgot this. See the third trap below.** |
| `X` | `ADP_EXIT` :576 | leave the monitor into the transparent STDIO bypass. ESC (0x1b) re-enters. |
| `F <hex>` | `ADP_FCTRL` :663 / :645 | **block fill**: write the `V` register to `<count>` successive addresses. |
| `M [hex]` | :583 | set / report the 32-bit compare **mask**. |
| `P <hex>` | `ADP_POLL0` :587 | **masked-compare poll loop**, up to `<count>` iterations. |
| `U <hex>` | `ADP_UCTRL` :578 / :633 | **binary upload**: stream `<count>` raw bytes from the link straight into memory. |
| `V [hex]` | :590 | set / report the compare **value** (and the fill datum for `F`). |

**The access-size rule — the single most important formatting trap.** The parameter's *hex-digit count* sets `HSIZE`, via `FNsize_inc` (:143-154) feeding `FNparam2size` (:156-167). An `x`/`X` prefix, a space or a tab **zeroes the digit count** and starts a fresh parameter (:171-175).

| Hex digits in param | HSIZE |
|---|---|
| none | 32-bit (default) |
| 1–2 | **8-bit** |
| 3–4 | **16-bit** |
| 5 or more | 32-bit |

> **Rule for every test in this plan: always write parameters as `x` + exactly 8 hex digits.** `W FF` is a *byte* write of 0xFF; `Wx000000FF` is a word write. This applies to `A`, `R`, `W`, `P`, `V` and `M` alike — including `P`, whose count parameter silently sets the size of the poll's read.

**`[R2]` The second formatting trap, and it is worse than the first: for `R`, the digit COUNT sets the access size and the parameter VALUE sets the NUMBER OF READS.** The two are independent and the same characters do both jobs at once — `adp_count <= adp_param` (:536) and the `ADP_LINEACK2` repeat arm (:727-729). So a parameter you wrote purely to reach a digit count also runs that many bus transactions. **MEASURED 2026-08-25:**

| Command | Lines returned | Nibbles per line | Address advances by | HSIZE |
|---|---|---|---|---|
| `R` | 1 | 8 | `+4` | 32-bit |
| `R1` | 1 | 2 | `+1` | 8-bit |
| `R000` | 1 | 4 | `+2` | 16-bit |
| `R010` | **16** | 4 | `+0x20` | 16-bit |
| `Rx00000004` | **4** | 8 | `+0x10` | 32-bit |

> **Revision 1's HIO-006 reached for `R100` purely to get a three-digit parameter. That is a 256-line, 256-transaction block dump** (`0x100` halfword reads), not the single 16-bit read the test wanted. **The correct form is `R000`** — the identical digit-counter path with a count of zero: one line, one bus read, same 16-bit size. The repeat arm is HIO-009's subject, not HIO-006's.

**`[R2]` The third trap: `R` AND `W` BOTH auto-increment — and twelve of Revision 1's literal command sequences got it wrong.** The `R` and `W` rows above both said so, and ten sequences in Tiers 2 and 3 were nevertheless written `A x<addr>` ; `R` ; `W…`, which puts the write at **`addr+4`** — plus **HIO-502**, the one irreversible action in the plan, and **HIO-504**, whose `P` inherited the wrong poll address. Every affected row below is corrected in place and carries an `[R2]` note naming where its write actually landed. **The worst was HIO-209 (ROM write-protection): it wrote ROM word 1 and then checked that word 0 was unchanged, so it passed unconditionally on RAM as well as on ROM** — a vacuous green in the one test whose entire value is that it can fail.

> **The rule that follows, and it governs every sequence in this document: re-issue `A x<addr>` before EVERY access.** Never let an access inherit the address of the one before it. The only exceptions are HIO-008 and HIO-009, whose subject *is* the increment, and the block engines `R<n>`/`F<n>`/`U<n>`, which increment by design.

### 1.3 VERDICT: P / U / F / M / V give a genuine autonomous engine. S does not.

**Yes — `P`, `U` and `F` are hardware loop engines that run at `HCLK`, not at link speed, and `M`/`V` are their operand registers.** This is the highest-value capability of the port and it removes the need for firmware for a large class of tests.

**`P` — masked-compare poll with a bounded budget and a latency readout.** `ADP_POLL0/1/2`, `socdebug_adp_control.v:640-652`:

```
ADP_POLL0: adp_bus_req <= 1; adp_bus_write <= 0;                 // read, NO address increment
ADP_POLL1: on done -> adp_bus_data <= HRDATA32_i; adp_count_dec; adp_bus_err <= adp_bus_err | HRESP_i;
ADP_POLL2: if (FNcount_down_zero_next(adp_count))   -> ECHOCMD, adp_bus_err <= 1'b1;      // TIMEOUT
           else if (((adp_bus_data & adp_mask) ^ adp_val[31:0]) == 0)
                                                    -> ECHOCMD, adp_param <= (adp_param - adp_count);  // MATCH
           else                                     -> ADP_POLL0;                          // loop
```

Properties that make it usable as a test primitive:

1. **Fixed address.** `ADP_POLL0` does not use `ADP_BUSREADINC_next`, so `adp_addr` never advances. `P` polls one location.
2. **Bounded.** The budget is the `P` parameter, decremented once per *completed* bus read (the decrement is gated on `adp_bus_done`, :450).
3. **Match and timeout are distinguishable in the reply.** On timeout `adp_bus_err` is forced to 1, so the echo prints `P!0x<original count>`. On match the echo prints `P 0x<iterations consumed>` — the *number of poll reads it took*, i.e. **a hardware latency measurement in bus-transaction units**, free of link latency.
4. **It has its own built-in discrimination pair.** With `M x00000000` (mask 0) the compare degenerates to `0 ^ V == 0`:
   - `M x00000000`, `V x00000000`, `P x00000010` → **must** match on iteration 1 → `P 0x00000001`.
   - `M x00000000`, `V x00000001`, `P x00000010` → **can never** match → `P!0x00000010`.
   These two commands prove the poll engine is really looping and really comparing, using no fault injection and no DUT state. See **HIO-402**.
5. **Limitation:** `ADP_ECHOCMD` (:678) overwrites `adp_bus_data` with `adp_param`, so **`P` never shows you the polled value** — only the iteration count. Follow with `R` to read the value (the address is unchanged).
6. **Limitation:** `!` on a `P` reply is ambiguous between *timeout* and *a bus ERROR seen during the poll* (the OR at :647). Always prove the address answers OKAY with a plain `R` before polling it.
7. **Limitation:** the compare uses the **un-rotated** `HRDATA32_i` (:646), unlike `ADP_READ` which byte-rotates (:610-614). For sub-word polls at non-zero byte offsets the compare is against the raw bus word, not the printed-style rotated value.

**`F` — block fill.** `ADP_FCTRL`/`ADP_FWRITE` (:655-660). Writes `adp_val[31:0]` to `<count>` successive addresses with auto-increment, at the size encoded in **`V`'s digit count** (`adp_size <= FNparam2size(adp_val[34:33])`, :656). One command fills an entire RAM.

**`U` — binary upload.** `ADP_UCTRL`/`ADP_UREADB`/`ADP_UWRITE` (:633-639). Forces `adp_size <= 2'b00` (byte), then for `<count>` iterations reads one **raw binary byte** off the link and writes it to the current address, incrementing. This is the firmware-download path and it is ~6.5x denser on the wire than `W` per byte (1 link byte per data byte, vs. an 11-char command + 15-char echo per 4 data bytes).

**`M` / `V`** are plain registers (:583, :590). With no parameter they *report* (`adp_param <= {3'b111, adp_mask}` / `<= adp_val`), which makes them readback-testable. `V` additionally stores the digit-count size bits, which `F` consumes.

**`S` is NOT a system self-test.** `ADP_SYSCHK` (:664-668) pushes `adp_param[7:0]` into the SoC's **STDIN** stream and reports `S!` if the stream will not accept it. On this SoC that stream goes to `socdebug_usrt_control` inside `u_debug_0`, **whose APB configuration slave is tied off** (`nanosoc_multicore_soc.sv:1571-1575`: `DEBUG_PSEL(1'b0)`, `DEBUG_PADDR(10'b0)`, …) and which has no serial pins at the SoC boundary. `S` therefore carries data nowhere. It remains useful only as a FIFO-liveness probe of that dead USRT. Likewise the STDIO bypass reached by `X` is an inert channel on this SoC — nothing ever sources STDOUT.

**`C` is inert at the system level on this SoC.** `GPO8_o = adp_sys[7:0]` (:343) and the register is real, but at the top level it is wired to *itself*: `.GPO8(debug_0_gpo8_w), .GPI8(debug_0_gpo8_w)` (`nanosoc_multicore_soc.sv:1585-1586`) and `debug_0_gpo8_w` appears **nowhere else in the file** (only lines 290, 1585, 1586). The `assign debug_resetreq = adp_gpo8[0]` that a reader will find in `nanosoc_arch_tech/rtl/src/nanosoc/nanosoc.sv:589`, and the port comment "GPO8[0] = debug reset request; looped to GPI8 at SoC top" in `src/rtl/wrappers/nanosoc_hostio_debug_ss.v:77`, belong to the **legacy single-core `nanosoc.sv` top, which this chiplet does not use**. Do not plan a reset around `C`.

> **A measured `C` result that was misread, and the corrected test.** The 2026-08-25 session issued `Cx00000200`, saw `C 0x00000200`, and concluded *"GPO read/modify works; `0x2xx` = set bits, low byte is the operand"*. The RTL says otherwise: the set-bits arm is `adp_param[31:8] == 24'h000002`, and the bits actually set are `adp_param[7:0]` (`socdebug_adp_control.v:560-561`). `0x00000200` has a low byte of **`0x00`**, so **nothing was set** — and the `0x0200` that came back is merely the parameter echoed in the report word `{GPI8, GPO8, param[15:0]}` (`:674`). The observation is consistent with a GPO that never changed. **To actually exercise it, write a non-zero low byte:** `Cx0000020f` must return `0x0f0f020f` — `0x0F` in GPO bits `[23:16]` *and* the same `0x0F` mirrored into GPI bits `[31:24]` by the top-level loopback. See HIO-011.

**`R <n>` is a block dump.** `ADP_LINEACK2` (:727-729) re-arms the read while `adp_count != 0` and the last command was `R`. One `Rx00002000` dumps 8192 words. **`[R2]` And it is a block dump for ANY non-zero parameter value, whatever you meant that parameter for — `R100` dumps 256 lines. See the measured table in §1.2.**

### 1.4 The reachable address space — the hard boundary of this whole plan

`debug_m`'s decode is explicit in `multicore_matrix_decode_DEBUG_M.v:448-513`. **R**

| ADP address range | Target |
|---|---|
| `0x00000000`–`0x1FFFFFFF` | eth subsystem (`eth_ss_slave` → its `eth_ss_0` initiator) — see sub-map below |
| `0x20000000`–`0x20FFFFFF` | DMA-250 (`dmac_0`) APB config |
| `0x21000000`–`0x21FFFFFF` | QSPI flash controller |
| `0x22000000`–`0x22FFFFFF` | PTP hardware clock (PHC) |
| `0x23000000`–`0x23FFFFFF` | IPC mailbox |
| `0x24000000`–`0x27FFFFFF` | QSPI XiP read aperture (4 MB, `0x24000000`+) |
| `0x28000000`–`0x28FFFFFF` | CPU1 peripheral block (`cc_periph`) |
| `0x29000000`–`0x29FFFFFF` | **`chip_core_remap_ctrl` — the boot gates** |
| `0x2A000000`–`0x2AFFFFFF` | **`nanosoc_reset_ctrl` — per-CPU reset + ID ROM** |
| `0x2B000000`–`0x2BFFFFFF` | `evt_route_0` |
| `0x2C000000`–`0x2CFFFFFF` | `ctrl_dbg_group` (4 × 1 MB leaves, see below) |
| `0x2D000000`–`0x2DFFFFFF` | shared cross-core SRAM (8 KB physical) |
| `0x2E000000`–`0x2FFFFFFF` | D2D window → TideLink + TideChart + **peer aperture** |
| `0x80000000`–`0x9FFFFFFF` | CPU1 (`chip_core`) subsystem slave |
| **everything else** | **top-level default slave → two-cycle AHB ERROR → `R!`** |

Eth-subsystem sub-map as seen through `0x00000000`–`0x1FFFFFFF` (`eth_ss_matrix_decode_ETH_SS_0.v:9-52`, and `nanosoc_multicore_soc.sv:20-27` for physical sizes): **R**

| ADP address | Target | Physical size | Aliases every |
|---|---|---|---|
| `0x00000000`–`0x07FFFFFF` | bootrom **or** IMEM, depending on the eth REMAP bit | — | — |
| `0x08000000`–`0x0FFFFFFF` | eth bootrom (alias, **always**, remap-independent) | 2 KB (`ETH_BOOTROM_ADDR_W=11`) | 2 KB |
| `0x10000000`–`0x17FFFFFF` | eth IMEM (alias, **always**, remap-independent) | 32 KB (`ETH_IMEM_RAM_ADDR_W=15`) | 32 KB |
| `0x18000000`–`0x1FFFFFFF` | eth DMEM | 16 KB (`ETH_DMEM_RAM_ADDR_W=14`) | 16 KB |

CPU1 sub-map as seen through `0x80000000`–`0x9FFFFFFF` (`nanosoc_cpu_ss_matrix_decode_CPU_SS.v`, static regions): **R**

| ADP address | Target | Physical size |
|---|---|---|
| `0x80000000`–`0x87FFFFFF` | CPU1 bootrom (remap-independent) | 2 KB (`CC_BOOTROM_ADDR_W=11`) |
| `0x90000000`–`0x97FFFFFF` | CPU1 IMEM (remap-independent) | 16 KB (`CC_IMEM_RAM_ADDR_W=14`) |
| `0x98000000`–`0x9FFFFFFF` | CPU1 DMEM | 8 KB (`CC_DMEM_RAM_ADDR_W=13`) |

`ctrl_dbg_group` leaves, sub-decoded on `HADDR[21:20]` (`imp/fpga/nanosoc_multicore_ip/src/ctrl_dbg_group.v:17-27,103,139-142`): **R**

| ADP address | Leaf |
|---|---|
| `0x2C000000` | `etc_capture` (PHC event-timestamp capture) |
| `0x2C100000` | `hw_spinlock` (16 locks; **requester pages** CPU0 `+0x000`, CPU1 `+0x100`, **DBG `+0x200`**, DIAG `+0x300`) |
| `0x2C200000` | **`[R2]` `ctrl_ahb_perf_probe_regs`** (per-initiator AHB performance counters) — **its readout is a SHADOW and its counters SATURATE. See the box below before writing any test against it.** |
| `0x2C300000` | `bus_fault_monitor` (first-fault recorder) |

> ### `[R2]` `ctrl_ahb_perf_probe_regs` at `0x2C200000` — the block that broke four tests. All MEASURED on the die.
>
> Revision 1 treated this as an ordinary free-running counter block. It is not, and the difference invalidated HIO-402 (an ABORT GATE), HIO-307, HIO-404 and HIO-405.
>
> - **The readout registers — `P0_CYC` at `0x2C200040` and every sibling — are a SHADOW SET, frozen until `CTRL[0]` SNAP is written** (`src/rtl/perf_probe/ctrl_ahb_perf_probe_regs.v:23-32`). A read with no preceding SNAP returns whatever the last SNAP captured. **MEASURED: after a `CLR` with no `SNAP` the readout is BIT-IDENTICAL to the pre-`CLR` value; after a `SNAP` it is fresh.** Every observation of this block must be SNAP-then-read.
> - **`CTRL` at `0x2C200008` is WRITE-ONLY and SELF-CLEARING.** `[0]` = SNAP (latch live counters into the shadow), `[1]` = CLR (zero the *live* counters; the shadow is untouched). **Reading `CTRL` back as `0x00000000` is the CORRECT answer, not a fault** — that asymmetry is HIO-307's subject.
> - **The counters SATURATE at `0xFFFFFFFF`. They do not wrap** (`ctrl_ahb_perf_probe.v:184`: `cyc_q <= (cyc_q == CNT_MAX) ? CNT_MAX : +1`). Full scale is 43 s at 100 MHz, so any die that has been powered for a minute reads `0xFFFFFFFF`. **`[R2]` Revision 1's caveat that saturation is a problem to be cleared before measuring is DELETED. A saturated counter is POSITIVE EVIDENCE THAT THE FABRIC CLOCK RAN**, not a stuck register and not a false-fail to be worked around.
> - **The ID constant is `0x50524631` ("PRF1"), MEASURED**, matching `ctrl_ahb_perf_probe_regs.v:72`. `firmware/include/perf_probe.h:40-44`'s `0x50524601` describes a different block. **The dispute Revision 1 recorded in HIO-110 is settled.**
> - **A free clock cross-check.** Three consecutive SNAP deltas taken 2026-08-25 agreed to **~0.02 %** and imply **~100 MHz** — which independently corroborates the `0x05F5E100` (100 000 000) `SystemCoreClock` word at `0x18000000` that HIO-107 reads. Two unrelated observations of the same number is a stronger result than either alone.
> - **Consequence for `P`: `P0_CYC` CANNOT BE POLLED AT ALL.** A poll loop never SNAPs, so it never sees the shadow advance; it either matches on iteration 1 or burns the whole budget. **Both of Revision 1's suggested poll targets in HIO-405 (`P0_CYC` and `CAP_NANOSECONDS`) are shadow latches.** The only genuinely free-running location this port can poll is a cc_periph timer `VALUE`.

D2D sub-decode inside `0x2E000000`–`0x2FFFFFFF` (`src/rtl/chiplet_d2d_decode.sv:118-172`): **R**

| ADP address | Target |
|---|---|
| `0x2E000000`+16 KB | TideLink TX aperture — **gated by `link_active_i`**: ERRORs cleanly while the link is down, can wedge when it is up |
| `0x2E010000`+16 KB | TideLink local RX FIFO |
| `0x2E020000`+16 B | PTP TX write port |
| `0x2E030000`+32 KB | TideLink APB (wlink @ `+0x0000`, tidelink @ `+0x2000`, addr-translator @ `+0x4000`) |
| `0x2E040000`+4 KB | TideChart APB |
| `0x2F000000`+16 MB | **peer aperture — all of `0x2F`, no default responder** |
| any other `0x2E` offset | internal default responder → clean two-cycle ERROR |

#### What ADP therefore CANNOT reach at all

This is a hard consequence of `debug_m`'s decode having no window above `0x2FFFFFFF` except `0x8x`/`0x9x`:

- **The Ethernet MAC registers and MDIO (`0x40000000`).** Not reachable. The eth subsystem decodes them, but the multicore matrix never routes `0x4xxxxxxx` to the eth subsystem.
- **The eth APB peripheral block (`0x50000000`)** — eth UART, timer, watchdog, **and the eth `sys_remap_ctrl` register**. Not reachable. ADP therefore **cannot change the eth REMAP bit**.
- **Eth scratch RX/TX RAM (`0x30000000`, `0x38000000`)**, the CRC checker (`0x48000000`), the eth perf probe (`0x60000000`). Not reachable.
- **Both CPU debug windows (`0xA0000000` network core, `0xB0000000` chip core).** They exist as matrix targets 14 and 15 but `debug_m`'s visibility mask is `0x00003FFF` (targets 0–13) and its decode has no case for them. Only `dap_ss_0_m` (the SWD/DAP path, visibility `0x0000FFFF`) sees them. **ADP cannot halt, single-step, or read CPU registers.**

> **A trap worth stating explicitly.** The `0x84xxxxxx` "bare-link" address family, which is documented elsewhere as wedging the PS backdoor, is **not** an undecoded hole from ADP. `0x84000000` falls inside `0x80000000`–`0x87FFFFFF` and lands on **CPU1's boot ROM**, aliased. ADP will not hang there — it will return plausible ROM data. Do not mistake a successful `0x84…` read for a bare-link access.

### 1.5 Error and hazard semantics

**`!` in place of the space in the reply is the flag** (`ADP_ECHOBUS` :680). It is **overloaded** across three meanings, disambiguated only by the command letter:

| Reply | Meaning |
|---|---|
| `R!0x…` / `W!0x…` | `HRESP` was ERROR on the completing beat (`:606`, `:614`) |
| `P!0x…` | poll timeout **or** a bus ERROR during the poll (`:648` forces it; `:647` ORs it) |
| `S!0x…` | the STDIN FIFO would not accept the byte (`:667`) |
| `F!` / `U!` | a bus ERROR on **some** beat of the fill/upload — see the hole below |

The flag is cleared after each reply is printed (`ADP_WRITEHEX0` :715).

**Off-by-one hole in `F` and `U`.** In both `ADP_FWRITE` (:658) and `ADP_UWRITE` (:637) the `HRESP` capture sits in the **else** branch — the one taken when the loop *continues*. On the final beat the FSM takes the then-branch and exits to `ECHOCMD` without ORing that beat's `HRESP`. **A fill or upload whose only erroring beat is the last one reports clean.** Any `F`/`U` used as a coverage test must therefore be bounded so that the last beat is known-good, or be followed by an explicit `W`/`R` at the final address.

**There is no HREADY timeout anywhere in this FSM.** `ADP_WRITE`/`ADP_READ`/`ADP_POLL1` all re-assert `adp_bus_req` while waiting. A slave that never returns `HREADY` hangs the ADP forever, with the bus held. Consequently:

- ADP is **immune** to *undecoded* addresses — they reach a default slave that ERRORs, and the monitor answers `R!0x00000000` and stays usable. **M** (measured) and **R** (the matrix's `multicore_ahb_interconnect_default_slave.v`, and `chiplet_d2d_decode.sv:236-250` for the `0x2E` holes).
- ADP is **fully exposed** to *stalling* slaves. The known ones are below.

**Hazard register.** Every test in this plan carries a hazard note keyed to this list.

| ID | Address | Hazard |
|---|---|---|
| **HZ-1** | **`0x2E0321A0`–`0x2E0321B8` (the whole band)** | Hard-stall — `SYNC_DIST_OBS` `0x1AC`, `SYNC_DIST_SEL` `0x1B0`, `SWI_PHASE_LSB` `0x1B4`. `tidelink/docs_site/register_map.md:566-571`: *"Uninterruptible AXI hang. Power cycle to recover."* **Quarantine the whole band, not the three offsets** (`tidelink/docs/gate_reports/03_addrmap_param.md:106`). Note the read mux does carry marker bytes `0x5B`/`0x5A`/`0x1B` for these slots (`axi_chiplet_controller.sv:2804-2806`) — **do not be tempted**; the stall is beside the APB slave and the marker is unreachable. **Simulation can never reproduce this** (`03_addrmap_param.md:105-112`: in RTL these are combinational Region-D reads with `pready=1`), so the blocklist is load-bearing and nothing downstream will catch a mistake. |
| **HZ-2** | `0x2F000000`–`0x2FFFFFFF` (peer aperture) | A failed cross-die read parks the peer port and the **next** access wedges the host. `chiplet_d2d_decode.sv` gives all of `0x2F` to the peer with **no default responder**, so ADP has no error escape. Deliberately-guarded, one-shot tests only. |
| **HZ-3** | `0x2E000000`–`0x2E003FFF` (TX aperture) | Wedges on a write **while the link is up**. While the link is down the decoder's `tx_open` gate routes it to the clean ERROR path (`chiplet_d2d_decode.sv:166,171`). Read link state first. |
| **HZ-4** | `0x29000000` | Boot gates are **write-1-set only**; `remap_q <= remap_q \| HWDATA[3:0]` (`chip_core_remap_ctrl.v:117`) and reset only on `PORESETn`. **Setting a bit is irreversible without a power cycle.** |
| **HZ-5** | `0x2A000020` bit 1 (`CPU1_SWRST`) | Resets CPU1, whose PRMU is the **source of the whole SoC's HCLK/HRESETn** — this resets the fabric, the ADP and HOSTIO itself. Destructive; recoverable (the banner reappears). Bit 0 (`CPU0_SWRST`) is safe. |
| **HZ-6** | **`0x24000000`–`0x24FFFFFF` (QSPI XiP aperture)** | **Blocklisted.** With no flash device the AHB wrapper holds `HREADYOUT` low until a 16-bit watchdog expires — **65 536 HCLK ≈ 1.3 ms** — then returns ERROR (`ahb_qspi_interface.sv:109-122,168,224-227`). Any host-side transaction timeout shorter than 1.3 ms will fire first and look like a dead port. Worse, *with* flash present a CPU executing from XiP livelocks on a backward branch and the wrapper watchdog **never** fires (`ahb_qspi/docs/xip_branch_fetch_hang_rootcause.md:10-21`, HW-confirmed on z2_01), and XiP-heavy tests have wedged the PS in the lab (`cocotb-silicon-findings.md:21`). **The QSPI *register* aperture at `0x21000000` is a different thing and is safe** — combinational, no wait states. **Measured 2026-08-25: `0x21000000` reads `0x00000100`, i.e. `CTRL[8] XIP_ACTIVE` is already SET** on that FPGA build (reset is 0, `apb_qspi_regs.v:172`), so XiP was live — treat `0x24xxxxxx` as armed, not dormant. |
| **HZ-7** | `0x2C100000`, `0x2C100100`, `0x2C100200` (spinlock **acquire pages**) | A **read** of an acquire page acquires the lock (`hw_spinlock.v:154-159,199-200`). Page = `HADDR[9:8]`: 0 = CPU0, 1 = CPU1, 2 = DBG, **3 = DIAG**. The DIAG page (`0x2C100300` OWNER, `0x2C100304` FORCE_RELEASE) is **not** an acquire page and is safe to read — `is_acquire_page` excludes it (`hw_spinlock.v:154-156`). Never include pages 0/1/2 in a blind read sweep. |
| **HZ-8** | `0x2E032020`, `0x2E032024`, `0x2E032038`, `0x2E03215C`, `0x2E032160`, `0x2E032168` | **Read-clearing / auto-incrementing.** `RELEASED_CREDITS_ACC` and `DOORBELL_RESPONSE_ACC` read-clear and corrupt live credit bookkeeping (`tidelink_apb_regs.sv:167-168,325-329,356`). Never poll these and never include them in a sweep — a read *is* a write. |
| **HZ-9** | `0x2E030000`–`0x2E031FFF` (wlink) and `0x2E034000`–`0x2E035FFF` (addr-translator) | These two sub-regions **pass the sub-slave's `pready` straight through with no watchdog** (`tidelink/docs/gate_reports/03_addrmap_param.md:100-103`) — a stuck sub-slave hangs the master forever. The `+0x2000` tidelink region *is* watchdogged. Reads here are measured-good today (`0x2E030000` **M**) but are not structurally guaranteed; use a host-side transaction timeout. The reserved quadrant `0x2E036000`–`0x2E037FFF` is explicitly safe (`prdata=0, pready=1, pslverr=0`, `tidelink_top.sv:845-853`). |

### 1.6 The boot/reset architecture — why HOSTIO is alive before any CPU is

This determines the whole bring-up order, and it is the single most important thing on this page.

- `u_network_core` (the ethernet subsystem, containing CPU0) is instantiated with **`.CLK_RST_CONSUMER(1)`** and takes its clock and resets from CPU1: `.sys_hclk_i(u_chip_core_sys_hclk)`, `.sys_hresetn_i(u_chip_core_sys_hresetn)`, `.sys_poresetn_i(u_chip_core_sys_poresetn)` (`nanosoc_multicore_soc.sv:852-860`). **R**
- The fabric — interconnect, `reset_ctrl`, `chip_core_remap_ctrl`, `u_debug_0` (the ADP) and `u_hostio4_0` — is clocked and reset from `u_network_core_sys_hclk` / `u_network_core_sys_hresetn`, which in consumer mode are just routed copies of CPU1's PRMU outputs (`ethernet_ss_ahb_rmii.sv:336-397`). **R**
- `cpu1_bootgate` is tied **`1'b1`** and `cpu0_bootgate` is `chip_core_remap_ctrl_w[2]` (`nanosoc_multicore_soc.sv:1387-1388`), and `cpu0_resetn = cpu0_bootgate & ~cpu0_reset_pulse` (`nanosoc_reset_ctrl.v:363`). **R**
- `chip_core_remap_ctrl` resets to `4'b0000` on `PORESETn` (`chip_core_remap_ctrl.v:115`). **R**

**Therefore, on a brand-new die at power-on:**

1. **CPU1 (`chip_core`) runs immediately** from its own boot ROM. Its PRMU generates the SoC clock and reset.
2. **CPU0 (`network_core`, the ethernet core) is HELD IN RESET.**
3. **HOSTIO/ADP is alive and fully functional**, independent of both CPUs' firmware, because its clock/reset come from CPU1's PRMU and not from the gated CPU0 path.
4. The bootgate that releases CPU0 is at `0x29000000` bit 2 — **reachable from ADP** (target 8, inside `debug_m`'s visibility).

### 1.7 What needs firmware, and what does not

**Does NOT need firmware** (everything in Tiers 0–4): the whole reachable memory map; every register in it; memory integrity; free-running counters (perf-probe cycles, PHC, timers); TideLink/TideChart state observation; DMA-250 descriptor execution (ADP programs the registers and `P` polls the done bit); CPU0 release; CPU0/CPU1 software reset; boot-gate control; spinlock acquire/release; bus-fault-record readout.

**DOES need firmware** (Tier 5): anything behind an address `debug_m` cannot decode — **the Ethernet MAC and MDIO above all**, the eth APB UART/timer/watchdog, the eth scratch RAMs, the CRC checker; anything requiring CPU register state, halt or single-step (that is the DAP's job, not ADP's); anything requiring a response faster than a bus transaction issued from a 6-beat-per-byte serial link.

**Can ADP preload IMEM and release a CPU? YES — both, and by two independent routes.**

- Preload CPU0 IMEM at `0x10000000` (remap-independent alias) with `U` or `W`; preload CPU1 IMEM at `0x90000000`.
- Release CPU0: `A x29000000` then `W x00000004` (sets `NETWORK_CORE_BOOTGATE`). **Irreversible — HZ-4.**
- Re-launch CPU0 as many times as you like afterwards: `A x2A000020`, `W x00000001` (`CPU0_SWRST`, a self-clearing stretched pulse, `nanosoc_reset_ctrl.v:222-239,271-285`). This is the repeatable relaunch primitive and it does **not** touch HOSTIO.
- **Not** via `C`/GPO — see §1.3.

---

## 2. The test list

### 2.0 Conventions and the cost model

- **Every parameter is written `x` + exactly 8 hex digits** unless the test is deliberately exercising the size encoder. See §1.2.
- **Entry preamble, prepended to every test** (from `hostio_adp.py:71-72`): resync the host PIO → send ESC → send one **throwaway** command (the first command after ESC is always rejected with `?`) → then the test's commands. **`[R2]` This preamble is only correct when the port is OUTSIDE the monitor.** ESC is an entry event only (HIO-002 `[R2]`); inside the monitor it is swallowed as a command letter and arms a spurious `?` on the next line. On any re-run the port is inside the monitor, so the preamble must be preceded by an `X` and a confirmation that it landed. The three tests that must observe the entry transition itself — HIO-001, HIO-002, HIO-003 — take no preamble at all and drive (or deliberately do not drive) entry themselves.
- **Cost unit.** `1 CU` = one ADP command round trip. **Measured on hardware 2026-08-25 at a 50 ms host pump slice: a 32-bit read (`A`+`R` = 2 CU) takes ~130 ms, 48/48 successful** — so **`1 CU ≈ 65 ms`**. Runtimes below are quoted as `N CU`; the bracketed wall-clock figures use 65 ms/CU. **The cost figures in the tables below were originally written against the repo client's untuned 2200 ms pump defaults and are therefore ~40× pessimistic — read the bracketed times as upper bounds and §4.1 for the measured numbers.**
- **Block commands (`R<n>`, `F<n>`, `U<n>`, `P<n>`) collapse thousands of bus transactions into 1 CU and are the only reason the memory tiers are tractable** — a full 64 KB dump is ~35 min even at the measured rate.
- **PRECONDITION FOR EVERY TEST: the client's resync watchdog must be live.** Measured 2026-08-25: one client configuration (2 ms pump slices) returned **0/16 reads**, every one timing out at 2.5 s, purely because the small slice starved the stuck-detector so the auto-resync never fired; the same code at 50 ms slices was 12/12. **A HOSTIO client without a working resync watchdog looks exactly like dead silicon.** This is the single easiest way to misdiagnose the port, and it is the first thing to check before believing ABORT GATE 1. Counter-intuitively, **smaller pump slices are slower and less reliable** — the bottleneck is per-iteration MicroPython interpreter overhead, not the link.
- **Class** column: `M` measured, `R` from RTL, `B` from a build artefact — see §0. **`[R2]` A `B`-class expected value is recorded and classified, never asserted — see the warning box in §0.**
- Every test's **DISCRIMINATION** cell states the mutation or fault that turns it red. A test with no such mutation is marked **WEAK** and must not be counted as coverage.
- **`[R2]` RE-ISSUE `A x<addr>` BEFORE EVERY ACCESS.** `R` and `W` both auto-increment (§1.2). A sequence written `A x<addr>` ; `R` ; `W…` puts the write one word past where you meant it. Twelve Revision-1 sequences did exactly that — including **HIO-502**, the one irreversible action in this plan. All are corrected below.
- **`[R2]` "THE VALUE DID NOT CHANGE" IS NOT A TEST.** A no-change assertion is satisfied perfectly by an access path that goes nowhere. Any test whose PASS criterion is *unchanged* — HIO-209, HIO-309's RO half, HIO-313, HIO-314 — **must carry a contemporaneous positive control on the same path**, or it is measuring nothing. See HIO-313 and §4.3 #4.

---

### Tier 0 — port self-test (11 tests)

Nothing below Tier 0 is meaningful until all of Tier 0 passes.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-001** | **Power-on banner.** Attach the host *before* releasing reset, then power-cycle (or, on a running die, `A x2A000020; W x00000002` — HZ-5). Capture the COM TX stream with no commands sent. | Exactly one line ` 0x50c1ab04` then LF CR, and **no prompt character** (`ADP_WRITEHEX0` :711-714 and `ADP_LINEACK2` :725 take the `banner` path straight to `STD_IOCHK`). PASS = that word, first thing, once. | Dead ADP clock, held `HRESETn`, a broken COM TX path, or a wrong `ADPBASIC` build (which would give `0x50c1ab01`, :64-68) all change or remove it. This is the only test that proves the ADP TX path with **zero** dependence on the RX path. | R | 0 CU + reset | HZ-5 if using swreset |
| **HIO-002** | **`[R2]` Monitor entry — the pre-state must be FORCED, not assumed.** Send `X` to drop to the STDIO bypass; **confirm it landed** with a probe command before the `X` and another after it (answers before, silent after ⇒ the `X` provably landed *and* RX is already proven alive); *then* send ESC (0x1b). | LF CR then the prompt char `]` (`STD_RXD1` :488-489 → `ADP_LINEACK` → `ADP_PROMPT`). PASS = prompt seen **after a confirmed bypass pre-state**. | If ESC is not recognised (`FNvalid_adp_entry` :86-89) or the RX path is dead, no prompt. Proves the RX path and the STDIO→monitor transition. **`[R2]` REVISION 1 ASSUMED THE PORT STARTS OUTSIDE THE MONITOR. IT DOES NOT** — that holds exactly once, on a cold die at §3 A1, and never again; the previous test, the previous run and any manual poking all leave it inside. `FNvalid_adp_entry` (:86-89) is evaluated **only in `STD_RXD1`** (:487), which is reachable only from `STD_IOCHK`, the bypass. **Inside the monitor an ESC is not exit** (`FNexit` is `0x04`/`0x00`, :133-136), not a space and not an EOL, so `ADP_RXCMD` (:523) takes it as the **command letter** and parks in `ADP_RXPARAM` waiting for an EOL: **no prompt, no output at all — and the next command line completes that dangling line, is invalid, and is answered `?`.** **MEASURED 2026-08-25**, first hardware run of the implemented suite: a bare ESC to a port earlier work had left in the monitor returned `''`, and this test reported **ABORT GATE 2 — "the RX path is dead" — on a completely healthy die**, taking nine downstream tests with it as `needs` skips. The very next command answered `C 0x00000000]`. **MEASURED: `X` then ESC returns `]`.** The two probes around the `X` are what make a later "no prompt" unambiguous: silent before *and* after means the port was already in the bypass **or** RX is dead, and the ESC is then exactly the experiment that separates those two — which is ABORT GATE 2's actual job. | R+**M** | 3 CU | — |
| **HIO-003** | **First-command `?` artefact. `[R2]` Force the STDIO-bypass pre-state first** (`X`, confirmed, then resync, then a bare ESC — the entry preamble minus the throwaway), *then* send `C`, then `C` again. | First `C` → `?`. Second `C` → `C 0x…`. PASS = the *second* answers. Whether the *first* is rejected is **recorded, not checked**. | **Note:** nothing in the FSM rejects a first command — `ADP_RXCMD`/`ADP_ACTION` have no such rule. The `?` is therefore a **link-layer artefact** (a residual byte in the RX FIFO after `resync()`), not an ADP feature. If a die ever answers the *first* command cleanly, the host link changed, not the SoC. **`[R2]` THERE ARE THREE WAYS TO MANUFACTURE A `?`, NOT TWO,** and Revision 1 named only two: (i) the link artefact this test is about; (ii) `FNvalid_cmd`'s default arm, which is HIO-004's subject; and (iii) **a bare ESC swallowed as a command letter inside the monitor**, whose dangling `ADP_RXPARAM` line the *next* command completes and is rejected for (see HIO-002 `[R2]`). On the hardware run **this test passed while measuring mechanism (iii)** — a pass that measured the wrong thing, which is worse than a fail. Forcing the bypass and confirming the ESC produced a prompt is what makes the `?` below attributable to (i). | R+M | 4 CU | — |
| **HIO-004** | **Unknown-command rejection.** Send `Z`. | `?` then a new prompt (`ADP_ACTION` else-branch :596, `ADP_UNKNOWN` :662). PASS = `?`. | A parser that accepted anything would answer `Z 0x…`. Proves `FNvalid_cmd`'s default arm. | R | 1 CU | — |
| **HIO-005** | **Address register R/W.** `A x12345678` ; `A` | `A 0x12345678` then `A 0x12345678` (report path :551, `adp_param <= {3'b111, adp_addr}`). PASS = both. | Stuck-at or unwritten `adp_addr` bits show as a mismatch. Use a second pass with `A xEDCBA987` to cover the complementary bit pattern — **run both, one value alone cannot detect a stuck-at-that-value fault.** | R | 4 CU (10 s) | — |
| **HIO-006** | **Access-size encoder — LOAD-BEARING FOR THE WHOLE SUITE. `[R2]`** `A x08000000` ; `R` ; `A x08000000` ; `R1` ; `A x08000000` ; **`R000`** | `R` → 8 nibbles; `R1` (1 digit) → **2** nibbles; **`R000` (3 digits) → 4 nibbles in exactly ONE line** (`FNsize_inc` :143-154 → `FNparam2size` :156-167 → `ADP_WRITEHEX9` :693-698). PASS = the three widths **and one line from the third command**. | A broken digit counter prints the wrong width. This is the test that stops every later test from silently issuing byte accesses. **`[R2]` REVISION 1 SPECIFIED `R100` HERE AND THAT WAS WRONG.** It reached for `R100` purely for its three-digit parameter, but the digit count sets the size while the parameter **value** sets the read count, so `R100` is `0x100` = **256 halfword reads and 256 reply lines** — a block dump that also leaves the address 512 bytes further on. MEASURED: `R010` gives 16 lines and advances the address by `0x20`; `Rx00000004` gives 4 lines. `R000` is the identical encoder path with a count of zero. Full table in §1.2. **A related correction: the echo width is NOT sticky.** `ADP_RXPARAM` (:536-537) re-derives `adp_size` from *this* command's own digit count on every EOL, so nothing leaks out of this test into the next one — a bare `A`/`C`/`M` always reports 32 bits wide. No guard is needed and Revision 2's implementation removed the one it had. | R+**M** | 6 CU | — |
| **HIO-007** | **Bus-error flag discrimination — the control pair.** `A x30000000` ; `R` ; `A x08000000` ; `R` | First → `R!0x00000000` (unmapped → default slave ERROR). Second → `R 0x18003c00` (space, not `!`). PASS = **both**, in that order. | This is the plan's master control: it proves the `!` flag can be *both* raised and cleared. If it never raises, every `R!`-based test below is vacuous; if it never clears, every OK-based test is vacuous. **Run it before and after any sweep.** | M+R | 4 CU (10 s) | — |
| **HIO-008** | **Address auto-increment.** `A x08000000` ; `R` ; `R` ; `R` ; `A` | Three consecutive ROM words, then `A 0x0800000c` (increment `1 << adp_size` per completed transfer, :448). PASS = the address advanced by exactly 12. | An `adp_addr_inc` stuck low leaves the address at `0x08000000` and all three reads identical; stuck high advances on non-transfer cycles. Both visible. | R | 5 CU (13 s) | — |
| **HIO-009** | **Block dump.** `A x08000000` ; `Rx00000010` | 16 lines, each `R 0x…`, the first matching HIO-008's first word; then `A` reports `0x08000040`. PASS = exactly 16 lines and the right end address. | If the `ADP_LINEACK2` repeat arm (:727-729) is broken you get 1 line. A miscounted loop gives 15 or 17. Both are unambiguous. | R | 2 CU (5 s) | — |
| **HIO-010** | **Exit / re-enter.** `X` ; then ESC ; then `C` ; `C` | `X` gives LF and drops to `STD_IOCHK` (:576, :671); ESC re-enters and gives a prompt. PASS = a working prompt after the round trip. | Proves the monitor is re-enterable, which every recovery procedure in §3 depends on. If `X` wedged, the port would need a reset to recover. | R | 4 CU (10 s) | — |
| **HIO-011** | **GPO/GPI register and its loopback.** `C` ; `Cx0000020f` ; `C` ; `Cx0000010f` ; `C` | First `C` → `0x000000<param>` with GPO = `0x00`. After `Cx0000020f` (set bits `0x0F`) → **`0x0f0f020f`**: GPO `[23:16]` = `0x0F` and GPI `[31:24]` = `0x0F` too, because the SoC ties `GPI8` to `GPO8` (`nanosoc_multicore_soc.sv:1585-1586`). After `Cx0000010f` (clear bits) → GPO and GPI back to `0x00`. PASS = the three steps. | **The two mirrored bytes are the discriminator**: a report of `0x000f020f` (GPO set, GPI zero) would mean the loopback is broken; `0x0000020f` would mean the set-bits arm never fired. Note what this test does **not** prove: `GPO8` drives **nothing** on this SoC (§1.3), so this is a test of the ADP register and its report path only, never of any system effect. **Use a non-zero low byte** — the measured `Cx00000200` sets nothing and is the null-result form of this test. **`[R2]` CONFIRMED ON THE DIE — this row is now `M`, and it is no longer true that `Cx00000200` is the only measured `C` result.** All eleven checks green: set arm `C 0x0f0f020f` (GPO `[23:16]` = `0x0F`), loopback `C 0x0f0f020f` (GPI `[31:24]` = `0x0F`), the parameter echoed in `[15:0]`, **GPO persists across a bare report** (`C 0x0f0f0000` — note the parameter field drops out, which is what tells you the `0x020f` in the earlier reply was an echo and not state), clear arm `C 0x0000010f`, and the cleared state persists (`C 0x00000000`). **Both mirrored bytes behave, so the two-byte discriminator documented above is real and not a prediction.** | **`[R2]` M** (was `R`) | 5 CU | harmless — GPO is unconnected |

---

### Tier 1 — static identity (27 tests)

All Tier-1 tests are **non-destructive reads**. They are the die's fingerprint and should be captured verbatim into the test record for every die.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-101** | **Eth boot ROM vector table.** `A x08000000` ; `Rx00000010` | Golden dump. Anchors: `[0]=0x18003c00` (initial MSP = DMEM base + 0x3C00), `[1]=0x08000189`, `[2]=0x080001cd`, `[3]=0x080001cf`, `[11]=0x080001d7`, `[14]=0x080001db`, `[15]=0x080001dd`. PASS = byte-exact against the ROM image taped out for this die. | A wrong or unprogrammed ROM changes every word. **Structural back-stop that works with no golden file:** `[0]` must be word-aligned and inside `0x18000000`–`0x18003FFF`; `[1]` must have bit0 = 1 (Thumb) and lie inside `0x08000000`–`0x080007FF`. A garbage ROM fails those. | B (`build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom/stage0_bootrom.hex`), `[0]` also **M** | 2 CU | — |
| **HIO-102** | **CPU1 boot ROM, and discriminating it from CPU0's.** `A x800000e4` ; `R` ; `A x080000e4` ; `R` | CPU1 → `0x08000678`; CPU0 → `0x0800048c`. PASS = the two differ *and* each matches its golden. | The two ROMs' **first 0xE4 bytes are identical** (both vector tables read `0x18003c00, 0x08000189, …`), so a test that compares only the vector table cannot tell them apart and would pass even if both ports were wired to the same ROM. Offset `0xE4` is the first differing word. | B | 4 CU | — |
| **HIO-103** | **CoreSight component ID of `reset_ctrl`.** `A x2a000ff0` ; `Rx00000004` | `0x0000000d, 0x000000f0, 0x00000005, 0x000000b1` → the canonical `0xB105F00D`. PASS = all four. | Hard-coded localparams (`nanosoc_reset_ctrl.v:97-100`). Fails on a dead APB/AHB leg, a mis-decoded region, or a wrong `HADDR[11:2]` path. The four-word pattern cannot be produced by a bus returning zeros, ones, or the last data. **Strongest single identity read on the die.** | R | 2 CU | — |
| **HIO-104** | **Peripheral ID of `reset_ctrl`.** `A x2a000fd0` ; `Rx0000000c` | `PID4..PID7 = 04,00,00,00`; `PID0..PID3 = 26,B8,1B,00` (`nanosoc_reset_ctrl.v:89-96`). PASS = all 12 (note the 4 words at `0xFC0`–`0xFCC` in the same dump read 0 by :185). | Same as HIO-103 but with a *non-uniform* value set including three zeros — it also proves the read mux's `reg_addr[5:2]` decode, which HIO-103 alone does not fully exercise. | R | 2 CU | — |
| **HIO-105** | **`reset_ctrl` reset values.** `A x2a000000` ; `Rx00000009` | `+0x00 REMAP_CTRL = 0` (RAZ), `+0x04 PMU_CTRL = 0` (RAZ), `+0x08 SYS_CTRL = 0`, `+0x0C = 0`, `+0x10 RESET_INFO_CPU0`, `+0x14 RESET_INFO_CPU1`, `+0x18/+0x1C = 0`, `+0x20 SW_RESET` (W, reads 0). PASS = all seven zero. **`[R2]` The two RESET_INFO words are RECORDED, NOT ASSERTED, and `0x00000000` is the CORRECT cold-die reading.** | **`[R2]` REVISION 1 HAD THE POLARITY BACKWARDS AND WOULD HAVE FAILED EVERY HEALTHY DIE.** It claimed RESET_INFO is *expected non-zero* after a power-on via `EXTRESET`. The opposite is true: **a power-on CLEARS the record.** The capture flop is async-cleared *by* the power-on reset — `always @(posedge FCLK or negedge PORESETn) if (~PORESETn) reg_resetinfo_cpu0 <= 4'b0000` (`nanosoc_reset_ctrl.v:326-331`, and `:343-345` for CPU1). Every set-source is a **later** event that has not happened on a cold die: `[0]` `cpu0_sysresetreq`, `[2]` `cpu0_lockup`, `[3]` `EXTRESET` via the `ext_sysresetreq` **input** (:320, :338). **And on this board that input is hardwired off** — `wire ext_sysresetreq = 1'b0;` (`pynq/vivado_ip/nanosoc_multicore_vivado_wrapper.v:182`, wired at `:231` into `.sys_sysresetreq`, passed to `.ext_sysresetreq` at `nanosoc_multicore_soc.sv:1386`) — **so EXTRESET can NEVER set here.** MEASURED `0x00000000` on both words. What may still be asserted, because the RTL guarantees it unconditionally: `[31:4] == 0` (the read mux is `{{28{1'b0}}, reg_resetinfo_cpuN}`, `:165-166`), and `RESET_INFO_CPU0[1] == 0` (`assign nxt_resetinfo_cpu0[1] = 1'b0;`, `:318` — CPU0 has no WDOGRESETREQ source). **HONEST ACCOUNTING OF THE COST:** RESET_INFO was this row's stuck-at-**zero** half, so relaxing it leaves HIO-105 one-sided — it now fails only on a bus stuck at ones. The stuck-at-zero half for this block is HIO-104's non-zero PID words; for the tier it is HIO-125, HIO-127 and the census `D` rows. **The positive control for this register is HIO-503** (CPU0 relaunch), which must make bit `[0]` appear — nothing in a read-only tier can make a cause bit set. **ASIC NOTE:** `ext_sysresetreq` may be bonded to a real pad on the ASIC, so EXTRESET could legitimately read SET there. Record it either way; do not inherit a non-zero expectation. | R+**M** | 2 CU | — |
| **HIO-106** | **Boot-gate register reset value.** `A x29000000` ; `R` | On a **cold** die: `0x00000000` (`chip_core_remap_ctrl.v:115`). On a die where CPU1's stage-0 has run: bit 2 set (`0x00000004`) or bits 0/1/2. PASS = value recorded; a cold-die run must additionally satisfy HIO-107. | This register **is the boot state of the chip**. Its value tells you directly whether CPU0 has been released. Cannot be faked: `HRDATA = {28'b0, remap_q}` (:121). | R | 1 CU | HZ-4 (read only — safe) |
| **HIO-107** | **Boot-gate ↔ CPU0-alive consistency.** Read `0x29000000` (HIO-106), then `A x18000000` ; `R`. | If `0x29000000` bit 2 = 0 → CPU0 has never run → DMEM word 0 must be **unwritten** (zeros or X-pattern on a cold die). If bit 2 = 1 → CPU0 ran its stage-0 scatter-load → DMEM word 0 = `0x05f5e100` (= 100000000 = the generated `SYS_CLK_FREQ_HZ`, i.e. the `SystemCoreClock` initialiser). PASS = the two agree. | This is a **cross-check between two independent observations**, so it fails if either one lies. It is also how the FPGA state of 2026-08-25 is explained: `0x18000000` reading `0x05f5e100` **M** with an empty IMEM means CPU0 *was* released and *did* run its ROM stage-0, then branched into a blank IMEM. If a die shows bit2=1 and DMEM word 0 = 0, CPU0 was released but never executed — a distinct, diagnosable failure. | M + B | 2 CU | — |
| **HIO-108** | **Bus-fault-monitor ID.** `A x2c300010` ; `R` | `0x42464d31` ("BFM1"). PASS = exact. | 4-byte ASCII magic; unforgeable by a stuck bus. Also proves the `ctrl_dbg_group` sub-decode arm `HADDR[21:20]==3` (`ctrl_dbg_group.v:142`). | **`[R2]` R** — confirmed against the instantiated RTL: `src/rtl/wrappers/bus_fault_monitor.v:282`, `localparam ID_CONST`. No longer `B`. **The register OFFSETS around it (HIO-308) are still `B`.** | 1 CU | — |
| **HIO-109** | **Event-timestamp-capture ID.** `A x2c000000` ; `R` | `0x45544331` ("ETC1"). PASS = exact. | As HIO-108, and proves sub-decode arm 0. | **`[R2]` R** — confirmed against the instantiated RTL: `src/rtl/wrappers/etc_capture.v:104`, `localparam ID_MAGIC`. No longer `B`. | 1 CU | — |
| **HIO-110** | **Perf-probe ID + INFO. `[R2]` THE DISPUTE IS SETTLED.** `A x2c200000` ; `R` ; `A x2c200004` ; `R` | **ID at `+0x00` = `0x50524631` ("PRF1") — MEASURED.** `+0x04 INFO = 0x00000004` (4 probes). PASS = both. | **`[R2]` The block actually instantiated here is `ctrl_ahb_perf_probe_regs`** (`ctrl_dbg_group.v:244`, leaf 2), and **`src/rtl/perf_probe/ctrl_ahb_perf_probe_regs.v:72` reads `localparam [31:0] ID_VALUE = 32'h50524631`** — which is what the die returns. **`firmware/include/perf_probe.h:40-44`'s `0x50524601` describes a different block** and is a `B`-class artefact that was never reconciled; it is the third instance of the class of error §0 now warns about. Assert `0x50524631`; the ASCII `PRF` in `[31:8]` is the structural back-stop that no stuck or mis-decoded bus can produce. The INFO word remains the independent half: a wrong probe count detects a mis-parameterised instance that a magic-only check would miss. **Read the two words with separate `A`+`R` pairs, not `Rx00000003`** — a three-line dump has no per-word parse in the client's reply model. **This block is not an ordinary counter file: see the `[R2]` box in §1.4 before writing anything else against `0x2C2xxxxx`.** | **`[R2]` R+M** (was `B (disputed)`) | 4 CU | — |
| **HIO-111** | **IPC mailbox ID.** `A x23000034` ; `R` | `0xc0de0001`. PASS = exact. | Distinct magic on a *different matrix port* from HIO-108/109/110, so it independently proves the `0x23xxxxxx` decode arm. | **`[R2]` R** — confirmed against the instantiated RTL: `ipc_mailbox_apb_regs.sv:29` `parameter PERIPH_ID`, served from slot `6'd13` at `:286`. No longer `B`. | 1 CU | — |
| **HIO-112** | **Spinlock owner reset value.** `A x2c100300` ; `R` | `0x00000000` — all 16 locks free (`hw_spinlock.v:179-180`). PASS = zero. | Weak on its own (a dead bus also returns zero) — **it is only meaningful paired with HIO-304**, which makes a specific non-zero value appear. Marked **WEAK ALONE**. | R | 1 CU | **HZ-7** — `0x2C100300` is the DIAG page and is safe; do **not** read `0x2C100000/100/200` here |
| **HIO-113** | **CPU1 UART (`uart2`) CoreSight ID.** `A x28006ff0` ; `Rx00000004` | `0xB105F00D` pattern (CMSDK `cmsdk_apb_uart` ID ROM). PASS = the four words. | Proves the `0x28xxxxxx` (`cc_periph`) matrix port **and** its internal APB slot decode on `PADDR[15:12]` = 6. A collapsed slot decode would return another peripheral's PID, which differs in PID0/PID1. | R (`cmsdk_apb_uart.v` ID ROM) — read out the exact PID words on first use and freeze them | 2 CU | — |
| **HIO-114** | **Memory-map census / decode fingerprint.** For each address in the census list (§2.1), `A x<addr>` ; `R`. Record OK / `!` / NO-REPLY. | The classification must match §1.4 exactly. Three *distinct* outcome classes must all appear: **OK-with-data** (e.g. `0x08000000`), **ERROR** (`0x30000000`, `0x38000000`, `0x40000000`, `0x48000000`, `0x50000000`, `0x60000000`, `0x70000000`, `0xA0000000`, `0xB0000000`, `0xC0000000`, `0xF0000000`, and `0x23000038` — IPC asserts `PSLVERR` above offset `0x34`, `ipc_mailbox_apb_regs.sv:295`), and **OK-with-zeros** (`0x2E036000`, the TideLink reserved quadrant, which answers `prdata=0, pready=1, pslverr=0`, `tidelink_top.sv:845-853`). PASS = full match on all three classes. | **The highest-information single test in Tier 1.** A shifted or collapsed decode moves the OK/`!` boundary immediately. It is inherently **three-sided** — it asserts OK-with-data, ERROR, *and* OK-with-zeros at named addresses — so it cannot pass by measuring nothing, unlike a sweep that only checks "no errors". The OK-with-zeros class matters because it is exactly what a *dead* bus looks like: including a location where zeros are the **correct** answer forces the test to distinguish "correctly zero" from "everything is zero". | R | ~2 CU per probe × ~32 = 64 CU (2.7 min) | census list in §2.1 excludes every HZ address |
| **HIO-115** | **QSPI controller identity (register aperture only).** `A x21000ff0` ; `Rx00000004` ; then `A x21000034` ; `R` | CIDR0–3 = `0x50, 0x51, 0x4c, 0x53` = ASCII `P Q L S` (`apb_qspi_regs.v:104-107`); `CLK_DIV` = `0x00000001` (clamped to a minimum of 1 so a divider of 0 cannot pass HCLK through, `apb_qspi_regs.v:181,196`). PASS = all five. **Also read `0x21000000` and record `CTRL[8]`**: measured `0x00000100` on FPGA 2026-08-25 (XiP already enabled by firmware) against a reset value of 0. | A **non-Arm** CID string, so it cannot be confused with any of the `0xB105F00D` peripherals — that alone proves the `0x21xxxxxx` decode arm goes to the right block. `CLK_DIV=1` is a second, functional non-zero reset. **The XiP aperture `0x24000000` is NOT probed** — see HZ-6; probing it is what a naive "read one word from every region" sweep would do, and it costs 1.3 ms of stall per probe at best. | R | 4 CU | register aperture is safe; **HZ-6** forbids `0x24xxxxxx` |
| **HIO-116** | **Eth REMAP state probe.** `A x00000000` ; `R` ; `A x08000000` ; `R` ; `A x10000000` ; `R` | If `[0x00000000] == [0x08000000]` → REMAP = 0, `0x0` is boot ROM. If `[0x00000000] == [0x10000000]` → REMAP = 1, `0x0` is IMEM. PASS = exactly one of those holds. | Three-way comparison — it cannot be satisfied by a bus that returns a constant, because that would make **both** equalities true, which the PASS criterion rejects. **Note ADP cannot change this bit** (§1.4): the eth `sys_remap_ctrl` lives in the unreachable eth APB block. Observation only. | R | 6 CU | — |
| **HIO-117** | **Single-register-region aliasing fingerprint.** `A x29000000` ; `R` ; `A x29fffff0` ; `R` ; `A x2a000ff0` ; `R` ; `A x2a0ffff0` ; `R` | `chip_core_remap_ctrl` ignores `HADDR` entirely (`chip_core_remap_ctrl.v:92`), so both `0x29` reads are identical. `reset_ctrl` decodes only `HADDR[11:2]`, so `0x2A000FF0` and `0x2A0FFFF0` both return CID0 = `0x0000000d`. PASS = both alias pairs match. | A region that stopped aliasing (i.e. started decoding upper bits and erroring) would break these. More usefully, it documents the true window size so that later sweeps do not mistake an alias for a second register. | R | 8 CU | — |
| **HIO-118** | **Physical-size probe of every RAM (alias wrap detection).** For each RAM: write a unique tag at offset 0, then read at offset `2^k` for k = 10…20 until the tag reappears. Eth IMEM `0x10000000`, eth DMEM `0x18000000`, CPU1 IMEM `0x90000000`, CPU1 DMEM `0x98000000`, shared SRAM `0x2D000000`. | Wrap points: eth IMEM 32 KB, eth DMEM 16 KB, CPU1 IMEM 16 KB, CPU1 DMEM 8 KB, shared SRAM 8 KB (`nanosoc_multicore_soc.sv:24-27,31-33,43`). PASS = each wrap at the declared size. | Detects a RAM built at the wrong depth or a macro not populated — a class the walking-ones tests cannot see, because a 16 KB RAM aliased into a 32 KB window passes walking-ones at every address. **Also flags a known documentation discrepancy:** the generated discovery table declares eth IMEM `TGT_1_SIZE = 0x00010000` (64 KB) while `ETH_IMEM_RAM_ADDR_W = 15` gives 32 KB physical. The silicon is the authority; the discovery table's SIZE fields are not (its bootrom entry says 8 KB for a 2 KB macro). | R | ~14 CU per RAM × 5 ≈ 70 CU (3 min) | destroys RAM contents — run before any preload |
| **HIO-119** | **Interconnect discovery table readback** (if instantiated and mapped on this build — resolve its base first; it is generated as `*_discovery_table` register files). `A x<disc_base>` ; `Rx00000004` | `TABLE_ID = 0x534f4344` ("SOCD"), `TABLE_VERSION = 0x00000001`, `TABLE_SIZE = 0x00200610` (multicore: 16 targets, 6 initiators, 32-bit) / `0x0020040A` (eth), `INTERCONNECT_NAME = 0x746c756d` ("mult") / `0x5f687465` ("eth_"). PASS = magic + the target/initiator counts matching §1.4. | Self-describing table: the counts and the per-target BASE/SIZE words can be **compared against HIO-114's measured census**, giving a machine-checkable agreement test between what the die says its map is and what it actually decodes. Those two disagreeing is a real finding, not a test bug. | B (`build_soc/discovery/*.yaml`) | 2 CU + ~20 CU for the full table | **`[R2]` STILL UNRESOLVED, AND THIS IS THE ONE SKIP IN TIER 1** (§6). The base address was not located in the built RTL, so the implemented test SKIPs with that reason rather than guessing an address or passing vacuously. **Do not guess a base.** Every constant in this row is `B`-class besides. |
| **HIO-120** | **`ADP` mask/value register readback.** `Mx0f0f0f0f` ; `M` ; `Vxa5a5a5a5` ; `V` ; `Mxf0f0f0f0` ; `M` | Each report echoes the value just written (:583, :590). PASS = all three readbacks exact. | Two complementary patterns on `M` catch stuck-at bits in either direction. This is a **prerequisite** for every `P`-based test — an unwritable mask register would make every poll compare against the wrong thing while still *appearing* to work. | R | 6 CU | — |
| **HIO-121** | **TideLink identity, read-only half.** `A x2e030200` ; `R` ; `A x2e03211c` ; `R` ; `A x2e034fe0` ; `Rx00000004` | **`[R2]` `LINK_CAPABILITIES = 0x00000088`** — `max_tx_lanes` in `[3:0]`, `max_rx_lanes` in `[7:4]`, `[31:8] = 0`. **MEASURED.** (Revision 1 said `0x00080008`; see the DISCRIMINATION cell.) `PHY_ALIGN_ID = 0x50410100` ("PA" v1.0, `axi_chiplet_controller.sv:2922`); addr-translator PIDR0–3 = `0x59, 0x16, 0x15, 0x00` (`tl_addr_trans_regs.sv:61-64`). PASS = all. | **Prefer these to `0x2E030000`.** `0x2E030000` is *RW* — firmware or a previous test can perturb it, so it is not a sound identity register even though it matches on silicon today. `LINK_CAPABILITIES` and `PHY_ALIGN_ID` are pure RO. The addr-translator CIDR (`0x50/0x51/0x4C/**0x54**` at `0x2E034FF0`+) is one byte different from QSPI's (`…0x53`), which is exactly the kind of near-collision that a lazy "check the CID is 0xB105F00D" test cannot see. **`[R2]` `LINK_CAPABILITIES` IS `0x00000088`, NOT `0x00080008`. THE DIE IS RIGHT AND REVISION 1 WAS WRONG, AND IT IS A REGISTER-MAP DOCUMENTATION BUG, NOT A SILICON ONE.** The built RTL is generated from **Chisel, not from the RDL**: `wav-wlink-hw/src/main/scala/Wlink.scala:256-258` declares `WavSWReg(0x0, "LinkCapabilities", …, WavRO(numTxLanes.asUInt, "max_tx_lanes", …), WavRO(numRxLanes.asUInt, "max_rx_lanes", …))` — and a Chisel `8.asUInt` literal is **four** bits wide, not sixteen, so the two fields pack into `[3:0]` and `[7:4]`. The generated Verilog hardcodes the result: `32'h88` at `Wlink.v:1342` (the `eth_chiplet_ip` build). By contrast `tidelink/src/rdl/wlink_regs.rdl:269,274` says `field {} max_tx_lanes[16] = 8;` — two **sixteen**-bit fields, which is where `0x00080008` came from. **The RDL is a hand-maintained specification that the Chisel generator never reads; where they disagree the Chisel wins, because it is what was built.** The *meaning* Revision 1 intended — 8 TX lanes, 8 RX lanes — is confirmed exactly; **only the field offsets were wrong**, so this row still reds on a differently-parameterised link, a constant bus or a dead one. **ASIC NOTE:** the value comes from the Chisel elaboration parameters `numTxLanes`/`numRxLanes`, **not** from the ECC/CRC/FCSM configuration that differs between FPGA and ASIC (§0.1), so `0x00000088` is expected on the ASIC too — unless that build elaborates a different lane count, which these two field checks are exactly what will catch. | R+**M** | 6 CU | **HZ-9** (no watchdog on these two sub-regions) |
| **HIO-122** | **TideLink `PHY_GENERAL_CONTROLS` boot value.** `A x2e030000` ; `R` | `0x00010701` = `pre_count=0x01` `[7:0]`, `post_count=0x07` `[15:8]`, `rx_polarity=1` `[16]` (`wlink_regs.rdl:200-219`). PASS = exact **on a die where nothing has written it**. | Field-decoded, so a partial match is diagnosable rather than just "wrong". Marked as a *boot-value* test not an identity test — see HIO-121. | M + R | 1 CU | HZ-9 |
| **HIO-123** | **TideChart identity.** `A x2e04000c` ; `R` ; `A x2e040010` ; `R` | `TC_TIMEOUT = 0x03E81000` (`{enum_timeout=1000, election_timeout=4096}`, `tidechart_apb_regs.sv:425`); `TC_DEVICE_CLASS = 0x00000001` (`tidechart_apb_regs.sv:19`). PASS = both. | **TideChart has no ID/magic register at all** — these two non-zero resets are the only identity handles in the block, and `TC_DEVICE_CLASS` additionally reads back the **per-die strap**. On a two-die pair the two dies must read *different* device classes; if both read `0x0001` the election has no tiebreak and both can settle as root (`nanosoc_eth_chiplet.sv:76-80`). **That makes this test a direct probe for the known dual-root failure.** Do **not** use `TC_RANDOM_ID` (`0x2E04001C`) — it is PUF-derived and differs per die and per boot. | R | 2 CU | reads safe; **never write `0x2E040008`** (bit 3 re-arms the election) |
| **HIO-124** | **DMA-250 identity *and power state*.** `A x20000fc8` ; `R` ; `A x20000fe0` ; `Rx00000004` | `IIDR = 0x2500043B` (product `0x250`, implementer `0x43B` = Arm; `dma250_gen_regif_dmainfo_CFG_MIN_pkg.sv:44-47`); PIDR0–3 = `0x50, 0xB2, 0x0B, 0x00`. PASS = `IIDR` exact. | **`IIDR == 0` is NOT "absent" — it is "present but power-gated".** The DMA-250's registers are gated by `pqen_apb = pwr_en & clk_en`, and this part has a documented silicon symptom of exactly this: *"the DMA-250 is unresponsive on silicon: IIDR read `0x00000000` (sim returns `0x2500043b`) and config-register writes don't stick"* (`docs/DMA250_DESIGN_AND_WORKPLAN.md:69-70,86-88`). So this one read has **three** distinguishable outcomes — correct ID / zero (gated) / `!` (decode fault) — and each is a different diagnosis. Contrast with the naive check "`0x20000000` reads 0, therefore DMA present": `0x20000000` is `SCFG_CHSEC0`, a security-mapping register whose zero value is what a dead bus also returns. **The measured `0x20000000 → 0x00000000` from 2026-08-25 therefore proves nothing about the DMA; HIO-124 is what settles it.** | R | 3 CU | — |
| **HIO-125** | **Event-router reset defaults and window shape. `[R2]` THE PID PROBE IS DELETED; AN ALIAS CHECK REPLACES IT.** `A x2b000000` ; `R` ; `A x2b000004` ; `R` ; `A x2b000008` ; `R` ; `A x2b00000c` ; `R` ; `A x2b000010` ; `R` ; `A x2b000024` ; `R` | `IRQ_ROUTE_CPU0` (`+0x00`) = `0`, **`IRQ_ROUTE_CPU1` (`+0x04`) = `0x0000000F`**, `EVT_ROUTE_CPU0` (`+0x08`) = `0`, `EVT_ROUTE_CPU1` (`+0x0C`) = `0`, `[31:4] = 0` on all four; `ROUTE_LOCK` (`+0x10`) `[31:1] = 0`; and **`0x2B000024` must equal `0x2B000004`** — the block's 32-byte alias. PASS = all of those, **and the two adjacent `IRQ_ROUTE` registers must DIFFER**. | A **non-zero** reset default (`IRQ_CPU1_RST = {N_SRC{1'b1}}`, `evt_route_ctrl.v:82,114` — all DMA-done to CPU1), so it fails on a bus that returns zeros, the failure mode that makes most reset-value tests worthless; its zero neighbour proves the block distinguishes two adjacent registers, which neither read alone can. **`[R2]` REVISION 1 EXPECTED `PID0 = 0x22` AT `0x2B000FE0`. THE DIE READ `0x00000000` AND THE DIE IS RIGHT: `evt_route_ctrl` HAS NO CoreSight ID SPACE AT ALL.** The whole register file is a five-entry mux — `OFF_IRQ_CPU0`/`IRQ_CPU1`/`EVT_CPU0`/`EVT_CPU1`/`LOCK` at word offsets 0..4, with `default: hrdata_q = {SYS_DATA_W{1'b0}}` (`evt_route_ctrl.v:144-151`) — and the file contains no PID or CID register anywhere. **Worse, `0x2B000FE0` is not an unmapped offset at all — it is an ALIAS.** The decode is `wire [2:0] word_addr = HADDR[ADDR_MSB:ADDR_LSB]` with `ADDR_MSB=4`, `ADDR_LSB=2` (`:71-72,91`), so **only `HADDR[4:2]` is decoded and the block repeats every 32 bytes** across the whole `0x2B` window; `0x2B000FE0` has `HADDR[4:2] = 3'b000`, so it is an alias of `IRQ_ROUTE_CPU0`, whose reset is 0. **MEASURED: `0x2B000004`, `+0x20`, `+0x40` and `0x2B000FE4` all read `0x0000000f`; `0x2B000000` and `0x2B000FE0` both read `0x00000000`.** The `0x22` came from `sys_desc/register_maps/evt_route_ctrl.yaml:27` (`pid0`) at offset `0xFE0` (`:111-112`) — a register-map **specification** artefact the implemented RTL never realised, and precisely the `B`-class trap §0 now warns about. **The alias check turns that discovery into coverage:** the aliasing *is* the block's window shape, and it is now asserted rather than mistaken for a missing peripheral. **ASIC NOTE:** plain RTL with no ECC/CRC/FCSM dependency, so the ASIC must read the same. | R+**M** | 12 CU | reads safe; **never write `0x2B000010`** (`ROUTE_LOCK` is one-way until `HRESETn`) |
| **HIO-126** | **cc_periph slot-decode discrimination.** `A x28000fe0` ; `R` ; `A x28002fe0` ; `R` ; `A x28006fe0` ; `R` ; `A x28008fe0` ; `R` | PID0 = `0x22` (timer0), `0x23` (dualtimer), `0x21` (uart2), `0x24` (watchdog) — `cmsdk_apb_timer.v:63-74`, `cmsdk_apb_dualtimers.v:232-234`, `cmsdk_apb_uart.v:85-96`, `cmsdk_apb_watchdog.v:122-124`. PASS = four **different** values in the right slots. | **Four distinct part numbers in four slots is the strongest decode test on the die.** A collapsed `PADDR[15:12]` decode returns the same PID four times — which a per-peripheral "CID is `0xB105F00D`" test would happily pass, because all four share the same CID. This is the concrete instance of the "check that the check can tell things apart" rule. **Do not assert PID3** (`+0xFEC`): it packs `ECOREVNUM` and is revision-dependent (`cmsdk_apb_timer.v:174`). | R | 8 CU | reads safe; **never write the watchdog** (arming it starts a reset countdown). Slots `0x4000`/`0x5000` (USRT0/1) are tied off inside the wrapper — skip them. |
| **HIO-127** | **Non-zero counter reset values.** `A x28002004` ; `R` ; `A x28008000` ; `R` ; `A x28008004` ; `R` | Dualtimer `TIMER1VALUE = 0xFFFFFFFF` (resets high to avoid a spurious interrupt at start, `cmsdk_apb_dualtimers_frc.v:460-465`); watchdog `WDOGLOAD = 0xFFFFFFFF` and `WDOGVALUE = 0xFFFFFFFF` (`cmsdk_apb_watchdog_frc.v:204,360`). PASS = all three all-ones. | The **complement** of every zero-reset test in this tier: an all-ones expected value fails on a bus stuck at zero, and the zero-reset tests fail on a bus stuck at ones. Running both classes is what makes the reset-value tier two-sided. | R | 3 CU | reads safe |

---

### 2.1 HIO-114 census probe list

Each entry is one `A x<addr>` + `R` pair. `E` = must report `!`, `D` = must report OK with meaningful data, `Z` = must report OK with `0x00000000`.

| Addr | Cls | Addr | Cls | Addr | Cls |
|---|---|---|---|---|---|
| `0x00000000` | **`[R2]` Z** | `0x23000000` | Z ✓ | `0x2C300010` | D ✓ |
| `0x08000000` | D | `0x23000034` | D | `0x2D000000` | D/Z |
| `0x10000000` | D/Z | `0x23000038` | **E** | `0x2E030200` | D |
| `0x18000000` | D | `0x28000fe0` | D | `0x2E036000` | **Z** |
| `0x1FFFFFF0` | **`[R2]` Z** | `0x29000000` | D/Z ✓ | `0x2E040010` | D ✓ |
| `0x20000fc8` | D | `0x2A000ff0` | D | `0x30000000` | **E** |
| `0x21000ffc` | D | `0x2B000004` | D | `0x38000000` | **E** |
| `0x80000000` | D | `0x2C000000` | D | `0x40000000` | **E** |
| `0x90000000` | D/Z | `0x2C200004` | D | `0x48000000` | **E** |
| `0x98000000` | D/Z | `0x50000000` | **E** | `0x60000000` | **E** |
| `0x70000000` | **E** | `0xA0000000` | **E** | `0xB0000000` | **E** |
| `0xC0000000` | **E** | `0xF0000000` | **E** | | |

**Excluded by hazard, deliberately:** all of `0x2E0321A0`–`0x2E0321B8` (HZ-1), all of `0x2F000000`+ (HZ-2), `0x2E000000`–`0x2E003FFF` (HZ-3), `0x24000000`+ (HZ-6), `0x2C100000`/`100`/`200` (HZ-7), `0x2E032020`/`024`/`038`/`15C`/`160`/`168` (HZ-8). **This exclusion list is part of the test — it must be encoded in the census script, not left to the operator.**

> ### `[R2]` THIS CENSUS HAS BEEN RUN — ALL 35 PROBES, VERIFIED INDEPENDENTLY OF THE SUITE, BOTH CONTROLS BEHAVING
>
> Controls: `0x08000000` → `R 0x18003c00` (decoded) and `0x30000000` → `R!` (errored), so the probe demonstrably discriminates and the run is not a null result. **Every address matched its encoded class — after two of them were corrected.**
>
> **`[R2]` TWO ROWS WERE CLASSED `D` AND MEASURE `Z`, AND THEY ARE THE TWO THAT MATTER: `0x00000000` AND `0x1FFFFFF0` BOTH READ `0x00000000`.** Run literally, Revision 1 would have **false-failed ABORT GATE 5 on a healthy chip** — and ABORT GATE 5 stops the whole plan, so the die would have been declared to have a decode fault and everything below Phase B would never have run. Why `Z` is correct at both: `0x00000000` is the remap-selected window, which on a die where the eth REMAP bit maps IMEM there is an **empty RAM**, not ROM (HIO-116 is the test that resolves which); and `0x1FFFFFF0` is the top of the 128 MB eth DMEM window aliasing into a **16 KB** macro, i.e. unwritten RAM. **Neither is a defect and neither was ever going to hold data on a die whose CPUs have not run.** The general lesson is the one §4.3 #6 states: an expected value asserted from a map rather than measured produces a false red, and a false red on an abort gate is the most expensive kind there is.
>
> Values recorded for the rows previously flagged as unverified, and for the ones worth keeping in the die record:
>
> | Addr | Class | Read | Note |
> |---|---|---|---|
> | `0x00000000` | **Z** | `0x00000000` | **reclassified** — see above |
> | `0x1FFFFFF0` | **Z** | `0x00000000` | **reclassified** — see above |
> | `0x10000000` | Z | `0x00000000` | eth IMEM, empty — consistent with HIO-107 |
> | `0x18000000` | D | `0x05f5e100` | `SystemCoreClock` = 100 MHz. **Cross-checks the ~100 MHz fabric rate measured at the perf probe** (§1.4 box) from a completely independent source. |
> | `0x21000FFC` | D | `0x00000053` | QSPI `CIDR3` = ASCII `S` |
> | `0x23000000` | Z | `0x00000000` | IPC slot-0 data word |
> | `0x29000000` | D | `0x00000004` | **boot gate bit 2 already SET** — **`[R3]` RESOLVED**: `cc_rom` (CPU1) writes it on every terminating path, verified at mask geometry. Expected, not an anomaly. |
> | `0x2D000000` | Z | `0x00000000` | shared SRAM, empty |
> | `0x2E036000` | **Z** | `0x00000000` | TideLink reserved quadrant — the deliberate *correctly-zero* row that stops the census passing on a dead bus |
> | `0x90000000` / `0x98000000` | Z | `0x00000000` | CPU1 IMEM / DMEM |
> | `0x20000FC8` | D | **`0x2500043b`** | **`[R2]` THE DMA-250 IS PRESENT AND NOT POWER-GATED ON THIS DIE.** HIO-124 and HIO-411 are written around the documented silicon symptom of `IIDR == 0`; that symptom is **absent here**. The gate for HIO-412 is therefore OPEN, and the only thing still blocking the DMA sub-suite is the unresolved channel offsets. |
> | `0x2E040010` | D | **`0x00000002`** | **`[R2]` `TC_DEVICE_CLASS` reads `0x00000002`, not the `0x00000001` HIO-123 quotes** from `tidechart_apb_regs.sv:19`. That constant is the *reset*; this field also carries the **per-die strap**. Recorded, not failed. **This matters: a strap that differs per die is exactly the tiebreak the TideChart election needs**, so a non-`0x0001` reading here is the good outcome — but confirm the peer die reads something different before concluding the dual-root failure is addressed. |

---

### Tier 2 — memory integrity (11 tests)

These are the tests the block engines were made for. **Always destructive** — schedule before any firmware preload, and re-run HIO-007 immediately after each one to prove the error flag still discriminates.

> **`[R2]` Every command sequence in this tier and the next re-issues `A x<addr>` before every access.** `R` and `W` both auto-increment (§1.2), and twelve Revision-1 sequences put their write (or their poll) one word past the register they named. Each affected row says where it actually landed.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-201** | **Eth IMEM walking-ones/zeros (data-bus integrity).** At `0x10000000`: for each of 32 patterns `1<<k`, `A x10000000` ; `W x<pat>` ; `A x10000000` ; `R`. Then repeat with `~(1<<k)`. | Each readback equals the pattern written. PASS = all 64. | Detects stuck-at, bridged and open data-bus bits. A bridged pair `Dn`/`Dm` fails the walking-ones half; a stuck-at-1 fails walking-zeros. **Running only walking-ones is the classic half-blind version — both halves are required.** | R | 256 CU (11 min) | destructive |
| **HIO-202** | **Eth IMEM address uniqueness (aliasing / address-bus integrity).** Write each address's own value into it: for k = 0…12, `A x1000<off>` ; `Wx1000<off>` at offsets `4<<k` plus offset 0; then read all of them back. | Every location holds its own address. PASS = all match. | An address line stuck or shorted makes two locations the same cell, so one write overwrites another and the readback shows a *different* address's value. **The `F` engine cannot do this test** — it writes one constant, so an aliased RAM passes an `F`+verify perfectly. This is why HIO-202 exists next to HIO-210. | R | 28 CU | destructive |
| **HIO-203** | **Eth IMEM bulk pattern via the fill engine.** `A x10000000` ; `Vx5a5a5a5a` ; `Fx00002000` ; `A x10000000` ; `Rx00002000` | 8192 words all `0x5a5a5a5a`, no `!` on the `F` reply. PASS = the whole dump matches. | Covers every cell, which HIO-201/202 do not. Catches single-bit cell failures and decoder faults inside the macro. **Beware the `F` off-by-one hole (§1.5): the final beat's `HRESP` is not captured** — so follow with **`A x10007ffc` ; `R` ; `A x10007ffc` ; `Wx5a5a5a5a` ; `A x10007ffc` ; `R`** to prove the last word explicitly. **`[R2]` Revision 1 wrote that follow-up as `A x10007ffc` ; `R` ; `W x5a5a5a5a`, which puts the write at `0x10008000` — past the end of a 32 KB RAM, so it aliases back to offset 0 and proves the FIRST word, not the last, leaving the `F` off-by-one hole entirely uncovered.** The same defect is in HIO-204. | R | 3 CU + 1 CU dump (the dump streams 8192 × 15 bytes — see §5) | destructive; **V must have ≥5 hex digits or `F` writes bytes** |
| **HIO-204** | **Eth IMEM inverse bulk pattern.** As HIO-203 with `Vxa5a5a5a5`. | All `0xa5a5a5a5`. PASS = whole dump. | The complementary pattern; a cell stuck at `0x5a5a5a5a`'s value passes HIO-203 and fails here. Running only one polarity is the "measured nothing" failure mode. | R | 4 CU | destructive |
| **HIO-205** | **Eth DMEM (16 KB @ `0x18000000`).** HIO-201/202/203/204 pattern, `Fx00001000`. | As above. | As above. **This RAM currently holds `SystemCoreClock` at word 0 (HIO-107)** — capture that value before destroying it if the boot-state inference matters. | R | ~290 CU | destructive |
| **HIO-206** | **CPU1 IMEM (16 KB @ `0x90000000`).** As HIO-205. | As above. | Reaches CPU1's memory through the remap-independent `0x9x` alias, so it works whatever CPU1's REMAP bit says. **Do this with CPU1 halted if possible** — CPU1 runs from power-on and executes out of this space, so a live CPU1 will fight the test. See §3 for the ordering constraint. | R | ~290 CU | destructive; **CPU1 is running** |
| **HIO-207** | **CPU1 DMEM (8 KB @ `0x98000000`).** As HIO-205, `Fx00000800`. | As above. | As HIO-206 — CPU1's stack lives here. | R | ~290 CU | destructive; **CPU1 is running** |
| **HIO-208** | **Shared cross-core SRAM (8 KB @ `0x2D000000`).** As HIO-205, `Fx00000800`. | As above. | This RAM is the only one reachable by *both* CPUs and the ADP, so it is the medium for every later handshake test (HIO-410, HIO-504). Its integrity must be established before those. | R | ~290 CU | destructive |
| **HIO-209** | **ROM write-protection. `[R2]` THE WORST OF THE AUTO-INCREMENT DEFECTS — CORRECTED.** `A x08000000` ; `R` (record) ; **`A x08000000`** ; `Wxdeadbeef` ; `A x08000000` ; `R` | The ROM word is **unchanged**. The `W` may report OK or `!` — record which. PASS = value unchanged **at the address that was actually written**. | A ROM that accepted writes would be RAM, which is a real integration failure (wrong macro instantiated). Repeat at `0x80000000` for CPU1's ROM. **This test can fail** — that is the point. **`[R2]` AS REVISION 1 WROTE IT, IT COULD NOT.** `A x08000000` ; `R` ; `W xdeadbeef` puts the write at `0x08000004` because `R` auto-increments — **so it wrote ROM word 1 and then checked that word 0 was unchanged. That sequence passes unconditionally on RAM as well as on ROM.** The one test in this plan whose entire value is its ability to go red was structurally incapable of it, and no amount of running it on more dies would have shown that. It is also the reason the `[R2]` rule in §2.0 is stated as an absolute: this failure is invisible in the result, only in the sequence. **A second, independent defect in the same shape:** the write datum `0xdeadbeef` is only distinguishable from the ROM's own contents by luck — read the location first (this row does) and assert against the *recorded* value, never against a constant. | R | 12 CU | — |
| **HIO-210** | **Byte-lane integrity.** `A x10000000` ; `Wx00000000` ; then for lane L = 0..3: `A x1000000<L>` ; `WFF` (**2 digits = byte write**) ; `A x10000000` ; `R` | After lane L's byte write, the word reads `0x000000FF << (8L)` cumulatively: `0x000000FF`, `0x0000FFFF`, `0x00FFFFFF`, `0xFFFFFFFF`. PASS = the four steps. | Exercises the `HWDATA` byte replication (`socdebug_adp_control.v:338-340`) and the RAM's byte-enable decode. A broken byte-enable writes all four lanes at once, giving `0xFFFFFFFF` on the first step. **This is the only test in the plan that deliberately uses a short parameter.** | R | 12 CU | destructive |
| **HIO-211** | **Retention / short soak.** After HIO-203 (`0x5a5a5a5a` fill), wait a defined interval with the port idle (60 s), then `A x10000000` ; `Rx00000100` and spot-check `A x10007ffc` ; `R`. | Unchanged. PASS = identical dump. | Catches retention failures and, more usefully in practice, **catches another agent (a CPU, the DMA, a cross-die write) mutating memory behind your back**. A change here during a supposedly quiescent window is a finding in its own right. | R | 3 CU + 60 s | — |

---

### Tier 3 — subsystem register behaviour (14 tests)

Reset values were Tier 1. This tier proves the registers *behave*: that RW bits are writable, RO bits are not, W1C bits clear only on a 1, and write-only bits do not read back.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-301** | **`reset_ctrl.SYS_CTRL` RW bit. `[R2]`** `A x2a000008` ; `Wx00000001` ; `A x2a000008` ; `R` ; **`A x2a000008`** ; `Wx00000000` ; `A x2a000008` ; `R` | Reads `0x00000001` then `0x00000000` (`nanosoc_reset_ctrl.v:201-215`, readback `:164`). PASS = both. | The **first RW register proven writable through ADP on a peripheral** (as opposed to a RAM). If this fails but Tier-1 reads pass, the ADP write path or `HWDATA` routing is broken while reads work — a failure mode that a read-only test suite cannot see at all. **Restore to 0 afterwards, and ASSERT the restore.** Leaving `LOCKUPRESETEN` set makes a later CPU lockup silently reset that CPU and corrupt subsequent tests. **`[R2]` Revision 1's sequence never restored it:** its `Wx00000000` landed on `0x2A00000C` because `R` auto-increments, so the register was **left set** — precisely the state its own hazard note warns about. | R | 8 CU | leaves a global behaviour change if not restored |
| **HIO-302** | **`reset_ctrl.RESET_INFO_CPU0` W1C semantics. `[R2]`** `A x2a000010` ; `R` (record `v`) ; **`A x2a000010`** ; `Wx00000000` ; `A x2a000010` ; `R` ; **`A x2a000010`** ; `Wx<v>` ; `A x2a000010` ; `R` | Writing **0** must leave `v` unchanged; writing `v` must clear it to `0`. PASS = both steps (`nanosoc_reset_ctrl.v:316-320`: `nxt = (~(write & HWDATA[n])) & reg[n] \| <cause>`). | **The write-0 step is the whole test.** A register wired as plain RW would be cleared by the write-0 and pass a naive "write then read 0" check. Testing W1C without the write-0 negative control measures nothing. **`[R2]` Revision 1's `Wx<v>` landed on `0x2A000014` and cleared `RESET_INFO_CPU1` instead** — destroying the wrong record while proving nothing about the right one. **`[R2]` And per HIO-105, on a cold die `v` is `0x00000000`: with no set bits there is nothing a W1C could clear and this test measures nothing. SKIP it in that case rather than passing it vacuously** — its positive control is HIO-503, which makes bit `[0]` appear. | R | 10 CU | destroys the reset-cause record — capture it (HIO-105) first |
| **HIO-303** | **TideChart `TC_ERROR` W1C. `[R2]`** `A x2e04002c` ; `R` ; **`A x2e04002c`** ; `Wx00000000` ; **`A x2e04002c`** ; `R` ; **`A x2e04002c`** ; `Wx00000007` ; `A x2e04002c` ; `R` | Same shape as HIO-302 on a second, independent W1C implementation. Bits: `[0]` election_timeout, `[1]` enum_timeout, `[2]` **dual_root**. PASS = write-0 inert, write-1 clears. | Same negative control. Additionally, `[2] dual_root` is the sticky flag for the known TideChart dual-root behaviour — **reading it non-zero before you clear it is a real result, not a test artefact.** Record it. **`[R2]` Revision 1's `Wx00000007` landed on `0x2E040030`, the TideChart PUF seed word**, and its bare `R` between the two writes read `0x2E040030` as well. | R | 12 CU | destroys a sticky error record — read it first |
| **HIO-304** | **Spinlock acquire / owner / force-release — the strongest side-effect test on the die.** `A x2c100300` ; `R` ; `A x2c100200` ; `R` ; `A x2c100300` ; `R` ; `A x2c100304` ; `Wx00000001` ; `A x2c100300` ; `R` | `OWNER` = `0x00000000` → read of the **DBG page** lock 0 returns 1 (granted) → `OWNER` = `0x00000003` (`OWN_DBG` in bits `[1:0]`, `hw_spinlock.v:118-124,199-200`) → force-release → `OWNER` = `0x00000000`. PASS = all four. | **This is a value that nothing else on the die can produce.** `0b11` in the owner field appears only if an access arrived through `HADDR[9:8] == 2`, i.e. the debug page — so it proves ADP's read reached the block *and* that the requester-page decode works, in one observation. A stuck bus, a mirrored read, or a decode that ignores `HADDR[9:8]` all fail. It is also fully reversible. | R | 8 CU | **HZ-7** — only pages 0/1/2 acquire; `0x2C100300`/`0x304` are DIAG and safe. Always force-release. |
| **HIO-305** | **IPC mailbox R/W + W1C + aperture edge.** `A x23000000` ; `Wx5a5a5a5a` ; `A x23000000` ; `R` ; `A x23000030` ; `Wx00000001` ; **`A x23000030`** ; `R` ; `A x23000028` ; `R` ; `A x23000038` ; `R` | Slot-0 data word 0 reads back `0x5a5a5a5a`; `LOCK` reads back `0x00000001`; `IRQ_STATUS` reads `0` (nothing has posted); **`0x23000038` reports `!`** (`ipc_mailbox_apb_regs.sv:83,295` — `PSLVERR` above word index 13). PASS = all four. | The `0x23000038` ERROR is the discriminator: this block was deliberately fixed (bug N1, `:269-272`) so in-range holes read **0** rather than aliasing, while out-of-range **errors**. A test that only probed `0x23000000` could not tell a correctly-bounded aperture from one that aliases the whole 16 MB. **`[R2]` Revision 1's bare `R` after the LOCK write read `0x23000034`, `PERIPH_ID` = `0xC0DE0001` — which has bit 0 set, so it would have "confirmed" the LOCK readback while never reading LOCK at all.** This is a false green produced by an off-by-one-word, and it is the reason the §2.0 rule is unconditional. | R | 12 CU | restore slot 0 and `LOCK` to 0 afterwards — CPU1 firmware uses them |
| **HIO-306** | **`etc_capture` CTRL RW. `[R2]`** `A x2c000004` ; `Wx00000003` ; `A x2c000004` ; `R` ; **`A x2c000004`** ; `Wx00000000` ; `A x2c000004` ; `R` | `0x00000003` then `0x00000000` (`[0]` GLOBAL_EN, `[1]` IRQ_EN, `etc_capture.yaml:55-72`). PASS = both. | Proves `ctrl_dbg_group` sub-decode arm 0 accepts writes, not just reads. **Note leaf 0 takes one wait state on reads** (`ctrl_dbg_group.yaml:20-21`) — bounded, not a stall, but it means this leaf exercises the ADP's `HREADY` wait path, which the three zero-wait leaves do not. That makes HIO-306 the only test that proves ADP handles a wait state at all. **`[R2]` Revision 1's restoring write landed on `0x2C000008`, so `GLOBAL_EN` was LEFT SET** — the same defect shape as HIO-301, and it silently arms the capture block for every test after it. | R | 8 CU | leave GLOBAL_EN = 0 — **and assert the restore** |
| **HIO-307** | **Write-only register asymmetry. `[R2]` REWRITTEN — REVISION 1'S SEQUENCE MEASURED NOTHING AND PRODUCED THREE FALSE REDS.** `A x2c200008` ; `Wx00000001` (SNAP) ; `A x2c200040` ; `R` (as-found) ; **`A x2c200008`** ; `Wx00000002` (CLR) ; `A x2c200008` ; `R` ; `A x2c200040` ; `R` (**shadow control — no SNAP**) ; `A x2c200008` ; `Wx00000001` (SNAP) ; `A x2c200040` ; `R` ; `A x2c200008` ; `Wx00000001` ; `A x2c200040` ; `R` | Four assertions, all required. **(a) SHADOW CONTROL:** the post-CLR read *without* a SNAP is **bit-identical** to the as-found value. **(b)** after CLR+SNAP the value is below a bound **derived from the host-measured elapsed time**, never hard-coded. **(c)** it is strictly lower than the as-found value — asserted only when the as-found value was above that bound, so a die powered seconds ago cannot false-red. **(d)** a **later SNAP reads larger**. Plus: `CTRL` read back must not be the `0x00000002` just written, and **`0x00000000` is the correct answer** because `CTRL` is write-only *and self-clearing*. | A block that implemented WO as RW would return `0x00000002`. The functional half is what separates "the read didn't match" from "the write went nowhere". **`[R2]` REVISION 1 GOT BOTH HALVES WRONG.** Its `Wx00000002` landed on `0x2C20000C`, not on `CTRL`, because `R` auto-increments — so no CLR was ever issued. And its criterion, "`CLR` visibly resets `P0_CYC`", **reads the PRE-CLR shadow**: the readout at `0x2C200040` is frozen until `CTRL[0]` SNAP (§1.4 `[R2]` box). **MEASURED on the die: `P0_CYC` as found `0xffffffff` → CLR → `P0_CYC` with no SNAP `0xffffffff`, UNCHANGED → SNAP → `0x0e6e0fe4`, fresh.** On a cold die the same shadow reads `0x00000000` before *and* after, and "a successful reset" is declared having observed nothing at all. **That criterion produced THREE false reds on the hardware run.** Assertion (a) turns the defect into coverage: it now *asserts* the shadow semantics, and would go red if the readout ever became direct. Assertion (d) is what separates "CLR worked" from "the readout is stuck at a small number", which no single post-CLR read can do. **The counters saturate rather than wrap, so an as-found `0xFFFFFFFF` is positive evidence the fabric clock ran** — the implied rate from the SNAP delta is recorded as a free cross-check of the `0x05F5E100` word at `0x18000000`. | R+**M** | ~22 CU | **issuing `CLR` belongs to this test alone.** It zeroes every probe's live counters — do not run it mid-measurement, and note Tier 4's HIO-402 deliberately refuses to emit `CLR`. |
| **HIO-308** | **`bus_fault_monitor` W1C + record.** `A x2c300000` ; `R` ; `A x2c300004` ; `R` ; `A x2c30000c` ; `R` ; `A x2c300000` ; `Wx00000001` ; `A x2c300000` ; `R` | `FAULT_STAT` `[0]` FAULT_SEEN (W1C), `[5:4]` INIT_IDX, `[8]` OVERFLOW; `FAULT_ADDR`, `FAULT_COUNT`. Write-1 clears the whole record and re-arms. PASS = the record reads coherently and clears. | **Important scope limit: `debug_m` is NOT one of the four monitored initiators.** The map is 0 `eth_ss_m` (CPU0), 1 `cpu_ss_1_m` (CPU1), 2 `dmac_0_m`, 3 `dap_ss_0_m` (`firmware/include/bus_dbg.h:11-13`; the same four initiators are the ones tapped for the perf probes at `nanosoc_multicore_soc.sv:827-834`, and `debug_m` is absent from both — **confirm against `src/rtl/wrappers/bus_fault_monitor.v` before freezing this test**). **ADP therefore cannot record its own faults** — so this test cannot be self-stimulated in Tier 3 and only becomes a *live* test in HIO-507. Marked **WEAK until paired with HIO-507**: on its own it proves the register file, not the monitor. | B | 8 CU | destroys a fault record — read it first |
| **HIO-309** | **PHC configuration registers RW/RO split.** **`[R2]`** `A x22000008` ; `R` (record `n`) ; **`A x22000008`** ; `Wx00000005` ; **`A x22000008`** ; `R` ; **`A x22000008`** ; `Wx<n>` ; then `A x2200001c` ; `Wx00000003` ; **`A x2200001c`** ; `R` ; **`A x2200001c`** ; `Wx00000000` ; then `A x22000028` ; `R` (record) ; **`A x22000028`** ; `Wxdeadbeef` ; `A x22000028` ; `R` | `NS_INCR` and `INT_EN` are RW and read back. `CAP_NANOSECONDS` (`0x22000028`) is **RO** — the write must not change it (`phc_regs.rdl:196-200`). PASS = the two RW readbacks **and** the RO non-change. | The RO half is the discriminator. A register file that made everything RW would pass both RW checks. **Restore `NS_INCR` to the value you recorded** — its reset is parameterised (`DEFAULT_NS_INCR`, RDL default 4) and the chiplet override was not located, so it must be read-then-restored, never written blind. **`[R2]` Revision 1's `NS_INCR` write landed on `0x2200000C` and its `INT_EN` readback read `0x22000020`, so neither register was exercised.** **`[R2]` And the RO half is a no-change assertion (§2.0): on its own, a dead write path passes it. It is only meaningful because the two RW readbacks in the same test are its contemporaneous positive control — do not run the RO half alone.** | R (RDL) / ❓ (reset value, still `B`-class) | 18 CU | **PHC cannot stall** — `pready=1'b1` unconditional (`phc_apb_regs.sv:400-401`). Do **not** poll `0x22000004`: `STATUS[1] pps_sticky` is read-to-clear (`phc_regs.rdl:78`) and a polling loop eats every PPS event. |
| **HIO-310** | **TideLink read-only census with the quarantine enforced.** Sweep `0x2E032000`–`0x2E0321FC` step 4, **skipping** `0x1A0`–`0x1B8` and `0x020`/`0x024`/`0x038`/`0x15C`/`0x160`/`0x168`. Read each twice. | Record every value. Each register reads the **same value twice** unless it is a live counter. PASS = the sweep completes, the skip list was honoured, and no address reports NO-REPLY. | The double-read is the point: it separates *stable* registers from *live* and *read-clearing* ones without needing a golden file. **The test's real subject is the blocklist:** if the script's skip list is wrong you find out by hanging the port, and per `03_addrmap_param.md:105-112` **simulation can never catch that mistake for you** — in RTL those addresses are combinational reads with `pready=1`. Dry-run the skip list against the address generator before first silicon use. | R | ~256 CU (11 min) | **HZ-1, HZ-8** — this test exists partly to validate the blocklist |
| **HIO-311** | **cc_periph timer0 RW. `[R2]` THE TWO REGISTERS WERE MISLABELLED.** `A x28000000` ; `R` ; `A x28000004` ; `Wx00010000` ; `A x28000004` ; `R` ; `A x28000008` ; `Wx00010000` ; `A x28000008` ; `R` | `CTRL` reset `0x00000000` (`cmsdk_apb_timer.v:122,156`); **`0x28000004` is CURRENT VALUE (RW), `0x28000008` is RELOAD (RW)** — `cmsdk_apb_timer.v:29-38`. Both accept `0x00010000` and read it back. PASS = **both** readbacks. | Proves the `cc_periph` APB write path (HIO-126 only proved reads). Sets up HIO-405 and HIO-406. **`[R2]` Revision 1 called `0x28000004` RELOAD and `0x28000008` VALUE. The CMSDK map is `0x00 CTRL / 0x04 CURRENT VALUE / 0x08 RELOAD`.** Exercising both words covers the plan's *intent* (RELOAD is writable) and its *literal sequence* (`0x04` is writable) under their correct names, so nothing downstream inherits the swap — HIO-405 and HIO-406 both poll `0x28000004`, which is the live down-counter, and that is only correct under the corrected naming. | R | 12 CU | leave `CTRL` = 0 until HIO-406 |
| **HIO-312** | **QSPI register RW without any flash activity.** **`[R2]`** `A x21000008` ; `Wx00000003` ; `A x21000008` ; `R` ; **`A x21000008`** ; `Wx00000000` ; then `A x2100000c` ; `Wx00123456` ; `A x2100000c` ; `R` ; **`A x2100000c`** ; `Wx00000000` | `CMD` and `ADDR` read back (`apb_qspi_regs.v:174-175`). PASS = both. **`CMD[8]` (enable) must stay 0** — `0x00000003` sets only the command byte, never the enable. | Deliberately exercises the QSPI block **without starting a flash transaction**, so it is safe with or without a device fitted. `ADDR` is 22 bits (`apb_qspi_regs.v:136`), so writing `0x00123456` and reading back `0x00123456` also confirms the width — writing `0xFFFFFFFF` and reading `0x003FFFFF` would confirm it more sharply, and is the better version if you want the width proven. **`[R2]` Both of Revision 1's restoring writes landed one word past their register**, so `CMD` and `ADDR` were left holding the test values — on a block whose `CMD[8]` starts a flash transaction, leaving `CMD` dirty is not a cosmetic defect. **Assert both restores.** | R | 14 CU | never set `CMD[8]`; **HZ-6** still forbids `0x24xxxxxx` |
| **HIO-313** | **Boot-gate write path, non-destructively — ABORT GATE 8. `[R2]` A POSITIVE CONTROL IS NOW MANDATORY AND RUNS FIRST.** **(control, contemporaneous and reversible)** `A x10001000` ; `R` (capture) ; `A x10001000` ; `Wxd00dfeed` ; `A x10001000` ; `R` ; `A x10001000` ; `W x<captured>` ; `A x10001000` ; `R` — **then** `A x29000000` ; `R` (record `v`) ; **`A x29000000`** ; `Wx00000000` ; `A x29000000` ; `R` | The control word takes and returns `0xD00DFEED` and is then **restored** to what was captured. The boot gate is **bit-for-bit unchanged** and the write reported OK: `remap_q <= remap_q \| HWDATA[3:0]` (`chip_core_remap_ctrl.v:117`), so OR-with-0 is a guaranteed no-op. PASS = **all of it**. `HRESP` is tied 0 in this block, so a `!` means the access never reached it and fell through to the default slave — a decode fault, and a real discriminator. | **This is how you prove the write path to the most dangerous register on the die without arming anything.** It converts HZ-4 from "we daren't touch it" into "we have exercised it safely". If this write reports `!` or the readback changes, do **not** proceed to HIO-502. **`[R2]` AS REVISION 1 SPECIFIED IT, THIS TEST COULD NOT FAIL, AND IT IS THE GATE THAT AUTHORISES THE IRREVERSIBLE CPU0 RELEASE.** Its only assertion was *"the value did not change"* — **which a completely dead ADP write path satisfies perfectly** (mutation-proven against the implementation). "The boot gate did not change" is exactly what a write that goes nowhere produces, so ABORT GATE 8 could not detect the one failure that matters: an ADP whose reads work and whose writes do not. **A no-change assertion is not a test.** The fix is a *contemporaneous* positive control on the *same* path — eth IMEM at `0x10001000` is real writable RAM, is measured-good for write/read-back/restore, and is destroyed by Tier 2 anyway, so the test still destroys nothing. It must be contemporaneous: HIO-301 passing ten minutes earlier does not prove the write path is alive **now**. **`[R2]` A second, independent defect:** Revision 1's `Wx00000000` landed on `0x29000004` because `R` auto-increments. It was a no-op *only* because `chip_core_remap_ctrl` ignores `HADDR` entirely (`chip_core_remap_ctrl.v:92`) and because the datum was 0. **The safety of the last gate before an irreversible action must not rest on an address-decode accident.** | R | 12 CU | **HZ-4** — the parameter must be exactly `x00000000`; any set bit here is irreversible. Guard the datum, the address **and** the constant in code, not by operator discipline. |
| **HIO-314** | **RO-immutability sweep.** For each of `0x2A000FF0` (CID0), `0x2E030200` (LINK_CAPABILITIES), `0x2E040010` (TC_DEVICE_CLASS), `0x23000034` (IPC PERIPH_ID), `0x20000FC8` (DMA IIDR): `A x<addr>` ; `Wxffffffff` ; `A x<addr>` ; `R`. | Every one reads its Tier-1 value unchanged. PASS = all five. | The mirror image of HIO-301: it proves the identity constants used throughout Tier 1 are **actually constants** and not RW registers that happen to hold the right value. Without this, every Tier-1 identity test is one stray earlier write away from being meaningless. **`[R2]` But it is a no-change assertion (§2.0), so it needs its own guard against a vacuous pass:** a register reading `0x00000000` both times passes trivially, and **the DMA IIDR does exactly that whenever the block is power-gated** (HIO-124). Record every entry whose pre-value is zero as **UNEXERCISED**, and add a separate check that **at least three of the five constants held a non-zero value across the write**. Note also that `LINK_CAPABILITIES` is `0x00000088`, not `0x00080008` (HIO-121 `[R2]`) — this sweep asserts *unchanged*, so it would not have caught that, which is itself the point. | R | 20 CU | writes to RO registers are harmless here by construction — but do **not** extend this sweep to any address not on this list |

---

### Tier 4 — dynamic and functional (15 tests, one of them structurally impossible and recorded as such)

This is where the `P` engine earns its place: every "wait until" below runs in hardware at `HCLK` and costs **one** command.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-401** | **Poll-engine self-test — the built-in discrimination pair.** (a) `A x08000000` ; `Mx00000000` ; `Vx00000000` ; `Px00000010` — then (b) `Mx00000000` ; `Vx00000001` ; `Px00000010` | (a) → `P 0x00000001` (matched on the first read; space, not `!`). (b) → `P!0x00000010` (budget exhausted; `!`). PASS = **both**, exactly. | With mask 0 the compare is `0 ^ V == 0`, so (a) **must** match and (b) **can never** match, whatever the DUT contains. This proves, with no fault injection and no DUT dependency, that the poll loop actually iterates, actually compares, actually counts down, and actually distinguishes match from timeout. **Every other `P`-based test in this tier is vacuous without it — run it first, every session.** | R | 8 CU | — |
| **HIO-402** | **The fabric clock is running — ABORT GATE 6. `[R2]` REWRITTEN: REVISION 1'S VERSION FAILED ON A HEALTHY COLD DIE.** `A x2c200008` ; `Wx00000001` (SNAP) ; `A x2c200040` ; `R` ; wait ~5 s ; `A x2c200008` ; `Wx00000001` (SNAP) ; `A x2c200040` ; `R` | **Every sample must be SNAP-then-read.** PASS = a **non-zero advance whose implied frequency is physically plausible** (say 1 MHz…2 GHz). **The two not-counting signatures — a static `0x00000000` and a static `0xFFFFFFFF` — are SKIPs, not fails.** | `P0_CYC` counts fabric cycles. If `HCLK` has stopped, everything else in this plan still "works" (registers hold their values, reads return data) and **only this test goes red.** It is the one test that can distinguish "the die is clocked" from "the die is latched". **`[R2]` REVISION 1 GOT THIS TEST — AN ABORT GATE — WRONG IN THREE WAYS.** **(1) The readout is a SHADOW, frozen until `CTRL[0]` SNAP** (§1.4 `[R2]` box). Without a SNAP between the two reads, **both samples return the same stale word**, so "strictly increasing" is unreachable by construction and the gate **FAILED on a healthy cold die**. **(2) "Strictly increasing" is the wrong criterion.** A cold die that has never been snapped reads `0x00000000` twice; a die up for a minute reads `0xFFFFFFFF` twice because **the counter saturates at full scale (43 s at 100 MHz) and does not wrap**. Both readings come from a fully clocked die. **(3) Revision 1's caveat — that saturation is a false-fail to be cleared away with a CLR first — is DELETED. Saturation is POSITIVE EVIDENCE that the clock ran.** **What actually discriminates:** the test may only go red on a counter that **demonstrably counted and then stopped**, i.e. a zero delta from a **mid-range** value. Everything else is a SKIP with its reason, because this register alone cannot tell a probe held in reset or with its global enable low (`ctrl_ahb_perf_probe.v:69`; note `ctrl_dbg_group` takes `sys_sysresetn` while the ADP takes `u_network_core_sys_hresetn`, so the probe **can** be in reset while the monitor runs) from a genuinely stopped fabric. **And there is independent evidence in hand either way: the reply reached you.** `u_debug_0` is clocked from `u_network_core_sys_hclk`, the same net that clocks `ctrl_dbg_group` and this counter — a monitor that answers cannot be on a stopped `HCLK`, because its own AHB transactions would never complete. **Do not power-cycle a die on this result.** To get a measurement out of a saturated part, run HIO-307's CLR (Tier 3's to issue) and re-run. **MEASURED: three consecutive SNAP deltas agreed to ~0.02 % and imply ~100 MHz**, cross-checking the `0x05F5E100` word at `0x18000000`. | R+**M** | 8 CU | **this test must NOT emit `CLR`** — it only SNAPs, which does not disturb the live counters. `CLR` belongs to HIO-307. |
| **HIO-403** | **PHC enable + capture protocol.** `A x22000000` ; `Wx00000001` ; `A x22000004` ; `R` ; `A x22000000` ; `Wx00000005` ; `A x22000028` ; `R` ; `A x22000000` ; `Wx00000005` ; `A x22000028` ; `R` | `STATUS[0] running` = 1 after enable. The two `CAP_NANOSECONDS` reads differ. PASS = running = 1 **and** the two captures differ. | **The single most likely false-fail in this whole plan, and the reason this test is written out step by step:** `CTRL` resets to `0x00000000`, i.e. *"counter frozen"* (`phc_regs.rdl:39-62`). Out of reset the PHC **will not advance** and a naive "read the counter twice" test reports a dead clock on a perfectly good die. Also note `capture` (bit 2) is a self-clearing single pulse and **bit 0 must be re-asserted in the same write** (`Wx00000005`, not `Wx00000004`) or the write stops the clock. There is **no live-readable counter register** — the read mux (`phc_apb_regs.sv:333-397`) reaches only the `cap_*` sets, so the shadow-latch protocol is mandatory, not optional. | R | 14 CU | leaves the PHC enabled — that is usually what you want |
| **HIO-404** | **PHC advance rate. `[R2]`** Two captures separated by a host-measured interval `T`, each one a **fresh** `A x22000000` ; `Wx00000005` followed by reading **both** `CAP_SECONDS_LO` (`0x22000020`) **and** `CAP_NANOSECONDS` (`0x22000028`) from that same capture. | `Δ(sec×1e9 + ns) / T` ≈ `NS_INCR × f_core`. With `NS_INCR = 4` and a 250 MHz core, ≈ 1 ns per ns. PASS = within ±10 % of the rate implied by the `NS_INCR` you read in HIO-309. | Detects a wrong `NS_INCR` strap or a core clock at the wrong frequency — both invisible to HIO-403, which only asks "did it move". The fraction register `CAP_NS_FRAC` (`0x2200002C`) is **static on a fresh part** because `NS_INCR_FRAC` resets to 0, so do not use it as the liveness signal. **`[R2]` Two corrections. (a) These are SHADOW LATCHES: a capture register only advances when a capture is written, so a read without a fresh capture returns a stale word** — Revision 1's sequence read stale shadows, in the same class of defect as HIO-402/307. Re-issue the capture before every sample. **(b) Revision 1's `CAP_NANOSECONDS[15:0]` form wraps every 65.5 µs, far faster than the ~130 ms link**, so the 1e9 nanosecond rollover aliases the measurement into noise; take `{seconds, nanoseconds}` from the **same atomic capture** instead. `CAP_SECONDS_LO` alone moves once per second — too slow — but paired with `ns` it de-aliases. **A free corroboration:** SNAP-sample `P0_CYC` inside the same bracket and record `implied_core_hz / fabric_hz`; if the rate check fails but that ratio is ~1.0, the PHC is fine and the expected-frequency constant is wrong for this build. **`[R2]` THIS TEST HAS NOW RUN, IT FAILED, AND IT IS A REAL FINDING — NOT A WRONG TEST CONSTANT. THE PHC DOES NOT KEEP REAL TIME; IT RUNS 10x SLOW.** MEASURED: `phc_delta_ns = 577,928,912` over `5.7777 s` of wall time ⇒ **`phc_ns_per_wall_s = 100,027,307`** — about **100 M nanoseconds per real second, where real time requires 1000 M**. With `phc_ns_incr = 4` read back from the die, the implied core clock is **`25,006,826 Hz` (~25 MHz)**, against a fabric **`[R3]` re-measured at 25.010 MHz** (§6.3 — the earlier ~100 MHz was wrong by 4x, an estimated rather than measured interval). **`[R3]` So the clock is CORRECT and `NS_INCR = 4` is simply wrong for it**, and a PTP hardware clock that advances at a tenth of real time cannot serve a servo, cannot timestamp, and cannot align a PPS. **This is the FIRST hardware measurement of the PTP subsystem** — until now it sat on the never-tested list. **`[R3]` With the corrected fabric figure the `implied_core_hz / fabric_hz` ratio is ~1.0**, so the PHC counts its clock correctly and the defect is the increment alone. **`[R3]` The clock domain IS now established** — PHC HCLK traces to `assign SYS_HCLK = SYS_FCLK` (`slcorem0p_prmu.v:91-93`) with no divider anywhere. **And the remedy is PROVEN: `NS_INCR` is RW; writing 40 gave 1.0004x real time on the die, restoring 4 gave 0.1000x. NOT a tapeout blocker — fix in PHC init firmware (ASIC wants 10). See §6.3.** | R+**M** | 14 CU + wall time | — |
| **HIO-405** | **Hardware latency measurement via `P`'s return value. `[R2]` THE POLL TARGET IS CHANGED — BOTH OF REVISION 1'S SUGGESTIONS ARE SHADOW LATCHES.** Free-run cc_periph timer0: `A x28000000` ; `Wx00000000` ; `A x28000004` ; `Wxffffffff` ; `A x28000000` ; `Wx00000001` ; then `A x28000004` ; `Mx0000f000` ; `Vx00000000` ; `Px00100000` — **three times** — then `A x28000000` ; `Wx00000000`. | `P 0x<n>` where `n` is the number of bus reads taken for the polled window to be entered. PASS = **no `!`**, every `n` inside the window the mask implies, **and the three counts are not identical** (a constant is an echo, not a measurement). | This is the capability that makes `P` more than a convenience: `n` is measured **in bus transactions at `HCLK`**, entirely free of the 6-beat-per-byte link. It is the only way this port can measure a hardware interval to better than link resolution. **`[R2]` REVISION 1 NAMED TWO POSSIBLE POLL TARGETS AND BOTH ARE UNPOLLABLE.** `CAP_NANOSECONDS` advances only on a capture write, and **`P0_CYC` is frozen until the next SNAP** (`ctrl_ahb_perf_probe_regs.v:30-32`, §1.4 `[R2]` box) — and `P` never SNAPs or captures between its reads, so **a poll can never see either advance**; it matches on iteration 1 or burns the whole budget, and both outcomes are correct behaviour rather than a measurement. The **only genuinely free-running location this port can poll is a cc_periph timer `VALUE`** (`0x28000004`, RW, decrements every PCLK while `CTRL[0]` is set, `cmsdk_apb_timer.v:132-133,247` — and note the register naming correction in HIO-311 `[R2]`). Keep the PHC form as a **recorded demonstration of exactly that limitation**, never as a PHC measurement. **Always leave the timer disabled.** | R+**M** | ~14 CU | leaves timer0 `CTRL` = 0; destroys timer0 `VALUE` |
| **HIO-406** | **Timer counts down, waited on in hardware. `[R2]` THE RELOAD WAS THREE ORDERS OF MAGNITUDE TOO SMALL.** Negative control first: `A x28000000` ; `Wx00000000` ; `A x28000004` ; `Wx18000000` ; `A x28000004` ; `Mxffffffff` ; `Vx00000000` ; `Px00100000` (**must** `P!`). Then, for **`reload_a = 0x18000000` and `reload_b = 0x30000000` (exactly 2×)**: `A x28000000` ; `Wx00000000` ; `A x28000004` ; `Wx<reload>` ; `A x28000000` ; `Wx00000001` ; `A x28000004` ; `Mxffffffff` ; `Vx00000000` ; `Px20000000` ; `A x28000000` ; `Wx00000000`. | Disabled → `P!`. Enabled → match, twice, with counts `n_a` and `n_b`. PASS = **the polarity pair**, `n_b > n_a`, and — the real check — **`(reload_b − reload_a) / (n_b − n_a)` lands in 1…64 `HCLK` cycles per poll read.** | Two independent things must both be true — the timer must actually count *and* the poll must actually terminate — so it cross-validates HIO-401 against real hardware. **Negative control:** with `CTRL` at 0 it must time out with `P!`. Run both polarities. **`[R2]` REVISION 1'S RELOAD OF `0x00010000` MAKES THIS TEST MEASURE THE LINK, NOT THE HARDWARE.** `0x00010000` counts down in **0.65 ms at 100 MHz** — and the floor on "arm the timer, then start polling" is ~2 CU of link, **~130 ms measured**. The timer has therefore parked at 0 long before the poll's first read lands, so **every count comes back as 1**, which is indistinguishable from a broken poll, a stuck register and a correct measurement. The reload must be **many times** the count the clock racks up in that window: `0x18000000` is ~1.6 s at 250 MHz and ~4 s at 100 MHz, an order of magnitude clear of the link. **A count of 1 is a SKIP with that explanation, never a pass** — the polarity result still stands. **`[R2]` And "within an order of magnitude of the reload" is a criterion that cannot fail usefully.** Use two reloads differing by exactly 2× and check the **difference**, not the ratio: the fixed link overhead between arming and polling cancels out of a difference, so `(reload_b − reload_a)/(n_b − n_a)` yields the poll loop's real cycles-per-read directly and requiring that to be physically possible is **self-calibrating — it needs no assumption about the clock frequency at all.** | R+**M** | ~30 CU | disable the timer afterwards; raise the reload further on a slower link |
| **HIO-407** | **TideLink lane / calibration / FCSM state.** `A x2e032108` ; `R` | Decode (`tidelink_regs.rdl:416-472`): `[7:0]` lane_locked, `[15:8]` lane_fault, `[16]` **calibration_done**, `[20:17]` **fcsm_state**, `[22:21]` llrx_state (`==2` → error), `[29]` llrx_valid. Healthy target = **`fcsm = 4`, `cal = 1`** (`axi_chiplet_controller.sv:890,1491`). PASS = record and classify. | Named failure signatures, not just "non-zero": **`fcsm = 1`** is the credit-path bring-up wedge (`tidelink_regs.rdl:441`), **`fcsm = 2`** is the stalled/no-progress signature (`axi_chiplet_controller.sv:739,891`), healthy operating region is 4–7 (`:510`). A non-zero `lane_fault` byte names the failing lane. This test therefore *diagnoses* rather than merely passing or failing. | R | 1 CU | — |
| **HIO-408** | **Wait for link-up, in hardware.** `A x2e032108` ; `Mx00010000` ; `Vx00010000` ; `Px00100000` | Match → `calibration_done` set within the budget. Timeout → `P!`. PASS = match, or a recorded timeout with HIO-407 run immediately afterwards to name the state it was stuck in. | The masked poll is exactly the operation that would otherwise need firmware or thousands of link round trips. **Negative control available for free:** re-run with `Vx00000000` on the same mask — if `cal` really is 1 that must time out. Running only one polarity cannot distinguish "matched because the bit is set" from "matched because the compare is broken". | R | 4 CU | HZ-9 |
| **HIO-409** | **XHB bridge health and the deadlock witness.** `A x2e0321f8` ; `R` ; then `A x2e0321e0` ; `R` | `0xB5000001` and `0xAD800000` on a healthy die. Decode: `0x1F8[31:24]` marker `0xB5`, `[10]` **`xhb_stall_stuck_sticky`** (`hreadyout` low ≥ 2¹² hclk — the XHB500 hazard-list deadlock witness), `[0]` bridge ready (`tidelink_top.sv:1874-1882`). `0x1E0[31:24]` marker `0xAD`, `[23]` `data_healthy`, `[19:10]` per-channel sticky wedge (`tidelink_axinode_obs.sv:162-168`). PASS = both markers present **and** `0x1F8[10] == 0` **and** `0x1E0[23] == 1`. | **Check the marker byte first, always.** If `[31:24]` is not `0xB5`/`0xAD` the register is absent or mis-decoded and *every bit below it is meaningless* — a test that reads bits without checking the marker will report "healthy, all zeros" on a register that isn't there. That is the exact failure this plan exists to avoid. Both markers are the measured values **M**. | M + R | 2 CU | — |
| **HIO-410** | **TideChart election state.** `A x2e040000` ; `R` ; `A x2e040004` ; `R` ; `A x2e040028` ; `R` ; `A x2e04002c` ; `R` | `TC_STATUS`: `[0]` election_done, `[1]` **is_root**, `[2]` enum_done, `[7:3]` local_id, `[12:8]` total_chiplets. `TC_ERROR[2]` = **dual_root** sticky. PASS = record; on a two-die pair, **exactly one die may report `is_root` = 1**. | On a die pair this is a genuine two-sided test: read `TC_STATUS[1]` on **both** dies. Two roots, or `TC_ERROR[2]` set on either die, is the known dual-root failure and is a hard red. On a **single** die the test degenerates — a lone die will legitimately elect itself root — so mark the single-die form **WEAK** and record only. | R | 4 CU | never write `TC_CTRL`; bit 3 re-arms the election |
| **HIO-411** | **DMA-250 liveness before use.** `A x20000fc8` ; `R` | `0x2500043B`. PASS = exact. | **Gate for HIO-412.** If this reads `0x00000000` the block is power-gated (`DMA250_DESIGN_AND_WORKPLAN.md:86-88`) and every DMA test below is unrunnable — **skip them and say so, do not run them and report zeros as passes.** This is the single check that stops a whole sub-suite from silently measuring nothing. | R | 1 CU | — |
| **HIO-412** | **DMA-250 memory-to-memory descriptor.** Gate on HIO-411. Programme a short mem-to-mem transfer from a pattern written into eth DMEM into shared SRAM, start it, then `A x<status>` ; `Mx<done_mask>` ; `Vx<done_val>` ; `Px00100000`, then verify the destination with `Rx…`. | Poll matches; destination matches source. PASS = both. | **The exact DMA-250 channel register offsets, the start bit and the done bit are NOT resolved in this document** — the config aperture is `DMAC_CFG_ADDR_W = 14` (16 KB) with `DMASECCFG` at `+0x000`, `SCFG_CTRL` at `+0x040`, `SCFG_INTRSTATUS` at `+0x044` (`dma250_regdef.h:112-115`), and the channel block layout must be read out of the rendered register package before this test is written. **Marked NOT-YET-EXECUTABLE.** Writing it against guessed offsets would produce a test that passes by writing to reserved space and polling a register that is zero for an unrelated reason. | ❓ | ~12 CU once resolved | needs `SCFG_CHSEC0` security mapping understood before any write |
| **HIO-413** | **Cross-die peer read — deliberately guarded, one shot.** Preconditions: HIO-407 shows `fcsm` in 4–7 and `cal` = 1; HIO-409 shows both markers and `0x1F8[10] == 0`; the peer die is powered and has passed its own Tier 0–1. Then **one** `A x2f000000` ; `R`, with a host transaction timeout, and **stop** — success or failure, issue no further command until the guard below has run. | A data word, or `!`. PASS = a definite outcome. **After the access, re-run HIO-409 before anything else.** | **HZ-2 is the reason for the one-shot rule: a failed cross-die read parks the peer port and it is the *next* access that wedges the host.** So the failure is not visible in this test's own result — it is visible in HIO-409's re-read, and only if that re-read is the very next thing you do. All of `0x2F000000`–`0x2FFFFFFF` goes to the peer with **no default responder** (`chiplet_d2d_decode.sv:172`), so ADP has no error escape here as it does everywhere else. Budget a power cycle. | M (hazard) + R | 3 CU + recovery | **HZ-2 — highest-risk test in the plan.** Never in an unattended sweep. |
| **HIO-414** | **Firmware boot-confirm token.** `A x2d001ff0` ; `R` | `0xB007C0FE` if a CPU has booted and confirmed (`firmware/include/nanosoc_boot_confirm.h:73-74`). PASS = record. | A **firmware-free observation of firmware liveness**, in the one RAM both CPUs and the ADP can reach. Its value is that it is written by software and read by the debug port, so it proves an end-to-end path that no register test covers. **Beware:** on a die where HIO-208 has run, shared SRAM was overwritten — the token's absence then means nothing. Order matters (see §3). | B | 1 CU | — |

**HIO-415 — MDIO / Ethernet MAC: NOT EXECUTABLE OVER HOSTIO.** The MAC and its MDIO controller live at `0x40000000` in the *ethernet subsystem's* map. `debug_m`'s decode has no window there (`multicore_matrix_decode_DEBUG_M.v:456-513`), so an ADP access to `0x40000000` reaches the top-level default slave and returns `R!0x00000000`. There is no alias, no translation, and no window. **The only route to MDIO from this port is via CPU0 firmware — HIO-506.** This entry is recorded rather than omitted so that a later reader does not re-derive it, and so that "MDIO untested" appears in the coverage record rather than being quietly dropped.

---

### Tier 5 — firmware-assisted (9 tests)

Everything here is downstream of releasing CPU0, which is **irreversible within a power cycle** (HZ-4). Do not enter Tier 5 until Tiers 0–4 are complete and recorded.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-501** | **Preload CPU0 IMEM and verify.** `A x10000000` ; `Vx00000000` ; `Fx00002000` (zero the RAM) ; `A x10000000` ; `Ux00001000` + 4096 raw payload bytes ; `A x10000000` ; `Rx00000400` | The dump matches the image. PASS = byte-exact. | `U` forces byte size and writes one byte per link byte (`socdebug_adp_control.v:633-639`), so the count is in **bytes and must exactly equal the payload length** — see the hazard. **The `F` pre-zero is what makes the verify meaningful:** without it, a `U` that wrote nothing would still verify against whatever was already there. **Also verify the final byte explicitly** (`A x10000fff` ; `R`) because of the last-beat `HRESP` hole in `U` (§1.5). | R | ~4 CU + payload | **`U` has no abort and no timeout.** If you send fewer bytes than the count the FSM waits in `ADP_UREADB` forever and `0x04`/`0x00` are *data*, not escapes. Recovery is a host PIO resync. **`[R2]` The blocker on running this test has been the TRANSPORT, not the die or the FSM:** the client's pinned `Adp` API had no raw-payload transmit call, so a `U` issued from the suite could never be satisfied and HIO-501/HIO-508 skipped. That is being wired to the harness's `adp.raw_tx()`; both tests should become at least partly runnable. Nothing in this row's SoC-side description changes. |
| **HIO-502** | **Release CPU0.** Gate on HIO-313 (write path proven safe **and its positive control passed**) and HIO-501 (image loaded and verified). `A x29000000` ; `R` (record) ; **if and only if bit 2 is clear:** **`A x29000000`** ; `Wx00000004` ; `A x29000000` ; `R` | Bit 2 set: `NETWORK_CORE_BOOTGATE`. `cpu0_resetn = cpu0_bootgate & ~cpu0_reset_pulse` (`nanosoc_reset_ctrl.v:363`), gate from `chip_core_remap_ctrl_w[2]` (`nanosoc_multicore_soc.sv:1388`). PASS = the readback shows bit 2 and CPU0 shows life in HIO-504. | **This is the answer to "can ADP release a CPU": yes, by an AHB write, not by GPO.** It goes red if the readback does not change **after a write that was actually needed** (a broken write path — but HIO-313 already ruled that out) or if CPU0 shows no life afterwards, which is then a *firmware* or *reset-tree* result, not a debug-port result. **`[R2]` TWO CORRECTIONS ON THE ONE IRREVERSIBLE ACTION IN THIS PLAN.** **(a)** Revision 1's `Wx00000004` landed on `0x29000004`, because `R` auto-increments. It happens to work only because `chip_core_remap_ctrl` ignores `HADDR` entirely (`chip_core_remap_ctrl.v:92`) — **an irreversible write must not depend on an address-decode accident.** **(b) Read the gate and record it first, and issue the write only if bit 2 is genuinely clear.** On the FPGA build `0x29000000` already reads `0x00000004` with IMEM all zeros — **`[R3]` explained: `cc_rom` opens the gate on every terminating path, so a FRESH ASIC DIE ALSO BOOTS WITH IT OPEN and this write is a no-op there too** — so **a blind write is a no-op that would be reported as a successful release.** Record `bootgate_already_set` either way. | R | 6 CU | **HZ-4 — irreversible until power cycle.** Once set, CPU0 contends for the bus and mutates memory; every quiescent-bus test above becomes unrepeatable. |
| **HIO-503** | **Repeatable CPU0 relaunch.** `A x2a000020` ; `Wx00000001` ; then re-run HIO-504. | `CPU0_SWRST` fires a stretched self-clearing reset pulse (`nanosoc_reset_ctrl.v:222-239,271-285`); `RESET_INFO_CPU0` records the cause. PASS = CPU0 restarts and the reset-info record changes. | **The relaunch primitive, and it does not touch HOSTIO.** It makes the whole of Tier 5 iterable: reload IMEM with `U`, pulse `CPU0_SWRST`, observe again — no power cycle, no re-arming the bootgate. It goes red if the pulse does not restart CPU0 (visible as an unchanged `RESET_INFO_CPU0` and unchanged firmware behaviour). | R | 4 CU | resets CPU0 only — **bit 1 is a different matter, see HIO-509** |
| **HIO-504** | **Firmware liveness via shared SRAM.** Load a firmware that writes an incrementing heartbeat to `0x2D000000`. Then `A x2d000000` ; `R` ; wait ; `A x2d000000` ; `R` ; and **`A x2d000000`** ; `Mxffffffff` ; `Vx<expected>` ; `Px00100000`. | The heartbeat advances. PASS = strictly increasing across two reads, or a `P` match on a sentinel. | The `P` form is the strong one: it waits for a **specific** value the firmware will write, so a stuck heartbeat, a wrong value, and a dead CPU are all distinguishable from success. A two-read comparison alone cannot tell "advancing correctly" from "advancing wrongly". **`[R2]` Revision 1's `P` inherited `0x2D000004` from the preceding `R`'s auto-increment, so it polled the word AFTER the heartbeat** — and since `P` itself does not advance the address (§1.3 property 1) it would have sat on the wrong location for the whole budget. Re-issue `A x2d000000` before the `M`/`V`/`P` triple. | R | 10 CU | shared SRAM must not have been clobbered — see §3 ordering |
| **HIO-505** | **Firmware console, polled from ADP.** With CPU1 or CPU0 firmware writing to `uart2`: `A x28006004` ; `Mx00000002` ; `Vx00000002` ; `Px00100000` (wait for RX-buffer-full) ; then `A x28006000` ; `R`. Repeat, or poll TX state to inject. | Characters recoverable one at a time. PASS = readable text. | **This is the console substitute, and it matters because ADP's own STDIO path is dead on this SoC** (§1.3: the debug USRT's APB slave is tied off at `nanosoc_multicore_soc.sv:1571-1575` and it has no pins). `uart2` at `0x28006000` is the CPU1 console and *is* ADP-reachable, so the console exists — just not through `S`/`X`. **Confirm the CMSDK `STATE` bit polarity against `cmsdk_apb_uart.v` before writing the mask**; a wrong mask polarity gives a poll that always matches, which looks exactly like success. | R (block) / ❓ (bit polarity) | ~4 CU per char | slow — see §5 |
| **HIO-506** | **Ethernet MAC and MDIO, via CPU0 firmware.** Load a firmware that (a) reads the MAC ID registers at `0x40000000`, (b) performs an MDIO read of the LAN8720's PHY ID registers 2 and 3, (c) writes both results to shared SRAM. Release CPU0 (HIO-502), then read the results from `0x2D0000xx` over ADP. | The LAN8720 PHY ID appears (OUI `0x0007C0`, model/revision per the datasheet). PASS = the PHY ID matches. | **The only route to MDIO from this port.** Its discrimination is strong: a PHY that is absent, unpowered, strapped to the wrong address, or has a dead MDIO line returns `0xFFFF`/`0x0000` rather than the OUI, and those are distinguishable from each other. The result travels back through a path (firmware → shared SRAM → ADP) already proven by HIO-504, so a failure here is attributable to the MAC/PHY and not to the transport. | R | firmware build + ~6 CU | requires HIO-502 (irreversible) |
| **HIO-507** | **Bus-fault monitor, live.** Have firmware perform one deliberate access to an unmapped address (e.g. `0x70000000`). Then `A x2c300000` ; `R` ; `A x2c300004` ; `R` ; `A x2c30000c` ; `R`. | `FAULT_SEEN` = 1, `FAULT_ADDR` = the address firmware used, `INIT_IDX` = 0 (`eth_ss_m`/CPU0) or 1 (CPU1). PASS = the address matches **exactly** and the initiator index is right. | **This is what upgrades HIO-308 from WEAK to real.** The captured address is a value only a correct monitor could produce, and the initiator index proves the per-initiator demux. Recall `debug_m` is **not** monitored, so ADP cannot stimulate this itself — which is precisely why it needs firmware and why HIO-308 alone is not coverage. | B | firmware + 6 CU | clears/re-arms on write-1 |
| **HIO-508** | **CPU1 memory preload (the other core).** `A x90000000` ; `Vx00000000` ; `Fx00001000` ; `A x90000000` ; `Ux<n>` + payload ; verify with `Rx…`. Then `A x29000000` ; `Wx00000001` to point CPU1's address 0 at IMEM, and `A x2a000020` ; `Wx00000002` to restart it. | CPU1 runs the loaded image. PASS = CPU1 firmware liveness via HIO-504/505. | `0x90000000` is a **remap-independent** alias of CPU1 IMEM (`nanosoc_cpu_ss_matrix_decode_CPU_SS.v`, static region), so the preload works whatever CPU1's REMAP bit currently says — you do not have to know the boot state to load the image. Fails visibly if the alias is wrong (HIO-118 would already have caught that). | R | ~6 CU + payload | **HZ-4** on the remap write; **HZ-5** on the restart — see HIO-509. **`[R2]` Skipped so far for the same transport reason as HIO-501, not for a silicon reason.** |
| **HIO-509** | **Whole-SoC reset, and the banner as proof.** `A x2a000020` ; `Wx00000002` (`CPU1_SWRST`), with the host capturing the raw RX stream. | The ADP **banner `0x50C1AB04` reappears** and the port returns to the STDIO bypass, requiring a fresh ESC. PASS = the banner. | **Destructive and deliberately so.** CPU1's PRMU is the source of the whole SoC's `HCLK`/`HRESETn` (§1.6), so resetting CPU1 resets the fabric, the ADP and HOSTIO itself. The re-emitted banner is therefore an end-to-end proof of the reset tree that no read can give you — and the recovery is automatic. It also gives you a repeatable way to return a die to its cold state for **everything except the boot gates**, which survive on `PORESETn` (`chip_core_remap_ctrl.v:113-115`). Use it as the standard "start over" between Tier-5 iterations. | R | 2 CU + resync | **HZ-5 — destructive.** Never in an unattended sweep. Confirm HIO-010 (re-entry) works before relying on it. |

**Test count: 11 (Tier 0) + 27 (Tier 1) + 11 (Tier 2) + 14 (Tier 3) + 15 (Tier 4, incl. the recorded non-executable HIO-415) + 9 (Tier 5) = 87.**
Of these, **3 are marked not-yet-executable or weak-alone and must not be counted as coverage**: HIO-412 (DMA offsets unresolved), HIO-415 (structurally impossible over this port), and HIO-308/HIO-112 (weak until paired with HIO-507/HIO-304 respectively). HIO-119 is conditional on the discovery tables being mapped in the built RTL.

---

## 3. ASIC bring-up ordering — one die at a time

Run the phases in order. Each **ABORT GATE** is binding: if it fails, stop and do not run the phases below it. The reason for the gates is not caution for its own sake — it is that a failure above a gate makes every result below it **uninterpretable**, and an uninterpretable green is worse than a red.

### Phase A — is the port alive at all? (no writes, ~3 s of link time plus a power cycle)

| Step | Test | Gate |
|---|---|---|
| A0 | **Prove the client's resync watchdog is live** before touching the die (§2.0). A starved watchdog gives 0/16 reads that look exactly like dead silicon. | **If the watchdog is not verified, ABORT GATE 1 below is not trustworthy.** |
| A1 | **HIO-001** — power the die with the host already attached and capture the raw RX stream. | **ABORT GATE 1: no banner → stop.** See §3.1 for what that means and what to do. |
| A2 | **HIO-002**, **HIO-003**, **HIO-004**, **HIO-010** — enter the monitor, confirm rejection of a bad command, confirm re-entry after `X`. **`[R2]` Send `X` and confirm the bypass BEFORE the ESC.** | **ABORT GATE 2: no prompt → the RX path is dead.** The banner already proved TX, so this isolates the fault to the host→SoC direction: one PIO state machine, four data lines and `IOREQ1/2`. Scope those. **`[R2]` BUT ONLY IF THE PORT WAS PROVABLY OUTSIDE THE MONITOR WHEN THE ESC WENT OUT.** ESC is an entry event only; inside the monitor it is swallowed as a command letter and returns nothing (HIO-002 `[R2]`). **This gate tripped on a healthy die on the first hardware run for exactly that reason**, taking nine tests with it. "Starts outside the monitor" holds exactly once — here, on a cold die at A1 — and never again, so on any re-run you must force the bypass with `X` and confirm it landed. **Do not declare a dead RX path from a silent ESC alone.** |
| A3 | **HIO-005**, **HIO-006**, **HIO-008**, **HIO-009**, **HIO-011**, **HIO-120** — address register, size encoder, auto-increment, block dump, GPO/GPI loopback, mask/value registers. | If HIO-006 fails, **every parameter in every later test is the wrong access size.** Stop. |
| A4 | **HIO-007** — the `R!` / `R ` control pair. | **ABORT GATE 3: if `!` never appears, or never clears, stop.** Every OK/ERROR classification below — the whole of HIO-114 — is vacuous without a demonstrated two-sided error flag. |

### Phase B — identity and census, still read-only (~150 CU ≈ 10 s of link time)

| Step | Test | Gate |
|---|---|---|
| B1 | **HIO-106** — read `0x29000000` **first**, before anything else. | Not a gate, but it is the die's boot state. It tells you immediately whether CPU0 is loose and therefore whether the bus is quiescent. Record it in the die's test record before any other value. |
| B2 | **HIO-103**, **HIO-104** — `reset_ctrl` CID `0xB105F00D` and PID. | **ABORT GATE 4: wrong CID → the fabric is not decoding.** Nothing below is meaningful. Suspect the matrix, the `0x2A` decode arm, or `HADDR` routing from the ADP. |
| B3 | **HIO-114** — the memory-map census (§2.1). | **ABORT GATE 5: any address in the wrong outcome class → stop and locate the decode fault.** Running later tests against a shifted map produces confident readings of the wrong register. |
| B4 | **HIO-116**, **HIO-101**, **HIO-102**, **HIO-107** — remap state, both boot ROMs, boot-state consistency. | A ROM mismatch is a hard red for the die. HIO-107 disagreeing is a real finding — record it and continue. |
| B5 | **HIO-108**–**HIO-113**, **HIO-115**, **HIO-117**, **HIO-121**–**HIO-127** — the full identity set. | Record every value verbatim. This block is the die's fingerprint and is what you diff between dies. |
| B6 | **HIO-402** — the fabric clock is advancing. **`[R2]` SNAP before every sample.** | **`[R2]` ABORT GATE 6 — RESTATED, BECAUSE REVISION 1'S FORM FAILED ON A HEALTHY COLD DIE.** The gate trips **only** on a counter that demonstrably counted and then stopped: a **zero delta from a mid-range value, with a `CTRL[0]` SNAP before each of the two samples.** A static `0x00000000` (never snapped) and a static `0xFFFFFFFF` (**saturated — positive evidence the clock ran**) are **SKIPs, not aborts**. And note the standing independent evidence: the ADP is clocked from the same net as this counter, so **a monitor that answers you cannot be on a stopped `HCLK`**. Every register read above would still have "worked" if the fabric really were latched — but so would nothing else. **Do not power-cycle a die on this row.** |
| B7 | **HIO-407**, **HIO-409**, **HIO-410**, **HIO-411** — TideLink FCSM/cal, XHB witness, TideChart election, DMA power state. | Not gates — these are *state* readings. HIO-411 gates only HIO-412. |

### Phase C — write behaviour, nothing destroyed (~130 CU ≈ 9 s of link time)

| Step | Test | Gate |
|---|---|---|
| C1 | **HIO-401** — the poll-engine discrimination pair. | **ABORT GATE 7: if either polarity fails, every `P`-based test below is vacuous.** Do not skip this because it "always passes". |
| C2 | **HIO-313** — the boot-gate write path, exercised with a guaranteed no-op, **`[R2]` preceded by its positive write-path control.** | **ABORT GATE 8 for Phase F.** If the OR-with-zero write reports `!` or changes the value, do **not** attempt HIO-502. **`[R2]` AND IF THE POSITIVE CONTROL DID NOT RUN, THIS GATE IS NOT A GATE.** As Revision 1 specified it, HIO-313's only assertion was "the value did not change" — which a **completely dead ADP write path satisfies perfectly**. The gate authorising the irreversible CPU0 release could not detect the one failure that matters. **A no-change assertion is not a test.** Run the reversible control at `0x10001000` in the same test, immediately before, and treat a missing control as a failed gate. |
| C3 | **HIO-301**, **HIO-302**, **HIO-303**, **HIO-304**, **HIO-305**, **HIO-306**, **HIO-307**, **HIO-309**, **HIO-311**, **HIO-312**, **HIO-314**. | HIO-314 (RO-immutability) should run **last** in this block: it retro-validates every identity constant Phase B recorded. |
| C4 | **HIO-403**, **HIO-404**, **HIO-405**, **HIO-406**, **HIO-408** — PHC enable and rate, hardware latency measurement, timer countdown, link-up wait. | Remember HIO-403's trap: the PHC is **frozen out of reset** and must be enabled first. |
| C5 | **HIO-414** — read the boot-confirm token **now**, before Phase D destroys shared SRAM. | — |

### Phase D — destructive memory tests (minutes if spot-checked, ~1.5 h if every RAM is fully dumped — see §4.1)

Capture anything you still need from RAM **before** this phase: the boot-confirm token (C5), DMEM word 0 (HIO-107), and any sticky record you have not yet read.

| Step | Test | Note |
|---|---|---|
| D1 | **HIO-118** — physical-size / alias-wrap probes for all five RAMs. | Do this first: it tells you the real depth, which every pattern test below must respect. |
| D2 | **HIO-201**, **HIO-202**, **HIO-210** on eth IMEM; then **HIO-203**, **HIO-204**. | HIO-202 (address uniqueness) cannot be replaced by an `F`-based test — see its discrimination note. |
| D3 | **HIO-205** eth DMEM, **HIO-208** shared SRAM. | |
| D4 | **HIO-206**, **HIO-207** — CPU1 IMEM and DMEM. **CPU1 is executing out of these.** | `cpu1_bootgate` is tied `1'b1` (`nanosoc_multicore_soc.sv:1387`), so **CPU1 cannot be held in reset** and `CPU1_SWRST` is only a pulse. Two honest options: **(a)** run the tests anyway and treat any mismatch as *inconclusive* rather than a fault — a running CPU legitimately writes its own stack; or **(b)** **park CPU1 first**: preload a two-instruction spin loop at `0x90000000` (HIO-508's mechanism), set `0x29000000` bit 0 so CPU1's address 0 maps to IMEM, then pulse `CPU1_SWRST`. CPU1 then spins in a handful of IMEM words and stops touching DMEM. Option (b) costs an irreversible bit (HZ-4) and a fabric reset (HZ-5) — choose deliberately and record which you did. |
| D5 | **HIO-209** ROM write-protection, **HIO-211** retention/soak. | HIO-211 doubles as a "is anything else mutating memory" probe. |
| D6 | **Re-run HIO-007 after each of D2–D5.** | Cheap, and it catches the case where a destructive test left the port in a state where the error flag no longer discriminates. |

### Phase E — cross-die (only with a peer die present, both through Phases A–C)

| Step | Test | Gate |
|---|---|---|
| E1 | **HIO-408** — wait for `calibration_done`, both dies. | **ABORT: no link-up → do not touch `0x2F`.** |
| E2 | **HIO-407** + **HIO-409** — confirm `fcsm` ∈ 4–7, `cal` = 1, both markers present, `0x1F8[10] == 0`. | **ABORT: any of those wrong → do not touch `0x2F`.** |
| E3 | **HIO-410** on **both** dies — exactly one may report `is_root`. | Dual root is a hard red; record and stop the cross-die sequence. |
| E4 | **HIO-413** — one single peer read, then **HIO-409 as the very next command**. | **HZ-2.** Budget a power cycle. Never unattended. |

### Phase F — firmware, irreversible (point of no return)

| Step | Test | Note |
|---|---|---|
| F1 | **HIO-501** — zero IMEM with `F`, load with `U`, verify with `R<n>` including the last byte. | `U`'s count must equal the payload length exactly — it has no timeout and no abort. |
| F2 | Re-confirm **HIO-313**. | Last chance to check the write path before arming. |
| F3 | **HIO-502** — set `0x29000000` bit 2. | **POINT OF NO RETURN for this power cycle.** From here CPU0 contends for the bus and mutates memory; nothing in Phases B–D is repeatable in the same conditions. |
| F4 | **HIO-504**, **HIO-505**, **HIO-506**, **HIO-507**. | HIO-506 is the only route to the Ethernet MAC and MDIO. |
| F5 | Iterate with **HIO-503** (CPU0 relaunch, cheap) or **HIO-509** (whole-SoC reset, returns everything except the boot gates to cold). | HIO-509 re-emits the banner — which is also a free re-run of HIO-001. |

### 3.1 What HOSTIO tells you when SWD returns nothing

SWD has never returned a DPIDR on these boards. That single symptom has several very different causes and, until now, no way to tell them apart. **HOSTIO separates most of them, and that is its principal strategic value on this chiplet.**

| What you observe | What it rules IN | What it rules OUT | Action |
|---|---|---|---|
| **HOSTIO banner appears** (HIO-001) | Core supplies up; CPU1's PRMU released; the fabric clock and `HRESETn` are live; the ADP is out of reset. Because the fabric clock/reset come from CPU1's PRMU (§1.6), the banner alone proves **all of that**. | "The die is dead." "The clock is not running." "Reset is stuck." **None of these can be the reason SWD is silent.** | The SWD failure is isolated to the DAP, the SWD pins, their pull-ups/level shifting, or the debug power domain. Stop debugging the SoC and debug the SWD wiring. |
| **Banner appears and HIO-114 census matches** | The AHB matrix decodes correctly for a non-CPU initiator. | A broken bus fabric as the cause of SWD silence. | Same as above, with more confidence. |
| **HIO-402 shows `P0_CYC` advancing** | The fabric clock is genuinely toggling, not merely settled. | A latched-up or gated fabric. | Same. |
| **`0x29000000` reads bit 2 = 0** (HIO-106) | **CPU0 has never been released from reset.** | "CPU0 has crashed." It never started. | This is a completely different fault from a dead chip, and it is invisible to SWD. Either CPU1's stage-0 never ran or it never wrote the gate. **Release CPU0 yourself with HIO-502** and the chip may simply work. |
| **`0x29000000` bit 2 = 0 AND `0x18000000` word 0 = 0** (HIO-107) | Consistent: CPU0 never ran, so it never scatter-loaded `.data`. | A subtly-running CPU0. | As above. |
| **`0x29000000` bit 2 = 1 but firmware is silent** | CPU0 was released and ran far enough to initialise `.data` (if HIO-107's DMEM word is set), then stopped. | "CPU0 was never released." | A **firmware** problem, not a silicon or debug problem. Load a known-good image with HIO-501 and relaunch with HIO-503. |
| **No banner at all** | Nothing. | Nothing. | This is the only case where HOSTIO is as blind as SWD — and it is informative *because* both are blind: two independent debug paths failing together points at power, the PRMU/PLL, or the global reset, not at either debug path. Scope `IOACK` and the supplies. |

**The operational conclusion: on a die where SWD returns nothing, HOSTIO alone is sufficient to take the chip from cold to running firmware** — verify the ROMs, census the map, test the RAMs, load an image into IMEM, release CPU0, and observe it through shared SRAM and `uart2`. The only thing SWD would have given you that HOSTIO cannot is **CPU register state, halt and single-step** (the `0xA0000000`/`0xB0000000` debug windows are visible to `dap_ss_0_m` only — §1.4).

---

## 4. Coverage honesty

### 4.1 Link throughput, and which tests are impractically slow

**Protocol.** HOSTIO4 is 7 pins: a 4-bit bidirectional data bus plus `IOREQ1`, `IOREQ2` and a single `IOACK`, fully hardware-interlocked, **with no source-synchronous clock** (`nanosoc_arch_tech/rtl/hostio4/README.md`). One byte crosses as command-nibble + two data nibbles through the state sequence `STAZ → TXC1 → TXC2 → TXDH/RXDH → TXDL/RXDL → TXDZ/RXDZ → STAZ` (`hostio4_controller_fsm.v:150-159`) — **six states, five of which advance only on an `IOACK` level change. Six fully-interlocked beats per byte.**

**Floor set by the SoC.** Each beat crosses a 2-flop synchroniser (`hostio4_controller_sync.v:26`) and the controller runs on a divide-by-2 clock enable (`hostio4_controller.v:109-120`), so the SoC contributes roughly 4 `sys_hclk` ≈ **40 ns per beat ≈ 0.24 µs per byte** at 100 MHz. The host PIO turnaround and pad delays dominate; a realistic wire rate is order **1–5 µs per beat → 6–30 µs per byte → roughly 30–170 kB/s**. **This has not been measured and should be.** Nothing in this plan depends on the exact figure — only on the ratios below.

**Ceiling set by the client — and this half is measured, not estimated.** Sweep of four client configurations, 12 reads each, 2026-08-25 on KR260 + RP2350, 48/48 successful:

| host pump slice | ms per 32-bit read | success | implied 64 KB dump |
|---|---|---|---|
| **50 ms** | **130 ms** | 12/12 | **~35 min** |
| 20 ms | 177 ms | 12/12 | ~48 min |
| 10 ms | 216 ms | 12/12 | ~59 min |
| 5 ms | 208 ms | 12/12 | ~57 min |
| 2 ms | — | **0/16, all timed out** | — (watchdog starved) |

- **Budget ~130 ms per 32-bit access, i.e. ~65 ms per command, ~30 B/s of payload.**
- **Smaller pump slices are *slower*.** The bottleneck is per-iteration MicroPython interpreter overhead (`get_xiot_fifo_status()` + `sm0.put()` on every loop pass), not link speed or wait granularity. At 2 ms the stuck-detector is starved, auto-resync never fires, and the port appears dead.
- The client is still roughly **three orders of magnitude** slower than the protocol allows. **If any test in this plan is too slow, fix the client before redesigning the test** — a `@micropython.native` inner loop, batched puts, or a compiled host driver should recover most of the headroom. This is a client problem, not a silicon problem.
- The repo client `hostio_adp.py` as committed uses much larger untuned pumps (2200 ms per command, 25 ms per character, `hostio_adp.py:59-70`) and is correspondingly ~40× slower than the tuned figures above. **Tune it before running this plan.**

**Bytes on the wire per operation** (command + CR in, echo + LF CR + prompt out):

| Operation | Bytes | Beats |
|---|---|---|
| `A x08000000` | 26 | 156 |
| `R` (single word) | 17 | 102 |
| **one word read (`A`+`R`)** | **43** | **258** |
| `Wx12345678` | 26 | 156 |
| `Rx00002000` (dump 32 KB) | ~123 000 | ~738 000 |
| `Ux00008000` (load 32 KB) | ~32 800 | ~197 000 |
| `Fx00002000` (fill 32 KB) | **26** | **156** |
| `Px00100000` (wait up to 1 M polls) | 26 | 156 |

**The three ratios that should drive every test you write:**

1. **Filling a RAM is ~4700× cheaper than dumping it.** `F` moves 32 KB in one 26-byte command (the 8192 AHB writes take ~82 µs on-die); `R<n>` needs ~123 kB back. So: fill with `F`, spot-check with a handful of `P` commands (1 CU each, and `P` returns pass/fail directly), and only fall back to a full `R<n>` dump when a spot check fails.
2. **`U` is ~6.5× denser than `W` per byte** (1 link byte per data byte vs. a 26-byte command per 4 data bytes). Never load firmware with `W`.
3. **`P` collapses an arbitrary wait into one command.** A "wait for link-up" that would need thousands of `A`+`R` round trips is one `P`, and it polls at `HCLK`, not at link speed.

**Tests that are impractically slow and what to do about them:**

| Test | Cost at the measured 65 ms/CU | Mitigation |
|---|---|---|
| HIO-201 walking ones/zeros | 256 CU ≈ **17 s** per RAM | Fine. Do not extend it to every address — that is what HIO-203/204 are for. |
| HIO-203/204 full-RAM verify | one `F` (instant) + a **~18 min** dump per 32 KB RAM | Replace the dump with ~16 sampled `P` checks (≈ 1 s total) in routine runs; keep the full dump for the first die of a lot and for any die that fails a spot check. |
| HIO-310 TideLink sweep | ~256 CU ≈ **17 s** | Fine, once per die. |
| HIO-505 UART console | ~4 CU ≈ **0.26 s per character** | Still **unusable as a console** (≈ 4 chars/s). Use it to recover a short status string, and put real firmware output into shared SRAM (HIO-504) where one `R<n>` retrieves a whole buffer. |
| Any per-word loop over a whole RAM | 8192 × 130 ms ≈ **18 min** | Use `R<n>` — a block dump of the same 8192 words costs the same wall time but **one** command, so it cannot desynchronise mid-way. |
| HIO-118 alias-wrap probes | ~70 CU ≈ **5 s** | Fine. |

**One measured anomaly to resolve, and HIO-401 is the test that resolves it.** In the 2026-08-25 session `P`, `U` and `F` **returned no response inside a 2.5 s window, though the link recovered fully afterwards** — and that session recorded "what `P`/`U`/`F` actually converge on, and their termination conditions" as *not established*. The RTL explains all three without needing a fault:

- **`U <n>` waits in `ADP_UREADB` for `n` raw payload bytes and has no timeout and no abort** (`socdebug_adp_control.v:633-635`; `0x04`/`0x00` are *data* there, not escapes). Issuing `U` with a count and no payload hangs until the host resyncs — exactly the observed "no response, then recovery".
- **`F <n>` writes `adp_val` to `n` addresses from the current address.** If `V` was never set, or the address pointed somewhere unhelpful, it still completes — but a large `n` at a wait-stated slave can exceed a 2.5 s window.
- **`P <n>` polls up to `n` times and only replies on match or budget exhaustion.** A non-matching value with a large `n` is silent for the whole budget. With mask and value at their reset zeros, `(data & 0) ^ 0 == 0` matches immediately — so a `P` that was silent had a *non-zero* mask or value, or a large budget against a stalling address.

So the observation is consistent with the RTL and is **not** evidence of a broken engine. **HIO-401 settles it in two commands** by forcing one guaranteed match and one guaranteed timeout. Run it before drawing any conclusion about `P`.

**A second measured item worth correcting.** That session recorded `M` as *"reads `0x00000000`; a write attempt did not stick — inconclusive"*. The likely explanation is a test that measured nothing: `M` with a parameter sets the mask, and `M` with no parameter reports it — but if the value written was `0x00000000`, the readback is `0x00000000` whether the write landed or not. **HIO-120 uses two complementary non-zero patterns precisely to avoid this**, and is the test that settles `M`'s writability.

### 4.2 What HOSTIO fundamentally cannot test

These are structural limits, not gaps to be closed by a better test. Each belongs in the coverage record as *not covered by this port*.

**1. Everything off `debug_m`'s decode.** The Ethernet MAC and MDIO (`0x40000000`), the eth APB block — UART, timer, watchdog **and the eth REMAP control** (`0x50000000`), eth scratch RX/TX (`0x30000000`/`0x38000000`), the CRC checker (`0x48000000`), the eth perf probe (`0x60000000`). Not reachable at any address, with or without firmware running — only *through* firmware (HIO-506). §1.4.

**2. CPU internal state.** No register read, no halt, no single-step, no breakpoints, no watchpoints, no PC sampling. The `0xA0000000` and `0xB0000000` debug windows are visible to `dap_ss_0_m` only. ADP can start and reset a CPU and watch what it writes to memory; it cannot look inside one.

**3. Anything analogue.** Supply rails and IR drop, PLL lock quality and jitter, the D2D eye, LAN8720 electricals and signal integrity, pad drive strength, ESD structures. TideChart's PUF seed is *readable* (`0x2E040030`) but a readable value is not a characterisation.

**4. Timing and margin.** ADP issues single, non-pipelined `NONSEQ` beats and cannot vary the clock or the voltage, so setup/hold margin, Fmax and shmoo are all out of reach. Note in particular that a die can pass every test in this plan and still fail at speed.

**5. AHB protocol behaviour ADP cannot generate.** `HTRANS` is `NONSEQ` only and `HBURST` is always `INCR` regardless (`socdebug_adp_control.v:333-336`), so bursts, back-to-back pipelined beats and `SEQ` handling are untested. `HADDR[1:0]` is forced to `00` for word accesses (`:331`), so **misaligned-access fault behaviour cannot be tested at all**. `HMASTLOCK` is tied 0, so locked sequences are untested. Multi-initiator arbitration can be *observed* through the perf probes but not *provoked* — ADP is one initiator and cannot create a race.

**6. Real-time response.** Anything needing a reaction faster than one command round trip: interrupt latency, PPS edge alignment, PTP servo behaviour, packet-rate behaviour, and every race condition. **`[R2]` One important qualification, earned on the die: the PHC's *rate* IS measurable from this port, and measuring it found a real defect** — two shadow captures bracketed by host wall time gave `100,027,307` ns per real second, i.e. **10× slow** (§6.3). So "real-time *response* is out of reach" remains true, but do not let it be read as "nothing about the PTP clock is testable here". A rate is not a servo, and it was still enough to find the thing. `P` mitigates this for the special case of *waiting* on one address with one masked compare at `HCLK` — but `P` cannot sequence two conditions, cannot act on a match, and cannot capture the value that matched. Anything needing a *reaction* needs firmware.

**7. Simultaneity of any kind.** Two initiators at once, cross-die concurrency, cache/coherence effects. Cross-die work is additionally limited by HZ-2: a failed peer read can cost a power cycle, so **the peer aperture cannot be soaked from this port** — one guarded shot at a time is the honest ceiling.

**8. Its own link.** If HOSTIO does not answer, HOSTIO cannot tell you why. That case needs a scope on the seven pins. The banner (HIO-001) is the closest thing to a self-diagnosis, because it is emitted with no host stimulus and so separates the two directions.

**9. Scan, BIST and boundary scan.** Separate infrastructure, separate plan.

**10. Power-domain control.** The DMA-250's power state is *observable* (HIO-124: `IIDR == 0` means gated, not absent) but not *controllable* from this port. The same applies to any other LPI-gated block.

### 4.3 The things in this plan most likely to produce a false green — **`[R2]` three became six, and two of them have already fired**

Stated explicitly, because this is where a test plan usually fails:

1. **A `P`-based test that passes because the compare is broken.** Mitigation: HIO-401 every session, plus the opposite-polarity negative control named in HIO-406 and HIO-408.
2. **An identity read that passes because the register is RW and something wrote the right value.** Mitigation: HIO-314, and preferring pure-RO registers (HIO-121) over RW ones (HIO-122).
3. **A reset-value test that passes because the bus returns zeros.** Mitigation: the census's OK-with-zeros class (HIO-114), the non-zero reset defaults (HIO-125, HIO-127), and never treating `0x20000000 == 0` as evidence about the DMA (HIO-124).
4. **`[R2]` A NO-CHANGE ASSERTION THAT PASSES BECAUSE THE ACCESS WENT NOWHERE — and this one already happened, on the most dangerous gate in the plan.** Any test whose PASS criterion is *"the value is unchanged"* is satisfied perfectly by a write path that is dead, by an address that decodes somewhere harmless, or by a register that was never reached at all. **HIO-313 (ABORT GATE 8) was specified this way and was therefore structurally incapable of failing** — it authorises the irreversible CPU0 release. The same shape is in **HIO-209** (ROM write-protection), **HIO-309**'s RO half and **HIO-314** (RO-immutability sweep). Mitigation: **every no-change assertion must carry a contemporaneous positive control on the same path** — a reversible write to a known-writable location, in the same test, immediately adjacent. *Contemporaneous* is load-bearing: a write test that passed ten minutes ago does not prove the write path is alive now. And a register that reads `0x00000000` both times must be recorded as **UNEXERCISED**, not as a pass.
5. **`[R2]` A TEST THAT PASSES WHILE MEASURING THE WRONG MECHANISM.** HIO-003 passed on the hardware run, but the `?` it observed came from a bare ESC swallowed inside the monitor, not from the link artefact the test is about (HIO-002/HIO-003 `[R2]`). A green here would have been read as "the first-command artefact behaves as documented". Mitigation: **establish the pre-state and assert that you established it** — the two probes around the `X` in HIO-002 exist for exactly this. Where a symptom has more than one cause, a test must rule out the others before it may claim the one it names.
6. **`[R2]` AN EXPECTED VALUE THAT CAME FROM A SPECIFICATION THE RTL NEVER IMPLEMENTED.** This produces the mirror failure — a **false red on a good die** — and it has fired four times already (§0). It belongs in this list because its cost is the same: a wrong verdict held with confidence. Mitigation: the `B`-class rule in §0 — record and classify, never assert.

---

## 5. Hardware verification of this plan's key claims (2026-08-25 daytime, after drafting)

> **`[R2]` This section records the FPGA session that checked the *draft*. It is superseded in one respect only: §5.2's `P` result stands, but the perf-probe, `RESET_INFO`, `LINK_CAPABILITIES` and `evt_route` claims elsewhere in the document were not exercised here and were later found wrong. §6 records the run of the implemented suite.**

Run on the live FPGA link after the plan above was written. Each block carried a
control that had to behave correctly for the result to count.

### 5.1 Reachability boundary — CONFIRMED

| address | result | verdict |
|---|---|---|
| `0x08000000` boot ROM | `R 0x18003c00` | CONTROL — decodes |
| `0x30000000` undecoded | `R!0x00000000` | CONTROL — errors |
| `0x28000000` cc_periph_0 | `R 0x00000000` | decoded |
| `0x40000000` ETHMAC | `R!0x00000000` | **ERROR — unreachable** |
| `0x40001000` ETHMAC | `R!0x00000000` | **ERROR — unreachable** |
| `0x80000000` CPU1 | `R 0x18003c00` | decoded |
| `0x80001000` CPU1 | `R 0x18003c00` | decoded |
| `0x90000000` CPU1 high | `R 0x00000000` | decoded |

Both controls behaved, so the probe discriminates. **§1.4's boundary is real:
the Ethernet MAC is structurally unreachable from HOSTIO (HIO-415 stands), and
the CPU1 subsystem is reachable.** Note `0x80000000` and `0x80001000` return the
same word — an alias signature, exactly what HIO Tier-2 address-uniqueness is
for; treat CPU1 region size as unestablished.

### 5.2 Poll engine — PROVEN, and HIO-401 passes as specified

```
A x08000000 ; M x00000000
V x00000000 ; P x00000100   ->  P 0x00000001    matched, iteration 1
V x00000001 ; P x00000100   ->  P!0x00000100    no match, full budget, ! flag
```

The predicted discrimination pair holds exactly. `P` **returns the iteration
count on match and the exhausted budget with `!` on timeout** — a bounded,
self-discriminating hardware timer that needs no fault injection. Link alive
afterwards (`C 0x00000000`). This is the single most valuable capability in the
plan: latency measured on-die, independent of the ~130 ms link round-trip.

### 5.3 `0x84xxxxxx` is a CPU1 ROM alias from ADP — hazard is backdoor-specific

```
0x84000000 -> R 0x18003c00     same word as 0x08000000 / 0x80000000
0x84032100 -> R 0x1800006c
0x840321F8 -> R 0xe7fee7fe     ARM Thumb "b ." twice
```

`0xe7fee7fe` is a branch-to-self pair — real ROM code, not a floating bus.
**§1.5 confirmed: the `0x84...` family wedges the PS backdoor but is ordinary
decoded ROM from ADP.** Do not carry the backdoor hazard into HOSTIO procedures.

### 5.4 `M` IS writable — two earlier readings were both wrong

```
M          -> M 0x00000000
Mx0000FF00 -> M 0x0000ff00
M          -> M 0x0000ff00      persists
Mx00000000 -> M 0x00000000      restores
```

The earlier "inconclusive M write" was a client sequencing artefact, and the
explanation offered for it (that it wrote zero) was also wrong — `0x0000FF00`
was written and does stick. `M` is a full read/write operand register, so every
masked-compare test in Tier 4 is executable as written.

### 5.5 CPU0 boot gate reads as ALREADY RELEASED — investigate before Phase F

```
0x29000000 -> R 0x00000004      bit 2 set
0x29000004 -> R 0x00000004      same value (possible alias)
```

§1.6 states `cpu0_bootgate = chip_core_remap_ctrl_w[2]` resets to 0 and HIO-502
releases CPU0 with `W x00000004`. On this FPGA build **bit 2 already reads set**,
i.e. the gate appears open — while IMEM at `0x00000000` is all zeros. If both
readings are right, CPU0 was released into empty memory and is faulting. Two
caveats before acting: the two addresses return identical values, so this may be
an alias rather than the live gate; and this is the FPGA build, not the ASIC.
**Resolve this before Phase F on any die — HIO-502 is irreversible without a
power cycle, and it may already be a no-op here.** **`[R2]` STILL UNRESOLVED as of
the 2026-08-25 evening run — see §6.3.** The implemented HIO-313 records the
boot-gate value and whether bit 2 was already set, and says so in its own record,
but nothing in Tiers 0–4 can distinguish the live gate from an alias, because
`chip_core_remap_ctrl` ignores `HADDR` entirely (`chip_core_remap_ctrl.v:92`).

### 5.6 Net effect on the plan

Upgraded from derived to measured: HIO-401 (poll discrimination), HIO-415
(ETHMAC unreachable), the `0x84...` hazard scoping, `M` operand behaviour, and
the reachability census rows above. Unchanged: everything requiring a peer die,
the ASIC configuration, and all of Tier 5.

---

## 6. `[R2]` Hardware results of the implemented suite (2026-08-25, evening)

The plan above was implemented as an executable suite —
`scripts/rig/eth_chiplet/hostio_suite/{tier0,tier1,tier2_3,tier4_5}.py`, driven by
`harness.py` against the pinned API in `CONTRACT.md` — and run against the die.
**Implementing it is what found the ten errors listed in the Revision 2 box at the
top of this document.** Every one of them was found by writing the test, not by
running it; several of them the run could never have found, because a test that
cannot fail does not announce itself.

### 6.1 Results

| Tier | PASS | FAIL | SKIP | Notes |
|---|---|---|---|---|
| **Tier 0** — port self-test | **10** | **0** | **1** | Over **three consecutive warm runs**, i.e. with the port left inside the monitor by the run before it. That repeatability is the point: the first run's ABORT GATE 2 false red (HIO-002 `[R2]`) was a *warm*-start artefact and would never have shown up on a single cold-die run. |
| **Tier 1** — static identity | **27** | **0** | **1** | The full fingerprint captured. Four expected values were corrected against the die first — HIO-105, HIO-110, HIO-121, HIO-125 — see §0. The §2.1 census was additionally re-run **independently of the suite**, all 35 probes, both controls behaving; two of its classes were wrong (§2.1 `[R2]`). |
| **Tier 2** — memory integrity | **13** | **0** | **0** | Destructive, run deliberately. **Nothing skipped and nothing failed.** |
| **Tier 3** — register behaviour | **14** | **0** | **2** | After the HIO-312 fix. |
| **Tier 4** — dynamic and functional | **10** | **1** | **6** | **The one FAIL is HIO-404 and it is a REAL FINDING, not a test defect — the PHC runs 10× slow. See §6.3.** |
| **Tier 5** — firmware-assisted | — | — | — | **NOT RUN — irreversible, deliberately held.** Do not infer anything from its absence. |

> **`[R2]` Do not read these totals as this document's row counts.** The suite's
> test units do not map one-to-one onto the rows in Tiers 2–4 (this document lists
> 11 / 14 / 15 rows there). **Reconcile coverage by test ID, never by total** —
> a matching total is not evidence that a particular test ran.

**Every SKIP is correct-by-design and none is a defect in the die.** Stated
individually, because "skipped" is where a suite hides the tests it cannot face:

| Skipped | Why, and why that is right |
|---|---|
| **HIO-001** | The runner refuses `HZ.RESET` without an explicit flag. Needs a power-cycle capture the warm runs did not have. |
| **HIO-119** | Discovery-table base address **still unresolved in the built RTL**. SKIPs with that reason rather than guessing a base — this document's own instruction. The one genuinely open item in Tier 1. |
| **HIO-303** | `TC_ERROR` reads `0x00000000`, so **there is no set bit for a W1C to clear and the test would measure nothing**. Recorded clean — *not* a vacuous PASS. This is the same discipline HIO-302 needs on a cold die (HIO-302 `[R2]`), and it is the right answer: a W1C test without a set bit is not a test. **The clean read is itself a result — `TC_ERROR[2] dual_root` is CLEAR on this die.** |
| **HIO-310**, **HIO-413** | The runner refuses `WEDGE_RISK` without an explicit flag. HIO-413 additionally needs a peer die and a human watching (HZ-2). |
| **HIO-412** | DMA-250 channel offsets, start bit and done bit still unresolved. **Note the gate is otherwise OPEN** — the DMA is present and not power-gated on this die (§2.1 `[R2]`). |
| **HIO-415** | Permanently not executable over this port, by construction. Recorded rather than omitted, exactly as intended. |
| **HIO-405**, **HIO-406** | Both declare `needs=["HIO-311"]`, which lives in Tier 3 — a cross-tier dependency the runner voids rather than greens. Run Tier 3 before Tier 4, or run them together. |
| **HIO-501**, **HIO-508** | The **transport**, not the die: the client had no raw-payload transmit call for `U`. Being wired to `adp.raw_tx()`. |

### 6.2 What this result does and does not mean

Stated plainly, because 74 PASS against 1 FAIL is exactly the kind of result this
plan exists to be sceptical of — in both directions:

- **It does mean** the port, the matrix decode for `debug_m`, the reachable map,
  every identity constant in Tier 1 and the two-sided error flag are all confirmed
  on silicon, and that the controls (HIO-007, HIO-401) demonstrably discriminate.
- **It does not mean** the Revision-1 document would have produced this. Run
  literally, Revision 1 would have given **ABORT GATE 2 on a healthy die**
  (HIO-002), **ABORT GATE 6 failing on a healthy cold die** (HIO-402), **three
  false reds from HIO-307**, **four false reds from `B`-class constants** (HIO-105,
  110, 121, 125), a **256-line dump** where HIO-006 wanted one word, **twelve writes
  and polls landing one word past their register — including the irreversible
  HIO-502**, a **false ABORT GATE 5 from two census rows classed `D` that read
  zero** (§2.1), and a **vacuous green on HIO-209 and on ABORT GATE 8**.
- **It does not mean Tier 4 is clean.** Tier 4 carries the run's only FAIL, and
  it is the most consequential single result on this page: **the PHC does not keep
  real time** (§6.3). A tier reported as "10 PASS / 1 FAIL" is not 91 % good; it
  contains one finding that invalidates the PTP subsystem's whole purpose.
- **Tier 5 has not been run at all**, deliberately — it is irreversible. Its
  corrections above come from adjudicating the sequences against RTL while
  implementing them, not from a run, so treat every Tier 5 row as
  corrected-but-unexecuted. **HIO-502's auto-increment defect in particular has
  never been exercised**, and it is the one irreversible action in the plan.

### 6.3 The one FAIL — and its remedy, proven

> ## `[R2]` FINDING — THE PHC DOES NOT KEEP REAL TIME AT RESET. IT RUNS 10x SLOW.
> ## `[R3]` RESOLVED: the clock is fine, `NS_INCR` is wrong, and the fix is a register write.
>
> HIO-404, measured:
>
> ```
> phc_delta_ns        =   577,928,912   over 5.7777 s of wall time
> phc_ns_per_wall_s   =   100,027,307   <- ~100 M ns per REAL second; real time needs 1000 M
> phc_implied_core_hz =    25,006,826   <- ~25 MHz
> phc_ns_incr         =             4   read back from the die
> fabric HCLK         =    25,010,000   <- `[R3]` CORRECTED, see below
> ```
>
> **`[R3]` TWO CORRECTIONS TO REVISION 2'S OWN REASONING.** Both mattered, and
> together they turn an open question into a closed one.
>
> **(a) The fabric is 25.010 MHz, not ~100 MHz.** Revision 2 recorded ~100 MHz
> from P0_CYC deltas whose *interval was estimated rather than measured* — the
> client burns four commands x 2200 ms of pump per snap cycle, so the real
> interval was ~9.68 s, not the ~2.4 s assumed. Wrong by exactly 4x. Re-measured
> with a host timer: **492,193,491 cycles over 19.680 s = 25.010 MHz**, matching
> the routed timing report's 25.011 MHz to 0.004 %.
>
> **(b) `0x05F5E100` at `0x18000000` is NOT an independent clock measurement.**
> It is `SystemCoreClock`, a **firmware build constant** (default 100 MHz in
> `nanosoc_multicore_addrmap.h`). Revision 2 cited it as corroboration; it is
> nothing of the kind. *It is itself a finding*: reading 100 MHz on 25 MHz
> hardware means the loaded image was built for the wrong clock, which also
> implies a 4x UART baud mismatch. See `scripts/check_firmware_clock.sh`.
>
> **So the `implied_core_hz / fabric_hz` ratio is ~1.0, not ~0.25.** The PHC is
> on the fabric clock and counting it correctly. The clock domain is no longer
> unestablished: PHC HCLK <- `u_network_core_sys_hclk` <- eth-SS `sys_hclk`
> pass-through <- chip_core `sys_hclk` <- `assign SYS_HCLK = SYS_FCLK;`
> (`slcorem0p_prmu.v:91-93`). **No divider, prescaler or gate anywhere**, and
> `phc_clock_core.sv` adds `ns_incr` every cycle with no tick divisor.
>
> **The defect is therefore simple and singular: `NS_INCR = 4` is wrong for this
> design's clock, on every target.** Real time needs `NS_INCR x f = 1e9`:
>
> | target | clock | `NS_INCR` needed | reset default | rate at reset |
> |---|---|---|---|---|
> | ASIC | 100 MHz | **10** (exact, no `NS_INCR_FRAC`) | 4 | **0.4x real time** |
> | KR260 FPGA | 25.010 MHz | **40** | 4 | **0.1x real time** |
>
> `DEFAULT_NS_INCR = 8'd4` (`phc_apb_regs.sv:18`) is commented *"4 ns for 250
> MHz"* — a frequency this design has never run at on any target; the ASIC SDC
> says so in terms. It is defaulted to 4 at every instantiation and never
> overridden.
>
> ## `[R3]` THE REMEDY IS PROVEN ON HARDWARE, AND THIS IS NOT A TAPEOUT BLOCKER
>
> `NS_INCR` is **RW** — only the reset default is wrong. Measured on the die,
> both directions, with the PHC enabled:
>
> ```
> NS_INCR = 4    ->  0.1000 x real time
> write 40 (0x28 at 0x22000008), reads back 0x28
> NS_INCR = 40   ->  1.0004 x real time
> restore 4      ->  clean
> ```
>
> **Do not spin the GDS for this.** The fix belongs in **PHC init firmware**:
> write `NS_INCR = 10` on the ASIC. The 0.04 % residual above is the FPGA's
> 25.010 vs 25.000 MHz, not an arithmetic limit; at exactly 100 MHz the ASIC
> divides evenly.
>
> **The residual risk is silence, not function.** The reset default stays wrong,
> so an uninitialised PHC runs at 0.4x real time on ASIC *and reports no error
> while doing it*. A PTP clock that is confidently wrong is worse than one that
> is obviously dead. Three mitigations, in order: (1) firmware sets it during PHC
> bring-up — the actual fix; (2) **HIO-404 is the guard** and already reds on
> "does not keep real time" rather than on an assumed frequency, so an
> uninitialised die is caught; (3) change the reset default in a later revision.
>
> **Caveat:** proven on FPGA. The ASIC instantiates the same IP with the same
> parameter, so the RW behaviour should carry — but that is untested on silicon,
> and FPGA/ASIC divergence has bitten this plan repeatedly (§0).
>
> **This remains the FIRST hardware measurement of the PTP subsystem on this
> part.** It was on the never-tested list until 2026-08-25, so there is no prior
> baseline to say whether the wrong default is a regression or has always been
> true.
### 6.4 `[R2]` State readings recorded on this die

Not verdicts — the die's state at the time of the run, recorded because §0.1 says
first silicon is record-and-classify until a baseline exists.

| Reading | Value | What it means |
|---|---|---|
| **TideLink `fcsm_state`** (HIO-407) | **`8`** | **Outside the documented 0–7 range**, classified "unknown state". `tidelink_regs.rdl` names 1 as the credit-path bring-up wedge, 2 as stalled, and 4–7 as the healthy operating region — **there is no 8**. With `cal = 0`, `lane_locked = 0` and **no peer die attached**, a link that never started is the expected condition, so this is not yet evidence of a fault. But **an FSM reporting a state its own register map does not define is a documentation gap or an encoding bug, and it should not be left unexplained**: either the RDL is short an entry or the field is wider than documented. Resolve before HIO-407's signatures are used to diagnose anything. |
| **XHB bridge** (HIO-409) | **fully healthy** | Both markers valid (`0xB5` at `0x2E0321F8`, `0xAD` at `0x2E0321E0`), `bridge_ready = 1`, `data_healthy = 1`, **all sticky wedge bits clear**. The marker-first discipline this document insists on was applied, so the zeros below the markers are meaningful zeros and not an absent register. |
| **`TC_ERROR`** (HIO-303) | `0x00000000` | **`[2] dual_root` is CLEAR.** The test SKIPs — a W1C with no set bit measures nothing — but the clean read is itself the result. |
| **`TC_DEVICE_CLASS`** | `0x00000002` | Not the `0x00000001` HIO-123 quotes. Per-die strap; see §2.1 `[R2]`. |
| **DMA-250 `IIDR`** | `0x2500043b` | **Present and NOT power-gated** — the documented silicon symptom is absent on this die. |
| **Boot gate `0x29000000`** | `0x00000004` | Bit 2 already set. Still unresolved — §5.5. |

### 6.5 Still open after this run

| Item | Status |
|---|---|
| **The PHC runs 10× slow** | **THE ONE FAIL — a real finding, §6.3.** Resolve the clock source vs. the `NS_INCR` strap. Blocks any use of the PTP subsystem. |
| **TideLink `fcsm_state = 8`** | Undocumented state, §6.4. Link down with no peer, so not yet a fault — but the encoding gap must be closed before HIO-407 is trusted as a diagnostic. |
| **HIO-119** discovery-table base address | **Unresolved in the built RTL.** The one SKIP in Tier 1. Set it once located; never guess it. |
| **HIO-412** DMA-250 channel offsets, start bit, done bit | Still unresolved (`dma250_regdef.h`). NOT-YET-EXECUTABLE, as Revision 1 said — **but its gate is now open: the DMA is present and not power-gated** (§2.1 `[R2]`), so the offsets are the only thing left. |
| **§5.5** CPU0 boot gate reading already-released, and `0x29000000`/`0x29000004` returning the same word | **Unresolved.** The block ignores `HADDR` entirely, so an alias cannot be ruled out from this register alone. **Resolve before Phase F on any die** — HIO-502 is irreversible and may already be a no-op. |
| **HIO-308 / HIO-507** `bus_fault_monitor` register offsets and the initiator-index map | Still `B`-class (`firmware/include/bus_dbg.h`). The `BFM1` magic is now `R`-class; the offsets are not. |
| **HIO-309** `NS_INCR` chiplet reset value | Still not located. Read-then-restore only. |
| **HIO-113** `uart2` PID1/PID2 | Recorded on first use, not asserted — the plan asks for them to be frozen from silicon rather than predicted. Freeze them from this run's record. |
| **HIO-505** may be structurally impossible as written | **Unverified and flagged.** It polls `uart2` RX-buffer-full to recover firmware *console* output — but firmware writes **TX**. Without an external TXD→RXD loop, ADP cannot see console output at all. The board wiring could not be confirmed. **If there is no loop, this is an eleventh error in the plan and the "console substitute" claim in §3.1 is wrong.** |
| **HIO-501 / HIO-508** `U` transport | Was blocked by the client having no raw-payload transmit call, **not** by the die. Being wired to `adp.raw_tx()`. |
| **`TC_DEVICE_CLASS = 0x00000002`** | Recorded, not failed. Confirm the peer die reads something different before concluding the TideChart election has a working tiebreak. |
| Everything requiring a **peer die** (HIO-407/409/410/413, Phase E) | Not run. Unchanged from §5.6. |
| The whole **ASIC** configuration delta (§0.1) | Not run. Every `M`-class TideLink value here is FPGA. |
