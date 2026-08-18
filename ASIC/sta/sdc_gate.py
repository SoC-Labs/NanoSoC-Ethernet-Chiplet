#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# ASIC/sta/sdc_gate.py -- Track-B constraint gate for a WRITTEN *_syn.sdc
#
# WHY THIS EXISTS
# ---------------
# Four of five input SDCs are newer than the last synthesis (_syn.sdc is
# 2026-08-14 14:01; inputs run to 2026-08-18 00:25). Two constraint changes have
# therefore never been synthesised, and the only artefact that proves whether
# they survived Genus's write_sdc is the written SDC itself -- 16.7 MB of it.
#
#   GATE 1  TX word clocks resolved.
#           (a) SDC half:    every D2D_TX_WORD_CLK_* -source names user_hsclk,
#                            NOT pad_clk_tx.  Checkable the moment Genus writes.
#           (b) report half: master_clk_edge_not_reaching == 0 and TA-1018 == 0.
#                            Only checkable after Innovus has read the SDC.
#           These are reported SEPARATELY.  A run that has not reached Innovus
#           yet gets NOT MEASURED for (b) -- never PASS.
#
#   GATE 2  The C2 Option A anchors actually landed.
#           69 synchroniser anchors under set_false_path,
#           22 FIFO/addr-sync datapath anchors under set_max_delay.
#
# THE TRAP THIS SCRIPT EXISTS TO DEFEAT
# -------------------------------------
# `f1_reg` -- the synchroniser demet pin pattern -- appears 564 times in the
# current build/full-20260814 _syn.sdc.  Every single one of those 564 is inside
# a `group_path` command.  ZERO are inside a `set_false_path`.  A naive
# `grep f1_reg` therefore reports the C2 fix as PRESENT when it is ABSENT.
#
# SDC commands here span up to hundreds of physical lines via backslash-newline
# and unclosed `[list` brackets, so "the line the match is on" tells you nothing
# about which command owns it.  The parser below folds continuations and
# attributes every match to its OWNING command.  It is unit-tested (--self-test)
# against exactly this trap before it is allowed to judge anything.
#
# THE SECOND TRAP: HIERARCHY SEPARATORS ARE NOT PRESERVED
# -------------------------------------------------------
# The input SDC names an anchor with '/' separators:
#     .../u_wlink/axi2wl/wlink_axiawFC/a2l_fc_replay/.../wptr_rclk_demet/f1_reg*/D
# Genus writes it back with most of those levels flattened to '_':
#     .../u_wlink/axi2wl_wlink_axiawFC_a2l_fc_replay_..._wptr_rclk_demet_f1_reg
# A literal string match of the input anchor against the written SDC can never
# succeed.  Anchors are therefore compiled to separator-insensitive regexes
# ([/_]+ for every separator).
#
# CONTROLS -- THIS PROJECT HAS REPEATEDLY BEEN BURNED BY CHECKS THAT MEASURED
# NOTHING, SO THE SCRIPT MUST PROVE IT CAN SEE
# ---------------------------------------------------------------------------
#   POSITIVE control: constraints known to be in every existing _syn.sdc --
#       the pad set_multicycle_path (constraints.sdc:236) and
#       set_clock_groups -name eth_chiplet_cdc.
#       If these are not found, the verdict is NULL RESULT, not PASS.
#   MATCHER control: the 69/22 anchor stems must be findable SOMEWHERE in the
#       file (they are, under group_path).  This separates "the fix is absent"
#       from "my regex is broken" -- the two look identical without it.
#       READ THE NUMBER CORRECTLY: on build/full-20260814 this control reports
#       53/69, not 69/69, and that is NOT a matcher failure.  A written SDC is
#       NOT a netlist census -- it contains only objects some command names.
#       The 16 absent stems are the enable_*_clk_demet flops and the whole
#       gb2wl/wlink_generalbusgb block, which no surviving command mentions.
#       The control asks only "can the matcher resolve these names at all"; the
#       GATE asks "are they under the right command", and 0/69 is unambiguous
#       either way.  If C2 lands, all 69 must appear, because write_sdc emits
#       the exception's own object collection.
#   NEGATIVE control: a deliberately bogus anchor that must NOT match.  If it
#       does, the matcher is too permissive and every PASS is worthless.
#
# Any control failure => NULL RESULT (exit 3).  Never PASS.
#
# USAGE
#   ./sdc_gate.py --self-test
#   ./sdc_gate.py <path/to/*_syn.sdc> [...]
#   ./sdc_gate.py --scan ASIC/            # dedupes ~140 files to ~13 by content
#   ./sdc_gate.py <sdc> --run-dir <dir>   # override report/log location
#   ./sdc_gate.py <sdc> --json out.json
#
# EXIT CODES
#   0  all gates PASS and all controls PASS
#   1  a gate FAILED (controls passed -- this is a real, trustworthy failure)
#   3  NULL RESULT: a control failed, so the gate verdicts mean nothing
#   4  usage / IO error
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------

from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from dataclasses import dataclass, field
from pathlib import Path

