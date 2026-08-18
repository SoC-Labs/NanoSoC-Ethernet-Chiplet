"""ADVERSARIAL suite against the proposed cap_done_r beat-handshake re-arm.

The proposal (src/rtl/nanosoc_eth_chiplet.sv ~:323) changes

    if (~dph_peer) cap_done_r <= 1'b0;
to
    if (~dph_peer | d2d_ahb_m_hready) cap_done_r <= 1'b0;

test_peer_burst_corruption.py proves the INCR4 case and the isolated SINGLE.
This file attacks the SAME change from the directions that killed the sister
chiplet's rd_pipe_r fix -- i.e. the shapes a narrow test does NOT reach:

  A1 INCR16          -- 16 beats, 16 distinct payloads. A depth-sensitive fix
                        (pulse/counter) breaks past 4.
  A2 back-to-back    -- two INCR4 bursts with NO idle gap between them, so
                        dph_peer never drops across the seam. The old `~dph_peer`
                        re-arm cannot see the boundary at all.
  A3 single-after-burst -- the LIVE VALIDATED silicon path must still work AFTER
                        a burst has left cap_done_r/hwdata_q in a burst state.
  A4 read-after-write   -- a peer READ's data phase must not disturb hwdata_q
                        (peer_wr_r gate), and must not itself corrupt.
  A5 W-BACKPRESSURE BURST -- THE ONE THAT MATTERS. Forces die A's AXI W-ready low
                        across the burst so the W beat SLIPS, exactly the silicon
                        condition that made v1/v2 drop 5/5. Observed at
                        s_axi_wdata on each W handshake (NOT die B's SRAM: forcing
                        Wlink's own wready output corrupts link transport -- see
                        Pair.wbp_slip_check docstring). Must run LAST.
  A6 wr_hold census  -- CHARACTERISATION, not pass/fail: is TideLink's wr_hold_r
                        (tidelink_top.sv:1863, the register that holds the master
                        across W backpressure) actually SET for the SEQ beats of a
                        burst? Its set term is `ext_is_nonseq & ...`, which is
                        NONSEQ-only by construction.

Run (from verif/g2_soc_pair, env sourced), each with a clean SIM_BUILD:
  rm -rf build/sim && make sim MODULE=test_peer_burst_adversarial TESTCASE=<name>
"""
import os

import cocotb
from cocotb.triggers import ClockCycles, RisingEdge

from test_g2_soc_pair import (
    Pair, PEER_ADDR, LANDED_ADDR, FCSM_LINK_IDLE,
)
from test_peer_burst_corruption import Eth0BurstMaster, HBURST_INCR4

os.environ.setdefault("COCOTB_RESOLVE_X", "ZEROS")

HBURST_INCR16 = 0b111
HBURST_INCR   = 0b001          # undefined-length INCR


async def _up(dut, tb):
    """Bring the pair up and assert the link is live, or declare INCONCLUSIVE."""
    await tb.bring_up()
    a_st, b_st = tb.fcsm_state("A"), tb.fcsm_state("B")
    assert tb.link_is_up(), (
        f"INCONCLUSIVE: FCSM did not reach LINK_IDLE ({FCSM_LINK_IDLE}): "
        f"A={a_st} B={b_st}")
    await tb.program_cam(enable=True)
    await ClockCycles(dut.sys_fclk, 50)
    return a_st, b_st


class BurstMaster2(Eth0BurstMaster):
    """Adds a back-to-back burst pair with NO idle beat at the seam."""

    async def write_incr_pair(self, base0, d0, base1, d1, hburst=HBURST_INCR4):
        resp = 0
        await self._await_ready("pre-burst idle")
        for (base, datas) in ((base0, d0), (base1, d1)):
            n = len(datas)
            self.s("hwrite").value = 1
            self.s("hsize").value = 0b010
            self.s("hburst").value = hburst
            self.s("hprot").value = 0
            self.s("haddr").value = base
            self.s("htrans").value = 0b10           # NONSEQ, beat 0
            resp |= await self._await_ready(f"pair addr[0] 0x{base:08x}")
            for k in range(1, n):
                self.s("haddr").value = base + 4 * k
                self.s("htrans").value = 0b11       # SEQ
                self.s("hwdata").value = datas[k - 1]
                resp |= await self._await_ready(f"pair beat[{k-1}]")
            # NO idle: the next iteration's NONSEQ address phase lands here,
            # concurrent with this burst's last data beat.
            self.s("hwdata").value = datas[n - 1]
        self.s("htrans").value = 0
        self.s("hwrite").value = 0
        resp |= await self._await_ready("pair final beat")
        self.s("hwdata").value = 0
        return resp


