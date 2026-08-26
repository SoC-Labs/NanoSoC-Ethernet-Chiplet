"""HOSTIO4 / ADP test suite — Tier 1: static identity (HIO-101 .. HIO-127, 27 tests).

This tier is the die's FINGERPRINT. Every value it reads is captured verbatim into
the die record and diffed between chips. Nothing here writes the bus.

Written against:
  - scripts/rig/eth_chiplet/hostio_suite/CONTRACT.md          (pinned API — binding)
  - docs/bringup/HOSTIO4_FUNCTIONAL_TEST_PLAN.md  Tier 1 table, §2.1, §1.4, §1.5, §5

Assumptions this module makes about the runner (from CONTRACT.md + plan §2.0):
  - The runner has already done the entry preamble (`adp.enter()`), and the client's
    resync watchdog is live. A starved watchdog looks exactly like dead silicon.
  - Tests are executed in the order they are declared in this module. That order is
    the plan's §3 Phase-A3/B1..B5 order, and it puts HIO-106 first (see PHASE_ORDER).

Deliberate deviations from the plan, each justified in the test's own note():
  - Block reads (`Rx000000nn`) are not used. CONTRACT's `Reply` exposes a single
    `.value`, so a multi-word reply has no defined parse. Every multi-word read here
    is done as N x `adp.read(addr)` calls, which is the same bus traffic at 2 CU each.
  - HIO-118 is implemented READ-ONLY (see its docstring). The plan's tag-write variant
    is destructive and belongs in Phase D; Tier 1 is non-destructive by definition.
  - Build-artefact (`B`-class) magics are asserted only where this module confirmed
    them against the instantiated RTL (see the per-test notes). Disputed constants are
    recorded, never asserted.
"""

from harness import Adp, Reply, test, Rec, HZ  # noqa: F401  (HZ unused: Tier 1 is read-only)
import harness as harness_module  # fill patterns + LOADED_MODULES; see _residue_drift()

# ---------------------------------------------------------------------------
# Declaration order == execution order. Plan §3 Phase A3 / B1..B5.
# HIO-106 is FIRST: it is the die's boot state and tells you whether CPU0 is loose,
# i.e. whether the bus was even quiescent for every reading below it.
# ---------------------------------------------------------------------------
PHASE_ORDER = [
    "HIO-106",                                    # B1  boot gate, FIRST
    "HIO-120",                                    # A3  ADP operand regs (no bus access)
    "HIO-103", "HIO-104",                         # B2  ABORT GATE 4 — the CID control
    "HIO-114",                                    # B3  ABORT GATE 5 — the census
    "HIO-116", "HIO-101", "HIO-102", "HIO-107",   # B4  remap, both ROMs, boot consistency
    "HIO-105", "HIO-108", "HIO-109", "HIO-110",   # B5  the rest of the identity set
    "HIO-111", "HIO-112", "HIO-113", "HIO-115",
    "HIO-117", "HIO-118", "HIO-119", "HIO-121",
    "HIO-122", "HIO-123", "HIO-124", "HIO-125",
    "HIO-126", "HIO-127",
]


# ===========================================================================
# HAZARD BLOCKLIST — plan §1.5 and the §2.1 exclusion list.
#
# "This exclusion list is part of the test — it must be encoded in the census
#  script, not left to the operator."  (§2.1)
#
# It is enforced here for EVERY read this module makes, not just the census, by
# _rd()/_probe(). An address in one of these bands raises rather than being sent.
# ===========================================================================
_HAZARD_BANDS = [
    # (lo, hi_inclusive, id, why)
    (0x2E0321A0, 0x2E0321B8, "HZ-1",
     "TideLink SYNC_DIST band — uninterruptible AXI hang, power cycle to recover. "
     "The whole band is quarantined, not just the three named offsets."),
    (0x2F000000, 0x2FFFFFFF, "HZ-2",
     "Peer aperture — no default responder. A failed cross-die read parks the peer "
     "port and the NEXT access wedges the host. Tier 4 HIO-413 only, one-shot."),
    (0x2E000000, 0x2E003FFF, "HZ-3",
     "TideLink TX aperture — wedges on a write while the link is up."),
    (0x24000000, 0x27FFFFFF, "HZ-6",
     "QSPI XiP aperture — HREADYOUT held low for 65536 HCLK (~1.3 ms) with no flash, "
     "and never released if a CPU is executing from XiP. Blocklisted outright."),
    (0x2C100000, 0x2C1002FF, "HZ-7",
     "Spinlock ACQUIRE pages (CPU0 +0x000 / CPU1 +0x100 / DBG +0x200). A READ of an "
     "acquire page ACQUIRES the lock. The DIAG page at +0x300 is excluded from this "
     "band and is safe — that is the one HIO-112 reads."),
]

_HAZARD_WORDS = {
    # HZ-8 — read-clearing / auto-incrementing. A read here IS a write.
    0x2E032020: "HZ-8 RELEASED_CREDITS_ACC — read-clears, corrupts live credit bookkeeping",
    0x2E032024: "HZ-8 RELEASED_CREDITS_ACC — read-clears",
    0x2E032038: "HZ-8 DOORBELL_RESPONSE_ACC — read-clears",
    0x2E03215C: "HZ-8 read-clearing / auto-incrementing",
    0x2E032160: "HZ-8 read-clearing / auto-incrementing",
    0x2E032168: "HZ-8 read-clearing / auto-incrementing",
}


def forbidden(addr):
    """Return a reason string if `addr` must never be read from Tier 1, else None."""
    if addr in _HAZARD_WORDS:
        return _HAZARD_WORDS[addr]
    for lo, hi, hz, why in _HAZARD_BANDS:
        if lo <= addr <= hi:
            return "%s [0x%08X-0x%08X] %s" % (hz, lo, hi, why)
    return None


class HazardViolation(RuntimeError):
    """Raised instead of touching a blocklisted address. Never caught in this module."""


def _guard(addr):
    why = forbidden(addr)
    if why is not None:
        raise HazardViolation("REFUSING to read 0x%08X — %s" % (addr, why))


# ---------------------------------------------------------------------------
# small helpers
# ---------------------------------------------------------------------------
def _h(v):
    return "None" if v is None else "0x%08X" % (v & 0xFFFFFFFF)


def _field(word, hi, lo):
    return (word >> lo) & ((1 << (hi - lo + 1)) - 1)


def _ascii(word):
    """Render a 32-bit word MSB-byte-first: 0x42464D31 -> 'BFM1'.

    That is the order every block magic this tier reads is packed in: BFM1 (HIO-108),
    ETC1 (HIO-109), PRF1 (HIO-110). Byte order is not universal across the SoC, so
    check it before reusing this on a magic from another block.
    """
    if word is None:
        return ""
    bs = [(word >> s) & 0xFF for s in (24, 16, 8, 0)]
    return "".join(chr(b) if 0x20 <= b <= 0x7E else "." for b in bs)


def _printable(word):
    return all(0x20 <= ((word >> s) & 0xFF) <= 0x7E for s in (0, 8, 16, 24))


def _probe(adp, addr):
    """One guarded read. Returns the Reply whatever it says — errors included."""
    _guard(addr)
    return adp.read(addr)


def _rd(adp, rec, addr, label):
    """Guarded read that MUST come back clean. Returns the value, or None on failure.

    Two separate assertions so a timeout and a bus error are distinguishable in the
    record: NO-REPLY is a different diagnosis from HRESP=ERROR (plan §1.5)."""
    r = _probe(adp, addr)
    ok_reply = rec.check("%s @%s replied" % (label, _h(addr)), r.ok is True, got=r.raw)
    ok_bus = rec.check("%s @%s no bus error (!)" % (label, _h(addr)),
                       r.error is False, got=r.raw)
    if ok_reply is False or ok_bus is False:
        pass  # rec.check records the failure; keep going so the record stays complete
    if r.ok and not r.error:
        return r.value
    return None


def _eq(rec, label, got, want):
    return rec.check("%s == %s" % (label, _h(want)), got == want, got=_h(got))


def _marker(rec, label, word, expect, hi=31, lo=24):
    """Marker-byte discipline (plan HIO-409 note, §0.1).

    A TideLink/CoreSight-style register carries a structural marker in its top bits.
    If the marker is absent the register is absent or mis-decoded and EVERY BIT BELOW
    IT IS MEANINGLESS — a test that decodes bits without this check will cheerfully
    report "healthy, all zeros" on a register that is not there.

    This is always a SEPARATE rec.check that must hold, evaluated BEFORE any sub-field
    is decoded. Returns True when the caller may decode below the marker.
    """
    if word is None:
        rec.check("%s marker [%d:%d] present" % (label, hi, lo), False, got="no value")
        return False
    got = _field(word, hi, lo)
    held = rec.check("%s marker [%d:%d] == 0x%X" % (label, hi, lo, expect),
                     got == expect, got="0x%X (word %s)" % (got, _h(word)))
    return bool(held) and got == expect


# ===========================================================================
# B1 — HIO-106.  RUNS FIRST.
# ===========================================================================
# The six-rung BOOT-STATE LADDER.
# docs/bringup/ASIC_FIRST_SILICON_HOSTIO_PROCEDURE.md §3.2 (running order and expected
# values) and §0.3 (what a zero boot gate actually means). Every rung is HOSTIO-
# readable and each says how far CPU1 got, so a zero gate resolves into WHICH of four
# states rather than one undifferentiated "anomaly". Run only when the gate reads
# zero: 8 extra reads, ~1 s, and only on the die that needs the diagnosis.
#
# (rung, address, expected, mode, what it proves)
_BOOT_LADDER = [
    (0, 0x800000E4, 0x08000678, "eq",  "CPU1 ROM slot holds stage0_bootrom_chip_core"),
    (0, 0x800004F4, 0x220423A4, "eq",  "gate-release store site 1 present in ROM"),
    (0, 0x800004F8, 0x601A059B, "eq",  "gate-release store site 1 (continued)"),
    (1, 0x98000200, 0x0F1C0DE1, "eq",  "CPU1 main() entered"),
    (2, 0x21000030, 0x0000800B, "eq",  "QSPI AHB_SETUP written"),
    (3, 0x21000000, 1 << 8,     "bit", "QSPI CTRL[8] XIP_ACTIVE latched"),
    (4, 0x23000010, 0xD15C0001, "eq",  "XiP-warm handshake published"),
    (5, 0x98000084, 0xFFFFFFFF, "eq",  "CPU1 g_tbl (0xFFFFFFFF on blank flash)"),
]


def _bootgate_values(rec):
    """The target profile's declared terminating-path words, or () if undeclared."""
    t = getattr(rec, "target", None)
    if t is None:
        return ()
    return tuple(t.get("bootgate_values", ()) or ())


def _run_boot_ladder(adp, rec):
    """Read the ladder and return (rung_ok dict, values dict). No assertions here --
    the caller decides, because most ladder failures are benign diagnoses."""
    ok, vals = {}, {}
    for rung, addr, expect, mode, what in _BOOT_LADDER:
        v = _probe(adp, addr)
        got = v.value if (v.ok and not v.error) else None
        vals["%s" % _h(addr)] = {"rung": rung, "value": got, "raw": v.raw,
                                 "expected": _h(expect), "proves": what}
        held = (got is not None and
                ((got & expect) == expect if mode == "bit" else got == expect))
        ok[rung] = ok.get(rung, True) and held
    return ok, vals


# Every other test in the tier. HIO-106 gates all of them — see its purpose.
_TIER1_OTHERS = [
    "HIO-101", "HIO-102", "HIO-103", "HIO-104", "HIO-105", "HIO-107", "HIO-108",
    "HIO-109", "HIO-110", "HIO-111", "HIO-112", "HIO-113", "HIO-114", "HIO-115",
    "HIO-116", "HIO-117", "HIO-118", "HIO-119", "HIO-120", "HIO-121", "HIO-122",
    "HIO-123", "HIO-124", "HIO-125", "HIO-126", "HIO-127",
]


@test("HIO-106", tier=1, control=True, gates=_TIER1_OTHERS, hazard=None,
      purpose="Boot-gate register 0x29000000 — the boot state of the chip, read FIRST, "
              "and on a zero reading followed immediately by the six-rung BOOT-STATE "
              "LADDER that says how far CPU1 actually got. "
              "ALWAYS ASSERTED, target-independent: the read is clean, and bits "
              "[31:4] == 0 because HRDATA = {28'b0, remap_q} "
              "(chip_core_remap_ctrl.v:121) — a non-zero top means something other "
              "than the boot gate answered. "
              "THE VALUE IS NEVER ASSERTED AGAINST A HARDCODED CONSTANT. On a "
              "NON-ZERO reading it is checked against the target profile's "
              "bootgate_values via rec.target_check, so an undeclared target defers "
              "instead of inheriting FPGA expectations. "
              "A ZERO READING IS NOT ASSUMED TO BE A FAULT. 0x00000000 is FOUR "
              "distinct states, not one, and on an ASIC bring-up board with "
              "unprovisioned or absent QSPI flash it is the EXPECTED reading and the "
              "quietest bus state the die can be in: CPU1 HardFaults on xip_enable()'s "
              "warm-up read of 0x24000000 (the QSPI AHB wrapper holds HREADYOUT low "
              "for a 16-bit watchdog then ERRORs with no flash device) and parks in "
              "'b .' at 0x080001CE, never reaching either cc_rom site that writes the "
              "gate. So the ladder runs and CLASSIFIES instead: rung 0 wrong ROM; rung "
              "1 CPU1 never reached main(); rungs 2/3 halted inside xip_enable(); "
              "rungs 1-3 good but no handshake at rung 4 = the no-flash HardFault park, "
              "BENIGN and by far the most likely first-silicon reading. "
              "THE ONE ZERO THAT IS A HARD RED is rung 4 published (the XiP-warm "
              "handshake at 0x23000010 = 0xD15C0001) with the gate still zero on a "
              "re-read: CPU1 provably survived xip_enable(), so it must have reached a "
              "terminating store — both are in the reticle — and a zero then "
              "contradicts the mask. That is the only reading in §0.3's table that is a "
              "silicon finding, and it is the only one that fails here. "
              "NOT a write test: HZ-4 (write-1-set, irreversible without a power "
              "cycle) applies to writes only; this test only reads.")
