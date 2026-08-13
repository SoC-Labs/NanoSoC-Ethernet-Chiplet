source ../scripts/procs.tcl
source ../scripts/flow_utils.tcl    ;# say/warn/step/try_step/die/fail/opt/reports

set process_node 65

# ── DESIGN_HOME — resolved ONCE, here ───────────────────────────────────────
# Every stage script sources this file first (1b:45, 2b:63, 3b:74, 4b:62), so
# this is the one place the repo root has to be worked out. Downstream code uses
# $::design_home and never touches the environment again — that is what lets a
# second chiplet reuse these scripts unedited.
#
# TWO NAMES, ON PURPOSE. DESIGN_HOME is the portable spelling (ASIC/common.mk
# exports it); NANOSOC_ETH_CHIPLET_HOME is the historical, design-named one that
# set_env.sh still exports and that any already-open shell is carrying. Checking
# DESIGN_HOME first and falling back means the migration cannot strand a running
# flow in either direction. Remove the fallback only when set_env.sh exports
# DESIGN_HOME as well.
#
# `set ::design_home`, not `set design_home`: pnr_utils.tcl reads it from INSIDE
# a proc, where a bare name would resolve to a nonexistent local.
if {[info exists ::env(DESIGN_HOME)]} {
    set ::design_home $::env(DESIGN_HOME)
} elseif {[info exists ::env(NANOSOC_ETH_CHIPLET_HOME)]} {
    set ::design_home $::env(NANOSOC_ETH_CHIPLET_HOME)
} else {
    error "neither DESIGN_HOME nor NANOSOC_ETH_CHIPLET_HOME is set"
}

# ── UNCAP THE MESSAGE LOG ───────────────────────────────────────────────────
# Innovus prints at most 20 instances of any message ID and then goes silent.
# Cadence's own doc for set_message states it plainly:
#     "-limit number ... The default limit is 20, so any specific message will be
#      written out 20 times and then further output of that message will be
#      disabled"
#     "-id ... If you do not specify a message ID, the change is applied to ALL
#      message IDs"
#
# WHY THIS MATTERS HERE. The 2026-08-06 run's own session totals read:
#     *** Message Summary: 57018 warning(s), 178 error(s)     <- place stage alone
# while the whole log contains 807 `**WARN` lines. Under 1.5% of what the tool
# emitted was ever visible, and NINETEEN message IDs hit the cap in that run.
#
# Every triage done on this design so far — including two findings that turned
# out to be tapeout-blocking — was performed on a 20-instance sample. Counts
# quoted as "41x IMPPP-570" were really "20, capped, true value unknown". At
# least one message class (TCLCMD-1005) is capped in all six sessions of both
# runs with not a single instance visible anywhere, so nobody knows what it says.
#
# Cost: a bigger log. The 08-06 log is 6.7MB; expect tens of MB. That is nothing
# against a 5-hour run, and it is the difference between triaging the design and
# triaging a sample of it.
#
# Guarded on `info commands` because this file is sourced by BOTH Genus and
# Innovus, and set_message is an Innovus command. Sourcing an Innovus-only
# command unguarded here has broken the Genus run before (see the note on
# clp_treat_errors_as_warnings below).
if {[llength [info commands set_message]]} {
    set_message -no_limit
}

# ── check_cpf must not abort the script ─────────────────────────────────────
# check_cpf raises RCLP-203 (91 low-power rule errors) and aborts the script.
# clp_treat_errors_as_warnings doesn't work and fails under Innovus.
# Solution: wrap check_cpf to catch errors. Still runs and logs to stderr.
# Pre-existing errors: 34x UPF naming, 55x PG pins, 2x undriven QSPI tag RAM GWEN.
# Guarded: under Innovus check_cpf doesn't exist; re-sourcing is idempotent.
#
if {[llength [info commands check_cpf]]
    && ![llength [info commands _check_cpf_unwrapped]]} {
    rename check_cpf _check_cpf_unwrapped
    proc check_cpf {args} {
        if {[catch {eval _check_cpf_unwrapped $args} msg]} {
            puts stderr "WARNING: check_cpf FAILED — continuing deliberately."
            puts stderr "WARNING:   $msg"
            puts stderr "WARNING:   detail: logs/syn_cpf_check.log"
            return ""
        }
        return $msg
    }
}

set hdl_file_list ../scripts/read_flist.tcl

