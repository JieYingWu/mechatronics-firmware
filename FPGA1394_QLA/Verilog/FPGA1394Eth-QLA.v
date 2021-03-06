/* -*- Mode: Verilog; tab-width: 4; indent-tabs-mode: nil; c-basic-offset: 4 -*-   */
/* ex: set filetype=v softtabstop=4 shiftwidth=4 tabstop=4 cindent expandtab:      */

/*******************************************************************************    
 *
 * Copyright(C) 2011-2016 ERC CISST, Johns Hopkins University.
 *
 * This is the top level module for the FPGA1394-QLA motor controller interface.
 *
 * Revision history
 *     07/15/10                        Initial revision - MfgTest
 *     10/27/11    Paul Thienphrapa    Initial revision (pault at cs.jhu.edu)
 *     02/29/12    Zihan Chen
 *     11/01/15    Peter Kazanzides    Modified for FPGA Rev 2 (Ethernet)
 */

`timescale 1ns / 1ps

// clock information
// clk1394: 49.152 MHz 
// sysclk: same as clk1394 49.152 MHz

`include "Constants.v"


module FPGA1394EthQLA
(
    // ieee 1394 phy-link interface
    input            clk1394,   // 49.152 MHz
    inout [7:0]      data,
    inout [1:0]      ctl,
    output wire      lreq,
    output wire      reset_phy,

    // ksz8851-16mll ethernet interface
    output wire      ETH_CSn,       // chip select
    output wire      ETH_RSTn,      // reset
    input wire       ETH_PME,       // power management event, unused
    output wire      ETH_CMD,       // command input for ksz8851 register IO
    output wire      ETH_8n,        // 8 or 16 bit bus
    input wire       ETH_IRQn,      // interrupt request
    output wire      ETH_RDn,
    output wire      ETH_WRn,
    inout [15:0]     SD,

    // debug I/Os
    input wire       clk25m,    // 25.0000 MHz 
    //output wire [3:0] DEBUG,

    // misc board I/Os
    input [3:0]      wenid,     // rotary switch
    inout [1:32]     IO1,
    inout [1:38]     IO2,
    output wire      LED,

    // SPI interface to PROM
    output           XCCLK,    
    input            XMISO,
    output           XMOSI,
    output           XCSn
);

    // -------------------------------------------------------------------------
    // local wires to tie the instantiated modules and I/Os
    //

    wire eth1394;               // 1: eth1394 mode 0: firewire mode
    wire lreq_trig;             // phy request trigger
    wire fw_lreq_trig;          // phy request trigger from FireWire
    wire eth_lreq_trig;         // phy request trigger from Ethernet
    wire[2:0] lreq_type;        // phy request type
    wire[2:0] fw_lreq_type;     // phy request type from FireWire
    wire[2:0] eth_lreq_type;    // phy request type from Ethernet
    wire reg_wen;               // register write signal
    wire fw_reg_wen;            // register write signal from FireWire
    wire eth_reg_wen;           // register write signal from Ethernet
    wire blk_wen;               // block write enable
    wire fw_blk_wen;            // block write enable from FireWire
    wire eth_blk_wen;           // block write enable from Ethernet
    wire blk_wstart;            // block write start
    wire fw_blk_wstart;         // block write start from FireWire
    wire eth_blk_wstart;        // block write start from Ethernet
    wire[15:0] reg_raddr;       // 16-bit reg read address
    wire[15:0] fw_reg_raddr;    // 16-bit reg read address from FireWire
    wire[15:0] eth_reg_raddr;   // 16-bit reg read address from Ethernet
    wire[15:0] reg_waddr;       // 16-bit reg write address
    wire[15:0] fw_reg_waddr;    // 16-bit reg write address from FireWire
    wire[15:0] eth_reg_waddr;   // 16-bit reg write address from Ethernet
    wire[31:0] reg_rdata;       // reg read data
    wire[31:0] reg_wdata;       // reg write data
    wire[31:0] fw_reg_wdata;    // reg write data from FireWire
    wire[31:0] eth_reg_wdata;   // reg write data from Ethernet
    wire[31:0] reg_rd[0:15];
    wire eth_read_en;           // 1 -> Ethernet is driving reg_raddr to read from board registers
    wire[5:0] node_id;          // 6-bit phy node id

