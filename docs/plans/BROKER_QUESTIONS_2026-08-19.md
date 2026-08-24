# Questions for the broker / foundry — eth chiplet, 2026-08-19

DRAFT FOR DAVID'S REVIEW. Nothing here has been sent.

Four questions. Each states what we measured, what we are asking, and what we
would do with each possible answer. Where a number is measured on someone else's
deck rather than ours, that is said in the same paragraph as the number — please
keep it attached if these are forwarded or split up.

---

## Q1. Is the pad-ring bus permitted to be discontinuous through the die corners?

**This is the highest-leverage question we have.** Its answer governs a large
population of DRC results, not a handful.

**What we would do.** The four `PCORNER_G` corner cells (135 x 135 um, LEF
obstruction solid on M1..M7) sit inside the corner keep-out region. Deleting them
and filling with `PFILLER*_G` is a `.io` edit plus a place-and-route pass — the
corner cells are not in the gate netlist, so no resynthesis is needed. We have
not done it, and will not, without an electrical ruling.

**Why we are asking rather than deciding.** Removing them breaks pad-ring bus
continuity at all four corners, leaving four independent side-buses. Our reading
is that this conflicts with ESD guidance for the ring, but the ruling is yours
to give.

**The measurement.** In our own Calibre run on the current stream, `CSR.R.1`
reports **56 results**, all attributable to those four cells. Separately, we
parsed all ~1670 raw RVE polygon coordinates in the IMEC full-library-merge
archives and found that **100% of the unattributed `CSR.R.2` / `EN.8`
violations lie 14-70 um from a die corner**, in the same footprint — and a
further 59 of 157 newly-appearing rule categories share the same by-cell
signature.

**The caveat, which must travel with those numbers.** The ~1670 population was
measured in IMEC's archive against their full-merge deck, NOT on our stream. The
same rule name already disagrees between the two decks (`CSR.R.1` is 56 on ours,
28 on theirs). So "the ruling governs roughly thirty times more than the 56" is
an inference about leverage, not a measurement on our lineage. We cannot close
that gap locally: our current lineage has never had a full-library-merge DRC run,
and we have no Back-End PDK on site to do one.

**What each answer changes.**
- *Discontinuity is acceptable (perhaps with a stated mitigation)* — we remove the
  corner cells in the next place-and-route pass.
- *Discontinuity is not acceptable* — we stop pursuing it, and the corner-resident
  population becomes a waiver conversation instead. Please tell us if you would
  prefer that framing.
- *It depends on the ring's ESD strategy* — please tell us what to measure.

---

## Q2. How many `PVDD2POC_G` instances should this ring carry?

We currently instantiate **four — one per side**. Our reading of the cell's role
suggests **one per ring** may be correct. We have no datasheet for it on site and
cannot resolve this from the collateral we hold.

**What each answer changes.** If one is correct, three come out and the ring is
re-spaced — a `.io` edit, cheap, but it must happen before the run we are about
to commit to rather than after. If four is correct we change nothing and would
like that on the record.

---

## Q3. Can we have an untruncated by-cell DRC report?

The by-cell report we hold **truncates exactly where the residual population
begins**. Our best-evidenced candidate for the un-attributed cell is
`SBC331_SUB_CORNER`, but the evidence stops at the truncation and we are not
willing to name it as established on that basis.

**What we would do with it.** Confirm or refute that attribution, which in turn
tells us whether Q1's ruling covers the whole corner-resident population or only
part of it. This is the cheapest of the four to answer and it improves the
quality of the Q1 decision.

---

## Q4. What is the minimum same-row bond pad pitch your assembly flow supports?

A packaging question, and the only one here whose answer changes a die frame, so
we would rather ask now than discover it late.

**The question, in the form that needs no context from us.** State the minimum
same-row bond pad pitch you can bond, and we will do the arithmetic ourselves.
That answer stays correct however our floorplan moves, which is why we ask it
this way round.

**The specific case, if it is easier to answer.** Is **84 um** bondable? A 42 um
D2D driver pitch yields an 84 um same-row pad pitch, down from 130 um. The
geometry is legal by our own checks — the ring fits, the inventory is unchanged
at 21/27/21/27 with 96 pads and 4 corners, and the trailing gaps close on the
filler set. Whether it is *bondable* is the part we cannot establish here.

