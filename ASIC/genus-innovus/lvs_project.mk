#-----------------------------------------------------------------------------
# project.mk.example — a worked example of the ASIC/lvs-flow contract.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# HOW TO USE THIS
#   1. Copy it next to your flow Makefile and rename it, e.g. lvs_project.mk
#   2. Edit the values below (they are tagged, so you know which are yours)
#   3. Add ONE line to your Makefile, at the END of its variable section:
#          include $(DESIGN_DIR)/lvs_project.mk
#      That gets you: lvs-preflight, lvs_source, lvs_batch/lvs, lvs-report,
#      lvs-rve, lvs-clean, lvs-help.
#
# EVERY LINE IS TAGGED
#   [PROJECT] this design. Changes when the design changes.
#   [PDK]     this process / library release. Same for every design on it.
#   [SITE]    where things are installed on this machine.
#   [FLOW]    a flow default. You will rarely touch these.
#
# WHY `?=` EVERYWHERE, AND WHY THE INCLUDE IS LAST
#   `?=` only assigns to a still-undefined variable. So: assign first, include
#   lvs.mk last. An assignment placed after the include is silently ignored,
#   because lvs.mk has already defined the variable. It also means every value
#   here can be overridden on the command line without editing the file:
#       make lvs_batch LVS_GDS=/tmp/experiment.gds
#
# THIS IS THE ONE FILE UNDER lvs-flow/ THAT CARRIES CONCRETE PATHS. It is a
# template to copy OUT of the flow, not flow logic — CONTRACT.md §7 keeps
# lvs.mk and run_lvs.sh free of site and project paths so they can be promoted
# into the shared toolkit unchanged.
#
# The worked values are the SoC Labs ethernet chiplet on TSMC 65nm LP, verified
# on disk 2026-08-10.
#-----------------------------------------------------------------------------

#-----------------------------------------------------------------------------
# 1. Where the flow lives, and where your design lives
#-----------------------------------------------------------------------------
# [PROJECT] Path from your makefile to the lvs-flow directory. Once this flow
#           is promoted into the shared toolkit it becomes something like
#           $(SOCLABS_ASIC_FLOW_DIR)/Mentor/lvs-flow.
LVS_FLOW_DIR ?= $(DESIGN_DIR)/../lvs-flow

# [PROJECT] The house directory variables. If your Makefile already defines
#           these (the SoC Labs Genus/Innovus flows do), these lines are no-ops
#           and you can delete them.
DESIGN_DIR ?= $(CURDIR)
OUT_DIR    ?= $(DESIGN_DIR)/outputs
WORK_DIR   ?= $(DESIGN_DIR)/work
LOG_DIR    ?= $(DESIGN_DIR)/logs

# [PROJECT] The top cell. Must be the name that appears in BOTH the GDS and the
#           post-P&R netlist — for a padded chiplet that is the PAD WRAPPER, not
#           the core. Every LVS artefact is named after it.
BLOCK ?= nanosoc_eth_chiplet_pads

#-----------------------------------------------------------------------------
# 2. The layout and the schematic
#
# These two MUST come from the same P&R database. The GDS is what the tool
# streamed; the netlist must be the POST-P&R one (Innovus `write_netlist`,
# usually <top>_pnr.v) — the synthesis netlist predates CTS and every post-route
# ECO, so it cannot match the layout and will mis-compare by thousands of nets.
#-----------------------------------------------------------------------------
# [PROJECT] Which P&R run to verify. Flows that archive each run to a
#           timestamped directory leave the live outputs/ empty or full of
#           derived streams — as here: outputs/ holds only logo-merged GDS, and
#           the signoff pair lives under runs/. lvs.mk resolves BOTH inputs and
#           the run directory from this one name, so layout and schematic can
#           never come from different runs by accident.
#
#           Leave it EMPTY to use $(OUT_DIR) — the normal case for a flow that
#           writes in place. Override per invocation:
#               make lvs_batch LVS_RUN=20260810T092257Z_derate-check3
#           `make lvs-preflight` lists the archived runs that carry a GDS.
#
#           A `latest` symlink, if your flow maintains one, works as a value —
#           but PIN THE TIMESTAMP for anything you intend to quote. `latest`
#           moves under you, and its run directory (lvs_run_latest) is reused,
#           so a second P&R run silently overwrites the first one's report.
LVS_RUN      ?= 20260810T065131Z_honest-full-pnr2
LVS_RUNS_DIR ?= $(DESIGN_DIR)/runs