def hio_106(adp, rec):
    v = _rd(adp, rec, 0x29000000, "boot gate")
    rec.record("boot_gate_word", v)
    if v is None:
        return

    # Structural, target-independent: 4-bit register, zero-extended.
    rec.check("boot gate [31:4] == 0 (HRDATA = {28'b0, remap_q})",
              _field(v, 31, 4) == 0, got=_h(v))

    cpu0_released = bool(v & (1 << 2))          # nanosoc_multicore_soc.sv:1387-1388
    rec.record("cpu0_bootgate_bit2", int(cpu0_released))
    rec.record("boot_gate_bit0", int(bool(v & 1)))
    rec.record("boot_gate_bit1", int(bool(v & 2)))
    rec.record("boot_gate_bit3", int(bool(v & 8)))
    rec.record("bus_quiescent_expected", int(not cpu0_released))

    if v & (1 << 1):
        rec.note("BOOT GATE BIT 1 (CHIP_CORE_BOOTGATE) IS SET — unexplained. Nothing "
                 "in either boot ROM writes it, and the SoC ties cpu1_bootgate to "
                 "1'b1 so it does nothing anyway. Something other than the ROM wrote "
                 "this register. Recorded, not diagnosed; stop before Phase C and "
                 "resolve it.")

    # ---------------------------------------------------------------- non-zero ----
    if v != 0x00000000:
        outcome = {0x00000004: "CPU1 found NO boot candidate — unprovisioned flash, "
                               "the expected first-silicon reading. CPU1 is in "
                               "'wfi ; b .' in ROM and CPU0 HAS been released.",
                   0x00000005: "CPU1 found a CRC-valid image: it released CPU0, set "
                               "its own REMAP and branched into IMEM. CPU1 IS RUNNING "
                               "AN APPLICATION and you do not know what it is doing "
                               "to memory.",
                   }.get(v, "unrecognised encoding — decode against cc_rom before "
                            "trusting anything below")
        rec.record("cpu1_boot_outcome", outcome)
        rec.record("boot_ladder_run", 0)

        known = _bootgate_values(rec)
        rec.target_check("boot gate is a terminating-path value for this target",
                         (v in known) if known else None,
                         prop="bootgate_values", got=_h(v),
                         expected=[_h(x) for x in known] or None)
        rec.note("Boot gate = %s: %s CPU0 IS RELEASED and is contending for the bus "
                 "and mutating memory, so every Tier-1 value below was read from a "
                 "LIVE system — RAM-backed readings (HIO-107, the census RAM rows, "
                 "HIO-118) may move between probes. That is the NORMAL condition on "
                 "both targets, not a fault." % (_h(v), outcome))
        return

    # -------------------------------------------------------------------- zero ----
    rec.record("boot_ladder_run", 1)
    ok, vals = _run_boot_ladder(adp, rec)
    rec.record("boot_ladder", vals)
    rec.record("boot_ladder_rungs_ok",
               dict(("rung%d" % k, int(bool(ok.get(k)))) for k in sorted(ok)))

    # Re-read: the ladder itself bought ~1 s of elapsed time, so a CPU1 that was
    # merely still executing has had a chance to finish.
    again = _rd(adp, rec, 0x29000000, "boot gate (after ladder)")
    rec.record("boot_gate_word_after_ladder", again)
    if again not in (None, 0x00000000):
        rec.record("cpu1_boot_outcome",
                   "CPU1 was STILL EXECUTING during the first read; the gate reached "
                   "%s by the end of the ladder. Not a fault." % _h(again))
        rec.note("The boot gate went 0x00000000 -> %s across the ladder. CPU1 was "
                 "simply still booting when the suite started. Use the later value "
                 "for the record, and note that anything read before it was taken "
                 "from a die that had not finished booting." % _h(again))
        return

    # §0.3's table, in order. Only the last branch is a silicon finding.
    if not ok.get(0, False):
        state = ("rung 0 FAILED — the CPU1 ROM slot does not hold "
                 "stage0_bootrom_chip_core, or the gate-release stores are not in it. "
                 "A wrong ROM image explains a zero gate with NO silicon fault, and it "
                 "voids the premise of the whole bring-up procedure for this die.")
        silicon = False
    elif not ok.get(1, False):
        state = ("rung 1 FAILED — CPU1 never reached main(). Suspect the CPU1 core, "
                 "its reset, or the ROM. Rung 0 passed, so the image is right.")
        silicon = False
    elif not (ok.get(2, False) and ok.get(3, False)):
        state = ("rungs 2/3 FAILED — CPU1 halted inside xip_enable(); CTRL.XIP_ACTIVE "
                 "never latched. halt() is 'for(;;) wfi();', a quiet park in ROM. "
                 "Suspect the QSPI controller or its clock.")
        silicon = False
    elif not ok.get(4, False):
        state = ("rungs 1-3 OK, rung 4 absent — THE MOST LIKELY READING ON A FIRST "
                 "BRING-UP BOARD, AND IT IS BENIGN. xip_enable()'s warm-up read of "
                 "0x24000000 hit an AHB ERROR (no flash device: the QSPI AHB wrapper "
                 "holds HREADYOUT low for 65536 HCLK, then ERRORs) and CPU1 took "
                 "HardFault_Handler, which is 'b .' at 0x080001CE. CPU1 is parked in a "
                 "branch-to-self in ROM — the QUIETEST bus state this die can be in — "
                 "and CPU0 is still held in reset. Provision flash, or accept a "
                 "quiescent bus and read on.")
        silicon = False
    else:
        state = ("rung 4 PUBLISHED but the gate is STILL ZERO on a re-read — THE ONLY "
                 "SILICON FINDING in §0.3's table. CPU1 provably survived "
                 "xip_enable(), so it reached a terminating path, and both stores are "
                 "in the reticle (cc_rom byte offsets 0x4F4 and 0x528). Either CPU1 is "
                 "still executing — re-run after 5 s before believing this — or the "
                 "0x29 decode arm or chip_core_remap_ctrl is faulty.")
        silicon = True

    rec.record("cpu1_boot_outcome", state)
    rec.record("boot_gate_zero_is_silicon_finding", int(silicon))

    rec.check("boot gate zero is not the rung-4 contradiction "
              "(XiP handshake published, yet no terminating store landed)",
              not silicon, got="%s | %s" % (_h(v), state))

    if not silicon:
        rec.target_defer(
            "boot gate value is a known terminating-path word",
            prop=None, got=_h(v),
            expected=[_h(x) for x in _bootgate_values(rec)] or None,
            would_have_held=False,
            reason="the gate reads 0x00000000 and the ladder classifies that as a "
                   "NON-silicon state (%s). Whether zero is correct here depends on "
                   "whether QSPI flash is provisioned on this board, and NO TARGET "
                   "PROPERTY ESTABLISHES THAT — targets.py has no flash_provisioned "
                   "property, so there is nothing sound to assert against and the "
                   "value is recorded instead. Asserting bootgate_values here would "
                   "red a healthy unprovisioned board on the first test of the first "
                   "die." % state.split(" — ")[0])
        rec.note("BOOT GATE READS 0x00000000, and the ladder says this is NOT a "
                 "silicon fault. %s CPU0 is still held in reset, so unlike the "
                 "non-zero case the bus below IS quiescent — which makes the memory "
                 "readings in this run unusually trustworthy, not untrustworthy."
                 % state)
    else:
        rec.note("BOOT GATE READS 0x00000000 AND THE LADDER CONTRADICTS IT. %s "
                 "Everything below is VOID, which is correct here: the boot state is "
                 "genuinely unknown." % state)


# ===========================================================================
# A3 — HIO-120.  No bus access at all: ADP-internal operand registers.
# ===========================================================================
@test("HIO-120", tier=1, control=True, hazard=None,
      purpose="ADP mask/value operand registers M and V — write/readback with two "
              "complementary patterns. CONTROL: an unwritable M would make every "
              "P-based (masked-compare poll) test in Tier 4 compare against the wrong "
              "thing while still appearing to work. RED when: any readback differs from "
              "what was just written, or a reply comes back with the wrong command "
              "letter. 0x0F0F0F0F then 0xF0F0F0F0 catches stuck-at bits in BOTH "
              "directions; a single pattern would not. Issues NO bus transaction, so "
              "it is valid even on a die whose fabric is not decoding.")
def hio_120(adp, rec):
    seq = [("Mx0F0F0F0F", "M", 0x0F0F0F0F, "M"),
           ("Vxa5a5a5a5", "V", 0xA5A5A5A5, "V"),
           ("MxF0F0F0F0", "M", 0xF0F0F0F0, "M")]
    for setcmd, readcmd, want, letter in seq:
        w = adp.cmd(setcmd)
        rec.check("%s accepted" % setcmd, w.ok is True and w.letter == letter, got=w.raw)
        r = adp.cmd(readcmd)
        rec.check("%s reports back" % readcmd, r.ok is True and r.letter == letter,
                  got=r.raw)
        _eq(rec, "%s readback after %s" % (readcmd, setcmd), r.value, want)
        rec.record("adp_%s_readback_%08X" % (letter, want), r.value)

    # Leave the operands in a defined state for whatever runs next.
    adp.cmd("Mx00000000")
    adp.cmd("Vx00000000")
    m = adp.cmd("M")
    v = adp.cmd("V")
    rec.check("M restored to 0", m.value == 0, got=m.raw)
    rec.check("V restored to 0", v.value == 0, got=v.raw)
    rec.note("Plan §5.4: 'M IS writable' was measured on 2026-08-25 after two earlier "
             "readings said otherwise; both were client-sequencing artefacts. This test "
             "is the per-die re-proof of that. Parameters are written as 'x' + exactly "
             "8 hex digits (plan §1.2 size rule) — a short parameter would set an 8- or "
             "16-bit access size.")


# ===========================================================================
# B2 — HIO-103 / HIO-104.  ABORT GATE 4.
# ===========================================================================
_GATED_BY_CID = [
    "HIO-101", "HIO-102", "HIO-104", "HIO-105", "HIO-107", "HIO-108", "HIO-109",
    "HIO-110", "HIO-111", "HIO-112", "HIO-113", "HIO-114", "HIO-115", "HIO-116",
    "HIO-117", "HIO-118", "HIO-119", "HIO-121", "HIO-122", "HIO-123", "HIO-124",
    "HIO-125", "HIO-126", "HIO-127",
]


@test("HIO-103", tier=1, control=True, gates=_GATED_BY_CID, hazard=None,
      purpose="CoreSight component ID of reset_ctrl at 0x2A000FF0..FFC — the canonical "
              "0xB105F00D, assembled from four separate reads. THE CONTROL FOR THIS "
              "TIER, and ABORT GATE 4 in plan §3: a wrong CID means the fabric is not "
              "decoding and NOTHING below it is meaningful. RED when: any of the four "
              "words differs from 0x0D/0xF0/0x05/0xB1. The four-word pattern cannot be "
              "produced by a bus stuck at zero, stuck at ones, or returning the last "
              "data — which is exactly why it, and not a single-word magic, is the "
              "control. (HIO-106 is deliberately NOT in the gated list: it must run "
              "first, and its own [31:4]==0 structural check stands on its own.)")
def hio_103(adp, rec):
    want = [0x0000000D, 0x000000F0, 0x00000005, 0x000000B1]  # nanosoc_reset_ctrl.v:97-100
    got = []
    for i, w in enumerate(want):
        v = _rd(adp, rec, 0x2A000FF0 + 4 * i, "reset_ctrl CID%d" % i)
        got.append(v)
        _eq(rec, "reset_ctrl CID%d" % i, v, w)
    rec.record("reset_ctrl_cid_words", got)

    if all(g is not None for g in got):
        composed = ((got[3] & 0xFF) << 24) | ((got[2] & 0xFF) << 16) | \
                   ((got[1] & 0xFF) << 8) | (got[0] & 0xFF)
        rec.record("reset_ctrl_cid", composed)
        _eq(rec, "reset_ctrl CID composed", composed, 0xB105F00D)
        # Two-sided: the four words must not be identical. A constant-returning bus
        # would satisfy "reads succeeded" but never this.
        rec.check("the four CID words are not all identical (not a constant bus)",
                  len(set(got)) == 4, got=str([_h(g) for g in got]))


@test("HIO-104", tier=1, control=False, hazard=None,
      purpose="Peripheral ID of reset_ctrl, 0x2A000FC0..0x2A000FEC — a NON-UNIFORM "
              "value set: four zeros at 0xFC0-0xFCC, then PID4..PID7 = 04,00,00,00 and "
              "PID0..PID3 = 26,B8,1B,00. RED when: any of the twelve differs. This is "
              "the half of ABORT GATE 4 that HIO-103 cannot cover — the CID is four "
              "consecutive non-zero words, so it does not prove the read mux's "
              "reg_addr[5:2] decode; a mux that collapsed to a single ID ROM entry "
              "would pass HIO-103 and fail here, and the interleaved zeros mean a "
              "stuck-at-anything bus fails too. All values are RTL localparams "
              "(nanosoc_reset_ctrl.v:89-96,185), so they are R-class, not build-class.")
def hio_104(adp, rec):
    zeros = {}
    for off in (0xFC0, 0xFC4, 0xFC8, 0xFCC):
        v = _rd(adp, rec, 0x2A000000 + off, "reset_ctrl +0x%03X" % off)
        zeros[off] = v
        _eq(rec, "reset_ctrl +0x%03X (reads 0 by :185)" % off, v, 0x00000000)
    rec.record("reset_ctrl_fc0_fcc", [zeros[o] for o in (0xFC0, 0xFC4, 0xFC8, 0xFCC)])

    pid_hi = [0x04, 0x00, 0x00, 0x00]   # PID4..PID7 @ 0xFD0..0xFDC
    pid_lo = [0x26, 0xB8, 0x1B, 0x00]   # PID0..PID3 @ 0xFE0..0xFEC
    got_hi, got_lo = [], []
    for i, w in enumerate(pid_hi):
        v = _rd(adp, rec, 0x2A000FD0 + 4 * i, "reset_ctrl PID%d" % (4 + i))
        got_hi.append(v)
        _eq(rec, "reset_ctrl PID%d" % (4 + i), v, w)
    for i, w in enumerate(pid_lo):
        v = _rd(adp, rec, 0x2A000FE0 + 4 * i, "reset_ctrl PID%d" % i)
        got_lo.append(v)
        _eq(rec, "reset_ctrl PID%d" % i, v, w)
    rec.record("reset_ctrl_pid4_7", got_hi)
    rec.record("reset_ctrl_pid0_3", got_lo)
    rec.note("PID3 (+0xFEC) is asserted here, unlike in HIO-126: reset_ctrl's PID3 is a "
             "hard localparam, whereas the CMSDK peripherals pack a revision-dependent "
             "ECOREVNUM into theirs. If this one ever moves, it is a real RTL change.")


# ===========================================================================
# B3 — HIO-114.  ABORT GATE 5.  The census.
# ===========================================================================
#
# THREE-SIDED BY CONSTRUCTION.  Classes, exactly as plan §2.1 defines them:
#   D    must report OK (no '!')  AND carry meaningful (non-zero) data
#   Z    must report OK (no '!')  AND read exactly 0x00000000
#   E    must report '!'          (HRESP = ERROR on the completing beat)
#   D/Z  must report OK (no '!'); the value is not constrained
#
# `Reply.error` is the ONLY thing that separates E from Z. Both show 0x00000000 in
# the data field. Inferring an error from value==0 would collapse the two classes and
# destroy the entire point of the test.
#
_D, _Z, _DZ, _E = "D", "Z", "D/Z", "E"

_CENSUS = [
    # (address, class, what it is)
    (0x00000000, _D,  "eth remap window (bootrom or IMEM per the REMAP bit)"),
    (0x08000000, _D,  "eth bootrom, remap-independent alias"),
    (0x10000000, _DZ, "eth IMEM, remap-independent alias"),
    (0x18000000, _D,  "eth DMEM word 0"),
    (0x1FFFFFF0, _D,  "eth DMEM window top — boundary probe"),
    (0x20000FC8, _D,  "DMA-250 IIDR"),
    (0x21000FFC, _D,  "QSPI CIDR3"),
    (0x80000000, _D,  "CPU1 bootrom"),
    (0x90000000, _DZ, "CPU1 IMEM"),
    (0x98000000, _DZ, "CPU1 DMEM"),
    (0x23000000, _Z,  "IPC mailbox +0x00"),
    (0x23000034, _D,  "IPC mailbox PERIPH_ID"),
    (0x23000038, _E,  "IPC above the decoded aperture — PSLVERR "
                      "(ipc_mailbox_apb_regs.sv:295)"),
    (0x28000FE0, _D,  "cc_periph timer0 PID0"),
    (0x29000000, _DZ, "chip_core_remap_ctrl boot gate"),
    (0x2A000FF0, _D,  "reset_ctrl CID0"),
    (0x2B000004, _D,  "evt_route IRQ_ROUTE_CPU1"),
    (0x2C000000, _D,  "etc_capture ID"),
    (0x2C200004, _D,  "perf_probe INFO"),
    (0x2C300010, _D,  "bus_fault_monitor ID"),
    (0x2D000000, _DZ, "shared cross-core SRAM"),
    (0x2E030200, _D,  "TideLink LINK_CAPABILITIES"),
    (0x2E036000, _Z,  "TideLink reserved quadrant — prdata=0, pready=1, pslverr=0 "
                      "(tidelink_top.sv:845-853)"),
    (0x2E040010, _D,  "TideChart TC_DEVICE_CLASS"),
    (0x30000000, _E,  "eth scratch RX RAM — not routed to the eth SS from debug_m"),
    (0x38000000, _E,  "eth scratch TX RAM — not routed"),
    (0x40000000, _E,  "ETHMAC — STRUCTURALLY UNREACHABLE from this port"),
    (0x48000000, _E,  "eth CRC checker — not routed"),
    (0x50000000, _E,  "eth APB block (incl. the eth sys_remap_ctrl) — not routed"),
    (0x60000000, _E,  "eth perf probe — not routed"),
    (0x70000000, _E,  "unmapped"),
    (0xA0000000, _E,  "network-core debug window — matrix target 14, outside debug_m's "
                      "0x00003FFF visibility mask"),
    (0xB0000000, _E,  "chip-core debug window — matrix target 15, likewise"),
    (0xC0000000, _E,  "unmapped"),
    (0xF0000000, _E,  "unmapped"),
]

