# IDCODE decision record — nanoSoC ethernet chiplet

**Status: DECIDED 2026-08-20. This is a decision record, not a plan.**

**Decision: this die ships with JEDEC manufacturer field `0x000`, permanently and
deliberately. No JEDEC JEP106 manufacturer ID will be requested for it.**

The IDCODE is **`0x10001001`** (`Makefile:444`, `src/rtl/bscan/pad_table.json:14`,
`src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv:110`,
`sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:233`):

| field | bits | value |
|---|---|---|
| version | `[31:28]` | `0x1` |
| part number | `[27:12]` | `0x0001` (this die; `0x0002` reserved for the compute chiplet) |
| **manufacturer** | `[11:1]` | **`0x000`** |
| required by 1149.1 | `[0]` | `1` |

This file supersedes `JEDEC_ID_REQUEST.md`, which described obtaining an ID as an
open action item. The research in that file is retained below because it is what
justifies the decision and what a future revisit would otherwise have to redo.

**Sections 1–4 record the facts. §5 records what the decision costs. §6 records the
circumstances under which it should be revisited. §7 records what could not be
established. §8 lists the consequential edits still outstanding.**

---

## 1. What was decided, and what changed to implement it

Before 2026-08-19 the tree carried `BSCAN_IDCODE = 0x100005A1`. Its manufacturer
field is `0x2D0`, which decodes (§3) to **JEP106 bank 6, code `0x50` — assigned to
Neterion Inc**. The die was announcing itself as a company that has nothing to do
with it, and would have kept doing so for the life of every part.

Two changes landed, both in commit `61aa090`:

1. **The manufacturer field became `0x000`** and the part number became `0x0001`
   (it had been `0x0000`, which discriminated nothing between this die and any
   sibling on the same scan chain).
2. **`scripts/gen_bscan.py` gained `check_idcode_manufacturer()`**
   (`scripts/gen_bscan.py:290`), which **fails the build** unless *either* the
   manufacturer field is `0x000`, *or* the pad table records a real JEDEC bank and
   code in `design.jedec` and the field packs from them exactly. `make bscan-check`
   runs the generator's `--check` gate (`Makefile:465–468`), so a hand-edited or
   invented constant is a build failure rather than a silent tapeout.

Recording an allocation is now the **only** way to get a non-zero manufacturer field.
The decision above is therefore enforced by tooling, not by convention.

---

## 2. Why `0x000` and not some other unused-looking number

### `0x000` is the one code JEP106 can never issue

JEP106 identity codes run **1..126** (`0x7F` is the continuation escape; `0` is not
issued). So a manufacturer field of `0x000` is not "unassigned today" — it is
**structurally unassignable, for the life of the registry**. It impersonates nobody
now and cannot come to impersonate somebody later.

Verified by inspection of the JEP106BO-aligned manufacturer table: **no slot with
identity code `0x00` exists in any of the 18 published banks.**

### There is no private, experimental or reserved range to use instead

JEP106 defines none. Inspection of all 18 populated banks (2202 populated slots)
found every slot to be a named company, with no reserved or TBD entries.

- **Banks 1 through 16 are 126 of 126 assigned — completely full.** There is no
  unallocated slot anywhere in the range a JTAG IDCODE can express (§4).
- **Memorable constants are the worst option.** `0xDEADBEEF` carries manufacturer
  field `0x777` = bank 15, code `0x77` — an assigned member, recorded elsewhere as
  *Fabric of Truth Inc* (see §7 on the provenance of that name). `0x12345678` has
  LSB 0 and is not a legal IDCODE at all.

Field arithmetic for all of the above was recomputed locally on 2026-08-20 and
agrees: `0x10001001` → manuf `0x000`; `0x100005A1` → manuf `0x2D0` = bank 6 code
`0x50`; `0xDEADBEEF` → manuf `0x777` = bank 15 code `0x77`; `0x12345678` → LSB 0.

### It is self-announcing at the strongest level a tool offers

OpenOCD range-checks the identity code **before** the table lookup
(`src/helper/jep106.c`: `if (id < 1 || id > 126) { ... return "<invalid>"; }`), so it
prints `mfg: 0x000 (<invalid>)` — **`<invalid>`, not the softer `<unknown>`** it
gives an unpopulated-but-legal slot. A reader of that log is told the field carries
no identity, rather than being left to wonder whether the table is out of date.