# =============================================================================
# SECTION 1 -- THE SDC PARSER.  Fold continuations, attribute matches to owners.
# =============================================================================


@dataclass
class SdcCommand:
    """One logical SDC/Tcl command, with its continuations folded in."""

    name: str  # first bareword, e.g. "set_false_path"
    text: str  # full folded text, newlines preserved
    line_start: int  # 1-based physical line where the command starts
    line_end: int  # 1-based physical line where it ends

    @property
    def flat(self) -> str:
        """Folded text with all whitespace runs collapsed to single spaces."""
        return re.sub(r"\s+", " ", self.text).strip()


def parse_sdc(text: str) -> list[SdcCommand]:
    """Split an SDC/Tcl script into logical commands.

    Handles, because the real files use all of them:
      * backslash-newline continuation
      * multi-line `[list \\ ... ]` (bracket depth keeps the command open)
      * `{...}` brace groups spanning lines
      * double-quoted strings containing braces/brackets/#
      * `;` as a command separator at depth 0
      * `#` comments -- ONLY where a command could start (Tcl rule), and a
        comment is itself continued by a trailing backslash

    A newline ends a command only at brace depth 0, bracket depth 0, outside
    quotes, and when not escaped by a trailing backslash.
    """
    commands: list[SdcCommand] = []

    i = 0
    n = len(text)
    line = 1

    # Start of the current command in the source, and the line it began on.
    cur_start: int | None = None
    cur_line = 1

    brace = 0
    bracket = 0
    in_quote = False

    def flush(end_idx: int, end_line: int) -> None:
        nonlocal cur_start
        if cur_start is None:
            return
        raw = text[cur_start:end_idx]
        if raw.strip():
            # Command name = first bareword, after stripping any leading
            # brace/bracket noise. Continuation backslashes are removed for
            # the name lookup only.
            m = re.match(r"\s*([A-Za-z_][A-Za-z0-9_:]*)", raw)
            cmd_name = m.group(1) if m else "<expr>"
            commands.append(
                SdcCommand(
                    name=cmd_name,
                    text=raw,
                    line_start=cur_line,
                    line_end=end_line,
                )
            )
        cur_start = None

    while i < n:
        c = text[i]

        # ---- escape: backslash consumes the next char (incl. newline) -------
        if c == "\\":
            if i + 1 < n:
                if text[i + 1] == "\n":
                    line += 1
                i += 2
                continue
            i += 1
            continue

        # ---- inside a double-quoted string ----------------------------------
        if in_quote:
            if c == '"':
                in_quote = False
            elif c == "\n":
                line += 1
            i += 1
            continue

        # ---- comment: only at a command-start position ----------------------
        if c == "#" and cur_start is None:
            # Consume to end of line, honouring backslash continuation.
            while i < n:
                if text[i] == "\\" and i + 1 < n:
                    if text[i + 1] == "\n":
                        line += 1
                    i += 2
                    continue
                if text[i] == "\n":
                    line += 1
                    i += 1
                    break
                i += 1
            continue

        # ---- whitespace before a command begins ------------------------------
        if cur_start is None:
            if c in " \t\r\n":
                if c == "\n":
                    line += 1
                i += 1
                continue
            # a real command starts here
            cur_start = i
            cur_line = line

        # ---- structural characters ------------------------------------------
        if c == '"':
            in_quote = True
        elif c == "{":
            brace += 1
        elif c == "}":
            brace = max(0, brace - 1)
        elif c == "[":
            bracket += 1
        elif c == "]":
            bracket = max(0, bracket - 1)
        elif c == ";" and brace == 0 and bracket == 0:
            flush(i, line)
            i += 1
            continue
        elif c == "\n":
            if brace == 0 and bracket == 0:
                flush(i, line)
                line += 1
                i += 1
                continue
            line += 1

        i += 1

    flush(n, line)
    return commands


# =============================================================================
# SECTION 2 -- ANCHOR MATCHING.  Separator-insensitive, wildcard-aware.
# =============================================================================


def anchor_to_regex(anchor: str, strip_pin: bool = True) -> re.Pattern:
    """Compile an input-SDC anchor path into a written-SDC matcher.

    Rules, each of which exists because the written file breaks the naive
    assumption:
      * a trailing '/D' (or any single-letter pin) is dropped -- write_sdc
        re-expresses -to [get_pins .../D] collections at cell granularity.
      * '/' and '_' are interchangeable separators ([/_]+), because Genus
        flattens hierarchy inconsistently.
      * '*' matches any run of non-delimiter characters.
      * NO end anchor: the written name may carry a bus index ('[0]') or a
        further flattened leaf ('_mem_reg[0][3]').  Deliberately permissive --
        see the module header: a permissive matcher that STILL reports the C2
        anchors absent is a far stronger result than a strict one, and the
        negative control below bounds how permissive it is allowed to be.
    """
    a = anchor.strip()
    if strip_pin:
        a = re.sub(r"/[A-Z]{1,4}$", "", a)  # /D, /CP, /OEN ...

    parts = re.split(r"[/_]+", a)
    out = []
    for p in parts:
        if not p:
            continue
        # escape everything, then re-enable '*'
        chunks = p.split("*")
        esc = r"[^\s\]\}\[\{]*".join(re.escape(ch) for ch in chunks)
        out.append(esc)
    return re.compile(r"[/_]+".join(out))


