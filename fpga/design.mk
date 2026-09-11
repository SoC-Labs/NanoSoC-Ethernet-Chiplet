#-----------------------------------------------------------------------------
# nanosoc-ethernet-chiplet / fpga/design.mk  --  THE ONE FILE THE FLOW READS FIRST
#
# The eth chiplet (whole nanoSoC multicore SoC + ethernet MAC + internal
# TideLink + TideChart) built for one Kria KR260, as the nanoSoC FPGA Toolkit's
# contract describes it.  See fpga/README.md for what this is and what it is
# NOT yet.
#
# THIS MANIFEST POINTS AT THE EXISTING FLOW'S COLLATERAL. IT DOES NOT COPY IT.
# ---------------------------------------------------------------------------
# The three XDCs, the block-design Tcl and the board-level top still live in
# tidelink/fpga/targets/kr260-eth-chiplet/, which is where today's working
# build reads them from.  Every one of them is named by a VARIABLE below and
# not one of them has been copied here, because:
#
#   A COPY IS A SNAPSHOT THAT DRIFTS SILENTLY. A POINTER CANNOT.
#
# and the drift is not hypothetical in this repo - the timing XDC changed on
# 2026-08-21 and the pins XDC with it.  A second copy under fpga/ would have
# gone on building the 2026-08-10 constraints with every gate green, which is
# exactly the failure class the toolkit exists to remove.  Physically moving
# the collateral is a LATER and SEPARATE decision; when it is taken it is a
# `git mv` plus the deletion of the TARGET_DIR override in section 4.
#
# THE READING ORDER OF THIS FILE IS THE ORDER MAKE READS IT. A `:=` is expanded
# the moment make reaches the line, so anything it references must ALREADY be
# defined ABOVE it. Referencing something defined further down does not error --
# it expands to empty, and `$(MY_ROOT)/rtl/top.flist` quietly becomes
# `/rtl/top.flist`, an absolute path that looks plausible and does not exist.
# That is why PROJECT_ROOT is hoisted to section 1 here instead of sitting in
# section 3 where the template puts it: sections 2 and 4 both build paths from
# it.
#
# Scaffolded by `fpga-flow-init` on 2026-09-08 and filled in the same day.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------


# -- 1. REQUIRED: the three the engine will not start without ----------------

# BLOCK is the design's short name and the STEM OF EVERY ARTEFACT the flow
# writes: nanosoc_eth_chiplet.bit / .bin / _synth.dcp / _routed.dcp.
#
# BLOCK != TOP HERE, AND THAT IS DELIBERATE - the template asks that the reason
# be written down, so: BLOCK names THE DESIGN (the packaged
# nanosoc_eth_chiplet IP, which is the whole SoC and is what anyone means when
# they say "the eth chiplet"), while TOP names the BLOCK-DESIGN WRAPPER that
# bolts that IP to a KR260 - the PS8, the clk_wiz, the SmartConnect, the AHB
# bridge.  Naming the artefacts after the wrapper would file this design's
# bitstreams under a name that describes Xilinx IP glue.
BLOCK := nanosoc_eth_chiplet

# BOARD selects the board pack at $(BOARD_DIR)/board.tcl.
BOARD := kr260-eth-chiplet

# The toolkit checkout.  `fpga-flow-init` wrote an ABSOLUTE path here because
# the toolkit is not inside this project, and warned about it.  We use a
# relative one instead: every SoC Labs repo on this bench is a SIBLING under
# one parent directory, so ../../ is the layout that is actually true, and it
# survives the whole tree being moved, cloned, or checked out by CI under a
# different root.  `?=` so CI can point at a pinned checkout without editing.
#
# IT IS NOW A SUBMODULE (2026-09-09), at fpga/fpga-toolkit, pinned to a commit
# that resolves on github.com:SoC-Labs/nanoSoC-FPGA-Toolkit.git.  So the
# submodule is probed FIRST and the sibling clone remains as a fallback, which
# is the same shape ASIC/eth-chiplet/design.mk uses for the ASIC toolkit.
#
# PROBED ON mk/flow.mk, NOT ON THE DIRECTORY.  An uninitialised submodule is an
# EMPTY DIRECTORY that passes every `test -d`, so a directory test would select
# it, find no engine, and fail with a make syntax error instead of saying
# `git submodule update --init`.  This is the reference toolkit's own hard-won
# wording and it is repeated here because the failure is identical.
FPGA_TOOLKIT_SUBMODULE := $(FPGA_DIR)/fpga-toolkit
FPGA_TOOLKIT_SIBLING   := $(abspath $(FPGA_DIR)/../../nanoSoC-FPGA-Toolkit)
FPGA_FLOW_DIR ?= $(if $(wildcard $(FPGA_TOOLKIT_SUBMODULE)/mk/flow.mk),\
                     $(FPGA_TOOLKIT_SUBMODULE),$(FPGA_TOOLKIT_SIBLING))

# ---------------------------------------------------------------------------
# HOISTED FROM SECTION 3 - see the reading-order note in the header.
#
# PROJECT_ROOT is this repository's root.  The contract uses it for git
# provenance only, and that remains its ONLY use in the engine; here it is also
# the anchor for the two paths below, both of which are inputs the engine
# reads.  That is a project-side decision and it is safe: fpga/ is a directory
# OF this repo, so $(FPGA_DIR)/.. is this repo by construction, not a reach out
# of the project.  (CONTRACT §9.8 forbids the TOOLKIT reaching up out of the
# project.  It says nothing about a project addressing its own submodule, which
# is what the two lines below do.)
# ---------------------------------------------------------------------------
PROJECT_ROOT ?= $(abspath $(FPGA_DIR)/..)

# The existing, working FPGA flow: a 54k Makefile + build_design.tcl inside the
# tidelink submodule, which reaches UP into this repo for the SoC sources.
# Phase 2 reverses that direction.  Until it does, this is where the KR260
# eth-chiplet collateral lives and these two variables are how this manifest
# addresses it WITHOUT copying anything.
LEGACY_FPGA_DIR    := $(PROJECT_ROOT)/tidelink/fpga
LEGACY_TARGET_DIR  := $(LEGACY_FPGA_DIR)/targets/kr260-eth-chiplet


# -- 2. REQUIRED: reported by `make check`, not by make ----------------------

# THE BOARD-LEVEL TOP, NOT THE SoC TOP.  tidelink_design_wrapper is the
# generated wrapper around the tidelink_design block design; it instantiates
# the packaged nanosoc_eth_chiplet IP alongside the PS8, the clk_wiz, the
# SmartConnect and the AHB-Lite bridge, and it is the only module that has the
# KR260's pad_* ports on its boundary.  Naming nanosoc_eth_chiplet here would
# synthesise cleanly and silently unconstrain every pin in XDC_PINS.
TOP := tidelink_design_wrapper

# ===========================================================================
# WHAT RTL_FLIST IS FOR WHEN THE SoC ARRIVES AS A PACKAGED IP.  CORRECTED
# 2026-09-08, AND IT IS A MODELLING DECISION, NOT A PATH FIX.
#
# It used to name $(PROJECT_ROOT)/flist/nanosoc_eth_chiplet.flist - the SoC's
# own 596-source master list.  That is the right list for elaborating the SoC
# and the WRONG list for this build, because on this target the SoC does not
# arrive as RTL at all.  It arrives as the packaged IP
# soclabs.org:user:nanosoc_eth_chiplet_vivado_wrapper:1.0, instantiated by the
# block design and resolved through IP_REPOS.  Feeding both put every SoC
# module into one synthesis TWICE - once loose from the flist, once inside the
# IP - which is a redefinition Vivado resolves by its own rule and reports as a
# warning among hundreds.
#
# So RTL_FLIST now names what this flow actually COMPILES: the glue between
# that IP and the board.  One file - the /2 divider the block design
# instantiates by module reference.  With TOP_HDL that is exactly the legacy
# flow's fileset, measured on the shipping build's own project file:
#
#     $ grep -oE '<File Path="[^"]*"' tidelink_project.xpr | grep -cE '\.(v|sv|svh)$$'
#     2   tidelink_design_wrapper.v, tidelink_phy_clk_div2.v
#
# THE SoC FLIST HAS NOT BEEN DELETED AND IT HAS NOT LOST ITS JOB.  It is the
# input to the PACKAGING step - PACKAGE_TCL, stage 2 - which is what BUILDS the
# IP this design consumes, and which this project cannot yet run (see
# fpga/README.md, known hole 2, and PACKAGE_TCL in section 6).  It is kept
# below under its own name so that the day stage 2 is wired, the list it needs
# is already stated and already checked by `make check`.
#
# THE OPTION NOT TAKEN, and why: keeping the full flist and NOT consuming the
# prebuilt IP would make this flow self-sufficient - but it cannot, because
# nothing here can produce the IP, and the block design instantiates it by
# VLNV.  That is a phase-2 change and it is written down in the parity report,
# not attempted here.
# ===========================================================================
RTL_FLIST := $(FPGA_DIR)/targets/kr260-eth-chiplet/board_glue.flist