//------------------------------------------------------------------------------
// hardware description
//

BUFG clksysclk(.I(clk1394), .O(sysclk));

assign reg_raddr = eth_read_en ? eth_reg_raddr : fw_reg_raddr;
assign reg_waddr = (eth_reg_wen | eth_blk_wen) ? eth_reg_waddr : fw_reg_waddr;
assign reg_wdata = (eth_reg_wen | eth_blk_wen) ? eth_reg_wdata : fw_reg_wdata;
assign reg_wen = fw_reg_wen | eth_reg_wen;
assign blk_wen = fw_blk_wen | eth_blk_wen;
assign blk_wstart = fw_blk_wstart | eth_blk_wstart;
// Following is for debugging; it is a little risky to allow Ethernet to
// access the FireWire PHY registers without some type of arbitration.
assign lreq_trig = eth_lreq_trig | fw_lreq_trig;
assign lreq_type = eth_lreq_trig ? eth_lreq_type : fw_lreq_type;

// Mux routing read data based on read address
//   See Constants.v for detail
//     addr[15:12]  main | hub | prom | prom_qla | eth

// route HubReg data to global reg_rdata
wire [31:0] reg_rdata_hub;      // reg_rdata_hub is for hub memory
wire [31:0] reg_rdata_prom;     // reg_rdata_prom is for block reads from PROM
wire [31:0] reg_rdata_prom_qla; // reads from QLA prom
wire [31:0] reg_rdata_eth;      // for eth memory access
wire [31:0] reg_rdata_fw;       // for fw memory access
assign reg_rdata = (reg_raddr[15:12]==`ADDR_HUB) ? (reg_rdata_hub) :
                  ((reg_raddr[15:12]==`ADDR_PROM) ? (reg_rdata_prom) :
                  ((reg_raddr[15:12]==`ADDR_PROM_QLA) ? (reg_rdata_prom_qla) : 
                  ((reg_raddr[15:12]==`ADDR_ETH) ? (reg_rdata_eth) :
                  ((reg_raddr[15:12]==`ADDR_FW) ? (reg_rdata_fw) :
                  ((reg_raddr[7:4]==4'd0) ? reg_rdata_chan0 : reg_rd[reg_raddr[3:0]])))));


// 1394 phy low reset, never reset
assign reset_phy = 1'b1; 

// Ethernet
assign ETH_CSn = 0;         // Always select

// The FPGA board is designed to enable the 16-bit bus. If resistor R45
// is populated, then this can be changed by driving ETH_8n low during reset.
// By default, R45 is not populated, so driving this pin has no effect.
assign ETH_8n = 1;          // 16-bit bus

`ifdef USE_CHIPSCOPE
// --------------------------------------------------------------------------
// Chipscope debug
// --------------------------------------------------------------------------
wire [35:0] control_ksz;
wire [35:0] control_fw;
//wire[35:0] control_eth;
//wire[35:0] control_brd_reg;

icon_ethernet icon_e(
    .CONTROL0(control_ksz),
    .CONTROL1(control_fw)
);

wire[7:0] eth_port_debug;
wire[3:0] dbg_state;
wire[31:0] dbg_reg_debug;
assign eth_port_debug = {1'd0, reg_wen, ETH_RSTn, ETH_CMD, ETH_RDn, 
                         ETH_WRn, ETH_IRQn, ETH_PME};
// assign eth_port_debug = {eth_cmd_req, reg_wen, ETH_RSTn,
//                          ETH_CMD, ETH_RDn, ETH_WRn, ETH_IRQn, eth_cmd_ack};
wire[5:0] dbg_state_eth;
wire[5:0] dbg_nextState_eth;
`endif

// --------------------------------------------------------------------------
// hub register module
// --------------------------------------------------------------------------

HubReg hub(
    .sysclk(sysclk),
    .reg_wen(reg_wen),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_hub),
    .reg_wdata(reg_wdata)
);


// --------------------------------------------------------------------------
// firewire modules
// --------------------------------------------------------------------------
wire eth_send_fw_req;
wire eth_send_fw_ack;
wire[6:0] eth_fwpkt_raddr;
wire[31:0] eth_fwpkt_rdata;
wire[15:0] eth_fwpkt_len;

wire eth_send_req;
wire eth_send_ack;
wire [6:0] eth_send_addr;
wire [31:0] eth_send_data;
wire [15:0] eth_send_len;
   

// phy-link interface
PhyLinkInterface phy(
    .sysclk(sysclk),         // in: global clk  
    .reset(reset),           // in: global reset
    .eth1394(eth1394),       // in: eth1394 mode
    .board_id(~wenid),       // in: board id (rotary switch)
    .node_id(node_id),       // out: phy node id
    
    .ctl_ext(ctl),           // bi: phy ctl lines
    .data_ext(data),         // bi: phy data lines
    
    .reg_wen(fw_reg_wen),       // out: reg write signal
    .blk_wen(fw_blk_wen),       // out: block write signal
    .blk_wstart(fw_blk_wstart), // out: block write is starting

    .reg_raddr(fw_reg_raddr),  // out: register address
    .reg_waddr(fw_reg_waddr),  // out: register address
    .reg_rdata(reg_rdata),     // in:  read data to external register
    .reg_wdata(fw_reg_wdata),  // out: write data to external register

    .eth_send_fw_req(eth_send_fw_req), // in: send req from eth
    .eth_send_fw_ack(eth_send_fw_ack), // out: ack send req to eth
    .eth_fwpkt_raddr(eth_fwpkt_raddr), // out: eth fw packet addr
    .eth_fwpkt_rdata(eth_fwpkt_rdata), // in: eth fw packet data
    .eth_fwpkt_len(eth_fwpkt_len),     // out: eth fw packet length

    .eth_send_req(eth_send_req),
    .eth_send_ack(eth_send_ack),
    // .eth_send_addr(reg_raddr[6:0]),
    // .eth_send_data(reg_rdata_fw),
    .eth_send_addr(eth_send_addr),
    .eth_send_data(eth_send_data),
    .eth_send_len(eth_send_len),
                     
    .lreq_trig(fw_lreq_trig),  // out: phy request trigger
    .lreq_type(fw_lreq_type),  // out: phy request type

    .ila_control(control_fw)   // in: control
);


// phy request module
PhyRequest phyreq(
    .sysclk(sysclk),          // in: global clock
    .reset(reset),            // in: reset
    .lreq(lreq),              // out: phy request line
    .trigger(lreq_trig),      // in: phy request trigger
    .rtype(lreq_type),        // in: phy request type
    .data(reg_wdata[11:0])    // in: phy request data
);

// --------------------------------------------------------------------------
// Ethernet module
// --------------------------------------------------------------------------

wire eth_init_req;
wire eth_init_ack;
wire eth_cmd_req;
wire eth_cmd_ack;
wire eth_read_valid;
wire eth_is_dma;
wire eth_is_write;
wire eth_is_word;
wire[7:0] eth_reg_addr;
wire[15:0] eth_to_chip;
wire[15:0] eth_from_chip;
wire eth_error;

wire eth_recv_enabled;  // for debugging
   
wire ksz_isIdle;
wire[31:0] Eth_Result;

KSZ8851 EthernetChip(
    .sysclk(sysclk),          // in: global clock
    .reset(reset),            // in: FPGA reset

    .ETH_RSTn(ETH_RSTn),      // out: reset to KSZ8851
    .ETH_CMD(ETH_CMD),        // out: CMD to KSZ8851 (0=data, 1=addr)
    .ETH_RDn(ETH_RDn),        // out: read strobe to KSZ8851
    .ETH_WRn(ETH_WRn),        // out: write strobe to KSZ8851
    .SD(SD),                  // inout: addr/data bus to KSZ8851

    .initReq(eth_init_req),
    .initAck(eth_init_ack),
    .cmdReq(eth_cmd_req),
    .cmdAck(eth_cmd_ack),
    .dataValid(eth_read_valid),
    .isDMA(eth_is_dma),
    .isWrite(eth_is_write),
    .isWord(eth_is_word),
    .RegAddr(eth_reg_addr),
    .DataIn(eth_to_chip),
    .DataOut(eth_from_chip),
    .eth_error(eth_error),              // error from lower layer (KSZ8851)

    .ksz_isIdle(ksz_isIdle),

    .reg_wen(fw_reg_wen),          // in: write enable from FireWire
    .reg_waddr(fw_reg_waddr),      // in: write address from FireWire
    .reg_wdata(fw_reg_wdata),      // in: data from FireWire
    .eth_data(Eth_Result[15:0])    // out: Last register read

`ifdef USE_CHIPSCOPE
    ,
    .dbg_state(dbg_state)
`endif
);


EthernetIO EthernetTransfers(
    .sysclk(sysclk),          // in: global clock
    .reset(reset),            // in: FPGA reset
    .board_id(~wenid),        // in: board id (rotary switch)
    .node_id(node_id),        // in: phy node id

    .ETH_IRQn(ETH_IRQn),      // in: interrupt request from KSZ8851
    .eth_status(Eth_Result[31:16]),
    .sendReq(eth_send_req),
    .sendAck(eth_send_ack),
    .sendAddr(eth_send_addr),
    .sendData(eth_send_data),
    .sendLen(eth_send_len),
    .ksz_isIdle(ksz_isIdle),

    .reg_rdata(reg_rdata_eth),
    .reg_raddr(reg_raddr),

    .eth_reg_rdata(reg_rdata),         //  in: reg read data
    .eth_reg_raddr(eth_reg_raddr),     // out: reg read addr
    .eth_read_en(eth_read_en),         // out: reg read enable
    .eth_reg_wdata(eth_reg_wdata),     // out: reg write data
    .eth_reg_waddr(eth_reg_waddr),     // out: reg write addr
    .eth_reg_wen(eth_reg_wen),         // out; reg write enable
    .eth_block_wen(eth_blk_wen),       // out: blk write enable
    .eth_block_wstart(eth_blk_wstart), // out: blk write start

    .initReq(eth_init_req),
    .initAck(eth_init_ack),
    .cmdReq(eth_cmd_req),
    .cmdAck(eth_cmd_ack),
    .readValid(eth_read_valid),
    .isDMA(eth_is_dma),
    .isWrite(eth_is_write),
    .isWord(eth_is_word),
    .RegAddr(eth_reg_addr),
    .WriteData(eth_to_chip),
    .ReadData(eth_from_chip),
    .eth_error(eth_error),

    .lreq_trig(eth_lreq_trig),  // out: phy request trigger
    .lreq_type(eth_lreq_type),   // out: phy request type

    .eth_send_fw_req(eth_send_fw_req), // out: req to send fw pkt
    .eth_send_fw_ack(eth_send_fw_ack), // in: ack from fw module
    .eth_fwpkt_raddr(eth_fwpkt_raddr), // out: eth fw packet addr
    .eth_fwpkt_rdata(eth_fwpkt_rdata), // in: eth fw packet data
    .eth_fwpkt_len(eth_fwpkt_len)      // out: eth fw packet len

`ifdef USE_CHIPSCOPE
    ,
    .dbg_state_eth(dbg_state_eth),
    .dbg_nextState_eth(dbg_nextState_eth),
    .dbg_reg_debug(dbg_reg_debug)
`endif
);


// --------------------------------------------------------------------------
// adcs: pot + current 
// --------------------------------------------------------------------------

// ~12 MHz clock for spi communication with the adcs
wire clkdiv2, clkadc;
ClkDiv div2clk(sysclk, clkdiv2);
defparam div2clk.width = 2;
BUFG adcclk(.I(clkdiv2), .O(clkadc));


// map 2 types of  reads to the output of the adc controller; the
//   latter will select the correct data to output based on read address
wire[31:0] reg_radc;
assign reg_rd[`OFF_ADC_DATA] = reg_radc;    // adc reads

// local wire for cur_fb(1-4) 
wire[15:0] cur_fb[1:4];

// adc controller routes conversion results according to address
CtrlAdc adc(
    .clkadc(clkadc),
    .reset(reset),
    .sclk({IO1[10],IO1[28]}),
    .conv({IO1[11],IO1[27]}),
    .miso({IO1[12:15],IO1[26],IO1[25],IO1[24],IO1[23]}),
    .reg_raddr(reg_raddr),
    .reg_rdata(reg_radc),
    .cur1(cur_fb[1]),
    .cur2(cur_fb[2]),
    .cur3(cur_fb[3]),
    .cur4(cur_fb[4])
);


// --------------------------------------------------------------------------
// dacs
// --------------------------------------------------------------------------

// local wire for dac
wire[31:0] reg_rdac;
assign reg_rd[`OFF_DAC_CTRL] = reg_rdac;   // dac reads

wire[15:0] cur_cmd[1:4];

// the dac controller manages access to the dacs
CtrlDac dac(
    .sysclk(sysclk),
    .reset(reset),
    .sclk(IO1[21]),
    .mosi(IO1[20]),
    .csel(IO1[22]),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdac),
    .reg_wdata(reg_wdata),
    .dac1(cur_cmd[1]),
    .dac2(cur_cmd[2]),
    .dac3(cur_cmd[3]),
    .dac4(cur_cmd[4])
);


// --------------------------------------------------------------------------
// encoders
// --------------------------------------------------------------------------

// fast (~1 MHz) / slow (~12 Hz) clocks to measure encoder period / frequency
wire clk_1mhz, clk_12hz;
ClkDiv divenc1(sysclk, clk_1mhz); defparam divenc1.width = 6;
ClkDiv divenc2(sysclk, clk_12hz); defparam divenc2.width = 22;

// map all types of encoder reads to the output of the encoder controller; the
//   latter will select the correct data to output based on read address
wire[31:0] reg_renc;
assign reg_rd[`OFF_ENC_LOAD] = reg_renc;    // preload
assign reg_rd[`OFF_ENC_DATA] = reg_renc;    // quadrature
assign reg_rd[`OFF_PER_DATA] = reg_renc;    // period
assign reg_rd[`OFF_FREQ_DATA] = reg_renc;   // frequency


// encoder controller: the thing that manages encoder reads and preloads
CtrlEnc enc(
    .sysclk(sysclk),
    .reset(reset),
    .enc_a({IO2[23],IO2[21],IO2[19],IO2[17]}),
    .enc_b({IO2[15],IO2[13],IO2[12],IO2[10]}),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_renc),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen)
);

// --------------------------------------------------------------------------
// digital output (DOUT) control
// --------------------------------------------------------------------------

wire[31:0] reg_rdout;
assign reg_rd[`OFF_DOUT_CTRL] = reg_rdout;

// DOUT hardware configuration
wire dout_config_valid;
wire dout_config_bidir;
wire [3:0] dout;

// IO1[16]: DOUT 4
// IO1[17]: DOUT 3
// IO1[18]: DOUT 2
// IO1[19]: DOUT 1
assign {IO1[16],IO1[17],IO1[18],IO1[19]} = (dout_config_bidir) ? (~dout) : dout;

CtrlDout cdout(
    .sysclk(sysclk),
    .reset(reset),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdout),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .dout(dout),
    .dir12(IO1[6]),
    .dir34(IO1[5]),
    .dout_cfg_valid(dout_config_valid),
    .dout_cfg_bidir(dout_config_bidir)
	 //.debug(DEBUG[3:0])
);

// --------------------------------------------------------------------------
// temperature sensors 
// --------------------------------------------------------------------------

// divide 25 MHz clock down to 400 kHz for temperature sensor readings
// TO FIX: dividing by 63 gives ~397 kHz (actual factor is 62.5)
wire clk400k_raw, clk400k;
ClkDivI divtemp(clk25m, clk400k_raw);
defparam divtemp.div = 63;
BUFG clktemp(.I(clk400k_raw), .O(clk400k));

// route temperature data into BoardRegs module for readout
wire[15:0] tempsense;

// tempsense module instantiations
Max6576 T1(
    .clk400k(clk400k), 
    .reset(reset), 
    .In(IO1[29]), 
    .Out(tempsense[15:8])
);

Max6576 T2(
    .clk400k(clk400k), 
    .reset(reset), 
    .In(IO1[30]), 
    .Out(tempsense[7:0])
);


// --------------------------------------------------------------------------
// Config prom M25P16
// --------------------------------------------------------------------------

// Route PROM status result between M25P16 and BoardRegs modules
wire[31:0] PROM_Status;
wire[31:0] PROM_Result;
   
M25P16 prom(
    .clk(sysclk),
    .reset(reset),
    .prom_cmd(reg_wdata),
    .prom_status(PROM_Status),
    .prom_result(PROM_Result),
    .prom_rdata(reg_rdata_prom),

    // address & wen 
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .blk_wstart(blk_wstart),

    // spi pins
    .prom_mosi(XMOSI),
    .prom_miso(XMISO),
    .prom_sclk(XCCLK),
    .prom_cs(XCSn)
);


// --------------------------------------------------------------------------
// QLA prom 25AA138 
//    - SPI pin connection see QLA schematics
//    - TEMP version, interface subject to future change
// --------------------------------------------------------------------------

QLA25AA128 prom_qla(
    .clk(sysclk),
    .reset(reset),
    
    // address & wen
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_prom_qla),
    .reg_wdata(reg_wdata),
        
    .reg_wen(reg_wen),
    .blk_wen(blk_wen),
    .blk_wstart(blk_wstart),

    // spi interface
    .prom_mosi(IO1[2]),
    .prom_miso(IO1[1]),
    .prom_sclk(IO1[3]),
    .prom_cs(IO1[4])
);