@dataclass
class AnchorSet:
    label: str
    anchors: list[str]
    owning_commands: tuple[str, ...]  # commands that would satisfy the gate
    expect_count: int
    strip_pin: bool = True
    _rx: list[re.Pattern] = field(default_factory=list)

    def compile(self) -> None:
        self._rx = [anchor_to_regex(a, self.strip_pin) for a in self.anchors]

    def find(self, cmds: list[SdcCommand], restrict: tuple[str, ...] | None):
        """Return (matched_anchor_indices, per-owning-command tally)."""
        pool = cmds if restrict is None else [c for c in cmds if c.name in restrict]
        blob = "\n".join(c.text for c in pool)
        hit = set()
        for idx, rx in enumerate(self._rx):
            if rx.search(blob):
                hit.add(idx)
        return hit


# =============================================================================
# SECTION 3 -- THE DESIGN-SPECIFIC EXPECTATIONS (C2 Option A, TX word clocks)
# =============================================================================

WL = "u_nanosoc_eth_chiplet_chip/u_soc/u_tidelink/u_chiplet_controller/u_wlink"

# ASIC/genus-innovus/inputs/constraints.sdc:456-460
C2_FC = [
    "axi2wl/wlink_axiawFC",
    "axi2wl/wlink_axiwFC",
    "axi2wl/wlink_axibFC",
    "axi2wl/wlink_axiarFC",
    "axi2wl/wlink_axirFC",
    "gb2wl/wlink_generalbusgb",
    "tl2wl/wlink_tidelinktl",
]

# constraints.sdc:461-470
C2_SFX = [
    "a2l_fc_replay/enable_app_clk_demet",
    "a2l_fc_replay/enable_link_clk_demet",
    "a2l_fc_replay/fifo/sync_wptr_demet",
    "a2l_fc_replay/fifo/sync_rptr_demet",
    "a2l_fc_replay/link_addr_to_app_clk/addrsync/rptr_wclk_demet",
    "a2l_fc_replay/link_addr_to_app_clk/addrsync/wptr_rclk_demet",
    "l2a_fifo_addr_to_tx/addrsync/wptr_rclk_demet",
    "l2a_fifo_addr_to_tx/addrsync/rptr_wclk_demet",
]

# constraints.sdc:476-482
C2_SOLO = [
    "lltx/enable_ff2_demet",
    "lltx/err_inj_ff2_demet",
    "tx_link_clk_reset_wrs/reset_sync_demet",
    "sp2wl/tx_fifo/sync_wptr_demet",
    "sp2wl/tx_fifo/sync_rptr_demet",
]

# constraints.sdc:489
C2_OBS = ["asl", "ioen", "oae", "sop", "grant", "cnt", "idaw", "idsb"]


def build_c2_pins() -> list[str]:
    """Mirror constraints.sdc:491-496 exactly.  69 synchroniser anchors."""
    pins: list[str] = []
    for fc in C2_FC:
        for s in C2_SFX:
            pins.append(f"{WL}/{fc}/{s}/f1_reg*/D")
    for s in C2_SOLO:
        pins.append(f"{WL}/{s}/f1_reg*/D")
    for s in C2_OBS:
        pins.append(f"{WL}/u_fcemit_obs/{s}_s0_reg*/D")
    return pins


def build_c2_dp() -> list[str]:
    """Mirror constraints.sdc:547-553 exactly.  22 datapath anchors."""
    dp: list[str] = []
    for fc in C2_FC:
        dp.append(f"{WL}/{fc}/a2l_fc_replay/fifo/mem")
        dp.append(f"{WL}/{fc}/a2l_fc_replay/link_addr_to_app_clk/addrsync")
        dp.append(f"{WL}/{fc}/l2a_fifo_addr_to_tx/addrsync")
    dp.append(f"{WL}/sp2wl/tx_fifo/mem")
    return dp


# The same guard the constraint file applies to itself.  If these trip, this
# script's transcription of the Tcl has drifted from the Tcl.
_C2_PINS = build_c2_pins()
_C2_DP = build_c2_dp()
assert len(_C2_PINS) == 69, f"transcription error: {len(_C2_PINS)} pins, expected 69"
assert len(_C2_DP) == 22, f"transcription error: {len(_C2_DP)} dp, expected 22"

# NEGATIVE control -- structurally identical to a real anchor, but names a
# hierarchy that does not exist.  Must never match.
BOGUS_ANCHOR = f"{WL}/axi2wl/wlink_axiZZFC/a2l_fc_replay/nonesuch_demet/f1_reg*/D"


# =============================================================================
# SECTION 4 -- GATES
# =============================================================================

VERDICT_PASS = "PASS"
VERDICT_FAIL = "FAIL"
VERDICT_NULL = "NULL RESULT"
VERDICT_NM = "NOT MEASURED"