# The SoC's own master list.  NOT read by this flow today - see above.  It
# -f-includes two GENERATED lists, ${CHIPLET_SOC_VCS_FLIST} and
# ${CHIPLET_TL_VCS_FLIST} (exported in section 16 so the flist resolves without
# sourcing set_env.sh), plus ${TIDECHART_HOME}/flist/tidechart.flist.  See
# RTL_FLIST_GEN in section 5 for why regeneration is deliberately NOT wired.
SOC_IP_FLIST := $(PROJECT_ROOT)/flist/nanosoc_eth_chiplet.flist

# Pin and placement constraints - read in synthesis AND in implementation.
# The engine sets the read window from the variable that names the file, so
# nothing here sets USED_IN_*; that is the whole point of a role-specific
# variable.  Named EXPLICITLY, not globbed: the flow this replaces discovers
# constraints with `glob *_tidelink*.xdc`, so an XDC named anything else is
# invisible - present in the directory, read by nothing, warned about by
# nobody, and indistinguishable from a constraint that matched nothing.
XDC_PINS := $(LEGACY_TARGET_DIR)/kr260_eth_chiplet_tidelink.xdc

# THE DEVICE.  The board pack states this too, and they must agree.
#
# WHY IT IS STATED IN BOTH PLACES, given the template says to delete this line
# and let board.tcl be the single source: `make check` FAILS with PART empty.
# The board pack is Tcl, make cannot read it, and mk/flow.mk says so in as many
# words ("PART normally arrives from the board pack ... at this layer PART is
# frequently EMPTY, and that is not an error") - but fpga-flow-check treats an
# empty PART as a hard failure and never loads the pack to ask.  Reported to
# the toolkit; see fpga/README.md.  Until it is fixed this line is REQUIRED,
# and board.tcl's `part` key is what any Tcl-side consumer reads.
PART ?= xck26-sfvc784-2LV-c


# -- 3. IDENTITY -------------------------------------------------------------

# The block design's name.  It is the name of the .bd file and the stem of the
# generated wrapper, which is where TOP comes from: tidelink_design ->
# tidelink_design_wrapper.  It is NOT $(BLOCK): the BD predates the eth-chiplet
# packaging and every target in the legacy flow shares this one BD name.
DESIGN_NAME := tidelink_design

# PROJECT_ROOT is set in section 1 (hoisted).


# -- 4. TARGET: which board, which device, which flavour of build ------------

BOARD_DIR ?= $(FPGA_DIR)/board/$(BOARD)

# One board, one build, so TARGET is BOARD.  The legacy flow's sibling target
# `kr260-eth-chiplet-flip` (die_b: DEVICE_CLASS 2, role strap 1) is NOT
# described here - see fpga/README.md, "not yet migrated".  When it is, it is a
# second TARGET over the same BOARD, which is exactly the distinction TARGET
# exists to carry.
TARGET ?= $(BOARD)

# ===========================================================================
# TARGET_DIR IS REDIRECTED AT THE EXISTING COLLATERAL. THIS IS THE POINTER.
#
#   The default is $(FPGA_DIR)/targets/$(TARGET).  We override it because the
#   collateral is real, current and in daily use one directory away, and a
#   second copy of a 28 KB timing XDC is a second copy of a 28 KB timing XDC.
#
#   Redirecting the DIRECTORY rather than only the three XDC paths is the
#   stronger choice, and the reason is `make check`'s orphan-XDC gate: it walks
#   TARGET_DIR and ERRORS on any .xdc that no variable names.  Pointed here,
#   that gate covers the directory the constraints actually live in - so the
#   day somebody adds kr260_eth_chiplet_tidelink_extrefclk.xdc and forgets to
#   name it, check goes red.  Left at the default it would have walked an empty
#   project directory and reported "0 file(s), all named by a variable": a
#   green verdict that measured nothing.
#
#   fpga/targets/kr260-eth-chiplet/ still exists and holds a README saying
#   exactly this, so a reader who looks where the contract says to look finds
#   the answer instead of an absence.
# ===========================================================================
TARGET_DIR := $(LEGACY_TARGET_DIR)

# PART_DIR IS DELIBERATELY NOT SET HERE, although the template offers the line.
# The template's form is `PART_DIR ?= $(FPGA_FLOW_DIR)/part/$(PART)`, and with
# an empty PART that expands to $(FPGA_FLOW_DIR)/part/ - a directory that
# EXISTS, holds every pack, and is not one.  mk/flow.mk's own default is
# guarded against exactly that, so restating the unguarded form here would
# shadow the guard with the bug it was written for.  Point this elsewhere only
# for a site pack held outside the toolkit checkout.

# THE VENDOR BOARD FILE.  Zynq UltraScale+ targets drive the PS8/DDR/MIO
# configuration from this preset, and the BD must be sourced with it already
# set on the project.  The board pack states it as well (board_part), together
# with the board_repo_paths it makes mandatory.
BOARD_PART ?= xilinx.com:kr260_som:part0:1.1

# BOARD_REPO_PATHS IS DELIBERATELY EMPTY HERE AND DEFERRED IN THE BOARD PACK.
#
# MEASURED 2026-09-08: the Kria board files are NOT INSTALLED ON THIS HOST.
# Neither Vivado 2021.1 nor 2024.1 carries data/boards/board_files at all, and
# the user's xhub board_store holds TUL/pynq-z2 and nothing else.  So the
# legacy flow's own guard - "FPGA_BOARD_PART not found in this Vivado's board
# catalog ... exit 1" - is what a KR260 build would hit here today, and the
# working KR260 bitstreams in tidelink/imp/ were produced somewhere the files
# were present.  Writing a path here would be a guess.  board.tcl resolves it
# through `board_env KRIA_BOARD_FILES`, which RECORDS the resolution attempt
# whether or not it succeeds, so the absence is reported rather than silent.
BOARD_REPO_PATHS ?=

# ===========================================================================
# `direct`, NOT `project`.  CORRECTED 2026-09-08, AND IT IS A CORRECTION TO
# WHAT THIS MANIFEST CLAIMED, NOT TO WHAT THE BUILD DOES.
#
# This said `project`, on the reasoning that the legacy flow builds a .xpr the
# GUI can open and that the pre_synth hook needs a fileset.  Both halves were
# wrong about this toolkit:
#
#   * flow/vivado/4_synth.tcl says in its own header, "It does not implement
#     FLOW_MODE=project's `launch_runs synth_1` path."  Every mode runs the same
#     in-memory synthesis.  Declaring `project` did not select a project flow;
#     it selected a NOT-COVERED bullet in the synth gate saying the declaration
#     had been ignored.  (That the toolkit accepts a mode it does not implement
#     is a TOOLKIT defect and is item 4 of the parity report; it is not fixed
#     by this manifest and is not hidden by it either.)
#
#   * the fileset exists in `direct` too.  4_synth.tcl now opens an in-memory
#     project before it reads anything (it has to: an IP resolves against the
#     part that is set when it is READ), and an in-memory project has a
#     sources_1 fileset with GENERIC and VERILOG_DEFINE on it.  The hook read it
#     happily in the run that measured this.
#
# The bd stage DOES build a real .xpr - work/bd_project - and that is the one
# the GUI opens.  It is a fact about stage 3, not about FLOW_MODE.
# ===========================================================================
FLOW_MODE ?= direct

# A bitstream plus the firmware built into it.  NOT `pynq`: the KR260 runs
# Ubuntu with fpgautil, not a PYNQ overlay image, and the .hwh this flow emits
# is consumed by the host-side test scripts rather than by an overlay loader.
PLATFORM ?= bare

# ===========================================================================
# THE SYSTEM CLOCK - 25 MHz, AND IT IS NOT pl_clk0.
#
#   PS8 pl_clk0 runs at 100 MHz nominal (99.999 MHz measured on the pin; the
#   BD reads it back and re-states clk_wiz PRIM_IN_FREQ from it to dodge BD
#   41-238).  clk_wiz_0 divides it to 25 MHz on clk_out1, and clk_out1 is
#   sys_fclk - the clock the SoC, the AHB fabric and the PHC all run on.  It is
#   also the clock the forwarded PHY output is derived from, `-divide_by 8`.
#
#   So 25000000 is the number that is compiled into the firmware and that
#   constrains the fabric.  100000000 is the oscillator-side number and lives
#   in the board pack.  Recording pl_clk0 here would leave every baud rate and
#   every timer wrong by a factor of four while the board booted normally.
# ===========================================================================
SYS_CLK_FREQ_HZ ?= 25000000