# [FLOW] Derived from the above; set them directly only to verify a stream from
#        somewhere else entirely (a merged/logo GDS, a hand-built netlist).
#            LVS_GDS   ?= $(LVS_IN_DIR)/$(LVS_TOP).gds
#            LVS_SRC_V ?= $(LVS_IN_DIR)/$(LVS_TOP)_pnr.v
#        Note the SIGNOFF artefact is the plain stream, not the logo-merged one
#        — quote a verdict against the file you actually ran.

# [PROJECT] Printed by preflight when the GDS or netlist is missing. Name the
#           make target someone should run, in YOUR flow's words.
LVS_INPUT_HINT ?= run 'make pnr_route' (it streams the GDS and writes <top>_pnr.v)

#-----------------------------------------------------------------------------
# 3. The PDK
#-----------------------------------------------------------------------------
# [SITE] The PDK install root. The one path to change on a different machine;
#        everything below hangs off it. This project's ASIC/common.mk already
#        exports the same tree as TSMC_65_HOME.
# Derived from TSMC_65_HOME (ASIC/common.mk) rather than respelling the site
# mount: that file is the single place this repository names one.
PDK_ROOT ?= $(TSMC_65_HOME)

# [PDK] The foundry LVS rule deck. TSMC ships it per process option, under
#       Calibre/lvs/. Pick the one matching the process you taped out on (here
#       LP, and note it is under CMOS/LP/pdk/ — NOT the util/ tree the DRC deck
#       lives in). Find yours with:
#           find $(PDK_ROOT) -name 'calibre.lvs'
#       Read-only: the flow copies and rewrites it, never edits it in place.
# Resolved by pdk_paths.sh via ASIC/common.mk, so run_lvs.sh and this makefile
# cannot drift onto different decks. Same file as before.
LVS_DECK ?= $(PDK_LVS_DECK)

# [PDK] `source.added` — the deck's own SPICE stubs for foundry primitives
#       (RF/analogue devices), fed to `v2lvs -lsp`. Ships beside calibre.lvs.
#       Legitimately empty on PDKs that do not provide one.
LVS_SOURCE_ADDED ?= $(PDK_LVS_SOURCE_ADDED)

# [PDK] Standard-cell SIMULATION Verilog — the behavioural models, not the
#       liberty and not a netlist. In an academic Front-End PDK release this is
#       under .../<lib>_FE/TSMCHOME/digital/Front_End/verilog/<lib>/<lib>.v.
#       It is what gives v2lvs the leaf-cell names and port order. Space-separated
#       if your design maps into more than one cell library (RVT + HVT, 9-track
#       + 12-track, ...). Find yours with:
#           find $(PDK_ROOT) -path '*Front_End/verilog/*' -name '*.v'
# NOTE the _pwr.v suffix. This design's _pnr.v wires .VDD/.VSS on every
# standard-cell instance, so the leaf stubs must declare those pins too or
# Calibre rejects the whole source with "Wrong pin count" and never reaches a
# compare (measured: 256 errors). TSMC ships both variants side by side; pick
# the one matching your netlist. CONTRACT.md 6b.
# The two release directories in this path name what this site bought, so the
# path is globbed by pdk_paths.sh (exact-one-or-fail) rather than spelled.
# The _pwr.v BASENAME is kept -- it is the variant selector described above and
# carries no revision. Same file as before.
STDCELL_VLOG ?= $(PDK_STDCELL_VLOG)

# [PDK] The same thing for the IO drivers. Same Front_End/verilog/ shape, in the
#       IO library release rather than the standard-cell one. Leave EMPTY for a
#       padless macro — the flow handles that.
IO_VLOG ?= $(PDK_IO_VLOG)

#-----------------------------------------------------------------------------
# 4. Hard macros — the part of the run that is real verification
#
# These are REAL TRANSISTOR CDLs, one per compiled memory / ROM / analogue hard
# IP. They are never black-boxed: their interiors compare device-for-device
# against the macro GDS merged into the stream. If a macro is instanced and its
# CDL is NOT listed here, Calibre reports "No matching .SUBCKT" and the compare
# is worthless — so list EVERY macro the design instances, including ones only
# one instance deep.
#
# Where to find them: a memory compiler emits <name>.cdl beside <name>.lef and
# <name>.gds2. Cross-check the list against the GDS merge list your P&R config
# uses — the two must agree.
#-----------------------------------------------------------------------------
# [SITE] Compiled-memory and ROM output trees.
MEM_BASE    ?= /research/precompiled_mems/TSMC65
ROMLIBS_DIR ?= $(DESIGN_DIR)/../romlibs

