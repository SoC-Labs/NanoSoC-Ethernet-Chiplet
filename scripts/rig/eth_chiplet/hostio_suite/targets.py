#!/usr/bin/env python3
"""targets.py -- the TARGET PROFILE for the HOSTIO4 / ADP functional test suite.

THE PROBLEM THIS SOLVES
=======================
The suite was calibrated end to end on ONE vehicle: the KR260 FPGA build.  Tier 1
alone carries ~106 assertions, and a meaningful number of them are true only of
that vehicle -- the fabric runs at 25.010 MHz, the eth boot ROM is `smoke_remap`,
eth DMEM word 0 is the `SystemCoreClock` initialiser 0x05F5E100.  Run the same
suite unmodified against first ASIC silicon and it produces a WALL OF FALSE REDS,
because on the ASIC the fabric runs at 100 MHz, the eth ROM is `stage0_bootrom`
(172 of 320 words differ, first at word 55), and eth DMEM word 0 is 0x00000000 by
construction.  A wall of false reds on first silicon is worse than no suite: the
operator learns to ignore red, and the ONE real red is lost in it.

Before this file the suite had four scattered environment knobs -- `ETH_ROM_IMAGE`,
`HOSTIO_CPU1_PARKED`, `HOSTIO_SOAK_SECONDS`, `HOSTIO_PHC_CORE_HZ` -- and no
coherent notion of WHICH THING IS UNDER TEST.  Four knobs is four chances to set
three of them and get a run that is quietly calibrated for neither vehicle.

THE DESIGN RULE THAT MATTERS
============================
A target profile is NOT a way to make failures disappear.  It is a way to say
WHICH ASSERTIONS ARE EVIDENCE ON THIS VEHICLE.  Therefore:

  * every assertion the profile relaxes is RECORDED -- the value seen, the
    property it depended on, and the reason it was not asserted;
  * the run record and the printed report both carry the DEFERRAL COUNT, so a run
    that asserted almost nothing cannot be mistaken for a clean run;
  * the default target is `unknown`, never `fpga_kr260`.  An operator who forgets
    `--target` on first silicon gets DATA AND A FLAG, not a fake failure -- and
    not a fake pass either.

SOME FACTS BELONG TO THE BOARD, NOT TO THE VEHICLE
==================================================
A profile answers "which vehicle is this?".  It cannot answer "which SOCKET is
this die in?".  Whether QSPI flash is fitted and programmed is the second kind of
question: the same silicon reads a HEALTHY zero boot gate on a bare board and a
healthy 0x4 on a provisioned one.  Properties like that (`Target.OPERATOR_DECLARED`)
are None on EVERY profile by construction, are declared per run with
`--target-set flash_provisioned=0` or `HOSTIO_FLASH_PROVISIONED=0`, and are
reported apart from the open questions so that nobody "closes the gap" by writing
a constant into a profile that then answers for every board it is pointed at.

AND THE LESSON THAT PUT THEM THERE: AN ESTABLISHED PROPERTY IS NOT AUTOMATICALLY
THE RIGHT PROPERTY TO GATE ON.  `bootgate_values` is `known` on asic_tsmc65, so
`rec.target_check(prop="bootgate_values")` on a ZERO gate sails through its guard
and reds a perfectly healthy unprovisioned board.  The guard can only ask whether
a property is declared; asking whether it is the property that ANSWERS THE
QUESTION is the author's job, and it has to be done once, at the call site.

TARGET-INDEPENDENT FACTS STAY ASSERTED ON EVERY PROFILE
=======================================================
`unknown` asserts nothing TARGET-SPECIFIC.  It still asserts everything that is
true of the DESIGN rather than of the vehicle -- see `TargetIndependent` below.
The boot gate is never 0x00000000 on any vehicle, because cc_rom writes 4 to it on
both of its exit paths and cc_rom carries no sim-divergence waiver; the PHC's
NS_INCR reset default is 4 everywhere, and wrong everywhere.  Those are properties
of the RTL, and a profile that stopped asserting them would be exactly the
"make the red go away" failure this file exists to avoid.

THE MEASURED DIFFERENCES (established 2026-08-25; do not re-derive)
===================================================================
                        KR260 FPGA              ASIC (TSMC65)
  fabric clock          25.010 MHz measured     100 MHz (ASIC/common.mk
                        (routed report 25.011)  CLK_PERIOD = 10.0)
  eth boot ROM          smoke_remap             stage0_bootrom -- 172 of 320
                                                words differ, first at word 55
  eth DMEM word 0       0x05F5E100              0x00000000 (the ASIC image never
                        (SystemCoreClock)       links it; .data[0] is all-zero
                                                impure_data)
  CPU0 boot gate        0x00000004              0x00000004 or 0x00000005
  PHC NS_INCR for
    real time           40                      10
  ECC / CRC / FCSM      ECC on, CRC off,        ECC bypassed, CRC ON at reset,
                        FCSM recovery present   FCSM recovery STRIPPED

AND THE CONSEQUENCE THAT SHAPES EVERYTHING: ON THE ASIC THERE IS NEVER A
QUIESCENT BUS.  `cpu1_bootgate` is tied 1'b1, so CPU1 free-runs from power-on, and
cc_rom then releases CPU0.  Neither core can be held.  Any memory-integrity result
taken on the ASIC is taken from a LIVE system, so a word that changed between two
probes is INCONCLUSIVE, not a fault.  That is what `bus_quiescent` /
`bus_parkable` are for, and it is why the FPGA profile says the bus is not
quiescent EITHER (measured gate 0x00000004 -- CPU0 is loose there too) but IS
parkable, which the ASIC's is not.

USING IT FROM A TIER MODULE
===========================
    def hio_xxx(adp, rec):
        t = rec.target                      # always present; never None

        # 1. a target-independent assertion -- unchanged, always asserted
        rec.check("boot gate is not 0x00000000", v != 0, got=v)

        # 2. a target-dependent assertion -- degrades to record-and-flag
        rec.target_check("eth DMEM word 0 == the image's .data[0]",
                         v == t.eth_dmem_word0.value,
                         prop="eth_dmem_word0", got=v)

        # 3. a value the profile supplies
        if t.known("fabric_hz"):
            ...
        else:
            rec.target_defer("fabric frequency", prop="fabric_hz", got=measured)

`rec.target_check()` asserts when the property is KNOWN on this target and records
a deferral when it is not.  `rec.target_defer()` records unconditionally.  Both
land in the JSON under the test's `target_deferred` list and are counted in
`summary.target`.

This module imports NOTHING from harness.py -- harness imports it, not the other
way round.  Keep it that way or the tier modules' `from harness import ...` will
re-enter a half-initialised harness.
"""

from __future__ import annotations

import os


TARGETS_SCHEMA = "hostio4-target-profile/1"

# The reference vehicle every FPGA-calibrated constant in the suite was measured
# on.  `scale_cycles()` rescales an FPGA-derived cycle count against it.
FPGA_REF_HZ = 25_010_000
ASIC_REF_HZ = 100_000_000


# ---------------------------------------------------------------------------
# Expect -- one target-dependent expectation
# ---------------------------------------------------------------------------
class Expect(object):
    """One expectation, which may or may not be ASSERTABLE on this target.

        e.asserted   True  -> the caller SHOULD assert `e.matches(got)`
                     False -> the caller MUST record and flag instead
        e.values     tuple of acceptable values (empty when not asserted)
        e.reason     why it is not asserted, or what pins it when it is

    An Expect with no values is never `asserted`.  That is deliberate: the only
    way to get an assertion out of this object is to give it something to assert.
    """

    __slots__ = ("prop", "values", "reason", "_asserted")

    def __init__(self, prop, values=None, reason="", asserted=None):
        self.prop = prop
        if values is None:
            vs = ()
        elif isinstance(values, (list, tuple, set, frozenset)):
            vs = tuple(values)
        else:
            vs = (values,)
        self.values = vs
        self.reason = reason
        self._asserted = bool(vs) if asserted is None else (bool(asserted) and bool(vs))

    @property
    def asserted(self):
        return self._asserted

    @property
    def value(self):
        """The single expected value, or None when there is not exactly one."""
        return self.values[0] if len(self.values) == 1 else None

    def matches(self, got):
        """True/False when this is assertable; None when it is not.

        None is NOT False.  A caller that treats it as False has just turned a
        deferral back into a red, which is the whole bug this file prevents.
        """
        if not self._asserted:
            return None
        return got in self.values

    def to_dict(self):
        return {"property": self.prop,
                "asserted": self._asserted,
                "values": [fmt_prop(self.prop, v) for v in self.values],
                "reason": self.reason}

    def __repr__(self):
        return "<Expect %s %s %s>" % (
            self.prop, "ASSERT" if self._asserted else "record-only",
            [fmt_prop(self.prop, v) for v in self.values])


# Which properties are 32-bit BUS WORDS.  Only these render as hex.
#
# This is deliberately a whitelist and not "anything that looks big": rendering
# fabric_hz as 0x05F5E100 is the report-column-misread class of bug -- a reader
# glances at a hex frequency and reads a data word, or reads 100 MHz as some
# register value.  Frequencies are decimal, always, and the printed table spells
# out the MHz alongside.
WORD_PROPS = frozenset(("eth_dmem_word0", "cpu0_ran_marker", "bootgate_values"))
HZ_PROPS = frozenset(("fabric_hz", "phc_core_hz"))


def _word(v):
    if isinstance(v, int) and not isinstance(v, bool):
        return "0x%08X" % (v & 0xFFFFFFFF)
    return v


def fmt_prop(prop, v):
    """Render one property value for a record or a report.

    Bus words in hex, everything else in its own natural units.  Never guess
    from magnitude.
    """
    if v is None or isinstance(v, bool) or isinstance(v, str):
        return v
    if prop in WORD_PROPS:
        if isinstance(v, (list, tuple)):
            return [_word(x) for x in v]
        return _word(v)
    if isinstance(v, (list, tuple)):
        return [fmt_prop(prop, x) for x in v]
    return v


def _hexish(v):
    """Legacy scalar renderer, used only where no property name is in hand."""
    return v


# ---------------------------------------------------------------------------
# census classes -- mirrors tier1's, kept here so this module stands alone
# ---------------------------------------------------------------------------
CLS_D = "D"       # OK (no '!') AND non-zero data
CLS_Z = "Z"       # OK (no '!') AND exactly 0x00000000
CLS_DZ = "D/Z"    # OK (no '!'); the value is not constrained
CLS_E = "E"       # must report '!'
CENSUS_CLASSES = (CLS_D, CLS_Z, CLS_DZ, CLS_E)


