#-----------------------------------------------------------------------------
# Makefile — nanoSoC ethernet chiplet integration
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------
# WHAT THIS DRIVES
#   nanosoc_eth_chiplet — the integration top that wires three submodules
#   (nanosoc-multicore-system, tidelink, tidechart) into one die — plus every
#   gate run over it and the ASIC flow that implements it.
#
#   `make help` lists every target, grouped. Bare `make` prints that help and
#   starts nothing.
#
# WHERE THE BUILD LOGIC LIVES — six makefiles, one job each
#   Makefile (this file)        gates, generated file lists, and pass-throughs
#                               into the ASIC flows. The only tool it invokes
#                               directly is `vcs`, for `elab`.
#   ASIC/eth-chiplet/Makefile   three lines: design.mk, then the asic-toolkit's
#                               mk/flow.mk. THE flow that builds the chip.
#   ASIC/eth-chiplet/design.mk  this design's contract with the toolkit —
#                               libraries, floorplan, MMMC, stage order, and the
#                               project-only stages (DRC, LVS, LEC, ROM).
#   ASIC/common.mk              environment and PDK/IP path resolution shared by
#                               both ASIC flows; included by design.mk and by
#                               ASIC/genus-innovus. Set a project constant here.
#   ASIC/rom_gate.mk            boot-ROM content verification (included by
#                               common.mk).
#   ASIC/rom_build.mk           per-run boot-ROM compilation and its cache
#                               (included by common.mk, after rom_gate.mk).
#   ASIC/genus-innovus/         the frozen legacy implementation flow, and still
#                               the only home of LVS and the padring GDS check.
#   ci-pipeline.conf            the whole check ladder, run by the toolkit's
#                               ci/pipeline.sh — see `asic-pipeline`.
#
# VARIABLES A USER SETS
#   RUN_TAG=<name>  which ASIC build directory to work in,
#                   ASIC/eth-chiplet/build/<name> (default: `default`).
#                   Command-line variables propagate into sub-makes, so
#                   `make asic-syn RUN_TAG=fp1505` reaches the flow.
#   ARGS=--quick    passed through to scripts/regress.sh.
#   GDS=<path>      the stream `asic-padring-gds` should check.
#   HOOK_INSTALLER  path to the toolkit's git-hook installer, if the search
#                   in `hooks` does not find it.
#
# TWO TRAPS
#   1. Adding RTL to tidelink/flists/tidelink_top_full_asic.flist puts NOTHING
#      in the chip. The ASIC build reads a GENERATED flist: `asic-flist` below
#      resolves tidelink_top_full_asic_V2 into build/chip/flist/tidelink_asic.flist,
#      and flist/nanosoc_eth_chiplet_asic.flist -f-includes only that generated
#      file. V2 is the ship configuration; the V1 flist reaches nothing here.
#      `syn` in design.mk depends on asic-flist, so the render is never skipped.
#   2. `make -n` and `make -q` are NOT target-existence probes in this tree. GNU
#      make runs recursive `$(MAKE)` lines even under -n/-t/-q, so the
#      pass-throughs below really enter the ASIC flows and can take a licence
#      seat. To ask what exists, read the makefile or run
#      `make -pRrq < /dev/null`, which only parses and prints the database.
#
# THE ENVIRONMENT IS ASSEMBLED IN THE RECIPES, not by one set_env.sh. Each
# component owns its own; `elab` and `asic-flist` source all three in dependency
# order — this repo, then the SoC, then TideLink — because TideLink defaults
# CMSDK_DIR with `:=` and the SoC's choice has to win.
#
# HELP TEXT LIVES NEXT TO ITS TARGET. A line `## <target>: <one line>` is picked
# up by `help`; `##@<n> <title>` opens a group, printed in number order. Plain
# `#` comments are never listed, so use `#` for anything that is not help text.
#-----------------------------------------------------------------------------

SHELL := /bin/bash
.ONESHELL:

CHIPLET_HOME := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
FLIST        := $(CHIPLET_HOME)/flist/nanosoc_eth_chiplet.flist
TOP          := nanosoc_eth_chiplet
SIMV         := simv_chiplet
BUILD        := $(CHIPLET_HOME)/build/elab

# Generated file lists. The *_VCS_* pair is flattened for VCS (`elab`); the
# *_ASIC_* pair is what the ASIC flist -f-includes. Both are rendered by the
# recipes below, never hand-edited.
export CHIPLET_SOC_VCS_FLIST := $(BUILD)/soc_vcs.f
export CHIPLET_SOC_ASIC_FLIST := $(CHIPLET_HOME)/build/chip/flist/soc.flist
# resolve_tidelink_flist.py drops TideLink's shadowed deps module so exactly
# one definition of every module reaches the compiler: leaning on VCS's "last
# declaration wins" would let a first-wins tool bind the copy that lacks the
# a2l reset-skew fix.
export CHIPLET_TL_VCS_FLIST := $(BUILD)/tidelink_vcs.f
export CHIPLET_TL_ASIC_FLIST := $(CHIPLET_HOME)/build/chip/flist/tidelink_asic.flist

VCS_FLAGS    := -full64 -sverilog -timescale=1ns/1ps

# The flow that builds this chip: the asic-toolkit entry point. Everything
# under signoff came out of it — the shipping GDS is
# ASIC/eth-chiplet/build/full-20260814/outputs/nanosoc_eth_chiplet_pads.gds,
# and the shipping netlist carries the toolkit's provenance block in
# reports/syn_manifest.txt.
ASIC_DIR     := $(CHIPLET_HOME)/ASIC/eth-chiplet

# The legacy flow. Frozen, still runnable, reachable as `make asic-*-legacy`;
# no CI gate calls it and its outputs/ holds no netlist and no GDS. The
# DIRECTORY is still live for reasons unrelated to its stages: design.mk reads
# its floorplan, power plan, MMMC and .io files, and it hosts lec/rail/romlibs
# and the LVS setup. Retiring the stage targets and retiring the directory are
# different changes.
LEGACY_ASIC_DIR := $(CHIPLET_HOME)/ASIC/genus-innovus

TOOLKIT_DIR  := $(CHIPLET_HOME)/ASIC/asic-toolkit

.PHONY: bootstrap elab chip-boundary chip-wrapper lint check regress cdc elab-strict clean
.PHONY: vendor-check hooks
.PHONY: bscan bscan-table bscan-gen bscan-splice bscan-check bscan-sim
.PHONY: help asic asic-status asic-syn asic-pnr asic-gds asic-drc asic-padring-gds
.PHONY: asic-lvs asic-lvs-pre asic-lec-pnr asic-pipeline asic-pipeline-resume
.PHONY: asic-legacy asic-status-legacy asic-syn-legacy asic-pnr-legacy
.PHONY: asic-gds-legacy asic-lec-pnr-legacy asic-drc-legacy
.PHONY: asic-lvs-legacy asic-lvs-pre-legacy

# Bare `make` must not start a 42-submodule fetch, which is what happened when
# `bootstrap` was simply the first target in the file.
.DEFAULT_GOAL := help

##@1 Setup

## help: list every target in this Makefile, grouped by what it is for.
help:
	@echo "nanosoc_eth_chiplet — integration top.   usage: make <target> [VAR=value]"
	awk '
	  /^##@[0-9]/ { n = substr($$0, 4) + 0; t = substr($$0, 4);
	                sub(/^[0-9]+[ \t]*/, "", t); title[n] = t; cur = n; next }
	  /^## [a-z][a-zA-Z0-9_.-]*:/ { e = substr($$0, 4); c = index(e, ":");
	                body[cur] = body[cur] sprintf("  %-22s %s\n",
	                            substr(e, 1, c-1), substr(e, c+2)) }
	  END { for (i = 1; i <= 9; i++)
	          if (title[i] != "") printf "\n%s\n%s", title[i], body[i] }
	' "$(CHIPLET_HOME)/Makefile"
	echo
	echo "  RUN_TAG=<name> selects the ASIC build dir; ARGS= is passed to regress.sh."
	echo "  LVS and the padring GDS check still run out of ASIC/genus-innovus."
	echo "  -n / -q do NOT probe for a target here: the ASIC pass-throughs run under them."
	echo

