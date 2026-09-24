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
#
# Knobs (environment; all optional -- unset, this is the chain above):
#   FAR=adpmon                 the far end (default)
#   FAR=fake_mon:MODE[:AFTER]  ./fake_mon.py, a deliberately misbehaving
#                              monitor, connected DIRECTLY (no bridge: the
#                              bridge's own pacing would hide the fault)
#   FAR=fakebench:ADDR:SIZE    HAPS-work prove-load-image-fakebench.py: the
#                              dongle's ']'->ESC + adpmon.py; the region's
#                              contents at exit land in <name>.final. Its
#                              <name>.wire comes back EMPTY (it leaves by
#                              os._exit() without flushing --trace): read
#                              .final and the bridge's counters instead
#   BRIDGE=raw|bench|none      adp-bridge with --raw (default for adpmon),
#                              without it (ESC->']' and 0x03 dropped, as on the
#                              bench; default for fakebench), or no bridge
#   PRELOAD="A=W A=W ..."      adpmon --preload words (adpmon only)
#   EXTRA_CFG='line\nline'     appended to the generated openocd cfg
#   OOCD_TIMEOUT=90            wall-clock cap on openocd (then SIGKILL)
#   SIGTERM_AFTER=S            send openocd SIGTERM S seconds after it starts,
#   SIGTERM_GRACE=10           and record in <name>.sigterm whether it was gone
#                              within SIGTERM_GRACE seconds (then SIGKILL)
#   QUIET=1                    do not print the log/bridge/wire afterwards
#   PA= PB=                    ports; unset, two free ones are picked
# Every run leaves <name>.{cfg,log,mon,bridge,wire,elapsed} in <outdir>;
# <name>.log ends "openocd rc=N".
set -u
HAPS=${HAPS:-/home/dam1n19/SoCLabs/HAPS-work/fpga/haps-sx/hostio}
ADPMON=$HAPS/adpmon.py
BRIDGE_PY=$HAPS/adp-bridge
FAKEBENCH=${FAKEBENCH:-$HAPS/../../../docs/bench/tools/prove-load-image-fakebench.py}
HERE=$(cd "$(dirname "$0")" && pwd)
NAME=$1; OOCD=$2; OUT=$3; shift 3
[ "${1:-}" = "--" ] && shift

free_port(){ python3 -c 'import socket; s=socket.socket(); s.bind(("127.0.0.1",0)); print(s.getsockname()[1])'; }
PA=${PA:-$(free_port)}
PB=${PB:-$(free_port)}
FAR=${FAR:-adpmon}
case "$FAR" in
  adpmon)      BRIDGE=${BRIDGE:-raw} ;;
  fakebench:*) BRIDGE=${BRIDGE:-bench} ;;
  fake_mon:*)  BRIDGE=none ;;
  *) echo "run_proof_real.sh: unknown FAR=$FAR" >&2; exit 2 ;;
esac
mkdir -p "$OUT"
B=$OUT/$NAME
rm -f "$B".*

MONPID=; BRPID=
case "$FAR" in
adpmon)
  # the reference monitor.  --preload gives the boot ROM a ramp so a block read
  # is visibly a block read; every other address keeps adpmon's own defaults.
  PRE=()
  for i in 0 1 2 3 4 5 6 7; do
    PRE+=(--preload "$((0x08000000 + 4*i))=$((0xB0070000 + i))")
  done
  for p in ${PRELOAD:-}; do PRE+=(--preload "$p"); done
  printf '%s\n' "${PRE[@]}" | paste -d' ' - - > "$B.preload"
  python3 "$ADPMON" --tcp 127.0.0.1:$PA --once --idle-exit 20 \
          --trace "$B.wire" "${PRE[@]}" ${EXTRA_MON[@]+"${EXTRA_MON[@]}"} > "$B.mon" 2>&1 &
  MONPID=$!
  for i in $(seq 1 60); do grep -q "^127" "$B.mon" 2>/dev/null && break; sleep 0.1; done
  ;;
fake_mon:*)
  IFS=: read -r _ FMODE FAFTER <<< "$FAR"
  python3 "$HERE/fake_mon.py" "$FMODE" "$PA" ${FAFTER:+"$FAFTER"} > "$B.mon" 2>&1 &
  MONPID=$!
  for i in $(seq 1 60); do grep -q "^listening" "$B.mon" 2>/dev/null && break; sleep 0.1; done
  : > "$B.wire"
  ;;
