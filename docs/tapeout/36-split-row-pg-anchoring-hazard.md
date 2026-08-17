# `split_row` PG anchoring: one mechanism, five macros, and no gate

**Status: MECHANISM UNDERSTOOD. NOT FIXED. The four VDD–VSS shorts are closed on
the current floorplan by luck, not by repair.**

This document explains the *cause* behind several things that were being worked
as separate problems. For the shorts themselves — coordinates, the phasing rule,
and the `rf_32k` coordinate history — see
[`32-macro-placement-pg-short-window.md`](32-macro-placement-pg-short-window.md).
This one is about why they exist at all, and what it means for the next person
who moves a macro.

---

## 1. The mechanism

`power_plan.tcl:198` calls `split_row -selected` over all 21 placed macros. Per
the Innovus 21.11 reference (`TCRcom/split_row.html`) that command *"cuts site
rows within an area or that intersect with the selected object(s)"* — so every
macro gets its own row region.

`add_stripes` then re-anchors the M5 VDD/VSS ladder **per region**. From the M5
call at `power_plan.tcl:480` (`-width 1 -spacing 0.5 -set_to_set_distance 15
-start_from bottom -start_offset $M5_START_OFFSET`), each region's ladder runs at

```
    F + k*15      measured from THAT MACRO'S OWN bottom edge
```

Two consequences follow, and between them they account for everything below.

### 1a. Inside a macro, the ladder stops one pitch short of the channel

For the QSPI cache data RAMs (`flash_cache_data`, 311.8 × 36.36), k = 0,1,2 put
stripes at F, F+15, F+30 — and F+30 is the last that still lands inside a
36.36 µm footprint. The channel above occupies 36.36–45.0 in the same local
frame, so **the ladder never reaches it, at any offset.** `route_special` then
has nowhere to feed from except *inside* the footprint, driving deep M4 risers
alongside the vendor's internal M4 columns.

**This is not a channel-size problem, and the old comment saying it was has
misdirected people.** Measured channel heights through the stack:

| gap | µm | | gap | µm |
|---|---|---|---|---|
| `way1_w0 → way1_w1` | 8.64 | | `way0_w3 → way1_w3` | 8.64 |
| `way1_w1 → way0_w0` | 8.64 | | `way1_w3 → way0_w2` | 9.00 |
| `way0_w0 → way0_w1` | 8.64 | | `way0_w2 → way1_w2` | 10.44 |
| `way0_w1 → way0_w3` | 8.64 | | `way0_tag → way1_tag` | 26.09 |

A VDD+VSS pair spans **2.5 µm** (`-width 1 -spacing 0.5`: VDD at [y, y+1], gap
0.5, VSS at [y+1.5, y+2.5]). Every channel has **at least 8.64 µm** — three and a
half times what a pair needs. **Opening the channels would achieve nothing,
because nothing is trying to put a strap in them.**

### 1b. Between regions, the phases collide

Where two regions' ladders meet, VDD from one can land against VSS from the
other. That is the four rail-to-rail shorts, in the network bootrom's region.

---

## 2. What this one mechanism accounts for

**Five macros, of three different types, sizes and orientations, in unrelated
parts of the die.**

| owner | results | class |
|---|---|---|
| QSPI cache stack (10 macros) | **57** | 40 M4 spacing + 17 G.4 |
| network bootrom `rom_via` | **4** | rail-to-rail M5 shorts — *electrical* |
| imem `rf_32k` | 2 | G.4 |
| dmem `rf_16k` | 2 | G.4 |
| chip bootrom `rom_via` | 2 | G.4 |

The correlation is not loose. **All 40** M4 spacing results sit within 8 µm of a
cache-RAM horizontal edge, on a regular **8.4 µm riser pitch**. **All 10** G.4
notch locations sit on a macro edge — 9 on horizontal edges, and the tenth
1.1 µm off the chip bootrom's *right* edge at x = 1387.000 (`rom_via` is
164.665 × 59.735, placed at 1222.335, so 1222.335 + 164.665 = 1387.000 exactly).

Every G.4 edge is **5–80 nm** long — far below any routing track pitch. These
are not router jogs. Looking for a NanoRoute notch setting was a dead end.

---

## 3. The hazard: the damage has no locality

**A macro move can short VDD to VSS somewhere else entirely.** Row regions are
partitioned from *all* macros collectively, so changing one y re-phases ladders
belonging to macros nowhere near it.

