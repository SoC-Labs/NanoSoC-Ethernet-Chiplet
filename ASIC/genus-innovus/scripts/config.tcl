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

# ── Foundry library paths — RESOLVED, NOT SPELLED ───────────────────────────
# These used to name the deck/library RELEASE this site licensed, in a PUBLIC
# repository. They now come from ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh,
# which globs the installed PDK and derives the metal stack from the single
# installed tech LEF. Selection is unchanged — every path below resolves
# byte-identically to the literal it replaced; `make -C $DESIGN_HOME/ASIC
# -f common.mk pdk-paths` re-proves that on demand.
#
# THE SAME RESOLVER THE MAKEFILES USE. ASIC/common.mk exports these as PDK_*
# before Innovus launches, so the P&R flow, the DRC flow, the LVS flow and the
# KLayout deck generator cannot drift onto different foundry collateral. The
# `exec` fallback is for a config.tcl sourced outside that makefile; it calls
# the identical script, so there is still exactly one resolution.
proc site_env {envvar what} {
    if {[info exists ::env($envvar)] && $::env($envvar) ne ""} { return $::env($envvar) }
    die "$envvar is not set, so $what cannot be located. ASIC/common.mk exports
  it and is the one place in this repository that names a site mount - run this
  flow through a makefile that includes it, or export $envvar yourself. Do not
  work around this by pasting an absolute path back in: this repository is
  public and that is the disclosure the export exists to avoid."
}

proc pdk_path {key envvar} {
    if {[info exists ::env($envvar)] && $::env($envvar) ne ""} {
        return $::env($envvar)
    }
    set sh $::design_home/ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh
    if {![file executable $sh]} {
        die "cannot resolve foundry path '$key': $envvar is not set and the
  resolver $sh is missing or not executable. Nothing can select the right deck
  or layer map without one of the two - this is not a state to work around by
  hardcoding a path back in."
    }
    if {[catch {exec $sh $key} out]} {
        die "cannot resolve foundry path '$key' via $sh:\n$out"
    }
    return $out
}


set hdl_file_list ../scripts/read_flist.tcl

# System Paths — resolved, not spelled. Both of these named the library RELEASE
# this site licensed, twice each (the package and the inner library directory).
# The trailing slash on io_lib_dir is PRESERVED deliberately: it is concatenated
# into $lib_search_path_list below and the value must not change shape.
set io_lib_dir [pdk_path io-nldm-dir PDK_IO_NLDM_DIR]/
set sc_lib_dir [pdk_path sc-nldm-dir PDK_SC_NLDM_DIR]

# Automatically setup !Don't touch!
# Derived from MEM_LIB_ROOT (ASIC/common.mk names it, and is the one place in
# this repository that names a site mount). Trailing slashes preserved exactly.
set mem_lib_root [site_env MEM_LIB_ROOT "the compiled-memory library root"]
set rf_32k_dir $mem_lib_root/rf_32k
set rf_16k_dir $mem_lib_root/rf_16k/ 
set rf_08k_dir $mem_lib_root/rf_08k/ 
set rf_01k_dir $mem_lib_root/rf_01k/
set flash_cache_data_dir $mem_lib_root/flash_cache_data
set flash_cache_tag_dir $mem_lib_root/flash_cache_tag

# ── THE BOOT ROMs — THIS RUN'S, NOT THE SHARED DROP ────────────────────────
# These two macros are MASK PROGRAMMED, and until 2026-08-14 they were a
# gitignored binary drop hand-copied out of another user's tapeout tree, with no
# dependency on the firmware they were supposed to contain. Both shipped holding
# something else. ASIC/rom_build.mk now compiles them per run into
# <run>/romlibs and pins the run to that build; ROMLIBS_DIR is how the run tells
# these scripts where its own copy is.
#
# THE FALLBACK IS THE OLD SHARED PATH, and it is not a soft landing: everything
# in ASIC/romlibs is still gated word-for-word by ASIC/rom_gate.mk before
# synthesis is allowed to start. What the override buys is that synthesis, P&R
# and stream-out read the SAME build — the run holds it, so it cannot be
# swapped underneath a flow that takes hours to cross those three stages.
if {[info exists ::env(ROMLIBS_DIR)]} {
    set romlib_root $::env(ROMLIBS_DIR)
} else {
    set romlib_root $::design_home/ASIC/romlibs
}
set bootrom_dir $romlib_root/cc_rom
set eth_rom_dir $romlib_root/eth_rom

# A missing ROM directory here becomes "Cannot open file rom_via_*.lib" about
# ten minutes into a licence hour, with the path buried in a Genus log. Say it
# now, with the variable that produced it.
foreach {_rd _rn} [list $bootrom_dir cc_rom $eth_rom_dir eth_rom] {
    if {![file isdirectory $_rd]} {
        error "config.tcl: no $_rn macro directory at $_rd\
             \n  ROMLIBS_DIR = [expr {[info exists ::env(ROMLIBS_DIR)] ? $::env(ROMLIBS_DIR) : \"(unset — using the default shared drop)\"}]\
             \n  Build this run's ROMs:  make -C ASIC -f common.mk rom-run ROM_RUN_DIR=$romlib_root"
    }
}
unset _rd _rn

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