#-----------------------------------------------------------------------------
# ASIC pass-throughs
#-----------------------------------------------------------------------------
# The implementation flow reachable from the repo root like every other gate.
# $(ASIC_DIR)/Makefile is the authority; these only forward, and the stage names
# differ between the two flows, so the mapping is spelled out once:
#
#     root target       toolkit ($(ASIC_DIR))   legacy ($(LEGACY_ASIC_DIR))
#     asic              help                    help
#     asic-status       status                  status
#     asic-syn          syn                     syn
#     asic-pnr          place cts route         pnr_place pnr_cts pnr_route
#     asic-gds          all                     pnr_all
#     asic-lec-pnr      lec-pnr                 lec-pnr
#     asic-pipeline     pipeline                — none
#     asic-drc          drc                     drc            (asic-drc-legacy)
#     asic-lvs          lvs                     lvs            (asic-lvs-legacy)
#     asic-lvs-pre      lvs-preflight           lvs-preflight  (asic-lvs-pre-legacy)
#
# `pipeline` is not `all` renamed: `all` is syn->place->cts->route and stops at
# the first failure, while `pipeline` runs the whole declared ladder from
# ci-pipeline.conf and deliberately continues past failures. There is no legacy
# counterpart, hence no asic-pipeline-legacy.
#
# NONE of these pass a RUN_TAG, so a bare `make asic-<stage>` works in
# build/default. ci/signoff.yaml spells its own tag out rather than calling
# these. A command-line RUN_TAG= reaches the sub-make.

##@6 ASIC implementation — ASIC/eth-chiplet, the asic-toolkit flow

## asic: the ASIC flow's own help, listing every stage it offers.
asic:        ; @$(MAKE) -C $(ASIC_DIR) --no-print-directory help
## asic-status: which flow stages have run in this build directory.
asic-status: ; @$(MAKE) -C $(ASIC_DIR) --no-print-directory status
## asic-syn: synthesis (Genus) -> gate netlist, SDC and reports.
asic-syn:    ; $(MAKE) -C $(ASIC_DIR) syn
## asic-pnr: place + CTS + route (Innovus) -> routed DB and GDSII. Multi-hour.
asic-pnr:    ; $(MAKE) -C $(ASIC_DIR) place cts route
## asic-gds: syn + place + cts + route, unattended, end to end.
asic-gds:    ; $(MAKE) -C $(ASIC_DIR) all
## asic-lec-pnr: Conformal LEC, synthesis netlist against the post-P&R netlist.
asic-lec-pnr: ; $(MAKE) -C $(ASIC_DIR) lec-pnr
## asic-pipeline: run every declared check in order, past failures, then collate.
## asic-pipeline-resume: re-run only the pipeline stages that have not passed.
#  A superset of asic-gds. The ladder is declared in ci-pipeline.conf.
asic-pipeline:        ; $(MAKE) -C $(ASIC_DIR) pipeline
asic-pipeline-resume: ; $(MAKE) -C $(ASIC_DIR) pipeline-resume

##@7 Physical signoff gates

# The toolkit dispatches `drc` to drc-project, whose runner is
# $(LEGACY_ASIC_DIR)/scripts/calibre/run_drc.sh (design.mk:434) with DRC_DECK
# empty so it takes its assembling branch — same script and same foundry deck
# as the legacy stage, pointed at a different GDS.
## asic-drc: Calibre DRC over the GDS this build produced.
asic-drc:        ; $(MAKE) -C $(ASIC_DIR) drc
## asic-drc-legacy: the same deck over the legacy flow's GDS.
asic-drc-legacy: ; $(MAKE) -C $(LEGACY_ASIC_DIR) drc