fakebench:*)
  IFS=: read -r _ FADDR FSIZE <<< "$FAR"
  python3 "$FAKEBENCH" --tcp 127.0.0.1:$PA --region "$FADDR:$FSIZE" \
          --final "$B.final" --original "$B.original" --trace "$B.wire" > "$B.mon" 2>&1 &
  MONPID=$!
  for i in $(seq 1 60); do grep -q "^listening" "$B.mon" 2>/dev/null && break; sleep 0.1; done
  ;;
esac

PORT=$PA
if [ "$BRIDGE" != none ]; then
  # the real transport.  --raw: adpmon IS the monitor, there is no console
  # bridge in front of it to remap ESC.  Without --raw the bench's own
  # translation is live, which only makes sense with the dongle's half
  # (fakebench) at the far end.
  RAW=--raw; [ "$BRIDGE" = bench ] && RAW=
  python3 "$BRIDGE_PY" --up tcp:127.0.0.1:$PA $RAW --tcp 127.0.0.1:$PB --once \
          --idle-exit 20 > "$B.bridge" 2>&1 &
  BRPID=$!
  for i in $(seq 1 60); do grep -q "listening" "$B.bridge" 2>/dev/null && break; sleep 0.1; done
  PORT=$PB
else
  : > "$B.bridge"
fi

{ sed "s|@PORT@|127.0.0.1:$PORT|" "$HERE/hostio4-fake.cfg"; printf '%b\n' "${EXTRA_CFG:-}"; } > "$B.cfg"

T0=$(date +%s.%N)
if [ -n "${SIGTERM_AFTER:-}" ]; then
  exec 3>&2 2>/dev/null     # not bash's own "Terminated" job notice
  "$OOCD" -s "$(dirname "$OOCD")/../tcl" -f "$B.cfg" "$@" > "$B.log" 2>&1 &
  OPID=$!
  sleep "$SIGTERM_AFTER"
  if kill -0 $OPID 2>/dev/null; then
    kill -TERM $OPID
    TS=$(date +%s.%N)
    GRACE=${SIGTERM_GRACE:-10}
    for i in $(seq 1 $((GRACE * 10))); do kill -0 $OPID 2>/dev/null || break; sleep 0.1; done
    if kill -0 $OPID 2>/dev/null; then
      echo "sigterm: STILL RUNNING ${GRACE}s after SIGTERM -- killed" > "$B.sigterm"
      kill -KILL $OPID 2>/dev/null
    else
      awk -v a="$TS" -v b="$(date +%s.%N)" 'BEGIN{printf "sigterm: exited %.1fs after SIGTERM\n", b-a}' > "$B.sigterm"
    fi
  else
    echo "sigterm: had already exited before SIGTERM" > "$B.sigterm"
  fi
  wait $OPID 2>/dev/null; RC=$?
  exec 2>&3 3>&-
else
  exec 3>&2 2>/dev/null     # not bash's own "Killed" job notice
  timeout -k 5 "${OOCD_TIMEOUT:-90}" "$OOCD" -s "$(dirname "$OOCD")/../tcl" -f "$B.cfg" "$@" > "$B.log" 2>&1
  RC=$?
  exec 2>&3 3>&-
fi
awk -v a="$T0" -v b="$(date +%s.%N)" 'BEGIN{printf "%.1f\n", b-a}' > "$B.elapsed"
echo "openocd rc=$RC" >> "$B.log"

# The bridge, adpmon and fake_mon serve one client and exit when it leaves
# (given up to 5 s); fakebench serves for ever and writes <name>.final on
# SIGTERM, so it is stopped as soon as the bridge has gone.
alive(){ [ -n "$1" ] && kill -0 "$1" 2>/dev/null; }
for i in $(seq 1 50); do alive "$BRPID" || break; sleep 0.1; done
case "$FAR" in fakebench:*) ;; *)
  for i in $(seq 1 50); do alive "$MONPID" || break; sleep 0.1; done ;;
esac
[ -n "$BRPID" ] && kill $BRPID 2>/dev/null
kill -TERM $MONPID 2>/dev/null
wait 2>/dev/null

[ "${QUIET:-0}" = 1 ] && exit 0
echo "########## $NAME : openocd ##########"
grep -v '^For bug reports\|^\s*http://openocd.org\|Licensed under\|^Open On-Chip\|adapter speed is not selected\|To remove this warnings' "$B.log"
echo "########## $NAME : bridge ##########"
cat "$B.bridge"
echo "########## $NAME : wire (the far end's own trace) ##########"
cat "$B.wire"