# -- 5. RTL ------------------------------------------------------------------

# DELIBERATELY EMPTY, AND THIS IS NOT AN OVERSIGHT.
#
# The two generated lists RTL_FLIST -f-includes are produced by
# `make -C $(PROJECT_ROOT) elab`, which flattens the SoC flist and resolves the
# TideLink flist to one definition per module - and then ALSO runs a full VCS
# elaboration.  Wiring that target here would make `make flist`, a stage that
# needs no licence at all, take a VCS licence and several minutes every time.
#
# The honest state is: the flist HAS a generator, the generator is not
# separable from a simulator run today, and until it is, the two .f files are
# treated as inputs whose freshness is the caller's problem.
#
# THIS PARAGRAPH USED TO CLAIM "`make check` reports their absence via the flist
# scan rather than pretending otherwise". THAT WAS FALSE, and it was false in
# the worst direction: it named a check that does not happen, which is the one
# reason someone would trust the check to catch it. RTL_FLIST for this target is
# board_glue.flist - ONE line, no `-f` includes at all - so there is nothing for
# the flist scan to follow and `make flist` succeeds whether or not those two
# .f files have ever existed. Found 2026-09-10 by a clean-checkout run that
# reached synthesis without them.
#
# They are not needed by THIS target. The SoC arrives through IP_REPOS as
# packaged IP, not through the flist. If a future target reads them directly
# then the -f-include walk in `make check` WILL report them missing - that
# machinery is real - but nothing in this manifest exercises it today.
RTL_FLIST_GEN ?=

# The flist carries its own +incdir+ for src/rtl.  Nothing extra is needed.
RTL_INCDIRS ?=

# ===========================================================================
# WHY THERE IS NOTHING IN RTL_DEFINES.
#
#   `ipx::package_project` DROPS FILESET DEFINES, by three separate routes,
#   none of which warn.  In THIS codebase that failure was measured: a
#   `ifdef TIDELINK_USE_IDELAY opt-in was false in every FPGA build, proven by
#   an "IDELAY-off" bitstream coming out BYTE-IDENTICAL to the "IDELAY-on" one.
#   This design is packaged as an IP (the whole SoC is one
#   nanosoc_eth_chiplet_vivado_wrapper core), so a plain +define+ here would
#   reach nothing.
#
#   Every define that reaches the PACKAGED IP is therefore INBODY, and that is
#   not a toolkit convention - it is what the existing flow already does:
#   tidelink/fpga/vivado_ip/nanosoc_eth_chiplet_filelist.tcl writes materialised
#   copies of the affected sources with the `define prepended into the file.
#
#   TIDELINK_PHY_V2 IS DIFFERENT, AND IT LIVES HERE.  CORRECTED 2026-09-08.
#
#   It was declared in RTL_DEFINES_INBODY, and RTL_DEFINES_INBODY is delivered
#   by exactly one stage - 2_package_ip.tcl, "THE MATERIALISER".  PACKAGE_TCL is
#   empty on this project, so that stage does not run, so the define was
#   DECLARED AND NEVER DELIVERED.  flow/vivado/1_flist.tcl says so in as many
#   words: "RTL_DEFINES_INBODY NEVER REACHES synth_setup's LIST AT ALL."  The
#   run's own artefact agreed - reports/rtl_assert_pre_synth.txt recorded
#   `declared_rtl_defines (none)`.
#
#   RTL_DEFINES is the honest home for it while stage 2 is unconfigured, AND it
#   is the mechanism that matches the legacy flow exactly.  Measured, from the
#   shipping build's own log:
#
#     build_design.log:814  verilog_define injected into run synth_1 :
#                           -verilog_define TIDELINK_PHY_V2
#     build_design.log:852  Command: synth_design -top tidelink_design_wrapper
#                           -part xck26-sfvc784-2LV-c -verilog_define TIDELINK_PHY_V2
#
#   RTL_DEFINES reaches flow/steps/synth_setup.tcl and lands on the same
#   synth_design command line.  Its SCOPE matches too: with BD_GLOBAL_SYNTH=1
#   there is no out-of-context IP run to miss, so the whole block design -
#   including the packaged IP's copies of nanosoc_eth_chiplet.sv and
#   tidelink_apb_regs.sv, the two files the IP packaging does NOT materialise -
#   is compiled in the one pass that carries the define.  That is the same set
#   of files the legacy synth_1 compiles it into.
# ===========================================================================
RTL_DEFINES ?= TIDELINK_PHY_V2

# ===========================================================================
# EMPTY, AND THAT IS A CORRECTION MADE 2026-09-08.
#
# It named TIDELINK_PHY_V2, TD_AUTO_LANE_MASK_E4 and RAM_PRELOAD.  Nothing
# delivered any of them: RTL_DEFINES_INBODY is materialised by stage 2
# (2_package_ip.tcl) and PACKAGE_TCL is empty here, so all three were declared
# and never applied.  A variable whose entries reach nothing is worse than an
# empty one - it reads as cover.
#
# WHERE THE THREE ACTUALLY COME FROM TODAY:
#
#   TIDELINK_PHY_V2        moved to RTL_DEFINES, above.  It has to reach the
#                          two sources the IP packaging does not materialise,
#                          and the synth_design command line is the mechanism
#                          the legacy flow uses for exactly that.
#   TD_AUTO_LANE_MASK_E4   already baked in-body into the PACKAGED IP, by
#                          tidelink/fpga/vivado_ip/nanosoc_eth_chiplet_filelist.tcl:164,
#                          which prepends it to every materialised v2shim.  This
#                          flow consumes that prebuilt IP, so the define is
#                          already inside the sources it reads.
#   RAM_PRELOAD            same file, line 221: baked into a standalone copy of
#                          sl_ahb_rom so CPU0's IMEM image is $readmemh'd in.
#
# The day PACKAGE_TCL is wired and this flow builds its own IP, the last two
# come back here and this comment is the record of why.
# ===========================================================================
RTL_DEFINES_INBODY ?=

# ASSERTED ABSENT.  ASIC_TSMC65 is real and it is reachable: it guards the body
# of tidelink/deps/axi-chiplet-controller/logical/wlink/WavDemetReset_*.v, where
# it swaps the generic reset synchroniser for a foundry-cell one.  On an FPGA
# that is a black box in the netlist, not an error message.
RTL_DEFINES_NEVER ?= ASIC_TSMC65

# ===========================================================================
# PARAMETERS, WHICH ARE WHAT SURVIVES PACKAGING.
#
#   Both of these are parameters of nanosoc_eth_chiplet_vivado_wrapper (the
#   packaged IP's top module, lines 43 and 46) and both therefore survive
#   ipx::package_project as CONFIG.* properties.  The BD sets DEVICE_CLASS on
#   the instance as well; the pre_synth hook in section 9 asserts the instance
#   value, which is the form that actually reaches synthesis.
#
#     NUM_PHY_LANES  8       the TideLink GPIO-PHY lane count, and with it the
#                            width of the pad_* boundary the XDC pins.
#     DEVICE_CLASS   1       TideChart grandmaster-election priority, LOWER
#                            WINS.  die_a is 1, die_b is 2.  EQUAL VALUES ON
#                            BOTH DIES LEAVE THE ELECTION WITHOUT A TIEBREAK
#                            AND BOTH DIES CAN SETTLE AS ROOT - observed on
#                            silicon, and it is the reason the parameter was
#                            exposed on the wrapper at all (2026-07-29).
#
# TWO VALUES FROM THE ACCEPTANCE LIST ARE NOT HERE, ON PURPOSE.  CLKGATE_PRESENT
# and TXGEN_PRESENT are NOT parameters of this top module - CLKGATE_PRESENT is a
# parameter of slcorem0 deep inside the SoC (default 0) and TXGEN_PRESENT is a
# parameter of tidelink_top (default 1'b1, 1'b0 only in the ASIC DFT wrapper).
# Listing them here would emit a generic override for a parameter the top module
# does not declare: Vivado accepts that silently and applies it to nothing,
# which is a row that looks like coverage and is not.  They are recorded here as
# OBSERVED DEFAULTS and nothing more.
# ===========================================================================
# ===========================================================================
# EMPTY.  CORRECTED 2026-09-08, AND THE PARAGRAPH ABOVE IS ITS OWN DIAGNOSIS.
#
# It said "Listing them here would emit a generic override for a parameter the
# top module does not declare: Vivado accepts that silently and applies it to
# nothing, which is a row that looks like coverage and is not."  That is
# precisely what NUM_PHY_LANES and DEVICE_CLASS were doing.
#
# RTL_PARAMS lands on `synth_design -generic`, which applies to THE TOP MODULE
# OF THE SYNTHESIS.  TOP here is tidelink_design_wrapper, the hand-written
# board-level top, and it declares NO PARAMETERS AT ALL:
#
#     $ grep -n parameter tidelink/fpga/targets/kr260-eth-chiplet/tidelink_design_wrapper.v
#     (no output)
#
# The two parameters are on nanosoc_eth_chiplet_vivado_wrapper, which is two
# levels down INSIDE the packaged IP.  A generic cannot reach it from here.
#
# HOW THEY ACTUALLY REACH THE DESIGN, and it is the same way in both flows:
#
#   DEVICE_CLASS   set on the BD CELL, by the block design itself -
#                  tidelink/fpga/targets/kr260-eth-chiplet/tidelink_design.tcl:155
#                  `set_property CONFIG.DEVICE_CLASS {1} $soc`.  That is a
#                  CONFIG.* property on an IP instance, which is the form that
#                  survives ipx::package_project.  fpga/hooks/post_bd.tcl
#                  asserts it, at the one seam where the block design is open
#                  and the question can be asked.
#   NUM_PHY_LANES  the packaged IP's own default.  Nothing overrides it in
#                  either flow, and the legacy build passes no -generic at all.
#
# So this is empty for parity AND for honesty: the legacy synth_design command
# line carries no generic, and neither does this one.
# ===========================================================================
RTL_PARAMS ?=

