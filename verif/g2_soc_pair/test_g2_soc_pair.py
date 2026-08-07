"""full G2: a memory transaction crosses from die A's SoC into die B's SoC SRAM.

Copyright 2026, SoC Labs (www.soclabs.org)

`verif/g2_peer_aperture` proved the LINK carries a translated transaction, with
an AHB master model standing in for CPU0 and an `ahb_probe_mem` standing in for
the far die. This runs the same experiment end to end between two REAL
`nanosoc_eth_chiplet` dies:

    die A eth_ss_0 (external master)
      -> die A SoC matrix -> d2d_ahb_m -> chiplet_d2d_decode (hsel_peer)
      -> die A tidelink ahb_sub  (0x2F aperture)
      == CAM rewrites addr[31:24] 0x2F -> 0x2D ==
      -> PHY pads -> die B tidelink ahb_mng
      -> die B d2d_ahb_s -> die B SoC matrix -> die B shared_sram_0  (0x2D......)

Everything is firmware-free: both dies' CPU0 are boot-gated secondaries never
released; both CPU1 halt on the unprogrammed flash. Every stimulus is an
EXTERNAL master on each die's `eth_ss_0`, which reaches the 0x2E/0x2F D2D window
(and shared SRAM at 0x2D......) through the eth-subsystem `system` passthrough,
exactly as `soc_d2d_loopback` does.

The link is brought up entirely over each die's own `eth_ss_0`: an AHB write to
0x2E03_xxxx lands, through the chiplet decode's tlapb bridge, as a TideLink APB
write. So the bring-up sequence from `test_peer_aperture` (role-lock, cal_done,
LL bootstrap, CAM) is issued here as AHB writes to 0x2E03_xxxx rather than to a
directly-exposed APB port.

Two tests:
  * test_smoke_eth_ss0_reaches_sram  — fast. Proves the harness: an eth_ss_0
    write into a die's OWN shared_sram_0 (0x2D......, inside the passthrough)
    reads back. No link involved.
  * test_peer_write_crosses_to_die_b — the full G2 experiment. Slow: a full
    two-SoC link bring-up. See RUNTIME below.

RUNTIME. `test_peer_aperture` records ~6 min wall-clock per bring-up for the raw
TideLink pair; here each die is a whole `nanosoc_multicore_soc`, so a single
bring-up is substantially longer. The test carries a heartbeat (a frozen
heartbeat while the process burns CPU means a zero-delay loop, which sim-time
timeouts cannot catch) and a generous sim-time timeout.
"""
import os

import cocotb
from cocotb.handle import Force, Release
from cocotb.triggers import ClockCycles, RisingEdge
from cocotb.utils import get_sim_time
from cocotbext.ahb import AHBBus, AHBLiteMaster

# The MAC wishbone slave drives X on hrdata during unrelated APB writes; ZEROS
# resolution matches soc_d2d_loopback and masks nothing this env asserts on.
os.environ.setdefault("COCOTB_RESOLVE_X", "ZEROS")

# --- Addresses -------------------------------------------------------------
SHARED_SRAM   = 0x2D00_0000        # inbound D2D + local passthrough both reach it
PEER_APERTURE = 0x2F00_0000        # die A tidelink ahb_sub (address-translated)

# TideLink APB, reached through the chiplet decode's tlapb bridge at 0x2E03_0000.
# The bridge passes haddr[14:0] to the APB, so AHB 0x2E03_0000|off -> APB paddr off.
TLAPB_BASE               = 0x2E03_0000
APB_WL_LINK_ENABLE_RESET = TLAPB_BASE + 0x0208
APB_ROLE_CFG             = TLAPB_BASE + 0x2080   # NOT 0x2084 (REGISTER_MAP.md:164)
APB_R8_SLOT0             = TLAPB_BASE + 0x2100
APB_R8_SWI_LANE_STATUS   = TLAPB_BASE + 0x2108   # bit[16] = cal_done
CAM_BASE_OFFSET          = TLAPB_BASE + 0x4000
CAM_CTRL                 = TLAPB_BASE + 0x4004   # bit[0] = global_enable
CAM_RULE_0               = TLAPB_BASE + 0x4010   # [0]=en [15:8]=match [23:16]=replace

ROLE_CFG_MASTER_LOCK = 0x02
ROLE_CFG_SLAVE_LOCK  = 0x03

# Wlink flow-control state machine: 4 == LINK_IDLE == "the link is actually up".
# cr/crack packets prove the M->S link LAYER is exchanging, but the FCSM can sit
# short of LINK_IDLE with cr/crack already seen — so cr/crack alone is NOT
# sufficient evidence the data plane will open. That gap let the heterogeneous
# pair's F6 stall hide behind a green run here; see the het-testing repo's
# docs/F6_ATTRIBUTION.md. Assert on the FCSM as well.
FCSM_LINK_IDLE = 4

# 3-write LL bootstrap; order matters (swreset first clears CR/CRACK sticky).
LL_SWRESET_ON  = 0x00027F08
LL_SWRESET_OFF = 0x00027F00
LL_ENABLE      = 0x00027F07

# The mapping under test: die A's 0x2F aperture -> die B's 0x2D (shared_sram_0).
APERTURE_BYTE = 0x2F
REMOTE_BYTE   = 0x2D
RULE_0_VALUE  = (REMOTE_BYTE << 16) | (APERTURE_BYTE << 8) | 1   # 0x002D2F01