@dataclass
class GateResult:
    name: str
    verdict: str
    detail: str
    data: dict = field(default_factory=dict)


def gate1_sdc(cmds: list[SdcCommand]) -> GateResult:
    """GATE 1a -- every D2D_TX_WORD_CLK_* -source must name user_hsclk."""
    cgc = [c for c in cmds if c.name == "create_generated_clock"]
    tx = [c for c in cgc if "D2D_TX_WORD_CLK_" in c.flat]

    if not tx:
        return GateResult(
            "GATE 1a  TX word-clock -source (SDC)",
            VERDICT_NULL,
            "no create_generated_clock names D2D_TX_WORD_CLK_* at all -- the "
            "8 TX word clocks are missing from this SDC, so there is nothing "
            "to judge. This is a null result, not a pass.",
            {"tx_clocks_found": 0},
        )

    good, bad, none = [], [], []
    for c in tx:
        flat = c.flat
        nm = re.search(r'-name\s+"?([A-Za-z0-9_]+)"?', flat)
        clk = nm.group(1) if nm else "<unnamed>"
        src = re.search(r"-source\s+\[\s*get_pins\s+\{?([^\]\}\s]+)", flat)
        if not src:
            none.append(clk)
        elif src.group(1).endswith("/user_hsclk"):
            good.append(clk)
        else:
            bad.append((clk, src.group(1).rsplit("/", 1)[-1]))

    if bad or none:
        wrong = ", ".join(f"{c}->{p}" for c, p in bad[:4])
        return GateResult(
            "GATE 1a  TX word-clock -source (SDC)",
            VERDICT_FAIL,
            f"{len(good)}/{len(tx)} TX word clocks anchored on user_hsclk; "
            f"{len(bad)} still on the wrong pin ({wrong}"
            f"{', ...' if len(bad) > 4 else ''})"
            + (f"; {len(none)} carry no -source at all" if none else ""),
            {"total": len(tx), "user_hsclk": len(good), "wrong": len(bad),
             "no_source": len(none)},
        )

    return GateResult(
        "GATE 1a  TX word-clock -source (SDC)",
        VERDICT_PASS,
        f"all {len(tx)} D2D_TX_WORD_CLK_* clocks take -source from user_hsclk",
        {"total": len(tx), "user_hsclk": len(good)},
    )


def _count_master_clk_edge(run_dir: Path) -> tuple[int | None, list[str]]:
    """Largest master_clk_edge_not_reaching count across the run's reports.

    Two report layouts exist in this flow (an ASCII table with '|' columns and
    a plain whitespace layout); both are handled.
    """
    rep_dir = run_dir / "reports"
    if not rep_dir.is_dir():
        return None, []
    files = sorted(rep_dir.glob("*check_timing*.rep"))
    if not files:
        return None, []
    worst, seen = None, []
    for f in files:
        try:
            txt = f.read_text(errors="replace")
        except OSError:
            continue
        for line in txt.splitlines():
            if "master_clk_edge_not_reaching" not in line:
                continue
            nums = re.findall(r"(\d+)\s*\|?\s*$", line.strip())
            if nums:
                v = int(nums[-1])
                worst = v if worst is None else max(worst, v)
                seen.append(f"{f.name}={v}")
    return worst, seen


def _count_ta1018(run_dir: Path) -> tuple[int | None, list[str]]:
    """Largest per-log TA-1018 WARNING count.

    Two counting traps, both of which inflate the number:

    1. COUNT LINES, NOT OCCURRENCES.  Every TA-1018 warning line names the code
       TWICE -- once in the `**WARN: (TA-1018):` header and once in the closing
       "available using 'man TA-1018'" trailer.  A substring count therefore
       reports exactly double (579 vs the true 291 in innovus.logv).

    2. COUNT PER FILE AND TAKE THE MAX, NEVER THE SUM.  The flow rotates logs
       (innovus.log, .log1 .. .log5) and writes a verbose twin (.logv*) of each,
       so summing multiplies the same warning by ~12 and invents a number no
       single run ever produced.
    """
    work = run_dir / "work"
    if not work.is_dir():
        return None, []
    logs = sorted(work.glob("innovus.log*"))
    if not logs:
        return None, []
    # The authoritative emission is the WARN header; fall back to a plain line
    # match if a future log format drops the decoration.
    hdr = re.compile(r"\*\*WARN:\s*\(TA-1018\)")
    worst, seen = None, []
    for f in logs:
        try:
            lines = f.read_text(errors="replace").splitlines()
        except OSError:
            continue
        v = sum(1 for ln in lines if hdr.search(ln))
        if v == 0:
            v = sum(1 for ln in lines if "TA-1018" in ln)
        if v:
            seen.append(f"{f.name}={v}")
        worst = v if worst is None else max(worst, v)
    return worst, seen


