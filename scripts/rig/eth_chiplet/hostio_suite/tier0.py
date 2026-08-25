#!/usr/bin/env python3
"""HOSTIO4 / ADP suite — Tier 0: the port self-test (HIO-001 .. HIO-011).

Written against scripts/rig/eth_chiplet/hostio_suite/CONTRACT.md and
docs/bringup/HOSTIO4_FUNCTIONAL_TEST_PLAN.md section 2 "Tier 0".

Nothing in Tiers 1-5 is meaningful until every test here passes.  HIO-007 is the
master control of the whole suite: it proves the bus-error flag can be BOTH
raised and cleared.  If it never raises, every ERROR-based test below is
vacuous; if it never clears, every OK-based test is vacuous.  (HIO-401, the poll
engine's own discrimination pair, is the other half of that pair and lives in
Tier 4.)

Values used here that are MEASURED, not derived (plan sections 5.1 and 1.3):

    0x08000000 -> 0x18003c00     eth boot ROM, cross-validated against the
                                 eth_ss_0 backdoor
    0x30000000 -> R!             undecoded from debug_m -> default slave ERROR
    banner word 0x50c1ab04       (an ADPBASIC build would emit 0x50c1ab01)

FOUR IMPLEMENTATION TRAPS.  Read these before changing anything in this file.

 1. THE ECHO WIDTH IS NOT STICKY -- IT IS RE-DERIVED PER COMMAND.  An earlier
    revision of this file guarded against a sticky `adp_size` leaking a narrow
    echo out of HIO-006 into the tests after it.  THAT GUARD WAS WRONG AND HAS
    BEEN REMOVED.  Measured on the live FPGA link 2026-08-25, after `R1` had
    narrowed the size to 8-bit:

        R1           ->  R 0x00           2 nibbles: the size really did narrow
        A x12345678  ->  A 0x12345678     full width
        C            ->  C 0x00000000     full width
        M            ->  M 0x00000000     full width

    The mechanism is ADP_RXPARAM at :536-537: on the EOL that completes ANY
    command line, `adp_size <= FNparam2size(adp_param[34:33])` fires
    unconditionally, one state before ADP_ACTION.  Every command therefore
    re-derives the size from ITS OWN parameter's digit count, and nothing
    survives from the command before it.  (ADP_WRITEHEX9 :692-698 does select the
    printed width on `adp_size` -- but on the value :537 has just latched.)  A
    bare `A`/`C`/`M` carries no digits, FNparam2size(2'b00) = 2'b10, so a report
    is always 32 bits wide; an 8-digit parameter is likewise always 32 bits.
    This is why the plan's "always write x + exactly 8 hex digits" rule is
    sufficient on its own, and it is what makes the width assertions in HIO-005
    meaningful: they check that THIS command's 8 digits encoded a 32-bit access.

 2. `R100` IS A 256-LINE BLOCK DUMP, NOT ONE READ -- so HIO-006 uses `R000`.
    The plan reaches for `R100` purely for its 3-digit parameter, but the digit
    COUNT sets the access size while the parameter VALUE sets the number of
    reads: `adp_count <= adp_param` (:536) and the ADP_LINEACK2 repeat arm
    (:727-729) make `R100` 0x100 = 256 halfword reads.  Measured 2026-08-25:

        R           ->  1 line,  8 nibbles, addr +4
        R1          ->  1 line,  2 nibbles, addr +1
        R000        ->  1 line,  4 nibbles, addr +2
        R010        -> 16 lines, 4 nibbles, addr +0x20
        Rx00000004  ->  4 lines, 8 nibbles, addr +0x10

    `R000` is 3 digits with a count of zero: the identical encoder path in one
    line instead of 256.  HIO-006 issues `R000` and records the deviation.

 3. THE FIRST-COMMAND `?` IS A LINK ARTEFACT AND enter() EATS IT.  HIO-003 has to
    re-create the condition deliberately (resync, then command) or it observes
    nothing.  HIO-004 must do the opposite: prove a good command answers first,
    so that its `?` is the parser's default arm and not the artefact.

 3. ESC IS AN ENTRY EVENT ONLY, SO A TEST MUST ESTABLISH THE STARTING STATE.
    FNvalid_adp_entry (:86-89) is evaluated in STD_RXD1 (:487), which is reached
    only from STD_IOCHK -- the STDIO bypass.  Inside the monitor an ESC is not
    exit (FNexit is 0x04/0x00, :133-136), not a space and not an EOL, so
    ADP_RXCMD (:523) takes it as the COMMAND LETTER and parks in ADP_RXPARAM
    waiting for an EOL: no prompt, no output at all, and the NEXT command line
    completes that dangling line as an invalid command and answers '?'.
    MEASURED 2026-08-25, first hardware run of this suite: HIO-002 sent a bare
    ESC to a port that earlier work had left inside the monitor, got '', and
    reported ABORT GATE 2 -- "the RX path is dead" -- on a healthy die, taking
    nine tests down with it as `needs` skips.  The very next command answered
    `C 0x00000000]`.  X then ESC returns ']' (measured separately).
    A port is left in the monitor by the previous test, by the previous run and
    by any manual poking, so "starts outside the monitor" holds exactly once, on
    a cold die at plan section 3 A1, and never again.  HIO-002 and HIO-003 call
    _to_bypass() to FORCE the pre-state and record which one they found.  The
    same trap makes a '?' ambiguous three ways -- see HIO-003.

 4. HIO-001 MUST NOT SEND ANYTHING.  It is the only test that proves the ADP TX
    path with zero dependence on RX, so it uses adp.raw_rx() and never enter().
    The runner's own per-test entry preamble would destroy it just as surely as a
    command would, so HIO-001, HIO-002 and HIO-003 are declared preamble=False
    and drive (or deliberately do not drive) entry themselves.  Those three are
    the only tests here that may not be preceded by an enter().

Two API notes.  This module is written against CONTRACT.md; where harness.py
offers a strictly better primitive it is used only if it is actually there:
adp.esc() (a bare ESC with no throwaway command) lets HIO-002, HIO-003 and
HIO-010 see the prompt standing alone, which is what the plan specifies, and
_esc() falls back to the contract-only path if it ever goes away.  Widths and
per-beat results are re-derived from r.raw with the local _replies() helper for
the same reason: r.value is an int and cannot carry the printed nibble count
that HIO-006 exists to measure.

A NOTE ON HOW TRAP 1 CAME TO BE WRONG, because it is the failure class this
suite exists to catch.  The sticky-size claim was derived from the RTL and then
"mutation-proved" against a simulated ADP that had been written to model the
very behaviour being claimed.  That exercise validated the simulator, not the
die.  Nothing in this file is evidence about the SoC unless it was measured on
the SoC; the fixture now reproduces the measured rows above before any mutation
result from it is believed.
"""

