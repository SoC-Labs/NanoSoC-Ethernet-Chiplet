#!/usr/bin/env bash
# capture_readpark.sh - the read-park experiment, as ONE scripted run.
#
# WHY SCRIPTED: a parked peer port is a ONE-SHOT event per power-cycle. The next
# cross-die WRITE after the park hangs the host with no timeout (measured
# 2026-08-24), so improvising the order costs the whole experiment and a JTAG POR.
#
# ORDER IS THE POINT: reads before any write, and never a write at all.
#   1  bring up both dies, confirm fcsm=4
#   2  0x21F8 PRE, both dies
#   2b INSTRUMENT CHECK: run the poll harness on a HEALTHY port first, so a
#      post-failure reading cannot be the only thing it has ever produced.
#      Verify the instrument before the DUT.
#   3  READ #1             -> expect SIGBUS, parks the port
#   4  poll 0x21F8 30 s, full word + timestamps  <- CAPTURE 1 (+ recovery latency)
#   4b GATE: sample bit[0] immediately before READ #2.
#      If the port RECOVERED during step 4, then READ #2 tests a RECOVERED port,
#      not a parked one -- a clean result would read as "reads error bounded"
#      when it actually means "the port came back". Capture 2 is only valid if
#      bit[0] is still 0 here. Interpret conditionally; do not conflate.
#   5  READ #2 (a READ)    <- CAPTURE 2: bounded error, or wedge?
#   6  0x21F8 POST, both dies
#   7  STOP. No write. We already know the write wedges the host.
#
# Recovery if it wedges anyway:
#   ssh mapstone-dev.ecs.soton.ac.uk 'fpgahub target reset kr260_01 --method default'
#   (the GROUP `board reset` fails HTTP 400 on the _pl member; ~50 s to ping,
#    SSH lags ping by ~20 s)
set -u
A=${A_HOST:-ubuntu@10.22.24.159}
B=${B_HOST:-ubuntu@10.22.24.153}
PW=${KR260_PASSWORD:?set KR260_PASSWORD}
R=${REPO:-/home/dam1n19/SoCLabs/nanosoc-ethernet-chiplet}
RUN="$R/tidelink/pynq_host/scripts/kr260_eth_run.sh"
SSH="ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10"
RD="cd td && echo $PW | sudo -S -p '' python3 rd21f8_eth.py"
log(){ echo; echo "######## $* :: $(date -u +%T) ########"; }

log "0. PRE-FLIGHT boot-epoch check (a PL load does NOT survive a reboot)"
for h in "$A" "$B"; do
  echo -n "  $h: "; timeout 30 $SSH "$h" 'echo "boot=$(uptime -s) bin=$(stat -c %y ~/td/tidelink.bin|cut -d. -f1) fpga=$(cat /sys/class/fpga_manager/fpga0/state)"' 2>&1|tail -1
done
echo "  ^ if bin is OLDER than boot, REDEPLOY before continuing or the fabric is not your design."

log "1. BRING UP BOTH DIES"
( KR260_HOST=$A KR260_PASSWORD=$PW KR260_ETH_ROLE=die_a timeout 120 bash "$RUN" bringup >/tmp/cap_a.log 2>&1 ) &
( KR260_HOST=$B KR260_PASSWORD=$PW KR260_ETH_ROLE=die_b timeout 120 bash "$RUN" bringup >/tmp/cap_b.log 2>&1 ) &
wait
grep -E "RESULT:|EPOCH_STATUS" /tmp/cap_a.log | tail -2
grep -E "RESULT:|EPOCH_STATUS" /tmp/cap_b.log | tail -2
if ! grep -q "fcsm=4" /tmp/cap_a.log; then echo "  !! die_a not at fcsm=4 - ABORT, retry bring-up"; exit 1; fi

log "2. 0x21F8 PRE"
echo "-- die_a:"; timeout 40 $SSH "$A" "$RD" 2>&1 | grep -E "OBS|\[ 9\]|\[10\]|\[ 0\]"
echo "-- die_b:"; timeout 40 $SSH "$B" "$RD" 2>&1 | grep -E "OBS|\[ 9\]|\[10\]|\[ 0\]"

log "2b. INSTRUMENT CHECK - poll harness on a HEALTHY port (expect 0xB5000001, raw=1)"
timeout 60 $SSH "$A" "cd td && echo $PW | sudo -S -p '' python3 poll21f8.py 2 0.2 --tag PRECHK" 2>&1 | grep -vE "^\[sudo"
echo "  ^ must show raw=1 and status=HEALTHY. If it does not, the instrument is"
echo "    wrong or the port is ALREADY parked - fix that before spending the POR."

log "3. READ #1 (expect SIGBUS; this parks the port)"
KR260_HOST=$A KR260_PASSWORD=$PW timeout 120 bash "$RUN" xfer_readback 2>&1 | tail -3

log "4. CAPTURE 1 - poll 0x21F8 bit[0] for 30 s"
timeout 90 $SSH "$A" "cd td && echo $PW | sudo -S -p '' python3 poll21f8.py 30 0.2" 2>&1 | grep -vE "^\[sudo"

log "4b. GATE - is the port STILL parked? (decides whether capture 2 is valid)"
GATE=$(timeout 40 $SSH "$A" "$RD" 2>&1 | grep -oE "\[ 0\] xhb_sub_hreadyout_raw   = [01]" | grep -oE "[01]$")
echo "  hreadyout_raw immediately before READ #2 = ${GATE:-unknown}"
if [ "${GATE:-1}" = "1" ]; then
  echo "  !! PORT RECOVERED during step 4."
  echo "     Capture 1 HAS its answer (see status= above), but CAPTURE 2 IS NOT VALID:"
  echo "     READ #2 would test a recovered port, not a parked one. Recording that"
  echo "     explicitly rather than reporting a misleading clean result."
else
  echo "  port still parked -> capture 2 is valid."
fi

log "5. CAPTURE 2 - READ #2 (a READ, deliberately NOT a write)"
KR260_HOST=$A KR260_PASSWORD=$PW timeout 120 bash "$RUN" xfer_readback 2>&1 | tail -3
echo "  INTERPRET WITH THE GATE ABOVE: valid only if hreadyout_raw was 0 before this read." 

log "6. 0x21F8 POST"
echo "-- die_a:"; timeout 40 $SSH "$A" "$RD" 2>&1 | grep -E "OBS|\[ 9\]|\[10\]|\[ 0\]"
echo "-- die_b:"; timeout 40 $SSH "$B" "$RD" 2>&1 | grep -E "OBS|\[ 9\]|\[10\]|\[ 0\]"

log "7. DONE - no write issued, by design"
for h in "$A" "$B"; do echo -n "  $h alive: "; ping -c2 -W2 "${h#*@}" >/dev/null 2>&1 && echo yes || echo "NO - JTAG POR needed"; done
