################################################################################
# nanosoc-ethernet-chiplet / ASIC/eth-chiplet/config/design_config.tcl
#
# The DESIGN half of the tool setup for nanosoc_eth_chiplet_pads. The tech pack
# (tech/tsmc65) owns the standard cells, the IO library, the tech LEF, the cap
# tables, every layer and cell name, and the stream-out map. What is left here is
# the eight hard macros this design instantiates, its PG net names, its DFT
# setting, and two protections it needs from the tools.
#
# ── WHY THIS FILE EXISTS, WHEN ../genus-innovus/scripts/config.tcl DOES ─────
#
# It is the ONE Tcl file this directory owns, and reluctantly: every other file
# the manifest hands the tools is the live production file, pointed at rather
# than copied. The production config.tcl cannot be sourced as DESIGN_CONFIG_TCL
# for four measured reasons:
#
#   1. IT SOURCES TWO SIBLINGS BY RELATIVE PATH - the production flow's own
#      say/warn/die/opt/step helpers, over the top of the engine's, which the
#      toolkit has already loaded. That is two engines in one interpreter, not a
#      path problem a symlink fixes.
#   2. IT REDEFINES THE RUN'S OUTPUT TREE to ../logs, ../reports, ../outputs,
#      after flow_boot has already set all three from the run directory - so a
#      run would write its reports outside itself and every artefact assertion in
#      mk/flow.mk would fail on a run that had worked.
#   3. `set ::design_home` TRIPS THE COLLATERAL TYPO GUARD. The engine treats any
#      global matching design_* that is not one of the nine contract names as an
#      error, because a misspelt collateral variable is silent and produces a
#      wrong netlist with every check green.
#   4. IT DECLARES THE PROCESS, NOT JUST THE DESIGN - the TSMC Liberty, tech LEF,
#      base LEF, IO pad LEF and DRC ruledeck. In the toolkit those belong to the
#      tech pack, which DERIVES several of them from the PDK at load time.
#      Restating them here would be a static second copy of live values.
#
# So: the eight macros and the four PG nets are transcribed, and nothing else.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

#### 1. IDENTITY ###############################################################
#
# A design configuration that silently belongs to another block is worse than a
# missing one: the collateral would load and the netlist would be wrong.
if {$block_name ne "nanosoc_eth_chiplet_pads"} {
    error "design_config: block_name '$block_name' does not match this file.\
         \n  This file describes nanosoc_eth_chiplet_pads. BLOCK in design.mk\
         \n  says '$block_name'."
}


#### 2. MACRO LIBRARIES ########################################################
#
# Eight hard macros, instantiated 21 times between them (floorplan.tcl publishes
# the resolved list as ::PLACED_MACROS, and power_plan.tcl asserts 21).
#
#   rf_32k            eth (CPU0) IMEM                            AW=15
#   rf_16k            CPU1 IMEM, eth DMEM, eth scratch RX/TX      AW=14
#   rf_08k            CPU1 DMEM, shared cross-core SRAM           AW=13
#   rf_01k            QSPI line buffer                            AW=10
#   flash_cache_data  QSPI cache data array
#   flash_cache_tag   QSPI cache tag array
#   rom_via           chip-core bootrom      BUILT IN TREE
#   eth_rom_via       ethernet bootrom       BUILT IN TREE
#
# The register files and the two flash-cache arrays are pre-compiled and shared.
# THE TWO ROMs ARE NOT: they are compiled from the bootloader firmware into
# ASIC/romlibs/, and they do not exist until that has happened. On this host they
# CANNOT be rebuilt - the Arm memory compiler has listed zero generators since
# the RHEL 8.10 upgrade (../common.mk documents the whole diagnosis) - so the
# built tree is fetched, not made. design.mk's `romlibs-check` gate asserts all
# four ROM files before a licence-hour is spent, because Genus otherwise dies
# inside set_db with "Cannot open file rom_via_*.lib" about ten minutes in.
#
# Source: ../genus-innovus/scripts/config.tcl:89-97 (directories),
#         :102-125 (the max-corner .lib names), :179-222 (LEF and GDS lists),
#         scripts/nanosoc_eth_chiplet_pads.mmmc:5-10, :30-69 (all three corners)

