# Dry-run submission candidate — 24 August 2026   ** USE THIS ONE **

    file  nanosoc_eth_chiplet_pads_DRYRUN_20260824_pinfix.gds
    md5   3215cbe15fa373b4112fb6631b2c660d
    size  302,611,140
    top   nanosoc_eth_chiplet_pads

Supersedes `_DRYRUN_20260823_rzG` (md5 41a0baee), which imec graded on 24 Aug and
which carries a FUNCTIONAL DEFECT — see below. Do not submit rzG again.

    rzG      750 total / 14 design-owned / 3 bare macro pins / PO.R.8 = 14 post-merge
    pinfix   738 total /  1 design-owned / 0 bare macro pins

## What changed, and why it matters more than the DRC count

**rzG shipped with three macro pins carrying no metal on any layer:**

    way0 u_..._u_cache_subsystem_u_way0_cache_ram_data_ram_0_word_3_i   D[27], Q[27]
    way1 u_..._u_cache_subsystem_u_way1_cache_ram_data_ram_0_word_3_i   D[27]

Nets `RAMCLD0WDATA[123]` / `RAMCLD0RDATA[123]`. Bit 123 of a 4x32 line = word_3
bit 27. **Cache data bit 123 was unwritable on both ways and way0's read of it
was lost.** imec found the consequence post-merge as 14 `PO.R.8` floating gates.

CAUSE: the route stage's regular-wire DRC repair runs `delete_routes
-regular_wire_with_drc` then `route_eco -fix_drc`. `-fix_drc` **refuses open nets
by design** (`TCRcom/route_eco.html`) and `delete_routes` had just created four.
The nets stayed deleted; a deleted net carries no DRC marker, so the step's own
metric `Regular Wire 5 -> 0` scored the failure as a success. The tool said so in
the run log and no gate read it:

    #INFO: There were 4 open nets and ecoRoute -fix_drc will not route these
           nets. User needs to use ecoRoute command to route the open nets.
    #WARNING (NRDR-27) Net ...RAMCLD0WDATA_123 is not globally routed.

FIX (this stream): `write_def -selected -routing` from the pre-repair
`route_preopt` checkpoint, read back into the routed DB — literally "the repair
never ran", restoring the exact wires the timing-driven route and post-route
optimisation produced. An alternative using `route_eco -target` measured
identically and is kept as `_eco`.

**The repair was never doing anything anyway.** Its real before/after is 10 -> 5,
not the 35 -> 5 the log implies — `flow_step filler` closed the other 25 M1
EndOfLine markers minutes earlier. All five the repair "closed" were the two
cache nets, closed by deleting them.

## Provenance

    base run    gdsrun-20260824-valid4 (place 41m rc=0 / cts / route, HARD FAILURES none)
    fix run     build/pinfix-20260824, Option 1 arm, DB db_orig_final
    also carries ASIC/genus-innovus/scripts/pg_drc_post_route_edits.tcl
                 (M8.S.3 x2 -> 0 by VIA8 master clone; VIA4.R.4:M5 -> 0 by
                  re-cutting one PG via 1 -> 2 along the landing. No metal moved.)
    logo        AP-only at (663.875, 1000.0), 727.750 x 320.250 um

## Measured — ASIC/genus-innovus/calibre_runs/drc_pinfix_orig_logo_0824/

    TOTAL DRC Results Generated:   738 (4329)
      less waived (PO.R.8)         691
      REPORTED                      47   density + dummy markers + the 1 below

    DESIGN-OWNED GEOMETRY: 1
      VIA3.R.4:M4   1   inside vendor macro flash_cache_dataVIA_V3_1X1. Legal in
                        isolation; illegal only because OUR PG via-array M4 pad
                        sits 0.440 um below it. Second cut needs 0.300 against a
                        0.200 macro riser and a 0.265 M3 rail; widening blocked by
                        neighbouring macro risers at 0.140. WAIVER, as vendor-macro
                        context.

    ZERO, all previously non-zero on rzG:
      M8.S.3 2->0   VIA4.R.4:M5 1->0   M4.S.1 1->0   M5.W.1 1->0   M5.A.1 1->0
      M9.W.1 1->0   G.4:M5i 2->0       G.4:M6i 4->0
      LOGO.S.1 / LOGO.O.1 / LOGO.R.4 = 0, real zeros (not capped)

    648-pin macro census (LEF pin rects vs streamed metal)   3 bare -> 0
    check_connectivity -type regular                         2 open -> 0
    setup WNS/TNS/FEP    +0.018 / 0.000 / 0
    hold  WNS/TNS/FEP    -0.006 / -0.020 / 11   (was -0.023 / -0.042 / 12)
    density              6121 core windows of 12774, unchanged, none saturated

Calibre delta against a matched no-change control on a byte-identical deck: ZERO.
The five Innovus markers the repair had been "closing" return, and they are
violations against the macro's LEF ABSTRACTION, not silicon — flattening
flash_cache_data.gds2 with positive controls gives real VIA3 at the cut-short
sites = 0 (control 19,986 in-macro) and real M3 in the Metal Short box = 0
(control 120,528).

## NOT PROVEN BY THIS STREAM

  - **The foundry has not re-graded.** PO.R.8 = 14 was imec's measurement on a
    merged database we cannot reproduce — no standard-cell layout exists on this
    site. Our evidence is pins-have-metal, connectivity clean, Calibre unchanged.
    Only another imec run closes it.
  - 691 PO.R.8 remain waived (`PO.R.8-blackbox-context`); imec's own runs show 21
    of 22 cells clear on merge, so the mechanism holds, but the waiver's
    withdrawal condition has technically fired and it needs re-specifying
    per-cell rather than on the run total.
  - The underlying pin-access squeeze is UNCHANGED: flash_cache_data blankets its
    whole footprint with VIA1/2/3 obstruction and leaves a 0.42 um M3 band with
    0.14 um clearance per pin. Both fixes restore the wires; neither widens the
    corridor. Next-spin item.

## Ask imec, with this submission

  1. Confirm PO.R.8 returns to 0 (or report it BY HIERARCHICAL INSTANCE PATH —
     their merged DB can name the cell, ours cannot).
  2. Q7: set `PITCH_70_STAGGER`. Measured CB opening is 58.000 x 66.000, which
     hits the P70 minimums exactly on both axes; the P80 branch demands 65 and 75.
     Four results, one switch.
  3. Q8: confirm the acceptance run merges tcbn65lp + tphn65lpgv2od3_sl + tpbn65v.
  4. Return the merged GDS so the wire-bond deck stops being unmeasurable here.
