# Change units — one RTL fix, one manifest, one proof

A **change unit (CU)** is the smallest thing that can be proven and reverted on
its own: one defect, one branch, one commit, one verdict. The manifests here are
the executable form of `docs/verification/LINT_REMEDIATION_PLAN.md`.

The rule that makes this work: **a CU declares what it expects to happen before
it is applied.** A fix that claims to be behaviour-preserving and then fails
equivalence is not a surprise to be investigated — it is a failed gate, and the
gate says so without anyone having to judge.

## Schema

```yaml
id:      A2-ptp-servo-lock-compare      # also the branch name: fix/lint/<id>
title:   one line, what is wrong
area:    tidelink | tidechart | soc | generated | integration | asic-flow
risk:    behaviour-preserving | behaviour-changing | flow-only
files:   [paths]                        # a CU touching >3 files needs a reason

defect: |                               # what is wrong, with the evidence
change: |                               # the exact edit

expect:
  lec: equivalent | non-equivalent | n/a
  # ^ THE load-bearing field. behaviour-preserving => equivalent, and a
  #   non-equivalent result is a hard stop. behaviour-changing => NON-equivalent,
  #   and an "equivalent" result means the fix did nothing.
  lint_delta: {CODE: -N}                # per-code change in the authored report
  netlist_delta: none | expected

gates:
  unit:        [make targets]           # owning cocotb/UVM env
  integration: [make targets]
  fpga:        none | kr260-eth-chiplet # hardware run required?

new_test:  required | none
test_spec: |                            # if required: what must the test prove
```

## Why `expect.lec` is the spine

Most of this backlog is width edits. The failure mode of a 78-edit mechanical
batch is a typo in edit 54 — which a directed test samples for and equivalence
checking proves against. So:

| risk | expect.lec | a violation means |
|---|---|---|
| `behaviour-preserving` | `equivalent` | **you changed silicon behaviour without meaning to** — hard stop |
| `behaviour-changing` | `non-equivalent` | the edit was a no-op; the finding was cosmetic; re-classify |
| `flow-only` | `n/a` | no RTL changed |

On a genuine non-equivalence, Conformal's `analyze_nonequivalent -source_diagnosis`
names the diverging input cone. **That output is the specification for the
directed test** — you do not have to invent one.

## The width rule

> **Always widen the narrow side. Never narrow the wide side.**

`tl_addr_trans_regs.sv:168-172` is the live trap: `reg_word_addr` is 10 bits and
the RHS are unsized parameters, so zero-extension makes the comparison correct.
"Fixing" it by sizing the RHS down truncates `RULE_BASE_WORD + NUM_RULES` and
breaks the upper bound of the rule window. LEC catches a violation of this rule
mechanically; review does not.

## Adding a CU

1. Copy an existing manifest. One defect per file.
2. Fill `expect` **before** you write the code — that is the point.
3. `verif/lint/full/prove_fix.sh fixes/<id>.yaml` runs the ladder.

## Ordering

`prove_fix.sh` does not enforce order; the workflow does. Two constraints:

- **Nothing runs before `run_lec.sh` has an `rtl` mode** (plan step 2). Without
  it the only evidence for a mechanical batch is a sampling test.
- **`fpga: kr260-eth-chiplet` CUs are serialised** — two boards, one lease.