# ===========================================================================
# A1 -- INCR16. Depth beyond the 4 the headline test proves.
# ===========================================================================
@cocotb.test(timeout_time=180, timeout_unit="ms")
async def test_a1_incr16(dut):
    log = dut._log
    tb = Pair(dut)
    m = BurstMaster2(dut, "a")
    await _up(dut, tb)
    m.idle()

    base = PEER_ADDR + 0x400
    land = LANDED_ADDR + 0x400
    data = [0x1100_0000 | (i << 8) | (i + 1) for i in range(16)]
    assert len(set(data)) == 16

    await m.write_incr(base, data, HBURST_INCR16)
    await ClockCycles(dut.sys_fclk, 3000)
    got = [await tb.b.read(land + 4 * k) for k in range(16)]

    log.info("=" * 74)
    log.info("A1 INCR16 -- 16 distinct payloads")
    bad = []
    for k in range(16):
        ok = got[k] == data[k]
        if not ok:
            bad.append(k)
        log.info(f"  beat {k:2d} B[0x{land+4*k:08x}] = 0x{got[k]:08x} "
                 f"(want 0x{data[k]:08x}) [{'OK' if ok else 'BAD'}]")
    log.info(f"  distinct landed values = {len(set(got))}/16")
    log.info("=" * 74)
    assert not bad, (f"A1 FAIL: INCR16 beats {bad} wrong. "
                     f"landed={[hex(x) for x in got]} want={[hex(x) for x in data]}")


# ===========================================================================
# A2 -- two INCR4 bursts back to back, NO idle gap. dph_peer never drops at
#       the seam, so the old `~dph_peer` re-arm is structurally blind to it.
# ===========================================================================
@cocotb.test(timeout_time=180, timeout_unit="ms")
async def test_a2_back_to_back_bursts(dut):
    log = dut._log
    tb = Pair(dut)
    m = BurstMaster2(dut, "a")
    await _up(dut, tb)
    m.idle()

    base0 = PEER_ADDR + 0x500
    base1 = PEER_ADDR + 0x600
    land0 = LANDED_ADDR + 0x500
    land1 = LANDED_ADDR + 0x600
    d0 = [0x2200_0000 | k for k in range(4)]
    d1 = [0x3300_0000 | k for k in range(4)]

    # No idle beat between them: write_incr's trailing beat is immediately
    # followed by the next burst's NONSEQ address phase.
    await m.write_incr_pair(base0, d0, base1, d1, HBURST_INCR4)
    await ClockCycles(dut.sys_fclk, 3000)
    g0 = [await tb.b.read(land0 + 4 * k) for k in range(4)]
    g1 = [await tb.b.read(land1 + 4 * k) for k in range(4)]

    log.info("=" * 74)
    log.info("A2 back-to-back INCR4 (no idle gap)")
    log.info(f"  burst0 landed={[hex(x) for x in g0]} want={[hex(x) for x in d0]}")
    log.info(f"  burst1 landed={[hex(x) for x in g1]} want={[hex(x) for x in d1]}")
    log.info("=" * 74)
    assert g0 == d0, f"A2 FAIL burst0: {[hex(x) for x in g0]} != {[hex(x) for x in d0]}"
    assert g1 == d1, f"A2 FAIL burst1: {[hex(x) for x in g1]} != {[hex(x) for x in d1]}"


