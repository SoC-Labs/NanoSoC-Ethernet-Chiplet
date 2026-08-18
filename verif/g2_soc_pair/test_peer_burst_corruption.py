"""URGENT (possibly tapeout-blocking) probe — READ-ONLY investigation.

Does a multi-beat peer-write BURST (INCR4, DISTINCT per-beat payloads) into the
eth-chiplet peer aperture deliver beat 0's payload on EVERY beat (silicon data
corruption)?

Alleged mechanism (statically confirmed; this file SIMULATES it):
  nanosoc_eth_chiplet.sv:319-323 captures d2d_ahb_m_hwdata into
  d2d_ahb_m_hwdata_q on the FIRST peer-write data-phase cycle (cap_done_r) and
  then HOLDS it; it re-arms only when dph_peer drops (:323). d2d_ahb_m_hwdata_q
  feeds tidelink's ahb_sub_hwdata (:775). chiplet_d2d_decode.sv:112 keeps the
  peer selected across SEQ beats, so if dph_peer stays high across a burst,
  cap_done_r never re-arms mid-burst and beats 1..N-1 present beat-0's held value
  to TideLink/XHB500 -- and thus to the far die.

WHY g2_soc_pair AND NOT g2_peer_aperture
----------------------------------------
The cap_done_r / d2d_ahb_m_hwdata_q register exists ONLY inside the
nanosoc_eth_chiplet wrapper. verif/g2_peer_aperture/tb_pair.sv drives
tidelink_top.ahb_sub DIRECTLY and never instantiates the wrapper, so it sits
DOWNSTREAM of the capture register and is structurally BLIND to this bug. A strict
INCR4 master there exercises TideLink's ahb_sub only. verif/g2_soc_pair
instantiates two REAL nanosoc_eth_chiplet dies, so the capture register IS in the
path; die B's real shared_sram_0 is the ground-truth sink.

The existing g2_soc_pair "8-word burst" (test_g2_soc_pair Stage 2c, regress.sh:18)
writes DISTINCT data and checks each landed word, but issues 8 ISOLATED single
NONSEQ writes (cocotbext AHBLiteMaster hardwires hburst=SINGLE and awaits each
transfer to completion). An IDLE gap sits between them, so dph_peer drops and
cap_done_r re-arms per beat -- the mechanism is never reached. This test issues a
genuine CONTINUOUS INCR4 burst (NONSEQ + SEQ beats, no bubble), which is the only
stimulus shape that holds dph_peer high across beats.

VERDICT is derived from the DIRECT capture observation on die A's outbound path
(d2d_ahb_m_hwdata_q == ahb_sub_hwdata, sampled every cycle while dph_peer is high)
-- this needs no link and is exactly the register the bug lives in. The end-to-end
read of die B's real SRAM is the belt-and-braces ground-truth confirmation.

Run (from verif/g2_soc_pair, env sourced):
  make sim MODULE=test_peer_burst_corruption \
       TESTCASE=test_peer_write_burst_delivers_each_beat
"""
import os

import cocotb
from cocotb.triggers import ClockCycles, RisingEdge

from test_g2_soc_pair import (
    Pair, PEER_ADDR, LANDED_ADDR, APERTURE_BYTE, REMOTE_BYTE, FCSM_LINK_IDLE,
)

os.environ.setdefault("COCOTB_RESOLVE_X", "ZEROS")

# INCR4, distinct payloads, none zero, none a repeat -- a data-phase hold shows up.
BURST_BASE   = PEER_ADDR + 0x100          # 0x2F001100 -> die B 0x2D001100
BURST_LAND   = LANDED_ADDR + 0x100        # 0x2D001100
BURST_DATA   = [0xAAAA0000, 0xBBBB0001, 0xCCCC0002, 0xDDDD0003]
HBURST_INCR4 = 0b011

# a single write, separate word, to prove the data plane is live end-to-end.
SINGLE_ADDR  = PEER_ADDR + 0x200
SINGLE_LAND  = LANDED_ADDR + 0x200
SINGLE_DATA  = 0x1234ABCD