PEER_ADDR  = (APERTURE_BYTE << 24) | 0x001000   # 0x2F001000  (die A writes)
LANDED_ADDR= (REMOTE_BYTE   << 24) | 0x001000   # 0x2D001000  (die B shared SRAM)
PAYLOAD    = 0xC0FFEE01


async def _heartbeat(dut, every=2000):
    while True:
        await ClockCycles(dut.sys_fclk, every)
        dut._log.info(f"heartbeat: t={get_sim_time('us'):.1f} us")


def _rd(resp):
    """cocotbext-ahb returns [{'resp':…, 'data':'0x…'}]."""
    return int(resp[0]["data"], 16)


class Die:
    """One die: an AHB master on its eth_ss_0 port + its status/observation nets."""

    def __init__(self, dut, tag):
        self.dut = dut
        self.tag = tag                       # "a" or "b"
        self.log = dut._log
        bus = AHBBus.from_prefix(dut, f"{tag}_eth_ss_0")
        rstn = getattr(dut, f"{tag}_sysresetn")
        self.ahb = AHBLiteMaster(bus, dut.sys_fclk, rstn, timeout=50000)

    def sig(self, name):
        return getattr(self.dut, f"{self.tag}_{name}")

    async def write(self, addr, data):
        # cocotbext-ahb 0.x takes an int value; size defaults to the bus width.
        await self.ahb.write(addr, data)

    async def read(self, addr):
        return _rd(await self.ahb.read(addr))

    async def apb_write(self, addr, data):
        await self.write(addr, data)

    async def apb_read(self, addr):
        return await self.read(addr)


