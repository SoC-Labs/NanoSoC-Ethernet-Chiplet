#!/usr/bin/env bash
# test_driver_fixes.sh -- repeatable tests for the hostio4 and ahb_qspi driver
# fixes of 2026-09-24, and the regression set they must not break.
#
#   test_driver_fixes.sh [--out DIR] OPENOCD [LEG ...]
#
# OPENOCD is the binary under test (it must carry both drivers). Every leg runs
# through run_proof_real.sh against a SOFTWARE far end: nothing here touches a
# board, a dongle, a GUI or a session. Exit status = number of failed legs.
#
# Each FIX leg fails on the driver as it was before the fix and passes after:
#   S   #1  mwb, mwh and two 7-byte load_images (byte+half+word head, and
#           word+half+byte tail) against adpmon.py: mdb reads back byte-exact,
#           and the monitor's own memory (h4check.py replay) holds exactly the
#           written bytes with NO other word changed. Before: whole-word writes
#           with the neighbouring lanes zeroed, landing in the wrong words,
#           two of them outside the images, rc 0.
#   D   #2  a block read whose third reply line is garbled in transit
#           (fake_mon.py drop-one): "short reply", no data. Before: the "A"
#           echo counted as word 0 and the read returned wrong data with rc 0.
#   T   #4  a far end that never goes quiet (fake_mon.py chatter-init, console
#           text every 2 ms): openocd is gone within 10 s of SIGTERM. Before:
#           stuck in the init drain for ever, SIGTERM ignored.
#   C   #4  the same chatter starting mid-session (chatter-cmd): the read times
#           out and openocd exits without being killed. Before: it hung in the
#           shutdown drain until the 20 s cap killed it.
#   F   deadline: the far end floods with no pause (flood-cmd), so the socket is
#           never empty: the read times out on its absolute deadline. Before:
#           the exchange never returned.
#   G1  guard, over the bench's own translation (adp-bridge WITHOUT --raw, and
#           prove-load-image-fakebench.py's dongle ']'->ESC in front of
#           adpmon.py), hostio4_block_write on: four 16-byte blocks, clean /
#           0x1b / 0x5d / 0x03 in every lane. The region at exit is exactly the
#           four images; the driver's counters show the clean block as one U
#           and each hazard block as four Wx; the bridge translated only the
#           mode-entry ESC and dropped no Ctrl-C. Before: the 0x5d block is
#           silently rewritten to 0x1b and the 0x03 block parks the monitor.
#   G2  guard, seen from the monitor (adpmon.py --trace, --raw bridge): one U
#           command in total, no 0x03/0x1b/0x5d inside any U payload, memory
#           exactly the four images.
#   Q1  ahb_qspi #8: `flash probe` with no flash fitted (RDID reads 0) and CTRL
#           found with XIP_ACTIVE=1: CTRL is 0x00000100 after the failed probe,
#           read through OpenOCD AND in the monitor's replayed memory.
#           Before: 0x00000000 (XiP left off).
#   Q2  ahb_qspi #8: the same, through the "unknown JEDEC ID" early return.
#   Q3  control: CTRL found with XiP OFF stays off (passes before and after).
# REGRESSION legs, which must pass before and after:
#   R   the six documented hardware-proof steps (PROOF-HARDWARE-2026-09-22.md),
#       against adpmon.py: dap init; mdw; mdw 8 as ONE R00000008; mww/mdw
#       round trip; an unmapped read reports a fault; the D2D window is refused
#       with nothing on the wire and the counters unchanged.
#   R7  an 8224-byte load_image: dump_image reads it back identical, and the
#       monitor's replayed memory holds exactly the image and nothing else.
set -u
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=
while [ $# -gt 0 ]; do
  case "$1" in
    --out) OUT=$2; shift 2 ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d; s/^# \{0,1\}//'; exit 0 ;;
    *) break ;;
  esac
