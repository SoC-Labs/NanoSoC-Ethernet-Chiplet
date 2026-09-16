# sta-signoff fixtures — provenance

Cut by `regen.py` on 2026-09-16 from a REAL run: `ASIC/sta/work/vt7higheco2-20260914`
(Tempus 21.11 on `build/vt7higheco2-20260914/work/nanosoc_eth_chiplet_pads_eco`, the
ECO stage's output; extraction standalone Quantus at signoff effort, three SPEFs of
371 MB, 250,887 nets, fallback message counts 0; 104 clocks; one setup and three hold
views). Paths are scrubbed to `/builds/nanosoc-ethernet-chiplet`. `expectations.json`
records each fixture's expected codes; `regen.py --verify` grades every fixture with
both graders and checks the EXACT code set.

## The one field the pass fixture does not take from its run — declared

`pass/.../timing_summary_hold.rpt`, the hold `View : ALL` row:
`-0.022  -0.037  2` (the run) → `0.056  0.000  0` (the run's own worst PASSING hold
view, `default_analysis_view_hold`). Recorded in `expectations.json` under
`pass_edits`. Why: no signoff STA on this branch passes yet. The best ECO output leaves
two hold endpoints in the fast-hot view (`av_ml_libset_hold`: −0.022 and −0.015, the
multicore and eth_ss bus-matrix input-stage registers), which is the parity gap the
flow is closing, and the gate's `HOLD_FEP` arm fails the real run for exactly that
reason — as it should. A must-pass cut verbatim would be a must-fail. The must-fail
set descends from the edited pass and still yields one code each. **Replace this
fixture with an unedited cut the day a run passes.**

The previous (2026-08-26) fixtures were hand-cut: the pass fixture's
`analysis_coverage.rpt` had its untested column zeroed and three rows deleted, a state
no real Tempus run of this design can reproduce, and the must-fails carried up to four
codes each. Both defects are gone.

## Exactly one code per must-fail (from `regen.py --verify`, 2026-09-16)

| fixture | binding | gate |
|---|---|---|
| pass | — | — |
| fail-cap-table-fallback | — | EXTRACT_FALLBACK |
| fail-clock-count | — | CLOCK_COUNT |
| fail-eco-parent-missing | ECO_PARENT_MISSING | (not reached) |
| fail-effort-not-signoff | — | EXTRACT_EFFORT |
| fail-no-extraction | — | EXTRACTION_UNMEASURED |
| fail-no-result | STA_NOT_RUN | (not reached) |
| fail-spef-too-small | — | SPEF_TOO_SMALL |
| fail-unfinished | RUN_INCOMPLETE | RUN_INCOMPLETE |
| fail-untested-checks | — | UNTESTED_REASONS_MISSING |
| fail-view-missing | — | VIEW_ABSENT |
| fail-violating | — | SETUP_FEP |
| fail-wrong-build | WRONG_BUILD | — |

Binding-arm fixtures never reach `sta_gate.py` (the composite check runs
`sta_binding.py || exit 1`); their gate column is therefore "not reached", not
"clean". No "over budget" must-fail exists because the shipped policy has no BLOCKING
ceiling (`False Path` is ceiling 0 but report-only; the null classes are unlimited);
that arm is proven by `sta_gate.py --selftest`.

## Notes for the merge with feat/padring-boundary-scan

- That branch carries uncommitted/committed edits to the same fixture manifests
  (clock_count 52→104, three hold views). These fixtures supersede them: same policy,
  cut from a run rather than edited by hand.
- `untested_budget_by_reason` is the same key and semantics on both branches
  (`"No endpoint clock": null, "const": null, "False Path": 0`); ours adds
  `untested_budget_report_only: ["False Path"]`, alias canonicalisation of policy keys,
  and `UNTESTED_POLICY_KEY_UNKNOWN`.
- SPEF sizes differ from rc4's evidence run (371 MB vs 323 MB) because this is a
  different, ECO'd database with 267 k nets against 225 k, not an extraction difference.
- The untested census is symmetric on this run: setup 5,113 False Path = Setup 2,119 +
  Recovery 2,994; hold 5,113 = Hold 2,119 + Removal 2,994. An earlier run whose hold
  enumeration was scoped `-check_type hold` showed 2,119 only; the final script reads
  `analysis_coverage_early_all.rpt` and carries Removal.