import re

from harness import test, HZ

# ---------------------------------------------------------------- constants --

BOOTROM_ADDR = 0x08000000       # eth boot ROM alias, remap-independent
BOOTROM_WORD = 0x18003C00       # MEASURED 2026-08-25, two independent paths
UNMAPPED_ADDR = 0x30000000      # eth scratch RX RAM: decoded by the eth SS,
                                # never routed to it by the multicore matrix
BANNER_WORD = 0x50C1AB04        # ADPBASIC build would give 0x50C1AB01
BANNER_STEM = "0x50c1ab"        # match the family, then check the build digit
PROMPT = "]"                    # PROMPT_CHAR parameter, socdebug_adp_control.v:16

_REPLY_RE = re.compile(r"([A-Za-z?])([ !])0x([0-9a-fA-F]+)")
_HEX_RE = re.compile(r"0x([0-9a-fA-F]+)")

# ------------------------------------------------------------------ helpers --


def _replies(raw):
    """Every well-formed ADP reply in a captured string.

    Returns [(letter, err_bool, ndigits, value), ...].  Used instead of Reply
    fields wherever the test needs the printed width (HIO-006) or needs to count
    replies inside one block-dump capture (HIO-009), neither of which survives
    the int in r.value.
    """
    if not raw:
        return []
    return [(m.group(1).upper(), m.group(2) == "!", len(m.group(3)),
             int(m.group(3), 16)) for m in _REPLY_RE.finditer(raw)]


def _width(raw):
    """Nibble count of the first hex field in a reply, or 0 if there is none."""
    reps = _replies(raw)
    if reps:
        return reps[0][2]
    m = _HEX_RE.search(raw or "")
    return len(m.group(1)) if m else 0


def _decode(words):
    """RX words -> console text.  Only (w & 0xf00) == 0 words are data bytes."""
    out = []
    for w in words or []:
        if (w & 0xF00) != 0:
            continue
        b = w & 0xFF
        if 32 <= b < 127 or b in (10, 13):
            out.append(chr(b))
    return "".join(out)


def _gpo(word):
    """GPO8 byte of a `C` report word {GPI8, GPO8, param[15:0]} (:674).

    A missing value yields a sentinel that can never compare equal to a real
    byte NOR to the GPI sentinel: a timeout must not be able to satisfy the
    mirror check by making both sides None.
    """
    return -1 if word is None else (word >> 16) & 0xFF


def _gpi(word):
    """GPI8 byte of a `C` report word.  Tied to GPO8 at the SoC top level."""
    return -2 if word is None else (word >> 24) & 0xFF


