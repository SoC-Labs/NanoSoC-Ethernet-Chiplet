"""Full-SoC cpu_ss_hsel / eth_ss regression, rc4-lineage nanosoc_multicore_soc.

EXPECT=defect (shipped RTL): every corruption below must reproduce exactly.
EXPECT=clean  (both HSEL gates applied): none may appear.

The DMA-250 is the ONLY bus master: both CPUs' AHB HTRANS are forced IDLE from t=0 and the
DAP/HOSTIO/D2D/backdoor inputs are tied idle by soc_smoke's tb_top. The DMA is programmed
through its APB port by forcing dmac_0_apb_* (testbench shortcut; the AHB data path, where
the defect lives, is untouched RTL). Memories are seeded and read back hierarchically.
"""
import os

import cocotb
from cocotb.handle import Force, Release
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles, Timer

CH0 = 0x1000
CH_CMD, CH_STATUS, CH_INTREN, CH_CTRL = CH0 + 0x000, CH0 + 0x004, CH0 + 0x008, CH0 + 0x00C
CH_SRCADDR, CH_DESADDR, CH_XSIZE, CH_XADDRINC, CH_LINKADDR, CH_IIDR = (
    CH0 + 0x010, CH0 + 0x018, CH0 + 0x020, CH0 + 0x030, CH0 + 0x078, CH0 + 0x0C8)
CMD_ENABLECMD, CMD_CLEARCMD = 1 << 0, 1 << 1
STAT_DONE, STAT_ERR = 1 << 16, 1 << 17
CTRL_1D_WORD = 2 | (1 << 9) | (1 << 21)
N = 8


def mem(parent):
    return [getattr(parent, f"BRAM{b}") for b in range(4)]


def mw(parent, idx, val):
    for b, arr in enumerate(mem(parent)):
        arr[idx].value = (val >> (8 * b)) & 0xFF


def mr(parent, idx):
    return sum(int(arr[idx].value) << (8 * b) for b, arr in enumerate(mem(parent)))


class Apb:
    def __init__(self, u):
        self.u, self.clk = u, u.u_network_core_sys_hclk
        self.idle()

    def _set(self, sel, en, wr, addr, data):
        u = self.u
        u.dmac_0_apb_psel.value = Force(sel)
        u.dmac_0_apb_penable.value = Force(en)
        u.dmac_0_apb_pwrite.value = Force(wr)
        u.dmac_0_apb_paddr.value = Force(addr)
        u.dmac_0_apb_pwdata.value = Force(data)

    def idle(self):
        self._set(0, 0, 0, 0, 0)

    async def xfer(self, addr, data=0, write=False):
        await RisingEdge(self.clk)
        self._set(1, 0, int(write), addr, data)
        await RisingEdge(self.clk)
        self._set(1, 1, int(write), addr, data)
        for _ in range(1000):
            await RisingEdge(self.clk)
            if int(self.u.dmac_0_apb_pready.value):
                val = int(self.u.dmac_0_apb_prdata.value)
                self.idle()
                return val
        raise AssertionError(f"APB 0x{addr:04x}: PREADY never rose")


class WriteLog:
    """Write address phases (and their data) seen on one AHB slave-side interface."""
    def __init__(self, clk, htrans, hwrite, hready, haddr, hwdata, hsel=None):
        self.clk, self.t, self.w, self.r, self.a, self.d, self.s = (
            clk, htrans, hwrite, hready, haddr, hwdata, hsel)
        self.log, self.on = [], False
        cocotb.start_soon(self._run())

    @classmethod
    def region(cls, r):
        return cls(r.HCLK, r.HTRANS, r.HWRITE, r.HREADY, r.HADDR, r.HWDATA, r.HSEL)

    async def _run(self):
        pend = None
        while True:
            await FallingEdge(self.clk)
            if pend is not None and int(self.r.value):
                self.log.append((pend, int(self.d.value)))
                pend = None
            sel = 1 if self.s is None else int(self.s.value)
            if (self.on and sel and (int(self.t.value) & 2) and int(self.r.value)
                    and int(self.w.value)):
                pend = int(self.a.value)


