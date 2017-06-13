/*******************************************************************************
 *
 * Copyright(C) 2008-2012 ERC CISST, Johns Hopkins University.
 *
 * This module measures the encoder pulse period by counting the edges of a
 * fixed fast clock (~1 MHz) between encoder pulses.  Each new encoder pulse
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
 *     03/17/14    Peter Kazanzides    Update data every ticks (dP = 4)
 *	    04/07/17    Jie Ying Wu  	      Return only larger of cnter or cnter_latch
 */

// ---------- Peter ------------------
module EncPeriod(
   input wire clk_fast,      // count this clock between encoder ticks
   input wire reset,         // global reset signal
   input wire ticks,         // encoder transition signal
   input wire dir,           // direction of the ticks
   output wire ticks_en,     // edge signal 
   output wire[31:0] latched, // latched counter from last encoder event
   output wire[31:0] count    // number clk_fast periods per tick
);

    // local registers 
    reg[21:0] cnter;        // cnter current value
    reg[21:0] cnter_latch;  // latched cnter value

    // overflow value for unsigned 22-bit number
    parameter overflow = 22'h3FFFFF;


//------------------------------------------------------------------------------
// hardware description
//

// convert ticks to pulse
reg dir_r;      // dir start 
reg dir_changed; //changed direction in this cycle
reg ticks_r;    // previous ticks
assign ticks_en = ticks & (~ticks_r);

assign latched = {1, dir, dir_changed, 7'h00, cnter_latch};
assign count = {0, dir, dir_changed, 7'h00, cnter};

// latch cnter value 
always @(posedge ticks_en or negedge reset)
begin
    if (reset == 0) begin
        cnter_latch <= 22'd0;
    end
    else begin
        cnter_latch <= cnter;
    end
end

// free-running counter 
always @(posedge clk_fast or posedge ticks_en or negedge reset) 
begin
	if (reset == 0 || ticks_en) begin
		cnter <= 22'd0;
      dir_changed <= 0;
	end
   else if (dir != dir_r) begin
      cnter <= overflow;
      dir_changed <= 1;
   end
   else if (cnter != overflow) begin
      cnter <= cnter + 1;   
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
    wire[31:0] a_up_latched;   // channel a up data 
    wire[31:0] a_dn_latched;   // channel a dn data
    wire[31:0] b_up_latched;   // channel b up data
    wire[31:0] b_dn_latched;   // channel b dn latched_value
    wire[31:0] a_up_counter;   // channel a up free running counter
    wire[31:0] a_dn_counter;   // channel a dn free running counter
    wire[31:0] b_up_counter;   // channel b up free running counter
    wire[31:0] b_dn_counter;   // channel b dn free running counter

//------------------------------------------------------------------------------
// hardware description
//
EncPeriod EncPerUpA(clk_fast, reset,  a, dir, a_up_tick, a_up_latched, a_up_counter);
EncPeriod EncPerDnA(clk_fast, reset, ~a, dir, a_dn_tick, a_dn_latched, a_dn_counter);
EncPeriod EncPerUpB(clk_fast, reset,  b, dir, b_up_tick, b_up_latched, b_up_counter);
EncPeriod EncPerDnB(clk_fast, reset, ~b, dir, b_dn_tick, b_dn_latched, b_dn_counter);

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
// 1) It is from the free running counter
// 2) There has been no direction change in its last encoder cycle
// 3) The value is bigger than the current one
always @(posedge clk_fast or negedge reset) begin
   if (reset == 0) begin
      period <= 32'd0;
   end
   
   else if (mux == a_up) begin  // A up
      if ((dir == 0) && (~b_up_counter[29]) && (b_up_counter[21:0] > a_up_latched[21:0])) begin
         period <= {b_up_counter[31:29], b_up, 2'b01, b_up_counter[24:0]};
      end 
      else if ((dir == 1) && (~b_dn_counter[29]) && (b_dn_counter[21:0] > a_up_latched[21:0])) begin
         period <= {b_dn_counter[31:29], b_dn, 2'b10, b_dn_counter[24:0]};
      end 
      else begin
         period <= {a_up_latched[31:29], a_up, 2'b11, a_up_latched[24:0]};
      end
   end
   
   else if (mux == b_up) begin  // B up
      if ((dir == 0) && (~a_dn_latched[29]) && (a_dn_counter[21:0] > b_up_latched[21:0])) begin
         period <= {a_dn_counter[31:29], a_dn, 2'b01, a_dn_counter[24:0]};
      end 
      else if ((dir == 1) && (~a_up_counter[29] )&& (a_up_counter[21:0] > b_up_latched[21:0])) begin
         period <= {a_up_counter[31:29], a_up, 2'b10, a_up_counter[24:0]};
      end 
      else begin
         period <= {b_up_latched[31:29], b_up, 2'b11, b_up_latched[24:0]};
      end
   end
   
   else if (mux == a_dn) begin  // A down
      if ((dir == 0) && (~b_dn_latched[29]) && (b_dn_counter[21:0] > a_dn_latched[21:0])) begin
         period <= {b_dn_counter[31:29], b_dn, 2'b01, b_dn_counter[24:0]};
      end 
      else if ((dir == 1) && (~b_up_counter[29]) && (b_up_counter[21:0] > a_dn_latched[21:0])) begin
         period <= {b_up_counter[31:29], b_up, 2'b10, b_up_counter[24:0]};
      end 
      else begin
         period <= {a_dn_counter[31:29], a_dn, 2'b11, a_dn_counter[24:0]};
      end
   end
   
   else if (mux == b_dn) begin  // B down
      if ((dir == 0) && (~a_up_counter[29]) && (a_up_counter[21:0] > b_dn_latched[21:0])) begin
         period <= {a_up_counter[31:29], a_up, 2'b01, a_up_counter[24:0]};
      end 
      else if ((dir == 1) && (~a_dn_counter[29]) && (a_dn_counter[21:0] > b_dn_latched[21:0])) begin
         period <= {a_dn_counter[31:29], a_dn, 2'b10, a_dn_counter[24:0]};
      end
      else begin
         period <= {b_dn_latched[31:29], b_dn, 2'b11, b_dn_latched[24:0]};
      end
   end
end

endmodule


