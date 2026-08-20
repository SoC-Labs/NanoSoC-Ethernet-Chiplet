# JEDEC manufacturer ID — action item for the nanoSoC ethernet chiplet

**Status: PARTIALLY ACTIONED 2026-08-19. The squat is fixed; the purchase is still OPEN.**

**Bottom line: an ID costs $750 one-off, needs no JEDEC membership, and JEDEC fulfils by email
within 10 business days of payment.** That is cheap and fast enough that buying one before the
1 September submission is a real option, not a someday item — see §4, and §4a for a hard
constraint that must be raised with JEDEC *at order time*.

Raised from `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl`. Every fact below is marked
**CONFIRMED**, **SECONDARY** or **UNCONFIRMED**; §8 lists what could not be established.

**What was found (§3):** the previous placeholder `0x100005A1` was not an unused value. Its
manufacturer field `0x2D0` decodes to a JEP106 code **assigned to Neterion Inc** — the die was
impersonating a real company.

**What was done (§7):** the manufacturer field is now `0x000`, the one code JEP106 can never
issue, and `scripts/gen_bscan.py` now **refuses to build** any non-zero manufacturer field unless
a real allocation is recorded. Buying an ID remains outstanding.

---

## 1. What a JEDEC manufacturer ID is

It is an entry in **JEDEC JEP106**, *Standard Manufacturer's Identification Code* — the registry
that gives each silicon vendor a number so that a device can say who made it. The same registry is
read by JTAG IDCODE, SPI-NOR `RDID`, SDRAM SPD and CoreSight ROM tables.

**CONFIRMED** (JEP106AY §2, Feb 2019):

> "The manufacturer's identification code is defined by one or more eight (8) bit fields each
> consisting of seven (7) data bits plus one (1) odd parity bit. It is a single field limiting the
> possible number of vendors to 126. To expand the maximum number of identification codes a
> continuation scheme has been defined. The code 7F [...] indicates that the manufacturer's code is
> beyond the limit of this field and the next sequential manufacturer's identification field is
> used."

So an assignment is a pair — **a bank and a code**:

- the **code** is 7 bits, values **1 to 126** (`0x7F` is reserved as the continuation escape, and
  `0` is not issued). The parity bit is the **MSB**, odd parity.
- the **bank** is expressed on the wire as that many `0x7F` continuation bytes ahead of the code.
  JEDEC names banks from 1, so **bank *N* = *N*−1 continuation bytes**.

JEDEC's own example format is "bank 13, 0xEF" (lowRISC's assignment). The current revision is
**JEP106BO, May 2026**; JEDEC lists it as a free download subject to registration. **CONFIRMED.**

There is **no private-use, experimental or reserved range.** JEP106 defines none, and an inspection
of all 18 populated banks of OpenOCD's JEP106BO-aligned table found every slot to be a named
company, with no reserved or TBD entries. **CONFIRMED** (JEP106 normative text + table inspection).

---

## 2. How a JEP106 code becomes the 11-bit IDCODE manufacturer field

This is the step that is most often got wrong, so it is written out in full.

IEEE 1149.1's device identification register is:

```
 bits [31:28]  version         4 bits
 bits [27:12]  part number    16 bits
 bits [11: 1]  manufacturer   11 bits   <-- the JEDEC field
 bit  [    0]  always 1                 <-- distinguishes IDCODE from a BYPASS register
```

The 11-bit manufacturer field is **not** the JEP106 byte. Two things happen to it:

1. the **odd-parity bit is discarded**, leaving the 7-bit code in `[7:1]`;
2. the continuation bytes are **counted, not carried** — the count goes in `[11:8]`.

```
IDCODE[11:1] = (continuation_count << 7) | code7
             = ((bank - 1)        << 7) | code7
```

