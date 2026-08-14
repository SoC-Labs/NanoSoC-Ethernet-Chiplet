# 29 — The private TSMC65 tech repository: where we got to

**Status: not built — and largely overtaken by a better answer.** No private
foundry repository exists, on GitHub or as a submodule anywhere. What happened
instead, on 2026-08-13, is that the toolkit was rewritten so it carries *no
foundry data at all* — every process value is now read from the licensee's own
PDK at run time — which removes most of the reason to have a private repo in the
first place.

Read this before deciding what to do next: the original request has not been
half-implemented and left dangling. It has been superseded, and the supersession
is undocumented. That is the actual gap.

---

## 1. Status

| Question | Answer | Evidence |
|---|---|---|
| Private tech repo created? | **No** | `gh repo list SoC-Labs` — 44 repos, none foundry/TSMC. The `*-Tech` repos that do exist (`milliSoC-Tech`, `ASIC-Library-Tech`, `SoCDebug-Tech`, `Generic-Library-Tech`, `RTL-Primitives-Tech`) are all **public** and none holds PDK data |
| Referenced as a submodule? | **No** | Neither toolkit checkout has a `.gitmodules` at all |
| Does TSMC data still live inline in the toolkit? | **No longer — that is the point** | `tech/tsmc65/` still exists, but now holds paths, keys and transforms only. `tech/tsmc65/gdsmap/` was deleted in `66c9118` |
| Any doc proposing the private-submodule design? | **None found** | Grep for "private submodule" / "private tech" across both trees' docs returns only CI-credential notes (`docs/source/howto/ci-runners.md:413`) |

**Which checkouts I read** (the two-checkout trap is live here — they differ):

| Checkout | Commit | Note |
|---|---|---|
| `…/nanosoc-ethernet-chiplet/ASIC/asic-toolkit` (submodule) | `dce2e51` on `main` | **ahead 1** of `origin/main` |
| `/home/dam1n19/SoCLabs/nanoSoC-ASIC-Toolkit` (standalone) | `7473345` on `main` | level with `origin/main` |

Both agree on everything in this report; the extra commit is a pad-ring flow fix.

---

## 2. What was actually built

Everything below is **implemented and working**, not merely designed, unless
marked otherwise.

**In the toolkit** (four commits, all 2026-08-13):

| Commit | What it did |
|---|---|
| `66c9118` | `tech: read the foundry's numbers from the PDK instead of carrying them` — the core change. Transcribed density rules, fill geometry, thicknesses, pad-ring dimensions and the stream-out map were deleted and replaced by load-time reads |
| `66135b5`, `31be8c7` | Stripped foundry numbers from docs and test fixtures |
| `7473345` | Apache-2.0 `LICENSE` + `VENDOR_COLLATERAL.md` — the one-page contributor rule |

The mechanism, in `tech/tech_api.tcl`: `tech_pdk_input` (:626), `tech_derived_dir`
(:658), `tech_defer` (:690), `tech_deferral_note` (:709), `tech_env` (:725),
`tech_check_files` (:1426). The TSMC65 pack uses 9 `tech_pdk_input` guards and 11
`tech_defer` calls (`tech/tsmc65/tech.tcl`), behind a single site variable,
`TSMC_65_HOME` (`tech/tsmc65/tech.tcl:48`). With no PDK mounted the derived keys
go **unset and reported**, never defaulted — an empty density table would make
metal fill fill nothing and report success.

**In this repo** (the concrete precedent, `fix/tag-ram-gwen`):

- `e424af6` — removed a 414,535-byte verbatim copy of TSMC's staggered IO-driver
  LEF that had been tracked on the **public** `origin/main` since `95f5e4a`
  (2026-08-06). Replaced by `ASIC/tech_wrappers/tsmc65/scripts/patch_pad_lef.py`,
  which reads the vendor file from the read-only PDK, applies three lines of
  project-owned intent by exact-match anchor, and writes to a gitignored build
  path. Input and output SHA-256 are both pinned, so a PDK bump fails loudly.
  Regeneration was verified byte-identical.
- `scripts/ci/check_no_vendor_collateral.sh`, wired at `Makefile:114`. Keys on
  **content** (vendor sha, patched sha, any tracked `.lef` over 64 kB), so a
  rename does not evade it.
- `.gitignore:144-170` — `generated/` and `local_overrides/*.lef|*.map` ignored;
  `local_overrides/` not being ignored was the root cause of the original leak.

**Designed/started but NOT finished:**

