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
 *   overflow_count - How many times has the core overflowed. This is a indicator of a bug in the code or the core. If this happens, data is lost due to state reset.
 *
 */
module axis_data_width_converter #(
    parameter SLAVE_WIDTH   = 1,
    parameter MASTER_WIDTH  = 1,
    parameter FLUSH_LAST    = 1
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
    input  wire                        s_axis_tlast,
    output wire [31:0]                 overflow_count
  );
  
  `include "util_helper_math.vh"
  
  // Group: States
  // Core has 4 states, including an overflow(error) state.
  //
  //  <READY>     - d1
  //  <FULL>      - d2
  //  <FLUSH>     - d3
  //  <OVERFLOW>  - d0

  // State: READY
  // In this state core can register data into the FIFO.
  localparam READY  = 2'd1;
  // State: FULL
  // In this state core is FULL and can't accept more data.
  localparam FULL   = 2'd2;
  // State: FLUSH
  // In this state core has received TLAST and will flush out data.
  localparam FLUSH  = 2'd3;
  // State: OVERFLOW
  // Should never be reached, state machine is in a bad state due to buffer overflow.
  localparam OVERFLOW  = 2'd0;
  
  // Set the register depth to some power that is large enough to hold all the data without overflow or underflow.
  localparam REG_DEPTH_POW = clogb2((MASTER_WIDTH == 1 ? 2 : MASTER_WIDTH)*(SLAVE_WIDTH == 1 ? 2 : SLAVE_WIDTH));
  
  // Set the reg depth to that power of two.
  localparam REG_DEPTH = 2**(REG_DEPTH_POW);
  
  // Filter values that are not 0 to a 1. 0 is 0.
  localparam FLUSH_LAST_BOOL = (FLUSH_LAST == 0 ? 1'b0 : 1'b1);
  
  // Generate loops
  genvar gen_index;
  
  //Generate for equal and unequal
  generate
    //pass through, this is silly.
    if(SLAVE_WIDTH == MASTER_WIDTH) begin : gen_EQUAL_WIDTH
      assign m_axis_tdata   = s_axis_tdata;
      assign m_axis_tvalid  = s_axis_tvalid;
      assign s_axis_tready  = m_axis_tready;
      assign m_axis_tlast   = s_axis_tlast;
      assign m_axis_tkeep   = s_axis_tkeep;
      assign overflow_count = {32{1'b0}};
    //real work is in the unequal case.
    end else begin : gen_UNEQUAL_WIDTH
      // used to concatenated transistion signals
      // Are we almost full, (SLAVE_WIDTH*2 From REG_DEPTH)?
      wire  w_almost_full_check;
      // Is the buffer growing though is outputing data
      wire  w_growth_check;
      // Is the core empty?
      wire  w_empty_check;
      // Time to output data
      wire  w_get_data;
      
      // wire the m_axis output so it can be read and used internally
      wire [(MASTER_WIDTH*8)-1:0] w_m_axis_tdata;
      wire [MASTER_WIDTH-1:0]     w_m_axis_tkeep;
      wire                        w_m_axis_tvalid;
      wire                        w_m_axis_tlast;
      
      // Special cases of output data when we are trying to flush ALIGNED data
      // Meaning 2 bytes for a 4 byte output will populate the 0th and 1st bytes.
      wire [(MASTER_WIDTH*8)-1:0] w_m_axis_tdata_align;
      wire [MASTER_WIDTH-1:0]     w_m_axis_tkeep_align;
      // Are there and valid bytes in the buffer? Different than empty since we can have bytes, but taxis might have them marked as invalid (0).
      wire                        w_valid_bytes_left;
      // Range checks across the whole buffer.
      wire                        w_valid_bytes_left_in_range;

      // state register
      reg   [ 1:0] r_state;
      
      // FIFO registers for input data.
      reg [REG_DEPTH*8-1:0] r_fifo_tdata;
      reg [REG_DEPTH-1:0]   r_fifo_tlast;
      reg [REG_DEPTH-1:0]   r_fifo_tkeep;
      
      // counter, in bytes, larger to show overflows.
      reg [REG_DEPTH_POW:0] r_count;
      reg [REG_DEPTH_POW:0] rr_count;
      
      // Set when core is ready for input data.
      reg r_ready;
      
      // Hold data if we don't need to get data and master axis out has a slave thats not ready.
      reg [(MASTER_WIDTH*8)-1:0] r_m_axis_tdata;
      reg [MASTER_WIDTH-1:0]     r_m_axis_tkeep;
      reg                        r_m_axis_tvalid;
      reg                        r_m_axis_tlast;
      
      //overflow counter
      reg [31:0]  r_overflow_counter;
      
      // Are we almost full? With a bit to spare since when this is high we will still insert data.
      assign w_almost_full_check   = (r_count >= (REG_DEPTH - SLAVE_WIDTH*2));
      
      // Is the register growing while the output device is not ready.
      assign w_growth_check = ~m_axis_tready | (r_count > rr_count);
      
      // Is the register empty.
      assign w_empty_check  = (r_count == 0);
      
      // Is there valid data to output, and in FLUSH mode its valid till its empty.
      assign w_get_data     = (r_state == FLUSH ? ~w_empty_check : (r_count >= MASTER_WIDTH));
      
      // Tell input device core is ready for conversion.
      assign s_axis_tready  = r_ready & arstn;
      
      // Set output wires to register data, unless we can get data and if the count for data is less or equal to the output than use the aligned wires(signals).
      assign w_m_axis_tdata  = (w_get_data ? (r_count <= MASTER_WIDTH ? w_m_axis_tdata_align : r_fifo_tdata[(REG_DEPTH-r_count)*8 +:MASTER_WIDTH*8]) : r_m_axis_tdata);
      assign w_m_axis_tvalid = (w_get_data ? (r_count <= MASTER_WIDTH ? |w_m_axis_tkeep_align : 1'b1) : r_m_axis_tvalid);
      assign w_m_axis_tkeep  = (w_get_data ? (r_count <= MASTER_WIDTH ? w_m_axis_tkeep_align : r_fifo_tkeep[(REG_DEPTH-r_count) +:MASTER_WIDTH]) : r_m_axis_tkeep);
      // (NEEDS A SECOND PASS) last is a bit special since we use tkeep to mask out extra tlast output, and use an or to output 1 whenever it exists, or we also use w_valid_bytes_left. 
      assign w_m_axis_tlast  = (w_get_data ? (r_count <= MASTER_WIDTH ? |r_fifo_tlast[(REG_DEPTH-r_count) +:MASTER_WIDTH] & |w_m_axis_tkeep_align : ~w_valid_bytes_left) : r_m_axis_tlast);
      
      // assign outputs to current muxed selections.
      assign m_axis_tdata   = w_m_axis_tdata;
      assign m_axis_tvalid  = w_m_axis_tvalid;
      assign m_axis_tkeep   = w_m_axis_tkeep;
      assign m_axis_tlast   = w_m_axis_tlast;
      
      // keep track if a overflow happens, this shouldn't happen, but just in case lets have a way of catching it (code in the core has a bug that should be corrected).
      assign overflow_count = r_overflow_counter;
      
      //Set valid bytes left only bother if we are still over the master width. The w_valid_bytes_left_in_range checks the last bytes for output to see if tkeep is all zeros.
      assign w_valid_bytes_left = (r_count == 0 ? 1'b0 : (r_count <= MASTER_WIDTH) ? 1'b1 : w_valid_bytes_left_in_range);
      
      //If we set the FLUSH method, generate signals.
      if(FLUSH_LAST_BOOL) begin : gen_LAST_FLUSH
        //Create aligned data that based upon the r_count will align the 0th valid byte to the 0th output byte of the master port.
        for(gen_index = 1; gen_index <= MASTER_WIDTH; gen_index = gen_index + 1) begin : gen_BYTE_ALIGN
          assign w_m_axis_tdata_align = (r_count == gen_index ? {{(MASTER_WIDTH-gen_index)*8{1'b0}}, r_fifo_tdata[(REG_DEPTH-gen_index)*8 +:gen_index*8]}: {{MASTER_WIDTH*8{1'bz}}});
          assign w_m_axis_tkeep_align = (r_count == gen_index ? {{(MASTER_WIDTH-gen_index){1'b0}}, r_fifo_tkeep[(REG_DEPTH-gen_index) +:gen_index]}: {{MASTER_WIDTH{1'bz}}});
        end
        
        //Check the last master output bytes for all depth ranges to see if we have run out of valid (tkeep) data bytes.
        for(gen_index = MASTER_WIDTH+1; gen_index < REG_DEPTH; gen_index = gen_index + 1) begin : gen_END_OF_BYTE_CHECK
          assign w_valid_bytes_left_in_range = (r_count == gen_index ? |r_fifo_tkeep[REG_DEPTH-(gen_index-MASTER_WIDTH) +:(gen_index-MASTER_WIDTH)] : 1'bz);
        end
      end
      
      // AXIS MASTER OUTPUT REGISTER SETUP
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
              //When ready we set the register to current output
              //This is due to READY being able to still take in data
              //And won't stall till its full and r_count will continue.
              //Also if we are not ready for data we don't destroy what is there.
              r_m_axis_tdata  <= w_m_axis_tdata;
              r_m_axis_tvalid <= w_m_axis_tvalid;
              r_m_axis_tkeep  <= w_m_axis_tkeep;
              r_m_axis_tlast  <= w_m_axis_tlast;
              
              // clear data once ready
              if(m_axis_tready)
              begin
                r_m_axis_tdata  <= {MASTER_WIDTH*8{1'b0}};
                r_m_axis_tkeep  <= {MASTER_WIDTH{1'b0}};
                r_m_axis_tvalid <= 1'b0;
                r_m_axis_tlast  <= 1'b0;
              end
            end
            OVERFLOW:
            begin
              r_m_axis_tdata  <= {MASTER_WIDTH*8{1'b0}};
              r_m_axis_tkeep  <= {MASTER_WIDTH{1'b0}};
              r_m_axis_tvalid <= 1'b0;
              r_m_axis_tlast  <= 1'b0;
            end
            default:
            begin
              //clear current registered data on FLUSH or FULL. Since this is leftover from READY state.
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
      
      // State Machine, ready, and counter update block.
      always @(posedge aclk) begin
        if(arstn == 1'b0) begin
          r_overflow_counter <= {32{1'b0}};
          r_count   <= {REG_DEPTH_POW{1'b0}};
          rr_count  <= {REG_DEPTH_POW{1'b0}};
          r_state   <= READY;
          r_ready   <= 1'b0;
        end else begin
          r_state <= r_state;
          rr_count <= r_count;
          r_overflow_counter <= r_overflow_counter;
          
          //Any state that isn't a ready state defaults to not ready.
          r_ready <= 1'b0;
          
          case(r_state)
            READY:
            begin
              r_ready <= 1'b1;
              
              //essentially update the counter on specific situations, in a way that takes into account a read AND write, read, write or nothing.
              case({m_axis_tready & ~w_empty_check & w_get_data, s_axis_tvalid})
                2'b11: r_count <= r_count + SLAVE_WIDTH - MASTER_WIDTH;
                2'b10: r_count <= r_count - MASTER_WIDTH;
                2'b01: r_count <= r_count + SLAVE_WIDTH;
                default: r_count <= r_count;
              endcase
              
              //Almost full, and the buffer is growing. If it isn't growing we can skip going to full and stay ready.
              if(w_almost_full_check & w_growth_check) begin
                r_state <= FULL;
                r_ready <= 1'b0;
              end
              
              //FLUSH is enabled and we have a valid tlast from the input stream.
              if(s_axis_tlast & s_axis_tvalid & FLUSH_LAST_BOOL)
              begin
                r_state <= FLUSH;
                r_ready <= 1'b0;
              end
              
              //COUNTER has over flowed 
              if(r_count > REG_DEPTH) begin
                r_state <= OVERFLOW;
                r_ready <= 1'b0;
              end
            end
            FULL:
            begin
              //Since READY will have output data, in the FULL state we can wait for tready before next update (FWFT).
              if(m_axis_tready) begin
                //update counter
                r_count  <= (w_get_data ? r_count - MASTER_WIDTH : r_count);
                
                //we are no longer full, or there is not enough data in the registers.
                if(~w_almost_full_check || (r_count < MASTER_WIDTH)) begin
                  r_state <= READY;
                  r_ready <= 1'b1;
                end
              end
            end
            FLUSH:
            begin
              //Since READY will have output data, in the FLUSH state we can wait for tready before next update (FWFT).
              if(m_axis_tready) begin
                //once we have exhausted all the full word output data, go back to ready and clear the counter so we output remaining bytes.
                if(r_count <= MASTER_WIDTH) begin
                  r_state <= READY;
                  r_count <= {REG_DEPTH_POW{1'b0}};
                  r_ready <= 1'b1;
                end else begin
                  //Since we still have full words of data, perform a normal counter update
                  r_count  <= (w_get_data ? r_count - MASTER_WIDTH : r_count);
                  
                  //If the valid bytes is false, 
                  if(w_valid_bytes_left == 1'b0) begin
                    r_state <= READY;
                    r_count <= {REG_DEPTH_POW{1'b0}};
                    r_ready <= 1'b1;
                  end
                end
              end
            end
            //This shouldn't happen, only state not decoded is a overflow and will increment a counter to show how many have happened.
            default:
            begin
              r_state   <= READY;
              r_count   <= {REG_DEPTH_POW{1'b0}};
              rr_count  <= {REG_DEPTH_POW{1'b0}};
              r_ready   <= 1'b0;
              r_overflow_counter = r_overflow_counter + 1;
            end
          endcase
        end
      end
      
      // Update data into the buffers based upon the current state.
      always @(posedge aclk) begin
        if(arstn == 1'b0) begin
          r_fifo_tdata <= {REG_DEPTH*8{1'b0}};
          r_fifo_tlast <= {REG_DEPTH{1'b0}};
          r_fifo_tkeep <= {REG_DEPTH{1'b0}};
        end else begin
          case(r_state)
            READY:
            begin
              // In ready state with valid data, always update the register with data from input.
              r_fifo_tdata <= (s_axis_tvalid ? {s_axis_tdata, r_fifo_tdata[REG_DEPTH*8-1:SLAVE_WIDTH*8]} : r_fifo_tdata);
              r_fifo_tlast <= (s_axis_tvalid ? {{SLAVE_WIDTH{s_axis_tlast}}, r_fifo_tlast[REG_DEPTH-1:SLAVE_WIDTH]} : r_fifo_tlast);
              r_fifo_tkeep <= (s_axis_tvalid ? {s_axis_tkeep, r_fifo_tkeep[REG_DEPTH-1:SLAVE_WIDTH]}: r_fifo_tkeep);
            end
            OVERFLOW:
            begin
              // OVERFLOW is a reset of all registers besides the overflow_counter.
              r_fifo_tdata <= {REG_DEPTH*8{1'b0}};
              r_fifo_tlast <= {REG_DEPTH{1'b0}};
              r_fifo_tkeep <= {REG_DEPTH{1'b0}};
            end
            //In flush or fill, if we get data, are not empty and are ready, lets clear some old data from the registers. For LOLS.
            default:
            begin
              if((m_axis_tready & w_get_data) | w_empty_check) begin
                r_fifo_tdata[(REG_DEPTH-r_count)*8 +:MASTER_WIDTH*8] <= {MASTER_WIDTH*8{1'b0}};
                r_fifo_tkeep[(REG_DEPTH-r_count) +:MASTER_WIDTH] <= {MASTER_WIDTH{1'b0}};
                r_fifo_tlast[(REG_DEPTH-r_count) +:MASTER_WIDTH] <= {MASTER_WIDTH{1'b0}};
              end
            end
          endcase
        end
      end
    end
  endgenerate
  
endmodule

`resetall
