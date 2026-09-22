#-----------------------------------------------------------------------------
# ASIC/sta.mk -- where THIS die keeps its signoff-STA data.
#
# THE STAGE ITSELF IS THE TOOLKIT'S. `sta`, `sta-gate`, `sta-vars` and
# `sta-selftest` come from ASIC/asic-toolkit/mk/sta.mk, which mk/flow.mk
# includes; the runner, the Tempus session, the MMMC derivation, the log scan
# and the two graders are ASIC/asic-toolkit/flow/verify/sta/. Promoted
# 2026-09-22 -- see docs/tapeout/79-promoting-signoff-sta-to-the-toolkit.md.
#
# WHAT IS LEFT HERE IS ONE LINE OF DATA. The toolkit defaults STA_DIR to
# $(ASIC_DIR)/sta, i.e. ASIC/eth-chiplet/sta. This project keeps its STA
# directory a level up, beside the flows rather than inside one, because an STA
# run is evidence ABOUT a build and outlives any single P&R tree.
#
# WHY A PLAIN `:=` AND NOT `?=`. This file is included AFTER mk/flow.mk (see
# ASIC/eth-chiplet/Makefile and the note there about target collisions), so the
# toolkit's `STA_DIR ?=` has already bound. A plain assignment overrides it, and
# everything the toolkit derives from STA_DIR -- STA_POLICY, STA_SITE_ENV,
# STA_WORK_ROOT -- is recursively expanded, so all three follow.
#
#     make sta       RUN_TAG=<tag> [IN_DB=<db>]   run Tempus, then grade
#     make sta-gate  RUN_TAG=<tag>                grade an existing run, no licence
#     make sta-vars  RUN_TAG=<tag>                what it would do, without doing it
#     make sta-selftest                           the graders' own batteries
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
#-----------------------------------------------------------------------------

STA_DIR := $(abspath $(ASIC_DIR)/../sta)
