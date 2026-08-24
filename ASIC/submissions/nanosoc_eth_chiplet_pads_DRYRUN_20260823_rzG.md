# Dry-run submission candidate — 23 August 2026   ** USE THIS ONE **

    file  nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG.gds
    md5   41a0baee9343e10cb2c5f8b8fe1a4e50
    top   nanosoc_eth_chiplet_pads

Supersedes all three earlier candidates here. Logo at (663.875, 1000.0) in every
one of them, so the four differ ONLY by the P&R.

    _DRYRUN_20260823.gds        allfix  17b6c8e6  785 total, 46 ours, check_drc 47
    _DRYRUN_20260823_pgfix.gds  pgfix   6b334e1e  782 total, 46 ours, check_drc 24
    _DRYRUN_20260823_armA2.gds  armA2   ccc52eb2  779 total, 42 ours, check_drc 19
    _DRYRUN_20260823_rzG.gds    rzG     41a0baee  750 total, 14 ours, check_drc 12  <-

## Provenance

    P&R run     gdsrun-20260823-rzG
    carries     dd78a50   core ring -spacing 4um -> 3um
                fix 1     M9 add_stripes -start_offset 39.5 -> 39.6
                rzG       M4 -pg_nets keep-out over 20 of 21 macro footprints,
                          in force ONLY across the block-pin route_special and
                          deleted immediately after (20 created / 20 deleted,
                          guard silent). way1_cache_ram_data_ram_0_word_0_i is
                          EXEMPT: it owns none of the 26 and the first M9 stripe
                          runs along its top edge.
    synthesis   seeded from gdsrun-20260821-slpads, netlist sha256 5a191f26...
    route mode  ROUTE_OPT_MODE=setup_then_hold
    stages      place 43m48 rc=0 / cts 53m33 rc=0 / route 67m / HARD FAILURES none

## Measured — ASIC/genus-innovus/calibre_runs/drc_rzG_logo_0823/

DRC summary 19:29:39 against a GDS modified 19:24:07 — these numbers are these bytes.

    TOTAL DRC RuleChecks Executed:   1926
    TOTAL DRC Results Generated:     750

    691  PO.R.8            cleared by imec merging tcbn65lp.gds (NOT by fill)
     32  density (*.DN.*)  cleared by imec's fill + library merge
     13  D*.R.1 markers    cleared the same way
     14  ours

The 14, with what each needs:

    G.4:M6i         4   min-step, M6. residue of the keep-out. fixable, low value.
    M8.S.3          2   1.495 vs 1.500, SAME-NET (VDD vs VDD). WAIVER CANDIDATE:
                        every genuine two-party marker names both parties.
    G.4:M5i         2   min-step, M5. introduced by the keep-out.
    M4.S.1          1   0.025 vs 0.100 against a vendor macro pin. two-party.
    M5.A.1          1   min area. NO LEVER EXISTS - fix_via does only
                        short/mincut/minstep and accuracy_effort is already high.
    M5.W.1          1   introduced by the keep-out.
    M9.W.1          1   VIA8 landing-pad tab overhanging a CONTINUOUS 3.6um
                        stripe. Manufacturability, NOT an EM/IR defect.
    VIA3.R.4:M4     1
    VIA4.R.4:M5     1

    Innovus check_drc  12   (MAR 1 MINCUT 3 MINSTEP 3 MINWIDTH 2 SPACING 3)
    setup FEP           0
    hold  FEP          13   @ -0.010
    missing power vias 372   (was 524 on allfix)

## Known, deliberately shipped unfixed

  - bond-pad M9 clearance: 1.685um vs a required 2.000, because PAD70NU_SL is
    173.315 deep against PAD70NU's 171.000. Innovus-only; the pad masters stream
    as empty shells so Calibre cannot see them.
  - PG connectivity 53 opens / 711 dangling / 372 missing vias. CHRONIC since
    fp1505. Note LVS has NEVER RUN on this design, so this is unvalidated either way.

## THE DEPENDENCY THAT MATTERS MOST

736 of these 750 clear only because imec merges replacement libraries. Measured
from their own three reports:

    17 Aug   no libraries merged        PO.R.8 691, 22 density rules fail
    18 Aug   tcbn65lp + tphn65lpgv2od3  PO.R.8   0,  7 density rules fail
    21 Aug   + tpbn65v                  PO.R.8   0,  0 density rules fail

This is their per-run operator configuration and it has differed EVERY RUN.
Get written confirmation that the final run merges all three.

## Not measured anywhere — do not read these greens as passes

  - all 50 SR.* and 197 CSR.* seal-ring checks
  - all 26 LUP.* latch-up checks
  - AN.R.46:M1, the deck's only antenna check
  - AP.EN.2 / PM.EN.1 passivation enclosure (EPT_AD_001 s6.5: can never be
    violated). Our BND reads 0 because PM/CB/CB2/WBDMY are EMPTY layers here --
    187 of 205 rulechecks measured nothing.
  - imec's own ERC has never executed: three runs, three aborts on
    "No labels found in topcell. At least power/ground labels are required."
