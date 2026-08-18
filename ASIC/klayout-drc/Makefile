# ---------------------------------------------------------------------------
# Rough DRC with KLayout --- the laptop-side parallel to `make drc` in
# ../genus-innovus, which is Calibre against the TSMC deck and is the signoff.
#
#   make deck        generate the deck from the PDK   (LAB SERVER ONLY)
#   make drc         run it on the built GDS          (anywhere KLayout runs)
#   make clip        cut a carryable window out of the stream
#   make compare     KLayout counts next to Calibre's
#   make pack        tar up deck + GDS window for a laptop
#
# `make deck` needs /tsmc65pdk. Nothing else here does: `make drc` needs one
# binary, one deck and one GDS, and no licence.
# ---------------------------------------------------------------------------

FLOW_DIR    := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
DESIGN_DIR  := $(FLOW_DIR)/../genus-innovus
TOOLKIT_DIR := $(FLOW_DIR)/../eth-chiplet
BLOCK       := nanosoc_eth_chiplet_pads

DECK   ?= $(FLOW_DIR)/decks/tsmc65_rough.drc

## THE SIGNOFF STREAM IS NOT IN outputs/. `make logo` made outputs/ the home of
## the *submission* artefact (logo-merged) so that "a DRC count can never be
## quoted against the wrong file" (../genus-innovus/Makefile:429). The un-logoed
## signoff stream lives one directory deeper, per run.
##
## IT ALSO IS NOT IN genus-innovus ANY MORE. The implementation flow moved to
## the toolkit, so streams are now at ../eth-chiplet/build/<RUN_TAG>/outputs/.
## Search there FIRST and fall back to the legacy runs/, because
## ../genus-innovus/outputs/ currently holds no GDS at all: a default pointing
## only at the legacy tree cannot find the stream anyone is actually checking.
TOOLKIT_GDS := $(firstword $(shell ls -t $(TOOLKIT_DIR)/build/*/outputs/$(BLOCK).gds 2>/dev/null))
LEGACY_GDS  := $(firstword $(shell ls -t $(DESIGN_DIR)/runs/*/outputs/$(BLOCK).gds 2>/dev/null))
GDS    ?= $(if $(TOOLKIT_GDS),$(TOOLKIT_GDS),$(LEGACY_GDS))

