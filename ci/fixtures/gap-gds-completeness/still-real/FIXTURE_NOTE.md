# gap-gds-completeness / still-real

The gds-completeness gap says the streamed GDS has no transistors in 424 of its
cell masters, and names its own root cause: this PDK ships Front-End packages
only and **no `*_BE` directory exists anywhere on the system**. That root cause
is what the probe tests, and the refuting artefact is therefore a *directory* —
a Back-End package appearing beside the Front-End ones.

This half stages the site as it is: an FE package present, no BE package.
`find ${TSMC_65_HOME} -maxdepth 4 -name '*_BE' -type d | grep -q .` must exit 1.

SYNTHETIC STAND-IN. Nothing in this tree is foundry content: no
vendor file, no vendor filename, no vendor data. These are one-line marker files
whose only property the probe reads is the NAME and TYPE of the directory that
contains them.

## Why the search root is the sandbox

`_sandbox_env()` in `scripts/ci/signoff.py` sets `TSMC_65_HOME=.` for the
duration of a prove sandbox, so `find ${TSMC_65_HOME}` searches THIS TREE — on
every host, including the one where the real PDK is installed. Without that this
fixture would be authoritative wherever the PDK is absent and decorative on
srv03335, the one host that does the real physical signoff, and a proof that
answers differently on the machine that matters is not a proof.

It is SET rather than deleted on purpose. Deleting it works only by accident:
`find ${TSMC_65_HOME}` with the variable unset collapses to a bare `find`, which
GNU find happens to read as `.`. Pointing it at the sandbox says the intended
thing outright and keeps the hardened probe in
`ci/fixtures/PROPOSED_GAP_PROBES.yaml` provable — that one exits 2 when the
variable is unset, which under a delete would turn every half of these three
fixtures red.

**The limit that follows:** these fixtures pin the probe's *name*, *type* and
*depth* clauses. They say nothing about whether it looks in the right PLACE.
That clause has no fixture and cannot have one in a public repository.

## Decoys

| path | why it must not refute |
|---|---|
| `pdk-stand-in/pdk-root/docs_BE_request/` | a directory whose name *contains* `_BE` but does not END with it. `-name '*_BE'` is anchored at the end; a probe using `*_BE*` would match a request document and delete a real gap. |
| `pdk-stand-in/pdk-root/vendor_note_BE` | a FILE ending in `_BE`. `-type d` is load-bearing: the package is a directory, and a stray file is not a delivery. |
| `pdk-stand-in/pdk-root/x/y/buried_lib_BE/` | a package directory at depth 5, past `-maxdepth 4`. This decoy pins a **known blind spot, not a virtue**: the bound is deliberate (the probe runs on every `lint`, and the packages would land as siblings of the FE ones) but a BE package installed deeper than four levels would not be seen. Named here so it is a decision on the record rather than a surprise. |

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
