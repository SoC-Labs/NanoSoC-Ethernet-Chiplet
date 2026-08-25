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
# WHAT THIS FILE DOES WITH `U` AND `F`, AND WHAT IT STILL REFUSES
#   * It DOES emit `U` and `F` -- from _upload() and _fill_words() only, and into
#     eth IMEM only.  `U` has NO ABORT AND NO TIMEOUT (socdebug_adp_control.v
#     :624-632): the FSM sits in ADP_UREADB consuming raw bytes until its counter
#     runs out, FNexit() is not evaluated there, and 0x04/0x00 are DATA, not
#     escapes -- so a count that does not equal the payload length parks the port
#     until a host PIO resync.  _upload() makes that mismatch UNCONSTRUCTIBLE: it
#     takes a payload and NO count, formats the command line from len(payload),
#     concatenates command and payload into one byte string, then parses the count
#     back OUT of that string and refuses unless it equals the bytes that follow
#     it.  The transmit is adp.raw_tx(), which is byte-exact including 0x00/0x04
#     and returns the accepted count; a short count is a resync, never "send more".
#   * `F` appears only as HIO-501's pre-zero and post-zero.  The PRE-zero is what
#     makes the verify mean anything -- without it a `U` that wrote nothing still
#     verifies against whatever was already there -- and HIO-501 proves the zero
#     landed rather than assuming it.
#   * Both go through _check_bulk_write(), which allows exactly ONE region (eth
#     IMEM), refuses any span that touches a hazard band, and refuses any span
#     containing a _WRITE_WHITELIST address.  `F` and `U` are CARPET writes: one
#     command line puts a chosen value across a whole range, so a mistyped address
#     here is far worse than a mistyped `W`, and the guard is code, not review.
#   * It still never uploads into CPU1 IMEM.  CPU1 cannot be held in reset
#     (`.cpu1_bootgate (1'b1)`, nanosoc_multicore_soc.sv:1387) and its PRMU sources
#     the fabric's HCLK/HRESETn, so overwriting its live code can take the whole
#     SoC -- including this debug port -- down.  HIO-508 refuses the TARGET, not
#     the mechanism; 0x90000000 is deliberately absent from _BULK_WRITE_REGIONS.
#   * It never touches the HZ-1 quarantine band, the HZ-8 read-clearing
#     registers, the HZ-6 XiP aperture, or the spinlock acquire pages.  That is
#     enforced in code by _check_addr(), not by review.
#   * It touches the HZ-2 peer aperture exactly once, from HIO-413, guarded.
#   * It never WRITES wlink 0x208 (0x2E030208); reads there are safe and allowed.
#
# OPERATIONAL HAZARDS -- not addresses, but they belong beside the address guards
# so nobody re-derives them the hard way.  None of these is enforceable in code;
# they bound what an operator may do around a run of this suite.
#   * NEVER reload the PL on a live link.  POR both boards instead.
#   * NEVER `sudo reboot` a KR260.  It wedges harder, and only a JTAG POR recovers
#     it.
#   * Do NOT run `eth_ss_probe.py` or `kr260_eth_run.sh status`.  That probe
#     hard-wedged a board on 2026-08-23.  Its "safe by construction" claim rests
#     on the SoC being clocked and out of reset, which nothing asserts.
#   * 0x2E0321AC / 0x21B0 / 0x21B4 hard-stall the CPU (HZ-1, enforced in _BANDS).
#     0x2E0321F8 and 0x2E0321E0 are documented-safe and are what this file reads.
#
# ENVIRONMENT (all optional; every one of them defaults to "skip, and say so")
#   HOSTIO_PHC_CORE_HZ      HIO-404: the clock feeding the PHC on THIS platform.
#                           NO DEFAULT any more -- unset means HIO-404 makes no
#                           absolute-frequency assertion at all.  The old default
#                           of 250000000 was wrong on every target that exists:
#                           the ASIC signs off at 100 MHz (ASIC/common.mk:242-261
#                           CLK_PERIOD=10.0; constraints.sdc:524-534 says so in
#                           terms) and the KR260 FPGA runs sys_fclk at 25.011 MHz
#                           (clk_wiz CLKOUT1 25.000 requested, routed timing
#                           summary 39.982 ns).  See HIO-404.
#   HOSTIO_TIMER_RELOAD     HIO-406 timer reload (default 0x18000000). Raise it if
#                           the link is slow -- see the sizing note at the constant.
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
# HIO-406 sizing.  The floor on "arm the timer, then start polling" is ~2 CU of
# link (~130 ms measured), so a reload must be MANY times the count the clock
# racks up in that window or the timer parks at 0 before the poll's first read
# and every count comes back as 1.  0x18000000 is ~1.6 s at 250 MHz, ~4 s at
# 100 MHz -- an order of magnitude clear of the link.  Override for a slow link.
TIMER_RELOAD_A = 0x18000000
TIMER_RELOAD_B = 0x30000000       # exactly 2x, so the counts must scale with it
TIMER_POLL_BUDGET = 0x20000000    # must exceed reload_b / (cycles per poll read)
TIMER_POLL_TIMEOUT_MS = 45000     # the poll cannot finish before the timer does
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
# HIO-501's `F` / `U` upload mechanism.
#
# TARGET.  0x10000000 is the REMAP-INDEPENDENT alias of eth IMEM (plan section
# 1.4): it is that 32 KB RAM whatever the eth REMAP bit says.  0x00000000 is the
# same RAM only when remap points at IMEM -- otherwise it is the boot ROM -- so a
# carpet write aimed there is a coin toss between RAM and ROM, and this module
# does not aim there.  eth IMEM is real writable RAM and was EMPTY on the die
# measured 2026-08-25 (plan section 5.5; write/read-back/restore of 0xD00DFEED at
# 0x10001000 is HIO-313's positive write-path control).  HIO-501 re-proves both
# in-test, before it writes anything it cannot take back.
#
# SIZE.  240 payload bytes + 16 guard bytes = 256 bytes = 64 words.  240 keeps
# the whole payload inside ONE period of the pattern below (see _pattern_byte),
# and `U` costs ~1 ms per byte where a 32-bit `A`+`R` pair costs ~130 ms -- so
# the streamed payload is NOT the expensive part; the block-read verify is.
# -----------------------------------------------------------------------------
UPLOAD_BASE = ETH_IMEM
UPLOAD_PAYLOAD_BYTES = 240
UPLOAD_GUARD_BYTES = 16           # zeroed by `F`, must STILL be zero after `U`
UPLOAD_REGION_BYTES = UPLOAD_PAYLOAD_BYTES + UPLOAD_GUARD_BYTES
UPLOAD_REGION_WORDS = UPLOAD_REGION_BYTES // 4
UPLOAD_PROBE_TAG = 0xD00DFEED     # HIO-313's tag, for the same reason
UPLOAD_MAX_BYTES = 4096           # hard cap on any single `U` from this module.
                                  # Raising it commits the port for ~1 ms/byte
                                  # with no abort and no timeout -- read _upload
                                  # before you do.
BLOCK_READ_WORDS = 16             # words per `R x<n>` dump; caps one reply's size
BLOCK_READ_TIMEOUT_MS = 15000     # a 16-word dump is ~240 console characters
FILL_TIMEOUT_MS = 8000            # `F` is ONE command however many words it fills
UPLOAD_RX_CHUNK_MS = 300          # RX drain slice while waiting for the `U` echo
UPLOAD_ECHO_WINDOW_S = 20.0

# The synthetic payload: p(off) = 1 + (0x67*off + 0x2D) mod 255.
PATTERN_MUL = 0x67                # 103, coprime with 255 -> p is injective
PATTERN_ADD = 0x2D
PATTERN_MOD = 255

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


# Write-only refusals: addresses that are SAFE TO READ but must never be driven
# from here.  Kept separate from _BANDS because a read refusal would cost real
# observability for no safety gain.
_WRITE_REFUSED_BANDS = (
    (0x2E030208, 0x2E03020B,
     "WLINK 0x208 (swi_enable[0], lltx_enable[1], lltx_enable_1[2], swreset[3]). "
     "Hand-driving it wedges the PS: swreset resets axi2wl mid-burst, BVALID never "
     "returns, the PS7 M_AXI_GP0 SmartConnect SI port saturates and the whole PL "
     "slave set wedges until a USB power-cycle (tidelink_top.sv:2887-2928). Let "
     "autonomy drive it. READS ARE SAFE and deliberately still allowed -- the RTL "
     "shim is write-only and states reads are bit-exact unchanged. The whole 32-bit "
     "word is refused, not just 0x208: the hardening shim matches apb_paddr[12:0] "
     "== 13'h208 EXACTLY, so a write to 0x209/0x20A/0x20B reaches the same Wlink "
     "register with the swreset mask BYPASSED."),
)


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
    for lo, hi, why in _WRITE_REFUSED_BANDS:
        if lo <= addr <= hi:
            raise HazardRefusal("refusing to WRITE 0x%08X: %s" % (addr, why))
    allowed = _WRITE_WHITELIST.get(addr)
    if allowed is not None and val not in allowed:
        raise HazardRefusal(
            "refusing W x%08X to 0x%08X: only %s may be written to this register "
            "from tier4_5" % (val, addr, sorted("0x%08X" % v for v in allowed)))


# Regions this module may CARPET-write with `F` or `U`.  Exactly one entry, and
# CPU1 IMEM (0x90000000) is deliberately NOT on it -- see HIO-508.
_BULK_WRITE_REGIONS = (
    (ETH_IMEM, 0x8000, "eth IMEM, 32 KB at 0x10000000 (ETH_IMEM_RAM_ADDR_W=15), "
                       "the remap-independent alias"),
)


def _check_bulk_write(addr, nbytes, value=0):
    """The address guard for `F` and `U`.  Returns the target region's name.

    `F` and `U` write a whole RANGE from one command line, so this checks the
    whole SPAN, not just the first address: a mistyped base that lands one word
    short of a hazard band still carpets into it.  Three refusals, all in code:

      * the span must lie entirely inside one _BULK_WRITE_REGIONS entry;
      * it must not overlap any _BANDS hazard range;
      * it must not contain any _WRITE_WHITELIST address -- those registers may
        only ever take one exact value from this file, and a carpet write is
        not a way around that.
    """
    nbytes = int(nbytes)
    if nbytes <= 0:
        raise HazardRefusal("refusing a bulk write of %d bytes" % nbytes)
    _check_addr(addr)
    _check_addr(addr + nbytes - 1)
    _check_write(addr, value)
    for lo, hi, why in _BANDS:
        if addr <= hi and lo < addr + nbytes:
            raise HazardRefusal(
                "refusing a %d-byte `F`/`U` span at 0x%08X: it overlaps 0x%08X-0x%08X, "
                "%s" % (nbytes, addr, lo, hi, why))
    for wl in sorted(_WRITE_WHITELIST):
        if addr <= wl < addr + nbytes:
            raise HazardRefusal(
                "refusing a %d-byte `F`/`U` span at 0x%08X: it covers 0x%08X, which is "
                "on the single-value write whitelist and may never be carpet-written"
                % (nbytes, addr, wl))
    for base, size, what in _BULK_WRITE_REGIONS:
        if base <= addr and addr + nbytes <= base + size:
            return what
    raise HazardRefusal(
        "refusing a %d-byte `F`/`U` carpet write at 0x%08X: this module may bulk-write "
        "ONLY inside %s. CPU1 IMEM (0x%08X) is deliberately not on that list -- CPU1 "
        "cannot be held in reset and its PRMU sources the fabric clock, so overwriting "
        "its live code can take the whole SoC down. See HIO-508."
        % (nbytes, addr, "; ".join(w for _, _, w in _BULK_WRITE_REGIONS), CPU1_IMEM))


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


