#-----------------------------------------------------------------------------
# ASIC/gls-netlist/Makefile - THIS PROJECT'S netlist gate-level-simulation table.
#
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# The engine is $(ASIC_FLOW_DIR)/mk/gls_netlist.mk in the toolkit and knows
# nothing about this chip. Everything design- or site-specific is below.
#
#   make -C ASIC/gls-netlist collateral   what is needed vs what is on disk
#   make -C ASIC/gls-netlist census       resolve every cell   (no licence)
#   make -C ASIC/gls-netlist build        + compile
#   make -C ASIC/gls-netlist run          + run
#   make -C ASIC/gls-netlist gls          all of it
#   make -C ASIC/gls-netlist help         the engine's own target list
#
#   make -C ASIC/gls-netlist flash-image        build + validate the boot image
#   make -C ASIC/gls-netlist flash-selftest     prove the attachment, no netlist
#   make -C ASIC/gls-netlist no-force           prove the last run held no wire
#   make -C ASIC/gls-netlist negative-control   blank flash: the gate MUST fail
#   make -C ASIC/gls-netlist forced-fallback    diagnostic; NOT a boot
#
# THE SHIPPED ITEM BOOTS OFF A REAL FLASH. THERE IS NO FORCE.
#
# fp1505_cc simulates the routed netlist with a vendor SST26VF064B model bound
# onto its QSPI pins and a validated boot image in it, so CPU0 leaves reset
# because CPU1's stage-0 walked its whole boot and wrote the bootgate - not
# because the bench held the wire. See THE QSPI FLASH DEVICE below.
#
# TWO THINGS THAT MUST TRAVEL WITH ANY PASS FROM THIS GATE:
#   * the boot image is BENCH-SUPPLIED. inputs.txt carries its sha256 and
#     sim.log carries the attachment's banner; both are published evidence.
#   * the bootgate is NOT the success criterion, because CPU1's ROM writes it
#     unconditionally on the way to halt() so a blank flash releases CPU0 too.
#     `make negative-control` runs that image and requires this gate to go red.
#
# WHY THE ROUTED PAD-RING NETLIST AND NOT THE SYNTHESIS ONE
#
# Both candidate netlists have the same top module and both contain the pad ring
# - the "core-level netlist without pads" they are sometimes described as does
# not exist here. The synthesis netlist simply has no VDD/VDDIO/VSS/VSSIO PORTS
# on its top, because power ports are added later, and both instantiate the same
# nine TSMC IO driver cells and the same 12 memory macros.
#
# The one real difference is that the routed netlist also holds 82 bond pads
# (PAD70GU x42, PAD70NU x40) that P&R inserted and that have no Verilog model
# anywhere in this PDK - LEF only. That is the argument for the synthesis
# netlist, and it does not survive contact with the file: Innovus writes them
# with an EMPTY PORT LIST,
#
#     PAD70GU BuPAD_HOST_IO_5 ();
#
# so they have no electrical connection and an empty-module declaration for them
# cannot change behaviour. The census checks exactly that rather than taking it
# on trust (netlist_census.py, THE STUB RULE). So the cost is two mechanically
# inert declarations, against the benefit of simulating the netlist actually
# being taped out - after placement, CTS and routing rebuilt the clock tree and
# remapped a large fraction of the cells.
#
# The stub file is the one ASIC/genus-innovus/scripts/lec/ already uses for the
# same two cells for the same reason, so this introduces no new deviation.
#-----------------------------------------------------------------------------

THIS_DIR   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
REPO       := $(patsubst %/,%,$(dir $(patsubst %/,%,$(dir $(THIS_DIR)))))

ASIC_FLOW_DIR ?= $(REPO)/ASIC/asic-toolkit
BUILD_DIR     ?= $(REPO)/build

# -- site collateral ---------------------------------------------------------
# NOT SPELLED HERE. This repository is public, and an absolute mount point
# paired with a revision-coded release directory is together an INVENTORY of the
# collateral this site is licensed to hold, which the licence does not permit
# publishing. ci/check-vendor-collateral.sh refuses both.
#
# These are SITE FACTS that ASIC/common.mk already defines exactly once and
# exports. This gate is invoked DIRECTLY (`make -C ASIC/gls-netlist ...`), so
# that export does not reach it, and a bare default would leave every model path
# as an absolute, plausible, non-existent string like "/rf_01k/rf_01k.v". So
# read each value from its single definition at use time: a pointer cannot
# drift, and a second copy is a second thing to keep in step.
#
# A command-line or environment value still wins, because `?=`.
common_mk_var = $(shell sed -n 's/^export $(1)[[:space:]]*?*=[[:space:]]*//p' $(REPO)/ASIC/common.mk 2>/dev/null | head -1)

MEM_BASE     ?= $(call common_mk_var,MEM_BASE)
TSMC_65_HOME ?= $(call common_mk_var,TSMC_65_HOME)
PHYS_IP      ?= $(call common_mk_var,PHYS_IP)
STDCELL_PKG  ?=
STDCELL_REL  ?=
IOCELL_PKG   ?=
IOCELL_REL   ?=

