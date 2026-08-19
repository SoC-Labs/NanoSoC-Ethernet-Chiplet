# DRC Waiver Inventory

Every DRC result on the shipping stream, assigned to **fix** or **waive**, with
the reason and — for each waiver — what it would take to withdraw it.

Compiled 2026-08-17 against
`ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817`, which measured
`ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds`
(streamed 2026-08-17 13:52). **Revised 2026-08-18**: § 2's verdict on the 691
`PO.R.8` was wrong and is corrected, and those results are now waived in the
census rather than only on paper. Reproduce the numbers with:

```
python3 scripts/ci/drc_census.py ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817
                                                                     # 837 raw -> 146 reported
python3 scripts/ci/drc_census.py ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817 --no-waivers
                                                                     # 837, the number the foundry will get
```

**The premise of this document.** On 2026-08-17 it was decided that the **TSMC
Back-End packages will not be obtained**. That converts three previously
open items into permanent conditions of this project, and it is the reason this
inventory exists: the un-fixable classes need to be waived *on the record* with
their consequences stated, not parked pending a delivery that is not coming.
`TSMC_BACKEND_PACKAGE_REQUEST.md` describes a route that is now closed;
this document supersedes its status section.

Verdict vocabulary, deliberately narrower than the CDC inventory's:

| Verdict | Meaning |
|---|---|
| **FIX** | Ours, actionable by a P&R iteration. No waiver. |
| **WAIVE-BLACKBOX** | Fires only because our stream carries no cell layout. Resolves on the foundry's import; nobody needs to sign anything off. |
| **WAIVE-VENDOR** | Inside vendor GDS we hold no editable source for, and *not* explained by black-boxing. Needs a foundry/IP waiver at submission. |
| **WAIVE-STRUCTURAL** | Not measurable on this site at all, because the layers it checks are absent from every stream we can produce. |
| **WAIVE-INFO** | The deck emits it as a reminder or warning, not a violation. |

`WAIVE-BLACKBOX` and `WAIVE-VENDOR` were one verdict until 2026-08-18 and the
distinction is not cosmetic: one costs an email, the other costs a signature we
have no route to. § 2 records why the 691 moved from the second to the first.

---

## 1. Headline accounting

Every result is assigned. Nothing is waived by omission.

| Bucket | Count | Verdict |
|---|---|---|
| vendor-memory `PO.R.8` | **691** | WAIVE-BLACKBOX — **suppressed in the census from 2026-08-18** |
| vendor-memory `VIA3.R.2__VIA3.R.3` | **6** | WAIVE-VENDOR — deliberately **not** suppressed, see § 2.1 |
| design geometry | **96** | FIX (94) + WAIVE-INFO (2) |
| design density/dummy parent entries | **44** | FIX (33) + WAIVE-STRUCTURAL (11) |
| io-pad-abstract | **0** | — (was 140; closed by the LEFOBS map fix) |
| **TOTAL results, raw** | **837** | what Calibre reports and what the foundry will reproduce |
| **TOTAL results, reported** | **146** | 837 − 691. The number to work from. |

Both numbers are printed by `drc_census.py` on every run, and the Calibre deck is
untouched — the raw 837 is preserved evidence, not a number we have edited away.
`--no-waivers` reproduces it.

Density is counted separately, in *windows*, because Calibre reports one merged
result per check and writes the real detail to `<check>.density`:

| Density class | Windows | Verdict |
|---|---|---|
| back-end (M1–M9, AP), CORE-ONLY failing | **6,149** of 12,805 | FIX — metal fill |
| front-end (OD, PO) | **23,246** | WAIVE-STRUCTURAL |

---

## 2. WAIVE-BLACKBOX — 691 `PO.R.8`