def gate1_reports(run_dir: Path | None) -> GateResult:
    """GATE 1b -- the report half.  Only meaningful after Innovus has run."""
    if run_dir is None or not run_dir.is_dir():
        return GateResult(
            "GATE 1b  TX word-clock resolved (reports)",
            VERDICT_NM,
            "no run directory located; master_clk_edge_not_reaching and TA-1018 "
            "were NOT MEASURED. A freshly written _syn.sdc predates Innovus, so "
            "this is expected mid-flow -- it is not a pass.",
        )

    mce, mce_seen = _count_master_clk_edge(run_dir)
    ta, ta_seen = _count_ta1018(run_dir)

    if mce is None and ta is None:
        return GateResult(
            "GATE 1b  TX word-clock resolved (reports)",
            VERDICT_NM,
            f"{run_dir}: no check_timing reports and no innovus logs found. "
            "NOT MEASURED -- not a pass.",
        )

    parts, bad, missing = [], False, []
    if mce is None:
        missing.append("master_clk_edge_not_reaching (no check_timing report)")
    else:
        parts.append(f"master_clk_edge_not_reaching={mce} [{', '.join(mce_seen) or 'none'}]")
        bad |= mce != 0
    if ta is None:
        missing.append("TA-1018 (no innovus log)")
    else:
        parts.append(f"TA-1018(max per log)={ta} [{', '.join(ta_seen) or 'none'}]")
        bad |= ta != 0

    if missing:
        return GateResult(
            "GATE 1b  TX word-clock resolved (reports)",
            VERDICT_NM,
            "partially measured -- " + "; ".join(parts + ["MISSING: " + ", ".join(missing)]),
            {"master_clk_edge_not_reaching": mce, "ta1018_max": ta},
        )

    return GateResult(
        "GATE 1b  TX word-clock resolved (reports)",
        VERDICT_FAIL if bad else VERDICT_PASS,
        "; ".join(parts),
        {"master_clk_edge_not_reaching": mce, "ta1018_max": ta},
    )


def gate2(cmds: list[SdcCommand]) -> tuple[GateResult, GateResult, dict]:
    """GATE 2 -- the C2 anchors, attributed to their OWNING command."""
    sync = AnchorSet("C2 synchroniser", _C2_PINS, ("set_false_path",), 69)
    dp = AnchorSet("C2 datapath", _C2_DP, ("set_max_delay",), 22, strip_pin=False)
    sync.compile()
    dp.compile()

    res = {}
    out = []
    for aset, gname in (
        (sync, "GATE 2a  69 synchroniser anchors under set_false_path"),
        (dp, "GATE 2b  22 datapath anchors under set_max_delay"),
    ):
        in_owner = aset.find(cmds, aset.owning_commands)
        anywhere = aset.find(cmds, None)

        # Where DO they live?  This is what turns "absent" into a diagnosis.
        elsewhere: dict[str, int] = {}
        if len(anywhere) > len(in_owner):
            for c in cmds:
                if c.name in aset.owning_commands:
                    continue
                for idx in anywhere - in_owner:
                    if aset._rx[idx].search(c.text):
                        elsewhere[c.name] = elsewhere.get(c.name, 0) + 1
                        break

        owner_cmd_count = sum(1 for c in cmds if c.name in aset.owning_commands)
        detail = (
            f"{len(in_owner)}/{aset.expect_count} anchors found under "
            f"{'/'.join(aset.owning_commands)} "
            f"({owner_cmd_count} such command(s) in file); "
            f"{len(anywhere)}/{aset.expect_count} found anywhere in the file"
        )
        if elsewhere:
            where = ", ".join(f"{k}({v})" for k, v in sorted(elsewhere.items()))
            detail += f"; the unattributed ones are owned by: {where}"

        verdict = VERDICT_PASS if len(in_owner) == aset.expect_count else VERDICT_FAIL
        out.append(GateResult(gname, verdict, detail,
                              {"in_owner": len(in_owner),
                               "anywhere": len(anywhere),
                               "expected": aset.expect_count,
                               "elsewhere": elsewhere}))
        res[aset.label] = {"in_owner": len(in_owner), "anywhere": len(anywhere)}

    return out[0], out[1], res


# ---- controls ---------------------------------------------------------------

PAD_MCP_PINS = ["uPAD*/I", "uPAD*/C", "uPAD*/PAD", "uPAD*/OEN", "uPAD*/REN"]