# THE PG VARIANT, and it is not a preference. This netlist is a POWER netlist:
# 171k of its 204k instances are written with .VDD()/.VSS() connections, and
# VDD/VSS are plumbed as inout ports through every level of the hierarchy down to
# the leaf cells. The ordinary (non-PG) standard-cell library defines every one
# of those cells BY NAME and none with power pins, so a module-name check passes
# completely and elaboration then fails on the first instance - measured at
# 370/370 cell types "resolved" and 318 interface-mismatched. `census` catches
# that statically now.
#
# RESOLVED, NOT SPELLED, and not assembled from separately-defaulted parts
# either: five empty defaults once produced an absolute path that looked
# plausible and did not exist, and `make collateral` failed on every model.
# pdk_paths.sh is this repository's own PDK resolver and answers exactly these
# two questions, so using it removes four variables rather than defaulting them
# and picks up a release-directory bump instead of silently mismatching. Same
# mechanism ASIC/eth-chiplet/design.mk uses for ARM_CLN65LP_TECH.
PDK_PATHS_SH ?= $(dir $(lastword $(MAKEFILE_LIST)))../tech_wrappers/tsmc65/scripts/pdk_paths.sh
STDCELL_V := $(shell TSMC_65_HOME='$(TSMC_65_HOME)' PHYS_IP='$(PHYS_IP)' \
                     bash $(PDK_PATHS_SH) stdcell-vlog 2>/dev/null)
IOCELL_V  := $(shell TSMC_65_HOME='$(TSMC_65_HOME)' PHYS_IP='$(PHYS_IP)' \
                     bash $(PDK_PATHS_SH) io-vlog 2>/dev/null)

# CAVEAT, AND IT MUST TRAVEL WITH EVERY CLAIM MADE FROM A RUN OF THIS: the
# simulation Verilog above is an OLDER CELL REVISION than the Liberty the design
# was timed against, for both the standard cells and the IO library. That makes
# this a FUNCTIONAL check and not a timing one. It says whether the logic works;
# it says nothing about whether it closes.

MEM_V := $(MEM_BASE)/rf_01k/rf_01k.v \
         $(MEM_BASE)/rf_08k/rf_08k.v \
         $(MEM_BASE)/rf_16k/rf_16k.v \
         $(MEM_BASE)/rf_32k/rf_32k.v \
         $(MEM_BASE)/flash_cache_data/flash_cache_data.v \
         $(MEM_BASE)/flash_cache_tag/flash_cache_tag.v

ROMLIBS  := $(REPO)/ASIC/romlibs
ROM_V    := $(ROMLIBS)/cc_rom/rom_via.v $(ROMLIBS)/eth_rom/eth_rom_via.v

# ASIC/romlibs is evidence in an open investigation: it is READ here and never
# written. The content files are COPIED into the run directory by the runner.
CC_RCF   := $(ROMLIBS)/cc_rom/rom_via_verilog.rcf
ETH_RCF  := $(ROMLIBS)/eth_rom/eth_rom_via_verilog.rcf

# The golden for the array comparison is the FIRMWARE, from the firmware build
# tree - not the .rcf that was staged into the ROM. Comparing the array against
# the file that filled it would prove only that $readmemb ran.
CC_FIRMWARE  ?= $(REPO)/nanosoc-multicore-system/build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom_chip_core/nanosoc_bootrom_chip_core.bintxt
ETH_FIRMWARE ?= $(REPO)/nanosoc-multicore-system/build/cmake/gcc-m0plus-le/firmware/bootloader/stage0_bootrom/eth_ss_bootrom.bintxt

BONDPAD_STUBS := $(REPO)/ASIC/genus-innovus/scripts/lec/bondpad_stubs.v

# -- the table ---------------------------------------------------------------
GLSN_ITEMS := fp1505_cc full0814_cc gdsrun_cc

GLSN_NETLIST_fp1505_cc := $(REPO)/ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads_pnr.v
GLSN_TOP_fp1505_cc     := nanosoc_eth_chiplet_pads
GLSN_SPEC_fp1505_cc    := $(THIS_DIR)/bench/eth_chiplet_fp1505_cc.json
# EVIDENCE INTO EACH ITEM'S OWN BUILD -- BUT ONLY THE EVIDENCE.
#
# scripts/ci/package_submission.sh collects exactly one tree,
# $(ASIC_DIR)/reports. Written under $(BUILD_DIR)/gls-netlist - gitignored and
# outside every build tree - this gate's proof reaches nobody.
#
# A RUN DIRECTORY AND AN EVIDENCE DIRECTORY ARE NOT THE SAME THING. Pointing the
# run at reports/gls put 257 MB per item into a packaged tree (simv.daidir 164M,
# csrc 48M, a 41M PG-completed netlist copy) against ~28 KB of actual evidence.
# So the run stays in build/ and the gate PUBLISHES its evidence separately.
#
# The netlist path already names the run that produced it, so derive it:
# <run>/outputs/x.v -> <run>. `=` not `:=` - these dereference GLSN_NETLIST_<n>
# declared further down, and an immediate assignment expands to nothing and
# yields "//reports/...", an absolute path that looks plausible and is not.
glsn_run_root = $(abspath $(dir $(GLSN_NETLIST_$(1)))/..)
GLSN_EVIDENCE_fp1505_cc    = $(call glsn_run_root,fp1505_cc)/reports/gls/fp1505_cc
GLSN_EVIDENCE_full0814_cc  = $(call glsn_run_root,full0814_cc)/reports/gls/full0814_cc