> ### ⚠ CORRECTED 2026-08-18. THE PREVIOUS VERSION OF THIS SECTION WAS WRONG.
>
> It said: *"`PO.R.8` was previously treated as an abstraction artefact that an
> IO-layout import would resolve. It is not. Its results are real merged memory
> GDS … An IO import changes nothing about them."*
>
> **That is false.** It *is* an artefact of black-boxing, and the import is
> exactly what resolves it. `docs/tapeout/28-drc-status-and-attribution.md` § 4
> and `docs/tapeout/27-broker-questions-SEND-NOW.md` Q4 had it right; this
> document, and `scripts/ci/drc_census.py`'s docstring, had it wrong. Both are
> now corrected.
>
> **The error was a conflation, and it is worth naming so it is not repeated.**
> "Identical under the 2012 and 2024 decks" is true, and it rules out a *rule
> revision* artefact. It says nothing about *context*, because both of those runs
> share the black-box condition — they cannot discriminate. Evidence and full
> working: **`docs/tapeout/39-po-r8-resolved.md`**.

Inside 22 Artisan memory-compiler leaf cells: `eth_rom_viaCK64WLM8` (103),
`rom_viaCK64WLM8` (103), `rf_32kCNTRL` (74), `rf_16kCNTRL` (70), `rf_08kCNTRL`
(68), `flash_cache_dataCNTRL` (67), `flash_cache_tagCNTRL` (62),
`rf_01kCKM4_BIST` (60), six `*WDX*` cells (8 each), two `*BUFDO_M8` (6 each) and
six `*COLM*` cells (4 each). The full list with per-cell counts is the waiver
file itself, `ASIC/genus-innovus/scripts/calibre/drc_waivers.yaml`.

**Why it is waived.** `PO.R.8` is net-based: it fires when a gate's extracted net
reaches no source/drain anywhere. A gate behind a macro input pin has its
source/drain in the *driving* cell, outside the macro — and in our stream every
driver is a LEF abstract with no diffusion at all. Calibre is calling the net
floating, correctly, given what it was shown. Merge real cell layout and they go.

**The evidence, in one line.** The same macros inside a previously taped-out chip
that has real cell layout report **0**, against **429** expected if the results
were inherent — verified both by cell attribution and by testing all 148 of that
chip's own `PO.R.8` coordinates against the five memory footprints (none inside).
Our own in-chip counts equal the standalone black-box counts exactly (80 and 82),
i.e. our surroundings contribute nothing. Directly demonstrated for 162 of the
691; the other 529 rest on the same mechanism — stated plainly, and doc 27 Q4
asks the foundry to report the count either way, which is the falsification test.

**To withdraw this waiver:** the foundry reports a non-zero `PO.R.8` after
importing cell layout. That would refute the mechanism and turn these into a real
vendor-IP waiver request — for which **there is no ready-made cover, and none may
be invented**: TSMC's `SRAMDMY` exclude does not reach this rule (the
floating-gate chain is built from raw `PO`/`OD`, and the markers sit on bitcell
arrays while every one of these results is in periphery/control logic), and ARM's
register-file compiler release note (§5 *Known issues & work-around*;
revision-coded product name not reproduced here) waives `M5–M9.DN.1L` density and four
`PATHCHK` ERC categories in these macros but **not** `PO.R.8`.

**How it is implemented.** `drc_waivers.yaml`, consumed by `scripts/ci/drc_census.py`
— the script `ci/signoff.yaml` (id: `drc`) delegates the whole DRC verdict to.
Cell-scoped, never rule-scoped: a `PO.R.8` in any cell not named there still
reports, and one attributed to the layout primary cell is refused **in code**, so
no edit to the yaml can suppress a violation in our own routing. It fails the gate
if it goes stale, if any waived count moves in either direction, or if it names
the top cell. Not in the Calibre deck, and deliberately so — `make_project_deck.sh`
copies the foundry rule bodies verbatim from the read-only PDK on every run, so
Calibre still reports all 837 and the raw summary stays untouched evidence.
Proof of all six controls: `docs/tapeout/39-po-r8-resolved.md` § 8.

### 2.1 WAIVE-VENDOR — 6 `VIA3.R.2__VIA3.R.3`, and why they still show up