# --- D-class addresses where ZERO is a legitimate reading -------------------
#
# §2.1 classes these D (OK-with-DATA), but the plan's OWN text elsewhere says a zero
# there is correct and benign. Since HIO-114 is ABORT GATE 5 — "any address in the
# wrong outcome class -> STOP" — letting any of these red would abort the whole
# bring-up for a non-decode reason. The OK/'!' boundary, which is what the gate is
# actually about, is still asserted at every one of them; only the non-zero half is
# relaxed, and the observed value is recorded and noted either way.
#
_D_ZERO_OK = {
    0x00000000: "plan §5.5 MEASURED all-zeros here: with REMAP=1 this window is IMEM, "
                "and a cold IMEM is zeros. HIO-116 is what resolves the remap state.",
    0x18000000: "eth DMEM word 0 is the CPU0 image's .data[0]. On the ASIC image "
                "(stage0_bootrom) that initialiser is impure_data — ALL ZERO — so zero "
                "is the healthy reading there; on the FPGA image (smoke_remap) it is "
                "0x05F5E100. Either way the value belongs to HIO-107, not to a decode "
                "gate. NOTE the earlier reason given here — 'on a cold die CPU0 is held "
                "in reset' — is REFUTED: cc_rom releases CPU0 on every path.",
    0x1FFFFFF0: "top of the eth DMEM window, above the 0x3C00 initial MSP — never "
                "written by stage-0 and uninitialised on a cold die. Its purpose in "
                "the census is the window-boundary decode, which is still asserted.",
    0x20000FC8: "DMA-250 IIDR reads 0x00000000 when the block is POWER-GATED "
                "(pqen_apb = pwr_en & clk_en) — a documented silicon symptom, "
                "docs/DMA250_DESIGN_AND_WORKPLAN.md:69-70. That is a power finding, "
                "not a decode fault, and must not trip a decode abort gate. HIO-124 "
                "is the test that settles the DMA.",
    0x2E040010: "TC_DEVICE_CLASS is a PER-DIE STRAP, not a fixed constant — the two "
                "dies of a pair must read DIFFERENT classes. HIO-123 records it.",
}


@test("HIO-114", tier=1, control=True,
      gates=["HIO-101", "HIO-102", "HIO-105", "HIO-107", "HIO-108", "HIO-109",
             "HIO-110", "HIO-111", "HIO-112", "HIO-113", "HIO-115", "HIO-116",
             "HIO-117", "HIO-118", "HIO-119", "HIO-121", "HIO-122", "HIO-123",
             "HIO-124", "HIO-125", "HIO-126", "HIO-127"],
      hazard=None,
      purpose="Memory-map census / decode fingerprint over the 35 probes of plan §2.1. "
              "THE HIGHEST-INFORMATION TEST IN THIS TIER, and ABORT GATE 5. It is "
              "THREE-SIDED: it asserts OK-with-DATA at named addresses, ERROR ('!') at "
              "named addresses, AND OK-with-ZEROS at named addresses, so it cannot pass "
              "by measuring nothing the way a sweep that only checks 'no errors' can. "
              "RED when: any address lands in the wrong outcome class, i.e. a shifted "
              "or collapsed decode, or a region that stopped erroring, or a bus that "
              "returns zeros everywhere (which fails all 11 hard-D rows while passing "
              "the Z rows — the OK-with-zeros class exists precisely to make 'correctly "
              "zero' distinguishable from 'everything is zero'). It also asserts, as a "
              "meta-check, that all three classes were actually OBSERVED. The '!' flag "
              "is read from Reply.error only; value==0 is never used to infer an error, "
              "because Z and E both show 0x00000000.")
def hio_114(adp, rec):
    # ---- the exclusion list is part of the test (§2.1) ---------------------
    leaked = [a for a, _c, _d in _CENSUS if forbidden(a) is not None]
    rec.check("census contains no hazard-blocklisted address (HZ-1/2/3/6/7/8)",
              leaked == [], got=str([_h(a) for a in leaked]))
    rec.record("census_hazard_bands",
               ["%s [%s-%s]" % (hz, _h(lo), _h(hi)) for lo, hi, hz, _w in _HAZARD_BANDS])
    rec.record("census_hazard_words", [_h(a) for a in sorted(_HAZARD_WORDS)])

    observed = {}
    seen_data = seen_zero = seen_error = seen_noreply = 0

    for addr, cls, what in _CENSUS:
        r = _probe(adp, addr)

        if not r.ok:
            actual = "NO-REPLY"
            seen_noreply += 1
        elif r.error:
            actual = _E
            seen_error += 1
        elif r.value == 0:
            actual = _Z
            seen_zero += 1
        else:
            actual = _D
            seen_data += 1

        observed["%s" % _h(addr)] = {"expect": cls, "actual": actual,
                                     "value": r.value, "raw": r.raw, "what": what}

        tag = "%s %s" % (_h(addr), what)

        # ---- E: the '!' must be there. Reply.error, never value==0. --------
        if cls == _E:
            rec.check("%s -> ERROR '!'" % tag, r.ok is True and r.error is True,
                      got="%s (raw %s)" % (actual, r.raw))
            continue

        # ---- everything else must be a clean, well-formed OK ---------------
        rec.check("%s -> OK, no '!'" % tag, r.ok is True and r.error is False,
                  got="%s (raw %s)" % (actual, r.raw))
        if not (r.ok and not r.error):
            continue

        # ---- Z: must be EXACTLY zero. This is the anti-vacuity row. --------
        if cls == _Z:
            rec.check("%s -> OK-with-ZEROS (exactly 0x00000000)" % tag,
                      r.value == 0, got=_h(r.value))
        # ---- D: must carry data ------------------------------------------
        elif cls == _D:
            if addr in _D_ZERO_OK:
                if r.value == 0:
                    rec.note("%s classed D by §2.1 but read 0x00000000; NOT counted as "
                             "a decode fault. %s" % (tag, _D_ZERO_OK[addr]))
                rec.record("census_D_zero_tolerated_%s" % _h(addr), r.value)
            else:
                rec.check("%s -> OK-with-DATA (non-zero)" % tag,
                          r.value != 0, got=_h(r.value))
        # ---- D/Z: decode only; value recorded ------------------------------

    rec.record("census", observed)
    rec.record("census_class_counts", {"D": seen_data, "Z": seen_zero,
                                       "E": seen_error, "NO-REPLY": seen_noreply})

    # ---- the three-sidedness meta-check -----------------------------------
    rec.check("class OK-with-DATA was observed at least once", seen_data > 0,
              got=str(seen_data))
    rec.check("class ERROR ('!') was observed at least once", seen_error > 0,
              got=str(seen_error))
    rec.check("class OK-with-ZEROS was observed at least once", seen_zero > 0,
              got=str(seen_zero))
    rec.check("no probe went unanswered (NO-REPLY is a third, distinct outcome)",
              seen_noreply == 0, got=str(seen_noreply))

    rec.note("0x40000000 is expected to ERROR: the eth subsystem decodes the ETHMAC, "
             "but the multicore matrix never routes 0x4xxxxxxx to it, so the MAC and "
             "MDIO are structurally unreachable from ADP (plan §1.4, measured §5.1). "
             "An OK there would be a bigger finding than a '!'.")


# ===========================================================================
# B4 — HIO-116, HIO-101, HIO-102, HIO-107
# ===========================================================================
@test("HIO-116", tier=1, control=False, hazard=None,
      purpose="Eth REMAP state probe — compare the 2-word signature at 0x00000000 "
              "against the same signature at 0x08000000 (bootrom, always aliased) and "
              "at 0x10000000 (IMEM, always aliased). EXACTLY ONE must match. RED when: "
              "neither matches (the remap window is decoding to something that is "
              "neither) or BOTH match — which is what a bus returning a constant does, "
              "and is the reason the criterion is 'exactly one' rather than 'at least "
              "one'. Observation only: ADP cannot change this bit, because the eth "
              "sys_remap_ctrl lives at 0x50000000 in the unreachable eth APB block.")
def hio_116(adp, rec):
    def sig(base, name):
        return (_rd(adp, rec, base, "%s+0" % name), _rd(adp, rec, base + 4, "%s+4" % name))

    s_win = sig(0x00000000, "remap window")
    s_rom = sig(0x08000000, "eth bootrom")
    s_mem = sig(0x10000000, "eth IMEM")
    rec.record("remap_window_sig", list(s_win))
    rec.record("eth_bootrom_sig", list(s_rom))
    rec.record("eth_imem_sig", list(s_mem))

    if None in s_win + s_rom + s_mem:
        rec.check("all three remap probes read cleanly", False,
                  got="win=%s rom=%s imem=%s" % (s_win, s_rom, s_mem))
        return

    is_rom = (s_win == s_rom)
    is_mem = (s_win == s_mem)
    rec.check("exactly one of (window==bootrom, window==IMEM) holds",
              is_rom != is_mem,
              got="window==bootrom:%s window==IMEM:%s bootrom==IMEM:%s"
                  % (is_rom, is_mem, s_rom == s_mem))

    state = 0 if is_rom and not is_mem else (1 if is_mem and not is_rom else None)
    rec.record("eth_remap_bit", state)
    rec.note("REMAP=%s. Two words are compared, not one, because a single word is a "
             "much weaker signature when IMEM is cold (all zeros) — the plan's "
             "three-way comparison is preserved, only widened."
             % ("0 (address 0 is boot ROM)" if state == 0 else
                "1 (address 0 is IMEM)" if state == 1 else "INDETERMINATE"))


# CONFIRMED-RTL (promoted from B-class 2026-08-25 by an independent audit): these
# seven anchors match BOTH the instantiated FPGA RTL and the ASIC eth_rom_via macro
# image, so they are asserted, not merely recorded. They sit at words 0..15, which is
# ahead of word 55 where the two eth ROM images first diverge.
_ETH_ROM_ANCHORS = {
    0: 0x18003C00, 1: 0x08000189, 2: 0x080001CD, 3: 0x080001CF,
    11: 0x080001D7, 14: 0x080001DB, 15: 0x080001DD,
}


@test("HIO-101", tier=1, control=False, hazard=None,
      purpose="Eth boot ROM vector table, 16 words from 0x08000000, captured verbatim "
              "as the die's ROM fingerprint. RED when: any read errors; or the initial "
              "MSP at [0] is not 0x18003C00 (M-class, cross-validated against an "
              "independent backdoor); or the STRUCTURAL BACKSTOP fails — [0] must be "
              "word-aligned and inside 0x18000000-0x18003FFF (eth DMEM), and [1] (the "
              "reset vector) must have bit0=1 (Thumb) and lie inside "
              "0x08000000-0x080007FF (the 2 KB ROM). A garbage or unprogrammed ROM "
              "fails those regardless of which firmware image the die carries. The "
              "remaining six anchors are now CONFIRMED-RTL — an independent audit "
              "matched them against both the instantiated FPGA RTL and the ASIC "
              "eth_rom_via macro image — so they are ASSERTED, not merely recorded. "
              "They lie at words 0..15, ahead of word 55 where the FPGA and ASIC eth "
              "ROM images first diverge, which is why one set of anchors is valid on "
              "both targets even though 172 of the 320 words differ.")
def hio_101(adp, rec):
    words = []
    for i in range(16):
        words.append(_rd(adp, rec, 0x08000000 + 4 * i, "eth ROM[%d]" % i))
    rec.record("eth_bootrom_vectors", words)

    v0, v1 = words[0], words[1]
    _eq(rec, "eth ROM[0] initial MSP (M-class)", v0, 0x18003C00)

    if v0 is not None:
        rec.check("eth ROM[0] is word-aligned", (v0 & 3) == 0, got=_h(v0))
        rec.check("eth ROM[0] initial MSP lies in eth DMEM 0x18000000-0x18003FFF",
                  0x18000000 <= v0 <= 0x18003FFF, got=_h(v0))
    else:
        rec.check("eth ROM[0] readable", False, got="no value")

    if v1 is not None:
        rec.check("eth ROM[1] reset vector is Thumb (bit0 == 1)", (v1 & 1) == 1, got=_h(v1))
        rec.check("eth ROM[1] reset vector lies in the 2 KB ROM 0x08000000-0x080007FF",
                  0x08000000 <= v1 <= 0x080007FF, got=_h(v1))
    else:
        rec.check("eth ROM[1] readable", False, got="no value")

    for i in sorted(_ETH_ROM_ANCHORS):
        _eq(rec, "eth ROM[%d] (CONFIRMED-RTL, both targets)" % i,
            words[i], _ETH_ROM_ANCHORS[i])
    mismatch = {i: (_h(words[i]), _h(w)) for i, w in _ETH_ROM_ANCHORS.items()
                if words[i] != w}
    rec.record("eth_bootrom_anchor_mismatch", {str(k): v for k, v in mismatch.items()})
    if mismatch:
        rec.note("eth boot ROM differs at word indices %s (got, expected). These "
                 "anchors are CONFIRMED-RTL against both the FPGA RTL and the ASIC "
                 "eth_rom_via macro image, so a mismatch is a HARD RED for the die: "
                 "either the ROM macro is not the one that was taped out, or the vector "
                 "table is corrupt." % sorted(mismatch))
    else:
        rec.note("eth boot ROM matches all seven CONFIRMED-RTL anchors.")
    # Structural, recorded not asserted: NMI/HardFault vectors should also be Thumb
    # addresses inside the ROM, but a minimal image may legitimately leave them 0.
    rec.record("eth_bootrom_vec23_thumb_in_rom",
               [int(w is not None and (w & 1) == 1 and 0x08000000 <= w <= 0x080007FF)
                for w in words[2:4]])


@test("HIO-102", tier=1, control=False, hazard=None,
      purpose="CPU1 boot ROM, and DISCRIMINATING IT FROM CPU0's. The two ROMs' first "
              "0xE4 bytes are IDENTICAL (both vector tables start 0x18003C00, "
              "0x08000189, ...), so a test that compares only the vector table cannot "
              "tell them apart and would pass even if both ports were wired to the same "
              "ROM. Offset 0xE4 is the first differing word. RED when: 0x800000E4 and "
              "0x080000E4 read the SAME value (one ROM, or one port mirroring the "
              "other), or when the two ports do NOT agree at offset 0 — that second "
              "check is what stops 'they differ' from passing because one port returned "
              "garbage. Both halves must hold: same at 0x00, different at 0xE4.")
def hio_102(adp, rec):
    cpu0_v0 = _rd(adp, rec, 0x08000000, "eth ROM[0]")
    cpu1_v0 = _rd(adp, rec, 0x80000000, "CPU1 ROM[0]")
    cpu0_e4 = _rd(adp, rec, 0x080000E4, "eth ROM +0xE4")
    cpu1_e4 = _rd(adp, rec, 0x800000E4, "CPU1 ROM +0xE4")
    rec.record("eth_bootrom_word0", cpu0_v0)
    rec.record("cpu1_bootrom_word0", cpu1_v0)
    rec.record("eth_bootrom_e4", cpu0_e4)
    rec.record("cpu1_bootrom_e4", cpu1_e4)

    # Positive half: both ports are alive and are reading real, mirrored vector tables.
    _eq(rec, "eth ROM[0] (M-class)", cpu0_v0, 0x18003C00)
    _eq(rec, "CPU1 ROM[0] (M-class, plan §5.1)", cpu1_v0, 0x18003C00)

    # Negative half: they are NOT the same ROM.
    if cpu0_e4 is None or cpu1_e4 is None:
        rec.check("both +0xE4 words read cleanly", False,
                  got="eth=%s cpu1=%s" % (_h(cpu0_e4), _h(cpu1_e4)))
    else:
        rec.check("the two boot ROMs DIFFER at +0xE4 (not one ROM behind two ports)",
                  cpu0_e4 != cpu1_e4,
                  got="eth=%s cpu1=%s" % (_h(cpu0_e4), _h(cpu1_e4)))

    ref = {"eth": 0x0800048C, "cpu1": 0x08000678}   # B-class
    mism = {k: v for k, v in (("eth", cpu0_e4), ("cpu1", cpu1_e4)) if v != ref[k]}
    rec.record("bootrom_e4_build_mismatch",
               {k: (_h(v), _h(ref[k])) for k, v in mism.items()})
    if mism:
        rec.note("+0xE4 differs from the repo build artefact for %s. B-class, so not "
                 "asserted — see the HIO-101 note. The DIFFERENCE between the two ROMs "
                 "is the assertion here, and it is build-independent." % sorted(mism))