def _to_bypass(adp, rec, probe_ms=1500):
    """Force the STDIO bypass, and report what the pre-state actually was.

    ESC only enters the monitor from the bypass (trap 3), so any test that wants
    to observe the entry transition has to guarantee it starts outside.  `X`
    (ADP_EXIT :576, :671) is the way out and is benign in both directions: in the
    monitor it exits; in the bypass its characters are pushed at the SoC's dead
    STDIN and discarded.

    The two probes are what make a later "no prompt" unambiguous:

      answered before X, silent after   -> the port WAS in the monitor and the X
                                           provably landed; RX is already proven
                                           alive, so a missing prompt after the
                                           ESC can only be the entry path.
      silent before and after           -> the port was already in the bypass, OR
                                           RX is dead.  The X is a no-op and
                                           cannot be shown to land -- it does not
                                           need to.  The ESC is then exactly the
                                           experiment that separates those two,
                                           which is ABORT GATE 2's actual job.

    The exit is CONFIRMED, not assumed, and retried once.  A single residual
    byte -- the one resync() leaves, or a bare ESC parked in ADP_RXPARAM by an
    interrupted earlier run -- is consumed by whatever command line arrives next,
    and that can be the `X` itself, in which case the port never leaves the
    monitor.  One probe before the X absorbs one residual; two residuals need the
    retry.  If the monitor is still answering after two exits, that is a real
    anomaly and the caller's check says so.

    Returns (answered_before, answered_after) as plain bools.
    """
    before = adp.cmd("C", timeout_ms=probe_ms)
    for attempt in (1, 2):
        adp.cmd("X", timeout_ms=1000)      # no reply and no prompt by design
        after = adp.cmd("C", timeout_ms=probe_ms)
        if after.ok is False:
            break
    rec.record("pre_state", "monitor" if before.ok else "stdio-bypass or dead RX")
    rec.record("probe_before_exit", before.raw)
    rec.record("exit_attempts", attempt)
    rec.record("probe_after_exit", after.raw)
    return (before.ok is True), (after.ok is True)


def _esc(adp):
    """adp.esc() if the harness offers it, else None.

    CONTRACT.md has no bare-ESC primitive; harness.py added one for exactly the
    three tests that need to see a prompt with no command behind it. Preferred
    when present, never required.
    """
    return getattr(adp, "esc", None)


# ---------------------------------------------------------------- HIO-001 ----


@test("HIO-001", tier=0, hazard=HZ.RESET, weak=True, preamble=False,
      purpose="Power-on banner — the ONLY proof of the ADP TX path with zero "
              "dependence on RX. RED when a banner-shaped word is present but "
              "is 0x50c1ab01 (an ADPBASIC build), when more than one is emitted, "
              "or when a prompt follows it (which would mean the banner did not "
              "take the STD_IOCHK bypass at ADP_LINEACK2:733). "
              "WEAK as automated: with no banner in the capture this cannot tell "
              "'the operator did not power-cycle' from 'the TX path is dead', so "
              "absence reports SKIP, not FAIL. Its ABORT-GATE-1 strength exists "
              "only in the manual procedure of plan section 3 A1 (attach the host, "
              "THEN power the die). HIO-509 is the automatable version: it resets "
              "the SoC deliberately and the banner must reappear.")
def hio_001(adp, rec):
    # Deliberately no enter(), no resync(), no command: any host stimulus would
    # destroy the one property this test exists to establish.
    words = adp.raw_rx(3000)
    text = _decode(words)
    if BANNER_STEM not in text.lower():
        words += adp.raw_rx(3000)
        text = _decode(words)
    rec.record("banner_capture_words", len(words))
    if BANNER_STEM not in text.lower():
        rec.skip("no 0x50c1ab.. word in %d captured RX words. The banner is "
                 "emitted once, out of reset (adp_state <= ADP_WRITEHEX with "
                 "banner=1, :433-436). On a die that is already running it can "
                 "only be re-emitted by a reset (HZ-5: A x2a000020 ; W x00000002 "
                 "-- see HIO-509), which this test does not issue. Either attach "
                 "the host before powering the die and re-run, or run HIO-509 "
                 "with the reset hazard enabled. This SKIP is NOT evidence that "
                 "the TX path is alive." % len(words))

    low = text.lower()
    hits = [m for m in _HEX_RE.finditer(low) if m.group(1).startswith("50c1ab")]
    rec.record("banner_count", len(hits))
    rec.record("banner_word", int(hits[0].group(1), 16) if hits else None)
    rec.check("banner word is 0x%08x" % BANNER_WORD,
              bool(hits) and int(hits[0].group(1), 16) == BANNER_WORD,
              got=text.strip())
    rec.check("banner emitted exactly once", len(hits) == 1, got=len(hits))
    tail = low[hits[0].end():] if hits else ""
    rec.check("no prompt character after the banner", PROMPT not in tail,
              got=repr(tail[:40]))
    rec.note("Banner path: ADP_WRITEHEX0 (:723) and ADP_LINEACK2 (:733) go "
             "straight to STD_IOCHK, so a prompt after the banner would mean the "
             "monitor was entered by something other than this test.")
    rec.record("banner_followed_by_lfcr",
               bool(re.match(r"[^0-9a-f]*\n\r", text[hits[0].end():])) if hits else None)


# ---------------------------------------------------------------- HIO-002 ----