class Pair:
    def __init__(self, dut):
        self.dut = dut
        self.log = dut._log
        self.a = Die(dut, "a")
        self.b = Die(dut, "b")
        cocotb.start_soon(_heartbeat(dut))

    # --- reset + the calibrator sim bypass ---------------------------------
    def _calibrator_sim_bypass(self):
        """Without this, both calibrators sit in S_VALIDATE for ~2M link cycles and
        `cal_done` never asserts in any sane sim budget. Apply before role_locked."""
        for die in ("u_dieA", "u_dieB"):
            try:
                getattr(self.dut, die).u_tidelink.u_chiplet_controller \
                    .u_calibrator.tb_early_exit_force_q.value = 1
            except AttributeError:
                self.log.warning(f"{die}: tb_early_exit_force_q missing — bypass NOT applied")

    async def reset(self):
        self.dut.a_sysresetn.value = 0
        self.dut.b_sysresetn.value = 0
        self.dut.a_pad_en.value = 1
        self.dut.b_pad_en.value = 1
        await ClockCycles(self.dut.sys_fclk, 20)
        self._calibrator_sim_bypass()
        self.dut.a_sysresetn.value = 1
        self.dut.b_sysresetn.value = 1
        # Let each SoC's reset controller lift internal resets and each CPU1
        # stage-0 reach its flash-magic halt so the bus is quiet.
        await ClockCycles(self.dut.sys_fclk, 4000)

    # --- link bring-up, issued as AHB writes to each die's 0x2E03_xxxx -----
    async def role_lock(self):
        await self.a.apb_write(APB_ROLE_CFG, ROLE_CFG_MASTER_LOCK)
        await self.b.apb_write(APB_ROLE_CFG, ROLE_CFG_SLAVE_LOCK)
        for _ in range(400):
            if int(self.dut.a_role_locked_o.value) and int(self.dut.b_role_locked_o.value):
                return
            await ClockCycles(self.dut.sys_fclk, 50)
        raise TimeoutError("role_locked never asserted on both dies")

    async def wait_cal_done(self):
        for _ in range(100):
            m = await self.a.apb_read(APB_R8_SWI_LANE_STATUS)
            s = await self.b.apb_read(APB_R8_SWI_LANE_STATUS)
            if ((m >> 16) & 1) and ((s >> 16) & 1):
                return
            await ClockCycles(self.dut.sys_fclk, 100)
        raise TimeoutError("cal_done never asserted on both dies within budget")

    async def to_data_mode(self):
        await self.a.apb_write(APB_R8_SLOT0, 0)
        await self.b.apb_write(APB_R8_SLOT0, 0)
        await ClockCycles(self.dut.sys_fclk, 20)
        for val in (LL_SWRESET_ON, LL_SWRESET_OFF, LL_ENABLE):
            await self.a.apb_write(APB_WL_LINK_ENABLE_RESET, val)
            await self.b.apb_write(APB_WL_LINK_ENABLE_RESET, val)
            await ClockCycles(self.dut.sys_fclk, 20)
        await ClockCycles(self.dut.sys_fclk, 5000)   # CR/CRACK exchange

    async def program_cam(self, enable=True):
        """CTRL armed last so a half-configured rule is never live."""
        await self.a.apb_write(CAM_BASE_OFFSET, 0x00000000)
        await self.a.apb_write(CAM_RULE_0, RULE_0_VALUE)
        await self.a.apb_write(CAM_CTRL, 1 if enable else 0)

    async def bring_up(self):
        await self.reset()
        await self.role_lock()
        await self.wait_cal_done()
        await self.to_data_mode()

    def link_carries_m2s(self):
        """Slave has seen the master's CR and CRACK packets — evidence the M->S
        link layer is live. `link_active` alone is just role_locked_o."""
        f = self.dut.u_dieB.u_tidelink.u_chiplet_controller.u_wlink.tl2wl.wlink_tidelinktl
        return int(f.cr_pkt_seen_rx.value) and int(f.crack_pkt_seen_rx.value)

    def _fcsm(self, die):
        return getattr(self.dut, f"u_die{die}").u_tidelink.u_chiplet_controller \
            .u_wlink.tl2wl.wlink_tidelinktl

    def fcsm_state(self, die):
        """Wlink FCSM state on one die. -1 if unresolvable (X at this instant)."""
        v = self._fcsm(die).state.value
        return int(v) if v.is_resolvable else -1

    def link_is_up(self):
        """BOTH dies at LINK_IDLE — the condition the data plane actually needs.

        Strictly stronger than link_carries_m2s(): the autonomous-negotiation
        posture reaches cr/crack and cal_done on both dies and still parks the
        FCSM short of LINK_IDLE, so the peer aperture never opens. Measured on
        this very testbench: manual posture -> 4/4; autoneg -> 1/1."""
        return (self.fcsm_state("A") == FCSM_LINK_IDLE
                and self.fcsm_state("B") == FCSM_LINK_IDLE)

    def observe_inbound(self):
        """The address die B's inbound D2D port (its ahb_mng) is presenting — read
        hierarchically so we can see the CAM's translated byte even before it
        retires into SRAM."""
        return int(self.dut.u_dieB.d2d_ahb_s_haddr.value)

    async def trace_peer_write(self):
        """Cycle-by-cycle trace of die A's ahb_sub/XHB500 capture once the peer
        write starts, to pin the address-pipeline vs live-hwdata skew."""
        w = self.dut.u_dieA
        t = self.dut.u_dieA.u_tidelink
        def g(o, sig):
            v = getattr(o, sig).value
            return ('0x%08x' % int(v)) if v.is_resolvable else 'x'
        def g1(o, sig):
            v = getattr(o, sig).value
            return str(int(v)) if v.is_resolvable else 'x'
        # wait for the first peer write address phase
        while True:
            await RisingEdge(self.dut.sys_fclk)
            hs = w.hsel_peer.value
            ht = w.d2d_ahb_m_htrans.value
            if hs.is_resolvable and int(hs) and ht.is_resolvable and (int(ht) & 0b10) \
               and w.d2d_ahb_m_hwrite.value.is_resolvable and int(w.d2d_ahb_m_hwrite.value):
                break
        for i in range(9):
            self.dut._log.info(
                'TRACE +%d  m_hwr=%s m_hwdata=%s m_hready=%s selp=%s | tl: sub_hwdata=%s sub_hready=%s sub_hrdyout=%s pipe_v=%s awv=%s awr=%s wv=%s wr=%s s_wdata=%s'
                % (i, g1(w,'d2d_ahb_m_hwrite'), g(w,'d2d_ahb_m_hwdata'), g1(w,'d2d_ahb_m_hready'), g1(w,'hsel_peer'),
                   g(t,'ahb_sub_hwdata'), g1(t,'ahb_sub_hready'), g1(t,'ahb_sub_hreadyout'), g1(t,'pipe_valid_r'),
                   g1(t,'s_axi_awvalid'), g1(t,'s_axi_awready'), g1(t,'s_axi_wvalid'), g1(t,'s_axi_wready'), g(t,'s_axi_wdata')))
            await RisingEdge(self.dut.sys_fclk)

    async def catch_inbound_writes(self):
        """Record every write beat die B's inbound D2D port (ahb_mng -> d2d_ahb_s)
        actually retires: capture the address in its address phase (htrans[1] &
        hwrite & hready) and the data on the completing cycle (hready high). Lets
        us see whether the PAYLOAD crossed the link, and whether the far SoC
        accepted the write (hready) or erred (hresp)."""
        s = self.dut.u_dieB
        self.inbound_writes = []
        pend = None
        while True:
            await RisingEdge(self.dut.sys_fclk)
            def rd(sig):
                v = getattr(s, sig).value
                return int(v) if v.is_resolvable else None
            htrans = rd("d2d_ahb_s_htrans"); hready = rd("d2d_ahb_s_hready")
            hwrite = rd("d2d_ahb_s_hwrite"); haddr = rd("d2d_ahb_s_haddr")
            if pend is not None and hready:
                self.inbound_writes.append((pend, rd("d2d_ahb_s_hwdata"),
                                            rd("d2d_ahb_s_hresp"),
                                            str(s.d2d_ahb_s_hwdata.value.binstr)))
                pend = None
            if htrans and (htrans & 0b10) and hwrite and hready:
                pend = haddr

    async def catch_outbound_writes(self):
        """Same, on die A's OUTBOUND d2d_ahb_m (SoC -> decode -> tidelink ahb_sub).
        Localises where the payload is lost: if it is correct here but 0 at die B
        inbound, the loss is in the link; if 0 here, in die A's SoC/aperture path."""
        s = self.dut.u_dieA
        self.outbound_writes = []
        pend = None
        while True:
            await RisingEdge(self.dut.sys_fclk)
            def rd(sig):
                v = getattr(s, sig).value
                return int(v) if v.is_resolvable else None
            htrans = rd("d2d_ahb_m_htrans"); hready = rd("d2d_ahb_m_hready")
            hwrite = rd("d2d_ahb_m_hwrite"); haddr = rd("d2d_ahb_m_haddr")
            selp   = rd("hsel_peer")
            if pend is not None and hready:
                self.outbound_writes.append((pend, rd("d2d_ahb_m_hwdata"),
                                             str(s.d2d_ahb_m_hwdata.value.binstr)))
                pend = None
            if htrans and (htrans & 0b10) and hwrite and hready and selp:
                pend = haddr

    # =======================================================================
    # Silicon "peer-write data-phase drop" reproduction (Rank 2 regression).
    #
    # On silicon a cross-die peer write dropped its DATA (die B read 0). Root
    # cause: die A's TideLink `ahb_sub` XHB500 bridge samples the AHB write data
    # LIVE on its AXI W beat (u_xhb_sub .hwdata(ahb_sub_hwdata),
    # tidelink_top.sv:2357), while the address is pipelined one cycle. The bridge
    # posts the AHB beat (ahb_sub_hreadyout high, gated by wdata_2_empty which is
    # hardwired 1 — NOT by the st1 skid fullness), so the SoC completes and
    # RELEASES hwdata even while a *following* W beat's data has not yet been
    # captured. When the AXI W ingress backpressures (link CDC / credit /
    # outstanding writes), the W-data capture slips past the one cycle the SoC
    # held the payload; the fragile 1-cycle-delay fix aligned ONLY that one cycle,
    # so it captured 0. The Rank 2 fix (src/rtl/nanosoc_eth_chiplet.sv ~281:
    # peer_wr_dph_r + load-and-HOLD of d2d_ahb_m_hwdata_q) holds the payload on
    # ahb_sub_hwdata across any W backpressure depth.
    #
    # The idle sim link holds s_axi_wready high every cycle, so the W beat always
    # lands at +2 and the drop never reproduced (both fixes looked fine). These
    # helpers inject the missing backpressure so the regression is real.
    # =======================================================================
    def _dieA_tl(self):
        return self.dut.u_dieA.u_tidelink

    def w_backpressure(self, on):
        """Force die A's TideLink AXI target W-ready (into u_xhb_sub) LOW/RELEASE.
        This is the datanode target face `axi_tgt_0_w_ready` == `s_axi_wready`
        (tidelink_top.sv:2396,2758). DIAGNOSTIC ONLY: forcing this Wlink *output*
        decouples Wlink's internal W-accept from the wire, which corrupts the link
        transport (the payload is dropped downstream even when the bridge delivered
        it correctly). See test EXP A. The faithful injection is the bridge-side
        capture skew below."""
        wr = self._dieA_tl().s_axi_wready
        wr.value = Force(0) if on else Release()

    def fragile_pin(self, on):
        """Emulate the OLD fragile 1-cycle-delay fix BIT-EXACTLY, without editing
        the committed RTL. The ONLY node that differs between the fragile and the
        Rank 2 RTL is `d2d_ahb_m_hwdata_q` (== ahb_sub_hwdata). The fragile fix put
        the payload on it for exactly ONE cycle (the data phase) then reverted to 0
        (it was the raw SoC hwdata delayed one cycle, and the SoC releases hwdata
        after its single data-phase beat). Pinning this net to 0 after that one
        cycle makes the sim behave exactly as if compiled with the fragile RTL."""
        q = self.dut.u_dieA.d2d_ahb_m_hwdata_q
        q.value = Force(0) if on else Release()

    async def _wait_peer_wr_addr(self, target_addr):
        """Block until the peer-WRITE address phase for target_addr appears on die
        A's outbound d2d_ahb_m. Returns on the address-phase cycle T."""
        w = self.dut.u_dieA
        while True:
            await RisingEdge(self.dut.sys_fclk)
            selp = w.hsel_peer.value
            ht = w.d2d_ahb_m_htrans.value
            hw = w.d2d_ahb_m_hwrite.value
            hr = w.d2d_ahb_m_hready.value
            ha = w.d2d_ahb_m_haddr.value
            if (selp.is_resolvable and int(selp)
                    and ht.is_resolvable and (int(ht) & 0b10)
                    and hw.is_resolvable and int(hw)
                    and hr.is_resolvable and int(hr)
                    and ha.is_resolvable and int(ha) == target_addr):
                return

    async def rich_trace(self, n=40):
        """Cycle-by-cycle view of die A's outbound hwdata, the Rank 2 held value on
        ahb_sub_hwdata (q), the AXI W beat, and the XHB500 slv bridge's own capture
        signals — so we can SEE the W beat slip and where the payload is sampled."""
        w = self.dut.u_dieA
        t = self._dieA_tl()
        try:
            wd = t.u_xhb_sub.u_core.u_wdata
        except Exception:
            wd = None
        try:
            st1 = wd.u_wdata_st1_regslice
        except Exception:
            st1 = None

        def gh(o, sig):
            try:
                v = getattr(o, sig).value
                return ('%08x' % int(v)) if v.is_resolvable else 'xxxxxxxx'
            except Exception:
                return '????????'

        def g1(o, sig):
            try:
                v = getattr(o, sig).value
                return str(int(v)) if v.is_resolvable else 'x'
            except Exception:
                return '?'

        for i in range(n):
            bfull = '?'
            if st1 is not None:
                try:
                    bv = st1.buffer_full.value
                    bfull = ('%x' % int(bv)) if bv.is_resolvable else 'x'
                except Exception:
                    bfull = '?'
            self.dut._log.info(
                'RTRACE +%02d haddr=%s selp=%s ht=%s hrdy=%s | m_hwdata=%s q(sub)=%s s_wdata=%s | '
                'awv=%s awr=%s wv=%s wr=%s | wd_valid=%s in_valid=%s in_ready=%s stall=%s bfull=%s hrdyout=%s'
                % (i, gh(w, 'd2d_ahb_m_haddr'), g1(w, 'hsel_peer'), g1(w, 'd2d_ahb_m_htrans'),
                   g1(w, 'd2d_ahb_m_hready'),
                   gh(w, 'd2d_ahb_m_hwdata'), gh(w, 'd2d_ahb_m_hwdata_q'), gh(t, 's_axi_wdata'),
                   g1(t, 's_axi_awvalid'), g1(t, 's_axi_awready'), g1(t, 's_axi_wvalid'), g1(t, 's_axi_wready'),
                   g1(wd, 'write_data_valid') if wd is not None else '?', g1(wd, 'wdata_in_valid') if wd is not None else '?',
                   g1(wd, 'wdata_in_ready') if wd is not None else '?', g1(wd, 'stall_writes') if wd is not None else '?',
                   bfull, g1(t, 'ahb_sub_hreadyout')))
            await RisingEdge(self.dut.sys_fclk)

    async def peer_write_crosses(self, paddr, landed, pdata, pin_zero=False):
        """End-to-end peer write into die B's real shared_sram_0 through the whole
        two-SoC link. With pin_zero, ahb_sub_hwdata (== d2d_ahb_m_hwdata_q) is pinned
        to 0 across the write — a bit-exact emulation of the ORIGINAL no-fix RTL
        (which sampled the released, 0 hwdata) — so die B receives the dropped 0.
        No W-ready force here, so the link is not perturbed. Returns die B's SRAM."""
        if pin_zero:
            wtask = cocotb.start_soon(self.a.write(paddr, pdata))
            await self._wait_peer_wr_addr(paddr)             # T
            self.fragile_pin(True)                            # ahb_sub_hwdata -> 0 (original drop)
            await ClockCycles(self.dut.sys_fclk, 8)          # cover data phase + bridge capture
            self.fragile_pin(False)
            try:
                await wtask
            except Exception:
                pass
        else:
            await self.a.write(paddr, pdata)
        await ClockCycles(self.dut.sys_fclk, 400)
        got = await self.b.read(landed)
        self.log.info(f"CROSS: die A 0x{paddr:08x} -> die B 0x{landed:08x} = 0x{got:08x} "
                      f"(pin_zero={pin_zero})")
        return got

    async def wbp_slip_check(self, paddr, pdata, depth):
        """Issue a peer write and force die A's TideLink AXI W-ready LOW for `depth`
        cycles from the payload's data phase, so the W beat is genuinely BACKPRESSURED
        and SLIPS (RTRACE shows wv=1 while wr=0). Record (wvalid, wready, s_axi_wdata)
        each cycle of the window, plus s_axi_wdata on the cycle the W beat finally
        completes after release. The fix's job is to keep the payload on the AXI W
        data across the whole slip so the delayed W beat still carries it.

        die B is NOT read here: force-overriding Wlink's own wready OUTPUT corrupts
        the link transport (payload leaves the bridge correct on s_axi_wdata yet die B
        reads 0), so the end-to-end crossing is checked separately by
        peer_write_crosses() with no force. This experiment must therefore run LAST."""
        t = self._dieA_tl()
        self.log.info(f"WBP-SLIP paddr=0x{paddr:08x} depth={depth}")
        cocotb.start_soon(self.rich_trace(depth + 16))
        wtask = cocotb.start_soon(self.a.write(paddr, pdata))
        await self._wait_peer_wr_addr(paddr)                 # T (address phase)
        await RisingEdge(self.dut.sys_fclk)                 # T+1 (SoC data phase; SoC releases)
        self.w_backpressure(True)                            # force wr=0 now, stable before the T+2 W beat
        await RisingEdge(self.dut.sys_fclk)                 # T+2 (bridge presents W: payload on s_wdata)

        def _i(sig):
            v = getattr(t, sig).value
            return int(v) if v.is_resolvable else -1

        recs = []            # (wvalid, wready, s_axi_wdata) each window cycle
        for _ in range(depth):
            recs.append((_i('s_axi_wvalid'), _i('s_axi_wready'), _i('s_axi_wdata')))
            await RisingEdge(self.dut.sys_fclk)
        self.w_backpressure(False)                           # release: W beat may complete now
        fire_wdata = None
        for _ in range(24):
            if _i('s_axi_wvalid') == 1 and _i('s_axi_wready') == 1:
                fire_wdata = _i('s_axi_wdata')
                break
            await RisingEdge(self.dut.sys_fclk)
        try:
            await wtask
        except Exception:
            pass
        await ClockCycles(self.dut.sys_fclk, 60)
        slipped = any(wv == 1 and wr == 0 for (wv, wr, _sd) in recs)
        held = [sd for (wv, wr, sd) in recs if wv == 1]
        self.log.info(f"WBP-SLIP recs(wv,wr,wdata)={[(wv, wr, hex(sd) if sd >= 0 else 'x') for (wv, wr, sd) in recs]}")
        self.log.info(f"WBP-SLIP slipped={slipped} wdata_while_slipped={[hex(s) for s in held]} "
                      f"fire_wdata={hex(fire_wdata) if fire_wdata is not None else None}")
        return {"slipped": slipped, "held": held, "fire_wdata": fire_wdata}


