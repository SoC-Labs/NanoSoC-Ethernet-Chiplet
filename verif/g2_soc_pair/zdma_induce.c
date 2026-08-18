// SPDX-License-Identifier: MIT
//
// zdma_induce.c  --  ZynqMP PS ZDMA (LPD-ADMA / FPD-GDMA) userspace induction tool
// ============================================================================
// Authorized hardware-debug induction for the KR260 (xck26, Cortex-A53, Linux).
//
// PURPOSE
//   A PS CPU store to a PL aperture is a *single blocking* AXI write: the core
//   issues one AW, then waits for BRESP before the next store. Only ONE write is
//   ever outstanding, so a CPU can never fill a downstream N-deep flow-control
//   window (here XHB500/TideLink's 8-deep outstanding-write window).
//
//   The ZynqMP ZDMA (LPD-ADMA @ 0xFFA8_0000, FPD-GDMA @ 0xFD50_0000) is a real
//   AXI master that keeps MULTIPLE writes outstanding (it does not block on each
//   BRESP). Pointing its write side at a PL aperture and letting it issue many
//   short, self-completing write transactions back-to-back accumulates >8
//   outstanding entries in the downstream window -- the exact stimulus a CPU
//   cannot produce, and the one that exposes the D2D wedge.
//
// TWO MODES
//   --selftest        DDR -> DDR copy via the ZDMA, then verify dst == src.
//                     Proves the ZDMA programming AND the physical-addressing
//                     assumption (no SMMU remap) are correct. SAFE, non-wedging.
//                     This is the validation gate BEFORE touching the PL.
//
//   --induce [SIZE]   Same engine, destination = a PL aperture (default
//                     0x8000_0000, M_AXI_HPM0_LPD). Issues many short posted
//                     write bursts. EXPECTED TO STALL/WEDGE (that is the intent;
//                     authorized and JTAG-POR recoverable). Polls the channel
//                     ISR/STATUS with a timeout so the stall is detectable.
//
// TRANSACTION SHAPE (important -- see README)
//   --induce issues MANY SHORT, self-completing transactions rapid-fire
//   (small AWLEN), NOT one long burst. A single ZDMA descriptor of SIZE bytes
//   with a small AWLEN is split BY THE ENGINE into ceil(SIZE/((AWLEN+1)*beat))
//   short AXI write bursts. Each is well-formed and self-completes its data
//   beats immediately, so the downstream per-transaction integrity check
//   ("write_broken", which trips only if ONE transaction's address side goes
//   idle while it still owes beats) is never armed -- while the back-to-back
//   arrival still fills the 8-deep outstanding-write window.
//
// BUILD
//   native on board : gcc -O2 -Wall -o zdma_induce zdma_induce.c
//   cross           : aarch64-linux-gnu-gcc -O2 -Wall -o zdma_induce zdma_induce.c
//
// RUN (as root -- needs /dev/mem and /proc/self/pagemap PFNs)
//   ./zdma_induce --selftest              # MUST pass before --induce
//   ./zdma_induce --induce 65536          # blast to 0x80000000, expect STALL
//   ./zdma_induce --induce --dry-run      # print the register plan, touch nothing
//
// Register facts below are from the Xilinx embeddedsw zdma driver
// (xzdma_hw.h / xzdma.c) and UG1085; base addresses from the mainline
// arch/arm64/boot/dts/xilinx/zynqmp.dtsi.
// ============================================================================

#define _GNU_SOURCE
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <errno.h>
#include <fcntl.h>
#include <unistd.h>
#include <time.h>
#include <ctype.h>
#include <sys/mman.h>
#include <sys/stat.h>
#include <sys/types.h>

// ------------------------------------------------------------------ constants
#define ADMA_BASE      0xFFA80000UL   // LPD DMA, 8 ch (dma@ffa80000..ffaf0000)
#define GDMA_BASE      0xFD500000UL   // FPD DMA, 8 ch (dma@fd500000..fd570000)
#define CH_STRIDE      0x10000UL
#define REG_WINDOW     0x1000UL       // all channel regs live below 0x200

