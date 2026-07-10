"""Does a memory transaction actually cross the die boundary, with its address intact?

Copyright 2026, SoC Labs (www.soclabs.org)

`docs/PEER_APERTURE_PROGRAMMING.md` §8.1 answers that by reading the Chisel and
the generated Verilog: the packetiser carries a 64-bit address field and the far
die reconstructs it from the packet. Reading RTL is not simulating a transaction.
This does the transaction.

Die A writes `0x2F00_1000`. TideLink's 8-rule CAM must rewrite `addr[31:24]`
from `0x2F` to `0x2D`, the packetiser must carry it, and die B's `ahb_mng` must
re-present `0x2D00_1000` to its local fabric, where `ahb_probe_mem` latches it.

The assertion that the address equals `0x2D......` is worthless on its own — a
testbench that hard-wired `0x2D` anywhere would pass it. So `test_cam_disabled_is_identity`
runs the identical transfer with the CAM's `global_enable` clear and requires the
address to arrive as `0x2F......`. Only the pair of results shows the CAM is what
moved the byte, and that the byte crossed the link rather than being invented on
the far side.

Direction is deliberately master→slave. TideLink's own pair tests record a
sim-harness S→M asymmetry (`test_04`, `test_30`, `test_36`): the master's
`crack_pkt_seen_rx` can stay 0 regardless of bring-up. M→S is the proven-good
direction, so that is the one used here.
"""
import os

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge
from cocotb.utils import get_sim_time

# Every test carries a sim-time timeout so a link wedge is a clean FAIL rather
# than a simulation that runs until someone notices. Note this cannot catch a
# zero-delay loop, where sim time never advances — the heartbeat below is what
# distinguishes "wedged but ticking" from "sim time frozen".
TEST_TIMEOUT_MS = 4


async def _heartbeat(dut, every=1000):
    """Log sim time periodically. If these stop while the process still burns CPU,
    the simulator is in a zero-delay loop, not a slow test."""
    while True:
        await ClockCycles(dut.hclk, every)
        dut._log.info(f"heartbeat: t={get_sim_time('us'):.1f} us")

CLK_PERIOD_NS = 20.0   # hclk  = 50 MHz  (AHB/APB/application clock)
REF_PERIOD_NS = 8.0    # ref_clk = 125 MHz (Wlink PLL reference)

# --- APB map. Three regions, decoded on apb_paddr[14:13] (tidelink_top.sv:688).
#     !14 & !13 -> 0x0000 Wlink LL
#     !14 &  13 -> 0x2000 TideLink cfg + PTP + Region 8
#      14 & !13 -> 0x4000 Address translator (CAM), channel 0
APB_WL_LINK_ENABLE_RESET = 0x0208
APB_ROLE_CFG             = 0x2080   # NOT 0x2084 — see REGISTER_MAP.md:164
APB_R8_SLOT0             = 0x2100
APB_R8_SWI_LANE_STATUS   = 0x2108   # bit[16] = cal_done

CAM_BASE_OFFSET = 0x4000
CAM_CTRL        = 0x4004            # bit[0] = global_enable
CAM_RULE_0      = 0x4010            # [0]=enable [15:8]=match [23:16]=replace

ROLE_CFG_MASTER_LOCK = 0x02         # bit0=0 master, bit1=1 lock
ROLE_CFG_SLAVE_LOCK  = 0x03         # bit0=1 slave,  bit1=1 lock

# The 3-write LL bootstrap. The order matters: a {swreset=1, swi_enable=0} write
# returns all seven FCSMs to IDLE and loses the CR/CRACK sticky state.
LL_SWRESET_ON  = 0x00027F08
LL_SWRESET_OFF = 0x00027F00
LL_ENABLE      = 0x00027F07

# The mapping under test: die A's 0x2F aperture -> die B's 0x2D (shared_sram_0).
APERTURE_BYTE = 0x2F
REMOTE_BYTE   = 0x2D
RULE_0_VALUE  = (REMOTE_BYTE << 16) | (APERTURE_BYTE << 8) | 1   # 0x002D2F01

PEER_ADDR = (APERTURE_BYTE << 24) | 0x001000    # 0x2F001000
XLAT_ADDR = (REMOTE_BYTE   << 24) | 0x001000    # 0x2D001000
PAYLOAD   = 0xC0FFEE01


