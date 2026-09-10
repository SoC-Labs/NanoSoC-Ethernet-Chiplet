#-----------------------------------------------------------------------------
# fpga/generate.mk - inputs this project derives, rather than hand-maintains
#
# INCLUDED AFTER mk/flow.mk, and that is not a style choice. A rule's TARGET is
# expanded when the rule is PARSED, and every path here names BUILD_DIR, which
# is an engine variable that does not exist until flow.mk has been read.
# Declared in design.mk (read BEFORE the engine) the target expands to
# `/gen/...` at the filesystem root - a rule nothing ever asks for, failing
# silently. Measured 2026-09-09; deferring the VARIABLE does not help, because
# it is the rule's target that is expanded early.
#
# Every target name below was checked against mk/*.mk and design.mk first. An
# include guard cannot see a target collision.
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

## clocks-xdc: regenerate the synthesis-visible clock definitions
##   Runs automatically before flist and synth. Also useful on its own after
##   editing the timing XDC, to see what synthesis will be told.
.PHONY: clocks-xdc
clocks-xdc: $(XDC_CLOCKS_GEN)

# GENERATED, NEVER HAND-EDITED. The clock definitions have exactly one author -
# tidelink's timing XDC - and a hand-made second copy is a snapshot that drifts
# silently while the original changes. This re-derives it on every build, so the
# two cannot disagree. Same argument as RTL_FLIST_GEN, and the same pattern
# nanosoc_gen uses to emit SDC and XDC from one model.
#
# WHY IT IS NEEDED AT ALL: Vivado converts an RTL clock gate into a clock enable
# only on a net it has been told is a clock. The toolkit reads XDC_TIMING at
# implementation only - correctly, because an EXCEPTION read at synthesis
# changes what synthesis builds - and this design keeps 6 of its 7 clock
# DEFINITIONS in that same file. Synthesis therefore saw one clock, and
# `-gated_clock_conversion auto` would have converted almost nothing while
# reporting success.
#
# Only whole create_clock / create_generated_clock statements are taken,
# continuations included. If the generated file ever contains a set_false_path
# or a set_max_delay then this filter is wrong AND the read-window rule it
# exists to respect has been broken - so the recipe checks, and refuses.
#
# The check allows LEADING WHITESPACE, and that is the whole of its usefulness.
# Written `^set_` it could not fire on the one shape it exists to catch: an
# exception dragged in by a create_clock's line continuation, which is indented
# by convention. Caught 2026-09-09 by feeding it a deliberate leak and watching
# it pass.
$(XDC_CLOCKS_GEN): $(XDC_TIMING)
	@mkdir -p $(dir $@)
	@printf '%s\n' \
	  '# GENERATED from $(notdir $(XDC_TIMING)) by fpga/generate.mk. DO NOT EDIT.' \
	  '# Clock DEFINITIONS only, for SYNTHESIS. Implementation reads the original' \
	  '# file and takes the same definitions from there, so each stage defines' \
	  '# each clock exactly once.' > $@
	@awk '/^[[:space:]]*create_(generated_)?clock/{p=1} \
	      p{print; if ($$0 !~ /\\[[:space:]]*$$/) p=0}' $(XDC_TIMING) >> $@
	@n=$$(grep -c '^create_' $@); \
	 bad=$$(grep -cE '^[[:space:]]*set_' $@ || true); \
	 if [ "$$bad" -ne 0 ]; then \
	   echo "FAIL: $@ contains $$bad set_* statement(s)." >&2; \
	   echo "      This file must hold clock DEFINITIONS only. An exception read" >&2; \
	   echo "      at synthesis changes what synthesis builds, which is the whole" >&2; \
	   echo "      reason XDC_TIMING is withheld from it." >&2; \
	   exit 1; fi; \
	 if [ "$$n" -eq 0 ]; then \
	   echo "FAIL: $@ holds no clock definition." >&2; \
	   echo "      $(XDC_TIMING) defines none, or the filter no longer matches" >&2; \
	   echo "      how they are written. Either way synthesis would be told" >&2; \
	   echo "      nothing and gated-clock conversion would be inert." >&2; \
	   exit 1; fi; \
	 echo "  clocks-xdc: $$n definition(s) -> $@"

