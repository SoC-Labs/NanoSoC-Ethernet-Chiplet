# Stage-test scenarios for the survival gate

`ASIC/asic-toolkit/test/stage/run.sh` runs the four stage scripts in a bare
`tclsh` with every EDA command stubbed — no PDK, no licence, ~6 s. It is the
right home for these, because it is the only harness in this project that
executes `1_synthesis.tcl` rather than merely parsing it.

**Nothing below is installed.** The toolkit submodule is dirty with several
sessions' work; these are the files and hunks a reviewer would apply.

---

## 1. New file — `test/stage/project/survival.tcl`

The reference project's manifest. It declares logic the stub design "has", so
the gate has something to be right and wrong about.

```tcl
# The stage-test project's survival manifest. Deliberately tiny, and
# deliberately NOT derived from anything: the derivation belongs to a real
# project (see docs/bscan/survival_manifest.eth-chiplet.tcl), and what this
# harness tests is the ENGINE's behaviour around a claim, not a JSON parser.
#
# `-min 8` is sourced to this comment, which is honest for a synthetic design
# and is exactly what -source is for: the number has a stated origin that a
# reader can check.
survive "stub declared flops" \
    -pattern "*u_bsc_*_reg" \
    -min     8 \
    -source  "test/stage/project/survival.tcl: the stub design has 8 by\
              construction (stubs/eda_stubs.tcl, ::scn(survive_pool))" \
    -baseline
```

## 2. New scenario — `test/stage/scenarios/survive_deleted.tcl`

```tcl
# syn_opt deleted 4 of the 8 instances the manifest declared.
#
# THIS IS THE BOUNDARY-SCAN DEFECT, and the pad defect before it. The command
# does not fail: syn_opt returns cleanly, prints nothing about the deletion,
# and every downstream number gets QUIETER rather than louder - less logic
# means less area, fewer endpoints, better timing. Section 16's verdict is
# built from Genus message IDs, and a correct optimisation produces none.
stub_scn survive_deleted 4
```

## 3. New scenario — `test/stage/scenarios/survive_all_deleted.tcl`

```tcl
# The whole declared population is gone before optimisation ever runs - the
# shape a case-analysed enable pin produces, where the deletion happens in
# syn_generic and no post-mapping baseline could ever have counted it.
#
# The BASELINE arm must fail here, not the floor arm, and it must not read as
# "0 required, 0 found, pass".
stub_scn survive_pool 0
```

## 4. Stub patch — `test/stage/stubs/eda_stubs.tcl`

Add to the documented scenario block (beside `iofile_missing`, which models the
same defect one stage later):

```tcl
# --- declared-logic survival --------------------------------------------------
# survive_pool     how many instances matching the manifest's pattern exist
#                  after technology mapping. 0 models logic deleted during
#                  syn_generic, i.e. before any baseline could see it.
# survive_deleted  how many of those syn_opt removes. The command succeeds and
#                  says nothing, which is the entire defect: on the reference
#                  design this was 34 supply pads, and later 4 boundary-scan
#                  update stages behind a run that reported "Status : OK".
```

and to the `array set ::scn { ... }` block:

```tcl
    survive_pool         8
    survive_deleted      0
```

then the mutable population, and the one command that shrinks it:

```tcl
# The declared population, as a MUTABLE list. It has to be mutable because the
# defect is a change ACROSS syn_opt: a stub that answered the same count at the
# baseline and at the gate could not express the failure at all.
set ::stub_survive_n -1
proc stub_survive_names {} {
    if {$::stub_survive_n < 0} { set ::stub_survive_n $::scn(survive_pool) }
    set out {}
    for {set i 0} {$i < $::stub_survive_n} {incr i} {
        lappend out [format "u_dut_u_bsc_%02d_q_reg" $i]
    }
    return $out
}

# REPLACES the `foreach c {syn_generic syn_map syn_opt} { stub_cmd $c }` line
# for syn_opt only; syn_generic and syn_map keep their plain stubs.
proc syn_opt {args} {
    stub_record syn_opt $args
    if {$::stub_survive_n < 0} { set ::stub_survive_n $::scn(survive_pool) }
    set ::stub_survive_n [expr {$::stub_survive_n - $::scn(survive_deleted)}]
    if {$::stub_survive_n < 0} { set ::stub_survive_n 0 }
    return ""
}
```

