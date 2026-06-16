/* verilator lint_off TIMESCALEMOD */

`timescale 1ns / 1ps

//****************
// Module: bch_decoder_tt_top - BCH(59,35,9)
// File:   bch_decoder_tt_top.v
// Description: Module dedicated to perform the BCH decoding at the retrieve phase of the HDA. Adapted to TinyTapeout constraints.
// Target board: GF180 ASIC TT run
// Author: Fco. Javier Rubio
// Last update: 2026-06-01
//****************

module bch_decoder_tt_top #(
    parameter M = 6,               // Galois Field GF(2^6)
    parameter T = 4,              // Error correction capability (t=4)
    parameter P = 1,              // Parallelism (16 bits per clock cycle)
    parameter N_CODE = 59,        // Code length (59)
    parameter N_PAD = 64,         // Padded codeword length (255 padded to 256)
    parameter KES_CYCLES = 22      // Typical cycles for BMA to solve 2t syndromes
)(
    input  wire          clk,
    input  wire          rst_n,

    input  wire          ena,   // Required by TT. Always ON when the design is powered

    // Input Interface
    input  wire          valid_in,
    input  wire          sop_in,   // Start of Packet (first 16 bits)
    input  wire          eop_in,   // End of Packet (last 16 bits)
    input  wire [P-1:0]  data_in,  // 16-bit parallel received data
    input  wire          pass_sel, // 0 = Syndromes, 1 = Chien/Correction

    // Output Interface
    output wire          valid_out,
    output wire          sop_out,
    output wire          eop_out,
    output wire [P-1:0]  data_out, // 16-bit corrected data
    output wire          uncorrectable_err // High if errors > 11
);

    // -------------------------------------------------------------------------
    // Internal Signals & Arrays (Verilog-2001)
    // -------------------------------------------------------------------------
    
    // Syndromes: 22 syndromes * 8 bits = 176 bits wide flat vector
    (* keep = "true" *) wire [(2*T*M)-1:0] syndromes_flat;
    (* keep = "true" *) wire               syndromes_ready;
    
    // Error Locator Polynomial: 12 coefficients * 8 bits = 96 bits wide flat vector
    (* keep = "true" *) wire [((T+1)*M)-1:0] locator_poly_flat;
    (* keep = "true" *) wire         locator_ready;
    (* keep = "true" *) wire         kes_fail;
    (* keep = "true" *) wire [4:0]   expected_errors_wire; // Carries L from iBMA to Chien
    (* keep = "true" *) wire         chien_uncorrectable;  // Carries the root mismatch flag back
    
    // Chien Search & Correction Mask
    (* keep = "true" *) wire [P-1:0] error_mask;
    (* keep = "true" *) wire         chien_valid;
    (* keep = "true" *) wire         chien_sop;
    (* keep = "true" *) wire         chien_eop;
    
    // -------------------------------------------------------------------------
    // Stage 1: Parallel Syndrome Calculation
    // Calculates S1 to S22 using 16-bit unrolled GF multipliers
    // -------------------------------------------------------------------------
    (* keep_hierarchy = "true" *)
    bch_syndrome_tt #(
        .M(M), .T(T), .P(P), .N_PAD(N_PAD)
    ) u_syndrome (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid_in & ~pass_sel),
        .sop_in(sop_in),
        .data_in(data_in),
        .syndromes(syndromes_flat),
        .done(syndromes_ready)
    );

    // -------------------------------------------------------------------------
    // Stage 2: Key Equation Solver (iBMA)
    // -------------------------------------------------------------------------
    (* keep_hierarchy = "true" *)
    bch_kes_ibma_tt #(
        .M(M), .T(T)
    ) u_kes (
        .clk(clk),
        .rst_n(rst_n),
        .start(syndromes_ready),
        .syndromes(syndromes_flat),
        .locator_poly(locator_poly_flat),
        .done(locator_ready_pulse), 
        .uncorrectable(kes_fail),
        .L_out(expected_errors_wire)
    );

    // -------------------------------------------------------------------------
    // Stage 3: Bit-Serial Chien Search
    // -------------------------------------------------------------------------
    (* keep_hierarchy = "true" *)
    bch_chien_tt #(
        .M(M), .T(T), .P(P), .N_CODE(N_CODE), .N_PAD(N_PAD)
    ) u_chien (
        .clk(clk),
        .rst_n(rst_n),
        .start(locator_ready_latch & pass_sel & sop_in & valid_in), 
        .valid_in(valid_in & pass_sel), 
        .locator_poly(locator_poly_flat),
        .expected_errors(expected_errors_wire), 
        .error_mask(error_mask),
        .valid_out(chien_valid),
        .sop_out(chien_sop),
        .eop_out(chien_eop),
        .uncorrectable_out(chien_uncorrectable) 
    );

    // -------------------------------------------------------------------------
    // Output Correction Logic & Latch
    // -------------------------------------------------------------------------
    assign valid_out = chien_valid & pass_sel;
    assign sop_out   = chien_sop;
    assign eop_out   = chien_eop;
    
    // LATCH the uncorrectable flag so the testbench/CPU can read it
    reg uncorrectable_latch;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) 
            uncorrectable_latch <= 1'b0;
        else if (valid_in && sop_in) // Clear the flag when a NEW packet starts
            uncorrectable_latch <= 1'b0; 
        else if (kes_fail || chien_uncorrectable) // Catch either failure
            uncorrectable_latch <= 1'b1;
    end

    // In Pass 2, the host re-transmits the noisy data on data_in.
    // We XOR it in real-time with the Chien search mask.
    assign data_out  = data_in ^ error_mask;
    
    assign uncorrectable_err = uncorrectable_latch | kes_fail | chien_uncorrectable;

    // -------------------------------------------------------------------------
    // Internal Signals & Synchronization Latches
    // -------------------------------------------------------------------------
    
    // Rename the direct wire to indicate it's a transient pulse
    wire locator_ready_pulse;
    
    // Create a persistent latch for the testbench crossing
    reg locator_ready_latch;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            locator_ready_latch <= 1'b0;
        end else if (valid_in && sop_in && !pass_sel) begin
            // Clear the latch when a NEW Pass 1 starts
            locator_ready_latch <= 1'b0;
        end else if (locator_ready_pulse) begin
            // Set the latch when the iBMA finishes, hold it indefinitely
            locator_ready_latch <= 1'b1;
        end
        
    end
    
wire _unused_pins = &{ena, 1'b0};

endmodule