# ---------------------------------------------------------------------------
# RESIDUE THIS SUITE ITSELF LEAVES IN ETH DMEM WORD 0.
#
# HIO-107's witness lives at 0x18000000, and Tier 2's HIO-205 overwrites ALL 16 KB
# of eth DMEM including word 0 (its own `destroys=` string says so). So once Tier 2
# has run in this power cycle, word 0 holds OUR pattern, not the die's answer, and
# any conclusion drawn from it would be an accusation against silicon for something
# a sibling test did.
#
#
# WHERE THE VALUES COME FROM, AND WHY THAT CHANGED. They used to be a LOCAL COPY
# of tier2_3's literals, kept because CONTRACT.md is explicit -- "Nothing else is
# shared. One file per agent, no collisions." -- so tier1 may not import tier2_3.
# The copy was the problem, not the import ban: THE PATTERNS NOW LIVE IN harness,
# the one module every tier may legally import, and both sides read them from
# there. tier2_3's battery EXECUTES harness.MEM_FILL_PHASES; this table is built
# from the same declaration. It is a CONSUMER of those patterns. It does not own
# them, and it no longer restates them.
ETH_DMEM_BASE = 0x18000000
ETH_DMEM_WORD1 = ETH_DMEM_BASE + 4          # the corroboration word

#: The one entry that is genuinely THIS module's and not a battery terminal.
#: An F-fill of zero leaves it, but so does a cold die and a zero-init image, so
#: no phase owns it and nothing follows from it either way.
_ZERO_IS_AMBIGUOUS = ("an F-fill of zero -- but ALSO what a cold die and a "
                      "zero-init image read, so this one is ambiguous by nature "
                      "(see the note)")


def _build_dmem_residue():
    """{value at eth DMEM word 0: harness.MemFillPhase or None}.

    DERIVED from harness.MEM_FILL_PHASES -- the same declaration tier2_3's
    _ram_battery runs from -- plus the ambiguous zero, which is ours. A None
    phase means "recognised, but not a battery terminal".
    """
    tbl = dict(harness_module.mem_fill_terminals(ETH_DMEM_BASE))
    tbl.setdefault(0x00000000, None)
    return tbl


_DMEM_RESIDUE = _build_dmem_residue()


def _residue_why(value):
    """The prose for a recognised residue value; the PHASE supplies its own."""
    phase = _DMEM_RESIDUE.get(value)
    return _ZERO_IS_AMBIGUOUS if phase is None else phase.what


def _residue_drift(t23):
    """{issue: explanation} -- drift between this table and what the suite WRITES.

    Empty dict means no drift. PURE by design: it takes the tier2_3 module object
    (or None) and returns a plain dict, so harness --selftest can drive it BOTH
    WAYS with a stub and prove that it can still go red. A drift check that
    cannot fail is worth nothing, and this one became trivially satisfiable the
    moment the copy went away -- so what it checks had to change with it.

    WHAT IT NO LONGER CHECKS: "does tier1's PAT_A equal tier2_3's PAT_A". Both
    literals are gone; both modules read harness. Asserting that agreement now
    would be asserting harness == harness.

    WHAT IT CHECKS INSTEAD -- the three ways a single source can still be
    abandoned without anyone noticing:

      (A) THIS TABLE still covers every phase harness declares, and excuses
          NOTHING ELSE. Needs no sibling module, so it runs even when tier2_3 is
          not loaded. A dropped entry stops excusing a pattern we do write (and
          so accuses the die of our residue); a surplus entry excuses a value
          nothing writes (and so writes off a real fault).
      (B) tier2_3 still EXECUTES every declared phase, and the value each one
          leaves at eth DMEM word 0 is one this table recognises. Compared BY
          VALUE, not by identity, so it holds across module reloads.
      (C) tier2_3's PAT_A/PAT_B are still the shared values -- the direct
          successor of the old check. This is what fires if someone re-literalises
          a pattern in the writing module, i.e. if the problem were moved rather
          than solved.
    """
    drift = {}

    # ---- (A) this table against the shared declaration ----------------------
    declared = harness_module.mem_fill_terminals(ETH_DMEM_BASE)
    for phase in harness_module.MEM_FILL_PHASES:
        v = phase.terminal_at(ETH_DMEM_BASE)
        if v not in _DMEM_RESIDUE:
            drift["table_missing_%s" % phase.name] = (
                "harness declares phase %s leaves %s at eth DMEM word 0, and this "
                "table does not recognise it -- HIO-107 would report our own "
                "residue as a die fault" % (phase.name, _h(v)))
    for v in _DMEM_RESIDUE:
        if v not in declared and v != 0x00000000:
            drift["table_excuses_%s" % _h(v)] = (
                "this table excuses %s, which no declared phase writes -- HIO-107 "
                "would write off a genuine die value as our residue" % _h(v))

    # ---- (B)/(C) the WRITING module, when the harness has it ----------------
    if t23 is None:
        return drift

    plan = getattr(t23, "battery_plan", None)
    if plan is None:
        drift["battery_plan"] = ("tier2_3 no longer publishes battery_plan(), so what "
                                 "the battery actually writes cannot be cross-checked")
    else:
        for phase, runnable in plan():
            if not runnable:
                drift["phase_not_written_%s" % phase.name] = (
                    "harness declares phase %s but tier2_3 has no runner for it: this "
                    "table would excuse a value nothing ever writes" % phase.name)
            v = phase.terminal_at(ETH_DMEM_BASE)
            if v not in _DMEM_RESIDUE:
                drift["written_but_unrecognised_%s" % phase.name] = (
                    "tier2_3's battery leaves %s at eth DMEM word 0 and this table "
                    "does not recognise it" % _h(v))

    for name, shared in (("PAT_A", harness_module.FILL_PAT_A),
                         ("PAT_B", harness_module.FILL_PAT_B)):
        theirs = getattr(t23, name, None)
        if theirs is None:
            drift[name] = "absent from tier2_3 (renamed?)"
        elif theirs != shared:
            drift[name] = ("tier2_3 says %s, harness says %s -- the writing module has "
                           "stopped reading the shared declaration"
                           % (_h(theirs), _h(shared)))
    return drift


def _residue_drift_check(rec, t23=None):
    """Assert that the residue table still matches what this suite WRITES.

    tier2_3 is reached through harness.LOADED_MODULES -- harness state, not a
    sibling import -- so this creates no dependency the CONTRACT forbids. When it
    is absent, arm (A) still runs and is still assertable; the write-side arms
    are recorded as not run rather than silently passing.

    THIS IS A REAL CHECK, not a record. A drifted table makes HIO-107's residue
    verdict unsound in one of two directions, and both are wrong verdicts about
    silicon, so the test must not report PASS on top of it.
    """
    mods = getattr(harness_module, "LOADED_MODULES", None) if harness_module else None
    if t23 is None and isinstance(mods, dict):
        t23 = mods.get("tier2_3")

    drift = _residue_drift(t23)
    rec.record("residue_xcheck", drift or "agrees with harness.MEM_FILL_PHASES")
    rec.record("residue_xcheck_write_side_verified", int(t23 is not None))
    rec.check("the HIO-107 residue table still matches the fill patterns this suite "
              "WRITES (harness.MEM_FILL_PHASES; and tier2_3's battery_plan() when the "
              "runner loaded it). This table is what stops HIO-107 blaming CPU0 for a "
              "pattern Tier 2 wrote, so a stale entry either EXCUSES A REAL FAULT or "
              "ACCUSES THE DIE OF OUR OWN RESIDUE",
              not drift,
              got=(drift or ("no drift"
                             + ("" if t23 is not None
                                else "; tier2_3 not loaded, so only the "
                                     "table-vs-harness arm ran"))))
    if drift:
        rec.note("RESIDUE TABLE HAS DRIFTED: %s. Reconcile it before reading anything "
                 "into eth DMEM word 0 -- the classification below is unsound until "
                 "you do." % drift)


def _classify_witness(dmem0, neighbour):
    """(kind, why, corroborated) for a non-marker eth DMEM word 0.

    kind is 'residue' (a pattern this suite writes) or 'unexplained' (the genuine
    finding). `corroborated` says whether the NEIGHBOURING word agrees with the same
    fill -- a lone word holding PAT_B with an untouched neighbour is not a fill.
    """
    if dmem0 not in _DMEM_RESIDUE:
        return "unexplained", None, None
    phase = _DMEM_RESIDUE[dmem0]
    why = _residue_why(dmem0)
    if neighbour is None:
        return "residue", why, None
    # ASK THE PHASE what it would have left in the NEIGHBOURING word. For a
    # uniform fill that is the same pattern; for address-uniqueness each word
    # holds its OWN address, so it is ETH_DMEM_WORD1. That special case used to be
    # a literal 0x18000004 here -- a second place the address-uniqueness rule was
    # written down, and a second place it could drift.
    expect = dmem0 if phase is None else phase.terminal_at(ETH_DMEM_WORD1)
    return "residue", why, (neighbour == expect)


# ---------------------------------------------------------------------------
# Which program the die's eth boot ROM carries. THE TWO TARGETS DIFFER.
#
#   "smoke_remap"     FPGA. Links SystemCoreClock; its .data[0] initialiser is
#                     0x05F5E100 (= 100000000 = the generated SYS_CLK_FREQ_HZ), so
#                     eth DMEM word 0 IS a positive witness that CPU0 executed.
#   "stage0_bootrom"  ASIC. A DIFFERENT PROGRAM -- 172 of 320 words differ, first
#                     difference at word 55. Its .data[0] is impure_data (all-zero
#                     init) and it does not link SystemCoreClock at all, so
#                     0x05F5E100 never appears and NO witness exists in this word.
#   None              undeclared. Only the target-independent half is asserted.
#
# The divergence is known and formally waived upstream: eth.json carries an
# allow_sim_divergence allowlist entry and is the single WARN in a 12-pass/1-warn
# result. cc_rom has no waiver and passes 13/0, i.e. CPU1's ROM is identical on both
# targets -- which is why HIO-106's expectation is target-independent and this one is
# not. Set this once per rig and HIO-107 recovers its full strength.
ETH_ROM_IMAGE = None

CPU0_RAN_MARKER = 0x05F5E100        # SystemCoreClock initialiser, FPGA image only


@test("HIO-107", tier=1, control=False, hazard=None, needs=["HIO-106"],
      purpose="Boot-gate <-> CPU0-alive consistency. The half that is TRUE ON BOTH "
              "TARGETS is asserted unconditionally; the half that is FPGA-only is "
              "asserted only when the eth ROM image is declared. "
              "TARGET-INDEPENDENT AND ALWAYS ASSERTED: (a) both gate reads have "
              "[31:4] == 0; (b) NO GATE BIT IS EVER CLEARED between the two reads that "
              "bracket the DMEM probe — remap_q is write-1-set and clears only on "
              "PORESETn (chip_core_remap_ctrl.v:115,117), so a bit going away means "
              "this is not the live gate or the die reset mid-test; (c) THE ONE-WAY "
              "IMPLICATION 'marker present => gate open': if eth DMEM word 0 reads "
              "0x05F5E100 then some CPU0 image definitely executed a scatter-load, so "
              "bit2 MUST be set. That direction can never be wrong on either target, "
              "and it reds on the genuine contradiction of CPU0 having executed while "
              "the gate says it was never released. "
              "ORDERING DEPENDENCY, WHICH IS A REAL CONSTRAINT ON THE BRING-UP "
              "SEQUENCE: this test's POSITIVE half is only meaningful BEFORE TIER 2 "
              "HAS RUN IN THIS POWER CYCLE. Its witness is eth DMEM word 0, and "
              "HIO-205 overwrites all 16 KB of eth DMEM including word 0 — its own "
              "destroys= string says so and tells you to capture HIO-107 first. After "
              "Tier 2 the word holds one of this suite's own fill patterns, so the "
              "check reports INCONCLUSIVE with witness_destroyed_by naming the "
              "pattern, and never a red against CPU0: a test must not draw a "
              "conclusion about the DUT from a value it knows a sibling wrote. Only a "
              "POWER CYCLE restores it. A value that is neither the marker nor a known "
              "pattern is still a genuine red. "
              "WHY THE CONVERSE IS NOT ASSERTED BY DEFAULT: the old test read "
              "'bit2 == 1 AND word 0 != 0x05F5E100' as 'released but never executed'. "
              "On ASIC that combination is the HEALTHY state, because the ASIC eth ROM "
              "is a different program (stage0_bootrom, not the FPGA's smoke_remap; 172 "
              "of 320 words differ, first at word 55) whose .data[0] is impure_data — "
              "all-zero init — and which does not link SystemCoreClock at all. So the "
              "0x05F5E100 anchor went RED on a healthy ASIC die when the gate was open, "
              "and VACUOUSLY GREEN when it was shut: the false-red and the false-green "
              "in one test. Since HIO-106 now establishes that cc_rom opens the gate on "
              "EVERY path, 'gate open' carries no information about CPU0 on its own and "
              "the converse is only sound where a witness exists. Declaring "
              "ETH_ROM_IMAGE = 'smoke_remap' restores it in full. "
              "ON ASIC THE WITNESS IS STRUCTURALLY ABSENT, the cross-check is "
              "recorded as NOT EXECUTABLE (target_defer, never a pass and never a "
              "red), and only the two target-independent structural checks are "
              "asserted. The replacement and its one-shot precondition are specified "
              "in ASIC_FIRST_SILICON_HOSTIO_PROCEDURE.md §3.7.4/§3.5.1; it is not "
              "implemented here because it depends on a Phase-B measurement of "
              "uninitialised SRAM that has not been taken.")
