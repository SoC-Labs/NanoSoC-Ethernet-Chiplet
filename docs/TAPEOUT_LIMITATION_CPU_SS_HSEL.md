# Stated limitation — DMA-250 copies can corrupt local memory and TideLink targets

**For inclusion in the tapeout submission / partner-facing errata.**
Drafted 2026-09-28 from an RTL, netlist and simulation audit. It describes the die that
was taped out:

    design     rc4-20260829, ASIC/eth-chiplet/build/rc4-20260829/outputs/
               nanosoc_eth_chiplet_pads_rc4_logo.gds, md5 6b0833c4216bdb683ed2427cd0deba75
               (the bytes imec graded; P&R netlist nanosoc_eth_chiplet_pads_rc4_pnr.v,
               md5 1899a304623cbf9df16e1af5a06c7a65)
    RTL        nanosoc-multicore-system/build_soc/rtl/ (generated 2026-08-18 by
               nanosoc_gen d04de2e; gitignored; mtimes unchanged since)
    re-spin    NONE. The owner has decided not to re-spin, so this die is final.

---

## 1. Summary

Two subsystem ports on the main bus matrix accept a transfer that the matrix did not
select. They pass the matrix's HTRANS into the subsystem's own bus matrix without
qualifying it with HSEL, and that subsystem matrix ties its HSEL high.

| Port | Window | Subsystem behind it | RTL |
|---|---|---|---|
| `cpu_ss_1_slave` | `0x8000_0000–0x9FFF_FFFF` | CPU1's boot ROM, IMEM, DMEM (admin alias) | `nanosoc_ss_cpu_plus.sv:67` declares `cpu_ss_hsel` and never reads it; `:354` passes `cpu_ss_htrans` straight through; `nanosoc_cpu_ss_ahb_interconnect_lite.v:431` ties `HSEL_CPU_SS` high |
| `eth_ss_slave` | `0x0000_0000–0x1FFF_FFFF` (and `0x5000_0000–0x5FFF_FFFF` from SWD) | the network core: CPU0's boot ROM, IMEM, DMEM, and CPU0's system port back onto the main matrix | `ethernet_ss_ahb_rmii.sv:74-94` has no hsel input; `nanosoc_multicore_soc.sv:329/:1747` drives `eth_ss_slave_hsel` and never reads it; `eth_ss_ahb_interconnect_lite.v:859` ties `HSEL_ETH_SS_0` high |

The Arm bus matrix legally shows `HTRANS=NONSEQ` with `HSEL=0` on a port for one cycle,
when the master that last used the port issues its next transfer to a different port.
Both subsystems take that cycle as a real transfer ("phantom").

**On this die only the DMA-250 can start it.** The phantom needs the master's next
transfer within one IDLE cycle of the previous one. The DMA-250 does that at **every**
source/destination switch of a memory-to-memory copy: 0 IDLE cycles at 736 of 736
switches, measured on the rc4 DMA-250 RTL. So the effects below occur **on every beat of
any DMA-250 copy whose source and destination are behind different main-matrix ports**,
when one of them is one of the two ports above.

**The DMA reports success, so firmware cannot detect the corruption from DMA status.**

---

## 2. What the DMA-250 can reach

The DMA-250's master (`dmac_0_m`) decodes exactly four windows
(`build_soc/interconnect/multicore_ahb_interconnect/address_maps/multicore_ahb_interconnect_address_maps.txt:40-48`):

| Window | Main-matrix port | Affected port? |
|---|---|---|
| `0x0000_0000–0x1FFF_FFFF` | `eth_ss_slave` (network core) | **yes** |
| `0x2400_0000–0x27FF_FFFF` | QSPI XIP | no |
| `0x2E00_0000–0x2FFF_FFFF` | D2D: TideLink registers and the `0x2F` peer aperture | no |
| `0x8000_0000–0x9FFF_FFFF` | `cpu_ss_1_slave` (CPU1) | **yes** |

It does not decode shared SRAM (`0x2D00_0000`).

Two address aliases turn a phantom into a real access to a different target:

