// ==============================================================
// Vitis HLS - High-Level Synthesis from C, C++ and OpenCL v2023.1 (64-bit)
// Tool Version Limit: 2023.05
// Copyright 1986-2022 Xilinx, Inc. All Rights Reserved.
// Copyright 2022-2023 Advanced Micro Devices, Inc. All Rights Reserved.
// 
// ==============================================================
`timescale 1ns/1ps
module cow_dps_control_s_axi
#(parameter
    C_S_AXI_ADDR_WIDTH = 13,
    C_S_AXI_DATA_WIDTH = 32
)(
    input  wire                          ACLK,
    input  wire                          ARESET,
    input  wire                          ACLK_EN,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] AWADDR,
    input  wire                          AWVALID,
    output wire                          AWREADY,
    input  wire [C_S_AXI_DATA_WIDTH-1:0] WDATA,
    input  wire [C_S_AXI_DATA_WIDTH/8-1:0] WSTRB,
    input  wire                          WVALID,
    output wire                          WREADY,
    output wire [1:0]                    BRESP,
    output wire                          BVALID,
    input  wire                          BREADY,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0] ARADDR,
    input  wire                          ARVALID,
    output wire                          ARREADY,
    output wire [C_S_AXI_DATA_WIDTH-1:0] RDATA,
    output wire [1:0]                    RRESP,
    output wire                          RVALID,
    input  wire                          RREADY,
    output wire                          interrupt,
    output wire                          ap_start,
    input  wire                          ap_done,
    input  wire                          ap_ready,
    input  wire                          ap_idle,
    input  wire [63:0]                   ap_return,
    input  wire [7:0]                    privacyAmplifiedKey_address0,
    input  wire                          privacyAmplifiedKey_ce0,
    input  wire                          privacyAmplifiedKey_we0,
    input  wire [31:0]                   privacyAmplifiedKey_d0,
    input  wire [8:0]                    siftedKey_address0,
    input  wire                          siftedKey_ce0,
    input  wire                          siftedKey_we0,
    input  wire [31:0]                   siftedKey_d0,
    output wire [31:0]                   siftedKey_q0,
    input  wire [8:0]                    errorCorrectedKey_address0,
    input  wire                          errorCorrectedKey_ce0,
    input  wire                          errorCorrectedKey_we0,
    input  wire [31:0]                   errorCorrectedKey_d0
);
//------------------------Address Info-------------------
// 0x0000 : Control signals
//          bit 0  - ap_start (Read/Write/COH)
//          bit 1  - ap_done (Read/COR)
//          bit 2  - ap_idle (Read)
//          bit 3  - ap_ready (Read/COR)
//          bit 7  - auto_restart (Read/Write)
//          bit 9  - interrupt (Read)
//          others - reserved
// 0x0004 : Global Interrupt Enable Register
//          bit 0  - Global Interrupt Enable (Read/Write)
//          others - reserved
// 0x0008 : IP Interrupt Enable Register (Read/Write)
//          bit 0 - enable ap_done interrupt (Read/Write)
//          bit 1 - enable ap_ready interrupt (Read/Write)
//          others - reserved
// 0x000c : IP Interrupt Status Register (Read/TOW)
//          bit 0 - ap_done (Read/TOW)
//          bit 1 - ap_ready (Read/TOW)
//          others - reserved
// 0x0010 : Data signal of ap_return
//          bit 31~0 - ap_return[31:0] (Read)
// 0x0014 : Data signal of ap_return
//          bit 31~0 - ap_return[63:32] (Read)
// 0x0400 ~
// 0x07ff : Memory 'privacyAmplifiedKey' (256 * 32b)
//          Word n : bit [31:0] - privacyAmplifiedKey[n]
// 0x0800 ~
// 0x0fff : Memory 'siftedKey' (500 * 32b)
//          Word n : bit [31:0] - siftedKey[n]
// 0x1000 ~
// 0x17ff : Memory 'errorCorrectedKey' (500 * 32b)
//          Word n : bit [31:0] - errorCorrectedKey[n]
// (SC = Self Clear, COR = Clear on Read, TOW = Toggle on Write, COH = Clear on Handshake)

//------------------------Parameter----------------------
localparam
    ADDR_AP_CTRL                  = 13'h0000,
    ADDR_GIE                      = 13'h0004,
    ADDR_IER                      = 13'h0008,
    ADDR_ISR                      = 13'h000c,
    ADDR_AP_RETURN_0              = 13'h0010,
    ADDR_AP_RETURN_1              = 13'h0014,
    ADDR_PRIVACYAMPLIFIEDKEY_BASE = 13'h0400,
    ADDR_PRIVACYAMPLIFIEDKEY_HIGH = 13'h07ff,
    ADDR_SIFTEDKEY_BASE           = 13'h0800,
    ADDR_SIFTEDKEY_HIGH           = 13'h0fff,
    ADDR_ERRORCORRECTEDKEY_BASE   = 13'h1000,
    ADDR_ERRORCORRECTEDKEY_HIGH   = 13'h17ff,
    WRIDLE                        = 2'd0,
    WRDATA                        = 2'd1,
    WRRESP                        = 2'd2,
    WRRESET                       = 2'd3,
    RDIDLE                        = 2'd0,
    RDDATA                        = 2'd1,
    RDRESET                       = 2'd2,
    ADDR_BITS                = 13;

//------------------------Local signal-------------------
    reg  [1:0]                    wstate = WRRESET;
    reg  [1:0]                    wnext;
    reg  [ADDR_BITS-1:0]          waddr;
    wire [C_S_AXI_DATA_WIDTH-1:0] wmask;
    wire                          aw_hs;
    wire                          w_hs;
    reg  [1:0]                    rstate = RDRESET;
    reg  [1:0]                    rnext;
    reg  [C_S_AXI_DATA_WIDTH-1:0] rdata;
    wire                          ar_hs;
    wire [ADDR_BITS-1:0]          raddr;
    // internal registers
    reg                           int_ap_idle;
    reg                           int_ap_ready = 1'b0;
    wire                          task_ap_ready;
    reg                           int_ap_done = 1'b0;
    wire                          task_ap_done;
    reg                           int_task_ap_done = 1'b0;
    reg                           int_ap_start = 1'b0;
    reg                           int_interrupt = 1'b0;
    reg                           int_auto_restart = 1'b0;
    reg                           auto_restart_status = 1'b0;
    wire                          auto_restart_done;
    reg                           int_gie = 1'b0;
    reg  [1:0]                    int_ier = 2'b0;
    reg  [1:0]                    int_isr = 2'b0;
    reg  [63:0]                   int_ap_return;
    // memory signals
    wire [7:0]                    int_privacyAmplifiedKey_address0;
    wire                          int_privacyAmplifiedKey_ce0;
    wire [3:0]                    int_privacyAmplifiedKey_be0;
    wire [31:0]                   int_privacyAmplifiedKey_d0;
    wire [7:0]                    int_privacyAmplifiedKey_address1;
    wire                          int_privacyAmplifiedKey_ce1;
    wire [31:0]                   int_privacyAmplifiedKey_q1;
    reg                           int_privacyAmplifiedKey_read;
    reg                           int_privacyAmplifiedKey_write;
    wire [8:0]                    int_siftedKey_address0;
    wire                          int_siftedKey_ce0;
    wire [3:0]                    int_siftedKey_be0;
    wire [31:0]                   int_siftedKey_d0;
    wire [31:0]                   int_siftedKey_q0;
    wire [8:0]                    int_siftedKey_address1;
    wire                          int_siftedKey_ce1;
    wire                          int_siftedKey_we1;
    wire [3:0]                    int_siftedKey_be1;
    wire [31:0]                   int_siftedKey_d1;
    wire [31:0]                   int_siftedKey_q1;
    reg                           int_siftedKey_read;
    reg                           int_siftedKey_write;
    wire [8:0]                    int_errorCorrectedKey_address0;
    wire                          int_errorCorrectedKey_ce0;
    wire [3:0]                    int_errorCorrectedKey_be0;
    wire [31:0]                   int_errorCorrectedKey_d0;
    wire [8:0]                    int_errorCorrectedKey_address1;
    wire                          int_errorCorrectedKey_ce1;
    wire [31:0]                   int_errorCorrectedKey_q1;
    reg                           int_errorCorrectedKey_read;
    reg                           int_errorCorrectedKey_write;

//------------------------Instantiation------------------
// int_privacyAmplifiedKey
cow_dps_control_s_axi_ram #(
    .MEM_STYLE ( "auto" ),
    .MEM_TYPE  ( "S2P" ),
    .BYTES     ( 4 ),
    .DEPTH     ( 256 )
) int_privacyAmplifiedKey (
    .clk0      ( ACLK ),
    .address0  ( int_privacyAmplifiedKey_address0 ),
    .ce0       ( int_privacyAmplifiedKey_ce0 ),
    .we0       ( int_privacyAmplifiedKey_be0 ),
    .d0        ( int_privacyAmplifiedKey_d0 ),
    .q0        (  ),
    .clk1      ( ACLK ),
    .address1  ( int_privacyAmplifiedKey_address1 ),
    .ce1       ( int_privacyAmplifiedKey_ce1 ),
    .we1       ( {4{1'b0}} ),
    .d1        ( {32{1'b0}} ),
    .q1        ( int_privacyAmplifiedKey_q1 )
);
// int_siftedKey
cow_dps_control_s_axi_ram #(
    .MEM_STYLE ( "auto" ),
    .MEM_TYPE  ( "T2P" ),
    .BYTES     ( 4 ),
    .DEPTH     ( 500 )
) int_siftedKey (
    .clk0      ( ACLK ),
    .address0  ( int_siftedKey_address0 ),
    .ce0       ( int_siftedKey_ce0 ),
    .we0       ( int_siftedKey_be0 ),
    .d0        ( int_siftedKey_d0 ),
    .q0        ( int_siftedKey_q0 ),
    .clk1      ( ACLK ),
    .address1  ( int_siftedKey_address1 ),
    .ce1       ( int_siftedKey_ce1 ),
    .we1       ( int_siftedKey_be1 ),
    .d1        ( int_siftedKey_d1 ),
    .q1        ( int_siftedKey_q1 )
);
// int_errorCorrectedKey
cow_dps_control_s_axi_ram #(
    .MEM_STYLE ( "auto" ),
    .MEM_TYPE  ( "S2P" ),
    .BYTES     ( 4 ),
    .DEPTH     ( 500 )
) int_errorCorrectedKey (
    .clk0      ( ACLK ),
    .address0  ( int_errorCorrectedKey_address0 ),
    .ce0       ( int_errorCorrectedKey_ce0 ),
    .we0       ( int_errorCorrectedKey_be0 ),
    .d0        ( int_errorCorrectedKey_d0 ),
    .q0        (  ),
    .clk1      ( ACLK ),
    .address1  ( int_errorCorrectedKey_address1 ),
    .ce1       ( int_errorCorrectedKey_ce1 ),
    .we1       ( {4{1'b0}} ),
    .d1        ( {32{1'b0}} ),
    .q1        ( int_errorCorrectedKey_q1 )
);


//------------------------AXI write fsm------------------
assign AWREADY = (wstate == WRIDLE);
assign WREADY  = (wstate == WRDATA) && (!ar_hs);
assign BRESP   = 2'b00;  // OKAY
assign BVALID  = (wstate == WRRESP);
assign wmask   = { {8{WSTRB[3]}}, {8{WSTRB[2]}}, {8{WSTRB[1]}}, {8{WSTRB[0]}} };
assign aw_hs   = AWVALID & AWREADY;
assign w_hs    = WVALID & WREADY;

// wstate
always @(posedge ACLK) begin
    if (ARESET)
        wstate <= WRRESET;
    else if (ACLK_EN)
        wstate <= wnext;
end

// wnext
always @(*) begin
    case (wstate)
        WRIDLE:
            if (AWVALID)
                wnext = WRDATA;
            else
                wnext = WRIDLE;
        WRDATA:
            if (w_hs)
                wnext = WRRESP;
            else
                wnext = WRDATA;
        WRRESP:
            if (BREADY)
                wnext = WRIDLE;
            else
                wnext = WRRESP;
        default:
            wnext = WRIDLE;
    endcase
end

// waddr
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (aw_hs)
            waddr <= AWADDR[ADDR_BITS-1:0];
    end
end

//------------------------AXI read fsm-------------------
assign ARREADY = (rstate == RDIDLE);
assign RDATA   = rdata;
assign RRESP   = 2'b00;  // OKAY
assign RVALID  = (rstate == RDDATA) & !int_privacyAmplifiedKey_read & !int_siftedKey_read & !int_errorCorrectedKey_read;
assign ar_hs   = ARVALID & ARREADY;
assign raddr   = ARADDR[ADDR_BITS-1:0];

// rstate
always @(posedge ACLK) begin
    if (ARESET)
        rstate <= RDRESET;
    else if (ACLK_EN)
        rstate <= rnext;
end

// rnext
always @(*) begin
    case (rstate)
        RDIDLE:
            if (ARVALID)
                rnext = RDDATA;
            else
                rnext = RDIDLE;
        RDDATA:
            if (RREADY & RVALID)
                rnext = RDIDLE;
            else
                rnext = RDDATA;
        default:
            rnext = RDIDLE;
    endcase
end

// rdata
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (ar_hs) begin
            rdata <= 'b0;
            case (raddr)
                ADDR_AP_CTRL: begin
                    rdata[0] <= int_ap_start;
                    rdata[1] <= int_task_ap_done;
                    rdata[2] <= int_ap_idle;
                    rdata[3] <= int_ap_ready;
                    rdata[7] <= int_auto_restart;
                    rdata[9] <= int_interrupt;
                end
                ADDR_GIE: begin
                    rdata <= int_gie;
                end
                ADDR_IER: begin
                    rdata <= int_ier;
                end
                ADDR_ISR: begin
                    rdata <= int_isr;
                end
                ADDR_AP_RETURN_0: begin
                    rdata <= int_ap_return[31:0];
                end
                ADDR_AP_RETURN_1: begin
                    rdata <= int_ap_return[63:32];
                end
            endcase
        end
        else if (int_privacyAmplifiedKey_read) begin
            rdata <= int_privacyAmplifiedKey_q1;
        end
        else if (int_siftedKey_read) begin
            rdata <= int_siftedKey_q1;
        end
        else if (int_errorCorrectedKey_read) begin
            rdata <= int_errorCorrectedKey_q1;
        end
    end
end


//------------------------Register logic-----------------
assign interrupt         = int_interrupt;
assign ap_start          = int_ap_start;
assign task_ap_done      = (ap_done && !auto_restart_status) || auto_restart_done;
assign task_ap_ready     = ap_ready && !int_auto_restart;
assign auto_restart_done = auto_restart_status && (ap_idle && !int_ap_idle);
// int_interrupt
always @(posedge ACLK) begin
    if (ARESET)
        int_interrupt <= 1'b0;
    else if (ACLK_EN) begin
        if (int_gie && (|int_isr))
            int_interrupt <= 1'b1;
        else
            int_interrupt <= 1'b0;
    end
end

// int_ap_start
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_start <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AP_CTRL && WSTRB[0] && WDATA[0])
            int_ap_start <= 1'b1;
        else if (ap_ready)
            int_ap_start <= int_auto_restart; // clear on handshake/auto restart
    end
end

// int_ap_done
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_done <= 1'b0;
    else if (ACLK_EN) begin
            int_ap_done <= ap_done;
    end
end

// int_task_ap_done
always @(posedge ACLK) begin
    if (ARESET)
        int_task_ap_done <= 1'b0;
    else if (ACLK_EN) begin
        if (task_ap_done)
            int_task_ap_done <= 1'b1;
        else if (ar_hs && raddr == ADDR_AP_CTRL)
            int_task_ap_done <= 1'b0; // clear on read
    end
end

// int_ap_idle
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_idle <= 1'b0;
    else if (ACLK_EN) begin
            int_ap_idle <= ap_idle;
    end
end

// int_ap_ready
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_ready <= 1'b0;
    else if (ACLK_EN) begin
        if (task_ap_ready)
            int_ap_ready <= 1'b1;
        else if (ar_hs && raddr == ADDR_AP_CTRL)
            int_ap_ready <= 1'b0;
    end
end

// int_auto_restart
always @(posedge ACLK) begin
    if (ARESET)
        int_auto_restart <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_AP_CTRL && WSTRB[0])
            int_auto_restart <=  WDATA[7];
    end
end

// auto_restart_status
always @(posedge ACLK) begin
    if (ARESET)
        auto_restart_status <= 1'b0;
    else if (ACLK_EN) begin
        if (int_auto_restart)
            auto_restart_status <= 1'b1;
        else if (ap_idle)
            auto_restart_status <= 1'b0;
    end
end

// int_gie
always @(posedge ACLK) begin
    if (ARESET)
        int_gie <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_GIE && WSTRB[0])
            int_gie <= WDATA[0];
    end
end

// int_ier
always @(posedge ACLK) begin
    if (ARESET)
        int_ier <= 1'b0;
    else if (ACLK_EN) begin
        if (w_hs && waddr == ADDR_IER && WSTRB[0])
            int_ier <= WDATA[1:0];
    end
end

// int_isr[0]
always @(posedge ACLK) begin
    if (ARESET)
        int_isr[0] <= 1'b0;
    else if (ACLK_EN) begin
        if (int_ier[0] & ap_done)
            int_isr[0] <= 1'b1;
        else if (w_hs && waddr == ADDR_ISR && WSTRB[0])
            int_isr[0] <= int_isr[0] ^ WDATA[0]; // toggle on write
    end
end

// int_isr[1]
always @(posedge ACLK) begin
    if (ARESET)
        int_isr[1] <= 1'b0;
    else if (ACLK_EN) begin
        if (int_ier[1] & ap_ready)
            int_isr[1] <= 1'b1;
        else if (w_hs && waddr == ADDR_ISR && WSTRB[0])
            int_isr[1] <= int_isr[1] ^ WDATA[1]; // toggle on write
    end
end

// int_ap_return
always @(posedge ACLK) begin
    if (ARESET)
        int_ap_return <= 0;
    else if (ACLK_EN) begin
        if (ap_done)
            int_ap_return <= ap_return;
    end
end

//synthesis translate_off
always @(posedge ACLK) begin
    if (ACLK_EN) begin
        if (int_gie & ~int_isr[0] & int_ier[0] & ap_done)
            $display ("// Interrupt Monitor : interrupt for ap_done detected @ \"%0t\"", $time);
        if (int_gie & ~int_isr[1] & int_ier[1] & ap_ready)
            $display ("// Interrupt Monitor : interrupt for ap_ready detected @ \"%0t\"", $time);
    end
end
//synthesis translate_on

//------------------------Memory logic-------------------
// privacyAmplifiedKey
assign int_privacyAmplifiedKey_address0 = privacyAmplifiedKey_address0;
assign int_privacyAmplifiedKey_ce0      = privacyAmplifiedKey_ce0;
assign int_privacyAmplifiedKey_be0      = {4{privacyAmplifiedKey_we0}};
assign int_privacyAmplifiedKey_d0       = privacyAmplifiedKey_d0;
assign int_privacyAmplifiedKey_address1 = ar_hs? raddr[9:2] : waddr[9:2];
assign int_privacyAmplifiedKey_ce1      = ar_hs | (int_privacyAmplifiedKey_write & WVALID);
// siftedKey
assign int_siftedKey_address0           = siftedKey_address0;
assign int_siftedKey_ce0                = siftedKey_ce0;
assign int_siftedKey_be0                = {4{siftedKey_we0}};
assign int_siftedKey_d0                 = siftedKey_d0;
assign siftedKey_q0                     = int_siftedKey_q0;
assign int_siftedKey_address1           = ar_hs? raddr[10:2] : waddr[10:2];
assign int_siftedKey_ce1                = ar_hs | (int_siftedKey_write & WVALID);
assign int_siftedKey_we1                = int_siftedKey_write & w_hs;
assign int_siftedKey_be1                = int_siftedKey_we1 ? WSTRB : 'b0;
assign int_siftedKey_d1                 = WDATA;
// errorCorrectedKey
assign int_errorCorrectedKey_address0   = errorCorrectedKey_address0;
assign int_errorCorrectedKey_ce0        = errorCorrectedKey_ce0;
assign int_errorCorrectedKey_be0        = {4{errorCorrectedKey_we0}};
assign int_errorCorrectedKey_d0         = errorCorrectedKey_d0;
assign int_errorCorrectedKey_address1   = ar_hs? raddr[10:2] : waddr[10:2];
assign int_errorCorrectedKey_ce1        = ar_hs | (int_errorCorrectedKey_write & WVALID);
// int_privacyAmplifiedKey_read
always @(posedge ACLK) begin
    if (ARESET)
        int_privacyAmplifiedKey_read <= 1'b0;
    else if (ACLK_EN) begin
        if (ar_hs && raddr >= ADDR_PRIVACYAMPLIFIEDKEY_BASE && raddr <= ADDR_PRIVACYAMPLIFIEDKEY_HIGH)
            int_privacyAmplifiedKey_read <= 1'b1;
        else
            int_privacyAmplifiedKey_read <= 1'b0;
    end
end

// int_siftedKey_read
always @(posedge ACLK) begin
    if (ARESET)
        int_siftedKey_read <= 1'b0;
    else if (ACLK_EN) begin
        if (ar_hs && raddr >= ADDR_SIFTEDKEY_BASE && raddr <= ADDR_SIFTEDKEY_HIGH)
            int_siftedKey_read <= 1'b1;
        else
            int_siftedKey_read <= 1'b0;
    end
end

// int_siftedKey_write
always @(posedge ACLK) begin
    if (ARESET)
        int_siftedKey_write <= 1'b0;
    else if (ACLK_EN) begin
        if (aw_hs && AWADDR[ADDR_BITS-1:0] >= ADDR_SIFTEDKEY_BASE && AWADDR[ADDR_BITS-1:0] <= ADDR_SIFTEDKEY_HIGH)
            int_siftedKey_write <= 1'b1;
        else if (w_hs)
            int_siftedKey_write <= 1'b0;
    end
end

// int_errorCorrectedKey_read
always @(posedge ACLK) begin
    if (ARESET)
        int_errorCorrectedKey_read <= 1'b0;
    else if (ACLK_EN) begin
        if (ar_hs && raddr >= ADDR_ERRORCORRECTEDKEY_BASE && raddr <= ADDR_ERRORCORRECTEDKEY_HIGH)
            int_errorCorrectedKey_read <= 1'b1;
        else
            int_errorCorrectedKey_read <= 1'b0;
    end
end


endmodule


`timescale 1ns/1ps

