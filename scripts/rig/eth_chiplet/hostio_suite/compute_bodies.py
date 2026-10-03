"""compute_bodies.py -- the NanoSoC COMPUTE chiplet's bodies for three tier-1 controls.

NOT a tier module (the name does not match tier*.py, so discover() never imports
it). The `haps_sx_compute` target names these in Target.test_bodies, and the
runner calls them in place of the eth bodies for the SAME test ids. The ids keep
their control role and their gating, so THE RULE is unchanged: everything
HIO-103 / HIO-106 / HIO-114 gate is VOID unless the compute body PASSES.

Why bodies and not skips: HIO-106 gates every other tier-1 test AND HIO-120,
and HIO-120 gates tiers 2-5. Skipping the eth body would VOID the whole suite;
running it would read eth's boot gate ladder on a die that has none. Each body
below asks the SAME QUESTION its eth original asks, of the compute map:

  HIO-106  "what boot state is this chip in, before anything else is read?"
           -- compute core_remap + the M4 BootROM/SPL breadcrumbs + the
              hostio_test phase word.
  HIO-103  "does the fabric decode four DIFFERING ID words?"  (ABORT GATE 4)
           -- the CMSDK watchdog CID (a block nothing else in tier 1 asserts).
  HIO-114  "does the decode map match the RTL's?"
           -- a census of compute's debug_m targets against the generated
              memory map: each probe's OK-vs-'!' class is asserted.

Sources: nanosoc_compute_soc_memory_map.txt (rsyn9 launch snapshot, debug_m
Initiator Connectivity), compute_mem.h (breadcrumb addresses and values),
hostio_test.c (HT_* phase words), compute_ss_bootrom.sv (ROM words).

Every address here is READ ONLY. No body in this file writes anything.
"""

from __future__ import annotations

SHARED = 0x2D000000
HT_STATUS = SHARED + 0x400
BC_COPY, BC_STAGE, BC_FAIL = SHARED + 0xEC, SHARED + 0xF0, SHARED + 0xFC
SPL_MARK, STAGE1_MARK = SHARED + 0x04, SHARED + 0x0C
CORE_REMAP = 0x29000000

BC_COPY_OK = (0x444D4121, 0x43505521)       # 'DMA!' / 'CPU!' (compute_mem.h:133-134)
BC_STAGE_SPL_HANDOFF = 0xB0070008           # measured T6a, the value a good flash boot leaves
SIG_SPL = 0x53504C21                        # 'SPL!'
SIG_STAGE1 = 0x53544731                     # 'STG1' (COMPUTE_SIG_STAGE1)
HT_PHASES = {0x48540001: "TX_DONE", 0x48540002: "RX_DONE",
             0x48540003: "HAMMER_RUN", 0x48540004: "HAMMER_DONE (parked on WFI)"}

WDOG_CID = 0x28008FF0                       # cmsdk_apb_watchdog CID0..3 (READ only)
CID_WANT = (0x0D, 0xF0, 0x05, 0xB1)


def _h(v):
    return "None" if v is None else "0x%08X" % v


def _rd(adp, rec, addr, what):
    r = adp.read(addr)
    rec.check("%s (0x%08X) read is well-formed and unflagged" % (what, addr),
              bool(r.ok) and r.error is False, got=r.raw)
    return r.value if (r.ok and r.error is False) else None


