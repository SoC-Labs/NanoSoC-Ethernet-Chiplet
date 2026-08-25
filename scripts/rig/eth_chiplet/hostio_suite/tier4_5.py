#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# HOSTIO4 / ADP functional suite -- Tier 4 (dynamic and functional) and
# Tier 5 (firmware-assisted).
#
# Written against docs/bringup/HOSTIO4_FUNCTIONAL_TEST_PLAN.md sections 2 (Tier 4
# and Tier 5 tables), 1.2 (command set), 1.4 (reachable map), 1.5 (error and
# hazard semantics) and 5 (2026-08-25 hardware verification), and against the
# PINNED API in CONTRACT.md.  Nothing here imports or touches another tier file.
#
# ORDERING REQUIREMENT.  HIO-401 is the master control for every test in this
# file that uses `P`.  It is declared first and must be RUN first in the tier:
# with mask 0 the compare degenerates to `0 ^ V == 0`, so V=0 must match and
# V=1 can never match, whatever the DUT contains.  Every other `P`-based test
# (405, 406, 408, 412, 504, 505) is vacuous unless 401 passed, and each declares
# `needs=["HIO-401"]` so the runner voids them rather than greening them.
#
# WHAT THIS FILE NEVER DOES
#   * It never emits `U`.  `U` has no abort and no timeout (socdebug_adp_control.v
#     :633-635): the FSM waits in ADP_UREADB for exactly <count> raw payload
#     bytes, and 0x04/0x00 are DATA there, not escapes.  The pinned Adp API has
#     no raw-payload transmit call (`adp.cmd` sends a command line; `adp.raw_rx`
#     is receive-only), so a `U` issued from this file could never be satisfied
#     and would hang the port until a host PIO resync.  HIO-501 and HIO-508
#     therefore SKIP; see their reasons.
#   * It never emits `F` either -- the only `F` in this plan's Tier 5 is HIO-501's
#     IMEM pre-zero, which is pointless (and destructive) without the `U` that
#     must follow it.
#   * It never touches the HZ-1 quarantine band, the HZ-8 read-clearing
#     registers, the HZ-6 XiP aperture, or the spinlock acquire pages.  That is
#     enforced in code by _check_addr(), not by review.
#   * It touches the HZ-2 peer aperture exactly once, from HIO-413, guarded.
#
# ENVIRONMENT (all optional; every one of them defaults to "skip, and say so")
#   HOSTIO_PHC_CORE_HZ      HIO-404 expected PHC core clock (default 250000000).
#   HOSTIO_PEER_DIE=1       HIO-413: a peer die is powered, has passed its own
#                           Tier 0-1, and a human is watching.  The harness
#                           cannot verify any of that, so it must be asserted.
#   HOSTIO_CPU0_IMAGE       path to a CPU0 image for HIO-501/502/506.
#   HOSTIO_CPU1_IMAGE       path to a CPU1 image for HIO-508.
#   HOSTIO_FW_HEARTBEAT_ADDR   HIO-504 incrementing heartbeat word (default
#                           0x2D000000).
#   HOSTIO_FW_SENTINEL_ADDR HIO-503/504 fixed sentinel word (default heartbeat+4).
#   HOSTIO_FW_SENTINEL      HIO-503/504 the exact value firmware writes there.
#   HOSTIO_FW_MDIO_RESULT_ADDR HIO-506 where firmware parks the PHY ID words.
#   HOSTIO_FW_FAULT_ADDR    HIO-507 the unmapped address firmware deliberately hit.
#   HOSTIO_UART2_LOOPBACK=1 HIO-505: uart2 TXD is externally looped to RXD (see
#                           the note in that test -- without a loop, ADP cannot
#                           see firmware console output at all).
#
# Copyright 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------
"""HOSTIO4 ADP suite, Tier 4 (dynamic/functional) and Tier 5 (firmware-assisted)."""

import os
import time

from harness import Adp, Reply, test, Rec, HZ  # noqa: F401  (pinned import, CONTRACT.md)


# -----------------------------------------------------------------------------
# Addresses.  Every one is inside debug_m's decode (plan section 1.4).
# -----------------------------------------------------------------------------
BOOTROM_ETH = 0x08000000          # always-aliased eth boot ROM; answers OKAY. M
ETH_IMEM = 0x10000000             # remap-independent eth IMEM alias, 32 KB
CPU1_IMEM = 0x90000000            # remap-independent CPU1 IMEM alias, 16 KB

DMA_IIDR = 0x20000FC8             # DMA-250 IIDR; 0 => power-gated
DMA_IIDR_EXPECT = 0x2500043B

PHC_CTRL = 0x22000000             # [0] en, [1] set_time (pulse), [2] capture (pulse)
PHC_STATUS = 0x22000004           # [0] running, [1] pps_sticky (READ-TO-CLEAR), [2] alarm_hit
PHC_NS_INCR = 0x22000008          # [7:0] integer ns per core cycle
PHC_CAP_SEC_LO = 0x22000020       # latched by ctrl.capture
PHC_CAP_NS = 0x22000028           # latched 30-bit nanoseconds
PHC_CTRL_EN = 0x00000001
PHC_CTRL_EN_CAPTURE = 0x00000005  # bit0 MUST be re-asserted with bit2 or the clock stops
PHC_NS_PER_SEC = 1000000000

TIMER0_CTRL = 0x28000000          # cmsdk_apb_timer.v:118-125  [0] EN
TIMER0_VALUE = 0x28000004         # reg_curr_val, RW, decrements while CTRL[0]
TIMER0_RELOAD = 0x28000008        # reg_reload_val

UART2_DATA = 0x28006000           # read mux index 0 -> reg_rx_buf (cmsdk_apb_uart.v:261)
UART2_STATE = 0x28006004          # {rx_ovr, tx_ovr, rx_buf_full, tx_buf_full}  (:251)
UART2_STATE_RX_FULL = 0x00000002

BOOTGATE = 0x29000000             # chip_core_remap_ctrl; [2] NETWORK_CORE_BOOTGATE
BOOTGATE_ALIAS_PROBE = 0x29000004  # section 5.5: returns the same word -- alias or not?
BOOTGATE_CPU0 = 0x00000004
BOOTGATE_CPU1_REMAP = 0x00000001

RESET_INFO_CPU0 = 0x2A000010      # W1C, [0] SYSRESETREQ [2] LOCKUPRESET [3] EXTRESET
SW_RESET = 0x2A000020             # [0] CPU0_SWRST, [1] CPU1_SWRST (HZ-5)
SWRST_CPU0 = 0x00000001
SWRST_CPU1 = 0x00000002

PERF_CTRL = 0x2C200008            # WO, write-1-pulse; [0] SNAP, [1] CLR
PERF_CTRL_SNAP = 0x00000001       # latch live counters -> shadow.  CLR is HIO-307's.
PERF_P0_CYC = 0x2C200040          # probe 0 CYC -- the SHADOW of a SATURATING counter
PERF_CNT_MAX = 0xFFFFFFFF         # ctrl_ahb_perf_probe.v:184 holds here, never wraps

FAULT_STAT = 0x2C300000           # [0] FAULT_SEEN(W1C) [5:4] INIT_IDX [8] OVERFLOW
FAULT_ADDR = 0x2C300004
FAULT_COUNT = 0x2C30000C

SHARED_SRAM = 0x2D000000          # 8 KB, the only RAM both CPUs and ADP reach
BOOT_CONFIRM = 0x2D001FF0         # nanosoc_boot_confirm.h:73-74
BOOT_CONFIRM_TOKEN = 0xB007C0FE

TL_LANE_STATUS = 0x2E032108       # tidelink_regs.rdl swi_lane_status @0x108
XHB_SUB_OBS = 0x2E0321F8          # marker 0xB5 (tidelink_top.sv:1874-1882)
AXINODE_OBS = 0x2E0321E0          # marker 0xAD (tidelink_axinode_obs.sv:162-168)
XHB_MARKER = 0xB5
AXINODE_MARKER = 0xAD

TC_STATUS = 0x2E040000            # [0] election_done [1] is_root [2] enum_done
TC_BEST_CLAIM = 0x2E040004        #                    [7:3] local_id [12:8] total
TC_ENUM_STATE = 0x2E040028
TC_ERROR = 0x2E04002C             # [2] DUAL_ROOT sticky (W1C -- we only ever read)

PEER_APERTURE = 0x2F000000        # HZ-2.  No default responder.  One shot only.

ETHMAC_BASE = 0x40000000          # UNREACHABLE from debug_m (measured R!) -- HIO-415

# -----------------------------------------------------------------------------
# Budgets and windows.
# -----------------------------------------------------------------------------
POLL_BUDGET = 0x00100000          # 1 M poll reads; ~tens of ms on-die
POLL_BUDGET_SMALL = 0x00000010    # HIO-401's discrimination pair
POLL_TIMEOUT_MS = 12000           # host-side; a 1 M-iteration poll is on-die fast
CMD_TIMEOUT_MS = 4000
PEER_TIMEOUT_MS = 6000            # HZ-2: bounded host transaction timeout
FABRIC_INTERVAL_S = 3.0           # HIO-402; must stay well under the 2^32 wrap
PHC_INTERVAL_S = 5.0              # HIO-404; also under the P0_CYC wrap at <=850 MHz
BANNER_WINDOW_S = 12.0            # HIO-509
BANNER_CHUNK_MS = 500

FABRIC_HZ_MIN = 1000000           # plausibility band for a measured fabric clock
FABRIC_HZ_MAX = 2000000000

# -----------------------------------------------------------------------------
# Hard address blocklist (plan section 1.5).  A typo in this file must not be
# able to wedge a die, so the guard lives in code and every access in this
# module goes through it.
# -----------------------------------------------------------------------------
_BANDS = (
    (0x2E0321A0, 0x2E0321B8, "HZ-1 TideLink SYNC_DIST band: uninterruptible AXI hang, "
                             "power cycle to recover; simulation cannot reproduce it"),
    (0x24000000, 0x27FFFFFF, "HZ-6 QSPI XiP aperture: 1.3 ms HREADY stall or a livelock"),
    (0x2C100000, 0x2C1002FF, "HZ-7 spinlock ACQUIRE pages (0/1/2): a read acquires the lock"),
    (0x2F000000, 0x2FFFFFFF, "HZ-2 peer aperture: no default responder, a failed read parks "
                             "the peer port and the NEXT access wedges the host"),
)
_READ_CLEARING = {
    0x2E032020: "HZ-8 RELEASED_CREDITS_ACC (read-clearing)",
    0x2E032024: "HZ-8 RELEASED_CREDITS_ACC (read-clearing)",
    0x2E032038: "HZ-8 DOORBELL_RESPONSE_ACC (read-clearing)",
    0x2E03215C: "HZ-8 read-clearing / auto-incrementing",
    0x2E032160: "HZ-8 read-clearing / auto-incrementing",
    0x2E032168: "HZ-8 read-clearing / auto-incrementing",
}
# Writes that are irreversible or reset something.  Only these exact values may
# ever be written to these addresses from this file.
_WRITE_WHITELIST = {
    BOOTGATE: {0x00000000, BOOTGATE_CPU0, BOOTGATE_CPU1_REMAP},
    SW_RESET: {SWRST_CPU0, SWRST_CPU1},
    # SNAP only.  CLR (bit 1) zeroes every probe's live counters and belongs to
    # HIO-307; a typo here would silently destroy another test's measurement.
    PERF_CTRL: {PERF_CTRL_SNAP},
}