- **CPU1 decodes the network-core addresses as its own memory.** CPU1's port decoder sends
  `0x0000_0000–0x0FFF_FFFF` to its boot ROM (to IMEM for `0x0000_0000–0x07FF_FFFF` when
  CPU1's `REMAP[0]` is set), `0x1000_0000–0x17FF_FFFF` to IMEM and `0x1800_0000–0x1FFF_FFFF`
  to DMEM (`nanosoc_cpu_ss_matrix_decode_CPU_SS.v:235-293`). The memories alias, so the
  word hit is the address modulo the memory size.
- **The network core forwards `0x2xxx_xxxx` to CPU0's system port.** Its port decoder sends
  `0x2000_0000–0x2FFF_FFFF` to its SYSTEM output (`eth_ss_matrix_decode_ETH_SS_0.v:397-399`),
  which is CPU0's master port back onto the main matrix (`eth_ss_m`,
  `nanosoc_multicore_soc.sv:868-877`). That port reaches every `0x2xxx_xxxx` target on the
  main matrix: the DMA-250 and QSPI registers, PHC, mailbox, XIP, CPU1 remap control, reset
  control, event routing, debug control, shared SRAM, TideLink and the peer aperture
  (address map `:3-19`), including targets the DMA-250 itself cannot reach.

---

## 3. Effects

| # | DMA-250 copy (source → destination) | Effect | Seen as |
|---|---|---|---|
| **E1** | CPU1 window (`0x8/0x9…`) → network-core window (`0x0000_0000–0x1FFF_FFFF`) | For every beat, CPU1's own boot ROM / IMEM / DMEM word at the **destination** address, as CPU1 decodes it (§2), is overwritten. The destination copy itself is correct. | silent; DMA DONE |
| **E2** | network-core window → a write in `0x2xxx_xxxx` (TideLink registers, the `0x2F` peer aperture) | The network core repeats each write through CPU0's system port after the real write, so every beat lands twice and the target ends with the repeated write's value (zero, below). The same happens for a destination the DMA-250 cannot reach itself, such as shared SRAM (`0x2D…`): the DMA gets ERROR and stops, but the word is still overwritten. | silent; DMA DONE (ERROR for an unreachable destination) |
| **E3** | `0x2xxx_xxxx` (XIP, TideLink) → network-core window | Each read of the source is repeated through CPU0's system port: a second read of read-sensitive registers. | silent; DMA DONE |
| **E4** | E2 or E3 with XIP (`0x24–0x27…`) or TideLink (`0x2E–0x2F…`) on the other side | When that side has wait states, the DMA's **own** following network-core access can be dropped and answered OKAY. An XIP → network-core IMEM copy lost 4 of 8 writes. | silent; DMA DONE |
| **E5** | any copy in E1–E4 while SWD or HOSTIO4 accesses the same subsystem's local memory | The debug access can be dropped. On CPU1's port it is answered with a 1-cycle ERROR. On the network-core port it is answered **OKAY**, and the DMA's own reads there can return wrong data. | silent on the network core |

**What the overwriting write carries.** Zero, because the matrix's write-data mux outputs
0 in the phantom's data phase (`multicore_target_output_CPU_SS_1_SLAVE.v:446,459-462`).
If SWD or HOSTIO4 is writing through the same port at that moment, it carries **that
master's write data** instead (45 of 75 simulated cases on the network-core port).

**Network core → CPU1 window** (the reverse of E1) was not simulated. Its phantoms are a
default-slave ERROR in the network core and a read of CPU1 memory, but every beat still
opens the E5 window, and whether the DMA can drop its own next access here is not
measured. Treat it as affected.

---

## 4. Firmware rules and workarounds

1. **Use the DMA-250 only for copies whose source and destination are behind the same
   port:** within `0x0000_0000–0x1FFF_FFFF` (network core to network core), or within
   `0x8000_0000–0x9FFF_FFFF` (CPU1 to CPU1). Copies between XIP and TideLink involve
   neither affected port, so this erratum does not restrict them.