# ---------------------------------------------------------------------------
# facts that belong to the DESIGN, not to the vehicle
# ---------------------------------------------------------------------------
class TargetIndependent(object):
    """Everything below is true on FPGA, on ASIC, and on a target nobody declared.

    These are RTL-grounded, cross-checked against both builds, and are asserted by
    EVERY profile including `unknown`.  Relaxing one of these is not "being
    careful about targets", it is deleting coverage -- so they live here, apart
    from the per-target table, and no profile can override them.
    """

    # cc_rom writes 4 to 0x29000000 on BOTH of its exit paths (byte offsets 0x4F4
    # and 0x528, the second being "every boot candidate failed"), and cc_rom is
    # identical on FPGA and ASIC -- no sim-divergence waiver, unanimous across all
    # 23 build pins.  There is no path that leaves the gate closed.
    bootgate_never_zero = True
    bootgate_upper_bits_zero = True        # HRDATA = {28'b0, remap_q}

    # eth ROM words 0..15 were audited against BOTH the instantiated FPGA RTL and
    # the ASIC eth_rom_via macro image.  They sit AHEAD of word 55, where the two
    # images first diverge, so they are valid on both.
    eth_rom_anchor_words = (0, 1, 2, 3, 11, 14, 15)
    eth_rom_word0_msp = 0x18003C00

    # CPU1's boot ROM (cc_rom) is identical on both targets: 13/0 clean, no waiver.
    cpu1_rom_identical_across_targets = True

    # phc_apb_regs.sv:18 DEFAULT_NS_INCR = 8'd4, commented "4 ns for 250 MHz" on a
    # design that has never run at 250 MHz.  Wrong on BOTH vehicles; the remedy is
    # firmware, not silicon.
    phc_ns_incr_reset_default = 4

    # The OK-vs-'!' boundary of the census is matrix routing: RTL, not vehicle.
    census_decode_class_is_target_independent = True

    @classmethod
    def to_dict(cls):
        return {k: getattr(cls, k) for k in dir(cls)
                if not k.startswith("_") and k != "to_dict"}


# Notes every profile carries, `unknown` included. A hazard that appears on two
# of three profiles will be missed on the third -- which is the one the operator
# who knows least is running.
_UNIVERSAL_NOTES = [
    "RUNNING TIER 2 DESTROYS ANY LOADED FIRMWARE. HIO-203/HIO-204 overwrite all "
    "32 KB of eth IMEM and HIO-208 carpets shared SRAM, and NOTHING in tiers 0-4 "
    "pulses CPU0_SWRST to restart the core afterwards. So a firmware-dependent "
    "test (tier 5, and anything reading a firmware witness) must run BEFORE "
    "tier 2 in a power cycle, or the image must be reloaded after it with "
    "scripts/rig/eth_chiplet/hostio_fw/fw_load.py. Ordering is not a "
    "preference here; a tier-5 run after a tier-2 run is measuring a wiped die.",

    "THE WRITE-PATH CONTROL IS NOT A RAM WORD, deliberately. It is the QSPI "
    "ADDR scratch at 0x2100000C: reg [31:0] reg3, written unmasked "
    "(apb_qspi_regs.v:188) and read back whole and combinationally (:220), so "
    "any 32-bit tag round-trips exactly -- the reg3[21:0] narrowing at :136 is "
    "on the derived OUTPUT PORT to the flash controller and is not observable "
    "over APB. It is in NO core's instruction fetch, and it cannot start a "
    "flash transaction: that needs the CMD enable bit, which the tier module "
    "guards. Better still, qspi_controller_mux.v:55-63 muxes EVERY APB control "
    "input -- CMD, ENABLE, READ, WRITE, ADDR_EN, ADDR, WDATA -- away from the "
    "flash controller whenever XIP_ACTIVE is 1, which is the FPGA's measured "
    "state (CTRL = 0x00000100). So on the vehicle where XiP is armed the APB "
    "path is not merely idle, it is disconnected.",
]