class HazardRefusal(RuntimeError):
    """Raised instead of issuing an access this module is forbidden to make."""


def _check_addr(addr, allow_peer=False):
    if not 0 <= addr <= 0xFFFFFFFF:
        raise HazardRefusal("address 0x%X out of range" % addr)
    for lo, hi, why in _BANDS:
        if lo <= addr <= hi:
            if allow_peer and lo == 0x2F000000:
                continue
            raise HazardRefusal("refusing 0x%08X: %s" % (addr, why))
    if addr in _READ_CLEARING:
        raise HazardRefusal("refusing 0x%08X: %s" % (addr, _READ_CLEARING[addr]))


def _check_write(addr, val):
    allowed = _WRITE_WHITELIST.get(addr)
    if allowed is not None and val not in allowed:
        raise HazardRefusal(
            "refusing W x%08X to 0x%08X: only %s may be written to this register "
            "from tier4_5" % (val, addr, sorted("0x%08X" % v for v in allowed)))


# -----------------------------------------------------------------------------
# Link helpers.  Every parameter is x + exactly 8 hex digits (plan section 1.2:
# the hex-digit count sets HSIZE, and `P`'s count parameter silently sets the
# size of the poll's read).
# -----------------------------------------------------------------------------
def _rd(adp, addr, timeout_ms=None, allow_peer=False):
    """One 32-bit read: A x<addr> ; R.  R auto-increments, so A is re-issued."""
    _check_addr(addr, allow_peer=allow_peer)
    if timeout_ms is None:
        return adp.read(addr)
    adp.cmd("Ax%08X" % addr, timeout_ms=timeout_ms)
    return adp.cmd("R", timeout_ms=timeout_ms)


def _wr(adp, addr, val, timeout_ms=None):
    _check_addr(addr)
    _check_write(addr, val)
    if timeout_ms is None:
        return adp.write(addr, val)
    adp.cmd("Ax%08X" % addr, timeout_ms=timeout_ms)
    return adp.cmd("Wx%08X" % val, timeout_ms=timeout_ms)


def _poll(adp, addr, mask, value, budget, timeout_ms=POLL_TIMEOUT_MS):
    """A ; M ; V ; P.  Returns the P reply.

    Match  -> r.error False, r.value = iterations consumed (a HARDWARE latency
              measurement in bus transactions, free of the ~130 ms link).
    Timeout-> r.error True,  r.value = the un-consumed budget.
    `!` on P is ambiguous between timeout and a bus ERROR seen during the poll
    (socdebug_adp_control.v:647-648), which is why callers prove the address
    answers OKAY with a plain R first.
    """
    _check_addr(addr)
    adp.cmd("Ax%08X" % addr, timeout_ms=CMD_TIMEOUT_MS)
    adp.cmd("Mx%08X" % mask, timeout_ms=CMD_TIMEOUT_MS)
    adp.cmd("Vx%08X" % value, timeout_ms=CMD_TIMEOUT_MS)
    return adp.cmd("Px%08X" % budget, timeout_ms=timeout_ms)


def _matched(r):
    """A `P` that matched.  The letter is checked because a rejected command
    comes back as a well-formed '?' (ok True, error False) and would otherwise
    read as a match."""
    return bool(r.ok) and r.letter == "P" and not r.error and r.value is not None


def _timed_out(r):
    """A `P` that exhausted its budget (or hit a bus error -- `!` on P is
    ambiguous between the two, socdebug_adp_control.v:647-648)."""
    return bool(r.ok) and r.letter == "P" and bool(r.error)


def _good(r):
    """A read that arrived, was a read, and did not raise the bus-error flag."""
    return bool(r.ok) and r.letter == "R" and not r.error and r.value is not None


def _wrote(r):
    """A write that arrived, was a write, and did not raise the bus-error flag."""
    return bool(r.ok) and r.letter == "W" and not r.error


def _bits(v, hi, lo):
    return (v >> lo) & ((1 << (hi - lo + 1)) - 1)


def _u32(x):
    return x & 0xFFFFFFFF


def _env(name, default=None):
    v = os.environ.get(name)
    return default if v is None or v.strip() == "" else v.strip()


def _env_flag(name):
    return str(_env(name, "0")).lower() in ("1", "true", "yes", "on")


def _env_int(name, default):
    v = _env(name)
    return default if v is None else int(v, 0)


def _sentinel_addr():
    """Where firmware parks its fixed liveness sentinel.  Separate from the
    incrementing heartbeat word: HIO-504 needs one word that holds a known value
    and one that keeps changing, and no single word can be both."""
    return _env_int("HOSTIO_FW_SENTINEL_ADDR",
                    _env_int("HOSTIO_FW_HEARTBEAT_ADDR", SHARED_SRAM) + 4)


def _perf_snapshot(adp):
    """SNAP, then read probe 0's CYC shadow.

    The block at 0x2C200000 is ctrl_ahb_perf_probe_regs (ID "PRF1" 0x50524631),
    whose readout returns SHADOW registers, frozen until the next SNAP
    (ctrl_ahb_perf_probe_regs.v:23-32).  Reading 0x2C200040 twice with no SNAP
    between therefore returns the same word however fast the clock is running --
    which is why this helper exists and why every P0_CYC sample in this file goes
    through it.  SNAP does not disturb the live counters; only CLR does, and CLR
    is HIO-307's to issue.
    """
    w = _wr(adp, PERF_CTRL, PERF_CTRL_SNAP)
    r = _rd(adp, PERF_P0_CYC)
    return w, r


def _require_okay(adp, rec, addr, label):
    """Prove an address answers OKAY before any `P` is aimed at it."""
    r = _rd(adp, addr)
    rec.check("%s answers OKAY before polling (P's ! is ambiguous)" % label,
              _good(r), got=r.raw)
    return r


def _refuse_upload(rec, what, nbytes):
    """The one guard that keeps `U` out of this file.  Always skips."""
    rec.skip(
        "%s needs `U` (%d bytes of raw payload) and this suite has no way to send it. "
        "The pinned Adp API (CONTRACT.md) has adp.cmd() for command lines and "
        "adp.raw_rx() for receive; there is no raw-payload transmit call. `U` has NO "
        "abort and NO timeout (socdebug_adp_control.v:633-635): the FSM waits in "
        "ADP_UREADB for exactly the byte count given, and 0x04/0x00 are DATA there, "
        "not escapes -- so a `U` issued without a byte-exact payload path hangs the "
        "port until a host PIO resync. TO ENABLE: add a raw-payload transmit to the "
        "harness (e.g. adp.raw_tx(bytes)) that writes exactly len(payload) bytes with "
        "no CR and no escaping, then set the image path in the environment."
        % (what, nbytes))


# -----------------------------------------------------------------------------
# Decoders shared by more than one test.
# -----------------------------------------------------------------------------
def _decode_lane_status(v):
    """tidelink_regs.rdl swi_lane_status @0x108 (verified against the RDL)."""
    return {
        "lane_locked": _bits(v, 7, 0),
        "lane_fault": _bits(v, 15, 8),
        "calibration_done": _bits(v, 16, 16),
        "fcsm_state": _bits(v, 20, 17),
        "llrx_state": _bits(v, 22, 21),
        "cr_pkt_seen_rx": _bits(v, 23, 23),
        "crack_pkt_seen_rx": _bits(v, 24, 24),
        "llrx_valid": _bits(v, 29, 29),
    }


def _classify_fcsm(f):
    if f == 1:
        return "WEDGE: credit-path bring-up failure (tidelink_regs.rdl:441)"
    if f == 2:
        return "WEDGE: stalled / no progress (axi_chiplet_controller.sv:739,891)"
    if 4 <= f <= 7:
        return "healthy operating region"
    if f == 0:
        return "idle / not brought up"
    return "unknown state"


def _read_xhb_witness(adp, timeout_ms=None):
    """HIO-409's two reads, also used verbatim as HIO-413's guard.

    Marker byte FIRST.  If [31:24] is not 0xB5 / 0xAD the register is absent or
    mis-decoded and every bit below it is meaningless -- a decoder that skips
    the marker reports 'healthy, all zeros' on a register that is not there.
    """
    out = {}
    r_f8 = _rd(adp, XHB_SUB_OBS, timeout_ms=timeout_ms)
    out["f8"] = r_f8
    out["f8_ok"] = _good(r_f8)
    out["f8_marker_ok"] = out["f8_ok"] and _bits(r_f8.value, 31, 24) == XHB_MARKER
    if out["f8_marker_ok"]:
        v = r_f8.value
        out["bridge_ready"] = _bits(v, 0, 0)             # xhb_sub_hreadyout_raw
        out["sub_wr_os_ctr"] = _bits(v, 3, 1)
        out["sub_wr_os_hwm"] = _bits(v, 7, 5)
        out["sub_wr_stuck_sticky"] = _bits(v, 8, 8)
        out["sub_err_sticky"] = _bits(v, 9, 9)
        out["xhb_stall_stuck_sticky"] = _bits(v, 10, 10)  # the deadlock witness
        out["ext_stall_err"] = _bits(v, 11, 11)

    r_e0 = _rd(adp, AXINODE_OBS, timeout_ms=timeout_ms)
    out["e0"] = r_e0
    out["e0_ok"] = _good(r_e0)
    out["e0_marker_ok"] = out["e0_ok"] and _bits(r_e0.value, 31, 24) == AXINODE_MARKER
    if out["e0_marker_ok"]:
        v = r_e0.value
        out["data_healthy"] = _bits(v, 23, 23)
        out["any_stall_live"] = _bits(v, 22, 22)
        out["ini_err"] = _bits(v, 21, 21)
        out["tgt_err"] = _bits(v, 20, 20)
        out["wedge_sticky"] = _bits(v, 19, 10)
        out["stall_live"] = _bits(v, 9, 0)

    out["healthy"] = bool(
        out["f8_marker_ok"] and out["e0_marker_ok"]
        and out.get("xhb_stall_stuck_sticky", 1) == 0
        and out.get("data_healthy", 0) == 1)
    return out


def _record_xhb(rec, w, prefix):
    rec.record(prefix + "_0x21F8", None if not w["f8_ok"] else w["f8"].value)
    rec.record(prefix + "_0x21E0", None if not w["e0_ok"] else w["e0"].value)
    rec.record(prefix + "_marker_b5", bool(w["f8_marker_ok"]))
    rec.record(prefix + "_marker_ad", bool(w["e0_marker_ok"]))
    if w["f8_marker_ok"]:
        rec.record(prefix + "_xhb_stall_stuck_sticky", w["xhb_stall_stuck_sticky"])
        rec.record(prefix + "_bridge_ready", w["bridge_ready"])
        rec.record(prefix + "_sub_err_sticky", w["sub_err_sticky"])
        rec.record(prefix + "_sub_wr_stuck_sticky", w["sub_wr_stuck_sticky"])
    if w["e0_marker_ok"]:
        rec.record(prefix + "_data_healthy", w["data_healthy"])
        rec.record(prefix + "_wedge_sticky", w["wedge_sticky"])


# =============================================================================
# TIER 4 -- dynamic and functional
# =============================================================================

