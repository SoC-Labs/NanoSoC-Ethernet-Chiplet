# must_pass — the real gate, unmodified

This fixture supplies NO file that shadows the repository. That is the whole
point of it: the positive control for `ir-drop-selftest` has to be the real
`rail_gate.py` running its real battery, because a positive control built out
of a stub would only prove that the check can read a stub.

The three `fail-*` siblings each shadow `ASIC/genus-innovus/rail/rail_gate.py`
with a stub that prints a DIFFERENT tally, so that each clause of the check is
proved separately rather than all of them by one mutation:

| fixture                      | tally printed          | clause it proves         |
|------------------------------|------------------------|--------------------------|
| fail-mutation-escaped        | `19 passed, 1 failed`  | failures are not ignored |
| fail-battery-cut-down        | `3 passed, 0 failed`   | the case COUNT is checked|
| fail-positive-control-missing| `20 passed, 0 failed`  | a gate that rejects      |
|                              | but no baseline PASS   | everything is not a gate |

The last one is the subtle one and it is the reason the check does not simply
trust the tally: a battery whose every case expects FAIL passes its own tally
while proving only that the gate says no to everything.
