# System-level bug report — <one-line title>

> The rig side of the loop. Fill this from an ILA/OBS/rig capture, then feed it to the diagnosis:
> `/diagnose-bug` (or `Workflow({name:"diagnose-bug", args:{reportPath:"<this file>"}})`).
> The workflow runs everything downstream of the capture — it does NOT touch the rig.
> Rule of the house: **every line is a measured value, not an inference.** If it's inferred, label it.

## 1. Provenance (so the diagnosis trusts the capture)
- **Build / md5:** <die_a bits md5, die_b bits md5; source commit; any `ifdef` defines that matter>
- **Rig config:** die_a = <board/ip>, die_b = <board/ip>; roles/flip; eye/link state at capture (fcsm, cal, cr_seen)
- **Capture modality:** <JTAG ILA / OBS_AXI register / ssh readback>; core-vs-nocore control? probe count + ILA_PROBE_OK?
- **Liveness check:** <the probe that proves the capture is live — e.g. a counter spanning distinct values — NOT all-zeros>

## 2. Trigger
- **Kind:** <single inject / soak / spontaneous>
- **Inject params (if any):** node, byte, bit, address, payload
- **Symptom:** <rc=124 / PING_DOWN / ssh timeout / bus-error>; which die wedged; recoverable how (POR?)

## 3. FROZEN SIGNAL STATE (the core — this is what the diagnosis reasons over)
| signal | value | meaning (as you read it) |
|---|---|---|
| `<witness signal>` | `<value>` | **← the wedge witness (its stuck state IS the hang)** |
| `<sig>` | `<value>` | |
| `<sig>` | `<value>` | |

- **Raw word(s) / CSV path:** <the unclassified numbers, so the diagnosis can decode independently>

## 4. What the capture ESTABLISHES (measured, direct)
- <fact grounded in a frozen value>
- <fact>

## 5. What the capture REFUTES (frozen values that already kill a hypothesis)
- <hypothesis> — killed by `<signal>=<value>`

## 6. Cross-observations (other runs / readbacks — flag if a DIFFERENT run)
- <e.g. "die_b memory readback (SEPARATE run): idx0..3 landed" — note it's cross-run, so any reconciliation is inference>

## 7. The OPEN QUESTION
- <the single thing the diagnosis must resolve, e.g. "which override term at :1909 holds hreadyout low — wr_hold_r or pipe-never-fills?">

## 8. Known-relevant RTL anchors (optional, speeds grounding)
- `<file:line>` — <what it is>