@test("HIO-002", tier=0, preamble=False,
      purpose="Monitor entry: ESC (0x1b) moves STD_RXD1 -> ADP_LINEACK -> "
              "ADP_PROMPT and the port prompts. The pre-state is ESTABLISHED, not "
              "assumed: ESC is an entry event only (trap 3), so the test exits to "
              "the STDIO bypass with `X` first and records which pre-state it "
              "found. RED when ESC is not recognised (FNvalid_adp_entry :86-89) "
              "or the host->SoC direction is dead: no prompt comes back. This is "
              "ABORT GATE 2 — the banner already proved TX, so a failure here "
              "isolates the fault to the RX direction: one PIO state machine, "
              "four data lines and IOREQ1/2. It must therefore be impossible to "
              "fail it any other way, which is what the two probes around the `X` "
              "are for: they separate 'the X never landed' from 'RX is dead'.")
def hio_002(adp, rec):
    esc = _esc(adp)
    if esc is not None:
        adp.resync()
        # Trap 3: guarantee the bypass, do not assume it. On the second and every
        # later run of this suite the port is left inside the monitor.
        was_in, still_in = _to_bypass(adp, rec)
        rec.check("the port is in the STDIO bypass when the ESC goes out",
                  still_in is False, got=rec.values.get("probe_after_exit"))
        if was_in:
            rec.note("Pre-state was the MONITOR: the port answered a command "
                     "before the X and is silent after it, so the X provably "
                     "landed AND the RX path is already proven alive. A missing "
                     "prompt below could then only be the ESC entry path itself.")
        else:
            rec.note("Pre-state was the STDIO BYPASS or a dead RX: nothing "
                     "answered before the X either, so the X is a no-op here and "
                     "cannot be shown to have landed -- it does not need to be. "
                     "This is the cold-die case of plan section 3 A1, and the ESC "
                     "below is precisely the experiment that separates 'sitting "
                     "in the bypass' from 'RX is dead'.")
        # The plan's own sequence: ESC alone, and the prompt must come back with
        # no command behind it.
        e = esc()
        rec.record("esc_reply", e.raw)
        rec.check("prompt character '%s' comes back from a bare ESC" % PROMPT,
                  PROMPT in (e.raw or ""), got=e.raw)
        rec.note("Observed with a bare ESC (harness extension adp.esc()); no "
                 "command was sent, so the prompt is ADP_LINEACK -> ADP_PROMPT "
                 "and nothing else. r.ok is deliberately NOT checked here: a "
                 "prompt-only response has no letter+hex reply in it, so ok is "
                 "False by construction and checking it would be a false red.")
        first = adp.cmd("C")        # may be the HIO-003 first-command artefact
        rec.record("first_after_esc", first.raw)
        r = adp.cmd("C")
    else:
        adp.enter()                 # resync + ESC + throwaway
        r = adp.cmd("C")
        rec.note("CONTRACT-ONLY PATH: the pinned API has no primitive that sends "
                 "a bare ESC, so the prompt is observed as the trailing "
                 "PROMPT_CHAR of a command reply (ADP_LINEACK2 :738) instead of "
                 "standing alone. The proof is the same -- a prompt exists only "
                 "inside the monitor -- but it is one step less direct.")
    rec.check("monitor answers a command once entered", r.ok is True, got=r.raw)
    rec.check("reply is the echoed command letter, not '?'", r.letter == "C",
              got=r.raw)
    rec.check("prompt character '%s' present in the reply" % PROMPT,
              PROMPT in (r.raw or ""), got=r.raw)
    rec.record("entry_reply", r.raw)


# ---------------------------------------------------------------- HIO-003 ----


@test("HIO-003", tier=0, needs=["HIO-002"], preamble=False,
      purpose="First-command '?' artefact, and recovery from it. The '?' is a "
              "LINK-layer artefact (a residual byte in the RX FIFO after a host "
              "resync), NOT an ADP feature -- ADP_RXCMD/ADP_ACTION have no "
              "first-command rule. So the PASS is the SECOND command answering, "
              "and that is what goes RED: a resynced link that never recovers, or "
              "one that leaves more than one residual byte, rejects the second "
              "command too. Whether the FIRST is rejected is recorded, not "
              "checked: if a die ever answers the first command cleanly, the host "
              "link changed and the SoC did not. The pre-state is forced to the "
              "STDIO bypass first, because otherwise the '?' is ambiguous three "
              "ways -- the link artefact, the parser's default arm, or (trap 3) a "
              "bare ESC swallowed as a command letter inside the monitor, whose "
              "dangling line the next command completes and is rejected for. That "
              "third mechanism would let this test pass while measuring the wrong "
              "thing, which is worse than failing.")
