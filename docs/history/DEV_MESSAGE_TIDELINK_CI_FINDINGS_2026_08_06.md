# TideLink findings from standing up chiplet CI — 2026-08-06

**From:** nanosoc-ethernet-chiplet integration
**Context:** bringing up a sandboxed GitHub Actions runner (srv04936) and climbing
the chiplet's gate ladder — bootstrap → chip-boundary → lint → elab → elab-strict.
Five findings are TideLink-side. None is a blocker for us any more; we have local
workarounds for all of them, and this is a report rather than a request.

**Chiplet pin at time of writing:** `tidelink 9dfe1da` (TideLink HEAD locally
`e28c898`). All evidence below reproduced at that pin.

---

## 1. `_generate_xhb500` reports success on a failed generation — Rank 1

**Where:** `set_env.sh`, `_generate_xhb500()`

This is the highest-value fix in this report, because it converts a clear,
immediate error into a confusing one that surfaces minutes later somewhere else.

```bash
python3 "${XHB500_GENERATOR}" \
    --config "${config_file}" \
    --output "${output_dir}" \
    2>&1 | sed 's/^/         /'

if [ $? -eq 0 ] && [ -d "${output_dir}/logical" ]; then
    echo "  [done] ${name} generated at ${output_dir}"
```

`$?` after a pipeline is the exit status of the **last** command in it — `sed`,
which essentially always succeeds. The generator's status is discarded. The
second condition doesn't save it either: the generator creates `logical/` before
it dies, so the directory exists and the guard passes.

There is no `set -o pipefail` anywhere in the file.

**Observed.** On a host missing the generator's perl dependency, our CI printed
*both* of these, in this order:

```
  [gen]  Generating xhb500_ahb_to_axi_bridge_chiplet_slv...
         Can't locate File/Slurp.pm in @INC (you may need to install the File::Slurp module)
         BEGIN failed--compilation aborted at .../generate_xhb500_bridge.pl line 45.
         %error	RTL_generation	Error encountered during RTL generation
  [done] xhb500_ahb_to_axi_bridge_chiplet_slv generated at .../xhb_chiplet_slv
```

`%error RTL_generation` immediately followed by `[done]`. The build then carried
on and failed ~1 minute later inside VCS with a symptom that names neither the
generator nor the missing perl module:

```
Error-[SFCOR] Source file cannot be opened
  ".../tidelink/deps/xhb500/generated/xhb_chiplet_slv/logical/models/cells/generic/xhb500_flop.sv"
  cannot be opened for reading due to 'No such file or directory'.
```

**Suggested fix:** either

```bash
if [ "${PIPESTATUS[0]}" -eq 0 ] && [ -d "${output_dir}/logical" ]; then
```

or `set -o pipefail` before the pipeline.

**The second-order bug is worse, and we hit it.** The partial `logical/` tree is
left behind on failure, and the early-out at the top of the function tests only
`[ -d "${output_dir}/logical" ]`. So a failed generation is indistinguishable
from a completed one on the next run.

We installed `perl-File-Slurp` to fix the failure above. **The very next CI run
failed identically** — it printed

```
  [skip] xhb500_ahb_to_axi_bridge_chiplet_slv already generated at .../xhb_chiplet_slv
```

skipped generation over the half-written output from the previous run, and never
used the newly-installed perl module at all. From the outside this looks exactly
like "the fix didn't work", which is an expensive thing to debug.

Suggested: `rm -rf "${output_dir}"` on the failure path, and/or make the early-out
test for a known-terminal artefact (e.g. `logical/models/cells/generic/xhb500_flop.sv`)
rather than the directory. We work around it by deleting the tree before every
elaboration.

**Related, undocumented host requirements.** `set_env.sh` invokes the Arm XHB500
generator as `python3 "${XHB500_GENERATOR}"`, i.e. against whatever `python3`
happens to be on PATH. That generator needs:

- the perl module **`File::Slurp`** (`perl-File-Slurp` on RHEL 8, in appstream);
- a python in the window **`>= 3.7, < 3.11`**. It calls `open(..., 'U')`, and
  universal-newline mode was **removed in 3.11**:

  ```
  ValueError: invalid mode: 'U'
  %error	IP-XACT_generation	Error encountered during IP-XACT file generation
  ```

  Verified: 3.6 and 3.8 fine, 3.11 and 3.12 both fail. Combined with the silent
  `[done]`, the result is a green-looking generation step and a mystifying VCS
  failure later.

Neither is mentioned in the README. Both bit us on a host that was otherwise
perfectly capable. Probing for them in `set_env.sh` — or simply documenting them
— would save the next integrator the whole trace above. We now check both in our
`scripts/ci/preflight.sh`, along with the `jinja2` that the SoC generator needs.

---

## 2. `tidelink_fpga.flist` (V1) no longer elaborates

**Where:** `flists/tidelink_fpga.flist` vs `flists/tidelink_fpga_v2.flist`

`src/rtl/local_overrides/Wlink.v` instantiates two observation modules:

| module | instantiated at | listed in |
|---|---|---|
| `tidelink_fcemit_obs` | `local_overrides/Wlink.v:1554` | **only** `tidelink_fpga_v2.flist` |
| `tidelink_winscan_obs` | `local_overrides/Wlink.v` | **only** `tidelink_fpga_v2.flist` |

