# 44 — The eth boot ROM's sim/silicon divergence is DECLARED, not a defect

[index](00-index.md) · [34 Content gates runbook](34-content-gates-gate1-runbook.md) · [16 Open defects](16-open-defects.md)

**Investigated 2026-08-18.** `make -f ASIC/common.mk romlibs-verify` passes, and raises one
WARN: the simulation boot ROM for `eth_rom` carries a different program from the one
mask-programmed into silicon. This page establishes that the divergence is **deliberate,
per-environment, and by construction** — and that regenerating the file to "fix" it would
produce a false green rather than a real agreement.

---

## TL;DR

| | |
|---|---|
| **Is the divergence real?** | Yes. 172 of 512 words differ; genuinely different data, not a permutation. |
| **Is it a defect?** | **No.** It is the documented design of a mutable, gitignored slot. |
| **Should the file be regenerated?** | **No.** The change is not landable and not durable — see §4. |
| **Is the silicon image simulated anywhere?** | **Yes** — `soc_boot_flash` and `soc_dma250_boot` install it and boot it. |
| **Resolution** | Declare it: allow-list the smoke_remap content hash, with this page as the reason. |

The WARN text, verbatim:

```
[WARN] sim_divergence  SIM/SILICON DIVERGENCE: the simulation boot ROM eth_ss_bootrom.sv
differs from the ASIC code file in 172/512 words (genuinely different data (set-bit
populations differ)); it matches .../smoke_remap/eth_ss_bootrom.bintxt (512/512 words).
sim content sha256=9d5fa954ceb646f51aaf5f40f615380dc4296760ca533846ebb553d20434d504
-- not allow-listed.
```

`cc_rom` passes its `sim_divergence` check 512/512. The asymmetry is not evidence of an
accident on the eth side; it is because only the eth ROM has more than one legitimate
boot program (see §3).

---

## 1. The file the gate reads is a MUTABLE SLOT, not source

`ROM_SIM_eth` points at `nanosoc-multicore-system/src/rtl/bootrom/eth_ss_bootrom.sv`.
That file is:

- **untracked** — `git ls-files` does not know it;
- **gitignored** — `.gitignore:179`, `/src/rtl/bootrom/eth_ss_bootrom.sv`;
- **materialised on demand** by `scripts/ensure_bootrom.sh`, from the tracked
  `eth_ss_bootrom_default.sv`, idempotently and only when absent.

This was made deliberate by submodule commit `f4793b6`, *"fix(A4): stop tracking the
bootrom slot; it was never a set_env.sh problem"*, whose message states the intent
directly:

> that file is a MUTABLE SLOT. `scripts/install_bootrom.sh` drops a build-specific
> bootloader variant into it, and 56 cocotb and pynq targets call it. **Whichever flow
> ran last decides its contents.**

So the content the ROM gate hashes is **workspace state**, not a committed artefact. Its
value answers the question "which simulation environment was built here most recently",
which is not the same question as "what does simulation boot".

## 2. Who installs what

`scripts/install_bootrom.sh <variant>` copies a build-dir `.sv` over the slot. Measured
by grep over the submodule's cocotb/pynq Makefiles:

| variant | environments | what it is |
|---|---:|---|
| `smoke_remap` | **54** | remap IMEM→0x0 and jump to `$readmemh`-preloaded firmware |
| `stage0` | **2** | the real CPU0 stage-0 bootloader — the silicon image |

The two `stage0` environments are `cocotb/soc_boot_flash` and `cocotb/soc_dma250_boot`.
Each environment installs its own variant as a prerequisite of `simv`, so **the resting
content of the slot does not determine what any environment simulates.** `soc_boot_flash`'s
own header says so:

> NOTE: running this env mutates the shared stub to stage0 content. Any other cocotb env
> that runs afterwards installs its own variant via `scripts/install_bootrom.sh`, so
> **regression ordering is safe.**

## 3. Why `smoke_remap` exists: the silicon bootloader cannot run in an IMEM-preload env

`firmware/bootloader/stage0_bootrom/main.c` is the SECONDARY-role bootloader. In order it:

1. waits (bounded, ~0x40000 spins) for CPU1's XiP-WARM handshake word `0xD15C0001` in IPC
   mailbox slot-1;
2. **reads back QSPI `CTRL.XIP_ACTIVE`, and calls `halt()` if it is not latched** —
   `halt()` prints `'X'` and spins in `wfi()` forever;
3. parses a boot table out of XiP flash, copies the app image into IMEM, and CRC-checks it;
4. sets VTOR, REMAPs IMEM→0x0 and branches.

In the 54 environments that preload IMEM via `$readmemh` and instantiate no QSPI flash
model, step 2 halts. CPU0 never boots. That is the concrete reason a smoke variant exists,
and `smoke_remap/main.c` says the same thing in its header — *"For use in cocotb/soc_smoke
where IMEM is pre-loaded with firmware via `$readmemh` and no QSPI flash is present."*

