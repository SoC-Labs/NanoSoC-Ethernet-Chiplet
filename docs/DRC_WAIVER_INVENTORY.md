# DRC Waiver Inventory

Every DRC result on the shipping stream, assigned to **fix** or **waive**, with
the reason and — for each waiver — what it would take to withdraw it.

Compiled 2026-08-17 against
`ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817`, which measured
`ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds`
(streamed 2026-08-17 13:52). Reproduce the numbers with:

```
python3 scripts/ci/drc_census.py ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817
```

**The premise of this document.** On 2026-08-17 it was decided that the **TSMC
Back-End packages will not be obtained**. That converts three previously
open items into permanent conditions of this project, and it is the reason this
inventory exists: the un-fixable classes need to be waived *on the record* with
their consequences stated, not parked pending a delivery that is not coming.
`docs/TSMC_BACKEND_PACKAGE_REQUEST.md` describes a route that is now closed;
this document supersedes its status section.

Verdict vocabulary, deliberately narrower than the CDC inventory's:

| Verdict | Meaning |
|---|---|
| **FIX** | Ours, actionable by a P&R iteration. No waiver. |
| **WAIVE-VENDOR** | Inside vendor GDS we hold no editable source for. Needs a foundry/IP waiver at submission. |
| **WAIVE-STRUCTURAL** | Not measurable on this site at all, because the layers it checks are absent from every stream we can produce. |
| **WAIVE-INFO** | The deck emits it as a reminder or warning, not a violation. |

---

## 1. Headline accounting

Every result is assigned. Nothing is waived by omission.

| Bucket | Count | Verdict |
|---|---|---|
| vendor-memory geometry | **697** | WAIVE-VENDOR |
| design geometry | **96** | FIX (94) + WAIVE-INFO (2) |
| design density/dummy parent entries | **44** | FIX (33) + WAIVE-STRUCTURAL (11) |
| io-pad-abstract | **0** | — (was 140; closed by the LEFOBS map fix) |
| **TOTAL results** | **837** | |

Density is counted separately, in *windows*, because Calibre reports one merged
result per check and writes the real detail to `<check>.density`:

| Density class | Windows | Verdict |
|---|---|---|
| back-end (M1–M9, AP), CORE-ONLY failing | **6,149** of 12,805 | FIX — metal fill |
| front-end (OD, PO) | **23,246** | WAIVE-STRUCTURAL |

---

## 2. WAIVE-VENDOR — 697 results

Two checks, inside 23 Artisan memory-compiler leaf cells:

| Check | Count |
|---|---|
| `PO.R.8` | 691 |
| `VIA3.R.2__VIA3.R.3` | 6 |

Spread across `eth_rom_viaCK64WLM8` (103), `rom_viaCK64WLM8` (103),
`rf_32kCNTRL` (74), `rf_16kCNTRL` (70), `rf_08kCNTRL` (68),
`flash_cache_dataCNTRL` (67), `flash_cache_tagCNTRL` (62),
`rf_01kCKM4_BIST` (60) and 15 further leaf cells.

**Why it is waived.** These sit inside merged vendor memory GDS. We hold no
editable source for them and no P&R setting reaches them.

**Why it will not clear later, which is the correction this document makes.**
`PO.R.8` was previously treated as an abstraction artefact that an IO-layout
import would resolve. It is not. Its results are **real merged memory GDS**,
identical under both the 2012 and 2024 rule decks, and they are present because
the memory's own layout contains floating-gate structures the deck flags. An IO
import changes nothing about them.

**To withdraw this waiver:** obtain a foundry/IP-vendor sign-off on the memory
macros as delivered. This is a submission-time paperwork item, not an
engineering one, and it should be raised with the shuttle organiser early
because 691 results is a number that stops a submission desk cold without a
prior agreement in place.

---

## 3. WAIVE-STRUCTURAL — 11 results + 23,246 density windows

