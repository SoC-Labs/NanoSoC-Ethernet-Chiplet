# Peer-aperture programming — how die A writes `shared_sram_0` on die B

**Question answered:** exactly how a CPU on die A writes `shared_sram_0` (and the
IPC mailbox) on die B through TideLink, and precisely how the TideLink address
translator must be programmed to make it work.

**Method:** RTL is authoritative. Every structural claim below carries a
`file:line`. Where a TideLink doc disagrees with the RTL, the RTL wins and the
divergence is called out. Nothing here is a guessed bit position.

**Scope note:** this is a *design/research* document. No RTL is produced. The
register sequences are what the G2 bring-up firmware (or `pynq_host` bring-up
script) must issue; none of the existing bring-up automation does this yet
(see Open Questions).

---

## 0. TL;DR

* The translator is **not** a fixed offset and **not** a windowed segment table
  in the active build. It is an **8-rule CAM** that matches and replaces the
  **upper address byte only** (`addr[31:24]`), passing `addr[23:0]` through
  unchanged. It lives in the **AHB domain** on die A's outbound (`ahb_sub`) path,
  *before* XHB500. `tl_addr_trans_cam.sv:50-93`.
* It has **one active channel** (`NUM_CHANNELS=1`), **8 rules**, granularity
  **16 MB** (one `addr[31:24]` value per rule). `tidelink_top.sv:1877-1878`.
* Its APB config bank is at **`0x2E034000`** (channel 0). Confirmed — see §3.
* To map die A's peer aperture `0x2F000000..0x2FFFFFFF` onto die B's
  `shared_sram_0` at `0x2D000000`, the whole programming is **three writes**:
  `BASE_OFFSET=0`, `RULE_0={replace=0x2D, match=0x2F, enable=1}=0x002D2F01`,
  `CTRL=1`. See §4.
* **Hard constraint:** a single 16 MB peer aperture (one source upper byte)
  can reach **exactly one** remote 16 MB region. Die A **cannot** reach both
  `shared_sram_0` (`0x2D`) and `ipc_mailbox_0` (`0x23`) from the one `0x2F`
  aperture with this CAM. This breaks G2 assertion 2 as written. See §5.

---

## 1. The traced path, with the address at every hop

Die A CPU issues a word write to `0x2F000000 + X` (X in `0..0xFFFFFF`).

| # | Hop | Module / port | Address carried | Evidence |
|---|-----|---------------|-----------------|----------|
| 1 | CPU0/CPU1/DMA/DAP write, top matrix decodes the 32 MB D2D window onto the initiator port | `nanosoc_multicore_soc.d2d_ahb_m_*` | `0x2F000000+X` | `D2D_PORT.md:19,88`; window `0x2E..0x2F` |
| 2 | Wrapper sub-decode: `haddr[24]==1` ⇒ peer aperture; asserts `hsel_peer`; **haddr fans out unchanged** | `chiplet_d2d_decode` → `hsel_peer` | `0x2F000000+X` | `chiplet_d2d_decode.sv:43,81,108,116`; header §CONSTRAINT `:51-53` |
| 3 | Enters TideLink's transparent-bridge subordinate | `tidelink_top.ahb_sub_*` (`ahb_sub_haddr`) | `0x2F000000+X` | `tidelink_top.sv:139`; README `:81` |
| 4 | **Address translator (CAM), combinational** | `u_addr_translator.chp0_ahb_haddr_i → chp0_ahb_haddr_o` | in `0x2F000000+X` → **out `0x2D000000+X`** | `tidelink_top.sv:1896-1897`; CAM `tl_addr_trans_cam.sv:51,59,76,88` |
| 5 | Pipeline reg, then presented to XHB500 AHB→AXI | `translated_sub_haddr → pipe_haddr_r → xhb_sub_haddr → u_xhb_sub.haddr` | `0x2D000000+X` | `tidelink_top.sv:1104,1138,1156,1703` |
| 6 | XHB500 AHB→AXI (32-bit AXI addr), Wlink AXI2WL, SERDES PHY | `u_xhb_sub` (`xhb500_ahb_to_axi_bridge_chiplet_slv`) → Wlink | `0x2D000000+X` (AXI AW) | `tidelink_top.sv:1695`; `deps/xhb500/configs/cfg_xhb_ahb_to_axi.cfg:47` (ADDR_WIDTH 32) |
| 7 | *link* → die B Wlink WL2AXI, die B XHB500 AXI→AHB | die B `u_xhb_mng` (`xhb500_axi_to_ahb_bridge_chiplet_mst`) | `0x2D000000+X` | `tidelink_top.sv:1782` |
| 8 | Emerges on die B's manager port (**not** translated on this side) | die B `tidelink_top.ahb_mng_*` (`ahb_mng_haddr`) | `0x2D000000+X` | `tidelink_top.sv:1846`; `INTEGRATION_GUIDE.md:133` |
| 9 | Becomes die B's 6th matrix initiator | die B `nanosoc_multicore_soc.d2d_ahb_s_*` | `0x2D000000+X` | `D2D_PORT.md:20`; `sys_desc/...:302` |
| 10 | Matrix passthrough initiator, confined target list | die B `d2d_m` → `shared_sram_0` | `0x2D000000+X` ⇒ SRAM hit | `sys_desc/...:2383-2387` |