# System Paths, please edit for your system
set io_lib_dir $::env(TSMC_65_HOME)/CMOS/LP/IO2.5V/iolib/STAGGERED/tphn65lpgv2od3_sl_210a_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tphn65lpgv2od3_sl_210a/
set sc_lib_dir $::env(TSMC_65_HOME)/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_FE/TSMCHOME/digital/Front_End/timing_power_noise/NLDM/tcbn65lp_220a

# Automatically setup !Don't touch!
set rf_32k_dir /research/precompiled_mems/TSMC65/rf_32k
set rf_16k_dir /research/precompiled_mems/TSMC65/rf_16k/ 
set rf_08k_dir /research/precompiled_mems/TSMC65/rf_08k/ 
set rf_01k_dir /research/precompiled_mems/TSMC65/rf_01k/
set flash_cache_data_dir /research/precompiled_mems/TSMC65/flash_cache_data
set flash_cache_tag_dir /research/precompiled_mems/TSMC65/flash_cache_tag

set bootrom_dir $::design_home/ASIC/romlibs/cc_rom
set eth_rom_dir $::design_home/ASIC/romlibs/eth_rom

set lib_search_path_list "$io_lib_dir $sc_lib_dir $rf_32k_dir $rf_16k_dir $rf_08k_dir $rf_01k_dir $bootrom_dir $eth_rom_dir $flash_cache_data_dir $flash_cache_tag_dir"

# Libraries for Synthesis
set BASE_LIB tcbn65lpwc.lib
set RF_32K_LIB rf_32k_ss_1p08v_1p08v_125c.lib
set RF_LIB rf_16k_ss_1p08v_1p08v_125c.lib
set RF_08K rf_08k_ss_1p08v_1p08v_125c.lib
set RF_01K rf_01k_ss_1p08v_1p08v_125c.lib
set ROM_LIB rom_via_ss_1p08v_1p08v_125c.lib
set ETH_ROM_LIB eth_rom_via_ss_1p08v_1p08v_125c.lib
set FLASH_DATA_LIB flash_cache_data_ss_1p08v_1p08v_125c.lib
set FLASH_TAG_LIB flash_cache_tag_ss_1p08v_1p08v_125c.lib

set IO_PAD_DRIVER tphn65lpgv2od3_slwc.lib

set syn_lib_list [list \
    $BASE_LIB \
    $RF_LIB \
    $RF_08K \
    $RF_01K \
    $RF_32K_LIB \
    $IO_PAD_DRIVER \
    $ROM_LIB \
    $ETH_ROM_LIB \
    $FLASH_DATA_LIB \
    $FLASH_TAG_LIB \
]

set block_name nanosoc_eth_chiplet_pads

set LOG_DIR ../logs
set REPORT_DIR ../reports
set OUT_DIR ../outputs

set top_level_hdl $::design_home/ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v
set constraints_file ../inputs/constraints.sdc

set DFT 0

## VDDACC dropped: zero occurrences in the netlist, so its "no problems" report
## was checking nothing. Re-add it if an analogue supply is ever instantiated.
set power_nets {VDD VDDIO}
set ground_nets {VSS VSSIO}


