"""HOSTIO4 / ADP test suite — Tier 2 (memory integrity) and Tier 3 (register behaviour).

Implements HIO-201..211 and HIO-301..314 from
``docs/bringup/HOSTIO4_FUNCTIONAL_TEST_PLAN.md`` against the pinned API in
``CONTRACT.md``.  Nothing here is shared with any other tier module.

===============================================================================
READ THIS BEFORE RUNNING TIER 2
===============================================================================

**Tier 2 is destructive by construction.**  Every test that mutates memory
carries ``hazard=HZ.DESTRUCTIVE`` and a ``destroys=`` string, so the runner
refuses the whole tier without ``--allow-destructive``.  Capture these BEFORE
Phase D (plan §3, Phase D preamble):

  * the boot-confirm token in shared SRAM  -> destroyed by HIO-208
  * eth DMEM word 0 (``SystemCoreClock``, the HIO-107 evidence) -> HIO-205
  * ``RESET_INFO_CPU0``                    -> destroyed by HIO-302 (Tier 3)
  * TideChart ``TC_ERROR`` sticky flags    -> destroyed by HIO-303 (Tier 3)
  * the ``bus_fault_monitor`` record       -> destroyed by HIO-308 (Tier 3)

===============================================================================
DEFECTS FOUND IN THE PLAN'S LITERAL COMMAND SEQUENCES  (all fixed here)
===============================================================================

``R`` and ``W`` both auto-increment the ADP address register (plan §1.2).
Several of the plan's written sequences issue ``A x<addr> ; R ; W…`` — which
puts the write at **addr+4**, not at addr.  Consequences, and what this module
does instead (it re-issues ``A`` before every access, via ``adp.read`` /
``adp.write``, which the CONTRACT guarantees do so):

  * **HIO-209** — ``A x08000000 ; R ; W xdeadbeef ; A x08000000 ; R`` writes
    ROM *word 1* and then checks *word 0* is unchanged.  As written the test
    **passes unconditionally on RAM as well as on ROM**: a vacuous green in the
    one test whose entire value is that it can fail.  This is the worst of the
    set.
  * **HIO-301** — the restoring ``Wx00000000`` lands on ``0x2A00000C``, so
    ``SYS_CTRL.LOCKUPRESETEN`` is **left set**, which is precisely the state
    the plan's own hazard note warns corrupts later tests.
  * **HIO-306** — same shape: ``etc_capture.CTRL.GLOBAL_EN`` is left **set**.
  * **HIO-307** — the CLR write lands on ``0x2C20000C``, not on ``CTRL``.
  * **HIO-302** — the ``Wx<v>`` W1C-clear lands on ``RESET_INFO_CPU1``
    (``0x2A000014``) and clears *that* record instead.
  * **HIO-303** — the ``Wx00000007`` lands on ``0x2E040030``, the TideChart PUF
    seed word, instead of ``TC_ERROR``.
  * **HIO-305** — the ``R`` after the LOCK write reads ``PERIPH_ID``
    (``0x23000034`` = ``0xC0DE0001``, which has bit 0 set) instead of LOCK.
  * **HIO-309** — the ``NS_INCR`` write lands on ``0x2200000C``; the ``INT_EN``
    readback reads ``0x22000020``.
  * **HIO-312** — both restoring writes land one word past their register.
  * **HIO-203/204** — the "prove the last word" follow-up
    ``A x10007ffc ; R ; W x5a5a5a5a`` writes at ``0x10008000``, which aliases
    back to offset 0 — so it proves the *first* word, not the last, and leaves
    the ``F`` off-by-one hole (plan §1.5) uncovered.
  * **HIO-313 — the dangerous one.**  ``A x29000000 ; R ; Wx00000000`` puts the
    boot-gate write at ``0x29000004``.  It is a no-op *only* because
    ``chip_core_remap_ctrl`` ignores ``HADDR`` entirely
    (``chip_core_remap_ctrl.v:92``, verified) and because the datum is 0.  The
    safety of Abort Gate 8 should not rest on an address-decode accident.
    See ``_bootgate_noop_write`` below for the guard used instead.

Two register mislabels, also fixed:

  * **HIO-311** calls ``0x28000004`` RELOAD and ``0x28000008`` VALUE.  The CMSDK
    map is ``0x00 CTRL / 0x04 CURRENT VALUE / 0x08 RELOAD``
    (``cmsdk_apb_timer.v:29-38``, verified).  This module exercises **both**
    words so the plan's intent (RELOAD is writable) and its literal sequence
    (``0x04`` is writable) are each covered and correctly named.
  * **HIO-307**'s "``P0_CYC`` restarts from a small value" needs a bound.
    ``P0_CYC`` is documented *saturating*, not wrapping
    (``perf_probe.yaml``), so a die up for >43 s at 100 MHz sits at
    ``0xFFFFFFFF`` and "small" is well defined.  The bound used here is derived
    from the host-measured elapsed time, not hard-coded.

===============================================================================
CPU1 IS RUNNING WHILE HIO-206 / HIO-207 TEST ITS RAMs
===============================================================================

``cpu1_bootgate`` is tied ``1'b1`` (``nanosoc_multicore_soc.sv:1387``), so CPU1
**cannot be held in reset** and is executing while its IMEM and DMEM are under
test.  A running CPU legitimately rewrites its own stack, so a mismatch is not
evidence of a fault.  The plan (§3, D4) offers two honest options:

  (a) **run anyway and treat mismatches as INCONCLUSIVE** — the default here.
      HIO-206/207 downgrade the per-cell assertions to recorded observations
      and keep only the assertions a live CPU cannot explain:
        * no bus error and no NO-REPLY anywhere inside the declared window;
        * at least one sampled cell retained what was written (a CPU cannot
          rewrite an entire RAM inside one link round trip, but a missing or
          fully-aliased macro shows up here immediately).
      Both tests are declared ``weak=True`` in this mode, because their primary
      assertion has been withdrawn.  They are *not* counted as full coverage.

  (b) **park CPU1 first**, then re-run with ``HOSTIO_CPU1_PARKED=1`` set, which
      restores the strict per-cell assertions and clears ``weak``.  Parking
      (plan §3 D4, HIO-508's mechanism):
          1. preload a two-instruction spin loop at ``0x90000000``;
          2. set ``0x29000000`` bit 0 so CPU1's address 0 maps to IMEM
             — **irreversible within this power cycle (HZ-4)**;
          3. pulse ``CPU1_SWRST`` (``0x2A000020`` bit 1) — **this resets the
             fabric, the ADP and HOSTIO itself (HZ-5)**; the banner reappears.
      Neither step is performed by this module; both are outside Tier 2/3.

**Additional risk not spelled out in the plan.** CPU1's PRMU is the source of
the whole SoC's ``HCLK``/``HRESETn`` (§1.6, HZ-5).  Filling CPU1's DMEM
destroys CPU1's live stack, so CPU1 will fault on its next return.  A faulting
CPU1 that reaches its PRMU registers can take the fabric clock — and therefore
HOSTIO — down with it.  Budget a power cycle around HIO-207 and prefer to run
it last.  ``TIER2_RECOMMENDED_ORDER`` below encodes an order that keeps the
cheap high-value tests ahead of it.

===============================================================================
COST MODEL
===============================================================================

1 CU = one ADP command round trip ~= 65 ms measured (plan §2.0).  ``adp.read``
and ``adp.write`` are ``A``+``R`` / ``A``+``W`` = 2 CU ~= 130 ms each.  Every
test states its own budget in ``purpose``.

Whole-RAM *writes* go through the ``F`` engine (one command, ~4700x cheaper
than a dump).  Whole-RAM *reads* do not: a full ``R<n>`` dump returns thousands
of replies, which the pinned ``Reply`` API cannot represent, and costs ~18 min
per 32 KB.  Verification here is therefore **strided sampling** — every cell is
written, a fixed deterministic sample is read back — plus an explicit last-word
write/read that closes the ``F``/``U`` off-by-one hole in §1.5.  Each test says
so in its ``purpose``; none of them claims full-RAM read coverage.

Environment knobs (host-side only, they touch nothing on the die):
  ``HOSTIO_CPU1_PARKED=1``   CPU1 has been parked -> HIO-206/207 run strict.
  ``HOSTIO_SOAK_SECONDS=N``  HIO-211 soak length (default 60).
"""

from __future__ import annotations

import os
import time

from harness import Adp, Reply, test, Rec, HZ


# ---------------------------------------------------------------------------
# Memory map (plan §1.4, R-class: read out of the generated RTL)
# ---------------------------------------------------------------------------

ETH_ROM_BASE = 0x08000000          # eth boot ROM alias, 2 KB, remap-independent
ETH_IMEM_BASE = 0x10000000         # eth IMEM alias, 32 KB, remap-independent
ETH_IMEM_SIZE = 32 * 1024
ETH_DMEM_BASE = 0x18000000         # eth DMEM, 16 KB
ETH_DMEM_SIZE = 16 * 1024
SHARED_SRAM_BASE = 0x2D000000      # shared cross-core SRAM, 8 KB
SHARED_SRAM_SIZE = 8 * 1024
CPU1_ROM_BASE = 0x80000000         # CPU1 boot ROM, 2 KB
CPU1_IMEM_BASE = 0x90000000        # CPU1 IMEM, 16 KB
CPU1_IMEM_SIZE = 16 * 1024
CPU1_DMEM_BASE = 0x98000000        # CPU1 DMEM, 8 KB
CPU1_DMEM_SIZE = 8 * 1024

ROM_DIFF_OFFSET = 0x0E4            # first word where the two boot ROMs differ (HIO-102)

PAT_A = 0x5A5A5A5A
PAT_B = 0xA5A5A5A5
ROM_POISON = 0xDEADBEEF
WRITE_PATH_TAG = 0x0BADC0DE

# SYS_CLK_FREQ_HZ = 100 MHz (0x05F5E100, the HIO-107 DMEM word 0 initialiser).
ASSUMED_HCLK_HZ = 100_000_000

SOAK_SECONDS = int(os.environ.get("HOSTIO_SOAK_SECONDS", "60"))


def _env_flag(name: str) -> bool:
    return os.environ.get(name, "").strip().lower() in ("1", "true", "yes", "y", "on")


#: CPU1 has been parked out of its RAMs by the operator (plan §3 D4 option b).
#: Read once at import so it can feed the ``weak=`` kwarg of HIO-206/207.
CPU1_PARKED = _env_flag("HOSTIO_CPU1_PARKED")


#: Plan §3 Phase D order, with the CPU1 pair deliberately last (see the module
#: docstring: HIO-207 can take the fabric clock down with CPU1).  A runner that
#: sorts by test ID gets a different, still-valid but riskier order.
TIER2_RECOMMENDED_ORDER = [
    "HIO-201", "HIO-202", "HIO-210",          # D2 eth IMEM, per-cell
    "HIO-203", "HIO-204",                     # D2 eth IMEM, bulk
    "HIO-205", "HIO-208",                     # D3 eth DMEM, shared SRAM
    "HIO-209", "HIO-211",                     # D5 pulled ahead of D4 on purpose
    "HIO-206", "HIO-207",                     # D4 CPU1 (may cost a power cycle)
]

#: Plan §3 Phase C order.  HIO-313 first (Abort Gate 8), HIO-314 last (it
#: retro-validates every identity constant Tier 1 recorded).  HIO-308 and
#: HIO-310 are absent from the plan's C3 list; they are slotted in ID order.
TIER3_RECOMMENDED_ORDER = [
    "HIO-313",
    "HIO-301", "HIO-302", "HIO-303", "HIO-304", "HIO-305", "HIO-306",
    "HIO-307", "HIO-308", "HIO-309", "HIO-310", "HIO-311", "HIO-312",
    "HIO-314",
]


# ---------------------------------------------------------------------------
# Hazard guard — the blocklist as code, not as operator discipline
# ---------------------------------------------------------------------------
#
# The plan says of HIO-114 and HIO-310 that the exclusion list "must be encoded
# in the census script, not left to the operator", and of HZ-1 that
# "simulation can never catch that mistake for you".  So every access in this
# module goes through _r()/_w(), which refuse a hazard address outright.  A
# violation is a programming error and raises rather than reporting a result.

class HazardGuard(Exception):
    """Raised when a test tries to touch an address the plan quarantines."""


#: (lo, hi, why) — never read, never write.
_NEVER_TOUCH = (
    (0x2E0321A0, 0x2E0321B8, "HZ-1 TideLink SYNC_DIST band: uninterruptible AXI hang, power cycle to recover"),
    (0x2F000000, 0x2FFFFFFF, "HZ-2 peer aperture: a failed read parks the peer port and the next access wedges the host"),
    (0x2E000000, 0x2E003FFF, "HZ-3 TideLink TX aperture: wedges on a write while the link is up"),
    (0x24000000, 0x24FFFFFF, "HZ-6 QSPI XiP aperture: 1.3 ms stall minimum, livelock with flash fitted"),
)

