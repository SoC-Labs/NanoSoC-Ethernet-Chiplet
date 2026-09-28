#!/usr/bin/env bash
# test_dma250_quiesce.sh -- prove dma250_quiesce.tcl against dma_mon.py (adpmon.py
# plus a DMA-250 pause-register model and an erratum oracle). No hardware.
#
#   test_dma250_quiesce.sh [--out DIR] OPENOCD
#
# OPENOCD must carry the hostio4 adapter (e.g. soclabs-openocd/install/bin/openocd).
# Legs (exit status = number of failed legs):
#   C0  CONTROL, no quiesce, DMA running: an mww to network-core IMEM is dropped
#       and a violation is recorded. Proves the oracle can fail a test.
#   Q1  dma250_quiesced { mww 0x10000000 } with the DMA running: the word lands,
#       0 violations, the pause is requested before and released after.
#   Q2  nested pause + load_image (8 words) into CPU1 IMEM 0x9000_0000 and a
#       readback: lands, 0 violations, exactly one request and one release.
#   Q3  the DMA never acknowledges: dma250_pause errors, the body never runs,
#       IMEM unchanged, 0 violations.
#   Q4  ALLCHPAUSE already set by someone else: the body runs, this session does
#       not release it.
#   Q5  MUTANT: the naive quiesce -- no ALLCHPAUSE request, and "paused" read
#       from the sticky STAT_ALLCHIDLE bit. The oracle must catch it (the body
#       runs unpaused and a violation is recorded), or the harness cannot tell
#       a correct quiesce from a wrong one.
#   G1  dma250_hold_for_gdb: arm-none-eabi-gdb attaches to the mem_ap target and
#       detaches: exactly one pause at attach and one release at detach. (Memory
#       access through gdb on mem_ap is not tested: stock arm-none-eabi-gdb 10.3
#       crashes on this target before any memory packet -- README.md:131-132.)
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=$(mktemp -d)
[ "${1:-}" = "--out" ] && { OUT=$2; shift 2; }
OOCD=${1:?usage: $0 [--out DIR] OPENOCD}
mkdir -p "$OUT"
FAILS=0

free_port(){ python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }

# leg NAME "dma_mon args" "openocd -c script" CHECK...
leg() {
  local name=$1 margs=$2 script=$3; shift 3
  local P; P=$(free_port)
  python3 "$HERE/dma_mon.py" --tcp 127.0.0.1:$P --once --idle-exit 10 \
      --report "$OUT/$name.report" --dump 0x10000000:1 --dump 0x90000000:8 $margs \
      > "$OUT/$name.mon" 2>&1 &
  local MP=$!
  for i in $(seq 1 60); do grep -q "^127" "$OUT/$name.mon" 2>/dev/null && break; sleep 0.1; done
  sed "s|@PORT@|127.0.0.1:$P|" "$HERE/hostio4-fake.cfg" > "$OUT/$name.cfg"
  timeout -k 5 60 "$OOCD" -s "$(dirname "$OOCD")/../share/openocd/scripts" -f "$OUT/$name.cfg" \
      -c "telnet_port disabled" -c "tcl_port disabled" \
      -c "init" -c "$script" -c "shutdown" > "$OUT/$name.log" 2>&1
  echo "openocd rc=$?" >> "$OUT/$name.log"
  wait $MP 2>/dev/null
  local ok=1 c
  for c in "$@"; do
    if ! eval "$c"; then ok=0; echo "    check failed: $c"; fi
  done
  if [ $ok = 1 ]; then echo "PASS $name"; else echo "FAIL $name (see $OUT/$name.*)"; FAILS=$((FAILS+1)); fi
}
rep() { grep -q -- "$2" "$OUT/$1.report"; }
nrep() { ! grep -q -- "$2" "$OUT/$1.report"; }
cnt() { [ "$(grep -o -- "$2" "$OUT/$1.report" | wc -l)" = "$3" ]; }
TCL="source $HERE/dma250_quiesce.tcl"

leg C0 "--dma-running" \
  "mww 0x10000000 0x11111111" \
  'rep C0 "violations [1-9]"' 'rep C0 "mem 0x10000000 0x00000000"'

leg Q1 "--dma-running" \
  "$TCL; dma250_quiesced { mww 0x10000000 0x11111111 }" \
  'rep Q1 "violations 0"' 'rep Q1 "mem 0x10000000 0x11111111"' \
  'rep Q1 "events pause-req release"' 'rep Q1 "final ALLCHPAUSE 0"'

printf '%08x\n' 0x0A0B0C01 0x0A0B0C02 0x0A0B0C03 0x0A0B0C04 0x0A0B0C05 0x0A0B0C06 0x0A0B0C07 0x0A0B0C08 \
  | python3 -c 'import sys,struct; sys.stdout.buffer.write(b"".join(struct.pack("<I",int(l,16)) for l in sys.stdin))' \
  > "$OUT/img8.bin"
