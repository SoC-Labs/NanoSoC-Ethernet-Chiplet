# Fixtures for `scripts/ci/route_message_census.py`

## They are EXTRACTS OF REAL LOGS, not invented specimens

Every line in every fixture here was produced by Innovus on this site and is
copied verbatim, with one transformation: **absolute site paths are replaced by
`${CHIPLET_HOME}` or `${SITE_PATH_WITHHELD}`.** The repository is public and its
vendor guard rejects absolute site paths in tracked content.

That matters because of this project's own fixture-realism rule: a gate proven
only against fixtures is proven to match its FIXTURES, not real tool output. The
shapes here cannot drift from real tool output, because they *are* real tool
output. The one thing to re-check if the tool is upgraded is whether NanoRoute
still writes `#WARNING (ID) text` rather than `**WARN: (ID): text` — the whole
gate turns on that distinction.

The source logs live under `ASIC/eth-chiplet/build/`, which is **gitignored**
(`.gitignore:207`), so they cannot be checked in and cannot be relied on to
survive. That is itself an instance of the problem this whole work item is
about, and it is why these extracts exist.

## Derivation

Each fixture keeps only the lines the gate reads: the `Options:` header naming
the stage script, the routing-section markers, every `#SEVERITY (ID)` router
message, the open-nets decline, and the not-globally-routed finding. Everything
else is dropped. Line counts are therefore much smaller than the sources.

| fixture | source log | source shape | expected verdict |
|---|---|---|---|
| `pass/innovus_route_clean.log` | `gdsrun-20260822-halo/work/innovus.log2` (25,113 lines) | 16 routing markers, 31 router messages, 0 unrouted, 0 open | **PASS** |
| `fail-unrouted-net/innovus_route_rzG.log` | `gdsrun-20260823-rzG/work/innovus.log2` (27,202 lines) | 24 routing markers, 37 router messages, **1 unrouted net, 1 "4 open nets"** | **FAIL** |
| `fail-open-nets/innovus_route_opennets_only.log` | the same rzG log, with the `is not globally routed` line **removed** | 24 markers, 36 router messages, 0 unrouted, 1 "4 open nets" | **FAIL** |
| `not-measured-abort/innovus_route_aborted.log` | `m5off6/work/innovus.log2` (2,917 lines) | **0 routing markers, 0 router messages** — session aborted in `tech_load` | **NOT-MEASURED** |

### Why each one is in the set

**`pass`** is the control that makes the fail arms mean something. It is not an
empty file: it carries 31 real router messages, so when the gate reports zero
unrouted nets over it, that zero was *measured*. A pass fixture with no router
messages at all would be indistinguishable from a parser that matched nothing.

**`fail-unrouted-net`** is the actual defect. `gdsrun-20260823-rzG` is the stream
the foundry graded and the one that carries the three bare macro pins. This
fixture is the exact evidence that existed on 23 August and was never read.

**`fail-open-nets`** exists because the rzG log trips *both* assertions at once,
and a gate that passes a fixture tripping two rules has not proven either rule
alone. With the `NRDR-27` line deleted, only the open-nets decline remains, and
the gate must still fail. Without this arm, the open-nets rule could be dead code
and the selftest would still be green.

**`not-measured-abort`** is a real route session that died in `tech_load`
because a site environment variable was unset. It has zero unrouted nets in the
same sense that an unopened box has no contents. A naive `grep -c 'is not
globally routed'` returns 0 and scores it clean. This project has shipped at
least six zeros that measured nothing; this fixture is what stops the seventh.

## Regenerating

The fixtures were cut from the sources by a short extraction pass (keep the
lines the gate reads, scrub site paths). If a source log is still on disk the
extraction is reproducible; if it has been cleaned up, the fixture here is the
only surviving copy, which is the point.

Do not hand-edit a fixture to make a gate pass. If the gate needs to change,
change the gate and re-cut the fixture from a real log that exhibits the new
shape.

---

## The DERIVED arms — added after mutation testing, and labelled

Round 1 of mutation testing showed the observed fixtures above proved fewer
rules than they appeared to: disabling the headline unrouted-net rule left the
selftest green, because the rzG fixture trips the open-nets rule at the same
time. Three further arms isolate one guard each. **None of these shapes has
ever been produced by the tool on this site**, and each says so in its own
first five lines.

| fixture | derivation | isolates | expected |
|---|---|---|---|
| `fail-unrouted-net-only/` | rzG extract, `There were 4 open nets` line deleted | the unrouted-net rule alone | FAIL |
| `not-measured-no-markers/` | clean extract, routing-marker lines deleted | the vacuity control alone | NOT-MEASURED |
| `not-measured-shape-drift/` | clean extract, router-message lines deleted | the shape-drift guard alone | NOT-MEASURED |
| `pass-zero-open-nets/` | clean extract + one `There were 0 open nets` line | the `> 0` predicate | PASS |

`There were 0 open nets` is the only text in this directory that no real log on
this site contains: every occurrence in the build tree reads `There were 4 open
nets`, 16 of them. It is here to prove the gate does not fire on a router
reporting no open nets, and it is flagged rather than passed off as observed.

## Mutation result

8 mutations, 8 caught, each by a different arm. The table is in the script's
own header so it travels with the code. Re-run it whenever a rule changes:
a fixture set that catches fewer than all of them is a fixture set that has
stopped proving something it used to.