# ---------------------------------------------------------------------------
# Target
# ---------------------------------------------------------------------------
class Target(object):
    """One vehicle the suite can be pointed at.

    Every property is either a concrete value or None.  **None means UNKNOWN ON
    THIS TARGET, and unknown means do not assert** -- it never means zero, false,
    or "assume the FPGA".  `known(prop)` is the only correct way to ask.
    """

    # --- the property table -------------------------------------------------
    # name -> (default, one-line meaning).  Anything not here is not a profile
    # property and cannot be set by an override, which is what stops a typo'd
    # env knob from silently doing nothing.
    PROPS = {
        # identity
        "kind":                      (None, "'fpga' | 'asic' | 'unknown'"),
        "label":                     (None, "human-readable vehicle name"),
        "description":               ("",   "one paragraph, for the record"),

        # clocks
        "fabric_hz":                 (None, "HCLK/fabric frequency in Hz"),
        "fabric_hz_tol":             (0.01, "fractional tolerance for a measured "
                                            "comparison against fabric_hz"),
        "phc_core_hz":               (None, "clock feeding the PHC (defaults to "
                                            "fabric_hz)"),
        "phc_ns_incr_for_realtime":  (None, "NS_INCR that makes the PHC keep real "
                                            "time: NS_INCR x f = 1e9"),

        # boot image / memory identity
        "eth_rom_image":             (None, "'smoke_remap' (FPGA) | "
                                            "'stage0_bootrom' (ASIC)"),
        "eth_dmem_word0":            (None, "expected eth DMEM word 0, or None"),
        "cpu0_ran_marker":           (None, "a word that WITNESSES CPU0 execution "
                                            "on this image, or None if the image "
                                            "provides no witness"),
        "bootgate_values":           (None, "tuple of boot-gate words that are "
                                            "healthy at power-on. It judges a "
                                            "NON-ZERO gate only -- a ZERO is "
                                            "judged by flash_provisioned, and "
                                            "gating a zero on THIS property "
                                            "reds a healthy no-flash board"),

        # the bus
        "bus_quiescent":             (None, "is the bus quiet while the suite "
                                            "runs?"),
        "bus_parkable":              (None, "CAN it be made quiet at all?"),
        "cpu1_free_running":         (None, "cpu1_bootgate tied 1'b1?"),

        # link configuration -- differs between the two builds on all three
        "ecc_enabled":               (None, "TideLink ECC active"),
        "crc_enabled_at_reset":      (None, "TideLink CRC on at reset"),
        "fcsm_recovery_present":     (None, "FCSM recovery logic built in"),

        # census
        "census_overlay":            (None, "{addr: (class, reason)} -- OVERRIDES "
                                            "the base table, never replaces it"),
        "census_value_class_asserted": (None, "assert the D/Z value class, or only "
                                              "the OK-vs-'!' decode class?"),

        # things a test needs that are properties of the VEHICLE, discovered
        # while auditing the tiers (see tp_TIER_MIGRATION.md)
        "write_path_control_addr":   (None, "a word that is safe to use as a "
                                            "write-path POSITIVE CONTROL. It must "
                                            "not be reachable by ANY core's "
                                            "instruction fetch or data path -- see "
                                            "the note on both profiles"),
        "write_path_control_tag":    (None, "the value that control writes. Must "
                                            "read back EXACTLY at that address"),
        "rom_distinct_offsets":      (None, "{rom name: byte offset} at which the "
                                            "ROM image is known to differ from "
                                            "offset 0 -- the DISTINCT-DATA control"),
        "subword_rmw_supported":     (None, "does a byte write into a protected "
                                            "macro read-modify-write correctly? "
                                            "CRC-at-reset makes this a real "
                                            "question on the ASIC"),
        # A BOARD FACT, NOT A DIE FACT. The same silicon in two sockets can
        # have flash fitted-and-programmed in one and bare pads in the other, so
        # NO PROFILE DECLARES IT -- every profile leaves it None and the operator
        # says so per run:
        #     --target-set flash_provisioned=0   (no flash / not programmed)
        #     --target-set flash_provisioned=1   (flash fitted AND programmed)
        #     HOSTIO_FLASH_PROVISIONED=0|1
        #
        # WHAT IT IS FOR. cc_rom writes 0x4 to the CPU0 boot gate at 0x29000000 on
        # EVERY terminating path -- verified at mask geometry -- so a healthy fresh
        # die reads 0x00000004 or 0x00000005. But on a board with NO QSPI FLASH,
        # ZERO IS THE CORRECT READING: CPU1 HardFaults on xip_enable()'s warm-up
        # read of 0x24000000 and parks in `b .` at 0x080001CE, reaching NEITHER
        # cc_rom store site. A first-silicon board very likely has unprovisioned
        # flash, so "the gate is non-zero" is not a safe assertion to make blind.
        #
        # THE TRAP THIS PROPERTY EXISTS TO CLOSE, and the reason it had to be added
        # rather than borrowed: `bootgate_values` IS `known` on asic_tsmc65, so a
        # naive rec.target_check(prop="bootgate_values") on a zero gate PASSES ITS
        # GUARD and still reds the healthy no-flash board. AN ESTABLISHED PROPERTY
        # IS NOT AUTOMATICALLY THE RIGHT PROPERTY TO GATE ON. The guard only asks
        # "is this property declared?"; it cannot ask "is this property the one
        # that answers the question?" -- that is the author's job, here, once.
        #
        # AND THE FALSY-None TRAP, which bites in the WORSE direction than
        # eth_imem_live_code's. `if t.flash_provisioned:` reads unknown as "no
        # flash fitted" and would EXCUSE a genuine rung-4 contradiction: a vacuous
        # green, which CONTRACT.md names as the specific failure this suite exists
        # to prevent. Never read the raw property in a branch condition. Use
        # flash_absence_explains_zero_bootgate() and
        # flash_presence_makes_zero_bootgate_a_finding(); each is true only on an
        # EXPLICIT declaration, so unknown licenses neither the excuse nor the red.
        "flash_provisioned":         (None, "BOARD FACT, per socket, not per die: "
                                            "is QSPI flash fitted AND carrying a "
                                            "CRC-valid image? None = UNDECLARED, "
                                            "and undeclared must DEFER -- it is "
                                            "the only property that says whether "
                                            "a ZERO boot gate is expected"),

        # RUN-TIME STATE, NOT A DIE PROPERTY. Whether eth IMEM holds live code
        # depends on whether anyone loaded an image THIS POWER CYCLE, and a
        # debug operation can flip it at any moment. None therefore means
        # "unknown -- assume code MAY be live", the SAFE reading, and the only
        # value that permits an overwrite is an explicit False. Use
        # eth_imem_safe_to_overwrite(); `if t.eth_imem_live_code:` is falsy on
        # None and reads "unknown" as "safe", which is backwards.
        "eth_imem_live_code":        (None, "RUN-TIME: is a core fetching from eth "
                                            "IMEM right now? None = unknown, and "
                                            "unknown must be treated as YES"),
        "timer0_owned_by_firmware":  (None, "does firmware own cc_periph timer0? "
                                            "If so, HIO-405/406 fight it"),
        "dma_powered":               (None, "is the DMA-250 powered, or gated "
                                            "(IIDR reads 0)?"),
        "phy_oui":                   (None, "the fitted PHY's 22-bit OUI, or None "
                                            "when no PHY is named for this board"),
        "fcsm_state_map":            (None, "which build the TideLink FCSM decode "
                                            "was derived from. The bit packing and "
                                            "the state meanings are a property of "
                                            "the CONFIGURED RTL, and the ASIC "
                                            "strips FCSM recovery"),

        # poll / timer budgets -- wall-clock windows expressed in fabric cycles,
        # so they shrink 4x on the faster clock unless they are scaled
        "poll_budget":               (None, "ADP `P` iteration budget. A COUNT, so "
                                            "the wall window it buys shrinks as "
                                            "the clock rises"),
        "timer_reload":              (None, "HIO-406 timer preload. 0x18000000 is "
                                            "16.1 s at 25.010 MHz but 4.03 s at "
                                            "100 MHz"),
        "timer_poll_budget":         (None, "HIO-406 poll budget; must exceed "
                                            "timer_reload / cycles-per-poll-read"),

        # run shaping
        "soak_seconds":              (60,   "HIO-211 soak length"),
        "perf_clr_floor_seconds":    (5.0,  "HIO-307's counter-bound floor, "
                                            "expressed in SECONDS. The suite "
                                            "hard-codes it as 500,000,000 cycles, "
                                            "which is 5 s at 100 MHz and 20 s at "
                                            "25.010 MHz -- an unnamed clock-rate "
                                            "assumption. Multiply by fabric_hz."),

        # SUITE PORTING to a vehicle that is not the eth chiplet at all (the
        # NanoSoC compute chiplet on HAPS-SX). Empty on every eth profile, so
        # they change nothing there. Every one of them is RECORDED in the run
        # record (target.module_overrides_applied, and SKIP reasons per test).
        "test_skips":                ({}, "{test id: reason} -- tests that do not "
                                          "apply to this vehicle. They report SKIP "
                                          "with the reason; never PASS"),
        "test_bodies":               ({}, "{test id: 'module:function'} -- a "
                                          "vehicle-specific BODY for a test whose "
                                          "role (control, gating) carries over but "
                                          "whose addresses do not. Same id, same "
                                          "gates; the record names the body run"),
        "module_overrides":          ((), "((module, attr, value, why), ...) -- "
                                          "tier-module constants re-pointed at this "
                                          "vehicle's map. Applied unconditionally "
                                          "and recorded, unlike MODULE_BINDINGS"),
        "write_forbid":              ((), "((lo, hi, why), ...) -- address ranges "
                                          "Adp.write() refuses on this vehicle, "
                                          "whatever a tier module's own guard says"),

        # provenance
        "settled_absent":            (None, "{prop: why} for properties whose None "
                                            "is an ESTABLISHED FINDING, not a gap. "
                                            "Everything else that is None is an "
                                            "OPEN QUESTION someone can answer."),
        "sources":                   (None, "where each number above came from"),
        "notes":                     (None, "free text carried into the record"),
    }

    # THE THIRD KIND OF None. `to_dict()` already separates an OPEN QUESTION (a
    # person can go and measure it) from an ESTABLISHED ABSENCE (someone did, and
    # the answer is "there is none"). Neither describes a property whose answer
    # does not belong to the VEHICLE at all: whether flash is fitted in THIS
    # socket, or whether anyone loaded an image THIS power cycle. Filing those
    # under "open questions" invites the fix that must never happen -- somebody
    # "closing the gap" by writing a constant into a profile, which then answers
    # for every board that profile is ever pointed at.
    #
    # They are not a licence either: they are None, `known()` says so, and every
    # assertion resting on them still DEFERS. What changes is only WHO is being
    # asked -- the operator at the bench, per run, not the author of the profile.
    OPERATOR_DECLARED = frozenset((
        "flash_provisioned",        # per socket: is QSPI flash fitted + programmed?
        "eth_imem_live_code",       # per power cycle: did anyone load an image?
    ))

    def __init__(self, name, **kw):
        self.name = name
        self.overrides = {}            # prop -> {"from": ..., "to": ..., "via": ...}
        self.override_conflicts = []   # human-readable strings
        unknown = [k for k in kw if k not in self.PROPS]
        if unknown:
            raise ValueError(
                "Target(%r): unknown propert%s %s. The property table in "
                "Target.PROPS is the contract -- add it there first, so a typo "
                "cannot silently become a no-op."
                % (name, "y" if len(unknown) == 1 else "ies",
                   ", ".join(sorted(unknown))))
        for prop, (default, _doc) in self.PROPS.items():
            setattr(self, prop, kw.get(prop, default))
        if self.phc_core_hz is None:
            self.phc_core_hz = self.fabric_hz
        if self.census_overlay is None:
            self.census_overlay = {}
        if self.rom_distinct_offsets is None:
            self.rom_distinct_offsets = {}
        if self.sources is None:
            self.sources = {}
        if self.settled_absent is None:
            self.settled_absent = {}
        self.notes = list(self.notes or []) + list(_UNIVERSAL_NOTES)
        if self.label is None:
            self.label = name
        self.independent = TargetIndependent

    # -- interrogation -------------------------------------------------------
    def known(self, prop):
        """Is `prop` established on this target?  The ONLY correct guard."""
        if prop not in self.PROPS:
            raise KeyError(
                "%r is not a target property (see Target.PROPS). Asking about a "
                "property that does not exist would always answer 'unknown', and "
                "a guard that is always false silently deletes the assertion "
                "behind it." % prop)
        return getattr(self, prop) is not None

    def get(self, prop, default=None):
        v = getattr(self, prop, None) if prop in self.PROPS else None
        return default if v is None else v

    @property
    def is_unknown(self):
        return self.kind == "unknown"

    # -- expectations --------------------------------------------------------
    def expect(self, prop, reason=None):
        """The expectation for `prop` on this target, as an `Expect`.

        Assertable when the property is known; record-only when it is not.
        """
        if prop not in self.PROPS:
            raise KeyError("%r is not a target property (see Target.PROPS)" % prop)
        v = getattr(self, prop)
        if v is None:
            return Expect(prop, None,
                          reason or ("%s is not established on target %r -- "
                                     "recorded, not asserted" % (prop, self.name)))
        if isinstance(v, Expect):
            return v
        return Expect(prop, v, reason or self.sources.get(prop, ""))

    # -- clock arithmetic ----------------------------------------------------
    def scale_cycles(self, n, ref_hz=FPGA_REF_HZ):
        """Rescale a cycle count calibrated at `ref_hz` to this target's clock.

        Returns None when the clock is unknown -- and None must not be quietly
        turned back into `n`.  A timeout scaled by "I assumed the FPGA" is the
        FPGA-calibration bug wearing a helmet.
        """
        if self.fabric_hz is None:
            return None
        return int(round(n * (float(self.fabric_hz) / float(ref_hz))))

    def seconds_for_cycles(self, n):
        if self.fabric_hz is None:
            return None
        return float(n) / float(self.fabric_hz)

    def cycles_for_seconds(self, s):
        if self.fabric_hz is None:
            return None
        return int(round(float(s) * self.fabric_hz))

    def eth_imem_safe_to_overwrite(self):
        """True ONLY on an explicit `eth_imem_live_code = False`.

        `None` -- nobody has declared it -- returns False, because "no one told
        me" and "no core is running there" are not the same claim, and a loader
        can make the second one false between one test and the next.
        """
        return self.eth_imem_live_code is False

    def flash_absence_explains_zero_bootgate(self):
        """True ONLY on an explicit `flash_provisioned = False`.

        This is the accessor that licenses the BENIGN reading of a zero boot
        gate: no flash on the board, so CPU1 HardFaulted in xip_enable() and
        never reached either cc_rom store site, so nothing ever wrote the gate.

        `None` -- nobody declared it -- returns False, and it must. The falsy-None
        trap bites HARDER here than it does on eth_imem_live_code: there, reading
        unknown as "safe" risks a corrupted image; here, `if t.flash_provisioned:`
        reads unknown as "no flash fitted" and would EXCUSE the one zero that IS a
        silicon finding. That is a vacuous green, which CONTRACT.md names as the
        specific failure mode this suite exists to prevent.
        """
        return self.flash_provisioned is False

    def flash_presence_makes_zero_bootgate_a_finding(self):
        """True ONLY on an explicit `flash_provisioned = True`.

        The mirror, and it is a SEPARATE accessor rather than
        `not flash_absence_explains_zero_bootgate()` on purpose: the negation
        would be true on an UNDECLARED board and would turn the healthy
        first-silicon reading red, which is the exact bug this property was added
        to prevent. Both accessors are false when nobody has declared anything,
        and that is what makes the third state -- DEFER -- reachable at all.
        """
        return self.flash_provisioned is True

    def perf_counter_saturation_seconds(self, width_bits=32):
        """How long P0_CYC takes to saturate from a fresh CLR.

        171.7 s at 25.010 MHz, 42.95 s at 100 MHz -- the biggest silent clock
        dependency in Tier 4, because a saturated counter turns HIO-402 from a
        measurement into a SKIP four times sooner on the ASIC.
        """
        if self.fabric_hz is None:
            return None
        return float((1 << width_bits) - 1) / float(self.fabric_hz)

    def fabric_hz_holds(self, measured_hz):
        """Does a measured frequency match this target, within tolerance?

        None when the target has no declared frequency.
        """
        if self.fabric_hz is None or measured_hz is None:
            return None
        return abs(float(measured_hz) - self.fabric_hz) <= self.fabric_hz_tol * self.fabric_hz

    # -- census --------------------------------------------------------------
    def census_class(self, addr, base_class):
        """Effective census class for `addr`, given the tier's BASE class.

        The overlay OVERRIDES the base table entry by entry; it never replaces
        the table, so an address the profile says nothing about keeps the class
        the tier declared.  Returns (class, reason_or_None) -- reason is non-None
        exactly when something changed.

        Two separate mechanisms, and they compose in this order:
          1. a per-target overlay entry, if there is one for this address;
          2. `census_value_class_asserted is False` (the `unknown` target), which
             demotes any surviving hard-D to D/Z.  The OK-vs-'!' decode class is
             NEVER demoted -- that boundary is matrix routing, i.e. RTL, and is
             target-independent, so it stays asserted even on an unknown target.
        """
        cls, reason = base_class, None
        ov = self.census_overlay.get(addr)
        if ov is not None:
            new, why = (ov if isinstance(ov, (tuple, list)) else (ov, ""))
            if new not in CENSUS_CLASSES:
                raise ValueError("census overlay for 0x%08X on target %s gives %r, "
                                 "which is not one of %s"
                                 % (addr, self.name, new, ", ".join(CENSUS_CLASSES)))
            if new != cls:
                reason = ("target %s overrides the base class %s -> %s: %s"
                          % (self.name, cls, new, why))
            cls = new
        if self.census_value_class_asserted is False and cls == CLS_D:
            cls = CLS_DZ
            reason = ("target %s does not assert the census VALUE class (the "
                      "OK-vs-'!' decode class is still asserted): a non-zero "
                      "requirement at this address depends on which image is "
                      "loaded and on block power state, neither of which is "
                      "established on an undeclared target" % self.name)
        return cls, reason

    # -- overrides -----------------------------------------------------------
    def override(self, prop, value, via="override"):
        """Set one property, keeping a record of what it was and where it came from.

        Per-test / per-rig overrides are legitimate -- an operator who has parked
        CPU1 knows something the profile does not.  What is NOT legitimate is an
        override that leaves no trace, so every one of them lands in the run
        record and a self-contradicting one is flagged as well as applied.
        """
        if prop not in self.PROPS:
            raise KeyError("%r is not a target property (see Target.PROPS)" % prop)
        old = getattr(self, prop)
        if old == value:
            return self
        setattr(self, prop, value)
        self.overrides[prop] = {"from": fmt_prop(prop, old),
                                "to": fmt_prop(prop, value), "via": via}
        if prop == "bus_quiescent" and value is True and self.bus_parkable is False:
            self.override_conflicts.append(
                "bus_quiescent was forced True via %s, but target %s declares the "
                "bus is NOT PARKABLE (cpu1_bootgate is tied 1'b1, so CPU1 cannot be "
                "held, and cc_rom releases CPU0). The override is honoured -- an "
                "operator may have halted the cores through another path -- but any "
                "memory-integrity PASS that rests on it is only as good as that "
                "claim." % (via, self.name))
        if prop == "fabric_hz":
            self.phc_core_hz = self.phc_core_hz if "phc_core_hz" in self.overrides \
                else value
        return self

    # -- the record ----------------------------------------------------------
    def to_dict(self):
        d = {"schema": TARGETS_SCHEMA, "name": self.name}
        for prop in sorted(self.PROPS):
            v = getattr(self, prop)
            if prop == "census_overlay":
                d[prop] = dict(("0x%08X" % a,
                                list(x) if isinstance(x, (tuple, list)) else [x, ""])
                               for a, x in (v or {}).items())
            elif isinstance(v, Expect):
                d[prop] = v.to_dict()
            elif isinstance(v, dict):
                d[prop] = dict((str(k), x) for k, x in v.items())
            else:
                d[prop] = fmt_prop(prop, v)
        d["overrides"] = dict(self.overrides)
        d["override_conflicts"] = list(self.override_conflicts)
        d["target_independent"] = TargetIndependent.to_dict()
        # THE TWO KINDS OF None, kept apart on purpose. An open question is
        # something a person can go and measure; an established absence is a
        # result. Collapsing them invites someone to "fill in the gap" by
        # guessing a value that was determined not to exist.
        unknown = sorted(p for p in self.PROPS if getattr(self, p) is None)
        d["open_questions"] = [p for p in unknown
                               if p not in self.settled_absent
                               and p not in self.OPERATOR_DECLARED]
        d["established_absent"] = dict(
            (p, self.settled_absent[p]) for p in unknown if p in self.settled_absent)
        # THE THIRD KIND (see Target.OPERATOR_DECLARED): not a gap in the profile,
        # because no profile can ever close it. The operator declares it per run.
        d["operator_declared_unknown"] = [p for p in unknown
                                          if p in self.OPERATOR_DECLARED]
        d["unknown_properties"] = unknown          # kept: ALL THREE kinds, as before
        return d

    def summary_line(self):
        f = ("%.3f MHz" % (self.fabric_hz / 1e6)) if self.fabric_hz else "clock UNKNOWN"
        q = {True: "bus quiescent", False: "bus LIVE",
             None: "bus quiescence UNKNOWN"}[self.bus_quiescent]
        return "%s (%s) -- %s, ROM %s, %s" % (
            self.name, self.label, f, self.eth_rom_image or "UNDECLARED", q)

    def __repr__(self):
        return "<Target %s>" % self.name