**Why hop 4 is load-bearing.** Die B's `d2d_m` initiator reaches **only**
`shared_sram_0` (`0x2D000000`) and `ipc_mailbox_0` (`0x23000000`); everything
else takes a DECERR from the top-level default slave
(`D2D_PORT.md:95-101`, `sys_desc/nanosoc_multicore_soc.yaml:2383-2387`, target
sizes `:2167,2169`). Die A's peer aperture is `0x2F` (`chiplet_d2d_decode.sv:81`).
Die A's *own* `0x2D` is die A's *own* shared SRAM, so aliasing is impossible —
the address **must be actively rewritten** from `0x2F` to `0x2D` on die A before
it crosses. Only the CAM does that. If the CAM is left at its reset state
(disabled, identity), the far die sees `0x2F000000+X`, which is outside
`d2d_m`'s target list ⇒ **DECERR**.

The translator is **only on the outbound (`ahb_sub`) side** — the inbound
`ahb_mng` path is untranslated (`chp1` is tied off, `tidelink_top.sv:1900-1901`).
So the rewrite happens once, on the sender.

---

## 2. Translator architecture (Q1) and registers (Q2)

### Architecture

* **CAM, not fixed-offset, not windows.** `tidelink_addr_translator.sv` (header
  `:1-14`) instantiates `tl_addr_trans_regs` + `tl_addr_trans_cam` per channel.
  A parallel segment-table alternative (`tidelink_addr_translation.sv`) exists
  but is **explicitly NOT instantiated** (`tidelink_addr_translation.sv:1-11`).
* **Channels:** parameter `NUM_CHANNELS` default 2, but `tidelink_top`
  instantiates it with **`NUM_CHANNELS=1`** (`tidelink_top.sv:1877-1878`). Only
  channel 0 exists; channel 1's register bank returns `pslverr`
  (`tidelink_addr_translator.sv:97-102,196-205`).
* **Rules per channel:** `NUM_RULES` default **8** (`tidelink_addr_translator.sv:33`).
* **Granularity: 16 MB.** The CAM matches and replaces `addr[31:24]` only; the
  low 24 bits always pass through **from the raw input** `addr_i[23:0]`
  (`tl_addr_trans_cam.sv:59`). One rule = one 16 MB-aligned source→dest mapping.
* **Domain: AHB.** It transforms `ahb_sub_haddr` (a 32-bit AHB address) *before*
  the XHB500 AHB→AXI bridge (`tidelink_top.sv:1896-1897,1703`). It is *not* in
  the AXI domain and *not* on the far side.
