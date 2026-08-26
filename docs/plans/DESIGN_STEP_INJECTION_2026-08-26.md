# Design-step injection: how a design ships its own geometry fixes without putting them in the toolkit

**Date** 2026-08-26 · **Status** proposal, nothing implemented · **Scope** `ASIC/asic-toolkit` contract, `ASIC/eth-chiplet` consumption

## What this document is

`ASIC/asic-toolkit` is a pinned submodule (`b1a903a`, described by `git submodule status` as
`v0.1.0-27-gb1a903a`) meant to be design-agnostic across the nanosoc family. `ASIC/eth-chiplet/`
is one consumer. On 2026-08-25 this design landed three post-route DRC repairs — a via-master
clone, a via re-cut, and a macro-pin escape narrowing — as design-side Tcl
(`8c0c9c7`), wired in through a hook (`c9d30a6`). None of that content belongs in the toolkit,
and all of it needs the toolkit to run it, order it, judge it and record it.

This proposes the mechanism for that. It is written from the three scripts and the four hooks as
they exist today, and every recommendation below names the file and line it came from.

**Two parallel audits are running** — one on the current seam, one on cross-design reuse. This
document is written to absorb them rather than pre-empt them. Section 6 (seams) states its
reasoning so a seam-audit finding can move a row without changing the mechanism; section 2's
option D (search path) is deliberately deferred to the reuse audit, and section 10 lists the
questions whose answers change the proposal.

---

## 1. What today's case actually looks like, measured

The concrete artefacts:

| file | lines | what it is |
|---|---|---|
| `ASIC/genus-innovus/scripts/pg_drc_geom_lib.tcl` | 305 | 22 `pgg_*` geometry primitives. Read-only on the design. Carries `PGG_LIB_VERSION 1` (`:28`). |
| `ASIC/genus-innovus/scripts/pg_drc_post_route_edits.tcl` | 778 | two edits (a via re-cut, a via-master clone-and-trim), seek + apply + verify, driven by a bare `source` |
| `ASIC/genus-innovus/scripts/pg_drc_via3r4_m4_narrow.tcl` | 653 | a third edit that cannot seek from the database at all and takes a Calibre marker as input (`:44-49`) |
| `ASIC/eth-chiplet/hooks/post_powerplan.tcl` | 156 | the wiring: resolves paths, sets eight globals, sources, writes one report |

Seven properties of that code are load-bearing and the architecture must keep every one:

1. **The target is located by rule predicate, not coordinate.** `pg_drc_post_route_edits.tcl:5-10`
   records why: the previous revision named both targets by literal coordinate, "safe on the
   lineage they were measured on and USELESS on a fresh route".
2. **The seek reports its own census.** `_pg_v4r4_seek` prints how many candidates it examined and
   how many it rejected in each of five named buckets (`:266-268`), plus the closest *rejected*
   candidate and its margin (`:269-273`).
3. **The predicate has a stated control.** Three sites carry the same via master with the same
   landing and are *not* violations; "any predicate that fires on those three is wrong"
   (`:190-195`). Today that control is a comment.
4. **Every stage asserts a count range and refuses outside it, including zero.** `_pg_range_check`
   (`:149-160`) — and its own message admits the ambiguity it cannot resolve: "ZERO means either
   the defect is not present ... or the predicate no longer matches the geometry — both are
   refusals".
5. **The apply is bracketed by post-guards on the placed object.** Cut count, both metal faces
   unmoved, cuts inside the landing (`:352-366`); and for the trim, the trimmed face, the untouched
   face, and the cut count (`:685-697`).
6. **The edit refuses rather than degrade.** Nine distinct `error` sites across the two apply procs,
   each naming the rule that would be broken instead.
7. **A post-edit verify re-runs the seek and requires zero** (`:759-777`).

That is a good step. The problem is that all seven properties are *hand-written in the step*, so the
next step re-implements them or does not. The proposal is to move properties 2, 4, 5 and 7 into the
toolkit, and leave 1, 3 and 6 — the design knowledge — in the design.

### The wiring is where it goes wrong

`ASIC/eth-chiplet/hooks/post_powerplan.tcl` is 156 lines to run two things. Of those:

- **Two copies of a path-resolution block** (`:46-51` and `:124-129`), each 6 lines, each with its
  own `LEGACY_ASIC_DIR`-or-climb branch. `pre_synth.tcl:36-40` and `post_synth.tcl:124-128` carry
  two more. Four copies of the same idea in one design.
- **Two hand-written "cannot read the file" errors** (`:58-62`, `:132-136`), each arguing at length
  why a missing file must be fatal.
- **Configuration passed by setting stage globals before `source`** (`:139-144`). Because `flow_hook`
  sources with `uplevel 1` (`flow_utils.tcl:341`), those eight variables land in the stage's global
  scope and stay there. The step's own header states the hazard: "in a long-lived session an
  override survives until it is unset" (`pg_drc_post_route_edits.tcl:105-106`).
- **A `unset` of the leaked variables** (`:68`) — which is a live defect, see the appendix.
- **A silent skip switch.** `EVP_NO_PG_DRC_EDITS=1` (`:114`) produces a `warn` in a multi-hundred-
  megabyte log and appears in no artefact.
- **A hand-widened expectation.** `PG_V4R4_EXPECT {0 2}` and `PG_M8S3_EXPECT {0 3}` (`:142-143`),
  overriding the step's own `{1 2}` / `{1 3}` defaults. The comment at `:104-111` is honest about
  what this costs and says the protection "MOVES" to a `check_drc` report — i.e. to a file nobody is
  required to read. **This is the single most important thing to fix.** It converts the step's
  refusal into a pass, in the one direction where nothing downstream notices.