// --------------------------------------------------------------------------
// miscellaneous board I/Os
// --------------------------------------------------------------------------

// safety_amp_enable from SafetyCheck moudle
wire[4:1] safety_amp_disable;

// 'channel 0' is a special axis that contains various board I/Os
wire[31:0] reg_rdata_chan0;

// TO FIX: clkaux was 40m, now 25m
BoardRegs chan0(
    .sysclk(sysclk),
    .clkaux(clk25m),
    .reset(reset),
    .amp_disable({IO2[38],IO2[36],IO2[34],IO2[32]}),
    .dout(dout),
    .dout_cfg_valid(dout_config_valid),
    .dout_cfg_bidir(dout_config_bidir),
    .pwr_enable(IO1[32]),
    .relay_on(IO1[31]),
    .eth1394(eth1394),
    .enc_a({IO2[17], IO2[19], IO2[21], IO2[23]}),    // axis 4:1
    .enc_b({IO2[10], IO2[12], IO2[13], IO2[15]}),
    .enc_i({IO2[2], IO2[4], IO2[6], IO2[8]}),
    .neg_limit({IO2[26],IO2[24],IO2[25],IO2[22]}),
    .pos_limit({IO2[30],IO2[29],IO2[28],IO2[27]}),
    .home({IO2[20],IO2[18],IO2[16],IO2[14]}),
    .fault({IO2[37],IO2[35],IO2[33],IO2[31]}),
    .relay(IO2[9]),
    .mv_faultn(IO1[7]),
    .mv_good(IO2[11]),
    .v_fault(IO1[9]),
    .board_id(~wenid),
    .temp_sense(tempsense),
    .reg_raddr(reg_raddr),
    .reg_waddr(reg_waddr),
    .reg_rdata(reg_rdata_chan0),
    .reg_wdata(reg_wdata),
    .reg_wen(reg_wen),
    .prom_status(PROM_Status),
    .prom_result(PROM_Result),
    .eth_result(Eth_Result),
    .safety_amp_disable(safety_amp_disable)
`ifdef USE_CHIPSCOPE
    ,
    .reg_debug(dbg_reg_debug)
`endif
);