# The local, licence-free analogue of the foundry's CompareCells +
# Padringcheck: pad cell names, counts and order in a streamed GDS against the
# pad ring's own sources. scripts/check_padring_gds.py records what it can and
# cannot see. It lives in the LEGACY directory with the bnd/logo/drc
# infrastructure it reuses and has not been ported to the toolkit, so a
# toolkit-built stream must be named explicitly:
#   make asic-padring-gds GDS=ASIC/eth-chiplet/build/fp1505/outputs/nanosoc_eth_chiplet_pads.gds
## asic-padring-gds: padframe name/count/order check on a built GDS.
asic-padring-gds: ; $(MAKE) -C $(LEGACY_ASIC_DIR) padring-gds

# LVS runs on the toolkit path but has NEVER been executed there — only its
# preflight has. Preflight-clean is not run-clean; treat the first
# `make asic-lvs` as an experiment. Both halves name one flow on purpose: when
# preflight and the full run graded different streams, the gate answered a
# question nobody had asked and reported it as the answer to the one they had.
# With no RUN_TAG the toolkit's input check names each missing input and exits
# 2, rather than silently grading a stale artefact.
## asic-lvs: Calibre nmLVS on the built layout against the netlist.
asic-lvs:         ; $(MAKE) -C $(ASIC_DIR) lvs
## asic-lvs-pre: the LVS input preflight alone — no licence, no long run.
asic-lvs-pre:     ; $(MAKE) -C $(ASIC_DIR) lvs-preflight
## asic-lvs-legacy: nmLVS in the legacy flow.
#  Its lvs_project.mk still holds this design's original LVS input declarations.
asic-lvs-legacy:     ; $(MAKE) -C $(LEGACY_ASIC_DIR) lvs
## asic-lvs-pre-legacy: that flow's preflight.
asic-lvs-pre-legacy: ; $(MAKE) -C $(LEGACY_ASIC_DIR) lvs-preflight

##@8 Legacy implementation flow — ASIC/genus-innovus, frozen

# Kept runnable, not deleted: these four stage targets are the only entry
# points in the repository that reach the ASIC/asic-flows submodule at all.
# No CI gate calls any of them.
## asic-legacy: the legacy flow's own help.
asic-legacy:        ; @$(MAKE) -C $(LEGACY_ASIC_DIR) --no-print-directory help
## asic-status-legacy: which legacy stages have run.
asic-status-legacy: ; @$(MAKE) -C $(LEGACY_ASIC_DIR) --no-print-directory status
## asic-syn-legacy: synthesis in the legacy flow.
asic-syn-legacy:    ; $(MAKE) -C $(LEGACY_ASIC_DIR) syn
## asic-pnr-legacy: place + CTS + route in the legacy flow.
asic-pnr-legacy:    ; $(MAKE) -C $(LEGACY_ASIC_DIR) pnr_place pnr_cts pnr_route
## asic-gds-legacy: the legacy flow's full P&R to GDSII.
asic-gds-legacy:    ; $(MAKE) -C $(LEGACY_ASIC_DIR) pnr_all
## asic-lec-pnr-legacy: LEC over the legacy flow's netlists.
asic-lec-pnr-legacy: ; $(MAKE) -C $(LEGACY_ASIC_DIR) lec-pnr

##@1 Setup

## bootstrap: fetch all 42 submodules (not `git clone --recursive`).
#  Some remotes are SSH-only and are fetched separately; see scripts/bootstrap.sh.
bootstrap:
	"$(CHIPLET_HOME)/scripts/bootstrap.sh"

##@2 Fast checks — no EDA licence, runnable in a fresh clone

## lint: Verilator structural lint over the wrapper RTL.
#  Combinational loops, inferred latches, width and undriven-net faults that
#  `elab` cannot see.
#  Findings and waivers: docs/verification/LINT_FINDINGS.md.
lint:
	"$(CHIPLET_HOME)/scripts/lint.sh"

