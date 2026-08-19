# `PO.R.8` — the contradiction resolved, and the waiver built on the answer

**Status: RESOLVED 2026-08-18.** Two of our own documents said opposite things about
the same 691 results. They have been reconciled against the run data, not against
each other. This page is the evidence; `docs/asic/DRC_WAIVER_INVENTORY.md` § 2 is the
dossier entry; `ASIC/genus-innovus/scripts/calibre/drc_waivers.yaml` is the
implementation.

---

## 1. The contradiction

| document | claim |
|---|---|
| `docs/asic/DRC_WAIVER_INVENTORY.md` § 2 (compiled 2026-08-17) | "`PO.R.8` was previously treated as an abstraction artefact that an IO-layout import would resolve. **It is not.** Its results are real merged memory GDS … An IO import changes nothing about them." |
| `docs/tapeout/28-drc-status-and-attribution.md` § 4 (corrected 2026-08-13) | the opposite — they *are* a black-boxing artefact, and the import is exactly what resolves them |
| `docs/tapeout/27-broker-questions-SEND-NOW.md` Q4 | agrees with 28: "the same macros inside a previously taped-out chip with real cell layouts report zero" |
| `scripts/ci/drc_census.py` docstring | agreed with the inventory — so it was **three against two**, and majority was not evidence |

**Doc 28 and doc 27 are right. The inventory and the census docstring were wrong,
and are corrected.**

## 2. The two questions that were being conflated

This is why the wrong answer was defensible for four days.

| question | evidence | answer |
|---|---|---|
| Is this a **rule-revision** artefact — a 2024 deck flagging what a 2012 deck did not? | 691 under the 2024 signoff deck **and** 691 under its 2012 predecessor (deck revision names not reproduced here — read them off your own PDK install; doc 28 § 4 records the pair) | **No.** Stable across twelve years of revisions. |
| Is this a **context** artefact — the same geometry judged differently with and without surrounding cell layout? | the controlled experiment below | **Yes.** |

The deck-version table answers the first and says **nothing whatever** about the
second. The inventory read "identical under both decks" as "inherent to the
macros". It is not: the two runs share the black-box condition, so they cannot
discriminate. Do not quote that table for this purpose again.

## 3. The controlled experiment — checked, and it holds

`ASIC/genus-innovus/runs/fanis/nanosoc_fanis_26_02_24v2.gds` is a previously
taped-out chip (top cell `nanosoc_chip_pads`, 1000 × 1500 µm) that carries the
same Artisan macros **with real standard-cell layout around them**. Same deck,
same tool, same macro geometry; only the surroundings differ.

| context | run dir | `rf_08k` | `rf_16k` |
|---|---|---:|---:|
| macro alone as `LAYOUT PRIMARY`, our vendor copy | `drc_macro_rf_08k` | 80 | — |
| macro alone as `LAYOUT PRIMARY`, **out of the taped-out file** | `drc_fanismacro_rf_08k` / `_rf_16k` | 80 | 82 |
| inside **our** chip (surroundings are LEF abstracts) | `drc_toolkit_20260817` | **80** | **82** |
| inside the **taped-out** chip (surroundings are real cells) | `drc_fanis_20260813` | **0** | **0** |

**The comparison does not depend on the two files holding identical macros.** Doc
28 says the macro is byte-equivalent in both, and it may well be, but that claim
is not load-bearing here and was not re-checked: rows 2 and 4 are **the same
file**. `drc_fanismacro_rf_08k` promotes that file's own copy of the macro to
`LAYOUT PRIMARY` and gets 80; `drc_fanis_20260813` checks the same file as a
whole chip and gets 0 from it. Within one GDS, the only variable left is whether
the macro is being judged alone or in company.

Two further things in that table are load-bearing and were verified for this page
rather than taken on trust:

**a. Our in-chip number is exactly the standalone number.** `rf_08k` = 68
(`rf_08kCNTRL`) + 8 (`rf_08kWDX64`) + 4 (`rf_08kCOLM8_BIST_WM`) = **80**, and
`rf_16k` = 70 + 8 + 4 = **82**. Our surroundings contribute nothing, because our
surroundings contain no diffusion at all.

**b. The taped-out chip's zero is a real zero, not an attribution artefact.**
`drc_fanis_20260813` is *not* a clean run — it reports 1,449 results and **148
`PO.R.8`**. The claim needed testing, because "zero from the macros" and "zero in
the chip" are different statements and only the first is being made. Checked two
ways:

* **By attribution.** Its `(BY CELL)` section names eight cells: `PAD60LU`,
  `PRDW0408SCDG`, `PVDD1CDG`, `PVSS1CDG`, `PVDD2CDG`, `PVSS2CDG`,
  `AOI22_X0P5M_A12TR` and the top cell. **Not one `rf_*`, `rom_via*` or
  `flash_cache_*` cell appears at all** — not for `PO.R.8`, not for any check.
