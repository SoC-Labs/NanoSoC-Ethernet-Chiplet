#!/usr/bin/env bash
# =============================================================================
# tl042_v2_arm.sh — ONE arm of the TL-042 v2 NO-HARM delivery A/B (KR260 pair).
#
# WHAT THIS MEASURES (read docs/HW_VALIDATION_PLAN_TL042_V2.md first)
# ------------------------------------------------------------------
# This is v2 *NO-HARM*, NOT v2-fixes-the-wedge. The acceptance question is:
#
#     does this arm deliver byte-exact cross-die, at the SAME rate as the
#     other arm, on anchor-good bring-ups?
#
# So this script does NOT inject an error and does NOT ask "does die_a survive
# an errinject" — a v2 build WILL still wedge on an inject (the wedge has a
# second, XHB500-internal hold beneath wr_hold_r that v2 does not touch), and
# scoring v2 on that would reject a correct patch. If you want to WATCH the
# expected v2 wedge, run tidelink/imp/hw_gate/tl035_ab.sh or
# coverage/cov_errinject_sweep.py SEPARATELY — never fold it into this NO-HARM
# measurement.
#
# ONE RUN OF ONE ARM =
#   1. JTAG POR both dies                         (kpor on mapstone-dev)
#   2. select this arm's .bin, VERIFY md5, load PL (provenance is load-bearing)
#   3. AFI PS-master-port width fix               (MANDATORY after every PL load)
#   4. concurrent pair bring-up, ANCHOR GATE = off (link-up only; NOT re-rolled
#      on the anchor pair, because the anchor pair is the STRATIFIER we must be
#      able to SEE — see the plan §2)
#   5. status (expect fcsm=4 both)
#   6. latch the ANCHOR PAIR (per-die reanchored + sr_span_meas) via
#      anchor_pair_gate.py
#   7. DELIVERY TRUTH = LOCALMEM byte-exact verify: die_a writes N distinct
#      isolated words across the CAM'd peer aperture; die_b reads its OWN local
#      SRAM back (no link traversal on the read -> the verifier cannot wedge).
#      The Region F / OBS_AXI_NODES sampler is NOT trusted (plan §3); it is
#      logged once, INFORMATIONAL ONLY.
#
# OUTPUT: emits exactly ONE machine-readable line on stdout for the driver:
#   TL042_ARM_RESULT run=.. arm=.. linkup=.. anchor_a=.. anchor_b=.. \
#       span_a=.. span_b=.. delivery_ok=.. delivery_n=.. delivery_pass=.. \
#       bringup_tries=.. md5_a=.. md5_b=..
# and writes the same as key=value to $OUTDIR/result.kv plus a full 00_run.log.
#
# This script NEVER touches a lease and NEVER picks a bitstream for you: the
# per-arm .bin must already be staged on both boards as td/tl_arm_<ARM>.bin and
# its md5 passed in via MD5_A / MD5_B (see the driver + the checklist).
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
# =============================================================================
set -u

ARM="${1:?usage: tl042_v2_arm.sh <baseline|v2>}"
: "${KR260_PASSWORD:?KR260_PASSWORD not set}"
: "${MD5_A:?MD5_A (expected die_a md5 for arm $ARM) not set — build+stage the bin, then pin it}"
: "${MD5_B:?MD5_B (expected die_b md5 for arm $ARM) not set — build+stage the bin, then pin it}"

# --- repo root (this file lives at scripts/rig/) ----------------------------
ETH="${ETH:-$(cd "$(dirname "$0")/../.." && pwd)}"
RUN="$ETH/tidelink/pynq_host/scripts/kr260_eth_run.sh"
PAIRSH="$ETH/tidelink/pynq_host/scripts/kr260_eth_bringup_pair.sh"
GATE="$ETH/tidelink/pynq_host/scripts/anchor_pair_gate.py"
KB="$ETH/tidelink/imp/hw_gate/kb.sh"
for f in "$RUN" "$PAIRSH" "$GATE" "$KB"; do
  [ -r "$f" ] || { echo "MISSING dependency: $f" >&2; exit 2; }
done