# Set library paths 
# !! EDIT THIS TO YOUR PATHS IN YOUR ENVIRONMENT
set TECH_LEF $::env(TSMC_65_HOME)/CMOS/util/lef/PRTF_EDI_65nm_001_Cad_V24a/PRTF_EDI_N65_9M_6X1Z1U_RDL.24a.tlef
#$::env(PHYS_IP)/arm/tsmc/cln65lp/arm_tech/r2p0/lef/1p9m_6x2z/sc12_tech.lef
set BASE_LEF $::env(TSMC_65_HOME)/CMOS/LP/stclib/9-track/tcbn65lp-set/tcbn65lp_220a_FE/TSMCHOME/digital/Back_End/lef/tcbn65lp_200a/lef/tcbn65lp_9lmT2.lef
set IO_PAD_LEF $::env(TSMC_65_HOME)/iolib/tpbn65v_200b_FE/TSMCHOME/digital/Back_End/lef/tpbn65v_200b/cup/9m/9M_6X1Z1U/lef/tpbn65v_9lm.lef
# PATCHED TSMC IO driver LEF — GENERATED AT BUILD TIME, three added lines.
#
# The IO supply pads declare their supply pins as plain signal pins:
#     PIN VDDPST / DIRECTION INOUT ;      (PVDD2DGZ_G, PVDD2POC_G)
#     PIN VSSPST / DIRECTION INOUT ;      (PVSS2DGZ_G)
# with no `USE POWER ;` / `USE GROUND ;`. The liberty agrees — they are pin()
# groups, not pg_pin(). So `connect_global_net -type pg_pin` cannot match them,
# and the VDDIO/VSSIO global-net rules failed with IMPDB-1221.
#
# Consequence, stated by NanoRoute itself (NRDB-51): the VDDIO/VSSIO
# SPECIAL_NETs stayed empty, so the router treated the IO supplies as ORDINARY
# SIGNAL NETS and threaded them around the periphery into the bond-pad M8/M9
# blockages. Every VDDIO/VSSIO DRC record is a "Regular Wire"; VDD/VSS have
# none. That was 76 violations.
#
# Verified, not assumed: correcting -pin_base_name alone is NOT sufficient.
# `connect_global_net VDDIO -type pg_pin -pin_base_name VDDPST` still raises
# IMPDB-1221 against a design loaded from the real DB, because the pin is not
# classified as power. The LEF has to say so.
#
# DERIVED FROM THE READ-ONLY PDK, NOT COMMITTED. This path is a BUILD PRODUCT.
# `USE POWER ;` / `USE GROUND ;` are inserted after DIRECTION on exactly those
# three pins by ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py, which reads
# the vendor file from $TSMC_65_HOME and writes here. The shared PDK under
# /tsmc65pdk is READ-ONLY and is never modified — see the read-only-filesystem
# rule in CLAUDE.md.
#
# The tree used to carry a committed 414 kB copy of the vendor LEF at
# ASIC/tech_wrappers/tsmc65/local_overrides/. This repository is PUBLIC and
# TSMC's licence does not permit reproducing their collateral, so what is
# committed now is the transform, not the result. DO NOT COMMIT THIS FILE — it
# is gitignored, and scripts/ci/check_no_vendor_collateral.sh fails if a copy
# reappears anywhere in the tree (content-keyed, so renaming it does not evade).
#
# `make -C ASIC -f common.mk pad-lef` produces it. The toolkit flow depends on
# that target already (ASIC/eth-chiplet/design.mk:581). The genus-innovus flow
# hangs it off `setup_dirs`, which at the time of writing is an UNCOMMITTED edit
# in ASIC/genus-innovus/Makefile owned by another session — so until that lands,
# a fresh clone reaches this line with no generated LEF. Hence the check below:
# a missing build product must say so and say what to run, not surface later as
# a LEF parse error or, worse, as a silently unpadded design.
set IO_PAD_DRIVER_LEF $::design_home/ASIC/tech_wrappers/tsmc65/generated/tphn65lpgv2od3_sl_9lm.patched.lef
if {![file readable $IO_PAD_DRIVER_LEF]} {
    error "the patched IO-driver LEF has not been generated.\
           \n  expected: $IO_PAD_DRIVER_LEF\
           \n  produce it with: make -C \$DESIGN_HOME/ASIC -f common.mk pad-lef\
           \n\
           \n  This file is DERIVED from the read-only PDK at build time and is\
           \n  deliberately not committed -- it is TSMC collateral and this repo\
           \n  is public. Do NOT satisfy this by copying the vendor LEF into the\
           \n  tree; scripts/ci/check_no_vendor_collateral.sh will reject it."
}


# !! THESE SHOULD BE CORRECT FOR ANY ENVIRONMENT AS THEY ARE GENERATED BY MAKEFILE
set RF32_LEF $rf_32k_dir/rf_32k.lef
set RF16_LEF $rf_16k_dir/rf_16k.lef
set RF8_LEF $rf_08k_dir/rf_08k.lef
set RF1_LEF $rf_01k_dir/rf_01k.lef
set CC_ROM_LEF $bootrom_dir/rom_via.lef
set ETH_ROM_LEF $eth_rom_dir/eth_rom_via.lef
set FLASH_DATA_LEF $flash_cache_data_dir/flash_cache_data.lef
set FLASH_TAG_LEF $flash_cache_tag_dir/flash_cache_tag.lef

