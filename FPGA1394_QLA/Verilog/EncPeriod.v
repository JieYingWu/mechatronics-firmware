/*******************************************************************************
 *
 * Copyright(C) 2008-2017 ERC CISST, Johns Hopkins University.
 *
 * This module measures the encoder pulse period by counting the edges of a
 * fixed fast clock (~3 MHz) between encoder pulses.  Each new encoder pulse
 * latches the current count and starts a new one.  From this measurement the
 * encoder period can be obtained by multiplying the number of counts by the
 * period of the fixed fast clock.
 *
 * Assumes counter will overflow if encoder moves too slowly.
 *
 * Revision history
 *     07/20/08    Paul Thienphrapa    Initial revision
 *     11/21/11    Paul Thienphrapa    Fix to use ticks+ as clock
 *     02/27/12    Paul Thienphrapa    Only count up due to unknown problem
 *     02/29/12    Zihan Chen          Fix implementation and debug module
 *     03/17/14    Peter Kazanzides    Update data every tick (dP = 4)
 *     04/07/17    Jie Ying Wu         Return only larger of cnter or cnter_latch
 */

// ---------- Peter ------------------
module EncPeriod(
   input wire clk_fast,      // count this clock between encoder ticks
   input wire reset,         // global reset signal
   input wire ticks,         // encoder transition signal
   input wire dir,           // direction of the ticks
   output wire ticks_en,     // edge signal 
   output reg[21:0] latched, // latched counter from last encoder event
   output reg[21:0] count,    // number clk_fast periods per tick
   output reg dir_changed
);

    // overflow value for unsigned 22-bit number
    parameter overflow = 22'h3FFFFF;


//------------------------------------------------------------------------------
// hardware description
//

// convert ticks to pulse
reg dir_r;      // dir start 
reg ticks_r;    // previous ticks
assign ticks_en = ticks & (~ticks_r);

// latch cnter value 
always @(posedge ticks_en or negedge reset)
begin
    if (reset == 0) begin
        latched <= 22'd0;
    end
    else begin
        latched <= count;
    end
end

// free-running counter 
always @(posedge clk_fast or posedge ticks_en or negedge reset) 
begin
   if (reset == 0 || ticks_en) begin
      count <= 22'd0;
      dir_changed <= 0;
   end
   else if (dir != dir_r) begin
      count <= overflow;
      dir_changed <= 1;
   end
   else if (count != overflow) begin
      count <= count + 1;   
   end
end

endmodule


// ------------------------------------------------
// Quad Ticks Version 
// ------------------------------------------------
module EncPeriodQuad(
    input wire clk,           // sysclk
    input wire clk_fast,      // count this clock between encoder ticks
    input wire reset,         // global reset signal
    input wire a,             // quad encoder line a
    input wire b,             // quad encoder line b
    input wire dir,           // dir from EncQuad
    output reg[31:0] period   // num of fast clock ticks
);

    reg[1:0] mux;
    wire a_up_tick;
    wire a_dn_tick;
    wire b_up_tick;
    wire b_dn_tick;
    wire[21:0] a_up_latched;   // channel a up data 
    wire[21:0] a_dn_latched;   // channel a dn data
    wire[21:0] b_up_latched;   // channel b up data
    wire[21:0] b_dn_latched;   // channel b dn latched_value
    wire[21:0] a_up_counter;   // channel a up free running counter
    wire[21:0] a_dn_counter;   // channel a dn free running counter
    wire[21:0] b_up_counter;   // channel b up free running counter
    wire[21:0] b_dn_counter;   // channel b dn free running counter
    wire a_up_dir_changed;
    wire a_dn_dir_changed;
    wire b_up_dir_changed;
    wire b_dn_dir_changed;

//------------------------------------------------------------------------------
// hardware description
//
EncPeriod EncPerUpA(clk_fast, reset,  a, dir, a_up_tick, a_up_latched, a_up_counter, a_up_dir_changed);
EncPeriod EncPerDnA(clk_fast, reset, ~a, dir, a_dn_tick, a_dn_latched, a_dn_counter, a_dn_dir_changed);
EncPeriod EncPerUpB(clk_fast, reset,  b, dir, b_up_tick, b_up_latched, b_up_counter, b_up_dir_changed);
EncPeriod EncPerDnB(clk_fast, reset, ~b, dir, b_dn_tick, b_dn_latched, b_dn_counter, b_dn_dir_changed);