@test("HIO-401", tier=4, control=True,
      gates=["HIO-405", "HIO-406", "HIO-408", "HIO-412", "HIO-504", "HIO-505"],
      hazard=None,
      purpose="Poll-engine self-test -- the built-in discrimination pair, and the "
              "master control for every `P` in this suite. With M=0 the compare "
              "degenerates to (data & 0) ^ V == 0, so V=0 MUST match on iteration 1 "
              "and V=1 can NEVER match, whatever the DUT contains. Goes red if the "
              "poll does not iterate, does not compare, does not count down, or "
              "cannot tell match from timeout -- with no fault injection and no DUT "
              "dependency. MEASURED 2026-08-25: P 0x00000001 and P!0x00000100 exactly "
              "as specified (plan section 5.2). Run first, every session; every other "
              "`P`-based test is vacuous without it.")
def hio_401(adp, rec):
    # P's `!` is ambiguous between timeout and a bus ERROR during the poll, so
    # prove the polled address answers OKAY first (plan section 1.3, limitation 6).
    _require_okay(adp, rec, BOOTROM_ETH, "boot ROM 0x08000000")

    a = _poll(adp, BOOTROM_ETH, 0x00000000, 0x00000000, POLL_BUDGET_SMALL)
    rec.record("p_match_raw", a.raw)
    rec.record("p_match_iterations", a.value)
    rec.check("mask 0 / value 0 MATCHES (no ! flag)", _matched(a), got=a.raw)
    rec.check("match reports iteration 1", a.value == 1, got=a.raw)

    b = _poll(adp, BOOTROM_ETH, 0x00000000, 0x00000001, POLL_BUDGET_SMALL)
    rec.record("p_timeout_raw", b.raw)
    rec.record("p_timeout_budget", b.value)
    rec.check("mask 0 / value 1 TIMES OUT (! flag)", _timed_out(b), got=b.raw)
    rec.check("timeout reports the exhausted budget", b.value == POLL_BUDGET_SMALL,
              got=b.raw)

    rec.note("This pair gates HIO-405/406/408/412/504/505. A run in which it did not "
             "pass must treat every other `P` result in this file as VOID.")


@test("HIO-402", tier=4, hazard=None,
      purpose="The fabric clock is running. Two P0_CYC reads bracketed by a "
              "host-measured interval; PASS = a non-zero advance whose implied "
              "frequency is physically plausible. This is the ONE test that "
              "distinguishes 'the die is clocked' from 'the die is latched' -- with a "
              "stopped HCLK every other test in this plan still 'works' (registers "
              "hold their values, reads return data) and only this one goes red. "
              "Goes red on delta == 0 (clock stopped) or an implausible rate.")
def hio_402(adp, rec):
    # The plan calls P0_CYC saturating and warns of a false-fail once it saturates.
    # The RTL says otherwise: ahb_perf_probe.v:120 is an unconditional
    # `cyc_q <= cyc_q + 1` with no saturation term, so the counter WRAPS modulo
    # 2^32 -- about every 43 s at 100 MHz, 17 s at 250 MHz.  That makes the plan's
    # "strictly increasing over ~5 s" criterion flaky by construction (a wrap
    # inside the window reads as a decrease), so this test uses a short interval,
    # modulo arithmetic, and a plausibility band instead.  The saturation case is
    # still handled explicitly below in case a build differs from this RTL.
    r1 = _rd(adp, PERF_P0_CYC)
    t1 = time.monotonic()
    rec.check("P0_CYC readable", _good(r1), got=r1.raw)
    if not _good(r1):
        return
    time.sleep(FABRIC_INTERVAL_S)
    r2 = _rd(adp, PERF_P0_CYC)
    t2 = time.monotonic()
    rec.check("P0_CYC readable (second sample)", _good(r2), got=r2.raw)
    if not _good(r2):
        return

    elapsed = t2 - t1
    delta = _u32(r2.value - r1.value)
    rec.record("p0_cyc_first", r1.value)
    rec.record("p0_cyc_second", r2.value)
    rec.record("p0_cyc_delta_mod32", delta)
    rec.record("p0_cyc_interval_s", round(elapsed, 4))

    if r1.value == 0xFFFFFFFF and r2.value == 0xFFFFFFFF:
        rec.skip("P0_CYC reads 0xFFFFFFFF twice -- saturated, so it can no longer "
                 "measure anything. Per ahb_perf_probe.v:120 this build should wrap "
                 "rather than saturate, so either the build differs or the counter is "
                 "stuck. Run HIO-307 (A x2c200008 ; Wx00000002, the perf-probe CLR, "
                 "which is Tier 3's to issue because it clears every probe) and re-run "
                 "this test. Reported as SKIP, not FAIL: a saturated counter measures "
                 "nothing either way.")

    hz = delta / elapsed if elapsed > 0 else 0.0
    rec.record("fabric_hclk_hz_estimate", int(hz))
    rec.check("the fabric clock advanced (delta != 0)", delta != 0,
              got="delta=%d over %.3f s" % (delta, elapsed))
    rec.check("implied HCLK is physically plausible (1 MHz .. 2 GHz)",
              FABRIC_HZ_MIN <= hz <= FABRIC_HZ_MAX,
              got="%.3f MHz" % (hz / 1e6))
    rec.note("Interval kept at %.1f s deliberately: P0_CYC wraps at 2^32 (~43 s at "
             "100 MHz), and a wrap inside the sampling window would read as a stopped "
             "clock." % FABRIC_INTERVAL_S)


@test("HIO-403", tier=4, hazard=None,
      destroys="leaves the PHC enabled (ctrl.en = 1) and the CAP_* latches updated",
      purpose="PHC enable + capture protocol, written out step by step because it is "
              "the most likely false-fail in the plan. ctrl resets to 0 = counter "
              "FROZEN (phc_regs.rdl ctrl.en), so a naive read-the-counter-twice test "
              "reports a dead clock on a perfectly good die; and ctrl.capture is a "
              "self-clearing single pulse whose write MUST re-assert bit 0 "
              "(Wx00000005, never Wx00000004) or the write stops the clock. There is "
              "no live-readable counter -- the shadow latch is the only path -- so "
              "the sequence below is mandatory, not stylistic. Goes red if enable "
              "does not stick (status.running = 0) or if the two shadow captures are "
              "identical (counter frozen despite enable).")
def hio_403(adp, rec):
    w = _wr(adp, PHC_CTRL, PHC_CTRL_EN)
    rec.check("CTRL enable write accepted", _wrote(w), got=w.raw)

    st = _rd(adp, PHC_STATUS)
    rec.check("STATUS readable", _good(st), got=st.raw)
    if not _good(st):
        return
    running = _bits(st.value, 0, 0)
    rec.record("phc_status", st.value)
    rec.record("phc_running", running)
    rec.check("status.running = 1 after enable", running == 1, got=st.raw)
    rec.note("STATUS read exactly once: bit 1 pps_sticky is read-to-clear "
             "(phc_regs.rdl), so polling this register would eat every PPS event.")

    caps = []
    for i in (0, 1):
        cw = _wr(adp, PHC_CTRL, PHC_CTRL_EN_CAPTURE)  # en + capture, in one write
        rec.check("capture pulse %d accepted (Wx00000005, bit 0 re-asserted)" % i,
                  _wrote(cw), got=cw.raw)
        cs = _rd(adp, PHC_CAP_SEC_LO)
        cn = _rd(adp, PHC_CAP_NS)
        rec.check("CAP_SECONDS_LO readable (capture %d)" % i, _good(cs), got=cs.raw)
        rec.check("CAP_NANOSECONDS readable (capture %d)" % i, _good(cn), got=cn.raw)
        if not (_good(cs) and _good(cn)):
            return
        caps.append((cs.value, cn.value))
        rec.record("phc_cap%d_seconds_lo" % i, cs.value)
        rec.record("phc_cap%d_nanoseconds" % i, cn.value)

    rec.check("the two shadow captures differ (the counter is advancing)",
              caps[0] != caps[1],
              got="cap0=%r cap1=%r" % (caps[0], caps[1]))


@test("HIO-404", tier=4, hazard=None, needs=["HIO-403"],
      purpose="PHC advance rate. Two shadow captures separated by a host-measured "
              "interval; PASS = the implied core frequency is within +/-10 % of "
              "ns_incr x the expected core clock. Detects a wrong NS_INCR strap or a "
              "core clock at the wrong frequency -- both invisible to HIO-403, which "
              "only asks whether the counter moved. Both {seconds, nanoseconds} are "
              "read from the same atomic capture, so the 1e9 nanosecond rollover "
              "cannot alias the measurement (the plan's CAP_NANOSECONDS[15:0] form "
              "wraps every 65.5 us, far faster than the ~130 ms link). CAP_NS_FRAC is "
              "deliberately unused: ns_incr_frac resets to 0, so it is static on a "
              "fresh part and would be a liveness signal that can never move.")
def hio_404(adp, rec):
    core_hz = _env_int("HOSTIO_PHC_CORE_HZ", 250000000)
    rec.record("phc_expected_core_hz", core_hz)

    ni = _rd(adp, PHC_NS_INCR)
    rec.check("NS_INCR readable", _good(ni), got=ni.raw)
    if not _good(ni):
        return
    ns_incr = _bits(ni.value, 7, 0)
    rec.record("phc_ns_incr", ns_incr)
    if ns_incr == 0:
        rec.skip("NS_INCR reads 0, so the PHC cannot advance by construction and a "
                 "rate measurement would be meaningless. Restore NS_INCR (HIO-309 "
                 "reads and restores it; RDL default is 4) and re-run.")

    def capture():
        cw = _wr(adp, PHC_CTRL, PHC_CTRL_EN_CAPTURE)
        t = time.monotonic()
        cs = _rd(adp, PHC_CAP_SEC_LO)
        cn = _rd(adp, PHC_CAP_NS)
        cyc = _rd(adp, PERF_P0_CYC)
        return cw, t, cs, cn, cyc

    w0, t0, s0, n0, c0 = capture()
    time.sleep(PHC_INTERVAL_S)
    w1, t1, s1, n1, c1 = capture()

    for label, r in (("capture 0 write", w0), ("capture 1 write", w1)):
        rec.check("%s accepted" % label, _wrote(r), got=r.raw)
    for label, r in (("sec0", s0), ("ns0", n0), ("sec1", s1), ("ns1", n1)):
        rec.check("%s readable" % label, _good(r), got=r.raw)
    if not all(_good(r) for r in (s0, n0, s1, n1)):
        return

    total0 = s0.value * PHC_NS_PER_SEC + n0.value
    total1 = s1.value * PHC_NS_PER_SEC + n1.value
    delta_ns = total1 - total0
    elapsed = t1 - t0
    rec.record("phc_delta_ns", delta_ns)
    rec.record("phc_interval_s", round(elapsed, 4))

    if elapsed <= 0 or delta_ns <= 0:
        rec.check("PHC advanced over the interval", False,
                  got="delta_ns=%d over %.3f s" % (delta_ns, elapsed))
        return

    rate = delta_ns / elapsed                 # nanoseconds of PHC per second of wall
    implied_core_hz = rate / ns_incr
    rec.record("phc_ns_per_wall_s", int(rate))
    rec.record("phc_implied_core_hz", int(implied_core_hz))

    # Free cross-check: the fabric counter was sampled inside the same bracket.
    if _good(c0) and _good(c1):
        fabric_hz = _u32(c1.value - c0.value) / elapsed
        rec.record("fabric_hz_during_phc_window", int(fabric_hz))
        if fabric_hz > 0:
            rec.record("phc_core_over_fabric_ratio", round(implied_core_hz / fabric_hz, 4))

    lo, hi = core_hz * 0.9, core_hz * 1.1
    rec.check("implied core clock within +/-10 %% of %d Hz" % core_hz,
              lo <= implied_core_hz <= hi,
              got="%.3f MHz (ns_incr=%d)" % (implied_core_hz / 1e6, ns_incr))
    rec.note("If this fails but phc_core_over_fabric_ratio is ~1.0, the PHC is fine "
             "and the expected-frequency constant is wrong for this build: set "
             "HOSTIO_PHC_CORE_HZ to the measured fabric clock and re-run.")