// PL apertures (destinations we are allowed to --induce into). NEVER DDR/peri.
#define HPM0_LPD_LO    0x80000000UL   // M_AXI_HPM0_LPD  0x8000_0000-0x9FFF_FFFF (512M)
#define HPM0_LPD_HI    0x9FFFFFFFUL
#define HPM0_FPD_LO    0xA0000000UL   // M_AXI_HPM0_FPD  0xA000_0000-0xAFFF_FFFF (256M)
#define HPM0_FPD_HI    0xAFFFFFFFUL
#define HPM1_FPD_LO    0xB0000000UL   // M_AXI_HPM1_FPD  0xB000_0000-0xBFFF_FFFF (256M)
#define HPM1_FPD_HI    0xBFFFFFFFUL

// ZDMA per-channel register offsets (xzdma_hw.h)
#define CH_ISR             0x100
#define CH_IMR             0x104
#define CH_IEN             0x108
#define CH_IDS             0x10C
#define CH_CTRL0           0x110
#define CH_CTRL1           0x114
#define CH_STS             0x11C
#define CH_DATA_ATTR       0x120
#define CH_DSCR_ATTR       0x124
#define CH_SRC_DSCR_W0     0x128   // addr[31:0]
#define CH_SRC_DSCR_W1     0x12C   // addr[48:32] (mask 0x1FFFF)
#define CH_SRC_DSCR_W2     0x130   // size bytes (mask 0x3FFFFFFF)
#define CH_SRC_DSCR_W3     0x134   // [0]=coherent [1]=type [2]=intr
#define CH_DST_DSCR_W0     0x138
#define CH_DST_DSCR_W1     0x13C
#define CH_DST_DSCR_W2     0x140
#define CH_DST_DSCR_W3     0x144
#define CH_WR_ONLY_W0      0x148   // write-only data pattern (memset engine)
#define CH_WR_ONLY_W1      0x14C
#define CH_WR_ONLY_W2      0x150
#define CH_WR_ONLY_W3      0x154
#define CH_TOTAL_BYTE      0x188   // bytes transferred so far
#define CH_IRQ_DST_ACCT    0x194
#define CH_CTRL2           0x200   // [0]=EN (start)

// CTRL0 fields
#define CTRL0_OVR_FETCH    (1u<<7)
#define CTRL0_POINT_TYPE   (1u<<6)   // 0 = simple (regs), 1 = scatter-gather
#define CTRL0_MODE_MASK    (3u<<4)
#define CTRL0_MODE_WRONLY  (1u<<4)   // write-only (data from WR_ONLY_Wx, no read)
#define CTRL0_MODE_RDONLY  (2u<<4)
// normal (read+write) mode = MODE field 00

// CTRL1 / CTRL2
#define CTRL1_SRC_ISSUE_MASK 0x1Fu   // outstanding read issue (max 31)
#define CTRL2_EN             0x1u

// DATA_ATTR field shifts / masks
#define DA_ARBURST_SH  26            // [27:26]
#define DA_ARCACHE_SH  22            // [25:22]
#define DA_ARQOS_SH    18            // [21:18]
#define DA_ARLEN_SH    14            // [17:14]
#define DA_AWBURST_SH  12            // [13:12]
#define DA_AWCACHE_SH   8            // [11:8]
#define DA_AWQOS_SH     4            // [7:4]
#define DA_AWLEN_SH     0            // [3:0]

// AXI burst types / cache encodings
#define AXI_BURST_FIXED 0
#define AXI_BURST_INCR  1
#define AXI_CACHE_DEV_NONBUF   0x0   // Device non-bufferable (strongly ordered)
#define AXI_CACHE_NC_BUF       0x3   // Normal non-cacheable, Bufferable (posted)

// descriptor word masks
#define W1_MSB_MASK    0x1FFFFu
#define W2_SIZE_MASK   0x3FFFFFFFu
#define W3_COHERENT    0x1u

// ISR / STATUS bits
#define IXR_DMA_DONE   0x400u
#define IXR_DMA_PAUSE  0x800u
#define IXR_ERR_MASK   0xBF9u        // all error bits (rd/wr AXI err, apb, ovfl...)
#define IXR_ALL_MASK   0xFFFu
#define STS_STATE_MASK 0x3u          // 0=done 1=pause 2=busy 3=done-with-err

// ------------------------------------------------------------------- globals
static volatile uint32_t *g_regs = NULL;   // mapped channel register block
static int   g_dry  = 0;                   // dry-run: print, do not touch HW
static int   g_verbose = 0;

