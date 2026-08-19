# `verif/lint` — Verilator structural lint over the wrapper RTL

```sh
source ../../set_env.sh
./run.sh                 # or: make lint   (repo root)
```

Four passes, in this order:

1. **LEAF** — `chiplet_d2d_decode`, standalone.
2. **SHIM** — `tidechart_shim` against a generated `tidechart_controller` blackbox.
3. **WRAPPER** — `nanosoc_eth_chiplet` with the real decode and shim, and blackboxes for the SoC, TideLink, TideChart and `cmsdk_ahb_to_apb`.
4. **SANITY** — `hready_loop_probe.sv`, which proves the lint can still detect the HREADY combinational cycle it exists to catch.

Only the three integration modules are ours; the vendor hierarchies are
blackboxed by `gen_bbox.py` so the wrapper's own nets are analysed in
isolation. Triage and waivers: `docs/LINT_FINDINGS.md`.

## A skipped pass is a failure

Pass 3 needs the GENERATED SoC top (`nanosoc-multicore-system/build_soc/`), so
on a fresh clone it has nothing to lint. That is treated as a FAILURE, not a
pass, because a pass that did not run measured nothing. `LINT_ALLOW_SKIP=1`
downgrades it to a warning and says so in the verdict line.

One run at a time per working tree: the blackbox stubs and per-pass logs live at
fixed paths under `build/lint/`, which CI reads by name. The script takes an
`flock` so concurrent runs serialise rather than corrupting each other.

The whole-design version of this pass — Verilator plus Cadence HAL over all
~590 files — is [`full/`](full/).
