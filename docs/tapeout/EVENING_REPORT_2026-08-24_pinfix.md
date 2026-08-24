# Build record — `_DRYRUN_20260824_pinfix`, 24 August 2026

    stream  ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260824_pinfix.gds
    md5     3215cbe15fa373b4112fb6631b2c660d
    size    302,611,140
    top     nanosoc_eth_chiplet_pads

Supersedes `_DRYRUN_20260823_rzG` (md5 `41a0baee`), which imec graded on 24 Aug
and which carries a functional defect. **Do not submit rzG again.**

---

## 1. What was wrong with the stream we had already sent

Three macro pins shipped with **no metal on any layer**:

    way0 u_..._u_cache_subsystem_u_way0_cache_ram_data_ram_0_word_3_i   D[27], Q[27]
    way1 u_..._u_cache_subsystem_u_way1_cache_ram_data_ram_0_word_3_i   D[27]

Nets `RAMCLD0WDATA[123]` / `RAMCLD0RDATA[123]`. Bit 123 of a 4x32 cache line is
word_3 bit 27. **Cache data bit 123 was unwritable on both ways and way0's read
of it was lost.** A functional defect, not a DRC nuisance.

imec's 24 Aug return reported it as **14 `PO.R.8` floating gates** post-merge.
That return was also the FIRST imec run to grade our actual shipping lineage —
every earlier archive graded a retired 10 August snapshot, and nobody had noticed.

## 2. Root cause

The route stage's regular-wire DRC repair:

    delete_routes -regular_wire_with_drc -status ROUTED
    route_eco -fix_drc

