# rc4 — the candidate where setup and hold both close, 29 August 2026

    file    ASIC/eth-chiplet/build/rc4-20260829/outputs/nanosoc_eth_chiplet_pads_rc4_logo.gds
    md5     6b0833c4216bdb683ed2427cd0deba75
    sha256  73fad49a087d390741bbb62f303fcca504adbc2c4b564e451364fd4d9f9cfd19
    size    303,996,534 bytes
    top     nanosoc_eth_chiplet_pads

No copy is kept in this directory. The `.gds` files here are untracked, the
bytes above are not overwritten by any later run, and the artifact store is the
place a stream is retrievable from by md5. Earlier notes in this directory kept
a copy because their source WAS an overwritable slot in the retired engine
directory; this one is not.

## Provenance

    descends from  rc3fix-20260828 (md5 70b3fb07430b083dc7380f1c95435ade)
    ECO tree       ASIC/eth-chiplet/build/setupclose-20260829
    streamed from  ASIC/eth-chiplet/build/rc4-20260829/db_rc4
    timed          ASIC/eth-chiplet/build/setupclose-20260829/sta_rc3setup
    evidence       ASIC/eth-chiplet/evidence/rc4-20260829.json

THE TIMED DATABASE AND THE STREAMED DATABASE ARE THE SAME BYTES. They are two
different paths, so it was checked and not assumed: `diff -r` over the two
trees reports no difference, 53 files each.

The delta from rc3fix is three cell resizes, applied by ECO and read back from
the database AFTER place_eco, route_eco, re-fill and fix_drc
(`final.resizes_verified = 3/3`):

    u_..._u_soc_u_tidelink/g57706    FA1D0    -> FA1D1
    u_..._u_soc_u_soc/g127940        ND2D3    -> CKND2D3
    u_..._u_soc_u_tidelink/g33463    OAI21D1  -> OAI21D2

## What this candidate buys

rc3fix left one setup endpoint failing at the signoff corner by 1 ps. rc4
closes it without moving hold.

    Tempus, SS/1.08V/125C, RC extracted at 125C, CPPR on, OCV 0.95/1.05/0.97/1.03

    setup   +0.015   TNS 0.000   FEP 0        (rc3fix: -0.001, FEP 1)
    hold    +0.003   TNS 0.000   FEP 0

    hold per view   default_analysis_view_hold   +0.003
                    av_ltfix_libset_hold         +0.003
                    av_ml_libset_hold            +0.006

All three hold views active and all four RC corners extracted at their own
temperature. `clock_count` 104 — one object per SDC clock per active view.

## Measured DRC — ASIC/genus-innovus/calibre_runs/drc_rc4_logo_0829/

    TOTAL DRC RuleChecks Executed:   1926
    TOTAL DRC Results Generated:     737 (4328)
    four tiers                       737 / 46 / 13 / 0
    non-zero rulechecks              32,  max count 691,  check limit 100000

IDENTICAL TO rc3fix ON EVERY RULECHECK. The two summaries were compared line by
line: zero of the rulecheck lines differ, same 737, same tiers.

The streams are NOT the same file, and the deck says so: flat original-layer
geometries read 178,282,662 here against 178,282,660 for rc3fix. The ECO is
really in these bytes; it just does not move a single rule outcome.

## Measured elsewhere on these same bytes

    foundry antenna    0 on every one of 714 rulechecks, 7 population controls
                       all non-empty. SCOPE: the stream carries LEF abstracts
                       for standard cells, IO and bond pads, so the deck's
                       GATE = OD AND POLY denominator exists only inside the
                       merged memory macros. Not the foundry's population.
    LVS                0 `missing connection` discrepancies below the top level.
                       The overall LVS VERDICT remains INCORRECT for the reasons
                       in known_bad[lvs-verdict-incorrect]; it is not graded.
    connectivity       -type regular: "Found no problems or warnings."
    Innovus check_drc  0  (rc3fix baseline was 3 MINCUT, all LEF-abstract
                       artefacts against the rf SRAM; a zero here and a zero in
                       Calibre are consistent, neither validates the other)

## Known and deliberately shipped unfixed

  - PG connectivity: 51 special-wire opens and 727 dangling on the all-nets
    check, unchanged from rc3fix and declared as that candidate's baseline.
    These are the standing PG known-bad, not signal nets.
  - 57,955 timing checks UNTESTED, and `sta_gate.py` FAILS on them. The number
    is IDENTICAL on rc2 and rc3fix, so it is not an rc4 regression. Violated is
    zero in every category, and the same counts appear in both directions
    (Setup 2,377 / Hold 2,377), which is the signature of endpoints excluded
    from timing altogether rather than an analysis that ran one way only.
    Nobody has enumerated them. "Setup and hold close" means "over the 96% of
    checks that were evaluated".
  - Voltus rail was NOT re-run on rc4. The last measurement is on rc3fix, and
    two of the three resizes step drive strength up, so the carried EM and IR
    numbers are optimistic by an unmeasured amount.
  - The OCV derates are flat and uncharacterised. No AOCV/SOCV/LVF ships with
    this tech pack. Both checks are entirely CPPR-financed: with CPPR off this
    design reads setup -0.154 and hold -0.605.

## Not measured here

ERC, pad shorts, post-merge PO.R.8, seal-ring/BND and metal density are all
foundry-side on the merged stream and are asked for in
`docs/tapeout/65-imec-round-trip-2026-08-29.md`.
