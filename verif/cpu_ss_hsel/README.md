# cpu_ss_hsel: the unqualified-HTRANS bus defect on the eth chiplet SoC

The shipped (rc4) SoC passes a main-matrix target port's HTRANS into a subsystem matrix without
qualifying it by that port's HSEL, on two ports:

- `CPU_SS_1_SLAVE`: `build_soc/rtl/nanosoc_ss_cpu_plus.sv:354`, where `cpu_ss_hsel` is declared and never read.
- `ETH_SS_SLAVE`: `build_soc/rtl/nanosoc_multicore_soc.sv:880`, where `eth_ss_slave_hsel` is driven and
  never read, and `eth_ss_ahb_interconnect_lite.v:859` ties `HSEL_ETH_SS_0` high.

When the last user of such a port moves on to another slave, the Arm matrix legally shows its
NONSEQ with HSEL=0 on that port for one cycle. The subsystem executes it as a phantom transfer.
The phantom carries HWDATA=0 and decodes through the subsystem's own map, which aliases the main
map. Full write-up: `~/SoCLabs/nanoSoC-M0-QuickStart-SoC/docs/DEFECT-cpu-ss-hsel.md`.

## What this directory proves

`make soc` runs the rc4-lineage `nanosoc_multicore_soc` twice:

- **shipped** is the RTL as built (`EXPECT=defect`). Every corruption below must reproduce.
- **gated** adds the two one-line gates, `hsel ? htrans : 2'b00`, applied by `gen_variants.py` to
  copies in `build/gated/` (`EXPECT=clean`). None may appear.

The DMA-250 is the only bus master. Four 8-word copies, each read back:

| scenario | shipped | gated |
|---|---|---|
| S0: network-core DMEM to network-core DMEM (same port) | correct | correct |
| P2: CPU1 DMEM `0x9800_0100` to network-core DMEM `0x1800_0600` | DMA **DONE**, copy correct, **CPU1 DMEM @0x600 zeroed 8/8** | untouched |
| P1b: network-core DMEM to D2D peer aperture `0x2F00_0400` | DMA **DONE**, **16 writes for 8**, each real write followed by a zero; peer ends 8/8 zero | 8 correct writes |
| P1a: network-core DMEM to shared SRAM `0x2D00_0400` (not in the DMA's map) | DMA ERRORs, but **the SRAM word is still zeroed** | DMA ERRORs, untouched |

`make dma-issue` shows the real rc4 DMA-250 always meets the phantom condition: it asserts that
every source/destination switch of a memory-to-memory copy has at most 1 IDLE cycle. Measured:
0 IDLE on every switch, across 1 to 64 words and 0 to 3 wait states on either side.

## Test shortcuts (none on the defect path)

- Both CPUs' AHB HTRANS are forced IDLE from t=0. soc_smoke's `tb_top` ties DAP, HOSTIO,
  D2D-inbound and the eth_ss_0 backdoor idle.
- The CPU0 boot gate is released (`remap_q |= 4`), as `cocotb/soc_dma250` does. It holds the
  network-core reset domain, which also resets the DMA.
- The DMA is programmed by forcing `dmac_0_apb_*`. Memories are seeded and read back through the
  `cmsdk_fpga_sram` byte lanes.
- `build/tb_top_okd2d.sv` is soc_smoke's `tb_top` with the D2D error responder replaced by an
  OKAY responder. With the stock error responder a D2D copy stops after one beat in both variants.
- `RAM_PRELOAD` is not defined. With it, IMEM becomes a ROM, which the silicon's IMEM is not.

## Running

```bash
make soc                  # ~5 min: two compiles, two runs
make dma-issue            # ~1 min
# from a worktree, where the submodule is empty:
make soc NANOSOC_MULTICORE_HOME=/path/to/populated/nanosoc-multicore-system
```

Needs VCS (T-2022.06-SP2 used), cocotb 2.x and read access to the Arm IP library.
`env.mk` sets only the variables of `nanosoc-multicore-system/set_env.sh`. It reads the IP
library paths from that script's export lines as text and never runs the script. `make env`
prints them. CMSDK is deliberately set_env.sh's `Corstone-101` candidate: the two CMSDK copies
differ in `cmsdk_fpga_sram.v`, the model this bench seeds, and `Corstone-101` is the one
`cocotb/soc_dma250` uses and 12 of rc4's 14 CMSDK flist lines name.

**Never source `set_env.sh` for this.** It runs `make -C sys_desc` when the top YAML is newer
than `build_soc/rtl`, which regenerates `build_soc/`: the gitignored, only copy of the RTL rc4
was synthesised from. `build/inputs.md5` records the md5 and mtime of the files that decide the
result. On 2026-09-28 the `build_soc` files dated from 2026-08-18 15:00, the set the rc1 synthesis
read on 2026-08-26.

## Provenance, 2026-09-28

- `build_soc/` is unchanged since 08-18. `src/rtl` and `flist/` are unchanged since the rc1 pin
  `f60449b`. Two submodules differ from that pin, both off these paths: `ahb_qspi` (e908ac8 to
  07b40f5) and the nested `socdebug_tech` (1953e32).
- The DMA sources are `build_soc/flist/dma250_rendered.flist`: the same 60 files, in the same
  order, as rc4's `build/chip/flist/soc.flist`.
- **Do not use `cocotb/dma250_block` for rc4 questions.** It compiles `src/rtl/vendored/dma_250`,
  which differs from the rc4 copy in 61 files, including the BIU.