def hio_107(adp, rec):
    rec.record("eth_rom_image_declared", ETH_ROM_IMAGE)

    gate_a = _rd(adp, rec, 0x29000000, "boot gate (before)")
    dmem0 = _rd(adp, rec, 0x18000000, "eth DMEM word 0")
    gate_b = _rd(adp, rec, 0x29000000, "boot gate (after)")
    rec.record("boot_gate_word_reread", gate_a)
    rec.record("boot_gate_word_after_dmem", gate_b)
    rec.record("eth_dmem_word0", dmem0)

    if gate_a is None or gate_b is None or dmem0 is None:
        rec.check("all three observations available", False,
                  got="gate_a=%s dmem0=%s gate_b=%s"
                      % (_h(gate_a), _h(dmem0), _h(gate_b)))
        return

    # (a) structural, both targets
    for label, g in (("before", gate_a), ("after", gate_b)):
        rec.check("boot gate (%s) [31:4] == 0" % label, _field(g, 31, 4) == 0, got=_h(g))

    # (b) write-1-set: bits can appear, never vanish. Both targets.
    rec.check("no boot-gate bit was CLEARED across the DMEM read "
              "(remap_q is write-1-set, clears only on PORESETn)",
              (gate_a & ~gate_b) == 0,
              got="before=%s after=%s" % (_h(gate_a), _h(gate_b)))
    if gate_b != gate_a:
        rec.note("The boot gate CHANGED during this test: %s -> %s. Bits only ever set, "
                 "so this is CPU1 still executing cc_rom while the suite ran. Not a "
                 "failure, but it means the die was still booting — re-read HIO-106 and "
                 "prefer the later value for the record."
                 % (_h(gate_a), _h(gate_b)))

    released = bool(gate_b & (1 << 2))
    witness = (dmem0 == CPU0_RAN_MARKER)
    rec.record("cpu0_released", int(released))
    rec.record("cpu0_stage0_witness_present", int(witness))

    # (c) the one-way implication -- sound on BOTH targets.
    rec.check("witness present => boot gate bit2 is set "
              "(CPU0 cannot have scatter-loaded while still held in reset)",
              (not witness) or released,
              got="witness=%s gate=%s" % (witness, _h(gate_b)))

    # ---- the FPGA-only converse, gated on a declared image --------------------
    if ETH_ROM_IMAGE == "smoke_remap":
        _residue_drift_check(rec)

        if witness or not released:
            # Either the witness is there, or the gate is shut and the converse says
            # nothing. Nothing to excuse; assert as before.
            rec.record("hio107_crosscheck_strength", "full (bidirectional)")
            rec.record("hio107_crosscheck_executable", 1)
            rec.check("FPGA image declared: gate bit2 == 1 => eth DMEM word 0 == "
                      "0x05F5E100 (SystemCoreClock initialiser)",
                      (not released) or witness, got=_h(dmem0))
            return

        # Gate open, witness absent. BEFORE blaming CPU0, ask whether this suite
        # wrote the value we are looking at.
        neighbour = _rd(adp, rec, ETH_DMEM_WORD1, "eth DMEM word 1 (residue corroboration)")
        rec.record("eth_dmem_word1", neighbour)
        kind, why, corroborated = _classify_witness(dmem0, neighbour)
        rec.record("witness_classification", kind)

        if kind == "unexplained":
            rec.record("hio107_crosscheck_strength", "full (bidirectional)")
            rec.record("hio107_crosscheck_executable", 1)
            rec.check("FPGA image declared: gate bit2 == 1 => eth DMEM word 0 == "
                      "0x05F5E100 (SystemCoreClock initialiser)",
                      False, got=_h(dmem0))
            rec.note("INCONSISTENT on a declared smoke_remap die, and NOT explained by "
                     "this suite's own residue: the gate is open but word 0 is %s, "
                     "which is neither the SystemCoreClock initialiser nor any pattern "
                     "Tier 2 writes (%s). CPU0 was released and did not execute its "
                     "scatter-load. Corroborate with HIO-105's "
                     "reset_info_cpu0_lockupreset_bit2 — CPU0 released into blank IMEM "
                     "faults immediately, and that latches the lockup cause if "
                     "lockupreseten is on."
                     % (_h(dmem0), ", ".join(_h(k) for k in sorted(_DMEM_RESIDUE))))
            return

        # ---- our own residue. INCONCLUSIVE, never a red against the die. ----
        rec.record("hio107_crosscheck_strength", "NOT EXERCISED — witness destroyed")
        rec.record("hio107_crosscheck_executable", 0)
        rec.record("witness_destroyed_by", "%s (%s)" % (_h(dmem0), why))
        rec.record("witness_residue_corroborated",
                   None if corroborated is None else int(corroborated))

        ambiguous = (dmem0 == 0x00000000)
        rec.target_defer(
            "FPGA image declared: gate bit2 == 1 => eth DMEM word 0 == 0x05F5E100",
            prop="eth_dmem_word0", got=_h(dmem0), expected=_h(CPU0_RAN_MARKER),
            would_have_held=None,
            reason="WITNESS DESTROYED BY A PRIOR TIER 2 RUN — power-cycle the die to "
                   "restore it. Word 0 holds %s: %s. This is not evidence about CPU0, "
                   "it is this suite's own residue, so no conclusion is drawn from "
                   "it%s." % (_h(dmem0), why,
                              " (and note this particular value is ambiguous: it is "
                              "also what a cold die reads)" if ambiguous else ""))

        if ambiguous:
            rec.note("eth DMEM word 0 reads 0x00000000 with the gate OPEN. This is "
                     "GENUINELY AMBIGUOUS and is deliberately not called either way: "
                     "zero is what an F-fill of zero leaves, AND what a cold die reads "
                     "if CPU0 never ran. One word cannot separate them. To resolve: "
                     "POWER-CYCLE and run HIO-107 BEFORE Tier 2 — then a zero here is "
                     "real evidence that CPU0 did not scatter-load.")
        else:
            rec.note("WITNESS DESTROYED BY A PRIOR TIER 2 RUN, not by the die. eth "
                     "DMEM word 0 holds %s — %s. HIO-205's own destroys= string names "
                     "word 0 explicitly and tells you to capture HIO-107 first. The "
                     "neighbouring word %s the same fill, so the residue reading is %s. "
                     "NOTHING IS CONCLUDED ABOUT CPU0 HERE: power-cycle the die and run "
                     "HIO-107 before Tier 2 to exercise the positive half."
                     % (_h(dmem0), why,
                        "confirms" if corroborated else "does NOT confirm",
                        "solid" if corroborated
                        else "WEAKER THAN IT LOOKS — a lone word matching a test "
                             "pattern without the fill around it is worth a second "
                             "look before dismissing it"))
    elif ETH_ROM_IMAGE == "stage0_bootrom":
        rec.record("hio107_crosscheck_strength", "NOT EXECUTABLE on this image")
        rec.record("hio107_crosscheck_executable", 0)
        rec.target_defer("boot gate <-> CPU0-alive cross-check",
                         prop="eth_dmem_word0", got=_h(dmem0),
                         would_have_held=None,
                         reason="STRUCTURALLY BROKEN on this image and deliberately "
                                "not asserted in either direction. See "
                                "docs/bringup/ASIC_FIRST_SILICON_HOSTIO_PROCEDURE.md "
                                "§3.7.4: 0x18000000 reads 0x00000000 whether or not "
                                "CPU0 ran, because stage0_bootrom's .data[0] is zero "
                                "and the image never links SystemCoreClock. A test "
                                "asserting either way would report 'CPU0 never ran' on "
                                "a die where CPU0 ran perfectly.")
        rec.note("ASIC image declared (stage0_bootrom): THIS CROSS-CHECK IS NOT "
                 "EXECUTABLE, and it is recorded as such rather than passed or failed. "
                 "eth DMEM word 0 = %s carries NO information about CPU0 on this "
                 "image: .data[0] is impure_data, an all-zero initialiser, and "
                 "SystemCoreClock is never linked, so 0x05F5E100 is absent by "
                 "construction. Only the target-independent structural checks above "
                 "(register width, and the write-1-set monotonicity of the gate) were "
                 "asserted. THE REPLACEMENT, and its precondition, are in "
                 "ASIC_FIRST_SILICON_HOSTIO_PROCEDURE.md §3.7.4: compare the "
                 "initialised region 0x18000000..0x18000104 against an UNINITIALISED "
                 "region of the same RAM (0x18000200), with 0x18000084 (eth g_tbl, "
                 "0xFFFFFFFF on blank flash) as independent corroboration. It is valid "
                 "ONLY IF §3.5.1's one-shot Phase-B measurement shows uninitialised "
                 "TSMC rf_* SRAM is not all-zero — that measurement is destroyed by "
                 "Phase C and cannot be retaken without a power cycle, so take it "
                 "before anything writes shared SRAM. If it comes back all zeros, this "
                 "test is NOT EXECUTABLE on this die permanently." % _h(dmem0))
    else:
        rec.record("hio107_crosscheck_strength", "one-way (image undeclared)")
        rec.record("hio107_crosscheck_executable", 0)
        rec.note("ETH_ROM_IMAGE is undeclared, so only the target-independent half ran. "
                 "eth DMEM word 0 = %s, gate = %s. Set tier1.ETH_ROM_IMAGE to "
                 "'smoke_remap' (FPGA) to restore the full bidirectional cross-check, "
                 "or to 'stage0_bootrom' (ASIC) to record explicitly that no witness "
                 "exists on this image. It is left undeclared by default because "
                 "guessing the target from a ROM word would itself be the bug this "
                 "test just had." % (_h(dmem0), _h(gate_b)))


# ===========================================================================
# B5 — the rest of the identity set
# ===========================================================================
@test("HIO-105", tier=1, control=False, hazard=None,
      purpose="reset_ctrl reset values, 0x2A000000 +0x00..+0x20. Seven words that must "
              "be ZERO (REMAP_CTRL and PMU_CTRL are RAZ, SYS_CTRL and +0x0C and "
              "+0x18/+0x1C are 0, SW_RESET at +0x20 is write-only and reads 0), plus "
              "the two RESET_INFO cause registers, which are RECORDED, NOT ASSERTED — "
              "see below. RED when: any of the seven is non-zero; or either RESET_INFO "
              "has a bit set above [3:0], which is impossible because the read mux is "
              "{{28{1'b0}}, reg_resetinfo_cpuN} (nanosoc_reset_ctrl.v:165-166); or "
              "RESET_INFO_CPU0 bit[1] is set, which is impossible because CPU0 has no "
              "WDOGRESETREQ source and the RTL ties it off — "
              "'assign nxt_resetinfo_cpu0[1] = 1'b0' (nanosoc_reset_ctrl.v:318). "
              "WHY RESET_INFO IS NO LONGER ASSERTED NON-ZERO (measured 0x00000000 on "
              "the FPGA die, 2026-08-25; the plan predicted non-zero and the plan is "
              "WRONG): the capture flop is async-cleared BY the power-on reset — "
              "'always @(posedge FCLK or negedge PORESETn) if (~PORESETn) "
              "reg_resetinfo_cpu0 <= 4'b0000' (nanosoc_reset_ctrl.v:326-331, and "
              ":343-345 for CPU1) — so a power-on leaves it ZERO, it does not populate "
              "it. Every set-source is a LATER event that has not happened on a cold "
              "die: bit[0] cpu0_sysresetreq, bit[2] cpu0_lockup, bit[3] EXTRESET via "
              "the ext_sysresetreq INPUT (:320,:338). And on this FPGA build that input "
              "is hardwired off — 'wire ext_sysresetreq = 1'b0;  // no external "
              "system-reset source on this board' "
              "(pynq/vivado_ip/nanosoc_multicore_vivado_wrapper.v:182, wired at :231 "
              "into .sys_sysresetreq, passed to .ext_sysresetreq at "
              "nanosoc_multicore_soc.sv:1386) — so EXTRESET can NEVER set on this "
              "board. Zero is the RTL-correct cold-die reading, and asserting non-zero "
              "would red every good die. HONEST ACCOUNTING OF WHAT THIS COSTS: "
              "RESET_INFO was this test's stuck-at-zero half, and relaxing it leaves "
              "HIO-105 one-sided (it now fails on a bus stuck at ONES only). The "
              "stuck-at-zero half for this same block is HIO-104, whose PID words "
              "0x26/0xB8/0x1B/0x04 are non-zero; for the tier it is HIO-125 "
              "(IRQ_ROUTE_CPU1 = 0x0F), HIO-127 (all-ones) and the census D rows. "
              "ASIC NOTE: ext_sysresetreq may be bonded to a real pad on the ASIC, so "
              "EXTRESET could legitimately read SET there. Either way it is recorded, "
              "not asserted; do not inherit a non-zero expectation for the ASIC run.")
def hio_105(adp, rec):
    offs = [0x00, 0x04, 0x08, 0x0C, 0x10, 0x14, 0x18, 0x1C, 0x20]
    names = ["REMAP_CTRL", "PMU_CTRL", "SYS_CTRL", "rsvd_0C", "RESET_INFO_CPU0",
             "RESET_INFO_CPU1", "rsvd_18", "rsvd_1C", "SW_RESET"]
    vals = {}
    for off, name in zip(offs, names):
        vals[name] = _rd(adp, rec, 0x2A000000 + off, "reset_ctrl %s" % name)
    rec.record("reset_ctrl_block", {n: vals[n] for n in names})

    for name in ["REMAP_CTRL", "PMU_CTRL", "SYS_CTRL", "rsvd_0C",
                 "rsvd_18", "rsvd_1C", "SW_RESET"]:
        _eq(rec, "reset_ctrl %s" % name, vals[name], 0x00000000)

    # RESET_INFO: RECORDED, not asserted. The only assertions are structural ones the
    # RTL guarantees unconditionally -- see purpose for the file:line evidence.
    for name in ("RESET_INFO_CPU0", "RESET_INFO_CPU1"):
        v = vals[name]
        if v is None:
            continue
        rec.check("reset_ctrl %s [31:4] == 0 (read mux zero-extends a 4-bit flop)"
                  % name, _field(v, 31, 4) == 0, got=_h(v))
        low = name.lower()
        rec.record("%s_cause" % low, _field(v, 3, 0))
        rec.record("%s_sysresetreq_bit0" % low, _field(v, 0, 0))
        rec.record("%s_lockupreset_bit2" % low, _field(v, 2, 2))
        rec.record("%s_extreset_bit3" % low, _field(v, 3, 3))

    v0 = vals["RESET_INFO_CPU0"]
    if v0 is not None:
        # nanosoc_reset_ctrl.v:318 -- assign nxt_resetinfo_cpu0[1] = 1'b0;
        rec.check("RESET_INFO_CPU0 bit[1] == 0 (no WDOGRESETREQ source on CPU0; "
                  "the RTL ties this bit off)", _field(v0, 1, 1) == 0, got=_h(v0))
    v1 = vals["RESET_INFO_CPU1"]
    if v1 is not None:
        rec.record("reset_info_cpu1_wdogresetreq_bit1", _field(v1, 1, 1))

    both_zero = (v0 == 0 and v1 == 0)
    rec.record("reset_info_both_zero", int(bool(both_zero)))
    if both_zero:
        rec.note("Both RESET_INFO words read 0x00000000. This is the EXPECTED cold-die "
                 "state, not a defect: PORESETn async-clears the capture flop "
                 "(nanosoc_reset_ctrl.v:326-331,343-345), so a power-on clears the "
                 "record rather than writing to it, and on this FPGA build "
                 "ext_sysresetreq is tied 1'b0 (vivado_ip wrapper :182) so EXTRESET "
                 "can never set. MEANING OF A NON-ZERO VALUE, for whoever reads the "
                 "record: bit[0] the core asked for a system reset (SYSRESETREQ, i.e. "
                 "software called NVIC_SystemReset); bit[1] CPU1 only, the watchdog "
                 "fired; bit[2] the core LOCKED UP and lockupreseten was on — an "
                 "unhandled fault at the highest priority, always worth investigating; "
                 "bit[3] an external reset arrived on the ext_sysresetreq pin. These "
                 "are W1C, so a non-zero value is a latched history, not a live state. "
                 "HIO-503 (CPU0 relaunch) is expected to make bit[0] appear — that is "
                 "the positive control for this register and it belongs in Tier 5, "
                 "because nothing in a read-only tier can make a cause bit set.")
    else:
        rec.note("RESET_INFO is non-zero (CPU0=%s CPU1=%s): a reset cause IS latched. "
                 "Not a failure — decode the bits from the record. On this FPGA build "
                 "EXTRESET (bit 3) should be unreachable, so a set bit[3] here would "
                 "itself be a finding worth chasing to the board wiring."
                 % (_h(v0), _h(v1)))


@test("HIO-108", tier=1, control=False, hazard=None,
      purpose="Bus-fault-monitor ID at 0x2C300010 — ASCII magic 'BFM1' = 0x42464D31, "
              "confirmed against the instantiated RTL "
              "(src/rtl/wrappers/bus_fault_monitor.v:282, localparam ID_CONST), so it "
              "is R-class here, not the B-class the plan hedged on. RED when: the word "
              "is not that magic, or its four bytes are not printable ASCII (the "
              "structural backstop — a stuck bus, a floating read mux or a "
              "mis-decoded region cannot produce four printable bytes). Also proves "
              "ctrl_dbg_group's HADDR[21:20]==3 sub-decode arm.")
def hio_108(adp, rec):
    v = _rd(adp, rec, 0x2C300010, "bus_fault_monitor ID")
    rec.record("bus_fault_monitor_id", v)
    if v is None:
        return
    rec.record("bus_fault_monitor_id_ascii", _ascii(v))
    rec.check("bus_fault_monitor ID is four printable ASCII bytes",
              _printable(v), got="%s '%s'" % (_h(v), _ascii(v)))
    _eq(rec, "bus_fault_monitor ID ('BFM1')", v, 0x42464D31)


@test("HIO-109", tier=1, control=False, hazard=None,
      purpose="Event-timestamp-capture ID at 0x2C000000 — ASCII magic 'ETC1' = "
              "0x45544331, confirmed against the instantiated RTL "
              "(src/rtl/wrappers/etc_capture.v:104, localparam ID_MAGIC). RED when: the "
              "word is not that magic, or its bytes are not printable ASCII. Proves "
              "ctrl_dbg_group sub-decode arm 0, which HIO-108 (arm 3) does not.")
def hio_109(adp, rec):
    v = _rd(adp, rec, 0x2C000000, "etc_capture ID")
    rec.record("etc_capture_id", v)
    if v is None:
        return
    rec.record("etc_capture_id_ascii", _ascii(v))
    rec.check("etc_capture ID is four printable ASCII bytes",
              _printable(v), got="%s '%s'" % (_h(v), _ascii(v)))
    _eq(rec, "etc_capture ID ('ETC1')", v, 0x45544331)


