#******************************************************************************
# file:    tb_cocotb.py
#
# author:  JAY CONVERTINO
#
# date:    2024/12/09
#
# about:   Brief
# Cocotb test bench
#
# license: License MIT
# Copyright 2024 Jay Convertino
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to
# deal in the Software without restriction, including without limitation the
# rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
# sell copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in
# all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
# FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
# IN THE SOFTWARE.
#
#******************************************************************************

import random
import itertools

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import FallingEdge, RisingEdge, Timer, Event
from cocotb.binary import BinaryValue
from cocotbext.axi import (AxiStreamBus, AxiStreamSource, AxiStreamSink, AxiStreamMonitor, AxiStreamFrame)

# Function: random_bool
# Return a infinte cycle of random bools
#
# Returns: List
def random_bool():
  temp = []

  for x in range(0, 256):
    temp.append(bool(random.getrandbits(1)))

  return itertools.cycle(temp)

# Function: start_clock
# Start the simulation clock generator.
#
# Parameters:
#   dut - Device under test passed from cocotb test function
def start_clock(dut):
  cocotb.start_soon(Clock(dut.m_axis_aclk, 2, units="ns").start())
  cocotb.start_soon(Clock(dut.s_axis_aclk, 2, units="ns").start())
  cocotb.start_soon(Clock(dut.data_count_aclk, 2, units="ns").start())

# Function: reset_dut
# Cocotb coroutine for resets, used with await to make sure system is reset.
async def reset_dut(dut):
  dut.m_axis_arstn.value = 0
  dut.s_axis_arstn.value = 0
  dut.data_count_arstn.value = 0
  await Timer(5, units="ns")
  dut.m_axis_arstn.value = 1
  dut.s_axis_arstn.value = 1
  dut.data_count_arstn.value = 1

# Function: single_word
# Coroutine that is identified as a test routine. This routine tests for writing a single word, and
# then reading a single word.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def single_word(dut):

    start_clock(dut)

    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.s_axis_aclk, dut.s_axis_arstn, False)
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.m_axis_aclk, dut.m_axis_arstn, False)

    await reset_dut(dut)

    for x in range(0, 256):
        data = x.to_bytes(length = 1, byteorder='little') * dut.BUS_WIDTH.value
        tx_frame = AxiStreamFrame(data, tdest=x%(2**dut.s_axis_tdest.value.n_bits), tuser=(x-255)%(2**dut.s_axis_tuser.value.n_bits), tx_complete=Event())

        await axis_source.send(tx_frame)
        await tx_frame.tx_complete.wait()

        rx_frame = await axis_sink.recv()

        assert dut.m_axis_tlast.value.integer == 1, "tlast is not 1!"

        assert dut.s_axis_tready.value.integer == 1, "tready is not 1!"

        assert rx_frame.tdata == tx_frame.tdata, "Input tdata does not match output"
        assert rx_frame.tdest == tx_frame.tdest, "Input tdest does not match output"
        assert rx_frame.tuser == tx_frame.tuser, "Input tuser does not match output"

    await RisingEdge(dut.s_axis_aclk)

    assert dut.s_axis_tready.value[0] == 1, "tready is not 1!"

# Function: full_empty
# Coroutine that is identified as a test routine. This routine tests for writing till the fifo is full,
# Then reading from the full FIFO.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def full_empty(dut):

    start_clock(dut)

    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.s_axis_aclk, dut.s_axis_arstn, False)
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.m_axis_aclk, dut.m_axis_arstn, False)

    await reset_dut(dut)

    for x in range(0, 256):
        axis_sink.pause = True

        data = x.to_bytes(length = 1, byteorder='little') * dut.BUS_WIDTH.value * dut.FIFO_DEPTH.value
        tx_frame = AxiStreamFrame(data, tdest=x%(2**dut.s_axis_tdest.value.n_bits), tuser=(x-255)%(2**dut.s_axis_tuser.value.n_bits), tx_complete=Event())

        await axis_source.send(tx_frame)
        await tx_frame.tx_complete.wait()

        await Timer(10, units="ns")

        assert dut.data_count == dut.FIFO_DEPTH.value, "FIFO and DATA COUNT mismatch"

        assert dut.s_axis_tready.value.integer == 0, "tready is not 0!"

        axis_sink.pause = False

        rx_frame = await axis_sink.recv()
        assert rx_frame.tdata == tx_frame.tdata, "Input tdata does not match output"
        assert rx_frame.tdest == tx_frame.tdest, "Input tdest does not match output"
        assert rx_frame.tuser == tx_frame.tuser, "Input tuser does not match output"

    await RisingEdge(dut.s_axis_aclk)

    assert dut.s_axis_tready.value.integer == 1, "tready is not 1!"

# Function: random_ready
# Coroutine that is identified as a test routine. This routine tests for randomized ready from the sink.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def random_ready(dut):

    start_clock(dut)

    axis_source = AxiStreamSource(AxiStreamBus.from_prefix(dut, "s_axis"), dut.s_axis_aclk, dut.s_axis_arstn, False)
    axis_sink = AxiStreamSink(AxiStreamBus.from_prefix(dut, "m_axis"), dut.m_axis_aclk, dut.m_axis_arstn, False)

    axis_sink.set_pause_generator(random_bool())

    await reset_dut(dut)

    data = bytearray()

    for x in range(1024):
      data += random.randrange(256).to_bytes(length = 1, byteorder='little') * dut.BUS_WIDTH.value

    tx_frame = AxiStreamFrame(data, tdest=data[0]%(2**dut.s_axis_tdest.value.n_bits), tuser=data[dut.BUS_WIDTH.value]%(2**dut.s_axis_tuser.value.n_bits), tx_complete=Event())

    await axis_source.send(tx_frame)
    await tx_frame.tx_complete.wait()

    rx_frame = await axis_sink.recv()
    assert rx_frame.tdata == tx_frame.tdata, "Input tdata does not match output"
    assert rx_frame.tdest == tx_frame.tdest, "Input tdest does not match output"
    assert rx_frame.tuser == tx_frame.tuser, "Input tuser does not match output"

    await RisingEdge(dut.s_axis_aclk)

    assert dut.s_axis_tready.value.integer == 1, "tready is not 1!"

# Function: in_reset
# Coroutine that is identified as a test routine. This routine tests if device stays
# in unready state when in reset.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def in_reset(dut):

    start_clock(dut)

    dut.m_axis_tready.value = 0

    dut.m_axis_arstn.value = 0

    dut.s_axis_arstn.value = 0

    await Timer(10, units="ns")

    assert dut.s_axis_tready.value.integer == 0, "tready is 1!"

# Function: no_clock
# Coroutine that is identified as a test routine. This routine tests if no ready when clock is lost
# and device is left in reset.
#
# Parameters:
#   dut - Device under test passed from cocotb.
@cocotb.test()
async def no_clock(dut):

    dut.m_axis_tready.value = 0

    dut.m_axis_arstn.value = 0

    dut.m_axis_aclk.value = 0

    dut.s_axis_arstn.value = 0

    dut.s_axis_aclk.value = 0

    await Timer(5, units="ns")

    assert dut.s_axis_tready.value.integer == 0, "tready is 1!"