GLSN_MODELS_N_fp1505_cc  := 10
GLSN_MODELS_fp1505_cc  := $(STDCELL_V) $(IOCELL_V) $(MEM_V) $(ROM_V)

GLSN_STUBS_fp1505_cc      := $(BONDPAD_STUBS)
GLSN_STUB_CELLS_fp1505_cc := PAD70GU PAD70NU

# model=content. The runner reads the basename OUT OF the model and stages the
# content file there; it is not assumed to match the macro name.
GLSN_CONTENT_fp1505_cc := \
    $(ROMLIBS)/cc_rom/rom_via.v=$(CC_RCF) \
    $(ROMLIBS)/eth_rom/eth_rom_via.v=$(ETH_RCF)

#-----------------------------------------------------------------------------
# THE QSPI FLASH DEVICE - why the shipped item boots instead of being released.
#
# CPU1's stage-0 does flash I/O before anything else - an attempt-counter
# read+program in APB command mode, XiP bring-up, a boot table, an image copy and
# a CRC - and only then writes 0x4 to release CPU0. With nothing on the QSPI pins
# none of that completes, CPU0 never fetches, and the only way to get a run is to
# force the bootgate wire, which cannot be quoted as the CPU1->CPU0 handshake.
#
# There is a device on those pins now. Three files make that work, and each is
# here for a reason that is not interchangeable with the others:
#
#   SST26_V        the VENDOR model of the part on the board. Not ours, not
#                  written for this, and therefore not able to flatter us.
#   FLASH_ATTACH   binds that model onto the generated bench's QSPI nets and
#                  loads the image into it. `bind` because the bench is GENERATED
#                  and rewritten on every build, and its JSON schema can declare
#                  a net but cannot instantiate a module. No toolkit change:
#                  run_gls_netlist.sh already compiles -sverilog.
#   FLASH_IMAGE    the $readmemh image, built by flash/mkflash.sh, which wraps the
#                  authoritative v2 packer in nanosoc_arch_tech and validates the
#                  result against the two ROMs' own accept/reject rules before
#                  this gate is allowed to see it.
#
# THE IMAGE IS BENCH-SUPPLIED AND THAT TRAVELS WITH THE VERDICT. A run that
# reached the application only because the testbench handed the design a valid
# image is not the design booting unaided. inputs.txt records flash_image.hex
# with its sha256; sim.log carries the attachment's GLSN-FLASH banner. Both are
# published evidence. Do not quote a pass without them.
#
# DO NOT SET GLSN_ZERO_DELAY_fp1505_cc=0 WITH THIS ATTACHED. SST26VF064B.v
# corrupts its ENTIRE array to x on any timing violation (`corrupt_all`), so a
# gate-level QSPI clock that trips the model's Fclk/Tsckh specparams would wipe
# the image mid-boot and present as a CRC failure. The default 1 adds
# +nospecify +notimingcheck, which keeps that block inert - and also removes the
# model's output delays, so this is a FUNCTIONAL attachment that says nothing
# about QSPI timing closure.
#-----------------------------------------------------------------------------
FLASH_DIR    := $(THIS_DIR)/flash
SST26_V      ?= $(REPO)/nanosoc-multicore-system/ahb_qspi/verif/VIP/SST26VF064B.v
FLASH_ATTACH := $(FLASH_DIR)/gls_flash_attach.sv
FLASH_OUT    ?= $(BUILD_DIR)/gls-netlist/flash
FLASH_IMAGE  := $(FLASH_OUT)/flash_image.hex

GLSN_COMPILE_ARGS_fp1505_cc := $(SST26_V) $(FLASH_ATTACH)

# The bench $readmemb's the two ROM goldens by basename out of the run
# directory; gls_flash_attach.sv $readmemh's flash_image.hex from the same
# place. All three are staged there by the runner.
GLSN_STAGE_fp1505_cc := $(CC_FIRMWARE) $(ETH_FIRMWARE) $(FLASH_IMAGE)

# ARM_UD_* select the memory compilers' fast functional models and collapse their
# internal delays to zero. INITIALIZE_MEMORY zero-fills the RAM storage at time
# 0: without it the rf_* and flash_cache_* arrays come up X, that X reaches the
# reset network before reset can drive anything, the design never leaves reset,
# and it presents as a reset-tree bug.
#
# POWER_PINS is the macro the memory and ROM compilers gate their PG port list
# on, and it must be set for the same reason the standard-cell library above is
# the PG one: the ROM macros are instantiated with .VDDE()/.VSSE() and the RAMs
# with .VDD()/.VSS(). The IO pad cells are the exception - the _G cells this
# netlist uses carry no PG pins at all - so their model is used unmodified.
GLSN_DEFINES_fp1505_cc := ARM_UD_MODEL ARM_UD_DP ARM_UD_CP ARM_UD_SEQ INITIALIZE_MEMORY POWER_PINS