# The board-level top, read AFTER the flist.  It is target collateral and is
# deliberately not in the flist, which describes the SoC.
TOP_HDL ?= $(LEGACY_TARGET_DIR)/tidelink_design_wrapper.v

# EMPTY - THE DIVIDER MOVED INTO RTL_FLIST.  CORRECTED 2026-09-08.
#
# The /2 divider that makes the PHY link/pad clock is instantiated by the block
# design as a bare module (`create_bd_cell -type module -reference
# tidelink_phy_clk_div2`), and a module reference resolves only against a file
# ALREADY IN sources_1 when the BD is built - which is stage 3.
#
# EXTRA_SRCS is read in stage 4 (flow/vivado/4_synth.tcl), one stage too late,
# and FLIST_TOP_IN_SOURCES defaults to 0 so it does not reach the flist either.
# So the divider was named by a variable no stage read at the moment it was
# needed, and the block design would have built it as a black box.
#
# RTL_FLIST is the variable the bd stage DOES read (BD_READ_SOURCES=1 sources
# work/sources.tcl into the BD's project), so the divider is named there - see
# section 2 and fpga/targets/kr260-eth-chiplet/board_glue.flist.  Naming it in
# both would read the same file twice and elaborate as a duplicate module.
EXTRA_SRCS ?=

# Vivado decides file type by EXTENSION.  The integration RTL is .sv and the
# flist names it as such, so nothing needs forcing here.
SV_FILES ?=


# -- 6. IP AND BLOCK DESIGN --------------------------------------------------

# THE OUTPUTS OF PACKAGING STEPS, NOT COMMITTED TREES.  Both directories are
# written by the legacy flow's package_eth_chiplet_ip / package_phc_ip targets
# under tidelink/imp/ (gitignored), which is why they are stated as paths built
# from LEGACY_IMP_DIR rather than named individually.
#
# The toolkit models this as ONE LIST where the legacy flow has two scalars
# (FPGA_IP_REPO + FPGA_PHC_IP_REPO); the list is the better shape and the two
# scalars fold into it without loss.
LEGACY_IMP_DIR := $(PROJECT_ROOT)/tidelink/imp/fpga
IP_REPOS ?= $(LEGACY_IMP_DIR)/eth_chiplet_ip $(LEGACY_IMP_DIR)/phc_ip

IP_VENDOR   ?= soclabs.org
IP_CORE_REV ?= 1

# Under BUILD_DIR so a clean is a clean.  The legacy flow suffixes its cache
# path per build variant because Vivado keys config_ip_cache on IP config +
# part + tool and NOT on the synth run's -verilog_define, so two variants whose
# packaged sources are byte-identical collide in one cache and the second one
# silently links the first one's OOC netlist.  Under the toolkit that
# separation comes free: RUN_TAG is already in the path.
IP_CACHE_DIR ?= $(BUILD_DIR)/ip_cache

# NOT SET.  The legacy packaging scripts
# (tidelink/fpga/vivado_ip/package_eth_chiplet_ip.tcl and its filelist) are
# written against the legacy Makefile's environment - FPGA_COMPONENT_FILELIST,
# FPGA_COMPONENT_LIB, NANOSOC_ETH_CHIPLET_DIR - not against this contract's.
# Pointing PACKAGE_TCL at one of them would name a script that cannot run in
# this flow.  Porting them is phase 2.  See fpga/README.md.
PACKAGE_TCL ?=

# ===========================================================================
# BD_TCL MUST NAME SOMETHING THAT CREATES THE BLOCK DESIGN.  CORRECTED
# 2026-09-08.
#
# It named tidelink/fpga/targets/kr260-eth-chiplet/tidelink_design.tcl, which
# does not.  That file is a LIBRARY: its only top-level construct is
# `proc create_root_design { parentCell }`, it contains no create_bd_design, and
# sourcing it defines a proc and builds nothing.  BD_TCL's contract is "sourcing
# this creates the block design" (CONTRACT.md section 3.3), and the bd stage
# asserted exactly that and failed:
#
#     HARD FAILURES: 1
#       - BD_TCL ran and NO block design exists afterwards.
#
# The legacy flow supplies the missing calls from its own driver
# (tidelink/fpga/build_design.tcl:347-349).  fpga/targets/kr260-eth-chiplet/
# bd_create.tcl is that driver, in the project, at the seam the contract names.
# It sources the library unchanged from its legacy location - nothing is copied,
# so the two flows keep building the same block design from the same file.
# ===========================================================================
BD_TCL ?= $(FPGA_DIR)/targets/kr260-eth-chiplet/bd_create.tcl

BD_OVERLAY_TCL ?=

# ===========================================================================
# BD_WRAPPER=0 - THIS DESIGN HAS A HAND-WRITTEN BOARD TOP AND THE NAMES COLLIDE.
#
# The toolkit's default (BD_WRAPPER=1) calls `make_wrapper -top -force -import`,
# which produces a module named <DESIGN_NAME>_wrapper = tidelink_design_wrapper
# - THE SAME NAME as TOP_HDL, the hand-written board top.  The two are not
# interchangeable: the hand-written one carries the SWDIO and MDIO IOBUFs, so
# its boundary has MDIO and SWDIO as INOUT ports, and the generated one would
# expose six unidirectional ports instead.  The pin XDC constrains the INOUT
# spelling; against the generated wrapper it would match nothing, and Vivado
# drops a constraint that matches nothing without an error.
#
# The legacy flow has the same collision and resolves it by reading the
# hand-written file explicitly (build_design.log:971 shows synthesis picking the
# 5,055-byte hand-written top).  Not generating the file at all is the stronger
# form of the same answer: in this flow's checkpoint synthesis both would be
# read, and two modules of one name is a duplicate definition rather than a
# priority question.
#
# It is a TOOLKIT KNOB (`opt BD_WRAPPER` in flow/vivado/3_bd.tcl), so it is
# exported by bare name, per CONTRACT.md section 6.1.2 - a knob set by an
# environment variable nobody recorded produces a result nobody can reproduce.
# `opt` registers it, so the resolved value lands in the bd manifest.
# ===========================================================================
export BD_WRAPPER ?= 0

# 1 - synthesise the BD as one unit.  This is NOT a turnaround preference: the
# legacy flow forces it for every kr260-eth-chiplet% target because the design
# IS one packaged IP containing the whole SoC, so per-IP out-of-context
# synthesis buys nothing and costs the whole-design optimisation across the
# wrapper boundary.
BD_GLOBAL_SYNTH ?= 1


# -- 7. CONSTRAINTS ----------------------------------------------------------
#
# All three files are named explicitly, all three live in TARGET_DIR (which
# section 4 redirected), and the engine sets the read window from the variable
# that names each one.  `make check`'s orphan gate then covers that directory.

# XDC_PINS is in section 2 with the other required inputs.

