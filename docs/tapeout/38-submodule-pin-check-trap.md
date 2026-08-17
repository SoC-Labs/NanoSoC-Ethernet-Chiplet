# A submodule pin check that compares SHAs cannot see a dirty submodule

**Found 2026-08-17, pre-launch on `gate1`. It would have shipped a tapeout stream
containing a module that exists in no commit anywhere.**

---

## 1. The check that passes while being wrong

The obvious pin check reads the gitlink recorded in the superproject commit,
reads the submodule's checked-out HEAD, and compares them:

```
  ASIC/asic-toolkit    HEAD=3910c18  want=3910c18   MATCH
  ASIC/asic-flows      HEAD=c2a46ee  want=c2a46ee   MATCH
  tidelink             HEAD=9e4a401  want=e21e274   DIFFERS
```

That found one problem. It is blind to two worse ones, and if the third line had
also read `MATCH` — which is the normal case — the check would have reported all
clear while the build compiled something else entirely.

**A SHA comparison cannot see:**

1. **The submodule's own working tree.** A submodule can sit exactly on its pin
   and still have uncommitted edits, deleted files, and untracked files that the
   build reads.
2. **The superproject's `dirty` verdict is computed one level up.** `git status
   --porcelain` in the superproject was **clean for every path the run reads**.
   The manifest would have recorded `dirty no` truthfully by its own definition
   and falsely in fact.

## 2. What was actually in there

```
M  src/rtl/tidelink_top.sv                <- the ASIC top RTL, 14 code lines
M  flists/tidelink_top_full_asic.flist    <- the file list itself
D  deps/xhb500/generated
?? src/rtl/tidelink_link_clk_div.sv       <- IN ZERO COMMITS, ANYWHERE
```

The flist edit adds exactly one entry — 182 entries at the pin, 182 at the
checked-out commit, **183 in the working tree** — and that entry is the untracked
file. `git log --all -- src/rtl/tidelink_link_clk_div.sv` returns nothing.

So the design under build contained a module present in no commit in any repo.
Not hard to rebuild: **impossible to rebuild**, by anyone, at any SHA, on any
machine.

It was not a leaf module either. The uncommitted `tidelink_top.sv` hunk adds a
new top-level input port and re-routes the D2D PHY high-speed clock through it:

```verilog
+  input wire [2:0] link_clk_div_ratio_i        // new chip-level port
+  tidelink_link_clk_div u_link_clk_div (.clk_in(user_ref_clk), ...)
-      .user_hsclk (user_ref_clk)
+      .user_hsclk (link_hsclk_w)
```

A new top-level port is a chip interface change, and this one sits in the clock
path that the transmit-clock constraints (`D2D_TX_CLK_0`, the eight
`D2D_TX_WORD_CLK_n`) describe as generated directly from `user_ref_clk`. The SDC
and the netlist would have disagreed about the clock topology, and the resulting
`master_clk_edge_not_reaching` would have been read as a constraints bug.

## 3. The one tell

`git submodule status` prefixes a dirty submodule with `+`:

```
   c2a46eec... ASIC/asic-flows  (heads/lpddr4-pll)
   3910c18f... ASIC/asic-toolkit (heads/main)
  +9e4a401c... tidelink          (archive/2026-08-collapse/...)
  ^
  this character is the entire warning
```

One character, in column 1, easy to lose in a wrapped terminal. Note also that
`+` here means *the checked-out commit differs from the recorded gitlink* — the
dirty **working tree** is reported separately and only with `--recursive` or by
running `git status` **inside** the submodule. Do both.

## 4. What to run instead

```bash
git submodule status --recursive          # read column 1: + or U is a stop
for m in $(git config -f .gitmodules --get-regexp path | awk '{print $2}'); do
    n=$(git -C "$m" status --porcelain | wc -l)
    [ "$n" -eq 0 ] || { echo "DIRTY SUBMODULE: $m ($n entries)"; git -C "$m" status --porcelain; }