# --- rig topology + knobs (all overridable) ---------------------------------
IP_A="${IP_A:-10.22.24.159}"           # die_a  (kr260-01, master/grandmaster)
IP_B="${IP_B:-10.22.24.153}"           # die_b  (kr260-02, slave)
KPOR_A="${KPOR_A:-kr260-01}"
KPOR_B="${KPOR_B:-kr260-02}"
KPOR_HOST="${KPOR_HOST:-mapstone-dev}" # where ~/bin/kpor lives
ARM_BIN="${ARM_BIN:-td/tl_arm_${ARM}.bin}"   # staged per-arm image on each board
SOAK_N="${SOAK_N:-16}"                 # delivery window (n=20 campaign used 16)
SOAK_BASE="${SOAK_BASE:-A5A50000}"
BRINGUP_TRIES="${BRINGUP_TRIES:-8}"    # LINK-UP retry budget (anchor NOT gated)
PAIR_TIMEOUT="${PAIR_TIMEOUT:-1200}"
# ssh-poll spacing. The plan (§3) warns ~25 back-to-back ssh sessions trip
# sshd's rate limiter and the resulting rc=2 is indistinguishable from a wedge.
# This NO-HARM arm issues only a handful of ssh sessions (POR/deploy/afi/bringup/
# status/write/verify) and does NOT run the 25-poll Region F liveness loop at
# all, but we still space the discrete sessions.
SSH_GAP="${SSH_GAP:-3}"

OUT="${OUTDIR:?OUTDIR not set (driver supplies scratchpad path)}"
mkdir -p "$OUT"
KV="$OUT/result.kv"; : > "$KV"
RUN_IDX="${RUN_IDX:-0}"

log(){ echo "[$(date -u +%H:%M:%S)] $*" | tee -a "$OUT/00_run.log"; }
kv(){ echo "$1=$2" >> "$KV"; }
alive(){ ping -c1 -W2 "$1" >/dev/null 2>&1 && echo UP || echo DOWN; }
gap(){ sleep "$SSH_GAP"; }

# ssh_wait — block until the board answers a REAL ssh command (not just ping).
# After a POR the net stack answers ICMP before sshd listens; a ping-only gate
# races the md5 step and returns empty output, which then reads as a bad image.
ssh_wait(){
  local ip="$1" tries="${2:-60}" i
  for i in $(seq 1 "$tries"); do
    if timeout 10 sshpass -p "$KR260_PASSWORD" ssh -o StrictHostKeyChecking=no \
         -o ConnectTimeout=5 "ubuntu@$ip" true >/dev/null 2>&1; then
      log "  ssh ready on $ip (after ${i} attempt(s))"; return 0
    fi
    sleep 5
  done
  log "  ssh NEVER became ready on $ip after $((tries*5))s"; return 1
}

# Defaults for the result line; overwritten as we learn each field.
LINKUP=0; ANCH_A='?'; ANCH_B='?'; SPAN_A='-'; SPAN_B='-'
DELIV_OK=0; DELIV_PASS='VOID'; TRIES='-'
kv arm "$ARM"; kv run "$RUN_IDX"

emit_and_exit(){
  # single machine-readable line the driver greps for; also stored in result.kv.
  local line
  line="TL042_ARM_RESULT run=$RUN_IDX arm=$ARM linkup=$LINKUP"
  line="$line anchor_a=$ANCH_A anchor_b=$ANCH_B span_a=$SPAN_A span_b=$SPAN_B"
  line="$line delivery_ok=$DELIV_OK delivery_n=$SOAK_N delivery_pass=$DELIV_PASS"
  line="$line bringup_tries=$TRIES md5_a=${GOT_A:--} md5_b=${GOT_B:--}"
  {
    echo "linkup=$LINKUP"; echo "anchor_a=$ANCH_A"; echo "anchor_b=$ANCH_B"
    echo "span_a=$SPAN_A"; echo "span_b=$SPAN_B"; echo "delivery_ok=$DELIV_OK"
    echo "delivery_n=$SOAK_N"; echo "delivery_pass=$DELIV_PASS"
    echo "bringup_tries=$TRIES"; echo "md5_a=${GOT_A:--}"; echo "md5_b=${GOT_B:--}"
  } >> "$KV"
  log "$line"
  echo "$line"
  exit "${1:-0}"
}

