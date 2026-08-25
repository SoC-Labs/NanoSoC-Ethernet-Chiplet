# HOSTIO4 / ADP Functional Test Plan — nanoSoC Ethernet Chiplet

**Status:** draft for inclusion in the chiplet functional test plan and for use at ASIC bring-up.
**Author basis:** RTL analysis 2026-08-25 + the FPGA measurements of 2026-08-25 supplied with the task.
**Scope:** everything executable over the 7-wire HOSTIO4 port via the ADP monitor. No SWD, no PS backdoor, no firmware unless a test says so.

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
| 4 | Coverage honesty — throughput, what this port cannot test, and the three likeliest false greens |

---

## 0. Sources, and what is measured vs. derived

Everything in this document is traceable to one of three classes. Rows in the test tables are marked with the class of their *expected value*, because a test whose expected value is derived from a build artefact can go red for a build reason rather than a silicon reason.

| Class | Meaning |
|---|---|
| **M** | Measured on FPGA 2026-08-25 and supplied as ground truth in the task brief. |
| **R** | Read out of RTL / generated RTL in this repo (file:line given). A hardware constant. |
| **B** | Read out of a *build artefact* (firmware hex, generated memmap, discovery yaml). **Build-dependent** — re-derive per die/per image before use. |

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
| `R [hex]` | `ADP_READ` :567 | bus read at address, **address auto-increments**. With a non-zero param it **repeats that many times** (`ADP_LINEACK2` :727-729) — a block dump. |
| `S [hex]` | `ADP_SYSCHK` :664 | push `param[7:0]` into the SoC-side USRT **STDIN** FIFO; `!` if that FIFO will not accept. Not a "self test". |
| `W <hex>` | `ADP_WRITE` :574 | bus write at address, auto-increment. |
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

**`R <n>` is a block dump.** `ADP_LINEACK2` (:727-729) re-arms the read while `adp_count != 0` and the last command was `R`. One `Rx00002000` dumps 8192 words.

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
| `0x2C200000` | `ahb_perf_probe_regs` (per-initiator AHB performance counters) |
| `0x2C300000` | `bus_fault_monitor` (first-fault recorder) |

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
- **Entry preamble, prepended to every test** (from `hostio_adp.py:71-72`): resync the host PIO → send ESC → send one **throwaway** command (the first command after ESC is always rejected with `?`) → then the test's commands.
- **Cost unit.** `1 CU` = one ADP command round trip. **Measured on hardware 2026-08-25 at a 50 ms host pump slice: a 32-bit read (`A`+`R` = 2 CU) takes ~130 ms, 48/48 successful** — so **`1 CU ≈ 65 ms`**. Runtimes below are quoted as `N CU`; the bracketed wall-clock figures use 65 ms/CU. **The cost figures in the tables below were originally written against the repo client's untuned 2200 ms pump defaults and are therefore ~40× pessimistic — read the bracketed times as upper bounds and §4.1 for the measured numbers.**
- **Block commands (`R<n>`, `F<n>`, `U<n>`, `P<n>`) collapse thousands of bus transactions into 1 CU and are the only reason the memory tiers are tractable** — a full 64 KB dump is ~35 min even at the measured rate.
- **PRECONDITION FOR EVERY TEST: the client's resync watchdog must be live.** Measured 2026-08-25: one client configuration (2 ms pump slices) returned **0/16 reads**, every one timing out at 2.5 s, purely because the small slice starved the stuck-detector so the auto-resync never fired; the same code at 50 ms slices was 12/12. **A HOSTIO client without a working resync watchdog looks exactly like dead silicon.** This is the single easiest way to misdiagnose the port, and it is the first thing to check before believing ABORT GATE 1. Counter-intuitively, **smaller pump slices are slower and less reliable** — the bottleneck is per-iteration MicroPython interpreter overhead, not the link.
- **Class** column: `M` measured, `R` from RTL, `B` from a build artefact — see §0.
- Every test's **DISCRIMINATION** cell states the mutation or fault that turns it red. A test with no such mutation is marked **WEAK** and must not be counted as coverage.

---

### Tier 0 — port self-test (11 tests)

Nothing below Tier 0 is meaningful until all of Tier 0 passes.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-001** | **Power-on banner.** Attach the host *before* releasing reset, then power-cycle (or, on a running die, `A x2A000020; W x00000002` — HZ-5). Capture the COM TX stream with no commands sent. | Exactly one line ` 0x50c1ab04` then LF CR, and **no prompt character** (`ADP_WRITEHEX0` :711-714 and `ADP_LINEACK2` :725 take the `banner` path straight to `STD_IOCHK`). PASS = that word, first thing, once. | Dead ADP clock, held `HRESETn`, a broken COM TX path, or a wrong `ADPBASIC` build (which would give `0x50c1ab01`, :64-68) all change or remove it. This is the only test that proves the ADP TX path with **zero** dependence on the RX path. | R | 0 CU + reset | HZ-5 if using swreset |
| **HIO-002** | **Monitor entry.** Send ESC (0x1b). | LF CR then the prompt char `]` (`STD_RXD1` :488-489 → `ADP_LINEACK` → `ADP_PROMPT`). PASS = prompt seen. | If ESC is not recognised (`FNvalid_adp_entry` :86-89) or the RX path is dead, no prompt. Proves the RX path and the STDIO→monitor transition. | R | 1 CU (2.5 s) | — |
| **HIO-003** | **First-command `?` artefact.** Immediately after HIO-002 send `C`. Then send `C` again. | First `C` → `?`. Second `C` → `C 0x…`. PASS = the *second* answers. | **Note:** nothing in the FSM rejects a first command — `ADP_RXCMD`/`ADP_ACTION` have no such rule. The `?` is therefore a **link-layer artefact** (a residual byte in the RX FIFO after `resync()`), not an ADP feature. If a die ever answers the *first* command cleanly, the host link changed, not the SoC. | R+M | 2 CU (5 s) | — |
| **HIO-004** | **Unknown-command rejection.** Send `Z`. | `?` then a new prompt (`ADP_ACTION` else-branch :596, `ADP_UNKNOWN` :662). PASS = `?`. | A parser that accepted anything would answer `Z 0x…`. Proves `FNvalid_cmd`'s default arm. | R | 1 CU | — |
| **HIO-005** | **Address register R/W.** `A x12345678` ; `A` | `A 0x12345678` then `A 0x12345678` (report path :551, `adp_param <= {3'b111, adp_addr}`). PASS = both. | Stuck-at or unwritten `adp_addr` bits show as a mismatch. Use a second pass with `A xEDCBA987` to cover the complementary bit pattern — **run both, one value alone cannot detect a stuck-at-that-value fault.** | R | 4 CU (10 s) | — |
| **HIO-006** | **Access-size encoder.** `A x08000000` ; `R` ; `A x08000000` ; `R1` ; `A x08000000` ; `R100` | `R` → 8 nibbles; `R1` (1 digit) → **2** nibbles; `R100` (3 digits) → **4** nibbles (`FNsize_inc` :143-154 → `FNparam2size` :156-167 → `ADP_WRITEHEX9` :693-698). PASS = the three widths. | A broken digit counter prints the wrong width. This is the test that stops every later test from silently issuing byte accesses. | R | 6 CU (15 s) | — |
| **HIO-007** | **Bus-error flag discrimination — the control pair.** `A x30000000` ; `R` ; `A x08000000` ; `R` | First → `R!0x00000000` (unmapped → default slave ERROR). Second → `R 0x18003c00` (space, not `!`). PASS = **both**, in that order. | This is the plan's master control: it proves the `!` flag can be *both* raised and cleared. If it never raises, every `R!`-based test below is vacuous; if it never clears, every OK-based test is vacuous. **Run it before and after any sweep.** | M+R | 4 CU (10 s) | — |
| **HIO-008** | **Address auto-increment.** `A x08000000` ; `R` ; `R` ; `R` ; `A` | Three consecutive ROM words, then `A 0x0800000c` (increment `1 << adp_size` per completed transfer, :448). PASS = the address advanced by exactly 12. | An `adp_addr_inc` stuck low leaves the address at `0x08000000` and all three reads identical; stuck high advances on non-transfer cycles. Both visible. | R | 5 CU (13 s) | — |
| **HIO-009** | **Block dump.** `A x08000000` ; `Rx00000010` | 16 lines, each `R 0x…`, the first matching HIO-008's first word; then `A` reports `0x08000040`. PASS = exactly 16 lines and the right end address. | If the `ADP_LINEACK2` repeat arm (:727-729) is broken you get 1 line. A miscounted loop gives 15 or 17. Both are unambiguous. | R | 2 CU (5 s) | — |
| **HIO-010** | **Exit / re-enter.** `X` ; then ESC ; then `C` ; `C` | `X` gives LF and drops to `STD_IOCHK` (:576, :671); ESC re-enters and gives a prompt. PASS = a working prompt after the round trip. | Proves the monitor is re-enterable, which every recovery procedure in §3 depends on. If `X` wedged, the port would need a reset to recover. | R | 4 CU (10 s) | — |
| **HIO-011** | **GPO/GPI register and its loopback.** `C` ; `Cx0000020f` ; `C` ; `Cx0000010f` ; `C` | First `C` → `0x000000<param>` with GPO = `0x00`. After `Cx0000020f` (set bits `0x0F`) → **`0x0f0f020f`**: GPO `[23:16]` = `0x0F` and GPI `[31:24]` = `0x0F` too, because the SoC ties `GPI8` to `GPO8` (`nanosoc_multicore_soc.sv:1585-1586`). After `Cx0000010f` (clear bits) → GPO and GPI back to `0x00`. PASS = the three steps. | **The two mirrored bytes are the discriminator**: a report of `0x000f020f` (GPO set, GPI zero) would mean the loopback is broken; `0x0000020f` would mean the set-bits arm never fired. Note what this test does **not** prove: `GPO8` drives **nothing** on this SoC (§1.3), so this is a test of the ADP register and its report path only, never of any system effect. **Use a non-zero low byte** — the measured `Cx00000200` sets nothing and is the null-result form of this test. | R | 5 CU | harmless — GPO is unconnected |