## vendor-check: prove no TSMC foundry collateral is tracked in this PUBLIC repo.
#  The PDK licence does not permit reproducing vendor files.
#
#  BOTH scanners run, in the order the PR gate runs them, and neither is a
#  superset of the other:
#    scripts/ci/check_no_vendor_collateral.sh   tracked *.lef by content SHA
#      and size, plus — only where a PDK is readable — runs of verbatim vendor
#      text in a file of any type. Its pathspec cannot match .tlef, .lib,
#      .captable, .map or .gds.
#    ASIC/asic-toolkit/ci/check-vendor-collateral.sh   ~20 collateral
#      suffixes, size, content SHA, and seven text rules (values, GDS
#      layer/datatype pairs, revision-coded release names, absolute site paths,
#      captured licence output). Needs no PDK, licence or tool.
#
#  A local gate greener than the PR gate is worse than none: it sends people to
#  a red PR having told them they were clean. If the two must differ, change CI
#  first. A missing toolkit scanner is a FAILURE here, not a skip.
vendor-check:
	@set -uo pipefail
	rc=0
	echo "== scanner 1/2: scripts/ci/check_no_vendor_collateral.sh =="
	"$(CHIPLET_HOME)/scripts/ci/check_no_vendor_collateral.sh" || rc=1
	echo
	echo "== scanner 2/2: ASIC/asic-toolkit/ci/check-vendor-collateral.sh =="
	tk="$(TOOLKIT_DIR)/ci/check-vendor-collateral.sh"
	if [ ! -r "$$tk" ]; then
	    echo "make vendor-check: the toolkit content scanner is not present." >&2
	    echo >&2
	    if [ ! -d "$(TOOLKIT_DIR)/.git" ] && [ ! -f "$(TOOLKIT_DIR)/.git" ]; then
	        echo "  ASIC/asic-toolkit is not checked out. Run: make bootstrap" >&2
	    else
	        echo "  ASIC/asic-toolkit is checked out but has no" >&2
	        echo "  ci/check-vendor-collateral.sh — the submodule pin predates it." >&2
	        echo "  Roll the pin forward: git -C ASIC/asic-toolkit log --oneline -5" >&2
	    fi
	    echo >&2
	    echo "  THIS IS A FAILURE, NOT A SKIP. Scanner 1 above cannot see a" >&2
	    echo "  tracked .tlef, .lib, .captable, .map or .gds, so a green run" >&2
	    echo "  without scanner 2 would mean less than it looks like — which is" >&2
	    echo "  exactly what the PR gate was doing before both were wired in." >&2
	    exit 1
	fi
	# Run from CHIPLET_HOME: the scanner takes its corpus from `git ls-files` in
	# whatever repository it is invoked FROM, not from where the script lives.
	# Invoked from inside the submodule it would faithfully scan the toolkit.
	cd "$(CHIPLET_HOME)"
	bash "$$tk" < /dev/null || rc=1
	if [ $$rc -ne 0 ]; then
	    echo >&2
	    echo "== vendor-check FAILED — see the findings above ==" >&2
	    exit 1
	fi
	echo
	echo "== vendor-check OK: both scanners clean =="

##@1 Setup

