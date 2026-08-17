#!/usr/bin/env bash
# =============================================================================
# run_tl042_v2_noharm.sh — the turnkey TL-042 v2 NO-HARM A/B campaign driver.
#
# Runs the two arms INTERLEAVED (baseline, v2, baseline, v2, ...), n>=6 per arm,
# NEVER blocked (v1's confound came from an n=1 baseline vs an n=2 fix run
# back-to-back). Each run is one full POR -> load -> AFI -> pair-bring-up ->
# LOCALMEM-delivery cycle handled by tl042_v2_arm.sh. At the end it stratifies
# the results ON THE ANCHOR PAIR and prints the NO-HARM verdict.
#
#   ACCEPTANCE (plan §0): v2 delivers byte-exact at the SAME rate as baseline on
#   ANCHOR-GOOD runs. A v2 build WILL still wedge on an inject — that is EXPECTED
#   and is NOT measured here (this harness injects nothing).
#
# WHAT THIS DRIVER DOES **NOT** DO (by design; see the checklist):
#   * It does NOT acquire/release the fpgahub lease. Hold the lease yourself
#     (lease show -> lease acquire as its OWN command -> release with the token)
#     per the checklist; this driver assumes you already own both boards.
#   * It does NOT BUILD the bitstreams. You must build BOTH images (baseline =
#     pristine submodule HEAD; v2 = HEAD + tl042_v2_proposed.patch), stage each
#     board's image as td/tl_arm_{baseline,v2}.bin, and pin the four md5s below.
#   * It does NOT edit kr260_eth_bringup.py. The EPOCH_STATUS span instrument is
#     a checklist step (and appears already landed — verify at rig-time).
#
# USAGE
#   # 1) fill in the four md5s (build+stage first), then:
#   KR260_PASSWORD=... \
#   MD5_BASELINE_A=<hex> MD5_BASELINE_B=<hex> MD5_V2_A=<hex> MD5_V2_B=<hex> \
#       bash scripts/rig/run_tl042_v2_noharm.sh [N_PER_ARM]
#
#   # dry-run: print the interleave plan + config, touch NOTHING:
#   DRY_RUN=1 ... bash scripts/rig/run_tl042_v2_noharm.sh
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
# =============================================================================
set -u

ETH="${ETH:-$(cd "$(dirname "$0")/../.." && pwd)}"
ARMSH="$(cd "$(dirname "$0")" && pwd)/tl042_v2_arm.sh"
REPORT="$(cd "$(dirname "$0")" && pwd)/tl042_v2_report.py"
[ -x "$ARMSH" ] || { echo "MISSING/!x: $ARMSH" >&2; exit 2; }

N_PER_ARM="${1:-${N_PER_ARM:-6}}"      # plan: n>=6 per arm minimum
if [ "$N_PER_ARM" -lt 6 ]; then
  echo "REFUSING n=$N_PER_ARM: the ~15% baseline failure mode cannot be separated" >&2
  echo "  from a real regression below n=6/arm (plan §1). Override only knowingly." >&2
  [ "${FORCE_SMALL_N:-0}" = 1 ] || exit 2
fi

# --- the four md5 pins — TODO: fill after building+staging both bitstreams ---
# die_a runs the normal image, die_b runs the -flip image, so A != B per arm.
# Left UNSET on purpose: the run must ABORT rather than flash an unattributable
# image (the rig has been found running an unlabelled ILA build before).
MD5_BASELINE_A="${MD5_BASELINE_A:-}"   # <baseline, die_a normal>
MD5_BASELINE_B="${MD5_BASELINE_B:-}"   # <baseline, die_b -flip>
MD5_V2_A="${MD5_V2_A:-}"               # <v2 (patched), die_a normal>
MD5_V2_B="${MD5_V2_B:-}"               # <v2 (patched), die_b -flip>

: "${KR260_PASSWORD:?KR260_PASSWORD not set}"
missing=""
for v in MD5_BASELINE_A MD5_BASELINE_B MD5_V2_A MD5_V2_B; do
  [ -n "${!v}" ] || missing="$missing $v"
done
if [ -n "$missing" ]; then
  echo "ABORT: md5 pin(s) not set:$missing" >&2
  echo "  Build BOTH bitstreams, stage them as td/tl_arm_{baseline,v2}.bin on each" >&2
  echo "  board, compute md5sum, and export the four MD5_* vars (see the checklist)." >&2
  exit 2
fi