// ----------------------------------------------------------------------------
// safety check 
//    1. get adc feedback current & dac command current
//    2. check if cur_fb > 2 * cur_cmd
SafetyCheck safe1(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[1]),
    .dac_in(cur_cmd[1]),
    .reg_wen(reg_wen),
    .amp_disable(safety_amp_disable[1])
);

SafetyCheck safe2(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[2]),
    .dac_in(cur_cmd[2]),
    .reg_wen(reg_wen),
    .amp_disable(safety_amp_disable[2])
);

SafetyCheck safe3(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[3]),
    .dac_in(cur_cmd[3]),
    .reg_wen(reg_wen),
    .amp_disable(safety_amp_disable[3])
);

SafetyCheck safe4(
    .clk(sysclk),
    .reset(reset),
    .cur_in(cur_fb[4]),
    .dac_in(cur_cmd[4]),
    .reg_wen(reg_wen),
    .amp_disable(safety_amp_disable[4])
);


//------------------------------------------------------------------------------
// debugging, etc.
//
reg[23:0] CountC;
reg[23:0] CountI;
// TO FIX: clk40m changed to clk25m
always @(posedge(clk25m)) CountC <= CountC + 1'b1;
always @(posedge(sysclk)) CountI <= CountI + 1'b1;

assign LED = IO1[32];     // NOTE: IO1[32] pwr_enable
// assign LED = reg_led;
// assign DEBUG = { clk_1mhz, clk_12hz, CountI[23], CountC[23] }; 