### It is the convergent practice for exactly this situation

- **OpenTitan / lowRISC**, `hw/ip/rv_dm/rtl/rv_dm.sv`:
  `parameter logic [31:0] IdcodeValue = 32'h 0000_0001`. Issue
  lowRISC/opentitan#490 states the intent: *"We currently use `00000001` as JTAG
  IDCODE for our system [...] If anybody builds a product out of our code, they
  should assign a different ID to it."* lowRISC later bought a real assignment and
  now ships `{4'd12, 7'b110_1111}` — bank 13, `0xEF`.
- **pulp-platform `riscv-dbg`**, **Hazard3** and **lowRISC's `sonata-system`** all
  ship `32'h00000001` while unallocated.
- **rocket-chip**, `DebugTransport.scala`: `idcodeManufId : Int, // Assigned by
  JEDEC`, defaulting to `0`.
- RISC-V's `mvendorid` rule — *"a value of 0 can be returned to indicate a
  non-commercial implementation"* — is the same instinct in a different register.

---

## 3. How a JEP106 code becomes the 11-bit manufacturer field

Retained because §6's revisit path needs it, and because this is the step most often
got wrong.

IEEE 1149.1's device identification register is:

```
 bits [31:28]  version         4 bits
 bits [27:12]  part number    16 bits
 bits [11: 1]  manufacturer   11 bits   <-- the JEDEC field
 bit  [    0]  always 1                 <-- distinguishes IDCODE from BYPASS
```

The 11-bit manufacturer field is **not** the JEP106 byte. Two things happen to it:

1. the **odd-parity bit is discarded**, leaving the 7-bit code in `[7:1]`;
2. the continuation bytes are **counted, not carried** — the count goes in `[11:8]`.

```
IDCODE[11:1] = (continuation_count << 7) | code7
             = ((bank - 1)        << 7) | code7
```

Arm's Cortex-M3 TRM Table 12-17 gives exactly this split (continuation code, 4 bits,
`[11:8]`; identity code, 7 bits, `[7:1]`), and OpenOCD implements it as
`jep106_table_manufacturer(manufacturer >> 7, manufacturer & 0x7f)` with
`#define EXTRACT_MFG(X) (((X) & 0xffe) >> 1)`.

Worked examples, each cross-checked against the JEP106 table:

| Vendor | JEDEC assignment | continuations | 7-bit code | `IDCODE[11:1]` |
|---|---|---:|---:|---|
| Arm Ltd | bank 5, `0x3B` | 4 | `0x3B` | `0x23B` |
| TSMC | bank 6, `0x68` | 5 | `0x68` | `0x2E8` |
| SiFive | bank 10, `0x89` | 9 | `0x09` | `0x489` |
| lowRISC | bank 13, `0xEF` | 12 | `0x6F` | `0x66F` |

Note lowRISC's row: JEDEC issued the byte `0xEF`, whose parity bit is set; stripping
it gives `0x6F`. Their RTL encodes it literally as `{4'd12, 7'b110_1111}`.

```python
# bank and code as JEDEC issues them, e.g. bank=13, code=0xEF
manuf = ((bank - 1) << 7) | (code & 0x7F)          # strip parity, count continuations
idcode = (version << 28) | (part << 12) | (manuf << 1) | 1
```

---

## 4. What a request would have involved, and the constraint that makes it moot

Recorded so that §6's revisit does not have to re-derive it, and because the last
item below is the reason the purchase was not simply bought as insurance.

### The process

JEP106 §3 names the route in the standard itself: a request to the JEDEC office via
`http://www.jedec.org/standards-documents/id-codes-order-form`. From the order form
(read from an archived snapshot dated 2026-04-27; `jedec.org` returns 403 to
automated fetches):

- JEDEC item number **4900**; price **$750 (one time fee)**; **all orders require
  prepayment**; **ALL SALES ARE FINAL. JEDEC Membership is NOT required to purchase
  an ID Code.**
- **Delivery: fulfilled by email within 10 business days of confirmed payment.**
- *"the company name and ID code assigned will be included in JEDEC publication
  JEP106 (all future versions)"* — the assignment is **public and permanent**, and
  the entity named cannot be changed later.

JEDEC membership dues (archived 2026-08-03): one committee $7,195; two $11,804;
three $17,199; four or more $21,588. **Not required** — the order form says so.