**What the answer changes for us.** A pitch we cannot meet forces a die frame to
transpose, moving every macro coordinate — a change we would want to start
immediately rather than late. We are not asking you to weigh that; the number is
the whole answer.

---

## Not asked here, recorded so it is not raised twice

- **Metal fill.** We already declare `METAL_FILL_OWNER=foundry` and insert no
  dummy metal; the ~38,000 density windows in our route report are a measurement
  of a deliberately unfilled design. We are not asking you to confirm the rule
  set — we are asking, in the submission correspondence rather than here, for
  written confirmation that the fill is yours to insert.
- **Antenna and LVS signoff.** Declared gaps on our side with their own records.
  No question for you at this time.

---

# Added 2026-08-23, after measuring imec's 21 Aug archive

Everything below is measured against
`ASIC/imec_results/Archive_nanosoc_eth_chiplet_pads_SUBMIT_allpads_logo_merged_dummyWithSealRing_21Aug26_14u50/`
and against our own current stream
(`nanosoc_eth_chiplet_pads_DRYRUN_20260823.gds`, md5 `17b6c8e678d3624f0a5d8c1759ad3797`).

## Q5. Can your merge populate the `PAD70*_SL` bond-pad masters?  [HIGHEST PRIORITY]

Your 21 Aug `Padringcheck` reported **82 errors**, one per bond pad:

    Error-padringcheck, Bond cell: PAD70NU is not correctly abutting IO cell:
      PDDW16DGZ_G in X
    Info-padringcheck, Bondpad origin is on: (1047.5, 20.0), IO cell is on: (1050.0, 20.0)

Offsets across all 82: 26 at (0,-2.5), 22 at (0,+2.5), 17 at (+2.5,0), 17 at (-2.5,0).

Root cause, from the bond-pad library LEF for this metal stack (full path
withheld here — it encodes the deck revision this site licensed and this
repository is public; it will be quoted in the email itself):

    PAD70GU     SIZE 30.000 BY  86.685      PAD70GU_SL   SIZE 25.000 BY  86.815
    PAD70NU     SIZE 30.000 BY 171.000      PAD70NU_SL   SIZE 25.000 BY 173.315

The IO cells are 25.000 wide. The 30.000 pads were centred, giving exactly half
the 5.000 mismatch. We have therefore switched to the `_SL` variants, which are
25.000 and origin-align.

**The problem.** Your own `CompareCells` against `tpbn65v.gds` reports:

    Identical cell names:   PAD70GU   PAD70NU
    *** WARNING *** Similar cell names:
      PAD70GU ~~ PAD70GU_SL
      PAD70NU ~~ PAD70NU_SL

So your `tpbn65v.gds` appears to carry the bare names but not the `_SL` masters.
Our new stream instantiates **only** `_SL` (42 + 40). Pads stream from our side
as empty shells by design — our `write_stream -merge` list is memories and ROMs
only, because the IO, pad and standard-cell back-ends are yours to merge.

**Please confirm one of:**
  (a) your `tpbn65v.gds` does contain `PAD70GU_SL`/`PAD70NU_SL` and the merge
      will populate them; or
  (b) it does not, in which case tell us which pad cell you *can* merge and we
      will place that one instead.

If neither, the 82 bond pads ship hollow and every pad-dependent check — BND
`PM.*`/`CB.*`, `AP.EN.2`, `PM.EN.1`, `Padringcheck`, LVS — passes without
measuring anything.

**Added 2026-08-24 — measured, and it makes the failure mode cleaner to detect.**

A per-structure geometry census of the stream you last checked
(`nanosoc_eth_chiplet_pads_logo_full_L300.gds`, md5 `7f621496…`) against our
current one:

| structure | your 10 Aug copy | our current stream |
|---|---|---|
| `PAD70GU` / `PAD70NU` | 13 shapes (M8 5, M9 5, AP 3) | renamed, absent |
| `PAD70GU_SL` / `PAD70NU_SL` | — | **empty shell** |
| `PCORNER_G`, `PFILLER*_G` | 7 shapes, one per M1–M7 | **empty shell** |
| `NR2D1`, `INVD1`, `DFCNQD1` | M1 only (LEF pin) | M1 only (LEF pin) |

Two consequences worth stating plainly.