# [PROJECT] The eight macros this chiplet instances: four register-file sizes,
#           two flash-cache arrays, and the two boot ROMs (one per CPU).
MACRO_CDLS ?= \
    $(MEM_BASE)/rf_01k/rf_01k.cdl \
    $(MEM_BASE)/rf_08k/rf_08k.cdl \
    $(MEM_BASE)/rf_16k/rf_16k.cdl \
    $(MEM_BASE)/rf_32k/rf_32k.cdl \
    $(MEM_BASE)/flash_cache_data/flash_cache_data.cdl \
    $(MEM_BASE)/flash_cache_tag/flash_cache_tag.cdl \
    $(LVS_ROM_CDL_DIR)/cc_rom/rom_via.cdl \
    $(LVS_ROM_CDL_DIR)/eth_rom/eth_rom_via.cdl

# [PROJECT] The two ROM CDLs are NOT read from $(ROMLIBS_DIR) directly. They are
#           DERIVED copies whose macro-internal virtual ground `VSS` is renamed
#           `VSS_ROMVIRT`, which is what makes `.GLOBAL VSS` below safe --
#           CONTRACT.md 6d prescribes exactly this ("point MACRO_CDLS at a
#           project-local copy of the CDL with the internal net renamed. Never
#           edit vendor or PDK collateral in place").
#
#           DERIVED, not checked in: the ROM CDL changes whenever the firmware
#           does, so a committed copy would silently go stale against the GDS it
#           is compared to. The rule below re-derives from $(ROMLIBS_DIR) on
#           every run and is order-only-safe (same mtime semantics as any
#           generated file).
#
#           THE RENAME IS EXACT. `\bVSS\b` matches the 524 bare-token uses and
#           nothing else: VSSE (the ROM's REAL ground pin, 738 uses) and the
#           IVSS* internal node names are untouched, and every changed line
#           differs only by the rename. Verified 2026-08-27 on both ROMs.
#           Only the SOURCE side is renamed; the ROM GDS/LEF are untouched,
#           because `.GLOBAL` is a SPICE construct with no layout counterpart.
LVS_ROM_CDL_DIR ?= $(DESIGN_DIR)/outputs/lvs_rom_cdl

$(LVS_ROM_CDL_DIR)/%.cdl: $(ROMLIBS_DIR)/%.cdl
	@mkdir -p $(dir $@)
	@sed -E 's/\bVSS\b/VSS_ROMVIRT/g' $< > $@.tmp
	@# Assert the rename did what it claims before letting it be consumed:
	@# no bare VSS survives, and VSSE survives untouched.
	@test "$$(grep -coE '\bVSS\b' $@.tmp)" = 0 || { \
	    echo "LVS ROM CDL: bare VSS survived the rename in $@"; rm -f $@.tmp; exit 1; }
	@test "$$(grep -coE '\bVSSE\b' $@.tmp)" = "$$(grep -coE '\bVSSE\b' $<)" || { \
	    echo "LVS ROM CDL: the rename altered VSSE in $@"; rm -f $@.tmp; exit 1; }
	@mv $@.tmp $@
	@echo "LVS ROM CDL: $< -> $@ (internal VSS renamed VSS_ROMVIRT)"

#-----------------------------------------------------------------------------
# 5. How the two sides are compared
#-----------------------------------------------------------------------------
# [PROJECT] Power and ground net names. These replace the deck's POWER_NAME /
#           GROUND_NAME placeholders, so they must be the names your P&R
#           configuration used — copy them from there rather than assuming
#           VDD/VSS. Here: ASIC/genus-innovus/scripts/config.tcl:117-118
#           (`set power_nets {VDD VDDIO}` / `set ground_nets {VSS VSSIO}`),
#           the IO ring having its own 2.5 V supply pair.
LVS_POWER  ?= VDD VDDIO
LVS_GROUND ?= VSS VSSIO