class ApbMaster:
    """Hand-rolled APB3. TideLink's own harness does not use cocotbext-apb."""

    def __init__(self, dut, prefix):
        self.dut = dut
        self.clk = dut.hclk
        self.p = lambda n: getattr(dut, f"{prefix}_apb_{n}")

    def idle(self):
        self.p("psel").value = 0
        self.p("penable").value = 0
        self.p("pwrite").value = 0

    async def _xfer(self, addr, data, write, timeout=200):
        await RisingEdge(self.clk)
        self.p("psel").value = 1
        self.p("paddr").value = addr & 0x7FFF
        self.p("pwrite").value = 1 if write else 0
        self.p("pwdata").value = data
        self.p("pstrb").value = 0xF
        self.p("pprot").value = 0
        self.p("penable").value = 0
        await RisingEdge(self.clk)
        self.p("penable").value = 1
        for _ in range(timeout):
            await RisingEdge(self.clk)
            if int(self.p("pready").value):
                rd = 0
                if not write:
                    try:
                        rd = int(self.p("prdata").value)
                    except ValueError:
                        rd = 0
                self.idle()
                return rd
        self.idle()
        raise TimeoutError(f"APB {'write' if write else 'read'} @0x{addr:04x} never readied")

    async def write(self, addr, data):
        await self._xfer(addr, data, True)

    async def read(self, addr):
        return await self._xfer(addr, 0, False)


class AhbSubMaster:
    """AHB-Lite master on die A's `ahb_sub` — the peer aperture.

    Timing follows the lesson in tidelink's `test_data_path_compliant`: sample
    `hreadyout` on the clock edge, never combinationally in the same timestep, and
    hold `hwdata` for the whole data phase. Getting this wrong ships the payload
    as zero and the test still 'passes' its address check.
    """

    def __init__(self, dut, timeout=500):
        self.dut = dut
        self.clk = dut.hclk
        self.timeout = timeout

    def idle(self):
        self.dut.m_sub_hsel.value = 0
        self.dut.m_sub_htrans.value = 0
        self.dut.m_sub_hwrite.value = 0

    async def _addr_phase(self, addr, write):
        self.dut.m_sub_hsel.value = 1
        self.dut.m_sub_haddr.value = addr
        self.dut.m_sub_htrans.value = 0b10        # NONSEQ
        self.dut.m_sub_hwrite.value = 1 if write else 0
        self.dut.m_sub_hsize.value = 0b010        # word
        self.dut.m_sub_hburst.value = 0           # SINGLE
        self.dut.m_sub_hprot.value = 0
        for _ in range(self.timeout):
            await RisingEdge(self.clk)
            if int(self.dut.m_sub_hreadyout.value):
                return
        raise TimeoutError(f"ahb_sub address phase @0x{addr:08x} never accepted")

    async def _data_phase(self):
        for _ in range(self.timeout):
            await RisingEdge(self.clk)
            if int(self.dut.m_sub_hreadyout.value):
                return int(self.dut.m_sub_hresp.value)
        raise TimeoutError("ahb_sub data phase never completed")

    async def write(self, addr, data):
        await self._addr_phase(addr, True)
        self.dut.m_sub_htrans.value = 0           # IDLE — single beat
        self.dut.m_sub_hsel.value = 0
        self.dut.m_sub_hwdata.value = data        # held across the data phase
        resp = await self._data_phase()
        self.idle()
        return resp

    async def read(self, addr):
        await self._addr_phase(addr, False)
        self.dut.m_sub_htrans.value = 0
        self.dut.m_sub_hsel.value = 0
        resp = await self._data_phase()
        data = int(self.dut.m_sub_hrdata.value)
        self.idle()
        return resp, data