# -----------------------------------------------------------------------------
# `F` (fill) and `U` (stream-to-memory).  READ THIS BEFORE EDITING ANY OF IT.
#
# THE ONE FACT THAT MATTERS.  `U x<n>` has no abort and no timeout.  ADP_UCTRL
# drops into ADP_UREADB and stays there consuming raw bytes until the counter
# runs out (socdebug_adp_control.v:624-632); FNexit() is NOT evaluated in that
# state, so 0x04 and 0x00 are DATA, not escapes, and there is no byte you can
# send to get out early.  One byte short and the port is parked until a host PIO
# resync.  One byte long and the extra byte is parsed as the next command line.
# So the count must equal the payload length EXACTLY -- and the way to guarantee
# that is to never have a count that could be wrong: see _upload().
#
# TWO RTL FACTS THE SIZING DEPENDS ON, re-derived rather than assumed:
#
#   * `U` forces BYTE accesses.  ADP_UCTRL sets adp_size <= 2'b00 (:624) and each
#     beat writes {4{rx_byte}} with HADDR[1:0] = adp_addr[1:0] (:377, :627), the
#     address stepping by 1 << adp_size = 1 (:466).  The count is therefore in
#     BYTES: one link byte per memory byte, no padding, no alignment rule.
#
#   * BOTH `F` and `U` treat a count of 0 OR 1 as "nothing to do".
#     FNcount_down_zero_next(x) is (x >> 1) == 0 (:426-429) -- true for 0 AND for
#     1 -- and it is evaluated on the PARAMETER in ADP_ACTION (:578-580 for `U`,
#     :592-595 for `F`).  `Ux00000001` therefore consumes NO payload bytes at all
#     and `Fx00000001` writes nothing, in both cases echoing a perfectly clean
#     reply.  Both helpers below refuse a count under 2 rather than emit a
#     command whose effect is not what its parameter says.
#
# `F`'s fill VALUE and fill SIZE both come from `V`, not from `F`: ADP_FCTRL
# loads adp_bus_data from adp_val and adp_size from FNparam2size(adp_val[34:33])
# (:648), and that size is set by how many hex DIGITS the `V` parameter carried
# (:144-167: 1-2 digits = byte, 3-4 = halfword, 5+ = word).  Eight digits,
# always -- which is the plan's "x + exactly 8 hex digits" rule doing real work.
#
# NEITHER `F` NOR `U` CAPTURES HRESP ON ITS LAST BEAT.  The `adp_bus_err <=
# adp_bus_err | HRESP_i` sits in the loop-CONTINUE branch of ADP_UWRITE (:631)
# and ADP_FWRITE (:651), so the beat that ends the transfer skips it entirely: a
# fill or an upload whose ONLY erroring beat is its last one echoes clean.  That
# is why HIO-501 re-reads the last word and the last byte explicitly instead of
# trusting the echo.
# -----------------------------------------------------------------------------


def _pattern_byte(off):
    """The payload byte for offset `off`.  Position-dependent, never 0x00.

        p(off) = 1 + (0x67*off + 0x2D) mod 255

    Three properties, each catching a failure a CONSTANT payload cannot see:

      * INJECTIVE.  0x67 (103) is coprime with 255 (= 3*5*17), so
        off -> (103*off + 45) mod 255 is a bijection and p never repeats inside
        one 255-offset window.  The payload is 240 bytes, inside one window, so
        no two offsets hold the same byte.  That is what makes ADDRESS ALIASING
        and an address that fails to increment visible: with a constant payload
        every location holds the right value whatever the address bus did.

      * NEVER ZERO.  The range is 1..255.  Combined with a PROVEN `F` pre-zero,
        "this byte was never written" reads back as a value the payload cannot
        produce -- which is what catches TRUNCATION, a dropped beat, and a `U`
        that wrote nothing at all.  A payload containing 0x00 would hide all
        three behind a legitimately-zero byte.

      * ADJACENT BYTES DIFFER (by 103 mod 255).  So byte ORDERING inside a word
        is checked too: a byte-lane swap cannot alias onto the expected word.
    """
    return 1 + ((PATTERN_MUL * int(off) + PATTERN_ADD) % PATTERN_MOD)


def _pattern_payload(nbytes, base_off=0):
    return bytes(bytearray(_pattern_byte(base_off + i) for i in range(int(nbytes))))


def _pattern_word_le(off):
    """The word an aligned 32-bit read at byte offset `off` must return.

    LITTLE-ENDIAN, and that is a build fact, not a convention:
    `parameter BE = 0,  // Endianness` (nanosoc_multicore_soc.sv:45), fed to both
    CPU integrations (:846, :962).  So byte `off` lands in bits [7:0].
    """
    return (_pattern_byte(off)
            | (_pattern_byte(off + 1) << 8)
            | (_pattern_byte(off + 2) << 16)
            | (_pattern_byte(off + 3) << 24))


def _pattern_word_be(off):
    """The same four bytes assembled the other way round -- computed ONLY so a
    byte-order failure is reported as itself rather than as a generic mismatch."""
    return (_pattern_byte(off + 3)
            | (_pattern_byte(off + 2) << 8)
            | (_pattern_byte(off + 1) << 16)
            | (_pattern_byte(off) << 24))


def _words_summary(words, limit=8):
    if not words:
        return "no words"
    parts = ["None" if w is None else "0x%08X" % w for w in words[:limit]]
    if len(words) > limit:
        parts.append("... (%d words total)" % len(words))
    return " ".join(parts)


def _block_read(adp, addr, nwords, timeout_ms=BLOCK_READ_TIMEOUT_MS):
    """`A x<addr>` ; `R x<nwords>` -- ONE command, nwords reply lines.

    MEASURED 2026-08-25 (recorded in tier0's HIO-006 header): `Rx00000004` gives
    4 lines of 8 nibbles and leaves the address +0x10.  The DIGIT COUNT sets the
    access size and the parameter VALUE sets the number of reads (adp_count <=
    adp_param at :536, and the ADP_LINEACK2 repeat arm at :727-729) -- which is
    why the parameter here is always 8 digits.  This is the cheap way to read a
    region: 16 words for one command round trip instead of 32.
    """
    _check_addr(addr)
    _check_addr(addr + nwords * 4 - 1)
    if not 1 <= nwords <= BLOCK_READ_WORDS:
        raise HazardRefusal(
            "refusing a %d-word `R` dump: this module caps one command's reply at %d "
            "words so it cannot overrun the board-side RX buffer (RX_CAP), which would "
            "truncate the dump and look like missing data"
            % (nwords, BLOCK_READ_WORDS))
    a = adp.cmd("Ax%08X" % addr, timeout_ms=CMD_TIMEOUT_MS)
    r = adp.cmd("Rx%08X" % nwords, timeout_ms=timeout_ms)
    r.prior = a
    r.addr_ok = bool(a.ok and not a.rejected and a.letter == "A")
    return r


def _read_byte(adp, addr):
    """`A x<addr>` ; `R1` -- ONE 8-bit read of exactly this byte.

    MEASURED 2026-08-25 (tier0 HIO-006 header): `R1` gives 1 line of 2 nibbles
    and leaves the address +1.  One hex digit encodes an 8-bit access
    (FNparam2size, :144-167) and the parameter VALUE 1 is the read count.  At
    byte size HADDR[1:0] really is adp_addr[1:0] (:377 -- a WORD read forces it
    to 00 instead) and ADP_READ rotates HRDATA so the addressed byte lands in
    adp_bus_data[7:0] (:607-610), so the two printed digits ARE this byte.
    """
    _check_addr(addr)
    a = adp.cmd("Ax%08X" % addr, timeout_ms=CMD_TIMEOUT_MS)
    r = adp.cmd("R1", timeout_ms=CMD_TIMEOUT_MS)
    r.prior = a
    return r


def _read_region(adp, rec, addr, nwords, label):
    """Block-read `nwords` words, in <= BLOCK_READ_WORDS chunks.

    Every chunk re-issues its own `A`, so a truncated or lost reply cannot
    silently shift the words after it -- which would turn one dropped line into
    a whole-region mismatch and hide where the real fault was.

    Returns (words, ok).  Missing words come back as None (never as 0, which
    would be indistinguishable from a legitimately zero location).  ok is False
    if any chunk was short, timed out, overflowed the board RX buffer, or raised
    `!` on any beat -- and the reason is recorded, not swallowed.
    """
    words = []
    ok = True
    off = 0
    while off < nwords:
        n = min(BLOCK_READ_WORDS, nwords - off)
        r = _block_read(adp, addr + off * 4, n)
        vals = list(r.values)[:n]
        if (not r.ok) or r.error or r.overflow or len(vals) != n:
            ok = False
            rec.record(
                "%s_chunk_fault_word_%d" % (label, off),
                "0x%08X +%d words: %r (parsed=%d want=%d error=%s overflow=%s "
                "timed_out=%s addr_ok=%s)"
                % (addr + off * 4, n, r.raw[:120], len(vals), n, r.error,
                   r.overflow, r.timed_out, r.addr_ok))
            vals = vals + [None] * (n - len(vals))
            if r.timed_out:
                # A bus error is a result and the sweep goes on; silence is not.
                # Each further chunk would burn its full budget for nothing, and
                # this helper is called three times per run.
                words.extend(vals)
                words.extend([None] * (nwords - off - n))
                rec.record("%s_abandoned_at_word" % label, off)
                return words, False
        words.extend(vals)
        off += n
    return words, ok


def _fill_words(adp, rec, addr, nwords, value, label):
    """`V x<value>` ; `A x<addr>` ; `F x<nwords>` -- fill nwords 32-bit words.

    Returns (v, a, f) so the caller asserts all three: `V` sets the value AND the
    access size, `A` sets the base, and only then does `F` mean what it says.
    """
    what = _check_bulk_write(addr, nwords * 4, value)
    if nwords < 2:
        raise HazardRefusal(
            "refusing `Fx%08X`: FNcount_down_zero_next (socdebug_adp_control.v"
            ":426-429) is (x >> 1) == 0, so a count of 0 or 1 fills NOTHING while "
            "echoing a clean reply -- the command would not do what its parameter says"
            % nwords)
    rec.record("%s_fill" % label,
               "%d words of 0x%08X at 0x%08X in %s" % (nwords, value, addr, what))
    v = adp.cmd("Vx%08X" % (value & 0xFFFFFFFF), timeout_ms=CMD_TIMEOUT_MS)
    a = adp.cmd("Ax%08X" % addr, timeout_ms=CMD_TIMEOUT_MS)
    f = adp.cmd("Fx%08X" % nwords, timeout_ms=FILL_TIMEOUT_MS)
    return v, a, f