* **By coordinate**, because Calibre promotes a result to the top cell when the
  geometry that caused it spans more than one, so an absent cell name is not by
  itself proof. The macro placements were read straight out of the GDS
  hierarchy: 2 × `rf_08k`, 2 × `rf_16k`, 1 × `rom_via`, at

  ```
  rf_08k   545.800  440.520 – 857.600  594.610      rf_16k  545.800  772.700 – 857.600 1057.950
  rf_08k   545.800  606.610 – 857.600  760.700      rf_16k  545.800 1069.950 – 857.600 1355.200
  rom_via  142.340 1303.945 – 307.125 1355.200
  ```

  All 148 `PO.R.8` polygons were extracted from the results database and tested
  against those five boxes. **148 of 148 fall outside every one.** They are real
  floating gates in that chip's own logic — which is the other half of the proof:
  `PO.R.8` is not a check that goes quiet when cells are real. It fires there. It
  just does not fire from the memories.

**The arithmetic.** If these results were inherent to the macros, that chip would
report 2 × 80 + 2 × 82 + 105 = **429** from them. It reports **0**.

### 3.1 Which stream these numbers are from

Everything here is the **shipping stream**,
`ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds`
(streamed 2026-08-17 13:52) — both the reference run `drc_toolkit_20260817` and
an independent re-run made for this page (2026-08-18, 1,926 rulechecks, **837
results**, `PO.R.8` **691**, no check within 309 of the 1,000 cap). The two agree
exactly, so the count is reproducible and not a one-off parse.

**Not `fp1505`.** That build is the clean one for the *M5 offset* question, and
the shipping stream separately carries four real M5 VDD-to-VSS shorts that merge
the supplies in extraction. Neither fact touches these numbers — a short is an
LVS/extraction problem and `PO.R.8` is counted geometry — but the comparison
above is only valid because **both runs are the same stream**, so quote them as a
pair or not at all.

## 4. The mechanism, and why the cell list corroborates it

`PO.R.8` is net-based: `Float_GATE_check INTERACT NSDu > 1 BY NET`. It fires when
a gate's extracted net reaches no source/drain anywhere. A gate behind a macro
*input pin* has its source/drain in the driving cell, outside the macro. Our
stream has no standard-cell, IO or bond-pad layout (`write_stream` reports 384
master cells not found after merging), so every such driver is a LEF abstract with
metal pin shapes and no diffusion. The net then has a gate and nothing else, and
Calibre correctly calls it floating **given what it was shown**.

That predicts the results should sit in macro *periphery*, not in bitcell arrays.
They do — all 22 cells are control logic (`*CNTRL`), write drivers (`*WDX*`),
column/BIST logic (`*COLM*_BIST_WM`, `*CKM4_BIST`), ROM wordline decode
(`*CK64WLM8`) and output buffers (`*BUFDO_M8`). **No result is in a bitcell-array
cell.** This was not designed into the experiment; it is an independent check that
came out right, and it also explains why TSMC's `SRAMDMY` markers cannot help:
they sit on the bitcell arrays, which is precisely where the results are not.

## 5. Scope of proof — stated, not glossed

* **Directly demonstrated:** `rf_08k` (80) and `rf_16k` (82) — **162 of 691**.
  Only those two macro types exist in the reference chip.
* **Inferred** from the same mechanism plus the periphery distribution: the
  remaining **529** (`rf_01k`, `rf_32k`, `flash_cache_*`, and 64-wordline ROMs
  against the reference's 32-wordline one).
* Doc 27 Q4 already asks the foundry to report the `PO.R.8` count after import
  **either way**. That request is now more valuable, not less: it is the
  falsification test for the inferred 529. Leave it in.

## 5.1 There is no ERC route to these, by TSMC's own design

Worth recording because it is the obvious next idea and it is a dead end. The
Calibre LVS deck's changelog states:

> *"Remove floating gate checking in ERC section, because DRM has rule PO.R.8 to
> define it."*

Floating-gate checking was **deliberately moved out of ERC and into DRC**. So ERC
will never report these 691, `PO.R.8` is *the* floating-gate rule by the
foundry's own intent, and this cannot be reframed as an ERC concern or deferred
to the ERC run a sibling is holding a seat for. It is a DRC finding and it stays
one. (Established 2026-08-18 from the deck changelog, not inferred.)

## 6. What this does *not* license

`rom_via` standalone is 105 in the reference file and 109 in ours. **That is not a
discrepancy** — ROM contents are programmed in layout, so two differently-programmed
ROMs are legitimately different geometry. It does mean the reference's ROM is not a
byte-for-byte control for ours, and the ROM's 212 results (`rom_viaCK64WLM8` 103 +
`eth_rom_viaCK64WLM8` 103 + 2 × `BUFDO_M8` 6) rest on the mechanism, not on a
matched control. Said here so nobody later reads the table in § 3 as covering them.