class Pair:
    def __init__(self, dut):
        self.dut = dut
        self.log = dut._log
        self.m_apb = ApbMaster(dut, "m")
        self.s_apb = ApbMaster(dut, "s")
        self.sub = AhbSubMaster(dut)
        cocotb.start_soon(Clock(dut.hclk, CLK_PERIOD_NS, units="ns").start())
        cocotb.start_soon(Clock(dut.ref_clk, REF_PERIOD_NS, units="ns").start())
        cocotb.start_soon(_heartbeat(dut))

    def _calibrator_sim_bypass(self):
        """Without this, both calibrators sit in S_VALIDATE for 2M link cycles and
        `cal_done` never asserts inside any sane sim budget. Must be applied before
        `role_locked` rises."""
        for name in ("u_master", "u_slave"):
            try:
                getattr(self.dut, name).u_chiplet_controller.u_calibrator.tb_early_exit_force_q.value = 1
            except AttributeError:
                self.log.warning(f"{name}: tb_early_exit_force_q missing — bypass NOT applied")

    async def reset(self):
        self.m_apb.idle()
        self.s_apb.idle()
        self.sub.idle()
        self.dut.poresetn.value = 0
        self.dut.hresetn.value = 0
        await ClockCycles(self.dut.hclk, 20)
        self._calibrator_sim_bypass()
        self.dut.poresetn.value = 1
        await ClockCycles(self.dut.hclk, 5)
        self.dut.hresetn.value = 1
        await ClockCycles(self.dut.hclk, 50)

    async def role_lock(self):
        await self.m_apb.write(APB_ROLE_CFG, ROLE_CFG_MASTER_LOCK)
        await self.s_apb.write(APB_ROLE_CFG, ROLE_CFG_SLAVE_LOCK)
        await ClockCycles(self.dut.hclk, 200)
        for _ in range(400):
            if int(self.dut.m_role_locked.value) and int(self.dut.s_role_locked.value):
                return
            await ClockCycles(self.dut.hclk, 50)
        raise TimeoutError("role_locked never asserted on both dies")

    async def wait_cal_done(self):
        """cal_done is bit[16] of SWI_LANE_STATUS. Do NOT gate on lanes_locked==0xff:
        that only reads 0xff while the calibrator drives training patterns, and
        self-deasserts to 0x00 after S_DONE in passive autocal.

        Budget deliberately tight. TideLink's own harness allows 500k hclk here,
        which at this design's ~1.2k simulated cycles per wall-clock minute is
        about seven hours — a failure looks exactly like a hang. Bring-up converges
        by ~6k cycles, so 10k is a 1.7x margin and a real failure reports in
        minutes."""
        for _ in range(100):
            m = await self.m_apb.read(APB_R8_SWI_LANE_STATUS)
            s = await self.s_apb.read(APB_R8_SWI_LANE_STATUS)
            if ((m >> 16) & 1) and ((s >> 16) & 1):
                return
            await ClockCycles(self.dut.hclk, 100)
        raise TimeoutError("cal_done never asserted on both dies within 10k hclk")

    async def to_data_mode(self):
        await self.m_apb.write(APB_R8_SLOT0, 0)
        await self.s_apb.write(APB_R8_SLOT0, 0)
        await ClockCycles(self.dut.hclk, 20)
        for val in (LL_SWRESET_ON, LL_SWRESET_OFF, LL_ENABLE):
            await self.m_apb.write(APB_WL_LINK_ENABLE_RESET, val)
            await self.s_apb.write(APB_WL_LINK_ENABLE_RESET, val)
            await ClockCycles(self.dut.hclk, 20)
        await ClockCycles(self.dut.hclk, 5000)   # CR/CRACK exchange

    def _fcsm(self, side):
        top = self.dut.u_master if side == "m" else self.dut.u_slave
        return top.u_chiplet_controller.u_wlink.tl2wl.wlink_tidelinktl

    def link_carries_m2s(self):
        """The slave has seen the master's CR and CRACK packets. This is evidence
        the M->S link layer is live. `link_active` is NOT — it is literally
        `assign link_active = role_locked_o` (tidelink_top.sv:2308)."""
        f = self._fcsm("s")
        return int(f.cr_pkt_seen_rx.value) and int(f.crack_pkt_seen_rx.value)

    async def bring_up(self):
        await self.reset()
        await self.role_lock()
        await self.wait_cal_done()
        await self.to_data_mode()

    async def program_cam(self, enable=True):
        """Three writes, CTRL armed last so a half-configured rule is never live."""
        await self.m_apb.write(CAM_BASE_OFFSET, 0x00000000)
        await self.m_apb.write(CAM_RULE_0, RULE_0_VALUE)
        await self.m_apb.write(CAM_CTRL, 1 if enable else 0)

    def probe(self):
        d = self.dut
        return dict(
            haddr=int(d.probe_last_haddr.value),
            hwdata=int(d.probe_last_hwdata.value),
            writes=int(d.probe_write_count.value),
            reads=int(d.probe_read_count.value),
        )

    async def settle(self, cycles=2000):
        await ClockCycles(self.dut.hclk, cycles)