leg Q2 "--dma-running" \
  "$TCL; dma250_pause; dma250_quiesced { load_image $OUT/img8.bin 0x90000000 bin; echo \"RB [read_memory 0x90000000 32 8]\" }; dma250_release" \
  'rep Q2 "violations 0"' 'rep Q2 "mem 0x9000001c 0x0a0b0c08"' 'cnt Q2 "pause-req" 1' 'cnt Q2 "release" 1' \
  'grep -q "^RB " "$OUT/Q2.log"'

leg Q3 "--dma-running --dma-no-ack" \
  "$TCL; if {[catch {dma250_quiesced { mww 0x10000000 0x22222222 }} msg]} { echo \"REFUSED: \$msg\" }" \
  'rep Q3 "violations 0"' 'rep Q3 "mem 0x10000000 0x00000000"' 'grep -q "REFUSED: dma250_pause: the DMA-250 did not acknowledge" "$OUT/Q3.log"'

leg Q4 "--dma-running --dma-paused-by-other" \
  "$TCL; dma250_quiesced { mww 0x10000000 0x33333333 }" \
  'rep Q4 "violations 0"' 'rep Q4 "mem 0x10000000 0x33333333"' 'rep Q4 "final ALLCHPAUSE 1"' 'nrep Q4 "release"'

sed -e 's@dma250q_wr $ctrl_a \[expr {$ctrl | $ALLCHPAUSE}\]@# MUTANT: request removed@' \
    -e 's@set ST_PAUSED \[expr {1 << 19}\]@set ST_PAUSED [expr {1 << 17}] ;# MUTANT: sticky ALLCHIDLE@' \
    "$HERE/dma250_quiesce.tcl" > "$OUT/mutant.tcl"
[ "$(grep -c MUTANT "$OUT/mutant.tcl")" -ge 3 ] || { echo "FAIL Q5 (mutant not applied)"; FAILS=$((FAILS+1)); }
leg Q5 "--dma-running" \
  "source $OUT/mutant.tcl; dma250_quiesced { mww 0x10000000 0x44444444 }" \
  'rep Q5 "violations [1-9]"' 'rep Q5 "mem 0x10000000 0x00000000"'

# G1: gdb attach/detach hold (needs arm-none-eabi-gdb on PATH; skipped if absent)
if command -v arm-none-eabi-gdb >/dev/null 2>&1; then
  P=$(free_port); G=$(free_port); name=G1
  python3 "$HERE/dma_mon.py" --tcp 127.0.0.1:$P --once --idle-exit 10 --report "$OUT/$name.report" \
      --dump 0x10000000:1 --dma-running > "$OUT/$name.mon" 2>&1 &
  MP=$!
  for i in $(seq 1 60); do grep -q "^127" "$OUT/$name.mon" 2>/dev/null && break; sleep 0.1; done
  sed "s|@PORT@|127.0.0.1:$P|" "$HERE/hostio4-fake.cfg" | sed "s|-ap-num 0|-ap-num 0 -gdb-port $G|" > "$OUT/$name.cfg"
  timeout -k 5 60 "$OOCD" -f "$OUT/$name.cfg" -c "telnet_port disabled" -c "tcl_port disabled" \
      -c "source $HERE/dma250_quiesce.tcl" \
      -c "dma250_hold_for_gdb chip.ahb" -c "init" > "$OUT/$name.log" 2>&1 &
  OP=$!
  for i in $(seq 1 100); do grep -q "Listening on port $G" "$OUT/$name.log" 2>/dev/null && break; sleep 0.1; done
  timeout 40 arm-none-eabi-gdb -nx -batch -ex "set remotetimeout 10" -ex "target extended-remote 127.0.0.1:$G" \
      -ex "detach" \
      > "$OUT/$name.gdb" 2>&1
  sleep 1; kill $OP 2>/dev/null; wait $OP 2>/dev/null; wait $MP 2>/dev/null
  ok=1
  for c in 'rep G1 "violations 0"' 'cnt G1 "pause-req" 1' 'cnt G1 "release" 1' \
           'grep -q "dma250_quiesce: DMA-250 paused" "$OUT/G1.log"' 'grep -q "dma250_quiesce: DMA-250 released" "$OUT/G1.log"'; do
    eval "$c" || { ok=0; echo "    check failed: $c"; }
  done
  if [ $ok = 1 ]; then echo "PASS G1"; else echo "FAIL G1 (see $OUT/G1.*)"; FAILS=$((FAILS+1)); fi
else
  echo "SKIP G1 (no arm-none-eabi-gdb)"
fi

echo "failed legs: $FAILS  (artefacts in $OUT)"
exit $FAILS
