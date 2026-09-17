#!/usr/bin/env bash
# Run the hostio4 driver's proofs against the RTL-cited reference monitor
# (HAPS-work adpmon.py) through the real transport (HAPS-work adp-bridge),
# instead of the bootstrap fake_adp.py.
#
#   run_proof_real.sh <name> <openocd-binary> <outdir> -- <openocd -c args...>
#
# Chain:   adpmon.py --tcp PA  <--  adp-bridge --raw --tcp PB  <--  openocd
# Nothing here touches hardware.  HAPS-work is read-only: both tools are
# invoked from their own tree and never copied or modified.
set -u
HAPS=${HAPS:-/home/dam1n19/SoCLabs/HAPS-work/fpga/haps-sx/hostio}
ADPMON=$HAPS/adpmon.py
BRIDGE=$HAPS/adp-bridge
NAME=$1; OOCD=$2; OUT=$3; shift 3
[ "$1" = "--" ] && shift

PA=${PA:-24820}
PB=${PB:-24821}
mkdir -p "$OUT"
B=$OUT/$NAME
rm -f "$B".*

# the reference monitor.  --preload gives the boot ROM a ramp so a block read
# is visibly a block read; every other address keeps adpmon's own defaults.
PRE=()
for i in 0 1 2 3 4 5 6 7; do
  PRE+=(--preload "$((0x08000000 + 4*i))=$((0xB0070000 + i))")
done
python3 "$ADPMON" --tcp 127.0.0.1:$PA --once --idle-exit 20 \
        --trace "$B.wire" "${PRE[@]}" ${EXTRA_MON[@]+"${EXTRA_MON[@]}"} > "$B.mon" 2>&1 &
MONPID=$!
for i in $(seq 1 60); do grep -q "^127" "$B.mon" 2>/dev/null && break; sleep 0.1; done

# the real transport.  --raw: adpmon IS the monitor, there is no console
# bridge in front of it to remap ESC.
python3 "$BRIDGE" --up tcp:127.0.0.1:$PA --raw --tcp 127.0.0.1:$PB --once \
        --idle-exit 20 > "$B.bridge" 2>&1 &
BRPID=$!
for i in $(seq 1 60); do grep -q "listening" "$B.bridge" 2>/dev/null && break; sleep 0.1; done

sed "s|@PORT@|127.0.0.1:$PB|" "$(dirname "$0")/hostio4-fake.cfg" > "$B.cfg"
timeout 90 "$OOCD" -s "$(dirname "$OOCD")/../tcl" -f "$B.cfg" "$@" > "$B.log" 2>&1
echo "openocd rc=$?" >> "$B.log"
wait $BRPID 2>/dev/null; wait $MONPID 2>/dev/null
kill $BRPID $MONPID 2>/dev/null

echo "########## $NAME : openocd ##########"
grep -v '^For bug reports\|^\s*http://openocd.org\|Licensed under\|^Open On-Chip\|adapter speed is not selected\|To remove this warnings' "$B.log"
echo "########## $NAME : bridge ##########"
cat "$B.bridge"
echo "########## $NAME : wire (adpmon's own trace) ##########"
cat "$B.wire"
