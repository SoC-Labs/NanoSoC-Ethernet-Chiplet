# 53 — Gate-hardening plan: from four report-only stages to a trustworthy blocking system

Turning `layer-map-check`, `bnd`, `erc` and `padring-gds` (all built 2026-08-18, all currently
`gate: report`) plus the corner-rotation finding into gates worth trusting. Companion to
[48](48-imec-signoff-results-analysis.md), [49](49-layer-map-coverage-check.md),
[50](50-bnd-and-logo-checks.md), [51](51-erc-pg-labels.md), [52](52-padring-gds-check.md), and
`docs/plans/CONVERGENCE_PLAN_2026-08-18.md` §8-9.

## 1. Promotion criteria and order

The bar is `drc`'s own pattern (`docs/tapeout/39-po-r8-resolved.md` §7-8,
`scripts/ci/drc_census.py`): a **cell-scoped, self-testing waiver** — never a rule-scoped
suppression — with `check_proof` fixtures that prove both a real pass *and* every known
failure mode (stale waiver, drift, saturation, missing evidence). "The tool exited 0" is never
sufficient; each promoted gate needs its own `drc_census`-equivalent script with an explicit
pass/fail predicate.

| Order | Stage | Promotion evidence required | New `check:` predicate |
|---|---|---|---|
| 1 | `padring-gds` | **DONE 2026-08-18** — Clean (or waived-clean) run on ≥2 real builds (fp1505 + one successor); names/counts/order already verified against the exact GDS IMEC saw (doc 52). Corner-orientation extension added and validated against real GDSII bytes, the exact IMEC-evaluated archive, and fp1505 — see doc 52 §7. Promoted `report`→`block` in `ci/signoff.yaml`; stage is currently RED on fp1505 (a real, un-re-streamed defect), which is the correct, intended outcome, not a regression | Parse the JSON report, fail on any `MISMATCH`/`MISSING`/`EXTRA`/`ORIENTATION_MISMATCH`, `check_proof` with must-fail fixtures per defect class (renamed cell, dropped cell, reordered side) **plus orientation** — all 5 proven via `scripts/ci/signoff.py prove padring-gds` |
| 2 | `layer-map-check` | `LAYER_MAP_EXTRA` fed a real foundry layer table across ≥1 full-merge build, with an explicit allow-list for the vendor-drawn layers the Makefile already documents as expected-unmapped | Flip `LAYER_MAP_STRICT=1`; the script must distinguish "unmapped, expected (vendor-drawn)" from "unmapped, populated, unexplained" — never a bare unmapped count |
| 3 | `erc` | OVERALL line parsed by a real `check:` (not "exit code is the verdict"); PARTIAL treated as fail, not folded into OK; VDDIO/VSSIO labels landed | New `erc_census.py`-style script grepping `OVERALL`, asserting `OK` exactly, `check_proof` covering OK/PARTIAL/error-exit fixtures |
| 4 | `bnd` | Rule-by-rule diff against IMEC's report closed (doc 50 already does this); LOGO AP-only fix wired into the real submission stream and re-verified post full-merge | Census-style script over the BND summary, cell-scoped waiver for any residual known-artefact, same stale/drift self-test as `drc` |

`padring-gds` goes first — cheapest, license-free, and already validated against the exact
failing IMEC GDS, closest to `drc`'s discipline today. `bnd` goes last — its promotion depends
on external re-validation (full-merge LOGO re-check) not yet in our control.

**Row 4 done, 2026-08-18 — landed as `report`, not `block`.** The rule-by-rule diff IS
closed with a real script (`scripts/ci/imec_rule_diff.py`, `bnd`/`logo` wired into
`ci/signoff.yaml` with real `check:`/`check_proof:`), but two things stopped short of the
`block` bar this row's evidence column names: (1) a **new** finding, not an old one closed —
16 design-owned `AP.W.1`/`AP.S.1` results, exact-matching IMEC, never root-caused as
acceptable, so a zero-budget block gate would fail permanently starting today; (2) the LOGO
AP-only fix was re-verified against a denser LOCAL stream (third independent real zero) but
**not** against a real full-library merge — neither IMEC archive ever checked the AP-only
artefact, only the original marked logo, whose `LOGO.R.4` true count demonstrably grew +19.9%
under full merge (evidence, not assumption, that "more real geometry moves LOGO numbers" is a
real phenomenon for this rule family). Full evidence and the promotion decision:
`docs/tapeout/50-bnd-and-logo-checks.md` Part C.

