# Dry-run submission candidate — 23 August 2026  (SUPERSEDES the allfix candidate)

    file  nanosoc_eth_chiplet_pads_DRYRUN_20260823_pgfix.gds
    md5   6b334e1e932da7257734f17beb40f46d
    size  303,284,094 bytes
    top   nanosoc_eth_chiplet_pads

Prefer this over `nanosoc_eth_chiplet_pads_DRYRUN_20260823.gds` (the allfix
stream, md5 17b6c8e6...). Same 46 design-owned signoff results, but 23 fewer
bond-pad clearance violations and setup closed. The bond-pad set is exactly what
imec's Padringcheck flagged 82 times, so this stream puts the corrected pad ring
in front of them.

## Provenance

    P&R run     gdsrun-20260823-pgfix
    carries     dd78a50  (core ring -spacing 4um -> 3um; first build of that fix)
    synthesis   seeded from gdsrun-20260821-slpads, netlist sha256 5a191f26...
    route mode  ROUTE_OPT_MODE=setup_then_hold
    logo        ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds, seam-repaired 22 Aug,
                merged at centre (663.875, 1000.0) -- matched to the allfix
                candidate so the two streams differ ONLY by the P&R

## Measured — ASIC/genus-innovus/calibre_runs/drc_pgfix_logo_0823/

DRC summary written 03:26:43 against a GDS last modified 03:19:34, so the
numbers below belong to these exact bytes.

    TOTAL DRC RuleChecks Executed:   1926
    TOTAL DRC Results Generated:     782

    691  PO.R.8            black-box artefact; imec's dummy fill clears it to 0
     32  density (*.DN.*)  cleared by dummy fill
     13  D*.R.1 markers    "no dummy layer present"; cleared by dummy fill
     46  power grid        ours. every one a Special Wire of VDD or VSS.
                           zero signal-route violations.

    Innovus check_drc  24   (was 47 on allfix; MAR 1 MINCUT 1 MINHOLE 2
                             MINSTEP 3 NSMETAL 7 SPACING 10)
    setup FEP           0   (was 50 @ -0.065 on allfix)
    hold  FEP          39   @ -0.018  (allfix: 24 @ -0.053)
    route gate         HARD FAILURES: none

## Known, deliberately shipped unfixed

  - 21 bond-pad M9 clearance violations remain (down from 44). 1.685um against a
    required 2.000. Cause: PAD70NU_SL is 173.315 deep against PAD70NU's 171.000.
    Innovus is the only instrument that sees these; the pad masters stream as
    empty shells so Calibre cannot.
  - PAD70GU_SL x42 / PAD70NU_SL x40. imec's CompareCells lists these only under
    "Similar cell names" against tpbn65v.gds -- see broker question Q5.
  - PG connectivity: 51 opens, 707 dangling wires, 524 missing power vias on
    VDD/VSS. CHRONIC -- present in every run since fp1505, not a regression of
    this one. Does not affect a GDS-based dry run.

## Not measured anywhere — do not read these greens as passes

  - all 50 SR.* and 197 CSR.* seal-ring checks (no seal ring in this stream)
  - all 26 LUP.* latch-up checks
  - AN.R.46:M1, the deck's only antenna check
  - AP.EN.2 and PM.EN.1 passivation enclosure -- EPT_AD_001 section 6.5 says this
    family can never be violated, and our BND run reads 0 only because PM, CB,
    CB2 and WBDMY are EMPTY layers in this stream (calibre_bnd.log:3038).
    187 of 205 BND rulechecks ran over an empty layer.
  - LOGO.R.4 / LOGO.S.1: the logo is on AP, the LOGO marker layer is empty.