localparam[1:0] a_up = 2'b00;
localparam[1:0] a_dn = 2'b01;
localparam[1:0] b_up = 2'b10;
localparam[1:0] b_dn = 2'b11;

// Determine which edge is the most recent
always @(posedge a_up_tick or posedge a_dn_tick or posedge b_up_tick or posedge b_dn_tick)
begin
    if (a_up_tick) begin
        mux <= a_up;
    end
    else if (b_up_tick) begin
        mux <= b_up;    
    end    
    else if (a_dn_tick) begin
        mux <= a_dn;
    end
    else if (b_dn_tick) begin
        mux <= b_dn;
    end
end

// Pass back the next expected value (depending on direction) if:
// 1) It is from the free running counter (bit 31 is 0)
// 2) There has been no direction change in its last encoder cycle (bit 29 is 0)
// 3) The value is bigger than the current one
always @(posedge clk_fast or negedge reset) begin
   if (reset == 0) begin
      period <= 32'd0;
   end
   
   else if (mux == a_up) begin  // A up
      if ((dir == 0) && ~b_up_dir_changed && (b_up_counter[21:0] > a_up_latched[21:0])) begin
         period <= {1'b0, dir, b_up_dir_changed, b_up, 5'b01000, b_up_counter};
      end 
      else if ((dir == 1) && ~b_dn_dir_changed && (b_dn_counter[21:0] > a_up_latched[21:0])) begin
         period <= {1'b0, dir, b_dn_dir_changed, b_dn, 5'b10000, b_dn_counter};
      end 
      else begin
         period <= {1'b1, dir, a_up_dir_changed, a_up, 5'b11000, a_up_latched};
      end
   end
   
   else if (mux == b_up) begin  // B up
      if ((dir == 0) && ~a_dn_dir_changed && (a_dn_counter[21:0] > b_up_latched[21:0])) begin
         period <= {1'b0, dir, a_up_dir_changed, a_dn, 5'b01000, a_dn_counter};
      end 
      else if ((dir == 1) && ~a_up_dir_changed && (a_up_counter[21:0] > b_up_latched[21:0])) begin
         period <= {1'b0, dir, a_up_dir_changed, a_up, 5'b10000, a_up_counter};
      end 
      else begin
         period <= {1'b1, dir, b_up_dir_changed, b_up, 5'b11000, b_up_latched};
      end
   end
   
   else if (mux == a_dn) begin  // A down
      if ((dir == 0) && ~b_dn_dir_changed && (b_dn_counter[21:0] > a_dn_latched[21:0])) begin
         period <= {1'b0, dir, b_dn_dir_changed, b_dn, 5'b01000, b_dn_counter};
      end 
      else if ((dir == 1) && ~b_up_dir_changed && (b_up_counter[21:0] > a_dn_latched[21:0])) begin
         period <= {1'b0, dir, b_up_dir_changed, b_up, 5'b10000, b_up_counter};
      end 
      else begin
         period <= {1'b1, dir, a_dn_dir_changed, a_dn, 5'b11000, a_dn_counter};
      end
   end
   
   else if (mux == b_dn) begin  // B down
      if ((dir == 0) && ~a_up_dir_changed && (a_up_counter[21:0] > b_dn_latched[21:0])) begin
         period <= {1'b0, dir, a_up_dir_changed, a_up, 5'b01000, a_up_counter};
      end 
      else if ((dir == 1) && ~a_dn_dir_changed && (a_dn_counter[21:0] > b_dn_latched[21:0])) begin
         period <= {1'b0, dir, a_dn_dir_changed, a_dn, 5'b10000, a_dn_counter};
      end
      else begin
         period <= {1'b1, dir, b_dn_dir_changed, b_dn, 5'b11000, b_dn_latched};
      end
   end
end

endmodule


