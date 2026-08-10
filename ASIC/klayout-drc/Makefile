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

FLOW_DIR   := $(patsubst %/,%,$(dir $(abspath $(lastword $(MAKEFILE_LIST)))))
DESIGN_DIR := $(FLOW_DIR)/../genus-innovus
BLOCK      := nanosoc_eth_chiplet_pads

DECK   ?= $(FLOW_DIR)/decks/tsmc65_rough.drc
GDS    ?= $(DESIGN_DIR)/outputs/$(BLOCK).gds
TAG     = $(notdir $(basename $(GDS)))
RUNDIR ?= $(FLOW_DIR)/work/$(TAG)
COUNTS  = $(RUNDIR)/$(TAG).counts

## Calibre's summary for the SAME GDS. Override when comparing a different run:
##   make compare CAL_SUMMARY=<path>/…drc.summary
CAL_SUMMARY ?= $(DESIGN_DIR)/work/drc_run/$(BLOCK).drc.summary

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

## Put the two tools' counts side by side. Both must have run on the SAME GDS;
## nothing here checks that for you, so check it yourself.
compare:
	@test -s $(COUNTS) || { echo "FAIL: no KLayout counts at $(COUNTS) - run 'make drc'"; exit 1; }
	@test -s $(CAL_SUMMARY) || { echo "FAIL: no Calibre summary at $(CAL_SUMMARY)"; \
	    echo "      run 'make drc' in ../genus-innovus, or set CAL_SUMMARY=<path>"; exit 1; }
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
