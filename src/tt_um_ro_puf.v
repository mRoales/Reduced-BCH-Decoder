/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_ro_puf(
    input  wire [7:0] ui_in,    // Dedicated inputs from Tiny Tapeout
    output wire [7:0] uo_out,   // Dedicated outputs to Tiny Tapeout
    input  wire [7:0] uio_in,   // Bidirectional pins (Input path) - Unused
    output wire [7:0] uio_out,  // Bidirectional pins (Output path) - Unused
    output wire [7:0] uio_oe,   // Bidirectional pin direction control (0=Input, 1=Output)
    input  wire       ena,      // Design power enablement signal
    input  wire       clk,      // Main system clock
    input  wire       rst_n     // Active-low asynchronous reset
);

    localparam PUF_LENGTH_CONFIG = 2;    // nº of programmable RO used in the bank
    localparam PUF_LENGTH        = 4;    // Num total ROs
    localparam MUX_LENGTH        = 4;    // nº of total RO used in the bank
    localparam MUX_SZ            = 4;    // nº of RO inputs of the Muxs
    localparam NO_PUF_STAGE      = 8;    // nº of programmable stages
    localparam CNT_BIT_SIZE      = 16;   // Size of the counter
    localparam CONT_MAX          = 8063; // Hardcoded Threshold Value for Tiny tapeout
    localparam NO_COUNTER        = 2;    // Number of counters to be instantiated

    wire [$clog2(MUX_LENGTH)-1:0]    sel_mux_0 = ui_in[$clog2(MUX_LENGTH)-1:0]; // [1:0] -> 2 bits
    wire [$clog2(MUX_LENGTH)-1:0]    sel_mux_1 = ui_in[2*$clog2(MUX_LENGTH)-1:$clog2(MUX_LENGTH)]; // [3:2] -> 2 bits
    wire [$clog2(NO_PUF_STAGE)-1:0]  n_inv      = ui_in[$clog2(NO_PUF_STAGE)+ 2*$clog2(MUX_LENGTH)-1:2*$clog2(MUX_LENGTH)]; // [6:4] -> 3 bits

    wire                             puf_enable = ui_in[7];   // Último bit disponible de ui_in
    
    wire                             tx_ready   = uio_in[0];  // uio_oe[0]=1'b0
    wire                             op_mode    = uio_in[1];  // uio_oe[1]=1'b0

    
    wire [MUX_LENGTH-1:0]            debug_ro;
    wire [NO_COUNTER-1:0]            valid_out;
    wire [NO_COUNTER-1:0]            cnt_data_out;
    wire [NO_COUNTER-1:0]            debug_done_out;
    
    assign uo_out[1+MUX_LENGTH:MUX_LENGTH] = valid_out;                     // Mapea o_valid
    assign uo_out[3+MUX_LENGTH:2+MUX_LENGTH] = cnt_data_out;                  // Mapea o_cnt_data
    assign uo_out[MUX_LENGTH-1:0] = debug_ro[MUX_LENGTH-1:0];
    
    assign uio_out[7:6] = debug_done_out[NO_COUNTER-1:0];                // Mapea o_debug_done

    assign uio_oe = {2'b11, 4'b0000, 2'b00}; 
    
 puf_top #(
        .PUF_LENGTH_CONFIG ( PUF_LENGTH_CONFIG ),
        .PUF_LENGTH        ( PUF_LENGTH        ),
        .MUX_LENGTH        ( MUX_LENGTH        ),
        .MUX_SZ            ( MUX_SZ            ),
        .NO_PUF_STAGE      ( NO_PUF_STAGE      ),
        .CNT_BIT_SIZE      ( CNT_BIT_SIZE      ),
        .CONT_MAX          ( CONT_MAX          ),
        .NO_COUNTER        ( NO_COUNTER        )
    ) puf_instance (
        .clk          ( clk            ),
        .rst_n        ( rst_n          ),
        .i_sel_mux_0  ( sel_mux_0      ),
        .i_sel_mux_1  ( sel_mux_1      ),
        .i_n_inv      ( n_inv          ),
        .i_enable     ( puf_enable     ),
        .i_tx_ready   ( tx_ready       ),
        .i_op_mode    ( op_mode        ),
        .o_puf_ro     ( debug_ro       ),
        .o_valid      ( valid_out      ),
        .o_cnt_data   ( cnt_data_out   ),
        .o_debug_done ( debug_done_out )
    );
  // ---------------------------------------------------------------------
  // 5. LINTER WARNING PREVENTION (Handling unused input ports)
  // ---------------------------------------------------------------------
  // We feed the remaining ui_in bits and the uio_in bus into a dummy reduction AND gate.
  // This informs Verilator that we are intentionally aware of these unused signals.
    wire _unused = &{uio_in[5:2], ena, 1'b0};

endmodule