# ===========================================================================
# THE PROFILES
# ===========================================================================
def _fpga_kr260():
    t = Target(
        "fpga_kr260",
        kind="fpga",
        label="KR260 FPGA, kr260-eth-chiplet build",
        description=(
            "The vehicle every constant in this suite was originally calibrated "
            "on. Its readings are the reference, NOT the definition of correct: "
            "several of them are properties of this board and this firmware "
            "image rather than of the design."),
        fabric_hz=25_010_000,
        fabric_hz_tol=0.01,
        phc_ns_incr_for_realtime=40,
        eth_rom_image="smoke_remap",
        eth_dmem_word0=0x05F5E100,
        cpu0_ran_marker=0x05F5E100,
        bootgate_values=(0x00000004,),
        # CPU0 IS RELEASED here too -- measured gate 0x00000004 -- so the bus is
        # NOT quiet by default. The difference from the ASIC is that it CAN be
        # made quiet, which HOSTIO_CPU1_PARKED=1 declares.
        bus_quiescent=False,
        bus_parkable=True,
        cpu1_free_running=True,
        ecc_enabled=True,
        crc_enabled_at_reset=False,
        fcsm_recovery_present=True,
        census_value_class_asserted=True,
        # NOT an eth IMEM word. See the shared note below -- this was
        # 0x10001000 and that was a hazard, not a convenience.
        write_path_control_addr=0x2100000C,
        write_path_control_tag=0x0BADC0DE,
        rom_distinct_offsets={"eth_rom": 0x0E4, "cpu1_rom": 0x0E4},
        subword_rmw_supported=True,
        # NOT False. An operator can load an image into eth IMEM over the ADP
        # `U` command and pulse CPU0_SWRST at any point in a power cycle, and
        # that is a normal bring-up action, not an exotic one. The old False
        # asserted a run-time fact that a debug operation invalidates.
        eth_imem_live_code=None,
        timer0_owned_by_firmware=False,
        dma_powered=True,
        phy_oui=0x0007C0,
        fcsm_state_map="fpga_ip",
        poll_budget=0x00100000,
        timer_reload=0x18000000,
        timer_poll_budget=0x20000000,
        census_overlay={
            0x18000000: (CLS_D,
                         "smoke_remap links SystemCoreClock, so .data[0] is "
                         "0x05F5E100 and eth DMEM word 0 carries real data"),
            # A STRENGTHENING, not a relaxation. tier1's _D_ZERO_OK tolerates a
            # zero here unconditionally, on the theory that the DMA might be
            # power-gated. On THIS build it is not: IIDR reads 0x2500043b. So the
            # non-zero requirement is real here and the tolerance is dead weight
            # -- the overlay exists to sharpen a class as well as to soften one.
            0x20000FC8: (CLS_D,
                         "DMA-250 is PRESENT and powered on this build (IIDR = "
                         "0x2500043b, HIO-124 PASS in three run records), so a "
                         "zero at the IIDR would be a real finding, not the "
                         "documented power-gated symptom"),
        },
        soak_seconds=60,
        sources={
            "fabric_hz": "MEASURED 2026-08-25: P0_CYC delta 492,193,491 over a "
                         "host-timed 19.680 s = 25.010 MHz; routed timing report "
                         "says 25.011 MHz (0.004% apart)",
            "phc_ns_incr_for_realtime":
                "MEASURED both directions on the die: NS_INCR=4 -> 0.1000x real "
                "time; NS_INCR=40 (0x28 at 0x22000008) -> 1.0004x; restored "
                "cleanly. 40 x 25.010e6 = 1.0004e9",
            "eth_rom_image": "the FPGA build loads smoke_remap",
            "eth_dmem_word0":
                "golden_fpga_reference.json stable_constants -- 0x05F5E100 is a "
                "FIRMWARE BUILD CONSTANT (SystemCoreClock, defaulted to 100 MHz "
                "in nanosoc_multicore_addrmap.h). It is NOT a clock-rate "
                "register: the fabric measures 25.010 MHz, so this word says the "
                "loaded image was built for the wrong clock",
            "bootgate_values": "measured 0x00000004 on this build -- CPU1 found "
                               "no boot candidate. 0x00000005 would also be "
                               "healthy if flash were provisioned",
            "write_path_control_addr":
                "WAS 0x10001000 (eth IMEM), justified on the premise that eth "
                "IMEM is empty. THAT PREMISE IS FALSE: a 1128-byte image was "
                "loaded at 0x10000000 over the ADP `U` command and CPU0 was "
                "pulsed and ran it, writing shared SRAM at ~1 kHz. The write "
                "landed past that image's .text+.bss and corrupted nothing -- "
                "which is luck about one image's size, not a property of the "
                "profile, and a larger image reaches it. The address is used by "
                "HIO-313, ABORT GATE 8, whose job is to prove the write path "
                "before the IRREVERSIBLE CPU0 release: a control that can "
                "perturb a running core is the wrong control.",
            "eth_imem_live_code":
                "WAS False, MEASURED empty on this die 2026-08-25. That is a "
                "run-time fact with a shelf life, not a die property -- see the "
                "property comment. Now None (unknown, assume live); the loader "
                "at hostio_fw/fw_load.py, or HOSTIO_ETH_IMEM_LIVE, can declare "
                "it per run.",
            "dma_powered":
                "MEASURED PRESENT. 0x20000FC8 (IIDR) = 0x2500043b, read "
                "independently with an ad-hoc client AND reported by HIO-124 "
                "(dma250_state = PRESENT) in t1b.json and tf1.json and by "
                "HIO-411 (dma_power_gated = False) in tf4.json. "
                "THIS PROPERTY WAS WRONG (False) IN THE FIRST VERSION OF THIS "
                "PROFILE, and the mechanism is worth keeping written down: it was "
                "inferred from golden_fpga_reference.json's '0x20000000: "
                "0x00000000'. That address is SCFG_CHSEC0, not the IIDR, and "
                "HIO-124's own purpose text names that exact inference as invalid "
                "-- 'its zero value is also what a dead bus returns, so the "
                "measured 0x20000000 -> 0x00000000 proves nothing about the DMA. "
                "This test is what settles it.' The test had settled it, in the "
                "run records, and the profile did not look.",
            "ecc_enabled": "docs: FPGA is ECC on, CRC off, FCSM recovery present "
                           "-- the ASIC netlist is the opposite on all three",
            "flash_provisioned":
                "None here too, and for the same reason as on the ASIC: it is a "
                "BOARD fact, not a build fact, so even the vehicle every constant "
                "in this suite was calibrated on cannot declare it for the next "
                "board of the same kind. What IS known about this one is a "
                "CONSEQUENCE, not the property: the gate measured 0x00000004 -- "
                "CPU1 ran, found no boot candidate, and released CPU0 -- so on "
                "the day of that run the flash was not carrying a CRC-valid "
                "image. That is a reading, and it expires; declare the property "
                "per run rather than freezing the reading into the profile.",
        },
        notes=[
            "eth DMEM word 0 = 0x05F5E100 is a firmware build constant and a "
            "4x clock mismatch: the image was built for 100 MHz and the fabric "
            "runs at 25.010 MHz, which also implies a 4x UART baud mismatch. "
            "Never quote it as a hardware rate.",
            "MDIO does not work on this board and a LAN8720 IS fitted: the fault "
            "is FPGA board/XDC integration (PMOD ball mapping), not the MAC. "
            "Nothing about it transfers to the ASIC.",
            "A PROFILE VALUE IS A CLAIM ABOUT A DIE, so it is settled by RUN "
            "RECORDS, not by reading the test that would have measured it. Every "
            "property here that a test already reports should be filled in from "
            "that test's recorded value -- see the dma_powered source above for "
            "what happens otherwise.",
        ],
    )
    return t


