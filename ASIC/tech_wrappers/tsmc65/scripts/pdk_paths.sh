#!/usr/bin/env bash
#-----------------------------------------------------------------------------
# pdk_paths.sh — resolve foundry collateral paths WITHOUT spelling release codes
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHY THIS EXISTS
#
# github.com/SoC-Labs/NanoSoC-Ethernet-Chiplet is PUBLIC. A path like
#
#     $TSMC_65_HOME/CMOS/util/MAIN_DRC_TopMu/<deck>_<stack>.<rev>
#
# discloses, in its last component, WHICH DECK REVISION and WHICH IP RELEASE
# this site holds. That is purchase information: the family spelling is public
# (it is in TSMC's own public collateral list), the revision suffix is not.
# Before this script those suffixes appeared ~65 times across ~30 files.
#
# THE RULE THIS SCRIPT IMPLEMENTS: REDACT THE SPELLING, NEVER CHANGE THE
# SELECTION. Every path below resolves, on this host, byte-identically to the
# literal it replaced. Selecting a different deck or a different stream-out map
# changes what the GDS *is*; that is a far worse outcome than the disclosure
# this file exists to fix. The `--verify` mode exists to prove it.
#
# HOW IT AVOIDS SPELLING ANYTHING
#
# One anchor, globbed: the routing tech LEF. Exactly one is installed, and its
# own filename carries the metal stack. So the stack is READ OUT of the PDK
# rather than typed in here, and every stack-dependent path below is selected
# with a value this script never had to know:
#
#     <cad>/PRTF_EDI_N65_<stack>_RDL.<rev>.tlef   -- globbed, 1 match
#            └── stack_full  e.g. "<n>M_<opt>"    -- parsed out, not typed
#                    └── stack_opt                -- drops the layer count
#
# That is also why this is more robust than the literals it replaces: a site
# that installs a different metal option gets a consistent set of paths, where
# before it got a hardcoded mismatch between the deck and the map. Note the
# metal STACK CODE ITSELF is a judgement call the maintainers have reserved
# (it is a purchase when it carries a revision and a public option name when it
# does not) -- this script sidesteps that question entirely by never storing it.
#
# EVERY GLOB IS EXACT-ONE. A glob that silently takes the first match is a
# defect: `find` order is not stable, so it would select a different file run to
# run and read as clean either way. This repository has been bitten by that
# class of bug before (Calibre's truncated result counts; check_connectivity
# stopping at 1000). So `pick_one` fails on 0 matches AND on 2+, and names the
# count and the candidates so the failure is actionable rather than mysterious.
#
# Usage:
#   pdk_paths.sh <key>          print the resolved path, exit 0
#   pdk_paths.sh --list         every key and its resolved value
#   pdk_paths.sh --verify       resolve all keys, report readability, exit 1 on
#                               any failure. Use this after touching a consumer.
#
# Keys:
#   tech-lef            routing tech LEF (the anchor; also read by gen_deck.py)
#   gdsout-map          foundry GDS stream-out layer map for this metal option
#   drc-ruledeck        foundry Calibre DRC rule deck for this metal stack
#   base-lef            standard-cell abstract LEF
#   io-pad-lef          bond-pad LEF for this metal stack
#   stdcell-vlog        standard-cell Verilog (power-aware) for GLS
#   io-vlog             IO-driver Verilog for GLS
#   lvs-deck            foundry Calibre LVS rule deck
#   lvs-source-added    foundry LVS source.added
#   stdcell-cdl         standard-cell CDL      ) NOT INSTALLED -- see below
#   iodrv-cdl           IO-driver CDL          ) these three resolve to the
#   pad-cdl             bond-pad CDL           ) path a _BE pack WOULD install
#   metal-stack         e.g. the layer count + option, parsed from the anchor
#   metal-option        the option alone
#   arm-target-lib      Arm sc12 target .db          ) under $PHYS_IP; the Arm
#   arm-db-dir          Arm sc12 .db directory       ) RELEASE directory is
#   arm-stdcell-verilog-dir  Arm sc12 release root   ) globbed, never spelled
#   arm-tf-file         Arm sc12 Milkyway tech file  ) (see ARM_MILKYWAY_STACK
#   arm-mw-ref-lib      Arm sc12 Milkyway ref lib    )  for the one exception)
#   arm-tech-dir        Arm cln65lp tech release root
#   eda-rtla-rm         RTLA Reference Methodology   ) under $EDA_RESEARCH_ROOT
#
# THE THREE CDLs ARE DELIBERATELY DANGLING. Every TSMC package installed here is
# a Front End (_FE) pack, so no transistor netlist exists for the standard
# cells, IO drivers or bond pads, and full LVS cannot run (black-box LVS can,
# and does). run_lvs.sh --check reports them as MISSING and that is the correct,
# intended answer. They are derived from the INSTALLED _FE package name with the
# suffix swapped, so they name the exact path the matching _BE pack would
# install to, and they keep saying MISSING until it does. Do NOT "fix" them by
# making them resolve to something that exists: that would silently turn
# black-box LVS into a full LVS run against the wrong netlists.
#
# Exit: 0 resolved, 1 unresolvable (diagnostic on stderr, nothing on stdout).
#-----------------------------------------------------------------------------
set -uo pipefail