def _upload(adp, rec, addr, payload, label):
    """`U` -- stream `payload` into memory at `addr`, one link byte per memory byte.

    THE COUNT GUARD, which is the whole point of this function.  There is no
    count parameter here and no way to supply one:

      1. n is len(payload).  It is not passed in and cannot be passed in.
      2. the command line is formatted from n.
      3. command line and payload are concatenated into ONE byte string, so the
         thing that carries the count and the thing that carries the bytes are
         the same object from here on.
      4. the count is then PARSED BACK OUT of that byte string and required to
         equal the number of bytes that follow the CR in the same string.

    A count that disagrees with its payload cannot be built by this function --
    not by care, by construction.  Step 4 is not redundant with steps 1-3: it is
    what a later edit that reintroduces a separate count has to get past.

    Returns a dict: sent, frame_len, reply (the `U` echo), text, addr_reply.
    On any failure the port is resynced before returning, so the caller is never
    handed a port parked in ADP_UREADB.
    """
    payload = bytes(bytearray(payload))
    n = len(payload)
    what = _check_bulk_write(addr, n)
    if n < 2:
        raise HazardRefusal(
            "refusing `U` with %d payload bytes: FNcount_down_zero_next "
            "(socdebug_adp_control.v:426-429) is evaluated on the PARAMETER in "
            "ADP_ACTION (:578-580), so a count of 0 or 1 consumes NO payload at all -- "
            "the bytes would be parsed as the next command line instead" % n)
    if n > UPLOAD_MAX_BYTES:
        raise HazardRefusal(
            "refusing a %d-byte `U` from this module (cap %d bytes): `U` has no abort "
            "and no timeout, so the size of the stream is the size of an unbreakable "
            "commitment -- ~1 ms of link per byte during which nothing can interrupt it"
            % (n, UPLOAD_MAX_BYTES))

    frame = ("Ux%08X\r" % n).encode("ascii") + payload
    head, sep, tail = frame.partition(b"\r")
    if (sep != b"\r" or not head.startswith(b"Ux") or len(head) != 10
            or int(head[2:], 16) != len(tail) or len(tail) != n):
        raise HazardRefusal(
            "REFUSING TO EMIT `U`: the count in the command line does not match the "
            "payload that follows it in the very same byte string (command %r, %d bytes "
            "after the CR, payload %d bytes). `U` has no abort and no timeout -- a "
            "mismatch parks the port in ADP_UREADB until a host PIO resync."
            % (head, len(tail), n))

    rec.record("%s_u_command" % label, head.decode("ascii"))
    rec.record("%s_u_payload_bytes" % label, n)
    rec.record("%s_u_target" % label, "0x%08X in %s" % (addr, what))

    a = adp.cmd("Ax%08X" % addr, timeout_ms=CMD_TIMEOUT_MS)
    adp.raw_rx(1)                      # drop the `A` echo so the `U` echo stands alone
    sent = adp.raw_tx(frame)
    rec.record("%s_u_bytes_accepted" % label, sent)

    out = {"sent": int(sent), "frame_len": len(frame), "addr_reply": a,
           "text": "", "reply": Reply("", timed_out=True, sent=False,
                                      cmd=head.decode("ascii"))}
    if int(sent) != len(frame):
        # adp.raw_tx stops at the first stalled chunk and its contract is
        # explicit: a short count means resync, NOT "send the rest".  The FSM is
        # now waiting in ADP_UREADB for bytes that will never arrive, and a
        # resync is the only exit.
        rec.record("%s_u_short_send" % label,
                   "link accepted %d of %d bytes; port resynced" % (sent, len(frame)))
        adp.resync()
        adp.enter()
        return out

    text = ""
    deadline = time.monotonic() + UPLOAD_ECHO_WINDOW_S
    while time.monotonic() < deadline:
        chunk = adp.raw_rx(UPLOAD_RX_CHUNK_MS, flush=False)
        # RX words are 12-bit; only (w & 0xf00) == 0 are console data bytes.
        text += "".join(chr(w & 0xFF) for w in chunk if (w & 0xF00) == 0)
        if "]" in text:
            break
    out["text"] = text
    out["reply"] = Reply(text, timed_out=("]" not in text),
                         cmd=head.decode("ascii"))
    if "]" not in text:
        rec.record("%s_u_no_prompt" % label,
                   "no ']' inside %.1f s of the last payload byte; port resynced. "
                   "Tail: %r" % (UPLOAD_ECHO_WINDOW_S, text[-120:]))
        adp.resync()
        adp.enter()
    return out


def _refuse_cpu1_upload(rec):
    """HIO-508's refusal.  The TARGET is refused, not the mechanism."""
    rec.skip(
        "PERMANENT REFUSAL OF THE CPU1 TARGET -- and not for want of a mechanism. The "
        "`U` transport this test needs is built, guarded and exercised end to end by "
        "HIO-501 (adp.raw_tx + _upload's count guard). What is refused here is writing "
        "it into CPU1's IMEM. "
        "CPU1 IS EXECUTING OUT OF THE MEMORY THIS WOULD OVERWRITE, AND IT CANNOT BE "
        "STOPPED FIRST. `.cpu1_bootgate (1'b1)` is tied high at the SoC top "
        "(nanosoc_multicore_soc.sv:1387) and cpu1_resetn = cpu1_bootgate & "
        "~cpu1_reset_pulse (nanosoc_reset_ctrl.v:364), so there is no gate to close: "
        "unlike CPU0 there is no hold-in-reset / load / release order available from "
        "this port. The only way to stop CPU1 is CPU1_SWRST -- which is HZ-5 and resets "
        "the WHOLE SoC including the ADP, so no upload survives it. "
        "AND THE FAILURE MODE IS THE DIE, NOT ONE CORE: CPU1's PRMU sources the "
        "fabric's HCLK and HRESETn (see HIO-509), so a CPU1 that faults or locks up on "
        "half-overwritten code can take the fabric, the ADP and HOSTIO itself down -- "
        "the very port that would diagnose it. That is a power cycle, not a red. "
        "THERE IS NO SAFE SUBSET EITHER: nothing this port can read says which parts of "
        "CPU1's 16 KB IMEM are live code, so 'write somewhere it is not running' would "
        "be an assumption, not a measurement. "
        "ENFORCED IN CODE, NOT BY REVIEW: 0x%08X is deliberately absent from "
        "_BULK_WRITE_REGIONS, so _check_bulk_write() refuses any `F` or `U` aimed at it "
        "even if this guard were deleted. "
        "WHAT WOULD MAKE IT RUNNABLE: a build in which cpu1_bootgate is driven by "
        "chip_core_remap_ctrl instead of tied to 1'b1, or a CPU1 boot ROM that parks in "
        "a spin loop OUT OF ROM until told otherwise. The plan's Phase-D option (b) -- "
        "park CPU1 in a two-instruction spin loop so it stops fighting the memory tests "
        "-- is that idea, but loading that image needs exactly the write refused here. "
        "No bus access attempted." % CPU1_IMEM)


# -----------------------------------------------------------------------------
# Decoders shared by more than one test.
# -----------------------------------------------------------------------------
def _decode_lane_status(v):
    """swi_lane_status @0x2E032108, decoded against the RTL THAT PACKS IT.

    THE RDL IS WRONG ABOUT BIT 20, AND THIS DECODER USED TO INHERIT THAT.
    tidelink_regs.rdl:437-441 declares ``fcsm_state[4]`` spanning [20:17] with the
    note "3b; bit[20] always 0".  The register mux that actually drives the word
    packs ``sync_obs_fcsm_state_1`` -- declared ``reg [2:0]`` at
    axi_chiplet_controller.sv:1796 -- at **[19:17]**, and puts
    ``sync_obs_a2l_app_v_1`` (a2l_replay_app_valid) at **[20]**
    (axi_chiplet_controller.sv:2904-2905).  Identical in the packaged FPGA IP that
    built the KR260 bitstream: tidelink/imp/fpga/eth_chiplet_ip/src/
    axi_chiplet_controller.sv:2904-2905.  Bit 20 is a live signal, not a spare,
    and the RDL comment predates it.

    MEASURED 2026-08-25 on the eth die, which is what exposed this: the old 4-bit
    decode reported ``fcsm_state = 8`` and classified it "unknown state", outside
    the documented 0..7.  **There is no state 8.**  8 is bit[20] set with the real
    FCSM at 0 -- exactly right for a lone die: FCSM idle, and the a2l replay
    buffer's app side holding a word it cannot hand to a link that is down.  An
    operator reading "unknown state" would reasonably have read it as "broken".
    """
    return {
        "lane_locked": _bits(v, 7, 0),
        "lane_fault": _bits(v, 15, 8),
        "calibration_done": _bits(v, 16, 16),
        "fcsm_state": _bits(v, 19, 17),          # 3 bits -- see the docstring
        "a2l_replay_app_valid": _bits(v, 20, 20),  # NOT part of fcsm_state
        "llrx_state": _bits(v, 22, 21),
        "cr_pkt_seen_rx": _bits(v, 23, 23),
        "crack_pkt_seen_rx": _bits(v, 24, 24),
        "llrx_valid": _bits(v, 29, 29),
    }


def _link_up(f):
    """THE link predicate for this file: fcsm in the 4..7 band AND cal done.

    NEVER put lane_locked (or lane_synced) in a link predicate.  lane_locked
    reads 0x00 even on a healthy, fully working link -- a known observability
    defect, not a link state (lane_synced_i is tied 8'h00, same class).  So
    `lane_locked != 0` is DEAD on a good link and can only ever fire on garbage:
    as an OR term it is a false-GREEN path (a die with cal=0 but a junk non-zero
    lane_locked would be declared link-present), and as an AND term it would be a
    permanent false red.  The 4..7 band is the RTL's own definition of link-up
    (auto_anchor_link_up = sync_obs_fcsm_state_1[2], axi_chiplet_controller.sv
    :4992), which is why it, with calibration_done, is the whole predicate.
    """
    return 4 <= f["fcsm_state"] <= 7 and f["calibration_done"] == 1


def _classify_fcsm(f):
    """FCSM state is 3 bits, so 0..7 IS the whole domain -- there is no state 8.

    The 4..7 band is the RTL's own definition of link-up, not a guess:
    ``wire auto_anchor_link_up = sync_obs_fcsm_state_1[2];  // FCSM in 4..7
    (link up)`` (axi_chiplet_controller.sv:4992, and :6404 for data_mode_o).
    """
    if f == 1:
        return "WEDGE: credit-path bring-up failure (tidelink_regs.rdl:441)"
    if f == 2:
        return "WEDGE: stalled / no progress (axi_chiplet_controller.sv:739,891)"
    if 4 <= f <= 7:
        return "healthy operating region (bit 2 set = link up)"
    if f == 0:
        return "idle / not brought up -- the normal state on a die with no peer"
    if f == 3:
        return "bring-up in progress (not yet in the 4..7 link-up band)"
    return ("out of range: fcsm_state is 3 bits, so this value did not come from "
            "_decode_lane_status")


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
        # [10] sets on ANY healthy cross-die read: a ~460 us round trip exceeds
        # its 4096-hclk threshold.  OBSERVATION ONLY -- it is not a wedge
        # indicator, and gating on it reds the first successful cross-die read.
        out["xhb_stall_stuck_sticky"] = _bits(v, 10, 10)
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

    # PARKED predicate: sub_err_sticky high AND bridge_ready low AND STUCK.
    # "Stuck" needs more than one look, so 0x21F8 is sampled twice; a single
    # low sample is legitimate mid-transfer.
    r_f8b = _rd(adp, XHB_SUB_OBS, timeout_ms=timeout_ms)
    out["f8_second"] = r_f8b
    out["f8_second_ok"] = _good(r_f8b)
    if out["f8_marker_ok"] and out["f8_second_ok"]:
        out["bridge_ready_2nd"] = _bits(r_f8b.value, 0, 0)
        out["bridge_ready_stuck"] = (out["bridge_ready"] == 0
                                     and out["bridge_ready_2nd"] == 0)
    else:
        out["bridge_ready_stuck"] = False
    out["parked"] = bool(out["f8_marker_ok"]
                         and out.get("sub_err_sticky", 0) == 1
                         and out["bridge_ready_stuck"])

    out["healthy"] = bool(
        out["f8_marker_ok"] and out["e0_marker_ok"]
        and not out["parked"]
        and out.get("data_healthy", 0) == 1)
    return out


