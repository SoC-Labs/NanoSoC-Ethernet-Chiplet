# gap-lvs / still-real

> **THE FILENAMES ON DISK CARRY A `.__fixture__.txt` SUFFIX.** This probe
> searches BY EXTENSION, and the pre-commit vendor guard refuses to let any
> `.cdl`, `.lef`, `.lib` or `.sp` be tracked whatever it contains — deliberately,
> by extension, so that "read it, it is synthetic" is not an argument it can be
> talked out of. `scripts/ci/signoff.py prove` strips the suffix when it stages
> the sandbox, so `tcbn65lp_stub.cdl.__fixture__.txt` on disk is `tcbn65lp_stub.cdl` where the
> probe looks. **Every path in this note is written as the probe sees it.** If
> you add a file here, name it `<what the check reads>.__fixture__.txt` and
> nothing else — the convention, and the three guards that stop it from quietly
> doing nothing, are in `ci/fixtures/README.md`.


The `lvs` gap is **not** "no LVS tool" and **not** "no LVS evidence". Both of
those are false here: three LVS tools are installed and idle, the decks are on
disk, a working harness exists, and the `lvs-missing-connection` STAGE grades a
real discrepancy list on every run. The gap is narrower and is about SOURCE
DATA: there is no transistor-level CDL for the standard-cell, IO or bond-pad
libraries, so full-chip LVS cannot be closed. The refuting artefact is therefore
**the CDL arriving** — nothing about a tool, a licence or a stage.

This half stages the site as it is. `find ${TSMC_65_HOME} -maxdepth 6 -size +1k
\( -name 'tcbn65lp*.cdl' -o -name 'tphn65*.cdl' -o -name 'tpbn65v*.cdl' \)
| grep -q .` must exit 1.

Everything here is synthetic. There is no vendor content in this tree and there
must never be: this is a public repository, and the gap is *about* vendor
collateral. The library prefixes in the filenames are the ones already written
in `ci/signoff.yaml`; the file bodies are invented.

## Decoys

| path | why it must not refute |
|---|---|
| `pdk-stand-in/pdk-root/cdl/unit.cdl` | the one CDL this site actually has, in stand-in form. Right extension, wrong name, and under 1 kB. |
| `pdk-stand-in/pdk-root/cdl/tcbn65lp_stub.cdl` | **right name, under 1 kB.** This is the decoy that earns the `-size +1k` clause: a placeholder in the right place with the right name must not close a procurement gap. |
| `pdk-stand-in/pdk-root/lef/tcbn65lp.lef` | **right library, over 1 kB, wrong view.** LEF abstracts are exactly what this site has and exactly why the gap exists. |

## What this pair does not prove

`_sandbox_env()` sets `TSMC_65_HOME=.` inside a prove sandbox, so the probe
searches this tree instead of the real PDK — deterministically, on every host. That pins the probe's *name*, *size* and *extension* clauses and says
nothing about whether it looks in the right PLACE. That clause cannot be
fixtured in a public repository and is the residual risk.

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
