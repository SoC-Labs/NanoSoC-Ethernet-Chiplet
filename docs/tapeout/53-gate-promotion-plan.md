# 53 — Gate-hardening plan: from four report-only stages to a trustworthy blocking system

Turning `layer-map-check`, `bnd`, `erc` and `padring-gds` (all built 2026-08-18, all currently
`gate: report`) plus the corner-rotation finding into gates worth trusting. Companion to
[48](48-imec-signoff-results-analysis.md), [49](49-layer-map-coverage-check.md),
[50](50-bnd-and-logo-checks.md), [51](51-erc-pg-labels.md), [52](52-padring-gds-check.md), and
`CONVERGENCE_PLAN_2026-08-18.md` §8-9.

## 1. Promotion criteria and order

The bar is `drc`'s own pattern (`docs/tapeout/39-po-r8-resolved.md` §7-8,
`scripts/ci/drc_census.py`): a **cell-scoped, self-testing waiver** — never a rule-scoped
suppression — with `check_proof` fixtures that prove both a real pass *and* every known
failure mode (stale waiver, drift, saturation, missing evidence). "The tool exited 0" is never
sufficient; each promoted gate needs its own `drc_census`-equivalent script with an explicit
pass/fail predicate.

| Order | Stage | Promotion evidence required | New `check:` predicate |
|---|---|---|---|
| 1 | `padring-gds` | Clean (or waived-clean) run on ≥2 real builds (fp1505 + one successor); names/counts/order already verified against the exact GDS IMEC saw (doc 52) | Parse the JSON report, fail on any `MISMATCH`/`MISSING`/`EXTRA`, `check_proof` with must-fail fixtures per defect class (renamed cell, dropped cell, reordered side) |
| 2 | `layer-map-check` | `LAYER_MAP_EXTRA` fed a real foundry layer table across ≥1 full-merge build, with an explicit allow-list for the vendor-drawn layers the Makefile already documents as expected-unmapped | Flip `LAYER_MAP_STRICT=1`; the script must distinguish "unmapped, expected (vendor-drawn)" from "unmapped, populated, unexplained" — never a bare unmapped count |
| 3 | `erc` | OVERALL line parsed by a real `check:` (not "exit code is the verdict"); PARTIAL treated as fail, not folded into OK; VDDIO/VSSIO labels landed | New `erc_census.py`-style script grepping `OVERALL`, asserting `OK` exactly, `check_proof` covering OK/PARTIAL/error-exit fixtures |
| 4 | `bnd` | Rule-by-rule diff against IMEC's report closed (doc 50 already does this); LOGO AP-only fix wired into the real submission stream and re-verified post full-merge | Census-style script over the BND summary, cell-scoped waiver for any residual known-artefact, same stale/drift self-test as `drc` |

`padring-gds` goes first — cheapest, license-free, and already validated against the exact
failing IMEC GDS, closest to `drc`'s discipline today. `bnd` goes last — its promotion depends
on external re-validation (full-merge LOGO re-check) not yet in our control.

## 2. New gates needed

**Padring orientation check — do this first.** `check_padring_gds.py` already parses
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

**Regression fixture for the corner-rotation bug.** `ci/fixtures/padring-orientation/fail-corner-180`,
built from the pre-fix `.io` values (R90/R180/R270/R0), wired into `check_proof.must_fail` —
the same "prove the gate can fail" discipline doc 45 §3.8 names as a real, named deficiency for
`cdc`/`lvs-preflight`.

**CSR / 157-category ratchet.** Not a fix — a `DRC_DESIGN_BUDGET`-style budget file recording
today's counts (the ~800/644/96 unattributed CSR hits, the 157 new rule categories, each
capped/uncapped noted) that a `drc_census`-sibling refuses to let grow silently. `report`-gated
until root-caused; `block`-gated once the count has a verified ceiling and no unexplained
residue.

**PVDD2POC cardinality check.** A structural netlist check on `nanosoc_eth_chiplet_pads.v`
asserting the confirmed-correct instance count for `PVDD2POC_G` (today: 4, all on VDDIO) —
cheap, license-free, `report`-gated until the broker/vendor confirms "one per ring" semantics.
**Do not** silently convert the other three to `PVDD2DGZ_G` without that confirmation.

## 3. Sequencing

**Today, no Calibre seat needed:** orientation-table extension to `check_padring_gds.py` +
regression fixture; PVDD2POC netlist-count check; CSR/157-category budget-ratchet skeleton.

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
| Padringcheck: orientation | **No, until this plan** | free — see §2 above |
| Padringcheck: bond-attach warnings | No | free but low-value (needs a bond map that doesn't exist yet) |
| Padringcheck: power-domain cardinality | No | needs-vendor-data to confirm the fix; the check itself is free to add once confirmed |

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

This page holds the mechanics. `CONVERGENCE_PLAN_2026-08-18.md` §9 carries the retrospective
(what should have been caught) and links here for the forward plan.