# Clocks, IO delays and exceptions.  Implementation only.  28 KB and by far the
# most volatile of the three - it was last rewritten 2026-08-21.
XDC_TIMING ?= $(LEGACY_TARGET_DIR)/kr260_eth_chiplet_tidelink_timing.xdc

# XDC_CLOCKS - the clock definitions for SYNTHESIS, GENERATED from XDC_TIMING.
# The VALUE is declared here; the RULE that builds it lives in generate.mk,
# which the Makefile includes AFTER mk/flow.mk. It has to: a rule's target is
# expanded when the rule is parsed, and BUILD_DIR is an engine variable that
# does not exist until flow.mk has been read. See generate.mk for the argument.
XDC_CLOCKS_GEN = $(BUILD_DIR)/gen/kr260_eth_chiplet_clocks.xdc
XDC_CLOCKS    ?= $(XDC_CLOCKS_GEN)

# DRC severities and the ALLOW_COMBINATORIAL_LOOPS waiver for the XHB500
# HREADY loopback.  Implementation only.
XDC_DRC ?= $(LEGACY_TARGET_DIR)/kr260_eth_chiplet_tidelink_drc.xdc

XDC_EXTRA ?=

# NOT USED ON THIS TARGET, and the reason is a fact about the DEVICE, not a
# preference: the KR260's ribbon lands in HDIO bank 44, and banks 43/44/45 on
# xck26 are BT_HIGH_DENSITY.  HD banks carry NO IDELAY - the input-delay
# resource on this device lives in the HP banks' RXTX_BITSLICE.  So
# FPGA_USE_IDELAY is 0 here (section 16), no *_idelay.xdc exists in TARGET_DIR,
# and naming one in XDC_OPTIONAL would name a file that does not exist.
XDC_OPTIONAL ?=

# Nothing is sourced after route_design.  The one procedural thing this design
# needs - the combinational-loop waiver - is a set_property and lives in
# XDC_DRC, which is a legal XDC.
XDC_POST_ROUTE ?=


# -- 8. FIRMWARE -------------------------------------------------------------
#
# NOT WIRED, AND THE GAP IS REAL.  CPU0's IMEM image reaches this design
# through the RAM_PRELOAD in-body define plus the ETH_IMEM_IMG parameter's
# default (`NANOSOC_ETH_IMEM_IMG, "image.hex"), resolved by $readmemh relative
# to the Vivado run directory - not through any variable the legacy flow
# exports.  Declaring FW_HEX / FPGA_IMAGE_HEX here without also making the flow
# resolve them would be a path nothing reads.
#
# The consequence is stated rather than hidden: THIS MANIFEST DOES NOT TRACK
# THE FIRMWARE AS AN INPUT, so a rebuilt hex and an unchanged bitstream are not
# distinguishable from here.  Closing it is a phase-2 item.
FW_APP ?=
FW_HEX ?=
FW_HEX_FORMAT ?= word
FPGA_IMAGE_HEX ?=


# -- 9. EXTENSION POINTS -----------------------------------------------------

HOOKS_DIR     ?= $(FPGA_DIR)/hooks
OVERRIDES_DIR ?= $(FPGA_DIR)/overrides

# ===========================================================================
# THE DECLARATION TABLES.  ONE PER SEAM, SPLIT 2026-09-08.
#
#   Both hooks refuse until a table exists, which is correct: a shipped check
#   with nothing declared must not pass quietly.  Both rows below are measured
#   defects in this design rather than plausible-looking coverage.
#
#   WHY THERE ARE TWO TABLES NOW.  There was one, holding both rows, and it was
#   read only at pre_synth - where the DEVICE_CLASS row CANNOT BE ANSWERED.
#   Measured: in this toolkit's checkpoint synthesis `get_ips` returns nothing
#   at that seam, because the block design's IP objects belong to the project
#   the bd stage built and the synthesis session only read the design back out
#   of it.  The row refused as `ip 'nanosoc_eth_chiplet_0' ... is not in this
#   project`, and refused identically when it was "corrected" to the
#   fully-qualified tidelink_design_nanosoc_eth_chiplet_0_0.  The name was never
#   the problem.  The seam was.
#
#   ROW 1 - DEVICE_CLASS on the BD cell, at post_bd.  This is the strong form of
#   the assertion: `ip` reads CONFIG.<name> on the object, which is the
#   mechanism that SURVIVES ipx::package_project, rather than a fileset property
#   that does not.  It is a BD CELL, not a Vivado IP instance: the value is set
#   by the block design itself (tidelink_design.tcl:155,
#   `set_property CONFIG.DEVICE_CLASS {1} $soc`), so post_bd - where that cell
#   exists and the hook fires before save_bd_design - is where it is real.  The
#   failure it catches was observed on silicon: two dies carrying the same class
#   leave the TideChart grandmaster election with no tiebreak and BOTH settle as
#   root, and nothing in the build reports it.
#
#   ROW 2 - ASIC_TSMC65 absent, at pre_synth.  The enforcement half of
#   RTL_DEFINES_NEVER in section 5.  `expect absent` is the polarity that
#   matters: an ASIC-only macro reaching an FPGA build swaps a reset
#   synchroniser for a foundry cell the fabric does not have, and the result is
#   a black box in the netlist.
#
#   TIDELINK_PHY_V2 IS NOT A ROW, AND IT COULD BE.  Measured 2026-09-08: the
#   flist stage folds RTL_DEFINES into ::flist_defines, work/sources.tcl sets
#   them on the fileset, and flow/steps/synth_setup.tcl ALSO puts them on the
#   synth_design command line - so the hook sees `VERILOG_DEFINE =
#   TIDELINK_PHY_V2` at both seams and a `present` row would pass.  It is left
#   out until the first green bitstream, for the same reason NUM_PHY_LANES is:
#   the point of a row is to catch a REGRESSION against a build that is known
#   good, and there is not one under this flow yet.
#
#   NOT DECLARED, deliberately: NUM_PHY_LANES.  It is a real parameter of the
#   packaged IP's top module, but nothing in either flow overrides it - it takes
#   the IP's own default - and the value that reaches the instance has not been
#   read off a real run.  A row asserting a number nobody measured is the
#   "budget set to the day's number" pattern this project already has a class
#   of.  Add it after the first green synth, with the measurement beside it.
# ===========================================================================
#   THE SPELLING OF ROW 1'S VALUE IS MEASURED, NOT GUESSED, AND IT IS NOT "1".
#   Read off this design at post_bd on 2026-09-08, run tag bd-fix:
#
#       BD:   ip 'nanosoc_eth_chiplet_0' resolved to the block-design IP object
#             'tidelink_design_nanosoc_eth_chiplet_0_0'
#       BD:   param DEVICE_CLASS  = '0000000000000001'
#
#   The block design sets it as `{1}`; the IP declares the parameter as a
#   16-bit vector, so Vivado STORES it as a 16-bit binary string and hands that
#   back.  The hook compares strings as written and does not normalise them -
#   deliberately, because 1, 1'b1 and 16'd1 are three different strings and a
#   comparison that guessed between them would pass on a value it had not
#   actually read.  So the row carries the spelling the tool holds, and this
#   comment carries the number a human means.  A future change that made the
#   parameter a plain integer would fail this row, which is correct: the value
#   would then be reaching the instance by a different route.
export RTL_ASSERT_TABLE_POST_BD := \
    {name DEVICE_CLASS kind param value 0000000000000001 ip nanosoc_eth_chiplet_0 \
     why "TideChart grandmaster election, lower wins. die_a=1 (0000000000000001), \
          die_b=2. Equal on both dies leaves the election without a tiebreak and \
          both dies settle as root - observed on silicon, reported by nothing."}

export RTL_ASSERT_TABLE := \
    {name ASIC_TSMC65 kind define expect absent \
     why "Guards the body of WavDemetReset_*.v and swaps the generic reset \
          synchroniser for a TSMC65 cell. On the fabric that is a black box in \
          the netlist, not an error."}

# UTIL_ASSERT_TABLE is NOT declared, and hooks/post_impl.tcl has been DELETED
# rather than left to refuse on every run.  See fpga/README.md: no
# per-primitive count for this design has been measured under this flow, and
# the template's own three honest ways out are declare / move / delete.


# -- 10. RUN NAMESPACE -------------------------------------------------------

BUILD_DIR ?= $(FPGA_DIR)/build
RUN_TAG   ?= default
IN_RUN_TAG    ?= $(RUN_TAG)
SYNTH_RUN_TAG ?= $(RUN_TAG)

