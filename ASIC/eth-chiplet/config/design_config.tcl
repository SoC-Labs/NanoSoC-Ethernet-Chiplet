################################################################################
# nanosoc-ethernet-chiplet / ASIC/eth-chiplet/config/design_config.tcl
#
# The DESIGN half of the tool setup for nanosoc_eth_chiplet_pads. The tech pack
# (tech/tsmc65) owns the standard cells, the IO library, the tech LEF, the cap
# tables, every layer and cell name, and the stream-out map. What is left here
# is the eight hard macros this design instantiates, its PG net names, and its
# DFT setting.
#
# ── WHY THIS FILE EXISTS AT ALL, WHEN ../genus-innovus/scripts/config.tcl DOES ──
#
# It is the ONE Tcl file this directory owns, and it is owned reluctantly. Every
# other file the manifest hands the tools is the live production file, pointed
# at, not copied. This one could not be: the production config.tcl cannot be
# sourced as DESIGN_CONFIG_TCL, for four reasons, each of them measured rather
# than suspected.
#
#   1. IT SOURCES TWO SIBLINGS BY RELATIVE PATH.
#      config.tcl:1-2 does `source ../scripts/procs.tcl` and
#      `source ../scripts/flow_utils.tcl`. Those are the PRODUCTION flow's own
#      helpers, and the toolkit has already loaded its own say/warn/die/opt/step
#      by the time flow_boot sources this file. Loading a second, differently
#      behaved set over the top of the engine's is not a path problem that a
#      symlink fixes; it is two engines in one interpreter.
#
#   2. IT REDEFINES THE RUN'S OUTPUT TREE.
#      config.tcl:129-131 sets LOG_DIR / REPORT_DIR / OUT_DIR to ../logs,
#      ../reports, ../outputs. flow_boot has already set all three from
#      ASIC_LOG_DIR / ASIC_REPORT_DIR / ASIC_OUT_DIR, and it sources this file
#      AFTERWARDS - so a run would write its reports outside its own run
#      directory, into whatever ../reports happens to be. Every artefact
#      assertion in mk/flow.mk would then fail on a run that had worked.
#
#   3. `set ::design_home` TRIPS THE COLLATERAL TYPO GUARD.
#      flow/common/flow_utils.tcl:675-689 treats ANY global matching `design_*`
#      (case-insensitively) that is not one of the nine contract names as an
#      error, because a misspelt collateral variable is silent and produces a
#      wrong netlist with every check green. `design_home` matches. The engine
#      would stop, correctly, on a variable that is not collateral at all.
#
#   4. IT DECLARES THE PROCESS, NOT JUST THE DESIGN.
#      config.tcl:85-225 names the TSMC standard-cell and IO liberty, the tech
#      LEF, the base LEF, the IO pad LEF and the DRC ruledeck. In the toolkit
#      those are the tech pack's, and the pack now DERIVES several of them from
#      the PDK at load time. Declaring them here would be a second, static copy
#      of values the pack reads live - the exact failure mode the pack was
#      rewritten to remove.
#
# So: the eight macros and the four PG nets are transcribed, and nothing else.
# The values below are checked against config.tcl:89-222 and against
# scripts/$(BLOCK).mmmc:5-69, which are the two places they exist today.
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
if {[info exists ::env(DESIGN_HOME)]} {
    set romlib_root $::env(DESIGN_HOME)
} elseif {[info exists ::env(NANOSOC_ETH_CHIPLET_HOME)]} {
    set romlib_root $::env(NANOSOC_ETH_CHIPLET_HOME)
} else {
    error "design_config: neither DESIGN_HOME nor NANOSOC_ETH_CHIPLET_HOME is set.\
         \n  Both are exported by ASIC/common.mk, which ASIC/eth-chiplet/design.mk\
         \n  includes. A stage started outside make needs one of them in the\
         \n  environment."
}
set bootrom_dir $romlib_root/ASIC/romlibs/cc_rom
set eth_rom_dir $romlib_root/ASIC/romlibs/eth_rom

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
# Innovus prints at most 20 instances of any message ID and then goes silent.
# Cadence's own set_message doc: "The default limit is 20, so any specific
# message will be written out 20 times and then further output of that message
# will be disabled", and "If you do not specify a message ID, the change is
# applied to ALL message IDs".
#
# WHY IT MATTERS ON THIS DESIGN. The 2026-08-06 run's session totals read
# "57018 warning(s), 178 error(s)" for the place stage alone, while the whole log
# contained 807 **WARN lines - under 1.5% of what the tool emitted was ever
# visible, and NINETEEN message IDs hit the cap. Every triage done on this
# design, including two findings that turned out to be tapeout-blocking, was
# performed on a 20-instance sample. At least one class (TCLCMD-1005) is capped
# in all six sessions of both runs with not one instance visible anywhere.
#
# Cost: a bigger log - tens of MB against 6.7. Against a five-hour run that is
# nothing, and it is the difference between triaging the design and triaging a
# sample of it.
#
# Guarded on `info commands`, because this file is sourced by BOTH tools and
# set_message is Innovus-only. Sourcing an Innovus-only command unguarded has
# broken the Genus run on this project before.
# Source: ../genus-innovus/scripts/config.tcl:57-59
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