---

## 2. The mechanism: four options, and the recommendation

### Option A — enriched hooks (today, plus helpers)

Keep `hooks/<seam>.tcl`; give the toolkit a `flow_eco` helper the hook calls.

*For*: zero discovery machinery; the seam list already exists in three places; a design already
knows how to write one. *Against*: one file per seam holds N unrelated fixes with no identity, so
provenance can never be finer than `post_powerplan(12s)` (`flow_utils.tcl:353`); ordering is source
order in a 156-line file; a fix cannot be individually skipped, ranged, or reported; and the
boilerplate stays, because each hook still has to find its own scripts.

### Option B — a declarative manifest the design supplies

`ASIC/eth-chiplet/steps.tcl` (or `.conf`) lists steps: id, seam, order, file, expectations.

*For*: ordering and inventory are explicit and reviewable in one place; the toolkit can print the
plan before running anything. *Against*: **it is a second source of truth.** The manifest and the
step file must agree, and this repo has a named recurring failure for exactly that shape — the
tree carries multiple copies of the same source and only the flist says which one builds. A step
whose expectations live in the manifest and whose predicate lives in the file will drift, and the
drift is silent because the manifest still parses.

### Option C — a registry directory the toolkit scans, each step self-declaring

`ASIC/eth-chiplet/steps/*.tcl`; each file calls `design_step <id> -seam ... -order ...` once;
the toolkit globs, loads, sorts, and invokes.

*For*: one source of truth — the declaration is next to the code it declares; adding a step is
adding a file; the toolkit can census "files discovered" against "steps registered" and refuse a
mismatch, which closes the "a file that registered nothing is invisible" hole. *Against*: discovery
order is `readdir` order unless the declaration carries an explicit `-order`; and a registry needs a
rule for what happens when two steps claim the same id.

### Option D — a design-steps search path

`ASIC_DESIGN_STEPS_PATH` as a colon-separated list of registry directories, so a step can be shared
across designs without being in the toolkit.

*For*: this is the only option that answers cross-design reuse; and the toolkit already has a
two-entry search path with exactly these semantics — `flow_step` (`flow_utils.tcl:371-388`) looks in
`ASIC_OVERRIDES_DIR` then `$ASIC_FLOW_DIR/flow/steps`, announces which one won
(`say "step file: $name ($src)"`, `:385`) and records it in `::flow(steps)`. *Against*: precedence
and shadowing are new rules to get wrong, and nothing needs them today. `flow_step` gets away with
two entries and wholesale replacement precisely because it refuses to merge (`:360-370`).

### Recommendation: C as the substrate, D deferred, B derived not authored

Adopt **option C**. Add option **D** only when the reuse audit produces a step two designs actually
share — and when it does, copy `flow_step`'s idiom exactly: an ordered path, announce the winner,
refuse to merge. Emit option **B**'s manifest as an *artefact* of the run rather than an input to
it, so the inventory exists for review without becoming a second thing to maintain.

Two design decisions make C work, and both are the point of the whole proposal:

**C1. The toolkit owns the control flow; the design owns only the predicate and the edit.** A step
does not `source` and run; it *registers callbacks*. The runner performs, for every step
identically: seek → census → range check → plan print → apply (or not) → bracket → verify → record.
That is how the predicate form becomes the easy one (lesson 1): the shortest legal step is a `seek`
that returns sites, and there is no shorter way to write a coordinate.

**C2. A step file is sourced in its own scope and configured by a dict.** Not `uplevel 1`, not
globals set by the caller. This deletes the leaked-configuration hazard the step's own header
documents (`pg_drc_post_route_edits.tcl:105-106`), deletes the `unset` boilerplate, and deletes the
defect in the appendix by construction.

There is precedent for the declaration form inside the toolkit already: `ROM_ASSERT_TABLE` in
`ASIC/asic-toolkit/templates/hooks/post_synth.tcl` is a Tcl list-of-dicts validated row by row with
unknown-key-is-fatal (`:148-203`). The declarative registry idiom also exists in
`ASIC/asic-toolkit/ci/pipeline.conf.example:24-31`, whose header states the property this proposal
needs: *a stage that is not declared there is not run and does not appear in the results.* Use those
two idioms; do not invent YAML.

### Where it lives

```
ASIC/eth-chiplet/steps/                        the registry (design-owned, design-committed)
  _lib/pg_geom.tcl                             shared design libraries, loaded once
  pg_m8s3_via_trim.tcl                         one step, one file
  pg_via4r4_recut.tcl
  pg_via3r4_pad_narrow.tcl
ASIC/asic-toolkit/flow/common/design_steps.tcl the runner (toolkit-owned, design-agnostic)
```

Nothing about the eth chiplet enters the toolkit. The runner never names a rule, a layer, a via
master or a coordinate; it knows only ids, seams, counts and statuses.

---

## 3. The contract

### 3.1 Declaration

One call per step, at file scope, no tool commands allowed during load:

```tcl
design_step pg_m8s3_via_trim \
    -contract   1 \
    -seam       post_powerplan \
    -order      50 \
    -title      "wide-metal gap on stacked riser landings" \
    -why        "born in the power plan; nothing downstream regenerates PG geometry" \
    -config     {trim_face bottom  verify 1} \
    -expect     {1 3} \
    -tolerate   {0 3} \
    -discriminates {also-wide near-miss} \
    -changes    {special_vias via_defs} \
    -probe_at   {post_route} \
    -lib        pg_geom@1 \
    -seek       ::steps::m8s3::seek \
    -apply      ::steps::m8s3::apply \
    -verify     default
```