done
```

And the check that would have caught this one regardless of git state — **ask the
flist, not the repo**: every file the build compiles must resolve to a commit.

**Get this one right or it is worse than useless.** Written the obvious way — run
from the repo root — it reported **137 of 182 entries untracked** on the first
flist it was pointed at, and every one was a false positive: nested submodules
(`deps/axi-chiplet-controller`, `deps/tidelink-phy`) keep their files in their own
indexes, so the parent correctly does not track them. A second, "submodule-aware"
attempt silently failed to populate its lookup table and reproduced the same 137
under a different label. A check that cries wolf gets switched off, which leaves
you worse off than having no check.

The version that works is shorter than either. Ask git from the **file's own
directory** and let it resolve the innermost repo itself:

```bash
d=$(dirname "$p"); b=$(basename "$p")
git -C "$d" ls-files --error-unmatch "$b" >/dev/null 2>&1 \
    || echo "NOT RESOLVABLE TO A COMMIT: $p"
```

On the same flist that gives 150 resolvable and 32 not — and the 32 are one real
finding rather than a flood.

### What the real 32 turned out to be

All under `deps/xhb500/generated`, and the tracked entry is not a file at all:

```
120000  deps/xhb500/generated -> /home/dam1n19/SoCLabs/tidelink/deps/xhb500/generated
```

**A committed symlink holding an absolute path into a personal home directory**,
pointing at a *different checkout* of the same project. The worktree has a
materialised directory there instead, so the build works on this machine and git
reports the symlink as deleted.

Check for the legitimate version of this before raising it: vendor IP that must
*not* be committed is often referenced rather than vendored, and that is correct.
The tell is where the link points — the read-only lab-shared IP tree named in
`CLAUDE.md` is by design; someone's `$HOME` is not.

The compiled bits are identical today, and that is the trap rather than the
reassurance:

```
  submodule HEAD    d7fe5d5
  standalone HEAD   3d4748fc      <- a DIFFERENT commit
  diff -rq          identical apart from one stray nested directory
```

Two checkouts of the same project on different commits, one of them referenced
from the other's build, and nothing keeping them in step. It agrees by luck, and
will stop agreeing silently. Committing the files is not the fix (Arm IP); the fix
is to resolve the path at build time from the shared IP location the rest of the
flow already uses.

### The check that had this document's own bug

Worth stating plainly rather than hiding as an admission: **the check written to
catch "a correct command answering a different question" was itself a correct
command answering a different question.** `git ls-files --error-unmatch` faithfully
answered "does the parent repo track this path" when the question was "does *any*
repo track this path". It was right, and useless, and looked like 137 findings.

If it can happen to the check, in the document about it, minutes after writing the
document — assume it is happening in whatever you are measuring right now. The
defence is not care. It is a control: run the probe against a case you *know* is
positive, and if it does not light up, the instrument is wrong rather than the
subject clean.

An untracked file in a flist is unreproducible whatever the SHAs say. That is the
strongest form of the check and it does not care how many levels of submodule sit
between the manifest and the source.

### 4a. But first: find the flist the build actually reads

The analysis above was done against `tidelink/flists/tidelink_top_full_asic.flist`
— which **this chiplet does not read**. The real chain is:

```
  chiplet ASIC flist   ->  build/chip/flist/tidelink_asic.flist     (GENERATED)
  generated by         ->  flist/resolve_tidelink_flist.py
  whose input is       ->  tidelink/flists/tidelink_top_full_asic_V2.flist
                                                              ^^ V2 is the ship config