## THE RUN THIS STREAM BELONGS TO, not the file's basename. Every stream in this
## project is called $(BLOCK).gds, so `basename` named every run identically:
## work/ collided between runs, one run's counts silently satisfied the next
## run's `make compare`, and `make pack` overwrote the previous tarball.
## .../build/fp1505/outputs/x.gds -> fp1505 ; .../runs/<stamp>/outputs/x.gds -> <stamp>
TAG     = $(if $(GDS),$(shell d='$(GDS)'; d=$${d%/*}; d=$${d%/eval}; d=$${d%/outputs}; basename "$$d"),)
RUNDIR ?= $(FLOW_DIR)/work/$(TAG)
## run_drc.sh names its outputs after the GDS BASENAME, not after $(TAG).
## Keep this in step with scripts/run_drc.sh:63 or `make compare` stops finding them.
COUNTS  = $(RUNDIR)/$(BLOCK).counts
PROV    = $(RUNDIR)/provenance.txt

## Calibre's summary for the SAME GDS. Newest run under calibre_runs/ by
## default — the Calibre deck is under active development (the switch set moved
## from the INCLUDE wrapper to a project deck header, see
## ../genus-innovus/scripts/calibre/make_project_deck.sh), and each generation
## produces different counts, so pinning one tag here would rot. Override with:
##   make compare CAL_SUMMARY=<path>/…drc.summary
CAL_SUMMARY ?= $(firstword $(shell ls -t $(DESIGN_DIR)/calibre_runs/*/$(BLOCK).drc.summary 2>/dev/null))

## Window for `make clip` and for `make drc CLIP=…`, in um.
BOX     ?= 600,250,750,400
CLIP    ?=
ONLY    ?=
THREADS ?= $(shell nproc 2>/dev/null || echo 4)
PACKDIR ?= $(FLOW_DIR)/pack

.PHONY: all deck drc drc-flat clip compare pack clean help
.DEFAULT_GOAL := help

## Regenerate the deck from the tech LEF + GdsOutMap. Needs the /tsmc65pdk
## mount and membership of group tsmc65pdkgrp. The result carries foundry
## dimensions and is gitignored -- see the header of gen_deck.py.
deck:
	$(FLOW_DIR)/scripts/gen_deck.py -o $(DECK)

## The rough check. Not signoff -- see README.md.
drc:
	@test -n "$(GDS)" || { echo "FAIL: no GDS. outputs/ holds only logo-merged"; \
	    echo "      streams now; the signoff stream is runs/<stamp>/outputs/$(BLOCK).gds"; \
	    echo "      and none was found. Pass one: make drc GDS=<path>"; exit 1; }
	KL_DECK=$(DECK) KL_RUNDIR=$(RUNDIR) KL_THREADS=$(THREADS) \
	    $(if $(CLIP),KL_CLIP=$(CLIP),) $(if $(ONLY),KL_ONLY=$(ONLY),) \
	    $(FLOW_DIR)/scripts/run_drc.sh $(GDS)

## Same run with hierarchical mode off. Slower and hungrier, but it is the
## reference: if deep and flat disagree, distrust the deep result.
drc-flat:
	KL_DECK=$(DECK) KL_RUNDIR=$(RUNDIR)_flat KL_THREADS=$(THREADS) KL_FLAT=1 \
	    $(if $(CLIP),KL_CLIP=$(CLIP),) $(if $(ONLY),KL_ONLY=$(ONLY),) \
	    $(FLOW_DIR)/scripts/run_drc.sh $(GDS)

## Cut BOX out of the stream into something small enough to carry.
clip:
	@mkdir -p $(PACKDIR)
	klayout -b -r $(FLOW_DIR)/scripts/clip_gds.rb \
	    -rd in=$(GDS) -rd out=$(PACKDIR)/$(TAG)_clip.gds -rd box=$(BOX)

## Put the two tools' counts side by side. Both must have run on the SAME GDS.
##
## THIS USED TO SAY "nothing here checks that for you, so check it yourself",
## and that was survivable while both defaults globbed one tree. It is not now.
## The KLayout side globs the newest stream and the Calibre side globs the
## newest summary, INDEPENDENTLY — so once Calibre runs moved to the toolkit
## builds while the stream default still searched the legacy runs/, the two
## defaults pointed at different designs and the comparison stayed silent.
## Measured 2026-08-18: KLayout would have read an Aug-10 legacy stream
## (311,998,380 B) and Calibre a toolkit fp1505 stream (312,343,330 B).
## The stream is recorded on both sides, so it is asserted rather than trusted.
## ALLOW_STREAM_MISMATCH=1 to compare two streams deliberately.
compare:
	@test -s $(COUNTS) || { echo "FAIL: no KLayout counts at $(COUNTS) - run 'make drc'"; exit 1; }
	@test -s $(CAL_SUMMARY) || { echo "FAIL: no Calibre summary at $(CAL_SUMMARY)"; \
	    echo "      run 'make drc' in ../genus-innovus, or set CAL_SUMMARY=<path>"; exit 1; }
	@k=""; [ -s "$(PROV)" ] && k=$$(sed -n 's/^gds=//p' "$(PROV)" | head -1); \
	 c=$$(grep -hoE '/[^ "]*\.gds' "$(CAL_SUMMARY)" 2>/dev/null | head -1); \
	 if [ -z "$$k" ]; then \
	     echo "FAIL: no provenance at $(PROV) — cannot prove both tools read one stream."; \
	     echo "      These counts predate the provenance stamp. Re-run 'make drc',"; \
	     echo "      or set ALLOW_STREAM_MISMATCH=1 to compare them unverified."; \
	     [ "$(ALLOW_STREAM_MISMATCH)" = "1" ] || exit 1; \
	 elif [ -n "$$c" ] && [ "$$(readlink -f "$$k")" != "$$(readlink -f "$$c")" ]; then \
	     echo "FAIL: the two tools did not read the same stream."; \
	     echo "      KLayout : $$k"; \
	     echo "      Calibre : $$c"; \
	     echo "      Counts from different designs are not comparable. Either run"; \
	     echo "      'make drc GDS=$$c', or point CAL_SUMMARY at the run for $$k."; \
	     echo "      ALLOW_STREAM_MISMATCH=1 to compare them anyway."; \
	     [ "$(ALLOW_STREAM_MISMATCH)" = "1" ] || exit 1; \
	 else echo "== same stream on both sides: $$k =="; fi
	$(FLOW_DIR)/scripts/compare_calibre.py $(COUNTS) $(CAL_SUMMARY)

## Everything a laptop needs, in one tarball: the deck and a GDS window.
## Read the NDA note in README.md before this leaves the building.
pack: clip
	@mkdir -p $(PACKDIR)
	@test -s $(DECK) || { echo "FAIL: no deck at $(DECK) - run 'make deck' here first"; exit 1; }
	cp $(DECK) $(PACKDIR)/
	cp $(FLOW_DIR)/scripts/run_drc.sh $(PACKDIR)/
	cp $(FLOW_DIR)/README.md $(PACKDIR)/
	tar czf $(FLOW_DIR)/$(TAG)_klayout_drc.tgz -C $(dir $(PACKDIR)) $(notdir $(PACKDIR))
	@echo
	@echo "OK: $(FLOW_DIR)/$(TAG)_klayout_drc.tgz ($$(du -h $(FLOW_DIR)/$(TAG)_klayout_drc.tgz | cut -f1))"
	@echo "    CONTAINS FOUNDRY-DERIVED DIMENSIONS AND THE DESIGN. Read README.md."

clean:
	rm -rf $(FLOW_DIR)/work $(PACKDIR) $(FLOW_DIR)/*_klayout_drc.tgz

help:
	@echo "KLayout rough DRC - the laptop parallel to Calibre signoff"
	@echo
	@echo "  make deck       generate the deck from /tsmc65pdk   (lab server only)"
	@echo "  make drc        run it on $(GDS)"
	@echo "  make drc CLIP=x1,y1,x2,y2 ONLY=M4,VIA3    one window, some layers"
	@echo "  make drc-flat   same, hierarchical mode off (reference run)"
	@echo "  make clip BOX=x1,y1,x2,y2                 carryable GDS window"
	@echo "  make compare    KLayout counts next to Calibre's"
	@echo "  make pack       tarball for a laptop (deck + window + runner)"
	@echo "  make clean      drop work/ and pack/"
	@echo
	@echo "  deck    : $(DECK)"
	@echo "  gds     : $(GDS)"
	@echo "  rundir  : $(RUNDIR)"
	@echo
	@echo "  NOT SIGNOFF. ../genus-innovus 'make drc' is. See README.md."
