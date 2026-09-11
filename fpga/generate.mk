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
	  phcs="$(PHC_REPO_DIR)"; phcn="$$P/nanosoc-multicore-system/ptp-hardware-clock-ahb"; \
	  cs=$$(git -C "$$phcs" rev-parse --short HEAD 2>/dev/null); \
	  cn=$$(git -C "$$phcn" rev-parse --short HEAD 2>/dev/null); \
	  if [ -n "$$cs" ] && [ -n "$$cn" ] && [ "$$cs" != "$$cn" ]; then \
	    echo "  WARNING  phc_ip is built from an UNPINNED source, and the two differ:"; \
	    echo "             PHC_REPO_DIR (sibling, no sha recorded) $$phcs @ $$cs"; \
	    echo "             pinned submodule                        $$phcn @ $$cn"; \
	    echo "           Only phc_ip is affected - the chiplet's own PHC RTL resolves"; \
	    echo "           through the pinned submodule. But a clone gets $$cn and this"; \
	    echo "           host packages $$cs, so the two do not build the same phc_ip."; \
	    echo "           RESOLVED 2026-09-11 - this is NOT a design decision. The two"; \
	    echo "           are not divergent: the sibling is an ANCESTOR of the pinned"; \
	    echo "           submodule, 7 commits and ~3 months behind, missing a signed"; \
	    echo "           frac-trim fix, an alarm-IRQ W1C fix, a STATUS.running fix and"; \
	    echo "           ASIC bug 7 (hw_capture sync). The PINNED one is correct."; \
	    echo "           Test it in the repo that knows BOTH shas - the sibling has"; \
	    echo "           never fetched the other, so an ancestry test run there"; \
	    echo "           returns false in both directions and reads as 'divergent'."; \
	    echo "           NOT switched here only because PHC_REPO_DIR is defined in"; \
	    echo "           tidelink/fpga/Makefile, a SHARED submodule this project does"; \
	    echo "           not edit. To build the right one, pass it explicitly:"; \
	    echo "             make -C tidelink/fpga package_phc_ip \\"; \
	    echo "                  PHC_REPO_DIR=\$$PWD/nanosoc-multicore-system/ptp-hardware-clock-ahb"; \
	    echo "           MOOT FOR THIS TARGET: phc_ip is added to ip_repo_paths and"; \
	    echo "           then never instantiated - 0 create_bd_cell, 0 in"; \
	    echo "           utilization_hier_{synth,impl}. Being on the IP path is not"; \
	    echo "           being in the design. See fpga/REBUILD.md step 5."; \
	  fi; \
	  echo ""; \
	  echo "  NOTE none of this proves the packaged IP is the V2 build. Packaging"; \
	  echo "  outside \`make package_eth_chiplet_ip\` silently substitutes the V1"; \
	  echo "  GPIO-PHY and still compiles - REBUILD.md step 5 has the tell."; \
	fi

#-----------------------------------------------------------------------------
# ip-phy-check - is the packaged IP the V2 build, or the silent V1 substitute?
#
# THE TRAP THIS EXISTS FOR, measured 2026-09-10.
# tidelink/fpga/vivado_ip/nanosoc_eth_chiplet_filelist.tcl:146-148 DELETES the
# v2 flist the Makefile wrote seconds earlier, and line 57 then falls back to
# the V1 list SILENTLY - exit 0, no warning. The result is a different SoC: the
# whole GPIO-PHY generation is substituted, six PHY framing files vanish, and
# the include directory moves from tidelink-phy to tidelink-gpio-phy. It
# compiles clean and reaches a bitstream.
#
# The make recipe's regeneration step is the only thing preventing it, so
# anyone who sources the packaging TCL directly, re-runs it under another
# driver, or resumes a failed run gets a V1 chiplet. This project does not
# control that file - it lives in a submodule shared with the compute chiplet -
# so instead of relying on the trap being fixed, it DETECTS the result.
#
# TESTED BY NAME, NOT BY COUNT. The reported tell is 601/20/4 sources against
# 597/19/1, but a count moves whenever the design does and would then need
# updating in lockstep - a check that has to be maintained to keep working is
# one that stops working. File presence is a direct fact about which PHY got
# packaged.
#
# TWO-SIDED on purpose: it requires the V2 files present AND the V1-only file
# absent. A one-sided test passes on an IP that somehow contains both, which is
# the shape a half-finished repackage leaves behind.
#-----------------------------------------------------------------------------
IP_PHY_V2_MARKERS := WlinkGPIOPHY_v2.v tidelink_lane_deskew_v2.sv \
                     tidelink_phy_align_calibrator_v2.sv WavD2DGpio_v2.v
IP_PHY_V1_MARKER  := tidelink_eye_regs.sv

## ip-phy-check: prove the packaged IP is the V2 PHY build, not the silent V1 one
##   Runs before synth. Reads only - no Vivado, no licence, under a second.
.PHONY: ip-phy-check
ip-phy-check:
	@bad=""; root=""; \
	for d in $(IP_REPOS); do [ -d "$$d" ] && root="$$root $$d"; done; \
	if [ -z "$$root" ]; then \
	  echo "ip-phy-check: no IP_REPOS directory exists yet - nothing to check."; \
	  echo "  This is not a pass. Run \`make bootstrap-status\`."; exit 0; fi; \
	for m in $(IP_PHY_V2_MARKERS); do \
	  if ! find $$root -name "$$m" 2>/dev/null | grep -q .; then bad="$$bad $$m"; fi; \
	done; \
	v1=$$(find $$root -name '$(IP_PHY_V1_MARKER)' 2>/dev/null | head -1); \
	if [ -n "$$bad" ] || [ -n "$$v1" ]; then \
	  echo "FAIL: the packaged IP is NOT the V2 PHY build." >&2; \
	  [ -n "$$bad" ] && echo "      missing V2 file(s):$$bad" >&2; \
	  [ -n "$$v1" ]  && echo "      found V1-only file: $$v1" >&2; \
	  echo "" >&2; \
	  echo "      The packaging TCL falls back to the V1 GPIO-PHY silently when" >&2; \
	  echo "      its v2 flist is absent - which it deletes itself. A V1 chiplet" >&2; \
	  echo "      compiles clean and reaches a bitstream, so nothing downstream" >&2; \
	  echo "      would have told you." >&2; \
	  echo "" >&2; \
	  echo "      Repackage through the make target, never the TCL directly:" >&2; \
	  echo "        make -C tidelink/fpga package_eth_chiplet_ip" >&2; \
	  echo "      See fpga/REBUILD.md step 5." >&2; \
	  exit 1; fi; \
	echo "  ip-phy-check: V2 PHY confirmed ($(words $(IP_PHY_V2_MARKERS)) markers present, V1 marker absent)"

synth: ip-phy-check
