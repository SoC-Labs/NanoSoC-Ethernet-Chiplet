# `-core_pin_check_stdcell_geometry` post-route ECO: NOT TESTED — host contended

**Date: 2026-08-19. Verdict: NOT TESTED. No Innovus session was launched.**
**This page is the falsifiable-test runbook, fully prepared and ready to execute,
plus everything that could be established without an EDA licence.**

This is a six-step falsifiable test of candidate fix 4 from
[`42-stranded-cells-pg-islands.md`](42-stranded-cells-pg-islands.md) §6b
(`-core_pin_check_stdcell_geometry`, post-route). Steps 2–6 require a live
Innovus session. **That session was not started, because the host load check
that gates step 2 failed, and the instructions were explicit: stand down
rather than force it.** Nothing below should be read as a pass or a fail on
the ECO itself — that question is still open.

---

## 1. Why it did not run — the load check, verbatim

Four samples, each a fresh `ps` scan for `innovus|genus|calibre|stylus|
encounter|voltus` (case-insensitive, any user) plus `/proc/loadavg`, taken over
about two minutes immediately before any Innovus invocation would have
happened:

| when | load (1m / 5m / 15m) | EDA processes found |
|---|---|---|
| baseline (given in brief) | 10.92 / — / — | zero |
| t0 | 16.87 / 11.51 / 7.45 | zero |
| t0+~10s | 14.52 / 11.47 / 7.57 | zero |
| t0+~30s | 13.48 / 11.42 / 7.64 | zero |
| **final, immediately pre-launch** | **20.85 / 14.82 / 9.52** | **zero** |

`nproc` = 16. Memory was never the constraint — 228 GB of 251 GB stayed
available throughout, and it stayed there because nothing memory-heavy was
running.

**Zero Innovus/Genus/Calibre/Stylus/Encounter/Voltus processes on the host at
any of the four samples.** The load is not P&R contention in the sense the
brief was worried about (another lane's live run). `ps` showed the actual
consumers: roughly fifteen concurrent Claude Code sessions (one per
`--resume=<uuid>` VS Code extension-host process) and their `bfs`/`find`
child processes doing filesystem searches (`*.lef`, `*wc.lib`, `rf_08k*.lef`,
`tpbn65v_9lm.lef`) — general host contention from concurrent agent activity,
not a rival EDA run.

That distinction doesn't change the call. The 1-minute figure did not trend
down across the four samples — it went 16.87 → 14.52 → 13.48 → **20.85**, and
the 5-minute and 15-minute averages rose in lock-step (11.51→14.82,
7.45→9.52). This is a host getting **more** loaded over the two minutes I
watched it, not a transient spike settling out. Launching an Innovus session
into that — even a small one — would have added a CPU- and memory-hungry
process to an already-climbing curve, for a task the brief itself says
"can wait" and "is not urgent enough to fight for a seat." So it did not
launch. Re-check load and EDA-process state again before running the runbook
in §5.

---

## 2. What `full-20260814` is, confirmed without touching it

Per the brief, `ASIC/eth-chiplet/build/full-20260814` was the named candidate
database. Before deciding whether to copy it, I confirmed it is idle:

- No file under it has been modified in the last hour (most recent touch:
  `reports/run_attestation.json`, 2026-08-18 23:05 — about 11.5 hours before
  this check).
- `lsof +D` on the directory returned nothing — no process has any file under
  it open.
- No live-session markers (nothing matching a lock/session file pattern; the
  only `*lock*` filename hits are report/artefact names like
  `cts_clock_latency_hold.rep` and `clock_trees.bin`, not real locks).
- Directory size: **3.6 GB** — small enough to copy to scratch cheaply once
  the host clears.

**It was not copied.** Copying 3.6 GB is itself I/O that competes with
whatever the other ~15 sessions are doing to a climbing load average, and
there is no point pre-staging a copy for a session I decided not to run.
§5 below gives the exact copy command to run first when the host clears.

### 2a. Provenance — which defect population this build carries

`reports/run_attestation.json` (`provenance.stages`) and `git merge-base
--is-ancestor` against the build's own recorded `project_revisions`
(`ac1e1e9`, `e089a79`, `cd8b47d`, all dirty):

| stage | date | project rev | toolkit rev |
|---|---|---|---|
| synthesis | 2026-08-14 14:03:23 | `ac1e1e9` | `20bc972` |
| place | 2026-08-14 16:16:24 | `e089a79` | `9feeca9` |
| cts | 2026-08-17 13:01:04 | `cd8b47d` | `9feeca9` |
| route | 2026-08-17 13:53:43 | `cd8b47d` | `9feeca9` |

`4d89253` (the M5 rail-short fix, "floorplan: move rf_32k off the placement
phase that shorts VDD to VSS") was committed **2026-08-17 20:51:25** — over
seven hours **after** this build's route stage finished — and
`git merge-base --is-ancestor 4d89253 <rev>` returns false for all three of
`ac1e1e9`, `e089a79`, `cd8b47d`. So **`full-20260814` predates `4d89253`**,
and it predates the 2026-08-19 power-plan feed-stripe fix
too (nothing in its stages is dated 08-19).

That means `full-20260814` carries **both** open defects at once, and they
are different:

1. **The via-less-riser / stranded-cell population** this ECO targets —
   confirmed present, see §3.
2. **The M5 VDD–VSS rail-to-rail shorts** `4d89253` was written to fix —
   independently confirmed still `FAIL` in this build's own
   `run_attestation.json`: *"4 rail-to-rail VDD-VSS SHORT record(s) on
   special wiring, at lines 21, 25, 29, 33"* (gate: PG rail-to-rail shorts,
   stream: signoff un-logoed).

**Whoever runs §5 should read the AFTER `check_drc` against both defects
separately.** A DRC delta that looks bad could be the (already-known,
already-diagnosed, unrelated) M5 short population moving for reasons that
have nothing to do with this ECO. Don't let that confound the read.

---

## 3. The BEFORE state — real numbers, already on disk, not fabricated

`full-20260814` carries its own `check_connectivity -type special` output
from its route stage, and it is **not capped**: the command line embedded in
the report itself is
`check_connectivity -type special -nets VDD -error 200000 -warning 200000
-out_file .../nanosoc_eth_chiplet_pads_conn_VDD.rep`, run
**2026-08-17 13:47:14**, well above the tool's 1000-error default (the exact
trap `flow/verify/check_conn_uncapped.tcl` exists to avoid — see its header
comment for the "337 problems from a check that had already stopped" case
study). This is a legitimate, complete BEFORE reading; I read it rather than
reproducing it.