`-fix_drc` **refuses open nets by design** — Innovus documents it
(`TCRcom/route_eco.html`: *"If open nets are found in the design, NanoRoute skips
them"*) — and `delete_routes` had just created four. The rip-up was permanent.

A deleted net carries no DRC marker, so the step's own success metric,
`Regular Wire 5 -> 0`, **scored the failure as a success.**

The tool said so, in our own run log, and no gate parsed it:

    #INFO: There were 4 open nets and ecoRoute -fix_drc will not route these
           nets. User needs to use ecoRoute command to route the open nets.
    #WARNING (NRDR-27) Net ...RAMCLD0WDATA_123 is not globally routed.

**The repair was never achieving anything.** Its real before/after is 10 -> 5,
not the 35 -> 5 the log implies — `flow_step filler` closed the other 25 M1
EndOfLine markers minutes earlier. All five the repair "closed" were the two cache
nets, closed by deleting them.

### The underlying squeeze, unchanged and still open

`flash_cache_data` declares full-plate OBS on VIA1, VIA2 **and** VIA3 over its
entire footprint, while its M1/M2/M3 plates stop at y=0.42 so pins stay reachable.
A pin can be landed on inside the footprint but **its layer transition cannot
happen there** — every pin must make its M3->M4 via in a corridor just off the pin
edge, with 0.14 um clearance per pin. Nothing in the flow protects that corridor.
Both fixes restore the wires; neither widens it. **Next-spin item.**

## 3. The fix

Two arms, both measured against a matched no-change control on a byte-identical
deck. **Option 1 shipped**, on provenance grounds:

  - **Option 1 (`_orig`, shipped)** — `write_def -selected -routing` from the
    pre-repair `route_preopt` checkpoint, read back into the routed DB. Literally
    *the repair never ran*: the exact wires the timing-driven route and post-route
    optimisation produced. Does not use `route_eco` at all.
  - Option 2 (`_eco`) — `route_eco -target`, the mode that DOES route open nets.
    Identical acceptance numbers; harsher Innovus marker mix (3 shorts vs 1).

Also folded in: `ASIC/genus-innovus/scripts/pg_drc_post_route_edits.tcl` —
`M8.S.3` x2 cleared by cloning a VIA8 master with a 10 nm smaller M8 bottom rect
(trim M8, never M9: M8 has 0.220 slack, M9 has zero against `M9_EN_1`), and
`VIA4.R.4:M5` cleared by re-cutting one PG via 1 -> 2 along the landing, no metal
moved.

## 4. Verification — three independent checks, all on the shipped bytes

    Calibre signoff   calibre_runs/drc_pinfix_orig_logo_0824/
        total 738 / reported 47 / non-density 14 / REAL GEOMETRY 1
        LOGO.S.1, LOGO.O.1, LOGO.R.4 = 0, real zeros (not capped)
        Calibre delta vs matched control: ZERO

    Macro pin gate    scripts/ci/gds_macro_pin_connected.py
        PASS — 0 bare of 748 signal pins across 10 placed macros
        (rzG: FAIL, 3 bare of 648 — the exact pins the foundry found)
        1 via-only (way0 word_3 Q[27]) reported as its own class, not hidden

    LVS               LVS_PG=1 LVS_PG_PIN_TEXT=1
        verdict INCORRECT — EXPECTED, and not the thing to grade on
        DISCRIMINATING ASSERTION PASSES:
                          RAMCLD0*[123]   g87561   u_cache_subsystem
            rzG                  2           2            388
            pinfix               0           0            384
        The 384 is the population control: the report DID cover the cache
        subsystem, so the zeros are a clean, not a coverage gap.

    Timing            setup WNS +0.018 / FEP 0
                      hold  WNS -0.006 / FEP 11   (control -0.023 / 12; improved)

**Why the LVS verdict is not the gate.** It stays INCORRECT for known reasons:
`.GLOBAL VSS` floods 17,233 unmatched source nets, and the pad ring has no LEF
PINs to compare. Grading on the verdict is grading on noise — which is precisely
why it was ignored. Grade on *zero missing-connection discrepancies on nets below
the top level*.

## 5. The finding that matters most for how we work

**Our own LVS caught this a day before the foundry did.**

`lvs/run/nanosoc_eth_chiplet_pads.lvs.rep:3612` —

    62  Net X99/6106   Xu_..._u_cache_subsystem_RAMCLD0RDATA[123]
        --- 1 Connections ---        --- 2 Connections ---
        ** missing connection **     Xu_..._u_soc/Xg87561:B2

Named, located, correctly diagnosed. Of all missing-connection entries in that
report, exactly ONE reaches into the SoC core. One `grep` would have isolated it.

It went unread for four independent reasons, each fixable:

  1. the run's own summary said the list was truncated and to use the
     reconciliation table instead — right for counting, fatal as triage;
  2. the report lived in an ephemeral session scratchpad;
  3. `ci/signoff.yaml:1735` collects LVS artifacts from a build path that is
     **measured empty** — the collector points where the run does not write;
  4. the submission record, written **11 minutes earlier**, states "LVS has NEVER
     RUN on this design".

The tool did not whisper: it printed the `INCORRECT` banner, `Error: Connectivity
errors.`, and exited 1.

## 6. Flow changes landed today

    toolkit  9a982be   post-fill re-measure gated on "did the DB change", not
                       "did we add metal" — the gate had been certifying a
                       pre-fill database and was 18 ps optimistic on hold
    toolkit  3a8c30a   re-check connectivity AFTER the repair; hard-fail on an
                       unrouted signal net
    toolkit  cadbd3b   route_eco -target, so the repair actually restores
    super    8040bf5   submodule pin moved 29 commits forward — it had been
                       stale, so runs were using code the pin did not name
    super    baede37   re-pin to cadbd3b (I moved it, then added a commit)
    super    828d53c   the macro pin gate + the tapeout punchlist
    super    14ac4c5   the pinfix provenance record

All toolkit commits are pushed to `origin/fix/tcl-parse-gate-both-directions`.

## 7. What is NOT proven

  - **The foundry has not re-graded.** `PO.R.8 = 14` was imec's measurement on a
    merged database we cannot reproduce — no standard-cell layout exists on this
    site. Our evidence is pins-have-metal, LVS-clean-on-the-assertion, and
    Calibre unchanged. Only another imec run closes it.
    **Wednesday 27 August is the last day for that round-trip.**
  - 691 `PO.R.8` remain waived. imec's own runs show 21 of 22 cells clear on
    merge so the mechanism holds, but the waiver's withdrawal condition has
    technically fired and it needs re-specifying per-cell rather than on a count.
  - `VIA3.R.4:M4` x1 remains: inside vendor macro `flash_cache_dataVIA_V3_1X1`,
    legal in isolation, illegal only because our PG pad sits 0.440 um below it.
    Every lever measured closed. **Waiver, as vendor-macro context.**
  - The pin-escape corridor (section 2) is unwidened.

## 8. Evidence index

    stream          ASIC/submissions/..._DRYRUN_20260824_pinfix.gds  (gitignored)
    provenance      ASIC/submissions/..._DRYRUN_20260824_pinfix.md   (14ac4c5)
    arms            ASIC/eth-chiplet/build/pinfix-20260824/ARMS.txt
                    -- READ THIS FIRST. Four arms; `_orig` is a FIX and `_ctl` is
                       the control. Bind by md5, never by directory name.
    Calibre         ASIC/genus-innovus/calibre_runs/drc_pinfix_orig_logo_0824/
    LVS (fixed)     <session scratch>/lvs_pinfix/run/*.lvs.rep
    LVS (rzG)       <session scratch>/lvs/run/*.lvs.rep

**The two LVS reports exist only in an ephemeral scratchpad and are the only
copies.** The rzG one is the artefact that identified a tapeout-blocking defect a
day before the foundry. Publishing them to `asic-record` is worth more than the
stream, which can always be re-streamed.

## 9. Ask imec with this submission

  1. Confirm `PO.R.8` returns to 0 — and report it **by hierarchical instance
     path, not coordinate**. Their merged database can name the cell; ours cannot,
     and their coordinate frame is offset +20.000 um in X and Y from ours.
  2. **Q7** — set `PITCH_70_STAGGER`. The measured CB opening is 58.000 x 66.000,
     which hits the P70 minimums exactly on both axes; the P80 branch demands 65
     and 75. Four results, one switch, fourth run running the wrong one.
  3. **Q8** — confirm the acceptance run merges all three libraries
     (`tcbn65lp` + `tphn65lpgv2od3_sl` + `tpbn65v`). 736 of 750 results depend on it.
  4. Return the **merged GDS**, so the wire-bond deck stops being unmeasurable
     here — CB, PM, CB2 and UBM are entirely absent from our stream and a local
     run of that deck reads four zeros over empty layers.
