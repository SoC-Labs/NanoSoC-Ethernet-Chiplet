# `verif/` — verification environments for the ethernet chiplet

One directory per environment. Each is self-contained and each answers a
different question; none is a superset of another.

Everything below assumes the environment has been sourced first:

```sh
source set_env.sh          # from the repo root
```

| environment | what it proves | how to run | runtime |
|---|---|---|---|
| [`lint/`](lint/) | Verilator structural lint over the three wrapper modules (comb loops, latches, width and undriven-net faults) | `make lint` (repo root), or `verif/lint/run.sh` | seconds |
| [`lint/full/`](lint/full/) | Verilator **and** Cadence HAL over the whole ~590-file design, zoned by who owns each file, ratcheted against a recorded baseline | `verif/lint/full/run.sh` | long |
| [`cdc/`](cdc/) | Cadence HAL structural clock-domain-crossing pass over the integrated top | `make cdc` | ~25 min |
| [`elab_strict/`](elab_strict/) | the synthesis blockers a simulator hides — above all a same-clock procedural multi-driver | `make elab-strict` | ~25 min |
| [`chiplet_d2d_decode/`](chiplet_d2d_decode/) | the D2D sub-decoder: TX-aperture wedge gate, and the peer-aperture HREADY loop break | `make -C verif/chiplet_d2d_decode` | seconds |
| [`bscan/`](bscan/) | the IEEE 1149.1 boundary-scan register and TAP against the pad table | `make bscan-sim`, or `verif/bscan/run.sh` | ~6 s |
| [`g2_peer_aperture/`](g2_peer_aperture/) | a transaction crossing ONE TideLink pair: `addr[31:24]` rewritten by the CAM and re-presented on the far side | `make -C verif/g2_peer_aperture sim` | minutes |
| [`g2_soc_pair/`](g2_soc_pair/) | the same experiment between TWO real `nanosoc_eth_chiplet` dies, into die B's real SRAM | `make -C verif/g2_soc_pair sim` | longest |

`scripts/regress.sh` (`make regress`) chains the simulation environments in
that order. `--quick` skips `g2_soc_pair`, the long pole.

## Reading a result

Several of these gates are structured to fail when they did NOT measure
anything, rather than reporting the resulting zero as clean. A skipped pass, a
tool that stopped before it reached the design, a truncated log and an absent
baseline are all failures here. If a run prints "NOT MEASURED", that is not a
pass with a caveat — nothing was checked.

Findings and triage live in `docs/`: `LINT_FINDINGS.md`, `CDC_FINDINGS.md`,
`ELAB_STRICT_FINDINGS.md`, `D2D_HREADY_LOOP.md`.