---

### Tier 1 — static identity (27 tests)

All Tier-1 tests are **non-destructive reads**. They are the die's fingerprint and should be captured verbatim into the test record for every die.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-101** | **Eth boot ROM vector table.** `A x08000000` ; `Rx00000010` | Golden dump. Anchors: `[0]=0x18003c00` (initial MSP = DMEM base + 0x3C00), `[1]=0x08000189`, `[2]=0x080001cd`, `[3]=0x080001cf`, `[11]=0x080001d7`, `[14]=0x080001db`, `[15]=0x080001dd`. PASS = byte-exact against the ROM image taped out for this die. | A wrong or unprogrammed ROM changes every word. **Structural back-stop that works with no golden file:** `[0]` must be word-aligned and inside `0x18000000`–`0x18003FFF`; `[1]` must have bit0 = 1 (Thumb) and lie inside `0x08000000`–`0x080007FF`. A garbage ROM fails those. | B (`build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom/stage0_bootrom.hex`), `[0]` also **M** | 2 CU | — |
| **HIO-102** | **CPU1 boot ROM, and discriminating it from CPU0's.** `A x800000e4` ; `R` ; `A x080000e4` ; `R` | CPU1 → `0x08000678`; CPU0 → `0x0800048c`. PASS = the two differ *and* each matches its golden. | The two ROMs' **first 0xE4 bytes are identical** (both vector tables read `0x18003c00, 0x08000189, …`), so a test that compares only the vector table cannot tell them apart and would pass even if both ports were wired to the same ROM. Offset `0xE4` is the first differing word. | B | 4 CU | — |
| **HIO-103** | **CoreSight component ID of `reset_ctrl`.** `A x2a000ff0` ; `Rx00000004` | `0x0000000d, 0x000000f0, 0x00000005, 0x000000b1` → the canonical `0xB105F00D`. PASS = all four. | Hard-coded localparams (`nanosoc_reset_ctrl.v:97-100`). Fails on a dead APB/AHB leg, a mis-decoded region, or a wrong `HADDR[11:2]` path. The four-word pattern cannot be produced by a bus returning zeros, ones, or the last data. **Strongest single identity read on the die.** | R | 2 CU | — |
| **HIO-104** | **Peripheral ID of `reset_ctrl`.** `A x2a000fd0` ; `Rx0000000c` | `PID4..PID7 = 04,00,00,00`; `PID0..PID3 = 26,B8,1B,00` (`nanosoc_reset_ctrl.v:89-96`). PASS = all 12 (note the 4 words at `0xFC0`–`0xFCC` in the same dump read 0 by :185). | Same as HIO-103 but with a *non-uniform* value set including three zeros — it also proves the read mux's `reg_addr[5:2]` decode, which HIO-103 alone does not fully exercise. | R | 2 CU | — |
| **HIO-105** | **`reset_ctrl` reset values.** `A x2a000000` ; `Rx00000009` | `+0x00 REMAP_CTRL = 0` (RAZ), `+0x04 PMU_CTRL = 0` (RAZ), `+0x08 SYS_CTRL = 0`, `+0x0C = 0`, `+0x10 RESET_INFO_CPU0`, `+0x14 RESET_INFO_CPU1`, `+0x18/+0x1C = 0`, `+0x20 SW_RESET` (W, reads 0). PASS = all zero **except** the two RESET_INFO words, which record the last reset cause and are expected non-zero after a power-on (`EXTRESET` bit 3 via `ext_sysresetreq`, :320/:338). | The RESET_INFO words are the discriminator: they must be **non-zero** on a cold die and must change after HIO-503. A block that returned all-zeros unconditionally would pass a naive "reset values are 0" check and fail this one. | R | 2 CU | — |
| **HIO-106** | **Boot-gate register reset value.** `A x29000000` ; `R` | On a **cold** die: `0x00000000` (`chip_core_remap_ctrl.v:115`). On a die where CPU1's stage-0 has run: bit 2 set (`0x00000004`) or bits 0/1/2. PASS = value recorded; a cold-die run must additionally satisfy HIO-107. | This register **is the boot state of the chip**. Its value tells you directly whether CPU0 has been released. Cannot be faked: `HRDATA = {28'b0, remap_q}` (:121). | R | 1 CU | HZ-4 (read only — safe) |
| **HIO-107** | **Boot-gate ↔ CPU0-alive consistency.** Read `0x29000000` (HIO-106), then `A x18000000` ; `R`. | If `0x29000000` bit 2 = 0 → CPU0 has never run → DMEM word 0 must be **unwritten** (zeros or X-pattern on a cold die). If bit 2 = 1 → CPU0 ran its stage-0 scatter-load → DMEM word 0 = `0x05f5e100` (= 100000000 = the generated `SYS_CLK_FREQ_HZ`, i.e. the `SystemCoreClock` initialiser). PASS = the two agree. | This is a **cross-check between two independent observations**, so it fails if either one lies. It is also how the FPGA state of 2026-08-25 is explained: `0x18000000` reading `0x05f5e100` **M** with an empty IMEM means CPU0 *was* released and *did* run its ROM stage-0, then branched into a blank IMEM. If a die shows bit2=1 and DMEM word 0 = 0, CPU0 was released but never executed — a distinct, diagnosable failure. | M + B | 2 CU | — |
| **HIO-108** | **Bus-fault-monitor ID.** `A x2c300010` ; `R` | `0x42464d31` ("BFM1"). PASS = exact. | 4-byte ASCII magic; unforgeable by a stuck bus. Also proves the `ctrl_dbg_group` sub-decode arm `HADDR[21:20]==3` (`ctrl_dbg_group.v:142`). | B (`firmware/include/bus_dbg.h:50-52`) — **confirm against `src/rtl/wrappers/bus_fault_monitor.v` before first use** | 1 CU | — |
| **HIO-109** | **Event-timestamp-capture ID.** `A x2c000000` ; `R` | `0x45544331` ("ETC1"). PASS = exact. | As HIO-108, and proves sub-decode arm 0. | B (`firmware/include/etc_capture.h:45,55`) | 1 CU | — |
| **HIO-110** | **Perf-probe ID + INFO.** `A x2c200000` ; `Rx00000003` | `+0x04 INFO = 0x00000004` (4 probes, `sys_desc/register_maps/perf_probe.yaml:48-52`). **The ID at `+0x00` is disputed between two artefacts in this repo: `sys_desc/register_maps/perf_probe.yaml:40-44` says `0x50524631` ("PRF1"); `firmware/include/perf_probe.h:40-44` says `0x50524601` ("PRF"+v1).** PASS = the value is one of those two, and INFO = 4; **record which**. | The two-artefact disagreement is itself a finding — resolve it against `ahb_perf_probe_regs.v` before freezing the golden. Do **not** assert one value blind: a test written against the wrong constant fails on good silicon, which is the most expensive kind of false red. The INFO word is the sound half: a wrong probe count detects a mis-parameterised instance that a magic-only check would miss. | B (disputed) | 2 CU | — |
| **HIO-111** | **IPC mailbox ID.** `A x23000034` ; `R` | `0xc0de0001`. PASS = exact. | Distinct magic on a *different matrix port* from HIO-108/109/110, so it independently proves the `0x23xxxxxx` decode arm. | B (`firmware/include/nanosoc_multicore_addrmap.h:106`) | 1 CU | — |
| **HIO-112** | **Spinlock owner reset value.** `A x2c100300` ; `R` | `0x00000000` — all 16 locks free (`hw_spinlock.v:179-180`). PASS = zero. | Weak on its own (a dead bus also returns zero) — **it is only meaningful paired with HIO-304**, which makes a specific non-zero value appear. Marked **WEAK ALONE**. | R | 1 CU | **HZ-7** — `0x2C100300` is the DIAG page and is safe; do **not** read `0x2C100000/100/200` here |
| **HIO-113** | **CPU1 UART (`uart2`) CoreSight ID.** `A x28006ff0` ; `Rx00000004` | `0xB105F00D` pattern (CMSDK `cmsdk_apb_uart` ID ROM). PASS = the four words. | Proves the `0x28xxxxxx` (`cc_periph`) matrix port **and** its internal APB slot decode on `PADDR[15:12]` = 6. A collapsed slot decode would return another peripheral's PID, which differs in PID0/PID1. | R (`cmsdk_apb_uart.v` ID ROM) — read out the exact PID words on first use and freeze them | 2 CU | — |
| **HIO-114** | **Memory-map census / decode fingerprint.** For each address in the census list (§2.1), `A x<addr>` ; `R`. Record OK / `!` / NO-REPLY. | The classification must match §1.4 exactly. Three *distinct* outcome classes must all appear: **OK-with-data** (e.g. `0x08000000`), **ERROR** (`0x30000000`, `0x38000000`, `0x40000000`, `0x48000000`, `0x50000000`, `0x60000000`, `0x70000000`, `0xA0000000`, `0xB0000000`, `0xC0000000`, `0xF0000000`, and `0x23000038` — IPC asserts `PSLVERR` above offset `0x34`, `ipc_mailbox_apb_regs.sv:295`), and **OK-with-zeros** (`0x2E036000`, the TideLink reserved quadrant, which answers `prdata=0, pready=1, pslverr=0`, `tidelink_top.sv:845-853`). PASS = full match on all three classes. | **The highest-information single test in Tier 1.** A shifted or collapsed decode moves the OK/`!` boundary immediately. It is inherently **three-sided** — it asserts OK-with-data, ERROR, *and* OK-with-zeros at named addresses — so it cannot pass by measuring nothing, unlike a sweep that only checks "no errors". The OK-with-zeros class matters because it is exactly what a *dead* bus looks like: including a location where zeros are the **correct** answer forces the test to distinguish "correctly zero" from "everything is zero". | R | ~2 CU per probe × ~32 = 64 CU (2.7 min) | census list in §2.1 excludes every HZ address |
| **HIO-115** | **QSPI controller identity (register aperture only).** `A x21000ff0` ; `Rx00000004` ; then `A x21000034` ; `R` | CIDR0–3 = `0x50, 0x51, 0x4c, 0x53` = ASCII `P Q L S` (`apb_qspi_regs.v:104-107`); `CLK_DIV` = `0x00000001` (clamped to a minimum of 1 so a divider of 0 cannot pass HCLK through, `apb_qspi_regs.v:181,196`). PASS = all five. **Also read `0x21000000` and record `CTRL[8]`**: measured `0x00000100` on FPGA 2026-08-25 (XiP already enabled by firmware) against a reset value of 0. | A **non-Arm** CID string, so it cannot be confused with any of the `0xB105F00D` peripherals — that alone proves the `0x21xxxxxx` decode arm goes to the right block. `CLK_DIV=1` is a second, functional non-zero reset. **The XiP aperture `0x24000000` is NOT probed** — see HZ-6; probing it is what a naive "read one word from every region" sweep would do, and it costs 1.3 ms of stall per probe at best. | R | 4 CU | register aperture is safe; **HZ-6** forbids `0x24xxxxxx` |
| **HIO-116** | **Eth REMAP state probe.** `A x00000000` ; `R` ; `A x08000000` ; `R` ; `A x10000000` ; `R` | If `[0x00000000] == [0x08000000]` → REMAP = 0, `0x0` is boot ROM. If `[0x00000000] == [0x10000000]` → REMAP = 1, `0x0` is IMEM. PASS = exactly one of those holds. | Three-way comparison — it cannot be satisfied by a bus that returns a constant, because that would make **both** equalities true, which the PASS criterion rejects. **Note ADP cannot change this bit** (§1.4): the eth `sys_remap_ctrl` lives in the unreachable eth APB block. Observation only. | R | 6 CU | — |
| **HIO-117** | **Single-register-region aliasing fingerprint.** `A x29000000` ; `R` ; `A x29fffff0` ; `R` ; `A x2a000ff0` ; `R` ; `A x2a0ffff0` ; `R` | `chip_core_remap_ctrl` ignores `HADDR` entirely (`chip_core_remap_ctrl.v:92`), so both `0x29` reads are identical. `reset_ctrl` decodes only `HADDR[11:2]`, so `0x2A000FF0` and `0x2A0FFFF0` both return CID0 = `0x0000000d`. PASS = both alias pairs match. | A region that stopped aliasing (i.e. started decoding upper bits and erroring) would break these. More usefully, it documents the true window size so that later sweeps do not mistake an alias for a second register. | R | 8 CU | — |
| **HIO-118** | **Physical-size probe of every RAM (alias wrap detection).** For each RAM: write a unique tag at offset 0, then read at offset `2^k` for k = 10…20 until the tag reappears. Eth IMEM `0x10000000`, eth DMEM `0x18000000`, CPU1 IMEM `0x90000000`, CPU1 DMEM `0x98000000`, shared SRAM `0x2D000000`. | Wrap points: eth IMEM 32 KB, eth DMEM 16 KB, CPU1 IMEM 16 KB, CPU1 DMEM 8 KB, shared SRAM 8 KB (`nanosoc_multicore_soc.sv:24-27,31-33,43`). PASS = each wrap at the declared size. | Detects a RAM built at the wrong depth or a macro not populated — a class the walking-ones tests cannot see, because a 16 KB RAM aliased into a 32 KB window passes walking-ones at every address. **Also flags a known documentation discrepancy:** the generated discovery table declares eth IMEM `TGT_1_SIZE = 0x00010000` (64 KB) while `ETH_IMEM_RAM_ADDR_W = 15` gives 32 KB physical. The silicon is the authority; the discovery table's SIZE fields are not (its bootrom entry says 8 KB for a 2 KB macro). | R | ~14 CU per RAM × 5 ≈ 70 CU (3 min) | destroys RAM contents — run before any preload |
| **HIO-119** | **Interconnect discovery table readback** (if instantiated and mapped on this build — resolve its base first; it is generated as `*_discovery_table` register files). `A x<disc_base>` ; `Rx00000004` | `TABLE_ID = 0x534f4344` ("SOCD"), `TABLE_VERSION = 0x00000001`, `TABLE_SIZE = 0x00200610` (multicore: 16 targets, 6 initiators, 32-bit) / `0x0020040A` (eth), `INTERCONNECT_NAME = 0x746c756d` ("mult") / `0x5f687465` ("eth_"). PASS = magic + the target/initiator counts matching §1.4. | Self-describing table: the counts and the per-target BASE/SIZE words can be **compared against HIO-114's measured census**, giving a machine-checkable agreement test between what the die says its map is and what it actually decodes. Those two disagreeing is a real finding, not a test bug. | B (`build_soc/discovery/*.yaml`) | 2 CU + ~20 CU for the full table | **Base address not yet located in the built RTL — resolve before scheduling. If the tables are not mapped on this build, mark HIO-119 NOT APPLICABLE rather than passing it vacuously.** |
| **HIO-120** | **`ADP` mask/value register readback.** `Mx0f0f0f0f` ; `M` ; `Vxa5a5a5a5` ; `V` ; `Mxf0f0f0f0` ; `M` | Each report echoes the value just written (:583, :590). PASS = all three readbacks exact. | Two complementary patterns on `M` catch stuck-at bits in either direction. This is a **prerequisite** for every `P`-based test — an unwritable mask register would make every poll compare against the wrong thing while still *appearing* to work. | R | 6 CU | — |
| **HIO-121** | **TideLink identity, read-only half.** `A x2e030200` ; `R` ; `A x2e03211c` ; `R` ; `A x2e034fe0` ; `Rx00000004` | `LINK_CAPABILITIES = 0x00080008` (max 8 TX / 8 RX lanes, `wlink_regs.rdl:269,274`); `PHY_ALIGN_ID = 0x50410100` ("PA" v1.0, `axi_chiplet_controller.sv:2922`); addr-translator PIDR0–3 = `0x59, 0x16, 0x15, 0x00` (`tl_addr_trans_regs.sv:61-64`). PASS = all. | **Prefer these to `0x2E030000`.** `0x2E030000` is *RW* — firmware or a previous test can perturb it, so it is not a sound identity register even though it matches on silicon today. `LINK_CAPABILITIES` and `PHY_ALIGN_ID` are pure RO. The addr-translator CIDR (`0x50/0x51/0x4C/**0x54**` at `0x2E034FF0`+) is one byte different from QSPI's (`…0x53`), which is exactly the kind of near-collision that a lazy "check the CID is 0xB105F00D" test cannot see. | R | 6 CU | **HZ-9** (no watchdog on these two sub-regions) |
| **HIO-122** | **TideLink `PHY_GENERAL_CONTROLS` boot value.** `A x2e030000` ; `R` | `0x00010701` = `pre_count=0x01` `[7:0]`, `post_count=0x07` `[15:8]`, `rx_polarity=1` `[16]` (`wlink_regs.rdl:200-219`). PASS = exact **on a die where nothing has written it**. | Field-decoded, so a partial match is diagnosable rather than just "wrong". Marked as a *boot-value* test not an identity test — see HIO-121. | M + R | 1 CU | HZ-9 |
| **HIO-123** | **TideChart identity.** `A x2e04000c` ; `R` ; `A x2e040010` ; `R` | `TC_TIMEOUT = 0x03E81000` (`{enum_timeout=1000, election_timeout=4096}`, `tidechart_apb_regs.sv:425`); `TC_DEVICE_CLASS = 0x00000001` (`tidechart_apb_regs.sv:19`). PASS = both. | **TideChart has no ID/magic register at all** — these two non-zero resets are the only identity handles in the block, and `TC_DEVICE_CLASS` additionally reads back the **per-die strap**. On a two-die pair the two dies must read *different* device classes; if both read `0x0001` the election has no tiebreak and both can settle as root (`nanosoc_eth_chiplet.sv:76-80`). **That makes this test a direct probe for the known dual-root failure.** Do **not** use `TC_RANDOM_ID` (`0x2E04001C`) — it is PUF-derived and differs per die and per boot. | R | 2 CU | reads safe; **never write `0x2E040008`** (bit 3 re-arms the election) |
| **HIO-124** | **DMA-250 identity *and power state*.** `A x20000fc8` ; `R` ; `A x20000fe0` ; `Rx00000004` | `IIDR = 0x2500043B` (product `0x250`, implementer `0x43B` = Arm; `dma250_gen_regif_dmainfo_CFG_MIN_pkg.sv:44-47`); PIDR0–3 = `0x50, 0xB2, 0x0B, 0x00`. PASS = `IIDR` exact. | **`IIDR == 0` is NOT "absent" — it is "present but power-gated".** The DMA-250's registers are gated by `pqen_apb = pwr_en & clk_en`, and this part has a documented silicon symptom of exactly this: *"the DMA-250 is unresponsive on silicon: IIDR read `0x00000000` (sim returns `0x2500043b`) and config-register writes don't stick"* (`docs/DMA250_DESIGN_AND_WORKPLAN.md:69-70,86-88`). So this one read has **three** distinguishable outcomes — correct ID / zero (gated) / `!` (decode fault) — and each is a different diagnosis. Contrast with the naive check "`0x20000000` reads 0, therefore DMA present": `0x20000000` is `SCFG_CHSEC0`, a security-mapping register whose zero value is what a dead bus also returns. **The measured `0x20000000 → 0x00000000` from 2026-08-25 therefore proves nothing about the DMA; HIO-124 is what settles it.** | R | 3 CU | — |
| **HIO-125** | **Event-router load-bearing default.** `A x2b000004` ; `R` ; `A x2b000fe0` ; `R` | `IRQ_ROUTE_CPU1 = 0x0000000F` (`sys_desc/register_maps/evt_route_ctrl.yaml:46-54`, explicitly marked a load-bearing reset default); PID0 = `0x00000022`. PASS = both. | A **non-zero** reset default, so it fails on a bus that returns zeros — the failure mode that makes most reset-value tests worthless. Pair it with the adjacent `IRQ_ROUTE_CPU0` at `0x2B000000`, whose reset **is** zero: the pair proves the block distinguishes two neighbouring registers. | R | 2 CU | reads safe; **never write `0x2B000010`** (`ROUTE_LOCK` is one-way until `HRESETn`) |
| **HIO-126** | **cc_periph slot-decode discrimination.** `A x28000fe0` ; `R` ; `A x28002fe0` ; `R` ; `A x28006fe0` ; `R` ; `A x28008fe0` ; `R` | PID0 = `0x22` (timer0), `0x23` (dualtimer), `0x21` (uart2), `0x24` (watchdog) — `cmsdk_apb_timer.v:63-74`, `cmsdk_apb_dualtimers.v:232-234`, `cmsdk_apb_uart.v:85-96`, `cmsdk_apb_watchdog.v:122-124`. PASS = four **different** values in the right slots. | **Four distinct part numbers in four slots is the strongest decode test on the die.** A collapsed `PADDR[15:12]` decode returns the same PID four times — which a per-peripheral "CID is `0xB105F00D`" test would happily pass, because all four share the same CID. This is the concrete instance of the "check that the check can tell things apart" rule. **Do not assert PID3** (`+0xFEC`): it packs `ECOREVNUM` and is revision-dependent (`cmsdk_apb_timer.v:174`). | R | 8 CU | reads safe; **never write the watchdog** (arming it starts a reset countdown). Slots `0x4000`/`0x5000` (USRT0/1) are tied off inside the wrapper — skip them. |
| **HIO-127** | **Non-zero counter reset values.** `A x28002004` ; `R` ; `A x28008000` ; `R` ; `A x28008004` ; `R` | Dualtimer `TIMER1VALUE = 0xFFFFFFFF` (resets high to avoid a spurious interrupt at start, `cmsdk_apb_dualtimers_frc.v:460-465`); watchdog `WDOGLOAD = 0xFFFFFFFF` and `WDOGVALUE = 0xFFFFFFFF` (`cmsdk_apb_watchdog_frc.v:204,360`). PASS = all three all-ones. | The **complement** of every zero-reset test in this tier: an all-ones expected value fails on a bus stuck at zero, and the zero-reset tests fail on a bus stuck at ones. Running both classes is what makes the reset-value tier two-sided. | R | 3 CU | reads safe |

---

### 2.1 HIO-114 census probe list

Each entry is one `A x<addr>` + `R` pair. `E` = must report `!`, `D` = must report OK with meaningful data, `Z` = must report OK with `0x00000000`.

| Addr | Cls | Addr | Cls | Addr | Cls |
|---|---|---|---|---|---|
| `0x00000000` | D | `0x23000000` | Z | `0x2C300010` | D |
| `0x08000000` | D | `0x23000034` | D | `0x2D000000` | D/Z |
| `0x10000000` | D/Z | `0x23000038` | **E** | `0x2E030200` | D |
| `0x18000000` | D | `0x28000fe0` | D | `0x2E036000` | **Z** |
| `0x1FFFFFF0` | D | `0x29000000` | D/Z | `0x2E040010` | D |
| `0x20000fc8` | D | `0x2A000ff0` | D | `0x30000000` | **E** |
| `0x21000ffc` | D | `0x2B000004` | D | `0x38000000` | **E** |
| `0x80000000` | D | `0x2C000000` | D | `0x40000000` | **E** |
| `0x90000000` | D/Z | `0x2C200004` | D | `0x48000000` | **E** |
| `0x98000000` | D/Z | `0x50000000` | **E** | `0x60000000` | **E** |
| `0x70000000` | **E** | `0xA0000000` | **E** | `0xB0000000` | **E** |
| `0xC0000000` | **E** | `0xF0000000` | **E** | | |

**Excluded by hazard, deliberately:** all of `0x2E0321A0`–`0x2E0321B8` (HZ-1), all of `0x2F000000`+ (HZ-2), `0x2E000000`–`0x2E003FFF` (HZ-3), `0x24000000`+ (HZ-6), `0x2C100000`/`100`/`200` (HZ-7), `0x2E032020`/`024`/`038`/`15C`/`160`/`168` (HZ-8). **This exclusion list is part of the test — it must be encoded in the census script, not left to the operator.**

---

### Tier 2 — memory integrity (11 tests)

These are the tests the block engines were made for. **Always destructive** — schedule before any firmware preload, and re-run HIO-007 immediately after each one to prove the error flag still discriminates.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-201** | **Eth IMEM walking-ones/zeros (data-bus integrity).** At `0x10000000`: for each of 32 patterns `1<<k`, `A x10000000` ; `W x<pat>` ; `A x10000000` ; `R`. Then repeat with `~(1<<k)`. | Each readback equals the pattern written. PASS = all 64. | Detects stuck-at, bridged and open data-bus bits. A bridged pair `Dn`/`Dm` fails the walking-ones half; a stuck-at-1 fails walking-zeros. **Running only walking-ones is the classic half-blind version — both halves are required.** | R | 256 CU (11 min) | destructive |
| **HIO-202** | **Eth IMEM address uniqueness (aliasing / address-bus integrity).** Write each address's own value into it: for k = 0…12, `A x1000<off>` ; `Wx1000<off>` at offsets `4<<k` plus offset 0; then read all of them back. | Every location holds its own address. PASS = all match. | An address line stuck or shorted makes two locations the same cell, so one write overwrites another and the readback shows a *different* address's value. **The `F` engine cannot do this test** — it writes one constant, so an aliased RAM passes an `F`+verify perfectly. This is why HIO-202 exists next to HIO-210. | R | 28 CU | destructive |
| **HIO-203** | **Eth IMEM bulk pattern via the fill engine.** `A x10000000` ; `Vx5a5a5a5a` ; `Fx00002000` ; `A x10000000` ; `Rx00002000` | 8192 words all `0x5a5a5a5a`, no `!` on the `F` reply. PASS = the whole dump matches. | Covers every cell, which HIO-201/202 do not. Catches single-bit cell failures and decoder faults inside the macro. **Beware the `F` off-by-one hole (§1.5): the final beat's `HRESP` is not captured** — so follow with `A x10007ffc` ; `R` ; `W x5a5a5a5a` to prove the last word explicitly. | R | 3 CU + 1 CU dump (the dump streams 8192 × 15 bytes — see §5) | destructive; **V must have ≥5 hex digits or `F` writes bytes** |
| **HIO-204** | **Eth IMEM inverse bulk pattern.** As HIO-203 with `Vxa5a5a5a5`. | All `0xa5a5a5a5`. PASS = whole dump. | The complementary pattern; a cell stuck at `0x5a5a5a5a`'s value passes HIO-203 and fails here. Running only one polarity is the "measured nothing" failure mode. | R | 4 CU | destructive |
| **HIO-205** | **Eth DMEM (16 KB @ `0x18000000`).** HIO-201/202/203/204 pattern, `Fx00001000`. | As above. | As above. **This RAM currently holds `SystemCoreClock` at word 0 (HIO-107)** — capture that value before destroying it if the boot-state inference matters. | R | ~290 CU | destructive |
| **HIO-206** | **CPU1 IMEM (16 KB @ `0x90000000`).** As HIO-205. | As above. | Reaches CPU1's memory through the remap-independent `0x9x` alias, so it works whatever CPU1's REMAP bit says. **Do this with CPU1 halted if possible** — CPU1 runs from power-on and executes out of this space, so a live CPU1 will fight the test. See §3 for the ordering constraint. | R | ~290 CU | destructive; **CPU1 is running** |
| **HIO-207** | **CPU1 DMEM (8 KB @ `0x98000000`).** As HIO-205, `Fx00000800`. | As above. | As HIO-206 — CPU1's stack lives here. | R | ~290 CU | destructive; **CPU1 is running** |
| **HIO-208** | **Shared cross-core SRAM (8 KB @ `0x2D000000`).** As HIO-205, `Fx00000800`. | As above. | This RAM is the only one reachable by *both* CPUs and the ADP, so it is the medium for every later handshake test (HIO-410, HIO-504). Its integrity must be established before those. | R | ~290 CU | destructive |
| **HIO-209** | **ROM write-protection.** `A x08000000` ; `R` (record) ; `W xdeadbeef` ; `A x08000000` ; `R` | The ROM word is **unchanged**. The `W` may report OK or `!` — record which. PASS = value unchanged. | A ROM that accepted writes would be RAM, which is a real integration failure (wrong macro instantiated). Repeat at `0x80000000` for CPU1's ROM. **This test can fail** — that is the point. | R | 8 CU | — |
| **HIO-210** | **Byte-lane integrity.** `A x10000000` ; `Wx00000000` ; then for lane L = 0..3: `A x1000000<L>` ; `WFF` (**2 digits = byte write**) ; `A x10000000` ; `R` | After lane L's byte write, the word reads `0x000000FF << (8L)` cumulatively: `0x000000FF`, `0x0000FFFF`, `0x00FFFFFF`, `0xFFFFFFFF`. PASS = the four steps. | Exercises the `HWDATA` byte replication (`socdebug_adp_control.v:338-340`) and the RAM's byte-enable decode. A broken byte-enable writes all four lanes at once, giving `0xFFFFFFFF` on the first step. **This is the only test in the plan that deliberately uses a short parameter.** | R | 12 CU | destructive |
| **HIO-211** | **Retention / short soak.** After HIO-203 (`0x5a5a5a5a` fill), wait a defined interval with the port idle (60 s), then `A x10000000` ; `Rx00000100` and spot-check `A x10007ffc` ; `R`. | Unchanged. PASS = identical dump. | Catches retention failures and, more usefully in practice, **catches another agent (a CPU, the DMA, a cross-die write) mutating memory behind your back**. A change here during a supposedly quiescent window is a finding in its own right. | R | 3 CU + 60 s | — |

---

### Tier 3 — subsystem register behaviour (14 tests)

Reset values were Tier 1. This tier proves the registers *behave*: that RW bits are writable, RO bits are not, W1C bits clear only on a 1, and write-only bits do not read back.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-301** | **`reset_ctrl.SYS_CTRL` RW bit.** `A x2a000008` ; `Wx00000001` ; `A x2a000008` ; `R` ; `Wx00000000` ; `A x2a000008` ; `R` | Reads `0x00000001` then `0x00000000` (`nanosoc_reset_ctrl.v:201-215`, readback `:164`). PASS = both. | The **first RW register proven writable through ADP on a peripheral** (as opposed to a RAM). If this fails but Tier-1 reads pass, the ADP write path or `HWDATA` routing is broken while reads work — a failure mode that a read-only test suite cannot see at all. **Restore to 0 afterwards:** leaving `LOCKUPRESETEN` set makes a later CPU lockup silently reset that CPU and corrupt subsequent tests. | R | 6 CU | leaves a global behaviour change if not restored |
| **HIO-302** | **`reset_ctrl.RESET_INFO_CPU0` W1C semantics.** `A x2a000010` ; `R` (record `v`) ; `Wx00000000` ; `A x2a000010` ; `R` ; `Wx<v>` ; `A x2a000010` ; `R` | Writing **0** must leave `v` unchanged; writing `v` must clear it to `0`. PASS = both steps (`nanosoc_reset_ctrl.v:316-320`: `nxt = (~(write & HWDATA[n])) & reg[n] \| <cause>`). | **The write-0 step is the whole test.** A register wired as plain RW would be cleared by the write-0 and pass a naive "write then read 0" check. Testing W1C without the write-0 negative control measures nothing. | R | 8 CU | destroys the reset-cause record — capture it (HIO-105) first |
| **HIO-303** | **TideChart `TC_ERROR` W1C.** `A x2e04002c` ; `R` ; `Wx00000000` ; `R` ; `Wx00000007` ; `A x2e04002c` ; `R` | Same shape as HIO-302 on a second, independent W1C implementation. Bits: `[0]` election_timeout, `[1]` enum_timeout, `[2]` **dual_root**. PASS = write-0 inert, write-1 clears. | Same negative control. Additionally, `[2] dual_root` is the sticky flag for the known TideChart dual-root behaviour — **reading it non-zero before you clear it is a real result, not a test artefact.** Record it. | R | 8 CU | destroys a sticky error record — read it first |
| **HIO-304** | **Spinlock acquire / owner / force-release — the strongest side-effect test on the die.** `A x2c100300` ; `R` ; `A x2c100200` ; `R` ; `A x2c100300` ; `R` ; `A x2c100304` ; `Wx00000001` ; `A x2c100300` ; `R` | `OWNER` = `0x00000000` → read of the **DBG page** lock 0 returns 1 (granted) → `OWNER` = `0x00000003` (`OWN_DBG` in bits `[1:0]`, `hw_spinlock.v:118-124,199-200`) → force-release → `OWNER` = `0x00000000`. PASS = all four. | **This is a value that nothing else on the die can produce.** `0b11` in the owner field appears only if an access arrived through `HADDR[9:8] == 2`, i.e. the debug page — so it proves ADP's read reached the block *and* that the requester-page decode works, in one observation. A stuck bus, a mirrored read, or a decode that ignores `HADDR[9:8]` all fail. It is also fully reversible. | R | 8 CU | **HZ-7** — only pages 0/1/2 acquire; `0x2C100300`/`0x304` are DIAG and safe. Always force-release. |
| **HIO-305** | **IPC mailbox R/W + W1C + aperture edge.** `A x23000000` ; `Wx5a5a5a5a` ; `A x23000000` ; `R` ; `A x23000030` ; `Wx00000001` ; `R` ; `A x23000028` ; `R` ; `A x23000038` ; `R` | Slot-0 data word 0 reads back `0x5a5a5a5a`; `LOCK` reads back `0x00000001`; `IRQ_STATUS` reads `0` (nothing has posted); **`0x23000038` reports `!`** (`ipc_mailbox_apb_regs.sv:83,295` — `PSLVERR` above word index 13). PASS = all four. | The `0x23000038` ERROR is the discriminator: this block was deliberately fixed (bug N1, `:269-272`) so in-range holes read **0** rather than aliasing, while out-of-range **errors**. A test that only probed `0x23000000` could not tell a correctly-bounded aperture from one that aliases the whole 16 MB. | R | 10 CU | restore slot 0 and `LOCK` to 0 afterwards — CPU1 firmware uses them |
| **HIO-306** | **`etc_capture` CTRL RW.** `A x2c000004` ; `Wx00000003` ; `A x2c000004` ; `R` ; `Wx00000000` ; `A x2c000004` ; `R` | `0x00000003` then `0x00000000` (`[0]` GLOBAL_EN, `[1]` IRQ_EN, `etc_capture.yaml:55-72`). PASS = both. | Proves `ctrl_dbg_group` sub-decode arm 0 accepts writes, not just reads. **Note leaf 0 takes one wait state on reads** (`ctrl_dbg_group.yaml:20-21`) — bounded, not a stall, but it means this leaf exercises the ADP's `HREADY` wait path, which the three zero-wait leaves do not. That makes HIO-306 the only test that proves ADP handles a wait state at all. | R | 6 CU | leave GLOBAL_EN = 0 |
| **HIO-307** | **Write-only register asymmetry.** `A x2c200008` ; `R` (record) ; `Wx00000002` ; `A x2c200008` ; `R` ; then `A x2c200040` ; `R` | `perf_probe.CTRL` is **WO** (`perf_probe.yaml:57-75`); its read value must **not** be `0x00000002`. The `CLR` write must make `P0_CYC` at `0x2C200040` restart from a small value. PASS = the read is not the written value **and** `P0_CYC` visibly reset. | A block that implemented WO as RW would return `0x00000002`. More importantly the `P0_CYC` restart is the *functional* proof that the write had an effect — without it, "the read didn't match" is indistinguishable from "the write went nowhere". **This test needs both halves.** | R | 8 CU | clears all perf counters — do not run mid-measurement |
| **HIO-308** | **`bus_fault_monitor` W1C + record.** `A x2c300000` ; `R` ; `A x2c300004` ; `R` ; `A x2c30000c` ; `R` ; `A x2c300000` ; `Wx00000001` ; `A x2c300000` ; `R` | `FAULT_STAT` `[0]` FAULT_SEEN (W1C), `[5:4]` INIT_IDX, `[8]` OVERFLOW; `FAULT_ADDR`, `FAULT_COUNT`. Write-1 clears the whole record and re-arms. PASS = the record reads coherently and clears. | **Important scope limit: `debug_m` is NOT one of the four monitored initiators.** The map is 0 `eth_ss_m` (CPU0), 1 `cpu_ss_1_m` (CPU1), 2 `dmac_0_m`, 3 `dap_ss_0_m` (`firmware/include/bus_dbg.h:11-13`; the same four initiators are the ones tapped for the perf probes at `nanosoc_multicore_soc.sv:827-834`, and `debug_m` is absent from both — **confirm against `src/rtl/wrappers/bus_fault_monitor.v` before freezing this test**). **ADP therefore cannot record its own faults** — so this test cannot be self-stimulated in Tier 3 and only becomes a *live* test in HIO-507. Marked **WEAK until paired with HIO-507**: on its own it proves the register file, not the monitor. | B | 8 CU | destroys a fault record — read it first |
| **HIO-309** | **PHC configuration registers RW/RO split.** `A x22000008` ; `R` (record `n`) ; `Wx00000005` ; `R` ; `Wx<n>` ; then `A x2200001c` ; `Wx00000003` ; `R` ; `Wx00000000` ; then `A x22000028` ; `Wxdeadbeef` ; `A x22000028` ; `R` | `NS_INCR` and `INT_EN` are RW and read back. `CAP_NANOSECONDS` (`0x22000028`) is **RO** — the write must not change it (`phc_regs.rdl:196-200`). PASS = the two RW readbacks **and** the RO non-change. | The RO half is the discriminator. A register file that made everything RW would pass both RW checks. **Restore `NS_INCR` to the value you recorded** — its reset is parameterised (`DEFAULT_NS_INCR`, RDL default 4) and the chiplet override was not located, so it must be read-then-restored, never written blind. | R (RDL) / ❓ (reset value) | 12 CU | **PHC cannot stall** — `pready=1'b1` unconditional (`phc_apb_regs.sv:400-401`). Do **not** poll `0x22000004`: `STATUS[1] pps_sticky` is read-to-clear (`phc_regs.rdl:78`) and a polling loop eats every PPS event. |
| **HIO-310** | **TideLink read-only census with the quarantine enforced.** Sweep `0x2E032000`–`0x2E0321FC` step 4, **skipping** `0x1A0`–`0x1B8` and `0x020`/`0x024`/`0x038`/`0x15C`/`0x160`/`0x168`. Read each twice. | Record every value. Each register reads the **same value twice** unless it is a live counter. PASS = the sweep completes, the skip list was honoured, and no address reports NO-REPLY. | The double-read is the point: it separates *stable* registers from *live* and *read-clearing* ones without needing a golden file. **The test's real subject is the blocklist:** if the script's skip list is wrong you find out by hanging the port, and per `03_addrmap_param.md:105-112` **simulation can never catch that mistake for you** — in RTL those addresses are combinational reads with `pready=1`. Dry-run the skip list against the address generator before first silicon use. | R | ~256 CU (11 min) | **HZ-1, HZ-8** — this test exists partly to validate the blocklist |
| **HIO-311** | **cc_periph timer0 RW.** `A x28000000` ; `R` ; `A x28000004` ; `Wx00010000` ; `A x28000004` ; `R` ; `A x28000008` ; `R` | `CTRL` reset `0x00000000` (`cmsdk_apb_timer.v:122,156`); `RELOAD` accepts `0x00010000`; `VALUE` readable. PASS = the reload readback. | Proves the `cc_periph` APB write path (HIO-126 only proved reads). Sets up HIO-406. | R | 8 CU | leave `CTRL` = 0 until HIO-406 |
| **HIO-312** | **QSPI register RW without any flash activity.** `A x21000008` ; `Wx00000003` ; `A x21000008` ; `R` ; `Wx00000000` ; then `A x2100000c` ; `Wx00123456` ; `A x2100000c` ; `R` ; `Wx00000000` | `CMD` and `ADDR` read back (`apb_qspi_regs.v:174-175`). PASS = both. **`CMD[8]` (enable) must stay 0** — `0x00000003` sets only the command byte, never the enable. | Deliberately exercises the QSPI block **without starting a flash transaction**, so it is safe with or without a device fitted. `ADDR` is 22 bits (`apb_qspi_regs.v:136`), so writing `0x00123456` and reading back `0x00123456` also confirms the width — writing `0xFFFFFFFF` and reading `0x003FFFFF` would confirm it more sharply, and is the better version if you want the width proven. | R | 10 CU | never set `CMD[8]`; **HZ-6** still forbids `0x24xxxxxx` |
| **HIO-313** | **Boot-gate write path, non-destructively.** `A x29000000` ; `R` (record `v`) ; `Wx00000000` ; `A x29000000` ; `R` | Unchanged: `remap_q <= remap_q \| HWDATA[3:0]` (`chip_core_remap_ctrl.v:117`), so OR-with-0 is a guaranteed no-op. PASS = the value is identical and the write reported OK. | **This is how you prove the write path to the most dangerous register on the die without arming anything.** It converts HZ-4 from "we daren't touch it" into "we have exercised it safely". If this write reports `!` or the readback changes, do **not** proceed to HIO-502. | R | 4 CU | **HZ-4** — the parameter must be exactly `x00000000`; any set bit here is irreversible |
| **HIO-314** | **RO-immutability sweep.** For each of `0x2A000FF0` (CID0), `0x2E030200` (LINK_CAPABILITIES), `0x2E040010` (TC_DEVICE_CLASS), `0x23000034` (IPC PERIPH_ID), `0x20000FC8` (DMA IIDR): `A x<addr>` ; `Wxffffffff` ; `A x<addr>` ; `R`. | Every one reads its Tier-1 value unchanged. PASS = all five. | The mirror image of HIO-301: it proves the identity constants used throughout Tier 1 are **actually constants** and not RW registers that happen to hold the right value. Without this, every Tier-1 identity test is one stray earlier write away from being meaningless. | R | 20 CU | writes to RO registers are harmless here by construction — but do **not** extend this sweep to any address not on this list |

---

### Tier 4 — dynamic and functional (15 tests, one of them structurally impossible and recorded as such)

This is where the `P` engine earns its place: every "wait until" below runs in hardware at `HCLK` and costs **one** command.

| ID | Purpose / commands | Expect + PASS criterion | DISCRIMINATION — how it goes red | Cls | Cost | Hz |
|---|---|---|---|---|---|---|
| **HIO-401** | **Poll-engine self-test — the built-in discrimination pair.** (a) `A x08000000` ; `Mx00000000` ; `Vx00000000` ; `Px00000010` — then (b) `Mx00000000` ; `Vx00000001` ; `Px00000010` | (a) → `P 0x00000001` (matched on the first read; space, not `!`). (b) → `P!0x00000010` (budget exhausted; `!`). PASS = **both**, exactly. | With mask 0 the compare is `0 ^ V == 0`, so (a) **must** match and (b) **can never** match, whatever the DUT contains. This proves, with no fault injection and no DUT dependency, that the poll loop actually iterates, actually compares, actually counts down, and actually distinguishes match from timeout. **Every other `P`-based test in this tier is vacuous without it — run it first, every session.** | R | 8 CU | — |
| **HIO-402** | **The fabric clock is running.** `A x2c200040` ; `R` ; `R` (the second `R` after the auto-increment, so re-issue `A x2c200040` between them) — record two `P0_CYC` values ~5 s apart. | The second value is greater than the first. PASS = strictly increasing. | `P0_CYC` is a free-running cycle counter (`perf_probe.yaml:80`). If `HCLK` has stopped, everything else in this plan still "works" (registers hold their values, reads return data) and **only this test goes red.** It is the one test that can distinguish "the die is clocked" from "the die is latched". **Caveat: it is saturating** — if it has already saturated it stops increasing and the test false-fails; issue `A x2c200008` ; `Wx00000002` (CLR) first, which is HIO-307. | R | 6 CU | HIO-307's CLR clears all probes |
| **HIO-403** | **PHC enable + capture protocol.** `A x22000000` ; `Wx00000001` ; `A x22000004` ; `R` ; `A x22000000` ; `Wx00000005` ; `A x22000028` ; `R` ; `A x22000000` ; `Wx00000005` ; `A x22000028` ; `R` | `STATUS[0] running` = 1 after enable. The two `CAP_NANOSECONDS` reads differ. PASS = running = 1 **and** the two captures differ. | **The single most likely false-fail in this whole plan, and the reason this test is written out step by step:** `CTRL` resets to `0x00000000`, i.e. *"counter frozen"* (`phc_regs.rdl:39-62`). Out of reset the PHC **will not advance** and a naive "read the counter twice" test reports a dead clock on a perfectly good die. Also note `capture` (bit 2) is a self-clearing single pulse and **bit 0 must be re-asserted in the same write** (`Wx00000005`, not `Wx00000004`) or the write stops the clock. There is **no live-readable counter register** — the read mux (`phc_apb_regs.sv:333-397`) reaches only the `cap_*` sets, so the shadow-latch protocol is mandatory, not optional. | R | 14 CU | leaves the PHC enabled — that is usually what you want |
| **HIO-404** | **PHC advance rate.** Two `CAP_NANOSECONDS` captures separated by a host-measured interval `T`. | `Δns / T` ≈ `NS_INCR × f_core`. With `NS_INCR = 4` and a 250 MHz core, ≈ 1 ns per ns. PASS = within ±10 % of the rate implied by the `NS_INCR` you read in HIO-309. | Detects a wrong `NS_INCR` strap or a core clock at the wrong frequency — both invisible to HIO-403, which only asks "did it move". Use `CAP_NANOSECONDS[15:0]`; the fraction register `CAP_NS_FRAC` (`0x2200002C`) is **static on a fresh part** because `NS_INCR_FRAC` resets to 0, so do not use it as the liveness signal. `CAP_SECONDS_LO` moves once per second — too slow. | R | 8 CU + wall time | — |
| **HIO-405** | **Hardware latency measurement via `P`'s return value.** `A x22000028` ; `Mx0000ffff` ; `Vx00000000` ; `Px00100000` | `P 0x<n>` where `n` is the number of bus reads taken for `CAP_NANOSECONDS[15:0]` to reach 0. PASS = a plausible `n` and no `!`. | This is the capability that makes `P` more than a convenience: `n` is measured **in bus transactions at `HCLK`**, entirely free of the 6-beat-per-byte link. It is the only way this port can measure a hardware interval to better than link resolution. **Caveat:** the polled address must be re-captured to advance, so for the PHC this measures the *stale* latch — use it instead on a genuinely free-running location such as `P0_CYC` or a timer `VALUE`. Treat the PHC form as a demonstration of the mechanism, not as a PHC measurement. | R | 8 CU | — |
| **HIO-406** | **Timer counts down, waited on in hardware.** `A x28000004` ; `Wx00010000` ; `A x28000000` ; `Wx00000001` ; `A x28000004` ; `Mxffffffff` ; `Vx00000000` ; `Px00100000` ; then `A x28000000` ; `Wx00000000` | The `P` returns a match with an iteration count roughly proportional to the reload. PASS = match (not `!`) and the count is within an order of magnitude of the reload. | Two independent things must both be true for this to pass — the timer must actually count *and* the poll must actually terminate — so it cross-validates HIO-401 against real hardware. **Negative control:** repeat with `CTRL` left at 0 (timer disabled); it must then **time out** with `P!`. Run both polarities. | R | 18 CU | disable the timer afterwards |
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
| **HIO-501** | **Preload CPU0 IMEM and verify.** `A x10000000` ; `Vx00000000` ; `Fx00002000` (zero the RAM) ; `A x10000000` ; `Ux00001000` + 4096 raw payload bytes ; `A x10000000` ; `Rx00000400` | The dump matches the image. PASS = byte-exact. | `U` forces byte size and writes one byte per link byte (`socdebug_adp_control.v:633-639`), so the count is in **bytes and must exactly equal the payload length** — see the hazard. **The `F` pre-zero is what makes the verify meaningful:** without it, a `U` that wrote nothing would still verify against whatever was already there. **Also verify the final byte explicitly** (`A x10000fff` ; `R`) because of the last-beat `HRESP` hole in `U` (§1.5). | R | ~4 CU + payload | **`U` has no abort and no timeout.** If you send fewer bytes than the count the FSM waits in `ADP_UREADB` forever and `0x04`/`0x00` are *data*, not escapes. Recovery is a host PIO resync. |
| **HIO-502** | **Release CPU0.** Gate on HIO-313 (write path proven safe) and HIO-501 (image loaded and verified). `A x29000000` ; `R` (record) ; `Wx00000004` ; `A x29000000` ; `R` | Bit 2 set: `NETWORK_CORE_BOOTGATE`. `cpu0_resetn = cpu0_bootgate & ~cpu0_reset_pulse` (`nanosoc_reset_ctrl.v:363`), gate from `chip_core_remap_ctrl_w[2]` (`nanosoc_multicore_soc.sv:1388`). PASS = the readback shows bit 2 and CPU0 shows life in HIO-504. | **This is the answer to "can ADP release a CPU": yes, by an AHB write, not by GPO.** It goes red if the readback does not change (a broken write path — but HIO-313 already ruled that out) or if CPU0 shows no life afterwards, which is then a *firmware* or *reset-tree* result, not a debug-port result. | R | 4 CU | **HZ-4 — irreversible until power cycle.** Once set, CPU0 contends for the bus and mutates memory; every quiescent-bus test above becomes unrepeatable. |
| **HIO-503** | **Repeatable CPU0 relaunch.** `A x2a000020` ; `Wx00000001` ; then re-run HIO-504. | `CPU0_SWRST` fires a stretched self-clearing reset pulse (`nanosoc_reset_ctrl.v:222-239,271-285`); `RESET_INFO_CPU0` records the cause. PASS = CPU0 restarts and the reset-info record changes. | **The relaunch primitive, and it does not touch HOSTIO.** It makes the whole of Tier 5 iterable: reload IMEM with `U`, pulse `CPU0_SWRST`, observe again — no power cycle, no re-arming the bootgate. It goes red if the pulse does not restart CPU0 (visible as an unchanged `RESET_INFO_CPU0` and unchanged firmware behaviour). | R | 4 CU | resets CPU0 only — **bit 1 is a different matter, see HIO-509** |
| **HIO-504** | **Firmware liveness via shared SRAM.** Load a firmware that writes an incrementing heartbeat to `0x2D000000`. Then `A x2d000000` ; `R` ; wait ; `A x2d000000` ; `R` ; and `Mxffffffff` ; `Vx<expected>` ; `Px00100000`. | The heartbeat advances. PASS = strictly increasing across two reads, or a `P` match on a sentinel. | The `P` form is the strong one: it waits for a **specific** value the firmware will write, so a stuck heartbeat, a wrong value, and a dead CPU are all distinguishable from success. A two-read comparison alone cannot tell "advancing correctly" from "advancing wrongly". | R | 8 CU | shared SRAM must not have been clobbered — see §3 ordering |
| **HIO-505** | **Firmware console, polled from ADP.** With CPU1 or CPU0 firmware writing to `uart2`: `A x28006004` ; `Mx00000002` ; `Vx00000002` ; `Px00100000` (wait for RX-buffer-full) ; then `A x28006000` ; `R`. Repeat, or poll TX state to inject. | Characters recoverable one at a time. PASS = readable text. | **This is the console substitute, and it matters because ADP's own STDIO path is dead on this SoC** (§1.3: the debug USRT's APB slave is tied off at `nanosoc_multicore_soc.sv:1571-1575` and it has no pins). `uart2` at `0x28006000` is the CPU1 console and *is* ADP-reachable, so the console exists — just not through `S`/`X`. **Confirm the CMSDK `STATE` bit polarity against `cmsdk_apb_uart.v` before writing the mask**; a wrong mask polarity gives a poll that always matches, which looks exactly like success. | R (block) / ❓ (bit polarity) | ~4 CU per char | slow — see §5 |
| **HIO-506** | **Ethernet MAC and MDIO, via CPU0 firmware.** Load a firmware that (a) reads the MAC ID registers at `0x40000000`, (b) performs an MDIO read of the LAN8720's PHY ID registers 2 and 3, (c) writes both results to shared SRAM. Release CPU0 (HIO-502), then read the results from `0x2D0000xx` over ADP. | The LAN8720 PHY ID appears (OUI `0x0007C0`, model/revision per the datasheet). PASS = the PHY ID matches. | **The only route to MDIO from this port.** Its discrimination is strong: a PHY that is absent, unpowered, strapped to the wrong address, or has a dead MDIO line returns `0xFFFF`/`0x0000` rather than the OUI, and those are distinguishable from each other. The result travels back through a path (firmware → shared SRAM → ADP) already proven by HIO-504, so a failure here is attributable to the MAC/PHY and not to the transport. | R | firmware build + ~6 CU | requires HIO-502 (irreversible) |
| **HIO-507** | **Bus-fault monitor, live.** Have firmware perform one deliberate access to an unmapped address (e.g. `0x70000000`). Then `A x2c300000` ; `R` ; `A x2c300004` ; `R` ; `A x2c30000c` ; `R`. | `FAULT_SEEN` = 1, `FAULT_ADDR` = the address firmware used, `INIT_IDX` = 0 (`eth_ss_m`/CPU0) or 1 (CPU1). PASS = the address matches **exactly** and the initiator index is right. | **This is what upgrades HIO-308 from WEAK to real.** The captured address is a value only a correct monitor could produce, and the initiator index proves the per-initiator demux. Recall `debug_m` is **not** monitored, so ADP cannot stimulate this itself — which is precisely why it needs firmware and why HIO-308 alone is not coverage. | B | firmware + 6 CU | clears/re-arms on write-1 |
| **HIO-508** | **CPU1 memory preload (the other core).** `A x90000000` ; `Vx00000000` ; `Fx00001000` ; `A x90000000` ; `Ux<n>` + payload ; verify with `Rx…`. Then `A x29000000` ; `Wx00000001` to point CPU1's address 0 at IMEM, and `A x2a000020` ; `Wx00000002` to restart it. | CPU1 runs the loaded image. PASS = CPU1 firmware liveness via HIO-504/505. | `0x90000000` is a **remap-independent** alias of CPU1 IMEM (`nanosoc_cpu_ss_matrix_decode_CPU_SS.v`, static region), so the preload works whatever CPU1's REMAP bit currently says — you do not have to know the boot state to load the image. Fails visibly if the alias is wrong (HIO-118 would already have caught that). | R | ~6 CU + payload | **HZ-4** on the remap write; **HZ-5** on the restart — see HIO-509 |
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
| A2 | **HIO-002**, **HIO-003**, **HIO-004**, **HIO-010** — enter the monitor, confirm rejection of a bad command, confirm re-entry after `X`. | **ABORT GATE 2: no prompt → the RX path is dead.** The banner already proved TX, so this isolates the fault to the host→SoC direction: one PIO state machine, four data lines and `IOREQ1/2`. Scope those. |
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
| B6 | **HIO-402** — the fabric clock is advancing. | **ABORT GATE 6: a static `P0_CYC` (after a CLR) means the fabric is latched, not clocked.** Every register read above would still have "worked". |
| B7 | **HIO-407**, **HIO-409**, **HIO-410**, **HIO-411** — TideLink FCSM/cal, XHB witness, TideChart election, DMA power state. | Not gates — these are *state* readings. HIO-411 gates only HIO-412. |

### Phase C — write behaviour, nothing destroyed (~130 CU ≈ 9 s of link time)

| Step | Test | Gate |
|---|---|---|
| C1 | **HIO-401** — the poll-engine discrimination pair. | **ABORT GATE 7: if either polarity fails, every `P`-based test below is vacuous.** Do not skip this because it "always passes". |
| C2 | **HIO-313** — the boot-gate write path, exercised with a guaranteed no-op. | **ABORT GATE 8 for Phase F.** If the OR-with-zero write reports `!` or changes the value, do **not** attempt HIO-502. |
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

**6. Real-time response.** Anything needing a reaction faster than one command round trip: interrupt latency, PPS edge alignment, PTP servo behaviour, packet-rate behaviour, and every race condition. `P` mitigates this for the special case of *waiting* on one address with one masked compare at `HCLK` — but `P` cannot sequence two conditions, cannot act on a match, and cannot capture the value that matched. Anything needing a *reaction* needs firmware.

**7. Simultaneity of any kind.** Two initiators at once, cross-die concurrency, cache/coherence effects. Cross-die work is additionally limited by HZ-2: a failed peer read can cost a power cycle, so **the peer aperture cannot be soaked from this port** — one guarded shot at a time is the honest ceiling.

**8. Its own link.** If HOSTIO does not answer, HOSTIO cannot tell you why. That case needs a scope on the seven pins. The banner (HIO-001) is the closest thing to a self-diagnosis, because it is emitted with no host stimulus and so separates the two directions.

**9. Scan, BIST and boundary scan.** Separate infrastructure, separate plan.

**10. Power-domain control.** The DMA-250's power state is *observable* (HIO-124: `IIDR == 0` means gated, not absent) but not *controllable* from this port. The same applies to any other LPI-gated block.

### 4.3 The three things in this plan most likely to produce a false green

Stated explicitly, because this is where a test plan usually fails:

1. **A `P`-based test that passes because the compare is broken.** Mitigation: HIO-401 every session, plus the opposite-polarity negative control named in HIO-406 and HIO-408.
2. **An identity read that passes because the register is RW and something wrote the right value.** Mitigation: HIO-314, and preferring pure-RO registers (HIO-121) over RW ones (HIO-122).
3. **A reset-value test that passes because the bus returns zeros.** Mitigation: the census's OK-with-zeros class (HIO-114), the non-zero reset defaults (HIO-125, HIO-127), and never treating `0x20000000 == 0` as evidence about the DMA (HIO-124).

---

## 5. Hardware verification of this plan's key claims (2026-08-25, after drafting)

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
power cycle, and it may already be a no-op here.**

### 5.6 Net effect on the plan

Upgraded from derived to measured: HIO-401 (poll discrimination), HIO-415
(ETHMAC unreachable), the `0x84...` hazard scoping, `M` operand behaviour, and
the reachability census rows above. Unchanged: everything requiring a peer die,
the ASIC configuration, and all of Tier 5.
