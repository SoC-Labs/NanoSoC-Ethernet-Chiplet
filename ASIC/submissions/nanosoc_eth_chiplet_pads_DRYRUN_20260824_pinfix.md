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
    NOT A PASS -- VACUOUS. Corrected 2026-08-25.
      LOGO.S.1 / LOGO.O.1 / LOGO.R.4 = 0, and G.1/G.2/G.3/CSR.R.1:LOGO = 0, but
      the summary's own layer census reads `LAYER LOGO ... TOTAL Original
      Geometry Count = 0`. The logo recognition layer is absent from the stream
      by choice, so these seven rulechecks ran over an empty layer and could not
      have fired. An earlier revision of this note called them "real zeros (not
      capped)": not-capped is true and beside the point. imec sees the same
      absence from their side as IM.LOGO.R.1:WARN. We are NOT re-adding the
      layer -- on a placed-and-routed die it has no legal placement, and it
      resurrects two 1000-capped rulechecks.

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

## LVS — ran, verdict INCORRECT, and why that is not a blocker

Added 2026-08-25. An earlier revision of this note did not mention LVS at all.
It ran on 24 Aug at 20:19 and it says INCORRECT; silence about that is exactly
the failure mode that nearly shipped the rzG defect, so the reasoning is set out
here in full rather than left for imec to find.

    verdict     INCORRECT
    ports       52 / 52 matched, 0 unmatched either side
    instances   every device type 0 unmatched both sides
                (MN 17,269  MP 51,539  D 1,241  and all std cells)
    nets        270,715 matched / 185 unmatched layout / 18,137 unmatched source

**Graded on the discrepancy list, not the verdict.** The count that discriminates
a real open from pad-model noise is sub-top `missing connection`:

    10 Aug   153 layout-missing connections, 84 of them SUB-TOP
    rzG      95, 3 sub-top   <- includes the RAMCLD bit-123 defect we shipped
    pinfix   97, 1 sub-top

rzG's three include `Xg87561:B2`, the defect this stream fixes. **It is gone.**
LVS confirms the pin fix independently of the macro-pin census.

**The one remaining sub-top entry was traced end to end to real routed metal.**
Discrepancy 65 names `bsp_host_io_0_out` missing a mux output. Chain: Calibre's
own matched-instance line places that mux at (1315.600, 1293.835); its Z pin is
net 3416; that resolves to top net 27448; net 27448 is a terminal of the
HOST_IO_0 pad wrapper. Mux to pad, in metal. Net 27448 is itself listed as
"unmatched layout" -- which is what that bucket actually is.

**Cause: the pad LEF abstract, not our routing.** Each pad pin is repeated as the
same rectangle on every metal layer with no via geometry, so a 5-pin source model
extracts as 33 ports. The router lands on one layer while the pin-name text sits
on another: the named port is an unrouted stub and the routed port is unnamed.
All 97 layout-missing connections sit at the IO pad boundary; none reaches core
logic. The `bsp_*` names are not new either -- on 10 Aug the same population was
called `soc_pad_rx[N]`, mapping one for one.

**18,117 of the 18,137 unmatched source nets are one CDL bug**: `.GLOBAL` omits
VSS. Layout VSS connections minus source VSS connections = 18,117 exactly. The
layout has MORE ground connectivity than the source declares -- the safe
direction. Fix in CDL prep before 1 Sept; it makes the list readable.

**The report we had been reading was truncated.** `LVS REPORT MAXIMUM 1000` hid
17,392 entries. Re-run uncapped: 18,474 discrepancies, identical verdict and
identical counts. Nothing load-bearing was lost this time only because the
layout-side entries happen to occupy positions 1-255 contiguously. Set it to ALL.

**ERC (same run):** all six checks zero and not capped -- mnpg, mppg,
floating.nxwell_float, floating.psub, npvss49, ppvdd49. The floating N-well and
the aborted psub check seen previously are both absent. Coverage caveat: ERC is
device-based and the only transistors in this stream are the merged memory and
ROM macros, so this is "no ERC violation among merged macro devices", not
chip-wide.

**A clean CORRECT is structurally unreachable** while the pads are LEF abstracts
-- 5 declared pins must extract as 33 ports. The 82 unmodelled bondpad instances
are the other line. Neither is fixable by us.

## NOT PROVEN BY THIS STREAM

  - ~~The foundry has not re-graded.~~ **CLOSED 2026-08-25.** imec ran this exact
    stream (their Final Report records md5 3215cbe1..., verified both ways) and
    **PO.R.8 = 0**, down from 14 on rzG. Eight further rules went with it —
    G.4:M5i 2, G.4:M6i 4, M8.S.3 2, M4.S.1, VIA4.R.4:M5, M5.W.1, M5.A.1, M9.W.1.
    Design-owned results 29 -> 2. Antenna 204/204 zero on a real 16m18s run over
    9.25M devices; padring 0 errors 0 warnings. The zero is an EXECUTED zero: the
    report format lists only non-zero rulechecks, the switch tables diff identical
    against the run that DID report 14, and VIA3.R.4:M4 fires in both runs at the
    same core coordinate, so the check descended into the core.
  - 691 PO.R.8 remain waived (`PO.R.8-blackbox-context`); imec's own runs show 21
    of 22 cells clear on merge, so the mechanism holds, but the waiver's
    withdrawal condition has technically fired and it needs re-specifying
    per-cell rather than on the run total.
  - The underlying pin-access squeeze is UNCHANGED, and is now fully diagnosed.
    flash_cache_data blankets VIA1/VIA2/VIA3 over 100% of its footprint with no
    slots, so a pin is reachable only planar and the first layer change must sit
    above the pin edge. Over Q[27]/D[27] a VSS rail-to-M8 stacked via puts SOLID
    M1..M5 plates and cut arrays 0.235 um above that edge, where a VIA3 needs
    0.330-0.360. **Zero legal positions** — established 2026-08-25 by four
    independent investigations, two run blind and one adversarial, with a
    constructive disproof (inserting the best candidate via reproduces the
    predicted shorts to the nanometre) and eleven router settings measured dead.
    THIS STREAM IS SAFE: its wires are restored from the pre-repair checkpoint and
    Calibre sees nothing at the site — the Innovus markers are against the macro's
    LEF abstraction, which is more conservative than its actual GDS, and imec's own
    run on the merged database agrees. The fix for the next spin is a macro move in
    y (+1.20 um gives a 0.835 um pocket); see docs and floorplan.tcl.
  - **A caution for whoever validates the next spin:** check `check_connectivity
    -type regular` on those two nets, NOT `check_drc`. A deleted net has no DRC
    marker, so the DRC gate cannot tell a fixed net from a deleted one. That is
    exactly how rzG shipped: its two bit-123 nets were DELETED, not routed, and
    the flow's own connectivity check reported zero problems.

## Ask imec, with this submission

  1. ~~Confirm PO.R.8 returns to 0.~~ **ANSWERED 2026-08-25: it is 0.** Replaced by
     a new ask — please run ERC / LVS / PadShorts on THIS candidate. The 25 Aug
     archive has no LVS section and its erc report is the 13-line "no labels found
     in topcell" bail, so the only pad-short and floating-pad data we hold belongs
     to the superseded rzG stream. DRC, antenna and padring all ran on this one and
     all pass; those three are not in question.
  2. Q7 — **CORRECTED 2026-08-25, ask for `PITCH_60_STAGGER`, not P70.** Our
     19 Aug question told imec the parts are 70 um staggered. That was our error.
     Measured from imec's OWN ERC pad table the ring is **67 um** staggered
     (outer row x=56, inner x=158, alternating every 67), which on the deck's own
     switch definitions selects P60 — also the deck's shipped default. Our CB
     opening is 66 x 58: P80 demands 65/75 and fails both; P70 demands 58/66 and
     passes at ZERO margin; P60 demands 53/66 and passes with 5 um. The point is
     not the four results — it is that the P60 rule family has never been run
     against this design. Full text in docs/tapeout/59-imec-round-trip-2026-08-27.md.
  3. Q8 — answered for the 25 Aug run (the Final Report lists exactly those three
     replacement libraries, and the 24 and 25 Aug runs used identical configuration).
     Keep only the forward-looking half: confirm the 1 September run matches.
  4. Return the merged GDS so the wire-bond deck stops being unmeasurable here.