// ------------------------------------------------------------- register I/O
static void reg_wr(unsigned off, uint32_t val)
{
    if (g_dry || g_verbose)
        printf("    [w] 0x%03x <= 0x%08x\n", off, val);
    if (!g_dry)
        g_regs[off / 4] = val;
}
static uint32_t reg_rd(unsigned off)
{
    if (g_dry) return 0;
    return g_regs[off / 4];
}

// ---------------------------------------------------- AArch64 cache maintenance
// Non-coherent DMA: clean+invalidate to Point of Coherency so (a) src data the
// CPU wrote reaches DDR before the engine reads it, and (b) the CPU re-reads
// DMA-written dst from DDR, not a stale cache line. dc civac at EL0 needs
// SCTLR_EL1.UCI=1, which Linux sets by default.
#if defined(__aarch64__)
static void dcache_civac(void *addr, size_t len)
{
    uintptr_t p   = (uintptr_t)addr & ~(uintptr_t)63;   // A53: 64B lines
    uintptr_t end = (uintptr_t)addr + len;
    for (; p < end; p += 64)
        __asm__ volatile("dc civac, %0" :: "r"(p) : "memory");
    __asm__ volatile("dsb sy" ::: "memory");
}
#else
static void dcache_civac(void *addr, size_t len)
{
    (void)addr; (void)len;
    // Only reached if built for a non-ARM64 host (compile-check only). The tool
    // is meaningless off the KR260; warn loudly rather than silently no-op.
    static int warned = 0;
    if (!warned) { fprintf(stderr,
        "WARN: dcache_civac is a no-op on this non-aarch64 build (test build only)\n");
        warned = 1; }
}
#endif

// ------------------------------------------------------- pagemap phys lookup
// Translate a locked userspace VA to its physical address via /proc/self/pagemap.
// Requires root (kernel redacts the PFN to 0 for unprivileged readers).
static int va_to_pa(void *va, uint64_t *pa_out)
{
    long   page = sysconf(_SC_PAGESIZE);
    int    fd   = open("/proc/self/pagemap", O_RDONLY);
    if (fd < 0) { perror("open pagemap"); return -1; }

    uint64_t vaddr  = (uint64_t)va;
    uint64_t offset = (vaddr / page) * 8;
    uint64_t entry  = 0;
    if (pread(fd, &entry, sizeof(entry), offset) != (ssize_t)sizeof(entry)) {
        perror("pread pagemap"); close(fd); return -1;
    }
    close(fd);

    if (!(entry & (1ULL << 63))) {              // bit63 = page present
        fprintf(stderr, "va_to_pa: page not present (not resident/locked?)\n");
        return -1;
    }
    uint64_t pfn = entry & ((1ULL << 55) - 1);  // bits[54:0]
    if (pfn == 0) {
        fprintf(stderr,
            "va_to_pa: PFN reads 0 -- run as root (pagemap PFNs are privileged)\n");
        return -1;
    }
    *pa_out = pfn * page + (vaddr % page);
    return 0;
}

// --------------------------------------------------- contiguous DDR buffer
// Allocate a page-aligned, locked, PHYSICALLY-CONTIGUOUS DDR buffer.
// Strategy: try a single 2 MiB huge page (contiguous by construction); else fall
// back to one ordinary 4 KiB page (trivially contiguous). We then verify every
// constituent 4 KiB sub-page has a consecutive PFN and report the usable
// contiguous byte count (a DMA simple-descriptor addresses ONE contiguous run).
struct dbuf { void *va; uint64_t pa; size_t bytes; int huge; };

