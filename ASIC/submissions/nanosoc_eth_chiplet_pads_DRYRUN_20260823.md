# Dry-run submission candidate — 23 August 2026

    file  nanosoc_eth_chiplet_pads_DRYRUN_20260823.gds
    md5   17b6c8e678d3624f0a5d8c1759ad3797
    size  304,065,888 bytes
    top   nanosoc_eth_chiplet_pads

Copied from `ASIC/genus-innovus/outputs/nanosoc_eth_chiplet_pads_logo.gds`.
That path is an untagged slot in the retired engine directory and has already
reported two different DRC totals for two different sets of bytes (857 on
18 Aug, 785 on 22 Aug). This copy exists so the number below is attached to
bytes that cannot be overwritten.

## Provenance

    P&R run        gdsrun-20260822-allfix
    synthesis      seeded from gdsrun-20260821-slpads, gate.v md5 a7076071823c7bbe096885d70dcb2e18
    logo           ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds, seam-repaired 22 Aug
                   (0x2BCA and 0x2BD2, y -97632 -> -97625; off-grid vertices 2 -> 0)

## Measured DRC — ASIC/genus-innovus/calibre_runs/drc_allfix_logo2_0822/

    TOTAL DRC RuleChecks Executed:   1926
    TOTAL DRC Results Generated:     785

    691  PO.R.8            black-box artefact; imec's fill clears it to 0
     35  density (*.DN.*)  cleared by dummy fill
     13  D*.R.1 markers    "no dummy layer present"; cleared by dummy fill
     46  power grid        ours. every one a Special Wire of net VDD or VSS.
                           zero signal-route violations.

    G.1:APi = 0            the logo costs nothing

## Measured elsewhere on these same bytes

    Innovus check_drc   47   (23 on M9: 21 bond-pad blockage + 2 routing blockage)
    local ERC            0   6 of 10 checks executed, 884 cells black-boxed
    local BND            1   NOT TRUSTWORTHY: 187 of 205 rulechecks ran over an
                             empty layer (calibre_bnd.log:3038 names PM, CB, CB2,
                             WBDMY). Treat as unmeasured, not as a pass.

## Known and deliberately shipped unfixed

  - 21 bond-pad M9 clearance violations. 1.685 um against a required 2.000.
    Cause: PAD70NU_SL is 173.315 deep against PAD70NU's 171.000. Innovus is the
    only instrument that can see these; Calibre cannot, because the pad masters
    stream as empty shells.
  - The pad ring instantiates PAD70GU_SL x42 and PAD70NU_SL x40. imec's
    CompareCells against tpbn65v.gds lists these only under "Similar cell
    names", never "Identical" — so their merge may not populate them. See the
    broker question.

## Not measured anywhere — do not read the greens as passes

  - all 50 SR.* and 197 CSR.* seal-ring checks (no seal ring in this stream)
  - all 26 LUP.* latch-up checks
  - AN.R.46:M1, the deck's only antenna check
  - AP.EN.2 and PM.EN.1, passivation enclosure — the family the mini@sic manual
    (EPT_AD_001, section 6.5) says can never be violated
  - LOGO.R.4 and LOGO.S.1: the logo is on AP, the LOGO marker layer is empty