# [PROJECT] All four supplies are global. VSS was ABSENT from this list until
#           2026-08-27, and its absence was the single reason LVS could not
#           verify ground connectivity on this design at all.
#
#           WHY IT WAS ABSENT, and why that reasoning was sound as far as it
#           went: both boot ROMs bring their real supplies out as VDDE/VSSE and
#           use VSS internally as the power-gated virtual ground (structurally
#           confirmed -- `rom_via`'s top .SUBCKT ports are `VDDE VSSE ...`, no
#           VSS, and VSS is created locally inside rom_viaTILE_TOP /
#           rom_viaWDEC_64WL). `.GLOBAL` is unscoped, so `.GLOBAL VSS` with the
#           VENDOR CDLs merges that virtual ground with chip ground and
#           fabricates a short across the power gate, source-side only.
#           `make lvs-preflight` still detects that and names both ROMs; try it
#           by pointing MACRO_CDLS back at $(ROMLIBS_DIR).
#
#           WHY IT IS NOW PRESENT: CONTRACT.md 6d gives two remedies -- narrow
#           this list, which is "safe when the post-P&R netlist wires the
#           supplies explicitly on every instance", or rename the internal net
#           in a project-local CDL copy. This design took the first WITHOUT its
#           precondition: _pnr.v wires .VDD/.VSS on 186,598 instantiation lines
#           and NOT on 18,322 tool-inserted ones (FE_OFC*, FE_PHC*, LTIE_*,
#           CTS_*_buf_*). MACRO_CDLS above now takes the second remedy, so the
#           precondition no longer has to hold.
#
#           WHAT THE ABSENCE COST, measured on rc2-20260827 (same database, same
#           re-streamed GDS, source side the only variable):
#             - 18,322 one-pin orphan `<inst>/VSS` source nets. Exactly the
#               18,322 instances that lack .VSS(); `.GLOBAL VDD` rescued their
#               VDD by name, so /VDD orphans were 0 and /VSS orphans were 18,322.
#             - source-side `Net VSS` 18,322 connections SHORT of the layout's
#               (243,747 vs 262,069) -- one discrepancy carrying 18,330 rows.
#             - and the check's SIGN WAS INVERTED. A stranded VSS pin is an
#               exact match to its own one-pin phantom, so breaking a power pin
#               made LVS look CLEANER. On a deliberately-stranded database the
#               broken cell vanished from the report entirely.
#           With VSS global and the renamed ROM CDLs: orphans 18,322 -> 0, the
#           `Net VSS` discrepancy disappears, and on the stranded database the
#           broken pin appears as 1 of exactly 10 missing connections, named and
#           located. Nothing else moves -- 65 of 67 net discrepancies are
#           byte-identical, ERC is unchanged, and the two that vanish are the
#           flood and one phantom pairing it had caused.
LVS_GLOBAL_NETS ?= VDD VDDIO VSS VSSIO

# [PROJECT] Bond-pad / bump cells. These are LEF-only: no simulation model and
#           no CDL at all, so v2lvs cannot even emit a stub for them and the
#           SPICE source fails to READ without an explicit empty .SUBCKT.
#           Get the names from your bond-pad placement script or the pad LEF.
#           Empty for any design without flip-chip bumps or wire-bond pads.
BONDPAD_CELLS ?= PAD70GU_SL PAD70NU_SL

# [FLOW] Black-box every Front-End-only leaf on BOTH sides, so they compare by
#        port connectivity. This is the idea the whole flow rests on — see
#        CONTRACT.md §4. Set 0 only to reproduce the unboxed failure for
#        diagnosis; a 0 run is not a result.
LVS_BOX_LEAF ?= 1

# [PDK] Physical-only cells: present in the GDS, absent from write_netlist
#       output (fill, decap, antenna diodes, tap cells). They must stay UNBOXED
#       so their frames auto-flatten and match the netlist's silence about them
#       — box them and they become unmatched layout instances. Extend this
#       regex with your library's prefixes; check what P&R actually inserted:
#           grep -c '^ *FILLER' ... / your add_fillers + antenna-fix cell lists.
LVS_BOX_EXCLUDE_RE ?= ^(ANTENNA|DCAP|GDCAP|GFILL|OD25DCAP)

#-----------------------------------------------------------------------------
# 6. Tools
#-----------------------------------------------------------------------------
# [SITE] Bare names work when Calibre is on PATH. Give absolute paths on a host
#        where it is not (e.g. /eda/mentor/calibre/bin/v2lvs).
V2LVS   ?= v2lvs
CALIBRE ?= calibre