### The constraint: every bank a JTAG IDCODE can express is full

The IDCODE's manufacturer field packs the continuation count into **4 bits**
(`[11:8]`), so a JTAG IDCODE can express only **JEDEC banks 1 to 16**. JEP106BO
publishes banks 17 and 18, which alias onto banks 1 and 2 — an ID in those banks
**cannot be represented in a JTAG IDCODE without colliding with a bank 1 or bank 2
assignee.**

| JEDEC bank | populated | representable in a JTAG IDCODE? |
|---|---:|---|
| 1 – 16 | **126 / 126 each — full** | yes |
| 17 | 126 / 126 — full | **no** — aliases onto bank 1 |
| 18 | 60 / 126 — **filling now** | **no** — aliases onto bank 2 |

**JEDEC is currently issuing into bank 18.** An ID bought today would, in all
likelihood, land in a bank this die's IDCODE cannot express — so $750 would not
have bought a usable JTAG identity. Whether JEDEC can still issue a bank 1–16 code
on request is **not established** (§7): nobody asked.

---

## 5. What this decision costs

Stated plainly, because it is the half of a decision record that is usually missing.

### What still works, unchanged

- **The IDCODE instruction works normally.** `0x10001001` is a well-formed 32-bit
  IDCODE with LSB 1, so a tool's chain auto-discovery — counting devices, measuring
  IR lengths, distinguishing IDCODE from BYPASS — behaves exactly as it would for
  any assigned vendor. The manufacturer field has no effect on TAP behaviour.
- **Every boundary-scan instruction works.** EXTEST, SAMPLE/PRELOAD, CLAMP and
  BYPASS are unaffected. The manufacturer field is read-only data.
- **A board-test house can run a full interconnect test.** BSDL is bound to a device
  position by explicit assignment in the tester's setup; it does not require an
  IDCODE match to load.
- **The two dies remain distinguishable from each other** — by part number
  (`0x0001` here, `0x0002` reserved for the compute chiplet), not by manufacturer.

### What does not work

1. **No tool will auto-select this die's BSDL from an IDCODE-keyed library.**
   Testers, scan-chain browsers and CoreSight enumerators that maintain a
   vendor/device database keyed on IDCODE will find no entry. **The operator must
   point the tool at `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl` explicitly, for
   this device position, every time.** This is a recurring manual step in every test
   program and every debug session, not a one-off.

2. **The die does not identify its maker.** There is no IDCODE-based provenance,
   anti-counterfeit or "which fab/project is this part from" answer. A part found
   loose on a bench cannot be traced to SoC Labs through its JTAG identity. The
   BSDL says so in its own `DESIGN_WARNING`: *"Do not identify this device by its
   IDCODE."*

3. **Tools will report the manufacturer as invalid or unknown.** OpenOCD prints
   `mfg: 0x000 (<invalid>)`; this is verified from source. Behaviour of Vivado,
   Quartus, TRACE32, J-Link and UrJTAG on manufacturer `0x000` is **not
   established** (§7). If any of them treats an unresolvable manufacturer as an
   error rather than a warning, that tool will need configuring to accept it, and
   the work to find out has not been done.

4. **The part number becomes the only discriminator in a multi-device chain.**
   Manufacturer `0x000` is not unique to this project — every design listed in §2
   ships something close to it. If this die ever shares a scan chain with another
   null-manufacturer device, `part = 0x0001` is the *entire* difference between
   them. That is why the compute chiplet's `0x0002` reservation matters more here
   than it would for a vendor with a real ID, and why it must actually be applied
   on that die (§8).

5. **The decision is irreversible for silicon already made.** The IDCODE is
   hard-wired: `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:354`
   instantiates `nanosoc_eth_chiplet_bscan` with **no parameter override**, so the
   generated default reaches the die and there is no second place to change it.
   Buying an ID later changes future silicon only; parts already in the field keep
   manufacturer `0x000` for ever. There is no errata mechanism for a hard-wired
   IDCODE.

6. **Enforcement exposure — not established.** Whether anything *enforces*
   manufacturer IDs (a conformance gate, a JEDEC term, trademark) could not be
   established; JEDEC's order-form terms say nothing about misuse. No documented
   case of a *JTAG* IDCODE collision causing a field failure was found. This cost is
   listed as unquantified, not as zero.