# The seven derived variables (RUN_DIR WORK_DIR LOG_DIR REPORT_DIR OUT_DIR
# IN_WORK_DIR SYNTH_OUT_DIR) are NOT assigned here.  The engine computes them
# with `:=` after this file is read, so anything set here is computed over and
# discarded silently.


# -- 11. TOOLS ---------------------------------------------------------------

VIVADO ?= vivado

# NOT ASSERTED YET.  `make doctor` reports what is on this host's filesystem:
# 2021.1 and 2024.1 under /apps/Xilinx/Vivado, 2025.2 and 2026.1 under
# /research/CAD/Xilinx/Vivado.  The legacy KR260 builds were made under 2024.1
# and its DRC behaviour is referenced by name in the DRC XDC's comments, so
# 2024.1 is the version to pin - on the day there is a build from this flow
# worth reproducing.  Pinning it before then would refuse runs for a version
# nobody has yet shown produces the right answer.
VIVADO_VER ?=

# 8, matching the legacy flow.  Measured, not guessed: it was raised 4 -> 8 on
# 2026-06-21 so the ~4-5 minute OOC sub-IP synth runs overlap fully on a
# 16-core host, and it was QoR-neutral.  Lower it on a smaller farm host.
NUM_JOBS ?= 8

TCLSH ?= tclsh


# -- 12. GATES ---------------------------------------------------------------
#
# EVERY EXPECT_* IS LEFT AT -1: MEASURE AND REPORT, DO NOT GATE.
#
# That is not laziness, it is the only defensible state: THIS FLOW HAS NEVER
# RUN.  The numbers that exist - the legacy flow's farm_gate_sv_baseline.txt
# and its WNS history - were produced by a different flow with a different
# constraint read window, and copying them here would create budgets that pass
# whatever this flow first produces and discriminate nothing.  This repo
# already has a class of exactly that.  Set each one after the first run, with
# the measurement, the date, the run tag and the margin written beside it.
EXPECT_WNS_MIN  ?= -1
EXPECT_WHS_MIN  ?= -1
EXPECT_LUT_MAX  ?= -1
EXPECT_FF_MAX   ?= -1
EXPECT_BRAM_MAX ?= -1
EXPECT_DSP_MAX  ?= -1

# These two stay at 0.  There is no design for which the right answer is "some
# unrouted nets" or "some black boxes".
EXPECT_UNROUTED_MAX ?= 0
EXPECT_BLACKBOX_MAX ?= 0

# 0.  The legacy build_design.tcl reads FPGA_ALLOW_CRITICAL_WARNINGS and the
# legacy flow does not set it either, so this is the behaviour that is already
# in force - written down for the first time rather than changed.
ALLOW_CRITICAL_WARNINGS ?= 0

# NOT SET.  `make xdc-lint` compares what each constraint file matched against
# a committed baseline, and there is no baseline for this flow because this
# flow has not run.  tidelink/fpga/farm_gate_xdc_baseline.txt is NOT it: it is
# the legacy farm gate's format, produced by a different reader, and naming it
# here would point a comparison at a file it cannot parse.  Generate one from
# the first run.
XDC_BASELINE ?=

# ===========================================================================
# THE IMPLEMENTATION RECIPE, WRITTEN DOWN FOR THE FIRST TIME. 2026-09-08.
#
# These four knobs are toolkit knobs (flow/steps/impl_setup.tcl), exported by
# bare name per CONTRACT §6.1.2, and `opt` registers each one so the resolved
# value lands in the impl manifest.
#
# THEY EXIST BECAUSE THE SHIPPING BUILD'S RECIPE WAS NEVER IN A MANIFEST.  It
# lived in tidelink/fpga/build_design.tcl as run properties on impl_1, and the
# first run of this flow used the toolkit's defaults instead - which are not the
# same recipe.  Both command lines, read out of the two logs:
#
#   step             LEGACY (the shipping bitstream)     TOOLKIT DEFAULT
#   opt_design       opt_design                          -directive Explore
#   place_design     place_design                        -directive Default
#   phys_opt_design  -directive AggressiveExplore        -directive Default
#   route_design     route_design                        -directive Default -tns_cleanup
#   phys_opt (post)  -directive AggressiveExplore        NOT RUN
#
#   legacy: imp/fpga/run/kr260-eth-chiplet/build_design.log:4628,4845,5177,5276,5573
#   new   : fpga/build/bd-fix/logs/impl.log:3195,3360,3677,3698
#
# THE CONSEQUENCE WAS MEASURED, NOT ASSUMED.  With the toolkit defaults the two
# flows' POST-SYNTHESIS netlists were IDENTICAL - LUT 60,756 and FF 54,451 on
# both - and the ROUTED ones were not: 131,071 primitives against 131,005, LUT
# 59,575 against 59,658, FF 54,430 against 54,336.  +94 registers and -83 LUTs
# is the signature of a different physical-optimisation directive, and that is
# what it was.  Every port, every package pin, every IO standard and all eleven
# clock definitions were identical in both.
#
# So the divergence was never in what this flow BUILDS.  It was in a recipe the
# manifest did not state, and this is the manifest stating it.
# ===========================================================================
# ===========================================================================
# GATED-CLOCK CONVERSION IS OFF FOR THIS DESIGN, AND THE TOOLKIT DEFAULT IS NOT
#
# The toolkit defaults SYNTH_GATED_CLOCK_CONVERSION to `auto`, and that default
# is right: Arm IP is written for ASIC and arrives carrying clock gates, so a
# Xilinx flow that never converts them leaves area and buffers on the table.
# This project overrides it because THIS design has something the general case
# does not, and the override is what the project/toolkit split is for.
#
# MEASURED 2026-09-11, two builds from design sha 4691a24 differing ONLY in this
# knob, both carried through to a bitstream:
#
#                     off        auto
#     LUT (impl)      59,851     59,615      -236   auto wins
#     WNS             +0.332     +0.215
#     WHS             -22.145    -23.654
#     failing hold    8          15          +7     auto loses
#     BUFGCE (impl)   23         24          +1     auto loses
#
# READ THE IMPLEMENTATION NUMBERS, NOT THE SYNTHESIS ONES. At synthesis `auto`
# reported 10 BUFG against `off`'s 12 and looked like a win on both axes. The
# count INVERTS through implementation. A synth-stage area or buffer figure is
# an intermediate, not a result.
#
# WHAT THE 7 EXTRA FAILURES ARE. All 8 of `off`'s failures are `pad_tx[*]`, the
# -20ns set_output_delay-on-the-wrong-edge artefact documented at XDC_TIMING
# below - phantom, not real. `auto` has those same 8 PLUS seven REAL ones, at
# -2.158ns and -1.871ns, on /CE pins in u_soc/u_network_core/u_rmii_to_mii:
# mrxd_reg[0..3], mrxdv_reg, rmii_txd_r_reg[0..1]. That is the Ethernet RECEIVE
# datapath.
#
# THE MECHANISM, read off the path report rather than inferred: rmii_to_mii
# divides the receive clock IN FABRIC (mrx_clk_reg). Conversion turns that
# generated clock into a clock ENABLE and inserts a BUFGCE to distribute it -
# the failing path is literally `mrx_clk_reg/Q -> BUFGCE (Logic Levels: 1) ->
# mrxd_reg/CE`, both ends on mii_rx_clk. That inserted buffer is the +1 BUFGCE,
# and the enable arrives ~2.16ns too early to meet hold.
#
# So the rule for anyone reading this on another design: conversion is a good
# default, and it is unsafe wherever a clock is DIVIDED IN FABRIC. Check for
# those before enabling it, and judge the result on impl numbers.
#
# Vivado also emits `WARNING [Synth 8-5866] 'keep_hierarchy' ... gated clock
# conversion will not be possible` for tidelink_design_i, axi_ahb_eth_ss and
# axi_smc, so conversion only ever reached the modules without kept hierarchy.
# That is why the damage is concentrated in the SoC internals.
#
# To re-measure: make all RUN_TAG=<tag> SYNTH_GATED_CLOCK_CONVERSION=auto
# ===========================================================================
export SYNTH_GATED_CLOCK_CONVERSION ?= off

export IMPL_OPT_DIRECTIVE       ?= Default
export IMPL_PLACE_DIRECTIVE     ?= Default
export IMPL_PHYS_OPT_DIRECTIVE  ?= AggressiveExplore
export IMPL_ROUTE_DIRECTIVE     ?= Default

# The legacy flow enables POST_ROUTE_PHYS_OPT_DESIGN on impl_1 with the same
# AggressiveExplore directive (build_design.log:5573 - phys_opt_design runs a
# SECOND time, after route_design).  The toolkit default is off.
export IMPL_POST_ROUTE_PHYS_OPT            ?= 1
export IMPL_POST_ROUTE_PHYS_OPT_DIRECTIVE  ?= AggressiveExplore