Measured 2026-08-17: a **0.52 µm** nudge to `rf_32k` at **x = 290.8** changed the
short count in the network bootrom's ladder at **x = 883.5** — **550 µm away**.
Independently, `knobs-live` has zero rail shorts and `macro-move` has four, and
neither moved macro is within 550 µm of x = 844.5.

So you **cannot** clear a macro move by inspecting its neighbourhood, and a
clean-looking placement diff proves nothing.

---

## 4. Why the current numbers are lucky, not safe

`rf_32k = 1505.60` gives `(1538.60 − y) mod 15 = 3.000`, which sits a clear half
micron outside the phasing window. That is what closes the four shorts on the
current floorplan.

It is a coordinate that happens to fall in a safe phase. **The mechanism is
untouched.** Note the third row of the table in doc 32: the naive 1506.10 "back
off by the 20 nm overshoot" fix lands *exactly on* the interval edge, where the
two stripe edges become coincident — still a short, reported with a zero-height
marker that reads like a rounding artefact.

**Four more macro pairs sit within half a micron of the same window.** The next
nudge gets no such luck.

---

## 5. There is no gate for this, and both obvious instruments lie

Nothing in either flow checks that a PG stripe landed inside a macro. Worse, the
two numbers a person would naturally reach for are both untrustworthy here:

- **Innovus `check_drc` disagrees in sign with Calibre on this design.** On the
  F=8 vs F=5 pair the in-tool total reads **71 → 69** (better) while the Calibre
  design-owned count goes **96 → 98** (worse). **Never rank a placement or a PG
  variant on `check_drc`.** It is a smoke test.
- **The rail-short record's net order is reversed between stages** — the probe
  writes `Net VDD & ... Net VSS`, the full route writes `Net VSS & ... Net VDD`.
  A detector matching either literal finds 1 where the truth is 4. **Capture both
  net names and compare them**, and restrict the match to the `SHORT:` class — an
  M4 `ParallelRunLength` SPACING record also names two different supply nets and
  will otherwise be counted as a short.

### What to do if you move a macro

Re-run the PG probe (`scripts/probe_pg_build.tcl`) and read the **rail-to-rail
short count** specifically — not the DRC total — plus `check_connectivity` opens
and dangling. It takes about 3 minutes and needs no P&R licence, and it
reproduces the routed short count exactly (4 at every offset measured). **A macro
move that has not been through it is unverified, whatever the placement looks
like.**

Assert the grid was actually built before believing any number: the probe has a
recorded false-green mode where `power_plan` aborted, no grid existed, and
`check_drc` reported clean over a design with no special routing.

---

## 6. The offset is not the lever — closed by measurement

For the avoidance of another sweep: **the M5 start offset never reduces the
Calibre count. It redistributes classes 1:1.**

| | F=8 shipping | F=5 |
|---|---|---|
| design-owned total | **140** | **140** |
| design geometry | 96 | **98** |
| back-end density windows | 6,149 | **6,219** |

41 results leave M4 spacing (`M4.S.2.1` 28→7, `M4.S.1` 12→0) and 43 arrive
elsewhere (`M5.A.2` 2→27, `G.4:M4i` 2→14, `G.4:M5i` 15→18). One binary condition
— does a third M5 stripe fit inside a short macro — drives two classes in
opposite directions, so no offset wins both. Reproduce with `drc_census.py` over
`drc_toolkit_20260817` (F=8) and `drc_m5off5_20260817` (F=5); both streams were
re-streamed after the 2026-08-17 12:28 map edit, so the map is constant.

---

## 7. The fix, deferred

**Not this week's run.** The structural fix is to stop the ladder re-anchoring
per region: keep `split_row -selected` exactly as it is, and give the M5
`add_stripes` call a single explicit `-area` covering the core, so one continuous
ladder is generated over one region.

`-area {x1 y1 x2 y2 ...}` is confirmed present in this Innovus version. Two notes
for whoever implements it:

- `-area` is **mutually exclusive** with `-extend_to design_boundary` and with
  `first_padring`/`last_padring`, and errors if combined. The M8 and M9 calls
  (lines 124, 178) use `-extend_to all_domains` and would need checking. **The M5
  call at line 480 has no `-extend_to` at all** — it uses `-over_power_domain 1` —
  so the change is clean on exactly the call that needs it, and only that call.
- **Do not achieve this by removing `split_row`.** It is a *row* operation and
  `power_plan` runs *before* placement, so removing it changes the standard-cell
  row structure the placer will later see around all 21 macros. The PG probe
  rebuilds floorplan and power_plan only and is structurally incapable of
  warning you about that.

The measurement that proves the change did what is intended is the **anchor count
dropping to one**, not the DRC total.