#: HZ-8 — a read *is* a write here (read-clearing / auto-incrementing).
_READ_CLEARING = frozenset(
    (0x2E032020, 0x2E032024, 0x2E032038, 0x2E03215C, 0x2E032160, 0x2E032168)
)

#: HZ-7 — a read of one of these pages ACQUIRES a lock.  Page = HADDR[9:8];
#: 0 = CPU0, 1 = CPU1, 2 = DBG.  Page 3 (0x2C100300, DIAG) is not an acquire
#: page and is safe (``hw_spinlock.v:154-156``, verified).
_SPINLOCK_ACQUIRE_PAGES = ((0x2C100000, 0x2C1000FF), (0x2C100100, 0x2C1001FF), (0x2C100200, 0x2C1002FF))

#: Writes that are irreversible or that reset the SoC.  Nothing in Tier 2/3
#: legitimately writes any of these.  HIO-313's guarded no-op is the single
#: sanctioned exception and it does not go through _w().
_NEVER_WRITE = (
    (0x29000000, 0x29FFFFFF, "HZ-4 boot gates are write-1-set and cleared only by PORESETn; "
                             "use _bootgate_noop_write() for HIO-313"),
    (0x2A000020, 0x2A000023, "HZ-5 SW_RESET: bit 1 CPU1_SWRST resets the fabric, the ADP and HOSTIO itself"),
    (0x2B000010, 0x2B000013, "evt_route ROUTE_LOCK is one-way until HRESETn"),
    (0x2E040008, 0x2E04000B, "TideChart TC_CTRL bit 3 re-arms the election"),
    (0x28008000, 0x28008FFF, "cc_periph watchdog: arming it starts a reset countdown"),
)

QSPI_CTRL = 0x21000000
QSPI_CMD = 0x21000008
QSPI_ADDR = 0x2100000C
QSPI_CMD_ENABLE_BIT = 1 << 8       # CMD[8]: starts a flash transaction.  Never set it.


def _guard(addr: int, write: bool, allow_acquire: bool = False) -> None:
    for lo, hi, why in _NEVER_TOUCH:
        if lo <= addr <= hi:
            raise HazardGuard("refusing %s 0x%08X: %s" % ("write to" if write else "read of", addr, why))
    if not write:
        if addr in _READ_CLEARING:
            raise HazardGuard("refusing read of 0x%08X: HZ-8, this read clears live credit bookkeeping" % addr)
        if not allow_acquire:
            for lo, hi in _SPINLOCK_ACQUIRE_PAGES:
                if lo <= addr <= hi:
                    raise HazardGuard(
                        "refusing read of 0x%08X: HZ-7, reading a spinlock acquire page acquires the lock" % addr)
    else:
        for lo, hi, why in _NEVER_WRITE:
            if lo <= addr <= hi:
                raise HazardGuard("refusing write to 0x%08X: %s" % (addr, why))


def _guard_value(addr: int, val: int) -> None:
    if addr == QSPI_CMD and (val & QSPI_CMD_ENABLE_BIT):
        raise HazardGuard(
            "refusing QSPI CMD write 0x%08X: bit 8 would start a flash transaction (HZ-6 territory)" % val)
    if not (0 <= val <= 0xFFFFFFFF):
        raise HazardGuard("write datum 0x%X is not a 32-bit value" % val)


def _r(adp: Adp, addr: int, allow_acquire: bool = False, timeout_ms: int = 4000) -> Reply:
    """Guarded word read.  ``A x<addr>`` then ``R`` — 2 CU.

    Always re-issues ``A``: ``R`` auto-increments, so never assume the address
    register still points where you left it.
    """
    _guard(addr, write=False, allow_acquire=allow_acquire)
    return adp.read(addr)


def _w(adp: Adp, addr: int, val: int) -> Reply:
    """Guarded word write.  ``A x<addr>`` then ``W x<val>`` — 2 CU."""
    _guard(addr, write=True)
    _guard_value(addr, val)
    return adp.write(addr, val)


# ---------------------------------------------------------------------------
# HIO-313's boot-gate write path.  Triple-guarded; the only sanctioned write to
# 0x29xxxxxx anywhere in this module.
# ---------------------------------------------------------------------------

BOOTGATE_ADDR = 0x29000000
BOOTGATE_NOOP_DATUM = 0x00000000

#: Positive write-path control for HIO-313.  eth IMEM is real writable RAM and
#: is EMPTY on this die; write/read-back/restore of 0xD00DFEED at 0x10001000 is
#: a MEASURED hardware fact.  Captured and restored, so HIO-313 destroys nothing.
BOOTGATE_WRITE_CONTROL_ADDR = 0x10001000
BOOTGATE_WRITE_CONTROL_TAG = 0xD00DFEED

#: bit 0 = CPU1 remap (address 0 -> IMEM), bit 2 = NETWORK_CORE_BOOTGATE
#: (releases CPU0).  ``remap_q <= remap_q | HWDATA[3:0]`` and the register
#: resets only on PORESETn (``chip_core_remap_ctrl.v:113-118``, verified), so
#: any set bit written here is irreversible within this power cycle.


def _bootgate_noop_write(adp: Adp, addr: int, datum: int) -> Reply:
    """Write ``0x00000000`` to the boot-gate register — a guaranteed no-op.

    ``remap_q <= remap_q | HWDATA[3:0]``, so OR-with-zero cannot set a bit.
    Three independent guards, because this is the most dangerous register on
    the die and Tier 5's irreversible CPU0 release is gated on this test:

      1. the datum must be exactly 0;
      2. the address must be exactly ``BOOTGATE_ADDR``;
      3. the module constant itself must still be 0 (catches an edit that
         changed the constant rather than the call site).

    ``adp.write`` re-issues ``A`` before ``W``, so the write lands on the
    intended address and does not ride the auto-increment from a preceding
    ``R``.
    """
    if datum != 0x00000000:
        raise HazardGuard(
            "HIO-313 refused: boot-gate datum must be exactly 0x00000000, got 0x%08X. "
            "Any set bit here is irreversible without a power cycle (HZ-4)." % datum)
    if addr != BOOTGATE_ADDR:
        raise HazardGuard("HIO-313 refused: boot-gate address must be 0x%08X, got 0x%08X" % (BOOTGATE_ADDR, addr))
    if BOOTGATE_NOOP_DATUM != 0x00000000:
        raise HazardGuard("HIO-313 refused: BOOTGATE_NOOP_DATUM has been edited to 0x%08X" % BOOTGATE_NOOP_DATUM)
    return adp.write(BOOTGATE_ADDR, 0x00000000)


# ---------------------------------------------------------------------------
# Small shared helpers
# ---------------------------------------------------------------------------

def _hexl(vals) -> str:
    return "[" + ", ".join("0x%08X" % v for v in vals) + "]"


def _sample_offsets(size_bytes: int) -> list:
    """Deterministic strided sample set for a RAM of ``size_bytes``.

    Fixed, not random, so two dies are compared at the same cells.  Covers the
    first words, both halves, the quarter boundaries and the last words — the
    places a decoder fault inside the macro shows up.
    """
    cands = [
        0, 4, 8, 0x3C, 0x100,
        size_bytes // 8, size_bytes // 4,
        size_bytes // 2, size_bytes // 2 + 4,
        (3 * size_bytes) // 4,
        size_bytes - 0x100, size_bytes - 8,
    ]
    out = sorted({o & ~3 for o in cands if 0 <= (o & ~3) < size_bytes})
    return out


def _addr_walk_offsets(size_bytes: int) -> list:
    """Offset 0 plus one offset per address bit: 4<<k while 4<<k < size."""
    offs = [0]
    k = 0
    while (4 << k) < size_bytes:
        offs.append(4 << k)
        k += 1
    return offs


def _replies_healthy(rec: Rec, replies, what: str) -> bool:
    """All replies well-formed and none flagged a bus error.

    ``Reply.error`` is the only correct bus-error test (CONTRACT).  A missing
    reply (``ok`` False) is a NO-REPLY — a stall or a desynced link — and is a
    different, worse finding than an ERROR.
    """
    no_reply = [i for i, r in enumerate(replies) if not r.ok]
    errored = [i for i, r in enumerate(replies) if r.ok and r.error]
    ok = not no_reply and not errored
    rec.check("%s: %d accesses, no NO-REPLY and no bus ERROR" % (what, len(replies)), ok,
              got="no_reply=%d errored=%d" % (len(no_reply), len(errored)))
    return ok


# ---------------------------------------------------------------------------
# Memory-integrity primitives
# ---------------------------------------------------------------------------

def _walking_ones_zeros(adp: Adp, rec: Rec, addr: int, tag: str, strict: bool) -> dict:
    """Data-bus integrity at one address: 32 walking ones AND 32 walking zeros.

    Both polarities are mandatory.  Walking ones alone cannot see a stuck-at-1
    bit (the pattern's other 31 bits are already 0 and the stuck bit is only
    ever asked to be 1 once, where it agrees); walking zeros alone cannot see a
    stuck-at-0 bit.  Running one half is the classic half-blind version.

    Cost: 64 patterns x (write 2 CU + read 2 CU) = 256 CU ~= 17 s.
    """
    replies = []
    fails = {"ones": [], "zeros": []}
    stuck_high = 0          # bits that read 1 when 0 was written
    stuck_low = 0           # bits that read 0 when 1 was written

    for polarity in ("ones", "zeros"):
        for k in range(32):
            pat = (1 << k) if polarity == "ones" else ((~(1 << k)) & 0xFFFFFFFF)
            wr = _w(adp, addr, pat)
            rd = _r(adp, addr)
            replies.extend((wr, rd))
            got = rd.value if rd.value is not None else -1
            if got != pat:
                fails[polarity].append((pat, got))
                if got >= 0:
                    stuck_high |= (got & ~pat) & 0xFFFFFFFF
                    stuck_low |= (~got & pat) & 0xFFFFFFFF

    _replies_healthy(rec, replies, "%s walking patterns" % tag)
    rec.record("%s_walk_stuck_high_mask" % tag, "0x%08X" % stuck_high)
    rec.record("%s_walk_stuck_low_mask" % tag, "0x%08X" % stuck_low)

    n_ones_ok = 32 - len(fails["ones"])
    n_zeros_ok = 32 - len(fails["zeros"])

    if strict:
        rec.check("%s: all 32 walking-ONES patterns read back exactly (finds stuck-low / open data bits)" % tag,
                  not fails["ones"],
                  got="%d/32 ok, first failures %s" % (n_ones_ok, fails["ones"][:4]))
        rec.check("%s: all 32 walking-ZEROS patterns read back exactly (finds stuck-high / bridged data bits)" % tag,
                  not fails["zeros"],
                  got="%d/32 ok, first failures %s" % (n_zeros_ok, fails["zeros"][:4]))
    else:
        rec.check("%s: at least one walking-ONES pattern round-tripped "
                  "(a live CPU cannot explain zero of 32)" % tag,
                  n_ones_ok > 0, got="%d/32 ok" % n_ones_ok)
        rec.check("%s: at least one walking-ZEROS pattern round-tripped" % tag,
                  n_zeros_ok > 0, got="%d/32 ok" % n_zeros_ok)
        if fails["ones"] or fails["zeros"]:
            rec.note("%s: INCONCLUSIVE — %d/64 walking patterns mismatched while the owning CPU is live; "
                     "a running CPU legitimately writes this memory. Not reported as a fault. "
                     "Park the CPU and re-run with HOSTIO_CPU1_PARKED=1 for a verdict." %
                     (tag, len(fails["ones"]) + len(fails["zeros"])))

    return {"ones_ok": n_ones_ok, "zeros_ok": n_zeros_ok,
            "stuck_high": stuck_high, "stuck_low": stuck_low}


