# G2 — nanoSoC ↔ nanoSoC across the link

The gate that says the die-to-die port works between two dies, not just against
a memory model.

> **Provenance.** This plan was written in a parallel scaffold repo,
> `~/SoCLabs/chiplet-integration-wrapper` (1 commit, unpushed, no submodules
> wired). It is preserved here because it is the right plan. See
> "Two wrapper repos" below.

## The environment

Two `nanosoc_multicore_soc` instances, each behind the chiplet wrapper, crossed
through `tidelink_top_pair` — the paired-die harness that already ran
**18.77 Mbit with zero errors** on z2_02 ↔ z2_03. Reuse it rather than build a
new one; it is the most exercised thing in `tidelink`.

## Assertions

These mirror `cocotb/soc_d2d_loopback` in the SoC, the env that closed gap D1 by
driving the port instead of terminating it.

1. **Cross-die write.** CPU0 on die A writes `shared_sram_0` on die B; die B
   reads it back. This is the data plane.
2. **Cross-die doorbell.** A write to `ipc_mailbox_0` on die A raises
   `doorbell_irq` on die B — which lands on die B's CPU0 NVIC at `IRQ[10]`,
   because the SoC maps `d2d_irq[0]` there. Proves the interrupt seam.
3. **Wedge hazard.** A TX-aperture write while `link_active=0` must **wait-state,
   not wedge**, and must complete once the link comes up.

Assertion 3 is the one worth building the env for. `tidelink`'s own
`INTEGRATION_GUIDE.md` flags `ahb_tx_*` as a **WEDGE HAZARD** — "a write with the
link down hangs the bus" — and the wrapper is where that gate belongs, since the
wrapper owns the sub-decode. An env that does not try to wedge the bus has not
tested the thing most likely to bite on silicon.

## What must already be true

`soc_d2d_loopback::outbound_slave_can_wait_state` proves the SoC's matrix honours
`d2d_ahb_m_hready`. Without that fix (see `D2D_PORT.md` §5) no multi-cycle link
can ever work, and G2 would fail in a way that looks like a link bug. Run it
first.

## Done means

Passes in simulation, then across two PYNQ boards using the existing two-board
SerDes harness.

---

## Two wrapper repos

There are currently **two** scaffolds for this work:

| Repo | State |
|---|---|
| `~/SoCLabs/nanosoc-ethernet-chiplet` (this one) | 5+ commits. Submodules pinned and a recursive clone proven to resolve. `tidelink_top.yaml` (165 ports) + `tidechart.yaml` (28 ports), both cross-checked against the RTL. `chiplet_d2d_decode.sv` and `tidechart_shim.sv`, both elaborated under VCS with mutation-verified testbenches. |
| `~/SoCLabs/chiplet-integration-wrapper` | 1 commit, no remote. Submodules scripted but never added. A 148-line wrapper skeleton, verilator-lint-only. Carries `docs/D2D_TIDELINK_WRAPPER.md` (in the SoC repo, `89c1efa`) as its blueprint, and this G2 plan. |

They agree on the design — including the two signature adapters (AHB5
`hprot[6:0]` → `hprot[3:0]` low nibble; tie `hmastlock`). Neither is pushed.

**This needs a human decision, not a merge.** One of them should be deleted. The
work that is unique to the other repo is its blueprint doc and this G2 plan; the
blueprint already lives in the SoC repo, and the plan now lives here.