static int dbuf_alloc(struct dbuf *b, size_t want)
{
    long page = sysconf(_SC_PAGESIZE);
    memset(b, 0, sizeof(*b));

    // Try a 2 MiB huge page first.
    size_t hsz = 2UL * 1024 * 1024;
    void  *va  = mmap(NULL, hsz, PROT_READ | PROT_WRITE,
                      MAP_PRIVATE | MAP_ANONYMOUS | MAP_HUGETLB, -1, 0);
    size_t sz;
    if (va != MAP_FAILED) {
        b->huge = 1; sz = hsz;
    } else {
        // Fall back to a single ordinary page (always contiguous).
        sz = (size_t)page;
        va = mmap(NULL, sz, PROT_READ | PROT_WRITE,
                  MAP_PRIVATE | MAP_ANONYMOUS | MAP_LOCKED, -1, 0);
        if (va == MAP_FAILED) { perror("mmap buffer"); return -1; }
    }

    if (mlock(va, sz) != 0) perror("mlock (continuing)");
    memset(va, 0, sz);                       // fault every page in, make resident

    uint64_t base_pa;
    if (va_to_pa(va, &base_pa) != 0) { munmap(va, sz); return -1; }

    // Verify physical contiguity page-by-page; stop at the first break.
    size_t contig = page;
    for (size_t off = page; off < sz; off += page) {
        uint64_t pa;
        if (va_to_pa((char *)va + off, &pa) != 0) break;
        if (pa != base_pa + off) break;      // physical discontinuity
        contig += page;
    }

    b->va = va; b->pa = base_pa; b->bytes = contig;
    if (contig < want) {
        fprintf(stderr,
          "NOTE: usable contiguous buffer is %zu bytes (< requested %zu); "
          "capping transfer. Reserve huge pages for larger contiguous DMA.\n",
          contig, want);
    }
    return 0;
}
static void dbuf_free(struct dbuf *b)
{
    if (b->va) { munlock(b->va, b->bytes); munmap(b->va, b->huge ? 2UL<<20 : (size_t)sysconf(_SC_PAGESIZE)); }
}

// --------------------------------------------------------- ZDMA programming
static void zdma_reset(void)
{
    reg_wr(CH_CTRL2, 0);              // EN=0: stop new issue
    reg_wr(CH_IDS,   IXR_ALL_MASK);  // mask all interrupts to the GIC (we poll ISR)
    reg_wr(CH_ISR,   IXR_ALL_MASK);  // write-1-clear all latched status
}

// build a DATA_ATTR value (same burst attrs on read and write sides)
static uint32_t data_attr(int burst, int awlen, int arcache, int awcache)
{
    uint32_t v = 0;
    v |= (uint32_t)(burst   & 0x3) << DA_ARBURST_SH;
    v |= (uint32_t)(arcache & 0xF) << DA_ARCACHE_SH;
    v |= (uint32_t)(awlen   & 0xF) << DA_ARLEN_SH;   // read burst len == write's
    v |= (uint32_t)(burst   & 0x3) << DA_AWBURST_SH;
    v |= (uint32_t)(awcache & 0xF) << DA_AWCACHE_SH;
    v |= (uint32_t)(awlen   & 0xF) << DA_AWLEN_SH;
    return v;
}

// NORMAL mode: read src -> write dst (used by --selftest and --induce --mode normal)
static void zdma_cfg_normal(uint64_t src_pa, uint64_t dst_pa, uint32_t size,
                            int burst, int awlen, int arcache, int awcache, int coherent)
{
    reg_wr(CH_CTRL0, 0);   // POINT_TYPE=0 (simple), MODE=00 (normal read+write)
    uint32_t c1 = (reg_rd(CH_CTRL1) & ~CTRL1_SRC_ISSUE_MASK) | CTRL1_SRC_ISSUE_MASK;
    reg_wr(CH_CTRL1, c1);  // max read outstanding -> keep write buffer full
    reg_wr(CH_DATA_ATTR, data_attr(burst, awlen, arcache, awcache));

    reg_wr(CH_SRC_DSCR_W0, (uint32_t)(src_pa & 0xFFFFFFFF));
    reg_wr(CH_SRC_DSCR_W1, (uint32_t)((src_pa >> 32) & W1_MSB_MASK));
    reg_wr(CH_SRC_DSCR_W2, size & W2_SIZE_MASK);
    reg_wr(CH_SRC_DSCR_W3, coherent ? W3_COHERENT : 0);

    reg_wr(CH_DST_DSCR_W0, (uint32_t)(dst_pa & 0xFFFFFFFF));
    reg_wr(CH_DST_DSCR_W1, (uint32_t)((dst_pa >> 32) & W1_MSB_MASK));
    reg_wr(CH_DST_DSCR_W2, size & W2_SIZE_MASK);
    reg_wr(CH_DST_DSCR_W3, coherent ? W3_COHERENT : 0);
}