# NO -y SEARCH PATH, deliberately. A cell a -y path cannot find elaborates as
# an empty module with Z outputs and no diagnostic. Every model is named above
# and the census refuses anything left over.
GLSN_LIBDIRS_fp1505_cc :=

# PG COMPLETION. See the note on STDCELL_V above and flow/verify/gls/
# pg_complete.py. 22,469 instances in this file - every cell P&R inserted - are
# written without their supply pins while 171k others have them. The transform
# writes a COPY with those pins tied to a local supply1/supply0 and simulates the
# copy; ASIC/eth-chiplet/build/ is never written to.
#
# THIS IS A DEVIATION AND MUST BE DECLARED IN ANY RESULT QUOTED FROM IT. It is a
# narrow one - the cells are on the rails in the layout, LVS reads the DEF and
# not this file, and a tied supply is what the vendor's non-PG model of the same
# cell does - but the file simulated is not byte-identical to the file being
# taped out. build/gls-netlist/fp1505_cc/pg_complete.txt records which instances
# differ.
GLSN_PG_PAIRS_fp1505_cc := VDD:VSS VDDE:VSSE

GLSN_BUILD_TIMEOUT_fp1505_cc := 7200
GLSN_RUN_TIMEOUT_fp1505_cc   := 7200

#-----------------------------------------------------------------------------
# ITEM 3: the 2026-08-19 ROUTED netlist, PG-COMPLETE AS WRITTEN.
#
# The first netlist in this project that needs no PG-completion transform. Its
# supplies are written by `write_netlist -include_pg` in the toolkit route stage
# (asic-toolkit 668dc65, ROUTE_NETLIST_PG) rather than reconstructed afterwards
# by pg_complete.py, so what simulates is what the stream was written from.
#
# MEASURED 2026-08-19, against the plain _pnr.v of the SAME run as a control:
#   _pnr_pg.v  ->      0 instances need completion
#   _pnr.v     -> 18,158 instances need completion
# and the .VDD( census agrees exactly: 204,648 vs 186,490, delta 18,158.
#
# THE TRAP THAT MAKES THAT CONTROL MANDATORY. pg_complete.py REFUSES to run
# without --pair, but returns a cheerful 0 without --model. Run it with no models
# and it scores 0 on BOTH files and reads as a clean pass. Never accept a zero
# here until the plain netlist has been run through the same invocation and come
# back NON-ZERO.
#
# WHY A SEPARATE ITEM RATHER THAN REPOINTING fp1505_cc: the ROM MODELS are
# regenerated per run - rom_via.v differs from the repo copy - while the ROM
# CONTENT is byte-identical (.rcf md5 f00635fc / 8f565668). Models must come from
# the same run as the netlist that instantiates them; content is the firmware and
# does not move. Binding this run's netlist to the repo's models would be the
# mixed-vintage trap this project has already lost time to.
#-----------------------------------------------------------------------------
# OVERRIDE ME on any other machine. This run was made in an isolated worktree,
# so the path is not repo-relative and cannot be derived. `?=` rather than `:=`
# so `make GDSRUN_ROOT=... ` works without editing this file. The item refuses
# loudly rather than silently simulating nothing if the path does not exist.
GDSRUN_ROOT   ?= $(HOME)/SoCLabs/gds-run-20260819/ASIC/eth-chiplet/build/gdsrun-20260819
GDSRUN_ROMLIB := $(GDSRUN_ROOT)/romlibs
ROM_V_GDSRUN  := $(GDSRUN_ROMLIB)/cc_rom/rom_via.v $(GDSRUN_ROMLIB)/eth_rom/eth_rom_via.v

# The netlist is STRIPPED before it is simulated - see strip_leaf_defs.py. The
# raw `-include_pg` file carries a port-only definition for every leaf it
# instantiates and those shadow the vendor models, so it cannot be simulated as
# written. Stripping is done HERE rather than in write_netlist deliberately: the
# emission side is on the P&R critical path to the stream and this is not.
#
# BOTH the models AND the bondpad stubs are passed as authorities. Dropping the
# stubs from that list leaves PAD70GU/PAD70NU defined twice - once by the netlist
# and once by bondpad_stubs.v - which is the same collision one layer down.
GDSRUN_PG_RAW      := $(GDSRUN_ROOT)/outputs/nanosoc_eth_chiplet_pads_pnr_pg.v
GDSRUN_PG_STRIPPED := $(REPO)/build/gls-netlist/gdsrun_cc/nanosoc_eth_chiplet_pads_pnr_pg_stripped.v

