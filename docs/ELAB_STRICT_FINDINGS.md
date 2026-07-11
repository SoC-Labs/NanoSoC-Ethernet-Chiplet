# Strict ASIC-elaboration gate — `make elab-strict`

Catches the class of synthesis blocker that a *simulator* hides but a *synthesis
front-end* (Synopsys `fc_shell` / Cadence Genus) rejects — above all a same-clock
**procedural multi-driver**. Run `verif/elab_strict/run.sh` (or `make elab-strict`).

## The hole this closes

Our gate stack had a blind spot, demonstrated on real RTL:

| Gate | Catches | Misses the multi-driver? |
|---|---|---|
| `make elab` (VCS) | linking / connectivity | **yes** — a simulator resolves two procedural drivers by scheduling (last write wins) |
| `make lint` (Verilator) | comb loops, latches, width, undriven **in our wrapper** | **yes** — Verilator's `MULTIDRIVEN` fires only across *different* clocks, and the submodules are blackboxed |
| `make regress` (cocotb) | functional behaviour | **yes** — same scheduling tolerance |
| **`fc_shell` / Genus** | — | **no** — must build ONE flip-flop; rejects it as a multi-driver net (ELAB), blocking synthesis |

A register assigned from **two `always` blocks** is legal to a simulator and to
Verilator (same clock) but is un-synthesisable. Nothing we ran before would have
stopped it reaching the physical team.

**This bit us for real.** TideChart's `tidechart_link_state_agent` drove
`heartbeat_pending_r` / `change_pending_r` / `trigger_pending_r` from two blocks
(SET in the pending block, CLEARED in the TX-FSM block). VCS + Verilator passed
it; only `fc_shell` strict elaboration caught it. It was fixed upstream
(`736c139`) and pulled in via the tidechart pointer roll (`b1b584e`) — and this
gate now guards against the next one.

## The tool, and why this one

`xrun -hal` — Xcelium's parser (which, unlike standalone `hal` or Genus
`read_hdl -sv`, actually parses this design — same reason the CDC pass uses it)
plus HAL's structural ruleset. The load-bearing rule:

```
*E,MLTDRV   Signal/register '<name>' has multiple drivers.
              Driver for '<name>' @<lineA>
              Driver for '<name>' @<lineB>
```

**Mutation-proven** against the known tidechart bug:

| Module version | `*E,MLTDRV` count |
|---|---|
| pre-fix `tidechart_link_state_agent` (`b5102b2`) | **3** (`heartbeat`/`change`/`trigger_pending_r`) |
| fixed (`34ffcdb`) | **0** |

Plain `xrun -elaborate` (simulator) reports **0** on the buggy module — confirming
this is a HAL-structural catch, not a simulator one.

## The gate

`make elab-strict` runs `xrun -hal` over the whole dedup'd integration (the same
tool-independent flist the CDC pass builds) and:

- **FAILS** if any `*E,MLTDRV` lands in **authored RTL** — our wrapper
  (`src/rtl/`), the TideChart / TideLink SoCLabs `src/rtl`, and the SoC glue
  (`build_soc/rtl/`).
- **Reports but does not gate** multi-drivers in **vendor / pre-verified IP** (Arm
  CMSDK, OpenCores MAC, XHB500, memory models) — it is not ours to edit; a
  multi-driver there is an IP-owner escalation, not a local build break.
- Also tallies other structural findings (mixed-type vector drivers `DFDRVS`,
  latch/undriven classes) for triage.

Fix for any authored MLTDRV: **drive the register from exactly one `always`
block** (compute the set/clear conditions as `wire`s and apply them in a single
block — the pattern the tidechart fix used).

## Current findings (full-integration sweep, tidechart @34ffcdb)

**`MLTDRV` = 0 across the whole elaborated design — no multiple-driver nets
anywhere.** The gate PASSES; the design is fc_shell-multi-driver-clean, and the
tidechart fix is confirmed at the integration level. `make elab-strict` → OK.

The sweep also surfaced synthesizability findings — none a hard blocker, all
triaged:

| Class | Count | Where | Verdict |
|---|---|---|---|
| `*E,MLTDRV` multiple driver | **0** | — | **clean (the gate's job)** |
| `*W,LATINF` inferred latch | 1 | Arm Cortex-M0+ PMU `cm0p_pmu_acg.v` (clock-gate cell) | vendor IP, intentional latch pattern — waive |
| `*E,SIZMIS` size mismatch | 13 | 10 × TideLink `i2c_master_axil` (AXI-Stream sidebands `s_axis_tkeep/tid/tdest`); 3 × `ethernet_ss_ahb_rmii` (`sel` mux width) | benign width notes on third-party i2c (management channel, not the D2D data path) + generated SoC glue; both elaborate + regress green — review, not a blocker |
| `*E,RTLINI` decl initializer | ~104 | authored + generated | synth ignores declaration inits (relies on reset) — hygiene; verify none is relied on without a reset path |
| `*E,GLTASR` async set/reset | 5 | authored | reset-glitch class — review at signoff |
| `*E,CBPAHI` comb path across hier | ~40.9k | pervasive | halstruct STYLE noise, waivable — see `docs/CDC_FINDINGS.md` |

The gate deliberately hard-fails only on `MLTDRV` (the proven un-synthesisable
blocker) in authored RTL; the rest are reported for owner triage. `SIZMIS` on
AXI-Stream sidebands is the classic unused-sideband pattern; the `i2c_master_axil`
IP is TideLink's management channel, off the validated data path.

## Reproduce

```sh
source set_env.sh
make elab-strict          # ~25 min: full elaboration + HAL structural
# findings: verif/elab_strict/build/xrun_hal.log
```

Run it before handing RTL to synthesis, and after any submodule pointer roll — a
multi-driver can arrive from a dependency, exactly as this one did.
