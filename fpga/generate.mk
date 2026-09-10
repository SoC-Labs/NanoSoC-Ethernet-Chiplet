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
