#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# seed_build_run.sh -- seed a toolkit run's outputs/ from another run, WITHOUT
#                      laundering the synthesis provenance out of the record.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS, with the two runs that proved it.
#
# Synthesis costs about 1.5 h and a floorplan experiment does not change the
# netlist, so a run is routinely started by copying another run's outputs/ into
# build/<tag>/outputs/ and invoking `make place cts route`. That copy is not
# neutral. It removes reports/syn_manifest.txt and reports/syn_provenance.txt
# from the new run -- they were never written there, because synthesis never ran
# there -- and the coherence gate in the toolkit
# (ASIC/asic-toolkit/ci/collect-results.py, read_manifests) can only compare the
# manifests it FINDS.
#
# So on 2026-08-22:
#
#   gdsrun-20260821-slpads  synthesised its own netlist. 4 manifests.
#                           Coherence gate: "2 revisions across 3 stages,
#                           2 toolkit revisions".
#   gdsrun-20260822-halo    seeded from it -- byte-identical netlist, sha256
#                           5a191f26...  3 manifests, no syn_*.
#                           Coherence gate: "2 revisions across 2 stages".
#
# The seeded run scores CLEANER than the honest one, on the same logic, because
# the evidence that would have convicted it is the evidence the seeding deleted.
# A gate that reads better the less it is given is not a gate.
#
# WHAT THIS SCRIPT DOES ABOUT IT
#
#   1. refuses to seed from a run that cannot state what it synthesised;
#   2. copies outputs/ forward, minus the SDF (same reasoning as
#      scripts/ci/new_run.sh section 3b, which is the legacy-path original of
#      this script);
#   3. VERIFIES the seeded netlist against the sha256 the source's own manifest
#      recorded, and refuses on a mismatch. A netlist that is not the one the
#      source manifest describes makes the whole carried-forward record a lie;
#   4. carries syn_manifest.txt / syn_provenance.txt forward under the suffixed
#      names `<name>.seeded-from-<tag>`. The suffix matters: the coherence
#      gate globs `reports/*_manifest.txt`, so a suffixed copy is EVIDENCE and is
#      never mistaken for a manifest this run wrote. A seeded run must not be
#      able to impersonate one that synthesised;
#   5. writes reports/seed_record.txt, which the toolkit's provenance collector
#      reads (prov_collect_seed in flow/common/provenance.tcl) and turns into
#      prov.seed.* fields in EVERY stage manifest of the seeded run. That is what
#      makes the seeding visible to a reader who only ever opens one file.
#
# It refuses rather than warns. This runs BEFORE a three-hour flow starts, which
# is the one moment in the whole pipeline when failing is cheap.
#
# Usage:
#   scripts/ci/seed_build_run.sh --from <src-tag|src-dir> --to <dst-tag|dst-dir>
#                                [--build-dir <dir>] [--stage syn] [--dry-run]
#
#   scripts/ci/seed_build_run.sh --from gdsrun-20260821-slpads \
#                                --to   gdsrun-20260822-halo
#-----------------------------------------------------------------------------
set -uo pipefail

ROOT="${ASIC_PROJECT_ROOT:-$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)}"
BUILD_DIR="${BUILD_DIR:-$ROOT/ASIC/eth-chiplet/build}"
SRC=""; DST=""; STAGE="syn"; DRY=0

die() { echo "!! $*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        --from)      SRC="${2:?--from needs a value}"; shift 2 ;;
        --to)        DST="${2:?--to needs a value}";   shift 2 ;;
        --build-dir) BUILD_DIR="${2:?}";               shift 2 ;;
        --stage)     STAGE="${2:?}";                   shift 2 ;;
        --dry-run)   DRY=1; shift ;;
        -h|--help)   sed -n '2,62p' "$0"; exit 0 ;;
        *)           die "unknown argument '$1' (try --help)" ;;
    esac
done

[ -n "$SRC" ] || die "--from is required"
[ -n "$DST" ] || die "--to is required"