# ===========================================================================
# A3 -- the LIVE VALIDATED path: an isolated SINGLE write AFTER a burst.
# ===========================================================================
@cocotb.test(timeout_time=180, timeout_unit="ms")
async def test_a3_single_after_burst(dut):
    log = dut._log
    tb = Pair(dut)
    m = BurstMaster2(dut, "a")
    await _up(dut, tb)
    m.idle()

    # single BEFORE
    await m.write_single(PEER_ADDR + 0x700, 0x5EED_0001)
    await ClockCycles(dut.sys_fclk, 800)
    before = await tb.b.read(LANDED_ADDR + 0x700)

    # a burst in between, to leave cap_done_r / hwdata_q in a burst state
    await m.write_incr(PEER_ADDR + 0x800, [0x4400_0000 | k for k in range(4)],
                       HBURST_INCR4)
    await ClockCycles(dut.sys_fclk, 1500)

    # single AFTER
    await m.write_single(PEER_ADDR + 0x900, 0x5EED_0002)
    await ClockCycles(dut.sys_fclk, 800)
    after = await tb.b.read(LANDED_ADDR + 0x900)

    # and a THIRD single, immediately after the second with a short gap
    await m.write_single(PEER_ADDR + 0x904, 0x5EED_0003)
    await ClockCycles(dut.sys_fclk, 800)
    after2 = await tb.b.read(LANDED_ADDR + 0x904)

    log.info("=" * 74)
    log.info("A3 isolated SINGLE around a burst (the live validated silicon path)")
    log.info(f"  single BEFORE burst = 0x{before:08x} (want 0x5eed0001)")
    log.info(f"  single AFTER  burst = 0x{after:08x} (want 0x5eed0002)")
    log.info(f"  single AFTER  again = 0x{after2:08x} (want 0x5eed0003)")
    log.info("=" * 74)
    assert before == 0x5EED_0001, f"A3 FAIL: single before burst = 0x{before:08x}"
    assert after == 0x5EED_0002, (
        f"A3 REGRESSION: isolated single after a burst = 0x{after:08x}, want 0x5eed0002 "
        "-- the fix broke the live validated path")
    assert after2 == 0x5EED_0003, f"A3 FAIL: second single after burst = 0x{after2:08x}"


# ===========================================================================
# A4 -- a peer READ between writes must not disturb the held payload.
# ===========================================================================
@cocotb.test(timeout_time=180, timeout_unit="ms")
async def test_a4_read_between_writes(dut):
    log = dut._log
    tb = Pair(dut)
    m = BurstMaster2(dut, "a")
    await _up(dut, tb)
    m.idle()

    await m.write_single(PEER_ADDR + 0xA00, 0x6AAA_0001)
    await ClockCycles(dut.sys_fclk, 900)
    # peer READ back across the link (exercises the read data phase)
    rd = await tb.a.read(PEER_ADDR + 0xA00)
    await ClockCycles(dut.sys_fclk, 900)
    # a burst AFTER the read
    d = [0x7700_0000 | k for k in range(4)]
    await m.write_incr(PEER_ADDR + 0xB00, d, HBURST_INCR4)
    await ClockCycles(dut.sys_fclk, 2000)
    got = [await tb.b.read(LANDED_ADDR + 0xB00 + 4 * k) for k in range(4)]
    landed_first = await tb.b.read(LANDED_ADDR + 0xA00)

    log.info("=" * 74)
    log.info("A4 peer READ between writes")
    log.info(f"  first single landed  = 0x{landed_first:08x} (want 0x6aaa0001)")
    log.info(f"  peer read returned   = 0x{rd:08x}")
    log.info(f"  burst after read     = {[hex(x) for x in got]} want={[hex(x) for x in d]}")
    log.info("=" * 74)
    assert landed_first == 0x6AAA_0001, f"A4 FAIL: single = 0x{landed_first:08x}"
    assert got == d, f"A4 FAIL: burst after a read {[hex(x) for x in got]} != {[hex(x) for x in d]}"