### For context: the cost the previous value would have carried

Ordered by likelihood of actually biting. All of these are **avoided** by the
decision; they are recorded because they are what makes reaching for another
invented number later a mistake.

1. **The die would identify itself as another company.** OpenOCD prints, on every
   scan-chain examination, `"JTAG tap: %s %16.16s: 0x%08x (mfg: 0x%3.3x (%s), part:
   0x%4.4x, ver: 0x%1.1x)"`, resolving `%s` through the JEP106 table. The log would
   read `mfg: 0x2d0 (Neterion Inc)` — in bug reports, papers and partner hand-offs.
2. **A board tester would bind the wrong BSDL.** `0x100005A1` is a plausible-looking
   Neterion part `0x0000`; it is not obviously junk, so nothing prompts an operator
   to look twice. The failure mode is a *silently wrong* 76-cell boundary register
   description, not a refusal to proceed. Under manufacturer `0x000` the tool finds
   nothing and asks — which is the point of §5 item 1 being a cost worth paying.
3. **The mistake would age badly**, for the same irreversibility reason as §5 item 5.

**Precedent that the registry does get abused, and what it costs.** In SPI-NOR ID
space — the same JEP106 registry, a different consumer — collisions are common
enough that the Linux MTD subsystem carries a dedicated collision-disambiguation
driver. From that series: *"Some manufacturers completely ignore the manufacturer's
identification code standard (JEP106) [...] Boya ignores the continuation scheme and
its ID collides with the manufacturer defined in bank one: Convex Computer."* Others
document Winbond parts shipping under Nexcom's `0xEF` and Micron parts identifying
as STMicro. The lesson is not that JTAG fails the same way — it is that once a wrong
ID is in silicon, the cost lands on downstream tool maintainers and is paid for ever.

---

## 6. When this decision should be revisited

Revisit if **any** of the following becomes true. None of them is true as of
2026-08-20.

1. **The die is to be sold or distributed as a product bearing an organisation's
   identity**, rather than used as a research/academic test vehicle. A commercial
   part that cannot name its maker over JTAG is a different proposition from a lab
   chiplet.
2. **A board-test house, customer or partner makes an IDCODE-resolvable
   manufacturer a condition** — of a test program, a tool flow, or a contract. §5
   item 1 is a manual step; if a counterparty will not accept a manual step, the
   ID becomes a purchase, not a preference.
3. **This die will share a JTAG chain with another null-manufacturer device whose
   part number could collide with `0x0001`.** Part number is the only discriminator
   left (§5 item 4); if it stops discriminating, the manufacturer field has to.
4. **A tool in the required flow refuses an unresolvable manufacturer.** §7 records
   that only OpenOCD's behaviour was verified. If a tool that must be used turns out
   to hard-error, that changes the cost from "manual step" to "blocked".
5. **JEDEC confirms a bank 1–16 code can still be issued** *and* one of 1–4 above
   applies. On its own this changes nothing: §4 makes the purchase useless for JTAG
   unless the bank is representable, but a representable bank does not by itself
   create a reason to buy.

**What a revisit costs, mechanically:** it is a purchase order, not a standards
application — $750, no membership, ~10 business days from *confirmed payment*
(§4). **Ask JEDEC about bank 1–16 availability before paying**, and choose the
named legal entity deliberately: the assignment is public and permanent, all sales
are final, and whether the entity should be "SoC Labs", the University of
Southampton or another body is a decision for whoever holds the budget (§7).

---

## 7. How to apply an allocation, if §6 is ever triggered

The IDCODE has **one source of truth and four generated consumers.** Do not edit
the generated files: `python3 scripts/gen_bscan.py --check` is a CI gate and a
hand-edit is a build failure by design.

### 7a. Sites to edit by hand

