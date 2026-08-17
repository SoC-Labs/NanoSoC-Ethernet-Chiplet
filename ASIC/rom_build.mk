#-----------------------------------------------------------------------------
# ASIC/rom_build.mk -- per-run boot ROM macro generation
# A joint work commissioned on behalf of SoC Labs, under Arm Academic
# Access license.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# Included by ASIC/common.mk, immediately before rom_gate.mk -- it BUILDS the
# ROMs, rom_gate.mk JUDGES them, and the order matters because `rom-run` runs
# the gate against what it just built.
#
# WHAT CHANGED, AND WHY
# ---------------------
# ASIC/romlibs/{eth_rom,cc_rom} was a gitignored binary drop, hand-copied out of
# another user's tapeout tree by `romlibs-fetch` (genus-innovus/Makefile). There
# was no dependency of any kind between the firmware and those macros: a
# firmware change could reach the .bintxt and never reach the ROM, and nothing
# in the flow would notice. It did not notice. Both macros shipped holding
# something other than their firmware, seven weeks older than their own code
# files, and they are MASK PROGRAMMED.
#
# rom_gate.mk now blocks synthesis on that. This file removes the opportunity:
# the ROM a run synthesises against is BUILT BY THAT RUN and lives IN that run's
# directory, beside the netlist and the GDS it produced.
#
#   make -f ASIC/common.mk rom-run ROM_RUN_DIR=<run>
#
#       ensures both macros exist in a content-addressed cache (building them if
#       the inputs are new), hardlinks them into <run>/romlibs/{eth_rom,cc_rom},
#       pins the run to those exact builds, and then runs the FULL ROM GATE
#       against the run-local copy. Synthesis depends on this target, so a run
#       cannot consume a ROM that was not built for it and checked.
#
# THE COST, MEASURED (srv03335, 2026-08-14)
# -----------------------------------------
#       liberty      136 s   <- 5 corners; 79% of the whole build
#       postscript     5.0 s      gds2        5.0 s      lef-fp      4.0 s
#       bitmap         4.0 s      lvs         3.5 s      apache_avm  3.5 s
#       ascii          3.3 s      verilog     1.5 s      masis       1.1 s
#       tmax           1.1 s      fastscan    1.1 s      memorybist  1.1 s
#       ctl            0.9 s
#       ------------------------------------------------------------------
#       ~171 s per ROM, ~5.7 min for both, ~16 MB each.
#
# Against a synthesis run measured in licence-hours that is affordable per run,
# which is why the cache is a convenience rather than the load-bearing part. It
# earns its place anyway: the cache is what makes two runs with identical inputs
# provably share one artefact, and it turns a re-run after a floorplan change
# from six minutes into nothing.
#
# WHAT IS NOT CACHED, DELIBERATELY
# --------------------------------
# A cache entry older than its code file is treated as a MISS and rebuilt. See
# scripts/ci/rom_cache.py's header: rom_verify.py proves a macro postdates its
# firmware, partly from mtimes, and a hit that predates a rewritten (even
# byte-identical) code file would fail that check on a correct macro. Rather
# than weaken the check that caught a seven-week-stale ROM, the build is
# repeated. `eth-bintxt`/`cc-bintxt` in common.mk keep .bintxt mtimes stable
# when the program has not changed, so this is rare.
#
# WHERE THIS SPLITS FOR THE TOOLKIT
# ---------------------------------
# GENERIC (belongs in asic-toolkit, when it wants it): "compile a memory macro
# into a content-addressed cache, materialise it into the run, pin the run to
# it, refuse to re-pin". Nothing in rom_cache.py knows this design.
# PROJECT (stays here): which ROMs exist, their specs, their code files, their
# depth, and the entire contents of rom_gate.mk. ROM_RUN_DIR is the seam -- a
# toolkit that publishes its run directory under that name gets this for free.
#-----------------------------------------------------------------------------

ROM_CACHE       ?= $(NANOSOC_ETH_CHIPLET_HOME)/scripts/ci/rom_cache.py

# The cache. Under build/ (gitignored), shared by every run and every flow in
# this checkout. Point it at a shared path to share across checkouts; entries
# are immutable and content-addressed, so that is safe.
ROM_CACHE_DIR   ?= $(NANOSOC_ETH_CHIPLET_HOME)/build/rom_cache

# THE RUN. Every flow sets this to its own per-run directory:
#   genus-innovus   $(OUT_DIR)/romlibs      (archived with the run into runs/)
#   eth-chiplet     $(RUN_DIR)/romlibs      (the toolkit's build/$(RUN_TAG))
# The default is the legacy shared location, so an un-migrated caller behaves
# exactly as before rather than silently building somewhere new.
ROM_RUN_DIR     ?= $(ROMLIBS_DIR)

# Depth this design's ROMs must be. NOT a free parameter and not a preference:
# 512 words is A[8:0] in the RTL wrappers (.TA(9'd0)), the HADDR[10:2] region
# decode, `bootrom_gen.py -a 9`, and the linker's 2 KB RO cap. The specs said
# 2048 until 2026-08-14 while every macro on disk was 512, so a naive rebuild
# produced an 11-bit-address macro matching neither the wrapper nor the placed
# abstract. rom_cache.py refuses to compile against a disagreement between this
# number, the spec and the code file, BEFORE spending the compiler time.
ROM_EXPECT_WORDS ?= 512