- `ASIC/genus-innovus/scripts/gdsmap_derive.py` (22 kB) — the same transform for
  the stream-out map. **Untracked.** Written, not committed.
- The `setup_dirs: pad-lef` hook lives in `ASIC/genus-innovus/Makefile`, which
  another session is holding; `e424af6` notes this as a known gap.
- **Nothing is on `main`.** The toolkit-submodule wiring (`20e73ae`) and the LEF
  removal (`e424af6`) are 27 commits deep on `fix/tag-ram-gwen`, and
  `git branch -r --contains e424af6` is **empty** — unpushed. The request was
  "do it on the main branch"; the public repo still has the vendor LEF on
  `origin/main` today.

---

## 3. What the design was — and what replaced it

**The original ask:** a private repo holding TSMC65 collateral, `git submodule
add`-ed into the toolkit and into every project instantiated from it. Public
flow, private foundry data, joined by a submodule boundary.

**What was adopted instead:** move the boundary from *repository* to *filesystem*.
No repo holds foundry data — not even a private one. A process pack
(`tech/<node>/`) holds only paths, keys and the transforms that read them; the
values live at the far end of a site-supplied environment variable and exist only
in the memory of the run that needs them. A pack that cannot reach the PDK defers
its keys rather than guessing. The `tech_api` contract is that boundary: `flow/`
may contain no cell name, layer name or micron value, and asks `tech_get` for
anything it needs.

The two are the same principle at different scale. The IO-pad LEF fix ships the
*transform*, not the *result*, for one file. The tech-pack rewrite ships the
transform, not the result, for an entire process node. The reasoning in
`VENDOR_COLLATERAL.md` is why a private repo is the weaker option: TSMC's
STATEMENT OF USE forbids *transcription* and *translation into any computer
language*, so a hand-typed Tcl table of LEF values is a breach wherever it is
stored — a private repo makes it less visible, not less of a breach.

A private repo would still be needed for genuinely non-derivable, per-site
artefacts. Nothing in the current pack needs one.

---

## 4. What is left to do — ordered

1. **Get `e424af6` onto `origin/main`.** The public repo carries the vendor LEF
   right now. Everything else here is secondary to that.
2. **Land the `pad-lef` make hook** once `ASIC/genus-innovus/Makefile` is free,
   so `config.tcl` stops failing with an instruction.
3. **Commit `gdsmap_derive.py`** and point the flow at it; retire the last
   `local_overrides/*.map`.
4. **Record the decision.** One short ADR: "private tech submodule — considered,
   superseded by runtime PDK reads". Without it this question gets re-asked.
5. **Run `check_no_vendor_collateral.sh` in the toolkit too.** The policy is
   written there (`VENDOR_COLLATERAL.md`) but only partly enforced
   (`test/python/test_klayout_drc.py:42,96,117`); the content-keyed guard lives
   only in this repo.
6. **Decide the toolkit's visibility.** It is private but has just been given
   Apache-2.0 and a "contains no foundry data" claim — that is a repo being
   prepared to go public. Either publish it or stop implying it.
7. Only then, if a real need survives: create the private repo for the residue.

---

## 5. Risks and open questions

- **Public repo → private submodule is already broken, today.** This repo is
  public; `SoC-Labs/nanoSoC-ASIC-Toolkit` is private. `clone --recursive` fails
  for anyone outside the org, and CI needs a token
  (`.github/workflows/ci-ladder.yml:171,189`; `asic-gds.yml:96-115`;
  `asic-signoff.yml:92-106`). **Adding a private tech submodule would make this
  strictly worse** — a second credential on the same path. The runtime-read
  design avoids adding one, which is a point in its favour.
- **The toolkit's own quickstart is broken for outsiders.** `README.md` says
  `git submodule add https://github.com/SoC-Labs/nanosoc-asic-flow.git` — a repo
  name that does not exist; the real one is `nanoSoC-ASIC-Toolkit`, and it is
  private.
- **Removal from `HEAD` is not removal from history.** The IO-pad LEF is in this
  public repo's history from `95f5e4a` onward. `e424af6` fixes the tip. Whether
  the history needs rewriting is a decision nobody has taken, and it gets more
  expensive every commit.
- **The supersession is undocumented**, so the private-repo plan will be proposed
  again. See item 4.
- **Site variables are the new single point of failure.** One `TSMC_65_HOME`
  now gates 20 derived keys. That is intended, and `tech_check_files` reports it
  before a licence-hour is spent — but a mis-set variable is now a silent
  20-key deferral rather than a loud missing file.

---

*Written 2026-08-13. Untracked by design — no commit made.*
