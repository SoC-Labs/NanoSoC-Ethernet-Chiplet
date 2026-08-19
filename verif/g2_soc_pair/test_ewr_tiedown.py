"""DIRECTED PROOF: the peer-path HPROT tie-down clears HPROT[3:2] at ahb_sub.

WHAT THIS PROVES
----------------
`nanosoc_eth_chiplet.sv` connects TideLink's peer subordinate as

    .ahb_sub_hprot ({2'b00, d2d_ahb_m_hprot[1:0]})

so whatever an initiator asks for, the bits TideLink receives on the peer path
have HPROT[3] (cacheable) and HPROT[2] (bufferable) forced to 0.

WHY THOSE TWO BITS. TideLink instantiates the bridge as
`.hprot({3'h0, xhb_sub_hprot})` (tidelink_top.sv:2676), so XHB500's hprot[6] is
hardwired 0 and its early-write-response arm

    ewr <= hprot[2] & ~hprot[6];          (..._core_wdata.sv:248)

reduces to exactly HPROT[2]. The same term gates the hazard-list allocation
(`hazard_add`, ..._core_addr.sv:233) and `pause_addr_submit` (:155) — the
multiple-outstanding-write behaviour the D2D wedge builds on. HPROT[3] sets
`write_mod` / `awcache[1]` and clears `singles_burst` (..._core_addr.sv:147),
which is what lets a fixed-length burst become one multi-beat AXI burst.

WHY A NEW TEST. The existing bench master drives hprot=0 everywhere
(tb_g2_soc_pair.sv:122,134; test_peer_burst_corruption.py:107,128), so this path
has NEVER been exercised by the suite. A test that passes with and without the
tie-down proves nothing, so this test is built to FAIL when the tie-down is
reverted:

  * it first asserts the STIMULUS ARRIVED — die A's own d2d_ahb_m_hprot must
    show the requested bits — so a write that never reached the aperture is
    reported INCONCLUSIVE rather than passing vacuously;
  * only then does it assert the tie-down held at the ahb_sub boundary.

Run (from verif/g2_soc_pair, env sourced):
  make sim MODULE=test_ewr_tiedown
"""
import os

import cocotb
from cocotb.triggers import ClockCycles, RisingEdge

from test_g2_soc_pair import Pair, PEER_ADDR, LANDED_ADDR, FCSM_LINK_IDLE
from test_peer_burst_corruption import Eth0BurstMaster

os.environ.setdefault("COCOTB_RESOLVE_X", "ZEROS")

# One scratch peer word per stimulus case, clear of the other tests' addresses.
CASES = [
    # (label,                 hprot, addr_off, data)
    ("hprot[2] bufferable",   0b0100, 0x400, 0xE2E20002),
    ("hprot[3] cacheable",    0b1000, 0x410, 0xE3E30003),
    ("hprot[3:2] both",       0b1100, 0x420, 0xE5E50005),
    ("hprot=0 control",       0b0000, 0x430, 0xE0E00000),
]


class HprotBoundaryProbe:
    """Samples die A's peer-aperture HPROT on BOTH sides of the tie-down.

    `d2d_ahb_m_hprot`            — what the SoC bus matrix presents (master side)
    `u_tidelink.ahb_sub_hprot`   — what TideLink actually receives (the boundary
                                   the tie-down acts on)

    and the two XHB500 effects that HPROT[2] arms, so the downstream consequence
    is observed and not merely inferred:
    `u_xhb_sub.u_core.u_wdata.ewr`        — the early-write-response latch
    `u_xhb_sub.u_core.u_addr.hazard_add`  — a hazard-list entry being allocated
    """

    def __init__(self, dut):
        self.dut = dut
        self.w = dut.u_dieA
        self.rows = []
        self.on = False
        self.ewr_seen = False
        self.hazard_seen = False
        self.missing = []

    def _read(self, obj, path):
        cur = obj
        try:
            for part in path.split("."):
                cur = getattr(cur, part)
        except AttributeError:
            if path not in self.missing:
                self.missing.append(path)
            return None
        v = cur.value
        return int(v) if v.is_resolvable else None

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
            # Only while die A's peer aperture is selected.
            sel = self._read(w, "hsel_peer")
            ewr = self._read(w, "u_tidelink.u_xhb_sub.u_core.u_wdata.ewr")
            haz = self._read(w, "u_tidelink.u_xhb_sub.u_core.u_addr.hazard_add")
            if ewr:
                self.ewr_seen = True
            if haz:
                self.hazard_seen = True
            if not sel:
                continue
            self.rows.append((
                self._read(w, "d2d_ahb_m_hprot"),          # master side
                self._read(w, "u_tidelink.ahb_sub_hprot"),  # TideLink side
                self._read(w, "d2d_ahb_m_hwrite"),
            ))

    def seen(self):
        """(master_hprot_values, tidelink_hprot_values) over the sampled run."""
        m = sorted({r[0] for r in self.rows if r[0] is not None})
        t = sorted({r[1] for r in self.rows if r[1] is not None})
        return m, t


class HprotMaster(Eth0BurstMaster):
    """Eth0BurstMaster, but the single write drives a CHOSEN HPROT.

    The base class hardwires hprot=0, which is exactly why this path has never
    been exercised.
    """

    async def write_single_hprot(self, addr, data, hprot):
        await self._await_ready("pre-single idle")
        self.s("hwrite").value = 1
        self.s("hsize").value = 0b010
        self.s("hburst").value = 0
        self.s("hprot").value = hprot
        self.s("haddr").value = addr
        self.s("htrans").value = 0b10
        await self._await_ready(f"single addr 0x{addr:08x} hprot=0x{hprot:x}")
        self.s("htrans").value = 0
        self.s("hwrite").value = 0
        self.s("hwdata").value = data
        resp = await self._await_ready(f"single data 0x{addr:08x}")
        self.s("hwdata").value = 0
        self.s("hprot").value = 0
        return resp