`Wlink.v` is shared by both flists, so anyone resolving the V1 list gets:

```
Error-[CFCILFBI] Cannot find cell in liblist
  Cell 'tidelink_fcemit_obs' cannot be found in liblist for binding instance
  'nanosoc_eth_chiplet.u_tidelink.u_chiplet_controller.u_wlink.u_fcemit_obs'.
```

This is not caused by anything on our side — we confirmed it by stashing all of
our own RTL changes and reproducing identically.

**What we did:** pointed our `make elab` at `tidelink_fpga_v2.flist`. That was
arguably overdue regardless — our ASIC flow already resolves
`tidelink_top_full_asic_v2.flist`, so the structural gate had been elaborating a
PHY configuration the chip does not ship.

**Ask:** is V1 still supported? If yes, the two files want adding to
`tidelink_fpga.flist`. If it is superseded, retiring it (or a loud comment at the
top) would stop others walking into this.

---

## 3. Both PHY submodules point at the same repo, at commits 97 apart

**Where:** `.gitmodules`

```
submodule.deps/tidelink-gpio-phy.url  git@github.com:SoC-Labs/TideLink-Chiplet-GPIO-PHY.git
submodule.deps/tidelink-phy.url       git@github.com:SoC-Labs/TideLink-Chiplet-GPIO-PHY.git
```

Two submodule paths, one upstream repo, two very different revisions:

| path | pin | position |
|---|---|---|
| `deps/tidelink-phy` | `5c76e76` | `= origin/main` |
| `deps/tidelink-gpio-phy` | `6ee8418` | 2026-06-11 WIP; **3 ahead of `main`, 97 behind**, diverging at `7fb5d18` (2026-06-03) |

The two trees carry same-named modules — our own Makefile notes they "can never
co-compile" — so which one reaches a build is decided purely by flist choice.
`deps/tidelink-gpio-phy` appears to be reachable only from the V1 flist (finding
2), which suggests it may be vendorial dead weight.

**Ask:** is `deps/tidelink-gpio-phy` still needed? If V1 goes, it looks droppable,
which would remove a 97-commit-stale tree from every recursive clone.

---

## 4. Pinned commits were unreachable on the configured remote

Two separate instances broke fresh clones entirely — neither is visible to anyone
already holding a populated working copy, which is why they went unnoticed:

- **`tidelink` itself** was pinned at `9dfe1da`, which was **58 commits ahead of
  `origin/main` and on no remote branch at all**. `git submodule update` failed
  with `upload-pack: not our ref`. Now pushed to `origin/integ/eth-chiplet-pin`.
- **`deps/tidelink-gpio-phy`** pinned `6ee8418`, present on the GitLab mirror as
  `feat/standalone-phy-bist` but absent from the configured GitHub remote. Now
  pushed to GitHub under the same branch name.

Both are resolved from our side. Worth flagging as a habit though: work done in
detached HEADs gets pinned by the parent and never pushed, and the breakage only
appears on a machine that has never cloned before. A cheap guard is to check pins
against the **live** remote (`git ls-remote`, or `git fetch --prune` first) —
`git branch -r --contains` reads cached remote-tracking refs and will happily
report a deleted or rewound branch as still present. It told us these pins were
fine when they were not.

**Ask:** land `9dfe1da` (or its successor) on a default branch rather than leaving
the integration pin on a feature branch.

---

## 5. SSH URLs in `.gitmodules` are unusable from sandboxed CI

Minor, but it costs every sandboxed consumer a workaround.

The two PHY deps use `git@github.com:`. Our runner executes jobs inside a
bubblewrap sandbox, where `getpwuid()` fails — the account resolves via SSSD and
the sandbox binds neither the SSSD socket nor a real `/run`. OpenSSH refuses to
start at all under that condition:

```
No user exists for uid 74755
fatal: Could not read from remote repository.
```

Note this is **not** a missing-key problem — ssh aborts before it considers keys,
so no deploy key or agent would fix it.

All three GitHub repos in the tree are public as of today, so plain HTTPS URLs in
`.gitmodules` would work everywhere with no credential. We currently work around
it per-job with:

```bash
git config --global url."https://github.com/".insteadOf "git@github.com:"
```

**Ask:** consider HTTPS in `.gitmodules`. It costs contributors nothing (git
credential helpers handle push auth) and removes the workaround for every CI
consumer.

---

## 6. FYI — new port `tl_data_mode_o`

`tidelink_top` gained `tl_data_mode_o` on 2026-07-21 (`602ef8d`). Integrations
that don't connect it get a lint `PINMISSING`, which for us was a gate failure
until we tied it open explicitly. No action needed — just noting that new
top-level ports are a silent break for downstream lint, so calling them out in
release notes would help.

---

## What we verified working

So the above is understood as a report from a working integration, not a pile of
complaints — at pin `9dfe1da`, with the V2 flist and the fixes on our side:

- 43 submodules bootstrap cleanly from a fresh clone, anonymously, no credentials
- `make chip-boundary` — 111 ports, all accounted for
- `make lint` — all four Verilator passes clean, no non-waived findings
- `make elab` — 211 modules, `simv_chiplet` links
- `make elab-strict` — no multiple-driver nets in authored RTL

Happy to take any of items 1–5 as PRs against TideLink if that is easier than
picking them up your end — item 1 in particular is a two-line change and would
have saved us most of a debugging session.
