# Physical implementation — start here

The entry point for the physical implementation team. It says what the chiplet
**is**, what is **proven**, what is **yours to decide**, and the handful of
non-obvious facts that will cost you a day if you learn them the hard way. Every
claim links to the doc that backs it.

## What this is

`nanosoc_eth_chiplet` = a `nanosoc_multicore_soc` (two Cortex-M0+ cores, ethernet
subsystem, PHC/PTP) + `tidelink_top` (the die-to-die link) + a TideChart shim,
wired together so a CPU on one die can reach memory on another die over an
8-lane source-synchronous link. It is the shipping integration top; the bonded
chip is `nanosoc_eth_chiplet_chip`.

## Get the source and sanity-check it

```sh
git clone https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet.git
cd NanoSoC-Ethernet-Chiplet
./scripts/bootstrap.sh      # 42 submodules, 8 levels deep — NOT `git clone --recursive`
source set_env.sh
make hooks                  # install the pre-commit / pre-push vendor guards — do this once
make check                  # vendor-check + chip-boundary + lint — no EDA license needed
make elab                   # full structural elaboration — needs VCS
make regress                # every data-plane sim proof, one table — needs VCS
```

`make check` is the fast static gate (no license). `make regress` is the dynamic
gate: it runs every simulation proof below — the two decode guards, the tidelink
pair, and the two-real-SoC write+read+burst — and prints one pass/fail table
(`make regress ARGS=--quick` skips the two-SoC long pole). `scripts/regress.sh`.
`make elab-strict` is the pre-synthesis gate: `xrun -hal` over the whole
integration, failing on a same-clock procedural **multi-driver** (`MLTDRV`) — the
class `fc_shell`/Genus reject but VCS and Verilator both pass. Run it before
handing RTL to synthesis and after any submodule roll (that is how the last one
arrived). `docs/ELAB_STRICT_FINDINGS.md`.

`scripts/bootstrap.sh` rather than `git clone --recursive` because one submodule
*inside* TideLink is still declared over SSH; the script rewrites it to HTTPS for
the fetch. See the README.

## The one gate that runs on every pull request

**This repository is public. The TSMC PDK licence does not permit reproducing
their collateral.** Everything else in CI is dispatched or nightly; the vendor
gate is the only thing that runs automatically on a pull request, because it is
the only failure here that cannot be undone by a follow-up commit.

### CI is DETECTION, not prevention. Read this before relying on it.

**Every job below starts after the push.** By the time a runner is allocated the
objects are already on GitHub and already fetchable by SHA, by anyone, whether or
not any ref points at them — and a fork or a mirror taken in that window keeps
them regardless of what you do next. A red tick buys you a redaction commit; it
does not unpublish anything, and `git rm` moves a blob out of the tip and out of
nothing else. For a licence breach that ordering is the whole story: what CI
gives you is **incident timing** — you learn today rather than at the next audit.

The only layer that prevents rather than detects is the **pre-push hook**, which
runs before the bytes move. `make hooks` installs it; do it once per clone. That
is not a nicety, it is the difference between a mistake and a disclosure.

**As of the currently pinned `ASIC/asic-toolkit` commit that hook does not exist
yet** — the submodule carries no `hooks/` directory at the pin, so `make hooks`
fails with the message that says so. Until the toolkit lands them and this
repository rolls the pin forward, **there is no preventive layer at all**, only
the detection below. Run `make vendor-check` by hand before any commit that adds
a file.

### Which check enforces what

`.github/workflows/vendor-guard.yml`, two jobs, both blocking. Two *scanners*,
which is not the same list — the hosted job runs both of them:

| Check name | Runs on | Trigger | Scanners it runs |
|---|---|---|---|
| `vendor-collateral-gate` | GitHub-hosted `ubuntu-latest` | **every push and every PR** | chiplet scanner (check 1 only) **+ toolkit content scanner** |
| `vendor-collateral-gate-pdk` | self-hosted `soclabs-pdk` | push, dispatch, 01:30 nightly | chiplet scanner, **both halves** — adds the verbatim-vendor-text scan |