## hooks: install the toolkit's pre-commit / pre-push vendor guards in this clone.
#  CI catches vendor collateral after a push; a hook catches it before
#  it leaves the machine. The hooks and the installer belong to the toolkit
#  submodule and this target only calls it — a second copy of the install
#  routine here would be the one that goes stale. Point it at a specific
#  installer with `make hooks HOOK_INSTALLER=/path/to/installer`.
HOOK_INSTALLER ?=
HOOK_ARGS      ?=
hooks:
	@set -uo pipefail
	inst="$(HOOK_INSTALLER)"
	if [ -z "$$inst" ]; then
	    # Candidate paths, in the order the toolkit is most likely to use.
	    # First hit wins; if the toolkit lands the installer somewhere else,
	    # add it here rather than copying its logic into this file.
	    for c in "$(TOOLKIT_DIR)/hooks/install.sh" \
	             "$(TOOLKIT_DIR)/hooks/install-hooks.sh" \
	             "$(TOOLKIT_DIR)/scripts/asic-flow-install-hooks" \
	             "$(TOOLKIT_DIR)/ci/install-hooks.sh"; do
	        if [ -x "$$c" ]; then inst="$$c"; break; fi
	    done
	fi
	if [ -z "$$inst" ]; then
	    echo "make hooks: no hook installer found in the toolkit." >&2
	    echo >&2
	    if [ ! -d "$(TOOLKIT_DIR)/.git" ] && [ ! -f "$(TOOLKIT_DIR)/.git" ]; then
	        echo "  ASIC/asic-toolkit is not checked out. Run: make bootstrap" >&2
	    else
	        echo "  ASIC/asic-toolkit is checked out, but none of these exist" >&2
	        echo "  and are executable:" >&2
	        echo "      ASIC/asic-toolkit/hooks/install.sh" >&2
	        echo "      ASIC/asic-toolkit/hooks/install-hooks.sh" >&2
	        echo "      ASIC/asic-toolkit/scripts/asic-flow-install-hooks" >&2
	        echo "      ASIC/asic-toolkit/ci/install-hooks.sh" >&2
	        echo >&2
	        echo "  The hooks may not have landed upstream yet, or the submodule" >&2
	        echo "  pin predates them: git -C ASIC/asic-toolkit log --oneline -5" >&2
	        echo "  Point this target at it directly with:" >&2
	        echo "      make hooks HOOK_INSTALLER=<path>" >&2
	    fi
	    echo >&2
	    echo "  UNTIL THEN THERE IS NO LOCAL GUARD. Run \`make vendor-check\`" >&2
	    echo "  by hand before every commit that adds a file; CI's vendor-guard" >&2
	    echo "  workflow is the backstop, and it only fires after you push." >&2
	    exit 1
	fi
	echo "== installing git hooks via $$inst =="
	cd "$(CHIPLET_HOME)"
	"$$inst" $(HOOK_ARGS) || exit $$?
	# Report what actually landed. This is confirmation, not installation --
	# the installer above owns where the hooks go and what they contain.
	hookdir=$$(git rev-parse --git-path hooks)
	echo
	echo "hooks now present in $$hookdir:"
	found=0
	for h in pre-commit pre-push; do
	    if [ -x "$$hookdir/$$h" ]; then echo "  $$h"; found=1; fi
	done
	if [ $$found -eq 0 ]; then
	    echo "  (none) — the installer exited 0 but installed no pre-commit or" >&2
	    echo "  pre-push hook. Treat this as a failure, not a clean run." >&2
	    exit 1
	fi

##@2 Fast checks — no EDA licence, runnable in a fresh clone

## check: the licence-free gate set - vendor-check + chip-boundary + lint.
#  `elab` and the verif/ environments need a tool licence on top.
check: vendor-check chip-boundary lint
	@echo "== check OK: vendor-check + chip-boundary + lint clean =="

##@3 Simulation and structural gates — need a tool licence

## regress: every data-plane simulation proof, as one pass/fail table. Needs VCS.
#  Decode tx-gate and hready-loop guards, g2_peer_aperture, and the two-real-SoC
#  g2_soc_pair write + read + burst. `ARGS=--quick` skips the two-SoC long pole.
#  See scripts/regress.sh.
regress:
	"$(CHIPLET_HOME)/scripts/regress.sh" $(ARGS)

## cdc: structural clock-domain-crossing pass over the integrated top.
#  Cadence HAL via xrun -hal; ~25 min, needs an Xcelium/HAL licence.
#  Findings: docs/verification/CDC_FINDINGS.md.
cdc:
	"$(CHIPLET_HOME)/verif/cdc/run.sh"

## elab-strict: strict ASIC-elaboration gate for the blockers a simulator hides.
#  Above all a same-clock procedural MULTI-DRIVER, which fc_shell and Genus
#  reject but VCS and Verilator accept. xrun -hal, gates on MLTDRV in authored
#  RTL; ~25 min. See docs/verification/ELAB_STRICT_FINDINGS.md.
elab-strict:
	"$(CHIPLET_HOME)/verif/elab_strict/run.sh"

