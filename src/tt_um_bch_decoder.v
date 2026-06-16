/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_bch_decoder(
    input  wire [7:0] ui_in,    // Dedicated inputs from Tiny Tapeout
    output wire [7:0] uo_out,   // Dedicated outputs to Tiny Tapeout
    input  wire [7:0] uio_in,   // Bidirectional pins (Input path) - Unused
    output wire [7:0] uio_out,  // Bidirectional pins (Output path) - Unused
    output wire [7:0] uio_oe,   // Bidirectional pin direction control (0=Input, 1=Output)
    input  wire       ena,      // Design power enablement signal
    input  wire       clk,      // Main system clock
    input  wire       rst_n     // Active-low asynchronous reset
);

  // ---------------------------------------------------------------------
  // 1. INPUT MAPPING (Distributing individual bits of ui_in)
  // ---------------------------------------------------------------------
  wire valid_in_wire = ui_in[0];
  wire sop_in_wire   = ui_in[1];
  wire eop_in_wire   = ui_in[2];
  wire data_in_wire  = ui_in[3]; // <--- Your serial input data bit (1 bit)
  wire pass_sel_wire = ui_in[4];

  // ---------------------------------------------------------------------
  // 2. BIDIRECTIONAL PINS CONFIGURATION (uio)
  // ---------------------------------------------------------------------
  // Since these pins are not needed, they are driven to 0 and configured 
  // as inputs (uio_oe = 0) to avoid any floating states or power consumption.
  assign uio_out = 8'b00000000;
  assign uio_oe  = 8'b00000000; 

  // ---------------------------------------------------------------------
  // 3. OUTPUT MAPPING (Connecting internal signals to the uo_out bus)
  // ---------------------------------------------------------------------
  wire valid_out_wire;
  wire sop_out_wire;
  wire eop_out_wire;
  wire data_out_wire; // <--- Your serial output data bit (1 bit)
  wire uncorrectable_err_wire;

  // Assigning individual bits to the dedicated output pins
  assign uo_out[0] = valid_out_wire;
  assign uo_out[1] = sop_out_wire;
  assign uo_out[2] = eop_out_wire;
  assign uo_out[3] = data_out_wire;
  assign uo_out[4] = uncorrectable_err_wire;
  
  // Driving the remaining unused output pins to a safe 0 state
  assign uo_out[7:5] = 3'b000;

  // ---------------------------------------------------------------------
  // 4. TOP MODULE INSTANTIATION (Your BCH Decoder)
  // ---------------------------------------------------------------------
  bch_decoder_tt_top #(
      .M(6),
      .T(4),
      .P(1), // Keeping your original bit-serial parallelism configuration
      .N_CODE(59),
      .N_PAD(64),
      .KES_CYCLES(22)
  ) my_bch_decoder_instance (
      .clk               (clk),
      .rst_n             (rst_n),
      .ena               (ena),
      
      // Inputs
      .valid_in          (valid_in_wire),
      .sop_in            (sop_in_wire),
      .eop_in            (eop_in_wire),
      .data_in           (data_in_wire), // Feeding the single bit directly
      .pass_sel          (pass_sel_wire),
      
      // Outputs
      .valid_out         (valid_out_wire),
      .sop_out           (sop_out_wire),
      .eop_out           (eop_out_wire),
      .data_out          (data_out_wire), // Receiving the single bit directly
      .uncorrectable_err (uncorrectable_err_wire)
  );

  // ---------------------------------------------------------------------
  // 5. LINTER WARNING PREVENTION (Handling unused input ports)
  // ---------------------------------------------------------------------
  // We feed the remaining ui_in bits and the uio_in bus into a dummy reduction AND gate.
  // This informs Verilator that we are intentionally aware of these unused signals.
  wire _unused = &{ui_in[7:5], uio_in, 1'b0};

endmodule
