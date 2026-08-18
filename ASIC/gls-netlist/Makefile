#-----------------------------------------------------------------------------
# ASIC/gls-netlist/Makefile - THIS PROJECT'S netlist-GLS table.
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
#
#-----------------------------------------------------------------------------
# WHY THE ROUTED PAD-RING NETLIST AND NOT THE SYNTHESIS ONE
#
# Two netlists were candidates:
#
#   build/fp1505/outputs/nanosoc_eth_chiplet_pads_pnr.v    routed, the current
#                                                          shipping candidate
#   build/full-20260814/outputs/..._gate.v                 synthesis, older run
#
# Both have the SAME top module and both contain the pad ring - the
# "core-level netlist without pads" the two are sometimes described as does not
# exist here; the synthesis netlist simply has no VDD/VDDIO/VSS/VSSIO PORTS on
# its top, because power ports are added later. Both instantiate the same nine
# TSMC IO driver cells and the same 12 memory macros.
#
# The one real difference is that the routed netlist also holds 82 bond pads
# (PAD70GU x42, PAD70NU x40) that P&R inserted and that have no Verilog model
# anywhere in this PDK - LEF only. That was the argument for preferring the
# synthesis netlist, and it does not survive contact with the file: Innovus
# writes them with an EMPTY PORT LIST,
#
#     PAD70GU BuPAD_HOST_IO_5 ();
#
# so they have no electrical connection to anything and an empty-module
# declaration for them cannot change behaviour. The census checks exactly that
# rather than taking it on trust (see netlist_census.py, THE STUB RULE), so the
# cost of choosing the routed netlist is two declarations that are mechanically
# proven inert - against the benefit of simulating the netlist that is actually
# being taped out, after placement, CTS and routing have rebuilt the clock tree
# and remapped a large fraction of the cells.
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
# paired with a revision-coded release directory is together an INVENTORY of
# the collateral this site is licensed to hold, which the licence does not
# permit publishing. ci/check-vendor-collateral.sh refuses both.
#
# Supply all four from the environment (see ASIC/asic-flows/site.env.example):
#   TSMC_65_HOME    the PDK root
#   MEM_BASE        the compiled-memory root
#   STDCELL_PKG / STDCELL_REL   the standard-cell package and release dirs
#   IOCELL_PKG  / IOCELL_REL    the IO-library package and release dirs
# THESE TWO ARE SITE FACTS AND THIS FILE MUST NOT CARRY THEM. Both are already
# defined, once, in ASIC/common.mk (TSMC_65_HOME:94, MEM_BASE:340) and EXPORTED,
# so any invocation that went through it inherits them. Invoked directly with
# neither set, this gate now fails NAMING the variable instead of building a
# path out of an empty string -- see the collateral guard below.
# MEM_BASE: READ FROM ITS ONE DEFINITION, NOT RETYPED AND NOT LEFT EMPTY.
# ASIC/common.mk:340 is where this repository defines the compiled-memory root,
# and it EXPORTS it -- so any invocation routed through common.mk inherits it.
# This gate is invoked DIRECTLY (`make -C ASIC/gls-netlist ...`), which is not
# such an invocation, so the export never reaches it and the bare default left
# every model path as "/rf_01k/rf_01k.v" -- absolute, plausible, non-existent.
# The vendor hook is right that the path must not be spelled in this public
# file, so resolve it from that single definition at use time. A pointer cannot
# drift; a second copy is a second thing to keep in step. Same reasoning as
# STDCELL_V/IOCELL_V above, which resolve through pdk_paths.sh.
# A command-line or environment MEM_BASE still wins, because `?=`.
# ONE HELPER, NOT THREE COPIES OF A sed. Reads a variable from its single
# definition in ASIC/common.mk. Every one of these is a SITE FACT that this
# public file must not spell, and that common.mk already spells exactly once.
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
# VDD/VSS are plumbed as inout ports through every level of the hierarchy down
# to the leaf cells. tcbn65lp.v - the ordinary library - defines every one of
# those cells BY NAME and none of them with power pins, so a module-name check
# passes completely and elaboration then fails on the first instance. Measured
# here 2026-08-18: 370/370 cell types "resolved", 318 cell types interface-
# mismatched. gls-netlist-census now catches it statically.
# RESOLVED, NOT SPELLED -- and not assembled from five separately-defaulted
# parts either. The vendor-collateral hook was right to strip the absolute site
# mounts out of this public file, but the replacement left TSMC_65_HOME,
# STDCELL_PKG, STDCELL_REL, IOCELL_PKG and IOCELL_REL all defaulting to EMPTY,
# so this line produced
#     /CMOS/LP/stclib/9-track/tcbn65lp-set//TSMCHOME/.../verilog//tcbn65lp_pwr.v
# -- an absolute path that looks plausible and does not exist. Measured
# 2026-08-18: `make collateral` failed on every model and this harness, which
# had booted CPU1 hours earlier, no longer ran from committed state.
#
# ASIC/tech_wrappers/tsmc65/scripts/pdk_paths.sh is this repository's own PDK
# resolver and already answers exactly these two questions. Using it removes
# FOUR variables rather than defaulting them, keeps no site layout in this file,
# and means a release-directory bump is picked up instead of silently mismatched.
# Same mechanism ASIC/eth-chiplet/design.mk uses for ARM_CLN65LP_TECH.
PDK_PATHS_SH ?= $(dir $(lastword $(MAKEFILE_LIST)))../tech_wrappers/tsmc65/scripts/pdk_paths.sh
STDCELL_V := $(shell TSMC_65_HOME='$(TSMC_65_HOME)' PHYS_IP='$(PHYS_IP)' \
                     bash $(PDK_PATHS_SH) stdcell-vlog 2>/dev/null)
