# `fail-fixture-vanished` — the proof cannot silently stop running

Deletes the observed sub-top FAIL arm. `--selftest` treats a missing fixture as
a failure, never as a skip, so the stage must go red.

`.__absent__` rather than omission: the prove sandbox symlinks the real repo in,
so an omitted path resolves to the repo's real file.