async def dma_copy(dut, apb, src, dst, n):
    await apb.xfer(CH_CMD, CMD_CLEARCMD, True)
    await apb.xfer(CH_STATUS, STAT_DONE | STAT_ERR | 0xF, True)
    await apb.xfer(CH_INTREN, 0, True)
    await apb.xfer(CH_LINKADDR, 0, True)
    await apb.xfer(CH_SRCADDR, src, True)
    await apb.xfer(CH_DESADDR, dst, True)
    await apb.xfer(CH_XSIZE, n | (n << 16), True)
    await apb.xfer(CH_XADDRINC, 1 | (1 << 16), True)
    await apb.xfer(CH_CTRL, CTRL_1D_WORD, True)
    await apb.xfer(CH_CMD, CMD_ENABLECMD, True)
    for _ in range(5000):
        st = await apb.xfer(CH_STATUS)
        if st & (STAT_DONE | STAT_ERR):
            await ClockCycles(apb.clk, 100)          # let any re-issued phantom land
            return st
    raise AssertionError("DMA never finished")


@cocotb.test()
async def test_soc_hsel(dut):
    u = dut.u_dut
    # Only the DMA may drive the bus.
    u.u_network_core.i_network_core_htrans.value = Force(0)
    u.u_chip_core.i_cpu_0_htrans.value = Force(0)
    await Timer(1, unit="us")
    # Release the CPU0 boot gate (as cocotb/soc_dma250 does): it holds the whole
    # network-core reset domain, which also clocks/resets the DMA-250.
    cur = int(u.u_chip_core_remap_0.remap_q.value)
    u.u_chip_core_remap_0.remap_q.value = cur | 0x4
    for _ in range(2000):
        await RisingEdge(dut.sys_fclk)
        if int(u.u_network_core_sys_hresetn.value):
            break
    await ClockCycles(u.u_network_core_sys_hclk, 200)
    apb = Apb(u)
    iidr = await apb.xfer(CH_IIDR)
    dut._log.info("DMA-250 CH_IIDR=0x%08x", iidr)
    assert iidr not in (0, 0xFFFFFFFF), "DMA APB not alive"

    cpu1 = u.u_chip_core.u_region_dmem_0.u_mem.u_sram
    netc = u.u_network_core.u_region_dmem_0.u_sram.u_sram
    shs = u.u_shared_sram_0.u_sram.u_sram
    wl_cpu1 = WriteLog.region(u.u_chip_core.u_region_dmem_0)
    wl_shs = WriteLog.region(u.u_shared_sram_0)
    wl_d2d = WriteLog(dut.sys_hclk, u.d2d_ahb_m_htrans, u.d2d_ahb_m_hwrite, u.d2d_ahb_m_hready,
                      u.d2d_ahb_m_haddr, u.d2d_ahb_m_hwdata)
    summary = []
    m = {}

    # ---- S0: same-port copy, NETC DMEM -> NETC DMEM (no port switch: must be clean) ----
    for i in range(N):
        mw(netc, 0x040 + i, 0x50000000 | i); mw(netc, 0x080 + i, 0)
    st = await dma_copy(dut, apb, 0x1800_0100, 0x1800_0200, N)
    ok = all(mr(netc, 0x080 + i) == (0x50000000 | i) for i in range(N))
    m["s0"] = (st, ok)
    summary.append(f"S0 same-port NETC->NETC: status=0x{st:08x} dst_ok={ok}")

    # ---- P2: CPU1 DMEM (0x9800_0100) -> NETC DMEM (0x1800_0600) ----
    for i in range(N):
        mw(cpu1, 0x040 + i, 0xB2000000 | i)      # source
        mw(cpu1, 0x180 + i, 0xC0DE0000 | i)      # sentinel at the aliased dst offset 0x600
        mw(netc, 0x180 + i, 0)
    wl_cpu1.log.clear(); wl_cpu1.on = True
    st = await dma_copy(dut, apb, 0x9800_0100, 0x1800_0600, N)
    wl_cpu1.on = False
    dst_ok = sum(mr(netc, 0x180 + i) == (0xB2000000 | i) for i in range(N))
    zeroed = sum(mr(cpu1, 0x180 + i) == 0 for i in range(N))
    intact = sum(mr(cpu1, 0x180 + i) == (0xC0DE0000 | i) for i in range(N))
    m["p2"] = dict(st=st, dst_ok=dst_ok, zeroed=zeroed, intact=intact, writes=len(wl_cpu1.log))
    summary.append(f"P2 CPU1->NETC: status=0x{st:08x} dst_ok={dst_ok}/{N} "
                   f"CPU1-DMEM sentinel zeroed={zeroed}/{N} intact={intact}/{N} "
                   f"writes_into_CPU1_DMEM={len(wl_cpu1.log)}")
    for a, d in wl_cpu1.log[:4]:
        summary.append(f"    CPU1_DMEM write a=0x{a:08x} d=0x{d:08x}")

    # ---- P1a: NETC DMEM (0x1800_0400) -> shared SRAM (0x2D00_0400), not in dmac_0_m's map ----
    for i in range(N):
        mw(netc, 0x100 + i, 0xA1000000 | i); mw(shs, 0x100 + i, 0x5EED0000 | i)
    wl_shs.log.clear(); wl_shs.on = True
    st = await dma_copy(dut, apb, 0x1800_0400, 0x2D00_0400, N)
    wl_shs.on = False
    fin_zero = sum(mr(shs, 0x100 + i) == 0 for i in range(N))
    intact = sum(mr(shs, 0x100 + i) == (0x5EED0000 | i) for i in range(N))
    m["p1a"] = dict(st=st, zeroed=fin_zero, intact=intact, writes=len(wl_shs.log))
    summary.append(f"P1a NETC->SHARED_SRAM (DMA cannot decode 0x2D): status=0x{st:08x} "
                   f"writes_into_shared_sram={len(wl_shs.log)} sentinel_zeroed={fin_zero}/{N} "
                   f"intact={intact}/{N}")
    for a, d in wl_shs.log[:4]:
        summary.append(f"    SHARED write a=0x{a:08x} d=0x{d:08x}")

    # ---- P1b: NETC DMEM (0x1800_0500) -> D2D peer aperture (0x2F00_0400), a legal DMA target ----
    for i in range(N):
        mw(netc, 0x140 + i, 0xD2000000 | i)
    wl_d2d.log.clear(); wl_d2d.on = True
    st = await dma_copy(dut, apb, 0x1800_0500, 0x2F00_0400, N)
    wl_d2d.on = False
    last = {}
    for a, d in wl_d2d.log:
        last[a] = d
    real = sum(1 for a, d in wl_d2d.log if d == (0xD2000000 | ((a - 0x2F000400) >> 2)))
    zeros = sum(1 for a, d in wl_d2d.log if d == 0)
    fin_zero = sum(1 for i in range(N) if last.get(0x2F000400 + 4 * i) == 0)
    m["p1b"] = dict(st=st, writes=len(wl_d2d.log), real=real, zeros=zeros, fin_zero=fin_zero)
    summary.append(f"P1b NETC->D2D 0x2F: status=0x{st:08x} writes_across_d2d={len(wl_d2d.log)} "
                   f"with_real_data={real} with_zero={zeros} final_value_zero={fin_zero}/{N}")
    for a, d in wl_d2d.log[:6]:
        summary.append(f"    D2D write a=0x{a:08x} d=0x{d:08x}")

    for line in summary:
        dut._log.info("RESULT %s", line)
    u.u_network_core.i_network_core_htrans.value = Release()
    u.u_chip_core.i_cpu_0_htrans.value = Release()

    # ---- verdict ----
    expect = os.environ.get("EXPECT", "defect")
    done = lambda st: bool(st & STAT_DONE) and not (st & STAT_ERR)
    fails = []
    def need(cond, msg):
        if not cond:
            fails.append(msg)
    need(done(m["s0"][0]) and m["s0"][1], "S0 same-port copy must complete correctly")
    need(done(m["p2"]["st"]) and m["p2"]["dst_ok"] == N, "P2: the DMA's own copy must succeed")
    need(done(m["p1b"]["st"]) and m["p1b"]["real"] == N, "P1b: all 8 real writes must cross D2D")
    need(m["p1a"]["st"] & STAT_ERR, "P1a: 0x2D is not in dmac_0_m's map, so the DMA must ERROR")
    if expect == "defect":
        need(m["p2"]["zeroed"] == N and m["p2"]["writes"] == N, "P2: CPU1 DMEM must be zeroed 8/8")
        need(m["p1b"]["writes"] == 2 * N and m["p1b"]["zeros"] == N and m["p1b"]["fin_zero"] == N,
             "P1b: every D2D write must be followed by a zero write")
        need(m["p1a"]["zeroed"] >= 1 and m["p1a"]["writes"] >= 1, "P1a: shared SRAM must be zeroed")
    elif expect == "clean":
        need(m["p2"]["intact"] == N and m["p2"]["writes"] == 0, "P2: CPU1 DMEM must be untouched")
        need(m["p1b"]["writes"] == N and m["p1b"]["zeros"] == 0, "P1b: exactly 8 writes, no zeros")
        need(m["p1a"]["intact"] == N and m["p1a"]["writes"] == 0, "P1a: shared SRAM untouched")
    else:
        fails.append(f"EXPECT must be defect or clean, got {expect!r}")
    for f in fails:
        dut._log.error("VERDICT FAIL: %s", f)
    assert not fails, f"EXPECT={expect}: {len(fails)} check(s) failed"
    dut._log.info("VERDICT PASS: EXPECT=%s holds on every scenario", expect)
