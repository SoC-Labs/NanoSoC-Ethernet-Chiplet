# `fail-fixture-vanished` — the proof cannot silently stop running

Deletes the ONE arm that carries the real defect: the rzG route log, the log
that named `RAMCLD0WDATA[123]` a day before the foundry did.

`--selftest` treats a missing fixture as a FAILURE and not as a skip, so this
must turn the stage red. Without this arm, somebody could delete the fixtures
and the stage would go green over nothing — which is the whole class of defect
the evidence flow exists to stop, reappearing inside its own proof.

`.__absent__` rather than omission: the prove sandbox symlinks the real repo
in, so an omitted path resolves to the repo's real file and the arm would pass
for the wrong reason.
