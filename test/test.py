# SPDX-FileCopyrightText: © 2024 Tiny Tapeout
# SPDX-License-Identifier: Apache-2.0

import cocotb
from cocotb.clock import Clock
from cocotb.triggers import ClockCycles, RisingEdge


@cocotb.test()
async def test_project(dut):
    dut._log.info("Start")
    data_to_send = [0, 1, 0, 0, 1, 1, 0, 1] 
    
    # Set the clock period to 20 ns
    clock = Clock(dut.clk, 20, unit="ns")
    cocotb.start_soon(clock.start())

    # Reset
    dut._log.info("Reset")
    dut.ena.value = 1
    dut.ui_in.value = 0
    dut.uio_in.value = 0
    dut.rst_n.value = 0
    await ClockCycles(dut.clk, 10)
    dut.rst_n.value = 1
    
    dut._log.info("Test project behavior")
    
    # -------------------------------------------------------------------------
    # 5. Serial transmission loop (Building entire integer masks for GL_TEST compatibility)
    # -------------------------------------------------------------------------
    for i in range(len(data_to_send)):
        bit_actual = data_to_send[i]
        
        # Determine control flags based on the current bit index
        # valid_in (bit 0) is always 1 during transmission
        valid_in = 1
        # sop_in (bit 1) is 1 ONLY on the first bit (i == 0)
        sop_in = 1 if (i == 0) else 0
        # eop_in (bit 2) is 0 during active data streaming
        eop_in = 0
        # data_in (bit 3) takes the actual bit from the data_to_send array
        data_in = bit_actual
        
        # Combine all bits into a single integer vector: 
        # ui_data = (data_in << 3) | (eop_in << 2) | (sop_in << 1) | (valid_in << 0)
        ui_data = (data_in << 3) | (eop_in << 2) | (sop_in << 1) | (valid_in << 0)
        
        # Write the whole vector to the packed netlist pins at once
        dut.ui_in.value = ui_data
        
        # Wait for the clock edge so the chip samples the bit
        await RisingEdge(dut.clk)
        
    # -------------------------------------------------------------------------
    # 6. End of Packet signal
    # -------------------------------------------------------------------------
    # After the loop, we drive: valid_in=1, sop_in=0, eop_in=1, data_in=0
    # ui_data = (0 << 3) | (1 << 2) | (0 << 1) | (1 << 0) = 4'b0101 = decimal 5
    dut.ui_in.value = (0 << 3) | (1 << 2) | (0 << 1) | (1 << 0)
    await RisingEdge(dut.clk)
    
    # -------------------------------------------------------------------------
    # 7. Clean up signals
    # -------------------------------------------------------------------------
    # Drive all control and data lines back to 0
    dut.ui_in.value = 0
    
    # Wait some cycles to see the decoder output change
    for _ in range(30):
        await RisingEdge(dut.clk)

    dut._log.info("Test completed successfully")