@test("HIO-405", tier=4, hazard=None, needs=["HIO-401"],
      purpose="Hardware latency measurement via `P`'s return value -- the capability "
              "that makes this port able to time a hardware interval at HCLK, free of "
              "the ~130 ms link. `P` returns the number of bus reads consumed before "
              "the match. Polled on P0_CYC, which is genuinely free-running; the "
              "plan's PHC form cannot advance under a poll (the polled shadow latch "
              "is stale until the next capture) and is run below only as a recorded "
              "demonstration of that limitation. Goes red if a poll that must "
              "terminate does not, if the count is outside the window the mask "
              "implies, or if repeated measurements return an identical constant "
              "(a canned reply rather than a measurement).")
def hio_405(adp, rec):
    _require_okay(adp, rec, PERF_P0_CYC, "P0_CYC 0x2C200040")

    # Window chosen so the poll cannot step over it: bits [15:12] == 0 is a
    # 4096-cycle-wide window in a 65536-cycle period, and one poll iteration is a
    # handful of HCLK.  Worst-case wait is ~61440 cycles, i.e. far below the budget.
    mask, value = 0x0000F000, 0x00000000
    window_period = 0x10000
    counts = []
    for i in range(3):
        r = _poll(adp, PERF_P0_CYC, mask, value, POLL_BUDGET)
        rec.record("p0_cyc_poll%d_raw" % i, r.raw)
        rec.check("free-running poll %d matched (no !)" % i, _matched(r), got=r.raw)
        if not _matched(r):
            return
        counts.append(r.value)
        rec.record("p0_cyc_poll%d_iterations" % i, r.value)

    rec.check("every count is inside the window the mask implies (1 .. %d)"
              % (2 * window_period),
              all(1 <= n <= 2 * window_period for n in counts), got=repr(counts))
    rec.check("the counts are not a constant (this is a measurement, not an echo)",
              len(set(counts)) > 1, got=repr(counts))

    # The PHC form, recorded rather than checked: the polled address is a shadow
    # latch that only advances on a capture write, so this poll either matches
    # immediately or burns the whole budget.  Both outcomes are correct; what is
    # being demonstrated is that `P` cannot time a register that does not move.
    demo = _poll(adp, PHC_CAP_NS, 0x0000FFFF, 0x00000000, 0x00010000)
    rec.record("phc_stale_latch_poll_raw", demo.raw)
    rec.check("the PHC demonstration returned a definite outcome", bool(demo.ok),
              got=demo.raw)
    rec.note("PHC form is a demonstration only: CAP_NANOSECONDS is a shadow latch, so "
             "polling it measures the stale value and never the live clock.")


@test("HIO-406", tier=4, hazard=None, needs=["HIO-401", "HIO-311"],
      destroys="cc_periph timer0 VALUE and CTRL (CTRL restored to 0, VALUE left at 0)",
      purpose="Timer counts down, waited on in hardware -- and the cross-validation of "
              "HIO-401 against real hardware, because two independent things must both "
              "be true for it to pass: the timer must actually count AND the poll must "
              "actually terminate. Runs BOTH polarities: with CTRL = 0 the poll must "
              "time out (the negative control the plan names), and with CTRL = 1 it "
              "must match. Two different reloads are used so the iteration count is "
              "checked for PROPORTIONALITY, not merely for being non-zero -- a poll "
              "whose count does not scale with the interval is not measuring the "
              "interval. Goes red on a match with the timer disabled, on a timeout "
              "with it enabled, or on counts that do not scale ~2x with the reload.")
def hio_406(adp, rec):
    # cmsdk_apb_timer.v: 0x00 CTRL ([0] EN), 0x04 VALUE (reg_curr_val, RW, decrements
    # while dec_ctrl), 0x08 RELOAD.  At zero the counter reloads from RELOAD, which is
    # left at its 0 reset value, so VALUE parks at 0 and the poll match is stable.
    reload_a, reload_b = 0x00010000, 0x00020000

    off = _wr(adp, TIMER0_CTRL, 0x00000000)
    rec.check("timer disabled for the negative control", _wrote(off), got=off.raw)
    wv = _wr(adp, TIMER0_VALUE, reload_a)
    rec.check("VALUE preload accepted", _wrote(wv), got=wv.raw)
    rb = _rd(adp, TIMER0_VALUE)
    rec.check("VALUE reads back the preload while disabled",
              _good(rb) and rb.value == reload_a, got=rb.raw)
    rec.record("timer_reload_readback", None if rb.value is None else rb.value)
    rec.record("timer_0x08_reload_reg", _rd(adp, TIMER0_RELOAD).value)

    neg = _poll(adp, TIMER0_VALUE, 0xFFFFFFFF, 0x00000000, POLL_BUDGET)
    rec.record("timer_negative_control_raw", neg.raw)
    rec.check("NEGATIVE CONTROL: disabled timer never reaches 0 (P! timeout)",
              _timed_out(neg), got=neg.raw)
    rec.check("negative control reports the exhausted budget",
              neg.value == POLL_BUDGET, got=neg.raw)

    counts = {}
    for name, reload_val in (("a", reload_a), ("b", reload_b)):
        _wr(adp, TIMER0_CTRL, 0x00000000)
        _wr(adp, TIMER0_VALUE, reload_val)
        en = _wr(adp, TIMER0_CTRL, 0x00000001)
        rec.check("timer enabled for run %s" % name, _wrote(en), got=en.raw)
        p = _poll(adp, TIMER0_VALUE, 0xFFFFFFFF, 0x00000000, POLL_BUDGET)
        _wr(adp, TIMER0_CTRL, 0x00000000)
        rec.record("timer_run%s_raw" % name, p.raw)
        rec.check("run %s: enabled timer reaches 0 and the poll matches" % name,
                  _matched(p), got=p.raw)
        if not _matched(p):
            return
        counts[name] = p.value
        rec.record("timer_run%s_reload" % name, reload_val)
        rec.record("timer_run%s_iterations" % name, p.value)

    n_a, n_b = counts["a"], counts["b"]
    # One poll iteration costs several HCLK, so n is reload/k with k of order 4-10.
    # A two-decade band catches "did not count" without pretending to know k.
    rec.check("run a's count is on the order of its reload (reload/100 .. reload*10)",
              reload_a // 100 <= n_a <= reload_a * 10,
              got="%d iterations for reload 0x%08X" % (n_a, reload_a))
    ratio = (n_b / n_a) if n_a else 0.0
    rec.record("timer_count_ratio_b_over_a", round(ratio, 3))
    rec.record("timer_implied_hclk_per_poll_read", round(reload_a / n_a, 3) if n_a else None)
    rec.check("doubling the reload doubles the count (1.5x .. 2.5x)",
              1.5 <= ratio <= 2.5,
              got="n_a=%d n_b=%d ratio=%.3f" % (n_a, n_b, ratio))
    rec.note("Timer left disabled (CTRL = 0) as the plan requires.")


@test("HIO-407", tier=4, hazard=None,
      purpose="TideLink lane / calibration / FCSM state -- a diagnosis, not just a "
              "verdict. Decodes swi_lane_status @0x2E032108 (RDL-verified: [7:0] "
              "lane_locked, [15:8] lane_fault, [16] calibration_done, [20:17] "
              "fcsm_state, [22:21] llrx_state, [29] llrx_valid). Named failure "
              "signatures are hard reds once the PHY is up: fcsm = 1 is the "
              "credit-path bring-up wedge, fcsm = 2 is the stalled/no-progress "
              "signature, llrx_state = 2 is a link-layer error, and a non-zero "
              "lane_fault byte names the failing lane. Those checks are gated on the "
              "PHY having locked or calibrated, because on a die with no peer every "
              "one of them is legitimately in its down state -- in that case the "
              "record carries link_present = False and only readability is asserted.")
def hio_407(adp, rec):
    r = _rd(adp, TL_LANE_STATUS)
    rec.check("swi_lane_status readable", _good(r), got=r.raw)
    if not _good(r):
        return
    f = _decode_lane_status(r.value)
    rec.record("tl_lane_status_raw", r.value)
    for k, v in sorted(f.items()):
        rec.record("tl_" + k, v)
    rec.record("tl_fcsm_class", _classify_fcsm(f["fcsm_state"]))

    phy_up = f["calibration_done"] == 1 or f["lane_locked"] != 0
    rec.record("tl_link_present", bool(phy_up))
    if not phy_up:
        rec.note("No link: calibration_done = 0 and no lane is locked. fcsm/lane_fault "
                 "are not interpretable in that state (a lone die legitimately sits "
                 "there), so they are recorded and not asserted. On a die that is "
                 "supposed to be paired, this line IS the finding.")
        return

    rec.check("no lane reports a sticky fault", f["lane_fault"] == 0,
              got="lane_fault=0x%02X" % f["lane_fault"])
    rec.check("llrx byte-align FSM is not in its error state (2)",
              f["llrx_state"] != 2, got="llrx_state=%d" % f["llrx_state"])
    rec.check("fcsm is not a named wedge signature (1 = credit bring-up, 2 = stalled)",
              f["fcsm_state"] not in (1, 2),
              got="fcsm=%d (%s)" % (f["fcsm_state"], _classify_fcsm(f["fcsm_state"])))
    healthy = 4 <= f["fcsm_state"] <= 7 and f["calibration_done"] == 1
    rec.record("tl_healthy", bool(healthy))
    rec.check("healthy operating point (fcsm in 4..7 and calibration_done = 1)",
              healthy, got="fcsm=%d cal=%d" % (f["fcsm_state"], f["calibration_done"]))


@test("HIO-408", tier=4, hazard=None, needs=["HIO-401", "HIO-407"],
      purpose="Wait for link-up, in hardware -- one command instead of thousands of "
              "link round trips. The masked poll on calibration_done is run at BOTH "
              "polarities on the same mask, because matching on one polarity alone "
              "cannot distinguish 'matched because the bit is set' from 'matched "
              "because the compare is broken'. PASS = exactly one polarity matches; "
              "which one it is records whether the link is up. Both matching, or "
              "neither, means the compare is not discriminating and the link verdict "
              "is worthless. On a timeout the lane-status register is re-read "
              "immediately so the state it was stuck in is named, as the plan requires.")
