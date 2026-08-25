#!/usr/bin/env python3
"""hostio_fw -- the firmware/host ABI, READ OUT OF fw_abi.h.

There is exactly one copy of these numbers in this directory and it is the C
header.  This module PARSES it; it does not restate it.  That is deliberate:
a second hand-maintained copy of an address map is the standard way an ABI
starts lying, and this tree has been bitten by duplicated sources before.

    >>> from fw_abi import ABI
    >>> hex(ABI["FW_SENTINEL_ADDR"])
    '0x2d000004'

Missing keys are a hard error at import, not a KeyError three layers down.

Copyright 2026, SoC Labs (www.soclabs.org)
"""

import os
import re

HERE = os.path.dirname(os.path.abspath(__file__))
ABI_HEADER = os.path.join(HERE, "fw_abi.h")

# `#define FW_NAME 0x1234` / `#define FW_NAME 42`.  Anything whose value is not
# a plain integer literal (an expression, a string, a macro reference) is
# ignored rather than half-parsed.
_DEFINE = re.compile(
    r"^\s*#\s*define\s+(FW_[A-Z0-9_]+)\s+(0[xX][0-9a-fA-F]+|\d+)\s*(?:/\*|//|$)")

# Every name the loader, the printed env block or the README promises.  If the
# header stops defining one of these, this module refuses to import rather than
# letting a caller quietly get a default.
REQUIRED = (
    "FW_SHARED_SRAM_BASE", "FW_SHARED_SRAM_SIZE",
    "FW_HEARTBEAT_ADDR", "FW_SENTINEL_ADDR", "FW_SENTINEL_VALUE",
    "FW_IMAGE_ID_ADDR", "FW_IMAGE_ID_MAGIC",
    "FW_IMAGE_ID_PARK", "FW_IMAGE_ID_HEARTBEAT", "FW_IMAGE_ID_MDIO",
    "FW_CORE_HZ_ADDR",
    "FW_MDIO_RESULT_ADDR", "FW_MDIO_PHYID1_ADDR", "FW_MDIO_PHYID2_ADDR",
    "FW_MDIO_MIIMODER_ADDR", "FW_MDIO_STATUS_ADDR", "FW_MDIO_STATUS_MAGIC",
    "FW_MDIO_MASK_FLOAT_ADDR", "FW_MDIO_MASK_ZERO_ADDR",
    "FW_MDIO_MASK_UNSTABLE_ADDR", "FW_MDIO_MASK_OTHER_ADDR",
    "FW_MDIO_MASK_CAND_ADDR", "FW_MDIO_MASK_TIMEOUT_ADDR",
    "FW_MDIO_TIMEOUTS_ADDR", "FW_MAC_MODER_ADDR", "FW_MAC_PACKETLEN_ADDR",
    "FW_MDIO_SCANS_ADDR", "FW_MDIO_INVALID_FLAG",
    "FW_FAULT_ADDR", "FW_FAULT_INFO_ADDR", "FW_FAULT_PC_ADDR",
    "FW_BOOT_TOKEN_ADDR", "FW_BOOT_TOKEN_VALUE",
    "FW_ETHMAC_BASE", "FW_ETH_MIIMODER_RESET", "FW_ETH_MODER_RESET",
    "FW_ETH_PACKETLEN_RESET", "FW_PHY_ID1_EXPECT", "FW_PHY_ID2_EXPECT",
    "FW_ETH_IMEM_BASE", "FW_ETH_IMEM_SIZE",
    "FW_CPU1_IMEM_BASE", "FW_CPU1_IMEM_SIZE", "FW_CPU1_IMEM_DEBUG_ALIAS",
)


def parse(path=ABI_HEADER):
    out = {}
    with open(path) as fh:
        for line in fh:
            m = _DEFINE.match(line)
            if m:
                out[m.group(1)] = int(m.group(2), 0)
    missing = [k for k in REQUIRED if k not in out]
    if missing:
        raise RuntimeError(
            "%s does not define %s. This module is a PARSER of that header, not "
            "a second copy of it -- add the #define there rather than a default "
            "here." % (path, ", ".join(missing)))
    return out


ABI = parse()

# Result codes, keyed by value, for printing.  Parsed the same way.
RESULT_CODES = dict(
    (v, k[len("FW_MDIO_RC_"):])
    for k, v in ABI.items() if k.startswith("FW_MDIO_RC_"))

IMAGE_IDS = {
    ABI["FW_IMAGE_ID_PARK"]: "cpu1_park",
    ABI["FW_IMAGE_ID_HEARTBEAT"]: "heartbeat",
    ABI["FW_IMAGE_ID_MDIO"]: "mdio_probe",
}

# The two load geometries.  base is the address the image is LINKED for; the
# CPU1 entry also carries the debug port's alias for the same RAM, which is a
# different address and is NOT what the image is linked for.
GEOMETRY = {
    "cpu0": {"base": ABI["FW_ETH_IMEM_BASE"], "size": ABI["FW_ETH_IMEM_SIZE"],
             "alias": ABI["FW_ETH_IMEM_BASE"],
             "what": "eth CPU0 IMEM, 32 KB, remap-independent alias"},
    "cpu1": {"base": ABI["FW_CPU1_IMEM_BASE"], "size": ABI["FW_CPU1_IMEM_SIZE"],
             "alias": ABI["FW_CPU1_IMEM_DEBUG_ALIAS"],
             "what": "CPU1 IMEM, 16 KB (debug-port alias 0x%08X)"
                     % ABI["FW_CPU1_IMEM_DEBUG_ALIAS"]},
}


def geometry_for(path):
    """Which memory an image is linked for, from its file name."""
    name = os.path.basename(path).lower()
    return "cpu1" if "cpu1" in name else "cpu0"


def env_exports(image="heartbeat"):
    """The hostio_suite environment block for a loaded image, as (name, value).

    These are the variables tier4_5.py reads.  HOSTIO_CPU0_IMAGE is left to the
    caller: only the operator knows which file was actually loaded.
    """
    ev = [
        ("HOSTIO_FW_HEARTBEAT_ADDR", "0x%08X" % ABI["FW_HEARTBEAT_ADDR"]),
        ("HOSTIO_FW_SENTINEL_ADDR", "0x%08X" % ABI["FW_SENTINEL_ADDR"]),
        ("HOSTIO_FW_SENTINEL", "0x%08X" % ABI["FW_SENTINEL_VALUE"]),
    ]
    if image == "mdio_probe":
        ev.append(("HOSTIO_FW_MDIO_RESULT_ADDR",
                   "0x%08X" % ABI["FW_MDIO_RESULT_ADDR"]))
    return ev


if __name__ == "__main__":
    for k in sorted(ABI):
        print("%-28s 0x%08X" % (k, ABI[k]))