def _record_xhb(rec, w, prefix):
    rec.record(prefix + "_0x21F8", None if not w["f8_ok"] else w["f8"].value)
    rec.record(prefix + "_0x21E0", None if not w["e0_ok"] else w["e0"].value)
    rec.record(prefix + "_marker_b5", bool(w["f8_marker_ok"]))
    rec.record(prefix + "_marker_ad", bool(w["e0_marker_ok"]))
    if w["f8_marker_ok"]:
        rec.record(prefix + "_xhb_stall_stuck_sticky", w["xhb_stall_stuck_sticky"])
        rec.record(prefix + "_bridge_ready_stuck", bool(w.get("bridge_ready_stuck")))
        rec.record(prefix + "_parked", bool(w.get("parked")))
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
      destroys="the perf-probe SHADOW set (two SNAP pulses). The live counters are "
               "NOT touched -- only CLR zeroes those, and CLR is HIO-307's to issue",
      purpose="The fabric clock is running. Two SNAP-latched P0_CYC samples bracketed "
              "by a host-measured interval; PASS = a non-zero advance whose implied "
              "frequency is physically plausible. This is the ONE test that "
              "distinguishes 'the die is clocked' from 'the die is latched' -- with a "
              "stopped HCLK every other test in this plan still 'works' (registers "
              "hold their values, reads return data) and only this one goes red. It "
              "goes red ONLY on a counter that has demonstrably counted and then "
              "stopped; the two not-counting signatures (static zero, saturated) are "
              "SKIPs, because this register alone cannot tell a disabled or "
              "reset-held probe from a stopped fabric.")
def hio_402(adp, rec):
    # THE TRAP THIS TEST IS BUILT AROUND, measured on the live FPGA die 2026-08-25
    # and then run to ground in the RTL:
    #
    #   0x2C200040 cold  -> 0x00000000 twice     (looks like a dead clock)
    #   after a SNAP     -> 0xFFFFFFFF three times (looks like a stuck register)
    #
    # Both readings come from a HEALTHY, fully clocked die.  The block here is
    # ctrl_ahb_perf_probe_regs (ID "PRF1" = 0x50524631, matching the measurement),
    # NOT the ahb_perf_probe_regs of the same name elsewhere in the tree:
    #   * its readout returns SHADOW registers, frozen until CTRL[0] SNAP
    #     (ctrl_ahb_perf_probe_regs.v:23-32).  A cold die has never been snapped,
    #     so the shadow reads 0 -- that is the correct cold value, not a fault.
    #   * its live counters SATURATE, holding at CNT_MAX
    #     (ctrl_ahb_perf_probe.v:184: cyc_q <= (cyc_q == CNT_MAX) ? CNT_MAX : +1).
    #     At 100 MHz full scale is 43 s, so ANY die up for a minute reads
    #     0xFFFFFFFF -- which is positive evidence the clock RAN, not that it stopped.
    #   * CTRL is write-only and self-clearing, so CTRL reading back 0x00000000
    #     after a write is correct (that asymmetry is HIO-307's subject).
    # The plan's "it is saturating" caveat was right; an earlier revision of this
    # file cited ahb_perf_probe.v:120 (an unconditional +1, i.e. wrapping) to
    # contradict it -- that is a DIFFERENT, non-instantiated block (ID "PRF"+0x01).
    pre = _rd(adp, PERF_P0_CYC)
    rec.record("p0_cyc_shadow_before_any_snap", pre.value)
    rec.check("P0_CYC readable", _good(pre), got=pre.raw)
    if not _good(pre):
        return

    w1, r1 = _perf_snapshot(adp)
    t1 = time.monotonic()
    rec.check("SNAP accepted (sample 1)", _wrote(w1), got=w1.raw)
    rec.check("P0_CYC readable after SNAP (sample 1)", _good(r1), got=r1.raw)
    if not (_wrote(w1) and _good(r1)):
        return
    time.sleep(FABRIC_INTERVAL_S)
    w2, r2 = _perf_snapshot(adp)
    t2 = time.monotonic()
    rec.check("SNAP accepted (sample 2)", _wrote(w2), got=w2.raw)
    rec.check("P0_CYC readable after SNAP (sample 2)", _good(r2), got=r2.raw)
    if not (_wrote(w2) and _good(r2)):
        return

    elapsed = t2 - t1
    rec.record("p0_cyc_snap1", r1.value)
    rec.record("p0_cyc_snap2", r2.value)
    rec.record("p0_cyc_interval_s", round(elapsed, 4))

    # ---- ONE arm for "not advancing", covering both not-counting signatures.
    stuck = (r1.value == r2.value)
    if stuck and r1.value in (0x00000000, PERF_CNT_MAX):
        which = ("STATIC ZERO" if r1.value == 0 else "SATURATED at 0xFFFFFFFF")
        rec.record("p0_cyc_not_advancing", which)
        rec.skip(
            "P0_CYC is not advancing: %s across two SNAP-latched samples %0.1f s "
            "apart. THIS IS NOT EVIDENCE OF A STOPPED FABRIC, and Abort Gate 6 must "
            "not be tripped on it. The register cannot discriminate between (a) the "
            "probe not counting -- its global enable low (ctrl_ahb_perf_probe.v:69, "
            "'CYC and all events freeze when low') or the probe held in reset, note "
            "ctrl_dbg_group takes sys_sysresetn while the ADP takes "
            "u_network_core_sys_hresetn, so the probe CAN be in reset while the "
            "monitor runs -- and (b) the fabric genuinely stopped. INDEPENDENT "
            "EVIDENCE THE FABRIC IS LIVE: this reply reached you, and the ADP "
            "(u_debug_0) is clocked from u_network_core_sys_hclk, the SAME net that "
            "clocks ctrl_dbg_group and this counter. A monitor that answers cannot be "
            "on a stopped HCLK -- its own AHB transactions would never complete. So a "
            "responding port already proves the clock this counter counts is toggling; "
            "do NOT power-cycle on this result. %s TO GET A MEASUREMENT: issue "
            "HIO-307's CLR (A x2c200008 ; Wx00000002) -- it is Tier 3's to issue "
            "because it zeroes every probe's live counters -- then re-run this test."
            % (which, FABRIC_INTERVAL_S,
               ("Saturation is itself positive evidence: the counter reached full "
                "scale (43 s at 100 MHz), so it was counting."
                if r1.value == PERF_CNT_MAX else
                "A never-snapped shadow also reads zero, so a cold die reads this "
                "even with the probe counting normally underneath.")))

    if r2.value < r1.value:
        rec.skip("P0_CYC went backwards (0x%08X -> 0x%08X). The counter saturates and "
                 "never wraps, so the only way down is a CLR landing mid-measurement "
                 "-- a concurrent HIO-307, or another session on this die. Re-run "
                 "when the die is quiet; measuring nothing is reported as SKIP."
                 % (r1.value, r2.value))

    delta = r2.value - r1.value
    hz = delta / elapsed if elapsed > 0 else 0.0
    rec.record("p0_cyc_delta", delta)
    rec.record("fabric_hclk_hz_estimate", int(hz))

    # Reached only when the counter is in mid-range, i.e. it HAS counted: a zero
    # delta here is a clock that ran and then stopped, which is a real red.
    rec.check("the fabric clock advanced between the two snapshots", delta != 0,
              got="0x%08X -> 0x%08X over %.3f s (mid-range, so the counter had been "
                  "counting)" % (r1.value, r2.value, elapsed))
    rec.check("implied HCLK is physically plausible (1 MHz .. 2 GHz)",
              FABRIC_HZ_MIN <= hz <= FABRIC_HZ_MAX,
              got="%.3f MHz" % (hz / 1e6))
    if r2.value == PERF_CNT_MAX:
        rec.note("Sample 2 is at full scale: the counter saturated inside the window, "
                 "so the rate above is a lower bound. Re-run after HIO-307's CLR for "
                 "a true rate.")


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
      purpose="PHC ADVANCE RATE -- and, on this build, the first hardware measurement "
              "the PTP subsystem has ever had. Two shadow captures separated by a "
              "host-measured interval give nanoseconds-of-PHC per second-of-wall. "
              "THIS TEST NO LONGER ASSERTS A HARDCODED CORE CLOCK, and the reason is a "
              "finding in its own right: the 250 MHz it used to assume is not this "
              "design's frequency on ANY target that exists. The ASIC signs off at "
              "100 MHz (ASIC/common.mk:242-261 CLK_PERIOD=10.0, and "
              "ASIC/genus-innovus/inputs/constraints.sdc:524-534 says 'THIS DESIGN DOES "
              "NOT RUN AT 250 MHz' in terms); the KR260 FPGA runs sys_fclk at "
              "25.011 MHz (clk_wiz_0 CLKOUT1 requested 25.000, routed timing summary "
              "39.982 ns) and HAPS-SX at 25 MHz. 250 MHz survives only as a comment in "
              "the PHC IP -- 'parameter [7:0] DEFAULT_NS_INCR = 8'd4  // 4 ns for "
              "250 MHz' (phc_apb_regs.sv:18). "
              "WHAT IS ASSERTED INSTEAD. (a) the implied clock is a plausible clock at "
              "all, so a garbage or frozen measurement cannot pass; (b) NS_INCR is "
              "unchanged across the window, so the rate was computed with the "
              "increment actually in force; (c) THE PHC KEEPS REAL TIME -- ns_incr x "
              "f_phc must equal 1e9. (c) is the assertion the PTP subsystem exists to "
              "satisfy and it is deliberately NOT relaxed: on the die measured "
              "2026-08-25 it FAILS by a factor of ten, and that red is the result, not "
              "a test defect. An absolute-frequency comparison is made only when the "
              "operator supplies HOSTIO_PHC_CORE_HZ; with it unset, none is made. "
              "THERE IS NO CLOCK-RATE REGISTER TO DERIVE IT FROM -- the PHC map is "
              "CTRL/STATUS/NS_INCR/NS_INCR_FRAC/SET_*/INT_EN/CAP_*/ALARM_*/HW_CAP_*/"
              "ETH_*_CAP_*/SERVO_* (phc_apb_regs.rdl) and none of them reports a "
              "frequency, a period or a divider; the only divider register on the die "
              "is the QSPI SCLK divider. The 0x05F5E100 word at 0x18000000 is NOT one "
              "either: it is SystemCoreClock from the loaded image, i.e. a firmware "
              "build constant, not a hardware readout. "
              "Both {seconds, nanoseconds} come from the same atomic capture, so the "
              "1e9 rollover cannot alias the measurement. CAP_NS_FRAC is deliberately "
              "unused: ns_incr_frac resets to 0, so it is static on a fresh part and "
              "would be a liveness signal that can never move.")