* **Reset domain:** `CLK=hclk`, `RESETn=hresetn` (`tidelink_top.sv:1880-1881`).
  Registers reset on **`hresetn`** (`tl_addr_trans_regs.sv:96-98,141-143`) — i.e.
  a warm system reset clears the mapping. This is *not* a POR-only survivor like
  `ROLE_CFG`; **it must be reprogrammed after every `hresetn`.**

### Exact CAM operation (`tl_addr_trans_cam.sv`)

```
addr_norm        = addr_i - base_offset              ; :51  (full 32-bit subtract)
addr_upper       = addr_norm[31:24]                  ; :54
addr_o[23:0]     = addr_i[23:0]                       ; :59  (RAW low bits, not normalised)
for k in 0..7:  match[k] = rule_enable[k] & (rule_match[k] == addr_upper)  ; :69
if global_enable and any match:
    addr_o[31:24] = rule_replace[<lowest matching k>] ; :82-92  (first/lowest index wins)
else:
    addr_o[31:24] = addr_upper                        ; :83  (identity of the *normalised* byte)
```

Two subtleties that matter:
1. On a **match**, the output low 24 bits are `addr_i[23:0]` (the aperture
   offset), *not* `addr_norm[23:0]`. So the offset within the destination
   region equals the offset within the aperture.
2. On **no match / disabled**, the identity byte is `addr_norm[31:24]`
   (base-offset-subtracted). With `base_offset=0` this equals `addr_i[31:24]`,
   i.e. pure passthrough.

### Register bank (`tl_addr_trans_regs.sv`, per channel)

| Word offset | Name | Access | Fields | Evidence |
|---|---|---|---|---|
| `0x000` | `BASE_OFFSET` | RW | `[31:0]` subtracted from input before matching | `tl_addr_trans_regs.sv:94-107`; rdl `:56` |
| `0x004` | `CTRL` | RW | `[0]` `global_enable` (0=identity passthrough) | `tl_addr_trans_regs.sv:113-124`; rdl `:73` |
| `0x010` | `RULE_0` | RW | `[0]` enable, `[15:8]` match byte, `[23:16]` replace byte; `[7:1]`,`[31:24]` reserved | `tl_addr_trans_regs.sv:128-157`; rdl `:102-125` |
| `0x014..0x02C` | `RULE_1..RULE_7` | RW | same layout; **rule 0 = highest priority** | `tl_addr_trans_regs.sv:144`; cam `:82-92` |
| `0x030..0xFCC` | (gap) | RO | reads `0xCAFECAFE` | `tl_addr_trans_regs.sv:190` |
| `0xFD0..0xFDC` | `PIDR4..7` | RO | all `0x00` | `tl_addr_trans_regs.sv:178-181`; rdl `:155-165` |
| `0xFE0..0xFEC` | `PIDR0..3` | RO | `0x59,0x16,0x15,0x00` | `tl_addr_trans_regs.sv:182-185`; rdl `:167-177` |
| `0xFF0..0xFFC` | `CIDR0..3` | RO | `0x50,0x51,0x4C,0x54` | `tl_addr_trans_regs.sv:186-189`; rdl `:179-189` |

A single mapping entry (a rule) therefore consists of **{enable, 8-bit match,
8-bit replace}** — *no* mask, *no* remap-base beyond the 8-bit replace, and
**no security/valid field beyond `enable`**. There is no per-rule security bit
in the RTL (the RDL has none either). Region size is fixed at 16 MB by the
byte-granularity; there is no size/mask field.

> **Doc divergence (RTL wins):** `REGISTER_MAP.md:543-544` cites the routing at
> `tidelink_top.sv:667 / :1741`. In the current RTL the decode is at
> `tidelink_top.sv:683-690` and the instantiation at `:1877`. The behaviour it
> describes is correct; only the line numbers are stale.

---

## 3. Absolute CPU-visible addresses (Q3) — **`0x2E034000` CONFIRMED**

The APB bank decode chain, end to end:

