# Stated BEFORE the screening runs (baseline 'base' already measured)

MEASURED BASELINE (probe, today's power_plan, pinned snapshot 7dbfa1b1):
  62 localised open boxes; 34 rail-class; 37 stranding.
  Per site rail-class: A=19  B=10  C=3  D=1  D'=1
  == identical, box for box, to ROUTED build/fp1505 (62/34/37, same per-site).

MEASURED GEOMETRY (core_bbox {205 205 1395 1795}):
  M8 is the ONLY perpendicular (vertical) stripe layer. Sets at
  x = 205 + 39.5 + 60k = 244.5 + 60k, each set 8.4 wide:
  VDD [244.5+60k, 248.1+60k], VSS [249.3+60k, 252.9+60k].
  Overlap with the five islands:
    A  [1034.2,1055.6] : NONE
    B  [1051.8,1055.0] : NONE
    C  [1043.2,1055.6] : NONE
    D' [879.8, 895.2]  : NONE
    D  [869.2, 907.6]  : k=11 VDD only, x 904.5-907.6. VSS (909.3-912.9) misses.
  Independent confirmation of the grid: doc 32's four rail-shorts span
  x = 844.500 -> 912.900, which is exactly M8 set k=10 start (844.5) to
  M8 set k=11 end (912.9).

## CANDIDATE 1  -core_pin_target {stripe ring block_ring}
PREDICT: NO material improvement. Rail-class stays ~34; A=19 B=10 C=3 D=1 D'=1
  substantially unchanged (allow +/-2 per site).
WHY: the M5 ladder is HORIZONTAL = PARALLEL to the followpin rails, so a rail
  extending along its row never crosses it. The only perpendicular stripes are
  M8, and none overlaps A, B, C or D'. At D the only overlapping stripe is the
  VDD half, and VDD at D is already connected - D's one open is VSS.
  There is therefore no stripe to target at 4 of 5 sites, and at the 5th the
  overlapping stripe belongs to the net that is not broken.
RISK: may get WORSE - the list form REPLACES the first_after_row_end enum, so
  the row-end extension that currently feeds rails elsewhere may be dropped.
WRONG IF: (a) the list form still extends past the row end and the failing
  risers succeed against a different target class; (b) route_special will drop
  a via where a parallel M5 stripe is y-coincident with a rail; (c) my M8 grid
  is wrong.

## CANDIDATE 4  EVP_M5_ABS_START=213.0  (= core_lly 205 + the default offset 8)
PREDICT (semantics, THE CRUX): -start is DIE-ABSOLUTE. One ladder at
  y = 213 + 15k over the whole core. Reason: the reference's "start coordinate
  for the region" is qualified by -area, whose documented default is "stripes
  are created for the entire design area"; with no -area the region IS the die.
PREDICT (defect): does NOT clear the five sites. Rail-class total stays in the
  same ballpark (allow 25-45) with the box Y-COORDINATES MOVED. Changing the
  ladder phase only changes which PARALLEL rails sit under a stripe; it creates
  no perpendicular feed. This is the redistribute-never-reduce behaviour already
  measured three times (doc 42 s4: m5off5=36, m5off6=42 boxes vs 34 baseline).
WRONG IF: per-region re-anchoring is itself what starves the islands, in which
  case one global ladder collapses the count toward 0.
FALSIFIES THE SEMANTICS HALF: if -start is region-relative, regions whose
  y-range excludes 213 get no ladder or a clamped one, so opens should EXPLODE
  well above 64 and/or check_drc should jump sharply.

## CANDIDATE 5 (MINE) - targeted perpendicular feed, screened as two variants
Two extra M8 vertical sets at x=1049.0 (covers island rails A/B/C, which span
x 1030.7-1059.1) and x=880.0 (covers D 865.7-911.1 and D' 876.3-898.7), placed
with the now-MEASURED die-absolute -start.
  'feed'     = the two sets + candidate 1's list-form -core_pin_target
  'feedonly' = the two sets, keeping first_after_row_end

PREDICT 'feed': all five sites collapse. A, B, C -> 0-2 rail-class boxes each;
  D and D' -> 0. Total localised boxes < 62. NO new off-site rail cluster of the
  kind EVP_M5_ABS_START produced, because this change is additive and local and
  re-phases nothing. SHORT records stay 0.
PREDICT 'feedonly': little or no improvement, because first_after_row_end does
  not treat a stripe crossing the MIDDLE of a row as a target - it only looks
  past the row end. This isolates whether candidate 1 is the necessary ENABLER
  of the feed rather than a fix in its own right.
WRONG IF: the M1->M8 via stack cannot be built inside a 3.2um island (site B),
  or the added M8 collides with macro top metal and is dropped.
IF feedonly ALSO clears the sites, then route_special stitches crossing stripes
  without the list form, and candidate 1's null result needs another explanation.