@test("HIO-110", tier=1, control=False, hazard=None,
      purpose="Perf-probe ID and INFO at 0x2C200000/+0x04. Asserts ID == 0x50524631 "
              "('PRF1', CONFIRMED-RTL) and INFO == 4 (the probe count), plus the "
              "structural backstop that the top three bytes are ASCII 'PRF', which no "
              "stuck or mis-decoded bus produces. RED when: any of those fails, or "
              "either read errors. THE EARLIER 'DISPUTE' WAS NOT ONE — 0x50524631 and "
              "0x50524601 belong to two different modules and 0x2C200000 is "
              "unambiguously the PRF1 one, so the constant is asserted rather than "
              "recorded; see the note for the file:line chain. INFO is the half a "
              "magic-only check would miss: a mis-parameterised instance changes the "
              "probe count while keeping the ID.")
def hio_110(adp, rec):
    vid = _rd(adp, rec, 0x2C200000, "perf_probe ID")
    info = _rd(adp, rec, 0x2C200004, "perf_probe INFO")
    rec.record("perf_probe_id", vid)
    rec.record("perf_probe_info", info)

    if vid is not None:
        rec.record("perf_probe_id_ascii", _ascii(vid))
        # Marker discipline applied to an ASCII magic: assert the part both artefacts
        # agree on ([23:0] = 'P','R','F' little-end-first) before reading anything else.
        rec.check("perf_probe ID top three bytes are ASCII 'PRF' (undisputed half)",
                  _field(vid, 31, 8) == 0x505246,
                  got="%s '%s'" % (_h(vid), _ascii(vid)))
        _eq(rec, "perf_probe ID ('PRF1', CONFIRMED-RTL)", vid, 0x50524631)
        rec.note("THE DISPUTE IS RESOLVED and this constant is now asserted. It was "
                 "never a real disagreement: 0x50524631 and 0x50524601 belong to two "
                 "DIFFERENT modules, and 0x2C200000 is unambiguously the PRF1 one. The "
                 "block instantiated at this address is ctrl_ahb_perf_probe_regs "
                 "(ctrl_dbg_group.v:244, leaf 2), whose "
                 "src/rtl/perf_probe/ctrl_ahb_perf_probe_regs.v:72 reads "
                 "'localparam [31:0] ID_VALUE = 32'h50524631'; "
                 "firmware/include/perf_probe.h:44 (0x50524601) describes the other "
                 "module and never applied here. The 'PRF' prefix check above is kept "
                 "as the structural backstop, so a wrong low byte is still diagnosable "
                 "as a version/module confusion rather than a dead bus.")

    rec.check("perf_probe INFO == 4 (probe count; RTL N_PROBE via OFF_INFO)",
              info == 0x00000004, got=_h(info))


@test("HIO-111", tier=1, control=False, hazard=None,
      purpose="IPC mailbox PERIPH_ID at 0x23000034 — 0xC0DE0001, confirmed against the "
              "instantiated RTL (ipc_mailbox_apb_regs.sv:29 parameter PERIPH_ID, served "
              "from slot 6'd13 at :286), so it is R-class here. A distinct magic on a "
              "DIFFERENT matrix port from HIO-108/109/110, so it independently proves "
              "the 0x23xxxxxx decode arm. RED when: the word is not 0xC0DE0001, or the "
              "read errors. The 0xC0DE half is checked separately from the version "
              "half so a version bump is diagnosable rather than just 'wrong'.")
def hio_111(adp, rec):
    v = _rd(adp, rec, 0x23000034, "IPC PERIPH_ID")
    rec.record("ipc_periph_id", v)
    if v is None:
        return
    if _marker(rec, "IPC PERIPH_ID", v, 0xC0DE, hi=31, lo=16):
        rec.check("IPC PERIPH_ID version [15:0] == 0x0001",
                  _field(v, 15, 0) == 1, got=_h(v))
        rec.record("ipc_periph_version", _field(v, 15, 0))


@test("HIO-112", tier=1, control=False, hazard=None, weak=True,
      purpose="WEAK ALONE — declared as such by the plan and repeated here so it is not "
              "counted as coverage. Spinlock OWNER at 0x2C100300 (the DIAG page) must "
              "read 0x00000000, all 16 locks free. The only way it goes red is a bus "
              "ERROR or a NO-REPLY at that address; the VALUE half cannot discriminate, "
              "because a dead bus returns zero too and that is indistinguishable from "
              "'all locks free'. It becomes meaningful only paired with HIO-304 (Tier "
              "3), which makes a specific NON-ZERO owner value appear. HZ-7: the DIAG "
              "page is safe, but a READ of the acquire pages at +0x000/+0x100/+0x200 "
              "ACQUIRES the lock — those three are in this module's hazard blocklist "
              "and cannot be reached by any test here.")
def hio_112(adp, rec):
    rec.check("HZ-7 acquire pages are blocklisted in this module",
              all(forbidden(a) is not None
                  for a in (0x2C100000, 0x2C100100, 0x2C100200)),
              got="0x2C100300 (DIAG) allowed: %s" % (forbidden(0x2C100300) is None))
    v = _rd(adp, rec, 0x2C100300, "spinlock OWNER (DIAG page)")
    rec.record("spinlock_owner", v)
    _eq(rec, "spinlock OWNER (all 16 free)", v, 0x00000000)
    rec.note("Zero here proves nothing on its own. Pair with HIO-304 before treating "
             "this as coverage of the spinlock block.")


@test("HIO-113", tier=1, control=False, hazard=None,
      purpose="CPU1 UART (uart2) CoreSight ID at 0x28006FF0..FFC — the 0xB105F00D "
              "four-word pattern, plus PID0 at 0x28006FE0. RED when: any CID word is "
              "wrong, or PID0 is not 0x21 (the CMSDK UART part number). The CID alone "
              "would NOT prove the APB slot decode, because all four cc_periph "
              "peripherals share it — PID0 is what makes the claim 'this is slot 6, and "
              "slot 6 is the UART' falsifiable, and it is cross-checked against "
              "HIO-126's four-slot sweep. Proves both the 0x28xxxxxx matrix port and "
              "its internal PADDR[15:12]==6 decode. PID1/PID2/PID3 are also asserted "
              "(CONFIRMED-RTL: 0xB8, 0x1B, 0x00 — PID3 is 0x00 because this instance "
              "hardwires ECOREVNUM to 4'h0), giving the complete part identity.")
def hio_113(adp, rec):
    want = [0x0000000D, 0x000000F0, 0x00000005, 0x000000B1]
    got = []
    for i, w in enumerate(want):
        v = _rd(adp, rec, 0x28006FF0 + 4 * i, "uart2 CID%d" % i)
        got.append(v)
        _eq(rec, "uart2 CID%d" % i, v, w)
    rec.record("uart2_cid_words", got)

    pid0 = _rd(adp, rec, 0x28006FE0, "uart2 PID0")
    rec.record("uart2_pid0", pid0)
    _eq(rec, "uart2 PID0 (part number 0x21 — slot 6 really is the UART)", pid0, 0x21)

    # CONFIRMED-RTL: PID1=0xB8, PID2=0x1B, and PID3=0x00 because this instance's
    # ECOREVNUM is hardwired 4'h0 -- so PID3 IS assertable here, unlike the general
    # caution in HIO-126 (which does not read PID3 at all).
    pids = []
    for want, off, idx in ((0xB8, 0xFE4, 1), (0x1B, 0xFE8, 2), (0x00, 0xFEC, 3)):
        v = _rd(adp, rec, 0x28006000 + off, "uart2 PID%d" % idx)
        pids.append(v)
        _eq(rec, "uart2 PID%d (CONFIRMED-RTL)" % idx, v, want)
    rec.record("uart2_pid1_pid2_pid3", pids)
    rec.note("PID1/PID2/PID3 are now ASSERTED (promoted from record-only 2026-08-25). "
             "PID3 is safe to assert for THIS instance because its ECOREVNUM field is "
             "hardwired 4'h0; that is an instance fact, not a general one, which is why "
             "HIO-126 still declines to read PID3 across the four cc_periph slots. "
             "Together with PID0 = 0x21 above, this is the full CMSDK UART part "
             "identity and it pins slot 6 by part number, not merely by CID.")


@test("HIO-115", tier=1, control=False, hazard=None,
      purpose="QSPI controller identity, REGISTER APERTURE ONLY. CIDR0-3 at "
              "0x21000FF0..FFC = 0x50,0x51,0x4C,0x53 = ASCII 'PQLS' — a NON-Arm CID "
              "string, so it cannot be confused with any of the 0xB105F00D peripherals, "
              "which is what makes it prove the 0x21xxxxxx decode arm goes to the right "
              "block. RED when: any CIDR byte is wrong, or CLK_DIV reads 0 (the RTL "
              "clamps it to a minimum of 1 so a divider of zero cannot pass HCLK "
              "through — a zero means the register is not the real one). CLK_DIV == 1 "
              "is the RESET value and is recorded, not asserted, because firmware that "
              "has enabled XiP will legitimately have reprogrammed it. HZ-6: the XiP "
              "aperture at 0x24000000 is NOT probed and is blocklisted module-wide — "
              "probing it is exactly what a naive 'read one word from every region' "
              "sweep would do, and it stalls 1.3 ms per probe at best.")
def hio_115(adp, rec):
    rec.check("HZ-6 XiP aperture is blocklisted in this module",
              forbidden(0x24000000) is not None and forbidden(0x24FFFFFC) is not None,
              got="0x21xxxxxx register aperture allowed: %s"
                  % (forbidden(0x21000000) is None))

    want = [0x50, 0x51, 0x4C, 0x53]
    got = []
    for i, w in enumerate(want):
        v = _rd(adp, rec, 0x21000FF0 + 4 * i, "QSPI CIDR%d" % i)
        got.append(v)
        _eq(rec, "QSPI CIDR%d" % i, v, w)
    rec.record("qspi_cidr", got)
    if all(g is not None for g in got):
        rec.record("qspi_cidr_ascii",
                   "".join(chr(g) if 0x20 <= g <= 0x7E else "." for g in got))

    clk_div = _rd(adp, rec, 0x21000034, "QSPI CLK_DIV")
    rec.record("qspi_clk_div", clk_div)
    rec.check("QSPI CLK_DIV != 0 (RTL clamps the divider to a minimum of 1)",
              clk_div is not None and clk_div != 0, got=_h(clk_div))
    rec.record("qspi_clk_div_is_reset_value", int(clk_div == 1))

    ctrl = _rd(adp, rec, 0x21000000, "QSPI CTRL")
    rec.record("qspi_ctrl", ctrl)
    if ctrl is not None:
        xip = bool(ctrl & (1 << 8))
        rec.record("qspi_ctrl_xip_active_bit8", int(xip))
        if xip:
            rec.note("QSPI CTRL[8] XIP_ACTIVE is SET (reset value is 0), so XiP is "
                     "live on this die and the 0x24xxxxxx aperture is ARMED, not "
                     "dormant. Plan §1.5 HZ-6 measured exactly this on the FPGA "
                     "(0x21000000 -> 0x00000100).")


@test("HIO-117", tier=1, control=False, hazard=None,
      purpose="Single-register-region aliasing fingerprint, documenting the TRUE window "
              "size of two regions so that later sweeps do not mistake an alias for a "
              "second register. chip_core_remap_ctrl ignores HADDR entirely "
              "(chip_core_remap_ctrl.v:92), so 0x29000000 and 0x29FFFFF0 must be "
              "IDENTICAL; reset_ctrl decodes only HADDR[11:2], so 0x2A000FF0 and "
              "0x2A0FFFF0 must both return CID0 = 0x0000000D. RED when: either alias "
              "pair stops matching (a region that started decoding upper bits and "
              "erroring), or when ALL FOUR reads are equal — which is what a "
              "constant-returning bus does, and would otherwise satisfy both alias "
              "equalities for the wrong reason.")
def hio_117(adp, rec):
    a1 = _rd(adp, rec, 0x29000000, "remap_ctrl @0x29000000")
    a2 = _rd(adp, rec, 0x29FFFFF0, "remap_ctrl @0x29FFFFF0")
    b1 = _rd(adp, rec, 0x2A000FF0, "reset_ctrl CID0 @0x2A000FF0")
    b2 = _rd(adp, rec, 0x2A0FFFF0, "reset_ctrl CID0 @0x2A0FFFF0")
    rec.record("alias_29", [a1, a2])
    rec.record("alias_2a", [b1, b2])

    rec.check("0x29000000 aliases 0x29FFFFF0 (HADDR ignored)",
              a1 is not None and a1 == a2,
              got="%s vs %s" % (_h(a1), _h(a2)))
    rec.check("0x2A000FF0 aliases 0x2A0FFFF0 (only HADDR[11:2] decoded)",
              b1 is not None and b1 == b2,
              got="%s vs %s" % (_h(b1), _h(b2)))
    _eq(rec, "0x2A000FF0 CID0", b1, 0x0000000D)
    _eq(rec, "0x2A0FFFF0 CID0 (aliased)", b2, 0x0000000D)

    quad = [a1, a2, b1, b2]
    rec.check("the two regions do not return the same value (not a constant bus)",
              None not in quad and len(set(quad)) > 1,
              got=str([_h(q) for q in quad]))
    rec.note("Corner case, stated so a red is diagnosable rather than mysterious: the "
             "constant-bus check would mis-fire if the boot gate legitimately read "
             "0x0000000D (remap_q = 0b1101). If that ever happens, HIO-103's "
             "four-distinct-words check is the authority on whether the bus is constant.")


# ---------------------------------------------------------------------------
# HIO-118 — alias-wrap / physical-size probes
# ---------------------------------------------------------------------------
# Declared physical sizes, nanosoc_multicore_soc.sv:20-27,31-33,43.
# The two ROMs are included as the probe's POSITIVE CONTROL: their contents are known
# to be distinctive and their size is fixed in RTL, so if the method cannot find the
# 2 KB ROM wrap, the RAM verdicts below it are worthless.
_SIZE_PROBE = [
    # (base, declared_bytes, name, is_control)
    (0x08000000, 2 * 1024,  "eth_bootrom",  True),
    (0x80000000, 2 * 1024,  "cpu1_bootrom", True),
    (0x10000000, 32 * 1024, "eth_imem",     False),
    (0x18000000, 16 * 1024, "eth_dmem",     False),
    (0x90000000, 16 * 1024, "cpu1_imem",    False),
    (0x98000000, 8 * 1024,  "cpu1_dmem",    False),
    (0x2D000000, 8 * 1024,  "shared_sram",  False),
]
_SIZE_K = list(range(10, 21))   # 1 KB .. 1 MB, all inside every window above


@test("HIO-118", tier=1, control=False, hazard=None,
      purpose="Physical-size probe of every RAM and ROM by ALIAS-WRAP DETECTION — reads "
              "a 2-word signature at offset 0 and at 2^k for k=10..20 and finds the "
              "first offset at which the signature reappears. It DETECTS the wrap "
              "rather than assuming a size, which matters because plan §5.1 MEASURED "
              "0x80000000 and 0x80001000 returning the same word 0x18003C00 and "
              "concluded the CPU1 region size is unestablished. RED when: any probe "
              "errors or times out (these windows are declared decoded across their "
              "whole range); OR the two BOOT ROMs — the probe's positive control, with "
              "known distinctive contents and an RTL-fixed 2 KB depth — fail to show a "
              "confirmed wrap at exactly 2048 bytes, which means the METHOD is broken "
              "and every RAM verdict below it is void; OR a RAM shows a CONFIRMED wrap "
              "at a size other than its declared one (a macro built at the wrong depth, "
              "or not populated — a class the walking-ones tests cannot see, because a "
              "16 KB RAM aliased into a 32 KB window passes walking-ones everywhere). "
              "A RAM whose signature is degenerate (uniform, or all-zero) is reported "
              "INDETERMINATE and asserts nothing, rather than inventing a size.")
