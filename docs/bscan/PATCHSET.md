# Patch set — the declared-logic survival gate, and the transitive input fingerprint

**Nothing in `ASIC/asic-toolkit` has been modified.** The submodule is a
dirty working tree carrying several sessions' work (`flow/innovus/4_route.tcl`,
`mk/drc.mk`, `mk/help.mk`, `flow/power/`, `test/power/` and more are
modified or untracked as of 2026-08-20), and a peer owns tonight's EDA
scheduling. Every hunk below is stated with enough surrounding context to be
placed by hand, against **toolkit HEAD as read on 2026-08-20**. Line numbers are
from that read and will move; the anchor text is the contract.

**Patch A** (gate 1, survival) and **Patch C** (gate 2, provenance closure) are
independent of each other and can land in either order. **Patch B** is optional,
comes last, and is discussed in `DELETION_GUARD_DESIGN.md` §2.7.

---

## Patch A — the general gate (five hunks, all additive)

### A0. New file: `flow/genus/survival.tcl`

Copy `docs/bscan/survival.tcl` verbatim.

It defines `survive`, `syn_survive_read_manifest`, `syn_survive_count`,
`syn_survive_missing_names`, `syn_survive_baseline` and
`syn_survive_assert`. It is inert until a project supplies a manifest.

Executed under `tclsh 8.6.8` with stubbed queries by
`docs/bscan/stage_test/t_survival.tcl` — **17 assertions, 0 failures**. It uses
no Tcl 8.6-only construct (no `lmap`, no `string cat`); `{*}` expansion is
8.5+ and is already used by `syn_hard` itself.

### A1. `mk/flow.mk` — declare the knob

Anchor (currently ~line 249), in the block introduced by
`# Optional. Empty means "this design does not have one", and the engine skips`
`# the section rather than failing.`:

```make
 BONDPADS_TCL      ?=
+# Optional, same contract as BONDPADS_TCL above. The Tcl file in which this
+# design declares the instances that MUST still exist after optimisation.
+# Empty = this design declares nothing, and the survival gate does not run.
+# Non-empty and unreadable = a hard input-contract failure, not a skip.
+SURVIVAL_MANIFEST ?=
 POWER_INTENT      ?=
```

### A2. `mk/flow.mk` — export it

Anchor (currently ~line 369):

```make
 export ASIC_BONDPADS_TCL   := $(BONDPADS_TCL)
+export ASIC_SURVIVAL_MANIFEST := $(SURVIVAL_MANIFEST)
 export ASIC_POWER_INTENT   := $(POWER_INTENT)
```

### A3. `mk/flow.mk` — show it in the config dump

Anchor (currently ~line 446):

```make
 	@printf '  %-22s %s\n' BONDPADS_TCL "$(if $(BONDPADS_TCL),$(BONDPADS_TCL),(none))"
+	@printf '  %-22s %s\n' SURVIVAL_MANIFEST "$(if $(SURVIVAL_MANIFEST),$(SURVIVAL_MANIFEST),(none))"
 	@printf '  %-22s %s\n' HOOKS_DIR "$(HOOKS_DIR)"
```

A knob absent from the dump is a knob nobody notices is unset — and "the
variable was empty so the gate silently did not run" is precisely the failure
mode this gate is built against.

### A4. `flow/genus/1_synthesis.tcl` — source it, and read the manifest

**Section 0, INPUT CONTRACT**, at its end. Anchor is the last check in the
section (currently ~line 215), immediately before the `# 1. TOOL SETUP` banner:

```tcl
 if {$SYN_ISPATIAL && !$SYN_MMMC} {
     die "SYN_ISPATIAL=1 requires SYN_MMMC=1 - read_physical needs the MMMC init" \
         "  sequence (TUI-340). Re-run with SYN_MMMC=1."
 }
+
+# --- what this design declares must survive optimisation ----------------------
+# Read HERE, in the input contract, for the reason the section states: a
+# malformed manifest, or one whose source artefact has gone, costs nothing to
+# find now and a licence-hour to find later. Registration touches no design
+# object, so it is safe this early.
+source $::env(ASIC_FLOW_DIR)/flow/genus/survival.tcl
+syn_survive_read_manifest
 
 
 ################################################################################
 # 1. TOOL SETUP
```

### A5. `flow/genus/1_synthesis.tcl` — take the baseline after mapping

**End of section 11, TECHNOLOGY MAPPING** (currently ~line 981), after the map
reports and snapshot, before the `# 12. SCAN CHAIN CONNECTION` banner:

```tcl
 if {$SYN_SNAPSHOTS} {
     try_step "snapshot map" { write_snapshot -tag map -directory $REPORT_DIR }
 }
+
+# --- headcount, before anything optimises ------------------------------------
+# MUST run after syn_map and before syn_opt. Before syn_generic the mapped
+# instances do not exist - the flops are still RTL - so there is nothing to
+# count. After syn_opt it is too late to know what was lost. This seam is
+# reachable ONLY from inside the engine: the project hook points are pre_synth
+# (before syn_generic) and post_synth (after syn_opt), which is why this gate
+# cannot live in a project hook.
+#
+# It runs BEFORE section 12's scan insertion. With DFT on, convert_to_scan
+# replaces flops with their scan equivalents and connect_scan_chains rewires
+# them; a claim that is scan-sensitive should therefore be written -min/-source
+# rather than -baseline. Said here because the alternative - baselining after
+# section 12 - would make the gate blind to anything scan insertion removed.
+syn_survive_baseline
 
 
 ################################################################################
 # 12. SCAN CHAIN CONNECTION - DFT only
```

### A6. `flow/genus/1_synthesis.tcl` — the gate, as section 13b

Immediately **after section 13a's closing brace** (currently ~line 1057) and
before the `# 14. REPORTS` banner. It therefore runs after
`flow_hook post_synth` (~line 1015) and after the pad-ring check, and well
before `write_hdl` (~line 1130).

```tcl
     } else {
         say "pad ring intact: all [llength $::SYN_IO_INSTS] IO-file instances\
              survived synthesis"
     }
 }
+
+
+################################################################################
+# 13b. DID THE LOGIC THIS DESIGN DECLARED SURVIVE SYNTHESIS?
+#
+# The general form of 13a. Section 13a asks the question for the pad ring,
+# because 34 supply pads were once deleted behind a completed run. The same
+# thing then happened to a boundary-scan register, for the same reason: logic a
+# tool was CORRECT to delete, that nobody had declared must survive, and that
+# nothing noticed had gone. 13a is one instance of that; this is the mechanism.
+#
+# HERE, and not later, for the reason 13a is here: this is the last point at
+# which the deletion is both real and still cheap. One stage further on is
+# write_hdl, and everything after that spends hours on a dead netlist.
+#
+# AFTER the post_synth hook on purpose, exactly as 13a is: a project hook may
+# legitimately restructure, and the question is what is there when it has
+# finished.
+################################################################################
+
+syn_survive_assert
 
 
 ################################################################################
 # 14. REPORTS
```

---

## Patch A' — the project side (eth chiplet)

### A'1. New file: `ASIC/eth-chiplet/survival.tcl`

Copy `docs/bscan/survival_manifest.eth-chiplet.tcl`. Its relative path to the
pad table (`[file dirname [info script]]/../../src/rtl/bscan/pad_table.json`)
resolves correctly from `ASIC/eth-chiplet/`.

Executed under `tclsh`, it derives **119**, **4** and **48** with no number
typed in the file.

### A'2. `ASIC/eth-chiplet/design.mk`

Beside `BONDPADS_TCL` (currently ~line 213):

```make
+SURVIVAL_MANIFEST ?= $(ASIC_DIR)/survival.tcl
```

### A'3. Stage tests

See `docs/bscan/stage_test/scenarios.md` — six `fail_case`s and two
`pass_case`s, plus the stub knob that makes the population shrink across
`syn_opt`.

---

## Patch B — reimplement §13a on the mechanism (LATER, separately)

```tcl
 if {[info exists ::SYN_IO_INSTS] && [llength $::SYN_IO_INSTS]} {
-    step "pad ring survives synthesis"
-    set gone [syn_missing_io_insts $::SYN_IO_INSTS]
-    if {[llength $gone]} {
-        syn_hard "[llength $gone] pad instance(s) DELETED by synthesis" \
-        ...
+    # 13a is now the FIRST CLAIM of the general mechanism rather than a
+    # sibling of it. The expectation still comes from the IO file, the
+    # diagnosis is still the pad-ring one, and there is now ONE place where
+    # "is this instance present" is decided.
+    survive "pad ring (instances named by [file tail $IO_FILE])" \
+        -names   $::SYN_IO_INSTS \
+        -source  "[file tail $IO_FILE]: [llength $::SYN_IO_INSTS] entries with no cell=" \
+        -baseline \
+        -advice  "They were present before synthesis, so this is optimisation,\
+                  not a naming mismatch. Supply pads have no ports and are read\
+                  as dead logic unless DONT_TOUCH_PATTERNS protects them by\
+                  name - see section 7. Downstream this costs read_io_file the\
+                  placements, the bond-pad ring one IMPFP-254 per pad, and the\
+                  supply pads their bond wires."
 }
```

registered at section 7 where `::SYN_IO_INSTS` is built, so the baseline and
the gate both pick it up automatically.

**Why this is a separate, later patch.** 13a is the only thing standing between
this flow and a defect that has already shipped three times. Rewriting it in the
same change that introduces the mechanism means that if the mechanism is wrong,
13a is wrong too, and the regression is invisible — 13a passes silently on a
healthy design either way. Land A, watch 13b fire and pass on a real run, then
land B. The cost of waiting is one duplicated check on the eth chiplet, whose
manifest claim 3 covers the pad table's 48 pads while 13a covers the IO file's
list; see the note in the manifest on why that overlap is worth having anyway.

---

## Patch C — the transitive input fingerprint (gate 2)

Independent of Patch A. Records; does not judge.