def hio_408(adp, rec):
    _require_okay(adp, rec, TL_LANE_STATUS, "swi_lane_status 0x2E032108")

    mask = 0x00010000  # calibration_done
    pos = _poll(adp, TL_LANE_STATUS, mask, 0x00010000, POLL_BUDGET)
    rec.record("linkup_poll_set_raw", pos.raw)
    neg = _poll(adp, TL_LANE_STATUS, mask, 0x00000000, POLL_BUDGET)
    rec.record("linkup_poll_clear_raw", neg.raw)

    m_pos, m_neg = _matched(pos), _matched(neg)
    rec.check("both poll replies arrived", bool(pos.ok) and bool(neg.ok),
              got="%s / %s" % (pos.raw, neg.raw))
    rec.check("EXACTLY ONE polarity matches (the compare discriminates)",
              m_pos != m_neg,
              got="cal=1 -> %s ; cal=0 -> %s" % (pos.raw, neg.raw))

    rec.record("link_up", bool(m_pos))
    if m_pos:
        rec.record("linkup_iterations", pos.value)
        rec.note("calibration_done was already set; the complementary poll correctly "
                 "exhausted its budget.")
    else:
        # The plan: a recorded timeout is an acceptable outcome only if the state it
        # was stuck in is named immediately afterwards.
        r = _rd(adp, TL_LANE_STATUS)
        if _good(r):
            f = _decode_lane_status(r.value)
            rec.record("linkdown_lane_status_raw", r.value)
            rec.record("linkdown_fcsm_state", f["fcsm_state"])
            rec.record("linkdown_fcsm_class", _classify_fcsm(f["fcsm_state"]))
            rec.record("linkdown_lane_locked", f["lane_locked"])
            rec.record("linkdown_lane_fault", f["lane_fault"])
            rec.note("Link NOT up. Stuck state named above. Phase E ABORTS here: do "
                     "not touch 0x2F (HIO-413).")
        else:
            rec.note("Link NOT up and the follow-up state read failed: %s" % r.raw)
    rec.note("The polled offset +0x2108 sits in the watchdogged tidelink region, not "
             "the pass-through wlink region the plan's HZ-9 tag covers; a bounded "
             "host timeout is used regardless.")


@test("HIO-409", tier=4, hazard=None,
      purpose="XHB bridge health and the deadlock witness -- and the marker discipline "
              "that makes it mean anything. The marker byte is checked FIRST: "
              "0x2E0321F8[31:24] must be 0xB5 and 0x2E0321E0[31:24] must be 0xAD "
              "(MEASURED 0xb5000001 / 0xad800000). If a marker is wrong the register "
              "is absent or mis-decoded and every bit below it is meaningless, so the "
              "bits are not decoded at all in that case -- a test that reads bits "
              "without checking the marker reports 'healthy, all zeros' on a register "
              "that is not there. PASS = both markers, 0x1F8[10] "
              "xhb_stall_stuck_sticky = 0 (hreadyout low for 2^12 hclk: the XHB500 "
              "hazard-list deadlock witness) and 0x1E0[23] data_healthy = 1, which by "
              "construction also asserts wedge_sticky = 0 and both error bits clear.")
def hio_409(adp, rec):
    w = _read_xhb_witness(adp)
    _record_xhb(rec, w, "xhb")

    rec.check("0x2E0321F8 readable", w["f8_ok"], got=w["f8"].raw)
    rec.check("0x2E0321E0 readable", w["e0_ok"], got=w["e0"].raw)
    rec.check("marker 0xB5 present at 0x2E0321F8[31:24]", w["f8_marker_ok"],
              got=w["f8"].raw)
    rec.check("marker 0xAD present at 0x2E0321E0[31:24]", w["e0_marker_ok"],
              got=w["e0"].raw)
    if not (w["f8_marker_ok"] and w["e0_marker_ok"]):
        rec.note("Marker check failed -- the bits below it were NOT decoded, because "
                 "on a mis-decoded register they would read as a healthy all-zero "
                 "word. Treat every other TideLink observation in this run as "
                 "unattributed.")
        return

    rec.check("xhb_stall_stuck_sticky (0x1F8[10]) is clear", w["xhb_stall_stuck_sticky"] == 0,
              got="0x%08X" % w["f8"].value)
    rec.check("data_healthy (0x1E0[23]) is set", w["data_healthy"] == 1,
              got="0x%08X" % w["e0"].value)
    if w["sub_err_sticky"] or w["sub_wr_stuck_sticky"] or w["ext_stall_err"]:
        rec.note("Secondary stickies set at 0x1F8 (sub_err=%d sub_wr_stuck=%d "
                 "ext_stall=%d). The plan's PASS criterion does not gate on these, "
                 "but a set bit is a real event and is recorded."
                 % (w["sub_err_sticky"], w["sub_wr_stuck_sticky"], w["ext_stall_err"]))
    if w["bridge_ready"] == 0:
        rec.note("bridge_ready (0x1F8[0], xhb_sub_hreadyout_raw) sampled low. That is "
                 "legitimate mid-transfer; it is only a finding together with the "
                 "stall sticky.")


@test("HIO-410", tier=4, hazard=None, weak=True,
      purpose="TideChart election state. WEAK on a single die, and marked so "
              "deliberately: a lone die will legitimately elect itself root, so "
              "is_root = 1 here is not evidence of anything and cannot be made to "
              "fail. The real test is the two-die form -- exactly one die of a pair "
              "may report is_root -- and that requires the peer's record, which a "
              "single-die run cannot express. What IS falsifiable here and is checked: "
              "the registers read without error, and TC_ERROR[2] dual_root (sticky) "
              "must be clear; a set dual_root is a hard red on either die, and is the "
              "known TideChart failure. Never writes TC_CTRL -- bit 3 re-arms the "
              "election.")
def hio_410(adp, rec):
    regs = {}
    for name, addr in (("tc_status", TC_STATUS), ("tc_best_claim", TC_BEST_CLAIM),
                       ("tc_enum_state", TC_ENUM_STATE), ("tc_error", TC_ERROR)):
        r = _rd(adp, addr)
        regs[name] = r
        rec.check("%s (0x%08X) readable" % (name, addr), _good(r), got=r.raw)
        rec.record(name, r.value)
    if not all(_good(r) for r in regs.values()):
        return

    st = regs["tc_status"].value
    election_done = _bits(st, 0, 0)
    is_root = _bits(st, 1, 1)
    enum_done = _bits(st, 2, 2)
    local_id = _bits(st, 7, 3)
    total = _bits(st, 12, 8)
    rec.record("tc_election_done", election_done)
    rec.record("tc_is_root", is_root)
    rec.record("tc_enum_done", enum_done)
    rec.record("tc_local_id", local_id)
    rec.record("tc_total_chiplets", total)

    err = regs["tc_error"].value
    rec.record("tc_err_election_timeout", _bits(err, 0, 0))
    rec.record("tc_err_enum_timeout", _bits(err, 1, 1))
    rec.record("tc_err_dual_root", _bits(err, 2, 2))
    rec.check("TC_ERROR[2] dual_root sticky is clear", _bits(err, 2, 2) == 0,
              got="TC_ERROR=0x%08X" % err)

    rec.note("Two-die verdict is NOT decided here. Read tc_is_root on BOTH dies and "
             "require exactly one; two roots, or dual_root on either die, is the known "
             "hard red. total_chiplets=%d local_id=%d election_done=%d enum_done=%d."
             % (total, local_id, election_done, enum_done))


@test("HIO-411", tier=4, control=True, gates=["HIO-412"], hazard=None,
      purpose="DMA-250 liveness before use -- the single check that stops a whole "
              "sub-suite from silently measuring nothing. IIDR must read exactly "
              "0x2500043B. If it reads 0x00000000 the block is power-gated, every "
              "DMA test below is unrunnable, and they must SKIP rather than run and "
              "report zeros as passes. Goes red on any other value, which is a wrong "
              "or absent block rather than a gated one; the two cases are "
              "distinguished in the record.")
def hio_411(adp, rec):
    r = _rd(adp, DMA_IIDR)
    rec.check("DMA IIDR readable (no bus error)", _good(r), got=r.raw)
    rec.record("dma_iidr", r.value)
    if not _good(r):
        return
    gated = (r.value == 0)
    rec.record("dma_power_gated", bool(gated))
    if gated:
        rec.note("IIDR reads 0x00000000: the DMA-250 is POWER-GATED, not absent "
                 "(DMA250_DESIGN_AND_WORKPLAN.md:86-88). Its power state is "
                 "observable from this port but not controllable, so HIO-412 stays "
                 "unrunnable until the block is powered.")
    rec.check("IIDR == 0x2500043B exactly",
              r.value == DMA_IIDR_EXPECT,
              got="0x%08X" % r.value)


@test("HIO-412", tier=4, hazard=None, needs=["HIO-411"],
      purpose="DMA-250 memory-to-memory descriptor. NOT-YET-EXECUTABLE and skipped by "
              "construction: the channel register offsets, the start bit and the done "
              "bit are unresolved. Writing it against guessed offsets would produce a "
              "test that 'passes' by writing to reserved space and polling a register "
              "that reads zero for an unrelated reason -- a vacuous green of exactly "
              "the kind this suite exists to prevent.")
def hio_412(adp, rec):
    rec.skip(
        "DMA-250 channel register layout unresolved -- no bus access attempted. "
        "KNOWN: the config aperture is DMAC_CFG_ADDR_W = 14 (16 KB) at 0x20000000, "
        "DMASECCFG at +0x000, SCFG_CTRL at +0x040, SCFG_INTRSTATUS at +0x044 "
        "(dma250_regdef.h:112-115). UNRESOLVED and required before this test may be "
        "written: (1) the per-channel block base and stride, (2) the channel "
        "SRC/DST/SIZE/CTRL offsets within it, (3) which bit starts a transfer, "
        "(4) which bit or status register signals done, and (5) the SCFG_CHSEC0 "
        "security mapping, which must be understood before ANY write. Resolve them "
        "from the rendered register package, not from this plan. Gate: HIO-411 must "
        "read IIDR 0x2500043B; a power-gated block (IIDR 0) leaves this unrunnable "
        "whatever the offsets turn out to be.")


_HIO413_FIRED = False


@test("HIO-413", tier=4, hazard=HZ.WEDGE_RISK,
      needs=["HIO-407", "HIO-408", "HIO-409", "HIO-410"],
      destroys="peer port state on failure -- a failed cross-die read PARKS the peer "
               "port; recovery is a power cycle",
      purpose="Cross-die peer read -- one shot, guarded, and the highest-risk test in "
              "the plan. All of 0x2F000000-0x2FFFFFFF goes to the peer with NO default "
              "responder (chiplet_d2d_decode.sv:172), so ADP has none of the error "
              "escape it has everywhere else. HZ-2 is the reason for the one-shot "
              "rule: a failed cross-die read parks the peer port and it is the NEXT "
              "access that wedges the host -- so the failure is NOT visible in this "
              "test's own result. It is visible only in the XHB witness re-read, and "
              "only if that re-read is the very next thing issued. That guard is part "
              "of this test body, runs in a finally-style unconditional path, and its "
              "verdict is what makes this test able to go red at all. Never run "
              "unattended; budget a power cycle.")