def hio_118(adp, rec):
    rec.note("READ-ONLY IMPLEMENTATION, deliberate deviation. The plan's variant writes "
             "a unique tag at offset 0 first, which is destructive and belongs in Phase "
             "D; Tier 1 is non-destructive by definition. The cost is that a region "
             "whose probed words are uniform cannot be resolved read-only — those are "
             "reported INDETERMINATE, not guessed. Re-run the tag-write variant in "
             "Phase D to close them.")

    results = {}
    for base, declared, name, is_control in _SIZE_PROBE:
        s0 = (_rd(adp, rec, base, "%s+0" % name),
              _rd(adp, rec, base + 4, "%s+4" % name))
        sigs = {}
        for k in _SIZE_K:
            off = 1 << k
            sigs[k] = (_rd(adp, rec, base + off, "%s+0x%X" % (name, off)),
                       _rd(adp, rec, base + off + 4, "%s+0x%X" % (name, off + 4)))

        readable = (None not in s0) and all(None not in s for s in sigs.values())
        matches = [k for k in _SIZE_K if sigs[k] == s0]
        differs = [k for k in _SIZE_K if sigs[k] != s0]
        first = (1 << matches[0]) if matches else None

        # Determinacy: an all-zero or uniform region cannot establish a wrap read-only.
        informative = readable and s0 != (0, 0) and len(differs) > 0
        verdict = ("CONFIRMED" if (informative and first is not None) else
                   "INDETERMINATE" if readable else "UNREADABLE")

        # wrap_bytes is only populated on a CONFIRMED verdict. first_match_bytes is the
        # raw observation and is meaningless on its own — in a uniform region every
        # offset "matches" offset 0, which is INDETERMINATE, not a 1 KB wrap.
        results[name] = {"base": _h(base), "declared_bytes": declared,
                         "sig0": list(s0), "verdict": verdict,
                         "wrap_bytes": (first if verdict == "CONFIRMED" else None),
                         "first_match_bytes": first,
                         "matched_k": matches, "differed_k": differs}

        rec.check("%s: all wrap probes readable across its window" % name,
                  readable, got=verdict)

        if is_control:
            rec.check("%s CONTROL: wrap is CONFIRMED (the method works on known "
                      "distinctive content)" % name, verdict == "CONFIRMED",
                      got="%s sig0=%s" % (verdict, [_h(x) for x in s0]))
            rec.check("%s CONTROL: wraps at the RTL-declared %d bytes"
                      % (name, declared), first == declared,
                      got="wrap=%s" % first)
        else:
            if verdict == "CONFIRMED":
                rec.check("%s: confirmed wrap == declared %d bytes" % (name, declared),
                          first == declared, got="wrap=%s" % first)
            else:
                rec.note("%s at %s: wrap INDETERMINATE read-only (signature %s, "
                         "%d of %d probed offsets differ from it). No size is asserted. "
                         "Declared depth is %d bytes."
                         % (name, _h(base), [_h(x) for x in s0],
                            len(differs), len(_SIZE_K), declared))

    rec.record("size_probe", results)

    cpu1_rom = results.get("cpu1_bootrom", {})
    rec.record("cpu1_region_wrap_bytes", cpu1_rom.get("wrap_bytes"))
    rec.note("ARBITRATION SETTLED, and this probe was right. The generated discovery "
             "table declares eth IMEM TGT_1_SIZE = 0x00010000 (64 KB); "
             "ETH_IMEM_RAM_ADDR_W = 15 gives 32 KB physical "
             "(nanosoc_multicore_soc.sv:25), and the chiplet overrides only the ROM "
             "image filename, so FPGA and ASIC are identical here. The alias-wrap "
             "measurement above agrees with the parameter, not with the table. "
             "THE MECHANISM, because it is a class and not a one-off: discovery.py "
             "lines 237-244 resolve phys_size against the SUBSYSTEM'S DEFAULT "
             "parameters and are blind to the parent's override. That single defect "
             "explains FOUR wrong targets — bootrom 8 KB declared vs 2 KB real, imem "
             "64 vs 32 KB, scratch_rx 16 vs 8 KB, scratch_tx 16 vs 8 KB. Note the "
             "arbitration is now settled MORE STRONGLY than a table readback could "
             "have settled it: a readback would only have told us what one table "
             "SAID, whereas the parameter chain tells us WHY the table is wrong. "
             "Nothing in this tier treats the discovery table as an authority for a "
             "size, and nothing should — see HIO-119, which is a permanent skip "
             "because no such table is instantiated on this build at all.")


# ---------------------------------------------------------------------------
# HIO-119 — PERMANENT SKIP. NOT APPLICABLE ON THIS BUILD.
# ---------------------------------------------------------------------------
# THERE IS NO DISCOVERY TABLE ON THIS DIE, AND THERE IS NO BASE ADDRESS TO FIND.
# Do not add one. This is a tombstone, not a TODO.
#
# If you have just found one of the *_ahb_interconnect_discovery register files and
# are about to helpfully wire this test up: those files are COMPILED BUT INSTANTIATED
# NOWHERE. An RTL audit over the real flist (flist/nanosoc_eth_chiplet.flist, 601
# files) found each of the three module names appearing ONLY in its own defining file,
# with no `bind` statements anywhere; and `grep -c -i discovery` on the shipping gate
# netlist returns 0. The single instantiation site in the whole repo is the legacy
# single-core nanosoc_region_soc_peripheral.v:370 at APB slot 13 — a file that is in
# neither flist, and this build sets EN13 = 0 so that slot is disabled regardless.
#
# So the resolution is NOT "we could not locate the base"; it is "the base does not
# exist". Deliberately there is no DISCOVERY_TABLE_BASE constant to set: a settable
# knob would be an invitation to point this test at some plausible-looking address and
# get a confident reading of the wrong register.
#
# The table would not have been worth much even if it were mapped: its SIZE fields are
# wrong by construction for four targets (see HIO-118). HIO-118's alias-wrap probe
# already establishes the real geometry from the silicon, and the parameter chain
# explains why the table disagrees — both stronger than a readback would have been.


@test("HIO-119", tier=1, control=False, hazard=None,
      purpose="Interconnect discovery-table readback — PERMANENTLY NOT APPLICABLE on "
              "this build, and reported as a SKIP rather than a pass. There is no "
              "discovery table to read: all three *_ahb_interconnect_discovery register "
              "files are compiled but INSTANTIATED NOWHERE (each module name appears "
              "only in its own defining file across all 601 files of "
              "flist/nanosoc_eth_chiplet.flist, there are no bind statements, and "
              "grep -c -i discovery on the shipping gate netlist returns 0). The only "
              "instantiation site in the repo is the legacy single-core "
              "nanosoc_region_soc_peripheral.v:370 at APB slot 13, which is in neither "
              "flist and is disabled by EN13 = 0 in this build. HOW THIS TEST GOES RED: "
              "it does not, and it never passes either — it always skips, which is the "
              "honest outcome for a test of something that is not on the die. The plan "
              "is explicit that an unmapped table must be marked NOT APPLICABLE rather "
              "than passed vacuously. There is deliberately NO base-address constant to "
              "set; the cross-check against HIO-114 that this test was meant to provide "
              "is not available on this build, and HIO-118's alias-wrap probe is what "
              "establishes RAM geometry instead — from the silicon, which is a better "
              "authority than the table would have been.")
def hio_119(adp, rec):
    rec.record("discovery_table_instantiated", 0)
    rec.record("discovery_table_base", None)
    rec.note("Nothing was read and nothing was asserted. NOT APPLICABLE on this build, "
             "which is not the same as a pass. RAM geometry comes from HIO-118 "
             "instead, measured on the die rather than declared by a table whose SIZE "
             "fields are wrong for four targets.")
    rec.skip("no discovery table exists on this build: all three "
             "*_ahb_interconnect_discovery register files are compiled but instantiated "
             "nowhere (no instance and no bind across the 601 files of the real flist; "
             "0 hits for 'discovery' in the shipping gate netlist). The only "
             "instantiation site in the repo is the legacy single-core "
             "nanosoc_region_soc_peripheral.v:370 at APB slot 13, which is in neither "
             "flist and is disabled by EN13 = 0 here. This is permanent — the base "
             "address does not exist, so do not add one.")


# ---------------------------------------------------------------------------
# TideLink / TideChart identity
# ---------------------------------------------------------------------------
@test("HIO-121", tier=1, control=False, hazard=None,
      purpose="TideLink identity, READ-ONLY HALF — preferred to 0x2E030000 because that "
              "one is RW and firmware or a previous test can have written the right "
              "value into it (plan §4.3 false-green #2). Asserts LINK_CAPABILITIES == "
              "0x00080008 (8 TX / 8 RX lanes max), the PHY_ALIGN_ID marker 'PA' with "
              "version 1.0, and the addr-translator PIDR0-3 and CIDR0-3. RED when: any "
              "of those is wrong; in particular the addr-translator CIDR3 must be 0x54 "
              "and NOT 0x53, which is QSPI's — the two ID strings differ in exactly one "
              "byte, and that near-collision is invisible to a lazy 'check the CID is "
              "0xB105F00D' test. MARKER DISCIPLINE: the 'PA' marker in PHY_ALIGN_ID "
              "[31:16], and the 0xB5 / 0xAD markers at 0x2E0321F8 / 0x2E0321E0, are "
              "each a SEPARATE check that must hold BEFORE any bit below them is "
              "decoded — without it a missing register reports as 'healthy, all zeros'. "
              "The status bits under those two markers are RECORDED here, never "
              "asserted: they are HIO-409's business, and plan §0.1 says only the "
              "markers themselves transfer from the FPGA to the ASIC. HZ-9: the wlink "
              "and addr-translator sub-regions pass pready straight through with no "
              "watchdog, so every read here relies on the client's transaction timeout.")
def hio_121(adp, rec):
    # LINK_CAPABILITIES field packing: max_tx_lanes[3:0], max_rx_lanes[7:4], [31:8]=0.
    # NOT the 16-bit fields wlink_regs.rdl declares -- see the note at the end.
    caps = _rd(adp, rec, 0x2E030200, "LINK_CAPABILITIES")
    rec.record("tidelink_link_capabilities", caps)
    if caps is not None:
        tx = _field(caps, 3, 0)
        rx = _field(caps, 7, 4)
        rec.record("tidelink_max_tx_lanes", tx)
        rec.record("tidelink_max_rx_lanes", rx)
        rec.check("LINK_CAPABILITIES max_tx_lanes [3:0] == 8", tx == 8,
                  got="%d (word %s)" % (tx, _h(caps)))
        rec.check("LINK_CAPABILITIES max_rx_lanes [7:4] == 8", rx == 8,
                  got="%d (word %s)" % (rx, _h(caps)))
        rec.check("LINK_CAPABILITIES [31:8] == 0 (only two 4-bit RO fields exist)",
                  _field(caps, 31, 8) == 0, got=_h(caps))

    align = _rd(adp, rec, 0x2E03211C, "PHY_ALIGN_ID")
    rec.record("tidelink_phy_align_id", align)
    if _marker(rec, "PHY_ALIGN_ID", align, 0x5041, hi=31, lo=16):   # 'PA'
        rec.check("PHY_ALIGN_ID version [15:0] == 0x0100 (v1.0)",
                  _field(align, 15, 0) == 0x0100, got=_h(align))

    want_pidr = [0x59, 0x16, 0x15, 0x00]
    got_pidr = []
    for i, w in enumerate(want_pidr):
        v = _rd(adp, rec, 0x2E034FE0 + 4 * i, "addr_trans PIDR%d" % i)
        got_pidr.append(v)
        _eq(rec, "addr_trans PIDR%d" % i, v, w)
    rec.record("tidelink_addrtrans_pidr", got_pidr)

    want_cidr = [0x50, 0x51, 0x4C, 0x54]      # 'P','Q','L','T' — NOT QSPI's ...0x53
    got_cidr = []
    for i, w in enumerate(want_cidr):
        v = _rd(adp, rec, 0x2E034FF0 + 4 * i, "addr_trans CIDR%d" % i)
        got_cidr.append(v)
        _eq(rec, "addr_trans CIDR%d" % i, v, w)
    rec.record("tidelink_addrtrans_cidr", got_cidr)
    rec.check("addr_trans CIDR3 is 0x54 and NOT QSPI's 0x53 (one-byte near-collision)",
              got_cidr[3] == 0x54 and got_cidr[3] != 0x53, got=_h(got_cidr[3]))

    # --- marker-only observation of the two status registers ----------------
    xhb = _rd(adp, rec, 0x2E0321F8, "XHB bridge status")
    rec.record("tidelink_21f8_word", xhb)
    if _marker(rec, "0x2E0321F8", xhb, 0xB5):
        rec.record("tidelink_21f8_xhb_stall_stuck_sticky_bit10",
                   _field(xhb, 10, 10))
        rec.record("tidelink_21f8_bridge_ready_bit0", _field(xhb, 0, 0))

    axinode = _rd(adp, rec, 0x2E0321E0, "axinode obs")
    rec.record("tidelink_21e0_word", axinode)
    if _marker(rec, "0x2E0321E0", axinode, 0xAD):
        rec.record("tidelink_21e0_data_healthy_bit23", _field(axinode, 23, 23))
        rec.record("tidelink_21e0_channel_wedge_19_10", _field(axinode, 19, 10))

    rec.note("LINK_CAPABILITIES is asserted as 8 TX / 8 RX lanes at bits [3:0] and "
             "[7:4], i.e. 0x00000088 -- NOT the 0x00080008 the plan's HIO-121 row "
             "quotes. The die is RIGHT and the plan was wrong, and the disagreement is "
             "a REGISTER-MAP DOCUMENTATION BUG, not a silicon one. Evidence: the built "
             "RTL is generated from Chisel, not from the RDL. "
             "wav-wlink-hw/src/main/scala/Wlink.scala:256-258 declares "
             "'WavSWReg(0x0, \"LinkCapabilities\", ..., WavRO(numTxLanes.asUInt, "
             "\"max_tx_lanes\", ...), WavRO(numRxLanes.asUInt, \"max_rx_lanes\", ...))' "
             "-- and a Chisel '8.asUInt' literal is FOUR bits wide, not sixteen, so the "
             "two fields pack into [3:0] and [7:4]. The generated Verilog hardcodes the "
             "result: 'wire [31:0] out_out_bits_data_out_1 = _out_out_bits_data_T ? "
             "32'h88 : ...' (Wlink.v:1342, the eth_chiplet_ip build). By contrast "
             "tidelink/src/rdl/wlink_regs.rdl:269,274 says 'field {} max_tx_lanes[16] = "
             "8;' -- two 16-bit fields, which would give 0x00080008. The RDL is a "
             "hand-maintained spec that the Chisel generator does not read; where they "
             "disagree the Chisel wins, because it is what was built. The MEANING the "
             "plan intended (8 TX lanes, 8 RX lanes) is confirmed exactly -- only the "
             "field offsets were wrong -- so this test still reds on a "
             "differently-parameterised link, a constant bus or a dead one. ASIC NOTE: "
             "this value comes from the Chisel elaboration parameters numTxLanes / "
             "numRxLanes, NOT from the ECC/CRC/FCSM configuration that differs between "
             "FPGA and ASIC, so 0x00000088 is expected on the ASIC too -- unless the "
             "ASIC build elaborates a different lane count, in which case these two "
             "checks are exactly what will catch it. "
             "The 0xB5 / 0xAD status bits are recorded, not asserted, on purpose. Plan "
             "§0.1: the marker bytes are structural and transfer to the ASIC, but the "
             "status bits below them may legitimately differ, so first ASIC silicon is "
             "record-and-classify until an ASIC baseline exists. HIO-409 (Tier 4) is "
             "the test that asserts 0x1F8[10]==0 and 0x1E0[23]==1. Reference words "
             "measured on FPGA 2026-08-25: 0xB5000001 and 0xAD800000.")


@test("HIO-122", tier=1, control=False, hazard=None,
      purpose="TideLink PHY_GENERAL_CONTROLS boot value at 0x2E030000 == 0x00010701, "
              "field-decoded so a partial match is diagnosable rather than just 'wrong': "
              "pre_count[7:0]=0x01, post_count[15:8]=0x07, rx_polarity[16]=1, and "
              "[31:17] must be zero. RED when any field differs. Explicitly a BOOT-VALUE "
              "test, NOT an identity test: this register is RW, so unlike HIO-121 it can "
              "be perturbed by firmware or by an earlier test and a green here does not "
              "prove the block is the right block — that is what HIO-121 is for. HZ-9 "
              "applies (wlink has no pready watchdog).")