| # | File | Line | Content now | Role |
|---|---|---:|---|---|
| 1 | `Makefile` | 444 | `BSCAN_IDCODE := 0x10001001` | **the flow's entry point** — passed to `gen_pad_table.py --idcode` by the `bscan-table` target |
| 2 | `scripts/gen_pad_table.py` | 183 | `ap.add_argument("--idcode", default="0x10001001", ...)` | **the generator constant** — the fallback default; keep it in step with #1 or a table generated without the Makefile silently reverts |
| 3 | `src/rtl/bscan/pad_table.json` | 14 | `"idcode": "0x10001001"` | the committed pad table's `design.idcode`; **written by #2, read by `gen_bscan.py`** |
| 4 | `src/rtl/bscan/pad_table.json` | — | *(absent)* `design.jedec` | **the allocation record.** Add `"jedec": {"bank": N, "code": C}` — with `C` the 7-bit code, parity stripped — and the guard derives and enforces the manufacturer field. This is the **only** way to legitimately get a non-zero field |
| 5 | `verif/bscan/tb_bscan_gate.sv` | 89 | `IDCODE_INTENDED = 32'h1000_05A1` | the gate bench's expected value. **This is currently CORRECT and must not be "fixed" blind** — see §7c |

`verif/bscan/tb_bscan.sv:70` already holds `32'h1000_1001` and needs no change.

### 7b. Sites that regenerate — never edit these

| File | What carries the ID | Produced by |
|---|---|---|
| `src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv:110` | **the RTL parameter** `IDCODE_VALUE` | `gen_bscan.py` `render_rtl()` |
| the same file, the adjacent comment block | the manufacturer-field explanation | `gen_bscan.py` `idcode_notes()` |
| `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:233` | **the BSDL attribute** `IDCODE_REGISTER`, four binary field strings | `gen_bscan.py` `render_bsdl()` |
| the same BSDL, the comment above it | the same explanation as `--` comments | `gen_bscan.py` `idcode_notes()` |
| the same BSDL, `DESIGN_WARNING` and the banner's open-items list | the tester-visible summary | `gen_bscan.py` |

`idcode_notes()` is the single derivation behind all of these, so the die and its
description cannot disagree about whether the number identifies anyone. **All of
this prose switches automatically** when `design.jedec` is present — there is no
placeholder text left to remember to delete.

**The RTL parameter is what silicon gets.**
`ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v:354` instantiates the wrapper
with **no parameter override**.

### 7c. Procedure

```
# 1. edit sites 1, 2 and add the `jedec` block (site 4) above
# 2. re-derive the pad table (this rewrites site 3):
make bscan-table            # NOTE: reads the PRE-SPLICE pad ring from commit 458d108
# 3. regenerate both outputs:
make bscan-gen
# 4. prove they agree with the table, the ring and the boundary spec:
make bscan-check
# 5. re-run the RTL bench:
make bscan-sim
# 6. rebuild the routed netlist BEFORE re-running the gate bench, then update
#    site 5 -- or run it with  +idcode=<new value>  against a rebuilt netlist.
```

`gen_bscan.py` asserts `IDCODE_VALUE & 1`, asserts that its own four-way field split
recomposes to the parameter, and refuses to build if the manufacturer field is
non-zero without a recorded allocation, or if a recorded allocation does not pack to
the field.

If re-running `bscan-table` is undesirable (it re-derives the whole table from a
historical commit), editing `design.idcode` in `pad_table.json` directly and running
`make bscan-gen` is equivalent for this field. Expect the SHA-256 stamped in both
generated banners to change either way.

**Worked example.** For lowRISC's real assignment of "bank 13, `0xEF`":

```json
"jedec": { "bank": 13, "code": 111 }        // 0xEF & 0x7F = 0x6F = 111
```

and set `BSCAN_IDCODE` so that `IDCODE[11:1] == ((13 - 1) << 7) | 0x6F == 0x66F`.
The guard recomputes this and fails if the two disagree.

### 7d. The gate bench expects the netlist's value, not the RTL's — on purpose

`verif/bscan/tb_bscan_gate.sv:89` holds `32'h1000_05A1` because the routed netlist it
drives (`ASIC/eth-chiplet/build/bscan-probe/outputs/nanosoc_eth_chiplet_pads_pnr.v`)
was written at 18:57 on 2026-08-19, before `61aa090` landed at ~22:17. **That netlist
still carries the retired value, and it answers it** — measured, `verif/bscan/build_gate/sim.log:71`,
`IDCODE read back: 32'h100005a1`. Expecting the RTL's value against that netlist
would turn a design that is answering correctly into a red.

`scripts/bscan_bsdl_crosscheck.py` (added in `6c82edb`) found this divergence
independently, comparing BSDL `0x10001001` against netlist `0x100005A1`.
**That netlist must be rebuilt before it is used for anything**, and when a netlist
built after `61aa090` arrives, run the bench with `+idcode=10001001` and then move
the constant.