def _asic_tsmc65():
    t = Target(
        "asic_tsmc65",
        kind="asic",
        label="eth chiplet, TSMC65 silicon",
        description=(
            "First silicon. The suite has never run here. Everything below is "
            "derived from the build configuration and the ROM images, NOT from a "
            "measurement on a die -- so where the ASIC value is genuinely not "
            "established, the property is left None and the assertion defers."),
        fabric_hz=100_000_000,
        fabric_hz_tol=0.02,
        phc_ns_incr_for_realtime=10,
        eth_rom_image="stage0_bootrom",
        eth_dmem_word0=0x00000000,
        # There is NO witness of CPU0 execution in this image. Saying so
        # explicitly is the point: the FPGA's 0x05F5E100 anchor went RED on a
        # healthy ASIC die when the gate was open, and VACUOUSLY GREEN when it
        # was shut -- the false-red and the false-green in one assertion.
        cpu0_ran_marker=None,
        settled_absent={
            "cpu0_ran_marker":
                "ESTABLISHED ABSENT, not unmeasured. stage0_bootrom offers no "
                "witness of CPU0 execution: .data[0] is impure_data (all-zero "
                "init) and the image never links SystemCoreClock, so 0x05F5E100 "
                "cannot appear. Do not fill this in -- a value here would "
                "resurrect the assertion that went RED on a healthy ASIC die "
                "when the gate was open and VACUOUSLY GREEN when it was shut. "
                "Closing the hole needs a Tier-5 firmware token or an image "
                "whose .data[0] is non-zero, not a wider constant.",
        },
        bootgate_values=(0x00000004, 0x00000005),
        bus_quiescent=False,
        bus_parkable=False,
        cpu1_free_running=True,
        ecc_enabled=False,
        crc_enabled_at_reset=True,
        fcsm_recovery_present=False,
        census_value_class_asserted=True,
        # The SAME control as the FPGA, and for the same reason: the QSPI ADDR
        # scratch is on a decode arm present on both vehicles and is in no
        # core's instruction fetch. This was None -- forcing ABORT GATE 8 to
        # defer on silicon -- only because the FPGA's control was an eth IMEM
        # word that could not be borrowed. Moving the FPGA off IMEM closes the
        # ASIC gap as a side effect.
        write_path_control_addr=0x2100000C,
        write_path_control_tag=0x0BADC0DE,
        # cc_rom releases CPU0, so eth IMEM is (or becomes) live instruction
        # memory. The exact argument that makes HIO-508 refuse CPU1 IMEM now
        # applies to eth IMEM here.
        eth_imem_live_code=True,
        timer0_owned_by_firmware=None,
        dma_powered=None,
        phy_oui=None,
        # None, NOT "asic_config": the FCSM bit packing and state meanings were
        # derived from the FPGA IP package, and this build STRIPS FCSM recovery.
        # Until someone re-derives them from the configured RTL there is no map,
        # and every check that decodes below the marker must defer.
        fcsm_state_map=None,
        # 4x the FPGA count buys the SAME WALL WINDOW at 4x the clock. A budget
        # is a cycle count, so leaving it alone quietly quarters the patience of
        # every `P` that waits for an external event.
        poll_budget=0x00400000,
        timer_reload=0x60000000,
        timer_poll_budget=0x80000000,
        # cc_rom is identical on both targets (13/0 clean, no waiver), so CPU1's
        # 0xE4 handle transfers. The eth ROM's does NOT: 172 of 320 words differ
        # and nobody has checked word 57 on stage0_bootrom.
        rom_distinct_offsets={"cpu1_rom": 0x0E4},
        subword_rmw_supported=None,
        census_overlay={
            0x18000000: (CLS_DZ,
                         "stage0_bootrom's .data[0] is impure_data -- an all-zero "
                         "initialiser -- and the image does not link "
                         "SystemCoreClock, so 0x00000000 is the HEALTHY reading. "
                         "The decode is still asserted; only the non-zero "
                         "requirement is dropped"),
        },
        soak_seconds=60,
        sources={
            "fabric_hz": "ASIC/common.mk CLK_PERIOD = 10.0 ns",
            "phc_ns_incr_for_realtime":
                "NS_INCR x f = 1e9; 10 x 100e6 is exact, so no NS_INCR_FRAC is "
                "needed. PROVEN ON FPGA ONLY -- the ASIC instantiates the same "
                "IP with the same parameter, but this has not been tested on "
                "silicon",
            "eth_rom_image": "stage0_bootrom -- 172 of 320 words differ from the "
                             "FPGA's smoke_remap, first divergence at word 55. "
                             "Formally waived upstream: eth.json carries an "
                             "allow_sim_divergence allowlist entry",
            "eth_dmem_word0": ".data[0] is impure_data, all-zero init; the image "
                              "never links SystemCoreClock",
            "bootgate_values": "cc_rom (stage0_bootrom_chip_core) writes 0x4 to "
                               "0x29000000 on EVERY terminating path -- VERIFIED "
                               "AT MASK GEOMETRY in build/rom_verify/cc_gds.bits "
                               "at byte offsets 0x4F4 and 0x528 (0x528 is the "
                               "'every boot candidate failed' path). 0x00000004 = "
                               "no boot candidate (unprovisioned flash, the "
                               "expected first-silicon case); 0x00000005 = CPU1 "
                               "loaded and booted an app, bit0 also mapping CPU1 "
                               "address 0 to IMEM. 0x00000000 IS NOT SIMPLY "
                               "AN ANOMALY -- CORRECTED 2026-08-26. On a board "
                               "with NO QSPI FLASH it is the EXPECTED reading: "
                               "CPU1 HardFaults on xip_enable()'s warm-up read "
                               "(b . at 0x080001CE) and reaches NEITHER cc_rom "
                               "site, so the gate is never written. A zero "
                               "resolves into four distinct states and only one "
                               "is a silicon fault -- HIO-106 runs an 8-read "
                               "boot ladder to separate them. DO NOT GATE ON "
                               "bootgate_values FOR A ZERO: this property is "
                               "`known` here, so the guard passes and a healthy "
                               "no-flash die reds. flash_provisioned is the "
                               "property that discriminates, and HIO-106 now "
                               "gates the zero on IT (added 2026-08-26). This "
                               "property still judges the NON-ZERO reading, and "
                               "only that.",
            "flash_provisioned":
                "DELIBERATELY None, on this profile and on every other, and it is "
                "NOT an open question a profile can close: it is a fact about the "
                "SOCKET, not about the silicon. The same die reads a healthy "
                "0x00000000 on a board with bare QSPI pads and a healthy "
                "0x00000004 once flash is fitted and programmed. The operator "
                "declares it per run (--target-set flash_provisioned=0|1, or "
                "HOSTIO_FLASH_PROVISIONED), and an undeclared board DEFERS -- "
                "which is the correct first-silicon outcome, because a first "
                "board very likely has unprovisioned flash and an assertion of "
                "'non-zero' would red a healthy die on the first test of the "
                "first chip.",
            "bus_quiescent": "cpu1_bootgate is tied 1'b1 so CPU1 free-runs from "
                             "power-on, and cc_rom releases CPU0. There is no "
                             "configuration of this SoC in which a running ASIC "
                             "die presents a quiescent bus to HOSTIO",
            "write_path_control_addr":
                "The QSPI ADDR scratch, same as the FPGA. Present on both "
                "vehicles, in no core's instruction fetch, and RTL-verified as a "
                "full 32-bit RW store -- so ABORT GATE 8 no longer has to defer "
                "on silicon for want of a control word.",
            "eth_imem_live_code":
                "True: cc_rom releases CPU0, so eth IMEM is or becomes live "
                "instruction memory. Unlike the FPGA's, this one is a "
                "consequence of the ROM and does not depend on an operator "
                "loading anything.",
            "subword_rmw_supported":
                "UNESTABLISHED. With CRC ON at reset and FCSM recovery stripped, "
                "a byte write into a word-granular protected macro needs a "
                "read-modify-write in the controller. Whether that path exists "
                "here is a question for the memory-subsystem owner, not for a "
                "test to answer by going red",
            "poll_budget": "0x00100000 x (100.000/25.010) rounded up to 0x00400000 "
                           "-- same wall window, 4x the cycles",
            "timer_reload": "0x18000000 is 16.1 s at 25.010 MHz and only 4.03 s at "
                            "100 MHz; 0x60000000 restores the wall time. Keep it "
                            "at or below 0x7FFFFFFF or HIO-406's "
                            "reload_b = min(reload_a*2, 0xFFFFFFFF) clamps and "
                            "the 'exactly 2x' premise dies silently",
            "fcsm_state_map": "UNESTABLISHED. The decode (3-bit fcsm_state at "
                              "[19:17], a2l_replay_app_valid at [20], 4..7 = link "
                              "up) was cross-checked against the PACKAGED FPGA IP. "
                              "This build strips FCSM recovery, so the reachable "
                              "states -- and possibly the packing -- differ",
            "ecc_enabled": "the tapeout netlist ships ECC BYPASSED, CRC ON at "
                           "reset, and FCSM recovery STRIPPED -- the opposite of "
                           "the FPGA-proven configuration on all three axes",
        },
        notes=[
            "THERE IS NEVER A QUIESCENT BUS HERE. Any memory-integrity result is "
            "taken from a live system: a word that changed between two probes is "
            "INCONCLUSIVE, not a fault. Report it as such.",
            "Every TideLink test in this suite was written against the FPGA "
            "configuration (ECC active, CRC off, FCSM recovery present) and the "
            "ASIC differs on all three. A TideLink mismatch here is a finding to "
            "CLASSIFY, not automatically a bad die.",
            "ext_sysresetreq is tied 1'b0 on the FPGA wrapper but may be bonded "
            "to a real pad on the ASIC, so RESET_INFO EXTRESET (bit 3) could "
            "legitimately read SET. It is recorded, never asserted.",
            "The eth ROM anchors at words 0..15 ARE valid here: they were audited "
            "against the ASIC eth_rom_via macro image and sit ahead of word 55.",

            "DECLARE flash_provisioned ON THIS BOARD. A zero CPU0 boot gate is "
            "FOUR states, not one, and only one of them is a silicon fault. "
            "Without the declaration HIO-106 runs its ladder, records the "
            "classification and DEFERS -- correct, but it asserts nothing. "
            "--target-set flash_provisioned=0 turns the no-flash park into a "
            "clean PASS and every OTHER zero into a red; =1 makes any zero a red. "
            "Do not reach for bootgate_values instead: it is `known` on this "
            "profile, so the guard passes and a healthy unprovisioned die goes "
            "red on the first test of the run.",
        ],
    )
    return t


