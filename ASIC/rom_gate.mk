#-----------------------------------------------------------------------------
# ASIC/rom_gate.mk — content verification for the mask-programmed boot ROMs
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Included by ASIC/common.mk. Everything here is project data (paths, ROM
# identities) plus checks that need no EDA licence, so it stays project-side
# when the flow moves to the asic-toolkit: the toolkit owns the stage scripts,
# this owns "are the ROMs right".
#
# WHY THIS FILE EXISTS
# --------------------
# The boot ROMs are MASK PROGRAMMED. Wrong bits are a dead die, unfixable after
# tapeout. Until 2026-08-13 the only ROM check in the flow was `romlibs-verify`,
# which asserted that four files existed and were non-empty. It passed for
# months while:
#
#   * ASIC/romlibs/eth_rom held RANDOM contents  — word 0 is 0x5b679892, not a
#     4-byte-aligned Cortex-M initial stack pointer, and it matches none of the
#     .bintxt images in the tree;
#   * ASIC/romlibs/cc_rom held REAL, PLAUSIBLE FIRMWARE — a valid vector table,
#     zero-padding, the lot — but A DIFFERENT PROGRAM from the one its spec
#     names: only ~135 of its 512 words coincide with that image.
#
# The two failures do not look alike. A gate that asks "does this look random?"
# passes cc_rom; a gate that compares modification times catches neither
# reliably, because cc_rom is the wrong program rather than an old copy of the
# right one. THE ONLY ACCEPTABLE CRITERION IS EXACT EQUALITY, word for word,
# against the code file the firmware build produced.
#
# THE CAUSE, which is cheaper to catch than the symptom
# -----------------------------------------------------
# The eth code file comes from a CMake target that is explicitly NOT in the
# default build (nanosoc-multicore-system/firmware/bootloader/stage0_bootrom/
# CMakeLists.txt:53 — "# Not added to ALL"). Handed a missing or short code
# file, the Arm ROM compiler does NOT fail: it substitutes contents and emits a
# perfectly well-formed macro. So `romlibs-verify-static` below refuses to let a
# ROM build start, or a synthesis run proceed, when the code file is absent,
# empty, malformed, or shorter than the macro depth.
#
# THE TRAP IN THE OBVIOUS FIX
# ---------------------------
# "Just rebuild the ROMs" walks into a second defect: both macros on disk were
# compiled 512 words deep (A[8:0]) while both specs in ASIC/tech_wrappers/tsmc65
# say `words = 2048`, and both RTL wrappers drive an 11-bit address. Rebuilding
# from today's specs produces an 11-bit-address macro that no longer matches the
# placed LEF/GDS. `romlibs-verify-static` fails loudly on that four-way
# disagreement (spec / wrapper / macro / code file) rather than letting anyone
# rebuild into it.
#
# WHAT EACH TARGET IS FOR
# -----------------------
#   romlibs-verify          the gate. files + static + content. Runs BEFORE
#                           synthesis (ASIC/genus-innovus/Makefile: `syn`
#                           depends on romlibs-check, which calls this), so a
#                           bad ROM costs seconds, not a licence hour.
#   romlibs-verify-files    the four files Genus opens exist and are non-empty.
#                           THIS PROVES NOTHING ABOUT CONTENT — it is kept only
#                           because a missing .lib is a distinct, common failure
#                           that deserves its own message.
#   romlibs-verify-static   spec / wrapper / macro / code-file agreement, and
#                           the code file's own well-formedness. No checker, no
#                           licence, milliseconds.
#   romlibs-verify-content  the word-for-word comparison. Delegated to
#                           scripts/ci/rom_verify.py ($(ROM_VERIFY)).
#   romlibs-verify-gds      the same question asked of the MERGED STREAM: are
#                           the bits that reached the GDS the firmware? Needs a
#                           bit extractor ($(ROM_GDS_EXTRACT)).
#   romlibs-selftest        mutation test: proves this gate can FAIL, and can
#                           still PASS. A gate nobody has seen fail is a rumour.
#
# HOW THIS GATE IS BUILT, AND WHY IT LOOKS PARANOID
# -------------------------------------------------
#   * The checker's EXIT CODE IS NEVER THE VERDICT. Its JSON artefact must
#     exist, be non-empty, parse, name the exact rom-dir and code-file it was
#     pointed at, and carry a verdict. Exit code and verdict must AGREE — if
#     they disagree the gate fails, because one of them is lying.
#   * A MISSING INPUT IS A FAILURE, NEVER A SKIP. No checker, no code file, no
#     spec, no JSON: all hard failures. The classic way a gate like this dies
#     silently is a path that resolves to nothing, so it finds no files and
#     therefore reports no problems.
#   * NOTHING IS GATED ON A BARE COUNT. Every assertion names the object it is
#     about: this ROM, this word index, this spec key, this file.
#-----------------------------------------------------------------------------

# The checker (owned by scripts/ci/rom_verify.py). `?=` so a test harness can
# point at another copy — it cannot be defeated that way, because a stand-in
# that does not write the JSON artefact fails the post-conditions below.
ROM_VERIFY      ?= $(NANOSOC_ETH_CHIPLET_HOME)/scripts/ci/rom_verify.py

# THE STREAM-OUT GATE IS THE TOOLKIT'S NOW. This file keeps the TABLE.
#
# The mechanism -- extract, prove the artefacts belong to THIS stream, prove the
# macro is actually instanced, stamp a verdict, collect the evidence -- moved to
# ASIC/asic-toolkit/mk/rom.mk on 2026-08-18, because none of it is about this
# die. What stays here is what only this project can say: which ROMs exist,
# where their code files are, and what the stream being gated actually IS.
#
# The extractor moved with it, to
# $(ASIC_TOOLKIT_DIR)/scripts/asic-flow-rom-gds-bits. scripts/ci/rom_gds_bits.py
# is now a FORWARDER to that one program, so the path in docs/tapeout/34 still
# works and there is exactly ONE implementation. Two copies of a decoder is a
# trap this tree has already been caught in.
ASIC_TOOLKIT_DIR ?= $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/asic-toolkit
ROM_TOOLKIT_MK   ?= $(ASIC_TOOLKIT_DIR)/mk/rom.mk
ROM_GDS_EXTRACT  ?= $(ASIC_TOOLKIT_DIR)/scripts/asic-flow-rom-gds-bits

# ── THIS FILE OWNS THE ROM GATE HERE, SO THE TOOLKIT'S COPY STAYS OUT ──────
#
# The toolkit's mk/flow.mk includes mk/rom.mk BY DEFAULT (it used to be opt-in,
# which is how this fork came to exist unnoticed in the first place). Both files
# define `rom-vars`, and mk/rom.mk also defines `rom-compiler-stage`, which
# ASIC/common.mk:444 defines too. GNU make does not refuse a redefinition: it
# prints "overriding recipe for target" and silently keeps the LAST one - and
# the toolkit's is last, because design.mk includes common.mk (and so this
# file) at line 65 and mk/flow.mk at line 522.
#
# MEASURED, with this line removed:
#   mk/rom.mk:533: warning: overriding recipe for target 'rom-vars'
#   ASIC/rom_gate.mk: warning: ignoring old recipe for target 'rom-vars'
#   mk/rom.mk:939: warning: overriding recipe for target 'rom-compiler-stage'
#   ASIC/common.mk:444: warning: ignoring old recipe for target 'rom-compiler-stage'
# `rom-vars` happens to print identically (the toolkit's recipe reads THIS
# file's table), but `rom-compiler-stage` is a different recipe entirely, and a
# silently substituted ROM compiler stage is not something to discover later.
#
# So this project declares that it supplies the `rom` fragment itself. DELETE
# THIS LINE when the fork below is retired in favour of $(ROM_TOOLKIT_MK), which
# is the whole point of keeping the two in step - and re-run
# `make -C ASIC/eth-chiplet rom-vars` when you do: it must stay warning-free.
ASIC_FLOW_SKIP_MK += rom

# ── THE RUN'S OWN TREE, DERIVED FROM THE STREAM UNDER TEST ─────────────────
#
# Two defects share one cause, and one derivation closes both. Found 2026-08-18
# by two sessions independently.
#
# 1. GEOMETRY CAME FROM A TREE THAT IS NOT THE RUN'S. This gate extracts
#    <words> x <bits> from the stream and takes those numbers from the macro's
#    metadata -- but ROMLIBS_DIR points at the SHARED ASIC/romlibs, not at the
#    macros this run actually merged. They are byte-identical today (md5'd, both
#    trees), so the result stands; the safety rests on a coincidence. The day
#    they diverge, the gate extracts another macro's geometry and PASSES.
#
# 2. THE EVIDENCE WAS UNREACHABLE. build/rom_verify is gitignored AND sits at
#    the repo root, outside $(ASIC_DIR) -- and scripts/ci/package_submission.sh
#    collects exactly one reports tree, $(ASIC_DIR)/reports. So a submission
#    bundle could be assembled, pass its own checks, and contain NO evidence
#    that the mask-programmed boot ROMs were ever compared against the firmware.
#    The ROMs are the one thing on this die that cannot be fixed after tapeout.
#
# THE STREAM NAMES ITS OWN RUN. Gating .../build/<tag>/outputs/<block>.gds means
# the run root is .../build/<tag>, which holds both that run's romlibs/ and the
# reports/ tree the packager collects. Nothing else has to be passed, and no
# RUN_DIR is needed here (it is only defined in eth-chiplet/design.mk, which is
# not in scope in a common.mk context -- that is what blocked this before).
#
# CONSERVATIVE BY CONSTRUCTION. Every redirect is guarded on the artefact
# actually existing, and falls back to today's behaviour otherwise. With no
# ROM_GDS -- i.e. `romlibs-verify`, the paper gate -- nothing changes at all.
ROM_GDS_RUN_ROOT   := $(if $(strip $(ROM_GDS)),$(abspath $(dir $(ROM_GDS))/..),)

# Trust the run's romlibs only if BOTH macros' metadata is really there. A
# partial tree would otherwise fail the gate on a stream that is fine.
ROM_RUN_ROMLIBS    := $(if $(ROM_GDS_RUN_ROOT),$(ROM_GDS_RUN_ROOT)/romlibs,)
# $(strip) IS LOAD-BEARING. A backslash-continuation inside $(if ...) keeps the
# leading whitespace of the next line, so the unstripped form yields " /path"
# and every ROM_DIR_<r> below becomes " /path/<rom>". Caught 2026-08-18 by
# reading `rom-vars` output rather than assuming the expansion was clean.
ROMLIBS_EFFECTIVE  := $(strip $(if $(and \
                        $(wildcard $(ROM_RUN_ROMLIBS)/eth_rom/eth_rom_via.memlib),\
                        $(wildcard $(ROM_RUN_ROMLIBS)/cc_rom/rom_via.memlib)),\
                        $(ROM_RUN_ROMLIBS),$(ROMLIBS_DIR)))

# ── AND ASSERT IT, RATHER THAN LEAVING THE KNOB FOR SOMEONE TO REMEMBER ────
#
# ROM_GDS_GEOM_ROOT makes the geometry source a CHECK instead of a printed note.
# It is set here only when the geometry actually came from the run's own tree --
# if the guards above fell back to the shared ASIC/romlibs, declaring the run
# root would fail every ROM for being outside it, which is a false failure and
# would train someone to switch the assertion off.
#
# Proven to discriminate, 2026-08-18, both directions on the real fp1505 stream:
#   correct run tree -> "geometry containment asserted for memlib against .../fp1505", PASS
#   wrong run tree   -> "the memlib ... is OUTSIDE the declared run tree", FAIL
# The toolkit only applies containment to run-emitted artefacts (the .memlib);
# the .spec is a checked-in request shared by every run, is recorded in the
# manifest, and is answered for by rom_verify.py's provenance check instead.
ROM_GDS_GEOM_ROOT ?= $(strip $(if $(filter $(ROM_RUN_ROMLIBS),$(ROMLIBS_EFFECTIVE)),\
                       $(ROM_GDS_RUN_ROOT),))

# Evidence: into the run's own reports/ when we are gating that run's stream, so
# the packager collects it BY CONSTRUCTION rather than by someone remembering an
# override. Falls back to the old gitignored location otherwise -- which is
# still where the paper gate writes, and is still not collected. Guarded on
# outputs/ so an arbitrary --gds path cannot make us scatter directories.
ROM_VERIFY_DIR  ?= $(strip $(if $(wildcard $(ROM_GDS_RUN_ROOT)/outputs),\
                     $(ROM_GDS_RUN_ROOT)/reports/rom,\
                     $(NANOSOC_ETH_CHIPLET_HOME)/build/rom_verify))

# `block` (default) — an UNVERIFIED stream-out gate fails, exactly like a
#                     detected mismatch. "We could not check" is not a pass.
# `report`          — an UNVERIFIED verdict prints and does not fail. A DETECTED
#                     MISMATCH STILL FAILS IN THIS MODE. Use only while the
#                     extractor is being landed, and never in CI.
ROM_GDS_GATE    ?= block

# ── The ROMs on this die. Both of them. ────────────────────────────────────
# CPU0 (ethernet subsystem) and CPU1 (chip-control core). Adding a third ROM is
# one line here plus its ROM_*_<name> values.
ROMS := eth cc

# -- What the stream-out gate needs to know about THIS die -------------------
#
# WHICH ARTEFACT. This project deliberately produces two GDSs that are not the
# same file: the un-logoed SIGNOFF stream at build/<tag>/outputs/<block>.gds,
# which the DRC and LVS numbers are quoted against, and a logo-merged SUBMISSION
# stream selected by SUBMIT_GDS, which is what actually ships. The logo is
# merged in a SEPARATE step after write_stream, precisely so a DRC count can
# never be quoted against the wrong file -- and a bundle has already once been
# built carrying the wrong one.
#
# The defaults below describe THE WIRED INVOCATION: ASIC/genus-innovus/Makefile
# runs this gate on the un-logoed signoff stream after route and after restream.
# That is a true statement about what the flow gates today, not a guess about
# whatever path a human passes on the command line -- which is why the basis
# records where the label comes from rather than just asserting it.
#
# GATING THE STREAM THAT SHIPS is one line, and it is the line a promotion or a
# submission step must use:
#
#   make -f ASIC/common.mk romlibs-verify-gds ROM_GDS=<logo-merged>.gds \
#        ROM_GDS_CLASS=submission ROM_GDS_SHIPS=yes ROM_GDS_REQUIRE_SHIPPING=1
#
# No fp1505 logo-merged stream exists yet, so if fp1505 is promoted the logo
# merge happens afterwards and THAT stream will never have been through this
# gate. The ROM bits almost certainly survive a logo merge. "Almost certainly"
# is the phrase this gate exists to remove.
ROM_GDS_CLASS       ?= signoff
ROM_GDS_CLASS_BASIS ?= declared:genus-innovus gates the un-logoed stream at build/<tag>/outputs
ROM_GDS_SHIPS       ?= no

# Both ROMs are instanced exactly once on this die.
ROM_GDS_PLACEMENTS_eth ?= 1
ROM_GDS_PLACEMENTS_cc  ?= 1

# The compiler's own content view, for the independence report. Measured
# 2026-08-18: *_verilog.rcf and the .bintxt are BYTE-IDENTICAL for both ROMs,
# because the compiler produced one from the other. That does NOT weaken the
# stream-out gate -- its other side is decoded out of the GDS -- but it does
# mean any gate whose two sides are the .rcf and the .bintxt is a mirror, and
# that belongs on the record rather than being rediscovered.
ROM_CODE_PEER_eth ?= $(ROM_DIR_eth)/eth_rom_via_verilog.rcf
ROM_CODE_PEER_cc  ?= $(ROM_DIR_cc)/rom_via_verilog.rcf

# -- Declared sim/silicon divergence -----------------------------------------
# The eth simulation boot ROM is a gitignored MUTABLE SLOT materialised per
# environment: 55 cocotb environments install a smoke variant and 2 install the
# silicon image, because the silicon bootloader requires a QSPI XiP handshake
# that IMEM-preload environments do not model. Regenerating the slot would
# self-revert on the next build and would be a false green. So this is a
# DECLARED EXCEPTION, hash-scoped, and it stays visible as [ALLOW-LISTED].
#
# Reason and evidence: docs/tapeout/44-eth-rom-sim-divergence.md
ROM_SIM_ALLOW_eth        ?= sha256:9d5fa954ceb646f51aaf5f40f615380dc4296760ca533846ebb553d20434d504
ROM_SIM_ALLOW_REASON_eth ?= sim ROM is a per-environment smoke image; the silicon bootloader needs a QSPI XiP handshake. Evidence: docs/tapeout/44-eth-rom-sim-divergence.md
ROM_SIM_ALLOW_cc         ?=
ROM_SIM_ALLOW_REASON_cc  ?=

# ── Geometry for the SIMULATION readback gate (mk/gls.mk, `make gls-rom`) ───
#
# DERIVED FROM THE ONE EXISTING SPELLING, NOT RE-STATED. $(ROM_EXPECT_WORDS)
# lives in rom_build.mk and is already cross-checked against $(ROM_ADDR_BITS)
# there, with an $(error) if the two disagree -- because "two spellings of one
# fact" is exactly how the 512-vs-2048 disagreement survived on this project.
# A third independent copy here would re-open that hole in a new place.
#
# The gate REFUSES to infer these from the .rcf, and that refusal is the point:
# a truncated content file would otherwise define a shorter ROM and then match
# itself perfectly. Measured 2026-08-17 - an under-declared depth of 256 against
# these 512-word macros passed a .rcf whose top half was garbage, and printed
# "every word matches the firmware". Declared here, cross-checked against the
# artefacts by the runner before any simulator starts.
#
# Both ROMs are the same shape. A die whose ROMs differ sets them per ROM.
#
# `$$` IS LOAD-BEARING. common.mk includes THIS file at :605 and rom_build.mk -
# where $(ROM_EXPECT_WORDS) is defined - at :613, eight lines later. A plain
# `$(ROM_EXPECT_WORDS)` here is expanded by $(eval) immediately, finds nothing,
# and assigns EMPTY; `?=` then treats the variable as set, so nothing later
# fixes it and `make gls-rom` reports the depth as undeclared. Escaping the
# dollar defers expansion to use time, by which point rom_build.mk has been
# read. Measured 2026-08-17: the un-escaped form left GLS_ROM_WORDS_eth empty
# while GLS_ROM_BITS_eth resolved fine, because ROM_EXPECT_BITS is defined on
# the line above and ROM_EXPECT_WORDS is not.
ROM_EXPECT_BITS ?= 32
$(foreach r,$(ROMS),$(eval GLS_ROM_WORDS_$(r) ?= $$(ROM_EXPECT_WORDS)))
$(foreach r,$(ROMS),$(eval GLS_ROM_BITS_$(r)  ?= $$(ROM_EXPECT_BITS)))

# ROM_SIM_<r> is the SIMULATION boot ROM — the behavioural .sv the RTL flows
# and the FPGA build read. The checker compares it too, because "the ASIC ROM
# and the ROM everyone simulates hold different programs" is a defect nobody
# would otherwise see. A difference is a WARNING, not a failure: sim and ASIC
# may legitimately diverge. Set ROM_SIM_<r>=none to state that explicitly —
# it becomes --no-sim-check, which the checker prints. Leaving the file simply
# missing is NOT that statement, and fails.
ROM_SIM_RTL_DIR ?= $(NANOSOC_MULTICORE_HOME)/src/rtl/bootrom

# ROM_WRAP_<r> — the ASIC RTL wrapper that binds the hard macro.
#
# THESE MUST BE THE SUBMODULE COPIES UNDER nanosoc-multicore-system, because
# THOSE ARE THE FILES THE FLIST COMPILES (nanosoc_multicore_asic.flist, and the
# build/chip/flist/soc.flist generated from it). Do not "simplify" these back to
# $(NANOSOC_ETH_CHIPLET_HOME)/ASIC/tech_wrappers/tsmc65/ — that is the mistake
# this comment exists to prevent.
#
# Until 2026-08-14 they pointed at a pair of STALE HAND-COPIES that used to sit
# in ASIC/tech_wrappers/tsmc65/. Those copies still declared word_addr[10:0] and
# .TA(11'd0) into a 512-word A[8:0] macro, long after the real wrappers were
# fixed. The gate therefore reported two geometry FAILURES PER ROM against RTL
# THAT NOTHING BUILDS, while the wrappers that do get compiled were correct.
# Four red lines, zero real defects — and, far worse, the reverse was equally
# possible: a genuine width defect in the compiled wrapper would have been
# invisible, because the gate was not reading that file. The stale copies were
# deleted in the same change; ASIC/tech_wrappers/tsmc65 still legitimately owns
# the ROM .spec files, the pad wrapper and the pad LEF, just not these two.
#
# ROM_FLIST below turns this from a convention into an assertion: rom-static-%
# fails if ROM_WRAP_<r> is not a file the flist actually compiles.
ROM_FLIST ?= $(NANOSOC_MULTICORE_HOME)/flist/nanosoc_multicore_asic.flist
ROM_WRAP_DIR ?= $(NANOSOC_MULTICORE_HOME)/syn/asic/tech_wrappers/tsmc65

ROM_LABEL_eth  := eth_rom
ROM_DIR_eth    := $(ROMLIBS_EFFECTIVE)/eth_rom
ROM_CODE_eth   := $(ETH_BINTXT)
ROM_SPEC_eth   := $(ETH_ROM_SPEC)
ROM_WRAP_eth   := $(ROM_WRAP_DIR)/eth_ss_bootrom.sv
ROM_INST_eth   := eth_rom_via
ROM_MEMLIB_eth := $(ROM_DIR_eth)/eth_rom_via.memlib
ROM_SIM_eth    := $(ROM_SIM_RTL_DIR)/eth_ss_bootrom.sv
ROM_REGION_eth := $(ROM_SIM_RTL_DIR)/nanosoc_region_bootrom.v

ROM_LABEL_cc   := cc_rom
ROM_DIR_cc     := $(ROMLIBS_EFFECTIVE)/cc_rom
ROM_CODE_cc    := $(CC_BINTXT)
ROM_SPEC_cc    := $(CC_ROM_SPEC)
ROM_WRAP_cc    := $(ROM_WRAP_DIR)/nanosoc_bootrom_chip_core.sv
ROM_INST_cc    := rom_via
ROM_MEMLIB_cc  := $(ROM_DIR_cc)/rom_via.memlib
ROM_SIM_cc     := $(ROM_SIM_RTL_DIR)/nanosoc_bootrom_chip_core.sv
ROM_REGION_cc  := $(ROM_SIM_RTL_DIR)/nanosoc_region_bootrom.v

# The four files Genus opens through config.tcl's lib_search_path_list. Named
# here so the "which file is missing" message stays specific.
ROM_GENUS_FILES := $(ROM_DIR_cc)/rom_via_ss_1p08v_1p08v_125c.lib \
                   $(ROM_DIR_cc)/rom_via.lef \
                   $(ROM_DIR_eth)/eth_rom_via_ss_1p08v_1p08v_125c.lib \
                   $(ROM_DIR_eth)/eth_rom_via.lef

.PHONY: romlibs-verify romlibs-verify-files romlibs-verify-static \
        romlibs-verify-content romlibs-verify-gds romlibs-selftest rom-vars

## make -f common.mk rom-vars — the ROM table, machine readable, one line per
## ROM: name|label|rom_dir|code_file|memlib|instance|json|gds_bits
## So a CI check (ci/signoff.yaml) or a toolkit-side wrapper can re-read the
## evidence without a second copy of these paths drifting from this one.
rom-vars:
	@$(foreach r,$(ROMS),echo "$(r)|$(ROM_LABEL_$(r))|$(ROM_DIR_$(r))|$(ROM_CODE_$(r))|$(ROM_MEMLIB_$(r))|$(ROM_INST_$(r))|$(ROM_VERIFY_DIR)/$(r).json|$(ROM_VERIFY_DIR)/$(r)_gds.bits";)

#-----------------------------------------------------------------------------
# The gate
#-----------------------------------------------------------------------------
# All three sub-gates RUN, then the verdict. Not `romlibs-verify: a b c`, which
# would stop at the first failure and hide the other two — and the two ROMs on
# this die fail differently, so a partial picture is a misleading one.
romlibs-verify:
	@mkdir -p $(ROM_VERIFY_DIR)
	@# The pass stamp is deleted FIRST. It records a pass that happened; it must
	@# never survive a run that did not happen or did not pass.
	@rm -f $(ROM_VERIFY_DIR)/last_pass.txt
	@fail=""; for g in files static content; do \
	    $(MAKE) -f $(COMMON_MK) --no-print-directory romlibs-verify-$$g || fail="$$fail $$g"; \
	done; \
	echo ""; \
	if [ -n "$$fail" ]; then \
	    echo "FAIL: ROM GATE FAILED:$$fail"; \
	    echo "      The boot ROMs are MASK PROGRAMMED. Nothing downstream — not"; \
	    echo "      synthesis, not P&R, not LEC, not DRC — looks at their contents."; \
	    exit 1; \
	fi; \
	{ echo "ROM gate passed $$(date -u +%Y-%m-%dT%H:%M:%SZ) on $$(hostname)"; \
	  echo "code files verified against (sha256):"; \
	  sha256sum $(foreach r,$(ROMS),$(ROM_CODE_$(r))); \
	} > $(ROM_VERIFY_DIR)/last_pass.txt; \
	$(MAKE) -f $(COMMON_MK) --no-print-directory romlibs-content-hashes || exit 1; \
	echo "OK: ROM gate passed — files, spec/wrapper/macro agreement, and content"; \
	echo "    stamp: $(ROM_VERIFY_DIR)/last_pass.txt"

#-----------------------------------------------------------------------------
# romlibs-content-hashes — the flat file every P&R run manifest reads
#
# The toolkit's stage scripts write a PROVENANCE block into every stage manifest
# (flow/common/provenance.tcl), and a boot ROM's content hash is one of its
# fields — because two builds of "the same design" whose ROMs differ are not the
# same design, and a comparison between their reports is meaningless. That block
# READS this file. It does not compute a hash of its own: a second implementation
# of "what is in this ROM" is a second thing to be wrong, and the two would agree
# until the day they did not.
#
# So this is an EXTRACTION from the JSON the checker has already written — the
# PHYSICAL bit-cell programming decoded out of the transistor-level netlist,
# which is the only view that describes silicon.
#
# Written ONLY after the gate has passed. A tree whose ROM gate has not passed
# has no file here, every stage manifest records UNVERIFIED for its ROMs, and
# `asic-flow-compare-runs` REFUSES to diff that run against any other. That is
# the point, not a side effect: a build on unverified ROMs must not be quietly
# compared against one on verified ROMs, and it has been.
#
# Mirrors the toolkit's mk/rom.mk `rom-content-hashes`. This file is a project-
# side fork of that one; keep the two in step.
#
# Format, one line per ROM:  <name> <content sha256> <code-file sha256>
#-----------------------------------------------------------------------------
.PHONY: romlibs-content-hashes
romlibs-content-hashes:
	@mkdir -p $(ROM_VERIFY_DIR)
	@rc=0; \
	{ echo "# ROM content hashes, extracted from the ROM gate's own JSON."; \
	  echo "# name  content_sha256  code_file_sha256"; \
	} > $(ROM_VERIFY_DIR)/rom_content_hashes.txt; \
	for r in $(ROMS); do \
	    j=$(ROM_VERIFY_DIR)/$$r.json; \
	    test -s "$$j" || { echo "FAIL: no $$j — cannot extract a content hash the gate did not write"; rc=1; continue; }; \
	    python3 -c 'import json,sys;\
d=json.load(open(sys.argv[1]));\
roms=d.get("roms",[]);\
m=[x for x in roms if x.get("name")==sys.argv[2]] or (roms if len(roms)==1 else []);\
sys.exit("no rom entry for %s" % sys.argv[2]) if not m else None;\
r=m[0];\
c=r.get("physical",{}).get("stats",{}).get("content_sha256");\
f=r.get("code_file",{}).get("sha256");\
sys.exit("no physical content_sha256 — the checker did not decode the CDL") if not c else None;\
sys.exit("no code_file sha256") if not f else None;\
print("%s %s %s" % (sys.argv[3], c, f))' \
	        "$$j" "$(ROM_LABEL_$(r))" "$$r" \
	        >> $(ROM_VERIFY_DIR)/rom_content_hashes.txt \
	      || { echo "FAIL: could not extract a content hash for '$$r' from $$j"; rc=1; }; \
	done; \
	if [ $$rc -ne 0 ]; then \
	    rm -f $(ROM_VERIFY_DIR)/rom_content_hashes.txt; \
	    echo "      Removed the hash file rather than leave a partial one: a run"; \
	    echo "      manifest naming one of two ROMs compares equal against a run"; \
	    echo "      with a different second one."; \
	    exit 1; \
	fi; \
	echo "    content hashes: $(ROM_VERIFY_DIR)/rom_content_hashes.txt"

romlibs-verify-files:
	@echo "== ROM gate 1/3: the files Genus opens =="
	@rc=0; for f in $(ROM_GENUS_FILES); do \
	    if [ -s "$$f" ]; then echo "  OK:   $$f"; else echo "  FAIL: MISSING $$f"; rc=1; fi; \
	done; \
	if [ $$rc -ne 0 ]; then echo "FAIL: Genus cannot open the ROM libraries listed above."; fi; \
	exit $$rc

#-----------------------------------------------------------------------------
# Gate 2 — static agreement. No checker, no licence, no EDA tool.
#-----------------------------------------------------------------------------
romlibs-verify-static:
	@echo "== ROM gate 2/3: spec / wrapper / macro / code-file agreement =="
	@fail=""; for r in $(ROMS); do \
	    $(MAKE) -f $(COMMON_MK) --no-print-directory rom-static-$$r || fail="$$fail $$r"; \
	done; \
	if [ -n "$$fail" ]; then echo "FAIL: ROM static checks failed for:$$fail"; exit 1; fi; \
	echo "OK: static checks passed for: $(ROMS)"

rom-static-%:
	@test -n "$(ROM_DIR_$*)" || { echo "FAIL: unknown ROM '$*' — known ROMs: $(ROMS)"; exit 1; }
	@test -s "$(ROM_SPEC_$*)" || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] no spec at $(ROM_SPEC_$*) — a gate with no reference is not a check"; exit 1; }
	@test -s "$(ROM_CODE_$*)" || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] no code file at $(ROM_CODE_$*)"; \
	    echo "      This is the DEFECT, not a missing prerequisite: the ROM compiler does"; \
	    echo "      not fail on an absent code file, it substitutes contents."; \
	    echo "      eth: make -f common.mk eth-bintxt   (its CMake target is not in ALL)"; \
	    echo "      cc : build the bootloader firmware"; exit 1; }
	@test -s "$(ROM_WRAP_$*)" || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] no RTL wrapper at $(ROM_WRAP_$*)"; exit 1; }
	@# A flist that is missing is NOT a skip: without it the wrapper-vs-flist
	@# assertion below cannot run, and that assertion is the only thing stopping
	@# this gate from grading a file nothing compiles.
	@test -s "$(ROM_FLIST)" || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] no flist at $(ROM_FLIST) — without it this gate"; \
	    echo "      cannot prove it is reading the wrapper the design actually builds."; exit 1; }
	@NANOSOC_MULTICORE_HOME="$(NANOSOC_MULTICORE_HOME)" \
	 NANOSOC_ETH_CHIPLET_HOME="$(NANOSOC_ETH_CHIPLET_HOME)" \
	 printf '%s\n' "$$ROM_STATIC_ASSERT" | \
	 NANOSOC_MULTICORE_HOME="$(NANOSOC_MULTICORE_HOME)" \
	 NANOSOC_ETH_CHIPLET_HOME="$(NANOSOC_ETH_CHIPLET_HOME)" python3 - \
	    "$(ROM_LABEL_$*)" "$(ROM_SPEC_$*)" "$(ROM_CODE_$*)" "$(ROM_WRAP_$*)" \
	    "$(ROM_MEMLIB_$*)" "$(ROM_INST_$*)" "$(ROM_FLIST)"