1. Wrapper decodes `0x2E030000` (32 KB) to `tidelink_top.apb_*` via
   `cmsdk_ahb_to_apb #(.ADDRWIDTH(15))`, so `apb_paddr[14:0] = haddr[14:0]`
   within that region (`README.md:79`; `D2D_PORT.md:36-38,51-52`).
2. Inside `tidelink_top`, `paddr[14:13]` selects the bank
   (`tidelink_top.sv:683-690`, `REGISTER_MAP.md:11-18`):
   * `00` → Wlink regs → `0x2E030000`
   * `01` → TideLink config/PTP/role → `0x2E032000`
   * `10` → **address-translator config → `0x2E034000`**
   * `11` → reserved
   `apb_sel_addr_xlat = apb_psel & apb_paddr[14] & !apb_paddr[13]`
   (`tidelink_top.sv:690`).
3. The translator receives `chp_adr_paddr = {3'b000, apb_paddr[12:0]}`
   (`tidelink_top.sv:1884`), and selects the channel with
   `chp_adr_paddr[15:12]` (`tidelink_addr_translator.sv:89`). That equals
   `{3'b000, apb_paddr[12]}`, so **channel 0 = `apb_paddr[12]==0`**, i.e. the
   `0x4000..0x4FFF` half of the bank. Channel 1 (`0x5000..0x5FFF`) is present
   in the decode but returns `pslverr` because `NUM_CHANNELS=1`.
4. Within a channel, the register word address is `paddr[11:2]`
   (`tl_addr_trans_regs.sv:88-89`).

So **channel 0 lives at `0x2E034000..0x2E034FFF`**, and every register is:

| Register | Absolute address |
|---|---|
| `BASE_OFFSET` | `0x2E034000` |
| `CTRL` | `0x2E034004` |
| `RULE_0` | `0x2E034010` |
| `RULE_1` | `0x2E034014` |
| `RULE_2` | `0x2E034018` |
| `RULE_3` | `0x2E03401C` |
| `RULE_4` | `0x2E034020` |
| `RULE_5` | `0x2E034024` |
| `RULE_6` | `0x2E034028` |
| `RULE_7` | `0x2E03402C` |
| `PIDR4..7` | `0x2E034FD0 / FD4 / FD8 / FDC` |
| `PIDR0..3` | `0x2E034FE0 / FE4 / FE8 / FEC` |
| `CIDR0..3` | `0x2E034FF0 / FF4 / FF8 / FFC` |

(The `0x2E034xxx` = `0x5000..0x5FFF` mirror at `0x2E035xxx` is channel 1 and
DECERRs/pslverrs — do not use it.)

The task's stated `0x2E034000` is **confirmed correct**.

---

## 4. The mapping sequence for G2 (Q4) — 3 writes

Goal: die A's `0x2F000000..0x2FFFFFFF` → die B's `0x2D000000` (16 MB, 1:1).

```
write(0x2E034000, 0x00000000)   # BASE_OFFSET = 0  (match the raw upper byte, no normalisation)
write(0x2E034010, 0x002D2F01)   # RULE_0: enable=1, match=0x2F, replace=0x2D
write(0x2E034004, 0x00000001)   # CTRL.global_enable = 1  (arm LAST)
```

Field derivation of `RULE_0`:
* `[0] enable   = 1`            → `0x00000001`
* `[15:8] match = 0x2F`         → `0x00002F00`  (die A aperture upper byte, `chiplet_d2d_decode.sv:81`)
* `[23:16] replace = 0x2D`      → `0x002D0000`  (die B `shared_sram_0` upper byte, `sys_desc:2169`)
* OR = **`0x002D2F01`**

Verification against the CAM (`tl_addr_trans_cam.sv`): input `0x2F000000+X`,
`base_offset=0` ⇒ `addr_upper=0x2F` ⇒ rule 0 matches ⇒
`addr_o = {0x2D, addr_i[23:0]} = 0x2D000000+X` for all `X∈[0,0xFFFFFF]`. Full
16 MB, one-to-one.

Notes:
* Program `CTRL` **last** so no half-configured rule is ever armed. All three
  are 32-bit word writes (`pstrb=0xF`).