module cow_dps_control_s_axi_ram
#(parameter
    MEM_STYLE = "auto",
    MEM_TYPE  = "S2P",
    BYTES  = 4,
    DEPTH  = 256,
    AWIDTH = log2(DEPTH)
) (
    input  wire               clk0,
    input  wire [AWIDTH-1:0]  address0,
    input  wire               ce0,
    input  wire [BYTES-1:0]   we0,
    input  wire [BYTES*8-1:0] d0,
    output reg  [BYTES*8-1:0] q0,
    input  wire               clk1,
    input  wire [AWIDTH-1:0]  address1,
    input  wire               ce1,
    input  wire [BYTES-1:0]   we1,
    input  wire [BYTES*8-1:0] d1,
    output reg  [BYTES*8-1:0] q1
);
//------------------------ Parameters -------------------
localparam
    BYTE_WIDTH = 8,
    PORT0 = (MEM_TYPE == "S2P") ? "WO" : ((MEM_TYPE == "2P") ? "RO" : "RW"),
    PORT1 = (MEM_TYPE == "S2P") ? "RO" : "RW";
//------------------------Local signal-------------------
(* ram_style = MEM_STYLE*)
reg  [BYTES*8-1:0] mem[0:DEPTH-1];
wire re0, re1;
//------------------------Task and function--------------
function integer log2;
    input integer x;
    integer n, m;