```

Three ways to get this wrong, all of which happened while this was being chased:

- **Reading the obviously-named file.** `tidelink_asic.flist` is generated;
  editing or auditing it proves nothing.
- **Reading V1 when V2 ships.** The two are similar enough to look right.
- **Trusting the generated file's mtime.** The on-disk copy was three days stale
  and carried zero `clk_div` entries while the RTL instantiated the divider twice
  — which reads exactly like an unresolved module in the D2D clock path. It is a
  false alarm: `syn: asic-flist` is a real prerequisite (`design.mk:747`), so the
  generated flist is rebuilt every synthesis and the stale copy is never used.

**Why the stale-copy alarm keeps coming back, and why it is not a one-off.** The
bullet above is right that synthesis never uses the stale copy — but that is only
half the picture, and the missing half is what makes this reproducible:

| Consumer | Reads the generated flist | Re-renders it first |
|---|---|---|
| `make syn` | yes | **yes** — `asic-flist` is a real prerequisite (`design.mk:747`) |
| `make lint` | yes | **no** — it reads whatever is on disk |

So lint and synthesis can disagree about the design's contents indefinitely, and
lint is the one that is wrong. A stale render therefore produces findings that
are internally consistent, reproducible on demand, and entirely phantom — the
worked example being an "unresolved module in the D2D clock path" plus HAL
`E,UNCONI` on `user_hsclk` and `UASWIR` on `link_hsclk_w`, i.e. *"the D2D PHY
reference clock has no driver"*. All three vanish against a fresh render. Nothing
was wrong with the design.

Before reporting anything from a flist-derived check, **re-render first** and say
in the report which render you measured. A lint finding against a stale flist is
not weak evidence, it is evidence about a file that does not exist.

So: resolve the generated flist from its generator before auditing it, and
confirm which config (V1/V2) the flow selects. Auditing the wrong flist produces
confident conclusions about a file nothing compiles.

## 5. Also present, and a separate decision

The checked-out commit was 10 commits ahead of the pin and contained it, so the
N1 read-backstop fix was present. But those commits also carried behavioural RTL
changes in files that are in the ASIC flist:

| file | raw insertions | code-only (comments stripped) |
|---|---|---|
| `WlinkGenericFCSM.v` | 46 | 17 |
| `axi_chiplet_controller.sv` | 68 | 25 |
| `WlinkGenericFCSM_{1,2,3,4}.v` | 21 each | — |

The FCSM change adds a watchdog force-clear to the flow-control state-7 exit,
behind a `TL033_LEGACY_WDOG` guard. Its originating commit describes itself as
*"safety-commit auto-anchor/TL-033 watchdog RTL edits (uncommitted,
unreviewed)"*.

Quote the code-only counts when arguing about behaviour and the raw counts when
arguing about review burden; they differ by roughly 2.5x here and mixing them
makes two people think they disagree when they do not.

## 5a. A freeze protects the run from edits — and freezes in the defects

Two more instances of the same disease appeared while `gate1` was being prepared.
Both are worth naming because neither looks like a measurement error at the time.

**The frozen snapshot.** A route stage died in `route_power_via_census` on a
`regexp` pattern beginning with a hyphen and no `--` guard. It presents perfectly
as a live toolkit bug, and the obvious response is to fix the toolkit. But:

```
  pinned toolkit 3910c18, line 371   regexp -- {-layer_range...}   HAS the guard
  toolkit worktree                   clean, 0 diff lines
  the scratchpad snapshot it ran     regexp {-layer_range...}      LACKS it
```

The run had been frozen against a snapshot to insulate it from another session
editing a stage script mid-execution. That freeze worked — and it captured the
defect as it stood before the upstream fix. **A freeze protects a run from
changes, including the ones that fix things.** Someone acting on the failure would
have "fixed" a file that was already correct, then wondered why the next run
behaved identically.

Before treating a stage failure as a live defect, check *which copy* of the script
actually executed. The log names its own path; read it.

**The config-layer inversion.** A toolkit ships `opt PLACE_ERROR_ALLOWLIST {}` and
the obvious inference is that the effective allowlist is empty — so a placement
raising 211 `IMPLF-223` will be rejected. Wrong: `design.mk` already overrode it
with the needed IDs, and the empty toolkit default is *correct*, because the
project is supposed to override it. The contract was working exactly as designed.

Reading a default and inferring the effective value is the same error as reading
the index and inferring the commit — a real measurement, at the wrong layer.
**Resolve the value the flow actually exports, not the one its lowest layer
declares.**

## 6. The general shape

This is the same failure that has recurred all week in different clothing: **a
correct command answering a different question than the one being asked.**

- `git ls-remote` lists ref *tips*, so a reachable ancestor SHA reads as absent
- `grep | head -2` stops before the answer and reads as "not present"
- `git status` letters cannot distinguish staged work from a stale index entry
- **a submodule SHA comparison cannot see the submodule's working tree**
- a stage failure in a *frozen* script is not evidence about the live one
- a shipped default is not the effective value when a layer above overrides it
- a violation-class grep anchored on the net pair (`Net VDD & ... Net VSS`)
  instead of on `^SHORT` counts M4 spacing records as power-to-ground shorts —
  it returns 3 on a build that has none

In each case the instrument was fine and the inference from it was not. When a
check reports clean, the question to ask is not "do I believe it" but **"what
would this command do if the thing I fear were true?"** If the answer is "look
exactly like this", the check has told you nothing.

---

*Written 2026-08-17 after the finding held the `gate1` launch. The launch hold was
correct: the run would have produced a stream that passed its own `dirty no`
manifest and that nobody could ever rebuild.*
