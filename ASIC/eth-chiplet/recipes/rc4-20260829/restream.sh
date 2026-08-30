#!/usr/bin/env bash
# Stream the holdfix database with EXACTLY the write_stream arguments rc2 and
# gdsrun-20260826-rc1 used (map, merge list, unit, lib name, -output_macros,
# -mode all). The map and the two ROM GDS were cp -a'd from rc2 and md5-verified
# at copy time, so this stream differs from rc2's only by the ECO geometry.
set -u
B="${RUN_DIR:?set RUN_DIR to the run directory}"
M="${MEM_BASE:?set MEM_BASE to the precompiled-memory root}"

export RESTREAM_DB=$B/db_rc4
export RESTREAM_MAP=$B/work/tech/gdsout.stream.map
export RESTREAM_GDS_OUT=$B/outputs/nanosoc_eth_chiplet_pads_rc4.gds
export RESTREAM_REPORT=$B/reports/nanosoc_eth_chiplet_pads_holdfix_stream.rep
export RESTREAM_UNIT=1000
export RESTREAM_LIB_NAME=DesignLib
export RESTREAM_MERGE="$M/rf_32k/rf_32k.gds2 $M/rf_16k/rf_16k.gds2 $M/rf_08k/rf_08k.gds2 $M/rf_01k/rf_01k.gds2 $M/flash_cache_data/flash_cache_data.gds2 $M/flash_cache_tag/flash_cache_tag.gds2 $B/romlibs/cc_rom/rom_via.gds2 $B/romlibs/eth_rom/eth_rom_via.gds2"

for f in $RESTREAM_MERGE $RESTREAM_MAP; do
    [ -r "$f" ] || { echo "FATAL: cannot read $f"; exit 1; }
done
[ -d "$RESTREAM_DB" ] || { echo "FATAL: no DB at $RESTREAM_DB"; exit 1; }

cd $B/work || exit 1
env -u DISPLAY "${INNOVUS:-innovus}" -stylus \
    -files "${REPO_ROOT:?set REPO_ROOT}"/ASIC/asic-toolkit/flow/verify/restream.tcl \
    < /dev/null > $B/logs/restream_console.log 2>&1
echo "innovus returned $? (not trusted - assert on the artefact)"
ls -l $RESTREAM_GDS_OUT 2>/dev/null && md5sum $RESTREAM_GDS_OUT | tee $RESTREAM_GDS_OUT.md5
