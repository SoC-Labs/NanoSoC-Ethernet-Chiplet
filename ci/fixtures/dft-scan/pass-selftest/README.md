# must_pass — the real detector, unmodified

This fixture supplies NO file that shadows the repository, and that is the whole
point of it. The positive control for `dft-icg-selftest` has to be the real
`scripts/ci/dft_icg_census.py` running its real five-case battery, because a
positive control built out of a stub would only prove that the check can read a
stub.

Its four `fail-selftest-*` siblings each shadow that script with a stub printing
the REAL transcript with one mutation, so that each clause of the check is
proved separately rather than all of them at once:

| fixture                   | mutation                                    | clause it proves            |
|---------------------------|---------------------------------------------|-----------------------------|
| fail-selftest-exit0-liar  | two cases fail, and it still exits 0        | status and text must agree  |
| fail-selftest-shrunk      | 5 cases become 3, summary agrees            | the case COUNT is checked   |
| fail-selftest-no-red      | 5 cases, none of them negative controls     | a gate that never says no   |
| fail-selftest-hollow      | the summary line and no case transcript     | a tally is not a result     |

`fail-selftest-exit0-liar` is the load-bearing one. It is the shape several
tools in this flow actually have — a nonzero finding reported over a zero exit
status — and a stage that read `$?` alone would record it as a clean run.