Both CMake files spell out the split explicitly. `smoke_remap/CMakeLists.txt` writes the
shared stub and is in `ALL`; `stage0_bootrom/CMakeLists.txt` is opt-in, emits only into
the build tree, and comments:

> This target is opt-in: it emits its own `.sv` into the build tree and does NOT touch the
> in-tree stub. […] then any subsequent `make firmware` run rewrites the stub back to
> smoke_remap — **so the default (IMEM-preload) test flow stays stable.**

`ASIC/rom_gate.mk` anticipated exactly this when it wired the check: *"A difference is a
WARNING, not a failure: sim and ASIC may legitimately diverge."*

## 4. Why regenerating the slot would be a false green

Three independent reasons, any one of which is sufficient:

1. **There is nothing to commit.** The slot is gitignored and untracked. A regeneration
   changes only this workspace; a fresh clone or CI checkout is unaffected. The WARN would
   still fire everywhere else.
2. **It self-reverts.** `add_custom_target(generate_smoke_bootrom ALL ...)` copies
   smoke_remap into the slot on *every* firmware build, and 54 cocotb targets reinstall it
   before compiling. The gate would go green until the next build and then flip back —
   read, at that point, as a regression.
3. **It would break the default RTL suite** *if* it ever did stick: per §3, the stage0
   image halts in an IMEM-preload environment.

## 5. Three states the slot can hold — and one genuine latent finding

Measured with `scripts/ci/rom_verify.py` against the silicon code file
(`.../stage0_bootrom/eth_ss_bootrom.bintxt`, sha256 `582200fe…`):

| slot content | content sha256 | vs silicon | how you get it |
|---|---|---:|---|
| `smoke_remap` (current) | `9d5fa954…` | 340/512 match | any `make firmware`, or 54 cocotb envs |
| tracked `eth_ss_bootrom_default.sv` | `153fc65d…` | 415/512 match | fresh clone → `ensure_bootrom.sh` |
| `stage0` build-dir `.sv` | — | **512/512 PASS** | `soc_boot_flash`, `soc_dma250_boot` |

The third row is a **positive control**: pointing the checker at the stage0 build product
yields a clean pass, which proves the checker, the generator and the silicon image all
agree. The only variable is which variant is installed.

**The second row is a separate, genuine finding.** `eth_ss_bootrom_default.sv` is the
tracked canonical bytes a fresh clone gets, and it is neither smoke_remap nor the current
stage0 — it best-matches the stage0 program at 415/512, i.e. it is a **stale stage0
vintage**. Because `lint/`, `cdc/`, `formal/` and `syn/` read the slot without ever calling
`install_bootrom.sh`, those flows elaborate a stale image. Nothing executes the ROM in
those flows, so the impact is low — but refreshing that default from the current stage0
build is the one place where "make the sim view match silicon" is both durable and
harmless. **Not done here** (it is a tracked change in a shared submodule); recommended
separately.

## 6. The declared divergence

The checker accepts an allow-list entry, but **nothing currently passes
`--allow-sim-divergence`** — `ASIC/rom_gate.mk`'s `rom-verify-%` recipe has no hook for it.
Landing the declaration therefore needs the following change, which is an **owner change to
`ASIC/rom_gate.mk` and has NOT been made**:

```make
# ── Declared sim/silicon divergences, per ROM ──────────────────────────────
# The eth simulation slot is a MUTABLE SLOT (gitignored; whichever flow ran
# last decides its contents). Its DECLARED default is the smoke_remap image,
# installed by 54 of 56 cocotb/pynq envs, because the real stage-0 bootloader
# halts in an IMEM-preload environment with no QSPI flash model. The silicon
# image IS simulated, by soc_boot_flash and soc_dma250_boot, which install it.
# Reason and evidence: docs/tapeout/44-eth-rom-sim-divergence.md
ROM_SIM_ALLOW_eth ?= sha256:9d5fa954ceb646f51aaf5f40f615380dc4296760ca533846ebb553d20434d504
ROM_SIM_ALLOW_cc  ?=
```

and, inside the `rom-verify-%` recipe, one line after the `--sim-rtl` argument:

```make
	    $(foreach a,$(ROM_SIM_ALLOW_$*),--allow-sim-divergence "$(a)") \
```

With that in place the finding reads `[WARN] … [ALLOW-LISTED]` and carries a reason.

**Deliberately hash-scoped, not glob-scoped.** A pattern such as `*/smoke_remap/*` would
also silence a future *third* program landing in the slot. Pinning the sha256 means the
declaration covers exactly the image that was reasoned about here, and anything else —
including the stale default of §5 — still raises an un-acknowledged warning.

## 7. What this does NOT establish

- It does not verify the silicon image itself. That is `content_equivalence`, which passes
  512/512 against the physical bit-cell array, and the reticle check recorded elsewhere.
- It does not claim the eth RTL suite has ever exercised the silicon boot path *broadly* —
  it has not. Two environments do; the other 54 boot a stub by design.
- The stale tracked default (§5) is left open.