# a second, pre-link INCR4 to a scratch peer address for the DIRECT capture probe.
PRE_BASE     = PEER_ADDR + 0x300


class Eth0BurstMaster:
    """Hand-rolled AHB-Lite master on a die's eth_ss_0 manager port.

    eth_ss_0 is a manager-style port (no hsel; selected by htrans[1]) whose hready
    is a SoC OUTPUT. Standard AHB-Lite: present address+control, sample hready on
    the clock edge, advance when high. hwdata is driven in the beat's data phase
    (cycle after its address phase) and advanced to each beat's OWN value.
    """

    def __init__(self, dut, tag, timeout=40000):
        self.dut = dut
        self.tag = tag
        self.clk = dut.sys_fclk
        self.timeout = timeout

    def s(self, name):
        return getattr(self.dut, f"{self.tag}_eth_ss_0_{name}")

    def idle(self):
        self.s("htrans").value = 0
        self.s("hwrite").value = 0
        self.s("hburst").value = 0
        self.s("hwdata").value = 0

    async def _await_ready(self, what):
        for _ in range(self.timeout):
            await RisingEdge(self.clk)
            if int(self.s("hready").value):
                v = self.s("hresp").value
                return int(v) if v.is_resolvable else 0
        raise TimeoutError(f"eth_ss_0 hready never high: {what}")

    async def write_incr(self, base, datas, hburst=HBURST_INCR4):
        """One AHB INCR<n> burst: NONSEQ beat 0 + (n-1) SEQ beats, addr/data
        pipelined, DISTINCT data per beat. Returns OR of the hresp seen."""
        n = len(datas)
        resp = 0
        await self._await_ready("pre-burst idle")
        self.s("hwrite").value = 1
        self.s("hsize").value = 0b010            # word
        self.s("hburst").value = hburst
        self.s("hprot").value = 0
        self.s("haddr").value = base
        self.s("htrans").value = 0b10            # NONSEQ, beat 0
        resp |= await self._await_ready("burst addr[0]")
        for k in range(1, n):
            self.s("haddr").value = base + 4 * k
            self.s("htrans").value = 0b11        # SEQ
            self.s("hwdata").value = datas[k - 1]
            resp |= await self._await_ready(f"burst beat[{k-1}]")
        self.s("htrans").value = 0
        self.s("hwrite").value = 0
        self.s("hwdata").value = datas[n - 1]
        resp |= await self._await_ready(f"burst beat[{n-1}]")
        self.s("hwdata").value = 0
        return resp

    async def write_single(self, addr, data):
        await self._await_ready("pre-single idle")
        self.s("hwrite").value = 1
        self.s("hsize").value = 0b010
        self.s("hburst").value = 0
        self.s("hprot").value = 0
        self.s("haddr").value = addr
        self.s("htrans").value = 0b10
        await self._await_ready(f"single addr 0x{addr:08x}")
        self.s("htrans").value = 0
        self.s("hwrite").value = 0
        self.s("hwdata").value = data
        resp = await self._await_ready(f"single data 0x{addr:08x}")
        self.s("hwdata").value = 0
        return resp


class OutboundCaptureProbe:
    """Samples die A's outbound decode + capture EVERY cycle. The mechanism is
    visible here directly and independently of the link: while dph_peer is high,
    d2d_ahb_m_hwdata is the LIVE per-beat data the SoC presents and
    d2d_ahb_m_hwdata_q is what is HELD onto tidelink's ahb_sub_hwdata."""

    def __init__(self, dut):
        self.dut = dut
        self.w = dut.u_dieA
        self.rows = []          # (dph, capd, live_hwdata|None, q_hwdata|None, htrans, hwrite)
        self.on = False

    def start(self):
        self.rows = []
        self.on = True

    def stop(self):
        self.on = False

    async def run(self):
        w = self.w
        while True:
            await RisingEdge(self.dut.sys_fclk)
            if not self.on:
                continue

            def i(sig):
                v = getattr(w, sig).value
                return int(v) if v.is_resolvable else None
            dph = i("dph_peer")
            if dph:
                self.rows.append((dph, i("cap_done_r"), i("d2d_ahb_m_hwdata"),
                                  i("d2d_ahb_m_hwdata_q"), i("d2d_ahb_m_htrans"),
                                  i("d2d_ahb_m_hwrite")))

    def peer_write_dph_run(self):
        """The contiguous run of peer data-phase cycles that belong to a WRITE.
        Returns (live_values, q_values) over that run, de-duplicated per distinct
        (live,q) so a multi-cycle-per-beat hold reads clearly."""
        live, q = [], []
        prev = None
        for (dph, capd, lv, qv, ht, hw) in self.rows:
            key = (lv, qv)
            if key != prev:
                live.append(lv)
                q.append(qv)
                prev = key
        return live, q


