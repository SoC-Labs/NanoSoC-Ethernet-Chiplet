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

---

## The ECHO PAIR — added 2026-08-26, and both halves are real bytes

| fixture | source log | source shape | expected verdict |
|---|---|---|---|
| `pass-echoed-continuation/innovus_route_echoed_body_rc1.log` | `gdsrun-20260826-rc1/work/innovus.log2:24444-24554` plus that log's own `Options:` line, 3 routing markers and 5 router messages | one complete echoed `try_step` command: **1 prefixed line, 107 BARE continuation lines**, two of them quoting `There were 4 open nets` and `NRDR-27 ... is not globally routed` | **PASS** |
| `fail-real-after-echoed-continuation/innovus_route_echoed_body_then_real.log` | byte-identical, plus `gdsrun-20260824-valid4/work/innovus.log2:25200` and `:25204` appended | the same echoed block followed by the two **genuine** router messages | **FAIL** |

### Why the pair, and why the old echo arm was not enough

`pass-echoed-source-only` proved that a line beginning `@file <n>: ` is not the
tool speaking. That is half the truth. **Innovus prefixes only the FIRST line of
each complete Tcl command; the remaining lines of a multi-line command are
echoed verbatim, with no prefix at all.** Measured in the same rc1 log:

```
6414:@file 1459: proc pnr_session_logs {dir} {
6415:    set out {}                                <- no prefix
...                                               <- 7 bare lines, src 1460-1466
6422:@file 1467:                                  <- next command, src 1467
```

`1459 + 1 prefixed + 7 bare = 1467`. The arithmetic closes exactly.

So a filter keyed on `^@file` caught every top-level comment — each is its own
one-line command — and kept every line of every proc body and every braced
block. `4_route.tcl`'s regwire-repair comment, which quotes both router messages
verbatim *to document the rzG defect*, lives inside a braced `if`. It was echoed
bare, read as tool output, and hard-failed a run whose cache bit 123 is routed
both ways (RDATA 24 wires / 5 vias, WDATA 23 / 9). The `...` in
`Net ...RAMCLD0WDATA_123` is the tell: the tool prints the full hierarchical net
name and never an ellipsis.

The replacement treats **the command, not the line**, as the unit: an `@file`
line opens a region, and the region runs until the accumulated text is a
complete Tcl command — the same question the tool's own reader was waiting on,
answered by `info complete` in the Tcl gate and by `_tcl_complete` in the Python
one. Measured 2026-08-26 over all 63 non-verbose session logs under 6 MB on this
site, that drops **8 findings across 4 logs and adds none**, and all 8 are the
`...` comment text. The two implementations agree line for line: 11,136 echoed
of 26,765 on rc1's route log, 10,323 of 27,497 on valid4's.

**The FAIL half is the load-bearing one.** A region that over-runs its command
would swallow real output, and the gate would go quiet on exactly the defect it
was built for. That arm is byte-identical to the PASS arm up to its last two
lines, so nothing but the region boundary separates them.

### The runaway guard is NOT a fixture here, deliberately

Tripping it needs an echoed region longer than `ECHO_MAX_RUN` (5,000 lines;
longest real region measured over 63 logs on this site is 1,692, in
`bscan-probe/work/innovus.log2`, and no log runs away). A 5,000-line file of synthetic
filler is precisely the invented specimen this document exists to keep out of
this directory, so `--selftest` generates that log in a temp dir instead and
says so in its output. The same guard is proved in the toolkit with the limit
lowered: `ASIC/asic-toolkit/test/common/router_message_gate.test`,
`unterminated-echo-region-is-notmeasured`, mutation `router.echo-runaway-guard`.

## Mutation result

11 mutations, 11 caught, each by a different arm. The table is in the script's
own header so it travels with the code. Re-run it whenever a rule changes:
a fixture set that catches fewer than all of them is a fixture set that has
stopped proving something it used to.

M11 is the one to read. With the runaway guard removed, a log whose echoed
region never closes reads as a clean PASS while carrying a genuine `NRDR-27`
twelve lines further down — the echo tracker without its guard is a bigger hole
than the false positive it fixes.

## A sibling fixture set, for the other half of the same false red

The same run also hard-failed on its `check_drc` report, for an unrelated
reason: Innovus writes no `Total Violations` trailer when a design is clean.
Those fixtures are real check_drc reports rather than session logs, so they live
in the toolkit beside the parser they prove —
`ASIC/asic-toolkit/test/fixtures/route_drc/`, with its own PROVENANCE.md.