: "${TSMC_65_HOME:=}"
: "${PHYS_IP:=}"
: "${EDA_RESEARCH_ROOT:=}"

# The Arm milkyway metal option. UNLIKE everything else in this file this one is
# NOT derivable: six options ship side by side and only a human knows which this
# design targets, so a glob here would have to guess. It is also the one code in
# this file whose disclosure status is genuinely unsettled — a metal option name
# is public, a purchased stack is not, and the two are spelled the same. It is
# therefore parked in a single overridable variable rather than decided:
# maintainers, this is yours to rule on. Note it does NOT agree with the TSMC
# stack this flow actually streams (see `metal-stack`); that is expected only
# because nothing live consumes it — the Milkyway keys feed a Synopsys flow this
# project does not run. Do not "fix" the mismatch without checking that first.
: "${ARM_MILKYWAY_STACK:=1p9m_6x2z}"

die() { printf 'pdk_paths: %s\n' "$*" >&2; exit 1; }

# Roots are checked per key, not up front: a host may have the Arm phys-IP tree
# without the foundry PDK, or the reverse, and only the keys that need a missing
# root should fail.
need_root() {
    local var=$1 val=$2
    [ -n "$val" ] || die "$var is unset. It is exported by ASIC/common.mk, which
  is the one place in this repository that names a site mount. Either include
  that makefile or export $var yourself. This is not a pass: the key you asked
  for cannot be resolved without it."
    [ -d "$val" ] || die "$var is set but is not a directory.
  On a host without that tree mounted the collateral is simply unavailable and
  this key is unresolvable; that is expected off the lab servers."
}