# ------------------------------------------------------------------ HIO-106 --
def hio_106_compute(adp, rec):
    adp.enter()
    remap = _rd(adp, rec, CORE_REMAP, "core_remap")
    rec.record("core_remap_word", _h(remap))
    if remap is not None:
        rec.record("remap_q", remap & 0xF)
        # core_remap_ctrl.v:126 -- HRDATA = {28'b0, remap_q}: a structural check
        # a decode fault or a different slave on this arm would fail.
        rec.check("core_remap [31:4] read as zero (HRDATA = {28'b0, remap_q}, "
                  "core_remap_ctrl.v:126)", (remap & ~0xF) == 0, got=_h(remap))

    copy = _rd(adp, rec, BC_COPY, "BootROM BC_COPY")
    stage = _rd(adp, rec, BC_STAGE, "BootROM BC_STAGE")
    fail = _rd(adp, rec, BC_FAIL, "BootROM BC_FAIL")
    spl = _rd(adp, rec, SPL_MARK, "SPL marker")
    stg1 = _rd(adp, rec, STAGE1_MARK, "stage-1 marker")
    ht = _rd(adp, rec, HT_STATUS, "hostio_test HT_STATUS")
    rec.record("bc", {"BC_COPY": _h(copy), "BC_STAGE": _h(stage), "BC_FAIL": _h(fail),
                      "SPL": _h(spl), "STAGE1": _h(stg1), "HT_STATUS": _h(ht)})

    rec.check("BootROM copied its stage: BC_COPY is 'DMA!' or 'CPU!'",
              copy in BC_COPY_OK, got=_h(copy))
    rec.check("BootROM handed off to the SPL: BC_STAGE == 0xB0070008",
              stage == BC_STAGE_SPL_HANDOFF, got=_h(stage))
    # BC_FAIL is written ONLY on a failure (0xFA11xxxx, ROM v2) and is never
    # cleared on success, so "== 0" would read a stale RAM word as a verdict
    # (a tier-2 fill leaves 0xA5A5A5A5 there). The check is the failure TAG.
    rec.check("BootROM recorded no failure: BC_FAIL is not a 0xFA11xxxx tag",
              fail is not None and (fail >> 16) != 0xFA11, got=_h(fail))
    rec.check("the SPL ran: 'SPL!' at shared+0x4", spl == SIG_SPL, got=_h(spl))
    rec.check("stage 1 (hostio_test) ran: 'STG1' at shared+0xC", stg1 == SIG_STAGE1, got=_h(stg1))
    rec.check("HT_STATUS is one of hostio_test's four phase words",
              ht in HT_PHASES, got=_h(ht))
    rec.record("hostio_test_phase", HT_PHASES.get(ht, "unknown"))
    # The suite's ROM/IMEM reads are safe ONLY in the parked phase (no bus
    # timeout on ADP). Not a check -- the operator owns the precondition -- but
    # it is the first thing to read in a red run.
    if ht != 0x48540004:
        rec.note("HT_STATUS is %s, NOT 0x48540004: the M4 is NOT parked on WFI, and "
                 "ROM/IMEM reads later in this run can starve on the admin port."
                 % _h(ht))
    rec.note("Compute body for HIO-106 (target haps_sx_compute): eth's boot gate "
             "ladder does not exist on this die. The question is the same -- what "
             "boot state is the chip in -- asked of core_remap and the M4 boot "
             "breadcrumbs. Eight values, each of which can be wrong.")


# ------------------------------------------------------------------ HIO-103 --
def hio_103_compute(adp, rec):
    got = []
    for i, w in enumerate(CID_WANT):
        v = _rd(adp, rec, WDOG_CID + 4 * i, "watchdog CID%d" % i)
        got.append(v)
        rec.check("watchdog CID%d == 0x%02X" % (i, w), v == w, got=_h(v))
    rec.record("watchdog_cid_words", [_h(g) for g in got])
    if all(g is not None for g in got):
        composed = ((got[3] & 0xFF) << 24) | ((got[2] & 0xFF) << 16) | \
                   ((got[1] & 0xFF) << 8) | (got[0] & 0xFF)
        rec.record("watchdog_cid", _h(composed))
        rec.check("watchdog CID composes 0xB105F00D", composed == 0xB105F00D, got=_h(composed))
        rec.check("the four CID words are not all identical (not a constant bus)",
                  len(set(got)) == 4, got=str([_h(g) for g in got]))
    rec.note("Compute body for HIO-103: there is no reset_ctrl on compute (0x2A is "
             "the IPC mailbox). The CMSDK watchdog's CID is used because no other "
             "tier-1 test asserts that block. READ ONLY: arming the watchdog "
             "starts a reset countdown, and nothing here writes it.")