# `route_design -tns_cleanup` is a toolkit default and the legacy run strategy
# does not pass it.  Off, for the same reason as the four above: this is a
# parity manifest before it is a QoR manifest, and a knob that changes routing
# has to be a stated choice rather than an inherited one.
export IMPL_ROUTE_TNS_CLEANUP ?= 0

# ===========================================================================
# CFGBVS / CONFIG_VOLTAGE - SET TO SATISFY A STEP THAT HAS NO FAMILY GUARD, AND
# MEASURED INERT ON THIS DEVICE.  NAME THIS AS A WORKAROUND WHEN YOU QUOTE IT.
#
# flow/steps/bitstream_opts.tcl REFUSES the bitstream stage unless something
# states both, on the grounds that "write_bitstream reports their absence as DRC
# CFGBVS-1 ... the tool then assumes the configuration bank's voltage".  That
# reasoning is a 7-series / UltraScale one and it does not hold here.
#
# MEASURED 2026-09-08 on this design's own routed checkpoint:
#
#     PART:   xck26-sfvc784-2LV-c
#     FAMILY: zynquplus
#     PROP CFGBVS = ''      PROP CONFIG_VOLTAGE = ''
#     report_drc -checks CFGBVS-1  ->  Violations found: 0
#
# The check RUNS on this part and finds nothing with both properties unset,
# because on a Zynq UltraScale+ MPSoC the PL is configured through the PS and
# there is no user-supplied configuration bank whose voltage the tool has to
# assume.  The shipping legacy build agrees by omission: it sets neither, and
# the string "CFGBVS" does not appear anywhere in its 760 KB build log.
#
# So the honest statement is "not applicable to this device family", and there
# is no way to say that to the step - board_defer makes board_have answer 0 and
# the step dies just the same.  The two values below are therefore NOT a board
# fact and this file is not claiming they are: they are the interim mechanism
# the step's own refusal message prescribes ("Until that is settled in
# CONTRACT.md section 8, set them per project"), they are registered knobs so
# they land in the bitstream manifest, and they are INERT - proven by the DRC
# above returning 0 with them unset.
#
# THE REAL FIX IS IN THE TOOLKIT: flow/steps/bitstream_opts.tcl needs a family
# guard, so that a device on which CFGBVS-1 cannot fire is not refused for not
# answering it.  Raised with the toolkit; not fixable from here.
# ===========================================================================
export BITSTREAM_CFGBVS         ?= GND
export BITSTREAM_CONFIG_VOLTAGE ?= 1.8

# ===========================================================================
# UNUSED PINS: Pulldown, MATCHING THE SHIPPING BITSTREAM. Decided 2026-09-09.
#
# The toolkit defaults to `Pullnone` and that is the right default THERE: it
# applies to boards nobody has measured, and it is the only setting that cannot
# create contention on a PCB the build knows nothing about. This board is not
# that board.
#
# MEASURED from the shipping routed checkpoint, four bitstream writes in one
# Vivado session, diffing the payloads:
#
#   nothing set (what the shipping build did)  0 bytes differ
#   Pulldown, explicit                         0 bytes differ   <- so this is it
#   Pullup                                   598 bytes differ
#   Pullnone                                 307 bytes differ
#
# So the shipping KR260 bitstream pulls every unused PL pin DOWN - by inheriting
# Vivado's default, not by anyone choosing it. Two reasons to keep it rather
# than take the toolkit's default:
#
#   1. It is the field-proven state. These boards have been running with unused
#      pins pulled down. Changing a working board's pin termination as a SIDE
#      EFFECT of adopting a build tool is an unforced change with no upside
#      anyone has identified.
#   2. The KR260 exposes unused PL pins on the PMOD and RPi headers. On an
#      exposed header a defined level beats a floating one, and `Pullnone`
#      leaves them floating.
#
# This is stated EXPLICITLY rather than left to the tool's default, so that the
# value appears in the bitstream manifest and a future reader can see it was
# chosen. If a future board wants the toolkit default, set it there and say why.
#
# NOTE the earlier record was wrong: this was first put to the project owner as
# "Pullnone instead of the shipping build's Pullup". The Pullup figure came from
# a parity harness that had FORCED that value to chase a byte count, and the
# forced value was mistaken for the shipped one. The comparison that matters is
# Pullnone against PULLDOWN.
# ===========================================================================
export BITSTREAM_UNUSEDPIN      ?= Pulldown


# ===========================================================================
# ONE ID, DIAGNOSED 2026-09-08 ON A REAL RUN OF THIS FLOW (run tag bd-fix).
#
#     CRITICAL WARNING: [Timing 38-282] The design failed to meet the timing
#     requirements. Please see the timing summary report for details on the
#     timing violations.                        (synth.log:7521)
#
# IT IS EMITTED BY THIS FLOW'S OWN REPORT STEP, AT A STAGE THIS FLOW
# DELIBERATELY LEAVES UNCONSTRAINED.  CONTRACT §3.3 makes XDC_TIMING
# implementation-only, and flow/vivado/4_synth.tcl says why: "a create_clock
# read before synthesis constrains a netlist that does not exist yet".  The
# synthesis stage then runs report_timing_summary over a design with NO CLOCK
# DEFINED, and report_timing_summary's answer to an unconstrained design is
# this message.  The synth gate already states the same thing in its own
# DECLARED-ELSEWHERE section: "timing, owner=the impl stage ... any timing
# number from it would describe an unconstrained design".
#
# So the gate was failing a build for the consequence of its own contract.  The
# allowlist is the mechanism the contract provides for exactly that, and this
# comment is the diagnosis it requires.
#
# WHAT THIS DOES NOT DO, AND IT MATTERS.  The same id is emitted at
# IMPLEMENTATION, where it means something real - and this design's shipping
# baseline does NOT meet timing (WHS -22.273 ns on 8 endpoints of 116,678,
# measured on tidelink/imp/fpga/output/kr260-eth-chiplet).  Timing is therefore
# MEASURED AND NOT GATED here, by EXPECT_WNS_MIN and EXPECT_WHS_MIN above, both
# -1, both with their own note.  Allowlisting the id does not change that
# either way; it stops a message about an unconstrained SYNTHESIS from being
# read as a verdict.  Set EXPECT_WHS_MIN the day this flow has a routed result
# worth ratcheting against.
#
# The exemption is CONDITIONAL in the flow, not blanket: it applies only when
# the ids read out of the stage log account for the whole of the tool's own
# critical-warning count.  A second, undiagnosed critical warning would take
# the count past the ids and fail the gate with this entry still in place.
# ===========================================================================
MSG_GATE_ALLOWLIST ?= {Timing 38-282}


# -- 13. DEPLOY --------------------------------------------------------------
#
# ===========================================================================
# THE BOARD GROUP AND THE TARGET ARE DIFFERENT NAMESPACES.
#
#   kr260_01     is the board GROUP.   Leases, queues and reservations address
#                this name:  `fpgahub lease acquire kr260_01`.
#   kr260_01_pl  is the TARGET.        Program, reset and actions address this
#                one:  POST /api/v1/targets/kr260_01_pl/...
#
#   They do not overlap and neither 404 says which of the two you got wrong.
#   On this bench the KR260 carries TWO target-namespace members - the PL and
#   the PS behind the switch - so the board group genuinely cannot stand in for
#   the target here even by accident.
# ===========================================================================
FPGAHUB_BOARD  ?= kr260_01
FPGAHUB_TARGET ?= kr260_01_pl

# The existing deploy manifest, pointed at rather than copied - same reasoning
# as the XDCs.  It is 24 KB, it describes every target on this bench, and the
# eth-chiplet artefact and action entries in it are live.
#
# NOTE the contract (§3.3) specifies this default as
# `$(wildcard $(FPGA_DIR)/fpgahub.toml)` - DISCOVER, do not ASSERT - while the
# scaffolded template writes the bare path.  With the bare path a project with
# no deploy configured cannot pass `make check` until it creates an empty file
# it never asked for.  Reported; see fpga/README.md.
FPGAHUB_TOML ?= $(LEGACY_FPGA_DIR)/fpgahub.toml