# pick_one <description> <glob...>  -- exactly one match, or a named failure.
pick_one() {
    local what=$1; shift
    local matches=() m
    for m in "$@"; do [ -e "$m" ] && matches+=("$m"); done
    if [ ${#matches[@]} -eq 1 ]; then printf '%s\n' "${matches[0]}"; return 0; fi
    if [ ${#matches[@]} -eq 0 ]; then
        die "no match for $what.
  Looked for: $*
  0 candidates. The PDK may be a different install layout, or you may lack
  membership of the group that can read it. NOT a pass - resolve it."
    fi
    { printf 'pdk_paths: %s is AMBIGUOUS - %d candidates, expected exactly 1.\n' \
        "$what" "${#matches[@]}"
      printf '  candidate: %s\n' "${matches[@]}"
      printf '  Refusing to guess: picking the first would select a different\n'
      printf '  file depending on directory order, and would read as clean\n'
      printf '  either way. Narrow the glob or set the path explicitly.\n'
    } >&2
    exit 1
}

# ── THE ANCHOR ──────────────────────────────────────────────────────────────
# One installed routing tech LEF. Its filename carries the metal stack, so the
# stack is read out of the PDK instead of being typed into a public repository.
resolve_anchor() {
    need_root TSMC_65_HOME "$TSMC_65_HOME"
    tech_lef=$(pick_one "the routing tech LEF" \
        "$TSMC_65_HOME"/CMOS/util/lef/*/PRTF_EDI_N65_*_RDL.*.tlef) || exit 1
    cad_dir=$(dirname "$tech_lef")
    local base; base=$(basename "$tech_lef")
    # PRTF_EDI_N65_<stack_full>_RDL.<rev>.tlef
    stack_full=${base#PRTF_EDI_N65_}; stack_full=${stack_full%%_RDL.*}
    # <n>M_<opt>  ->  <opt>
    stack_opt=${stack_full#*M_}
    [ -n "$stack_full" ] && [ -n "$stack_opt" ] || die \
        "could not parse the metal stack out of the tech LEF name '$base'.
  This script derives every stack-dependent path from that name so it never has
  to store the stack code itself; an unexpected name breaks that. Do not
  hardcode the stack to work around this - fix the parse."
}

# ── FE-package helper ───────────────────────────────────────────────────────
# The installed Front End package name carries the IP release code. Callers get
# the code by asking the filesystem, never by spelling it.
fe_dir()  { pick_one "$1" "${@:2}"; }
fe_rel()  { local d; d=$(basename "$1"); printf '%s\n' "${d%_FE}"; }

usage() { sed -n '/^# Keys:/,/^#   metal-option/p' "$0" | sed 's/^# \{0,1\}//' >&2; }

resolve() {
    local key=$1 prod d
    case $key in
    # Foundry keys glob under $TSMC_65_HOME; arm-* keys glob under $PHYS_IP.
    base-lef|io-pad-lef|stdcell-vlog|io-vlog|lvs-deck|lvs-source-added|stdcell-cdl|iodrv-cdl|pad-cdl|sc-nldm-dir|io-nldm-dir|pad-driver-lef)
        need_root TSMC_65_HOME "$TSMC_65_HOME" ;;&
    arm-*)
        need_root PHYS_IP "$PHYS_IP" ;;&
    esac
    case $key in
    tech-lef)     resolve_anchor; printf '%s\n' "$tech_lef" ;;
    metal-stack)  resolve_anchor; printf '%s\n' "$stack_full" ;;
    metal-option) resolve_anchor; printf '%s\n' "$stack_opt" ;;

    gdsout-map)
        resolve_anchor
        pick_one "the GDS stream-out map for metal option $stack_opt" \
            "$cad_dir"/PR_tech/Cadence/GdsOutMap/PRTF_EDI_N65_gdsout_"$stack_opt".*.map
        ;;
    drc-ruledeck)
        resolve_anchor
        pick_one "the foundry DRC rule deck for metal stack $stack_full" \
            "$TSMC_65_HOME"/CMOS/util/MAIN_DRC_TopMu/CLN65S_"$stack_full".*
        ;;

    base-lef)
        pick_one "the standard-cell LEF" \
            "$TSMC_65_HOME"/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_*_FE/TSMCHOME/digital/Back_End/lef/tcbn65lp_*/lef/tcbn65lp_9lmT2.lef
        ;;
    io-pad-lef)
        resolve_anchor
        pick_one "the bond-pad LEF for metal stack $stack_full" \
            "$TSMC_65_HOME"/iolib/tpbn65v_*_FE/TSMCHOME/digital/Back_End/lef/tpbn65v_*/cup/9m/"$stack_full"/lef/tpbn65v_9lm.lef
        ;;
    stdcell-vlog)
        pick_one "the standard-cell Verilog" \
            "$TSMC_65_HOME"/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_*_FE/TSMCHOME/digital/Front_End/verilog/tcbn65lp_*/tcbn65lp_pwr.v
        ;;
    io-vlog)
        pick_one "the IO-driver Verilog" \
            "$TSMC_65_HOME"/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_*_FE/TSMCHOME/digital/Front_End/verilog/tphn65lpgv2od3_sl_*/tphn65lpgv2od3_sl.v
        ;;

    # The NLDM (liberty) directories Genus and Innovus read for timing. Both the
    # package release and the inner library release are globbed.
    sc-nldm-dir)
        pick_one "the standard-cell NLDM directory" \
            "$TSMC_65_HOME"/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_*_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_*
        ;;
    io-nldm-dir)
        pick_one "the IO-driver NLDM directory" \
            "$TSMC_65_HOME"/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_*_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tphn65lpgv2od3_sl_*
        ;;

    # The unpatched IO-driver LEF patch_pad_lef.py reads. Both release
    # directories in the path are globbed.
    pad-driver-lef)
        pick_one "the IO-driver LEF" \
            "$TSMC_65_HOME"/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_*_FE/TSMCHOME/digital/Back_End/lef/tphn65lpgv2od3_sl_*/mt_2/9lm/lef/tphn65lpgv2od3_sl_9lm.lef
        ;;

    lvs-deck)         pick_one "the foundry LVS deck" "$TSMC_65_HOME"/CMOS/LP/pdk/Calibre/lvs/calibre.lvs ;;
    lvs-source-added) pick_one "the foundry LVS source.added" "$TSMC_65_HOME"/CMOS/LP/pdk/Calibre/lvs/source.added ;;

    # The three that do not exist. See the header: they name where the matching
    # _BE pack would install, derived from the _FE pack that IS installed, so
    # they stay MISSING (which is the correct answer) without this file having
    # to spell an IP release code.
    stdcell-cdl)
        local d rel
        d=$(fe_dir "the standard-cell _FE package" \
            "$TSMC_65_HOME"/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_*_FE) || exit 1
        rel=$(fe_rel "$d")
        printf '%s\n' "$(dirname "$d")/${rel}_BE/TSMCHOME/digital/Back_End/cdl/${rel}/tcbn65lp.cdl"
        ;;
    iodrv-cdl)
        local d rel
        d=$(fe_dir "the IO-driver _FE package" \
            "$TSMC_65_HOME"/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_*_FE) || exit 1
        rel=$(fe_rel "$d")
        printf '%s\n' "$(dirname "$d")/${rel}_BE/TSMCHOME/digital/Back_End/cdl/tphn65lpgv2od3_sl.cdl"
        ;;
    pad-cdl)
        local d rel
        d=$(fe_dir "the bond-pad _FE package" "$TSMC_65_HOME"/iolib/tpbn65v_*_FE) || exit 1
        rel=$(fe_rel "$d")
        printf '%s\n' "$(dirname "$d")/${rel}_BE/TSMCHOME/digital/Back_End/cdl/tpbn65v.cdl"
        ;;

    # ── Arm phys-IP, rooted at $PHYS_IP ─────────────────────────────────────
    # `sc12_base_rvt/*` and `arm_tech/*` are the Arm RELEASE directories. Exactly
    # one of each is installed, so globbing them selects the same tree the
    # hardcoded release codes did while spelling neither. The library BASENAMES
    # kept below carry no revision and are public family/variant spellings.
    arm-target-lib)
        pick_one "the Arm sc12 target .db" \
            "$PHYS_IP"/arm/tsmc/cln65lp/sc12_base_rvt/*/db/sc12_cln65lp_base_rvt_ss_typical_max_1p08v_125c.db
        ;;
    arm-db-dir)
        pick_one "the Arm sc12 .db directory" \
            "$PHYS_IP"/arm/tsmc/cln65lp/sc12_base_rvt/*/db
        ;;
    arm-stdcell-verilog-dir)
        pick_one "the Arm sc12 release directory" \
            "$PHYS_IP"/arm/tsmc/cln65lp/sc12_base_rvt/*
        ;;
    arm-tf-file)
        pick_one "the Arm sc12 Milkyway tech file for stack $ARM_MILKYWAY_STACK" \
            "$PHYS_IP"/arm/tsmc/cln65lp/arm_tech/*/milkyway/"$ARM_MILKYWAY_STACK"/sc12_tech.tf
        ;;
    arm-mw-ref-lib)
        pick_one "the Arm sc12 Milkyway reference library for stack $ARM_MILKYWAY_STACK" \
            "$PHYS_IP"/arm/tsmc/cln65lp/sc12_base_rvt/*/milkyway/"$ARM_MILKYWAY_STACK"/sc12_cln65lp_base_rvt
        ;;
    arm-tech-dir)
        pick_one "the Arm cln65lp tech release directory" \
            "$PHYS_IP"/arm/tsmc/cln65lp/arm_tech/*
        ;;
    arm-tluplus-dir)
        pick_one "the Arm TLUplus directory for stack $ARM_MILKYWAY_STACK" \
            "$PHYS_IP"/arm/tsmc/cln65lp/arm_tech/*/synopsys_tluplus/"$ARM_MILKYWAY_STACK"
        ;;

    # The memory/ROM compilers. These two return a path RELATIVE to $PHYS_IP:
    # common.mk joins them onto MEM_COMPILER_DIR, which is deliberately
    # re-pointable at a local rsync copy (the shared install cannot enumerate its
    # own views over NFS), so an absolute answer would defeat that. The compiler
    # PRODUCT names carry no revision and stay; only the release does not.
    arm-rf-compiler-rel|arm-rom-compiler-rel)
        case $key in
        arm-rf-compiler-rel)  prod=rf_sp_hdf_hvt_rvt ;;
        arm-rom-compiler-rel) prod=rom_via_hdd_rvt_rvt ;;
        esac
        d=$(pick_one "the Arm $prod compiler release" \
                "$PHYS_IP"/arm/tsmc/cln65lp/"$prod"/*) || exit 1
        printf '%s\n' "${d#"$PHYS_IP"/}"
        ;;

    # ── EDA install, rooted at $EDA_RESEARCH_ROOT ───────────────────────────
    # A tool VERSION is the same inventory-shaped disclosure as a PDK revision,
    # so it is globbed rather than spelled. Exact-one applies here too: taking
    # the first of several installed RTLA-RM versions would silently pick a
    # different methodology depending on directory order.
    eda-rtla-rm)
        need_root EDA_RESEARCH_ROOT "$EDA_RESEARCH_ROOT"
        pick_one "the RTLA Reference Methodology release" "$EDA_RESEARCH_ROOT"/RTLA-RM_*
        ;;

    *) printf 'pdk_paths: unknown key %s\n\n' "$key" >&2; usage; exit 1 ;;
    esac
}

ALL_KEYS="tech-lef gdsout-map drc-ruledeck base-lef io-pad-lef stdcell-vlog
          io-vlog lvs-deck lvs-source-added stdcell-cdl iodrv-cdl pad-cdl
          metal-stack metal-option
          arm-target-lib arm-db-dir arm-stdcell-verilog-dir arm-tf-file
          arm-mw-ref-lib arm-tech-dir arm-tluplus-dir
          arm-rf-compiler-rel arm-rom-compiler-rel
          sc-nldm-dir io-nldm-dir pad-driver-lef eda-rtla-rm"

case ${1:-} in
    --list)
        for k in $ALL_KEYS; do printf '%-18s %s\n' "$k" "$(resolve "$k")"; done ;;
    --verify)
        # Readability is reported, never required: the three CDLs are SUPPOSED
        # to be missing, so a run where they are absent is a pass.
        rc=0
        for k in $ALL_KEYS; do
            v=$("$0" "$k") || { rc=1; continue; }
            case $k in
            metal-*|arm-*-compiler-rel) printf '  ok        %-18s %s\n' "$k" "$v" ;;
            stdcell-cdl|iodrv-cdl|pad-cdl)
                if [ -r "$v" ]; then     printf '  PRESENT   %-18s %s\n' "$k" "$v"
                                         printf '            (a _BE pack has landed - full LVS is now possible)\n'
                else                     printf '  expected- %-18s %s\n' "$k" "$v"
                                         printf '  missing   (correct: only _FE packs are installed here)\n'; fi ;;
            *)
                if [ -r "$v" ]; then     printf '  ok        %-18s %s\n' "$k" "$v"
                else                     printf '  UNREADABLE %-17s %s\n' "$k" "$v"; rc=1; fi ;;
            esac
        done
        [ $rc -eq 0 ] && printf 'pdk_paths: all keys resolved.\n' \
                      || printf 'pdk_paths: FAILURES above.\n' >&2
        exit $rc ;;
    ""|-h|--help) usage; exit 1 ;;
    *) resolve "$1" ;;
esac