def _unknown():
    t = Target(
        "unknown",
        kind="unknown",
        label="target not declared",
        description=(
            "THE DEFAULT, and deliberately so. An unspecified target must not "
            "silently inherit FPGA expectations: a first-silicon operator who "
            "forgets --target should get DATA AND A FLAG, never a fake failure "
            "and never a fake pass. Every target-specific property below is None, "
            "so every target-dependent assertion degrades to record-and-flag and "
            "is counted in summary.target. What survives is the "
            "target-INDEPENDENT set (see TargetIndependent), which is RTL-grounded "
            "on both vehicles and stays asserted -- relaxing that would be "
            "deleting coverage, not being careful."),
        # every target-specific property stays None
        census_value_class_asserted=False,
        soak_seconds=60,
        sources={},
        notes=[
            "Run again with --target fpga_kr260 or --target asic_tsmc65 to turn "
            "the deferred assertions back into evidence. The deferral list in "
            "this record names every one of them and the value that was seen.",

            "flash_provisioned is the exception to that sentence: NO --target "
            "will ever supply it, because it describes the board in front of you "
            "and not the vehicle class. --target-set flash_provisioned=0|1 (or "
            "HOSTIO_FLASH_PROVISIONED) is the only thing that turns HIO-106's "
            "zero-boot-gate deferral into evidence, and it works on this profile "
            "exactly as it does on the declared ones.",
        ],
    )
    return t


def _haps_sx_compute():
    """The NanoSoC COMPUTE chiplet on HAPS-SX (single Cortex-M4, rsyn9 RTL).

    NOT an eth vehicle. It shares the HOSTIO4 wrapper, the socdebug ADP monitor
    and several APB blocks with eth (QSPI regs, DMA-250, the cc_periph
    timer/uart2/watchdog slots, IPC mailbox regs, hw_spinlock), but its memory
    map is different: no reset_ctrl, no TideChart/TideLink/perf/BFM/ETC on
    debug_m's reach, IPC at 0x2A, PHC at 0x2B (a different register model),
    spinlock at 0x2C000000, and its RAMs are reached through the compute_admin
    alias (ROM 0x80000000, IMEM 0x90000000, DMEM 0x98000000).

    STATE THIS PROFILE ASSUMES (operator's duty to establish before a run):
    the M4 runs hostio_test from flash and is PARKED ON WFI after the host sent
    STOP (shared SRAM 0x2D000400 = 0x48540004). That is what makes the bus
    quiescent and ROM/IMEM reads safe: ADP has no bus timeout, and an M4
    spinning in ROM/IMEM can starve the admin port (procedure section 3.3).
    """
    # PHYSICAL SIZES, from the RTL the bitstream was built from -- NOT from
    # compute_mem.h's "IMEM 32K, DMEM 32K" comment or the memory map's 128 MB
    # windows: nanosoc_compute_soc.sv:29-30 sets COMPUTE_IMEM_RAM_ADDR_W = 14
    # (16 KB, rf_16k) and COMPUTE_DMEM_RAM_ADDR_W = 13 (8 KB, rf_08k). MEASURED
    # 2026-10-03: a first run of this profile assumed 32 KB and its IMEM/DMEM
    # "upper halves" aliased onto the parked M4's code and stack (HIO-205
    # caught the DMEM alias: 0x98006000 landed on 0x98004000).
    IMEM_BASE, IMEM_SIZE = 0x90000000, 16 * 1024
    DMEM_BASE, DMEM_SIZE = 0x98000000, 8 * 1024
    # Above hostio_test (999 bytes at 0x90001000) and below the 16 KB top: the
    # window tier4_5's F/U and DMA tests may write without touching live code.
    IMEM_SCRATCH, IMEM_SCRATCH_SIZE = 0x90002000, 0x2000
    skips = {
        # tier 0
        "HIO-001": "power-on banner needs an operator power cycle; on compute "
                   "the banner ' 0x50c1ab04' was captured when the console was "
                   "first drained (T8 log), and no reset is taken in this run",
        # tier 1 -- eth identity that does not exist on the compute map
        "HIO-101": "eth boot ROM vector table at 0x08000000: compute has no eth "
                   "ROM (0x08000000 answers R!); the compute ROM is checked by "
                   "HIO-106's compute body and HIO-007",
        "HIO-102": "CPU1-vs-CPU0 ROM discrimination: compute has ONE ROM (M4)",
        "HIO-104": "reset_ctrl PIDs at 0x2A000FC0: compute has no reset_ctrl "
                   "(0x2A is the IPC mailbox)",
        "HIO-105": "reset_ctrl reset values at 0x2A000000: no reset_ctrl on compute",
        "HIO-107": "eth CPU0-ran witness / boot-gate ladder: eth-only boot flow",
        "HIO-108": "bus_fault_monitor 0x2C300010: not in the compute map",
        "HIO-109": "event-timestamp-capture 0x2C000000: not in the compute map "
                   "(0x2C is hw_spinlock, and its page 0 read ACQUIRES a lock)",
        "HIO-110": "perf-probe 0x2C200000: not in the compute map",
        "HIO-111": "IPC PERIPH_ID hard-coded at eth's 0x23000034; compute's IPC is "
                   "at 0x2A000000 and is exercised by HIO-305 (ported)",
        "HIO-112": "eth-only weak identity probe",
        "HIO-116": "eth REMAP signature at 0x00000000: compute's 0x0 is not on "
                   "debug_m, and the REMAP register is compute core_remap",
        "HIO-117": "aliasing fingerprint needs reset_ctrl at 0x2A (absent on compute)",
        "HIO-118": "alias-wrap size probe is calibrated on the two eth ROMs and eth "
                   "windows; not ported",
        "HIO-119": "permanently not applicable (eth's own verdict)",
        "HIO-121": "TideLink registers are NOT reachable from compute's debug_m",
        "HIO-122": "TideLink registers are NOT reachable from compute's debug_m",
        "HIO-123": "TideChart is NOT reachable from compute's debug_m",
        "HIO-125": "eth event router: not in the compute map (0x2B is the PHC)",
        "HIO-127": "eth non-zero counter reset values (perf/BFM/TideLink): absent",
        # tier 2
        "HIO-206": "CPU1 IMEM battery: compute has no CPU1. Its single M4 IMEM "
                   "(16 KB) is covered by HIO-201..204",
        "HIO-207": "CPU1 DMEM battery: compute has no CPU1. Its single M4 DMEM "
                   "(8 KB) is covered by HIO-205",
        # tier 3
        "HIO-301": "reset_ctrl SYS_CTRL: no reset_ctrl on compute",
        "HIO-302": "reset_ctrl RESET_INFO W1C: no reset_ctrl on compute",
        "HIO-303": "TideChart TC_ERROR: not reachable from compute's debug_m",
        "HIO-306": "etc_capture: not in the compute map",
        "HIO-307": "perf probe: not in the compute map",
        "HIO-308": "bus_fault_monitor: not in the compute map",
        "HIO-309": "PHC: compute's PHC (0x2B000000, compute phc_apb_regs.sv) is a "
                   "different register model from eth's phc_regs.rdl; not ported",
        "HIO-310": "TideLink census: not reachable from compute's debug_m",
        "HIO-313": "boot-gate WRITE path: compute's 0x29000000 is core_remap, and "
                   "this bench forbids any write to it (REMAP is POR-only clear)",
        "HIO-314": "RO sweep writes 0xFFFFFFFF to five eth-only addresses "
                   "(0x2A000FF0 is compute's IPC window); not ported",
        # tier 4
        "HIO-402": "fabric clock via the eth perf probe: not in the compute map",
        "HIO-403": "PHC protocol is eth phc_regs.rdl; compute's PHC differs",
        "HIO-404": "PHC rate: needs HIO-403 and a declared fabric clock",
        "HIO-407": "TideLink lane state: not reachable from compute's debug_m",
        "HIO-408": "TideLink link-up wait: not reachable from compute's debug_m",
        "HIO-409": "XHB bridge witness: eth TideLink registers, not reachable",
        "HIO-410": "TideChart election: not reachable from compute's debug_m",
        "HIO-413": "cross-die peer read: single-die bench (decided 2026-09-30)",
        "HIO-414": "eth firmware boot-confirm token 0x2D001FF0: compute firmware "
                   "does not write it",
        "HIO-415": "MDIO / Ethernet MAC: compute has no Ethernet MAC",
        # tier 5
        "HIO-502": "release CPU0 = a write to 0x29000000: forbidden on this bench, "
                   "and compute has no CPU0",
        "HIO-503": "needs HIO-502 (eth CPU0 relaunch)",
        "HIO-504": "needs HIO-502 (eth CPU0 firmware liveness)",
        "HIO-506": "Ethernet MAC/MDIO via CPU0 firmware: no MAC on compute",
        "HIO-507": "live bus-fault monitor: not in the compute map",
        "HIO-509": "whole-SoC reset via eth reset_ctrl SW_RESET: no reset_ctrl on "
                   "compute, and a reset would undo the WFI park this run needs",
    }
    overrides = (
        # tier0: the mapped/unmapped control pair and the ROM word
        ("tier0", "BOOTROM_ADDR", 0x80000000,
         "compute boot ROM through the compute_admin alias (bootrom_0)"),
        ("tier0", "BOOTROM_WORD", 0x18002000,
         "bootrom.bin (md5 44bbdfcc) word 0, MEASURED over ADP 2026-10-03"),
        ("tier0", "UNMAPPED_ADDR", 0x30000000,
         "in no compute decode range; MEASURED R! 2026-10-03"),
        # tier2_3: the RAM batteries re-pointed at FREE compute RAM
        ("tier2_3", "ETH_ROM_BASE", 0x80000000, "compute boot ROM (admin alias)"),
        ("tier2_3", "CPU1_ROM_BASE", 0x80000000,
         "compute has ONE ROM; HIO-209 checks it under both names"),
        ("tier2_3", "ETH_IMEM_BASE", IMEM_BASE,
         "the M4's WHOLE IMEM via the admin alias. DESTROYS the parked M4's "
         "code: reset the M4 after tier 2 (it reloads from flash)"),
        ("tier2_3", "ETH_IMEM_SIZE", IMEM_SIZE,
         "16 KB physical (COMPUTE_IMEM_RAM_ADDR_W = 14, rf_16k)"),
        ("tier2_3", "ETH_DMEM_BASE", DMEM_BASE,
         "the M4's WHOLE DMEM via the admin alias. DESTROYS its stack/.data"),
        ("tier2_3", "ETH_DMEM_SIZE", DMEM_SIZE,
         "8 KB physical (COMPUTE_DMEM_RAM_ADDR_W = 13, rf_08k)"),
        # tier2_3: spinlock and IPC at their compute bases (same register files:
        # hw_spinlock.v differs from eth only in a function's `automatic`;
        # ipc_mailbox_apb_regs.sv is md5-identical, 641e7105)
        ("tier2_3", "SPINLOCK_OWNER", 0x2C000300, "compute hw_spinlock base 0x2C000000"),
        ("tier2_3", "SPINLOCK_FORCE_RELEASE", 0x2C000304, "compute hw_spinlock"),
        ("tier2_3", "SPINLOCK_DBG_PAGE", 0x2C000200, "compute hw_spinlock"),
        ("tier2_3", "_SPINLOCK_ACQUIRE_PAGES",
         ((0x2C000000, 0x2C0000FF), (0x2C000100, 0x2C0001FF), (0x2C000200, 0x2C0002FF)),
         "the HZ-7 acquire-page guard follows the block to its compute base"),
        ("tier2_3", "IPC_SLOT0_W0", 0x2A000000, "compute ipc_mailbox_0 base 0x2A000000"),
        ("tier2_3", "IPC_IRQ_STATUS", 0x2A000028, "compute ipc_mailbox_0"),
        ("tier2_3", "IPC_LOCK", 0x2A000030, "compute ipc_mailbox_0"),
        ("tier2_3", "IPC_PERIPH_ID", 0x2A000034, "compute ipc_mailbox_0"),
        ("tier2_3", "IPC_OUT_OF_RANGE", 0x2A000038, "compute ipc_mailbox_0"),
        # tier4_5
        ("tier4_5", "BOOTROM_ETH", 0x80000000,
         "HIO-401's always-OKAY poll target: the compute boot ROM (admin alias)"),
        ("tier4_5", "PHC_CAP_NS", 0x2B000028,
         "HIO-405's recorded-only stale-latch demo: compute PHC cap_nanoseconds "
         "(region 1, word 2 of phc_apb_regs.sv)"),
        ("tier4_5", "ETH_IMEM", IMEM_SCRATCH, "compute IMEM above hostio_test"),
        ("tier4_5", "UPLOAD_BASE", IMEM_SCRATCH,
         "HIO-501's F/U target: compute IMEM 0x90002000 (above hostio_test)"),
        ("tier4_5", "_BULK_WRITE_REGIONS",
         ((IMEM_SCRATCH, IMEM_SCRATCH_SIZE,
           "compute IMEM 0x90002000-0x90003FFF (admin alias), above the parked "
           "M4's code and below the 16 KB top"),),
         "the only region tier4_5 may carpet-write on compute"),
        ("tier4_5", "DMA_TEST_SRC", 0x90003000, "compute IMEM scratch window"),
        ("tier4_5", "DMA_TEST_DST", 0x90003800, "compute IMEM scratch window"),
        ("tier4_5", "DMA_REACHABLE_SAFE", (IMEM_SCRATCH, IMEM_SCRATCH + IMEM_SCRATCH_SIZE - 1),
         "compute DMA-250 data master reaches compute_admin (memory map Initiator "
         "Connectivity); 0x90002000-0x90003FFF is above the live code"),
        ("tier4_5", "DMA_NAMED_REFUSALS",
         ((0x24000000, 0x27FFFFFF, "QSPI XiP aperture (HZ-6)"),
          (0x40000000, 0x6FFFFFFF, "compute D2D windows d2d0/d2d1"),
          (0x80000000, 0x90001FFF, "compute ROM and the PARKED M4's IMEM code"),
          (0x90004000, 0x97FFFFFF, "above the 16 KB IMEM: ALIASES back onto live code"),
          (0x98000000, 0x9FFFFFFF, "compute DMEM (8 KB, aliased across the window): "
                                   "the M4's stack/.data")),
         "compute's hazard windows for a DMA descriptor"),
    )
    forbid = (
        (0x29000000, 0x29FFFFFF, "compute core_remap: REMAP is cleared only by "
                                 "POR -- no writes on this bench"),
        (0x24000000, 0x27FFFFFF, "QSPI XiP aperture (HZ-6)"),
        (0x28008000, 0x28008FFF, "watchdog: arming it starts a reset countdown"),
    )
    t = Target(
        "haps_sx_compute",
        kind="fpga",
        label="NanoSoC compute chiplet on HAPS-SX (rsyn9, single M4, M4 parked on WFI)",
        description=(
            "The compute chiplet's HOSTIO4/ADP port on the HAPS-SX VU19P "
            "(bitstream be8093f7, rsyn9 launch RTL), with hostio_test parked on "
            "WFI after STOP. Eth-only tests SKIP with a per-test reason; tests on "
            "blocks the two dies share run unchanged or re-pointed at the "
            "compute map (module_overrides); the three tier-1 controls run a "
            "compute body (test_bodies)."),
        fabric_hz=None,
        eth_rom_image=None,
        bus_quiescent=True,
        bus_parkable=True,
        cpu1_free_running=False,
        census_value_class_asserted=False,
        rom_distinct_offsets={"eth_rom": 0x004, "cpu1_rom": 0x004},
        subword_rmw_supported=None,
        eth_imem_live_code=False,
        timer0_owned_by_firmware=False,
        dma_powered=True,
        soak_seconds=30,
        test_skips=skips,
        test_bodies={
            "HIO-103": "compute_bodies:hio_103_compute",
            "HIO-106": "compute_bodies:hio_106_compute",
            "HIO-114": "compute_bodies:hio_114_compute",
        },
        module_overrides=overrides,
        write_forbid=forbid,
        sources={
            "bus_quiescent": "hostio_test parked on WFI after STOP: HT_STATUS "
                             "0x48540004 and HT_ITER stable over 1.5 s (T8 log, "
                             "2026-10-03); no other master is programmed",
            "rom_distinct_offsets": "bootrom.bin (44bbdfcc): word 0 0x18002000, "
                                    "word 1 0x00000085 (reset vector), measured "
                                    "over ADP",
            "eth_imem_live_code": "re-pointed at the M4's IMEM: the M4 is ASLEEP "
                                  "on WFI (DHCSR 0x00050001, S_SLEEP, read over SWD "
                                  "2026-10-03), so no core is fetching from it",
            "write_forbid": "no ROM band: compute_ss_bootrom.sv is a pure "
                            "case-statement ROM with no write port, so HIO-209's "
                            "write cannot land",
            "dma_powered": "hostio_test ran 8527 DMA-250 copies on this image "
                           "(HT_DMA_ERR 0)",
            "timer0_owned_by_firmware": "hostio_test and the SPL use no timer",
        },
        notes=[
            "Run ONLY with the M4 parked on WFI (0x2D000400 == 0x48540004). "
            "Tier 2 overwrites the M4's WHOLE IMEM and DMEM (HIO-201..205) and "
            "shared SRAM (HIO-208, the breadcrumbs and the HT block): the M4 "
            "sleeps through it, but its image is gone. Afterwards RESET THE M4 "
            "(SWD 'reset run'): the boot ROM reloads SPL + hostio_test from "
            "flash, and the console/GO/STOP protocol parks it again.",
        ],
    )
    return t


