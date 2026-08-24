# `absent` — the arm that proves a MISSING report is not a clean one

`evidence_report.json.__absent__` is not a typo. `signoff.py`'s prove sandbox
symlinks every top-level repo entry in and then copies the fixture over the
top, so **a fixture cannot express absence by omission** — an omitted file
resolves to whatever the real repo has at that path. `.__absent__` is the
marker that makes the sandbox guarantee the named path does *not* exist.

Without this arm, "no report" would be tested against whatever report happened
to be lying in the working tree, and the arm would pass for the wrong reason.