**CONFIRMED** — Arm Cortex-M3 TRM Table 12-17 gives exactly this split (continuation code, 4 bits,
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

Note lowRISC's row: JEDEC issued the byte `0xEF`, whose parity bit is set; stripping it gives
`0x6F`. Their RTL encodes it literally as `{4'd12, 7'b110_1111}`. That is the shape to copy.

To go from an assignment straight to the constant this design needs:

```python
# bank and code as JEDEC issues them, e.g. bank=13, code=0xEF
manuf = ((bank - 1) << 7) | (code & 0x7F)          # strip parity, count continuations
idcode = (version << 28) | (part << 12) | (manuf << 1) | 1
```

---

## 3. What was found — the placeholder was a squat

**This section records the defect. §7 records the fix.**

The value in the tree until 2026-08-19 was `BSCAN_IDCODE = 0x100005A1`, which decomposes as:

| field | value |
|---|---|
| version `[31:28]` | `0x1` |
| part number `[27:12]` | `0x0000` |
| **manufacturer `[11:1]`** | **`0x2D0`** |
| bit 0 | `1` (required) |

Applying §2 in reverse to `0x2D0` = `0b0101_1010_000`:

- continuation count `[11:8]` = `0b0101` = **5** → **JEDEC bank 6**
- identity code `[7:1]` = `0b1010000` = **`0x50`**

**Bank 6, code `0x50` is an assigned JEDEC entry: `Neterion Inc`.** **CONFIRMED** by lookup in the
JEP106BO-aligned table, with Arm/TSMC/SiFive/lowRISC used as controls to validate the lookup method.

This is the finding that changes the character of the action item. The placeholder was chosen to be
a meaningless number; it is not one. It is a **structurally valid, currently-assigned** manufacturer
ID belonging to a third party. Silicon carrying it does not read as "no vendor" — it reads as
*Neterion*, and every IDCODE-keyed tool will say so out loud (§6).

### There was no safer invented value to reach for

Two things make "just pick a different number" a trap, both **CONFIRMED** by exhaustive inspection
of the JEP106BO-aligned table (2202 populated slots):

- **Banks 1 through 16 are 126 of 126 assigned — completely full.** There is no unallocated slot
  in the entire range a JTAG IDCODE can express (§4a). "Currently unused" is not available, let
  alone "permanently unused".
- **Memorable constants are the worst of all.** `0xDEADBEEF` carries manufacturer field `0x777`,
  which is an assigned member; `0x12345678` has LSB 0 and is not a legal IDCODE at all.

Only the manufacturer field `0x000` is safe, and it is safe *by construction* rather than by luck:
JEP106 identity codes run 1..126, so code 0 is not assigned today and **cannot be assigned later**.
Verified against the table: **no slot with identity code `0x00` exists in any of the 18 banks.**

### A related trap already in the tree

`src/rtl/bscan/INTERFACE_CONTRACT.md` line 188 prints the constant as `32'h1_0000_05A1`. That is a
**nine**-hex-digit (36-bit) literal; SystemVerilog truncates it to `32'h0000_05A1`, silently losing
the version nibble. The correct literal is `32'h1000_05A1`. This is already caught by
`verif/bscan/tb_bscan.sv` (mutation M9) and documented in `src/rtl/bscan/bscan_ir.sv`, but anyone
transcribing the contract by hand will reintroduce it. Whoever applies the real ID should fix the
contract text at the same time.

---

## 4. How to obtain a manufacturer ID

### The process — CONFIRMED

JEP106 §3 names the route in the standard itself:

> "Any company can be added to the list by making a request to the JEDEC office at
> http://www.jedec.org/standards-documents/id-codes-order-form or by calling (703) 907-7540."

The order form itself (read from an archived snapshot dated 2026-04-27, as `jedec.org` refuses
automated fetches) states, verbatim:

> - JEDEC item number: **4900**
> - Price: **$750 (one time fee)**
> - Delivery: **ID Code orders are fulfilled by email within 10 business days of confirmed payment.**
> - **All orders require prepayment.** [...] To pay by wire transfer, contact [the named JEDEC staff
>   member on the form] for instructions.
> - **ALL SALES ARE FINAL. JEDEC Membership is NOT required to purchase an ID Code.**
> - "You further acknowledge and agree that **the company name and ID code assigned will be included
>   in JEDEC publication JEP106 (all future versions)**."

Three consequences worth stating plainly to whoever signs it off:

1. **£/$750 one-off, no membership, no recurring cost.** This is not a barrier for a university
   group. It is a purchase order, not a standards-body application.
2. **The assignment is public and permanent.** "SoC Labs" (or whichever legal entity is named) will
   appear in every future revision of JEP106. Choose the entity name deliberately — it cannot be
   changed later and all sales are final.
3. **Lead time is 10 business days from *confirmed payment*.** Payment confirmation, not order
   placement, starts the clock.

### 4a. A hard limit to raise with JEDEC AT ORDER TIME

**CONFIRMED, and more urgent than expected.**

The IDCODE's manufacturer field packs the continuation count into **4 bits** (`[11:8]`), so a JTAG
IDCODE can only express **JEDEC banks 1 to 16**. JEP106BO already publishes banks 17 and 18, which
alias onto banks 1 and 2 respectively — an ID in those banks **cannot be represented in a JTAG
IDCODE without colliding with a bank 1 or bank 2 assignee.**

This is not hypothetical. From the table:

| JEDEC bank | populated | representable in a JTAG IDCODE? |
|---|---:|---|
| 1 – 16 | **126 / 126 each — full** | yes |
| 17 | 126 / 126 — full | **no** — aliases onto bank 1 |
| 18 | 60 / 126 — **filling now** | **no** — aliases onto bank 2 |

Every bank a JTAG IDCODE can name is already exhausted, and **JEDEC is currently issuing into bank
18**. A new assignment bought today will therefore, in all likelihood, land in a bank that this
die's IDCODE cannot express.

**Action:** when placing the order, ask JEDEC explicitly whether a bank 1–16 code can be issued, or
what they advise for JTAG IDCODE users. Do not assume the $750 buys a usable JTAG identity. If the
answer is that only bank 18 is available, keeping the manufacturer field at `0x000` may remain the
correct engineering choice even after purchase — and that reframes the whole action item.

### JEDEC membership — not required, listed only to close the question

JEDEC membership dues (archived 2026-08-03): one committee **$7,195**; two **$11,804**; three
**$17,199**; four or more **$21,588**; 50% off the first year for new member companies.
**CONFIRMED**, and **not needed** — the order form says so explicitly.

### Interim practice elsewhere in open silicon — CONFIRMED from source

Both major open-source silicon projects ship **manufacturer field `0`**:

- **OpenTitan / lowRISC**, `hw/ip/rv_dm/rtl/rv_dm.sv`: `parameter logic [31:0] IdcodeValue = 32'h 0000_0001`.
  Issue lowRISC/opentitan#490 states the intent: *"We currently use `00000001` as JTAG IDCODE for our
  system [...] If anybody builds a product out of our code, they should assign a different ID to it."*
  lowRISC later bought a real assignment and now ships `{4'd12, 7'b110_1111}` — bank 13, `0xEF`.
- **rocket-chip**, `DebugTransport.scala`: `idcodeManufId : Int, // Assigned by JEDEC`, defaulting to `0`.

`0` is the right interim choice for a precise reason: **JEP106 identity codes start at 1**, so a
manufacturer field of `0` can never collide with any present or future assignee. It is *invalid*,
not *reserved* — and that is exactly the point. OpenOCD renders it `<invalid>`, which is the honest
signal. **CONFIRMED** (JEP106 code range; OpenOCD `jep106.c`:
`if (id < 1 || id > 126) { ... return "<invalid>"; }`).

---

## 5. Exactly what changes once an ID is assigned

The IDCODE has **one source of truth and four generated consumers**. Do not edit the generated
files: `python3 scripts/gen_bscan.py --check` is a CI gate and a hand-edit is a build failure by
design.

### 5a. Sites to edit by hand

| # | File | Line | Content now | Role |
|---|---|---:|---|---|
| 1 | `Makefile` | 444 | `BSCAN_IDCODE := 0x10001001` | **the flow's entry point** — passed to `gen_pad_table.py --idcode` by the `bscan-table` target |
| 2 | `scripts/gen_pad_table.py` | 183 | `ap.add_argument("--idcode", default="0x10001001", ...)` | **the generator constant** — the fallback default; keep it in step with #1 or a table generated without the Makefile silently reverts |
| 3 | `src/rtl/bscan/pad_table.json` | 14 | `"idcode": "0x10001001"` | the committed pad table's `design.idcode`; **written by #2, read by `gen_bscan.py`** |
| 4 | `src/rtl/bscan/pad_table.json` | — | *(absent)* `design.jedec` | **the new allocation record.** Add `"jedec": {"bank": N, "code": C}` — with `C` the 7-bit code, parity stripped — and the guard derives and enforces the manufacturer field. This is the **only** way to legitimately get a non-zero field |
| 5 | `verif/bscan/tb_bscan.sv` | 70 | `localparam logic [31:0] IDCODE_INTENDED = 32'h1000_05A1;` | the RTL bench's expected value — **STALE, see §5e** |
| 6 | `verif/bscan/tb_bscan_gate.sv` | 79 | `localparam logic [31:0] IDCODE_INTENDED = 32'h1000_05A1;` | the gate bench's expected value — **STALE, see §5e** |
| 7 | `src/rtl/bscan/INTERFACE_CONTRACT.md` | §5 | updated 2026-08-19 | the contract; the 36-bit-literal trap is now called out rather than committed |
| 8 | `src/rtl/bscan/bscan_ir.sv` | 85–95 | updated 2026-08-19 | comment only |

### 5b. Sites that regenerate — never edit these

| File | What carries the ID | Produced by |
|---|---|---|
| `src/rtl/bscan/nanosoc_eth_chiplet_bscan.sv` line 110 | **the RTL parameter** `parameter logic [31:0] IDCODE_VALUE = 32'h1000_1001` | `gen_bscan.py` `render_rtl()` |
| the same file, lines 99–109 | the manufacturer-field explanation, as `//` comments | `gen_bscan.py` `idcode_notes()` |
| `sys_desc/bscan/nanosoc_eth_chiplet_pads.bsdl` line 233 | **the BSDL attribute** `IDCODE_REGISTER`, emitted as four binary field strings | `gen_bscan.py` `render_bsdl()` |
| the same BSDL, lines 220–232 | the same explanation as `--` comments, adjacent to the attribute | `gen_bscan.py` `idcode_notes()` |
| the same BSDL, `DESIGN_WARNING` and banner item 3 | the tester-visible summary | `gen_bscan.py` |

`idcode_notes()` is the single derivation behind every one of these, so the die and its description
cannot disagree about whether the number identifies anyone. **All of this prose switches
automatically** when `design.jedec` is present — there is no placeholder text left to remember to
delete.

**The RTL parameter is what silicon gets.** `ASIC/tech_wrappers/tsmc65/nanosoc_eth_chiplet_pads.v`
line 354 instantiates `nanosoc_eth_chiplet_bscan` with **no parameter override**, so the generated
default is the value that reaches the die. There is no second place to catch a mistake.

### 5c. Procedure

```
# 1. edit sites 1, 2 and add the `jedec` block (site 4) above
# 2. re-derive the pad table (this rewrites site 3):
make bscan-table            # NOTE: reads the PRE-SPLICE pad ring from commit 458d108
# 3. regenerate both outputs:
make bscan-gen
# 4. prove they agree with the table, the ring and the boundary spec:
make bscan-check
# 5. re-run the bench:
make bscan-sim
```

`gen_bscan.py` asserts `IDCODE_VALUE & 1` (1149.1 requires bit 0 = 1), asserts that its own
four-way field split recomposes to the parameter, and — via `check_idcode_manufacturer()` —
**refuses to build at all** if the manufacturer field is non-zero without a recorded allocation, or
if a recorded allocation does not pack to the field. A mistyped or invented constant is a build
failure, not a silent tapeout.

If re-running `bscan-table` is undesirable (it re-derives the whole table from a historical commit),
editing `design.idcode` in `pad_table.json` directly and running `make bscan-gen` is equivalent for
this field. Expect the SHA-256 stamped in both generated banners to change either way — the table's
hash is deliberately carried into the outputs.

### 5d. Recording an allocation, worked

JEDEC issues a **bank** and a **byte**. The byte carries JEP106's odd-parity bit in its MSB; strip
it. For lowRISC's real assignment of "bank 13, `0xEF`":

```json
"jedec": { "bank": 13, "code": 111 }        // 0xEF & 0x7F = 0x6F = 111
```

and set `BSCAN_IDCODE` so that `IDCODE[11:1] == ((13 - 1) << 7) | 0x6F == 0x66F`. The guard
recomputes this and fails if the two disagree, so the arithmetic cannot be got wrong silently.

### 5e. Outstanding — could not be applied here

`verif/` is outside this change's remit, so two benches still expect the retired value:

- `verif/bscan/tb_bscan.sv:70` and `verif/bscan/tb_bscan_gate.sv:79` both hold
  `IDCODE_INTENDED = 32'h1000_05A1`. **Tests T2 and T3 will fail until these are changed to
  `32'h1000_1001`.**
- Both benches accept a runtime override, so they can be run green immediately with
  **`+idcode=10001001`** while the one-line edits are pending.

Checked and clear: `ci/fixtures/boundary-scan/fail-vacuous-table/src/rtl/bscan/pad_table.json` also
carries the old value, but `scripts/bscan_syn_verdict.py` — the only consumer of that fixture —
never reads `idcode` and never invokes `gen_bscan.py`, so the new guard does not reach it and that
fixture still fails for the reason it is designed to test.

---

## 6. Risk of taping out with the placeholder

Ordered by how likely each is to actually bite.

**These are the risks the previous value carried. Items 1, 2 and 4 are RESOLVED by the change in
§7; item 3 is resolved for this die; item 5 stands.** They are kept because the reasoning is what
justifies not reaching for another invented number later.

1. **The die identifies itself as another company. CONFIRMED. — RESOLVED.**
   OpenOCD prints, on every scan-chain examination:
   `"JTAG tap: %s %16.16s: 0x%08x (mfg: 0x%3.3x (%s), part: 0x%4.4x, ver: 0x%1.1x)"`
   — resolving `%s` through the JEP106 table. Connect to this chiplet and the log reads
   **`mfg: 0x2d0 (Neterion Inc)`**. Every IDCODE-keyed tool (OpenOCD, UrJTAG, vendor scan-chain
   browsers, CoreSight enumerators) will attribute SoC Labs silicon to a third party, in logs that
   end up in bug reports, papers and partner hand-offs.

2. **A board tester binds the wrong BSDL. CONFIRMED as a mechanism. — RESOLVED.**
   Boundary-scan tools identify a device on the chain by its IDCODE and select a BSDL from a
   library. `0x100005A1` is a plausible-looking Neterion part number `0x0000` — it is not obviously
   junk, so nothing prompts the operator to look twice. The failure mode is a *silently wrong*
   boundary register description applied to a 76-cell chain, not a refusal to proceed.

3. **The part number was `0x0000`, which discriminates nothing. — RESOLVED for this die.**
   `part = 0x0000` meant this chiplet and any sibling die shared an identity on one scan chain. The
   part number is the vendor's own to assign and costs nothing, so it is now **`0x0001` for the
   ethernet chiplet, with `0x0002` reserved for the compute chiplet**. That reservation is recorded
   here and in the `Makefile` comment; **it still has to be applied on the compute die**, which is a
   separate repository.

4. **The assignment is permanent, so the mistake ages badly. — RESOLVED.**
   If SoC Labs later buys a real ID, parts already in the field keep claiming to be Neterion. There
   is no errata mechanism for a hard-wired IDCODE.

5. **Enforcement — UNCONFIRMED.** Whether anything *enforces* manufacturer IDs (a conformance gate,
   a JEDEC term, trademark) could not be established; JEDEC's order-form terms say nothing about
   misuse. Treat the constraint as convention plus tooling correctness, not as a legal exposure —
   and note that no documented case of a *JTAG* IDCODE collision causing a field failure was found
   (see §8).

### Precedent that the registry does get abused, and what it costs

**SECONDARY.** In SPI-NOR ID space — the same JEP106 registry, different consumer — collisions are
common enough that the Linux MTD subsystem carries a *dedicated collision-disambiguation driver*.
From that series: *"Some manufacturers completely ignore the manufacturer's identification code
standard (JEP106) [...] Boya ignores the continuation scheme and its ID collides with the
manufacturer defined in bank one: Convex Computer."* Others document Winbond parts shipping under
Nexcom's `0xEF` and Micron parts identifying as STMicro. The lesson is not that JTAG will fail the
same way — it is that once a wrong ID is in silicon, the cost lands on *downstream tool maintainers*
and is paid forever.

---

## 7. What was done, and what is left

### (a) DONE 2026-08-19 — the squat is removed

`BSCAN_IDCODE` is now **`0x10001001`**: version `0x1`, part `0x0001`, **manufacturer `0x000`**,
bit 0 = 1. The die no longer claims to be Neterion; it declares itself unidentified.

Why `0x000` specifically, rather than another unused-looking value:

- **It impersonates nobody, permanently.** JEP106 identity codes run 1..126, so code 0 is not
  assigned and cannot become assigned. Verified: no slot with identity `0x00` exists in any of the
  18 published banks.
- **It is self-announcing at the strongest level a tool offers.** OpenOCD range-checks
  (`id < 1 || id > 126`) *before* the table lookup, so it reports `(mfg: 0x000 (<invalid>))` —
  `<invalid>`, not the softer `<unknown>` it gives an unpopulated-but-legal slot.
- **It is the convergent convention** for exactly this situation: OpenTitan, rocket-chip,
  pulp-platform `riscv-dbg`, Hazard3 and lowRISC's sonata-system all ship a null manufacturer field
  while unallocated. RISC-V's `mvendorid` rule — "a value of 0 can be returned to indicate a
  non-commercial implementation" — is the same instinct.
- **There was no alternative.** §3 and §4a: every bank a JTAG IDCODE can express is 126/126 full.

### (b) DONE 2026-08-19 — the defect is now structurally unrepeatable

`scripts/gen_bscan.py` gained `check_idcode_manufacturer()`, which **fails the build** unless
either the manufacturer field is `0x000`, or the pad table records the real JEDEC bank and code and
the field packs from them exactly. Inventing a second number is no longer something a person can do
by editing a constant — and the generator's `--check` gate is already wired into `make bscan-check`.

### (c) OPEN — buy an ID, but ask the bank question first

$750, no membership, ~10 business days, JEDEC item 4900 (§4). **Before paying, resolve §4a**: banks
1–16 are full and JEDEC is issuing into bank 18, which a JTAG IDCODE cannot express. An ID that
cannot go in this die's IDCODE is still useful for other purposes, but it would not close this item
— so ask before ordering, not after.

### (d) OPEN — apply the value to the two benches

See §5e. Two `verif/` benches still expect the retired value and need a one-line change each; they
run green in the meantime with `+idcode=10001001`.

### (e) OPEN — the compute chiplet

Part number `0x0002` is reserved for it here, but the reservation has to be applied in its own
repository, and its IDCODE should be checked for the same squat.

---

## 8. What could not be established

Stated explicitly so that nobody re-derives these as if they were settled.

- **Real-world lead time.** No first-hand account (forums, mailing lists, blogs) of an organisation
  actually applying and reporting elapsed time or friction was found. **The 10-business-day figure
  is JEDEC's own claim and is uncorroborated.**
- **The IEEE clause reserving the all-ones / `0b0000_1111111` manufacturer value.** IEEE 1149.1 is
  paywalled and its text could not be obtained. That such values are unreachable is *derivable* from
  JEP106 (`0x7F` is the continuation escape and so can never be an identity) plus the IDCODE field
  layout, and that derivation is what is relied on above. **Do not cite an IEEE clause number for
  it.**
- **A documented JTAG-IDCODE collision causing a specific field failure.** None found. The
  collisions in §6 are SPI-NOR `RDID`. Say "no documented case found", not "no such case exists".
- **Behaviour of specific commercial tools** (Vivado, Quartus, TRACE32, J-Link, UrJTAG) on an
  unknown or mismatched IDCODE. Only OpenOCD's behaviour was verified from source.
- **Whether the entity to be named should be "SoC Labs", the University of Southampton, or another
  legal entity.** This is a decision for whoever holds the budget, and it is irreversible.
- **JEP166F** ("JC-42.6 Manufacturer ID", for LPDDR / Wide-IO) is a *separate* registry with its own
  order route; its price could not be confirmed. It is not relevant to JTAG.

## Provenance

JEP106AY (Feb 2019) normative text; JEDEC ID-code order form and membership-dues pages (archived
snapshots 2026-04-27 and 2026-08-03 — `jedec.org` returns 403 to automated fetches); Arm Cortex-M3
TRM Table 12-17; OpenOCD sources (`src/helper/jep106.{c,h}`, `src/jtag/core.c`) and its JEP106BO-
aligned manufacturer table; OpenTitan and rocket-chip sources; Linux MTD "Manufacturer ID
collisions" series. Field decode of `0x100005A1` and the `Neterion Inc` lookup were computed and
re-verified locally against four known-good controls.