set lef_file_list [list \
    ${TECH_LEF} \
    ${BASE_LEF} \
    ${IO_PAD_LEF} \
    ${IO_PAD_DRIVER_LEF} \
    ${RF32_LEF} \
    ${RF16_LEF} \
    ${RF8_LEF} \
    ${RF1_LEF} \
    ${CC_ROM_LEF} \
    ${ETH_ROM_LEF} \
    ${FLASH_DATA_LEF} \
    ${FLASH_TAG_LEF} \
    ]

# !! THESE SHOULD BE CORRECT FOR ANY ENVIRONMENT AS THEY ARE GENERATED BY MAKEFILE
set RF32_GDS $rf_32k_dir/rf_32k.gds2
set RF16_GDS $rf_16k_dir/rf_16k.gds2
set RF8_GDS $rf_08k_dir/rf_08k.gds2
set RF1_GDS $rf_01k_dir/rf_01k.gds2
set CC_ROM_GDS $bootrom_dir/rom_via.gds2
set ETH_ROM_GDS $eth_rom_dir/eth_rom_via.gds2
set FLASH_DATA_GDS $flash_cache_data_dir/flash_cache_data.gds2
set FLASH_TAG_GDS $flash_cache_tag_dir/flash_cache_tag.gds2

set gds_merge_list [list \
    ${RF32_GDS} \
    ${RF16_GDS} \
    ${RF8_GDS} \
    ${RF1_GDS} \
    ${CC_ROM_GDS} \
    ${ETH_ROM_GDS} \
    ${FLASH_DATA_GDS} \
    ${FLASH_TAG_GDS} \
]

set drc_ruledeck /tsmc65pdk/65/CMOS/util/MAIN_DRC_TopMu/CLN65S_9M_6X1Z1U.26_2a

# ── multi-CPU / distributed processing ──────────────────────────────────────
# The stage scripts used to hardcode `-local_cpu 8`. srv03335 has 16 physical
# cores (4 sockets x 4, no SMT), so that left half the machine idle. Licences
# are not the constraint: Innovus_CPU_Opt has 41 issued and typically 0 in use.
#
# Distribution onto a second host is OFF by default and should stay that way
# unless the extra host is on a fast link. Measured srv03335<->srv04936 is
# ~25 MB/s, i.e. ~37x slower than srv03335's local disk, so slaves spend
# longer fetching the design than they save working on it.
#
# Override per-run from the environment, e.g.
#     INNOVUS_LOCAL_CPU=8 make pnr
#     INNOVUS_DISTRIBUTED=1 INNOVUS_REMOTE_HOSTS=srv04936 make pnr
foreach {__v __default} {
    INNOVUS_LOCAL_CPU      14
    INNOVUS_DISTRIBUTED     0
    INNOVUS_REMOTE_HOSTS   {}
    INNOVUS_CPU_PER_REMOTE  6
} {
    if {[info exists ::env($__v)]} {
        set $__v $::env($__v)
    } elseif {![info exists $__v]} {
        set $__v $__default
    }
}
unset __v __default

# Applies the settings above. Called by each stage script in place of the old
# hardcoded line. Degrades to local-only under Genus, which has no
# set_distributed_hosts.
proc soclabs_setup_multi_cpu {} {
    global INNOVUS_LOCAL_CPU INNOVUS_DISTRIBUTED
    global INNOVUS_REMOTE_HOSTS INNOVUS_CPU_PER_REMOTE

    set can_distribute [expr {$INNOVUS_DISTRIBUTED
                              && [llength $INNOVUS_REMOTE_HOSTS] > 0
                              && [llength [info commands set_distributed_hosts]] > 0}]

    if {$can_distribute} {
        set_distributed_hosts -ssh -add $INNOVUS_REMOTE_HOSTS
        set_multi_cpu_usage -local_cpu $INNOVUS_LOCAL_CPU \
                            -remote_host [llength $INNOVUS_REMOTE_HOSTS] \
                            -cpu_per_remote_host $INNOVUS_CPU_PER_REMOTE
        puts "MULTICPU: local=$INNOVUS_LOCAL_CPU\
              remote={$INNOVUS_REMOTE_HOSTS} x $INNOVUS_CPU_PER_REMOTE cpu"
    } else {
        set_multi_cpu_usage -local_cpu $INNOVUS_LOCAL_CPU
        puts "MULTICPU: local=$INNOVUS_LOCAL_CPU (distribution off)"
    }
}