@cocotb.test(timeout_time=180, timeout_unit="ms")
async def test_peer_hprot_tiedown_clears_bits_3_2(dut):
    log = dut._log
    tb = Pair(dut)
    m = HprotMaster(dut, "a")
    probe = HprotBoundaryProbe(dut)
    cocotb.start_soon(probe.run())

    await tb.bring_up()
    m.idle()
    a_st, b_st = tb.fcsm_state("A"), tb.fcsm_state("B")
    assert tb.link_is_up(), (
        f"INCONCLUSIVE: Wlink FCSM did not reach LINK_IDLE ({FCSM_LINK_IDLE}): "
        f"die A={a_st} die B={b_st}.")
    log.info(f"link up (FCSM A={a_st} B={b_st})")

    await tb.program_cam(enable=True)
    await ClockCycles(dut.sys_fclk, 50)

    results = []
    for label, hprot, off, data in CASES:
        addr = PEER_ADDR + off
        land = LANDED_ADDR + off
        probe.start()
        try:
            resp = await m.write_single_hprot(addr, data, hprot)
        except TimeoutError as e:
            probe.stop()
            results.append((label, hprot, None, None, None, f"TIMEOUT {e}"))
            log.error(f"  {label}: master timed out: {e}")
            continue
        await ClockCycles(dut.sys_fclk, 40)
        probe.stop()
        await ClockCycles(dut.sys_fclk, 1500)          # drain across the link
        landed = await tb.b.read(land)
        mvals, tvals = probe.seen()
        results.append((label, hprot, mvals, tvals, landed, f"hresp={resp}"))
        log.info(f"  {label}: master d2d_ahb_m_hprot={[hex(v) for v in mvals]} "
                 f"-> TideLink ahb_sub_hprot={[hex(v) for v in tvals]} "
                 f"die B[0x{land:08x}]=0x{landed:08x} (want 0x{data:08x})")

    log.info("=" * 78)
    log.info("PEER-PATH HPROT TIE-DOWN — ahb_sub boundary observation (die A)")
    if probe.missing:
        log.warning(f"  UNREADABLE probe paths: {probe.missing}")
    for (label, hprot, mvals, tvals, landed, note) in results:
        log.info(f"  requested hprot=0x{hprot:x} [{label}]")
        log.info(f"      master  d2d_ahb_m_hprot   = "
                 f"{[hex(v) for v in mvals] if mvals else mvals}")
        log.info(f"      TideLink ahb_sub_hprot    = "
                 f"{[hex(v) for v in tvals] if tvals else tvals}   <-- tie-down acts here")
        log.info(f"      landed die B              = "
                 f"{('0x%08x' % landed) if landed is not None else None}   ({note})")
    log.info(f"  XHB500 u_wdata.ewr ever asserted       = {probe.ewr_seen}")
    log.info(f"  XHB500 u_addr.hazard_add ever asserted = {probe.hazard_seen}")
    log.info("=" * 78)

    # ---- Discrimination guard: the stimulus must have REACHED the aperture ----
    # Without this, a build where hprot never propagates from eth_ss_0 to
    # d2d_ahb_m would "pass" while measuring nothing.
    stim = {label: mvals for (label, hprot, mvals, _t, _l, _n) in results
            if mvals is not None}
    armed = [label for (label, hprot, mvals, _t, _l, _n) in results
             if hprot & 0b1100 and mvals and any(v & 0b1100 for v in mvals)]
    assert armed, (
        "INCONCLUSIVE: no case presented HPROT[3:2] on die A's d2d_ahb_m_hprot, so "
        "the tie-down was never actually challenged. The SoC bus matrix may be "
        f"zeroing HPROT upstream of the aperture. master-side values seen: {stim}")
    log.info(f"stimulus confirmed at the aperture for: {armed}")

    # ---- THE ASSERTION UNDER TEST -------------------------------------------
    for (label, hprot, mvals, tvals, landed, note) in results:
        if tvals is None:
            continue
        bad = [v for v in tvals if v & 0b1100]
        assert not bad, (
            f"TIE-DOWN NOT IN EFFECT for [{label}]: TideLink received "
            f"ahb_sub_hprot={[hex(v) for v in bad]} with HPROT[3:2] set, after the "
            f"master requested hprot=0x{hprot:x} and die A's d2d_ahb_m_hprot showed "
            f"{[hex(v) for v in mvals]}. XHB500's EWR / cacheable paths are reachable "
            f"on the peer path.")

    # ---- Downstream consequence ---------------------------------------------
    assert not probe.ewr_seen, (
        "XHB500 u_wdata.ewr asserted on the peer path despite the tie-down — the "
        "early-write-response path armed.")
    assert not probe.hazard_seen, (
        "XHB500 u_addr.hazard_add asserted on the peer path despite the tie-down — "
        "a hazard-list entry was allocated, i.e. multiple outstanding writes armed.")

    # ---- The tie-down must not have broken data delivery ---------------------
    for (label, hprot, mvals, tvals, landed, note) in results:
        expect = {c[0]: c[3] for c in CASES}[label]
        assert landed == expect, (
            f"REGRESSION for [{label}]: peer write did not land — "
            f"die B = {('0x%08x' % landed) if landed is not None else None}, "
            f"want 0x{expect:08x}. The tie-down must not change data delivery.")

    log.info("PASS: HPROT[3:2] cleared at ahb_sub for every case; ewr and hazard_add "
             "never asserted; all four peer writes landed.")
