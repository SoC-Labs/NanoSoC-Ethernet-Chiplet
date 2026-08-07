################################################################################
# flow_utils.tcl
#
# Tool-agnostic Tcl helpers shared by the Genus and Innovus stage scripts.
# Sourced by config.tcl, which every stage sources, so these are always
# available and never need sourcing again.
#
# Nothing here calls a Genus- or Innovus-specific command. Anything that does
# belongs in the stage script that needs it - e.g. cost_group wraps Genus's
# define_cost_group, which has no Innovus equivalent, so it stays in
# 1b_synthesis_eval.tcl.
#
# READ THIS BEFORE USING try_step
# ------------------------------
# try_step catches the error and carries on. That is right for OPTIONAL work -
# reports, audits, tuning - and wrong for anything the run's result depends on.
# Both Genus and Innovus exit 0 after a failed script (docs/tapeout/
# 17-silent-noops.md), so a try_step wrapped round a core step turns a real
# failure into a passing run with a missing artefact, which is the single
# failure mode this flow keeps being bitten by. Leave the core flow unwrapped
# and let it stop.
#
# Per-script configuration:
#     flow_config prefix EVAL    ;# tags messages "EVAL: ...", "EVAL-FAIL: ..."
#     flow_config strict 1       ;# make `flow_fail` fatal rather than advisory
#
# Contributors
#
# Daniel Newbrook (d.newbrook@soton.ac.uk)
# David Mapstone (d.a.mapstone@soton.ac.uk)
#
# Copyright (C) 2026, SoC Labs (www.soclabs.org)
################################################################################

# Idempotent: config.tcl can be re-sourced (interactively, or by a helper
# script) without tripping the collision check below.
if {[info exists ::flow_utils_loaded]} { return }
set ::flow_utils_loaded 1

# `proc` silently REPLACES an existing command of the same name. These names are
# short and generic, and this file is now sourced into every Genus and Innovus
# run, so assert they are free rather than discover a shadowed built-in three
# hours into a P&R stage. None of them collides in Genus 21.1x / Innovus 21.11;
# this is the guard for the next tool version, not for today.
foreach c {flow_config say warn step die flow_fail try_step opt reports fresh_report mf} {
    if {[llength [info commands $c]]} {
        error "flow_utils.tcl: '$c' is already a command in this tool - it would be\
               shadowed. Rename the helper (and its callers) before sourcing."
    }
}

# prefix : tag on every message emitted from this file
# strict : `flow_fail` is fatal when true, advisory when false
# knobs  : names registered by `opt`, in declaration order, for the manifest
array set ::flow {
    prefix FLOW
    strict 0
    knobs  {}
}

# Reject undeclared keys rather than quietly creating them: a typo'd
# `flow_config stict 1` that silently did nothing is exactly the class of
# silent no-op this flow exists to stamp out.
proc flow_config {key value} {
    if {![info exists ::flow($key)]} {
        error "flow_config: unknown key '$key' (have: [lsort [array names ::flow]])"
    }
    set ::flow($key) $value
}


# --- Messages ----------------------------------------------------------------

proc say  {args} { puts "$::flow(prefix): [join $args { }]" }
proc warn {args} { puts "$::flow(prefix)-WARN: [join $args { }]" }
proc step {text} { puts "\n==== $::flow(prefix): $text ====" }

# die is always fatal; flow_fail is fatal only under `flow_config strict 1`.
#
# NAMED flow_fail, NOT fail. `fail` IS A BUILT-IN COMMAND IN INNOVUS 21.11 — the
# collision guard above caught it and aborted 4_pnr_route.tcl outright on
# 2026-08-07, 2.5 hours into a run, because config.tcl sources this file into
# BOTH tools. The guard did its job; the name was simply wrong. Do not rename it
# back, and be wary of any other short generic name added to that list.
proc die {args} {
    foreach line $args { puts "$::flow(prefix)-FAIL: $line" }
    exit 1
}
proc flow_fail {args} {
    puts "$::flow(prefix)-FAIL: [join $args { }]"
    if {$::flow(strict)} { die "strict mode set - stopping." }
}


# --- Optional steps ----------------------------------------------------------

# OPTIONAL work only - see the warning at the top of this file.
proc try_step {label body} {
    if {[catch {uplevel 1 $body} msg]} { warn "'$label' skipped: $msg" ; return 0 }
    return 1
}


# --- Environment-overridable knobs -------------------------------------------

# `opt NAME default` sets global $NAME from $env(NAME) or the default, and
# records NAME in ::flow(knobs) so a run manifest cannot drift out of step with
# the configuration - a hand-maintained list had already silently dropped three
# effort knobs, which change QoR.
proc opt {name default} {
    global $name
    lappend ::flow(knobs) $name
    if {[info exists ::env($name)]} {
        set $name $::env($name)
    } else {
        set $name $default
    }
}


# --- Reports -----------------------------------------------------------------
# Both read REPORT_DIR, which config.tcl sets for every stage.

# {file cmd file cmd ...} -> run each cmd into $REPORT_DIR/<file>. Advisory: a
# report that will not run should never kill the flow.
proc reports {pairs} {
    global REPORT_DIR
    foreach {f cmd} $pairs { try_step $f "$cmd > $REPORT_DIR/$f" }
}

# Create/truncate a report and return its path, for the reports that have to be
# built by appending - a command that must be called once per type and have its
# output concatenated.
proc fresh_report {name} {
    global REPORT_DIR
    close [open $REPORT_DIR/$name w]
    return $REPORT_DIR/$name
}

# One key/value line of a manifest.
proc mf {fh k v} { puts $fh [format "%-22s %s" $k $v] }