| Scanner | Where | Corpus / rules | Needs |
|---|---|---|---|
| `scripts/ci/check_no_vendor_collateral.sh` **check 1** | this repo | tracked `*.lef` only, by content SHA and by size (>64 kB) | nothing |
| `scripts/ci/check_no_vendor_collateral.sh` **check 2** | this repo | any file of any type, matched against runs of **verbatim** text from the installed PDK | a readable PDK at `$TSMC_65_HOME` |
| `ASIC/asic-toolkit/ci/check-vendor-collateral.sh` | submodule | **extension** (~20 collateral suffixes incl. `.tlef .lib .captable .map .gds .cdl .spef`), **size**, content SHA, and seven text rules — transcribed LEF/Liberty values, GDS layer/datatype pairs, revision-coded release names, absolute site paths, captured licence output | nothing |

**Read the first row again: check 1's pathspec is `*.lef`, and that does not match
`.tlef`.** Until the toolkit scanner was added, the hosted job — the one that is
about to become a required status check — enforced *only* that first row.
Measured on a scratch tree holding three ~244 kB invented vendor-shaped files
tracked as `.tlef`, `.lib` and `.captable`: the chiplet scanner exits 0, on a PDK
host as well as a hosted one, because check 2 catches copying and those bytes
were invented. The toolkit scanner exits 1 on the same tree. Neither scanner is
a superset of the other, which is why both run.

The chiplet scanner is driven through `scripts/ci/vendor_guard_report.sh`, which
classifies which of its halves actually ran and says so in the job summary. **A
green `vendor-collateral-gate` still does not mean the tree is clean of verbatim
vendor text** — check 2 needs a PDK and a hosted runner has none, so there it is
skipped and the summary says so in as many words. `vendor-collateral-gate-pdk` is
the job that looks for that; it fails rather than passing if the PDK is missing,
and also if the PDK is present but unreadable (which would otherwise let the scan
compare your tree against an empty corpus and report clean).

The PDK job is deliberately absent from the `pull_request` event: this repo is
public, and running a fork's branch on a lab host that has the PDK, the IP trees
and the licence servers mounted is how a self-hosted runner is lost. Pushing the
branch is what scans it at full strength.

**`ASIC/asic-toolkit` is a private repository, so the hosted job needs the
`SUBMODULE_TOKEN` secret** and fetches that one submodule by path. If it cannot,
**the job fails** — it does not carry on with the `*.lef`-only scanner, because a
gate that quietly degrades to the weaker of its two scanners is the defect, not
the mitigation. One consequence, stated plainly: GitHub withholds secrets from a
pull request opened **from a fork**, so this job goes red there naming that as
the cause, and a maintainer has to push the branch to this repository to get it
scanned. `make vendor-check` runs the same two scanners locally, in the same
order, for the same reason — a local gate that is greener than the PR check is
worse than no local gate.

### The toolkit scanner on this repository today

Not a threat and not a projection — measured, at the currently pinned toolkit
commit, on the tree as it stands. Recorded here rather than tuned away, because
tuning a scanner until it agrees with the repository is how the `*.lef` gate
came to mean nothing:

| Rule | Findings in the tree at HEAD | What it is, on inspection |
|---|---|---|
| `file.ext` | 3 | the three tracked `ASIC/genus-innovus/logos/*.gds` — **this project's own logo artwork**, caught because `.gds` is collateral by extension. A false positive here, and the clearest candidate for a waiver. |
| `value.lef` | 46 | a LEF or Liberty keyword standing beside a decimal, concentrated in the two power-grid Tcl scripts and the tapeout notes |
| `value.lefwin` | 6 | a table keyword within two lines of a multi-significant-figure number |
| `value.map` | 2 | a GDS layer and datatype pair |
| `value.libtag` | 5 | a provenance annotation, in the bracketed source-tag form, on a line carrying a number |
| `ident` | 38 | revision-coded release names |
| `path` | 97 | absolute site paths, in `ASIC/common.mk`, the config and eval Tcl, and the workflow files |

**197 findings, 7 failing gates, exit 1** for the tree as a whole. The pre-push
hook charges only what a push ADDS to what the server already has, so the number
that blocks a push is far smaller than this backlog and moves with the branch.
Read that number from the hook, never from this table.

The row above describes the bracketed source-tag rule without reproducing the
tag itself, and that is deliberate rather than evasive: measured, the only
number in that row is this scanner's own finding count, so there is no value
here to redact and nothing is gained by writing a token the rule reads as a
citation. This file stays wholly inside the scanned corpus — no waiver, no
exemption — so a real citation written anywhere in it is still caught.

#### The value rules ask a question this table cannot answer