## 2. New gates needed

**Padring orientation check — do this first. DONE 2026-08-18, see doc 52 §7.**
`check_padring_gds.py` already parses
`.io`/`pads.v`/`place_bondpads.tcl` and reads live GDS SREF/AREF transforms for `PCORNER_G`; it
never compared the transform against an *expected* orientation. Add an `expected_orientation`
table keyed by instance name, diffed against each placement's live rotation.

**Recommend a reviewed, commented lookup table — not a derived formula.** No generator exists
for `nanosoc_eth_chiplet_pads.io` (it was hand-edited once, commit `9f57214`, and drifted
silently for months) so there is no authoritative geometric rule to derive "expected" from — a
formula would just re-encode the same one-off knowledge with extra indirection and its own risk
of being wrong from day one, the same way `04-floorplan-and-io.md` §4.2 (commit `b5d249c8`)
*asserted* a "verified" +90°/step pattern that was in fact wrong. A table, reviewed against the
`.io` file today with each entry commented on *why* (die corner + which edges the pad ring must
face), is auditable in a way a formula guessing symmetry from LEF `SYMMETRY` bits is not —
`PCORNER_G` is rotation-symmetric for `CSR.R.1` purposes but *not* for which TL/TR/BL/BR
position it may sit in relative to the pad rows it must abut.

**Regression fixture for the corner-rotation bug. DONE 2026-08-18.**
`ci/fixtures/padring-orientation/fail-corner-180`,
built from the pre-fix `.io` values (R90/R180/R270/R0), wired into `check_proof.must_fail` —
the same "prove the gate can fail" discipline doc 45 §3.8 names as a real, named deficiency for
`cdc`/`lvs-preflight`. (Landed as a real-GDSII-bytes regression proof, generated by
`scripts/ci/gen_padring_orientation_fixture.py`, *plus* JSON-based `check_proof:` fixtures under
`ci/fixtures/padring-gds/` proving the promoted `check:`'s own post-condition logic — see doc 52
§7 for why both layers exist.)

**CSR / 157-category ratchet — DONE 2026-08-18.** Not a fix — a `DRC_DESIGN_BUDGET`-style budget
file recording today's counts (the 644/804(816)/96 CSR.R.2:B/D/EN.8 hits — exact figures below —
and all 157 new-in-archive-2 rule categories, each with its capped/uncapped pair) that a
`drc_census`-sibling refuses to let grow silently.

- Budget file: `ASIC/genus-innovus/scripts/calibre/csr_ratchet_budget.yaml` — `tracked_checks:`
  (`CSR.R.2:B` ceiling 644, `CSR.R.2:D` ceiling 804, `CSR.EN.8` ceiling 96, each against its
  archive-1 count and a `justification:`) plus `new_categories:` (all 157, `[capped_count,
  original_count]`, pulled by diffing archive 2's DRC summary rulecheck-name set against archive
  1's — not hand-copied). Baseline sourced from archive 2 (fuller/more-recent merge), against
  both archives' `drc/cali_drc_...rpt`; every number re-verified against those files directly,
  not transcribed from this doc or `CONVERGENCE_PLAN`.
- Script: `scripts/ci/csr_ratchet.py` — reuses `drc_census.parse_summary()` rather than
  reimplementing the Calibre-grammar parser (see the script's own "why a standalone sibling"
  section for why it is a sibling, not an extension, of `drc_census.py` itself). Fails if any
  tracked check exceeds its ceiling; separately FLAGS (never fails on, by itself) any rulecheck
  firing that is in neither `tracked_checks` nor `new_categories`. `--self-test` re-derives the
  budget file's numbers directly from the two raw archive reports when reachable (host-local,
  gitignored — `ASIC/imec_results` is not in a normal checkout, so this degrades to an explicit
  SKIP, never a silent pass) and runs 8 synthetic fixtures (over-ceiling, at-ceiling, untracked
  new category, both at once, an absent tracked check, and two malformed-budget cases) proving
  the mechanism discriminates — the `drc_waivers.yaml` stale/drift discipline
  (`docs/tapeout/39-po-r8-resolved.md` §8), applied to a budget file. Proven against the real
  archive 2 report with one count synthetically inflated (`CSR.R.2:B` 644→900): `csr_ratchet.py`
  correctly FAILs, naming the check and both numbers.