def hio_404(adp, rec):
    ni0 = _rd(adp, PHC_NS_INCR)
    rec.check("NS_INCR readable", _good(ni0), got=ni0.raw)
    if not _good(ni0):
        return
    ns_incr = _bits(ni0.value, 7, 0)
    rec.record("phc_ns_incr", ns_incr)
    if ns_incr == 0:
        rec.skip("NS_INCR reads 0, so the PHC cannot advance by construction and a "
                 "rate measurement would be meaningless. Restore NS_INCR (HIO-309 "
                 "reads and restores it; the RDL/RTL default is 4) and re-run.")

    def capture():
        cw = _wr(adp, PHC_CTRL, PHC_CTRL_EN_CAPTURE)
        t = time.monotonic()
        cs = _rd(adp, PHC_CAP_SEC_LO)
        cn = _rd(adp, PHC_CAP_NS)
        # P0_CYC is a SNAP-latched shadow, not a live counter: without the SNAP
        # both samples return the same stale word and the cross-check below would
        # silently read zero.  See _perf_snapshot().
        _, cyc = _perf_snapshot(adp)
        return cw, t, cs, cn, cyc

    w0, t0, s0, n0, c0 = capture()
    time.sleep(PHC_INTERVAL_S)
    w1, t1, s1, n1, c1 = capture()
    ni1 = _rd(adp, PHC_NS_INCR)

    for label, r in (("capture 0 write", w0), ("capture 1 write", w1)):
        rec.check("%s accepted" % label, _wrote(r), got=r.raw)
    for label, r in (("sec0", s0), ("ns0", n0), ("sec1", s1), ("ns1", n1)):
        rec.check("%s readable" % label, _good(r), got=r.raw)
    if not all(_good(r) for r in (s0, n0, s1, n1)):
        return

    # The rate below is (delta PHC) / (delta NS_INCR-weighted cycles).  If NS_INCR
    # moved mid-window -- another agent, firmware, a half-finished HIO-309 -- the
    # arithmetic is over two different increments and every number after this is
    # meaningless.  Cheap to prove, so prove it.
    rec.record("phc_ns_incr_after", None if not _good(ni1) else _bits(ni1.value, 7, 0))
    rec.check("NS_INCR is UNCHANGED across the measurement window (0x%02X), so the "
              "rate below was computed with the increment that was actually in force "
              "for the whole interval" % ns_incr,
              _good(ni1) and _bits(ni1.value, 7, 0) == ns_incr, got=ni1.raw)

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
    realtime_ratio = rate / float(PHC_NS_PER_SEC)
    incr_for_realtime = PHC_NS_PER_SEC / implied_core_hz
    hz_for_realtime = PHC_NS_PER_SEC / float(ns_incr)
    rec.record("phc_ns_per_wall_s", int(rate))
    rec.record("phc_implied_core_hz", int(implied_core_hz))
    rec.record("phc_realtime_ratio", round(realtime_ratio, 6))
    rec.record("phc_ns_incr_for_realtime", round(incr_for_realtime, 3))
    rec.record("phc_clock_hz_for_realtime", int(hz_for_realtime))

    # (a) The measurement is a measurement.  A frozen counter, a mis-sized read or
    #     a rollover artefact lands outside this band; a real clock does not.
    rec.check("the implied PHC clock is a plausible clock at all (%d Hz .. %d Hz). "
              "This is the only check here that a garbage measurement cannot pass, "
              "and it is NOT the real-time check below"
              % (FABRIC_HZ_MIN, FABRIC_HZ_MAX),
              FABRIC_HZ_MIN <= implied_core_hz <= FABRIC_HZ_MAX,
              got="%.4f MHz (ns_incr=%d, %d ns of PHC per wall second)"
                  % (implied_core_hz / 1e6, ns_incr, int(rate)))

    # (b) Same-net cross-check against the fabric counter, RECORDED not asserted --
    #     see the note for why the ratio is the diagnostic and not the verdict.
    if (_good(c0) and _good(c1) and c1.value > c0.value
            and c0.value not in (0x00000000, PERF_CNT_MAX)):
        fabric_hz = (c1.value - c0.value) / elapsed
        ratio = (implied_core_hz / fabric_hz) if fabric_hz else 0.0
        rec.record("phc_fabric_crosscheck", "available")
        rec.record("fabric_hz_during_phc_window", int(fabric_hz))
        rec.record("phc_core_over_fabric_ratio", round(ratio, 4))
        if 0.9 <= ratio <= 1.1:
            rec.note("The PHC's implied clock and the fabric counter agree (ratio "
                     "%.4f), which is what the RTL predicts: they are the same net."
                     % ratio)
        else:
            rec.note("RATIO %.4f, AND IT SHOULD BE 1.0 -- BUT THIS IS NOT EVIDENCE "
                     "THAT THE PHC IS ON A DIFFERENT CLOCK. The path is: PHC's HCLK is "
                     "u_network_core_sys_hclk (nanosoc_multicore_soc.sv:1033-1037), "
                     "which is the eth subsystem's sys_hclk output (:954, :834), which "
                     "with CLK_RST_CONSUMER=1 is sys_hclk_i passed straight through "
                     "(ethernet_ss_ahb_rmii.sv:336-343, :387-389), which is chip_core's "
                     "sys_hclk (:960, :978), which is `assign SYS_HCLK = SYS_FCLK;` "
                     "(slcorem0p_prmu.v:91-93). There is NO divider, prescaler or "
                     "gate anywhere on that path, and the PHC counter itself adds "
                     "ns_incr every cycle with no tick divisor "
                     "(phc_clock_core.sv:136-170). So a ratio far from 1.0 means one "
                     "of the two MEASUREMENTS is not in the units it is assumed to be "
                     "in, and the P0_CYC side is the one to distrust first. That is "
                     "HIO-402's and HIO-307's question, not this test's, which is why "
                     "it is recorded here and not asserted." % ratio)
    else:
        rec.record("phc_fabric_crosscheck",
                   "unavailable (P0_CYC not counting -- diagnosed by HIO-402)")

    # (c) THE FINDING.  Not relaxed, not overridable.
    rec.check("THE PHC KEEPS REAL TIME: ns_incr x f_phc must be 1e9, i.e. the clock "
              "must advance 1,000,000,000 ns per wall second. Measured %d ns/s = "
              "%.4f x real time. The +/-2 %% tolerance is set by host-timing jitter "
              "over a %.0f s window and by nothing else -- it is NOT widened to "
              "accommodate a result. AT THE CLOCK ACTUALLY MEASURED (%.4f MHz) "
              "NS_INCR WOULD HAVE TO BE %.1f, not %d; equivalently, NS_INCR=%d wants "
              "a %.4f MHz clock. NS_INCR is RW (HIO-309 writes and restores it), so "
              "the fix is a register write or a changed reset default, NOT a clock "
              "change"
              % (int(rate), realtime_ratio, PHC_INTERVAL_S, implied_core_hz / 1e6,
                 incr_for_realtime, ns_incr, ns_incr, hz_for_realtime / 1e6),
              abs(realtime_ratio - 1.0) <= 0.02,
              got="%.6f x real time (%d ns per wall second, ns_incr=%d)"
                  % (realtime_ratio, int(rate), ns_incr))
    if abs(realtime_ratio - 1.0) > 0.02:
        rec.note("THIS RED IS A RESULT ABOUT THE BUILD, NOT ABOUT THE TEST. The RTL "
                 "reset value of NS_INCR is 4, documented as '4 ns for 250 MHz' "
                 "(phc_apb_regs.sv:18, phc_clock_core.sv:9 'Designed for clock "
                 "frequencies of 200-250 MHz'), and 250 MHz is not this design's "
                 "frequency on any target: the ASIC is 100 MHz (wants NS_INCR=10) and "
                 "the KR260/HAPS FPGA builds are 25 MHz (want NS_INCR=40). NS_INCR=4 "
                 "is therefore wrong on BOTH platforms, not just this one -- it is not "
                 "an FPGA-only artefact and it will not fix itself on silicon. Nothing "
                 "in the firmware derives NS_INCR from NANOSOC_SYS_CLK_FREQ_HZ either; "
                 "two apps hard-code 10 (a 100 MHz number) into their own tick maths. "
                 "The PHC is otherwise healthy: HIO-403 proved it enables and counts, "
                 "and the rate is stable -- it counts the wrong number of nanoseconds "
                 "per cycle, which is a one-word fix, not a broken block.")

    # (d) An absolute expectation ONLY if the operator supplies one.
    exp = _env("HOSTIO_PHC_CORE_HZ")
    if exp is None:
        rec.record("phc_expected_core_hz", None)
        rec.note("No HOSTIO_PHC_CORE_HZ set, so NO absolute-frequency assertion was "
                 "made -- deliberately. A hardcoded expectation here was wrong for "
                 "every platform and would have been believed at bring-up. If you know "
                 "this die's PHC clock, pass it: 100000000 for the ASIC "
                 "(ASIC/common.mk CLK_PERIOD=10.0), 25011000 for the KR260 FPGA "
                 "(routed timing summary 39.982 ns), 25000000 for HAPS-SX.")
    else:
        core_hz = int(exp, 0)
        rec.record("phc_expected_core_hz", core_hz)
        lo, hi = core_hz * 0.9, core_hz * 1.1
        rec.check("implied PHC clock within +/-10 %% of the OPERATOR-SUPPLIED %d Hz "
                  "(HOSTIO_PHC_CORE_HZ). This is the only check here that depends on "
                  "a number this suite cannot measure" % core_hz,
                  lo <= implied_core_hz <= hi,
                  got="%.4f MHz (ns_incr=%d)" % (implied_core_hz / 1e6, ns_incr))


@test("HIO-405", tier=4, hazard=None, needs=["HIO-401", "HIO-311"],
      destroys="cc_periph timer0 VALUE and CTRL (CTRL restored to 0 afterwards)",
      purpose="Hardware latency measurement via `P`'s return value -- the capability "
              "that makes this port able to time a hardware interval at HCLK, free of "
              "the ~130 ms link. `P` returns the number of bus reads consumed before "
              "the match, so the count IS the measurement. Polled on the cc_periph "
              "timer0 down-counter, which is the only genuinely free-running location "
              "this port can poll: BOTH of the plan's suggestions turn out to be "
              "shadow latches that a poll can never see advance -- P0_CYC is frozen "
              "until the next SNAP (ctrl_ahb_perf_probe_regs.v:30-32) and "
              "CAP_NANOSECONDS until the next capture write. The PHC form is kept "
              "below as a recorded demonstration of exactly that limitation. Goes red "
              "if a poll that must terminate does not, if the count falls outside the "
              "window the mask implies, or if three measurements return an identical "
              "constant (a canned reply rather than a measurement).")
def hio_405(adp, rec):
    # Free-run the timer from full scale: VALUE is live-readable and decrements
    # every PCLK while CTRL[0] is set (cmsdk_apb_timer.v:132-133,247).
    _wr(adp, TIMER0_CTRL, 0x00000000)
    _wr(adp, TIMER0_VALUE, 0xFFFFFFFF)
    en = _wr(adp, TIMER0_CTRL, 0x00000001)
    rec.check("timer0 enabled as the free-running poll target", _wrote(en), got=en.raw)
    _require_okay(adp, rec, TIMER0_VALUE, "timer0 VALUE 0x28000004")

    # Window chosen so the poll cannot step over it: bits [15:12] == 0 is a
    # 4096-count-wide window in a 65536-count period, and one poll iteration is a
    # handful of HCLK.  Worst case is ~61440 counts, far below the budget.
    mask, value = 0x0000F000, 0x00000000
    window_period = 0x10000
    counts = []
    try:
        for i in range(3):
            r = _poll(adp, TIMER0_VALUE, mask, value, POLL_BUDGET)
            rec.record("latency_poll%d_raw" % i, r.raw)
            rec.check("free-running poll %d matched (no !)" % i, _matched(r), got=r.raw)
            if not _matched(r):
                return
            counts.append(r.value)
            rec.record("latency_poll%d_iterations" % i, r.value)
    finally:
        _wr(adp, TIMER0_CTRL, 0x00000000)     # always leave the timer disabled

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
    rec.note("Shadow-latch demonstration: CAP_NANOSECONDS advances only on a capture "
             "write, so polling it measures a stale value, never the live clock. The "
             "same is true of P0_CYC between SNAPs -- neither can serve as `P`'s "
             "free-running target, which is why this test polls timer0.")