`value.lef`, `value.lefwin` and `value.libtag` match a SHAPE: a LEF or Liberty
keyword standing as a word beside a decimal. The scanner says so in its own
text, and says outright that a human must read the line — because the shape
cannot tell a number this design CHOSE from a number transcribed out of the
PDK. **That is a measurable question, and it must not be settled by eye.**

`scripts/ci/pdk_value_provenance.py` measures it. For each flagged line it asks
the installed technology LEF, and the vendor timing library that line's own
legend cites, whether the number is the value of that rule on that layer, or a
point on that library's own axis. A number that appears nowhere is this design's
own and the finding is a false positive; a number that IS the rule's value is a
disclosure and the line needs redacting. It prints PRESENT or absent and never
a vendor number, so its output belongs in a review, a commit message or an
allowlist reason. It runs controls on every invocation and fails when they do
not hold, because a probe that answers "absent" having parsed nothing looks
exactly like a clean result — and it distinguishes a bare small integer the deck
happens to carry in twenty places from a match that means something.

The toolkit deliberately cannot do this. Reading the PDK in order to compare
against it is itself the disclosure the toolkit exists to prevent. A check that
lives in the consuming project can, because it publishes nothing.

#### Triage is one of three things and never a fourth

Per finding: redact it, waive it with a written reason, or accept the block.
**Do not make it a fourth thing by narrowing a rule.** Do not reach for
`VENDOR_CHECK_BYPASS` either — it leaves a name and a reason in the log, which
is the point of it, and it is not a substitute for doing one of the three.

**There IS a chiplet-specific allowlist now, and it lives in the submodule.** An
earlier revision of this section said there was deliberately none, and that this
repository could not have one without forking the scanner into it. That is no
longer true, and it was always half true: the scanner's table is a hardcoded
shell variable, so a chiplet path is waived by adding an entry to
`ASIC/asic-toolkit/ci/check-vendor-collateral.sh` and bumping the submodule pin
— one table, not two copies that drift until they disagree about the same file.
**The waivers reach this repository only when the pin is bumped**, and until
then the local hooks (which read the submodule *working tree*) and CI (which
clones the *pinned* commit) will disagree about this repository — the local one
being the greener of the two, which is the direction that misleads. If the two
disagree, believe CI.
Every entry names one path and the one rule it waives, carries the measurement
that justifies it, and is reported by `vendor.allowlist.stale` the day that rule
stops firing on that path — which is the day the entry must be deleted. The
stale warning is the feature working; do not silence it.

**When it fires.** It prints the offending paths and never their contents. Two
things are certainly wrong, and neither is the check:

- **Do not delete or narrow the check, and do not add an allowlist to `scripts/ci/check_no_vendor_collateral.sh`.** There used
  to be one, and removing it is what armed this gate. A tracked vendor file is a
  licence breach, not a CI failure.
- **Ship the transform, not the result.** If a build needs a vendor file,
  generate it: read the PDK at build time and write into a gitignored directory,
  the way `ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py` and
  `ASIC/genus-innovus/scripts/gdsmap_derive.py` already do. `make -C ASIC -f
  common.mk pad-lef` produces the patched IO-driver LEF this way.
- Already committed it? `git rm --cached <path>` — and remember the blob is in
  the history, so say so rather than assuming the untrack is the end of it.

**The legitimate bypass** is narrow and it is by design: a vendor file sitting
**untracked** in your work directory is a WARNING, not a failure — a scratch copy
is not a publication. So keep it out of the index rather than looking for a flag.
For the local hooks, `git commit --no-verify` skips them, which is fine for a
work-in-progress commit on a branch you will rebase; it buys you nothing at the
PR, where `vendor-collateral-gate` has no bypass at all. If a file genuinely must
be published, that is a licensing decision for the repo owner, not a CI setting.

**Install the local hooks once per clone: `make hooks`.** CI catches collateral
after it is pushed; the hooks catch it before it leaves the machine, which for
licensed foundry data is the difference that matters. The hooks and their
installer live in `ASIC/asic-toolkit` (a submodule, so `make bootstrap` first);
`make hooks` only calls the installer and reports which hooks landed.

## What is proven