#-----------------------------------------------------------------------------
# IEEE 1149.1 boundary scan
#-----------------------------------------------------------------------------
# The per-design configuration is the seven variables below and nothing else;
# the three scripts are design-agnostic, so a second chiplet adopting the flow
# changes only this block.
#
# The table is parsed from a PRISTINE ring. Once the register is spliced in the
# pad cells no longer touch the core nets, so re-parsing the live ring yields a
# table wired to the register itself — which still elaborates, still lints, still
# counts 76 cells, and is wrong. gen_pad_table.py refuses to parse a spliced
# ring; `bscan-table` recovers the pre-splice ring out of git and parses that.

##@4 Boundary scan (IEEE 1149.1)

BSCAN_BLOCK    := nanosoc_eth_chiplet_pads
BSCAN_MODULE   := nanosoc_eth_chiplet_bscan
BSCAN_PADRING  := ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v
BSCAN_IO       := ASIC/genus-innovus/scripts/nanosoc_eth_chiplet_pads.io
BSCAN_TABLE    := src/rtl/bscan/pad_table.json
# TAP pins are muxed onto existing pads — no new bonds. SE was bonded and
# driving nothing, which is why it is the enable.
BSCAN_TAP      := --tap-en uPAD_SE_I --tap-tck uPAD_SWDCK_I --tap-tms uPAD_SWDIO_IO \
                  --tap-tdi uPAD_HOST_IO_0 --tap-tdo uPAD_HOST_IO_1
# PLACEHOLDER: SoC Labs holds no JEDEC manufacturer ID. Until one is assigned a
# tester will bind the wrong BSDL to this die.
BSCAN_IDCODE   := 0x100005A1
# The commit whose pad ring predates the splice.
BSCAN_PRISTINE := 458d108

## bscan-table: re-derive the pad table from the PRE-SPLICE pad ring.
bscan-table:
	@git show $(BSCAN_PRISTINE):$(BSCAN_PADRING) > $(BUILD)/pristine_pads.v
	python3 "$(CHIPLET_HOME)/scripts/gen_pad_table.py" \
	    --padring $(BUILD)/pristine_pads.v --record-padring $(BSCAN_PADRING) \
	    --io $(BSCAN_IO) --block $(BSCAN_BLOCK) --module $(BSCAN_MODULE) \
	    $(BSCAN_TAP) --idcode $(BSCAN_IDCODE) -o $(BSCAN_TABLE)

## bscan-gen: regenerate the wrapper RTL and the BSDL from the table.
bscan-gen:
	python3 "$(CHIPLET_HOME)/scripts/gen_bscan.py"

## bscan-splice: wire the register into the pad ring (idempotent).
bscan-splice:
	python3 "$(CHIPLET_HOME)/scripts/insert_bscan_padring.py"

## bscan-check: fail if the generated files have drifted from the table.
bscan-check:
	python3 "$(CHIPLET_HOME)/scripts/gen_bscan.py" --check
	python3 "$(CHIPLET_HOME)/scripts/insert_bscan_padring.py" --check
	python3 "$(CHIPLET_HOME)/scripts/check_chip_boundary.py"

## bscan-sim: run the self-checking boundary-scan bench under VCS.
bscan-sim:
	cd "$(CHIPLET_HOME)/verif/bscan" && ./run.sh

## bscan: table -> generate -> splice -> check.
bscan: bscan-table bscan-gen bscan-splice bscan-check

##@2 Fast checks — no EDA licence, runnable in a fresh clone

## chip-boundary: check the boundary spec covers every RTL port exactly once.
#  Fails on an unclassified port, a stale name, or a direction/width mismatch.
#  An unclassified port is dropped from the wrapper and its inputs then float.
chip-boundary:
	python3 "$(CHIPLET_HOME)/scripts/check_chip_boundary.py"

## chip-wrapper: chip-boundary, then emit build/chip/rtl/*_chip.v.
chip-wrapper:
	python3 "$(CHIPLET_HOME)/scripts/check_chip_boundary.py" --emit "$(CHIPLET_HOME)/build/chip/rtl"

##@3 Simulation and structural gates — need a tool licence

