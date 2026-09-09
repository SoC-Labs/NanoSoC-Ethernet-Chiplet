# ci/fixtures/dft-scan — fixtures for the clock-gate test-enable census

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.  Copyright 2026, SoC Labs (www.soclabs.org)

These fixtures belong to two proposed `ci/signoff.yaml` stages,
`dft-icg-selftest` and `dft-icg-census`. Both stanzas are in
[`PROPOSED_STANZA.yaml`](PROPOSED_STANZA.yaml) in this directory — read its
header first; it explains why the stanzas are delivered as a patch rather than
committed straight into the manifest, and where they splice in.

---

## What is being wired in, and what it measures

`scripts/ci/dft_icg_census.py` has existed in this repository since 2026-08-31.
It is complete, executable, self-tested, and **before this it was referenced by
no Makefile, no `.mk` and no CI stage**: `grep -rn dft_icg_census` outside the
script itself returned nothing.

What it finds, on every netlist it has been pointed at:

| netlist                                     | clock gates | test-enable        |
|---------------------------------------------|-------------|--------------------|
| rc5vt-20260829  `_gate.v` (post-synthesis)   | 3007        | 3007 `tied_low`    |
| rc5vt-20260829  `_pnr.v`  (post-route)       | 3007        | 3007 `no_test_pin` |
| rc6full-20260831 `_gate.v`                   | 3007        | 3007 `tied_low`    |
| rc6full-20260831 `_pnr.v`                    | 3007        | 3007 `no_test_pin` |
| vt1-20260902 `_gate.v`                       | 3007        | 3007 `tied_low`    |
| vt2ctl-20260908 `_pnr.v`                     | 3007        | 3007 `no_test_pin` |
| rc7gskew1-20260901 `_pnr.v`                  | 3007        | 3007 `no_test_pin` |

Every Genus-inserted integrated clock gate in this design has its test-enable
held low. **That is correct.** There is no scan chain, so there is nothing to
shift, and a clock gate whose test pin is tied off is the netlist you should
get. This is a census, not a violation, and the stage is gated `report`
accordingly.

It is worth a stage because nothing else in this flow can see the day that stops
being true. Genus does not warn — tying a clock-gate test pin low is a legal
netlist. Innovus does not warn. `report_scan_chains` reports the chains it was
asked to build, not the chains that can shift. Tempus grades the same netlist as
`6014 checks, 3007 Met, 0 Violated, 3007 Untested` — 6014 is 2 × 3007, the E pin
checked and the TE pin not — and calls the half it did not check *Untested*,
which reddens nothing.

---

## The three ways a naive check gets this wrong

Every one of these was measured on the real artefacts in this repository, and
every one has a fixture.

**1. The post-route disguise.** Innovus drops the `.test()` connection once the
constant has propagated, and physicalises the tie-off as a `TIEL` cell inside
the wrapper module. The routed netlist therefore contains **zero** occurrences of
`1'b0` on a clock gate:

```
$ grep -c ".test(1'b0)" ASIC/eth-chiplet/build/rc5vt-20260829/outputs/nanosoc_eth_chiplet_pads_pnr.v
0
```

A `grep`-based gate reads a 51 MB netlist whose every clock gate is held off as
clean. The census reads the same file as `3007 no_test_pin`.

**2. The line wrap.** Even on the *post-synthesis* netlist, where the tie-off is
written out in full, a line-oriented grep undercounts it by 31 %: 926 of the
3007 instances are wrapped so that `.test` and `(1'b0)` land on different lines.
`grep -c ".test (1'b0)"` returns 2081, not 3007. The census flattens whitespace
before matching, which is why it returns 3007.

**3. The source echo.** Genus reprints its own Tcl into the transcript. A run
with `DFT=0` produces a `logs/syn.log` containing, verbatim:

```
@file(1_synthesis.tcl) 987: if {$DFT} {
    step "scan chains"
    convert_to_scan
    connect_scan_chains
    try_step "scan chains rep" { report_scan_chains > $REPORT_DIR/syn_scan_chains.rep }
}
```

None of it ran. There is no `==== SYN: scan chains ====` step banner anywhere in
that log. **Any gate that greps a synthesis log for scan commands is vacuous by
construction** — it would report scan insertion on a run that had none. The only
trustworthy discriminator is the line the flow actually executed:

```
SYN: mmmc=0 ispatial=0 unc_fix=0 dft=0
```

which is anchored, unambiguous, and is what the `check:` reads.

---

## The fixtures

Fixture trees are overlaid onto a symlinked mirror of the repository by
`signoff.py prove`, so a fixture can only ADD files. A path ending `.__absent__`
is the directive that removes one. All netlist and log fixtures below are cut
from real artefacts — the rc5vt-20260829 netlists and the vt1-20260902 Genus
transcript — with the mutation named in each file's own header.