2. **Do not use the DMA-250 for any other copy.** In particular: CPU1 window ↔ anything
   else, network-core window ↔ XIP, network-core window ↔ TideLink or the peer aperture.
   Copy with a CPU instead:
   - CPU1 moves data into and out of its own memory, through shared SRAM (`0x2D00_0000`).
   - CPU0 moves data between its own memory and `0x2xxx_xxxx` targets, including
     XIP → CPU0 memory.
   - There is no DMA-250 bounce buffer that avoids the problem: the DMA cannot reach
     shared SRAM, and every CPU0 RAM address it can reach aliases onto CPU1 memory.
3. **Do not treat DMA DONE as proof.** A copy that breaks rule 2 completes with DONE. The
   damage is in another memory (E1), in the destination after the copy (E2), or in
   repeated or dropped accesses (E3–E5). Only a read-back compare of every affected memory
   shows it.
4. **Keep concurrent channels on one port.** The DMA-250's channels share one bus master.
   If two channels on different ports are active together, its transfers can alternate
   between the ports like one cross-port copy. This is inferred from the mechanism; it was
   not simulated.
5. **No SWD or HOSTIO4 access to boot ROM, IMEM or DMEM while a DMA-250 transfer that
   touches the same subsystem is running.** Wait for the channel to go idle. Reading the
   DMA-250's own registers (`0x2000_0000`) while it runs is fine.
6. **If a DMA copy touched CPU1's window anyway, check CPU1's image CRC before releasing
   CPU1.**

**Known affected software, fixed from the current submodule pin.** The eth_netapp GDB stub
copied CPU1 memory with the DMA-250 between CPU1's admin alias and a bounce buffer at
`0x1000_F000`. Every `m`, and the read half of every `M` and `Z0`, is the E1 shape: CPU1
decodes `0x1000_F0xx` as IMEM offset `0x30xx` (16 KB IMEM), so it is expected to zero CPU1
IMEM `0x3000–0x30FF`. Reproduced on an FPGA built from the rc4 RTL: 64 of 64 words
zeroed, DMA DONE, destination correct (§6). Not yet observed on silicon. There is no bus-only fix: CPU0 has no route to CPU1's window, and every
CPU0 RAM address the DMA-250 reaches is also CPU1 memory. The fix has CPU1 copy its own
memory with its own loads and stores and return the bytes over IPC ring socket 3
(`nanosoc-multicore-system` `f25a3e2`, merged as `9507a93`, which this repository pins).
The `eth_netapp_gdb*` and `eth_netapp_demo*` images built from that pin link no DMA-250
copy code. **An image built from an earlier pin still has the bug: do not use its memory
commands (`m`, `M`, `Z0`) on CPU1.** The fixed commands need CPU1 running
`chip_core_demo_worker` or `telnet_worker` built from the same pin; both now serve socket 3.
After CPU1 faults (for example, at a breakpoint) they return `E01`, so use SWD to inspect
CPU1 memory. The fix is proven by host tests and a firmware build, not yet on silicon.
A first audit of the other DMA-250 uses in
`nanosoc-multicore-system/firmware/` and this repository's `scripts/` found only same-port
copies, register reads, and one unimplemented skeleton (the PL022 SPI DMA mode); a full
inventory of DMA-250 users and host debug paths is being completed.

**Enforcement in firmware (rules 1, 2 and 4).** Since this repository pinned
`nanosoc-multicore-system` `f474197`, every firmware target there that links the DMA-250
driver also links a guard (`firmware/include/dma250_hsel_guard.h`,
`firmware/lib/dma250_hsel_guard/`). The driver's `dma250_mem2mem_1d()` is wrapped at link
time (`-Wl,--wrap`), so every copy through the driver is checked first. The guard refuses a
copy, and returns an error instead of starting it, when:
- its source and destination sit behind different ports and one of them is affected;
- either range spans two windows or falls outside the DMA's decode;
- any channel is already running, or the channel is not allowed (only CH0 by default);
- the command is linked or auto-restarting.