$(GDSRUN_PG_STRIPPED): $(GDSRUN_PG_RAW) $(THIS_DIR)/strip_leaf_defs.py
	@mkdir -p $(dir $@)
	python3 $(THIS_DIR)/strip_leaf_defs.py --netlist $< \
	    $(foreach m,$(GLSN_MODELS_gdsrun_cc) $(GLSN_STUBS_gdsrun_cc),--model $(m)) \
	    --out $@ --report $(dir $@)strip_leaf_defs.txt

gls-netlist-gdsrun_cc gls-netlist-build-gdsrun_cc: $(GDSRUN_PG_STRIPPED)

GLSN_NETLIST_gdsrun_cc    := $(GDSRUN_PG_STRIPPED)
GLSN_TOP_gdsrun_cc        := nanosoc_eth_chiplet_pads
GLSN_SPEC_gdsrun_cc       := $(THIS_DIR)/bench/eth_chiplet_fp1505_cc.json
GLSN_MODELS_N_gdsrun_cc   := 10
GLSN_MODELS_gdsrun_cc     := $(STDCELL_V) $(IOCELL_V) $(MEM_V) $(ROM_V_GDSRUN)
GLSN_STUBS_gdsrun_cc      := $(BONDPAD_STUBS)
GLSN_STUB_CELLS_gdsrun_cc := PAD70GU PAD70NU
GLSN_CONTENT_gdsrun_cc    := \
    $(GDSRUN_ROMLIB)/cc_rom/rom_via.v=$(GDSRUN_ROMLIB)/cc_rom/rom_via_verilog.rcf \
    $(GDSRUN_ROMLIB)/eth_rom/eth_rom_via.v=$(GDSRUN_ROMLIB)/eth_rom/eth_rom_via_verilog.rcf
GLSN_STAGE_gdsrun_cc      := $(CC_FIRMWARE) $(ETH_FIRMWARE) $(FLASH_IMAGE)
GLSN_DEFINES_gdsrun_cc    := ARM_UD_MODEL ARM_UD_DP ARM_UD_CP ARM_UD_SEQ INITIALIZE_MEMORY POWER_PINS
GLSN_LIBDIRS_gdsrun_cc    :=
GLSN_PG_PAIRS_gdsrun_cc   := VDD:VSS VDDE:VSSE
# The QSPI device. Without this the pads are addressed and nothing answers:
# CPU1 boots, enters main, drives nCS low, finds no image and never writes its
# IMEM - which reads exactly like a design that cannot boot. Measured 2026-08-19:
# omitting it gave RESULT FAIL pass=13 fail=14 with qspi_flash_addressed PASS.
GLSN_COMPILE_ARGS_gdsrun_cc := $(SST26_V) $(FLASH_ATTACH)

# WHERE THE EVIDENCE LANDS. Without this the run's verdict stays in build/ and no
# packager collecting a build tree finds it - the toolkit prints a NOTE saying so
# on every run. The tag names the RUN, so a later run publishes beside this one
# rather than overwriting it: two streams, two verdicts, both re-readable.
GLSN_EVIDENCE_gdsrun_cc := $(REPO)/ASIC/eth-chiplet/build/gdsrun-20260819/reports/gls/gdsrun_cc

# Publish WITHOUT re-simulating. Upstream reaches glsn_publish only from
# `gls-netlist-%`, which re-runs the whole item - so setting GLSN_EVIDENCE after a
# good run otherwise costs another full simulation to copy six files. Nothing here
# recomputes evidence; it copies what the run already wrote.
# strip_leaf_defs.txt JOINS THE EVIDENCE, and it is load-bearing rather than
# decorative. This item simulates a STRIPPED COPY of the routed netlist, so its
# inputs.txt records only that copy's path in build/ - nothing in the published
# evidence otherwise ties the run to the gdsrun outputs tree it came from. The
# strip report names the source, and the signoff stage's SECONDARY block asserts
# the chain: report source under the declared run's outputs/, report `out` equal
# to the netlist inputs.txt actually simulated.
GLSN_EVIDENCE_FILES += strip_leaf_defs.txt

gls-netlist-publish-%: ; @$(call glsn_publish,$*)
GLSN_BUILD_TIMEOUT_gdsrun_cc := 7200
GLSN_RUN_TIMEOUT_gdsrun_cc   := 7200