# ------------------------------------------------------------------ HIO-114 --
# (address, expected decode class, why). 'OK' = reply with a space (no '!');
# 'E' = the bus-error flag. Derived from the GENERATED memory map's debug_m
# connectivity, not from a measurement on this die -- so the census can disagree
# with the die, which is the point.
CENSUS = [
    (0x20000FC8, "OK", "dma_250_0 (IIDR)"),
    (0x21000FF0, "OK", "qspi_flash_0 regs (CIDR0)"),
    (0x28000FE0, "OK", "manager_periph_0 slot 0 timer0 PID0"),
    (0x28006FF0, "OK", "manager_periph_0 slot 6 uart2 CID0"),
    (0x2800DFF0, "OK", "manager_periph_0 slot 13 HOSTIO USRT CID0"),
    (0x29000000, "OK", "core_remap_0"),
    (0x2A000034, "OK", "ipc_mailbox_0 PERIPH_ID"),
    (0x2B000000, "OK", "phc_0 ctrl"),
    (0x2C000300, "OK", "hw_spinlock_0 DIAG OWNER (NOT an acquire page)"),
    (0x2D000000, "OK", "shared_sram_0 word 0"),
    (0x2D001FFC, "OK", "shared_sram_0 last word of 8 KB"),
    (0x80000000, "OK", "compute_admin -> bootrom_0 word 0"),
    (0x90003FFC, "OK", "compute_admin -> imem_0 last word of 16 KB (rf_16k)"),
    (0x98001FFC, "OK", "compute_admin -> dmem_0 last word of 8 KB (rf_08k)"),
    (0x08000000, "E", "eth's boot ROM alias: not on compute's debug_m"),
    (0x10000000, "E", "M4-local IMEM view: not on debug_m"),
    (0x18000A00, "E", "M4-local DMEM view: not on debug_m (hostio_test's BAD target)"),
    (0x22000000, "E", "eth's PHC base: unmapped on compute"),
    (0x23000000, "E", "eth's IPC base: unmapped on compute"),
    (0x2E000000, "E", "eth's TideLink window: unmapped on compute"),
    (0x30000000, "E", "the suite's canonical unmapped address"),
    (0x40000000, "E", "d2d0: NOT in debug_m's target list"),
    (0x60000000, "E", "d2d1: NOT in debug_m's target list"),
    (0x70000000, "E", "unmapped"),
]


def hio_114_compute(adp, rec):
    adp.enter()
    rows, bad = [], []
    for addr, want, why in CENSUS:
        r = adp.read(addr)
        if not r.ok:
            cls = "TIMEOUT"
        else:
            cls = "E" if r.error else "OK"
        rows.append({"addr": _h(addr), "want": want, "got": cls, "raw": r.raw, "what": why})
        if cls != want:
            bad.append("%s want %s got %s (%s)" % (_h(addr), want, cls, why))
    rec.record("census", rows)
    rec.check("every probe answered (no timeout)", all(x["got"] != "TIMEOUT" for x in rows),
              got=[x["addr"] for x in rows if x["got"] == "TIMEOUT"])
    rec.check("every probe's decode class matches the generated memory map",
              not bad, got=bad)
    n_ok = sum(1 for x in rows if x["got"] == "OK")
    n_e = sum(1 for x in rows if x["got"] == "E")
    rec.check("the census is not one-sided (both OK and '!' were seen)",
              n_ok > 0 and n_e > 0, got="OK=%d E=%d" % (n_ok, n_e))
    rec.record("census_counts", {"OK": n_ok, "E": n_e})
    rec.note("Compute body for HIO-114: %d probes over compute's debug_m map. The "
             "decode CLASS is asserted; values are recorded only. 0x24000000 (XiP, "
             "HZ-6) and the spinlock ACQUIRE pages are deliberately not probed."
             % len(CENSUS))
