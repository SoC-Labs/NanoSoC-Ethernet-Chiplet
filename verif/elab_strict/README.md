# `verif/elab_strict` — strict ASIC-elaboration gate

```sh
source ../../set_env.sh
./run.sh                 # or: make elab-strict   (repo root)   ~25 min
```

Needs an Xcelium/HAL licence.

## Why it exists

`make elab` (VCS) links a netlist; `make lint` (Verilator) catches
combinational loops, latches and width faults. Neither catches a **same-clock
procedural multi-driver** — one register assigned from two `always` blocks. A
simulator resolves it by scheduling, and Verilator's MULTIDRIVEN only fires
across *different* clocks, so both stay silent. A synthesis front end must build
one flip-flop and rejects it, which blocks ASIC synthesis.

This pass runs `xrun -hal` over the dedup'd integration and gates on
`*E,MLTDRV` in AUTHORED RTL. Vendor IP (Arm CMSDK, OpenCores MAC, XHB500, memory
models) is reported but not gated — a multi-driver there is an IP-owner
escalation, not a build break here. Triage: `docs/ELAB_STRICT_FINDINGS.md`.

## Two traps this script guards

* **`-BB_NONSYNTH` is not optional.** Without it, halsynth stops on
  synthesizability errors *before* halstruct runs, MLTDRV never executes, and
  the gate reports a clean design it never checked.
* **A killed run looks clean.** `ELAB_STRICT_TIMEOUT` must be set with real
  headroom, not to the last measured runtime. A `timeout` kill leaves no abort
  marker and plenty of `halstruct:` output, so the script checks the exit status
  and the rule-tally block explicitly. `MLTDRV=0` from a truncated log means NOT
  MEASURED, not clean.
