"""The rc4 DMA-250's idle cycles at source<->destination switches (cpu_ss_hsel mechanism).

The phantom behind the defect needs the master's next NONSEQ to another slave within <=1 IDLE
cycle. This asserts the rc4 DMA-250 always issues that fast (measured: 0 IDLE at every switch).

Programming mirrors nanosoc-multicore-system/cocotb/dma250_block/test_dma250_copy.py
(the firmware's dma250_mem2mem_1d()). Source region HADDR[15]=0, destination HADDR[15]=1.
"""
import cocotb
from cocotb.triggers import RisingEdge, FallingEdge, ClockCycles

CH0 = 0x1000
CH_CMD, CH_STATUS, CH_INTREN, CH_CTRL = CH0 + 0x000, CH0 + 0x004, CH0 + 0x008, CH0 + 0x00C
CH_SRCADDR, CH_DESADDR, CH_XSIZE, CH_XADDRINC, CH_LINKADDR = (
    CH0 + 0x010, CH0 + 0x018, CH0 + 0x020, CH0 + 0x030, CH0 + 0x078)
CMD_ENABLECMD, CMD_CLEARCMD = 1 << 0, 1 << 1
STAT_DONE, STAT_ERR = 1 << 16, 1 << 17
CTRL_1D_WORD = 2 | (1 << 9) | (1 << 21)
SRC, DST = 0x0000_0000, 0x0000_8000

NBEATS = [1, 2, 4, 8, 16, 64]
WAITS = [(0, 0), (0, 2), (2, 0), (0, 3)]   # (source, destination) wait states


MAX_IDLE = 1


def switch_gaps(cycles):
    """[(htrans, haddr, hwrite, hready)] per cycle -> [(kind, idle)] at each region switch.
    Region = HADDR[15]. idle = IDLE cycles between the last accepted transfer in one region and
    the first NONSEQ presented in the other."""
    out, last, idle, presented = [], None, 0, False
    for t, a, w, r in cycles:
        reg = (a >> 15) & 1
        if t in (2, 3) and last is not None and reg != last[0] and not presented:
            out.append((("R" if not last[1] else "W") + "->" + ("W" if w else "R"), idle))
            presented = True
        if t == 0:
            idle += 1
        if t in (2, 3) and r:
            last, idle, presented = (reg, w), 0, False
    return out


async def sample(dut, trace):
    while True:
        await FallingEdge(dut.hclk)
        if int(dut.scen.value):
            trace.append((int(dut.htrans.value), int(dut.haddr.value),
                          int(dut.hwrite.value), int(dut.hready.value)))


async def reset(dut):
    dut.hresetn.value = 0
    await ClockCycles(dut.hclk, 10)
    dut.hresetn.value = 1
    await ClockCycles(dut.hclk, 4)


async def apb_write(dut, addr, data):
    await RisingEdge(dut.hclk)
    dut.paddr.value, dut.pwdata.value, dut.pwrite.value = addr, data, 1
    dut.psel.value, dut.penable.value = 1, 0
    await RisingEdge(dut.hclk)
    dut.penable.value = 1
    await RisingEdge(dut.hclk)
    dut.psel.value, dut.penable.value, dut.pwrite.value = 0, 0, 0


async def apb_read(dut, addr):
    await RisingEdge(dut.hclk)
    dut.paddr.value, dut.pwrite.value = addr, 0
    dut.psel.value, dut.penable.value = 1, 0
    await RisingEdge(dut.hclk)
    dut.penable.value = 1
    await RisingEdge(dut.hclk)
    val = int(dut.prdata.value)
    dut.psel.value, dut.penable.value = 0, 0
    return val


@cocotb.test()
async def test_issue_gaps(dut):
    # The measurement must be able to fail: two IDLEs between a read and a write read as 2.
    probe = [(2, 0x0000, 0, 1), (0, 0, 0, 1), (0, 0, 0, 1), (2, 0x8000, 1, 1)]
    assert switch_gaps(probe) == [("R->W", 2)], switch_gaps(probe)
    trace = []
    cocotb.start_soon(sample(dut, trace))
    await reset(dut)
    await ClockCycles(dut.hclk, 50)                      # LPI power-up handshake
    dut._log.info("CH_IIDR=0x%08x", await apb_read(dut, CH0 + 0x0C8))
    sid = 0
    bad = slow = switches = 0
    for nb in NBEATS:
        for wl, wh in WAITS:
            sid += 1
            for i in range(nb):
                dut.u_sram.mem[(SRC >> 2) + i].value = 0xA5A50000 | (sid << 8) | i
                dut.u_sram.mem[(DST >> 2) + i].value = 0
            dut.u_sram.ws_lo.value, dut.u_sram.ws_hi.value = wl, wh
            await apb_write(dut, CH_CMD, CMD_CLEARCMD)
            await apb_write(dut, CH_STATUS, STAT_DONE | STAT_ERR | 0xF)
            await apb_write(dut, CH_INTREN, 0)
            await apb_write(dut, CH_LINKADDR, 0)
            await apb_write(dut, CH_SRCADDR, SRC)
            await apb_write(dut, CH_DESADDR, DST)
            await apb_write(dut, CH_XSIZE, (nb & 0xFFFF) | ((nb & 0xFFFF) << 16))
            await apb_write(dut, CH_XADDRINC, 1 | (1 << 16))
            await apb_write(dut, CH_CTRL, CTRL_1D_WORD)
            trace.clear()
            dut.scen.value = sid
            await apb_write(dut, CH_CMD, CMD_ENABLECMD)
            for _ in range(20000):
                st = await apb_read(dut, CH_STATUS)
                assert not (st & STAT_ERR), f"scen {sid}: DMA error 0x{st:08x}"
                if st & STAT_DONE:
                    break
            else:
                raise AssertionError(f"scen {sid}: no STAT_DONE")
            await ClockCycles(dut.hclk, 4)
            dut.scen.value = 0
            errs = sum(int(dut.u_sram.mem[(DST >> 2) + i].value) != (0xA5A50000 | (sid << 8) | i)
                       for i in range(nb))
            bad += errs
            gaps = switch_gaps(trace)
            worst = max((i for _, i in gaps), default=0)
            slow += sum(1 for _, i in gaps if i > MAX_IDLE)
            switches += len(gaps)
            dut._log.info("SCEN %d nbeats=%d ws_src=%d ws_dst=%d copy_errors=%d switches=%d max_idle=%d",
                          sid, nb, wl, wh, errs, len(gaps), worst)
    assert bad == 0, f"{bad} copy errors"
    assert switches > 0, "no region switches observed: the measurement saw nothing"
    assert slow == 0, f"{slow}/{switches} switches had more than {MAX_IDLE} IDLE cycles"
    dut._log.info("VERDICT PASS: %d/%d switches at <=%d IDLE (phantom-capable)", switches, switches, MAX_IDLE)