and `get_db` / `get_cells` answer name-pattern queries from it:

```tcl
# In proc get_db, before the existing body's return:
if {[lindex $args 0] eq "insts"} {
    set pat ""
    if {[regexp {\.name\s*==\s*([^\s\}]+)} [join $args " "] -> pat]} {
        set out {}
        foreach n [stub_survive_names] { if {[string match $pat $n]} { lappend out $n } }
        return $out
    }
}
```

```tcl
# In proc get_cells: the dont_touch pass asserts a non-empty match and must keep
# getting one, so only name-filtered queries are answered from the pool.
proc get_cells {args} {
    stub_record get_cells $args
    set pat ""
    if {[regexp {name\s*=~\s*\"?([^\"\}]+)} [join $args " "] -> pat]} {
        set out {}
        foreach n [stub_survive_names] { if {[string match $pat $n]} { lappend out $n } }
        if {[llength $out]} { return $out }
    }
    return [list cell:pad0 cell:pad1]
}
```

## 5. Interface — `test/stage/lib.sh`

`lib.sh` holds ONE definition of the `ASIC_*` interface, taken from `mk/flow.mk`.
Add beside `ASIC_BONDPADS_TCL`:

```sh
export ASIC_SURVIVAL_MANIFEST="${ASIC_SURVIVAL_MANIFEST-$PROJ/survival.tcl}"
```

The `${VAR-default}` form (no colon) matters: it lets a case export
`ASIC_SURVIVAL_MANIFEST=` to test the **not-applicable** path, which a `:-`
would silently overwrite with the default.

## 6. Cases — `test/stage/run.sh`

Beside the other `syn.gate.*` cases (around line 208):

```sh
# The survival gate. Section 13b exists because the same defect has now happened
# twice: 34 supply pads, then the boundary-scan update stages. Each fail_case is
# paired with a pass_case below - a gate proven only to fire is a gate that may
# fire on everything.
fail_case syn.survive.deleted        syn survive_deleted.tcl \
    "DECLARED LOGIC DID NOT SURVIVE SYNTHESIS."
fail_case syn.survive.never-existed  syn survive_all_deleted.tcl \
    "matched NO instances"
fail_case syn.survive.vacuous-floor  syn - \
    "satisfied by an EMPTY design" \
    "ASIC_SURVIVAL_MANIFEST=$HERE/project/fixtures/survival_zero_floor.tcl"
fail_case syn.survive.no-provenance  syn - \
    "A floor with no provenance is a literal" \
    "ASIC_SURVIVAL_MANIFEST=$HERE/project/fixtures/survival_no_source.tcl"
fail_case syn.survive.declared-missing syn - \
    "cannot read" \
    "ASIC_SURVIVAL_MANIFEST=$HERE/project/does-not-exist.tcl"
fail_case syn.survive.empty-manifest syn - \
    "registered ZERO claims" \
    "ASIC_SURVIVAL_MANIFEST=$HERE/project/fixtures/survival_empty.tcl"
```

and, in the pass section (around line 562):

```sh
pass_case syn.survive.armed          syn - \
    "the survival gate passes a design whose declared logic is intact"
pass_case syn.survive.not-applicable syn - \
    "a design that declares no survival manifest is not failed by the gate" \
    "ASIC_SURVIVAL_MANIFEST="
```

`syn.survive.armed` is the load-bearing one. Five reds and no green is how a
gate that fires on everything gets shipped looking rigorous.

## 7. Fixtures — `test/stage/project/fixtures/`

```tcl
# survival_zero_floor.tcl
# The floor derived to zero, because its source artefact was missing or its
# parse silently failed. `0 found >= 0 required` is TRUE, and a gate that
# reports it as a pass has measured nothing and said so in green.
survive "declared flops" -pattern "*u_bsc_*_reg" -min 0 -source "a table that did not parse"
```

```tcl
# survival_no_source.tcl
# A floor with no provenance. Right for one die, quietly wrong for the next.
survive "declared flops" -pattern "*u_bsc_*_reg" -min 8
```

```tcl
# survival_empty.tcl
# A manifest that parses and declares nothing. Not the same as having no
# manifest: that is spelled by leaving SURVIVAL_MANIFEST empty.
say "this manifest declares nothing at all"
```