| Check | Count | |
|---|---|---|
| `PO.DN.2` | 5 | poly density |
| `PO.DN.1` | 1 | |
| `OD.DN.1` / `OD.DN.2` / `OD.DN.3` | 1 each | diffusion density |
| `DOD.R.1` / `DPO.R.1` | 1 each | OD/PO dummy-fill reminders |

plus the 23,246 front-end density windows (`PO.DN.2` 22,660, `OD.DN.2L` 445,
`OD.DN.3L` 139, `OD.DN.1L` 1).

**Why it is waived.** There is no OD or PO in the stream to measure. `write_stream`
reports **384 master cells not found after merging**; the PDK ships Front-End
packages only, and with the BE decision no `*_BE` directory will ever exist on
this site. Calibre is computing diffusion and poly density over cells that
contain neither. A number produced this way is not a lenient measurement, it is
not a measurement.

**The consequence, which must not be softened.** The same absence means the
design bucket is a **FLOOR, not a total**. Any rule that would fire between
top-level routing and a standard cell's *internal* geometry cannot fire, because
that geometry is not in the stream. **`design == 0` would mean "clean in the
layers we actually have", never "clean".** Every downstream report quoting these
numbers must carry that sentence.

**To withdraw:** the TSMC `_BE` counterparts of the standard-cell, IO-driver and
bond-pad libraries this design links against. The exact revision-coded package
names are deliberately not reproduced here — read them off the `_FE` packs on
your own install, or from `docs/TSMC_BACKEND_PACKAGE_REQUEST.md § 1`, which is
where they belong. Decided against 2026-08-17.

---

## 4. WAIVE-INFO — 2 results

| Check | Count | Why |
|---|---|---|
| `ESD.WARN.1` | 1 | "SDI is not in whole chip" — a deck advisory, not a geometry violation |
| `DRM.R.1` | 1 | the deck's own reminder to check related rules manually |

Neither denotes a geometry error. Both should be read once by a human and then
left; they do not clear by editing layout.

---

## 5. FIX — 94 geometry results

No waiver applies to any of these. Ranked by leverage:

| # | Class | n | Root cause | Status |
|---|---|---|---|---|
| 1 | `M4.S.2.1` 28 + `M4.S.1` 12 | **40** | M5 straps anchored per-macro by `split_row`, so `route_special` drives deep M4 risers *inside* the QSPI cache RAM footprints alongside the vendor's internal M4 columns; merged shapes cross the wide-metal breakpoint and the vendor's legal internal gap becomes illegal. All 40 sit within 8 µm of a cache-RAM horizontal edge, on a regular 8.4 µm riser pitch. | **fix in flight.** Mechanism established and scored 4/4 against predictions logged in advance (`power_plan.tcl:274-330`). `build/fp1505` is routing at M5 offset 5. |
| 2 | `VIA3.R.2__VIA3.R.3` 17 + `VIA3.R.4:M4` 2 | **19** | single via on M3/M4 wider than 0.3 µm — the deck requires more than one. | router setting: enable via-doubling on wide wires. Not hand work. |
| 3 | `G.4:M5i` 15, `M2i`/`M4i`/`M6i`/`M7i` 2 each | **23** | adjacent edges shorter than min width — router notches/jogs. | notch cleanup / `setNanoRouteMode` jog control. |
| 4 | `M8.W.1` 3, `M8.S.3` 2, `M5.A.2` 2, `M5.W.1`/`M5.A.1`/`M6.W.1`/`M7.W.1`/`M9.W.1` 1 each | **12** | width/area slivers; the two `M8.S.3` sit on the die top and bottom edges. | PG trim at the core-ring boundary. |

### The M4 offset decision

The offset sweep is a genuine trade, not a tuning exercise — one binary
condition (does a third M5 stripe fit inside a short macro) drives two classes in
opposite directions:

