# 59 — The four M5 VDD–VSS shorts: where they are, and what moves them

**Status: the four shorts are CLEARED by `rf_32k` at y=1505.60, committed in
`floorplan.tcl`. The general defect behind them is OPEN and unguarded.**

Rail-to-rail means `Special Wire of Net VSS & Special Wire of Net VDD` — power
shorted to ground. Not a yield risk; a dead-chip risk.

This document has been wrong twice, in opposite directions, and both corrections
are kept below because the wrong versions were each circulated.

---

## 1. The measurement

Rail-to-rail records by build:

| build | M5 `-start_offset` | `rf_32k` y | rail-short coordinates (x, y) |
|---|---|---|---|
| `knobs-live` | 8 | 1503.40 | **none** |
| `macro-move` | 8 | 1506.12 | 844.500 @ 1546.600 / 1561.600 / 1576.600 / 1591.600 |
| `full-20260814` | 8 | 1506.12 | 844.500 @ 1546.600 / 1561.600 / 1576.600 / 1591.600 |
| `m5off6` | 6 | 1506.12 | 844.500 @ 1544.600 / 1559.600 / 1574.600 / 1589.600 |
| `m5off5` | 5 | 1506.12 | 844.500 @ 1543.600 / 1558.600 / 1573.600 / 1588.600 |

All four sit at **x = 844.500**, spanning to 912.900, 0.020 µm tall.

## 2. WHERE they are — the bootrom

The only macro in that x-span at that height is the **network boot ROM**,
`*u_network_core*u_region_bootrom_0*rom_via*` at **(883.535, 1538.600)**
(`floorplan.tcl:303`).

```
    short y  =  1538.600  +  M5_start_offset  +  k*15        k = 0,1,2,3
```

Confirmed at three offsets — 8→1546.600, 6→1544.600, 5→1543.600, each measured
where predicted. **The offset does not cancel; it translates the shorts by its
own value and never removes them.**

`rf_32k` is at x = 290.8, some 550 µm away, and is not where the shorts are.

## 3. WHETHER they exist — `rf_32k`

Measured on the PG probe, one variable isolated. Same day, same tree, same
netlist; a private copy of `floorplan.tcl` differing only in this line, `diff`
zero lines beyond it:

| `rf_32k` y | D mod P | `check_drc` | rail shorts | marker height |
|---|---|---|---|---|
| 1506.12 | 2.480 | 71 | **4** | 0.020 µm |
| 1506.10 | 2.500 | 71 | **4** | 0.000 µm |
| **1505.60** | **3.000** | **65** | **0** | — |

**Both sections are true.** The bootrom's ladder says *where* a short lands;
`rf_32k`'s y says *whether* one exists at all. The mechanism that connects two
macros 550 µm apart is in §4.

**Do not take the obvious repair.** Backing 1506.12 off by the 20 nm the
arithmetic suggests lands exactly on the window edge, where the two stripe edges
are *coincident* — still a short, reported with a **zero-height marker** that
reads like a rounding artefact. The window is closed, not open. 1505.60 sits a
clear half-micron clear of it and still closes the orphan corridor the move was
made for: the halo top lands 0.52 µm below the core top, and a standard-cell row
is 1.8 µm, so no row fits.

## 4. The mechanism

`split_row -selected` derives row regions from **all** placed macros
collectively, and `add_stripes -start_offset` re-anchors the ladder **per
region**, on each region's own bottom edge. So a boundary shift caused by one
macro re-phases the strap ladder in another. With region A below region B and
D = By − Ay, A's VSS stripe overlaps B's VDD stripe iff `D mod P` falls in
(0.5, 2.5), and the offset F cancels because it is on both sides.

```
  1538.60 − 1503.40 = 35.20,  mod 15 = 5.20  ->  clear by 2.70   ZERO shorts
  1538.60 − 1506.12 = 32.48,  mod 15 = 2.48  ->  overlap 0.020   FOUR shorts
  1538.60 − 1505.60 = 33.00,  mod 15 = 3.00  ->  clear by 0.50   ZERO shorts
```

The 2026-08-13 move needed +2.72 and had +2.70 of clearance. **It overshot by 20
nanometres, and that is the entire defect.**

*Unverified premise:* this treats the two as adjacent regions, but they are 550
µm apart in x. The form predicts correctly at every offset and placement tested
and the controlled experiment confirms its verdict — but the region adjacency
itself is assumed, not measured. If you need it, dump the regions after
`split_row` rather than trusting the arithmetic.

## 5. Two corrections, both circulated before they were caught

**(a) The first version was fitted, not derived.** It took 1538.600 as "the
fixed structure above" without asking what structure it was, and differenced it
against `rf_32k`. Session 94 challenged the anchor and was right: 1538.600 is
the *bootrom's* y. It fitted three databases because all three shared a
floorplan and an offset, and predicted nothing it had not already seen.

**(b) The correction was then over-applied.** This document went on to state that
`rf_32k` at 1505.60 "does not fix this" and "must not be reported as one". That
is refuted by §3, measured after it was written. Being wrong about *where* the
shorts are did not make the fix wrong — I retracted the conclusion along with
the reasoning, which threw away a correct result.

**How the original bug shipped:** 1506.12 was reviewed on the violation COUNT
(71 → 69, timing closed, IMPSP-2021 zero) and scored better on the number being
watched while introducing four power-to-ground shorts. Counting violations is
not the same as reading their kinds.

## 6. Open defect — unchanged, and larger than the fix

> **Any macro placement change can introduce a rail-to-rail short in an
> unrelated region, and nothing in either flow checks for it.**

Four more macro pairs sit within half a micron of the same phase window. The
structural cure is one M5 ladder over the whole core instead of per-region
re-anchoring, which removes the coupling entirely; it is DRC-population work and
is not gating `gate1`.

The macro-PG gate that landed in the toolkit on 2026-08-17 has a near-miss arm
measuring the smallest different-net gap inside a macro footprint. That would
catch this class where it lands inside a macro — untested on this design, and
expected to turn `place` red.

**Until that gate is real, treat `grep -c 'Special Wire of Net VSS & Special
Wire of Net VDD'` on the routed DRC report as a mandatory read after any
floorplan change.** It is the only thing standing between a macro nudge and a
dead die.

---

*Corrected twice on 2026-08-17: §5(a) after session 94 challenged the anchor,
§5(b) after the controlled 1505.60/1506.12 experiment refuted the
over-retraction. All quantities are this project's own placement coordinates and
power-plan parameters; no foundry values are reproduced.*