// WRITE-ONLY mode: engine emits the WR_ONLY pattern to dst, NO source read.
// Best induce shape: W-channel data is always immediately available, so no
// transaction can ever idle mid-burst; writes stream at max outstanding.
static void zdma_cfg_writeonly(uint64_t dst_pa, uint32_t size, const uint32_t pat[4],
                               int burst, int awlen, int awcache)
{
    reg_wr(CH_CTRL0, CTRL0_MODE_WRONLY);   // POINT_TYPE=0 simple, MODE=write-only
    reg_wr(CH_DATA_ATTR, data_attr(burst, awlen, /*arcache*/0, awcache));
    reg_wr(CH_WR_ONLY_W0, pat[0]);
    reg_wr(CH_WR_ONLY_W1, pat[1]);
    reg_wr(CH_WR_ONLY_W2, pat[2]);
    reg_wr(CH_WR_ONLY_W3, pat[3]);
    reg_wr(CH_DST_DSCR_W0, (uint32_t)(dst_pa & 0xFFFFFFFF));
    reg_wr(CH_DST_DSCR_W1, (uint32_t)((dst_pa >> 32) & W1_MSB_MASK));
    reg_wr(CH_DST_DSCR_W2, size & W2_SIZE_MASK);
    reg_wr(CH_DST_DSCR_W3, 0);
}

static void zdma_start(void) { reg_wr(CH_CTRL2, CTRL2_EN); }

enum { R_DONE, R_STALLED, R_ERROR };
static int zdma_poll(int timeout_ms, uint32_t *isr_out, uint32_t *sts_out, uint32_t *tb_out)
{
    struct timespec t0, tn;
    clock_gettime(CLOCK_MONOTONIC, &t0);
    for (;;) {
        uint32_t isr = reg_rd(CH_ISR);
        uint32_t sts = reg_rd(CH_STS);
        uint32_t tb  = reg_rd(CH_TOTAL_BYTE);
        if (isr_out) *isr_out = isr;
        if (sts_out) *sts_out = sts;
        if (tb_out)  *tb_out  = tb;
        if (g_dry) return R_DONE;                 // nothing real to poll
        if (isr & IXR_ERR_MASK)  return R_ERROR;
        if (isr & IXR_DMA_DONE)  return R_DONE;

        clock_gettime(CLOCK_MONOTONIC, &tn);
        long ms = (tn.tv_sec - t0.tv_sec) * 1000L +
                  (tn.tv_nsec - t0.tv_nsec) / 1000000L;
        if (ms >= timeout_ms) return R_STALLED;
        struct timespec s = {0, 200 * 1000};      // 200us between polls
        nanosleep(&s, NULL);
    }
}

// --------------------------------------------------------------- map regs
static int map_channel(unsigned long engine_base, int ch)
{
    unsigned long base = engine_base + (unsigned long)ch * CH_STRIDE;
    if (g_dry) {
        printf("  channel base = 0x%08lx (dry-run: /dev/mem not opened)\n", base);
        return 0;
    }
    int fd = open("/dev/mem", O_RDWR | O_SYNC);
    if (fd < 0) { perror("open /dev/mem (need root)"); return -1; }
    void *m = mmap(NULL, REG_WINDOW, PROT_READ | PROT_WRITE, MAP_SHARED, fd, base);
    close(fd);
    if (m == MAP_FAILED) { perror("mmap channel regs"); return -1; }
    g_regs = (volatile uint32_t *)m;
    printf("  channel base = 0x%08lx  mapped\n", base);
    return 0;
}