Six results in `rf_01kMEM_SLICE`. Also vendor geometry, also un-editable by us,
and still carried as WAIVE-VENDOR for submission. They are **deliberately left
out of the suppression** for two reasons:

1. **No control covers them.** `rf_01k` is not in the reference chip, and unlike
   `PO.R.8` there is no mechanism tying a via-redundancy rule to absent
   diffusion. Waiving them would be suppression on an unestablished premise —
   the exact fault this revision of the document exists to correct.
2. **They are the standing positive control.** Six vendor-memory results survive
   into the reported count on every run. If the census ever prints a
   vendor-memory total of 0, the waiver has stopped being cell-scoped and has
   started swallowing the bucket. Six results drown nothing.

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
your own install, or from `TSMC_BACKEND_PACKAGE_REQUEST.md § 1`, which is
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
| 1 | `M4.S.2.1` 28 + `M4.S.1` 12 | **40** | M5 straps anchored per-macro by `split_row`, so `route_special` drives deep M4 risers *inside* the QSPI cache RAM footprints alongside the vendor's internal M4 columns; merged shapes cross the wide-metal breakpoint and the vendor's legal internal gap becomes illegal. All 40 sit within 8 µm of a cache-RAM horizontal edge, on a regular 8.4 µm riser pitch. | **root-caused; fix identified, not yet run.** The lever is the per-region ladder anchoring itself, *not* the M5 offset (§ below) and *not* the channel sizes (`power_plan.tcl` § the channel table). `build/fp1505` runs the **default offset 8** — an earlier revision of this document said offset 5, which was a misreading of `power_plan.tcl`'s own comment echoed into the run log. |
| 2 | `VIA3.R.2__VIA3.R.3` 17 + `VIA3.R.4:M4` 2 | **19** | single via on M3/M4 wider than 0.3 µm — the deck requires more than one. | router setting: enable via-doubling on wide wires. Not hand work. |
| 3 | `G.4:M5i` 15, `M2i`/`M4i`/`M6i`/`M7i` 2 each | **23** | adjacent edges shorter than min width — router notches/jogs. | notch cleanup / `setNanoRouteMode` jog control. |
| 4 | `M8.W.1` 3, `M8.S.3` 2, `M5.A.2` 2, `M5.W.1`/`M5.A.1`/`M6.W.1`/`M7.W.1`/`M9.W.1` 1 each | **12** | width/area slivers; the two `M8.S.3` sit on the die top and bottom edges. | PG trim at the core-ring boundary. |

### The M5 offset is not a lever — measured, and closed

**There is no offset worth running. Do not sweep it again.** An earlier revision
of this section presented offset 5 vs 6 as a decision to be made. It is not one.
Calibre on the offset-5 stream against the offset-8 shipping baseline — both
re-streamed *after* the 2026-08-17 12:28 map edit, so the map is constant and the
offset is the only variable:

| | F=8 shipping | F=5 |
|---|---|---|
| design-owned **total** | **140** | **140** |
| design **geometry** | 96 | **98** |
| back-end density windows | 6,149 | **6,219** |

It is a 1:1 redistribution between rule classes, not a reduction:

| leaves | | arrives | |
|---|---|---|---|
| `M4.S.2.1` | 28 → 7 | `M5.A.2` | 2 → **27** |
| `M4.S.1` | 12 → 0 | `G.4:M4i` | 2 → **14** |
| `VIA3.R.2/3`, `M8.W.1`, `G.4:M2i`, `M6/M7.W.1` | −8 | `G.4:M5i`, `VIA4.R.2/3`, `M6.S.1`, `M6.A.2` | +6 |
| **−41** | | **+43** | |

This confirms at signoff level what `power_plan.tcl`'s aliasing model derived:
one binary condition — does a third M5 stripe fit inside a short macro — drives
two classes in opposite directions, so no offset wins both. Reproduce with
`drc_census.py` over `drc_toolkit_20260817` (F=8) and `drc_m5off5_20260817` (F=5).

