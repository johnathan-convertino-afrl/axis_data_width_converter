//******************************************************************************
// file:    axis_data_width_converter.v
//
// author:  JAY CONVERTINO
//
// date:    2026/03/24
//
// about:   Brief
// AXIS DATA WIDTH CONVERTER
//
// license: License MIT
// Copyright 2026 Jay Convertino
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

`resetall
`timescale 1 ns/100 ps
`default_nettype none

/*
 * Module: axis_data_width_converter
 *
 * Change size of streaming bus in even integers of. 1/2 2/1 2/4 4/2 etc.
 *
 * Parameters:
 *
 *   SLAVE_WIDTH    - Width of the slave input bus in bytes
 *   MASTER_WIDTH   - Width of the master output bus in bytes
 *   FLUSH_LAST     - Once last bytes are received, force them out regardless of size (no longer ready to accept more data once this happens).
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
 *
 */
module axis_data_width_converter #(
    parameter SLAVE_WIDTH   = 1,
    parameter MASTER_WIDTH  = 1,
    parameter FLUSH_LAST    = 0
  )
  (
    input  wire                        aclk,
    input  wire                        arstn,
    output wire [(MASTER_WIDTH*8)-1:0] m_axis_tdata,
    output wire [MASTER_WIDTH-1:0]     m_axis_tkeep,
    output wire                        m_axis_tvalid,
    input  wire                        m_axis_tready,
    output wire                        m_axis_tlast,
    input  wire [(SLAVE_WIDTH*8)-1:0]  s_axis_tdata,
    input  wire [SLAVE_WIDTH-1:0]      s_axis_tkeep,
    input  wire                        s_axis_tvalid,
    output wire                        s_axis_tready,
    input  wire                        s_axis_tlast
  );
  
  `include "util_helper_math.vh"
  
  // Group: States
  // Core has 4 states, that includes an error state.
  //
  //  <READY>   - d1
  //  <FULL>    - d2
  //  <FLUSH>   - d3
  //  <ERROR>   - d0

  // State: READY
  // In this state core can register data into the FIFO.
  localparam READY  = 2'd1;
  // State: FULL
  // In this state core is FULL and can't accept more data.
  localparam FULL   = 2'd2;
  // State: FLUSH
  // In this state core has received TLAST and will flush out data.
  localparam FLUSH  = 2'd3;
  // State: ERROR
  // Should never be reached, state machine is in a bad state.
  localparam ERROR  = 2'd0;
  
  localparam RAM_DEPTH_POW = clogb2(MASTER_WIDTH*SLAVE_WIDTH);
  
  localparam RAM_DEPTH = 2**(RAM_DEPTH_POW);
  
  localparam FLUSH_LAST_BOOL = (FLUSH_LAST == 0 ? 1'b0 : 1'b1);
  
  generate
    if(SLAVE_WIDTH == MASTER_WIDTH) begin : gen_EQUAL_WIDTH
      assign m_axis_tdata  = s_axis_tdata;
      assign m_axis_tvalid = s_axis_tvalid;
      assign s_axis_tready = m_axis_tready;
      assign m_axis_tlast  = s_axis_tlast;
      assign m_axis_tkeep  = s_axis_tkeep;
    end else begin : gen_UNEQUAL_WIDTH
      integer index = 0;
      // used to concatenated transistion signals
      // Are we full?
      wire  w_full_check;
      // Is the buffer growing though is outputing data
      wire  w_growth_check;
      // Is the core empty?
      wire  w_empty_check;
      // Time to output data
      wire  w_get_data;
      
      wire [(MASTER_WIDTH*8)-1:0] w_m_axis_tdata;
      wire [MASTER_WIDTH-1:0]     w_m_axis_tkeep;
      wire                        w_m_axis_tvalid;
      wire                        w_m_axis_tlast;

      // state register
      reg   [ 1:0] r_state;
      
      // FIFO reg
      reg [RAM_DEPTH*8-1:0] r_fifo_tdata;
      reg [RAM_DEPTH-1:0]   r_fifo_tlast;
      reg [RAM_DEPTH-1:0]   r_fifo_tkeep;
      
      // counter, in bytes
      reg [RAM_DEPTH_POW:0] r_count;
      reg [RAM_DEPTH_POW:0] rr_count;
      
      reg r_ready;
      
      reg [(MASTER_WIDTH*8)-1:0] r_m_axis_tdata;
      reg [MASTER_WIDTH-1:0]     r_m_axis_tkeep;
      reg                        r_m_axis_tvalid;
      reg                        r_m_axis_tlast;
      
      assign w_full_check  = (r_count >= (RAM_DEPTH - (MASTER_WIDTH%SLAVE_WIDTH ? SLAVE_WIDTH*2 : SLAVE_WIDTH)));
      
      assign w_growth_check = ~m_axis_tready | (r_count > rr_count);
      
      assign w_empty_check = (r_count == 0);
      
      assign w_get_data    = (r_state == FLUSH ? ~w_empty_check : (r_count >= MASTER_WIDTH));
      
      assign s_axis_tready = r_ready & arstn;
      
      //r_count < MASTER_WIDTH ?  {MASTER_WIDTH*8{1'b0}} | r_fifo_tdata[RAM_DEPTH*8-1 -:] :
      
      assign w_m_axis_tdata  = (w_get_data ? r_fifo_tdata[(RAM_DEPTH-r_count)*8 +:MASTER_WIDTH*8] : r_m_axis_tdata);
      assign w_m_axis_tvalid = (w_get_data ? 1'b1 : r_m_axis_tvalid);
      
      assign w_m_axis_tkeep  = (w_get_data ? r_fifo_tkeep[(RAM_DEPTH-r_count) +:MASTER_WIDTH] : r_m_axis_tkeep);
      
      assign w_m_axis_tlast  = (w_get_data ? (r_count <= MASTER_WIDTH ? |r_fifo_tlast[(RAM_DEPTH-r_count) +:MASTER_WIDTH] : 1'b0) : r_m_axis_tlast);
      
      assign m_axis_tdata   = w_m_axis_tdata;
      assign m_axis_tvalid  = w_m_axis_tvalid;
      assign m_axis_tkeep   = w_m_axis_tkeep;
      assign m_axis_tlast   = w_m_axis_tlast;
      
      /*
      * AXIS OUT
      */
      always @(posedge aclk)
      begin
        if(arstn == 1'b0)
        begin
          r_m_axis_tdata  <= {MASTER_WIDTH*8{1'b0}};
          r_m_axis_tkeep  <= {MASTER_WIDTH{1'b0}};
          r_m_axis_tvalid <= 1'b0;
          r_m_axis_tlast  <= 1'b0;
        end else begin
          case(r_state)
            READY:
            begin
              r_m_axis_tdata  <= w_m_axis_tdata;
              r_m_axis_tvalid <= w_m_axis_tvalid;
              r_m_axis_tkeep  <= w_m_axis_tkeep;
              r_m_axis_tlast  <= w_m_axis_tlast;
              
              if(m_axis_tready)
              begin
                r_m_axis_tdata  <= {MASTER_WIDTH*8{1'b0}};
                r_m_axis_tkeep  <= {MASTER_WIDTH{1'b0}};
                r_m_axis_tvalid <= 1'b0;
                r_m_axis_tlast  <= 1'b0;
              end
            end
            default:
            begin
              if(m_axis_tready)
              begin
                r_m_axis_tdata  <= {MASTER_WIDTH*8{1'b0}};
                r_m_axis_tkeep  <= {MASTER_WIDTH{1'b0}};
                r_m_axis_tvalid <= 1'b0;
                r_m_axis_tlast  <= 1'b0;
              end
            end
          endcase
        end
      end
      
      // maintain state machine
      always @(posedge aclk) begin
        if(arstn == 1'b0) begin
          r_count   <= {RAM_DEPTH_POW{1'b0}};
          rr_count  <= {RAM_DEPTH_POW{1'b0}};
          r_state   <= READY;
          r_ready   <= 1'b0;
        end else begin
          r_state <= r_state;
          rr_count <= r_count;
          
          r_ready <= 1'b0;
          
          case(r_state)
            READY:
            begin
              r_ready <= 1'b1;
              
              case({m_axis_tready & ~w_empty_check & w_get_data, s_axis_tvalid})
                2'b11: r_count <= r_count + SLAVE_WIDTH - MASTER_WIDTH;
                2'b10: r_count <= r_count - MASTER_WIDTH;
                2'b01: r_count <= r_count + SLAVE_WIDTH;
                default: r_count <= r_count;
              endcase
              
              if(w_full_check & w_growth_check) begin
                r_state <= FULL;
                r_ready <= 1'b0;
              end
              
              if(s_axis_tlast & s_axis_tvalid & FLUSH_LAST_BOOL)
              begin
                r_state <= FLUSH;
                r_ready <= 1'b0;
              end
            end
            FULL:
            begin
              if(m_axis_tready) begin
                r_count  <= (w_get_data ? r_count - MASTER_WIDTH : r_count);
                
                if((r_count - MASTER_WIDTH) < (RAM_DEPTH - SLAVE_WIDTH*2)) begin
                  r_state <= READY;
                  r_ready <= 1'b1;
                end
              end
            end
            FLUSH:
            begin
              if(m_axis_tready) begin
                if(r_count <= MASTER_WIDTH) begin
                  r_state <= READY;
                  r_count <= {RAM_DEPTH_POW{1'b0}};
                  r_ready <= 1'b1;
                end else begin
                  r_count  <= (w_get_data ? r_count - MASTER_WIDTH : r_count);
                end
              end
            end
            default:
            begin
              r_state <= READY;
              r_count <= {RAM_DEPTH_POW{1'b0}};
            end
          endcase
        end
      end
      
      //data insertion
      always @(posedge aclk) begin
        if(arstn == 1'b0) begin
          r_fifo_tdata <= {RAM_DEPTH*8{1'b0}};
          r_fifo_tlast <= {RAM_DEPTH{1'b0}};
          r_fifo_tkeep <= {RAM_DEPTH{1'b0}};
        end else begin
          case(r_state)
            READY:
            begin
              r_fifo_tdata <= (s_axis_tvalid ? {s_axis_tdata, r_fifo_tdata[RAM_DEPTH*8-1:SLAVE_WIDTH*8]} : r_fifo_tdata);
              r_fifo_tlast <= (s_axis_tvalid ? {{SLAVE_WIDTH{s_axis_tlast}}, r_fifo_tlast[RAM_DEPTH-1:SLAVE_WIDTH]} : r_fifo_tlast);
              r_fifo_tkeep <= (s_axis_tvalid ? {s_axis_tkeep, r_fifo_tkeep[RAM_DEPTH-1:SLAVE_WIDTH]}: r_fifo_tkeep);
            end
            default:
            begin
              if((m_axis_tready & w_get_data) | w_empty_check) begin
                r_fifo_tdata[(RAM_DEPTH-r_count)*8 +:MASTER_WIDTH*8] <= {MASTER_WIDTH*8{1'b0}};
                r_fifo_tkeep[(RAM_DEPTH-r_count) +:MASTER_WIDTH] <= {MASTER_WIDTH{1'b0}};
                r_fifo_tlast[(RAM_DEPTH-r_count) +:MASTER_WIDTH] <= {MASTER_WIDTH{1'b0}};
              end
            end
          endcase
        end
      end
    end
  endgenerate
  
endmodule

`resetall