set rf_32k_dir           /research/precompiled_mems/TSMC65/rf_32k
set rf_16k_dir           /research/precompiled_mems/TSMC65/rf_16k
set rf_08k_dir           /research/precompiled_mems/TSMC65/rf_08k
set rf_01k_dir           /research/precompiled_mems/TSMC65/rf_01k
set flash_cache_data_dir /research/precompiled_mems/TSMC65/flash_cache_data
set flash_cache_tag_dir  /research/precompiled_mems/TSMC65/flash_cache_tag

# The two ROM directories are in the PROJECT, and are located from the
# environment rather than from a hardcoded root. DESIGN_HOME is the portable
# spelling ../common.mk exports; NANOSOC_ETH_CHIPLET_HOME is the historical,
# design-named one that set_env.sh exports and that any already-open shell is
# carrying. Checking DESIGN_HOME first and falling back is what stops a
# half-migrated environment stranding a run in either direction - the same
# two-name rule ../genus-innovus/scripts/config.tcl:21-27 applies.
#
# Deliberately NOT `set design_home`: any global matching design_* is read by
# the engine as collateral (flow_utils.tcl:675-689) and an unrecognised one is a
# hard error. The name below cannot be mistaken for collateral.
# ROMLIBS_DIR, when set, names THIS RUN'S ROM directory and wins outright.
# ASIC/rom_build.mk compiles both macros per run into $(RUN_DIR)/romlibs and
# pins the run to that build, so the .lib synthesis reads, the .lef P&R reads
# and the .gds2 stream-out merges are one artefact rather than three reads of a
# shared directory that anything may have replaced in between. These ROMs are
# mask programmed and the shared drop has already shipped wrong bits once.
if {[info exists ::env(ROMLIBS_DIR)]} {
    set romlib_dir $::env(ROMLIBS_DIR)
} elseif {[info exists ::env(DESIGN_HOME)]} {
    set romlib_dir $::env(DESIGN_HOME)/ASIC/romlibs
} elseif {[info exists ::env(NANOSOC_ETH_CHIPLET_HOME)]} {
    set romlib_dir $::env(NANOSOC_ETH_CHIPLET_HOME)/ASIC/romlibs
} else {
    error "design_config: none of ROMLIBS_DIR, DESIGN_HOME or\
         \n  NANOSOC_ETH_CHIPLET_HOME is set. All three are exported by\
         \n  ASIC/common.mk, which ASIC/eth-chiplet/design.mk includes. A stage\
         \n  started outside make needs one of them in the environment."
}
set bootrom_dir $romlib_dir/cc_rom
set eth_rom_dir $romlib_dir/eth_rom

# ── ONE LOOP, SO THE FIVE LISTS CANNOT DRIFT APART ─────────────────────────
#
# Every macro is characterised at the same three points as the standard cells:
#     max  ss 1.08 V  125 C      min  ff 1.32 V  -40 C      typ  tt 1.20 V  25 C
#
# THE NAMES ARE THE CONTRACT AND THEY ARE CASE-SENSITIVE. The engine reads
# exactly DESIGN_LIBS_MAX / DESIGN_LIBS_MIN / DESIGN_LIBS_TYP / DESIGN_LEFS /
# DESIGN_GDS_MERGE / DESIGN_LIB_SEARCH_PATH. A misspelling is SILENT - it reads
# as "this design adds nothing", the list is never empty because the tech pack
# contributes to it, so the "nothing to map to" guard never fires, every
# compiled memory's Liberty is dropped, synthesis maps the macros to nothing,
# and every artefact assertion passes. The toolkit's own template and worked
# example shipped with all six of these misspelt (`design_liberty_max`), which
# is why the engine now treats a stray design_* global as an error.
#
# All five initialised explicitly, so re-sourcing this file interactively or
# from a probe script REBUILDS the lists rather than doubling them.
set DESIGN_LIBS_MAX  {}
set DESIGN_LIBS_MIN  {}
set DESIGN_LIBS_TYP  {}
set DESIGN_LEFS      {}
set DESIGN_GDS_MERGE {}

