# -----------------------------------------------------------------------------
# provenance.spec -- what a run of THIS design must record about itself.
# A joint work commissioned on behalf of SoC Labs, under Arm Academic Access license.
#
# Copyright 2026, SoC Labs (www.soclabs.org)
# -----------------------------------------------------------------------------
# Read by scripts/ci/run_provenance.py. The engine is design-agnostic and names
# nothing; this file is where the design lives. That split is the migration
# doc's boundary rule -- "does the file name the design?" -- applied to run
# provenance: the engine goes to ASIC/asic-toolkit, this file stays here.
#
# THE ONE RULE THAT MATTERS IN HERE
# ---------------------------------
# Do not restate the flow's input list. Point at where the flow ALREADY declares
# it and read the declaration back:
#
#   tcl-var lef_file_list   evaluates ASIC/genus-innovus/scripts/config.tcl and
#                           takes the list the flow itself builds. Add a macro
#                           to config.tcl and the next capture picks it up with
#                           no edit here.
#   make-var ASIC_FLIST     reads GNU make's own database (`make -qp`, no recipe
#                           runs) rather than repeating a path.
#   flist make:ASIC_FLIST   walks that flist with exactly the semantics of
#                           scripts/read_flist.tcl, down to the rule that only
#                           *.v / *.sv count as source.
#
# A spec maintained in parallel with the flow goes stale, and a stale provenance
# spec is worse than none, because it looks complete.
#
# NO FOUNDRY PATHS IN THIS FILE. It is tracked, and this repository is public.
# `env-from-make` pulls TSMC_65_HOME and friends out of ASIC/common.mk at
# capture time; their values land only in the run directory, which is
# gitignored. See scripts/ci/check_no_vendor_collateral.sh for why this matters.
#
# GROUP ATTRIBUTES
#   min=N       fewer than N files resolving is a FAILURE, not an empty result.
#               This is the whole defence against the check that silently finds
#               nothing and reports success.
#   copy        archive byte copies. The engine NEVER copies a file classified
#               `external` (PDK, /research, EDA installs) whatever this says.
#   phases=...  the group is only enforced at these capture phases. For inputs
#               that cannot exist before a stage has produced them.
# -----------------------------------------------------------------------------

set DESIGN  $REPO/ASIC/genus-innovus
set TECHW   $REPO/ASIC/tech_wrappers/tsmc65

# --- environment -------------------------------------------------------------
# Snapshot take 1 of the 2026-08-13 reference run resolved ZERO RTL files
# because set_env.sh had not been sourced and ${NANOSOC_ETH_CHIPLET_HOME} did
# not expand. Sourcing the same script the flow sources is the only way this
# cannot drift from the flow.
env-script      $REPO/set_env.sh
env-from-make   $DESIGN  DESIGN_HOME TSMC_65_HOME ASIC_FLIST PHYS_IP ARM_IP_LIBRARY_PATH
env-require     ASIC_FLIST
env-require     TSMC_65_HOME
env-require     NANOSOC_ETH_CHIPLET_HOME
env-require     TIDELINK_HOME
env-require     TIDECHART_HOME

# The flow's own input declaration, evaluated with a swallowing `unknown` so
# every EDA command in it is a no-op. Costs no licence.
tcl-config      $DESIGN/scripts/config.tcl   $DESIGN/scripts

# The make database that drives the same flow.
make-dir        $DESIGN

# --- environment recorded verbatim ------------------------------------------
# Every knob the stage scripts read through `opt` (flow_utils.tcl) arrives as an
# environment variable, so recording these records the gate configuration.
record-env      EVAL_*
record-env      EVP_*
record-env      EVC_*
record-env      EVR_*
record-env      CLK_PERIOD
record-env      PRE_CTS_OPT
record-env      CONN_LIMIT
record-env      SDC_STALE_OK
record-env      ROM_GDS_GATE
record-env      LOGO_STRIP_JACK
record-env      INNOVUS_*
record-env      MAKEFLAGS
record-env      SEED_OUTPUTS_FROM
record-env      SEED_WORK_FROM

