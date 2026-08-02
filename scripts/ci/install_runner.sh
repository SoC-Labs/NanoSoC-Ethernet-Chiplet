#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# install_runner.sh — register + start the self-hosted GitHub Actions runner
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Sets up the runner .github/workflows/nightly.yml targets, on srv03335.
#
# WHY srv03335 and not srv04936:
#   - /tsmc65pdk is not mounted on srv04936, and that tree holds the Calibre DRC
#     ruledeck AND the GDS-out layer map the flow hardcodes.
#   - dam1n19 is not in group `tsmc65` on srv04936, so the fallback PDK copy
#     under /home/dwn1c21 is unreadable there too.
#   - srv03335 has 16 cores / 251 GB against srv04936's 8 / 62, and the flow
#     asks for `-local_cpu 8` / `-turbo 8`.
#   Moving CI to srv04936 needs BOTH an /tsmc65pdk mount and tsmc65pdkgrp
#   membership on that host. Until then this is the only host that works.
#
# Run this ON srv03335, as dam1n19:
#
#   REG_TOKEN=<token> bash scripts/ci/install_runner.sh
#
# Get REG_TOKEN from:
#   https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/settings/actions/runners/new
# (needs repo admin; the token is single-use and expires in one hour)
#-----------------------------------------------------------------------------
set -euo pipefail

REPO_URL="https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet"
RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner-nanosoc-eth}"
RUNNER_VERSION="${RUNNER_VERSION:-2.321.0}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname -s)-nanosoc-eth}"
# `soclabs-eda` is what nightly.yml keys on — it means "EDA tools + /research
# + a TSMC65 PDK". Do not put it on a host that lacks any of the three.
RUNNER_LABELS="${RUNNER_LABELS:-soclabs-eda}"

if [ -z "${REG_TOKEN:-}" ]; then
    echo "FAIL: set REG_TOKEN. Get one (single-use, 1h TTL) from:" >&2
    echo "  $REPO_URL/settings/actions/runners/new" >&2
    exit 1
fi

# The runner is only useful on a host that can actually run the gates. Check
# now, loudly, rather than discovering it in a red workflow run at 02:00.
echo "== preflight =="
rc=0
for t in vcs xrun verilator python3 make git; do
    if command -v "$t" >/dev/null 2>&1; then
        printf 'OK:      %-10s %s\n' "$t" "$(command -v "$t")"
    else
        printf 'MISSING: %s\n' "$t"; rc=1
    fi
done
for d in /research/AAA/ip_library /research/precompiled_mems/TSMC65; do
    if [ -r "$d" ]; then echo "OK:      $d"; else echo "MISSING: $d"; rc=1; fi
done
# Not fatal — the nightly gates don't need the PDK, only the ASIC flow does.
[ -r /tsmc65pdk/65 ] \
    && echo "OK:      /tsmc65pdk/65 (ASIC flow can run here too)" \
    || echo "WARN:    /tsmc65pdk/65 unreadable — nightly gates fine, ASIC flow is not"
[ "$rc" = 0 ] || { echo "== preflight FAILED — do not register a runner here =="; exit 1; }

echo
echo "== installing runner $RUNNER_VERSION into $RUNNER_DIR =="
mkdir -p "$RUNNER_DIR"
cd "$RUNNER_DIR"

if [ ! -x ./config.sh ]; then
    tarball="actions-runner-linux-x64-${RUNNER_VERSION}.tar.gz"
    curl -fsSL -o "$tarball" \
        "https://github.com/actions/runner/releases/download/v${RUNNER_VERSION}/${tarball}"
    tar xzf "$tarball"
    rm -f "$tarball"
fi

./config.sh --unattended --replace \
    --url "$REPO_URL" \
    --token "$REG_TOKEN" \
    --name "$RUNNER_NAME" \
    --labels "$RUNNER_LABELS" \
    --work _work

# No `svc.sh install`: that needs root, and dam1n19 has no passwordless sudo on
# srv03335. There is no systemd --user session either (no lingering), so a user
# unit is out. nohup + an @reboot crontab line is what survives here.
echo
echo "== starting runner =="
pkill -f "$RUNNER_DIR/run.sh" 2>/dev/null || true
nohup ./run.sh > "$RUNNER_DIR/runner.log" 2>&1 &
sleep 5

if pgrep -f "$RUNNER_DIR/run.sh" >/dev/null; then
    echo "OK: runner up (pid $(pgrep -f "$RUNNER_DIR/run.sh" | head -1))"
else
    echo "FAIL: runner did not stay up — see $RUNNER_DIR/runner.log" >&2
    tail -20 "$RUNNER_DIR/runner.log" >&2 || true
    exit 1
fi

cron_line="@reboot cd $RUNNER_DIR && nohup ./run.sh > $RUNNER_DIR/runner.log 2>&1 &"
if crontab -l 2>/dev/null | grep -Fq "$RUNNER_DIR/run.sh"; then
    echo "OK: @reboot crontab entry already present"
else
    ( crontab -l 2>/dev/null; echo "$cron_line" ) | crontab -
    echo "OK: added @reboot crontab entry"
fi

cat <<EOF

== done ==
Runner   : $RUNNER_NAME
Labels   : self-hosted, linux, X64, $RUNNER_LABELS
Log      : $RUNNER_DIR/runner.log
Verify   : $REPO_URL/settings/actions/runners
Trigger  : $REPO_URL/actions/workflows/nightly.yml  -> "Run workflow"

The nightly schedule (02:00 UTC) only starts firing once nightly.yml is on the
DEFAULT branch — GitHub ignores \`schedule:\` triggers on any other branch.
EOF
