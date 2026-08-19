# Lint waivers — the arguments, and the reader that holds them to the design

`docs/verification/LINT_WAIVER_INVENTORY.md` is the account of every finding. This directory
is the machine-checkable half of it.

| file | what |
|---|---|
| `verilator.yaml` | Verilator site waivers, class dispositions, open items |
| `hal.yaml` | HAL site waivers and open items |
| `apply_waivers.py` | reads either against a findings JSON, and gates |

```sh
python3 verif/lint/full/waivers/apply_waivers.py --tool verilator \
        --findings build/lint/full/verilator/findings.json
python3 verif/lint/full/waivers/apply_waivers.py --tool hal \
        --findings build/lint/full/hal/hal_findings.json
```

Exit `0` clean, `1` accounting failure, `2` accounting sound with open findings.

## What a waiver has to carry

`id`, `rule`, `expect`, `why`, `invalidated_by`, `decided_by`, `evidence` — the
reader refuses an entry missing any of them, because an entry without them is a
suppression wearing a waiver's clothes. Selection is by any of `file` (glob),
`zone`, `lines`, `subject` / `not_subject` (the net or pin the message names).

`subject` is **exact unless the pattern actually wildcards**: net names carry bit
selects (`cc_periph_irq_w[31:11]`) and `fnmatch` would read `[31:11]` as a
character class, so a pattern copied from the report would match nothing. That
is the silent-orphan failure this directory exists to prevent.

## The five guards

| | |
|---|---|
| **G1** | every waiver matches **exactly** the number it declares — 0 and "more than expected" both fail |
| **G2** | no waiver may target a never-waive rule, or a pin finding whose direction is not `output` |
| **G3** | the class tables in `verilator_lint.py` and `check_baseline.py` agree, and every code they suppress has a written `class_disposition` |
| **G4** | every authored DESIGN finding is waived or recorded open — nothing by omission |
| **G5** | every open item still fires; one that stopped is good news that the record has to be updated |

## Not wired into the runner

`run.sh` does not call this yet — see `docs/verification/LINT_WAIVER_INVENTORY.md` §8 for the
three-line wiring request and why it was left to the runner's owner. Until then
this is an auditor, not a gate.
