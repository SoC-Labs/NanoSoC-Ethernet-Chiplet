# As-built padring — rzG, 23 August 2026

Pad locations, orientations, names and types for the current submission
candidate. Generated 2026-08-24.

## What it describes

    stream   ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG.gds
    md5      41a0baee9343e10cb2c5f8b8fe1a4e50
    top      nanosoc_eth_chiplet_pads
    die      0 0 1600 2000 um
    source   ASIC/eth-chiplet/build/gdsrun-20260823-rzG/work/
             nanosoc_eth_chiplet_pads_routed   (Innovus 21.11, saved 19:01)

The DB was saved at 19:01 and the stream written at 19:24 from the same run.

## Verified against the stream

    python3 scripts/xcheck_io_vs_gds.py \
        ASIC/submissions/nanosoc_eth_chiplet_pads_DRYRUN_20260823_rzG.gds \
        as_built_pads.csv

    -> 493/493 exact match on (cell, x, y, orientation)

Run it against `_as_built_pads.csv`, the complete table. The `_pads_only`
files are a strict filter of it, verified as an exact subset.

That is every pad placement in the DB present in the stream and vice versa,
with nothing left over on either side. Re-run it if either artefact changes.

## Files

    ..._as_built_pads_only.csv  START HERE FOR LAYOUT. 168 rows: the real
                                pads only, ring fillers dropped.
    ..._as_built_pads_only.def  the same 168 as DEF. 11KB. Keeps UNITS and
                                DIEAREA, drops ROWS.

    ..._as_built_pads.csv       COMPLETE. 493 rows, every field, both origins.
    ..._as_built_pads.json      same data, machine-readable, plus the die box.
    ..._as_built_padring.def    the whole ring incl. fillers, + the 21 macros.
    ..._as_built.io             Innovus write_io_file -locations.
    ..._as_built_order.io       Innovus write_io_file, ring order, cell names.

The `_pads_only` pair is the full table with the 325 `PFILLER*` rows removed --
82 IO cells, 82 bond pads, 4 corners. Fillers are ring spacers: no signal, no
bond, nothing for a package or die drawing to do with them, and two thirds of
the rows. The full table keeps them because a padring audit needs to see the
ring is closed. `_pads_only.csv` is byte-for-byte the full table minus
`kind=filler`, so it inherits the GDS verification below.

DEF is the format to hand to anything that is not Innovus. COMPONENTS carries
instance name, cell, FIXED, absolute origin and orientation:

    - uPAD_CORNER_TL PCORNER_G + SOURCE DIST + FIXED ( 0 3730000 ) E

Watch two things. DEF units here are `UNITS DISTANCE MICRONS 2000`, so 2000
DBU per micron -- 3730000 is 1865 um, NOT 3730. And DEF orientation is
N/W/S/E for 0/90/180/270, so the CSV's `r90` is DEF's `W`. The 514 COMPONENTS
are the 493 padring instances plus the 21 macros, which a floorplan reader
generally wants.

## Contents

    kind      n    what
    io       82    the TSMC IO driver / supply cells (PDDW*, PDUW*, PVDD*, PVSS*)
    bondpad  82    the staggered bond pads (PAD70GU_SL / PAD70NU_SL)
    corner    4    PCORNER_G
    filler  325    PFILLER*_G

`cell` is the pad TYPE. For the IO cells that is the driver (e.g.
PDDW16DGZ_G); the bond pad you actually wire to is the matching `BuPAD_*`
row. Bonding is STAGGERED: PAD70NU_SL is the deep inner pad (173.315 um),
PAD70GU_SL the shallow outer one (86.815), alternating along each side.

## Two origins, and why

Innovus `.location` and the GDS SREF point are different references, and on a
rotated pad they differ by a full cell height. Both are in the CSV:

    gds_origin_x/y     cell origin AFTER transform -- matches the stream
    inn_location_x/y   lower-left of the placed bbox -- what Innovus reports
    bbox_*             unambiguous, use this if in doubt
    center_x/y         bbox centre, convenient for a bond diagram

## Where these come from now

Generated in-flow by `ASIC/eth-chiplet/hooks/post_route.tcl`, which the toolkit
fires at `flow/innovus/4_route.tcl:1735` -- immediately after the `write_stream`
at :1637. Same session, same in-memory design, so every future run drops these
files into `build/<RUN_TAG>/outputs/` beside its GDS at no extra licence cost.
Every write is wrapped in `try_step`, so a failure warns and never kills a route.

This particular bundle predates the hook and was recovered from the archived
database with `ASIC/genus-innovus/scripts/dump_io_file.tcl`, which is a thin
wrapper that sources the same hook -- one implementation, not two.

## Caveats

  - `orient` is Innovus notation (r0/r90/r180/r270). All 493 are unmirrored.
  - The two `.io` files carry the IO cells, corners and fillers but NOT the 82
    bond pads -- `write_io_file` only knows about IO-class cells, and the bond
    pads are CLASS BLOCK. Use the CSV for a complete ring.
  - GDSII has no instance names. Every name here comes from the DB; it cannot
    be recovered from the stream alone.
  - `ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io` is the INPUT plan
    (`make check` reports it as IO_FILE) and its own header says its offsets
    are evenly-spaced placeholders. Do not draw a layout from it.
  - The .io format cannot express an absolute coordinate at all. `write_io_file`
    has no such flag, and a version-3 I/O file carries a 1-D `offset=` along a
    side. Since this die's origin is (0,0) those offsets happen to convert
    directly, but use the CSV or the DEF and avoid the question.