done
[ $# -ge 1 ] || { echo "usage: $0 [--out DIR] OPENOCD [LEG ...]" >&2; exit 2; }
OOCD=$(readlink -f "$1"); shift
[ -x "$OOCD" ] || { echo "$0: $OOCD is not executable" >&2; exit 2; }
LEGS=${*:-S D T C F G1 G2 Q1 Q2 Q3 R R7}
OUT=${OUT:-$(mktemp -d "${TMPDIR:-/tmp}/h4tests.XXXXXX")}
mkdir -p "$OUT"
OUT=$(cd "$OUT" && pwd)
RUN=$HERE/run_proof_real.sh
CHK=$HERE/h4check.py
export QUIET=1
# no listening servers: nothing here may collide with a live session's ports
NOSRV=(-c "gdb_port disabled" -c "telnet_port disabled" -c "tcl_port disabled")

echo "test_driver_fixes: $OOCD"
echo "  md5 $(md5sum "$OOCD" | cut -d' ' -f1), $("$OOCD" --version 2>&1 | head -1)"
echo "  evidence in $OUT"

NPASS=0; NFAIL=0; SUMMARY=
LEG_BAD=0
check(){   # check "what must hold" command...
  local what=$1; shift
  if "$@" > /dev/null 2>&1; then echo "      ok    $what"; else echo "      FAIL  $what"; LEG_BAD=1; fi
}
leg_begin(){ LEG_BAD=0; echo "  --- $1: $2"; }
leg_end(){
  local t; t=$(cat "$OUT/$1.elapsed" 2>/dev/null || echo "?")
  if [ $LEG_BAD = 0 ]; then NPASS=$((NPASS + 1)); SUMMARY="$SUMMARY PASS:$1"; echo "  PASS  $1  (${t}s)"
  else NFAIL=$((NFAIL + 1)); SUMMARY="$SUMMARY FAIL:$1"; echo "  FAIL  $1  (${t}s)  -- see $OUT/$1.log"; fi
}
L(){ echo "$OUT/$1.log"; }
rc_is(){ grep -qx "openocd rc=$2" "$(L "$1")"; }
not_killed(){ ! grep -qE '^openocd rc=(124|137)$' "$(L "$1")"; }
eq(){ [ "$1" = "$2" ]; }
stats(){   # stats LEG N -> "block_reads single_reads word_writes block_writes faults" of the Nth hostio4_info
  grep ' wire stats' "$(L "$1")" | sed -n "${2}p" | tr -cs '0-9' ' ' | sed 's/^ *//; s/ *$//'
}

# ---------------------------------------------------------------- fix legs
leg_S(){
  leg_begin S "#1 byte/halfword writes and odd-sized load_image are byte-exact"
  printf '\x01\x02\x03\x04\x05\x06\x07' > "$OUT/seven.bin"
  local pre="0x200000FC=0x55555555 0x20000120=0x55555555" a
  for a in 100 104 108 10C 110 114 118 11C; do pre="$pre 0x20000$a=0xAAAAAAAA"; done
  PRELOAD="$pre" "$RUN" S "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init \
    -c "mwb 0x20000101 0x11" -c "mwh 0x20000106 0xBEEF" \
    -c "load_image $OUT/seven.bin 0x20000109 bin" -c "load_image $OUT/seven.bin 0x20000114 bin" \
    -c "mdb 0x20000100 32" -c shutdown
  python3 "$CHK" replay "$OUT/S.wire" "$OUT/S.preload" \
    --word 0x20000100=0xAAAA11AA --word 0x20000104=0xBEEFAAAA --word 0x20000108=0x030201AA \
    --word 0x2000010C=0x07060504 --word 0x20000114=0x04030201 --word 0x20000118=0xAA070605 \
    > "$OUT/S.replay" 2>&1
  local rrc=$?
  check "openocd rc=0" rc_is S 0
  check "both load_images report 7 bytes written" eq "$(grep -c '^7 bytes written' "$(L S)")" 2
  check "mdb 0x20000100 32 reads back aa 11 aa aa aa aa ef be aa 01..07 aa aa aa aa 01..07 aa aa aa aa aa" \
    grep -q '^0x20000100: aa 11 aa aa aa aa ef be aa 01 02 03 04 05 06 07 aa aa aa aa 01 02 03 04 05 06 07 aa aa aa aa aa *$' "$(L S)"
  check "monitor memory: exactly the 6 expected words changed, none outside (S.replay)" eq $rrc 0
  leg_end S
}

leg_D(){
  leg_begin D "#2 a garbled reply line in a block read is an error, not wrong data"
  FAR=fake_mon:drop-one "$RUN" D "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init -c "mdw 0x20000000 4" -c shutdown
  check "reported: 'short reply: wanted 4 words at 0x20000000, got 3'" \
    grep -q 'short reply: wanted 4 words at 0x20000000, got 3' "$(L D)"
  check "no data printed for the failed read" bash -c "! grep -q '^0x20000000:' '$(L D)'"
  check "the command failed (openocd rc != 0)" bash -c "! grep -qx 'openocd rc=0' '$(L D)'"
  leg_end D
}

leg_T(){
  leg_begin T "#4 console chatter from connect: openocd exits within 10 s of SIGTERM"
  FAR=fake_mon:chatter-init SIGTERM_AFTER=1 SIGTERM_GRACE=10 "$RUN" T "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init
  echo "      $(cat "$OUT/T.sigterm")"
  check "gone within 10 s of SIGTERM" grep -q '^sigterm: exited' "$OUT/T.sigterm"
  leg_end T
}

leg_C(){
  leg_begin C "#4 chatter mid-session: the read fails and shutdown completes"
  FAR=fake_mon:chatter-cmd:3 OOCD_TIMEOUT=20 "$RUN" C "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init -c "mdw 0x20000000" -c shutdown
  check "the read timed out" grep -q 'hostio4: timeout after' "$(L C)"
  check "openocd exited by itself (not killed at the 20 s cap)" not_killed C
  leg_end C
}

leg_F(){
  leg_begin F "absolute deadline: a far end that never pauses cannot hold an exchange open"
  FAR=fake_mon:flood-cmd:3 OOCD_TIMEOUT=20 "$RUN" F "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init -c "mdw 0x20000000" -c shutdown
  check "the read timed out" grep -q 'hostio4: timeout after' "$(L F)"
  check "openocd exited by itself (not killed at the 20 s cap)" not_killed F
  leg_end F
}

mk_guard_images(){
  printf '\x11\x22\x33\x44\x55\x66\x77\x88\x99\xaa\xbb\xcc\xdd\xee\xf0\x01' > "$OUT/g-clean.bin"
  printf '\x1b\x01\x02\x04\x05\x1b\x06\x07\x08\x09\x1b\x0a\x0c\x0e\x0f\x1b' > "$OUT/g-esc.bin"
  printf '\x5d\x01\x02\x04\x05\x5d\x06\x07\x08\x09\x5d\x0a\x0c\x0e\x0f\x5d' > "$OUT/g-brk.bin"
  printf '\x03\x01\x02\x04\x05\x03\x06\x07\x08\x09\x03\x0a\x0c\x0e\x0f\x03' > "$OUT/g-etx.bin"
  cat "$OUT/g-clean.bin" "$OUT/g-esc.bin" "$OUT/g-brk.bin" "$OUT/g-etx.bin" > "$OUT/g-all.bin"
}

leg_G1(){
  leg_begin G1 "block-write guard over the bench translation: hazard blocks go as Wx and arrive intact"
  mk_guard_images
  FAR=fakebench:0x10007000:64 EXTRA_CFG='hostio4_block_write on' OOCD_TIMEOUT=40 \
    "$RUN" G1 "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init \
    -c "load_image $OUT/g-clean.bin 0x10007000 bin" -c hostio4_info \
    -c "load_image $OUT/g-esc.bin 0x10007010 bin" -c hostio4_info \
    -c "load_image $OUT/g-brk.bin 0x10007020 bin" -c hostio4_info \
    -c "load_image $OUT/g-etx.bin 0x10007030 bin" -c hostio4_info -c shutdown
  check "openocd rc=0" rc_is G1 0
  check "region at exit (fakebench's own dump) == the four images" cmp -s "$OUT/G1.final" "$OUT/g-all.bin"
  check "clean block: one U, no Wx       (block writes 1, word writes 0)"  eq "$(stats G1 1 | cut -d' ' -f3,4)" "0 1"
  check "0x1b block: four Wx, no new U  (block writes 1, word writes 4)"  eq "$(stats G1 2 | cut -d' ' -f3,4)" "4 1"
  check "0x5d block: four Wx, no new U  (block writes 1, word writes 8)"  eq "$(stats G1 3 | cut -d' ' -f3,4)" "8 1"
  check "0x03 block: four Wx, no new U  (block writes 1, word writes 12)" eq "$(stats G1 4 | cut -d' ' -f3,4)" "12 1"
  check "bridge: only the mode-entry ESC translated, no Ctrl-C dropped" grep -q '1 ESC translated, 0 Ctrl-C dropped' "$OUT/G1.bridge"
  leg_end G1
}

leg_G2(){
  leg_begin G2 "block-write guard seen from the monitor: no hazard byte inside any U payload"
  mk_guard_images
  EXTRA_CFG='hostio4_block_write on' OOCD_TIMEOUT=40 \
    "$RUN" G2 "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init \
    -c "load_image $OUT/g-clean.bin 0x20000200 bin" -c "load_image $OUT/g-esc.bin 0x20000210 bin" \
    -c "load_image $OUT/g-brk.bin 0x20000220 bin" -c "load_image $OUT/g-etx.bin 0x20000230 bin" -c shutdown
  python3 "$CHK" replay "$OUT/G2.wire" "$OUT/G2.preload" --bytes "$OUT/g-all.bin@0x20000200" > "$OUT/G2.replay" 2>&1
  local rrc=$?
  check "openocd rc=0" rc_is G2 0
  check "exactly one U command reached the monitor (the clean block)" \
    eq "$(python3 "$CHK" count "$OUT/G2.wire" 'U[xX ]?[0-9A-Fa-f]+')" 1
  check "no 0x03/0x1b/0x5d byte inside any U payload" eq "$(python3 "$CHK" payload-has "$OUT/G2.wire" 0x03,0x1b,0x5d)" 0
  check "monitor memory == the four images, nothing else changed (G2.replay)" eq $rrc 0
  leg_end G2
}

qspi_leg(){   # qspi_leg NAME TITLE PRELOAD CTRL_AS_FOUND MESSAGE
  leg_begin "$1" "$2"
  PRELOAD="$3" EXTRA_CFG='flash bank qspi ahb_qspi 0x24000000 0x400000 0 0 chip.ahb' \
    "$RUN" "$1" "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init -c "mdw 0x21000000" \
    -c 'echo "probe rc=[catch {flash probe 0}]"' -c "mdw 0x21000000" -c shutdown
  check "CTRL read before the probe: $4" eq "$(grep '^0x21000000:' "$(L "$1")" | sed -n 1p | tr -d ' ')" "0x21000000:$4"
  check "the probe failed: '$5'" grep -q "$5" "$(L "$1")"
  check "the probe returned an error" grep -q '^probe rc=-' "$(L "$1")"
  check "CTRL read after the failed probe: $4 (as found)" eq "$(grep '^0x21000000:' "$(L "$1")" | sed -n 2p | tr -d ' ')" "0x21000000:$4"
  check "CTRL in the monitor's replayed memory: 0x$4" eq "$(python3 "$CHK" peek "$OUT/$1.wire" "$OUT/$1.preload" 0x21000000)" "0x$4"
  leg_end "$1"
}
leg_Q1(){ qspi_leg Q1 "ahb_qspi #8: no flash, XiP on: the failed probe leaves XiP on" \
  "0x21000000=0x00000100" 00000100 "no flash responded to RDID"; }
leg_Q2(){ qspi_leg Q2 "ahb_qspi #8: unknown JEDEC ID, XiP on: the failed probe leaves XiP on" \
  "0x21000000=0x00000100 0x21000010=0x00ABCDEF" 00000100 "unknown flash, JEDEC ID"; }
leg_Q3(){ qspi_leg Q3 "ahb_qspi control: no flash, XiP off: stays off" \
  "0x21000000=0x00000000" 00000000 "no flash responded to RDID"; }

# ---------------------------------------------------------- regression legs
leg_R(){
  leg_begin R "the six hardware-proof steps (PROOF-HARDWARE-2026-09-22.md)"
  "$RUN" R "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init -c targets \
    -c "mdw 0x08000000" \
    -c hostio4_info -c "mdw 0x08000000 8" -c hostio4_info \
    -c "mww 0x2100000C 0x0badc0de" -c "mdw 0x2100000C" \
    -c 'echo "unmapped rc=[catch {mdw 0x30000000}]"' -c hostio4_info \
    -c 'echo "d2d rc=[catch {mdw 0x2E000000}]"' -c hostio4_info -c shutdown
  local l; l=$(L R)
  check "openocd rc=0" rc_is R 0
  check "1 dap init: the monitor responds and the mem_ap target exists" \
    bash -c "grep -q 'ADP monitor is responding' '$l' && grep -q 'chip.ahb *mem_ap' '$l'"
  check "2 mdw 0x08000000 = b0070000 (the preloaded ROM word)" grep -qx '0x08000000: b0070000 *' "$l"
  check "3 mdw 0x08000000 8: the eight preloaded words" \
    grep -q '^0x08000000: b0070000 b0070001 b0070002 b0070003 b0070004 b0070005 b0070006 b0070007' "$l"
  check "3 ... as ONE R00000008 on the wire" eq "$(python3 "$CHK" count "$OUT/R.wire" 'R00000008')" 1
  check "3 ... counters: block reads +1, single reads unchanged" \
    eq "$(stats R 2 | awk '{print $1-0, $2}')" "$(stats R 1 | awk '{print $1+1, $2}')"
  check "4 mww/mdw 0x2100000C round trip = 0badc0de" grep -qx '0x2100000c: 0badc0de *' "$l"
  check "5 unmapped 0x30000000 reports the bus fault" grep -q "AHB bus error reading 0x30000000" "$l"
  check "5 ... and the command fails" grep -q '^unmapped rc=[^0]' "$l"
  check "5 ... counters: bus faults 1" eq "$(stats R 3 | cut -d' ' -f5)" 1
  check "6 D2D 0x2E000000 refused by the driver" grep -q 'refusing access to 0x2e000000' "$l"
  check "6 ... counters unchanged across the refused access" eq "$(stats R 4)" "$(stats R 3)"
  check "6 ... nothing addressed the D2D window on the wire" eq "$(python3 "$CHK" count "$OUT/R.wire" 'A[xX]2[Ee].*')" 0
  leg_end R
}

leg_R7(){
  leg_begin R7 "an 8224-byte load_image lands byte-exact and nowhere else"
  python3 -c 'import sys; sys.stdout.buffer.write(bytes((i * 37 + (i >> 8) * 11) & 0xff for i in range(8224)))' > "$OUT/big.bin"
  rm -f "$OUT/R7.dump"
  OOCD_TIMEOUT=120 "$RUN" R7 "$OOCD" "$OUT" -- "${NOSRV[@]}" -c init \
    -c "load_image $OUT/big.bin 0x20001000 bin" -c "dump_image $OUT/R7.dump 0x20001000 8224" -c shutdown
  python3 "$CHK" replay "$OUT/R7.wire" "$OUT/R7.preload" --bytes "$OUT/big.bin@0x20001000" > "$OUT/R7.replay" 2>&1
  local rrc=$?
  check "openocd rc=0" rc_is R7 0
  check "8224 bytes written at address 0x20001000" grep -q '^8224 bytes written at address 0x20001000' "$(L R7)"
  check "dump_image reads back the image byte for byte" cmp -s "$OUT/R7.dump" "$OUT/big.bin"
  check "monitor memory == the image, nothing else changed (R7.replay)" eq $rrc 0
  leg_end R7
}

for leg in $LEGS; do
  if declare -F "leg_$leg" > /dev/null; then "leg_$leg"
  else echo "  unknown leg $leg"; NFAIL=$((NFAIL + 1)); SUMMARY="$SUMMARY FAIL:$leg(unknown)"; fi
done
echo "test_driver_fixes: $NPASS passed, $NFAIL failed --$SUMMARY"
exit $NFAIL