# ===========================================================================
# A6 -- CHARACTERISATION: is TideLink's wr_hold_r set for a burst's SEQ beats?
#       (run before A5 so its trace is not perturbed by the wready force)
# ===========================================================================
@cocotb.test(timeout_time=180, timeout_unit="ms")
async def test_a6_wr_hold_census_over_burst(dut):
    log = dut._log
    tb = Pair(dut)
    m = BurstMaster2(dut, "a")
    await _up(dut, tb)
    m.idle()

    w = dut.u_dieA
    t = tb._dieA_tl()
    rows = []
    on = {"v": False}

    async def sample():
        while True:
            await RisingEdge(dut.sys_fclk)
            if not on["v"]:
                continue

            def i(o, s):
                try:
                    v = getattr(o, s).value
                    return int(v) if v.is_resolvable else None
                except Exception:
                    return None
            if i(w, "dph_peer"):
                rows.append({
                    "htrans": i(w, "d2d_ahb_m_htrans"),
                    "hready": i(w, "d2d_ahb_m_hready"),
                    "capd":   i(w, "cap_done_r"),
                    "live":   i(w, "d2d_ahb_m_hwdata"),
                    "q":      i(w, "d2d_ahb_m_hwdata_q"),
                    "wr_hold": i(t, "wr_hold_r"),
                    "wvalid": i(t, "s_axi_wvalid"),
                    "wready": i(t, "s_axi_wready"),
                    "wdata":  i(t, "s_axi_wdata"),
                })

    cocotb.start_soon(sample())
    on["v"] = True
    d = [0x8800_0000 | k for k in range(4)]
    await m.write_incr(PEER_ADDR + 0xC00, d, HBURST_INCR4)
    await ClockCycles(dut.sys_fclk, 60)
    on["v"] = False

    log.info("=" * 74)
    log.info("A6 CHARACTERISATION -- per-cycle over the burst's peer data phases")
    log.info("  htrans hready capd live       q          wr_hold wv wr wdata")
    for r in rows[:40]:
        def h(x):
            return "x" if x is None else (hex(x) if isinstance(x, int) else str(x))
        log.info(f"   {h(r['htrans'])}     {h(r['hready'])}     {h(r['capd'])}   "
                 f"{h(r['live']):>10} {h(r['q']):>10}    {h(r['wr_hold'])}    "
                 f"{h(r['wvalid'])}  {h(r['wready'])}  {h(r['wdata'])}")
    holds = [r["wr_hold"] for r in rows]
    log.info(f"  wr_hold_r values seen across the burst data phases = {sorted(set(map(str, holds)))}")
    log.info(f"  hready low cycles during peer dph = {sum(1 for r in rows if r['hready'] == 0)}")
    log.info(f"  wready low cycles during peer dph = {sum(1 for r in rows if r['wready'] == 0)}")
    log.info("=" * 74)
    # characterisation only -- never fails
    assert True


# ===========================================================================
# A5 -- THE ONE THAT MATTERS. Burst under REAL W-channel backpressure.
#       Forcing Wlink's wready output corrupts link transport, so the verdict
#       is read at s_axi_wdata on each W handshake, NOT at die B's SRAM.
#       MUST RUN LAST (the force perturbs the link).
# ===========================================================================
@cocotb.test(timeout_time=180, timeout_unit="ms")
async def test_a5_burst_under_w_backpressure(dut):
    log = dut._log
    tb = Pair(dut)
    m = BurstMaster2(dut, "a")
    await _up(dut, tb)
    m.idle()

    t = tb._dieA_tl()
    base = PEER_ADDR + 0xD00
    d = [0x9900_0000 | k for k in range(4)]

    fired = []       # (wdata) at each W handshake
    on = {"v": False}

    async def wsample():
        while True:
            await RisingEdge(dut.sys_fclk)
            if not on["v"]:
                continue

            def i(s):
                v = getattr(t, s).value
                return int(v) if v.is_resolvable else None
            if i("s_axi_wvalid") == 1 and i("s_axi_wready") == 1:
                fired.append(i("s_axi_wdata"))

    cocotb.start_soon(wsample())
    on["v"] = True

    # Kick the burst off, then backpressure W from the first data phase for a
    # few cycles so the W beats genuinely slip behind the AHB beats.
    wtask = cocotb.start_soon(m.write_incr(base, d, HBURST_INCR4))
    await tb._wait_peer_wr_addr(base)          # T: burst beat-0 address phase
    await RisingEdge(dut.sys_fclk)             # T+1: beat 0 data phase
    tb.w_backpressure(True)
    await ClockCycles(dut.sys_fclk, 6)         # hold W off across the burst beats
    tb.w_backpressure(False)
    try:
        await wtask
    except Exception as e:
        log.error(f"  burst under backpressure did not complete: {e}")
    await ClockCycles(dut.sys_fclk, 400)
    on["v"] = False

    log.info("=" * 74)
    log.info("A5 INCR4 under FORCED W-channel backpressure (the silicon condition)")
    log.info(f"  W beats fired, s_axi_wdata = {[hex(x) if x is not None else 'x' for x in fired]}")
    log.info(f"  want (in order)            = {[hex(x) for x in d]}")
    log.info("  NOTE die B is NOT read: forcing Wlink's wready output corrupts link")
    log.info("       transport (see Pair.wbp_slip_check docstring).")
    log.info("=" * 74)

    # The payload each W beat CARRIES must be the beat's own, in order.
    seen = [x for x in fired if x is not None]
    assert len(seen) >= 4, (
        f"A5 INCONCLUSIVE: only {len(seen)} W beats fired ({[hex(x) for x in seen]}); "
        "cannot judge per-beat payload under backpressure.")
    assert seen[:4] == d, (
        f"A5 FAIL: under W backpressure the W beats carried {[hex(x) for x in seen[:4]]}, "
        f"want {[hex(x) for x in d]}. The single capture register cannot both HOLD a "
        "beat across W backpressure and ADVANCE to the next beat.")