```
reports/nanosoc_eth_chiplet_pads_conn_VDD.rep:
    35 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected together.
    533 Problem(s) (IMPVFC-94): The net has dangling wire(s).

reports/nanosoc_eth_chiplet_pads_conn_VSS.rep:
    30 Problem(s) (IMPVFC-200): Special Wires: Pieces of the net are not connected together.
    353 Problem(s) (IMPVFC-94): The net has dangling wire(s).
```

**Total IMPVFC-200 (special-wire opens): 65.** This lines up with the fp1505
numbers `42-…` quotes for the same geometry (35 VDD + 29 VSS there vs. 35 VDD
+ 30 VSS here) — consistent with that document's own finding that the five
sites are geometrically fixed across builds while the exact per-build count
drifts by one or two.

### 3a. The known via-less riser — confirmed still open, exact box

`42-…` §6a cites one riser example verbatim: `VDD 1058.735 475.000 0.330 ×
0.800`. It is in this file, unchanged:

```
Net VDD: has special routes with opens at (1058.735, 475.000) (1059.065, 475.800)
Net VDD: has special routes with opens at (1058.735, 489.000) (1059.065, 489.400)
Net VDD: has special routes with opens at (1058.735, 309.000) (1059.065, 309.400)
```

All three are on the same riser track (`x = 1058.735 → 1059.065`, a box
exactly 0.330 µm wide, matching `15-pg-opens-analysis.md`'s riser signature —
"a 0.330 µm-wide riser … each one measures 0.330 µm across the row's short
axis," `IMPPP-570` "detected cut layer obstruction(s) and cannot create via on
the VIA1/VIA3 layer," x-values including `1058.735`). **This is the exact
mechanism the ECO claims to repair** (`route_special.html`: *"Checks the
standard cell geometries in the design for any spacing violations between the
power rail to power stripe vias and cell blockages … repairs these violations
by trimming the via arrays as needed"*). These three boxes are the natural
BEFORE anchor for the live test's pass criterion (a): does the live
`check_connectivity -type special` after the ECO show these three gone, and
does an `IMPPP-570` search in `check_drc` output at these coordinates drop to
zero?

This is real, dated, on-disk evidence of the BEFORE state. **It is not a
substitute for step 3 of the brief's protocol** — it comes from the flow's own
route-stage run, not from a `read_db` in a session I controlled myself, so I
cannot vouch for exact reproducibility of the tool's internal state (message
ordering, any warm-start effects) the way a fresh `check_connectivity` in the
same live session as the ECO would provide. Re-run it fresh as step 1 of §5
regardless — it should take well under a minute and costs nothing to confirm.

---

## 4. Everything else the runbook needs — confirmed, so §5 has zero guesswork

**Toolkit database-open idiom.** Plain `read_db <path>`, not `pnr_read_db`.
Two toolkit scripts do exactly this kind of ad hoc, read-only, single-database
session and both use the bare form:

```tcl
# flow/verify/check_conn_uncapped.tcl:59
read_db $db
# flow/verify/lvs/lvs_pg_emit.tcl:751
read_db $db_dir
```

Both carry the same header warning, worth repeating here: *"READ-ONLY ON THE
DATABASE: `read_db` only, never `write_db`. Safe to run against an archived
signoff database without perturbing it."* `pnr_utils.tcl`'s `pnr_read_db`
(used by `2_place.tcl`/`3_cts.tcl` mid-flow) is the wrong tool for this — it
expects `$::pnr(in_db_dir)` and the rest of the flow harness state to already
be set up, which a throwaway scratch-copy session doesn't have.

**`route_special` syntax**, confirmed against `TCRcom/route_special.html` in
the installed Innovus 21.11-s130_1 reference (doc dated July 2021; the doc
root is inherited from the site's Cadence install and is not spelled in this
repository — see `42-…`'s provenance table for the same convention):

> `-core_pin_check_stdcell_geometry` — *"Checks the standard cell geometries
> in the design for any spacing violations between the power rail to power
> stripe vias and cell blockages to repair any DRC violations. When detected,
> Innovus repairs these violations by trimming the via arrays as needed. Use
> this parameter after routing the power structures."* Default: off.
> Data type: bool, optional (no argument).

`-nets { names }` takes the brace-list form. So the brief's proposed
invocation is exactly right as written:

```tcl
route_special -core_pin_check_stdcell_geometry -nets {VDD VSS}
```

One more thing the doc says that the runbook in §5 should use: *"To undo the
`route_special` command, use the `defOut` command to save the design database
before you issue the `route_special` command. Then you can use the `read_def`
command to restore the design to its state before running
`route_special`."* Take that checkpoint even though you're already on a
scratch copy — it makes the BEFORE/AFTER diff mechanical instead of
re-derived.

**`post_route` hook point**, confirmed real and confirmed currently empty:

- `ASIC/asic-toolkit/flow/innovus/4_route.tcl:1619` — `flow_hook post_route`,
  the last thing that runs before the (currently disabled) in-flow Calibre
  block.
- `flow_hook` (`ASIC/asic-toolkit/flow/common/flow_utils.tcl:302-325`) sources
  `$ASIC_HOOKS_DIR/post_route.tcl` if it exists, and aborts the stage loudly
  if that hook raises an error (hooks are treated as project code in the
  critical path, on purpose).
- `$ASIC_HOOKS_DIR` resolves for this project via
  `ASIC/eth-chiplet/design.mk:253`: `HOOKS_DIR ?= $(ETH_CHIPLET_ASIC_DIR)/hooks`
  → `ASIC/eth-chiplet/hooks/`.
- That directory currently holds `post_powerplan.tcl`, `post_synth.tcl`,
  `pre_synth.tcl`. **No `post_route.tcl` exists.** If §5 passes both
  criteria, this is exactly where the ECO would be wired in as
  defense-in-depth, guarded the same way the existing hooks are — advisory,
  wrapped in its own `catch` if it shouldn't be allowed to abort a route
  stage on a tool hiccup.

**Next free `docs/tapeout/` number.** Directory listing + `00-index.md` show
`55-imec-preliminary-gds-submission-checklist.md` as the highest in use, no
`56` reserved anywhere. This page is `56`.

---

## 5. The runbook — ready to run, unchanged from the brief, nothing skipped

Re-check load and EDA processes (§1's method) immediately before step 1. If
either looks like §1's final sample (climbing, or any real EDA process
present), stand down again — this is not urgent.

```sh
# 0. Copy, never touch the original
SCRATCH=<your scratchpad>/pgfix-eco-test
rsync -a --stats /home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet/ASIC/eth-chiplet/build/full-20260814/ "$SCRATCH/"
```

```tcl
# 1. Open it read-only, as an ad hoc session (see §4 for why this idiom)
read_db <SCRATCH>/work/nanosoc_eth_chiplet_pads_routed
# or whichever work/<block>_routed snapshot rsync copied — confirm the exact
# subdirectory name on the copy before this line; full-20260814/work/ has
# several (…_pads_route_preopt, …_pads_cts, …_pads_routed) and only the last
# is the one the brief means by "routed database".

# 2. BEFORE
defOut <SCRATCH>/checkpoint_before.def          ;# so route_special is undoable
check_connectivity -type special -nets VDD -error 200000 -warning 200000 \
    -out_file <SCRATCH>/before_conn_VDD.rep
check_connectivity -type special -nets VSS -error 200000 -warning 200000 \
    -out_file <SCRATCH>/before_conn_VSS.rep
check_drc -out_file <SCRATCH>/before_drc.rep
# Confirm §3a's three boxes are still there (or re-derive if geometry moved
# since 08-17):
#   grep -n "1058.735" <SCRATCH>/before_conn_VDD.rep

# 3. THE ECO
route_special -core_pin_check_stdcell_geometry -nets {VDD VSS}

# 4. AFTER
check_connectivity -type special -nets VDD -error 200000 -warning 200000 \
    -out_file <SCRATCH>/after_conn_VDD.rep
check_connectivity -type special -nets VSS -error 200000 -warning 200000 \
    -out_file <SCRATCH>/after_conn_VSS.rep
check_drc -out_file <SCRATCH>/after_drc.rep
```

```sh
# 5. Diff, honestly
diff <SCRATCH>/before_conn_VDD.rep <SCRATCH>/after_conn_VDD.rep
diff <SCRATCH>/before_conn_VSS.rep <SCRATCH>/after_conn_VSS.rep
diff <SCRATCH>/before_drc.rep      <SCRATCH>/after_drc.rep
```

### Pass criteria (both required — restated from the brief, unchanged)

- **(a)** The three known riser boxes at `x = 1058.735–1059.065` (§3a), and
  any other `IMPPP-570`-class 0.330 µm boxes `before_drc.rep` shares with
  `14-drc-triage.md` / `15-pg-opens-analysis.md`, gain a via and disappear
  from `after_conn_*.rep` / drop out of `after_drc.rep` at those exact
  coordinates.
- **(b)** The total open/DRC count does not go up anywhere else in the
  design — check this both by grand total (`IMPVFC-200` count, `check_drc`
  violation count) and by a coordinate-level diff, in case a net-count wash
  hides the ECO trading one open for a different one elsewhere. **Read the M5
  short lines (run_attestation's "4 rail-to-rail VDD-VSS SHORT… at lines 21,
  25, 29, 33") separately** — that population is a different, already-fixed
  (on other builds) defect and moving has nothing to do with this ECO; don't
  let it read as a criterion-(b) failure.

`42-…` §6b already commits to a qualitative prediction ahead of this test:
*"Riser-class opens fall; does not by itself feed an island whose only
target is outside the row. Complementary to 1, not a substitute."* That's
the hypothesis this runbook falsifies or confirms. It has not been run.

### If it passes both

Say so plainly, with the real before/after numbers, and note in the write-up
that this can be wired into `4_route.tcl`'s `post_route` hook
(`ASIC/eth-chiplet/hooks/post_route.tcl`, currently absent — see §4) as
defense-in-depth, alongside Fix 1 (`42-…` §6b, `-core_pin_target` with the
list form) rather than instead of it — the two are complementary, not
substitutes, by `42-…`'s own framing, since this ECO cannot feed a row island
whose only target lies outside the row.

### If it fails either

Say so plainly too, with the real numbers, and do not wire it into the hook.

---

## 6. What was, and was not, done

**Done:** host/EDA-process load check (four samples, §1); confirmed
`full-20260814` idle and safe to copy without copying it (§2); read its
provenance and established it carries both the stranded-cell defect and the
independent M5-short defect, unfixed (§2a); read its own genuine uncapped
BEFORE `check_connectivity` output and located the exact known riser boxes
named in `42-…` (§3); confirmed the toolkit's `read_db` idiom, the exact
`route_special` syntax against the installed reference, and the real,
currently-empty `post_route` hook point (§4); confirmed the next free
`docs/tapeout/` number.

**Not done:** no `read_db`, `check_connectivity`, or `route_special` was run
in a live Innovus session; no scratch copy was made; no pass/fail verdict on
the ECO exists. The host was contended and worsening at every check, per §1,
and the brief was explicit that this task can wait. §5 is the complete,
ready-to-run recipe for whoever (or whichever future session) picks it up
next when the host clears.

## 7. See also

- [`42-stranded-cells-pg-islands.md`](42-stranded-cells-pg-islands.md) §6b —
  names this ECO as candidate Fix 4, ranks it, gives the falsifiable
  prediction this runbook tests
- [`15-pg-opens-analysis.md`](15-pg-opens-analysis.md) — the riser mechanism
  in full, `IMPPP-570`, the 0.330 µm signature
- [`36-split-row-pg-anchoring-hazard.md`](36-split-row-pg-anchoring-hazard.md)
  — Fix 2, the structural alternative
- [`59-macro-placement-pg-short-window.md`](59-macro-placement-pg-short-window.md)
  — the four M5 VDD–VSS shorts `full-20260814` also carries (§2a), a
  different defect fixed by `4d89253`, not by this ECO