The netlist extracts are 290 clock gates rather than 3007 for one reason: the
census refuses a netlist under 100 kB as too small to be a real one, which is
its guard against grading a truncated synthesis. 290 verbatim gates is the
smallest extract that clears that floor.

### `dft-icg-census` — one must_pass, five must_fail

| fixture | what it is | what it would catch |
|---|---|---|
| `pass` | The shipping shape. `dft=0`; 290 gates `tied_low` in `_gate.v` and the same 290 `no_test_pin` in `_pnr.v`; a syn.log carrying **five** echoed-but-unexecuted scan commands. | The positive control, and simultaneously the log-echo trap: a check that grepped the log for `convert_to_scan` would call this a scan design and go red on a correct netlist. |
| `fail-scan-on-no-test-pin` | `dft=1`, and only the routed netlist — 290 gates, `.test()` gone. `grep -c "1'b0"` on it returns **0**. | **The post-route disguise.** This is the fixture the whole design of the stage turns on: the defect is present, the file contains no `1'b0`, and the gate must still go red. |
| `fail-scan-on-tied-low` | `dft=1`, post-synthesis netlist, 290 × `.test (1'b0)`. | The same defect in its other clothes. Proves the ratchet fires on the form Genus writes, not only the form Innovus writes. |
| `fail-no-banner` | Healthy netlist, and a syn.log with the executed `SYN: ... dft=` banner deleted — while all three echoed scan commands survive. | That an **unknown** DFT mode is UNVERIFIED and not silently "no scan". This is the negative half of trap 3: it proves the check is not falling back on the echo. |
| `fail-vacuous-netlist` | 103 kB of real ordinary cells with every clock gate removed. Parses, greps, looks like a netlist. | **Vacuity.** "0 clock gates tied low" is true of this file and measures nothing. A gate that calls it a pass has reported a green verdict over an empty census, which is this project's documented characteristic failure. |
| `fail-netlists-disagree` | 290 gates post-synthesis, 200 post-route, nothing else changed. | The detector going blind on one of the two netlist forms. The bucket is allowed to change between synthesis and route; the count is not, and it has been measured equal on five netlists across four runs. |

### `dft-icg-selftest` — one must_pass, four must_fail

See [`pass-selftest/README.md`](pass-selftest/README.md) for the table. In
short: the must_pass fixture supplies no file, so the real detector runs, and
each `fail-selftest-*` shadows `scripts/ci/dft_icg_census.py` with a stub
printing the real transcript with one mutation.

Each of the four is cut to trip the **first** clause of the check it reaches:
`exit0-liar` → clause 1 (status/text agreement), `shrunk` → clause 2 (case
count), `no-red` → clause 2's second half (negative-control count), `hollow` →
clause 3 (the transcript must show the work). A genuinely shrunk battery would
also trip clause 3; that is defence in depth, and clause 2 is the one that names
the cause.

---

## Evidence that the wiring can fail

Run against a copy of `ci/signoff.yaml` with both stanzas spliced in
(2026-09-09):

```
scripts/ci/signoff.py lint                              -> lint clean
scripts/ci/signoff.py prove dft-icg-selftest dft-icg-census
                                                        -> 11 case(s), 0 problem(s)
```

Eleven cases: 2 must_pass and 9 must_fail. Every must_fail case was confirmed to
be rejected *by the clause it was cut for*, not incidentally, by reading each
case's log under `build/signoff/prove/`.

---

## The ratchet

`dft-icg-census` is `gate: report` today because with no scan chain the tied-off
state is correct and blocking on it would block a design that is right.

**Promote it to `gate: block` when, and only when, the graded build's
`logs/syn.log` carries the executed banner `SYN: ... dft=1`** — that is, when
`ASIC/eth-chiplet/design.mk` sets `DFT=1` and `DFT_SETUP_TCL` names a real
scan-setup file. That is a one-word edit to the manifest and nothing else: the
`check:` already switches itself to `--require-scan` off the banner, and
`fail-scan-on-tied-low` and `fail-scan-on-no-test-pin` already prove it goes red
in that mode in both netlist forms.

Two follow-ons, deliberately not armed now and recorded so they are not
discovered at the ratchet instead:

* **`--shift-enable`.** The detector supports it; there is no port name to give
  it until a scan-setup file declares one. A name invented today would be a
  literal that is right for one die and quietly wrong for the next.
* **The wrapper-internal blind spot.** The census reads the test pin at the
  wrapper *instance*. Post-route, Innovus also physicalises the constant inside
  the wrapper as a `TIEL` cell driving the library cell's `TE`. A netlist could
  therefore connect `.test(scan_en)` at the wrapper and still hold `TE` low
  inside it, and the census would read `net` and call it healthy. Closing that
  is a change to `scripts/ci/dft_icg_census.py`, and belongs in the same commit
  as `--shift-enable`.