# ===========================================================================
# zynqmp. NOT zynq7.  THIS IS THE LINE THAT CORRUPTS A LOAD IF IT IS WRONG.
#
#   ZynqMP wants the .bit HEADER STRIPPED and nothing else.  Zynq-7000 wants
#   the header stripped AND THE PAYLOAD BYTE-SWAPPED.  The legacy flow keeps
#   two separate converters for exactly this and says so: bit2bin.py MUST NOT
#   be used on ZynqMP, because its byte-swap is the zynq-fpga driver's format
#   and not fpgautil's.
#
#   Feed a KR260 a byte-swapped .bin and the conversion succeeds, the file is
#   the right size, fpgautil accepts it, and the PL does not come up.  Nothing
#   in the chain says why.
#
#   The board pack states this as a REQUIRED key - it is a fact about the
#   board's boot ROM, not about this design - and this line only exists so the
#   two can be cross-checked.
# ===========================================================================
BIN_STYLE ?= zynqmp


# -- 14. THE ENGINE ----------------------------------------------------------

include $(FPGA_FLOW_DIR)/mk/flow.mk


# ===========================================================================
# -- 15. WHAT THE TOOLKIT MUST NOT OWN --------------------------------------
#
#   Everything below is a PROJECT KNOB.  Each one is read by this design's own
#   Tcl - the legacy build_design.tcl today, this project's hooks and packaging
#   scripts tomorrow - and NOT by the toolkit.  They are declared here, and
#   exported here, for the reason CONTRACT §6.1.2 gives: a knob set by an
#   environment variable nobody recorded produces a result nobody can
#   reproduce.  Declared in the manifest, they land in the run manifest.
#
#   THE TEST APPLIED TO EVERY LINE: would a DIFFERENT design on a KR260 want
#   this variable?  If yes it is a contract variable and it belongs above.  If
#   no - if it names a module, an IP, a repo, a macro or a bring-up decision
#   that is ours - it belongs here and the toolkit must never learn about it.
#
#   The block is AFTER the include on purpose. These are not inputs mk/flow.mk
#   reads, and putting them above would invite the next reader to think they
#   are part of the contract.
# ===========================================================================

# -- Arm IP roots.  SITE PATHS, resolved from the environment, NEVER defaulted
#    to a literal.  These trees are shared, lab-wide, read-only vendor
#    collateral; a manifest that wrote one of those roots as a literal would be
#    a path that works on one machine and, worse, an inventory disclosure the
#    moment the manifest is pasted into a bug report.  (The literal that used to
#    illustrate this sentence has been removed: the repository's own vendor
#    guard blocked the commit that introduced it, in the comment warning against
#    exactly that.  The rule caught its own prose - twice now, here and in the
#    toolkit's CONTRACT.)  set_env.sh resolves
#    them; this passes them through and records that it did.
#    PROJECT-SIDE because WHICH Arm IP this SoC is built from is a fact about
#    this SoC.  A different KR260 design needs none of it.
export CMSDK_DIR
export CMSDK_FPGA_SRAM_V
export XHB500_IP_DIR

# -- The three sibling checkouts this design is assembled from, and the two
#    generated flists the master flist -f-includes.  PROJECT-SIDE, obviously:
#    they are the names of this project's own components.  Exported so
#    RTL_FLIST resolves without a caller having sourced set_env.sh - the
#    ${VAR} references inside the flist are expanded from the environment.
export NANOSOC_ETH_CHIPLET_HOME := $(PROJECT_ROOT)
export TIDELINK_HOME            := $(PROJECT_ROOT)/tidelink
export TIDECHART_HOME           := $(PROJECT_ROOT)/tidechart
export NANOSOC_MULTICORE_HOME   := $(PROJECT_ROOT)/nanosoc-multicore-system
export CHIPLET_SOC_VCS_FLIST    := $(PROJECT_ROOT)/build/elab/soc_vcs.f
export CHIPLET_TL_VCS_FLIST     := $(PROJECT_ROOT)/build/elab/tidelink_vcs.f

# -- The PHC source repo.  A SIBLING CHECKOUT, not a submodule, and the legacy
#    flow defaults it to $(HOME)/SoCLabs/ptp-hardware-clock-ahb - a per-user
#    path.  PROJECT-SIDE: that this design takes its PTP hardware clock from
#    another repo is a fact about this design.  FPGA_PHC_IP_REPO (the packaged
#    OUTPUT) folds into the contract's IP_REPOS in section 6; this is the
#    INPUT, and it is the half the toolkit cannot own.
export PHC_REPO_DIR ?= $(abspath $(PROJECT_ROOT)/../ptp-hardware-clock-ahb)

# -- PTP inclusion.  1 on every kr260-eth-chiplet build because the PHC is
#    INTEGRAL to the eth chiplet - it is inside the packaged IP, not an
#    optional block design cell - so unlike the bare-link kr260-pair targets
#    there is no PTP-off variant of this design at all.  Recorded rather than
#    left implicit.
export FPGA_TIDELINK_PTP ?= 1

# -- Clock regime.  0 = PLESIOCHRONOUS: this board derives its PHY link clock
#    from its own PS oscillator, so a two-board pair has same-nominal-rate,
#    independent crystals and ppm drift.  1 takes an external reference on
#    RPi BCM12 / AA13 and makes the pair MESOCHRONOUS.  PROJECT-SIDE: it is a
#    property of TideLink's forwarded-clock PHY, which has no CDR and freezes
#    (slip,phase) at S_DONE.  On this target it is 0 and the
#    *_extrefclk.xdc it would pull in does not exist.
export FPGA_TIDELINK_EXTREFCLK ?= 0
export FPGA_TIDELINK_REFCLK_OUT ?= 0

# -- Input delay.  0, and it is a DEVICE fact reached through a BOARD fact:
#    the ribbon lands in HDIO bank 44, and xck26 banks 43/44/45 are
#    BT_HIGH_DENSITY, which carry no IDELAY at all - the resource lives in the
#    HP banks' RXTX_BITSLICE.  A design that asks for one here does not get
#    one.  PROJECT-SIDE because it selects a TideLink RTL path, not a tool
#    setting.
export FPGA_USE_IDELAY ?= 0

# -- Deskew corrector.  0 = the shipped configuration.  1 selects
#    TL_EPOCH_ANCHOR_EN in WavD2DGpio.v - a real netlist change, intended for
#    an on-silicon A/B.  PROJECT-SIDE and unmistakably so: it names a signal in
#    our PHY.
export TIDELINK_EPOCH_ANCHOR ?= 0

# -- Placer directive override, applied to impl_1 when non-empty.
#    PROJECT-SIDE HERE, BUT SEE fpga/README.md: this is the one knob in this
#    block that arguably SHOULD be a contract variable.  A place/route
#    directive is a generic Vivado implementation strategy that every project
#    on this tool wants, and §3.3 has no variable for it - so today the only
#    contract-sanctioned way to set one is a wholesale step override, which is
#    a large hammer for one property.  Left empty: no directive is forced.
export TIDELINK_PLACE_DIRECTIVE ?=

# -- USR_ACCESS.  The legacy flow computes the low 32 bits of the git SHA and
#    exports it to the implementation child so the bitstream carries its own
#    provenance.  Left empty here: the toolkit's manifest records
#    project_git_sha and toolkit_git_sha per stage, which is the same claim
#    made where a reader can find it.  PROJECT-SIDE either way.
export TIDELINK_GIT_USR_ACCESS ?=

# -- ILA insertion.  0.  The debug core was removed from every build on
#    2026-06-19 for the no-ILA headroom build: it was being synthesised into
#    EVERY build because the legacy flow globs *_tidelink_drc.xdc and adds it
#    unconditionally, and with mark_debug stripped it failed implementation
#    with Chipscope 16-213.  PROJECT-SIDE: it is driven by our own
#    insert_debug_core.tcl.
export FPGA_INSERT_DEBUG_CORE ?= 0

# -- 1 on this target.  The eth-chiplet IP is packaged from THIS repo's source
#    resolution, so the legacy tidelink-flist provenance gate
#    (tl_verify_packaged_ip) is the wrong oracle for it and is skipped.
#    PROJECT-SIDE: it names one of our gates.
#
#    IT IS A SKIP, AND A SKIP IS NOT A PASS.  What is not checked on this
#    target is that the packaged IP's sources match the flist that claims to
#    describe them.  Written down here so the hole is visible from the
#    manifest rather than from a Makefile conditional.
export FPGA_SKIP_IP_VERIFY ?= 1


# -- 16. YOUR OWN WORK, ATTACHED TO A STAGE ----------------------------------
#
# Nothing yet.  When something lands here it is a RECIPE-LESS rule
# (`synth: nanosoc-eth-chiplet-<something>`), it goes below this line because
# above the include the stage targets do not exist yet, and its name is
# prefixed so it cannot collide with one of the engine's.

# Copyright (C) 2026, SoC Labs (www.soclabs.org)