set TECH_LEF   [pdk_path tech-lef    PDK_TECH_LEF]
set BASE_LEF   [pdk_path base-lef    PDK_BASE_LEF]
set IO_PAD_LEF [pdk_path io-pad-lef  PDK_IO_PAD_LEF]
# Alternative std-cell tech LEF, kept for reference: the Arm sc12 Milkyway-side
# tech file under $::env(PHYS_IP) (key arm-tech-dir + /lef/<stack>/sc12_tech.lef).
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

# ── GDS stream-out layer map ────────────────────────────────────────────────
# Read by the LEGACY flow's write_stream (asic-flows/Cadence/4_pnr_route.tcl),
# which errors by name if this is unset rather than failing inside write_stream.
# The eval flow reaches the SAME file through its own knob, EVR_GDS_MAP_FILE
# (scripts/4b_pnr_route_eval.tcl) — one map, two spellings, deliberately not two
# maps.
#
# THIS IS THE DERIVED MAP, NOT THE STOCK PDK ONE, AND THAT IS THE POINT. The
# stock map streams LEFOBS — LEF *obstruction*, i.e. routing blockage — onto the
# same GDS layer as the metal it blocks, so a blockage arrives at the foundry as
# conductor. That is the "phantom metal" defect: 68.8% of the metal in the
# 2026-08-07 tapeout stream, and the measured source of the 1,549 antenna
# results and the M*.W.3 blankets. scripts/gdsmap_derive.py moves LEFOBS to
# <layer>+9000 instead (keeping the geometry, off every mask layer), except on
# M8/M9/AP where OBS is the bond pads' real pad metal and must stay.
#
# DERIVED FROM THE READ-ONLY PDK, NOT COMMITTED — a BUILD PRODUCT, exactly like
# IO_PAD_DRIVER_LEF above, and for the same licence reason. Produce it with:
#     make -C $DESIGN_HOME/ASIC/genus-innovus gdsmap
# `pnr_route` and `pnr_route_eval` both depend on that target, so under make the
# file is always present and current before Innovus starts.
#
# Set GDS_LAYER_MAP in the environment to A/B against the stock PDK map without
# editing this file (`make restream` does the same for an already-routed DB).
#
# RESOLVED BY GLOB, NOT BY NAME. The derived map is our own build product, but it
# inherits the vendor map's release-coded filename and this repository is public,
# so the name is not spelled here. `*.derived.map` selects the identical file and
# survives a PDK map upgrade that a hardcoded name would silently miss. The same
# glob is used by 4b_pnr_route_eval.tcl, so the two consumers cannot diverge --
# which they could when each carried its own copy of the literal.
#
# Deliberately NOT fatal on zero or several matches, unlike the stage script:
# this file is sourced by EVERY stage (see the note below), and synthesis,
# placement and CTS neither read nor need the map. It leaves gds_layer_map empty
# and lets the warning below do its job; the stream-out stage does its own strict
# check, and the Makefile gates before Innovus takes a licence.
if {[info exists ::env(GDS_LAYER_MAP)] && $::env(GDS_LAYER_MAP) ne ""} {
    set gds_layer_map $::env(GDS_LAYER_MAP)
} else {
    set _cfg_maps [glob -nocomplain -directory \
        $::design_home/ASIC/genus-innovus/work/tech *.derived.map]
    set gds_layer_map [expr {[llength $_cfg_maps] == 1 ? [lindex $_cfg_maps 0] : ""}]
    unset _cfg_maps
}

# WARN, NOT error: this file is sourced by EVERY stage, and synthesis, placement
# and CTS neither read nor need the map. Making them fatal on a missing stream
# map would break four stages to protect one. The stage that does stream is
# gated in the Makefile BEFORE Innovus launches, which costs no licence — a
# missing map must never be discovered hours in, at write_stream. That was the
# 2026-08-14 defect this line exists to close.
if {![file readable $gds_layer_map]} {
    warn "GDS stream-out map not generated: $gds_layer_map"
    warn "  produce it with: make -C \$DESIGN_HOME/ASIC/genus-innovus gdsmap"
    warn "  harmless before the route stage; write_stream will FAIL without it."
}

# Resolved like every other foundry path above, which also fixes the anomaly
# that this one was an ABSOLUTE literal while the rest already derived from
# $::env(TSMC_65_HOME). The deck must match the stack the stream uses; both are
# now chosen from the same anchor, so they cannot disagree.
set drc_ruledeck [pdk_path drc-ruledeck PDK_DRC_DECK]

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