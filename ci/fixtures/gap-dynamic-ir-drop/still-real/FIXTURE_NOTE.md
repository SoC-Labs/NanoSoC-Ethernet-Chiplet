# gap-dynamic-ir-drop / still-real

> **THE FILENAMES ON DISK CARRY A `.__fixture__.txt` SUFFIX.** This probe
> searches BY EXTENSION, and the pre-commit vendor guard refuses to let any
> `.cdl`, `.lef`, `.lib` or `.sp` be tracked whatever it contains — deliberately,
> by extension, so that "read it, it is synthetic" is not an argument it can be
> talked out of. `scripts/ci/signoff.py prove` strips the suffix when it stages
> the sandbox, so `tcbn65lp_tiny.sp.__fixture__.txt` on disk is `tcbn65lp_tiny.sp` where the
> probe looks. **Every path in this note is written as the probe sees it.** If
> you add a file here, name it `<what the check reads>.__fixture__.txt` and
> nothing else — the convention, and the three guards that stop it from quietly
> doing nothing, are in `ci/fixtures/README.md`.


The gap is a LIMIT OF THE SITE, not work not yet done, and the probe is written
on the load-bearing clause: **the absence of the collateral, not the absence of
the run.** `set_pg_library_mode -cell_type stdcells|macros` needs cell SPICE or
cell GDS to model the path from a cell's PG pin to its transistors; this site has
LEF abstracts and `.lib` timing only, so only a `techonly` power grid library can
ever be built here.

This half stages that site. `find ${TSMC_65_HOME} -maxdepth 8 -size +1k
\( -name 'tcbn65lp*.sp' -o -name 'tcbn65lp*.spi' -o -name 'tcbn65lp*.gds*' \)
| grep -q .` must exit 1.

All content synthetic; no vendor content, in a public repository, in a fixture
that is *about* vendor collateral.

## Decoys

| path | why it must not refute |
|---|---|
| `pdk-stand-in/pdk-root/digital/front_end/lef/tcbn65lp.lef` | an abstract view, over 1 kB, right library. |
| `pdk-stand-in/pdk-root/digital/front_end/lib/tcbn65lp_tt.lib` | timing, over 1 kB, right library. Together with the LEF this is **everything this site has** — the two decoys are the status quo, and a probe that matched them would declare a cell-accurate rail analysis reachable off the collateral whose insufficiency is the claim. |
| `pdk-stand-in/pdk-root/digital/front_end/spice/tcbn65lp_tiny.sp` | **right name, right extension, under 1 kB.** Earns the `-size +1k` clause. |

## The half of the gap this probe does not cover

The reason makes TWO claims. The first is the collateral. The second is that
*"there is no switching activity anywhere in this flow — no SAIF, no VCD — so
even the static currents are a default-activity estimate."* **The probe tests
only the first.** A SAIF appearing would not move it, and cell SPICE appearing
would refute the whole entry while the activity half stayed true. That is a
scope mismatch between `reason:` and `refuted_by:`, not a defect in either half
of this fixture, and it is recorded in `ci/fixtures/README.md`.

---

## THE DIRECTORY DEPTH HERE IS LOAD-BEARING. Read this before moving a file.

This probe is a `find` with `-maxdepth 8`, and `${TSMC_65_HOME}` reaches it from
two different places:

* **`prove`** runs it with `TSMC_65_HOME=.` inside the sandbox (see
  `_sandbox_env()`), so the search root is this fixture and the collateral must
  be **within** `-maxdepth 8`. Here it is at depth **6**.
* **`lint`** runs it from the REPOSITORY ROOT with the operator's own
  environment. On any host with no PDK installed `${TSMC_65_HOME}` is unset, the
  expansion is empty, and GNU `find` falls back to `.` — **the whole working
  tree, this fixture included.** So the collateral must be **beyond**
  `-maxdepth 8` counted from the repository root. Here it is at depth **10**.


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