@test("HIO-406", tier=4, hazard=None, needs=["HIO-401", "HIO-311"],
      destroys="cc_periph timer0 VALUE and CTRL (CTRL restored to 0, VALUE left at 0)",
      purpose="Timer counts down, waited on in hardware -- and the cross-validation of "
              "HIO-401 against real hardware, because two independent things must both "
              "be true for it to pass: the timer must actually count AND the poll must "
              "actually terminate. Runs BOTH polarities: with CTRL = 0 the poll must "
              "time out (the negative control the plan names), and with CTRL = 1 it "
              "must match. Two reloads differing by exactly 2x are used so the count "
              "is checked for PROPORTIONALITY, not merely for being non-zero. The "
              "check is on the DIFFERENCE of the counts, not their ratio: the fixed "
              "link overhead between arming and polling cancels out of a difference, "
              "so (reload_b - reload_a) / (n_b - n_a) yields the HCLK cycles per poll "
              "read directly, and requiring that to be physically plausible (1..64) is "
              "a self-calibrating check that needs no assumption about the clock "
              "frequency. Goes red on a match with the timer disabled, a timeout with "
              "it enabled, counts that do not scale, or an impossible cycles-per-read.")
def hio_406(adp, rec):
    # cmsdk_apb_timer.v: 0x00 CTRL ([0] EN), 0x04 VALUE (reg_curr_val, RW, decrements
    # while dec_ctrl), 0x08 RELOAD.  At zero the counter reloads from RELOAD, which is
    # left at its 0 reset value, so VALUE parks at 0 and the poll match is stable.
    reload_a = _env_int("HOSTIO_TIMER_RELOAD", TIMER_RELOAD_A)
    reload_b = min(reload_a * 2, 0xFFFFFFFF)
    rec.record("timer_reload_a", reload_a)
    rec.record("timer_reload_b", reload_b)

    off = _wr(adp, TIMER0_CTRL, 0x00000000)
    rec.check("timer disabled for the negative control", _wrote(off), got=off.raw)
    wv = _wr(adp, TIMER0_VALUE, reload_a)
    rec.check("VALUE preload accepted", _wrote(wv), got=wv.raw)
    rb = _rd(adp, TIMER0_VALUE)
    rec.check("VALUE reads back the preload while disabled",
              _good(rb) and rb.value == reload_a, got=rb.raw)
    rec.record("timer_reload_readback", None if rb.value is None else rb.value)
    rec.record("timer_0x08_reload_reg", _rd(adp, TIMER0_RELOAD).value)

    # Negative control keeps the SMALL budget: it only has to prove that a disabled
    # timer never reaches 0, and a 0x20000000 budget would burn ~30 s on-die.
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
        p = _poll(adp, TIMER0_VALUE, 0xFFFFFFFF, 0x00000000, TIMER_POLL_BUDGET,
                  timeout_ms=TIMER_POLL_TIMEOUT_MS)
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

    # The timer must still have been counting when the poll's first read landed.
    # If it had already parked at 0 the count is 1 and measures only the link.
    if n_a <= 1 or n_b <= 1:
        rec.skip("the timer expired before the poll began (counts %d / %d). The reload "
                 "must be many times the count the clock racks up during the ~2 CU of "
                 "link between arming the timer and the poll's first read; at this "
                 "clock 0x%08X is not. Raise HOSTIO_TIMER_RELOAD (try 4x) and re-run. "
                 "Reported as SKIP because a count of 1 measures the link, not the "
                 "hardware interval -- the polarity result above still stands."
                 % (n_a, n_b, reload_a))

    rec.check("more reload gives more iterations", n_b > n_a,
              got="n_a=%d n_b=%d" % (n_a, n_b))
    if n_b > n_a:
        # Fixed overhead cancels out of the difference, so this is the real
        # cycles-per-poll-read of the ADP's poll loop against an APB target.
        k = (reload_b - reload_a) / float(n_b - n_a)
        rec.record("hclk_cycles_per_poll_read", round(k, 3))
        rec.check("implied HCLK cycles per poll read is physically possible (1..64)",
                  1.0 <= k <= 64.0, got="%.2f cycles" % k)
        rec.record("timer_count_ratio_b_over_a", round(n_b / float(n_a), 3))
    rec.check("run a's count cannot exceed its reload (at least 1 cycle per read)",
              n_a <= reload_a, got="%d iterations for reload 0x%08X" % (n_a, reload_a))
    rec.note("Timer left disabled (CTRL = 0) as the plan requires.")