> **Never rank a P&R variant on Innovus `check_drc`.** On this same pair the
> in-tool total reads 71 → 69, i.e. *better*, while the Calibre design-owned
> count goes 96 → 98, i.e. *worse* — **the two metrics disagree in sign**. The
> PG probe's offset table (base 71, F=6 56, F=5 69, F=4 94, F=2 105) would
> nominate F=6 as the winner; that nomination is worthless for signoff. Use
> `check_drc` as a smoke test only. Rail-to-rail short count and
> `check_connectivity` opens/dangling remain valid on the probe.

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

## 7. What the waiver mechanism does and does not reach

Stated because "waived" is being used here in two different senses and they must
not be allowed to blur:

- **Suppressed in our reporting:** the 691 only, and only inside the 22 named
  cells, and only in `scripts/ci/drc_census.py`. Nothing else in the flow changes.
- **NOT suppressed anywhere else.** The Calibre deck is untouched — the foundry
  rule bodies are copied verbatim from the read-only PDK on every run — so the
  run directory, `<block>.drc.summary`, and the results database all still carry
  the full **837**. Anyone we hand this to reproduces 837, and doc 27 Q4 asks
  them to. There is no version of this stream that reports 146 to a third party.
- **Still owed at submission regardless:** the 6 `VIA3.R.2__VIA3.R.3` (§ 2.1)
  and the structural items in § 3 need to be *stated* to the shuttle organiser
  whether or not anything suppresses them locally. A suppression is not an
  agreement.

## 8. What this inventory does not cover

- **LVS** is not waived here because it has never run full-chip. There is no CDL
  for the standard-cell, IO-driver or bond-pad libraries anywhere on this system
  (one 92-byte stub in the whole PDK), and with the BE decision there will not
  be. Black-box LVS *does* work on this site and is the only form available; see
  `ci/signoff.yaml`'s `lvs` gap entry.
- **Antenna** is **NOT COVERED, and must not be read as clean** (corrected
  2026-08-17). The previous wording here — "needs no waiver: it is 0 across every
  rulecheck on this stream, down from 1,549" — was true as written and materially
  misleading, because **the signoff deck contains zero antenna rulechecks**. The
  only `AN.*` check executed is `AN.R.46`, a differential-pair *matching* rule.
  A count of 0 over a set of no checks measures nothing; this is the same class of
  false pass as a capped `check_connectivity` count.
  **The foundry antenna deck HAS been run separately, and its 0 is also not a
  pass.** `ASIC/genus-innovus/calibre_runs/ant_toolkit_20260817` (2026-08-17
  15:39–16:02) ran
  the foundry antenna deck (an `INCLUDE` of the revision-coded antenna rule file
  under the PDK's `ANTENNA_DRC/` directory — not reproduced here, per §3; read it
  from `deck_expanded.rules` in that run directory on your own install) against
  `ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds`:
  **714 rulechecks, 0 results, 0 of 204 report files non-empty.** That is a NULL
  RESULT, not a clean one. An antenna ratio is gate area over connected metal
  area, and this stream carries no standard-cell, IO or pad layout — its
  `write_stream -merge` list holds only the eight vendor-memory GDS files. There
  are no gates in the stream for a ratio to be computed against, so 0 is the
  arithmetic of an absent measurement.
  (An earlier revision of this correction, made the same day, wrongly stated the
  foundry deck had never been run. It had. The conclusion is unchanged and better
  grounded: antenna cannot be measured until the foundry merges its own layout.)
  The 1,549 → 0 improvement is real but belongs to the LEFOBS stream-map fix as
  measured by Innovus `check_process_antenna`, which is a router-level LEF-based
  check and is not foundry antenna signoff.
  `route_gate.txt` already states this correctly ("antenna against the foundry
  deck" is listed as not covered); this inventory previously contradicted it.
  **Antenna signoff remains open.**
- **Boundary** is 1 result (`AP.DN.1.L`), inside the metal-fill item above.
