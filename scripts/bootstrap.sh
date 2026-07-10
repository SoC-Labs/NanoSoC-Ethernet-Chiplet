#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# bootstrap.sh — fetch every submodule, all 42 of them, 8 levels deep.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Why this exists rather than a plain `git submodule update --init --recursive`:
#
# This repo's own three submodules are HTTPS. But one submodule *inside TideLink*
# — `deps/tidelink-phy`, at the commit we pin — is still declared over SSH
# (`git@git.soton.ac.uk:...`). Fixing that means a new TideLink commit, and this
# repo's TideLink pointer is deliberately frozen. So instead we rewrite the SSH
# prefix to HTTPS for the duration of the fetch.
#
# `git -c` exports its settings through GIT_CONFIG_PARAMETERS, and submodule
# recursion runs child `git` processes — so the rewrite reaches the nested clone.
# Verified by running this with SSH disabled outright (GIT_SSH_COMMAND=/bin/false).
#
# The rewrite is scoped to this invocation. It writes nothing to your git config.
# If you already have SoTON SSH keys the rewrite is a harmless no-op: HTTPS and
# SSH reach the same GitLab.
#-----------------------------------------------------------------------------
set -euo pipefail

cd "$(dirname "$(readlink -f "$0")")/.."

echo "== fetching submodules (SSH URLs rewritten to HTTPS) =="
git -c url."https://git.soton.ac.uk/".insteadOf="git@git.soton.ac.uk:" \
    submodule update --init --recursive

# A failed submodule clone leaves an empty directory behind, and `submodule
# update` can exit 0 having skipped one. Check rather than assume.
#
# NOT `submodule foreach`: it only descends into submodules that already have a
# .git, so it steps straight over the empty directory we are hunting for. It
# reports a broken tree as clean. `submodule status --recursive` prefixes '-' to
# every submodule that was never populated, which is exactly the signal.
missing=$(git submodule status --recursive | sed -n 's/^-[0-9a-f]* //p')

if [ -n "$missing" ]; then
    echo "== INCOMPLETE: these submodules were never populated ==" >&2
    echo "$missing" | sed 's/^/  /' >&2
    exit 1
fi

n=$(git submodule status --recursive | wc -l)
echo "== OK: $n submodules populated =="
echo
echo "Next:"
echo "  source set_env.sh && make elab      # structural elaboration (needs VCS)"
echo "  make chip-boundary                  # boundary coverage check (python only)"
