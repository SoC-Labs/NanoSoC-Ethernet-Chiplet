# Stated limitation — the interconnect discovery tables report the wrong memory sizes

**For inclusion in the tapeout submission / partner-facing errata.**
Drafted 2026-10-05 from a regeneration audit. It describes the die that was taped out:

    design     rc4-20260829, ASIC/eth-chiplet/build/rc4-20260829/outputs/
               nanosoc_eth_chiplet_pads_rc4_logo.gds, md5 6b0833c4216bdb683ed2427cd0deba75
    RTL        nanosoc-multicore-system/build_soc/rtl/ (generated 2026-08-18 by
               nanosoc_gen d04de2e, tag keep/eth-rc4/nanosoc_gen; gitignored)
    re-spin    NONE. This die is final.

---

## 1. Summary

Each subsystem interconnect carries a read-only discovery table: one base and one
size per target, for software that sizes memory at run time. On rc4, **five of the
eight memory sizes are wrong, all too large, by 2x to 8x.**

| Core | Target | Table says | Memory built | Error |
|---|---|---|---|---|
| CPU1 (chip-control) | boot ROM (TGT_0) | `0x2000` (8 KB) | 2 KB | 4x |
| CPU1 (chip-control) | IMEM (TGT_1) | `0x10000` (64 KB) | 16 KB | 4x |
| CPU1 (chip-control) | DMEM (TGT_2) | `0x10000` (64 KB) | 8 KB | 8x |
| CPU0 (network core) | boot ROM (TGT_0) | `0x2000` (8 KB) | 2 KB | 4x |
| CPU0 (network core) | IMEM (TGT_1) | `0x10000` (64 KB) | 32 KB | 2x |
| CPU0 (network core) | DMEM (TGT_2) | `0x4000` (16 KB) | 16 KB | correct |
| CPU0 (network core) | RX scratch (TGT_4) | `0x4000` (16 KB) | 8 KB | 2x |
| CPU0 (network core) | TX scratch (TGT_5) | `0x4000` (16 KB) | 8 KB | 2x |

Tables: `nanosoc_cpu_ss_ahb_interconnect_discovery.sv` (CPU1) and
`eth_ss_ahb_interconnect_discovery.sv` (CPU0), both in the rc4 render.

## 2. What software must do

**Never size a memory from the discovery tables on this die.** Use the linker
scripts or the fixed sizes above. A loader, allocator or memory test that trusts the
table will write past the end of the real memory. In the boot-ROM wrappers checked,
only the low address bits are decoded, so such accesses alias back into the same
memory and return or overwrite live data rather than fault. Assume the RAM regions
behave the same until shown otherwise. The base addresses in the tables are correct.

## 3. Why

Three causes, each now fixed upstream (none can be fixed on this die):

1. **The generator ignored the top-level size overrides** for most targets and
   reported the subsystem module's default instead. This is why CPU0's IMEM and
   scratch entries are 2x, and why CPU1's DMEM is 8x rather than 4x.
2. **arch_tech's CPU subsystem description multiplied by 4.** The pinned arch_tech
   (`ecf76aa`, tag `keep/eth-rc4/nanosoc_arch_tech`) predates fix `72500d9`
   ("phys_size = 2^ADDR_W, not 4*(2^N)"). The RAM widths are byte widths.
3. **The boot ROM's width means bytes here, words elsewhere.** Both rc4 boot-ROM
   wrappers decode `HADDR[ROM_ADDR_W-1:2]`
   (`nanosoc-multicore-system/src/rtl/bootrom/nanosoc_region_bootrom.v:47`,
   `ethernet-subsystem-ahb/src/rtl/regions/bootrom/eth_ss_region_bootrom.v:47`), a
   BYTE width. With `ROM_ADDR_W = 11` that is 512 words, 2 KB, matching the 512-word
   ROM macros and the ROM build (`words=512`). Another generated wrapper reads the
   same parameter as a word width, which is where the 8 KB figure came from.

## 4. Evidence

- **Control:** nanosoc_gen `d04de2e` re-run in scratch reproduces the live rc4
  `build_soc/rtl` exactly (bar the `// Generated:` line). The table values above are
  read from it.
- **Fixed render:** nanosoc_gen `main` `308e2e0` with arch_tech `main` and the rc4
  file list renders every memory size correctly. Its discovery size guard, which
  compares each table entry with the memory compiled behind it, reports 9 of 10
  targets matching and 0 mismatches. The tenth is the QSPI XIP window, a flash
  aperture rather than a RAM or ROM.
- Cross-checked with the nanosoc_gen owner, 2026-10-01.