log "=== TL-042 v2 NO-HARM arm '$ARM' (run $RUN_IDX) — $(date -u +%FT%TZ) ==="

# --- 1. POR both dies -------------------------------------------------------
log "step 1: JTAG POR both dies ($KPOR_A / $KPOR_B via $KPOR_HOST)"
ssh -o BatchMode=yes "$KPOR_HOST" "~/bin/kpor $KPOR_A --wait" > "$OUT/01_por_a.log" 2>&1 &
pa=$!
ssh -o BatchMode=yes "$KPOR_HOST" "~/bin/kpor $KPOR_B --wait" > "$OUT/01_por_b.log" 2>&1 &
pb=$!
wait $pa; wait $pb
log "  ping: die_a=$(alive "$IP_A") die_b=$(alive "$IP_B")"
ssh_wait "$IP_A" || emit_and_exit 5
ssh_wait "$IP_B" || emit_and_exit 5

# --- 2. select this arm's image, VERIFY md5 (per-run pin), load PL ----------
# die_a and die_b run DIFFERENT images (normal vs -flip) so MD5_A != MD5_B; what
# must match is, per die, the staged arm .bin against the expected source md5.
# Pinning per run is deliberate (plan §1): it catches a board image silently
# swapped by a concurrent session between runs.
log "step 2: select $ARM_BIN, verify md5, fpgautil load"
GOT_A=$(KR260_PASSWORD="$KR260_PASSWORD" "$KB" "$IP_A" \
        "cp $ARM_BIN td/tidelink.bin && md5sum td/tidelink.bin" 2>/dev/null | awk '{print $1}' | tail -1)
gap
GOT_B=$(KR260_PASSWORD="$KR260_PASSWORD" "$KB" "$IP_B" \
        "cp $ARM_BIN td/tidelink.bin && md5sum td/tidelink.bin" 2>/dev/null | awk '{print $1}' | tail -1)
echo "die_a deployed=$GOT_A expected=$MD5_A" >> "$OUT/02_md5.log"
echo "die_b deployed=$GOT_B expected=$MD5_B" >> "$OUT/02_md5.log"
if [ "$GOT_A" != "$MD5_A" ] || [ "$GOT_B" != "$MD5_B" ]; then
  log "  MD5 MISMATCH (die_a got=$GOT_A want=$MD5_A | die_b got=$GOT_B want=$MD5_B) — ABORTING arm"
  emit_and_exit 4
fi
log "  md5 verified: die_a=$GOT_A die_b=$GOT_B"
gap
KR260_PASSWORD="$KR260_PASSWORD" "$KB" "$IP_A" "fpgautil -b td/tidelink.bin -f Full" > "$OUT/02_pl_a.log" 2>&1
gap
KR260_PASSWORD="$KR260_PASSWORD" "$KB" "$IP_B" "fpgautil -b td/tidelink.bin -f Full" > "$OUT/02_pl_b.log" 2>&1
grep -h "successfully" "$OUT"/02_pl_*.log | tee -a "$OUT/00_run.log" || true

# --- 3. AFI PS-master-port width fix (MANDATORY after a PL load) ------------
log "step 3: AFI PS-master-port width fix"
gap
KR260_PASSWORD="$KR260_PASSWORD" "$KB" "$IP_A" "env KR260_AFI_NO_CANARY=1 sh td/scripts/kr260_afi.sh fix" > "$OUT/03_afi_a.log" 2>&1
gap
KR260_PASSWORD="$KR260_PASSWORD" "$KB" "$IP_B" "env KR260_AFI_NO_CANARY=1 sh td/scripts/kr260_afi.sh fix" > "$OUT/03_afi_b.log" 2>&1
grep -h "^AFI:" "$OUT"/03_afi_*.log | tee -a "$OUT/00_run.log" || true

