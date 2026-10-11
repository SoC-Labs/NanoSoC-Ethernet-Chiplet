# rc6 flow demonstrator: close-out, 2026-10-11

**Audience:** the next engineer to take a nanoSoC design through the ASIC toolkit. rc6 is not a
tapeout candidate (rc4-20260829 shipped). It is the run that tested whether the toolkit is a
crank-the-handle flow, and it is frozen here. This page records what it proves, what it does
not, and where to restart.

## What rc6 is

- rc4's design with the HSEL bus-defect fix brought in: multicore `852bd05` (arch_tech
  `ceef4c7`, nanosoc_gen `308e2e0`).
- Synthesised fresh in `rc6b-20261007`; placed, clock-tree built and routed in the same run.
  ECO in `rc6e-20261008`. A second physical attempt, `rc6f-20261010`, used a placement-density
  cap.
- Toolkit at `914b22f`, branch `fix/lec-hier-abort-bounded` (PR #1 on the toolkit). The branch
  carries three fixes this run found.

## What it proves

| Check | Result | Run |
|---|---|---|
| Setup at signoff (Tempus, full extraction) | −0.018 ns, 1 endpoint (one PHC counter bit). Passes in-flow at +0.012 | rc6e |
| DRC | 0 | rc6b, rc6e |
| LEC, synthesised gates vs routed netlist | **Equivalent, 61,599 / 61,599** in 10 min | rc6b |
| LEC, RTL vs synthesised gates | 31 of 33 module pairs equivalent; 2 aborted (unproven, not shown wrong) | rc6b |
| Route and ECO stage gates | No hard failures after the layer-probe fix | rc6b, rc6e |

## What it does not prove

- **Hold.** Signoff hold is **−0.133 ns over 37 endpoints**. 29 of the 50 worst paths end at
  the ethernet CPU's interrupt-enable registers, whose clock arrives 0.51 ns later than their
  launching flops'. Hold is clean after CTS (+0.005 ns, 0 endpoints) and breaks at route.
  Route's hold repair reported 216 + 110 nets it could not fix for lack of a legal location;
  the signoff ECO made one change and stopped.
- **Two RTL→gate LEC modules**: the TideLink D2D link (`Wlink`) and the ETH IMEM wrapper. Each
  stops at its first abort, so about 14,800 points in each are not compared. `Wlink` has
  9,845 XOR gates in RTL against 466 XOR + 297 XNOR in gates, a classic abort source.

## What the run changed in the toolkit

1. **LEC finishes.** Genus's `set_analyze_option -auto` makes `run_hier_compare` insert an
   unbounded `analyze abort -compare`; on rc6b that ran 10 h in one module, twice. The RTL leg
   now runs with `-noanalyze_abort` and finished in 56 min.
2. **LEC sees child aborts.** The verdict read the top module's counters only, which reported
   5433/5433 equivalent and 0 aborts while 2 children had aborted. It now reads the
   per-module progress lines and fails unless every pair is equivalent.
3. **Signoff STA reports by view role**, clearing six tool errors per run.
4. **`PLACE_MAX_DENSITY`**, a placement-density cap with range check and read-back.

Use `make lec-syn` and `make lec-pnr`. `make lec` still runs Genus's dofile directly and has
neither fix.

## The rc6f attempt

`PLACE_MAX_DENSITY=0.90` (rc6b placed uncapped at 85.5 % utilisation, local density 100 %).
Placement applied the cap and read it back. CTS then could not legalise 15 instances
(IMPSP-2021) and the stage stopped in strict mode. The cap is too close to the design's
utilisation for this floorplan.

## Where to restart

1. Rerun from rc6b's synthesis with `PLACE_MAX_DENSITY=0.95`, or keep 0.90 and find why CTS
   legalisation fails (the 15 instances are small logic cells near the core).
2. For a new die, plan utilisation in the 60–70 % range so hold repair has room.
3. Run the two aborted LEC modules alone at high compare effort, with XOR-tree abort
   resolution, under a per-module time limit.
4. Give the RTL leg its own rule set; removed constant registers and clock-gate latches are
   expected there.

Run directories (gitignored) live under `ASIC/eth-chiplet/build/` as `rc6b-20261007`,
`rc6e-20261008` and `rc6f-20261010`; signoff STA under `ASIC/sta/work/rc6e-20261008/`.