### C0. New file: `flow/common/prov_closure.tcl`

Copy `docs/bscan/prov_closure.tcl` verbatim. Loads in bare `tclsh`, calls no
Genus or Innovus command, and guards against double-loading the same way
`provenance.tcl` does.

Exercised against the real `ASIC/genus-innovus/inputs/constraints.sdc`: it finds
the parent and all five sub-SDCs, and produces a stable aggregate digest.

### C1. `flow/common/read_flist.tcl` — record which filelists were visited

`_flist_scan` (pass 1) already visits every flist in the chain exactly once.
It records the *sources* in `::flist_read` but not the *flists*. Anchor is the
top of `_flist_scan`, beside the existing globals (~line 100 and ~line 155):

```tcl
 set ::flist_read    {}    ;# every path handed to the tool, for -y de-duplication
+set ::flist_flists  {}    ;# every FILELIST visited, incl. those reached by -f.
+                          ;# prov_closure_flist hashes these: `-f` includes were
+                          ;# invisible to provenance, and build/chip/flist/*.flist
+                          ;# are regenerated before every synthesis run.
```

```tcl
 proc _flist_scan {flist} {
+    if {[lsearch -exact $::flist_flists $flist] < 0} {
+        lappend ::flist_flists $flist
+    }
```

and in `read_filelist`, beside the other resets:

```tcl
     set ::flist_read    {}
+    set ::flist_flists  {}
```

Two lines of behaviour change and no traversal reimplemented — a second
implementation of a walk is a second thing to be wrong, which is the reasoning
`provenance.tcl` already applies to ROM hashes.

### C2. `flow/genus/1_synthesis.tcl` — load it beside `read_flist.tcl`

Anchor (currently line 480):

```tcl
 source $FLOW_DIR/flow/common/read_flist.tcl
+source $FLOW_DIR/flow/common/prov_closure.tcl
```

### C3. `flow/genus/1_synthesis.tcl` — fingerprint the flist closure AT READ TIME

Immediately after the `read_filelist` call in **§6, READ THE RTL**.

```tcl
+# --- what the filelist actually pulled in ------------------------------------
+# AT READ TIME, not at section 16. build/chip/flist/{soc,tidelink_asic}.flist
+# are regenerated before every synthesis run, so by the time the manifest is
+# written the bytes that were read may no longer exist. flist.sha256 covers the
+# ENTRY POINT only; everything reached by `-f` was invisible.
+prov_collect_closure flist.closure [prov_closure_flist]
```

### C4. `flow/genus/1_synthesis.tcl` — fingerprint the SDC closure AT READ TIME

**§8, CONSTRAINTS**, immediately after the read loop (currently line 764):

```tcl
     foreach s $SDC_FILES { read_sdc $s }
+
+    # --- what those SDCs actually sourced -------------------------------------
+    # MEASURED, 2026-08-19 -> 2026-08-20: constraints.sdc was byte-identical
+    # across two runs (44270 B) while bscan_constraints.sdc, which it `source`s,
+    # went 5255 -> 6724 B and restructured the netlist hierarchy. The flow
+    # recorded no input change, and the investigation cost a day.
+    #
+    # AT READ TIME, because there is no snapshot to go back to: on this project
+    # build/<tag>/inputs is a SYMLINK to the live input tree, so an in-place
+    # edit leaves the earlier run's bytes unrecoverable.
+    #
+    # cwd is the work directory because that is where the tool is running and
+    # therefore how Tcl resolves a relative `source` - the scanner tries the
+    # sourcing file's directory as well, and records which one resolved.
+    prov_collect_closure sdc.closure \
+        [prov_closure_sdc $SDC_FILES [flow_env ASIC_WORK_DIR ""]]
```

### C5. `flow/genus/1_synthesis.tcl` — write the sidecar

Beside the existing `prov_write` (currently line 1292):

```tcl
             prov_write $REPORT_DIR/syn_provenance.txt
+            # The manifest carries one aggregate digest per closure; THIS is the
+            # file a human diffs to find out WHICH of five sub-SDCs moved.
+            prov_closure_write $REPORT_DIR/syn_inputs.sha256
```

### C6. The same two hooks in the Innovus stages (optional, later)

`2_place.tcl`, `3_cts.tcl` and `4_route.tcl` read the SDC through the MMMC, so
the equivalent call belongs after the mmmc is loaded. Left out of this patch
deliberately: the synthesis stage is where the constraint set determines the
netlist, and one stage proven beats four unproven.

### C7. Stage tests

`prov_closure.tcl` loads in bare `tclsh`, so `test/stage/run.sh` covers it for
free once C2 lands. Worth adding to the existing manifest probe near
`run.sh:594`:

```sh
# The closure fields must be PRESENT and non-UNVERIFIED on a healthy run: an
# aggregate that silently reports nothing is the failure this gate exists for.
grep -q '^sdc\.closure\.count '  "$ASIC_REPORT_DIR/syn_provenance.txt"
grep -q '^flist\.closure\.count ' "$ASIC_REPORT_DIR/syn_provenance.txt"
```
