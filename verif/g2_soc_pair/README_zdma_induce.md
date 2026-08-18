# zdma_induce — ZynqMP PS-DMA posted-write induction tool

A root userspace tool for the KR260 (xck26, Cortex-A53, Linux) that programs a
PS ZDMA channel to issue **posted write bursts with multiple outstanding AWs**
into a PL aperture. Purpose: an *authorized* hardware-debug induction. A PS CPU
store is a single blocking AXI write (1 outstanding), so it can never fill the
downstream 8-deep flow-control window. A ZDMA engine keeps many writes
outstanding and can.

- `zdma_induce.c` — the tool (single file, C).
- Build: `gcc -O2 -Wall -o zdma_induce zdma_induce.c`
  (or `aarch64-linux-gnu-gcc ...` with a glibc sysroot).

---

## 1. Feasibility — CONFIRMED

**The LPD-DMA (ADMA) can write to `0x8000_0000`.** Evidence:

- `0x8000_0000–0x9FFF_FFFF` (512 MB) is the **M_AXI_HPM0_LPD** PL aperture — a
  slave *inside the LPD*. (UG1085 system address map; AMD PL-Masters wiki.)
- **ADMA (LPD-DMA @ `0xFFA8_0000`)** is a full AXI master *on the LPD main
  switch*, which also hosts the HPM0_LPD egress port. So ADMA → HPM0_LPD is a
  **direct intra-LPD path** — the shortest route to any PL aperture from any PS
  master. No domain crossing.
- AMD confirms the general rule: *"as long as the memory is hooked to one of the
  M_AXI ports on the PS, the ZDMA can access it."*
- Base addresses verified against mainline `arch/arm64/boot/dts/xilinx/zynqmp.dtsi`:
  `dma@ffa80000…ffaf0000` (ADMA, 8 ch), `dma@fd500000…fd570000` (GDMA, 8 ch),
  `compatible = "xlnx,zynqmp-dma-1.0"`.

GDMA (FPD-DMA @ `0xFD50_0000`) can also reach `0x8000_0000` via the FPD→LPD
inter-domain path, but ADMA is the clean, recommended route and the tool default.

> The `--selftest` DDR→DDR copy is the empirical proof that the programming AND
> the physical-addressing assumption are correct on *this* board before any PL
> write is issued.

---

## 2. Register sequence (ZDMA "simple"/point-type, per channel)

Channel base = `0xFFA8_0000 + ch*0x1_0000`. Offsets from
Xilinx `xzdma_hw.h`; write order from `xzdma.c` (order among the 8 descriptor
words is immaterial — the engine acts only on `CTRL2.EN`).

| step | reg | off | value |
|------|-----|-----|-------|
| stop | `CH_CTRL2` | `0x200` | `0` (EN=0) |
| mask irq | `CH_IDS` | `0x10C` | `0xFFF` (poll ISR instead of GIC) |
| clear sts | `CH_ISR` | `0x100` | `0xFFF` (write-1-clear) |
| ctrl0 | `CH_CTRL0` | `0x110` | `0x00` normal(rd+wr) simple · `0x10` write-only |
| ctrl1 | `CH_CTRL1` | `0x114` | `SRC_ISSUE=0x1F` (max read outstanding) |
| attrs | `CH_DATA_ATTR` | `0x120` | burst/len/cache (see below) |
| wr-only pat | `CH_WR_ONLY_W0..3` | `0x148..0x154` | data word (write-only mode) |
| src addr lo/hi | `CH_SRC_DSCR_W0/W1` | `0x128/0x12C` | `pa[31:0]` / `pa[48:32]&0x1FFFF` |
| src size | `CH_SRC_DSCR_W2` | `0x130` | bytes `&0x3FFFFFFF` |
| src ctrl | `CH_SRC_DSCR_W3` | `0x134` | `[0]`=coherent |
| dst addr lo/hi | `CH_DST_DSCR_W0/W1` | `0x138/0x13C` | `pa[31:0]` / `pa[48:32]` |
| dst size | `CH_DST_DSCR_W2` | `0x140` | bytes `&0x3FFFFFFF` |
| dst ctrl | `CH_DST_DSCR_W3` | `0x144` | `[0]`=coherent |
| **START** | `CH_CTRL2` | `0x200` | `0x1` (EN) |
| poll | `CH_ISR` | `0x100` | done=`0x400`, err mask=`0xBF9` |
| watch | `CH_STS` / `CH_TOTAL_BYTE` | `0x11C`/`0x188` | state `[1:0]` · bytes moved |

### `CH_DATA_ATTR` (`0x120`) fields
```
[27:26] ARBURST  [25:22] ARCACHE  [21:18] ARQOS  [17:14] ARLEN
[13:12] AWBURST  [11:8]  AWCACHE  [7:4]   AWQOS   [3:0]   AWLEN
```
`ARLEN`/`AWLEN` = AXI burst length − 1 (0 → single beat, 15 → 16-beat).
`ARBURST`/`AWBURST`: 0=FIXED, 1=INCR. `AWCACHE=0x3` = Normal-non-cacheable
**Bufferable** (posted); `0x0` = Device non-bufferable.

