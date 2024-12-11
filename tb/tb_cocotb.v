//******************************************************************************
// file:    tb_cocotb.v
//
// author:  JAY CONVERTINO
//
// date:    2024/12/11
//
// about:   Brief
// Test bench wrapper for cocotb
//
// license: License MIT
// Copyright 2024 Jay Convertino
//
// Permission is hereby granted, free of charge, to any person obtaining a copy
// of this software and associated documentation files (the "Software"), to
// deal in the Software without restriction, including without limitation the
// rights to use, copy, modify, merge, publish, distribute, sublicense, and/or
// sell copies of the Software, and to permit persons to whom the Software is
// furnished to do so, subject to the following conditions:
//
// The above copyright notice and this permission notice shall be included in
// all copies or substantial portions of the Software.
//
// THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
// IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
// FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
// AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
// LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
// FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS
// IN THE SOFTWARE.
//
//******************************************************************************

 `timescale 1ns/100ps

/*
 * Module: tb_cocotb
 *
 * Test bench for data width converter. This will run a file through the system
 * and write its output. These can then be compared to check for errors.
 * If the files are identical, no errors. A FST file will be written.
 *
 * Parameters:
 *
 *   SLAVE_WIDTH    - Width of the slave input bus in bytes
 *   MASTER_WIDTH   - Width of the master output bus in bytes
 *   REVERSE        - Change byte order
 *
 * Ports:
 *
 *   aclk           - Clock for AXIS
 *   arstn          - Negative reset for AXIS
 *   m_axis_tdata   - Output data
 *   m_axis_tvalid  - When active high the output data is valid
 *   m_axis_tready  - When set active high the output device is ready for data.
 *   m_axis_tlast   - Indicates last word in stream.
 *   s_axis_tdata   - Input data
 *   s_axis_tvalid  - When set active high the input data is valid
 *   s_axis_tready  - When active high the device is ready for input data.
 *   s_axis_tlast   - Is this the last word in the stream (active high).
 */
module tb_cocotb #(
    parameter SLAVE_WIDTH   = 1,
    parameter MASTER_WIDTH  = 1,
    parameter REVERSE = 0
  )
  (
    input                         aclk,
    input                         arstn,
    output [(MASTER_WIDTH*8)-1:0] m_axis_tdata,
    output                        m_axis_tvalid,
    input                         m_axis_tready,
    output                        m_axis_tlast,
    input  [(SLAVE_WIDTH*8)-1:0]  s_axis_tdata,
    input                         s_axis_tvalid,
    output                        s_axis_tready,
    input                         s_axis_tlast
  );

  // fst dump command
  initial begin
    $dumpfile ("tb_cocotb.fst");
    $dumpvars (0, tb_cocotb);
    #1;
  end
  
  //Group: Instantiated Modules

  /*
   * Module: dut
   *
   * Device under test, axis_data_width_converter
   */
  axis_data_width_converter #(
    .MASTER_WIDTH(MASTER_WIDTH),
    .SLAVE_WIDTH(SLAVE_WIDTH)
  ) dut (
    .aclk(aclk),
    .arstn(arstn),
    .m_axis_tdata(m_axis_tdata),
    .m_axis_tvalid(m_axis_tvalid),
    .m_axis_tready(m_axis_tready),
    .m_axis_tlast(m_axis_tlast),
    .s_axis_tdata(s_axis_tdata),
    .s_axis_tvalid(s_axis_tvalid),
    .s_axis_tready(s_axis_tready),
    .s_axis_tlast(s_axis_tlast)
  );
  
endmodule