| Claim | How | Where |
|---|---|---|
| The top wires together consistently | `make elab` — 0 VCS errors, every port connected once | — |
| Every top port is bonded / tied / open exactly once | `make chip-boundary` — 111 ports, 46 pad cells | `PIN_MAP.md` |
| No combinational loops / latches / width bugs in our RTL | `make lint` (Verilator) | `LINT_FINDINGS.md` |
| **A memory transaction crosses between two REAL SoCs over the link** | `verif/g2_soc_pair` — die A `0x2F00_1000` → die B's real `shared_sram_0` `0x2D00_1000`, payload intact, CAM-off control | `G2_SOC_PAIR_STATUS.md` |
| **The data plane crosses BOTH ways** — peer read round-trip | `verif/g2_soc_pair` STAGE 2b — read back `0x2F00_1000` = written value across the link | `G2_SOC_PAIR_STATUS.md` |
| **Back-to-back bursts stay intact** | `verif/g2_soc_pair` STAGE 2c — 8-word write+read sequence, every beat verified | `G2_SOC_PAIR_STATUS.md` |
| The link trains between two real SoCs, firmware-free | same env, STAGE 1 | `G2_SOC_PAIR_STATUS.md` |
| The address survives the link end-to-end | RTL trace + G2 sim | `PEER_APERTURE_PROGRAMMING.md §8` |
| Link-down TX write is a 2-cycle ERROR, not a hang; APB stays reachable | `verif/chiplet_d2d_decode` tx-gate | `PHYSICAL_HANDOFF.md` |
| No comb cycle on back-to-back peer writes | `verif/chiplet_d2d_decode` hready-loop | `D2D_HREADY_LOOP.md` |

This is simulation. There is **no silicon and no timing/area/power** — see "open".

## The two integration adapters TideLink's `ahb_sub` required

Both were found by driving the real path (a real SoC master through the real
decode into TideLink) and both are in `nanosoc_eth_chiplet.sv`. Neither is
optional; a chiplet without them wedges or silently drops peer-write data. If you
refactor the peer path, keep them and re-run `verif/g2_soc_pair` +
`verif/chiplet_d2d_decode`.

1. **HREADY comb-loop break** (`hready_to_peer`). TideLink's `ahb_sub_hreadyout`
   depends combinationally on its `ahb_sub_hready` input, which fed back through
   the decode into a zero-register loop. Broken by withholding the peer's own
   HREADY contribution while it owns the data phase. `D2D_HREADY_LOOP.md`.
2. **Write-data alignment** (`d2d_ahb_m_hwdata_q`, 1-cycle delay). TideLink
   pipelines the `ahb_sub` address but samples write data live and sequences AW
   then W a cycle later, so a compliant AHB master's data is gone by the W beat.
   `G2_SOC_PAIR_STATUS.md` (Milestone 2 finding: RESOLVED).

## Document map

| Doc | For |
|---|---|
| `PHYSICAL_HANDOFF.md` | the original handoff: clock domains, reset topology, boundary classes, hard architectural constraints |
| `PIN_MAP.md` | the 50 bonded pads as a fill-in template |
| `POWER_DOMAINS.md` | the D2D power-domain analysis + recommendation (single domain for v1) |
| `RESET_ORDERING.md` | two-die reset ordering for the source-synchronous link |
| `PEER_APERTURE_PROGRAMMING.md` | how a CPU programs the CAM and reaches the peer; the bring-up register sequence |
| `D2D_HREADY_LOOP.md` | the HREADY comb loop and its fix |
| `G2_SOC_PAIR_STATUS.md` | the two-real-SoC proof + the write-data / read-pipe fixes |
| `CDC_FINDINGS.md` | the structural CDC pass + `constraints/nanosoc_eth_chiplet_cdc.sdc` for full sign-off |
| `ELAB_STRICT_FINDINGS.md` | the strict-elaboration gate (`make elab-strict`) — catches multi-drivers synthesis rejects |
| `LINT_FINDINGS.md` | lint tooling, the sanity harness, triaged findings |
| `PIN_POLICY.md` | which submodule pins are on default branches vs frozen |
| `patches/` | prepared upstream fixes (TideLink flist, nanosoc_gen `$()→${}`) — not applied |
| `UPSTREAMING_BLOCK_YAMLS.md` | where the two block-description YAMLs belong upstream |

## Yours to decide (open items)