---

## 3. Outstanding / burst config — the whole point

- The ZDMA is a real AXI master that **keeps multiple writes outstanding** (it
  does not block per BRESP); a CPU blocking store keeps exactly 1. That
  difference is what lets this fill an 8-deep window.
- `CTRL1.SRC_ISSUE = 0x1F` (31) maximizes outstanding **reads** so the internal
  write buffer never starves → writes stream at full outstanding depth.
- **There is no software "write-issue" knob.** The write-outstanding depth is a
  fixed property of the engine — the one thing to confirm on an ILA (count AWs
  before the first BRESP). It is >1 by construction, which is sufficient.
- **Transaction shape (per target-RTL analysis): many SHORT self-completing
  writes, small `AWLEN` — not one long burst.** A single descriptor of `SIZE`
  bytes with small `AWLEN` is split *by the engine* into
  `ceil(SIZE/((AWLEN+1)·beat))` short AXI bursts (beat = 8 B ADMA / 16 B GDMA).
  Each self-completes its beats immediately, so XHB500's per-transaction
  `write_broken` check (which arms only when *one* transaction's address side
  goes idle while it still owes beats) never trips — while the back-to-back
  arrival still fills the 8-deep window. Default `--awlen 0` = single-beat, the
  most self-completing shape.

## 4. AXI attributes (posted)
`--induce` sets `AWCACHE = 0x3` (bufferable/posted) so the interconnect need not
hold each write for its response — maximizing outstanding writes. `--selftest`
uses `0x0` (device) with explicit cache maintenance for a deterministic verify.

---

## 5. How to run

```sh
# build on the board (or cross-build and scp)
gcc -O2 -Wall -o zdma_induce zdma_induce.c

# 1) VALIDATION GATE — must PASS before touching the PL
sudo ./zdma_induce --selftest
#    -> "VERIFY: dst == src  ->  SELFTEST PASS"

# 2) INDUCE — posted bursts to 0x80000000 (expect STALL = wedge)
sudo ./zdma_induce --induce 65536
#    -> "engine STALLED with writes outstanding -> INDUCTION ACHIEVED"

# review the exact register plan WITHOUT touching hardware:
./zdma_induce --induce --dry-run --awlen 0 --burst incr
```

Useful knobs (see `--help`): `--awlen N` (0..15, small), `--burst incr|fixed`,
`--mode writeonly|normal`, `--addr HEX`, `--engine adma|gdma`, `--channel N`,
`--timeout MS`, `--pattern HEX`.

- **write-only** (induce default): engine emits the `WR_ONLY` pattern to the
  aperture with **no source read** → no transaction can idle mid-burst; maximum
  sustained outstanding writes.
- **normal**: real, fully-resident/mlocked DDR source → PL (a DMA-250-style
  copy). Short bursts keep each transaction self-completing.

After a successful induce the die/link is wedged **by design** — recover via
**JTAG-POR**. The channel `EN=0` does not clear an AW already stuck in the fabric.

---

## 6. Safety assumptions & uncertainties

1. **No SMMU remap.** The tool programs pagemap-resolved *physical* addresses. If
   the SMMU/IOMMU were translating this master, those addresses would be wrong —
   in which case **`--selftest` FAILS SAFELY** (dst ≠ src) and you never reach
   the PL. That is the gate's purpose. (ZynqMP SMMU is bypass/disabled by default
   for these masters unless a `iommus=` binding is set.)
2. **pagemap needs root.** PFNs read as 0 for unprivileged callers; the tool
   errors out clearly. Run as root.
3. **Physical contiguity.** A simple descriptor addresses one contiguous run. The
   tool allocates a 2 MiB huge page (contiguous) or falls back to a single 4 KiB
   page, verifies contiguity via pagemap, and caps the transfer to the contiguous
   length. For large contiguous DDR sources reserve huge pages
   (`echo N > /proc/sys/vm/nr_hugepages`). *(write-only induce needs no source
   buffer at all.)*
4. **Cache coherency.** Non-coherent DMA + explicit `dc civac` (clean+invalidate
   to PoC) around the buffers. `dc civac` at EL0 relies on `SCTLR_EL1.UCI=1`
   (Linux default). Verified to assemble for aarch64 (`d50b7e20`).
5. **Write-outstanding depth is HW-fixed**, not a register. It is >1 (enough to
   beat a CPU's 1), but the exact count that reaches the window is best confirmed
   on an ILA. This is the one open empirical question.
6. **Destination guard.** `--induce` refuses any address not wholly inside a PL
   aperture (`0x8000_0000–0x9FFF_FFFF`, `0xA000_0000–0xAFFF_FFFF`,
   `0xB000_0000–0xBFFF_FFFF`). The CPU never maps or touches `0x8000_0000`; only
   the DMA writes it. The only physical addresses the CPU writes are the ZDMA
   channel registers and its own pagemap-resolved DDR buffers.