_BUILDERS = {
    "fpga_kr260": _fpga_kr260,
    "asic_tsmc65": _asic_tsmc65,
    "unknown": _unknown,
    "haps_sx_compute": _haps_sx_compute,
}

# Short aliases the operator will actually type at 2 a.m.
ALIASES = {
    "fpga": "fpga_kr260",
    "kr260": "fpga_kr260",
    "asic": "asic_tsmc65",
    "tsmc65": "asic_tsmc65",
    "silicon": "asic_tsmc65",
    "none": "unknown",
    "compute": "haps_sx_compute",
    "": "unknown",
}

DEFAULT_TARGET = "unknown"


def names():
    return sorted(_BUILDERS)


def resolve(name):
    """Build a FRESH Target for `name`.  Fresh because overrides mutate it."""
    key = (name or "").strip()
    key = ALIASES.get(key.lower(), key)
    if key not in _BUILDERS:
        raise ValueError(
            "unknown target %r. Known targets: %s (aliases: %s). The default is "
            "%r, which asserts nothing target-specific and records everything."
            % (name, ", ".join(names()),
               ", ".join("%s->%s" % kv for kv in sorted(ALIASES.items()) if kv[0]),
               DEFAULT_TARGET))
    return _BUILDERS[key]()


# ---------------------------------------------------------------------------
# environment overrides -- the pre-existing knobs, kept working
# ---------------------------------------------------------------------------
# Each entry: env var -> (property, parser).  These are PER-TEST / PER-RIG
# OVERRIDES layered ON TOP of the profile; the profile is the primary source.
# Every one that fires is recorded in target.overrides, so an override can never
# be the silent reason a run looks different from the last one.
ENV_OVERRIDES = {
    "ETH_ROM_IMAGE":       ("eth_rom_image", str),
    "HOSTIO_ETH_ROM_IMAGE": ("eth_rom_image", str),
    "HOSTIO_FABRIC_HZ":    ("fabric_hz", "int"),
    "HOSTIO_PHC_CORE_HZ":  ("phc_core_hz", "int"),
    "HOSTIO_PHC_NS_INCR":  ("phc_ns_incr_for_realtime", "int"),
    "HOSTIO_CPU1_PARKED":  ("bus_quiescent", "bool"),
    # Set by the operator, or by hostio_fw/fw_load.py, which knows exactly when
    # an image was installed. 0 asserts "I have not loaded anything this power
    # cycle"; absent leaves it unknown, which is treated as live.
    "HOSTIO_ETH_IMEM_LIVE": ("eth_imem_live_code", "bool"),
    # The BOARD in front of the operator, declared per run. 0 = no QSPI flash
    # fitted or none programmed, which makes a ZERO boot gate the EXPECTED
    # reading; 1 = flash fitted and carrying a CRC-valid image, which makes a
    # zero a finding. Absent leaves it None, and None DEFERS -- it never guesses,
    # in either direction.
    "HOSTIO_FLASH_PROVISIONED": ("flash_provisioned", "bool"),
    "HOSTIO_SOAK_SECONDS": ("soak_seconds", "int"),
    "HOSTIO_ECC":          ("ecc_enabled", "bool"),
    "HOSTIO_CRC":          ("crc_enabled_at_reset", "bool"),
    "HOSTIO_FCSM_RECOVERY": ("fcsm_recovery_present", "bool"),
}

