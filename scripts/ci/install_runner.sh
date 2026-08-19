#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# install_runner.sh — register + start the self-hosted GitHub Actions runner
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Sets up the runners .github/workflows/nightly.yml targets.
#
# TWO HOSTS, SPLIT BY CAPABILITY — NOT by preference:
#   srv03335  soclabs-sim + soclabs-pdk   16 cores / 251 GB, /tsmc65pdk mounted
#   srv04936  soclabs-sim                  8 cores /  62 GB, /tsmc65pdk is an
#                                         EMPTY MOUNTPOINT — the autofs/NFS map
#                                         entry (auto.direct.puppet ->
#                                         fsresearch:/ifs/research/FPSE/
#                                         FPSEallocated/tsmc65pdk) exists only on
#                                         srv03335. Adding it is a Puppet change.
#
#   GROUP MEMBERSHIP IS NOT THE DIFFERENCE. Both hosts are in `tsmc65pdkgrp`,
#   which is what guards /tsmc65pdk/65 (mode 2770); `tsmc65` guards an older
#   tree ASIC/common.mk moved off. The difference is purely the mount. Inside
#   the CI sandbox's user namespace a group cannot be resolved to its NAME at
#   all (SSSD is unreachable) while access still works, so preflight treats PDK
#   READABILITY — not group name — as authoritative.
#
#   The ASIC flow (syn -> pnr -> DRC) hardcodes the Calibre ruledeck and GDS-out
#   layer map under /tsmc65pdk, so it can ONLY run on srv03335 — hence a separate
#   `soclabs-pdk` label rather than one blanket `soclabs-eda`. Splitting this way
#   also parks the nightly sim gates on srv04936 and leaves the 16-core box free.
#
#   Note GitHub Actions has NO runner priority: if two idle runners carry the
#   label a job asks for, the pick is arbitrary, and an offline preferred runner
#   makes the job QUEUE rather than fail over. So preference has to be expressed
#   as capability, which is what the labels above do.
#
# Run this ON the host being registered, as dam1n19:
#
#   REG_TOKEN=<token> bash scripts/ci/install_runner.sh
#
# Get REG_TOKEN from:
#   https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet/settings/actions/runners/new
# (needs repo admin; the token is single-use and expires in one hour)
#-----------------------------------------------------------------------------
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_URL="https://github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet"
# Hostname in the dir: the two runner hosts have SEPARATE homes today, but a
# shared /home would silently make two runners fight over one work tree.
RUNNER_DIR="${RUNNER_DIR:-$HOME/actions-runner-nanosoc-eth-$(hostname -s)}"
RUNNER_VERSION="${RUNNER_VERSION:-2.336.0}"
RUNNER_NAME="${RUNNER_NAME:-$(hostname -s)-nanosoc-eth}"

if [ -z "${REG_TOKEN:-}" ]; then
    echo "FAIL: set REG_TOKEN. Get one (single-use, 1h TTL) from:" >&2
    echo "  $REPO_URL/settings/actions/runners/new" >&2
    exit 1
fi

# The runner is only useful on a host that can actually run the gates. Check
# now, loudly, rather than discovering it in a red workflow run at 02:00.
#
# Labels are DERIVED, not asserted: preflight.sh probes the host and reports
# which capabilities it has actually earned. Hosts differ (srv04936 has no PDK
# and cannot run the ASIC flow), and a hand-typed label that outlives the
# capability it claims is how a pool starts returning different answers for the
# same commit. Override RUNNER_LABELS only if you know better than the probe.
echo "== preflight =="
"$HERE/preflight.sh" || {
    echo "== preflight FAILED — do not register a runner here ==" >&2
    exit 1
}
RUNNER_LABELS="${RUNNER_LABELS:-$("$HERE/preflight.sh" --labels)}"
echo
echo "== labels: $RUNNER_LABELS =="

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