* This must be done on **both dies** for bidirectional traffic — die A maps its
  `0x2F` to die B's `0x2D` for A→B; die B independently maps *its* `0x2F` to die
  A's `0x2D` for B→A. The map is symmetric only because the two SoCs are
  identical.
* Re-issue after any `hresetn` (§2, reset domain).
* `BASE_OFFSET` could equivalently be `0x2F000000` with `match=0x00` — the CAM
  would normalise `0x2F→0x00` then match `0x00`. Both are valid; `BASE_OFFSET=0`
  + `match=0x2F` is the simplest and is used above.

---

## 5. The IPC mailbox and the one-remote-region constraint (Q5)

**Stated plainly: a single 16 MB peer aperture cannot reach two disjoint remote
16 MB regions through this CAM. Die A can map its `0x2F` aperture to EITHER
`shared_sram_0` (`0x2D`) OR `ipc_mailbox_0` (`0x23`) — not both at once.**

Why the 8 rules do not help:
* The aperture `0x2F000000..0x2FFFFFFF` is exactly one `addr[31:24]` value
  (`0x2F`). With `base_offset=0`, **every** address in the aperture normalises
  to the same `addr_upper=0x2F`, so only the single rule whose `match=0x2F`
  ever fires (`tl_addr_trans_cam.sv:69,82-92`). The other 7 rules are dead for
  this aperture. Multiple rules are only useful when the aperture spans multiple
  upper bytes (aperture > 16 MB).
* The `base_offset` borrow trick cannot rescue it. To split the aperture you'd
  set `base_offset` so a subtraction borrow produces two different normalised
  upper bytes across the window — but that boundary is power-of-two aligned
  (e.g. 8 MB), and because the output low 24 bits are the **raw** aperture
  offset (`:59`), the upper half of the aperture maps to `0x23_800000`, not
  `0x23_000000`. The mailbox base is not reachable that way. Worse, the mailbox
  (a 2×4-word doorbell, `sys_desc:2167` desc) needs aperture offsets near 0,
  which are the *same* offsets shared SRAM needs at its base — a direct
  conflict. No `base_offset` value resolves it.

**This collides with the G2 plan.** `docs/G2_PAIR_SIM.md:23-27` asserts *both*
(1) CPU0 on die A writes `shared_sram_0` on die B, **and** (2) a write to
`ipc_mailbox_0` on die A raises `doorbell_irq` on die B. As written, assertion 2
means writing die B's `ipc_mailbox_0` at `0x23` **through the data plane**
(peer aperture → `ahb_mng` → `d2d_m` → `ipc_mailbox_0`). With one `0x2F`
aperture mapped to `0x2D`, assertion 2 is unreachable.

Options to record (each is a chiplet-level decision, not a firmware tweak):

* **(A) Two source apertures.** Give the D2D window a second 16 MB peer slot
  (a second `addr[31:24]`, e.g. also expose `0x2E`'s spare or claim another
  `0x2x` byte) and add a second CAM rule `{match=<byte2>, replace=0x23}`. Cost:
  the top matrix is already **16/16 full** (`D2D_PORT.md:80`), and CPU0 only
  sees `0x20..0x2F` (`D2D_PORT.md:70-76`) — so this needs a matrix re-plan or
  sub-decode behind the existing D2D slot, not just a translator rule.
* **(B) Use TideLink's own doorbell, not the SoC mailbox.** TideLink already has
  a native cross-die doorbell over the FC sideband: die A writes `DOORBELL`
  (`0x2E032014`), the returner ships it, die B raises `doorbell_irq`
  (`REGISTER_MAP.md:69,96`; returner path §7 below). This satisfies the *intent*
  of G2 assertion 2 (a cross-die doorbell interrupt) without touching the SoC
  `ipc_mailbox_0`. But it is a **different mechanism and a different IRQ source**
  than "write `0x23` → `doorbell_irq`", so the assertion text must change and the
  firmware contract for the mailbox data (the 2×4-word payload) is *not* carried.