# ===========================================================================
# A7 -- ROOT-CAUSE DIAGNOSTIC for the residual one-beat skew.
#
# With the beat-handshake re-arm in place the capture register is CORRECT
# (d2d_ahb_m_hwdata_q advances through every distinct payload), yet the landed
# words are shifted one beat. This test pairs the AXI AW and W handshakes at die
# A's XHB500 s_axi face so the skew is visible where it is created:
#
#   AW addresses accepted:  A0, A1, A2, A3
#   W  data  accepted    :  D?, D?, D?, D?
#
# If W[k] != data[k] while AW[k] == base+4k, the write-data path and the address
# path have DIFFERENT latencies through the ahb_sub ingress. TideLink delays the
# address of a NONSEQ beat by one cycle (pipe_valid_r, tidelink_top.sv:1606) but
# passes SEQ beats through LIVE (:1778-1784) -- so the wrapper's one-cycle data
# capture re-aligns beat 0 and MIS-aligns every SEQ beat by exactly one beat.
# That is a TideLink ingress property; no wrapper-local register can correct it.
# ===========================================================================
@cocotb.test(timeout_time=180, timeout_unit="ms")
async def test_a7_axi_aw_w_pairing(dut):
    log = dut._log
    tb = Pair(dut)
    m = BurstMaster2(dut, "a")
    await _up(dut, tb)
    m.idle()

    t = tb._dieA_tl()
    w = dut.u_dieA
    base = PEER_ADDR + 0xE00
    d = [0xABCD_0000 | k for k in range(4)]

    aws, ws, rows = [], [], []
    on = {"v": False}

    def i(o, s):
        try:
            v = getattr(o, s).value
            return int(v) if v.is_resolvable else None
        except Exception:
            return None

    async def sample():
        while True:
            await RisingEdge(dut.sys_fclk)
            if not on["v"]:
                continue
            if i(t, "s_axi_awvalid") == 1 and i(t, "s_axi_awready") == 1:
                aws.append(i(t, "s_axi_awaddr"))
            if i(t, "s_axi_wvalid") == 1 and i(t, "s_axi_wready") == 1:
                ws.append(i(t, "s_axi_wdata"))
            if i(w, "dph_peer") or i(t, "pipe_valid_r"):
                rows.append((i(w, "d2d_ahb_m_htrans"), i(w, "d2d_ahb_m_haddr"),
                             i(w, "d2d_ahb_m_hready"), i(w, "cap_done_r"),
                             i(w, "d2d_ahb_m_hwdata"), i(w, "d2d_ahb_m_hwdata_q"),
                             i(t, "pipe_valid_r"), i(t, "s_axi_awvalid"),
                             i(t, "s_axi_wvalid"), i(t, "s_axi_wdata")))

    cocotb.start_soon(sample())
    on["v"] = True
    await m.write_incr(base, d, HBURST_INCR4)
    await ClockCycles(dut.sys_fclk, 300)
    on["v"] = False

    def h(x):
        return "x" if x is None else hex(x)

    log.info("=" * 78)
    log.info("A7 AXI AW/W PAIRING at die A s_axi (the skew's birthplace)")
    log.info(f"  AW addresses accepted = {[h(x) for x in aws]}")
    log.info(f"  W  data      accepted = {[h(x) for x in ws]}")
    log.info(f"  intended pairing      = "
             f"{[(h(base + 4*k), h(d[k])) for k in range(4)]}")
    log.info("  --- per-cycle (htrans haddr hready capd live q | pipeV awv wv wdata) ---")
    for r in rows[:44]:
        log.info(f"   {h(r[0])} {h(r[1])} {h(r[2])} {h(r[3])} {h(r[4]):>12} {h(r[5]):>12}"
                 f" | {h(r[6])} {h(r[7])} {h(r[8])} {h(r[9]):>12}")
    log.info("=" * 78)

    n = min(len(aws), len(ws), 4)
    mism = [k for k in range(n) if ws[k] != d[k]]
    log.info(f"  W-beat payload mismatches vs intent at beats {mism}")
    log.info(f"  DIAGNOSIS: {'ADDRESS/DATA LATENCY MISMATCH in ahb_sub ingress' if mism else 'aligned'}")
    assert True   # diagnostic only