| M5 offset | total `check_drc` | macro-blockage | MINHOLE/M5 | rail-rail M5 short |
|---|---|---|---|---|
| 8 (**shipping**) | 68 | 33 | 2 | 4 |
| 6 | 54 | 22 | 0 | 4 |
| 5 (`fp1505`, in flight) | 67 | **5** | 27 | 4 |

Offset 6 gives the lowest total; offset 5 nearly eliminates the vendor-macro
class but pays 27 MINHOLE/M5. **There is no offset that wins both** — that is
derived from the aliasing model, not observed. Pick by which class you would
rather carry, and note that the shipping stream currently carries neither fix.

---

## 6. FIX — 6,149 density windows

The single largest item in this document, and one switch.

| Check | core-only failing | total |
|---|---|---|
| `M7.DN.1` | 1,430 | 2,160 |
| `M9.DN.2L` | 1,312 | 2,097 |
| `M6.DN.1` | 1,266 | 1,996 |
| `M8.DN.1` | 1,093 | 1,884 |
| `M5.DN.1` | 483 | 1,213 |
| `M4.DN.1` | 230 | 960 |
| `M2.DN.1` / `M3.DN.1` / `M1.DN.1` | 335 | 2,493 |

Metal fill **is implemented, and more carefully than the census's one-line
advice suggests.** `ASIC/genus-innovus/scripts/4b_pnr_route_eval.tcl:1197-1246`
already:

- **reads all 27 fill values out of the installed foundry deck** (`DMn_W_1`,
  `DMn_S_1`, `DMn_EN_1`) rather than carrying transcribed literals, and *errors*
  on a name the deck does not define — an empty `-min_width` would make fill
  produce nothing and report success;
- **asserts the M1–M7 thin-metal group is still uniform**, so a deck revision
  that splits it fails loudly instead of filling M2–M7 to M1's geometry;
- **sets M8 and M9 per-layer** from their own deck values — the "M9 needs
  3.0/3.0" advice is already satisfied, from the deck rather than by hand;
- **keeps fill out of the sealring corners** via `CSR_CORNER_KEEPOUT`
  (`floorplan.tcl:225`), written as a **square** `create_route_blockage -fills`
  precisely because fill silently ignores triangular blockages.

So both traps this document previously listed as open are closed in code. **The
only thing standing between this project and 6,149 fewer failing windows is that
`EVR_METAL_FILL` defaults to 0** (`4b_pnr_route_eval.tcl:134`) and no run has
set it to 1. The 33 back-end density/dummy parent entries (`M*.DN.*`,
`DM1-9.R.1`, `AP.DN.1:L`) are the same item counted as results.

**What to do:** run the route stage with `EVR_METAL_FILL=1` *on top of the
chosen M5 offset* (§5), not as a separate branch — fill changes coupling, and
the script already re-measures timing after fill for that reason. Then read the
next Calibre summary for the checks that saturated last time — `DM8.W.1`,
`DM8.S.1`, `DM9.W.1`, `DM9.S.1`, `DM8.EN.1`, `DM9.EN.1`, and `CSR.R.1` on
`DUM8_NEW`/`DUM9_NEW`/`APi`. `drc_census.py` fails the run if any of them cap,
so a capped count cannot be mistaken for a real one.

**One expected artefact, not a regression:** with `-border_spacing` set, Innovus's
own `check_metal_density` reports the border area as density 0 and will look
worse at the die edge than Calibre does. Calibre is the authority here.

---

## 7. What this inventory does not cover

- **LVS** is not waived here because it has never run full-chip. There is no CDL
  for the standard-cell, IO-driver or bond-pad libraries anywhere on this system
  (one 92-byte stub in the whole PDK), and with the BE decision there will not
  be. Black-box LVS *does* work on this site and is the only form available; see
  `ci/signoff.yaml`'s `lvs` gap entry.
- **Antenna** needs no waiver: it is **0** across every rulecheck on this stream,
  down from 1,549, closed by the LEFOBS stream-map fix.
- **Boundary** is 1 result (`AP.DN.1.L`), inside the metal-fill item above.