// ------------------------------------------------------------------ modes
static int do_selftest(unsigned long engine_base, int ch, int burst, int awlen)
{
    printf("=== SELFTEST: ZDMA DDR->DDR copy + verify (SAFE gate) ===\n");
    size_t want = 4096;
    struct dbuf src, dst;
    if (dbuf_alloc(&src, want) != 0) return 2;
    if (dbuf_alloc(&dst, want) != 0) { dbuf_free(&src); return 2; }
    size_t n = src.bytes < dst.bytes ? src.bytes : dst.bytes;
    if (n > want) n = want;

    // fill src with a checkable pattern
    unsigned char *s = src.va, *d = dst.va;
    for (size_t i = 0; i < n; i++) s[i] = (unsigned char)(0xA5 ^ (i * 7 + 3));
    memset(d, 0x00, n);
    dcache_civac(src.va, n);        // src -> DDR
    dcache_civac(dst.va, n);        // no dirty dst lines over the DMA target

    printf("  src_pa=0x%010llx dst_pa=0x%010llx size=%zu burst=%s awlen=%d\n",
           (unsigned long long)src.pa, (unsigned long long)dst.pa, n,
           burst == AXI_BURST_INCR ? "INCR" : "FIXED", awlen);

    if (map_channel(engine_base, ch) != 0) { dbuf_free(&src); dbuf_free(&dst); return 2; }
    zdma_reset();
    zdma_cfg_normal(src.pa, dst.pa, (uint32_t)n, burst, awlen,
                    AXI_CACHE_DEV_NONBUF, AXI_CACHE_DEV_NONBUF, /*coherent*/0);
    zdma_start();

    uint32_t isr = 0, sts = 0, tb = 0;
    int r = zdma_poll(2000, &isr, &sts, &tb);
    printf("  poll -> %s  ISR=0x%03x STS=0x%x TOTAL_BYTE=%u\n",
           r == R_DONE ? "DONE" : r == R_ERROR ? "ERROR" : "STALLED", isr, sts & STS_STATE_MASK, tb);

    int rc = 1;
    if (r == R_DONE) {
        dcache_civac(dst.va, n);    // invalidate -> read fresh DDR
        if (memcmp(src.va, dst.va, n) == 0) {
            printf("  VERIFY: dst == src  ->  SELFTEST PASS\n");
            printf("  (ZDMA programming AND physical addressing confirmed; SMMU not remapping)\n");
            rc = 0;
        } else {
            printf("  VERIFY: dst != src  ->  SELFTEST FAIL (mismatch)\n");
            printf("  If ISR said DONE but data is wrong, suspect SMMU/IOMMU remap or cache.\n");
        }
    } else {
        printf("  SELFTEST FAIL: engine did not complete a plain DDR->DDR copy.\n");
    }
    dbuf_free(&src); dbuf_free(&dst);
    return rc;
}

static int in_pl_aperture(uint64_t a, uint64_t sz)
{
    uint64_t end = a + sz - 1;
    if (a >= HPM0_LPD_LO && end <= HPM0_LPD_HI) return 1;
    if (a >= HPM0_FPD_LO && end <= HPM0_FPD_HI) return 1;
    if (a >= HPM1_FPD_LO && end <= HPM1_FPD_HI) return 1;
    return 0;
}

