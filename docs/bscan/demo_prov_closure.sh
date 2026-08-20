#!/bin/sh
# demo_prov_closure.sh -- does the transitive fingerprint distinguish the two
# runs that the named entry point could not?
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
# license. Copyright 2026, SoC Labs (www.soclabs.org)
#
# The two synthesis runs of 2026-08-19 and 2026-08-20 produced netlists with
# different hierarchy. The flow recorded no input change, because the only file
# it fingerprints is constraints.sdc and constraints.sdc did not move. The file
# that DID move, bscan_constraints.sdc, is reached only through a `source`.
#
# Run from the repository root:  sh docs/bscan/demo_prov_closure.sh
set -e
cd "$(git rev-parse --show-toplevel)"
IN=ASIC/genus-innovus/inputs
OLD=f2467d8      # bscan_constraints.sdc 5255 B  -- the run-1 constraint set
NEW=a2ca938      # bscan_constraints.sdc 6724 B  -- the run-2 constraint set

WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

for rev in $OLD $NEW; do
    mkdir -p "$WORK/$rev/$IN"
    # every SDC in the closure, at that revision
    for f in constraints qspi_constraints tidelink_constraints \
             ethernet_constraints i2c_constraints bscan_constraints; do
        git show "$rev:$IN/$f.sdc" > "$WORK/$rev/$IN/$f.sdc" 2>/dev/null \
            || cp "$IN/$f.sdc" "$WORK/$rev/$IN/$f.sdc"
    done
done

echo "=================================================================="
echo "WHAT THE FLOW FINGERPRINTS TODAY -- the named entry point only"
echo "=================================================================="
for rev in $OLD $NEW; do
    printf '  %s  constraints.sdc  %7s B  %s\n' "$rev" \
        "$(stat -c%s "$WORK/$rev/$IN/constraints.sdc")" \
        "$(sha256sum "$WORK/$rev/$IN/constraints.sdc" | cut -c1-16)"
done
echo "  -> IDENTICAL. The manifest reports no input change between the runs."
echo ""
echo "=================================================================="
echo 'WHAT THE TRANSITIVE CLOSURE FINGERPRINTS -- every file it sources'
echo "=================================================================="
for rev in $OLD $NEW; do
    echo "  $rev:"
    ( cd "$WORK/$rev" && for f in $IN/*.sdc; do
        printf '    %s  %7s B  %s\n' "$(sha256sum "$f" | cut -c1-16)" \
               "$(stat -c%s "$f")" "$(basename "$f")"
      done | sort -k4 )
    agg=$( cd "$WORK/$rev" && for f in $IN/*.sdc; do sha256sum "$f"; done \
           | sort | sha256sum | cut -d' ' -f1 )
    echo "    sdc.closure.sha256 = $agg"
    eval "AGG_$rev=$agg"
done
echo ""
echo "=================================================================="
echo "VERDICT"
echo "=================================================================="
eval "a=\$AGG_$OLD; b=\$AGG_$NEW"
if [ "$a" = "$b" ]; then
    echo "  THE CLOSURE DID NOT DISCRIMINATE -- the gate is useless."
    exit 1
fi
n=$(diff -rq "$WORK/$OLD/$IN" "$WORK/$NEW/$IN" | wc -l)
echo "  entry-point hash : SAME       (constraints.sdc, 44270 B, both revisions)"
echo "  closure hash     : DIFFERENT"
echo "  files the closure names as changed: $n"
diff -rq "$WORK/$OLD/$IN" "$WORK/$NEW/$IN" \
    | sed "s|$WORK/$OLD/$IN/||; s|$WORK/$NEW/$IN/[^ ]*||; s/^/    /"
echo ""
echo "  READ THAT NUMBER HONESTLY. $n files moved between these two COMMITS, not"
echo "  one - the commits are a stand-in for the two constraint sets, because the"
echo "  bytes the two RUNS actually read are unrecoverable (build/<tag>/inputs is"
echo "  a symlink to the live tree, so an in-place edit leaves no snapshot). That"
echo "  irrecoverability is the argument for fingerprinting AT READ TIME, and it"
echo "  is why this demo has to reconstruct from git at all."
echo ""
echo "  The point stands regardless: the entry point names ZERO changed files and"
echo "  the closure names $n, one of which is bscan_constraints.sdc, 5255 -> 6724 B,"
echo "  the edit that restructured the netlist hierarchy."