# ===========================================================================
# A9 -- REACHABILITY WIDENER. Two back-to-back NONSEQ SINGLE writes with NO idle
# beat between them (an aperture memcpy -- the exact traffic shape
# nanosoc_eth_chiplet.sv:250 already names: "It oscillates on back-to-back peer
# transfers -- a memcpy across the aperture").
#
# This needs NO burst-capable master and NO DMA-250 programming. If it corrupts,
# the defect is reachable from ordinary CPU stores, not just from an unprogrammed
# DMA path, and the "structural hole that ships" framing understates it.
#
# hburst stays SINGLE and every beat is NONSEQ; only the IDLE gap is removed.
# ===========================================================================
@cocotb.test(timeout_time=180, timeout_unit="ms")
async def test_a9_back_to_back_nonseq_singles(dut):
    log = dut._log
    tb = Pair(dut)
    m = BurstMaster2(dut, "a")
    await _up(dut, tb)
    m.idle()

    base = PEER_ADDR + 0xF00
    land = LANDED_ADDR + 0xF00
    d = [0xC0DE_0001, 0xC0DE_0002, 0xC0DE_0003, 0xC0DE_0004]

    w = dut.u_dieA
    rows = []
    on = {"v": False}

    def i(o, s):
        try:
            v = getattr(o, s).value
            return int(v) if v.is_resolvable else None
        except Exception:
            return None

    async def sample():
        while True:
            await RisingEdge(dut.sys_fclk)
            if on["v"] and i(w, "dph_peer"):
                rows.append((i(w, "d2d_ahb_m_hready"), i(w, "cap_done_r"),
                             i(w, "d2d_ahb_m_hwdata"), i(w, "d2d_ahb_m_hwdata_q")))

    cocotb.start_soon(sample())
    on["v"] = True

    # Back-to-back NONSEQ singles: each beat's address phase is presented in the
    # SAME cycle as the previous beat's data phase, with no IDLE in between.
    await m._await_ready("pre idle")
    m.s("hwrite").value = 1
    m.s("hsize").value = 0b010
    m.s("hburst").value = 0            # SINGLE, not a burst
    m.s("hprot").value = 0
    for k, val in enumerate(d):
        m.s("haddr").value = base + 4 * k
        m.s("htrans").value = 0b10     # NONSEQ every time
        await m._await_ready(f"a9 addr[{k}]")
        if k > 0:
            pass
        m.s("hwdata").value = val
    m.s("htrans").value = 0
    m.s("hwrite").value = 0
    await m._await_ready("a9 last data")
    m.s("hwdata").value = 0

    await ClockCycles(dut.sys_fclk, 2500)
    on["v"] = False
    got = [await tb.b.read(land + 4 * k) for k in range(4)]

    def h(x):
        return "x" if x is None else hex(x)

    log.info("=" * 78)
    log.info("A9 back-to-back NONSEQ SINGLE writes (memcpy shape, hburst=SINGLE)")
    log.info("   hready capd live         q")
    for r in rows[:30]:
        log.info(f"    {h(r[0])}     {h(r[1])}   {h(r[2]):>12} {h(r[3]):>12}")
    for k in range(4):
        ok = got[k] == d[k]
        log.info(f"  word {k} B[0x{land+4*k:08x}] = 0x{got[k]:08x} (want 0x{d[k]:08x}) "
                 f"[{'OK' if ok else 'BAD'}]")
    log.info(f"  distinct landed = {len(set(got))}/4")
    log.info("=" * 78)
    assert got == d, (
        f"A9: back-to-back NONSEQ singles corrupt. landed={[hex(x) for x in got]} "
        f"want={[hex(x) for x in d]}. This shape needs no DMA and no burst-capable "
        "master -- ordinary consecutive CPU stores to the aperture reach it.")
