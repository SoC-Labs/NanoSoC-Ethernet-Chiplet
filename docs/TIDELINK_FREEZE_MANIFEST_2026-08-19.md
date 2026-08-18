# TideLink integration freeze — 2026-08-19

**Status: DRAFT.** Pending the final re-pin and a re-gate on the merged state.
Every claim below was checked with a command; where a number came from a peer
session rather than a run of my own, it says so.

This document is the freeze. A manifest that lists only what is *in* a release
misleads whoever picks it up, so the second half — what is broken, unmeasured, or
untested — is the more important half. Read it before quoting anything from this
tree.

---

## 1. What is in the freeze

| Fix | Commit | Evidence |
|---|---|---|
| N1 read-backstop | `e008c58` | ancestor of the pin; was the tapeout blocker |
| PHY framing (TL-001 drop) | `2c249ec` | ancestor of the pin |
| TL-037 — `ahb_sub` terminal-timeout dead gate | on `origin/main` | landed by the TideLink session; mutation-tested, full-regression-clean, HW-validated 5000/5000 byte-exact soak (their evidence, not mine) |
| N3 / Hazard-4 — phantom `read_complete` advancing `read_ptr` | on `origin/main` | as above |
| Peer-write burst corruption | `181632f` (chiplet) + `253b951c` (tidelink port) | pair bench 14/14 on a clean rebuild; bench verdict flips to "each burst beat delivered its OWN payload into die B's real SRAM" |
| Bufferable/EWR guard | `0ec54af` | landed after the stale-binary diagnosis; pair bench 14/14 with fix **and** guard together |
| Hazard 3 / N2 — AUTO_ANCHOR idle-qualified force path | `e6aaa82f` | no regression in the general suite |

### Gate results on the pinned state

- `verif/g2_soc_pair`: **14 PASS / 0 FAIL**, clean rebuild, fresh compile confirmed.
- `make sim_gate`: **52 suites PASS**, plus 3 known-defect sentinels at `XFAIL`.

`XFAIL` means *the defect is present and unchanged*. The gate says so itself. It
is not a pass and must not be reported as one.

---

## 2. What is NOT fixed, and ships broken

### The D2D write-wedge is diagnosed but unfixed

The root cause is characterised: the AW-node's `a2l_fc_replay` window has **no
timeout**, so `app_ready` — and therefore `s_axi_awready` — dies permanently once
the peer's ACK stream stops advancing. Confirmed dynamically in simulation:
freezing the ACK pointer walks the depth-8 FIFO to full, `a2l_full` sets,
`app_ready` drops, and the next write wedges — held for 26,001 observed cycles
with zero self-clear.

**It is silicon-unconfirmed.** The instrumented bitstream and ILA are built and
proven (166 probes, timing met, trigger verified not to false-fire on healthy
traffic), but the wedge could not be induced on the bare-pair FPGA: PS stores
serialise to one outstanding write, there is no clean way to silence the peer,
and no DMA path exists on that target. The DMA inducer built for it never got past
its own self-test.

**Recovery is JTAG power-on reset.** That is a workaround, not a fix. No timeout
or recovery logic exists anywhere in the tree.

### The bufferable peer-write path is now guarded, but was nearly not

Worth recording because the failure mode was deceptive: the guard was first landed
*with* the burst fix, scored 8/14, and the primary case failed byte-identically to
the original bug — so it read as "the fix does not work." It was neither. A stale
simulator binary in `build/elab/csrc`, which the usual `rm -rf sim_build*` does not
reach, meant the fix was never actually compiled into that run. See CONTRIBUTING §4.

### The timing numbers are not trustworthy

Three defects in the synthesis/signoff flow, all diagnosed, none fixed, none of
them RTL:

- no `set_case_analysis` on the DFT scan mux, so `scan_clk` out-builds `hclk`'s own
  clock tree;
- a scenario-scoping bug leaves the slow signoff corner with **zero** clock
  uncertainty;
- an SDC read aborts silently mid-file and drops every constraint after it — on
  every build to date.

Do not quote timing closure from this freeze without re-running signoff.

### The link has never had a bit-error-rate number

F19 / PHY-BIST: no BER figure has ever existed for this IP. Not a regression —
simply never measured.

### Other open items

- **Hazard 1** — simulation-clean, never hardware-validated.
- **Hazard 3** — landed, with a disclosed limitation: its qualifying signal can
  read 0 under severe skew, making the beacon inert. That fails *closed* (no
  beacon rather than a deleted word), which is why it was landed, but the hardware
  campaign is still owed.
- **FCSM `_GEN_115`** — two worktrees disagree, unreconciled. Deprioritised
  because the wedge hypothesis moved away from that mechanism; still open.

---

## 3. Known coverage gaps

- **No concurrent-stress test for the combined fix set** at the chiplet level. The
  one candidate, `test_v2_bidir_throughput`, does not fill it: it is not wired into
  `sim_gate`, and it drives `tidelink_top` *without* the chiplet wrapper — the same
  structural blind spot that hid the burst-corruption bug from
  `g2_peer_aperture` for weeks. The fixes are structurally independent (N3 is the
  RX read-pointer/credit path; the burst fix is TX W-consumption; different files,
  different directions, no shared registers), so this is a real gap rather than a
  suspected bug.
- **The peer-aperture bench cannot see capture-register bugs**, by construction —
  it wires `tidelink_top.ahb_sub` directly and never instantiates the chiplet, so
  it sits downstream of the capture. Do not read a green there as covering the
  chiplet's peer-write path.

---

## 4. Reproducing the gates

`sim_gate` has two traps that each produce a confident, wrong answer.

```bash
cd <chiplet>/tidelink
source ./set_env.sh                       # MANDATORY
export CHIPLET_HOME=<chiplet>
export ETH_SS_HOME=<...>/ethernet-subsystem-ahb
export TIDECHART_HOME=<chiplet>/tidechart # the SUBMODULE, not ~/SoCLabs/tidechart
make sim_gate                             # then READ THE TABLE
```

1. **Without `set_env.sh`**, `CMSDK_FPGA_SRAM_V` is empty, the flist carries the
   literal unexpanded `${CMSDK_FPGA_SRAM_V}`, and ~40 suites fail in 2–7 s each
   without reading any RTL. Forty suites failing uniformly in seconds is an
   environment fault, never a regression.
2. **The exit code lies.** Child makes run `SIM_GATE_NONFATAL=1`, so `make
   sim_gate` returned **0** on a run whose own summary said `RESULT: FAILURES
   DETECTED`. Never gate on `$?`; parse the per-suite table and the RESULT line.
3. `TIDECHART_HOME` must be the chiplet's own submodule. The standalone checkout is
   a genuinely different tree whose `tidechart_controller.sv` has no `device_strap`
   port, and pointing at it fails two suites with `Error-[UPIMI-E]` after ~5 s —
   which *does* compile RTL first, so elapsed time alone will not tell you which
   artefact you are looking at.

---

## 5. Provenance

Two of the fixes in section 1 were, until this session, on **no published branch at
all** — reachable only from one session's scratch worktree, while being described
as the current netlist line. They were rescued to
`origin/integ/tl037-n3-rescue-2026-08-18`, and have since landed properly on
`origin/main`.

The lesson generalises, and is worth applying to anything else believed to be "in":
ancestry by SHA is not enough, because a cherry-pick changes the SHA. Check the
*content* against the pin and against `origin/main`, and run
`git branch -a --contains`. If only `exec/*` scratch branches hold it, it is one
cleanup away from gone.