foreach {dir stem} [list \
        $rf_32k_dir           rf_32k \
        $rf_16k_dir           rf_16k \
        $rf_08k_dir           rf_08k \
        $rf_01k_dir           rf_01k \
        $flash_cache_data_dir flash_cache_data \
        $flash_cache_tag_dir  flash_cache_tag \
        $bootrom_dir          rom_via \
        $eth_rom_dir          eth_rom_via ] {
    lappend DESIGN_LIBS_MAX  $dir/${stem}_ss_1p08v_1p08v_125c.lib
    lappend DESIGN_LIBS_MIN  $dir/${stem}_ff_1p32v_1p32v_m40c.lib
    lappend DESIGN_LIBS_TYP  $dir/${stem}_tt_1p20v_1p20v_25c.lib
    lappend DESIGN_LEFS      $dir/${stem}.lef
    lappend DESIGN_GDS_MERGE $dir/${stem}.gds2
}

set DESIGN_LIB_SEARCH_PATH [list \
    $rf_32k_dir $rf_16k_dir $rf_08k_dir $rf_01k_dir \
    $flash_cache_data_dir $flash_cache_tag_dir \
    $bootrom_dir $eth_rom_dir]

# ── NO DESIGN_LEF_OVERRIDES, AND THAT IS DELIBERATE ────────────────────────
#
# This design does need the patched IO driver LEF - the vendor file declares
# three pad-cell supply pins as plain signal pins, which left the VDDIO/VSSIO
# special nets empty and cost 76 DRC records. But the tech pack asks for the
# patched copy by ENVIRONMENT VARIABLE (TSMC65_IO_DRIVER_LEF), and design.mk
# exports it. Overriding the LEF list here as well would substitute a file that
# is already the one in the list.
#
# The toolkit's worked example uses DESIGN_LEF_OVERRIDES with `tech_get io_lef`
# as the key to replace. That was correct against the pack as it stood; the pack
# has since taken the override into its own hands, and the env-var route is now
# the supported one (tech/tsmc65/tech.tcl:138-146).


#### 3. EQUIVALENCE CHECKING ###################################################
#
# A Liberty file cannot express a 32 Kb RAM: it carries pins, timing arcs and
# power, but no logic function. LEC has nothing to compare a memory against and
# must be told to treat it as a blackbox on BOTH sides.
#
# Blackboxing is not a loss of coverage here - it is what makes memory
# CONNECTIVITY verified. Every address, data, write-enable, chip-enable and
# clock pin becomes a compare point and every Q output drives compared logic, so
# a swapped address bit or a dropped write-enable is still caught.
#
# ONE ENTRY PER STEM IN THE LOOP ABOVE - all eight. A macro with a Liberty in
# DESIGN_LIBS_MAX and no entry here is not blackboxed on the revised side, and
# the resolver stops the run rather than compare against a function-free model.
set DESIGN_LEC_NOTRANSLATE {rf_32k rf_16k rf_08k rf_01k
                            flash_cache_data flash_cache_tag
                            rom_via eth_rom_via}

# Physical-only cells - filler, endcap, well tap, antenna diodes, bond pads.
# They have layout and no logic, so LEC needs an empty module rather than a
# blackbox. Empty here because this design's physical-only cells all come from
# the tech pack's own lec_stub_cells, which the resolver reads directly.
set DESIGN_LEC_STUB_CELLS {}