# The same number as an address width, because `bootrom_gen.py -a N` wants it
# that way and common.mk's code-file regeneration passes it. Two spellings of
# one fact is exactly how the 512-vs-2048 disagreement survived, so they are
# checked against each other here rather than trusted to stay in step.
ROM_ADDR_BITS   ?= 9
ifneq ($(shell awk 'BEGIN{print 2^$(ROM_ADDR_BITS)}'),$(ROM_EXPECT_WORDS))
$(error ROM_ADDR_BITS=$(ROM_ADDR_BITS) means $(shell awk 'BEGIN{print 2^$(ROM_ADDR_BITS)}') \
words, but ROM_EXPECT_WORDS=$(ROM_EXPECT_WORDS). These are one number: the macro \
depth, the RTL wrapper's address width and the HADDR region decode. Set both.)
endif

# Generators. The compiler's own list MINUS `testcode`, which is not an omission
# but the entire point: `testcode` treats -code_file as its OUTPUT and
# overwrites the firmware, and generators sequenced after it inside `all` then
# read the clobbered file. rom_cache.py refuses `testcode` and `all` by name and
# re-hashes the code file after every single generator.
ROM_GENERATORS  ?= liberty lef-fp gds2 verilog masis tmax fastscan ctl lvs \
                   bitmap apache_avm memorybist ascii postscript

# Import instead of compile, for a host with no working compiler. This is the
# honest replacement for `romlibs-fetch`: the entry is labelled origin=imported
# and records the tree it came from, and it still has to pass the full gate.
#   make -f ASIC/common.mk rom-run ROM_IMPORT_FROM=/path/to/romlibs
ROM_IMPORT_FROM ?=

_rom_import = $(if $(ROM_IMPORT_FROM),--import-from $(ROM_IMPORT_FROM)/$(ROM_LABEL_$(1)),)

# ONLY THE AGGREGATES ARE .PHONY. `rom-stage-%` and `rom-status-%` are pattern
# rules, and GNU make DOES NOT SEARCH IMPLICIT OR PATTERN RULES FOR A TARGET
# DECLARED PHONY -- it is an explicit optimisation in the manual. Listing
# $(addprefix rom-stage-,$(ROMS)) here therefore does not "declare them phony",
# it makes them targets with no rule, and make answers
#     make: Nothing to be done for 'rom-stage-eth'.
# and moves on. Both ROMs then fail the gate for being absent, which reads as a
# build failure rather than as a makefile bug. rom_gate.mk's rom-static-% and
# rom-verify-% are correct for the same reason: it lists only the aggregates.
.PHONY: rom-run rom-run-stage rom-run-ensure rom-run-status rom-cache-clean

## make -f common.mk rom-run [ROM_RUN_DIR=<run>]
## Build (or reuse) both ROMs, materialise them into the run, pin the run to
## them, then run the full ROM gate against the run-local copy.
##
## THE GATE RUNS AGAINST WHAT WAS JUST STAGED, not against ASIC/romlibs: the
## ROMLIBS_DIR override below is what points rom_gate.mk's ROM_DIR_<r> at the
## run. Verifying the shared drop while synthesising the run-local build would
## be a gate that tests something other than the artefact in use, which is how
## the original defect survived for months.
##
## ROM_VERIFY_DIR IS DELIBERATELY *NOT* REDIRECTED INTO THE RUN. The gate's
## evidence stays at its established path ($(ROM_VERIFY_DIR), build/rom_verify),
## because ci/signoff.yaml's `rom-content` row locates those JSONs through
## `rom-vars` — which is invoked WITHOUT this run's ROM_RUN_DIR and so would
## look at the default while the gate wrote somewhere else. The row would then
## report "no result ... the gate did not run" on a run that had just passed,
## which is the worst kind of CI failure: one that looks like a real defect.
##
## The run is still self-describing: it carries .rom_pin.json and a
## .rom_build.json per ROM (key, origin, code-file sha256, build time, per-file
## hashes), and the copy step below puts the gate's own artefacts beside them.
rom-run: rom-run-stage
	@$(MAKE) -f $(COMMON_MK) --no-print-directory romlibs-verify \
	    ROMLIBS_DIR=$(ROM_RUN_DIR)
	@# A COPY, clearly marked as one. The originals stay where CI reads them.
	@mkdir -p $(ROM_RUN_DIR)/verify
	@cp -f $(ROM_VERIFY_DIR)/*.json $(ROM_VERIFY_DIR)/*.log \
	       $(ROM_VERIFY_DIR)/last_pass.txt $(ROM_RUN_DIR)/verify/ 2>/dev/null || true
	@echo "OK: this run's ROMs are built, pinned and verified — $(ROM_RUN_DIR)"

rom-run-stage: rom-compiler-stage rom-bintxt
	@echo "== ROM build for this run: $(ROM_RUN_DIR) =="
	@$(MAKE) -f $(COMMON_MK) --no-print-directory $(addprefix rom-stage-,$(ROMS))

# One ROM: ensure the cache entry, hardlink it into the run, pin it.
#
# `rom-compiler-stage` is a prerequisite of the aggregate rather than of this
# rule, so the mirror is refreshed once per invocation and not once per ROM.
# --compiler is passed even when importing; rom_cache.py only probes it when it
# has to compile.
rom-stage-%:
	@test -n "$(ROM_DIR_$*)" || { echo "FAIL: unknown ROM '$*' -- known ROMs: $(ROMS)"; exit 1; }
	@mkdir -p $(ROM_RUN_DIR)
	@python3 $(ROM_CACHE) stage \
	    --rom $(ROM_LABEL_$*) \
	    --spec $(ROM_SPEC_$*) \
	    --code-file $(ROM_CODE_$*) \
	    --compiler $(ROM_COMPILER) \
	    --cache-root $(ROM_CACHE_DIR) \
	    --generators "$(ROM_GENERATORS)" \
	    --expect-words $(ROM_EXPECT_WORDS) \
	    --run-romlibs $(ROM_RUN_DIR) \
	    $(call _rom_import,$*) \
	    --json $(ROM_RUN_DIR)/$*_stage.json
	@# The tool's exit code is not the verdict -- assert the artefact. A stage
	@# that "succeeded" and left no .lib is the failure mode this flow has been
	@# bitten by in three other places.
	@test -s $(ROM_RUN_DIR)/$(ROM_LABEL_$*)/$(ROM_INST_$*).lef || { \
	    echo "FAIL: [$(ROM_LABEL_$*)] staging reported success but wrote no LEF into"; \
	    echo "      $(ROM_RUN_DIR)/$(ROM_LABEL_$*)"; exit 1; }

## make -f common.mk rom-run-ensure -- the cheap per-stage guard.
##
## THIS IS WHAT P&R AND STREAM-OUT HANG OFF, and why they read the same build
## synthesis did. `rom-run` is the heavyweight entry point: it regenerates the
## code files, consults the cache and runs the full gate, and it needs the
## firmware build tree to exist. Hanging that off every Innovus stage would make
## `pnr_route` fail on a host with no firmware checkout, for a run whose ROMs
## were settled hours earlier.
##
## So this target asks the one question a later stage actually needs answered:
## are this run's pinned ROMs still here? If yes it is a no-op costing
## milliseconds and touching no compiler. If the run has no ROMs at all —
## a resumed run, a cleaned outputs/ — it falls through to the full build, which
## re-materialises the SAME cache entry rather than inventing a new one.
##
## What it never does is quietly substitute a different ROM. That decision
## belongs to the pin in rom_cache.py, which refuses a key change outright.
##
## The file list is generated from the ROM table in rom_gate.mk rather than
## restated. A second copy of "eth means eth_rom_via" is precisely the kind of
## drift that left this flow grading a wrapper nothing compiles.
rom-run-ensure:
	@missing=""; \
	$(foreach r,$(ROMS),\
	  test -s "$(ROM_RUN_DIR)/$(ROM_LABEL_$(r))/$(ROM_INST_$(r)).lef" \
	    -a -s "$(ROM_RUN_DIR)/$(ROM_LABEL_$(r))/$(ROM_INST_$(r)).gds2" \
	    || missing="$$missing $(ROM_LABEL_$(r))"; ) \
	if [ -z "$$missing" ] && [ -s "$(ROM_RUN_DIR)/.rom_pin.json" ]; then \
	    echo "OK: this run's ROMs are staged and pinned ($(ROM_RUN_DIR))"; \
	else \
	    echo "== this run has no staged ROMs ($$missing) — building/restaging =="; \
	    $(MAKE) -f $(COMMON_MK) --no-print-directory rom-run ROM_RUN_DIR=$(ROM_RUN_DIR); \
	fi

## make -f common.mk rom-run-status -- what the cache would do, without doing it.
## No compiler time, no writes. Answers "would this run rebuild?".
rom-run-status:
	@for r in $(ROMS); do \
	    $(MAKE) -f $(COMMON_MK) --no-print-directory rom-status-$$r; \
	done

rom-status-%:
	@python3 $(ROM_CACHE) status \
	    --rom $(ROM_LABEL_$*) --spec $(ROM_SPEC_$*) --code-file $(ROM_CODE_$*) \
	    --compiler $(ROM_COMPILER) --cache-root $(ROM_CACHE_DIR) \
	    --generators "$(ROM_GENERATORS)" --expect-words $(ROM_EXPECT_WORDS)

## make -f common.mk rom-cache-clean -- drop the cache.
## Safe with runs open: every run holds HARDLINKS, so deleting a cache entry
## frees nothing a run still references and breaks no run.
rom-cache-clean:
	@test -n "$(ROM_CACHE_DIR)" || { echo "FAIL: ROM_CACHE_DIR is empty"; exit 1; }
	@rm -rf $(ROM_CACHE_DIR)
	@echo "OK: removed $(ROM_CACHE_DIR) (open runs are unaffected -- they hold hardlinks)"
