#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# vendor_guard_report.sh — run the vendor-collateral gate and say WHICH HALF RAN
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# check_no_vendor_collateral.sh has two halves and only one of them is portable:
#
#   CHECK 1  tracked *.lef, by content hash and by size     — needs nothing
#   CHECK 2  runs of verbatim vendor text, in any file      — needs the PDK
#
# Check 2 reads the installed PDK at $TSMC_65_HOME. On a GitHub-hosted runner
# there is none, so the script prints a NOTE, SKIPS check 2, and still exits 0.
# That is the correct behaviour for the script -- but it is a trap for a CI job,
# because the job then reports a green tick for a gate that ran at half strength
# and nobody reading the tick can tell. Worse, when the PDK mount IS present but
# unreadable (missing group membership), the script builds a near-empty corpus,
# warns, and then scans against it -- so the verbatim half returns "clean"
# because it had nothing to compare against.
#
# THIS WRAPPER EXISTS TO MAKE THAT DISTINCTION LOUD AND, WHERE IT MATTERS, FATAL:
#
#   ran        both halves executed                     -> pass, verdict FULL
#   skipped    no PDK at all (a hosted runner)          -> pass, verdict PARTIAL
#                                                          (fatal if REQUIRE_PDK)
#   untrusted  PDK present but the corpus is too small  -> ALWAYS FATAL
#
# `untrusted` is fatal everywhere and deliberately so. It is the only one of the
# three states that can print "OK" while being actively wrong, and this
# repository has been bitten twice by a check that returned a shorter answer
# without saying so (Calibre's truncated result counts; check_connectivity
# stopping at 1000). A crippled corpus is the same failure wearing a green tick.
# Escalating it here does not weaken the script -- the script's own NOTE already
# says "treat the verbatim check as NOT HAVING RUN"; this makes CI obey it.
#
# WHAT IT WILL NOT PRINT. The gate's whole subject is data that must not be
# copied, and a CI log on a PUBLIC repository is a copy. The underlying script is
# already careful -- it prints file LOCATIONS and match COUNTS, never matched
# text -- with one exception: its "no readable PDK" NOTE echoes $TSMC_65_HOME,
# which on a lab host is an absolute path to this site's PDK mount. That is
# exactly the class VENDOR_COLLATERAL.md names as not-for-publication ("absolute
# paths to *this* site's PDK mounts"). So the output is passed through one
# redaction before it reaches the log or the job summary. Nothing else is
# filtered: paths inside this repository are this repository's own.
#
# Usage:  scripts/ci/vendor_guard_report.sh
# Env:    VENDOR_GUARD_REQUIRE_PDK=1  fail unless the verbatim half really ran
#         GITHUB_STEP_SUMMARY=<path>  markdown summary sink (set by Actions)
# Exit:   0 clean, 1 violation or an untrustworthy run, 2 harness fault.
#-----------------------------------------------------------------------------
set -uo pipefail

root=$(git rev-parse --show-toplevel 2>/dev/null) || {
    echo "vendor_guard_report: not in a git work tree" >&2; exit 2; }
cd "$root" || exit 2

CHECK="$root/scripts/ci/check_no_vendor_collateral.sh"

# A required check must fail when its detector is missing, never pass. Deleting
# or un-chmod-ing the script is precisely the change this gate must not survive.
if [ ! -x "$CHECK" ]; then
    echo "::error::scripts/ci/check_no_vendor_collateral.sh is missing or not" >&2
    echo "::error::executable. The vendor-collateral gate cannot run, so this" >&2
    echo "::error::job fails rather than reporting a pass it did not earn." >&2
    exit 2
fi

raw=$(mktemp) || exit 2
red=$(mktemp) || exit 2
trap 'rm -f "$raw" "$red"' EXIT

"$CHECK" < /dev/null > "$raw" 2>&1
rc=$?

# The one redaction: the site's PDK mount path. See the header.
sed -E 's#(TSMC_65_HOME=)[^,[:space:]]+#\1<set; site path withheld>#g' "$raw" > "$red"
cat "$red"