* **(C) Time-multiplex the single rule** (reprogram `RULE_0.replace` between
  `0x2D` and `0x23` around each mailbox access). Racy, serialises the data
  plane, and needs a lock; not recommended, recorded for completeness.

**Recommendation to record:** option (A) is the only one that preserves both the
data plane *and* the SoC mailbox semantics; it is a change to the SoC D2D window
map, not to TideLink. Until it is taken, the G2 sim can prove assertion 1
(shared SRAM) *or* a redefined assertion 2 (option B doorbell), not both
literally as `G2_PAIR_SIM.md` states today.

---

## 6. Full ordered bring-up before a peer write works (Q6)

From `INTEGRATION_GUIDE.md:256-283`, rebased from the reference map
(`0x4403_xxxx` TideLink / `0x4403_0xxx` Wlink) onto the chiplet
(`0x2E03_2xxx` / `0x2E03_0xxx`). Do this on **both dies**.

| Step | Action | Absolute chiplet address | Value / check | Source |
|---|---|---|---|---|
| 1a | (optional) override role if not using strap: `ROLE_CFG[0]` | `0x2E032084` | 0=master / 1=slave | `INTEGRATION_GUIDE.md:263`; `REGISTER_MAP.md:181` |
| 1b | Latch role: `ROLE_CFG[1]=1` — releases Wlink POR, starts training | `0x2E032084` | write `0x2` (or `0x3` for slave) | `INTEGRATION_GUIDE.md:263`; `REGISTER_MAP.md:182` |
| 1c | Set `PAIR_BASE_ADDR` to peer's TideLink base | `0x2E032000` | `0x2E032000` (see §7) | `INTEGRATION_GUIDE.md:264`; `REGISTER_MAP.md:64` |
| 2 | Calibrate: poll `SWI_LANE_STATUS` | `0x2E032108` | `[7:0]=0xFF`, `[15:8]=0x00`, `[16]=1` | `INTEGRATION_GUIDE.md:266-268` |
| 3a | Drop training mode | `0x2E032100` | write `0x0` | `INTEGRATION_GUIDE.md:269-270` |
| 3b | Cycle `WL_EnableReset` (Wlink 0x208) | `0x2E030208` | `0x00027F08 → 0x00027F00 → 0x00027F07`, ≥5 ms/≥5 µs apart | `INTEGRATION_GUIDE.md:270-272` |
| 4 | Verify credit handshake: `SWI_LANE_STATUS[23]`=1 and `PAIR_CREDIT_COUNTER`≠0 | `0x2E032108`, `0x2E032028` | both sides | `INTEGRATION_GUIDE.md:273-274` |
| 5 | **Program the address translator (§4)** | `0x2E034000/010/004` | `0`, `0x002D2F01`, `1` | this doc |
| 6 | Peer write | `0x2F000000+X` (data), never `0x2E000000` TX aperture until link verified | reaches die B `0x2D000000+X` | `INTEGRATION_GUIDE.md:275-277` |

Ordering notes:
* Steps 1–4 are the link bring-up; step 5 (translator) can be done any time
  after `hresetn` and is independent of link state, but the **peer write in
  step 6 will DECERR on the far die until step 5 has run** — so step 5 must
  precede any real traffic.
* **`ROLE_CFG` survives `hresetn`** (POR-only reset, `REGISTER_MAP.md:154-157`),
  but the **translator does not** (§2). After a warm reset you may skip 1–4 but
  must repeat step 5.
* On the FPGA pair, `bringup_pair_converge.sh` automates steps 1–2 and
  `sw_coord_autocal_region8.sh` adds step 3 (`INTEGRATION_GUIDE.md:279-280`) —
  **neither programs the translator (step 5).** That step is currently unowned.
* The Tier-2 hardening shim intercepts writes to Wlink `0x208`: it force-holds
  `swi_enable[0]=1` and blocks `swreset[3]` (`tidelink_top.sv:1920-1960`). The
  `0x00027F0x` values above are still what firmware writes; the shim only
  guarantees bit 0 stays 1 and bit 3 never reaches Wlink.