IOCELL_V  := $(shell TSMC_65_HOME='$(TSMC_65_HOME)' PHYS_IP='$(PHYS_IP)' \
                     bash $(PDK_PATHS_SH) io-vlog 2>/dev/null)

# CAVEAT, and it must be carried into every claim made from a run of this:
# the simulation Verilog above is an OLDER CELL REVISION than the Liberty the
# design was timed against - an older stdcell release against a newer
# package, and likewise for the IO library. That makes this a FUNCTIONAL check and not a timing
# one. It says whether the logic works. It says nothing about whether it
# closes.

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
GLSN_ITEMS := fp1505_cc full0814_cc

GLSN_NETLIST_fp1505_cc := $(REPO)/ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads_pnr.v
GLSN_TOP_fp1505_cc     := nanosoc_eth_chiplet_pads
GLSN_SPEC_fp1505_cc    := $(THIS_DIR)/bench/eth_chiplet_fp1505_cc.json
# EVIDENCE INTO EACH ITEM'S OWN BUILD -- BUT ONLY THE EVIDENCE.
#
# scripts/ci/package_submission.sh collects exactly one tree, $(ASIC_DIR)/reports.
# Written under $(BUILD_DIR)/gls-netlist -- gitignored, outside every build tree
# -- this gate's proof reaches nobody, the hole the ROM lane closed on 2026-08-18.
#
# THE FIRST ATTEMPT AT THIS WAS WRONG AND THE MEASUREMENT IS WHY IT CHANGED.
# Pointing the RUN directory at reports/gls put 257 MB per item into a tree that
# gets packaged -- simv.daidir 164M, csrc 48M, and a 41M PG-completed netlist
# copy -- against about 28 KB of actual evidence. A run directory and an
# evidence directory are not the same thing: one is a simulator's working set,
# the other is the small set of files that answer "what ran, over what, and what
# did it decide". Only the second belongs in reports/.
#
# So the run stays in build/ and the gate PUBLISHES its evidence. The netlist
# path already names the run that produced it, so derive it: <run>/outputs/x.v
# -> <run>. `=` not `:=` -- these dereference GLSN_NETLIST_<n> declared further
# down, and an immediate assignment expands to nothing and yields "//reports/…",
# an absolute path that looks plausible and is not (measured here 2026-08-18).
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

# The bench $readmemb's this by basename out of the run directory.
GLSN_STAGE_fp1505_cc := $(CC_FIRMWARE) $(ETH_FIRMWARE)