- **Pin map**: pad-cell types, die sides, ball/bump assignment. `PIN_MAP.md`.
- **Power domains**: confirm single-domain for v1 or justify a split. `POWER_DOMAINS.md`.
- **Two-die reset ordering**: the pad-ring / power-sequencing asks. `RESET_ORDERING.md`.
- **Per-die straps**: `role_strap` is the only per-die differentiator while
  `nego_priority_i` is tied — decide whether to fuse it. `PIN_MAP.md`, `PHYSICAL_HANDOFF.md §3`.
- **CDC signoff**: a first structural CDC pass is done (`verif/cdc/run.sh`, HAL
  22.03 via `xrun -hal`) — 14 multi-clock instances, all component-internal, none
  at the wrapper boundary. The clock/async-group constraints now exist —
  `constraints/nanosoc_eth_chiplet_cdc.sdc` declares the primary clocks and the
  async cut at the D2D boundary (`sys_hclk` ↔ `{user_ref_clk, pad_clk_rx}`). HAL
  takes no SDC input, so to *complete* the `CLKDMN` analysis, fill the `[OWNER]`
  items in the SDC and run it through a dedicated CDC tool (SpyGlass — TideLink's
  flow). The same SDC seeds the ASIC STA constraints. `CDC_FINDINGS.md`.
- **Lint**: `make lint` (Verilator) covers our wrapper RTL — no non-waived
  findings. `LINT_FINDINGS.md`.
- **TideLink pin**: `tidelink` is frozen on a feature branch; roll it to `main`
  and apply `patches/0001` upstream. `PIN_POLICY.md`.
- **Peer READ round-trip**: **fixed** (2026-07-10), and the fix is now UPSTREAM.
  Both directions of the data plane cross between two real SoCs. The fix is a
  one-cycle read pipe-offset mask in TideLink's `ahb_sub`; it lives in TideLink
  itself (as the I2 `rd_pipe_r` mask, 2026-07-29) and the flow compiles
  `tidelink/src/rtl/tidelink_top.sv` directly.
  `G2_SOC_PAIR_STATUS.md` "read round-trip".

  It was originally carried as a chiplet-local override
  (`src/rtl/local_overrides/tidelink_top.sv` + `patches/0003-*.patch`) while the
  TideLink pin was frozen. That override was **retired on 2026-08-03** — it had
  outlived its reason and was silently pinning `tidelink_top` at 2026-07-10,
  discarding 23 later commits including the I1 `SELF_ARM_TRAIN_EN` fix proven on
  silicon and the RX-FIFO TWIN 2 chip-killer fix. `patches/0003` is obsolete.
  If you ever add another override to that directory, give it an expiry check
  against the submodule pin: the swap is by BASENAME, invisible at the point of
  use, and nothing makes it expire.

## Load-bearing gotchas

- **The bench straps can defeat the CDC gate.** `apb_debug_unlock_i` /
  `mask_hs_bypass_i` let software force `role_locked` on a dead recovered clock —
  the path to the a2l 6-word false-FULL wedge, **invisible in single-clock sim**.
  Decide their production defaults. `RESET_ORDERING.md §3`.
- **`link_active_o` is not "link carries data"** — it is `role_locked_o` renamed.
  It also gates the TX aperture internally; isolate it to 0 if you split domains.
- **`ROLE_CFG` survives `hresetn` but not `poresetn`; the CAM survives neither.**
  Re-program the CAM after any warm reset. Matters for retention if you split
  domains. `PEER_APERTURE_PROGRAMMING.md §2`, `POWER_DOMAINS.md`.
- **The peer aperture reaches exactly one remote 16 MB region** (`0x2F`→`0x2D`).
  The mailbox is reached by TideLink's native doorbell, not a remote AHB write.
  `PHYSICAL_HANDOFF.md §4.2`.
- **`make elab` does not evaluate the netlist** — it linked a combinational loop
  cleanly for a month. `make lint` and the `verif/` sims are the real checks.

## Suggested first steps

1. `./scripts/bootstrap.sh && source set_env.sh && make check` — confirm a clean
   tree. Then `make elab && make regress` if you have VCS — `regress` is the
   one-command proof that the whole data plane still crosses both ways.
2. Read `PHYSICAL_HANDOFF.md`, then `RESET_ORDERING.md`, then `POWER_DOMAINS.md`
   — in that order; each builds on the last.
3. Start `PIN_MAP.md` (pad cells + sides) and settle the power-domain decision.
4. Run your lint/CDC signoff on `nanosoc_eth_chiplet`, not on the components.
5. Resolve the reset-ordering and strap-default questions before committing a pad
   ring.