def controls(cmds: list[SdcCommand]) -> list[GateResult]:
    out: list[GateResult] = []

    # POSITIVE 1 -- the pad multicycle path (constraints.sdc:236-238).
    mcp = [c for c in cmds if c.name == "set_multicycle_path"]
    pad_mcp = [c for c in mcp if re.search(r"uPAD", c.text)]
    out.append(
        GateResult(
            "CONTROL+ pad set_multicycle_path (constraints.sdc:236)",
            VERDICT_PASS if pad_mcp else VERDICT_FAIL,
            f"{len(pad_mcp)} of {len(mcp)} set_multicycle_path command(s) "
            f"reference uPAD*"
            + (f" (first at line {pad_mcp[0].line_start})" if pad_mcp else ""),
            {"pad_mcp": len(pad_mcp), "total_mcp": len(mcp)},
        )
    )

    # POSITIVE 2 -- the eth_chiplet_cdc clock group.
    cg = [c for c in cmds if c.name == "set_clock_groups"]
    eth = [c for c in cg if "eth_chiplet_cdc" in c.flat]
    out.append(
        GateResult(
            "CONTROL+ set_clock_groups -name eth_chiplet_cdc",
            VERDICT_PASS if eth else VERDICT_FAIL,
            f"{len(eth)} of {len(cg)} set_clock_groups command(s) named "
            f"eth_chiplet_cdc"
            + (f" (line {eth[0].line_start})" if eth else ""),
            {"eth_cdc": len(eth), "total_cg": len(cg)},
        )
    )

    # MATCHER control -- can the compiled anchor regexes see anything at all?
    # If the 69 stems are invisible file-wide, a GATE 2 FAIL is indistinguishable
    # from a broken regex, and must not be reported as a finding.
    sync = AnchorSet("C2 synchroniser", _C2_PINS, ("set_false_path",), 69)
    sync.compile()
    anywhere = sync.find(cmds, None)
    out.append(
        GateResult(
            "CONTROL~ anchor matcher can resolve C2 stems (any command)",
            VERDICT_PASS if len(anywhere) >= 1 else VERDICT_FAIL,
            f"{len(anywhere)}/69 synchroniser stems resolve somewhere in the "
            f"file. This separates 'the exception is absent' from 'the regex is "
            f"broken'; without it the two are indistinguishable.",
            {"stems_resolved": len(anywhere)},
        )
    )

    # NEGATIVE control -- bounds how permissive the matcher is allowed to be.
    bogus = anchor_to_regex(BOGUS_ANCHOR)
    blob = "\n".join(c.text for c in cmds)
    hit = bool(bogus.search(blob))
    out.append(
        GateResult(
            "CONTROL- bogus anchor must NOT match",
            VERDICT_FAIL if hit else VERDICT_PASS,
            "a structurally identical but non-existent hierarchy "
            "(wlink_axiZZFC/nonesuch_demet) "
            + ("MATCHED -- the matcher is too permissive and every PASS above "
               "is worthless" if hit else "correctly did not match"),
            {"bogus_hit": hit},
        )
    )

    return out


# =============================================================================
# SECTION 5 -- FILE DISCOVERY: resolve symlinks, dedupe by content
# =============================================================================


def sha256(p: Path) -> str:
    h = hashlib.sha256()
    with p.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def discover(paths: list[Path], scan_root: Path | None) -> list[tuple[Path, str, list[Path]]]:
    """Return [(representative_real_path, sha256, [aliases that reached it])].

    There are ~140 *_syn.sdc under ASIC/ but only ~13 unique contents;
    build/fp1505/outputs/..._syn.sdc is a symlink to full-20260814's.  Resolving
    symlinks alone is not enough -- distinct real files with identical bytes
    (copied prev_outputs/, per-arm run directories) also exist.  Dedupe on
    content hash so the script cannot be fooled into "verifying" a file whose
    bytes it has already judged.
    """
    cand: list[Path] = []
    if scan_root is not None:
        cand.extend(sorted(scan_root.rglob("*_syn.sdc")))
    cand.extend(paths)

    # step 1: collapse aliases (symlinks, relative/absolute spellings) onto the
    # real path they resolve to.
    by_real: dict[Path, list[Path]] = {}
    for p in cand:
        try:
            rp = p.resolve()
        except OSError:
            continue
        if not rp.is_file():
            continue
        lst = by_real.setdefault(rp, [])
        if p != rp and p.resolve() == rp and p not in lst:
            lst.append(p)

    # step 2: collapse distinct real files with identical content.
    by_hash: dict[str, list[Path]] = {}
    for rp in sorted(by_real):
        try:
            h = sha256(rp)
        except OSError:
            continue
        by_hash.setdefault(h, []).append(rp)

    out: list[tuple[Path, str, list[Path]]] = []
    for h, reals in by_hash.items():
        aliases: list[Path] = [reals[0]]
        for extra in reals[1:]:
            aliases.append(extra)
        for rp in reals:
            for a in by_real.get(rp, []):
                if a not in aliases:
                    aliases.append(a)
        out.append((reals[0], h, aliases))
    return out


def infer_run_dir(sdc: Path) -> Path | None:
    """<run>/outputs/<block>_syn.sdc  ->  <run>."""
    if sdc.parent.name == "outputs":
        return sdc.parent.parent
    if sdc.parent.name in ("mmmc", "prev_outputs"):
        # baseline_*/work/<blk>_cts/libs/mmmc/... -- walk up to the run root
        for anc in sdc.parents:
            if (anc / "reports").is_dir() or (anc / "work").is_dir():
                return anc
    return None


# =============================================================================
# SECTION 6 -- SELF-TEST.  Build the parser's credibility BEFORE it judges.
# =============================================================================

