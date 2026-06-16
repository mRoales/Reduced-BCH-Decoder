/* verilator lint_off TIMESCALEMOD */

`timescale 1ns / 1ps

//****************
// Module: bch_chien_tt - iBMA for TinyTapeout
// File:   bch_chien_tt.v
// Description: Module dedicated to perform the bit-serial Chien search for BCH decoding.
// Target board: GF180 ASIC TT run
// Author: Fco. Javier Rubio (Cleaned for ASIC Synthesis)
// Last update: 2026-06-16
//****************

module bch_chien_tt #(parameter M=6, T=4, P=1, N_CODE = 59, N_PAD = 64)(
    input  wire clk, rst_n, start, valid_in,
    input  wire [((T+1)*M)-1:0] locator_poly,
    input  wire [4:0]   expected_errors, 
    output wire [P-1:0] error_mask,
    output wire valid_out, sop_out, eop_out, 
    output reg  uncorrectable_out
);
    // -------------------------------------------------------------------------
    // 1. Internal Registers & Bounds
    // -------------------------------------------------------------------------
    localparam [5:0] MAX_CYCLES = (N_PAD / P) - 1; // 63
    localparam PAD_BITS   = N_PAD - N_CODE;  // 5

    reg [M-1:0] chien_reg [0:T]; 
    reg [5:0]   cycle_cnt;       
    reg         busy;            

    integer i;
    wire [M-1:0] locator_poly_2d [0:T];
    
    genvar j;
    generate
        for (j = 0; j <= T; j = j + 1) begin : unpack_loc
            assign locator_poly_2d[j] = locator_poly[((j+1)*M)-1 : j*M];
        end
    endgenerate

    assign valid_out = (busy | start) & valid_in;
    assign sop_out   = busy & valid_in & (cycle_cnt == 6'd0);
    assign eop_out   = busy & valid_in & (cycle_cnt == MAX_CYCLES);

    reg [4:0] root_count;
    reg [4:0] cycle_roots;
    integer bit_idx;

    // Combinational root tally for the current cycle
    always @(*) begin
        cycle_roots = 5'd0;
        for (bit_idx = 0; bit_idx < P; bit_idx = bit_idx + 1) begin
            if (error_mask[bit_idx]) begin
                cycle_roots = cycle_roots + 1'b1;
            end
        end
    end

    // -------------------------------------------------------------------------
    // 2. ASIC-Compliant Combinational Multiplier Network
    // -------------------------------------------------------------------------
    // We compute the Galois Field stepping functions continuously onto wires.
    // This removes combinational logic from the clock edge, resolving ABC errors.
    wire [M-1:0] next_chien_1 = update_mult_1(chien_reg[1]);
    wire [M-1:0] next_chien_2 = update_mult_2(chien_reg[2]);
    wire [M-1:0] next_chien_3 = update_mult_3(chien_reg[3]);
    wire [M-1:0] next_chien_4 = update_mult_4(chien_reg[4]);

    // -------------------------------------------------------------------------
    // 3. Main FSM: Clean Synchronous Sequential Block
    // -------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy              <= 1'b0;
            cycle_cnt         <= 6'd0;
            root_count        <= 5'd0;
            uncorrectable_out <= 1'b0;
            for (i = 0; i <= T; i = i + 1) chien_reg[i] <= {M{1'b0}};
            
        end else begin
            if (start) begin
                busy              <= 1'b1;
                cycle_cnt         <= 6'd0;
                root_count        <= 5'd0;
                uncorrectable_out <= 1'b0;
                
                chien_reg[0] <= locator_poly_2d[0];
                chien_reg[1] <= locator_poly_2d[1];
                chien_reg[2] <= locator_poly_2d[2];
                chien_reg[3] <= locator_poly_2d[3];
                chien_reg[4] <= locator_poly_2d[4];
                
            end else if (busy) begin
                
                // --- PHASE 1: ACTIVE UPDATE ---
                if (valid_in) begin
                    cycle_cnt  <= cycle_cnt + 1'b1;
                    root_count <= root_count + cycle_roots; 

                    // Telemetry $display removed to prevent unmapped cell errors in synthesis.
                    
                    chien_reg[0] <= chien_reg[0]; 
                    chien_reg[1] <= next_chien_1; // Safely register pre-calculated wires
                    chien_reg[2] <= next_chien_2;
                    chien_reg[3] <= next_chien_3;
                    chien_reg[4] <= next_chien_4;
                end
                
                // --- PHASE 2: DECOUPLED TEARDOWN ---
                if (cycle_cnt == MAX_CYCLES && !valid_in) begin
                    busy <= 1'b0;
                    if ((root_count + cycle_roots) != expected_errors)
                        uncorrectable_out <= 1'b1;
                end
                
            end
        end 
    end

    // -------------------------------------------------------------------------
    // 4. Parallel Combinational Evaluation
    // -------------------------------------------------------------------------
    wire [M-1:0] eval_sum;
    assign eval_sum  = eval_pos_0(chien_reg[0], chien_reg[1], chien_reg[2], chien_reg[3], chien_reg[4]);

    genvar k;
    generate
        for (k = 0; k < P; k = k + 1) begin : gen_error_mask
            // CRITICAL ASIC FIX: Removed implicit multiplication (cycle_cnt * P). 
            // Since P=1, we simplify it directly to cycle_cnt to avoid hardware multipliers.
            assign error_mask[k] = ((eval_sum == {M{1'b0}}) && ((cycle_cnt + k) >= (PAD_BITS - 1))) ? 1'b1 : 1'b0;
        end
    endgenerate

    // -------------------------------------------------------------------------
    // 5. Pure Logic Combinational Functions
    // -------------------------------------------------------------------------
    function [5:0] update_mult_1;
        input [5:0] d;
        begin
            update_mult_1[0] = d[5];
            update_mult_1[1] = d[0] ^ d[5];
            update_mult_1[2] = d[1];
            update_mult_1[3] = d[2];
            update_mult_1[4] = d[3];
            update_mult_1[5] = d[4];
        end
    endfunction

    function [5:0] update_mult_2;
        input [5:0] d;
        begin
            update_mult_2[0] = d[4];
            update_mult_2[1] = d[4] ^ d[5];
            update_mult_2[2] = d[0] ^ d[5];
            update_mult_2[3] = d[1];
            update_mult_2[4] = d[2];
            update_mult_2[5] = d[3];
        end
    endfunction

    function [5:0] update_mult_3;
        input [5:0] d;
        begin
            update_mult_3[0] = d[3];
            update_mult_3[1] = d[3] ^ d[4];
            update_mult_3[2] = d[4] ^ d[5];
            update_mult_3[3] = d[0] ^ d[5];
            update_mult_3[4] = d[1];
            update_mult_3[5] = d[2];
        end
    endfunction

    function [5:0] update_mult_4;
        input [5:0] d;
        begin
            update_mult_4[0] = d[2];
            update_mult_4[1] = d[2] ^ d[3];
            update_mult_4[2] = d[3] ^ d[4];
            update_mult_4[3] = d[4] ^ d[5];
            update_mult_4[4] = d[0] ^ d[5];
            update_mult_4[5] = d[1];
        end
    endfunction

    function [5:0] eval_pos_0;
        input [5:0] r0, r1, r2, r3, r4;
        begin
            eval_pos_0 = r0 ^ r1 ^ r2 ^ r3 ^ r4;
        end
    endfunction

endmodule