Unknown keys are fatal at load (the `ROM_ASSERT_TABLE` rule,
`templates/hooks/post_synth.tcl:148-203`). Required: `-contract -seam -seek`. A step with `-seek`
and no `-apply` is a **measurement-only step** and is legal — that is how a gate ships through the
same machinery as a fix.

### 3.2 Seams, and what the DB guarantees at each

The engine has exactly ten `flow_hook` call sites. Their DB state, from the call sites:

| seam | file:line | the DB guarantees | can it change what ships? |
|---|---|---|---|
| `pre_synth` | `flow/genus/1_synthesis.tcl:933` | RTL elaborated, SDC read, cost groups built; nothing mapped | yes |
| `post_synth` | `1_synthesis.tcl:1015` | mapped + optimised netlist in memory; **nothing written yet** | yes |
| `pre_floorplan` | `flow/innovus/2_place.tcl:805` | post-`init_design`: netlist, MMMC, LEF, power intent. **No die box, no rows, no macros** | yes |
| *(gap)* | between `:816` and `:870` | floorplan sourced, rows cut, macros placed; **no PG** | — |
| `post_powerplan` | `2_place.tcl:879` | floorplan + complete PG grid (rings, stripes, row splits, endcaps, risers); nothing placed | yes |
| `pre_place` | `2_place.tcl:1297` | placement attributes applied and read back | yes |
| `post_place` | `2_place.tcl:1332` | placed, pre-CTS optimised, tie-offs; **before the snapshot** | yes |
| `pre_cts` | `flow/innovus/3_cts.tcl:994` | placed DB, CTS config validated, clock still ideal | yes |
| `post_cts` | `3_cts.tcl:1326` | clock tree built, post-CTS opt and hold done, scan reordered | yes |
| `pre_route` | `flow/innovus/4_route.tcl:820` | routing config applied and read back; no signal metal | yes |
| *(gap)* | before `:1816` | routed, optimised, filled, bond pads in, verified | — |
| `post_route` | `4_route.tcl:1970` | **everything already on disk** — GDS at `:1816`, netlists `:1836`/`:1895`, SDF `:1909` | **no** |

Two contract facts a step author must be told, because neither is obvious:

- **`post_route` cannot change what ships, and the engine enforces it.** `4_route.tcl:1953-1984`
  brackets the hook with a geometry census, armed by the hook's *existence* rather than by a knob,
  and asserts nothing was added. It uses `die`, so `ROUTE_STRICT=0` cannot downgrade it
  (`:1933-1940`). The comment records that a project's entire bond-pad ring was once placed from a
  `post_route` hook and streamed into nothing (`:1926-1931`).
- **Strictness is not uniform across seams.** `3_cts.tcl:1018` sets `flow_config strict 0`
  immediately *after* `pre_cts`, so a `flow_fail` raised in `pre_cts` is governed by `CTS_STRICT`
  and the same call at `post_cts` is inside the relaxed window. A step must not reason about
  strictness itself; §4 removes the need to.

### 3.3 Variables in scope

`flow_boot` (`flow_utils.tcl:453-541`) publishes, before any hook fires: `FLOW_DIR`, `ASIC_DIR`,
`block_name`, `RUN_TAG`, `WORK_DIR`, `LOG_DIR`, `REPORT_DIR`, `OUT_DIR`, `IN_DIR`, `IO_FILE`,
`TECH_DIR`, `process_node`, `SDC_FILES`, the collateral lists, everything
`config/design_config.tcl` sets, and the helpers `say warn step die flow_fail try_step opt reports`
plus `tech`/`tech_has` and the `prov_*` family. The four output directories are created at
`:487-489`.

**A step gets these read-only, through the runner's environment, not by scope leakage.** In
particular `ASIC_RUN_DIR` is consumed by `flow_boot` into a proc-local and never republished
(`:467-469`), so the runner must publish `step_dir run` explicitly rather than let each author
rediscover `[file dirname $REPORT_DIR]`.

### 3.4 What a step returns

`seek` returns a dict. Three keys are mandatory:

```tcl
dict create \
    sites    {<site> <site> ...}     ;# opaque to the runner; each is a list whose
                                      ;# first element is a human coordinate string
    examined <N>                      ;# candidates the predicate actually looked at
    rejected {on-plate 12  no-wide 41  too-far 6  already-multicut 3}
```

Optional: `nearest {<text> <margin>}` — the closest rejected candidate and its margin, so a run
drifting toward a limit says so before it crosses. `pg_drc_post_route_edits.tcl:269-273` already
produces exactly this by hand; the runner should print it in a fixed column so it is greppable
across runs.

`apply` receives one site and a tag, and returns a one-line description. It reports structured
facts through two runner-supplied commands rather than by formatting:

```tcl
step_site   <coord-string> <one-line description of what was done here>
step_note   <key> <value>          ;# lands in the manifest as step.<id>.note.<key>
```

`verify default` re-runs `seek` and requires `sites` empty and `examined` unchanged within the same
run. A step may supply its own `verify` proc; it may not omit verification — `-verify none` requires
a `-verify_why` string that is recorded verbatim in the manifest and in the evidence bundle.

### 3.5 The four outcomes, and what the toolkit does with each

This is the heart of it. **The runner distinguishes four states, not two**, and the distinction is
made by `examined`, not by `sites`:

| outcome | condition | in-flow | standalone |
|---|---|---|---|
| **UNMEASURED** | `examined == 0` | **hard error, always** | hard error |
| **CLEAN** | `examined > 0`, `sites == 0`, and `0` is inside `-expect` | pass, recorded | pass |
| **DEVIATED** | `sites` outside `-expect` but inside `-tolerate` | continue, run un-certifiable (§4) | hard error |
| **REFUSED** | `sites` outside `-tolerate`, or an `apply` raised | hard error | hard error |