def hio_003(adp, rec):
    # enter() absorbs the artefact by design, so re-create the condition rather
    # than observe nothing: resync (+ a bare ESC where the harness offers one)
    # is the entry preamble minus the throwaway command.
    esc = _esc(adp)
    if esc is not None:
        was_in, still_in = _to_bypass(adp, rec)
        rec.check("the port is in the STDIO bypass before the entry preamble",
                  still_in is False, got=rec.values.get("probe_after_exit"))
        adp.resync()
        e = esc()
        rec.record("esc_reply", e.raw)
        rec.check("ESC entered the monitor (prompt seen), so the '?' below is the "
                  "ENTRY artefact and not a swallowed ESC",
                  PROMPT in (e.raw or ""), got=e.raw)
        rec.record("recreation",
                   "X -> bypass -> resync -> bare ESC (the entry preamble minus "
                   "the throwaway command)")
    else:
        adp.resync()
        rec.record("recreation", "resync only (no bare-ESC primitive available)")
    r1 = adp.cmd("C")
    r2 = adp.cmd("C")
    rec.record("first_after_resync", r1.raw)
    rec.record("first_rejected", r1.letter == "?")
    rec.check("second command answers cleanly", r2.ok is True and r2.letter == "C",
              got=r2.raw)
    rec.check("second command is not a second rejection", r2.letter != "?",
              got=r2.raw)
    if r1.letter != "?":
        rec.note("The first command after resync was NOT rejected (%r). Per the "
                 "plan this means the host link behaviour changed; the SoC-side "
                 "expectation is unchanged. Re-check adp.enter()'s throwaway: if "
                 "the artefact is gone, enter() is now swallowing a real command."
                 % r1.raw)


# ---------------------------------------------------------------- HIO-004 ----


@test("HIO-004", tier=0, needs=["HIO-002"],
      purpose="Unknown-command rejection: 'Z' hits the else-branch of ADP_ACTION "
              "(:596) -> ADP_UNKNOWN (:662) -> '?'. RED if a parser that accepts "
              "anything answers 'Z 0x...'. The known-good command issued first is "
              "the control that makes the '?' meaningful: without it, a '?' could "
              "be the first-command link artefact of HIO-003 rather than "
              "FNvalid_cmd's default arm.")
def hio_004(adp, rec):
    adp.enter()
    good = adp.cmd("C")
    rec.check("CONTROL: a valid command answers before the probe",
              good.ok is True and good.letter == "C", got=good.raw)
    bad = adp.cmd("Z")
    rec.check("unknown command 'Z' is rejected with '?'", bad.letter == "?",
              got=bad.raw)
    rec.check("'Z' is not echoed as a valid command", bad.letter != "Z",
              got=bad.raw)
    rec.record("unknown_cmd_reply", bad.raw)
    still = adp.cmd("C")
    rec.check("monitor still usable after a rejection",
              still.ok is True and still.letter == "C", got=still.raw)


# ---------------------------------------------------------------- HIO-005 ----


@test("HIO-005", tier=0, needs=["HIO-002"],
      purpose="Address register write/readback, BOTH POLARITIES. adp_addr is "
              "written from adp_param when a param is present, and reported as "
              "{3'b111, adp_addr} when it is not (:551). RED on any stuck-at bit: "
              "0x12345678 and 0xEDCBA987 are bitwise complements, so a bit stuck "
              "either way shows as a mismatch in one pass or the other. ONE VALUE "
              "ALONE CANNOT DETECT A STUCK-AT-THAT-VALUE FAULT -- that is why both "
              "run, and why a failure of only one half is still a fail.")
def hio_005(adp, rec):
    adp.enter()
    for name, val in (("pattern_a", 0x12345678), ("pattern_b", 0xEDCBA987)):
        w = adp.cmd("A x%08X" % val)
        rec.check("A x%08X echoes the value written" % val,
                  w.ok is True and w.letter == "A" and w.value == val,
                  got=w.raw)
        rb = adp.cmd("A")
        rec.check("bare A reports back 0x%08X" % val,
                  rb.ok is True and rb.letter == "A" and rb.value == val,
                  got=rb.raw)
        # 8 digits -> FNparam2size(2'b11) -> 32-bit, latched at :537 by this
        # command's own EOL. A short echo means the digit counter is wrong.
        rec.check("echo width is 8 nibbles for 0x%08X" % val, _width(w.raw) == 8,
                  got=w.raw)
        rec.record(name, rb.value)
    rec.note("0x12345678 ^ 0xEDCBA987 == 0xFFFFFFFF: every bit is exercised in "
             "both directions across the two passes.")


# ---------------------------------------------------------------- HIO-006 ----


@test("HIO-006", tier=0, needs=["HIO-002", "HIO-005"],
      purpose="Access-size encoder — LOAD-BEARING FOR THE WHOLE SUITE. The hex "
              "DIGIT COUNT of a parameter sets HSIZE via FNsize_inc (:143-154) -> "
              "FNparam2size (:156-167), and the same size picks the printed width "
              "at ADP_WRITEHEX9 (:693-698). RED when a broken digit counter prints "
              "the wrong width: no param must give 8 nibbles (32-bit), 1 digit 2 "
              "nibbles (8-bit), 3 digits 4 nibbles (16-bit). A miscount here means "
              "every parameter in every later test is silently the wrong access "
              "size, which is why plan section 3 A3 says STOP on a failure. Uses "
              "adp.cmd() directly, never the fixed-width helpers, because those "
              "always format 8 digits and so cannot exercise the encoder at all.")