# --- 4. concurrent pair bring-up, ANCHOR GATE = off ------------------------
# mode=off: the pair orchestrator still requires LINK-UP (retries the lottery up
# to BRINGUP_TRIES), but does NOT re-roll on the anchor pair. We WANT to see the
# die_a=YES/die_b=NO pair when it occurs so we can report it separately, so we
# must NOT let the gate throw it away. The bring-up recipe (kr260_eth_bringup.py)
# already logs the full EPOCH_STATUS word incl. sr_span_meas, which is what the
# anchor latch below reads.
log "step 4: pair bring-up (ANCHOR_GATE_MODE=off, link-up budget=$BRINGUP_TRIES)"
DIE_A="ubuntu@$IP_A" DIE_B="ubuntu@$IP_B" KR260_PASSWORD="$KR260_PASSWORD" \
    MAX_TRIES="$BRINGUP_TRIES" ANCHOR_GATE_MODE=off \
    PAIR_LOG_DIR="$OUT" BU_LOG_A="$OUT/04_bringup_a.log" BU_LOG_B="$OUT/04_bringup_b.log" \
    timeout "$PAIR_TIMEOUT" bash "$PAIRSH" > "$OUT/04_pair.log" 2>&1
pair_rc=$?
TRIES=$(grep -aoE 'attempts_used=[0-9]+' "$OUT/04_pair.log" 2>/dev/null | tail -1 | cut -d= -f2)
[ -n "$TRIES" ] || TRIES='-'
grep -aE "ANCHOR_GATE_SUMMARY|PAIR (ACCEPTED|did NOT)" "$OUT/04_pair.log" | tail -3 | tee -a "$OUT/00_run.log" || true
log "  pair bring-up rc=$pair_rc tries=$TRIES"
if [ "$pair_rc" != 0 ]; then
  log "  LINK never came up within budget — this run is VOID for delivery (excluded)."
  LINKUP=0; DELIV_PASS='VOID'
  emit_and_exit 0
fi
LINKUP=1

# --- 5. status (expect fcsm=4 both) ----------------------------------------
log "step 5: status (expect fcsm=4 both)"
gap
KR260_PASSWORD="$KR260_PASSWORD" KR260_HOST="ubuntu@$IP_A" timeout 180 bash "$RUN" status > "$OUT/05_status_a.log" 2>&1
gap
KR260_PASSWORD="$KR260_PASSWORD" KR260_HOST="ubuntu@$IP_B" timeout 180 bash "$RUN" status > "$OUT/05_status_b.log" 2>&1
grep -h "calibration_done\|fcsm=" "$OUT"/05_status_*.log | tee -a "$OUT/00_run.log" || true

# --- 6. latch the ANCHOR PAIR (the stratifier) -----------------------------
# One source of truth for the pair predicate: anchor_pair_gate.py, mode=off (so
# it PARSES and PRINTS the pair without gating). We read its per-die lines:
#   die_a: linkup=YES reanchored=YES epoch=0x.. sr_span_meas=0
log "step 6: latch anchor pair (anchor_pair_gate.py --mode off)"
python3 "$GATE" --log-a "$OUT/04_bringup_a.log" --log-b "$OUT/04_bringup_b.log" \
    --mode off > "$OUT/06_anchor.log" 2>&1 || true
cat "$OUT/06_anchor.log" | tee -a "$OUT/00_run.log" || true
_pa=$(grep -aE '^\s*die_a:' "$OUT/06_anchor.log" | tail -1)
_pb=$(grep -aE '^\s*die_b:' "$OUT/06_anchor.log" | tail -1)
case "$_pa" in *reanchored=YES*) ANCH_A=YES ;; *reanchored=NO*) ANCH_A=NO ;; *) ANCH_A='?' ;; esac
case "$_pb" in *reanchored=YES*) ANCH_B=YES ;; *reanchored=NO*) ANCH_B=NO ;; *) ANCH_B='?' ;; esac
SPAN_A=$(echo "$_pa" | grep -aoE 'sr_span_meas=[0-9-]+' | tail -1 | cut -d= -f2); [ -n "$SPAN_A" ] || SPAN_A='-'
SPAN_B=$(echo "$_pb" | grep -aoE 'sr_span_meas=[0-9-]+' | tail -1 | cut -d= -f2); [ -n "$SPAN_B" ] || SPAN_B='-'
log "  ANCHOR PAIR = die_a:$ANCH_A / die_b:$ANCH_B   (span $SPAN_A/$SPAN_B)"
[ "$ANCH_A" = YES ] && [ "$ANCH_B" = NO ] && \
  log "  *** this is the die_a=YES/die_b=NO cell — expected 0/$SOAK_N; reported SEPARATELY ***"