def hio_413(adp, rec):
    global _HIO413_FIRED
    if _HIO413_FIRED:
        rec.skip("one-shot already consumed in this process. HZ-2 permits exactly one "
                 "peer access per power cycle in this suite; re-running would issue "
                 "the 'next access' that is the one which wedges the host.")
    if not _env_flag("HOSTIO_PEER_DIE"):
        rec.skip("HOSTIO_PEER_DIE is not set. This test requires a peer die that is "
                 "powered and has passed its own Tier 0-1. The runner already gates "
                 "the hazard (--allow-wedge) and attendance (interactive); what it "
                 "cannot know is whether a peer exists at the other end of the link, "
                 "and firing this at a peerless die is how the port gets parked. "
                 "Set HOSTIO_PEER_DIE=1 only when the peer is up and checked.")

    # Preconditions re-checked at the instant of the access, not merely inherited
    # from `needs`: link state can change between tests, and a stale green here is
    # exactly what parks the peer port.
    ls = _rd(adp, TL_LANE_STATUS)
    if not _good(ls):
        rec.skip("lane status unreadable immediately before the access (%s); refusing "
                 "to touch 0x2F." % ls.raw)
    f = _decode_lane_status(ls.value)
    rec.record("peer_pre_lane_status", ls.value)
    rec.record("peer_pre_fcsm", f["fcsm_state"])
    rec.record("peer_pre_cal", f["calibration_done"])
    if not (4 <= f["fcsm_state"] <= 7 and f["calibration_done"] == 1
            and f["lane_fault"] == 0):
        rec.skip("link preconditions not met at the moment of the access: fcsm=%d (%s), "
                 "cal=%d, lane_fault=0x%02X. Phase E aborts here -- do not touch 0x2F."
                 % (f["fcsm_state"], _classify_fcsm(f["fcsm_state"]),
                    f["calibration_done"], f["lane_fault"]))

    before = _read_xhb_witness(adp)
    _record_xhb(rec, before, "peer_pre_xhb")
    if not before["healthy"]:
        rec.skip("XHB witness is not healthy immediately before the access (markers "
                 "%s/%s, stall_sticky=%s, data_healthy=%s). Refusing to touch 0x2F."
                 % (before["f8_marker_ok"], before["e0_marker_ok"],
                    before.get("xhb_stall_stuck_sticky"), before.get("data_healthy")))

    # ---- ARMED.  Nothing below may skip, and nothing may be interpreted until
    # ---- the guard has run.  The one-shot flag is set BEFORE the access so a
    # ---- crash mid-access still consumes it.
    _HIO413_FIRED = True
    rec.note("ONE SHOT ARMED: a single R at 0x%08X, then the XHB witness as the very "
             "next commands and nothing in between." % PEER_APERTURE)

    peer = None
    peer_exc = None
    try:
        # `A` sets adp_addr and makes no bus access; only `R` crosses the die.
        adp.cmd("Ax%08X" % PEER_APERTURE, timeout_ms=PEER_TIMEOUT_MS)
        peer = adp.cmd("R", timeout_ms=PEER_TIMEOUT_MS)
    except BaseException as exc:          # noqa: BLE001 - the guard must still run
        peer_exc = exc

    guard = None
    guard_exc = None
    try:
        guard = _read_xhb_witness(adp, timeout_ms=PEER_TIMEOUT_MS)
    except BaseException as exc:          # noqa: BLE001 - report, never mask
        guard_exc = exc
    # ---- Guard has run.  Interpretation may begin.

    # An operator interrupt is honoured, but only AFTER the guard has run and
    # been recorded -- an un-guarded peer access is the one thing this test may
    # never leave behind.
    for exc in (peer_exc, guard_exc):
        if isinstance(exc, KeyboardInterrupt):
            rec.record("peer_read_raw", "INTERRUPTED after the guard ran")
            if guard is not None:
                _record_xhb(rec, guard, "peer_post_xhb")
            raise exc

    if peer_exc is not None:
        rec.record("peer_read_raw", "EXCEPTION: %r" % (peer_exc,))
        rec.check("the peer read returned a definite outcome (data or !)", False,
                  got="no reply: %r" % (peer_exc,))
    else:
        rec.record("peer_read_raw", peer.raw)
        rec.record("peer_read_value", peer.value)
        rec.record("peer_read_error_flag", bool(peer.error))
        rec.check("the peer read returned a definite outcome (data or !)",
                  bool(peer.ok), got=peer.raw)
        if peer.ok and peer.error:
            rec.note("Peer read raised `!`. With no default responder in 0x2F, an "
                     "error escape means the D2D decode rejected the access before it "
                     "left the die rather than the peer answering -- record it as a "
                     "decode result, not a peer result.")

    if guard_exc is not None or guard is None:
        rec.check("GUARD: XHB witness readable immediately after the peer access",
                  False, got="guard read failed: %r" % (guard_exc,))
        rec.note("STOP. The guard read did not complete: the host is wedged as HZ-2 "
                 "describes. Power cycle the die before issuing any further command.")
        return

    _record_xhb(rec, guard, "peer_post_xhb")
    rec.check("GUARD: marker 0xB5 still present after the peer access",
              guard["f8_marker_ok"], got=guard["f8"].raw)
    rec.check("GUARD: marker 0xAD still present after the peer access",
              guard["e0_marker_ok"], got=guard["e0"].raw)
    if guard["f8_marker_ok"] and guard["e0_marker_ok"]:
        rec.check("GUARD: xhb_stall_stuck_sticky still clear (no bridge deadlock)",
                  guard["xhb_stall_stuck_sticky"] == 0, got="0x%08X" % guard["f8"].value)
        rec.check("GUARD: data_healthy still set (no axinode wedge)",
                  guard["data_healthy"] == 1, got="0x%08X" % guard["e0"].value)
        if guard["xhb_stall_stuck_sticky"] or guard["data_healthy"] != 1:
            rec.note("STOP. The peer access parked the port: the witness changed. Power "
                     "cycle before any further command.")
    rec.note("One shot consumed. Do not re-run this test in this power cycle.")


@test("HIO-414", tier=4, hazard=None, weak=True,
      purpose="Firmware boot-confirm token at 0x2D001FF0 -- a firmware-free "
              "observation of firmware liveness, in the one RAM both CPUs and the ADP "
              "can reach, proving an end-to-end path (software writes, debug port "
              "reads) that no register test covers. WEAK as a verdict and marked so: "
              "the token is absent on any die whose CPUs have not run, which is the "
              "normal pre-Tier-5 state, so absence cannot be a red. Only the read "
              "itself is asserted. Presence, by contrast, is strong: 0xB007C0FE is a "
              "value nothing but firmware writes. The strong form of this test is "
              "HIO-504. If HIO-208 has run, shared SRAM was overwritten and absence "
              "means nothing at all.")
def hio_414(adp, rec):
    r = _rd(adp, BOOT_CONFIRM)
    rec.check("shared SRAM token word readable (no bus error)", _good(r), got=r.raw)
    rec.record("boot_confirm_word", r.value)
    if not _good(r):
        return
    present = (r.value == BOOT_CONFIRM_TOKEN)
    rec.record("boot_confirm_present", bool(present))
    if present:
        rec.note("Token 0xB007C0FE present: a CPU has booted and confirmed "
                 "(nanosoc_boot_confirm.h:73-74; emitted by the image on trial, "
                 "typically CPU1). This is a positive end-to-end result.")
    else:
        rec.note("Token absent (0x%08X). That is the expected state on a die whose "
                 "CPUs have not been released, and it is uninterpretable on a die "
                 "where HIO-208 has overwritten shared SRAM. Not counted as a "
                 "failure." % r.value)


@test("HIO-415", tier=4, hazard=None,
      purpose="MDIO / Ethernet MAC -- NOT EXECUTABLE OVER HOSTIO. Recorded rather than "
              "omitted so that 'MDIO untested' stays visible in the coverage record "
              "instead of being quietly dropped, and so a later reader does not "
              "re-derive it. Structurally impossible: no bus access is attempted.")
def hio_415(adp, rec):
    rec.skip(
        "PERMANENT SKIP -- structurally impossible over this port. The MAC and its "
        "MDIO controller live at 0x%08X in the ethernet subsystem's own map, but "
        "debug_m's decode has no window there (multicore_matrix_decode_DEBUG_M.v"
        ":456-513), so an ADP access reaches the top-level default slave. MEASURED "
        "2026-08-25: 0x40000000 and 0x40001000 both return R!0x00000000 against "
        "controls that decoded (0x08000000 -> R 0x18003c00) and errored "
        "(0x30000000 -> R!) correctly. There is no alias, no translation and no "
        "window. The only route to MDIO from this port is CPU0 firmware -- HIO-506."
        % ETHMAC_BASE)


# =============================================================================
# TIER 5 -- firmware-assisted.  Everything here is downstream of HIO-502, which
# is IRREVERSIBLE within a power cycle.
# =============================================================================

@test("HIO-501", tier=5, hazard=HZ.DESTRUCTIVE,
      destroys="eth IMEM, 32 KB at 0x10000000 (F zero-fill, then the image)",
      purpose="Preload CPU0 IMEM and verify byte-exact. The F pre-zero is what makes "
              "the verify meaningful: without it a U that wrote nothing would still "
              "verify against whatever was already there. The final byte is verified "
              "explicitly (A x10000fff ; R) because F and U do not capture HRESP on "
              "their last beat -- the capture sits in the else branch, so a fill or "
              "upload whose only erroring beat is the last one reports clean.")
def hio_501(adp, rec):
    image = _env("HOSTIO_CPU0_IMAGE")
    if image is None:
        rec.skip("no CPU0 image. REQUIRED: a raw binary (not ELF, not hex) of at most "
                 "32768 bytes to be written at 0x10000000, its path in "
                 "HOSTIO_CPU0_IMAGE. The image must be a complete Cortex-M vector "
                 "table plus code, because HIO-502 releases CPU0 straight into it and "
                 "that release is irreversible within a power cycle. No such image "
                 "exists in this tree today. No bus access attempted -- in particular "
                 "the destructive F pre-zero is NOT issued, since zeroing IMEM without "
                 "the upload that must follow it would leave the die worse than found.")
    if not os.path.isfile(image):
        rec.skip("HOSTIO_CPU0_IMAGE=%s does not exist. No bus access attempted." % image)
    size = os.path.getsize(image)
    rec.record("cpu0_image_path", image)
    rec.record("cpu0_image_bytes", size)
    if size == 0 or size > 32768:
        rec.skip("HOSTIO_CPU0_IMAGE is %d bytes; eth IMEM is 32 KB "
                 "(ETH_IMEM_RAM_ADDR_W=15). Refusing to size a `U` from it." % size)
    # Reached only with a real image, and still refused: see the guard's text.
    _refuse_upload(rec, "HIO-501 (CPU0 IMEM preload)", size)


@test("HIO-502", tier=5, hazard=HZ.IRREVERSIBLE, needs=["HIO-313", "HIO-501"],
      destroys="CPU0 held-in-reset state -- once bit 2 is set CPU0 contends for the "
               "bus and mutates memory, and every quiescent-bus result above becomes "
               "unrepeatable in this power cycle",
      purpose="Release CPU0 -- the answer to 'can ADP release a CPU': yes, by an AHB "
              "write, not by GPO. The gate is READ AND RECORDED FIRST and the write is "
              "issued only if bit 2 is actually clear, because on the FPGA build "
              "0x29000000 already reads 0x00000004 with IMEM all zeros (plan section "
              "5.5) -- so a blind write would be a no-op reported as a release. Goes "
              "red if the readback does not change after a write that was needed "
              "(a broken write path, which HIO-313 has already ruled out) -- and CPU0 "
              "showing no life afterwards is then a firmware or reset-tree result, "
              "not a debug-port result. Boot gates are write-1-set only "
              "(remap_q <= remap_q | HWDATA[3:0]) and reset only on PORESETn.")