def hio_006(adp, rec):
    adp.enter()

    adp.cmd("A x%08X" % BOOTROM_ADDR)
    r0 = adp.cmd("R")
    rec.check("no parameter -> 32-bit, 8 nibbles", _width(r0.raw) == 8, got=r0.raw)
    rec.check("32-bit read of the boot ROM is OK and correct",
              r0.error is False and r0.value == BOOTROM_WORD, got=r0.raw)

    adp.cmd("A x%08X" % BOOTROM_ADDR)
    r1 = adp.cmd("R1")
    rec.check("1 hex digit -> 8-bit, 2 nibbles", _width(r1.raw) == 2, got=r1.raw)
    rec.check("byte read still reports OK", r1.error is False, got=r1.raw)
    rec.record("byte_read", r1.raw)

    # DELIBERATE DEVIATION, trap 2: the plan says `R100` here, but the digit
    # count sets the size while the parameter VALUE sets the read count, so R100
    # is 0x100 = 256 halfword reads (MEASURED: R010 gives 16 lines and advances
    # the address by 0x20). `R000` is the same 3-digit encoder path with a count
    # of zero: one line, one bus read, same 16-bit size.
    adp.cmd("A x%08X" % BOOTROM_ADDR)
    r2 = adp.cmd("R000")
    rec.record("size_16bit_form", "R000")
    rec.check("3 hex digits -> 16-bit, 4 nibbles", _width(r2.raw) == 4, got=r2.raw)
    rec.check("a zero count is one line, not a block dump",
              len(_replies(r2.raw)) == 1, got=r2.raw)

    rec.record("widths", [_width(r0.raw), _width(r1.raw), _width(r2.raw)])
    rec.note("The plan's HIO-006 issues R100 for its 3-digit parameter; that is a "
             "256-iteration block dump. R000 exercises the identical digit "
             "counter in one line. The repeat arm itself is HIO-009's job.")


# ---------------------------------------------------------------- HIO-007 ----


@test("HIO-007", tier=0, control=True,
      gates=["HIO-005", "HIO-006", "HIO-008", "HIO-009", "HIO-011", "HIO-114"],
      purpose="THE MASTER CONTROL OF THE SUITE — bus-error flag discrimination. "
              "Proves '!' (ADP_ECHOBUS :680) can be BOTH raised and cleared: "
              "0x30000000 is undecoded by debug_m and reaches the default slave, "
              "which ERRORs; 0x08000000 is the boot ROM and must answer with a "
              "space. RED if either half misbehaves, and the failure is not local: "
              "if '!' never raises, every R!-based test in this suite is vacuous; "
              "if it never clears, every OK-based test is vacuous. That includes "
              "the whole of the HIO-114 census. This is ABORT GATE 3; the runner "
              "should re-run it after every destructive test and after every "
              "sweep. Its Tier-4 counterpart HIO-401 (the poll engine's own "
              "match/timeout pair) is the other master control -- the two together "
              "are what makes any green in this suite mean anything. NOTE it can "
              "never be vacuous itself: the two halves contradict each other, so a "
              "flag stuck in either direction fails one of them.")
def hio_007(adp, rec):
    adp.enter()

    a = adp.read(UNMAPPED_ADDR)
    rec.check("unmapped 0x%08X raises '!'" % UNMAPPED_ADDR, a.error is True,
              got=a.raw)
    rec.check("unmapped read still returns a well-formed reply (monitor usable)",
              a.ok is True, got=a.raw)
    rec.record("unmapped_reply", a.raw)
    rec.record("unmapped_value", a.value)

    b = adp.read(BOOTROM_ADDR)
    rec.check("mapped 0x%08X clears '!'" % BOOTROM_ADDR, b.error is False,
              got=b.raw)
    rec.check("mapped read returns the measured boot ROM word",
              b.value == BOOTROM_WORD, got=b.raw)
    rec.record("bootrom_word", b.value)
    rec.record("mapped_reply", b.raw)

    rec.note("Order matters and is part of the test: the ERROR is raised FIRST, "
             "so the clear also proves the sticky flag is really cleared per reply "
             "at ADP_WRITEHEX0 (:715) rather than merely never having been set. "
             "r.error is read directly -- never inferred from value == 0, because "
             "an OK-with-zeros and an ERROR both print 0x00000000.")
    if a.value not in (None, 0):
        rec.note("Unmapped read returned non-zero data 0x%08X where the default "
                 "slave is expected to give 0x00000000. The flag is what this test "
                 "gates on, but that data is worth explaining before trusting any "
                 "OK-with-zeros classification." % a.value)


# ---------------------------------------------------------------- HIO-008 ----