begin
    n = 1;
    m = 2;
    while (m < x) begin
        n = n + 1;
        m = m * 2;
    end
    log2 = n;
end
endfunction
//------------------------Body---------------------------
generate
    if (MEM_STYLE == "hls_ultra" && PORT0 == "RW") begin
        assign re0 = ce0 & ~|we0;
    end else begin
        assign re0 = ce0;
    end
endgenerate

generate
    if (MEM_STYLE == "hls_ultra" && PORT1 == "RW") begin
        assign re1 = ce1 & ~|we1;
    end else begin
        assign re1 = ce1;
    end
endgenerate

// read port 0
generate if (PORT0 != "WO") begin
    always @(posedge clk0) begin
        if (re0) q0 <= mem[address0];
    end
end
endgenerate

// read port 1
generate if (PORT1 != "WO") begin
    always @(posedge clk1) begin
        if (re1) q1 <= mem[address1];
    end
end
endgenerate

integer i;
// write port 0
generate if (PORT0 != "RO") begin
    always @(posedge clk0) begin
        if (ce0)
        for (i = 0; i < BYTES; i = i + 1)
            if (we0[i])
                mem[address0][i*BYTE_WIDTH +: BYTE_WIDTH] <= d0[i*BYTE_WIDTH +: BYTE_WIDTH];
    end
end
endgenerate

// write port 1
generate if (PORT1 != "RO") begin
    always @(posedge clk1) begin
        if (ce1)
        for (i = 0; i < BYTES; i = i + 1)
            if (we1[i])
                mem[address1][i*BYTE_WIDTH +: BYTE_WIDTH] <= d1[i*BYTE_WIDTH +: BYTE_WIDTH];
    end
end
endgenerate

endmodule