First, **the shapes that vanished were never pad layout.** They were LEF
obstruction, which our old stream-out map emitted onto mask layers as though it
were manufactured metal — 68.8% of all metal in that file. We corrected the map
on 17 August. On the bond pads specifically it was emitting a **solid AP plate
with no CB opening**, which is worse than an empty cell, so their removal is
deliberate and is not a regression.

Second, **your merge does not depend on our cells having contents.** Our
standard-cell shells carried LEF-pin geometry rather than being empty, and your
18 Aug `tcbn65lp` merge populated them regardless — device census 6,420,952 →
8,599,725, `PO.R.8` 691 → 0. Substitution is keyed on the structure name. So an
empty `PAD70NU_SL` is not itself an obstacle; the only question is whether the
name exists in your `tpbn65v.gds`.

**An acceptance test we can both apply.** When the next archive returns, we will
census the merged GDS for geometry inside `PAD70NU_SL` and `PAD70GU_SL`:
non-zero means the merge landed, empty means every pad check in that run
measured nothing. We are happy to share the script — it is a plain GDSII record
filter in the Python standard library, no KLayout or Calibre licence needed.

## Q6. Does your BND run see passivation geometry that ours structurally cannot?

Our own BND run on the current stream returns 1 result from 205 rulechecks, and
our Calibre log states why:

    NOTE: The following required simple layers are EMPTY:  5  7  8 ...

Those are PM, CB, CB2 and WBDMY. **187 of our 205 executed rulechecks ran over an
empty layer.** We are treating our BND result as unmeasured, not as a pass.

Of your 1054 BND results we attribute 1034 (`PM.W.1` 903, `AP.S.4` 131) to your
seal-ring merge — all inside the 30um die-edge band, 26 of them inside TSMC's own
`CORNER_B`. 16 (`AP.W.1`, `AP.S.1`) are ours and are the chip logo; those are
fixed in the current stream (12->0 and 4->0, reproduced locally).

**Question:** after your merge, do `AP.EN.2` and `PM.EN.1` evaluate against real
geometry? Section 6.5 of EPT_AD_001 says passivation-opening enclosure by top
routing metal "can never be violated", and it is the one family we have no way
to measure before you run it.

## Q7. You ran `#DEFINE PITCH_80_STAGGER` on a 70um pad ring

Your 21 Aug BND run declares `'#DEFINE PITCH_80_STAGGER'`, and the only two
non-seal-ring, non-logo results are `CB.W.1:P80_ST` and `CB.W.2:P80_ST`, both
inside the vendor cells `PAD70GU` and `PAD70NU`.

Our pads are 70um-pitch, and our deck sets `PITCH_70_STAGGER`. We believe those
4 results are a switch artefact rather than a defect. Please confirm the pitch
option you intend to run, and re-run with `PITCH_70_STAGGER` if you agree.

## Q8. Please confirm the exact library set the FINAL run will merge  [HIGHEST PRIORITY]

**736 of the 750 results on our current stream clear only because of your merge**,
so the merge list is the single largest determinant of the result we get back —
larger than anything remaining in our own layout. It has differed on every run
you have done for us:

| your run | libraries merged | `PO.R.8` | density rules failing |
|---|---|---|---|
| 17 Aug | none | 691 | 22 |
| 18 Aug | `tcbn65lp` + `tphn65lpgv2od3_sl` | 0 | 7 |
| 21 Aug | + `tpbn65v` | 0 | **0** |

We are not asking you to change anything — the 21 Aug configuration is the one
that works. We are asking for it **in writing for the final run**, because we
cannot tell from a returned archive whether a library was merged until we see
its effects, and by then the run is spent.

Specifically, please confirm the final acceptance run merges all three:

    tcbn65lp             standard cells
    tphn65lpgv2od3_sl    IO drivers
    tpbn65v              bond pads      <- the one dropped from the 18 Aug run

Note the third is also what Q5 turns on. If `tpbn65v` is merged but lacks the
`_SL` masters, the merge runs and the pads still come back hollow, so a "yes" to
this question does not by itself answer Q5.

## Withdrawn — do not raise

- **`PO.R.8` (691 results).** We previously believed these needed a
  standard-cell layout merge on your side and would otherwise persist. That is
  wrong. Your own three runs settle it: 17 Aug (unfilled) had 20 `PO.R.8`
  rulechecks firing; 18 and 21 Aug (both `_dummy_merged_`) have **zero**, along
  with zero density. Your dummy fill clears them. No question needed.
