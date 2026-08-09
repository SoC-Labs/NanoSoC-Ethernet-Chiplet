"""Ownership zoning for the full-chiplet lint.

Three tiers, because "who can fix this?" is the only question that decides
whether a lint finding is actionable:

  ARM_IP       Arm-licensed IP. Read-only lab tree or vendor-generated copies
               inside the submodules. Black-boxed: we neither may nor should
               edit it, and its findings are not evidence about this design.
  THIRD_PARTY  OpenCores / Wlink / vendor-generated RTL that IS compiled into
               the chip but is not authored here. Analysed and reported, never
               gated -- a finding is an upstream escalation, not a build break.
  AUTHORED     SoC Labs RTL. The gate applies here.
"""

import os

# verif/lint/full/zones.py -> the repo root, four levels up.
REPO = os.environ.get(
    "NANOSOC_ETH_CHIPLET_HOME",
    os.path.dirname(os.path.dirname(os.path.dirname(
        os.path.dirname(os.path.abspath(__file__))))))

ARM_IP = [
    # Read-only shared lab tree
    "/research/AAA/ip_library/BP210/",
    "/research/AAA/ip_library/Corstone-101/",
    "/research/AAA/ip_library/CG092/",              # flash cache
    "/research/AAA/ip_library/Cortex-M0-plus/",
    "/research/AAA/ip_library/PL022/",              # SSP
    "/research/AAA/ip_library/SoC-400/",            # CoreSight DAP
    # Arm IP that lives INSIDE the submodules, vendor-generated
    f"{REPO}/tidelink/deps/xhb500/",                       # XHB500 AHB bridge
    f"{REPO}/nanosoc-multicore-system/build_soc/rtl/dma250/rendered_CFG_MIN/",
]

THIRD_PARTY = [
    "/research/AAA/ip_library/OpenCores-EthMAC/",
    "/research/AAA/ip_library/OpenCores-HA1588/",
    f"{REPO}/nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb/src/rtl/ethmac_patches/",
    f"{REPO}/nanosoc-multicore-system/ethernet-subsystem-ahb/ethernet-mac-ahb/src/rtl/ha1588_patches/",
    f"{REPO}/tidelink/deps/axi-chiplet-controller/",       # Wlink, Bluespec-generated
    f"{REPO}/tidelink/deps/tidelink-phy/",
    f"{REPO}/tidelink/src/rtl/local_overrides/",           # vendor copies + local fixes
]

# Finer labels inside AUTHORED, for a report that says WHERE, not just "ours".
AUTHORED_ZONES = [
    ("integration",  f"{REPO}/src/rtl/"),
    ("chip-wrapper", f"{REPO}/build/chip/rtl/"),
    ("tidechart",    f"{REPO}/tidechart/"),
    ("tidelink",     f"{REPO}/tidelink/"),
    ("soc-generated", f"{REPO}/nanosoc-multicore-system/build_soc/"),
    ("soc",          f"{REPO}/nanosoc-multicore-system/"),
]


def tier(path):
    # Generated black boxes (build/lint/full/**/armbb|bbox) stand in for the IP
    # they replace, so a finding against one is a finding against that IP.
    if "/armbb/" in path or "/bbox/" in path:
        return "arm-ip"
    if any(p in path for p in ARM_IP):
        return "arm-ip"
    if any(p in path for p in THIRD_PARTY):
        return "third-party"
    return "authored"


def zone(path):
    t = tier(path)
    if t != "authored":
        return t
    for label, pref in AUTHORED_ZONES:
        if pref in path:
            return label
    return "other"