SELFTEST_TRAP = r"""
# This fixture is the exact failure mode the script exists to defeat: a
# demet anchor that is present in the file but owned by group_path.
create_clock -name clk -period 10 [get_ports clk]

group_path -weight 1.000000 -name cg_enable_group_D2D_TX_WORD_CLK_0 -through [list \
  [get_cells u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink/u_chiplet_controller/u_wlink/axi2wl_wlink_axiawFC_a2l_fc_replay_enable_app_clk_demet_f1_reg]  \
  [get_cells u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink/u_chiplet_controller/u_wlink/axi2wl_wlink_axiawFC_a2l_fc_replay_enable_link_clk_demet_f1_reg] ]

set_false_path -from [get_clocks clk] -to [get_clocks swdclk] -hold
"""

SELFTEST_GOOD = r"""
set_false_path -from [get_clocks clk] -to [list \
  [get_pins u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink/u_chiplet_controller/u_wlink/axi2wl_wlink_axiawFC_a2l_fc_replay_enable_app_clk_demet_f1_reg/D]  \
  [get_pins u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink/u_chiplet_controller/u_wlink/axi2wl_wlink_axiawFC_a2l_fc_replay_enable_link_clk_demet_f1_reg/D] ]
"""


def self_test() -> int:
    fails: list[str] = []

    def check(cond: bool, msg: str) -> None:
        print(f"  {'ok  ' if cond else 'FAIL'}  {msg}")
        if not cond:
            fails.append(msg)

    print("SELF-TEST 1 -- continuation folding")
    cmds = parse_sdc(SELFTEST_TRAP)
    names = [c.name for c in cmds]
    check(names == ["create_clock", "group_path", "set_false_path"],
          f"3 commands recovered from a multi-line fixture, in order: {names}")
    gp = [c for c in cmds if c.name == "group_path"][0]
    check(gp.text.count("f1_reg") == 2,
          "both f1_reg cells folded into the ONE owning group_path command")
    check(gp.line_end - gp.line_start == 2,
          f"group_path folds 3 physical lines into 1 command "
          f"(lines {gp.line_start}..{gp.line_end})")

    print("SELF-TEST 2 -- THE TRAP: f1_reg present, but not under set_false_path")
    naive = SELFTEST_TRAP.count("f1_reg")
    check(naive == 2, f"a naive grep finds {naive} f1_reg hits (would say PASS)")
    aset = AnchorSet("t", [f"{WL}/axi2wl/wlink_axiawFC/a2l_fc_replay/enable_app_clk_demet/f1_reg*/D"],
                     ("set_false_path",), 1)
    aset.compile()
    check(len(aset.find(cmds, ("set_false_path",))) == 0,
          "attributed matcher finds 0 under set_false_path -- TRAP DEFEATED")
    check(len(aset.find(cmds, None)) == 1,
          "the same anchor IS found file-wide (so this is absence, not blindness)")

    print("SELF-TEST 3 -- the positive case is detected when it is real")
    good = parse_sdc(SELFTEST_GOOD)
    check(len(aset.find(good, ("set_false_path",))) == 1,
          "when the anchor really is under set_false_path, it is found")

    print("SELF-TEST 4 -- separator-insensitive matching ('/' vs '_')")
    rx = anchor_to_regex(f"{WL}/axi2wl/wlink_axiawFC/a2l_fc_replay/fifo/sync_wptr_demet/f1_reg*/D")
    flat = ("u_nanosoc_eth_chiplet_chip_u_soc_u_tidelink/u_chiplet_controller/"
            "u_wlink/axi2wl_wlink_axiawFC_a2l_fc_replay_fifo_sync_wptr_demet_f1_reg[0]")
    check(bool(rx.search(flat)), "Genus-flattened name matches the '/'-separated anchor")

    print("SELF-TEST 5 -- negative control: a bogus hierarchy must not match")
    check(not anchor_to_regex(BOGUS_ANCHOR).search(flat),
          "bogus anchor does not match a real flattened name")

    print("SELF-TEST 6 -- brace/quote/comment/semicolon handling")
    tricky = parse_sdc(
        '# a comment with { an unbalanced brace and [ a bracket\n'
        'set_units -capacitance 1pF ; set_load 1.0 [get_ports a]\n'
        'set_false_path -to [get_pins {u_x/y_reg[0]/D}]\n'
        '# trailing comment continued \\\n'
        'still comment\n'
        'create_clock -name "c { }" -period 5\n'
    )
    tn = [c.name for c in tricky]
    check(tn == ["set_units", "set_load", "set_false_path", "create_clock"],
          f"comments/semicolons/braces/quotes handled: {tn}")

    print("SELF-TEST 7 -- transcribed anchor counts match the constraint file")
    check(len(_C2_PINS) == 69, "69 synchroniser anchors built (7x8 + 5 + 8)")
    check(len(_C2_DP) == 22, "22 datapath anchors built (7x3 + 1)")

    print()
    if fails:
        print(f"SELF-TEST FAILED ({len(fails)} check(s)). The gate is not trustworthy.")
        return 1
    print("SELF-TEST PASSED -- parser and matcher are trustworthy.")
    return 0


# =============================================================================
# SECTION 7 -- DRIVER
# =============================================================================