# A bare name is a RUN TAG under $BUILD_DIR; anything with a slash is a path.
resolve_run() {
    case "$1" in
        */*) echo "$1" ;;
        *)   echo "$BUILD_DIR/$1" ;;
    esac
}
SRC_DIR="$(resolve_run "$SRC")"
DST_DIR="$(resolve_run "$DST")"
SRC_TAG="$(basename "$SRC_DIR")"
DST_TAG="$(basename "$DST_DIR")"

[ -d "$SRC_DIR" ]         || die "no source run at $SRC_DIR"
[ -d "$SRC_DIR/outputs" ] || die "$SRC_DIR has no outputs/ -- nothing to seed from"
[ "$SRC_DIR" != "$DST_DIR" ] || die "--from and --to name the same run ($SRC_TAG)"

echo "== seed $DST_TAG  <-  $SRC_TAG"
echo "   source : $SRC_DIR"
echo "   target : $DST_DIR"

#-----------------------------------------------------------------------------
# 1. THE SOURCE MUST BE ABLE TO SAY WHAT IT SYNTHESISED
#
# Seeding from a run that has no synthesis record does not lose provenance -- it
# propagates an ALREADY LOST provenance one hop further, and each hop makes the
# loss harder to see. If the source is itself a seeded run its own seed_record
# supplies the chain, and that IS acceptable: the ancestry is recorded.
#-----------------------------------------------------------------------------
SRC_MF="$SRC_DIR/reports/${STAGE}_manifest.txt"
SRC_PV="$SRC_DIR/reports/${STAGE}_provenance.txt"
SRC_SEED="$SRC_DIR/reports/seed_record.txt"

if [ ! -s "$SRC_MF" ] && [ ! -s "$SRC_SEED" ]; then
    die "$SRC_TAG has neither reports/${STAGE}_manifest.txt nor a seed_record.txt.
   It cannot state what netlist it holds or where the netlist came from, so
   seeding from it would carry nothing forward -- which is the exact failure
   this script exists to stop. Re-run synthesis, or seed from a run that has
   its own ${STAGE} manifest."
fi

# The recorded netlist hash. The manifest is preferred over the standalone
# provenance file because the manifest is the artefact the coherence gate reads;
# if only one of the two exists, say which was used.
recorded_sha=""
recorded_from=""
for f in "$SRC_MF" "$SRC_PV"; do
    [ -s "$f" ] || continue
    v=$(awk '$1=="prov.netlist.sha256" { print $2; exit }' "$f")
    case "$v" in
        [0-9a-f]*) recorded_sha="$v"; recorded_from="$f"; break ;;
    esac
done

#-----------------------------------------------------------------------------
# 2. WHAT GETS COPIED
#
# SDF IS EXCLUDED, for the reason new_run.sh gives: _pnr.sdf is ~390 MB and
# _gate.sdf ~200 MB, and nothing downstream of a seeded run reads either. They
# stay in the source run for anyone who wants gate-level simulation.
#-----------------------------------------------------------------------------
NETLIST_SRC=$(find "$SRC_DIR/outputs" -maxdepth 1 -name '*_gate_power.v' | head -1)
[ -n "$NETLIST_SRC" ] || die "$SRC_DIR/outputs holds no *_gate_power.v -- refusing to seed"
NETLIST_BASE="$(basename "$NETLIST_SRC")"

if [ "$DRY" = 1 ]; then
    echo "   DRY RUN -- would copy $(find "$SRC_DIR/outputs" -maxdepth 1 -mindepth 1 ! -name '*.sdf' | wc -l) item(s)"
    echo "   netlist        : $NETLIST_BASE"
    echo "   recorded sha   : ${recorded_sha:-(none recorded)}  ${recorded_from:+from $(basename "$recorded_from")}"
    exit 0
fi

mkdir -p "$DST_DIR/outputs" "$DST_DIR/reports" || die "cannot create $DST_DIR"
find "$SRC_DIR/outputs" -maxdepth 1 -mindepth 1 ! -name '*.sdf' \
     -exec cp -a {} "$DST_DIR/outputs/" \; \
    || die "copy failed -- $DST_DIR/outputs is now PARTIAL, do not run against it"
echo "   copied outputs/ (SDF excluded)"

#-----------------------------------------------------------------------------
# 3. THE CHECK THAT MAKES THE CARRIED RECORD MEAN SOMETHING
#
# The manifest about to be copied forward describes ONE netlist, by hash. If the
# file that landed in outputs/ is not that netlist then the carried manifest
# describes a design this run is not building, and a wrong provenance record is
# worse than an absent one because it reads as evidence.
#-----------------------------------------------------------------------------
seeded_sha=$(sha256sum -- "$DST_DIR/outputs/$NETLIST_BASE" | awk '{print $1}')
echo "   netlist  : $NETLIST_BASE"
echo "   sha256   : $seeded_sha"

if [ -z "$recorded_sha" ]; then
    if [ -s "$SRC_SEED" ]; then
        recorded_sha=$(awk '$1=="seed.netlist_sha256" { print $2; exit }' "$SRC_SEED")
        recorded_from="$SRC_SEED"
    fi
fi

if [ -z "$recorded_sha" ]; then
    die "$SRC_TAG records no prov.netlist.sha256 anywhere. There is nothing to
   check the seeded netlist against, so this seed cannot be attested. Refusing."
fi

if [ "$seeded_sha" != "$recorded_sha" ]; then
    rm -f "$DST_DIR/outputs/$NETLIST_BASE"
    die "SEEDED NETLIST DOES NOT MATCH THE SOURCE MANIFEST.
   recorded in : $recorded_from
     $recorded_sha
   copied file : $DST_DIR/outputs/$NETLIST_BASE
     $seeded_sha
   The source run's outputs/ has changed since its manifest was written, so that
   manifest describes a netlist that is no longer there. The copied netlist has
   been removed. Re-synthesise, or find the run whose manifest matches."
fi
echo "   VERIFIED against $(basename "$recorded_from")"

#-----------------------------------------------------------------------------
# 4. CARRY THE RECORD FORWARD -- SUFFIXED, SO IT CANNOT IMPERSONATE
#-----------------------------------------------------------------------------
carried=""
for f in "$SRC_MF" "$SRC_PV"; do
    [ -s "$f" ] || continue
    cp -a "$f" "$DST_DIR/reports/$(basename "$f").seeded-from-$SRC_TAG" \
        && carried="$carried $(basename "$f").seeded-from-$SRC_TAG"
done
# A seeded source's own carried evidence comes too, or the chain has a hole in
# the middle of it.
for f in "$SRC_DIR"/reports/*_manifest.txt.seeded-from-* \
         "$SRC_DIR"/reports/*_provenance.txt.seeded-from-*; do
    [ -e "$f" ] || continue
    cp -a "$f" "$DST_DIR/reports/$(basename "$f")" && carried="$carried $(basename "$f")"
done
echo "   carried :${carried:- (nothing -- source had no ${STAGE} record)}"

#-----------------------------------------------------------------------------
# 5. THE RECORD THE FLOW ITSELF WILL READ
#
# flow/common/provenance.tcl's prov_collect_seed reads this file at EVERY stage
# of the seeded run and emits prov.seed.* into that stage's manifest. Format is
# the same `key<spaces>value` shape as a manifest, so the same parsers work.
#-----------------------------------------------------------------------------
chain="$SRC_TAG"
if [ -s "$SRC_SEED" ]; then
    prev=$(awk '$1=="seed.chain" { $1=""; sub(/^ +/,""); print; exit }' "$SRC_SEED")
    [ -n "$prev" ] && chain="$SRC_TAG <- $prev"
fi

REC="$DST_DIR/reports/seed_record.txt"
{
    echo "# seed record -- this run did NOT run the stage named below."
    echo "# Written by scripts/ci/seed_build_run.sh. Read by prov_collect_seed"
    echo "# in the toolkit's flow/common/provenance.tcl, which turns these into"
    echo "# prov.seed.* fields in every stage manifest of this run."
    printf '%-24s %s\n' seed.stage           "$STAGE"
    printf '%-24s %s\n' seed.source_run      "$SRC_TAG"
    printf '%-24s %s\n' seed.netlist_sha256  "$seeded_sha"
    printf '%-24s %s\n' seed.chain           "$chain"
    printf '%-24s %s\n' seed.netlist_file    "$NETLIST_BASE"
    printf '%-24s %s\n' seed.verified_against "$(basename "$recorded_from")"
    printf '%-24s %s\n' seed.date            "$(date -u +'%Y-%m-%d %H:%M:%S') UTC"
    printf '%-24s %s\n' seed.by              "${USER:-unknown}@$(hostname -s)"
} > "$REC" || die "cannot write $REC"

echo "   record  : $REC"
echo "== seeded. This run will report prov.seed.source_run $SRC_TAG in every"
echo "   stage manifest, and reports/${STAGE}_manifest.txt will be ABSENT -"
echo "   correctly, because this run did not synthesise."
exit 0
