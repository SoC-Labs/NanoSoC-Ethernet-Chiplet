#!/usr/bin/env bash
# scripts/lint.sh — entry point for the structural lint pass.
# The machinery lives in verif/lint/; this is a stable, discoverable forwarder
# (mirrors scripts/check_chip_boundary.py). See docs/LINT_FINDINGS.md.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
set -eu
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec "${HERE}/../verif/lint/run.sh" "$@"