def _address_uniqueness(adp: Adp, rec: Rec, base: int, size: int, tag: str, strict: bool) -> dict:
    """Address-bus integrity: a DISTINCT value per address, then read all back.

    Each location is given its own absolute address as its datum, so no two
    locations hold the same value.  **A fill-based test cannot do this**: an
    ``F`` writes one constant everywhere, so a RAM whose A12 is stuck passes an
    ``F``+verify perfectly.  Here, if two offsets land on the same cell, the
    later write overwrites the earlier and the readback returns a *different
    address's* value — which also names the aliasing pair for you.

    All writes are issued before any read, which is what makes the aliasing
    visible; a write-verify-write-verify loop would not see it.

    Also probes the alias wrap at ``base + size``: in a correctly sized window
    that address must alias back onto offset 0.  A mismatch means the macro is
    not the declared depth — the HIO-118 class of fault, and the reason the
    generated discovery table's SIZE fields are not authoritative (plan
    HIO-118: it declares eth IMEM 64 KB against a 32 KB macro).

    Cost: (n_offsets writes + n_offsets reads + 1 wrap read) x 2 CU;
    14 offsets for a 32 KB RAM = 58 CU ~= 3.8 s.
    """
    offs = _addr_walk_offsets(size)
    replies = []

    for off in offs:
        a = base + off
        replies.append(_w(adp, a, a))

    got = {}
    for off in offs:
        a = base + off
        r = _r(adp, a)
        replies.append(r)
        got[off] = r.value if r.value is not None else -1

    wrap = _r(adp, base + size)
    replies.append(wrap)

    _replies_healthy(rec, replies, "%s address-uniqueness" % tag)

    bad = [(off, got[off]) for off in offs if got[off] != (base + off)]
    aliases = []
    for off, v in bad:
        for other in offs:
            if v == (base + other):
                aliases.append("off 0x%X reads the value written at off 0x%X (address bit 0x%X suspect)"
                               % (off, other, off ^ other))
                break

    rec.record("%s_addr_unique_offsets" % tag, ["0x%X" % o for o in offs])
    rec.record("%s_addr_unique_mismatches" % tag, ["off 0x%X -> 0x%08X" % (o, v) for o, v in bad])
    if aliases:
        rec.record("%s_addr_alias_pairs" % tag, aliases)

    wrap_val = wrap.value if wrap.value is not None else -1
    wrap_ok = wrap_val == base

    if strict:
        rec.check("%s: every location holds its own address (no address aliasing, no stuck address bit)" % tag,
                  not bad, got="%d/%d ok; %s" % (len(offs) - len(bad), len(offs), aliases[:3] or "no alias pairs"))
        rec.check("%s: window aliases back to offset 0 at the declared physical size 0x%X "
                  "(a mismatch means the macro is not the declared depth — HIO-118 class)" % (tag, size),
                  wrap_ok, got="0x%08X at base+0x%X, expected 0x%08X" % (wrap_val, size, base))
    else:
        rec.check("%s: at least one location still holds its own address" % tag,
                  len(bad) < len(offs), got="%d/%d ok" % (len(offs) - len(bad), len(offs)))
        rec.record("%s_addr_wrap_observed" % tag, "0x%08X (expected 0x%08X)" % (wrap_val, base))
        if bad:
            rec.note("%s: INCONCLUSIVE — %d/%d address-uniqueness locations mismatched while the owning CPU "
                     "is live. Not reported as a fault." % (tag, len(bad), len(offs)))

    return {"mismatches": bad, "aliases": aliases, "wrap_ok": wrap_ok}