- Wired as `ci/signoff.yaml` id `csr-category-ratchet`, `phase: physical`, `gate: report` (runs
  `--self-test` — there is no live full-merge summary to check against yet, see below), plus
  `make csr-ratchet`/`make csr-ratchet-selftest` in `ASIC/genus-innovus/Makefile` and
  `make asic-csr-ratchet`/`make asic-csr-ratchet-selftest` at the repo root.
- `report`-gated until root-caused; `block`-gated once the count has a verified ceiling and no
  unexplained residue — neither is true today (§4's classification of items 4/9 as
  "ambiguous"/"structurally undetectable locally" stands). **The baseline itself is against the
  STALE reference GDS** (legacy engine, 2026-08-10 — see the budget file's own header) — the
  ratchet's real job right now is "don't let a future re-check show these numbers growing past
  today's baseline," not "gate the current build," since the current `fp1505`/`full-20260814`
  lineage has never had a full-library-merge DRC run at all.

**PVDD2POC cardinality check — DONE 2026-08-18.** A structural netlist check on
`nanosoc_eth_chiplet_pads.v` reporting the CURRENT instance count for `PVDD2POC_G` (today: 4, one
per pad-ring side, all wired to `VDDIO`; verified at lines 215/228/241/249) next to the
best-evidenced-but-UNCONFIRMED IMEC convention (1 per ring) — cheap, license-free, `report`-gated
until the broker/vendor confirms "one per ring" semantics. **Does not** silently convert the
other three to `PVDD2DGZ_G` — confirmed by construction: the script only reads and reports, never
writes to `nanosoc_eth_chiplet_pads.v`.

- Script: `scripts/check_pvdd2poc_cardinality.py`. Parses `nanosoc_eth_chiplet_pads.v` (the sole
  authoritative source for cell TYPE — neither `place_bondpads.tcl` nor `nanosoc_eth_chiplet_pads.io`
  names a cell type at all, both were checked and confirmed to carry instance names/placement only)
  and cross-checks every `PVDD2POC_G` instance name against both of those files, informationally,
  for the same desync failure class `check_padring_gds.py` already guards for the rest of the
  pad ring. Drift-detects (fails, report-gated) on the count moving in EITHER direction, on
  mixed-net wiring, or on a name dropping out of the `.io`/`place_bondpads.tcl` cross-check.
  Proven both directions: a synthetic 3-of-4-converted-to-`PVDD2DGZ_G` `.v` file and a
  `--expect 1` run both correctly DRIFT-DETECT (exit 1); the real, current `.v` file PASSes
  (exit 0) against the recorded baseline of 4.
- Wired as `ci/signoff.yaml` id `padring-power-domain`, `phase: physical` (topically grouped with
  `padring-gds` directly above it), `gate: report`, `label: soclabs-sim` (no PDK or Calibre seat
  is actually needed — only the tracked Verilog source), matching `padring-gds`'s shape
  (`needs_implementation`-free, `run:` + `artifacts:`, no `check:`).
- Makefile: `make pvdd2poc-check` in `ASIC/genus-innovus/Makefile`, `make asic-pvdd2poc-check` at
  the repo root — same `LEGACY_ASIC_DIR` forwarding pattern as `asic-padring-gds`.

## 3. Sequencing

**Today, no Calibre seat needed:** orientation-table extension to `check_padring_gds.py` +
regression fixture; PVDD2POC netlist-count check (**DONE** —
`scripts/check_pvdd2poc_cardinality.py`); CSR/157-category budget-ratchet skeleton (**DONE** —
`scripts/ci/csr_ratchet.py` + `ASIC/genus-innovus/scripts/calibre/csr_ratchet_budget.yaml`; still
a skeleton in the sense that it has nothing live to check against yet — see its own §2 entry
above).

**Needs a Calibre seat:** `layer-map-check` strict-mode validation against a full-merge build;
`erc` OVERALL-parsing script + VDDIO/VSSIO re-check (root cause now named — a LEF pin-type
defect at `ASIC/tech_wrappers/tsmc65/design_config.tcl:177-189`, not yet fixed); `bnd`/LOGO
re-verification post full-merge.

**Needs external input:** PVDD2POC confirmation (broker/vendor datasheet); fuller CSR by-cell
attribution (broker report or a local re-check on the rotation-fixed, fully-merged stream); the
CSR.R.1 ESD ruling (`floorplan.tcl:219-223`).

## 4. IMEC tool parity, current state (2026-08-18)

| IMEC tool/check | Local equivalent? | Gap-closing feasibility |
|---|---|---|
| LayerMapCadence | Partial — no standing local copy of the real layer table (licence-forbidden to commit); closed per-submission via `--imec-report` | needs-vendor-data (permanent), workaround already free |
| CheckIPWM | No | needs-vendor-data (permanent — no Back-End PDK) |
| CompareCells | Partial — our own names/counts/order self-consistent and confirmed correct (doc 52), can't diff against real vendor cell names locally | needs-vendor-data |
| DevCheck | No | needs-vendor-data (permanent) |
| `bnd` deck | **Yes** | closed — exact match on AP.W.1/W.2/S.1 |
| `custom_drc` (MINIASIC) | Partial — approximated via the main deck + mini@sic header, not the literal foundry file; LOGO numbers already track IMEC's closely | not worth resolving — see rec. below |
| main `drc` + `ant` | **Yes** | closed — PO.R.8 exact match, antenna 782/782 both archives |
| ERC (PG labels) | **Yes, partial fix** | free — root cause named, VDDIO/VSSIO fix outstanding |
| Padringcheck: names/counts/order | **Yes** | closed |
| Padringcheck: orientation | **Yes — DONE 2026-08-18** | closed — see doc 52 §7; reproduces IMEC's own 4 `Error-padringcheck` lines exactly |
| Padringcheck: bond-attach warnings | No | free but low-value (needs a bond map that doesn't exist yet) |
| Padringcheck: power-domain cardinality | **Visibility check DONE** (`scripts/check_pvdd2poc_cardinality.py`) | needs-vendor-data to confirm what the RIGHT count is; the drift-detection check is now free and added — see §2 above |

**Recommendation on DevCheck/CheckIPWM:** don't chase a real equivalent. A weak sanity check
(static device-count estimate from Genus synthesis reports, cross-checked by hand against
whatever IMEC returns) could work, but given how rarely this project submits, "wait for IMEC's
real number and diff it by hand" is good enough. Build only if submission cadence increases.

**Recommendation on `custom_drc` deck identity:** not worth resolving. Archive 1's LOGO numbers
already matched IMEC's real deck almost exactly under our main-deck approximation, and archive
2 confirms LOGO stays identically saturated regardless of library merge — the approximation
tracks faithfully on the rules that matter. Chasing the literal foundry file needs the same
Back-End PDK we don't have anyway.

## 5. Where this plan lives

This page holds the mechanics. `docs/plans/CONVERGENCE_PLAN_2026-08-18.md` §9 carries the retrospective
(what should have been caught) and links here for the forward plan.