# ARM_UD_* select the memory compilers' fast functional models and collapse
# their internal delays to zero. INITIALIZE_MEMORY zero-fills the RAM storage
# at time 0: without it the rf_* and flash_cache_* arrays come up X and that X
# reaches the reset network before reset can drive anything, so the design
# never leaves reset and it looks like a reset-tree bug.
#
# POWER_PINS is the macro the memory and ROM compilers gate their PG port list
# on. It must be set for the same reason the stdcell library above is the _pwr
# one: the ROM macros are instantiated with .VDDE()/.VSSE() and the RAMs with
# .VDD()/.VSS(). The IO pad cells are the exception - the _G cells this netlist
# uses carry no PG pins at all - so tphn65lpgv2od3_sl.v is used unmodified.
GLSN_DEFINES_fp1505_cc := ARM_UD_MODEL ARM_UD_DP ARM_UD_CP ARM_UD_SEQ INITIALIZE_MEMORY POWER_PINS

# NO -y SEARCH PATH, deliberately. A cell a -y path cannot find elaborates as
# an empty module with Z outputs and no diagnostic. Every model is named above
# and the census refuses anything left over.
GLSN_LIBDIRS_fp1505_cc :=

# PG COMPLETION. See the note on STDCELL_V above and flow/verify/gls/
# pg_complete.py. 22,469 instances in this file - every cell P&R inserted -
# are written without their supply pins while 171k others have them. The
# transform writes a COPY with those pins tied to a local supply1/supply0 and
# simulates the copy; ASIC/eth-chiplet/build/ is never written to.
#
# THIS IS A DEVIATION AND MUST BE DECLARED IN ANY RESULT QUOTED FROM IT. It is
# a narrow one - the cells are on the rails in the layout, LVS reads the DEF
# and not this file, and a tied supply is exactly what the vendor's non-PG
# model of the same cell does - but the file simulated is not byte-identical
# to the file being taped out, and build/gls-netlist/fp1505_cc/pg_complete.txt
# records precisely which instances differ.
GLSN_PG_PAIRS_fp1505_cc := VDD:VSS VDDE:VSSE

GLSN_BUILD_TIMEOUT_fp1505_cc := 7200
GLSN_RUN_TIMEOUT_fp1505_cc   := 7200

#-----------------------------------------------------------------------------
# ITEM 2: the 2026-08-14 SYNTHESIS netlist.
#
# Not a preference - a control, and a fallback with a reason. The routed
# netlist above is PG-INCONSISTENT: 171k of its instances are written with
# .VDD()/.VSS() and 22,469 - every cell P&R inserted, which is the whole clock
# tree buffering (CKND/CKBD), all 3040 tie cells, the hold-fix buffers and the
# delay cells - are written WITHOUT. Against the PG library those 22,469 cells
# have floating supplies, and every PG cell routes its output through a
# u_power_down UDP whose table says `? x ? : x`. So they all drive X, the clock
# tree included, and the design cannot be clocked at all. Against the non-PG
# library the other 171k instances do not elaborate. Neither library can
# simulate that file as written.
#
# This synthesis netlist has no such split: 0 stdcell and 0 macro instances
# carry PG, and the only .VDD() in the file are on the six PVDD1DGZ_G supply
# pads, which genuinely have a VDD port. It pairs with the ordinary library and
# needs no POWER_PINS.
#
# A RESULT HERE DOES NOT TRANSFER TO fp1505. It is a different and older build:
# placement, CTS and routing rebuilt the clock tree and remapped a large
# fraction of the cells (the drive-strength histograms differ throughout), and
# it is the routed netlist that is being taped out. What this item can do is
# prove the boot PATH exists in the design, and separate "the CPU cannot fetch"
# from "this particular file cannot be simulated".
#-----------------------------------------------------------------------------
# The non-PG twin is the SAME release directory, different basename. Derived
# from STDCELL_V rather than resolved again, so the two cannot drift onto
# different releases -- which is the mixed-vintage trap this project already
# lost time to on gate_power.v.
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

.PHONY: collateral census build run gls help
collateral: gls-netlist-collateral
census:     gls-netlist-census
build:      gls-netlist-build-fp1505_cc
run:        gls-netlist-run-fp1505_cc
gls:        gls-netlist
help:       gls-netlist-help