# [FLOW] Calibre -turbo CPU count. Defaults to nproc; lower it on a shared host
#        or where the site licence caps parallel CPUs.
# LVS_TURBO ?= 8

# [SITE] Licence-queue behaviour, same convention as the DRC flow. 0 (default)
#        queues for a free Calibre seat — right for an interactive or overnight
#        run, which should not throw away its setup because the pool was busy.
#        1 passes `-nowait`: fail immediately instead. Set it in CI, where a job
#        parked on a licence is worse than one that fails fast and retries.
# LVS_NOWAIT ?= 1

#-----------------------------------------------------------------------------
# 7. Pull in the flow. MUST BE LAST — see the `?=` note in the header.
#-----------------------------------------------------------------------------
#-----------------------------------------------------------------------------
# 7. PG-labelled stream for LVS  (make lvs_pg_gds, then make lvs_batch LVS_PG=1)
#-----------------------------------------------------------------------------
# A signoff GDS carries no power/ground text, so Calibre finds no supplies and
# the compare is meaningless (measured here: 4,084,884 unmatched layout
# objects). lvs_pg_emit.tcl re-streams the SAME routed database with SPNET text
# added -- read-only, no write_db, new filename, signoff GDS untouched.
# CONTRACT.md 6a.

# [SITE] The foundry GDS-out map. Must be the one P&R streams with:
#        scripts/4b_pnr_route_eval.tcl:225.
# Same resolution the P&R stream uses (PDK_GDSMAP), so "must be the one P&R
# streams with" is now enforced by sharing one value instead of by two
# hand-kept copies of a release-coded filename.
LVS_PG_MAP_IN ?= $(PDK_GDSMAP)

# [PROJECT] Hard-macro GDS to merge, matching MACRO_CDLS one-for-one.
LVS_PG_MERGE_GDS ?= \
    $(MEM_BASE)/rf_32k/rf_32k.gds2 \
    $(MEM_BASE)/rf_16k/rf_16k.gds2 \
    $(MEM_BASE)/rf_08k/rf_08k.gds2 \
    $(MEM_BASE)/rf_01k/rf_01k.gds2 \
    $(MEM_BASE)/flash_cache_data/flash_cache_data.gds2 \
    $(MEM_BASE)/flash_cache_tag/flash_cache_tag.gds2 \
    $(ROMLIBS_DIR)/cc_rom/rom_via.gds2 \
    $(ROMLIBS_DIR)/eth_rom/eth_rom_via.gds2

# [PROJECT] Only VDD and VSS are routed as special nets here (power_plan.tcl),
#           so only those two can be labelled. VDDIO/VSSIO are declared in
#           connect_global_net but have no top-level geometry -- the warning
#           this produces every run is correct and deliberate. Adding stripes
#           purely to satisfy LVS would be a real P&R change for no gain.
LVS_PG_EXPECT_NETS ?= $(LVS_POWER) $(LVS_GROUND)

# [PROJECT] Both default OFF in lvs.mk, which is right for a generic project and
#           wrong for this one. Without them `make lvs` compares the signoff GDS
#           with no pin text: no supplies (exit 6, NOT MEANINGFUL) and, even
#           past that, boxed cells extract with ZERO pins so ~633k routed nets
#           are dropped and no standard-cell routing is checked at all.
#           With both on: nets reconciled 62,483 -> 268,171, arbitrary matches
#           1,014 -> 44. Measured 2026-08-10. CONTRACT.md 6a, and the LEFPIN
#           note in lvs_pg_emit.tcl.
LVS_PG          ?= 1
LVS_PG_PIN_TEXT ?= 1

include $(LVS_FLOW_DIR)/lvs.mk

#-----------------------------------------------------------------------------
# 8. Derived inputs the flow above must build before it runs
#-----------------------------------------------------------------------------
# [PROJECT] MUST come AFTER the include: these targets are defined in lvs.mk,
#           and a prerequisite can only be added to a rule that already exists.
#           (The `?=` ordering warning at the top of this file is about
#           ASSIGNMENTS; a prerequisite-only rule here is the opposite case.)
#
#           Without this, the renamed ROM CDLs are never built and preflight
#           stops with `MISSING macro cdl` -- loud, but a step the operator
#           should not have to take by hand. Verified both ways 2026-08-27.
lvs-preflight lvs_batch: $(filter $(LVS_ROM_CDL_DIR)/%,$(MACRO_CDLS))