@test("HIO-008", tier=0, needs=["HIO-002", "HIO-005", "HIO-006"],
      purpose="Address auto-increment: adp_addr advances by (1 << adp_size) per "
              "COMPLETED transfer (:448, :466). Three 32-bit reads must leave the "
              "address exactly 12 bytes on. RED both ways, which is why the final "
              "`A` readback is the PASS criterion and not the data: adp_addr_inc "
              "stuck low leaves the address at 0x08000000 (and all three words "
              "identical); stuck high advances on non-transfer cycles and "
              "overshoots. Reading the address back also makes this immune to a "
              "ROM that happens to hold repeated words.")
def hio_008(adp, rec):
    adp.enter()

    adp.cmd("A x%08X" % BOOTROM_ADDR)
    words = []
    for i in range(3):
        r = adp.cmd("R")
        rec.check("read %d is OK" % i, r.ok is True and r.error is False, got=r.raw)
        rec.check("read %d is 32-bit wide" % i, _width(r.raw) == 8, got=r.raw)
        words.append(r.value)
    rec.record("rom_words", words)

    a = adp.cmd("A")
    rec.check("address advanced by exactly 12 (three 32-bit transfers)",
              a.ok is True and a.value == BOOTROM_ADDR + 12, got=a.raw)
    rec.record("end_address", a.value)
    rec.check("first word matches the measured boot ROM word",
              words[0] == BOOTROM_WORD, got=words)
    if len(set(words)) == 1:
        rec.note("All three words are identical (0x%08X). With the address "
                 "readback correct this is a property of the ROM, not a stuck "
                 "increment -- but record it, because it removes the data-side "
                 "corroboration this test would otherwise carry." % words[0])


# ---------------------------------------------------------------- HIO-009 ----


@test("HIO-009", tier=0, needs=["HIO-002", "HIO-006", "HIO-008"],
      purpose="Block dump: `R` with a non-zero count re-arms at ADP_LINEACK2 "
              "(:727-729) until adp_count hits zero. Rx00000010 must give exactly "
              "16 replies and leave the address 0x40 on. RED unambiguously in both "
              "directions -- a broken repeat arm gives 1 line, a miscounted loop "
              "gives 15 or 17, and each of those also lands the end address "
              "somewhere other than 0x08000040. The block engines are the only "
              "reason the Tier-2 memory tests are tractable at ~130 ms per "
              "single read, so this is the test that licenses all of them.")
def hio_009(adp, rec):
    adp.enter()

    adp.cmd("A x%08X" % BOOTROM_ADDR)
    d = adp.cmd("R x00000010", timeout_ms=15000)
    reps = [r for r in _replies(d.raw) if r[0] == "R"]
    rec.record("dump_lines", len(reps))
    rec.check("exactly 16 read replies in the dump", len(reps) == 16,
              got=(len(reps), d.raw))
    if reps:
        rec.check("first dumped word is the measured boot ROM word",
                  reps[0][3] == BOOTROM_WORD, got=reps[0])
        rec.check("no dumped beat raised '!'", not any(r[1] for r in reps),
                  got=[r for r in reps if r[1]])
        rec.check("every dumped beat is 32-bit wide",
                  all(r[2] == 8 for r in reps), got=[r[2] for r in reps])
        rec.record("dump_words", [r[3] for r in reps])

    a = adp.cmd("A")
    rec.check("end address is 0x%08X (16 x 4 bytes)" % (BOOTROM_ADDR + 0x40),
              a.ok is True and a.value == BOOTROM_ADDR + 0x40, got=a.raw)
    rec.record("end_address", a.value)
    rec.note("If the line count reads 1 while the end address is correct, the SoC "
             "dumped correctly and the CLIENT truncated its capture -- fix the "
             "harness's raw retention before believing the red, because the whole "
             "of Tier 2 depends on reading a multi-line dump back.")


# ---------------------------------------------------------------- HIO-010 ----


@test("HIO-010", tier=0, needs=["HIO-002"],
      purpose="Exit and re-enter: `X` emits LF and drops to the STDIO bypass "
              "(:576, :671); ESC must bring the monitor back. RED if `X` wedges "
              "the port -- the command after re-entry times out or never prompts, "
              "and the port would then need a reset to recover. Every recovery "
              "procedure in plan section 3 depends on this being true, including "
              "the use of HIO-509 as the standard 'start over'.")
def hio_010(adp, rec):
    adp.enter()
    before = adp.cmd("C")
    rec.check("CONTROL: monitor answers before the exit",
              before.ok is True and before.letter == "C", got=before.raw)

    x = adp.cmd("X", timeout_ms=2000)
    rec.record("exit_reply", x.raw)
    rec.note("`X` prints LF and goes to STD_IOCHK: no reply word and no prompt are "
             "expected, so a timeout on this command is the correct behaviour and "
             "is recorded, not checked. On this SoC the STDIO bypass is inert -- "
             "nothing ever sources STDOUT (plan section 1.3).")

    esc = _esc(adp)
    if esc is not None:
        adp.resync()
        e = esc()
        rec.record("reentry_esc_reply", e.raw)
        rec.check("ESC prompts again after the exit", PROMPT in (e.raw or ""),
                  got=e.raw)
        adp.cmd("C")            # the first-command artefact, per HIO-003
    else:
        adp.enter()             # resync + ESC + throwaway: documented re-entry
    after = adp.cmd("C")
    rec.check("monitor re-entered after X", after.ok is True and after.letter == "C",
              got=after.raw)
    rec.check("prompt present after the round trip", PROMPT in (after.raw or ""),
              got=after.raw)

    r = adp.read(BOOTROM_ADDR)
    rec.check("bus access works after the round trip",
              r.error is False and r.value == BOOTROM_WORD, got=r.raw)
    rec.record("post_reentry_read", r.raw)