#-----------------------------------------------------------------------------
# ITEM 2: the 2026-08-14 SYNTHESIS netlist.
#
# Not a preference - a control, and a fallback with a reason. The routed netlist
# above is PG-INCONSISTENT: 171k of its instances are written with .VDD()/.VSS()
# and 22,469 - every cell P&R inserted, which is the whole clock-tree buffering
# (CKND/CKBD), all 3040 tie cells, the hold-fix buffers and the delay cells - are
# written WITHOUT. Against the PG library those 22,469 have floating supplies and
# every PG cell routes its output through a u_power_down UDP whose table says
# `? x ? : x`, so they all drive X, the clock tree included, and the design
# cannot be clocked at all. Against the non-PG library the other 171k do not
# elaborate. Neither library can simulate that file as written, which is what the
# PG-completion transform above exists for.
#
# This synthesis netlist has no such split: 0 stdcell and 0 macro instances carry
# PG, and the only .VDD() in the file are on the six PVDD1DGZ_G supply pads,
# which genuinely have a VDD port. It pairs with the ordinary library and needs
# no POWER_PINS.
#
# A RESULT HERE DOES NOT TRANSFER TO fp1505. It is a different and older build -
# placement, CTS and routing rebuilt the clock tree and remapped a large fraction
# of the cells - and it is the routed netlist that is being taped out. What this
# item can do is prove the boot PATH exists in the design, separating "the CPU
# cannot fetch" from "this particular file cannot be simulated".
#-----------------------------------------------------------------------------
# The non-PG twin is the SAME release directory, different basename. Derived from
# STDCELL_V rather than resolved again, so the two cannot drift onto different
# releases - the mixed-vintage trap this project already lost time to.
STDCELL_V_NOPG := $(patsubst %_pwr.v,%.v,$(STDCELL_V))

GLSN_NETLIST_full0814_cc := $(REPO)/ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads_gate.v
GLSN_TOP_full0814_cc     := nanosoc_eth_chiplet_pads
GLSN_SPEC_full0814_cc    := $(THIS_DIR)/bench/eth_chiplet_full0814_cc.json
GLSN_MODELS_N_full0814_cc  := 10
GLSN_MODELS_full0814_cc  := $(STDCELL_V_NOPG) $(IOCELL_V) $(MEM_V) $(ROM_V)
# Synthesis inserted no bond pads; P&R did. Nothing to stub.
GLSN_STUBS_full0814_cc      :=
GLSN_STUB_CELLS_full0814_cc :=
GLSN_CONTENT_full0814_cc := \
    $(ROMLIBS)/cc_rom/rom_via.v=$(CC_RCF) \
    $(ROMLIBS)/eth_rom/eth_rom_via.v=$(ETH_RCF)
GLSN_STAGE_full0814_cc := $(CC_FIRMWARE) $(ETH_FIRMWARE)
# No POWER_PINS: this netlist connects none.
GLSN_DEFINES_full0814_cc := ARM_UD_MODEL ARM_UD_DP ARM_UD_CP ARM_UD_SEQ INITIALIZE_MEMORY
GLSN_LIBDIRS_full0814_cc :=
GLSN_BUILD_TIMEOUT_full0814_cc := 7200
GLSN_RUN_TIMEOUT_full0814_cc   := 7200

include $(ASIC_FLOW_DIR)/mk/gls_netlist.mk

#-----------------------------------------------------------------------------
# THE IMAGE IS A PREREQUISITE, NOT AN INSTRUCTION IN A COMMENT.
#
# GLSN_STAGE_fp1505_cc names flash_image.hex, and the runner REFUSES to stage a
# missing file - correctly, because $readmemh on a missing file is only a
# warning, the array stays uniformly 0xFF, and a blank-flash boot still releases
# CPU0. The failure would be a false PASS rather than a missing file, so the
# image is wired in as a real prerequisite and cannot be forgotten.
#
# These four names are matched by pattern rules in the toolkit. A target with
# prerequisites and NO recipe still takes its recipe from the pattern rule, so
# this adds the dependency without duplicating - or shadowing - the engine.
# `gls-netlist` and `gls-netlist-collateral` recurse with
# `-f $(firstword $(MAKEFILE_LIST))`, which is THIS file, so the dependency
# survives the recursion.
#-----------------------------------------------------------------------------
gls-netlist-collateral-fp1505_cc: $(FLASH_IMAGE)
gls-netlist-census-fp1505_cc:     $(FLASH_IMAGE)
gls-netlist-build-fp1505_cc:      $(FLASH_IMAGE)
gls-netlist-fp1505_cc:            $(FLASH_IMAGE)

$(FLASH_IMAGE):
	@echo "== building the QSPI boot image (flash/mkflash.sh) =="
	$(FLASH_DIR)/mkflash.sh --outdir $(FLASH_OUT)

.PHONY: flash-image
## Build + validate the QSPI boot image only. mkflash.sh checks it against the
## two ROMs' own accept/reject rules and refuses to emit one they would reject.
flash-image: $(FLASH_IMAGE)

.PHONY: flash-selftest
## Prove the ATTACHMENT without the netlist: bind + $readmemh + a real Fast-Read
## 0x0B through the vendor model. Seconds, no PDK, no 83 s compile. Run it first
## when the shipped item goes red - it separates a broken attachment from a slow
## or failing boot, which the full run cannot do on its own.
flash-selftest: $(FLASH_IMAGE)
	@mkdir -p $(FLASH_OUT)/selftest
	cd $(FLASH_OUT)/selftest && cp -f $(FLASH_IMAGE) . && \
	    $(GLSN_SIM) -full64 -sverilog -timescale=1ns/1ps -top gls_netlist_tb \
	        -o simv_selftest $(SST26_V) $(FLASH_ATTACH) \
	        $(FLASH_DIR)/selftest/tb_flash_attach_selftest.sv \
	        -l compile.log < /dev/null && \
	    ./simv_selftest -l run.log < /dev/null && \
	    grep -q "SELFTEST: OVERALL PASS" run.log && echo "flash attachment: PASS"

