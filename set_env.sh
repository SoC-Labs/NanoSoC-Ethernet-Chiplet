#-----------------------------------------------------------------------------
# set_env.sh — environment for the nanoSoC ethernet chiplet integration
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Source this, do not execute it:   source set_env.sh
#
# Exports the roots the flists and sys_desc lib-dirs resolve against. Every path
# below is a ${VAR} in the flists so VCS / Xcelium / Vivado expand them directly
# (the same convention the SoC and tidelink use).
#
# This wrapper does NOT re-source its submodules' set_env.sh scripts. Each of
# them mutates PATH and points vendor-IP vars at the shared lab tree, and
# sourcing three of them in sequence produces an environment nobody can reason
# about. Instead we export only the roots, and delegate to the submodule's own
# Makefile when a submodule flow needs its own environment.
#-----------------------------------------------------------------------------

# Resolve this file's directory whether sourced from bash or zsh.
if [ -n "$BASH_SOURCE" ]; then
    _SETENV_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
    _SETENV_DIR="$(cd "$(dirname "$0")" && pwd)"
fi

export NANOSOC_ETH_CHIPLET_HOME="${_SETENV_DIR}"

# --- Component roots ---------------------------------------------------------
export NANOSOC_MULTICORE_HOME="${NANOSOC_ETH_CHIPLET_HOME}/nanosoc-multicore-system"
export TIDELINK_HOME="${NANOSOC_ETH_CHIPLET_HOME}/tidelink"
export TIDECHART_HOME="${NANOSOC_ETH_CHIPLET_HOME}/tidechart"

# The code generator lives two levels down inside the SoC.
export SOCLABS_NANOSOC_ARCH_TECH_DIR="${NANOSOC_MULTICORE_HOME}/nanosoc_arch_tech"
export SOCLABS_NANOSOC_GEN_DIR="${SOCLABS_NANOSOC_ARCH_TECH_DIR}/nanosoc_gen"
export SOCLABS_NANOSOC_SOC_DIR="${NANOSOC_MULTICORE_HOME}"

# --- sys_desc library search path -------------------------------------------
# `soc_model` resolves module references BY NAME across these directories.
# Order matters only for shadowing; there is none today.
export CHIPLET_SYS_DESC_LIB_DIRS="\
${NANOSOC_ETH_CHIPLET_HOME}/sys_desc \
${NANOSOC_MULTICORE_HOME}/sys_desc \
${NANOSOC_MULTICORE_HOME}/ethernet-subsystem-ahb/sys_desc \
${NANOSOC_MULTICORE_HOME}/ethernet-subsystem-ahb/ethernet-mac-ahb/sys_desc \
${NANOSOC_MULTICORE_HOME}/ahb_qspi/sys_desc \
${TIDELINK_HOME}/sys_desc"

# --- Vendor IP (READ-ONLY shared lab trees; never write here) ----------------
# Left to the submodules' own scripts to define if unset, so a wrong value here
# cannot silently override a correct one there.
: "${ARM_IP_LIBRARY_PATH:=/research/AAA/ip_library}"
export ARM_IP_LIBRARY_PATH

# --- Sanity ------------------------------------------------------------------
_missing=0
for _d in "${NANOSOC_MULTICORE_HOME}" "${TIDELINK_HOME}" "${TIDECHART_HOME}"; do
    if [ ! -d "${_d}" ]; then
        echo "set_env.sh: MISSING ${_d}" >&2
        _missing=1
    fi
done
if [ "${_missing}" = "1" ]; then
    echo "set_env.sh: run 'git submodule update --init --recursive' first" >&2
fi
unset _d _missing _SETENV_DIR

echo "nanosoc-ethernet-chiplet: NANOSOC_ETH_CHIPLET_HOME=${NANOSOC_ETH_CHIPLET_HOME}"
