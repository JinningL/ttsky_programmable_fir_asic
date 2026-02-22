# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge, FallingEdge


def hi8(v: int) -> int:
    return (v & 0xFFFF) >> 8


def filt_value(hist, coeffs):
    x0, x1, x2, x3 = hist
    h0, h1, h2, h3 = coeffs
    y = x0 * h0 + x1 * h1 + x2 * h2 + x3 * h3
    return y & 0xFFFF


async def write_ui(dut, value: int):
    dut.ui_in.value = value & 0xFF
    await RisingEdge(dut.clk)


async def apply_reset(dut, cycles: int = 5):
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, cycles)
    dut.rst_n.value = 1
    await RisingEdge(dut.clk)


async def load_mode(dut, mode: int):
    # op_type=11, data[5:4]=mode, data[3]=1(enable)
    await write_ui(dut, (0b11 << 6) | ((mode & 0x3) << 4) | (1 << 3))


async def send_sample(dut, sample: int):
    # op_type=00, data[5:0]=sample
    await write_ui(dut, sample & 0x3F)


async def read_coeff6(dut, sel: int) -> int:
    dut.uio_in.value = sel & 0x3
    await RisingEdge(dut.clk)
    return (int(dut.uio_out.value) >> 2) & 0x3F


async def check_stream_mode(dut, samples, coeffs, mode_name: str):
    # y_output_reg captures previous cycle's FIR result, so compare against
    # an expected value delayed by one sample cycle.
    hist = [0, 0, 0, 0]
    expected_delayed = 0

    for sample in samples:
        await send_sample(dut, sample)
        await FallingEdge(dut.clk)

        got = int(dut.uo_out.value)
        assert got == expected_delayed, (
            f"{mode_name} sample={sample}, hist={hist}, "
            f"expected=0x{expected_delayed:02x}, got=0x{got:02x}"
        )

        hist = [sample & 0x3F, hist[0], hist[1], hist[2]]
        expected_delayed = hi8(filt_value(hist, coeffs))


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start enhanced FIR protocol test")

    clock = Clock(dut.clk, 10, unit="us")
    cocotb.start_soon(clock.start())

    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    await apply_reset(dut)

    # Verify low-pass preset readback: h=[4,2,1,1]
    await load_mode(dut, 0b10)
    assert await read_coeff6(dut, 0b00) == 4
    assert await read_coeff6(dut, 0b01) == 2
    assert await read_coeff6(dut, 0b10) == 1
    assert await read_coeff6(dut, 0b11) == 1

    # Functional check in bypass mode: y = x0
    await apply_reset(dut)
    await load_mode(dut, 0b00)
    await check_stream_mode(
        dut=dut,
        samples=[10, 33, 63, 1, 0],
        coeffs=[1, 0, 0, 0],
        mode_name="bypass",
    )

    # Functional check in high-pass mode: y = x0 - x1
    await apply_reset(dut)
    await load_mode(dut, 0b11)
    await check_stream_mode(
        dut=dut,
        samples=[0, 63, 0, 20, 0],
        coeffs=[1, -1, 0, 0],
        mode_name="high-pass",
    )

    # Sanity: coeff readback of h1 in high-pass is -1 => 0xFF => low 6 bits 0x3F
    h1_rb = await read_coeff6(dut, 0b01)
    assert h1_rb == 0x3F, f"expected h1 readback 0x3F, got 0x{h1_rb:02x}"

    dut._log.info("Enhanced FIR protocol test passed")