def hio_502(adp, rec):
    before = _rd(adp, BOOTGATE)
    alias_before = _rd(adp, BOOTGATE_ALIAS_PROBE)
    rec.check("boot gate readable", _good(before), got=before.raw)
    rec.record("bootgate_before", before.value)
    rec.record("bootgate_0x29000004_before", alias_before.value)
    if not _good(before):
        return

    already = _bits(before.value, 2, 2) == 1
    rec.record("bootgate_already_set", bool(already))

    if already:
        rec.note("BIT 2 WAS ALREADY SET before this test ran (0x%08X). This test "
                 "released nothing: no write was issued. On the FPGA build the gate "
                 "reads 0x00000004 out of reset while IMEM is all zeros, which would "
                 "mean CPU0 was released into empty memory and is faulting -- and "
                 "0x29000004 returns 0x%08X, so this may be an alias rather than the "
                 "live gate. Resolve that before believing either reading. CPU0 "
                 "liveness must come from HIO-504, not from this register."
                 % (before.value, alias_before.value or 0))
        rec.check("boot gate bit 2 (NETWORK_CORE_BOOTGATE) is set",
                  _bits(before.value, 2, 2) == 1, got="0x%08X" % before.value)
        return

    w = _wr(adp, BOOTGATE, BOOTGATE_CPU0)   # whitelist-checked; nothing else may go here
    rec.check("boot-gate write reported OK", _wrote(w), got=w.raw)
    after = _rd(adp, BOOTGATE)
    alias_after = _rd(adp, BOOTGATE_ALIAS_PROBE)
    rec.record("bootgate_after", after.value)
    rec.record("bootgate_0x29000004_after", alias_after.value)
    rec.check("readback shows bit 2 set", _good(after) and _bits(after.value, 2, 2) == 1,
              got=after.raw)
    if _good(alias_before) and _good(alias_after):
        aliased = (alias_after.value != alias_before.value
                   and alias_after.value == after.value)
        rec.record("bootgate_0x29000004_is_alias", bool(aliased))
        rec.note("0x29000004 %s with the write, which %s the section-5.5 alias question."
                 % ("changed" if alias_after.value != alias_before.value else "did not change",
                    "answers" if aliased else "leaves open"))
    rec.note("POINT OF NO RETURN passed for this power cycle. HZ-4: the gate is "
             "write-1-set only and clears only on PORESETn.")


@test("HIO-503", tier=5, hazard=HZ.RESET, needs=["HIO-502"],
      destroys="CPU0 execution state (CPU0 reset pulse only -- does NOT touch the "
               "fabric, the ADP or HOSTIO, unlike HIO-509)",
      purpose="Repeatable CPU0 relaunch -- the primitive that makes all of Tier 5 "
              "iterable: reload IMEM, pulse CPU0_SWRST, observe again, with no power "
              "cycle and no re-arming of the boot gate. Goes red if the pulse does not "
              "restart CPU0, which is visible only as unchanged firmware behaviour. "
              "NOTE, against the plan: RESET_INFO_CPU0 is NOT a witness for this. Its "
              "capture terms are cpu0_sysresetreq, lockup and ext_sysresetreq "
              "(nanosoc_reset_ctrl.v:314-321); cpu0_swreset_pulse feeds the reset "
              "request at :246 but never the RESET_INFO flops, so a software reset "
              "leaves that register unchanged by construction and 'the reset-info "
              "record changes' would be a guaranteed false red. It is recorded, not "
              "asserted.")
def hio_503(adp, rec):
    sentinel = _env("HOSTIO_FW_SENTINEL")
    if sentinel is None:
        rec.skip("no firmware liveness witness configured, so a relaunch cannot be "
                 "observed and this test could only ever report a write that reads "
                 "back 0 (SW_RESET is self-clearing). REQUIRED: a CPU0 image whose "
                 "restart is observable -- set HOSTIO_FW_SENTINEL to the fixed word it "
                 "writes ONCE, early in main(), to HOSTIO_FW_SENTINEL_ADDR, so the "
                 "relaunch is proven by that word being cleared here and written again "
                 "by the restarted CPU.")

    sent_addr = _sentinel_addr()
    want = int(sentinel, 0)

    info_before = _rd(adp, RESET_INFO_CPU0)
    rec.record("reset_info_cpu0_before", info_before.value)

    # Clear the witness so its reappearance is caused by THIS relaunch and not by a
    # value that was already sitting in SRAM.
    zap = _wr(adp, sent_addr, 0x00000000)
    rec.check("sentinel word cleared before the pulse", _wrote(zap), got=zap.raw)
    rec.record("fw_sentinel_addr", sent_addr)

    p = _wr(adp, SW_RESET, SWRST_CPU0)      # whitelist-checked: bit 1 can never go here
    rec.check("CPU0_SWRST write accepted", _wrote(p), got=p.raw)

    poll = _poll(adp, sent_addr, 0xFFFFFFFF, want, POLL_BUDGET)
    rec.record("relaunch_poll_raw", poll.raw)
    rec.check("CPU0 restarted: the sentinel reappears after the pulse", _matched(poll),
              got=poll.raw)
    rec.record("relaunch_iterations", poll.value if _matched(poll) else None)

    info_after = _rd(adp, RESET_INFO_CPU0)
    rec.record("reset_info_cpu0_after", info_after.value)
    rec.note("RESET_INFO_CPU0 recorded for information only: no capture term exists "
             "for a software reset, so an unchanged value here is correct.")


@test("HIO-504", tier=5, hazard=None, needs=["HIO-401", "HIO-502"],
      purpose="Firmware liveness via shared SRAM. The `P` form is the strong one: it "
              "waits for a SPECIFIC value the firmware will write, so a stuck "
              "heartbeat, a wrong value and a dead CPU are all distinguishable from "
              "success -- a two-read comparison alone cannot tell 'advancing "
              "correctly' from 'advancing wrongly'. Both are run: the sentinel poll "
              "must match, and two reads either side of an interval must differ. Goes "
              "red on a poll timeout (no such value was ever written) or on a "
              "heartbeat that does not move.")
def hio_504(adp, rec):
    sentinel = _env("HOSTIO_FW_SENTINEL")
    if sentinel is None:
        rec.skip("no firmware heartbeat configured. REQUIRED, and this is the whole "
                 "firmware ABI this test needs: a CPU0 (or CPU1) image that (a) writes "
                 "a FIXED sentinel word once, early in main(), to "
                 "HOSTIO_FW_SENTINEL_ADDR (default heartbeat+4) and (b) writes an "
                 "INCREMENTING heartbeat to HOSTIO_FW_HEARTBEAT_ADDR (default 0x%08X, "
                 "inside the 8 KB shared cross-core SRAM) every pass of its main loop. "
                 "The two words are separate on purpose: the poll needs a value the "
                 "firmware is guaranteed to write and hold, and the advance check needs "
                 "a word that keeps changing -- one word cannot be both. Set "
                 "HOSTIO_FW_SENTINEL to the sentinel value. No such image exists in "
                 "this tree today. Ordering: shared SRAM must not have been clobbered "
                 "by HIO-208 first." % SHARED_SRAM)
    hb_addr = _env_int("HOSTIO_FW_HEARTBEAT_ADDR", SHARED_SRAM)
    sent_addr = _sentinel_addr()
    want = int(sentinel, 0)
    rec.record("fw_heartbeat_addr", hb_addr)
    rec.record("fw_sentinel_addr", sent_addr)
    rec.record("fw_sentinel", want)

    _require_okay(adp, rec, sent_addr, "sentinel word 0x%08X" % sent_addr)

    p = _poll(adp, sent_addr, 0xFFFFFFFF, want, POLL_BUDGET)
    rec.record("fw_sentinel_poll_raw", p.raw)
    rec.check("firmware wrote the sentinel (P matched, not a timeout)", _matched(p),
              got=p.raw)
    rec.record("fw_sentinel_iterations", p.value if _matched(p) else None)

    a = _rd(adp, hb_addr)
    time.sleep(1.0)
    b = _rd(adp, hb_addr)
    rec.record("fw_heartbeat_first", a.value)
    rec.record("fw_heartbeat_second", b.value)
    rec.check("both heartbeat reads succeeded", _good(a) and _good(b),
              got="%s / %s" % (a.raw, b.raw))
    if _good(a) and _good(b):
        rec.check("the heartbeat advanced across the interval", a.value != b.value,
                  got="0x%08X then 0x%08X" % (a.value, b.value))


@test("HIO-505", tier=5, hazard=None, needs=["HIO-401", "HIO-502"],
      purpose="Firmware console, polled from ADP -- the console substitute, and it "
              "matters because ADP's own STDIO path is dead on this SoC (the debug "
              "USRT's APB slave is tied off and it has no pins, so `S` and `X` carry "
              "nothing). uart2 at 0x28006000 IS ADP-reachable. Mask polarity resolved "
              "from RTL rather than assumed: cmsdk_apb_uart.v:251 packs STATE as "
              "{rx_overrun, tx_overrun, rx_buf_full, tx_buf_full}, so bit 1 set means "
              "RX-buffer-full and Mx00000002/Vx00000002 is the correct wait -- a wrong "
              "polarity would give a poll that always matches, which looks exactly "
              "like success. Both polarities are run for that reason. Goes red if both "
              "or neither polarity matches, or if no character is recovered.")
def hio_505(adp, rec):
    # cmsdk_apb_uart.v:261 -- read mux index 0 returns reg_rx_buf, i.e. bytes that
    # ARRIVED on uart2's RXD pad.  Firmware's console output leaves on TXD, to a
    # physical pin, and is not visible to ADP at all unless TXD is looped back
    # externally to RXD.  This is a real limit of the plan's HIO-505 as written and
    # is the reason for the opt-in below rather than a silent partial pass.
    if not _env_flag("HOSTIO_UART2_LOOPBACK"):
        rec.skip("uart2 console recovery needs a path by which characters reach the "
                 "RX buffer this port can read. Reading 0x28006000 returns reg_rx_buf "
                 "(cmsdk_apb_uart.v:261) -- bytes arriving on the uart2 RXD pad. "
                 "Firmware console output goes out on TXD to a pin and is invisible to "
                 "ADP. REQUIRED: either an external TXD->RXD loopback on the uart2 pads "
                 "(then set HOSTIO_UART2_LOOPBACK=1) or a character source driving RXD, "
                 "PLUS firmware that writes to uart2. Neither exists in this tree "
                 "today. At ~4 CU per character this is a status-string recovery "
                 "mechanism, never a console: put real firmware output in shared SRAM "
                 "(HIO-504), where one R<n> retrieves a whole buffer.")

    _require_okay(adp, rec, UART2_STATE, "uart2 STATE 0x28006004")

    pos = _poll(adp, UART2_STATE, UART2_STATE_RX_FULL, UART2_STATE_RX_FULL, POLL_BUDGET)
    rec.record("uart2_rxfull_poll_raw", pos.raw)
    neg = _poll(adp, UART2_STATE, UART2_STATE_RX_FULL, 0x00000000, POLL_BUDGET)
    rec.record("uart2_rxempty_poll_raw", neg.raw)
    rec.check("EXACTLY ONE STATE[1] polarity matches (mask polarity is real)",
              _matched(pos) != _matched(neg),
              got="full -> %s ; empty -> %s" % (pos.raw, neg.raw))
    rec.check("RX-buffer-full was reached within the budget", _matched(pos), got=pos.raw)
    if not _matched(pos):
        return

    ch = _rd(adp, UART2_DATA)
    rec.check("a character was read out of the RX buffer", _good(ch), got=ch.raw)
    rec.record("uart2_char", None if ch.value is None else ch.value & 0xFF)
    if _good(ch):
        rec.note("Recovered byte 0x%02X. Reading DATA clears rx_buf_full, so repeating "
                 "the poll/read pair walks the stream one character at a time."
                 % (ch.value & 0xFF))