#-----------------------------------------------------------------------------
# THE NEGATIVE CONTROL, and it is the most important target in this file.
#
# CPU1's stage-0 writes NETWORK_CORE_BOOTGATE twice: once on the success path and
# once UNCONDITIONALLY after every candidate including the golden recovery image
# has failed, so a blank board does not silently hold CPU0 in reset with a dead
# debug UART. The consequence for this gate is sharp: A BLANK FLASH STILL
# RELEASES CPU0, and CPU0 still fetches its MSP and reset vector out of eth_rom.
# Any gate whose success criterion is the bootgate, or the eth_rom fetch, PASSES
# an image that never parsed.
#
# This target runs exactly that image - same netlist, same bench, same device, a
# 512 KB image of erased 0xFF - and REQUIRES the shipped spec to go red on the
# FOUR IMEM rungs a blank flash can never climb, at any window length, because
# there is no image to copy: cpu1_imem_write, cpu1_imem_fetch (CPU1 side) and
# eth_imem_write_after_release, eth_imem_fetch (CPU0 side). Those eight checks
# are the discrimination; nothing else here is.
#
# Two rungs in this spec are NOT discrimination and must not be read as such:
#   - eth_rom_port PASSES on the blank image (1137 accesses vs 13908 on a good
#     one). It proves the ROM is alive, never that the boot succeeded.
#   - eth_sysctrl_remap_set goes red on the blank image only because the window
#     closes before CPU1 finishes exhausting TABLE0/TABLE1/GOLDEN. The release
#     above is UNCONDITIONAL, so a longer window turns that red green. It is a
#     sound positive check and a worthless negative one.
#
# It runs in its OWN directory and uses build/run rather than the all-in-one
# target, so it can neither overwrite the shipped item's evidence nor publish its
# own into reports/.
#-----------------------------------------------------------------------------
NEG_DIR   := $(BUILD_DIR)/gls-netlist-negative
NEG_IMG   := $(FLASH_OUT)/blank/flash_image.hex
NEG_BYTES ?= 524288

$(NEG_IMG):
	@mkdir -p $(dir $@)
	@$(GLSN_PYTHON) -c "import sys; sys.stdout.write('FF\n' * $(NEG_BYTES))" > $@
	@echo "blank (erased 0xFF) image: $@  ($$(wc -l < $@) bytes)"

.PHONY: negative-control
## Run the gate against a deliberately blank flash and require it to FAIL.
negative-control: $(NEG_IMG)
	@echo "== NEGATIVE CONTROL: a blank (erased) flash, which still releases CPU0 =="
	$(MAKE) --no-print-directory gls-netlist-build-fp1505_cc \
	    GLSN_DIR=$(NEG_DIR) GLSN_STAGE_fp1505_cc="$(CC_FIRMWARE) $(ETH_FIRMWARE) $(NEG_IMG)"
	@rc=0; $(MAKE) --no-print-directory gls-netlist-run-fp1505_cc \
	    GLSN_DIR=$(NEG_DIR) GLSN_STAGE_fp1505_cc="$(CC_FIRMWARE) $(ETH_FIRMWARE) $(NEG_IMG)" \
	    || rc=$$?; \
	v=$(NEG_DIR)/fp1505_cc/verdict.txt; \
	echo ""; echo "-- negative-control verdict ($$v) --"; \
	[ -s "$$v" ] || { echo "FAIL: the blank-flash run wrote no verdict at all."; \
	                  echo "  That is a crashed run, not a discriminating gate."; exit 1; }; \
	sed 's/^/    /' "$$v"; echo ""; \
	if [ $$rc -eq 0 ]; then \
	    echo "FAIL: the gate PASSED a blank flash. It is not discriminating."; exit 1; fi; \
	bad=0; \
	for k in cpu1_imem_write.accessed cpu1_imem_fetch.accessed \
	         eth_imem_write_after_release.accessed eth_imem_fetch.accessed; do \
	    if grep -q "^$$k FAIL" "$$v"; then echo "  ok   $$k went RED, as it must"; \
	    else echo "  ** $$k did NOT go red -- the discriminating rung is not discriminating"; bad=1; fi; \
	done; \
	if grep -q "^eth_rom_port.accessed PASS" "$$v"; then \
	    echo ""; \
	    echo "  AND THE POINT: eth_rom_port.accessed PASSED on this image."; \
	    echo "  CPU0 left reset and fetched from its ROM out of a blank flash,"; \
	    echo "  exactly as main.c:403 intends. A gate grading the bootgate, or"; \
	    echo "  the eth_rom fetch, would have called this a boot."; \
	else \
	    echo ""; \
	    echo "  NOTE: eth_rom_port.accessed did not pass here, so this run does not"; \
	    echo "  also demonstrate the false-pass a bootgate-based gate would give."; \
	fi; \
	[ $$bad -eq 0 ] || exit 1; \
	echo ""; echo "OK: the shipped bench FAILS a blank flash. The gate discriminates."