static int do_induce(unsigned long engine_base, int ch, uint64_t dst, uint32_t size,
                     int burst, int awlen, int use_writeonly, uint32_t pattern,
                     int timeout_ms, int beat_bytes)
{
    printf("=== INDUCE: posted write bursts -> PL aperture (EXPECT STALL) ===\n");

    // SAFETY: destination must be a PL aperture, never DDR/OCM/peripheral space.
    // For INCR the whole walked range must stay inside the aperture.
    uint64_t span = (burst == AXI_BURST_INCR) ? size : (uint64_t)(awlen + 1) * beat_bytes;
    if (!in_pl_aperture(dst, span)) {
        fprintf(stderr,
          "REFUSING: dst 0x%llx (+0x%llx) is not wholly inside a PL aperture\n"
          "  HPM0_LPD 0x80000000-0x9FFFFFFF, HPM0_FPD 0xA0000000-0xAFFFFFFF, "
          "HPM1_FPD 0xB0000000-0xBFFFFFFF\n",
          (unsigned long long)dst, (unsigned long long)span);
        return 2;
    }

    long ntxn = (long)((size + (uint32_t)(awlen + 1) * beat_bytes - 1) /
                       ((uint32_t)(awlen + 1) * beat_bytes));
    printf("  dst=0x%010llx size=%u mode=%s burst=%s awlen=%d(%d-beat) "
           "beat=%dB  ~%ld transactions\n",
           (unsigned long long)dst, size, use_writeonly ? "write-only" : "normal",
           burst == AXI_BURST_INCR ? "INCR" : "FIXED", awlen, awlen + 1,
           beat_bytes, ntxn);
    printf("  shape: many SHORT self-completing writes (small AWLEN) -> fill the\n"
           "         downstream 8-deep window WITHOUT arming its write_broken check\n");

    struct dbuf src; int have_src = 0;
    if (map_channel(engine_base, ch) != 0) return 2;
    zdma_reset();

    if (use_writeonly) {
        uint32_t pat[4] = { pattern, pattern, pattern, pattern };
        zdma_cfg_writeonly(dst, size, pat, burst, awlen, AXI_CACHE_NC_BUF);
    } else {
        // normal mode: real, fully-resident DDR source so no read stalls mid-burst
        if (dbuf_alloc(&src, size) != 0) return 2;
        have_src = 1;
        uint32_t n = size < src.bytes ? size : (uint32_t)src.bytes;
        if (n != size) { printf("  (capping to contiguous src %u bytes)\n", n); size = n; }
        memset(src.va, 0x5A, size);
        dcache_civac(src.va, size);
        zdma_cfg_normal(src.pa, dst, size, burst, awlen,
                        AXI_CACHE_DEV_NONBUF, AXI_CACHE_NC_BUF, /*coherent*/0);
    }

    printf("  starting engine... (SIGKILL-safe: channel EN just set; wedge is in the fabric)\n");
    zdma_start();

    uint32_t isr = 0, sts = 0, tb = 0;
    int r = zdma_poll(timeout_ms, &isr, &sts, &tb);
    const char *rs = r == R_DONE ? "DONE" : r == R_ERROR ? "ERROR" : "STALLED";
    printf("  poll(%dms) -> %s  ISR=0x%03x STS=0x%x TOTAL_BYTE=%u of %u\n",
           timeout_ms, rs, isr, sts & STS_STATE_MASK, tb, size);

    if (r == R_STALLED) {
        // confirm it is truly stuck (TOTAL_BYTE not advancing)
        uint32_t tb2 = reg_rd(CH_TOTAL_BYTE);
        struct timespec s = {0, 50 * 1000 * 1000}; nanosleep(&s, NULL);
        uint32_t tb3 = reg_rd(CH_TOTAL_BYTE);
        printf("  drain-check: TOTAL_BYTE %u -> %u -> %u  (%s)\n", tb, tb2, tb3,
               (tb2 == tb3) ? "STUCK -- wedge induced" : "still draining slowly");
        printf("  RESULT: engine STALLED with writes outstanding -> INDUCTION ACHIEVED.\n");
        printf("  Recover the die/link via JTAG-POR before further tests.\n");
    } else if (r == R_DONE) {
        printf("  RESULT: transfer COMPLETED -- the aperture drained all writes;\n"
               "          no wedge this run (window not overrun, or link healthy).\n");
    } else {
        printf("  RESULT: engine reported an AXI/protocol ERROR (ISR err bits set).\n");
    }
    if (have_src) dbuf_free(&src);
    return (r == R_STALLED) ? 0 : 1;
}

// ------------------------------------------------------------------- usage
static void usage(const char *p)
{
    printf(
"Usage: %s (--selftest | --induce [SIZE]) [options]\n"
"\n"
"Modes:\n"
"  --selftest            ZDMA DDR->DDR copy + verify (SAFE). Run this FIRST.\n"
"  --induce [SIZE]       Posted write bursts to a PL aperture (EXPECT STALL).\n"
"                        SIZE in bytes, or with K/M suffix (default 65536).\n"
"\n"
"Routing:\n"
"  --engine adma|gdma    adma=LPD @0xFFA80000 (default, direct to HPM0_LPD),\n"
"                        gdma=FPD @0xFD500000 (reaches HPM0_LPD via FPD->LPD).\n"
"  --channel N           0..7 (default 0).\n"
"\n"
"Induce target/shape:\n"
"  --addr HEX            PL destination (default 0x80000000 = HPM0_LPD).\n"
"                        Refused unless wholly inside a PL aperture.\n"
"  --awlen N             AXI burst length-1, 0..15 (default 0 = single-beat,\n"
"                        the most 'self-completing' shape). SMALL keeps each\n"
"                        transaction short so the per-txn check never arms.\n"
"  --burst incr|fixed    default incr (fixed hammers exactly --addr).\n"
"  --mode writeonly|normal  writeonly (default): no source read, max outstanding.\n"
"                           normal: real resident DDR source -> PL (DMA-250-like).\n"
"  --pattern HEX         write-only data word (default 0xDEADBEEF).\n"
"  --timeout MS          stall-detect poll timeout (default 1000).\n"
"\n"
"Other:\n"
"  --dry-run             print the exact register write plan; touch NO hardware.\n"
"  --verbose             echo every register write.\n"
"  --help\n"
"\n"
"Examples:\n"
"  sudo %s --selftest\n"
"  sudo %s --induce 65536\n"
"  %s --induce --dry-run --awlen 0 --burst incr\n", p, p, p, p);
}