---

## 8. Outstanding, and not closed by this decision

- **The compute chiplet.** Part number `0x0002` is reserved for it here, but the
  reservation has to be applied in its own repository, and that die's IDCODE should
  be checked for the same manufacturer squat. §5 item 4 makes this load-bearing:
  if both dies ship manufacturer `0x000` and both ship part `0x0001`, they are
  indistinguishable on a shared chain.
- **The routed netlist is stale with respect to this decision** — §7d.
- **Six files still point at the old filename.** This document was renamed from
  `JEDEC_ID_REQUEST.md`; the following still reference the old path and are outside
  the remit of the change that renamed it:
  `Makefile:443`, `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl:232`,
  `src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv:109`, `scripts/gen_bscan.py:332`,
  `scripts/gen_bscan.py:382`, `src/rtl/bscan/INTERFACE_CONTRACT.md:202`.
  Four of those six are **generated** — `gen_bscan.py` is the source for the BSDL
  and wrapper strings, so fixing `gen_bscan.py:332` and `:382` and re-running
  `make bscan-gen` closes four of them at once.
- **`docs/bscan/` is not in `mkdocs.yml`'s nav**, so neither this file nor
  `BRINGUP.md` is published by the docs site.

---

## 9. What could not be established

Stated explicitly so nobody re-derives these as if they were settled.

- **Whether JEDEC can still issue a bank 1–16 code.** The question in §4 was never
  put to JEDEC. The bank table shows 1–16 at 126/126 and issuance running in bank
  18; whether JEDEC holds back reclaimed slots, or advises something else for JTAG
  users, is unknown.
- **Real-world lead time.** No first-hand account of an organisation applying and
  reporting elapsed time or friction was found. **The 10-business-day figure is
  JEDEC's own claim and is uncorroborated.**
- **The IEEE clause reserving the all-ones / `0b0000_1111111` manufacturer value.**
  IEEE 1149.1 is paywalled and its text could not be obtained. That such values are
  unreachable is *derivable* from JEP106 (`0x7F` is the continuation escape and so
  can never be an identity) plus the IDCODE field layout, and that derivation is what
  is relied on above. **Do not cite an IEEE clause number for it.**
- **A documented JTAG-IDCODE collision causing a specific field failure.** None
  found. The collisions in §5 are SPI-NOR `RDID`. Say "no documented case found",
  not "no such case exists".
- **Behaviour of specific commercial tools** (Vivado, Quartus, TRACE32, J-Link,
  UrJTAG) on an unknown or mismatched IDCODE. Only OpenOCD's behaviour was verified
  from source. This is the gap behind §5 item 3 and §6 item 4.
- **The company name behind `0x777`.** The bank-15/code-`0x77` arithmetic was
  recomputed locally and is certain; the name *Fabric of Truth Inc* comes from the
  JEP106BO-aligned table lookup and could not be re-verified on this host (no
  JEP106 table is installed here). An earlier revision of this document recorded
  only "an assigned member" without naming it.
- **Which legal entity should be named**, were an ID ever bought — "SoC Labs", the
  University of Southampton, or another body. This is a decision for whoever holds
  the budget, and it is irreversible.
- **JEP166F** ("JC-42.6 Manufacturer ID", for LPDDR / Wide-IO) is a *separate*
  registry with its own order route; its price could not be confirmed. It is not
  relevant to JTAG.

---

## Provenance

JEP106AY (Feb 2019) normative text; JEDEC ID-code order form and membership-dues
pages (archived snapshots 2026-04-27 and 2026-08-03 — `jedec.org` returns 403 to
automated fetches); Arm Cortex-M3 TRM Table 12-17; OpenOCD sources
(`src/helper/jep106.{c,h}`, `src/jtag/core.c`) and its JEP106BO-aligned manufacturer
table; OpenTitan, rocket-chip, pulp-platform `riscv-dbg`, Hazard3 and
`sonata-system` sources; Linux MTD "Manufacturer ID collisions" series. Field decode
of `0x100005A1` and the `Neterion Inc` lookup were computed and re-verified against
four known-good controls. All IDCODE field arithmetic quoted here was recomputed
locally on 2026-08-20. In-tree line numbers were verified against the working tree
on branch `feat/padring-boundary-scan` on 2026-08-20.