def evaluate(sdc: Path, run_dir: Path | None) -> tuple[list[GateResult], list[GateResult], dict]:
    text = sdc.read_text(errors="replace")
    cmds = parse_sdc(text)
    ctrls = controls(cmds)
    g1a = gate1_sdc(cmds)
    g1b = gate1_reports(run_dir)
    g2a, g2b, _ = gate2(cmds)
    stats = {
        "physical_lines": text.count("\n") + 1,
        "logical_commands": len(cmds),
        "command_histogram": {},
    }
    for c in cmds:
        stats["command_histogram"][c.name] = stats["command_histogram"].get(c.name, 0) + 1
    return [g1a, g1b, g2a, g2b], ctrls, stats


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(
        description="Track-B constraint gate for a written *_syn.sdc",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    ap.add_argument("sdc", nargs="*", type=Path, help="one or more *_syn.sdc")
    ap.add_argument("--scan", type=Path, metavar="ROOT",
                    help="recursively find *_syn.sdc under ROOT (deduped by content)")
    ap.add_argument("--run-dir", type=Path,
                    help="override the run directory holding reports/ and work/")
    ap.add_argument("--self-test", action="store_true",
                    help="unit-test the parser and matcher, then exit")
    ap.add_argument("--json", type=Path, help="write machine-readable results here")
    ap.add_argument("--quiet", action="store_true", help="one line per file")
    args = ap.parse_args(argv)

    if args.self_test:
        return self_test()

    if not args.sdc and not args.scan:
        ap.error("give at least one *_syn.sdc, or --scan ROOT, or --self-test")

    # The gate never runs on an unproven parser.
    print("=" * 78)
    print("PRE-FLIGHT: self-test (the gate refuses to judge on an unproven parser)")
    print("=" * 78)
    if self_test() != 0:
        return 3
    print()

    groups = discover(list(args.sdc), args.scan)
    if not groups:
        print("no *_syn.sdc found", file=sys.stderr)
        return 4

    print("=" * 78)
    print(f"DISCOVERY: {len(groups)} unique file content(s) after symlink resolution "
          f"and content dedupe")
    print("=" * 78)
    for rep, h, aliases in groups:
        print(f"  {h[:12]}  {rep}")
        for a in aliases[1:]:
            try:
                if a.is_symlink():
                    tag = "symlink"
                elif a.resolve() == rep:
                    tag = "same file, different spelling"
                else:
                    tag = "distinct file, identical bytes"
            except OSError:
                tag = "alias"
            print(f"                 <- {tag}: {a}")
    print()

    results = {}
    worst = 0
    for rep, h, aliases in groups:
        run_dir = args.run_dir or infer_run_dir(rep)
        gates, ctrls, stats = evaluate(rep, run_dir)

        ctrl_bad = [c for c in ctrls if c.verdict != VERDICT_PASS]
        gate_bad = [g for g in gates if g.verdict == VERDICT_FAIL]
        gate_null = [g for g in gates if g.verdict == VERDICT_NULL]
        gate_nm = [g for g in gates if g.verdict == VERDICT_NM]

        if ctrl_bad or gate_null:
            overall = VERDICT_NULL
            rc = 3
        elif gate_bad:
            overall = VERDICT_FAIL
            rc = 1
        elif gate_nm:
            overall = f"{VERDICT_PASS} (partial: {len(gate_nm)} gate(s) NOT MEASURED)"
            rc = 0
        else:
            overall = VERDICT_PASS
            rc = 0
        worst = max(worst, rc)

        print("=" * 78)
        print(f"FILE   {rep}")
        print(f"SHA256 {h}")
        print(f"RUNDIR {run_dir if run_dir else '<not located>'}")
        print(f"PARSE  {stats['physical_lines']} physical lines -> "
              f"{stats['logical_commands']} logical commands "
              f"(fold ratio {stats['physical_lines'] / max(1, stats['logical_commands']):.1f}x)")
        print("=" * 78)
        if not args.quiet:
            for c in ctrls:
                print(f"  [{c.verdict:^12}] {c.name}")
                print(f"                 {c.detail}")
            print()
            for g in gates:
                print(f"  [{g.verdict:^12}] {g.name}")
                print(f"                 {g.detail}")
            print()
        print(f"  OVERALL: {overall}")
        if ctrl_bad:
            print("           A CONTROL FAILED -- the gate verdicts above measured "
                  "nothing and must not be quoted as evidence.")
        print()

        results[str(rep)] = {
            "sha256": h,
            "aliases": [str(a) for a in aliases],
            "run_dir": str(run_dir) if run_dir else None,
            "overall": overall,
            "stats": {k: v for k, v in stats.items() if k != "command_histogram"},
            "controls": [{"name": c.name, "verdict": c.verdict,
                          "detail": c.detail, "data": c.data} for c in ctrls],
            "gates": [{"name": g.name, "verdict": g.verdict,
                       "detail": g.detail, "data": g.data} for g in gates],
        }

    if args.json:
        args.json.write_text(json.dumps(results, indent=2))
        print(f"wrote {args.json}")

    return worst


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