CPU1 builds refuse every DMA-250 command. `dma250_hsel_copy_sync()` retries a refused copy
with the CPU when this CPU can reach both ends. `firmware/tests/check_dma250_guard.py`
finds code that starts the DMA without the driver, or calls the driver past the guard; it
is run by hand, not by the build. The guard does not cover images built from an earlier
pin, a DMA started by a debugger, or rules 3, 5 and 6.

**Host tools (rule 5).** `scripts/rig/eth_chiplet/dma250_quiesce.py` and
`openocd_hostio4/dma250_quiesce.tcl` pause every DMA-250 channel (`NSEC_CTRL.ALLCHPAUSE`,
`0x2000_020C` bit 9) around an SWD or HOSTIO4 access to an affected window, and release it
by clearing `STAT_ALLCHPAUSED` (`0x2000_0208` bit 19). They are opt-in: no host tool calls
them by default, so wrap the access yourself (see `openocd_hostio4/README.md`).

---

## 5. Not affected

- **CPU0 and CPU1 accesses.** Neither CPU uses these ports. CPU1's decoder keeps
  `0x0000_0000–0x1FFF_FFFF` local, and CPU0 reaches its memory directly. 176 simulated CPU
  transfers produced 0 phantoms.
- **SWD and HOSTIO4, alone or together, with the DMA-250 idle.** SWD leaves at least two
  IDLE cycles between transfers (the AHB-AP state machine), and 0 phantoms occur at two or
  more. HOSTIO4 issues back to back only inside one auto-increment block or poll, which
  stays on one port; a new address needs a serial command. (Do not run one auto-increment
  block across the end of the network-core or CPU1 window into another port.)
- **Same-port DMA-250 copies** (full-SoC simulation: network-core DMEM → DMEM clean).
- **The peer die.** Inbound D2D requests decode only to the mailbox (`0x23…`) and shared
  SRAM (`0x2D…`), never to either port (`d2d_m` in
  `build_soc/interconnect/multicore_ahb_interconnect/address_maps/multicore_ahb_interconnect_address_maps.txt:93-99`).
- **The Ethernet MAC's DMA.** It is an initiator inside the network core, not on this port.
- **The network core's second port `eth_ss_1`** (the FPGA PS backdoor). It is correctly
  handshaken, and tied idle on the ASIC.
- **The boot ROMs.** Both copy images with the CPU (`firmware/bootloader/stage0_bootrom/main.c:91-99`,
  `stage0_bootrom_chip_core/main.c:100-106`).

---

## 6. How it was proven

