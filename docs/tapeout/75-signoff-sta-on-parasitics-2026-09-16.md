# Signoff STA on this flow's output, on parasitics

    measured 2026-09-16, ASIC/sta/work/vt7higheco2-20260914 (re-run on the final script, 14:56-15:15)
    database build/vt7higheco2-20260914/work/nanosoc_eth_chiplet_pads_eco (the ECO stage's output)
    status   the stage runs, extracts, enumerates, grades, and its gate is `block`; it FAILS this run on hold, correctly

## 1. What ran

Tempus 21.11 through `make sta RUN_TAG=vt7higheco2-20260914` (new `ASIC/sta.mk`,
included by the project Makefile; `IN_DB` defaults to the ECO database when one
exists). Extraction is explicit and recorded: engine `post_route`, effort
`signoff`, the tech pack's QRC layer map, standalone Quantus, 250,887 nets,
three SPEFs of 371 MB (worst / best / rc_best_125C; typical inactive), and the
fallback message counts IMPEXT-3518 / EXTSNZ-127 / IMPEXT-5016 all 0 — counted on
severity-prefixed lines only, since Tempus echoes the script's own source. One
licence message (IMPLIC-90, base licence for floorplan-data load) is counted and
recorded; the design loaded fully and it is not gated.

Correction to the earlier record: rc4 WAS timed on parasitics on 29 August
(three SPEFs of 323 MB, `step.extract_parasitics = ok`); the directory
`rc4probe-untested` in this tree is a wire-free probe and is not that run.

## 2. The numbers, beside rc4's

| | rc4 evidence run (2026-08-29) | vt7higheco2 (this run) |
|---|---|---|
| setup View:ALL | +0.015 / 0.000 / 0 | **+0.050 / 0.000 / 0** |
| hold View:ALL | +0.003 / 0.000 / 0 | **−0.022 / −0.037 / 2** |
| default_analysis_view_hold | +0.003 | +0.056 (worst of the two watched endpoints) |
| av_ltfix_libset_hold | +0.003 | +0.055 |
| av_ml_libset_hold | +0.006 | **−0.022, −0.015** |
| clocks | 104 | 104 |
| untested, setup side | 57,955 | 57,983 (No endpoint clock 43,200; const 9,670; False Path 5,113) |
| untested, hold side | (not enumerated) | 8,472 (const 3,359; False Path 5,113) |

The two hold endpoints are the multicore and eth_ss bus-matrix input-stage
registers, exactly as opt_signoff's own signoff view read them. They are room,
not flow: rc4's holdfix settings applied as a second pass on this database
(target slack 0.010, margin 0.020, legal-only, non-core sites allowed) inserted
one buffer and left "15 net(s): no legal location". rc4 closed its hold with
2,245 repeaters in a database that had room; it never had these two exposed.

## 3. The gate

`ci/signoff.yaml` sta-signoff is `gate: block`. `sta_gate.py` HARD-fails a run
without extraction evidence (`EXTRACTION_UNMEASURED`, `EXTRACT_FALLBACK`,
`EXTRACT_QRC_FAILED`, `EXTRACT_LAYER_UNMAPPED`, `EXTRACT_EFFORT` ≠ signoff, SPEF
below `require_spef_min_bytes`), enumerates untested checks by Tempus's Reason
text on both sides and budgets them per reason (`untested_budget_by_reason`:
"No endpoint clock" null — every PulseWidth arc on a CDN/SDN/TE pin driven by a
reset-synchroniser data net, CDN 41,898 + SDN 1,391 + TE 3,007 on this netlist,
uncomputable; "const" null — tied-off endpoints; "False Path" 0, the
`set_clock_groups -asynchronous` exposure at constraints.sdc:706, reported as
"FAIL (report-only)" on every run and blocking none). A reason absent from the
map fails; a policy key the gate cannot place fails. `sta_binding.py` accepts an
ECO database only through `eco_manifest.txt`'s `parent_manifest` row resolving
to a finished route; nothing is forged into an ECO tree.

On this run: `BINDING: PASS`, `GATE: FAIL [HOLD_FEP] hold FEP 2 > budget 0`. That
is the parity gap, and the gate says so. The `sta-hold-coverage` gap stanza is
deleted: its own probe fires on this run.

Fixtures: 13, cut from this run by `ci/fixtures/sta-signoff/regen.py`, one code
each, with the single declared edit described in `PROVENANCE.md`.
`signoff.py prove sta-signoff`: 13 cases, 0 problems. `signoff.py lint`: clean.
`sta_gate.py --selftest` 54 / 0, `sta_extract_evidence.py` 20 / 0,
`sta_binding.py` 20 / 0, `regen.py --selftest` 5 / 0. Full `signoff.py prove`
over every stage: 194 cases, 0 problems.

The root defect this closes is not the stale numbers. Nothing tied a
`sta_policy.json` edit to regenerating the fixtures, so a policy tightened on
29 August met fixtures cut on the 26th and `prove` stayed green on four of the
five, because a rotted must-fail still fails — for the wrong reason. A
generator that cuts from a real run and refuses an undeclared edit removes the
class: there is no hand-maintained copy left to drift.

The block flip is sound only on a tree whose pinned database defines all three
hold views; the frozen branch's rc1 database defines one.