#### 4. POWER AND GROUND NETS ##################################################
#
# Two supplies: 1.2 V core and 2.5 V IO. Four nets.
#
# VDDACC was dropped: zero occurrences in the netlist, so its "no problems"
# report was checking nothing at all. Re-add it if an analogue supply is ever
# instantiated.
# Source: ../genus-innovus/scripts/config.tcl:140-141
set power_nets  {VDD VDDIO}
set ground_nets {VSS VSSIO}

# ── WHERE THE POWER INTENT IS DECLARED, AND WHERE IT IS NOT ────────────────
#
# NOT HERE. The UPF is named by POWER_INTENT in design.mk, which the engine
# exports as ASIC_POWER_INTENT and flow/genus/1_synthesis.tcl:135 reads. That is
# the only route in.
#
# The toolkit's worked example sets `upf_file`, `cpf_file` and
# `cpf_patch_required` in this file instead. Those are this project's
# scripts/config.tcl spellings, carried across unconverted, and they have ZERO
# readers anywhere in flow/, mk/ or tech/. Setting them here does not connect
# power intent; it only looks as though it has. Synthesis then skips its power
# intent section and writes no CPF, place skips read_power_intent and
# commit_power_intent, no power domains exist, add_fillers inserts nothing, and
# a GDS streams with no filler and no antenna diodes. Nothing fails.
#
# If you find yourself adding a `upf_file` line to this file, the variable you
# want is POWER_INTENT in design.mk, and it is already set.


#### 5. BLOCK-SPECIFIC TOOL SETTINGS ###########################################

# No scan chain is bonded on this tapeout. TEST and SE are strapped and excluded
# from timing by set_case_analysis in inputs/constraints.sdc:402-403, which is
# the right instrument - turning DFT off here does not stop the timer walking
# the scan mux inside every SDF* flop.
# Source: ../genus-innovus/scripts/config.tcl:136
set DFT 0

# Auto-ungroup is left at the Genus default (on). Macro placement copes, because
# floorplan.tcl resolves macros by PATTERN rather than by hierarchical path.

# ── UNCAP THE MESSAGE LOG ──────────────────────────────────────────────────
#
# Innovus prints at most 20 instances of any message ID and then goes silent
# ("The default limit is 20 ... further output of that message will be
# disabled"); with no ID named, the change applies to ALL message IDs.
#
# WHY IT MATTERS HERE. A place stage on this design reported "57018 warning(s),
# 178 error(s)" in its session totals while the whole log carried 807 **WARN
# lines - under 1.5% of what the tool emitted was ever visible, and nineteen
# message IDs hit the cap. Triage on this design, including two findings that
# turned out to be tapeout-blocking, was done on a 20-instance sample.
#
# Cost: tens of MB of log against 6.7. Against a five-hour run that is nothing.
#
# Guarded on `info commands`, because this file is sourced by BOTH tools and
# set_message is Innovus-only; sourcing an Innovus-only command unguarded has
# broken the Genus run on this project before.
if {[llength [info commands set_message]]} {
    set_message -no_limit
}