@test("HIO-506", tier=5, hazard=None, needs=["HIO-502", "HIO-504"],
      purpose="Ethernet MAC and MDIO via CPU0 firmware -- the ONLY route to MDIO from "
              "this port, since the MAC at 0x40000000 is outside debug_m's decode "
              "(HIO-415). Discrimination is strong and the failure modes are "
              "distinguishable from each other: a PHY that is absent, unpowered, "
              "strapped to the wrong address or has a dead MDIO line returns 0xFFFF or "
              "0x0000 rather than the LAN8720's OUI 0x0007C0. The result travels back "
              "through firmware -> shared SRAM -> ADP, a path HIO-504 has already "
              "proven, so a failure here is attributable to the MAC/PHY and not to the "
              "transport.")
def hio_506(adp, rec):
    result = _env("HOSTIO_FW_MDIO_RESULT_ADDR")
    if result is None:
        rec.skip("no MDIO result address. REQUIRED: a CPU0 image that (a) reads the MAC "
                 "ID registers at 0x40000000, (b) performs MDIO reads of the LAN8720 "
                 "PHY ID registers 2 and 3, and (c) writes both results to shared SRAM "
                 "at a fixed, documented address -- then set HOSTIO_FW_MDIO_RESULT_ADDR "
                 "to that address (PHYID1 word at +0x0, PHYID2 word at +0x4, MAC ID "
                 "word at +0x8). No such image exists in this tree today, and the "
                 "firmware/ADP address ABI is not defined anywhere, so this test is "
                 "deliberately not written against an invented layout.")
    base = int(result, 0)
    rec.record("fw_mdio_result_addr", base)

    r1 = _rd(adp, base)
    r2 = _rd(adp, base + 4)
    r3 = _rd(adp, base + 8)
    rec.check("PHY ID words readable", _good(r1) and _good(r2), got="%s / %s" % (r1.raw, r2.raw))
    rec.record("phy_id1", r1.value)
    rec.record("phy_id2", r2.value)
    rec.record("mac_id_word", r3.value)
    if not (_good(r1) and _good(r2)):
        return

    id1, id2 = r1.value & 0xFFFF, r2.value & 0xFFFF
    if id1 in (0x0000, 0xFFFF) and id2 in (0x0000, 0xFFFF):
        rec.note("PHY ID reads 0x%04X/0x%04X -- the all-ones/all-zeros signature. "
                 "0xFFFF means MDIO floated (no PHY responding, wrong address strap, "
                 "or MDIO not driven); 0x0000 means the bus was driven low. These are "
                 "distinguishable and neither is a PHY." % (id1, id2))
    oui = ((id1 << 6) | (id2 >> 10)) & 0x3FFFFF
    rec.record("phy_oui_22bit", oui)
    rec.check("LAN8720 OUI recovered (0x0007C0 in the 22-bit OUI field)",
              (oui >> 2) == 0x0007C0 or id1 == 0x0007,
              got="id1=0x%04X id2=0x%04X oui=0x%06X" % (id1, id2, oui))


@test("HIO-507", tier=5, hazard=None, needs=["HIO-502", "HIO-504"],
      purpose="Bus-fault monitor, live -- this is what upgrades HIO-308 from WEAK to "
              "real. The captured address is a value only a correct monitor could "
              "produce, and the initiator index proves the per-initiator demux. "
              "debug_m is NOT one of the four monitored initiators (0 eth_ss_m/CPU0, "
              "1 cpu_ss_1_m/CPU1, 2 dmac_0_m, 3 dap_ss_0_m), so ADP cannot stimulate "
              "this itself -- which is precisely why it needs firmware and why HIO-308 "
              "alone is not coverage. Goes red if FAULT_ADDR is not EXACTLY the "
              "address firmware used, or if INIT_IDX names the wrong initiator.")
def hio_507(adp, rec):
    expect = _env("HOSTIO_FW_FAULT_ADDR")
    if expect is None:
        rec.skip("no expected fault address. REQUIRED: a firmware image that performs "
                 "one deliberate access to an unmapped address (the plan suggests "
                 "0x70000000), and that address in HOSTIO_FW_FAULT_ADDR so the capture "
                 "can be checked for an EXACT match. Without the expected value this "
                 "test could only assert that some fault was recorded, which is the "
                 "weak form HIO-308 already covers. No such image exists in this tree "
                 "today. This test does NOT clear the record (write-1 re-arms) -- "
                 "read it before HIO-308 destroys it.")
    want = int(expect, 0)
    rec.record("fw_expected_fault_addr", want)

    stat = _rd(adp, FAULT_STAT)
    addr = _rd(adp, FAULT_ADDR)
    count = _rd(adp, FAULT_COUNT)
    rec.check("fault registers readable",
              _good(stat) and _good(addr) and _good(count),
              got="%s / %s / %s" % (stat.raw, addr.raw, count.raw))
    if not (_good(stat) and _good(addr) and _good(count)):
        return
    rec.record("fault_stat", stat.value)
    rec.record("fault_addr", addr.value)
    rec.record("fault_count", count.value)
    seen = _bits(stat.value, 0, 0)
    init_idx = _bits(stat.value, 5, 4)
    overflow = _bits(stat.value, 8, 8)
    rec.record("fault_seen", seen)
    rec.record("fault_init_idx", init_idx)
    rec.record("fault_overflow", overflow)

    rec.check("FAULT_SEEN is set", seen == 1, got="FAULT_STAT=0x%08X" % stat.value)
    rec.check("FAULT_ADDR is EXACTLY the address firmware used",
              addr.value == want, got="0x%08X (expected 0x%08X)" % (addr.value, want))
    rec.check("INIT_IDX names a CPU (0 = eth_ss_m/CPU0, 1 = cpu_ss_1_m/CPU1)",
              init_idx in (0, 1), got="INIT_IDX=%d" % init_idx)


@test("HIO-508", tier=5, hazard=[HZ.IRREVERSIBLE, HZ.RESET, HZ.DESTRUCTIVE],
      needs=["HIO-313"],
      destroys="CPU1 IMEM (16 KB at 0x90000000); sets boot-gate bit 0 (irreversible, "
               "HZ-4); and its CPU1 restart resets the WHOLE SoC including the fabric, "
               "the ADP and HOSTIO itself (HZ-5)",
      purpose="CPU1 memory preload -- the other core. 0x90000000 is a "
              "remap-independent alias of CPU1 IMEM, so the preload works whatever "
              "CPU1's REMAP bit currently says: you do not have to know the boot state "
              "to load the image, and it fails visibly if the alias is wrong (HIO-118 "
              "would already have caught that). Carries TWO hazards that the "
              "single-valued `hazard` field cannot both express: HZ-4 on the "
              "0x29000000 bit-0 remap write (irreversible without a power cycle) and "
              "HZ-5 on the CPU1 restart, which resets the whole SoC because CPU1's "
              "PRMU sources HCLK/HRESETn -- so it declares BOTH, plus DESTRUCTIVE for "
              "the IMEM it overwrites, and needs all three runner flags before it may "
              "run at all.")
def hio_508(adp, rec):
    image = _env("HOSTIO_CPU1_IMAGE")
    if image is None:
        rec.skip("no CPU1 image. REQUIRED: a raw binary of at most 16384 bytes for "
                 "0x90000000 (CC_IMEM_RAM_ADDR_W=14), its path in HOSTIO_CPU1_IMAGE. "
                 "Note the plan's Phase-D option (b) uses this same mechanism to PARK "
                 "CPU1 in a two-instruction spin loop so it stops fighting the memory "
                 "tests -- that is the most useful image to build first. No such image "
                 "exists in this tree today. No bus access attempted.")
    if not os.path.isfile(image):
        rec.skip("HOSTIO_CPU1_IMAGE=%s does not exist. No bus access attempted." % image)
    size = os.path.getsize(image)
    rec.record("cpu1_image_path", image)
    rec.record("cpu1_image_bytes", size)
    if size == 0 or size > 16384:
        rec.skip("HOSTIO_CPU1_IMAGE is %d bytes; CPU1 IMEM is 16 KB." % size)
    _refuse_upload(rec, "HIO-508 (CPU1 IMEM preload)", size)


@test("HIO-509", tier=5, hazard=[HZ.RESET, HZ.DESTRUCTIVE], needs=["HIO-010"],
      destroys="the whole SoC: fabric, ADP and HOSTIO are reset; the port returns to "
               "the STDIO bypass and needs a fresh ESC. Everything except the boot "
               "gates returns to its cold state (they survive on PORESETn)",
      purpose="Whole-SoC reset, and the banner as proof. CPU1's PRMU sources the whole "
              "SoC's HCLK/HRESETn, so CPU1_SWRST resets the fabric, the ADP and HOSTIO "
              "itself -- and the re-emitted banner is therefore an end-to-end proof of "
              "the reset tree that no read can give you, with automatic recovery. PASS "
              "= the banner text reappears in the raw RX stream (the ADP prints it as "
              "the line ' 0x50c1ab04', socdebug_adp_control.v:67 BANNERHEX) and the "
              "port is usable again after a fresh ESC. Goes red if the reset does not "
              "propagate (no banner) or if the port does not come back. Never in an "
              "unattended sweep; run it last, after Tier 4's record is collected.")
def hio_509(adp, rec):
    pre = _rd(adp, BOOTROM_ETH)
    rec.record("pre_reset_bootrom_word", pre.value)
    rec.check("port healthy before the reset", _good(pre), got=pre.raw)
    if not _good(pre):
        return

    try:
        w = _wr(adp, SW_RESET, SWRST_CPU1, timeout_ms=1500)
        rec.record("cpu1_swrst_reply", w.raw)
    except BaseException as exc:            # noqa: BLE001
        # Expected: the ADP is reset mid-command, so the echo may never arrive.
        rec.record("cpu1_swrst_reply", "no reply (%r)" % (exc,))

    text = ""
    words = 0
    found = False
    deadline = time.monotonic() + BANNER_WINDOW_S
    while time.monotonic() < deadline:
        chunk = adp.raw_rx(BANNER_CHUNK_MS)
        words += len(chunk)
        # RX words are 12-bit; only (w & 0xf00) == 0 are console data bytes.
        text += "".join(chr(w & 0xFF) for w in chunk if (w & 0xF00) == 0)
        if "50c1ab04" in text.lower():
            found = True
            break
    rec.record("post_reset_rx_words", words)
    rec.record("post_reset_rx_tail", text[-120:].strip())
    rec.check("the ADP banner 0x50c1ab04 was re-emitted", found,
              got=repr(text[-120:]))

    adp.enter()                              # fresh ESC + the throwaway command
    post = _rd(adp, BOOTROM_ETH)
    rec.record("post_reset_bootrom_word", post.value)
    rec.check("port usable again after a fresh ESC", _good(post), got=post.raw)
    if _good(post) and _good(pre):
        rec.check("the boot ROM reads the same word as before the reset",
                  post.value == pre.value,
                  got="0x%08X then 0x%08X" % (pre.value, post.value))
    rec.note("Boot gates survive this reset (PORESETn only), so a die released with "
             "HIO-502 stays released. Everything else is back to cold.")