# ===========================================================================
# Fast harness smoke test — no link. Proves eth_ss_0 -> SoC matrix -> SRAM.
# ===========================================================================
@cocotb.test(timeout_time=3, timeout_unit="ms")
async def test_smoke_eth_ss0_reaches_sram(dut):
    tb = Pair(dut)
    await tb.reset()

    # Die A writes and reads back its OWN shared_sram_0 through eth_ss_0.
    await tb.a.write(SHARED_SRAM + 0x40, 0xA5A50001)
    got = await tb.a.read(SHARED_SRAM + 0x40)
    assert got == 0xA5A50001, f"die A shared SRAM read-back 0x{got:08x} != 0xA5A50001"

    # Die B likewise, independently.
    await tb.b.write(SHARED_SRAM + 0x80, 0x5A5A0002)
    got = await tb.b.read(SHARED_SRAM + 0x80)
    assert got == 0x5A5A0002, f"die B shared SRAM read-back 0x{got:08x} != 0x5A5A0002"

    dut._log.info("SMOKE ok: both dies' eth_ss_0 masters reach their own shared_sram_0")


# ===========================================================================
# Full G2 — a peer write on die A lands in die B's real shared_sram_0. Staged in
# ONE test (a second bring-up in the same sim does not re-converge cal_done).
# ===========================================================================
@cocotb.test(timeout_time=60, timeout_unit="ms")
async def test_peer_write_crosses_to_die_b(dut):
    tb = Pair(dut)

    # -- Stage 1: the link. --------------------------------------------------
    await tb.bring_up()
    assert tb.link_carries_m2s(), "M->S link layer never came up (cr/crack not seen on die B)."
    a_st, b_st = tb.fcsm_state("A"), tb.fcsm_state("B")
    assert tb.link_is_up(), (
        f"Wlink FCSM did not reach LINK_IDLE ({FCSM_LINK_IDLE}): die A={a_st} die B={b_st}. "
        "cr/crack were seen, so the link LAYER is exchanging — but the FCSM is short "
        "of LINK_IDLE and the peer aperture will not open. Do not treat cr/crack as "
        "proof the link is up.")
    dut._log.info(f"STAGE 1 ok: link up (cal_done both dies; cr+crack on die B; "
                  f"FCSM A={a_st} B={b_st} = LINK_IDLE)")

    # -- Stage 2: CAM on, peer write, observe die B's inbound + SRAM. --------
    cocotb.start_soon(tb.catch_inbound_writes())
    cocotb.start_soon(tb.catch_outbound_writes())
    cocotb.start_soon(tb.trace_peer_write())
    await tb.program_cam(enable=True)
    await tb.a.write(PEER_ADDR, PAYLOAD)
    await ClockCycles(dut.sys_fclk, 4000)

    inbound = tb.observe_inbound()
    def _fmt(lst):
        return [tuple(hex(x) if isinstance(x, int) else x for x in row) for row in lst]
    dut._log.info(f"DIAG die A OUTBOUND d2d_ahb_m peer writes = {_fmt(getattr(tb, 'outbound_writes', []))}")
    dut._log.info(f"DIAG die B INBOUND d2d_ahb_s write beats  = {_fmt(getattr(tb, 'inbound_writes', []))}  (inbound-haddr now=0x{inbound:08x})")
    assert (inbound >> 24) == REMOTE_BYTE, (
        f"die B inbound saw 0x{inbound:08x}; expected upper byte 0x{REMOTE_BYTE:02x} "
        "(CAM should have rewritten 0x2F->0x2D)"
    )

    # KNOWN GAP (see docs/G2_SOC_PAIR_STATUS.md "Milestone 2 finding"). With two
    # real SoCs the ADDRESS crosses (asserted above: die B inbound sees 0x2D....,
    # CAM-translated) but the write DATA arrives as 0: the diagnostics above show
    # 0xC0FFEE01 leaving die A on d2d_ahb_m yet 0x0 at die B's inbound port. The
    # payload is dropped in the link's peer-write data phase — the "ships the
    # payload as zero" case test_peer_aperture warns of, which that env's
    # hand-timed ahb_sub master (holding hwdata across the whole data phase) masks
    # and a real SoC's d2d_ahb_m (which releases hwdata as soon as the forced
    # hready_to_peer completes the beat) exposes.
    got = await tb.b.read(LANDED_ADDR)
    assert got == PAYLOAD, (
        f"die B shared_sram_0[0x{LANDED_ADDR:08x}] = 0x{got:08x}, expected 0x{PAYLOAD:08x}. "
        "ADDRESS crossed (die B inbound = 0x2D...., CAM ok) but DATA did not: "
        "0xC0FFEE01 leaves die A on d2d_ahb_m, arrives 0x0 at die B inbound. "
        "Peer-write data-phase drop — see docs/G2_SOC_PAIR_STATUS.md."
    )
    dut._log.info(f"STAGE 2 ok: die A 0x{PEER_ADDR:08x} -> die B shared_sram_0 0x{LANDED_ADDR:08x} "
                  f"= 0x{got:08x}")

    # -- Stage 2b: the READ round-trip. die A reads the peer aperture; the data
    # must return over the link from die B's real shared_sram_0. Stage 2 proved
    # the write reached die B; this proves the read path — request out, data back
    # — through two real SoCs. CAM still enabled, so 0x2F.... -> 0x2D.....
    # (The TideLink ahb_sub read pipe-offset that made this return 0 is fixed by
    # the src/rtl/local_overrides/tidelink_top.sv override; see G2_SOC_PAIR_STATUS.md.)
    rb = await tb.a.read(PEER_ADDR)
    assert rb == PAYLOAD, (
        f"peer read-back 0x{PEER_ADDR:08x} returned 0x{rb:08x}, expected 0x{PAYLOAD:08x} "
        f"— read round-trip did not carry the data.")
    dut._log.info(f"STAGE 2b ok: die A read 0x{PEER_ADDR:08x} -> 0x{rb:08x} (link round-trip)")

    # -- Stage 2c: a multi-word SEQUENCE — hardens the write + read fixes across
    # consecutive beats (what a memcpy across the aperture does). The single-beat
    # stages above cannot catch an off-by-one BETWEEN beats: a write-data delay
    # that mis-aligned beat N with beat N+1, or a read pipe-offset mask that failed
    # to re-arm between reads, would corrupt a sequence while a lone access passes.
    # CAM still enabled. Distinct values so a cross-beat swap is visible.
    seq = [(PEER_ADDR + 4 * i, 0x5EED0000 + (i << 4) + i) for i in range(8)]
    for addr, val in seq:
        await tb.a.write(addr, val)
    await ClockCycles(dut.sys_fclk, 4000)  # let the last writes drain over the link
    for addr, val in seq:
        rb = await tb.a.read(addr)
        assert rb == val, (
            f"burst mismatch at 0x{addr:08x}: read 0x{rb:08x}, wrote 0x{val:08x} "
            f"— a consecutive-beat write or read corrupted the sequence.")
    dut._log.info(f"STAGE 2c ok: {len(seq)}-word write+read sequence across the aperture, "
                  f"all beats intact")

    # -- Stage 3: the control. CAM off => address arrives UNtranslated. ------
    await tb.a.apb_write(CAM_CTRL, 0)
    await tb.a.write(PEER_ADDR ^ 0x40, PAYLOAD ^ 0xFFFF)
    await ClockCycles(dut.sys_fclk, 4000)
    inbound = tb.observe_inbound()
    assert (inbound >> 24) == APERTURE_BYTE, (
        f"with the CAM disabled die B inbound saw 0x{inbound:08x}; expected an identity "
        f"map (upper byte 0x{APERTURE_BYTE:02x}). Stage 2's 0x2D did not come from the CAM."
    )
    dut._log.info(f"STAGE 3 ok: CAM disabled -> die B inbound 0x{inbound:08x} (identity)")