---

## 7. `TIDELINK_PAIR_BASE` / `PAIR_BASE_ADDR` (Q7)

**What it is.** A parameter (`tidelink_top.sv:53-54`, default `'0`) that sets the
reset value of the runtime `PAIR_BASE_ADDR` register (`0x2E032000`;
`fifo/tidelink_apb_regs.sv:226`, write-once-lockable `:236`). It is consumed by
the **returner** to form the target addresses of credit-return / doorbell-response
/ doorbell packets (`fifo/tidelink_fifo.sv:181,193-196`):

```
PAIR_RELEASED_CREDITS_ADDR   = pair_base_addr + 0x20   ; fifo/tidelink_fifo.sv:194
PAIR_DOORBELL_RESPONSE_ADDR  = pair_base_addr + 0x24   ; :195
PAIR_DOORBELL_ADDR           = pair_base_addr + 0x14   ; :196
```

It is **unrelated to the peer-aperture data plane** — that path uses the CAM
(§4), not `PAIR_BASE_ADDR`. The returner is a control-plane master whose writes
are **intercepted internally by the FC adapter and shipped as FC sideband
packets**, *not* routed out `ahb_mng` (`tidelink_top.sv:1214,1282,1306`;
"routed to FC adapter, NOT external bus" `:1214`). So `PAIR_BASE_ADDR` does
**not** require die B's `d2d_m` to reach `0x2E` — the credit loop never touches
the SoC matrix. (This is what lets the confined `d2d_m` target list coexist with
credit return.)

**What it should be in our chiplet:** `0x2E032000` — die B's TideLink config
bank base, per the documented semantics and step 1c above.

**What actually breaks if left at 0 — honest RTL reading:** in the *current*
RTL, **nothing functional in this address map.** The FC adapter ships only
`rtn_haddr[13:0]` in the sideband packet (`tidelink_fc_adapter.sv:394,414`), and
the receiver consumes only `rx_addr_offset[APB_ADDR_W-1:0] = [11:0]` for the
config write (`tidelink_fc_adapter.sv:607,698`, `APB_ADDR_W=12`). Because both
`0x2E032000` and `0x00000000` have **low 12 bits = 0**, the delivered offsets are
identical (`0x014/0x020/0x024`) either way, and they decode to the same peer
registers (region 1/0 slots). So credit-return and doorbell still close with
`PAIR_BASE=0` **in this specific map**.

Nonetheless, **set it to `0x2E032000`**:
* it is the documented contract (`REGISTER_MAP.md:64`, `INTEGRATION_GUIDE.md:264`)
  and matches every bring-up script's assumption;
* it is future-proof: any widening of `APB_ADDR_W`, or any change that makes the
  receiver use more than `[11:0]`, or a peer whose TideLink bank is not
  `0x..02000`-aligned, would make the high bits load-bearing and a stale `0`
  would then silently mis-route the credit loop (link stalls once initial
  credits drain — a nasty, intermittent-looking failure).

> **Doc vs RTL note:** the docs treat `PAIR_BASE_ADDR` as semantically "the
> peer's full APB base." The RTL only transports `[13:0]` and decodes `[11:0]`.
> Both are recorded; the RTL is why `0` happens to work today.

---

## 8. Open questions (could not fully resolve from the RTL)