def _fill_and_sample(adp: Adp, rec: Rec, base: int, size: int, pattern: int,
                     tag: str, strict: bool) -> dict:
    """Whole-RAM fill via the ``F`` engine, then strided sampled readback.

    ``F`` writes ``V`` to ``<count>`` successive addresses in ONE command, so
    every cell is written (~4700x cheaper than a dump, plan §4.1).  The
    readback is sampled, not exhaustive: a full ``R<n>`` dump of 32 KB costs
    ~18 min and returns thousands of replies that the pinned ``Reply`` API
    cannot represent.  **Write coverage is total; read coverage is the sample.**

    Three guards the naive version misses:

      * ``V`` is read back before the fill.  ``F``'s access size comes from
        ``V``'s hex-digit count, so a ``V`` that did not take, or that was
        written with fewer than 5 digits, silently turns the fill into a BYTE
        fill.  Without this check the whole test measures the wrong thing.
      * The ``F`` reply's ``error`` flag is recorded — but per §1.5 ``F``
        captures ``HRESP`` only in the loop-continue branch, so **a fill whose
        only erroring beat is the last one reports clean**.
      * That hole is closed explicitly: the last word is read, then written
        with a plain ``W`` (whose ``HRESP`` is captured), then read again.

    Cost: 5 CU setup + 1 CU fill + samples x 2 CU + 6 CU last-word proof;
    ~35 CU ~= 2.3 s for any of the five RAMs.
    """
    nwords = size // 4
    last = base + size - 4

    adp.cmd("A x%08X" % base)
    adp.cmd("V x%08X" % pattern)
    vrep = adp.cmd("V")
    vback = (vrep.value & 0xFFFFFFFF) if vrep.value is not None else -1
    rec.check("%s: V operand register holds 0x%08X before the fill "
              "(guards the digit-count size trap — <5 digits makes F a BYTE fill)" % (tag, pattern),
              vback == pattern, got="V reports 0x%08X (%s)" % (vback, vrep.raw))

    adp.cmd("A x%08X" % base)
    frep = adp.cmd("F x%08X" % nwords, timeout_ms=8000)
    rec.record("%s_fill_reply" % tag, frep.raw)
    rec.check("%s: F x%08X (%d words, %d KB) returned a well-formed reply" % (tag, nwords, nwords, size // 1024),
              frep.ok, got=frep.raw)
    if frep.ok and frep.error:
        rec.note("%s: the F reply carried '!' — a bus ERROR on some non-final beat of the fill." % tag)

    offs = _sample_offsets(size)
    replies = [vrep, frep]
    bad = []
    for off in offs:
        r = _r(adp, base + off)
        replies.append(r)
        v = r.value if r.value is not None else -1
        if v != pattern:
            bad.append((off, v))

    # Last-word proof — closes the F off-by-one hole in §1.5.  Note the plan's
    # own follow-up (A x10007ffc ; R ; W x5a5a5a5a) writes at base+size, which
    # aliases onto offset 0 and proves the FIRST word.
    lrd0 = _r(adp, last)
    lwr = _w(adp, last, pattern)
    lrd1 = _r(adp, last)
    replies.extend((lrd0, lwr, lrd1))
    last_filled = (lrd0.value == pattern)
    last_wr_clean = lwr.ok and not lwr.error
    last_rb = (lrd1.value == pattern)

    _replies_healthy(rec, replies, "%s fill/verify" % tag)
    rec.record("%s_fill_pattern" % tag, "0x%08X" % pattern)
    rec.record("%s_fill_sample_offsets" % tag, ["0x%X" % o for o in offs])
    rec.record("%s_fill_mismatches" % tag, ["off 0x%X -> 0x%08X" % (o, v) for o, v in bad])

    if strict:
        rec.check("%s: all %d sampled cells hold 0x%08X after the whole-RAM fill" % (tag, len(offs), pattern),
                  not bad, got="%d/%d ok; %s" % (len(offs) - len(bad), len(offs),
                                                 ["off 0x%X -> 0x%08X" % (o, v) for o, v in bad[:4]]))
        rec.check("%s: the LAST word (0x%08X) was filled — the beat whose HRESP F does not capture" % (tag, last),
                  last_filled, got="0x%08X" % (lrd0.value if lrd0.value is not None else -1))
        rec.check("%s: an explicit W at the last word reports OK (closes the F/U off-by-one hole, §1.5)" % tag,
                  last_wr_clean, got=lwr.raw)
        rec.check("%s: the last word reads back 0x%08X after that explicit write" % (tag, pattern),
                  last_rb, got="0x%08X" % (lrd1.value if lrd1.value is not None else -1))
    else:
        rec.check("%s: at least one sampled cell holds the fill pattern "
                  "(a live CPU cannot rewrite a whole RAM inside one link round trip; "
                  "zero of %d would mean an absent or fully-aliased macro)" % (tag, len(offs)),
                  len(bad) < len(offs), got="%d/%d ok" % (len(offs) - len(bad), len(offs)))
        rec.check("%s: an explicit W at the last word reports OK (F/U off-by-one hole, §1.5)" % tag,
                  last_wr_clean, got=lwr.raw)
        if bad or not last_filled:
            rec.note("%s: INCONCLUSIVE — %d/%d sampled cells did not hold 0x%08X while the owning CPU is live. "
                     "Not reported as a fault." % (tag, len(bad), len(offs), pattern))

    return {"mismatches": bad, "last_filled": last_filled, "sample_offsets": offs}


def _ram_battery(adp: Adp, rec: Rec, base: int, size: int, tag: str, strict: bool) -> None:
    """The HIO-201/202/203/204 pattern applied to one RAM (plan's HIO-205 shape).

    Order matters: per-cell tests first (they need a quiet RAM to interpret),
    then the two complementary bulk fills.  Cost ~= 380 CU ~= 25 s for a 16 KB
    RAM; the walking-pattern half dominates and does not scale with depth.
    """
    _walking_ones_zeros(adp, rec, base, tag, strict)
    _address_uniqueness(adp, rec, base, size, tag, strict)
    _fill_and_sample(adp, rec, base, size, PAT_A, tag + "_5a", strict)
    _fill_and_sample(adp, rec, base, size, PAT_B, tag + "_a5", strict)


# ===========================================================================
# TIER 2 — memory integrity  (HIO-201 .. HIO-211)
# ===========================================================================

@test("HIO-201", tier=2, hazard=HZ.DESTRUCTIVE,
      destroys="eth IMEM word at 0x10000000 (left holding 0x7FFFFFFF)",
      purpose="Eth IMEM data-bus integrity: 32 walking-ones AND 32 walking-zeros at 0x10000000. "
              "RED when a written pattern does not read back. Both polarities are required and are "
              "asserted separately: walking-ones alone cannot see a stuck-at-1 bit, walking-zeros alone "
              "cannot see a stuck-at-0 bit, and a bridged Dn/Dm pair fails only the ones half. "
              "Also RED on any NO-REPLY or bus ERROR across the 128 accesses. "
              "Records stuck-high/stuck-low bit masks so a failure names the data bit. "
              "Budget: 256 CU ~= 17 s.")
def hio_201(adp, rec):
    _walking_ones_zeros(adp, rec, ETH_IMEM_BASE, "eth_imem", strict=True)


@test("HIO-202", tier=2, hazard=HZ.DESTRUCTIVE,
      destroys="eth IMEM words at offsets 0x0, 0x4, 0x8 ... 0x4000 (14 locations)",
      purpose="Eth IMEM address-bus integrity / aliasing: writes each location's own ADDRESS into it "
              "(a distinct value per location), then reads them all back. RED when any location returns a "
              "different location's value, which is what a stuck or shorted address line produces, and the "
              "returned value names the aliasing partner. "
              "THIS CANNOT BE REPLACED BY A FILL-BASED TEST: F writes one constant everywhere, so an "
              "aliased RAM passes F+verify perfectly — which is why this test sits next to HIO-210 and why "
              "HIO-118's size probes matter. All writes precede all reads; a write-verify loop would not see it. "
              "Also RED when base+0x8000 does not alias back to offset 0 (macro not the declared 32 KB depth). "
              "Budget: 58 CU ~= 3.8 s.")
def hio_202(adp, rec):
    _address_uniqueness(adp, rec, ETH_IMEM_BASE, ETH_IMEM_SIZE, "eth_imem", strict=True)


@test("HIO-203", tier=2, hazard=HZ.DESTRUCTIVE,
      destroys="ALL 32 KB of eth IMEM (0x10000000-0x10007FFF), overwritten with 0x5A5A5A5A",
      purpose="Eth IMEM whole-RAM fill 0x5A5A5A5A via the F engine, then strided sampled readback. "
              "Every cell is WRITTEN (one F command, ~4700x cheaper than a dump); 12 fixed sample cells are "
              "READ — a full R<n> dump is ~18 min and returns thousands of replies the pinned Reply API "
              "cannot represent, so this test does not claim full-RAM read coverage. "
              "RED when a sampled cell does not hold the pattern, when V does not read back before the fill "
              "(guards the digit-count trap that silently turns F into a BYTE fill), or when the explicit "
              "last-word W reports '!'. That last step exists because per §1.5 F captures HRESP only in the "
              "loop-continue branch, so a fill whose ONLY erroring beat is the last one reports clean. "
              "Budget: 35 CU ~= 2.3 s.")
def hio_203(adp, rec):
    _fill_and_sample(adp, rec, ETH_IMEM_BASE, ETH_IMEM_SIZE, PAT_A, "eth_imem_5a", strict=True)


@test("HIO-204", tier=2, hazard=HZ.DESTRUCTIVE,
      destroys="ALL 32 KB of eth IMEM (0x10000000-0x10007FFF), overwritten with 0xA5A5A5A5",
      purpose="Eth IMEM whole-RAM fill 0xA5A5A5A5 — the complement of HIO-203. RED for the same reasons. "
              "The pair is what makes either sound: a cell stuck at 0x5A5A5A5A's bit values passes HIO-203 "
              "and fails here. Running one polarity only is the 'measured nothing' failure mode. "
              "Budget: 35 CU ~= 2.3 s.")
def hio_204(adp, rec):
    _fill_and_sample(adp, rec, ETH_IMEM_BASE, ETH_IMEM_SIZE, PAT_B, "eth_imem_a5", strict=True)


@test("HIO-205", tier=2, hazard=HZ.DESTRUCTIVE,
      destroys="ALL 16 KB of eth DMEM (0x18000000-0x18003FFF) — INCLUDING WORD 0, the SystemCoreClock "
               "value (0x05F5E100) that HIO-107 uses to prove CPU0 ran its stage-0 scatter-load. "
               "Capture HIO-107 before this test (plan §3, Phase D preamble).",
      purpose="Eth DMEM full battery: walking ones/zeros, address uniqueness, and both bulk fills "
              "(F x00001000). RED on the same conditions as HIO-201/202/203/204, applied to the 16 KB "
              "DMEM macro; the address-uniqueness half additionally goes RED if the window does not alias "
              "at 16 KB. Budget: ~380 CU ~= 25 s.")
def hio_205(adp, rec):
    rec.note("eth DMEM word 0 held the HIO-107 boot-state evidence; it is destroyed by this test.")
    _ram_battery(adp, rec, ETH_DMEM_BASE, ETH_DMEM_SIZE, "eth_dmem", strict=True)


@test("HIO-206", tier=2, hazard=HZ.DESTRUCTIVE, weak=not CPU1_PARKED,
      destroys="ALL 16 KB of CPU1 IMEM (0x90000000-0x90003FFF). CPU1 IS EXECUTING and cannot be held in "
               "reset (cpu1_bootgate tied 1'b1). If CPU1's REMAP bit is set, this destroys the code it is "
               "running.",
      purpose="CPU1 IMEM full battery through the remap-independent 0x9x alias, so it works whatever CPU1's "
              "REMAP bit says. CPU1 CANNOT BE HELD IN RESET, so by default a mismatch is reported as "
              "INCONCLUSIVE (rec.note + a recorded count), NOT as a fault — a running CPU legitimately "
              "writes its own memory, and a red here would be unfalsifiable. What still goes RED, and cannot "
              "be explained by a live CPU: any NO-REPLY or bus ERROR inside the declared window, and ZERO of "
              "32/12 locations retaining what was written (an absent or fully-aliased macro). "
              "Declared weak=True in this mode because the per-cell assertion has been withdrawn. "
              "Set HOSTIO_CPU1_PARKED=1 after parking CPU1 (docstring, option b) to restore strict "
              "assertions and clear weak. Budget: ~380 CU ~= 25 s.")
def hio_206(adp, rec):
    rec.record("hio206_mode", "STRICT (CPU1 parked)" if CPU1_PARKED else "INCONCLUSIVE-BY-DEFAULT (CPU1 live)")
    if not CPU1_PARKED:
        rec.note("CPU1 is running out of this address space and cannot be held in reset "
                 "(cpu1_bootgate tied 1'b1, nanosoc_multicore_soc.sv:1387). Mismatches below are recorded "
                 "as INCONCLUSIVE, not as faults. Park CPU1 and re-run with HOSTIO_CPU1_PARKED=1 for a verdict.")
    _ram_battery(adp, rec, CPU1_IMEM_BASE, CPU1_IMEM_SIZE, "cpu1_imem", strict=CPU1_PARKED)


@test("HIO-207", tier=2, hazard=HZ.DESTRUCTIVE, weak=not CPU1_PARKED,
      destroys="ALL 8 KB of CPU1 DMEM (0x98000000-0x98001FFF) — INCLUDING CPU1'S LIVE STACK. CPU1 will "
               "fault on its next return. CPU1's PRMU is the source of the whole SoC's HCLK/HRESETn, so a "
               "runaway CPU1 can take the fabric clock, the ADP and HOSTIO down with it: budget a power cycle "
               "and run this test LAST.",
      purpose="CPU1 DMEM full battery. Same inconclusive-by-default contract as HIO-206 and for the same "
              "reason — CPU1's stack lives here, so a mismatch is recorded, not failed. RED only on a "
              "NO-REPLY / bus ERROR inside the window, or on ZERO locations retaining what was written. "
              "Declared weak=True unless HOSTIO_CPU1_PARKED=1. "
              "HIGHEST-RISK TEST IN TIER 2: destroying a live stack can cost the session. "
              "Budget: ~376 CU ~= 24 s plus a possible power cycle.")
def hio_207(adp, rec):
    rec.record("hio207_mode", "STRICT (CPU1 parked)" if CPU1_PARKED else "INCONCLUSIVE-BY-DEFAULT (CPU1 live)")
    if not CPU1_PARKED:
        rec.note("CPU1's live stack is in this RAM. Mismatches are INCONCLUSIVE, not faults. After this test "
                 "CPU1 has almost certainly faulted; if HOSTIO stops answering, the fabric clock went with it "
                 "(CPU1's PRMU sources HCLK/HRESETn, HZ-5) and a power cycle is required.")
    _ram_battery(adp, rec, CPU1_DMEM_BASE, CPU1_DMEM_SIZE, "cpu1_dmem", strict=CPU1_PARKED)


@test("HIO-208", tier=2, hazard=HZ.DESTRUCTIVE,
      destroys="ALL 8 KB of shared cross-core SRAM (0x2D000000-0x2D001FFF) — INCLUDING THE BOOT-CONFIRM "
               "TOKEN read by HIO-414. Read HIO-414 first (plan §3, Phase C5).",
      purpose="Shared cross-core SRAM full battery. This is the only RAM reachable by both CPUs and the ADP, "
              "so it is the medium for every later handshake test (HIO-410, HIO-504) and its integrity must "
              "be established before them. RED on the same conditions as HIO-205. "
              "Budget: ~376 CU ~= 24 s.")
def hio_208(adp, rec):
    rec.note("Shared SRAM carries the boot-confirm token (HIO-414) and is the medium for HIO-410/HIO-504; "
             "this test destroys its contents.")
    _ram_battery(adp, rec, SHARED_SRAM_BASE, SHARED_SRAM_SIZE, "shared_sram", strict=True)


@test("HIO-209", tier=2, hazard=HZ.DESTRUCTIVE,
      destroys="nothing, IF the boot ROMs are ROM — that is the assertion under test. If a 'ROM' turns out "
               "to be writable this test will have written 0xDEADBEEF into one word of it (until the next "
               "power cycle), and reports RED. Also destroys eth IMEM word at 0x10000040, used as the "
               "write-path positive control.",
      purpose="ROM write-protection — A NEGATIVE TEST with inverted discrimination: it goes RED when the "
              "write SUCCEEDS. Reads the word, attempts W 0xDEADBEEF AT THE SAME ADDRESS (the plan's literal "
              "sequence lets R's auto-increment move the write to word 1, which makes the test pass "
              "unconditionally — see the module docstring), re-reads and compares against the value captured "
              "before the attempt. Repeated for the eth ROM at 0x08000000 and CPU1's ROM at 0x80000000. "
              "TWO CONTROLS make 'unchanged' mean something rather than being vacuous. (1) A POSITIVE "
              "WRITE-PATH CONTROL immediately before: a tag is written to eth IMEM and read back, so a dead "
              "ADP write path — which would make any ROM look protected — is itself RED. This is what "
              "distinguishes a silently-ignored write from a genuinely protected ROM. (2) A DISTINCT-DATA "
              "control: ROM offset 0xE4 must differ from offset 0x00, so a bus returning one constant "
              "everywhere cannot pass by making 'unchanged' trivially true. The W reply's error flag is "
              "RECORDED, not asserted: a ROM may answer OKAY or ERROR and both are correct. "
              "Budget: ~24 CU ~= 1.6 s.")
def hio_209(adp, rec):
    # (1) contemporaneous positive control: the ADP write path is alive right now.
    ctrl_addr = ETH_IMEM_BASE + 0x40
    cw = _w(adp, ctrl_addr, WRITE_PATH_TAG)
    cr = _r(adp, ctrl_addr)
    rec.record("hio209_write_path_control", "0x%08X -> %s" % (ctrl_addr, cr.raw))
    rec.check("POSITIVE CONTROL: the ADP write path is alive (0x%08X takes 0x%08X) — without this, a "
              "protected-looking ROM is indistinguishable from a dead write path"
              % (ctrl_addr, WRITE_PATH_TAG),
              cw.ok and not cw.error and cr.value == WRITE_PATH_TAG,
              got="W=%s R=%s" % (cw.raw, cr.raw))

    for name, rom in (("eth_rom", ETH_ROM_BASE), ("cpu1_rom", CPU1_ROM_BASE)):
        before = _r(adp, rom)
        other = _r(adp, rom + ROM_DIFF_OFFSET)
        wr = _w(adp, rom, ROM_POISON)
        after = _r(adp, rom)

        rec.record("%s_word0_before" % name, "0x%08X" % (before.value if before.value is not None else -1))
        rec.record("%s_word0_after" % name, "0x%08X" % (after.value if after.value is not None else -1))
        rec.record("%s_write_reply" % name, wr.raw)
        rec.record("%s_write_flagged_error" % name, bool(wr.error))

        rec.check("%s: reads are well-formed and unflagged before and after the write attempt" % name,
                  before.ok and not before.error and after.ok and not after.error,
                  got="before=%s after=%s" % (before.raw, after.raw))
        rec.check("DISTINCT-DATA CONTROL %s: offset 0xE4 differs from offset 0x00, so the ROM read path "
                  "returns real data and 'unchanged' is not trivially true" % name,
                  other.ok and other.value is not None and before.value is not None
                  and other.value != before.value,
                  got="0x00=0x%08X 0xE4=0x%08X" % (before.value or 0, other.value or 0))
        rec.check("%s: the ROM word at 0x%08X is UNCHANGED after W 0x%08X — RED IF THE WRITE SUCCEEDED "
                  "(a writable boot ROM is RAM: the wrong macro was instantiated)"
                  % (name, rom, ROM_POISON),
                  before.value is not None and after.value == before.value,
                  got="before=0x%08X after=0x%08X" % (before.value or 0, after.value or 0))


@test("HIO-210", tier=2, hazard=HZ.DESTRUCTIVE,
      destroys="eth IMEM word at 0x10000000 (left holding 0xFFFFFFFF)",
      purpose="Byte-lane integrity. Zeroes 0x10000000 with a word write, then does four BYTE writes (WFF, "
              "two hex digits — the only deliberate short parameter in the plan, §1.2) at byte addresses "
              "0x10000000..0x10000003, reading the whole word after each. RED when the word does not step "
              "0x000000FF, 0x0000FFFF, 0x00FFFFFF, 0xFFFFFFFF. A broken byte-enable writes all four lanes at "
              "once and gives 0xFFFFFFFF on the FIRST step, so the discrimination is in the intermediate "
              "values, not the final one. Exercises the HWDATA byte replication "
              "(socdebug_adp_control.v:338-340) and the RAM's byte-enable decode. "
              "Budget: 18 CU ~= 1.2 s.")
def hio_210(adp, rec):
    z = _w(adp, ETH_IMEM_BASE, 0x00000000)
    rec.check("byte-lane: the word starts at 0x00000000", z.ok and not z.error, got=z.raw)

    expect = [0x000000FF, 0x0000FFFF, 0x00FFFFFF, 0xFFFFFFFF]
    seen = []
    replies = [z]
    for lane in range(4):
        a = adp.cmd("A x%08X" % (ETH_IMEM_BASE + lane))
        w = adp.cmd("WFF")          # 2 hex digits => 8-bit access (FNparam2size, §1.2)
        r = _r(adp, ETH_IMEM_BASE)
        replies.extend((a, w, r))
        seen.append(r.value if r.value is not None else -1)

    _replies_healthy(rec, replies, "byte-lane")
    rec.record("hio210_byte_lane_steps", ["0x%08X" % v for v in seen])
    for lane in range(4):
        rec.check("byte-lane %d: word reads 0x%08X after the byte write at 0x%08X"
                  % (lane, expect[lane], ETH_IMEM_BASE + lane),
                  seen[lane] == expect[lane], got="0x%08X" % seen[lane])
    if seen and seen[0] == 0xFFFFFFFF:
        rec.note("Lane 0's byte write set ALL FOUR lanes: the byte-enable decode is broken, or HSIZE did not "
                 "reach 8-bit (check that the parameter really was two hex digits).")


@test("HIO-211", tier=2, hazard=None, needs=["HIO-203"],
      purpose="Retention / short soak, and — more usefully in practice — a probe for anything else mutating "
              "memory behind your back. Snapshots 12 strided eth IMEM words, leaves the port idle for "
              "HOSTIO_SOAK_SECONDS (default 60), then re-reads the same words. RED when any word changed, "
              "which means either a retention failure or another agent (a released CPU0, the DMA, a cross-die "
              "write) writing this RAM during a window that was supposed to be quiescent — a finding in its "
              "own right. Does NOT assume a particular fill pattern: it compares against its own snapshot, "
              "so it is valid whichever of HIO-203/204/210 ran last. Records whether the baseline was "
              "distinctive; an all-zero baseline weakens the test, because a read path stuck at zero also "
              "'does not change'. Non-destructive: reads only. "
              "Budget: 48 CU ~= 3.2 s plus the soak, ~63 s total.")
def hio_211(adp, rec):
    offs = _sample_offsets(ETH_IMEM_SIZE)
    before, replies = [], []
    for off in offs:
        r = _r(adp, ETH_IMEM_BASE + off)
        replies.append(r)
        before.append(r.value if r.value is not None else -1)

    distinct = len(set(before))
    all_zero = all(v == 0 for v in before)
    rec.record("hio211_soak_seconds", SOAK_SECONDS)
    rec.record("hio211_baseline", ["0x%08X" % v for v in before])
    if all_zero:
        rec.note("Soak baseline is all zeros. The comparison is still valid but WEAKENED: a read path stuck "
                 "at zero would also show 'no change'. Run this after HIO-203/204 so the baseline carries a "
                 "distinctive fill pattern.")
    rec.record("hio211_baseline_distinct_values", distinct)

    time.sleep(SOAK_SECONDS)

    after = []
    for off in offs:
        r = _r(adp, ETH_IMEM_BASE + off)
        replies.append(r)
        after.append(r.value if r.value is not None else -1)

    _replies_healthy(rec, replies, "soak")
    changed = [(offs[i], before[i], after[i]) for i in range(len(offs)) if before[i] != after[i]]
    rec.record("hio211_changed", ["off 0x%X: 0x%08X -> 0x%08X" % c for c in changed])
    rec.check("eth IMEM is unchanged across a %d s idle window (RED = retention failure, or another agent "
              "is writing this RAM while the bus was supposed to be quiescent)" % SOAK_SECONDS,
              not changed, got="%d/%d words changed: %s" % (len(changed), len(offs),
                                                            ["off 0x%X: 0x%08X -> 0x%08X" % c
                                                             for c in changed[:4]]))


# ===========================================================================
# TIER 3 — subsystem register behaviour  (HIO-301 .. HIO-314)
# ===========================================================================

RESET_CTRL_SYS_CTRL = 0x2A000008        # bit 0 LOCKUPRESETEN (nanosoc_reset_ctrl.v:19-20)
RESET_INFO_CPU0 = 0x2A000010            # W1C, 4 bits (nanosoc_reset_ctrl.v:21-23, 316-320)
TC_ERROR = 0x2E04002C                   # TideChart W1C: [0] election_timeout [1] enum_timeout [2] dual_root
SPINLOCK_OWNER = 0x2C100300             # DIAG page, RO, 2 bits per lock, lock 0 in [1:0]
SPINLOCK_FORCE_RELEASE = 0x2C100304     # DIAG page, WO, write bit n frees lock n
SPINLOCK_DBG_PAGE = 0x2C100200          # HZ-7: a READ here acquires; a WRITE releases what DBG owns
SPINLOCK_OWN_DBG = 0b11                 # OWN_DBG (hw_spinlock.v:90-93, verified)
IPC_SLOT0_W0 = 0x23000000
IPC_IRQ_STATUS = 0x23000028
IPC_LOCK = 0x23000030
IPC_PERIPH_ID = 0x23000034
IPC_OUT_OF_RANGE = 0x23000038           # first word index above the aperture -> PSLVERR
ETC_CTRL = 0x2C000004                   # RW: [0] GLOBAL_EN [1] IRQ_EN (etc_capture.yaml, verified)
PERF_CTRL = 0x2C200008                  # WO: [0] SNAP [1] CLR (perf_probe.yaml, verified)
PERF_CLR = 0x00000002
PERF_P0_CYC = 0x2C200040                # RO, "cycles since clear (time base, SATURATING)"
BFM_STAT = 0x2C300000                   # [0] FAULT_SEEN (W1C) [5:4] INIT_IDX [8] OVERFLOW
BFM_ADDR = 0x2C300004
BFM_COUNT = 0x2C30000C
BFM_ID = 0x2C300010                     # 0x42464D31 "BFM1"
PHC_NS_INCR = 0x22000008
PHC_INT_EN = 0x2200001C
PHC_CAP_NANOSECONDS = 0x22000028        # RO (phc_regs.rdl:196-200)
TIMER0_CTRL = 0x28000000
TIMER0_VALUE = 0x28000004               # CURRENT VALUE, RW (cmsdk_apb_timer.v:34)
TIMER0_RELOAD = 0x28000008              # RELOAD VALUE, RW (cmsdk_apb_timer.v:35)
TIMER_SETUP_VALUE = 0x00010000
TIDELINK_SWEEP_BASE = 0x2E032000
TIDELINK_SWEEP_LAST = 0x2E0321FC


@test("HIO-301", tier=3, hazard=None,
      purpose="reset_ctrl.SYS_CTRL bit 0 (LOCKUPRESETEN) RW readback — the first RW register proven writable "
              "through ADP on a PERIPHERAL rather than a RAM. RED when the write does not read back, or when "
              "the restore to 0 does not take. If this fails while Tier-1 reads pass, the ADP write path or "
              "HWDATA routing is broken while reads work — a failure mode a read-only suite cannot see at all. "
              "The register is RESTORED TO 0 in a finally block and the restore is ASSERTED: leaving "
              "LOCKUPRESETEN set makes a later CPU lockup silently reset that CPU and corrupt every "
              "subsequent test. (The plan's literal sequence never restores it — its restoring write lands on "
              "0x2A00000C because R auto-increments.) Budget: 10 CU ~= 0.7 s.")
def hio_301(adp, rec):
    orig = _r(adp, RESET_CTRL_SYS_CTRL)
    rec.record("sys_ctrl_before", "0x%08X" % (orig.value if orig.value is not None else -1))
    try:
        w1 = _w(adp, RESET_CTRL_SYS_CTRL, 0x00000001)
        r1 = _r(adp, RESET_CTRL_SYS_CTRL)
        rec.check("SYS_CTRL accepts a write of 0x00000001 and reads it back",
                  w1.ok and not w1.error and r1.value == 0x00000001,
                  got="W=%s R=%s" % (w1.raw, r1.raw))
    finally:
        w0 = _w(adp, RESET_CTRL_SYS_CTRL, 0x00000000)
        r0 = _r(adp, RESET_CTRL_SYS_CTRL)
        rec.record("sys_ctrl_restored", "0x%08X" % (r0.value if r0.value is not None else -1))
        rec.check("SYS_CTRL is RESTORED to 0x00000000 (LOCKUPRESETEN must not be left set)",
                  w0.ok and not w0.error and r0.value == 0x00000000,
                  got="W=%s R=%s" % (w0.raw, r0.raw))


@test("HIO-302", tier=3, hazard=HZ.DESTRUCTIVE,
      destroys="reset_ctrl.RESET_INFO_CPU0 — the last-reset-cause record for CPU0. It is cleared and cannot "
               "be recovered until the next reset. Capture it with HIO-105 first.",
      purpose="reset_ctrl.RESET_INFO_CPU0 W1C semantics. Reads v, writes 0 (v must be UNCHANGED), then "
              "writes v (v must become 0). THE WRITE-0 STEP IS THE WHOLE TEST: a register wired as plain RW "
              "would be cleared by the write-0 and would pass a naive 'write then read 0' check, so testing "
              "W1C without the write-0 negative control measures nothing. RED when write-0 changes the value, "
              "or when write-v fails to clear it. SKIPs rather than passing vacuously when the register "
              "already reads 0 — with no set bits there is nothing a W1C could clear and the test would "
              "measure nothing. (The plan's literal sequence clears RESET_INFO_CPU1 at 0x2A000014 instead, "
              "because R auto-increments.) Budget: 10 CU ~= 0.7 s.")
def hio_302(adp, rec):
    r0 = _r(adp, RESET_INFO_CPU0)
    v = r0.value if r0.value is not None else -1
    rec.record("reset_info_cpu0", "0x%08X" % v)
    rec.check("RESET_INFO_CPU0 read is well-formed and unflagged", r0.ok and not r0.error, got=r0.raw)
    if v <= 0:
        rec.skip("RESET_INFO_CPU0 reads 0x%08X — no set bits, so W1C semantics cannot be exercised and a "
                 "PASS here would measure nothing. HIO-105 expects a NON-ZERO cause on a cold die "
                 "(EXTRESET bit 3); if it really is zero that is itself a Tier-1 finding." % v)

    w0 = _w(adp, RESET_INFO_CPU0, 0x00000000)
    r1 = _r(adp, RESET_INFO_CPU0)
    rec.check("NEGATIVE CONTROL: writing 0x00000000 leaves RESET_INFO_CPU0 unchanged at 0x%08X "
              "(a plain-RW register would have been cleared here)" % v,
              w0.ok and not w0.error and r1.value == v, got="W=%s R=%s" % (w0.raw, r1.raw))

    w1 = _w(adp, RESET_INFO_CPU0, v)
    r2 = _r(adp, RESET_INFO_CPU0)
    rec.check("writing 0x%08X back clears RESET_INFO_CPU0 to 0x00000000 (write-1-to-clear)" % v,
              w1.ok and not w1.error and r2.value == 0x00000000, got="W=%s R=%s" % (w1.raw, r2.raw))


@test("HIO-303", tier=3, hazard=HZ.DESTRUCTIVE,
      destroys="TideChart TC_ERROR sticky flags, INCLUDING [2] dual_root — the sticky evidence of the known "
               "TideChart dual-root behaviour. Its pre-clear value is recorded first; it cannot be recovered.",
      purpose="TideChart TC_ERROR W1C — the same shape as HIO-302 on a SECOND, INDEPENDENT W1C "
              "implementation, with the same write-0 negative control. RED when write-0 changes the value or "
              "when write-1 fails to clear. Bits: [0] election_timeout, [1] enum_timeout, [2] dual_root. "
              "READING [2] NON-ZERO BEFORE CLEARING IT IS A REAL RESULT, NOT A TEST ARTEFACT — it is recorded "
              "explicitly. SKIPs rather than passing vacuously when TC_ERROR already reads 0 (nothing to "
              "clear); the recorded value survives the skip and 'no errors latched' is the good outcome. "
              "(The plan's literal sequence writes 0x00000007 to 0x2E040030, the PUF seed word, because R "
              "auto-increments.) Budget: 10 CU ~= 0.7 s.")
def hio_303(adp, rec):
    r0 = _r(adp, TC_ERROR)
    v = r0.value if r0.value is not None else -1
    rec.record("tc_error_before", "0x%08X" % v)
    rec.record("tc_error_dual_root", bool(v > 0 and (v & 0x4)))
    rec.record("tc_error_election_timeout", bool(v > 0 and (v & 0x1)))
    rec.record("tc_error_enum_timeout", bool(v > 0 and (v & 0x2)))
    rec.check("TC_ERROR read is well-formed and unflagged", r0.ok and not r0.error, got=r0.raw)
    if v > 0 and (v & 0x4):
        rec.note("TC_ERROR[2] dual_root IS SET before this test cleared it — the known TideChart dual-root "
                 "behaviour is present on this die. That is a finding, not a test artefact.")
    if v <= 0:
        rec.skip("TC_ERROR reads 0x00000000 — no sticky error latched, so W1C semantics cannot be exercised. "
                 "Recorded as a clean result (no dual_root, no timeouts) rather than a vacuous PASS.")

    w0 = _w(adp, TC_ERROR, 0x00000000)
    r1 = _r(adp, TC_ERROR)
    rec.check("NEGATIVE CONTROL: writing 0x00000000 leaves TC_ERROR unchanged at 0x%08X" % v,
              w0.ok and not w0.error and r1.value == v, got="W=%s R=%s" % (w0.raw, r1.raw))

    w1 = _w(adp, TC_ERROR, 0x00000007)
    r2 = _r(adp, TC_ERROR)
    rec.check("writing 0x00000007 clears TC_ERROR[2:0]",
              w1.ok and not w1.error and r2.value is not None and (r2.value & 0x7) == 0,
              got="W=%s R=%s" % (w1.raw, r2.raw))


@test("HIO-304", tier=3, hazard=None,
      purpose="Spinlock acquire / owner / force-release — the strongest side-effect test on the die, and "
              "fully reversible. Reads OWNER on the DIAG page (must be 0x00000000, all 16 locks free), reads "
              "the DBG ACQUIRE page (HZ-7: this read IS the acquire; must return 1 = granted), re-reads OWNER "
              "(must be 0x00000003 = OWN_DBG in bits [1:0]), force-releases, re-reads OWNER (must be 0). "
              "RED on any of the four. 0b11 IN THE OWNER FIELD IS A VALUE NOTHING ELSE ON THE DIE CAN "
              "PRODUCE: it appears only if an access arrived with HADDR[9:8]==2, so one observation proves "
              "the ADP read reached the block AND that the requester-page decode works. A stuck bus, a "
              "mirrored read, or a decode that ignores HADDR[9:8] all fail. "
              "SAFETY BEYOND THE PLAN: force-release frees a lock regardless of owner, so it is issued ONLY "
              "if this test actually acquired the lock; if a CPU already holds lock 0 the test reports that "
              "and never steals it. A finally block releases via the DBG page (which frees only what DBG "
              "owns) if anything went wrong mid-test. Budget: 10 CU ~= 0.7 s.")
def hio_304(adp, rec):
    acquired = False
    try:
        o0 = _r(adp, SPINLOCK_OWNER)
        rec.record("spinlock_owner_before", "0x%08X" % (o0.value if o0.value is not None else -1))
        rec.check("OWNER reads 0x00000000 before the test (all 16 locks free)",
                  o0.ok and not o0.error and o0.value == 0x00000000, got=o0.raw)
        if o0.value != 0x00000000:
            rec.note("A lock is already held (OWNER = %s). NOT force-releasing: that would steal a running "
                     "CPU's mutual exclusion. The acquire/release half of this test is not exercised."
                     % o0.raw)
            return

        acq = _r(adp, SPINLOCK_DBG_PAGE, allow_acquire=True)   # HZ-7: this read acquires lock 0
        rec.record("spinlock_dbg_acquire", acq.raw)
        rec.check("a read of the DBG acquire page returns 1 (lock 0 granted)",
                  acq.ok and not acq.error and acq.value == 0x00000001, got=acq.raw)
        acquired = bool(acq.ok and not acq.error and acq.value == 0x00000001)

        o1 = _r(adp, SPINLOCK_OWNER)
        rec.record("spinlock_owner_after_acquire", "0x%08X" % (o1.value if o1.value is not None else -1))
        rec.check("OWNER now reads 0x00000003 — OWN_DBG in lock 0's field [1:0]. Nothing else on this die "
                  "can produce 0b11: it requires an access with HADDR[9:8]==2, so this proves both that the "
                  "ADP read reached the block and that the requester-page decode works",
                  o1.ok and not o1.error and o1.value == 0x00000003, got=o1.raw)

        if acquired:
            fr = _w(adp, SPINLOCK_FORCE_RELEASE, 0x00000001)
            o2 = _r(adp, SPINLOCK_OWNER)
            acquired = not (o2.ok and o2.value == 0x00000000)
            rec.record("spinlock_owner_after_release", "0x%08X" % (o2.value if o2.value is not None else -1))
            rec.check("FORCE_RELEASE returns OWNER to 0x00000000",
                      fr.ok and not fr.error and o2.value == 0x00000000, got="W=%s R=%s" % (fr.raw, o2.raw))
    finally:
        if acquired:
            # Polite release: a write to the DBG page frees the lock only if DBG owns it.
            _w(adp, SPINLOCK_DBG_PAGE, 0x00000001)
            rec.note("Released lock 0 via the DBG release page in the cleanup path.")


@test("HIO-305", tier=3, hazard=HZ.DESTRUCTIVE,
      destroys="IPC mailbox slot-0 data word 0 and the LOCK register. Both are captured first and RESTORED, "
               "but they are transiently corrupt while the test runs and CPU1 firmware uses them — a live "
               "reader could observe 0x5A5A5A5A in slot 0.",
      purpose="IPC mailbox R/W + aperture edge. Slot-0 data word 0 must read back 0x5A5A5A5A; LOCK must read "
              "back 0x00000001; IRQ_STATUS must read 0 (nothing posted); and 0x23000038 MUST REPORT '!'. "
              "THE ERROR IS THE DISCRIMINATOR: this block was deliberately fixed (bug N1) so that in-range "
              "holes read 0 while out-of-range accesses raise PSLVERR, so a test that only probed 0x23000000 "
              "could not tell a correctly-bounded 16 KB aperture from one that aliases the whole 16 MB. "
              "Uses Reply.error, never value == 0. RED on any of the four. The original slot-0 word and LOCK "
              "are restored in a finally block; LOCK is not touched at all if a CPU already holds it. "
              "(The plan's literal sequence reads PERIPH_ID = 0xC0DE0001 instead of LOCK, because W "
              "auto-increments.) Budget: ~16 CU ~= 1.0 s.")
def hio_305(adp, rec):
    slot_orig = _r(adp, IPC_SLOT0_W0)
    lock_orig = _r(adp, IPC_LOCK)
    rec.record("ipc_slot0_w0_before", "0x%08X" % (slot_orig.value if slot_orig.value is not None else -1))
    rec.record("ipc_lock_before", "0x%08X" % (lock_orig.value if lock_orig.value is not None else -1))
    took_lock = False
    try:
        w = _w(adp, IPC_SLOT0_W0, PAT_A)
        r = _r(adp, IPC_SLOT0_W0)
        rec.check("IPC slot-0 data word 0 reads back 0x5A5A5A5A",
                  w.ok and not w.error and r.value == PAT_A, got="W=%s R=%s" % (w.raw, r.raw))

        if lock_orig.value == 0x00000000:
            lw = _w(adp, IPC_LOCK, 0x00000001)
            took_lock = True
            lr = _r(adp, IPC_LOCK)
            rec.check("IPC LOCK reads back 0x00000001",
                      lw.ok and not lw.error and lr.value == 0x00000001, got="W=%s R=%s" % (lw.raw, lr.raw))
        else:
            rec.note("IPC LOCK already reads %s — a CPU holds it. Not writing LOCK; that half is not "
                     "exercised rather than stamping on live firmware state." % lock_orig.raw)

        irq = _r(adp, IPC_IRQ_STATUS)
        rec.record("ipc_irq_status", "0x%08X" % (irq.value if irq.value is not None else -1))
        rec.check("IPC IRQ_STATUS reads 0x00000000 with no error flag (nothing has posted)",
                  irq.ok and not irq.error and irq.value == 0x00000000, got=irq.raw)

        oor = _r(adp, IPC_OUT_OF_RANGE)
        rec.record("ipc_out_of_range_reply", oor.raw)
        rec.check("0x23000038 REPORTS '!' — the out-of-range word index raises PSLVERR, proving the aperture "
                  "is bounded rather than aliasing the whole 16 MB (Reply.error, never value == 0)",
                  oor.ok and oor.error is True, got=oor.raw)
    finally:
        if took_lock:
            _w(adp, IPC_LOCK, lock_orig.value if lock_orig.value is not None else 0)
        if slot_orig.value is not None:
            _w(adp, IPC_SLOT0_W0, slot_orig.value)
        rec.note("Restored IPC slot-0 word 0 and LOCK to their captured values.")


@test("HIO-306", tier=3, hazard=None,
      purpose="etc_capture CTRL RW ([0] GLOBAL_EN, [1] IRQ_EN). Writes 0x00000003, reads it back, restores 0 "
              "and asserts the restore. RED on either readback. Proves ctrl_dbg_group sub-decode arm 0 "
              "accepts WRITES, not just reads. "
              "UNIQUE COVERAGE: leaf 0 takes ONE WAIT STATE on reads (ctrl_dbg_group.yaml:20-21) — bounded, "
              "not a stall — which makes HIO-306 the only test in the plan that proves the ADP handles an "
              "HREADY wait state at all; the other three leaves are zero-wait. GLOBAL_EN is restored to 0 in "
              "a finally block; leaving it set would arm event capture behind later tests. (The plan's "
              "literal restore lands on 0x2C000008 and leaves GLOBAL_EN SET.) Budget: 10 CU ~= 0.7 s.")
def hio_306(adp, rec):
    orig = _r(adp, ETC_CTRL)
    rec.record("etc_ctrl_before", "0x%08X" % (orig.value if orig.value is not None else -1))
    try:
        w = _w(adp, ETC_CTRL, 0x00000003)
        r = _r(adp, ETC_CTRL)
        rec.check("etc_capture CTRL accepts 0x00000003 and reads it back (also proves the ADP survives the "
                  "one wait state this leaf inserts)",
                  w.ok and not w.error and r.value == 0x00000003, got="W=%s R=%s" % (w.raw, r.raw))
    finally:
        w0 = _w(adp, ETC_CTRL, 0x00000000)
        r0 = _r(adp, ETC_CTRL)
        rec.check("etc_capture CTRL restored to 0x00000000 (GLOBAL_EN must be left clear)",
                  w0.ok and not w0.error and r0.value == 0x00000000, got="W=%s R=%s" % (w0.raw, r0.raw))


@test("HIO-307", tier=3, hazard=HZ.DESTRUCTIVE,
      destroys="every AHB perf-probe live counter (P0..P3 CYC/XFER/WAIT/...). The CLR is the point of the "
               "test. Do not run it in the middle of a measurement.",
      purpose="Write-only register asymmetry, in two halves that are both required. (1) perf_probe.CTRL "
              "(0x2C200008) is WO: its read value must NOT be the 0x00000002 just written — a block that "
              "implemented WO as RW would return it. (2) The FUNCTIONAL half: the CLR must actually restart "
              "P0_CYC. Without (2), 'the read did not match' is indistinguishable from 'the write went "
              "nowhere'. "
              "P0_CYC is documented SATURATING, not wrapping, so a die up for more than ~43 s at 100 MHz "
              "sits at 0xFFFFFFFF and 'restarted' is well defined. Three assertions: the post-CLR value is "
              "below a bound DERIVED FROM THE HOST-MEASURED elapsed time (not hard-coded); it is strictly "
              "less than the pre-CLR value; and it ADVANCES on a second read — that last one closes the "
              "vacuous path where a disabled or latched counter reads small forever and 'passes'. "
              "(The plan's literal CLR write lands on 0x2C20000C because R auto-increments.) "
              "Budget: ~16 CU ~= 1.0 s.")
def hio_307(adp, rec):
    ctrl_before = _r(adp, PERF_CTRL)
    cyc_before = _r(adp, PERF_P0_CYC)
    rec.record("perf_ctrl_read_value", "0x%08X" % (ctrl_before.value if ctrl_before.value is not None else -1))
    rec.record("perf_p0_cyc_before_clr", "0x%08X" % (cyc_before.value if cyc_before.value is not None else -1))
    if cyc_before.value == 0xFFFFFFFF:
        rec.note("P0_CYC reads 0xFFFFFFFF before the CLR: the counter is saturated, as expected on a die "
                 "that has been up for more than ~43 s at 100 MHz.")

    t0 = time.monotonic()
    wr = _w(adp, PERF_CTRL, PERF_CLR)
    cyc1 = _r(adp, PERF_P0_CYC)
    t1 = time.monotonic()
    cyc2 = _r(adp, PERF_P0_CYC)

    ctrl_after = _r(adp, PERF_CTRL)
    rec.check("perf_probe.CTRL is WRITE-ONLY: it does not read back the 0x%08X just written" % PERF_CLR,
              ctrl_after.ok and not ctrl_after.error and ctrl_after.value != PERF_CLR, got=ctrl_after.raw)

    elapsed = max(t1 - t0, 0.0)
    bound = max(200_000_000, int(elapsed * 3 * ASSUMED_HCLK_HZ))
    v1 = cyc1.value if cyc1.value is not None else -1
    v2 = cyc2.value if cyc2.value is not None else -1
    rec.record("perf_p0_cyc_after_clr", "0x%08X" % v1)
    rec.record("perf_p0_cyc_second_read", "0x%08X" % v2)
    rec.record("perf_clr_bound", "0x%08X (from %.3f s of host-measured elapsed time at %d Hz)"
               % (bound, elapsed, ASSUMED_HCLK_HZ))

    rec.check("the CLR write reported OK", wr.ok and not wr.error, got=wr.raw)
    rec.check("P0_CYC restarted: 0x%08X is below the elapsed-time bound 0x%08X" % (v1 & 0xFFFFFFFF, bound),
              0 <= v1 <= bound, got="0x%08X" % v1)
    rec.check("P0_CYC is strictly lower after the CLR than before it (the FUNCTIONAL proof that the WO write "
              "had an effect, which the read-value check alone cannot give)",
              cyc_before.value is not None and v1 >= 0 and v1 < cyc_before.value,
              got="before=0x%08X after=0x%08X" % (cyc_before.value or 0, v1))
    rec.check("P0_CYC ADVANCES after the CLR — rules out a latched or disabled counter reading small forever, "
              "which would make the two checks above vacuous",
              v2 > v1, got="0x%08X -> 0x%08X" % (v1, v2))


@test("HIO-308", tier=3, hazard=HZ.DESTRUCTIVE, weak=True,
      destroys="the bus_fault_monitor first-fault record (FAULT_STAT/FAULT_ADDR/FAULT_COUNT). Recorded "
               "first, then cleared and re-armed. Not recoverable.",
      purpose="bus_fault_monitor register file + W1C. "
              "WEAK=TRUE, and the reason is structural, not a shortcut: debug_m IS NOT ONE OF THE FOUR "
              "MONITORED INITIATORS (0 eth_ss_m/CPU0, 1 cpu_ss_1_m/CPU1, 2 dmac_0_m, 3 dap_ss_0_m), so ADP "
              "cannot provoke a fault it can then observe. This test cannot be self-stimulated and on its own "
              "proves the register file, not the monitor; it becomes a live test only when paired with "
              "HIO-507. "
              "What DOES go red here, and is not weak: the block's ASCII magic at 0x2C300010 must read "
              "0x42464D31 ('BFM1'), which a stuck bus cannot forge and which proves the ctrl_dbg_group "
              "sub-decode arm HADDR[21:20]==3. The W1C half is exercised only if FAULT_SEEN happens to be "
              "set; otherwise it is recorded as unexercised rather than counted. "
              "Register offsets are B-class (firmware/include/bus_dbg.h): confirm against "
              "src/rtl/wrappers/bus_fault_monitor.v before freezing. Budget: ~12 CU ~= 0.8 s.")
def hio_308(adp, rec):
    ident = _r(adp, BFM_ID)
    rec.record("bfm_id", "0x%08X" % (ident.value if ident.value is not None else -1))
    rec.check("bus_fault_monitor magic at 0x2C300010 reads 0x42464D31 ('BFM1') — unforgeable by a stuck bus, "
              "and it proves the ctrl_dbg_group sub-decode arm HADDR[21:20]==3",
              ident.ok and not ident.error and ident.value == 0x42464D31, got=ident.raw)

    stat = _r(adp, BFM_STAT)
    faddr = _r(adp, BFM_ADDR)
    fcount = _r(adp, BFM_COUNT)
    sv = stat.value if stat.value is not None else -1
    rec.record("bfm_fault_stat", "0x%08X" % sv)
    rec.record("bfm_fault_addr", "0x%08X" % (faddr.value if faddr.value is not None else -1))
    rec.record("bfm_fault_count", "0x%08X" % (fcount.value if fcount.value is not None else -1))
    rec.record("bfm_fault_seen", bool(sv > 0 and (sv & 0x1)))
    rec.record("bfm_init_idx", (sv >> 4) & 0x3 if sv > 0 else None)
    rec.record("bfm_overflow", bool(sv > 0 and (sv & 0x100)))
    rec.check("the fault record reads coherently (three well-formed, unflagged reads)",
              all(x.ok and not x.error for x in (stat, faddr, fcount)),
              got="stat=%s addr=%s count=%s" % (stat.raw, faddr.raw, fcount.raw))

    if sv > 0 and (sv & 0x1):
        w = _w(adp, BFM_STAT, 0x00000001)
        after = _r(adp, BFM_STAT)
        rec.check("writing 1 to FAULT_STAT[0] clears the record and re-arms the monitor",
                  w.ok and not w.error and after.value is not None and (after.value & 0x1) == 0,
                  got="W=%s R=%s" % (w.raw, after.raw))
    else:
        rec.note("FAULT_SEEN is clear, so the W1C half was NOT exercised. ADP cannot set it: debug_m is not "
                 "a monitored initiator. Pair with HIO-507 for a live test.")
        rec.record("bfm_w1c_exercised", False)


@test("HIO-309", tier=3, hazard=None,
      purpose="PHC RW / RO split, where the RO half is the discriminator. NS_INCR (0x22000008) and INT_EN "
              "(0x2200001C) are RW and must read back; CAP_NANOSECONDS (0x22000028) is RO and a write of "
              "0xDEADBEEF must NOT appear in it. A register file that made everything RW would pass both RW "
              "checks and fail only the RO one, which is exactly why the RO check is here. "
              "NS_INCR IS READ-THEN-RESTORED, never written blind: its reset is parameterised "
              "(DEFAULT_NS_INCR) and the chiplet override was not located, so the recorded value is the only "
              "safe restore target. The restore runs in a finally block and is asserted. "
              "The RO check compares against the POISON value, not against the pre-write value, because "
              "CAP_NANOSECONDS is a capture register and may legitimately change on its own. "
              "0x22000004 is NEVER read: STATUS[1] pps_sticky is read-to-clear and polling it eats every PPS "
              "event. PHC cannot stall (pready tied 1). (The plan's literal sequence writes NS_INCR to "
              "0x2200000C and reads INT_EN back from 0x22000020.) Budget: ~20 CU ~= 1.3 s.")
def hio_309(adp, rec):
    n0 = _r(adp, PHC_NS_INCR)
    n = n0.value if n0.value is not None else None
    rec.record("phc_ns_incr_before", "0x%08X" % (n if n is not None else -1))
    rec.check("NS_INCR read is well-formed and unflagged", n0.ok and not n0.error, got=n0.raw)
    if n is None:
        rec.skip("NS_INCR did not return a value; without a captured value there is no safe restore target.")

    try:
        w = _w(adp, PHC_NS_INCR, 0x00000005)
        r = _r(adp, PHC_NS_INCR)
        rec.check("PHC NS_INCR is RW and reads back 0x00000005",
                  w.ok and not w.error and r.value == 0x00000005, got="W=%s R=%s" % (w.raw, r.raw))
    finally:
        wr = _w(adp, PHC_NS_INCR, n)
        rr = _r(adp, PHC_NS_INCR)
        rec.check("PHC NS_INCR restored to its captured value 0x%08X" % n,
                  wr.ok and not wr.error and rr.value == n, got="W=%s R=%s" % (wr.raw, rr.raw))
        rec.note("NS_INCR was perturbed for one round trip (~0.3 s). If the PHC is enabled its accumulated "
                 "time is now offset by that window; the PHC is frozen out of reset, so on a die where "
                 "HIO-403 has not run there is no accrual at all.")

    try:
        wi = _w(adp, PHC_INT_EN, 0x00000003)
        ri = _r(adp, PHC_INT_EN)
        rec.check("PHC INT_EN is RW and reads back 0x00000003",
                  wi.ok and not wi.error and ri.value == 0x00000003, got="W=%s R=%s" % (wi.raw, ri.raw))
    finally:
        _w(adp, PHC_INT_EN, 0x00000000)

    c0 = _r(adp, PHC_CAP_NANOSECONDS)
    wc = _w(adp, PHC_CAP_NANOSECONDS, ROM_POISON)
    c1 = _r(adp, PHC_CAP_NANOSECONDS)
    rec.record("phc_cap_ns_before", "0x%08X" % (c0.value if c0.value is not None else -1))
    rec.record("phc_cap_ns_after", "0x%08X" % (c1.value if c1.value is not None else -1))
    rec.record("phc_cap_ns_write_reply", wc.raw)
    rec.check("PHC CAP_NANOSECONDS is READ-ONLY: 0x%08X did not land in it. This is the discriminator — a "
              "register file that made everything RW passes both RW checks above and fails only here"
              % ROM_POISON,
              c1.ok and not c1.error and c1.value != ROM_POISON, got=c1.raw)
    if c0.value is not None and c1.value is not None and c0.value != c1.value:
        rec.note("CAP_NANOSECONDS changed value across the write (0x%08X -> 0x%08X) without taking the "
                 "poison. It is a capture register; a capture event fired. Not a failure."
                 % (c0.value, c1.value))


@test("HIO-310", tier=3, hazard=HZ.WEDGE_RISK,
      purpose="TideLink read-only census over 0x2E032000-0x2E0321FC step 4, WITH THE QUARANTINE ENFORCED, "
              "each address read twice. "
              "THE TEST'S REAL SUBJECT IS THE BLOCKLIST. If the skip list is wrong you find out by hanging "
              "the port — HZ-1 is an uninterruptible AXI hang needing a power cycle — and per "
              "03_addrmap_param.md:105-112 SIMULATION CAN NEVER CATCH THAT MISTAKE, because in RTL those "
              "addresses are combinational reads with pready=1. So the skip list is DRY-RUN IN PROCESS "
              "BEFORE A SINGLE COMMAND IS SENT: the generated list is asserted to contain exactly 115 "
              "addresses, to exclude the whole 0x1A0-0x1B8 band (HZ-1, quarantined as a BAND, not as three "
              "offsets), and to exclude the six HZ-8 read-clearing registers where a read IS a write. That "
              "pre-flight assertion is itself a check that can go red, at zero bus cost. Every access "
              "additionally passes the module's hazard guard, which raises rather than transacting. "
              "The double read separates STABLE registers from LIVE counters without needing a golden file. "
              "RED on a NO-REPLY (a stall) or a failed pre-flight; differing values are CLASSIFIED, not "
              "failed. Marked WEDGE_RISK because a blocklist error costs a power cycle: never unattended. "
              "Budget: 460 CU ~= 30 s.")
def hio_310(adp, rec):
    hz1_lo, hz1_hi = 0x2E0321A0, 0x2E0321B8
    addrs = [a for a in range(TIDELINK_SWEEP_BASE, TIDELINK_SWEEP_LAST + 1, 4)
             if not (hz1_lo <= a <= hz1_hi) and a not in _READ_CLEARING]

    # ---- pre-flight dry run of the skip list: no bus traffic ----
    band = [a for a in addrs if hz1_lo <= a <= hz1_hi]
    rc = [a for a in addrs if a in _READ_CLEARING]
    aligned = all(a % 4 == 0 for a in addrs)
    in_window = all(TIDELINK_SWEEP_BASE <= a <= TIDELINK_SWEEP_LAST for a in addrs)
    rec.record("hio310_sweep_count", len(addrs))
    rec.record("hio310_skipped", 128 - len(addrs))
    rec.check("PRE-FLIGHT: the generated sweep excludes the whole HZ-1 band 0x2E0321A0-0x2E0321B8",
              not band, got=_hexl(band[:8]))
    rec.check("PRE-FLIGHT: the generated sweep excludes all six HZ-8 read-clearing registers",
              not rc, got=_hexl(rc))
    rec.check("PRE-FLIGHT: the sweep is exactly 115 word-aligned addresses inside 0x2E032000-0x2E0321FC "
              "(128 candidates minus 7 HZ-1 minus 6 HZ-8)",
              len(addrs) == 115 and aligned and in_window,
              got="n=%d aligned=%s in_window=%s" % (len(addrs), aligned, in_window))

    stable, live, errored, no_reply = [], [], [], []
    values = {}
    for a in addrs:
        r1 = _r(adp, a)
        r2 = _r(adp, a)
        if not (r1.ok and r2.ok):
            no_reply.append(a)
            continue
        if r1.error or r2.error:
            errored.append(a)
        values["0x%08X" % a] = ["0x%08X" % (r1.value or 0), "0x%08X" % (r2.value or 0)]
        (stable if r1.value == r2.value else live).append(a)

    rec.record("hio310_values", values)
    rec.record("hio310_stable_count", len(stable))
    rec.record("hio310_live_addrs", _hexl(live))
    rec.record("hio310_errored_addrs", _hexl(errored))
    rec.check("the sweep completed with NO NO-REPLY — a missing reply here means a stalling slave, which is "
              "what a wrong blocklist looks like",
              not no_reply, got=_hexl(no_reply[:8]))
    if live:
        rec.note("%d address(es) returned different values on two consecutive reads: live counters, or "
                 "read-side-effect registers not on the blocklist. Classify before adding any of them to a "
                 "polling loop: %s" % (len(live), _hexl(live[:8])))
    if errored:
        rec.note("%d address(es) reported '!' (a hole inside the APB window). Recorded, not failed."
                 % len(errored))


@test("HIO-311", tier=3, hazard=None,
      purpose="cc_periph timer0 RW — proves the cc_periph APB WRITE path (HIO-126 proved only reads) and "
              "sets up HIO-406. CTRL (0x28000000) is read and must be 0x00000000; VALUE (0x28000004) and "
              "RELOAD (0x28000008) are each written with 0x00010000 and read back. RED on either readback. "
              "NOTE THE PLAN MISLABELS THESE: the CMSDK map is 0x00 CTRL / 0x04 CURRENT VALUE / 0x08 RELOAD "
              "(cmsdk_apb_timer.v:29-38), while the plan calls 0x04 RELOAD and 0x08 VALUE. Both words are "
              "exercised here so the plan's intent and its literal sequence are each covered under the "
              "correct name. If CTRL[0] is found SET the timer is already counting, so VALUE is falling and "
              "the exact readback is relaxed to a bounded one and noted — otherwise this test would go red "
              "for a firmware reason rather than a silicon one. CTRL is left at 0 and RELOAD is left armed "
              "for HIO-406, by design. Budget: ~14 CU ~= 0.9 s.")
def hio_311(adp, rec):
    ctrl = _r(adp, TIMER0_CTRL)
    cv = ctrl.value if ctrl.value is not None else -1
    rec.record("timer0_ctrl", "0x%08X" % cv)
    rec.check("timer0 CTRL reads its reset value 0x00000000 (timer disabled)",
              ctrl.ok and not ctrl.error and cv == 0x00000000, got=ctrl.raw)
    running = cv > 0 and (cv & 0x1)
    if running:
        rec.note("timer0 CTRL[0] is SET: the timer is counting, so CURRENT VALUE is falling. The exact "
                 "readback below is relaxed to a bounded check.")

    wv = _w(adp, TIMER0_VALUE, TIMER_SETUP_VALUE)
    rv = _r(adp, TIMER0_VALUE)
    got_v = rv.value if rv.value is not None else -1
    rec.record("timer0_value_readback", "0x%08X" % got_v)
    if running:
        rec.check("timer0 CURRENT VALUE (0x28000004) accepted 0x00010000 and is counting down from it",
                  wv.ok and not wv.error and 0 < got_v <= TIMER_SETUP_VALUE, got=rv.raw)
    else:
        rec.check("timer0 CURRENT VALUE (0x28000004) accepts 0x00010000 and reads it back exactly",
                  wv.ok and not wv.error and got_v == TIMER_SETUP_VALUE, got=rv.raw)

    wr = _w(adp, TIMER0_RELOAD, TIMER_SETUP_VALUE)
    rr = _r(adp, TIMER0_RELOAD)
    rec.record("timer0_reload_readback", "0x%08X" % (rr.value if rr.value is not None else -1))
    rec.check("timer0 RELOAD (0x28000008) accepts 0x00010000 and reads it back — the cc_periph APB WRITE "
              "path, which HIO-126's read-only test could not reach",
              wr.ok and not wr.error and rr.value == TIMER_SETUP_VALUE, got="W=%s R=%s" % (wr.raw, rr.raw))
    rec.note("CTRL left at 0 and RELOAD left armed at 0x00010000 for HIO-406, as the plan intends.")


@test("HIO-312", tier=3, hazard=None,
      purpose="QSPI register RW with NO flash activity. CMD (0x21000008) takes 0x00000003 — the command byte "
              "only — and reads back; ADDR (0x2100000C) is written 0xFFFFFFFF and must read back 0x003FFFFF, "
              "then 0x00123456 and must read back exactly. RED on any of the three. "
              "The 0xFFFFFFFF -> 0x003FFFFF step is the sharper version the plan recommends: it proves ADDR's "
              "22-bit width (apb_qspi_regs.v:136) as well as its writability, so a full-width register or a "
              "truncated one are told apart, which the 0x00123456 pattern alone cannot do. "
              "CMD[8] IS NEVER SET — a module-level guard raises if any write to 0x21000008 carries bit 8, so "
              "no flash transaction can start and the test is safe with or without a device fitted. HZ-6 "
              "still forbids 0x24xxxxxx and the hazard guard enforces it. Both registers restored to 0 in a "
              "finally block. (The plan's literal restores land one word past their registers.) "
              "Budget: ~18 CU ~= 1.2 s.")
def hio_312(adp, rec):
    ctrl = _r(adp, QSPI_CTRL)
    rec.record("qspi_ctrl", "0x%08X" % (ctrl.value if ctrl.value is not None else -1))
    if ctrl.value is not None and (ctrl.value & 0x100):
        rec.note("QSPI CTRL[8] XIP_ACTIVE is SET — XiP is live on this build, so 0x24xxxxxx is ARMED, not "
                 "dormant (HZ-6). This test does not go near it.")
    try:
        wc = _w(adp, QSPI_CMD, 0x00000003)
        rc = _r(adp, QSPI_CMD)
        rec.check("QSPI CMD accepts 0x00000003 (command byte only, CMD[8] enable clear) and reads it back",
                  wc.ok and not wc.error and rc.value == 0x00000003, got="W=%s R=%s" % (wc.raw, rc.raw))

        wa = _w(adp, QSPI_ADDR, 0xFFFFFFFF)
        ra = _r(adp, QSPI_ADDR)
        rec.record("qspi_addr_all_ones_readback", "0x%08X" % (ra.value if ra.value is not None else -1))
        rec.check("QSPI ADDR is 22 bits wide: writing 0xFFFFFFFF reads back 0x003FFFFF",
                  wa.ok and not wa.error and ra.value == 0x003FFFFF, got=ra.raw)

        wa2 = _w(adp, QSPI_ADDR, 0x00123456)
        ra2 = _r(adp, QSPI_ADDR)
        rec.check("QSPI ADDR accepts 0x00123456 and reads it back exactly",
                  wa2.ok and not wa2.error and ra2.value == 0x00123456, got=ra2.raw)
    finally:
        _w(adp, QSPI_ADDR, 0x00000000)
        _w(adp, QSPI_CMD, 0x00000000)
        rec.note("QSPI CMD and ADDR restored to 0. CMD[8] was never set.")


@test("HIO-313", tier=3, control=True, gates=["HIO-502"], hazard=None,
      purpose="ABORT GATE 8 — the boot-gate WRITE PATH exercised as a GUARANTEED NO-OP. Reads 0x29000000, "
              "writes exactly 0x00000000 to it, reads again. remap_q <= remap_q | HWDATA[3:0] "
              "(chip_core_remap_ctrl.v:117, verified), so OR-with-zero cannot set a bit. "
              "THIS CONVERTS HZ-4 FROM 'WE DARE NOT TOUCH IT' INTO 'WE HAVE EXERCISED IT SAFELY': it proves "
              "the write reaches the most dangerous register on the die without arming anything. "
              "RED if the write reports '!' or if the readback differs by a single bit. HRESP is tied 0 in "
              "this block, so a '!' means the access did not reach the block at all and fell through to the "
              "default slave — a decode fault, and a real discriminator. "
              "GATES HIO-502 (the irreversible CPU0 release). IF THIS TEST REPORTS '!' OR THE VALUE CHANGES, "
              "DO NOT PROCEED TO HIO-502. "
              "SAFETY: the write goes through _bootgate_noop_write(), which triple-guards the datum (must be "
              "exactly 0), the address (must be exactly 0x29000000) and the module constant itself; and "
              "0x29xxxxxx is on the module's _NEVER_WRITE list so no other test in either tier can reach it. "
              "adp.write re-issues A before W, so the write cannot ride the auto-increment from the preceding "
              "R — which in the plan's literal sequence lands it on 0x29000004 and is a no-op only because "
              "this block ignores HADDR entirely. "
              "A POSITIVE WRITE-PATH CONTROL RUNS FIRST, and it is not optional: as the plan specifies this "
              "test, A COMPLETELY DEAD ADP WRITE PATH PASSES IT (mutation-proven), because 'the boot gate did "
              "not change' is exactly what a write that goes nowhere produces — so the gate that authorises "
              "the irreversible CPU0 release could not detect the one failure that matters. The control "
              "writes 0xD00DFEED to eth IMEM at 0x10001000 (a MEASURED-good write/read-back/restore address), "
              "reads it back, and restores the captured original, so this test still destroys nothing. "
              "Budget: 12 CU ~= 0.8 s.")
def hio_313(adp, rec):
    # POSITIVE WRITE-PATH CONTROL, contemporaneous and reversible.  Without it
    # this test passes with a completely dead ADP write path: its own assertion
    # is "the value did not change", which a write that goes nowhere satisfies
    # perfectly.  Abort Gate 8 gates the IRREVERSIBLE CPU0 release, so it must
    # not be able to pass vacuously.
    ctl_orig = _r(adp, BOOTGATE_WRITE_CONTROL_ADDR)
    try:
        cw = _w(adp, BOOTGATE_WRITE_CONTROL_ADDR, BOOTGATE_WRITE_CONTROL_TAG)
        cr = _r(adp, BOOTGATE_WRITE_CONTROL_ADDR)
        rec.record("bootgate_write_path_control", "0x%08X -> %s" % (BOOTGATE_WRITE_CONTROL_ADDR, cr.raw))
        rec.check("POSITIVE CONTROL: the ADP write path really lands data on the bus (0x%08X takes 0x%08X). "
                  "Without this check a write path that goes nowhere passes this whole test, because "
                  "'the boot gate did not change' is exactly what a dead write produces"
                  % (BOOTGATE_WRITE_CONTROL_ADDR, BOOTGATE_WRITE_CONTROL_TAG),
                  cw.ok and not cw.error and cr.value == BOOTGATE_WRITE_CONTROL_TAG,
                  got="W=%s R=%s" % (cw.raw, cr.raw))
    finally:
        if ctl_orig.ok and ctl_orig.value is not None:
            rw = _w(adp, BOOTGATE_WRITE_CONTROL_ADDR, ctl_orig.value)
            rr = _r(adp, BOOTGATE_WRITE_CONTROL_ADDR)
            rec.check("the write-path control word at 0x%08X is restored to 0x%08X — this test destroys nothing"
                      % (BOOTGATE_WRITE_CONTROL_ADDR, ctl_orig.value),
                      rw.ok and not rw.error and rr.value == ctl_orig.value,
                      got="W=%s R=%s" % (rw.raw, rr.raw))
        else:
            rec.note("Could not capture the original word at 0x%08X, so it was NOT restored and may still "
                     "hold 0x%08X. eth IMEM is destroyed by Tier 2 anyway."
                     % (BOOTGATE_WRITE_CONTROL_ADDR, BOOTGATE_WRITE_CONTROL_TAG))

    before = _r(adp, BOOTGATE_ADDR)
    v = before.value if before.value is not None else -1
    rec.record("bootgate_before", "0x%08X" % v)
    rec.record("bootgate_cpu0_released_before", bool(v > 0 and (v & 0x4)))
    rec.check("the boot-gate read is well-formed and unflagged", before.ok and not before.error, got=before.raw)

    wr = _bootgate_noop_write(adp, BOOTGATE_ADDR, BOOTGATE_NOOP_DATUM)
    rec.record("bootgate_write_reply", wr.raw)
    rec.check("the OR-with-zero write to 0x29000000 reports OK (no '!'). HRESP is tied 0 in this block, so a "
              "'!' means the access never reached it and hit the default slave instead",
              wr.ok and wr.error is False, got=wr.raw)

    after = _r(adp, BOOTGATE_ADDR)
    va = after.value if after.value is not None else -2
    rec.record("bootgate_after", "0x%08X" % va)
    rec.check("the boot gate is BIT-FOR-BIT UNCHANGED across the write (0x%08X). Any set bit here would be "
              "irreversible without a power cycle" % v,
              after.ok and not after.error and va == v, got="before=0x%08X after=0x%08X" % (v, va))

    if va == v and v >= 0 and not (v & 0x4):
        rec.note("Boot gate bit 2 is CLEAR: CPU0 has never been released. HIO-502 would be a real, "
                 "irreversible action on this die.")
    elif va == v and v >= 0:
        rec.note("Boot gate bit 2 already reads SET, so CPU0 is already released and HIO-502 may be a no-op "
                 "here. Resolve which before Phase F (plan §5.5): the FPGA build showed 0x29000000 and "
                 "0x29000004 returning identical values, and this block ignores HADDR, so an alias cannot be "
                 "ruled out from this register alone.")


@test("HIO-314", tier=3, hazard=None,
      purpose="RO-IMMUTABILITY SWEEP — RUN THIS LAST IN TIER 3. For each of CID0 (0x2A000FF0), "
              "LINK_CAPABILITIES (0x2E030200), TC_DEVICE_CLASS (0x2E040010), IPC PERIPH_ID (0x23000034) and "
              "DMA IIDR (0x20000FC8): read, write 0xFFFFFFFF, read again. RED when any value changes. "
              "This is the mirror image of HIO-301 and it RETRO-VALIDATES EVERY IDENTITY CONSTANT TIER 1 "
              "RECORDED: it proves they are actually constants and not RW registers that happen to hold the "
              "right value. Without it, every Tier-1 identity test is one stray earlier write away from being "
              "meaningless — the plan's own §4.3 false-green #2. "
              "GUARD AGAINST A VACUOUS PASS: a register reading 0x00000000 both times passes trivially "
              "(the DMA IIDR does exactly this when the block is power-gated), so entries whose pre-value is "
              "zero are recorded as UNEXERCISED and a separate check requires at least three non-zero "
              "constants to have survived. The address list is FIXED and asserted; the plan forbids extending "
              "this sweep to any address not on it. 0x2E030200 is in the wlink sub-region, which passes "
              "pready straight through with no watchdog (HZ-9). Budget: 20 CU ~= 1.3 s.")
def hio_314(adp, rec):
    sweep = (
        ("reset_ctrl_CID0", 0x2A000FF0),
        ("tidelink_LINK_CAPABILITIES", 0x2E030200),
        ("tidechart_TC_DEVICE_CLASS", 0x2E040010),
        ("ipc_PERIPH_ID", 0x23000034),
        ("dma250_IIDR", 0x20000FC8),
    )
    rec.check("the RO sweep list is exactly the five addresses the plan permits (it must not be extended)",
              len(sweep) == 5 and [a for _, a in sweep] ==
              [0x2A000FF0, 0x2E030200, 0x2E040010, 0x23000034, 0x20000FC8],
              got=_hexl([a for _, a in sweep]))

    exercised = 0
    for name, addr in sweep:
        b = _r(adp, addr)
        w = _w(adp, addr, 0xFFFFFFFF)
        a = _r(adp, addr)
        bv = b.value if b.value is not None else -1
        av = a.value if a.value is not None else -2
        rec.record("%s_before" % name, "0x%08X" % bv)
        rec.record("%s_after" % name, "0x%08X" % av)
        rec.record("%s_write_reply" % name, w.raw)
        rec.check("%s (0x%08X) is IMMUTABLE: unchanged after a write of 0xFFFFFFFF" % (name, addr),
                  b.ok and not b.error and a.ok and not a.error and av == bv,
                  got="before=0x%08X after=0x%08X" % (bv, av))
        if bv > 0:
            exercised += 1
        else:
            rec.note("%s reads 0x00000000, so its immutability check is UNEXERCISED — a dead read and an "
                     "immutable zero are indistinguishable. (For the DMA IIDR this means power-gated, not "
                     "absent: HIO-124.)" % name)

    rec.record("hio314_exercised_nonzero_constants", exercised)
    rec.check("at least 3 of the 5 constants held a NON-ZERO value across the write, so the sweep tested "
              "immutability rather than agreeing with a bus that returns zeros",
              exercised >= 3, got="%d/5 non-zero" % exercised)