# ===========================================================================
# Rank 2 regression: a cross-die peer write survives AXI W-channel backpressure.
#
# WHAT THIS SIM CAN AND CANNOT DO (all verified by RTRACE; see the agent report):
#
#   * The idle sim link holds s_axi_wready high, so the XHB500 W beat always lands
#     one cycle after AW — the test was BLIND to any W-timing hazard.
#   * The sim's skew from the SoC data phase (T+1) to the bridge's posted W-data
#     capture (T+2) is EXACTLY one cycle. The ORIGINAL no-fix RTL sampled the
#     released (0) hwdata and dropped the payload (die B read 0); both the fragile
#     1-cycle-delay fix and the committed Rank 2 fix present the payload at T+2 and
#     the W captures it there.
#   * MEASURED (test_diag_q_hold, no force): the committed Rank 2 fix holds
#     ahb_sub_hwdata (== d2d_ahb_m_hwdata_q) at the payload for EXACTLY ONE cycle
#     (T+2), then it drops to 0 at T+3 — byte-identical to the fragile fix. So in
#     THIS sim the two fixes are indistinguishable and a "catches a revert to
#     fragile" regression is not achievable; that distinction needs the wider skew
#     of the real Wlink AXI CDC/credit path the sim abstracts.
#   * You cannot widen the skew end-to-end from any AXI/bridge signal: the SoC
#     completion (ahb_sub_hreadyout) and the W-data capture (wdata_in_valid) are both
#     combinationally gated by stall_writes, so deferring the capture also stalls the
#     SoC (which then HOLDS hwdata — a wait state the fragile fix survives); and
#     force-overriding Wlink's own s_axi_wready OUTPUT corrupts the link transport.
#
# So this regression injects the backpressure the sim CAN express and asserts the
# strongest thing it supports with teeth against the ORIGINAL drop:
#
#   * X-CHK    a clean peer write (no force) crosses to die B's real shared_sram_0.
#              Non-vacuous vs the original bug: the no-fix RTL makes this read 0.
#   * WBP-SLIP hold die A's s_axi_wready low so the W beat genuinely SLIPS (wv=1,
#              wr=0 for the window); assert s_axi_wdata carries the payload on every
#              slipped cycle AND on the cycle the W beat finally completes after
#              release. Proves the fix keeps the payload on the backpressured AXI W
#              channel — the idle-link test never exercised this.
#   * NOFIX    the SAME WBP-SLIP with ahb_sub_hwdata pinned to 0 (bit-exact emulation
#              of the original undelayed RTL): the WBP-SLIP check FAILS (s_axi_wdata
#              is 0), proving the check is non-vacuous.
#
# Run:  make -C verif/g2_soc_pair sim TESTCASE=test_peer_write_survives_w_backpressure
# Tune: WBP_DEFER=<cycles> (default 6) = W-ready-low window depth (W-beat slip).
# ===========================================================================
@cocotb.test(timeout_time=60, timeout_unit="ms")
async def test_peer_write_survives_w_backpressure(dut):
    tb = Pair(dut)
    depth = int(os.environ.get("WBP_DEFER", "6"))

    # -- Stage 1: the link (same bring-up as the crossing test). --------------
    await tb.bring_up()
    assert tb.link_is_up(), (
        f"Wlink FCSM did not reach LINK_IDLE: die A={tb.fcsm_state('A')} "
        f"die B={tb.fcsm_state('B')}.")
    dut._log.info("STAGE 1 ok: link up on both dies")

    await tb.program_cam(enable=True)
    cocotb.start_soon(tb.catch_inbound_writes())

    X_PEER, X_LAND, X_PAY = PEER_ADDR + 0x00, LANDED_ADDR + 0x00, 0xC0FFEE01
    N_PEER, N_LAND, N_PAY = PEER_ADDR + 0x40, LANDED_ADDR + 0x40, 0xC0FFEE02
    B_PEER, B_PAY         = PEER_ADDR + 0x80, 0xC0FFEE03

    # -- X-CHK: clean end-to-end crossing (no force) — the payload reaches die B. -
    dut._log.info("==== X-CHK: clean peer write crosses to die B (no injection) ====")
    got_x = await tb.peer_write_crosses(X_PEER, X_LAND, X_PAY)

    # -- NOFIX: SAME path but ahb_sub_hwdata pinned to 0 (original no-fix drop) —
    #    reproduces the silicon symptom end-to-end and proves X-CHK is non-vacuous.
    #    No W-ready force here, so the link stays clean for both reads. -----------
    dut._log.info("==== NOFIX: original-drop emulation (ahb_sub_hwdata pinned 0) ====")
    got_n = await tb.peer_write_crosses(N_PEER, N_LAND, N_PAY, pin_zero=True)

    # -- WBP-SLIP: force the W beat to slip; payload must ride s_axi_wdata through
    #    the backpressure. Runs LAST (the wready force perturbs the link). --------
    dut._log.info("==== WBP-SLIP: W beat backpressured; payload must ride s_axi_wdata ====")
    r = await tb.wbp_slip_check(B_PEER, B_PAY, depth=depth)

    dut._log.info("======================= SUMMARY =======================")
    dut._log.info(f"X-CHK  clean crossing        : die B = 0x{got_x:08x}  (expect 0x{X_PAY:08x})")
    dut._log.info(f"NOFIX  original-drop emulation: die B = 0x{got_n:08x}  (expect 0x00000000)")
    dut._log.info(f"WBP-SLIP slipped={r['slipped']} wdata_held={[hex(s) for s in r['held']]} "
                  f"fire_wdata={hex(r['fire_wdata']) if r['fire_wdata'] is not None else None}")
    dut._log.info("=======================================================")

    # X-CHK: the fix delivers the payload end-to-end into die B's real SRAM.
    assert got_x == X_PAY, (
        f"clean peer write did not cross: die B[0x{X_LAND:08x}] = 0x{got_x:08x}, "
        f"expected 0x{X_PAY:08x}.")

    # NOFIX non-vacuity: with ahb_sub_hwdata pinned to 0 (original no-fix behaviour)
    # the SAME crossing drops the payload — proving X-CHK catches the real bug.
    assert got_n == 0x00000000, (
        f"NON-VACUITY FAILED: original-drop emulation still delivered die B[0x{N_LAND:08x}] "
        f"= 0x{got_n:08x} (expected 0). X-CHK would not catch the payload drop.")

    # WBP-SLIP: the W beat really was backpressured (wv=1 while wr=0), and the fix
    # kept the payload on the AXI W data through the whole slip and delivered it when
    # the beat completed.
    assert r["slipped"], "W beat did not slip — s_axi_wready force ineffective; check timing."
    assert r["held"] and all(s == B_PAY for s in r["held"]), (
        f"payload not held on s_axi_wdata across the slipped-W window: "
        f"{[hex(s) for s in r['held']]}, expected all 0x{B_PAY:08x}.")
    assert r["fire_wdata"] == B_PAY, (
        f"the slipped W beat completed with 0x{(r['fire_wdata'] or 0):08x}, expected "
        f"0x{B_PAY:08x} — the fix did not carry the payload through the backpressure.")

    dut._log.info("PASS: clean peer write crosses to die B; the original-drop emulation "
                  "drops it (non-vacuous); and under a genuinely slipped W beat the fix "
                  "keeps the payload on s_axi_wdata and delivers it.")