# --- 7. DELIVERY TRUTH: LOCALMEM byte-exact verify -------------------------
# die_a writes N distinct isolated words to the CAM'd peer aperture (soak_write,
# refuses unless FCSM=4). die_b reads its OWN local shared_sram_0 back
# (soak_verify) — a LOCAL read, no link traversal, so the verifier cannot wedge.
# soak_verify exits 0 iff all N are byte-exact and prints "VERIFY n/N byte-exact".
# This is the ONLY delivery verdict we trust; Region F below is informational.
log "step 7: DELIVERY (LOCALMEM) — die_a soak_write $SOAK_N, die_b soak_verify $SOAK_N"
KR260_PASSWORD="$KR260_PASSWORD" KR260_HOST="ubuntu@$IP_A" \
    KR260_SOAK_N="$SOAK_N" KR260_SOAK_BASE="$SOAK_BASE" \
    timeout 300 bash "$RUN" soak_write > "$OUT/07_write_a.log" 2>&1
w_rc=$?
grep -h "WROTE\|ABORT\|link SWI_LANE" "$OUT/07_write_a.log" | tee -a "$OUT/00_run.log" || true
gap
KR260_PASSWORD="$KR260_PASSWORD" KR260_HOST="ubuntu@$IP_B" \
    KR260_SOAK_N="$SOAK_N" KR260_SOAK_BASE="$SOAK_BASE" \
    timeout 300 bash "$RUN" soak_verify > "$OUT/07_verify_b.log" 2>&1
v_rc=$?
vline=$(grep -aE 'VERIFY [0-9]+/[0-9]+ byte-exact' "$OUT/07_verify_b.log" | tail -1)
echo "  $vline" | tee -a "$OUT/00_run.log"
DELIV_OK=$(echo "$vline" | grep -aoE 'VERIFY [0-9]+/' | grep -aoE '[0-9]+' | head -1)
[ -n "$DELIV_OK" ] || DELIV_OK=0
if [ -z "$vline" ]; then
  # die_b's verify is a LOCAL read; if it produced nothing the board or ssh path
  # is broken (or the rate limiter tripped) — treat as VOID, not as 0/N.
  log "  die_b LOCALMEM verify produced NO readable line (w_rc=$w_rc v_rc=$v_rc) — VOID"
  DELIV_PASS='VOID'
elif [ "$DELIV_OK" = "$SOAK_N" ] && [ "$v_rc" = 0 ]; then
  DELIV_PASS=1
else
  DELIV_PASS=0
fi
log "  DELIVERY: $DELIV_OK/$SOAK_N byte-exact -> delivery_pass=$DELIV_PASS"

# --- 7b. Region F snapshot — INFORMATIONAL ONLY, NOT a verdict -------------
# The plan (§3) is explicit: OBS_AXI_NODES 0x21E0 was dead in all 20 overnight
# runs; NO "ALL CLEAN" (0xad800000) word means anything. Logged for the record,
# never parsed into delivery_pass.
gap
rfa=$(KR260_PASSWORD="$KR260_PASSWORD" "$KB" "$IP_A" \
      "python3 td/scripts/eth_tlapb_poke.py read 0x21E0" 2>/dev/null | tr -d '\r' | tail -1)
echo "  Region F(0x21E0) die_a=$rfa  [INFORMATIONAL — do NOT trust as delivery truth]" \
    | tee -a "$OUT/00_run.log" >> "$OUT/07b_regionf_info.log"

# --- 8. post-mortem reachability -------------------------------------------
log "step 8: post-mortem  die_a=$(alive "$IP_A") die_b=$(alive "$IP_B")"
emit_and_exit 0