@test("HIO-407", tier=4, hazard=None,
      purpose="TideLink lane / calibration / FCSM state -- a diagnosis, not just a "
              "verdict. Decodes swi_lane_status @0x2E032108 (RDL-verified: [7:0] "
              "lane_locked (stuck at 0x00 by construction -- never a predicate), "
              "[15:8] lane_fault, [16] calibration_done, [19:17] "
              "fcsm_state, [22:21] llrx_state, [29] llrx_valid). Named failure "
              "signatures are hard reds once the PHY is up: fcsm = 1 is the "
              "credit-path bring-up wedge, fcsm = 2 is the stalled/no-progress "
              "signature, llrx_state = 2 is a link-layer error, and a non-zero "
              "lane_fault byte names the failing lane. Those checks are gated on the "
              "PHY having locked or calibrated, because on a die with no peer every "
              "one of them is legitimately in its down state -- in that case the "
              "record carries link_present = False and only readability is asserted. "
              "BIT 20 IS NOT PART OF fcsm_state, whatever the RDL says: the RTL packs "
              "a 3-bit FCSM at [19:17] and a2l_replay_app_valid at [20] "
              "(axi_chiplet_controller.sv:1796, :2904-2905), so fcsm_state has only "
              "eight legal values and there is no state 8. This test read 8 on the eth "
              "die 2026-08-25 under the old 4-bit decode and called it 'unknown state'; "
              "it was FCSM 0 (idle, correct for a die with no peer) with bit 20 set. "
              "See _decode_lane_status.")
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

    phy_up = _link_up(f)
    rec.record("tl_link_present", bool(phy_up))
    rec.note("lane_locked = 0x%02X is an OBSERVATION, not evidence: the field reads "
             "0x00 even on a healthy working link (known observability defect; "
             "lane_synced_i is tied 8'h00 in the same class). A zero there means "
             "NOTHING either way, so no predicate in this file reads it."
             % f["lane_locked"])
    # The named wedge signatures are asserted UNCONDITIONALLY. They do not depend
    # on the link being up, and they must not be swallowed by the "no link" arm:
    # fcsm=1 IS a credit-path wedge whether or not calibration ever completed, and
    # the documented cold/idle state of a die with no peer is 0, not 1 or 2.
    rec.check("fcsm is not a named wedge signature (1 = credit bring-up, 2 = stalled)",
              f["fcsm_state"] not in (1, 2),
              got="fcsm=%d (%s)" % (f["fcsm_state"], _classify_fcsm(f["fcsm_state"])))

    if not phy_up:
        rec.note("No link: fcsm=%d (%s) is outside the 4..7 band and/or "
                 "calibration_done=%d. lane_fault is not interpretable in that state "
                 "(a lone die legitimately sits here), so it is recorded and not "
                 "asserted. On a die that is supposed to be paired, this line IS the "
                 "finding."
                 % (f["fcsm_state"], _classify_fcsm(f["fcsm_state"]),
                    f["calibration_done"]))
        if f["a2l_replay_app_valid"]:
            rec.note("a2l_replay_app_valid (bit 20) is SET with the link down. That is "
                     "the APP side of the a2l replay buffer holding a word it cannot "
                     "hand to a link that is not up -- expected here, and NOT a wedge. "
                     "The wedge signature is this bit set while the LINK side stays "
                     "empty ON A LIVE LINK, which is read from A2L_REPLAY_OBS, not "
                     "from here (axi_chiplet_controller.sv:2626-2636). Under the old "
                     "4-bit fcsm decode this bit read as 'fcsm_state = 8, unknown "
                     "state' -- a bit-field error, not a die fault.")
        return

    # Reached only with the link up, so these are now interpretable.
    rec.check("no lane reports a sticky fault", f["lane_fault"] == 0,
              got="lane_fault=0x%02X" % f["lane_fault"])
    rec.check("llrx byte-align FSM is not in its error state (2)",
              f["llrx_state"] != 2, got="llrx_state=%d" % f["llrx_state"])
    rec.record("tl_healthy", True)
    rec.note("Healthy operating point: fcsm=%d is in the 4..7 link-up band and "
             "calibration_done=1." % f["fcsm_state"])


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
              "that is not there. PASS = both markers, NOT PARKED, and 0x1E0[23] "
              "data_healthy = 1 (which by construction also asserts wedge_sticky = 0 "
              "and both error bits clear). PARKED is 0x1F8[9] sub_err_sticky high AND "
              "0x1F8[0] bridge_ready low and STILL low on a second sample -- a single "
              "low sample is legitimate mid-transfer, so the register is read twice. "
              "0x1F8[10] xhb_stall_stuck_sticky is RECORDED, NOT GATED: it sets on ANY "
              "healthy cross-die read, because a ~460 us round trip exceeds its "
              "4096-hclk threshold, so gating on it would red the first successful "
              "cross-die read on every working link.")
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

    rec.record("xhb_stall_stuck_sticky_observed", w["xhb_stall_stuck_sticky"])
    rec.check("the bridge is not PARKED (0x1F8[9] set AND 0x1F8[0] low twice)",
              not w["parked"],
              got="sub_err_sticky=%d bridge_ready=%d/%d"
                  % (w.get("sub_err_sticky", -1), w.get("bridge_ready", -1),
                     w.get("bridge_ready_2nd", -1)))
    if w["xhb_stall_stuck_sticky"]:
        rec.note("0x1F8[10] xhb_stall_stuck_sticky is SET. This is EXPECTED on any "
                 "link that has served a cross-die read (~460 us round trip vs a "
                 "4096-hclk threshold) and is NOT a wedge indicator. Recorded, not "
                 "gated.")
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
    # One predicate, one definition: _link_up() is the only place the 4..7 band
    # and calibration_done are written down.
    if not (_link_up(f) and f["lane_fault"] == 0):
        rec.skip("link preconditions not met at the moment of the access: fcsm=%d (%s), "
                 "cal=%d, lane_fault=0x%02X. Phase E aborts here -- do not touch 0x2F."
                 % (f["fcsm_state"], _classify_fcsm(f["fcsm_state"]),
                    f["calibration_done"], f["lane_fault"]))

    before = _read_xhb_witness(adp)
    _record_xhb(rec, before, "peer_pre_xhb")
    if not before["healthy"]:
        rec.skip("XHB witness is not healthy immediately before the access (markers "
                 "%s/%s, parked=%s, data_healthy=%s). Refusing to touch 0x2F."
                 % (before["f8_marker_ok"], before["e0_marker_ok"],
                    before.get("parked"), before.get("data_healthy")))

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
        rec.record("peer_post_stall_sticky_observed", guard["xhb_stall_stuck_sticky"])
        rec.check("GUARD: the bridge is not PARKED (0x1F8[9] high AND 0x1F8[0] "
                  "low and stuck)", not guard["parked"],
                  got="sub_err_sticky=%d bridge_ready=%d/%d"
                      % (guard.get("sub_err_sticky", -1),
                         guard.get("bridge_ready", -1),
                         guard.get("bridge_ready_2nd", -1)))
        rec.check("GUARD: data_healthy still set (no axinode wedge)",
                  guard["data_healthy"] == 1, got="0x%08X" % guard["e0"].value)
        if guard["xhb_stall_stuck_sticky"]:
            rec.note("0x1F8[10] set after the peer access is the EXPECTED signature of "
                     "a cross-die read that actually crossed (~460 us > 4096 hclk). It "
                     "is not evidence of a wedge, and is recorded only.")
        if guard["parked"] or guard["data_healthy"] != 1:
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
      destroys="the first %d bytes of eth IMEM at 0x%08X: zeroed by `F`, overwritten by "
               "`U`, then zeroed again -- so the region is LEFT ZEROED, which is the "
               "cold-die state (plan section 5.5), and is NOT restored to its prior "
               "contents. Those contents are block-read into the record first, but only "
               "the first and last four words are archived. Nothing else on the die is "
               "written: no boot gate, no reset, no peripheral register, and one word "
               "of eth IMEM is written and restored as a pre-flight control."
               % (UPLOAD_REGION_BYTES, UPLOAD_BASE),
      purpose="THE UPLOAD MECHANISM: `F` zero-fill, `U` stream-to-memory, and the "
              "block-read verify -- exercised end to end with a SYNTHETIC payload, so "
              "it needs no firmware and runs on any die. NOTHING ELSE IN THIS SUITE "
              "EMITS `F` OR `U` AT ALL, and until this test ran neither had ever been "
              "exercised on hardware. "
              "TARGET is eth IMEM at 0x%08X, the REMAP-INDEPENDENT alias of that 32 KB "
              "RAM (plan section 1.4). Not 0x00000000: that window is bootrom OR IMEM "
              "depending on the eth REMAP bit, so a carpet write aimed there is a coin "
              "toss between RAM and ROM. Same physical RAM either way. "
              "SEQUENCE. (1) block-read the region and record what was there. "
              "(2) POSITIVE CONTROL, before anything destructive: write a tag to word "
              "0, read it back, restore it. That proves the target is writable RAM and "
              "that the ADP write path lands data -- and a die that fails it is left "
              "EXACTLY as found, because no `F` has been issued yet. "
              "(3) `Vx00000000` ; `A` ; `Fx%08X` -- zero %d words. (4) verify every one "
              "of them reads zero. (5) `A` ; `Ux%08X` + %d payload bytes. (6) verify "
              "every payload word, the guard words past it, and the final byte twice. "
              "(7) `F` again, leaving the region zeroed. "
              "WHY THE PRE-ZERO IS NOT OPTIONAL, AND WHY STEP 4 EXISTS: without it a "
              "`U` that wrote nothing verifies perfectly against whatever was already "
              "there, and 'the tail is still zero, so the upload was short' is not a "
              "valid inference. Step 4 is what turns the pre-zero from an assumption "
              "into a measurement. "
              "WHY THE FINAL BYTE IS RE-READ ON ITS OWN, TWICE: `F` and `U` OR HRESP "
              "into adp_bus_err only in the loop-CONTINUE branch "
              "(socdebug_adp_control.v:631 and :651), so the beat that ENDS the "
              "transfer skips the capture entirely -- a fill or an upload whose only "
              "erroring beat is its last one echoes perfectly clean. The last beat is "
              "exactly where a silent failure hides, so it is read back as an aligned "
              "32-bit access AND as an 8-bit access of that byte alone (`R1`, the form "
              "measured in HIO-006), neither of which depends on the block dump. "
              "THE PAYLOAD IS POSITION-DEPENDENT, AND EACH PROPERTY CATCHES A DIFFERENT "
              "FAILURE. p(off) = 1 + (0x67*off + 0x2D) mod 255. (a) INJECTIVE: 0x67 is "
              "coprime with 255 and the payload is inside one 255-offset window, so no "
              "two offsets hold the same byte -- which is what makes ADDRESS ALIASING "
              "and an address that fails to increment visible. A constant pattern "
              "cannot see either, because every location then holds the right value "
              "whatever the address bus did. (b) NEVER ZERO: the range is 1..255, so "
              "combined with the PROVEN pre-zero 'this byte was never written' reads "
              "back as a value the payload cannot produce -- which is what catches "
              "TRUNCATION and dropped beats. (c) ADJACENT BYTES DIFFER, so byte "
              "ORDERING inside a word is checked too; and if every word matches the "
              "byte-reversed assembly instead, that is reported as the named finding "
              "rather than as a generic mismatch (BE = 0, nanosoc_multicore_soc.sv:45). "
              "(d) the %d GUARD words past the payload must still read zero, which "
              "catches an OVERRUN. "
              "THE COUNT GUARD: `U` has no abort and no timeout, so the count must "
              "equal the payload length exactly or the port parks in ADP_UREADB until a "
              "host PIO resync. _upload() takes a payload and NO count, and re-parses "
              "the count out of the very byte string it is about to transmit -- a "
              "mismatch is unconstructible, not merely avoided. "
              "COST: ~50 command round trips plus %d streamed bytes. At the measured "
              "1 CU ~= 65 ms and ~1 ms per streamed byte that is ~4 s; the twelve "
              "16-word block dumps are the only replies much larger than one line, so "
              "budget 5-10 s. Note this is nowhere near %d x 130 ms: `U` streams one "
              "byte per link byte, `F` fills the whole region in ONE command, and a "
              "block dump reads 16 words in one. "
              "WHAT THIS TEST DOES NOT DO: it does not load firmware. That half needs "
              "an image, none exists in this tree, and it is recorded as not-run rather "
              "than silently folded in -- see the notes and HIO-502."
              % (UPLOAD_BASE, UPLOAD_REGION_WORDS, UPLOAD_REGION_WORDS,
                 UPLOAD_PAYLOAD_BYTES, UPLOAD_PAYLOAD_BYTES,
                 UPLOAD_GUARD_BYTES // 4, UPLOAD_PAYLOAD_BYTES,
                 UPLOAD_REGION_BYTES // 4))
def hio_501(adp, rec):
    base = UPLOAD_BASE
    nbytes = UPLOAD_PAYLOAD_BYTES
    region_words = UPLOAD_REGION_WORDS
    payload_words = nbytes // 4
    guard_words = region_words - payload_words
    payload = _pattern_payload(nbytes)

    rec.record("upload_base", "0x%08X" % base)
    rec.record("upload_payload_bytes", nbytes)
    rec.record("upload_guard_bytes", UPLOAD_GUARD_BYTES)
    rec.record("upload_region_words", region_words)
    rec.record("upload_pattern",
               "p(off) = 1 + (0x%02X*off + 0x%02X) mod %d, off = 0..%d"
               % (PATTERN_MUL, PATTERN_ADD, PATTERN_MOD, nbytes - 1))
    rec.record("upload_payload_first8",
               ["0x%02X" % b for b in bytearray(payload[:8])])
    rec.record("upload_payload_last_byte", "0x%02X" % _pattern_byte(nbytes - 1))

    # -- 1. what was there.  Recorded BEFORE anything is written. -------------
    before, before_ok = _read_region(adp, rec, base, region_words, "pre")
    rec.check("the target region block-reads cleanly BEFORE anything is written "
              "(%d words at 0x%08X, in 16-word `R x<n>` dumps)"
              % (region_words, base), before_ok, got=_words_summary(before))
    if not before_ok:
        rec.note("STOP -- and nothing destructive was issued. Without a clean read "
                 "there is no pre-state to record and no baseline to compare against, "
                 "so the `F` was not sent. Fix the read path first.")
        return
    rec.record("pre_region_first4", ["0x%08X" % w for w in before[:4]])
    rec.record("pre_region_last4", ["0x%08X" % w for w in before[-4:]])
    nonzero = sum(1 for w in before if w)
    rec.record("pre_region_nonzero_words", nonzero)
    rec.record("pre_region_all_zero", nonzero == 0)
    if nonzero:
        rec.note("THE REGION WAS NOT EMPTY: %d of %d words held data, and this test "
                 "destroys them. On a cold die eth IMEM is all zeros (plan section 5.5) "
                 "and that costs nothing; on a die where firmware had been loaded it "
                 "does. Only the first and last four words are archived above -- this "
                 "test does not back IMEM up." % (nonzero, region_words))

    # -- 2. positive control.  The last moment at which nothing has changed. --
    orig = before[0]
    tag = (UPLOAD_PROBE_TAG if orig != UPLOAD_PROBE_TAG
           else (~UPLOAD_PROBE_TAG) & 0xFFFFFFFF)
    pw = _wr(adp, base, tag)
    pr = _rd(adp, base)
    landed = _wrote(pw) and _good(pr) and pr.value == tag
    rec.record("probe_tag", "0x%08X" % tag)
    rec.record("probe_write_reply", pw.raw)
    rec.record("probe_read_reply", pr.raw)
    rec.check("POSITIVE CONTROL: 0x%08X is WRITABLE RAM and the ADP write path lands "
              "data on it (0x%08X written, read back bit for bit). Without this the "
              "whole test can pass vacuously against ROM or a dead write path, and it "
              "runs BEFORE the destructive `F` so a die that fails it is left untouched"
              % (base, tag), landed, got="W=%s R=%s" % (pw.raw, pr.raw))
    rw = _wr(adp, base, orig)
    rec.record("probe_restore_reply", rw.raw)
    if not landed:
        rec.note("STOP. No `F` and no `U` were issued. The word at 0x%08X did not take "
                 "a plain 32-bit write, so this is not writable RAM -- and the eth "
                 "REMAP bit cannot explain it at 0x10000000, which is IMEM whatever "
                 "remap says (plan section 1.4). Suspect the write path (HIO-313) or "
                 "the decode, not the upload mechanism." % base)
        return

    destructive = False
    raised = False
    try:
        # -- 3. the `F` pre-zero ------------------------------------------------
        destructive = True
        v, a, f = _fill_words(adp, rec, base, region_words, 0x00000000, "prezero")
        rec.record("prezero_v_reply", v.raw)
        rec.record("prezero_a_reply", a.raw)
        rec.record("prezero_f_reply", f.raw)
        rec.check("`Vx00000000` accepted -- it sets the fill VALUE and, through its "
                  "digit count, the 32-bit fill SIZE that `F` then uses",
                  v.ok and v.letter == "V" and not v.error, got=v.raw)
        rec.check("`Ax%08X` accepted (the fill base)" % base,
                  a.ok and a.letter == "A" and not a.error, got=a.raw)
        rec.check("`Fx%08X` returned a well-formed reply with no bus-error flag"
                  % region_words,
                  f.ok and f.letter == "F" and not f.error, got=f.raw)

        # -- 4. prove the pre-zero.  This is what makes step 6 mean anything. ---
        zeroed, zero_ok = _read_region(adp, rec, base, region_words, "postfill")
        all_zero = zero_ok and all(w == 0 for w in zeroed)
        rec.check("EVERY one of the %d words reads back 0x00000000 after `F`. This is "
                  "what makes the upload verify meaningful: without a PROVEN pre-zero, "
                  "a `U` that wrote nothing still verifies against whatever was already "
                  "there, and 'the tail is still zero so the upload was short' is not a "
                  "valid inference" % region_words,
                  all_zero, got=_words_summary(zeroed))
        last_f = _rd(adp, base + (region_words - 1) * 4)
        rec.record("prezero_last_word_reply", last_f.raw)
        rec.check("the LAST word of the fill, re-read on its own, is 0x00000000. `F` "
                  "ORs HRESP into adp_bus_err only in its loop-CONTINUE branch "
                  "(socdebug_adp_control.v:651), so a fill whose only erroring beat is "
                  "its last one echoes clean -- this read is what catches that",
                  _good(last_f) and last_f.value == 0, got=last_f.raw)
        if not all_zero:
            rec.note("STOP before `U`. The pre-zero did not hold, so any upload verify "
                     "after it would be uninterpretable: a matching word could be the "
                     "upload or could be what was there already. The region is "
                     "re-zeroed on the way out.")
            return

        # -- 5. the upload -----------------------------------------------------
        up = _upload(adp, rec, base, payload, "upload")
        u = up["reply"]
        rec.record("upload_echo_raw", u.raw)
        rec.record("upload_echo_text_tail", up["text"][-80:])
        rec.check("the link accepted every byte of the command line plus the %d-byte "
                  "payload. A SHORT COUNT IS THE ONE FAILURE THAT MATTERS HERE: `U` has "
                  "no abort and no timeout, so a short stream leaves the FSM parked in "
                  "ADP_UREADB waiting for bytes that never come" % nbytes,
                  up["sent"] == up["frame_len"],
                  got="%d of %d bytes accepted" % (up["sent"], up["frame_len"]))
        rec.check("`U` echoed a well-formed reply and returned to the prompt, so the "
                  "FSM consumed exactly the byte count it was given and left "
                  "ADP_UREADB of its own accord",
                  u.ok and u.letter == "U", got=u.raw)
        rec.check("`U` echoed back the count it was given (0x%08X = %d bytes)"
                  % (nbytes, nbytes), u.value == nbytes, got=u.raw)
        rec.check("`U` raised no bus-error flag. Note this covers every beat EXCEPT the "
                  "last, whose HRESP is not captured (socdebug_adp_control.v:631) -- "
                  "which is why the final byte is read back separately below",
                  u.ok and not u.error, got=u.raw)

        # -- 6. verify ---------------------------------------------------------
        got, got_ok = _read_region(adp, rec, base, region_words, "postupload")
        rec.check("the region block-reads cleanly after the upload", got_ok,
                  got=_words_summary(got))
        body = got[:payload_words]
        want_le = [_pattern_word_le(i * 4) for i in range(payload_words)]
        want_be = [_pattern_word_be(i * 4) for i in range(payload_words)]
        matched_le = (body == want_le)
        matched_be = (body == want_be)
        first_bad = next((i for i in range(payload_words) if body[i] != want_le[i]),
                         None)
        rec.record("upload_first_mismatch_word", first_bad)
        if first_bad is not None:
            rec.record("upload_first_mismatch",
                       "word %d at 0x%08X: got %s, want 0x%08X"
                       % (first_bad, base + first_bad * 4,
                          "None" if body[first_bad] is None
                          else "0x%08X" % body[first_bad], want_le[first_bad]))
        rec.check("all %d payload words read back BYTE-EXACT against the "
                  "position-dependent pattern. Because p() is injective across the "
                  "payload this also rules out address aliasing and a non-incrementing "
                  "address; because p() is never zero it also rules out a short or "
                  "dropped write hiding behind a legitimately zero byte"
                  % payload_words,
                  matched_le,
                  got=("all match" if matched_le else
                       "first mismatch at word %s" % first_bad))
        if matched_be and not matched_le:
            rec.note("EVERY word matches the BYTE-REVERSED assembly of the same "
                     "pattern. That is not a corrupt upload -- it is a byte-order "
                     "result, and a surprising one: this build is little-endian by "
                     "construction (`parameter BE = 0` at "
                     "nanosoc_multicore_soc.sv:45, fed to both CPU integrations at "
                     ":846 and :962). Either the `U` byte lane select is wrong "
                     "(HADDR[1:0] = adp_addr[1:0] at socdebug_adp_control.v:377) or "
                     "the read rotation is. Do not re-run before resolving it.")

        tail = got[payload_words:]
        rec.check("the %d GUARD words past the payload are STILL 0x00000000, so `U` "
                  "wrote exactly %d bytes and not one more" % (guard_words, nbytes),
                  all(w == 0 for w in tail), got=_words_summary(tail))

        want_last = _pattern_byte(nbytes - 1)
        lw = _rd(adp, base + (payload_words - 1) * 4)
        rec.record("final_word_reply", lw.raw)
        rec.check("THE FINAL BYTE, part 1: the last payload WORD re-read on its own at "
                  "0x%08X carries 0x%02X in its top byte. `U` does not capture HRESP on "
                  "its last beat (socdebug_adp_control.v:631), so an upload whose only "
                  "erroring beat is the last one echoes clean; this read uses nothing "
                  "but the proven `A` + `R` form"
                  % (base + (payload_words - 1) * 4, want_last),
                  _good(lw) and ((lw.value >> 24) & 0xFF) == want_last,
                  got="%s (top byte %s, want 0x%02X)"
                      % (lw.raw,
                         "n/a" if lw.value is None else "0x%02X" % ((lw.value >> 24) & 0xFF),
                         want_last))
        lb = _read_byte(adp, base + nbytes - 1)
        rec.record("final_byte_reply", lb.raw)
        rec.record("final_byte_width_nibbles", lb.width)
        rec.check("THE FINAL BYTE, part 2: read as an 8-bit access of that byte alone "
                  "(`A x%08X` ; `R1`) it is 0x%02X, in a 2-nibble reply. This is the "
                  "byte-precise form -- an aligned word read cannot distinguish which "
                  "byte lane failed"
                  % (base + nbytes - 1, want_last),
                  lb.ok and lb.letter == "R" and not lb.error
                  and lb.value == want_last and lb.width == 2,
                  got="%s (value=%s width=%s nibbles, want 0x%02X in 2)"
                      % (lb.raw, lb.value, lb.width, want_last))

        # -- the half that still needs firmware --------------------------------
        image = _env("HOSTIO_CPU0_IMAGE")
        rec.record("cpu0_image_configured", image is not None)
        rec.record("cpu0_image_loaded", False)
        if image is None:
            rec.note("NO FIRMWARE WAS LOADED, AND HIO-502 NEEDS TO KNOW THAT. This test "
                     "proved the transport, not a boot image: it leaves eth IMEM "
                     "ZEROED. If HIO-502 is run now it releases CPU0 into an empty "
                     "IMEM -- which is survivable (CPU0 does not source the fabric "
                     "clock; it faults or locks up) and is the state plan section 5.5 "
                     "already observed on the FPGA, but it is not a firmware test. "
                     "To load an image, set HOSTIO_CPU0_IMAGE: a raw binary (not ELF, "
                     "not hex) of at most 32768 bytes, a complete Cortex-M vector table "
                     "plus code. No such image exists in this tree today.")
        else:
            rec.record("cpu0_image_path", image)
            if os.path.isfile(image):
                rec.record("cpu0_image_bytes", os.path.getsize(image))
            rec.note("HOSTIO_CPU0_IMAGE IS SET BUT WAS NOT LOADED, and eth IMEM is left "
                     "ZEROED -- do not run HIO-502 expecting that image to be there. "
                     "This test deliberately covers the MECHANISM only: loading a real "
                     "image means zeroing all 32 KB and verifying a region whose size "
                     "and cost are set by the image, which is a different test with a "
                     "different runtime. The transport it would use is exactly the one "
                     "just proved here -- _upload() with the same count guard.")
        return
    except BaseException:
        raised = True
        raise
    finally:
        # -- 7. leave it clean -------------------------------------------------
        if destructive and not raised:
            cv, ca, cf = _fill_words(adp, rec, base, region_words, 0x00000000,
                                     "cleanup")
            z0 = _rd(adp, base)
            z1 = _rd(adp, base + (region_words - 1) * 4)
            rec.record("cleanup_f_reply", cf.raw)
            rec.record("cleanup_first_word", z0.raw)
            rec.record("cleanup_last_word", z1.raw)
            rec.check("THE REGION IS LEFT ZEROED: the cleanup `F` reported no bus "
                      "error and the first and last words both read 0x00000000. This "
                      "test leaves eth IMEM in the cold-die state, not holding a test "
                      "pattern -- but it does NOT restore the prior contents, which are "
                      "gone",
                      cv.ok and ca.ok and cf.ok and not cf.error
                      and _good(z0) and z0.value == 0
                      and _good(z1) and z1.value == 0,
                      got="F=%s first=%s last=%s" % (cf.raw, z0.raw, z1.raw))
        elif destructive:
            rec.record("cleanup", "NOT RUN -- the test raised, so no further commands "
                                  "were issued; the region holds whatever the last "
                                  "completed step wrote")


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
              "(remap_q <= remap_q | HWDATA[3:0]) and reset only on PORESETn. "
              "READ THIS BEFORE ARMING IT: `needs=HIO-501` no longer means an image "
              "was loaded. HIO-501 now PASSes on the upload MECHANISM alone, with a "
              "synthetic pattern, and LEAVES ETH IMEM ZEROED unless a firmware image "
              "was supplied -- check its cpu0_image_loaded record. Releasing CPU0 into "
              "a zeroed IMEM is survivable (CPU0 does not source the fabric clock, and "
              "it is the state plan section 5.5 already observed on the FPGA) but it "
              "is a bus-contention experiment, not a firmware test, and it is still "
              "irreversible for this power cycle.")
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
      destroys="NOTHING -- it makes no bus access at all. The hazards stay declared "
               "because they describe what this test WOULD do if its target were "
               "safe: overwrite CPU1 IMEM (16 KB at 0x90000000), set boot-gate bit 0 "
               "(irreversible, HZ-4), and restart CPU1, which resets the WHOLE SoC "
               "including the ADP and HOSTIO itself (HZ-5). Removing them would let a "
               "future edit re-enable the upload without an operator opting in.",
      purpose="CPU1 memory preload -- REFUSED AT THE TARGET, NOT FOR WANT OF A "
              "MECHANISM. Structured exactly like HIO-501, and it would use the same "
              "_upload() with the same count guard against the same `U`; 0x90000000 is "
              "a remap-independent alias of CPU1 IMEM, so the preload would work "
              "whatever CPU1's REMAP bit says. What stops it is that CPU1 IS EXECUTING "
              "OUT OF THE MEMORY IT WOULD OVERWRITE AND CANNOT BE STOPPED FIRST: "
              "`.cpu1_bootgate (1'b1)` is tied high at the SoC top "
              "(nanosoc_multicore_soc.sv:1387) and cpu1_resetn = cpu1_bootgate & "
              "~cpu1_reset_pulse (nanosoc_reset_ctrl.v:364), so unlike CPU0 there is no "
              "hold-in-reset / load / release order available from this port. And the "
              "failure mode is the whole die rather than one core: CPU1's PRMU sources "
              "the fabric's HCLK and HRESETn, so a CPU1 faulting on half-overwritten "
              "code can take the fabric, the ADP and HOSTIO down with it -- the very "
              "port that would diagnose it. THE REFUSAL IS IN CODE, NOT IN THIS TEXT: "
              "0x90000000 is deliberately absent from _BULK_WRITE_REGIONS, so "
              "_check_bulk_write() rejects any `F` or `U` aimed at it even if the guard "
              "in the body were deleted. It reports SKIP with that reasoning rather "
              "than being dropped, so 'CPU1 preload untested, and why' stays in the "
              "coverage record.")
def hio_508(adp, rec):
    image = _env("HOSTIO_CPU1_IMAGE")
    rec.record("cpu1_image_configured", image is not None)
    if image is not None:
        rec.record("cpu1_image_path", image)
        if os.path.isfile(image):
            rec.record("cpu1_image_bytes", os.path.getsize(image))
        else:
            rec.record("cpu1_image_bytes", None)
    rec.record("cpu1_upload_target", "0x%08X (NOT in _BULK_WRITE_REGIONS)" % CPU1_IMEM)
    _refuse_cpu1_upload(rec)


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