#-----------------------------------------------------------------------------
# THE FALLBACK. bench/eth_chiplet_fp1505_forced.json models no flash and HOLDS
# chip_core_remap_ctrl[2] high. It is NOT in GLSN_ITEMS and `gls` never runs it.
# Its one job is to separate "CPU0 cannot fetch from eth_rom" from "CPU1 never
# released CPU0" when the shipped item goes red, in 8,000 cycles rather than
# 250,000. A PASS HERE IS NOT A BOOT.
#
# Built without the flash sources: with the attachment compiled in and no image
# staged, gls_flash_attach.sv $fatal's on purpose rather than let a missing file
# read back as blank flash.
#-----------------------------------------------------------------------------
FORCED_DIR  := $(BUILD_DIR)/gls-netlist-forced
FORCED_SPEC := $(THIS_DIR)/bench/eth_chiplet_fp1505_forced.json

.PHONY: forced-fallback
## Diagnostic only: run the FORCED bench in its own directory. Not a boot.
forced-fallback:
	@echo "== FALLBACK: CPU0's bootgate is FORCED. A pass here is NOT a handshake. =="
	$(MAKE) --no-print-directory gls-netlist-fp1505_cc \
	    GLSN_DIR=$(FORCED_DIR) \
	    GLSN_SPEC_fp1505_cc="$(FORCED_SPEC)" \
	    GLSN_COMPILE_ARGS_fp1505_cc= \
	    GLSN_STAGE_fp1505_cc="$(CC_FIRMWARE) $(ETH_FIRMWARE)" \
	    GLSN_EVIDENCE_fp1505_cc=

#-----------------------------------------------------------------------------
# NO FORCE, CHECKED MECHANICALLY RATHER THAN ASSERTED IN A COMMENT.
#
# The generator emits a `force` statement only from the spec's `forces` key and
# announces every one as `GLSN-FORCE:`, so the absence of a force is checkable in
# the artefacts a reader has: the generated bench, the transcript, and - if the
# toolkit is new enough to write it - a FORCES row in verdict.txt, the only one
# of the three that is PUBLISHED evidence.
#
# ANCHOR THE COLON. A newer toolkit writes `GLSN-FORCES: 0 no testbench override
# was applied in this run` on a CLEAN run, and a bare `grep GLSN-FORCE` matches
# that banner - so the check would fail exactly the runs it is meant to bless.
#-----------------------------------------------------------------------------
.PHONY: no-force
## Prove the shipped run contained no testbench override of a design signal.
no-force:
	@d=$(GLSN_DIR)/fp1505_cc; rc=0; \
	for f in gls_netlist_tb.v sim.log; do \
	    [ -s "$$d/$$f" ] || { echo "** $$d/$$f is missing -- nothing to check, which is not a pass"; rc=1; continue; }; \
	done; \
	[ $$rc -eq 0 ] || exit 1; \
	if grep -qE '^\s*force ' $$d/gls_netlist_tb.v; then \
	    echo "** the generated bench contains a force statement:"; \
	    grep -nE '^\s*force ' $$d/gls_netlist_tb.v; rc=1; \
	else echo "  ok   $$d/gls_netlist_tb.v declares no force"; fi; \
	if grep -q 'GLSN-FORCE:' $$d/sim.log; then \
	    echo "** the transcript announces a force:"; grep -n 'GLSN-FORCE:' $$d/sim.log | head; rc=1; \
	else echo "  ok   $$d/sim.log announces no force"; fi; \
	if grep -qE '^FORCES 0 ' $$d/verdict.txt 2>/dev/null; then \
	    echo "  ok   $$d/verdict.txt states FORCES 0 in the published evidence"; \
	elif grep -qE '^FORCES ' $$d/verdict.txt 2>/dev/null; then \
	    echo "** the verdict file declares forces:"; grep -E '^FORCES ' $$d/verdict.txt; rc=1; \
	else \
	    echo "  NOTE: this verdict.txt carries no FORCES row, so the force question is"; \
	    echo "        answered only by the transcript above. A toolkit that writes the"; \
	    echo "        row puts it in the PUBLISHED evidence instead."; fi; \
	if grep -q 'GLSN-FLASH: loaded' $$d/sim.log; then \
	    echo "  ok   $$d/sim.log records the bench-supplied flash image"; \
	else echo "  ** the transcript does not record a flash image being loaded"; rc=1; fi; \
	[ $$rc -eq 0 ] || exit 1; \
	echo "OK: CPU0 was released by the design, not by the bench"

.PHONY: collateral census build run gls help
collateral: gls-netlist-collateral
census:     gls-netlist-census
build:      gls-netlist-build-fp1505_cc
run:        gls-netlist-run-fp1505_cc
gls:        gls-netlist
help:       gls-netlist-help
