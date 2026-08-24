# Dry-run submission candidate — 23 August 2026   ** USE THIS ONE **

    file  nanosoc_eth_chiplet_pads_DRYRUN_20260823_armA2.gds
    md5   ccc52eb2c7e6d5d34e22fdc015e1f9cb
    size  304,205,478 bytes  (logo-merged; the raw pre-merge stream is 310,760,688)
    top   nanosoc_eth_chiplet_pads

Supersedes both earlier candidates in this directory:

    _DRYRUN_20260823.gds        allfix  md5 17b6c8e6...  785 total, 46 ours, Innovus 47
    _DRYRUN_20260823_pgfix.gds  pgfix   md5 6b334e1e...  782 total, 46 ours, Innovus 24
    _DRYRUN_20260823_armA2.gds  armA2   md5 ccc52eb2...  779 total, 42 ours, Innovus 19  <-

## Provenance

    P&R run     gdsrun-20260823-armA2
    carries     dd78a50   core ring -spacing 4um -> 3um
                fix 1     M9 add_stripes -start_offset 39.5 -> 39.6 (power_plan.tcl:280)
    synthesis   seeded from gdsrun-20260821-slpads, netlist sha256 5a191f26...
    route mode  ROUTE_OPT_MODE=setup_then_hold
    logo        ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds, seam-repaired 22 Aug,
                merged at centre (663.875, 1000.0) -- identical placement to both
                earlier candidates, so the three differ ONLY by the P&R
    stages      place rc=0 42min / cts rc=0 50min / route 64min / HARD FAILURES: none

## Measured — ASIC/genus-innovus/calibre_runs/drc_armA2_logo_0823/

DRC summary written 15:07:14 against a GDS last modified 15:01:26, so these
numbers belong to these exact bytes.

    TOTAL DRC RuleChecks Executed:   1926
    TOTAL DRC Results Generated:     779

    691  PO.R.8            black-box artefact; imec's dummy fill clears it to 0
     33  density (*.DN.*)  cleared by dummy fill
     13  D*.R.1 markers    "no dummy layer present"; cleared by dummy fill
     42  power grid        ours. every one a Special Wire of VDD or VSS.
                           zero signal-route violations.

The 42, by rule:

    VIA3.R.2__VIA3.R.3  18   PG riser inside macro footprints (one defect; fix
                             measured, not in this stream -- see rzG below)
    G.4:M6i              7   min-step, M6
    M4.S.2.1             6   PG rail vs macro pin/blockage
    G.4:M4i              2   min-step, M4
    M5.A.2               2   min-hole, M5
    M8.S.3               2   1.495 vs 1.500 -- SAME-NET (VDD vs VDD); waiver candidate
    M4.S.1               1   0.025 vs 0.100 vs a vendor macro pin
    M5.A.1               1   min area, M5 -- no lever exists
    M9.W.1               1   VIA8 landing-pad tab overhanging a CONTINUOUS 3.6um
                             stripe. Manufacturability, NOT an EM/IR defect.
    VIA3.R.4:M4          1
    VIA4.R.4:M5          1

    Innovus check_drc  19   (allfix 47, pgfix 24)
    setup FEP           0
    hold  FEP          26   @ -0.011
    route gate         HARD FAILURES: none

## Logo — verified on THESE bytes

    Logo structure   present, 28 boundaries, all on layer 74 (AP)
    placed at        SREF (663.875, 1000.0) -- identical to the pgfix and allfix
                     candidates, so the three differ only by the P&R
    Calibre saw it   LAYER APi  Original Geometry Count = 35  (28 logo + 7 other)
    its own rules    G.1:APi 0, AP.W.1.WB 0, AP.W.2.WB 0, AP.S.1.FC 0,
                     AP.S.1.WB 0, AP.S.2.WB 0, AP.S.3.WB 0, AP.EN.1.WB 0

The 22 Aug seam repair holds: the logo contributes zero DRC results.

## Known, deliberately shipped unfixed

  - 21 bond-pad M9 clearance violations (Innovus-only; Calibre cannot see them,
    the pad masters stream as empty shells). 1.685um vs a required 2.000, because
    PAD70NU_SL is 173.315 deep against PAD70NU's 171.000.
  - PAD70GU_SL x42 / PAD70NU_SL x40. imec's CompareCells lists these only under
    "Similar cell names" against tpbn65v.gds -- broker question Q5.
  - PG connectivity: 54 opens, 717 dangling, 496 missing power vias on VDD/VSS.
    CHRONIC since fp1505, not a regression. Does not affect a GDS-based dry run.

## Not measured anywhere — do not read these greens as passes

  - all 50 SR.* and 197 CSR.* seal-ring checks (no seal ring in this stream)
  - all 26 LUP.* latch-up checks
  - AN.R.46:M1, the deck's only antenna check
  - AP.EN.2 / PM.EN.1 passivation enclosure. EPT_AD_001 s6.5 says this family can
    never be violated; our BND reads 0 only because PM, CB, CB2 and WBDMY are
    EMPTY layers here (calibre_bnd.log:3038) -- 187 of 205 rulechecks measured
    nothing.
  - LOGO.R.4 / LOGO.S.1: the logo is on AP, the LOGO marker layer is empty.

## Not in this stream: rzG

A measured fix for the 26-result macro-riser cluster exists and is NOT in these
bytes. On a probe whose control matches this stream exactly on every
real-geometry rule, it takes VIA3.R.2__R.3 18->0, M4.S.2.1 6->0, M5.A.2 2->0,
G.4:M4i 2->0, G.4:M6i 7->4, at a cost of G.4:M5i +2 and M5.W.1 +1.
Projection: 42 -> 14. The confirming run is in flight.