// --- debug LED ----------
// reg reg_led;
// reg[4:0] reg_led_counter;
// always @(posedge(rx_active) or posedge(clk_12hz)) begin
//     if (rx_active == 1'b1) begin
//         reg_led_counter <= 0;
//         reg_led <= 1'b1;
//     end
//     else if (reg_led_counter <= 5'd16) begin
//         reg_led_counter <= reg_led_counter + 1'b1;
//         reg_led <= 1'b1;
//     end
//     else begin
//         reg_led <= 1'b0;
//     end
// end


//------------------------------------------------------------------------------
// LEDs on QLA 
CtrlLED qla_led(
    .sysclk(sysclk),
    .clk_12hz(clk_12hz),
    .reset(reset),
    .led1_grn(IO2[1]),
    .led1_red(IO2[3]),
    .led2_grn(IO2[5]),
    .led2_red(IO2[7])
);


`ifdef USE_CHIPSCOPE


wire[31:0] dbg_eth_ksz;
assign dbg_eth_ksz = {26'd0, eth_cmd_req, eth_cmd_ack, eth_read_valid, eth_is_dma, 
                      eth_is_word, eth_error};

// ----------------------------
// Chipscope 
// ----------------------------
ila_eth_chip ila_ec(
    .CONTROL(control_ksz),
    .CLK(sysclk),
    .TRIG0(eth_port_debug),    // 8-bit
    .TRIG1(SD),                // 16-bit
    .TRIG2(dbg_state),         // 4-bit
    .TRIG3(reg_waddr),         // 16-bit
    .TRIG4(reg_wdata),         // 32-bit
    // .TRIG5(dbg_reg_debug),     // 32-bit
    .TRIG5(dbg_eth_ksz),
    .TRIG6(dbg_state_eth),     // 6-bit
    .TRIG7(dbg_nextState_eth), // 6-bit
    .TRIG8(eth_to_chip),       // 16-bit
    .TRIG9(eth_from_chip)      // 16-bit
);
`endif

endmodule
