#!/bin/bash
# Logo merge for the rc2 VIA3.R.4 candidate.  MIRRORS eco-20260826-via3r4 and
# rc1-signoff-20260826 exactly: the sanctioned `make logo` target, whose
# defaults are LOGO_GDS=ASIC/logos/nanosoc_eth_Logo_APonly_fixed.gds,
# LOGO_AP_ONLY=1, LOGO_STRIP_JACK=0, LOGO_X=663.875, LOGO_Y=1000.0.
set -u
GI="${REPO_ROOT:?set REPO_ROOT}"/ASIC/genus-innovus
V="${RUN_DIR:?set RUN_DIR to the run directory}"
SIGN=$V/outputs/nanosoc_eth_chiplet_pads_rc4.gds
test -s "$SIGN" || { echo "FAIL: no signoff stream at $SIGN"; exit 1; }
cd "$GI" || exit 1
make logo \
    GDS="$SIGN" \
    OUT_DIR="$V/outputs" \
    LOGO_GDS_OUT="$V/outputs/nanosoc_eth_chiplet_pads_rc4_logo.gds" \
    < /dev/null