# ---------------------------------------------------------------- HIO-011 ----


@test("HIO-011", tier=0, needs=["HIO-002", "HIO-006"],
      purpose="GPO8 register and its SoC-top loopback. `C` reports "
              "{GPI8, GPO8, param[15:0]} (:674); Cx0000020f sets GPO bits 0x0F "
              "(the set arm is adp_param[31:8] == 24'h000002 acting on "
              "adp_param[7:0], :560-561) and Cx0000010f clears them (:558-559). "
              "THE TWO MIRRORED BYTES ARE THE DISCRIMINATOR: 0x0f0f020f is a pass; "
              "0x000f020f (GPO set, GPI zero) means the top-level loopback is "
              "broken; 0x0000020f means the set arm never fired. The low byte MUST "
              "be non-zero -- the Cx00000200 that was actually issued during "
              "bring-up sets NOTHING and merely echoes its own parameter, which is "
              "the null-result form of this test and was misread as a pass. "
              "WHAT THIS DOES NOT PROVE: GPO8 drives nothing on this SoC -- it is "
              "wired to its own GPI8 (nanosoc_multicore_soc.sv:1585-1586) and "
              "appears nowhere else -- so this tests the ADP register and its "
              "report path only, never a system effect. Do not plan a reset around "
              "`C`; the debug_resetreq wiring belongs to the legacy single-core "
              "top this chiplet does not use.")
def hio_011(adp, rec):
    adp.enter()
    # Every `C` here is either bare or carries 8 digits, and :537 re-derives the
    # size from that on each command line, so the report is always 32 bits wide.
    # MEASURED 2026-08-25: a bare `C` straight after `R1` still answers
    # `C 0x00000000`. An earlier revision issued a width-restoring read here on
    # the strength of a derivation; it was refuted on hardware and removed.
    r0 = adp.cmd("C")
    rec.check("initial report is well formed and 32-bit wide",
              r0.ok is True and r0.letter == "C" and _width(r0.raw) == 8,
              got=r0.raw)
    rec.record("gpo_initial", _gpo(r0.value) if r0.value is not None else None)
    rec.record("gpi_initial", _gpi(r0.value) if r0.value is not None else None)
    rec.check("at rest GPI mirrors GPO", _gpi(r0.value) == _gpo(r0.value),
              got=r0.raw)
    if r0.value is not None and _gpo(r0.value) != 0x00:
        rec.note("GPO is 0x%02X on entry, not its 0x00 reset value: a previous "
                 "session left bits set. The set/clear checks below are absolute, "
                 "so this does not weaken them -- but the plan's 'first C reports "
                 "GPO = 0x00' is not true on this die right now."
                 % _gpo(r0.value))

    s = adp.cmd("C x0000020f")
    rec.check("set arm: GPO[23:16] == 0x0F", _gpo(s.value) == 0x0F, got=s.raw)
    rec.check("loopback: GPI[31:24] == 0x0F", _gpi(s.value) == 0x0F, got=s.raw)
    rec.check("parameter echoed in [15:0]", (s.value or 0) & 0xFFFF == 0x020F,
              got=s.raw)
    rec.record("set_reply", s.raw)
    rec.record("set_word", s.value)

    p = adp.cmd("C")
    rec.check("GPO persists across a bare report", _gpo(p.value) == 0x0F, got=p.raw)
    rec.check("GPI still mirrors it", _gpi(p.value) == 0x0F, got=p.raw)
    rec.check("bare report echoes no parameter", (p.value or 0) & 0xFFFF == 0x0000,
              got=p.raw)

    c = adp.cmd("C x0000010f")
    rec.check("clear arm: GPO back to 0x00", _gpo(c.value) == 0x00, got=c.raw)
    rec.check("loopback follows the clear: GPI back to 0x00", _gpi(c.value) == 0x00,
              got=c.raw)
    rec.record("clear_reply", c.raw)

    f = adp.cmd("C")
    rec.check("cleared state persists", _gpo(f.value) == 0x00 and _gpi(f.value) == 0x00,
              got=f.raw)
    rec.record("gpo_final", _gpo(f.value) if f.value is not None else None)
    rec.note("Set and clear are opposite polarities of the same register, so no "
             "single stuck value can satisfy both -- that pair is what stops this "
             "from being another Cx00000200.")