################################################################################
# CLOCK-TREE CELL CHOICE: WITHDRAW THE PACK'S OPINION
#
# flow/steps/cts_setup.tcl documents its own rule exactly: buffers and inverters
# are "left unset unless the tech pack has an opinion", because constraining the
# choice changes the tree and therefore the hold profile, and that is "a physical
# change to evaluate on its own rather than bundle with a hold experiment".
#
# The tsmc65 pack HAS an opinion -- cts_buffer_pattern CKB*, cts_inverter_pattern
# CKN*, icg_cell_patterns {CKLHQ* CKLNQ* CKLD*} -- so on this design the step
# would apply all three. This design has evidence against that, and it is the
# reason ../genus-innovus/scripts/cts_setup.tcl:20,22 leaves the equivalent
# set_db lines COMMENTED OUT rather than merely unwritten:
#
#   The shipped tree uses 3,290 BUFFD1 in its clock tree. That is a
#   general-purpose buffer, and a CKB* list EXCLUDES it. Constraining the choice
#   would rebuild the tree out of different cells -- changing insertion delay,
#   skew, the hold profile, hold-buffer count and area -- and the only thing the
#   run would say about it is one `say` line. Silent, and physical.
#
# icg_cell_patterns is worse than merely unwanted. The pack ALSO declares
#   tech_set icg_dont_use {CKLHQD20 CKLHQD24 CKLNQD20 CKLNQD24}
# because the vendor marks those cells dont_use -- and CKLHQ*/CKLNQ* MATCH them.
# cts_setup's own message for the buffer case says setting these "OVERRIDES
# vendor dont_use", so applying the ICG pattern can readmit exactly the cells
# the pack is trying to keep out.
#
# Withdrawn HERE rather than by overriding the step, deliberately. An
# overrides/cts_setup.tcl would replace the step wholesale and lose the two
# gates it adds -- the OCV-before-ccopt ordering check, and the source-latency
# writeback census -- which are strictly good and which this design needs: a
# misordered run previously produced 96,545 fictional hold violations.
#
# This file is sourced during flow_boot AFTER the tech pack and long before
# `flow_step cts_setup` (3_cts.tcl:462), so the step simply sees tech_has ->
# false and does what it documents.
#
# TO SWEEP the cell choice deliberately, do NOT delete these: use the stage
# knobs the step names for exactly that purpose, CTS_BUF_CELLS / CTS_INV_CELLS.
################################################################################

foreach __k {cts_buffer_pattern cts_inverter_pattern icg_cell_patterns} {
    if {[tech_has $__k]} {
        tech_unset $__k
        puts "DESIGN-CFG: withdrew tech key '$__k' - CTS chooses its own cells\
              (see the note in [info script])"
    }
}
unset -nocomplain __k


################################################################################
# PROTECT THE PAD RING FROM SYNTHESIS
#
# The supply pads in ../tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:192-213
# are instantiated with EMPTY PORT LISTS:
#
#     PVDD2POC_G uPAD_VDDIO_T_0();
#     PVDD2DGZ_G uPAD_VDDIO_T_1();
#
# To synthesis they are unloaded, undriven and worthless, and Genus deletes
# every one of them. The SIGNAL pads have real connections and survive, so the
# netlist still looks like a padded design.
#
# MEASURED on this toolkit's first run against this chip, before this block
# existed: 82 pad instances in, 48 out. All 34 PVDD1DGZ_G / PVDD2DGZ_G /
# PVDD2POC_G / PVSS1DGZ_G / PVSS2DGZ_G gone -- every core and IO supply pad and
# every power-on-control cell. Confirmed three ways: absent from the synthesis
# netlist, absent from the routed netlist, absent from the GDS; a top-level area
# drop of 114,826 um2 against the 114,750 um2 those 34 pads occupy; and the IO
# filler ring growing by exactly 850 um = 34 x 25.0 um of vacated slots.
#
# The result routes, streams a 296 MiB GDS, and is not a shippable die. It would
# fail LVS. Nothing upstream of LVS notices: the bond-pad count gate checks
# PAD70*, which is unaffected.
#
# The production flow has protected against this since it was written --
# ../genus-innovus/scripts/1b_synthesis_eval.tcl:406-412 issues an
# unconditional set_dont_touch on uPAD* and FAILS if the pattern matches
# nothing. This is the same protection, in the toolkit's own idiom.
#
# uPAD* covers all 82: the supply pads above, the 48 signal drivers, and the
# corner cells. Deliberately broad -- a pattern that matches too much costs some
# optimisation on cells that must not be optimised anyway, while one that
# matches too little is invisible until LVS.
################################################################################

set ::DONT_TOUCH_PATTERNS {uPAD*}