| Evidence | Result |
|---|---|
| **Generated RTL** (`build_soc/rtl/`, the files the rc4 flist lists; `soc.flist` md5 `a2382e1f…` = `gdsrun-20260826-rc1/PRE_RUN_MANIFEST.txt:630`) | both ports ungated, as in §1 |
| **rc4 P&R netlist** (md5 `1899a304…`, the netlist Calibre LVS compared with the stream). Combinational cone of each port's input-stage capture flops, counted in external-master address MSBs | CPU1 port 0 / 0, network-core port 0, against 77 and 91 in the matrix's own registered HSEL for the same two ports |
| **Interconnect simulation 1** (iverilog, byte copies of the three generated interconnects, zero-wait memories) | CPU1 DMEM → `0x1800_0600`: 8/8 CPU1 DMEM words zeroed. Network core → `0x2F00_0400`: 16 writes for 8, all end 0. A debug write issued in the phantom window was lost (ERROR on CPU1's port, OKAY on the network core's). Both gates, or one IDLE cycle between DMA transfers: clean |
| **Interconnect simulation 2** (independent: the unmodified `multicore_interconnect.sv`, `ethernet_ss_ahb_rmii.sv`, `nanosoc_ss_cpu_plus.sv`, Arm AhbLitePC on every port, scoreboarded memories) | phantom at 0–1 IDLE 12/12, at ≥2 IDLE 0. E2 12/12. 24 of 48 debug writes to network-core IMEM lost, answered OKAY. E3: 4 of 8 writes lost. Repeated write carries debug data in 45 of 75. CPU-only: 0 phantoms in 176. Both gates: clean on 3 seeds |
| **DMA-250 block level** (the 60 rendered rc4 DMA-250 files plus rc4's wrappers, driven by the firmware's `dma250_mem2mem_1d` sequence; 1–64 beats, 0–3 wait states either side) | 0 IDLE cycles at 736 of 736 source/destination switches; 24/24 copies correct. Control: 2 inserted IDLE cycles measured as 2 |
| **Full SoC** (`nanosoc_multicore_soc` from the rc4 `build_soc`, the real DMA-250 as the only master, CPUs held idle) | see below |
| **FPGA, rc4 RTL** (PYNQ-Z2 `pynq_z2_03`, 2026-10-02; the SoC only, no TideLink, 25 MHz; built from a byte-identical copy of rc4's `build_soc`, 332 files) | see below |

Full-SoC results (8-word copies, one channel; `orig` = rc4 as shipped, `ctrl` = the two
one-line gates of §7):

| Copy | orig | ctrl |
|---|---|---|
| network-core DMEM → network-core DMEM (same port) | DONE, correct | DONE, correct |
| CPU1 DMEM `0x9800_0100` → network-core DMEM `0x1800_0600` | DONE, destination correct, **CPU1 DMEM `@0x600` zeroed 8/8** | DONE, CPU1 DMEM intact |
| network-core DMEM → shared SRAM `0x2D00_0400` | DMA ERROR, **SRAM word zeroed** | DMA ERROR, SRAM intact |
| network-core DMEM → peer aperture `0x2F00_0400` (OKAY responder) | DONE, **16 writes for 8, all 8 end 0** | DONE, 8 writes, correct |

FPGA results (one DMA-250 channel, CPU1 halted; CPU1 memory seeded and read back over SWD
through its admin alias, so the check never relies on the DMA's own view):

| Copy | Result |
|---|---|
| network-core DMEM → network-core DMEM, through the §4 guard | DONE, correct |
| CPU1 IMEM `0x9000_1000` → `0x1000_F000` (the old GDB stub), through the guard | refused (`-11`), channel never enabled, CPU1 IMEM intact |
| the same copy without the guard | DONE, destination correct, **CPU1 IMEM `0x3000–0x30FF` zeroed 64/64** |
| CPU1 DMEM `0x9800_0100` → network-core DMEM `0x1800_0600` (the full-SoC case above), no guard | DONE, destination correct, **CPU1 DMEM `0x600–0x61F` zeroed 8/8** |

In both unguarded copies the memory on each side of the damaged range (256 bytes for
IMEM, 32 for DMEM) and the source were unchanged. The bench is the `hsel_proof` app and `hsel_proof_run.tcl` in session
scratch space, not in this repository (bitstream md5 `d6af6a90…`).

The simulation benches live in session scratch space, not in this repository:
`overnight/sim/` (simulation 1), `wave16/ethss/` in the nanoSoC-M0-QuickStart-SoC session
(simulation 2), `hsel6/dma_issue/` and `hsel6/soc/` (DMA-250 and full SoC). Each has a
README with the method. The defect has not yet been reproduced on silicon.

**FPGA benches.** Every KR260 and HAPS-SX build of this chip reads the same generated RTL
and carries both ports ungated. Use them as the silicon mirror for this erratum; a bitstream
built with the §7 gates does not predict silicon.

---

## 7. Fix for future dies

Gate each subsystem's HTRANS with the main matrix's HSEL:

```verilog
// nanosoc_ss_cpu_plus.sv, into the subsystem matrix
.cpu_ss_htrans (cpu_ss_hsel ? cpu_ss_htrans : 2'b00),
// nanosoc_multicore_soc.sv, at the network-core instance (that module has no hsel port)
.eth_ss_0_htrans (eth_ss_slave_hsel ? eth_ss_slave_htrans : 2'b00),
```

HREADY needs no change: once gated, an unselected subsystem is idle and drives
HREADYOUT high, which is what the main matrix assumes.

nanosoc_gen `036d381` adds the first gate. It does not cover the network-core port: its
`_hsel_gated_passthrough_initiators()` skips the initiator-boundary form, which has no hsel
port. The second gate has to come from the parent (top-level) backend, which already gates
the D2D port this way.