#-----------------------------------------------------------------------------
# Gate 3 — content. Word for word, against the code file.
#-----------------------------------------------------------------------------
romlibs-verify-content:
	@echo "== ROM gate 3/3: ROM contents vs the firmware code file =="
	@test -f "$(ROM_VERIFY)" || { \
	    echo "FAIL: no ROM content checker at $(ROM_VERIFY)."; \
	    echo "      A gate that cannot run is a FAILURE, not a skip: without it nothing"; \
	    echo "      in this flow compares a single ROM word against the firmware."; \
	    exit 1; }
	@mkdir -p $(ROM_VERIFY_DIR)
	@fail=""; for r in $(ROMS); do \
	    $(MAKE) -f $(COMMON_MK) --no-print-directory rom-verify-$$r || fail="$$fail $$r"; \
	done; \
	if [ -n "$$fail" ]; then \
	    echo ""; \
	    echo "FAIL: ROM CONTENT IS WRONG FOR:$$fail"; \
	    echo "      These ROMs are MASK PROGRAMMED. Wrong bits are a dead die."; \
	    echo "      Evidence: $(ROM_VERIFY_DIR)/<rom>.{log,json}"; \
	    exit 1; \
	fi; \
	echo "OK: content verified for: $(ROMS)"

# One ROM. Every step is an artefact assertion; the checker's exit code is only
# ever cross-checked against its JSON, never believed on its own.
rom-verify-%:
	@test -n "$(ROM_DIR_$*)" || { echo "FAIL: unknown ROM '$*' — known ROMs: $(ROMS)"; exit 1; }
	@test -d "$(ROM_DIR_$*)" || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] no ROM directory at $(ROM_DIR_$*)"; exit 1; }
	@ls $(ROM_DIR_$*)/* >/dev/null 2>&1 || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] $(ROM_DIR_$*) is EMPTY — a checker pointed at an"; \
	    echo "      empty directory finds no files and therefore reports no problems."; exit 1; }
	@test -s "$(ROM_CODE_$*)" || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] no code file at $(ROM_CODE_$*) — nothing to compare against"; exit 1; }
	@test -s "$(ROM_SPEC_$*)" || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] no spec at $(ROM_SPEC_$*)"; exit 1; }
	@mkdir -p $(ROM_VERIFY_DIR)
	@# A stale JSON from a previous run would be read as this run's verdict.
	@rm -f $(ROM_VERIFY_DIR)/$*.json $(ROM_VERIFY_DIR)/$*.rc $(ROM_VERIFY_DIR)/$*.log
	@# A sim ROM that is simply ABSENT is not a statement about anything, and
	@# the checker rightly fails on it. Say so here, where the path is visible.
	@test "$(ROM_SIM_$*)" = "none" -o -s "$(ROM_SIM_$*)" || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] no simulation boot ROM at $(ROM_SIM_$*)."; \
	    echo "      Point ROM_SIM_$* at it, or set ROM_SIM_$*=none to state on the record"; \
	    echo "      that the sim view is not being compared. Silence is not a statement."; exit 1; }
	@# A declared exception is validated and PRINTED before the checker runs.
	@# Past the checker an unjustified or pattern-shaped entry is
	@# indistinguishable from a genuine clean result. Same assertion text as the
	@# toolkit's mk/rom.mk; this file is a fork of that one, keep the two in step.
	@printf '%s\n' "$$ROM_SIM_ALLOW_ASSERT" | python3 - \
	    "$(ROM_LABEL_$*)" "$*" "$(ROM_SIM_ALLOW_REASON_$*)" "$(ROM_SIM_ALLOW_$*)" ""
	@# No --view/--family flag: which content view is authoritative is the
	@# checker's decision, made in one place. Five views exist in two families
	@# that share no data, and picking one here would fork that decision.
	@# --var: the specs write their code_file path through $$(NANOSOC_MULTICORE_HOME).
	@rc=0; python3 $(ROM_VERIFY) \
	    --rom-dir "$(ROM_DIR_$*)" \
	    --name "$(ROM_LABEL_$*)" \
	    --code-file "$(ROM_CODE_$*)" \
	    --spec "$(ROM_SPEC_$*)" \
	    --wrapper "$(ROM_WRAP_$*)" \
	    $(if $(filter none,$(ROM_SIM_$*)),--no-sim-check,--sim-rtl "$(ROM_SIM_$*)") \
	    $(if $(wildcard $(ROM_REGION_$*)),--region-rtl "$(ROM_REGION_$*)",) \
	    $(foreach a,$(ROM_SIM_ALLOW_$*),--allow-sim-divergence "$(a)") \
	    --var NANOSOC_MULTICORE_HOME="$(NANOSOC_MULTICORE_HOME)" \
	    --program-search-root "$(NANOSOC_MULTICORE_HOME)/build" \
	    --json "$(ROM_VERIFY_DIR)/$*.json" \
	    > $(ROM_VERIFY_DIR)/$*.log 2>&1 || rc=$$?; \
	  echo $$rc > $(ROM_VERIFY_DIR)/$*.rc; \
	  while IFS= read -r l; do echo "  | $$l"; done < $(ROM_VERIFY_DIR)/$*.log
	@printf '%s\n' "$$ROM_JSON_ASSERT" | python3 - \
	    "$(ROM_VERIFY_DIR)/$*.json" "$(ROM_DIR_$*)" "$(ROM_CODE_$*)" \
	    "$(ROM_LABEL_$*)" "$$(cat $(ROM_VERIFY_DIR)/$*.rc)"

#-----------------------------------------------------------------------------
# Stream-out gate — the same question, asked of the merged GDS
#
# Content-correct at synthesis does not prove the bits reached the stream: the
# macro is merged into the GDS by write_stream, from a $gds_merge_list that is
# maintained by hand in scripts/config.tcl.
#
# THE MECHANISM IS NOT HERE ANY MORE. It is $(ROM_TOOLKIT_MK)'s `rom-gate-gds`,
# which since 2026-08-18 also
#
#   * writes a per-ROM manifest recording WHICH STREAM was measured -- absolute
#     path, sha256, size, mtime -- and refuses to report a pass from artefacts
#     whose recorded stream is not the one being gated. Before that, the only
#     record was free text on line 1 of a log in a single mutable slot, and on
#     2026-08-18 at 08:21 a superseded build's artefacts sitting in that slot
#     were read as a live failure of the current shipping candidate;
#   * ASSERTS that the macro is actually INSTANCED in the stream, instead of
#     printing the count. The standalone macro .gds2 extracts perfectly and
#     diffs clean while saying nothing about the die;
#   * refuses to measure a stream whose CLASS is undeclared, and names it in
#     every verdict;
#   * writes one portable evidence artefact a packager can collect.
#
# This target stays, because it is the documented entry point and
# ASIC/genus-innovus/Makefile wires it after `pnr_route` and after `restream`.
# It is now a thin delegation carrying this die's table across.
#
#   make -f ASIC/common.mk romlibs-verify-gds ROM_GDS=/path/to/design.gds
#-----------------------------------------------------------------------------
ROM_GDS ?=

# Where the evidence lands. Pointed at the run's own reports tree, this is
# collected by whatever packages a submission BY CONSTRUCTION rather than by
# someone remembering; left at the default it is under build/, which is
# gitignored and outside $(ASIC_DIR)/reports -- i.e. reachable on this host and
# nowhere else. Not relocated by default here: an in-flight invocation whose
# evidence silently moves is its own incident.
#   make -f ASIC/common.mk romlibs-verify-gds ROM_GDS=... \
#        ROM_VERIFY_DIR=$(NANOSOC_ETH_CHIPLET_HOME)/ASIC/eth-chiplet/build/<tag>/reports/rom

romlibs-verify-gds:
	@test -f "$(ROM_TOOLKIT_MK)" || { \
	    echo "FAIL: no toolkit ROM gate at $(ROM_TOOLKIT_MK)."; \
	    echo "      The stream-out mechanism lives in the asic-toolkit submodule."; \
	    echo "      A gate that cannot run is a FAILURE, not a skip: nothing else in"; \
	    echo "      this flow compares a bit of the streamed macro against the firmware."; \
	    echo "      git submodule update --init ASIC/asic-toolkit"; exit 1; }
	@# Filename inference, used ONLY in the direction that makes the gate
	@# stricter. A stream whose name says logo cannot be graded with the
	@# signoff default; it has to be classified deliberately. Inference that can
	@# only refuse, never bless, is safe -- the reverse is what mislabels a
	@# submission artefact as a signoff one and passes.
	@case "$(notdir $(ROM_GDS))" in *_logo*|*logo_*) \
	    if [ "$(ROM_GDS_CLASS)" = "signoff" ]; then \
	        echo "FAIL: $(notdir $(ROM_GDS)) looks like a logo-merged SUBMISSION stream, and"; \
	        echo "      ROM_GDS_CLASS is still the signoff default. Say what it is:"; \
	        echo "        ROM_GDS_CLASS=submission ROM_GDS_SHIPS=yes ROM_GDS_REQUIRE_SHIPPING=1"; \
	        exit 1; \
	    fi ;; esac
	@$(MAKE) -f $(ROM_TOOLKIT_MK) --no-print-directory rom-gate-gds \
	    ROMS="$(ROMS)" ROM_DESIGN="nanosoc-ethernet-chiplet" \
	    $(foreach r,$(ROMS),ROM_LABEL_$(r)="$(ROM_LABEL_$(r))" \
	      ROM_CODE_$(r)="$(ROM_CODE_$(r))" ROM_SPEC_$(r)="$(ROM_SPEC_$(r))" \
	      ROM_MEMLIB_$(r)="$(ROM_MEMLIB_$(r))" ROM_INST_$(r)="$(ROM_INST_$(r))" \
	      ROM_GDS_PLACEMENTS_$(r)="$(ROM_GDS_PLACEMENTS_$(r))" \
	      ROM_CODE_PEER_$(r)="$(ROM_CODE_PEER_$(r))") \
	    ROM_VERIFY_DIR="$(ROM_VERIFY_DIR)" ROM_GDS_EXTRACT="$(ROM_GDS_EXTRACT)" \
	    ROM_GDS="$(ROM_GDS)" ROM_GDS_GATE="$(ROM_GDS_GATE)" \
	    ROM_GDS_CLASS="$(ROM_GDS_CLASS)" \
	    ROM_GDS_CLASS_BASIS="$(ROM_GDS_CLASS_BASIS)" \
	    ROM_GDS_SHIPS="$(ROM_GDS_SHIPS)" \
	    ROM_GDS_REQUIRE_SHIPPING="$(ROM_GDS_REQUIRE_SHIPPING)" \
	    ROM_GDS_GEOM_ROOT="$(ROM_GDS_GEOM_ROOT)"

#-----------------------------------------------------------------------------
# Mutation test — can this gate fail, and can it still pass?
#
# Modelled on lec-selftest. Everything runs on COPIES under $(ROM_SELFTEST_DIR);
# ASIC/romlibs is never touched (it is evidence in an open investigation).
#
# Both directions matter. A gate that always fails is as useless as one that
# always passes, and today every real ROM fails — so the positive controls here
# are the only evidence that this gate discriminates at all.
#
# The checker doubles it writes are HARNESS controls: they prove that a verdict,
# a missing artefact or a disagreement between exit code and JSON propagates
# correctly through this wiring. They are not a test of scripts/ci/rom_verify.py,
# which owns its own selftest.
#-----------------------------------------------------------------------------
ROM_SELFTEST_DIR ?= $(ROM_VERIFY_DIR)/selftest

romlibs-selftest:
	@echo "== ROM gate mutation test =="
	@test -s "$(ROM_CODE_eth)" || { \
	    echo "FAIL: the selftest needs a real code file at $(ROM_CODE_eth)"; exit 1; }
	@rm -rf $(ROM_SELFTEST_DIR); mkdir -p $(ROM_SELFTEST_DIR)
	@printf '%s\n' "$$ROM_SELFTEST_PY" | python3 - \
	    "$(COMMON_MK)" "$(ROM_SELFTEST_DIR)" "$(ROM_CODE_eth)" \
	    "$(ROM_SPEC_eth)" "$(ROM_WRAP_eth)"

#-----------------------------------------------------------------------------
# The assertions themselves. Kept as exported variables rather than recipe
# one-liners so they stay readable and can be reviewed as code.
#
# NOTE FOR EDITORS: make expands these before exporting them, so every literal
# dollar sign inside must be written $$.
#-----------------------------------------------------------------------------

# Static agreement: spec vs code file vs RTL wrapper vs the built macro.
define ROM_STATIC_ASSERT
import os, re, sys

name, spec, code, wrap, memlib, inst, flist = sys.argv[1:8]
fails = []
def ok(m):  print("  OK:   [%s] %s" % (name, m))
def bad(m): fails.append(m); print("  FAIL: [%s] %s" % (name, m))
def addr_bits(words): return max(1, (words - 1).bit_length())

# ---- the spec -------------------------------------------------------------
kv = {}
for raw in open(spec):
    line = raw.split("#", 1)[0].strip()
    if "=" in line:
        k, v = line.split("=", 1)
        kv[k.strip()] = v.strip()
try:
    swords = int(kv["words"]); sbits = int(kv["bits"])
except (KeyError, ValueError):
    print("  FAIL: [%s] spec %s has no parseable words=/bits=" % (name, spec)); sys.exit(1)
ok("spec asks for %d words x %d bits (%s)" % (swords, sbits, spec))

# The compiler is handed -code_file on the command line, but the spec carries
# its own code_file= line. If that line does not resolve, a run made from this
# spec may have been reading something else entirely -- and the compiler
# substitutes contents rather than failing.
sc = kv.get("code_file", "")
if sc:
    exp = re.sub(r"\$$[({](\w+)[)}]", lambda m: os.environ.get(m.group(1), "\x00"), sc)
    if "\x00" in exp:
        bad("the spec's code_file= names an environment variable that is not set here: %s" % sc)
    elif not os.path.exists(exp):
        bad("the spec's code_file= does not resolve to a file: %s\n"
            "        The ROM compiler does not fail on a missing code file, it substitutes." % exp)
    elif os.path.realpath(exp) != os.path.realpath(code):
        bad("the spec's code_file= is a DIFFERENT image from the one this flow verifies:\n"
            "        spec: %s\n        flow: %s" % (os.path.realpath(exp), os.path.realpath(code)))
    else:
        ok("the spec's code_file= resolves to the image this flow verifies")
else:
    bad("the spec has no code_file= line")

# ---- the code file --------------------------------------------------------
n = 0; badline = None
for i, raw in enumerate(open(code)):
    s = raw.strip()
    if not s:
        continue
    n += 1
    if badline is None and (len(s) != sbits or s.strip("01")):
        badline = (i + 1, s[:48])
if n == 0:
    bad("the code file %s has no words in it" % code)
elif badline:
    bad("code file %s line %d is not %d binary digits: %r" % (code, badline[0], sbits, badline[1]))
else:
    ok("code file is %d words x %d bits, every line well formed (%s)" % (n, sbits, code))

# ---- the built macro (absent on a fresh build) ----------------------------
mwords = None
if memlib and os.path.exists(memlib):
    m = re.search(r"NumberOfWords\s*:\s*(\d+)", open(memlib).read())
    if not m:
        bad("cannot read NumberOfWords from %s" % memlib)
    else:
        mwords = int(m.group(1))
        ok("the built macro is %d words deep, A[%d:0] (%s)"
           % (mwords, addr_bits(mwords) - 1, os.path.basename(memlib)))
else:
    print("  NOTE: [%s] no built macro at %s -- depth checks against it are not applicable"
          % (name, memlib))

# ---- the RTL wrapper ------------------------------------------------------
wtxt = open(wrap).read()
m = (re.search(r"\[\s*(\d+)\s*-\s*1\s*:\s*0\s*\]\s*word_addr", wtxt) or
     re.search(r"\[\s*(\d+)\s*:\s*0\s*\]\s*word_addr", wtxt))
waddr = None
if not m:
    bad("cannot find the word_addr port width in %s" % wrap)
else:
    waddr = int(m.group(1)) if "-" in m.group(0) else int(m.group(1)) + 1
    ok("the RTL wrapper drives a %d-bit address (%d words) -- %s"
       % (waddr, 1 << waddr, os.path.basename(wrap)))
if not re.search(r"^\s*%s\s+\w+\s*\(" % re.escape(inst), wtxt, re.M):
    bad("the wrapper %s does not instantiate %s" % (wrap, inst))

# ---- is this wrapper the one the design actually COMPILES? ----------------
# The failure this catches is not hypothetical: until 2026-08-14 this gate
# graded a stale hand-copy under ASIC/tech_wrappers/tsmc65 that no flist had
# referenced for months. It reported a width defect that had already been fixed
# in the compiled file, and it would just as happily have reported a clean pass
# while the compiled file was broken. Checking RTL nothing builds is the exact
# silent-pass shape this whole file exists to refuse, so it is an assertion.
want = os.path.realpath(wrap)
base = os.path.basename(want)
hits, unresolved = [], False
for raw in open(flist):
    line = raw.split("//", 1)[0].strip()
    if not line or line.startswith(("+", "-")):
        continue
    exp = re.sub(r"\$$[({](\w+)[)}]", lambda m: os.environ.get(m.group(1), "\x00"), line)
    if "\x00" in exp:
        unresolved = True
        continue
    if os.path.basename(exp) == base:
        hits.append(os.path.realpath(exp))
if want in hits:
    ok("the wrapper checked here is the one the flist compiles (%s)" % os.path.basename(flist))
elif hits:
    bad("THIS GATE IS READING RTL THE DESIGN DOES NOT BUILD.\n"
        "        checked : %s\n"
        "        compiled: %s\n"
        "        (%s)\n"
        "        Point ROM_WRAP_%s at the compiled file. A verifier aimed at an\n"
        "        unbuilt copy passes and fails for reasons the silicon never sees."
        % (want, "\n                  ".join(hits), flist, name))
elif unresolved:
    bad("cannot tell whether %s is compiled: %s has entries this gate could not\n"
        "        expand (an environment variable is unset here). Refusing to assume." % (base, flist))
else:
    bad("the flist %s compiles NO file named %s, so nothing in this design builds\n"
        "        the wrapper this gate is checking (%s)." % (flist, base, want))

# ---- agreement ------------------------------------------------------------
# A code file SHORTER than the macro is the defect that produced eth_rom: the
# compiler pads with substituted content instead of refusing.
depth = mwords if mwords is not None else swords
if n and n < depth:
    bad("the code file holds %d words but the ROM is %d deep -- the compiler fills the\n"
        "        remainder with substituted content and still exits 0" % (n, depth))
if mwords is not None and mwords != swords:
    bad("SPEC AND MACRO DISAGREE ON DEPTH: the spec asks for %d words, the built and\n"
        "        PLACED macro is %d. Rebuilding from this spec produces an A[%d:0] macro\n"
        "        that no longer matches the LEF/GDS already placed. Fix the spec, or\n"
        "        re-place the design -- do not simply rerun the compiler."
        % (swords, mwords, addr_bits(swords) - 1))
if waddr is not None and (1 << waddr) != swords:
    bad("the RTL wrapper addresses %d words, the spec asks for %d" % (1 << waddr, swords))
if waddr is not None and mwords is not None and (1 << waddr) != mwords:
    bad("the RTL wrapper drives a %d-bit address into a %d-word macro (A[%d:0]):\n"
        "        the upper address bits are silently truncated"
        % (waddr, mwords, addr_bits(mwords) - 1))

sys.exit(1 if fails else 0)
endef
export ROM_STATIC_ASSERT

# Post-conditions on the checker's own artefact.
define ROM_JSON_ASSERT
import json, os, sys

js, romdir, code, name, rcs = sys.argv[1:6]
rc = int(rcs)
def die(m):
    print("  FAIL: [%s] %s" % (name, m)); sys.exit(1)

# The checker's exit codes are 0 = all pass, 1 = at least one check failed,
# 2 (or anything else) = usage error or crash. A CRASH IS NOT A CLEAN FAIL: it
# means nothing was measured, and it is the state a wrong path produces. Say
# which one happened, because "the gate went red" reads the same either way and
# the two need different fixes.
if rc not in (0, 1):
    die("the checker exited %d -- that is a usage error or a crash, NOT a verdict.\n"
        "        Nothing was measured. Read the log above; a path that resolves to\n"
        "        nothing is the usual cause." % rc)

if not os.path.exists(js):
    die("the checker wrote no JSON at %s.\n"
        "        Its exit status was %d, but an exit status is not a measurement --\n"
        "        with no artefact there is nothing to show a reviewer." % (js, rc))
if os.path.getsize(js) == 0:
    die("the checker's JSON at %s is empty" % js)
try:
    d = json.load(open(js))
except Exception as e:
    die("the checker's JSON at %s does not parse: %s" % (js, e))

# Identity: it must record the exact ROM and code file it was pointed at. This
# is what catches a checker that resolved a path to nothing, looked at some
# other ROM, or handed back a stale result.
#
# A checker that echoes its own command line would satisfy this for free, so
# any top-level "argv"/"cmd" key is REMOVED before the search: the paths have to
# turn up in the findings, not in a copy of what we just told it.
body = {k: v for k, v in d.items() if k not in ("argv", "cmd", "command", "command_line")} \
       if isinstance(d, dict) else d
blob = json.dumps(body)
for p, what in ((romdir, "ROM directory"), (code, "code file")):
    if not any(x and x in blob for x in (p, os.path.realpath(p), os.path.basename(p.rstrip("/")))):
        die("the JSON never names the %s it was pointed at (%s).\n"
            "        The checker may have measured something else entirely." % (what, p))

TRUE  = {"pass", "passed", "ok", "true", "match", "matched", "clean", "verified"}
FALSE = {"fail", "failed", "mismatch", "error", "unverified", "false",
         "skip", "skipped", "none", "unknown"}
KEYS  = ("pass", "passed", "ok", "verdict", "result", "status", "overall",
         "overall_pass", "all_pass", "success")

verdict = key = None
if isinstance(d, dict):
    for k in KEYS:
        if k in d:
            v = d[k]; key = k
            if isinstance(v, bool):
                verdict = v
            elif isinstance(v, str):
                s = v.strip().lower()
                verdict = True if s in TRUE else (False if s in FALSE else None)
            break
if verdict is None:
    die("the checker's JSON carries no top-level verdict this gate recognises\n"
        "        (looked for: %s -- found: %s).\n"
        "        Refusing to infer a pass from silence." %
        (", ".join(KEYS), ", ".join(sorted(d)) if isinstance(d, dict) else type(d).__name__))

# HOW MUCH did it compare? A checker that found no files reports no problems,
# and that is the likeliest way this gate dies quietly. Anywhere in the result,
# a key that states a number of words must be non-zero somewhere.
WORDKEYS = ("words", "words_compared", "compared", "word_count", "n_words", "words_checked")
seen = []
def scan(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k.lower() in WORDKEYS and isinstance(v, int) and not isinstance(v, bool):
                seen.append((k, v))
            scan(v)
    elif isinstance(o, list):
        for v in o:
            scan(v)
scan(body)
if seen and max(v for _, v in seen) == 0:
    die("every word count in the checker's result is 0 -- it compared nothing,\n"
        "        which is not a pass (keys seen: %s)" % ", ".join(sorted({k for k, _ in seen})))
counts = {k: v for k, v in (body.items() if isinstance(body, dict) else [])
          if isinstance(v, int) and not isinstance(v, bool)}
if seen:
    counts["words"] = max(v for _, v in seen)

# WARNINGS ARE SURFACED, NOT PROMOTED AND NOT SWALLOWED. sim_divergence in
# particular is a warning by design — the simulation ROM and the ASIC ROM may
# legitimately differ — but a warning nobody reads is the same as no check.
def findings(o):
    if isinstance(o, dict):
        for k, v in o.items():
            if k == "findings" and isinstance(v, list):
                for f in v:
                    if isinstance(f, dict):
                        yield f
            else:
                for f in findings(v):
                    yield f
    elif isinstance(o, list):
        for v in o:
            for f in findings(v):
                yield f
warns = [f for f in findings(body)
         if str(f.get("severity", "")).lower() in ("warn", "warning")]
for f in warns:
    msg = str(f.get("message", "")).splitlines()
    print("  WARN: [%s] %s: %s" % (name, f.get("check", "?"), msg[0] if msg else ""))

# Exit status and verdict must agree. If they do not, one of them is wrong and
# neither can be trusted.
if verdict and rc != 0:
    die("the checker's JSON says %s=PASS but it exited %d -- these disagree" % (key, rc))
if (not verdict) and rc == 0:
    die("the checker exited 0 but its JSON says %s=FAIL -- these disagree.\n"
        "        Taking the failure: exit codes are not evidence in this flow." % key)
if not verdict:
    die("CONTENT MISMATCH -- this ROM does not contain this firmware (%s=FAIL).\n"
        "        The ROM is mask programmed: wrong bits are a dead die.\n"
        "        Detail: %s" % (key, js))

extra = ("  [%s]" % ", ".join("%s=%s" % kv for kv in sorted(counts.items()))) if counts else ""
print("  OK:   [%s] checker verdict %s=PASS, artefact %s%s" % (name, key, js, extra))
if not counts:
    print("  NOTE: [%s] the checker's JSON exposes no word count, so this gate could not\n"
          "        independently confirm how much was compared." % name)
endef
export ROM_JSON_ASSERT

# ROM_BITS_ASSERT lived here until 2026-08-18. It is now
# $(ROM_TOOLKIT_MK)'s, alongside the stream-identity and macro-reachability
# assertions it grew. Deleted rather than left as a second copy: this tree has
# already been bitten three times in one day by two copies of one source, where
# only the wiring said which one ran.


# Declared sim/silicon divergence: valid, justified, and PRINTED. A fork of the
# toolkit's ROM_SIM_ALLOW_ASSERT (ASIC/asic-toolkit/mk/rom.mk) -- keep in step.
define ROM_SIM_ALLOW_ASSERT
import re, sys

name, key, reason, narrow_s, broad_s = sys.argv[1:6]
narrow = [x for x in narrow_s.split() if x]
broad = [x for x in broad_s.split() if x]

def die(m):
    print("  FAIL: [%s] %s" % (name, m)); sys.exit(1)

if not narrow and not broad:
    sys.exit(0)

# HASH-SCOPED, NEVER PATH-SCOPED. A pattern forgives the image you meant and
# every future image that lands in the same place, including a stale one -- a
# different defect wearing the same clothes. Naming the CONTENT is what makes
# the gate speak up again when the content changes, which is the only reason a
# declaration beats a suppression.
for a in narrow:
    if not re.match(r"^sha256:[0-9a-fA-F]{64}$$", a):
        die("ROM_SIM_ALLOW_%s entry %r is not a sha256:<64 hex> token.\n"
            "        This table forgives CONTENT, not locations. The checker prints the\n"
            "        exact token to add when it finds an unforgiven divergence."
            % (key, a))

# An undocumented exception is refused: six months on, the only honest thing
# anyone could say about it is that somebody once thought it was fine.
if not reason.strip():
    die("ROM_SIM_ALLOW_%s declares %d exception(s) and ROM_SIM_ALLOW_REASON_%s is\n"
        "        empty. An entry nobody can review is one nobody can retire."
        % (key, len(narrow) + len(broad), key))

print("  ALLOW-LISTED: [%s] sim/silicon divergence is DECLARED for this ROM." % name)
print("        reason: %s" % reason.strip())
for a in narrow:
    print("        content: %s" % a)
print("        An exception, not a pass: the checker still reports it below,")
print("        marked [ALLOW-LISTED].")
endef
export ROM_SIM_ALLOW_ASSERT

# The mutation test. Every case states what it expects and why.
define ROM_SELFTEST_PY
import os, re, subprocess, sys

mk, D, CODE, SPEC, WRAP = sys.argv[1:6]
npass = nfail = 0

def run(target, over):
    args = ["make", "-f", mk, "--no-print-directory", target]
    args += ["%s=%s" % (k, v) for k, v in sorted(over.items())]
    p = subprocess.run(args, capture_output=True, text=True)
    return p.returncode, (p.stdout or "") + (p.stderr or "")

def expect_fail(case, needle, target, **over):
    global npass, nfail
    rc, out = run(target, over)
    if rc == 0:
        print("  SELFTEST FAIL: %s -- THE GATE PASSED A BROKEN ROM" % case)
        print(re.sub("^", "      ", out.rstrip(), flags=re.M)); nfail += 1; return
    if needle not in out:
        print("  SELFTEST FAIL: %s -- it failed, but not for the stated reason" % case)
        print("      expected to see: %s" % needle)
        print(re.sub("^", "      ", out.rstrip(), flags=re.M)); nfail += 1; return
    print("  ok   %-34s FAILED, naming: %s" % (case, needle)); npass += 1

def expect_pass(case, target, **over):
    global npass, nfail
    rc, out = run(target, over)
    if rc != 0:
        print("  SELFTEST FAIL: %s -- THE GATE FAILED A CORRECT ROM" % case)
        print(re.sub("^", "      ", out.rstrip(), flags=re.M)); nfail += 1; return
    print("  ok   %-34s PASSED" % case); npass += 1

# ---- build a consistent reference set from the real code file --------------
words = [l.strip() for l in open(CODE) if l.strip()]
n = len(words); width = len(words[0])
addr = max(1, (n - 1).bit_length())
good = os.path.join(D, "good"); os.makedirs(good, exist_ok=True)

spec_txt = []
for raw in open(SPEC):
    if re.match(r"\s*words\s*=", raw):      raw = "words = %d\n" % n
    elif re.match(r"\s*code_file\s*=", raw): raw = "code_file = %s\n" % os.path.join(good, "code.bintxt")
    spec_txt.append(raw)
open(os.path.join(good, "rom.spec"), "w").write("".join(spec_txt))
open(os.path.join(good, "code.bintxt"), "w").write("\n".join(words) + "\n")
wrap_txt = re.sub(r"\[\s*\d+\s*-\s*1\s*:\s*0\s*\]\s*word_addr",
                  "[%d-1:0] word_addr" % addr, open(WRAP).read())
open(os.path.join(good, "wrap.sv"), "w").write(wrap_txt)
open(os.path.join(good, "rom.memlib"), "w").write(
    "MemoryTemplate (x) {\n\tNumberOfWords : %d;\n}\n" % n)
# A flist that DOES compile the synthetic wrapper, so the "is this the file the
# design builds?" assertion has a consistent set to pass. The case below points
# ROM_WRAP_eth somewhere this flist does not name, and must fail.
open(os.path.join(good, "rom.flist"), "w").write(
    "// synthetic flist for the ROM gate selftest\n%s\n" % os.path.join(good, "wrap.sv"))

# A ROM directory whose contents ARE this firmware, and one that is off by a
# single bit in word 7 -- the smallest defect that still kills a die.
for tag, mutate in (("rom_ok", False), ("rom_bad", True)):
    d = os.path.join(D, tag); os.makedirs(d, exist_ok=True)
    w = list(words)
    if mutate:
        w[7] = ("1" if w[7][0] == "0" else "0") + w[7][1:]
    open(os.path.join(d, "content.bits"), "w").write("\n".join(w) + "\n")
assert open(os.path.join(D, "rom_ok/content.bits")).read() != \
       open(os.path.join(D, "rom_bad/content.bits")).read(), "the mutation did nothing"

S = dict(ROM_SPEC_eth=os.path.join(good, "rom.spec"),
         ROM_CODE_eth=os.path.join(good, "code.bintxt"),
         ROM_WRAP_eth=os.path.join(good, "wrap.sv"),
         ROM_MEMLIB_eth=os.path.join(good, "rom.memlib"),
         ROM_FLIST=os.path.join(good, "rom.flist"))

# ---- checker doubles: harness controls, not tests of the real checker ------
def double(name, body):
    p = os.path.join(D, name)
    open(p, "w").write(body)
    return p

REAL = double("double_real.py", '''
import argparse, json, os, sys
a = argparse.ArgumentParser()
for f in ("--rom-dir", "--code-file", "--spec", "--wrapper", "--json"): a.add_argument(f)
n, _ignored = a.parse_known_args()
want = [l.strip() for l in open(n.code_file) if l.strip()]
got  = [l.strip() for l in open(os.path.join(n.rom_dir, "content.bits")) if l.strip()]
mism = sum(1 for i in range(min(len(want), len(got))) if want[i] != got[i]) + abs(len(want) - len(got))
json.dump({"rom_dir": n.rom_dir, "code_file": n.code_file, "words_compared": len(got),
           "words_mismatching": mism, "pass": mism == 0}, open(n.json, "w"))
sys.exit(0 if mism == 0 else 1)
''')
SILENT = double("double_silent.py", "import sys\nsys.exit(0)\n")
NOVERDICT = double("double_noverdict.py", '''
import json, sys
j = sys.argv[sys.argv.index("--json") + 1]
d = sys.argv[sys.argv.index("--rom-dir") + 1]
c = sys.argv[sys.argv.index("--code-file") + 1]
json.dump({"rom_dir": d, "code_file": c, "note": "no verdict here"}, open(j, "w"))
''')
ZERO = double("double_zero.py", '''
import json, sys
j = sys.argv[sys.argv.index("--json") + 1]
d = sys.argv[sys.argv.index("--rom-dir") + 1]
c = sys.argv[sys.argv.index("--code-file") + 1]
json.dump({"rom_dir": d, "code_file": c, "pass": True, "words_compared": 0}, open(j, "w"))
''')
LIAR = double("double_liar.py", '''
import json, sys
j = sys.argv[sys.argv.index("--json") + 1]
d = sys.argv[sys.argv.index("--rom-dir") + 1]
c = sys.argv[sys.argv.index("--code-file") + 1]
json.dump({"rom_dir": d, "code_file": c, "pass": False, "words_compared": 512}, open(j, "w"))
''')
ELSEWHERE = double("double_elsewhere.py", '''
import json, sys
j = sys.argv[sys.argv.index("--json") + 1]
json.dump({"rom_dir": "/somewhere/else", "code_file": "/other.bintxt", "pass": True,
           "words_compared": 512}, open(j, "w"))
''')
# Exit 2 is the checker's "usage error or crash". It must not read as a clean
# FAIL: nothing was measured, and the fix is different.
CRASH = double("double_crash.py", '''
import json, sys
j = sys.argv[sys.argv.index("--json") + 1]
d = sys.argv[sys.argv.index("--rom-dir") + 1]
c = sys.argv[sys.argv.index("--code-file") + 1]
json.dump({"rom_dir": d, "code_file": c, "verdict": "FAIL", "words": 512}, open(j, "w"))
sys.exit(2)
''')

print("-- static gate: does it pass a set that agrees?")
expect_pass("consistent spec/wrapper/macro/code", "rom-static-eth", **S)

print("-- static gate: induced faults")
expect_fail("code file path resolves to nothing", "no code file at", "rom-static-eth",
            **dict(S, ROM_CODE_eth=os.path.join(D, "nope/absent.bintxt")))
# The 2026-08-14 defect, as a control, reproduced in its exact shape: a stale
# DUPLICATE that shares the compiled file's name and sits in another directory.
# It is real, self-consistent and parseable, and every other check passes on it,
# so ONLY the flist assertion can tell it from the file the design builds.
staled = os.path.join(D, "stale"); os.makedirs(staled, exist_ok=True)
stale = os.path.join(staled, "wrap.sv")
open(stale, "w").write(wrap_txt)
expect_fail("stale duplicate of a compiled file", "DOES NOT BUILD", "rom-static-eth",
            **dict(S, ROM_WRAP_eth=stale))
# The other shape: a wrapper no flist mentions under any name.
orphan = os.path.join(D, "orphan_wrap.sv")
open(orphan, "w").write(wrap_txt)
expect_fail("wrapper nothing compiles at all", "compiles NO file named", "rom-static-eth",
            **dict(S, ROM_WRAP_eth=orphan))
expect_fail("flist missing entirely", "no flist at", "rom-static-eth",
            **dict(S, ROM_FLIST=os.path.join(D, "nope/absent.flist")))
short = os.path.join(D, "short.bintxt")
open(short, "w").write("\n".join(words[:100]) + "\n")
expect_fail("code file truncated to 100 words", "the compiler fills the", "rom-static-eth",
            **dict(S, ROM_CODE_eth=short))
empty = os.path.join(D, "empty.bintxt"); open(empty, "w").close()
expect_fail("code file empty", "no code file at", "rom-static-eth",
            **dict(S, ROM_CODE_eth=empty))
junk = os.path.join(D, "junk.bintxt")
open(junk, "w").write("\n".join(words[:5] + ["DEADBEEF"] + words[6:]) + "\n")
expect_fail("code file has a non-binary word", "is not %d binary digits" % width,
            "rom-static-eth", **dict(S, ROM_CODE_eth=junk))
deep = os.path.join(D, "deep.spec")
open(deep, "w").write(re.sub(r"(?m)^words\s*=.*", "words = 2048",
                             open(os.path.join(good, "rom.spec")).read()))
expect_fail("spec deeper than the built macro", "SPEC AND MACRO DISAGREE ON DEPTH",
            "rom-static-eth", **dict(S, ROM_SPEC_eth=deep))
elsewhere_spec = os.path.join(D, "elsewhere.spec")
open(elsewhere_spec, "w").write(re.sub(r"(?m)^code_file\s*=.*", "code_file = %s" % CODE,
                                       open(os.path.join(good, "rom.spec")).read()))
expect_fail("spec points at another image", "DIFFERENT image", "rom-static-eth",
            **dict(S, ROM_SPEC_eth=elsewhere_spec))

print("-- content gate: does it pass a ROM that holds this firmware?")
expect_pass("ROM contents == code file", "rom-verify-eth",
            **dict(S, ROM_VERIFY=REAL, ROM_DIR_eth=os.path.join(D, "rom_ok")))

print("-- content gate: induced faults")
expect_fail("one bit wrong in word 7", "CONTENT MISMATCH", "rom-verify-eth",
            **dict(S, ROM_VERIFY=REAL, ROM_DIR_eth=os.path.join(D, "rom_bad")))
expect_fail("ROM directory does not exist", "no ROM directory at", "rom-verify-eth",
            **dict(S, ROM_VERIFY=REAL, ROM_DIR_eth=os.path.join(D, "nope")))
emptydir = os.path.join(D, "emptydir"); os.makedirs(emptydir, exist_ok=True)
expect_fail("ROM directory is empty", "is EMPTY", "rom-verify-eth",
            **dict(S, ROM_VERIFY=REAL, ROM_DIR_eth=emptydir))
expect_fail("checker is not installed", "A gate that cannot run is a FAILURE",
            "romlibs-verify-content", **dict(S, ROM_VERIFY=os.path.join(D, "nope/rom_verify.py")))
expect_fail("checker exits 0, writes no JSON", "wrote no JSON", "rom-verify-eth",
            **dict(S, ROM_VERIFY=SILENT, ROM_DIR_eth=os.path.join(D, "rom_ok")))
expect_fail("checker JSON carries no verdict", "no top-level verdict", "rom-verify-eth",
            **dict(S, ROM_VERIFY=NOVERDICT, ROM_DIR_eth=os.path.join(D, "rom_ok")))
expect_fail("checker compared zero words", "compared nothing", "rom-verify-eth",
            **dict(S, ROM_VERIFY=ZERO, ROM_DIR_eth=os.path.join(D, "rom_ok")))
expect_fail("exit 0 but JSON says FAIL", "these disagree", "rom-verify-eth",
            **dict(S, ROM_VERIFY=LIAR, ROM_DIR_eth=os.path.join(D, "rom_ok")))
expect_fail("JSON names another ROM entirely", "never names the", "rom-verify-eth",
            **dict(S, ROM_VERIFY=ELSEWHERE, ROM_DIR_eth=os.path.join(D, "rom_ok")))
expect_fail("checker crashed (exit 2), JSON says FAIL", "usage error or a crash",
            "rom-verify-eth", **dict(S, ROM_VERIFY=CRASH, ROM_DIR_eth=os.path.join(D, "rom_ok")))
expect_fail("simulation ROM path is missing", "Silence is not a statement", "rom-verify-eth",
            **dict(S, ROM_VERIFY=REAL, ROM_DIR_eth=os.path.join(D, "rom_ok"),
                   ROM_SIM_eth=os.path.join(D, "nope/sim.sv")))

print("-- stream-out gate: induced faults")
expect_fail("no stream given", "ROM_GDS is not set", "romlibs-verify-gds")
expect_fail("stream file does not exist", "no GDS at", "romlibs-verify-gds",
            ROM_GDS=os.path.join(D, "nope.gds"))
fake = os.path.join(D, "fake.gds"); open(fake, "w").write("not a real stream")
expect_fail("no bit extractor installed", "UNVERIFIED IS NOT A PASS", "romlibs-verify-gds",
            ROM_GDS=fake, ROM_GDS_EXTRACT=os.path.join(D, "nope/extract.py"))

print("")
print("SELFTEST: %d passed, %d failed" % (npass, nfail))
sys.exit(1 if nfail else 0)
endef
export ROM_SELFTEST_PY
