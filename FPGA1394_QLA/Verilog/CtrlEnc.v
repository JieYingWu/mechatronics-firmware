/*******************************************************************************
 *
 * Copyright(C) 2011-2017 ERC CISST, Johns Hopkins University.
 *
 * This module controls access to the encoder modules by selecting the data to 
 * output based on the read address, and by handling preload write commands to
 * the quadrature encoders.
 *
 * Revision history
 *     11/16/11    Paul Thienphrapa    Initial revision
 *     10/27/13    Zihan Chen          Minor, set preload to 24'h800000
 *     04/07/17    Jie Ying Wu         Minor change to clock frequency for velocity estimation
 */

// device register file offset
`include "Constants.v" 

module CtrlEnc(
    input  wire sysclk,           // global clock and reset signals
    input  wire reset,            // global reset
    input  wire[1:4] enc_a,       // set of quadrature encoder inputs
    input  wire[1:4] enc_b,
    input  wire[15:0] reg_raddr,  // register file read addr from outside 
    input  wire[15:0] reg_waddr,  // register file write addr from outside 
    output wire[31:0] reg_rdata,  // outgoing register file data
    input  wire[31:0] reg_wdata,  // incoming register file data
    input  wire reg_wen           // write enable signal from outside world
);    
    
    // -------------------------------------------------------------------------
    // local wires and registerscmake
    //

    // encoder signals, etc.
    reg[1:4] set_enc;              // used to raise enc preload flag
    wire[1:4] enc_a_filt;          // filtered encoder a line
    wire[1:4] enc_b_filt;          // filtered encoder b line
    wire[1:6] dir;                 // encoder transition direction

    // data buses to/from encoder modules
    reg[23:0]  preload[1:4];      // to encoder counter preload register
    wire[24:0] quad_data[1:4];    // transition count FROM encoder (ovf msb)
    wire[31:0] perd_data[1:4];    // encoder period measurement    
    wire[31:0] freq_data[1:4];    // encoder frequency measurement
    
    // clk for vel measurement     
    wire clk_fast;   // 3.072 MHz velocity measure encoder period
    wire clk_slow;   // ~12 Hz  velocity measure encoder tick frequency 

//------------------------------------------------------------------------------
// hardware description
//

// filters for raw encoder lines a and b (all channels, 1-4)
Debounce filter_a1(sysclk, reset, enc_a[1], enc_a_filt[1]);
Debounce filter_b1(sysclk, reset, enc_b[1], enc_b_filt[1]);
Debounce filter_a2(sysclk, reset, enc_a[2], enc_a_filt[2]);
Debounce filter_b2(sysclk, reset, enc_b[2], enc_b_filt[2]);
Debounce filter_a3(sysclk, reset, enc_a[3], enc_a_filt[3]);
Debounce filter_b3(sysclk, reset, enc_b[3], enc_b_filt[3]);
Debounce filter_a4(sysclk, reset, enc_a[4], enc_a_filt[4]);
Debounce filter_b4(sysclk, reset, enc_b[4], enc_b_filt[4]);

// modules for encoder counts, period, and frequency measurements
// position quad encoder 
EncQuad EncQuad1(sysclk, reset, enc_a_filt[1], enc_b_filt[1], set_enc[1], preload[1], quad_data[1], dir[1]);
EncQuad EncQuad2(sysclk, reset, enc_a_filt[2], enc_b_filt[2], set_enc[2], preload[2], quad_data[2], dir[2]);
EncQuad EncQuad3(sysclk, reset, enc_a_filt[3], enc_b_filt[3], set_enc[3], preload[3], quad_data[3], dir[3]);
EncQuad EncQuad4(sysclk, reset, enc_a_filt[4], enc_b_filt[4], set_enc[4], preload[4], quad_data[4], dir[4]);

// modules generate fast & slow clock 
ClkDiv divenc1(sysclk, clk_fast); defparam divenc1.width = 4; 
ClkDiv divenc2(sysclk, clk_slow); defparam divenc2.width = 22;

// velocity period (4/dT method)
// quad update version
EncPeriodQuad EncPerd1(sysclk, clk_fast, reset, enc_a_filt[1], enc_b_filt[1], dir[1], perd_data[1]);
EncPeriodQuad EncPerd2(sysclk, clk_fast, reset, enc_a_filt[2], enc_b_filt[2], dir[2], perd_data[2]);
EncPeriodQuad EncPerd3(sysclk, clk_fast, reset, enc_a_filt[3], enc_b_filt[3], dir[3], perd_data[3]);
EncPeriodQuad EncPerd4(sysclk, clk_fast, reset, enc_a_filt[4], enc_b_filt[4], dir[4], perd_data[4]);

reg[0:5] enc_a_low_freq[1:4];
reg[0:5] enc_b_low_freq[1:4];

always @(posedge enc_a_filt[1]) begin
   enc_a_low_freq[1] <= enc_a_low_freq[1] + (dir[1] ? 1 : -1);
end
always @(posedge enc_a_filt[2]) begin
   enc_a_low_freq[2] <= enc_a_low_freq[2] + (dir[2] ? 1 : -1);
end
always @(posedge enc_a_filt[3]) begin
   enc_a_low_freq[3] <= enc_a_low_freq[3] + (dir[3] ? 1 : -1);
end
always @(posedge enc_a_filt[4]) begin
   enc_a_low_freq[4] <= enc_a_low_freq[4] + (dir[4] ? 1 : -1);
end
always @(posedge enc_b_filt[1]) begin
   enc_b_low_freq[1] <= enc_b_low_freq[1] + (dir[1] ? 1 : -1);
end
always @(posedge enc_b_filt[2]) begin
   enc_b_low_freq[2] <= enc_b_low_freq[2] + (dir[2] ? 1 : -1);
end
always @(posedge enc_b_filt[3]) begin
   enc_b_low_freq[3] <= enc_b_low_freq[3] + (dir[3] ? 1 : -1);
end
always @(posedge enc_b_filt[4]) begin
   enc_b_low_freq[4] <= enc_b_low_freq[4] + (dir[4] ? 1 : -1);
end

EncPeriodQuad EncPerd5(sysclk, clk_fast, reset, enc_a_low_freq[1][0], enc_b_low_freq[1][0], dir[1], freq_data[1]);
EncPeriodQuad EncPerd6(sysclk, clk_fast, reset, enc_a_low_freq[2][0], enc_b_low_freq[2][0], dir[2], freq_data[2]);
EncPeriodQuad EncPerd7(sysclk, clk_fast, reset, enc_a_low_freq[3][0], enc_b_low_freq[3][0], dir[3], freq_data[3]);
EncPeriodQuad EncPerd8(sysclk, clk_fast, reset, enc_a_low_freq[4][0], enc_b_low_freq[4][0], dir[4], freq_data[4]);

// velocity frequency counting 
// NOTE: for fast motion, not used in dvrk 
//EncFreq EncFreq1(sysclk, clk_slow, reset, enc_b_filt[1], dir[1], freq_data[1]);
//EncFreq EncFreq2(sysclk, clk_slow, reset, enc_b_filt[2], dir[2], freq_data[2]);
//EncFreq EncFreq3(sysclk, clk_slow, reset, enc_b_filt[3], dir[3], freq_data[3]);
//EncFreq EncFreq4(sysclk, clk_slow, reset, enc_b_filt[4], dir[4], freq_data[4]);


//------------------------------------------------------------------------------
// register file interface to outside world
//

// output selected read register
assign reg_rdata = (reg_raddr[3:0]==`OFF_ENC_LOAD) ? (preload[reg_raddr[7:4]]) :
                  ((reg_raddr[3:0]==`OFF_ENC_DATA) ? (quad_data[reg_raddr[7:4]]) :
                  ((reg_raddr[3:0]==`OFF_PER_DATA) ? (perd_data[reg_raddr[7:4]]) : 
                  ((reg_raddr[3:0]==`OFF_FREQ_DATA) ? (freq_data[reg_raddr[7:4]]) : 32'd0)));


// write selected preload register
// set_enc: create a pulse when encoder preload is written
always @(posedge(sysclk) or negedge(reset))
begin
    if (reset == 0) begin
        set_enc <= 4'h0;
        preload[1] <= 24'h800000;    // set to half value
        preload[2] <= 24'h800000;
        preload[3] <= 24'h800000;
        preload[4] <= 24'h800000;
    end
    else if (reg_wen && reg_waddr[15:12]==`ADDR_MAIN && reg_waddr[3:0]==`OFF_ENC_LOAD)
    begin
        preload[reg_waddr[7:4]] <= reg_wdata[23:0]; 
        set_enc[reg_waddr[7:4]] <= 1'b1;
    end
    else 
        set_enc <= 4'h0;
end

endmodule