# ---------------------------------------------------------------------------
# ONE test, staged.
#
# Not four tests. cocotb runs every test in the same simulation, and a second
# `bring_up()` in the same sim does not re-converge: `cal_done` never re-asserts
# after the warm reset, so the test grinds through its whole cal budget. With
# TideLink's stock 500k-hclk budget that is ~7 hours of wall clock, which reads
# exactly like a hang. Bring up once, then assert in stages.
#
# The cost is that a failure at stage 2 hides stages 3-4. That is the right trade
# here: each bring-up is ~6 minutes of wall clock.
# ---------------------------------------------------------------------------
@cocotb.test(timeout_time=400, timeout_unit="us")
async def test_peer_aperture_crosses_the_link(dut):
    tb = Pair(dut)

    # -- Stage 1: the link. If this fails nothing below means anything. --------
    await tb.bring_up()
    assert tb.link_carries_m2s(), (
        "M->S link layer never came up (cr/crack not seen on the slave)."
    )
    dut._log.info("STAGE 1 ok: link up (cal_done both dies; cr+crack seen on slave)")

    # -- Stage 2: the CAM fires and the upper byte crosses. --------------------
    await tb.program_cam(enable=True)
    before = tb.probe()
    resp = await tb.sub.write(PEER_ADDR, PAYLOAD)
    assert resp == 0, f"peer write took an ERROR response (hresp={resp})"
    await tb.settle()
    after = tb.probe()

    assert after["writes"] > before["writes"], (
        f"nothing arrived at die B (writes {before['writes']} -> {after['writes']}). "
        "The transaction did not cross the link."
    )
    assert after["haddr"] == XLAT_ADDR, (
        f"die B saw 0x{after['haddr']:08x}, expected 0x{XLAT_ADDR:08x}"
    )
    assert (after["haddr"] >> 24) != APERTURE_BYTE, (
        "die B saw the UNtranslated upper byte — the CAM did not fire"
    )
    assert after["hwdata"] == PAYLOAD, (
        f"address crossed but data did not: got 0x{after['hwdata']:08x}, "
        f"expected 0x{PAYLOAD:08x} (check the data-phase hwdata hold)"
    )
    dut._log.info(f"STAGE 2 ok: die A 0x{PEER_ADDR:08x} -> die B 0x{after['haddr']:08x} "
                  f"data=0x{after['hwdata']:08x}")

    # -- Stage 3: the return path. --------------------------------------------
    resp, data = await tb.sub.read(PEER_ADDR)
    assert resp == 0, f"peer read took an ERROR response (hresp={resp})"
    assert data == PAYLOAD, f"read back 0x{data:08x}, wrote 0x{PAYLOAD:08x}"
    dut._log.info(f"STAGE 3 ok: read-back across the link = 0x{data:08x}")

    # -- Stage 4: THE CONTROL. Without it stage 2 proves nothing. -------------
    # Same transfer, CAM global_enable clear. The address must arrive
    # UNtranslated. If this also reported 0x2D, the upper byte would be coming
    # from somewhere other than the CAM and stage 2 would be measuring nothing.
    await tb.m_apb.write(CAM_CTRL, 0)
    before = tb.probe()
    resp = await tb.sub.write(PEER_ADDR ^ 0x40, PAYLOAD ^ 0xFFFF)   # different word
    assert resp == 0, f"peer write took an ERROR response with the CAM off (hresp={resp})"
    await tb.settle()
    after = tb.probe()

    assert after["writes"] > before["writes"], "nothing arrived at die B with the CAM disabled"
    assert (after["haddr"] >> 24) == APERTURE_BYTE, (
        f"with global_enable=0 the CAM must be an identity map, but die B saw "
        f"0x{after['haddr']:08x}. Stage 2's 0x2D did not come from the CAM."
    )
    dut._log.info(f"STAGE 4 ok: CAM disabled -> die B saw 0x{after['haddr']:08x} (identity)")
