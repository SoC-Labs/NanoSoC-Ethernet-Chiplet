# `evidence-report` stage fixtures

The stage's `check:` grades a report at a FIXED path
(`build/evidence/pinfix-20260824/evidence_report.json`), so each arm overlays a
report at exactly that path inside the prove sandbox.

| arm | what it is | why it must fail |
|---|---|---|
| `pass` | four rows, every one measured, SIGNED OFF | it must NOT fail |
| `fail-a-gate` | one FAIL row | the ordinary red |
| `fail-not-measured` | no FAIL, one NOT-MEASURED | **NOT-MEASURED is a verdict, not a missing PASS** |
| `vacuous-no-gates` | says SIGNED OFF over ZERO gate rows | green and empty — the shape a naive grader passes |
| `absent` | no report at all | an absent report is not a clean one |

The last two are the ones worth having. This project has shipped at least six
zeros that measured nothing, and a gate on a report must not become the
seventh.

`absent` uses `.__absent__` because the prove sandbox symlinks the real repo
in: a fixture cannot express absence by omission. `build/` is gitignored, so
these arms are the only checkable copies of these shapes.