## 7. Mechanism choice — why the waiver is not in the deck

Established by reading the flow, not by assuming it:

* `run_drc.sh` assembles the deck through `make_project_deck.sh`, which builds it
  as **derived header + `tail -n +250 <foundry deck>` copied verbatim**, both
  re-read from the read-only PDK on **every run**. There is nowhere in that to put
  a project waiver that would survive.
* Its one hook, `DECK_APPEND`, is documented in that file as "diagnostics only —
  never used by the signoff path".
* SVRF can express `DRC UNSELECT CHECK PO.R.8`, which is **rule**-scoped. That is
  the one thing we must not do: it would hide a `PO.R.8` in our own geometry the
  day we create one.
* Calibre's own auto-waiver flow **is installed** (`bin/waiver_flow`,
  `-waiver_file`, `-waiver_cell`), but it is marker-*geometry* based: it wants a
  waiver GDS, a second licence feature, and it **rewrites the results database** —
  destroying the raw 837 that we want on the record and want the foundry to
  reproduce independently. Rejected for that last reason above all.
* `scripts/ci/drc_census.py` is what `ci/signoff.yaml` (id: `drc`) delegates the
  entire DRC verdict to, and it already attributes every result to its owning
  cell. It is the one place in the flow that both **reads** the numbers and
  **judges** them.

So: **the deck is untouched and Calibre goes on reporting all 837.** The waiver
lives in `drc_waivers.yaml`, is applied by the census, and both numbers are
printed on every run.

## 8. Proof the waiver works

Reproduce all of it with no Calibre licence:

```
python3 scripts/ci/drc_census.py ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817
python3 scripts/ci/drc_census.py ASIC/genus-innovus/calibre_runs/drc_toolkit_20260817 --no-waivers
python3 scripts/ci/drc_census.py ASIC/genus-innovus/calibre_runs/drc_fanis_20260813
```

| control | expectation | result |
|---|---|---|
| waivers applied | 837 → **146**, exactly 691 waived across 22 cells | ✅ |
| `--no-waivers` | **837**, unchanged | ✅ |
| **independent Calibre re-run** of the same stream (2026-08-18), then censused | 837 raw → 146; `PO.R.8` still **691** in the summary, i.e. the deck really is untouched | ✅ |
| **cell-scoping, on real data**: the taped-out chip's 148 `PO.R.8` sit in `nanosoc_chip_pads` (146) and `AOI22_X0P5M_A12TR` (2) — cells the file does not name | **0 waived**, all 148 still reported, listed as "NOT waived (no entry)" | ✅ |
| **primary-cell guard**: add `nanosoc_eth_chiplet_pads: 140` to the waiver's cell list | refused **in code**; count stays 146, gate FAILS | ✅ |
| **stale**: rename one waived cell to one that does not exist | FAIL — "matched NOTHING … Fix the file; do not widen it"; the 74 re-surface as un-waived | ✅ |
| **drift**: change an expected count 74 → 73 | FAIL — "waived counts MOVED … a waived result that changed is a new fact" | ✅ |
| `ci/fixtures/drc/fail-waiver-stale` | permanent `must_fail` case, wired into `ci/signoff.yaml` | ✅ |

The last one is the one that matters in six months: it fails if anyone widens the
waiver to a rule-scoped suppression, because a rule-scoped waiver would swallow
`PO.R.8` in `rf_08kCNTRL_RECOMPILED` too.

**Six vendor-memory results are deliberately left un-waived** —
`VIA3.R.2__VIA3.R.3` in `rf_01kMEM_SLICE`. No control covers them (`rf_01k` is not
in the reference chip, and no mechanism ties a via-redundancy rule to absent
diffusion), and they are the standing proof that the waiver is scoped rather than
bucket-wide. If the census ever reports vendor-memory 0, something has gone wrong.

## 9. What changes for the submission

The waiver text had to match whichever answer was true. It is the first of the two:

> Excluded because our stream carries no cell layout, so `PO.R.8` cannot be
> answered about these macros here; the foundry's import resolves them. We have
> asked them to report the count either way.

**Not** the second ("real vendor geometry, needs a foundry/IP waiver"). That
matters practically: there is **no ready-made vendor cover** for the second story
and we must not invent one. TSMC's `SRAMDMY` exclude never reaches this rule, and
the ARM register-file compiler's release note (§5 *Known issues & work-around*;
revision-coded product name not reproduced here) waives `M5–M9.DN.1L` density and four
`PATHCHK` ERC categories in these macros but **not** `PO.R.8`. Doc 27 Q4 is
already written for the correct story and needs no change — send it as it stands.