TARGET_ENV = "HOSTIO_TARGET"


# Properties whose value is a BOOLEAN. `apply_settings` needs this because it
# infers the type from the value already in the profile, and a property that is
# None on the target being set has no type to infer from -- it used to fall
# through to `val = raw.strip()` and store the STRING "0", which is TRUTHY, makes
# `known()` answer True, and asserts against a string. That is the falsy/truthy
# trap arriving through the override channel instead of through a read, and it
# reached every bool that is None on some profile: dma_powered,
# subword_rmw_supported and timer0_owned_by_firmware on the ASIC,
# eth_imem_live_code on the FPGA, and flash_provisioned on all three.
BOOL_PROPS = frozenset((
    "bus_quiescent", "bus_parkable", "cpu1_free_running",
    "ecc_enabled", "crc_enabled_at_reset", "fcsm_recovery_present",
    "census_value_class_asserted", "subword_rmw_supported",
    "timer0_owned_by_firmware", "dma_powered", "eth_imem_live_code",
    "flash_provisioned",
))


def _parse(kind, raw):
    if kind is str:
        return raw.strip()
    s = raw.strip()
    if kind == "bool":
        if s.lower() in ("1", "true", "yes", "y", "on"):
            return True
        if s.lower() in ("0", "false", "no", "n", "off"):
            return False
        raise ValueError("%r is not a boolean" % raw)
    if kind == "int":
        try:
            return int(s, 0)
        except ValueError:
            return int(round(float(s)))     # accepts 25.010e6
    raise ValueError("no parser for %r" % kind)


def apply_env(target, environ=None):
    """Layer the environment knobs on top of `target`.  Returns the target."""
    env = os.environ if environ is None else environ
    for var, (prop, kind) in sorted(ENV_OVERRIDES.items()):
        if var not in env or env[var].strip() == "":
            continue
        try:
            target.override(prop, _parse(kind, env[var]), via="env:%s" % var)
        except ValueError as exc:
            target.override_conflicts.append(
                "%s=%r could not be parsed (%s) and was IGNORED -- the profile "
                "value stands. A knob that silently fails to apply is worse than "
                "one that is absent." % (var, env[var], exc))
    return target


def apply_settings(target, settings, via="--target-set"):
    """Layer explicit `prop=value` strings on top of `target`.

    Values are parsed by the property's own type in Target.PROPS, so
    `--target-set fabric_hz=100e6` and `--target-set bus_quiescent=1` both work.
    """
    for s in settings or ():
        if "=" not in s:
            raise ValueError("--target-set expects prop=value, got %r" % s)
        prop, raw = s.split("=", 1)
        prop = prop.strip()
        if prop not in Target.PROPS:
            raise ValueError("--target-set %s: %r is not a target property. "
                             "Known: %s" % (s, prop, ", ".join(sorted(Target.PROPS))))
        cur = getattr(target, prop)
        default = Target.PROPS[prop][0]
        ref = cur if cur is not None else default
        # BOOL_PROPS first: a property that is None on THIS target has no value to
        # infer a type from, and the fall-through at the bottom stores a string.
        if prop in BOOL_PROPS:
            val = _parse("bool", raw)
        elif isinstance(ref, bool):
            val = _parse("bool", raw)
        elif isinstance(ref, int):
            val = _parse("int", raw)
        elif isinstance(ref, float):
            val = float(raw)
        elif prop in ("eth_dmem_word0", "cpu0_ran_marker", "fabric_hz",
                      "phc_core_hz", "phc_ns_incr_for_realtime", "soak_seconds"):
            val = _parse("int", raw)
        elif prop in ("bus_quiescent", "bus_parkable", "cpu1_free_running",
                      "ecc_enabled", "crc_enabled_at_reset",
                      "fcsm_recovery_present", "census_value_class_asserted"):
            val = _parse("bool", raw)
        else:
            val = raw.strip()
        target.override(prop, val, via=via)
    return target


def build(name=None, environ=None, settings=None, use_env=True):
    """The one entry point the harness calls.

    Returns (target, source) where source is 'cli', 'env' or 'default' -- so the
    record says not only WHICH target was used but HOW it was chosen. A target
    picked up from the environment is explicit enough to honour and important
    enough to write down.
    """
    env = os.environ if environ is None else environ
    if name:
        source = "cli"
    elif use_env and env.get(TARGET_ENV, "").strip():
        name, source = env[TARGET_ENV].strip(), "env:%s" % TARGET_ENV
    else:
        name, source = DEFAULT_TARGET, "default"
    t = resolve(name)
    if use_env:
        apply_env(t, env)
    if settings:
        apply_settings(t, settings)
    return t, source


# ---------------------------------------------------------------------------
# module bindings -- making the profile reach the existing module constants
# ---------------------------------------------------------------------------
# Some tier modules already carry a per-target constant as a MODULE GLOBAL that
# the operator was expected to edit by hand (tier1.ETH_ROM_IMAGE is the one that
# exists today).  Rather than leave the profile disconnected from it -- which
# would mean `--target asic_tsmc65` silently failing to fix the single most
# dangerous FPGA-calibrated assertion in the suite -- the harness binds them.
#
# THE RULES, so this can never be the mysterious reason a run differs:
#   * a binding fires ONLY when the module's own value is still the "undeclared"
#     sentinel.  A tier owner or an operator who set it explicitly always wins.
#   * every binding that fires is recorded in the run record under
#     target.bindings_applied, with the module, the attribute and the value.
#   * `--no-target-bindings` disables the mechanism entirely.
#
# (module, attribute, target property, sentinel that means "undeclared")
MODULE_BINDINGS = [
    ("tier1", "ETH_ROM_IMAGE", "eth_rom_image", None),
]


def apply_module_bindings(modules, target):
    """Push profile values into tier-module globals.  Returns a record list."""
    applied = []
    for mod_name, attr, prop, sentinel in MODULE_BINDINGS:
        mod = modules.get(mod_name)
        if mod is None or not hasattr(mod, attr):
            continue
        value = getattr(target, prop, None)
        current = getattr(mod, attr)
        if value is None:
            applied.append({"module": mod_name, "attr": attr, "property": prop,
                            "applied": False,
                            "why": "target %s does not declare %s"
                                   % (target.name, prop),
                            "value": fmt_prop(prop, current)})
            continue
        if current != sentinel:
            applied.append({"module": mod_name, "attr": attr, "property": prop,
                            "applied": False,
                            "why": "module value was already set explicitly and "
                                   "wins over the profile",
                            "value": fmt_prop(prop, current)})
            continue
        setattr(mod, attr, value)
        applied.append({"module": mod_name, "attr": attr, "property": prop,
                        "applied": True, "why": "bound from target %s" % target.name,
                        "value": fmt_prop(prop, value)})
    return applied


def _hexrepr(v):
    """Addresses read as addresses in the record: ints as 0x%08X, recursively."""
    if isinstance(v, bool):
        return repr(v)
    if isinstance(v, int):
        return "0x%08X" % v if v >= 0x10000 else str(v)
    if isinstance(v, (tuple, list)):
        return "(" + ", ".join(_hexrepr(x) for x in v) + ")"
    return repr(v)


def apply_module_overrides(modules, target):
    """Re-point tier-module constants at this vehicle's map.  Returns records.

    Unlike apply_module_bindings this fires whatever the module's value is:
    a module constant on an eth vehicle IS the eth value, so there is no
    "undeclared" sentinel to wait for. That is exactly why every override is
    recorded with the value it replaced, and why the profile lists them.
    """
    applied = []
    for mod_name, attr, value, why in (target.module_overrides or ()):
        mod = modules.get(mod_name)
        if mod is None or not hasattr(mod, attr):
            applied.append({"module": mod_name, "attr": attr, "property":
                            "module_overrides", "applied": False,
                            "why": "module or attribute not loaded", "value": None})
            continue
        old = getattr(mod, attr)
        setattr(mod, attr, value)
        applied.append({"module": mod_name, "attr": attr,
                        "property": "module_overrides", "applied": True,
                        "why": "override from target %s: %s" % (target.name, why),
                        "value": _hexrepr(value), "replaced": _hexrepr(old)})
    return applied


# ---------------------------------------------------------------------------
# a printable table, for --list-targets
# ---------------------------------------------------------------------------
_TABLE_ROWS = [
    ("fabric_hz", "fabric clock (Hz)"),
    ("phc_ns_incr_for_realtime", "PHC NS_INCR for real time"),
    ("eth_rom_image", "eth boot ROM image"),
    ("eth_dmem_word0", "eth DMEM word 0"),
    ("bootgate_values", "CPU0 boot gate at power-on"),
    ("flash_provisioned", "QSPI flash provisioned (BOARD)"),
    ("bus_quiescent", "bus quiescent while testing"),
    ("bus_parkable", "bus CAN be made quiescent"),
    ("ecc_enabled", "TideLink ECC"),
    ("crc_enabled_at_reset", "TideLink CRC at reset"),
    ("fcsm_recovery_present", "FCSM recovery present"),
    ("census_value_class_asserted", "census value class asserted"),
]


def format_table(target_names=None, width=30):
    ts = [resolve(n) for n in (target_names or names())]
    out = []
    out.append("%-32s%s" % ("property", "".join("%-*s" % (width, t.name) for t in ts)))
    out.append("-" * (32 + width * len(ts)))
    for prop, label in _TABLE_ROWS:
        cells = []
        for t in ts:
            v = getattr(t, prop)
            if v is None:
                # THE THIRD KIND of None reads differently in a table: "unknown"
                # invites someone to fill the profile in, and no profile can
                # answer this one. Say who is being asked instead.
                cells.append("-- declare per run --"
                             if prop in Target.OPERATOR_DECLARED
                             else "-- unknown --")
            elif prop in HZ_PROPS:
                cells.append("%d (%.3f MHz)" % (v, v / 1e6))
            elif isinstance(v, tuple):
                cells.append(" or ".join(str(x) for x in fmt_prop(prop, v)))
            else:
                cells.append(str(fmt_prop(prop, v)))
        out.append("%-32s%s" % (label, "".join("%-*s" % (width, c) for c in cells)))
    out.append("")
    for t in ts:
        out.append("%s -- %s" % (t.name, t.label))
        out.append("    %s" % t.description)
        if t.notes:
            for n in t.notes:
                out.append("    * %s" % n)
        out.append("")
    return "\n".join(out)


if __name__ == "__main__":
    print(format_table())