# The stages that need it. flist does not read constraints, but generating here
# means a broken filter is found in seconds rather than after synthesis starts.
flist synth: $(XDC_CLOCKS_GEN)

#-----------------------------------------------------------------------------
# bootstrap-status - where am I in the rebuild chain?
#
# A clean clone of this project CANNOT build it: the SoC arrives as packaged IP
# that is gitignored, and reaching that needs four tiers of generated inputs.
# Two of the four must stay untracked - one holds per-machine tool roots and
# resolves an Arm IP release path into a PUBLIC repository, the other is 2626
# files of Arm generator output that are not ours to redistribute. So the chain
# is documented (fpga/REBUILD.md) rather than committed, and this target says
# where you are in it.
#
# READ-ONLY. Generates nothing, takes no licence, and names the ONE command for
# the first tier that is missing rather than listing all of them - a reader
# facing five commands does not know which one to run.
#-----------------------------------------------------------------------------
.PHONY: bootstrap-status
bootstrap-status:
	@echo "Rebuild chain for $(BLOCK) - see fpga/REBUILD.md for why each step exists."
	@echo ""
	@fail=""; \
	chk() { \
	  if [ -n "$$3" ]; then printf '  %-4s %-34s %s\n' "ok" "$$1" "$$2"; \
	  else printf '  %-4s %-34s %s\n' "MISS" "$$1" "$$2"; \
	       [ -z "$$fail" ] && fail="$$4"; fi; \
	  FAILCMD="$$fail"; \
	}; \
	P=$(PROJECT_ROOT); T=$$P/tidelink; \
	n_site=$$([ -f $$T/site.env ] && echo x); \
	n_xhb=$$(find $$T/deps/xhb500/generated -type f 2>/dev/null | head -1); \
	n_soc=$$(find $$P/nanosoc-multicore-system/build_soc/rtl -type f 2>/dev/null | head -1); \
	n_f=$$([ -f $$P/build/elab/soc_vcs.f ] && echo x); \
	n_ip=$$(for d in $(IP_REPOS); do [ -d "$$d" ] && echo x && break; done); \
	fail=""; \
	chk "1. tidelink/site.env"            "per-machine tool + Arm IP roots"   "$$n_site" "cp tidelink/site.env.example tidelink/site.env && edit it"; \
	fail="$$FAILCMD"; \
	chk "2. deps/xhb500/generated"        "Arm XHB-500 generator output"      "$$n_xhb"  "source tidelink/set_env.sh"; \
	fail="$$FAILCMD"; \
	chk "3. build_soc/rtl"                "nanosoc_gen render of sys_desc"    "$$n_soc"  "make -C nanosoc-multicore-system soc"; \
	fail="$$FAILCMD"; \
	chk "4. build/elab/soc_vcs.f"         "flattened flist (no licence needed)" "$$n_f"  "python3 flist/flatten_soc_flist.py ... (or make elab, which also runs VCS)"; \
	fail="$$FAILCMD"; \
	chk "5. IP_REPOS"                     "the SoC as packaged Vivado IP"     "$$n_ip"  "make -C tidelink/fpga package_eth_chiplet_ip"; \
	fail="$$FAILCMD"; \
	echo ""; \
	if [ -n "$$fail" ]; then \
	  echo "  NEXT: $$fail"; \
	  echo ""; \
	  echo "  Only the first missing tier is named on purpose. Each one feeds the"; \
	  echo "  next, so a list of five commands would not tell you which to run."; \
	  exit 1; \
	else \
	  echo "  All five tiers present. \`make check\` then \`make all\`."; \
	  echo ""; \
	  echo "  NOTE none of this proves the packaged IP is the V2 build. Packaging"; \
	  echo "  outside \`make package_eth_chiplet_ip\` silently substitutes the V1"; \
	  echo "  GPIO-PHY and still compiles - REBUILD.md step 5 has the tell."; \
	fi