# --- deviations, auto-detected ----------------------------------------------
# `deviation-env NAME DEFAULT`: if NAME is set to anything but DEFAULT, the run
# deviated from a clean invocation and says so in DEVIATIONS.txt at top level.
#
# The defaults below are the `opt` defaults in the stage scripts, NOT a wish.
# This is the check that would have caught the run behind the 838/966 DRC
# numbers: it placed with EVP_STRICT=0, its PG audit failed on three counts,
# the databases were written anyway, and nothing in the run recorded it.
deviation-env   EVAL_STRICT             1
deviation-env   EVAL_CHECKS             1
deviation-env   EVP_STRICT              1
deviation-env   EVP_CHECKS              1
deviation-env   EVP_PG_AUDIT            1
deviation-env   EVP_INPUT_CONTRACT      1
deviation-env   EVP_MACRO_PRECHECK      1
deviation-env   EVP_TIMING_CHECKS       1
deviation-env   EVP_CONN_CHECK          1
deviation-env   EVP_SKIP_PLACE          0
deviation-env   EVP_SDC_STALE_OK        0
deviation-env   EVP_MIN_RV_VIAS         8
deviation-env   EVP_MAX_M5_FRAGS        1500
deviation-env   EVP_EXPECT_MACROS       21
deviation-env   EVP_MIN_ENDCAPS         4400
deviation-env   EVC_STRICT              1
deviation-env   EVC_CHECKS              1
deviation-env   EVC_ASSERT_OCV          1
deviation-env   EVC_ALLOW_NO_WRITEBACK  0
deviation-env   EVR_STRICT              1
deviation-env   EVR_CHECKS              1
deviation-env   EVR_PG_AUDIT            1
deviation-env   EVR_UNCAP_CHECKS        1
deviation-env   EVR_DENSITY_CHECK       1
deviation-env   EVR_BUDGET_OPENS        350
deviation-env   EVR_BUDGET_DANGLING     1518
deviation-env   EVR_MIN_GDS_MB          200
deviation-env   CLK_PERIOD              10.0
deviation-env   ROM_GDS_GATE            block
deviation-env   PRE_CTS_OPT             1

# =============================================================================
# INPUT GROUPS
# =============================================================================

# The Tcl the four stage drivers source, plus the make layer above them. All of
# it is project-authored text; copying it is cheap and it is the thing that
# moved under the 2026-08-13 run (power_plan.tcl at +63 s, the Makefile at
# +2 min, common.mk at +4 min).
group flow_script min=45 copy
  note  Everything under scripts/, recursively: the stage drivers, the .io, the
  note  .mmmc, the Calibre and LEC decks, the probe and census helpers.
  glob  $DESIGN/scripts/**
  file  $DESIGN/Makefile
  file  $REPO/ASIC/common.mk
  glob  $REPO/ASIC/*.mk
  glob  $DESIGN/*.mk
  glob  $REPO/ASIC/asic-flows/Cadence/*.tcl

# Timing constraints and power intent. Three of these .sdc files were being
# edited by another session while this spec was written.
group constraint min=5 copy
  note  inputs/: the SDC set, the UPF and the CPF.
  glob  $DESIGN/inputs/**

# The top wrapper and the constraint file config.tcl actually points at -- taken
# from config.tcl rather than assumed, because config.tcl is what Genus reads.
group design_entry min=2 copy
  tcl-var  top_level_hdl
  tcl-var  constraints_file

# THE RTL. Resolved from the flist with read_flist.tcl's exact semantics.
# Hashed file by file, because on this project a git SHA does not identify the
# RTL: the tree is always dirty, a large part of the flist is generated and
# re-rendered on every run, and submodule worktrees move independently of the
# pins recorded in the superproject index.
group rtl min=400 copy
  note  Every source file the ASIC flist resolves to. The group tree hash is
  note  the RTL fingerprint flow_compare.py's Rule 3 asks for.
  flist make:ASIC_FLIST

# LEFs and macro GDS, from the flow's own lists. EXTERNAL collateral is hashed
# and never copied -- see the engine's copy_group().
group macro_collateral min=15
  note  lef_file_list and gds_merge_list, verbatim from config.tcl.
  tcl-var  lef_file_list
  tcl-var  gds_merge_list

# The timing libraries. config.tcl declares them as a directory list crossed
# with a file-name list; every timing number the run reports comes from these.
group liberty min=8
  tcl-var-join  lib_search_path_list  syn_lib_list

# The mask-programmed boot ROMs. HASHED, NOT COPIED -- deliberately.
# These are compiled memory views. The repository is public and under IP
# remediation, and whether a byte copy of a compiled memory may live in a run
# archive is a site IP decision, not one for a provenance tool to take
# unilaterally. The consequence is stated honestly in UNRECOVERABLE.txt: they
# are gitignored, they cannot be rebuilt on this host (no working Arm memory
# compiler), so if the tree's copies are lost the run is not reproducible.
# Add `copy` to this line if the site decides otherwise.
group rom_lib min=60
  glob  $REPO/ASIC/romlibs/**

# The ROM specs and the RTL wrappers around the ROM macros. Both spec files
# changed mid-run on 2026-08-13.
group rom_spec min=1 copy
  glob  $TECHW/*rom*.spec

# Build products that are inputs to a later stage: the patched IO-driver LEF and
# the generator that makes it. The LEF is a transform of vendor bytes, so it is
# hashed and not copied for the same reason as the ROM libraries.
group generated_input min=2
  make-var  PAD_LEF
  make-var  PAD_LEF_GEN

# The derived stream-out map. Cannot exist before the flow has run, so it is
# only required at the phases where it does. Getting this wrong is how a whole
# class of DRC and antenna results was misattributed: a stock map streams LEF
# OBS onto real metal layers.
group streamout_map min=1 phases=post,route,stream
  make-var  GDSMAP
  make-var  GDSMAP_GEN
