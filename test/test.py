# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start FIR test")

    # 100 kHz clock
    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    # Reset
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1

    # Input stream and expected moving-average outputs:
    # y[n] = floor((x[n] + x[n-1] + x[n-2] + x[n-3]) / 4)
    samples = [4, 8, 12, 16, 0, 0]
    expected = [1, 3, 6, 10, 9, 7]

    for sample, exp in zip(samples, expected):
        dut.ui_in.value = sample
        await ClockCycles(dut.clk, 1)
        got = int(dut.uo_out.value)
        assert got == exp, f"sample={sample}, expected={exp}, got={got}"