## elab: structurally elaborate the integration top under VCS.
#  The proof that the wrapper wires the three components together consistently.
#  Output: build/elab/simv_chiplet and build/elab/elab.log.
elab:
	source "$(CHIPLET_HOME)/set_env.sh"
	source "$(CHIPLET_HOME)/nanosoc-multicore-system/set_env.sh"
	source "$(CHIPLET_HOME)/tidelink/set_env.sh"
	mkdir -p "$(BUILD)"
	# Flatten the SoC's generated flist into a VCS-readable one: the generator
	# emits $()-syntax paths VCS cannot expand. Re-rendered every run so it
	# tracks the current build_soc.
	python3 "$(CHIPLET_HOME)/flist/flatten_soc_flist.py" \
	    "$${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore.flist" > "$(CHIPLET_SOC_VCS_FLIST)"
	# Resolve TideLink's flist to one definition per module (tool-independent).
	# V2, matching `asic-flist`: V2 IS THE SHIP CONFIGURATION, and it is the only
	# flist listing tidelink_fcemit_obs / tidelink_winscan_obs, which the shared
	# local_overrides/Wlink.v instantiates. V1 fails outright with
	# `Error-[CFCILFBI] Cannot find cell in liblist`. No +define+ is needed: the
	# V2 flist carries TIDELINK_PHY_V2 through per-file shims.
	python3 "$(CHIPLET_HOME)/flist/resolve_tidelink_flist.py" \
	    "$${TIDELINK_HOME}/flists/tidelink_fpga_v2.flist" > "$(CHIPLET_TL_VCS_FLIST)"
	cd "$(BUILD)"
	echo "== vcs $(VCS_FLAGS) -f $(FLIST) -top $(TOP) -o $(SIMV) =="
	vcs $(VCS_FLAGS) -f "$(FLIST)" -top $(TOP) -o "$(SIMV)" -l "$(BUILD)/elab.log"

##@5 Generated file lists

## asic-flist: render build/chip/flist/{soc,tidelink_asic}.flist.
#  These are the two generated sub-flists the ASIC flist -f-includes.
#
#  THIS TARGET SELECTS THE PHY THAT REACHES SYNTHESIS. It resolves
#  tidelink_top_full_asic_V2 — the shared deps/tidelink-phy GPIO-PHY — not the
#  V1 tidelink_top_full_asic. The two carry same-named modules and can never
#  co-compile, so editing V1 changes nothing about this chip.
#  V2 needs the deps/tidelink-phy submodule, whose remote is SSH-only and is
#  therefore not fetched by a plain `git submodule update --init`; `make
#  bootstrap` covers it, and the guard below names the fix if it is missing.
asic-flist:
	source "$(CHIPLET_HOME)/set_env.sh"
	source "$(CHIPLET_HOME)/nanosoc-multicore-system/set_env.sh"
	source "$(CHIPLET_HOME)/tidelink/set_env.sh"
	mkdir -p "$(BUILD)" "$(dir $(CHIPLET_SOC_ASIC_FLIST))"
	test -d "$${TIDELINK_HOME}/deps/tidelink-phy/rtl" || { \
	    echo "asic-flist: MISSING $${TIDELINK_HOME}/deps/tidelink-phy — the V2 PHY."; \
	    echo "            run: git -C $${TIDELINK_HOME} submodule update --init deps/tidelink-phy"; \
	    exit 1; }
	python3 "$(CHIPLET_HOME)/flist/flatten_soc_flist.py" \
	    "$${NANOSOC_MULTICORE_HOME}/flist/nanosoc_multicore_asic.flist" > "$(CHIPLET_SOC_ASIC_FLIST)"
	python3 "$(CHIPLET_HOME)/flist/resolve_tidelink_flist.py" \
	    "$${TIDELINK_HOME}/flists/tidelink_top_full_asic_v2.flist" > "$(CHIPLET_TL_ASIC_FLIST)"

##@9 Cleaning

## clean: remove build/elab (the elaboration artefacts only).
clean:
	rm -rf "$(BUILD)"