# ===========================================================================
# DIAGNOSTIC: characterise the NATURAL behaviour of ahb_sub_hwdata (the Rank 2
# held value) after a clean peer write, with NO force at all — to see exactly how
# long the fix holds the payload and correlate with d2d_ahb_m_hready / peer_wr_dph.
# Run: make -C verif/g2_soc_pair sim TESTCASE=test_diag_q_hold
# ===========================================================================
@cocotb.test(timeout_time=60, timeout_unit="ms")
async def test_diag_q_hold(dut):
    tb = Pair(dut)
    await tb.bring_up()
    assert tb.link_is_up(), "link not up"
    await tb.program_cam(enable=True)
    paddr = PEER_ADDR + 0x00
    q = dut.u_dieA.d2d_ahb_m_hwdata_q
    cocotb.start_soon(tb.rich_trace(16))
    cocotb.start_soon(tb.a.write(paddr, PAYLOAD))
    await tb._wait_peer_wr_addr(paddr)                    # T
    samples = []
    for i in range(12):
        v = q.value
        samples.append(int(v) if v.is_resolvable else None)
        await RisingEdge(dut.sys_fclk)
    dut._log.info(f"DIAG q(ahb_sub_hwdata) from T for 12 cyc (NO force) = "
                  f"{[hex(s) if s is not None else 'x' for s in samples]}")
    await ClockCycles(dut.sys_fclk, 200)