# --- which half ran ---------------------------------------------------------
# Order matters. Both NOTEs can appear together (an unreadable mount yields a
# small corpus AND an empty one), and `untrusted` is the stricter verdict, so it
# wins. A hosted runner with no PDK directory at all trips only the second.
if   grep -q 'vendor corpus is only'  "$raw"; then verbatim=untrusted
elif grep -q 'no readable PDK under'  "$raw"; then verbatim=skipped
else                                               verbatim=ran
fi

require_pdk=${VENDOR_GUARD_REQUIRE_PDK:-0}
exit_rc=$rc
case "$verbatim" in
    ran)
        halves='**both halves ran** — tracked/staged collateral AND verbatim vendor text'
        note='' ;;
    skipped)
        halves='**HALF THE GATE RAN.** Check 1 (tracked collateral by hash and size) ran. Check 2 (verbatim vendor text) was **SKIPPED** — this runner has no readable PDK, and check 2 has nothing to compare a file against without one.'
        note='A pass here does **not** mean no vendor text was copied in. It means nobody looked. The `vendor-collateral-gate-pdk` job on the PDK host is what looks.'
        [ "$require_pdk" = "1" ] && { exit_rc=1; note='This job exists **only** to run check 2, and check 2 did not run. Failing rather than reporting a pass it did not earn. Fix the runner: the host needs the PDK mount bound and membership of the PDK group.'; }
        ;;
    untrusted)
        halves='**CHECK 2 IS NOT TRUSTWORTHY.** A PDK path was found but the corpus read out of it is far too small to be the real thing — so check 2 compared this tree against almost nothing and would report clean whatever it contained.'
        note='This is a runner fault, not a code fault: the mount is present but unreadable (group membership). Treated as FATAL because it is the one state that can print OK while being wrong.'
        exit_rc=1 ;;
esac

if [ "$exit_rc" -eq 0 ]; then verdict='PASS'; else verdict='FAIL'; fi

# --- job summary ------------------------------------------------------------
# Locations and counts only. The underlying script never emits matched text, and
# the site PDK path has already been redacted out of $red above.
{
    echo "## vendor-collateral — check_no_vendor_collateral.sh — $verdict"
    echo
    # WHICH SCANNER THIS IS. This wrapper drives ONE of the two scanners the
    # hosted job runs, and its verdict is not the job's. Titling it "the
    # vendor-collateral gate" -- which it was -- let a PASS here read as "the
    # gate passed", and the whole content of the defect this pairing fixes is
    # that this scanner's corpus is `git ls-files -- '*.lef'` plus, on a PDK
    # host, verbatim text. It cannot see a tracked .tlef, .lib, .captable, .map
    # or .gds; ASIC/asic-toolkit/ci/check-vendor-collateral.sh is what does, and
    # it writes its own section below this one.
    echo '_Scanner 1 of 2 in this job. Corpus: tracked `*.lef` by content SHA and'
    echo 'by size, plus — on a PDK host only — runs of verbatim vendor text in a'
    echo 'file of any type. Extension, size and value rules over the other'
    echo 'collateral suffixes are the toolkit scanner’s section, not this one._'
    echo
    echo "$halves"
    echo
    [ -n "$note" ] && { echo "$note"; echo; }
    if [ "$rc" -ne 0 ]; then
        echo '### Files that must not be published'
        echo
        echo 'Paths only — no file content is reproduced here, deliberately.'
        echo
        echo '```'
        head -c 60000 "$red"
        echo '```'
        echo
        echo 'Do not "fix" this by deleting the check. Ship the TRANSFORM, not the'
        echo 'RESULT: read the vendor file from the PDK at build time and write the'
        echo 'derived artefact into a gitignored directory. `git rm --cached <path>`'
        echo 'untracks a file already added.'
    else
        echo '```'
        head -c 20000 "$red"
        echo '```'
    fi
    echo
    echo "_Gate: \`make vendor-check\` / \`scripts/ci/check_no_vendor_collateral.sh\`. See docs/IMPLEMENTATION.md._"
} >> "${GITHUB_STEP_SUMMARY:-/dev/stdout}"

exit "$exit_rc"
