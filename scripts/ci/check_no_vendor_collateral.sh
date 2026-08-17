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

# ── CHECK 2: VERBATIM VENDOR TEXT, IN ANY FILE, OF ANY TYPE ─────────────────
#
# Check 1 only ever looked at tracked *.lef. That is the file that was actually
# committed in 2026, and widening it was never done -- so on 2026-08-14 a DRC
# deck header sat in scripts/calibre/ with 144 lines byte-identical to TSMC's
# CLN65S deck, and this script said OK. Wrong extension, wrong corpus.
#
# So this check ignores extensions entirely and asks the only question that
# matters: does any file we are about to publish reproduce a RUN of consecutive
# lines from a vendor file installed on this host?
#
# A RUN, not a line. Single-line matches are noise -- a lone `}`, a bare `//`, or
# an SVRF specification statement (`LAYOUT SYSTEM GDSII`) that our own wrapper
# decks must legitimately emit. Measured across the whole calibre/ directory,
# legitimate files top out at a run of 1 and copied ones run to 13, so 3 splits
# them cleanly with room either way.
#
# WHAT IT SEES. `git ls-files` alone cannot see a file that has never been
# added, which is exactly the state every file in this class is in while it is
# being written -- so this also scans STAGED content and, as a warning, the
# untracked working tree. Untracked is a WARNING and not a failure: a scratch
# copy of a vendor file in a work directory is not a publication, and making
# that fatal would train people to skip the check.
RUN_THRESHOLD=3

corpus=$(mktemp) || exit 1
trap 'rm -f "$corpus"' EXIT

# THE PDK MOUNT IS INHERITED, NOT NAMED HERE. ASIC/common.mk exports
# TSMC_65_HOME and is the one place in this repo that carries the site's mount
# point; a default spelled here would be a second copy of a site constant, and
# the kind of copy this very script exists to find. Unset is already a handled
# state a dozen lines down - it SKIPS and says loudly that a skip is not a pass -
# so inheriting costs nothing and removes the duplicate.
: "${TSMC_65_HOME:=}"

# The sensitive, cheap-to-read collateral: the rule decks, the stream-out maps,
# the technology LEF. Globbed, never named by release code. Collected into an
# array FIRST -- a `while read | awk` pipeline runs its loop in a subshell, so
# any flag set inside it is lost and the check silently reports "no PDK".
# NOT `| head -N`. An earlier revision capped this at the first 40 matches, and
# because `find` order is not stable that silently scanned a DIFFERENT subset of
# the decks on every run -- so the same file passed once and would have failed
# the next time. It read as clean. That is the same failure this repository has
# already been bitten by twice (Calibre's own truncated result counts,
# check_connectivity stopping at 1000): a cap that produces a shorter answer
# without saying so. The whole corpus is 167 files and ~40 MB; read all of it,
# sorted so the set is reproducible.
vendor_files=()
if [ -d "$TSMC_65_HOME" ]; then
    while IFS= read -r vf; do
        [ -r "$vf" ] && vendor_files+=("$vf")
    done < <(
        find "$TSMC_65_HOME" -maxdepth 8 \
             \( -name 'CLN65*' -o -name '*.map' -o -name '*.tlef' \) \
             -type f 2>/dev/null | sort
    )
fi

if [ ${#vendor_files[@]} -gt 0 ]; then
    cat -- "${vendor_files[@]}" 2>/dev/null \
      | sed 's/^[ \t]*//;s/[ \t]*$//' \
      | awk 'length($0) >= 12' | sort -u > "$corpus"
    corpus_lines=$(wc -l < "$corpus")
    # A corpus that came back suspiciously small means the mount is there but
    # unreadable (group membership), which would otherwise present as a pass.
    if [ "$corpus_lines" -lt 5000 ]; then
        echo "check_no_vendor_collateral: NOTE — vendor corpus is only" >&2
        echo "  $corpus_lines lines from ${#vendor_files[@]} files. That is too small to be" >&2
        echo "  the real PDK; you probably lack group tsmc65pdkgrp. Treat the" >&2
        echo "  verbatim check below as NOT HAVING RUN." >&2
    fi
fi

if [ ${#vendor_files[@]} -eq 0 ] || [ ! -s "$corpus" ]; then
    echo "check_no_vendor_collateral: NOTE — no readable PDK under" >&2
    echo "  TSMC_65_HOME=${TSMC_65_HOME:-<unset; export it, or run via ASIC/common.mk>}," >&2
    echo "  so the verbatim-vendor-text check was" >&2
    echo "  SKIPPED. It is not a pass. Run it on a host with the PDK mounted" >&2
    echo "  (and membership of group tsmc65pdkgrp) before trusting a release." >&2
else
    scan_one() {   # $1 = path, $2 = "tracked" | "staged" | "untracked"
        local f=$1 origin=$2 run best line
        [ -f "$f" ] || return 0
        case "$f" in */.git/*) return 0 ;; esac
        # skip anything that is not text
        grep -Iq . "$f" 2>/dev/null || return 0
        best=$(awk -v thr="$RUN_THRESHOLD" '
            NR==FNR { vendor[$0]=1; next }
            { line=$0; gsub(/^[ \t]+|[ \t]+$/,"",line)
              if (length(line) >= 12 && (line in vendor)) { run++ ; if (run>best) best=run }
              else run=0 }
            END { print best+0 }' "$corpus" "$f")
        [ "${best:-0}" -ge "$RUN_THRESHOLD" ] || return 0
        if [ "${hdr2:-0}" -eq 0 ]; then
            echo "Files reproducing runs of vendor foundry text:" >&2
            echo >&2
            hdr2=1
        fi
        if [ "$origin" = untracked ]; then
            echo "  $f  [untracked — WARNING, not counted as a failure]" >&2
            echo "      longest verbatim run: $best lines from the installed PDK" >&2
            warned=1
        else
            echo "  $f  [$origin]" >&2
            echo "      longest verbatim run: $best lines from the installed PDK" >&2
            rc=1
        fi
    }

    warned=0
    hdr2=0
    while IFS= read -r f; do scan_one "$f" tracked;   done < <(git ls-files)
    while IFS= read -r f; do scan_one "$f" staged;    done < <(git diff --cached --name-only --diff-filter=ACM)
    while IFS= read -r f; do scan_one "$f" untracked; done < <(git ls-files --others --exclude-standard)
fi

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
