# `pass` — the proof runs against the real fixture set

This directory deliberately overlays NOTHING. `signoff.py`'s prove sandbox
symlinks every top-level repo entry in, so with nothing overlaid the check runs
`lvs_missing_connection.py --selftest` against the real eleven arms under
`ci/fixtures/lvs-missing-connection/`, which is exactly what it must do.

A fixture directory has to be non-empty or `signoff.py lint` rejects it (an
empty fixture makes the sandbox just the repo, silently), so this file is the
directory's content and its explanation at once.
