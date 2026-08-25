# HOSTIO4 suite — API contract (PINNED, do not change)

Every tier module is written against exactly this API. `harness.py` implements it;
tier modules import it. Nothing else is shared. One file per agent, no collisions.

## Import

    from harness import Adp, Reply, test, Rec, HZ

## Adp — the link

    adp.enter()                  # resync + ESC + one throwaway cmd. Idempotent.
    adp.resync()                 # force host PIO resync (watchdog also does it)
    adp.cmd(c, timeout_ms=4000) -> Reply      # send one ADP command line
    adp.read(addr)  -> Reply     # A x{addr:08X} ; R   (NOTE: R auto-increments)
    adp.write(addr, val) -> Reply# A x{addr:08X} ; W x{val:08X}
    adp.raw_rx(ms)  -> list[int] # drain RX words, no command sent (for HIO-001)

`addr`/`val` are ints. The harness formats `x` + exactly 8 hex digits unless you
call `adp.cmd()` yourself to exercise the size encoder (HIO-006).

## Reply

    r.raw      str   e.g. "R!0x00000000]"
    r.letter   str   'R', 'W', 'A', 'C', 'M', 'V', 'P', 'S' — or '?' if rejected
    r.error    bool  True when '!' sits where the space should be  <-- THE flag
    r.value    int|None
    r.ok       bool  well-formed reply received (not a timeout)

`r.error` is the ONLY correct way to test for a bus error. Never infer it from
`r.value == 0` — an OK-with-zeros and an ERROR both show 0x00000000.

## Declaring a test

    @test("HIO-007", tier=0, control=True, hazard=None,
          purpose="Bus-error flag discrimination — the control pair")
    def hio_007(adp, rec):
        a = adp.read(0x30000000)
        rec.check("unmapped raises !", a.error is True, got=a.raw)
        b = adp.read(0x08000000)
        rec.check("mapped clears !", b.error is False, got=b.raw)
        rec.record("bootrom_word", b.value)

Kwargs:
  tier      0..5
  control   True if other tests are only trustworthy when this passes
  gates     list of test IDs this test gates (optional; implies control)
  hazard    None or an HZ.* constant (see below)
  destroys  optional str, what state it destroys (e.g. "shared SRAM")
  needs     optional list of test IDs that must have PASSED first

## Rec — result recording

    rec.check(label, bool_expr, got=...)   # one assertion; all must hold to PASS
    rec.record(key, value)                 # capture a value into the die record
    rec.skip(reason)                       # raise; test reports SKIP not FAIL
    rec.note(text)                         # free text into the record

## Hazards — the runner refuses these unless explicitly enabled

    HZ.IRREVERSIBLE   # e.g. CPU0 release; needs --allow-irreversible
    HZ.DESTRUCTIVE    # destroys memory/state; needs --allow-destructive
    HZ.WEDGE_RISK     # cross-die peer read; needs --allow-wedge, never unattended
    HZ.RESET          # resets the SoC

## THE RULE THAT MATTERS

A test whose `control` failed is reported **VOID**, never PASS. Vacuous greens are
the specific failure mode this suite exists to prevent. If you cannot state how a
test goes red, mark it `weak=True` and say why in `purpose` — do not quietly
include it as coverage.

## Measured facts you must build on (do NOT re-derive)

- ~130 ms per 32-bit read. Budget accordingly; no bulk dumps.
- The resync watchdog MUST be live or the port looks like dead silicon (0/16 reads).
- The FIRST command after ESC is always rejected with '?'. `adp.enter()` absorbs it.
- RX words are 12-bit; only (w & 0xf00) == 0 are console data bytes.
- `R` auto-increments. Re-issue `A` between reads of the same address.
- Undecoded address -> `R!0x00000000`; the monitor stays usable.
- ETHMAC at 0x40000000 is UNREACHABLE (R!). Do not write register tests for it.
- 0x84xxxxxx is a CPU1 ROM alias from ADP, not a hole. Not a hazard here.