static uint64_t parse_size(const char *s)
{
    char *e = NULL;
    uint64_t v = strtoull(s, &e, 0);
    if (e && *e) {
        if (*e == 'k' || *e == 'K') v <<= 10;
        else if (*e == 'm' || *e == 'M') v <<= 20;
    }
    return v;
}

int main(int argc, char **argv)
{
    int mode_selftest = 0, mode_induce = 0;
    unsigned long engine_base = ADMA_BASE;
    int      channel   = 0;
    int      awlen     = 0;                 // single-beat default (shortest txn)
    int      burst     = AXI_BURST_INCR;
    int      writeonly = 1;                 // induce default: no source read
    int      timeout   = 1000;
    int      beat_bytes = 8;                // ADMA = 64-bit; GDMA overrides to 16
    uint32_t size      = 65536;
    uint64_t addr      = HPM0_LPD_LO;
    uint32_t pattern   = 0xDEADBEEF;

    for (int i = 1; i < argc; i++) {
        const char *a = argv[i];
        if      (!strcmp(a, "--selftest")) mode_selftest = 1;
        else if (!strcmp(a, "--induce"))  { mode_induce = 1;
            if (i + 1 < argc && argv[i+1][0] != '-') size = (uint32_t)parse_size(argv[++i]); }
        else if (!strcmp(a, "--engine") && i+1 < argc) {
            const char *e = argv[++i];
            if (!strcmp(e, "gdma")) { engine_base = GDMA_BASE; beat_bytes = 16; }
            else                    { engine_base = ADMA_BASE; beat_bytes = 8;  } }
        else if (!strcmp(a, "--channel") && i+1 < argc) channel = atoi(argv[++i]);
        else if (!strcmp(a, "--addr")    && i+1 < argc) addr = strtoull(argv[++i], NULL, 0);
        else if (!strcmp(a, "--awlen")   && i+1 < argc) awlen = atoi(argv[++i]) & 0xF;
        else if (!strcmp(a, "--burst")   && i+1 < argc) burst = strcmp(argv[++i], "fixed") ? AXI_BURST_INCR : AXI_BURST_FIXED;
        else if (!strcmp(a, "--mode")    && i+1 < argc) writeonly = strcmp(argv[++i], "normal") ? 1 : 0;
        else if (!strcmp(a, "--pattern") && i+1 < argc) pattern = (uint32_t)strtoul(argv[++i], NULL, 0);
        else if (!strcmp(a, "--timeout") && i+1 < argc) timeout = atoi(argv[++i]);
        else if (!strcmp(a, "--dry-run")) g_dry = 1;
        else if (!strcmp(a, "--verbose")) g_verbose = 1;
        else if (!strcmp(a, "--help") || !strcmp(a, "-h")) { usage(argv[0]); return 0; }
        else { fprintf(stderr, "unknown arg: %s\n", a); usage(argv[0]); return 2; }
    }

    if (mode_selftest == mode_induce) {   // need exactly one
        fprintf(stderr, "error: choose exactly one of --selftest / --induce\n");
        usage(argv[0]); return 2;
    }
    if (channel < 0 || channel > 7) { fprintf(stderr, "channel must be 0..7\n"); return 2; }

    printf("zdma_induce  engine=%s(0x%08lx) ch=%d  %s\n",
           engine_base == ADMA_BASE ? "ADMA" : "GDMA", engine_base, channel,
           g_dry ? "[DRY-RUN]" : "");

    if (!g_dry && geteuid() != 0)
        fprintf(stderr, "WARN: not root -- /dev/mem and pagemap PFNs will fail.\n");

    if (mode_selftest)
        return do_selftest(engine_base, channel, burst, awlen);
    return do_induce(engine_base, channel, addr, size, burst, awlen,
                     writeonly, pattern, timeout, beat_bytes);
}
