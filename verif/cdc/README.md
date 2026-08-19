# `verif/cdc` — structural clock-domain-crossing pass

Cadence HAL, driven through `xrun -hal`, over the whole integrated
`nanosoc_eth_chiplet`.

```sh
source ../../set_env.sh
./run.sh                 # or: make cdc   (repo root)   ~25 min
```

Needs an Xcelium/HAL licence. Output goes to `build/` (or `$ASIC_LANE_OUT`, so
this can run alongside the backend instead of serialising against it).

## What it is, and what it is not

`make elab` proves the netlist links and `make lint` finds structural faults in
the wrapper. Neither analyses clock-domain crossings across the integration —
the `sys_hclk` ↔ `user_ref_clk` / `pad_clk_rx` boundaries where a missing
synchroniser bites on silicon.

This is a **starting point** for the physical team's CDC signoff, not a clean
bill. The full integration pulls in the SoC's and TideLink's own internal
crossings, so most findings are pre-existing in the components; triage to the
crossings at the integration boundary. See `docs/CDC_FINDINGS.md`.

**A zero from this flow is not automatically clean.** `xrun -hal` takes no SDC,
so HAL cannot know which clocks are mutually asynchronous, and the whole
synchroniser rule class (`CLKDMN`, `CMBCDC`, `INSYNC`, `FLSYNC`, `RSTSYN`,
`RSTSCB`, ...) reports zero BY CONSTRUCTION. The script prints those separately
as NOT MEASURED. The real unsynchronised-crossing signoff needs
`constraints/nanosoc_eth_chiplet_cdc.sdc` driven into a dedicated CDC tool — the
SpyGlass setup for that lives in the repo-root `cdc/` directory.