STAMP="$(date -u +%Y%m%dT%H%M%SZ)"
OUTROOT="${OUTROOT:-${SCRATCH:-/tmp}/tl042_v2_noharm_$STAMP}"
mkdir -p "$OUTROOT"
RUNS_TSV="$OUTROOT/RUNS.tsv"
DRIVER_LOG="$OUTROOT/driver.log"
printf 'run\tarm\tlinkup\tanchor_a\tanchor_b\tspan_a\tspan_b\tdelivery_ok\tdelivery_n\tdelivery_pass\tbringup_tries\tmd5_a\tmd5_b\n' > "$RUNS_TSV"

RUN_GAP="${RUN_GAP:-20}"               # seconds between runs (thermal/rig settle)
SOAK_N="${SOAK_N:-16}"

dlog(){ echo "[$(date -u +%FT%TZ)] $*" | tee -a "$DRIVER_LOG"; }

# Build the INTERLEAVED arm sequence: baseline, v2, baseline, v2, ...
SEQ=()
for i in $(seq 1 "$N_PER_ARM"); do SEQ+=("baseline" "v2"); done
TOTAL=${#SEQ[@]}

dlog "=== TL-042 v2 NO-HARM CAMPAIGN — $STAMP ==="
dlog "  interleave: baseline,v2 x $N_PER_ARM  (total $TOTAL runs)"
dlog "  delivery window N=$SOAK_N  soak_base=${SOAK_BASE:-A5A50000}"
dlog "  md5 baseline a/b = $MD5_BASELINE_A / $MD5_BASELINE_B"
dlog "  md5 v2       a/b = $MD5_V2_A / $MD5_V2_B"
dlog "  out: $OUTROOT"

if [ "${DRY_RUN:-0}" = 1 ]; then
  dlog "DRY_RUN=1 — plan only, nothing touched. Sequence:"
  n=0; for arm in "${SEQ[@]}"; do n=$((n+1)); printf '   run %02d  arm=%s\n' "$n" "$arm"; done
  exit 0
fi

pin_for(){ # echo "MD5_A MD5_B" for an arm
  case "$1" in
    baseline) echo "$MD5_BASELINE_A $MD5_BASELINE_B" ;;
    v2)       echo "$MD5_V2_A $MD5_V2_B" ;;
  esac
}

idx=0
for arm in "${SEQ[@]}"; do
  idx=$((idx+1))
  tag=$(printf 'run_%02d_%s' "$idx" "$arm")
  read -r m_a m_b < <(pin_for "$arm")
  dlog "run $idx/$TOTAL arm=$arm START"
  line=$(RUN_IDX="$idx" OUTDIR="$OUTROOT/$tag" \
         MD5_A="$m_a" MD5_B="$m_b" \
         SOAK_N="$SOAK_N" ${SOAK_BASE:+SOAK_BASE="$SOAK_BASE"} \
         KR260_PASSWORD="$KR260_PASSWORD" ETH="$ETH" \
         bash "$ARMSH" "$arm" 2>>"$DRIVER_LOG" | tee -a "$DRIVER_LOG" \
         | grep -aE '^TL042_ARM_RESULT ' | tail -1)
  if [ -z "$line" ]; then
    dlog "run $idx arm=$arm produced NO result line — recording as void row"
    printf '%d\t%s\t0\t?\t?\t-\t-\t0\t%s\tVOID\t-\t-\t-\n' "$idx" "$arm" "$SOAK_N" >> "$RUNS_TSV"
  else
    # turn "k=v k=v ..." into a TSV row in fixed column order.
    python3 - "$line" "$idx" "$arm" "$SOAK_N" >> "$RUNS_TSV" <<'PY'
import sys
line, idx, arm, soakn = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4]
kv = dict(t.split("=", 1) for t in line.split() if "=" in t)
cols = ["run","arm","linkup","anchor_a","anchor_b","span_a","span_b",
        "delivery_ok","delivery_n","delivery_pass","bringup_tries","md5_a","md5_b"]
kv.setdefault("run", idx); kv.setdefault("arm", arm); kv.setdefault("delivery_n", soakn)
print("\t".join(str(kv.get(c, "-")) for c in cols))
PY
  fi
  dlog "run $idx arm=$arm END -> $(tail -1 "$RUNS_TSV")"
  [ "$idx" -lt "$TOTAL" ] && sleep "$RUN_GAP"
done

dlog "=== CAMPAIGN END — $TOTAL runs. RUNS.tsv: $RUNS_TSV ==="
echo
echo "================= STRATIFIED RESULTS (anchor pair) ================="
if [ -r "$REPORT" ]; then
  python3 "$REPORT" "$RUNS_TSV" | tee "$OUTROOT/REPORT.txt"
else
  echo "(report tool $REPORT not found — RUNS.tsv is at $RUNS_TSV)"
fi
echo
echo "RUNS.tsv : $RUNS_TSV"
echo "per-run logs + result.kv under: $OUTROOT/run_*"
