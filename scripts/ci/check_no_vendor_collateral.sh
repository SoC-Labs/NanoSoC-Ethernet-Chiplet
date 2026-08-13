#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# check_no_vendor_collateral.sh — keep foundry IP out of a PUBLIC repository.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHAT THIS DEFENDS AGAINST
#
# github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet is PUBLIC. TSMC's PDK collateral
# is licensed to this site and the licence does not permit reproducing or
# redistributing it. Committing a vendor LEF publishes foundry IP to the world.
#
# This is not hypothetical. The tree carried a 414 kB verbatim copy of TSMC's
# `tphn65lpgv2od3_sl_9lm.lef` at ASIC/tech_wrappers/tsmc65/local_overrides/ for
# months, because three lines of it needed changing and copying the file was the
# obvious way to change them. The fix was to ship the TRANSFORM instead of the
# RESULT: ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py reads the vendor
# file from the read-only PDK at build time and writes the patched LEF into a
# gitignored build directory. The repository holds three lines of intent and the
# code to apply them, and no vendor bytes at all.
#
# The failure mode this guards is not malice, it is helpfulness: a future
# session sees a build referencing a file that is not in the tree, "fixes" it by
# copying the file in, and the .gitignore rule does not stop them because they
# used `git add -f` or a different path. So this checks what is TRACKED, which
# is the thing that actually gets published.
#
# Usage:  scripts/ci/check_no_vendor_collateral.sh
# Exit:   0 clean, 1 violation. Costs no licence and no EDA tool.
#-----------------------------------------------------------------------------
set -uo pipefail

cd "$(git rev-parse --show-toplevel 2>/dev/null)" || {
    echo "check_no_vendor_collateral: not in a git work tree" >&2; exit 1; }

# Known vendor collateral, by content. These two are the TSMC IO-driver LEF as
# shipped (414,474 B) and the project's patched form of it (414,535 B) -- the
# exact file that used to be committed. Content-keyed, so renaming it or moving
# it elsewhere in the tree does not evade the check.
VENDOR_SHA="61c9e28ed94d4401d98f2f6b9b53a963ecbbea96233cfa033e61e91269c001a9"
PATCHED_SHA="862ed5abab7d209c59d3af19edc386a88a5688a361d8b7dd4b6aca80a7b66c6e"

# Any tracked .lef this size is vendor collateral: nothing this project authors
# comes close. The project's own LEF-shaped outputs are compiled memory views
# under ASIC/romlibs/, which is generated and gitignored.
SIZE_LIMIT=65536

# ── ARMED ───────────────────────────────────────────────────────────────────
# There was an allowlist here while the committed copy of the IO-driver LEF was
# still tracked. That file is gone and the entry went with it, in the same
# commit, which is what arms this check: there is now NO path that is permitted
# to hold vendor collateral. Do not add one back. If a build wants that LEF, it
# wants `make -C ASIC -f common.mk pad-lef`, not a copy in the tree.

rc=0

while IFS= read -r f; do
    [ -n "$f" ] || continue
    [ -f "$f" ] || continue

    reason=""
    sha=$(sha256sum "$f" | cut -d' ' -f1)
    size=$(wc -c < "$f" | tr -d ' ')

    if [ "$sha" = "$VENDOR_SHA" ]; then
        reason="byte-identical to the TSMC vendor IO-driver LEF"
    elif [ "$sha" = "$PATCHED_SHA" ]; then
        reason="the patched TSMC IO-driver LEF (vendor file + this project's 3 lines)"
    elif [ "$size" -gt "$SIZE_LIMIT" ]; then
        reason="a tracked .lef of ${size} bytes — too large to be anything but vendor collateral"
    fi

    [ -n "$reason" ] || continue

    if [ $rc -eq 0 ]; then
        echo "FAIL: vendor foundry collateral is TRACKED in a PUBLIC repository." >&2
        echo >&2
    fi
    echo "  $f" >&2
    echo "      $reason" >&2
    rc=1
done < <(git ls-files -- '*.lef' 2>/dev/null)

if [ $rc -ne 0 ]; then
    cat >&2 <<'EOF'

TSMC's licence does not permit reproducing their collateral, and this repository
is published. Do not commit the file, and do not "fix" a build that references a
generated path by copying the vendor file into the tree.

The supported pattern is to ship the TRANSFORM, not the RESULT:

  ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py   reads the PDK at build
  ASIC/genus-innovus/scripts/gdsmap_derive.py          time and writes into a
                                                       gitignored directory

To produce the patched IO-driver LEF:  make -C ASIC -f common.mk pad-lef
To untrack a file already added:       git rm --cached <path>

EOF
    exit 1
fi

echo "check_no_vendor_collateral: OK (no vendor collateral tracked)"
exit 0