@cocotb.test(timeout_time=120, timeout_unit="ms")
async def test_peer_write_burst_delivers_each_beat(dut):
    log = dut._log
    tb = Pair(dut)
    m = Eth0BurstMaster(dut, "a")
    probe = OutboundCaptureProbe(dut)
    cocotb.start_soon(probe.run())

    # -- Stage 1: bring the link up CLEANLY (no prior peer traffic; a stalled
    #    peer write with the link down wedges eth_ss_0 and breaks bring-up). -----
    await tb.bring_up()
    m.idle()
    a_st, b_st = tb.fcsm_state("A"), tb.fcsm_state("B")
    assert tb.link_is_up(), (
        f"INCONCLUSIVE: Wlink FCSM did not reach LINK_IDLE ({FCSM_LINK_IDLE}): "
        f"die A={a_st} die B={b_st}. Cannot exercise the peer aperture without a "
        "live link.")
    log.info(f"STAGE 1 ok: link up (FCSM A={a_st} B={b_st})")

    await tb.program_cam(enable=True)
    cocotb.start_soon(tb.catch_inbound_writes())      # die B d2d_ahb_s beats
    cocotb.start_soon(tb.catch_outbound_writes())     # die A d2d_ahb_m beats
    await ClockCycles(dut.sys_fclk, 50)

    # -- Stage 2: CONTROL single peer write — proves the data plane is live so a
    #    null SRAM result is not misread as the burst bug. -----------------------
    log.info("==== CONTROL single peer write (data-plane liveness) ====")
    await m.write_single(SINGLE_ADDR, SINGLE_DATA)
    await ClockCycles(dut.sys_fclk, 800)
    got_single = await tb.b.read(SINGLE_LAND)
    log.info(f"  CONTROL single: die B[0x{SINGLE_LAND:08x}] = 0x{got_single:08x} "
             f"(want 0x{SINGLE_DATA:08x})")

    # -- Stage 3: the BURST. Genuine continuous INCR4, DISTINCT per-beat data,
    #    with the DIRECT capture probe running (live d2d_ahb_m_hwdata vs held q). -
    log.info("==== INCR4 BURST (continuous, distinct per-beat payloads) ====")
    probe.start()
    e2e_burst_err = None
    try:
        resp = await m.write_incr(BURST_BASE, BURST_DATA, HBURST_INCR4)
        log.info(f"  burst issued, OR(hresp)={resp}")
    except TimeoutError as e:
        e2e_burst_err = str(e)
        log.error(f"  burst timed out: {e}")
    await ClockCycles(dut.sys_fclk, 40)
    probe.stop()
    await ClockCycles(dut.sys_fclk, 2000)             # drain across the link
    got = [await tb.b.read(BURST_LAND + 4 * k) for k in range(4)]

    live, q = probe.peer_write_dph_run()
    live_distinct = [x for x in live if x is not None]
    q_distinct    = set(x for x in q if x is not None)

    # -- Report ----------------------------------------------------------------
    def _fmt(lst):
        return [tuple(hex(x) if isinstance(x, int) else x for x in row) for row in lst]

    log.info("=" * 74)
    log.info("PEER-WRITE BURST DATA-INTEGRITY — full two-SoC (nanosoc_eth_chiplet) pair")
    log.info("  master: STRICT continuous INCR4 (advances hwdata to each beat's own "
             "DISTINCT value; NONSEQ+SEQ beats, no bubble)")
    sc = "OK" if got_single == SINGLE_DATA else "DATA-PLANE-DOWN"
    log.info(f"  CONTROL single die B = 0x{got_single:08x} (want 0x{SINGLE_DATA:08x}) [{sc}]")
    log.info(f"  [DIRECT] LIVE per-beat d2d_ahb_m_hwdata  = "
             f"{[hex(x) if x is not None else 'x' for x in live]}")
    log.info(f"  [DIRECT] HELD  ahb_sub_hwdata (q)        = "
             f"{[hex(x) if x is not None else 'x' for x in q]}")
    for k in range(4):
        tag = "OK" if got[k] == BURST_DATA[k] else (
            "==beat0" if got[k] == BURST_DATA[0] else "OTHER")
        log.info(f"  [E2E] burst beat {k} die B[0x{BURST_LAND+4*k:08x}] = 0x{got[k]:08x} "
                 f"(want 0x{BURST_DATA[k]:08x}) [{tag}]")
    log.info(f"  die A OUTBOUND d2d_ahb_m beats = {_fmt(getattr(tb, 'outbound_writes', []))}")
    log.info(f"  die B INBOUND  d2d_ahb_s beats = {_fmt(getattr(tb, 'inbound_writes', []))}")
    log.info("=" * 74)

    # -- Verdict ---------------------------------------------------------------
    assert got_single == SINGLE_DATA, (
        f"INCONCLUSIVE: CONTROL single peer write did not cross "
        f"(die B[0x{SINGLE_LAND:08x}]=0x{got_single:08x} != 0x{SINGLE_DATA:08x}); the "
        "data plane is down on this build, so the burst result cannot be attributed "
        "to the cap_done_r mechanism.")
    assert e2e_burst_err is None, f"INCONCLUSIVE: burst did not complete: {e2e_burst_err}"

    # DIRECT signature of the mechanism: over the peer WRITE data-phase run, the
    # LIVE d2d_ahb_m_hwdata advanced through >=2 distinct beat values while the
    # HELD ahb_sub_hwdata (q) stuck at beat 0.
    direct_corrupt = (len(live_distinct) >= 2 and len(q_distinct) == 1
                      and BURST_DATA[0] in q_distinct)

    # END-TO-END ground truth in die B's real SRAM.
    all_own        = all(got[k] == BURST_DATA[k] for k in range(4))
    beats123_beat0 = (got[0] == BURST_DATA[0]
                      and all(got[k] == BURST_DATA[0] for k in range(1, 4)))

    if beats123_beat0:
        assert False, (
            "VERDICT CONFIRMED-CORRUPT: burst beats 1-3 all carry beat 0's payload "
            f"in die B's real SRAM. landed={[hex(x) for x in got]}, "
            f"want={[hex(x) for x in BURST_DATA]}. DIRECT capture: live advanced "
            f"{[hex(x) for x in live_distinct]} while held q={sorted(hex(x) for x in q_distinct)} "
            "(cap_done_r held beat 0 across the burst; ahb_sub — and the far die — "
            "see beat 0 on every beat).")

    if all_own:
        assert not direct_corrupt, (
            "VERDICT CONTRADICTION: SRAM shows each beat its own, yet the DIRECT "
            f"capture probe shows ahb_sub_hwdata held at beat 0 "
            f"(q={sorted(hex(x) for x in q_distinct)}, live={[hex(x) for x in live_distinct]}). "
            "Investigate the probe window.")
        log.info("VERDICT REFUTED: each burst beat delivered its OWN payload into die B's "
                 "real SRAM, and the capture probe shows ahb_sub_hwdata advanced per beat.")
        return

    assert False, (
        f"VERDICT UNEXPECTED: landed={[hex(x) for x in got]}, "
        f"want={[hex(x) for x in BURST_DATA]}; DIRECT live={[hex(x) for x in live_distinct]}, "
        f"held q={sorted(hex(x) for x in q_distinct)}. Inspect the OUTBOUND/INBOUND traces.")
