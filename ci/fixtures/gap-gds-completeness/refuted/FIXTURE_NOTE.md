# gap-gds-completeness / refuted

The day the Back-End packages arrive. The gap's reason calls their absence
"PERMANENT AS OF 2026-08-17 ... DECIDED, not discovered" — and a decision can be
reversed, which is exactly the event this probe exists to notice. The refuting
artefact is a `*_BE` package directory beside the Front-End one.

`find ${TSMC_65_HOME} -maxdepth 4 -name '*_BE' -type d | grep -q .` must exit 0,
`signoff.py lint` must go red, and the declaration must then be rewritten.

SYNTHETIC STAND-IN. Nothing in this tree is foundry content: no
vendor file, no vendor filename, no vendor data. These are one-line marker files
whose only property the probe reads is the NAME and TYPE of the directory that
contains them.

## One directory separates this half from still-real

`pdk-stand-in/pdk-root/fixture_stdcell_lib_BE/`. Every decoy is unchanged — the
`docs_BE_request` directory, the `vendor_note_BE` file and the depth-5
`buried_lib_BE` are all still here — so the pair isolates exactly one clause.

## What refutation would and would not mean

Refuting this probe means the *collateral* arrived. It does not by itself mean
the streamed GDS is complete: the design would still have to be re-streamed with
the cell masters merged before "design-owned DRC == 0" stopped being a floor.
The probe deliberately watches the root cause rather than the consequence, and
is over-eager in that direction.

---

## THE DIRECTORY DEPTH HERE IS LOAD-BEARING. Read this before moving a file.

This probe is a `find` with `-maxdepth 4`, and `${TSMC_65_HOME}` reaches it from
two different places:

* **`prove`** runs it with `TSMC_65_HOME=.` inside the sandbox (see
  `_sandbox_env()`), so the search root is this fixture and the collateral must
  be **within** `-maxdepth 4`. Here it is at depth **3**.
* **`lint`** runs it from the REPOSITORY ROOT with the operator's own
  environment. On any host with no PDK installed `${TSMC_65_HOME}` is unset, the
  expansion is empty, and GNU `find` falls back to `.` — **the whole working
  tree, this fixture included.** So the collateral must be **beyond**
  `-maxdepth 4` counted from the repository root. Here it is at depth **7**.


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