1. ~~**Does the full 32-bit AXI address survive the Wlink SERDES?**~~
   **RESOLVED 2026-07-10 — yes, it survives.** The packetiser was opened.

   TX (`deps/axi-chiplet-controller/logical/wlink/AXI4ToWlink.v:395-399`):
   ```verilog
   axi_tgt_aw_bits_addr[35:0] = auto_axi_tgt_in_aw_bits_addr;  // 36-bit AXI addr
   aw_tgt_aw_addr[63:0]       = {28'd0, axi_tgt_aw_bits_addr}; // zero-extend to 64
   ```
   The address rides a **64-bit field** inside a 101-bit `app_data` word
   (`WlinkGenericFCSM wlink_axiawFC`, `AXI4ToWlink.v:529`) — no link-level
   truncation.

   RX (`AXI4ToWlink.v:401,450`):
   ```verilog
   aw_ini_aw_addr[63:0]      = wlink_axiawFC_io_app_l2a_data[88:25]; // FROM THE PACKET
   axi_ini_aw_bits_addr[35:0]= aw_ini_aw_addr[35:0];
   ```
   Reconstructed from the packet, **not** from a base/constant register. Hence
   `ahb_mng_haddr[31:24] = 0x2D` on die B. Chisel (`AXI.scala:442-471`) agrees
   with the generated Verilog, and `AXI4ToWlink` is not shadowed by any copy in
   `src/rtl/local_overrides/`.

   Two things this does **not** say. The peer aperture uses the **AXI** path
   (AW channel, `WlinkGenericFCSM`); the doorbell's FIFO/returner *native* path is
   a different mechanism, and the `WlinkGenericFCReplayAddrSync_18` reset-skew
   hazard lives on the a2l replay path, not on AW. And it remains worth probing
   far-die `ahb_mng_haddr[31:24]` against post-CAM `ahb_sub_haddr[31:24]` once the
   pair sim exists — RTL reading is not a simulated transaction.

   **Consequence for §5.** `ipc_mailbox_0` is unreachable through the aperture
   because **this SoC exposes only one local aperture byte (`0x2F`)**, and a CAM
   rule maps one local byte to one remote byte. It is *not* because the CAM is
   limited (it has 8 rules) and *not* because the link drops `addr[31:24]`.
   Reaching the mailbox needs a **second local aperture byte**, which the top
   matrix cannot spare today (16/16 targets used; CPU0's only window is
   `0x20`–`0x2F`, and `0x2E` is the TideLink control sub-decode).

2. **There is no existing test that programs this translator.** The one
   peer-aperture env (`cocotb/debug/tidelink_peer_aperture/`) is an
   **aspirational guard** for a not-yet-implemented peer-register ACL
   (`tidelink_peer_acl.sv`), and its own docstring says it "fails LOUDLY" until
   that lands (`test_eye_peer_aperture_drain.py:6-10`). Its `tb_top.sv` never
   writes the translator bank (`0x4000..0x5FFF`) and relies on the reset-state
   passthrough with symmetric `0x40↔0x44` windows. So the `0x2F→0x2D` mapping
   and the whole cross-die data plane are **un-exercised**; §4 is the first
   thing to encode into the G2 env, and it should be **mutation-checked**
   (disable `CTRL` ⇒ far-side DECERR) the way `soc_d2d_loopback::inbound_is_confined`
   was.

3. **The IPC-mailbox reachability decision (§5) is unresolved at the chiplet
   level.** Which of options (A)/(B)/(C) is taken changes the SoC D2D window map
   and the text of `G2_PAIR_SIM.md` assertion 2. This needs an owner decision,
   not more RTL reading.

4. **`ahb_mng` HPROT / hmastlock signature adaptation** (`README.md:99-100`,
   `D2D_PORT.md:48-49`) is asserted "trivial" but not shown wired here; if the
   wrapper mis-maps `hprot[6:0]→[3:0]` it could disturb cacheability/priv bits on
   the inbound write. Out of scope for the address trace, but it sits on the same
   hop 8→9 and should be eyeballed when the wrapper RTL lands.

5. **Reset-domain interaction with a running link.** The translator clears on
   `hresetn` while `ROLE_CFG` and the link survive it. A warm `hresetn` that
   reprograms nothing would leave the link up but the translator disabled ⇒ the
   first peer write silently DECERRs. Whether the G2/bring-up flow ever issues a
   lone `hresetn` (vs. always POR) determines if this is a live hazard. Not
   determinable from RTL alone; needs the board reset topology.

---

*A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license. Copyright 2026, SoC Labs (www.soclabs.org).*