def hio_122(adp, rec):
    v = _rd(adp, rec, 0x2E030000, "PHY_GENERAL_CONTROLS")
    rec.record("tidelink_phy_general_controls", v)
    if v is None:
        return
    rec.check("PHY_GENERAL_CONTROLS pre_count [7:0] == 0x01",
              _field(v, 7, 0) == 0x01, got=_h(v))
    rec.check("PHY_GENERAL_CONTROLS post_count [15:8] == 0x07",
              _field(v, 15, 8) == 0x07, got=_h(v))
    rec.check("PHY_GENERAL_CONTROLS rx_polarity [16] == 1",
              _field(v, 16, 16) == 1, got=_h(v))
    rec.check("PHY_GENERAL_CONTROLS [31:17] == 0",
              _field(v, 31, 17) == 0, got=_h(v))
    rec.record("tidelink_pre_count", _field(v, 7, 0))
    rec.record("tidelink_post_count", _field(v, 15, 8))
    rec.record("tidelink_rx_polarity", _field(v, 16, 16))
    rec.note("This is a reset default from wlink_regs.rdl:200-219, so it should transfer "
             "from FPGA to ASIC; but plan §0.1 warns every TideLink test was written "
             "against the FPGA configuration (ECC active, CRC off, FCSM recovery "
             "present) and the ASIC differs on all three. A mismatch here is a finding "
             "to classify, not automatically a bad die.")


@test("HIO-123", tier=1, control=False, hazard=None,
      purpose="TideChart identity — the block has NO ID or magic register at all, so "
              "its two non-zero reset values are the only identity handles it has. "
              "TC_TIMEOUT at 0x2E04000C == 0x03E81000, decoded as enum_timeout=1000 "
              "[31:16] and election_timeout=4096 [15:0]; RED when either field is "
              "wrong, and a non-zero expectation means it also fails on a bus returning "
              "zeros. TC_DEVICE_CLASS at 0x2E040010 is a PER-DIE STRAP and is RECORDED, "
              "not asserted — see the note; asserting the RTL default 0x00000001 would "
              "red the other die of every pair. Never reads TC_RANDOM_ID (0x2E04001C): "
              "it is PUF-derived and differs per die AND per boot, so it would poison a "
              "fingerprint meant to be diffed. Never writes 0x2E040008 (bit 3 re-arms "
              "the election) — this tier writes nothing.")
def hio_123(adp, rec):
    tmo = _rd(adp, rec, 0x2E04000C, "TC_TIMEOUT")
    rec.record("tidechart_tc_timeout", tmo)
    if tmo is not None:
        rec.check("TC_TIMEOUT enum_timeout [31:16] == 1000",
                  _field(tmo, 31, 16) == 1000, got=_h(tmo))
        rec.check("TC_TIMEOUT election_timeout [15:0] == 4096",
                  _field(tmo, 15, 0) == 4096, got=_h(tmo))
        rec.record("tidechart_enum_timeout", _field(tmo, 31, 16))
        rec.record("tidechart_election_timeout", _field(tmo, 15, 0))

    dev = _rd(adp, rec, 0x2E040010, "TC_DEVICE_CLASS")
    rec.record("tidechart_tc_device_class", dev)
    rec.record("tidechart_device_class_is_rtl_default", int(dev == 0x00000001))
    rec.note("TC_DEVICE_CLASS read %s. NOT ASSERTED, deliberately: it reads back the "
             "per-die strap, and on a two-die pair the two dies MUST read DIFFERENT "
             "device classes or the TideChart election has no tiebreak and both can "
             "settle as root (nanosoc_eth_chiplet.sv:76-80) — the known dual-root "
             "failure. The plan's row quotes the RTL default 0x00000001, which cannot "
             "be right for both dies of a pair. The comparison that matters is between "
             "the two dies' RECORDS, not against a constant; do it at record-diff time."
             % _h(dev))


@test("HIO-124", tier=1, control=False, hazard=None,
      purpose="DMA-250 identity AND POWER STATE — one read with THREE distinguishable "
              "outcomes, each a different diagnosis: IIDR == 0x2500043B (present and "
              "powered), IIDR == 0 (PRESENT BUT POWER-GATED, because the registers sit "
              "behind pqen_apb = pwr_en & clk_en — a documented silicon symptom on this "
              "part), or '!' (decode fault). RED when: the read errors, or IIDR is not "
              "the expected ID. The PIDRs are asserted only when IIDR is correct, so a "
              "gated part reports ONE failure with the right diagnosis instead of five "
              "with the wrong one. Contrast with the naive check '0x20000000 reads 0, "
              "therefore the DMA is present': that address is SCFG_CHSEC0, whose zero "
              "value is also what a dead bus returns, so the measured 0x20000000 -> "
              "0x00000000 of 2026-08-25 proves nothing about the DMA. This test is what "
              "settles it.")
def hio_124(adp, rec):
    r = _probe(adp, 0x20000FC8)
    rec.record("dma250_iidr", r.value)
    rec.record("dma250_iidr_raw", r.raw)
    rec.check("DMA-250 IIDR @0x20000FC8 replied", r.ok is True, got=r.raw)
    rec.check("DMA-250 IIDR @0x20000FC8 no bus error (decode fault if '!')",
              r.error is False, got=r.raw)

    if r.ok and not r.error:
        state = ("PRESENT" if r.value == 0x2500043B else
                 "POWER-GATED" if r.value == 0 else "UNEXPECTED")
    else:
        state = "DECODE-FAULT" if (r.ok and r.error) else "NO-REPLY"
    rec.record("dma250_state", state)

    _eq(rec, "DMA-250 IIDR", r.value, 0x2500043B)

    if state == "PRESENT":
        rec.record("dma250_product", _field(r.value, 31, 20))
        rec.record("dma250_implementer", _field(r.value, 11, 0))
        want = [0x50, 0xB2, 0x0B, 0x00]
        got = []
        for i, w in enumerate(want):
            v = _rd(adp, rec, 0x20000FE0 + 4 * i, "DMA-250 PIDR%d" % i)
            got.append(v)
            _eq(rec, "DMA-250 PIDR%d" % i, v, w)
        rec.record("dma250_pidr", got)
    elif state == "POWER-GATED":
        rec.note("DMA-250 IIDR reads 0x00000000: the block is PRESENT BUT POWER-GATED, "
                 "not absent (docs/DMA250_DESIGN_AND_WORKPLAN.md:69-70,86-88 — sim "
                 "returns 0x2500043B and config writes do not stick on silicon). PIDRs "
                 "are not read, because they would read zero for the same single "
                 "reason. This is a power/clock finding: chase pwr_en & clk_en, not the "
                 "decode.")
    else:
        rec.note("DMA-250 IIDR is %s, classified %s. Neither the expected ID nor the "
                 "power-gated zero — treat as an unknown part or a mis-decode before "
                 "believing anything else at 0x20xxxxxx." % (_h(r.value), state))


@test("HIO-125", tier=1, control=False, hazard=None,
      purpose="Event-router reset defaults and window shape. Asserts the four route "
              "registers the block ACTUALLY implements — IRQ_ROUTE_CPU0 (+0x00) = 0, "
              "IRQ_ROUTE_CPU1 (+0x04) = 0x0000000F, EVT_ROUTE_CPU0 (+0x08) = 0, "
              "EVT_ROUTE_CPU1 (+0x0C) = 0 — plus [31:4] = 0 on all four, ROUTE_LOCK "
              "(+0x10) [31:1] = 0, that the two adjacent IRQ_ROUTE registers DIFFER, "
              "and the block's 32-BYTE ALIAS: 0x2B000024 must equal 0x2B000004. "
              "IRQ_ROUTE_CPU1's 0x0F is a load-bearing NON-ZERO reset default "
              "('IRQ_CPU1_RST = {N_SRC{1'b1}}', evt_route_ctrl.v:82,114 — all DMA-done "
              "to CPU1), so this test fails on a bus that returns zeros, the failure "
              "mode that makes most reset-value tests worthless; its zero neighbour "
              "proves the block distinguishes two adjacent registers, which neither "
              "read alone can. RED when: any value is wrong, the neighbours read the "
              "same thing (a collapsed offset decode), any route register has a bit "
              "above [3:0], or the 32-byte alias stops holding. "
              "WHY THERE IS NO LONGER A PID CHECK (measured 0x00000000 at 0x2B000FE0 "
              "on the FPGA die, 2026-08-25; the plan predicted 0x22 and the plan is "
              "WRONG): evt_route_ctrl HAS NO CoreSight ID SPACE AT ALL. The whole "
              "register file is a five-entry mux — OFF_IRQ_CPU0/IRQ_CPU1/EVT_CPU0/"
              "EVT_CPU1/LOCK at word offsets 0..4 with 'default: hrdata_q = "
              "{SYS_DATA_W{1'b0}}' (evt_route_ctrl.v:144-151) — and the file contains "
              "no PID or CID register anywhere. Worse, the decode is "
              "'wire [2:0] word_addr = HADDR[ADDR_MSB:ADDR_LSB]' with ADDR_MSB=4, "
              "ADDR_LSB=2 (:71-72,91), so only HADDR[4:2] is decoded and the block "
              "aliases every 32 bytes across the whole 0x2B window: 0x2B000FE0 has "
              "HADDR[4:2] = 0b000, so it is not an unmapped offset at all, it is an "
              "ALIAS OF IRQ_ROUTE_CPU0 — whose reset value is 0. The die returned "
              "exactly what the RTL says it must. The 0x22 came from "
              "sys_desc/register_maps/evt_route_ctrl.yaml:27 (pid0) at offset 0xFE0 "
              "(:111-112), a register-map SPECIFICATION artefact that the implemented "
              "RTL never realised — precisely the B-class trap plan §0 warns about. "
              "The alias check below turns that discovery into coverage: the aliasing "
              "IS the block's window shape, and it is now asserted rather than "
              "mistaken for a missing peripheral. Never writes 0x2B000010 — ROUTE_LOCK "
              "is write-1-set and one-way until HRESETn; this tier writes nothing at "
              "all. ASIC NOTE: all of this is plain RTL with no ECC/CRC/FCSM "
              "dependency, so the ASIC must read the same.")
def hio_125(adp, rec):
    routes = [(0x2B000000, "IRQ_ROUTE_CPU0", 0x00000000),
              (0x2B000004, "IRQ_ROUTE_CPU1", 0x0000000F),
              (0x2B000008, "EVT_ROUTE_CPU0", 0x00000000),
              (0x2B00000C, "EVT_ROUTE_CPU1", 0x00000000)]
    vals = {}
    for addr, name, want in routes:
        v = _rd(adp, rec, addr, "evt_route %s" % name)
        vals[name] = v
        _eq(rec, "evt_route %s" % name, v, want)
        if v is not None:
            # read mux is {{(SYS_DATA_W-N_SRC){1'b0}}, reg} with N_SRC=4 (:144-148)
            rec.check("evt_route %s [31:4] == 0 (N_SRC=4, mux zero-extends)" % name,
                      _field(v, 31, 4) == 0, got=_h(v))
    rec.record("evt_route_routes", vals)
    rec.record("evt_route_irq_route_cpu0", vals["IRQ_ROUTE_CPU0"])
    rec.record("evt_route_irq_route_cpu1", vals["IRQ_ROUTE_CPU1"])

    cpu0, cpu1 = vals["IRQ_ROUTE_CPU0"], vals["IRQ_ROUTE_CPU1"]
    rec.check("the two adjacent IRQ_ROUTE registers read DIFFERENT values "
              "(offset decode is not collapsed)",
              cpu0 is not None and cpu1 is not None and cpu0 != cpu1,
              got="cpu0=%s cpu1=%s" % (_h(cpu0), _h(cpu1)))

    lock = _rd(adp, rec, 0x2B000010, "evt_route ROUTE_LOCK")
    rec.record("evt_route_route_lock", lock)
    if lock is not None:
        rec.check("evt_route ROUTE_LOCK [31:1] == 0 (single bit, zero-extended)",
                  _field(lock, 31, 1) == 0, got=_h(lock))
        rec.record("evt_route_route_lock_bit0", _field(lock, 0, 0))
        if _field(lock, 0, 0):
            rec.note("ROUTE_LOCK bit0 is SET: the routes are frozen until HRESETn and "
                     "no Tier-3 write test can change them. Recorded, not failed — a "
                     "locked router is a legitimate state, but it means something has "
                     "already written this block on this power cycle.")

    # The 32-byte alias IS the window shape: HADDR[4:2] only (evt_route_ctrl.v:71-72,91).
    alias = _rd(adp, rec, 0x2B000024, "evt_route +0x24 (alias of +0x04)")
    rec.record("evt_route_alias_0x24", alias)
    rec.check("0x2B000024 aliases IRQ_ROUTE_CPU1 at 0x2B000004 "
              "(block decodes HADDR[4:2] only, so it repeats every 32 bytes)",
              alias is not None and alias == cpu1,
              got="+0x24=%s vs +0x04=%s" % (_h(alias), _h(cpu1)))
    rec.note("0x2B000FE0 is NOT probed: it is not a PID register, it is another alias "
             "of IRQ_ROUTE_CPU0 (HADDR[4:2]=0). Reading it as a peripheral ID is what "
             "produced the 2026-08-25 false red.")


@test("HIO-126", tier=1, control=False, hazard=None,
      purpose="cc_periph slot-decode discrimination — PID0 from four APB slots: 0x22 "
              "(timer0, slot 0), 0x23 (dualtimer, slot 2), 0x21 (uart2, slot 6), 0x24 "
              "(watchdog, slot 8). FOUR DISTINCT PART NUMBERS IN FOUR SLOTS IS THE "
              "STRONGEST DECODE TEST ON THE DIE. RED when: any PID0 is wrong, or when "
              "the four values are not all different — a collapsed PADDR[15:12] decode "
              "returns the SAME PID four times, which a per-peripheral 'the CID is "
              "0xB105F00D' test would happily pass because all four share that CID. "
              "This is the concrete instance of 'check that the check can tell things "
              "apart'. PID3 (+0xFEC) is deliberately not read: it packs a "
              "revision-dependent ECOREVNUM. The watchdog is READ only — arming it "
              "starts a reset countdown. Slots 0x4000/0x5000 (USRT0/1) are tied off "
              "inside the wrapper and are skipped.")
def hio_126(adp, rec):
    slots = [(0x28000FE0, 0x22, "timer0"),
             (0x28002FE0, 0x23, "dualtimer"),
             (0x28006FE0, 0x21, "uart2"),
             (0x28008FE0, 0x24, "watchdog")]
    got = []
    for addr, want, name in slots:
        v = _rd(adp, rec, addr, "%s PID0" % name)
        got.append(v)
        _eq(rec, "%s PID0 @%s" % (name, _h(addr)), v, want)
    rec.record("cc_periph_pid0", {n: v for (_a, _w, n), v in zip(slots, got)})

    rec.check("the four slots return FOUR DIFFERENT part numbers "
              "(PADDR[15:12] decode is not collapsed)",
              None not in got and len(set(got)) == 4,
              got=str([_h(g) for g in got]))
    rec.note("uart2's PID0 here must equal the one HIO-113 read at the same address; "
             "the two tests cross-check each other's slot claim.")


@test("HIO-127", tier=1, control=False, hazard=None,
      purpose="Non-zero counter reset values — the COMPLEMENT of every zero-reset test "
              "in this tier. Dualtimer TIMER1VALUE (0x28002004), watchdog WDOGLOAD "
              "(0x28008000) and WDOGVALUE (0x28008004) all reset to 0xFFFFFFFF (the "
              "dualtimer resets high specifically to avoid a spurious interrupt at "
              "start). RED when any is not all-ones. An all-ones expectation fails on a "
              "bus stuck at ZERO, while the zero-reset tests (HIO-105, HIO-112, "
              "HIO-125's CPU0 route) fail on a bus stuck at ONES — running both classes "
              "is what makes this tier's reset-value coverage two-sided. Reads only; "
              "the watchdog is never written.")
def hio_127(adp, rec):
    probes = [(0x28002004, "dualtimer TIMER1VALUE"),
              (0x28008000, "watchdog WDOGLOAD"),
              (0x28008004, "watchdog WDOGVALUE")]
    vals = {}
    for addr, name in probes:
        v = _rd(adp, rec, addr, name)
        vals[name] = v
        _eq(rec, "%s (all-ones reset)" % name, v, 0xFFFFFFFF)
    rec.record("nonzero_counter_resets", vals)
    rec.note("Caveat for a red here: TIMER1VALUE and WDOGVALUE are COUNTERS. They hold "
             "0xFFFFFFFF only while their block is disabled, which is the reset state. "
             "If firmware has enabled the dualtimer or armed the watchdog they will be "
             "counting down and this test reds for a live-system reason rather than a "
             "silicon one — check HIO-106's bus_quiescent_expected before treating a "
             "failure here as a defect. WDOGLOAD is not a counter and is the "
             "unambiguous half.")