`examined == 0` is the state today's code cannot express. `_pg_range_check` folds "the defect is
absent" and "my predicate stopped matching" into one refusal and says so in its own message
(`:152-158`). A predicate that examined zero candidates has established nothing whatever, and a
predicate that examined 88 candidates and rejected all 88 for named reasons has established that the
grid is clean. Those are different facts and the artefacts must say which one happened.

Three existing precedents in this tree say the same thing in three idioms, which is why the
vocabulary should be shared rather than invented:

- `2_place.tcl:829-838` — a message count of `-1` means neither the tool nor the log could answer,
  and the flow fails with "an unasked question is not a clean answer."
- `flow/common/provenance.tcl:135` — `prov_unverified` is "the ONE spelling of *I could not measure
  this*", and `:46-49` forbids silent omission: every field is a value or `UNVERIFIED:<reason>`.
- `ci/contract.sh:36-38` — `ci_census`, whose whole subject is "the rules are fine; there was
  nothing to run them over."

**`-discriminates` is arming without a fixture.** It names one or more `rejected` buckets that must
be non-empty. If the predicate's "this candidate is on the plate, not on a branch" filter never
fires anywhere on the chip, the filter is dead and the seek's zero means nothing. This is the
executable form of the control the step documents in prose at
`pg_drc_post_route_edits.tcl:190-195`, and it costs the author one word.

**`-changes` is the generalised bracket.** The runner censuses the named object classes before and
after `apply` and refuses if anything outside the declared set moved. This is
`pnr_assert_no_geometry_added` (`4_route.tcl:1979-1980`) generalised from one seam to every step,
and it subsumes the hand-written post-guards at `pg_drc_post_route_edits.tcl:352-366` and `:685-697`
— which each check, per site, that the edit moved no metal. Making it declarative means the *next*
step gets the check for free.

**`-probe_at` answers lesson 3 with a measurement instead of a rule.** A step registered at
`post_powerplan` may name later seams at which its `seek` is re-run **read-only, never applied**.
The census from each probe lands in the manifest. That is the automated form of the comparison
`post_powerplan.tcl:74-84` did by hand — reading the power-plan-time PG report against the
post-route DRC report thirteen hours later to prove the defect was born early. A step whose defect
first appears at a probe seam *later* than where it applies is a bug in the step's placement, and
the manifest will show it as such rather than requiring a human to remember to look.

### 3.6 Load and run are separate phases

At the **start of each stage**, the runner globs the registry, sources every file in its own
namespace, and builds the inventory for all seams in that stage. Then, at each seam, it runs the
steps registered there. Consequences, all of them wanted:

- A syntax error in a step registered at `post_route` is caught at minute five, not hour four.
- The stage manifest can name steps that were *expected* at a later seam even if the stage aborts
  before reaching it — so an aborted run's artefacts still say what it was going to do.
