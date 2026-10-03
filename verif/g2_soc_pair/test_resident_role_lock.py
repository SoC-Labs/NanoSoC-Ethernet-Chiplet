"""g2_soc_pair — RESIDENT ROLE_CFG WRITER (no external master at all).

The whole point of this module is that it drives NOTHING. Every other test in
this directory brings the link up by writing `0x2E03_2080` from an external
master on `eth_ss_0`; here the only stimulus is power-on reset, and the only
thing that can write ROLE_CFG is CPU1's stage-0 boot ROM.

What it observes, in the order of the defect chain:

    ROLE_CFG[1] W1S            (axi_chiplet_controller.sv:831 sets
                                nego_lock_pending_reg)
      -> role_lock_reg = 1     (:912, the SELF_ARM_TRAIN_EN term; the eth
                                wrapper instantiates tidelink_top with
                                SELF_ARM_TRAIN_EN(1'b1),
                                src/rtl/nanosoc_eth_chiplet.sv:925)
      -> role_locked_o = 1     (a real wrapper port, `a_role_locked_o`)
      -> wlink_por_reset = 0   (:3154  ~poresetn | ~role_locked)
      -> pad_clk_tx TOGGLES    (`a_pad_clk_tx`, a TB wire — this is the far
                                die's pad_clk_rx, i.e. the thing whose absence
                                means neither die trains)

POSITIVE  (src/rtl/bootrom/nanosoc_bootrom_chip_core.sv built from a
           stage0_bootrom_chip_core with ETH_D2D_ROLE set): all four hold.
NEGATIVE  (the same bench against a boot ROM WITHOUT the writer): role_locked_o
           stays 0 and pad_clk_tx never moves.

Run the same testcase for both; the expectation is selected by the
EXPECT_RESIDENT_WRITER environment variable ("1" = positive, "0" = negative) so
the two runs execute identical code and differ only in the ROM under test.

A joint work commissioned on behalf of SoC Labs, under Arm Academic Access
license.

Copyright (C) 2026, SoC Labs (www.soclabs.org)
"""

import os

import cocotb
from cocotb.triggers import RisingEdge, Timer

# CPU1 leaves reset at 200 ns (tb_g2_soc_pair.sv:72-78), runs the CMSIS startup
# (bss clear + data copy: 156 B + 104 B) and enters main(). The ROLE_CFG store is
# the 6th instruction of main() — deliberately ahead of the QSPI/XiP bring-up,
# which takes milliseconds of sim time against the SST26 VIP. 400 us at 50 MHz
# (20000 cycles) is therefore ~an order of magnitude more than it needs, and
# still far short of the first flash transaction.
POLL_LIMIT_NS = 400_000
POLL_STEP_CYCLES = 50

EXPECT_WRITER = os.environ.get("EXPECT_RESIDENT_WRITER", "1") == "1"


def _get(dut, path):
    """Hierarchical lookup that degrades to None rather than erroring."""
    obj = dut
    try:
        for part in path.split("."):
            obj = getattr(obj, part)
        return obj
    except AttributeError:
        return None


async def _watch_pad_clk(dut, out):
    """Count rising edges on die A's forwarded TX clock."""
    while True:
        await RisingEdge(dut.a_pad_clk_tx)
        out[0] += 1


@cocotb.test()
async def test_role_lock_from_resident_firmware(dut):
    log = dut._log

    por = _get(dut, "u_dieA.u_tidelink.u_chiplet_controller.wlink_por_reset")
    log.info("wlink_por_reset visible in hierarchy: %s", por is not None)

    edges = [0]
    cocotb.start_soon(_watch_pad_clk(dut, edges))

    # Sample the pre-reset / just-out-of-reset state so the "it was 0 and then
    # became 1" claim is measured, not assumed.
    await Timer(1, units="ns")
    log.info("t=1ns            role_locked_o=%s", dut.a_role_locked_o.value)

    locked_at = None
    t = 0
    while t < POLL_LIMIT_NS:
        for _ in range(POLL_STEP_CYCLES):
            await RisingEdge(dut.sys_fclk)
        t = cocotb.utils.get_sim_time(units="ns")
        try:
            if int(dut.a_role_locked_o.value) == 1:
                locked_at = t
                break
        except ValueError:
            pass  # still X during reset

    # Let the ungated clock run a while so the edge count is meaningful either
    # way (the negative control must reach this point too).
    for _ in range(500):
        await RisingEdge(dut.sys_fclk)

    a_lock = dut.a_role_locked_o.value
    b_lock = dut.b_role_locked_o.value
    por_v = por.value if por is not None else "n/a"

    log.info("=========== RESIDENT ROLE_CFG WRITER ===========")
    log.info("expectation              : writer %s",
             "PRESENT" if EXPECT_WRITER else "ABSENT (negative control)")
    log.info("external APB writes       : 0 (this module drives nothing)")
    log.info("a_role_locked_o           : %s", a_lock)
    log.info("b_role_locked_o           : %s", b_lock)
    log.info("wlink_por_reset (die A)   : %s", por_v)
    log.info("a_pad_clk_tx rising edges : %d", edges[0])
    log.info("role_locked_o rose at     : %s",
             ("%d ns" % locked_at) if locked_at is not None else "never")
    log.info("================================================")

    if EXPECT_WRITER:
        assert locked_at is not None, (
            "role_locked_o never asserted within %d ns with NO external master. "
            "The resident ROLE_CFG[1] W1S in CPU1 stage-0 did not reach "
            "0x2E032080." % POLL_LIMIT_NS)
        assert int(a_lock) == 1, "a_role_locked_o = %s" % a_lock
        if por is not None:
            assert int(por.value) == 0, (
                "role_locked=1 but wlink_por_reset still asserted (%s)" % por.value)
        assert edges[0] > 0, (
            "role_locked_o=1 but pad_clk_tx never toggled — the forwarded TX "
            "clock is still gated, so the far die has no RX clock.")
    else:
        assert locked_at is None, (
            "NEGATIVE CONTROL FAILED: role_locked_o asserted at %s ns with no "
            "resident writer and no external master. Something else is "
            "latching role_lock, so the positive result proves nothing."
            % locked_at)
        assert int(a_lock) == 0, "a_role_locked_o = %s" % a_lock
        if por is not None:
            assert int(por.value) == 1, (
                "wlink_por_reset released without role_lock (%s)" % por.value)
        assert edges[0] == 0, (
            "NEGATIVE CONTROL FAILED: pad_clk_tx toggled %d times with "
            "role_lock=0 — the clock gate this whole chain rests on is not "
            "actually gating." % edges[0])
