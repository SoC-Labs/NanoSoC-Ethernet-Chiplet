# gap-lvs / refuted

> **THE FILENAMES ON DISK CARRY A `.__fixture__.txt` SUFFIX.** This probe
> searches BY EXTENSION, and the pre-commit vendor guard refuses to let any
> `.cdl`, `.lef`, `.lib` or `.sp` be tracked whatever it contains — deliberately,
> by extension, so that "read it, it is synthetic" is not an argument it can be
> talked out of. `scripts/ci/signoff.py prove` strips the suffix when it stages
> the sandbox, so `tcbn65lp.cdl.__fixture__.txt` on disk is `tcbn65lp.cdl` where the
> probe looks. **Every path in this note is written as the probe sees it.** If
> you add a file here, name it `<what the check reads>.__fixture__.txt` and
> nothing else — the convention, and the three guards that stop it from quietly
> doing nothing, are in `ci/fixtures/README.md`.


The day the transistor-level netlists arrive — the event the gap calls
"PERMANENT AS OF 2026-08-17" because the Back-End packages "will not be
obtained". Permanent-by-decision is not permanent-in-fact, and this is the probe
that would notice the decision being reversed. `find ... | grep -q .` must exit
0, `signoff.py lint` must go red, and the declaration must be rewritten.

**One file separates this half from `still-real`:**
`pdk-stand-in/pdk-root/cdl/tcbn65lp.cdl`, over 1 kB, matching the first of the three name
alternatives. Every decoy is unchanged, so the pair isolates one clause.

`tphn65*.cdl` and `tpbn65v*.cdl` — the IO and bond-pad libraries — are **not**
exercised by this fixture. Two of the probe's three alternatives are therefore
unproven, and that is a real limit of this pair, stated rather than papered over
by stuffing all three into one case: a fixture that trips three clauses at once
pins none of them. It also matters for a reason specific to this gap: the Arm
sc12 library ships both CDL and GDS and has no IO or bond-pad library, so
"standard cells arrived" is precisely the case that does **not** close full-chip
LVS. If this fixture ever needs to grow, the honest growth is a second refuting
case for the IO library, not more files in this one.

Everything here is synthetic and must stay that way. The netlist body names
devices `SYNTH_NMOS`/`SYNTH_PMOS` and cells `CELL_SYNTHETIC_*`, which correspond
to nothing in any process or library. **If a real CDL ever lands on this site, do
not copy any of it into this fixture.** The gap closes by `lint` going red
against the real PDK.

---

## THE DIRECTORY DEPTH HERE IS LOAD-BEARING. Read this before moving a file.

This probe is a `find` with `-maxdepth 6`, and `${TSMC_65_HOME}` reaches it from
two different places:

* **`prove`** runs it with `TSMC_65_HOME=.` inside the sandbox (see
  `_sandbox_env()`), so the search root is this fixture and the collateral must
  be **within** `-maxdepth 6`. Here it is at depth **4**.
* **`lint`** runs it from the REPOSITORY ROOT with the operator's own
  environment. On any host with no PDK installed `${TSMC_65_HOME}` is unset, the
  expansion is empty, and GNU `find` falls back to `.` — **the whole working
  tree, this fixture included.** So the collateral must be **beyond**
  `-maxdepth 6` counted from the repository root. Here it is at depth **8**.


**This is not decoration. It was MEASURED.** The first cut of the
`gap-dynamic-ir-drop` fixture put its synthetic `.sp` at repo depth 7, inside
that probe's `-maxdepth 8`, and `signoff.py lint` immediately reported

    dynamic-ir-drop   STALE   refuted_by SUCCEEDED — this gap no longer exists

over a gap that is wide open, because the only thing the probe had found was the
fixture written to prove it could notice. A gap fixture that refutes its own gap
is worse than no fixture: it hands a reader a false STALE and invites the
declaration to be deleted.

**If you move, rename or add anything under `pdk-stand-in/`, redo the
arithmetic**, then run BOTH `scripts/ci/signoff.py prove` and
`scripts/ci/signoff.py lint` — prove alone cannot see this failure, because
prove never runs the probe from the repository root.

The proper fix is a probe that refuses to search anything when
`${TSMC_65_HOME}` is unset, rather than silently searching the working tree.
That is written up, with the exact replacement text, in
`ci/fixtures/PROPOSED_GAP_PROBES.yaml`. It is not applied here because
`ci/signoff.yaml` is written by other sessions. Once it is spliced in, this
depth constraint stops mattering — and the fixtures keep working, because
`prove` sets `TSMC_65_HOME=.` rather than unsetting it.