- File-count versus registration-count is checkable: `N` files discovered must yield `≥ N`
  registrations, and a file that registered nothing is a hard error naming the file. A step that
  fails to register is otherwise invisible, which is the same class as a hook file with an
  unrecognised name (`scripts/asic-flow-check:402-407`: "they WILL NEVER RUN and nothing at run
  time will say so").

Ordering is `-order` ascending, ties broken by id lexically, and the resolved order is **printed
before the first step runs**. Duplicate ids at one seam are a hard error. The filename is not a
source of order or identity — one source of truth, per §2's objection to option B.

There is a stricter variant worth considering, and the toolkit already uses it.
`ci/pipeline.conf.example:26-31` declares that the written order *is* the run order and that the
dependency field is **checked against it rather than used to sort** — "a ladder whose written order
disagrees with its dependency order is a bug in the ladder, and pipeline.sh says so instead of
silently reordering." That trade is right for a hand-maintained ladder in one file. It is wrong for
a globbed registry, where "written order" is `readdir` order and therefore not written by anyone.
So: sort by `-order`, but adopt the underlying principle — if a step declares `-after <id>` and the
resolved order contradicts it, that is a hard error naming both steps, not a silent re-sort.

---

## 4. The dual failure policy, without a silent tolerant mode

The requirement: standalone must refuse on a zero; in-flow the same zero must not throw away five
hours when a grid legitimately comes out clean. Today that is solved by editing the numbers
(`post_powerplan.tcl:142-143`) — which is not tolerance, it is silence.

**The fix is that tolerance changes *where* the refusal lands, never *whether* there is one.**

A step declares two ranges. `-expect` is what the design believes is true. `-tolerate` is what a
long run may proceed through. Between them is DEVIATED, and DEVIATED is a first-class recorded
state with three consequences:

1. **The stage continues** and the step is recorded `status=deviated` with its counts, its census
   and its rejection buckets.
2. **The run cannot be certified clean.** The deviation is written to the step ledger and into the
   stage manifest, and `make evidence` refuses to grade the bundle while an *undeclared* deviation
   stands. This is not new machinery: `ASIC/eth-chiplet/evidence/gdsrun-20260825-resynth.json`
   already carries a `known_bad` array (6 entries) and a `not_measured` array (8 entries), each
   entry keyed `id / what / decision / person / date / withdraw_when`. A deviation is declared by
   adding an entry with that shape. The `withdraw_when` field is the part that matters: a declared
   deviation carries the condition under which it stops being acceptable.
3. **It is loud in the log at a fixed, greppable prefix**, and the count of deviations appears in
   the stage's own verdict line — not only in a report file. `floorplan-hazards.mk:56-59` already
   holds this rule for advisories: "The advisory count is in the verdict line and in the JSON, so a
   run record cannot quote a PASS without also carrying what it passed with."

Policy is set by the runner, not by the step:

| context | how it is set | `expect` violated | `tolerate` violated | `examined == 0` |
|---|---|---|---|---|
| in-flow | runner default when a stage is driving | DEVIATED | REFUSED | REFUSED |
| standalone | runner default under the standalone entry point | REFUSED | REFUSED | REFUSED |
| dry | `ASIC_DESIGN_STEP_MODE=dry` | as in-flow, no `apply` runs | REFUSED | REFUSED |

Three properties that keep this honest:

- **A step cannot set its own policy.** It declares ranges; the runner decides what a range
  violation means. The hook currently does the opposite (`post_powerplan.tcl:137-144`, "Every one is
  a deliberate departure from the script's standalone defaults").
- **`-tolerate` cannot be omitted to mean "anything".** Absent, it equals `-expect`, so the default
  is strict everywhere and tolerance is always an explicit, reviewable act.
- **`REFUSED` uses `die`, not `flow_fail`.** `flow_fail` is downgraded to advice when
  `$::flow(strict)` is 0 (`flow_utils.tcl:92-95`), and strictness is already relaxed across the
  CTS window (`3_cts.tcl:1018`). The engine has the precedent and the reasoning for the exception:
  `4_route.tcl:1933-1940` — "the fault being guarded is one where the run looks entirely successful,
  so a guard a setting can downgrade to advice is no guard at all."

**Skipping is also a recorded state.** `EVP_NO_PG_DRC_EDITS=1` (`post_powerplan.tcl:114`) currently
leaves a warning in the log and nothing else. A step disabled by environment must be recorded
`status=skipped` with the variable name and value that did it, and counted in the stage verdict.
`ci/contract.sh:55-60` is the precedent: "A SKIP is honest; a SKIP that nobody counts is a hole."

---

## 5. Path resolution, solved by removing the question

Four copies of a path-resolution branch exist in this design's four hooks
(`pre_synth.tcl:36-40`, `post_synth.tcl:124-128`, `post_powerplan.tcl:46-51` and `:124-129`), each
choosing between an environment variable and a two-level climb from `[info script]`. The climb broke
a synthesis six minutes in on 2026-08-25, in two different run layouts — one that copied hooks to
the run root, and one that copies them into a `pinned/` subtree. The fourth copy carries a live
defect (appendix).

**A step author must never compute a path.** The runner provides three commands and nothing else:

```tcl
design_file <role> <component>...   ;# resolve, assert readable, return the path
design_lib  <name>@<version>        ;# load a shared design library once, idempotent
step_dir    <role>                  ;# run | reports | outputs | work | logs | steps
```

`<role>` is resolved from the environment the make layer already exports, never from `[info script]`:

- `steps` — the directory the step file was discovered in. The runner knows it; the author cannot
  get it wrong.
- `legacy` — `LEGACY_ASIC_DIR`, which `ASIC/eth-chiplet/design.mk:61` defines and from which nine
  further inputs are derived (`:165`, `:170`, `:182`, `:185`, `:208`, `:213`, `:235`, `:245`,
  `:502`).
- `design`, `run`, `reports`, `outputs`, `work`, `logs` — from `flow_boot`'s published globals
  (`flow_utils.tcl:471-474`).

**This survives snapshotting by construction, and the run dir proves it.** A pinning run writes a
`pins.mk` whose entire content is five variable redirections — `LEGACY_ASIC_DIR`, `ASIC_FLOW_DIR`,
`HOOKS_DIR`, `OVERRIDES_DIR`, `DESIGN_CONFIG_TCL` — each pointed into the run's own `pinned/` tree,
and its header states the design intent: "LEGACY_ASIC_DIR is the SINGLE override that pins the whole
legacy input set." A registry rooted at `STEPS_DIR` (exported as `ASIC_DESIGN_STEPS_DIR` beside
`ASIC_HOOKS_DIR` at `ASIC/asic-toolkit/mk/flow.mk:374`) joins that list as a sixth line, and every
step follows without knowing anything happened. A climb cannot be made to work this way, because the
correct number of levels differs between the two layouts already on disk.

Two supporting measures:

- **`design_file` owns the missing-file error.** One implementation, printing the role, the
  requested components, the resolved path and *the whole anchor set it resolved from*. That replaces
  the two hand-written refusals at `post_powerplan.tcl:58-62` and `:132-136`, and makes the next one
  free.
- **The climb becomes detectable.** `scripts/asic-flow-check` already warns on unrecognised hook
  filenames (`:402-407`); it should also scan the registry for `info script`, `file dirname [file
  dirname`, and `$::env(` outside a declaration, and warn with the same reasoning. A grep is not a
  proof, but this is a shape and shapes are greppable — the method `ci/check-vacuous-gates.sh:14-17`
  argues for.

---

## 6. Seam coverage: put a seam where a decision becomes immutable

The four seams this design uses were chosen from the ten the engine offers. The right question is
not "which of the ten do we use" but "where does a class of decision stop being changeable", because
that is where a repair has to land to be made once instead of re-derived every spin.

Enumerate the artefacts a later stage only ever *reads*: the elaborated hierarchy; the mapped
netlist; the written power-intent text; the floorplan (rows and macro placement); the PG grid;
placement; the clock tree; routes; fill; the stream. Ten boundaries. The engine has a seam
immediately after seven of them. **Three are missing, and all three have a measured workaround
already in this tree.**

### Gap 1 — between the floorplan and the power plan

`pre_floorplan` fires at `2_place.tcl:805`, *before* `source $FLOORPLAN_TCL` at `:809`. The next
seam is `post_powerplan` at `:879`, *after* `source $POWER_PLAN_TCL` at `:877`. Between them the
rows are cut, the macros are placed, and the grid is then built on top of all of it — with no seam
at which a macro coordinate can be measured or nudged.

The workaround is in the tree and it is explicit about why it is where it is.
`ASIC/floorplan-hazards.mk` wires `scripts/ci/check_floorplan_hazards.py` as a **make prerequisite**
of `place` (`:183`) rather than as an in-tool check, and the header explains: the recipe belongs to
the toolkit submodule and a project must not edit it, so appending a prerequisite from an included
fragment is the supported way (`:27-33`). It runs on the floorplan *text*, before Innovus starts.
That is genuinely the cheapest place for a *pre-flight*, and the file says so (`:35-39`). But it
cannot repair, and it cannot see anything the tool computes. The same header records what the gap
cost: two macro pin edges half a track pitch off the escape grid, found by five DRC violations one
hour into a two-hour-thirty-eight-minute route (`:21-23`).

**Propose `post_floorplan`**, in `2_place.tcl` after the row-existence check at `:812-816` and
before the fatal-warning census at `:820`. Order matters: after the rows exist, so a step can
measure them; before the fatal-warning judgement, so a step's own repair is judged by it.

### Gap 2 — between the two tools, on the power-intent text

`ASIC/eth-chiplet/design.mk:894-902` states this one exactly, and names the four line numbers that
bracket it: `post_synth` is too early, the power-intent file is then written, synthesis ends with no
further seam, Innovus reads the file, and `pre_floorplan` is too late. The repair is a text edit and
belongs to neither tool, so it is wired at the make layer as `place: cpf-patch` (`:911-928`).

That is the right layer, and the mechanism should adopt it rather than fight it. The toolkit already
has make-layer post-stage seams — `evidence.mk:31` notes `ROUTE_POST_TARGETS = evidence`, fired
after the stage has exited and its verdict is parsed, with the reasoning at `:33-36`. **Propose the
symmetric pre-stage seam**, and let a registry step declare `-seam pre_place_files` to run at the
make layer with the same id, ordering, expectation and provenance semantics as a Tcl step. The step
body is then a program rather than a Tcl proc, and the runner's four outcomes apply unchanged: a
patch that finds zero files to patch is UNMEASURED, not clean.

### Gap 3 — after fill, before the stream

`post_route` fires at `4_route.tcl:1970`, after `write_stream` at `:1816`. There is no seam between
filler insertion and stream-out at which geometry that must ship can be created or repaired. The
engine's response to that gap has been to add bespoke escapes: `BONDPADS_TCL`, documented in
`ASIC/asic-toolkit/docs/source/reference/contract.md:117` as "the only correct seam for a pad ring";
and the armed guard at `:1953-1984` that exists because a project put its pad ring in `post_route`
and streamed a GDS without one (`:1926-1931`).

**Propose `pre_stream`**, immediately before `write_stream`. One general seam replaces the pressure
to keep adding named ones, and the existing guard generalises to it directly: bracket every
registry step with the census it already implements, and the declared `-changes` set says what is
allowed to move.

### The seam list must have one owner

The canonical hook names appear in four places today: a comment in
`ASIC/asic-toolkit/flow/common/flow_utils.tcl:287-305`, a Python list at
`scripts/asic-flow-check:38-44`, a table at `docs/source/reference/contract.md:420-431`, and a table
at `templates/hooks/README.md:15-22`. Nothing cross-checks them, and the drift is already visible:
the `templates/hooks/README.md` table lists eight seams and contains no mention of `post_powerplan`
at all, while `post_powerplan` is a real seam with a real consumer. The same script's `STEPS` list
(`asic-flow-check:48`) omits `metal_fill` and `pg_capacity`, which *are* real `flow_step` names
(`4_route.tcl:1145`, `:1442`) — so a legitimate override of either is reported as unrecognised
today.

**One machine-readable seam table in the toolkit, everything else generated from it.** Each row:
seam name, stage, the DB guarantee, whether it can change what ships, and which object classes it
may legally alter. The runner reads it to validate `-seam` and `-changes`; `asic-flow-check` reads
it instead of its hardcoded list; the documentation tables are rendered from it. A step naming a
seam that does not exist is then a **refusal at load**, not a file that never runs.

---

## 7. Provenance

The machinery exists; it needs per-step granularity and one new consumer.

**What exists.** `::flow(hooks)` accumulates `name(Ns)` per hook (`flow_utils.tcl:353`) and lands in
the stage manifest as `hooks_run` (`1_synthesis.tcl:1269-1270`, `pnr_utils.tcl:1798-1799`).
`::flow(steps)` does the same for step overrides (`flow_utils.tcl:386`, emitted at
`pnr_utils.tcl:1797`). `flow/common/provenance.tcl` provides `prov_pin <key> <path> <label>`
(`:234-244`), which records the resolved path, sha256, byte count and the epoch **at the moment the
stage read the file**, and flags `mutated_under_run` if a later observation disagrees. Its point of
use is already exactly this pattern: `2_place.tcl:808` pins the floorplan and `:876` pins the power
plan, with the incident that motivated it recorded at `:872-875` — a run hashed the power plan
thirty-eight minutes late, one minute after another session had edited it, and wrote the wrong hash
into the provenance file as though it had built the grid.

**What to add.** The runner pins each step file with `prov_pin` at the moment it sources it, and
emits per step:

```
step.<id>.file / .sha256 / .contract / .seam / .order / .lib
step.<id>.status         applied | clean | deviated | refused | skipped | unmeasured
step.<id>.examined       <N>
step.<id>.rejected       <bucket>=<n> ...
step.<id>.sites          <N>
step.<id>.expect         <lo>..<hi>
step.<id>.tolerate       <lo>..<hi>
step.<id>.applied_at     <coord> <coord> ...
step.<id>.verify         passed | declined:<why>
step.<id>.skip_reason    <VAR>=<value>
step.<id>.probe.<seam>   examined=<N> sites=<N>
```

Every field is a value or `UNVERIFIED:<reason>` — provenance.tcl's existing rule (`:46-49`), which
exists so that "a missing measurement must never read as agreement." The runner also writes one
human artefact per step at `reports/design_steps/<seam>.<id>.txt`, carrying the census, the sites
with coordinates, the nearest rejected candidate, and the verify result. Today the equivalent is one
whole-hook `check_drc` report written by hand (`post_powerplan.tcl:154-155`), whose own comment
concedes the alternative is an inference: "it must have worked, the signoff report is clean."

**How a reviewer verifies it, from artefacts alone.** Four independent legs, no shell on this box
required:

1. `reports/<stage>_manifest.txt` names every step that ran, with sha256 and status.
2. The run's pinned-inputs manifest independently hashes the same bytes. On the current run,
   `PRE_RUN_MANIFEST.txt` (schema 1, sectioned: pinned content, roll-up, tech pack, unpinned inputs,
   RTL provenance) already carries md5 lines for `pinned/genus-innovus/scripts/` both ECO scripts
   and for all four `pinned/eth-chiplet/hooks/` files. Two hashes, two algorithms, two mechanisms,
   two moments — they must agree.
3. `make evidence` folds the ledger into `ASIC/eth-chiplet/evidence/<RUN_TAG>.json` as a
   `design_steps` array beside the existing `known_bad`, `not_measured` and `require_measurable`
   arrays. A `deviated` step with no matching declaration makes the bundle ungradeable.
4. The per-step report file is the primary record, and it is inside the run directory, so it is
   captured by whatever captures the run.

One caution the evidence flow already documents and which applies to the ledger too: everything the
flow proves is written into a gitignored directory (`evidence.mk:38-44`), so the ledger is only
evidence once `make evidence` has bundled it. That is the reason the ledger feeds the bundle rather
than replacing it.

---

## 8. Versioning

The toolkit is pinned by commit and consumed as a submodule, and there is a tag lineage
(`v0.1.0-27-gb1a903a`). A step should **not** name a toolkit commit or tag. It should name the
*contract* it was written against, for the same reason `flow/common/provenance.tcl:95` versions its
schema rather than its file: what a consumer depends on is the meaning of the fields, not the
identity of the producer.

**`ASIC_STEP_CONTRACT`** — one integer, published by the toolkit, declared by every step as
`-contract N`. Bump it when a callback signature changes, when a status value changes meaning, or
when a seam's DB guarantee changes. Do **not** bump it for an additive field. `provenance.tcl:73-94`
is worth reading before the first bump: it is a worked example of deciding *not* to bump, and of why
an unappealable wall between every run already on disk and every run after it can be worse than a
weaker, waivable refusal.

Mismatch policy:

| case | action |
|---|---|
| step contract **>** toolkit contract | **refuse at load**, naming both numbers. The step was written against guarantees this toolkit does not make. |
| step contract **<** toolkit contract, still supported | run; record `step.<id>.contract_lag`; one `warn` per stage listing every lagging step |
| step contract **<** the toolkit's declared minimum | **refuse at load**, naming the change and pointing at the migration note |
| step names a seam this toolkit does not have | **refuse at load** — never a skip. The current failure mode for that mistake is silence at run time (`asic-flow-check:402-407`) |
| step names a library version the design does not provide (`-lib pg_geom@1`) | refuse at load. The library already carries `PGG_LIB_VERSION` (`pg_drc_geom_lib.tcl:28`); this makes it load-bearing |

The toolkit pin itself stays where it is and is already checked: `ci/check-pins.sh:198-201` verifies
every submodule is at its recorded commit, and its reachability check (`:323-394`) refuses a pin no
remote carries. Nothing here duplicates that.

One naming caution before adding helpers: `flow_utils.tcl:43-53` asserts that none of its helper
names already exists as a command and errors if one does, and the comment records that this fired in
anger — a helper named `fail` shadowed an Innovus builtin and aborted a route stage two and a half
hours in. `design_step`, `design_file`, `design_lib`, `step_site`, `step_note` and `step_dir` go into
that guard list in the same commit that introduces them. Note also that `scripts/asic-flow-hooks`
is already taken, by the *git*-hook installer (`mk/hooks.mk:27-59`) — the standalone entry point
proposed below must not be called `asic-flow-steps` if that collides either.

---

## 9. Migration

Nothing here requires a big-bang change, and the first step requires **no toolkit change at all**.

### Step 1 — the runner, design-side, behind the existing hook *(smallest thing that pays)*

Write the runner as `ASIC/eth-chiplet/steps/_runner.tcl`. Move the three edits into
`ASIC/eth-chiplet/steps/` as declarations wrapping the existing `seek`/`apply` procs — the procs
themselves change very little, because the loop the runner takes over is already there
(`pg_drc_post_route_edits.tcl:708-777` is that loop, written by hand, twice). Reduce
`hooks/post_powerplan.tcl` from 156 lines to roughly four:

```tcl
source [file join $::env(ASIC_DESIGN_STEPS_DIR) _runner.tcl]
design_steps_load
design_steps_run post_powerplan
```

What that buys on day one, all of it measurable against the current tree:

- the four copies of the path-climb boilerplate go, and with them the defect in the appendix;
- `examined` versus `sites` becomes expressible, so the widened `{0 2}` / `{0 3}` ranges
  (`post_powerplan.tcl:142-143`) can be replaced by a real CLEAN verdict rather than a suppressed
  refusal;
- each of the three edits gets an id, a status and its own report file;
- `EVP_NO_PG_DRC_EDITS` becomes a recorded skip;
- it is revertible by restoring one file.

Prove the runner the way this repo proves its other gates: a self-test that fires every outcome in
both directions. `floorplan-hazards.mk:7` and `:159` (`floorplan-hazards-selftest`, ~52 s, no
licence) and `evidence.mk:8` (`evidence-selftest`) are the pattern; `ci/contract.sh:81-90`'s arming
model is the vocabulary. Specifically: prove that a step whose seek returns zero *with* a non-zero
census reads CLEAN, that the same step with a zero census reads UNMEASURED, and that a step whose
`-discriminates` bucket is empty refuses. A runner that cannot demonstrate its own UNMEASURED path
is the thing it exists to prevent.

### Step 2 — promote the runner into the toolkit, unchanged

`ASIC/asic-toolkit/flow/common/design_steps.tcl`, sourced by `flow_boot`. Add the six helper names
to the collision guard. Add `export ASIC_DESIGN_STEPS_DIR := $(DESIGN_STEPS_DIR)` beside
`ASIC_HOOKS_DIR` (`mk/flow.mk:374`) with `DESIGN_STEPS_DIR ?= $(ASIC_DIR)/steps` beside
`HOOKS_DIR ?= $(ASIC_DIR)/hooks` (`:246`). The toolkit already documents this promotion route —
`PROMOTION_FROM_NANOSOC_ETH.md` sits at its root.

### Step 3 — the seam table, single-sourced

Add the machine-readable seam table (§6). Point `asic-flow-check` at it, replacing its hardcoded
`HOOKS` and `STEPS` lists (`:38-48`) and fixing the two known drifts in the same move. Render the
documentation tables from it.

### Step 4 — the three new seams

`post_floorplan`, `pre_stream`, and the make-layer `pre_place_files`. Each is additive: an absent
step file at a new seam costs nothing, exactly as an absent hook does today
(`flow_utils.tcl:335-337`).

### Step 5 — provenance and evidence

`prov_step` fields and `steps_run` in the stage manifest; a `design_steps` section in
`ASIC/eth-chiplet/evidence/<RUN_TAG>.json`; `make evidence` refuses to grade a bundle carrying an
undeclared deviation.

### Step 6 — cross-design sharing, *only if the reuse audit finds a real case*

`ASIC_DESIGN_STEPS_PATH`, copying `flow_step`'s two-entry precedence and its refusal to merge
(`flow_utils.tcl:371-388`). Not before.

---

## 10. Questions this proposal is waiting on

For the **seam audit**: is `post_powerplan` at `2_place.tcl:879` reached on a `PLACE_FROM_DB`
resume? It sits inside the `PLACE_FROM_DB eq ""` guard opened at `:870`, which means a resumed run
skips the power plan *and* every step registered there. If a resume can reach stream-out, the seam
table must record which seams a resume bypasses, and the runner must report steps it did not run for
that reason rather than omitting them.

For the **seam audit**: does any seam other than `post_route` have an engine-side guard on what a
hook may change? §3.5's `-changes` bracket is proposed as a generalisation of the one at
`4_route.tcl:1979`; if others exist, the declared object classes should be reconciled with them
rather than layered on top.

For the **reuse audit**: are the `pgg_*` primitives (`pg_drc_geom_lib.tcl`, 22 procs, none of which
names a rule, a layer or a coordinate) design-specific at all, or are they a *toolkit* library that
happens to live in a design? If the latter, they are a promotion candidate in their own right and
§9 step 6 arrives earlier than planned. The library's own header argues it exists to reproduce two
operations the signoff deck performs and the P&R tool does not expose (`:5-23`) — that reasoning is
not chiplet-specific.

For the **reuse audit**: the two chiplets in this family pin divergent lineages of shared IP, so a
step shared by path would be shared by *content* only if both trees carry the same bytes. Any
sharing mechanism needs the version handshake of §8 to be load-bearing, not advisory.

---

## Appendix — a live defect found while reading the case

`ASIC/eth-chiplet/hooks/post_powerplan.tcl:68` reads:

```tcl
unset _fpg_hook_dir _fpg_asic_dir _fpg_check
```

`_fpg_asic_dir` is **set nowhere** — not on either branch of the resolution block at `:46-51`, and
not by `check_fp_pg.tcl`, which is sourced at `:67` (grep for the name in that file returns
nothing). `_fpg_hook_dir` is set only on the climb branch (`:49`), so it is also absent whenever
`LEGACY_ASIC_DIR` is set — which is the pinning path, and the path the current run dir's `pins.mk`
takes.

Tcl's `unset` raises on a missing variable unless given `-nocomplain`. Verified locally:

```
$ tclsh
% set _fpg_hook_dir x ; set _fpg_check y
% unset _fpg_hook_dir _fpg_asic_dir _fpg_check
can't unset "_fpg_asic_dir": no such variable
```

`flow_hook` catches and **re-raises** (`flow_utils.tcl:341-348`), so this aborts the place stage —
on both resolution branches, every run, immediately after the floorplan PG gate passes. It has not
fired yet only because the run currently on disk pinned its hooks before commit `c9d30a6` was
written.

I have not fixed it: this task is a proposal and the brief forbids touching the hooks. It is
included because it is the argument for §2's decision C2 and §5 in a single line of code — the
boilerplate that exists only because every hook resolves its own paths and cleans up its own leaked
globals is where the defect lives, and a runner that sources each step in its own scope cannot
produce it.
